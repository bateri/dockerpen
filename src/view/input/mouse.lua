local lib_kit = require("../lib/kit")
local input_keys = require("./keys")
local model_act = require("../model/act")
local model_containers = require("../model/containers")
local model_dialog = require("../model/dialog")
local model_disk = require("../model/disk")
local model_log = require("../model/log")
local model_nav = require("../model/nav")
local model_palette = require("../model/palette")
local model_rows = require("../model/rows")
local model_state = require("../model/state")
local b, ui = lib_kit.b, lib_kit.ui
local log_keys = input_keys.log_keys
local act = model_act.act
local is_up = model_containers.is_up
local dialog = model_dialog.dialog
local palette = model_palette.palette
local DISK = model_disk.DISK
local L, log_show_match, log_step_match, log_toggle_wrap, log_wipe =
	model_log.L, model_log.log_show_match, model_log.log_step_match, model_log.log_toggle_wrap, model_log.log_wipe
local ansi = require("../lib/ansi").ansi
local fmt = require("../lib/fmt").fmt
local toast = require("../model/toast").toast
local ask_clean, ask_pull, cursor_row, go, step =
	model_nav.ask_clean, model_nav.ask_pull, model_nav.cursor_row, model_nav.go, model_nav.step
local SORTS, keep_cursor, targets = model_rows.SORTS, model_rows.keep_cursor, model_rows.targets
local S, bump = model_state.S, model_state.bump

-- ---- the pointer ---------------------------------------------------------------------------------------

local mouse = {}

