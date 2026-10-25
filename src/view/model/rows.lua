local lib_fmt = require("../lib/fmt")
local lib_sizes = require("../lib/sizes")
local model_containers = require("./containers")
local model_state = require("./state")
local fmt = lib_fmt.fmt
local SIZE = lib_sizes.SIZE
local has_issue, is_up = model_containers.has_issue, model_containers.is_up
local S = model_state.S

-- ---- the rows of the lists ----------------------------------------------------------------------

local SORTS = { "name", "state", "cpu", "memory", "created" }
local SORT_LABELS = { name = "Name", state = "State", cpu = "CPU", memory = "Memory", created = "Newest" }

local function sort_value(c, how)
	local sample = S.samples[c.short]
	if how == "cpu" then
		return -(sample and sample.cpu or -1)
	elseif how == "memory" then
		return -(sample and sample.memory or -1)
	elseif how == "created" then
		return -(c.created or 0)
	elseif how == "state" then
		return (c.state == "running" and 0 or (is_up(c) and 1 or 2)) * 10 + (has_issue(c) and 0 or 1)
	end
	return 0
end

local function container_matches(c, query)
	if query == "" then
		return true
	end
	if fmt.has(c.name, query) or fmt.has(c.image, query) or fmt.has(c.short, query) then
		return true
	end
	if c.project and fmt.has(c.project, query) then
		return true
	end
	if c.service and fmt.has(c.service, query) then
		return true
	end
	for _, port in ipairs(c.ports) do
		if port.public and fmt.has(tostring(port.public), query) or fmt.has(tostring(port.private), query) then
			return true
		end
	end
	return false
end

local function status_shows(c)
	if S.filter == "running" then
		return is_up(c)
	elseif S.filter == "stopped" then
		return not is_up(c)
	elseif S.filter == "issues" then
		return has_issue(c)
	end
	return true
end

