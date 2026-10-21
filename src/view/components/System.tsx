/** The engine and the disk it takes; and what has happened in it. */

import { AnimatePresence, motion } from "motion/react";
import { useEffect, useMemo, useRef, useState } from "react";
import {
  Activity as ActivityIcon,
  Box,
  CirclePlay,
  CircleStop,
  Download,
  HardDrive,
  HeartPulse,
  Layers,
  Network,
  Pause,
  Play,
  Plus,
  RotateCw,
  Skull,
  Sparkles,
  Trash2,
  Zap,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";

import type { DiskUsage, DockerEvent, PruneTarget } from "../../server/types";
import { loadDisk } from "../state/actions";
import { openDetail } from "../state/commands";
import { moveBy, useKeyLayer } from "../state/keys";
import { get, pick, set, useStore } from "../state/store";
import { bytes, clock, memory, plural } from "../lib/format";
import { Button, Empty, Segmented, Tween } from "./ui";

// ---- system -------------------------------------------------------------------------------------

const PARTS: {
  key: keyof DiskUsage;
  label: string;
  color: string;
  icon: LucideIcon;
  prune: PruneTarget[];
}[] = [
  {
    key: "images",
    label: "Images",
    color: "var(--accent)",
    icon: Layers,
    prune: ["danglingImages", "unusedImages"],
  },
  { key: "containers", label: "Containers", color: "var(--ok)", icon: Box, prune: ["containers"] },
  { key: "volumes", label: "Volumes", color: "var(--warn)", icon: HardDrive, prune: ["volumes"] },
  {
    key: "buildCache",
    label: "Build cache",
    color: "var(--info)",
    icon: Zap,
    prune: ["buildCache"],
  },
];

export function SystemSection() {
  const disk = useStore((s) => s.disk);
  const engine = useStore((s) => s.engine);
  const containers = useStore((s) => s.containers);
  const jobs = useStore((s) => s.jobs);
  const [chosen, setChosen] = useState(0);

  useEffect(() => {
    void loadDisk();
    const timer = setInterval(() => void loadDisk(), 20_000);
    return () => clearInterval(timer);
  }, []);

  const cleanup = (preset?: PruneTarget[]) => set({ dialog: { kind: "prune", preset } });

  useKeyLayer((event) => {
    const moved = moveBy(event, chosen, PARTS.length);
    if (moved !== undefined) {
      setChosen(moved);
      return true;
    }
    if (event.key === "Enter" || event.key === "c") {
      cleanup(event.key === "c" ? undefined : PARTS[chosen]!.prune);
      return true;
    }
    return false;
  });

  const total = disk ? PARTS.reduce((sum, p) => sum + disk[p.key].size, 0) : 0;
  const reclaimable = disk ? PARTS.reduce((sum, p) => sum + disk[p.key].reclaimable, 0) : 0;
  const pruning = jobs.some((j) => j.kind === "prune" && j.state === "running");

  return (
    <div className="section">
      <header className="header">
        <h1>System</h1>
        <span className="sub">{engine?.ok ? `${engine.name} · Docker ${engine.version}` : ""}</span>
        <span className="header-spacer" />
        <Button
          size="sm"
          variant="primary"
          busy={pruning}
          keys="c"
          tip="Choose what to remove"
          onClick={() => cleanup()}
        >
          <Sparkles size={13} /> Clean up
        </Button>
      </header>
      <div className="tab-body">
        <div className="pane-pad" style={{ paddingTop: 4 }}>
          <section className="card" style={{ padding: 14, display: "grid", gap: 12 }}>
            <div style={{ display: "flex", alignItems: "baseline", gap: 10, flexWrap: "wrap" }}>
              <span className="card-label">Disk</span>
              <span className="card-value" style={{ fontSize: 22 }}>
                {disk ? <Tween value={total} format={(n) => bytes(n)} /> : "…"}
              </span>
              {disk && reclaimable > 0 && (
                <span className="muted">
                  <b style={{ color: "var(--ok)" }}>
                    <Tween value={reclaimable} format={(n) => bytes(n)} />
                  </b>{" "}
                  can be freed
                </span>
              )}
            </div>
            <div className="disk-bar" aria-hidden>
              {disk ? (
                PARTS.map((p) => (
                  <motion.div
                    key={p.key}
                    className="disk-seg"
                    initial={{ flexGrow: 0 }}
                    animate={{ flexGrow: Math.max(disk[p.key].size, total * 0.004) }}
                    transition={{ duration: 0.9, ease: [0.2, 0, 0, 1] }}
                    style={{ background: p.color, flexBasis: 0 }}
                    data-tip={`${p.label}: ${bytes(disk[p.key].size)}`}
                  />
                ))
              ) : (
                <div className="skeleton" style={{ flex: 1 }} />
              )}
            </div>
            <div
              style={{ display: "flex", gap: 14, flexWrap: "wrap", fontSize: 11.5 }}
              className="muted"
            >
              {PARTS.map((p) => (
                <span key={p.key} style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
                  <span className="legend-dot" style={{ background: p.color }} />
                  {p.label}
                </span>
              ))}
            </div>
          </section>

          <div
            className="cards"
            style={{ gridTemplateColumns: "repeat(auto-fill, minmax(210px, 1fr))" }}
          >
            {PARTS.map((p, index) => {
              const part = disk?.[p.key];
              return (
                <motion.section
                  key={p.key}
                  className="card disk-card"
                  initial={{ opacity: 0, y: 8 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ duration: 0.3, delay: index * 0.05, ease: [0.2, 0, 0, 1] }}
                  style={
                    index === chosen
                      ? {
                          boxShadow: "inset 0 0 0 1px var(--selected-line)",
                          background: "var(--selected)",
                        }
                      : undefined
                  }
                  onPointerDown={() => setChosen(index)}
                >
                  <div className="disk-card-head">
                    <span
                      className="event-icon"
                      style={{
                        color: p.color,
                        background: `color-mix(in srgb, ${p.color} 14%, transparent)`,
                      }}
                    >
                      <p.icon size={13} />
                    </span>
                    <b className="grow">{p.label}</b>
                    <span className="faint" style={{ fontSize: 11 }}>
                      {part ? `${part.active}/${part.count} in use` : ""}
                    </span>
                  </div>
                  <div className="card-value">
                    {part ? (
                      <Tween value={part.size} format={(n) => bytes(n)} />
                    ) : (
                      <span
                        className="skeleton"
                        style={{ display: "inline-block", width: 80, height: 16 }}
                      />
                    )}
                  </div>
                  <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                    <span className="muted" style={{ flex: 1, fontSize: 11.5 }}>
                      {part
                        ? part.reclaimable > 0
                          ? `${bytes(part.reclaimable)} unused`
                          : "nothing unused"
                        : ""}
                    </span>
                    <Button
                      size="sm"
                      variant="ghost"
                      disabled={!part || part.reclaimable === 0}
                      onClick={() => cleanup(p.prune)}
                    >
                      <Trash2 size={12} /> Free
                    </Button>
                  </div>
                </motion.section>
              );
            })}
          </div>

          {engine?.ok && (
            <section className="card" style={{ padding: 14 }}>
              <h3 className="section-title">Engine</h3>
              <dl className="kv selectable">
                <dt>runs on</dt>
                <dd>{engine.name}</dd>
                <dt>docker</dt>
                <dd>
                  {engine.version} <span className="faint">· API {engine.apiVersion}</span>
                </dd>
                <dt>machine</dt>
                <dd>
                  {engine.os}/{engine.arch} · {plural(engine.cpus, "cpu")} · {memory(engine.memory)}
                </dd>
                <dt>socket</dt>
                <dd>{engine.endpoint}</dd>
                <dt>containers</dt>
                <dd>
                  {containers.filter((c) => c.state === "running").length} running of{" "}
                  {containers.length}
                </dd>
                <dt>docker command</dt>
                <dd>
                  {engine.cli
                    ? engine.compose
                      ? "installed, with compose"
                      : "installed"
                    : "not installed: no shell hand-over"}
                </dd>
              </dl>
            </section>
          )}
        </div>
      </div>
    </div>
  );
}

// ---- activity -----------------------------------------------------------------------------------

type Kind = "all" | "container" | "image" | "volume" | "network" | "problems";

function describe(event: DockerEvent): {
  icon: LucideIcon;
  tone?: "success" | "danger" | "warning" | "info";
  text: string;
} {
  const name = event.name ?? event.id.slice(0, 12);
  const action = event.action;
  if (event.type === "container") {
    if (action === "start") return { icon: CirclePlay, tone: "success", text: `${name} started` };
    if (action === "die") {
      const code = event.detail.exitCode;
      const failed = code !== undefined && code !== "0";
      return {
        icon: CircleStop,
        tone: failed ? "danger" : undefined,
        text: `${name} stopped${code !== undefined ? ` with exit ${code}` : ""}`,
      };
    }
    if (action === "stop") return { icon: CircleStop, text: `${name} was asked to stop` };
    if (action === "kill")
      return {
        icon: Skull,
        tone: "warning",
        text: `${name} was sent ${event.detail.signal ? `signal ${event.detail.signal}` : "a signal"}`,
      };
    if (action === "oom") return { icon: Zap, tone: "danger", text: `${name} ran out of memory` };
    if (action === "restart") return { icon: RotateCw, tone: "info", text: `${name} restarted` };
    if (action === "pause") return { icon: Pause, tone: "warning", text: `${name} paused` };
    if (action === "unpause") return { icon: Play, tone: "success", text: `${name} resumed` };
    if (action === "create")
      return { icon: Plus, text: `${name} created from ${event.detail.image ?? "an image"}` };
    if (action === "destroy") return { icon: Trash2, text: `${name} removed` };
    if (action.startsWith("health_status")) {
      const status = action.split(":")[1]?.trim() ?? "";
      return {
        icon: HeartPulse,
        tone: status === "healthy" ? "success" : status === "unhealthy" ? "danger" : "warning",
        text: `${name} is ${status}`,
      };
    }
    return { icon: Box, text: `${name}: ${action}` };
  }
  if (event.type === "image") {
    if (action === "pull") return { icon: Download, tone: "info", text: `pulled ${name}` };
    if (action === "delete" || action === "untag")
      return { icon: Trash2, text: `${action === "untag" ? "untagged" : "deleted"} ${name}` };
    if (action === "tag") return { icon: Layers, text: `tagged ${name}` };
    return { icon: Layers, text: `image ${name}: ${action}` };
  }
  if (event.type === "volume") {
    const id = /^[0-9a-f]{64}$/.test(event.id) ? event.id.slice(0, 12) : event.id;
    return {
      icon: HardDrive,
      tone: action === "destroy" ? undefined : undefined,
      text: `volume ${id} ${action === "destroy" ? "removed" : action === "create" ? "created" : action === "mount" ? `mounted by ${event.detail.container?.slice(0, 12) ?? "a container"}` : action}`,
    };
  }
  if (event.type === "network") {
    return {
      icon: Network,
      text: `network ${name} ${action}${event.detail.container ? ` ${event.detail.container.slice(0, 12)}` : ""}`,
    };
  }
  return { icon: ActivityIcon, text: `${event.type} ${name}: ${action}` };
}

function isProblem(event: DockerEvent): boolean {
  return (
    event.action === "oom" ||
    event.action.includes("unhealthy") ||
    (event.action === "die" && event.detail.exitCode !== undefined && event.detail.exitCode !== "0")
  );
}

export function ActivitySection() {
  const events = useStore((s) => s.events);
  const containers = useStore((s) => s.containers);
  const chosen = useStore((s) => s.pick.activity);
  const [kind, setKind] = useState<Kind>("all");
  const listRef = useRef<HTMLOListElement>(null);

  const rows = useMemo(() => {
    const list = events.filter((e) => {
      if (kind === "problems") return isProblem(e);
      if (kind === "all") return e.type !== "network" || e.action !== "disconnect";
      return e.type === kind;
    });
    return [...list].reverse();
  }, [events, kind]);

  useEffect(() => {
    if (rows.length > 0 && !rows.some((r) => r.seq === chosen)) pick("activity", rows[0]!.seq);
  }, [rows, chosen]);
  useEffect(() => {
    listRef.current?.querySelector(`[data-seq="${chosen}"]`)?.scrollIntoView({ block: "nearest" });
  }, [chosen]);

  const open = (event: DockerEvent) => {
    if (event.type !== "container") return;
    const container = get().containers.find((c) => c.id === event.id);
    if (container) openDetail(container.id, isProblem(event) ? "logs" : undefined);
  };

  useKeyLayer((event) => {
    const at = rows.findIndex((r) => r.seq === chosen);
    const moved = moveBy(event, at, rows.length);
    if (moved !== undefined) {
      pick("activity", rows[moved]!.seq);
      return true;
    }
    if (event.key === "Enter" && rows[at]) {
      open(rows[at]!);
      return true;
    }
    return false;
  });

  let day = "";
  return (
    <div className="section">
      <header className="header">
        <h1>Activity</h1>
        <span className="sub">what the engine reported, newest first</span>
      </header>
      <div className="toolbar">
        <Segmented
          label="Show"
          value={kind}
          onChange={setKind}
          options={[
            { value: "all", label: "All" },
            { value: "container", label: "Containers" },
            { value: "image", label: "Images" },
            { value: "volume", label: "Volumes" },
            { value: "network", label: "Networks" },
            {
              value: "problems",
              label: "Problems",
              count: events.filter(isProblem).length,
              tone: "danger",
            },
          ]}
        />
      </div>
      {rows.length === 0 ? (
        <Empty icon={<ActivityIcon size={20} />} title="Quiet">
          Nothing happened in the last ten minutes. Start or stop something and it shows up here as
          it happens.
        </Empty>
      ) : (
        <div className="table-scroll">
          <ol className="timeline" ref={listRef}>
            <AnimatePresence initial={false}>
              {rows.map((event) => {
                const d = describe(event);
                const label = new Date(event.time).toLocaleDateString(undefined, {
                  weekday: "long",
                  month: "short",
                  day: "numeric",
                });
                const header = label !== day ? label : null;
                day = label;
                const exists =
                  event.type === "container" && containers.some((c) => c.id === event.id);
                return (
                  <motion.li
                    key={event.seq}
                    layout="position"
                    initial={{ opacity: 0, y: -8 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={{ opacity: 0 }}
                    transition={{ duration: 0.25, ease: [0.2, 0, 0, 1] }}
                    style={{ listStyle: "none" }}
                  >
                    {header && <div className="event-day">{header}</div>}
                    <div
                      className="event"
                      data-seq={event.seq}
                      data-selected={event.seq === chosen}
                      onPointerDown={() => pick("activity", event.seq)}
                      onDoubleClick={() => open(event)}
                    >
                      <span className="faint" style={{ fontSize: 11.5 }}>
                        {clock(event.time)}
                      </span>
                      <span className="event-icon" data-tone={d.tone}>
                        <d.icon size={13} />
                      </span>
                      <span className="ellipsis">{d.text}</span>
                      {exists ? (
                        <Button
                          size="sm"
                          variant="ghost"
                          tip="Open the container"
                          onClick={() => open(event)}
                        >
                          Open
                        </Button>
                      ) : (
                        <span />
                      )}
                    </div>
                  </motion.li>
                );
              })}
            </AnimatePresence>
          </ol>
        </div>
      )}
    </div>
  );
}
