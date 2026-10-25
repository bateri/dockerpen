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
local L, log_live, log_top, log_tops, log_total =
	model_log.L, model_log.log_live, model_log.log_top, model_log.log_tops, model_log.log_total
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

-- The width of a character of the log, as a share of its size (the font of a terminal is one width
-- all through, a little under this), and the size of its text.
local CHAR = 0.62
local LOG_TEXT = SIZE.small + 1

-- The runs of a line cut into rows of `cols` characters.
local function wrap_runs(runs, cols)
	local rows, row, used = {}, {}, 0
	for _, run in ipairs(runs) do
		local text = run.text
		local length = utf8.len(text) or #text
		local from = 1
		while length > 0 do
			local take = math.min(length, cols - used)
			local cut = utf8.offset(text, take + 1) or (#text + 1)
			row[#row + 1] = { text = string.sub(text, from, cut - 1), fg = run.fg, bold = run.bold, dim = run.dim }
			from, length, used = cut, length - take, used + take
			if used >= cols and length > 0 then
				rows[#rows + 1], row, used = row, {}, 0
			end
		end
	end
	rows[#rows + 1] = row
	return rows
end

-- One row of the words of a line: the runs of it, each in its colour.
local function words_of(runs)
	local words = b.div():row():items_center():no_shrink()
	for _, run in ipairs(runs) do
		local role = run.fg
		if run.dim then
			role = "dim"
		end
		words:child(T(run.text, role, LOG_TEXT, run.bold and 700 or nil):no_shrink())
	end
	return words
end

-- One line of the log, as the rows it takes: in the colours it was written in, in red-edged rows
-- where it came on the error stream, lit where the search found it.
local function log_line(index, current, cols)
	local err = string.byte(L.streams, index) == 101
	local matched = L.query_on and L.match_set and L.match_set[index]
	local shown = log_runs(index)
	local rows
	if L.hscroll > 0 and not L.wrap then
		shown = shift_runs(shown, L.hscroll)
	end
	if L.wrap and cols then
		rows = wrap_runs(shown, cols)
	else
		rows = { shown }
	end
	local line = b.div():col():no_shrink():h(#rows * SIZE.line)
	if current then
		line:bg(alpha("warning", 0.14))
	elseif matched then
		line:bg(alpha("warning", 0.07))
	elseif err then
		line:bg(alpha("error", 0.05))
	end
	for position, runs in ipairs(rows) do
		local row = b.div():row():items_center():gap(8):h(SIZE.line):pr(12):clip():no_shrink()
		row:child(
			b.div():w(2):h(SIZE.line):no_shrink():bg(err and alpha("error", 0.7) or (current and "warning" or nil))
		)
		if L.timestamps then
			row:child(
				b.div()
					:w(90)
					:no_shrink()
					:child(position == 1 and T(L.clocks[index] or "", "quiet", SIZE.small):no_shrink() or b.div())
			)
		end
		if position == 1 and L.hscroll > 0 and not L.wrap then
			row:child(T("‹", "quiet", SIZE.small + 0.5):no_shrink())
		end
		row:child(words_of(runs))
		line:child(row)
	end
	return line
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
		ui:set_scroll("log", math.max(log_top(matches[#matches]) - (views.log or 400) / 2, 0))
	end
	return L.scanned < L.count
end

-- The bar over a log: the search and what it found, then what the log shows and does: following,
-- the time of each line, wrapping; clearing the view, copying it, following it in the terminal.
local function log_toolbar(width)
	local narrow = width < 620
	local top = b.div():row():items_center():gap(6):h(SIZE.bar + 4):px(12):pt(4):no_shrink()
	top:child(P.field(S.field == "logs", "Find in logs", nil))
	if L.query_on and S.query ~= "" then
		local total = #L.matches
		local note = total == 0 and (L.scanned < L.count and "…" or "0")
			or (string.format("%d/%d", math.max(L.match_at, 1), total) .. (L.scanned < L.count and "+" or ""))
		top:child(T(note, total == 0 and "quiet" or "dim", SIZE.small):no_shrink())
		top:child(P.switch("l:only", "only", L.only))
	end
	top:child(P.switch("l:follow", "follow", L.follow))
	top:child(P.switch("l:time", "time", L.timestamps))
	top:child(P.switch("l:wrap", "wrap", L.wrap))
	if not narrow then
		top:child(P.icon_button("l:clear", "eraser", { icon_size = 13 }))
		top:child(P.icon_button("l:copy", "copy", { icon_size = 13 }))
		top:child(P.icon_button("d:follow", "arrow-right-left", { icon_size = 13 }))
	end
	return top
end

local function log_tab(c, width)
	local box = b.div():col():grow(1):min_h(0)
	box:child(log_toolbar(width))
	if L.id ~= c.id then
		return box:child(P.nothing("Opening the log…"))
	end
	if L.count == 0 then
		local words = L.ended and (L.ended.message ~= "" and L.ended.message or "The log has ended.")
			or "It has written nothing yet."
		return box:child(P.nothing(words, L.ended == nil and "Lines show here as the container writes them." or nil))
	end
	-- The characters a row has room for: the width of the panel less the edge, the time, the margin.
	local cols = math.max(math.floor((width - 2 - 8 - 12 - (L.timestamps and 98 or 0)) / (LOG_TEXT * CHAR)), 10)
	L.cols = cols
	local searching = L.only and L.query_on and S.query ~= ""
	local tops = nil
	local count = L.count
	if searching then
		count = #L.matches
	else
		tops = log_tops(cols)
	end
	local view = views.log or 400
	if L.follow and not searching then
		ui:set_scroll("log", math.max(log_total() + 4 - view, 0))
	end
	local current = L.matches[L.match_at]
	if searching then
		box:child(virtual("log", count, SIZE.line, function(index)
			return log_line(L.matches[index], L.matches[index] == current, cols)
		end, { px = 0, pt = 4 }))
	else
		box:child(virtual("log", count, SIZE.line, function(index)
			return log_line(index, index == current, cols)
		end, { px = 0, pt = 4, tops = tops }))
	end
	if not L.follow and L.new_since > 0 then
		box:child(
			b.div():row():items_center():justify_center():h(26):no_shrink():child(
				b.div()
					:row()
					:items_center()
					:gap(6)
					:h(22)
					:px(10)
					:rounded(11)
					:bg("accent")
					:press("l:follow")
					:child(P.icon("arrow-down", 12, "background"))
					:child(T(fmt.count(L.new_since, "new line"), "background", SIZE.small, 600))
			)
		)
	elseif L.ended and not log_live() then
		box:child(
			b.div():row():items_center():h(22):px(14):no_shrink():child(
				T(
					c.state == "running" and "The log stopped here." or "It is not running: the log does not go on.",
					"dim",
					SIZE.small
				)
			)
		)
	end
	return box
end

return {
	log_tab = log_tab,
	scan_log = scan_log,
}
