-- Reading what the docker command prints: sizes written for people ("1.2GB", "936KiB"), the
-- `ports` and `labels` strings of `docker ps`, the words of a status, a date. Plain text in, plain
-- Lua values out; nothing here runs a command.

local pencere = require("pencere")
local json = pencere.json

local M = {}

-- The sizes `docker` writes: decimal for disk and network (`kB`, `MB`), binary for memory (`KiB`).
local UNITS = {
	b = 1,
	kb = 1e3,
	mb = 1e6,
	gb = 1e9,
	tb = 1e12,
	pb = 1e15,
	kib = 1024,
	mib = 1024 ^ 2,
	gib = 1024 ^ 3,
	tib = 1024 ^ 4,
	pib = 1024 ^ 5,
}

-- A size as docker writes it, in bytes: `1.06GB`, `7.266MiB`, `0B`. nil for what is not one
-- (`N/A`, nothing).
function M.bytes(text)
	if type(text) ~= "string" then
		return nil
	end
	local number, unit = string.match(text, "^%s*(%d+%.?%d*)%s*(%a*)%s*$")
	if number == nil then
		return nil
	end
	local factor = UNITS[string.lower(unit == "" and "b" or unit)]
	if factor == nil then
		return nil
	end
	return math.floor(tonumber(number) * factor + 0.5)
end

-- `"a / b"` as the two halves, trimmed; nil when it is not two.
function M.pair(text)
	if type(text) ~= "string" then
		return nil
	end
	local first, second = string.match(text, "^%s*(.-)%s*/%s*(.-)%s*$")
	return first, second
end

-- `"37.60%"` as 37.6; nil for `--`, `N/A` and the rest.
function M.percent(text)
	if type(text) ~= "string" then
		return nil
	end
	local number = string.match(text, "^%s*(%d+%.?%d*)%s*%%%s*$")
	return number and tonumber(number)
end

-- What the `Reclaimable` column says: `6.366GB (37%)` is 6.366GB.
function M.reclaimable(text)
	if type(text) ~= "string" then
		return nil
	end
	return M.bytes((string.gsub(text, "%s*%(.*$", "")))
end

