/**
 * What the view asks of its program: the poll that keeps it current, and every
 * action a button, a key, a menu or the palette can take. One function per action,
 * so that all four ways in do the same thing.
 */

import type {
  ActionOutcome,
  ContainerAction,
  ContainerDetail,
  ContainerSummary,
  DiskUsage,
  ImageSummary,
  Job,
  NetworkSummary,
  PollResult,
  PruneTarget,
  VolumeSummary,
} from "../../server/types";
import { call, copy, openLink } from "../lib/bridge";
import { duration, imageName, shortId } from "../lib/format";
import { applyPoll, get, set, setUi, toast } from "./store";

// ---- the poll ---------------------------------------------------------------------------

let wake: (() => void) | undefined;
let running = false;

/** Polls the program for as long as the view lives: once a second, slower when Docker is away. */
export function startPolling(): void {
  if (running) return;
  running = true;
  void (async () => {
    for (;;) {
      const started = Date.now();
      try {
        await pollOnce();
      } catch {
        // A poll that failed is followed by the next one; the view keeps what it had.
      }
      const state = get();
      const wait = state.engine && !state.engine.ok ? 2500 : document.hidden ? 4000 : 1000;
      await new Promise<void>((resolve) => {
        const timer = setTimeout(resolve, Math.max(150, wait - (Date.now() - started)));
        wake = () => {
          clearTimeout(timer);
          resolve();
        };
      });
      wake = undefined;
    }
  })();
}

/** Polls now instead of at the next second: after an action, or when the logs are opened. */
export function pollNow(): void {
  wake?.();
}

async function pollOnce(): Promise<void> {
  const state = get();
  const { ui } = state;
  const logsOf =
    ui.section === "containers" && ui.detail && ui.tab === "logs"
      ? state.containers.find((c) => c.id === ui.detail)
      : undefined;
  const logs = logsOf
    ? {
        id: logsOf.id,
        since: state.logs.id === logsOf.id ? state.logs.cursor : null,
        tail: 500,
      }
    : undefined;
  const result = await call<PollResult & { handoff?: boolean }>("dockerpen_poll", {
    events: state.eventsCursor,
    ...(logs ? { logs } : {}),
    ui: persistedUi(),
  });
  applyPoll(result);
  if (result.handoffFailed) {
    set({ handingOff: null });
    toast("warning", "The pane stayed with the view", { body: result.handoffFailed });
  }
  for (const job of result.jobs) watchJob(job);
}

/** What the view is doing, which the program keeps for the next view: one after a shell, or a restart. */
function persistedUi() {
  return get().ui;
}

// ---- jobs -------------------------------------------------------------------------------

const announced = new Set<string>();
const following = new Set<string>();

function watchJob(job: Job): void {
  if (job.state === "running") {
    following.add(job.id);
    return;
  }
  if (!following.has(job.id) || announced.has(job.id)) return;
  announced.add(job.id);
  if (job.state === "done") toast("success", job.title, { body: job.detail });
  else toast("danger", `${job.title} failed`, { body: job.error ?? job.detail });
  // What a job changed is read again.
  if (job.kind === "pull") void loadImages();
  if (job.kind === "prune") {
    void loadDisk();
    void loadImages();
    void loadVolumes(true);
    void loadNetworks();
  }
}

function track(job: Job): void {
  following.add(job.id);
  set((state) => ({ jobs: [...state.jobs.filter((j) => j.id !== job.id), job] }));
  pollNow();
}

// ---- containers -------------------------------------------------------------------------

const VERBS: Record<ContainerAction, { doing: string; done: string; failed: string }> = {
  start: { doing: "Starting", done: "Started", failed: "start" },
  stop: { doing: "Stopping", done: "Stopped", failed: "stop" },
  restart: { doing: "Restarting", done: "Restarted", failed: "restart" },
  pause: { doing: "Pausing", done: "Paused", failed: "pause" },
  unpause: { doing: "Resuming", done: "Resumed", failed: "resume" },
  kill: { doing: "Killing", done: "Killed", failed: "kill" },
  remove: { doing: "Removing", done: "Removed", failed: "remove" },
};

export function verbOf(action: ContainerAction) {
  return VERBS[action];
}

/** Containers the person or the program recently acted on: their events are not news. */
const actedOn = new Map<string, number>();

export function recentlyActedOn(id: string): boolean {
  const at = actedOn.get(id);
  return at !== undefined && Date.now() - at < 30_000;
}

