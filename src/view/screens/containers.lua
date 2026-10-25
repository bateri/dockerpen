local lib_kit = require("../lib/kit")
local lib_fmt = require("../lib/fmt")
local lib_sizes = require("../lib/sizes")
local lib_virtual = require("../lib/virtual")
local model_containers = require("../model/containers")
local model_rows = require("../model/rows")
local model_state = require("../model/state")
local parts_ui = require("../parts/ui")
local alpha, b = lib_kit.alpha, lib_kit.b
local fmt = lib_fmt.fmt
local FILTERS, LIST_MEDIUM, LIST_WIDE, SIZE =
	lib_sizes.FILTERS, lib_sizes.LIST_MEDIUM, lib_sizes.LIST_WIDE, lib_sizes.SIZE
local virtual = lib_virtual.virtual
local is_up, state_of = model_containers.is_up, model_containers.state_of
local container_rows, counts = model_rows.container_rows, model_rows.counts
local S = model_state.S
local P, T, hovered = parts_ui.P, parts_ui.T, parts_ui.hovered

local screens = {}

-- ---- the containers ----------------------------------------------------------------------------

local screens = {}

-- The columns of the list of containers that fit `width`.
local function columns(width)
	return {
		image = width >= LIST_MEDIUM,
		cpu = width >= LIST_MEDIUM + 40,
		memory = width >= LIST_WIDE,
		ports = width >= LIST_WIDE + 200,
	}
end

local COL = { check = 14, dot = 9, state = 108, cpu = 108, memory = 78, age = 70, verb = 66 }

