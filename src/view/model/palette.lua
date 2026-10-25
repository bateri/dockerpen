-- The command palette: every command, container, image, volume and network, by name. The host gives
-- the page one text field, and while the palette is up that field is the palette's: what is typed
-- in it is what is looked for (`S.query`, as for any list).

local lib_fmt = require("../lib/fmt")
local lib_sizes = require("../lib/sizes")
local model_act = require("./act")
local model_nav = require("./nav")
local model_rows = require("./rows")
local model_state = require("./state")
local fmt = lib_fmt.fmt
local FILTERS, SECTIONS = lib_sizes.FILTERS, lib_sizes.SECTIONS
local act = model_act.act
local ask_clean, ask_pull, go, step = model_nav.ask_clean, model_nav.ask_pull, model_nav.go, model_nav.step
local targets = model_rows.targets
local S, bump = model_state.S, model_state.bump

local palette = {}

-- Whether `text` has the characters of `query` in order, and where: the score is higher for a
-- match that is whole, that is at the start of a word, and that is in a run. Returns nil where it
-- is no match.
local function fuzzy(query, text)
	local q = string.lower((string.gsub(query, "^%s*(.-)%s*$", "%1")))
	if q == "" then
		return { score = 0, positions = {} }
	end
	local t = string.lower(text)
	local chars = {}
	for _, code in utf8.codes(t) do
		chars[#chars + 1] = utf8.char(code)
	end
	local qs = {}
	for _, code in utf8.codes(q) do
		qs[#qs + 1] = utf8.char(code)
	end
	local function boundary(at)
		if at <= 1 then
			return true
		end
		return string.find(chars[at - 1], "^[%s%-_./:]$") ~= nil
	end
	-- The whole query somewhere in the text.
	for from = 1, #chars - #qs + 1 do
		local whole = true
		for offset = 1, #qs do
			if chars[from + offset - 1] ~= qs[offset] then
				whole = false
				break
			end
		end
		if whole then
			local positions = {}
			for offset = 1, #qs do
				positions[offset] = from + offset - 2
			end
			local start = boundary(from) and 30 or 0
			return { score = 100 + start - (from - 1) * 0.5 - #chars * 0.05, positions = positions }
		end
	end
	local positions, score, run, from = {}, 0, 0, 1
	for _, char in ipairs(qs) do
		if char ~= " " then
			local at = nil
			for index = from, #chars do
				if chars[index] == char then
					at = index
					break
				end
			end
			if at == nil then
				return nil
			end
			local last = positions[#positions]
			run = (last ~= nil and last == at - 2) and run + 1 or 0
			score += 1 + run * 2 + (boundary(at) and 4 or 0) - (at - from) * 0.1
			positions[#positions + 1] = at - 1
			from = at + 1
		end
	end
	-- Characters scattered over the whole text are a coincidence, not a match.
	local span = positions[#positions] - positions[1] + 1
	if span > math.max(#positions * 3, #positions + 4) then
		return nil
	end
	return { score = score - #chars * 0.05, positions = positions }
end

-- What can be done to the containers chosen, one entry for each (the title says whom).
local function container_commands()
	local out = {}
	if S.section ~= "containers" then
		return out
	end
	local rows = targets("containers")
	if #rows == 0 then
		return out
	end
	local one = #rows == 1 and rows[1].c or nil
	local who = one and one.name or (#rows .. " containers")
	local up, stopped, paused = false, false, false
	for _, row in ipairs(rows) do
		local state = row.c.state
		up = up or state == "running" or state == "restarting"
		paused = paused or state == "paused"
		stopped = stopped or (state ~= "running" and state ~= "restarting" and state ~= "paused")
	end
	local function add(entry)
		entry.group = "Container"
		out[#out + 1] = entry
	end
	if up then
		add({ id = "stop", title = "Stop " .. who, icon = "square", keys = "s", run = act.toggle })
	end
	if stopped or paused then
		add({ id = "start", title = "Start " .. who, icon = "play", keys = "s", run = act.toggle })
	end
	add({
		id = "restart",
		title = "Restart " .. who,
		icon = "rotate-cw",
		keys = "r",
		run = function()
			act.do_all("restart")
		end,
	})
	if up or paused then
		add({
			id = "pause",
			title = (paused and "Resume " or "Pause ") .. who,
			icon = "pause",
			keys = "p",
			run = act.pause_toggle,
		})
	end
	if one then
		add({
			id = "shell",
			title = "Shell in " .. one.name,
			icon = "square-terminal",
			keys = "e",
			detail = "the pane becomes the terminal",
			run = function()
				act.terminal("shell", one)
			end,
		})
		add({
			id = "logs",
			title = "Logs of " .. one.name,
			icon = "scroll-text",
			keys = "l",
			run = function()
				go.open(one.id, true)
				go.tab("logs")
			end,
		})
		add({
			id = "follow",
			title = "Follow " .. one.name .. "'s logs in the terminal",
			icon = "arrow-right-left",
			keys = "F",
			run = function()
				act.terminal("logs", one)
			end,
		})
		add({
			id = "inspect",
			title = "Inspect " .. one.name,
			icon = "eye",
			keys = "i",
			run = function()
				go.open(one.id, true)
				go.tab("inspect")
			end,
		})
		add({
			id = "copy-id",
			title = "Copy " .. one.name .. "'s id",
			icon = "copy",
			keys = "y",
			run = function()
				S.copy = one.id
			end,
		})
	end
	add({ id = "kill", title = "Kill " .. who, icon = "skull", keys = "K", tone = "error", run = act.kill_containers })
	add({
		id = "remove",
		title = "Remove " .. who,
		icon = "trash-2",
		keys = "d",
		tone = "error",
		run = act.remove_containers,
	})
	return out
end

local function global_commands()
	local out = {}
	local function add(entry)
		out[#out + 1] = entry
	end
	for _, section in ipairs(SECTIONS) do
		add({
			id = "go-" .. section.id,
			title = "Go to " .. section.label,
			group = "Go to",
			icon = section.icon,
			keys = section.key,
			run = function()
				go.section(section.id)
			end,
		})
	end
	add({
		id = "group",
		title = S.group and "Stop grouping by compose project" or "Group by compose project",
		group = "View",
		icon = "folder-tree",
		keys = "P",
		run = function()
			S.group = not S.group
			bump()
		end,
	})
	local words = {
		all = "all containers",
		running = "running containers",
		stopped = "stopped containers",
		issues = "containers with issues",
	}
	for _, f in ipairs(FILTERS) do
		add({
			id = "filter-" .. f.id,
			title = "Show " .. words[f.id],
			group = "View",
			icon = "list-filter",
			keys = "f",
			run = function()
				go.section("containers")
				S.filter = f.id
				bump()
			end,
		})
	end
	add({ id = "pull", title = "Pull an image…", group = "Docker", icon = "download", run = ask_pull })
	add({
		id = "prune",
		title = "Clean up…",
		group = "Docker",
		icon = "sparkles",
		detail = "remove what nothing uses",
		run = function()
			ask_clean({ "containers", "dangling_images", "networks", "build_cache" })
		end,
	})
	add({
		id = "refresh",
		title = "Refresh",
		group = "Docker",
		icon = "refresh-cw",
		keys = "R",
		run = function()
			for _, section in ipairs({ "images", "volumes", "networks", "system" }) do
				S.stale[section] = true
			end
			S.pending_reload = S.now
			bump()
		end,
	})
	add({
		id = "help",
		title = "Keyboard shortcuts",
		group = "Help",
		icon = "keyboard",
		keys = "?",
		run = function()
			S.help = true
			bump()
		end,
	})
	return out
end

-- Everything the palette can run or go to, made once as it opens: what can be done to the chosen
-- containers, then the rest of the commands, then the things themselves.
local function entries()
	local out = {}
	for _, entry in ipairs(container_commands()) do
		entry.key = "cmd:" .. entry.id
		entry.command = true
		out[#out + 1] = entry
	end
	for _, entry in ipairs(global_commands()) do
		entry.key = "cmd:" .. entry.id
		entry.command = true
		out[#out + 1] = entry
	end
	for _, c in ipairs(S.containers) do
		out[#out + 1] = {
			key = "container:" .. c.id,
			title = c.name,
			group = "Containers",
			icon = "boxes",
			detail = c.state .. " · " .. fmt.image_name(c.image),
			run = function()
				go.section("containers")
				S.cursor.containers = c.id
				go.open(c.id, true)
				S.reveal = true
			end,
		}
	end
	for _, image in ipairs(S.lists.images or {}) do
		local name = image.tags[1] and fmt.image_name(image.tags[1]) or string.sub(image.id, 1, 12)
		out[#out + 1] = {
			key = "image:" .. image.id,
			title = name,
			group = "Images",
			icon = "layers",
			detail = #image.containers > 0 and ("used by " .. #image.containers) or "unused",
			run = function()
				go.section("images")
				S.cursor.images = image.id
				S.reveal = true
			end,
		}
	end
	for _, volume in ipairs(S.lists.volumes or {}) do
		out[#out + 1] = {
			key = "volume:" .. volume.name,
			title = volume.anonymous and string.sub(volume.name, 1, 12) or volume.name,
			group = "Volumes",
			icon = "hard-drive",
			detail = #volume.containers > 0 and ("used by " .. table.concat(volume.containers, ", ")) or "unused",
			run = function()
				go.section("volumes")
				S.cursor.volumes = volume.name
				S.reveal = true
			end,
		}
	end
	for _, network in ipairs(S.lists.networks or {}) do
		out[#out + 1] = {
			key = "network:" .. network.id,
			title = network.name,
			group = "Networks",
			icon = "network",
			detail = network.driver,
			run = function()
				go.section("networks")
				S.cursor.networks = network.id
				S.reveal = true
			end,
		}
	end
	return out
end

-- What is shown for what is typed: with nothing typed the commands; else the best matches (at most
-- sixty), a group at a time, the group with the best match first. `{ entry =, positions = }`.
function palette.shown()
	local p = S.palette
	if p == nil then
		return {}
	end
	if p.entries == nil then
		p.entries = entries()
	end
	local query = S.query or ""
	if p.shown and p.shown_for == query and p.shown_rev == S.rev then
		return p.shown
	end
	local list = {}
	if string.gsub(query, "%s", "") == "" then
		for _, entry in ipairs(p.entries) do
			if entry.command then
				list[#list + 1] = { entry = entry, positions = {} }
			end
		end
	else
		local matched = {}
		for _, entry in ipairs(p.entries) do
			local m = fuzzy(query, entry.title)
			if m then
				matched[#matched + 1] = { entry = entry, score = m.score, positions = m.positions }
			end
		end
		table.sort(matched, function(x, y)
			return x.score > y.score
		end)
		while #matched > 60 do
			matched[#matched] = nil
		end
		local seen, groups = {}, {}
		for _, m in ipairs(matched) do
			if not seen[m.entry.group] then
				seen[m.entry.group] = true
				groups[#groups + 1] = m.entry.group
			end
		end
		for _, group in ipairs(groups) do
			for _, m in ipairs(matched) do
				if m.entry.group == group then
					list[#list + 1] = { entry = m.entry, positions = m.positions }
				end
			end
		end
	end
	p.shown, p.shown_for, p.shown_rev = list, query, S.rev
	return list
end

function palette.open()
	S.palette = { active = 1, opened = S.now }
	S.want_field = true
	bump()
end

function palette.close()
	S.palette = nil
	S.typing = false
	bump()
end

function palette.move(delta)
	local p = S.palette
	local count = #palette.shown()
	if p == nil or count == 0 then
		return
	end
	p.active = math.max(1, math.min(count, p.active + delta))
	p.reveal = true
	bump()
end

-- Runs the entry `index` (the active one where there is none said) and puts the palette away.
function palette.run(index)
	local p = S.palette
	local item = palette.shown()[index or (p and p.active) or 0]
	if item == nil then
		return false
	end
	palette.close()
	item.entry.run()
	bump()
	return true
end

return {
	fuzzy = fuzzy,
	palette = palette,
}
