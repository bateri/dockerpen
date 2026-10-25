local lib_kit = require("../lib/kit")
local lib_fmt = require("../lib/fmt")
local lib_sizes = require("../lib/sizes")
local lib_virtual = require("../lib/virtual")
local model_containers = require("../model/containers")
local model_state = require("../model/state")
local parts_ui = require("../parts/ui")
local screens_logs = require("./logs")
local alpha, b, ui = lib_kit.alpha, lib_kit.b, lib_kit.ui
local fmt = lib_fmt.fmt
local ENV_MOST, LABELS_MOST, PROCESSES_MOST, SIZE, TABS =
	lib_sizes.ENV_MOST, lib_sizes.LABELS_MOST, lib_sizes.PROCESSES_MOST, lib_sizes.SIZE, lib_sizes.TABS
local virtual = lib_virtual.virtual
local ago, container, is_up, state_of =
	model_containers.ago, model_containers.container, model_containers.is_up, model_containers.state_of
local S = model_state.S
local P, T, hovered = parts_ui.P, parts_ui.T, parts_ui.hovered
local log_tab = screens_logs.log_tab

local screens = {}

-- ---- the detail of a container -------------------------------------------------------------------

-- What the exit code of a container that stopped says, when it says a signal's.
local SIGNALS = {
	[129] = "SIGHUP",
	[130] = "SIGINT (⌃C)",
	[131] = "SIGQUIT",
	[134] = "SIGABRT",
	[137] = "SIGKILL: killed, or out of memory",
	[139] = "SIGSEGV: a crash",
	[141] = "SIGPIPE",
	[143] = "SIGTERM: asked to stop",
}

local SECRET = { "PASS", "SECRET", "TOKEN", "KEY", "PWD", "CREDENTIAL", "AUTH", "PRIVATE", "SALT", "SIGNATURE" }

-- Whether an environment variable looks like it holds a secret: by its name, or a password in a URL.
local function secret_like(key, value)
	local upper = string.upper(key)
	for _, word in ipairs(SECRET) do
		if string.find(upper, word, 1, true) then
			return true
		end
	end
	return string.find(value, "://[^/@%s]+:[^/@%s]+@") ~= nil
end

-- The detail of the container that is open, as the program told it (or nil while it has not).
local function detail_data()
	local slot = S.open and S.details[S.open]
	return slot and slot.data, slot
end

local function lines_of_text(content, role, size)
	return T(content, role, size or SIZE.body):truncate()
end

-- The verbs of one container, as a row of buttons with their icons, and the one that removes it at
-- the end, as an icon of its own.
local function verbs_row(c, narrow)
	local up = is_up(c)
	local busy = S.busy[c.id] ~= nil
	local row = b.div():row():items_center():gap(6):px(14):h(32):no_shrink()
	local function verb(id, label, name, o)
		o = o or {}
		o.size, o.icon = "sm", name
		return P.button(id, label, o)
	end
	row:child(
		verb(
			"d:toggle",
			up and "Stop" or (c.state == "paused" and "Resume" or "Start"),
			up and "square" or "play",
			{ disabled = busy }
		)
	)
	row:child(verb("d:restart", "Restart", "rotate-cw", { disabled = busy }))
	if up or c.state == "paused" then
		row:child(
			verb(
				"d:pause",
				c.state == "paused" and "Resume" or "Pause",
				c.state == "paused" and "play" or "pause",
				{ disabled = busy }
			)
		)
	end
	row:child(verb("d:shell", "Shell", "square-terminal", { disabled = c.state ~= "running" }))
	row:child(b.spacer())
	row:child(
		P.button(
			"d:remove",
			nil,
			{ variant = "danger-ghost", size = "sm", icon = "trash-2", icon_size = 14, disabled = busy }
		)
	)
	return row
end

