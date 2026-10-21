/**
 * The state of one dockerpen program: the engine it talks to, the samplers and
 * the feed it keeps between the view's polls, the jobs that run, the view's own
 * state (which outlives the view: a view that comes back from a shell, or that
 * the terminal starts again, finds it here), and the hand-off of the pane.
 */

import { spawnSync } from "node:child_process";
import { hostname, userInfo } from "node:os";

import {
  StatsSampler,
  act,
  inspectContainer,
  listContainers,
  processes,
  readLogs,
} from "./containers.js";
import { Docker } from "./docker.js";
import { EventFeed } from "./events.js";
import { Jobs } from "./jobs.js";
import { DiskCounter, prune, pull } from "./resources.js";
import { bytes } from "./format.js";
import type {
  ActionOutcome,
  Boot,
  ContainerAction,
  ContainerSummary,
  Engine,
  EngineInfo,
  Handoff,
  Job,
  PollResult,
  PruneTarget,
  UiState,
} from "./types.js";

export interface PollRequest {
  stats?: boolean;
  history?: boolean;
  events?: number;
  logs?: { id: string; since?: string | null; tail?: number };
  ui?: UiState;
}

export interface HandoffRequest {
  kind: Handoff["kind"];
  id: string;
  name: string;
}

/**
 * Who can take the pane from the view: the program's main loop, which closes the
 * view, runs the command in the terminal and shows the view again. Absent when the
 * program is an MCP server on stdio, where there is no terminal to hand over.
 */
export interface Desk {
  request(request: HandoffRequest): "scheduled" | "busy";
}

const PRUNE_TITLES: Record<PruneTarget, string> = {
  containers: "stopped containers",
  danglingImages: "dangling images",
  unusedImages: "unused images",
  volumes: "unused volumes",
  networks: "unused networks",
  buildCache: "build cache",
};

export class Dockerpen {
  readonly docker: Docker;
  readonly sampler: StatsSampler;
  readonly events: EventFeed;
  readonly disk: DiskCounter;
  readonly jobs = new Jobs();
  ui: UiState = {};
  desk: Desk | undefined;
  /** What the pane was last handed to; told to the next view that boots, once. */
  returned: Handoff | undefined;
  /** A hand-off the terminal could not make; told to the view with its next poll, once. */
  handoffFailed: string | undefined;

  #engine: { at: number; value: Engine } | undefined;
  #tools: { cli: boolean; compose: boolean } | undefined;
  #containers: ContainerSummary[] = [];

  constructor(docker = new Docker()) {
    this.docker = docker;
    this.sampler = new StatsSampler(docker);
    this.events = new EventFeed(docker);
    this.disk = new DiskCounter(docker);
    this.jobs.onEnded = () => this.disk.forget();
  }

  /** The containers of the last poll: what other answers name containers by. */
  get containers(): readonly ContainerSummary[] {
    return this.#containers;
  }

  boot(): Boot {
    const returned = this.returned;
    this.returned = undefined;
    let user = "";
    try {
      user = userInfo().username;
    } catch {
      // A user without an entry in the password file still runs programs.
    }
    return {
      ui: this.ui,
      ...(returned ? { returned } : {}),
      user,
      hostname: hostname(),
    };
  }

  /** Whether the pane can be handed to a command: a terminal, and the docker command to run there. */
  canHandOff(engine: Engine): boolean {
    return this.desk !== undefined && engine.ok && engine.cli;
  }

  async engine(): Promise<Engine> {
    const cached = this.#engine;
    // A working engine is asked again every half minute; one that did not answer, at once.
    if (cached?.value.ok && Date.now() - cached.at < 30_000) return cached.value;
    const endpoint = this.docker.endpoint.label;
    try {
      const [info, version] = await Promise.all([
        this.docker.get<{
          Name?: string;
          OperatingSystem?: string;
          NCPU?: number;
          MemTotal?: number;
          OSType?: string;
          Architecture?: string;
        }>("/info", 5000),
        this.docker.get<{ Version?: string; ApiVersion?: string; Os?: string; Arch?: string }>(
          "/version",
          5000,
        ),
      ]);
      this.#tools ??= findTools();
      const value: EngineInfo = {
        ok: true,
        name: info.OperatingSystem ?? "Docker",
        hostname: info.Name ?? "",
        version: version.Version ?? "",
        apiVersion: version.ApiVersion ?? "",
        os: version.Os ?? info.OSType ?? "",
        arch: version.Arch ?? info.Architecture ?? "",
        cpus: info.NCPU ?? 0,
        memory: info.MemTotal ?? 0,
        endpoint,
        cli: this.#tools.cli,
        compose: this.#tools.compose,
      };
      this.#engine = { at: Date.now(), value };
      return value;
    } catch (error) {
      const value: Engine = {
        ok: false,
        endpoint,
        error: error instanceof Error ? error.message : String(error),
      };
      this.#engine = { at: Date.now(), value };
      return value;
    }
  }

