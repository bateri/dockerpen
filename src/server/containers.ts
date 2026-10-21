/**
 * Containers as the view shows them: the list, one container's detail, its
 * resource use over time, its processes and its logs.
 */

import { Demuxer, Docker, DockerError, query } from "./docker.js";
import type {
  ContainerDetail,
  ContainerState,
  ContainerStats,
  ContainerSummary,
  Health,
  LogLine,
  LogsChunk,
  PortBinding,
  ProcessList,
  StatsSample,
} from "./types.js";

// ---- the list --------------------------------------------------------------------------

interface RawContainer {
  Id: string;
  Names?: string[];
  Image: string;
  ImageID: string;
  Command: string;
  Created: number;
  State: string;
  Status: string;
  Ports?: { IP?: string; PrivatePort: number; PublicPort?: number; Type: string }[];
  Labels?: Record<string, string>;
  Health?: { Status?: string };
  NetworkSettings?: { Networks?: Record<string, unknown> };
  Mounts?: { Type: string; Name?: string; Source?: string; Destination: string }[];
}

const STATES: readonly ContainerState[] = [
  "running",
  "exited",
  "paused",
  "restarting",
  "created",
  "removing",
  "dead",
];

export async function listContainers(docker: Docker): Promise<ContainerSummary[]> {
  const raw = await docker.get<RawContainer[]>("/containers/json?all=1");
  return raw.map(summarize);
}

