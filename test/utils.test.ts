import test from "node:test";
import assert from "node:assert/strict";
import {
  buildAttachmentPath,
  buildCompanionCaptureURL,
  buildPlaceholder,
  buildTailscaleServeCommand,
  buildFailureMarker,
  extensionForContentType,
} from "../src/utils";

test("buildPlaceholder uses a stable hidden comment shape", () => {
  assert.equal(buildPlaceholder("abc123"), "<!-- notepaste:abc123 -->");
});

test("attachment path uses normalized folder and file extension", () => {
  const path = buildAttachmentPath("Attachments/NotePaste", "Linear Algebra", "image/heic", new Date(2026, 4, 26, 12, 34, 56));
  assert.match(path, /^Attachments\/NotePaste\/20260526-123456-Linear Algebra\.heic$/);
});

test("failure marker stays readable markdown", () => {
  const marker = buildFailureMarker("abc123", "timed out");
  assert.equal(marker, "> [!failure] NotePaste\n> Capture abc123 failed: timed out");
});

test("tailscale command targets the receiver port", () => {
  assert.equal(buildTailscaleServeCommand(43157), "tailscale serve --bg 43157");
});

test("content type fallback supports generic binary uploads", () => {
  assert.equal(extensionForContentType("application/octet-stream"), "jpg");
});

test("pdf uploads keep a pdf extension", () => {
  assert.equal(extensionForContentType("application/pdf"), "pdf");
});

test("companion capture URL carries callback and one-time token", () => {
  const url = new URL(buildCompanionCaptureURL(
    "notepaste-camera://capture",
    "http://127.0.0.1:43157/capture",
    "session-1",
    "token-1",
  ));
  assert.equal(url.protocol, "notepaste-camera:");
  assert.equal(url.host, "capture");
  assert.equal(url.searchParams.get("callback"), "http://127.0.0.1:43157/capture");
  assert.equal(url.searchParams.get("session"), "session-1");
  assert.equal(url.searchParams.get("token"), "token-1");
});
