/**
 * What happens in the engine — a container that starts, dies, turns unhealthy,
 * an image pulled, a volume removed — as a numbered list the view reads from
 * where it left off. One subscription to the engine's event stream, kept open
 * and opened again when it breaks.
 */

import { Docker, query } from "./docker.js";
import type { DockerEvent } from "./types.js";

/** How many events are kept for a view that asks. */
const KEPT = 400;

/** Actions that are the machinery of other actions, not news: an exec, an attach, a resize. */
const QUIET =
  /^(exec_create|exec_start|exec_die|attach|detach|resize|top|archive-path|extract-to-dir|copy)/;

interface RawEvent {
  Type?: string;
  Action?: string;
  Actor?: { ID?: string; Attributes?: Record<string, string> };
  time?: number;
  timeNano?: number;
}

export class EventFeed {
  readonly #events: DockerEvent[] = [];
  #seq = 0;
  #running = false;
  #since: number | undefined;
  #abort: AbortController | undefined;

  constructor(readonly docker: Docker) {}

  /** Starts listening, once. */
  start(): void {
    if (this.#running) return;
    this.#running = true;
    void this.#loop();
  }

  stop(): void {
    this.#running = false;
    this.#abort?.abort();
  }

  /** The events after `cursor`; a cursor of -1 asks for the most recent ones. */
  after(cursor: number): { cursor: number; items: DockerEvent[] } {
    const items =
      cursor < 0 ? this.#events.slice(-60) : this.#events.filter((event) => event.seq > cursor);
    return { cursor: this.#seq, items };
  }

  async #loop(): Promise<void> {
    while (this.#running) {
      const abort = new AbortController();
      this.#abort = abort;
      let rest = "";
      try {
        // On the first connection, the last ten minutes, so that a view that opens
        // has something to show; after a break, from where it broke.
        const since = this.#since ?? Math.floor(Date.now() / 1000) - 600;
        await this.docker.stream(
          "GET",
          `/events${query({ since })}`,
          (chunk) => {
            rest += chunk.toString("utf8");
            const lines = rest.split("\n");
            rest = lines.pop() ?? "";
            for (const line of lines) this.#take(line);
          },
          abort.signal,
        );
      } catch {
        // The engine went away or the stream broke; the loop waits and connects again.
      }
      if (!this.#running) return;
      await new Promise((resolve) => setTimeout(resolve, 2000).unref());
    }
  }

  #take(line: string): void {
    if (!line.trim()) return;
    let raw: RawEvent;
    try {
      raw = JSON.parse(line) as RawEvent;
    } catch {
      return;
    }
    const action = raw.Action ?? "";
    if (QUIET.test(action)) return;
    const time = raw.timeNano ? Math.floor(raw.timeNano / 1e6) : (raw.time ?? 0) * 1000;
    this.#since = Math.floor(time / 1000) + 1;
    const attributes = raw.Actor?.Attributes ?? {};
    const detail: Record<string, string> = {};
    for (const key of ["image", "exitCode", "signal", "driver", "type", "container"]) {
      if (attributes[key] !== undefined) detail[key] = attributes[key];
    }
    this.#seq += 1;
    this.#events.push({
      seq: this.#seq,
      time,
      type: raw.Type ?? "",
      action,
      id: raw.Actor?.ID ?? "",
      ...(attributes.name ? { name: attributes.name } : {}),
      detail,
    });
    if (this.#events.length > KEPT) this.#events.splice(0, this.#events.length - KEPT);
  }
}
