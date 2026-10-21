/** Every key, in one place. */

import { AnimatePresence } from "motion/react";
import { X } from "lucide-react";

import { set, useStore } from "../state/store";
import { Scrim } from "./overlays";
import { Button, Kbd } from "./ui";

const SHORTCUTS: [string, [string, string[]][]][] = [
  [
    "Anywhere",
    [
      ["Command palette", [":", "⌃K"]],
      ["Go to a section", ["1", "–", "6"]],
      ["Search", ["/"]],
      ["Refresh", ["R"]],
      ["Keyboard shortcuts", ["?"]],
      ["Close, go back", ["esc"]],
      ["Quit dockerpen", ["⌃C"]],
    ],
  ],
  [
    "Lists",
    [
      ["Move", ["↑", "↓"]],
      ["Move", ["j", "k"]],
      ["First, last", ["g", "G"]],
      ["Mark, for many at once", ["space"]],
      ["Mark all, none", ["a", "A"]],
      ["Open, expand", ["⏎", "→"]],
      ["Close, collapse", ["←"]],
      ["Context menu", ["."]],
    ],
  ],
  [
    "Containers",
    [
      ["Start or stop", ["s"]],
      ["Restart", ["r"]],
      ["Pause or resume", ["p"]],
      ["Shell in the terminal", ["e"]],
      ["Logs", ["l"]],
      ["Follow logs in the terminal", ["F"]],
      ["Inspect", ["i"]],
      ["Open the published port", ["o"]],
      ["Copy the id", ["y"]],
      ["Kill", ["K"]],
      ["Remove", ["d"]],
      ["Next filter", ["f"]],
      ["Group by compose project", ["P"]],
    ],
  ],
  [
    "The detail panel",
    [
      ["Between list and panel", ["tab"]],
      ["Previous, next tab", ["[", "]"]],
      ["Logs: follow", ["space"]],
      ["Logs: timestamps, wrap", ["t", "w"]],
      ["Logs: next, previous match", ["n", "N"]],
      ["Wider, narrower", ["<", ">"]],
    ],
  ],
];

export function HelpLayer() {
  const open = useStore((s) => s.help);
  return (
    <AnimatePresence>
      {open && (
        <Scrim key="help" onClose={() => set({ help: false })}>
          <div
            className="dialog"
            data-wide="true"
            role="dialog"
            aria-modal
            aria-label="Keyboard shortcuts"
          >
            <div style={{ display: "flex", alignItems: "center" }}>
              <h2 style={{ flex: 1 }}>Keyboard shortcuts</h2>
              <Button
                variant="ghost"
                icon
                size="sm"
                tip="Close"
                keys="esc"
                onClick={() => set({ help: false })}
              >
                <X size={14} />
              </Button>
            </div>
            <p>
              Everything the mouse does, the keys do too. A key acts on the marked containers, or on
              the chosen one.
            </p>
            <div className="help-grid">
              {SHORTCUTS.map(([section, rows]) => (
                <div key={section} style={{ display: "contents" }}>
                  <div className="help-section">{section}</div>
                  {rows.map(([label, keys], index) => (
                    <div key={`${label}${index}`} className="help-row">
                      <span>{label}</span>
                      <span className="help-keys">
                        {keys.map((key, i) =>
                          key === "–" ? (
                            <span key={i} className="faint">
                              –
                            </span>
                          ) : (
                            <Kbd key={i}>{key}</Kbd>
                          ),
                        )}
                      </span>
                    </div>
                  ))}
                </div>
              ))}
            </div>
          </div>
        </Scrim>
      )}
    </AnimatePresence>
  );
}
