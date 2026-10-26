-- The tables of images, volumes and networks: the heads of the columns, a row with the look of one
-- that is chosen, marked or under the pointer, and the cells they have in common.

local lib_kit = require("../lib/kit")
local lib_sizes = require("../lib/sizes")
local model_state = require("../model/state")
local parts_ui = require("./ui")
local alpha, b = lib_kit.alpha, lib_kit.b
local SIZE = lib_sizes.SIZE
local S = model_state.S
local P, T, chosen, hover_glow, lit = parts_ui.P, parts_ui.T, parts_ui.chosen, parts_ui.hover_glow, parts_ui.lit

local table_part = {}

-- The head of a table: a word for each column (`{ label =, sort =, align = }`; the first is the
-- column of the marks), and under it a line.
function table_part.head(tracks, columns, sorted)
	local row = b.div():grid(tracks):gap_x(10):items_center():h(28):px(16):no_shrink()
	row:child(b.div())
	for _, column in ipairs(columns) do
		local cell = b.div():row():items_center():gap(3):min_w(0)
		if column.align == "end" then
			cell:justify_end()
		end
		local id = column.sort and ("sorth:" .. column.sort) or nil
		local active = column.sort ~= nil and sorted == column.sort
		if id then
			cell:press(id)
		end
		cell:child(
			T(
				string.upper(column.label),
				(active or (id and lit(hover_glow(id)))) and "dim" or "quiet",
				SIZE.tiny + 0.5,
				500
			):truncate()
		)
		if active then
			cell:child(P.icon("chevron-down", 11, "dim"))
		end
		row:child(cell)
	end
	return b.div():col():no_shrink():child(row):child(b.div():h(1):bg(alpha("border", 0.6)))
end

-- A row: the grid the head has, framed as the cursor, a mark or the pointer say (`level`: how far
-- the pointer's highlight has come, 0 to 1).
function table_part.row(tracks, id, cursor, level, marked_on)
	local el = b.div():grid(tracks):gap_x(10):items_center():h(SIZE.row):px(8):rounded(6):press(id):no_shrink()
	if cursor then
		chosen(el, true)
	elseif marked_on then
		el:bg(alpha("accent", 0.09))
	elseif level > 0 then
		el:bg(alpha("foreground", 0.06 * level))
	end
	return el
end

-- The first cell of a row: a box to mark with where something is marked, else a quiet icon.
function table_part.lead(row_id, marked_on, mark, name)
	local cell = b.div():row():items_center():justify_center()
	if S.any_marked then
		return cell:press("mark:" .. row_id):child(P.check(marked_on))
	end
	if name == "chevron-right" or name == "chevron-down" then
		return cell:press("layers:toggle:" .. row_id)
			:child(P.icon(name, 13, lit(hover_glow("layers:toggle:" .. row_id)) and "foreground" or "quiet"))
	end
	return cell:child(P.icon(name, 13, "quiet"))
end

-- A size and a bar of how much it is of the largest.
function table_part.size_cell(text, fraction, role)
	local cell = b.div():row():items_center():gap(8):min_w(0)
	cell:child(b.div():w(64):no_shrink():child(T(text, "foreground", SIZE.small + 1):align("end")))
	cell:child(P.meter(fraction, role or "quiet"))
	return cell
end

-- What something is used by: how many, and who; or that nothing is.
function table_part.used_by(names, none)
	if #names == 0 then
		return T(none or "unused", "quiet", SIZE.small + 1)
	end
	local cell = b.div():row():items_center():gap(8):min_w(0)
	cell:child(P.tag(tostring(#names), "success"))
	cell:child(P.line(table.concat(names, ", "), "dim", SIZE.small + 1))
	return cell
end

return table_part
