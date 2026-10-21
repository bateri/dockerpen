/**
 * Every command, once: the palette lists them, the keyboard runs them, the context
 * menu shows them, the status line hints at them. A command acts on the marked
 * containers when some are marked, and on the chosen row otherwise.
 */

import type { LucideIcon } from "lucide-react";
import {
  ArrowRightLeft,
  Box,
  Boxes,
  Copy,
  Download,
  ExternalLink,
  Eye,
  FolderTree,
  HardDrive,
  Keyboard,
  Layers,
  ListFilter,
  Network,
  Pause,
  Play,
  RefreshCw,
  RotateCw,
  ScrollText,
  Skull,
  Sparkles,
  Square,
  SquareTerminal,
  Trash2,
  Activity,
} from "lucide-react";

import type { ContainerSummary, Section } from "../../server/types";
import {
  act,
  askKill,
  askRemove,
  copyText,
  loadDisk,
  loadImages,
  loadNetworks,
  loadVolumes,
  openInTerminal,
  openPort,
  pauseToggle,
  pollNow,
  portUrl,
  toggle,
} from "./actions";
import { listModel, targets } from "./derive";
import type { Item } from "./derive";
import { get, go, set, setUi } from "./store";
import type { MenuEntry } from "./store";

export interface Command {
  id: string;
  title: string;
  /** The label in a context menu, where the container is already known. */
  short?: string;
  group: string;
  icon: LucideIcon;
  keys?: string;
  detail?: string;
  tone?: "danger";
  run: () => void;
}

export const SECTIONS: { id: Section; title: string; icon: LucideIcon; key: string }[] = [
  { id: "containers", title: "Containers", icon: Boxes, key: "1" },
  { id: "images", title: "Images", icon: Layers, key: "2" },
  { id: "volumes", title: "Volumes", icon: HardDrive, key: "3" },
  { id: "networks", title: "Networks", icon: Network, key: "4" },
  { id: "system", title: "System", icon: Box, key: "5" },
  { id: "activity", title: "Activity", icon: Activity, key: "6" },
];

/** The list as the containers section shows it now. */
export function currentList(): { items: Item[]; visible: ContainerSummary[] } {
  const { containers, stats, ui } = get();
  return listModel(containers, stats, ui);
}

/** What a container command acts on now. */
export function selection(): ContainerSummary[] {
  const { containers, ui, marked } = get();
  if (ui.section !== "containers") return [];
  if (ui.detail && marked.length === 0) {
    const open = containers.find((c) => c.id === ui.detail);
    if (open && get().focus === "detail") return [open];
  }
  return targets(currentList().items, ui.selected, marked, containers);
}

function describe(list: readonly ContainerSummary[]): string {
  if (list.length === 1) return list[0]!.name;
  return `${list.length} containers`;
}

export function containerCommands(list: readonly ContainerSummary[]): Command[] {
  if (list.length === 0) return [];
  const one = list.length === 1 ? list[0]! : undefined;
  const who = describe(list);
  const up = list.some((c) => c.state === "running" || c.state === "restarting");
  const stopped = list.some((c) => !["running", "restarting", "paused"].includes(c.state));
  const paused = list.some((c) => c.state === "paused");
  const commands: Command[] = [];
  // `s` stops what runs first: on a project that is partly up, it stops it.
  if (up)
    commands.push({
      id: "stop",
      title: `Stop ${who}`,
      short: "Stop",
      group: "Container",
      icon: Square,
      keys: "s",
      run: () =>
        void act(
          list.filter((c) => c.state === "running" || c.state === "restarting"),
          "stop",
        ),
    });
  if (stopped || paused)
    commands.push({
      id: "start",
      title: `Start ${who}`,
      short: "Start",
      group: "Container",
      icon: Play,
      keys: "s",
      run: () => toggle(list.filter((c) => c.state !== "running")),
    });
  commands.push({
    id: "restart",
    title: `Restart ${who}`,
    short: "Restart",
    group: "Container",
    icon: RotateCw,
    keys: "r",
    run: () => void act(list, "restart"),
  });
  if (up || paused)
    commands.push({
      id: "pause",
      title: paused ? `Resume ${who}` : `Pause ${who}`,
      short: paused ? "Resume" : "Pause",
      group: "Container",
      icon: Pause,
      keys: "p",
      run: () => pauseToggle(list),
    });
  if (one) {
    commands.push({
      id: "shell",
      title: `Shell in ${one.name}`,
      short: "Open a shell",
      group: "Container",
      icon: SquareTerminal,
      keys: "e",
      detail: "the pane becomes the terminal",
      run: () => void openInTerminal(one, "shell"),
    });
    commands.push({
      id: "logs",
      title: `Logs of ${one.name}`,
      short: "Logs",
      group: "Container",
      icon: ScrollText,
      keys: "l",
      run: () => openDetail(one.id, "logs"),
    });
    commands.push({
      id: "follow",
      title: `Follow ${one.name}'s logs in the terminal`,
      short: "Follow logs in the terminal",
      group: "Container",
      icon: ArrowRightLeft,
      keys: "F",
      run: () => void openInTerminal(one, "logs"),
    });
    commands.push({
      id: "inspect",
      title: `Inspect ${one.name}`,
      short: "Inspect",
      group: "Container",
      icon: Eye,
      keys: "i",
      run: () => openDetail(one.id, "inspect"),
    });
    const published = one.ports.find((p) => p.public !== undefined);
    if (published) {
      commands.push({
        id: "open",
        title: `Open ${portUrl(published)}`,
        short: `Open ${portUrl(published)?.replace("http://", "")}`,
        group: "Container",
        icon: ExternalLink,
        keys: "o",
        run: () => void openPort(published),
      });
    }
    commands.push({
      id: "copy-id",
      title: `Copy ${one.name}'s id`,
      short: "Copy id",
      group: "Container",
      icon: Copy,
      keys: "y",
      run: () => void copyText(one.id, "the id"),
    });
  }
  commands.push({
    id: "kill",
    title: `Kill ${who}`,
    short: "Kill",
    group: "Container",
    icon: Skull,
    keys: "K",
    tone: "danger",
    run: () => askKill(list),
  });
  commands.push({
    id: "remove",
    title: `Remove ${who}`,
    short: "Remove…",
    group: "Container",
    icon: Trash2,
    keys: "d",
    tone: "danger",
    run: () => askRemove(list),
  });
  return commands;
}

