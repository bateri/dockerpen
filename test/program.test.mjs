// dockerpen in a terminal pane, with pencere's stand-in host (`pencere-fake-host`) playing the
// terminal, and a stand-in `docker` (test/fixtures/bin/docker) first on the PATH: the page's calls
// and topics travel to the program through the tty as they do in bateri, and what the page was
// told is read off the host's record. The program is the built file, `dist/dockerpen`
// (`make build`); DOCKERPEN_BIN names another. The host is the one built in a pencere checkout
// beside this one (`cargo build -p pencere-fake-host`); PENCERE_FAKE_HOST names another.
//
// Nothing here runs the machine's own Docker: the commands that change things are the stand-in's
// and the commands it was given are in the log it keeps (STANDIN_LOG).
//
// Nothing is skipped. A host or a program that is not there fails the run and says which: a gate
// that passes because it did not look proves nothing.

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterEach, beforeEach, test } from "node:test";

const HOST = process.env.PENCERE_FAKE_HOST
  ? resolve(process.env.PENCERE_FAKE_HOST)
  : new URL("../../pencere/target/debug/pencere-fake-host", import.meta.url).pathname;
const BIN = process.env.DOCKERPEN_BIN
  ? resolve(process.env.DOCKERPEN_BIN)
  : new URL("../dist/dockerpen", import.meta.url).pathname;
const STAND_IN = new URL("./fixtures/bin", import.meta.url).pathname;

const missing = !existsSync(HOST)
  ? `pencere-fake-host is not built (${HOST}): cargo build -p pencere-fake-host in a pencere checkout, then PENCERE_FAKE_HOST=<it>`
  : !existsSync(BIN)
    ? `the program is not built (${BIN}): run make build`
    : undefined;
if (missing !== undefined) {
  throw new Error(`the end-to-end tests cannot run: ${missing}`);
}

let dir;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "dockerpen-test-"));
  mkdirSync(join(dir, "state"));
});
afterEach(() => rmSync(dir, { recursive: true, force: true }));

const ID = (letter) => letter.repeat(64);

/**
 * Runs dockerpen in a pane: the page subscribes to `topics` and makes `calls` (each `[method,
 * params]`), then `then` happens. Gives what the page was told, by the number it asked with.
 */
function pane({ calls = [], topics = [], env = {}, then = ["--then", "interrupt"], limit = 20, args = [], host = [] } = {}) {
  const hostArgs = ["--size", "100x30", "--limit", String(limit), ...host];
  for (const [topic, params] of topics) hostArgs.push("--subscribe", `${topic}=${JSON.stringify(params ?? {})}`);
  for (const [method, params] of calls) hostArgs.push("--call", `${method}=${JSON.stringify(params ?? {})}`);
  const run = spawnSync(HOST, [...hostArgs, ...then, "--", BIN, ...args], {
    cwd: dir,
    env: {
      ...process.env,
      // Nothing the program keeps is written under the real home, and the docker command is the
      // stand-in's, whatever else is on the PATH.
      HOME: dir,
      PATH: `${STAND_IN}:${process.env.PATH}`,
      PENCERE_FAKE_GIST: "100000000",
      STANDIN_LOG: join(dir, "docker.log"),
      STANDIN_STATE: join(dir, "state"),
      ...env,
    },
    encoding: "utf8",
    timeout: 60_000,
  });
  return read(run.stderr, run);
}

/** What the host's record says the page was told. */
function read(log, run) {
  const asked = new Map();
  const told = { log, status: run.status, calls: {}, errors: {}, pushes: {} };
  for (const line of log.split("\n")) {
    let match = /^view: -> call id=(\d+) (\S+)/.exec(line);
    if (match) asked.set(Number(match[1]), match[2]);
    match = /^view: -> subscribe id=(\d+) (\S+)/.exec(line);
    if (match) asked.set(Number(match[1]), match[2]);
    match = /^view: <- response id=(\d+) result=(.*)$/.exec(line);
    if (match) {
      const name = asked.get(Number(match[1]));
      (told.calls[name] ??= []).push(JSON.parse(match[2]));
    }
    match = /^view: <- response id=(\d+) error code=(\S+) message="(.*)"$/.exec(line);
    if (match) {
      const name = asked.get(Number(match[1]));
      (told.errors[name] ??= []).push({ code: match[2], message: match[3] });
    }
    match = /^view: <- push id=(\d+) value=(.*)$/.exec(line);
    if (match) {
      const name = asked.get(Number(match[1]));
      (told.pushes[name] ??= []).push(JSON.parse(match[2]));
    }
  }
  return told;
}

