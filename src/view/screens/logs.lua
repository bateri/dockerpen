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
local LOG_BAR_ONE_LINE, LOG_MOST, SIZE = lib_sizes.LOG_BAR_ONE_LINE, lib_sizes.LOG_MOST, lib_sizes.SIZE
local views, virtual = lib_virtual.views, lib_virtual.virtual
local L, LOG_LEAD, log_live, log_match_tops, log_searching, log_show_match, log_tops, log_total =
	model_log.L,
	model_log.LOG_LEAD,
	model_log.log_live,
	model_log.log_match_tops,
	model_log.log_searching,
	model_log.log_show_match,
	model_log.log_tops,
	model_log.log_total
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
-- The room of the time of a line: "12:34:56.789", twelve characters of the log's size.
local TIME_W = math.ceil(12 * LOG_TEXT * CHAR) + 2

-- The wheel across a log, `dx` points: its lines are read that much further to the right (or back
-- to their start), while they run on past its width; where they wrap there is nothing to the right.
-- Whether what is on show moved.
local function shift_log(dx)
	if L.wrap then
		return false
	end
	local was = math.floor(L.hscroll)
	L.hscroll = math.max(L.hscroll + dx / (LOG_TEXT * CHAR), 0)
	return math.floor(L.hscroll) ~= was
end

