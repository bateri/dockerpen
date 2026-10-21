// The built server as an MCP client starts it: what it offers, and the view it serves,
// without a Docker engine (DOCKER_HOST points at nothing), so it runs on any machine.

import { Client } from "@modelcontextprotocol/client";
import { StdioClientTransport } from "@modelcontextprotocol/client/stdio";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { after, before, test } from "node:test";

const main = new URL("../dist/server/main.js", import.meta.url).pathname;
const manifest = JSON.parse(readFileSync(new URL("../package.json", import.meta.url), "utf8"));

let client;

before(async () => {
  client = new Client({ name: "dockerpen-test", version: "0.0.0" });
  await client.connect(
    new StdioClientTransport({
      command: process.execPath,
      args: [main],
      env: { PATH: process.env.PATH ?? "", DOCKER_HOST: "unix:///nonexistent/docker.sock" },
    }),
  );
});

after(async () => {
  await client?.close();
});

test("says the manifest's version", () => {
  assert.equal(
    execFileSync(process.execPath, [main, "--version"], { encoding: "utf8" }).trim(),
    manifest.version,
  );
});

test("offers the view tool to the model and keeps what changes things for the view", async () => {
  const { tools } = await client.listTools();
  const byName = new Map(tools.map((tool) => [tool.name, tool]));
  for (const name of ["show_docker", "list_containers", "container_logs", "disk_usage"]) {
    assert.ok(byName.has(name), `${name} is offered`);
  }
  assert.equal(byName.get("show_docker")._meta?.ui?.resourceUri, "ui://dockerpen/view");
  for (const name of ["container_action", "image_remove", "volume_remove", "prune"]) {
    assert.deepEqual(byName.get(name)?._meta?.ui?.visibility, ["app"], `${name} is the view's`);
  }
});

test("serves the view as one document", async () => {
  const { contents } = await client.readResource({ uri: "ui://dockerpen/view" });
  assert.equal(contents.length, 1);
  assert.match(contents[0].text, /<div id="root">/);
  assert.ok(contents[0].text.length > 100_000, "scripts and styles are inside the document");
});

test("says so when there is no engine, rather than failing the call", async () => {
  const result = await client.callTool({ name: "list_containers", arguments: {} });
  assert.match(JSON.stringify(result.content), /not reachable|ENOENT|connect/i);
});
