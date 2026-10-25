// Draws the page's icons as SVG files from Lucide (https://lucide.dev, ISC), whose drawings the
// first dockerpen used: `node tools/icons.mjs <the lucide-react package>` writes
// src/assets/icons/<name>.svg and the licence that goes with them. The files are what ships; this is
// only how they were made (nothing here runs in the product, and the product needs no npm).
//
// Each drawing is a stroke of 2 on a 24 grid, in black: the page draws it with `tint`, which makes
// every pixel the colour it names and keeps the drawing's own opacity.

import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const NAMES = [
  "activity", "arrow-down", "arrow-down-wide-narrow", "arrow-right-left", "arrow-up", "box", "boxes",
  "check", "chevron-down", "chevron-right", "circle-alert", "circle-check", "circle-play",
  "circle-stop", "copy", "cpu", "download", "eraser", "external-link", "eye", "eye-off",
  "folder-tree", "hard-drive", "heart-pulse", "info", "keyboard", "layers", "list-filter",
  "loader", "memory-stick", "network", "pause", "play", "plug-zap", "plus", "refresh-cw",
  "rotate-cw", "scroll-text", "search", "search-x", "skull", "sparkles", "square",
  "square-terminal", "trash-2", "triangle-alert", "x", "zap", "ellipsis",
];

const root = process.argv[2];
if (!root) {
  console.error("usage: node tools/icons.mjs <path of the lucide-react package>");
  process.exit(2);
}
const out = new URL("../src/assets/icons/", import.meta.url).pathname;
mkdirSync(out, { recursive: true });

function nodeOf(text) {
  const at = text.indexOf("node:");
  const start = text.indexOf("[", at);
  let depth = 0;
  for (let i = start; i < text.length; i++) {
    if (text[i] === "[") depth++;
    if (text[i] === "]" && --depth === 0) return new Function(`return ${text.slice(start, i + 1)}`)();
  }
  throw new Error("no icon node");
}

for (const name of NAMES) {
  const file = join(root, "dist/esm/icons", `${name}.mjs`);
  let text = readFileSync(file, "utf8");
  // An alias is a file that says where the drawing is.
  const alias = /from '\.\/([a-z0-9-]+)\.mjs'/.exec(text);
  if (alias && !text.includes("node:")) text = readFileSync(join(root, "dist/esm/icons", `${alias[1]}.mjs`), "utf8");
  const parts = nodeOf(text).map(([tag, attrs]) => {
    const list = Object.entries(attrs)
      .filter(([key]) => key !== "key")
      .map(([key, value]) => `${key}="${value}"`)
      .join(" ");
    return `<${tag} ${list}/>`;
  });
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${parts.join("")}</svg>\n`;
  writeFileSync(join(out, `${name}.svg`), svg);
}
copyFileSync(join(root, "LICENSE"), join(out, "LICENSE"));
console.log(`${NAMES.length} icons`);
