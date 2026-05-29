import {
  App,
  MarkdownView,
  Modal,
  Notice,
  Plugin,
  TFile,
} from "obsidian";
import { Buffer } from "buffer";
import { DEFAULT_COMPANION_URL_SCHEME, DEFAULT_SETTINGS, DEFAULT_SECRET_NAME, SESSION_FAILURE_PREFIX, TOKEN_TRIGGER } from "./constants";
import { replacePlaceholderInEditor, getEditorFile, ensureMarkdownFile, editorEndsWithTrigger } from "./note-editor";
import { NotePasteReceiver, type ReceiverDelegate, type UploadAuthorization } from "./receiver";
import { NotePasteSettingTab } from "./settings";
import type { CaptureSession, NotePasteSettings, IncomingCapture } from "./types";
import { buildAttachmentPath, buildCompanionCaptureURL, buildFailureMarker, buildPlaceholder, buildTailscaleServeCommand, createSessionId, createUploadToken, normalizeVaultPath } from "./utils";

export default class NotePastePlugin extends Plugin implements ReceiverDelegate {
  settings: NotePasteSettings = DEFAULT_SETTINGS;

  private receiver: NotePasteReceiver | null = null;
  private activeSession: CaptureSession | null = null;
  private captureStatusModal: CaptureStatusModal | null = null;
  private sessionTimeoutHandle: number | null = null;
  private suppressEditorTrigger = false;

  async onload(): Promise<void> {
    await this.loadSettings();
    this.receiver = new NotePasteReceiver(this);
    await this.restartReceiver();

    this.addCommand({
      id: "start-notepaste-capture",
      name: "Start NotePaste capture",
      editorCallback: async (editor, view) => {
        await this.startCaptureFromEditor(editor, view.file, false);
      },
    });

    this.addCommand({
      id: "open-notepaste-settings",
      name: "Open NotePaste settings",
      callback: () => {
        const appWithSettings = this.app as App & {
          setting?: {
            open: () => void;
            openTabById?: (id: string) => void;
          };
        };
        if (!appWithSettings.setting) {
          new Notice("Obsidian settings API is not available in this build.");
          return;
        }
        appWithSettings.setting.open();
        appWithSettings.setting.openTabById?.(this.manifest.id);
      },
    });

    this.addCommand({
      id: "repair-active-notepaste-placeholder",
      name: "Repair active NotePaste placeholder",
      callback: async () => {
        await this.repairActivePlaceholder();
      },
    });

    this.addSettingTab(new NotePasteSettingTab(this.app, this));

    this.registerEvent(
      this.app.workspace.on("editor-change", async (editor, info) => {
        if (this.suppressEditorTrigger) {
          return;
        }
        if (this.activeSession) {
          return;
        }
        const file = getEditorFile(info);
        if (!ensureMarkdownFile(file)) {
          return;
        }
        if (!editorEndsWithTrigger(editor, TOKEN_TRIGGER)) {
          return;
        }
        await this.startCaptureFromEditor(editor, file, true);
      }),
    );
  }

  async onunload(): Promise<void> {
    this.clearSessionTimeout();
    await this.receiver?.close();
  }

  async loadSettings(): Promise<void> {
    const loaded = (await this.loadData()) as Partial<NotePasteSettings> | null;
    this.settings = {
      ...DEFAULT_SETTINGS,
      ...loaded,
      attachmentsFolder: normalizeVaultPath(loaded?.attachmentsFolder?.trim() || DEFAULT_SETTINGS.attachmentsFolder),
      sharedUploadSecretName: loaded?.sharedUploadSecretName?.trim() || DEFAULT_SECRET_NAME,
      companionURLScheme: loaded?.companionURLScheme?.trim() || DEFAULT_COMPANION_URL_SCHEME,
    };
  }

  async saveSettings(): Promise<void> {
    await this.saveData(this.settings);
  }

  async restartReceiver(): Promise<void> {
    if (!this.receiver) {
      return;
    }
    try {
      await this.receiver.listen(this.settings.receiverPort);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Receiver startup failed.";
      new Notice(`NotePaste receiver failed to start: ${message}`);
    }
  }

  async getExpectedSecret(): Promise<string | null> {
    const name = this.settings.sharedUploadSecretName.trim();
    if (!name) {
      return null;
    }
    return this.app.secretStorage.getSecret(name);
  }

