-- The engine's events as one feed: a single `docker events` for everything that watches, opened
-- when the first watcher comes and stopped when the last one goes. When it is opened again it
-- asks for what happened since the last event it saw, so that what the engine reported while
-- the view was away (a shell had the pane) is not lost.

local cli = require("docker.cli")
local events = require("docker.events")
local feed = require("state.feed")

local M = {}

function M.new()
	local last_time = nil
	return feed.new({
		open = function(emit, closed)
			-- `--since` takes whole seconds and includes the one it names, so the event before may come
			-- again: it is told apart by its time.
			local handle = events.follow(function(event)
				if event.time ~= nil then
					if last_time ~= nil and event.time <= last_time then
						return
					end
					last_time = event.time
				end
				emit(event)
			end, function(code, stderr)
				closed(cli.failure(code, stderr))
			end, last_time and math.floor(last_time) or nil)
			return handle.stop
		end,
	})
end

return M
