/**
 * The MCP server: one tool with the view, a few a model may call to look, and the
 * tools only the view calls (`visibility: ["app"]`). Whatever changes or removes
 * something is the view's: a model can read the containers and their logs, and a
 * person decides what happens to them.
 *
 * Nothing in this file knows about pencere. Started by an MCP Apps host over stdio,
 * the same server shows the same view there.
 */

import {
  RESOURCE_MIME_TYPE,
  registerAppResource,
  registerAppTool,
} from "@modelcontextprotocol/ext-apps/server";
import { McpServer } from "@modelcontextprotocol/server";
import { readFile } from "node:fs/promises";
import { z } from "zod";

import type { Dockerpen } from "./app.js";
import { containerTable, diskText, summaryLine } from "./format.js";
import {
  imageHistory,
  listImages,
  listNetworks,
  listVolumes,
  removeImage,
  removeNetwork,
  removeVolume,
} from "./resources.js";
import { readLogs } from "./containers.js";

export const VIEW_URI = "ui://dockerpen/view";

/** The view as the files `vite build` writes, for a terminal that keeps them by content. */
export const VIEW_DIRECTORY = new URL("../view/", import.meta.url);

/** The view as one document, for every other MCP Apps host. */
const VIEW_DOCUMENT = new URL("../single/index.html", import.meta.url);

export const VERSION = "0.1.0";

const SECTIONS = ["containers", "images", "volumes", "networks", "system", "activity"] as const;

const uiState = z
  .object({
    section: z.enum(SECTIONS).optional(),
    selected: z.string().optional(),
    detail: z.string().nullable().optional(),
    tab: z.enum(["overview", "logs", "env", "processes", "inspect"]).optional(),
    filter: z.enum(["all", "running", "stopped", "issues"]).optional(),
    query: z.string().optional(),
    groupByProject: z.boolean().optional(),
    sort: z.enum(["name", "state", "cpu", "memory", "created"]).optional(),
    collapsed: z.array(z.string()).optional(),
    panelWidth: z.number().optional(),
    logs: z
      .object({
        timestamps: z.boolean().optional(),
        wrap: z.boolean().optional(),
        follow: z.boolean().optional(),
      })
      .optional(),
  })
  .passthrough();

const app = { _meta: { ui: { visibility: ["app" as const] } } };

function text(value: string) {
  return { content: [{ type: "text" as const, text: value }] };
}

function data<T>(value: T, summary: string) {
  return { ...text(summary), structuredContent: value as Record<string, unknown> };
}

function failure(error: unknown) {
  return {
    isError: true,
    ...text(error instanceof Error ? error.message : String(error)),
  };
}

/** Runs a handler and turns what it throws into a tool error the view can show. */
function guarded<A, R>(handler: (args: A) => Promise<R>) {
  return async (args: A) => {
    try {
      return await handler(args);
    } catch (error) {
      return failure(error);
    }
  };
}

