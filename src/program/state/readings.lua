-- The resource use of containers over time. `docker stats` gives totals (the bytes a container
-- has sent so far), so the rates are worked out here from the reading before, and the last two
-- minutes of each container are kept for the charts. They are the program's, not the page's, so
-- that a page that comes back from a shell finds them.

local M = {}

-- How many samples of each container are kept: two minutes at one a second.
M.HISTORY = 120

-- A gap in seconds after which the totals of the reading before say nothing about the rate now.
local STALE = 10

local Readings = {}
Readings.__index = Readings

function M.new()
	return setmetatable({ before = {}, series = {} }, Readings)
end

local function push(list, value)
	list[#list + 1] = value
	if #list > M.HISTORY then
		table.remove(list, 1)
	end
end

local function rate(now, before, seconds)
	if now == nil or before == nil or seconds <= 0 then
		return 0
	end
	return math.max(0, (now - before) / seconds)
end

-- Takes a reading (`docker/stats.lua`'s) at `now` (seconds, a clock that only goes forward) and
-- gives the sample it makes: the reading with the rates since the one before.
function Readings:take(reading, now)
	local before = self.before[reading.id]
	local fresh = before ~= nil and now - before.at <= STALE
	local seconds = fresh and now - before.at or 0
	local sample = {
		id = reading.id,
		name = reading.name,
		cpu = reading.cpu or 0,
		memory = reading.memory,
		memory_limit = reading.memory_limit,
		net_in = fresh and rate(reading.net_received, before.net_received, seconds) or 0,
		net_out = fresh and rate(reading.net_sent, before.net_sent, seconds) or 0,
		disk_read = fresh and rate(reading.block_read, before.block_read, seconds) or 0,
		disk_write = fresh and rate(reading.block_written, before.block_written, seconds) or 0,
		pids = reading.pids,
	}
	self.before[reading.id] = {
		at = now,
		net_received = reading.net_received,
		net_sent = reading.net_sent,
		block_read = reading.block_read,
		block_written = reading.block_written,
	}
	local series = self.series[reading.id]
	if series == nil then
		series = { cpu = {}, memory = {}, net_in = {}, net_out = {} }
		self.series[reading.id] = series
	end
	push(series.cpu, sample.cpu)
	push(series.memory, sample.memory)
	push(series.net_in, sample.net_in)
	push(series.net_out, sample.net_out)
	return sample
end

-- What is kept of one container: `{ cpu, memory, net_in, net_out }`, each a list of numbers, the
-- newest last.
function Readings:history(id)
	return self.series[id]
end

-- Every container's history, by id.
function Readings:all()
	return self.series
end

-- Forgets the containers that are not in `ids` (a set, by id).
function Readings:keep_only(ids)
	for id in pairs(self.series) do
		if not ids[id] then
			self.series[id] = nil
			self.before[id] = nil
		end
	end
end

return M
