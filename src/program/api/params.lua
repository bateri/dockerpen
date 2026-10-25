-- What the page sends is not trusted: each call says what it asks (a schema), and what does not
-- fit is answered `bad-params` and never run. A schema is a function from a value to the value as
-- the program takes it (members an object was not asked for are dropped), or to nil and the words
-- for what is wrong, led by where (`ids.0`). Lua cannot tell a member that is null from one that is
-- left out, so an optional member is nil either way.
--
-- This is api/'s: the files of api/ know the page; docker/, state/ and terminal/ do not.

local pencere = require("pencere")
local json = pencere.json

local M = {}

-- What a value from JSON is: an empty table is a list (a page's `[]`), and `{}` arrives marked.
local function kind(value)
	local t = type(value)
	if t ~= "table" then
		return t
	end
	if getmetatable(value) == "json.object" then
		return "object"
	end
	local count = 0
	for _ in pairs(value) do
		count += 1
	end
	if count == 0 then
		return "array"
	end
	if #value == count then
		return "array"
	end
	for key in pairs(value) do
		if type(key) ~= "string" then
			return "mixed"
		end
	end
	return "object"
end

local function where(path)
	return #path == 0 and "" or (table.concat(path, ".") .. ": ")
end

local function wrong(path, words)
	return nil, where(path) .. words
end

local function describe(value)
	local k = kind(value)
	return k == "nil" and "nothing" or k
end

function M.string(minimum)
	return function(value, path)
		if type(value) ~= "string" then
			return wrong(path, "expected a string, got " .. describe(value))
		end
		if minimum and #value < minimum then
			return wrong(path, "expected at least " .. minimum .. " character")
		end
		return value
	end
end

function M.integer(minimum, maximum)
	return function(value, path)
		if
			type(value) ~= "number"
			or value ~= value
			or math.floor(value) ~= value
			or value == math.huge
			or value == -math.huge
		then
			return wrong(path, "expected an integer, got " .. describe(value))
		end
		if minimum and value < minimum then
			return wrong(path, "expected at least " .. minimum)
		end
		if maximum and value > maximum then
			return wrong(path, "expected at most " .. maximum)
		end
		return value
	end
end

function M.boolean()
	return function(value, path)
		if type(value) ~= "boolean" then
			return wrong(path, "expected true or false, got " .. describe(value))
		end
		return value
	end
end

function M.enum(...)
	local names = { ... }
	return function(value, path)
		for _, name in ipairs(names) do
			if value == name then
				return value
			end
		end
		return wrong(path, "expected one of " .. table.concat(names, ", "))
	end
end

-- A member a call may leave out.
function M.optional(schema)
	return function(value, path)
		if value == nil then
			return nil, nil, true
		end
		return schema(value, path)
	end
end

function M.array(schema, most)
	return function(value, path)
		if kind(value) ~= "array" then
			return wrong(path, "expected a list, got " .. describe(value))
		end
		if most and #value > most then
			return wrong(path, "expected at most " .. most .. " items")
		end
		local out = {}
		for index = 1, #value do
			path[#path + 1] = tostring(index - 1)
			local item, why = schema(value[index], path)
			path[#path] = nil
			if why then
				return nil, why
			end
			out[index] = item
		end
		return out
	end
end

-- A list of at least one.
function M.some(schema, most)
	local inner = M.array(schema, most)
	return function(value, path)
		local list, why = inner(value, path)
		if why then
			return nil, why
		end
		if #list == 0 then
			return wrong(path, "expected at least one")
		end
		return list
	end
end

-- Any value: a place the page keeps what the program only holds for it. Its size is bounded by
-- the message it arrived in.
function M.any()
	return function(value)
		return value
	end
end

function M.object(shape)
	local keys = {}
	for key in pairs(shape) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	return function(value, path)
		if kind(value) ~= "object" then
			return wrong(path, "expected an object, got " .. describe(value))
		end
		local out = {}
		for _, key in ipairs(keys) do
			path[#path + 1] = key
			local clean, why, absent = shape[key](value[key], path)
			path[#path] = nil
			if why then
				return nil, why
			end
			if not absent then
				out[key] = clean
			end
		end
		return out
	end
end

-- `params` as `schema` has it, or nil and the words for what is wrong. No params at all is `{}`.
function M.parse(schema, params)
	if params == nil then
		params = json.object()
	end
	return schema(params, {})
end

-- The params of a call that asks for nothing, and for one container.
M.nothing = M.object({})
M.one_id = M.object({ id = M.string(1) })

return M
