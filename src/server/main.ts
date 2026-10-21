#!/usr/bin/env node
/**
 * dockerpen. In a terminal that shows pencere views, Docker opens in the pane; in
 * one that does not, it prints the containers; started by an MCP client over
 * stdio, it is an ordinary MCP server whose `show_docker` tool has the same view.
 *
 * The view hands the pane over when the person asks for a shell in a container
 * (or for its logs as they come): the program closes the view, runs the command
 * in the terminal, and shows the view again where it was when the command ends.
 */

import { bundleFromDirectory, serve, ViewControl } from "@pencere/sdk";
import type { Bundle, ToolCall } from "@pencere/sdk";
import { watch } from "node:fs";

import { Dockerpen } from "./app.js";
import type { HandoffRequest } from "./app.js";
import { containerTable, summaryLine } from "./format.js";
import { runInTerminal } from "./handoff.js";
import { VERSION, VIEW_DIRECTORY, createServer } from "./tools.js";
import type { Section } from "./types.js";

const SECTIONS: readonly Section[] = [
  "containers",
  "images",
  "volumes",
  "networks",
  "system",
  "activity",
];

const USAGE = `usage: dockerpen [container] [options]

Docker in the terminal pane: containers, logs, resource use, images, volumes,
networks and disk use, with the keyboard or the mouse.

  container            select a container (its name, compose service or id) on opening
  -s, --section <name> open on ${SECTIONS.join(", ")}
      --dev            show the view again when its files in dist/view change
  -h, --help           this text
  -v, --version        the version

In a terminal that does not show pencere views it prints the containers.
Started by an MCP client, it is an MCP server: give it \`dockerpen\` as the command.`;

interface Options {
  focus?: string;
  section?: Section;
  dev: boolean;
}

function parse(argv: readonly string[]): Options {
  const options: Options = { dev: false };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]!;
    if (arg === "-h" || arg === "--help") {
      console.log(USAGE);
      process.exit(0);
    } else if (arg === "-v" || arg === "--version") {
      console.log(VERSION);
      process.exit(0);
    } else if (arg === "--dev") {
      options.dev = true;
    } else if (arg === "-s" || arg === "--section" || arg.startsWith("--section=")) {
      const value = arg.includes("=") ? arg.slice(arg.indexOf("=") + 1) : argv[++i];
      if (!value || !(SECTIONS as readonly string[]).includes(value)) {
        console.error(`dockerpen: --section takes one of ${SECTIONS.join(", ")}`);
        process.exit(2);
      }
      options.section = value as Section;
    } else if (arg.startsWith("-")) {
      console.error(`dockerpen: unknown option ${arg}\n\n${USAGE}`);
      process.exit(2);
    } else {
      options.focus = arg;
    }
  }
  return options;
}

const options = parse(process.argv.slice(2));
const dockerpen = new Dockerpen();
const server = createServer(dockerpen);

/** Runs when there is no view to show: the containers, as text. */
async function fallback(): Promise<void> {
  const poll = await dockerpen.poll({ stats: false });
  if (!poll.engine.ok) {
    console.error(
      `dockerpen: Docker is not reachable at ${poll.engine.endpoint}: ${poll.engine.error}`,
    );
    process.exitCode = 1;
    return;
  }
  console.log(`${summaryLine(poll.containers)}\n`);
  console.log(containerTable(poll.containers, process.stdout.isTTY === true));
  console.log(
    "\n\x1b[2mThis terminal does not show pencere views, so this is the text. In one that\n" +
      "does (bateri), dockerpen opens as an interface in this pane.\x1b[0m",
  );
}

async function viewBundle(): Promise<Bundle | undefined> {
  try {
    return await bundleFromDirectory(VIEW_DIRECTORY);
  } catch {
    // Without the built files the host reads the one-document view from `resources/read`.
    return undefined;
  }
}

if (!process.stdin.isTTY) {
  // Started by an MCP client: an MCP server on stdio, whose tool shows the same view there.
  await serve(server, { tool: "show_docker" });
} else {
  let bundle = await viewBundle();
  let control: ViewControl | undefined;

  if (options.dev) {
    let timer: ReturnType<typeof setTimeout> | undefined;
    watch(VIEW_DIRECTORY, { recursive: true }, () => {
      clearTimeout(timer);
      timer = setTimeout(async () => {
        const next = await viewBundle();
        if (next === undefined || control === undefined) return;
        bundle = next;
        await control.reopen({ bundle: next });
      }, 300);
    }).unref();
  }

  let tool: ToolCall = {
    name: "show_docker",
    arguments: {
      ...(options.section ? { section: options.section } : {}),
      ...(options.focus ? { focus: options.focus } : {}),
    },
  };

  for (;;) {
    const current = new ViewControl();
    control = current;
    let pending: HandoffRequest | undefined;
    dockerpen.desk = {
      request(request) {
        if (pending !== undefined) return "busy";
        pending = request;
        // The answer to the view's call goes out first, so that it can show what comes.
        setTimeout(() => {
          void current.close().then((closed) => {
            if (closed.kind === "closed") return;
            pending = undefined;
            dockerpen.handoffFailed =
              closed.kind === "unsupported"
                ? "This terminal cannot hand its pane to a command and back."
                : "The view could not be closed just now.";
          });
        }, 120);
        return "scheduled";
      },
    };
    const result = await serve(server, {
      tool,
      ...(bundle ? { bundle } : {}),
      control: current,
      fallback,
    });
    dockerpen.desk = undefined;
    control = undefined;
    // What the view was doing is the program's to keep: the next one opens where it was.
    tool = { name: "show_docker", arguments: {} };
    if (result.kind === "closed" && result.by === "program" && pending !== undefined) {
      dockerpen.returned = await runInTerminal(pending);
      continue;
    }
    break;
  }
  dockerpen.events.stop();
}