-- The charts of a running container, and what it has used.
local function usage_cards(c, wide)
	local sample = S.samples[c.short]
	local series = S.series[c.short] or { cpu = {}, memory = {}, net_in = {}, net_out = {} }
	-- A card: its name with an icon, a value with a word beside it, and a line of readings.
	local function card(title, mark, value, small, line, role, ceiling)
		local el = P.card():gap(0)
		el:child(
			b.div()
				:row()
				:items_center()
				:gap(6)
				:h(18)
				:child(P.icon(mark, 12, "quiet"))
				:child(T(string.upper(title), "quiet", SIZE.tiny + 0.5, 500))
		)
		local head = b.div():row():items_center():gap(5):mt(2):child(T(value, "foreground", 17, 600):truncate())
		if small and small ~= "" then
			head:child(T(small, "quiet", SIZE.small):truncate())
		end
		el:child(head)
		if line then
			el:child(b.div():h(56):mt(8):child(P.spark(line, role, ceiling)))
		end
		return el
	end
	local running = c.state == "running" and sample ~= nil
	local waiting = c.state == "running" and "waiting for a reading" or "not running"
	local cpus = S.engine and S.engine.cpus or 1
	local cpu = running
			and card(
				"CPU",
				"cpu",
				fmt.percent(sample.cpu),
				cpus > 1 and "of one cpu" or "of the cpu",
				series.cpu,
				"accent"
			)
		or card("CPU", "cpu", "–", waiting, {}, "accent")
	local limit = sample and sample.memory_limit or 0
	local host = S.engine and S.engine.memory or 0
	local limited = limit > 0 and (host == 0 or limit < host * 0.95)
	local memory = running
			and card(
				"Memory",
				"memory-stick",
				fmt.memory(sample.memory),
				limited and ("of " .. fmt.memory(limit)) or "",
				series.memory,
				"success",
				limited and limit or nil
			)
		or card("Memory", "memory-stick", "–", waiting, {}, "success")
	local network
	if running then
		network = card("Network", "network", "", nil, series.net_in, "warning")
		local head = b.div():row():items_center():gap(10):mt(2)
		head:child(T("↓ " .. fmt.rate(sample.net_in), "info", 15, 600))
		head:child(T("↑ " .. fmt.rate(sample.net_out), "warning", 15, 600))
		-- The value row of the card is empty: this one is its own.
		network.kids[2] = head
	else
		network = card("Network", "network", "–", waiting, {}, "warning")
	end
	local disk = card("Disk and processes", "hard-drive", "", nil, nil, "warning")
	if running then
		local function kv(label, value)
			return b.div()
				:row()
				:items_center()
				:h(20)
				:child(b.div():w(80):no_shrink():child(T(label, "quiet", SIZE.small + 0.5)))
				:child(T(value, "foreground", SIZE.body))
		end
		disk.kids[2] = b.div()
			:col()
			:mt(4)
			:child(kv("read", fmt.rate(sample.disk_read)))
			:child(kv("write", fmt.rate(sample.disk_write)))
			:child(kv("processes", tostring(sample.pids)))
	else
		disk.kids[2] = b.div():mt(2):child(T("–", "foreground", 17, 600))
	end
	local grid = b.div():col():gap(8):no_shrink()
	if wide then
		local function half(el)
			return b.div():col():w(0):grow(1):min_w(0):child(el)
		end
		grid:child(b.div():row():gap(8):child(half(cpu)):child(half(memory)))
		grid:child(b.div():row():gap(8):child(half(network)):child(half(disk)))
	else
		grid:child(cpu):child(memory):child(network):child(disk)
	end
	return grid
end

-- Why a container that is not running is not.
local function why_stopped(c, data)
	if is_up(c) or data == nil then
		return nil
	end
	local state = data.state
	local card = P.card():gap(3)
	local role = (state.exit_code ~= 0 or state.oom_killed) and "error" or "dim"
	card:child(T("WHY IT STOPPED", "quiet", SIZE.tiny + 0.5, 600))
	if state.oom_killed then
		card:child(T("It ran out of memory and was killed.", "error", SIZE.body, 600))
	end
	local words = state.exit_code == 0 and "Exited normally (code 0)" or ("Exited with code " .. state.exit_code)
	if SIGNALS[state.exit_code] then
		words = words .. " · " .. SIGNALS[state.exit_code]
	end
	card:child(T(words, role, SIZE.body, 500):truncate())
	if state.error ~= "" then
		card:child(T(state.error, "error", SIZE.small):truncate())
	end
	local when = state.finished_at and ago(state.finished_at)
	if when then
		card:child(T("Stopped " .. when, "dim", SIZE.small))
	end
	return card
end

