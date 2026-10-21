/** Images, volumes and networks: tables that read the same and answer the same keys. */

import { AnimatePresence, motion } from "motion/react";
import { Fragment, useEffect, useMemo, useRef, useState } from "react";
import type { ReactNode } from "react";
import {
  ChevronDown,
  ChevronRight,
  Download,
  HardDrive,
  Layers,
  Network,
  RefreshCw,
  SearchX,
  Sparkles,
  Trash2,
} from "lucide-react";

import type { ImageLayer, ImageSummary, NetworkSummary, VolumeSummary } from "../../server/types";
import {
  askRemoveImages,
  askRemoveNetworks,
  askRemoveVolumes,
  copyText,
  loadDisk,
  loadImages,
  loadNetworks,
  loadVolumes,
  pullImage,
} from "../state/actions";
import { call } from "../lib/bridge";
import { contains } from "../state/derive";
import { ago, bytes, dateTime, imageName, plural, shortId } from "../lib/format";
import { moveBy, useKeyLayer } from "../state/keys";
import { get, openMenu, pick, set, useStore } from "../state/store";
import { openDetail } from "../state/commands";
import { Bar, Button, Checkbox, Empty, SearchField, Segmented, Tag } from "./ui";

/** Reads a section's data when it is shown, and again every so often while it is. */
function useRefresh(load: () => Promise<void>, every: number) {
  useEffect(() => {
    void load();
    const timer = setInterval(() => void load(), every);
    return () => clearInterval(timer);
  }, [load, every]);
}

/** The keys of a table: moving, marking, and what the section adds. */
function useTableKeys<T>(
  rows: readonly T[],
  keyOf: (row: T) => string,
  chosen: string,
  choose: (key: string) => void,
  marked: Set<string>,
  setMarked: (next: Set<string>) => void,
  extra: (event: KeyboardEvent, row: T | undefined) => boolean,
  search: () => void,
) {
  useKeyLayer(
    (event) => {
      const at = rows.findIndex((row) => keyOf(row) === chosen);
      const moved = moveBy(event, at, rows.length);
      if (moved !== undefined && !event.ctrlKey) {
        choose(keyOf(rows[moved]!));
        return true;
      }
      const row = rows[at];
      if (event.key === " " && row) {
        const next = new Set(marked);
        const key = keyOf(row);
        if (next.has(key)) next.delete(key);
        else next.add(key);
        setMarked(next);
        if (at < rows.length - 1) choose(keyOf(rows[at + 1]!));
        return true;
      }
      if (event.key === "a") {
        setMarked(new Set(rows.map(keyOf)));
        return true;
      }
      if (event.key === "A" || (event.key === "Escape" && marked.size > 0)) {
        setMarked(new Set());
        return true;
      }
      return extra(event, row);
    },
    { search },
  );
}

function useChosen<T>(
  rows: readonly T[],
  keyOf: (row: T) => string,
  section: "images" | "volumes" | "networks",
) {
  const chosen = useStore((s) => s.pick[section]);
  const choose = (key: string) => pick(section, key);
  useEffect(() => {
    if (rows.length > 0 && !rows.some((row) => keyOf(row) === chosen))
      pick(section, keyOf(rows[0]!));
  }, [rows, chosen, keyOf, section]);
  // The chosen row stays in sight.
  useEffect(() => {
    document
      .querySelector<HTMLElement>(`[data-row="${CSS.escape(chosen)}"]`)
      ?.scrollIntoView({ block: "nearest" });
  }, [chosen]);
  return [chosen, choose] as const;
}

function Header({ title, sub, children }: { title: string; sub: ReactNode; children?: ReactNode }) {
  return (
    <header className="header">
      <h1>{title}</h1>
      <span className="sub">{sub}</span>
      <span className="header-spacer" />
      {children}
    </header>
  );
}

function Loading() {
  return (
    <div style={{ padding: "8px 16px", display: "grid", gap: 10 }}>
      {Array.from({ length: 8 }, (_, i) => (
        <div key={i} style={{ display: "flex", gap: 12 }}>
          <div className="skeleton" style={{ height: 14, width: `${28 + ((i * 23) % 30)}%` }} />
          <div className="skeleton" style={{ height: 14, width: "12%" }} />
          <div className="skeleton" style={{ height: 14, width: "18%" }} />
        </div>
      ))}
    </div>
  );
}

