local lib_kit = require("../lib/kit")
local b = lib_kit.b

-- ---- what it asks its program, and what it is told ------------------------------------------

local net = {}

local watching = {}

-- Asks the program for `method`; `done(result, error)` when it answers.
function net.ask(method, params, done)
	return b.call(method, params, function(result, err)
		done(result, err)
		return true
	end)
end

-- Listens to a topic under a name of its own; asking again under the name replaces it.
function net.watch(key, topic, params, handler)
	if watching[key] then
		b.cancel(watching[key])
	end
	watching[key] = b.subscribe(topic, params, function(value)
		handler(value)
		return true
	end)
end

function net.unwatch(key)
	if watching[key] then
		b.cancel(watching[key])
		watching[key] = nil
	end
end

function net.watching(key)
	return watching[key] ~= nil
end

-- What a failed call says, for a person: the words, and for the two ways docker can be out of reach,
-- what to do.
local function why(err)
	if err == nil then
		return nil
	end
	return err.message or err.code or "it failed"
end

return {
	net = net,
	why = why,
}
