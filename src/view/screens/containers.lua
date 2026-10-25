-- The containers: a list of them, grouped by compose project, with the detail of one beside it.

local lib_fmt = require("../lib/fmt")
local lib_kit = require("../lib/kit")
local lib_sizes = require("../lib/sizes")
local lib_virtual = require("../lib/virtual")
local model_containers = require("../model/containers")
local model_rows = require("../model/rows")
local model_state = require("../model/state")
local parts_toolbar = require("../parts/toolbar")
local parts_ui = require("../parts/ui")
local alpha, b = lib_kit.alpha, lib_kit.b
local fmt = lib_fmt.fmt
local LIST_MEDIUM, LIST_NARROW, LIST_WIDE, SIZE =
	lib_sizes.LIST_MEDIUM, lib_sizes.LIST_NARROW, lib_sizes.LIST_WIDE, lib_sizes.SIZE
local virtual = lib_virtual.virtual
local display_name, has_issue, is_up, state_of =
	model_containers.display_name, model_containers.has_issue, model_containers.is_up, model_containers.state_of
local container_rows, counts, row_tops = model_rows.container_rows, model_rows.counts, model_rows.row_tops
local S = model_state.S
local P, T, chosen, hovered = parts_ui.P, parts_ui.T, parts_ui.chosen, parts_ui.hovered

local screens = {}

-- What the list shows for the room it has: the columns that fit, and the tracks they take.
local function layout(width)
	if width >= LIST_WIDE then
		return {
			image = true,
			memory = true,
			ports = true,
			tags = true,
			tracks = { 18, b.range(120, 1.5), b.range(90, 1), 96, 110, b.range(64, 0.8), 128 },
		}
	elseif width >= LIST_MEDIUM then
		return {
			image = true,
			memory = true,
			tags = true,
			tracks = { 18, b.range(120, 1.5), b.range(80, 1), 96, 110, 128 },
		}
	elseif width >= LIST_NARROW then
		return { memory = true, tracks = { 18, b.range(100, 1), 96, 110, 128 } }
	end
	return { tracks = { 18, b.range(90, 1), 96, 128 } }
end

-- A row of the list is a grid of these, in this order: the dot, the name, the image, what it takes of
-- the cpu, of the memory, the ports it publishes, how long it has been as it is.
local function row_grid(l, height)
	return b.div():grid(l.tracks):gap_x(10):items_center():h(height)
end

-- One column of the head of the list: the word, and a way to sort by it.
local function head_cell(label, how, align)
	local cell = b.div():row():items_center():gap(3):min_w(0)
	if align == "end" then
		cell:justify_end()
	end
	local active = how ~= nil and S.sort == how
	local over = how ~= nil and hovered("sorth:" .. how)
	if how then
		cell:press("sorth:" .. how)
	end
	cell:child(T(label, (active or over) and "dim" or "quiet", SIZE.tiny + 0.5, 500):truncate())
	if active then
		cell:child(P.icon("chevron-down", 11, "dim"))
	end
	return cell
end

local function header_row(l)
	local row = row_grid(l, 28):px(16):no_shrink()
	row:child(b.div())
	row:child(head_cell("NAME", "name"))
	if l.image then
		row:child(head_cell("IMAGE"))
	end
	row:child(head_cell("CPU", "cpu"))
	if l.memory then
		row:child(head_cell("MEMORY", "memory"))
	end
	if l.ports then
		row:child(head_cell("PORTS"))
	end
	row:child(head_cell("STATUS", "state", "end"))
	return b.div():col():no_shrink():child(row):child(b.div():h(1):bg(alpha("border", 0.6)))
end

-- The look of a row that has the cursor, the pointer, or a mark.
local function frame_of(el, cursor, over, marked_on)
	if cursor then
		if S.focus == "list" then
			chosen(el, true)
		else
			el:bg(alpha("foreground", 0.07)):border(1, alpha("border", 0.9))
		end
	elseif marked_on then
		el:bg(alpha("accent", 0.09))
	elseif over then
		el:bg(alpha("foreground", 0.06))
	end
	return el
end

-- The tag beside a name, where the state is news: what is wrong, what is being done.
local function name_tag(c)
	local busy = S.busy[c.id]
	if busy then
		return P.tag(busy .. "…", "accent")
	end
	local word, role = state_of(c)
	if role == "error" or role == "warning" then
		return P.tag(word, role)
	end
	return nil
end

local function cpu_cell(c, sample, series)
	local cell = b.div():row():items_center():justify_end():gap(8):min_w(0)
	if sample and c.state == "running" then
		cell:child(b.div():w(44):h(14):no_shrink():child(P.spark(series and series.cpu or {}, "accent")))
		cell:child(
			b.div():w(42):no_shrink():child(T(fmt.percent(sample.cpu), "foreground", SIZE.small + 1):align("end"))
		)
	else
		cell:child(T("–", "quiet", SIZE.small + 1))
	end
	return cell