export function createServer(dockerpen: Dockerpen): McpServer {
  const server = new McpServer({ name: "dockerpen", version: VERSION });

  // ---- the view's tool -----------------------------------------------------------------

  registerAppTool(
    server,
    "show_docker",
    {
      // What a terminal writes above the view, in place of `show_docker`.
      title: "Docker",
      description:
        "Show Docker: containers with their logs and resource use, images, volumes, networks and disk use",
      inputSchema: z.object({
        section: z.enum(SECTIONS).optional().describe("The part to open on"),
        focus: z.string().optional().describe("A container to select, by name or id"),
      }),
      _meta: { ui: { resourceUri: VIEW_URI } },
    },
    guarded(async (args: { section?: (typeof SECTIONS)[number]; focus?: string }) => {
      if (args.section) dockerpen.ui = { ...dockerpen.ui, section: args.section };
      const poll = await dockerpen.poll({ history: true, events: -1 });
      if (args.focus) {
        // By its name, its compose service, or the start of its id; a running one first.
        const focus = args.focus;
        const candidates = poll.containers.filter(
          (c) => c.name === focus || c.service === focus || c.id.startsWith(focus),
        );
        const found = candidates.find((c) => c.state === "running") ?? candidates[0];
        if (found) dockerpen.ui = { ...dockerpen.ui, selected: found.id, detail: found.id };
      }
      const boot = { ...dockerpen.boot(), handoff: dockerpen.canHandOff(poll.engine) };
      const summary = poll.engine.ok
        ? `${summaryLine(poll.containers)}\n\n${containerTable(poll.containers)}`
        : `Docker is not reachable at ${poll.engine.endpoint}: ${poll.engine.error}`;
      return data({ boot, poll }, summary);
    }),
  );

  registerAppTool(
    server,
    "dockerpen_poll",
    {
      description: "The view's refresh: containers, their resource use, events, logs and jobs",
      inputSchema: z.object({
        stats: z.boolean().optional(),
        history: z.boolean().optional(),
        events: z.number().optional(),
        logs: z
          .object({
            id: z.string(),
            since: z.string().nullable().optional(),
            tail: z.number().optional(),
          })
          .optional(),
        ui: uiState.optional(),
      }),
      ...app,
    },
    guarded(async (args: Parameters<Dockerpen["poll"]>[0]) => {
      const poll = await dockerpen.poll(args);
      return data(
        { ...poll, handoff: dockerpen.canHandOff(poll.engine) },
        summaryLine(poll.containers),
      );
    }),
  );

  // ---- containers ----------------------------------------------------------------------

  registerAppTool(
    server,
    "container_detail",
    {
      description:
        "Everything about one container: its configuration, state, health, mounts and networks",
      inputSchema: z.object({ id: z.string() }),
      ...app,
    },
    guarded(async ({ id }: { id: string }) => {
      const detail = await dockerpen.detail(id);
      return data(detail, `${detail.name}: ${detail.state.status}`);
    }),
  );

  registerAppTool(
    server,
    "container_processes",
    {
      description: "The processes running in a container",
      inputSchema: z.object({ id: z.string() }),
      ...app,
    },
    guarded(async ({ id }: { id: string }) => {
      const list = await dockerpen.processes(id);
      return data(list, `${list.processes.length} processes`);
    }),
  );

  registerAppTool(
    server,
    "container_action",
    {
      description: "Start, stop, restart, pause, resume, kill or remove containers",
      inputSchema: z.object({
        ids: z.array(z.string()).min(1),
        action: z.enum(["start", "stop", "restart", "pause", "unpause", "kill", "remove"]),
        force: z.boolean().optional(),
        volumes: z.boolean().optional(),
      }),
      ...app,
    },
    guarded(
      async (args: {
        ids: string[];
        action: "start" | "stop" | "restart" | "pause" | "unpause" | "kill" | "remove";
        force?: boolean;
        volumes?: boolean;
      }) => {
        const outcomes = await dockerpen.act(args.ids, args.action, args);
        const failed = outcomes.filter((o) => !o.ok);
        return data(
          { outcomes },
          failed.length === 0
            ? `${args.action}: ${outcomes.map((o) => o.name).join(", ")}`
            : failed.map((o) => `${o.name}: ${o.error}`).join("\n"),
        );
      },
    ),
  );

  registerAppTool(
    server,
    "open_in_terminal",
    {
      description:
        "Hand the pane to a shell in a container, or to its logs as they come; the view comes back when it ends",
      inputSchema: z.object({ kind: z.enum(["shell", "logs"]), id: z.string() }),
      ...app,
    },
    guarded(async ({ kind, id }: { kind: "shell" | "logs"; id: string }) => {
      const desk = dockerpen.desk;
      const engine = await dockerpen.engine();
      if (desk === undefined || !dockerpen.canHandOff(engine)) {
        return data(
          { state: "unavailable" },
          desk === undefined
            ? "There is no terminal to hand over: this server was started by an MCP client."
            : "The docker command is not installed where dockerpen runs.",
        );
      }
      const container = dockerpen.containers.find((c) => c.id === id);
      const state = desk.request({ kind, id, name: container?.name ?? id.slice(0, 12) });
      return data({ state }, state === "scheduled" ? "Handing the pane over" : "Busy");
    }),
  );

  // ---- images, volumes, networks, disk ---------------------------------------------------

  registerAppTool(
    server,
    "list_images",
    { description: "The images, with the containers made from each", ...app },
    guarded(async () => {
      const images = await listImages(dockerpen.docker, dockerpen.containers);
      return data({ images }, `${images.length} images`);
    }),
  );

  registerAppTool(
    server,
    "image_history",
    {
      description: "The layers of an image",
      inputSchema: z.object({ id: z.string() }),
      ...app,
    },
    guarded(async ({ id }: { id: string }) => {
      const layers = await imageHistory(dockerpen.docker, id);
      return data({ layers }, `${layers.length} layers`);
    }),
  );

  registerAppTool(
    server,
    "image_remove",
    {
      description: "Remove images",
      inputSchema: z.object({ ids: z.array(z.string()).min(1), force: z.boolean().optional() }),
      ...app,
    },
    guarded(async ({ ids, force }: { ids: string[]; force?: boolean }) => {
      const outcomes = await Promise.all(
        ids.map(async (id) => {
          try {
            await removeImage(dockerpen.docker, id, force === true);
            return { id, name: id, ok: true };
          } catch (error) {
            return {
              id,
              name: id,
              ok: false,
              error: error instanceof Error ? error.message : String(error),
            };
          }
        }),
      );
      dockerpen.disk.forget();
      return data(
        { outcomes },
        outcomes.map((o) => (o.ok ? `removed ${o.id}` : o.error)).join("\n"),
      );
    }),
  );

  registerAppTool(
    server,
    "image_pull",
    {
      description: "Pull an image; the pull runs as a job the view follows",
      inputSchema: z.object({ reference: z.string().min(1) }),
      ...app,
    },
    guarded(async ({ reference }: { reference: string }) => {
      const job = dockerpen.pull(reference.trim());
      return data({ job }, job.title);
    }),
  );

  registerAppTool(
    server,
    "list_volumes",
    {
      description: "The volumes, with their size once counted and the containers using each",
      inputSchema: z.object({ sizes: z.boolean().optional() }),
      ...app,
    },
    guarded(async ({ sizes }: { sizes?: boolean }) => {
      const counted = sizes
        ? (await dockerpen.disk.count(15_000)).volumes
        : dockerpen.disk.volumeSizes();
      const volumes = await listVolumes(dockerpen.docker, dockerpen.containers, counted);
      return data({ volumes, sized: counted !== undefined }, `${volumes.length} volumes`);
    }),
  );

  registerAppTool(
    server,
    "volume_remove",
    {
      description: "Remove volumes",
      inputSchema: z.object({ names: z.array(z.string()).min(1) }),
      ...app,
    },
    guarded(async ({ names }: { names: string[] }) => {
      const outcomes = await Promise.all(
        names.map(async (name) => {
          try {
            await removeVolume(dockerpen.docker, name);
            return { id: name, name, ok: true };
          } catch (error) {
            return {
              id: name,
              name,
              ok: false,
              error: error instanceof Error ? error.message : String(error),
            };
          }
        }),
      );
      dockerpen.disk.forget();
      return data(
        { outcomes },
        outcomes.map((o) => (o.ok ? `removed ${o.name}` : o.error)).join("\n"),
      );
    }),
  );

  registerAppTool(
    server,
    "list_networks",
    { description: "The networks, with the running containers on each", ...app },
    guarded(async () => {
      const networks = await listNetworks(dockerpen.docker, dockerpen.containers);
      return data({ networks }, `${networks.length} networks`);
    }),
  );

  registerAppTool(
    server,
    "network_remove",
    {
      description: "Remove networks",
      inputSchema: z.object({ ids: z.array(z.string()).min(1) }),
      ...app,
    },
    guarded(async ({ ids }: { ids: string[] }) => {
      const outcomes = await Promise.all(
        ids.map(async (id) => {
          try {
            await removeNetwork(dockerpen.docker, id);
            return { id, name: id, ok: true };
          } catch (error) {
            return {
              id,
              name: id,
              ok: false,
              error: error instanceof Error ? error.message : String(error),
            };
          }
        }),
      );
      return data(
        { outcomes },
        outcomes.map((o) => (o.ok ? `removed ${o.id}` : o.error)).join("\n"),
      );
    }),
  );

  server.registerTool(
    "disk_usage",
    {
      title: "Docker disk usage",
      description:
        "How much disk Docker's images, containers, volumes and build cache take, and how much can be freed",
    },
    guarded(async () => {
      const { usage } = await dockerpen.disk.count();
      return data({ usage }, diskText(usage));
    }),
  );

  registerAppTool(
    server,
    "prune",
    {
      description: "Remove what nothing uses; runs as a job the view follows",
      inputSchema: z.object({
        targets: z
          .array(
            z.enum([
              "containers",
              "danglingImages",
              "unusedImages",
              "volumes",
              "networks",
              "buildCache",
            ]),
          )
          .min(1),
      }),
      ...app,
    },
    guarded(async ({ targets }: { targets: Parameters<Dockerpen["prune"]>[0] }) => {
      const job = dockerpen.prune(targets);
      return data({ job }, job.title);
    }),
  );

  // ---- for a model -----------------------------------------------------------------------

  server.registerTool(
    "list_containers",
    {
      title: "Docker containers",
      description: "List Docker containers: their state, image, status and published ports",
    },
    guarded(async () => {
      const poll = await dockerpen.poll({ stats: false });
      if (!poll.engine.ok) return failure(`Docker is not reachable: ${poll.engine.error}`);
      return text(`${summaryLine(poll.containers)}\n\n${containerTable(poll.containers)}`);
    }),
  );

  server.registerTool(
    "container_logs",
    {
      title: "Container logs",
      description: "The last lines a container wrote to its output, stderr marked",
      inputSchema: z.object({
        container: z.string().describe("The container's name or id"),
        tail: z
          .number()
          .int()
          .min(1)
          .max(2000)
          .optional()
          .describe("How many lines (200 by default)"),
      }),
    },
    guarded(async ({ container, tail }: { container: string; tail?: number }) => {
      const poll = await dockerpen.poll({ stats: false });
      const found = poll.containers.find((c) => c.name === container || c.id.startsWith(container));
      if (!found) return failure(`There is no container "${container}".`);
      const logs = await readLogs(dockerpen.docker, found.id, null, tail ?? 200);
      const lines = logs.lines.map((line) => `${line.stream === "err" ? "! " : "  "}${line.text}`);
      return text(lines.length ? lines.join("\n") : `${found.name} has written nothing.`);
    }),
  );

  // ---- the view's document ----------------------------------------------------------------

  registerAppResource(server, "Docker", VIEW_URI, {}, async (uri) => ({
    contents: [
      { uri: uri.href, mimeType: RESOURCE_MIME_TYPE, text: await readFile(VIEW_DOCUMENT, "utf8") },
    ],
  }));

  return server;
}
