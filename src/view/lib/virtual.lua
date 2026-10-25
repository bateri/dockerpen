local lib_kit = require("./kit")
local b, ui = lib_kit.b, lib_kit.ui

-- ---- long lists: only the rows in view are made -----------------------------------------------

local views = {} -- how tall each scrolling box was laid out, by its id

local OVERSCAN = 3

-- A list of `count` rows of one `height`, of which the ones in view and a few around them are
-- made (`make(index)`): the rest of the list's length is two spacers.
local function virtual(id, count, height, make, options)
	options = options or {}
	local offset = ui:scroll_offset(id)
	local view = views[id] or 480
	local lead = options.lead or 0
	local first = math.max(1, math.floor((offset - lead) / height) + 1 - OVERSCAN)
	local last = math.min(count, math.ceil((offset + view - lead) / height) + OVERSCAN)
	local box = b.div():col():id(id):grow(1):min_h(0):scroll_y(offset):px(options.px or 8)
	if options.pt then
		box:pt(options.pt)
	end
	if lead > 0 then
		box:child(b.div():h(lead):no_shrink())
	end
	box:child(b.div():h(math.max(first - 1, 0) * height):no_shrink())
	for index = first, last do
		box:child(make(index))
	end
	box:child(b.div():h(math.max(count - last, 0) * height + (options.trail or 8)):no_shrink())
	return box
end

-- Scrolls the least that shows row `index` of the list `id`.
local function reveal(id, index, count, height, lead)
	local view = views[id] or 480
	lead = lead or 0
	local top = lead + (index - 1) * height
	local bottom = top + height
	local offset = ui:scroll_offset(id)
	if top - (index == 1 and lead or 0) < offset then
		ui:set_scroll(id, math.max(top - (index == 1 and lead or 0), 0))
	elseif bottom + (index == count and 8 or 0) > offset + view then
		ui:set_scroll(id, math.max(bottom + (index == count and 8 or 0) - view, 0))
	end
end

return {
	reveal = reveal,
	views = views,
	virtual = virtual,
}
