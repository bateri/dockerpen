/** What the list shows, worked out from the store: filtered, searched, sorted and grouped. */

import type { ContainerStats, ContainerSummary } from "../../server/types";
import type { Ui } from "./store";

export type Item =
  | { kind: "group"; key: string; project: string; containers: ContainerSummary[] }
  | { kind: "container"; key: string; container: ContainerSummary; grouped: boolean };

export const STANDALONE = "";

export function containerKey(id: string): string {
  return `c:${id}`;
}

export function groupKey(project: string): string {
  return `g:${project}`;
}

/**
 * Exit codes that say someone stopped the container, not that it failed: a stop
 * (SIGTERM, 143), a stop that ran out of patience or an engine that shut down
 * (SIGKILL, 137), ⌃C (130).
 */
const STOPPED_BY_SIGNAL = new Set([0, 130, 137, 143]);

/** A container that exited on its own with a failure. */
export function failed(container: ContainerSummary): boolean {
  return (
    container.state === "exited" &&
    container.exitCode !== undefined &&
    !STOPPED_BY_SIGNAL.has(container.exitCode)
  );
}

/** A container that needs a look: unhealthy, restarting, dead, or failed. */
export function hasIssue(container: ContainerSummary): boolean {
  return (
    container.health === "unhealthy" ||
    container.state === "restarting" ||
    container.state === "dead" ||
    failed(container)
  );
}

/** The name a row shows: in its compose project's group, the service is enough. */
export function displayName(container: ContainerSummary, grouped: boolean): string {
  if (!grouped || !container.service || !container.project) return container.name;
  const replica = new RegExp(`^${container.project}[-_]${container.service}[-_](\\d+)$`).exec(
    container.name,
  );
  if (replica)
    return replica[1] === "1" ? container.service : `${container.service} #${replica[1]}`;
  return container.name;
}

export function isUp(container: ContainerSummary): boolean {
  return (
    container.state === "running" ||
    container.state === "paused" ||
    container.state === "restarting"
  );
}

function passes(container: ContainerSummary, filter: Ui["filter"]): boolean {
  switch (filter) {
    case "all":
      return true;
    case "running":
      return isUp(container);
    case "stopped":
      return !isUp(container);
    case "issues":
      return hasIssue(container);
  }
}

const STATE_ORDER: Record<string, number> = {
  restarting: 0,
  running: 1,
  paused: 2,
  created: 3,
  exited: 4,
  dead: 5,
  removing: 6,
};

function sorter(ui: Ui, stats: Record<string, ContainerStats>) {
  return (a: ContainerSummary, b: ContainerSummary): number => {
    switch (ui.sort) {
      case "state":
        return (
          (STATE_ORDER[a.state] ?? 9) - (STATE_ORDER[b.state] ?? 9) || a.name.localeCompare(b.name)
        );
      case "cpu":
        return (stats[b.id]?.cpu ?? -1) - (stats[a.id]?.cpu ?? -1) || a.name.localeCompare(b.name);
      case "memory":
        return (
          (stats[b.id]?.memory ?? -1) - (stats[a.id]?.memory ?? -1) || a.name.localeCompare(b.name)
        );
      case "created":
        return b.created - a.created;
      case "name":
        return a.name.localeCompare(b.name);
    }
  };
}

/**
 * Whether `text` has every word of `query` in it. A filter narrows what is shown, so it
 * matches what was typed; the palette, which jumps, is the one that guesses.
 */
export function contains(text: string, query: string): boolean {
  const haystack = text.toLowerCase();
  return query
    .toLowerCase()
    .split(/\s+/)
    .filter(Boolean)
    .every((word) => haystack.includes(word));
}

export function matches(container: ContainerSummary, query: string): boolean {
  if (query.trim() === "") return true;
  const haystack = `${container.name} ${container.image} ${container.project ?? ""} ${container.service ?? ""} ${container.ports
    .map((p) => `${p.public ?? ""} ${p.private}`)
    .join(" ")} ${container.id.slice(0, 12)}`;
  return contains(haystack, query);
}

export interface ListModel {
  items: Item[];
  /** The containers that pass the filter and the search, in the order shown. */
  visible: ContainerSummary[];
  counts: { all: number; running: number; stopped: number; issues: number };
}

export function listModel(
  containers: readonly ContainerSummary[],
  stats: Record<string, ContainerStats>,
  ui: Ui,
): ListModel {
  const counts = {
    all: containers.length,
    running: containers.filter(isUp).length,
    stopped: containers.filter((c) => !isUp(c)).length,
    issues: containers.filter(hasIssue).length,
  };
  const shown = containers
    .filter((c) => passes(c, ui.filter) && matches(c, ui.query))
    .sort(sorter(ui, stats));
  if (!ui.groupByProject) {
    return {
      items: shown.map((container) => ({
        kind: "container",
        key: containerKey(container.id),
        container,
        grouped: false,
      })),
      visible: shown,
      counts,
    };
  }
  const groups = new Map<string, ContainerSummary[]>();
  for (const container of shown) {
    const project = container.project ?? STANDALONE;
    groups.set(project, [...(groups.get(project) ?? []), container]);
  }
  // Projects with something running come first: they are what one looks at.
  const upIn = (project: string) =>
    containers.filter((c) => (c.project ?? STANDALONE) === project && isUp(c)).length > 0 ? 0 : 1;
  const order = [...groups.keys()].sort((a, b) => {
    if (a === STANDALONE) return 1;
    if (b === STANDALONE) return -1;
    return upIn(a) - upIn(b) || a.localeCompare(b);
  });
  const items: Item[] = [];
  const visible: ContainerSummary[] = [];
  const onlyStandalone = order.length === 1 && order[0] === STANDALONE;
  for (const project of order) {
    const members = groups.get(project)!;
    if (!onlyStandalone) {
      items.push({ kind: "group", key: groupKey(project), project, containers: members });
      // A search looks into folded projects too.
      if (ui.collapsed.includes(project) && ui.query.trim() === "") continue;
    }
    for (const container of members) {
      items.push({
        kind: "container",
        key: containerKey(container.id),
        container,
        grouped: !onlyStandalone,
      });
      visible.push(container);
    }
  }
  return { items, visible, counts };
}

/** The containers an action applies to: the marked ones, or else the chosen row's (a group's members). */
export function targets(
  items: readonly Item[],
  selected: string,
  marked: readonly string[],
  containers: readonly ContainerSummary[],
): ContainerSummary[] {
  if (marked.length > 0) return containers.filter((c) => marked.includes(c.id));
  const item = items.find((i) => i.key === selected);
  if (!item) return [];
  return item.kind === "group" ? item.containers : [item.container];
}
