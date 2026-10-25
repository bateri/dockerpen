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
	-- The first time the page sees the containers, the projects with nothing running are folded away.
	if not S.folded_known and #S.containers > 0 then
		S.folded_known = true
		local seen, running = {}, {}
		for _, c in ipairs(S.containers) do
			if c.project then
				seen[c.project] = true
				running[c.project] = running[c.project] or c.state == "running"
			end
		end
		for project in pairs(seen) do
			if not running[project] then
				S.folded[project] = true
			end
		end
	end
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
	if #(value.samples or {}) > 0 then
		local cpu, memory = 0, 0
		for _, sample in pairs(S.samples) do
			cpu += sample.cpu or 0
			memory += sample.memory or 0
		end
		S.totals[#S.totals + 1] = { cpu = cpu, memory = memory }
		if #S.totals > 120 then
			table.remove(S.totals, 1)
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
		for _, item in ipairs(items) do
			S.live_from = math.max(S.live_from, item.seq or 0)
		end
	end
	for _, item in ipairs(items or {}) do
		table.insert(S.activity, 1, item)
		if #S.activity > 300 then
			table.remove(S.activity)
		end
		if item.notice and not value.backlog then
			-- What the person is to hear of while looking elsewhere: a container that ran out of
			-- memory, that stopped with a failure, that turned unhealthy.
			local name = item.name or string.sub(item.id or "", 1, 12)
			local code = item.detail and item.detail.exitCode
			local title, kind = name .. " " .. (item.words or item.action), "error"
			if item.notice == "oom" then
				title = name .. " ran out of memory"
			elseif item.notice == "died" then
				title, kind = name .. " exited with code " .. tostring(code or "?"), "warning"
			elseif item.notice == "unhealthy" then
				title = name .. " is unhealthy"
			end
			toast.say(title, {
				kind = kind,
				show = item.type == "container" and item.id or nil,
				action = item.type == "container" and { label = "Logs", open = item.id } or nil,
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
				local body = job.detail
				if (body == nil or body == "") and job.freed and job.freed > 0 then
					body = "Freed " .. fmt.bytes(job.freed)
				end
				toast.say(job.title, { kind = "success", body = body ~= "" and body or nil })
			else
				toast.say(job.title .. " failed", { kind = "error", body = job.error or job.detail })
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
