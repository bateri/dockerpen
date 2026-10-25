-- What every file of the page shares of the kit: its builders, a colour with an opacity, and the
-- one `Ui` that remembers the pointer and the scrolling of the page between frames.
local b = pencere

return { b = b, alpha = b.alpha, ui = b.Ui.new() }
