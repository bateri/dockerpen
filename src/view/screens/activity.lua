-- The activity: what the engine reported, newest first, a day at a time.

local lib_fmt = require("../lib/fmt")
local lib_kit = require("../lib/kit")
local lib_sizes = require("../lib/sizes")
local lib_virtual = require("../lib/virtual")
local model_rows = require("../model/rows")
local model_state = require("../model/state")
local parts_toolbar = require("../parts/toolbar")
local parts_ui = require("../parts/ui")
local alpha, b = lib_kit.alpha, lib_kit.b
local fmt = lib_fmt.fmt
local SIZE = lib_sizes.SIZE
local virtual = lib_virtual.virtual
local is_problem, plain_rows, row_tops = model_rows.is_problem, model_rows.plain_rows, model_rows.row_tops
local S = model_state.S
local P, T, chosen, glow, hovered = parts_ui.P, parts_ui.T, parts_ui.chosen, parts_ui.glow, parts_ui.hovered

local screens = {}

local KINDS = {
	{ id = "all", label = "All" },
	{ id = "container", label = "Containers" },
	{ id = "image", label = "Images" },
	{ id = "volume", label = "Volumes" },
	{ id = "network", label = "Networks" },
	{ id = "problems", label = "Problems", tone = "error" },
}

-- What an event is: a mark, the colour of the news in it (if it is news), and what it says.
local function describe(item)
	local name = item.name or string.sub(item.id or "", 1, 12)
	local action = item.action or ""
	local detail = item.detail or {}
	if item.type == "container" then
		if action == "start" then
			return "circle-play", "success", name .. " started"
		elseif action == "die" then
			local code = detail.exitCode
			local failed = code ~= nil and tostring(code) ~= "0"
			return "circle-stop",
				failed and "error" or nil,
				name .. " stopped" .. (code ~= nil and (" with exit " .. code) or "")
		elseif action == "stop" then
			return "circle-stop", nil, name .. " was asked to stop"
		elseif action == "kill" then
			return "skull",
				"warning",
				name .. " was sent " .. (detail.signal and ("signal " .. detail.signal) or "a signal")
		elseif action == "oom" then
			return "zap", "error", name .. " ran out of memory"
		elseif action == "restart" then
			return "rotate-cw", "info", name .. " restarted"
		elseif action == "pause" then
			return "pause", "warning", name .. " paused"
		elseif action == "unpause" then
			return "play", "success", name .. " resumed"
		elseif action == "create" then
			return "plus", nil, name .. " created from " .. (detail.image or "an image")
		elseif action == "destroy" then
			return "trash-2", nil, name .. " removed"
		elseif string.sub(action, 1, 13) == "health_status" then
			local status = detail.status or string.match(action, ":%s*(.*)$") or ""
			return "heart-pulse",
				status == "healthy" and "success" or (status == "unhealthy" and "error" or "warning"),
				name .. " is " .. status
		end
		return "box", nil, name .. ": " .. action
	elseif item.type == "image" then
		if action == "pull" then
			return "download", "info", "pulled " .. name
		elseif action == "delete" or action == "untag" then
			return "trash-2", nil, (action == "untag" and "untagged " or "deleted ") .. name
		elseif action == "tag" then
			return "layers", nil, "tagged " .. name
		end
		return "layers", nil, "image " .. name .. ": " .. action
	elseif item.type == "volume" then
		local id = string.find(item.id or "", "^%x+$") and #(item.id or "") == 64 and string.sub(item.id, 1, 12)
			or item.id
		local what = action == "destroy" and "removed"
			or (
				action == "create" and "created"
				or (
					action == "mount"
						and ("mounted by " .. (detail.container and string.sub(detail.container, 1, 12) or "a container"))
					or action
				)
			)
		return "hard-drive", nil, "volume " .. tostring(id) .. " " .. what
	elseif item.type == "network" then
		return "network",
			nil,
			"network "
				.. name
				.. " "
				.. action
				.. (detail.container and (" " .. string.sub(detail.container, 1, 12)) or "")
	end
	return "activity", nil, tostring(item.type) .. " " .. name .. ": " .. action
end

function screens.activity(width)
	local rows = plain_rows("activity")
	local col = b.div():col():grow(1):min_w(0):min_h(0)
	col:child(P.title("Activity", "what the engine reported, newest first", {}))
	local problems = 0
	for _, item in ipairs(S.activity) do
		if is_problem(item) then
			problems += 1
		end
	end
	local options = {}
	for _, kind in ipairs(KINDS) do
		options[#options + 1] =
			{ id = kind.id, label = kind.label, count = kind.id == "problems" and problems or nil, tone = kind.tone }
	end
	col:child(
		parts_toolbar.plain(
			width,
			{ prefix = "pf:", options = options, current = S.plain_filter.activity or "all" },
			nil,
			"Filter activity"
		)
	)
	if #rows == 0 then
		return col:child(
			P.nothing(
				"Quiet",
				"Nothing happened since dockerpen looked. Start or stop something and it shows up here as it happens.",
				"activity",
				width
			)
		)
	end
	local tops = row_tops("activity")
	col:child(virtual("list", #rows, SIZE.row, function(index)
		local row = rows[index]
		local item = row.item
		local id = "row:" .. row.id
		local cursor = S.cursor.activity == row.id
		local mark, tone, text = describe(item)
		local exists = item.type == "container" and S.by_id[item.id] ~= nil
		local over = hovered(id) or hovered("ev:open:" .. row.id)
		local el = b.div():row():items_center():gap(10):h(SIZE.row):px(8):rounded(6):press(id):no_shrink()
		local level = glow(id, over)
		if cursor then
			chosen(el, true)
		elseif level > 0 then
			el:bg(alpha("foreground", 0.06 * level))
		end
		el:child(b.div():w(70):no_shrink():child(T(item.clock or "", "quiet", SIZE.small + 0.5)))
		local chip = b.div():size(22, 22):rounded(7):row():items_center():justify_center():no_shrink()
		chip:bg(alpha(tone or "foreground", tone and 0.14 or 0.07))
		chip:child(P.icon(mark, 13, tone or "dim"))
		el:child(chip)
		el:child(b.div():grow(1):min_w(0):child(P.line(text, "foreground", SIZE.body)))
		if exists then
			el:child(P.button("ev:open:" .. row.id, "Open", { variant = "ghost", size = "sm" }))
		end
		local previous = rows[index - 1]
		if previous == nil or previous.item.day ~= item.day then
			-- The day as the original wrote it: "Monday, Oct 5", in capitals.
			local day = string.upper((string.gsub(item.day or "", " 0(%d)", " %1")))
			return b.div()
				:col()
				:h(SIZE.row + 30)
				:no_shrink()
				:child(b.div():row():items_end():h(30):px(8):pb(4):child(T(day, "quiet", SIZE.tiny + 0.5)))
				:child(el)
		end
		return el
	end, { px = 8, pt = 4, tops = tops }))
	return col
end

return {
	screens = screens,
}
