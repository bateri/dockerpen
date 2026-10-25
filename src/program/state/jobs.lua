-- The work that takes a while: a pull, a clean-up. It runs in the program, and what the page
-- sees of it is the list of jobs here, each with how far it has come: a view that closes and
-- comes back (a shell had the pane) finds them as they were.

local pencere = require("pencere")
local time = pencere.time

local images = require("docker.images")
local system = require("docker.system")

local M = {}

-- How many finished jobs are kept to be seen.
M.KEPT = 6

local TITLES = {
	containers = "stopped containers",
	dangling_images = "dangling images",
	unused_images = "unused images",
	volumes = "unused volumes",
	networks = "unused networks",
	build_cache = "build cache",
}

local Jobs = {}
Jobs.__index = Jobs

function M.new(on_done)
	return setmetatable({ list = {}, next_id = 1, watchers = {}, next_watcher = 1, on_done = on_done }, Jobs)
end

-- The jobs, oldest first, as plain tables.
function Jobs:all()
	return self.list
end

-- Calls `fn(jobs)` whenever a job starts, moves or ends; returns the function that stops it.
function Jobs:watch(fn)
	local id = self.next_watcher
	self.next_watcher += 1
	self.watchers[id] = fn
	return function()
		self.watchers[id] = nil
	end
end

function Jobs:changed()
	local ids = {}
	for id in pairs(self.watchers) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local fn = self.watchers[id]
		if fn then
			fn(self.list)
		end
	end
end

function Jobs:add(kind, title)
	local job = {
		id = "job" .. self.next_id,
		kind = kind,
		title = title,
		state = "running",
		progress = nil,
		detail = "",
		started = time.now(),
	}
	self.next_id += 1
	self.list[#self.list + 1] = job
	local finished = 0
	for index = #self.list, 1, -1 do
		if self.list[index].state ~= "running" then
			finished += 1
			if finished > M.KEPT then
				table.remove(self.list, index)
			end
		end
	end
	self:changed()
	return job
end

function Jobs:finish(job, state, detail, failure)
	job.state = state
	job.progress = state == "done" and 1 or job.progress
	job.detail = detail or job.detail
	job.error = failure
	job.ended = time.now()
	self:changed()
	if self.on_done then
		self.on_done(job)
	end
end

-- Pulls an image: the job it is. `reference` is what `docker pull` takes (`redis`, `nginx:1.27`).
function Jobs:pull(reference)
	local job = self:add("pull", "Pull " .. reference)
	local state = images.progress()
	local ok, handle = pcall(images.pull, reference, function(line)
		local fraction, said = images.pulled(state, line)
		job.progress = fraction or job.progress
		job.detail = said
		self:changed()
	end, function(code, message)
		if code == 0 then
			self:finish(job, "done", "pulled " .. reference)
		else
			self:finish(job, "failed", nil, message ~= "" and message or ("docker pull exited with " .. tostring(code)))
		end
	end)
	if not ok then
		self:finish(job, "failed", nil, type(handle) == "table" and handle.message or tostring(handle))
	end
	return job
end

-- Cleans up what nothing uses, one kind after another: the job it is.
function Jobs:prune(targets)
	local names = {}
	for _, target in ipairs(targets) do
		names[#names + 1] = TITLES[target] or target
	end
	local job = self:add("prune", "Clean up " .. table.concat(names, ", "))
	local freed, index = 0, 0
	local function next_target()
		index += 1
		local target = targets[index]
		if target == nil then
			job.freed = freed
			self:finish(job, "done", "")
			return
		end
		job.progress = (index - 1) / #targets
		job.detail = TITLES[target] or target
		self:changed()
		local ok, why = pcall(system.prune, target, function() end, function(code, message, reclaimed)
			if code ~= 0 then
				self:finish(job, "failed", nil, message ~= "" and message or ("docker exited with " .. tostring(code)))
				return
			end
			freed += reclaimed or 0
			next_target()
		end)
		if not ok then
			self:finish(job, "failed", nil, type(why) == "table" and why.message or tostring(why))
		end
	end
	next_target()
	return job
end

return M
