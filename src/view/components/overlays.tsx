/** What comes over the page: menus, dialogs, toasts, the hand-over of the pane. */

import { AnimatePresence, motion } from "motion/react";
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import type { ReactNode } from "react";
import {
  AlertTriangle,
  CheckCircle2,
  CircleAlert,
  Download,
  Info,
  ScrollText,
  Sparkles,
  SquareTerminal,
  X,
} from "lucide-react";

import type { PruneTarget } from "../../server/types";
import { prune, pullImage } from "../state/actions";
import { dismissToast, set, useStore } from "../state/store";
import type { ConfirmOption, Dialog, Menu, Toast } from "../state/store";
import { bytes } from "../lib/format";
import { Button, Checkbox, Kbd } from "./ui";

const EASE = [0.2, 0, 0, 1] as const;

// ---- the context menu ----------------------------------------------------------------------

export function MenuLayer() {
  const menu = useStore((s) => s.menu);
  return (
    <AnimatePresence>
      {menu && <MenuPanel key={`${menu.x},${menu.y}`} menu={menu} />}
    </AnimatePresence>
  );
}

function MenuPanel({ menu }: { menu: Menu }) {
  const ref = useRef<HTMLDivElement>(null);
  const items = menu.entries;
  const actionable = items
    .map((entry, index) => ({ entry, index }))
    .filter(({ entry }) => entry !== "separator" && !entry.disabled);
  const [active, setActive] = useState(
    menu.origin === "anchor" ? (actionable[0]?.index ?? -1) : -1,
  );
  const [position, setPosition] = useState({ x: menu.x, y: menu.y });

  useLayoutEffect(() => {
    const element = ref.current;
    if (!element) return;
    const rect = element.getBoundingClientRect();
    setPosition({
      x: Math.max(6, Math.min(menu.x, window.innerWidth - rect.width - 6)),
      y: menu.y + rect.height > window.innerHeight - 6 ? Math.max(6, menu.y - rect.height) : menu.y,
    });
    element.focus();
  }, [menu]);

  const close = () => set({ menu: null });
  const run = (index: number) => {
    const entry = items[index];
    if (!entry || entry === "separator" || entry.disabled) return;
    close();
    entry.run();
  };

  return (
    <>
      <div
        style={{ position: "fixed", inset: 0, zIndex: 59 }}
        onPointerDown={close}
        onContextMenu={(event) => {
          event.preventDefault();
          close();
        }}
      />
      <motion.div
        ref={ref}
        className="menu"
        role="menu"
        tabIndex={-1}
        initial={{ opacity: 0, scale: 0.96, y: -4 }}
        animate={{ opacity: 1, scale: 1, y: 0 }}
        exit={{ opacity: 0, scale: 0.98, transition: { duration: 0.1 } }}
        transition={{ duration: 0.16, ease: EASE }}
        style={{ left: position.x, top: position.y, transformOrigin: "top left" }}
        onKeyDown={(event) => {
          const order = actionable.map((a) => a.index);
          const at = order.indexOf(active);
          if (event.key === "ArrowDown" || (event.key === "j" && !event.metaKey)) {
            setActive(order[(at + 1) % order.length] ?? -1);
          } else if (event.key === "ArrowUp" || (event.key === "k" && !event.metaKey)) {
            setActive(order[(at - 1 + order.length) % order.length] ?? -1);
          } else if (event.key === "Enter" || event.key === " ") {
            run(active);
          } else if (event.key === "Escape" || event.key === "ArrowLeft" || event.key === "Tab") {
            close();
          } else if (event.key.length === 1) {
            // A letter jumps to the entry whose shortcut it is, or that starts with it.
            const key = event.key;
            const byShortcut = actionable.find(
              ({ entry }) => entry !== "separator" && entry.shortcut === key,
            );
            const byLetter = actionable.find(
              ({ entry }) =>
                entry !== "separator" && entry.label.toLowerCase().startsWith(key.toLowerCase()),
            );
            const found = byShortcut ?? byLetter;
            if (found) {
              if (byShortcut) run(found.index);
              else setActive(found.index);
            }
          } else return;
          event.preventDefault();
          event.stopPropagation();
        }}
      >
        {items.map((entry, index) =>
          entry === "separator" ? (
            <div key={index} className="menu-sep" />
          ) : (
            <button
              key={index}
              type="button"
              role="menuitem"
              className="menu-item"
              data-tone={entry.tone}
              data-active={index === active}
              disabled={entry.disabled}
              data-tip={entry.disabled ? entry.hint : undefined}
              onPointerEnter={() => setActive(index)}
              onPointerLeave={() => setActive(-1)}
              onClick={() => run(index)}
            >
              {entry.icon ? <entry.icon size={14} /> : <span style={{ width: 14 }} />}
              <span className="label">{entry.label}</span>
              {entry.shortcut && <span className="shortcut">{entry.shortcut}</span>}
            </button>
          ),
        )}
      </motion.div>
    </>
  );
}