  async validateUploadAuthorization(auth: UploadAuthorization): Promise<boolean> {
    const session = this.resolveCaptureSession(auth.sessionId);
    if (session && auth.uploadToken && auth.uploadToken === session.uploadToken) {
      return true;
    }

    const expectedSecret = await this.getExpectedSecret();
    return Boolean(expectedSecret && auth.sharedKey === expectedSecret);
  }

  onServerError(error: Error): void {
    console.error("NotePaste receiver error", error);
  }

  async onCapture(capture: IncomingCapture): Promise<void> {
    const session = this.resolveCaptureSession(capture.sessionId);
    if (!session) {
      throw new Error("Unknown or expired session.");
    }
    await this.completeSession(session, capture);
  }

  async showShortcutInstructions(): Promise<void> {
    const secret = await this.getExpectedSecret();
    new ShortcutInstructionsModal(this, {
      receiverUrl: this.buildCaptureUrl(),
      sessionId: this.activeSession?.id ?? "<session-id-from-plugin>",
      sharedSecret: secret ?? "<select a secret in settings>",
      tailscaleCommand: buildTailscaleServeCommand(this.settings.receiverPort),
    }).open();
  }

  private async startCaptureFromEditor(editor: MarkdownView["editor"], file: TFile | null, triggeredFromToken: boolean): Promise<void> {
    if (!ensureMarkdownFile(file)) {
      return;
    }

    if (this.activeSession) {
      const canceled = await this.markSessionFailed(this.activeSession, "replaced by a newer capture");
      if (canceled) {
        new Notice("Replaced the previous NotePaste capture session.");
      }
    }

    const sessionId = createSessionId();
    const uploadToken = createUploadToken();
    const placeholder = buildPlaceholder(sessionId);
    this.suppressEditorTrigger = true;
    try {
      if (triggeredFromToken) {
        const cursor = editor.getCursor();
        const line = editor.getLine(cursor.line);
        const prefix = line.slice(0, cursor.ch);
        if (prefix.endsWith(TOKEN_TRIGGER)) {
          editor.replaceRange(placeholder, { line: cursor.line, ch: cursor.ch - TOKEN_TRIGGER.length }, cursor);
        }
      } else {
        editor.replaceSelection(placeholder);
      }
    } finally {
      this.suppressEditorTrigger = false;
    }

    this.activeSession = {
      id: sessionId,
      filePath: file.path,
      placeholder,
      uploadToken,
      createdAt: Date.now(),
      expiresAt: Date.now() + this.settings.sessionTimeoutSeconds * 1000,
      noteBasename: file.basename,
    };
    this.armSessionTimeout(this.activeSession);

    this.closeCaptureStatusModal();
    this.captureStatusModal = new CaptureStatusModal(this, this.activeSession);
    this.captureStatusModal.open();
    await this.launchCompanion(this.activeSession);
  }

  private async completeSession(session: CaptureSession, capture: IncomingCapture): Promise<void> {
    const stored = await this.storeAttachment(session, capture);
    const embed = `![[${stored.attachmentPath}]]`;
    const replaced = replacePlaceholderInEditor(
      this.app.workspace.getLeavesOfType("markdown"),
      session.filePath,
      session.placeholder,
      embed,
    );

    if (!replaced) {
      const file = this.app.vault.getAbstractFileByPath(session.filePath);
      if (!(file instanceof TFile)) {
        throw new Error("Original note was not found.");
      }
      await this.app.vault.process(file, (content) => {
        if (!content.includes(session.placeholder)) {
          throw new Error("NotePaste placeholder no longer exists in the note.");
        }
        return content.replace(session.placeholder, embed);
      });
    }

    this.clearActiveSession(session.id);
    this.closeCaptureStatusModal(session.id);
  }

  private async storeAttachment(session: CaptureSession, capture: IncomingCapture): Promise<{ attachmentPath: string; file: TFile }> {
    await ensureFolderExists(this.app, this.settings.attachmentsFolder);
    const attachmentPath = buildAttachmentPath(this.settings.attachmentsFolder, session.noteBasename, capture.contentType);
    const file = await this.app.vault.createBinary(attachmentPath, toArrayBuffer(capture.body));
    return { attachmentPath, file };
  }

  private armSessionTimeout(session: CaptureSession): void {
    this.clearSessionTimeout();
    this.sessionTimeoutHandle = window.setTimeout(() => {
      void this.markSessionFailed(session, "timed out waiting for an upload");
    }, Math.max(1, session.expiresAt - Date.now()));
    this.registerInterval(this.sessionTimeoutHandle);
  }