end

-- The most memory any running container takes now: what the others are measured against.
local function memory_peak()
	local peak = 1
	for _, sample in pairs(S.samples) do
		peak = math.max(peak, sample.memory or 0)
	end
	return peak
end

local function memory_cell(c, sample, peak)
	local cell = b.div():row():items_center():justify_end():gap(8):min_w(0)
	if sample and c.state == "running" then
		-- A container with a limit of its own is measured against it; the rest against each other.
		local host = S.engine and S.engine.memory or 0
		local limit = sample.memory_limit or 0
		local limited = limit > 0 and (host == 0 or limit < host * 0.95)
		local share = limited and sample.memory / limit or sample.memory / peak
		local role = "quiet"
		if limited then
			role = share > 0.85 and "error" or (share > 0.65 and "warning" or "quiet")
		end
		cell:child(P.meter(share, role))
		cell:child(
			b.div()
				:w(54)
				:no_shrink()
				:child(T(fmt.memory_tight(sample.memory), "foreground", SIZE.small + 1):align("end"))
		)
	else
		cell:child(T("–", "quiet", SIZE.small + 1))
	end
	return cell
end

local function ports_cell(c)
	local cell = b.div():row():items_center():gap(4):min_w(0):clip()
	local published = {}
	for _, port in ipairs(c.ports or {}) do
		if port.public then
			published[#published + 1] = port
		end
	end
	for index, port in ipairs(published) do
		if index > 2 then
			break
		end
		cell:child(
			b.div()
				:row()
				:items_center()
				:h(20)
				:px(6)
				:rounded(4)
				:bg(alpha("info", 0.11))
				:no_shrink()
				:child(T(":" .. port.public, "info", SIZE.small))
		)
	end
	if #published > 2 then
		cell:child(T("+" .. (#published - 2), "quiet", SIZE.small))
	end
	return cell
end

-- The verbs of a row, as icons: stop or start, restart, logs, a shell, more.
local function row_verbs(c, up)
	local busy = S.busy[c.id] ~= nil
	local row = b.div():row():items_center():justify_end():gap(2)
	row:child(P.button("ra:toggle:" .. c.id, nil, {
		variant = "ghost",
		size = "sm",
		icon = up and "square" or "play",
		icon_size = up and 12 or 13,
		disabled = busy,
	}))
	row:child(P.icon_button("ra:restart:" .. c.id, "rotate-cw", { disabled = busy }))
	row:child(P.icon_button("ra:logs:" .. c.id, "scroll-text"))
	row:child(P.icon_button("ra:shell:" .. c.id, "square-terminal", { disabled = c.state ~= "running" }))
	row:child(P.icon_button("ra:more:" .. c.id, "ellipsis", { icon_size = 13 }))
	return row
end

-- One container of the list.
local function container_row(row, l, peak)
	local c = row.c
	local id = "row:" .. c.id
	local cursor = S.cursor.containers == c.id
	local marked_on = S.marks.containers and S.marks.containers[c.id]
	local over = hovered(id)
	for _, name in ipairs({ "toggle", "restart", "logs", "shell", "more" }) do
		over = over or hovered("ra:" .. name .. ":" .. c.id)
	end
	local up = is_up(c)
	local sample = S.samples[c.short]
	local series = S.series[c.short]
	local el = frame_of(row_grid(l, SIZE.row):px(8):rounded(6):press(id):no_shrink(), cursor, over, marked_on)
	-- The dot, or, where something is marked, a box to mark with.
	if S.any_marked then
		el:child(b.div():press("mark:" .. c.id):row():justify_center():child(P.check(marked_on)))
	else
		el:child(b.div():row():justify_center():child(P.dot(c)))
	end
	local quiet_name = c.state == "exited" or c.state == "created" or c.state == "dead"
	local name = b.div():row():items_center():gap(8):min_w(0)
	if row.grouped then
		name:pl(14)
	end
	name:child(
		T(display_name(c, row.grouped), quiet_name and "dim" or "foreground", SIZE.body, quiet_name and 500 or 600)
			:truncate()
			:min_w(0)
	)
	if not row.grouped and c.project then
		name:child(P.tag(c.project))
	end
	if l.tags then
		local tag = name_tag(c)
		if tag then
			name:child(tag)
		end
	end
	el:child(name)
	if l.image then
		el:child(P.line(fmt.image_name(c.image), "dim", SIZE.small + 1))
	end
	el:child(cpu_cell(c, sample, series))
	if l.memory then
		el:child(memory_cell(c, sample, peak))
	end
	if l.ports then
		el:child(ports_cell(c))
	end
	if cursor or over then
		el:child(row_verbs(c, up))
	else
		el:child(
			b.div():row():justify_end():min_w(0):child(P.line(fmt.status(c.status), "dim", SIZE.small + 1):align("end"))
		)
	end
	return el
end

-- The row that heads a compose project: whether it is open, its name, a bar for each of its
-- containers, how many are up, and, where the pointer is, what can be done to all of them.
local function group_row(group, first)
	local id = "row:" .. group.id
	local cursor = S.cursor.containers == group.id
	local over = hovered(id) or hovered("ga:toggle:" .. group.key) or hovered("ga:restart:" .. group.key)
	local el = frame_of(
		b.div():press(id):row():items_center():gap(8):h(SIZE.row):px(8):rounded(6):no_shrink(),
		cursor,
		over,
		false
	)
	el:child(
		b.div()
			:w(18)
			:no_shrink()
			:row()
			:justify_center()
			:child(P.icon(group.folded and "chevron-right" or "chevron-down", 14, "dim"))
	)
	el:child(T(group.name, "foreground", SIZE.title, 650):no_shrink())
	el:child(P.stack(group.members, function(c)
		if has_issue(c) then
			return "error"
		elseif is_up(c) then
			return "success"
		end
		return alpha("quiet", 0.4)
	end))
	local words = group.up .. "/" .. group.total .. " up"
	if group.issues > 0 then
		words = words .. " · " .. group.issues .. " with " .. (group.issues == 1 and "an issue" or "issues")
	end
	el:child(T(words, "quiet", SIZE.small + 0.5):no_shrink())
	el:child(b.spacer())
	if group.key ~= "" and (cursor or over) then
		el:child(
			P.icon_button(
				"ga:toggle:" .. group.key,
				group.up > 0 and "square" or "play",
				{ icon_size = group.up > 0 and 12 or 13 }
			)
		)
		el:child(P.icon_button("ga:restart:" .. group.key, "rotate-cw"))
	end
	-- A gap above, except under the head of the list.
	if first then
		return el
	end
	return b.div():col():h(SIZE.row + 6):no_shrink():pt(6):child(el)
end

-- Why there is nothing to list.
local function nothing_listed(rows_shown)
	if S.failure and #S.containers == 0 then
		local hint = S.failure.code == "docker-missing"
				and "dockerpen runs the docker command. Install Docker, or put docker on the PATH."
			or "Start Docker (or OrbStack, Colima, Podman…) and dockerpen carries on by itself."
		return P.nothing(
			S.failure.code == "docker-missing" and "There is no docker command" or "Docker is not reachable",
			hint,
			"plug-zap"
		):child(T(S.failure.message, "quiet", SIZE.small):truncate():max_w(560):mt(6))
	end
	if #S.containers == 0 then
		if not S.known then
			return P.nothing("Looking for containers…")
		end
		return P.nothing(
			"There are no containers",
			"Start one with docker run, or docker compose up, and it shows here.",
			"boxes"
		)
	end
	if S.query ~= "" then
		return P.nothing(
			"No container matches “" .. S.query .. "”",
			"Change the filter, or select what is in the field and type another.",
			"search-x"
		)
	end
	return P.nothing("No " .. string.lower(S.filter) .. " containers", "Press f to look at another kind.", "boxes")
end

-- The list of containers: the title, the bar, the heads of the columns, the rows.
function screens.list(width)
	local rows, shown = container_rows()
	local l = layout(width)
	local count = counts()
	local col = b.div():col():grow(1):min_w(0):min_h(0)
	col:child(P.title("Containers", count.running .. " running · " .. count.all .. " total", {
		parts_toolbar.verb("act:pull", "Pull", "download", width),
		parts_toolbar.verb("act:clean", "Clean up", "sparkles", width),
	}))
	col:child(parts_toolbar.containers(width))
	if S.failure and #S.containers > 0 then
		col:child(
			b.div():row():items_center():gap(8):h(26):px(20):no_shrink():bg(alpha("error", 0.1)):child(
				T(
					"Docker is not reachable: " .. S.failure.message .. " — this is the list as it was.",
					"error",
					SIZE.small
				):truncate()
			)
		)
	end
	if #rows == 0 then
		col:child(nothing_listed(shown))
		return col
	end
	col:child(header_row(l))
	local peak = memory_peak()
	col:child(virtual("list", #rows, SIZE.row, function(index)
		local row = rows[index]
		if row.kind == "group" then
			return group_row(row, index == 1)
		end
		return container_row(row, l, peak)
	end, { px = 8, pt = 6, tops = row_tops("containers") }))
	return col
end

return {
	screens = screens,
}