export function openDetail(id: string, tab?: ReturnType<typeof get>["ui"]["tab"]): void {
  const { ui } = get();
  setUi({ section: "containers", selected: `c:${id}`, detail: id, ...(tab ? { tab } : {}) });
  set({ focus: "detail" });
  if (tab === "logs" || ui.tab === "logs") pollNow();
}

export function globalCommands(): Command[] {
  const { ui } = get();
  const go_ = SECTIONS.map<Command>((s) => ({
    id: `go-${s.id}`,
    title: `Go to ${s.title}`,
    group: "Go to",
    icon: s.icon,
    keys: s.key,
    run: () => go(s.id),
  }));
  const filters: Command[] = (["all", "running", "stopped", "issues"] as const).map((filter) => ({
    id: `filter-${filter}`,
    title: `Show ${filter === "all" ? "all containers" : filter === "issues" ? "containers with issues" : `${filter} containers`}`,
    group: "View",
    icon: ListFilter,
    keys: "f",
    run: () => {
      setUi({ section: "containers", filter });
    },
  }));
  return [
    ...go_,
    {
      id: "group",
      title: ui.groupByProject ? "Stop grouping by compose project" : "Group by compose project",
      group: "View",
      icon: FolderTree,
      keys: "P",
      run: () => setUi({ groupByProject: !get().ui.groupByProject }),
    },
    ...filters,
    {
      id: "pull",
      title: "Pull an image…",
      group: "Docker",
      icon: Download,
      run: () => set({ dialog: { kind: "pull" } }),
    },
    {
      id: "prune",
      title: "Clean up…",
      group: "Docker",
      icon: Sparkles,
      detail: "remove what nothing uses",
      run: () => {
        void loadDisk();
        set({ dialog: { kind: "prune" } });
      },
    },
    {
      id: "refresh",
      title: "Refresh",
      group: "Docker",
      icon: RefreshCw,
      keys: "R",
      run: () => {
        pollNow();
        const section = get().ui.section;
        if (section === "images") void loadImages();
        if (section === "volumes") void loadVolumes(true);
        if (section === "networks") void loadNetworks();
        if (section === "system") void loadDisk();
      },
    },
    {
      id: "help",
      title: "Keyboard shortcuts",
      group: "Help",
      icon: Keyboard,
      keys: "?",
      run: () => set({ help: true }),
    },
  ];
}

/** The context menu of a container row. */
export function containerMenu(list: readonly ContainerSummary[]): MenuEntry[] {
  const commands = containerCommands(list);
  const entries: MenuEntry[] = [];
  const order = [
    "start",
    "stop",
    "restart",
    "pause",
    "|",
    "shell",
    "logs",
    "follow",
    "inspect",
    "open",
    "copy-id",
    "|",
    "kill",
    "remove",
  ];
  for (const id of order) {
    if (id === "|") {
      if (entries.length > 0 && entries.at(-1) !== "separator") entries.push("separator");
      continue;
    }
    const command = commands.find((c) => c.id === id);
    if (!command) continue;
    const disabled = command.id === "shell" && (!get().canHandOff || list[0]?.state !== "running");
    entries.push({
      label: command.short ?? command.title,
      icon: command.icon,
      shortcut: command.keys,
      tone: command.tone,
      disabled,
      hint: disabled
        ? get().canHandOff
          ? "Start it first"
          : "Needs a terminal and the docker command"
        : undefined,
      run: command.run,
    });
  }
  if (entries.at(-1) === "separator") entries.pop();
  return entries;
}
