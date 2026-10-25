-- What the program tells the page, as the tests make it: containers and what is around them, the
-- shapes src/program/api gives (the program's own tests hold the program to them).

local M = {}

local function id(letter)
	return string.rep(letter, 64)
end

M.id = id

-- A container as the program lists it; `fields` say what differs.
function M.container(letter, name, fields)
	local c = {
		id = id(letter),
		short = string.rep(letter, 12),
		name = name,
		image = "busybox",
		command = "sh",
		created = 1792925000,
		state = "running",
		status = "Up 3 minutes",
		health = "none",
		ports = {},
		networks = { "default" },
		mounts = {},
	}
	for key, value in pairs(fields or {}) do
		c[key] = value
	end
	return c
end

function M.shop()
	return {
		M.container("a", "shop-api-1", {
			image = "node:22-alpine",
			health = "healthy",
			status = "Up 3 minutes (healthy)",
			project = "shop",
			service = "api",
			ports = { { public = 3000, private = 3000, type = "tcp", ip = "0.0.0.0" } },
		}),
		M.container("b", "shop-web-1", { image = "nginx:alpine", project = "shop", service = "web" }),
		M.container("c", "shop-db-1", {
			image = "postgres:17-alpine",
			health = "starting",
			status = "Up 3 minutes (health: starting)",
			project = "shop",
			service = "db",
		}),
		M.container("d", "shop-search-1", {
			health = "unhealthy",
			status = "Up 3 minutes (unhealthy)",
			project = "shop",
			service = "search",
		}),
		M.container("e", "shop-mailer-1", {
			state = "exited",
			status = "Exited (1) 2 minutes ago",
			exit_code = 1,
			project = "shop",
			service = "mailer",
		}),
		M.container("f", "toolbox", { image = "redis:alpine", status = "Up About an hour" }),
		M.container("1", "blog-site-1", {
			state = "exited",
			status = "Exited (0) 20 hours ago",
			exit_code = 0,
			project = "blog",
			service = "site",
		}),
	}
end

M.engine = {
	ok = true,
	name = "Stand-in OS",
	hostname = "standin",
	version = "29.0.1",
	os = "linux",
	arch = "aarch64",
	cpus = 6,
	memory = 12589744128,
	endpoint = "unix:///standin.sock",
}

M.boot = {
	version = "0.2.1",
	time = 1792925800,
	hostname = "mac",
	remote = false,
	handoff = true,
}

M.detail = {
	id = id("a"),
	name = "shop-api-1",
	image = "node:22-alpine",
	image_id = "sha256:" .. id("9"),
	created = 1792925000,
	path = "docker-entrypoint.sh",
	args = { "node", "server.js" },
	entrypoint = { "docker-entrypoint.sh" },
	cmd = { "node", "server.js" },
	working_dir = "/app",
	user = "node",
	env = {
		{ key = "PORT", value = "3000" },
		{ key = "DATABASE_URL", value = "postgres://shop:hunter2@db:5432/shop" },
		{ key = "LOG_LEVEL", value = "info" },
	},
	labels = { ["com.docker.compose.project"] = "shop" },
	state = {
		status = "running",
		running = true,
		paused = false,
		restarting = false,
		oom_killed = false,
		dead = false,
		pid = 4242,
		exit_code = 0,
		error = "",
		started_at = 1792925700,
		health = { status = "healthy", failing_streak = 0, log = { { exit_code = 0, output = "ok" } } },
	},
	restart_count = 2,
	restart_policy = "on-failure:3",
	tty = false,
	platform = "linux",
	network_mode = "shop_default",
	privileged = false,
	memory_limit = 536870912,
	cpu_limit = 1.5,
	ports = { { public = 3000, private = 3000, type = "tcp", ip = "0.0.0.0" }, { private = 9229, type = "tcp" } },
	networks = { { name = "shop_default", ip = "172.18.0.7", gateway = "172.18.0.1", mac = "", aliases = { "api" } } },
	mounts = { { type = "volume", name = "shop_api-data", source = "/x", destination = "/data", rw = true } },
	healthcheck = { "CMD", "wget", "-q" },
	lines = {
		"[",
		"    {",
		'        "Id": "aaaa",',
		'        "State": {',
		'            "Running": true',
		"        }",
		"    }",
		"]",
	},
}

-- A batch of `count` lines of a log, numbered from `first`, as the program pushes them.
function M.log_batch(first, count)
	local texts, clocks, streams = {}, {}, {}
	for n = first, first + count - 1 do
		local level = n % 97 == 0 and "\27[31mERROR\27[0m" or "\27[32mINFO\27[0m "
		texts[#texts + 1] = level .. " GET /api/orders/" .. n .. " 200"
		clocks[#clocks + 1] = string.format("14:%02d:%02d.000", (n // 60) % 60, n % 60)
		streams[#streams + 1] = n % 97 == 0 and "e" or "o"
	end
	return { texts = texts, clocks = clocks, streams = table.concat(streams), last = "2026-10-25T10:00:00Z" }
end

return M
