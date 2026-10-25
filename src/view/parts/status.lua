-- The line at the bottom: the keys that do something where the person is (they follow what is
-- chosen: a stopped container offers to start, a running one to stop), the jobs that run, the
-- command palette, the help, and whether the engine answered.

local lib_icons = require("../lib/icons")
local lib_kit = require("../lib/kit")
local lib_sizes = require("../lib/sizes")
local model_act = require("../model/act")
local model_rows = require("../model/rows")
local model_state = require("../model/state")
local parts_ui = require("./ui")
local alpha, b = lib_kit.alpha, lib_kit.b
local icon = lib_icons.icon
local SIZE = lib_sizes.SIZE
local act = model_act.act
local marked, targets = model_rows.marked, model_rows.targets
local S = model_state.S
local P, T, hovered = parts_ui.P, parts_ui.T, parts_ui.hovered

local status = {}

-- What the keys do for the containers the cursor or the marks name.
local function container_hints()
	local list = {}
	local rows = targets("containers")
	local up, stopped = false, false
	for _, row in ipairs(rows) do
		local state = row.c.state
		if state == "running" or state == "restarting" then
			up = true
		end
		if state ~= "running" and state ~= "restarting" then
			stopped = true
		end
	end
	local marks = #marked("containers")
	if marks > 0 then
		list[#list + 1] = {
			keys = "esc",
			label = "unmark " .. marks,
			run = function()
				S.marks.containers = {}
			end,
		}
	end
	-- One hint a key: where some of a project is up, `s` stops.
	if up then
		list[#list + 1] = { keys = "s", label = "stop", run = act.toggle }
	elseif stopped then
		list[#list + 1] = { keys = "s", label = "start", run = act.toggle }
	end
	if #rows > 0 then
		list[#list + 1] = {
			keys = "r",
			label = "restart",
			run = function()
				act.do_all("restart")
			end,
		}
	end
	if #rows == 1 then
		list[#list + 1] = {
			keys = "e",
			label = "open a shell",
			run = function()
				act.terminal("shell", rows[1].c)
			end,
		}
		list[#list + 1] = { keys = "l", label = "logs", run = nil }
	end
	list[#list + 1] = { keys = ".", label = "more" }
	list[#list + 1] = { keys = "space", label = "mark" }
	return list
end

-- The keys that do something where the person is.
local function hints()
	if S.dialog then
		return {
			{ keys = "y", label = "yes" },
			{ keys = "esc", label = "no" },
			{ keys = "tab", label = "other answer" },
		}
	elseif S.help then
		return { { keys = "esc", label = "close" } }
	elseif S.palette then
		return { { keys = "↑↓", label = "choose" }, { keys = "esc", label = "close" } }
	elseif S.section == "containers" then
		if S.open and S.focus == "detail" and S.tab == "logs" then
			return {
				{ keys = "space", label = "follow" },
				{ keys = "/", label = "find" },
				{ keys = "t", label = "time" },
				{ keys = "w", label = "wrap" },
				{ keys = "[ ]", label = "tabs" },
				{ keys = "esc", label = "back" },
			}
		end
		return container_hints()
	elseif S.section == "system" then
		return {
			{ keys = "↑↓", label = "choose" },
			{ keys = "⏎", label = "free it" },
			{ keys = "c", label = "clean up" },
		}
	elseif S.section == "activity" then
		return { { keys = "↑↓", label = "move" }, { keys = "⏎", label = "open the container" } }
	end
	local list =
		{ { keys = "↑↓", label = "move" }, { keys = "/", label = "find" }, { keys = "space", label = "mark" } }
	if S.section == "images" then
		list[#list + 1] = { keys = "⏎", label = "layers" }
		list[#list + 1] = { keys = "p", label = "pull" }
		list[#list + 1] = { keys = "u", label = "update" }
	end
	list[#list + 1] = { keys = "d", label = "remove" }
	return list
end

-- A key and what it does, as a small button where it is something to press.
local function hint(entry, id)
	local over = id ~= nil and hovered(id)
	local el = b.div():row():items_center():gap(5):h(20):px(4):rounded(4):no_shrink()
	if id then
		el:press(id)
	end
	if over then
		el:bg(alpha("foreground", 0.06))
	end
	el:child(P.kbd(entry.keys, SIZE.tiny, 16))
	if entry.label ~= "" then
		el:child(T(entry.label, over and "foreground" or "quiet", SIZE.small))
	end
	return el
end

function status.bar(width)
	S.hint_runs = {}
	local row = b.div():row():items_center():gap(10):h(SIZE.status):px(8):clip():bg("raised1")
	local keys = b.div():row():items_center():gap(4):min_w(0):clip()
	local room = math.max(math.floor((width - 260) / 90), 2)
	for index, entry in ipairs(hints()) do
		if index > room then
			break
		end
		local id = nil
		if entry.run then
			id = "hint:" .. index
			S.hint_runs[index] = entry.run
		end
		keys:child(hint(entry, id))
	end
	row:child(keys):child(b.spacer())
	-- The jobs, the palette, the help and the engine, closer to each other than the keys are.
	local right = b.div():row():items_center():gap(8):no_shrink()
	if #S.jobs > 0 then
		local running = 0
		for _, job in ipairs(S.jobs) do
			if job.state == "running" then
				running += 1
			end
		end
		local ink = running > 0 and "accent" or "quiet"
		right:child(
			b.div()
				:row()
				:items_center()
				:gap(5)
				:h(20)
				:px(4)
				:rounded(4)
				:no_shrink()
				:press("jobs")
				:bg(hovered("jobs") and alpha("foreground", 0.06) or nil)
				:child(running > 0 and P.disc("accent", 9, false) or icon("circle-check", 12, "quiet"))
				:child(T(running > 0 and (running .. " running") or (#S.jobs .. " done"), ink, SIZE.small))
		)
	end
	right:child(hint({ keys = ":", label = "commands" }, "cmd"))
	right:child(hint({ keys = "?", label = "" }, "helpbtn"))
	right:child(b.div():row():items_center():px(4):no_shrink():child(
		-- A disc in a halo where the engine answers; a ring where it does not (red where it failed).
		(S.engine and not S.failure) and P.halo("success", 7) or P.disc(S.failure and "error" or "quiet", 7, false)
	))
	row:child(right)
	return b.div():col():no_shrink():child(b.div():h(1):bg(alpha("border", 0.6))):child(row)
end

return status
