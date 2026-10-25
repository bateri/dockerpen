-- The calls about containers: what is known of one (`detail`, `processes`) and what is done to
-- them (`act`).
--
-- This is api/'s: the files of api/ know the page; docker/, state/ and terminal/ do not.

local containers = require("docker.containers")

local call = require("api.call")
local params = require("api.params")

local M = {}

-- The most containers one `act` may name.
local MOST = 500

local ACTIONS = { "start", "stop", "restart", "pause", "unpause", "kill", "remove" }

function M.calls(session)
	local calls = {}

	-- Everything about one container: its configuration, state, health, mounts and networks, and
	-- the engine's whole answer as lines.
	calls.detail = call.new(params.one_id, function(args)
		return containers.detail(args.id)
	end)

	-- The processes running in a container.
	calls.processes = call.new(params.one_id, function(args)
		return containers.processes(args.id)
	end)

	-- Start, stop, restart, pause, resume, kill or remove containers, with one command; says what
	-- became of each.
	calls.act = call.new(
		params.object({
			ids = params.some(params.string(1), MOST),
			action = params.enum(table.unpack(ACTIONS)),
			force = params.optional(params.boolean()),
			volumes = params.optional(params.boolean()),
		}),
		function(args)
			local known = {}
			local snapshot = session.containers.last
			for _, container in ipairs(snapshot and snapshot.containers or {}) do
				known[container.id] = container.name
			end
			local list = {}
			for _, id in ipairs(args.ids) do
				list[#list + 1] = { id = id, name = known[id] or string.sub(id, 1, 12) }
			end
			return { outcomes = containers.act(list, args.action, { force = args.force, volumes = args.volumes }) }
		end
	)

	return calls
end

return M
