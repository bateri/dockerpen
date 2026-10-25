-- A feed runs while someone watches it, and not otherwise.

local pencere = require("pencere")
local t = require("t")
local feed = require("state.feed")

t.test("the first watcher opens it, the last one closes it", function()
	local opened, closed = 0, 0
	local f = feed.new({
		open = function(emit)
			opened += 1
			emit("first")
			return function()
				closed += 1
			end
		end,
	})
	local seen = {}
	local stop_one = f:watch(function(value)
		seen[#seen + 1] = value
	end)
	local stop_two = f:watch(function(value)
		seen[#seen + 1] = "two:" .. value
	end)
	t.eq(opened, 1, "opened once for two watchers")
	t.eq(seen, { "first" })
	stop_one()
	t.eq(closed, 0, "one still watches")
	stop_two()
	t.eq(closed, 1)
	t.ok(not f:running())
	f:watch(function() end)
	t.eq(opened, 2, "opened again for the next watcher")
end)

t.test("a feed that keeps its last value gives it to a watcher that comes later", function()
	local f = feed.new({
		keep = true,
		open = function(emit)
			emit(42)
			return function() end
		end,
	})
	f:watch(function() end)
	local late = nil
	f:watch(function(value)
		late = value
	end)
	t.eq(late, 42)
end)

t.test("a stream that ends by itself is opened again, and the watchers are told", function()
	local opened = 0
	local f = feed.new({
		open = function(emit, closed)
			opened += 1
			if opened == 1 then
				closed({ code = "engine-down", message = "gone" })
			else
				emit("again")
			end
			return function() end
		end,
	})
	local states, values = {}, {}
	f:watch(function(value)
		values[#values + 1] = value
	end, function(state, why)
		states[#states + 1] = state .. (why and (":" .. why.message) or "")
	end)
	t.eq(opened, 1)
	t.eq(states, { "down:gone" })
	pencere.time.sleep(1.3)
	t.eq(opened, 2, "opened again after a second")
	t.eq(values, { "again" })
	t.eq(states, { "down:gone", "up" })
end)

t.test("a stream nobody watches any more is not opened again", function()
	local opened = 0
	local f = feed.new({
		open = function(_, closed)
			opened += 1
			closed({ code = "x", message = "gone" })
			return function() end
		end,
	})
	local stop = f:watch(function() end, function() end)
	stop()
	pencere.time.sleep(1.3)
	t.eq(opened, 1)
end)
