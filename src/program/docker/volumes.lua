-- Volumes: what `docker volume ls` lists, how much each takes once Docker has counted, taking one
-- away.

local cli = require("docker.cli")
local parse = require("docker.parse")

local M = {}

-- The volumes: `name`, `driver`, `mountpoint`, the compose `project` that made it, and whether
-- it is anonymous (a name that is a 64-digit hash).
function M.list()
	local output = cli.run({ "volume", "ls", "--format", "json" }, { timeout = 30 })
	local list = {}
	for _, raw in ipairs(parse.objects(output)) do
		local labels = parse.labels(raw.Labels)
		local name = raw.Name or ""
		list[#list + 1] = {
			name = name,
			driver = raw.Driver or "",
			mountpoint = raw.Mountpoint or "",
			project = labels["com.docker.compose.project"],
			anonymous = string.match(name, "^%x+$") ~= nil and #name == 64,
		}
	end
	return list
end

-- The size of each volume in bytes, by name, as `docker system df -v` counts them. Counting
-- can take the engine a while on a busy machine.
function M.sizes()
	local output = cli.run({ "system", "df", "-v", "--format", "json" }, { timeout = 120 })
	local parsed = parse.object(string.match(output, "{.*}") or "")
	local sizes = {}
	for _, volume in ipairs(parsed and parsed.Volumes or {}) do
		local bytes = parse.bytes(volume.Size)
		if volume.Name ~= nil and bytes ~= nil then
			sizes[volume.Name] = bytes
		end
	end
	return sizes
end

-- Takes a volume away.
function M.remove(name)
	cli.run({ "volume", "rm", name }, { timeout = 60 })
end

return M