-- The ports of `docker ps`: `0.0.0.0:8088->80/tcp, [::]:8088->80/tcp, 5432/tcp`, each published
-- port once (the engine lists one for IPv4 and again for IPv6), the ones with a place on this
-- machine first.
function M.ports(text)
	local list, seen = {}, {}
	if type(text) ~= "string" then
		return list
	end
	for piece in string.gmatch(text, "[^,]+") do
		piece = string.match(piece, "^%s*(.-)%s*$")
		local left, right = string.match(piece, "^(.-)%->(.+)$")
		local private, kind
		local public, host
		if left then
			private, kind = string.match(right, "^([%d%-]+)/(%a+)$")
			host, public = string.match(left, "^(.*):([%d%-]+)$")
			if public == nil then
				public = string.match(left, "^([%d%-]+)$")
			end
		else
			private, kind = string.match(piece, "^([%d%-]+)/(%a+)$")
		end
		if private ~= nil then
			local entry = {
				private = tonumber(string.match(private, "^%d+")),
				type = kind,
			}
			if public ~= nil then
				entry.public = tonumber(string.match(public, "^%d+"))
				if host ~= nil and host ~= "" and host ~= ":" then
					entry.ip = host
				end
			end
			local key = tostring(entry.public) .. "/" .. tostring(entry.private) .. "/" .. kind
			if not seen[key] then
				seen[key] = true
				list[#list + 1] = entry
			end
		end
	end
	table.sort(list, function(a, b)
		local pa, pb = a.public or 1e6, b.public or 1e6
		if pa ~= pb then
			return pa < pb
		end
		return a.private < b.private
	end)
	return list
end

-- The labels of `docker ps`: `a=b,c=d`. A value may hold a comma, so a piece that does not begin
-- with a key belongs to the value before it.
function M.labels(text)
	local labels = {}
	if type(text) ~= "string" or text == "" then
		return labels
	end
	local last = nil
	for piece in string.gmatch(text, "[^,]+") do
		local key, value = string.match(piece, "^([%w%._%-/]+)=(.*)$")
		if key ~= nil then
			labels[key] = value
			last = key
		elseif last ~= nil then
			labels[last] = labels[last] .. "," .. piece
		end
	end
	return labels
end

-- What a status says beyond its words: `Up 2 hours (healthy)`, `Up 3 seconds (health: starting)`,
-- `Exited (137) 3 days ago`. A stopped container keeps the health of its last check, which says
-- nothing now, so only a running one has any.
function M.status(status, state)
	status = status or ""
	local health = "none"
	if state == "running" or state == "restarting" then
		if string.find(status, "(unhealthy)", 1, true) then
			health = "unhealthy"
		elseif string.find(status, "(healthy)", 1, true) then
			health = "healthy"
		elseif string.find(status, "(health: starting)", 1, true) then
			health = "starting"
		end
	end
	local code = string.match(status, "Exited %((%-?%d+)%)")
	return { health = health, exit_code = code and tonumber(code) or nil }
end

-- Days from 1970-01-01 to a date of the calendar (Howard Hinnant's algorithm).
local function days(year, month, day)
	if month <= 2 then
		year -= 1
	end
	local era = (year >= 0 and year or year - 399) // 400
	local yoe = year - era * 400
	local doy = (153 * (month + (month > 2 and -3 or 9)) + 2) // 5 + day - 1
	local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
	return era * 146097 + doe - 719468
end

-- A date as docker writes it, in seconds since 1970: `2026-10-25 13:57:05 +0300 +03` (what `ps`
-- and `ls` say) and `2026-10-24T19:46:22+03:00` (what `inspect` and `history` say), with or
-- without fractions of a second. nil for `0001-01-01…`, which docker writes for "never".
function M.time(text)
	if type(text) ~= "string" then
		return nil
	end
	local y, mo, d, h, mi, s, rest = string.match(text, "^(%d+)-(%d+)-(%d+)[T ](%d+):(%d+):(%d+)(.*)$")
	if y == nil or tonumber(y) < 1970 then
		return nil
	end
	rest = string.gsub(rest, "^%.%d+", "")
	local offset = 0
	local sign, oh, om = string.match(rest, "^%s*([%+%-])(%d%d):?(%d%d)")
	if sign ~= nil then
		offset = (tonumber(oh) * 3600 + tonumber(om) * 60) * (sign == "-" and -1 or 1)
	end
	local seconds = days(tonumber(y), tonumber(mo), tonumber(d)) * 86400
		+ tonumber(h) * 3600
		+ tonumber(mi) * 60
		+ tonumber(s)
	return seconds - offset
end

-- A line of `docker logs --timestamps`: the time docker gives it (RFC 3339 with nanoseconds) and
-- the text after it.
function M.log_line(line)
	local time, text = string.match(line, "^(%d%d%d%d%-%d%d%-%d%dT[%d:%.]+[Z%+%-]?[%d:]*) (.*)$")
	if time == nil then
		return nil, line
	end
	return time, text
end

-- The lines of a text, with the ones that are empty (the text of `inspect` is read as it is
-- printed). A last line ended by its line end is not followed by an empty one. At most `most`.
function M.lines(text, most)
	local lines = {}
	local from = 1
	local length = #text
	while from <= length and (most == nil or #lines < most) do
		local to = string.find(text, "\n", from, true)
		local line
		if to == nil then
			line = string.sub(text, from)
			from = length + 1
		else
			line = string.sub(text, from, to - 1)
			from = to + 1
		end
		if string.sub(line, -1) == "\r" then
			line = string.sub(line, 1, -2)
		end
		lines[#lines + 1] = line
	end
	return lines
end

-- The lines of a text that are JSON objects, decoded; the rest (a blank line, a warning) is
-- left out.
function M.objects(text)
	local list = {}
	for line in string.gmatch(text or "", "[^\n]+") do
		local record = string.match(line, "{.*}")
		if record ~= nil then
			local ok, value = pcall(json.decode, record)
			if ok and type(value) == "table" then
				list[#list + 1] = value
			end
		end
	end
	return list
end

-- A line that is one JSON object (a streaming command prints one a line, sometimes after a
-- control sequence): decoded, or nil.
function M.object(line)
	local record = string.match(line, "{.*}")
	if record == nil then
		return nil
	end
	local ok, value = pcall(json.decode, record)
	if ok and type(value) == "table" then
		return value
	end
	return nil
end

-- The table `docker top` prints: a title line and a row for each process, in columns that are
-- separated by spaces, the last of them (the command) holding the rest of the line.
function M.table(text)
	local titles, rows = nil, {}
	for line in string.gmatch(text or "", "[^\n]+") do
		local fields = {}
		for word in string.gmatch(line, "%S+") do
			fields[#fields + 1] = word
		end
		if titles == nil then
			titles = fields
		elseif #fields > 0 then
			local count = #titles
			local row = {}
			local rest = line
			for index = 1, count - 1 do
				local word
				word, rest = string.match(rest, "^%s*(%S+)(.*)$")
				row[index] = word or ""
			end
			row[count] = string.match(rest or "", "^%s*(.-)%s*$") or ""
			rows[#rows + 1] = row
		end
	end
	return titles or {}, rows
end

-- What the program says of an image name: `sha256:abc…` is shown as its first twelve digits.
function M.image_name(name)
	if type(name) == "string" and string.sub(name, 1, 7) == "sha256:" then
		return string.sub(name, 8, 19)
	end
	return name
end

return M
