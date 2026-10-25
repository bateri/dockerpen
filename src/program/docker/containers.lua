-- Containers: the list, one container's detail, its processes, and what can be done to it.

local pencere = require("pencere")
local json = pencere.json

local cli = require("docker.cli")
local parse = require("docker.parse")

local M = {}

local STATES = {
	running = true,
	exited = true,
	paused = true,
	restarting = true,
	created = true,
	removing = true,
	dead = true,
}

-- What `docker ps` says of a name list (`a,b` when a container has links): the first.
local function first_name(names)
	return string.match(names or "", "^[^,]+") or ""
end

local function split(list)
	local out = {}
	for item in string.gmatch(list or "", "[^,]+") do
		out[#out + 1] = item
	end
	return out
end

-- The command as `docker ps` prints it: in quotes, and cut with an ellipsis.
local function command_of(raw)
	return (string.gsub(raw or "", '^"(.*)"$', "%1"))
end

local function summarize(raw)
	local state = STATES[raw.State] and raw.State or "created"
	local labels = parse.labels(raw.Labels)
	local status = parse.status(raw.Status, state)
	local id = raw.ID or ""
	return {
		id = id,
		short = string.sub(id, 1, 12),
		name = first_name(raw.Names) ~= "" and first_name(raw.Names) or string.sub(id, 1, 12),
		image = parse.image_name(raw.Image) or "",
		command = command_of(raw.Command),
		created = parse.time(raw.CreatedAt),
		state = state,
		status = raw.Status or "",
		health = status.health,
		exit_code = status.exit_code,
		ports = parse.ports(raw.Ports),
		project = labels["com.docker.compose.project"],
		service = labels["com.docker.compose.service"],
		networks = split(raw.Networks),
		mounts = split(raw.Mounts),
	}
end

-- Every container, running or not, as plain tables.
function M.list()
	local output = cli.run({ "ps", "-a", "--no-trunc", "--format", "json" }, { timeout = 30 })
	local list = {}
	for _, raw in ipairs(parse.objects(output)) do
		list[#list + 1] = summarize(raw)
	end
	return list
end

local function policy_of(restart)
	if restart == nil or restart.Name == nil or restart.Name == "" or restart.Name == "no" then
		return "no"
	end
	if restart.Name == "on-failure" and restart.MaximumRetryCount and restart.MaximumRetryCount > 0 then
		return "on-failure:" .. restart.MaximumRetryCount
	end
	return restart.Name
end

-- The ports `inspect` says a container publishes: each as a table, and the ones it exposes
-- without publishing (`exposed`: the image's `EXPOSE`s, which `inspect` lists with no binding).
local function ports_of(map, exposed)
	local ports = {}
	local specs = {}
	for spec in pairs(exposed or {}) do
		specs[spec] = false
	end
	for spec, bindings in pairs(map or {}) do
		specs[spec] = bindings
	end
	for spec, bindings in pairs(specs) do
		local number, kind = string.match(spec, "^(%d+)/(%a+)$")
		if number ~= nil then
			local unique, any = {}, false
			if type(bindings) == "table" then
				for _, binding in ipairs(bindings) do
					local public = tonumber(binding.HostPort)
					if public ~= nil and not unique[public] then
						unique[public] = true
						any = true
						local entry = { public = public, private = tonumber(number), type = kind }
						if binding.HostIp and binding.HostIp ~= "" then
							entry.ip = binding.HostIp
						end
						ports[#ports + 1] = entry
					end
				end
			end
			if not any then
				ports[#ports + 1] = { private = tonumber(number), type = kind }
			end
		end
	end
	table.sort(ports, function(a, b)
		if a.private ~= b.private then
			return a.private < b.private
		end
		return (a.public or 0) < (b.public or 0)
	end)
	return ports
end

local function sorted_keys(map)
	local keys = {}
	for key in pairs(map or {}) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	return keys
end

-- The most lines of the engine's whole answer that are kept, and the longest one of them.
local MOST_RAW_LINES = 3000

-- Everything about one container: what `docker inspect` says, as plain values, and its text.
function M.detail(id)
	local output = cli.run({ "inspect", "--type", "container", id }, { timeout = 30 })
	local ok, decoded = pcall(json.decode, output)
	local raw = ok and type(decoded) == "table" and decoded[1] or nil
	if raw == nil then
		error({ code = "docker-failed", message = "there is no container " .. id }, 0)
	end
	local config, state, host = raw.Config or {}, raw.State or {}, raw.HostConfig or {}
	local env = {}
	for _, entry in ipairs(config.Env or {}) do
		local key, value = string.match(entry, "^([^=]*)=(.*)$")
		env[#env + 1] = key and { key = key, value = value } or { key = entry, value = "" }
	end
	local health = nil
	if state.Health then
		local log = {}
		local entries = state.Health.Log or {}
		for index = math.max(#entries - 4, 1), #entries do
			local entry = entries[index]
			log[#log + 1] = {
				start = parse.time(entry.Start),
				["end"] = parse.time(entry.End),
				exit_code = entry.ExitCode,
				output = string.sub((string.gsub(entry.Output or "", "^%s*(.-)%s*$", "%1")), 1, 2000),
			}
		end
		health = {
			status = state.Health.Status or "none",
			failing_streak = state.Health.FailingStreak or 0,
			log = log,
		}
	end
	local networks = {}
	local settings = raw.NetworkSettings or {}
	for _, name in ipairs(sorted_keys(settings.Networks)) do
		local network = settings.Networks[name]
		local aliases = {}
		for _, alias in ipairs(network.Aliases or {}) do
			if string.sub(raw.Id, 1, #alias) ~= alias then
				aliases[#aliases + 1] = alias
			end
		end
		networks[#networks + 1] = {
			name = name,
			ip = network.IPAddress or "",
			gateway = network.Gateway or "",
			mac = network.MacAddress or "",
			aliases = aliases,
		}
	end
	local mounts = {}
	for _, mount in ipairs(raw.Mounts or {}) do
		mounts[#mounts + 1] = {
			type = mount.Type or "",
			name = mount.Name,
			source = mount.Source or "",
			destination = mount.Destination or "",
			rw = mount.RW ~= false,
		}
	end
	local lines = parse.lines(output, MOST_RAW_LINES)
	-- A time of day for a person, in the machine's own clock: `Oct 22, 2026, 03:31 AM`.
	local function label(seconds)
		return seconds and os.date("%b %d, %Y, %I:%M %p", math.floor(seconds)) or nil
	end
	return {
		id = raw.Id,
		name = (string.gsub(raw.Name or "", "^/", "")),
		image = config.Image or "",
		image_id = raw.Image or "",
		created = parse.time(raw.Created),
		created_label = label(parse.time(raw.Created)),
		path = raw.Path or "",
		args = raw.Args or {},
		entrypoint = config.Entrypoint or {},
		cmd = config.Cmd or {},
		working_dir = config.WorkingDir or "",
		user = config.User or "",
		env = env,
		labels = config.Labels or {},
		state = {
			status = STATES[state.Status] and state.Status or "created",
			running = state.Running == true,
			paused = state.Paused == true,
			restarting = state.Restarting == true,
			oom_killed = state.OOMKilled == true,
			dead = state.Dead == true,
			pid = state.Pid or 0,
			exit_code = state.ExitCode or 0,
			error = state.Error or "",
			started_at = parse.time(state.StartedAt),
			finished_at = parse.time(state.FinishedAt),
			started_label = label(parse.time(state.StartedAt)),
			finished_label = label(parse.time(state.FinishedAt)),
			health = health,
		},
		restart_count = raw.RestartCount or 0,
		restart_policy = policy_of(host.RestartPolicy),
		tty = config.Tty == true,
		platform = raw.Platform or "",
		network_mode = host.NetworkMode or "",
		privileged = host.Privileged == true,
		memory_limit = host.Memory or 0,
		cpu_limit = (host.NanoCpus or 0) / 1e9,
		ports = ports_of(settings.Ports, config.ExposedPorts),
		networks = networks,
		mounts = mounts,
		healthcheck = config.Healthcheck and config.Healthcheck.Test or nil,
		lines = lines,
	}
end

-- The processes running in a container: the titles of the columns and a row for each. A container
-- that is not running has none, which is not a failure.
function M.processes(id)
	local result = cli.result({ "top", id }, { timeout = 15 })
	if not result.ok then
		local stderr = string.lower(result.stderr or "")
		if string.find(stderr, "is not running", 1, true) or string.find(stderr, "is paused", 1, true) then
			return { titles = {}, rows = {} }
		end
		error(cli.failure(result.code, result.stderr), 0)
	end
	local titles, rows = parse.table(result.stdout)
	return { titles = titles, rows = rows }
end

-- How long a container is given to stop before it is killed: Docker's own default.
local STOP_GRACE = 10

-- What can be done to a container: each gives the arguments of the command before the containers.
local ACTIONS = {
	start = function()
		return { "start" }
	end,
	stop = function()
		return { "stop", "--time", tostring(STOP_GRACE) }
	end,
	restart = function()
		return { "restart", "--time", tostring(STOP_GRACE) }
	end,
	pause = function()
		return { "pause" }
	end,
	unpause = function()
		return { "unpause" }
	end,
	kill = function()
		return { "kill" }
	end,
	remove = function(options)
		local args = { "rm" }
		if options and options.force then
			args[#args + 1] = "--force"
		end
		if options and options.volumes then
			args[#args + 1] = "--volumes"
		end
		return args
	end,
}

M.actions = ACTIONS

-- The line of what a command wrote that is about a container (it names it or its id), or the
-- first line there is.
local function said_of(lines, container)
	for _, line in ipairs(lines) do
		if line ~= "" and (string.find(line, container.id, 1, true) or string.find(line, container.name, 1, true)) then
			return line
		end
	end
	return lines[1]
end

-- Does `action` to `containers` (a list of `{ id =, name = }`) with one command, which does them
-- all at once. Gives an outcome for each: `{ id =, name =, ok =, error = }`. Raises when the
-- command could not be run at all.
function M.act(list, action, options)
	local build = ACTIONS[action]
	if build == nil then
		error({ code = "bad-params", message = "there is no action " .. tostring(action) }, 0)
	end
	local args = build(options)
	for _, container in ipairs(list) do
		args[#args + 1] = container.id
	end
	local result = cli.result(args, { timeout = STOP_GRACE + 25 })
	-- No engine is no answer for any of them, not an answer for each.
	if not result.ok then
		local failure = cli.failure(result.code, result.stderr)
		if failure.code == "engine-down" then
			error(failure, 0)
		end
	end
	-- The command prints what it was given for each container it did it to.
	local printed = {}
	for line in string.gmatch(result.stdout or "", "[^\n]+") do
		printed[string.match(line, "^%s*(.-)%s*$")] = true
	end
	local errors = {}
	for line in string.gmatch(result.stderr or "", "[^\n]+") do
		line = string.gsub(line, "^[Ee]rror response from daemon: ", "")
		errors[#errors + 1] = line
	end
	local outcomes = {}
	for _, container in ipairs(list) do
		local ok = printed[container.id] == true or printed[container.name] == true
		if result.ok then
			ok = true
		end
		outcomes[#outcomes + 1] = {
			id = container.id,
			name = container.name,
			ok = ok,
			error = (not ok) and (said_of(errors, container) or "docker did not say why") or nil,
		}
	end
	return outcomes
end

return M
