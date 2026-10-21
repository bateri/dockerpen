/** The small parts every screen is made of. */

import { motion } from "motion/react";
import { forwardRef, useEffect, useId, useLayoutEffect, useMemo, useRef, useState } from "react";
import type { ButtonHTMLAttributes, ReactNode } from "react";
import { Check, Search, X } from "lucide-react";

import type { ContainerSummary } from "../../server/types";
import { failed } from "../state/derive";

// ---- buttons ------------------------------------------------------------------------------

type Variant = "default" | "ghost" | "primary" | "danger" | "danger-ghost";

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
  size?: "sm" | "md";
  icon?: boolean;
  busy?: boolean;
  /** What the tooltip says, and the keys that do the same. */
  tip?: string;
  keys?: string;
  pressed?: boolean;
}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(function Button(
  {
    variant = "default",
    size = "md",
    icon,
    busy,
    tip,
    keys,
    pressed,
    children,
    className,
    ...rest
  },
  ref,
) {
  return (
    <button
      ref={ref}
      type="button"
      data-variant={variant}
      data-size={size}
      data-icon={icon ? "true" : undefined}
      data-busy={busy ? "true" : undefined}
      data-tip={tip}
      data-keys={keys}
      aria-label={icon ? tip : undefined}
      aria-pressed={pressed}
      aria-busy={busy}
      {...rest}
      className={className ? `btn ${className}` : "btn"}
    >
      {children}
      {busy && (
        <span className="btn-spinner">
          <span className="spinner" />
        </span>
      )}
    </button>
  );
});

export function Kbd({ children }: { children: ReactNode }) {
  return <kbd className="kbd">{children}</kbd>;
}

// ---- choosing ----------------------------------------------------------------------------

export interface SegmentOption<T extends string> {
  value: T;
  label: ReactNode;
  count?: number;
  tone?: "danger";
  tip?: string;
  keys?: string;
}

export function Segmented<T extends string>({
  value,
  options,
  onChange,
  label,
}: {
  value: T;
  options: SegmentOption<T>[];
  onChange: (value: T) => void;
  label: string;
}) {
  const id = useId();
  return (
    <div className="segmented" role="radiogroup" aria-label={label}>
      {options.map((option) => (
        <button
          key={option.value}
          type="button"
          role="radio"
          className="segment"
          aria-checked={option.value === value}
          data-tone={option.tone && (option.count ?? 0) > 0 ? option.tone : undefined}
          data-tip={option.tip}
          data-keys={option.keys}
          onClick={() => onChange(option.value)}
        >
          {option.value === value && (
            <motion.span
              layoutId={`segment-${id}`}
              className="segment-thumb"
              transition={{ type: "spring", duration: 0.35, bounce: 0.12 }}
            />
          )}
          <span>{option.label}</span>
          {option.count !== undefined && <span className="segment-count">{option.count}</span>}
        </button>
      ))}
    </div>
  );
}

export function Switch({
  checked,
  onChange,
  label,
  keys,
}: {
  checked: boolean;
  onChange: (value: boolean) => void;
  label: string;
  keys?: string;
}) {
  return (
    <button
      type="button"
      role="switch"
      className="switch"
      aria-checked={checked}
      data-tip={keys ? label : undefined}
      data-keys={keys}
      onClick={() => onChange(!checked)}
    >
      <span className="switch-track">
        <span className="switch-thumb" />
      </span>
      {label}
    </button>
  );
}

export function Checkbox({ checked }: { checked: boolean }) {
  return (
    <span className="checkbox" data-checked={checked} aria-hidden>
      {checked && (
        <motion.span
          initial={{ scale: 0.25, opacity: 0, filter: "blur(4px)" }}
          animate={{ scale: 1, opacity: 1, filter: "blur(0px)" }}
          transition={{ type: "spring", duration: 0.3, bounce: 0 }}
          style={{ display: "grid" }}
        >
          <Check size={12} strokeWidth={3} />
        </motion.span>
      )}
    </span>
  );
}

export const SearchField = forwardRef<
  HTMLInputElement,
  {
    value: string;
    onChange: (value: string) => void;
    placeholder: string;
    keys?: string;
    onKeyDown?: (event: React.KeyboardEvent<HTMLInputElement>) => void;
  }
>(function SearchField({ value, onChange, placeholder, keys, onKeyDown }, ref) {
  return (
    <label className="search">
      <Search size={14} />
      <input
        ref={ref}
        value={value}
        placeholder={placeholder}
        spellCheck={false}
        onChange={(event) => onChange(event.target.value)}
        onKeyDown={(event) => {
          if (event.key === "Escape") {
            event.preventDefault();
            if (value) onChange("");
            else event.currentTarget.blur();
            event.stopPropagation();
          }
          onKeyDown?.(event);
        }}
      />
      {value ? (
        <Button
          className="clear"
          variant="ghost"
          size="sm"
          icon
          tip="Clear"
          onClick={() => onChange("")}
        >
          <X size={13} />
        </Button>
      ) : (
        keys && <span className="kbd">{keys}</span>
      )}
    </label>
  );
});

