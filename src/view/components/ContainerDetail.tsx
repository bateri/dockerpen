/** The panel of one container: how it is, its logs, its environment, its processes, all of it. */

import { AnimatePresence, motion } from "motion/react";
import { useVirtualizer } from "@tanstack/react-virtual";
import { memo, useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import {
  AlertTriangle,
  ArrowDown,
  ArrowRightLeft,
  Copy,
  Cpu,
  Eraser,
  ExternalLink,
  Eye,
  EyeOff,
  HardDrive,
  HeartPulse,
  MemoryStick,
  Network,
  Pause,
  Play,
  RotateCw,
  Square,
  SquareTerminal,
  Trash2,
  X,
} from "lucide-react";

import type {
  ContainerDetail as Detail,
  ContainerSummary,
  LogLine,
  ProcessList,
  DetailTab,
} from "../../server/types";
import {
  act,
  askRemove,
  copyText,
  loadDetail,
  openInTerminal,
  openPort,
  pauseToggle,
  pollNow,
  portUrl,
  toggle,
} from "../state/actions";
import { call } from "../lib/bridge";
import { parseAnsi, levelOf, stripAnsi } from "../lib/ansi";
import {
  agoLong,
  dateTime,
  imageName,
  logTime,
  memory,
  percent,
  rate,
  shortId,
} from "../lib/format";
import { useKeyLayer } from "../state/keys";
import { get, set, setUi, useStore } from "../state/store";
import { Button, Empty, LiveChart, SearchField, StatusDot, Switch, Tag, stateLabel } from "./ui";

const TABS: { id: DetailTab; label: string }[] = [
  { id: "overview", label: "Overview" },
  { id: "logs", label: "Logs" },
  { id: "env", label: "Environment" },
  { id: "processes", label: "Processes" },
  { id: "inspect", label: "Inspect" },
];

export function ContainerDetail({
  container,
  focused,
}: {
  container: ContainerSummary;
  focused: boolean;
}) {
  const tab = useStore((s) => s.ui.tab);
  const pending = useStore((s) => s.pending[container.id]);
  const canHandOff = useStore((s) => s.canHandOff);
  const detail = useStore((s) => s.details[container.id]);
  const label = stateLabel(container);
  const up = container.state === "running" || container.state === "restarting";

  // The detail is read when the panel opens and again as the container changes state.
  useEffect(() => {
    void loadDetail(container.id);
  }, [container.id, container.state, container.status.startsWith("Up") ? "up" : container.status]);

  useKeyLayer(
    (event) => {
      if (event.key === "Escape" || event.key === "Tab") {
        set({ focus: "list" });
        return true;
      }
      if (event.key === "[" || event.key === "]") {
        const at = TABS.findIndex((t) => t.id === get().ui.tab);
        const next = TABS[(at + (event.key === "]" ? 1 : TABS.length - 1)) % TABS.length]!;
        setUi({ tab: next.id });
        if (next.id === "logs") pollNow();
        return true;
      }
      if (event.key === "ArrowLeft" && get().ui.tab !== "logs") {
        set({ focus: "list" });
        return true;
      }
      return false;
    },
    { active: () => get().focus === "detail", priority: 1 },
  );

  return (
    <>
      <div className="detail-head">
        <div className="detail-title">
          <StatusDot container={container} busy={pending !== undefined} />
          <h2 className="selectable">{container.name}</h2>
          <Button
            variant="ghost"
            size="sm"
            icon
            tip="Close"
            keys="esc"
            onClick={() => setUi({ detail: null })}
          >
            <X size={14} />
          </Button>
        </div>
        <div className="detail-sub">
          <Tag tone={label.tone}>{pending ? `${pending}…` : label.text}</Tag>
          <span className="ellipsis" data-tip={container.image}>
            {imageName(container.image)}
          </span>
          <button
            type="button"
            className="hint"
            style={{ padding: "0 4px" }}
            data-tip="Copy the id"
            data-keys="y"
            onClick={() => void copyText(container.id, "the id")}
          >
            {shortId(container.id)} <Copy size={11} />
          </button>
          {container.project && (
            <span className="faint">
              {container.project}
              {container.service ? ` / ${container.service}` : ""}
            </span>
          )}
        </div>
        <div className="detail-actions">
          <Button
            size="sm"
            busy={pending === "start" || pending === "stop"}
            disabled={pending !== undefined}
            keys="s"
            tip={up ? "Stop, then kill after 10s" : "Start"}
            onClick={() => toggle([container])}
          >
            {up ? <Square size={11} /> : <Play size={12} />}{" "}
            {up ? "Stop" : container.state === "paused" ? "Resume" : "Start"}
          </Button>
          <Button
            size="sm"
            busy={pending === "restart"}
            disabled={pending !== undefined}
            keys="r"
            tip="Restart"
            onClick={() => void act([container], "restart")}
          >
            <RotateCw size={12} /> Restart
          </Button>
          {(container.state === "running" || container.state === "paused") && (
            <Button
              size="sm"
              disabled={pending !== undefined}
              keys="p"
              tip={container.state === "paused" ? "Resume" : "Freeze its processes"}
              onClick={() => pauseToggle([container])}
            >
              {container.state === "paused" ? <Play size={12} /> : <Pause size={12} />}
              {container.state === "paused" ? "Resume" : "Pause"}
            </Button>
          )}
          <Button
            size="sm"
            disabled={container.state !== "running" || !canHandOff}
            keys="e"
            tip={
              canHandOff
                ? "A shell in the container, in this pane; exit comes back"
                : "Needs a terminal and the docker command"
            }
            onClick={() => void openInTerminal(container, "shell")}
          >
            <SquareTerminal size={12} /> Shell
          </Button>
          <span style={{ flex: 1 }} />
          <Button
            size="sm"
            variant="danger-ghost"
            icon
            keys="d"
            tip="Remove"
            onClick={() => askRemove([container])}
          >
            <Trash2 size={13} />
          </Button>
        </div>
      </div>
      <div className="tabs" role="tablist" aria-label="Container">
        {TABS.map((t) => (
          <button
            key={t.id}
            type="button"
            role="tab"
            className="tab"
            aria-selected={tab === t.id}
            onClick={() => {
              setUi({ tab: t.id });
              set({ focus: "detail" });
              if (t.id === "logs") pollNow();
            }}
          >
            {t.label}
            {tab === t.id && (
              <motion.span
                layoutId="tab-line"
                className="tab-line"
                transition={{ type: "spring", duration: 0.32, bounce: 0.1 }}
              />
            )}
          </button>
        ))}
      </div>
      <div className="tab-body" style={tab === "logs" ? { overflow: "hidden" } : undefined}>
        <AnimatePresence mode="wait" initial={false}>
          <motion.div
            key={`${container.id}-${tab}`}
            initial={{ opacity: 0, y: 4 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, transition: { duration: 0.08 } }}
            transition={{ duration: 0.18, ease: [0.2, 0, 0, 1] }}
            style={{ height: tab === "logs" ? "100%" : undefined }}
          >
            {tab === "overview" && <Overview container={container} detail={detail} />}
            {tab === "logs" && <Logs container={container} focused={focused} />}
            {tab === "env" && <Environment detail={detail} />}
            {tab === "processes" && <Processes container={container} />}
            {tab === "inspect" && <Inspect detail={detail} />}
          </motion.div>
        </AnimatePresence>
      </div>
    </>
  );
}

// ---- overview ------------------------------------------------------------------------------------

const SIGNALS: Record<number, string> = {
  130: "interrupted (SIGINT)",
  134: "aborted (SIGABRT)",
  137: "killed (SIGKILL)",
  139: "crashed (SIGSEGV)",
  143: "terminated (SIGTERM)",
};

function Overview({
  container,
  detail,
}: {
  container: ContainerSummary;
  detail: Detail | undefined;
}) {
  const samples = useStore((s) => s.history[container.id]);
  const stats = useStore((s) => s.stats[container.id]);
  const [labelsOpen, setLabelsOpen] = useState(false);
  const up = container.state === "running";
  const times = (samples ?? []).map((s) => s.t);

  const problem = (() => {
    if (!detail) return undefined;
    const state = detail.state;
    if (state.oomKilled)
      return {
        tone: "danger",
        text: `Killed for running out of memory${detail.memoryLimit ? ` (limit ${memory(detail.memoryLimit)})` : ""}.`,
      };
    if (
      container.state === "restarting" ||
      (detail.restartCount > 2 && container.state !== "running")
    )
      return {
        tone: "warning",
        text: `Restarting: it has restarted ${detail.restartCount} times. The logs say why.`,
      };
    if (container.state === "exited" && state.exitCode !== 0)
      return {
        tone: "danger",
        text: `Exited with code ${state.exitCode}${SIGNALS[state.exitCode] ? `, ${SIGNALS[state.exitCode]}` : ""}, ${agoLong(Date.parse(state.finishedAt))}.${state.error ? ` ${state.error}` : ""}`,
      };
    if (state.health?.status === "unhealthy") {
      const last = state.health.log.at(-1);
      return {
        tone: "danger",
        text: `Its health check has failed ${state.health.failingStreak} times in a row${last?.output ? `: ${last.output.split("\n")[0]}` : "."}`,
      };
    }
    return undefined;
  })();

  return (
    <div className="pane-pad">
      {problem && (
        <motion.div
          className="callout"
          data-tone={problem.tone}
          initial={{ opacity: 0, y: -4 }}
          animate={{ opacity: 1, y: 0 }}
        >
          <AlertTriangle size={15} />
          <span>{problem.text}</span>
        </motion.div>
      )}
      {up ? (
        <div className="cards">
          <div className="card">
            <div className="card-label">
              <Cpu size={12} /> CPU
            </div>
            <div className="card-value">
              {percent(stats?.cpu ?? null)}
              <small>{detail?.cpuLimit ? `of ${detail.cpuLimit} cpu` : "of one cpu"}</small>
            </div>
            <LiveChart
              series={[{ values: (samples ?? []).map((s) => s.cpu), color: "var(--accent)" }]}
              format={(v) => percent(v)}
              times={times}
            />
          </div>
          <div className="card">
            <div className="card-label">
              <MemoryStick size={12} /> Memory
            </div>
            <div className="card-value">
              {memory(stats?.memory ?? 0)}
              <small>{detail?.memoryLimit ? `of ${memory(detail.memoryLimit)}` : ""}</small>
            </div>
            <LiveChart
              series={[{ values: (samples ?? []).map((s) => s.memory), color: "var(--ok)" }]}
              format={(v) => memory(v)}
              times={times}
            />
          </div>
          <div className="card">
            <div className="card-label">
              <Network size={12} /> Network
            </div>
            <div className="card-value" style={{ fontSize: 14 }}>
              <span style={{ color: "var(--info)" }}>↓ {rate(stats?.netRx ?? 0)}</span>{" "}
              <span style={{ color: "var(--warn)", marginLeft: 6 }}>
                ↑ {rate(stats?.netTx ?? 0)}
              </span>
            </div>
            <LiveChart
              series={[
                { values: (samples ?? []).map((s) => s.netRx), color: "var(--info)" },
                { values: (samples ?? []).map((s) => s.netTx), color: "var(--warn)", fill: false },
              ]}
              format={(v) => rate(v)}
              times={times}
            />
          </div>
          <div className="card">
            <div className="card-label">
              <HardDrive size={12} /> Disk and processes
            </div>
            <dl className="kv" style={{ marginTop: 6 }}>
              <dt>read</dt>
              <dd>{rate(stats?.blockRead ?? 0)}</dd>
              <dt>write</dt>
              <dd>{rate(stats?.blockWrite ?? 0)}</dd>
              <dt>processes</dt>
              <dd>{stats?.pids ?? "–"}</dd>
            </dl>
          </div>
        </div>
      ) : null}

      {detail && detail.ports.length > 0 && (
        <section>
          <h3 className="section-title">Ports</h3>
          <ul className="plain-list">
            {detail.ports.map((port) => {
              const url = portUrl(port);
              return (
                <li key={`${port.public ?? "-"}:${port.private}/${port.type}`}>
                  <span style={{ flex: 1 }}>
                    {port.public !== undefined ? (
                      <>
                        <b>
                          {port.ip && port.ip !== "0.0.0.0" && port.ip !== "::"
                            ? `${port.ip}:`
                            : ""}
                          {port.public}
                        </b>
                        <span className="faint"> → </span>
                      </>
                    ) : (
                      <span className="faint">not published · </span>
                    )}
                    {port.private}/{port.type}
                  </span>
                  {url && (
                    <>
                      <Button
                        size="sm"
                        variant="ghost"
                        icon
                        tip="Copy the address"
                        onClick={() => void copyText(url, "the address")}
                      >
                        <Copy size={12} />
                      </Button>
                      <Button
                        size="sm"
                        variant="ghost"
                        tip={`Open ${url} in the browser`}
                        keys="o"
                        onClick={() => void openPort(port)}
                      >
                        <ExternalLink size={12} /> Open
                      </Button>
                    </>
                  )}
                </li>
              );
            })}
          </ul>
        </section>
      )}

      {detail ? (
        <section>
          <h3 className="section-title">Container</h3>
          <dl className="kv selectable">
            <dt>image</dt>
            <dd>{detail.image}</dd>
            <dt>command</dt>
            <dd>
              <Clamp text={[...detail.entrypoint, ...detail.cmd].join(" ") || "–"} />
            </dd>
            <dt>created</dt>
            <dd>{dateTime(detail.created)}</dd>
            {detail.state.running ? (
              <>
                <dt>started</dt>
                <dd>
                  {dateTime(detail.state.startedAt)}{" "}
                  <span className="faint">({agoLong(Date.parse(detail.state.startedAt))})</span>
                </dd>
              </>
            ) : (
              <>
                <dt>finished</dt>
                <dd>{dateTime(detail.state.finishedAt)}</dd>
              </>
            )}
            <dt>restarts</dt>
            <dd>
              {detail.restartCount} <span className="faint">· policy {detail.restartPolicy}</span>
            </dd>
            {detail.workingDir && (
              <>
                <dt>working dir</dt>
                <dd>{detail.workingDir}</dd>
              </>
            )}
            {detail.user && (
              <>
                <dt>user</dt>
                <dd>{detail.user}</dd>
              </>
            )}
            <dt>platform</dt>
            <dd>
              {detail.platform || "–"}
              {detail.privileged && (
                <>
                  {" "}
                  <Tag tone="warning">privileged</Tag>
                </>
              )}
            </dd>
          </dl>
        </section>
      ) : (
        <SkeletonLines count={6} />
      )}

      {detail && detail.networks.length > 0 && (
        <section>
          <h3 className="section-title">Networks</h3>
          <ul className="plain-list">
            {detail.networks.map((n) => (
              <li key={n.name}>
                <Network size={13} className="faint" />
                <b className="ellipsis">{n.name}</b>
                <span className="selectable" style={{ flex: 1 }}>
                  {n.ip || <span className="faint">no address</span>}
                </span>
                {n.aliases.length > 0 && (
                  <span className="faint ellipsis">{n.aliases.join(", ")}</span>
                )}
              </li>
            ))}
          </ul>
        </section>
      )}

      {detail && detail.mounts.length > 0 && (
        <section>
          <h3 className="section-title">Mounts</h3>
          <ul className="plain-list">
            {detail.mounts.map((m) => (
              <li key={m.destination}>
                <Tag tone={m.type === "volume" ? "info" : undefined}>{m.type}</Tag>
                <span className="ellipsis selectable" style={{ flex: 1 }} data-tip={m.source}>
                  {m.name && m.type === "volume"
                    ? /^[0-9a-f]{64}$/.test(m.name)
                      ? shortId(m.name)
                      : m.name
                    : m.source}
                  <span className="faint"> → </span>
                  {m.destination}
                </span>
                {!m.rw && <Tag>read-only</Tag>}
              </li>
            ))}
          </ul>
        </section>
      )}

      {detail?.state.health && (
        <section>
          <h3 className="section-title">
            <HeartPulse size={12} /> Health checks
          </h3>
          <ul className="plain-list">
            {[...detail.state.health.log].reverse().map((entry) => (
              <li key={entry.start} style={{ alignItems: "flex-start" }}>
                <Tag tone={entry.exitCode === 0 ? "success" : "danger"}>
                  {entry.exitCode === 0 ? "pass" : `exit ${entry.exitCode}`}
                </Tag>
                <span
                  className="selectable"
                  style={{ flex: 1, whiteSpace: "pre-wrap", fontSize: 11.5 }}
                >
                  {entry.output || <span className="faint">no output</span>}
                </span>
                <span className="faint" style={{ fontSize: 11 }}>
                  {agoLong(Date.parse(entry.end))}
                </span>
              </li>
            ))}
          </ul>
        </section>
      )}

      {detail && Object.keys(detail.labels).length > 0 && (
        <section>
          <h3 className="section-title">
            Labels
            <Button size="sm" variant="ghost" onClick={() => setLabelsOpen(!labelsOpen)}>
              {labelsOpen ? "Hide" : `Show ${Object.keys(detail.labels).length}`}
            </Button>
          </h3>
          <AnimatePresence initial={false}>
            {labelsOpen && (
              <motion.dl
                className="kv selectable"
                initial={{ opacity: 0, height: 0 }}
                animate={{ opacity: 1, height: "auto" }}
                exit={{ opacity: 0, height: 0 }}
                transition={{ duration: 0.22, ease: [0.2, 0, 0, 1] }}
                style={{ overflow: "hidden" }}
              >
                {Object.entries(detail.labels).map(([k, v]) => (
                  <div key={k} style={{ display: "contents" }}>
                    <dt className="ellipsis" data-tip={k}>
                      {k}
                    </dt>
                    <dd>{v}</dd>
                  </div>
                ))}
              </motion.dl>
            )}
          </AnimatePresence>
        </section>
      )}
    </div>
  );
}

/** A long text, three lines of it until asked for all. */
function Clamp({ text }: { text: string }) {
  const [open, setOpen] = useState(false);
  const [long, setLong] = useState(false);
  const ref = useRef<HTMLSpanElement>(null);
  useLayoutEffect(() => {
    const element = ref.current;
    if (element && !open) setLong(element.scrollHeight > element.clientHeight + 2);
  }, [text, open]);
  return (
    <>
      <span ref={ref} className={open ? undefined : "clamp"}>
        {text}
      </span>
      {(long || open) && (
        <button
          type="button"
          className="hint"
          style={{ marginLeft: -4, color: "var(--accent)" }}
          onClick={() => setOpen(!open)}
        >
          {open ? "less" : "all of it"}
        </button>
      )}
    </>
  );
}

function SkeletonLines({ count }: { count: number }) {
  return (
    <div style={{ display: "grid", gap: 8 }}>
      {Array.from({ length: count }, (_, i) => (
        <div
          key={i}
          className="skeleton"
          style={{ height: 12, width: `${40 + ((i * 37) % 50)}%` }}
        />
      ))}
    </div>
  );
}

// ---- logs -----------------------------------------------------------------------------------------

function Logs({ container, focused }: { container: ContainerSummary; focused: boolean }) {
  const logs = useStore((s) => s.logs);
  const options = useStore((s) => s.ui.logs);
  const canHandOff = useStore((s) => s.canHandOff);
  const [query, setQuery] = useState("");
  const [only, setOnly] = useState(false);
  const [current, setCurrent] = useState(-1);
  const [unseen, setUnseen] = useState(0);
  const scroller = useRef<HTMLDivElement>(null);
  const search = useRef<HTMLInputElement>(null);
  const following = options.follow;
  const mine = logs.id === container.id;
  const lines = mine ? logs.lines : [];

  const needle = query.trim().toLowerCase();
  const plain = useMemo(() => lines.map((line) => stripAnsi(line.text)), [lines]);
  const hits = useMemo(() => {
    if (!needle) return [] as number[];
    const out: number[] = [];
    plain.forEach((text, i) => {
      if (text.toLowerCase().includes(needle)) out.push(i);
    });
    return out;
  }, [plain, needle]);
  const rows = only && needle ? hits : null;
  const count = rows ? rows.length : lines.length;

  const virtualizer = useVirtualizer({
    count,
    getScrollElement: () => scroller.current,
    estimateSize: () => 18,
    overscan: 20,
  });

  const setFollow = useCallback((follow: boolean) => {
    setUi({ logs: { ...get().ui.logs, follow } });
  }, []);

  // Another container's logs start at their end, following.
  useEffect(() => {
    setFollow(true);
    setUnseen(0);
  }, [container.id, setFollow]);

  // There is something to come back to only when the lines do not fit.
  const [overflowing, setOverflowing] = useState(false);
  useLayoutEffect(() => {
    const element = scroller.current;
    if (element) setOverflowing(element.scrollHeight > element.clientHeight + 4);
  });

  // New lines: the view follows them when it is following, and counts them when it is not.
  const lastCount = useRef(count);
  useLayoutEffect(() => {
    const added = count - lastCount.current;
    lastCount.current = count;
    if (count === 0) return;
    if (following) {
      virtualizer.scrollToIndex(count - 1, { align: "end" });
      setUnseen(0);
    } else if (added > 0) setUnseen((n) => n + added);
  }, [count, following, virtualizer]);

  useEffect(() => {
    if (following) setUnseen(0);
  }, [following]);

  const jump = (direction: 1 | -1) => {
    if (hits.length === 0) return;
    const position = rows ? current : hits.indexOf(current);
    const nextHit =
      position < 0
        ? direction === 1
          ? 0
          : hits.length - 1
        : (position + direction + hits.length) % hits.length;
    const line = hits[nextHit]!;
    setCurrent(line);
    setFollow(false);
    virtualizer.scrollToIndex(rows ? nextHit : line, { align: "center" });
  };

  useKeyLayer(
    (event) => {
      const key = event.key;
      if (key === " ") {
        setFollow(!get().ui.logs.follow);
        return true;
      }
      if (key === "t") {
        setUi({ logs: { ...get().ui.logs, timestamps: !get().ui.logs.timestamps } });
        return true;
      }
      if (key === "w") {
        setUi({ logs: { ...get().ui.logs, wrap: !get().ui.logs.wrap } });
        return true;
      }
      if (key === "n" || key === "N") {
        jump(key === "n" ? 1 : -1);
        return true;
      }
      if (key === "G" || key === "End") {
        setFollow(true);
        return true;
      }
      if (key === "g" || key === "Home") {
        setFollow(false);
        virtualizer.scrollToIndex(0);
        return true;
      }
      if (key === "j" || key === "ArrowDown" || key === "k" || key === "ArrowUp") {
        const element = scroller.current;
        if (!element) return true;
        element.scrollBy({ top: key === "j" || key === "ArrowDown" ? 54 : -54 });
        if (key === "k" || key === "ArrowUp") setFollow(false);
        return true;
      }
      if (key === "PageDown" || key === "PageUp") {
        const element = scroller.current;
        if (element)
          element.scrollBy({ top: (key === "PageDown" ? 1 : -1) * element.clientHeight * 0.85 });
        if (key === "PageUp") setFollow(false);
        return true;
      }
      if (key === "F") {
        void openInTerminal(container, "logs");
        return true;
      }
      return false;
    },
    {
      active: () => get().focus === "detail" && focused,
      search: () => search.current?.focus(),
      priority: 2,
    },
  );

  // Following stops only when the person scrolls up (the wheel, the keys, the scrollbar), never
  // because the view scrolled itself; it starts again when they come back to the end.
  const dragging = useRef(false);
  const onScroll = () => {
    const element = scroller.current;
    if (!element) return;
    const atBottom = element.scrollHeight - element.scrollTop - element.clientHeight < 24;
    if (atBottom && !following) setFollow(true);
    else if (!atBottom && following && dragging.current) setFollow(false);
  };

  return (
    <div className="logs" data-wrap={options.wrap}>
      <div className="logs-bar">
        <SearchField
          ref={search}
          value={query}
          onChange={(value) => {
            setQuery(value);
            setCurrent(-1);
          }}
          placeholder="Find in logs"
          keys="/"
          onKeyDown={(event) => {
            if (event.key === "Enter") {
              event.preventDefault();
              jump(event.shiftKey ? -1 : 1);
            }
          }}
        />
        {needle && (
          <span className="faint" style={{ fontSize: 11, minWidth: 54 }}>
            {hits.length === 0
              ? "no match"
              : `${Math.max(0, (rows ? current : hits.indexOf(current)) + 1)}/${hits.length}`}
          </span>
        )}
        {needle && <Switch checked={only} onChange={setOnly} label="only" />}
        <Switch checked={following} onChange={setFollow} label="follow" keys="space" />
        <Switch
          checked={options.timestamps}
          onChange={(timestamps) => setUi({ logs: { ...options, timestamps } })}
          label="time"
          keys="t"
        />
        <Switch
          checked={options.wrap}
          onChange={(wrap) => setUi({ logs: { ...options, wrap } })}
          label="wrap"
          keys="w"
        />
        <Button
          size="sm"
          variant="ghost"
          icon
          tip="Clear the view (the container's log stays)"
          onClick={() => set((s) => ({ logs: { ...s.logs, lines: [] } }))}
        >
          <Eraser size={13} />
        </Button>
        <Button
          size="sm"
          variant="ghost"
          icon
          tip="Copy what is shown"
          onClick={() =>
            void copyText((rows ? rows.map((i) => plain[i]!) : plain).join("\n"), `${count} lines`)
          }
        >
          <Copy size={13} />
        </Button>
        {canHandOff && (
          <Button
            size="sm"
            variant="ghost"
            icon
            tip="Follow in the terminal, with nothing in between"
            keys="F"
            onClick={() => void openInTerminal(container, "logs")}
          >
            <ArrowRightLeft size={13} />
          </Button>
        )}
      </div>
      <div
        className="logs-scroll"
        ref={scroller}
        onScroll={onScroll}
        onWheel={(e) => e.deltaY < 0 && following && setFollow(false)}
        onPointerDown={() => {
          dragging.current = true;
        }}
        onPointerUp={() => {
          dragging.current = false;
        }}
      >
        {!mine ? (
          <div style={{ padding: 12 }}>
            <SkeletonLines count={10} />
          </div>
        ) : lines.length === 0 ? (
          <Empty icon={<ScrollIcon />} title="Nothing written yet">
            {container.state === "running"
              ? "Lines appear here as the container writes them."
              : "The container wrote nothing before it stopped."}
          </Empty>
        ) : (
          <div style={{ height: virtualizer.getTotalSize(), position: "relative" }}>
            {virtualizer.getVirtualItems().map((item) => {
              const index = rows ? rows[item.index]! : item.index;
              const line = lines[index]!;
              return (
                <div
                  key={item.key}
                  data-index={item.index}
                  ref={virtualizer.measureElement}
                  style={{
                    position: "absolute",
                    top: 0,
                    left: 0,
                    width: "100%",
                    transform: `translateY(${item.start}px)`,
                  }}
                >
                  <LogRow
                    line={line}
                    timestamps={options.timestamps}
                    needle={needle}
                    current={index === current}
                  />
                </div>
              );
            })}
          </div>
        )}
      </div>
      <AnimatePresence>
        {!following && mine && overflowing && (
          <motion.button
            type="button"
            className="follow-pill"
            initial={{ opacity: 0, y: 10, x: "-50%" }}
            animate={{ opacity: 1, y: 0, x: "-50%" }}
            exit={{ opacity: 0, y: 8, x: "-50%" }}
            transition={{ type: "spring", duration: 0.35, bounce: 0.2 }}
            style={{ translate: "none" }}
            onClick={() => setFollow(true)}
          >
            <ArrowDown size={13} />
            {unseen > 0 ? `${unseen} new line${unseen === 1 ? "" : "s"}` : "Follow"}
          </motion.button>
        )}
      </AnimatePresence>
    </div>
  );
}

function ScrollIcon() {
  return <SquareTerminal size={20} />;
}

const LogRow = memo(function LogRow({
  line,
  timestamps,
  needle,
  current,
}: {
  line: LogLine;
  timestamps: boolean;
  needle: string;
  current: boolean;
}) {
  // A program that colours its own lines is left to its colours; one that does not gets them from its words.
  const level = line.text.includes("\x1b") ? undefined : levelOf(line.text);
  return (
    <div className="log-line" data-stream={line.stream} data-level={level} data-current={current}>
      {timestamps && <span className="log-time">{logTime(line.time)}</span>}
      <span className="log-text">
        {parseAnsi(line.text).map((span, i) => {
          const classes = [
            span.fg !== undefined ? `ansi-${span.fg}` : "",
            span.bold ? "ansi-bold" : "",
            span.dim ? "ansi-dim" : "",
            span.italic ? "ansi-italic" : "",
            span.underline ? "ansi-underline" : "",
          ]
            .filter(Boolean)
            .join(" ");
          return (
            <span key={i} className={classes || undefined}>
              {needle ? mark(span.text, needle) : span.text}
            </span>
          );
        })}
      </span>
    </div>
  );
});

function mark(text: string, needle: string) {
  const lower = text.toLowerCase();
  const parts: React.ReactNode[] = [];
  let from = 0;
  for (;;) {
    const at = lower.indexOf(needle, from);
    if (at < 0) break;
    if (at > from) parts.push(text.slice(from, at));
    parts.push(<mark key={at}>{text.slice(at, at + needle.length)}</mark>);
    from = at + needle.length;
  }
  if (from === 0) return text;
  parts.push(text.slice(from));
  return parts;
}

// ---- environment -----------------------------------------------------------------------------------

const SECRET = /pass|secret|token|key|pwd|credential|auth|private|salt|cookie|session|dsn/i;

function Environment({ detail }: { detail: Detail | undefined }) {
  const [revealed, setRevealed] = useState<Set<string>>(new Set());
  const [all, setAll] = useState(false);
  const [query, setQuery] = useState("");
  const input = useRef<HTMLInputElement>(null);
  useKeyLayer(
    (event) => {
      if (event.key === "v") {
        setAll((a) => !a);
        return true;
      }
      return false;
    },
    { active: () => get().focus === "detail", search: () => input.current?.focus(), priority: 2 },
  );
  if (!detail)
    return (
      <div className="pane-pad">
        <SkeletonLines count={8} />
      </div>
    );
  const env = detail.env.filter(
    (e) => !query || `${e.key}=${e.value}`.toLowerCase().includes(query.toLowerCase()),
  );
  const secrets = detail.env.filter((e) => SECRET.test(e.key)).length;
  return (
    <div className="pane-pad" style={{ gap: 10 }}>
      <div style={{ display: "flex", gap: 6, alignItems: "center" }}>
        <SearchField
          ref={input}
          value={query}
          onChange={setQuery}
          placeholder="Find a variable"
          keys="/"
        />
        <span style={{ flex: 1 }} />
        {secrets > 0 && (
          <Button
            size="sm"
            variant="ghost"
            keys="v"
            tip={all ? "Hide the secrets again" : "Show the values that look secret"}
            onClick={() => setAll(!all)}
          >
            {all ? <EyeOff size={13} /> : <Eye size={13} />} {all ? "Hide" : `Reveal ${secrets}`}
          </Button>
        )}
      </div>
      {detail.env.length === 0 ? (
        <Empty icon={<Eye size={20} />} title="No environment" />
      ) : (
        <table className="table" style={{ tableLayout: "fixed" }}>
          <colgroup>
            <col style={{ width: "38%" }} />
            <col />
            <col style={{ width: 34 }} />
          </colgroup>
          <tbody>
            {env.map((e) => {
              const secret = SECRET.test(e.key) && e.value !== "";
              const shown = !secret || all || revealed.has(e.key);
              return (
                <tr key={e.key}>
                  <td className="ellipsis" data-tip={e.key} style={{ color: "var(--info)" }}>
                    {e.key}
                  </td>
                  <td
                    className="selectable"
                    style={{
                      whiteSpace: "normal",
                      overflowWrap: "anywhere",
                      height: "auto",
                      padding: "6px 8px",
                    }}
                  >
                    {shown ? (
                      e.value || <span className="faint">empty</span>
                    ) : (
                      <span className="secret">••••••••</span>
                    )}
                  </td>
                  <td className="actions-cell">
                    {secret ? (
                      <Button
                        size="sm"
                        variant="ghost"
                        icon
                        tip={shown ? "Hide" : "Reveal"}
                        onClick={() => {
                          const next = new Set(revealed);
                          if (next.has(e.key)) next.delete(e.key);
                          else next.add(e.key);
                          setRevealed(next);
                        }}
                      >
                        {shown ? <EyeOff size={12} /> : <Eye size={12} />}
                      </Button>
                    ) : (
                      <Button
                        size="sm"
                        variant="ghost"
                        icon
                        tip="Copy KEY=value"
                        onClick={() => void copyText(`${e.key}=${e.value}`, e.key)}
                      >
                        <Copy size={12} />
                      </Button>
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}
    </div>
  );
}

// ---- processes ---------------------------------------------------------------------------------------

function Processes({ container }: { container: ContainerSummary }) {
  const [list, setList] = useState<ProcessList | null>(null);
  const [error, setError] = useState<string>();
  useEffect(() => {
    let alive = true;
    const read = async () => {
      try {
        const result = await call<ProcessList>("container_processes", { id: container.id });
        if (alive) {
          setList(result);
          setError(undefined);
        }
      } catch (e) {
        if (alive) setError(e instanceof Error ? e.message : String(e));
      }
    };
    void read();
    const timer = setInterval(read, 2500);
    return () => {
      alive = false;
      clearInterval(timer);
    };
  }, [container.id]);
  if (container.state !== "running" && container.state !== "paused")
    return (
      <Empty icon={<Cpu size={20} />} title="Not running">
        A stopped container has no processes.
      </Empty>
    );
  if (error)
    return (
      <Empty icon={<AlertTriangle size={20} />} title="Could not list the processes">
        {error}
      </Empty>
    );
  if (!list)
    return (
      <div className="pane-pad">
        <SkeletonLines count={5} />
      </div>
    );
  const command = list.titles.findIndex((t) => /CMD|COMMAND/.test(t));
  return (
    <div style={{ padding: "4px 8px 16px" }}>
      <table className="table">
        <colgroup>
          {list.titles.map((t, i) => (
            <col
              key={t}
              style={{ width: i === command ? undefined : t === "PID" || t === "PPID" ? 74 : 86 }}
            />
          ))}
        </colgroup>
        <thead>
          <tr>
            {list.titles.map((t) => (
              <th key={t}>{t}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          <AnimatePresence initial={false}>
            {list.processes.map((p) => (
              <motion.tr
                key={p[list.titles.indexOf("PID")] ?? p.join()}
                layout="position"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
              >
                {p.map((cell, i) => (
                  <td
                    key={i}
                    className={i === command ? "selectable" : undefined}
                    data-tip={i === command && cell.length > 40 ? cell : undefined}
                  >
                    {cell}
                  </td>
                ))}
              </motion.tr>
            ))}
          </AnimatePresence>
        </tbody>
      </table>
    </div>
  );
}

// ---- inspect -------------------------------------------------------------------------------------------

function Inspect({ detail }: { detail: Detail | undefined }) {
  const text = useMemo(() => (detail ? JSON.stringify(detail.raw, null, 2) : ""), [detail]);
  const html = useMemo(() => highlightJson(text), [text]);
  if (!detail)
    return (
      <div className="pane-pad">
        <SkeletonLines count={12} />
      </div>
    );
  return (
    <div style={{ position: "relative" }}>
      <div
        style={{
          position: "sticky",
          top: 0,
          display: "flex",
          justifyContent: "flex-end",
          padding: "8px 10px 0",
          zIndex: 2,
          height: 0,
        }}
      >
        <Button size="sm" onClick={() => void copyText(text, "the JSON")}>
          <Copy size={12} /> Copy
        </Button>
      </div>
      <pre className="json" dangerouslySetInnerHTML={{ __html: html }} />
    </div>
  );
}

function escapeHtml(text: string): string {
  return text.replace(/[&<>]/g, (c) => (c === "&" ? "&amp;" : c === "<" ? "&lt;" : "&gt;"));
}

function highlightJson(text: string): string {
  return escapeHtml(text).replace(
    /("(?:\\.|[^"\\])*")(\s*:)?|\b(true|false)\b|\bnull\b|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?/g,
    (match, string: string | undefined, colon: string | undefined, bool: string | undefined) => {
      if (string !== undefined)
        return colon
          ? `<span class="k">${string}</span>${colon}`
          : `<span class="s">${string}</span>`;
      if (bool !== undefined) return `<span class="b">${match}</span>`;
      if (match === "null") return `<span class="z">null</span>`;
      return `<span class="n">${match}</span>`;
    },
  );
}
