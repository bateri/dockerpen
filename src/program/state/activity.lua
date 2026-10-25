-- What the engine reported: the last of it kept as the feed the Activity screen shows, and the
-- ones that deserve to be told wherever the person is — a container that died, ran out of memory
-- or turned unhealthy.

local pencere = require("pencere")
local time = pencere.time

local feed = require("state.feed")

local M = {}

-- How many events are kept.
M.KEPT = 300

-- A container that was asked to stop dies with a code that is the signal's; a death that follows
-- within this many seconds of the request is not news.
local ASKED = 20

-- What an event is, as a sentence for a person, and whether it is news: `{ notice = kind }`.
local function describe(event, asked)
	local detail = event.detail
	if event.type == "container" then
		if event.action == "die" then
			local code = tonumber(detail.exitCode)
			if code ~= nil and code ~= 0 and not (asked[event.id] and time.monotonic() - asked[event.id] < ASKED) then
				return { notice = "died", words = "exited with code " .. code }
			end
			return { words = code and ("exited with code " .. code) or "exited" }
		elseif event.action == "oom" then
			return { notice = "oom", words = "ran out of memory" }
		elseif event.action == "health_status" then
			if detail.status == "unhealthy" then
				return { notice = "unhealthy", words = "turned unhealthy" }
			end
			return { words = "is " .. (detail.status or "checked") }
		elseif event.action == "kill" then
			return { words = "was sent " .. (detail.signal and ("signal " .. detail.signal) or "a signal") }
		end
		return { words = event.action }
	end
	return { words = event.action }
end

-- The feed of what the engine reports, built on `events` (the feed of its events): each value is
-- `{ seq =, time =, clock =, day =, type =, action =, id =, name =, project =, detail =, words =, notice = }`.
-- `backlog()` is what was kept, oldest first; it outlives the feed, so a page that comes back
-- from a shell finds it.
function M.new(events)
	local ring, seq = {}, 0
	local asked = {}
	local self = {}
	self.feed = feed.new({
		open = function(emit, _closed)
			return events:watch(function(event)
				if event.type == "container" and (event.action == "kill" or event.action == "stop") then
					asked[event.id] = time.monotonic()
				end
				local words = describe(event, asked)
				seq += 1
				local at = event.time and math.floor(event.time) or nil
				local item = {
					seq = seq,
					time = event.time,
					-- The time of the day and the day, in the words of the machine's own clock.
					clock = at and os.date("%H:%M:%S", at) or nil,
					day = at and os.date("%A, %b %d", at) or nil,
					type = event.type,
					action = event.action,
					id = event.id,
					name = event.name,
					project = event.project,
					detail = event.detail,
					words = words.words,
					notice = words.notice,
				}
				ring[#ring + 1] = item
				if #ring > M.KEPT then
					table.remove(ring, 1)
				end
				emit(item)
			end)
		end,
	})
	function self.backlog()
		return ring
	end
	return self
end

return M
