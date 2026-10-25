local lib_kit = require("../lib/kit")
local lib_sizes = require("../lib/sizes")
local model_containers = require("../model/containers")
local model_state = require("../model/state")
local alpha, b, ui = lib_kit.alpha, lib_kit.b, lib_kit.ui
local SIZE, SPARK = lib_sizes.SIZE, lib_sizes.SPARK
local state_of = model_containers.state_of
local S = model_state.S

-- ---- the small things a screen is made of ---------------------------------------------------------

local P = {}

-- The longest line of text the page makes (the kit takes 64 KiB, and ends a page that makes more).
local LINE_MOST = 4000

-- A line of text in a role, a size and a weight.
local function T(content, color, size, weight)
	if type(content) == "string" and #content > LINE_MOST then
		local cut = string.sub(content, 1, LINE_MOST)
		-- Not in the middle of a character.
		while #cut > 0 and utf8.len(cut) == nil do
			cut = string.sub(cut, 1, -2)
		end
		content = cut .. "…"
	end
	local t = b.text(content)
	if color then
		t:color(color)
	end
	if size then
		t:text_size(size)
	end
	if weight then
		t:weight(weight)
	end
	return t
end

local function hovered(id)
	return ui.hover == id
end

-- A key cap: the key that does the same as what stands beside it.
function P.kbd(label, size)
	return b.div()
		:row()
		:items_center()
		:justify_center()
		:min_w(16)
		:h(16)
		:px(4)
		:rounded(4)
		:bg("raised2")
		:no_shrink()
		:child(T(label, "dim", size or SIZE.tiny))
end

-- A button: a verb. `options`: `primary` (the one thing to do), `danger`, `key` (its shortcut, shown
-- beside it), `disabled`, `selected`.
function P.button(id, label, options)
	options = options or {}
	local over = hovered(id) and not options.disabled
	local down = ui.pressed == id and over
	local el = b.div():row():items_center():gap(7):h(options.h or 26):px(options.px or 10):rounded(6):no_shrink()
	local ink = "foreground"
	if options.disabled then
		ink = "quiet"
		el:border(1, alpha("border", 0.6))
	else
		el:press(id)
		if options.primary then
			ink = "background"
			el:bg(down and alpha("accent", 0.75) or (over and alpha("accent", 0.9) or "accent"))
		elseif options.danger then
			ink = "error"
			el:bg(over and alpha("error", down and 0.22 or 0.14) or nil):border(1, alpha("error", over and 0.9 or 0.5))
		else
			el:bg(over and (down and "raised4" or "raised3") or (options.selected and "raised3" or "raised2"))
				:border(1, "border")
		end
	end
	el:child(T(label, ink, options.size or SIZE.body, 500))
	if options.key then
		el:child(P.kbd(options.key))
	end
	return el
end

-- A word in a coloured label: what a container is, what an image is used by.
function P.tag(label, role, size)
	return b.div()
		:row()
		:items_center()
		:h(18)
		:px(6)
		:rounded(4)
		:bg(alpha(role, 0.14))
		:no_shrink()
		:child(T(label, role, size or SIZE.tiny + 0.5))
end

-- A round mark: solid for what is up, a ring for what is not.
function P.dot(role, solid, size)
	size = size or 9
	local dot = b.div():size(size, size):rounded(size / 2):no_shrink()
	if solid then
		return dot:bg(role)
	end
	return dot:border(1.5, role)
end

-- The mark of a container's state: solid when it runs, a ring when not, half-lit when it is waiting.
function P.state_dot(c)
	local _, role = state_of(c)
	if c.state == "running" then
		return P.dot(role, true)
	elseif c.state == "paused" or c.state == "restarting" or S.busy[c.id] then
		return P.dot(alpha(role, 0.55), true)
	end
	return P.dot(role, false)
end

-- A bar that is `fraction` full (0 to 1).
function P.meter(fraction, role, width, height)
	fraction = math.max(0, math.min(1, fraction or 0))
	height = height or 4
	local track = b.div():h(height):rounded(height / 2):bg("raised2"):clip():no_shrink()
	if width then
		track:w(width)
	else
		track:grow(1):min_w(0)
	end
	if fraction > 0 then
		track:child(b.div():w_pct(math.max(fraction * 100, 3)):h(height):rounded(height / 2):bg(role))
	end
	return track
end

