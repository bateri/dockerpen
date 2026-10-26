-- The rail of sections, and what the engine is doing at the bottom of it. Where there is little room
-- it is its icons alone, and where there is less it is a strip across the top.

local lib_fmt = require("../lib/fmt")
local lib_icons = require("../lib/icons")
local lib_kit = require("../lib/kit")
local lib_sizes = require("../lib/sizes")
local model_containers = require("../model/containers")
local model_rows = require("../model/rows")
local model_state = require("../model/state")
local parts_ui = require("./ui")
local alpha, b, ui = lib_kit.alpha, lib_kit.b, lib_kit.ui
local fmt = lib_fmt.fmt
local icon = lib_icons.icon
local SECTIONS, SIZE = lib_sizes.SECTIONS, lib_sizes.SIZE
local counts = model_rows.counts
local S = model_state.S
local P, T, blend, glow, hovered = parts_ui.P, parts_ui.T, parts_ui.blend, parts_ui.glow, parts_ui.hovered

local rail = {}

-- A section's row is this tall, the rows this far apart, the first this far down.
local ITEM, GAP, TOP = 30, 2, 10

-- The pill under the section on show: where it set out from and where it is going, as indexes of
-- `SECTIONS`, and how far it has come (the fade named PILL). Moved from one section to another, it
-- slides, as the web page's did.
local PILL = "rail.pill"
local pill = { from = nil, to = nil }

-- Where the pill is now: an index, part way from one to the next while it moves.
local function pill_at()
	local level = ui.fades:level(PILL)
	-- Fast at first and settling, as a spring with little bounce.
	local eased = 1 - (1 - level) ^ 3
	return pill.from + (pill.to - pill.from) * eased
end

-- The pill for the section at `index` of `SECTIONS`: a step on its way there, from where it is.
local function pill_to(index)
	if pill.to == nil then
		pill.from, pill.to = index, index
		ui.fades:snap(PILL, 1)
	elseif pill.to ~= index then
		pill.from, pill.to = pill_at(), index
		ui.fades:snap(PILL, 0)
	end
	if S.reduce_motion then
		ui.fades:snap(PILL, 1)
	else
		ui.fades:to(PILL, 1)
	end
	return b.div()
		:id(PILL)
		:absolute()
		:inset(TOP + (pill_at() - 1) * (ITEM + GAP), 8, nil, 8)
		:h(ITEM)
		:rounded(6)
		:bg(alpha("accent", 0.13))
		:border(1, alpha("accent", 0.24))
end

-- What the engine reported since the page came that is worth a look: a container died, was killed,
-- ran out of memory, or went unhealthy.
local function fresh_news()
	local n = 0
	for _, item in ipairs(S.activity) do
		local action = item.action or ""
		if
			(item.seq or 0) > S.live_from
			and (
				string.find(action, "die")
				or string.find(action, "oom")
				or string.find(action, "unhealthy")
				or string.find(action, "kill")
			)
		then
			n += 1
		end
	end
	return n
end