// ---- showing ------------------------------------------------------------------------------

export function StatusDot({ container, busy }: { container: ContainerSummary; busy?: boolean }) {
  return (
    <span
      className="dot"
      data-state={container.state}
      data-health={container.state === "running" ? container.health : undefined}
      data-failed={failed(container) ? "true" : undefined}
      data-busy={busy ? "true" : undefined}
      aria-hidden
    />
  );
}

export function stateLabel(container: ContainerSummary): {
  text: string;
  tone?: "success" | "warning" | "danger" | "info";
} {
  if (container.state === "running") {
    if (container.health === "unhealthy") return { text: "unhealthy", tone: "danger" };
    if (container.health === "starting") return { text: "starting", tone: "warning" };
    return { text: container.health === "healthy" ? "healthy" : "running", tone: "success" };
  }
  if (container.state === "paused") return { text: "paused", tone: "warning" };
  if (container.state === "restarting") return { text: "restarting", tone: "warning" };
  if (container.state === "exited") {
    const code = container.exitCode;
    if (code === 137) return { text: "killed" };
    if (code === 143) return { text: "terminated" };
    if (code === 130) return { text: "interrupted" };
    return code !== undefined && code !== 0
      ? { text: `exited ${code}`, tone: "danger" }
      : { text: "exited" };
  }
  if (container.state === "dead") return { text: "dead", tone: "danger" };
  return { text: container.state };
}

export function Tag({
  children,
  tone,
  tip,
}: {
  children: ReactNode;
  tone?: "success" | "warning" | "danger" | "info" | "accent";
  tip?: string;
}) {
  return (
    <span className="tag" data-tone={tone} data-tip={tip}>
      {children}
    </span>
  );
}

export function Bar({ value, tone }: { value: number; tone?: "warning" | "danger" | "muted" }) {
  const clamped = Math.max(0, Math.min(1, Number.isFinite(value) ? value : 0));
  return (
    <div className="bar">
      <div className="bar-fill" data-tone={tone} style={{ scale: `${clamped} 1` }} />
    </div>
  );
}

export function Empty({
  icon,
  title,
  children,
  action,
}: {
  icon: ReactNode;
  title: string;
  children?: ReactNode;
  action?: ReactNode;
}) {
  return (
    <motion.div
      className="empty"
      initial={{ opacity: 0, y: 6 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.25, ease: [0.2, 0, 0, 1] }}
    >
      <div className="empty-icon">{icon}</div>
      <h3>{title}</h3>
      {children && <p>{children}</p>}
      {action}
    </motion.div>
  );
}

/** A number that moves to its new value instead of jumping. */
export function useTween(value: number, duration = 500): number {
  const [shown, setShown] = useState(value);
  const from = useRef(value);
  const frame = useRef(0);
  useEffect(() => {
    const start = performance.now();
    const origin = from.current;
    if (origin === value || window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      from.current = value;
      setShown(value);
      return;
    }
    const step = (now: number) => {
      const t = Math.min(1, (now - start) / duration);
      const eased = 1 - (1 - t) ** 3;
      const next = origin + (value - origin) * eased;
      from.current = next;
      setShown(next);
      if (t < 1) frame.current = requestAnimationFrame(step);
    };
    frame.current = requestAnimationFrame(step);
    return () => cancelAnimationFrame(frame.current);
  }, [value, duration]);
  return shown;
}

export function Tween({ value, format }: { value: number; format: (n: number) => string }) {
  return <>{format(useTween(value))}</>;
}

// ---- charts -------------------------------------------------------------------------------

function useWidth<T extends HTMLElement>(): [React.RefObject<T | null>, number] {
  const ref = useRef<T>(null);
  const [width, setWidth] = useState(0);
  useLayoutEffect(() => {
    const element = ref.current;
    if (!element) return;
    setWidth(element.clientWidth);
    const observer = new ResizeObserver(([entry]) => setWidth(entry?.contentRect.width ?? 0));
    observer.observe(element);
    return () => observer.disconnect();
  }, []);
  return [ref, width];
}

function path(points: [number, number][]): string {
  if (points.length === 0) return "";
  let d = `M${points[0]![0].toFixed(1)},${points[0]![1].toFixed(1)}`;
  for (let i = 1; i < points.length; i += 1) {
    const [x0, y0] = points[i - 1]!;
    const [x1, y1] = points[i]!;
    const mid = (x0 + x1) / 2;
    d += ` C${mid.toFixed(1)},${y0.toFixed(1)} ${mid.toFixed(1)},${y1.toFixed(1)} ${x1.toFixed(1)},${y1.toFixed(1)}`;
  }
  return d;
}

