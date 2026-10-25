-- The pane given away and taken back. When the person asks for a shell in a container (or for its
-- log as it comes) the program closes the view, runs the command in the terminal, and the view is
-- shown again where it was when the command ends; what the page keeps of itself is the program's
-- (`state/`), so it crosses that gap.
--
-- Plain values in and out: this file knows nothing of the page. How the command ended, and a
-- hand-off the terminal could not make, are left in the session (`returned`, `handoff_failed`) as
-- plain values for api/ to tell the view.

local pencere = require("pencere")
local time = pencere.time

local cli = require("docker.cli")

local M = {}

-- The shell integrations a person's rc file loads whatever the terminal, turned off in the shell
-- of a container: a short-lived command has no prompt the terminal needs to know of, and its marks
-- would only move the terminal's idea of the pane back and forth. The variables go to the local
-- `docker`, which does not pass them on into the container.
local ENV = {
	ITERM_SHELL_INTEGRATION_INSTALLED = "Yes",
	WEZTERM_SHELL_SKIP_ALL = "1",
	DOCKERPEN_SHELL = "1",
}

-- What the container runs for a shell: bash when it has it, the shell every image has otherwise.
local SHELL = "command -v bash >/dev/null 2>&1 && exec bash || exec sh"

-- How many lines of the log a person is given when the pane goes to it, before it goes on.
local LOG_TAIL = "200"

local bar = "\27[7m dockerpen \27[0m "

local function title(what, name, how)
	return bar .. what .. " \27[1m" .. name .. "\27[0m  \27[2m" .. how .. "\27[0m"
end

-- What a hand-off runs: the command (argv after `docker`) and the line the person is shown first.
-- The line is the first word, once the view is gone and the terminal is the command's.
local KINDS = {
	shell = function(id, name)
		return { "exec", "-it", id, "sh", "-c", SHELL }, title("shell in", name, "exit or ⌃D goes back to dockerpen")
	end,
	logs = function(id, name)
		return { "logs", "--follow", "--tail", LOG_TAIL, id }, title("log of", name, "⌃C goes back to dockerpen")
	end,
}

local Handoff = {}
Handoff.__index = Handoff

-- The hand-offs of `session`. `session.desk` is what api/ offers the page: `desk.request(kind, id,
-- name)`. `handed_off` is set once the view has been closed for a command: from then on a view that
-- does not come back is not replaced with another program.
function M.new(session)
	local self = setmetatable({ session = session, handed_off = false, asked = false }, Handoff)
	self.desk = {
		request = function(kind, id, name)
			if self.asked then
				return "busy"
			end
			if KINDS[kind] == nil then
				return "unavailable"
			end
			self.asked = true
			-- The answer to the page's call goes out first, so that it can show what comes.
			time.after(0.12, function()
				self:run(kind, id, name)
			end)
			return "scheduled"
		end,
	}
	return self
end

-- The pane, handed to the command of `kind` for the container `id`: the view closes, the command
-- has the terminal as if it had been started from the prompt, and when it ends the view is shown
-- again, where it was.
function Handoff:run(kind, id, name)
	local session = self.session
	local arguments, banner = KINDS[kind](id, name)
	local argv = { "/bin/sh", "-c", 'printf "%s\\n" "$1"; shift; exec "$@"', "sh", banner, cli.command }
	for _, argument in ipairs(arguments) do
		argv[#argv + 1] = argument
	end
	local started = time.monotonic()
	local ok, result = pcall(pencere.handoff, { argv = argv, env = ENV })
	self.handed_off = true
	self.asked = false
	if not ok then
		local words = tostring(result)
		session.handoff_failed = string.find(words, "cannot close the view", 1, true) and "unsupported" or "closing"
		return
	end
	local returned = {
		kind = kind,
		name = name,
		status = result.code,
		ms = math.floor((time.monotonic() - started) * 1000),
	}
	if result.code == 126 or result.code == 127 then
		returned.error = "could not run docker"
	end
	session.returned = returned
end

-- The view did not come back after the command: the terminal did not answer, or would not show
-- it. The person chooses: once more, or quit. True to try again.
function Handoff:try_again(reason)
	local pencere_io = pencere.io
	local why = reason == "no-host" and "the terminal did not answer" or ("the terminal said " .. tostring(reason))
	pencere_io.write(
		bar .. "the view did not come back: " .. why .. ".\n\27[2m             ⏎ tries again, q and ⏎ quits.\27[0m "
	)
	local answer = pencere_io.read_line()
	if answer == nil then
		return false
	end
	answer = string.lower((string.gsub(answer, "^%s*(.-)%s*$", "%1")))
	return answer ~= "q"
end

return M
