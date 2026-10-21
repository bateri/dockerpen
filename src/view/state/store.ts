/**
 * The view's state, in one store: what the program last said (the engine, the
 * containers and their use, events, logs, jobs) and what the person is doing
 * (where they are, what they chose, what is open over the page).
 */

import { create } from "zustand";

import type {
  Boot,
  ContainerAction,
  ContainerDetail,
  ContainerStats,
  ContainerSummary,
  DiskUsage,
  DockerEvent,
  Engine,
  ImageSummary,
  Job,
  LogLine,
  NetworkSummary,
  PollResult,
  PruneTarget,
  Section,
  StatsSample,
  UiState,
  VolumeSummary,
} from "../../server/types";

export type Tone = "info" | "success" | "warning" | "danger";

export interface Toast {
  id: number;
  tone: Tone;
  title: string;
  body?: string;
  action?: { label: string; run: () => void };
  /** Milliseconds it stays; 0 keeps it until it is closed. */
  timeout: number;
}

export interface ConfirmOption {
  key: string;
  label: string;
  hint?: string;
  value: boolean;
}

export type Dialog =
  | {
      kind: "confirm";
      title: string;
      body: string;
      confirm: string;
      tone: "danger" | "default";
      options?: ConfirmOption[];
      onConfirm: (options: Record<string, boolean>) => void;
    }
  | { kind: "pull"; initial?: string }
  | { kind: "prune"; preset?: PruneTarget[] };

export type MenuEntry =
  | {
      label: string;
      icon?: React.ComponentType<{ size?: number }>;
      shortcut?: string;
      tone?: "danger";
      disabled?: boolean;
      hint?: string;
      run: () => void;
    }
  | "separator";

export interface Menu {
  x: number;
  y: number;
  /** Where the menu was opened from, for its transform origin. */
  origin?: "pointer" | "anchor";
  entries: MenuEntry[];
}

export type Ui = Required<Omit<UiState, "detail" | "logs">> & {
  detail: string | null;
  logs: { timestamps: boolean; wrap: boolean; follow: boolean };
};

export const DEFAULT_UI: Ui = {
  section: "containers",
  selected: "",
  detail: null,
  tab: "overview",
  filter: "all",
  query: "",
  groupByProject: true,
  sort: "name",
  collapsed: [],
  panelWidth: 0.46,
  logs: { timestamps: false, wrap: true, follow: true },
};

/** How many samples the charts keep, at one a second. */
const HISTORY = 120;
/** How many lines of a container's log are kept. */
const LOG_LINES = 5000;

export interface Totals {
  t: number;
  cpu: number;
  memory: number;
}

export interface State {
  status: "connecting" | "ready";
  boot: Boot | null;
  canHandOff: boolean;
  engine: Engine | null;
  containers: ContainerSummary[];
  stats: Record<string, ContainerStats>;
  history: Record<string, StatsSample[]>;
  totals: Totals[];
  events: DockerEvent[];
  eventsCursor: number;
  /** Events that came after the view started: the ones that may make a toast. */
  liveFrom: number;
  jobs: Job[];
  logs: { id: string | null; lines: LogLine[]; cursor: string | null; dropped: number };
  details: Record<string, ContainerDetail>;
  images: ImageSummary[] | null;
  volumes: VolumeSummary[] | null;
  volumesSized: boolean;
  networks: NetworkSummary[] | null;
  disk: DiskUsage | null;
  ui: Ui;
  marked: string[];
  pending: Record<string, ContainerAction>;
  flash: { id: string; at: number } | null;
  handingOff: { kind: "shell" | "logs"; name: string } | null;
  /** The host is taking the view down. */
  leaving: boolean;
  toasts: Toast[];
  dialog: Dialog | null;
  menu: Menu | null;
  palette: boolean;
  help: boolean;
  focus: "list" | "detail";
  /** The chosen row of each section that is not the containers'. */
  pick: { images: string; volumes: string; networks: string; activity: number };
  lastPoll: number;
}