  private clearSessionTimeout(): void {
    if (this.sessionTimeoutHandle === null) {
      return;
    }
    window.clearTimeout(this.sessionTimeoutHandle);
    this.sessionTimeoutHandle = null;
  }

  private clearActiveSession(sessionId: string): void {
    if (this.activeSession?.id !== sessionId) {
      return;
    }
    this.activeSession = null;
    this.clearSessionTimeout();
  }

  private async markSessionFailed(session: CaptureSession, reason: string): Promise<boolean> {
    if (this.activeSession?.id !== session.id) {
      return false;
    }
    const marker = buildFailureMarker(session.id, reason);
    const replaced = replacePlaceholderInEditor(
      this.app.workspace.getLeavesOfType("markdown"),
      session.filePath,
      session.placeholder,
      marker,
    );
    if (!replaced) {
      const file = this.app.vault.getAbstractFileByPath(session.filePath);
      if (file instanceof TFile) {
        await this.app.vault.process(file, (content) => content.replace(session.placeholder, marker));
      }
    }
    this.clearActiveSession(session.id);
    return true;
  }

  private closeCaptureStatusModal(sessionId?: string): void {
    if (!this.captureStatusModal) {
      return;
    }
    if (sessionId && this.captureStatusModal.session.id !== sessionId) {
      return;
    }
    this.captureStatusModal.close();
    this.captureStatusModal = null;
  }

  buildCaptureUrl(): string {
    const base = this.settings.tailscaleServeURL.trim();
    if (!base) {
      return `http://127.0.0.1:${this.settings.receiverPort}/capture`;
    }
    return `${base.replace(/\/+$/, "")}/capture`;
  }

  buildLocalCaptureUrl(): string {
    return `http://127.0.0.1:${this.settings.receiverPort}/capture`;
  }

  buildCompanionLaunchUrl(session: CaptureSession): string {
    return buildCompanionCaptureURL(
      this.settings.companionURLScheme,
      this.buildLocalCaptureUrl(),
      session.id,
      session.uploadToken,
    );
  }

  async launchCompanion(session: CaptureSession): Promise<void> {
    const opened = await openExternalURL(this.buildCompanionLaunchUrl(session));
    if (!opened) {
      new Notice("NotePaste Camera companion could not be opened. Open it from the capture window.");
    }
  }

  private async repairActivePlaceholder(): Promise<void> {
    const session = this.activeSession;
    if (!session) {
      new Notice("No active NotePaste session.");
      return;
    }
    const file = this.app.vault.getAbstractFileByPath(session.filePath);
    if (!(file instanceof TFile)) {
      new Notice("The note for the active NotePaste session no longer exists.");
      return;
    }
    const contents = await this.app.vault.cachedRead(file);
    if (contents.includes(session.placeholder)) {
      new Notice("Active NotePaste placeholder looks valid.");
      return;
    }
    const failure = `${SESSION_FAILURE_PREFIX}\n> Capture ${session.id} lost its placeholder.`;
    const leaves = this.app.workspace.getLeavesOfType("markdown");
    const inserted = insertRecoveryMarker(leaves, file, failure);
    if (!inserted) {
      await this.app.vault.append(file, `\n\n${failure}\n`);
    }
    this.clearActiveSession(session.id);
    new Notice("Inserted a recovery marker for the missing NotePaste placeholder.");
  }

  private resolveCaptureSession(sessionId: string | null): CaptureSession | null {
    const session = this.activeSession;
    if (!session) {
      return null;
    }
    if (!sessionId) {
      return session;
    }
    return session.id === sessionId ? session : null;
  }
}

async function openExternalURL(url: string): Promise<boolean> {
  try {
    const desktopWindow = window as Window & {
      require?: (moduleName: "electron") => {
        shell?: {
          openExternal: (externalURL: string) => Promise<void>;
        };
      };
    };
    const electron = desktopWindow.require?.("electron");
    if (electron?.shell?.openExternal) {
      await electron.shell.openExternal(url);
      return true;
    }

    window.open(url);
    return true;
  } catch (error) {
    console.error("NotePaste could not open companion URL", error);
    return false;
  }
}

class CaptureStatusModal extends Modal {
  constructor(private readonly plugin: NotePastePlugin, readonly session: CaptureSession) {
    super(plugin.app);
  }

