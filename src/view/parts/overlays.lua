local lib_kit = require("../lib/kit")
local lib_sizes = require("../lib/sizes")
local model_state = require("../model/state")
local parts_ui = require("./ui")
local alpha, b, ui = lib_kit.alpha, lib_kit.b, lib_kit.ui
local SIZE = lib_sizes.SIZE
local S = model_state.S
local P, T = parts_ui.P, parts_ui.T

-- ---- over everything: the question, the help, the toasts, the jobs -----------------------------------

local overlays = {}

-- A question asked before something is removed. Its buttons are verbs, and the keys that answer
-- are on them.
function overlays.dialog()
	local d = S.dialog
	local card = b.div()
		:col()
		:gap(8)
		:p(18)
		:w(420)
		:max_w(520)
		:rounded(10)
		:bg("raised2")
		:border(1, "border")
		:shadow(0, 8, 24, alpha("shadow", 0.5))
	card:child(T(d.title, "foreground", 15, 650))
	if d.lines and d.lines.names then
		local list = b.div():col():gap(2):p(8):rounded(6):bg("raised1")
		for _, name in ipairs(d.lines.names) do
			list:child(P.line(name, "foreground", SIZE.small + 1))
		end
		card:child(list)
	end
	if d.lines and d.lines.note then
		card:child(T(d.lines.note, "dim", SIZE.small + 0.5):truncate():max_w(380))
	end
	if d.field then
		card:child(T(d.field.label, "dim", SIZE.small))
		card:child(P.field(true, d.field.hint))
	end
	local buttons = b.div():row():justify_end():gap(8):mt(6)
	local cancel = P.button("dialog:cancel", "Cancel", { key = "Esc", selected = d.choice == "cancel" })
	local confirm = P.button("dialog:confirm", d.confirm, {
		key = "y",
		danger = d.danger,
		primary = not d.danger,
		selected = d.choice == "confirm",
		disabled = d.field ~= nil and (d.text or "") == "",
	})
	if d.choice == "cancel" then
		cancel:border(1.5, "accent")
	else
		confirm:border(1.5, "accent")
	end
	buttons:child(cancel):child(confirm)
	card:child(buttons)
	return b.div()
		:absolute()
		:inset(0, 0, 0, 0)
		:row()
		:items_center()
		:justify_center()
		:bg(alpha("background", 0.6))
		:press("dialog:backdrop")
		:child(card)
end

local HELP = {
	{
		"Moving",
		{
			{ "↑ ↓  j k", "choose a row" },
			{ "g G  Home End", "first, last" },
			{ "⏎  →  ←", "open, fold / back" },
			{ "1 – 6", "the sections, from containers to activity" },
			{ "Tab", "list or detail" },
			{ "/", "filter, or search a log" },
		},
	},
	{
		"Containers",
		{
			{ "space  a  A", "mark, mark all, mark none; a project is all its own" },
			{ "s  r  p", "start or stop, restart, pause or resume" },
			{ "e  F", "a shell in it, its log as it comes (in the terminal)" },
			{ "l  i  [ ]", "logs, inspect, the tab before and after" },
			{ "K  d  z", "kill, remove (both ask first), take back the last stop" },
			{ "f  P  o", "next filter, group by project, sort" },
			{ "y  .", "copy the id, the menu of the row" },
		},
	},
	{
		"A log",
		{
			{ "↑ ↓  PgUp PgDn", "scroll; scrolling up stops following" },
			{ "End  t", "follow, timestamps" },
			{ "n  N", "next match, previous match" },
			{ "⇧←  ⇧→  0", "read further to the right, and back" },
			{ "L", "load more lines" },
		},
	},
	{
		"Everywhere",
		{
			{ "u  c", "pull an image, clean up" },
			{ "?  Esc", "this help, leave what is open" },
			{ "⌃C", "quit dockerpen" },
		},
	},
}

function overlays.help()
	local card = b.div()
		:col()
		:gap(4)
		:p(20)
		:w_pct(92)
		:max_w(660)
		:rounded(10)
		:bg("raised2")
		:border(1, "border")
		:shadow(0, 8, 24, alpha("shadow", 0.5))
	card:child(
		b.div():row():items_center():child(T("Keys", "foreground", 15, 650)):child(b.spacer()):child(P.kbd("Esc"))
	)
	local scroll = b.div():col():gap(2):no_shrink()
	for _, part in ipairs(HELP) do
		scroll:child(P.heading(part[1]))
		for _, entry in ipairs(part[2]) do
			scroll:child(
				b.div()
					:row()
					:gap(14)
					:min_h(20)
					:child(b.div():w(150):no_shrink():child(T(entry[1], "foreground", SIZE.small + 1, 600)))
					:child(b.div():grow(1):min_w(0):child(P.line(entry[2], "dim", SIZE.small + 1)))
			)
		end
	end
	card:child(
		b.div()
			:col()
			:id("help.scroll")
			:h(math.max(math.min(S.height - 200, 440), 120))
			:scroll_y(ui:scroll_offset("help.scroll"))
			:child(scroll)
	)
	card:child(
		T(
			"Everything the pointer does, the keys do too: rows answer a click, ⌘-click or ⇧-click marks, right-click opens the menu of the row.",
			"quiet",
			SIZE.small
		):truncate()
	)
	return b.div()
		:absolute()
		:inset(0, 0, 0, 0)
		:row()
		:items_center()
		:justify_center()
		:bg(alpha("background", 0.6))
		:press("help:backdrop")
		:child(card)
end

-- What was said for a moment, at the end of the page.
function overlays.toasts()
	local stack = b.div():absolute():inset(nil, 16, SIZE.status + 12, nil):col():gap(6):items_end()
	for index, item in ipairs(S.toasts) do
		local id = "toast:" .. index
		local role = item.kind == "info" and "foreground" or item.kind
		local el = b.div()
			:press(id)
			:row()
			:items_center()
			:gap(10)
			:p(10)
			:pl(12)
			:max_w(480)
			:rounded(8)
			:bg("raised3")
			:border(1, alpha(role, 0.55))
			:shadow(0, 4, 14, alpha("shadow", 0.45))
		el:child(b.div():w(3):h(16):rounded(1.5):bg(role):no_shrink())
		el:child(b.div():min_w(0):child(T(item.text, "foreground", SIZE.small + 1):truncate()))
		if item.action then
			el:child(
				P.button(
					"toast.action:" .. index,
					item.action.label,
					{ key = index == #S.toasts and "z" or nil, h = 22, px = 8, size = SIZE.small + 0.5 }
				)
			)
		end
		stack:child(el)
	end
	return stack
end

-- The jobs that are running, as a line of how far each has come.
function overlays.jobs()
	local running = {}
	for _, job in ipairs(S.jobs) do
		if job.state == "running" then
			running[#running + 1] = job
		end
	end
	if #running == 0 then
		return nil
	end
	local strip = b.div():col():gap(4):px(20):py(6):no_shrink():bg("raised1")
	for _, job in ipairs(running) do
		local row = b.div():row():items_center():gap(10):h(18)
		row:child(T(job.title, "foreground", SIZE.small + 0.5, 600):no_shrink())
		row:child(b.div():w(0):grow(1):min_w(0):child(P.line(job.detail or "", "dim", SIZE.small)))
		if job.progress then
			row:child(P.meter(job.progress, "accent", 120))
		else
			row:child(T("working…", "dim", SIZE.small):no_shrink())
		end
		strip:child(row)
	end
	return strip
end

return {
	overlays = overlays,
}