-- What stands at the end of a section's row: the containers with something to look at, news in the
-- activity, a job running, how many there are, or the key that goes to it.
local function trailing(section, keys, active)
	local count_role = active and "dim" or "quiet"
	if section.id == "containers" then
		local issues = counts().issues
		if issues > 0 then
			return P.badge(issues)
		end
		return T(tostring(#S.containers), count_role, SIZE.small)
	elseif section.id == "activity" then
		local news = fresh_news()
		if news > 0 then
			return P.badge(news)
		end
	elseif section.id == "system" then
		for _, job in ipairs(S.jobs) do
			if job.state == "running" then
				return P.disc("accent", 10, false)
			end
		end
	elseif S.lists[section.id] then
		return T(tostring(#S.lists[section.id]), count_role, SIZE.small)
	end
	-- The key is always there, seen as far as the pointer over the rail brings it in.
	return T(section.key, alpha("quiet", keys), SIZE.tiny + 0.5)
end

-- A section's row: its ground is the pointer's (the one that is on show has the pill, which
-- `rail.column` moves under it).
local function item(section, compact, keys)
	local id = "sec:" .. section.id
	local active = S.section == section.id
	local el = b.div():press(id):row():items_center():gap(10):h(ITEM):rounded(6):no_shrink()
	if compact then
		el:justify_center()
	else
		el:px(8)
	end
	local level = glow(id, hovered(id) and not active)
	if level > 0 then
		el:bg(alpha("foreground", 0.06 * level))
	end
	local ink = active and "foreground" or blend("dim", "foreground", level)
	el:child(icon(section.icon, 15, ink))
	local end_of = trailing(section, keys, active)
	if compact then
		if end_of and (section.id == "containers" or section.id == "activity") then
			-- A dot at the corner says there is news.
			local news = (section.id == "containers" and counts().issues > 0)
				or (section.id == "activity" and fresh_news() > 0)
			if news then
				el:child(b.div():absolute():inset(3, 5, nil, nil):size(8, 8):rounded(4):bg("error"))
			end
		end
		return el
	end
	el:child(b.div():grow(1):min_w(0):child(P.line(section.label, ink, SIZE.body)))
	if end_of then
		el:child(end_of)
	end
	return el
end

-- A line of numbers and a name: `cpu` or `mem`, a line of the last readings, what it is now.
local function meter(label, values, role, ceiling, now)
	local row = b.div():row():items_center():gap(6):h(14)
	row:child(b.div():w(26):no_shrink():child(T(label, "quiet", SIZE.tiny + 0.5)))
	row:child(b.div():grow(1):min_w(0):h(14):child(P.spark(values, role, ceiling)))
	row:child(T(now, "dim", SIZE.tiny + 0.5, 500):no_shrink())
	return row
end

-- The engine at a glance: its name, what all the containers take of the processor and the memory,
-- how many run on how much.
local function engine_card()
	local engine = S.engine
	if engine == nil or S.failure then
		return nil
	end
	local cpu, mem = {}, {}
	for _, total in ipairs(S.totals) do
		cpu[#cpu + 1] = total.cpu
		mem[#mem + 1] = total.memory
	end
	local latest = S.totals[#S.totals]
	local running = 0
	for _, c in ipairs(S.containers) do
		if c.state == "running" then
			running += 1
		end
	end
	local card =
		b.div():col():gap(6):p(8):rounded(8):bg(alpha("background", 0.55)):border(1, alpha("border", 0.6)):no_shrink()
	card:child(
		b.div():row():items_center():gap(7):child(P.halo("success", 7)):child(P.line(engine.name, "dim", SIZE.small))
	)
	card:child(meter("cpu", cpu, "accent", nil, fmt.percent(latest and latest.cpu or 0, 0)))
	card:child(
		meter(
			"mem",
			mem,
			"success",
			engine.memory and engine.memory > 0 and engine.memory or nil,
			fmt.memory_tight(latest and latest.memory or 0)
		)
	)
	-- In the card's room (the rail, less its sides and the card's), on as many lines as it takes, as
	-- the first dockerpen's line wrapped: a line of the kit is one line, and would run past the card.
	card:child(
		P.paragraph(
			running .. " running · " .. engine.cpus .. " cpu · " .. fmt.memory_tight(engine.memory),
			SIZE.rail - 2 * 8 - 2 * 8 - 2,
			"quiet",
			SIZE.tiny + 0.5
		)
	)
	return card
end

-- The rail, as wide as `width` allows: its icons alone where that is the compact width.
-- Whether the pointer is over the rail, anywhere on it (between its rows too), as the page last laid it
-- out: the keys of the sections show then.
function rail.pointer_over()
	local at, box = S.pointer, b.layout.bounds("rail")
	return at ~= nil
		and box ~= nil
		and at.x >= box.x
		and at.x < box.x + box.w
		and at.y >= box.y
		and at.y < box.y + box.h
end

function rail.column(compact)
	-- The keys come in while the pointer is anywhere over the rail and go when it leaves, as the web
	-- page's did; only the sections with no count or news of their own show one.
	local keys = glow("rail.keys", rail.pointer_over())
	local width = compact and SIZE.rail_compact or SIZE.rail
	local col = b.div():id("rail"):col():w(width):no_shrink():gap(GAP):px(8):pt(TOP):pb(8):bg("raised1")
	local shown = nil
	for index, section in ipairs(SECTIONS) do
		if section.id == S.section then
			shown = index
		end
	end
	-- First, so that the rows are drawn over it.
	if shown then
		col:child(pill_to(shown))
	end
	for _, section in ipairs(SECTIONS) do
		col:child(item(section, compact, keys))
	end
	col:child(b.spacer())
	if not compact then
		local card = engine_card()
		if card then
			col:child(card)
		end
	end
	return b.div():row():h_full():no_shrink():child(col):child(b.div():w(1):bg(alpha("border", 0.6)):no_shrink())
end

-- The sections as a strip, where there is no room for the rail.
function rail.strip()
	local strip = b.div():row():items_center():gap(2):h(34):px(10):no_shrink():bg("raised1")
	for _, section in ipairs(SECTIONS) do
		local id = "sec:" .. section.id
		local active = S.section == section.id
		local el = b.div():press(id):row():items_center():gap(6):h(26):px(8):rounded(6)
		local level = glow(id, hovered(id) and not active)
		if active then
			el:bg(alpha("accent", 0.13)):border(1, alpha("accent", 0.24))
		elseif level > 0 then
			el:bg(alpha("foreground", 0.06 * level))
		end
		el:child(icon(section.icon, 14, active and "foreground" or "dim"))
		if S.width >= 380 then
			el:child(T(section.label, active and "foreground" or "dim", SIZE.small + 1))
		end
		strip:child(el)
	end
	return strip
end

return rail
