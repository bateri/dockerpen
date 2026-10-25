-- The bar under the title of a screen: the field that filters it, and what else narrows or orders it.
-- The title's own verbs (Pull, Clean up) are quiet buttons at the end of the title.

local lib_kit = require("../lib/kit")
local lib_sizes = require("../lib/sizes")
local model_rows = require("../model/rows")
local model_state = require("../model/state")
local parts_ui = require("./ui")
local b = lib_kit.b
local FILTERS, SIZE = lib_sizes.FILTERS, lib_sizes.SIZE
local SORT_LABELS, counts = model_rows.SORT_LABELS, model_rows.counts
local S = model_state.S
local P = parts_ui.P

local toolbar = {}

-- A verb of the whole of a screen, at the end of its title: an icon and a word, quiet.
function toolbar.verb(id, label, name, width)
	return P.button(
		id,
		(width or 1000) >= 560 and label or nil,
		{ variant = "ghost", size = "sm", icon = name, icon_size = 13 }
	)
end

-- The bar of the list of containers: the field, the states, grouping, the order.
function toolbar.containers(width)
	local count = counts()
	local bar = b.div():row():items_center():gap(6):h(SIZE.bar):pb(8):px(14):no_shrink()
	bar:child(P.field(S.field == "list", "Filter by name, image, port…", width >= 600 and 220 or nil))
	local options = {}
	for _, f in ipairs(FILTERS) do
		options[#options + 1] = {
			id = f.id,
			label = f.label,
			count = count[f.id],
			tone = f.id == "issues" and "error" or nil,
		}
	end
	bar:child(P.segmented("filter:", options, S.filter))
	bar:child(P.button("group", nil, { variant = "ghost", icon = "folder-tree", icon_size = 14, selected = S.group }))
	bar:child(P.button("sort", width >= 560 and SORT_LABELS[S.sort] or nil, {
		variant = "ghost",
		size = "sm",
		icon = "arrow-down-wide-narrow",
		icon_size = 13,
	}))
	return bar
end

-- The bar of a list of another kind: the field and, where it has them, the segments that narrow it.
-- `segments` is `{ prefix =, options =, current = }` or nil; `extra` an element at the end.
function toolbar.plain(width, segments, extra)
	local bar = b.div():row():items_center():gap(6):h(SIZE.bar):pb(8):px(14):no_shrink()
	bar:child(P.field(S.field == "list", "Filter by name, image, port…", width >= 600 and 220 or nil))
	if segments then
		bar:child(P.segmented(segments.prefix, segments.options, segments.current))
	end
	if extra then
		bar:child(extra)
	end
	return bar
end

return toolbar