-- Whether a project is folded: as the person left it. (A project with nothing running is folded
-- the first time the page sees it, by `on_containers`: from then on it is the person's.)
local function folded(group)
	return S.folded[group.key] == true
end

-- The containers as the rows of the list: a row for each project that has any (when grouped), and
-- a row for each of its containers that is not folded away. `{ kind = "group" | "container", ... }`.
local function container_rows()
	local cached = S.cache.containers
	if cached and cached.rev == S.rev then
		return cached.rows, cached.shown
	end
	local query = S.focus == "detail" and S.tab == "logs" and "" or S.query
	local list = {}
	for _, c in ipairs(S.containers) do
		if status_shows(c) and container_matches(c, query) then
			list[#list + 1] = c
		end
	end
	local how = S.sort
	table.sort(list, function(x, y)
		local vx, vy = sort_value(x, how), sort_value(y, how)
		if vx ~= vy then
			return vx < vy
		end
		return x.name < y.name
	end)
	local rows = {}
	-- A project is counted over all of its containers, whatever the filter shows of them.
	local whole = {}
	for _, c in ipairs(S.containers) do
		local key = c.project or ""
		local count = whole[key]
		if count == nil then
			count = { total = 0, up = 0, running = 0, issues = 0 }
			whole[key] = count
		end
		count.total += 1
		if is_up(c) then
			count.up += 1
		end
		if c.state == "running" then
			count.running += 1
		end
		if has_issue(c) then
			count.issues += 1
		end
	end
	if S.group then
		local groups, order = {}, {}
		for _, c in ipairs(list) do
			local key = c.project or ""
			local group = groups[key]
			if group == nil then
				local count = whole[key]
				group = {
					kind = "group",
					key = key,
					name = c.project or "Standalone",
					members = {},
					up = count.up,
					total = count.total,
					issues = count.issues,
				}
				groups[key] = group
				order[#order + 1] = group
			end
			group.members[#group.members + 1] = c
		end
		table.sort(order, function(x, y)
			if (x.key == "") ~= (y.key == "") then
				return y.key == ""
			end
			if (x.up > 0) ~= (y.up > 0) then
				return x.up > 0
			end
			return x.name < y.name
		end)
		-- A list that is only the containers of no project is not grouped.
		local only_standalone = #order == 1 and order[1].key == ""
		for _, group in ipairs(order) do
			group.id = "group:" .. group.key
			group.grouped = not only_standalone
			-- A search looks into the projects that are folded.
			group.folded = group.grouped and folded(group) and query == ""
			if group.grouped then
				rows[#rows + 1] = group
			end
			if not group.folded then
				for _, c in ipairs(group.members) do
					rows[#rows + 1] = { kind = "container", id = c.id, c = c, grouped = group.grouped }
				end
			end
		end
	else
		for _, c in ipairs(list) do
			rows[#rows + 1] = { kind = "container", id = c.id, c = c }
		end
	end
	S.cache.containers = { rev = S.rev, rows = rows, shown = #list }
	return rows, #list
end

local function counts()
	local all, running, stopped, issues = #S.containers, 0, 0, 0
	for _, c in ipairs(S.containers) do
		if is_up(c) then
			running += 1
		else
			stopped += 1
		end
		if has_issue(c) then
			issues += 1
		end
	end
	return { all = all, running = running, stopped = stopped, issues = issues }
end

-- Whether an event of the engine is a problem: a container that ran out of memory, that turned
-- unhealthy, or that stopped with a failure code.
local function is_problem(item)
	local detail = item.detail or {}
	local action = item.action or ""
	return action == "oom"
		or string.find(action, "unhealthy", 1, true) ~= nil
		or detail.status == "unhealthy"
		or (action == "die" and detail.exitCode ~= nil and tostring(detail.exitCode) ~= "0")
end

-- The names a row of another list is looked for by.
local function image_title(image)
	return image.tags[1] or ("<none> " .. image.id)
end

local function image_matches(image, query)
	if query == "" then
		return true
	end
	for _, tag in ipairs(image.tags) do
		if fmt.has(tag, query) then
			return true
		end
	end
	if fmt.has(image.id, query) then
		return true
	end
	for _, name in ipairs(image.containers or {}) do
		if fmt.has(name, query) then
			return true
		end
	end
	return false
end

-- The rows of a list that is not the containers: filtered by the field, in the order the person
-- is used to. `{ id =, item = }`.
local function plain_rows(section)
	local cached = S.cache[section]
	if cached and cached.rev == S.rev then
		return cached.rows
	end
	local list = S.lists[section] or {}
	local rows = {}
	local query = S.query
	local narrowed = S.plain_filter[section] or "all"
	if section == "images" then
		for _, image in ipairs(list) do
			local used = #(image.containers or {}) > 0
			local passes = narrowed == "all"
				or (narrowed == "used" and used)
				or (narrowed == "unused" and not used)
				or (narrowed == "dangling" and image.dangling)
			if passes and image_matches(image, query) then
				rows[#rows + 1] = { id = image.id, item = image }
			end
		end
		local how = S.image_sort
		table.sort(rows, function(x, y)
			if how == "size" and x.item.size ~= y.item.size then
				return x.item.size > y.item.size
			elseif how == "created" and (x.item.created or 0) ~= (y.item.created or 0) then
				return (x.item.created or 0) > (y.item.created or 0)
			end
			return image_title(x.item) < image_title(y.item)
		end)
	elseif section == "volumes" then
		for _, volume in ipairs(list) do
			local used = #volume.containers > 0
			local passes = narrowed == "all"
				or (narrowed == "used" and used)
				or (narrowed == "unused" and not used)
				or (narrowed == "anonymous" and volume.anonymous)
			if
				passes
				and (query == "" or fmt.has(volume.name, query) or (volume.project and fmt.has(volume.project, query)))
			then
				rows[#rows + 1] = { id = volume.name, item = volume }
			end
		end
		table.sort(rows, function(x, y)
			local ux, uy = #x.item.containers > 0, #y.item.containers > 0
			if ux ~= uy then
				return ux
			end
			return x.item.name < y.item.name
		end)
	elseif section == "networks" then
		for _, network in ipairs(list) do
			if query == "" or fmt.has(network.name, query) or fmt.has(table.concat(network.subnets, " "), query) then
				rows[#rows + 1] = { id = network.id, item = network }
			end
		end
		table.sort(rows, function(x, y)
			if x.item.builtin ~= y.item.builtin then
				return y.item.builtin
			end
			return x.item.name < y.item.name
		end)
	elseif section == "activity" then
		local kind = S.plain_filter.activity or "all"
		for _, item in ipairs(S.activity) do
			local problem = is_problem(item)
			local passes
			if kind == "problems" then
				passes = problem
			elseif kind == "all" then
				passes = not (item.type == "network" and item.action == "disconnect")
			else
				passes = item.type == kind
			end
			local text = (item.name or item.id or "") .. " " .. item.action .. " " .. (item.words or "")
			if passes and (query == "" or fmt.has(text, query)) then
				rows[#rows + 1] = { id = tostring(item.seq), item = item, problem = problem }
			end
		end
	end
	S.cache[section] = { rev = S.rev, rows = rows }
	return rows
end

-- The rows of the section on show, whatever it is.
local function rows_of(section)
	if section == "containers" then
		return (container_rows())
	end
	return plain_rows(section)
end

-- What an image's open row has under it, how tall it is: the tags, who uses it, its layers (a line
-- each). The panel is made of rows of fixed heights, so that the list knows where its rows start.
local PANEL = { gap = 8, pad = 10, tags = 22, used = 24, layer = 18, layer_gap = 2, loading = 60, top = 2, bottom = 10 }

local function layers_height(image)
	local slot = S.layers[image.id]
	if slot == nil or (slot.list == nil and slot.error == nil) then
		return PANEL.loading
	elseif slot.error then
		return PANEL.layer
	end
	local n = #slot.list
	if n == 0 then
		return PANEL.layer
	end
	return n * PANEL.layer + (n - 1) * PANEL.layer_gap
end

local function image_panel_height(image)
	local rows = {}
	if #image.tags > 0 then
		rows[#rows + 1] = PANEL.tags
	end
	if #image.containers > 0 then
		rows[#rows + 1] = PANEL.used
	end
	rows[#rows + 1] = layers_height(image)
	local total = PANEL.pad * 2 + PANEL.top + PANEL.bottom
	for _, height in ipairs(rows) do
		total += height
	end
	return total + PANEL.gap * (#rows - 1)
end

-- Where each row of a list starts, where the rows are not all of one height (a project's head has a
-- gap above it); `nil` where they are. The last entry is where the list ends.
local function row_tops(section)
	if section ~= "containers" and section ~= "activity" and section ~= "images" then
		return nil
	end
	local cached = S.cache["tops:" .. section]
	if cached and cached.rev == S.rev then
		return cached.tops
	end
	local tops, y = {}, 0
	if section == "containers" then
		for index, row in ipairs(container_rows()) do
			tops[index] = y
			y += SIZE.row + ((row.kind == "group" and index > 1) and 6 or 0)
		end
		tops[#tops + 1] = y
	elseif section == "images" then
		for index, row in ipairs(plain_rows("images")) do
			tops[index] = y
			y += SIZE.row
			if S.layer_open == row.id then
				y += image_panel_height(row.item)
			end
		end
		tops[#tops + 1] = y
	else
		-- A day's first event has the name of the day over it.
		local day = nil
		for index, row in ipairs(plain_rows("activity")) do
			tops[index] = y
			y += SIZE.row
			if row.item.day ~= day then
				day = row.item.day
				y += 30
			end
		end
		tops[#tops + 1] = y
	end
	S.cache["tops:" .. section] = { rev = S.rev, tops = tops }
	return tops
end

-- The index of the row with `id` among `rows` (or nil), and of the cursor of `section`.
local function index_of(rows, id)
	if id == nil then
		return nil
	end
	for index, row in ipairs(rows) do
		if row.id == id then
			return index
		end
	end
	return nil
end

-- Puts the cursor on a row that is there: where it was, or the row nearest where it was.
local function keep_cursor(section)
	local rows = rows_of(section)
	local at = index_of(rows, S.cursor[section])
	if at == nil then
		local row = rows[1]
		S.cursor[section] = row and row.id or nil
	end
end

-- What the person marked of `section` that is still there, in the order of the list.
local function marked(section)
	local out = {}
	local marks = S.marks[section]
	if marks == nil then
		return out
	end
	for _, row in ipairs(rows_of(section)) do
		if row.kind ~= "group" and marks[row.id] then
			out[#out + 1] = row
		end
	end
	return out
end

-- What an action is meant for: the marked rows, or else the row the cursor is on.
local function targets(section)
	local list = marked(section)
	if #list > 0 then
		return list
	end
	local rows = rows_of(section)
	local row = rows[index_of(rows, S.cursor[section]) or 0]
	if row and row.kind == "group" then
		-- A project stands for all of its containers.
		local members = {}
		for _, c in ipairs(row.members) do
			members[#members + 1] = { kind = "container", id = c.id, c = c }
		end
		return members
	elseif row then
		return { row }
	end
	return {}
end

return {
	SORTS = SORTS,
	SORT_LABELS = SORT_LABELS,
	container_rows = container_rows,
	counts = counts,
	folded = folded,
	PANEL = PANEL,
	image_panel_height = image_panel_height,
	image_title = image_title,
	is_problem = is_problem,
	index_of = index_of,
	keep_cursor = keep_cursor,
	marked = marked,
	plain_rows = plain_rows,
	row_tops = row_tops,
	rows_of = rows_of,
	targets = targets,
}
