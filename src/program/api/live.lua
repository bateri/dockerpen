-- The topics the page listens to as things change: the containers, their resource use, what the
-- engine reports, the jobs. Each opens what it needs when the page subscribes and closes it when
-- the page does not listen any more (`sub:on_end`): with nothing subscribed, nothing runs.
--
-- This is api/'s: the files of api/ know the page; docker/, state/ and terminal/ do not.

local pencere = require("pencere")
local json, time = pencere.json, pencere.time

local M = {}

-- How long samples and events are gathered before they are pushed, seconds: `docker stats` says
-- a line for each container in the same moment, and one push carries them all.
local WINDOW = 0.1

-- A function that pushes what is `put` into it, at most once in a window, in a message of its
-- own. `shape(list)` makes the value pushed from what was put.
local function batcher(sub, shape)
	local waiting, timer = {}, nil
	local function flush()
		timer = nil
		if #waiting == 0 then
			return
		end
		local list = waiting
		waiting = {}
		sub:push(shape(list))
	end
	sub:on_end(function()
		if timer ~= nil then
			timer:cancel()
			timer = nil
		end
		waiting = {}
	end)
	return function(item)
		waiting[#waiting + 1] = item
		if timer == nil then
			timer = time.after(WINDOW, flush)
		end
	end
end

-- The containers and the engine they are in, as the page is told: the list; what the engine says
-- of itself, once it has; why there is no list, if there is none. A failure keeps the last list.
local function containers_value(value)
	return {
		containers = value.containers,
		engine = value.engine or json.null,
		failure = value.failure or json.null,
	}
end

-- What a reading is, as the page is told.
local function sample_value(sample)
	return {
		id = sample.id,
		name = sample.name,
		cpu = sample.cpu,
		memory = sample.memory,
		memory_limit = sample.memory_limit,
		net_in = sample.net_in,
		net_out = sample.net_out,
		disk_read = sample.disk_read,
		disk_write = sample.disk_write,
		pids = sample.pids,
	}
end

function M.topics(session)
	local topics = {}

	-- The containers, one value at once and then one each time something changed in them.
	topics.containers = function(_, sub)
		local unwatch = session.containers:watch(function(value)
			if value.containers then
				session:tidy(value.containers)
			end
			sub:push(containers_value(value))
		end)
		sub:on_end(unwatch)
	end

	-- The resource use of the running containers: the last two minutes of each at once, then the
	-- readings as they come.
	topics.stats = function(_, sub)
		local history = {}
		for id, series in pairs(session.readings:all()) do
			history[id] = series
		end
		sub:push({ history = history })
		local put = batcher(sub, function(samples)
			return { samples = samples }
		end)
		local unwatch = session.stats:watch(function(sample)
			put(sample_value(sample))
		end)
		sub:on_end(unwatch)
	end

	-- What the engine reports: what was kept at once, then each event as it comes.
	topics.events = function(_, sub)
		sub:push({ backlog = session.activity.backlog() })
		local put = batcher(sub, function(items)
			return { items = items }
		end)
		local unwatch = session.activity.feed:watch(put)
		sub:on_end(unwatch)
	end

	-- The jobs, as they are and each time one moves.
	topics.jobs = function(_, sub)
		sub:push({ jobs = session.jobs:all() })
		local unwatch = session.jobs:watch(function(list)
			sub:push({ jobs = list })
		end)
		sub:on_end(unwatch)
	end

	return topics
end

return M