// ---- dialogs -------------------------------------------------------------------------------

export function DialogLayer() {
  const dialog = useStore((s) => s.dialog);
  return (
    <AnimatePresence>
      {dialog && (
        <motion.div
          key="dialog"
          className="overlay"
          data-center="true"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0, transition: { duration: 0.12 } }}
          transition={{ duration: 0.16 }}
          onPointerDown={(event) => {
            if (event.target === event.currentTarget) set({ dialog: null });
          }}
        >
          <motion.div
            initial={{ opacity: 0, scale: 0.96, y: 8 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.98, y: 4, transition: { duration: 0.12 } }}
            transition={{ type: "spring", duration: 0.32, bounce: 0.08 }}
          >
            <DialogBody dialog={dialog} />
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}

function DialogBody({ dialog }: { dialog: Dialog }) {
  if (dialog.kind === "confirm") return <ConfirmDialog dialog={dialog} />;
  if (dialog.kind === "pull") return <PullDialog initial={dialog.initial} />;
  return <PruneDialog preset={dialog.preset} />;
}

/** Keeps Tab inside the dialog, and closes it with Escape. */
function useDialogKeys(onEnter?: () => void) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const element = ref.current;
    if (!element) return;
    const keydown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault();
        event.stopPropagation();
        set({ dialog: null });
      } else if (event.key === "Tab") {
        const focusable = [
          ...element.querySelectorAll<HTMLElement>("button:not(:disabled), input"),
        ];
        if (focusable.length === 0) return;
        const first = focusable[0]!;
        const last = focusable.at(-1)!;
        if (event.shiftKey && document.activeElement === first) {
          event.preventDefault();
          last.focus();
        } else if (!event.shiftKey && document.activeElement === last) {
          event.preventDefault();
          first.focus();
        }
        event.stopPropagation();
      } else if (event.key === "Enter" && onEnter && !(event.target instanceof HTMLButtonElement)) {
        event.preventDefault();
        event.stopPropagation();
        onEnter();
      } else {
        event.stopPropagation();
      }
    };
    element.addEventListener("keydown", keydown);
    return () => element.removeEventListener("keydown", keydown);
  }, [onEnter]);
  return ref;
}

