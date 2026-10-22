/**
 * What the server sends the view, and what the view sends back. The view imports
 * these as types only, so this file has no runtime part.
 */

export type Section = "containers" | "images" | "volumes" | "networks" | "system" | "activity";

export type ContainerState =
  "running" | "exited" | "paused" | "restarting" | "created" | "removing" | "dead";

export type Health = "healthy" | "unhealthy" | "starting" | "none";

export interface PortBinding {
  ip?: string;
  /** The port on the host, when it is published. */
  public?: number;
  private: number;
  type: string;
}

export interface ContainerSummary {
  id: string;
  name: string;
  image: string;
  imageId: string;
  command: string;
  /** Unix seconds. */
  created: number;
  state: ContainerState;
  /** Docker's own words: "Up 2 hours (healthy)", "Exited (137) 3 days ago". */
  status: string;
  health: Health;
  /** The exit code, for a container that exited. */
  exitCode?: number;
  ports: PortBinding[];
  /** The compose project and service, when compose made it. */
  project?: string;
  service?: string;
  networks: string[];
  mounts: { type: string; name?: string; source?: string; destination: string }[];
}

export interface ContainerStats {
  /** Percent of one CPU, as `docker stats` counts it: a container that keeps two cores busy is at 200. */
  cpu: number | null;
  memory: number;
  memoryLimit: number;
  /** Bytes per second since the previous sample. */
  netRx: number;
  netTx: number;
  blockRead: number;
  blockWrite: number;
  pids: number;
}

/** One sample of a container's history, for the charts. */
export interface StatsSample {
  /** Milliseconds since the epoch. */
  t: number;
  cpu: number | null;
  memory: number;
  netRx: number;
  netTx: number;
}

export interface EngineInfo {
  ok: true;
  /** What runs the engine, in its own words: "OrbStack", "Docker Desktop", "Ubuntu 24.04 LTS". */
  name: string;
  hostname: string;
  version: string;
  apiVersion: string;
  os: string;
  arch: string;
  cpus: number;
  memory: number;
  endpoint: string;
  /** Whether the docker command is installed: the shell and the log follower need it. */
  cli: boolean;
  /** Whether `docker compose` answers. */
  compose: boolean;
}

export interface EngineDown {
  ok: false;
  endpoint: string;
  error: string;
}

export type Engine = EngineInfo | EngineDown;

export interface DockerEvent {
  seq: number;
  /** Milliseconds since the epoch. */
  time: number;
  type: string;
  action: string;
  id: string;
  name?: string;
  /** A few of the event's attributes: the image, an exit code, a signal. */
  detail: Record<string, string>;
}

export interface LogLine {
  /** The time Docker gives the line, RFC 3339 with nanoseconds. */
  time: string;
  stream: "out" | "err";
  text: string;
}

export interface LogsChunk {
  id: string;
  lines: LogLine[];
  /** What to ask with next, to get only what comes after. */
  cursor: string | null;
  /** The answer starts over (the first read, or the container was replaced). */
  reset: boolean;
}

export type JobState = "running" | "done" | "failed";

export interface Job {
  id: string;
  kind: "pull" | "prune" | "compose";
  title: string;
  state: JobState;
  /** 0 to 1, when it is known. */
  progress: number | null;
  detail: string;
  started: number;
  ended?: number;
  error?: string;
}

/** A hand-off of the pane to a command in the terminal: a shell in a container, its logs. */
export interface Handoff {
  kind: "shell" | "logs";
  id: string;
  name: string;
  exitCode: number | null;
  /** Milliseconds the command ran. */
  duration: number;
  error?: string;
}

export interface UiState {
  section?: Section;
  selected?: string;
  detail?: string | null;
  tab?: DetailTab;
  filter?: ContainerFilter;
  query?: string;
  groupByProject?: boolean;
  sort?: SortKey;
  collapsed?: string[];
  panelWidth?: number;
  logs?: { timestamps?: boolean; wrap?: boolean; follow?: boolean };
}

export type DetailTab = "overview" | "logs" | "env" | "processes" | "inspect";
export type ContainerFilter = "all" | "running" | "stopped" | "issues";
export type SortKey = "name" | "state" | "cpu" | "memory" | "created";

export interface PollResult {
  at: number;
  engine: Engine;
  containers: ContainerSummary[];
  stats: Record<string, ContainerStats>;
  history?: Record<string, StatsSample[]>;
  events: { cursor: number; items: DockerEvent[] };
  logs?: LogsChunk;
  jobs: Job[];
  /** A hand-off the view asked for and the terminal could not make. */
  handoffFailed?: string;
}

export interface Boot {
  ui: UiState;
  /** What the pane was handed to, when the view comes back from it. */
  returned?: Handoff;
}

export interface ContainerDetail {
  id: string;
  name: string;
  image: string;
  imageId: string;
  created: string;
  path: string;
  args: string[];
  entrypoint: string[];
  cmd: string[];
  workingDir: string;
  user: string;
  env: { key: string; value: string }[];
  labels: Record<string, string>;
  state: {
    status: ContainerState;
    running: boolean;
    paused: boolean;
    restarting: boolean;
    oomKilled: boolean;
    dead: boolean;
    pid: number;
    exitCode: number;
    error: string;
    startedAt: string;
    finishedAt: string;
    health?: {
      status: Health;
      failingStreak: number;
      log: { start: string; end: string; exitCode: number; output: string }[];
    };
  };
  restartCount: number;
  restartPolicy: string;
  tty: boolean;
  platform: string;
  networkMode: string;
  privileged: boolean;
  memoryLimit: number;
  cpuLimit: number;
  ports: PortBinding[];
  networks: { name: string; ip: string; gateway: string; mac: string; aliases: string[] }[];
  mounts: { type: string; name?: string; source: string; destination: string; rw: boolean }[];
  healthcheck?: string[];
  raw: unknown;
}

export interface ProcessList {
  titles: string[];
  processes: string[][];
}

export interface ImageSummary {
  id: string;
  tags: string[];
  digests: string[];
  created: number;
  size: number;
  /** Containers that were made from it, running or not. */
  containers: string[];
  dangling: boolean;
}

export interface ImageLayer {
  id: string;
  created: number;
  createdBy: string;
  size: number;
  comment: string;
}

export interface VolumeSummary {
  name: string;
  driver: string;
  mountpoint: string;
  created: string;
  labels: Record<string, string>;
  anonymous: boolean;
  project?: string;
  /** Bytes, once Docker has counted them; -1 while it has not. */
  size: number;
  containers: string[];
}

export interface NetworkSummary {
  id: string;
  name: string;
  driver: string;
  scope: string;
  internal: boolean;
  subnets: string[];
  gateways: string[];
  created: string;
  builtin: boolean;
  project?: string;
  containers: string[];
}

export interface DiskUsage {
  images: { count: number; active: number; size: number; reclaimable: number };
  containers: { count: number; active: number; size: number; reclaimable: number };
  volumes: { count: number; active: number; size: number; reclaimable: number };
  buildCache: { count: number; active: number; size: number; reclaimable: number };
}

export type PruneTarget =
  "containers" | "danglingImages" | "unusedImages" | "volumes" | "networks" | "buildCache";

export type ContainerAction =
  "start" | "stop" | "restart" | "pause" | "unpause" | "kill" | "remove";

export interface ActionOutcome {
  id: string;
  name: string;
  ok: boolean;
  error?: string;
}