export interface Series {
  values: (number | null)[];
  color: string;
  fill?: boolean;
}

/**
 * A chart that scrolls: each new sample enters at the right and the line glides one
 * step to the left over the second until the next, the way a terminal's `top` does.
 */
export function LiveChart({
  series,
  capacity = 60,
  height = 54,
  max,
  format,
  times,
}: {
  series: Series[];
  capacity?: number;
  height?: number;
  max?: number;
  format?: (value: number) => string;
  times?: number[];
}) {
  const [ref, width] = useWidth<HTMLDivElement>();
  const gradient = useId();
  const group = useRef<SVGGElement>(null);
  const [hover, setHover] = useState<number | null>(null);
  const length = series[0]?.values.length ?? 0;
  const last = times?.at(-1) ?? length;

  const top = useMemo(() => {
    const peak = Math.max(
      0,
      ...series.flatMap((s) => s.values.filter((v): v is number => v !== null)),
    );
    const ceiling = max ?? peak * 1.25;
    return ceiling > 0 ? ceiling : 1;
  }, [series, max]);

  const step = width / Math.max(1, capacity - 1);
  const pad = 3;

  // Each new sample starts the line one step to the right and lets it glide back.
  useLayoutEffect(() => {
    const element = group.current;
    if (!element || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    element.style.transition = "none";
    element.style.transform = `translateX(${step}px)`;
    void element.getBoundingClientRect();
    element.style.transition = "transform 950ms linear";
    element.style.transform = "translateX(0)";
  }, [last, step]);

  const shapes = series.map((s, index) => {
    const values = s.values.slice(-capacity);
    const offset = capacity - values.length;
    const points: [number, number][] = [];
    values.forEach((v, i) => {
      if (v === null) return;
      const x = (offset + i) * step;
      const y = pad + (height - pad * 2) * (1 - Math.min(v, top) / top);
      points.push([x, y]);
    });
    const line = path(points);
    const area =
      points.length > 1
        ? `${line} L${points.at(-1)![0].toFixed(1)},${height} L${points[0]![0].toFixed(1)},${height} Z`
        : "";
    return { index, line, area, color: s.color, fill: s.fill, end: points.at(-1) };
  });

  const hovered =
    hover !== null && width > 0
      ? Math.max(0, Math.min(length - 1, length - 1 - Math.round((width - hover) / step)))
      : null;

  return (
    <div
      ref={ref}
      style={{ position: "relative", height }}
      onPointerMove={(event) => {
        const rect = event.currentTarget.getBoundingClientRect();
        setHover(event.clientX - rect.left);
      }}
      onPointerLeave={() => setHover(null)}
    >
      {width > 0 && (
        <svg className="chart" width={width} height={height} aria-hidden>
          <defs>
            {shapes.map((shape) => (
              <linearGradient
                key={shape.index}
                id={`${gradient}-${shape.index}`}
                x1="0"
                y1="0"
                x2="0"
                y2="1"
              >
                <stop offset="0%" stopColor={shape.color} stopOpacity={0.28} />
                <stop offset="100%" stopColor={shape.color} stopOpacity={0} />
              </linearGradient>
            ))}
          </defs>
          {[0.25, 0.5, 0.75].map((f) => (
            <line
              key={f}
              x1={0}
              x2={width}
              y1={height * f}
              y2={height * f}
              stroke="var(--line-2)"
              strokeDasharray="2 4"
            />
          ))}
          <g ref={group}>
            {shapes.map((shape) => (
              <g key={shape.index}>
                {shape.fill !== false && shape.area && (
                  <path d={shape.area} fill={`url(#${gradient}-${shape.index})`} />
                )}
                <path
                  d={shape.line}
                  fill="none"
                  stroke={shape.color}
                  strokeWidth={1.5}
                  strokeLinejoin="round"
                />
              </g>
            ))}
          </g>
          {hovered !== null && (
            <line
              x1={width - (length - 1 - hovered) * step}
              x2={width - (length - 1 - hovered) * step}
              y1={0}
              y2={height}
              stroke="var(--fg-3)"
              strokeWidth={1}
            />
          )}
        </svg>
      )}
      {hovered !== null && format && (
        <div className="chart-hover">
          {series
            .map((s) => s.values[hovered])
            .map((v, i) => (
              <span key={i} style={{ color: series[i]!.color, marginLeft: i ? 8 : 0 }}>
                {v === null || v === undefined ? "–" : format(v)}
              </span>
            ))}
          {times?.[hovered] !== undefined && (
            <span className="faint" style={{ marginLeft: 8 }}>
              {new Date(times[hovered]!).toLocaleTimeString(undefined, {
                hour: "2-digit",
                minute: "2-digit",
                second: "2-digit",
              })}
            </span>
          )}
        </div>
      )}
    </div>
  );
}

/** A small line of recent values, for rows and the rail. */
export function Sparkline({
  values,
  color = "var(--accent)",
  width = 54,
  height = 16,
  max,
}: {
  values: (number | null)[];
  color?: string;
  width?: number;
  height?: number;
  max?: number;
}) {
  const id = useId();
  const kept = values.slice(-30);
  const peak = max ?? Math.max(1e-9, ...kept.filter((v): v is number => v !== null)) * 1.15;
  const step = width / 29;
  const offset = 30 - kept.length;
  const points: [number, number][] = [];
  kept.forEach((v, i) => {
    if (v === null) return;
    points.push([(offset + i) * step, 1 + (height - 2) * (1 - Math.min(v, peak) / peak)]);
  });
  const line = path(points);
  return (
    <svg
      width={width}
      height={height}
      aria-hidden
      style={{ display: "block", overflow: "visible" }}
    >
      <defs>
        <linearGradient id={id} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={color} stopOpacity={0.3} />
          <stop offset="100%" stopColor={color} stopOpacity={0} />
        </linearGradient>
      </defs>
      {points.length > 1 && (
        <>
          <path
            d={`${line} L${points.at(-1)![0]},${height} L${points[0]![0]},${height} Z`}
            fill={`url(#${id})`}
          />
          <path d={line} fill="none" stroke={color} strokeWidth={1.25} />
        </>
      )}
    </svg>
  );
}

// ---- tooltips -----------------------------------------------------------------------------

/**
 * One tooltip for the page: any element with `data-tip` (and `data-keys`, the keys that do
 * the same) shows it after a moment's hover, and at once while moving from one to the next.
 */
export function Tooltips() {
  const [tip, setTip] = useState<{
    text: string;
    keys?: string;
    x: number;
    y: number;
    below: boolean;
  } | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const warm = useRef(0);

  useEffect(() => {
    const show = (target: HTMLElement) => {
      const text = target.dataset.tip;
      if (!text) return;
      const rect = target.getBoundingClientRect();
      const below = rect.top < 40;
      setTip({
        text,
        keys: target.dataset.keys,
        x: rect.left + rect.width / 2,
        y: below ? rect.bottom + 6 : rect.top - 6,
        below,
      });
      warm.current = Date.now();
    };
    const over = (event: PointerEvent) => {
      const target = (event.target as HTMLElement | null)?.closest<HTMLElement>("[data-tip]");
      clearTimeout(timer.current);
      if (!target) {
        setTip(null);
        return;
      }
      const delay = Date.now() - warm.current < 600 ? 0 : 480;
      timer.current = setTimeout(() => show(target), delay);
    };
    const hide = () => {
      clearTimeout(timer.current);
      setTip((current) => {
        if (current) warm.current = Date.now();
        return null;
      });
    };
    document.addEventListener("pointerover", over);
    document.addEventListener("pointerdown", hide, true);
    document.addEventListener("keydown", hide, true);
    document.addEventListener("scroll", hide, true);
    return () => {
      document.removeEventListener("pointerover", over);
      document.removeEventListener("pointerdown", hide, true);
      document.removeEventListener("keydown", hide, true);
      document.removeEventListener("scroll", hide, true);
    };
  }, []);

  const ref = useRef<HTMLDivElement>(null);
  const [shift, setShift] = useState(0);
  useLayoutEffect(() => {
    const element = ref.current;
    if (!element || !tip) return;
    const rect = element.getBoundingClientRect();
    const overflowRight = rect.right - (window.innerWidth - 6);
    const overflowLeft = 6 - rect.left;
    setShift(overflowRight > 0 ? -overflowRight : overflowLeft > 0 ? overflowLeft : 0);
  }, [tip]);

  if (!tip) return null;
  return (
    <motion.div
      ref={ref}
      className="tooltip"
      role="tooltip"
      initial={{ opacity: 0, y: tip.below ? -3 : 3, scale: 0.97 }}
      animate={{ opacity: 1, y: 0, scale: 1 }}
      transition={{ duration: 0.14, ease: [0.2, 0, 0, 1] }}
      style={{
        left: tip.x + shift,
        top: tip.y,
        translateX: "-50%",
        translateY: tip.below ? "0%" : "-100%",
      }}
    >
      {tip.text}
      {tip.keys && <span className="kbd">{tip.keys}</span>}
    </motion.div>
  );
}
