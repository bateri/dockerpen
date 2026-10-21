/**
 * dockerpen's view. It is an MCP App: it talks to its program through whatever
 * host shows it, with the messages MCP Apps defines. In a pencere terminal it is
 * the whole pane and every key but ⌃C and the terminal's own is its.
 */

import { AnimatePresence, MotionConfig, motion } from "motion/react";
import { useEffect, useState } from "react";

import type { Boot, DockerEvent, PollResult } from "../server/types";
import { ActivitySection, SystemSection } from "./components/System";
import { ContainersSection } from "./components/Containers";
import { HelpLayer } from "./components/Help";
import { DialogLayer, HandoffLayer, MenuLayer, Toasts } from "./components/overlays";
import { PaletteLayer } from "./components/Palette";
import { ImagesSection, NetworksSection, VolumesSection } from "./components/Resources";
import { Rail } from "./components/Rail";
import { BootScreen, EngineDown } from "./components/Screens";
import { StatusBar } from "./components/StatusBar";
import { Tooltips } from "./components/ui";
import { attach, call } from "./lib/bridge";
import { Host } from "./lib/host";
import { announceReturn, recentlyActedOn, startPolling } from "./state/actions";
import { openDetail } from "./state/commands";
import { onKeyDown } from "./state/keys";
import { applyBoot, get, onEvents, set, toast, useStore } from "./state/store";

const VERSION = "0.1.0";

type Shown = { boot: Boot & { handoff?: boolean }; poll: PollResult & { handoff?: boolean } };

function booted(result: { structuredContent?: unknown }): void {
  const shown = result.structuredContent as Shown | undefined;
  if (!shown?.boot || !shown.poll) return;
  if (get().status === "ready") return;
  applyBoot(shown.boot, { ...shown.poll, handoff: shown.boot.handoff });
  // The keys are the view's from the first moment, without a click into it first.
  window.focus();
  startPolling();
  announceReturn();
}

/** What happens in the engine that the person should hear of while looking elsewhere. */
function news(events: DockerEvent[]): void {
  for (const event of events) {
    if (event.type !== "container" || recentlyActedOn(event.id)) continue;
    const name = event.name ?? event.id.slice(0, 12);
    const open = { label: "Logs", run: () => openDetail(event.id, "logs") };
    if (event.action === "oom") {
      toast("danger", `${name} ran out of memory`, { action: open });
    } else if (event.action === "die" && event.detail.exitCode && event.detail.exitCode !== "0") {
      toast("warning", `${name} exited with code ${event.detail.exitCode}`, { action: open });
    } else if (event.action.includes("health_status: unhealthy")) {
      toast("danger", `${name} is unhealthy`, { action: open });
    }
  }
}

let connection: Promise<Host> | undefined;

/** The one connection to the host, made once: StrictMode mounts twice in development. */
function connect(): Promise<Host> {
  connection ??= (async () => {
    const host = new Host({
      toolResult: (result) => booted(result),
      teardown: async () => {
        set({ leaving: true });
        await new Promise((resolve) => setTimeout(resolve, 140));
      },
    });
    await host.connect({ name: "dockerpen", version: VERSION });
    return host;
  })();
  return connection;
}

export function App() {
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    let timer: ReturnType<typeof setTimeout> | undefined;
    connect().then(
      (host) => {
        attach(host);
        // A host that does not call the view's tool by itself: the view asks for what it shows.
        timer = setTimeout(() => {
          if (get().status === "ready") return;
          void call<Shown>("show_docker", {}).then(
            (shown) => booted({ structuredContent: shown }),
            () => {},
          );
        }, 2500);
      },
      (failure: unknown) =>
        setError(failure instanceof Error ? failure : new Error(String(failure))),
    );
    return () => clearTimeout(timer);
  }, []);

  useEffect(() => {
    onEvents(news);
    const keydown = (event: KeyboardEvent) => onKeyDown(event);
    window.addEventListener("keydown", keydown);
    // The page's own menu has nothing for a person here; the rows have theirs.
    const context = (event: MouseEvent) => {
      if (!(event.target as HTMLElement).closest("input, textarea, .selectable"))
        event.preventDefault();
    };
    window.addEventListener("contextmenu", context);
    return () => {
      window.removeEventListener("keydown", keydown);
      window.removeEventListener("contextmenu", context);
    };
  }, []);

  const status = useStore((s) => s.status);
  const section = useStore((s) => s.ui.section);
  const engine = useStore((s) => s.engine);
  const focus = useStore((s) => s.focus);
  const handingOff = useStore((s) => s.handingOff);
  const overlay = useStore((s) => s.menu !== null || s.dialog !== null || s.palette || s.help);
  const leaving = useStore((s) => s.leaving);
  const compact = useCompact();

  return (
    <MotionConfig reducedMotion="user">
      <motion.div
        className="app"
        data-rail={compact ? "compact" : "full"}
        data-focus={focus}
        data-overlay={overlay}
        data-handing-off={handingOff !== null}
        animate={{ opacity: leaving ? 0 : 1 }}
        transition={{ duration: 0.14 }}
      >
        <Rail />
        <main className="main">
          {status === "ready" && engine && !engine.ok ? (
            <EngineDown />
          ) : (
            <AnimatePresence mode="wait" initial={false}>
              <motion.div
                key={section}
                className="section"
                initial={{ opacity: 0, y: 6 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -4, transition: { duration: 0.09 } }}
                transition={{ duration: 0.2, ease: [0.2, 0, 0, 1] }}
              >
                {status === "ready" && <Section section={section} />}
              </motion.div>
            </AnimatePresence>
          )}
        </main>
        <StatusBar />
      </motion.div>
      <AnimatePresence>{status === "connecting" && <BootScreen key="boot" />}</AnimatePresence>
      {error && status === "connecting" && (
        <div className="boot" style={{ zIndex: 101 }}>
          <div className="boot-inner">
            <b>The host did not answer</b>
            <span className="faint">{error.message}</span>
          </div>
        </div>
      )}
      <MenuLayer />
      <DialogLayer />
      <PaletteLayer />
      <HelpLayer />
      <HandoffLayer />
      <Toasts />
      <Tooltips />
    </MotionConfig>
  );
}

function Section({ section }: { section: string }) {
  switch (section) {
    case "images":
      return <ImagesSection />;
    case "volumes":
      return <VolumesSection />;
    case "networks":
      return <NetworksSection />;
    case "system":
      return <SystemSection />;
    case "activity":
      return <ActivitySection />;
    default:
      return <ContainersSection />;
  }
}

/** The rail folds to its icons when the pane is narrow. */
function useCompact(): boolean {
  const [compact, setCompact] = useState(() => window.innerWidth < 780);
  useEffect(() => {
    const resize = () => setCompact(window.innerWidth < 780);
    window.addEventListener("resize", resize);
    return () => window.removeEventListener("resize", resize);
  }, []);
  return compact;
}
