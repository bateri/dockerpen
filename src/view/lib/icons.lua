-- The page's icons: Lucide's drawings (src/assets/icons/, with their licence), each a stroke on a 24
-- grid in black. `tint` makes every pixel of one the colour asked for and keeps the drawing's own
-- opacity, so an icon wears the theme's roles like any text does.
local kit = require("./kit")
local b = kit.b

local icons = {}

-- An icon `size` points square, in a role of the theme (`dim` when none is asked for).
function icons.icon(name, size, role)
	size = size or 14
	return b.image("assets/icons/" .. name .. ".svg"):size(size, size):tint(role or "dim"):no_shrink()
end

return icons