-- A click on the thing named `id` (a release over where the press began).
function mouse.click(id, mods)
	local kind, rest = string.match(id, "^([%w%.]+):(.*)$")
	mods = mods or {}
	if kind == "sec" then
		go.section(rest)
	elseif kind == "row" then
		local section = S.section
		S.cursor[section] = rest
		bump()
		if section == "containers" then
			local row = cursor_row("containers")
			if row and row.kind == "group" then
				go.fold(row)
			elseif row and (mods.shift or mods.command or mods.control) then
				go.toggle_mark("containers", row.id)
			elseif row then
				go.open(row.id, true)
			end
		elseif section == "images" then
			if mods.shift or mods.command or mods.control then
				go.toggle_mark(section, rest)
			end
		elseif section == "activity" then
			local row = cursor_row("activity")
			if row and row.item.type == "container" and S.by_id[row.item.id] then
				go.section("containers")
				S.cursor.containers = row.item.id
				go.open(row.item.id, true)
			end
		elseif mods.shift or mods.command or mods.control then
			go.toggle_mark(section, rest)
		end
	elseif kind == "mark" then
		go.toggle_mark(S.section, rest)
	elseif kind == "ra" then
		-- A verb on the row of a container.
		local verb, target = string.match(rest, "^(%a+):(.*)$")
		local c = S.by_id[target]
		if c == nil then
			return
		end
		S.cursor.containers = c.id
		if verb == "toggle" then
			act.run(
				{ c.id },
				(c.state == "running" or c.state == "restarting") and "stop"
					or (c.state == "paused" and "unpause" or "start")
			)
		elseif verb == "restart" then
			act.run({ c.id }, "restart")
		elseif verb == "logs" then
			go.open(c.id, true)
			go.tab("logs")
		elseif verb == "shell" then
			act.terminal("shell", c)
		elseif verb == "more" then
			local rect = b.layout.bounds(id)
			S.pending_menu = rect and { x = rect.x + rect.w - 216, y = rect.y + rect.h + 4 } or { x = 220, y = 160 }
		end
		bump()
	elseif kind == "ga" then
		-- A verb on the head of a project: for all of its containers shown.
		local verb, key = string.match(rest, "^(%a+):(.*)$")
		S.cursor.containers = "group:" .. key
		bump()
		local members = targets("containers")
		local ids, running = {}, false
		for _, row in ipairs(members) do
			running = running or is_up(row.c)
		end
		if verb == "restart" then
			for _, row in ipairs(members) do
				ids[#ids + 1] = row.id
			end
			act.run(ids, "restart")
		else
			for _, row in ipairs(members) do
				if running == is_up(row.c) then
					ids[#ids + 1] = row.id
				end
			end
			act.run(ids, running and "stop" or "start")
		end
	elseif kind == "ev" then
		local what, seq = string.match(rest, "^(%a+):(.*)$")
		for _, item in ipairs(S.activity) do
			if what == "open" and tostring(item.seq) == seq and S.by_id[item.id] then
				go.section("containers")
				S.cursor.containers = item.id
				go.open(item.id, true)
			end
		end
	elseif kind == "part" then
		S.system_pick = tonumber(rest) or S.system_pick
		bump()
	elseif kind == "sorth" then
		if S.section == "images" then
			S.image_sort = rest
		else
			S.sort = rest
		end
		bump()
	elseif kind == "pf" then
		S.plain_filter[S.section] = rest
		S.cache = {}
		bump()
		keep_cursor(S.section)
	elseif kind == "hint" then
		local run = S.hint_runs and S.hint_runs[tonumber(rest)]
		if run then
			run()
			bump()
		end
	elseif id == "jobs" then
		S.jobs_open = not S.jobs_open
		bump()
	elseif id == "cmd" then
		palette.open()
	elseif id == "helpbtn" then
		S.help = true
		bump()
	elseif kind == "verb" then
		if S.section == "containers" and string.sub(rest, 1, 6) == "group:" then
			S.cursor.containers = rest
			bump()
			local members = targets("containers")
			local ids, running = {}, false
			for _, row in ipairs(members) do
				running = running or is_up(row.c)
			end
			for _, row in ipairs(members) do
				if running == is_up(row.c) then
					ids[#ids + 1] = row.id
				end
			end
			act.run(ids, running and "stop" or "start")
		elseif S.section == "containers" then
			local c = S.by_id[rest]
			if c then
				S.cursor.containers = rest
				act.run({ rest }, is_up(c) and "stop" or "start")
			end
		else
			S.cursor[S.section] = rest
			S.marks[S.section] = {}
			act.remove_listed(S.section)
		end
	elseif kind == "filter" then
		S.filter = rest
		bump()
		keep_cursor("containers")
	elseif id == "group" then
		S.group = not S.group
		bump()
		keep_cursor("containers")
	elseif id == "sort" then
		local rect = b.layout.bounds("sort")
		S.pending_menu = rect and { x = rect.x, y = rect.y + rect.h + 4, kind = "sort" }
			or { x = 220, y = 160, kind = "sort" }
		bump()
	elseif id == "act:pull" then
		ask_pull()
	elseif id == "act:clean" then
		ask_clean()
	elseif id == "act:remove" then
		act.remove_listed(S.section)
	elseif kind == "d" then
		local c = S.open and S.by_id[S.open]
		if c == nil then
			return
		end
		if rest == "toggle" then
			act.run({ c.id }, is_up(c) and "stop" or "start")
		elseif rest == "restart" then
			act.run({ c.id }, "restart")
		elseif rest == "pause" then
			act.run({ c.id }, c.state == "paused" and "unpause" or "pause")
		elseif rest == "shell" then
			act.terminal("shell", c)
		elseif rest == "follow" then
			act.terminal("logs", c)
		elseif rest == "remove" then
			S.marks.containers = {}
			S.cursor.containers = c.id
			act.remove_containers()
		elseif rest == "close" then
			go.close()
		elseif rest == "copyid" then
			S.copy = c.id
			toast.say("Copied the id", { kind = "success" })
		elseif rest == "copyjson" then
			local data = S.details[c.id] and S.details[c.id].data
			if data then
				S.copy = table.concat(data.lines, "\n")
				toast.say("Copied the JSON", { kind = "success" })
			end
		elseif rest == "labels" then
			S.show_labels = not S.show_labels
		elseif rest == "secrets" then
			S.show_secrets = not S.show_secrets
		end
		bump()
	elseif kind == "tab" then
		go.tab(rest)
	elseif kind == "l" then
		if rest == "follow" then
			L.follow = not L.follow
			if L.follow then
				L.new_since = 0
			end
		elseif rest == "time" then
			L.timestamps = not L.timestamps
		elseif rest == "wrap" then
			log_toggle_wrap()
		elseif rest == "only" then
			-- The match on show stays on show, among the lines it found or in the whole log.
			L.only = not L.only
			if L.matches[L.match_at] then
				log_show_match(L.match_at)
			else
				lib_kit.scroll_to("log", 0)
			end
		elseif rest == "clear" then
			log_wipe()
		elseif rest == "copy" then
			local from = math.max(L.count - 4000 + 1, 1)
			local lines = {}
			for index = from, L.count do
				lines[#lines + 1] = ansi.strip(L.texts[index])
			end
			S.copy = table.concat(lines, "\n")
			toast.say("Copied " .. fmt.count(#lines, "line"), { kind = "success" })
		elseif rest == "next" then
			log_step_match(1)
		elseif rest == "prev" then
			log_step_match(-1)
		elseif rest == "more" then
			log_keys("L", {})
		end
	elseif kind == "envcopy" then
		local data = S.open and S.details[S.open] and S.details[S.open].data
		for _, entry in ipairs(data and data.env or {}) do
			if entry.key == rest then
				S.copy = entry.key .. "=" .. entry.value
				toast.say("Copied " .. entry.key, { kind = "success" })
			end
		end
	elseif kind == "copyport" or kind == "port" then
		local url = "http://localhost:" .. rest
		S.copy = url
		toast.say("Copied " .. url, { kind = "info", body = "A page cannot open a link in a browser: paste it there." })
	elseif kind == "env" then
		S.revealed_env[rest] = (not S.revealed_env[rest]) or nil
	elseif kind == "layers" then
		local what, id = string.match(rest, "^(%a+):(.*)$")
		if what == "toggle" then
			S.cursor.images = id
			go.layers(S.layer_open ~= id and id or nil)
		end
	elseif kind == "img" then
		local what, name = string.match(rest, "^(%a+):(.*)$")
		for _, c in ipairs(S.containers) do
			if what == "open" and c.name == name then
				go.section("containers")
				S.cursor.containers = c.id
				go.open(c.id, true)
			end
		end
	elseif kind == "free" then
		for index, one in ipairs(DISK) do
			if one.key == rest then
				S.system_pick = index
				go.free(index)
			end
		end
	elseif kind == "dialog" then
		local what, index = string.match(rest, "^(%a+):?(%d*)$")
		if S.dialog == nil then
			return
		elseif what == "cancel" or what == "backdrop" then
			dialog.close()
		elseif what == "confirm" then
			dialog.confirm()
		elseif what == "option" then
			dialog.toggle(tonumber(index))
		elseif what == "suggest" then
			dialog.suggest(dialog.SUGGESTIONS[tonumber(index)])
		end
	elseif kind == "palette" then
		local what, index = string.match(rest, "^(%a+):?(%d*)$")
		if what == "backdrop" then
			palette.close()
		elseif what == "item" then
			palette.run(tonumber(index))
		end
	elseif id == "help:backdrop" then
		S.help = false
		bump()
	elseif kind == "toast" then
		local item = S.toasts[tonumber(rest)]
		if item then
			table.remove(S.toasts, tonumber(rest))
			if item.show and S.by_id[item.show] then
				go.section("containers")
				S.cursor.containers = item.show
				go.open(item.show, true)
			end
			bump()
		end
	elseif kind == "toast.x" then
		table.remove(S.toasts, tonumber(rest))
		bump()
	elseif kind == "overlay" then
		return
	elseif id == "jobs:backdrop" then
		S.jobs_open = false
		bump()
	elseif id == "help:close" then
		S.help = false
		bump()
	elseif kind == "toast.action" then
		local index = tonumber(rest)
		local item = S.toasts[index]
		if item and item.action then
			table.remove(S.toasts, index)
			if item.action.open and S.by_id[item.action.open] then
				go.section("containers")
				S.cursor.containers = item.action.open
				go.open(item.action.open, true)
				go.tab("logs")
			elseif item.action.run then
				item.action.run()
			end
			bump()
		end
	end
end

return {
	mouse = mouse,
}
