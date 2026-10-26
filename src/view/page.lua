-- (page entry: assembled from the old page; to be rewritten)
local lib_kit = require("./lib/kit")
local parts_ui = require("./parts/ui")
local input_keys = require("./input/keys")
local input_mouse = require("./input/mouse")
local lib_fmt = require("./lib/fmt")
local lib_sizes = require("./lib/sizes")
local lib_virtual = require("./lib/virtual")
local model_feed = require("./model/feed")
local model_lists = require("./model/lists")
local model_log = require("./model/log")
local model_nav = require("./model/nav")
local model_net = require("./model/net")
local model_rows = require("./model/rows")
local model_state = require("./model/state")
local model_toast = require("./model/toast")
local parts_palette = require("./parts/palette")
local parts_rail = require("./parts/rail")
local parts_status = require("./parts/status")
local parts_overlays = require("./parts/overlays")
local screens_logs = require("./screens/logs")
local alpha, b, ui = lib_kit.alpha, lib_kit.b, lib_kit.ui
local keys, reply_field, scroll_by = input_keys.keys, input_keys.reply_field, input_keys.scroll_by
local mouse = input_mouse.mouse
local fmt = lib_fmt.fmt
local SIZE = lib_sizes.SIZE
local reveal, views = lib_virtual.reveal, lib_virtual.views
local on_containers, on_events, on_jobs = model_feed.on_containers, model_feed.on_events, model_feed.on_jobs
local load_list, load_system = model_lists.load_list, model_lists.load_system
local L, log_total = model_log.L, model_log.log_total
local field_context, go, persist, restore, row_menu, sync =
	model_nav.field_context, model_nav.go, model_nav.persist, model_nav.restore, model_nav.row_menu, model_nav.sync
local net, why = model_net.net, model_net.why
local index_of, keep_cursor, row_tops, rows_of =
	model_rows.index_of, model_rows.keep_cursor, model_rows.row_tops, model_rows.rows_of
local S, bump, geometry = model_state.S, model_state.bump, model_state.geometry
local toast = model_toast.toast
local palette_part = parts_palette
local rail = parts_rail
local status = parts_status
local overlays = parts_overlays.overlays
local scan_log = screens_logs.scan_log

-- The screens: each file of screens/ says what it can show, by name.
local screens = {}
for _, module in ipairs({
	require("./screens/containers"),
	require("./screens/detail"),
	require("./screens/resources"),
	require("./screens/system"),
	require("./screens/activity"),
}) do
	for name, screen in pairs(module.screens) do
		screens[name] = screen
	end
end

-- ---- the page ----------------------------------------------------------------------------------------------

-- What the screen of the section that is on show is.
local function main_screen(g)
	local section = S.section
	local frame_ = b.div():col():grow(1):min_w(0):min_h(0)
	if section == "containers" then
		local open = S.open and S.by_id[S.open]
		if open and g.beside then
			local detail_width = g.detail
			local list_width = g.main - detail_width
			return b
				.div()
				:row()
				:grow(1)
				:min_w(0)
				:min_h(0)
				:child(screens.list(list_width))
				-- The line between them, which the pointer drags: wider to the pointer than it is drawn.
				:child(
					b.div()
						:w(7)
						:ml(-3)
						:mr(-3)
						:no_shrink()
						:press("split")
						:row()
						:justify_center()
						:child(b.div():w(1):h_full():bg(alpha("border", ui.pressed == "split" and 1 or 0.6)))
				)
				:child(b.div():col():w(detail_width):no_shrink():child(screens.detail(detail_width, true)))
		elseif open then
			return frame_:child(screens.detail(g.main, false))
		end
		return frame_:child(screens.list(g.main))
	elseif section == "images" then
		return frame_:child(screens.images(g.main))
	elseif section == "volumes" then
		return frame_:child(screens.volumes(g.main))
	elseif section == "networks" then
		return frame_:child(screens.networks(g.main))
	elseif section == "system" then
		return frame_:child(screens.system(g.main))
	end
	return frame_:child(screens.activity(g.main))
end

local function build(g)
	local root = b.div():size_full()
	local app = b.div():size_full():col()
	if g.rail == 0 then
		app:child(rail.strip())
	end
	local body = b.div():row():grow(1):min_h(0)
	if g.rail > 0 then
		body:child(rail.column(g.compact))
	end
	body:child(main_screen(g))
	app:child(body)
	app:child(status.bar(S.width))
	root:child(app)
	local jobs = overlays.jobs()
	if jobs then
		root:child(jobs)
	end
	if #S.toasts > 0 then
		root:child(overlays.toasts())
	end
	if S.palette then
		root:child(palette_part.view())
	end
	if S.help then
		root:child(overlays.help())
	end
	if S.dialog then
		root:child(overlays.dialog())
	end
	return root
