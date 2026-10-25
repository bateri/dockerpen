-- The question over everything: its answers, shared by the keys and the pointer. A dialog is
-- `S.dialog` (made by `ask`, model/act.lua): the boxes it has to tick (`options`, their `values`),
-- the box the keys are on (`cursor`), and, for a pull, the name that is being typed (`reference`).

local model_state = require("./state")
local S, bump = model_state.S, model_state.bump

local dialog = {}

-- The names that can be pulled with one click.
dialog.SUGGESTIONS = {
	"nginx:alpine",
	"redis:7-alpine",
	"postgres:17-alpine",
	"node:22-alpine",
	"python:3.13-slim",
	"busybox",
}

function dialog.close()
	S.dialog = nil
	bump()
end

-- What the boxes say and the name typed, as `run` is given them.
local function values_of(d)
	local values = {}
	for key, on in pairs(d.values) do
		values[key] = on
	end
	values.reference = d.reference
	return values
end

-- Whether the answer can be given: a pull wants a name, a clean-up wants something ticked.
function dialog.ready()
	local d = S.dialog
	if d == nil then
		return false
	end
	if d.kind == "pull" then
		return string.gsub(d.reference or "", "%s", "") ~= ""
	elseif d.kind == "prune" then
		for _, on in pairs(d.values) do
			if on then
				return true
			end
		end
		return false
	end
	return true
end

-- Answers yes. False where it cannot be given yet.
function dialog.confirm()
	local d = S.dialog
	if d == nil or not dialog.ready() then
		return false
	end
	S.dialog = nil
	bump()
	d.run(values_of(d))
	return true
end

-- Ticks or unticks the box `index`.
function dialog.toggle(index)
	local d = S.dialog
	local option = d and d.options and d.options[index]
	if option == nil then
		return
	end
	d.cursor = index
	d.values[option.key] = not d.values[option.key]
	bump()
end

-- Moves the keys to the next or the previous box.
function dialog.move(delta)
	local d = S.dialog
	if d == nil or d.options == nil or #d.options == 0 then
		return
	end
	d.cursor = (d.cursor - 1 + delta) % #d.options + 1
	bump()
end

-- A name on a chip is the name to pull.
function dialog.suggest(name)
	local d = S.dialog
	if d and d.kind == "pull" then
		d.reference = name
		bump()
	end
end

-- What a clean-up of what is ticked frees, as docker counts it: nil until the disk is counted.
function dialog.total()
	local d = S.dialog
	local usage = S.system and S.system.usage
	if d == nil or d.options == nil or usage == nil then
		return nil
	end
	local sum = 0
	for _, option in ipairs(d.options) do
		if d.values[option.key] and option.size and usage[option.size] then
			sum += usage[option.size].reclaimable or 0
		end
	end
	return sum
end

-- The size docker counts for a part of what can be cleaned up.
function dialog.size_of(option)
	local usage = S.system and S.system.usage
	if usage == nil or option.size == nil or usage[option.size] == nil then
		return nil
	end
	return usage[option.size].reclaimable
end

return {
	dialog = dialog,
}
