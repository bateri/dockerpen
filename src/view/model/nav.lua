local lib_kit = require("../lib/kit")
local lib_sizes = require("../lib/sizes")
local lib_virtual = require("../lib/virtual")
local model_act = require("./act")
local model_containers = require("./containers")
local model_disk = require("./disk")
local model_feed = require("./feed")
local model_lists = require("./lists")
local model_log = require("./log")
local model_net = require("./net")
local model_rows = require("./rows")
local model_state = require("./state")
local model_toast = require("./toast")
local b, ui = lib_kit.b, lib_kit.ui
local FILTERS, LOG_TAIL, SECTIONS, SIZE, TABS =
	lib_sizes.FILTERS, lib_sizes.LOG_TAIL, lib_sizes.SECTIONS, lib_sizes.SIZE, lib_sizes.TABS
local reveal = lib_virtual.reveal
local act, ask = model_act.act, model_act.ask
local is_up = model_containers.is_up
local DISK = model_disk.DISK
local on_stats = model_feed.on_stats
local load_detail, load_list, load_processes, load_system, signature =
	model_lists.load_detail,
	model_lists.load_list,
	model_lists.load_processes,
	model_lists.load_system,
	model_lists.signature
local L, log_clear, log_live, on_log = model_log.L, model_log.log_clear, model_log.log_live, model_log.on_log
local net, why = model_net.net, model_net.why
local SORTS, SORT_LABELS, folded, index_of, keep_cursor, row_tops, rows_of =
	model_rows.SORTS,
	model_rows.SORT_LABELS,
	model_rows.folded,
	model_rows.index_of,
	model_rows.keep_cursor,
	model_rows.row_tops,
	model_rows.rows_of
local S, bump = model_state.S, model_state.bump
local toast = model_toast.toast

-- ---- what the person does ---------------------------------------------------------------------------

local go = {}

-- Which part of the page has the host's text field: the filter of a list, the search of a log,
-- the answer to a question; nothing, where there is nothing to type into.
local function field_context(g)
	if S.palette then
		return "palette"
	end
	if S.dialog then
		return S.dialog.field and "dialog" or nil
	end
	if S.section == "containers" then
		if S.open and (S.tab == "logs" or S.tab == "env") and (S.focus == "detail" or not g.beside) then
			return S.tab == "logs" and "logs" or "env"
		end
		if S.open and not g.beside then
			return nil
		end
		return "list"
	elseif S.section == "system" then
		return nil
	end
	return "list"
end

-- What the page keeps of itself for the next view, sent to the program when it changed.
local last_kept = nil

local function persist()
	if not S.ready then
		return
	end
	local kept = {
		section = S.section,
		detail = S.open,
		tab = S.tab,
		filter = S.filter,
		group = S.group,
		sort = S.sort,
		folded = S.folded,
		folded_known = S.folded_known,
		cursor = S.cursor,
		timestamps = L.timestamps,
	}
	local text = b.json.encode(kept)
	if text ~= last_kept then
		last_kept = text
		net.ask("ui", { ui = kept }, function() end)
	end
end

local function restore(kept)
	if type(kept) ~= "table" then
		return
	end
	local function one_of(value, list, key)
		for _, item in ipairs(list) do
			if item[key or "id"] == value then
				return value
			end
		end
		return nil
	end
	S.section = one_of(kept.section, SECTIONS) or S.section
	S.tab = one_of(kept.tab, TABS) or S.tab
	S.filter = one_of(kept.filter, FILTERS) or S.filter
	for _, sort in ipairs(SORTS) do
		if kept.sort == sort then
			S.sort = sort
		end
	end
	if type(kept.group) == "boolean" then
		S.group = kept.group
	end
	if type(kept.folded) == "table" and kept.folded_known == true then
		S.folded, S.folded_known = kept.folded, true
	end
	if type(kept.cursor) == "table" then
		S.cursor = kept.cursor
	end
	if type(kept.detail) == "string" then
		S.open, S.focus = kept.detail, "detail"
	end
	if type(kept.timestamps) == "boolean" then
		L.timestamps = kept.timestamps
	end
end

