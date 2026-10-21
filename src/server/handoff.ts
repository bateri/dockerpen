/**
 * The pane, handed to a command and back: a shell in a container, or its logs as
 * they come. The view has closed by then and the terminal is the program's again,
 * on the primary screen with its own modes, so the command gets a terminal as if
 * it had been started from the shell.
 */

import { spawn } from "node:child_process";

import type { HandoffRequest } from "./app.js";
import type { Handoff } from "./types.js";

const BAR = (text: string) => `\x1b[7m dockerpen \x1b[0m ${text}\x1b[0m`;
const DIM = (text: string) => `\x1b[2m${text}\x1b[0m`;

/** Picks bash where the image has it and sh where it does not, inside the container. */
const SHELL = "if command -v bash >/dev/null 2>&1; then exec bash -l; else exec sh -l; fi";

export async function runInTerminal(request: HandoffRequest): Promise<Handoff> {
  const out = process.stdout;
  const args =
    request.kind === "shell"
      ? [
          "exec",
          "-it",
          "-e",
          `TERM=${process.env.TERM ?? "xterm-256color"}`,
          request.id,
          "sh",
          "-c",
          SHELL,
        ]
      : ["logs", "--follow", "--tail", "200", request.id];
  out.write(
    request.kind === "shell"
      ? `${BAR(`shell in \x1b[1m${request.name}\x1b[0m`)}  ${DIM("exit or ⌃D comes back")}\n`
      : `${BAR(`logs of \x1b[1m${request.name}\x1b[0m, as they come`)}  ${DIM("⌃C comes back")}\n`,
  );

  // ⌃C reaches this process with the command, since both are the terminal's foreground: it
  // is the command's to act on (it ends `docker logs`), not a reason for dockerpen to end.
  const ignore = () => {};
  process.on("SIGINT", ignore);
  const started = Date.now();
  try {
    const exitCode = await new Promise<number | null>((resolve, reject) => {
      const child = spawn("docker", args, { stdio: "inherit" });
      child.on("error", reject);
      child.on("close", (code, signal) => resolve(code ?? (signal === "SIGINT" ? 130 : null)));
    });
    out.write(DIM(`\n↩ back to dockerpen\n`));
    return {
      kind: request.kind,
      id: request.id,
      name: request.name,
      exitCode,
      duration: Date.now() - started,
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    out.write(`${BAR(`could not run docker: ${message}`)}\n`);
    await new Promise((resolve) => setTimeout(resolve, 1500));
    return {
      kind: request.kind,
      id: request.id,
      name: request.name,
      exitCode: null,
      duration: Date.now() - started,
      error: message,
    };
  } finally {
    process.removeListener("SIGINT", ignore);
  }
}