-- What the health checks of a container say.
local function health_card(data)
	local health = data.state.health
	if health == nil then
		return nil
	end
	local role = health.status == "healthy" and "success" or (health.status == "unhealthy" and "error" or "warning")
	local card = P.card():gap(3)
	card:child(
		b.div()
			:row()
			:items_center()
			:gap(8)
			:child(T("HEALTH", "quiet", SIZE.tiny + 0.5, 600))
			:child(P.tag(health.status, role))
	)
	if health.failing_streak > 0 then
		card:child(T(fmt.count(health.failing_streak, "check") .. " in a row failed", "error", SIZE.small))
	end
	if data.healthcheck then
		card:child(T(table.concat(data.healthcheck, " "), "dim", SIZE.small):truncate())
	end
	for index = #health.log, math.max(#health.log - 3, 1), -1 do
		local entry = health.log[index]
		local output = string.gsub(entry.output or "", "%s+", " ")
		card:child(
			b.div()
				:row()
				:gap(8)
				:child(
					T(
						entry.exit_code == 0 and "✓" or "✗",
						entry.exit_code == 0 and "success" or "error",
						SIZE.small
					):no_shrink()
				)
				:child(T(output ~= "" and output or ("exit code " .. entry.exit_code), "dim", SIZE.small):truncate())
		)
	end
	return card
end

local function port_text(port)
	if port.public then
		return string.format("%s:%d → %d/%s", port.ip or "*", port.public, port.private, port.type)
	end
	return string.format("%d/%s (not published)", port.private, port.type)
end

