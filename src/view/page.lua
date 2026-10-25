-- dockerpen's page: Docker as an interface in the pane, in the colours and the font of the terminal
-- that shows it. It is a page of the kit's page API, which the terminal lays out and draws; every
-- colour below is a role of the theme (success, error, warning, accent, dim …), so it wears
-- whatever theme the terminal does.
--
-- The page is one script: the kit gives a page no `require`, and the runner packs `page.lua` and
-- the files of `assets/` into it. So it is long, and it is in parts, each a table or a group of
-- functions under a banner:
--
--   fmt, ansi      words for sizes, times and states; the colours a program writes into its log
--   S              what the page holds, and what it derives from it
--   net            what it asks its program (src/program/api) and what it is told back
--   parts          the small things a screen is made of: a button, a chip, a dot, a meter
--   screens        containers (with the detail of one), images, volumes, networks, system, activity
--   overlays       the question before something is removed, the help, the toasts, the menu
--   keys, mouse    what the person's keys and pointer do
--   the page       at the end: render, settle, handle, message
--
-- What it asks of its program, once: boot, the lists of images, volumes and networks, the disk of
-- the system, the detail of a container, its processes, the actions. What it listens to as it
-- changes: containers, events, jobs, and, only while the containers are on show, their resource
-- use, and, only while a container's logs are on show, those.

local b = pencere
local alpha = b.alpha
local ui = b.Ui.new()

-- ---- sizes, in points ----------------------------------------------------------------------

local SIZE = {
	row = 32, -- a row of a list, and the row that heads a compose project
	head = 52, -- the title of a screen
	bar = 40, -- the filter bar
	line = 17, -- a line of a log
	rail = 168, -- the rail of sections, where there is room for it
	detail = 460, -- the detail of a container, beside the list
	status = 26, -- the line of keys at the bottom
	body = 12.5, -- the size of the words of the page
	small = 11,
	tiny = 10,
}

-- The widths of the page at which it changes shape.
local RAIL_FROM = 700 -- the rail of sections is a rail from here, and a strip of them below it
local LIST_MEDIUM = 640
local LIST_WIDE = 860

local SECTIONS = {
	{ id = "containers", label = "Containers", key = "1" },
	{ id = "images", label = "Images", key = "2" },
	{ id = "volumes", label = "Volumes", key = "3" },
	{ id = "networks", label = "Networks", key = "4" },
	{ id = "system", label = "System", key = "5" },
	{ id = "activity", label = "Activity", key = "6" },
}

local TABS = {
	{ id = "overview", label = "Overview" },
	{ id = "logs", label = "Logs" },
	{ id = "env", label = "Environment" },
	{ id = "processes", label = "Processes" },
	{ id = "inspect", label = "Inspect" },
}

local FILTERS = {
	{ id = "all", label = "All" },
	{ id = "running", label = "Running" },
	{ id = "stopped", label = "Stopped" },
	{ id = "issues", label = "Issues" },
}

-- How many lines of a log are asked for at first, and the most (what the program allows).
local LOG_TAIL = 10000
local LOG_MOST = 100000
-- The most processes, environment variables and labels the detail draws: a page is held to 20 000
-- elements, and a container can have more of these than that.
local PROCESSES_MOST = 300
local ENV_MOST = 500
local LABELS_MOST = 200
-- How many samples of a resource a chart draws (the program keeps more).
local SPARK = 30

-- ---- words ---------------------------------------------------------------------------------

local fmt = {}

local BYTE_UNITS = { "B", "KiB", "MiB", "GiB", "TiB" }

-- A number of bytes: `936 KiB`, `1.2 GiB`.
function fmt.bytes(n)
	if n == nil then
		return "–"
	end
	local unit = 1
	while n >= 1024 and unit < #BYTE_UNITS do
		n /= 1024
		unit += 1
	end
	if unit == 1 then
		return string.format("%d B", n)
	end
	return string.format(n >= 100 and "%.0f %s" or (n >= 10 and "%.1f %s" or "%.2f %s"), n, BYTE_UNITS[unit])
end

-- A size as docker counts disk: decimal units, as `docker system df` writes them.
function fmt.disk(n)
	if n == nil then
		return "–"
	end
	local units = { "B", "kB", "MB", "GB", "TB" }
	local unit = 1
	while n >= 1000 and unit < #units do
		n /= 1000
		unit += 1
	end
	if unit == 1 then
		return string.format("%d B", n)
	end
	return string.format(n >= 100 and "%.0f %s" or (n >= 10 and "%.1f %s" or "%.2f %s"), n, units[unit])
end

function fmt.rate(n)
	return fmt.bytes(n) .. "/s"
end

function fmt.percent(n)
	if n == nil then
		return "–"
	end
	if n >= 100 then
		return string.format("%.0f%%", n)
	end
	return string.format("%.1f%%", n)
end

