-- What an agent reads of dockerpen's page in a few states, set against goldens (test/reading/goldens/<state>.txt),
-- and the reading audit of each (a control with no name, an item said twice, a modal's page read behind it).
-- The page is opened under the host with no screen (pencere-test), with a stand-in for the program that
-- answers the page's calls as the page tests' own does. `make test-reading` runs it; PENCERE_BLESS=1 writes
-- the goldens (read the diff: it is how an agent reads the page).

local pencere = require("pencere")
local test = require("pencere.test")
local data = require("lua.data")

-- Where the goldens are (an absolute path, given by the Makefile), and whether this run writes them.
local GOLDENS = pencere.env.get("READING_GOLDENS")
assert(GOLDENS and GOLDENS ~= "", "READING_GOLDENS names the directory of the goldens: make test-reading")
local BLESS = (pencere.env.get("PENCERE_BLESS") or "") ~= ""

local expect = test.expect

-- The reading of the main screen, kept to see that a state is not the main screen again (a key that did not
-- route would keep a copy of it): `marker` is a word the state must say.
local MAIN

local function save(name, page, marker)
	if marker then
		expect(page):to_say(marker)
	end
	local text = page.raw:reading()
	if name == "main" then
		MAIN = text
	else
		assert(text ~= MAIN, name .. ": the reading is the main screen's")
	end
	text = text .. (string.sub(text, -1) == "\n" and "" or "\n")
	local file = GOLDENS .. "/" .. name .. ".txt"
	if BLESS then
		pencere.fs.write(file, text)
	else
		local ok, golden = pcall(pencere.fs.read, file)
		assert(ok, name .. ": no golden at " .. file .. ": PENCERE_BLESS=1")
		assert(
			golden == text,
			name .. ": the page is read otherwise than the golden says: PENCERE_BLESS=1 writes it\n" .. text
		)
	end
	local flaws = page.raw:audit()
	assert(#flaws == 0, name .. ": the reading audit finds:\n" .. table.concat(flaws, "\n"))
end

local IMAGES = {
	{
		id = "999999999999",
		tags = { "node:22-alpine", "node:lts" },
		size = 180000000,
		created = 1792000000,
		dangling = false,
		containers = { "shop-api-1" },
		running = 1,
	},
	{
		id = "888888888888",
		tags = { "nginx:alpine" },
		size = 52500000,
		created = 1790000000,
		dangling = false,
		containers = {},
		running = 0,
	},
	{
		id = "777777777777",
		tags = {},
		size = 1060000000,
		created = 1780000000,
		dangling = true,
		containers = {},
		running = 0,
	},
}

local VOLUMES = {
	sized = true,
	volumes = {
		{
			name = "shop_db-data",
			driver = "local",
			project = "shop",
			anonymous = false,
			containers = { "shop-db-1" },
			size = 236000000,
		},
	},
}

local NETWORKS = {
	networks = {
		{
			id = "aaaaaaaaaaaa",
			name = "bridge",
			driver = "bridge",
			subnets = { "172.17.0.0/16" },
			containers = {},
			builtin = true,
		},
		{
			id = "bbbbbbbbbbbb",
			name = "shop_default",
			driver = "bridge",
			subnets = { "172.18.0.0/16" },
			containers = { "shop-api-1" },
			builtin = false,
			project = "shop",
		},
	},
}

local USAGE = {
	images = { count = 5, active = 4, size = 1100000000, reclaimable = 124000000 },
	containers = { count = 7, active = 6, size = 16400, reclaimable = 4100 },
	volumes = { count = 2, active = 1, size = 237000000, reclaimable = 189000000 },
	build_cache = { count = 0, active = 0, size = 0, reclaimable = 0 },
}

local STATS = {
	samples = {
		{
			id = string.rep("a", 12),
			name = "shop-api-1",
			cpu = 12.5,
			memory = 50541363,
			memory_limit = 536870912,
			net_in = 1500,
			net_out = 2100,
			disk_read = 0,
			disk_write = 4096,
			pids = 11,
		},
	},
}

-- The page, opened on the shop's containers and rested.
local function open(options)
	options = options or {}
	local page = test.open({
		size = { options.width or 1300, options.height or 760 },
		fonts = "fixed",
		calls = {
			boot = data.boot,
			detail = data.detail,
			processes = function()
				return {
					titles = { "PID", "USER", "TIME", "COMMAND" },
					rows = { { "42", "node", "0:01", "node server.js" } },
				}
			end,
			images = { images = IMAGES },
			volumes = VOLUMES,
			networks = NETWORKS,
			system = { usage = USAGE, engine = data.engine },
			image_layers = { layers = { { id = "", created_by = "RUN apk add curl", size = 91700000, comment = "" } } },
			volume_sizes = { sizes = { ["shop_db-data"] = 236000000 } },
			ui = {},
			act = { outcomes = {} },
		},
	})
	page:advance(1)
	page:push("containers", { containers = data.shop(), engine = data.engine })
	page:push("stats", STATS)
	page:advance(1)
	page:settle()
	return page
end

local function rest(page)
	page:advance(1)
	page:settle()
end

test("main", function()
	save("main", open(), "toolbox")
end)

test("filter", function()
	local page = open()
	page:press("f")
	rest(page)
	expect(page).never:to_say("exited 1")
	save("filter", page)
end)

test("marked", function()
	local page = open()
	page:press("down")
	page:press("space")
	page:press("down")
	page:press("space")
	rest(page)
	save("marked", page)
end)

test("detail-overview", function()
	local page = open()
	page:press("down")
	page:press("enter")
	rest(page)
	save("detail-overview", page, "Overview")
end)

test("detail-logs", function()
	local page = open()
	page:press("down")
	page:press("enter")
	rest(page)
	page:press("l")
	rest(page)
	page:push("logs", data.log_batch(1, 60))
	rest(page)
	save("detail-logs", page, "GET /api/orders/34 200")
end)

test("remove-dialog", function()
	local page = open()
	page:press("down")
	page:press("d")
	rest(page)
	save("remove-dialog", page, "Remove shop-api-1?")
end)

test("palette", function()
	local page = open()
	page:press("ctrl+k")
	rest(page)
	save("palette", page, "Go to Images")
end)

test("help", function()
	local page = open()
	page:type("?")
	rest(page)
	save("help", page, "Keyboard shortcuts")
end)

test("images", function()
	local page = open()
	page:press("2")
	rest(page)
	page:press("space")
	page:press("enter")
	rest(page)
	save("images", page, "RUN apk add curl")
end)

test("system-clean", function()
	local page = open()
	page:press("5")
	rest(page)
	page:press("c")
	rest(page)
	save("system-clean", page, "Unused volumes")
end)

test("toast", function()
	local page = open()
	page:press("2")
	-- The rows of the list that was left are gone before the toast comes: they move out for a moment.
	rest(page)
	page:push("events", {
		items = {
			{
				seq = 2,
				type = "container",
				action = "die",
				id = data.id("e"),
				name = "shop-mailer-1",
				detail = { exitCode = "1" },
				words = "exited with code 1",
				notice = "died",
			},
		},
	})
	page:settle()
	page:advance(0.1)
	save("toast", page, "shop-mailer-1 exited with")
end)

test("narrow-detail", function()
	local page = open({ width = 600, height = 700 })
	page:press("down")
	page:press("enter")
	rest(page)
	save("narrow-detail", page, "Overview")
end)

test("jobs", function()
	local page = open()
	page:push("jobs", {
		jobs = {
			{
				id = "job1",
				kind = "pull",
				title = "Pull redis",
				state = "running",
				progress = 0.5,
				detail = "abc: Pull complete",
			},
		},
	})
	rest(page)
	page.raw:click_id("jobs")
	rest(page)
	save("jobs", page, "Pull redis")
end)

-- What a screen reader or an agent can do on an element, as the page's own keys and presses do it.
test("the palette's Close is done as escape is", function()
	local page = open()
	page:press("ctrl+k")
	rest(page)
	assert(
		string.find(page.raw:reading(), 'dialog "Command palette" [action "Close"]', 1, true),
		"the palette lists Close"
	)
	page.raw:command_on("palette:card", "dismiss")
	rest(page)
	assert(not string.find(page.raw:reading(), "Command palette", 1, true), "Close shuts the palette")
end)

test("a container's row lists its verbs, and one done on it is done for that container", function()
	local page = open()
	local reading = page.raw:reading()
	assert(
		string.find(reading, '[action "Stop", action "Restart", action "Logs"]', 1, true),
		"a running container's verbs"
	)
	page.raw:command_on("row:" .. data.id("a"), "restart")
	page:settle()
	local sent = page:last_call("act")
	assert(sent and sent.params.action == "restart", "the page asked the program to restart")
	assert(sent.params.ids[1] == data.id("a"), "and the container the row is of")
end)
