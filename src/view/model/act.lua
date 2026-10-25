local lib_fmt = require("../lib/fmt")
local model_containers = require("./containers")
local model_net = require("./net")
local model_rows = require("./rows")
local model_state = require("./state")
local model_toast = require("./toast")
local fmt = lib_fmt.fmt
local name_of = model_containers.name_of
local net, why = model_net.net, model_net.why
local targets = model_rows.targets
local S, bump = model_state.S, model_state.bump
local toast = model_toast.toast

-- ---- what the person asks to be done ---------------------------------------------------------------

local act = {}

local PARTICIPLE = {
	start = "starting",
	stop = "stopping",
	restart = "restarting",
	pause = "pausing",
	unpause = "resuming",
	kill = "killing",
	remove = "removing",
}

local PAST = {
	start = "Started",
	stop = "Stopped",
	restart = "Restarted",
	pause = "Paused",
	unpause = "Resumed",
	kill = "Killed",
	remove = "Removed",
}

local FAILED = {
	start = "start",
	stop = "stop",
	restart = "restart",
	pause = "pause",
	unpause = "resume",
	kill = "kill",
	remove = "remove",
}

local function names_of(ids)
	if #ids == 1 then
		return name_of(ids[1])
	end
	return fmt.count(#ids, "container")
end

-- Does `action` to the containers `ids`, and says how it went. A stop or a pause can be taken back
-- from the toast that says it happened.
function act.run(ids, action, options)
	options = options or {}
	local todo = {}
	for _, id in ipairs(ids) do
		if not S.busy[id] then
			todo[#todo + 1] = id
		end
	end
	ids = todo
	if #ids == 0 then
		return
	end
	for _, id in ipairs(ids) do
		S.busy[id] = PARTICIPLE[action]
	end
	bump()
	local params = { ids = ids, action = action, force = options.force or nil, volumes = options.volumes or nil }
	net.ask("act", params, function(result, err)
		for _, id in ipairs(ids) do
			S.busy[id] = nil
		end
		bump()
		if err then
			toast.say("Could not " .. FAILED[action] .. " " .. names_of(ids), { kind = "error", body = why(err) })
			return
		end
		local done, failed = {}, {}
		for _, outcome in ipairs(result.outcomes) do
			if outcome.ok then
				done[#done + 1] = outcome.id
			else
				failed[#failed + 1] = outcome
			end
		end
		if #failed > 0 then
			local names = {}
			for _, outcome in ipairs(failed) do
				names[#names + 1] = outcome.name
			end
			toast.say(
				"Could not " .. FAILED[action] .. " " .. table.concat(names, ", "),
				{ kind = "error", body = failed[1].error or "it failed" }
			)
		end
		if #done > 0 and not options.quiet then
			local offer = nil
			if action == "stop" or action == "pause" then
				offer = {
					label = action == "stop" and "Start again" or "Resume",
					run = function()
						act.run(done, action == "stop" and "start" or "unpause")
					end,
				}
			end
			toast.say(PAST[action] .. " " .. names_of(done), { kind = "success", action = offer })
		end
		if action == "remove" then
			for _, id in ipairs(done) do
				S.marks.containers[id] = nil
				if S.open == id then
					S.open, S.focus = nil, "list"
				end
			end
		end
	end)
end

-- The pane to a shell in a container, or to its log as it comes.
function act.terminal(kind, c)
	if not S.handoff then
		toast.say("No terminal to hand over", {
			kind = "info",
			body = "dockerpen hands its pane to a shell when it runs in a terminal with the docker command.",
		})
		return
	end
	if kind == "shell" and c.state ~= "running" then
		toast.say(c.name .. " is not running", {
			kind = "warning",
			body = "A shell needs a running container.",
			action = {
				label = "Start it",
				run = function()
					act.run({ c.id }, "start")
				end,
			},
		})
		return
	end
	net.ask("handoff", { kind = kind, id = c.id, name = c.name }, function(result, err)
		if err then
			toast.say(
				"Could not open the " .. (kind == "shell" and "shell" or "logs"),
				{ kind = "error", body = why(err) }
			)
		elseif result.state == "unavailable" then
			toast.say(
				"No terminal to hand over",
				{ kind = "info", body = "This terminal cannot hand its pane to a command and back." }
			)
		elseif result.state == "busy" then
			toast.say("The pane is going to a command already.", { kind = "warning" })
		end
	end)
end

-- Asks first: a question over everything. `spec`: `kind` ("confirm", "pull" or "prune"), `title`,
-- `body`, `confirm` (the word on the button), `danger`, `options` (`{ key =, label =, hint =, size =,
-- value = }`, boxes to tick), `run(values)` for what to do, and, for a pull, `field`.
local function ask(spec)
	spec.kind = spec.kind or "confirm"
	spec.cursor = 1
	spec.values = {}
	for _, option in ipairs(spec.options or {}) do
		spec.values[option.key] = option.value == true
	end
	S.dialog = spec
	bump()
end

-- What a failed or finished removal says, and the list read again.
local function remove_things(method, key, ids, label, extra)
	local params = { [key] = ids }
	for name, value in pairs(extra or {}) do
		params[name] = value
	end
	net.ask(method, params, function(result, err)
		if err then
			toast.say("Could not remove", { kind = "error", body = why(err) })
			return
		end
		local done, failed = {}, {}
		for _, outcome in ipairs(result.outcomes) do
			if outcome.ok then
				done[#done + 1] = outcome
			else
				failed[#failed + 1] = outcome
			end
		end
		if #done == 1 then
			toast.say("Removed " .. (done[1].name or label), { kind = "success" })
		elseif #done > 1 then
			toast.say("Removed " .. #done, { kind = "success" })
		end
		if #failed > 0 then
			toast.say(
				"Could not remove " .. (failed[1].name or "it"),
				{ kind = "error", body = failed[1].error or "it failed" }
			)
		end
		local section = method == "image_remove" and "images" or (method == "volume_remove" and "volumes" or "networks")
		S.marks[section] = {}
		S.stale[section] = true
		S.pending_reload = S.now + 0.1
	end)
end

local function short(id)
	return string.sub((string.gsub(id or "", "^sha256:", "")), 1, 12)
end

-- Asks, then removes, what the cursor or the marks name in a list of images, volumes or networks.
function act.remove_listed(section)
	local rows = targets(section)
	if #rows == 0 then
		return
	end
	if section == "images" then
		local ids, used = {}, {}
		for _, row in ipairs(rows) do
			ids[#ids + 1] = row.id
			if #row.item.containers > 0 then
				used[#used + 1] = row.item.tags[1] and fmt.image_name(row.item.tags[1]) or short(row.id)
			end
		end
		local first = rows[1].item
		local name = first.tags[1] and fmt.image_name(first.tags[1]) or short(first.id)
		ask({
			title = #rows == 1 and ("Remove " .. name .. "?") or ("Remove " .. #rows .. " images?"),
			body = #used > 0
					and (table.concat(used, ", ") .. (#used == 1 and " is" or " are") .. " used by containers; removing needs force, and the containers keep running from layers they hold.")
				or "Layers no other image shares are deleted. A later run pulls the image again.",
			confirm = "Remove",
			danger = true,
			options = #used > 0 and { { key = "force", label = "Force, although containers use it", value = true } }
				or nil,
			run = function(values)
				remove_things("image_remove", "ids", ids, name, { force = values.force == true })
			end,
		})
	elseif section == "volumes" then
		local free = {}
		for _, row in ipairs(rows) do
			if #row.item.containers == 0 then
				free[#free + 1] = row
			end
		end
		if #free == 0 then
			toast.say("In use", {
				kind = "info",
				body = "A volume a container uses cannot be removed; remove the container first.",
			})
			return
		end
		local names = {}
		for _, row in ipairs(free) do
			names[#names + 1] = row.item.name
		end
		local one = free[1].item
		ask({
			title = #free == 1 and ("Remove volume " .. (one.anonymous and short(one.name) or one.name) .. "?")
				or ("Remove " .. #free .. " volumes?"),
			body = "The data in them is deleted for good. There is no undo.",
			confirm = "Delete data",
			danger = true,
			run = function()
				remove_things("volume_remove", "names", names, one.name)
			end,
		})
	else
		local free = {}
		for _, row in ipairs(rows) do
			if not row.item.builtin and #row.item.containers == 0 then
				free[#free + 1] = row
			end
		end
		if #free == 0 then
			toast.say("Nothing to remove", {
				kind = "info",
				body = "Built-in networks and networks with running containers stay.",
			})
			return
		end
		local ids = {}
		for _, row in ipairs(free) do
			ids[#ids + 1] = row.id
		end
		ask({
			title = #free == 1 and ("Remove network " .. free[1].item.name .. "?")
				or ("Remove " .. #free .. " networks?"),
			body = "Stopped containers attached to it lose the attachment.",
			confirm = "Remove",
			danger = true,
			run = function()
				remove_things("network_remove", "ids", ids, free[1].item.name)
			end,
		})
	end
end

-- Asks, then removes, the containers the cursor or the marks name.
function act.remove_containers()
	local rows = targets("containers")
	local ids, running = {}, 0
	for _, row in ipairs(rows) do
		ids[#ids + 1] = row.id
		if row.c.state == "running" or row.c.state == "paused" then
			running += 1
		end
	end
	if #ids == 0 then
		return
	end
	local one = #rows == 1 and rows[1].c or nil
	local body = one
			and ("The container and its writable layer go; the image " .. fmt.image_name(one.image) .. " stays.")
		or "The containers and their writable layers go; their images stay."
	if running > 0 then
		body = body
			.. ((running == 1 and one) and " It is" or (" " .. running .. " are"))
			.. " running and will be stopped first."
	end
	ask({
		title = one and ("Remove " .. one.name .. "?") or ("Remove " .. #ids .. " containers?"),
		body = body,
		confirm = "Remove",
		danger = true,
		options = {
			{
				key = "volumes",
				label = "Also remove anonymous volumes",
				hint = "Named volumes are kept either way",
				value = false,
			},
		},
		run = function(values)
			act.run(ids, "remove", { force = running > 0, volumes = values.volumes })
		end,
	})
end

function act.kill_containers()
	local rows = targets("containers")
	local ids, live = {}, {}
	for _, row in ipairs(rows) do
		if row.c.state == "running" or row.c.state == "paused" then
			ids[#ids + 1] = row.id
			live[#live + 1] = row.c
		end
	end
	if #ids == 0 then
		return
	end
	ask({
		title = #ids == 1 and ("Kill " .. live[1].name .. "?") or ("Kill " .. #ids .. " containers?"),
		body = "SIGKILL ends the main process at once, with no chance to clean up. Stop asks first.",
		confirm = "Kill",
		danger = true,
		run = function()
			act.run(ids, "kill")
		end,
	})
end

-- One verb for the row: what runs is stopped (where something of a project runs, it is stopped, and
-- what is stopped stays so), and where nothing runs, what is paused is resumed and the rest started.
function act.toggle()
	local rows = targets("containers")
	local stopping, starting, resuming = {}, {}, {}
	for _, row in ipairs(rows) do
		if row.c.state == "running" or row.c.state == "restarting" then
			stopping[#stopping + 1] = row.id
		elseif row.c.state == "paused" then
			resuming[#resuming + 1] = row.id
		else
			starting[#starting + 1] = row.id
		end
	end
	if #stopping > 0 then
		act.run(stopping, "stop")
		return
	end
	if #resuming > 0 then
		act.run(resuming, "unpause")
	end
	if #starting > 0 then
		act.run(starting, "start")
	end
end

function act.do_all(action)
	local rows = targets("containers")
	local ids = {}
	for _, row in ipairs(rows) do
		if
			action == "restart"
			or (action == "pause" and row.c.state == "running")
			or (action == "unpause" and row.c.state == "paused")
		then
			ids[#ids + 1] = row.id
		end
	end
	act.run(ids, action)
end

-- Pause what runs, resume what is paused.
function act.pause_toggle()
	local rows = targets("containers")
	local pausing, resuming = {}, {}
	for _, row in ipairs(rows) do
		if row.c.state == "paused" then
			resuming[#resuming + 1] = row.id
		elseif row.c.state == "running" then
			pausing[#pausing + 1] = row.id
		end
	end
	if #resuming > 0 then
		act.run(resuming, "unpause")
	end
	if #pausing > 0 then
		act.run(pausing, "pause")
	end
end

-- Pulls an image or a tag as a job.
function act.pull(reference)
	net.ask("pull", { reference = reference }, function(_, err)
		if err then
			toast.say("Could not pull " .. reference, { kind = "error", body = why(err) })
		end
	end)
end

-- What a clean-up can take away, in the order that frees most: the containers first, so that
-- their images and volumes are unused. `key` is what the program is asked for, `size` where on
-- the disk docker counts it.
local PRUNE = {
	{
		key = "containers",
		label = "Stopped containers",
		hint = "Every container that is not running",
		size = "containers",
	},
	{ key = "dangling_images", label = "Dangling images", hint = "Layers no tag points to any more" },
	{
		key = "unused_images",
		label = "Unused images",
		hint = "Every image no container was made from",
		size = "images",
	},
	{
		key = "volumes",
		label = "Unused volumes",
		hint = "Data no container mounts — gone for good",
		size = "volumes",
	},
	{ key = "networks", label = "Unused networks", hint = "Networks no container is on" },
	{
		key = "build_cache",
		label = "Build cache",
		hint = "What builds kept to go faster next time",
		size = "build_cache",
	},
}

-- Asks what to clean up (`preset`: what is ticked at first) and does it as a job.
function act.prune(preset)
	local on = {}
	for _, key in ipairs(preset or { "containers", "dangling_images", "networks", "build_cache" }) do
		on[key] = true
	end
	local options = {}
	for _, kind in ipairs(PRUNE) do
		options[#options + 1] =
			{ key = kind.key, label = kind.label, hint = kind.hint, size = kind.size, value = on[kind.key] == true }
	end
	ask({
		kind = "prune",
		title = "Clean up",
		body = "Remove what nothing uses. Running containers, and what they use, are never touched.",
		confirm = "Clean up",
		options = options,
		needs_system = true,
		run = function(values)
			local targets_ = {}
			for _, kind in ipairs(PRUNE) do
				if values[kind.key] then
					targets_[#targets_ + 1] = kind.key
				end
			end
			if #targets_ == 0 then
				return
			end
			net.ask("prune", { targets = targets_ }, function(_, err)
				if err then
					toast.say("Could not clean up", { kind = "error", body = why(err) })
				end
			end)
		end,
	})
end

-- Asks for the name of an image to pull: the host's field is where it is typed.
function act.ask_pull()
	ask({
		kind = "pull",
		title = "Pull an image",
		body = "A name with an optional tag; it runs in the background and the jobs show how far it got.",
		confirm = "Pull",
		field = true,
		reference = "",
		run = function(values)
			local text = values.reference or ""
			text = string.gsub(text, "^%s*(.-)%s*$", "%1")
			if text ~= "" then
				act.pull(text)
			end
		end,
	})
end

return {
	PRUNE = PRUNE,
	act = act,
	ask = ask,
}
