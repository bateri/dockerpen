-- Networks: what `docker network ls` lists with the subnets and the containers of each, taking
-- one away.

local pencere = require("pencere")
local json = pencere.json

local cli = require("docker.cli")
local parse = require("docker.parse")

local M = {}

local BUILTIN = { bridge = true, host = true, none = true }

-- The networks: `id` (twelve digits), `name`, `driver`, `scope`, whether it is `internal`, its
-- `subnets` and `gateways`, when it was made, the compose `project` that made it, and the
-- `containers` on it (names, the ones running or not that `inspect` says are attached).
function M.list()
	local output = cli.run({ "network", "ls", "--no-trunc", "--format", "json" }, { timeout = 30 })
	local list, ids = {}, {}
	for _, raw in ipairs(parse.objects(output)) do
		ids[#ids + 1] = raw.ID
		local labels = parse.labels(raw.Labels)
		list[#list + 1] = {
			id = string.sub(raw.ID or "", 1, 12),
			full_id = raw.ID,
			name = raw.Name or "",
			driver = raw.Driver or "",
			scope = raw.Scope or "",
			internal = raw.Internal == "true",
			created = parse.time(raw.CreatedAt),
			builtin = BUILTIN[raw.Name] == true,
			project = labels["com.docker.compose.project"],
			subnets = {},
			gateways = {},
			containers = {},
		}
	end
	if #ids > 0 then
		local args = { "network", "inspect" }
		for _, id in ipairs(ids) do
			args[#args + 1] = id
		end
		local result = cli.result(args, { timeout = 30 })
		local ok, decoded = pcall(json.decode, result.stdout)
		if ok and type(decoded) == "table" then
			local byid = {}
			for _, network in ipairs(list) do
				byid[network.full_id] = network
			end
			for _, raw in ipairs(decoded) do
				local network = byid[raw.Id]
				if network ~= nil then
					for _, config in ipairs((raw.IPAM or {}).Config or {}) do
						if config.Subnet then
							network.subnets[#network.subnets + 1] = config.Subnet
						end
						if config.Gateway then
							network.gateways[#network.gateways + 1] = config.Gateway
						end
					end
					for _, member in pairs(raw.Containers or {}) do
						if member.Name then
							network.containers[#network.containers + 1] = member.Name
						end
					end
					table.sort(network.containers)
				end
			end
		end
	end
	for _, network in ipairs(list) do
		network.full_id = nil
	end
	return list
end

-- Takes a network away.
function M.remove(id)
	cli.run({ "network", "rm", id }, { timeout = 60 })
end

return M
