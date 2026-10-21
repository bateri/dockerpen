/**
 * Work that takes longer than a view may wait for an answer — a pull, a prune —
 * runs here, and the view reads how far it has come with its next poll. A
 * terminal gives up a view's request the program does not answer within a
 * minute, so nothing that can take longer is done inside a tool call.
 */

import type { Job } from "./types.js";

/** Finished jobs are shown for this long, then forgotten. */
const KEEP_FINISHED = 60_000;

export class Jobs {
  readonly #jobs = new Map<string, Job>();
  #next = 1;
  /** Called when a job ends, with what it did: the server forgets the disk count then. */
  onEnded: ((job: Job) => void) | undefined;

  list(): Job[] {
    const now = Date.now();
    for (const [id, job] of this.#jobs) {
      if (job.ended !== undefined && now - job.ended > KEEP_FINISHED) this.#jobs.delete(id);
    }
    return [...this.#jobs.values()];
  }

  /** Runs `work` as a job; `update` tells how far it has come. Returns the job at once. */
  start(
    kind: Job["kind"],
    title: string,
    work: (update: (progress: number | null, detail: string) => void) => Promise<string>,
  ): Job {
    const job: Job = {
      id: `job-${this.#next++}`,
      kind,
      title,
      state: "running",
      progress: null,
      detail: "Starting…",
      started: Date.now(),
    };
    this.#jobs.set(job.id, job);
    const update = (progress: number | null, detail: string) => {
      job.progress = progress;
      job.detail = detail;
    };
    void work(update).then(
      (detail) => {
        job.state = "done";
        job.progress = 1;
        job.detail = detail;
        job.ended = Date.now();
        this.onEnded?.(job);
      },
      (error: unknown) => {
        job.state = "failed";
        job.error = error instanceof Error ? error.message : String(error);
        job.detail = job.error;
        job.ended = Date.now();
        this.onEnded?.(job);
      },
    );
    return { ...job };
  }
}
