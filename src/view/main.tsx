import { StrictMode } from "react";
import { createRoot } from "react-dom/client";

import { App } from "./App";
import "./styles.css";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);

if (import.meta.env.DEV) {
  // For the harness and the browser's console: the store, to look at while working on the view.
  Object.assign(window, { dockerpen: await import("./state/store") });
}