-- Seconds as the longest unit that fits: `45s`, `3m`, `2h`, `5d`.
function fmt.span(seconds)
	seconds = math.max(0, math.floor(seconds))
	if seconds < 60 then
		return seconds .. "s"
	elseif seconds < 3600 then
		return (seconds // 60) .. "m"
	elseif seconds < 86400 then
		return (seconds // 3600) .. "h"
	elseif seconds < 86400 * 14 then
		return (seconds // 86400) .. "d"
	elseif seconds < 86400 * 60 then
		return (seconds // (86400 * 7)) .. "w"
	end
	return (seconds // (86400 * 30)) .. "mo"
end

-- What docker says of how long (`Up 3 minutes`, `Exited (1) 2 hours ago`, `Up About an hour`) as
-- a few characters: `up 3m`, `2h ago`.
function fmt.status(status)
	local text = status or ""
	local up = string.find(text, "^Up") ~= nil
	local gone = string.find(text, "^Exited") ~= nil or string.find(text, "^Created") ~= nil
	text = string.gsub(text, "^Up ", "")
	text = string.gsub(text, "^Exited %(%-?%d+%) ", "")
	text = string.gsub(text, "^Created ", "")
	text = string.gsub(text, "%s*%(.*%)%s*$", "")
	text = string.gsub(text, "About an? ", "1 ")
	text = string.gsub(text, "Less than a second", "<1s")
	text = string.gsub(text, "an? ", "1 ")
	text = string.gsub(text, "(%d+) seconds?", "%1s")
	text = string.gsub(text, "(%d+) minutes?", "%1m")
	text = string.gsub(text, "(%d+) hours?", "%1h")
	text = string.gsub(text, "(%d+) days?", "%1d")
	text = string.gsub(text, "(%d+) weeks?", "%1w")
	text = string.gsub(text, "(%d+) months?", "%1mo")
	text = string.gsub(text, "(%d+) years?", "%1y")
	text = string.gsub(text, "^%s+", "")
	if up then
		return "up " .. text
	elseif gone and text ~= "" then
		return text
	end
	return string.lower(status or "")
end

-- A line of text cut to `n` characters, ending in an ellipsis where it was cut.
function fmt.cut(text, n)
	local length = utf8.len(text)
	if length == nil or length <= n then
		return text
	end
	return string.sub(text, 1, utf8.offset(text, n) - 1) .. "…"
end

-- Whether `text` has `needle` in it, ignoring case when `needle` has no capital.
function fmt.has(text, needle)
	if needle == "" then
		return true
	end
	if string.find(needle, "%u") then
		return string.find(text, needle, 1, true) ~= nil
	end
	return string.find(string.lower(text), needle, 1, true) ~= nil
end

-- A count and its noun: `1 container`, `3 containers`.
function fmt.count(n, noun)
	local plural = string.find(noun, "s$") and "es" or "s"
	return n .. " " .. noun .. (n == 1 and "" or plural)
end

-- ---- the colours a program writes into its log -----------------------------------------------

local ansi = {}

local ANSI_ROLES = {
	[0] = "black",
	"red",
	"green",
	"yellow",
	"blue",
	"magenta",
	"cyan",
	"white",
	"bright-black",
	"bright-red",
	"bright-green",
	"bright-yellow",
	"bright-blue",
	"bright-magenta",
	"bright-cyan",
	"bright-white",
}

-- The 256-colour cube folded onto the sixteen colours the theme has.
local function fold256(value)
	if value < 16 then
		return value
	end
	if value >= 232 then
		return value > 243 and 7 or 8
	end
	local v = value - 16
	local r, g, bl = v // 36, (v % 36) // 6, v % 6
	local bright = math.max(r, g, bl) > 3 and 8 or 0
	local index = (r > 2 and 1 or 0) + (g > 2 and 2 or 0) + (bl > 2 and 4 or 0)
	return index == 0 and (bright > 0 and 8 or 0) or index + bright
end

-- Whether a line has an escape in it.
function ansi.has(text)
	return string.find(text, "\27", 1, true) ~= nil
end

-- The text without what an escape says.
function ansi.strip(text)
	if not ansi.has(text) then
		return text
	end
	text = string.gsub(text, "\27%[[%d;?]*%a", "")
	text = string.gsub(text, "\27%][^\7\27]*[\7\27]\\?", "")
	return text
end

-- A line as runs of one style each: `{ text =, fg =, bold =, dim =, underline = }`. Everything an
-- escape can do besides colour and weight is dropped.
function ansi.runs(text)
	text = string.gsub(text, "\t", "    ")
	if not ansi.has(text) then
		return { { text = text } }
	end
	local runs = {}
	local style = {}
	local at = 1
	local function push(upto)
		if upto >= at then
			local piece = string.sub(text, at, upto)
			if piece ~= "" then
				runs[#runs + 1] = {
					text = piece,
					fg = style.fg,
					bold = style.bold,
					dim = style.dim,
					underline = style.underline,
				}
			end
		end
	end
	while true do
		local from, to, params, command = string.find(text, "\27%[([%d;?]*)(%a)", at)
		if from == nil then
			break
		end
		push(from - 1)
		at = to + 1
		if command == "m" then
			local codes = {}
			for number in string.gmatch(params, "%d+") do
				codes[#codes + 1] = tonumber(number)
			end
			if #codes == 0 then
				codes[1] = 0
			end
			local i = 1
			while i <= #codes do
				local code = codes[i]
				if code == 0 then
					style = {}
				elseif code == 1 then
					style.bold = true
				elseif code == 2 then
					style.dim = true
				elseif code == 4 then
					style.underline = true
				elseif code == 22 then
					style.bold, style.dim = nil, nil
				elseif code == 24 then
					style.underline = nil
				elseif code >= 30 and code <= 37 then
					style.fg = ANSI_ROLES[code - 30]
				elseif code >= 90 and code <= 97 then
					style.fg = ANSI_ROLES[code - 90 + 8]
				elseif code == 39 then
					style.fg = nil
				elseif (code == 38 or code == 48) and codes[i + 1] == 5 then
					if code == 38 then
						style.fg = ANSI_ROLES[fold256(codes[i + 2] or 0)]
					end
					i += 2
				elseif (code == 38 or code == 48) and codes[i + 1] == 2 then
					if code == 38 then
						style.fg =
							string.format("#%02x%02x%02x", codes[i + 2] or 0, codes[i + 3] or 0, codes[i + 4] or 0)
					end
					i += 4
				end
				i += 1
			end
		end
	end
	push(#text)
	if #runs == 0 then
		runs[1] = { text = "" }
	end
	return runs
end

-- The level a line of a log says in words, when it says one: what a program without colours tells.
function ansi.level(plain)
	local head = string.upper(string.sub(plain, 1, 48))
	if
		string.find(head, "%f[%w]ERROR%f[%W]")
		or string.find(head, "%f[%w]FATAL%f[%W]")
		or string.find(head, "%f[%w]PANIC%f[%W]")
	then
		return "error"
	elseif string.find(head, "%f[%w]WARN") then
		return "warning"
	elseif string.find(head, "%f[%w]DEBUG%f[%W]") or string.find(head, "%f[%w]TRACE%f[%W]") then
		return "dim"
	end
	return nil
end

-- ---- what the page holds ---------------------------------------------------------------------

local S = {
	ready = false,
	known = false, -- the program has told the containers once
	any_marked = false, -- something of the list on show is marked
	-- The time of the last frame, and what to add to it for seconds since 1970 (from `boot`).
	now = 0,
	clock = nil,
	width = 1000,
	height = 640,
	-- From the program.
	hostname = "",
	remote = false,
	handoff = false,
	engine = nil,
	failure = nil,
	containers = {},
	by_id = {},
	samples = {}, -- the last reading of each running container, by its short id
	series = {}, -- the last two minutes of each, by its short id: cpu, memory, net_in, net_out
	activity = {}, -- what the engine reported, newest first
	jobs = {},
	lists = {}, -- images, volumes, networks: as the program listed them, once it has
	problems = {}, -- a list the program could not make: its words
	loading = {},
	stale = {},
	volume_sizes = nil,
	system = nil,
	layers = {}, -- the layers of an image, by its id
	details = {}, -- what the program says of a container, by its id: { state =, data =, error = }
	processes = {}, -- the processes of the container whose detail is open
	busy = {}, -- containers with something being done to them: id -> the verb
	-- Where the person is.
	section = "containers",
	cursor = {}, -- by section: the id of the row the cursor is on
	marks = {}, -- by section: id -> true
	filter = "all",
	group = true,
	folded = {}, -- compose project -> true / false, as the person left it
	sort = "name",
	query = "", -- what the host's text field says
	open = nil, -- the container whose detail is open
	open_at = 0, -- when it was opened
	tab = "overview",
	focus = "list", -- where the keys go: the list, or the detail of the container
	reveal = false, -- the cursor's row is to be scrolled to
	revealed_env = {}, -- the environment variables whose value the person asked to see
	show_secrets = false,
	layer_open = nil, -- the image whose layers are shown
	-- Logs.
	log = {
		id = nil, -- the container the lines are of
		texts = {},
		streams = {}, -- 'o' or 'e' for each line, as a string
		clocks = {},
		count = 0,
		last = nil, -- the time docker gave the last line
		follow = true,
		timestamps = false,
		wrap = false,
		ended = nil, -- why the log stopped, once it has
		tail = LOG_TAIL,
		sub = nil,
		matches = {},
		scanned = 0,
		match_at = 0,
		new_since = 0, -- how many lines came since the person scrolled up
		hscroll = 0, -- how many characters the lines are read to the right of their start
		query = "",
		runs = {}, -- the runs of the lines on show, by index, kept while they are
		run_count = 0,
	},
	-- What is asked and shown over everything.
	toasts = {},
	dialog = nil,
	help = false,
	menu = nil, -- what the entries of the menu that is up do
	rev = 0,
	cache = {},
	pending_reload = nil,
	returned = nil,
}

local function bump()
	S.rev += 1
end

-- ---- the containers, as the page reads them ----------------------------------------------------

local function is_up(c)
	return c.state == "running" or c.state == "restarting" or c.state == "paused"
end

local function has_issue(c)
	return c.health == "unhealthy"
		or c.state == "restarting"
		or c.state == "dead"
		or (c.state == "exited" and c.exit_code ~= nil and c.exit_code ~= 0)
end

-- What a container is, in a word and a colour: its state, or its health when that is the news.
local function state_of(c)
	local busy = S.busy[c.id]
	if busy then
		return busy .. "…", "warning"
	end
	if c.state == "running" then
		if c.health == "unhealthy" then
			return "unhealthy", "error"
		elseif c.health == "starting" then
			return "starting", "warning"
		elseif c.health == "healthy" then
			return "healthy", "success"
		end
		return "running", "success"
	elseif c.state == "paused" then
		return "paused", "warning"
	elseif c.state == "restarting" then
		return "restarting", "warning"
	elseif c.state == "exited" then
		if c.exit_code ~= nil and c.exit_code ~= 0 then
			return "exited " .. c.exit_code, "error"
		end
		return "exited", "dim"
	elseif c.state == "dead" then
		return "dead", "error"
	end
	return c.state, "dim"
end

local function container(id)
	return S.by_id[id]
end

local function name_of(id)
	local c = S.by_id[id]
	return c and c.name or string.sub(id, 1, 12)
end

-- The unix time now, from the program's clock when the page has it.
local function unix_now()
	return S.clock and (S.now + S.clock) or nil
end

-- How long ago a time (seconds since 1970) was, in words.
local function ago(seconds)
	local at = unix_now()
	if seconds == nil or at == nil then
		return nil
	end
	return fmt.span(at - seconds) .. " ago"
end

-- ---- the rows of the lists ----------------------------------------------------------------------

local SORTS = { "name", "state", "cpu", "memory", "created" }

local function sort_value(c, how)
	local sample = S.samples[c.short]
	if how == "cpu" then
		return -(sample and sample.cpu or -1)
	elseif how == "memory" then
		return -(sample and sample.memory or -1)
	elseif how == "created" then
		return -(c.created or 0)
	elseif how == "state" then
		return (c.state == "running" and 0 or (is_up(c) and 1 or 2)) * 10 + (has_issue(c) and 0 or 1)
	end
	return 0
end

local function container_matches(c, query)
	if query == "" then
		return true
	end
	if fmt.has(c.name, query) or fmt.has(c.image, query) or fmt.has(c.short, query) then
		return true
	end
	if c.project and fmt.has(c.project, query) then
		return true
	end
	if c.service and fmt.has(c.service, query) then
		return true
	end
	for _, port in ipairs(c.ports) do
		if port.public and fmt.has(tostring(port.public), query) or fmt.has(tostring(port.private), query) then
			return true
		end
	end
	return false
end

local function status_shows(c)
	if S.filter == "running" then
		return is_up(c)
	elseif S.filter == "stopped" then
		return not is_up(c)
	elseif S.filter == "issues" then
		return has_issue(c)
	end
	return true
end

-- Whether a project is folded: as the person left it, and otherwise when nothing of it runs.
local function folded(group)
	local explicit = S.folded[group.key]
	if explicit ~= nil then
		return explicit
	end
	return group.up == 0
end

-- The containers as the rows of the list: a row for each project that has any (when grouped), and
-- a row for each of its containers that is not folded away. `{ kind = "group" | "container", ... }`.
local function container_rows()
	local cached = S.cache.containers
	if cached and cached.rev == S.rev then
		return cached.rows, cached.shown
	end
	local query = S.focus == "detail" and S.tab == "logs" and "" or S.query
	local list = {}
	for _, c in ipairs(S.containers) do
		if status_shows(c) and container_matches(c, query) then
			list[#list + 1] = c
		end
	end
	local how = S.sort
	table.sort(list, function(x, y)
		local vx, vy = sort_value(x, how), sort_value(y, how)
		if vx ~= vy then
			return vx < vy
		end
		return x.name < y.name
	end)
	local rows = {}
	if S.group then
		local groups, order = {}, {}
		for _, c in ipairs(list) do
			local key = c.project or ""
			local group = groups[key]
			if group == nil then
				group =
					{ kind = "group", key = key, name = c.project or "Standalone", members = {}, up = 0, issues = 0 }
				groups[key] = group
				order[#order + 1] = group
			end
			group.members[#group.members + 1] = c
			if is_up(c) then
				group.up += 1
			end
			if has_issue(c) then
				group.issues += 1
			end
		end
		table.sort(order, function(x, y)
			if (x.up > 0) ~= (y.up > 0) then
				return x.up > 0
			end
			if (x.key == "") ~= (y.key == "") then
				return y.key == ""
			end
			return x.name < y.name
		end)
		for _, group in ipairs(order) do
			group.id = "group:" .. group.key
			group.folded = folded(group)
			rows[#rows + 1] = group
			if not group.folded then
				for _, c in ipairs(group.members) do
					rows[#rows + 1] = { kind = "container", id = c.id, c = c }
				end
			end
		end
	else
		for _, c in ipairs(list) do
			rows[#rows + 1] = { kind = "container", id = c.id, c = c }
		end
	end
	S.cache.containers = { rev = S.rev, rows = rows, shown = #list }
	return rows, #list
end

local function counts()
	local all, running, stopped, issues = #S.containers, 0, 0, 0
	for _, c in ipairs(S.containers) do
		if is_up(c) then
			running += 1
		else
			stopped += 1
		end
		if has_issue(c) then
			issues += 1
		end
	end
	return { all = all, running = running, stopped = stopped, issues = issues }
end

-- The names a row of another list is looked for by.
local function image_title(image)
	return image.tags[1] or ("<none> " .. image.id)
end

local function image_matches(image, query)
	if query == "" then
		return true
	end
	for _, tag in ipairs(image.tags) do
		if fmt.has(tag, query) then
			return true
		end
	end
	if fmt.has(image.id, query) then
		return true
	end
	for _, name in ipairs(image.containers or {}) do
		if fmt.has(name, query) then
			return true
		end
	end
	return false
end

-- The rows of a list that is not the containers: filtered by the field, in the order the person
-- is used to. `{ id =, item = }`.
local function plain_rows(section)
	local cached = S.cache[section]
	if cached and cached.rev == S.rev then
		return cached.rows
	end
	local list = S.lists[section] or {}
	local rows = {}
	local query = S.query
	if section == "images" then
		for _, image in ipairs(list) do
			if image_matches(image, query) then
				rows[#rows + 1] = { id = image.id, item = image }
			end
		end
		table.sort(rows, function(x, y)
			local ux, uy = (x.item.running or 0) > 0, (y.item.running or 0) > 0
			if ux ~= uy then
				return ux
			end
			if x.item.dangling ~= y.item.dangling then
				return y.item.dangling
			end
			return image_title(x.item) < image_title(y.item)
		end)
	elseif section == "volumes" then
		for _, volume in ipairs(list) do
			if query == "" or fmt.has(volume.name, query) or (volume.project and fmt.has(volume.project, query)) then
				rows[#rows + 1] = { id = volume.name, item = volume }
			end
		end
		table.sort(rows, function(x, y)
			local ux, uy = #x.item.containers > 0, #y.item.containers > 0
			if ux ~= uy then
				return ux
			end
			return x.item.name < y.item.name
		end)
	elseif section == "networks" then
		for _, network in ipairs(list) do
			if query == "" or fmt.has(network.name, query) or fmt.has(table.concat(network.subnets, " "), query) then
				rows[#rows + 1] = { id = network.id, item = network }
			end
		end
		table.sort(rows, function(x, y)
			if x.item.builtin ~= y.item.builtin then
				return y.item.builtin
			end
			return x.item.name < y.item.name
		end)
	elseif section == "activity" then
		for _, item in ipairs(S.activity) do
			local text = (item.name or item.id or "") .. " " .. item.action .. " " .. (item.words or "")
			if query == "" or fmt.has(text, query) then
				rows[#rows + 1] = { id = tostring(item.seq), item = item }
			end
		end
	end
	S.cache[section] = { rev = S.rev, rows = rows }
	return rows
end

-- The rows of the section on show, whatever it is.
local function rows_of(section)
	if section == "containers" then
		return (container_rows())
	end
	return plain_rows(section)
end

-- The index of the row with `id` among `rows` (or nil), and of the cursor of `section`.
local function index_of(rows, id)
	if id == nil then
		return nil
	end
	for index, row in ipairs(rows) do
		if row.id == id then
			return index
		end
	end
	return nil
end

-- Puts the cursor on a row that is there: where it was, or the row nearest where it was.
local function keep_cursor(section)
	local rows = rows_of(section)
	local at = index_of(rows, S.cursor[section])
	if at == nil then
		local row = rows[1]
		S.cursor[section] = row and row.id or nil
	end
end

-- What the person marked of `section` that is still there, in the order of the list.
local function marked(section)
	local out = {}
	local marks = S.marks[section]
	if marks == nil then
		return out
	end
	for _, row in ipairs(rows_of(section)) do
		if row.kind ~= "group" and marks[row.id] then
			out[#out + 1] = row
		end
	end
	return out
end

-- What an action is meant for: the marked rows, or else the row the cursor is on.
local function targets(section)
	local list = marked(section)
	if #list > 0 then
		return list
	end
	local rows = rows_of(section)
	local row = rows[index_of(rows, S.cursor[section]) or 0]
	if row and row.kind == "group" then
		-- A project stands for all of its containers.
		local members = {}
		for _, c in ipairs(row.members) do
			members[#members + 1] = { kind = "container", id = c.id, c = c }
		end
		return members
	elseif row then
		return { row }
	end
	return {}
end

-- ---- what it asks its program, and what it is told ------------------------------------------

local net = {}

local watching = {}

-- Asks the program for `method`; `done(result, error)` when it answers.
function net.ask(method, params, done)
	return b.call(method, params, function(result, err)
		done(result, err)
		return true
	end)
end

-- Listens to a topic under a name of its own; asking again under the name replaces it.
function net.watch(key, topic, params, handler)
	if watching[key] then
		b.cancel(watching[key])
	end
	watching[key] = b.subscribe(topic, params, function(value)
		handler(value)
		return true
	end)
end

function net.unwatch(key)
	if watching[key] then
		b.cancel(watching[key])
		watching[key] = nil
	end
end

function net.watching(key)
	return watching[key] ~= nil
end

-- What a failed call says, for a person: the words, and for the two ways docker can be out of reach,
-- what to do.
local function why(err)
	if err == nil then
		return nil
	end
	return err.message or err.code or "it failed"
end

-- ---- toasts: what happened, said where the person is --------------------------------------------

local toast = {}

local TOAST_SECONDS = 6

-- Tells something for a few seconds. `options.kind` is the role it is in (success, error, warning,
-- info); `options.action = { label =, run = function }` is a verb it offers while it is up (undo).
function toast.say(text, options)
	options = options or {}
	local item = {
		text = text,
		kind = options.kind or "info",
		action = options.action,
		show = options.show,
		until_ = S.now + (options.seconds or TOAST_SECONDS),
	}
	S.toasts[#S.toasts + 1] = item
	while #S.toasts > 4 do
		table.remove(S.toasts, 1)
	end
	return item
end

-- Takes away the toasts whose time is up; the time of the next one to go (so that the page is
-- rendered again then), when there is one.
function toast.tidy()
	local keep, next_at = {}, nil
	for _, item in ipairs(S.toasts) do
		if item.until_ > S.now then
			keep[#keep + 1] = item
			next_at = next_at and math.min(next_at, item.until_) or item.until_
		end
	end
	if #keep ~= #S.toasts then
		S.toasts = keep
	end
	return next_at
end

-- ---- the containers, as the program tells them -----------------------------------------------------

local function sync_containers(list)
	S.containers = list
	S.by_id = {}
	for _, c in ipairs(list) do
		S.by_id[c.id] = c
	end
	for id in pairs(S.marks.containers or {}) do
		if S.by_id[id] == nil then
			S.marks.containers[id] = nil
		end
	end
	if S.open and S.by_id[S.open] == nil then
		S.open = nil
		S.focus = "list"
	end
	bump()
end

-- What the container list says of the engine: why there is no list, or that there is one again.
local function on_containers(value)
	local was = S.failure
	S.known = true
	S.engine = value.engine or S.engine
	S.failure = value.failure
	sync_containers(value.containers or {})
	keep_cursor("containers")
	S.reveal = false
	if S.failure and not was then
		-- Said once, where the person is, however far from the list.
		toast.say(why(S.failure), { kind = "error" })
	elseif was and not S.failure then
		toast.say("Docker is back", { kind = "success" })
	end
end

-- A container's stats as they come: the last reading of each, and a line of the last readings.
local function on_stats(value)
	if value.history then
		for short, series in pairs(value.history) do
			S.series[short] = series
		end
	end
	for _, sample in ipairs(value.samples or {}) do
		S.samples[sample.id] = sample
		local series = S.series[sample.id]
		if series == nil then
			series = { cpu = {}, memory = {}, net_in = {}, net_out = {} }
			S.series[sample.id] = series
		end
		for _, key in ipairs({ "cpu", "memory", "net_in", "net_out" }) do
			local line = series[key]
			line[#line + 1] = sample[key]
			if #line > 120 then
				table.remove(line, 1)
			end
		end
	end
	-- Containers that are not running have no reading.
	for short in pairs(S.samples) do
		local alive = false
		for _, c in ipairs(S.containers) do
			if c.short == short and c.state == "running" then
				alive = true
				break
			end
		end
		if not alive then
			S.samples[short] = nil
		end
	end
	if S.sort == "cpu" or S.sort == "memory" then
		bump()
	end
end

-- What the engine reports: kept as the Activity screen shows it, and, for the ones that are news,
-- told where the person is.
local function on_events(value)
	local items = value.items
	if value.backlog then
		items = value.backlog
		S.activity = {}
	end
	for _, item in ipairs(items or {}) do
		table.insert(S.activity, 1, item)
		if #S.activity > 300 then
			table.remove(S.activity)
		end
		if item.notice and not value.backlog then
			local name = item.name or string.sub(item.id or "", 1, 12)
			toast.say(name .. " " .. (item.words or item.action), {
				kind = item.notice == "unhealthy" and "warning" or "error",
				seconds = 9,
				show = item.type == "container" and item.id or nil,
			})
		end
		-- A change to what lists show is a reason to look again, if they are on show.
		if item.type == "image" or item.type == "volume" or item.type == "network" then
			local section = item.type .. "s"
			if S.lists[section] then
				S.stale[section] = true
				S.pending_reload = S.now + 0.4
			end
		end
	end
	bump()
end

local function on_jobs(value)
	local was = {}
	for _, job in ipairs(S.jobs) do
		was[job.id] = job.state
	end
	S.jobs = value.jobs or {}
	for _, job in ipairs(S.jobs) do
		if was[job.id] == "running" and job.state ~= "running" then
			if job.state == "done" then
				if job.kind == "pull" then
					toast.say(job.title .. ": done", { kind = "success" })
				else
					toast.say(
						job.freed and job.freed > 0 and ("Freed " .. fmt.disk(job.freed)) or (job.title .. ": done"),
						{ kind = "success" }
					)
				end
			else
				toast.say(job.title .. " failed: " .. tostring(job.error), { kind = "error", seconds = 10 })
			end
			S.stale.images, S.stale.volumes, S.stale.networks, S.stale.system = true, true, true, true
			S.pending_reload = S.now + 0.2
		end
	end
	bump()
end

-- ---- the lists docker keeps, asked for when they come on show ------------------------------------------

local function load_list(section)
	if S.loading[section] then
		S.stale[section] = true
		return
	end
	S.loading[section] = true
	S.stale[section] = false
	net.ask(section, nil, function(result, err)
		S.loading[section] = false
		if err then
			S.problems[section] = why(err)
		else
			S.problems[section] = nil
			S.lists[section] = result[section]
			if section == "volumes" and not result.sized then
				net.ask("volume_sizes", nil, function(counted, failed)
					if not failed then
						S.volume_sizes = counted.sizes
						bump()
					end
				end)
			end
		end
		bump()
		keep_cursor(section)
		if S.stale[section] then
			load_list(section)
		end
	end)
end

local function load_system()
	if S.loading.system then
		S.stale.system = true
		return
	end
	S.loading.system = true
	S.stale.system = false
	net.ask("system", nil, function(result, err)
		S.loading.system = false
		if err then
			S.problems.system = why(err)
		else
			S.problems.system = nil
			S.system = result
		end
		bump()
		if S.stale.system then
			load_system()
		end
	end)
end

-- The detail of a container, asked for when it opens, and again when its state changed.
local function signature(c)
	return c.state .. "/" .. c.health .. "/" .. c.status
end

local function load_detail(id)
	local c = S.by_id[id]
	local slot = S.details[id]
	if slot == nil then
		slot = { state = "loading" }
		S.details[id] = slot
	end
	if slot.asking then
		return
	end
	slot.asking = true
	slot.signature = c and signature(c) or nil
	net.ask("detail", { id = id }, function(result, err)
		slot.asking = false
		if err then
			slot.state, slot.error = "error", why(err)
		else
			slot.state, slot.data, slot.error = "ok", result, nil
		end
		bump()
	end)
end

local function load_processes(id)
	local slot = S.processes
	if slot.asking then
		return
	end
	slot.asking, slot.id = true, id
	net.ask("processes", { id = id }, function(result, err)
		slot.asking = false
		if slot.id ~= id then
			return
		end
		if err then
			slot.error = why(err)
		else
			slot.error, slot.titles, slot.rows = nil, result.titles, result.rows
		end
		slot.at = S.now
		bump()
	end)
end

-- ---- a container's log -----------------------------------------------------------------------------

local L = S.log

local function log_clear(id, tail)
	L.id, L.tail = id, tail or L.tail
	L.texts, L.streams, L.clocks = {}, "", {}
	L.count, L.last, L.ended = 0, nil, nil
	L.matches, L.scanned, L.match_at = {}, 0, 0
	L.runs, L.run_count = {}, 0
	L.new_since = 0
	L.hscroll = 0
	L.follow = true
end

-- Keeps what a log is allowed to hold: when it is more than the page keeps, the oldest fifth goes.
local function log_trim()
	if L.count <= LOG_MOST + LOG_MOST // 5 then
		return
	end
	local drop = L.count - LOG_MOST
	table.move(L.texts, drop + 1, L.count, 1)
	table.move(L.clocks, drop + 1, L.count, 1)
	for index = L.count - drop + 1, L.count do
		L.texts[index], L.clocks[index] = nil, nil
	end
	L.streams = string.sub(L.streams, drop + 1)
	L.count -= drop
	L.matches, L.scanned, L.match_at = {}, 0, 0
	L.runs, L.run_count = {}, 0
end

local function on_log(value)
	if value.ended then
		L.ended = value.ended
		return
	end
	local texts = value.texts
	if texts and #texts > 0 then
		table.move(texts, 1, #texts, L.count + 1, L.texts)
		table.move(value.clocks, 1, #value.clocks, L.count + 1, L.clocks)
		L.streams ..= value.streams
		L.count += #texts
		if not L.follow then
			L.new_since += #texts
		end
		log_trim()
	end
	L.last = value.last or L.last
end

-- Whether the container of the log on show is running (a log of one that stopped does not go on).
local function log_live()
	local c = L.id and S.by_id[L.id]
	return c ~= nil and c.state == "running"
end

-- ---- what the person asks to be done ---------------------------------------------------------------

local act = {}

local PARTICIPLE = {
	start = "starting",
	stop = "stopping",
	restart = "restarting",
	pause = "pausing",
	unpause = "resuming",
	kill = "killing",
	remove = "removing",
}

local PAST = {
	start = "Started",
	stop = "Stopped",
	restart = "Restarted",
	pause = "Paused",
	unpause = "Resumed",
	kill = "Killed",
	remove = "Removed",
}

local function names_of(ids)
	if #ids == 1 then
		return name_of(ids[1])
	end
	return fmt.count(#ids, "container")
end

-- Does `action` to the containers `ids`, and says how it went. A stop can be taken back from the
-- toast that says it happened.
function act.run(ids, action, options)
	options = options or {}
	if #ids == 0 then
		return
	end
	for _, id in ipairs(ids) do
		S.busy[id] = PARTICIPLE[action]
	end
	bump()
	local params = { ids = ids, action = action, force = options.force, volumes = options.volumes }
	net.ask("act", params, function(result, err)
		for _, id in ipairs(ids) do
			S.busy[id] = nil
		end
		bump()
		if err then
			toast.say(why(err), { kind = "error", seconds = 10 })
			return
		end
		local done, failed = {}, {}
		for _, outcome in ipairs(result.outcomes) do
			if outcome.ok then
				done[#done + 1] = outcome.id
			else
				failed[#failed + 1] = outcome
			end
		end
		if #done > 0 then
			local text = PAST[action] .. " " .. names_of(done)
			local offer = nil
			if action == "stop" then
				offer = {
					label = "Undo",
					run = function()
						act.run(done, "start")
					end,
				}
			end
			toast.say(text, { kind = "success", action = offer })
		end
		for _, outcome in ipairs(failed) do
			toast.say(outcome.name .. ": " .. (outcome.error or "it failed"), { kind = "error", seconds = 10 })
		end
		if action == "remove" then
			for _, id in ipairs(done) do
				S.marks.containers[id] = nil
			end
		end
	end)
end

-- The pane to a shell in a container, or to its log as it comes.
function act.terminal(kind, c)
	if not S.handoff then
		toast.say("This terminal cannot hand its pane to a command and back.", { kind = "warning" })
		return
	end
	if kind == "shell" and c.state ~= "running" then
		toast.say(c.name .. " is not running: start it first", { kind = "warning" })
		return
	end
	net.ask("handoff", { kind = kind, id = c.id, name = c.name }, function(result, err)
		if err then
			toast.say(why(err), { kind = "error" })
		elseif result.state == "unavailable" then
			toast.say("This terminal cannot hand its pane to a command and back.", { kind = "warning" })
		elseif result.state == "busy" then
			toast.say("The pane is going to a command already.", { kind = "warning" })
		end
	end)
end

-- Asks first: a question over everything, answered with a key or a button. `options.danger` makes
-- the answer that does nothing the one the keyboard is on.
local function ask(title, lines, confirm, run, options)
	options = options or {}
	S.dialog = {
		title = title,
		lines = lines,
		confirm = confirm,
		run = run,
		danger = options.danger,
		choice = options.danger and "cancel" or "confirm",
		field = options.field,
	}
	bump()
end

local function remove_things(method, key, ids, label, force)
	net.ask(method, { [key] = ids, force = force }, function(result, err)
		if err then
			toast.say(why(err), { kind = "error", seconds = 10 })
			return
		end
		local done, failed = 0, {}
		for _, outcome in ipairs(result.outcomes) do
			if outcome.ok then
				done += 1
			else
				failed[#failed + 1] = outcome
			end
		end
		if done > 0 then
			toast.say("Removed " .. fmt.count(done, label), { kind = "success" })
		end
		for _, outcome in ipairs(failed) do
			toast.say(outcome.name .. ": " .. (outcome.error or "it failed"), { kind = "error", seconds = 10 })
		end
		local section = method == "image_remove" and "images" or (method == "volume_remove" and "volumes" or "networks")
		S.marks[section] = {}
		S.stale[section] = true
		S.pending_reload = S.now + 0.1
	end)
end

-- Asks, then removes, what the cursor or the marks name in a list of images, volumes or networks.
function act.remove_listed(section)
	local rows = targets(section)
	if #rows == 0 then
		return
	end
	local ids, names = {}, {}
	for _, row in ipairs(rows) do
		names[#names + 1] = section == "images" and image_title(row.item) or row.item.name
		ids[#ids + 1] = section == "images" and row.id or (section == "volumes" and row.item.name or row.id)
	end
	if section == "networks" then
		for _, row in ipairs(rows) do
			if row.item.builtin then
				toast.say(row.item.name .. " is one of Docker's own: it cannot be removed", { kind = "warning" })
				return
			end
		end
	end
	local noun = section == "images" and "image" or (section == "volumes" and "volume" or "network")
	local lines = {}
	for index, name in ipairs(names) do
		if index <= 6 then
			lines[#lines + 1] = name
		end
	end
	if #names > 6 then
		lines[#lines + 1] = "and " .. (#names - 6) .. " more"
	end
	local note = nil
	if section == "images" then
		local used = 0
		for _, row in ipairs(rows) do
			used += #row.item.containers
		end
		if used > 0 then
			note = "Containers were made from "
				.. (#rows == 1 and "it" or "some of these")
				.. ": docker will say no unless they are removed first."
		end
	elseif section == "volumes" then
		note = "What is in " .. (#rows == 1 and "it" or "them") .. " is gone for good."
	end
	local method = section == "images" and "image_remove"
		or (section == "volumes" and "volume_remove" or "network_remove")
	local key = section == "images" and "ids" or (section == "volumes" and "names" or "ids")
	ask("Remove " .. fmt.count(#ids, noun) .. "?", { names = lines, note = note }, "Remove", function()
		remove_things(method, key, ids, noun, false)
	end, { danger = true })
end

-- Asks, then removes, the containers the cursor or the marks name.
function act.remove_containers()
	local rows = targets("containers")
	local ids, lines, running = {}, {}, 0
	for _, row in ipairs(rows) do
		ids[#ids + 1] = row.id
		if #lines < 6 then
			lines[#lines + 1] = row.c.name
		end
		if is_up(row.c) then
			running += 1
		end
	end
	if #ids == 0 then
		return
	end
	if #ids > 6 then
		lines[#lines + 1] = "and " .. (#ids - 6) .. " more"
	end
	local note = "Its logs and what it wrote to its own disk go with it."
	if #ids > 1 then
		note = "Their logs and what they wrote to their own disks go with them."
	end
	local force = running > 0
	if force then
		note = (
			running == 1 and "It is running and will be stopped first. "
			or (running .. " are running and will be stopped first. ")
		) .. note
	end
	ask("Remove " .. fmt.count(#ids, "container") .. "?", { names = lines, note = note }, "Remove", function()
		act.run(ids, "remove", { force = force })
	end, { danger = true })
end

function act.kill_containers()
	local rows = targets("containers")
	local ids, lines = {}, {}
	for _, row in ipairs(rows) do
		if is_up(row.c) then
			ids[#ids + 1] = row.id
			if #lines < 6 then
				lines[#lines + 1] = row.c.name
			end
		end
	end
	if #ids == 0 then
		toast.say("Nothing that runs is chosen", { kind = "warning" })
		return
	end
	ask(
		"Kill " .. fmt.count(#ids, "container") .. "?",
		{
			names = lines,
			note = "They are sent SIGKILL: no time to finish what they are doing.",
		},
		"Kill",
		function()
			act.run(ids, "kill")
		end,
		{ danger = true }
	)
end

-- Stops what runs and starts what does not, of the containers chosen: one verb for the row.
function act.toggle()
	local rows = targets("containers")
	local stopping, starting = {}, {}
	for _, row in ipairs(rows) do
		if is_up(row.c) then
			stopping[#stopping + 1] = row.id
		else
			starting[#starting + 1] = row.id
		end
	end
	if #stopping > 0 and #starting == 0 then
		act.run(stopping, "stop")
	elseif #starting > 0 and #stopping == 0 then
		act.run(starting, "start")
	elseif #stopping > 0 then
		act.run(stopping, "stop")
	end
end

function act.do_all(action)
	local rows = targets("containers")
	local ids = {}
	for _, row in ipairs(rows) do
		if
			action == "restart"
			or (action == "pause" and row.c.state == "running")
			or (action == "unpause" and row.c.state == "paused")
		then
			ids[#ids + 1] = row.id
		end
	end
	act.run(ids, action)
end

-- Pause what runs, resume what is paused.
function act.pause_toggle()
	local rows = targets("containers")
	local pausing, resuming = {}, {}
	for _, row in ipairs(rows) do
		if row.c.state == "paused" then
			resuming[#resuming + 1] = row.id
		elseif row.c.state == "running" then
			pausing[#pausing + 1] = row.id
		end
	end
	if #resuming > 0 then
		act.run(resuming, "unpause")
	else
		act.run(pausing, "pause")
	end
end

-- Pulls an image or a tag as a job.
function act.pull(reference)
	net.ask("pull", { reference = reference }, function(_, err)
		if err then
			toast.say(why(err), { kind = "error", seconds = 10 })
		end
	end)
end

-- Asks for the clean-up of what nothing uses, saying what it will free first.
function act.prune(targets_, titles, freed)
	local lines = {}
	for _, title in ipairs(titles) do
		lines[#lines + 1] = title
	end
	local note = freed and freed > 0 and ("About " .. fmt.disk(freed) .. " is freed.") or "There is nothing to free."
	ask("Clean up what nothing uses?", { names = lines, note = note }, "Clean up", function()
		net.ask("prune", { targets = targets_ }, function(_, err)
			if err then
				toast.say(why(err), { kind = "error", seconds = 10 })
			end
		end)
	end, { danger = true })
end

-- ---- the small things a screen is made of ---------------------------------------------------------

local P = {}

-- The longest line of text the page makes (the kit takes 64 KiB, and ends a page that makes more).
local LINE_MOST = 4000

-- A line of text in a role, a size and a weight.
local function T(content, color, size, weight)
	if type(content) == "string" and #content > LINE_MOST then
		local cut = string.sub(content, 1, LINE_MOST)
		-- Not in the middle of a character.
		while #cut > 0 and utf8.len(cut) == nil do
			cut = string.sub(cut, 1, -2)
		end
		content = cut .. "…"
	end
	local t = b.text(content)
	if color then
		t:color(color)
	end
	if size then
		t:text_size(size)
	end
	if weight then
		t:weight(weight)
	end
	return t
end

local function hovered(id)
	return ui.hover == id
end

-- A key cap: the key that does the same as what stands beside it.
function P.kbd(label, size)
	return b.div()
		:row()
		:items_center()
		:justify_center()
		:min_w(16)
		:h(16)
		:px(4)
		:rounded(4)
		:bg("raised2")
		:no_shrink()
		:child(T(label, "dim", size or SIZE.tiny))
end

-- A button: a verb. `options`: `primary` (the one thing to do), `danger`, `key` (its shortcut, shown
-- beside it), `disabled`, `selected`.
function P.button(id, label, options)
	options = options or {}
	local over = hovered(id) and not options.disabled
	local down = ui.pressed == id and over
	local el = b.div():row():items_center():gap(7):h(options.h or 26):px(options.px or 10):rounded(6):no_shrink()
	local ink = "foreground"
	if options.disabled then
		ink = "quiet"
		el:border(1, alpha("border", 0.6))
	else
		el:press(id)
		if options.primary then
			ink = "background"
			el:bg(down and alpha("accent", 0.75) or (over and alpha("accent", 0.9) or "accent"))
		elseif options.danger then
			ink = "error"
			el:bg(over and alpha("error", down and 0.22 or 0.14) or nil):border(1, alpha("error", over and 0.9 or 0.5))
		else
			el:bg(over and (down and "raised4" or "raised3") or (options.selected and "raised3" or "raised2"))
				:border(1, "border")
		end
	end
	el:child(T(label, ink, options.size or SIZE.body, 500))
	if options.key then
		el:child(P.kbd(options.key))
	end
	return el
end

-- A word in a coloured label: what a container is, what an image is used by.
function P.tag(label, role, size)
	return b.div()
		:row()
		:items_center()
		:h(18)
		:px(6)
		:rounded(4)
		:bg(alpha(role, 0.14))
		:no_shrink()
		:child(T(label, role, size or SIZE.tiny + 0.5))
end

-- A round mark: solid for what is up, a ring for what is not.
function P.dot(role, solid, size)
	size = size or 9
	local dot = b.div():size(size, size):rounded(size / 2):no_shrink()
	if solid then
		return dot:bg(role)
	end
	return dot:border(1.5, role)
end

-- The mark of a container's state: solid when it runs, a ring when not, half-lit when it is waiting.
function P.state_dot(c)
	local _, role = state_of(c)
	if c.state == "running" then
		return P.dot(role, true)
	elseif c.state == "paused" or c.state == "restarting" or S.busy[c.id] then
		return P.dot(alpha(role, 0.55), true)
	end
	return P.dot(role, false)
end

-- A bar that is `fraction` full (0 to 1).
function P.meter(fraction, role, width, height)
	fraction = math.max(0, math.min(1, fraction or 0))
	height = height or 4
	local track = b.div():h(height):rounded(height / 2):bg("raised2"):clip():no_shrink()
	if width then
		track:w(width)
	else
		track:grow(1):min_w(0)
	end
	if fraction > 0 then
		track:child(b.div():w_pct(math.max(fraction * 100, 3)):h(height):rounded(height / 2):bg(role))
	end
	return track
end

-- A line of the last readings of something, newest last.
function P.spark(values, role, ceiling)
	local n = #values
	local from = math.max(1, n - SPARK + 1)
	local tail = {}
	for index = from, n do
		tail[#tail + 1] = values[index]
	end
	if #tail == 0 then
		return b.div()
	end
	local line = b.spark(tail, role)
	if ceiling then
		line:peak(ceiling)
	end
	return line:size_full()
end

-- The title of a screen: its name, what it holds, and the verbs of the whole of it at the end.
function P.title(name, subtitle, verbs)
	local row = b.div():row():items_center():gap(12):h(SIZE.head):px(20):no_shrink()
	row:child(T(name, "foreground", 16, 650):no_shrink())
	if subtitle then
		row:child(T(subtitle, "dim", SIZE.small + 0.5):truncate():min_w(0))
	end
	row:child(b.spacer())
	for _, verb in ipairs(verbs or {}) do
		row:child(verb)
	end
	return row
end

-- A row of tabs: what is shown is one of them.
function P.tabs(list, current, prefix)
	local row = b.div():row():items_end():gap(2):px(16):h(32):no_shrink()
	for _, tab in ipairs(list) do
		local id = prefix .. tab.id
		local active = tab.id == current
		local over = hovered(id)
		row:child(
			b.div()
				:press(id)
				:col()
				:justify_end()
				:px(10)
				:h(32)
				:no_shrink()
				:bg(over and not active and alpha("foreground", 0.05) or nil)
				:rounded_corners({ 5, 5, 0, 0 })
				:child(
					b.div()
						:grow(1)
						:row()
						:items_center()
						:child(T(tab.label, active and "foreground" or "dim", SIZE.body, active and 600 or 400))
				)
				:child(b.div():h(2):bg(active and "accent" or nil))
		)
	end
	return row
end

-- A label and its value, side by side: one fact.
function P.fact(label, value, role)
	return b.div()
		:row()
		:gap(14)
		:min_h(22)
		:items_start()
		:child(b.div():w(112):no_shrink():child(T(label, "dim", SIZE.small + 0.5)))
		:child(b.div():grow(1):min_w(0):child(T(value, role or "foreground", SIZE.body):truncate()))
end

-- A small heading over a group of facts.
function P.heading(label, extra)
	local row = b.div()
		:row()
		:items_center()
		:gap(8)
		:h(26)
		:mt(10)
		:no_shrink()
		:child(T(string.upper(label), "quiet", SIZE.tiny + 0.5, 600))
	if extra then
		row:child(extra)
	end
	return row
end

-- A line that says there is nothing here, and what to do.
function P.nothing(title, hint)
	return b.div()
		:col()
		:items_center()
		:gap(6)
		:pt(54)
		:px(20)
		:no_shrink()
		:child(T(title, "dim", SIZE.body + 1))
		:child(hint and T(hint, "quiet", SIZE.small):align("center") or b.div())
end

-- A card: a surface a step above the page.
function P.card()
	return b.div():col():gap(4):p(12):rounded(8):bg("raised1"):border(1, alpha("border", 0.7))
end

-- The field of the host, or what it says where it is not here. The host's text field has one
-- place at a time on the page, the room of the element that says it is one.
function P.field(active, hint, width)
	local box =
		b.div():row():items_center():gap(8):h(28):px(9):rounded(6):bg("raised1"):border(1, "border"):press("field")
	if width then
		box:w(width):min_w(120)
	else
		box:grow(1):min_w(120)
	end
	if active then
		box:child(b.div():id("field.room"):text_field():grow(1):min_w(0):h(18))
	else
		box:child(b.div():grow(1):min_w(0):child(T(hint, "quiet", SIZE.body):truncate()))
	end
	return box:child(P.kbd("/"))
end

-- The mark of a row that can be chosen with space: filled when it is.
function P.check(on)
	local box = b.div():size(14, 14):rounded(4):no_shrink()
	if on then
		return box:bg("accent")
			:child(b.div():size_full():row():items_center():justify_center():child(T("✓", "background", 10, 700)))
	end
	return box:border(1.2, alpha("foreground", 0.3))
end

-- Some words are said in a line; this cuts them to the room the line has.
function P.line(content, role, size, weight)
	return T(content, role or "foreground", size or SIZE.body, weight):truncate()
end

-- ---- long lists: only the rows in view are made -----------------------------------------------

local views = {} -- how tall each scrolling box was laid out, by its id

local OVERSCAN = 3

-- A list of `count` rows of one `height`, of which the ones in view and a few around them are
-- made (`make(index)`): the rest of the list's length is two spacers.
local function virtual(id, count, height, make, options)
	options = options or {}
	local offset = ui:scroll_offset(id)
	local view = views[id] or 480
	local lead = options.lead or 0
	local first = math.max(1, math.floor((offset - lead) / height) + 1 - OVERSCAN)
	local last = math.min(count, math.ceil((offset + view - lead) / height) + OVERSCAN)
	local box = b.div():col():id(id):grow(1):min_h(0):scroll_y(offset):px(options.px or 8)
	if options.pt then
		box:pt(options.pt)
	end
	if lead > 0 then
		box:child(b.div():h(lead):no_shrink())
	end
	box:child(b.div():h(math.max(first - 1, 0) * height):no_shrink())
	for index = first, last do
		box:child(make(index))
	end
	box:child(b.div():h(math.max(count - last, 0) * height + (options.trail or 8)):no_shrink())
	return box
end

-- Scrolls the least that shows row `index` of the list `id`.
local function reveal(id, index, count, height, lead)
	local view = views[id] or 480
	lead = lead or 0
	local top = lead + (index - 1) * height
	local bottom = top + height
	local offset = ui:scroll_offset(id)
	if top - (index == 1 and lead or 0) < offset then
		ui:set_scroll(id, math.max(top - (index == 1 and lead or 0), 0))
	elseif bottom + (index == count and 8 or 0) > offset + view then
		ui:set_scroll(id, math.max(bottom + (index == count and 8 or 0) - view, 0))
	end
end

-- How wide the main part of the page is (what is not the rail), and whether the detail of a
-- container is beside the list or over it.
local function geometry()
	local rail = S.width >= RAIL_FROM and SIZE.rail or 0
	local main = S.width - rail
	local beside = main >= 880
	return { rail = rail, main = main, beside = beside }
end

-- ---- the containers ----------------------------------------------------------------------------

local screens = {}

-- The columns of the list of containers that fit `width`.
local function columns(width)
	return {
		image = width >= LIST_MEDIUM,
		cpu = width >= LIST_MEDIUM + 40,
		memory = width >= LIST_WIDE,
		ports = width >= LIST_WIDE + 200,
	}
end

local COL = { check = 14, dot = 9, state = 108, cpu = 108, memory = 78, age = 70, verb = 66 }

-- The cells a row of the list of containers is made of, from a function that makes each.
local function cells(cols, make)
	local list = {}
	list[#list + 1] = make.check()
	list[#list + 1] = make.dot()
	list[#list + 1] = make.name()
	if cols.image then
		list[#list + 1] = make.image()
	end
	list[#list + 1] = make.state()
	if cols.cpu then
		list[#list + 1] = make.cpu()
	end
	if cols.memory then
		list[#list + 1] = make.memory()
	end
	list[#list + 1] = make.age()
	list[#list + 1] = make.verb()
	return list
end

local function header_row(cols)
	local function label(text, width, grow, align)
		local cell = b.div():no_shrink()
		if width then
			cell:w(width)
		else
			cell:w(0):grow(grow):min_w(40):no_shrink()
		end
		return cell:child(T(text, "quiet", SIZE.tiny + 0.5, 600):align(align or "start"):truncate())
	end
	local row = b.div():row():items_center():gap(10):h(24):px(18):no_shrink()
	for _, cell in
		ipairs(cells(cols, {
			check = function()
				return b.div():w(COL.check):no_shrink()
			end,
			dot = function()
				return b.div():w(COL.dot):no_shrink()
			end,
			name = function()
				return label("NAME", nil, 1.5)
			end,
			image = function()
				return label("IMAGE", nil, 1.2)
			end,
			state = function()
				return label("STATE", COL.state)
			end,
			cpu = function()
				return label("CPU", COL.cpu)
			end,
			memory = function()
				return label("MEMORY", COL.memory, nil, "end")
			end,
			age = function()
				return label("UP", COL.age, nil, "end")
			end,
			verb = function()
				return b.div():w(COL.verb):no_shrink()
			end,
		}))
	do
		row:child(cell)
	end
	return row
end

-- One container of the list.
local function container_row(row, cols)
	local c = row.c
	local id = "row:" .. c.id
	local verb_id = "verb:" .. c.id
	local cursor = S.cursor.containers == c.id
	local over = hovered(id) or hovered(verb_id) or hovered("mark:" .. c.id)
	local word, role = state_of(c)
	local sample = S.samples[c.short]
	local series = S.series[c.short]
	local marked_on = S.marks.containers and S.marks.containers[c.id]
	local el = b.div():press(id):row():items_center():gap(10):h(SIZE.row):px(10):rounded(7):no_shrink()
	if cursor then
		el:bg(alpha("accent", S.focus == "list" and 0.14 or 0.08))
			:border(1, alpha("accent", S.focus == "list" and 0.55 or 0.3))
	elseif over then
		el:bg(alpha("foreground", 0.055))
	end
	local up = is_up(c)
	for _, cell in
		ipairs(cells(cols, {
			check = function()
				local cell = b.div():press("mark:" .. c.id):w(COL.check):no_shrink()
				if marked_on or over or cursor or S.any_marked then
					cell:child(P.check(marked_on))
				end
				return cell
			end,
			dot = function()
				return b.div():w(COL.dot):no_shrink():child(P.state_dot(c))
			end,
			name = function()
				return b.div()
					:w(0)
					:grow(1.5)
					:min_w(60)
					:row()
					:items_center()
					:gap(8)
					:child(P.line(c.name, up and "foreground" or "dim", SIZE.body, 600))
			end,
			image = function()
				return b.div():w(0):grow(1.2):min_w(40):child(P.line(c.image, "dim", SIZE.small + 0.5))
			end,
			state = function()
				return b.div()
					:w(COL.state)
					:no_shrink()
					:child(P.line(word, role, SIZE.small + 0.5, c.state == "running" and 400 or 500))
			end,
			cpu = function()
				local cell = b.div():w(COL.cpu):no_shrink():row():items_center():gap(8)
				if sample and c.state == "running" then
					cell:child(
						b.div()
							:w(48)
							:h(16)
							:no_shrink()
							:child(P.spark(series and series.cpu or {}, "accent", math.max(100, sample.cpu)))
					)
					cell:child(
						b.div()
							:w(48)
							:no_shrink()
							:child(T(fmt.percent(sample.cpu), "foreground", SIZE.small + 0.5):align("end"))
					)
				else
					cell:child(T("–", "quiet", SIZE.small + 0.5))
				end
				return cell
			end,
			memory = function()
				local cell = b.div():w(COL.memory):no_shrink():row():justify_end()
				if sample and c.state == "running" then
					cell:child(T(fmt.bytes(sample.memory), "foreground", SIZE.small + 0.5))
				else
					cell:child(T("–", "quiet", SIZE.small + 0.5))
				end
				return cell
			end,
			age = function()
				return b.div()
					:w(COL.age)
					:no_shrink()
					:row()
					:justify_end()
					:child(P.line(fmt.status(c.status), "dim", SIZE.small + 0.5):align("end"))
			end,
			verb = function()
				local cell = b.div():w(COL.verb):no_shrink():row():justify_end()
				if cursor or over then
					local label = up and "Stop" or "Start"
					if S.busy[c.id] then
						label = "…"
					end
					cell:child(
						P.button(
							verb_id,
							label,
							{ h = 22, px = 8, size = SIZE.small + 0.5, disabled = S.busy[c.id] ~= nil }
						)
					)
				end
				return cell
			end,
		}))
	do
		el:child(cell)
	end
	return el
end

-- The row that heads a compose project.
local function group_row(group)
	local id = "row:" .. group.id
	local cursor = S.cursor.containers == group.id
	local over = hovered(id)
	local el = b.div():press(id):row():items_center():gap(8):h(SIZE.row):px(12):rounded(7):no_shrink()
	if cursor then
		el:bg(alpha("accent", S.focus == "list" and 0.12 or 0.07)):border(1, alpha("accent", 0.5))
	elseif over then
		el:bg(alpha("foreground", 0.05))
	end
	el:child(T(group.folded and "▸" or "▾", "dim", SIZE.body):w(14):no_shrink())
	el:child(T(group.name, group.key == "" and "dim" or "foreground", SIZE.body + 0.5, 650):no_shrink())
	el:child(T(group.up .. "/" .. #group.members .. " up", "dim", SIZE.small + 0.5):no_shrink())
	if group.issues > 0 then
		el:child(P.tag(group.issues .. " with " .. (group.issues == 1 and "an issue" or "issues"), "error"))
	end
	el:child(b.spacer())
	if cursor or over or hovered("verb:" .. group.id) then
		el:child(
			P.button(
				"verb:" .. group.id,
				group.up > 0 and "Stop all" or "Start all",
				{ h = 22, px = 8, size = SIZE.small + 0.5 }
			)
		)
	end
	local marks = b.div():row():gap(2):items_center():no_shrink()
	for index, c in ipairs(group.members) do
		if index > 14 then
			break
		end
		local _, role = state_of(c)
		marks:child(b.div():size(5, 12):rounded(2):bg(is_up(c) and role or alpha("foreground", 0.2)))
	end
	return el:child(marks)
end

-- The line above the list: the filter, the states, grouping.
local function filter_bar(width)
	local count = counts()
	local bar = b.div():row():items_center():gap(8):h(SIZE.bar):px(20):no_shrink()
	bar:child(P.field(S.field == "list", "Filter by name, image, port…", width >= 700 and 260 or nil))
	local chips = b.div():row():items_center():gap(2):no_shrink():p(2):rounded(7):bg("raised1")
	for _, f in ipairs(FILTERS) do
		local id = "filter:" .. f.id
		local active = S.filter == f.id
		local n = count[f.id]
		local label = b.div():row():items_center():gap(5):h(24):px(9):rounded(5):press(id):no_shrink()
		if active then
			label:bg("raised3")
		elseif hovered(id) then
			label:bg(alpha("foreground", 0.06))
		end
		label:child(T(f.label, active and "foreground" or "dim", SIZE.small + 1, active and 600 or 400))
		local role = (f.id == "issues" and n > 0) and "error" or "quiet"
		label:child(T(tostring(n), role, SIZE.tiny + 0.5))
		chips:child(label)
	end
	bar:child(chips)
	bar:child(b.spacer())
	if width >= 760 then
		bar:child(
			P.button(
				"group",
				S.group and "Grouped" or "Flat",
				{ selected = S.group, key = "P", h = 24, size = SIZE.small + 0.5 }
			)
		)
		bar:child(P.button("sort", "Sort: " .. S.sort, { key = "o", h = 24, size = SIZE.small + 0.5 }))
	end
	return bar
end

-- Why there is nothing to list.
local function nothing_listed(rows_shown)
	if S.failure and #S.containers == 0 then
		local hint = S.failure.code == "docker-missing"
				and "dockerpen runs the docker command. Install Docker, or put docker on the PATH."
			or "Start Docker (or OrbStack, Colima, Podman…) and dockerpen carries on by itself."
		return P.nothing(
			S.failure.code == "docker-missing" and "There is no docker command" or "Docker is not reachable",
			hint
		)
			:child(T(S.failure.message, "quiet", SIZE.small):truncate():max_w(560):mt(6))
	end
	if #S.containers == 0 then
		if not S.known then
			return P.nothing("Looking for containers…")
		end
		return P.nothing(
			"There are no containers",
			"Start one with docker run, or docker compose up, and it shows here."
		)
	end
	if S.query ~= "" then
		return P.nothing(
			"No container matches “" .. S.query .. "”",
			"Change the filter, or select what is in the field and type another."
		)
	end
	return P.nothing("No " .. string.lower(S.filter) .. " containers", "Press f to look at another kind.")
end

-- The list of containers: the bar, the heads of the columns, the rows.
function screens.list(width)
	local rows, shown = container_rows()
	local cols = columns(width)
	local count = counts()
	local col = b.div():col():grow(1):min_w(0):min_h(0)
	local bits = { count.running .. " running", count.all .. " total" }
	col:child(P.title("Containers", table.concat(bits, " · "), {
		P.button("act:pull", "Pull…", { key = "u" }),
		P.button("act:clean", "Clean up…", { key = "c" }),
	}))
	col:child(filter_bar(width))
	if S.failure and #S.containers > 0 then
		col:child(
			b.div():row():items_center():gap(8):h(26):px(20):no_shrink():bg(alpha("error", 0.1)):child(
				T(
					"Docker is not reachable: " .. S.failure.message .. " — this is the list as it was.",
					"error",
					SIZE.small
				):truncate()
			)
		)
	end
	if #rows == 0 then
		col:child(nothing_listed(shown))
		return col
	end
	col:child(header_row(cols))
	col:child(virtual("list", #rows, SIZE.row, function(index)
		local row = rows[index]
		if row.kind == "group" then
			return group_row(row)
		end
		return container_row(row, cols)
	end, { px = 10 }))
	return col
end

-- ---- the detail of a container -------------------------------------------------------------------

-- What the exit code of a container that stopped says, when it says a signal's.
local SIGNALS = {
	[129] = "SIGHUP",
	[130] = "SIGINT (⌃C)",
	[131] = "SIGQUIT",
	[134] = "SIGABRT",
	[137] = "SIGKILL: killed, or out of memory",
	[139] = "SIGSEGV: a crash",
	[141] = "SIGPIPE",
	[143] = "SIGTERM: asked to stop",
}

local SECRET = { "PASS", "SECRET", "TOKEN", "KEY", "PWD", "CREDENTIAL", "AUTH", "PRIVATE", "SALT", "SIGNATURE" }

-- Whether an environment variable looks like it holds a secret: by its name, or a password in a URL.
local function secret_like(key, value)
	local upper = string.upper(key)
	for _, word in ipairs(SECRET) do
		if string.find(upper, word, 1, true) then
			return true
		end
	end
	return string.find(value, "://[^/@%s]+:[^/@%s]+@") ~= nil
end

-- The detail of the container that is open, as the program told it (or nil while it has not).
local function detail_data()
	local slot = S.open and S.details[S.open]
	return slot and slot.data, slot
end

local function lines_of_text(content, role, size)
	return T(content, role, size or SIZE.body):truncate()
end

-- The verbs of one container, as a row of buttons.
local function verbs_row(c, narrow)
	local up = is_up(c)
	local busy = S.busy[c.id] ~= nil
	local function key(letter)
		return (not narrow) and letter or nil
	end
	local row = b.div():row():items_center():gap(6):px(18):h(34):no_shrink()
	row:child(P.button("d:toggle", up and "Stop" or "Start", { key = key("s"), disabled = busy, primary = not up }))
	row:child(P.button("d:restart", "Restart", { key = key("r"), disabled = busy }))
	row:child(
		P.button("d:pause", c.state == "paused" and "Resume" or "Pause", { key = key("p"), disabled = busy or not up })
	)
	row:child(P.button("d:shell", "Shell", { key = key("e"), disabled = c.state ~= "running" }))
	if not narrow then
		row:child(P.button("d:follow", "Follow log", { key = "F" }))
	end
	row:child(b.spacer())
	row:child(P.button("d:remove", "Remove…", { danger = true, key = key("d"), disabled = busy }))
	return row
end

-- The charts of a running container, and what it has used.
local function usage_cards(c, wide)
	local sample = S.samples[c.short]
	local series = S.series[c.short] or { cpu = {}, memory = {}, net_in = {}, net_out = {} }
	local function card(title, value, sub, line, role, ceiling)
		return P.card()
			:child(T(string.upper(title), "quiet", SIZE.tiny + 0.5, 600))
			:child(T(value, "foreground", 18, 650):truncate())
			:child(T(sub, "dim", SIZE.small):truncate())
			:child(b.div():h(40):mt(4):child(P.spark(line, role, ceiling)))
	end
	local running = c.state == "running" and sample ~= nil
	local cpu = running
			and card(
				"CPU",
				fmt.percent(sample.cpu),
				"of one processor",
				series.cpu,
				"accent",
				math.max(100, sample.cpu)
			)
		or card("CPU", "–", c.state == "running" and "waiting for a reading" or "not running", {}, "accent")
	local limit = sample and sample.memory_limit or 0
	local memory = running
			and card(
				"Memory",
				fmt.bytes(sample.memory),
				limit > 0 and (string.format("%.1f%%", sample.memory / limit * 100) .. " of " .. fmt.bytes(limit))
					or "no limit",
				series.memory,
				"info",
				limit > 0 and limit or nil
			)
		or card("Memory", "–", c.state == "running" and "waiting for a reading" or "not running", {}, "info")
	local network = running
			and card(
				"Network",
				"↓ " .. fmt.rate(sample.net_in),
				"↑ " .. fmt.rate(sample.net_out),
				series.net_in,
				"success"
			)
		or card("Network", "–", "", {}, "success")
	local disk = running
			and card(
				"Disk · processes",
				"r " .. fmt.rate(sample.disk_read),
				"w " .. fmt.rate(sample.disk_write) .. " · " .. sample.pids .. " procs",
				{},
				"warning"
			)
		or card("Disk · processes", "–", "", {}, "warning")
	local grid = b.div():col():gap(8):no_shrink()
	if wide then
		local function half(card)
			return b.div():col():w(0):grow(1):min_w(0):child(card)
		end
		grid:child(b.div():row():gap(8):child(half(cpu)):child(half(memory)))
		grid:child(b.div():row():gap(8):child(half(network)):child(half(disk)))
	else
		grid:child(cpu):child(memory):child(network):child(disk)
	end
	return grid
end

-- Why a container that is not running is not.
local function why_stopped(c, data)
	if is_up(c) or data == nil then
		return nil
	end
	local state = data.state
	local card = P.card():gap(3)
	local role = (state.exit_code ~= 0 or state.oom_killed) and "error" or "dim"
	card:child(T("WHY IT STOPPED", "quiet", SIZE.tiny + 0.5, 600))
	if state.oom_killed then
		card:child(T("It ran out of memory and was killed.", "error", SIZE.body, 600))
	end
	local words = state.exit_code == 0 and "Exited normally (code 0)" or ("Exited with code " .. state.exit_code)
	if SIGNALS[state.exit_code] then
		words = words .. " · " .. SIGNALS[state.exit_code]
	end
	card:child(T(words, role, SIZE.body, 500):truncate())
	if state.error ~= "" then
		card:child(T(state.error, "error", SIZE.small):truncate())
	end
	local when = state.finished_at and ago(state.finished_at)
	if when then
		card:child(T("Stopped " .. when, "dim", SIZE.small))
	end
	return card
end

-- What the health checks of a container say.
local function health_card(data)
	local health = data.state.health
	if health == nil then
		return nil
	end
	local role = health.status == "healthy" and "success" or (health.status == "unhealthy" and "error" or "warning")
	local card = P.card():gap(3)
	card:child(
		b.div()
			:row()
			:items_center()
			:gap(8)
			:child(T("HEALTH", "quiet", SIZE.tiny + 0.5, 600))
			:child(P.tag(health.status, role))
	)
	if health.failing_streak > 0 then
		card:child(T(fmt.count(health.failing_streak, "check") .. " in a row failed", "error", SIZE.small))
	end
	if data.healthcheck then
		card:child(T(table.concat(data.healthcheck, " "), "dim", SIZE.small):truncate())
	end
	for index = #health.log, math.max(#health.log - 3, 1), -1 do
		local entry = health.log[index]
		local output = string.gsub(entry.output or "", "%s+", " ")
		card:child(
			b.div()
				:row()
				:gap(8)
				:child(
					T(
						entry.exit_code == 0 and "✓" or "✗",
						entry.exit_code == 0 and "success" or "error",
						SIZE.small
					):no_shrink()
				)
				:child(T(output ~= "" and output or ("exit code " .. entry.exit_code), "dim", SIZE.small):truncate())
		)
	end
	return card
end

local function port_text(port)
	if port.public then
		return string.format("%s:%d → %d/%s", port.ip or "*", port.public, port.private, port.type)
	end
	return string.format("%d/%s (not published)", port.private, port.type)
end

-- The overview: what it uses, why it stopped, what it is made of.
local function overview(c, w)
	local data = detail_data()
	local wide = w >= 400
	local body = b.div():col():gap(8):px(18):pt(4):pb(20)
	body:child(usage_cards(c, wide))
	local stopped = why_stopped(c, data)
	if stopped then
		body:child(stopped)
	end
	if data == nil then
		local slot = S.details[c.id]
		body:child(
			T(slot and slot.error or "Reading the container…", slot and slot.error and "error" or "dim", SIZE.small):mt(
				10
			)
		)
		return body
	end
	local health = health_card(data)
	if health then
		body:child(health)
	end
	body:child(P.heading("Container"))
	body:child(P.fact("image", data.image))
	local command = (#data.entrypoint > 0 and table.concat(data.entrypoint, " ") .. " " or "")
		.. table.concat(data.cmd, " ")
	body:child(P.fact("command", command ~= "" and command or (data.path .. " " .. table.concat(data.args, " "))))
	body:child(P.fact("created", data.created and (ago(data.created) or "–") or "–"))
	if data.state.running and data.state.started_at then
		body:child(P.fact("started", ago(data.state.started_at) or "–"))
	end
	body:child(P.fact("restarts", data.restart_count .. " · policy " .. data.restart_policy))
	body:child(P.fact("platform", data.platform ~= "" and data.platform or "–"))
	if data.user ~= "" then
		body:child(P.fact("user", data.user))
	end
	if data.working_dir ~= "" then
		body:child(P.fact("working dir", data.working_dir))
	end
	if data.memory_limit > 0 or data.cpu_limit > 0 then
		body:child(
			P.fact(
				"limits",
				(data.memory_limit > 0 and (fmt.bytes(data.memory_limit) .. " memory") or "")
					.. (data.memory_limit > 0 and data.cpu_limit > 0 and " · " or "")
					.. (data.cpu_limit > 0 and (data.cpu_limit .. " cpus") or "")
			)
		)
	end
	if data.privileged then
		body:child(P.fact("privileged", "yes", "warning"))
	end
	if #data.ports > 0 then
		body:child(P.heading("Ports"))
		for _, port in ipairs(data.ports) do
			body:child(lines_of_text(port_text(port), port.public and "foreground" or "dim"))
		end
	end
	if #data.networks > 0 then
		body:child(P.heading("Networks"))
		for _, network in ipairs(data.networks) do
			local aliases = #network.aliases > 0 and (" · " .. table.concat(network.aliases, ", ")) or ""
			body:child(
				b.div()
					:row()
					:gap(10)
					:child(T(network.name, "foreground", SIZE.body, 600):no_shrink())
					:child(T(network.ip .. aliases, "dim", SIZE.small + 0.5):truncate())
			)
		end
	end
	if #data.mounts > 0 then
		body:child(P.heading("Mounts"))
		for _, mount in ipairs(data.mounts) do
			body:child(
				b.div():row():gap(8):child(P.tag(mount.type, "info")):child(
					T(
						(mount.name or mount.source)
							.. " → "
							.. mount.destination
							.. (mount.rw and "" or "  read-only"),
						"foreground",
						SIZE.small + 0.5
					):truncate()
				)
			)
		end
	end
	local keys = {}
	for key in pairs(data.labels) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	if #keys > 0 then
		body:child(
			P.heading(
				"Labels",
				P.button(
					"d:labels",
					S.show_labels and "Hide" or ("Show " .. #keys),
					{ h = 20, px = 7, size = SIZE.small }
				)
			)
		)
		if S.show_labels then
			for index, key in ipairs(keys) do
				if index > LABELS_MOST then
					body:child(T("and " .. (#keys - LABELS_MOST) .. " more", "quiet", SIZE.small))
					break
				end
				body:child(P.fact(fmt.cut(key, 18), data.labels[key]))
			end
		end
	end
	return body
end

-- The environment: the variables, with what looks secret hidden until asked for.
local function environment(c)
	local data = detail_data()
	if data == nil then
		return b.div():px(18):child(T("Reading the container…", "dim", SIZE.small))
	end
	if #data.env == 0 then
		return P.nothing("It has no environment variables")
	end
	local body = b.div():col():gap(1):px(18):pt(4):pb(20)
	body:child(
		b.div()
			:row()
			:items_center()
			:gap(8)
			:h(30)
			:child(T(fmt.count(#data.env, "variable"), "dim", SIZE.small))
			:child(b.spacer())
			:child(
				P.button(
					"d:secrets",
					S.show_secrets and "Hide secrets" or "Show secrets",
					{ key = "v", h = 22, px = 8, size = SIZE.small }
				)
			)
	)
	for index, entry in ipairs(data.env) do
		if index > ENV_MOST then
			body:child(T("and " .. (#data.env - ENV_MOST) .. " more", "quiet", SIZE.small):mt(4))
			break
		end
		local hidden = secret_like(entry.key, entry.value) and not S.show_secrets and not S.revealed_env[entry.key]
		local id = "env:" .. entry.key
		body:child(
			b.div()
				:press(id)
				:row()
				:gap(14)
				:items_center()
				:h(24)
				:px(6)
				:rounded(5)
				:bg(hovered(id) and alpha("foreground", 0.05) or nil)
				:child(b.div():w(170):no_shrink():child(P.line(entry.key, "info", SIZE.small + 0.5, 600)))
				:child(
					b.div():grow(1):min_w(0):child(
						P.line(
							hidden and "••••••••  (click to show)" or entry.value,
							hidden and "quiet" or "foreground",
							SIZE.small + 0.5
						)
					)
				)
		)
	end
	return body
end

-- The processes: what `docker top` says, refreshed while it is looked at.
local function processes_tab(c)
	local slot = S.processes
	if c.state ~= "running" then
		return P.nothing("It is not running", "A container that is stopped has no processes.")
	end
	if slot.id ~= c.id or slot.titles == nil then
		return b.div()
			:px(18)
			:child(T(slot.error or "Looking at the processes…", slot.error and "error" or "dim", SIZE.small))
	end
	local body = b.div():col():gap(1):px(18):pt(4):pb(20)
	local widths = { 64, 80, 70 }
	local function cells(list, head)
		local row = b.div():row():gap(12):items_center():h(head and 24 or 22)
		for index, text in ipairs(list) do
			local last = index == #list
			local cell = b.div()
			if last then
				cell:grow(1):min_w(0)
			else
				cell:w(widths[index] or 80):no_shrink()
			end
			row:child(
				cell:child(
					P.line(
						text,
						head and "quiet" or "foreground",
						head and SIZE.tiny + 0.5 or SIZE.small + 0.5,
						head and 600 or 400
					)
				)
			)
		end
		return row
	end
	local titles = {}
	for index, title in ipairs(slot.titles) do
		titles[index] = title
	end
	body:child(cells(titles, true))
	for index, row in ipairs(slot.rows) do
		if index > PROCESSES_MOST then
			body:child(T("and " .. (#slot.rows - PROCESSES_MOST) .. " more", "quiet", SIZE.small):mt(4))
			break
		end
		body:child(cells(row, false))
	end
	body:child(T(fmt.count(#slot.rows, "process") .. " · refreshed while you look", "quiet", SIZE.tiny + 0.5):mt(8))
	return body
end

-- One line of the engine's answer, with the parts of it a person looks for in their own colours.
local function inspect_line(text)
	local indent, key, colon, value = string.match(text, '^(%s*)("[^"]*")(:%s*)(.*)$')
	if key == nil then
		local indent_only, rest = string.match(text, "^(%s*)(.*)$")
		return b.div():row():child(T(indent_only .. rest, "dim", SIZE.small + 0.5):no_shrink())
	end
	local role = "foreground"
	if string.sub(value, 1, 1) == '"' then
		role = "success"
	elseif string.match(value, "^%-?%d") then
		role = "warning"
	elseif string.match(value, "^true") or string.match(value, "^false") or string.match(value, "^null") then
		role = "magenta"
	end
	return b.div()
		:row()
		:child(T(indent .. key, "info", SIZE.small + 0.5):no_shrink())
		:child(T(colon, "dim", SIZE.small + 0.5):no_shrink())
		:child(T(value, role, SIZE.small + 0.5):truncate())
end

local function inspect_tab(c)
	local data = detail_data()
	if data == nil then
		return b.div():px(18):child(T("Reading the container…", "dim", SIZE.small))
	end
	local lines = data.lines
	return virtual("detail.inspect", #lines, 17, function(index)
		return b.div():h(17):no_shrink():row():items_center():child(inspect_line(lines[index]))
	end, { px = 18, pt = 4 })
end

-- ---- a container's log -----------------------------------------------------------------------------

-- The runs of line `index` as colours, kept while the line is near the window.
local function log_runs(index)
	local cached = L.runs[index]
	if cached then
		return cached
	end
	if L.run_count > 800 then
		L.runs, L.run_count = {}, 0
	end
	local text = L.texts[index]
	local runs = ansi.runs(text)
	if #runs == 1 and runs[1].fg == nil then
		local level = ansi.level(text)
		if level then
			runs[1].fg = level
		end
	end
	L.runs[index] = runs
	L.run_count += 1
	return runs
end

-- The runs of a line without its first `n` characters: a log read further to the right.
local function shift_runs(runs, n)
	local out = {}
	for _, run in ipairs(runs) do
		local length = utf8.len(run.text) or #run.text
		if n >= length then
			n -= length
		else
			local text = run.text
			if n > 0 then
				text = string.sub(text, utf8.offset(text, n + 1) or (n + 1))
			end
			n = 0
			out[#out + 1] = { text = text, fg = run.fg, bold = run.bold, dim = run.dim, underline = run.underline }
		end
	end
	return out
end

-- One line of the log as a row of the runs it is in.
local function log_line(index, current)
	local err = string.byte(L.streams, index) == 101
	local matched = L.query_on and L.match_set and L.match_set[index]
	local row = b.div():row():items_center():gap(8):h(SIZE.line):px(14):clip():no_shrink()
	if current then
		row:bg(alpha("warning", 0.28))
	elseif matched then
		row:bg(alpha("warning", 0.13))
	end
	row:child(b.div():w(3):h(SIZE.line - 5):rounded(1.5):no_shrink():bg(err and "error" or nil))
	if L.timestamps then
		row:child(T(L.clocks[index] or "", "quiet", SIZE.small + 0.5):no_shrink())
	end
	local words = b.div():row():items_center():no_shrink()
	local shown = log_runs(index)
	if L.hscroll > 0 then
		shown = shift_runs(shown, L.hscroll)
		row:child(T("‹", "quiet", SIZE.small + 0.5):no_shrink())
	end
	for _, run in ipairs(shown) do
		local role = run.fg
		if run.dim then
			role = "dim"
		end
		words:child(T(run.text, role, SIZE.small + 0.5, run.bold and 700 or nil):no_shrink())
	end
	row:child(words)
	return row
end

-- Looks through the lines the query has not been tried on, so many at a time (a log can be
-- a hundred thousand lines, and a call of the page is held to a quarter of a second). True while
-- there is more to look through.
local function scan_log(budget)
	local query = L.query_on and S.query or ""
	if query ~= L.scanned_for then
		L.scanned_for, L.matches, L.scanned, L.match_at, L.match_set = query, {}, 0, 0, {}
		L.pinned_match = false
	end
	if query == "" then
		return false
	end
	local last = math.min(L.count, L.scanned + budget)
	local matches, set = L.matches, L.match_set
	for index = L.scanned + 1, last do
		if fmt.has(ansi.strip(L.texts[index]), query) then
			matches[#matches + 1] = index
			set[index] = true
		end
	end
	L.scanned = last
	-- Until the person goes through the matches, the one on show is the latest: what a log is
	-- searched for is most often what happened last.
	if not L.pinned_match and #matches > 0 and L.match_at ~= #matches then
		L.match_at = #matches
		L.follow = false
		ui:set_scroll("log", math.max((matches[#matches] - 1) * SIZE.line - (views.log or 400) / 2, 0))
	end
	return L.scanned < L.count
end

-- The bar over a log: follow, timestamps, the search and what it found. In a narrow place the
-- search has a row of its own.
local function log_toolbar(width)
	local narrow = width < 600
	local small = { h = 24, size = SIZE.small + 0.5 }
	local function button(id, label, key, extra)
		local options =
			{ h = small.h, size = small.size, selected = extra and extra.selected, key = (not narrow) and key or nil }
		return P.button(id, label, options)
	end
	local top = b.div():row():items_center():gap(8):h(narrow and 34 or 40):px(18):no_shrink()
	top:child(button("l:follow", L.follow and "Following" or "Follow", "End", { selected = L.follow }))
	top:child(button("l:time", "Timestamps", "t", { selected = L.timestamps }))
	local search = b.div():row():items_center():gap(8):w(0):grow(1):min_w(0)
	search:child(P.field(S.field == "logs", "Search the log", nil))
	if L.query_on and S.query ~= "" then
		local total = #L.matches
		local note = total == 0 and (L.scanned < L.count and "looking…" or "no match")
			or (string.format("%d of %d", math.max(L.match_at, 1), total) .. (L.scanned < L.count and "+" or ""))
		search:child(T(note, total == 0 and "dim" or "foreground", SIZE.small):no_shrink())
		search:child(P.button("l:prev", "Prev", { h = 22, px = 8, size = SIZE.small, disabled = total == 0 }))
		search:child(P.button("l:next", "Next", { h = 22, px = 8, size = SIZE.small, disabled = total == 0 }))
	end
	if narrow then
		top:child(b.spacer())
		if L.count >= L.tail and L.tail < LOG_MOST then
			top:child(P.button("l:more", "Load more", { h = 22, px = 8, size = SIZE.small }))
		end
		top:child(T(fmt.count(L.count, "line"), "quiet", SIZE.small):no_shrink())
		return b.div():col():no_shrink():child(top):child(b.div():row():items_center():h(34):px(18):child(search))
	end
	top:child(search)
	if L.count >= L.tail and L.tail < LOG_MOST then
		top:child(P.button("l:more", "Load more", { key = "L", h = 22, px = 8, size = SIZE.small }))
	end
	top:child(T(fmt.count(L.count, "line"), "quiet", SIZE.small):no_shrink())
	return top
end

local function log_tab(c, width)
	local box = b.div():col():grow(1):min_h(0)
	box:child(log_toolbar(width))
	box:child(b.div():h(1):bg(alpha("border", 0.6)):no_shrink())
	if L.id ~= c.id then
		return box:child(P.nothing("Opening the log…"))
	end
	if L.count == 0 then
		local words = L.ended and (L.ended.message ~= "" and L.ended.message or "The log has ended.")
			or "It has written nothing yet."
		return box:child(P.nothing(words, L.ended == nil and "Lines show here as the container writes them." or nil))
	end
	local view = views.log or 400
	if L.follow then
		ui:set_scroll("log", math.max(L.count * SIZE.line + 8 - view, 0))
	end
	local current = L.matches[L.match_at]
	box:child(virtual("log", L.count, SIZE.line, function(index)
		return log_line(index, index == current)
	end, { px = 0, pt = 4 }))
	local footer = nil
	if not L.follow and L.new_since > 0 then
		footer = T("↓ " .. fmt.count(L.new_since, "new line") .. " — End follows", "accent", SIZE.small)
	elseif L.ended and not log_live() then
		footer = T(
			c.state == "running" and "The log stopped here." or "It is not running: the log does not go on.",
			"dim",
			SIZE.small
		)
	end
	if footer then
		box:child(b.div():row():items_center():h(22):px(18):no_shrink():bg("raised1"):child(footer))
	end
	return box
end

-- ---- the detail, as a whole --------------------------------------------------------------------------

function screens.detail(width, beside)
	local c = container(S.open)
	if c == nil then
		return b.div():grow(1)
	end
	local word, role = state_of(c)
	local panel = b.div():col():grow(1):min_w(0):min_h(0)
	if beside then
		panel:bg("raised1"):border(1, alpha("border", 0.7))
	end
	local head = b.div():row():items_center():gap(10):h(46):px(18):no_shrink()
	head:child(P.state_dot(c))
	head:child(b.div():grow(1):min_w(0):child(P.line(c.name, "foreground", 16, 650)))
	head:child(P.tag(word, role))
	head:child(P.button("d:close", beside and "Close" or "Back", { key = "Esc", h = 24, size = SIZE.small + 0.5 }))
	panel:child(head)
	local sub = {}
	sub[#sub + 1] = c.image
	sub[#sub + 1] = c.short
	if c.project then
		sub[#sub + 1] = c.project .. (c.service and (" / " .. c.service) or "")
	end
	panel:child(b.div():px(18):h(18):no_shrink():child(P.line(table.concat(sub, "  ·  "), "dim", SIZE.small + 0.5)))
	panel:child(b.div():h(6):no_shrink())
	panel:child(verbs_row(c, width < 560))
	panel:child(b.div():h(6):no_shrink())
	panel:child(P.tabs(TABS, S.tab, "tab:"))
	panel:child(b.div():h(1):bg(alpha("border", 0.6)):no_shrink())
	if S.tab == "logs" then
		return panel:child(log_tab(c, width))
	elseif S.tab == "inspect" then
		return panel:child(inspect_tab(c))
	end
	local content
	if S.tab == "env" then
		content = environment(c)
	elseif S.tab == "processes" then
		content = processes_tab(c)
	else
		content = overview(c, width)
	end
	panel:child(
		b.div()
			:col()
			:id("detail.scroll")
			:grow(1)
			:min_h(0)
			:scroll_y(ui:scroll_offset("detail.scroll"))
			:child(b.div():col():no_shrink():child(content))
	)
	return panel
end

-- ---- images, volumes, networks: lists of what containers are made of -----------------------------------

-- A list with one row for each of what `spec` says: its columns and its verb.
local function plain_screen(section, spec, width)
	local rows = plain_rows(section)
	local col = b.div():col():grow(1):min_w(0):min_h(0)
	col:child(P.title(spec.title, spec.subtitle(), spec.verbs))
	local bar = b.div():row():items_center():gap(8):h(SIZE.bar):px(20):no_shrink()
	bar:child(P.field(S.field == "list", spec.hint, width >= 700 and 260 or nil))
	bar:child(b.spacer())
	local chosen = marked(section)
	if #chosen > 0 then
		bar:child(T(#chosen .. " marked", "accent", SIZE.small + 0.5))
		bar:child(P.button("act:remove", "Remove…", { danger = true, key = "d", h = 24, size = SIZE.small + 0.5 }))
	end
	col:child(bar)
	if S.problems[section] then
		col:child(
			b.div()
				:row()
				:items_center()
				:h(26)
				:px(20)
				:no_shrink()
				:bg(alpha("error", 0.1))
				:child(T(S.problems[section], "error", SIZE.small):truncate())
		)
	end
	if S.lists[section] == nil and not S.problems[section] then
		return col:child(P.nothing("Looking…"))
	end
	if #rows == 0 then
		if S.query ~= "" then
			return col:child(P.nothing("Nothing matches “" .. S.query .. "”"))
		end
		return col:child(P.nothing(spec.empty))
	end
	local columns = spec.columns(width)
	local header = b.div():row():items_center():gap(10):h(24):px(18):no_shrink()
	header:child(b.div():w(COL.check):no_shrink())
	for _, column in ipairs(columns) do
		local cell = b.div():no_shrink()
		if column.width then
			cell:w(column.width)
		else
			cell:w(0):grow(column.grow or 1):min_w(40)
		end
		header:child(
			cell:child(
				T(string.upper(column.label), "quiet", SIZE.tiny + 0.5, 600):align(column.align or "start"):truncate()
			)
		)
	end
	header:child(b.div():w(COL.verb):no_shrink())
	col:child(header)
	col:child(virtual("list", #rows, SIZE.row, function(index)
		local row = rows[index]
		local id = "row:" .. row.id
		local cursor = S.cursor[section] == row.id
		local verb_id = "verb:" .. row.id
		local over = hovered(id) or hovered(verb_id) or hovered("mark:" .. row.id)
		local el = b.div():press(id):row():items_center():gap(10):h(SIZE.row):px(10):rounded(7):no_shrink()
		if cursor then
			el:bg(alpha("accent", 0.14)):border(1, alpha("accent", 0.55))
		elseif over then
			el:bg(alpha("foreground", 0.055))
		end
		local tick = b.div():press("mark:" .. row.id):w(COL.check):no_shrink()
		local on = S.marks[section] and S.marks[section][row.id]
		if on or over or cursor or S.any_marked then
			tick:child(P.check(on))
		end
		el:child(tick)
		for _, column in ipairs(columns) do
			local cell = b.div():no_shrink():row():items_center()
			if column.width then
				cell:w(column.width)
			else
				cell:w(0):grow(column.grow or 1):min_w(40)
			end
			if column.align == "end" then
				cell:justify_end()
			end
			el:child(cell:child(column.make(row.item)))
		end
		local verb = b.div():w(COL.verb):no_shrink():row():justify_end()
		if (cursor or over) and spec.verb_for(row.item) then
			verb:child(P.button(verb_id, spec.verb_for(row.item), { h = 22, px = 8, size = SIZE.small + 0.5 }))
		end
		return el:child(verb)
	end, { px = 10 }))
	return col
end

local function used_by(names, none)
	if #names == 0 then
		return P.line(none or "unused", "quiet", SIZE.small + 0.5)
	end
	local text = names[1]
	if #names > 1 then
		text = text .. "  +" .. (#names - 1)
	end
	return P.line(text, "foreground", SIZE.small + 0.5)
end

function screens.images(width)
	local images = S.lists.images or {}
	local unused = 0
	for _, image in ipairs(images) do
		if #image.containers == 0 then
			unused += 1
		end
	end
	return plain_screen("images", {
		title = "Images",
		hint = "Filter by name, id, container…",
		subtitle = function()
			return fmt.count(#images, "image") .. " · " .. unused .. " unused"
		end,
		verbs = {
			P.button("act:pull", "Pull…", { key = "u" }),
			P.button("act:clean", "Clean up…", { key = "c" }),
		},
		empty = "There are no images",
		verb_for = function()
			return "Remove…"
		end,
		columns = function(w)
			local list = {
				{
					label = "Image",
					grow = 2,
					make = function(image)
						local first = image.tags[1] or "<none>"
						local el = b.div():row():items_center():gap(8):min_w(0)
						el:child(P.line(first, image.dangling and "dim" or "foreground", SIZE.body, 600))
						if #image.tags > 1 then
							el:child(T("+" .. (#image.tags - 1), "quiet", SIZE.small):no_shrink())
						end
						if image.dangling then
							el:child(P.tag("dangling", "warning"))
						end
						return el
					end,
				},
				{
					label = "Size",
					width = 84,
					align = "end",
					make = function(image)
						return T(fmt.disk(image.size), "foreground", SIZE.small + 0.5)
					end,
				},
				{
					label = "Made",
					width = 74,
					align = "end",
					make = function(image)
						return T(image.created and (ago(image.created) or "–") or "–", "dim", SIZE.small + 0.5)
					end,
				},
				{
					label = "Used by",
					grow = 1.4,
					make = function(image)
						return b.div():pl(8):min_w(0):child(used_by(image.containers))
					end,
				},
			}
			if w >= LIST_MEDIUM then
				table.insert(list, 2, {
					label = "Id",
					width = 100,
					make = function(image)
						return P.line(image.id, "quiet", SIZE.small + 0.5)
					end,
				})
			end
			return list
		end,
	}, width)
end

function screens.volumes(width)
	local volumes = S.lists.volumes or {}
	local unused = 0
	for _, volume in ipairs(volumes) do
		if #volume.containers == 0 then
			unused += 1
		end
	end
	return plain_screen("volumes", {
		title = "Volumes",
		hint = "Filter by name, project…",
		subtitle = function()
			return fmt.count(#volumes, "volume") .. " · " .. unused .. " unused"
		end,
		verbs = { P.button("act:clean", "Clean up…", { key = "c" }) },
		empty = "There are no volumes",
		verb_for = function()
			return "Remove…"
		end,
		columns = function(w)
			local list = {
				{
					label = "Name",
					grow = 2,
					make = function(volume)
						local el = b.div():row():items_center():gap(8):min_w(0)
						el:child(
							P.line(
								volume.anonymous and fmt.cut(volume.name, 14) or volume.name,
								"foreground",
								SIZE.body,
								600
							)
						)
						if volume.anonymous then
							el:child(P.tag("anonymous", "dim"))
						end
						if volume.project then
							el:child(P.tag(volume.project, "info"))
						end
						return el
					end,
				},
				{
					label = "Size",
					width = 84,
					align = "end",
					make = function(volume)
						local size = S.volume_sizes and S.volume_sizes[volume.name]
						return T(
							size and fmt.disk(size) or (S.volume_sizes and "–" or "counting…"),
							size and "foreground" or "quiet",
							SIZE.small + 0.5
						)
					end,
				},
				{
					label = "Used by",
					grow = 1.4,
					make = function(volume)
						return used_by(volume.containers)
					end,
				},
			}
			if w >= LIST_MEDIUM then
				table.insert(list, 2, {
					label = "Driver",
					width = 70,
					make = function(volume)
						return P.line(volume.driver, "dim", SIZE.small + 0.5)
					end,
				})
			end
			return list
		end,
	}, width)
end

function screens.networks(width)
	local networks = S.lists.networks or {}
	return plain_screen("networks", {
		title = "Networks",
		hint = "Filter by name, subnet…",
		subtitle = function()
			return fmt.count(#networks, "network")
		end,
		verbs = { P.button("act:clean", "Clean up…", { key = "c" }) },
		empty = "There are no networks",
		verb_for = function(network)
			return (not network.builtin) and "Remove…" or nil
		end,
		columns = function(w)
			local list = {
				{
					label = "Name",
					grow = 2,
					make = function(network)
						local el = b.div():row():items_center():gap(8):min_w(0)
						el:child(P.line(network.name, "foreground", SIZE.body, 600))
						if network.builtin then
							el:child(P.tag("built in", "dim"))
						end
						if network.internal then
							el:child(P.tag("internal", "warning"))
						end
						if network.project then
							el:child(P.tag(network.project, "info"))
						end
						return el
					end,
				},
				{
					label = "Containers",
					grow = 1.6,
					make = function(network)
						return used_by(network.containers, "none")
					end,
				},
			}
			if w >= LIST_MEDIUM then
				table.insert(list, 2, {
					label = "Subnet",
					width = 150,
					make = function(network)
						return P.line(network.subnets[1] or "–", "dim", SIZE.small + 0.5)
					end,
				})
				table.insert(list, 2, {
					label = "Driver",
					width = 70,
					make = function(network)
						return P.line(network.driver, "dim", SIZE.small + 0.5)
					end,
				})
			end
			return list
		end,
	}, width)
end

-- The layers of an image: what made each, and how much it takes.
function screens.layers(width)
	local image
	for _, one in ipairs(S.lists.images or {}) do
		if one.id == S.layer_open then
			image = one
		end
	end
	local col = b.div():col():grow(1):min_w(0):min_h(0)
	if image == nil then
		return col:child(P.nothing("That image is gone"))
	end
	col:child(
		P.title(
			image_title(image),
			fmt.disk(image.size) .. " · " .. #image.tags .. " " .. (#image.tags == 1 and "tag" or "tags"),
			{
				P.button("layers:update", "Update", { key = "u", disabled = image.dangling }),
				P.button("layers:remove", "Remove…", { danger = true, key = "d" }),
				P.button("layers:back", "Back", { key = "Esc" }),
			}
		)
	)
	local layers = S.layers[image.id]
	if layers == nil or (layers.list == nil and layers.error == nil) then
		return col:child(P.nothing("Reading the layers…"))
	end
	if layers.error then
		return col:child(P.nothing(layers.error))
	end
	local list = layers.list
	col:child(
		b.div()
			:row()
			:gap(14)
			:px(28)
			:h(24)
			:items_center()
			:no_shrink()
			:child(T("SIZE", "quiet", SIZE.tiny + 0.5, 600):w(80):no_shrink())
			:child(T("MADE BY", "quiet", SIZE.tiny + 0.5, 600))
	)
	col:child(virtual("list", #list, SIZE.row, function(index)
		local layer = list[index]
		local command = string.gsub(layer.created_by, "^/bin/sh %-c #%(nop%) *", "")
		command = string.gsub(command, "^/bin/sh %-c ", "RUN ")
		command = string.gsub(command, "%s+", " ")
		return b.div()
			:row()
			:items_center()
			:gap(14)
			:h(SIZE.row)
			:px(18)
			:no_shrink()
			:child(
				b.div():w(80):no_shrink():child(
					T(
						layer.size > 0 and fmt.disk(layer.size) or "–",
						layer.size > 0 and "foreground" or "quiet",
						SIZE.small + 0.5
					):align("end")
				)
			)
			:child(b.div():grow(1):min_w(0):child(P.line(command, "dim", SIZE.small + 0.5)))
	end, { px = 10 }))
	return col
end

-- ---- the system: the disk docker takes -----------------------------------------------------------------

local DISK = {
	{ key = "images", label = "Images", role = "accent", target = "unused_images", title = "Unused images" },
	{ key = "containers", label = "Containers", role = "success", target = "containers", title = "Stopped containers" },
	{ key = "volumes", label = "Volumes", role = "warning", target = "volumes", title = "Unused volumes" },
	{ key = "build_cache", label = "Build cache", role = "info", target = "build_cache", title = "Build cache" },
}

-- What a clean-up of everything would free, and what it would take away.
local function all_that_can_be_freed()
	local usage = S.system and S.system.usage
	local targets_, titles, freed = {}, {}, 0
	if usage == nil then
		return targets_, titles, 0
	end
	for _, kind in ipairs(DISK) do
		local part = usage[kind.key]
		if part and part.reclaimable > 0 then
			targets_[#targets_ + 1] = kind.target
			titles[#titles + 1] = kind.title .. " (" .. fmt.disk(part.reclaimable) .. ")"
			freed += part.reclaimable
		end
	end
	return targets_, titles, freed
end

function screens.system(width)
	local col = b.div():col():grow(1):min_w(0):min_h(0)
	local engine = (S.system and S.system.engine) or S.engine
	col:child(P.title("System", engine and (engine.name .. " · Docker " .. engine.version) or nil, {
		P.button("act:clean", "Clean up…", { key = "c", primary = true }),
	}))
	local body = b.div():col():gap(10):px(20):pb(20):no_shrink()
	if S.problems.system then
		body:child(T(S.problems.system, "error", SIZE.small))
	end
	local usage = S.system and S.system.usage
	if usage == nil then
		body:child(T(S.problems.system and "" or "Counting the disk…", "dim", SIZE.body))
	else
		local total, freed = 0, 0
		for _, kind in ipairs(DISK) do
			total += usage[kind.key].size
			freed += usage[kind.key].reclaimable
		end
		local summary = P.card():gap(10)
		summary:child(
			b.div()
				:row()
				:items_center()
				:gap(10)
				:child(T("DISK", "quiet", SIZE.tiny + 0.5, 600))
				:child(T(fmt.disk(total), "foreground", 20, 650))
				:child(T(fmt.disk(freed) .. " can be freed", freed > 0 and "success" or "dim", SIZE.body))
		)
		local bar = b.div():row():h(10):rounded(5):clip():gap(1):bg("raised2")
		for _, kind in ipairs(DISK) do
			local size = usage[kind.key].size
			if size > 0 then
				bar:child(b.div():w(0):grow(size):h(10):bg(kind.role))
			end
		end
		summary:child(bar)
		local legend = b.div():row():gap(14):wrap()
		for _, kind in ipairs(DISK) do
			legend:child(
				b.div()
					:row()
					:items_center()
					:gap(6)
					:child(P.dot(kind.role, true, 8))
					:child(T(kind.label, "dim", SIZE.small))
			)
		end
		summary:child(legend)
		body:child(summary)
		local cards = b.div():row():gap(8):wrap()
		for _, kind in ipairs(DISK) do
			local part = usage[kind.key]
			local id = "free:" .. kind.target
			cards:child(
				P.card()
					:w(0)
					:grow(1)
					:min_w(170)
					:gap(6)
					:child(
						b.div()
							:row()
							:items_center()
							:gap(8)
							:child(P.dot(kind.role, true, 8))
							:child(T(kind.label, "foreground", SIZE.body, 600):no_shrink())
							:child(b.spacer())
							:child(T(part.active .. "/" .. part.count .. " in use", "quiet", SIZE.small):no_shrink())
					)
					:child(T(fmt.disk(part.size), "foreground", 18, 650))
					:child(
						b.div()
							:row()
							:items_center()
							:h(26)
							:child(
								T(
									part.reclaimable > 0 and (fmt.disk(part.reclaimable) .. " unused")
										or "nothing unused",
									"dim",
									SIZE.small
								)
							)
							:child(b.spacer())
							:child(
								P.button(
									id,
									"Free…",
									{ h = 22, px = 8, size = SIZE.small + 0.5, disabled = part.reclaimable == 0 }
								)
							)
					)
			)
		end
		body:child(cards)
	end
	if engine then
		local card = P.card():gap(2)
		card:child(T("ENGINE", "quiet", SIZE.tiny + 0.5, 600))
		card:child(P.fact("runs on", engine.name))
		card:child(P.fact("docker", engine.version))
		card:child(
			P.fact(
				"machine",
				engine.os
					.. "/"
					.. engine.arch
					.. " · "
					.. fmt.count(engine.cpus, "cpu")
					.. " · "
					.. fmt.bytes(engine.memory)
			)
		)
		card:child(P.fact("endpoint", engine.endpoint ~= "" and engine.endpoint or "the docker command's own"))
		local count = counts()
		card:child(P.fact("containers", count.running .. " running of " .. count.all))
		if S.hostname ~= "" then
			card:child(P.fact("dockerpen on", S.hostname .. (S.remote and " (over ssh)" or "")))
		end
		body:child(card)
	end
	return col:child(
		b.div():col():id("system.scroll"):grow(1):min_h(0):scroll_y(ui:scroll_offset("system.scroll")):child(body)
	)
end

-- ---- activity: what the engine reported -----------------------------------------------------------------

local function event_role(item)
	if item.notice == "oom" or item.notice == "died" then
		return "error"
	elseif item.notice == "unhealthy" then
		return "warning"
	elseif item.action == "start" or item.action == "create" or item.action == "unpause" or item.action == "pull" then
		return "success"
	elseif
		item.action == "die"
		or item.action == "stop"
		or item.action == "kill"
		or item.action == "destroy"
		or item.action == "delete"
	then
		return "dim"
	end
	return "info"
end

function screens.activity(width)
	local rows = plain_rows("activity")
	local col = b.div():col():grow(1):min_w(0):min_h(0)
	col:child(P.title("Activity", "what the engine reported since dockerpen looked", {}))
	local bar = b.div():row():items_center():gap(8):h(SIZE.bar):px(20):no_shrink()
	bar:child(P.field(S.field == "list", "Filter by name, kind, action…", width >= 700 and 260 or nil))
	col:child(bar)
	if #rows == 0 then
		return col:child(
			P.nothing(
				"Nothing has happened yet",
				"Containers that start, stop, die or turn unhealthy show here, and as a toast wherever you are."
			)
		)
	end
	col:child(virtual("list", #rows, SIZE.row, function(index)
		local item = rows[index].item
		local id = "row:" .. rows[index].id
		local cursor = S.cursor.activity == rows[index].id
		local role = event_role(item)
		local el = b.div():press(id):row():items_center():gap(10):h(SIZE.row):px(10):rounded(7):no_shrink()
		if cursor then
			el:bg(alpha("accent", 0.14)):border(1, alpha("accent", 0.55))
		elseif hovered(id) then
			el:bg(alpha("foreground", 0.055))
		end
		el:child(
			b.div()
				:w(60)
				:no_shrink()
				:child(T(item.time and (ago(item.time) or "") or "", "quiet", SIZE.small):align("end"))
		)
		el:child(P.dot(role, item.notice ~= nil or item.action == "start", 8))
		el:child(b.div():w(66):no_shrink():child(P.line(item.type, "quiet", SIZE.small + 0.5)))
		el:child(
			b.div()
				:w(0)
				:grow(1)
				:min_w(0)
				:row()
				:gap(8)
				:items_center()
				:child(P.line(item.name or string.sub(item.id or "", 1, 12), "foreground", SIZE.body, 600):no_shrink())
				:child(P.line(item.words or item.action, role == "dim" and "dim" or role, SIZE.small + 0.5))
		)
		return el
	end, { px = 10 }))
	return col
end

-- ---- over everything: the question, the help, the toasts, the jobs -----------------------------------

local overlays = {}

-- A question asked before something is removed. Its buttons are verbs, and the keys that answer
-- are on them.
function overlays.dialog()
	local d = S.dialog
	local card = b.div()
		:col()
		:gap(8)
		:p(18)
		:w(420)
		:max_w(520)
		:rounded(10)
		:bg("raised2")
		:border(1, "border")
		:shadow(0, 8, 24, alpha("shadow", 0.5))
	card:child(T(d.title, "foreground", 15, 650))
	if d.lines and d.lines.names then
		local list = b.div():col():gap(2):p(8):rounded(6):bg("raised1")
		for _, name in ipairs(d.lines.names) do
			list:child(P.line(name, "foreground", SIZE.small + 1))
		end
		card:child(list)
	end
	if d.lines and d.lines.note then
		card:child(T(d.lines.note, "dim", SIZE.small + 0.5):truncate():max_w(380))
	end
	if d.field then
		card:child(T(d.field.label, "dim", SIZE.small))
		card:child(P.field(true, d.field.hint))
	end
	local buttons = b.div():row():justify_end():gap(8):mt(6)
	local cancel = P.button("dialog:cancel", "Cancel", { key = "Esc", selected = d.choice == "cancel" })
	local confirm = P.button("dialog:confirm", d.confirm, {
		key = "y",
		danger = d.danger,
		primary = not d.danger,
		selected = d.choice == "confirm",
		disabled = d.field ~= nil and (d.text or "") == "",
	})
	if d.choice == "cancel" then
		cancel:border(1.5, "accent")
	else
		confirm:border(1.5, "accent")
	end
	buttons:child(cancel):child(confirm)
	card:child(buttons)
	return b.div()
		:absolute()
		:inset(0, 0, 0, 0)
		:row()
		:items_center()
		:justify_center()
		:bg(alpha("background", 0.6))
		:press("dialog:backdrop")
		:child(card)
end

local HELP = {
	{
		"Moving",
		{
			{ "↑ ↓  j k", "choose a row" },
			{ "g G  Home End", "first, last" },
			{ "⏎  →  ←", "open, fold / back" },
			{ "1 – 6", "the sections, from containers to activity" },
			{ "Tab", "list or detail" },
			{ "/", "filter, or search a log" },
		},
	},
	{
		"Containers",
		{
			{ "space  a  A", "mark, mark all, mark none; a project is all its own" },
			{ "s  r  p", "start or stop, restart, pause or resume" },
			{ "e  F", "a shell in it, its log as it comes (in the terminal)" },
			{ "l  i  [ ]", "logs, inspect, the tab before and after" },
			{ "K  d", "kill, remove (both ask first)" },
			{ "f  P  o", "next filter, group by project, sort" },
			{ "y  .", "copy the id, the menu of the row" },
		},
	},
	{
		"A log",
		{
			{ "↑ ↓  PgUp PgDn", "scroll; scrolling up stops following" },
			{ "End  t", "follow, timestamps" },
			{ "n  N", "next match, previous match" },
			{ "⇧←  ⇧→  0", "read further to the right, and back" },
			{ "L", "load more lines" },
		},
	},
	{
		"Everywhere",
		{
			{ "u  c", "pull an image, clean up" },
			{ "?  Esc", "this help, leave what is open" },
			{ "⌃C", "quit dockerpen" },
		},
	},
}

function overlays.help()
	local card = b.div()
		:col()
		:gap(4)
		:p(20)
		:w_pct(92)
		:max_w(660)
		:rounded(10)
		:bg("raised2")
		:border(1, "border")
		:shadow(0, 8, 24, alpha("shadow", 0.5))
	card:child(
		b.div():row():items_center():child(T("Keys", "foreground", 15, 650)):child(b.spacer()):child(P.kbd("Esc"))
	)
	local scroll = b.div():col():gap(2):no_shrink()
	for _, part in ipairs(HELP) do
		scroll:child(P.heading(part[1]))
		for _, entry in ipairs(part[2]) do
			scroll:child(
				b.div()
					:row()
					:gap(14)
					:min_h(20)
					:child(b.div():w(150):no_shrink():child(T(entry[1], "foreground", SIZE.small + 1, 600)))
					:child(b.div():grow(1):min_w(0):child(P.line(entry[2], "dim", SIZE.small + 1)))
			)
		end
	end
	card:child(
		b.div()
			:col()
			:id("help.scroll")
			:h(math.max(math.min(S.height - 200, 440), 120))
			:scroll_y(ui:scroll_offset("help.scroll"))
			:child(scroll)
	)
	card:child(
		T(
			"Everything the pointer does, the keys do too: rows answer a click, ⌘-click or ⇧-click marks, right-click opens the menu of the row.",
			"quiet",
			SIZE.small
		):truncate()
	)
	return b.div()
		:absolute()
		:inset(0, 0, 0, 0)
		:row()
		:items_center()
		:justify_center()
		:bg(alpha("background", 0.6))
		:press("help:backdrop")
		:child(card)
end

-- What was said for a moment, at the end of the page.
function overlays.toasts()
	local stack = b.div():absolute():inset(nil, 16, SIZE.status + 12, nil):col():gap(6):items_end()
	for index, item in ipairs(S.toasts) do
		local id = "toast:" .. index
		local role = item.kind == "info" and "foreground" or item.kind
		local el = b.div()
			:press(id)
			:row()
			:items_center()
			:gap(10)
			:p(10)
			:pl(12)
			:max_w(480)
			:rounded(8)
			:bg("raised3")
			:border(1, alpha(role, 0.55))
			:shadow(0, 4, 14, alpha("shadow", 0.45))
		el:child(b.div():w(3):h(16):rounded(1.5):bg(role):no_shrink())
		el:child(b.div():min_w(0):child(T(item.text, "foreground", SIZE.small + 1):truncate()))
		if item.action then
			el:child(P.button("toast.action:" .. index, item.action.label, { h = 22, px = 8, size = SIZE.small + 0.5 }))
		end
		stack:child(el)
	end
	return stack
end

-- The jobs that are running, as a line of how far each has come.
function overlays.jobs()
	local running = {}
	for _, job in ipairs(S.jobs) do
		if job.state == "running" then
			running[#running + 1] = job
		end
	end
	if #running == 0 then
		return nil
	end
	local strip = b.div():col():gap(4):px(20):py(6):no_shrink():bg("raised1")
	for _, job in ipairs(running) do
		local row = b.div():row():items_center():gap(10):h(18)
		row:child(T(job.title, "foreground", SIZE.small + 0.5, 600):no_shrink())
		row:child(b.div():w(0):grow(1):min_w(0):child(P.line(job.detail or "", "dim", SIZE.small)))
		if job.progress then
			row:child(P.meter(job.progress, "accent", 120))
		else
			row:child(T("working…", "dim", SIZE.small):no_shrink())
		end
		strip:child(row)
	end
	return strip
end

-- ---- the frame: the rail of sections, the keys at the bottom ------------------------------------------

local frame = {}

local function section_badge(id)
	if id == "containers" then
		local n = counts().issues
		if n > 0 then
			return n, "error"
		end
	end
	return nil
end

function frame.rail()
	local rail = b.div():col():w(SIZE.rail):no_shrink():gap(2):px(8):pt(10):pb(10):bg(alpha("foreground", 0.025))
	for _, section in ipairs(SECTIONS) do
		local id = "sec:" .. section.id
		local active = S.section == section.id
		local badge, role = section_badge(section.id)
		local el = b.div():press(id):row():items_center():gap(8):h(30):px(10):rounded(7)
		if active then
			el:bg(alpha("accent", 0.14))
		elseif hovered(id) then
			el:bg(alpha("foreground", 0.06))
		end
		el:child(b.div():w(3):h(14):rounded(1.5):bg(active and "accent" or nil):no_shrink())
		el:child(
			b.div()
				:grow(1)
				:min_w(0)
				:child(P.line(section.label, active and "foreground" or "dim", SIZE.body, active and 650 or 400))
		)
		if badge then
			el:child(P.tag(tostring(badge), role))
		else
			el:child(T(section.key, "quiet", SIZE.tiny + 0.5):no_shrink())
		end
		rail:child(el)
	end
	rail:child(b.spacer())
	local engine = S.engine
	local foot = b.div():col():gap(2):p(8)
	if engine then
		foot:child(
			b.div()
				:row()
				:items_center()
				:gap(7)
				:child(P.dot(S.failure and "error" or "success", true, 7))
				:child(P.line(engine.name, "dim", SIZE.small + 0.5))
		)
		foot:child(P.line("docker " .. engine.version, "quiet", SIZE.small))
		foot:child(P.line(fmt.count(engine.cpus, "cpu") .. " · " .. fmt.bytes(engine.memory), "quiet", SIZE.small))
	elseif S.failure then
		foot:child(
			b.div()
				:row()
				:items_center()
				:gap(7)
				:child(P.dot("error", true, 7))
				:child(P.line("not reachable", "error", SIZE.small + 0.5))
		)
	end
	return rail:child(foot)
end

-- The sections as a strip, where there is no room for the rail.
function frame.strip()
	local strip = b.div():row():items_center():gap(2):h(34):px(10):no_shrink()
	for _, section in ipairs(SECTIONS) do
		local id = "sec:" .. section.id
		local active = S.section == section.id
		local badge, role = section_badge(section.id)
		local el = b.div():press(id):row():items_center():gap(5):h(26):px(9):rounded(6)
		if active then
			el:bg(alpha("accent", 0.14))
		elseif hovered(id) then
			el:bg(alpha("foreground", 0.06))
		end
		el:child(T(section.label, active and "foreground" or "dim", SIZE.small + 1, active and 650 or 400))
		if badge then
			el:child(P.tag(tostring(badge), role))
		end
		strip:child(el)
	end
	return strip
end

-- The keys that do something where the person is.
local function hints()
	local list
	if S.dialog then
		list = { { "y", "yes" }, { "Esc", "no" }, { "Tab", "other answer" } }
	elseif S.help then
		list = { { "Esc", "close" } }
	elseif S.section == "containers" and S.open and S.tab == "logs" then
		list = {
			{ "/", "search" },
			{ "n", "next" },
			{ "End", "follow" },
			{ "t", "times" },
			{ "[ ]", "tabs" },
			{ "Esc", "back" },
		}
	elseif S.section == "containers" and S.open then
		list = {
			{ "s", "stop" },
			{ "r", "restart" },
			{ "e", "shell" },
			{ "[ ]", "tabs" },
			{ "Tab", "list" },
			{ "Esc", "close" },
		}
	elseif S.section == "containers" then
		list = {
			{ "↑↓", "choose" },
			{ "⏎", "open" },
			{ "space", "mark" },
			{ "s", "stop" },
			{ "r", "restart" },
			{ "e", "shell" },
			{ "l", "logs" },
			{ ".", "more" },
		}
	elseif S.section == "images" and S.layer_open then
		list = { { "u", "update" }, { "d", "remove" }, { "Esc", "back" } }
	elseif S.section == "images" then
		list = {
			{ "↑↓", "choose" },
			{ "⏎", "layers" },
			{ "space", "mark" },
			{ "d", "remove" },
			{ "u", "pull" },
			{ "c", "clean up" },
		}
	elseif S.section == "volumes" or S.section == "networks" then
		list =
			{ { "↑↓", "choose" }, { "space", "mark" }, { "d", "remove" }, { "c", "clean up" }, { "/", "filter" } }
	elseif S.section == "system" then
		list = { { "↑↓", "scroll" }, { "c", "clean up" } }
	else
		list = { { "↑↓", "choose" }, { "⏎", "show it" }, { "/", "filter" } }
	end
	return list
end

function frame.status(width)
	local bar = b.div():col():no_shrink():child(b.div():h(1):bg(alpha("border", 0.7)))
	local row = b.div():row():items_center():gap(10):h(SIZE.status):px(12):clip():bg("raised1")
	local keys = b.div():row():items_center():gap(10):min_w(0):clip()
	local room = math.max(math.floor((width - 220) / 90), 2)
	for index, hint in ipairs(hints()) do
		if index > room then
			break
		end
		keys:child(
			b.div()
				:row()
				:items_center()
				:gap(5)
				:no_shrink()
				:child(P.kbd(hint[1], SIZE.tiny))
				:child(T(hint[2], "quiet", SIZE.small))
		)
	end
	row:child(keys):child(b.spacer())
	row:child(
		b.div()
			:row()
			:items_center()
			:gap(5)
			:no_shrink()
			:child(P.kbd("?", SIZE.tiny))
			:child(T("help", "quiet", SIZE.small))
	)
	row:child(
		b.div()
			:row()
			:items_center()
			:gap(5)
			:no_shrink()
			:child(P.kbd("⌃C", SIZE.tiny))
			:child(T("quit", "quiet", SIZE.small))
	)
	return bar:child(row)
end

-- ---- what the person does ---------------------------------------------------------------------------

local go = {}

-- Which part of the page has the host's text field: the filter of a list, the search of a log,
-- the answer to a question; nothing, where there is nothing to type into.
local function field_context(g)
	if S.dialog then
		return S.dialog.field and "dialog" or nil
	end
	if S.section == "containers" then
		if S.open and S.tab == "logs" and (S.focus == "detail" or not g.beside) then
			return "logs"
		end
		if S.open and not g.beside then
			return nil
		end
		return "list"
	elseif S.section == "system" then
		return nil
	elseif S.section == "images" and S.layer_open then
		return nil
	end
	return "list"
end

-- What the page keeps of itself for the next view, sent to the program when it changed.
local last_kept = nil

local function persist()
	if not S.ready then
		return
	end
	local kept = {
		section = S.section,
		detail = S.open,
		tab = S.tab,
		filter = S.filter,
		group = S.group,
		sort = S.sort,
		folded = S.folded,
		cursor = S.cursor,
		timestamps = L.timestamps,
	}
	local text = b.json.encode(kept)
	if text ~= last_kept then
		last_kept = text
		net.ask("ui", { ui = kept }, function() end)
	end
end

local function restore(kept)
	if type(kept) ~= "table" then
		return
	end
	local function one_of(value, list, key)
		for _, item in ipairs(list) do
			if item[key or "id"] == value then
				return value
			end
		end
		return nil
	end
	S.section = one_of(kept.section, SECTIONS) or S.section
	S.tab = one_of(kept.tab, TABS) or S.tab
	S.filter = one_of(kept.filter, FILTERS) or S.filter
	for _, sort in ipairs(SORTS) do
		if kept.sort == sort then
			S.sort = sort
		end
	end
	if type(kept.group) == "boolean" then
		S.group = kept.group
	end
	if type(kept.folded) == "table" then
		S.folded = kept.folded
	end
	if type(kept.cursor) == "table" then
		S.cursor = kept.cursor
	end
	if type(kept.detail) == "string" then
		S.open, S.focus = kept.detail, "detail"
	end
	if type(kept.timestamps) == "boolean" then
		L.timestamps = kept.timestamps
	end
end

-- Brings what is asked of the program in line with what is on show: the readings while the
-- containers are, the log while it is, the lists of the section that is.
local function sync()
	if not S.ready then
		return
	end
	local want_stats = S.section == "containers"
	if want_stats and not net.watching("stats") then
		net.watch("stats", "stats", nil, on_stats)
	elseif not want_stats and net.watching("stats") then
		net.unwatch("stats")
	end
	local open = S.open and S.by_id[S.open]
	-- A container that is opened and left again at once (the cursor going down the list) is not
	-- asked about.
	local settled = S.now - S.open_at >= 0.2
	local want_logs = open ~= nil and S.tab == "logs" and S.section == "containers"
	if want_logs then
		if settled then
			if L.id ~= open.id or not net.watching("logs") then
				log_clear(open.id, LOG_TAIL)
				L.resub_at = S.now
				net.watch("logs", "logs", { id = open.id, tail = L.tail }, on_log)
			elseif L.ended and log_live() and S.now - (L.resub_at or 0) > 3 then
				-- The container came back: the log goes on from the last line shown.
				L.ended, L.resub_at = nil, S.now
				net.watch("logs", "logs", { id = open.id, since = L.last }, on_log)
			end
		end
	elseif net.watching("logs") then
		net.unwatch("logs")
		log_clear(nil)
	end
	if not settled then
		open = nil
	end
	if open and S.section == "containers" then
		local slot = S.details[open.id]
		if slot == nil or (slot.signature ~= signature(open) and not slot.asking) then
			load_detail(open.id)
		end
		if S.tab == "processes" and open.state == "running" then
			local p = S.processes
			if p.id ~= open.id then
				p.titles, p.rows, p.id, p.at, p.error = nil, nil, open.id, nil, nil
			end
			if not p.asking and (p.at == nil or S.now - p.at >= 2) then
				load_processes(open.id)
			end
		end
	end
	for _, section in ipairs({ "images", "volumes", "networks" }) do
		if S.section == section and (S.lists[section] == nil and not S.problems[section] or S.stale[section]) then
			load_list(section)
		end
	end
	if (S.section == "system" or S.dialog and S.dialog.needs_system) and (S.system == nil or S.stale.system) then
		load_system()
	end
	if S.section == "images" and S.layer_open then
		local slot = S.layers[S.layer_open]
		if slot == nil then
			S.layers[S.layer_open] = { list = nil }
			local id = S.layer_open
			net.ask("image_layers", { id = id }, function(result, err)
				S.layers[id] = err and { error = why(err) } or { list = result.layers }
				bump()
			end)
		end
	end
end

-- Opens the detail of a container, and says where the keys go.
function go.open(id, focus)
	if S.open ~= id then
		S.open, S.open_at = id, S.now
		ui.scroll["detail.scroll"] = nil
		ui.scroll["detail.inspect"] = nil
		S.show_labels = false
	end
	if focus then
		S.focus = "detail"
	end
	bump()
end

function go.close()
	S.open, S.focus = nil, "list"
	bump()
end

function go.section(id)
	if S.section == id then
		return
	end
	S.section = id
	S.layer_open = nil
	S.focus = "list"
	ui.scroll.list = nil
	bump()
	keep_cursor(id)
	S.reveal = true
end

function go.tab(id)
	if S.tab ~= id then
		S.tab = id
		ui.scroll["detail.scroll"] = nil
		bump()
	end
	if S.open then
		S.focus = "detail"
	end
end

local function step(list, current, delta, key)
	for index, item in ipairs(list) do
		if (key and item[key] or item) == current then
			return list[(index - 1 + delta) % #list + 1]
		end
	end
	return list[1]
end

-- Moves the cursor of a list: by `how` rows, or to its `first` or `last`.
function go.move(section, how)
	local rows = rows_of(section)
	if #rows == 0 then
		return
	end
	local at = index_of(rows, S.cursor[section]) or 0
	local to
	if how == "first" then
		to = 1
	elseif how == "last" then
		to = #rows
	else
		to = math.max(1, math.min(#rows, at + how))
	end
	S.cursor[section] = rows[to].id
	reveal("list", to, #rows, SIZE.row)
	if section == "containers" and S.open and rows[to].kind == "container" then
		go.open(rows[to].id, false)
	end
	bump()
end

-- The row the cursor is on in the section that is shown.
local function cursor_row(section)
	local rows = rows_of(section)
	return rows[index_of(rows, S.cursor[section]) or 0]
end

-- The container the keys are about: the one the cursor is on.
local function current_container()
	local row = cursor_row("containers")
	if row and row.kind == "container" then
		return row.c
	end
	return S.open and S.by_id[S.open] or nil
end

function go.toggle_mark(section, id)
	S.marks[section] = S.marks[section] or {}
	S.marks[section][id] = (not S.marks[section][id]) or nil
	bump()
end

function go.mark_all(section, on)
	S.marks[section] = {}
	if on then
		for _, row in ipairs(rows_of(section)) do
			if row.kind ~= "group" then
				S.marks[section][row.id] = true
			end
		end
	end
	bump()
end

function go.fold(row, to)
	if row.kind ~= "group" then
		return
	end
	local now_folded = row.folded
	if to == nil then
		to = not now_folded
	end
	S.folded[row.key] = to
	bump()
end

local function ask_pull(reference)
	ask("Pull an image", {}, "Pull", function()
		local text = string.gsub(S.query, "^%s*(.-)%s*$", "%1")
		if text ~= "" then
			act.pull(text)
		end
	end, {
		field = {
			label = "Image: a name, or name:tag. ⏎ ends typing, ⏎ again pulls.",
			hint = "redis, nginx:alpine",
		},
	})
end

local function ask_clean()
	local targets_, titles, freed = all_that_can_be_freed()
	if S.system == nil then
		S.stale.system = true
		load_system()
		toast.say("Counting the disk: ask again in a moment", { kind = "info" })
		return
	end
	if #targets_ == 0 then
		toast.say("There is nothing to clean up", { kind = "info" })
		return
	end
	act.prune(targets_, titles, freed)
end

-- The menu of the row the cursor is on, at `at`.
local function row_menu(at)
	local section = S.section
	local entries, acts = {}, {}
	local function item(title, key, enabled, fn)
		entries[#entries + 1] = { title = title, key = key, enabled = enabled ~= false }
		acts[#entries] = fn
	end
	local function line()
		entries[#entries + 1] = "-"
	end
	if section == "containers" then
		local c = current_container()
		if c == nil then
			return nil
		end
		local up = is_up(c)
		item(up and "Stop" or "Start", "s", true, act.toggle)
		item("Restart", "r", true, function()
			act.do_all("restart")
		end)
		item(c.state == "paused" and "Resume" or "Pause", "p", up, act.pause_toggle)
		line()
		item("Open a shell in the terminal", "e", c.state == "running", function()
			act.terminal("shell", c)
		end)
		item("Follow its log in the terminal", "F", true, function()
			act.terminal("logs", c)
		end)
		line()
		item("Logs", "l", true, function()
			go.open(c.id, true)
			go.tab("logs")
		end)
		item("Inspect", "i", true, function()
			go.open(c.id, true)
			go.tab("inspect")
		end)
		line()
		item("Copy the id", "y", true, function()
			S.copy = c.id
		end)
		line()
		item("Kill…", "K", up, act.kill_containers)
		item("Remove…", "d", true, act.remove_containers)
	elseif section == "images" or section == "volumes" or section == "networks" then
		local row = cursor_row(section)
		if row == nil then
			return nil
		end
		if section == "images" then
			item("Layers", nil, true, function()
				S.layer_open = row.id
				bump()
			end)
			line()
		end
		item("Remove…", "d", not (row.item.builtin == true), function()
			act.remove_listed(section)
		end)
	else
		return nil
	end
	S.menu = { acts = acts }
	return { at = at, entries = entries }
end

-- ---- keys --------------------------------------------------------------------------------------------------

local keys = {}

local function reply_field()
	return { redraw = true, keyboard = "field" }
end

-- A question is open: its keys.
function keys.dialog(key)
	local d = S.dialog
	if key == "escape" or key == "n" or key == "N" then
		S.dialog = nil
		bump()
		return true
	elseif key == "y" or key == "Y" then
		if d.field and string.gsub(S.query, "%s", "") == "" then
			return false
		end
		S.dialog = nil
		bump()
		d.run()
		return true
	elseif key == "enter" then
		if d.choice == "confirm" then
			if d.field and string.gsub(S.query, "%s", "") == "" then
				return false
			end
			S.dialog = nil
			bump()
			d.run()
		else
			S.dialog = nil
			bump()
		end
		return true
	elseif key == "tab" or key == "left" or key == "right" then
		d.choice = d.choice == "confirm" and "cancel" or "confirm"
		return true
	elseif key == "/" and d.field then
		return reply_field()
	end
	return false
end

-- Scrolls a scrolling box by `dy`, in points.
local function scroll_by(id, dy)
	ui:set_scroll(id, math.max(ui:scroll_offset(id) + dy, 0))
end

-- Keys over a log: it scrolls, follows, is searched.
local function log_keys(key, mods)
	local view = views.log or 400
	local page = math.max(view - SIZE.line * 2, SIZE.line)
	if key == "right" and mods and mods.shift then
		L.hscroll += 16
	elseif key == "left" and mods and mods.shift then
		L.hscroll = math.max(L.hscroll - 16, 0)
	elseif key == "0" then
		L.hscroll = 0
	elseif key == "up" or key == "k" then
		L.follow = false
		scroll_by("log", -SIZE.line * 3)
	elseif key == "down" or key == "j" then
		scroll_by("log", SIZE.line * 3)
	elseif key == "page_up" then
		L.follow = false
		scroll_by("log", -page)
	elseif key == "page_down" then
		scroll_by("log", page)
	elseif key == "home" or key == "g" then
		L.follow = false
		ui:set_scroll("log", 0)
	elseif key == "end" or key == "G" or key == "F" and false then
		L.follow, L.new_since = true, 0
	elseif key == "t" then
		L.timestamps = not L.timestamps
	elseif key == "n" or key == "N" then
		local total = #L.matches
		if total == 0 then
			return false
		end
		local at = L.match_at
		if key == "n" then
			at = at % total + 1
		else
			at = (at - 2) % total + 1
		end
		L.match_at, L.follow, L.pinned_match = at, false, true
		ui:set_scroll("log", math.max((L.matches[at] - 1) * SIZE.line - view / 2, 0))
	elseif key == "L" then
		if L.tail < LOG_MOST then
			L.tail = math.min(L.tail * 5, LOG_MOST)
			log_clear(L.id, L.tail)
			net.watch("logs", "logs", { id = L.id, tail = L.tail }, on_log)
		end
	else
		return nil
	end
	-- Following ends where the person scrolls up, and begins again at the bottom.
	return true
end

-- Keys that scroll what the detail shows, by tab.
local function detail_scroll_keys(key)
	local id = S.tab == "inspect" and "detail.inspect" or "detail.scroll"
	local view = views[id] or 400
	if key == "up" or key == "k" then
		scroll_by(id, -36)
	elseif key == "down" or key == "j" then
		scroll_by(id, 36)
	elseif key == "page_up" then
		scroll_by(id, -(view - 40))
	elseif key == "page_down" then
		scroll_by(id, view - 40)
	elseif key == "home" or key == "g" then
		ui:set_scroll(id, 0)
	elseif key == "end" or key == "G" then
		ui:set_scroll(id, 1e9)
	else
		return nil
	end
	return true
end

-- The keys that move the cursor of the list of containers.
local function list_navigation(key)
	local page = math.max(math.floor((views.list or 400) / SIZE.row) - 1, 1)
	local row = cursor_row("containers")
	if key == "down" or key == "j" then
		go.move("containers", 1)
	elseif key == "up" or key == "k" then
		go.move("containers", -1)
	elseif key == "page_down" then
		go.move("containers", page)
	elseif key == "page_up" then
		go.move("containers", -page)
	elseif key == "home" or key == "g" then
		go.move("containers", "first")
	elseif key == "end" or key == "G" then
		go.move("containers", "last")
	elseif key == "enter" or key == "right" then
		if row and row.kind == "group" then
			go.fold(row, key == "right" and false or nil)
		elseif row then
			go.open(row.id, true)
		end
	elseif key == "left" then
		local rows = rows_of("containers")
		if row and row.kind == "group" then
			go.fold(row, true)
		elseif S.open then
			go.close()
		elseif row and row.kind == "container" and row.c.project and S.group then
			-- To the head of its project.
			S.cursor.containers = "group:" .. row.c.project
			reveal("list", index_of(rows, S.cursor.containers) or 1, #rows, SIZE.row)
			bump()
		end
	else
		return nil
	end
	return true
end

-- What is done to the containers, wherever the keys are.
local function container_actions(key, g)
	local c = current_container()
	local row = cursor_row("containers")
	if key == "space" or key == " " then
		if row and row.kind == "container" then
			go.toggle_mark("containers", row.id)
		end
	elseif key == "a" then
		go.mark_all("containers", true)
	elseif key == "A" then
		go.mark_all("containers", false)
	elseif key == "s" then
		act.toggle()
	elseif key == "r" then
		act.do_all("restart")
	elseif key == "p" then
		act.pause_toggle()
	elseif key == "e" then
		if c then
			act.terminal("shell", c)
		end
	elseif key == "F" then
		if c then
			act.terminal("logs", c)
		end
	elseif key == "l" or key == "i" then
		if c then
			go.open(c.id, true)
			go.tab(key == "l" and "logs" or "inspect")
		end
	elseif key == "y" then
		if c then
			S.copy = c.id
		end
	elseif key == "K" then
		act.kill_containers()
	elseif key == "d" then
		act.remove_containers()
	elseif key == "f" then
		S.filter = step(FILTERS, S.filter, 1, "id").id
		bump()
		keep_cursor("containers")
	elseif key == "P" then
		S.group = not S.group
		bump()
		keep_cursor("containers")
	elseif key == "o" then
		S.sort = step(SORTS, S.sort, 1)
		bump()
	elseif key == "." then
		local at = { x = 220, y = 160 }
		local id = c and ("row:" .. c.id)
		local rect = id and b.layout.bounds(id)
		if rect then
			at = { x = rect.x + 40, y = rect.y + rect.h }
		end
		S.pending_menu = at
	else
		return nil
	end
	return true
end

-- Keys of the containers.
function keys.containers(key, mods, g)
	local in_detail = S.open ~= nil and (S.focus == "detail" or not g.beside)
	if S.open then
		if key == "[" then
			go.tab(step(TABS, S.tab, -1, "id").id)
			return true
		elseif key == "]" then
			go.tab(step(TABS, S.tab, 1, "id").id)
			return true
		elseif key == "escape" then
			go.close()
			return true
		elseif key == "tab" then
			S.focus = S.focus == "detail" and "list" or "detail"
			bump()
			return true
		end
	end
	if in_detail then
		local done
		if S.tab == "logs" then
			done = log_keys(key, mods)
		else
			done = detail_scroll_keys(key)
		end
		if done ~= nil then
			return done
		end
		if key == "left" then
			if g.beside then
				S.focus = "list"
				bump()
			else
				go.close()
			end
			return true
		elseif key == "v" and S.tab == "env" then
			S.show_secrets = not S.show_secrets
			return true
		end
	elseif list_navigation(key) then
		return true
	end
	if key == "u" then
		ask_pull()
		return true
	elseif key == "c" then
		ask_clean()
		return true
	end
	return container_actions(key, g)
end

-- Keys of the lists of images, volumes and networks, and of the activity.
function keys.plain(key, mods, g)
	local section = S.section
	if section == "images" and S.layer_open then
		if key == "escape" or key == "left" then
			S.layer_open = nil
			bump()
		elseif key == "u" then
			go.update_image(S.layer_open)
		elseif key == "d" then
			S.cursor.images = S.layer_open
			act.remove_listed("images")
		elseif key == "up" or key == "k" then
			scroll_by("list", -SIZE.row)
		elseif key == "down" or key == "j" then
			scroll_by("list", SIZE.row)
		else
			return nil
		end
		return true
	end
	local row = cursor_row(section)
	local page = math.max(math.floor((views.list or 400) / SIZE.row) - 1, 1)
	if key == "down" or key == "j" then
		go.move(section, 1)
	elseif key == "up" or key == "k" then
		go.move(section, -1)
	elseif key == "page_down" then
		go.move(section, page)
	elseif key == "page_up" then
		go.move(section, -page)
	elseif key == "home" or key == "g" then
		go.move(section, "first")
	elseif key == "end" or key == "G" then
		go.move(section, "last")
	elseif key == "space" or key == " " then
		if row then
			go.toggle_mark(section, row.id)
		end
	elseif key == "a" then
		go.mark_all(section, true)
	elseif key == "A" then
		go.mark_all(section, false)
	elseif key == "d" and section ~= "activity" then
		act.remove_listed(section)
	elseif key == "u" and (section == "images" or section == "containers") then
		ask_pull()
	elseif key == "c" then
		ask_clean()
	elseif key == "enter" or key == "right" then
		if section == "images" and row then
			S.layer_open = row.id
			ui.scroll.list = nil
			bump()
		elseif section == "activity" and row and row.item.type == "container" and S.by_id[row.item.id] then
			go.section("containers")
			S.cursor.containers = row.item.id
			go.open(row.item.id, true)
		end
	elseif key == "." then
		local rect = row and b.layout.bounds("row:" .. row.id)
		S.pending_menu = rect and { x = rect.x + 40, y = rect.y + rect.h } or { x = 220, y = 160 }
	else
		return nil
	end
	return true
end

function keys.system(key)
	if key == "c" then
		ask_clean()
	elseif key == "up" or key == "k" then
		scroll_by("system.scroll", -40)
	elseif key == "down" or key == "j" then
		scroll_by("system.scroll", 40)
	elseif key == "page_up" then
		scroll_by("system.scroll", -300)
	elseif key == "page_down" then
		scroll_by("system.scroll", 300)
	elseif key == "home" then
		ui:set_scroll("system.scroll", 0)
	elseif key == "end" then
		ui:set_scroll("system.scroll", 1e9)
	else
		return nil
	end
	return true
end

-- A key, as the page reads it. Gives what the page replies: true when something changed.
function keys.press(key, mods)
	local g = geometry()
	if S.dialog then
		return keys.dialog(key)
	end
	if S.help then
		if key == "escape" or key == "?" or key == "q" then
			S.help = false
			bump()
		elseif key == "up" or key == "k" then
			scroll_by("help.scroll", -40)
		elseif key == "down" or key == "j" then
			scroll_by("help.scroll", 40)
		end
		return true
	end
	if mods and (mods.control or mods.alt or mods.command) then
		return nil
	end
	if key == "?" then
		S.help = true
		return true
	end
	for _, section in ipairs(SECTIONS) do
		if key == section.key then
			go.section(section.id)
			return true
		end
	end
	if key == "/" and field_context(g) then
		return reply_field()
	end
	if S.section == "containers" then
		return keys.containers(key, mods, g)
	elseif S.section == "system" then
		return keys.system(key)
	end
	return keys.plain(key, mods, g)
end

-- Updates an image: pulls what its first tag names again.
function go.update_image(id)
	for _, image in ipairs(S.lists.images or {}) do
		if image.id == id and image.tags[1] then
			act.pull(image.tags[1])
			toast.say("Pulling " .. image.tags[1], { kind = "info" })
			return
		end
	end
	toast.say("That image has no name to pull", { kind = "warning" })
end

-- ---- the pointer ---------------------------------------------------------------------------------------

local mouse = {}

-- A click on the thing named `id` (a release over where the press began).
function mouse.click(id, mods)
	local kind, rest = string.match(id, "^([%w%.]+):(.*)$")
	mods = mods or {}
	if kind == "sec" then
		go.section(rest)
	elseif kind == "row" then
		local section = S.section
		S.cursor[section] = rest
		bump()
		if section == "containers" then
			local row = cursor_row("containers")
			if row and row.kind == "group" then
				go.fold(row)
			elseif row and (mods.shift or mods.command or mods.control) then
				go.toggle_mark("containers", row.id)
			elseif row then
				go.open(row.id, true)
			end
		elseif section == "images" then
			if mods.shift or mods.command or mods.control then
				go.toggle_mark(section, rest)
			else
				S.layer_open = rest
				ui.scroll.list = nil
			end
		elseif section == "activity" then
			local row = cursor_row("activity")
			if row and row.item.type == "container" and S.by_id[row.item.id] then
				go.section("containers")
				S.cursor.containers = row.item.id
				go.open(row.item.id, true)
			end
		elseif mods.shift or mods.command or mods.control then
			go.toggle_mark(section, rest)
		end
	elseif kind == "mark" then
		go.toggle_mark(S.section, rest)
	elseif kind == "verb" then
		if S.section == "containers" and string.sub(rest, 1, 6) == "group:" then
			S.cursor.containers = rest
			bump()
			local members = targets("containers")
			local ids, running = {}, false
			for _, row in ipairs(members) do
				running = running or is_up(row.c)
			end
			for _, row in ipairs(members) do
				if running == is_up(row.c) then
					ids[#ids + 1] = row.id
				end
			end
			act.run(ids, running and "stop" or "start")
		elseif S.section == "containers" then
			local c = S.by_id[rest]
			if c then
				S.cursor.containers = rest
				act.run({ rest }, is_up(c) and "stop" or "start")
			end
		else
			S.cursor[S.section] = rest
			S.marks[S.section] = {}
			act.remove_listed(S.section)
		end
	elseif kind == "filter" then
		S.filter = rest
		bump()
		keep_cursor("containers")
	elseif id == "group" then
		S.group = not S.group
		bump()
		keep_cursor("containers")
	elseif id == "sort" then
		S.sort = step(SORTS, S.sort, 1)
		bump()
	elseif id == "act:pull" then
		ask_pull()
	elseif id == "act:clean" then
		ask_clean()
	elseif id == "act:remove" then
		act.remove_listed(S.section)
	elseif kind == "d" then
		local c = S.open and S.by_id[S.open]
		if c == nil then
			return
		end
		if rest == "toggle" then
			act.run({ c.id }, is_up(c) and "stop" or "start")
		elseif rest == "restart" then
			act.run({ c.id }, "restart")
		elseif rest == "pause" then
			act.run({ c.id }, c.state == "paused" and "unpause" or "pause")
		elseif rest == "shell" then
			act.terminal("shell", c)
		elseif rest == "follow" then
			act.terminal("logs", c)
		elseif rest == "remove" then
			S.marks.containers = {}
			S.cursor.containers = c.id
			act.remove_containers()
		elseif rest == "close" then
			go.close()
		elseif rest == "labels" then
			S.show_labels = not S.show_labels
		elseif rest == "secrets" then
			S.show_secrets = not S.show_secrets
		end
		bump()
	elseif kind == "tab" then
		go.tab(rest)
	elseif kind == "l" then
		if rest == "follow" then
			L.follow = not L.follow
			if L.follow then
				L.new_since = 0
			end
		elseif rest == "time" then
			L.timestamps = not L.timestamps
		elseif rest == "next" then
			log_keys("n", {})
		elseif rest == "prev" then
			log_keys("N", {})
		elseif rest == "more" then
			log_keys("L", {})
		end
	elseif kind == "env" then
		S.revealed_env[rest] = (not S.revealed_env[rest]) or nil
	elseif kind == "layers" then
		if rest == "back" then
			S.layer_open = nil
		elseif rest == "update" then
			go.update_image(S.layer_open)
		elseif rest == "remove" then
			S.cursor.images = S.layer_open
			S.marks.images = {}
			act.remove_listed("images")
		end
		bump()
	elseif kind == "free" then
		for _, one in ipairs(DISK) do
			if one.target == rest then
				local part = S.system and S.system.usage[one.key]
				act.prune({ rest }, { one.title }, part and part.reclaimable or 0)
			end
		end
	elseif kind == "dialog" then
		local d = S.dialog
		if d == nil then
			return
		end
		if rest == "cancel" then
			S.dialog = nil
			bump()
		elseif rest == "confirm" then
			if d.field and string.gsub(S.query, "%s", "") == "" then
				return
			end
			S.dialog = nil
			bump()
			d.run()
		end
	elseif id == "help:backdrop" then
		S.help = false
		bump()
	elseif kind == "toast" then
		local item = S.toasts[tonumber(rest)]
		if item then
			table.remove(S.toasts, tonumber(rest))
			if item.show and S.by_id[item.show] then
				go.section("containers")
				S.cursor.containers = item.show
				go.open(item.show, true)
			end
			bump()
		end
	elseif kind == "toast.action" then
		local index = tonumber(rest)
		local item = S.toasts[index]
		if item and item.action then
			table.remove(S.toasts, index)
			item.action.run()
			bump()
		end
	end
end

-- ---- the page ----------------------------------------------------------------------------------------------

-- What the screen of the section that is on show is.
local function main_screen(g)
	local section = S.section
	local frame_ = b.div():col():grow(1):min_w(0):min_h(0)
	if section == "containers" then
		local open = S.open and S.by_id[S.open]
		if open and g.beside then
			local list_width = g.main - SIZE.detail
			return b.div()
				:row()
				:grow(1)
				:min_w(0)
				:min_h(0)
				:child(screens.list(list_width))
				:child(b.div():col():w(SIZE.detail):no_shrink():child(screens.detail(SIZE.detail, true)))
		elseif open then
			return frame_:child(screens.detail(g.main, false))
		end
		return frame_:child(screens.list(g.main))
	elseif section == "images" then
		return frame_:child(S.layer_open and screens.layers(g.main) or screens.images(g.main))
	elseif section == "volumes" then
		return frame_:child(screens.volumes(g.main))
	elseif section == "networks" then
		return frame_:child(screens.networks(g.main))
	elseif section == "system" then
		return frame_:child(screens.system(g.main))
	end
	return frame_:child(screens.activity(g.main))
end

local function build(g)
	local root = b.div():size_full()
	local app = b.div():size_full():col()
	if g.rail == 0 then
		app:child(frame.strip())
	end
	local body = b.div():row():grow(1):min_h(0)
	if g.rail > 0 then
		body:child(frame.rail())
	end
	body:child(main_screen(g))
	app:child(body)
	local jobs = overlays.jobs()
	if jobs then
		app:child(jobs)
	end
	app:child(frame.status(S.width))
	root:child(app)
	if #S.toasts > 0 then
		root:child(overlays.toasts())
	end
	if S.help then
		root:child(overlays.help())
	end
	if S.dialog then
		root:child(overlays.dialog())
	end
	return root
end

local function on_boot(result, err)
	if err then
		toast.say("The program did not start the page: " .. tostring(why(err)), { kind = "error", seconds = 15 })
		return
	end
	S.ready = true
	S.hostname, S.remote, S.handoff = result.hostname or "", result.remote == true, result.handoff == true
	S.clock = result.time and (result.time - S.now) or nil
	restore(result.ui)
	if result.section then
		S.section = result.section
	end
	S.focus_request = result.focus
	net.watch("containers", "containers", nil, on_containers)
	net.watch("events", "events", nil, on_events)
	net.watch("jobs", "jobs", nil, on_jobs)
	local back = result.returned
	if back then
		local what = back.kind == "shell" and "The shell in " or "The log of "
		local how = back.status == nil and "ended"
			or (back.status == 0 and "ended" or ("ended with code " .. back.status))
		toast.say(what .. back.name .. " " .. how .. " after " .. fmt.span((back.duration or 0) / 1000), {
			kind = (back.status == nil or back.status == 0) and "info" or "warning",
			error = back.error,
		})
		if back.error then
			toast.say(back.error, { kind = "error" })
		end
	end
	if result.handoff_failed then
		toast.say(result.handoff_failed, { kind = "warning" })
	end
	bump()
end

-- A name on the command line, found among the containers: the cursor goes to it and its detail opens.
local function find_requested()
	local key = S.focus_request
	if key == nil or not S.known then
		return
	end
	S.focus_request = nil
	local found = nil
	for _, c in ipairs(S.containers) do
		if c.id == key or c.name == key or c.service == key or string.sub(c.id, 1, #key) == key then
			if found == nil or (c.state == "running" and found.state ~= "running") then
				found = c
			end
		end
	end
	if found then
		S.section = "containers"
		S.cursor.containers = found.id
		go.open(found.id, true)
		S.reveal = true
	else
		toast.say("There is no container " .. key, { kind = "warning" })
	end
end

local function tick_reload()
	if S.pending_reload and S.now >= S.pending_reload then
		S.pending_reload = nil
		for _, section in ipairs({ "images", "volumes", "networks" }) do
			if S.stale[section] and S.section == section then
				load_list(section)
			end
		end
		if S.stale.system and S.section == "system" then
			load_system()
		end
	end
end

local started = false

local function render(size, now, reduce_motion)
	S.width, S.height, S.now = size.w, size.h, now
	if not started then
		started = true
		net.ask("boot", nil, on_boot)
	end
	local toast_at = toast.tidy()
	tick_reload()
	find_requested()
	if S.reveal and S.known then
		S.reveal = false
		local rows = rows_of(S.section)
		local at = index_of(rows, S.cursor[S.section])
		if at then
			reveal("list", at, #rows, SIZE.row)
		end
	end
	sync()
	local g = geometry()
	S.field = field_context(g)
	L.query_on = S.field == "logs"
	local scanning = false
	if S.section == "containers" and S.open and S.tab == "logs" and L.id == S.open then
		scanning = scan_log(3000)
	end
	S.any_marked = false
	for _ in pairs(S.marks[S.section] or {}) do
		S.any_marked = true
		break
	end
	local root = build(g)
	local wake = nil
	local function wake_at(at)
		if at then
			wake = wake and math.min(wake, at) or at
		end
	end
	wake_at(toast_at)
	wake_at(S.pending_reload)
	if S.open and now - S.open_at < 0.2 then
		wake_at(S.open_at + 0.21)
	end
	if S.open and S.tab == "processes" and S.processes.at then
		wake_at(S.processes.at + 2.05)
	end
	return root, scanning, wake
end

-- The keyboard goes to the host's field, or to the page.
local function on_text(text)
	S.query = text
	S.cache = {}
	bump()
	if S.field == "list" then
		ui.scroll.list = nil
		keep_cursor(S.section)
	end
end

local function cursor_shape()
	local hover = ui.hover
	if hover == "field" or hover == "field.room" then
		return "text"
	elseif hover ~= nil then
		return "pointer"
	end
	return "arrow"
end

-- What the page says back to an input, as the reply the kit takes.
local function answer(result)
	local reply = {}
	if type(result) == "table" then
		reply = result
	elseif result ~= nil then
		reply.redraw = result == true
	end
	if S.copy then
		reply.copy, S.copy = S.copy, nil
	end
	if S.pending_menu then
		reply.menu = row_menu(S.pending_menu)
		S.pending_menu = nil
	end
	reply.cursor = cursor_shape()
	persist()
	sync()
	return reply
end

local function handle(event)
	local kind = event.type
	local result = nil
	if kind == "move" then
		S.pointer = { x = event.x, y = event.y }
		return { redraw = ui:point(b.layout, event), cursor = cursor_shape() }
	elseif kind == "leave" then
		S.pointer = nil
		return { redraw = ui:point(b.layout, nil), cursor = "arrow" }
	elseif kind == "press" then
		S.pointer = { x = event.x, y = event.y }
		local hit = ui:press(b.layout, event)
		S.press_mods = event.mods
		result = false
		if hit == "field" or hit == "field.room" then
			result = reply_field()
		elseif event.button == "right" and hit and string.sub(hit, 1, 4) == "row:" then
			mouse.click(hit, { shift = false })
			S.pending_menu = { x = event.x, y = event.y }
			result = true
		elseif hit then
			result = true
		end
	elseif kind == "release" then
		local clicked = ui:release(b.layout, event)
		if clicked and event.button == "left" and clicked ~= "field" and clicked ~= "field.room" then
			mouse.click(clicked, S.press_mods)
		end
		result = true
	elseif kind == "scroll" then
		S.pointer = { x = event.x, y = event.y }
		local moved = ui:scroll_by(b.layout, event, event.dy)
		if moved and S.section == "containers" and S.open and S.tab == "logs" then
			if event.dy < 0 then
				L.follow = false
			else
				local view = views.log or 400
				if ui:scroll_offset("log") >= L.count * SIZE.line + 8 - view - 2 then
					L.follow, L.new_since = true, 0
				end
			end
		end
		result = moved
	elseif kind == "key" then
		result = keys.press(event.key, event.mods)
	elseif kind == "text" then
		on_text(event.text)
		result = true
	elseif kind == "menu" then
		local menu = S.menu
		S.menu = nil
		if menu and menu.acts[event.index] then
			menu.acts[event.index]()
		end
		result = true
	end
	return answer(result)
end

local function settle()
	local moved = ui:settle(b.layout)
	for _, id in ipairs({ "list", "log", "detail.inspect", "detail.scroll", "system.scroll", "help.scroll" }) do
		local extent = b.layout.scroll_extent(id)
		if extent and views[id] ~= extent.view then
			views[id] = extent.view
			moved = true
		end
	end
	if S.pointer then
		moved = ui:point(b.layout, S.pointer) or moved
	end
	return moved
end

return {
	render = render,
	handle = handle,
	settle = settle,
}
