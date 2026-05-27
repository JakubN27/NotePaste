import { randomBytes } from "crypto";

export function createSessionId(): string {
  return randomBytes(12).toString("hex");
}

export function createSharedKey(): string {
  return randomBytes(24).toString("base64url");
}

export function createUploadToken(): string {
  return randomBytes(24).toString("base64url");
}

export function buildPlaceholder(sessionId: string): string {
  return `<!-- notepaste:${sessionId} -->`;
}

export function buildFailureMarker(sessionId: string, reason: string): string {
  return `> [!failure] NotePaste\n> Capture ${sessionId} failed: ${reason}`;
}

export function sanitizePathSegment(input: string): string {
  return input
    .replace(/[\\/:*?"<>|#^\[\]]+/g, "-")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 80) || "note";
}

export function timestampSlug(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  const hours = String(date.getHours()).padStart(2, "0");
  const minutes = String(date.getMinutes()).padStart(2, "0");
  const seconds = String(date.getSeconds()).padStart(2, "0");
  return `${year}${month}${day}-${hours}${minutes}${seconds}`;
}

export function extensionForContentType(contentType: string): string {
  const normalized = contentType.toLowerCase().split(";")[0]?.trim() ?? "application/octet-stream";
  switch (normalized) {
    case "image/jpeg":
      return "jpg";
    case "image/png":
      return "png";
    case "image/heic":
    case "image/heif":
      return "heic";
    case "image/webp":
      return "webp";
    case "application/pdf":
      return "pdf";
    case "application/octet-stream":
      return "jpg";
    default:
      if (normalized.startsWith("image/")) {
        return normalized.slice("image/".length);
      }
      return "bin";
  }
}

export function buildAttachmentPath(folder: string, noteBasename: string, contentType: string, now = new Date()): string {
  const safeFolder = normalizeVaultPath(folder);
  const safeNote = sanitizePathSegment(noteBasename);
  const ext = extensionForContentType(contentType);
  return normalizeVaultPath(`${safeFolder}/${timestampSlug(now)}-${safeNote}.${ext}`);
}

export function buildTailscaleServeCommand(port: number): string {
  return `tailscale serve --bg ${port}`;
}

export function buildCompanionCaptureURL(baseURL: string, callbackURL: string, sessionId: string, uploadToken: string): string {
  const url = new URL(baseURL || "notepaste-camera://capture");
  url.searchParams.set("callback", callbackURL);
  url.searchParams.set("session", sessionId);
  url.searchParams.set("token", uploadToken);
  return url.toString();
}

export function isValidUploadSecretName(secretName: string): boolean {
  return secretName.trim().length > 0;
}

export function normalizeVaultPath(input: string): string {
  return input
    .replace(/\\/g, "/")
    .replace(/\/{2,}/g, "/")
    .replace(/^\/+/, "")
    .replace(/\/+$/, "")
    .trim();
}
