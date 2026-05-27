import { MarkdownView, Notice, TFile, type Editor, type MarkdownFileInfo, type WorkspaceLeaf } from "obsidian";

export function replacePlaceholderInEditor(
  leaves: WorkspaceLeaf[],
  filePath: string,
  placeholder: string,
  replacement: string,
): boolean {
  for (const leaf of leaves) {
    const view = leaf.view;
    if (!(view instanceof MarkdownView)) {
      continue;
    }
    if (view.file?.path !== filePath) {
      continue;
    }
    const editor = view.editor;
    const content = editor.getValue();
    const index = content.indexOf(placeholder);
    if (index < 0) {
      continue;
    }
    const start = editor.offsetToPos(index);
    const end = editor.offsetToPos(index + placeholder.length);
    editor.replaceRange(replacement, start, end);
    return true;
  }
  return false;
}

export function getEditorFile(info: MarkdownView | MarkdownFileInfo): TFile | null {
  return info.file instanceof TFile ? info.file : null;
}

export function replaceTriggerToken(editor: Editor, trigger: string, placeholder: string): boolean {
  const cursor = editor.getCursor();
  const line = editor.getLine(cursor.line);
  const prefix = line.slice(0, cursor.ch);
  if (!prefix.endsWith(trigger)) {
    return false;
  }
  const start = { line: cursor.line, ch: cursor.ch - trigger.length };
  editor.replaceRange(placeholder, start, cursor);
  return true;
}

export function editorEndsWithTrigger(editor: Editor, trigger: string): boolean {
  const cursor = editor.getCursor();
  const line = editor.getLine(cursor.line);
  return line.slice(0, cursor.ch).endsWith(trigger);
}

export function ensureMarkdownFile(file: TFile | null): file is TFile {
  if (!file) {
    new Notice("NotePaste requires an open Markdown note.");
    return false;
  }
  return file.extension === "md";
}
