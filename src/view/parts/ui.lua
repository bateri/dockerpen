-- The small things a screen is made of: text, a button, a tag, a dot, a meter, a field, a segmented
-- control. Every colour is a role of the theme: the ground a step above the page is `raised1`, a
-- control's is `raised2`, and what is chosen is the accent at an eighth with a line of it round.

local lib_icons = require("../lib/icons")
local lib_kit = require("../lib/kit")
local lib_sizes = require("../lib/sizes")
local model_containers = require("../model/containers")
local model_state = require("../model/state")
local alpha, b, ui = lib_kit.alpha, lib_kit.b, lib_kit.ui
local icon = lib_icons.icon
local SIZE, SPARK = lib_sizes.SIZE, lib_sizes.SPARK
local failed, state_of = model_containers.failed, model_containers.state_of
local S = model_state.S

local P = {}

-- The name of the host's text field: one at a time on the page, the room of whichever box is the
-- field now (the list's filter, the palette, a question's name), so that what was typed stays as the
-- room moves.
local FIELD = "field.room"

-- What a button that is an icon alone is to a screen reader, by its icon.
local ICON_WORDS = {
	x = "Close",
	ellipsis = "More",
	["rotate-cw"] = "Restart",
	["scroll-text"] = "Logs",
	["square-terminal"] = "Shell",
	play = "Start",
	square = "Stop",
	eraser = "Clear",
	copy = "Copy",
	["arrow-right-left"] = "Follow",
	["arrow-down-wide-narrow"] = "Sort",
	trash = "Remove",
	["trash-2"] = "Remove",
	["folder-tree"] = "Group by compose project",
	download = "Pull an image",
	sparkles = "Remove what nothing uses",
}

-- What a button that is an icon alone says while the pointer rests on it, beyond its words, and
-- the key that does the same, as the web page's tips did.
local ICON_TIPS = {
	x = { "Close", "esc" },
	ellipsis = { "More", "." },
	["rotate-cw"] = { "Restart", "r" },
	["scroll-text"] = { "Logs", "l" },
	["square-terminal"] = { "Shell, in the terminal", "e" },
	["arrow-right-left"] = { "Follow in the terminal, with nothing in between", "F" },
	["folder-tree"] = { "Group by compose project", "P" },
	eraser = { "Clear the view (the container's log stays)" },
}

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

