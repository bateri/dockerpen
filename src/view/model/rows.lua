local lib_fmt = require("../lib/fmt")
local model_containers = require("./containers")
local model_state = require("./state")
local fmt = lib_fmt.fmt
local has_issue, is_up = model_containers.has_issue, model_containers.is_up
local S = model_state.S

-- ---- the rows of the lists ----------------------------------------------------------------------

local SORTS = { "name", "state", "cpu", "memory", "created" }

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

-- Whether a project is folded: as the person left it, and otherwise when nothing of it runs.
local function folded(group)
	local explicit = S.folded[group.key]
	if explicit ~= nil then
		return explicit
	end
	return group.up == 0
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
	if S.group then
		local groups, order = {}, {}
		for _, c in ipairs(list) do
			local key = c.project or ""
			local group = groups[key]
			if group == nil then
				group =
					{ kind = "group", key = key, name = c.project or "Standalone", members = {}, up = 0, issues = 0 }
				groups[key] = group
				order[#order + 1] = group
			end
			group.members[#group.members + 1] = c
			if is_up(c) then
				group.up += 1
			end
			if has_issue(c) then
				group.issues += 1
			end
		end
		table.sort(order, function(x, y)
			if (x.up > 0) ~= (y.up > 0) then
				return x.up > 0
			end
			if (x.key == "") ~= (y.key == "") then
				return y.key == ""
			end
			return x.name < y.name
		end)
		for _, group in ipairs(order) do
			group.id = "group:" .. group.key
			group.folded = folded(group)
			rows[#rows + 1] = group
			if not group.folded then
				for _, c in ipairs(group.members) do
					rows[#rows + 1] = { kind = "container", id = c.id, c = c }
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
	if section == "images" then
		for _, image in ipairs(list) do
			if image_matches(image, query) then
				rows[#rows + 1] = { id = image.id, item = image }
			end
		end
		table.sort(rows, function(x, y)
			local ux, uy = (x.item.running or 0) > 0, (y.item.running or 0) > 0
			if ux ~= uy then
				return ux
			end
			if x.item.dangling ~= y.item.dangling then
				return y.item.dangling
			end
			return image_title(x.item) < image_title(y.item)
		end)
	elseif section == "volumes" then
		for _, volume in ipairs(list) do
			if query == "" or fmt.has(volume.name, query) or (volume.project and fmt.has(volume.project, query)) then
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
		for _, item in ipairs(S.activity) do
			local text = (item.name or item.id or "") .. " " .. item.action .. " " .. (item.words or "")
			if query == "" or fmt.has(text, query) then
				rows[#rows + 1] = { id = tostring(item.seq), item = item }
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
	container_rows = container_rows,
	counts = counts,
	folded = folded,
	image_title = image_title,
	index_of = index_of,
	keep_cursor = keep_cursor,
	marked = marked,
	plain_rows = plain_rows,
	rows_of = rows_of,
	targets = targets,
}