export const useStore = create<State>(() => ({
  status: "connecting",
  boot: null,
  canHandOff: false,
  engine: null,
  containers: [],
  stats: {},
  history: {},
  totals: [],
  events: [],
  eventsCursor: -1,
  liveFrom: Number.POSITIVE_INFINITY,
  jobs: [],
  logs: { id: null, lines: [], cursor: null, dropped: 0 },
  details: {},
  images: null,
  volumes: null,
  volumesSized: false,
  networks: null,
  disk: null,
  ui: DEFAULT_UI,
  marked: [],
  pending: {},
  flash: null,
  handingOff: null,
  leaving: false,
  toasts: [],
  dialog: null,
  menu: null,
  palette: false,
  help: false,
  focus: "list",
  pick: { images: "", volumes: "", networks: "", activity: -1 },
  lastPoll: 0,
}));

export const get = useStore.getState;
export const set = useStore.setState;

// ---- the program's answers ------------------------------------------------------------

export function applyBoot(boot: Boot, poll: PollResult & { handoff?: boolean }): void {
  const ui: Ui = {
    ...DEFAULT_UI,
    ...boot.ui,
    detail: boot.ui.detail ?? null,
    logs: { ...DEFAULT_UI.logs, ...boot.ui.logs },
  };
  if (boot.ui.collapsed === undefined) {
    // On a first start, projects with nothing running are folded away.
    const projects = new Set(poll.containers.flatMap((c) => (c.project ? [c.project] : [])));
    ui.collapsed = [...projects].filter(
      (project) => !poll.containers.some((c) => c.project === project && c.state === "running"),
    );
  }
  set({ boot, ui, status: "ready" });
  applyPoll(poll);
  // Everything already in the feed is history; what comes next is news.
  set({ liveFrom: get().eventsCursor });
}

type EventHook = (events: DockerEvent[]) => void;
let onLiveEvents: EventHook | undefined;

export function onEvents(hook: EventHook): void {
  onLiveEvents = hook;
}