-- The cells a row of the list of containers is made of, from a function that makes each.
local function cells(cols, make)
	local list = {}
	list[#list + 1] = make.check()
	list[#list + 1] = make.dot()
	list[#list + 1] = make.name()
	if cols.image then
		list[#list + 1] = make.image()
	end
	list[#list + 1] = make.state()
	if cols.cpu then
		list[#list + 1] = make.cpu()
	end
	if cols.memory then
		list[#list + 1] = make.memory()
	end
	list[#list + 1] = make.age()
	list[#list + 1] = make.verb()
	return list
end

local function header_row(cols)
	local function label(text, width, grow, align)
		local cell = b.div():no_shrink()
		if width then
			cell:w(width)
		else
			cell:w(0):grow(grow):min_w(40):no_shrink()
		end
		return cell:child(T(text, "quiet", SIZE.tiny + 0.5, 600):align(align or "start"):truncate())
	end
	local row = b.div():row():items_center():gap(10):h(24):px(18):no_shrink()
	for _, cell in
		ipairs(cells(cols, {
			check = function()
				return b.div():w(COL.check):no_shrink()
			end,
			dot = function()
				return b.div():w(COL.dot):no_shrink()
			end,
			name = function()
				return label("NAME", nil, 1.5)
			end,
			image = function()
				return label("IMAGE", nil, 1.2)
			end,
			state = function()
				return label("STATE", COL.state)
			end,
			cpu = function()
				return label("CPU", COL.cpu)
			end,
			memory = function()
				return label("MEMORY", COL.memory, nil, "end")
			end,
			age = function()
				return label("UP", COL.age, nil, "end")
			end,
			verb = function()
				return b.div():w(COL.verb):no_shrink()
			end,
		}))
	do
		row:child(cell)
	end
	return row
end

-- One container of the list.
local function container_row(row, cols)
	local c = row.c
	local id = "row:" .. c.id
	local verb_id = "verb:" .. c.id
	local cursor = S.cursor.containers == c.id
	local over = hovered(id) or hovered(verb_id) or hovered("mark:" .. c.id)
	local word, role = state_of(c)
	local sample = S.samples[c.short]
	local series = S.series[c.short]
	local marked_on = S.marks.containers and S.marks.containers[c.id]
	local el = b.div():press(id):row():items_center():gap(10):h(SIZE.row):px(10):rounded(7):no_shrink()
	if cursor then
		el:bg(alpha("accent", S.focus == "list" and 0.14 or 0.08))
			:border(1, alpha("accent", S.focus == "list" and 0.55 or 0.3))
	elseif over then
		el:bg(alpha("foreground", 0.055))
	end
	local up = is_up(c)
	for _, cell in
		ipairs(cells(cols, {
			check = function()
				local cell = b.div():press("mark:" .. c.id):w(COL.check):no_shrink()
				if marked_on or over or cursor or S.any_marked then
					cell:child(P.check(marked_on))
				end
				return cell
			end,
			dot = function()
				return b.div():w(COL.dot):no_shrink():child(P.state_dot(c))
			end,
			name = function()
				return b.div()
					:w(0)
					:grow(1.5)
					:min_w(60)
					:row()
					:items_center()
					:gap(8)
					:child(P.line(c.name, up and "foreground" or "dim", SIZE.body, 600))
			end,
			image = function()
				return b.div():w(0):grow(1.2):min_w(40):child(P.line(c.image, "dim", SIZE.small + 0.5))
			end,
			state = function()
				return b.div()
					:w(COL.state)
					:no_shrink()
					:child(P.line(word, role, SIZE.small + 0.5, c.state == "running" and 400 or 500))
			end,
			cpu = function()
				local cell = b.div():w(COL.cpu):no_shrink():row():items_center():gap(8)
				if sample and c.state == "running" then
					cell:child(
						b.div()
							:w(48)
							:h(16)
							:no_shrink()
							:child(P.spark(series and series.cpu or {}, "accent", math.max(100, sample.cpu)))
					)
					cell:child(
						b.div()
							:w(48)
							:no_shrink()
							:child(T(fmt.percent(sample.cpu), "foreground", SIZE.small + 0.5):align("end"))
					)
				else
					cell:child(T("–", "quiet", SIZE.small + 0.5))
				end
				return cell
			end,
			memory = function()
				local cell = b.div():w(COL.memory):no_shrink():row():justify_end()
				if sample and c.state == "running" then
					cell:child(T(fmt.bytes(sample.memory), "foreground", SIZE.small + 0.5))
				else
					cell:child(T("–", "quiet", SIZE.small + 0.5))
				end
				return cell
			end,
			age = function()
				return b.div()
					:w(COL.age)
					:no_shrink()
					:row()
					:justify_end()
					:child(P.line(fmt.status(c.status), "dim", SIZE.small + 0.5):align("end"))
			end,
			verb = function()
				local cell = b.div():w(COL.verb):no_shrink():row():justify_end()
				if cursor or over then
					local label = up and "Stop" or "Start"
					if S.busy[c.id] then
						label = "…"
					end
					cell:child(
						P.button(
							verb_id,
							label,
							{ h = 22, px = 8, size = SIZE.small + 0.5, disabled = S.busy[c.id] ~= nil }
						)
					)
				end
				return cell
			end,
		}))
	do
		el:child(cell)
	end
	return el
end

-- The row that heads a compose project.
local function group_row(group)
	local id = "row:" .. group.id
	local cursor = S.cursor.containers == group.id
	local over = hovered(id)
	local el = b.div():press(id):row():items_center():gap(8):h(SIZE.row):px(12):rounded(7):no_shrink()
	if cursor then
		el:bg(alpha("accent", S.focus == "list" and 0.12 or 0.07)):border(1, alpha("accent", 0.5))
	elseif over then
		el:bg(alpha("foreground", 0.05))
	end
	el:child(T(group.folded and "▸" or "▾", "dim", SIZE.body):w(14):no_shrink())
	el:child(T(group.name, group.key == "" and "dim" or "foreground", SIZE.body + 0.5, 650):no_shrink())
	el:child(T(group.up .. "/" .. #group.members .. " up", "dim", SIZE.small + 0.5):no_shrink())
	if group.issues > 0 then
		el:child(P.tag(group.issues .. " with " .. (group.issues == 1 and "an issue" or "issues"), "error"))
	end
	el:child(b.spacer())
	if cursor or over or hovered("verb:" .. group.id) then
		el:child(
			P.button(
				"verb:" .. group.id,
				group.up > 0 and "Stop all" or "Start all",
				{ h = 22, px = 8, size = SIZE.small + 0.5 }
			)
		)
	end
	local marks = b.div():row():gap(2):items_center():no_shrink()
	for index, c in ipairs(group.members) do
		if index > 14 then
			break
		end
		local _, role = state_of(c)
		marks:child(b.div():size(5, 12):rounded(2):bg(is_up(c) and role or alpha("foreground", 0.2)))
	end
	return el:child(marks)
end

-- The line above the list: the filter, the states, grouping.
local function filter_bar(width)
	local count = counts()
	local bar = b.div():row():items_center():gap(8):h(SIZE.bar):px(20):no_shrink()
	bar:child(P.field(S.field == "list", "Filter by name, image, port…", width >= 700 and 260 or nil))
	local chips = b.div():row():items_center():gap(2):no_shrink():p(2):rounded(7):bg("raised1")
	for _, f in ipairs(FILTERS) do
		local id = "filter:" .. f.id
		local active = S.filter == f.id
		local n = count[f.id]
		local label = b.div():row():items_center():gap(5):h(24):px(9):rounded(5):press(id):no_shrink()
		if active then
			label:bg("raised3")
		elseif hovered(id) then
			label:bg(alpha("foreground", 0.06))
		end
		label:child(T(f.label, active and "foreground" or "dim", SIZE.small + 1, active and 600 or 400))
		local role = (f.id == "issues" and n > 0) and "error" or "quiet"
		label:child(T(tostring(n), role, SIZE.tiny + 0.5))
		chips:child(label)
	end
	bar:child(chips)
	bar:child(b.spacer())
	if width >= 760 then
		bar:child(
			P.button(
				"group",
				S.group and "Grouped" or "Flat",
				{ selected = S.group, key = "P", h = 24, size = SIZE.small + 0.5 }
			)
		)
		bar:child(P.button("sort", "Sort: " .. S.sort, { key = "o", h = 24, size = SIZE.small + 0.5 }))
	end
	return bar
end

-- Why there is nothing to list.
local function nothing_listed(rows_shown)
	if S.failure and #S.containers == 0 then
		local hint = S.failure.code == "docker-missing"
				and "dockerpen runs the docker command. Install Docker, or put docker on the PATH."
			or "Start Docker (or OrbStack, Colima, Podman…) and dockerpen carries on by itself."
		return P.nothing(
			S.failure.code == "docker-missing" and "There is no docker command" or "Docker is not reachable",
			hint
		)
			:child(T(S.failure.message, "quiet", SIZE.small):truncate():max_w(560):mt(6))
	end
	if #S.containers == 0 then
		if not S.known then
			return P.nothing("Looking for containers…")
		end
		return P.nothing(
			"There are no containers",
			"Start one with docker run, or docker compose up, and it shows here."
		)
	end
	if S.query ~= "" then
		return P.nothing(
			"No container matches “" .. S.query .. "”",
			"Change the filter, or select what is in the field and type another."
		)
	end
	return P.nothing("No " .. string.lower(S.filter) .. " containers", "Press f to look at another kind.")
end

-- The list of containers: the bar, the heads of the columns, the rows.
function screens.list(width)
	local rows, shown = container_rows()
	local cols = columns(width)
	local count = counts()
	local col = b.div():col():grow(1):min_w(0):min_h(0)
	local bits = { count.running .. " running", count.all .. " total" }
	col:child(P.title("Containers", table.concat(bits, " · "), {
		P.button("act:pull", "Pull…", { key = "u" }),
		P.button("act:clean", "Clean up…", { key = "c" }),
	}))
	col:child(filter_bar(width))
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
	col:child(header_row(cols))
	col:child(virtual("list", #rows, SIZE.row, function(index)
		local row = rows[index]
		if row.kind == "group" then
			return group_row(row)
		end
		return container_row(row, cols)
	end, { px = 10 }))
	return col
end

return {
	COL = COL,
	columns = columns,
	screens = screens,
}
