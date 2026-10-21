/** The containers: the list, grouped by compose project, and the panel of the one opened. */

import { AnimatePresence, motion } from "motion/react";
import { memo, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import type { PointerEvent as ReactPointerEvent } from "react";
import {
  ArrowDownWideNarrow,
  Boxes,
  ChevronDown,
  Download,
  FolderTree,
  MoreHorizontal,
  Play,
  RotateCw,
  ScrollText,
  SearchX,
  Sparkles,
  Square,
  SquareTerminal,
  Trash2,
  X,
} from "lucide-react";

import type { ContainerStats, ContainerSummary, SortKey } from "../../server/types";
import {
  act,
  askRemove,
  loadDisk,
  openInTerminal,
  openPort,
  pollNow,
  toggle,
} from "../state/actions";
import { containerCommands, containerMenu, openDetail, selection } from "../state/commands";
import { containerKey, displayName, groupKey, hasIssue, isUp, listModel } from "../state/derive";
import type { Item } from "../state/derive";
import { moveBy, useKeyLayer } from "../state/keys";
import { get, openMenu, set, setUi, useStore } from "../state/store";
import type { Ui } from "../state/store";
import { imageName, memory, percent } from "../lib/format";
import { ContainerDetail } from "./ContainerDetail";
import {
  Bar,
  Button,
  Checkbox,
  Empty,
  SearchField,
  Segmented,
  Sparkline,
  StatusDot,
  Tag,
  stateLabel,
} from "./ui";

const FILTERS: Ui["filter"][] = ["all", "running", "stopped", "issues"];

export function ContainersSection() {
  const containers = useStore((s) => s.containers);
  const stats = useStore((s) => s.stats);
  const ui = useStore((s) => s.ui);
  const marked = useStore((s) => s.marked);
  const focus = useStore((s) => s.focus);
  const model = useMemo(() => listModel(containers, stats, ui), [containers, stats, ui]);
  const search = useRef<HTMLInputElement>(null);
  const splitRef = useRef<HTMLDivElement>(null);
  const [splitWidth, setSplitWidth] = useState(0);

  useLayoutEffect(() => {
    const element = splitRef.current;
    if (!element) return;
    setSplitWidth(element.clientWidth);
    const observer = new ResizeObserver(([entry]) => setSplitWidth(entry?.contentRect.width ?? 0));
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  // The chosen row falls on a neighbour when it leaves the list.
  const index = model.items.findIndex((item) => item.key === ui.selected);
  const lastIndex = useRef(0);
  useEffect(() => {
    if (index >= 0) {
      lastIndex.current = index;
      return;
    }
    const fallback = model.items[Math.min(lastIndex.current, model.items.length - 1)];
    if (fallback && fallback.key !== ui.selected) setUi({ selected: fallback.key });
  }, [index, model.items, ui.selected]);

  const detail = ui.detail ? containers.find((c) => c.id === ui.detail) : undefined;
  useEffect(() => {
    if (ui.detail && containers.length > 0 && !detail) setUi({ detail: null });
  }, [ui.detail, detail, containers.length]);

  const sideBySide = splitWidth >= 860;
  const [resizing, setResizing] = useState(false);
  const panelWidth = Math.round(
    Math.max(340, Math.min(splitWidth - 380, splitWidth * ui.panelWidth)),
  );

  const select = (key: string) => {
    setUi({ selected: key });
    if (get().ui.detail && key.startsWith("c:")) setUi({ detail: key.slice(2) });
  };

  useKeyLayer(
    (event) => {
      const state = get();
      const items = model.items;
      const at = items.findIndex((i) => i.key === state.ui.selected);
      const moved = moveBy(event, at, items.length);
      if (moved !== undefined && !event.ctrlKey) {
        select(items[moved]!.key);
        return true;
      }
      const item = items[at];
      const key = event.key;
      if (key === "Enter" || key === "ArrowRight") {
        if (!item) return false;
        if (item.kind === "group") {
          toggleCollapsed(item.project, key === "ArrowRight" ? false : undefined);
        } else {
          openDetail(item.container.id);
        }
        return true;
      }
      if (key === "ArrowLeft") {
        if (item?.kind === "group") toggleCollapsed(item.project, true);
        else if (state.ui.detail) setUi({ detail: null });
        else if (item?.kind === "container" && item.grouped)
          setUi({ selected: groupKey(item.container.project ?? "") });
        return true;
      }
      if (key === " ") {
        if (!item) return false;
        const ids = item.kind === "group" ? item.containers.map((c) => c.id) : [item.container.id];
        const all = ids.every((id) => state.marked.includes(id));
        set({
          marked: all
            ? state.marked.filter((id) => !ids.includes(id))
            : [...new Set([...state.marked, ...ids])],
        });
        if (item.kind === "container" && at < items.length - 1) select(items[at + 1]!.key);
        return true;
      }
      if (key === "a") {
        set({ marked: model.visible.map((c) => c.id) });
        return true;
      }
      if (key === "A") {
        set({ marked: [] });
        return true;
      }
      if (key === "Escape") {
        if (state.marked.length > 0) set({ marked: [] });
        else if (state.ui.detail) setUi({ detail: null });
        else if (state.ui.query) setUi({ query: "" });
        else if (state.ui.filter !== "all") setUi({ filter: "all" });
        else return false;
        return true;
      }
      if ((key === "[" || key === "]") && state.ui.detail) {
        const tabs = ["overview", "logs", "env", "processes", "inspect"] as const;
        const at = tabs.indexOf(state.ui.tab);
        setUi({ tab: tabs[(at + (key === "]" ? 1 : tabs.length - 1)) % tabs.length]! });
        pollNow();
        return true;
      }
      if (key === "Tab" && state.ui.detail) {
        set({ focus: "detail" });
        return true;
      }
      if (key === "f") {
        const next = FILTERS[(FILTERS.indexOf(state.ui.filter) + 1) % FILTERS.length]!;
        setUi({ filter: next });
        return true;
      }
      if (key === "P") {
        setUi({ groupByProject: !state.ui.groupByProject });
        return true;
      }
      if (key === "<" || key === ">") {
        const next = state.ui.panelWidth + (key === "<" ? 0.04 : -0.04);
        setUi({ panelWidth: Math.max(0.28, Math.min(0.72, next)) });
        return true;
      }
      if (key === "." || key === "ContextMenu" || (key === "F10" && event.shiftKey)) {
        const row = document.querySelector<HTMLElement>(
          `[data-key="${CSS.escape(state.ui.selected)}"]`,
        );
        const rect = row?.getBoundingClientRect();
        const list = selection();
        if (list.length === 0 || !rect) return true;
        openMenu({
          x: rect.left + 40,
          y: rect.bottom - 4,
          origin: "anchor",
          entries: containerMenu(list),
        });
        return true;
      }
      const command = containerCommands(selection()).find((c) => c.keys === key);
      if (command && !event.ctrlKey) {
        command.run();
        return true;
      }
      return false;
    },
    {
      search: () => search.current?.focus(),
    },
  );

  const summary = `${model.counts.running} running · ${model.counts.all} total`;

  return (
    <div className="section">
      <header className="header">
        <h1>Containers</h1>
        <span className="sub">{summary}</span>
        <span className="header-spacer" />
        <Button
          variant="ghost"
          size="sm"
          tip="Pull an image"
          onClick={() => set({ dialog: { kind: "pull" } })}
        >
          <Download size={13} /> <span className="btn-label">Pull</span>
        </Button>
        <Button
          variant="ghost"
          size="sm"
          tip="Remove what nothing uses"
          onClick={() => {
            void loadDisk();
            set({ dialog: { kind: "prune" } });
          }}
        >
          <Sparkles size={13} /> <span className="btn-label">Clean up</span>
        </Button>
      </header>
      <div className="toolbar">
        <SearchField
          ref={search}
          value={ui.query}
          onChange={(query) => setUi({ query })}
          placeholder="Filter by name, image, port…"
          keys="/"
          onKeyDown={(event) => {
            if (event.key === "ArrowDown" || event.key === "Enter") {
              event.preventDefault();
              event.currentTarget.blur();
              set({ focus: "list" });
              if (model.items[0] && index < 0) setUi({ selected: model.items[0].key });
            }
          }}
        />
        <Segmented
          label="Show"
          value={ui.filter}
          onChange={(filter) => setUi({ filter })}
          options={[
            {
              value: "all",
              label: "All",
              count: model.counts.all,
              tip: "Every container",
              keys: "f",
            },
            { value: "running", label: "Running", count: model.counts.running },
            { value: "stopped", label: "Stopped", count: model.counts.stopped },
            {
              value: "issues",
              label: "Issues",
              count: model.counts.issues,
              tone: "danger",
              tip: "Unhealthy, restarting or failed",
            },
          ]}
        />
        <Button
          variant="ghost"
          size="sm"
          icon
          pressed={ui.groupByProject}
          tip="Group by compose project"
          keys="P"
          onClick={() => setUi({ groupByProject: !ui.groupByProject })}
        >
          <FolderTree size={14} />
        </Button>
        <SortButton sort={ui.sort} />
      </div>
      <div className="split" ref={splitRef}>
        <div className="list-pane">
          <ContainerList items={model.items} ui={ui} marked={marked} onSelect={select} />
          <BulkBar />
        </div>
        <AnimatePresence initial={false}>
          {detail && (
            <motion.aside
              key="detail"
              className="detail"
              data-mode={sideBySide ? "side" : "sheet"}
              initial={sideBySide ? { width: 0, opacity: 0 } : { x: 40, opacity: 0 }}
              animate={
                sideBySide ? { width: panelWidth, opacity: 1 } : { x: 0, opacity: 1, width: "auto" }
              }
              exit={sideBySide ? { width: 0, opacity: 0 } : { x: 40, opacity: 0 }}
              transition={
                resizing ? { duration: 0 } : { type: "spring", duration: 0.42, bounce: 0.06 }
              }
              onPointerDown={() => set({ focus: "detail" })}
            >
              {sideBySide && <ResizeHandle width={splitWidth} onDragging={setResizing} />}
              <div
                style={{
                  width: sideBySide ? panelWidth : "100%",
                  height: "100%",
                  display: "flex",
                  flexDirection: "column",
                }}
              >
                <ContainerDetail container={detail} focused={focus === "detail"} />
              </div>
            </motion.aside>
          )}
        </AnimatePresence>
      </div>
    </div>
  );
}

function toggleCollapsed(project: string, collapse?: boolean): void {
  const { collapsed } = get().ui;
  const is = collapsed.includes(project);
  const next = collapse ?? !is;
  if (next === is) return;
  setUi({ collapsed: next ? [...collapsed, project] : collapsed.filter((p) => p !== project) });
}

const SORTS: { value: SortKey; label: string }[] = [
  { value: "name", label: "Name" },
  { value: "state", label: "State" },
  { value: "cpu", label: "CPU" },
  { value: "memory", label: "Memory" },
  { value: "created", label: "Newest" },
];

function SortButton({ sort }: { sort: SortKey }) {
  return (
    <Button
      variant="ghost"
      size="sm"
      tip="Sort"
      onClick={(event) => {
        const rect = event.currentTarget.getBoundingClientRect();
        openMenu({
          x: rect.left,
          y: rect.bottom + 4,
          origin: "anchor",
          entries: SORTS.map((s) => ({
            label: s.label,
            icon: s.value === sort ? ArrowDownWideNarrow : undefined,
            run: () => setUi({ sort: s.value }),
          })),
        });
      }}
    >
      <ArrowDownWideNarrow size={13} />{" "}
      <span className="sort-label">{SORTS.find((s) => s.value === sort)?.label}</span>
    </Button>
  );
}

// ---- the list --------------------------------------------------------------------------------

function ContainerList({
  items,
  ui,
  marked,
  onSelect,
}: {
  items: Item[];
  ui: Ui;
  marked: string[];
  onSelect: (key: string) => void;
}) {
  const stats = useStore((s) => s.stats);
  const history = useStore((s) => s.history);
  const pending = useStore((s) => s.pending);
  const flash = useStore((s) => s.flash);
  const engine = useStore((s) => s.engine);
  const status = useStore((s) => s.status);
  const memoryPeak = Math.max(1, ...Object.values(stats).map((s) => s.memory));
  const hostMemory = engine?.ok ? engine.memory : 0;
  const listRef = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState<"wide" | "medium" | "narrow" | "tiny">("wide");
  const first = useRef(true);
  const anchor = useRef<string | null>(null);

  useLayoutEffect(() => {
    const element = listRef.current;
    if (!element) return;
    const observer = new ResizeObserver(([entry]) => {
      const w = entry?.contentRect.width ?? 0;
      setWidth(w < 470 ? "tiny" : w < 660 ? "narrow" : w < 860 ? "medium" : "wide");
    });
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    const timer = setTimeout(() => {
      first.current = false;
    }, 800);
    return () => clearTimeout(timer);
  }, []);

  // The chosen row stays in sight as the keyboard moves it.
  useEffect(() => {
    listRef.current
      ?.querySelector<HTMLElement>(`[data-key="${CSS.escape(ui.selected)}"]`)
      ?.scrollIntoView({ block: "nearest" });
  }, [ui.selected]);

  const pointerDown = (event: ReactPointerEvent, item: Item) => {
    if (event.button !== 0) return;
    set({ focus: "list" });
    if (item.kind === "container" && (event.metaKey || event.ctrlKey)) {
      const id = item.container.id;
      const current = get().marked;
      set({ marked: current.includes(id) ? current.filter((m) => m !== id) : [...current, id] });
      anchor.current = item.key;
      onSelect(item.key);
      return;
    }
    if (item.kind === "container" && event.shiftKey) {
      const from = items.findIndex((i) => i.key === (anchor.current ?? ui.selected));
      const to = items.findIndex((i) => i.key === item.key);
      const [a, b] = from < to ? [from, to] : [to, from];
      const range = items
        .slice(Math.max(0, a), b + 1)
        .flatMap((i) => (i.kind === "container" ? [i.container.id] : []));
      set({ marked: [...new Set([...get().marked, ...range])] });
      onSelect(item.key);
      return;
    }
    anchor.current = item.key;
    onSelect(item.key);
  };

  const contextMenu = (event: React.MouseEvent, item: Item) => {
    event.preventDefault();
    const state = get();
    let list: ContainerSummary[];
    if (item.kind === "group") list = item.containers;
    else if (state.marked.includes(item.container.id))
      list = state.containers.filter((c) => state.marked.includes(c.id));
    else {
      set({ marked: [] });
      list = [item.container];
    }
    onSelect(item.key);
    openMenu({
      x: event.clientX,
      y: event.clientY,
      origin: "pointer",
      entries: containerMenu(list),
    });
  };

  if (status === "ready" && engine?.ok && items.length === 0) {
    return (
      <div className="list" ref={listRef} style={{ display: "flex" }}>
        {get().containers.length === 0 ? (
          <Empty icon={<Boxes size={20} />} title="No containers yet">
            Run one and it shows up here at once: <code>docker run -d -p 8080:80 nginx</code>
          </Empty>
        ) : (
          <Empty
            icon={<SearchX size={20} />}
            title="Nothing matches"
            action={
              <Button size="sm" onClick={() => setUi({ query: "", filter: "all" })}>
                Show all
              </Button>
            }
          >
            {ui.query ? `No container is like “${ui.query}”` : "No container is in this state"}
            {ui.filter !== "all" && ui.query ? ` among the ${ui.filter} ones` : ""}.
          </Empty>
        )}
      </div>
    );
  }

  let staggerIndex = 0;
  return (
    <div
      className="list"
      ref={listRef}
      data-width={width}
      role="listbox"
      aria-multiselectable
      aria-label="Containers"
    >
      <div className="list-head cols">
        <span />
        <SortHead sort="name" label="Name" />
        <span className="col-image">Image</span>
        <SortHead sort="cpu" label="CPU" />
        <SortHead sort="memory" label="Memory" className="col-mem" />
        <span className="col-ports">Ports</span>
        <SortHead sort="state" label="Status" />
      </div>
      <AnimatePresence initial={false}>
        {items.map((item) => {
          const order = first.current ? staggerIndex++ : 0;
          if (item.kind === "group") {
            return (
              <GroupRow
                key={item.key}
                item={item}
                selected={item.key === ui.selected}
                collapsed={ui.collapsed.includes(item.project)}
                order={order}
                onPointerDown={(event) => pointerDown(event, item)}
                onContextMenu={(event) => contextMenu(event, item)}
              />
            );
          }
          const c = item.container;
          return (
            <ContainerRow
              key={item.key}
              item={item}
              container={c}
              stats={stats[c.id]}
              cpuHistory={history[c.id]}
              selected={item.key === ui.selected}
              marked={marked.includes(c.id)}
              markMode={marked.length > 0}
              pending={pending[c.id]}
              flash={flash?.id === c.id ? flash.at : 0}
              order={order}
              memoryPeak={memoryPeak}
              hostMemory={hostMemory}
              onPointerDown={(event) => pointerDown(event, item)}
              onDoubleClick={() => openDetail(c.id)}
              onClick={() => {
                if (get().ui.detail) openDetail(c.id, undefined);
              }}
              onContextMenu={(event) => contextMenu(event, item)}
            />
          );
        })}
      </AnimatePresence>
    </div>
  );
}

function SortHead({
  sort,
  label,
  className,
}: {
  sort: SortKey;
  label: string;
  className?: string;
}) {
  const current = useStore((s) => s.ui.sort);
  return (
    <span className={className}>
      <button
        type="button"
        data-active={current === sort}
        onClick={() => setUi({ sort })}
        tabIndex={-1}
      >
        {label}
        {current === sort && <ChevronDown size={11} />}
      </button>
    </span>
  );
}

const rowMotion = (order: number) => ({
  layout: "position" as const,
  initial: { opacity: 0, y: order >= 0 ? 6 : -4 },
  animate: {
    opacity: 1,
    y: 0,
    transition: {
      duration: 0.28,
      ease: [0.2, 0, 0, 1] as const,
      delay: Math.min(order, 14) * 0.025,
    },
  },
  exit: { opacity: 0, y: -3, transition: { duration: 0.14 } },
  transition: { layout: { type: "spring" as const, duration: 0.35, bounce: 0.05 } },
});

function shortStatus(c: ContainerSummary): string {
  const text = c.status
    .replace(/\s*\((healthy|unhealthy|health: starting)\)/, "")
    .replace(/^Exited \(-?\d+\) /, "")
    .replace(/^Up /, "up ")
    .replace(/About an? /, "1 ")
    .replace(/Less than a second/, "<1 second")
    .replace(/ seconds?/, "s")
    .replace(/ minutes?/, "m")
    .replace(/ hours?/, "h")
    .replace(/ days?/, "d")
    .replace(/ weeks?/, "w")
    .replace(/ months?/, "mo")
    .replace(/ years?/, "y");
  return c.state === "created" ? "created" : text;
}

interface RowProps {
  item: Extract<Item, { kind: "container" }>;
  container: ContainerSummary;
  stats: ContainerStats | undefined;
  cpuHistory: { cpu: number | null }[] | undefined;
  selected: boolean;
  marked: boolean;
  markMode: boolean;
  pending: string | undefined;
  flash: number;
  order: number;
  memoryPeak: number;
  hostMemory: number;
  onPointerDown: (event: ReactPointerEvent) => void;
  onDoubleClick: () => void;
  onClick: () => void;
  onContextMenu: (event: React.MouseEvent) => void;
}

const ContainerRow = memo(function ContainerRow({
  item,
  container: c,
  stats,
  cpuHistory,
  selected,
  marked,
  markMode,
  pending,
  flash,
  order,
  memoryPeak,
  hostMemory,
  onPointerDown,
  onDoubleClick,
  onClick,
  onContextMenu,
}: RowProps) {
  const label = stateLabel(c);
  const up = isUp(c);
  const cpu = stats?.cpu ?? null;
  // A container with a limit of its own is measured against it; the rest against each other.
  const limited =
    stats !== undefined &&
    stats.memoryLimit > 0 &&
    (hostMemory === 0 || stats.memoryLimit < hostMemory * 0.95);
  const memoryShare = stats
    ? limited
      ? stats.memory / stats.memoryLimit
      : stats.memory / memoryPeak
    : 0;
  const published = c.ports.filter((p) => p.public !== undefined);
  const busy = pending !== undefined;
  const verb = pending
    ? {
        start: "starting",
        stop: "stopping",
        restart: "restarting",
        pause: "pausing",
        unpause: "resuming",
        kill: "killing",
        remove: "removing",
      }[pending]
    : undefined;
  return (
    <motion.div
      {...rowMotion(order)}
      className="row cols"
      role="option"
      aria-selected={selected}
      data-key={item.key}
      data-selected={selected}
      data-marked={marked}
      data-state={c.state}
      data-grouped={item.grouped}
      data-flash={flash > 0 && Date.now() - flash < 2000 ? "true" : undefined}
      onPointerDown={onPointerDown}
      onDoubleClick={onDoubleClick}
      onClick={onClick}
      onContextMenu={onContextMenu}
    >
      <span className="row-bg" />
      {selected && (
        <motion.span
          layoutId="row-highlight"
          className="row-highlight"
          transition={{ type: "spring", duration: 0.28, bounce: 0.1 }}
        />
      )}
      {markMode ? (
        <span
          style={{ display: "grid", placeItems: "center" }}
          onPointerDown={(event) => {
            event.stopPropagation();
            const current = get().marked;
            set({
              marked: current.includes(c.id)
                ? current.filter((m) => m !== c.id)
                : [...current, c.id],
            });
          }}
        >
          <Checkbox checked={marked} />
        </span>
      ) : (
        <StatusDot container={c} busy={busy} />
      )}
      <span className="col-name">
        <span className="name" data-tip={item.grouped && c.service ? c.name : undefined}>
          {displayName(c, item.grouped)}
        </span>
        {!item.grouped && c.project && <Tag tip={`compose project ${c.project}`}>{c.project}</Tag>}
        {(label.tone === "danger" || label.tone === "warning" || busy) && (
          <Tag tone={busy ? "accent" : label.tone}>{busy ? `${verb}…` : label.text}</Tag>
        )}
      </span>
      <span className="col-image ellipsis" data-tip={c.image}>
        {imageName(c.image)}
      </span>
      <span className="meter">
        {up && stats ? (
          <>
            <Sparkline
              values={(cpuHistory ?? []).map((s) => s.cpu)}
              width={44}
              height={14}
              color="var(--accent)"
            />
            <span className="meter-value">{percent(cpu)}</span>
          </>
        ) : (
          <span className="faint" style={{ gridColumn: "1 / -1", textAlign: "right" }}>
            –
          </span>
        )}
      </span>
      <span className="meter col-mem">
        {up && stats ? (
          <>
            <Bar
              value={memoryShare}
              tone={
                limited
                  ? memoryShare > 0.85
                    ? "danger"
                    : memoryShare > 0.65
                      ? "warning"
                      : undefined
                  : "muted"
              }
            />
            <span className="meter-value">{memory(stats.memory).replace(" ", "")}</span>
          </>
        ) : (
          <span className="faint" style={{ gridColumn: "1 / -1", textAlign: "right" }}>
            –
          </span>
        )}
      </span>
      <span className="ports col-ports">
        {published.slice(0, 2).map((port) => (
          <button
            key={`${port.public}/${port.private}`}
            type="button"
            className="port"
            data-tip={`Open http://localhost:${port.public} (→ ${port.private}/${port.type})`}
            onPointerDown={(event) => event.stopPropagation()}
            onClick={(event) => {
              event.stopPropagation();
              void openPort(port);
            }}
          >
            :{port.public}
          </button>
        ))}
        {published.length > 2 && (
          <span className="faint" style={{ fontSize: 11 }}>
            +{published.length - 2}
          </span>
        )}
      </span>
      <RowEnd container={c} busy={busy} />
    </motion.div>
  );
});

/** The end of a row: when it is quiet, how long the container has been as it is; under the pointer, what can be done. */
function RowEnd({ container: c, busy }: { container: ContainerSummary; busy: boolean }) {
  const up = c.state === "running" || c.state === "restarting";
  return (
    <span
      style={{
        position: "relative",
        display: "flex",
        justifyContent: "flex-end",
        alignItems: "center",
        minWidth: 0,
      }}
    >
      <span className="col-status ellipsis row-quiet">{shortStatus(c)}</span>
      <span className="row-actions" style={{ position: "absolute", right: 0 }}>
        <Button
          icon
          size="sm"
          disabled={busy}
          tip={up ? "Stop" : c.state === "paused" ? "Resume" : "Start"}
          keys="s"
          onPointerDown={(e) => e.stopPropagation()}
          onClick={(e) => {
            e.stopPropagation();
            toggle([c]);
          }}
        >
          {up ? <Square size={12} /> : <Play size={13} />}
        </Button>
        <Button
          icon
          size="sm"
          disabled={busy}
          tip="Restart"
          keys="r"
          onPointerDown={(e) => e.stopPropagation()}
          onClick={(e) => {
            e.stopPropagation();
            void act([c], "restart");
          }}
        >
          <RotateCw size={12} />
        </Button>
        <Button
          icon
          size="sm"
          tip="Logs"
          keys="l"
          onPointerDown={(e) => e.stopPropagation()}
          onClick={(e) => {
            e.stopPropagation();
            openDetail(c.id, "logs");
          }}
        >
          <ScrollText size={12} />
        </Button>
        <Button
          icon
          size="sm"
          disabled={c.state !== "running"}
          tip="Shell, in the terminal"
          keys="e"
          onPointerDown={(e) => e.stopPropagation()}
          onClick={(e) => {
            e.stopPropagation();
            void openInTerminal(c, "shell");
          }}
        >
          <SquareTerminal size={12} />
        </Button>
        <Button
          icon
          size="sm"
          tip="More"
          keys="."
          onPointerDown={(e) => e.stopPropagation()}
          onClick={(e) => {
            e.stopPropagation();
            const rect = e.currentTarget.getBoundingClientRect();
            const state = get();
            const list = state.marked.includes(c.id)
              ? state.containers.filter((x) => state.marked.includes(x.id))
              : [c];
            setUi({ selected: containerKey(c.id) });
            openMenu({
              x: rect.right - 216,
              y: rect.bottom + 4,
              origin: "anchor",
              entries: containerMenu(list),
            });
          }}
        >
          <MoreHorizontal size={13} />
        </Button>
      </span>
    </span>
  );
}

function GroupRow({
  item,
  selected,
  collapsed,
  order,
  onPointerDown,
  onContextMenu,
}: {
  item: Extract<Item, { kind: "group" }>;
  selected: boolean;
  collapsed: boolean;
  order: number;
  onPointerDown: (event: ReactPointerEvent) => void;
  onContextMenu: (event: React.MouseEvent) => void;
}) {
  const all = useStore((s) => s.containers);
  const members = item.project ? all.filter((c) => c.project === item.project) : item.containers;
  const up = members.filter(isUp).length;
  const issues = members.filter(hasIssue).length;
  const anyUp = up > 0;
  return (
    <motion.div
      {...rowMotion(order)}
      className="group-row"
      role="option"
      aria-selected={selected}
      aria-expanded={!collapsed}
      data-key={item.key}
      data-selected={selected}
      data-collapsed={collapsed}
      onPointerDown={onPointerDown}
      onClick={(event) => {
        if ((event.target as HTMLElement).closest(".row-actions")) return;
        toggleCollapsed(item.project);
      }}
      onContextMenu={onContextMenu}
    >
      <span className="row-bg" />
      {selected && (
        <motion.span
          layoutId="row-highlight"
          className="row-highlight"
          transition={{ type: "spring", duration: 0.28, bounce: 0.1 }}
        />
      )}
      <span className="group-chevron">
        <ChevronDown size={14} />
      </span>
      <span className="group-name">{item.project || "Standalone"}</span>
      <span className="group-stack" aria-hidden>
        {members.slice(0, 12).map((c) => (
          <span key={c.id} data-up={isUp(c) && !hasIssue(c)} data-issue={hasIssue(c)} />
        ))}
      </span>
      <span className="faint" style={{ fontSize: 11.5 }}>
        {up}/{members.length} up{issues ? ` · ${issues} with issues` : ""}
      </span>
      <span style={{ flex: 1 }} />
      {item.project && (
        <span className="row-actions">
          <Button
            icon
            size="sm"
            tip={anyUp ? `Stop ${item.project}` : `Start ${item.project}`}
            keys="s"
            onPointerDown={(e) => e.stopPropagation()}
            onClick={(e) => {
              e.stopPropagation();
              if (anyUp) void act(members.filter(isUp), "stop");
              else void act(members, "start");
            }}
          >
            {anyUp ? <Square size={12} /> : <Play size={13} />}
          </Button>
          <Button
            icon
            size="sm"
            tip={`Restart ${item.project}`}
            keys="r"
            onPointerDown={(e) => e.stopPropagation()}
            onClick={(e) => {
              e.stopPropagation();
              void act(members, "restart");
            }}
          >
            <RotateCw size={12} />
          </Button>
        </span>
      )}
    </motion.div>
  );
}

// ---- many at once -------------------------------------------------------------------------------

function BulkBar() {
  const marked = useStore((s) => s.marked);
  const containers = useStore((s) => s.containers);
  const list = containers.filter((c) => marked.includes(c.id));
  const anyUp = list.some(isUp);
  const anyDown = list.some((c) => !isUp(c));
  return (
    <AnimatePresence>
      {list.length > 0 && (
        <motion.div
          className="bulkbar"
          initial={{ opacity: 0, y: 16, x: "-50%", scale: 0.97 }}
          animate={{ opacity: 1, y: 0, x: "-50%", scale: 1 }}
          exit={{ opacity: 0, y: 10, x: "-50%", transition: { duration: 0.14 } }}
          transition={{ type: "spring", duration: 0.4, bounce: 0.15 }}
        >
          <span className="count">{list.length} marked</span>
          {anyDown && (
            <Button
              size="sm"
              variant="ghost"
              onClick={() =>
                void act(
                  list.filter((c) => !isUp(c)),
                  "start",
                )
              }
            >
              <Play size={12} /> Start
            </Button>
          )}
          {anyUp && (
            <Button size="sm" variant="ghost" onClick={() => void act(list.filter(isUp), "stop")}>
              <Square size={11} /> Stop
            </Button>
          )}
          <Button size="sm" variant="ghost" onClick={() => void act(list, "restart")}>
            <RotateCw size={12} /> Restart
          </Button>
          <Button size="sm" variant="danger-ghost" onClick={() => askRemove(list)}>
            <Trash2 size={12} /> Remove
          </Button>
          <Button
            size="sm"
            variant="ghost"
            icon
            tip="Unmark all"
            keys="esc"
            onClick={() => set({ marked: [] })}
          >
            <X size={13} />
          </Button>
        </motion.div>
      )}
    </AnimatePresence>
  );
}

// ---- the panel's width ---------------------------------------------------------------------------

function ResizeHandle({
  width,
  onDragging,
}: {
  width: number;
  onDragging: (dragging: boolean) => void;
}) {
  const [dragging, setDraggingState] = useState(false);
  const setDragging = (value: boolean) => {
    setDraggingState(value);
    onDragging(value);
  };
  return (
    <div
      className="resize-handle"
      role="separator"
      aria-orientation="vertical"
      tabIndex={0}
      data-dragging={dragging}
      data-tip="Drag to resize"
      data-keys="< >"
      onPointerDown={(event) => {
        event.preventDefault();
        event.currentTarget.setPointerCapture(event.pointerId);
        setDragging(true);
        const split = event.currentTarget.closest(".split")!.getBoundingClientRect();
        const move = (e: PointerEvent) => {
          const share = (split.right - e.clientX) / width;
          setUi({ panelWidth: Math.max(0.28, Math.min(0.72, share)) });
        };
        const up = () => {
          setDragging(false);
          window.removeEventListener("pointermove", move);
          window.removeEventListener("pointerup", up);
        };
        window.addEventListener("pointermove", move);
        window.addEventListener("pointerup", up);
      }}
      onDoubleClick={() => setUi({ panelWidth: 0.46 })}
    />
  );
}
