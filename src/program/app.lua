-- dockerpen. In a terminal that shows pencere views Docker opens in the pane: containers, their
-- logs and resource use, images, volumes, networks and the disk they take. In one that does not,
-- the containers are printed.
--
-- The view hands the pane over when the person asks for a shell in a container (or for its log as it
-- comes): the program closes the view, runs the command in the terminal, and shows the view again
-- where it was when the command ends. What the page keeps of itself lives in the program, so it
-- crosses that gap.
--
-- This file is the entry and nothing more: it reads the command line, makes the state, wires the
-- calls and the topics of api/ to `serve`, and ends with the status a shell gives the program. The
-- page is src/view/page.lua (`serve` is told none: it shows what the view directory has).
--
--   api/       everything the page talks to the program about; it knows the page
--   docker/    running the docker command and reading what it prints; knows nothing of the page
--   state/     what the program holds: the containers, the readings, the events, the jobs; same
--   terminal/  the command line, and the pane given to a command and taken back; same

local pencere = require("pencere")

local boot_api = require("api.boot")
local command_line = require("terminal.command_line")
local containers_api = require("api.containers")
local fallback = require("terminal.fallback")
local handoff = require("terminal.handoff")
local live_api = require("api.live")
local logs_api = require("api.logs")
local resources_api = require("api.resources")
local session_module = require("state.session")
local version = require("version")

local line, why = command_line.read(pencere.args)
if line == nil then
	pencere.io.ewrite("dockerpen: " .. why .. "\n" .. command_line.USAGE .. "\n")
	pencere.exit(64)
end
if line.help then
	pencere.io.write(command_line.USAGE .. "\n")
	pencere.exit(0)
end
if line.version then
	pencere.io.write("dockerpen " .. version .. "\n")
	pencere.exit(0)
end
if line.text then
	pencere.exit(fallback.print())
end

local session = session_module.new({ section = line.section, focus = line.focus })
local shell = handoff.new(session)
session.desk = shell.desk

-- What the page may call: each area of api/ gives its calls.
local calls = {}
for _, area in ipairs({ boot_api, containers_api, resources_api }) do
	for name, handler in pairs(area.calls(session)) do
		calls[name] = handler
	end
end

-- What the page may listen to.
local topics = live_api.topics(session)
topics.logs = logs_api.topic(session)

local exit_code = 0

local function serve()
	return pencere.serve({
		program = "dockerpen",
		-- What a terminal writes above the view, and the icon it draws beside it.
		title = "Docker",
		icons = {
			{ file = "assets/icon-32-dark.png", theme = "dark" },
			{ file = "assets/icon-64-dark.png", theme = "dark" },
			{ file = "assets/icon-32-light.png", theme = "light" },
			{ file = "assets/icon-64-light.png", theme = "light" },
		},
		calls = calls,
		topics = topics,
		-- A terminal that shows no views is given the containers as text, at the start only.
		fallback = function()
			if not shell.handed_off then
				exit_code = fallback.print()
			end
		end,
	})
end

while true do
	local result = serve()
	if not result.shown and shell.handed_off and result.reason ~= "interrupted" and shell:try_again(result.reason) then
		continue
	end
	if result.shown and result.ended == "signal" then
		exit_code = (result.signal == nil or result.signal == 2) and 130 or 128 + result.signal
	elseif result.shown and result.ended == "error" then
		exit_code = 1
	elseif not result.shown and result.reason == "interrupted" then
		exit_code = 130
	end
	break
end

pencere.exit(exit_code)
