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

-- What is chosen: the accent at an eighth, with a line of it round (`strong`: the keys are here).
local function chosen(el, strong)
	return el:bg(alpha("accent", 0.13)):border(1, alpha("accent", strong and 0.55 or 0.3))
end

-- An icon, by name, in a role.
function P.icon(name, size, role)
	return icon(name, size, role)
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
		:border(1, alpha("border", 0.7))
		:no_shrink()
		:child(T(label, "dim", size or SIZE.tiny))
end

-- A button: a verb. `o`: `variant` ("default", "ghost", "primary", "danger", "danger-ghost"), `size`
-- ("sm" is a little smaller), `icon` (the name of one, before the label; with no label the button is a
-- square of it), `selected` (pressed in), `disabled`.
function P.button(id, label, o)
	o = o or {}
	local variant = o.variant or (o.primary and "primary") or (o.danger and "danger-ghost") or "default"
	local small = o.size == "sm" or o.h ~= nil
	local height = o.h or (small and SIZE.small_control or SIZE.control)
	local over = hovered(id) and not o.disabled
	local down = ui.pressed == id and over
	local el = b.div():row():items_center():justify_center():gap(small and 5 or 6):h(height):rounded(6):no_shrink()
	if label == nil then
		el:w(height)
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
			el:bg(down and alpha("accent", 0.75) or (over and alpha("accent", 0.88) or "accent"))
		elseif variant == "danger" then
			ink = "background"
			el:bg(down and alpha("error", 0.75) or (over and alpha("error", 0.88) or "error"))
		elseif variant == "danger-ghost" then
			ink = "error"
			el:bg(over and alpha("error", down and 0.2 or 0.12) or nil)
		elseif variant == "ghost" then
			ink = over and "foreground" or "dim"
			el:bg(over and alpha("foreground", down and 0.1 or 0.06) or nil)
		else
			el:bg(over and (down and "raised4" or "raised3") or "raised2"):border(1, alpha("border", 0.6))
		end
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
function P.icon_button(id, name, o)
	o = o or {}
	return P.button(id, nil, {
		variant = "ghost",
		size = "sm",
		icon = name,
		icon_size = o.icon_size or 12,
		disabled = o.disabled,
		selected = o.selected,
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
		:child(T(tostring(n), "#ffffff", SIZE.tiny, 650))
end

-- A ring, or a disc, of a colour.
local function ring(role, size)
	return b.div():size(size, size):rounded(size / 2):border(1.5, role):no_shrink()
end

-- The mark of what a container is doing: a disc in a halo where it runs (red where it is unhealthy,
-- amber while it starts), half a disc where it is paused, a ring where it is not (red where it
-- failed), a ring in the colour of the news where it is waiting for something it was asked.
function P.dot(c)
	local box = b.div():row():items_center():justify_center():size(16, 16):no_shrink()
	local _, role = state_of(c)
	if S.busy[c.id] or c.state == "restarting" then
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
		local over = hovered(id)
		row:child(
			b.div()
				:press(id)
				:col()
				:justify_end()
				:px(10)
				:h(34)
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

-- A screen with nothing on it: a mark, what it is, and what to do.
function P.nothing(title, hint, mark)
	local col = b.div():col():items_center():gap(6):pt(54):px(20):no_shrink()
	if mark then
		col:child(
			b.div()
				:size(40, 40)
				:rounded(20)
				:bg("raised1")
				:row()
				:items_center()
				:justify_center()
				:mb(4)
				:child(icon(mark, 20, "quiet"))
		)
	end
	col:child(T(title, "dim", SIZE.body + 1))
	if hint then
		col:child(T(hint, "quiet", SIZE.small):align("center"))
	end
	return col
end

-- A card: a surface a step above the page.
function P.card()
	return b.div():col():gap(2):px(12):py(10):rounded(12):bg("raised1"):border(1, alpha("border", 0.6))
end

-- The field of the host, or what it says where it is not here. The host's text field has one
-- place at a time on the page, the room of the element that says it is one.
function P.field(active, hint, width)
	local focused = active and S.typing
	local box = b.div()
		:row()
		:items_center()
		:gap(7)
		:h(SIZE.control)
		:pl(8)
		:pr(5)
		:rounded(6)
		:bg(focused and "background" or "raised1")
		:border(1, focused and "accent" or alpha("border", 0.6))
		:press("field")
	if width then
		box:w(width):min_w(120)
	else
		box:grow(1):min_w(120)
	end
	box:child(icon("search", 14, "quiet"))
	if active then
		box:child(b.div():id("field.room"):text_field():grow(1):min_w(0):h(18))
	else
		box:child(b.div():grow(1):min_w(0):child(T(hint, "quiet", SIZE.body):truncate()))
	end
	return box:child(P.kbd("/"))
end

-- The mark of a row that can be chosen with space: filled when it is.
function P.check(on)
	local box = b.div():size(16, 16):rounded(4):no_shrink()
	if on then
		return box:bg("accent"):row():items_center():justify_center():child(icon("check", 12, "background"))
	end
	return box:border(1.2, alpha("foreground", 0.3))
end

-- A segmented control: `options` are `{ id =, label =, count =, tone = }`, `current` the id that is
-- on, and each one is named `prefix .. id` for a click.
function P.segmented(prefix, options, current)
	local control =
		b.div():row():items_center():gap(1):p(2):rounded(8):bg("raised1"):border(1, alpha("border", 0.6)):no_shrink()
	for _, option in ipairs(options) do
		local id = prefix .. option.id
		local active = option.id == current
		local seg = b.div():row():items_center():gap(6):h(24):px(9):rounded(6):press(id):no_shrink()
		if active then
			seg:bg("raised3"):border(1, alpha("border", 0.8))
		elseif hovered(id) then
			seg:bg(alpha("foreground", 0.05))
		end
		seg:child(T(option.label, (active or hovered(id)) and "foreground" or "dim", SIZE.body))
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
	local over = hovered(id)
	local track = b.div():w(26):h(14):rounded(7):no_shrink():row():items_center():px(2)
	track:bg(on and "accent" or alpha("foreground", over and 0.22 or 0.16))
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
		:child(T(label, over and "foreground" or "dim", SIZE.body))
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

-- Words in several lines, as a column of texts (see `P.wrap`).
function P.paragraph(text, width, role, size, weight, most)
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
	LINE_MOST = LINE_MOST,
	P = P,
	T = T,
	chosen = chosen,
	hovered = hovered,
}