end

local function on_boot(result, err)
	if err then
		toast.say("The program did not start the page: " .. tostring(why(err)), { kind = "error", seconds = 15 })
		return
	end
	S.ready = true
	S.hostname, S.remote, S.handoff = result.hostname or "", result.remote == true, result.handoff == true
	S.clock = result.time and (result.time - S.now) or nil
	restore(result.ui)
	if result.section then
		S.section = result.section
	end
	S.focus_request = result.focus
	net.watch("containers", "containers", nil, on_containers)
	net.watch("events", "events", nil, on_events)
	net.watch("jobs", "jobs", nil, on_jobs)
	local back = result.returned
	if back then
		local what = back.kind == "shell" and "The shell in " or "The log of "
		local how = back.status == nil and "ended"
			or (back.status == 0 and "ended" or ("ended with code " .. back.status))
		toast.say(what .. back.name .. " " .. how .. " after " .. fmt.span((back.duration or 0) / 1000), {
			kind = (back.status == nil or back.status == 0) and "info" or "warning",
			error = back.error,
		})
		if back.error then
			toast.say(back.error, { kind = "error" })
		end
	end
	if result.handoff_failed then
		toast.say(result.handoff_failed, { kind = "warning" })
	end
	bump()
end

-- A name on the command line, found among the containers: the cursor goes to it and its detail opens.
local function find_requested()
	local key = S.focus_request
	if key == nil or not S.known then
		return
	end
	S.focus_request = nil
	local found = nil
	for _, c in ipairs(S.containers) do
		if c.id == key or c.name == key or c.service == key or string.sub(c.id, 1, #key) == key then
			if found == nil or (c.state == "running" and found.state ~= "running") then
				found = c
			end
		end
	end
	if found then
		S.section = "containers"
		S.cursor.containers = found.id
		go.open(found.id, true)
		S.reveal = true
	else
		toast.say("There is no container " .. key, { kind = "warning" })
	end
end

local function tick_reload()
	if S.pending_reload and S.now >= S.pending_reload then
		S.pending_reload = nil
		-- All three, shown or not: the rail counts them.
		for _, section in ipairs({ "images", "volumes", "networks" }) do
			if S.stale[section] then
				load_list(section)
			end
		end
		if S.stale.system and S.section == "system" then
			load_system()
		end
	end
end

local started = false

local function render(size, now, reduce_motion)
	S.width, S.height, S.now, S.reduce_motion = size.w, size.h, now, reduce_motion
	if not started then
		started = true
		net.ask("boot", nil, on_boot)
	end
	local toast_at = toast.tidy()
	tick_reload()
	find_requested()
	if S.reveal and S.known then
		S.reveal = false
		local rows = rows_of(S.section)
		local at = index_of(rows, S.cursor[S.section])
		if at then
			reveal("list", at, #rows, SIZE.row, nil, row_tops(S.section))
		end
	end
	sync()
	local g = geometry()
	S.field = field_context(g)
	L.query_on = S.field == "logs"
	local scanning = false
	if S.section == "containers" and S.open and S.tab == "logs" and L.id == S.open then
		scanning = scan_log(3000)
	end
	S.any_marked = false
	for _ in pairs(S.marks[S.section] or {}) do
		S.any_marked = true
		break
	end
	-- The highlights take their step before the page is built from them, and the build says where
	-- each is going (`parts/ui.lua`'s `glow`); while one is on its way the page is drawn again.
	ui.fades:advance(now, reduce_motion)
	local root = build(g)
	-- A highlight the build has just set going starts its clock now (a step of nothing), so the
	-- next frame takes it a frame's way and not none.
	local fading = ui.fades:advance(now, reduce_motion)
	local wake = nil
	local function wake_at(at)
		if at then
			wake = wake and math.min(wake, at) or at
		end
	end
	wake_at(toast_at)
	wake_at(S.pending_reload)
	if S.open and now - S.open_at < 0.2 then
		wake_at(S.open_at + 0.21)
	end
	if S.open and S.tab == "processes" and S.processes.at then
		wake_at(S.processes.at + 2.05)
	end
	return root, scanning or fading, wake
end

-- The keyboard goes to the host's field, or to the page.
local function on_text(text)
	S.query = text
	S.cache = {}
	bump()
	if S.dialog and S.dialog.field then
		-- The name typed to be pulled.
		S.dialog.reference = text
	elseif S.palette then
		-- What is looked for in the palette: the first of what it finds is the one it is on.
		S.palette.active = 1
		S.palette.reveal = true
		ui:set_scroll("palette.list", 0)
	elseif S.field == "list" then
		ui.scroll.list = nil
		keep_cursor(S.section)
	end
end

local function cursor_shape()
	local hover = ui.hover
	if ui.pressed == "split" or hover == "split" then
		return "resize_horizontal"
	elseif hover == "field" or hover == "field.room" then
		return "text"
	elseif hover ~= nil then
		return "pointer"
	end
	return "arrow"
end

-- What the page says back to an input, as the reply the kit takes.
local function answer(result)
	local reply = {}
	if type(result) == "table" then
		reply = result
	elseif result ~= nil then
		reply.redraw = result == true
	end
	if S.copy then
		reply.copy, S.copy = S.copy, nil
	end
	if S.pending_menu then
		reply.menu = row_menu(S.pending_menu)
		S.pending_menu = nil
	end
	if S.want_field then
		S.want_field, S.typing = nil, true
		reply.keyboard = { field = parts_ui.FIELD }
	end
	reply.cursor = cursor_shape()
	persist()
	sync()
	return reply
end

local function handle(event)
	local kind = event.type
	local result = nil
	if kind == "move" then
		S.pointer = { x = event.x, y = event.y }
		if ui.pressed == "split" then
			-- The line between the list and a container is dragged: the container's side is what is
			-- right of the pointer (the layout holds it to what both sides need).
			S.detail_width = math.max(340, math.floor(S.width - event.x))
			return { redraw = true, cursor = "resize_horizontal" }
		end
		return { redraw = ui:point(b.layout, event), cursor = cursor_shape() }
	elseif kind == "leave" then
		S.pointer = nil
		return { redraw = ui:point(b.layout, nil), cursor = "arrow" }
	elseif kind == "press" then
		S.pointer = { x = event.x, y = event.y }
		local hit = ui:press(b.layout, event)
		if hit ~= "field" and hit ~= "field.room" then
			S.typing = false
		end
		S.press_mods = event.mods
		result = false
		if hit == "field" or hit == "field.room" then
			result = reply_field()
		elseif event.button == "right" and hit and string.sub(hit, 1, 4) == "row:" then
			mouse.click(hit, { shift = false })
			S.pending_menu = { x = event.x, y = event.y }
			result = true
		elseif hit then
			result = true
		end
	elseif kind == "release" then
		local clicked = ui:release(b.layout, event)
		if clicked and event.button == "left" and clicked ~= "field" and clicked ~= "field.room" then
			mouse.click(clicked, S.press_mods)
		end
		result = true
	elseif kind == "scroll" then
		S.pointer = { x = event.x, y = event.y }
		local dx, dy = event.dx or 0, event.dy or 0
		local moved = ui:scroll_by(b.layout, event, dx, dy)
		local over_log = S.section == "containers" and S.open and S.tab == "logs"
		if over_log and dx ~= 0 then
			-- Across, a log's lines move under it (they are not a box that scrolls across).
			local was = L.hscroll
			L.hscroll = math.max(math.floor(L.hscroll + dx), 0)
			moved = moved or L.hscroll ~= was
		end
		if moved and over_log and dy ~= 0 then
			if dy < 0 then
				L.follow = false
			else
				local view = views.log or 400
				if ui:scroll_offset("log") >= log_total() + 8 - view - 2 then
					L.follow, L.new_since = true, 0
				end
			end
		end
		result = moved
	elseif kind == "key" then
		if S.typing and S.palette and (event.key == "up" or event.key == "down") then
			-- In the palette the arrows choose while the words stay in the field.
			result = keys.palette(event.key, event.mods)
		elseif S.typing then
			-- A key the field gives the page (⏎, Esc, ⇥, an arrow): it leaves the field without a word,
			-- and the next key is the page's.
			S.typing = false
			result = { redraw = true, keyboard = "page" }
		else
			result = keys.press(event.key, event.mods)
		end
	elseif kind == "text" then
		on_text(event.text)
		result = true
	elseif kind == "focus" then
		-- The person clicked into the field (or the keyboard left it of itself).
		S.typing = event.field ~= nil
		result = true
	elseif kind == "menu" then
		local menu = S.menu
		S.menu = nil
		if menu and menu.acts[event.index] then
			menu.acts[event.index]()
		end
		result = true
	end
	return answer(result)
end

local function settle()
	local moved = ui:settle(b.layout)
	for _, id in ipairs({ "list", "log", "detail.inspect", "detail.scroll", "system.scroll", "help.scroll" }) do
		local extent = b.layout.scroll_extent(id)
		if extent and views[id] ~= extent.view then
			views[id] = extent.view
			moved = true
		end
	end
	if S.pointer then
		moved = ui:point(b.layout, S.pointer) or moved
	end
	return moved
end

return {
	render = render,
	handle = handle,
	settle = settle,
}
