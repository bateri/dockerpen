local lib_fmt = require("../lib/fmt")
local model_net = require("./net")
local model_rows = require("./rows")
local model_state = require("./state")
local model_toast = require("./toast")
local fmt = lib_fmt.fmt
local why = model_net.why
local keep_cursor = model_rows.keep_cursor
local S, bump = model_state.S, model_state.bump
local toast = model_toast.toast

-- ---- the containers, as the program tells them -----------------------------------------------------

local function sync_containers(list)
	S.containers = list
	S.by_id = {}
	for _, c in ipairs(list) do
		S.by_id[c.id] = c
	end
	for id in pairs(S.marks.containers or {}) do
		if S.by_id[id] == nil then
			S.marks.containers[id] = nil
		end
	end
	if S.open and S.by_id[S.open] == nil then
		S.open = nil
		S.focus = "list"
	end
	bump()
end

-- What the container list says of the engine: why there is no list, or that there is one again.
local function on_containers(value)
	local was = S.failure
	S.known = true
	S.engine = value.engine or S.engine
	S.failure = value.failure
	sync_containers(value.containers or {})
	keep_cursor("containers")
	S.reveal = false
	if S.failure and not was then
		-- Said once, where the person is, however far from the list.
		toast.say(why(S.failure), { kind = "error" })
	elseif was and not S.failure then
		toast.say("Docker is back", { kind = "success" })
	end
end

-- A container's stats as they come: the last reading of each, and a line of the last readings.
local function on_stats(value)
	if value.history then
		for short, series in pairs(value.history) do
			S.series[short] = series
		end
	end
	for _, sample in ipairs(value.samples or {}) do
		S.samples[sample.id] = sample
		local series = S.series[sample.id]
		if series == nil then
			series = { cpu = {}, memory = {}, net_in = {}, net_out = {} }
			S.series[sample.id] = series
		end
		for _, key in ipairs({ "cpu", "memory", "net_in", "net_out" }) do
			local line = series[key]
			line[#line + 1] = sample[key]
			if #line > 120 then
				table.remove(line, 1)
			end
		end
	end
	-- Containers that are not running have no reading.
	for short in pairs(S.samples) do
		local alive = false
		for _, c in ipairs(S.containers) do
			if c.short == short and c.state == "running" then
				alive = true
				break
			end
		end
		if not alive then
			S.samples[short] = nil
		end
	end
	if S.sort == "cpu" or S.sort == "memory" then
		bump()
	end
end

-- What the engine reports: kept as the Activity screen shows it, and, for the ones that are news,
-- told where the person is.
local function on_events(value)
	local items = value.items
	if value.backlog then
		items = value.backlog
		S.activity = {}
	end
	for _, item in ipairs(items or {}) do
		table.insert(S.activity, 1, item)
		if #S.activity > 300 then
			table.remove(S.activity)
		end
		if item.notice and not value.backlog then
			local name = item.name or string.sub(item.id or "", 1, 12)
			toast.say(name .. " " .. (item.words or item.action), {
				kind = item.notice == "unhealthy" and "warning" or "error",
				seconds = 9,
				show = item.type == "container" and item.id or nil,
			})
		end
		-- A change to what lists show is a reason to look again, if they are on show.
		if item.type == "image" or item.type == "volume" or item.type == "network" then
			local section = item.type .. "s"
			if S.lists[section] then
				S.stale[section] = true
				S.pending_reload = S.now + 0.4
			end
		end
	end
	bump()
end

local function on_jobs(value)
	local was = {}
	for _, job in ipairs(S.jobs) do
		was[job.id] = job.state
	end
	S.jobs = value.jobs or {}
	for _, job in ipairs(S.jobs) do
		if was[job.id] == "running" and job.state ~= "running" then
			if job.state == "done" then
				if job.kind == "pull" then
					toast.say(job.title .. ": done", { kind = "success" })
				else
					toast.say(
						job.freed and job.freed > 0 and ("Freed " .. fmt.disk(job.freed)) or (job.title .. ": done"),
						{ kind = "success" }
					)
				end
			else
				toast.say(job.title .. " failed: " .. tostring(job.error), { kind = "error", seconds = 10 })
			end
			S.stale.images, S.stale.volumes, S.stale.networks, S.stale.system = true, true, true, true
			S.pending_reload = S.now + 0.2
		end
	end
	bump()
end

return {
	on_containers = on_containers,
	on_events = on_events,
	on_jobs = on_jobs,
	on_stats = on_stats,
}
