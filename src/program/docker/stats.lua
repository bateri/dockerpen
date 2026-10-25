-- The resource use of running containers: `docker stats`, which goes on printing a reading of each
-- until it is stopped.

local cli = require("docker.cli")
local parse = require("docker.parse")

local M = {}

-- A line of `docker stats --format json` as a reading: the container, its processor in percent
-- of one processor (a container that keeps two busy is at 200), its memory and the totals of what
-- it moved over the network and the disk, in bytes. nil for a line that is not one.
function M.reading(line)
	local raw = parse.object(line)
	if raw == nil or raw.ID == nil then
		return nil
	end
	local used, limit = parse.pair(raw.MemUsage)
	local received, sent = parse.pair(raw.NetIO)
	local read, written = parse.pair(raw.BlockIO)
	return {
		id = raw.ID,
		name = raw.Name or raw.Container or raw.ID,
		cpu = parse.percent(raw.CPUPerc),
		memory = parse.bytes(used) or 0,
		memory_limit = parse.bytes(limit) or 0,
		net_received = parse.bytes(received),
		net_sent = parse.bytes(sent),
		block_read = parse.bytes(read),
		block_written = parse.bytes(written),
		pids = tonumber(raw.PIDs) or 0,
	}
end

-- Follows the resource use of every running container: `on_reading(reading)` for each line. It is
-- one command for all of them, so a container that starts is followed too. `on_exit(code,
-- stderr)` when the command ends by itself. Returns the handle to stop it with.
function M.follow(on_reading, on_exit)
	local errors = {}
	return cli.stream({ "stats", "--format", "json" }, {
		on_line = function(line)
			local reading = M.reading(line)
			if reading ~= nil then
				on_reading(reading)
			end
		end,
		on_error_line = function(line)
			if #errors < 10 then
				errors[#errors + 1] = line
			end
		end,
		on_exit = function(code)
			on_exit(code, table.concat(errors, "\n"))
		end,
	})
end

return M
