-- Images: what `docker image ls` lists, the layers of one, taking one away, pulling one.

local cli = require("docker.cli")
local parse = require("docker.parse")

local M = {}

-- The images, a table for each (an image with several tags is one): `id` (twelve digits), `tags`
-- (`repository:tag`), the size in bytes, when it was made, and whether it is dangling (it has no
-- name any more).
function M.list()
	local output = cli.run({ "image", "ls", "--format", "json" }, { timeout = 30 })
	local list, byid = {}, {}
	for _, raw in ipairs(parse.objects(output)) do
		local id = raw.ID or ""
		local image = byid[id]
		if image == nil then
			image = {
				id = id,
				tags = {},
				created = parse.time(raw.CreatedAt),
				size = parse.bytes(raw.Size) or 0,
				dangling = true,
			}
			byid[id] = image
			list[#list + 1] = image
		end
		if raw.Repository ~= nil and raw.Repository ~= "<none>" then
			local tag = raw.Tag ~= nil and raw.Tag ~= "<none>" and raw.Tag or nil
			image.tags[#image.tags + 1] = tag and (raw.Repository .. ":" .. tag) or raw.Repository
			image.dangling = false
		end
	end
	return list
end

-- The layers of an image, newest first: the instruction that made each, its size in bytes, when.
function M.history(id)
	local output = cli.run({ "image", "history", "--no-trunc", "--format", "json", id }, { timeout = 30 })
	local layers = {}
	for _, raw in ipairs(parse.objects(output)) do
		local layer_id = raw.ID or ""
		layers[#layers + 1] = {
			id = layer_id == "<missing>" and "" or parse.image_name(layer_id),
			created = parse.time(raw.CreatedAt),
			created_by = raw.CreatedBy or "",
			size = parse.bytes(raw.Size) or 0,
			comment = raw.Comment or "",
		}
	end
	return layers
end

-- Takes an image away; `force` takes it from the containers that were made from it too.
function M.remove(id, force)
	local args = { "image", "rm" }
	if force then
		args[#args + 1] = "--force"
	end
	args[#args + 1] = id
	cli.run(args, { timeout = 120 })
end

-- How far a pull has come, from the lines `docker pull` prints: each layer is announced
-- (`abc123: Pulling fs layer`) and later done (`Pull complete`, `Already exists`). A fresh table
-- is the state of a new pull.
function M.progress()
	return { layers = {}, done = 0, total = 0 }
end

-- Takes a line of a pull into `state`, and says how far it has come (0 to 1, nil while it does
-- not know) and what the line said.
function M.pulled(state, line)
	local layer, what = string.match(line, "^(%x+): (.+)$")
	if layer ~= nil then
		if state.layers[layer] == nil then
			state.layers[layer] = false
			state.total += 1
		end
		if what == "Pull complete" or what == "Already exists" then
			if state.layers[layer] == false then
				state.layers[layer] = true
				state.done += 1
			end
		end
	end
	local fraction = state.total > 0 and state.done / state.total or nil
	return fraction, line
end

-- Pulls `reference`: `on_line(line)` for what it prints, `on_exit(code, message)` when it ends.
-- Returns the handle to stop it with.
function M.pull(reference, on_line, on_exit)
	local errors = {}
	return cli.stream({ "pull", reference }, {
		on_line = on_line,
		on_error_line = function(line)
			if #errors < 10 then
				errors[#errors + 1] = line
			end
		end,
		on_exit = function(code)
			on_exit(code, table.concat(errors, "\n"))
		end,
	})
end

return M
