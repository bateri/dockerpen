-- Long lists: only the rows in view are made, and the length of the rest of the list is two spacers.
local lib_kit = require("./kit")
local b, ui = lib_kit.b, lib_kit.ui

local views = {} -- how tall each scrolling box was laid out, by its id

local OVERSCAN = 3

-- Where row `index` starts, and how tall it is: rows of one `height`, or, where the list says
-- `tops` (`tops[i]` is where row i starts, `tops[#tops]` the end of the last), the heights it has.
local function place(index, height, tops)
	if tops then
		return tops[index], tops[index + 1] - tops[index]
	end
	return (index - 1) * height, height
end

-- The first row that ends below `y`.
local function row_at(y, count, height, tops)
	if tops == nil then
		return math.max(1, math.min(count, math.floor(y / height) + 1))
	end
	local low, high = 1, count
	while low < high do
		local middle = (low + high) // 2
		if tops[middle + 1] <= y then
			low = middle + 1
		else
			high = middle
		end
	end
	return low
end

-- A list of `count` rows, of which the ones in view and a few around them are made (`make(index)`).
-- `options`: `tops` (the rows are not all of one `height`), `lead` (room before the first),
-- `px`, `pt`, `trail`.
local function virtual(id, count, height, make, options)
	options = options or {}
	local tops = options.tops
	local offset = lib_kit.offset(id)
	local view = views[id] or 480
	local lead = options.lead or 0
	local first = math.max(1, row_at(offset - lead, count, height, tops) - OVERSCAN)
	local last = math.min(count, row_at(offset + view - lead, count, height, tops) + OVERSCAN)
	local box = b.div():col():id(id):grow(1):min_h(0):scroll():px(options.px or 8)
	if options.pt then
		box:pt(options.pt)
	end
	if lead > 0 then
		box:child(b.div():h(lead):no_shrink())
	end
	local before = place(first, height, tops)
	box:child(b.div():h(math.max(before, 0)):no_shrink())
	for index = first, last do
		box:child(make(index))
	end
	local after_top, after_height = 0, 0
	if count >= 1 then
		after_top, after_height = place(last, height, tops)
	end
	local total = count >= 1 and (tops and tops[count + 1] or count * height) or 0
	box:child(b.div():h(math.max(total - (after_top + after_height), 0) + (options.trail or 8)):no_shrink())
	return box
end

-- Scrolls the least that shows row `index` of the list `id`.
local function reveal(id, index, count, height, lead, tops)
	local view = views[id] or 480
	lead = lead or 0
	local start, tall = place(index, height, tops)
	local top = lead + start
	local bottom = top + tall
	local offset = lib_kit.offset(id)
	if top - (index == 1 and lead or 0) < offset then
		lib_kit.scroll_to(id, math.max(top - (index == 1 and lead or 0), 0))
	elseif bottom + (index == count and 8 or 0) > offset + view then
		lib_kit.scroll_to(id, math.max(bottom + (index == count and 8 or 0) - view, 0))
	end
end

return {
	reveal = reveal,
	views = views,
	virtual = virtual,
}