export async function act(
  containers: readonly ContainerSummary[],
  action: ContainerAction,
  options: { force?: boolean; volumes?: boolean; quiet?: boolean } = {},
): Promise<void> {
  const targets = containers.filter((c) => !get().pending[c.id]);
  if (targets.length === 0) return;
  const now = Date.now();
  for (const c of targets) actedOn.set(c.id, now);
  set((state) => ({
    pending: { ...state.pending, ...Object.fromEntries(targets.map((c) => [c.id, action])) },
  }));
  const verb = VERBS[action];
  try {
    const { outcomes } = await call<{ outcomes: ActionOutcome[] }>("container_action", {
      ids: targets.map((c) => c.id),
      action,
      ...(options.force ? { force: true } : {}),
      ...(options.volumes ? { volumes: true } : {}),
    });
    const failed = outcomes.filter((o) => !o.ok);
    const done = outcomes.filter((o) => o.ok);
    if (failed.length > 0) {
      toast("danger", `Could not ${verb.failed} ${failed.map((o) => o.name).join(", ")}`, {
        body: failed[0]?.error,
      });
    }
    if (done.length > 0 && !options.quiet) {
      const names = done.map((o) => o.name);
      const title =
        names.length === 1 ? `${verb.done} ${names[0]}` : `${verb.done} ${names.length} containers`;
      const undo =
        action === "stop" || action === "pause"
          ? {
              label: action === "stop" ? "Start again" : "Resume",
              run: () => {
                const again = get().containers.filter((c) => done.some((o) => o.id === c.id));
                void act(again, action === "stop" ? "start" : "unpause");
              },
            }
          : undefined;
      toast("success", title, undo ? { action: undo } : {});
    }
    if (action === "remove") {
      const removed = new Set(done.map((o) => o.id));
      const { ui, marked } = get();
      set({ marked: marked.filter((id) => !removed.has(id)) });
      if (ui.detail && removed.has(ui.detail)) setUi({ detail: null });
    }
  } catch (error) {
    toast("danger", `Could not ${verb.failed} ${targets.map((c) => c.name).join(", ")}`, {
      body: error instanceof Error ? error.message : String(error),
    });
  } finally {
    set((state) => {
      const pending = { ...state.pending };
      for (const c of targets) delete pending[c.id];
      return { pending };
    });
    // The new state is read at once, so the row turns as the action ends.
    pollNow();
  }
}

/** Start what is stopped, stop what runs. */
export function toggle(containers: readonly ContainerSummary[]): void {
  const running = containers.filter((c) => c.state === "running" || c.state === "restarting");
  const paused = containers.filter((c) => c.state === "paused");
  const stopped = containers.filter(
    (c) => !running.includes(c) && !paused.includes(c) && c.state !== "removing",
  );
  if (running.length > 0) void act(running, "stop");
  if (paused.length > 0) void act(paused, "unpause");
  if (stopped.length > 0) void act(stopped, "start");
}

export function pauseToggle(containers: readonly ContainerSummary[]): void {
  const paused = containers.filter((c) => c.state === "paused");
  const running = containers.filter((c) => c.state === "running");
  if (paused.length > 0) void act(paused, "unpause");
  if (running.length > 0) void act(running, "pause");
}

export function askRemove(containers: readonly ContainerSummary[]): void {
  if (containers.length === 0) return;
  const running = containers.filter((c) => c.state === "running" || c.state === "paused");
  const one = containers.length === 1 ? containers[0]! : undefined;
  set({
    dialog: {
      kind: "confirm",
      title: one ? `Remove ${one.name}?` : `Remove ${containers.length} containers?`,
      body:
        (one
          ? `The container and its writable layer go; the image ${imageName(one.image)} stays.`
          : "The containers and their writable layers go; their images stay.") +
        (running.length > 0
          ? ` ${running.length === 1 && one ? "It is" : `${running.length} are`} running and will be stopped first.`
          : ""),
      confirm: "Remove",
      tone: "danger",
      options: [
        {
          key: "volumes",
          label: "Also remove anonymous volumes",
          hint: "Named volumes are kept either way",
          value: false,
        },
      ],
      onConfirm: (values) =>
        void act(containers, "remove", { force: running.length > 0, volumes: values.volumes }),
    },
  });
}

export function askKill(containers: readonly ContainerSummary[]): void {
  const live = containers.filter((c) => c.state === "running" || c.state === "paused");
  if (live.length === 0) return;
  set({
    dialog: {
      kind: "confirm",
      title: live.length === 1 ? `Kill ${live[0]!.name}?` : `Kill ${live.length} containers?`,
      body: "SIGKILL ends the main process at once, with no chance to clean up. Stop asks first.",
      confirm: "Kill",
      tone: "danger",
      onConfirm: () => void act(live, "kill"),
    },
  });
}

