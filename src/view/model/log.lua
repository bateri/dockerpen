local lib_sizes = require("../lib/sizes")
local model_state = require("./state")
local LOG_MOST = lib_sizes.LOG_MOST
local S = model_state.S

-- ---- a container's log -----------------------------------------------------------------------------

local L = S.log

local function log_clear(id, tail)
	L.id, L.tail = id, tail or L.tail
	L.texts, L.streams, L.clocks = {}, "", {}
	L.count, L.last, L.ended = 0, nil, nil
	L.matches, L.scanned, L.match_at = {}, 0, 0
	L.runs, L.run_count = {}, 0
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

-- Whether the container of the log on show is running (a log of one that stopped does not go on).
local function log_live()
	local c = L.id and S.by_id[L.id]
	return c ~= nil and c.state == "running"
end

return {
	L = L,
	log_clear = log_clear,
	log_live = log_live,
	on_log = on_log,
}
