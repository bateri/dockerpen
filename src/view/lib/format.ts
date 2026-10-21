/** Numbers, sizes and times, the way the view writes them. */

export function bytes(value: number, digits = 1): string {
  if (!Number.isFinite(value) || value < 0) return "–";
  const units = ["B", "KB", "MB", "GB", "TB"];
  let n = value;
  let unit = 0;
  while (n >= 1000 && unit < units.length - 1) {
    n /= 1000;
    unit += 1;
  }
  return `${unit === 0 || n >= 100 ? n.toFixed(0) : n.toFixed(digits)} ${units[unit]}`;
}

/** Memory as `docker stats` writes it: powers of 1024. */
export function memory(value: number): string {
  if (!Number.isFinite(value) || value < 0) return "–";
  const units = ["B", "KiB", "MiB", "GiB", "TiB"];
  let n = value;
  let unit = 0;
  while (n >= 1024 && unit < units.length - 1) {
    n /= 1024;
    unit += 1;
  }
  return `${unit === 0 || n >= 100 ? n.toFixed(0) : n.toFixed(1)} ${units[unit]}`;
}

export function rate(value: number): string {
  if (value < 1) return "0 B/s";
  return `${bytes(value)}/s`;
}

export function percent(value: number | null | undefined, digits = 1): string {
  if (value === null || value === undefined || !Number.isFinite(value)) return "–";
  return `${value >= 100 ? value.toFixed(0) : value.toFixed(digits)}%`;
}

export function shortId(id: string): string {
  return id.replace(/^sha256:/, "").slice(0, 12);
}

/** "3m", "2h", "5d": how long ago, short. */
export function ago(ms: number, now = Date.now()): string {
  const seconds = Math.max(0, Math.round((now - ms) / 1000));
  if (seconds < 45) return seconds < 5 ? "now" : `${seconds}s`;
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.round(minutes / 60);
  if (hours < 36) return `${hours}h`;
  const days = Math.round(hours / 24);
  if (days < 60) return `${days}d`;
  const months = Math.round(days / 30);
  if (months < 18) return `${months}mo`;
  return `${Math.round(months / 12)}y`;
}

export function agoLong(ms: number, now = Date.now()): string {
  const short = ago(ms, now);
  return short === "now" ? "just now" : `${short} ago`;
}

export function duration(ms: number): string {
  const seconds = Math.round(ms / 1000);
  if (seconds < 60) return `${seconds}s`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ${seconds % 60}s`;
  const hours = Math.floor(minutes / 60);
  return `${hours}h ${minutes % 60}m`;
}

export function clock(ms: number): string {
  const d = new Date(ms);
  return d.toLocaleTimeString(undefined, {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  });
}

export function dateTime(text: string | number): string {
  const d = typeof text === "number" ? new Date(text) : new Date(text);
  if (Number.isNaN(d.getTime()) || d.getFullYear() < 1971) return "–";
  return d.toLocaleString(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

/** The time of a log line, to the millisecond. */
export function logTime(text: string): string {
  const match = /T(\d\d:\d\d:\d\d)(\.\d{1,3})?/.exec(text);
  return match ? `${match[1]}${(match[2] ?? ".000").padEnd(4, "0")}` : "";
}

export function plural(count: number, one: string, many = `${one}s`): string {
  return `${count} ${count === 1 ? one : many}`;
}

/** An image's name without the registry's default parts: `docker.io/library/nginx` is `nginx`. */
export function imageName(reference: string): string {
  return reference.replace(/^docker\.io\//, "").replace(/^library\//, "");
}