-- The runs of a line cut into rows of `cols` characters.
local function wrap_runs(runs, cols)
	local rows, row, used = {}, {}, 0
	for _, run in ipairs(runs) do
		local text = run.text
		local length = utf8.len(text) or #text
		local from = 1
		while length > 0 do
			local take = math.min(length, cols - used)
			-- The character `take` on from where this row's part starts, not from the start of the run.
			local cut = utf8.offset(text, take + 1, from) or (#text + 1)
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
	local shift = L.wrap and 0 or math.floor(L.hscroll)
	if shift > 0 then
		shown = shift_runs(shown, shift)
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
		-- The edge, then the words 10 in from it, and 10 between the time and them.
		local row = b.div():row():items_center():gap(10):h(SIZE.line):pr(12):clip():no_shrink()
		row:child(
			b.div():w(2):h(SIZE.line):no_shrink():bg(err and alpha("error", 0.7) or (current and "warning" or nil))
		)
		if L.timestamps then
			row:child(
				b.div()
					:w(TIME_W)
					:no_shrink()
					:child(position == 1 and T(L.clocks[index] or "", "quiet", LOG_TEXT):no_shrink() or b.div())
			)
		end
		if position == 1 and shift > 0 then
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
		log_show_match(#matches)
	end
	return L.scanned < L.count
end

-- A switch with its word, as the first dockerpen's: a 24 track, the word in the second colour, and
-- the ground of a hover under both.
local function switch(id, label, on)
	local over = ui.hover == id
	local track = b.div():w(24):h(14):rounded(7):no_shrink():row():items_center():px(2)
	if on then
		track:bg("accent"):justify_end()
	else
		track:bg("raised2"):border(1, "border")
	end
	track:child(b.div():size(10, 10):rounded(5):bg(on and "background" or "dim"))
	return b.div()
		:row()
		:items_center()
		:gap(7)
		:h(26)
		:px(6)
		:rounded(6)
		:bg(over and alpha("foreground", 0.06) or nil)
		:press(id)
		:no_shrink()
		:child(track)
		:child(T(label, over and "foreground" or "dim", SIZE.body))
end

-- The way through what the search found: which of them is on show and how many there are (a `+`
-- while the log is still being looked through), the one before it and the one after (round from the
-- last to the first), and whether the log shows only them.
local function find_controls()
	local total = #L.matches
	local more = L.scanned < L.count
	local note
	if total == 0 then
		note = more and "…" or "No match"
	else
		note = string.format("%d/%d", math.max(L.match_at, 1), total) .. (more and "+" or "")
	end
	local none = total == 0
	-- The count is as wide as a long one, so the arrows do not move as it grows.
	local count =
		b.div():row():justify_end():min_w(58):pr(4):no_shrink():child(T(note, none and "quiet" or "dim", SIZE.small))
	return b.div()
		:row()
		:items_center()
		:gap(2)
		:no_shrink()
		:child(count)
		:child(P.icon_button("l:prev", "arrow-up", {
			label = "Previous match",
			tip = "Previous match",
			keys = "N",
			disabled = none,
		}))
		:child(P.icon_button("l:next", "arrow-down", {
			label = "Next match",
			tip = "Next match",
			keys = "n",
			disabled = none,
		}))
		:child(P.icon_button("l:only", "list-filter", {
			label = "Only the lines that match",
			tip = "Only the lines that match",
			selected = L.only,
		}))
end

-- A thin upright line between the parts of a bar.
local function divider()
	return b.div():w(1):h(16):ml(4):mr(4):bg(alpha("border", 0.7)):no_shrink()
end

-- The bar over a log: the search and the way through what it found; then what the log shows
-- (following, the time of each line, wrapping) and what is done with it (cleared, copied, followed in
-- the terminal). All on one line where the log is wide enough for all of it, the search with what it
-- found included, else the switches and the verbs on a second line: whether there is a search does
-- not move the log down a line as the person starts to type.
local function log_toolbar(width)
	local one_line = width >= LOG_BAR_ONE_LINE
	local bar = b.div():col():no_shrink()
	local top = b.div():row():items_center():gap(4):h(44):px(10):no_shrink()
	top:child(P.field(S.field == "logs", "Find in logs", nil, 140))
	if L.query_on and S.query ~= "" then
		top:child(find_controls())
	end
	bar:child(top)
	local rest = top
	if one_line then
		top:child(divider())
	else
		-- At the narrowest the end of it is cut, not run off the side of the page.
		rest = b.div():row():items_center():gap(4):h(30):px(10):mb(6):no_shrink():clip()
		bar:child(rest)
	end
	rest:child(switch("l:follow", "follow", L.follow))
	rest:child(switch("l:time", "time", L.timestamps))
	rest:child(switch("l:wrap", "wrap", L.wrap))
	if one_line then
		rest:child(divider())
	else
		rest:child(b.spacer())
	end
	rest:child(P.icon_button("l:clear", "eraser", { icon_size = 13 }))
	rest:child(P.icon_button("l:copy", "copy", { icon_size = 13 }))
	rest:child(P.icon_button("d:follow", "arrow-right-left", { icon_size = 13 }))
	bar:child(b.div():h(1):bg(alpha("border", 0.6)):no_shrink())
	return bar
end

local function log_tab(c, width)
	local box = b.div():col():grow(1):min_h(0)
	box:child(log_toolbar(width))
	if L.id ~= c.id then
		return box:child(P.nothing("Opening the log…", nil, nil, width))
	end
	if L.count == 0 then
		local words = (L.ended and L.ended.message ~= "") and L.ended.message or "Nothing written yet"
		local hint = c.state == "running" and "Lines appear here as the container writes them."
			or "The container wrote nothing before it stopped."
		return box:child(P.nothing(words, hint, "square-terminal", width))
	end
	-- The characters a row has room for: the width of the panel less the edge, the time, the margin.
	local cols =
		math.max(math.floor((width - 2 - 10 - 12 - (L.timestamps and (TIME_W + 10) or 0)) / (LOG_TEXT * CHAR)), 10)
	L.cols = cols
	local view = views.log or 400
	local current = L.matches[L.match_at]
	if log_searching() then
		-- The lines it found alone, each as tall as it is wrapped.
		box:child(virtual("log", #L.matches, SIZE.line, function(index)
			return log_line(L.matches[index], L.matches[index] == current, cols)
		end, { px = 0, pt = LOG_LEAD, tops = log_match_tops(cols), trail = 10 }))
	else
		box:child(virtual("log", L.count, SIZE.line, function(index)
			return log_line(index, index == current, cols)
		end, { px = 0, pt = LOG_LEAD, tops = log_tops(cols), trail = 10, at_end = L.follow }))
	end
	-- Back to the end: a pill over the foot of the log, while it is not followed and there is more
	-- of it than the window shows.
	if not L.follow and log_total() > view then
		box:child(
			b.div():absolute():inset(nil, 0, 14, 0):row():justify_center():child(
				b.div()
					:row()
					:items_center()
					:gap(6)
					:h(28)
					:px(12)
					:rounded(14)
					:bg("accent")
					:shadow(0, 6, 16, alpha("background", 0.6))
					:press("l:follow")
					:child(P.icon("arrow-down", 13, "background"))
					:child(
						T(
							L.new_since > 0 and fmt.count(L.new_since, "new line") or "Follow",
							"background",
							SIZE.body,
							600
						)
					)
			)
		)
	end
	if L.ended and not log_live() then
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
	shift_log = shift_log,
}
