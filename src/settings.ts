import {
  Notice,
  PluginSettingTab,
  SecretComponent,
  Setting,
} from "obsidian";
import { DEFAULT_COMPANION_URL_SCHEME, DEFAULT_SETTINGS } from "./constants";
import type NotePastePlugin from "./main";
import { createSharedKey, normalizeVaultPath } from "./utils";

export class NotePasteSettingTab extends PluginSettingTab {
  constructor(app: NotePastePlugin["app"], private readonly plugin: NotePastePlugin) {
    super(app, plugin);
  }

  display(): void {
    const { containerEl } = this;
    containerEl.empty();

    containerEl.createEl("h2", { text: "NotePaste" });

    new Setting(containerEl)
      .setName("Attachments folder")
      .setDesc("Vault-relative folder where uploaded images will be stored.")
      .addText((text) => {
        text
          .setPlaceholder(DEFAULT_SETTINGS.attachmentsFolder)
          .setValue(this.plugin.settings.attachmentsFolder)
          .onChange(async (value) => {
            this.plugin.settings.attachmentsFolder = normalizeVaultPath(value.trim() || DEFAULT_SETTINGS.attachmentsFolder);
            await this.plugin.saveSettings();
          });
      });

    new Setting(containerEl)
      .setName("Receiver port")
      .setDesc("The local HTTP port that NotePaste listens on.")
      .addText((text) => {
        text
          .setPlaceholder(String(DEFAULT_SETTINGS.receiverPort))
          .setValue(String(this.plugin.settings.receiverPort))
          .onChange(async (value) => {
            const parsed = Number.parseInt(value.trim(), 10);
            if (Number.isNaN(parsed) || parsed < 1 || parsed > 65535) {
              return;
            }
            this.plugin.settings.receiverPort = parsed;
            await this.plugin.saveSettings();
            await this.plugin.restartReceiver();
          });
      });

    new Setting(containerEl)
      .setName("Session timeout")
      .setDesc("How long a capture placeholder remains valid before it is marked failed.")
      .addText((text) => {
        text
          .setPlaceholder(String(DEFAULT_SETTINGS.sessionTimeoutSeconds))
          .setValue(String(this.plugin.settings.sessionTimeoutSeconds))
          .onChange(async (value) => {
            const parsed = Number.parseInt(value.trim(), 10);
            if (Number.isNaN(parsed) || parsed < 10) {
              return;
            }
            this.plugin.settings.sessionTimeoutSeconds = parsed;
            await this.plugin.saveSettings();
          });
      });

    new Setting(containerEl)
      .setName("Tailscale serve URL")
      .setDesc("The HTTPS URL exposed by Tailscale Serve, used in the iPhone Shortcut.")
      .addText((text) => {
        text
          .setPlaceholder("https://your-machine.ts.net")
          .setValue(this.plugin.settings.tailscaleServeURL)
          .onChange(async (value) => {
            this.plugin.settings.tailscaleServeURL = value.trim();
            await this.plugin.saveSettings();
          });
      });

    new Setting(containerEl)
      .setName("Companion URL")
      .setDesc("Custom URL opened when a capture starts. The native companion app registers this URL scheme.")
      .addText((text) => {
        text
          .setPlaceholder(DEFAULT_COMPANION_URL_SCHEME)
          .setValue(this.plugin.settings.companionURLScheme)
          .onChange(async (value) => {
            this.plugin.settings.companionURLScheme = value.trim() || DEFAULT_COMPANION_URL_SCHEME;
            await this.plugin.saveSettings();
          });
      });

    new Setting(containerEl)
      .setName("Shared upload key")
      .setDesc("Choose a secret from Obsidian Secret Storage. The iPhone Shortcut must send the same value.")
      .addComponent((el) =>
        new SecretComponent(this.app, el)
          .setValue(this.plugin.settings.sharedUploadSecretName)
          .onChange(async (value) => {
            this.plugin.settings.sharedUploadSecretName = value.trim();
            await this.plugin.saveSettings();
          }),
      );

    new Setting(containerEl)
      .setName("Generate example key")
      .setDesc("Writes a random key to the clipboard so you can store it in Secret Storage and your iPhone Shortcut.")
      .addButton((button) =>
        button.setButtonText("Copy key").onClick(async () => {
          const key = createSharedKey();
          await navigator.clipboard.writeText(key);
          new Notice("Generated NotePaste key copied to clipboard.");
        }),
      );

    new Setting(containerEl)
      .setName("Show iPhone Shortcut")
      .setDesc("Opens setup instructions with the current endpoint and headers.")
      .addButton((button) =>
        button.setButtonText("Show instructions").onClick(() => {
          this.plugin.showShortcutInstructions();
        }),
      );
  }
}
