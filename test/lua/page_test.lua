-- The page, run against the kit's page API: what it asks of its program, what it shows of what it
-- is told, what its keys and clicks do. Nothing is laid out here (that is the terminal's), so what is
-- looked at is the tree the page hands out and the messages it says; how it looks is not tested.

local pencere = require("pencere")
local t = require("t")
local kit = require("kit")
local data = require("data")

local PRELUDE = pencere.env.get("PENCERE_PRELUDE")
local PAGE = pencere.env.get("DOCKERPEN_PAGE")

-- The page, started, booted by a program that says `boot` and lists the shop's containers.
local function opened(options)
	options = options or {}
	local k = kit.start(PRELUDE, PAGE)
	k:render(options.width or 1300, options.height or 760, 100)
	k:answer("boot", options.boot or data.boot)
	k:render(options.width or 1300, options.height or 760, 100.5)
	k:push("containers", { containers = options.containers or data.shop(), engine = data.engine })
	k:render(options.width or 1300, options.height or 760, 101)
	return k
end

local function page_texts(k)
	return kit.texts(k.root)
end

-- The texts of a page as one run of words, for a sentence the page wraps into several lines.
local function words(texts)
	return { table.concat(texts, " ") }
end

t.test("the page asks its program what it is, then listens to what changes", function()
	local k = kit.start(PRELUDE, PAGE)
	k:render(1300, 760, 100)
	t.eq(#k:calls_of("boot"), 1)
	k:answer("boot", data.boot)
	k:render(1300, 760, 100.5)
	for _, topic in ipairs({ "containers", "events", "jobs", "stats" }) do
		t.ok(k:subscribed(topic), "listens to " .. topic)
	end
	t.ok(not k:subscribed("logs"), "no log is read until one is on show")
end)

t.test("containers are listed by project, with their state in words and not in colour alone", function()
	local k = opened()
	local texts = page_texts(k)
	for _, word in ipairs({
		"shop",
		"api",
		"starting",
		"unhealthy",
		"exited 1",
		"up 3m",
		"2m ago",
		"Standalone",
		"toolbox",
		"up 1h",
	}) do
		t.has(texts, word)
	end
	t.has(
		texts,
		"4/5 up · 2 with issues",
		"a project says how many of its containers are up, and how many are in trouble"
	)
	t.lacks(texts, "site", "a project that does not run is folded away on the first start")
	t.has(texts, "blog")
	t.lacks(texts, "shop-api-1", "a container of a project goes by its service")
end)

t.test("the filters count what they show", function()
	local k = opened()
	local texts = page_texts(k)
	t.has(texts, "Issues")
	t.has(texts, "5 running · 7 total")
	k:key("f")
	k:render(1300, 760, 102)
	texts = page_texts(k)
	t.has(texts, "api")
	t.lacks(texts, "mailer", "the filter after All is Running")
	k:key("f")
	k:key("f")
	k:render(1300, 760, 103)
	texts = page_texts(k)
	t.has(texts, "mailer", "Issues shows what exited with a failure")
	t.has(texts, "search", "and what is unhealthy")
	t.lacks(texts, "web")
end)

t.test("a stopped project is opened by its row", function()
	local k = opened()
	t.lacks(page_texts(k), "site")
	k:click("row:group:blog")
	k:render(1300, 760, 102)
	t.has(page_texts(k), "site")
end)

t.test("the text of the host's field filters the list, by name, image and port", function()
	local k = opened()
	k:text("web")
	k:render(1300, 760, 102)
	local texts = page_texts(k)
	t.has(texts, "web")
	t.lacks(texts, "api")
	k:text("3000")
	k:render(1300, 760, 103)
	texts = page_texts(k)
	t.has(texts, "api", "a published port is found")
	t.lacks(texts, "web")
	k:text("nothing of the kind")
	k:render(1300, 760, 104)
	t.has(page_texts(k), "No container matches “nothing of the kind”")
end)

t.test("the keys move the cursor and a container's detail opens beside the list", function()
	local k = opened()
	k:key("down")
	k:key("enter")
	k:render(1300, 760, 102)
	local texts = page_texts(k)
	t.has(texts, "Overview")
	t.has(texts, "Environment")
	t.has(texts, "Restart")
	t.eq(#k:calls_of("detail"), 1, "the container is asked about once")
	t.eq(k:last_call("detail").params.id, data.id("a"))
	t.has(texts, "shop-api-1", "its name heads the detail")
	t.has(texts, "toolbox", "the list is still there beside it")
	k:answer("detail", data.detail)
	k:render(1300, 760, 102.5)
	texts = page_texts(k)
	t.has(texts, "node:22-alpine")
	t.has(texts, "on-failure:3")
	t.has(texts, "not published · ", "a port that is exposed and not published")
	t.has(texts, "9229/tcp", "a port that is exposed and not published")
	k:key("escape")
	k:render(1300, 760, 103)
	t.lacks(page_texts(k), "Overview", "Esc closes the detail")
end)

t.test("in a narrow pane the detail takes the place of the list, and the rail is a strip", function()
	local k = opened({ width = 600, height = 380 })
	t.has(page_texts(k), "Containers")
	k:key("down")
	k:key("enter")
	k:render(600, 380, 102)
	local texts = page_texts(k)
	t.has(texts, "Overview")
	t.lacks(texts, "Standalone", "the list is not drawn under it")
	k:key("escape")
	k:render(600, 380, 103)
	t.has(page_texts(k), "Standalone", "Esc goes back to the list")
end)

t.test("s stops what runs and starts what does not, with one call, and the row says it is busy", function()
	local k = opened()
	k:key("down")
	k:key("s")
	local call = k:last_call("act")
	t.eq(call.params, { ids = { data.id("a") }, action = "stop" })
	k:render(1300, 760, 102)
	t.has(page_texts(k), "stopping…")
	k:answer("act", { outcomes = { { id = data.id("a"), name = "shop-api-1", ok = true } } })
	k:render(1300, 760, 103)
	t.has(page_texts(k), "Stopped shop-api-1")
	t.has(page_texts(k), "Start again", "a stop can be taken back")
	k:click("toast.action:1")
	t.eq(k:last_call("act").params, { ids = { data.id("a") }, action = "start" })
	-- The same from the keyboard.
	local again = opened()
	again:key("down")
	again:key("s")
	again:answer("act", { outcomes = { { id = data.id("a"), name = "shop-api-1", ok = true } } })
	again:key("z")
	t.eq(again:last_call("act").params, { ids = { data.id("a") }, action = "start" })
end)

t.test("what is marked is acted on together", function()
	local k = opened()
	k:key("down")
	k:key("space")
	k:key("down")
	k:key("space")
	k:key("r")
	t.eq(k:last_call("act").params, { ids = { data.id("a"), data.id("c") }, action = "restart" })
	k:render(1300, 760, 102)
	t.has(page_texts(k), "restarting…")
end)

t.test("a row's own verb acts on that row only", function()
	local k = opened()
	k:key("down")
	k:key("space")
	k:click("verb:" .. data.id("b"))
	t.eq(k:last_call("act").params, { ids = { data.id("b") }, action = "stop" })
end)

t.test("a project's row stands for all of its containers", function()
	local k = opened()
	k:key("s")
	local call = k:last_call("act")
	t.eq(call.params.action, "stop", "something of it runs, so it is stopped")
	t.eq(#call.params.ids, 4, "the four that run, the stopped one is left")
	k:click("verb:group:shop")
	t.eq(#k:last_call("act").params.ids, 4)
end)

t.test("removing asks first, and says what goes with it", function()
	local k = opened()
	k:key("down")
	k:key("d")
	k:render(1300, 760, 102)
	local texts = page_texts(k)
	t.has(texts, "Remove shop-api-1?")
	t.has(texts, "Also remove anonymous volumes", "and what goes with it can be chosen")
	t.has(texts, "Cancel")
	t.eq(#k:calls_of("act"), 0, "nothing was asked of docker")
	k:key("n")
	k:render(1300, 760, 103)
	t.lacks(page_texts(k), "Remove shop-api-1?")
	t.eq(#k:calls_of("act"), 0, "no answers it")
	k:key("d")
	k:key("enter")
	t.eq(k:last_call("act").params, { ids = { data.id("a") }, action = "remove", force = true })
end)

t.test("kill asks first too, and only for what runs", function()
	local k = opened()
	k:key("down")
	k:key("down")
	k:key("down")
	k:key("down")
	k:key("down")
	k:key("space")
	k:key("K")
	k:render(1300, 760, 102)
	t.has(page_texts(k), "Kill shop-web-1?")
	t.eq(#k:calls_of("act"), 0)
end)

t.test("the pane goes to a shell only for a container that runs", function()
	local k = opened()
	k:key("down")
	k:key("e")
	t.eq(k:last_call("handoff").params, { kind = "shell", id = data.id("a"), name = "shop-api-1" })
	k:key("F")
	t.eq(k:last_call("handoff").params, { kind = "logs", id = data.id("a"), name = "shop-api-1" })
	local before = #k:calls_of("handoff")
	k:click("row:group:blog")
	k:key("down")
	k:key("e")
	k:render(1300, 760, 102)
	t.eq(#k:calls_of("handoff"), before, "a container that is not running is not asked for a shell")
end)

t.test("a terminal that cannot hand its pane over is told so and not asked", function()
	local k = opened({ boot = { version = "0.2.1", time = 1, hostname = "mac", remote = false, handoff = false } })
	k:key("down")
	k:key("e")
	t.eq(#k:calls_of("handoff"), 0)
	k:render(1300, 760, 102)
	t.has(page_texts(k), "No terminal to hand over")
end)

t.test("docker that is not there is said, with what to do", function()
	local k = kit.start(PRELUDE, PAGE)
	k:render(1300, 760, 100)
	k:answer("boot", data.boot)
	k:render(1300, 760, 100.5)
	k:push(
		"containers",
		{ containers = {}, failure = { code = "docker-missing", message = "There is no docker command on the PATH." } }
	)
	k:render(1300, 760, 101)
	local texts = page_texts(k)
	t.has(texts, "There is no docker command")
	t.has(words(texts), "dockerpen runs the docker command. Install Docker, or put docker on the PATH.")
	k:push(
		"containers",
		{ containers = {}, failure = { code = "engine-down", message = "Cannot connect to the Docker daemon" } }
	)
	k:render(1300, 760, 102)
	texts = page_texts(k)
	t.has(texts, "Docker is not reachable")
	t.has(words(texts), "Start Docker (or OrbStack, Colima, Podman…) and dockerpen carries on by itself.")
end)

t.test("a list that was there stays when docker goes away, with the reason over it", function()
	local k = opened()
	k:push("containers", { containers = data.shop(), failure = { code = "engine-down", message = "gone" } })
	k:render(1300, 760, 102)
	local texts = page_texts(k)
	t.has(texts, "api")
	t.has(texts, "Docker is not reachable: gone — this is the list as it was.")
end)

t.test("what the engine reports that is news is told as a toast, wherever the person is", function()
	local k = opened()
	k:key("2")
	k:push("events", {
		items = {
			{ seq = 1, type = "container", action = "start", id = data.id("a"), name = "shop-api-1", words = "start" },
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
	k:render(1300, 760, 102)
	local texts = page_texts(k)
	t.has(words(texts), "shop-mailer-1 exited with code 1")
	t.lacks(texts, "shop-api-1 start", "a start is not news")
	k:render(1300, 760, 120)
	t.lacks(words(page_texts(k)), "shop-mailer-1 exited with code 1", "a toast goes after a while")
	k:key("6")
	k:render(1300, 760, 121)
	t.has(page_texts(k), "shop-mailer-1 stopped with exit 1", "and Activity keeps what happened")
end)

t.test("the readings are listened to only while the containers are on show", function()
	local k = opened()
	t.ok(k:subscribed("stats"))
	k:key("2")
	t.ok(not k:subscribed("stats"), "not on the images")
	k:key("1")
	t.ok(k:subscribed("stats"), "and again on the containers")
end)

t.test("a running container shows what it uses", function()
	local k = opened()
	k:push("stats", {
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
	})
	k:render(1300, 760, 102)
	t.has(page_texts(k), "12.5%")
	t.has(page_texts(k), "48.2MiB")
	k:key("down")
	k:key("enter")
	k:render(1300, 760, 103)
	k:answer("detail", data.detail)
	k:render(1300, 760, 103.5)
	local texts = page_texts(k)
	t.has(texts, "of 512 MiB")
	t.has(texts, "↓ 1.5 KB/s")
	t.has(texts, "11", "the processes it runs")
end)

-- ---- the log -------------------------------------------------------------------------------------

local function with_log(lines)
	local k = opened()
	k:key("down")
	k:key("enter")
	k:render(1300, 760, 102)
	k:key("l")
	k:render(1300, 760, 103)
	-- Long enough on the clock for the container to have been looked at.
	k:render(1300, 760, 104)
	local sub = k:calls_of("detail")
	assert(#sub == 1)
	k:render(1300, 760, 105)
	for first = 1, lines, 500 do
		k:push("logs", data.log_batch(first, math.min(500, lines - first + 1)))
	end
	k:render(1300, 760, 106)
	return k
end

t.test("the log is asked for when the tab is open and not before", function()
	local k = opened()
	k:key("down")
	k:key("enter")
	k:render(1300, 760, 102)
	t.ok(not k:subscribed("logs"))
	k:key("l")
	k:render(1300, 760, 103)
	t.ok(k:subscribed("logs"))
	local sub
	for _, message in ipairs(k:all_told()) do
		if message.subscribe and message.subscribe.topic == "logs" then
			sub = message.subscribe
		end
	end
	t.eq(sub.params, { id = data.id("a"), tail = 10000 })
	k:key("[")
	k:render(1300, 760, 104)
	t.ok(not k:subscribed("logs"), "and given up when it is closed")
end)

t.test("a log of fifty thousand lines is a window of elements, with the end of it on show", function()
	local k = with_log(50000)
	local texts = page_texts(k)
	local last = "GET /api/orders/50000 200"
	local found = false
	for _, text in ipairs(texts) do
		if string.find(text, last, 1, true) then
			found = true
		end
	end
	t.ok(found, "the last line is on show while it follows")
	t.ok(kit.count(k.root) < 700, "the page is a few hundred elements, not fifty thousand: " .. kit.count(k.root))
	t.lacks(texts, "GET /api/orders/100 200", "the first lines are not made")
end)

t.test("scrolling up stops following, and the lines that come are counted", function()
	local k = with_log(2000)
	-- The terminal knows how far the log reaches; the page is told by what it asks of the layout.
	k.extents.log = { content = 34000, view = 560 }
	k.hit_id = "log"
	k:event({ type = "scroll", x = 900, y = 300, dy = -400 })
	k.hit_id = nil
	k:push("logs", data.log_batch(2001, 30))
	k:render(1300, 760, 107)
	t.has(page_texts(k), "30 new lines")
	k:key("end")
	k:render(1300, 760, 108)
	t.lacks(page_texts(k), "30 new lines")
end)

t.test("the log is searched through the host's field, and n goes to the next match", function()
	local k = with_log(1000)
	k:render(1300, 760, 107)
	k:text("ERROR")
	for step = 1, 6 do
		k:render(1300, 760, 107 + step)
	end
	t.has(page_texts(k), "10/10", "the search begins at the latest match")
	k:key("n")
	k:render(1300, 760, 115)
	t.has(page_texts(k), "1/10", "n goes on, and round")
	k:key("N")
	k:key("N")
	k:render(1300, 760, 116)
	t.has(page_texts(k), "9/10")
end)

t.test("a log is read to the right, a few characters at a time", function()
	local k = with_log(20)
	local function first_words()
		for _, text in ipairs(page_texts(k)) do
			if string.find(text, "/20 200", 1, true) then
				return text
			end
		end
		return ""
	end
	k:key("w")
	k:render(1300, 760, 106.5)
	t.eq(first_words(), "  GET /api/orders/20 200")
	k:key("right", { shift = true })
	k:render(1300, 760, 107)
	t.eq(first_words(), "rders/20 200", "sixteen characters, across the two runs the line is in")
	k:key("0")
	k:render(1300, 760, 108)
	t.eq(first_words(), "  GET /api/orders/20 200")
end)

t.test("timestamps are shown when asked for", function()
	local k = with_log(100)
	t.lacks(page_texts(k), "14:01:30.000")
	k:key("t")
	k:render(1300, 760, 107)
	t.has(page_texts(k), "14:01:30.000")
end)

t.test("a log that ended says so, and a container that is back goes on from its last line", function()
	local k = with_log(10)
	k:push("logs", { ended = { code = 0, message = "" } })
	k:push("containers", {
		containers = (function()
			local list = data.shop()
			list[1].state, list[1].status = "exited", "Exited (0) 1 second ago"
			return list
		end)(),
		engine = data.engine,
	})
	k:render(1300, 760, 107)
	t.has(page_texts(k), "It is not running: the log does not go on.")
	k:push("containers", { containers = data.shop(), engine = data.engine })
	k:render(1300, 760, 112)
	local last
	for _, message in ipairs(k:all_told()) do
		if message.subscribe and message.subscribe.topic == "logs" then
			last = message.subscribe
		end
	end
	t.ok(last.params.since ~= nil, "the log is followed again from where it was")
	t.eq(last.params.tail, nil)
end)

-- ---- the other tabs ------------------------------------------------------------------------------------

t.test("the environment hides what looks secret until it is asked for", function()
	local k = opened()
	k:key("down")
	k:key("enter")
	k:render(1300, 760, 102)
	k:answer("detail", data.detail)
	k:key("]")
	k:key("]")
	k:render(1300, 760, 103)
	local texts = page_texts(k)
	t.has(texts, "PORT")
	t.has(texts, "3000")
	t.lacks(texts, "hunter2")
	t.has(texts, "Reveal")
	k:key("v")
	k:render(1300, 760, 104)
	-- The value wraps in its column, as it did; its first line holds the password.
	t.has(page_texts(k), "postgres://shop:hunter2@")
end)

t.test("the processes are asked for while they are looked at, and again after a while", function()
	local k = opened()
	k:key("down")
	k:key("enter")
	k:render(1300, 760, 102)
	k:key("]")
	k:key("]")
	k:key("]")
	k:render(1300, 760, 103)
	t.eq(#k:calls_of("processes"), 1)
	k:answer(
		"processes",
		{ titles = { "PID", "USER", "TIME", "COMMAND" }, rows = { { "42", "node", "0:01", "node server.js" } } }
	)
	k:render(1300, 760, 104)
	t.has(page_texts(k), "node server.js")
	t.eq(#k:calls_of("processes"), 1, "not again at once")
	k:render(1300, 760, 106)
	t.eq(#k:calls_of("processes"), 2, "and again after two seconds")
end)

t.test("a container with thousands of processes and a variable of a megabyte stays a page the kit takes", function()
	local k = opened()
	k:key("down")
	k:key("enter")
	k:render(1300, 760, 102)
	local detail = {}
	for key, value in pairs(data.detail) do
		detail[key] = value
	end
	detail.env = { { key = "BIG", value = string.rep("x", 1000000) } }
	for n = 1, 600 do
		detail.env[#detail.env + 1] = { key = "V" .. n, value = "v" }
	end
	k:answer("detail", detail)
	k:key("]")
	k:key("]")
	k:render(1300, 760, 103)
	t.ok(kit.count(k.root) < 20000, "elements: " .. kit.count(k.root))
	for _, text in ipairs(page_texts(k)) do
		t.ok(#text < 65536, "a line of text is cut: " .. #text)
	end
	t.has(page_texts(k), "and 101 more", "the variables that do not fit are counted")
	k:key("]")
	k:render(1300, 760, 104)
	local rows = {}
	for n = 1, 5000 do
		rows[n] = { tostring(n), "root", "0:00", "sleep " .. n }
	end
	k:answer("processes", { titles = { "PID", "USER", "TIME", "COMMAND" }, rows = rows })
	k:render(1300, 760, 105)
	t.ok(kit.count(k.root) < 20000, "elements: " .. kit.count(k.root))
	t.has(page_texts(k), "and 4700 more")
end)

t.test("inspect is the engine's answer, a line at a time", function()
	local k = opened()
	k:key("down")
	k:key("enter")
	k:render(1300, 760, 102)
	k:answer("detail", data.detail)
	k:key("i")
	k:render(1300, 760, 103)
	local texts = page_texts(k)
	t.has(texts, '        "Id"')
	t.has(texts, ": ")
end)

t.test("why a container stopped, in words", function()
	local k = opened()
	k:key("down")
	k:key("down")
	k:key("down")
	k:key("enter")
	k:render(1300, 760, 102)
	local stopped = {}
	for key, value in pairs(data.detail) do
		stopped[key] = value
	end
	stopped.state = {
		status = "exited",
		running = false,
		oom_killed = true,
		exit_code = 137,
		error = "",
		finished_at = 1792925790,
	}
	k:answer("detail", stopped)
	k:render(1300, 760, 103)
	local texts = page_texts(k)
	t.has(texts, "Killed for running out of memory")
end)

-- ---- images, volumes, networks, the disk ------------------------------------------------------------

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

t.test("the lists of images, volumes and networks are asked for when they come on show", function()
	local k = opened()
	t.eq(#k:calls_of("images"), 0)
	k:key("2")
	t.eq(#k:calls_of("images"), 1)
	k:answer("images", { images = IMAGES })
	k:render(1300, 760, 102)
	local texts = page_texts(k)
	t.has(texts, "node:22-alpine")
	t.has(texts, "+1", "a second tag")
	t.has(texts, "dangling")
	t.has(texts, "180 MB")
	t.has(texts, "shop-api-1")
	t.has(texts, "3 images · 1.3 GB")
	k:key("3")
	t.eq(#k:calls_of("volumes"), 1)
	k:key("4")
	t.eq(#k:calls_of("networks"), 1)
	k:key("2")
	t.eq(#k:calls_of("images"), 1, "a list that was asked for is not asked for again")
end)

t.test("a list the program could not make says why", function()
	local k = opened()
	k:key("2")
	k:fail("images", "docker-failed", "something is wrong in here")
	k:render(1300, 760, 102)
	t.has(page_texts(k), "something is wrong in here")
end)

t.test("images are removed after a question, and the list is looked at again", function()
	local k = opened()
	k:key("2")
	k:answer("images", { images = IMAGES })
	k:render(1300, 760, 102)
	k:key("space")
	k:key("d")
	k:render(1300, 760, 103)
	t.has(page_texts(k), "Force, although containers use it", "an image a container uses needs force")
	t.eq(#k:calls_of("image_remove"), 0)
	k:key("y")
	t.eq(k:last_call("image_remove").params, { ids = { "999999999999" }, force = true })
	k:answer("image_remove", { outcomes = { { id = "999999999999", name = "x", ok = true } } })
	k:render(1300, 760, 104)
	k:render(1300, 760, 105)
	t.eq(#k:calls_of("images"), 2, "the list is asked for again")
end)

t.test("the layers of an image are opened under its row", function()
	local k = opened()
	k:key("2")
	k:answer("images", { images = IMAGES })
	k:render(1300, 760, 102)
	k:key("enter")
	k:render(1300, 760, 103)
	t.eq(k:last_call("image_layers").params, { id = "999999999999" })
	k:answer(
		"image_layers",
		{ layers = { { id = "", created_by = "RUN apk add curl", size = 91700000, comment = "" } } }
	)
	k:render(1300, 760, 104)
	t.has(page_texts(k), "RUN apk add curl")
	t.has(page_texts(k), "91.7 MB")
	t.has(page_texts(k), "nginx:alpine", "the other images stay on show, under it")
	t.has(page_texts(k), "shop-api-1", "and the containers made from it are a click away")
	k:key("escape")
	k:render(1300, 760, 105)
	t.lacks(page_texts(k), "RUN apk add curl")
end)

t.test("a volume's size is counted apart from its list", function()
	local k = opened()
	k:key("3")
	k:answer("volumes", {
		sized = false,
		volumes = {
			{
				name = "shop_db-data",
				driver = "local",
				project = "shop",
				anonymous = false,
				containers = { "shop-db-1" },
			},
		},
	})
	k:render(1300, 760, 102)
	t.has(page_texts(k), "counting…")
	t.eq(#k:calls_of("volume_sizes"), 1)
	k:answer("volume_sizes", { sizes = { ["shop_db-data"] = 236000000 } })
	k:render(1300, 760, 103)
	t.has(page_texts(k), "236 MB")
end)

t.test("networks that are Docker's own cannot be removed", function()
	local k = opened()
	k:key("4")
	k:answer("networks", {
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
	})
	k:render(1300, 760, 102)
	t.has(page_texts(k), "built-in")
	k:key("down")
	k:key("d")
	k:render(1300, 760, 103)
	t.has(page_texts(k), "Nothing to remove")
	t.has(words(page_texts(k)), "Built-in networks and networks with running containers stay.")
	t.eq(#k:calls_of("network_remove"), 0)
end)

local USAGE = {
	images = { count = 5, active = 4, size = 1100000000, reclaimable = 124000000 },
	containers = { count = 7, active = 6, size = 16400, reclaimable = 4100 },
	volumes = { count = 2, active = 1, size = 237000000, reclaimable = 189000000 },
	build_cache = { count = 0, active = 0, size = 0, reclaimable = 0 },
}

t.test("the system says what the disk holds, and a clean-up says what it will free before it frees it", function()
	local k = opened()
	k:key("5")
	k:answer("system", { usage = USAGE, engine = data.engine })
	k:render(1300, 760, 102)
	local texts = page_texts(k)
	t.has(texts, "1.3 GB")
	t.has(texts, "313 MB")
	t.has(texts, "can be freed")
	t.has(texts, "124 MB unused")
	t.has(texts, "nothing unused")
	k:key("c")
	k:render(1300, 760, 103)
	texts = page_texts(k)
	t.has(texts, "Clean up")
	t.has(texts, "Stopped containers")
	t.has(texts, "Unused images")
	t.has(texts, "Unused volumes")
	t.has(texts, "189 MB", "each says what it holds")
	t.has(texts, "4.1 KB", "and what is ticked says what it frees")
	t.eq(#k:calls_of("prune"), 0)
	k:key("y")
	t.eq(
		k:last_call("prune").params,
		{ targets = { "containers", "dangling_images", "networks", "build_cache" } },
		"what is ticked at first is what costs nothing that cannot be had again"
	)
end)

t.test("one kind of clean-up from its own card", function()
	local k = opened()
	k:key("5")
	k:answer("system", { usage = USAGE, engine = data.engine })
	k:render(1300, 760, 102)
	k:click("free:volumes")
	k:render(1300, 760, 103)
	t.has(page_texts(k), "Unused volumes")
	t.has(page_texts(k), "189 MB")
	k:key("y")
	t.eq(k:last_call("prune").params, { targets = { "volumes" } })
end)

t.test("pulling an image asks for its name in the host's field, then pulls it", function()
	local k = opened()
	k:click("act:pull")
	k:render(1300, 760, 102)
	t.has(page_texts(k), "Pull an image")
	k:text("redis")
	k:key("enter")
	t.eq(k:last_call("pull").params, { reference = "redis" })
end)

t.test("a job that runs is shown with how far it has come, and its end is told", function()
	local k = opened()
	k:push("jobs", {
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
	k:render(1300, 760, 102)
	t.has(page_texts(k), "1 running")
	k:click("jobs")
	k:render(1300, 760, 102.5)
	t.has(page_texts(k), "Pull redis")
	t.has(page_texts(k), "abc: Pull complete")
	k:click("jobs:backdrop")
	k:push(
		"jobs",
		{ jobs = { { id = "job1", kind = "pull", title = "Pull redis", state = "done", progress = 1, detail = "" } } }
	)
	k:render(1300, 760, 103)
	t.has(page_texts(k), "Pull redis")
	t.has(page_texts(k), "1 done")
end)

-- ---- the page keeps itself ------------------------------------------------------------------------------------

t.test("where the person is is kept in the program, and found again", function()
	local k = opened()
	k:key("down")
	k:key("enter")
	k:key("l")
	local kept
	for _, message in ipairs(k:all_told()) do
		if message.call and message.call.method == "ui" then
			kept = message.call.params.ui
		end
	end
	t.eq(kept.section, "containers")
	t.eq(kept.detail, data.id("a"))
	t.eq(kept.tab, "logs")
	local again = opened({
		boot = {
			version = "0.2.1",
			time = 1792925800,
			hostname = "mac",
			handoff = true,
			ui = kept,
		},
	})
	again:render(1300, 760, 103)
	t.has(page_texts(again), "follow", "the detail is open on its logs, as it was left")
end)

t.test("a name on the command line finds its container, by name, service or the start of its id", function()
	local k = opened({ boot = { version = "0.2.1", time = 1, hostname = "mac", handoff = true, focus = "web" } })
	k:render(1300, 760, 102)
	t.has(page_texts(k), "Overview")
	t.eq(k:last_call("detail").params.id, data.id("b"))
	local missing =
		opened({ boot = { version = "0.2.1", time = 1, hostname = "mac", handoff = true, focus = "nothing" } })
	missing:render(1300, 760, 102)
	t.has(page_texts(missing), "There is no container nothing")
end)

t.test("what came back from a shell is told", function()
	local k = opened({
		boot = {
			version = "0.2.1",
			time = 1,
			hostname = "mac",
			handoff = true,
			returned = { kind = "shell", name = "shop-api-1", status = 0, duration = 12000 },
		},
	})
	t.has(words(page_texts(k)), "The shell in shop-api-1 ended after 12s")
end)

t.test("everything has a key: the help lists them, and ? opens it", function()
	local k = opened()
	k:key("?")
	k:render(1300, 760, 102)
	local texts = page_texts(k)
	t.has(texts, "Keyboard shortcuts")
	t.has(texts, "Start or stop")
	t.has(texts, "Shell in the terminal")
	k:key("escape")
	k:render(1300, 760, 103)
	t.lacks(page_texts(k), "Keyboard shortcuts")
end)

t.test("the page does not outgrow what a page may be: a few hundred elements with many containers", function()
	local many = {}
	for n = 1, 3000 do
		many[#many + 1] =
			data.container("a", "box-" .. n, { id = string.rep("a", 60) .. string.format("%04d", n), short = "x" .. n })
	end
	local k = opened({ containers = many })
	k:render(1300, 760, 102)
	t.ok(kit.count(k.root) < 1500, "elements: " .. kit.count(k.root))
	t.has(page_texts(k), "3000 total")
end)