function summarize(raw: RawContainer): ContainerSummary {
  const labels = raw.Labels ?? {};
  const state = (STATES as readonly string[]).includes(raw.State)
    ? (raw.State as ContainerState)
    : "created";
  const exited = /Exited \((-?\d+)\)/.exec(raw.Status);
  return {
    id: raw.Id,
    name: (raw.Names?.[0] ?? raw.Id.slice(0, 12)).replace(/^\//, ""),
    image: raw.Image.startsWith("sha256:") ? raw.Image.slice(7, 19) : raw.Image,
    imageId: raw.ImageID,
    command: raw.Command,
    created: raw.Created,
    state,
    status: raw.Status,
    // A stopped container keeps the health of its last check, which says nothing now.
    health: state === "running" ? healthOf(raw) : "none",
    ...(exited ? { exitCode: Number(exited[1]) } : {}),
    ports: ports(raw.Ports ?? []),
    ...(labels["com.docker.compose.project"]
      ? { project: labels["com.docker.compose.project"] }
      : {}),
    ...(labels["com.docker.compose.service"]
      ? { service: labels["com.docker.compose.service"] }
      : {}),
    networks: Object.keys(raw.NetworkSettings?.Networks ?? {}),
    mounts: (raw.Mounts ?? []).map((mount) => ({
      type: mount.Type,
      ...(mount.Name ? { name: mount.Name } : {}),
      ...(mount.Source ? { source: mount.Source } : {}),
      destination: mount.Destination,
    })),
  };
}

/** The health of a container: the list has it from API 1.52 on, and in its status words before. */
function healthOf(raw: RawContainer): Health {
  const status = raw.Health?.Status;
  if (status === "healthy" || status === "unhealthy" || status === "starting") return status;
  if (/\(healthy\)/.test(raw.Status)) return "healthy";
  if (/\(unhealthy\)/.test(raw.Status)) return "unhealthy";
  if (/\(health: starting\)/.test(raw.Status)) return "starting";
  return "none";
}

/** The ports, once each: the engine lists a published port for IPv4 and again for IPv6. */
function ports(raw: NonNullable<RawContainer["Ports"]>): PortBinding[] {
  const seen = new Map<string, PortBinding>();
  for (const port of raw) {
    const key = `${port.PublicPort ?? ""}/${port.PrivatePort}/${port.Type}`;
    if (seen.has(key)) continue;
    seen.set(key, {
      ...(port.IP && port.PublicPort !== undefined ? { ip: port.IP } : {}),
      ...(port.PublicPort !== undefined ? { public: port.PublicPort } : {}),
      private: port.PrivatePort,
      type: port.Type,
    });
  }
  return [...seen.values()].sort(
    (a, b) => (a.public ?? 1e6) - (b.public ?? 1e6) || a.private - b.private,
  );
}

// ---- one container ---------------------------------------------------------------------

interface RawInspect {
  Id: string;
  Name: string;
  Created: string;
  Path: string;
  Args?: string[];
  Image: string;
  Platform?: string;
  RestartCount?: number;
  State: {
    Status: string;
    Running: boolean;
    Paused: boolean;
    Restarting: boolean;
    OOMKilled: boolean;
    Dead: boolean;
    Pid: number;
    ExitCode: number;
    Error: string;
    StartedAt: string;
    FinishedAt: string;
    Health?: {
      Status: string;
      FailingStreak: number;
      Log?: { Start: string; End: string; ExitCode: number; Output: string }[];
    };
  };
  Config: {
    Image: string;
    Env?: string[];
    Cmd?: string[] | null;
    Entrypoint?: string[] | null;
    WorkingDir?: string;
    User?: string;
    Labels?: Record<string, string>;
    Tty?: boolean;
    Healthcheck?: { Test?: string[] };
  };
  HostConfig?: {
    RestartPolicy?: { Name?: string; MaximumRetryCount?: number };
    NetworkMode?: string;
    Privileged?: boolean;
    Memory?: number;
    NanoCpus?: number;
    PortBindings?: Record<string, { HostIp?: string; HostPort?: string }[] | null>;
  };
  NetworkSettings?: {
    Ports?: Record<string, { HostIp?: string; HostPort?: string }[] | null>;
    Networks?: Record<
      string,
      { IPAddress?: string; Gateway?: string; MacAddress?: string; Aliases?: string[] | null }
    >;
  };
  Mounts?: {
    Type: string;
    Name?: string;
    Source: string;
    Destination: string;
    RW: boolean;
  }[];
}

export async function inspectContainer(docker: Docker, id: string): Promise<ContainerDetail> {
  const raw = await docker.get<RawInspect>(`/containers/${encodeURIComponent(id)}/json`);
  ttys.set(raw.Id, raw.Config.Tty === true);
  const health = raw.State.Health;
  const policy = raw.HostConfig?.RestartPolicy;
  const portMap = raw.NetworkSettings?.Ports ?? {};
  const bound: PortBinding[] = [];
  for (const [spec, bindings] of Object.entries(portMap)) {
    const [port, type = "tcp"] = spec.split("/");
    const unique = new Set<string>();
    for (const binding of bindings ?? []) {
      if (binding.HostPort === undefined || unique.has(binding.HostPort)) continue;
      unique.add(binding.HostPort);
      bound.push({
        ...(binding.HostIp ? { ip: binding.HostIp } : {}),
        public: Number(binding.HostPort),
        private: Number(port),
        type,
      });
    }
    if ((bindings ?? []).length === 0) bound.push({ private: Number(port), type });
  }
  return {
    id: raw.Id,
    name: raw.Name.replace(/^\//, ""),
    image: raw.Config.Image,
    imageId: raw.Image,
    created: raw.Created,
    path: raw.Path,
    args: raw.Args ?? [],
    entrypoint: raw.Config.Entrypoint ?? [],
    cmd: raw.Config.Cmd ?? [],
    workingDir: raw.Config.WorkingDir ?? "",
    user: raw.Config.User ?? "",
    env: (raw.Config.Env ?? []).map((entry) => {
      const at = entry.indexOf("=");
      return at < 0
        ? { key: entry, value: "" }
        : { key: entry.slice(0, at), value: entry.slice(at + 1) };
    }),
    labels: raw.Config.Labels ?? {},
    state: {
      status: (STATES as readonly string[]).includes(raw.State.Status)
        ? (raw.State.Status as ContainerState)
        : "created",
      running: raw.State.Running,
      paused: raw.State.Paused,
      restarting: raw.State.Restarting,
      oomKilled: raw.State.OOMKilled,
      dead: raw.State.Dead,
      pid: raw.State.Pid,
      exitCode: raw.State.ExitCode,
      error: raw.State.Error,
      startedAt: raw.State.StartedAt,
      finishedAt: raw.State.FinishedAt,
      ...(health
        ? {
            health: {
              status: (["healthy", "unhealthy", "starting"].includes(health.Status)
                ? health.Status
                : "none") as Health,
              failingStreak: health.FailingStreak,
              log: (health.Log ?? []).slice(-5).map((entry) => ({
                start: entry.Start,
                end: entry.End,
                exitCode: entry.ExitCode,
                output: entry.Output.trim().slice(0, 2000),
              })),
            },
          }
        : {}),
    },
    restartCount: raw.RestartCount ?? 0,
    restartPolicy:
      policy?.Name && policy.Name !== "no"
        ? policy.Name === "on-failure" && policy.MaximumRetryCount
          ? `on-failure:${policy.MaximumRetryCount}`
          : policy.Name
        : "no",
    tty: raw.Config.Tty === true,
    platform: raw.Platform ?? "",
    networkMode: raw.HostConfig?.NetworkMode ?? "",
    privileged: raw.HostConfig?.Privileged === true,
    memoryLimit: raw.HostConfig?.Memory ?? 0,
    cpuLimit: (raw.HostConfig?.NanoCpus ?? 0) / 1e9,
    ports: bound.sort((a, b) => a.private - b.private),
    networks: Object.entries(raw.NetworkSettings?.Networks ?? {}).map(([name, network]) => ({
      name,
      ip: network.IPAddress ?? "",
      gateway: network.Gateway ?? "",
      mac: network.MacAddress ?? "",
      aliases: (network.Aliases ?? []).filter((alias) => !raw.Id.startsWith(alias)),
    })),
    mounts: (raw.Mounts ?? []).map((mount) => ({
      type: mount.Type,
      ...(mount.Name ? { name: mount.Name } : {}),
      source: mount.Source,
      destination: mount.Destination,
      rw: mount.RW,
    })),
    ...(raw.Config.Healthcheck?.Test ? { healthcheck: raw.Config.Healthcheck.Test } : {}),
    raw,
  };
}

export async function processes(docker: Docker, id: string): Promise<ProcessList> {
  try {
    const top = await docker.get<{ Titles?: string[]; Processes?: string[][] }>(
      `/containers/${encodeURIComponent(id)}/top`,
    );
    return { titles: top.Titles ?? [], processes: top.Processes ?? [] };
  } catch (error) {
    // A container that is not running has no processes, which is not a failure to show.
    if (error instanceof DockerError && error.status === 409) return { titles: [], processes: [] };
    throw error;
  }
}

// ---- resource use ----------------------------------------------------------------------

interface RawStats {
  read: string;
  cpu_stats?: {
    cpu_usage?: { total_usage?: number };
    system_cpu_usage?: number;
    online_cpus?: number;
  };
  memory_stats?: { usage?: number; limit?: number; stats?: Record<string, number> };
  networks?: Record<string, { rx_bytes: number; tx_bytes: number }>;
  blkio_stats?: { io_service_bytes_recursive?: { op: string; value: number }[] | null };
  pids_stats?: { current?: number };
}

interface Counters {
  at: number;
  cpu: number;
  system: number;
  rx: number;
  tx: number;
  read: number;
  write: number;
}

/** How many samples of each container are kept for the charts: two minutes at one a second. */
const HISTORY = 120;

/**
 * Samples the resource use of running containers. The engine's one-shot stats
 * carry the counters and not the rates, so the rates are worked out here from the
 * previous sample of the same container, the way `docker stats` does with two.
 */
export class StatsSampler {
  readonly #previous = new Map<string, Counters>();
  readonly #history = new Map<string, StatsSample[]>();
  #sampling: Promise<Record<string, ContainerStats>> | undefined;

  constructor(readonly docker: Docker) {}

  /** One sample of each of `ids`; a sampling that is under way is shared, not repeated. */
  sample(ids: readonly string[]): Promise<Record<string, ContainerStats>> {
    this.#sampling ??= this.#sample(ids).finally(() => {
      this.#sampling = undefined;
    });
    return this.#sampling;
  }

  history(): Record<string, StatsSample[]> {
    return Object.fromEntries(this.#history);
  }

  async #sample(ids: readonly string[]): Promise<Record<string, ContainerStats>> {
    const out: Record<string, ContainerStats> = {};
    await Promise.all(
      ids.map(async (id) => {
        try {
          const raw = await this.docker.get<RawStats>(
            `/containers/${id}/stats?stream=false&one-shot=true`,
            5000,
          );
          out[id] = this.#rates(id, raw);
        } catch {
          // A container that stopped between the list and the sample has none.
        }
      }),
    );
    for (const id of this.#previous.keys()) {
      if (!ids.includes(id)) {
        this.#previous.delete(id);
        this.#history.delete(id);
      }
    }
    return out;
  }

  #rates(id: string, raw: RawStats): ContainerStats {
    const at = Date.parse(raw.read) || Date.now();
    const network = Object.values(raw.networks ?? {});
    const blocks = raw.blkio_stats?.io_service_bytes_recursive ?? [];
    const now: Counters = {
      at,
      cpu: raw.cpu_stats?.cpu_usage?.total_usage ?? 0,
      system: raw.cpu_stats?.system_cpu_usage ?? 0,
      rx: network.reduce((sum, n) => sum + n.rx_bytes, 0),
      tx: network.reduce((sum, n) => sum + n.tx_bytes, 0),
      read: blocks
        .filter((b) => b.op.toLowerCase() === "read")
        .reduce((sum, b) => sum + b.value, 0),
      write: blocks
        .filter((b) => b.op.toLowerCase() === "write")
        .reduce((sum, b) => sum + b.value, 0),
    };
    const before = this.#previous.get(id);
    this.#previous.set(id, now);
    const seconds = before ? Math.max((now.at - before.at) / 1000, 0.001) : 1;
    const rate = (a: number, b: number | undefined) =>
      b === undefined ? 0 : Math.max(0, (a - b) / seconds);
    const cpus = raw.cpu_stats?.online_cpus ?? 1;
    const systemDelta = before ? now.system - before.system : 0;
    const cpu =
      before && systemDelta > 0
        ? Math.max(0, ((now.cpu - before.cpu) / systemDelta) * cpus * 100)
        : null;
    const memoryStats = raw.memory_stats?.stats ?? {};
    // What `docker stats` shows: the usage less the page cache the kernel can take back.
    const cache = memoryStats.inactive_file ?? memoryStats.total_inactive_file ?? 0;
    const memory = Math.max(0, (raw.memory_stats?.usage ?? 0) - cache);
    const stats: ContainerStats = {
      cpu,
      memory,
      memoryLimit: raw.memory_stats?.limit ?? 0,
      netRx: rate(now.rx, before?.rx),
      netTx: rate(now.tx, before?.tx),
      blockRead: rate(now.read, before?.read),
      blockWrite: rate(now.write, before?.write),
      pids: raw.pids_stats?.current ?? 0,
    };
    const samples = this.#history.get(id) ?? [];
    samples.push({ t: at, cpu, memory, netRx: stats.netRx, netTx: stats.netTx });
    if (samples.length > HISTORY) samples.splice(0, samples.length - HISTORY);
    this.#history.set(id, samples);
    return stats;
  }
}

