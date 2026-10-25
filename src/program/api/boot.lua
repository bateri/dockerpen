-- The calls about the program and the view's own state: `boot` (what the view shows first: where it
-- was, and what became of the last hand-off), `ui` (where the view is, kept for the next view) and
-- `handoff` (the pane given to a shell in a container, or to its log, which gives it back when it
-- ends).
--
-- This is api/'s: the files of api/ know the page; docker/, state/ and terminal/ do not.

local pencere = require("pencere")
local env, json, time = pencere.env, pencere.json, pencere.time

local call = require("api.call")
local params = require("api.params")
local version = require("version")

local M = {}

-- What the page keeps of itself between views: its section, the container it is on, its filters.
-- The program does not read it, and holds it only as large as one message allows.
local ui_state = params.object({ ui = params.any() })

-- What a failed hand-off is told as: the words for the person.
local HANDOFF_FAILED = {
	unsupported = "This terminal cannot hand its pane to a command and back.",
	closing = "The view could not be closed just now.",
}

local function present(value)
	return value ~= nil and value ~= ""
end

function M.calls(session)
	local calls = {}

	-- What the page shows first.
	calls.boot = call.new(params.nothing, function()
		local returned, focus, section = session.returned, session.focus, session.section
		session.returned, session.focus, session.section = nil, nil, nil
		local failed = session.handoff_failed
		session.handoff_failed = nil
		local boot = {
			version = version,
			-- The page has no clock of its own, only the time of its frames: it tells the time of day
			-- from this (seconds since 1970 as the program reads it now).
			time = time.now(),
			hostname = pencere.os.hostname(),
			remote = present(env.get("SSH_CONNECTION")) or present(env.get("SSH_TTY")),
			ui = session.ui or json.null,
			handoff = session.desk ~= nil,
			section = section or json.null,
			focus = focus or json.null,
		}
		if returned then
			boot.returned = {
				kind = returned.kind,
				name = returned.name,
				status = returned.status == nil and json.null or returned.status,
				duration = returned.ms,
				error = returned.error,
			}
		end
		if failed then
			boot.handoff_failed = HANDOFF_FAILED[failed] or failed
		end
		return boot
	end)

	-- Where the page is, kept for the next view.
	calls.ui = call.new(ui_state, function(args)
		session.ui = args.ui
		return json.object()
	end)

	-- Hands the pane to a shell in a container, or to its log as it comes.
	calls.handoff = call.new(
		params.object({
			kind = params.enum("shell", "logs"),
			id = params.string(1),
			name = params.optional(params.string(1)),
		}),
		function(args)
			local desk = session.desk
			if desk == nil then
				return { state = "unavailable" }
			end
			return { state = desk.request(args.kind, args.id, args.name or string.sub(args.id, 1, 12)) }
		end
	)

	return calls
end

return M
