local lib_sizes = require("../lib/sizes")
local model_state = require("./state")
local LOG_MOST, SIZE = lib_sizes.LOG_MOST, lib_sizes.SIZE
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

-- How many rows of `cols` characters a line takes where it wraps.
local function line_rows(text, cols)
	if #text <= cols then
		return 1
	end
	local plain = text
	if string.find(text, "\27", 1, true) then
		plain = string.gsub(text, "\27%[[%d;:]*%a", "")
	end
	local length = utf8.len(plain) or #plain
	return math.max(1, math.ceil(length / cols))
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

-- Whether the container of the log on show is running (a log of one that stopped does not go on).
local function log_live()
	local c = L.id and S.by_id[L.id]
	return c ~= nil and c.state == "running"
end

return {
	L = L,
	line_rows = line_rows,
	log_clear = log_clear,
	log_top = log_top,
	log_tops = log_tops,
	log_total = log_total,
	log_wipe = log_wipe,
	log_live = log_live,
	on_log = on_log,
}
