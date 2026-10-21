/** The command palette: every command, container, image, volume and network, by name. */

import { AnimatePresence, motion } from "motion/react";
import { useEffect, useMemo, useRef, useState } from "react";
import { Boxes, HardDrive, Layers, Network, Search } from "lucide-react";
import type { LucideIcon } from "lucide-react";

import { containerCommands, globalCommands, openDetail, selection } from "../state/commands";
import { fuzzy } from "../lib/fuzzy";
import { imageName, shortId } from "../lib/format";
import { get, go, pick, set, setUi, useStore } from "../state/store";
import { Scrim } from "./overlays";
import { Kbd } from "./ui";

interface Entry {
  key: string;
  title: string;
  group: string;
  icon: LucideIcon;
  keys?: string;
  detail?: string;
  tone?: "danger";
  run: () => void;
}

export function PaletteLayer() {
  const open = useStore((s) => s.palette);
  return <AnimatePresence>{open && <Palette key="palette" />}</AnimatePresence>;
}

function entries(): Entry[] {
  const state = get();
  const selected = selection();
  const out: Entry[] = [];
  for (const c of containerCommands(selected)) out.push({ ...c, key: `cmd:${c.id}` });
  for (const c of globalCommands()) out.push({ ...c, key: `cmd:${c.id}` });
  for (const container of state.containers) {
    out.push({
      key: `container:${container.id}`,
      title: container.name,
      group: "Containers",
      icon: Boxes,
      detail: `${container.state} · ${imageName(container.image)}`,
      run: () => {
        setUi({ section: "containers", selected: `c:${container.id}` });
        openDetail(container.id);
      },
    });
  }
  for (const image of state.images ?? []) {
    const name = image.tags[0] ? imageName(image.tags[0]) : shortId(image.id);
    out.push({
      key: `image:${image.id}`,
      title: name,
      group: "Images",
      icon: Layers,
      detail: image.containers.length ? `used by ${image.containers.length}` : "unused",
      run: () => {
        go("images");
        pick("images", image.id);
      },
    });
  }
  for (const volume of state.volumes ?? []) {
    out.push({
      key: `volume:${volume.name}`,
      title: volume.anonymous ? shortId(volume.name) : volume.name,
      group: "Volumes",
      icon: HardDrive,
      detail: volume.containers.length ? `used by ${volume.containers.join(", ")}` : "unused",
      run: () => {
        go("volumes");
        pick("volumes", volume.name);
      },
    });
  }
  for (const network of state.networks ?? []) {
    out.push({
      key: `network:${network.id}`,
      title: network.name,
      group: "Networks",
      icon: Network,
      detail: network.driver,
      run: () => {
        go("networks");
        pick("networks", network.id);
      },
    });
  }
  return out;
}

function Palette() {
  const [query, setQuery] = useState("");
  const [active, setActive] = useState(0);
  const input = useRef<HTMLInputElement>(null);
  const list = useRef<HTMLDivElement>(null);
  const all = useMemo(entries, []);

  const shown = useMemo(() => {
    if (!query.trim()) {
      // With nothing typed: what can be done to the chosen container, then the rest of the commands.
      return all
        .filter((e) => e.key.startsWith("cmd:"))
        .map((e) => ({ entry: e, positions: [] as number[] }));
    }
    const matched = all
      .map((entry) => ({ entry, match: fuzzy(query, entry.title) }))
      .filter(
        (m): m is { entry: Entry; match: NonNullable<ReturnType<typeof fuzzy>> } =>
          m.match !== undefined,
      )
      .sort((a, b) => b.match.score - a.match.score)
      .slice(0, 60);
    // Each group once, the group with the best match first.
    const groups = [...new Set(matched.map((m) => m.entry.group))];
    return groups.flatMap((group) =>
      matched
        .filter((m) => m.entry.group === group)
        .map((m) => ({ entry: m.entry, positions: m.match.positions })),
    );
  }, [all, query]);

  useEffect(() => setActive(0), [query]);
  useEffect(() => input.current?.focus(), []);
  useEffect(() => {
    list.current?.querySelector(`[data-index="${active}"]`)?.scrollIntoView({ block: "nearest" });
  }, [active]);

  const close = () => set({ palette: false });
  const run = (index: number) => {
    const item = shown[index];
    if (!item) return;
    close();
    item.entry.run();
  };

  let lastGroup = "";
  return (
    <Scrim onClose={close}>
      <div
        className="palette"
        role="dialog"
        aria-modal
        aria-label="Commands"
        onKeyDown={(event) => {
          if (event.key === "ArrowDown" || (event.ctrlKey && event.key === "n")) {
            setActive((a) => Math.min(shown.length - 1, a + 1));
          } else if (event.key === "ArrowUp" || (event.ctrlKey && event.key === "p")) {
            setActive((a) => Math.max(0, a - 1));
          } else if (event.key === "Enter") {
            run(active);
          } else if (event.key === "Escape") {
            close();
          } else if (event.key === "Tab") {
            // Tab stays here: the palette is a list, not a form.
          } else return;
          event.preventDefault();
          event.stopPropagation();
        }}
      >
        <div className="palette-input">
          <Search size={16} />
          <input
            ref={input}
            value={query}
            spellCheck={false}
            placeholder="Type a command, a container, an image…"
            onChange={(event) => setQuery(event.target.value)}
            aria-controls="palette-list"
            aria-activedescendant={`palette-${active}`}
          />
          <Kbd>esc</Kbd>
        </div>
        <div className="palette-list" ref={list} id="palette-list" role="listbox">
          {shown.length === 0 && (
            <div className="empty" style={{ padding: 30 }}>
              <p>Nothing is called that.</p>
            </div>
          )}
          {shown.map(({ entry, positions }, index) => {
            const header = entry.group !== lastGroup ? entry.group : null;
            lastGroup = entry.group;
            return (
              <div key={entry.key}>
                {header && <div className="palette-group">{header}</div>}
                <button
                  type="button"
                  id={`palette-${index}`}
                  data-index={index}
                  role="option"
                  aria-selected={index === active}
                  className="palette-item"
                  data-tone={entry.tone}
                  onPointerMove={() => setActive(index)}
                  onClick={() => run(index)}
                >
                  {index === active && (
                    <motion.span
                      layoutId="palette-highlight"
                      className="palette-highlight"
                      transition={{ type: "spring", duration: 0.22, bounce: 0 }}
                    />
                  )}
                  <entry.icon size={15} />
                  <span className="label">{highlight(entry.title, positions)}</span>
                  {entry.detail && <span className="detail-text">{entry.detail}</span>}
                  {entry.keys && <Kbd>{entry.keys}</Kbd>}
                </button>
              </div>
            );
          })}
        </div>
        <div className="palette-foot">
          <span>
            <Kbd>↑</Kbd>
            <Kbd>↓</Kbd> choose
          </span>
          <span>
            <Kbd>⏎</Kbd> run
          </span>
          <span>
            <Kbd>esc</Kbd> close
          </span>
        </div>
      </div>
    </Scrim>
  );
}

function highlight(text: string, positions: number[]) {
  if (positions.length === 0) return text;
  const marked = new Set(positions);
  const parts: React.ReactNode[] = [];
  let run = "";
  let bold = false;
  [...text].forEach((char, i) => {
    const is = marked.has(i);
    if (is !== bold && run) {
      parts.push(bold ? <b key={i}>{run}</b> : run);
      run = "";
    }
    bold = is;
    run += char;
  });
  if (run) parts.push(bold ? <b key="end">{run}</b> : run);
  return parts;
}