  onOpen(): void {
    const { contentEl } = this;
    contentEl.empty();
    contentEl.addClass("notepaste-capture-modal");

    const hero = contentEl.createDiv({ cls: "notepaste-hero" });
    hero.createDiv({ cls: "notepaste-kicker", text: "NotePaste is listening" });
    hero.createEl("h2", { text: "Take the photo on your iPhone" });
    hero.createEl("p", {
      text: "The native camera window should open automatically. Once the photo is accepted, this popup closes and the image appears in this note.",
    });

    const buttonRow = contentEl.createDiv({ cls: "notepaste-actions" });
    const openButton = buttonRow.createEl("button", {
      cls: "mod-cta",
      text: "Reopen iPhone Camera",
    });
    openButton.addEventListener("click", () => {
      void this.plugin.launchCompanion(this.session);
    });

    const stepList = contentEl.createDiv({ cls: "notepaste-steps" });
    stepList.createDiv({ text: "1. Choose Take Photo if macOS shows the device menu." });
    stepList.createDiv({ text: "2. Tap Use Photo on your iPhone." });
    stepList.createDiv({ text: "3. NotePaste inserts the image here and closes this popup." });

    const fallback = contentEl.createEl("details", { cls: "notepaste-fallback" });
    fallback.createEl("summary", { text: "Fallback upload details" });
    fallback.createEl("p", {
      cls: "notepaste-status",
      text: "Only use these if the native NotePaste Camera app cannot use Continuity Camera.",
    });
    fallback.createEl("strong", { text: "POST URL" });
    fallback.createDiv({ cls: "notepaste-code", text: this.plugin.buildCaptureUrl() });
    fallback.createEl("strong", { text: "Headers" });
    fallback.createDiv({
      cls: "notepaste-code",
      text: `X-NotePaste-Session: ${this.session.id}\nX-NotePaste-Token: ${this.session.uploadToken}`,
    });
  }
}

class ShortcutInstructionsModal extends Modal {
  constructor(
    plugin: NotePastePlugin,
    private readonly details: {
      receiverUrl: string;
      sessionId: string;
      sharedSecret: string;
      tailscaleCommand: string;
    },
  ) {
    super(plugin.app);
  }

  onOpen(): void {
    const { contentEl } = this;
    contentEl.empty();
    contentEl.createEl("h2", { text: "iPhone Shortcut setup" });
    contentEl.createEl("p", {
      text: "Shortcut flow: Take Photo -> Get Contents of URL (POST file) -> Show Result only on failure.",
    });
    contentEl.createEl("p", {
      text: "Run this once on your Mac to expose the local receiver through Tailscale Serve:",
    });
    contentEl.createDiv({ cls: "notepaste-code", text: this.details.tailscaleCommand });
    contentEl.createEl("p", { text: "Use these values in the Shortcut request:" });
    contentEl.createDiv({ cls: "notepaste-code", text: `URL: ${this.details.receiverUrl}` });
    contentEl.createDiv({ cls: "notepaste-code", text: `X-NotePaste-Key: ${this.details.sharedSecret}` });
    contentEl.createDiv({
      cls: "notepaste-code",
      text: "Optional: omit X-NotePaste-Session when you only use one active NotePaste capture at a time.",
    });
    contentEl.createDiv({ cls: "notepaste-code", text: `Current session (optional): ${this.details.sessionId}` });
  }
}

async function ensureFolderExists(app: Plugin["app"], folderPath: string): Promise<void> {
  const normalized = normalizeVaultPath(folderPath);
  const parts = normalized.split("/").filter(Boolean);
  let current = "";
  for (const part of parts) {
    current = current ? `${current}/${part}` : part;
    if (!app.vault.getAbstractFileByPath(current)) {
      await app.vault.createFolder(current);
    }
  }
}

function toArrayBuffer(buffer: Buffer): ArrayBuffer {
  return buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength) as ArrayBuffer;
}

function insertRecoveryMarker(leaves: ReturnType<Plugin["app"]["workspace"]["getLeavesOfType"]>, file: TFile, marker: string): boolean {
  for (const leaf of leaves) {
    const view = leaf.view;
    if (!(view instanceof MarkdownView)) {
      continue;
    }
    if (view.file?.path !== file.path) {
      continue;
    }
    view.editor.replaceSelection(`\n\n${marker}\n`);
    return true;
  }
  return false;
}
