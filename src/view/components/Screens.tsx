/** The screens that stand in for the rest: before the program answers, and while Docker does not. */

import { motion } from "motion/react";
import { useEffect, useState } from "react";
import { PlugZap, RefreshCw } from "lucide-react";

import { pollNow } from "../state/actions";
import { useKeyLayer } from "../state/keys";
import { useStore } from "../state/store";
import { Button } from "./ui";

/** dockerpen's mark, which tools/icon.mjs also draws as its icon. */
function Mark({ className }: { className?: string }) {
  // Three containers, stacked: the second lifted, as if one were being picked out.
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" aria-hidden>
      <rect x="3" y="14" width="18" height="6" rx="2" fill="currentColor" opacity="0.35" />
      <rect x="5" y="7.5" width="14" height="5.5" rx="2" fill="currentColor" opacity="0.7" />
      <rect x="7" y="2" width="10" height="4.5" rx="1.8" fill="currentColor" />
    </svg>
  );
}

export function BootScreen() {
  return (
    <motion.div
      className="boot"
      initial={{ opacity: 1 }}
      exit={{ opacity: 0, transition: { duration: 0.25 } }}
    >
      <div className="boot-inner">
        <motion.div
          initial={{ scale: 0.8, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ type: "spring", duration: 0.6, bounce: 0.3 }}
          style={{ color: "var(--accent)" }}
        >
          <svg width="44" height="44" viewBox="0 0 24 24" fill="none" aria-hidden>
            {[
              { y: 14, x: 3, w: 18, h: 6, o: 0.35, d: 0 },
              { y: 7.5, x: 5, w: 14, h: 5.5, o: 0.7, d: 0.12 },
              { y: 2, x: 7, w: 10, h: 4.5, o: 1, d: 0.24 },
            ].map((r) => (
              <motion.rect
                key={r.y}
                x={r.x}
                y={r.y}
                width={r.w}
                height={r.h}
                rx="2"
                fill="currentColor"
                initial={{ opacity: 0, y: -6 }}
                animate={{ opacity: [0, r.o, r.o], y: 0 }}
                transition={{ delay: r.d, duration: 0.5, ease: [0.2, 0, 0, 1] }}
              />
            ))}
          </svg>
        </motion.div>
        <motion.span initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 0.3 }}>
          Asking Docker…
        </motion.span>
      </div>
    </motion.div>
  );
}

export function EngineDown() {
  const engine = useStore((s) => s.engine);
  const [left, setLeft] = useState(3);
  useEffect(() => {
    const timer = setInterval(() => setLeft((n) => (n <= 1 ? 3 : n - 1)), 1000);
    return () => clearInterval(timer);
  }, []);
  useKeyLayer((event) => {
    if (event.key === "Enter" || event.key === "r") {
      pollNow();
      return true;
    }
    return false;
  });
  if (!engine || engine.ok) return null;
  const mac = navigator.userAgent.includes("Mac");
  return (
    <motion.div
      className="engine-down"
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.35, ease: [0.2, 0, 0, 1] }}
    >
      <motion.div
        className="empty-icon"
        style={{ width: 56, height: 56, color: "var(--warn)" }}
        animate={{ scale: [1, 1.06, 1] }}
        transition={{ duration: 2, repeat: Infinity, ease: "easeInOut" }}
      >
        <PlugZap size={24} />
      </motion.div>
      <h2 style={{ margin: 0, fontSize: 15 }}>Docker is not answering</h2>
      <p className="muted" style={{ margin: 0 }}>
        dockerpen asked <code>{engine.endpoint}</code> and heard: {engine.error}
      </p>
      <p className="faint" style={{ margin: 0, fontSize: 11.5 }}>
        {mac
          ? "Start Docker Desktop, OrbStack or Colima where dockerpen runs, or point DOCKER_HOST at the engine."
          : "Start the Docker service where dockerpen runs (systemctl start docker), check that your user may use its socket, or set DOCKER_HOST."}
      </p>
      <Button onClick={() => pollNow()} keys="⏎">
        <RefreshCw size={13} /> Try again <span className="faint">· again in {left}s</span>
      </Button>
      <Mark className="brand-mark" />
    </motion.div>
  );
}