/** The commands the stand-in docker was given. */
function ran() {
  const file = join(dir, "docker.log");
  return existsSync(file) ? readFileSync(file, "utf8").split("\n").filter(Boolean) : [];
}

// ---- the start ----------------------------------------------------------------------------

test("the page is shown the view and the program says what it is", () => {
  const told = pane({ calls: [["boot"]] });
  assert.match(told.log, /program: open id=\d+ view=lua version=2\.0 title="Docker"/);
  assert.match(told.log, /view: title="Docker" program="dockerpen"/);
  assert.match(told.log, /view: icons png 32x32 dark,png 64x64 dark,png 32x32 light,png 64x64 light/);
  const [boot] = told.calls.boot;
  assert.equal(boot.handoff, true);
  assert.equal(boot.ui, null);
  assert.equal(boot.section, null);
  assert.match(boot.version, /^\d+\.\d+\.\d+/);
  assert.ok(Math.abs(boot.time - Date.now() / 1000) < 60, "the time of day, for a page that has no clock");
});

test("the command line says what the view opens on, once", () => {
  const told = pane({ calls: [["boot"]], args: ["web", "--section", "images"] });
  assert.equal(told.calls.boot[0].focus, "web");
  assert.equal(told.calls.boot[0].section, "images");
});

test("what the page keeps of itself is held for the next view", () => {
  const ui = { section: "images", detail: ID("a") };
  const told = pane({ calls: [["ui", { ui }], ["boot"]] });
  assert.deepEqual(told.calls.boot[0].ui, ui);
});

test("a call is checked before it is run", () => {
  const told = pane({
    calls: [
      ["detail", { id: 3 }],
      ["act", { ids: [], action: "stop" }],
      ["act", { ids: ["x"], action: "explode" }],
      ["image_remove", {}],
      ["prune", { targets: ["everything"] }],
      ["pull", { reference: "--rm" }],
      ["handoff", { kind: "shell" }],
    ],
  });
  const codes = Object.values(told.errors).flat().map((error) => error.code);
  assert.deepEqual(codes, ["bad-params", "bad-params", "bad-params", "bad-params", "bad-params", "bad-params", "bad-params"]);
  assert.match(told.errors.detail[0].message, /id: expected a name, got number/);
  assert.deepEqual(ran(), [], "nothing was run for a call that did not fit");
});

test("a name that docker would read as an option is not passed to it", () => {
  const told = pane({
    calls: [
      ["detail", { id: "--all" }],
      ["act", { ids: ["-f"], action: "remove" }],
      ["image_layers", { id: "line\nbreak" }],
    ],
  });
  assert.deepEqual(
    Object.values(told.errors)
      .flat()
      .map((error) => error.code),
    ["bad-params", "bad-params", "bad-params"],
  );
  assert.deepEqual(ran(), []);
});

// ---- containers ---------------------------------------------------------------------------

