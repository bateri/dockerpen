-- Sizes in points, and the fixed lists the page is made of: its sections, the tabs of a container,
-- the filters of the list, and how much of what the page holds it is willing to draw.

local SIZE = {
	row = 32, -- a row of a list, and the row that heads a compose project
	head = 46, -- the title of a screen
	bar = 36, -- the toolbar under it: a 28 field and the gap
	control = 28, -- the height of a field, a button, a segmented control
	small_control = 24,
	line = 18, -- a line of a log
	rail = 188, -- the rail of sections, where there is room for it
	rail_compact = 52, -- and its icons alone, where there is not
	detail = 460, -- the detail of a container, beside the list
	status = 26, -- the line of keys at the bottom
	body = 12.5, -- the size of the words of the page
	title = 13.5,
	small = 11,
	tiny = 10,
}

-- The widths of the page at which it changes shape.
local RAIL_COMPACT_BELOW = 780 -- the rail is its icons alone below this
local RAIL_FROM = 480 -- below this the sections are a strip across the top
-- The widths of the list of containers (the room it has, not the page) at which it drops a column.
local LIST_NARROW = 470 -- no memory below this
local LIST_MEDIUM = 660 -- no image below this, and
local LIST_WIDE = 860 -- no ports below this

local SECTIONS = {
	{ id = "containers", label = "Containers", key = "1", icon = "boxes" },
	{ id = "images", label = "Images", key = "2", icon = "layers" },
	{ id = "volumes", label = "Volumes", key = "3", icon = "hard-drive" },
	{ id = "networks", label = "Networks", key = "4", icon = "network" },
	{ id = "system", label = "System", key = "5", icon = "box" },
	{ id = "activity", label = "Activity", key = "6", icon = "activity" },
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
-- How many samples of a resource a chart draws: all the kit holds of one line.
local SPARK = 30

return {
	ENV_MOST = ENV_MOST,
	FILTERS = FILTERS,
	LABELS_MOST = LABELS_MOST,
	LIST_MEDIUM = LIST_MEDIUM,
	LIST_NARROW = LIST_NARROW,
	LIST_WIDE = LIST_WIDE,
	LOG_MOST = LOG_MOST,
	LOG_TAIL = LOG_TAIL,
	PROCESSES_MOST = PROCESSES_MOST,
	RAIL_COMPACT_BELOW = RAIL_COMPACT_BELOW,
	RAIL_FROM = RAIL_FROM,
	SECTIONS = SECTIONS,
	SIZE = SIZE,
	SPARK = SPARK,
	TABS = TABS,
}
