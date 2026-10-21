import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";
import { viteSingleFile } from "vite-plugin-singlefile";

import { harness } from "./harness/plugin.ts";

// The view is built twice, into two directories: `vite build` writes many files, which a
// pencere terminal keeps by content, and `vite build --mode single` writes one document,
// which every other MCP Apps host reads. `vite --mode harness` serves it in a stand-in
// host in the browser, with the real server behind it.
export default defineConfig(({ mode }) => {
  const single = mode === "single";
  return {
    // Relative, so that the view's files are found wherever its document is served from.
    base: "./",
    plugins: [
      react(),
      ...(single ? [viteSingleFile()] : []),
      ...(mode === "harness" ? [harness()] : []),
    ],
    build: { outDir: single ? "dist/single" : "dist/view", emptyOutDir: true },
    server: { port: 5199, strictPort: true },
  };
});
