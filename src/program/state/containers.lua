-- The containers as the program holds them: the list and the engine it comes from, kept up to
-- date from the engine's events, never by asking again and again.

local pencere = require("pencere")
local json, time = pencere.json, pencere.time

local containers = require("docker.containers")
local feed = require("state.feed")
local system = require("docker.system")

local M = {}

-- How long after an event the list is looked at again, seconds: a compose project that starts
-- is a dozen events in a moment, and one look takes them all in.
M.DEBOUNCE = 0.25

-- The feed of the containers: a value is `{ containers =, engine =, failure = }` — the list, what
-- the engine says of itself, and why there is no list (a failure, with the last list kept).
-- `events` is the feed of the engine's events.
function M.new(events)
	local last_encoded = nil
	return feed.new({
		keep = true,
		open = function(emit, _closed)
			local engine, list, failure = nil, {}, nil
			local busy, again, stopped, timer = false, false, false, nil
			local function tell()
				local value = { containers = list, engine = engine, failure = failure }
				local encoded = json.encode(value)
				if encoded ~= last_encoded then
					last_encoded = encoded
					emit(value)
				end
			end
			local function look()
				if busy then
					again = true
					return
				end
				busy = true
				repeat
					again = false
					local ok, found = pcall(containers.list)
					if stopped then
						return
					end
					if ok then
						list, failure = found, nil
						if engine == nil or not engine.ok then
							local known, info = pcall(system.info)
							engine = known and info or nil
						end
					else
						failure = type(found) == "table" and found
							or { code = "docker-failed", message = tostring(found) }
					end
					tell()
				until not again
				busy = false
			end
			local function later()
				if timer == nil then
					timer = time.after(M.DEBOUNCE, function()
						timer = nil
						look()
					end)
				end
			end
			local unwatch = events:watch(function(event)
				if event.type == "container" then
					later()
				end
			end, function(state, why)
				if state == "down" then
					failure = why
					tell()
				else
					later()
				end
			end)
			-- The first look is made from a task of its own, so that opening returns at once.
			timer = time.after(0, function()
				timer = nil
				look()
			end)
			return function()
				stopped = true
				if timer ~= nil then
					timer:cancel()
					timer = nil
				end
				unwatch()
				-- A look that is under way is the one `stopped` ends; the next opening starts afresh.
				last_encoded = nil
			end
		end,
	})
end

return M