-- Brings what is asked of the program in line with what is on show: the readings while the
-- containers are, the log while it is, the lists of the section that is.
local function sync()
	if not S.ready then
		return
	end
	local want_stats = S.section == "containers"
	if want_stats and not net.watching("stats") then
		net.watch("stats", "stats", nil, on_stats)
	elseif not want_stats and net.watching("stats") then
		net.unwatch("stats")
	end
	local open = S.open and S.by_id[S.open]
	-- A container that is opened and left again at once (the cursor going down the list) is not
	-- asked about.
	local settled = S.now - S.open_at >= 0.2
	local want_logs = open ~= nil and S.tab == "logs" and S.section == "containers"
	if want_logs then
		if settled then
			if L.id ~= open.id or not net.watching("logs") then
				log_clear(open.id, LOG_TAIL)
				L.resub_at = S.now
				net.watch("logs", "logs", { id = open.id, tail = L.tail }, on_log)
			elseif L.ended and log_live() and S.now - (L.resub_at or 0) > 3 then
				-- The container came back: the log goes on from the last line shown.
				L.ended, L.resub_at = nil, S.now
				net.watch("logs", "logs", { id = open.id, since = L.last }, on_log)
			end
		end
	elseif net.watching("logs") then
		net.unwatch("logs")
		log_clear(nil)
	end
	if not settled then
		open = nil
	end
	if open and S.section == "containers" then
		local slot = S.details[open.id]
		if slot == nil or (slot.signature ~= signature(open) and not slot.asking) then
			load_detail(open.id)
		end
		if S.tab == "processes" and open.state == "running" then
			local p = S.processes
			if p.id ~= open.id then
				p.titles, p.rows, p.id, p.at, p.error = nil, nil, open.id, nil, nil
			end
			if not p.asking and (p.at == nil or S.now - p.at >= 2) then
				load_processes(open.id)
			end
		end
	end
	for _, section in ipairs({ "images", "volumes", "networks" }) do
		if S.section == section and (S.lists[section] == nil and not S.problems[section] or S.stale[section]) then
			load_list(section)
		end
	end
	if (S.section == "system" or S.dialog and S.dialog.needs_system) and (S.system == nil or S.stale.system) then
		load_system()
	end
	if S.section == "images" and S.layer_open then
		local slot = S.layers[S.layer_open]
		if slot == nil then
			S.layers[S.layer_open] = { list = nil }
			local id = S.layer_open
			net.ask("image_layers", { id = id }, function(result, err)
				S.layers[id] = err and { error = why(err) } or { list = result.layers }
				bump()
			end)
		end
	end
end

-- Opens the detail of a container, and says where the keys go.
function go.open(id, focus)
	if S.open ~= id then
		S.open, S.open_at = id, S.now
		ui.scroll["detail.scroll"] = nil
		ui.scroll["detail.inspect"] = nil
		S.show_labels = false
	end
	if focus then
		S.focus = "detail"
	end
	bump()
end

function go.close()
	S.open, S.focus = nil, "list"
	bump()
end

function go.section(id)
	if S.section == id then
		return
	end
	S.section = id
	S.layer_open = nil
	S.focus = "list"
	ui.scroll.list = nil
	bump()
	keep_cursor(id)
	S.reveal = true
end

function go.tab(id)
	if S.tab ~= id then
		S.tab = id
		ui.scroll["detail.scroll"] = nil
		bump()
	end
	if S.open then
		S.focus = "detail"
	end
end