function ConfirmDialog({ dialog }: { dialog: Extract<Dialog, { kind: "confirm" }> }) {
  const [options, setOptions] = useState<ConfirmOption[]>(dialog.options ?? []);
  const confirmRef = useRef<HTMLButtonElement>(null);
  const confirm = () => {
    set({ dialog: null });
    dialog.onConfirm(Object.fromEntries(options.map((o) => [o.key, o.value])));
  };
  const ref = useDialogKeys(confirm);
  useEffect(() => confirmRef.current?.focus(), []);
  return (
    <div ref={ref} className="dialog" role="alertdialog" aria-modal aria-label={dialog.title}>
      <div style={{ display: "flex", gap: 12, alignItems: "flex-start" }}>
        {dialog.tone === "danger" && (
          <span
            className="event-icon"
            data-tone="danger"
            style={{ width: 30, height: 30, borderRadius: 9, flex: "none" }}
          >
            <AlertTriangle size={16} />
          </span>
        )}
        <div style={{ display: "grid", gap: 6 }}>
          <h2>{dialog.title}</h2>
          <p>{dialog.body}</p>
        </div>
      </div>
      {options.map((option, index) => (
        <button
          key={option.key}
          type="button"
          className="dialog-option"
          role="checkbox"
          aria-checked={option.value}
          onClick={() =>
            setOptions(options.map((o, i) => (i === index ? { ...o, value: !o.value } : o)))
          }
        >
          <Checkbox checked={option.value} />
          <span className="opt-main">
            {option.label}
            {option.hint && <span className="hint-text">{option.hint}</span>}
          </span>
        </button>
      ))}
      <div className="dialog-actions">
        <Button variant="ghost" onClick={() => set({ dialog: null })}>
          Cancel <span className="faint">esc</span>
        </Button>
        <Button
          ref={confirmRef}
          variant={dialog.tone === "danger" ? "danger" : "primary"}
          onClick={confirm}
        >
          {dialog.confirm} <span style={{ opacity: 0.6 }}>⏎</span>
        </Button>
      </div>
    </div>
  );
}

const PULL_SUGGESTIONS = [
  "nginx:alpine",
  "redis:7-alpine",
  "postgres:17-alpine",
  "node:22-alpine",
  "python:3.13-slim",
  "busybox",
];

function PullDialog({ initial }: { initial?: string }) {
  const [reference, setReference] = useState(initial ?? "");
  const input = useRef<HTMLInputElement>(null);
  const submit = () => {
    const value = reference.trim();
    if (!value) return;
    set({ dialog: null });
    void pullImage(value);
  };
  const ref = useDialogKeys(submit);
  useEffect(() => {
    input.current?.focus();
    input.current?.select();
  }, []);
  return (
    <div ref={ref} className="dialog" role="dialog" aria-modal aria-label="Pull an image">
      <div style={{ display: "grid", gap: 6 }}>
        <h2>Pull an image</h2>
        <p>
          A name with an optional tag; it runs in the background and the jobs show how far it got.
        </p>
      </div>
      <label className="field">
        <Download size={14} className="faint" />
        <input
          ref={input}
          value={reference}
          placeholder="nginx:alpine"
          spellCheck={false}
          onChange={(event) => setReference(event.target.value)}
        />
      </label>
      <div className="suggestions">
        {PULL_SUGGESTIONS.map((s) => (
          <button key={s} type="button" className="suggestion" onClick={() => setReference(s)}>
            {s}
          </button>
        ))}
      </div>
      <div className="dialog-actions">
        <Button variant="ghost" onClick={() => set({ dialog: null })}>
          Cancel <span className="faint">esc</span>
        </Button>
        <Button variant="primary" disabled={!reference.trim()} onClick={submit}>
          Pull <span style={{ opacity: 0.6 }}>⏎</span>
        </Button>
      </div>
    </div>
  );
}

const PRUNE_OPTIONS: {
  key: PruneTarget;
  label: string;
  hint: string;
  size: (d: NonNullable<ReturnType<typeof useStore.getState>["disk"]>) => number | undefined;
}[] = [
  {
    key: "containers",
    label: "Stopped containers",
    hint: "Every container that is not running",
    size: (d) => d.containers.reclaimable,
  },
  {
    key: "danglingImages",
    label: "Dangling images",
    hint: "Layers no tag points to any more",
    size: () => undefined,
  },
  {
    key: "unusedImages",
    label: "Unused images",
    hint: "Every image no container was made from",
    size: (d) => d.images.reclaimable,
  },
  {
    key: "volumes",
    label: "Unused volumes",
    hint: "Data no container mounts — gone for good",
    size: (d) => d.volumes.reclaimable,
  },
  {
    key: "networks",
    label: "Unused networks",
    hint: "Networks no container is on",
    size: () => undefined,
  },
  {
    key: "buildCache",
    label: "Build cache",
    hint: "What builds kept to go faster next time",
    size: (d) => d.buildCache.reclaimable,
  },
];