test("the containers topic tells the list as docker gives it, with what is read from the words", () => {
  const told = pane({ topics: [["containers"]] });
  const [first] = told.pushes.containers;
  assert.equal(first.failure, null);
  assert.deepEqual(first.engine, {
    ok: true,
    name: "Stand-in OS 1.0",
    hostname: "standin",
    version: "29.0.1",
    os: "linux",
    arch: "aarch64",
    cpus: 6,
    memory: 12589744128,
    endpoint: "unix:///standin.sock",
  });
  const byName = Object.fromEntries(first.containers.map((c) => [c.name, c]));
  assert.equal(Object.keys(byName).length, 7);
  const api = byName["shop-api-1"];
  assert.equal(api.id, ID("a"));
  assert.equal(api.short, "a".repeat(12));
  assert.equal(api.state, "running");
  assert.equal(api.health, "healthy");
  assert.equal(api.project, "shop");
  assert.equal(api.service, "api");
  assert.equal(api.image, "node:22-alpine");
  assert.deepEqual(api.ports, [{ public: 3000, private: 3000, type: "tcp", ip: "0.0.0.0" }]);
  assert.deepEqual(api.networks, ["shop_default"]);
  assert.equal(api.created, Date.parse("2026-10-25T11:00:00Z") / 1000);
  assert.equal(byName["shop-db-1"].health, "starting");
  assert.deepEqual(byName["shop-db-1"].mounts, ["shop_db-data"]);
  assert.equal(byName["shop-search-1"].health, "unhealthy");
  assert.equal(byName["shop-mailer-1"].state, "exited");
  assert.equal(byName["shop-mailer-1"].exit_code, 1);
  assert.equal(byName["shop-mailer-1"].health, "none");
  assert.equal(byName["toolbox"].project, undefined);
  assert.deepEqual(byName["shop-web-1"].ports, [{ public: 8088, private: 80, type: "tcp", ip: "0.0.0.0" }]);
  assert.deepEqual(byName["toolbox"].ports, [{ private: 6379, type: "tcp" }]);
  // What it ran to tell this: the list, and the engine. (The events it follows are started at the
  // same time, and may not have said so yet when the first value goes: they are not told apart
  // from a list that came first.)
  const ran_first = ran().filter((line) => !line.startsWith("events "));
  assert.deepEqual(ran_first.sort(), [
    "context inspect --format {{.Endpoints.docker.Host}}",
    "info --format {{json .}}",
    "ps -a --no-trunc --format json",
  ]);
});

