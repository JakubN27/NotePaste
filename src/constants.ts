import type { NotePasteSettings } from "./types";

export const PLACEHOLDER_PREFIX = "<!-- notepaste:";
export const PLACEHOLDER_SUFFIX = " -->";
export const TOKEN_TRIGGER = "/notepaste";
export const DEFAULT_SECRET_NAME = "notepaste-shared-key";
export const DEFAULT_COMPANION_URL_SCHEME = "notepaste-camera://capture";

export const DEFAULT_SETTINGS: NotePasteSettings = {
  attachmentsFolder: "Attachments/NotePaste",
  sharedUploadSecretName: DEFAULT_SECRET_NAME,
  receiverPort: 43157,
  tailscaleServeURL: "",
  companionURLScheme: DEFAULT_COMPANION_URL_SCHEME,
  sessionTimeoutSeconds: 180,
};

export const SESSION_FAILURE_PREFIX = "> [!failure] NotePaste";