-- The overview: what it uses, why it stopped, what it is made of.
local function overview(c, w)
	local data = detail_data()
	local wide = w >= 400
	local body = b.div():col():gap(8):px(18):pt(4):pb(20)
	body:child(usage_cards(c, wide))
	local stopped = why_stopped(c, data)
	if stopped then
		body:child(stopped)
	end
	if data == nil then
		local slot = S.details[c.id]
		body:child(
			T(slot and slot.error or "Reading the container…", slot and slot.error and "error" or "dim", SIZE.small):mt(
				10
			)
		)
		return body
	end
	local health = health_card(data)
	if health then
		body:child(health)
	end
	body:child(P.heading("Container"))
	body:child(P.fact("image", data.image))
	local command = (#data.entrypoint > 0 and table.concat(data.entrypoint, " ") .. " " or "")
		.. table.concat(data.cmd, " ")
	body:child(P.fact("command", command ~= "" and command or (data.path .. " " .. table.concat(data.args, " "))))
	body:child(P.fact("created", data.created and (ago(data.created) or "–") or "–"))
	if data.state.running and data.state.started_at then
		body:child(P.fact("started", ago(data.state.started_at) or "–"))
	end
	body:child(P.fact("restarts", data.restart_count .. " · policy " .. data.restart_policy))
	body:child(P.fact("platform", data.platform ~= "" and data.platform or "–"))
	if data.user ~= "" then
		body:child(P.fact("user", data.user))
	end
	if data.working_dir ~= "" then
		body:child(P.fact("working dir", data.working_dir))
	end
	if data.memory_limit > 0 or data.cpu_limit > 0 then
		body:child(
			P.fact(
				"limits",
				(data.memory_limit > 0 and (fmt.memory(data.memory_limit) .. " memory") or "")
					.. (data.memory_limit > 0 and data.cpu_limit > 0 and " · " or "")
					.. (data.cpu_limit > 0 and (data.cpu_limit .. " cpus") or "")
			)
		)
	end
	if data.privileged then
		body:child(P.fact("privileged", "yes", "warning"))
	end
	if #data.ports > 0 then
		body:child(P.heading("Ports"))
		for _, port in ipairs(data.ports) do
			body:child(lines_of_text(port_text(port), port.public and "foreground" or "dim"))
		end
	end
	if #data.networks > 0 then
		body:child(P.heading("Networks"))
		for _, network in ipairs(data.networks) do
			local aliases = #network.aliases > 0 and (" · " .. table.concat(network.aliases, ", ")) or ""
			body:child(
				b.div()
					:row()
					:gap(10)
					:child(T(network.name, "foreground", SIZE.body, 600):no_shrink())
					:child(T(network.ip .. aliases, "dim", SIZE.small + 0.5):truncate())
			)
		end
	end
	if #data.mounts > 0 then
		body:child(P.heading("Mounts"))
		for _, mount in ipairs(data.mounts) do
			body:child(
				b.div():row():gap(8):child(P.tag(mount.type, "info")):child(
					T(
						(mount.name or mount.source)
							.. " → "
							.. mount.destination
							.. (mount.rw and "" or "  read-only"),
						"foreground",
						SIZE.small + 0.5
					):truncate()
				)
			)
		end
	end
	local keys = {}
	for key in pairs(data.labels) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	if #keys > 0 then
		body:child(
			P.heading(
				"Labels",
				P.button(
					"d:labels",
					S.show_labels and "Hide" or ("Show " .. #keys),
					{ key = "v", h = 20, px = 7, size = SIZE.small }
				)
			)
		)
		if S.show_labels then
			for index, key in ipairs(keys) do
				if index > LABELS_MOST then
					body:child(T("and " .. (#keys - LABELS_MOST) .. " more", "quiet", SIZE.small))
					break
				end
				body:child(P.fact(fmt.cut(key, 18), data.labels[key]))
			end
		end
	end
	return body
end

-- The environment: the variables, with what looks secret hidden until asked for.
local function environment(c)
	local data = detail_data()
	if data == nil then
		return b.div():px(18):child(T("Reading the container…", "dim", SIZE.small))
	end
	if #data.env == 0 then
		return P.nothing("It has no environment variables")
	end
	local body = b.div():col():gap(1):px(18):pt(4):pb(20)
	body:child(
		b.div()
			:row()
			:items_center()
			:gap(8)
			:h(30)
			:child(T(fmt.count(#data.env, "variable"), "dim", SIZE.small))
			:child(b.spacer())
			:child(
				P.button(
					"d:secrets",
					S.show_secrets and "Hide secrets" or "Show secrets",
					{ key = "v", h = 22, px = 8, size = SIZE.small }
				)
			)
	)
	for index, entry in ipairs(data.env) do
		if index > ENV_MOST then
			body:child(T("and " .. (#data.env - ENV_MOST) .. " more", "quiet", SIZE.small):mt(4))
			break
		end
		local hidden = secret_like(entry.key, entry.value) and not S.show_secrets and not S.revealed_env[entry.key]
		local id = "env:" .. entry.key
		body:child(
			b.div()
				:press(id)
				:row()
				:gap(14)
				:items_center()
				:h(24)
				:px(6)
				:rounded(5)
				:bg(hovered(id) and alpha("foreground", 0.05) or nil)
				:child(b.div():w(170):no_shrink():child(P.line(entry.key, "info", SIZE.small + 0.5, 600)))
				:child(
					b.div():grow(1):min_w(0):child(
						P.line(
							hidden and "••••••••  (click to show)" or entry.value,
							hidden and "quiet" or "foreground",
							SIZE.small + 0.5
						)
					)
				)
		)
	end
	return body
end

-- The processes: what `docker top` says, refreshed while it is looked at.
local function processes_tab(c)
	local slot = S.processes
	if c.state ~= "running" then
		return P.nothing("It is not running", "A container that is stopped has no processes.")
	end
	if slot.id ~= c.id or slot.titles == nil then
		return b.div()
			:px(18)
			:child(T(slot.error or "Looking at the processes…", slot.error and "error" or "dim", SIZE.small))
	end
	local body = b.div():col():gap(1):px(18):pt(4):pb(20)
	local widths = { 64, 80, 70 }
	local function cells(list, head)
		local row = b.div():row():gap(12):items_center():h(head and 24 or 22)
		for index, text in ipairs(list) do
			local last = index == #list
			local cell = b.div()
			if last then
				cell:grow(1):min_w(0)
			else
				cell:w(widths[index] or 80):no_shrink()
			end
			row:child(
				cell:child(
					P.line(
						text,
						head and "quiet" or "foreground",
						head and SIZE.tiny + 0.5 or SIZE.small + 0.5,
						head and 600 or 400
					)
				)
			)
		end
		return row
	end
	local titles = {}
	for index, title in ipairs(slot.titles) do
		titles[index] = title
	end
	body:child(cells(titles, true))
	for index, row in ipairs(slot.rows) do
		if index > PROCESSES_MOST then
			body:child(T("and " .. (#slot.rows - PROCESSES_MOST) .. " more", "quiet", SIZE.small):mt(4))
			break
		end
		body:child(cells(row, false))
	end
	body:child(T(fmt.count(#slot.rows, "process") .. " · refreshed while you look", "quiet", SIZE.tiny + 0.5):mt(8))
	return body
end

-- One line of the engine's answer, with the parts of it a person looks for in their own colours.
local function inspect_line(text)
	local indent, key, colon, value = string.match(text, '^(%s*)("[^"]*")(:%s*)(.*)$')
	if key == nil then
		local indent_only, rest = string.match(text, "^(%s*)(.*)$")
		return b.div():row():child(T(indent_only .. rest, "dim", SIZE.small + 0.5):no_shrink())
	end
	local role = "foreground"
	if string.sub(value, 1, 1) == '"' then
		role = "success"
	elseif string.match(value, "^%-?%d") then
		role = "warning"
	elseif string.match(value, "^true") or string.match(value, "^false") or string.match(value, "^null") then
		role = "magenta"
	end
	return b.div()
		:row()
		:child(T(indent .. key, "info", SIZE.small + 0.5):no_shrink())
		:child(T(colon, "dim", SIZE.small + 0.5):no_shrink())
		:child(T(value, role, SIZE.small + 0.5):truncate())
end

local function inspect_tab(c)
	local data = detail_data()
	if data == nil then
		return b.div():px(18):child(T("Reading the container…", "dim", SIZE.small))
	end
	local lines = data.lines
	return virtual("detail.inspect", #lines, 17, function(index)
		return b.div():h(17):no_shrink():row():items_center():child(inspect_line(lines[index]))
	end, { px = 18, pt = 4 })
end

-- ---- the detail, as a whole --------------------------------------------------------------------------

function screens.detail(width, beside)
	local c = container(S.open)
	if c == nil then
		return b.div():grow(1)
	end
	local word, role = state_of(c)
	local panel = b.div():col():grow(1):min_w(0):min_h(0)
	local head = b.div():row():items_center():gap(8):h(40):pl(12):pr(10):pt(4):no_shrink()
	head:child(P.dot(c))
	head:child(b.div():grow(1):min_w(0):child(P.line(c.name, "foreground", 14, 650)))
	head:child(P.button("d:close", nil, { variant = "ghost", size = "sm", icon = "x", icon_size = 14 }))
	panel:child(head)
	local sub = b.div():row():items_center():gap(8):px(14):h(24):no_shrink():clip()
	sub:child(P.tag(word, role ~= "dim" and role or nil))
	sub:child(T(fmt.image_name(c.image), "dim", SIZE.small + 1):no_shrink())
	sub:child(
		b.div()
			:row()
			:items_center()
			:gap(5)
			:press("d:copyid")
			:no_shrink()
			:child(T(c.short, hovered("d:copyid") and "foreground" or "dim", SIZE.small + 1))
			:child(P.icon("copy", 12, hovered("d:copyid") and "foreground" or "quiet"))
	)
	if c.project then
		sub:child(
			T(c.project .. (c.service and (" / " .. c.service) or ""), "quiet", SIZE.small + 1):truncate():min_w(0)
		)
	end
	panel:child(sub)
	panel:child(b.div():h(8):no_shrink())
	panel:child(verbs_row(c, width < 560))
	panel:child(b.div():h(8):no_shrink())
	panel:child(P.tabs(TABS, S.tab, "tab:"))
	panel:child(b.div():h(1):bg(alpha("border", 0.6)):no_shrink())
	if S.tab == "logs" then
		return panel:child(log_tab(c, width))
	elseif S.tab == "inspect" then
		return panel:child(inspect_tab(c))
	end
	local content
	if S.tab == "env" then
		content = environment(c)
	elseif S.tab == "processes" then
		content = processes_tab(c)
	else
		content = overview(c, width)
	end
	panel:child(
		b.div()
			:col()
			:id("detail.scroll")
			:grow(1)
			:min_h(0)
			:scroll_y(ui:scroll_offset("detail.scroll"))
			:child(b.div():col():no_shrink():child(content))
	)
	return panel
end

return {
	screens = screens,
}
