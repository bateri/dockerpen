-- ---- words ---------------------------------------------------------------------------------

local fmt = {}

-- A size in bytes as docker counts disk: decimal units (`1.2 GB`), `–` where there is none.
function fmt.bytes(n)
	if n == nil or n < 0 then
		return "–"
	end
	local units = { "B", "KB", "MB", "GB", "TB" }
	local unit = 1
	while n >= 1000 and unit < #units do
		n /= 1000
		unit += 1
	end
	if unit == 1 or n >= 100 then
		return string.format("%.0f %s", n, units[unit])
	end
	return string.format("%.1f %s", n, units[unit])
end

-- Memory as `docker stats` writes it: powers of 1024 (`936 KiB`, `7.2 MiB`).
function fmt.memory(n)
	if n == nil or n < 0 then
		return "–"
	end
	local units = { "B", "KiB", "MiB", "GiB", "TiB" }
	local unit = 1
	while n >= 1024 and unit < #units do
		n /= 1024
		unit += 1
	end
	if unit == 1 or n >= 100 then
		return string.format("%.0f %s", n, units[unit])
	end
	return string.format("%.1f %s", n, units[unit])
end

-- The same without the space, where the room is short (`7.2MiB`).
function fmt.memory_tight(n)
	return (string.gsub(fmt.memory(n), " ", ""))
end

function fmt.rate(n)
	if n == nil or n < 1 then
		return "0 B/s"
	end
	return fmt.bytes(n) .. "/s"
end

-- A percent with one decimal, none from a hundred (`0.9%`, `37.6%`, `120%`), or `digits` decimals.
function fmt.percent(n, digits)
	if n == nil then
		return "–"
	end
	if n >= 100 or digits == 0 then
		return string.format("%.0f%%", n)
	end
	return string.format("%." .. (digits or 1) .. "f%%", n)
end

-- Seconds as the longest unit that fits: `45s`, `3m`, `2h`, `5d`.
function fmt.span(seconds)
	seconds = math.max(0, math.floor(seconds))
	if seconds < 60 then
		return seconds .. "s"
	elseif seconds < 3600 then
		return (seconds // 60) .. "m"
	elseif seconds < 86400 then
		return (seconds // 3600) .. "h"
	elseif seconds < 86400 * 14 then
		return (seconds // 86400) .. "d"
	elseif seconds < 86400 * 60 then
		return (seconds // (86400 * 7)) .. "w"
	end
	return (seconds // (86400 * 30)) .. "mo"
end

-- What docker says of how long (`Up 3 minutes`, `Exited (1) 2 hours ago`, `Up About an hour`) as
-- a few characters: `up 3m`, `2h ago`.
function fmt.status(status)
	local text = status or ""
	local up = string.find(text, "^Up") ~= nil
	local gone = string.find(text, "^Exited") ~= nil or string.find(text, "^Created") ~= nil
	text = string.gsub(text, "^Up ", "")
	text = string.gsub(text, "^Exited %(%-?%d+%) ", "")
	text = string.gsub(text, "^Created ", "")
	text = string.gsub(text, "%s*%(.*%)%s*$", "")
	text = string.gsub(text, "About an? ", "1 ")
	text = string.gsub(text, "Less than a second", "<1s")
	text = string.gsub(text, "an? ", "1 ")
	text = string.gsub(text, "(%d+) seconds?", "%1s")
	text = string.gsub(text, "(%d+) minutes?", "%1m")
	text = string.gsub(text, "(%d+) hours?", "%1h")
	text = string.gsub(text, "(%d+) days?", "%1d")
	text = string.gsub(text, "(%d+) weeks?", "%1w")
	text = string.gsub(text, "(%d+) months?", "%1mo")
	text = string.gsub(text, "(%d+) years?", "%1y")
	text = string.gsub(text, "^%s+", "")
	if up then
		return "up " .. text
	elseif gone and text ~= "" then
		return text
	end
	return string.lower(status or "")
end

-- A line of text cut to `n` characters, ending in an ellipsis where it was cut.
function fmt.cut(text, n)
	local length = utf8.len(text)
	if length == nil or length <= n then
		return text
	end
	return string.sub(text, 1, utf8.offset(text, n) - 1) .. "…"
end

-- Whether `text` has `needle` in it, ignoring case when `needle` has no capital.
function fmt.has(text, needle)
	if needle == "" then
		return true
	end
	if string.find(needle, "%u") then
		return string.find(text, needle, 1, true) ~= nil
	end
	return string.find(string.lower(text), needle, 1, true) ~= nil
end

-- An image's name without the registry's default parts: `docker.io/library/nginx` is `nginx`.
function fmt.image_name(reference)
	local name = string.gsub(reference or "", "^docker%.io/", "")
	name = string.gsub(name, "^library/", "")
	return name
end

-- A count and its noun: `1 container`, `3 containers`.
function fmt.count(n, noun)
	local plural = string.find(noun, "s$") and "es" or "s"
	return n .. " " .. noun .. (n == 1 and "" or plural)
end

return {
	fmt = fmt,
}
