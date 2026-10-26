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

-- Whether the page is as narrow as a pane of 80 columns: there the bars keep to one line, and their
-- verbs are icons alone.
local function tight()
	return S.width < 760
end

-- A verb of the whole of a screen, at the end of its title: an icon and a word, quiet (the icon
-- alone on a narrow page).
function toolbar.verb(id, label, name)
	return P.button(id, not tight() and label or nil, { variant = "ghost", size = "sm", icon = name, icon_size = 13 })
end

-- The bar of the list of containers: the field, the states, grouping, the order. On a narrow page it
-- keeps to one line, the field giving way first; elsewhere, where the list has less room than all of
-- it takes, the states go to a second line.
function toolbar.containers(width)
	local count = counts()
	local narrow = tight()
	local field_width, field_wide = nil, nil
	if not narrow and width >= 600 then
		field_width, field_wide = 220, 300
	end
	local field =
		P.field(S.field == "list", "Filter by name, image, port…", field_width, narrow and 90 or 120, field_wide)
	local options = {}
	for _, f in ipairs(FILTERS) do
		options[#options + 1] = {
			id = f.id,
			label = f.label,
			count = count[f.id],
			tone = f.id == "issues" and "error" or nil,
		}
	end
	local states = P.segmented("filter:", options, S.filter, narrow and 7 or 9)
	local group = P.button(
		"group",
		nil,
		{ variant = "ghost", size = "sm", icon = "folder-tree", icon_size = 14, selected = S.group }
	)
	local sort = P.button("sort", not narrow and SORT_LABELS[S.sort] or nil, {
		variant = "ghost",
		size = "sm",
		icon = "arrow-down-wide-narrow",
		icon_size = 13,
	})
	if narrow or width >= 690 then
		return b.div()
			:row()
			:items_center()
			:gap(6)
			:h(SIZE.bar)
			:pb(8)
			:px(14)
			:no_shrink()
			:child(field)
			:child(states)
			:child(group)
			:child(sort)
	end
	local first = b.div():row():items_center():gap(6):h(SIZE.control):child(field):child(group):child(sort)
	local second = b.div():row():items_center():h(SIZE.control):child(states)
	return b.div():col():gap(6):pb(8):px(14):no_shrink():child(first):child(second)
end

-- The bar of a list of another kind: the field and, where it has them, the segments that narrow it.
-- `segments` is `{ prefix =, options =, current = }` or nil; `extra` an element at the end; `hint` what
-- the field says while it is empty ("Filter images"). The field gives way to the segments where both
-- do not fit, and what still does not is cut at the edge rather than drawn past it.
function toolbar.plain(width, segments, extra, hint)
	local bar = b.div():row():items_center():gap(6):h(SIZE.bar):pb(8):px(14):no_shrink()
	local room = segments and #segments.options >= 6 and 700 or 470
	if width >= room then
		bar:child(P.field(S.field == "list", hint or "Filter by name, image, port…", width >= 600 and 220 or nil))
	end
	if segments then
		bar:child(P.segmented(segments.prefix, segments.options, segments.current))
	end
	if extra then
		bar:child(extra)
	end
	return bar
end

return toolbar
