-- What dockerpen was asked to do on the command line:
--
--   dockerpen                      the interface
--   dockerpen web                  the interface, with a container chosen (a name, a compose
--                                  service or the start of an id)
--   dockerpen --section images     the interface, on another part
--   dockerpen --text               the containers as text, whatever the terminal is
--   dockerpen --version | --help
--
-- Plain values in and out: this file knows nothing of the page.

local M = {}

M.SECTIONS = { "containers", "images", "volumes", "networks", "system", "activity" }

M.USAGE = [[usage: dockerpen [container] [--section NAME] [--text] [--log FILE]
       dockerpen --version | --help

  container        open with this container chosen: its name, its compose service or the
                   start of its id
  --section NAME   open on containers, images, volumes, networks, system or activity
  --text           print the containers as text, as a terminal without views gets them
  --log FILE       write print and errors to FILE instead of the terminal]]

local function is_section(name)
	for _, section in ipairs(M.SECTIONS) do
		if section == name then
			return true
		end
	end
	return false
end

-- The command line `args` (a list of words) as `{ section =, focus =, text =, version =, help =
-- }`, or nil and the words for what is wrong with it.
function M.read(args)
	local line = { text = false, version = false, help = false }
	local index = 1
	while index <= #args do
		local word = args[index]
		if word == "--version" or word == "-v" then
			line.version = true
		elseif word == "--help" or word == "-h" then
			line.help = true
		elseif word == "--text" then
			line.text = true
		elseif word == "--section" or word == "-s" then
			index += 1
			local name = args[index]
			if name == nil or not is_section(name) then
				return nil, "--section is one of " .. table.concat(M.SECTIONS, ", ")
			end
			line.section = name
		elseif string.sub(word, 1, 10) == "--section=" then
			local name = string.sub(word, 11)
			if not is_section(name) then
				return nil, "--section is one of " .. table.concat(M.SECTIONS, ", ")
			end
			line.section = name
		elseif string.sub(word, 1, 1) == "-" then
			return nil, "no option " .. word
		elseif line.focus == nil then
			line.focus = word
		else
			return nil, "one container at most: " .. word
		end
		index += 1
	end
	return line
end

return M