local function step(list, current, delta, key)
	for index, item in ipairs(list) do
		if (key and item[key] or item) == current then
			return list[(index - 1 + delta) % #list + 1]
		end
	end
	return list[1]
end

-- Moves the cursor of a list: by `how` rows, or to its `first` or `last`.
function go.move(section, how)
	local rows = rows_of(section)
	if #rows == 0 then
		return
	end
	local at = index_of(rows, S.cursor[section]) or 0
	local to
	if how == "first" then
		to = 1
	elseif how == "last" then
		to = #rows
	else
		to = math.max(1, math.min(#rows, at + how))
	end
	S.cursor[section] = rows[to].id
	reveal("list", to, #rows, SIZE.row, nil, row_tops(section))
	if section == "containers" and S.open and rows[to].kind == "container" then
		go.open(rows[to].id, false)
	end
	bump()
end

-- The row the cursor is on in the section that is shown.
local function cursor_row(section)
	local rows = rows_of(section)
	return rows[index_of(rows, S.cursor[section]) or 0]
end

-- The container the keys are about: the one the cursor is on.
local function current_container()
	local row = cursor_row("containers")
	if row and row.kind == "container" then
		return row.c
	end
	return S.open and S.by_id[S.open] or nil
end

function go.toggle_mark(section, id)
	S.marks[section] = S.marks[section] or {}
	S.marks[section][id] = (not S.marks[section][id]) or nil
	bump()
end

function go.mark_all(section, on)
	S.marks[section] = {}
	if on then
		for _, row in ipairs(rows_of(section)) do
			if row.kind ~= "group" then
				S.marks[section][row.id] = true
			end
		end
	end
	bump()
end

-- Frees what nothing uses of one part of the disk (the images, the containers, ...), after asking.
function go.free(index)
	local one = DISK[index]
	if one == nil then
		return
	end
	act.prune(one.targets)
end

-- Opens the layers of an image under its row (or, with no id, shuts them): they are asked for again.
function go.layers(id)
	S.layer_open = id
	if id then
		S.layers[id] = nil
		S.cursor.images = id
	end
	bump()
end

function go.fold(row, to)
	if row.kind ~= "group" then
		return
	end
	local now_folded = row.folded
	if to == nil then
		to = not now_folded
	end
	S.folded[row.key] = to
	bump()
end

local function ask_pull()
	act.ask_pull()
end

-- Opens the clean-up, with what the section on show is about ticked.
local function ask_clean(preset)
	if preset == nil then
		if S.section == "images" then
			preset = { "dangling_images", "unused_images" }
		elseif S.section == "volumes" then
			preset = { "volumes" }
		elseif S.section == "networks" then
			preset = { "networks" }
		end
	end
	act.prune(preset)
end

-- The menu of the row the cursor is on, at `at`.
local function row_menu(at)
	local section = S.section
	local entries, acts = {}, {}
	if at.kind == "sort" then
		for _, how in ipairs(SORTS) do
			entries[#entries + 1] = { title = (S.sort == how and "✓ " or "   ") .. SORT_LABELS[how], enabled = true }
			acts[#entries] = function()
				S.sort = how
				bump()
			end
		end
		S.menu = { acts = acts }
		return { at = { x = at.x, y = at.y }, entries = entries }
	end
	local function item(title, key, enabled, fn)
		entries[#entries + 1] = { title = title, key = key, enabled = enabled ~= false }
		acts[#entries] = fn
	end
	local function line()
		entries[#entries + 1] = "-"
	end
	if section == "containers" then
		local c = current_container()
		if c == nil then
			return nil
		end
		local up = is_up(c)
		item(up and "Stop" or "Start", "s", true, act.toggle)
		item("Restart", "r", true, function()
			act.do_all("restart")
		end)
		item(c.state == "paused" and "Resume" or "Pause", "p", up, act.pause_toggle)
		line()
		item("Open a shell in the terminal", "e", c.state == "running", function()
			act.terminal("shell", c)
		end)
		item("Follow its log in the terminal", "F", true, function()
			act.terminal("logs", c)
		end)
		line()
		item("Logs", "l", true, function()
			go.open(c.id, true)
			go.tab("logs")
		end)
		item("Inspect", "i", true, function()
			go.open(c.id, true)
			go.tab("inspect")
		end)
		line()
		item("Copy the id", "y", true, function()
			S.copy = c.id
		end)
		line()
		item("Kill…", "K", up, act.kill_containers)
		item("Remove…", "d", true, act.remove_containers)
	elseif section == "images" or section == "volumes" or section == "networks" then
		local row = cursor_row(section)
		if row == nil then
			return nil
		end
		if section == "images" then
			item(S.layer_open == row.id and "Hide layers" or "Show layers", "⏎", true, function()
				go.layers(S.layer_open ~= row.id and row.id or nil)
			end)
			line()
		end
		item("Remove…", "d", not (row.item.builtin == true), function()
			act.remove_listed(section)
		end)
	else
		return nil
	end
	S.menu = { acts = acts }
	return { at = { x = at.x, y = at.y }, entries = entries }
end

-- Updates an image: pulls what its first tag names again.
function go.update_image(id)
	for _, image in ipairs(S.lists.images or {}) do
		if image.id == id and image.tags[1] then
			act.pull(image.tags[1])
			toast.say("Pulling " .. image.tags[1], { kind = "info" })
			return
		end
	end
	toast.say("That image has no name to pull", { kind = "warning" })
end

return {
	ask_clean = ask_clean,
	ask_pull = ask_pull,
	current_container = current_container,
	cursor_row = cursor_row,
	field_context = field_context,
	go = go,
	persist = persist,
	restore = restore,
	row_menu = row_menu,
	step = step,
	sync = sync,
}
