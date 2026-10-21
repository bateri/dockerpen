/** The status line: what the keys do here, and what runs in the background. */

import { AnimatePresence, motion } from "motion/react";
import { useRef, useState } from "react";
import { CheckCircle2, CircleAlert, Loader } from "lucide-react";

import { containerCommands, selection } from "../state/commands";
import { set, useStore } from "../state/store";
import { ago } from "../lib/format";
import { Bar, Kbd } from "./ui";

interface Hint {
  keys: string;
  label: string;
  run?: () => void;
}

function useHints(): Hint[] {
  const section = useStore((s) => s.ui.section);
  const focus = useStore((s) => s.focus);
  const tab = useStore((s) => s.ui.tab);
  const detail = useStore((s) => s.ui.detail);
  const marked = useStore((s) => s.marked.length);
  // Read so the hints follow the chosen row.
  useStore((s) => s.ui.selected);
  useStore((s) => s.containers);

  if (section === "containers") {
    if (focus === "detail" && detail && tab === "logs") {
      return [
        { keys: "space", label: "follow" },
        { keys: "/", label: "find" },
        { keys: "t", label: "time" },
        { keys: "w", label: "wrap" },
        { keys: "[ ]", label: "tabs" },
        { keys: "esc", label: "back" },
      ];
    }
    const commands = containerCommands(selection());
    const pick = (id: string) => commands.find((c) => c.id === id);
    const hints: Hint[] = [];
    if (marked > 0)
      hints.push({ keys: "esc", label: `unmark ${marked}`, run: () => set({ marked: [] }) });
    for (const id of ["stop", "start", "restart", "shell", "logs"]) {
      const c = pick(id);
      // One hint a key: on a group that is partly up, `s` stops.
      if (c?.keys && !hints.some((h) => h.keys === c.keys))
        hints.push({ keys: c.keys, label: c.short?.toLowerCase() ?? c.id, run: c.run });
    }
    hints.push({ keys: ".", label: "more" });
    hints.push({ keys: "space", label: "mark" });
    return hints;
  }
  if (section === "system") {
    return [
      { keys: "↑↓", label: "choose" },
      { keys: "⏎", label: "free it" },
      { keys: "c", label: "clean up", run: () => set({ dialog: { kind: "prune" } }) },
    ];
  }
  if (section === "activity") {
    return [
      { keys: "↑↓", label: "move" },
      { keys: "⏎", label: "open the container" },
    ];
  }
  return [
    { keys: "↑↓", label: "move" },
    { keys: "/", label: "find" },
    { keys: "space", label: "mark" },
    ...(section === "images"
      ? [
          { keys: "⏎", label: "layers" },
          { keys: "p", label: "pull", run: () => set({ dialog: { kind: "pull" } }) },
          { keys: "u", label: "update" },
        ]
      : []),
    { keys: "d", label: "remove" },
  ];
}

export function StatusBar() {
  const hints = useHints();
  const jobs = useStore((s) => s.jobs);
  const engine = useStore((s) => s.engine);
  const lastPoll = useStore((s) => s.lastPoll);
  const [jobsOpen, setJobsOpen] = useState(false);
  const anchor = useRef<HTMLButtonElement>(null);
  const runningJobs = jobs.filter((j) => j.state === "running");

  return (
    <footer className="statusbar">
      <div className="status-hints">
        {hints.map((hint) => (
          <button
            key={`${hint.keys}${hint.label}`}
            type="button"
            className="hint"
            onClick={hint.run}
            tabIndex={-1}
          >
            <Kbd>{hint.keys}</Kbd>
            {hint.label}
          </button>
        ))}
      </div>
      <span className="grow" />
      <div className="status-right">
        {jobs.length > 0 && (
          <button
            ref={anchor}
            type="button"
            className="hint"
            onClick={() => setJobsOpen((o) => !o)}
            style={{ color: runningJobs.length ? "var(--accent)" : undefined }}
          >
            {runningJobs.length ? <span className="spinner" /> : <CheckCircle2 size={12} />}
            {runningJobs.length ? `${runningJobs.length} running` : `${jobs.length} done`}
          </button>
        )}
        <button type="button" className="hint" tabIndex={-1} onClick={() => set({ palette: true })}>
          <Kbd>:</Kbd> commands
        </button>
        <button type="button" className="hint" tabIndex={-1} onClick={() => set({ help: true })}>
          <Kbd>?</Kbd>
        </button>
        <span
          data-tip={engine?.ok ? `Read ${ago(lastPoll)} ago` : undefined}
          style={{ display: "inline-flex" }}
        >
          <span
            className="dot"
            data-state={engine?.ok ? "running" : "exited"}
            data-failed={engine && !engine.ok ? "true" : undefined}
            style={{ width: 7, height: 7 }}
          />
        </span>
      </div>
      <AnimatePresence>
        {jobsOpen && jobs.length > 0 && (
          <JobsPopover anchor={anchor.current} onClose={() => setJobsOpen(false)} />
        )}
      </AnimatePresence>
    </footer>
  );
}

function JobsPopover({ anchor, onClose }: { anchor: HTMLElement | null; onClose: () => void }) {
  const jobs = useStore((s) => s.jobs);
  const rect = anchor?.getBoundingClientRect();
  return (
    <>
      <div style={{ position: "fixed", inset: 0, zIndex: 59 }} onPointerDown={onClose} />
      <motion.div
        className="popover"
        initial={{ opacity: 0, y: 6, scale: 0.98 }}
        animate={{ opacity: 1, y: 0, scale: 1 }}
        exit={{ opacity: 0, y: 4, transition: { duration: 0.1 } }}
        transition={{ duration: 0.18, ease: [0.2, 0, 0, 1] }}
        style={{
          right: rect ? Math.max(8, window.innerWidth - rect.right) : 8,
          bottom: rect ? window.innerHeight - rect.top + 6 : 34,
          transformOrigin: "bottom right",
        }}
      >
        {[...jobs].reverse().map((job) => (
          <div key={job.id} className="job">
            <div className="job-head">
              {job.state === "running" ? (
                <Loader
                  size={13}
                  className="spin"
                  style={{ color: "var(--accent)", animation: "spin 1s linear infinite" }}
                />
              ) : job.state === "done" ? (
                <CheckCircle2 size={13} style={{ color: "var(--ok)" }} />
              ) : (
                <CircleAlert size={13} style={{ color: "var(--bad)" }} />
              )}
              <b className="ellipsis" style={{ flex: 1 }}>
                {job.title}
              </b>
              <span className="faint" style={{ fontSize: 11 }}>
                {job.ended ? ago(job.ended) : ago(job.started)}
              </span>
            </div>
            {job.state === "running" && <Bar value={job.progress ?? 0.04} />}
            <span className="muted ellipsis" style={{ fontSize: 11.5 }}>
              {job.detail}
            </span>
          </div>
        ))}
      </motion.div>
    </>
  );
}
