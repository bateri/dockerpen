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

/**
 * What a pencere terminal takes of an icon list (specification §7.3): a base64 PNG in a data:
 * URI, at most 64 KiB and 512 pixels a side, four of them at most; a picture for each ground,
 * at the 32 pixels a strip asks for.
 */
function checkIcons(icons, owner) {
  assert.ok(Array.isArray(icons) && icons.length > 0 && icons.length <= 4, `${owner} has icons`);
  for (const icon of icons) {
    const match = /^data:image\/png;base64,([A-Za-z0-9+/=]+)$/.exec(icon.src);
    assert.ok(match, `${owner}: an icon is a base64 PNG in a data: URI`);
    const bytes = Buffer.from(match[1], "base64");
    assert.deepEqual([...bytes.subarray(0, 8)], [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    assert.ok(bytes.length <= 64 * 1024, `${owner}: an icon is at most 64 KiB`);
    const [width, height] = [bytes.readUInt32BE(16), bytes.readUInt32BE(20)];
    assert.ok(width <= 512 && height <= 512, `${owner}: an icon is at most 512 pixels a side`);
    assert.deepEqual(icon.sizes, [`${width}x${height}`]);
    assert.equal(icon.mimeType, "image/png");
  }
  for (const theme of ["dark", "light"]) {
    assert.ok(
      icons.some((icon) => icon.theme === theme && icon.sizes[0] === "32x32"),
      `${owner} has a 32-pixel icon for a ${theme} ground`,
    );
  }
}

test("gives its icon as a terminal takes one, for itself and for the view's tool", async () => {
  checkIcons(client.getServerVersion()?.icons, "the server");
  const { tools } = await client.listTools();
  checkIcons(tools.find((tool) => tool.name === "show_docker")?.icons, "show_docker");
});

test("says so when there is no engine, rather than failing the call", async () => {
  const result = await client.callTool({ name: "list_containers", arguments: {} });
  assert.match(JSON.stringify(result.content), /not reachable|ENOENT|connect/i);
});