export function applyPoll(poll: PollResult & { handoff?: boolean }): void {
  const state = get();
  const history = { ...state.history };
  if (poll.history) {
    for (const [id, samples] of Object.entries(poll.history)) history[id] = samples.slice(-HISTORY);
  } else {
    for (const [id, stats] of Object.entries(poll.stats)) {
      const samples = history[id] ? [...history[id]] : [];
      if (samples.at(-1)?.t !== poll.at) {
        samples.push({
          t: poll.at,
          cpu: stats.cpu,
          memory: stats.memory,
          netRx: stats.netRx,
          netTx: stats.netTx,
        });
      }
      history[id] = samples.length > HISTORY ? samples.slice(-HISTORY) : samples;
    }
  }
  for (const id of Object.keys(history)) {
    if (!poll.containers.some((c) => c.id === id && c.state === "running")) delete history[id];
  }

  const values = Object.values(poll.stats);
  // A view that starts with the program's history starts its totals from it too: the
  // sampler reads every running container at once, so the samples line up from the end.
  if (poll.history && state.totals.length === 0) {
    const series = Object.values(poll.history);
    const longest = Math.max(0, ...series.map((s) => s.length));
    const rebuilt: Totals[] = [];
    for (let back = longest - 1; back >= 1; back -= 1) {
      let cpu = 0;
      let memory = 0;
      let t = 0;
      for (const samples of series) {
        const sample = samples[samples.length - 1 - back];
        if (!sample) continue;
        cpu += sample.cpu ?? 0;
        memory += sample.memory;
        t = Math.max(t, sample.t);
      }
      rebuilt.push({ t, cpu, memory });
    }
    state.totals = rebuilt;
  }
  const totals =
    values.length === 0 && poll.containers.every((c) => c.state !== "running")
      ? [...state.totals, { t: poll.at, cpu: 0, memory: 0 }]
      : values.some((v) => v.cpu !== null)
        ? [
            ...state.totals,
            {
              t: poll.at,
              cpu: values.reduce((sum, v) => sum + (v.cpu ?? 0), 0),
              memory: values.reduce((sum, v) => sum + v.memory, 0),
            },
          ]
        : state.totals;

  const fresh = poll.events.items.filter((event) => event.seq > state.eventsCursor);
  const events = fresh.length === 0 ? state.events : [...state.events, ...fresh].slice(-400);

  let logs = state.logs;
  if (poll.logs) {
    const chunk = poll.logs;
    if (chunk.reset || chunk.id !== state.logs.id) {
      logs = {
        id: chunk.id,
        lines: chunk.lines.slice(-LOG_LINES),
        cursor: chunk.cursor,
        dropped: 0,
      };
    } else if (chunk.lines.length > 0) {
      const lines = [...state.logs.lines, ...chunk.lines];
      const over = Math.max(0, lines.length - LOG_LINES);
      logs = {
        id: chunk.id,
        lines: over > 0 ? lines.slice(over) : lines,
        cursor: chunk.cursor,
        dropped: state.logs.dropped + over,
      };
    } else if (chunk.cursor !== state.logs.cursor) {
      logs = { ...state.logs, cursor: chunk.cursor };
    }
  }

  // A choice that names a container that is gone falls on its neighbour, so the
  // keyboard always has somewhere to be.
  const ids = new Set(poll.containers.map((c) => c.id));
  const marked = state.marked.filter((id) => ids.has(id));

  set({
    engine: poll.engine,
    containers: poll.containers,
    stats: poll.stats,
    history,
    totals: totals.slice(-HISTORY),
    events,
    eventsCursor: poll.events.cursor,
    jobs: poll.jobs,
    logs,
    marked: marked.length === state.marked.length ? state.marked : marked,
    lastPoll: poll.at,
    ...(poll.handoff !== undefined ? { canHandOff: poll.handoff } : {}),
  });

  if (state.status === "ready" && fresh.length > 0) {
    const live = fresh.filter((event) => event.seq > state.liveFrom);
    if (live.length > 0) onLiveEvents?.(live);
  }
}

// ---- what the person does ---------------------------------------------------------------

export function setUi(patch: Partial<Ui>): void {
  set((state) => ({ ui: { ...state.ui, ...patch } }));
}

export function go(section: Section): void {
  const state = get();
  if (state.ui.section === section) return;
  set({ ui: { ...state.ui, section }, focus: "list", menu: null });
}

let toastId = 1;

export function toast(
  tone: Tone,
  title: string,
  extra: { body?: string; action?: Toast["action"]; timeout?: number } = {},
): number {
  const id = toastId++;
  const timeout = extra.timeout ?? (tone === "danger" ? 9000 : 4500);
  set((state) => ({
    toasts: [...state.toasts, { id, tone, title, timeout, ...extra }].slice(-4),
  }));
  return id;
}

export function dismissToast(id: number): void {
  set((state) => ({ toasts: state.toasts.filter((t) => t.id !== id) }));
}

export function openMenu(menu: Menu): void {
  set({ menu });
}

export function closeOverlays(): boolean {
  const state = get();
  if (state.menu) return (set({ menu: null }), true);
  if (state.palette) return (set({ palette: false }), true);
  if (state.help) return (set({ help: false }), true);
  if (state.dialog) return (set({ dialog: null }), true);
  return false;
}

export function pick(section: keyof State["pick"], value: string | number): void {
  set((state) => ({ pick: { ...state.pick, [section]: value } }));
}

export function flash(id: string): void {
  set({ flash: { id, at: Date.now() } });
}

// What closes gives the keyboard back at once: a field of the palette or of a dialog keeps
// the focus while it fades out, and would take for typing the keys that come meanwhile.
useStore.subscribe((state, previous) => {
  const closed =
    (previous.palette && !state.palette) || (previous.dialog !== null && state.dialog === null);
  const active = document.activeElement;
  if (closed && active instanceof HTMLElement && active.closest(".overlay")) active.blur();
});
