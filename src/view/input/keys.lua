local lib_kit = require("../lib/kit")
local lib_sizes = require("../lib/sizes")
local lib_virtual = require("../lib/virtual")
local model_act = require("../model/act")
local model_dialog = require("../model/dialog")
local model_disk = require("../model/disk")
local model_log = require("../model/log")
local model_nav = require("../model/nav")
local model_palette = require("../model/palette")
local model_containers = require("../model/containers")
local model_net = require("../model/net")
local model_rows = require("../model/rows")
local model_state = require("../model/state")
local model_toast = require("../model/toast")
local b, ui = lib_kit.b, lib_kit.ui
local FILTERS, LOG_MOST, SECTIONS, SIZE, TABS =
	lib_sizes.FILTERS, lib_sizes.LOG_MOST, lib_sizes.SECTIONS, lib_sizes.SIZE, lib_sizes.TABS
local reveal, views = lib_virtual.reveal, lib_virtual.views
local act = model_act.act
local port_url = model_containers.port_url
local toast = model_toast.toast
local dialog = model_dialog.dialog
local palette = model_palette.palette
local DISK = model_disk.DISK
local L, log_clear, log_top, on_log = model_log.L, model_log.log_clear, model_log.log_top, model_log.on_log
local ask_clean, ask_pull, current_container, cursor_row, field_context, go, step =
	model_nav.ask_clean,
	model_nav.ask_pull,
	model_nav.current_container,
	model_nav.cursor_row,
	model_nav.field_context,
	model_nav.go,
	model_nav.step
local net = model_net.net
local index_of, keep_cursor, marked, row_tops, rows_of =
	model_rows.index_of, model_rows.keep_cursor, model_rows.marked, model_rows.row_tops, model_rows.rows_of
local S, bump, geometry = model_state.S, model_state.bump, model_state.geometry

-- ---- keys --------------------------------------------------------------------------------------------------

local keys = {}

local function reply_field()
	S.typing = true
	return { redraw = true, keyboard = "field" }
end

-- A question is open: its keys. Where the host's field has the keyboard it takes the letters; what
-- comes here is the keys it gives back (⏎, ⇥, ↓ and Esc leave it without a word).
function keys.dialog(key)
	local d = S.dialog
	if key == "escape" or key == "n" and d.kind ~= "pull" then
		dialog.close()
		return true
	elseif key == "enter" or key == "y" and d.kind ~= "pull" then
		if not dialog.confirm() and d.kind == "pull" then
			return reply_field()
		end
		return true
	elseif key == "up" or key == "k" then
		dialog.move(-1)
		return true
	elseif key == "down" or key == "j" or key == "tab" then
		dialog.move(1)
		return true
	elseif key == "space" or key == " " then
		dialog.toggle(d.cursor)
		return true
	elseif key == "/" and d.field then
		return reply_field()
	end
	return false
end

