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
local P, T, hover_glow, lit = parts_ui.P, parts_ui.T, parts_ui.hover_glow, parts_ui.lit
local log_tab = screens_logs.log_tab

local screens = {}

-- ---- the detail of a container -------------------------------------------------------------------

-- What the exit code of a container that stopped says, when it says a signal's.
local SIGNALS = {
	[130] = "interrupted (SIGINT)",
	[134] = "aborted (SIGABRT)",
	[137] = "killed (SIGKILL)",
	[139] = "crashed (SIGSEGV)",
	[143] = "terminated (SIGTERM)",
}

local SECRET =
	{ "PASS", "SECRET", "TOKEN", "KEY", "PWD", "CREDENTIAL", "AUTH", "PRIVATE", "SALT", "COOKIE", "SESSION", "DSN" }

-- Whether an environment variable looks like it holds a secret: by its name, or a password in a URL.
local function secret_like(key, value)
	local upper = string.upper(key)
	for _, word in ipairs(SECRET) do
		if string.find(upper, word, 1, true) then
			return true
		end
	end
	return string.find(value or "", "://[^/@%s]+:[^/@%s]+@") ~= nil
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
-- the end, as an icon of its own. Where the row has no room for the words, the icons alone.
local function verbs_row(c, narrow)
	local up = is_up(c)
	local busy = S.busy[c.id] ~= nil
	local row = b.div():row():items_center():gap(4):px(14):h(24):no_shrink()
	local function verb(id, label, name, o)
		o = o or {}
		o.size, o.icon = "sm", name
		return P.button(id, (not narrow) and label or nil, o)
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
			{ variant = "danger-ghost", size = "sm", icon = "trash-2", icon_size = 13, disabled = busy }
		)
	)
	return row
end

-- The charts of a running container, and what it has used.
local function usage_cards(c, w, data)
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
				:child(P.icon(mark, 12, "quiet"))
				:child(T(string.upper(title), "quiet", SIZE.tiny + 0.5))
		)
		local head = b.div():row():items_center():gap(5):mt(2):child(T(value, "foreground", 17, 600):truncate())
		if small and small ~= "" then
			head:child(T(small, "quiet", SIZE.small):truncate())
		end
		el:child(head)
		if line then
			el:child(b.div():h(54):child(P.spark(line, role, ceiling)))
		end
		return el
	end
	local running = sample ~= nil
	local waiting = "waiting for a reading"
	local cpus = data and data.cpu_limit or 0
	local limit = data and data.memory_limit or 0
	local cpu = running
			and card(
				"CPU",
				"cpu",
				fmt.percent(sample.cpu),
				cpus > 0 and ("of " .. cpus .. " cpu") or "of one cpu",
				series.cpu,
				"accent"
			)
		or card("CPU", "cpu", "–", waiting, {}, "accent")
	local memory = running
			and card(
				"Memory",
				"memory-stick",
				fmt.memory(sample.memory),
				limit > 0 and ("of " .. fmt.memory(limit)) or "",
				series.memory,
				"success",
				limit > 0 and limit or nil
			)
		or card("Memory", "memory-stick", "–", waiting, {}, "success")
	local network
	if running then
		network = card("Network", "network", "", nil, nil)
		local head = b.div():row():items_center():gap(14):mt(2):clip()
		head:child(T("↓ " .. fmt.rate(sample.net_in), "info", 14, 600):no_shrink())
		head:child(T("↑ " .. fmt.rate(sample.net_out), "warning", 14, 600):truncate():min_w(0))
		network.kids[2] = head
		local lines = b.div():h(54)
		local both = 1
		for _, list in ipairs({ series.net_in, series.net_out }) do
			for _, value in ipairs(list) do
				both = math.max(both, value)
			end
		end
		lines:child(P.spark(series.net_in, "info", both))
		lines:child(b.div():absolute():inset(0, 0, 0, 0):child(P.spark(series.net_out, "warning", both)))
		network:child(lines)
	else
		network = card("Network", "network", "–", waiting, {}, "info")
	end
	local disk = card("Disk and processes", "hard-drive", "", nil, nil)
	if running then
		local function row(label, value)
			return b.div()
				:row()
				:items_center()
				:h(22)
				:gap(14)
				:child(b.div():w(90):no_shrink():child(T(label, "quiet", SIZE.small + 1)))
				:child(T(value, "foreground", SIZE.small + 1):truncate():min_w(0))
		end
		disk.kids[2] = b.div()
			:col()
			:mt(6)
			:child(row("read", fmt.rate(sample.disk_read)))
			:child(row("write", fmt.rate(sample.disk_write)))
			:child(row("processes", tostring(sample.pids)))
	else
		disk.kids[2] = b.div():mt(2):child(T("–", "foreground", 17, 600))
	end
	-- As many columns as there is room for cards at least 180 wide, as the first dockerpen's grid.
	local cards = { cpu, memory, network, disk }
	local cols = math.max(1, math.min(4, math.floor((w - 28 + 8) / (180 + 8))))
	local grid = b.div():col():gap(8):no_shrink()
	for from = 1, #cards, cols do
		local row = b.div():row():gap(8)
		for index = from, from + cols - 1 do
			local cell = b.div():col():w(0):grow(1):min_w(0)
			if cards[index] then
				cell:child(cards[index])
			end
			row:child(cell)
		end
		grid:child(row)
	end
	return grid
