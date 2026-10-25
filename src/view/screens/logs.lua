local lib_kit = require("../lib/kit")
local lib_ansi = require("../lib/ansi")
local lib_fmt = require("../lib/fmt")
local lib_sizes = require("../lib/sizes")
local lib_virtual = require("../lib/virtual")
local model_log = require("../model/log")
local model_state = require("../model/state")
local parts_ui = require("../parts/ui")
local alpha, b, ui = lib_kit.alpha, lib_kit.b, lib_kit.ui
local ansi = lib_ansi.ansi
local fmt = lib_fmt.fmt
local LOG_MOST, SIZE = lib_sizes.LOG_MOST, lib_sizes.SIZE
local views, virtual = lib_virtual.views, lib_virtual.virtual
local L, log_live = model_log.L, model_log.log_live
local S = model_state.S
local P, T = parts_ui.P, parts_ui.T

-- ---- a container's log -----------------------------------------------------------------------------

-- The runs of line `index` as colours, kept while the line is near the window.
local function log_runs(index)
	local cached = L.runs[index]
	if cached then
		return cached
	end
	if L.run_count > 800 then
		L.runs, L.run_count = {}, 0
	end
	local text = L.texts[index]
	local runs = ansi.runs(text)
	if #runs == 1 and runs[1].fg == nil then
		local level = ansi.level(text)
		if level then
			runs[1].fg = level
		end
	end
	L.runs[index] = runs
	L.run_count += 1
	return runs
end

