-- How a call of the page is answered. Its params are checked against the schema the call names
-- (what does not fit is answered `bad-params`, and the work never runs), and what the work raises
-- is told to the page with a code it can act on: `docker-missing` and `engine-down` for what
-- docker could not do at all, `docker-failed` for what it refused (the words are the command's,
-- for the person), `failed` for anything else.
--
-- This is api/'s: the files of api/ know the page; docker/, state/ and terminal/ do not.

local params = require("api.params")

local M = {}

-- What a failure tells the page: a table with a code is the call's own answer.
function M.failure(err)
	if type(err) == "table" and err.code then
		return { code = err.code, message = err.message or err.code }
	end
	local words = string.gsub(tostring(err), "\nstack traceback:.*$", "")
	return { code = "failed", message = words }
end

-- A call that takes the params `schema` describes.
function M.new(schema, work)
	return function(args, context)
		local parsed, why = params.parse(schema, args)
		if why then
			error({ code = "bad-params", message = why }, 0)
		end
		local results = table.pack(pcall(work, parsed, context))
		if not results[1] then
			error(M.failure(results[2]), 0)
		end
		return table.unpack(results, 2, results.n)
	end
end

return M