end

-- "5m ago", or "just now".
local function ago_long(seconds)
	local words = seconds and ago(seconds)
	if words == nil then
		return nil
	end
	return words == "0s ago" and "just now" or words
end

-- What is wrong with a container, in a sentence, as a box over the rest: it ran out of memory, it
-- keeps restarting, it exited with a failure, it is unhealthy. Nothing where nothing is.
local function problem_of(c, data)
	if data == nil then
		return nil
	end
	local state = data.state
	if state.oom_killed then
		return "error",
			"Killed for running out of memory" .. (data.memory_limit > 0 and (" (limit " .. fmt.memory(
				data.memory_limit
			) .. ")") or "") .. "."
	end
	if c.state == "restarting" or (data.restart_count > 2 and c.state ~= "running") then
		return "warning", "Restarting: it has restarted " .. data.restart_count .. " times. The logs say why."
	end
	if c.state == "exited" and state.exit_code ~= 0 then
		local signal = SIGNALS[state.exit_code]
		local when = ago_long(state.finished_at)
		return "error",
			"Exited with code "
				.. state.exit_code
				.. (signal and (", " .. signal) or "")
				.. (when and (", " .. when) or "")
				.. "."
				.. (state.error ~= "" and (" " .. state.error) or "")
	end
	if state.health and state.health.status == "unhealthy" then
		local last = state.health.log[#state.health.log]
		local first = last and last.output and string.match(last.output, "^[^\n]*") or ""
		return "error",
			"Its health check has failed "
				.. state.health.failing_streak
				.. " times in a row"
				.. (first ~= "" and (": " .. first) or ".")
	end
	return nil
end

local function callout(role, text, width)
	local box = b.div()
		:row()
		:gap(10)
		:items_start()
		:px(12)
		:py(10)
		:rounded(8)
		:bg(alpha(role, 0.1))
		:border(1, alpha(role, 0.3))
		:no_shrink()
	box:child(b.div():pt(1):child(P.icon("triangle-alert", 15, role)))
	box:child(
		b.div():grow(1):min_w(0):child(P.paragraph(text, width - 28 - 24 - 15 - 10, "foreground", SIZE.body, nil, 4))
	)
	return box
end

-- The title of a section, with an icon where it has one and a button at its end.
local function section_title(label, mark, extra)
	local row = b.div():row():items_center():gap(8):min_h(16):mb(3):no_shrink()
	if mark then
		row:child(P.icon(mark, 12, "quiet"))
	end
	row:child(T(string.upper(label), "quiet", SIZE.tiny + 0.5, 700))
	if extra then
		row:child(extra)
	end
	return row
end

-- One fact: what it is, and its value (an element or words, which wrap to `width`, in at most
-- `most` lines). The label is cut to `label_w` (92 unless it is said).
local function kv(label, value, width, role, label_w, most)
	label_w = label_w or 92
	local row = b.div():row():gap(14):items_start():min_h(20):no_shrink()
	row:child(b.div():w(label_w):no_shrink():child(P.line(label, "quiet", SIZE.small + 1)))
	if type(value) == "string" then
		value = P.paragraph(value, width - label_w - 14, role or "foreground", SIZE.small + 1, nil, most)
	end
	return row:child(b.div():grow(1):min_w(0):child(value))
end

-- A list of rows, each with the ground a step above the page.
local function plain_row()
	return b.div():row():items_center():gap(8):min_w(0):min_h(32):px(8):py(5):rounded(6):bg("raised1"):no_shrink()
end

local function port_row(port, width)
	local row = plain_row()
	local text = b.div():row():items_center():grow(1):min_w(0):clip()
	if port.public then
		local ip = (port.ip and port.ip ~= "0.0.0.0" and port.ip ~= "::") and (port.ip .. ":") or ""
		text:child(T(ip .. port.public, "foreground", SIZE.small + 1, 700):no_shrink())
		text:child(T(" → ", "quiet", SIZE.small + 1):no_shrink())
	else
		text:child(T("not published · ", "quiet", SIZE.small + 1):no_shrink())
	end
	text:child(T(port.private .. "/" .. port.type, "foreground", SIZE.small + 1):no_shrink())
	row:child(text)
	if port.public then
		local id = "port:" .. port.public
		row:child(
			P.button("copyport:" .. port.public, nil, { variant = "ghost", size = "sm", icon = "copy", icon_size = 12 })
		)
		row:child(P.button(id, "Open", { variant = "ghost", size = "sm", icon = "external-link", icon_size = 12 }))
	end
	return row
end

-- The overview: what the container uses, what is wrong with it, what it is made of.
local function overview(c, w)
	local data = detail_data()
	local width = w - 28
	local body = b.div():col():gap(16):px(14):pt(12):pb(18):no_shrink()
	if data ~= nil then
		local role, text = problem_of(c, data)
		if role then
			body:child(callout(role, text, w))
		end
	end
	if c.state == "running" then
		body:child(usage_cards(c, w, data))
	end
	if data == nil then
		local slot = S.details[c.id]
		body:child(
			T(slot and slot.error or "Reading the container…", slot and slot.error and "error" or "quiet", SIZE.small)
		)
		return body
	end
	if #data.ports > 0 then
		local section = b.div():col():gap(4)
		section:child(section_title("Ports"))
		for _, port in ipairs(data.ports) do
			section:child(port_row(port, width))
		end
		body:child(section)
	end
	local facts = b.div():col():gap(6)
	facts:child(section_title("Container"))
	facts:child(kv("image", data.image, width))
	local command = table.concat(data.entrypoint, " ")
	command = command .. ((command ~= "" and #data.cmd > 0) and " " or "") .. table.concat(data.cmd, " ")
	facts:child(kv("command", command ~= "" and command or "–", width, nil, nil, 3))
	facts:child(kv("created", data.created_label or "–", width))
	if data.state.running then
		facts:child(
			kv(
				"started",
				b.div()
					:row()
					:gap(6)
					:child(T(data.state.started_label or "–", "foreground", SIZE.small + 1))
					:child(T("(" .. (ago_long(data.state.started_at) or "–") .. ")", "quiet", SIZE.small + 1)),
				width
			)
		)
	else
		facts:child(kv("finished", data.state.finished_label or "–", width))
	end
	facts:child(
		kv(
			"restarts",
			b.div()
				:row()
				:gap(6)
				:child(T(tostring(data.restart_count), "foreground", SIZE.small + 1))
				:child(T("· policy " .. data.restart_policy, "quiet", SIZE.small + 1)),
			width
		)
	)
	if data.working_dir ~= "" then
		facts:child(kv("working dir", data.working_dir, width))
	end
	if data.user ~= "" then
		facts:child(kv("user", data.user, width))
	end
	local platform = b.div()
		:row()
		:items_center()
		:gap(6)
		:child(T(data.platform ~= "" and data.platform or "–", "foreground", SIZE.small + 1))
	if data.privileged then
		platform:child(P.tag("privileged", "warning"))
	end
	facts:child(kv("platform", platform, width))
	if data.memory_limit > 0 or data.cpu_limit > 0 then
		facts:child(
			kv(
				"limits",
				(data.memory_limit > 0 and (fmt.memory(data.memory_limit) .. " memory") or "")
					.. (data.memory_limit > 0 and data.cpu_limit > 0 and " · " or "")
					.. (data.cpu_limit > 0 and (data.cpu_limit .. " cpus") or ""),
				width
			)
		)
	end
	body:child(facts)
	if #data.networks > 0 then
		local section = b.div():col():gap(4)
		section:child(section_title("Networks"))
		for _, network in ipairs(data.networks) do
			local row = plain_row()
			row:child(P.icon("network", 13, "quiet"))
			row:child(b.div():min_w(0):child(P.line(network.name, "foreground", SIZE.small + 1, 700)))
			row:child(
				b.div():grow(1):min_w(0):child(
					network.ip ~= "" and P.line(network.ip, "foreground", SIZE.small + 1)
						or P.line("no address", "quiet", SIZE.small + 1)
				)
			)
			if #network.aliases > 0 then
				row:child(
					b.div()
						:max_w(width * 0.4)
						:min_w(0)
						:child(P.line(table.concat(network.aliases, ", "), "quiet", SIZE.small + 1))
				)
			end
			section:child(row)
		end
		body:child(section)
	end
	if #data.mounts > 0 then
		local section = b.div():col():gap(4)
		section:child(section_title("Mounts"))
		for _, mount in ipairs(data.mounts) do
			local row = plain_row()
			row:child(P.tag(mount.type, mount.type == "volume" and "info" or nil))
			local named = (mount.name and mount.type == "volume")
					and (#mount.name == 64 and string.sub(mount.name, 1, 12) or mount.name)
				or mount.source
			row:child(
				b.div()
					:grow(1)
					:min_w(0)
					:row()
					:items_center()
					:child(P.line(named, "foreground", SIZE.small + 1):min_w(0))
					:child(T(" → ", "quiet", SIZE.small + 1):no_shrink())
					:child(P.line(mount.destination, "foreground", SIZE.small + 1):min_w(0))
			)
			if not mount.rw then
				row:child(P.tag("read-only"))
			end
			section:child(row)
		end
		body:child(section)
	end
	if data.state.health then
		local section = b.div():col():gap(4)
		section:child(section_title("Health checks", "heart-pulse"))
		for index = #data.state.health.log, 1, -1 do
			local entry = data.state.health.log[index]
			local row = plain_row():items_start()
			row:child(
				P.tag(
					entry.exit_code == 0 and "pass" or ("exit " .. entry.exit_code),
					entry.exit_code == 0 and "success" or "error"
				)
			)
			local output = entry.output ~= "" and entry.output or nil
			row:child(
				b.div():grow(1):min_w(0):child(
					output and P.paragraph(output, width - 160, "foreground", SIZE.small + 0.5, nil, 4)
						or T("no output", "quiet", SIZE.small + 0.5)
				)
			)
			row:child(T(ago_long(entry["end"]) or "", "quiet", SIZE.small):no_shrink())
			section:child(row)
		end
		body:child(section)
	end
	local keys = {}
	for key in pairs(data.labels) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	if #keys > 0 then
		local section = b.div():col():gap(6)
		section:child(
			section_title(
				"Labels",
				nil,
				P.button("d:labels", S.show_labels and "Hide" or ("Show " .. #keys), { variant = "ghost", size = "sm" })
			)
		)
		if S.show_labels then
			-- The keys' column is as wide as the longest key, as far as a share of the panel.
			local longest = 0
			for _, key in ipairs(keys) do
				longest = math.max(longest, utf8.len(key) or #key)
			end
			local label_w = math.floor(math.max(92, math.min((longest + 1) * (SIZE.small + 1) * 0.62, width * 0.45)))
			for index, key in ipairs(keys) do
				if index > LABELS_MOST then
					section:child(T("and " .. (#keys - LABELS_MOST) .. " more", "quiet", SIZE.small))
					break
				end
				section:child(kv(key, data.labels[key], width, nil, label_w))
			end
		end
		body:child(section)
	end
	return body
end

-- The environment: the variables, with what looks secret hidden until asked for.
local function environment(c, w)
	local data = detail_data()
	local body = b.div():col():gap(10):px(14):pt(12):pb(18):no_shrink()
	if data == nil then
		return body:child(T("Reading the container…", "quiet", SIZE.small))
	end
	local query = (S.field == "env" and S.query) or ""
	local secrets = 0
	local list = {}
	for _, entry in ipairs(data.env) do
		if secret_like(entry.key, entry.value) and entry.value ~= "" then
			secrets += 1
		end
		if query == "" or fmt.has(entry.key .. "=" .. entry.value, query) then
			list[#list + 1] = entry
		end
	end
	local bar = b.div():row():items_center():gap(6):no_shrink()
	bar:child(P.field(S.field == "env", "Find a variable", 220))
	bar:child(b.spacer())
	if secrets > 0 then
		bar:child(P.button("d:secrets", S.show_secrets and "Hide" or ("Reveal " .. secrets), {
			variant = "ghost",
			size = "sm",
			icon = S.show_secrets and "eye-off" or "eye",
			icon_size = 13,
		}))
	end
	body:child(bar)
	if #data.env == 0 then
		return body:child(P.nothing("No environment", nil, "eye", w))
	end
	local key_width = math.floor((w - 28) * 0.38)
	local rows = b.div():col():no_shrink()
	for index, entry in ipairs(list) do
		if index > ENV_MOST then
			rows:child(T("and " .. (#list - ENV_MOST) .. " more", "quiet", SIZE.small):mt(4))
			break
		end
		local secret = secret_like(entry.key, entry.value) and entry.value ~= ""
		local shown = not secret or S.show_secrets or S.revealed_env[entry.key]
		local value
		if shown then
			if entry.value == "" then
				value = T("empty", "quiet", SIZE.small + 1)
			else
				local text = entry.value
				if #text > 1200 then
					text = string.sub(text, 1, 1200) .. "…"
				end
				value = T(text, "foreground", SIZE.small + 1):wrap():min_w(0)
			end
		else
			value = T("••••••••", "quiet", SIZE.small + 1)
		end
		local id = (secret and "env:" or "envcopy:") .. entry.key
		-- A row of a table, as the first dockerpen's: cells 8 in, at least 32 high, on its middle.
		local row = b.div():row():items_center():min_h(32):no_shrink()
		row:child(b.div():w(key_width):px(8):no_shrink():child(P.line(entry.key, "info", SIZE.small + 1)))
		row:child(b.div():grow(1):min_w(0):px(8):py(6):child(value))
		row:child(b.div():w(34):no_shrink():row():justify_end():child(P.button(id, nil, {
			variant = "ghost",
			size = "sm",
			icon = secret and (shown and "eye-off" or "eye") or "copy",
			icon_size = 12,
		})))
		rows:child(row)
	end
	return body:child(rows)
end

-- The processes: what `docker top` says, refreshed while it is looked at.
local function processes_tab(c, w)
	local slot = S.processes
	local pad = b.div():col():px(8):pt(4):pb(16):no_shrink()
	if c.state ~= "running" and c.state ~= "paused" then
		return P.nothing("Not running", "A stopped container has no processes.", "cpu", w)
	end
	if slot.id == c.id and slot.error and slot.titles == nil then
		return P.nothing("Could not list the processes", slot.error, "triangle-alert", w)
	end
	if slot.id ~= c.id or slot.titles == nil then
		return pad:child(T("Looking at the processes…", "quiet", SIZE.small):px(6))
	end
	local command = nil
	local tracks = {}
	for index, title in ipairs(slot.titles) do
		if string.find(title, "CMD") or string.find(title, "COMMAND") then
			command = index
			tracks[index] = b.range(120, 1)
		else
			tracks[index] = (title == "PID" or title == "PPID") and 64 or 76
		end
	end
	local function row_of(list, head)
		local row = b.div():grid(tracks):gap_x(10):items_center():h(head and 28 or 32):px(8):no_shrink()
		for index, text in ipairs(list) do
			row:child(
				P.line(
					text,
					head and "quiet" or "foreground",
					head and SIZE.tiny + 0.5 or SIZE.small + 1,
					head and 500 or nil
				)
			)
		end
		return row
	end
	local titles = {}
	for index, title in ipairs(slot.titles) do
		titles[index] = string.upper(title)
	end
	pad:child(row_of(titles, true))
	pad:child(b.div():h(1):bg(alpha("border", 0.6)):no_shrink())
	pad:child(b.div():h(6):no_shrink())
	for index, row in ipairs(slot.rows) do
		if index > PROCESSES_MOST then
			pad:child(T("and " .. (#slot.rows - PROCESSES_MOST) .. " more", "quiet", SIZE.small):mt(4):px(8))
			break
		end
		pad:child(row_of(row, false))
	end
	return pad
end

-- The colour of a value of the engine's answer, as the first dockerpen's: strings green, numbers
-- amber, true and false red, null quiet, the rest (braces, brackets) as the words are.
local function value_role(value)
	if string.sub(value, 1, 1) == '"' then
		return "success"
	elseif string.match(value, "^%-?%d") then
		return "warning"
	elseif string.match(value, "^true") or string.match(value, "^false") then
		return "error"
	elseif string.match(value, "^null") then
		return "quiet"
	end
	return "foreground"
end

-- One line of the engine's answer, with the parts of it a person looks for in their own colours.
local function inspect_line(text)
	local indent, key, colon, value = string.match(text, '^(%s*)("[^"]*")(:%s*)(.*)$')
	if key == nil then
		local indent_only, rest = string.match(text, "^(%s*)(.*)$")
		return b.div()
			:row()
			:child(T(indent_only, "foreground", SIZE.small + 1):no_shrink())
			:child(T(rest, value_role(rest), SIZE.small + 1):truncate())
	end
	return b.div()
		:row()
		:child(T(indent .. key, "info", SIZE.small + 1):no_shrink())
		:child(T(colon, "foreground", SIZE.small + 1):no_shrink())
		:child(T(value, value_role(value), SIZE.small + 1):truncate())
end

local function inspect_tab(c)
	local data = detail_data()
	if data == nil then
		return b.div():px(14):pt(12):child(T("Reading the container…", "quiet", SIZE.small))
	end
	local lines = data.lines
	local box = b.div():col():grow(1):min_h(0)
	box:child(virtual("detail.inspect", #lines, 19, function(index)
		return b.div():h(19):no_shrink():row():items_center():child(inspect_line(lines[index]))
	end, { px = 14, pt = 12 }))
	-- The button floats over the answer, at its top right, as it did.
	box:child(
		b.div()
			:absolute()
			:inset(8, 10, nil, nil)
			:child(P.button("d:copyjson", "Copy", { size = "sm", icon = "copy", icon_size = 12 }))
	)
	return box
end

-- ---- the detail, as a whole --------------------------------------------------------------------------

-- The tabs of the detail, as the first dockerpen drew them: the words in the second colour, the
-- one on show in the first, with the accent under it a little in from its ends.
local function detail_tabs(current)
	local row = b.div():row():items_end():gap(2):px(10):h(34):no_shrink()
	for _, tab in ipairs(TABS) do
		local id = "tab:" .. tab.id
		local active = tab.id == current
		row:child(
			b.div()
				:press(id)
				:col()
				:justify_end()
				:h(34)
				:no_shrink()
				:child(
					b.div()
						:grow(1)
						:row()
						:items_center()
						:px(9)
						:child(T(tab.label, (active or lit(hover_glow(id))) and "foreground" or "dim", SIZE.body))
				)
				:child(b.div():h(2):ml(6):mr(6):rounded_corners({ 2, 2, 0, 0 }):bg(active and "accent" or nil))
		)
	end
	return row
end

function screens.detail(width, beside)
	local c = container(S.open)
	if c == nil then
		return b.div():grow(1)
	end
	local word, role = state_of(c)
	local panel = b.div():col():grow(1):min_w(0):min_h(0)
	local head = b.div():row():items_center():gap(9):h(40):px(14):pt(4):no_shrink()
	head:child(P.dot(c))
	head:child(b.div():grow(1):min_w(0):child(P.line(c.name, "foreground", 14, 650)))
	head:child(P.button("d:close", nil, { variant = "ghost", size = "sm", icon = "x", icon_size = 14 }))
	panel:child(head)
	local sub = b.div():row():items_center():gap(8):px(14):h(24):no_shrink():clip()
	sub:child(P.tag(word, role ~= "dim" and role or nil))
	sub:child(T(fmt.image_name(c.image), "dim", SIZE.small + 0.5):truncate():min_w(0))
	local copy_lit = lit(hover_glow("d:copyid"))
	sub:child(
		b.div()
			:row()
			:items_center()
			:gap(5)
			:press("d:copyid")
			:no_shrink()
			:child(T(c.short, copy_lit and "foreground" or "dim", SIZE.small))
			:child(P.icon("copy", 11, copy_lit and "foreground" or "quiet"))
	)
	if c.project then
		sub:child(
			T(c.project .. (c.service and (" / " .. c.service) or ""), "quiet", SIZE.small + 0.5):truncate():min_w(0)
		)
	end
	panel:child(sub)
	panel:child(b.div():h(8):no_shrink())
	panel:child(verbs_row(c, width < 360))
	panel:child(b.div():h(4):no_shrink())
	panel:child(detail_tabs(S.tab))
	panel:child(b.div():h(1):bg(alpha("border", 0.6)):no_shrink())
	if S.tab == "logs" then
		return panel:child(log_tab(c, width))
	elseif S.tab == "inspect" then
		return panel:child(inspect_tab(c))
	end
	local content
	if S.tab == "env" then
		content = environment(c, width)
	elseif S.tab == "processes" then
		content = processes_tab(c, width)
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
