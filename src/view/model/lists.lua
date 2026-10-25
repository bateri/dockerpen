local model_net = require("./net")
local model_rows = require("./rows")
local model_state = require("./state")
local net, why = model_net.net, model_net.why
local keep_cursor = model_rows.keep_cursor
local S, bump = model_state.S, model_state.bump

-- ---- the lists docker keeps, asked for when they come on show ------------------------------------------

local function load_list(section)
	if S.loading[section] then
		S.stale[section] = true
		return
	end
	S.loading[section] = true
	S.stale[section] = false
	net.ask(section, nil, function(result, err)
		S.loading[section] = false
		if err then
			S.problems[section] = why(err)
		else
			S.problems[section] = nil
			S.lists[section] = result[section]
			if section == "volumes" and not result.sized then
				net.ask("volume_sizes", nil, function(counted, failed)
					-- A count that failed leaves no sizes, and the list says so and not "counting".
					S.volume_sizes = failed and {} or counted.sizes
					bump()
				end)
			end
		end
		bump()
		keep_cursor(section)
		if S.stale[section] then
			load_list(section)
		end
	end)
end

local function load_system()
	if S.loading.system then
		S.stale.system = true
		return
	end
	S.loading.system = true
	S.stale.system = false
	net.ask("system", nil, function(result, err)
		S.loading.system = false
		if err then
			S.problems.system = why(err)
		else
			S.problems.system = nil
			S.system = result
		end
		bump()
		if S.stale.system then
			load_system()
		end
	end)
end

-- The detail of a container, asked for when it opens, and again when its state changed.
local function signature(c)
	return c.state .. "/" .. c.health .. "/" .. c.status
end

local function load_detail(id)
	local c = S.by_id[id]
	local slot = S.details[id]
	if slot == nil then
		slot = { state = "loading" }
		S.details[id] = slot
	end
	if slot.asking then
		return
	end
	slot.asking = true
	slot.signature = c and signature(c) or nil
	net.ask("detail", { id = id }, function(result, err)
		slot.asking = false
		if err then
			slot.state, slot.error = "error", why(err)
		else
			slot.state, slot.data, slot.error = "ok", result, nil
		end
		bump()
	end)
end

local function load_processes(id)
	local slot = S.processes
	if slot.asking then
		return
	end
	slot.asking, slot.id = true, id
	net.ask("processes", { id = id }, function(result, err)
		slot.asking = false
		if slot.id ~= id then
			return
		end
		if err then
			slot.error = why(err)
		else
			slot.error, slot.titles, slot.rows = nil, result.titles, result.rows
		end
		slot.at = S.now
		bump()
	end)
end

return {
	load_detail = load_detail,
	load_list = load_list,
	load_processes = load_processes,
	load_system = load_system,
	signature = signature,
}
