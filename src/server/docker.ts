/**
 * A client of the Docker Engine API, over the socket the docker command itself
 * would use: `DOCKER_HOST`, then the current Docker context, then the sockets
 * Docker, Docker Desktop, OrbStack, Colima, Rancher Desktop and Podman put on
 * disk. Node's `http` and nothing else.
 */

import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { request as httpRequest } from "node:http";
import type { IncomingMessage, RequestOptions } from "node:http";
import { request as httpsRequest } from "node:https";
import { homedir } from "node:os";
import { join } from "node:path";

export type Endpoint =
  | { kind: "unix"; socketPath: string; label: string }
  | { kind: "tcp"; host: string; port: number; tls: TlsFiles | undefined; label: string };

interface TlsFiles {
  ca?: Buffer;
  cert?: Buffer;
  key?: Buffer;
}

/** An answer of the engine that is not a success, with the engine's own message. */
export class DockerError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = "DockerError";
  }
}

/** The endpoint the docker command would talk to on this machine. */
export function resolveEndpoint(env: NodeJS.ProcessEnv = process.env): Endpoint {
  const fromHost = env.DOCKER_HOST ? parseHost(env.DOCKER_HOST, env) : undefined;
  if (fromHost !== undefined) return fromHost;
  const context = env.DOCKER_CONTEXT ?? currentContext(env);
  if (context !== undefined && context !== "default") {
    const host = contextHost(context, env);
    const parsed = host === undefined ? undefined : parseHost(host, env);
    if (parsed !== undefined) return parsed;
  }
  const home = homedir();
  const runtime = env.XDG_RUNTIME_DIR;
  const uid = typeof process.getuid === "function" ? process.getuid() : undefined;
  const candidates = [
    "/var/run/docker.sock",
    join(home, ".docker/run/docker.sock"),
    join(home, ".orbstack/run/docker.sock"),
    join(home, ".colima/default/docker.sock"),
    join(home, ".colima/docker.sock"),
    join(home, ".rd/docker.sock"),
    ...(runtime ? [join(runtime, "docker.sock"), join(runtime, "podman/podman.sock")] : []),
    ...(uid !== undefined ? [`/run/user/${uid}/docker.sock`] : []),
    "/run/podman/podman.sock",
  ];
  const found = candidates.find((path) => existsSync(path)) ?? "/var/run/docker.sock";
  return { kind: "unix", socketPath: found, label: found };
}

function parseHost(host: string, env: NodeJS.ProcessEnv): Endpoint | undefined {
  if (host.startsWith("unix://")) {
    const socketPath = host.slice("unix://".length);
    return { kind: "unix", socketPath, label: socketPath };
  }
  if (host.startsWith("tcp://") || host.startsWith("http://") || host.startsWith("https://")) {
    const url = new URL(host.replace(/^tcp:/, "http:"));
    const verify = env.DOCKER_TLS_VERIFY !== undefined && env.DOCKER_TLS_VERIFY !== "";
    const secure = verify || host.startsWith("https://");
    const port = Number(url.port || (secure ? 2376 : 2375));
    let tls: TlsFiles | undefined;
    if (secure) {
      const dir = env.DOCKER_CERT_PATH ?? join(homedir(), ".docker");
      const read = (name: string) => {
        try {
          return readFileSync(join(dir, name));
        } catch {
          return undefined;
        }
      };
      tls = { ca: read("ca.pem"), cert: read("cert.pem"), key: read("key.pem") };
    }
    return { kind: "tcp", host: url.hostname, port, tls, label: `${url.hostname}:${port}` };
  }
  // ssh:// and npipe:// are the docker command's business; there is no socket to reach here.
  return undefined;
}

function currentContext(env: NodeJS.ProcessEnv): string | undefined {
  try {
    const dir = env.DOCKER_CONFIG ?? join(homedir(), ".docker");
    const config = JSON.parse(readFileSync(join(dir, "config.json"), "utf8")) as {
      currentContext?: unknown;
    };
    return typeof config.currentContext === "string" ? config.currentContext : undefined;
  } catch {
    return undefined;
  }
}

/** A context's endpoint, from the file the docker command keeps it in: named by the SHA-256 of its name. */
function contextHost(name: string, env: NodeJS.ProcessEnv): string | undefined {
  try {
    const dir = env.DOCKER_CONFIG ?? join(homedir(), ".docker");
    const digest = createHash("sha256").update(name).digest("hex");
    const meta = JSON.parse(
      readFileSync(join(dir, "contexts", "meta", digest, "meta.json"), "utf8"),
    ) as { Endpoints?: { docker?: { Host?: unknown } } };
    const host = meta.Endpoints?.docker?.Host;
    return typeof host === "string" ? host : undefined;
  } catch {
    return undefined;
  }
}

interface CallOptions {
  body?: unknown;
  /** Milliseconds before the request is given up. */
  timeout?: number;
  /** Statuses that are not failures, besides 2xx: a start of a running container is a 304. */
  accept?: number[];
}

