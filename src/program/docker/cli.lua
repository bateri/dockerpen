-- Running the `docker` command. Everything dockerpen knows of Docker comes from it, never from the
-- engine's socket: so the current context, `DOCKER_HOST`, a rootless Docker, OrbStack, Colima and
-- Podman's `docker` all work as they do for the person at a prompt.
--
-- A command that cannot be run, or that fails, raises a table `{ code =, message = }`:
--
--   docker-missing   there is no `docker` on the PATH
--   engine-down      `docker` could not reach an engine
--   docker-failed    the command ran and failed; `message` is what it said

local pencere = require("pencere")
local process, text = pencere.process, pencere.text

local M = {}

-- The command, looked up on the PATH as a shell does.
M.command = "docker"

-- The words of an error, for a person: the first line `docker` wrote, without its `Error response
-- from daemon:` lead.
local function words(stderr)
	stderr = text.lossy(stderr or "")
	local first = string.match(stderr, "[^\n]*%S[^\n]*") or ""
	first = string.gsub(first, "^%s+", "")
	first = string.gsub(first, "^[Ee]rror response from daemon: ", "")
	first = string.gsub(first, "^[Ee]rror: ", "")
	return first
end

-- Whether what `docker` said is that it has no engine to talk to.
local function engine_down(stderr)
	stderr = string.lower(stderr or "")
	return string.find(stderr, "cannot connect to the docker daemon", 1, true) ~= nil
		or string.find(stderr, "error during connect", 1, true) ~= nil
		or string.find(stderr, "is the docker daemon running", 1, true) ~= nil
		or string.find(stderr, "connection refused", 1, true) ~= nil
		or string.find(stderr, "no such file or directory", 1, true) ~= nil
			and string.find(stderr, "docker.sock", 1, true) ~= nil
end

-- What a failed run is, as the table that is raised.
local function failure(result)
	if engine_down(result.stderr) then
		return { code = "engine-down", message = words(result.stderr) }
	end
	local message = words(result.stderr)
	if message == "" then
		message = "docker " .. (result.code and ("exited with " .. result.code) or "was stopped")
	end
	return { code = "docker-failed", message = message }
end

-- What running a program that is not there raises, as the table that tells it.
local function unstartable(why)
	local message = tostring(why)
	if string.find(message, "No such file or directory", 1, true) or string.find(message, "not found", 1, true) then
		return {
			code = "docker-missing",
			message = "There is no docker command on the PATH. dockerpen runs the docker command; install Docker, or put it on the PATH.",
		}
	end
	return { code = "docker-failed", message = message }
end

-- Runs `docker <args>` and waits: `{ ok, code, stdout, stderr }`, or raises `docker-missing` when
-- there is no command. A command that exits with an error is a result, not a raise.
-- `options.timeout` (seconds) ends one that takes too long.
function M.result(args, options)
	local argv = { M.command }
	for _, argument in ipairs(args) do
		argv[#argv + 1] = argument
	end
	local spec = { argv = argv, timeout = options and options.timeout, max_output = 256 * 1024 * 1024 }
	local ok, result = pcall(process.run, spec)
	if not ok then
		error(unstartable(result), 0)
	end
	-- What a program writes is not always text (a process's arguments, a name in a locale): what is
	-- told on is, or it could not be told at all.
	result.stdout, result.stderr = text.lossy(result.stdout or ""), text.lossy(result.stderr or "")
	return result
end

-- Runs `docker <args>` and gives what it printed. A command that fails raises (see the top).
function M.run(args, options)
	local result = M.result(args, options)
	if not result.ok then
		if result.timed_out then
			error({ code = "docker-failed", message = "docker did not answer in time" }, 0)
		end
		error(failure(result), 0)
	end
	return result.stdout
end

-- Starts `docker <args>` and gives what it prints a line at a time: `on_line(line)` for its output,
-- `on_error_line(line)` for what it writes to the error stream, `on_exit(code, signal)` when it
-- ends. Returns a handle with `pid` and `stop()`, which ends it and everything it started; no
-- handler is called after that. Raises `docker-missing` when there is no command.
function M.stream(args, handlers)
	local argv = { M.command }
	for _, argument in ipairs(args) do
		argv[#argv + 1] = argument
	end
	local stopped = false
	local function guarded(name)
		local handler = handlers[name]
		if handler == nil then
			return nil
		end
		return function(...)
			if not stopped then
				handler(...)
			end
		end
	end
	local ok, child = pcall(process.spawn, {
		argv = argv,
		on_stdout = guarded("on_line"),
		on_stderr = guarded("on_error_line"),
		on_exit = guarded("on_exit"),
	})
	if not ok then
		error(unstartable(child), 0)
	end
	return {
		pid = child.pid,
		stop = function()
			if not stopped then
				stopped = true
				child:kill()
			end
		end,
	}
end

-- A failed command as the table that is raised: what a `result` that failed, or a stream that
-- ended with `code` after writing `stderr`, comes to.
function M.failure(code, stderr)
	return failure({ code = code, stderr = stderr })
end

return M