function PruneDialog({ preset }: { preset?: PruneTarget[] }) {
  const disk = useStore((s) => s.disk);
  const [chosen, setChosen] = useState<Set<PruneTarget>>(
    new Set(preset ?? ["containers", "danglingImages", "networks", "buildCache"]),
  );
  const total = useMemo(() => {
    if (!disk) return undefined;
    let sum = 0;
    for (const option of PRUNE_OPTIONS) if (chosen.has(option.key)) sum += option.size(disk) ?? 0;
    return sum;
  }, [disk, chosen]);
  const submit = () => {
    if (chosen.size === 0) return;
    set({ dialog: null });
    // In an order that frees most: containers first, so their images and volumes are unused.
    void prune(PRUNE_OPTIONS.map((o) => o.key).filter((k) => chosen.has(k)));
  };
  const ref = useDialogKeys(submit);
  const first = useRef<HTMLButtonElement>(null);
  useEffect(() => first.current?.focus(), []);
  const dangerous = chosen.has("volumes") || chosen.has("unusedImages");
  return (
    <div
      ref={ref}
      className="dialog"
      data-wide="true"
      role="dialog"
      aria-modal
      aria-label="Clean up"
    >
      <div style={{ display: "flex", gap: 12, alignItems: "flex-start" }}>
        <span
          className="event-icon"
          data-tone="info"
          style={{ width: 30, height: 30, borderRadius: 9, flex: "none" }}
        >
          <Sparkles size={16} />
        </span>
        <div style={{ display: "grid", gap: 6 }}>
          <h2>Clean up</h2>
          <p>Remove what nothing uses. Running containers, and what they use, are never touched.</p>
        </div>
      </div>
      <div style={{ display: "grid", gap: 4 }}>
        {PRUNE_OPTIONS.map((option, index) => {
          const size = disk ? option.size(disk) : undefined;
          return (
            <button
              key={option.key}
              ref={index === 0 ? first : undefined}
              type="button"
              className="dialog-option"
              role="checkbox"
              aria-checked={chosen.has(option.key)}
              onClick={() => {
                const next = new Set(chosen);
                if (next.has(option.key)) next.delete(option.key);
                else next.add(option.key);
                setChosen(next);
              }}
            >
              <Checkbox checked={chosen.has(option.key)} />
              <span className="opt-main">
                {option.label}
                <span className="hint-text">{option.hint}</span>
              </span>
              {size !== undefined && <span className="opt-size">{bytes(size)}</span>}
            </button>
          );
        })}
      </div>
      <div className="dialog-actions">
        <span className="grow muted">
          {total !== undefined && total > 0 ? (
            <>
              About <b style={{ color: "var(--fg)" }}>{bytes(total)}</b> to free
            </>
          ) : null}
        </span>
        <Button variant="ghost" onClick={() => set({ dialog: null })}>
          Cancel <span className="faint">esc</span>
        </Button>
        <Button
          variant={dangerous ? "danger" : "primary"}
          disabled={chosen.size === 0}
          onClick={submit}
        >
          Clean up <span style={{ opacity: 0.6 }}>⏎</span>
        </Button>
      </div>
    </div>
  );
}

// ---- toasts --------------------------------------------------------------------------------

const TOAST_ICONS = {
  success: CheckCircle2,
  danger: CircleAlert,
  warning: AlertTriangle,
  info: Info,
};

export function Toasts() {
  const toasts = useStore((s) => s.toasts);
  return (
    <div className="toasts" aria-live="polite">
      <AnimatePresence initial={false}>
        {toasts.map((t) => (
          <ToastCard key={t.id} toast={t} />
        ))}
      </AnimatePresence>
    </div>
  );
}

