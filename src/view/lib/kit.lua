-- What every file of the page shares of the kit: its builders, a colour with an opacity, the one
-- `Ui` that remembers the pointer of the page between frames, and how far the host has each box
-- scrolled. The host scrolls a box (the wheel, the trackpad, its bars, as the Mac does) and tells
-- the page where it went; the page asks for a box to go somewhere.
local b = pencere

-- How far the host has the box named `id` scrolled down, points.
local function offset(id)
	local y = b.layout.scroll_offset(id)
	return y
end

-- Asks the host to scroll the box named `id` down to `y` (past the end is the end), over a moment
-- where `animate`, before the page is next laid out.
local function scroll_to(id, y, animate)
	b.layout.scroll_to(id, { y = math.max(y, 0), animate = animate == true })
end

return { b = b, alpha = b.alpha, ui = b.Ui.new(), offset = offset, scroll_to = scroll_to }
