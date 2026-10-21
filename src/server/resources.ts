/**
 * What containers are made of and run on: images, volumes, networks, the disk
 * they take, and the clean-up of what nothing uses.
 */

import { Docker, query } from "./docker.js";
import type {
  ContainerSummary,
  DiskUsage,
  ImageLayer,
  ImageSummary,
  NetworkSummary,
  PruneTarget,
  VolumeSummary,
} from "./types.js";

// ---- images ----------------------------------------------------------------------------

interface RawImage {
  Id: string;
  RepoTags?: string[] | null;
  RepoDigests?: string[] | null;
  Created: number;
  Size: number;
}

export async function listImages(
  docker: Docker,
  containers: readonly ContainerSummary[],
): Promise<ImageSummary[]> {
  const raw = await docker.get<RawImage[]>("/images/json");
  const users = new Map<string, string[]>();
  for (const container of containers) {
    users.set(container.imageId, [...(users.get(container.imageId) ?? []), container.name]);
  }
  return raw
    .map((image) => {
      const tags = (image.RepoTags ?? []).filter((tag) => tag !== "<none>:<none>");
      return {
        id: image.Id,
        tags,
        digests: (image.RepoDigests ?? []).filter((digest) => !digest.startsWith("<none>")),
        created: image.Created,
        size: image.Size,
        containers: users.get(image.Id) ?? [],
        dangling: tags.length === 0,
      };
    })
    .sort((a, b) => b.created - a.created);
}

export async function imageHistory(docker: Docker, id: string): Promise<ImageLayer[]> {
  const raw = await docker.get<
    { Id: string; Created: number; CreatedBy: string; Size: number; Comment: string }[]
  >(`/images/${encodeURIComponent(id)}/history`);
  return raw.map((layer) => ({
    id: layer.Id,
    created: layer.Created,
    createdBy: layer.CreatedBy.replace(/^\/bin\/sh -c #\(nop\)\s*/, "").replace(
      /^\/bin\/sh -c /,
      "RUN ",
    ),
    size: layer.Size,
    comment: layer.Comment,
  }));
}

export async function removeImage(docker: Docker, id: string, force: boolean): Promise<void> {
  await docker.call("DELETE", `/images/${encodeURIComponent(id)}${query({ force })}`, {
    timeout: 60_000,
  });
}

// ---- volumes ---------------------------------------------------------------------------

interface RawVolume {
  Name: string;
  Driver: string;
  Mountpoint: string;
  CreatedAt?: string;
  Labels?: Record<string, string> | null;
  UsageData?: { Size: number; RefCount: number } | null;
}

export async function listVolumes(
  docker: Docker,
  containers: readonly ContainerSummary[],
  sizes: Map<string, number> | undefined,
): Promise<VolumeSummary[]> {
  const raw = await docker.get<{ Volumes?: RawVolume[] | null }>("/volumes");
  const users = new Map<string, string[]>();
  for (const container of containers) {
    for (const mount of container.mounts) {
      if (mount.type !== "volume" || mount.name === undefined) continue;
      users.set(mount.name, [...(users.get(mount.name) ?? []), container.name]);
    }
  }
  return (raw.Volumes ?? [])
    .map((volume) => {
      const labels = volume.Labels ?? {};
      return {
        name: volume.Name,
        driver: volume.Driver,
        mountpoint: volume.Mountpoint,
        created: volume.CreatedAt ?? "",
        labels,
        anonymous: "com.docker.volume.anonymous" in labels || /^[0-9a-f]{64}$/.test(volume.Name),
        ...(labels["com.docker.compose.project"]
          ? { project: labels["com.docker.compose.project"] }
          : {}),
        size: sizes?.get(volume.Name) ?? -1,
        containers: users.get(volume.Name) ?? [],
      };
    })
    .sort((a, b) => Number(a.anonymous) - Number(b.anonymous) || a.name.localeCompare(b.name));
}

export async function removeVolume(docker: Docker, name: string): Promise<void> {
  await docker.call("DELETE", `/volumes/${encodeURIComponent(name)}`, { timeout: 30_000 });
}

// ---- networks --------------------------------------------------------------------------

interface RawNetwork {
  Id: string;
  Name: string;
  Driver: string;
  Scope: string;
  Internal: boolean;
  Created: string;
  Labels?: Record<string, string> | null;
  IPAM?: { Config?: { Subnet?: string; Gateway?: string }[] | null };
}

const BUILTIN_NETWORKS = new Set(["bridge", "host", "none"]);