function ToastCard({ toast }: { toast: Toast }) {
  const [paused, setPaused] = useState(false);
  const left = useRef(toast.timeout);
  const started = useRef(Date.now());
  useEffect(() => {
    if (toast.timeout === 0 || paused) return;
    started.current = Date.now();
    const timer = setTimeout(() => dismissToast(toast.id), left.current);
    return () => {
      clearTimeout(timer);
      left.current -= Date.now() - started.current;
    };
  }, [paused, toast.id, toast.timeout]);
  const Icon = TOAST_ICONS[toast.tone];
  return (
    <motion.div
      layout
      className="toast"
      data-tone={toast.tone}
      role={toast.tone === "danger" ? "alert" : "status"}
      initial={{ opacity: 0, y: 14, scale: 0.97 }}
      animate={{ opacity: 1, y: 0, scale: 1 }}
      exit={{ opacity: 0, x: 24, scale: 0.98, transition: { duration: 0.16 } }}
      transition={{ type: "spring", duration: 0.38, bounce: 0.12 }}
      onPointerEnter={() => setPaused(true)}
      onPointerLeave={() => setPaused(false)}
    >
      <span className="toast-icon">
        <Icon size={15} />
      </span>
      <div style={{ minWidth: 0 }}>
        <div className="toast-title">{toast.title}</div>
        {toast.body && <div className="toast-body">{toast.body}</div>}
      </div>
      <div className="toast-actions">
        {toast.action && (
          <Button
            size="sm"
            variant="ghost"
            onClick={() => {
              dismissToast(toast.id);
              toast.action!.run();
            }}
            style={{ color: "var(--accent)" }}
          >
            {toast.action.label}
          </Button>
        )}
        <Button size="sm" variant="ghost" icon tip="Dismiss" onClick={() => dismissToast(toast.id)}>
          <X size={13} />
        </Button>
      </div>
      {toast.timeout > 0 && (
        <motion.div
          className="toast-timer"
          initial={{ scaleX: 1 }}
          animate={{ scaleX: paused ? undefined : 0 }}
          transition={{ duration: left.current / 1000, ease: "linear" }}
        />
      )}
    </motion.div>
  );
}

// ---- the hand-over of the pane ----------------------------------------------------------------

export function HandoffLayer() {
  const handingOff = useStore((s) => s.handingOff);
  return (
    <AnimatePresence>
      {handingOff && (
        <motion.div
          className="handoff"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={{ duration: 0.2 }}
        >
          <motion.div
            className="handoff-card"
            initial={{ opacity: 0, scale: 0.92, y: 10 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.96 }}
            transition={{ type: "spring", duration: 0.45, bounce: 0.15 }}
          >
            <motion.div
              className="handoff-glyph"
              animate={{ y: [0, -3, 0] }}
              transition={{ duration: 1.2, repeat: Infinity, ease: "easeInOut" }}
            >
              {handingOff.kind === "shell" ? (
                <SquareTerminal size={26} />
              ) : (
                <ScrollText size={26} />
              )}
            </motion.div>
            <div style={{ display: "grid", gap: 4 }}>
              <b>
                {handingOff.kind === "shell"
                  ? `Opening a shell in ${handingOff.name}`
                  : `Following the logs of ${handingOff.name}`}
              </b>
              <span className="muted">
                {handingOff.kind === "shell" ? (
                  <>
                    The pane is the terminal's until you <Kbd>exit</Kbd>
                  </>
                ) : (
                  <>
                    The pane is the terminal's until <Kbd>⌃C</Kbd>
                  </>
                )}
              </span>
            </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}

export function Scrim({ children, onClose }: { children: ReactNode; onClose: () => void }) {
  return (
    <motion.div
      className="overlay"
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0, transition: { duration: 0.12 } }}
      transition={{ duration: 0.15 }}
      onPointerDown={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <motion.div
        initial={{ opacity: 0, scale: 0.97, y: -6 }}
        animate={{ opacity: 1, scale: 1, y: 0 }}
        exit={{ opacity: 0, scale: 0.98, transition: { duration: 0.1 } }}
        transition={{ type: "spring", duration: 0.3, bounce: 0.06 }}
      >
        {children}
      </motion.div>
    </motion.div>
  );
}
