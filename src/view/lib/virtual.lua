-- Long lists: only the rows near what is in view are made, and the length of the rest of the list is
-- two spacers. Which rows, and when to make them again as the host scrolls the list, is the kit's
-- (`pencere.Built`): more of them the way the list goes than behind it, and made again only when
-- what is in view comes near the end of what was made, not at every turn of the wheel.
local lib_kit = require("./kit")
local b = lib_kit.b

local views = {} -- how tall each scrolling box was laid out, by its id
local built = {} -- which rows of each list were made and which way it goes, by its id
local lists = {} -- where the rows of each list stood when they were made, by its id

-- Where row `index` starts, and how tall it is: rows of one `height`, or, where the list says
-- `tops` (`tops[i]` is where row i starts, `tops[#tops]` the end of the last), the heights it has.
local function place(index, height, tops)
	if tops then
		return tops[index], tops[index + 1] - tops[index]
	end
	return (index - 1) * height, height
end

-- A list of `count` rows, of which the ones in view and those around them are made (`make(index)`).
-- `options`: `tops` (the rows are not all of one `height`), `lead` (room before the first),
-- `px`, `pt`, `trail`.
local function virtual(id, count, height, make, options)
	options = options or {}
	-- Where the rows stand: the list's tops while they are the tops of `count` rows, else rows of one
	-- height. Room before the first row is the box's and the list's.
	local tops = options.tops
	local rows = tops and #tops == count + 1 and b.Rows.from_tops(tops) or b.Rows.even(count, height)
	rows:padded((options.pt or 0) + (options.lead or 0), options.trail or 8)
	built[id] = built[id] or b.Built.new()
	lists[id] = rows
	local first, last = built[id]:span(rows, lib_kit.offset(id), views[id] or 480)
	local box = b.div():col():id(id):grow(1):min_h(0):scroll():px(options.px or 8)
	if options.pt then
		box:pt(options.pt)
	end
	if options.lead and options.lead > 0 then
		box:child(b.div():h(options.lead):no_shrink())
	end
	box:child(b.div():h(rows:top(first) - rows:top(1)):no_shrink())
	for index = first, last do
		box:child(make(index))
	end
	box:child(b.div():h(rows:total() - rows:top(last + 1)):no_shrink())
	return box
end

-- Whether the list `id`, scrolled to `offset` by the host, is to be made again: what is in view is
-- past the rows made, or near their end the way it goes. False for a box that is not a long list.
local function stale(id, offset)
	if lists[id] == nil then
		return false
	end
	return built[id]:stale(lists[id], offset, views[id] or 480)
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
	stale = stale,
	views = views,
	virtual = virtual,
}