export async function listNetworks(
  docker: Docker,
  containers: readonly ContainerSummary[],
): Promise<NetworkSummary[]> {
  const raw = await docker.get<RawNetwork[]>("/networks");
  const users = new Map<string, string[]>();
  for (const container of containers) {
    if (container.state !== "running") continue;
    for (const network of container.networks) {
      users.set(network, [...(users.get(network) ?? []), container.name]);
    }
  }
  return raw
    .map((network) => {
      const config = network.IPAM?.Config ?? [];
      const labels = network.Labels ?? {};
      return {
        id: network.Id,
        name: network.Name,
        driver: network.Driver,
        scope: network.Scope,
        internal: network.Internal,
        subnets: config.flatMap((c) => (c.Subnet ? [c.Subnet] : [])),
        gateways: config.flatMap((c) => (c.Gateway ? [c.Gateway] : [])),
        created: network.Created,
        builtin: BUILTIN_NETWORKS.has(network.Name),
        ...(labels["com.docker.compose.project"]
          ? { project: labels["com.docker.compose.project"] }
          : {}),
        containers: users.get(network.Name) ?? [],
      };
    })
    .sort((a, b) => Number(b.builtin) - Number(a.builtin) || a.name.localeCompare(b.name));
}

export async function removeNetwork(docker: Docker, id: string): Promise<void> {
  await docker.call("DELETE", `/networks/${encodeURIComponent(id)}`, { timeout: 30_000 });
}

// ---- disk ------------------------------------------------------------------------------

interface RawDf {
  LayersSize?: number;
  Images?: { Id: string; Size: number; SharedSize: number; Containers: number }[] | null;
  Containers?: { Id: string; SizeRw?: number; State: string }[] | null;
  Volumes?: RawVolume[] | null;
  BuildCache?: { Size: number; InUse: boolean; Shared: boolean }[] | null;
}

/**
 * The disk Docker takes, as `docker system df` counts it, and the size of each
 * volume. Counting volumes can take the engine a while on a busy machine, so the
 * answer is kept for a few seconds.
 */
export class DiskCounter {
  #last: { at: number; usage: DiskUsage; volumes: Map<string, number> } | undefined;
  #counting: Promise<{ usage: DiskUsage; volumes: Map<string, number> }> | undefined;

  constructor(readonly docker: Docker) {}

  /** The volumes' sizes from the last count, if there was one. */
  volumeSizes(): Map<string, number> | undefined {
    return this.#last?.volumes;
  }

  count(maxAge = 5000): Promise<{ usage: DiskUsage; volumes: Map<string, number> }> {
    const last = this.#last;
    if (last !== undefined && Date.now() - last.at < maxAge) return Promise.resolve(last);
    this.#counting ??= this.#count().finally(() => {
      this.#counting = undefined;
    });
    return this.#counting;
  }

  forget(): void {
    this.#last = undefined;
  }

  async #count(): Promise<{ usage: DiskUsage; volumes: Map<string, number> }> {
    const raw = await this.docker.get<RawDf>("/system/df", 60_000);
    const images = raw.Images ?? [];
    const containers = raw.Containers ?? [];
    const volumes = raw.Volumes ?? [];
    const cache = raw.BuildCache ?? [];
    const unused = images.filter((image) => image.Containers === 0);
    const usage: DiskUsage = {
      images: {
        count: images.length,
        active: images.length - unused.length,
        size: raw.LayersSize ?? images.reduce((sum, image) => sum + image.Size, 0),
        reclaimable: unused.reduce(
          (sum, image) => sum + Math.max(0, image.Size - Math.max(image.SharedSize, 0)),
          0,
        ),
      },
      containers: {
        count: containers.length,
        active: containers.filter((c) => c.State === "running").length,
        size: containers.reduce((sum, c) => sum + (c.SizeRw ?? 0), 0),
        reclaimable: containers
          .filter((c) => c.State !== "running")
          .reduce((sum, c) => sum + (c.SizeRw ?? 0), 0),
      },
      volumes: {
        count: volumes.length,
        active: volumes.filter((v) => (v.UsageData?.RefCount ?? 0) > 0).length,
        size: volumes.reduce((sum, v) => sum + Math.max(0, v.UsageData?.Size ?? 0), 0),
        reclaimable: volumes
          .filter((v) => (v.UsageData?.RefCount ?? 0) === 0)
          .reduce((sum, v) => sum + Math.max(0, v.UsageData?.Size ?? 0), 0),
      },
      buildCache: {
        count: cache.length,
        active: cache.filter((c) => c.InUse).length,
        size: cache.filter((c) => !c.Shared).reduce((sum, c) => sum + c.Size, 0),
        reclaimable: cache.filter((c) => !c.InUse && !c.Shared).reduce((sum, c) => sum + c.Size, 0),
      },
    };
    const sizes = new Map(volumes.map((v) => [v.Name, v.UsageData?.Size ?? -1]));
    this.#last = { at: Date.now(), usage, volumes: sizes };
    return this.#last;
  }
}

