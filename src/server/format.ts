/** Text for what has no view: a model's tool result, and a terminal that shows no views. */

import type { ContainerSummary, DiskUsage } from "./types.js";

export function bytes(value: number): string {
  if (!Number.isFinite(value) || value < 0) return "–";
  const units = ["B", "KB", "MB", "GB", "TB"];
  let n = value;
  let unit = 0;
  while (n >= 1000 && unit < units.length - 1) {
    n /= 1000;
    unit += 1;
  }
  return `${n >= 100 || unit === 0 ? n.toFixed(0) : n.toFixed(1)} ${units[unit]}`;
}

export function portsOf(container: ContainerSummary): string {
  return container.ports
    .filter((port) => port.public !== undefined)
    .map((port) => `${port.public}→${port.private}`)
    .join(", ");
}

/** The containers as a table, with colour when `colour` is set (a terminal, not a model). */
export function containerTable(containers: readonly ContainerSummary[], colour = false): string {
  if (containers.length === 0) return "No containers.";
  const paint = (code: string, text: string) => (colour ? `\x1b[${code}m${text}\x1b[0m` : text);
  const rows = [...containers]
    .sort(
      (a, b) =>
        Number(b.state === "running") - Number(a.state === "running") ||
        (a.project ?? "").localeCompare(b.project ?? "") ||
        a.name.localeCompare(b.name),
    )
    .map((c) => ({
      dot:
        c.state === "running"
          ? c.health === "unhealthy"
            ? paint("33", "●")
            : paint("32", "●")
          : c.state === "paused"
            ? paint("33", "◐")
            : c.exitCode !== undefined && c.exitCode !== 0
              ? paint("31", "○")
              : paint("2", "○"),
      name: c.name,
      image: c.image,
      status: c.status,
      ports: portsOf(c),
    }));
  const width = (key: "name" | "image" | "status") =>
    Math.min(40, Math.max(...rows.map((row) => row[key].length)));
  const [name, image, status] = [width("name"), width("image"), width("status")];
  const clip = (text: string, size: number) =>
    text.length > size ? `${text.slice(0, size - 1)}…` : text.padEnd(size);
  return rows
    .map((row) =>
      `${row.dot} ${clip(row.name, name)}  ${paint("2", clip(row.image, image))}  ${clip(row.status, status)}  ${row.ports}`.trimEnd(),
    )
    .join("\n");
}

export function summaryLine(containers: readonly ContainerSummary[]): string {
  const running = containers.filter((c) => c.state === "running").length;
  const unhealthy = containers.filter((c) => c.health === "unhealthy").length;
  const parts = [`${running} running`, `${containers.length - running} stopped`];
  if (unhealthy > 0) parts.push(`${unhealthy} unhealthy`);
  return `${containers.length} containers: ${parts.join(", ")}`;
}

export function diskText(usage: DiskUsage): string {
  const line = (label: string, part: DiskUsage["images"]) =>
    `${label.padEnd(12)} ${String(part.count).padStart(4)}  ${bytes(part.size).padStart(9)}  ${bytes(part.reclaimable).padStart(9)} reclaimable`;
  return [
    line("Images", usage.images),
    line("Containers", usage.containers),
    line("Volumes", usage.volumes),
    line("Build cache", usage.buildCache),
  ].join("\n");
}
