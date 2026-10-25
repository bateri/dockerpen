-- A stream that runs while someone watches it. The first watcher opens it (a `docker events` or
-- `docker stats` starts, or the container list is looked at), the last one closes it (the command
-- is stopped), and in between the watchers are told what comes. Nothing runs for a feed nobody
-- watches, which is what keeps dockerpen idle when its view is not up.
--
-- A stream that ends by itself (the engine was restarted, Docker was quit) is opened again after
-- a while, for as long as someone watches: 1 second, then twice as long each time up to 30. The
-- watchers are told it is down, with the words, and told it is up again.

local pencere = require("pencere")
local time = pencere.time

local M = {}

local Feed = {}
Feed.__index = Feed

-- The first delay before a stream that ended is opened again, seconds; and the longest.
local FIRST_RETRY = 1
local LONGEST_RETRY = 30
-- A stream that has run this long (seconds) when it ends was a good one: the next delay starts over.
local GOOD_RUN = 10
-- A stream that was opened again and has not ended in this long (seconds) is taken to be up, even
-- if it has nothing to say yet.
local SETTLE = 1.5

-- A feed made by `spec.open(emit, closed)`, which starts the stream and returns the function that
-- stops it. `emit(value)` gives the watchers a value; `closed(error)` says the stream ended by
-- itself. With `spec.keep`, a watcher that comes while it runs is given the last value at once.
function M.new(spec)
	return setmetatable({
		spec = spec,
		watchers = {},
		count = 0,
		next_id = 1,
		generation = 0,
		close = nil,
		timer = nil,
		delay = FIRST_RETRY,
		failure = nil,
		last = nil,
		opened_at = 0,
		settle = nil,
	}, Feed)
end

-- The watchers in the order they came, as a list (a watcher may stop watching as it is told).
local function ordered(feed)
	local ids = {}
	for id in pairs(feed.watchers) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	local list = {}
	for _, id in ipairs(ids) do
		list[#list + 1] = feed.watchers[id]
	end
	return list
end

local function tell_status(feed, state, failure)
	for _, watcher in ipairs(ordered(feed)) do
		if watcher.status and feed.watchers[watcher.id] then
			watcher.status(state, failure)
		end
	end
end

function Feed:fail(failure)
	local known = self.failure ~= nil and self.failure.message == failure.message
	self.failure = failure
	if not known then
		tell_status(self, "down", failure)
	end
	if self.count == 0 or self.timer ~= nil then
		return
	end
	local delay = self.delay
	self.delay = math.min(self.delay * 2, LONGEST_RETRY)
	self.timer = time.after(delay, function()
		self.timer = nil
		if self.count > 0 then
			self:open()
		end
	end)
end

function Feed:open()
	self.generation += 1
	local generation = self.generation
	self.opened_at = time.monotonic()
	local function emit(value)
		if generation ~= self.generation then
			return
		end
		if self.failure ~= nil then
			self.failure = nil
			tell_status(self, "up")
		end
		if self.spec.keep then
			self.last = value
		end
		for _, watcher in ipairs(ordered(self)) do
			if self.watchers[watcher.id] then
				watcher.fn(value)
			end
		end
	end
	local function closed(failure)
		if generation ~= self.generation then
			return
		end
		self.close = nil
		self:unsettle()
		if time.monotonic() - self.opened_at >= GOOD_RUN then
			self.delay = FIRST_RETRY
		end
		self:fail(failure or { code = "ended", message = "the stream ended" })
	end
	local ok, close = pcall(self.spec.open, emit, closed)
	if not ok then
		self.close = nil
		self:fail(type(close) == "table" and close or { code = "failed", message = tostring(close) })
		return
	end
	self.close = close
	-- A stream opened again after it failed is up if it is still there a little later.
	if self.failure ~= nil then
		self.settle = time.after(SETTLE, function()
			self.settle = nil
			if generation == self.generation and self.failure ~= nil then
				self.failure = nil
				tell_status(self, "up")
			end
		end)
	end
end

function Feed:unsettle()
	if self.settle ~= nil then
		self.settle:cancel()
		self.settle = nil
	end
end

function Feed:shut()
	self.generation += 1
	self:unsettle()
	if self.close ~= nil then
		local close = self.close
		self.close = nil
		pcall(close)
	end
	if self.timer ~= nil then
		self.timer:cancel()
		self.timer = nil
	end
	self.failure = nil
	self.delay = FIRST_RETRY
end

-- Watches the feed: `fn(value)` for each value, and `status("down", failure)` / `status("up")`
-- when the stream goes and comes back. Returns the function that stops watching.
function Feed:watch(fn, status)
	local id = self.next_id
	self.next_id += 1
	self.watchers[id] = { id = id, fn = fn, status = status }
	self.count += 1
	if self.count == 1 then
		self:open()
	else
		if self.spec.keep and self.last ~= nil then
			fn(self.last)
		end
		if self.failure ~= nil and status then
			status("down", self.failure)
		end
	end
	return function()
		if self.watchers[id] ~= nil then
			self.watchers[id] = nil
			self.count -= 1
			if self.count == 0 then
				self:shut()
			end
		end
	end
end

-- Whether anyone is watching (and so whether anything runs).
function Feed:running()
	return self.count > 0
end

return M
