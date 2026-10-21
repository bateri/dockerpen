/** The rail: the sections, and the engine at a glance. */

import { motion } from "motion/react";

import { SECTIONS } from "../state/commands";
import { hasIssue } from "../state/derive";
import { go, useStore } from "../state/store";
import { memory, percent } from "../lib/format";
import { Sparkline } from "./ui";

export function Mark({ className }: { className?: string }) {
  // Three containers, stacked: the second lifted, as if one were being picked out.
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" aria-hidden>
      <rect x="3" y="14" width="18" height="6" rx="2" fill="currentColor" opacity="0.35" />
      <rect x="5" y="7.5" width="14" height="5.5" rx="2" fill="currentColor" opacity="0.7" />
      <rect x="7" y="2" width="10" height="4.5" rx="1.8" fill="currentColor" />
    </svg>
  );
}

export function Rail() {
  const section = useStore((s) => s.ui.section);
  const containers = useStore((s) => s.containers);
  const images = useStore((s) => s.images);
  const volumes = useStore((s) => s.volumes);
  const networks = useStore((s) => s.networks);
  const engine = useStore((s) => s.engine);
  const totals = useStore((s) => s.totals);
  const boot = useStore((s) => s.boot);
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
      <div className="brand">
        <Mark className="brand-mark" />
        <div className="brand-text" style={{ minWidth: 0 }}>
          <div className="brand-name">dockerpen</div>
          <div className="brand-host ellipsis">
            {boot
              ? `${boot.user ? `${boot.user}@` : ""}${boot.hostname.replace(/\.local$|\.lan$/, "")}`
              : ""}
          </div>
        </div>
      </div>
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