-- How far the highlight named `key` has come, 0 to 1, on its way in while `on` and out while not:
-- a ground or a colour that the pointer brings comes and goes over the kit's fade (an eighth of a
-- second) instead of switching, as the web page's did over its transition. The page is drawn again
-- while one is on its way (`page.lua`'s `render`); under Reduce Motion each is where it is going.
local function glow(key, on)
	local name = "glow:" .. key
	if S.reduce_motion then
		ui.fades:snap(name, on and 1 or 0)
	else
		ui.fades:to(name, on and 1 or 0)
	end
	return ui.fades:level(name)
end

-- The highlight of what the pointer is over, by the element's id.
local function hover_glow(id)
	return glow(id, ui.hover == id)
end

-- A colour on its way from `from` to `to`, as far as `level` (0 to 1): a ground a highlight comes
-- in on, `dim` words that brighten to `foreground` with it.
local function blend(from, to, level)
	if level <= 0 then
		return from
	elseif level >= 1 then
		return to
	end
	return b.mix(from, to, level)
end

-- What is chosen: the accent at an eighth, with a line of it round (`strong`: the keys are here).
local function chosen(el, strong)
	return el:bg(alpha("accent", 0.13)):border(1, alpha("accent", strong and 0.55 or 0.3))
end

-- An icon, by name, in a role.
function P.icon(name, size, role)
	return icon(name, size, role)
end

-- A key cap: the key that does the same as what stands beside it, `box` points square at the least.
function P.kbd(label, size, box)
	box = box or 18
	return b.div()
		:row()
		:items_center()
		:justify_center()
		:min_w(box)
		:h(box)
		:px(4)
		:rounded(4)
		:bg("raised2")
		:border(1, alpha("border", 0.7))
		:no_shrink()
		:child(T(label, "dim", size or SIZE.tiny + 0.5))
end

-- A button: a verb. `o`: `variant` ("default", "ghost", "primary", "danger", "danger-ghost"), `size`
-- ("sm" is a little smaller), `icon` (the name of one, before the label; with no label the button is a
-- square of it), `selected` (pressed in), `disabled`, `ink` (the role of its icon and label, in
-- place of the variant's).
function P.button(id, label, o)
	o = o or {}
	local variant = o.variant or (o.primary and "primary") or (o.danger and "danger-ghost") or "default"
	local small = o.size == "sm" or o.h ~= nil
	local height = o.h or (small and SIZE.small_control or SIZE.control)
	local over = hovered(id) and not o.disabled
	local level = glow(id, over)
	local down = ui.pressed == id and over
	local el = b.div():row():items_center():justify_center():gap(small and 5 or 6):h(height):rounded(6):no_shrink()
	if label == nil then
		el:w(height)
		-- Its icon alone says nothing to a person who does not see it.
		if o.icon then
			local words = o.label or ICON_WORDS[o.icon] or string.gsub(o.icon, "-", " ")
			el:label(words)
			local said = ICON_TIPS[o.icon]
			el:tip(o.tip or (said and said[1]) or words, o.keys or (said and said[2]))
		end
	else
		el:px(o.px or (small and 8 or 10))
	end
	local ink = "foreground"
	if o.disabled then
		ink = "quiet"
		if variant == "default" then
			el:border(1, alpha("border", 0.5))
		end
	else
		el:press(id)
		if o.selected then
			chosen(el, true)
		elseif variant == "primary" then
			ink = "background"
			el:bg(down and alpha("accent", 0.75) or (level > 0 and alpha("accent", 1 - 0.12 * level) or "accent"))
		elseif variant == "danger" then
			ink = "background"
			el:bg(down and alpha("error", 0.75) or (level > 0 and alpha("error", 1 - 0.12 * level) or "error"))
		elseif variant == "danger-ghost" then
			ink = "error"
			el:bg(down and alpha("error", 0.2) or (level > 0 and alpha("error", 0.12 * level) or nil))
		elseif variant == "ghost" then
			ink = blend("dim", "foreground", level)
			el:bg(down and alpha("foreground", 0.1) or (level > 0 and alpha("foreground", 0.06 * level) or nil))
		else
			el:bg(down and "raised4" or blend("raised2", "raised3", level)):border(1, alpha("border", 0.6))
		end
	end
	if o.ink and not o.disabled then
		ink = o.ink
	end
	if o.icon then
		el:child(icon(o.icon, o.icon_size or (small and 12 or 13), ink))
	end
	if label then
		el:child(
			T(
				label,
				ink,
				o.size_text or (small and 11.5 or SIZE.body),
				(variant == "primary" or variant == "danger") and 600 or nil
			)
		)
	end
	if o.suffix then
		el:child(T(o.suffix, o.disabled and "quiet" or alpha(ink, 0.55), small and SIZE.small or SIZE.small + 0.5))
	end
	return el
end

-- A button that is an icon alone, as the verbs on a row are: quiet until the pointer is over it.
-- `label`, `tip` and `keys` say what it does where its icon alone does not.
function P.icon_button(id, name, o)
	o = o or {}
	return P.button(id, nil, {
		variant = "ghost",
		size = "sm",
		icon = name,
		icon_size = o.icon_size or 12,
		disabled = o.disabled,
		selected = o.selected,
		label = o.label,
		tip = o.tip,
		keys = o.keys,
	})
end

-- A word in a coloured label: what a container is, what an image is used by. With no role it is a
-- plain one.
function P.tag(label, role, size)
	local ink = role or "dim"
	return b.div()
		:row()
		:items_center()
		:h(18)
		:px(6)
		:rounded(4)
		:bg(role and alpha(role, 0.13) or "raised2")
		:no_shrink()
		:child(T(label, ink, size or SIZE.tiny + 0.5))
end

-- A mark of a count on a row of the rail: the number in a red pill.
function P.badge(n)
	return b.div()
		:row()
		:items_center()
		:justify_center()
		:min_w(16)
		:h(16)
		:px(4)
		:rounded(8)
		:bg("error")
		:no_shrink()
		:child(T(tostring(n), "background", SIZE.tiny, 650))
end

-- A ring, or a disc, of a colour.
local function ring(role, size)
	return b.div():size(size, size):rounded(size / 2):border(1.5, role):no_shrink()
end

-- The mark of what a container is doing: a disc in a halo where it runs (red where it is unhealthy,
-- amber while it starts), half a disc where it is paused, a ring where it is not (red where it
-- failed), a ring of the accent where it is waiting for something it was asked, an amber one while
-- it restarts.
function P.dot(c)
	local box = b.div():row():items_center():justify_center():size(16, 16):no_shrink()
	local _, role = state_of(c)
	if S.busy[c.id] then
		return box:child(ring("accent", 10))
	elseif c.state == "restarting" then
		return box:child(ring("warning", 10))
	elseif c.state == "running" then
		local colour = c.health == "unhealthy" and "error" or (c.health == "starting" and "warning" or "success")
		return box:child(
			b.div()
				:size(16, 16)
				:rounded(8)
				:row()
				:items_center()
				:justify_center()
				:bg(alpha(colour, colour == "success" and 0.18 or 0.2))
				:child(b.div():size(10, 10):rounded(5):bg(colour))
		)
	elseif c.state == "paused" then
		return box:child(
			b.div()
				:size(10, 10)
				:rounded(5)
				:border(1.5, "warning")
				:row()
				:child(b.div():w(4):h(7):rounded_corners({ 3.5, 0, 0, 3.5 }):bg("warning"))
		)
	elseif c.state == "dead" or failed(c) then
		return box:child(ring("error", 10))
	end
	return box:child(ring(role == "dim" and "quiet" or role, 10))
end

-- A round mark of a plain role: a disc, or a ring (the engine, a job).
function P.disc(role, size, solid)
	size = size or 8
	local dot = b.div():size(size, size):rounded(size / 2):no_shrink()
	if solid == false then
		return dot:border(1.5, role)
	end
	return dot:bg(role)
end

-- A disc of `size` (7) in a halo of its colour three points wide: what runs, as the engine does.
function P.halo(role, size)
	size = size or 7
	local outer = size + 6
	return b.div()
		:size(outer, outer)
		:rounded(outer / 2)
		:bg(alpha(role, 0.18))
		:row()
		:items_center()
		:justify_center()
		:no_shrink()
		:child(P.disc(role, size))
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
	local row = b.div():row():items_center():gap(10):min_h(SIZE.head):pt(10):pb(8):px(14):no_shrink()
	row:child(T(name, "foreground", SIZE.title, 650):no_shrink())
	if subtitle then
		row:child(T(subtitle, "quiet", SIZE.small + 0.5):truncate():min_w(0))
	end
	row:child(b.spacer())
	for _, verb in ipairs(verbs or {}) do
		row:child(verb)
	end
	return row
end

-- A row of tabs: what is shown is one of them.
function P.tabs(list, current, prefix)
	local row = b.div():row():items_end():gap(2):px(16):h(34):no_shrink()
	for _, tab in ipairs(list) do
		local id = prefix .. tab.id
		local active = tab.id == current
		local level = glow(id, hovered(id) and not active)
		row:child(
			b.div()
				:press(id)
				:col()
				:justify_end()
				:px(10)
				:h(34)
				:no_shrink()
				:bg(level > 0 and alpha("foreground", 0.05 * level) or nil)
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
		:child(b.div():w(112):no_shrink():child(T(label, "quiet", SIZE.small + 0.5)))
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

-- A screen with nothing on it, in the middle of the room it has: a mark, what it is, and what to do,
-- in lines of at most 46 characters (or what `width`, 400 where it is not said, has room for).
function P.nothing(title, hint, mark, width)
	local col = b.div():col():grow(1):items_center():justify_center():gap(8):py(40):px(20):no_shrink()
	if mark then
		col:child(
			b.div()
				:size(44, 44)
				:rounded(12)
				:bg("raised1")
				:border(1, alpha("border", 0.6))
				:row()
				:items_center()
				:justify_center()
				:no_shrink()
				:child(icon(mark, 20, "dim"))
		)
	end
	col:child(T(title, "foreground", 13, 600))
	if hint then
		-- At most 46 characters a line, as the first dockerpen's `max-width: 46ch`.
		local room = math.min((width or 400) - 40, 46 * SIZE.body * 0.62)
		col:child(T(hint, "dim", SIZE.body):wrap():align("center"):max_w(room))
	end
	return col
end

-- A card: a surface a step above the page.
function P.card()
	return b.div():col():gap(2):px(12):py(10):rounded(12):bg("raised1"):border(1, alpha("border", 0.6))
end

-- The field of the host, or what it says where it is not here. The host's text field has one
-- place at a time on the page, the room of the element that says it is one; `hint` is what it says
-- while it is empty either way (the text in its room is the host field's hint, and the page does not
-- draw it). `width` fixes its width (else it takes what there is), `min` is the least it gives way to
-- (120).
function P.field(active, hint, width, min, wide)
	-- While the keyboard is in it the box comes forward, as the web page's did over a fifth of a second:
	-- the page's ground, the accent's line and a soft ring of it round the box, and (where `wide` says)
	-- more room. The host moves it there and back.
	local on = active and S.typing
	local box = b.div()
		:row()
		:items_center()
		:gap(7)
		:h(SIZE.control)
		:pl(8)
		:pr(5)
		:rounded(6)
		:bg(on and "background" or "raised1")
		:border(1, on and "accent" or alpha("border", 0.6))
		:press("field")
		:motion({ seconds = 0.2, color = true, size = true })
	if width then
		box:w(on and wide or width):min_w(min or 120)
	else
		box:grow(1):min_w(min or 120)
	end
	-- The ring: three points outside the box, the accent at a little under a fifth.
	box:child(
		b.div()
			:id("field.ring")
			:absolute()
			:inset(-3, -3, -3, -3)
			:rounded(9)
			:border(3, alpha("accent", on and 0.18 or 0))
			:motion({ seconds = 0.2, color = true })
	)
	box:child(icon("search", 14, "quiet"))
	if active then
		box:child(P.room(18, hint))
	else
		box:child(b.div():grow(1):min_w(0):child(T(hint, "quiet", SIZE.body):truncate()))
	end
	return box:child(P.kbd("/", SIZE.tiny + 0.5, 18))
end

-- The room of the host's text field, `height` tall, that says `hint` while it is empty.
function P.room(height, hint)
	return b.div():text_field(FIELD):grow(1):min_w(0):h(height):child(T(hint, "quiet", SIZE.body))
end

-- The mark of a row that can be chosen with space: filled when it is.
function P.check(on)
	local box = b.div():size(16, 16):rounded(4):no_shrink()
	if on then
		return box:bg("accent"):row():items_center():justify_center():child(icon("check", 12, "background"))
	end
	return box:bg("background"):border(1.5, "border")
end

-- A segmented control: `options` are `{ id =, label =, count =, tone = }`, `current` the id that is
-- on, and each one is named `prefix .. id` for a click; `seg_px` the room each has at its sides (9).
function P.segmented(prefix, options, current, seg_px)
	local control =
		b.div():row():items_center():gap(1):p(2):rounded(8):bg("raised1"):border(1, alpha("border", 0.6)):no_shrink()
	for _, option in ipairs(options) do
		local id = prefix .. option.id
		local active = option.id == current
		local seg = b.div():row():items_center():gap(6):h(24):px(seg_px or 9):rounded(6):press(id):no_shrink()
		local level = glow(id, hovered(id) and not active)
		if active then
			seg:bg("raised2"):border(1, alpha("border", 0.8))
		elseif level > 0 then
			seg:bg(alpha("foreground", 0.05 * level))
		end
		seg:child(T(option.label, active and "foreground" or blend("dim", "foreground", level), SIZE.body))
		if option.count ~= nil then
			local role = option.tone and option.count > 0 and option.tone or (active and "dim" or "quiet")
			seg:child(T(tostring(option.count), role, SIZE.tiny + 0.5))
		end
		control:child(seg)
	end
	return control
end

-- A switch with its word: on or off.
function P.switch(id, label, on)
	local level = hover_glow(id)
	local track = b.div():w(26):h(14):rounded(7):no_shrink():row():items_center():px(2)
	track:bg(on and "accent" or alpha("foreground", 0.16 + 0.06 * level))
	if on then
		track:justify_end()
	end
	track:child(b.div():size(10, 10):rounded(5):bg(on and "background" or "dim"))
	return b.div()
		:row()
		:items_center()
		:gap(6)
		:h(24)
		:px(4)
		:press(id)
		:no_shrink()
		:child(track)
		:child(T(label, blend("dim", "foreground", level), SIZE.body))
end

-- The bars that stand for the containers of a project, one each (the first twelve), in the colour
-- `colour(c)` says.
function P.stack(members, colour)
	local marks = b.div():row():gap(2):items_center():no_shrink()
	for index, c in ipairs(members) do
		if index > 12 then
			break
		end
		marks:child(b.div():size(5, 10):rounded(2):bg(colour(c)))
	end
	return marks
end

-- How many characters of `size` a line `width` points wide has room for (a terminal's font has the
-- same width for each, a little over a half of its size).
function P.cols(width, size)
	return math.max(math.floor(width / ((size or SIZE.body) * 0.62)), 8)
end

-- Words as lines of at most `cols` characters, cut at the spaces (and, where a word is longer than a
-- line, in it): `{ "a line", "another" }`. At most `most` lines; the last ends in `…` where there was more.
function P.wrap(text, cols, most)
	local lines = {}
	for paragraph in string.gmatch(text .. "\n", "([^\n]*)\n") do
		local line = ""
		for word in string.gmatch(paragraph, "%S+") do
			while (utf8.len(word) or #word) > cols do
				if line ~= "" then
					lines[#lines + 1], line = line, ""
				end
				local cut = utf8.offset(word, cols + 1) or (#word + 1)
				lines[#lines + 1] = string.sub(word, 1, cut - 1)
				word = string.sub(word, cut)
			end
			local joined = line == "" and word or (line .. " " .. word)
			if (utf8.len(joined) or #joined) > cols then
				lines[#lines + 1] = line
				line = word
			else
				line = joined
			end
		end
		lines[#lines + 1] = line
		if most and #lines > most then
			break
		end
	end
	if most and #lines > most then
		while #lines > most do
			lines[#lines] = nil
		end
		lines[most] = (string.gsub(lines[most], "%s*$", "")) .. "…"
	end
	return lines
end

-- Words in as many lines as they take in at most `width` points: the kit breaks them where the
-- terminal's font says. With `most`, at most that many lines, the last ending in `…` where there was
-- more: the kit does not count lines, so those are cut here, by the width of a character of the
-- terminal's face (see `P.wrap`).
function P.paragraph(text, width, role, size, weight, most)
	if most == nil then
		return T(text, role, size, weight):wrap():max_w(width):min_w(0)
	end
	local col = b.div():col():min_w(0)
	for _, line in ipairs(P.wrap(text, P.cols(width, size), most)) do
		col:child(T(line, role, size, weight):no_shrink())
	end
	return col
end

-- Some words are said in a line; this cuts them to the room the line has.
function P.line(content, role, size, weight)
	return T(content, role or "foreground", size or SIZE.body, weight):truncate()
end

return {
	FIELD = FIELD,
	LINE_MOST = LINE_MOST,
	P = P,
	T = T,
	chosen = chosen,
	blend = blend,
	glow = glow,
	hover_glow = hover_glow,
	hovered = hovered,
}