-- The palette is up: its keys. The host's field has the letters; what comes here is what it gives
-- back (⏎, ⇥, ↓ and Esc leave it without a word), and the arrows.
function keys.palette(key, mods)
	if key == "escape" then
		palette.close()
	elseif key == "enter" then
		if not palette.run() then
			return reply_field()
		end
	elseif key == "down" or (mods and mods.control and key == "n") then
		palette.move(1)
	elseif key == "up" or (mods and mods.control and key == "p") then
		palette.move(-1)
	elseif key == "page_down" then
		palette.move(6)
	elseif key == "page_up" then
		palette.move(-6)
	elseif key == "tab" then
		return true
	elseif #key == 1 and not (mods and (mods.control or mods.command)) then
		-- A letter after the field gave the keyboard back: the field has it again (this letter is
		-- not in it: the host's field takes keys itself, and this one went to the page).
		return reply_field()
	else
		return nil
	end
	return true
end

-- Scrolls a scrolling box by `dy`, in points.
local function scroll_by(id, dy)
	ui:set_scroll(id, math.max(ui:scroll_offset(id) + dy, 0))
end

-- Keys over a log: it scrolls, follows, is searched.
local function log_keys(key, mods)
	local view = views.log or 400
	local page = math.max(view - SIZE.line * 2, SIZE.line)
	if key == "right" and mods and mods.shift then
		L.hscroll += 16
	elseif key == "left" and mods and mods.shift then
		L.hscroll = math.max(L.hscroll - 16, 0)
	elseif key == "0" then
		L.hscroll = 0
	elseif key == "up" or key == "k" then
		L.follow = false
		scroll_by("log", -SIZE.line * 3)
	elseif key == "down" or key == "j" then
		scroll_by("log", SIZE.line * 3)
	elseif key == "page_up" then
		L.follow = false
		scroll_by("log", -page)
	elseif key == "page_down" then
		scroll_by("log", page)
	elseif key == "home" or key == "g" then
		L.follow = false
		ui:set_scroll("log", 0)
	elseif key == "end" or key == "G" or key == "F" and false then
		L.follow, L.new_since = true, 0
	elseif key == "t" then
		L.timestamps = not L.timestamps
	elseif key == "w" then
		L.wrap = not L.wrap
		L.tops = nil
		L.runs, L.run_count = {}, 0
	elseif key == "space" or key == " " then
		L.follow = not L.follow
		if L.follow then
			L.new_since = 0
		end
	elseif key == "n" or key == "N" then
		local total = #L.matches
		if total == 0 then
			return false
		end
		local at = L.match_at
		if key == "n" then
			at = at % total + 1
		else
			at = (at - 2) % total + 1
		end
		L.match_at, L.follow, L.pinned_match = at, false, true
		ui:set_scroll("log", math.max(log_top(L.matches[at]) - view / 2, 0))
	elseif key == "L" then
		if L.tail < LOG_MOST then
			L.tail = math.min(L.tail * 5, LOG_MOST)
			log_clear(L.id, L.tail)
			net.watch("logs", "logs", { id = L.id, tail = L.tail }, on_log)
		end
	else
		return nil
	end
	-- Following ends where the person scrolls up, and begins again at the bottom.
	return true
end

-- Keys that scroll what the detail shows, by tab.
local function detail_scroll_keys(key)
	local id = S.tab == "inspect" and "detail.inspect" or "detail.scroll"
	local view = views[id] or 400
	if key == "up" or key == "k" then
		scroll_by(id, -36)
	elseif key == "down" or key == "j" then
		scroll_by(id, 36)
	elseif key == "page_up" then
		scroll_by(id, -(view - 40))
	elseif key == "page_down" then
		scroll_by(id, view - 40)
	elseif key == "home" or key == "g" then
		ui:set_scroll(id, 0)
	elseif key == "end" or key == "G" then
		ui:set_scroll(id, 1e9)
	else
		return nil
	end
	return true
end

-- The keys that move the cursor of the list of containers.
local function list_navigation(key)
	local page = math.max(math.floor((views.list or 400) / SIZE.row) - 1, 1)
	local row = cursor_row("containers")
	if key == "down" or key == "j" then
		go.move("containers", 1)
	elseif key == "up" or key == "k" then
		go.move("containers", -1)
	elseif key == "page_down" then
		go.move("containers", page)
	elseif key == "page_up" then
		go.move("containers", -page)
	elseif key == "home" or key == "g" then
		go.move("containers", "first")
	elseif key == "end" or key == "G" then
		go.move("containers", "last")
	elseif key == "enter" or key == "right" then
		if row and row.kind == "group" then
			go.fold(row, key == "right" and false or nil)
		elseif row then
			go.open(row.id, true)
		end
	elseif key == "left" then
		local rows = rows_of("containers")
		if row and row.kind == "group" then
			go.fold(row, true)
		elseif S.open then
			go.close()
		elseif row and row.kind == "container" and row.c.project and S.group then
			-- To the head of its project.
			S.cursor.containers = "group:" .. row.c.project
			reveal("list", index_of(rows, S.cursor.containers) or 1, #rows, SIZE.row, nil, row_tops("containers"))
			bump()
		end
	else
		return nil
	end
	return true
end

-- What is done to the containers, wherever the keys are.
local function container_actions(key, g)
	local c = current_container()
	local row = cursor_row("containers")
	if key == "space" or key == " " then
		if row and row.kind == "container" then
			go.toggle_mark("containers", row.id)
		end
	elseif key == "a" then
		go.mark_all("containers", true)
	elseif key == "A" then
		go.mark_all("containers", false)
	elseif key == "s" then
		act.toggle()
	elseif key == "r" then
		act.do_all("restart")
	elseif key == "p" then
		act.pause_toggle()
	elseif key == "e" then
		if c then
			act.terminal("shell", c)
		end
	elseif key == "F" then
		if c then
			act.terminal("logs", c)
		end
	elseif key == "l" or key == "i" then
		if c then
			go.open(c.id, true)
			go.tab(key == "l" and "logs" or "inspect")
		end
	elseif key == "y" then
		if c then
			S.copy = c.id
		end
	elseif key == "K" then
		act.kill_containers()
	elseif key == "d" then
		act.remove_containers()
	elseif key == "f" then
		S.filter = step(FILTERS, S.filter, 1, "id").id
		bump()
		keep_cursor("containers")
	elseif key == "P" then
		S.group = not S.group
		bump()
		keep_cursor("containers")
	elseif key == "o" then
		-- A page cannot open a link: the address is copied, for the browser.
		local url = c and port_url(c)
		if url then
			S.copy = url
			toast.say(
				"Copied " .. url,
				{ kind = "info", body = "A page cannot open a link in a browser: paste it there." }
			)
		elseif c then
			toast.say(c.name .. " publishes no port", { kind = "info" })
		end
	elseif key == "<" then
		S.detail_width = math.min((S.detail_width or 0) + 40, 2000)
		bump()
	elseif key == ">" then
		S.detail_width = math.max((S.detail_width or 460) - 40, 340)
		bump()
	elseif key == "." then
		local at = { x = 220, y = 160 }
		local id = c and ("row:" .. c.id)
		local rect = id and b.layout.bounds(id)
		if rect then
			at = { x = rect.x + 40, y = rect.y + rect.h }
		end
		S.pending_menu = at
	else
		return nil
	end
	return true
end

-- Keys of the containers.
function keys.containers(key, mods, g)
	local in_detail = S.open ~= nil and (S.focus == "detail" or not g.beside)
	if S.open then
		if key == "[" then
			go.tab(step(TABS, S.tab, -1, "id").id)
			return true
		elseif key == "]" then
			go.tab(step(TABS, S.tab, 1, "id").id)
			return true
		elseif key == "escape" then
			go.close()
			return true
		elseif key == "tab" then
			S.focus = S.focus == "detail" and "list" or "detail"
			bump()
			return true
		end
	end
	if in_detail then
		local done
		if S.tab == "logs" then
			done = log_keys(key, mods)
		else
			done = detail_scroll_keys(key)
		end
		if done ~= nil then
			return done
		end
		if key == "left" then
			if g.beside then
				S.focus = "list"
				bump()
			else
				go.close()
			end
			return true
		elseif key == "v" and S.tab == "env" then
			S.show_secrets = not S.show_secrets
			return true
		elseif key == "v" and S.tab == "overview" then
			S.show_labels = not S.show_labels
			return true
		end
	elseif list_navigation(key) then
		return true
	end
	return container_actions(key, g)
end

-- Keys of the lists of images, volumes and networks, and of the activity.
function keys.plain(key, mods, g)
	local section = S.section
	local row = cursor_row(section)
	local page = math.max(math.floor((views.list or 400) / SIZE.row) - 1, 1)
	if key == "down" or key == "j" then
		go.move(section, 1)
	elseif key == "up" or key == "k" then
		go.move(section, -1)
	elseif key == "page_down" then
		go.move(section, page)
	elseif key == "page_up" then
		go.move(section, -page)
	elseif key == "home" or key == "g" then
		go.move(section, "first")
	elseif key == "end" or key == "G" then
		go.move(section, "last")
	elseif key == "space" or key == " " then
		if row then
			go.toggle_mark(section, row.id)
		end
	elseif key == "a" then
		go.mark_all(section, true)
	elseif key == "A" then
		go.mark_all(section, false)
	elseif key == "d" and section ~= "activity" then
		act.remove_listed(section)
	elseif key == "p" and section == "images" then
		ask_pull()
	elseif key == "u" and section == "images" then
		if row then
			go.update_image(row.id)
		end
	elseif key == "y" and row and section ~= "activity" then
		S.copy = section == "images" and (row.item.tags[1] or row.id) or (row.item.name or row.id)
		toast.say("Copied the name", { kind = "success" })
	elseif key == "left" and section == "images" then
		go.layers(nil)
	elseif key == "escape" then
		if #marked(section) > 0 then
			go.mark_all(section, false)
		elseif S.layer_open then
			go.layers(nil)
		elseif S.query ~= "" then
			return nil
		else
			return nil
		end
	elseif key == "enter" or key == "right" then
		if section == "images" and row then
			go.layers(key == "enter" and S.layer_open == row.id and nil or row.id)
		elseif section == "activity" and row and row.item.type == "container" and S.by_id[row.item.id] then
			go.section("containers")
			S.cursor.containers = row.item.id
			go.open(row.item.id, true)
		end
	elseif key == "." then
		local rect = row and b.layout.bounds("row:" .. row.id)
		S.pending_menu = rect and { x = rect.x + 40, y = rect.y + rect.h } or { x = 220, y = 160 }
	else
		return nil
	end
	return true
end

function keys.system(key)
	if key == "c" then
		ask_clean()
	elseif key == "up" or key == "k" then
		S.system_pick = math.max(S.system_pick - 1, 1)
	elseif key == "down" or key == "j" then
		S.system_pick = math.min(S.system_pick + 1, #DISK)
	elseif key == "enter" then
		go.free(S.system_pick)
	elseif key == "page_up" then
		scroll_by("system.scroll", -300)
	elseif key == "page_down" then
		scroll_by("system.scroll", 300)
	elseif key == "home" then
		ui:set_scroll("system.scroll", 0)
	elseif key == "end" then
		ui:set_scroll("system.scroll", 1e9)
	else
		return nil
	end
	return true
end

-- A key, as the page reads it. Gives what the page replies: true when something changed.
function keys.press(key, mods)
	local g = geometry()
	if S.dialog then
		return keys.dialog(key)
	end
	if S.palette then
		return keys.palette(key, mods)
	end
	if S.help then
		if key == "escape" or key == "?" or key == "q" then
			S.help = false
			bump()
		elseif key == "up" or key == "k" then
			scroll_by("help.scroll", -40)
		elseif key == "down" or key == "j" then
			scroll_by("help.scroll", 40)
		end
		return true
	end
	if mods and mods.control and not mods.alt and not mods.command and key == "k" then
		palette.open()
		return true
	end
	if mods and (mods.control or mods.alt or mods.command) then
		return nil
	end
	if key == ":" then
		palette.open()
		return true
	end
	if key == "R" then
		for _, section in ipairs({ "images", "volumes", "networks", "system" }) do
			S.stale[section] = true
		end
		S.pending_reload = S.now
		bump()
		return true
	end
	if key == "?" then
		S.help = true
		return true
	end
	if key == "z" then
		-- What the newest toast that offers a way back offers (a stop can be undone).
		for index = #S.toasts, 1, -1 do
			local item = S.toasts[index]
			if item.action and item.action.run then
				table.remove(S.toasts, index)
				item.action.run()
				bump()
				return true
			end
		end
		return false
	end
	for _, section in ipairs(SECTIONS) do
		if key == section.key then
			go.section(section.id)
			return true
		end
	end
	if key == "/" and field_context(g) then
		return reply_field()
	end
	if S.section == "containers" then
		return keys.containers(key, mods, g)
	elseif S.section == "system" then
		return keys.system(key)
	end
	return keys.plain(key, mods, g)
end

return {
	keys = keys,
	log_keys = log_keys,
	reply_field = reply_field,
	scroll_by = scroll_by,
}
