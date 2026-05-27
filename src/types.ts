import type { TFile } from "obsidian";

export interface NotePasteSettings {
  attachmentsFolder: string;
  sharedUploadSecretName: string;
  receiverPort: number;
  tailscaleServeURL: string;
  companionURLScheme: string;
  sessionTimeoutSeconds: number;
}

export interface CaptureSession {
  id: string;
  filePath: string;
  placeholder: string;
  uploadToken: string;
  createdAt: number;
  expiresAt: number;
  noteBasename: string;
}

export interface IncomingCapture {
  body: Buffer;
  contentType: string;
  sessionId: string | null;
}

export interface CompletedCapture {
  attachmentPath: string;
  file: TFile;
}