  async poll(request: PollRequest): Promise<PollResult> {
    if (request.ui !== undefined) this.ui = request.ui;
    const handoffFailed = this.handoffFailed;
    this.handoffFailed = undefined;
    const engine = await this.engine();
    const base = {
      at: Date.now(),
      jobs: this.jobs.list(),
      ...(handoffFailed ? { handoffFailed } : {}),
    };
    if (!engine.ok) {
      return {
        ...base,
        engine,
        containers: [],
        stats: {},
        events: { cursor: request.events ?? -1, items: [] },
      };
    }
    try {
      this.events.start();
      const containers = await listContainers(this.docker);
      this.#containers = containers;
      const running = containers.filter((c) => c.state === "running").map((c) => c.id);
      const logsWanted = request.logs;
      const [stats, logs] = await Promise.all([
        request.stats === false ? Promise.resolve({}) : this.sampler.sample(running),
        logsWanted && containers.some((c) => c.id === logsWanted.id)
          ? readLogs(this.docker, logsWanted.id, logsWanted.since, logsWanted.tail ?? 400).catch(
              () => undefined,
            )
          : Promise.resolve(undefined),
      ]);
      return {
        ...base,
        engine,
        containers,
        stats,
        ...(request.history ? { history: this.sampler.history() } : {}),
        events: this.events.after(request.events ?? -1),
        ...(logs ? { logs } : {}),
      };
    } catch (error) {
      // The engine answered a moment ago and not now: it is asked afresh next time.
      this.#engine = undefined;
      return {
        ...base,
        engine: {
          ok: false,
          endpoint: this.docker.endpoint.label,
          error: error instanceof Error ? error.message : String(error),
        },
        containers: [],
        stats: {},
        events: { cursor: request.events ?? -1, items: [] },
      };
    }
  }

  detail(id: string) {
    return inspectContainer(this.docker, id);
  }

  processes(id: string) {
    return processes(this.docker, id);
  }

  async act(
    ids: readonly string[],
    action: ContainerAction,
    options: { force?: boolean; volumes?: boolean } = {},
  ): Promise<ActionOutcome[]> {
    const names = new Map(this.#containers.map((c) => [c.id, c.name]));
    return Promise.all(
      ids.map(async (id) => {
        const name = names.get(id) ?? id.slice(0, 12);
        try {
          await act(this.docker, id, action, options);
          return { id, name, ok: true };
        } catch (error) {
          return {
            id,
            name,
            ok: false,
            error: error instanceof Error ? error.message : String(error),
          };
        }
      }),
    );
  }

  pull(reference: string): Job {
    return this.jobs.start("pull", `Pull ${reference}`, async (update) => {
      await pull(this.docker, reference, update);
      return `Pulled ${reference}`;
    });
  }

  prune(targets: readonly PruneTarget[]): Job {
    const title =
      targets.length === 1
        ? `Remove ${PRUNE_TITLES[targets[0]!]}`
        : `Clean up ${targets.length} kinds`;
    return this.jobs.start("prune", title, async (update) => {
      let reclaimed = 0;
      for (const [index, target] of targets.entries()) {
        update(index / targets.length, `Removing ${PRUNE_TITLES[target]}…`);
        reclaimed += await prune(this.docker, target);
      }
      return reclaimed > 0 ? `Freed ${bytes(reclaimed)}` : "Nothing was in use to free";
    });
  }
}

/** Whether the docker command, and its compose plugin, are installed. */
function findTools(): { cli: boolean; compose: boolean } {
  const run = (args: string[]) => {
    try {
      return spawnSync("docker", args, { stdio: "ignore", timeout: 4000 }).status === 0;
    } catch {
      return false;
    }
  };
  const cli = run(["--version"]);
  return { cli, compose: cli && run(["compose", "version"]) };
}