export async function loadDetail(id: string): Promise<ContainerDetail | undefined> {
  try {
    const detail = await call<ContainerDetail>("container_detail", { id });
    set((state) => ({ details: { ...state.details, [id]: detail } }));
    return detail;
  } catch {
    return undefined;
  }
}

/** Hands the pane to a shell in the container, or to its logs as they come. */
export async function openInTerminal(
  container: ContainerSummary,
  kind: "shell" | "logs",
): Promise<void> {
  const state = get();
  if (state.handingOff) return;
  if (kind === "shell" && container.state !== "running") {
    toast("warning", `${container.name} is not running`, {
      body: "A shell needs a running container.",
      action: { label: "Start it", run: () => void act([container], "start") },
    });
    return;
  }
  if (!state.canHandOff) {
    toast("info", "No terminal to hand over", {
      body: "dockerpen hands its pane to a shell when it runs in a terminal with the docker command.",
    });
    return;
  }
  set({ handingOff: { kind, name: container.name } });
  // A moment for the view to show what comes before the terminal takes the pane.
  await new Promise((resolve) => setTimeout(resolve, 260));
  try {
    const { state: answer } = await call<{ state: string }>("open_in_terminal", {
      kind,
      id: container.id,
    });
    if (answer !== "scheduled") {
      set({ handingOff: null });
      toast("info", "The pane stayed with the view", {
        body:
          answer === "busy"
            ? "A hand-over is already under way."
            : "There is no terminal to hand over.",
      });
    }
  } catch (error) {
    set({ handingOff: null });
    toast("danger", "Could not hand the pane over", {
      body: error instanceof Error ? error.message : String(error),
    });
  }
}

export function announceReturn(): void {
  const returned = get().boot?.returned;
  if (!returned) return;
  const what = returned.kind === "shell" ? `shell in ${returned.name}` : `logs of ${returned.name}`;
  if (returned.error) {
    toast("danger", `Could not open the ${what}`, { body: returned.error });
    return;
  }
  const code = returned.exitCode;
  toast(
    code === 0 || code === null || returned.kind === "logs" ? "info" : "warning",
    `Back from the ${what}`,
    {
      body: `${duration(returned.duration)}${returned.kind === "shell" && code !== null ? ` · exit ${code}` : ""}`,
    },
  );
  set({ flash: { id: returned.id, at: Date.now() } });
}

export function portUrl(port: {
  ip?: string;
  public?: number;
  private: number;
}): string | undefined {
  if (port.public === undefined) return undefined;
  const host = !port.ip || port.ip === "0.0.0.0" || port.ip === "::" ? "localhost" : port.ip;
  const bracketed = host.includes(":") ? `[${host}]` : host;
  return `http://${bracketed}:${port.public}`;
}

export async function openPort(port: {
  ip?: string;
  public?: number;
  private: number;
}): Promise<void> {
  const url = portUrl(port);
  if (!url) return;
  const ok = await openLink(url);
  if (!ok)
    toast("info", "The link stayed closed", { body: `${url} — the terminal did not open it.` });
}

export async function copyText(text: string, what: string): Promise<void> {
  const ok = await copy(text);
  if (ok)
    toast("success", `Copied ${what}`, {
      body: text.length > 80 ? `${text.slice(0, 80)}…` : text,
      timeout: 2200,
    });
  else toast("warning", "The clipboard is not reachable from here", { body: text });
}

// ---- images, volumes, networks, disk -----------------------------------------------------

export async function loadImages(): Promise<void> {
  try {
    const { images } = await call<{ images: ImageSummary[] }>("list_images");
    set({ images });
  } catch (error) {
    if (get().images === null) set({ images: [] });
    toast("danger", "Could not read the images", {
      body: String(error instanceof Error ? error.message : error),
    });
  }
}

export async function loadVolumes(sizes = false): Promise<void> {
  try {
    const result = await call<{ volumes: VolumeSummary[]; sized: boolean }>("list_volumes", {
      sizes,
    });
    set({ volumes: result.volumes, volumesSized: result.sized });
  } catch (error) {
    if (get().volumes === null) set({ volumes: [] });
    toast("danger", "Could not read the volumes", {
      body: String(error instanceof Error ? error.message : error),
    });
  }
}

export async function loadNetworks(): Promise<void> {
  try {
    const { networks } = await call<{ networks: NetworkSummary[] }>("list_networks");
    set({ networks });
  } catch (error) {
    if (get().networks === null) set({ networks: [] });
    toast("danger", "Could not read the networks", {
      body: String(error instanceof Error ? error.message : error),
    });
  }
}

