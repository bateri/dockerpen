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

return {
	ENV_MOST = ENV_MOST,
	FILTERS = FILTERS,
	LABELS_MOST = LABELS_MOST,
	LIST_MEDIUM = LIST_MEDIUM,
	LIST_WIDE = LIST_WIDE,
	LOG_MOST = LOG_MOST,
	LOG_TAIL = LOG_TAIL,
	PROCESSES_MOST = PROCESSES_MOST,
	RAIL_FROM = RAIL_FROM,
	SECTIONS = SECTIONS,
	SIZE = SIZE,
	SPARK = SPARK,
	TABS = TABS,
}