-- A line of the last readings of something, newest last.
function P.spark(values, role, ceiling)
	local n = #values
	local from = math.max(1, n - SPARK + 1)
	local tail = {}
	for index = from, n do
		tail[#tail + 1] = values[index]
	end
	if #tail == 0 then
		return b.div()
	end
	local line = b.spark(tail, role)
	if ceiling then
		line:peak(ceiling)
	end
	return line:size_full()
end

-- The title of a screen: its name, what it holds, and the verbs of the whole of it at the end.
function P.title(name, subtitle, verbs)
	local row = b.div():row():items_center():gap(12):h(SIZE.head):px(20):no_shrink()
	row:child(T(name, "foreground", 16, 650):no_shrink())
	if subtitle then
		row:child(T(subtitle, "dim", SIZE.small + 0.5):truncate():min_w(0))
	end
	row:child(b.spacer())
	for _, verb in ipairs(verbs or {}) do
		row:child(verb)
	end
	return row
end

-- A row of tabs: what is shown is one of them.
function P.tabs(list, current, prefix)
	local row = b.div():row():items_end():gap(2):px(16):h(32):no_shrink()
	for _, tab in ipairs(list) do
		local id = prefix .. tab.id
		local active = tab.id == current
		local over = hovered(id)
		row:child(
			b.div()
				:press(id)
				:col()
				:justify_end()
				:px(10)
				:h(32)
				:no_shrink()
				:bg(over and not active and alpha("foreground", 0.05) or nil)
				:rounded_corners({ 5, 5, 0, 0 })
				:child(
					b.div()
						:grow(1)
						:row()
						:items_center()
						:child(T(tab.label, active and "foreground" or "dim", SIZE.body, active and 600 or 400))
				)
				:child(b.div():h(2):bg(active and "accent" or nil))
		)
	end
	return row
end

-- A label and its value, side by side: one fact.
function P.fact(label, value, role)
	return b.div()
		:row()
		:gap(14)
		:min_h(22)
		:items_start()
		:child(b.div():w(112):no_shrink():child(T(label, "dim", SIZE.small + 0.5)))
		:child(b.div():grow(1):min_w(0):child(T(value, role or "foreground", SIZE.body):truncate()))
end

-- A small heading over a group of facts.
function P.heading(label, extra)
	local row = b.div()
		:row()
		:items_center()
		:gap(8)
		:h(26)
		:mt(10)
		:no_shrink()
		:child(T(string.upper(label), "quiet", SIZE.tiny + 0.5, 600))
	if extra then
		row:child(extra)
	end
	return row
end

-- A line that says there is nothing here, and what to do.
function P.nothing(title, hint)
	return b.div()
		:col()
		:items_center()
		:gap(6)
		:pt(54)
		:px(20)
		:no_shrink()
		:child(T(title, "dim", SIZE.body + 1))
		:child(hint and T(hint, "quiet", SIZE.small):align("center") or b.div())
end

-- A card: a surface a step above the page.
function P.card()
	return b.div():col():gap(4):p(12):rounded(8):bg("raised1"):border(1, alpha("border", 0.7))
end

-- The field of the host, or what it says where it is not here. The host's text field has one
-- place at a time on the page, the room of the element that says it is one.
function P.field(active, hint, width)
	local box =
		b.div():row():items_center():gap(8):h(28):px(9):rounded(6):bg("raised1"):border(1, "border"):press("field")
	if width then
		box:w(width):min_w(120)
	else
		box:grow(1):min_w(120)
	end
	if active then
		box:child(b.div():id("field.room"):text_field():grow(1):min_w(0):h(18))
	else
		box:child(b.div():grow(1):min_w(0):child(T(hint, "quiet", SIZE.body):truncate()))
	end
	return box:child(P.kbd("/"))
end

-- The mark of a row that can be chosen with space: filled when it is.
function P.check(on)
	local box = b.div():size(14, 14):rounded(4):no_shrink()
	if on then
		return box:bg("accent")
			:child(b.div():size_full():row():items_center():justify_center():child(T("✓", "background", 10, 700)))
	end
	return box:border(1.2, alpha("foreground", 0.3))
end

-- Some words are said in a line; this cuts them to the room the line has.
function P.line(content, role, size, weight)
	return T(content, role or "foreground", size or SIZE.body, weight):truncate()
end

return {
	P = P,
	T = T,
	hovered = hovered,
}
