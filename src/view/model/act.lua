local lib_fmt = require("../lib/fmt")
local model_containers = require("./containers")
local model_net = require("./net")
local model_rows = require("./rows")
local model_state = require("./state")
local model_toast = require("./toast")
local fmt = lib_fmt.fmt
local is_up, name_of = model_containers.is_up, model_containers.name_of
local net, why = model_net.net, model_net.why
local image_title, targets = model_rows.image_title, model_rows.targets
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

local function names_of(ids)
	if #ids == 1 then
		return name_of(ids[1])
	end
	return fmt.count(#ids, "container")
end

-- Does `action` to the containers `ids`, and says how it went. A stop can be taken back from the
-- toast that says it happened.
function act.run(ids, action, options)
	options = options or {}
	if #ids == 0 then
		return
	end
	for _, id in ipairs(ids) do
		S.busy[id] = PARTICIPLE[action]
	end
	bump()
	local params = { ids = ids, action = action, force = options.force, volumes = options.volumes }
	net.ask("act", params, function(result, err)
		for _, id in ipairs(ids) do
			S.busy[id] = nil
		end
		bump()
		if err then
			toast.say(why(err), { kind = "error", seconds = 10 })
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
		if #done > 0 then
			local text = PAST[action] .. " " .. names_of(done)
			local offer = nil
			if action == "stop" then
				offer = {
					label = "Undo",
					run = function()
						act.run(done, "start")
					end,
				}
			end
			toast.say(text, { kind = "success", action = offer })
		end
		for _, outcome in ipairs(failed) do
			toast.say(outcome.name .. ": " .. (outcome.error or "it failed"), { kind = "error", seconds = 10 })
		end
		if action == "remove" then
			for _, id in ipairs(done) do
				S.marks.containers[id] = nil
			end
		end
	end)
end

-- The pane to a shell in a container, or to its log as it comes.
function act.terminal(kind, c)
	if not S.handoff then
		toast.say("This terminal cannot hand its pane to a command and back.", { kind = "warning" })
		return
	end
	if kind == "shell" and c.state ~= "running" then
		toast.say(c.name .. " is not running: start it first", { kind = "warning" })
		return
	end
	net.ask("handoff", { kind = kind, id = c.id, name = c.name }, function(result, err)
		if err then
			toast.say(why(err), { kind = "error" })
		elseif result.state == "unavailable" then
			toast.say("This terminal cannot hand its pane to a command and back.", { kind = "warning" })
		elseif result.state == "busy" then
			toast.say("The pane is going to a command already.", { kind = "warning" })
		end
	end)
end

-- Asks first: a question over everything, answered with a key or a button. `options.danger` makes
-- the answer that does nothing the one the keyboard is on.
local function ask(title, lines, confirm, run, options)
	options = options or {}
	S.dialog = {
		title = title,
		lines = lines,
		confirm = confirm,
		run = run,
		danger = options.danger,
		choice = options.danger and "cancel" or "confirm",
		field = options.field,
	}
	bump()
end

local function remove_things(method, key, ids, label, force)
	net.ask(method, { [key] = ids, force = force }, function(result, err)
		if err then
			toast.say(why(err), { kind = "error", seconds = 10 })
			return
		end
		local done, failed = 0, {}
		for _, outcome in ipairs(result.outcomes) do
			if outcome.ok then
				done += 1
			else
				failed[#failed + 1] = outcome
			end
		end
		if done > 0 then
			toast.say("Removed " .. fmt.count(done, label), { kind = "success" })
		end
		for _, outcome in ipairs(failed) do
			toast.say(outcome.name .. ": " .. (outcome.error or "it failed"), { kind = "error", seconds = 10 })
		end
		local section = method == "image_remove" and "images" or (method == "volume_remove" and "volumes" or "networks")
		S.marks[section] = {}
		S.stale[section] = true
		S.pending_reload = S.now + 0.1
	end)
end

-- Asks, then removes, what the cursor or the marks name in a list of images, volumes or networks.
function act.remove_listed(section)
	local rows = targets(section)
	if #rows == 0 then
		return
	end
	local ids, names = {}, {}
	for _, row in ipairs(rows) do
		names[#names + 1] = section == "images" and image_title(row.item) or row.item.name
		ids[#ids + 1] = section == "images" and row.id or (section == "volumes" and row.item.name or row.id)
	end
	if section == "networks" then
		for _, row in ipairs(rows) do
			if row.item.builtin then
				toast.say(row.item.name .. " is one of Docker's own: it cannot be removed", { kind = "warning" })
				return
			end
		end
	end
	local noun = section == "images" and "image" or (section == "volumes" and "volume" or "network")
	local lines = {}
	for index, name in ipairs(names) do
		if index <= 6 then
			lines[#lines + 1] = name
		end
	end
	if #names > 6 then
		lines[#lines + 1] = "and " .. (#names - 6) .. " more"
	end
	local note = nil
	if section == "images" then
		local used = 0
		for _, row in ipairs(rows) do
			used += #row.item.containers
		end
		if used > 0 then
			note = "Containers were made from "
				.. (#rows == 1 and "it" or "some of these")
				.. ": docker will say no unless they are removed first."
		end
	elseif section == "volumes" then
		note = "What is in " .. (#rows == 1 and "it" or "them") .. " is gone for good."
	end
	local method = section == "images" and "image_remove"
		or (section == "volumes" and "volume_remove" or "network_remove")
	local key = section == "images" and "ids" or (section == "volumes" and "names" or "ids")
	ask("Remove " .. fmt.count(#ids, noun) .. "?", { names = lines, note = note }, "Remove", function()
		remove_things(method, key, ids, noun, false)
	end, { danger = true })
end

-- Asks, then removes, the containers the cursor or the marks name.
function act.remove_containers()
	local rows = targets("containers")
	local ids, lines, running = {}, {}, 0
	for _, row in ipairs(rows) do
		ids[#ids + 1] = row.id
		if #lines < 6 then
			lines[#lines + 1] = row.c.name
		end
		if is_up(row.c) then
			running += 1
		end
	end
	if #ids == 0 then
		return
	end
	if #ids > 6 then
		lines[#lines + 1] = "and " .. (#ids - 6) .. " more"
	end
	local note = "Its logs and what it wrote to its own disk go with it."
	if #ids > 1 then
		note = "Their logs and what they wrote to their own disks go with them."
	end
	local force = running > 0
	if force then
		note = (
			running == 1 and "It is running and will be stopped first. "
			or (running .. " are running and will be stopped first. ")
		) .. note
	end
	ask("Remove " .. fmt.count(#ids, "container") .. "?", { names = lines, note = note }, "Remove", function()
		act.run(ids, "remove", { force = force })
	end, { danger = true })
end

function act.kill_containers()
	local rows = targets("containers")
	local ids, lines = {}, {}
	for _, row in ipairs(rows) do
		if is_up(row.c) then
			ids[#ids + 1] = row.id
			if #lines < 6 then
				lines[#lines + 1] = row.c.name
			end
		end
	end
	if #ids == 0 then
		toast.say("Nothing that runs is chosen", { kind = "warning" })
		return
	end
	ask(
		"Kill " .. fmt.count(#ids, "container") .. "?",
		{
			names = lines,
			note = "They are sent SIGKILL: no time to finish what they are doing.",
		},
		"Kill",
		function()
			act.run(ids, "kill")
		end,
		{ danger = true }
	)
end

-- Stops what runs and starts what does not, of the containers chosen: one verb for the row.
function act.toggle()
	local rows = targets("containers")
	local stopping, starting = {}, {}
	for _, row in ipairs(rows) do
		if is_up(row.c) then
			stopping[#stopping + 1] = row.id
		else
			starting[#starting + 1] = row.id
		end
	end
	if #stopping > 0 and #starting == 0 then
		act.run(stopping, "stop")
	elseif #starting > 0 and #stopping == 0 then
		act.run(starting, "start")
	elseif #stopping > 0 then
		act.run(stopping, "stop")
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
	else
		act.run(pausing, "pause")
	end
end

-- Pulls an image or a tag as a job.
function act.pull(reference)
	net.ask("pull", { reference = reference }, function(_, err)
		if err then
			toast.say(why(err), { kind = "error", seconds = 10 })
		end
	end)
end

-- Asks for the clean-up of what nothing uses, saying what it will free first.
function act.prune(targets_, titles, freed)
	local lines = {}
	for _, title in ipairs(titles) do
		lines[#lines + 1] = title
	end
	local note = freed and freed > 0 and ("About " .. fmt.disk(freed) .. " is freed.") or "There is nothing to free."
	ask("Clean up what nothing uses?", { names = lines, note = note }, "Clean up", function()
		net.ask("prune", { targets = targets_ }, function(_, err)
			if err then
				toast.say(why(err), { kind = "error", seconds = 10 })
			end
		end)
	end, { danger = true })
end

return {
	act = act,
	ask = ask,
}