export class Docker {
  constructor(readonly endpoint: Endpoint = resolveEndpoint()) {}

  /** Sends a request and reads the whole answer. */
  async call(method: string, path: string, options: CallOptions = {}): Promise<Buffer> {
    const response = await this.#open(method, path, options);
    const body = await readAll(response);
    const status = response.statusCode ?? 0;
    if ((status < 200 || status >= 300) && !(options.accept ?? []).includes(status)) {
      throw new DockerError(status, messageOf(body, status));
    }
    return body;
  }

  /** Sends a request and reads a JSON answer. */
  async json<T>(method: string, path: string, options: CallOptions = {}): Promise<T> {
    const body = await this.call(method, path, options);
    if (body.length === 0) return undefined as T;
    return JSON.parse(body.toString("utf8")) as T;
  }

  get<T>(path: string, timeout = 15_000): Promise<T> {
    return this.json<T>("GET", path, { timeout });
  }

  /**
   * Sends a request whose answer is a stream, and calls `onData` with each piece
   * of it until it ends or `signal` aborts. Resolves when the stream ends.
   */
  async stream(
    method: string,
    path: string,
    onData: (chunk: Buffer) => void,
    signal?: AbortSignal,
  ): Promise<void> {
    const response = await this.#open(method, path, { signal });
    const status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw new DockerError(status, messageOf(await readAll(response), status));
    }
    await new Promise<void>((resolve, reject) => {
      response.on("data", (chunk: Buffer) => onData(chunk));
      response.on("end", resolve);
      response.on("close", resolve);
      response.on("error", (error) => (signal?.aborted ? resolve() : reject(error)));
    });
  }

  #open(
    method: string,
    path: string,
    options: CallOptions & { signal?: AbortSignal },
  ): Promise<IncomingMessage> {
    const endpoint = this.endpoint;
    const payload = options.body === undefined ? undefined : JSON.stringify(options.body);
    const base: RequestOptions = {
      method,
      path,
      headers: {
        Host: "docker",
        ...(payload === undefined
          ? {}
          : { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(payload) }),
      },
      signal: options.signal,
    };
    return new Promise((resolve, reject) => {
      const request =
        endpoint.kind === "unix"
          ? httpRequest({ ...base, socketPath: endpoint.socketPath }, resolve)
          : endpoint.tls !== undefined
            ? httpsRequest(
                { ...base, host: endpoint.host, port: endpoint.port, ...endpoint.tls },
                resolve,
              )
            : httpRequest({ ...base, host: endpoint.host, port: endpoint.port }, resolve);
      request.on("error", reject);
      if (options.timeout !== undefined) {
        request.setTimeout(options.timeout, () => {
          request.destroy(new Error(`Docker did not answer ${method} ${path} in time`));
        });
      }
      if (payload !== undefined) request.write(payload);
      request.end();
    });
  }
}

function readAll(response: IncomingMessage): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    response.on("data", (chunk: Buffer) => chunks.push(chunk));
    response.on("end", () => resolve(Buffer.concat(chunks)));
    response.on("error", reject);
  });
}

function messageOf(body: Buffer, status: number): string {
  try {
    const parsed = JSON.parse(body.toString("utf8")) as { message?: unknown };
    if (typeof parsed.message === "string") return parsed.message;
  } catch {
    // Not JSON: the text is the message, if there is one.
  }
  const text = body.toString("utf8").trim();
  return text || `Docker answered ${status}`;
}

/** A query string from the values that are set; objects are JSON, as the engine's `filters` want. */
export function query(values: Record<string, unknown>): string {
  const parts: string[] = [];
  for (const [key, value] of Object.entries(values)) {
    if (value === undefined || value === null || value === false) continue;
    const text = typeof value === "object" ? JSON.stringify(value) : String(value);
    parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(text)}`);
  }
  return parts.length === 0 ? "" : `?${parts.join("&")}`;
}

/**
 * Splits the engine's multiplexed stream of a container without a tty: frames of
 * an 8-byte header (stream, 3 zero bytes, big-endian length) and their payload.
 * What is left of an unfinished frame is kept for the next chunk.
 */
export class Demuxer {
  #pending = Buffer.alloc(0);

  constructor(readonly onFrame: (stream: "out" | "err", payload: Buffer) => void) {}

  push(chunk: Buffer): void {
    let buffer = this.#pending.length === 0 ? chunk : Buffer.concat([this.#pending, chunk]);
    while (buffer.length >= 8) {
      const size = buffer.readUInt32BE(4);
      if (buffer.length < 8 + size) break;
      const stream = buffer[0] === 2 ? "err" : "out";
      this.onFrame(stream, buffer.subarray(8, 8 + size));
      buffer = buffer.subarray(8 + size);
    }
    this.#pending = Buffer.from(buffer);
  }
}
