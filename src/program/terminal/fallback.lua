-- What dockerpen does where the terminal shows no views: it prints the containers, as `docker ps`
-- would, and ends. Also what `--text` asks for.
--
-- Plain values in and out: this file knows nothing of the page.

local pencere = require("pencere")
local io = pencere.io

local containers = require("docker.containers")

local M = {}

-- The containers as lines of text, in columns.
function M.table(list)
	local rows = { { "NAME", "IMAGE", "STATE", "STATUS", "PORTS" } }
	for _, container in ipairs(list) do
		local ports = {}
		for _, port in ipairs(container.ports) do
			ports[#ports + 1] = port.public and (port.public .. "->" .. port.private) or tostring(port.private)
		end
		rows[#rows + 1] = {
			container.name,
			container.image,
			container.health ~= "none" and (container.state .. " (" .. container.health .. ")") or container.state,
			container.status,
			table.concat(ports, ", "),
		}
	end
	local widths = {}
	for _, row in ipairs(rows) do
		for column, cell in ipairs(row) do
			widths[column] = math.max(widths[column] or 0, utf8.len(cell) or #cell)
		end
	end
	local lines = {}
	for _, row in ipairs(rows) do
		local cells = {}
		for column, cell in ipairs(row) do
			if column < #row then
				cells[column] = cell .. string.rep(" ", widths[column] - (utf8.len(cell) or #cell))
			else
				cells[column] = cell
			end
		end
		lines[#lines + 1] = table.concat(cells, "  ")
	end
	return lines
end

-- Prints the containers. Gives the status the program ends with: 0, or 1 and what went wrong.
function M.print()
	local ok, list = pcall(containers.list)
	if not ok then
		io.ewrite("dockerpen: " .. (type(list) == "table" and list.message or tostring(list)) .. "\n")
		return 1
	end
	if #list == 0 then
		io.write("There are no containers.\n")
		return 0
	end
	for _, line in ipairs(M.table(list)) do
		io.write(line .. "\n")
	end
	return 0
end

return M
