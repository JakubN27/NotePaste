import { createServer, type IncomingMessage, type Server, type ServerResponse } from "http";
import { Buffer } from "buffer";
import type { IncomingCapture } from "./types";

export interface UploadAuthorization {
  sharedKey: string | null;
  sessionId: string | null;
  uploadToken: string | null;
}

export interface ReceiverDelegate {
  validateUploadAuthorization(auth: UploadAuthorization): Promise<boolean>;
  onCapture(capture: IncomingCapture): Promise<void>;
  onServerError(error: Error): void;
}

export class NotePasteReceiver {
  private server: Server | null = null;

  constructor(private readonly delegate: ReceiverDelegate) {}

  async listen(port: number): Promise<void> {
    await this.close();

    this.server = createServer(async (req, res) => {
      try {
        await this.handleRequest(req, res);
      } catch (error) {
        const message = error instanceof Error ? error.message : "Unexpected request failure.";
        this.delegate.onServerError(error instanceof Error ? error : new Error(message));
        if (!res.headersSent) {
          this.respond(res, 500, message);
        }
      }
    });

    this.server.on("error", (error) => {
      this.delegate.onServerError(error instanceof Error ? error : new Error(String(error)));
    });

    await new Promise<void>((resolve, reject) => {
      this.server?.listen(port, "127.0.0.1", () => resolve());
      this.server?.once("error", reject);
    });
  }

  async close(): Promise<void> {
    if (!this.server) {
      return;
    }
    const server = this.server;
    this.server = null;
    await new Promise<void>((resolve, reject) => {
      server.close((error) => {
        if (error) {
          reject(error);
          return;
        }
        resolve();
      });
    });
  }

  private async handleRequest(req: IncomingMessage, res: ServerResponse): Promise<void> {
    if (req.method !== "POST" || req.url !== "/capture") {
      this.respond(res, 404, "Not found");
      return;
    }

    const providedSecret = headerValue(req, "x-notepaste-key");
    const sessionId = headerValue(req, "x-notepaste-session");
    const uploadToken = headerValue(req, "x-notepaste-token");

    const isAuthorized = await this.delegate.validateUploadAuthorization({
      sharedKey: providedSecret,
      sessionId,
      uploadToken,
    });
    if (!isAuthorized) {
      this.respond(res, 401, "Invalid NotePaste upload credentials.");
      return;
    }

    const body = await readBody(req);
    if (body.length === 0) {
      this.respond(res, 400, "Empty upload body.");
      return;
    }

    const capture: IncomingCapture = {
      body,
      contentType: headerValue(req, "content-type") ?? "application/octet-stream",
      sessionId,
    };

    await this.delegate.onCapture(capture);
    this.respond(res, 202, "accepted");
  }

  private respond(res: ServerResponse, statusCode: number, message: string): void {
    res.statusCode = statusCode;
    res.setHeader("Content-Type", "text/plain; charset=utf-8");
    res.end(message);
  }
}

async function readBody(req: IncomingMessage): Promise<Buffer> {
  const chunks: Buffer[] = [];
  for await (const chunk of req) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  return Buffer.concat(chunks);
}

function headerValue(req: IncomingMessage, name: string): string | null {
  const value = req.headers[name];
  if (Array.isArray(value)) {
    return value[0] ?? null;
  }
  return value ?? null;
}