const rowIn = {
  initial: { opacity: 0 },
  animate: { opacity: 1 },
  exit: { opacity: 0, transition: { duration: 0.12 } },
  transition: { duration: 0.2 },
};

// ---- images -------------------------------------------------------------------------------------

type ImageFilter = "all" | "used" | "unused" | "dangling";

export function ImagesSection() {
  const images = useStore((s) => s.images);
  const [filter, setFilter] = useState<ImageFilter>("all");
  const [query, setQuery] = useState("");
  const [sort, setSort] = useState<"created" | "size" | "name">("created");
  const [marked, setMarked] = useState<Set<string>>(new Set());
  const [open, setOpen] = useState<string | null>(null);
  const search = useRef<HTMLInputElement>(null);
  useRefresh(loadImages, 15_000);

  const name = (image: ImageSummary) =>
    image.tags[0] ? imageName(image.tags[0]) : `<none> ${shortId(image.id)}`;
  const rows = useMemo(() => {
    const list = (images ?? []).filter((image) => {
      if (filter === "used" && image.containers.length === 0) return false;
      if (filter === "unused" && image.containers.length > 0) return false;
      if (filter === "dangling" && !image.dangling) return false;
      return (
        !query ||
        contains(
          `${image.tags.join(" ")} ${shortId(image.id)} ${image.containers.join(" ")}`,
          query,
        )
      );
    });
    return list.sort((a, b) =>
      sort === "size"
        ? b.size - a.size
        : sort === "name"
          ? name(a).localeCompare(name(b))
          : b.created - a.created,
    );
  }, [images, filter, query, sort]);
  const keyOf = (image: ImageSummary) => image.id;
  const [chosen, choose] = useChosen(rows, keyOf, "images");
  const largest = Math.max(1, ...rows.map((i) => i.size));
  const total = (images ?? []).reduce((sum, i) => sum + i.size, 0);
  const counts = {
    all: images?.length ?? 0,
    used: (images ?? []).filter((i) => i.containers.length > 0).length,
    unused: (images ?? []).filter((i) => i.containers.length === 0).length,
    dangling: (images ?? []).filter((i) => i.dangling).length,
  };
  const targets = () =>
    marked.size > 0
      ? (images ?? []).filter((i) => marked.has(i.id))
      : rows.filter((i) => i.id === chosen);

  useTableKeys(
    rows,
    keyOf,
    chosen,
    choose,
    marked,
    setMarked,
    (event, row) => {
      if (event.key === "Enter" || event.key === "ArrowRight" || event.key === "ArrowLeft") {
        if (row)
          setOpen(
            event.key === "ArrowLeft"
              ? null
              : open === row.id && event.key === "Enter"
                ? null
                : row.id,
          );
        return true;
      }
      if (event.key === "d" || event.key === "Delete" || event.key === "Backspace") {
        askRemoveImages(targets());
        return true;
      }
      if (event.key === "p") {
        set({ dialog: { kind: "pull" } });
        return true;
      }
      if (event.key === "u" && row?.tags[0]) {
        void pullImage(row.tags[0]);
        return true;
      }
      if (event.key === "y" && row) {
        void copyText(row.tags[0] ?? row.id, "the name");
        return true;
      }
      return false;
    },
    () => search.current?.focus(),
  );

  const menu = (event: React.MouseEvent, image: ImageSummary) => {
    event.preventDefault();
    choose(image.id);
    openMenu({
      x: event.clientX,
      y: event.clientY,
      entries: [
        {
          label: open === image.id ? "Hide layers" : "Show layers",
          icon: Layers,
          shortcut: "⏎",
          run: () => setOpen(open === image.id ? null : image.id),
        },
        ...(image.tags[0]
          ? [
              {
                label: `Pull ${imageName(image.tags[0])} again`,
                icon: RefreshCw,
                shortcut: "u",
                run: () => void pullImage(image.tags[0]!),
              },
            ]
          : []),
        {
          label: "Copy name",
          icon: undefined,
          shortcut: "y",
          run: () => void copyText(image.tags[0] ?? image.id, "the name"),
        },
        "separator",
        {
          label: "Remove…",
          icon: Trash2,
          shortcut: "d",
          tone: "danger",
          run: () => askRemoveImages(marked.has(image.id) ? targets() : [image]),
        },
      ],
    });
  };

  return (
    <div className="section">
      <Header
        title="Images"
        sub={images ? `${plural(images.length, "image")} · ${bytes(total)}` : "reading…"}
      >
        <Button
          size="sm"
          variant="ghost"
          tip="Pull an image"
          keys="p"
          onClick={() => set({ dialog: { kind: "pull" } })}
        >
          <Download size={13} /> Pull
        </Button>
        <Button
          size="sm"
          variant="ghost"
          tip="Remove the images no container uses"
          onClick={() => {
            void loadDisk();
            set({ dialog: { kind: "prune", preset: ["danglingImages", "unusedImages"] } });
          }}
        >
          <Sparkles size={13} /> Clean up
        </Button>
      </Header>
      <div className="toolbar">
        <SearchField
          ref={search}
          value={query}
          onChange={setQuery}
          placeholder="Filter images"
          keys="/"
        />
        <Segmented
          label="Show"
          value={filter}
          onChange={setFilter}
          options={[
            { value: "all", label: "All", count: counts.all },
            { value: "used", label: "In use", count: counts.used },
            { value: "unused", label: "Unused", count: counts.unused },
            {
              value: "dangling",
              label: "Dangling",
              count: counts.dangling,
              tip: "Untagged layers left by rebuilds",
            },
          ]}
        />
        {marked.size > 0 && (
          <Button size="sm" variant="danger-ghost" onClick={() => askRemoveImages(targets())}>
            <Trash2 size={12} /> Remove {marked.size}
          </Button>
        )}
      </div>
      {images === null ? (
        <Loading />
      ) : rows.length === 0 ? (
        <Empty
          icon={images.length ? <SearchX size={20} /> : <Layers size={20} />}
          title={images.length ? "Nothing matches" : "No images"}
        >
          {images.length ? "Try another filter." : "Pull one to start: press p."}
        </Empty>
      ) : (
        <div className="table-scroll">
          <table className="table">
            <colgroup>
              <col style={{ width: 38 }} />
              <col />
              <col style={{ width: 120 }} />
              <col style={{ width: 170 }} />
              <col style={{ width: 70 }} />
              <col style={{ width: "22%" }} />
            </colgroup>
            <thead>
              <tr>
                <th />
                <th>
                  <button
                    type="button"
                    data-active={sort === "name"}
                    onClick={() => setSort("name")}
                  >
                    Name
                  </button>
                </th>
                <th>Id</th>
                <th>
                  <button
                    type="button"
                    data-active={sort === "size"}
                    onClick={() => setSort("size")}
                  >
                    Size
                  </button>
                </th>
                <th>
                  <button
                    type="button"
                    data-active={sort === "created"}
                    onClick={() => setSort("created")}
                  >
                    Age
                  </button>
                </th>
                <th>Used by</th>
              </tr>
            </thead>
            <tbody>
              <AnimatePresence initial={false}>
                {rows.map((image) => (
                  <Fragment key={image.id}>
                    <motion.tr
                      {...rowIn}
                      data-row={image.id}
                      data-selected={image.id === chosen}
                      data-marked={marked.has(image.id)}
                      onPointerDown={(event) => {
                        if (event.button !== 0) return;
                        if (event.metaKey || event.ctrlKey) {
                          const next = new Set(marked);
                          if (next.has(image.id)) next.delete(image.id);
                          else next.add(image.id);
                          setMarked(next);
                        }
                        choose(image.id);
                      }}
                      onDoubleClick={() => setOpen(open === image.id ? null : image.id)}
                      onContextMenu={(event) => menu(event, image)}
                    >
                      <td>
                        {marked.size > 0 ? (
                          <Checkbox checked={marked.has(image.id)} />
                        ) : (
                          <button
                            type="button"
                            className="btn"
                            data-variant="ghost"
                            data-size="sm"
                            data-icon="true"
                            aria-label="Layers"
                            onClick={() => setOpen(open === image.id ? null : image.id)}
                          >
                            {open === image.id ? (
                              <ChevronDown size={13} />
                            ) : (
                              <ChevronRight size={13} />
                            )}
                          </button>
                        )}
                      </td>
                      <td>
                        <span className="cell-stack">
                          <span
                            className="ellipsis"
                            style={{
                              fontWeight: 600,
                              color: image.dangling ? "var(--fg-3)" : undefined,
                            }}
                          >
                            {name(image)}
                          </span>
                          {image.tags.length > 1 && (
                            <Tag tip={image.tags.slice(1).join(", ")}>+{image.tags.length - 1}</Tag>
                          )}
                          {image.dangling && <Tag tone="warning">dangling</Tag>}
                        </span>
                      </td>
                      <td className="faint">{shortId(image.id)}</td>
                      <td>
                        <span className="size-cell">
                          <span style={{ textAlign: "right" }}>{bytes(image.size)}</span>
                          <Bar
                            value={image.size / largest}
                            tone={image.containers.length ? undefined : "muted"}
                          />
                        </span>
                      </td>
                      <td className="muted" data-tip={dateTime(image.created * 1000)}>
                        {ago(image.created * 1000)}
                      </td>
                      <td>
                        {image.containers.length > 0 ? (
                          <span className="cell-stack">
                            <Tag tone="success">{image.containers.length}</Tag>
                            <span className="ellipsis muted">{image.containers.join(", ")}</span>
                          </span>
                        ) : (
                          <span className="faint">unused</span>
                        )}
                      </td>
                    </motion.tr>
                    {open === image.id && (
                      <tr>
                        <td
                          colSpan={6}
                          style={{
                            height: "auto",
                            padding: 0,
                            whiteSpace: "normal",
                            maxWidth: "none",
                          }}
                        >
                          <ImageLayers image={image} />
                        </td>
                      </tr>
                    )}
                  </Fragment>
                ))}
              </AnimatePresence>
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

function ImageLayers({ image }: { image: ImageSummary }) {
  const [layers, setLayers] = useState<ImageLayer[] | null>(null);
  const containers = useStore((s) => s.containers);
  useEffect(() => {
    let alive = true;
    void call<{ layers: ImageLayer[] }>("image_history", { id: image.id }).then(
      (r) => alive && setLayers(r.layers),
      () => alive && setLayers([]),
    );
    return () => {
      alive = false;
    };
  }, [image.id]);
  const largest = Math.max(1, ...(layers ?? []).map((l) => l.size));
  return (
    <motion.div
      initial={{ height: 0, opacity: 0 }}
      animate={{ height: "auto", opacity: 1 }}
      transition={{ duration: 0.24, ease: [0.2, 0, 0, 1] }}
      style={{ overflow: "hidden" }}
    >
      <div
        style={{
          margin: "2px 6px 10px 34px",
          padding: 10,
          borderRadius: 10,
          background: "var(--bg-2)",
          display: "grid",
          gap: 8,
        }}
      >
        {image.tags.length > 0 && (
          <div className="cell-stack" style={{ flexWrap: "wrap" }}>
            {image.tags.map((tag) => (
              <Tag key={tag}>{tag}</Tag>
            ))}
          </div>
        )}
        {image.containers.length > 0 && (
          <div className="cell-stack" style={{ flexWrap: "wrap" }}>
            <span className="faint">used by</span>
            {image.containers.map((n) => {
              const c = containers.find((x) => x.name === n);
              return (
                <button
                  key={n}
                  type="button"
                  className="suggestion"
                  onClick={() => c && openDetail(c.id)}
                >
                  {n}
                </button>
              );
            })}
          </div>
        )}
        {layers === null ? (
          <div className="skeleton" style={{ height: 60 }} />
        ) : (
          <div style={{ display: "grid", gap: 2 }}>
            {layers.map((layer, i) => (
              <div
                key={`${layer.id}${i}`}
                style={{
                  display: "grid",
                  gridTemplateColumns: "70px 60px minmax(0, 1fr)",
                  gap: 10,
                  alignItems: "center",
                  fontSize: 11.5,
                }}
              >
                <span style={{ textAlign: "right" }} className={layer.size ? "" : "faint"}>
                  {layer.size ? bytes(layer.size) : "0"}
                </span>
                <Bar value={layer.size / largest} tone={layer.size ? undefined : "muted"} />
                <span
                  className="ellipsis muted selectable"
                  data-tip={layer.createdBy.length > 60 ? layer.createdBy.slice(0, 300) : undefined}
                >
                  {layer.createdBy || layer.comment || shortId(layer.id)}
                </span>
              </div>
            ))}
          </div>
        )}
      </div>
    </motion.div>
  );
}

// ---- volumes -------------------------------------------------------------------------------------

type VolumeFilter = "all" | "used" | "unused" | "anonymous";

export function VolumesSection() {
  const volumes = useStore((s) => s.volumes);
  const sized = useStore((s) => s.volumesSized);
  const [filter, setFilter] = useState<VolumeFilter>("all");
  const [query, setQuery] = useState("");
  const [marked, setMarked] = useState<Set<string>>(new Set());
  const search = useRef<HTMLInputElement>(null);

  // The list comes at once; the sizes, which Docker takes a while to count, after it.
  useEffect(() => {
    void loadVolumes(false).then(() => loadVolumes(true));
    const timer = setInterval(() => void loadVolumes(true), 30_000);
    return () => clearInterval(timer);
  }, []);

  const rows = useMemo(
    () =>
      (volumes ?? []).filter((v) => {
        if (filter === "used" && v.containers.length === 0) return false;
        if (filter === "unused" && v.containers.length > 0) return false;
        if (filter === "anonymous" && !v.anonymous) return false;
        return !query || contains(`${v.name} ${v.project ?? ""} ${v.containers.join(" ")}`, query);
      }),
    [volumes, filter, query],
  );
  const keyOf = (v: VolumeSummary) => v.name;
  const [chosen, choose] = useChosen(rows, keyOf, "volumes");
  const largest = Math.max(1, ...rows.map((v) => v.size));
  const total = (volumes ?? []).reduce((sum, v) => sum + Math.max(0, v.size), 0);
  const targets = () =>
    marked.size > 0
      ? (volumes ?? []).filter((v) => marked.has(v.name))
      : rows.filter((v) => v.name === chosen);
  const label = (v: VolumeSummary) =>
    v.anonymous && /^[0-9a-f]{64}$/.test(v.name) ? shortId(v.name) : v.name;

  useTableKeys(
    rows,
    keyOf,
    chosen,
    choose,
    marked,
    setMarked,
    (event, row) => {
      if (event.key === "d" || event.key === "Delete" || event.key === "Backspace") {
        askRemoveVolumes(targets());
        return true;
      }
      if (event.key === "y" && row) {
        void copyText(row.name, "the name");
        return true;
      }
      if (event.key === "Enter" && row && row.containers[0]) {
        const c = get().containers.find((x) => x.name === row.containers[0]);
        if (c) openDetail(c.id);
        return true;
      }
      return false;
    },
    () => search.current?.focus(),
  );

  return (
    <div className="section">
      <Header
        title="Volumes"
        sub={
          volumes
            ? `${plural(volumes.length, "volume")}${sized ? ` · ${bytes(total)}` : ""}`
            : "reading…"
        }
      >
        <Button
          size="sm"
          variant="ghost"
          tip="Remove the volumes no container uses"
          onClick={() => {
            void loadDisk();
            set({ dialog: { kind: "prune", preset: ["volumes"] } });
          }}
        >
          <Sparkles size={13} /> Clean up
        </Button>
      </Header>
      <div className="toolbar">
        <SearchField
          ref={search}
          value={query}
          onChange={setQuery}
          placeholder="Filter volumes"
          keys="/"
        />
        <Segmented
          label="Show"
          value={filter}
          onChange={setFilter}
          options={[
            { value: "all", label: "All", count: volumes?.length ?? 0 },
            {
              value: "used",
              label: "In use",
              count: (volumes ?? []).filter((v) => v.containers.length > 0).length,
            },
            {
              value: "unused",
              label: "Unused",
              count: (volumes ?? []).filter((v) => v.containers.length === 0).length,
            },
            {
              value: "anonymous",
              label: "Anonymous",
              count: (volumes ?? []).filter((v) => v.anonymous).length,
            },
          ]}
        />
        {marked.size > 0 && (
          <Button size="sm" variant="danger-ghost" onClick={() => askRemoveVolumes(targets())}>
            <Trash2 size={12} /> Remove {marked.size}
          </Button>
        )}
      </div>
      {volumes === null ? (
        <Loading />
      ) : rows.length === 0 ? (
        <Empty
          icon={volumes.length ? <SearchX size={20} /> : <HardDrive size={20} />}
          title={volumes.length ? "Nothing matches" : "No volumes"}
        />
      ) : (
        <div className="table-scroll">
          <table className="table">
            <colgroup>
              <col style={{ width: 38 }} />
              <col />
              <col style={{ width: 170 }} />
              <col style={{ width: "26%" }} />
              <col style={{ width: 72 }} />
            </colgroup>
            <thead>
              <tr>
                <th />
                <th>Name</th>
                <th>Size</th>
                <th>Used by</th>
                <th>Driver</th>
              </tr>
            </thead>
            <tbody>
              <AnimatePresence initial={false}>
                {rows.map((v) => (
                  <motion.tr
                    {...rowIn}
                    key={v.name}
                    data-row={v.name}
                    data-selected={v.name === chosen}
                    data-marked={marked.has(v.name)}
                    onPointerDown={(event) => {
                      if (event.button !== 0) return;
                      if (event.metaKey || event.ctrlKey) {
                        const next = new Set(marked);
                        if (next.has(v.name)) next.delete(v.name);
                        else next.add(v.name);
                        setMarked(next);
                      }
                      choose(v.name);
                    }}
                    onContextMenu={(event) => {
                      event.preventDefault();
                      choose(v.name);
                      openMenu({
                        x: event.clientX,
                        y: event.clientY,
                        entries: [
                          {
                            label: "Copy name",
                            shortcut: "y",
                            run: () => void copyText(v.name, "the name"),
                          },
                          {
                            label: "Copy mount point",
                            run: () => void copyText(v.mountpoint, "the mount point"),
                          },
                          "separator",
                          {
                            label: "Remove…",
                            icon: Trash2,
                            shortcut: "d",
                            tone: "danger",
                            disabled: v.containers.length > 0,
                            hint: `In use by ${v.containers.join(", ")}`,
                            run: () => askRemoveVolumes([v]),
                          },
                        ],
                      });
                    }}
                  >
                    <td>
                      {marked.size > 0 ? (
                        <Checkbox checked={marked.has(v.name)} />
                      ) : (
                        <HardDrive size={13} className="faint" />
                      )}
                    </td>
                    <td>
                      <span className="cell-stack">
                        <span
                          className="ellipsis"
                          style={{ fontWeight: 600 }}
                          data-tip={v.name.length > 30 ? v.name : undefined}
                        >
                          {label(v)}
                        </span>
                        {v.anonymous && <Tag>anonymous</Tag>}
                        {v.project && <Tag>{v.project}</Tag>}
                      </span>
                    </td>
                    <td>
                      {v.size < 0 ? (
                        sized ? (
                          <span className="faint">–</span>
                        ) : (
                          <div className="skeleton" style={{ height: 10, width: "70%" }} />
                        )
                      ) : (
                        <span className="size-cell">
                          <span style={{ textAlign: "right" }}>{bytes(v.size)}</span>
                          <Bar
                            value={v.size / largest}
                            tone={v.containers.length ? undefined : "muted"}
                          />
                        </span>
                      )}
                    </td>
                    <td>
                      {v.containers.length > 0 ? (
                        <span className="ellipsis muted">{v.containers.join(", ")}</span>
                      ) : (
                        <span className="faint">unused</span>
                      )}
                    </td>
                    <td className="faint">{v.driver}</td>
                  </motion.tr>
                ))}
              </AnimatePresence>
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

// ---- networks ------------------------------------------------------------------------------------

export function NetworksSection() {
  const networks = useStore((s) => s.networks);
  const [query, setQuery] = useState("");
  const [marked, setMarked] = useState<Set<string>>(new Set());
  const search = useRef<HTMLInputElement>(null);
  useRefresh(loadNetworks, 10_000);
  const rows = useMemo(
    () =>
      (networks ?? []).filter(
        (n) =>
          !query ||
          contains(`${n.name} ${n.driver} ${n.subnets.join(" ")} ${n.containers.join(" ")}`, query),
      ),
    [networks, query],
  );
  const keyOf = (n: NetworkSummary) => n.id;
  const [chosen, choose] = useChosen(rows, keyOf, "networks");
  const targets = () =>
    marked.size > 0
      ? (networks ?? []).filter((n) => marked.has(n.id))
      : rows.filter((n) => n.id === chosen);

  useTableKeys(
    rows,
    keyOf,
    chosen,
    choose,
    marked,
    setMarked,
    (event, row) => {
      if (event.key === "d" || event.key === "Delete" || event.key === "Backspace") {
        askRemoveNetworks(targets());
        return true;
      }
      if (event.key === "y" && row) {
        void copyText(row.name, "the name");
        return true;
      }
      return false;
    },
    () => search.current?.focus(),
  );

  return (
    <div className="section">
      <Header title="Networks" sub={networks ? plural(networks.length, "network") : "reading…"}>
        <Button
          size="sm"
          variant="ghost"
          tip="Remove the networks no container is on"
          onClick={() => {
            void loadDisk();
            set({ dialog: { kind: "prune", preset: ["networks"] } });
          }}
        >
          <Sparkles size={13} /> Clean up
        </Button>
      </Header>
      <div className="toolbar">
        <SearchField
          ref={search}
          value={query}
          onChange={setQuery}
          placeholder="Filter networks"
          keys="/"
        />
        {marked.size > 0 && (
          <Button size="sm" variant="danger-ghost" onClick={() => askRemoveNetworks(targets())}>
            <Trash2 size={12} /> Remove {marked.size}
          </Button>
        )}
      </div>
      {networks === null ? (
        <Loading />
      ) : rows.length === 0 ? (
        <Empty icon={<Network size={20} />} title="Nothing matches" />
      ) : (
        <div className="table-scroll">
          <table className="table">
            <colgroup>
              <col style={{ width: 38 }} />
              <col />
              <col style={{ width: 84 }} />
              <col style={{ width: 150 }} />
              <col style={{ width: "34%" }} />
            </colgroup>
            <thead>
              <tr>
                <th />
                <th>Name</th>
                <th>Driver</th>
                <th>Subnet</th>
                <th>Running containers</th>
              </tr>
            </thead>
            <tbody>
              <AnimatePresence initial={false}>
                {rows.map((n) => (
                  <motion.tr
                    {...rowIn}
                    key={n.id}
                    data-row={n.id}
                    data-selected={n.id === chosen}
                    data-marked={marked.has(n.id)}
                    onPointerDown={(event) => {
                      if (event.button !== 0) return;
                      if (event.metaKey || event.ctrlKey) {
                        const next = new Set(marked);
                        if (next.has(n.id)) next.delete(n.id);
                        else next.add(n.id);
                        setMarked(next);
                      }
                      choose(n.id);
                    }}
                    onContextMenu={(event) => {
                      event.preventDefault();
                      choose(n.id);
                      openMenu({
                        x: event.clientX,
                        y: event.clientY,
                        entries: [
                          {
                            label: "Copy name",
                            shortcut: "y",
                            run: () => void copyText(n.name, "the name"),
                          },
                          ...(n.subnets[0]
                            ? [
                                {
                                  label: "Copy subnet",
                                  run: () => void copyText(n.subnets[0]!, "the subnet"),
                                },
                              ]
                            : []),
                          "separator" as const,
                          {
                            label: "Remove…",
                            icon: Trash2,
                            shortcut: "d",
                            tone: "danger" as const,
                            disabled: n.builtin || n.containers.length > 0,
                            hint: n.builtin
                              ? "Docker's own network"
                              : `Running containers are on it`,
                            run: () => askRemoveNetworks([n]),
                          },
                        ],
                      });
                    }}
                  >
                    <td>
                      {marked.size > 0 ? (
                        <Checkbox checked={marked.has(n.id)} />
                      ) : (
                        <Network size={13} className="faint" />
                      )}
                    </td>
                    <td>
                      <span className="cell-stack">
                        <span className="ellipsis" style={{ fontWeight: 600 }}>
                          {n.name}
                        </span>
                        {n.builtin && <Tag>built-in</Tag>}
                        {n.internal && <Tag tone="warning">internal</Tag>}
                        {n.project && <Tag>{n.project}</Tag>}
                      </span>
                    </td>
                    <td className="muted">{n.driver}</td>
                    <td className="muted selectable">{n.subnets.join(", ") || "–"}</td>
                    <td>
                      {n.containers.length > 0 ? (
                        <span className="cell-stack">
                          <Tag tone="success">{n.containers.length}</Tag>
                          <span className="ellipsis muted">{n.containers.join(", ")}</span>
                        </span>
                      ) : (
                        <span className="faint">none</span>
                      )}
                    </td>
                  </motion.tr>
                ))}
              </AnimatePresence>
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
