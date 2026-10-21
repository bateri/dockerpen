/**
 * The keyboard: one listener for the page. What is over the page (a menu, a dialog,
 * the palette) takes its keys first; then the keys of the whole view; then the layers
 * of what is on screen — the logs over the detail panel over the list — each while it
 * is active, the last one shown first.
 *
 * ⌃C is never taken: it is the program's, and the terminal sends it there whatever
 * the view does. Keys with ⌘ may be the terminal's own and never arrive, so every
 * command has a key without one.
 */

import { useEffect, useRef } from "react";

import { SECTIONS, globalCommands } from "./commands";
import { closeOverlays, get, go, set } from "./store";

export type KeyHandler = (event: KeyboardEvent) => boolean;

interface Layer {
  handle: KeyHandler;
  active: () => boolean;
  search?: () => void;
  priority: number;
}

const layers: Layer[] = [];

/**
 * Registers the keys of a part of the screen for as long as it is shown; `active` says
 * whether it should hear them now, and `search` is where `/` puts the cursor. A layer of a
 * higher `priority` hears a key first — the logs before the panel they are in, the panel
 * before the list beside it — and what it does not take goes on to the next.
 */
export function useKeyLayer(
  handle: KeyHandler,
  options: { active?: () => boolean; search?: () => void; priority?: number } = {},
): void {
  const ref = useRef({ handle, options });
  ref.current = { handle, options };
  useEffect(() => {
    const layer: Layer = {
      handle: (event) => ref.current.handle(event),
      active: () => ref.current.options.active?.() ?? true,
      search: () => ref.current.options.search?.(),
      priority: options.priority ?? 0,
    };
    layers.push(layer);
    return () => {
      const at = layers.indexOf(layer);
      if (at >= 0) layers.splice(at, 1);
    };
  }, []);
}

function typing(target: EventTarget | null): boolean {
  return (
    target instanceof HTMLInputElement ||
    target instanceof HTMLTextAreaElement ||
    (target instanceof HTMLElement && target.isContentEditable)
  );
}

export function onKeyDown(event: KeyboardEvent): void {
  if (event.defaultPrevented) return;
  const state = get();
  // ⌃C is the program's; nothing here may stand in its way.
  if (event.ctrlKey && event.key.toLowerCase() === "c") return;

  if (state.handingOff) {
    event.preventDefault();
    return;
  }

  const mod = event.metaKey || event.ctrlKey;
  if (
    mod &&
    (event.key.toLowerCase() === "k" || (event.shiftKey && event.key.toLowerCase() === "p"))
  ) {
    event.preventDefault();
    set({ palette: !state.palette, menu: null, help: false });
    return;
  }

  if (state.menu || state.dialog || state.palette) return;

  if (state.help) {
    if (event.key === "Escape" || event.key === "?" || event.key === "q") {
      event.preventDefault();
      set({ help: false });
    }
    return;
  }

  if (typing(event.target)) return;
  if (event.metaKey || event.altKey) return;

  // Highest priority first; among equals, the one shown last.
  const active = layers
    .map((layer, order) => ({ layer, order }))
    .filter(({ layer }) => layer.active())
    .sort((a, b) => b.layer.priority - a.layer.priority || b.order - a.order)
    .map(({ layer }) => layer);

  if (!event.ctrlKey) {
    if (event.key === ":") {
      event.preventDefault();
      set({ palette: true });
      return;
    }
    if (event.key === "?") {
      event.preventDefault();
      set({ help: true });
      return;
    }
    if (event.key === "/") {
      const layer = active.find((l) => l.search !== undefined);
      if (layer) {
        event.preventDefault();
        layer.search!();
        return;
      }
    }
    if (event.key === "R") {
      event.preventDefault();
      globalCommands()
        .find((c) => c.id === "refresh")
        ?.run();
      return;
    }
    const section = SECTIONS.find((s) => s.key === event.key);
    if (section) {
      event.preventDefault();
      go(section.id);
      return;
    }
  }

  for (const layer of active) {
    if (layer.handle(event)) {
      event.preventDefault();
      return;
    }
  }
  if (event.key === "Escape" && closeOverlays()) event.preventDefault();
}

/** Moves within a list of `count` rows by the key, if it is a moving key; the new index or undefined. */
export function moveBy(
  event: KeyboardEvent,
  index: number,
  count: number,
  page = 10,
): number | undefined {
  if (count === 0) return undefined;
  switch (event.key) {
    case "ArrowDown":
    case "j":
      return Math.min(count - 1, index + 1);
    case "ArrowUp":
    case "k":
      return Math.max(0, index < 0 ? 0 : index - 1);
    case "Home":
    case "g":
      return 0;
    case "End":
    case "G":
      return count - 1;
    case "PageDown":
      return Math.min(count - 1, index + page);
    case "PageUp":
      return Math.max(0, index - page);
    default:
      return undefined;
  }
}
