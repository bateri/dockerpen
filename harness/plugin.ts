/**
 * The harness's server side: Vite serves the view with hot reload, and this plugin
 * runs the real dockerpen server over stdio (as an MCP client would) and passes the
 * harness page's tool calls to it.
 */

import { Client } from "@modelcontextprotocol/client";
import { StdioClientTransport } from "@modelcontextprotocol/client/stdio";
import type { IncomingMessage } from "node:http";
import type { Plugin } from "vite";

export function harness(): Plugin {
  let client: Promise<Client> | undefined;
  const connect = () => {
    client ??= (async () => {
      const c = new Client({ name: "dockerpen-harness", version: "0.0.0" });
      // The whole environment, not the client's safe few: DOCKER_HOST and DOCKER_CONTEXT pick the engine.
      const env = Object.fromEntries(
        Object.entries(process.env).filter(
          (entry): entry is [string, string] => entry[1] !== undefined,
        ),
      );
      await c.connect(
        new StdioClientTransport({ command: process.execPath, args: ["dist/server/main.js"], env }),
      );
      return c;
    })();
    return client;
  };
  const body = (request: IncomingMessage) =>
    new Promise<string>((resolve, reject) => {
      let text = "";
      request.on("data", (chunk: Buffer) => (text += chunk.toString("utf8")));
      request.on("end", () => resolve(text));
      request.on("error", reject);
    });
  return {
    name: "dockerpen-harness",
    configureServer(server) {
      server.middlewares.use(async (request, response, next) => {
        if (request.url === "/" || request.url?.startsWith("/?")) {
          response.statusCode = 302;
          response.setHeader("Location", "/harness/index.html");
          response.end();
          return;
        }
        if (!request.url?.startsWith("/__harness/")) return next();
        try {
          const c = await connect();
          let result: unknown;
          if (request.url === "/__harness/tools") result = await c.listTools();
          else {
            const { name, arguments: args } = JSON.parse(await body(request)) as {
              name: string;
              arguments: Record<string, unknown>;
            };
            result = await c.callTool({ name, arguments: args });
          }
          response.setHeader("Content-Type", "application/json");
          response.end(JSON.stringify(result));
        } catch (error) {
          client = undefined;
          response.statusCode = 500;
          response.end(String(error));
        }
      });
    },
  };
}
