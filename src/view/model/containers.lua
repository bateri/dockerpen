local lib_fmt = require("../lib/fmt")
local model_state = require("./state")
local fmt = lib_fmt.fmt
local S = model_state.S

-- ---- the containers, as the page reads them ----------------------------------------------------

local function is_up(c)
	return c.state == "running" or c.state == "restarting" or c.state == "paused"
end

-- A container that stopped by a signal (⌃C, a kill, a stop that was asked for) did what it was told:
-- these exit codes are no failure.
local STOPPED_BY_SIGNAL = { [0] = true, [130] = true, [137] = true, [143] = true }

-- Whether it exited with a code that is a failure.
local function failed(c)
	return c.state == "exited" and c.exit_code ~= nil and not STOPPED_BY_SIGNAL[c.exit_code]
end

-- Whether there is something the person is to look at: unhealthy, restarting, dead, or failed.
local function has_issue(c)
	return c.health == "unhealthy" or c.state == "restarting" or c.state == "dead" or failed(c)
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
		if c.exit_code == 137 then
			return "killed", "dim"
		elseif c.exit_code == 143 then
			return "terminated", "dim"
		elseif c.exit_code == 130 then
			return "interrupted", "dim"
		elseif failed(c) then
			return "exited " .. c.exit_code, "error"
		end
		return "exited", "dim"
	elseif c.state == "dead" then
		return "dead", "error"
	end
	return c.state, "dim"
end

-- The name a container goes by in its project's list: the service it is a replica of (`api`, `api #2`),
-- or its own name where it is not one.
local function display_name(c, grouped)
	if not grouped or not c.service or not c.project then
		return c.name
	end
	local prefix = c.project .. "-" .. c.service .. "-"
	local alt = c.project .. "_" .. c.service .. "_"
	local replica = nil
	if string.sub(c.name, 1, #prefix) == prefix then
		replica = string.sub(c.name, #prefix + 1)
	elseif string.sub(c.name, 1, #alt) == alt then
		replica = string.sub(c.name, #alt + 1)
	end
	if replica and string.find(replica, "^%d+$") then
		return replica == "1" and c.service or (c.service .. " #" .. replica)
	end
	return c.name
end

-- The address a container publishes a port at, as a browser is given it: the first port that has
-- a public side.
local function port_url(c)
	for _, port in ipairs(c.ports or {}) do
		if port.public then
			return "http://localhost:" .. port.public
		end
	end
	return nil
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
	display_name = display_name,
	failed = failed,
	has_issue = has_issue,
	is_up = is_up,
	name_of = name_of,
	port_url = port_url,
	state_of = state_of,
	unix_now = unix_now,
}