// ---- logs ------------------------------------------------------------------------------

/** Whether each container has a tty, which decides whether its log stream is multiplexed. */
const ttys = new Map<string, boolean>();

/** At most this many lines in one answer: the view asks again for what follows. */
const MOST_LINES = 1500;
/** And at most this many characters of one line. */
const LONGEST_LINE = 4000;

export async function readLogs(
  docker: Docker,
  id: string,
  since: string | null | undefined,
  tail: number,
): Promise<LogsChunk> {
  let tty = ttys.get(id);
  if (tty === undefined) {
    tty = (await inspectContainer(docker, id)).tty;
  }
  const after = since ? nextInstant(since) : undefined;
  const body = await docker.call(
    "GET",
    `/containers/${encodeURIComponent(id)}/logs` +
      query({
        stdout: 1,
        stderr: 1,
        timestamps: 1,
        ...(after ? { since: after } : { tail }),
      }),
    { timeout: 10_000 },
  );
  const lines: LogLine[] = [];
  const take = (stream: "out" | "err", payload: Buffer) => {
    for (const line of payload.toString("utf8").split("\n")) {
      if (line === "") continue;
      const space = line.indexOf(" ");
      const time = space > 0 ? line.slice(0, space) : "";
      let text = space > 0 ? line.slice(space + 1) : line;
      if (text.endsWith("\r")) text = text.slice(0, -1);
      if (text.length > LONGEST_LINE) text = `${text.slice(0, LONGEST_LINE)}…`;
      lines.push({ time, stream, text });
    }
  };
  if (tty) take("out", body);
  else new Demuxer(take).push(body);
  const kept = lines.length > MOST_LINES ? lines.slice(-MOST_LINES) : lines;
  const last = kept.at(-1)?.time ?? since ?? null;
  return { id, lines: kept, cursor: last, reset: !since };
}