export async function loadDisk(): Promise<void> {
  try {
    const { usage } = await call<{ usage: DiskUsage }>("disk_usage");
    set({ disk: usage });
  } catch (error) {
    toast("danger", "Could not count the disk", {
      body: String(error instanceof Error ? error.message : error),
    });
  }
}

export async function pullImage(reference: string): Promise<void> {
  try {
    const { job } = await call<{ job: Job }>("image_pull", { reference });
    track(job);
  } catch (error) {
    toast("danger", `Could not pull ${reference}`, {
      body: String(error instanceof Error ? error.message : error),
    });
  }
}

export async function prune(targets: PruneTarget[]): Promise<void> {
  try {
    const { job } = await call<{ job: Job }>("prune", { targets });
    track(job);
  } catch (error) {
    toast("danger", "Could not clean up", {
      body: String(error instanceof Error ? error.message : error),
    });
  }
}

async function removeMany(
  tool: string,
  key: "ids" | "names",
  values: string[],
  label: (value: string) => string,
  reload: () => Promise<void>,
  extra: Record<string, unknown> = {},
): Promise<void> {
  try {
    const { outcomes } = await call<{ outcomes: ActionOutcome[] }>(tool, {
      [key]: values,
      ...extra,
    });
    const failed = outcomes.filter((o) => !o.ok);
    const done = outcomes.length - failed.length;
    if (done > 0)
      toast(
        "success",
        done === 1 ? `Removed ${label(outcomes.find((o) => o.ok)!.id)}` : `Removed ${done}`,
      );
    if (failed.length > 0)
      toast("danger", `Could not remove ${label(failed[0]!.id)}`, { body: failed[0]!.error });
  } catch (error) {
    toast("danger", "Could not remove", {
      body: String(error instanceof Error ? error.message : error),
    });
  }
  await reload();
}

export function askRemoveImages(images: readonly ImageSummary[]): void {
  if (images.length === 0) return;
  const used = images.filter((image) => image.containers.length > 0);
  const name = (image: ImageSummary) =>
    image.tags[0] ? imageName(image.tags[0]) : shortId(image.id);
  set({
    dialog: {
      kind: "confirm",
      title:
        images.length === 1 ? `Remove ${name(images[0]!)}?` : `Remove ${images.length} images?`,
      body:
        used.length > 0
          ? `${used.map(name).join(", ")} ${used.length === 1 ? "is" : "are"} used by containers; removing needs force, and the containers keep running from layers they hold.`
          : "Layers no other image shares are deleted. A later run pulls the image again.",
      confirm: "Remove",
      tone: "danger",
      options:
        used.length > 0
          ? [{ key: "force", label: "Force, although containers use it", value: true }]
          : [],
      onConfirm: (values) =>
        void removeMany(
          "image_remove",
          "ids",
          images.map((image) => image.id),
          (id) => {
            const image = images.find((i) => i.id === id);
            return image ? name(image) : shortId(id);
          },
          loadImages,
          { force: values.force === true },
        ),
    },
  });
}

export function askRemoveVolumes(volumes: readonly VolumeSummary[]): void {
  const free = volumes.filter((v) => v.containers.length === 0);
  if (free.length === 0) {
    toast("info", "In use", {
      body: "A volume a container uses cannot be removed; remove the container first.",
    });
    return;
  }
  set({
    dialog: {
      kind: "confirm",
      title:
        free.length === 1
          ? `Remove volume ${free[0]!.anonymous ? shortId(free[0]!.name) : free[0]!.name}?`
          : `Remove ${free.length} volumes?`,
      body: "The data in them is deleted for good. There is no undo.",
      confirm: "Delete data",
      tone: "danger",
      onConfirm: () =>
        void removeMany(
          "volume_remove",
          "names",
          free.map((v) => v.name),
          (n) => (/^[0-9a-f]{64}$/.test(n) ? shortId(n) : n),
          () => loadVolumes(true),
        ),
    },
  });
}

export function askRemoveNetworks(networks: readonly NetworkSummary[]): void {
  const free = networks.filter((n) => !n.builtin && n.containers.length === 0);
  if (free.length === 0) {
    toast("info", "Nothing to remove", {
      body: "Built-in networks and networks with running containers stay.",
    });
    return;
  }
  set({
    dialog: {
      kind: "confirm",
      title:
        free.length === 1 ? `Remove network ${free[0]!.name}?` : `Remove ${free.length} networks?`,
      body: "Stopped containers attached to it lose the attachment.",
      confirm: "Remove",
      tone: "danger",
      onConfirm: () =>
        void removeMany(
          "network_remove",
          "ids",
          free.map((n) => n.id),
          (id) => networks.find((n) => n.id === id)?.name ?? shortId(id),
          loadNetworks,
        ),
    },
  });
}
