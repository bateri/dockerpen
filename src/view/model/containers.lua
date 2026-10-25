local lib_fmt = require("../lib/fmt")
local model_state = require("./state")
local fmt = lib_fmt.fmt
local S = model_state.S

-- ---- the containers, as the page reads them ----------------------------------------------------

local function is_up(c)
	return c.state == "running" or c.state == "restarting" or c.state == "paused"
end

local function has_issue(c)
	return c.health == "unhealthy"
		or c.state == "restarting"
		or c.state == "dead"
		or (c.state == "exited" and c.exit_code ~= nil and c.exit_code ~= 0)
end

-- What a container is, in a word and a colour: its state, or its health when that is the news.
local function state_of(c)
	local busy = S.busy[c.id]
	if busy then
		return busy .. "…", "warning"
	end
	if c.state == "running" then
		if c.health == "unhealthy" then
			return "unhealthy", "error"
		elseif c.health == "starting" then
			return "starting", "warning"
		elseif c.health == "healthy" then
			return "healthy", "success"
		end
		return "running", "success"
	elseif c.state == "paused" then
		return "paused", "warning"
	elseif c.state == "restarting" then
		return "restarting", "warning"
	elseif c.state == "exited" then
		if c.exit_code ~= nil and c.exit_code ~= 0 then
			return "exited " .. c.exit_code, "error"
		end
		return "exited", "dim"
	elseif c.state == "dead" then
		return "dead", "error"
	end
	return c.state, "dim"
end

local function container(id)
	return S.by_id[id]
end

local function name_of(id)
	local c = S.by_id[id]
	return c and c.name or string.sub(id, 1, 12)
end

-- The unix time now, from the program's clock when the page has it.
local function unix_now()
	return S.clock and (S.now + S.clock) or nil
end

-- How long ago a time (seconds since 1970) was, in words.
local function ago(seconds)
	local at = unix_now()
	if seconds == nil or at == nil then
		return nil
	end
	return fmt.span(at - seconds) .. " ago"
end

return {
	ago = ago,
	container = container,
	has_issue = has_issue,
	is_up = is_up,
	name_of = name_of,
	state_of = state_of,
}
