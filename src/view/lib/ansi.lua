-- ---- the colours a program writes into its log -----------------------------------------------

local ansi = {}

local ANSI_ROLES = {
	[0] = "black",
	"red",
	"green",
	"yellow",
	"blue",
	"magenta",
	"cyan",
	"white",
	"bright-black",
	"bright-red",
	"bright-green",
	"bright-yellow",
	"bright-blue",
	"bright-magenta",
	"bright-cyan",
	"bright-white",
}

-- The 256-colour cube folded onto the sixteen colours the theme has.
local function fold256(value)
	if value < 16 then
		return value
	end
	if value >= 232 then
		return value > 243 and 7 or 8
	end
	local v = value - 16
	local r, g, bl = v // 36, (v % 36) // 6, v % 6
	local bright = math.max(r, g, bl) > 3 and 8 or 0
	local index = (r > 2 and 1 or 0) + (g > 2 and 2 or 0) + (bl > 2 and 4 or 0)
	return index == 0 and (bright > 0 and 8 or 0) or index + bright
end

-- Whether a line has an escape in it.
function ansi.has(text)
	return string.find(text, "\27", 1, true) ~= nil
end

-- The text without what an escape says.
function ansi.strip(text)
	if not ansi.has(text) then
		return text
	end
	text = string.gsub(text, "\27%[[%d;?]*%a", "")
	text = string.gsub(text, "\27%][^\7\27]*[\7\27]\\?", "")
	return text
end

-- A line as runs of one style each: `{ text =, fg =, bold =, dim =, underline = }`. Everything an
-- escape can do besides colour and weight is dropped.
function ansi.runs(text)
	text = string.gsub(text, "\t", "    ")
	if not ansi.has(text) then
		return { { text = text } }
	end
	-- A link, a title: what `ansi.strip` takes away, and is not in a line's words.
	text = string.gsub(text, "\27%][^\7\27]*[\7\27]\\?", "")
	local runs = {}
	local style = {}
	local at = 1
	local function push(upto)
		if upto >= at then
			local piece = string.sub(text, at, upto)
			if piece ~= "" then
				runs[#runs + 1] = {
					text = piece,
					fg = style.fg,
					bold = style.bold,
					dim = style.dim,
					underline = style.underline,
				}
			end
		end
	end
	while true do
		local from, to, params, command = string.find(text, "\27%[([%d;?]*)(%a)", at)
		if from == nil then
			break
		end
		push(from - 1)
		at = to + 1
		if command == "m" then
			local codes = {}
			for number in string.gmatch(params, "%d+") do
				codes[#codes + 1] = tonumber(number)
			end
			if #codes == 0 then
				codes[1] = 0
			end
			local i = 1
			while i <= #codes do
				local code = codes[i]
				if code == 0 then
					style = {}
				elseif code == 1 then
					style.bold = true
				elseif code == 2 then
					style.dim = true
				elseif code == 4 then
					style.underline = true
				elseif code == 22 then
					style.bold, style.dim = nil, nil
				elseif code == 24 then
					style.underline = nil
				elseif code >= 30 and code <= 37 then
					style.fg = ANSI_ROLES[code - 30]
				elseif code >= 90 and code <= 97 then
					style.fg = ANSI_ROLES[code - 90 + 8]
				elseif code == 39 then
					style.fg = nil
				elseif (code == 38 or code == 48) and codes[i + 1] == 5 then
					if code == 38 then
						style.fg = ANSI_ROLES[fold256(codes[i + 2] or 0)]
					end
					i += 2
				elseif (code == 38 or code == 48) and codes[i + 1] == 2 then
					if code == 38 then
						style.fg =
							string.format("#%02x%02x%02x", codes[i + 2] or 0, codes[i + 3] or 0, codes[i + 4] or 0)
					end
					i += 4
				end
				i += 1
			end
		end
	end
	push(#text)
	if #runs == 0 then
		runs[1] = { text = "" }
	end
	return runs
end

-- The level a line of a log says in words, when it says one: what a program without colours tells.
function ansi.level(plain)
	local head = string.upper(string.sub(plain, 1, 48))
	if
		string.find(head, "%f[%w]ERROR%f[%W]")
		or string.find(head, "%f[%w]FATAL%f[%W]")
		or string.find(head, "%f[%w]PANIC%f[%W]")
	then
		return "error"
	elseif string.find(head, "%f[%w]WARN") then
		return "warning"
	elseif string.find(head, "%f[%w]DEBUG%f[%W]") or string.find(head, "%f[%w]TRACE%f[%W]") then
		return "dim"
	end
	return nil
end

return {
	ansi = ansi,
}
