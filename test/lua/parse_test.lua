-- What the program reads of what docker prints.

local t = require("t")
local parse = require("docker.parse")

t.test("sizes as docker writes them, decimal and binary", function()
	t.eq(parse.bytes("0B"), 0)
	t.eq(parse.bytes("1.5kB"), 1500)
	t.eq(parse.bytes("52.5MB"), 52500000)
	t.eq(parse.bytes("1.06GB"), 1060000000)
	t.eq(parse.bytes("936KiB"), 958464)
	t.eq(parse.bytes("7.266MiB"), 7618953)
	t.eq(parse.bytes("11.73GiB"), 12594991596)
	t.eq(parse.bytes("N/A"), nil)
	t.eq(parse.bytes(nil), nil)
	t.eq(parse.bytes("12 parsecs"), nil)
end)

t.test("pairs and percentages of docker stats", function()
	local used, limit = parse.pair("48.2MiB / 512MiB")
	t.eq(used, "48.2MiB")
	t.eq(limit, "512MiB")
	t.eq(parse.percent("37.60%"), 37.6)
	t.eq(parse.percent("--"), nil)
	t.eq(parse.reclaimable("6.366GB (37%)"), 6366000000)
	t.eq(parse.reclaimable("0B"), 0)
end)

t.test("the ports of docker ps are told once each, the published ones first", function()
	local ports = parse.ports("5432/tcp, 0.0.0.0:8088->80/tcp, [::]:8088->80/tcp, :::6379->6379/tcp")
	t.eq(ports, {
		{ public = 6379, private = 6379, type = "tcp", ip = "::" },
		{ public = 8088, private = 80, type = "tcp", ip = "0.0.0.0" },
		{ private = 5432, type = "tcp" },
	})
	t.eq(parse.ports(""), {})
	t.eq(parse.ports("0.0.0.0:8000-8010->8000-8010/tcp"), {
		{ public = 8000, private = 8000, type = "tcp", ip = "0.0.0.0" },
	})
end)

t.test("labels, with a comma inside a value", function()
	local labels = parse.labels("com.docker.compose.project=shop,note=a,b,c,x.y/z=1")
	t.eq(labels["com.docker.compose.project"], "shop")
	t.eq(labels.note, "a,b,c")
	t.eq(labels["x.y/z"], "1")
	t.eq(parse.labels(""), {})
end)

t.test("health and the exit code, from the words of a status", function()
	t.eq(parse.status("Up 3 minutes (healthy)", "running"), { health = "healthy" })
	t.eq(parse.status("Up 3 minutes (unhealthy)", "running"), { health = "unhealthy" })
	t.eq(parse.status("Up 3 seconds (health: starting)", "running"), { health = "starting" })
	t.eq(parse.status("Exited (137) 3 days ago", "exited"), { health = "none", exit_code = 137 })
	-- A stopped container keeps the health of its last check, which says nothing now.
	t.eq(parse.status("Exited (0) 1 hour ago (healthy)", "exited"), { health = "none", exit_code = 0 })
end)

t.test("dates as docker writes them, in seconds since 1970", function()
	t.eq(parse.time("2026-10-25 13:57:05 +0300 +03"), 1792925825)
	t.eq(parse.time("2026-10-25T10:57:05Z"), 1792925825)
	t.eq(parse.time("2026-10-25T13:57:05.123456789+03:00"), 1792925825)
	t.eq(parse.time("2026-10-13 22:19:34.660958252 +0300 +03"), 1791919174)
	t.eq(parse.time("0001-01-01T00:00:00Z"), nil)
	t.eq(parse.time(nil), nil)
end)

t.test("a line of a log with its time, and one without", function()
	local time, text = parse.log_line("2026-10-25T10:57:08.502743316Z oops 5")
	t.eq(time, "2026-10-25T10:57:08.502743316Z")
	t.eq(text, "oops 5")
	local none, whole = parse.log_line("Error response from daemon: no such container")
	t.eq(none, nil)
	t.eq(whole, "Error response from daemon: no such container")
end)

t.test("lines keep the empty ones and end without a ghost", function()
	t.eq(parse.lines("a\n\nb\n"), { "a", "", "b" })
	t.eq(parse.lines("a\r\nb"), { "a", "b" })
	t.eq(parse.lines("a\nb\nc", 2), { "a", "b" })
	t.eq(parse.lines(""), {})
end)

t.test("objects are the lines that are JSON, the rest is left", function()
	local list = parse.objects('warning: something\n{"a":1}\n\n{"b":[1,2]}\nnot json {\n')
	t.eq(#list, 2)
	t.eq(list[1].a, 1)
	t.eq(parse.object('\27[2J{"ID":"x"}').ID, "x")
	t.eq(parse.object("nothing here"), nil)
end)

t.test("the table docker top prints, its last column holding the rest of the line", function()
	local titles, rows = parse.table("PID  USER  TIME  COMMAND\n42   root  0:01  sh -c  sleep 5\n")
	t.eq(titles, { "PID", "USER", "TIME", "COMMAND" })
	t.eq(rows, { { "42", "root", "0:01", "sh -c  sleep 5" } })
end)

t.test("an image that is named by its digest is shown by its first digits", function()
	t.eq(parse.image_name("sha256:0123456789abcdef0123"), "0123456789ab")
	t.eq(parse.image_name("nginx:alpine"), "nginx:alpine")
end)
