local lib_sizes = require("../lib/sizes")
local LOG_TAIL, RAIL_FROM, SIZE = lib_sizes.LOG_TAIL, lib_sizes.RAIL_FROM, lib_sizes.SIZE

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

-- How wide the main part of the page is (what is not the rail), and whether the detail of a
-- container is beside the list or over it.
local function geometry()
	local rail = S.width >= RAIL_FROM and SIZE.rail or 0
	local main = S.width - rail
	local beside = main >= 880
	return { rail = rail, main = main, beside = beside }
end

return {
	S = S,
	bump = bump,
	geometry = geometry,
}
