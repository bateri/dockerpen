-- The command palette over the page: a box with the host's field at its head, what matches under
-- it, a group at a time, and what the keys do at its foot.

local lib_kit = require("../lib/kit")
local lib_sizes = require("../lib/sizes")
local model_palette = require("../model/palette")
local model_state = require("../model/state")
local parts_ui = require("./ui")
local alpha, b, ui = lib_kit.alpha, lib_kit.b, lib_kit.ui
local SIZE = lib_sizes.SIZE
local palette = model_palette.palette
local S = model_state.S
local P, T, glow, hovered = parts_ui.P, parts_ui.T, parts_ui.glow, parts_ui.hovered

local part = {}

local ITEM, GROUP, LIST_MOST = 34, 26, 340

-- A title with the characters that matched in the accent (`positions` count from 0).
local function title_of(text, positions, role)
	if #positions == 0 then
		return b.div():row():items_center():min_w(0):clip():child(T(text, role, SIZE.body + 0.5):truncate())
	end
	local marked = {}
	for _, at in ipairs(positions) do
		marked[at] = true
	end
	local row = b.div():row():items_center():min_w(0):clip()
	local run, bold, index = "", false, 0
	local function flush()
		if run ~= "" then
			row:child(T(run, bold and "accent" or role, SIZE.body + 0.5, bold and 650 or nil):no_shrink())
		end
		run = ""
	end
	for _, code in utf8.codes(text) do
		local is = marked[index] == true
		if is ~= bold then
			flush()
			bold = is
		end
		run ..= utf8.char(code)
		index += 1
	end
	flush()
	return row
end

-- Where the entry `index` starts in the list, so that it can be kept in view: a group's name is a
-- line of the list, and the entries are the same height.
local function layout_of(list)
	local tops, y, last = {}, 0, nil
	for index, item in ipairs(list) do
		if item.entry.group ~= last then
			last = item.entry.group
			y += GROUP
		end
		tops[index] = y
		y += ITEM
	end
	return tops, y
end

function part.view()
	local p = S.palette
	local list = palette.shown()
	local width = math.min(560, S.width - 24)
	local top = math.min(math.floor(S.height * 0.12), 80)
	-- The list is as tall as it may be in the pane: the field (46 and its line), the foot (34), a margin.
	local most = math.max(math.min(LIST_MOST, S.height - top - 47 - 34 - 12), ITEM + 12)
	local box = b.div()
		:col()
		:w(width)
		:rounded(16)
		:bg("raised2")
		:border(1, alpha("border", 0.7))
		:clip()
		:shadow(0, 12, 32, alpha("shadow", 0.55))
	-- The field, with what to press to leave.
	box:child(
		b.div()
			:row()
			:items_center()
			:gap(10)
			:h(46)
			:px(14)
			:no_shrink()
			:child(P.icon("search", 16, "quiet"))
			:child(P.room(24, "Type a command, a container, an image…"))
			:child(P.kbd("esc"))
	)
	box:child(b.div():h(1):bg(alpha("border", 0.5)):no_shrink())
	local tops, total = layout_of(list)
	local scroll =
		b.div():col():id("palette.list"):h(math.min(total + 12, most)):scroll_y(ui:scroll_offset("palette.list")):p(6)
	if #list == 0 then
		scroll:child(b.div():col():items_center():pt(22):pb(22):child(T("Nothing is called that.", "dim", SIZE.body)))
	end
	local last = nil
	for index, item in ipairs(list) do
		local entry = item.entry
		if entry.group ~= last then
			last = entry.group
			scroll:child(
				b.div()
					:h(GROUP)
					:px(10)
					:pt(10)
					:no_shrink()
					:child(T(string.upper(entry.group), "quiet", SIZE.tiny + 0.5, 500))
			)
		end
		local id = "palette:item:" .. index
		local active = index == p.active
		local role = entry.tone or "foreground"
		local row = b.div():row():items_center():gap(10):h(ITEM):px(10):rounded(8):press(id):no_shrink()
		local level = glow(id, hovered(id) and not active)
		if active then
			row:bg(alpha("accent", 0.13))
		elseif level > 0 then
			row:bg(alpha("foreground", 0.05 * level))
		end
		row:child(P.icon(entry.icon, 15, entry.tone or "dim"))
		row:child(b.div():grow(1):min_w(0):child(title_of(entry.title, item.positions, role)))
		if entry.detail then
			row:child(b.div():max_w(220):min_w(0):no_shrink():child(T(entry.detail, "quiet", SIZE.small):truncate()))
		end
		if entry.keys then
			row:child(P.kbd(entry.keys))
		end
		scroll:child(row)
	end
	-- Keeps the entry the keys are on in view.
	if p.reveal then
		p.reveal = false
		local view = math.min(total + 12, most) - 12
		local top = tops[p.active] or 0
		local offset = ui:scroll_offset("palette.list")
		if top - GROUP < offset then
			ui:set_scroll("palette.list", math.max(top - GROUP, 0))
		elseif top + ITEM > offset + view then
			ui:set_scroll("palette.list", top + ITEM - view)
		end
	end
	box:child(scroll)
	box:child(b.div():h(1):bg(alpha("border", 0.5)):no_shrink())
	local foot = b.div():row():items_center():gap(14):px(14):py(8):no_shrink()
	local function hint(keys, label)
		local row = b.div():row():items_center():gap(5)
		for _, key in ipairs(keys) do
			row:child(P.kbd(key))
		end
		return row:child(T(label, "quiet", SIZE.small))
	end
	foot:child(hint({ "↑", "↓" }, "choose"))
	foot:child(hint({ "⏎" }, S.typing and "to the list" or "run"))
	foot:child(hint({ "esc" }, S.typing and "to the list" or "close"))
	box:child(foot)
	return b.div()
		:absolute()
		:inset(0, 0, 0, 0)
		:col()
		:items_center()
		:pt(top)
		:bg(alpha("background", 0.62))
		:press("palette:backdrop")
		:child(box)
end

return part
