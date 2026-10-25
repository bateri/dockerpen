-- A container's log: `docker logs --follow`, a line at a time, with the time docker gives each and
-- whether the container wrote it to its output or to its error stream.

local pencere = require("pencere")
local text = pencere.text

local cli = require("docker.cli")
local parse = require("docker.parse")

local M = {}

-- The longest line that is kept, characters of the line as bytes.
M.LONGEST_LINE = 4000

local function cut(line)
	line = text.lossy(line)
	if string.sub(line, -1) == "\r" then
		line = string.sub(line, 1, -2)
	end
	if #line > M.LONGEST_LINE then
		local at = M.LONGEST_LINE
		-- Not in the middle of a character.
		while
			at > 0
			and string.byte(line, at + 1)
			and string.byte(line, at + 1) >= 0x80
			and string.byte(line, at + 1) < 0xC0
		do
			at -= 1
		end
		line = string.sub(line, 1, at) .. "…"
	end
	return line
end

-- Follows the log of `id`: from its last `tail` lines on (all of it when that is nil), or from the
-- time `since` (as docker wrote it on a line) on when that is given. `on_line({ time =, stream =,
-- text = })` for each, `on_exit(code, message)` when docker ends (the container stopped, is
-- gone, or the engine is). Returns the handle to stop it with.
function M.follow(id, tail, on_line, on_exit, since)
	local errors = {}
	local args = { "logs", "--follow", "--timestamps" }
	if since ~= nil then
		args[#args + 1] = "--since"
		args[#args + 1] = since
	else
		args[#args + 1] = "--tail"
		args[#args + 1] = tail and tostring(tail) or "all"
	end
	args[#args + 1] = id
	return cli.stream(args, {
		on_line = function(line)
			local time, rest = parse.log_line(line)
			on_line({ time = time or "", stream = "out", text = cut(rest) })
		end,
		-- What a container writes to its error stream comes on docker's, line for line with a
		-- time before it; what docker itself says (the container is gone) has none.
		on_error_line = function(line)
			local time, rest = parse.log_line(line)
			if time ~= nil then
				on_line({ time = time, stream = "err", text = cut(rest) })
			elseif #errors < 10 then
				errors[#errors + 1] = line
			end
		end,
		on_exit = function(code)
			on_exit(code, table.concat(errors, "\n"))
		end,
	})
end

-- The last `tail` lines, once: `{ { time =, stream =, text = } … }`.
function M.read(id, tail)
	local lines = {}
	local result = cli.result({ "logs", "--timestamps", "--tail", tostring(tail), id }, { timeout = 20 })
	if not result.ok then
		error(cli.failure(result.code, result.stderr), 0)
	end
	for line in string.gmatch(result.stdout, "[^\n]+") do
		local time, rest = parse.log_line(line)
		lines[#lines + 1] = { time = time or "", stream = "out", text = cut(rest) }
	end
	return lines
end

return M
