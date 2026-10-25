local lib_kit = require("../lib/kit")
local lib_fmt = require("../lib/fmt")
local lib_sizes = require("../lib/sizes")
local model_rows = require("../model/rows")
local model_state = require("../model/state")
local parts_ui = require("./ui")
local alpha, b = lib_kit.alpha, lib_kit.b
local fmt = lib_fmt.fmt
local SECTIONS, SIZE = lib_sizes.SECTIONS, lib_sizes.SIZE
local counts = model_rows.counts
local S = model_state.S
local P, T, hovered = parts_ui.P, parts_ui.T, parts_ui.hovered

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

return {
	frame = frame,
}
