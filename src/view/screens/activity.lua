local lib_kit = require("../lib/kit")
local lib_sizes = require("../lib/sizes")
local lib_virtual = require("../lib/virtual")
local model_containers = require("../model/containers")
local model_rows = require("../model/rows")
local model_state = require("../model/state")
local parts_ui = require("../parts/ui")
local alpha, b = lib_kit.alpha, lib_kit.b
local SIZE = lib_sizes.SIZE
local virtual = lib_virtual.virtual
local ago = model_containers.ago
local plain_rows = model_rows.plain_rows
local S = model_state.S
local P, T, hovered = parts_ui.P, parts_ui.T, parts_ui.hovered

local screens = {}

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

return {
	screens = screens,
}