test("the detail of a container is what docker inspect says, read", () => {
  const told = pane({ calls: [["detail", { id: "shop-api-1" }]] });
  const [detail] = told.calls.detail;
  assert.equal(detail.name, "shop-api-1");
  assert.equal(detail.image, "node:22-alpine");
  assert.equal(detail.user, "node");
  assert.equal(detail.working_dir, "/app");
  assert.deepEqual(detail.env[1], { key: "DATABASE_URL", value: "postgres://shop:hunter2@db:5432/shop" });
  assert.equal(detail.restart_policy, "on-failure:3");
  assert.equal(detail.restart_count, 2);
  assert.equal(detail.memory_limit, 536870912);
  assert.equal(detail.cpu_limit, 1.5);
  assert.equal(detail.state.status, "running");
  assert.equal(detail.state.finished_at, undefined, "docker's \"never\" is no date");
  assert.equal(detail.state.started_at, Date.parse("2026-10-25T11:00:01Z") / 1000, "whole seconds");
  assert.equal(detail.state.health.status, "healthy");
  assert.equal(detail.state.health.log[0].output, "ok");
  assert.deepEqual(detail.ports, [
    { private: 3000, public: 3000, type: "tcp", ip: "0.0.0.0" },
    { private: 9229, type: "tcp" },
  ]);
  assert.deepEqual(detail.networks[0].aliases, ["shop-api-1", "api"], "the container's own id is no alias");
  assert.deepEqual(detail.mounts[0], {
    type: "volume",
    name: "shop_api-data",
    source: "/var/lib/docker/volumes/shop_api-data/_data",
    destination: "/data",
    rw: true,
  });
  assert.deepEqual(detail.healthcheck.slice(0, 2), ["CMD", "wget"]);
  assert.match(detail.lines[0], /^\[$/);
  assert.ok(detail.lines.length > 20, "the engine's whole answer, line by line");
});

test("a container that is not there is told as docker says it", () => {
  const told = pane({ calls: [["detail", { id: "nothing-of-the-kind" }]] });
  assert.deepEqual(told.errors.detail, [{ code: "docker-failed", message: "No such container: nothing-of-the-kind" }]);
});

test("the processes of a container are the columns docker top prints", () => {
  const told = pane({ calls: [["processes", { id: "shop-api-1" }]] });
  const [processes] = told.calls.processes;
  assert.deepEqual(processes.titles, ["PID", "USER", "TIME", "COMMAND"]);
  assert.deepEqual(processes.rows[1], ["4310", "node", "0:00", "sh -c wget -q -O /dev/null http://localhost:3000/healthz"]);
});

test("containers are acted on with one command, and what became of each is told", () => {
  const told = pane({
    calls: [
      ["act", { ids: [ID("a"), ID("b")], action: "stop" }],
      ["act", { ids: [ID("e")], action: "remove", force: true, volumes: true }],
      ["act", { ids: [ID("c")], action: "restart" }],
    ],
  });
  assert.deepEqual(
    told.calls.act.map((answer) => answer.outcomes.map((o) => [o.ok, o.name])),
    [
      [[true, "a".repeat(12)], [true, "b".repeat(12)]],
      [[true, "e".repeat(12)]],
      [[true, "c".repeat(12)]],
    ],
  );
  assert.deepEqual(ran(), [
    `stop --time 10 ${ID("a")} ${ID("b")}`,
    `rm --force --volumes ${ID("e")}`,
    `restart --time 10 ${ID("c")}`,
  ]);
});

test("one container that cannot be acted on does not fail the others", () => {
  const told = pane({
    calls: [["act", { ids: [ID("a"), ID("b")], action: "kill" }]],
    env: { STANDIN_FAIL: ID("b") },
  });
  const [{ outcomes }] = told.calls.act;
  assert.deepEqual(outcomes.map((o) => o.ok), [true, false]);
  assert.match(outcomes[1].error, /cannot kill container: b+: it is not possible just now/);
});

test("a container the page has listed is named in the outcome", () => {
  const told = pane({
    topics: [["containers"]],
    calls: [["act", { ids: [ID("e")], action: "start" }]],
  });
  assert.equal(told.calls.act[0].outcomes[0].name, "shop-mailer-1");
});

// ---- docker that is not there, or not well --------------------------------------------------

test("with no docker command the page is told so, and nothing is run", () => {
  const empty = join(dir, "empty");
  mkdirSync(empty);
  const told = pane({
    topics: [["containers"]],
    calls: [["detail", { id: "x" }], ["images"], ["act", { ids: ["x"], action: "stop" }]],
    env: { PATH: empty },
  });
  const [value] = told.pushes.containers;
  assert.equal(value.failure.code, "docker-missing");
  assert.match(value.failure.message, /no docker command on the PATH/);
  assert.deepEqual(value.containers, []);
  for (const method of ["detail", "images", "act"]) {
    assert.equal(told.errors[method][0].code, "docker-missing", method);
  }
});

test("with no engine to talk to the page is told so", () => {
  const told = pane({
    topics: [["containers"]],
    calls: [["images"], ["act", { ids: ["x"], action: "stop" }]],
    env: { STANDIN_MODE: "down" },
  });
  assert.equal(told.pushes.containers[0].failure.code, "engine-down");
  assert.match(told.pushes.containers[0].failure.message, /Cannot connect to the Docker daemon/);
  assert.equal(told.errors.images[0].code, "engine-down");
  assert.equal(told.errors.act[0].code, "engine-down");
});

test("a docker that fails says why, in its own words", () => {
  const told = pane({ calls: [["volumes"], ["networks"], ["system"]], env: { STANDIN_MODE: "broken" } });
  for (const method of ["volumes", "networks", "system"]) {
    assert.deepEqual(told.errors[method], [{ code: "docker-failed", message: "something is wrong in here" }], method);
  }
});

test("a terminal that shows no views is given the containers as text", () => {
  const run = spawnSync(HOST, ["--no-host", "--size", "100x30", "--limit", "20", "--", BIN], {
    cwd: dir,
    env: { ...process.env, HOME: dir, PATH: `${STAND_IN}:${process.env.PATH}` },
    encoding: "utf8",
    timeout: 40_000,
  });
  assert.match(run.stderr, /program: exited with status 0/);
  const text = spawnSync(BIN, ["--text"], {
    env: { ...process.env, HOME: dir, PATH: `${STAND_IN}:${process.env.PATH}` },
    encoding: "utf8",
  });
  assert.equal(text.status, 0);
  const lines = text.stdout.split("\n");
  assert.match(lines[0], /^NAME\s+IMAGE\s+STATE\s+STATUS\s+PORTS$/);
  assert.ok(lines.some((line) => /^shop-api-1\s+node:22-alpine\s+running \(healthy\)\s+Up 3 minutes \(healthy\)\s+3000->3000$/.test(line)), text.stdout);
  assert.ok(lines.some((line) => /^shop-mailer-1\s+busybox\s+exited\s+Exited \(1\) 2 minutes ago\s*$/.test(line)));
});

test("--text says what is wrong when docker is not there", () => {
  const empty = join(dir, "empty");
  mkdirSync(empty);
  const text = spawnSync(BIN, ["--text"], { env: { ...process.env, HOME: dir, PATH: empty }, encoding: "utf8" });
  assert.equal(text.status, 1);
  assert.match(text.stderr, /dockerpen: There is no docker command on the PATH/);
});

test("a command line that is wrong is refused", () => {
  const run = spawnSync(BIN, ["--section", "nowhere"], { encoding: "utf8" });
  assert.equal(run.status, 64);
  assert.match(run.stderr, /--section is one of containers, images/);
  assert.equal(spawnSync(BIN, ["--version"], { encoding: "utf8" }).stdout.trim().split(" ")[0], "dockerpen");
});

// ---- the streams ----------------------------------------------------------------------------

test("the logs topic tells a log in lists, with the time of day and the stream of each line", () => {
  const told = pane({ topics: [["logs", { id: "shop-api-1", tail: 100 }]] });
  const [batch] = told.pushes.logs;
  assert.equal(batch.texts.length, 7);
  assert.equal(batch.streams, "oooeooo");
  assert.equal(batch.texts[0], "\u001b[32mINFO\u001b[0m GET /api/orders 200 7ms");
  assert.equal(batch.texts[3], "\u001b[31mERROR\u001b[0m payment provider timed out");
  assert.equal(batch.clocks.length, 7);
  assert.match(batch.clocks[0], /^\d\d:\d\d:\d\d\.000$/);
  assert.match(batch.last, /^2026-10-25T10:56:\d\d\.\d+Z$/);
  assert.match(ran()[0], /^logs --follow --timestamps --tail 100 shop-api-1$/);
});

test("a log followed again goes on from the last line it showed", () => {
  const first = pane({ topics: [["logs", { id: "shop-api-1", tail: 100 }]] });
  const last = first.pushes.logs[0].last;
  // Nothing came after that line, and the line itself is not told twice: so, nothing is pushed.
  const again = pane({ topics: [["logs", { id: "shop-api-1", since: last }]], then: ["--then", "wait"], limit: 3 });
  assert.equal(again.pushes.logs, undefined);
  assert.match(ran().at(-1), new RegExp(`^logs --follow --timestamps --since ${last}`));
  const from = pane({ topics: [["logs", { id: "shop-api-1", since: "2026-10-25T10:56:44.000004000Z" }]] });
  assert.deepEqual(
    from.pushes.logs[0].texts.map((text) => text.replace(/\u001b\[\d+m/g, "")),
    ["INFO GET /api/orders 200 35ms", "INFO GET /api/orders 200 42ms"],
  );
});

test("a log the page may not ask for is ended, not run", () => {
  const told = pane({ topics: [["logs", { id: "x", tail: -5 }]] });
  assert.equal(told.pushes.logs[0].ended.code, "bad-params");
  assert.deepEqual(ran(), []);
});

test("the stats topic tells the readings of the running containers, rates worked out", () => {
  const told = pane({ topics: [["stats"]], then: ["--then", "wait"], limit: 6 });
  assert.deepEqual(told.pushes.stats[0], { history: [] });
  const samples = told.pushes.stats.slice(1).flatMap((push) => push.samples);
  const by = Object.fromEntries(samples.map((sample) => [sample.name, sample]));
  assert.equal(by["shop-api-1"].cpu, 12.5);
  assert.equal(by["shop-api-1"].memory, Math.round(48.2 * 1024 * 1024));
  assert.equal(by["shop-api-1"].memory_limit, 512 * 1024 * 1024);
  assert.equal(by["shop-db-1"].cpu, 200, "two processors busy is 200 percent");
  assert.equal(by["shop-db-1"].pids, 27);
  assert.equal(by["shop-api-1"].id, "a".repeat(12));
});

test("a stream that ends by itself is opened again while the page listens", () => {
  const told = pane({
    topics: [["stats"]],
    then: ["--then", "wait"],
    limit: 8,
    env: { STANDIN_STATS: "ends" },
  });
  const samples = told.pushes.stats.slice(1).flatMap((push) => push.samples);
  assert.ok(samples.length >= 6, `the readings of the second start came too: ${samples.length}`);
  assert.equal((ran().filter((line) => line === "stats --format json")).length >= 2, true);
});

test("the events topic tells the engine's reports, and which of them are news", () => {
  const told = pane({ topics: [["events"]], then: ["--then", "wait"], limit: 5 });
  assert.deepEqual(told.pushes.events[0], { backlog: [] });
  const items = told.pushes.events.slice(1).flatMap((push) => push.items);
  assert.deepEqual(
    items.map((item) => [item.action, item.name, item.notice ?? null]),
    [
      ["start", "shop-api-1", null],
      ["health_status", "shop-search-1", "unhealthy"],
      ["die", "shop-mailer-1", "died"],
      ["oom", "shop-db-1", "oom"],
      ["kill", "shop-web-1", null],
      ["die", "shop-web-1", null],
      ["pull", "nginx:alpine", null],
    ],
    "a container asked to stop that dies with the signal's code is not news; exec events and a look at the processes are left out",
  );
  assert.equal(items[2].words, "exited with code 1");
  assert.equal(items[2].project, "shop");
  assert.deepEqual(items.map((item) => item.seq), [1, 2, 3, 4, 5, 6, 7]);
});

test("nothing is run for a topic nobody listens to", () => {
  pane({ calls: [["boot"]] });
  assert.deepEqual(ran(), []);
});

test("a stream is stopped when the page stops listening", () => {
  // The page gives each subscription up after what the stream says first (the topics of `stats` and
  // `events` begin with what is kept, and the second push is the stream's own); the stand-in
  // docker says, when it is ended, that it was. A stream left running would not.
  for (const [topic, params, pushes] of [
    ["stats", {}, 2],
    ["events", {}, 2],
    ["logs", { id: "shop-api-1" }, 1],
  ]) {
    pane({ topics: [[topic, params]], then: ["--then", "wait"], limit: 6, host: ["--cancel-after", String(pushes)] });
    assert.ok(
      existsSync(join(dir, "state", `${topic}-stopped`)),
      `docker ${topic} was stopped when the page stopped listening`,
    );
    rmSync(join(dir, "state", `${topic}-stopped`));
  }
});

test("and a stream is ended with the pane, whatever it was doing", () => {
  pane({ topics: [["logs", { id: "shop-api-1" }]], then: ["--then", "interrupt"] });
  const pid = Number(readFileSync(join(dir, "state", "logs-pid"), "utf8"));
  assert.ok(pid > 0, "docker logs ran");
  let alive = true;
  try {
    process.kill(pid, 0);
  } catch {
    alive = false;
  }
  assert.ok(!alive, `docker logs (${pid}) ended with dockerpen`);
});

// ---- images, volumes, networks, the disk ----------------------------------------------------

test("images are listed by what they are, with the containers made from them", () => {
  const told = pane({ topics: [["containers"]], calls: [["images"]] });
  const { images } = told.calls.images[0];
  assert.equal(images.length, 3, "an image with two tags is one image");
  const node = images.find((image) => image.id === "9".repeat(12));
  assert.deepEqual(node.tags, ["node:22-alpine", "node:lts-alpine"]);
  assert.equal(node.size, 180_000_000);
  assert.deepEqual(node.containers, ["shop-api-1"]);
  assert.equal(node.running, 1);
  const nginx = images.find((image) => image.id === "8".repeat(12));
  assert.deepEqual(nginx.containers, ["blog-site-1", "shop-web-1"]);
  assert.equal(nginx.running, 1);
  const dangling = images.find((image) => image.dangling);
  assert.deepEqual(dangling.tags, []);
  assert.equal(dangling.size, 1_060_000_000);
});

test("the layers of an image, newest first", () => {
  const told = pane({ calls: [["image_layers", { id: "node:22-alpine" }]] });
  const { layers } = told.calls.image_layers[0];
  assert.equal(layers.length, 2);
  assert.equal(layers[0].created_by, 'CMD ["node"]');
  assert.equal(layers[0].size, 0);
  assert.equal(layers[1].id, "", "a layer that is missing has no id");
  assert.equal(layers[1].size, 91_700_000);
});

test("images are removed one at a time, and forced when the page says so", () => {
  const told = pane({
    calls: [
      ["image_remove", { ids: ["node:22-alpine", "nginx:alpine"] }],
      ["image_remove", { ids: ["nginx:alpine"], force: true }],
    ],
  });
  assert.deepEqual(told.calls.image_remove[0].outcomes.map((o) => o.ok), [true, true]);
  assert.deepEqual(ran(), [
    "image rm node:22-alpine",
    "image rm nginx:alpine",
    "image rm --force nginx:alpine",
  ]);
});

test("a pull is a job the page follows", () => {
  const told = pane({
    topics: [["jobs"]],
    calls: [["pull", { reference: "redis" }]],
    then: ["--then", "wait"],
    limit: 4,
  });
  const [{ job }] = told.calls.pull;
  assert.equal(job.kind, "pull");
  assert.equal(job.title, "Pull redis");
  assert.equal(job.state, "running");
  const jobs = told.pushes.jobs.map((push) => push.jobs.at(-1)).filter(Boolean);
  const last = jobs.at(-1);
  assert.equal(last.state, "done");
  assert.equal(last.progress, 1);
  assert.ok(jobs.some((one) => one.progress === 0.5), "how far it came, from the layers");
  assert.deepEqual(ran(), ["pull redis"]);
});

test("a pull that fails says why", () => {
  const told = pane({
    topics: [["jobs"]],
    calls: [["pull", { reference: "nosuch/image" }]],
    then: ["--then", "wait"],
    limit: 4,
    env: { STANDIN_PULL: "fail" },
  });
  const last = told.pushes.jobs.map((push) => push.jobs.at(-1)).filter(Boolean).at(-1);
  assert.equal(last.state, "failed");
  assert.match(last.error, /pull access denied for nosuch\/image/);
});

test("volumes are listed with who mounts them, and their sizes are counted apart", () => {
  const told = pane({ topics: [["containers"]], calls: [["volumes"], ["volume_sizes"]] });
  const { volumes, sized } = told.calls.volumes[0];
  assert.equal(sized, false);
  const named = volumes.find((volume) => volume.name === "shop_db-data");
  assert.equal(named.project, "shop");
  assert.equal(named.anonymous, false);
  assert.equal(named.size, null);
  assert.deepEqual(named.containers, ["shop-db-1"]);
  assert.equal(volumes.find((volume) => volume.name === "ab".repeat(32)).anonymous, true);
  assert.deepEqual(told.calls.volume_sizes[0].sizes, {
    "shop_db-data": 236_000_000,
    ["ab".repeat(32)]: 1_200_000,
  });
});

test("volumes are removed by name", () => {
  const told = pane({ calls: [["volume_remove", { names: ["shop_db-data"] }]] });
  assert.equal(told.calls.volume_remove[0].outcomes[0].ok, true);
  assert.deepEqual(ran(), ["volume rm shop_db-data"]);
});

test("networks are listed with their subnets and the containers on them", () => {
  const told = pane({ calls: [["networks"]] });
  const { networks } = told.calls.networks[0];
  const shop = networks.find((network) => network.name === "shop_default");
  assert.equal(shop.id, "shopnet111".padEnd(12, "1"));
  assert.equal(shop.project, "shop");
  assert.deepEqual(shop.subnets, ["172.18.0.0/16"]);
  assert.deepEqual(shop.gateways, ["172.18.0.1"]);
  assert.deepEqual(shop.containers, ["shop-api-1", "shop-web-1"]);
  assert.equal(shop.builtin, false);
  assert.equal(networks.find((network) => network.name === "bridge").builtin, true);
  assert.deepEqual(networks.find((network) => network.name === "host").subnets, []);
  assert.deepEqual(ran(), ["network ls --no-trunc --format json", `network inspect ${"bridge0000".padEnd(64, "0")} ${"shopnet111".padEnd(64, "1")} ${"host000000".padEnd(64, "0")}`]);
});

test("the disk is told as docker counts it", () => {
  const told = pane({ calls: [["system"]] });
  const { usage, engine } = told.calls.system[0];
  assert.deepEqual(usage.images, { count: 5, active: 4, size: 1_100_000_000, reclaimable: 124_000_000 });
  assert.deepEqual(usage.volumes, { count: 7 - 5, active: 1, size: 237_000_000, reclaimable: 189_000_000 });
  assert.deepEqual(usage.containers, { count: 7, active: 6, size: 16_400, reclaimable: 4_100 });
  assert.deepEqual(usage.build_cache, { count: 0, active: 0, size: 0, reclaimable: 0 });
  assert.equal(engine.version, "29.0.1");
});

test("a clean-up is a job of commands that do not ask, one kind after another", () => {
  const told = pane({
    topics: [["jobs"]],
    calls: [["prune", { targets: ["containers", "unused_images", "volumes", "networks", "build_cache"] }]],
    then: ["--then", "wait"],
    limit: 4,
  });
  assert.equal(told.calls.prune[0].job.kind, "prune");
  assert.deepEqual(ran(), [
    "container prune --force",
    "image prune --all --force",
    "volume prune --all --force",
    "network prune --force",
    "builder prune --all --force",
  ]);
  const last = told.pushes.jobs.map((push) => push.jobs.at(-1)).filter(Boolean).at(-1);
  assert.equal(last.state, "done");
  assert.equal(last.freed, 16_400 + 1_200_000 + 237_000_000, "what the commands said they freed, added");
});

// ---- the pane given away --------------------------------------------------------------------

test("the pane goes to a shell in a container and comes back to the view", () => {
  const told = pane({
    calls: [["handoff", { kind: "shell", id: ID("a"), name: "shop-api-1" }], ["boot"]],
    then: ["--on-view", "2", "--then", "interrupt"],
  });
  assert.match(told.log, /program: dismiss/);
  assert.match(told.log, /closed id=\d+ re=\d+ reason=program/);
  assert.equal((told.log.match(/view: started from the bundle/g) ?? []).length, 2);
  assert.equal(told.calls.handoff[0].state, "scheduled");
  const boots = told.calls.boot;
  assert.equal(boots.length, 2);
  assert.equal(boots[0].returned, undefined);
  assert.equal(boots[1].returned.kind, "shell");
  assert.equal(boots[1].returned.name, "shop-api-1");
  assert.equal(typeof boots[1].returned.duration, "number");
  assert.ok(
    ran().some((line) => line.startsWith(`exec -it ${ID("a")} sh -c command -v bash`)),
    ran().join("\n"),
  );
});

test("the log can have the pane too", () => {
  const told = pane({
    calls: [["handoff", { kind: "logs", id: ID("a"), name: "shop-api-1" }], ["boot"]],
    then: ["--on-view", "2", "--then", "interrupt"],
    env: { STANDIN_FOLLOW: "ends" },
  });
  assert.equal(told.calls.boot[1].returned.kind, "logs");
  assert.ok(ran().some((line) => line === `logs --follow --tail 200 ${ID("a")}`), ran().join("\n"));
});

test("what the page keeps of itself crosses the hand-off", () => {
  const ui = { section: "containers", detail: ID("a"), tab: "logs" };
  const told = pane({
    calls: [["ui", { ui }], ["handoff", { kind: "shell", id: ID("a") }], ["boot"]],
    then: ["--on-view", "2", "--then", "interrupt"],
  });
  assert.deepEqual(told.calls.boot.at(-1).ui, ui);
});