-- The runs of a line without its first `n` characters: a log read further to the right.
local function shift_runs(runs, n)
	local out = {}
	for _, run in ipairs(runs) do
		local length = utf8.len(run.text) or #run.text
		if n >= length then
			n -= length
		else
			local text = run.text
			if n > 0 then
				text = string.sub(text, utf8.offset(text, n + 1) or (n + 1))
			end
			n = 0
			out[#out + 1] = { text = text, fg = run.fg, bold = run.bold, dim = run.dim, underline = run.underline }
		end
	end
	return out
end

-- One line of the log as a row of the runs it is in.
local function log_line(index, current)
	local err = string.byte(L.streams, index) == 101
	local matched = L.query_on and L.match_set and L.match_set[index]
	local row = b.div():row():items_center():gap(8):h(SIZE.line):px(14):clip():no_shrink()
	if current then
		row:bg(alpha("warning", 0.28))
	elseif matched then
		row:bg(alpha("warning", 0.13))
	end
	row:child(b.div():w(3):h(SIZE.line - 5):rounded(1.5):no_shrink():bg(err and "error" or nil))
	if L.timestamps then
		row:child(T(L.clocks[index] or "", "quiet", SIZE.small + 0.5):no_shrink())
	end
	local words = b.div():row():items_center():no_shrink()
	local shown = log_runs(index)
	if L.hscroll > 0 then
		shown = shift_runs(shown, L.hscroll)
		row:child(T("‹", "quiet", SIZE.small + 0.5):no_shrink())
	end
	for _, run in ipairs(shown) do
		local role = run.fg
		if run.dim then
			role = "dim"
		end
		words:child(T(run.text, role, SIZE.small + 0.5, run.bold and 700 or nil):no_shrink())
	end
	row:child(words)
	return row
end

-- Looks through the lines the query has not been tried on, so many at a time (a log can be
-- a hundred thousand lines, and a call of the page is held to a quarter of a second). True while
-- there is more to look through.
local function scan_log(budget)
	local query = L.query_on and S.query or ""
	if query ~= L.scanned_for then
		L.scanned_for, L.matches, L.scanned, L.match_at, L.match_set = query, {}, 0, 0, {}
		L.pinned_match = false
	end
	if query == "" then
		return false
	end
	local last = math.min(L.count, L.scanned + budget)
	local matches, set = L.matches, L.match_set
	for index = L.scanned + 1, last do
		if fmt.has(ansi.strip(L.texts[index]), query) then
			matches[#matches + 1] = index
			set[index] = true
		end
	end
	L.scanned = last
	-- Until the person goes through the matches, the one on show is the latest: what a log is
	-- searched for is most often what happened last.
	if not L.pinned_match and #matches > 0 and L.match_at ~= #matches then
		L.match_at = #matches
		L.follow = false
		ui:set_scroll("log", math.max((matches[#matches] - 1) * SIZE.line - (views.log or 400) / 2, 0))
	end
	return L.scanned < L.count
end

-- The bar over a log: follow, timestamps, the search and what it found. In a narrow place the
-- search has a row of its own.
local function log_toolbar(width)
	local narrow = width < 600
	local small = { h = 24, size = SIZE.small + 0.5 }
	local function button(id, label, key, extra)
		local options =
			{ h = small.h, size = small.size, selected = extra and extra.selected, key = (not narrow) and key or nil }
		return P.button(id, label, options)
	end
	local top = b.div():row():items_center():gap(8):h(narrow and 34 or 40):px(18):no_shrink()
	top:child(button("l:follow", L.follow and "Following" or "Follow", "End", { selected = L.follow }))
	top:child(button("l:time", "Timestamps", "t", { selected = L.timestamps }))
	local search = b.div():row():items_center():gap(8):w(0):grow(1):min_w(0)
	search:child(P.field(S.field == "logs", "Search the log", nil))
	if L.query_on and S.query ~= "" then
		local total = #L.matches
		local note = total == 0 and (L.scanned < L.count and "looking…" or "no match")
			or (string.format("%d of %d", math.max(L.match_at, 1), total) .. (L.scanned < L.count and "+" or ""))
		search:child(T(note, total == 0 and "dim" or "foreground", SIZE.small):no_shrink())
		search:child(P.button("l:prev", "Prev", { h = 22, px = 8, size = SIZE.small, disabled = total == 0 }))
		search:child(P.button("l:next", "Next", { h = 22, px = 8, size = SIZE.small, disabled = total == 0 }))
	end
	if narrow then
		top:child(b.spacer())
		if L.count >= L.tail and L.tail < LOG_MOST then
			top:child(P.button("l:more", "Load more", { h = 22, px = 8, size = SIZE.small }))
		end
		top:child(T(fmt.count(L.count, "line"), "quiet", SIZE.small):no_shrink())
		return b.div():col():no_shrink():child(top):child(b.div():row():items_center():h(34):px(18):child(search))
	end
	top:child(search)
	if L.count >= L.tail and L.tail < LOG_MOST then
		top:child(P.button("l:more", "Load more", { key = "L", h = 22, px = 8, size = SIZE.small }))
	end
	top:child(T(fmt.count(L.count, "line"), "quiet", SIZE.small):no_shrink())
	return top
end

local function log_tab(c, width)
	local box = b.div():col():grow(1):min_h(0)
	box:child(log_toolbar(width))
	box:child(b.div():h(1):bg(alpha("border", 0.6)):no_shrink())
	if L.id ~= c.id then
		return box:child(P.nothing("Opening the log…"))
	end
	if L.count == 0 then
		local words = L.ended and (L.ended.message ~= "" and L.ended.message or "The log has ended.")
			or "It has written nothing yet."
		return box:child(P.nothing(words, L.ended == nil and "Lines show here as the container writes them." or nil))
	end
	local view = views.log or 400
	if L.follow then
		ui:set_scroll("log", math.max(L.count * SIZE.line + 8 - view, 0))
	end
	local current = L.matches[L.match_at]
	box:child(virtual("log", L.count, SIZE.line, function(index)
		return log_line(index, index == current)
	end, { px = 0, pt = 4 }))
	local footer = nil
	if not L.follow and L.new_since > 0 then
		footer = T("↓ " .. fmt.count(L.new_since, "new line") .. " — End follows", "accent", SIZE.small)
	elseif L.ended and not log_live() then
		footer = T(
			c.state == "running" and "The log stopped here." or "It is not running: the log does not go on.",
			"dim",
			SIZE.small
		)
	end
	if footer then
		box:child(b.div():row():items_center():h(22):px(18):no_shrink():bg("raised1"):child(footer))
	end
	return box
end

return {
	log_tab = log_tab,
	scan_log = scan_log,
}
