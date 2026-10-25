-- The engine as a whole: what it runs on, the disk it takes, the clean-up of what nothing uses.

local pencere = require("pencere")
local env, json = pencere.env, pencere.json

local cli = require("docker.cli")
local parse = require("docker.parse")

local M = {}

-- What the engine says of itself: `name` (the machine, or OrbStack, Docker Desktop), the
-- `version` of the engine, the system it `os` runs on, its `arch`, the processors and the memory
-- in bytes it has, and where the command talks to it (`endpoint`).
function M.info()
	local output = cli.run({ "info", "--format", "{{json .}}" }, { timeout = 30 })
	local ok, raw = pcall(json.decode, output)
	if not ok or type(raw) ~= "table" then
		error({ code = "docker-failed", message = "docker info said something that is not an answer" }, 0)
	end
	local endpoint = env.get("DOCKER_HOST")
	if endpoint == nil or endpoint == "" then
		local result = cli.result({ "context", "inspect", "--format", "{{.Endpoints.docker.Host}}" }, { timeout = 10 })
		endpoint = result.ok and string.match(result.stdout, "%S+") or nil
	end
	return {
		ok = true,
		name = raw.OperatingSystem or raw.Name or "",
		hostname = raw.Name or "",
		version = raw.ServerVersion or "",
		os = raw.OSType or "",
		arch = raw.Architecture or "",
		cpus = raw.NCPU or 0,
		memory = raw.MemTotal or 0,
		endpoint = endpoint or "",
	}
end

local KINDS = {
	Images = "images",
	Containers = "containers",
	["Local Volumes"] = "volumes",
	["Build Cache"] = "build_cache",
}

-- The disk Docker takes, as `docker system df` counts it: for each of the images, containers,
-- volumes and build cache, how many there are, how many are in use, their size and what of it
-- nothing uses, in bytes.
function M.usage()
	local output = cli.run({ "system", "df", "--format", "json" }, { timeout = 50 })
	local usage = {}
	for _, kind in pairs(KINDS) do
		usage[kind] = { count = 0, active = 0, size = 0, reclaimable = 0 }
	end
	for _, raw in ipairs(parse.objects(output)) do
		local kind = KINDS[raw.Type]
		if kind ~= nil then
			usage[kind] = {
				count = tonumber(raw.TotalCount) or 0,
				active = tonumber(raw.Active) or 0,
				size = parse.bytes(raw.Size) or 0,
				reclaimable = parse.reclaimable(raw.Reclaimable) or 0,
			}
		end
	end
	return usage
end

-- What each clean-up runs. Every one is told not to ask: the page asks the person first.
local PRUNES = {
	containers = { "container", "prune", "--force" },
	dangling_images = { "image", "prune", "--force" },
	unused_images = { "image", "prune", "--all", "--force" },
	volumes = { "volume", "prune", "--all", "--force" },
	networks = { "network", "prune", "--force" },
	build_cache = { "builder", "prune", "--all", "--force" },
}

M.PRUNES = PRUNES

-- Removes what nothing uses of one kind: `on_line(line)` for what the command prints,
-- `on_exit(code, message, reclaimed)` when it ends (`reclaimed` in bytes, when it said). Returns
-- the handle to stop it with.
function M.prune(target, on_line, on_exit)
	local args = PRUNES[target]
	if args == nil then
		error({ code = "bad-params", message = "there is nothing to clean up called " .. tostring(target) }, 0)
	end
	local errors, reclaimed = {}, nil
	return cli.stream(args, {
		on_line = function(line)
			local freed = string.match(line, "[Tt]otal reclaimed space: (.+)$")
			if freed ~= nil then
				reclaimed = parse.bytes(freed)
			end
			on_line(line)
		end,
		on_error_line = function(line)
			if #errors < 10 then
				errors[#errors + 1] = line
			end
		end,
		on_exit = function(code)
			on_exit(code, table.concat(errors, "\n"), reclaimed)
		end,
	})
end

return M
