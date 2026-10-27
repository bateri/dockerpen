-- Long lists: only the rows near what is in view are made, and the length of the rest of the list is
-- two spacers. The kit's long list does it (`:list`): more rows the way the list goes than behind
-- it, made again only when what is in view comes near the end of what was made, the frame for it
-- asked for by the kit when the host scrolls the list there.
local lib_kit = require("./kit")
local b = lib_kit.b

local views = {} -- how tall each scrolling box was laid out, by its id

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
	-- height. The room above the first row (`pt` and `lead`) and below the last is the list's, not
	-- the box's padding: the rows are found by it.
	local tops = options.tops
	local rows = tops and #tops == count + 1 and b.Rows.from_tops(tops) or b.Rows.even(count, height)
	rows:padded((options.pt or 0) + (options.lead or 0), options.trail or 8)
	return b.div():col():id(id):grow(1):min_h(0):scroll():px(options.px or 8):list(rows, make)
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
