/** The rail: the sections, and the engine at a glance. */

import { motion } from "motion/react";

import { SECTIONS } from "../state/commands";
import { hasIssue } from "../state/derive";
import { go, useStore } from "../state/store";
import { memory, percent } from "../lib/format";
import { Sparkline } from "./ui";

export function Rail() {
  const section = useStore((s) => s.ui.section);
  const containers = useStore((s) => s.containers);
  const images = useStore((s) => s.images);
  const volumes = useStore((s) => s.volumes);
  const networks = useStore((s) => s.networks);
  const engine = useStore((s) => s.engine);
  const totals = useStore((s) => s.totals);
  const jobs = useStore((s) => s.jobs);
  const events = useStore((s) => s.events);
  const liveFrom = useStore((s) => s.liveFrom);

  const issues = containers.filter(hasIssue).length;
  const running = containers.filter((c) => c.state === "running").length;
  const fresh = events.filter(
    (e) => e.seq > liveFrom && /die|oom|unhealthy|kill/.test(e.action),
  ).length;
  const counts: Record<string, number | undefined> = {
    containers: containers.length,
    images: images?.length,
    volumes: volumes?.length,
    networks: networks?.length,
  };
  const latest = totals.at(-1);

  return (
    <nav className="rail" aria-label="Sections">
      {SECTIONS.map((s) => (
        <button
          key={s.id}
          type="button"
          className="nav-item"
          aria-current={section === s.id ? "page" : undefined}
          data-tip={s.title}
          data-keys={s.key}
          onClick={() => go(s.id)}
        >
          {section === s.id && (
            <motion.span
              layoutId="nav-pill"
              className="nav-pill"
              transition={{ type: "spring", duration: 0.35, bounce: 0.12 }}
            />
          )}
          <s.icon size={15} />
          <span className="nav-label">{s.title}</span>
          {s.id === "containers" && issues > 0 ? (
            <span className="nav-badge" data-tip={`${issues} with issues`}>
              {issues}
            </span>
          ) : s.id === "activity" && fresh > 0 ? (
            <span className="nav-badge">{fresh}</span>
          ) : s.id === "system" && jobs.some((j) => j.state === "running") ? (
            <span className="spinner" style={{ color: "var(--accent)" }} />
          ) : counts[s.id] !== undefined ? (
            <span className="nav-count">{counts[s.id]}</span>
          ) : (
            <span className="nav-key">{s.key}</span>
          )}
        </button>
      ))}
      <div className="rail-spacer" />
      {engine?.ok && (
        <motion.div
          className="engine-card"
          initial={{ opacity: 0, y: 6 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.3, delay: 0.25 }}
        >
          <div className="engine-line">
            <span className="dot" data-state="running" style={{ width: 7, height: 7 }} />
            <span
              className="ellipsis"
              data-tip={`Docker ${engine.version} · API ${engine.apiVersion} · ${engine.endpoint}`}
            >
              {engine.name}
            </span>
          </div>
          <div className="engine-meter">
            <span>cpu</span>
            <Sparkline
              values={totals.map((t) => t.cpu)}
              width={70}
              height={14}
              color="var(--accent)"
            />
            <b>{percent(latest?.cpu ?? 0, 0)}</b>
          </div>
          <div className="engine-meter">
            <span>mem</span>
            <Sparkline
              values={totals.map((t) => t.memory)}
              width={70}
              height={14}
              color="var(--ok)"
              max={engine.memory || undefined}
            />
            <b>{memory(latest?.memory ?? 0).replace(" ", "")}</b>
          </div>
          <div className="engine-line" style={{ fontSize: 10.5, color: "var(--fg-3)" }}>
            {running} running · {engine.cpus} cpu · {memory(engine.memory).replace(" ", "")}
          </div>
        </motion.div>
      )}
    </nav>
  );
}