/** Removes what nothing uses, and says how many bytes came back. */
export async function prune(docker: Docker, target: PruneTarget): Promise<number> {
  const timeout = 10 * 60_000;
  switch (target) {
    case "containers": {
      const r = await docker.json<{ SpaceReclaimed?: number }>("POST", "/containers/prune", {
        timeout,
      });
      return r?.SpaceReclaimed ?? 0;
    }
    case "danglingImages":
    case "unusedImages": {
      const filters = { dangling: [target === "danglingImages" ? "true" : "false"] };
      const r = await docker.json<{ SpaceReclaimed?: number }>(
        "POST",
        `/images/prune${query({ filters })}`,
        { timeout },
      );
      return r?.SpaceReclaimed ?? 0;
    }
    case "volumes": {
      // From API 1.42 on, a prune keeps named volumes unless it is asked for all.
      const r = await docker.json<{ SpaceReclaimed?: number }>(
        "POST",
        `/volumes/prune${query({ filters: { all: ["true"] } })}`,
        { timeout },
      );
      return r?.SpaceReclaimed ?? 0;
    }
    case "networks":
      await docker.json("POST", "/networks/prune", { timeout });
      return 0;
    case "buildCache": {
      const r = await docker.json<{ SpaceReclaimed?: number }>("POST", "/build/prune", {
        timeout,
      });
      return r?.SpaceReclaimed ?? 0;
    }
  }
}

/**
 * Pulls `reference`, calling `progress` with how far it has come (0 to 1, when the
 * engine has said how big the layers are) and what it says it is doing.
 */
export async function pull(
  docker: Docker,
  reference: string,
  progress: (fraction: number | null, detail: string) => void,
): Promise<void> {
  const { image, tag } = splitReference(reference);
  const layers = new Map<string, { current: number; total: number; done: boolean }>();
  let rest = "";
  let failure: string | undefined;
  await docker.stream("POST", `/images/create${query({ fromImage: image, tag })}`, (chunk) => {
    rest += chunk.toString("utf8");
    const lines = rest.split("\n");
    rest = lines.pop() ?? "";
    for (const line of lines) {
      if (!line.trim()) continue;
      let event: {
        id?: string;
        status?: string;
        error?: string;
        progressDetail?: { current?: number; total?: number };
      };
      try {
        event = JSON.parse(line);
      } catch {
        continue;
      }
      if (event.error) failure = event.error;
      if (event.id && event.status) {
        const layer = layers.get(event.id) ?? { current: 0, total: 0, done: false };
        const detail = event.progressDetail ?? {};
        if (event.status === "Downloading" && detail.total) {
          layer.current = detail.current ?? layer.current;
          layer.total = detail.total;
        }
        if (/^(Download complete|Pull complete|Already exists)$/.test(event.status)) {
          layer.done = true;
          layer.current = layer.total;
        }
        layers.set(event.id, layer);
      }
      const known = [...layers.values()];
      const total = known.reduce((sum, layer) => sum + layer.total, 0);
      const current = known.reduce((sum, layer) => sum + layer.current, 0);
      const done = known.filter((layer) => layer.done).length;
      const fraction =
        total > 0 ? Math.min(1, current / total) : known.length ? done / known.length : null;
      progress(
        fraction,
        event.status && !event.id
          ? event.status
          : `${done}/${known.length} layers${event.status ? ` · ${event.status.toLowerCase()}` : ""}`,
      );
    }
  });
  if (failure !== undefined) throw new Error(failure);
}

function splitReference(reference: string): { image: string; tag: string } {
  const at = reference.indexOf("@");
  if (at >= 0) return { image: reference.slice(0, at), tag: reference.slice(at + 1) };
  const colon = reference.lastIndexOf(":");
  const slash = reference.lastIndexOf("/");
  if (colon > slash) return { image: reference.slice(0, colon), tag: reference.slice(colon + 1) };
  return { image: reference, tag: "latest" };
}
