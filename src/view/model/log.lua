local lib_ansi = require("../lib/ansi")
local lib_kit = require("../lib/kit")
local lib_sizes = require("../lib/sizes")
local lib_virtual = require("../lib/virtual")
local model_state = require("./state")
local ansi = lib_ansi.ansi
local LOG_MOST, SIZE = lib_sizes.LOG_MOST, lib_sizes.SIZE
local views = lib_virtual.views
local S = model_state.S

-- ---- a container's log -----------------------------------------------------------------------------

local L = S.log

local function log_clear(id, tail)
	L.id, L.tail = id, tail or L.tail
	L.texts, L.streams, L.clocks = {}, "", {}
	L.count, L.last, L.ended = 0, nil, nil
	L.matches, L.scanned, L.match_at = {}, 0, 0
	L.runs, L.run_count = {}, 0
	L.tops = nil
	L.new_since = 0
	L.hscroll = 0
	L.follow = true
end

-- Keeps what a log is allowed to hold: when it is more than the page keeps, the oldest fifth goes.
local function log_trim()
	if L.count <= LOG_MOST + LOG_MOST // 5 then
		return
	end
	local drop = L.count - LOG_MOST
	table.move(L.texts, drop + 1, L.count, 1)
	table.move(L.clocks, drop + 1, L.count, 1)
	for index = L.count - drop + 1, L.count do
		L.texts[index], L.clocks[index] = nil, nil
	end
	L.streams = string.sub(L.streams, drop + 1)
	L.count -= drop
	L.matches, L.scanned, L.match_at = {}, 0, 0
	L.runs, L.run_count = {}, 0
	L.tops = nil
end

local function on_log(value)
	if value.ended then
		L.ended = value.ended
		return
	end
	local texts = value.texts
	if texts and #texts > 0 then
		table.move(texts, 1, #texts, L.count + 1, L.texts)
		table.move(value.clocks, 1, #value.clocks, L.count + 1, L.clocks)
		L.streams ..= value.streams
		L.count += #texts
		if not L.follow then
			L.new_since += #texts
		end
		log_trim()
	end
	L.last = value.last or L.last
end

-- The lines on show are gone from the view; the ones that come are shown, and the log goes on.
local function log_wipe()
	local id, tail, last, wrap, timestamps, only = L.id, L.tail, L.last, L.wrap, L.timestamps, L.only
	log_clear(id, tail)
	L.last, L.wrap, L.timestamps, L.only = last, wrap, timestamps, only
end

-- How many rows of `cols` characters a line takes where it wraps: the characters it is shown in
-- (`ansi.runs`: a tab is four spaces, an escape none), or the rows it is made of and the room the
-- list keeps for it are not the same.
local function line_rows(text, cols)
	local tabs = string.find(text, "\t", 1, true)
	if #text <= cols and not tabs then
		return 1
	end
	local plain = ansi.strip(text)
	if tabs then
		plain = string.gsub(plain, "\t", "    ")
	end
	local length = utf8.len(plain) or #plain
	return math.max(1, math.ceil(length / cols))
end

-- Lines wrap at the width of the log, or run on past it to be read to the right: what was made for
-- the one is made again, and the lines are read from their start.
local function log_toggle_wrap()
	L.wrap = not L.wrap
	L.tops = nil
	L.runs, L.run_count = {}, 0
	L.hscroll = 0
end

-- Where each line starts, in points, when they wrap at `cols` characters (and are `SIZE.line` a row):
-- kept as the lines come, and made again where the width changes. `nil` where they do not wrap.
local function log_tops(cols)
	if not L.wrap then
		L.tops = nil
		return nil
	end
	if L.tops == nil or L.tops_cols ~= cols then
		L.tops, L.tops_cols, L.tops_n = { 0 }, cols, 0
	end
	local tops, line = L.tops, SIZE.line
	for index = L.tops_n + 1, L.count do
		tops[index + 1] = tops[index] + line_rows(L.texts[index], cols) * line
	end
	L.tops_n = L.count
	return tops
end

-- Where line `index` starts, and how tall all of them are.
local function log_top(index)
	if L.tops and L.wrap then
		return L.tops[index] or (L.tops[#L.tops] + (index - #L.tops) * SIZE.line)
	end
	return (index - 1) * SIZE.line
end

local function log_total()
	if L.tops and L.wrap then
		return L.tops[L.count + 1] or (L.tops[#L.tops] + (L.count + 1 - #L.tops) * SIZE.line)
	end
	return L.count * SIZE.line
end

-- The room above the first line of the log, in its list.
local LOG_LEAD = 4

-- Whether the log shows only the lines its search found (they are then the rows of its list).
local function log_searching()
	return L.only and L.query_on and S.query ~= ""
end

-- Where each line the search found starts in the list of them alone, when the lines wrap at `cols`
-- characters: each as tall as it is in the whole log. Kept as the matches come, and made again for
-- another search or width. `nil` where they do not wrap (they are then a row each).
local function log_match_tops(cols)
	local whole = log_tops(cols)
	if whole == nil then
		return nil
	end
	if L.mtops == nil or L.mtops_of ~= L.matches or L.mtops_cols ~= cols then
		L.mtops, L.mtops_of, L.mtops_cols, L.mtops_n = { 0 }, L.matches, cols, 0
	end
	local tops, matches = L.mtops, L.matches
	for at = L.mtops_n + 1, #matches do
		local index = matches[at]
		tops[at + 1] = tops[at] + (whole[index + 1] - whole[index])
	end
	L.mtops_n = #matches
	return tops
end

-- Shows match `at` (of `L.matches`) in the middle of the log, where it is in the list on show.
local function log_show_match(at)
	local index = L.matches[at]
	if index == nil then
		return
	end
	local top, tall
	if log_searching() then
		local tops = L.cols and log_match_tops(L.cols)
		top = tops and tops[at] or (at - 1) * SIZE.line
		tall = tops and tops[at + 1] - tops[at] or SIZE.line
	else
		top = log_top(index)
		tall = log_top(index + 1) - top
	end
	L.match_at, L.follow = at, false
	local view = views.log or 400
	lib_kit.scroll_to("log", math.max(LOG_LEAD + top + tall / 2 - view / 2, 0))
end

-- Goes `step` matches on (1) or back (-1), round from the last to the first: the person goes through
-- them, and the latest no longer takes the search's place. Whether there was one to go to.
local function log_step_match(step)
	local total = #L.matches
	if total == 0 then
		return false
	end
	local at = L.match_at
	if at < 1 then
		at = step > 0 and 1 or total
	else
		at = (at - 1 + step) % total + 1
	end
	L.pinned_match = true
	log_show_match(at)
	return true
end

-- Whether the container of the log on show is running (a log of one that stopped does not go on).
local function log_live()
	local c = L.id and S.by_id[L.id]
	return c ~= nil and c.state == "running"
end

return {
	L = L,
	LOG_LEAD = LOG_LEAD,
	line_rows = line_rows,
	log_clear = log_clear,
	log_match_tops = log_match_tops,
	log_searching = log_searching,
	log_show_match = log_show_match,
	log_step_match = log_step_match,
	log_toggle_wrap = log_toggle_wrap,
	log_top = log_top,
	log_tops = log_tops,
	log_total = log_total,
	log_wipe = log_wipe,
	log_live = log_live,
	on_log = on_log,
}
