-- The topic `logs`: a container's log, the last lines of it at once and then each line as it is
-- written. Lines go to the page in batches, as parallel lists (the text of each, whether it was
-- written to the error stream, the time of day it was written), since a log is many thousands of
-- lines and a message may be 1 MiB.
--
-- This is api/'s: the files of api/ know the page; docker/, state/ and terminal/ do not.

local pencere = require("pencere")
local time = pencere.time

local logs = require("docker.logs")
local parse = require("docker.parse")

local params = require("api.params")

local M = {}

-- The most lines the page may ask for at the start, and how many it is given if it says nothing.
M.MOST_TAIL = 100000
local DEFAULT_TAIL = 2000

-- A batch is pushed when it holds this many lines or this many bytes of text, and otherwise
-- after a short wait: a burst fills batches, a slow log is shown as it comes.
local BATCH_LINES = 500
local BATCH_BYTES = 200 * 1024
local BATCH_WAIT = 0.05

local schema = params.object({
	id = params.ident(),
	-- Lines from the end to start at; ignored when `since` is given.
	tail = params.optional(params.integer(0, M.MOST_TAIL)),
	-- The time (as the page was told it) of the last line it has: a log that is followed again
	-- goes on from there.
	since = params.optional(params.string(1)),
})

-- The time of day of a line, in this machine's time, as `HH:MM:SS.mmm`.
function M.clock(stamp)
	local seconds = parse.time(stamp)
	if seconds == nil then
		return ""
	end
	local fraction = string.match(stamp, "%.(%d%d%d)") or "000"
	return os.date("%H:%M:%S", seconds) .. "." .. fraction
end

function M.topic(_session)
	return function(args, sub)
		local options, why = params.parse(schema, args)
		if why then
			sub:push({ ended = { code = "bad-params", message = why } })
			return
		end
		local texts, streams, clocks = {}, {}, {}
		local bytes, timer, last = 0, nil, nil
		local skip = options.since
		local function flush()
			timer = nil
			if #texts == 0 then
				return
			end
			local value = {
				texts = texts,
				streams = table.concat(streams),
				clocks = clocks,
				last = last,
			}
			texts, streams, clocks, bytes = {}, {}, {}, 0
			sub:push(value)
		end
		local handle
		local ok, started = pcall(
			logs.follow,
			options.id,
			(options.since == nil) and (options.tail or DEFAULT_TAIL) or nil,
			function(line)
				-- A line a log that is followed again has shown already.
				if skip ~= nil then
					if line.time <= skip then
						return
					end
					skip = nil
				end
				texts[#texts + 1] = line.text
				streams[#streams + 1] = line.stream == "err" and "e" or "o"
				clocks[#clocks + 1] = M.clock(line.time)
				bytes += #line.text
				last = line.time
				if #texts >= BATCH_LINES or bytes >= BATCH_BYTES then
					if timer ~= nil then
						timer:cancel()
						timer = nil
					end
					flush()
				elseif timer == nil then
					timer = time.after(BATCH_WAIT, flush)
				end
			end,
			function(code, message)
				if timer ~= nil then
					timer:cancel()
					timer = nil
				end
				flush()
				sub:push({ ended = { code = code, message = message } })
			end,
			options.since
		)
		if not ok then
			sub:push({ ended = { code = started.code or "failed", message = started.message or tostring(started) } })
			return
		end
		handle = started
		sub:on_end(function()
			if timer ~= nil then
				timer:cancel()
				timer = nil
			end
			handle.stop()
		end)
	end
end

return M