/**
 * The engine's `since` takes `seconds.nanoseconds` and includes the instant it names;
 * the line at the cursor was read already, so the next read starts a nanosecond later.
 */
function nextInstant(time: string): string | undefined {
  const match = /^(.*T\d\d:\d\d:\d\d)(?:\.(\d+))?(Z|[+-]\d\d:\d\d)$/.exec(time);
  if (!match) return undefined;
  const seconds = Math.floor(Date.parse(`${match[1]}${match[3]}`) / 1000);
  if (!Number.isFinite(seconds)) return undefined;
  const nanos = Number((match[2] ?? "0").padEnd(9, "0").slice(0, 9)) + 1;
  return nanos >= 1e9 ? `${seconds + 1}.000000000` : `${seconds}.${String(nanos).padStart(9, "0")}`;
}

// ---- actions ---------------------------------------------------------------------------

/** How long a container is given to stop before it is killed, in seconds: Docker's own default. */
const STOP_GRACE = 10;

export async function act(
  docker: Docker,
  id: string,
  action: "start" | "stop" | "restart" | "pause" | "unpause" | "kill" | "remove",
  options: { force?: boolean; volumes?: boolean } = {},
): Promise<void> {
  const path = `/containers/${encodeURIComponent(id)}`;
  // A start of a running container and a stop of a stopped one are 304: done already.
  const accept = [304];
  const grace = (STOP_GRACE + 15) * 1000;
  switch (action) {
    case "start":
      await docker.call("POST", `${path}/start`, { accept, timeout: 30_000 });
      return;
    case "stop":
      await docker.call("POST", `${path}/stop${query({ t: STOP_GRACE })}`, {
        accept,
        timeout: grace,
      });
      return;
    case "restart":
      await docker.call("POST", `${path}/restart${query({ t: STOP_GRACE })}`, { timeout: grace });
      return;
    case "pause":
      await docker.call("POST", `${path}/pause`, { timeout: 15_000 });
      return;
    case "unpause":
      await docker.call("POST", `${path}/unpause`, { timeout: 15_000 });
      return;
    case "kill":
      await docker.call("POST", `${path}/kill`, { timeout: 15_000 });
      return;
    case "remove":
      await docker.call(
        "DELETE",
        `${path}${query({ force: options.force === true, v: options.volumes === true })}`,
        { timeout: grace },
      );
      ttys.delete(id);
      return;
  }
}
