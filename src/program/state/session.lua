-- What the program holds. A view that is closed and shown again (a shell had the pane) or that the
-- terminal starts anew finds all of it here: the engine's events and what was made of them, the
-- containers, the readings of the last two minutes, the jobs, and where the view was.

local pencere = require("pencere")
local time = pencere.time

local activity = require("state.activity")
local containers = require("state.containers")
local docker_stats = require("docker.stats")
local cli = require("docker.cli")
local events = require("state.events")
local feed = require("state.feed")
local jobs = require("state.jobs")
local readings = require("state.readings")

local M = {}

local Session = {}
Session.__index = Session

-- A new session. `options.section` and `options.focus` are what the command line asked the view
-- to open on.
function M.new(options)
	options = options or {}
	local self = setmetatable({}, Session)
	self.events = events.new()
	self.activity = activity.new(self.events)
	self.containers = containers.new(self.events)
	self.readings = readings.new()
	self.stats = feed.new({
		open = function(emit, closed)
			local handle = docker_stats.follow(function(reading)
				emit(self.readings:take(reading, time.monotonic()))
			end, function(code, stderr)
				closed(cli.failure(code, stderr))
			end)
			return handle.stop
		end,
	})
	-- A finished job changes what the lists say, and the disk count.
	self.jobs = jobs.new(function()
		self.volume_sizes = nil
	end)
	-- Where the view was: kept for the next view, which asks for it at the start.
	self.ui = nil
	self.section = options.section
	self.focus = options.focus
	-- Set by terminal/: the way to give the pane to a command, and what became of the last time.
	self.desk = nil
	self.returned = nil
	self.handoff_failed = nil
	-- The volumes' sizes when they were last counted, which is slow.
	self.volume_sizes = nil
	return self
end

-- Forgets the readings of containers that are not in `list` any more.
function Session:tidy(list)
	local ids = {}
	for _, container in ipairs(list) do
		ids[container.short] = true
	end
	self.readings:keep_only(ids)
end

return M
