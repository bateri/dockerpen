-- What the engine reports as it happens: `docker events`, which goes on until it is stopped.

local cli = require("docker.cli")
local parse = require("docker.parse")

local M = {}

-- The kinds of event that change what dockerpen shows.
local TYPES = { "container", "image", "volume", "network" }

-- What a container does that is not worth a line: running a command in it (the engine reports
-- each one of a health check), looking at its processes (dockerpen's own, while the tab is on
-- show), attaching to it, and the like.
local NOISE = {
	exec_create = true,
	exec_start = true,
	exec_die = true,
	exec_detach = true,
	top = true,
	attach = true,
	detach = true,
	resize = true,
	copy = true,
	export = true,
	["archive-path"] = true,
	["extract-to-dir"] = true,
}

-- An event the engine printed as a record: its kind, what happened, to what, and the few
-- attributes of it that say more (the image, an exit code, a signal).
function M.event(line)
	local raw = parse.object(line)
	if raw == nil then
		return nil
	end
	local kind = raw.Type or raw.type
	local action = raw.Action or raw.status
	if kind == nil or action == nil then
		return nil
	end
	-- `health_status: unhealthy` and `exec_start: sh -c …` say more after the colon.
	local base, after = string.match(action, "^([^:]+):%s*(.*)$")
	if base ~= nil then
		action = base
	end
	if NOISE[action] then
		return nil
	end
	local actor = raw.Actor or {}
	local attributes = actor.Attributes or {}
	local detail = {}
	if after ~= nil and after ~= "" then
		detail.status = after
	end
	for _, key in ipairs({ "image", "exitCode", "signal", "reason", "driver", "type" }) do
		if attributes[key] ~= nil and attributes[key] ~= "" then
			detail[key] = attributes[key]
		end
	end
	local time = tonumber(raw.timeNano)
	return {
		type = kind,
		action = action,
		id = actor.ID or raw.id or "",
		name = attributes.name,
		project = attributes["com.docker.compose.project"],
		time = time and time / 1e9 or tonumber(raw.time),
		detail = detail,
	}
end

-- Follows the engine's events (from `since`, seconds since 1970, when it is given): `on_event(event)`
-- for each, `on_exit(code, stderr)` when the command ends by itself. Returns the handle to stop it
-- with.
function M.follow(on_event, on_exit, since)
	local errors = {}
	local args = { "events", "--format", "json" }
	-- From a time on: what happened while nobody was watching.
	if since ~= nil then
		args[#args + 1] = "--since"
		args[#args + 1] = string.format("%d", since)
	end
	for _, kind in ipairs(TYPES) do
		args[#args + 1] = "--filter"
		args[#args + 1] = "type=" .. kind
	end
	return cli.stream(args, {
		on_line = function(line)
			local event = M.event(line)
			if event ~= nil then
				on_event(event)
			end
		end,
		on_error_line = function(line)
			if #errors < 10 then
				errors[#errors + 1] = line
			end
		end,
		on_exit = function(code)
			on_exit(code, table.concat(errors, "\n"))
		end,
	})
end

return M
