-- What comes over the page: the question before something is done, the keys, the toasts, the jobs.
-- (The menu is the host's, and is asked for with a reply; the palette has its own part.)

local lib_kit = require("../lib/kit")
local lib_sizes = require("../lib/sizes")
local model_dialog = require("../model/dialog")
local model_state = require("../model/state")
local parts_ui = require("./ui")
local alpha, b, ui = lib_kit.alpha, lib_kit.b, lib_kit.ui
local SIZE = lib_sizes.SIZE
local dialog = model_dialog.dialog
local S = model_state.S
local fmt = require("../lib/fmt").fmt
local P, T, hovered = parts_ui.P, parts_ui.T, parts_ui.hovered

local overlays = {}

-- A scrim over everything with a card in it; a press on the scrim (not on the card) is `id`.
local function over(card, id, top)
	card:press("overlay:card")
	local scrim = b.div():absolute():inset(0, 0, 0, 0):col():items_center():bg(alpha("background", 0.62)):press(id)
	if top then
		scrim:pt(top)
	else
		scrim:justify_center()
	end
	return scrim:child(card)
end

local function card_of(width)
	return b.div()
		:col()
		:gap(12)
		:p(18)
		:w(width)
		:rounded(16)
		:bg("raised2")
		:border(1, alpha("border", 0.7))
		:shadow(0, 12, 32, alpha("shadow", 0.55))
end

-- A box with a mark that stands for what is asked: red where it is a danger, the info colour where
-- it is a clean-up.
local function mark_box(name, role)
	return b.div()
		:size(30, 30)
		:rounded(9)
		:row()
		:items_center()
		:justify_center()
		:no_shrink()
		:bg(alpha(role, 0.14))
		:child(P.icon(name, 16, role))
end

-- One box to tick: its words, what it means, and (where docker has counted) how much it holds.
local function option_row(d, index, option)
	local on = d.values[option.key]
	local id = "dialog:option:" .. index
	local row = b.div():row():items_start():gap(10):px(10):py(9):rounded(8):press(id):no_shrink()
	row:bg(hovered(id) and "raised2" or "raised1")
	if d.cursor == index and #d.options > 1 then
		row:border(1, alpha("accent", 0.5))
	end
	row:child(b.div():pt(1):child(P.check(on)))
	local main = b.div():col():grow(1):min_w(0):child(T(option.label, "foreground", SIZE.body))
	if option.hint then
		main:child(T(option.hint, "quiet", SIZE.small):truncate())
	end
	row:child(main)
	local size = dialog.size_of(option)
	if size then
		row:child(T(fmt.bytes(size), "dim", SIZE.small + 0.5):no_shrink())
	end
	return row
end

-- A question: what is asked, boxes to tick, and the two answers.
function overlays.dialog()
	local d = S.dialog
	local wide = d.kind == "prune"
	local card_w = math.min(wide and 620 or 440, S.width - 32)
	local card = card_of(card_w)
	local head = b.div():row():gap(12):items_start()
	local text_w = card_w - 36 - ((d.danger or d.kind == "prune") and 42 or 0)
	if d.danger then
		head:child(mark_box("triangle-alert", "error"))
	elseif d.kind == "prune" then
		head:child(mark_box("sparkles", "info"))
	end
	head:child(
		b.div()
			:col()
			:gap(6)
			:grow(1)
			:min_w(0)
			:child(T(d.title, "foreground", 14, 650):truncate())
			:child(P.paragraph(d.body or "", text_w, "dim", SIZE.body))
	)
	card:child(head)
	if d.kind == "pull" then
		local text = d.reference or ""
		card:child(
			b.div()
				:row()
				:items_center()
				:gap(8)
				:h(34)
				:px(10)
				:rounded(8)
				:bg("background")
				:border(1, S.typing and "accent" or alpha("border", 0.8))
				:press("field")
				:child(P.icon("download", 14, "quiet"))
				:child(P.room(20, "nginx:alpine"))
		)
		if string.gsub(text, "%s", "") ~= "" and not S.typing then
			card:child(T("Pull " .. text, "dim", SIZE.small))
		end
		local chips = b.div():row():wrap():gap(6)
		for index, name in ipairs(dialog.SUGGESTIONS) do
			local id = "dialog:suggest:" .. index
			chips:child(
				b.div()
					:row()
					:items_center()
					:h(22)
					:px(8)
					:rounded(11)
					:press(id)
					:bg(name == text and alpha("accent", 0.2) or (hovered(id) and "raised3" or "raised2"))
					:child(T(name, (name == text or hovered(id)) and "foreground" or "dim", SIZE.small))
			)
		end
		card:child(chips)
	end
	if d.options and #d.options > 0 then
		local list = b.div():col():gap(4)
		for index, option in ipairs(d.options) do
			list:child(option_row(d, index, option))
		end
		card:child(list)
	end
	local actions = b.div():row():items_center():gap(8):mt(4)
	if d.kind == "prune" then
		local total = dialog.total()
		local note = b.div():grow(1):min_w(0):row():items_center():gap(5)
		if total and total > 0 then
			note:child(T("About", "dim", SIZE.body))
				:child(T(fmt.bytes(total), "foreground", SIZE.body, 650))
				:child(T("to free", "dim", SIZE.body))
		end
		actions:child(note)
	else
		actions:child(b.spacer())
	end
	actions:child(P.button("dialog:cancel", "Cancel", { variant = "ghost", suffix = "esc" }))
	actions:child(P.button("dialog:confirm", d.confirm, {
		variant = d.danger and "danger" or "primary",
		suffix = "⏎",
		disabled = not dialog.ready(),
	}))
	card:child(actions)
	return over(card, "dialog:backdrop")
end

-- The keys, a section at a time, as the original lists them (what this page cannot do is not here).
local HELP = {
	{
		"Anywhere",
		{
			{ "Command palette", { ":", "⌃K" } },
			{ "Go to a section", { "1", "–", "6" } },
			{ "Search", { "/" } },
			{ "Refresh", { "R" } },
			{ "Keyboard shortcuts", { "?" } },
			{ "Close, go back", { "esc" } },
			{ "Quit dockerpen", { "⌃C" } },
		},
	},
	{
		"Lists",
		{
			{ "Move", { "↑", "↓" } },
			{ "Move", { "j", "k" } },
			{ "First, last", { "g", "G" } },
			{ "Mark, for many at once", { "space" } },
			{ "Mark all, none", { "a", "A" } },
			{ "Open, expand", { "⏎", "→" } },
			{ "Close, collapse", { "←" } },
			{ "Context menu", { "." } },
		},
	},
	{
		"Containers",
		{
			{ "Start or stop", { "s" } },
			{ "Restart", { "r" } },
			{ "Pause or resume", { "p" } },
			{ "Shell in the terminal", { "e" } },
			{ "Logs", { "l" } },
			{ "Follow logs in the terminal", { "F" } },
			{ "Inspect", { "i" } },
			{ "Copy the published port's address", { "o" } },
			{ "Copy the id", { "y" } },
			{ "Kill", { "K" } },
			{ "Remove", { "d" } },
			{ "Next filter", { "f" } },
			{ "Group by compose project", { "P" } },
		},
	},
	{
		"The detail panel",
		{
			{ "Between list and panel", { "tab" } },
			{ "Previous, next tab", { "[", "]" } },
			{ "Logs: follow", { "space" } },
			{ "Logs: timestamps, wrap", { "t", "w" } },
			{ "Logs: next, previous match", { "n", "N" } },
			{ "Wider, narrower", { "<", ">" } },
		},
	},
}

local function keys_cell(keys)
	local cell = b.div():row():items_center():gap(3):no_shrink()
	for _, key in ipairs(keys) do
		if key == "–" then
			cell:child(T("–", "quiet", SIZE.small))
		else
			cell:child(P.kbd(key))
		end
	end
	return cell
end

function overlays.help()
	local card_w = math.min(620, S.width - 32)
	local card = card_of(card_w)
	card:child(
		b.div()
			:row()
			:items_center()
			:child(T("Keyboard shortcuts", "foreground", 14, 650):grow(1))
			:child(P.button("help:close", nil, { variant = "ghost", size = "sm", icon = "x", icon_size = 14 }))
	)
	card:child(
		P.paragraph(
			"Everything the mouse does, the keys do too. A key acts on the marked containers, or on the chosen one.",
			card_w - 36,
			"dim",
			SIZE.body
		)
	)
	-- Two columns of at least 230 where there is room for them, else one (the grid's own 4 at the end).
	local tracks = card_w - 40 >= 484 and { b.fr(1), b.fr(1) } or { b.fr(1) }
	local grid = b.div():grid(tracks):gap_x(24):gap_y(2):pr(4)
	for _, part in ipairs(HELP) do
		grid:child(b.div():span(#tracks):pt(10):pb(2):child(T(string.upper(part[1]), "quiet", SIZE.tiny + 0.5)))
		for _, row in ipairs(part[2]) do
			grid:child(
				b.div()
					:row()
					:items_center()
					:justify_between()
					:gap(10)
					:min_h(26)
					:child(T(row[1], "dim", SIZE.small + 1):truncate())
					:child(keys_cell(row[2]))
			)
		end
	end
	card:child(
		b.div()
			:col()
			:id("help.scroll")
			:h(math.max(math.min(S.height - 200, 480), 120))
			:scroll_y(ui:scroll_offset("help.scroll"))
			:child(grid)
	)
	return over(card, "help:backdrop", math.min(math.floor(S.height * 0.12), 80))
end

-- What was said for a moment, at the end of the page.
function overlays.toasts()
	local stack = b.div()
		:absolute()
		:inset(nil, 12, SIZE.status + 10, nil)
		:col()
		:gap(8)
		:w(math.min(340, S.width - 24))
		:items_stretch()
	local marks = { success = "circle-check", error = "circle-alert", warning = "triangle-alert", info = "info" }
	local roles = { success = "success", error = "error", warning = "warning", info = "info" }
	local toast_w = math.min(340, S.width - 24)
	for index, item in ipairs(S.toasts) do
		local id = "toast:" .. index
		-- The room the words have: the toast less its padding, the mark, the gaps and the buttons.
		local actions_w = 24 + (item.action and (#item.action.label * 7.2 + 16 + 2) or 0)
		local words_w = math.max(toast_w - 12 - 8 - 15 - 20 - actions_w, 60)
		local role = roles[item.kind] or "info"
		local el = b.div()
			:press(id)
			:row()
			:gap(10)
			:items_start()
			:pl(12)
			:pr(8)
			:py(10)
			:rounded(12)
			:bg("raised2")
			:border(1, alpha("border", 0.7))
			:shadow(0, 6, 18, alpha("shadow", 0.5))
		el:child(b.div():pt(1):child(P.icon(marks[item.kind] or "info", 15, role)))
		local text = b.div():col():gap(2):grow(1):min_w(0)
		text:child(P.paragraph(item.text or "", words_w, "foreground", SIZE.body, 600, 3))
		if item.body then
			text:child(P.paragraph(item.body, words_w, "dim", SIZE.small + 0.5, nil, 4))
		end
		el:child(text)
		local actions = b.div():row():items_center():gap(2):mt(-3):no_shrink()
		if item.action then
			actions:child(
				P.button(
					"toast.action:" .. index,
					item.action.label,
					{ variant = "ghost", size = "sm", ink = "accent" }
				)
			)
		end
		actions:child(
			P.button("toast.x:" .. index, nil, { variant = "ghost", size = "sm", icon = "x", icon_size = 13 })
		)
		el:child(actions)
		stack:child(el)
	end
	return stack
end

-- The jobs, as a list over the status line: what runs and how far it has come, what ended.
function overlays.jobs()
	if not S.jobs_open or #S.jobs == 0 then
		return nil
	end
	local card = b.div()
		:col()
		:p(6)
		:rounded(12)
		:bg("raised2")
		:border(1, alpha("border", 0.7))
		:shadow(0, 6, 18, alpha("shadow", 0.5))
		:absolute()
		:inset(nil, 8, SIZE.status + 6, nil)
		:w(math.min(340, S.width - 24))
		:press("overlay:card")
	local index = 0
	for position = #S.jobs, 1, -1 do
		local job = S.jobs[position]
		index += 1
		local el = b.div():col():gap(6):p(8)
		if index > 1 then
			card:child(b.div():h(1):px(6):bg(alpha("border", 0.4)):no_shrink())
		end
		local role = job.state == "running" and "accent" or (job.state == "done" and "success" or "error")
		local mark = job.state == "running" and "loader" or (job.state == "done" and "circle-check" or "circle-alert")
		el:child(
			b.div()
				:row()
				:items_center()
				:gap(8)
				:child(P.icon(mark, 13, role))
				:child(P.line(job.title, "foreground", SIZE.body, 600):grow(1))
		)
		if job.state == "running" then
			el:child(P.meter(job.progress or 0.04, "accent"))
		end
		local detail = job.state == "failed" and (job.error or job.detail) or job.detail
		if detail and detail ~= "" then
			el:child(P.line(detail, "dim", SIZE.small + 0.5))
		end
		card:child(el)
	end
	return b.div():absolute():inset(0, 0, 0, 0):press("jobs:backdrop"):child(card)
end

return {
	overlays = overlays,
}
