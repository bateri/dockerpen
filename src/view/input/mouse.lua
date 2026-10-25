local lib_kit = require("../lib/kit")
local input_keys = require("./keys")
local model_act = require("../model/act")
local model_containers = require("../model/containers")
local model_disk = require("../model/disk")
local model_log = require("../model/log")
local model_nav = require("../model/nav")
local model_rows = require("../model/rows")
local model_state = require("../model/state")
local ui = lib_kit.ui
local log_keys = input_keys.log_keys
local act = model_act.act
local is_up = model_containers.is_up
local DISK = model_disk.DISK
local L = model_log.L
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
			else
				S.layer_open = rest
				ui.scroll.list = nil
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
		S.sort = step(SORTS, S.sort, 1)
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
		elseif rest == "next" then
			log_keys("n", {})
		elseif rest == "prev" then
			log_keys("N", {})
		elseif rest == "more" then
			log_keys("L", {})
		end
	elseif kind == "env" then
		S.revealed_env[rest] = (not S.revealed_env[rest]) or nil
	elseif kind == "layers" then
		if rest == "back" then
			S.layer_open = nil
		elseif rest == "update" then
			go.update_image(S.layer_open)
		elseif rest == "remove" then
			S.cursor.images = S.layer_open
			S.marks.images = {}
			act.remove_listed("images")
		end
		bump()
	elseif kind == "free" then
		for _, one in ipairs(DISK) do
			if one.target == rest then
				local part = S.system and S.system.usage[one.key]
				act.prune({ rest }, { one.title }, part and part.reclaimable or 0)
			end
		end
	elseif kind == "dialog" then
		local d = S.dialog
		if d == nil then
			return
		end
		if rest == "cancel" then
			S.dialog = nil
			bump()
		elseif rest == "confirm" then
			if d.field and string.gsub(S.query, "%s", "") == "" then
				return
			end
			S.dialog = nil
			bump()
			d.run()
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
	elseif kind == "toast.action" then
		local index = tonumber(rest)
		local item = S.toasts[index]
		if item and item.action then
			table.remove(S.toasts, index)
			item.action.run()
			bump()
		end
	end
end

return {
	mouse = mouse,
}
