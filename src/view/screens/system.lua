local lib_kit = require("../lib/kit")
local lib_fmt = require("../lib/fmt")
local lib_sizes = require("../lib/sizes")
local model_disk = require("../model/disk")
local model_rows = require("../model/rows")
local model_state = require("../model/state")
local parts_ui = require("../parts/ui")
local alpha, b, ui = lib_kit.alpha, lib_kit.b, lib_kit.ui
local fmt = lib_fmt.fmt
local SIZE = lib_sizes.SIZE
local DISK = model_disk.DISK
local counts = model_rows.counts
local S = model_state.S
local P, T = parts_ui.P, parts_ui.T

local screens = {}

local MARKS = { images = "layers", containers = "box", volumes = "hard-drive", build_cache = "zap" }

function screens.system(width)
	local col = b.div():col():grow(1):min_w(0):min_h(0)
	local engine = (S.system and S.system.engine) or S.engine
	col:child(P.title("System", engine and (engine.name .. " · Docker " .. engine.version) or nil, {
		P.button("act:clean", "Clean up", { variant = "primary", size = "sm", icon = "sparkles", icon_size = 13 }),
	}))
	local body = b.div():col():gap(8):px(14):pt(4):pb(20):no_shrink()
	if S.problems.system then
		body:child(T(S.problems.system, "error", SIZE.small))
	end
	local usage = S.system and S.system.usage
	if usage == nil then
		body:child(T(S.problems.system and "" or "Counting the disk…", "dim", SIZE.body))
	else
		local total, freed = 0, 0
		for _, kind in ipairs(DISK) do
			total += usage[kind.key].size
			freed += usage[kind.key].reclaimable
		end
		local summary = P.card():gap(12):p(14)
		local head = b.div():row():items_center():gap(10)
		head:child(T("DISK", "quiet", SIZE.tiny + 0.5, 500))
		head:child(T(fmt.bytes(total), "foreground", 22, 600))
		if freed > 0 then
			head:child(T(fmt.bytes(freed), "success", SIZE.body, 650)):child(T("can be freed", "dim", SIZE.body))
		end
		summary:child(head)
		local bar = b.div():row():h(10):rounded(5):clip():gap(1):bg("raised2")
		for _, kind in ipairs(DISK) do
			local share = math.max(math.floor(usage[kind.key].size / math.max(total, 1) * 1000), 4)
			bar:child(b.div():w(0):grow(share):h(10):bg(kind.role))
		end
		summary:child(bar)
		local legend = b.div():row():gap(14):wrap()
		for _, kind in ipairs(DISK) do
			legend:child(
				b.div()
					:row()
					:items_center()
					:gap(6)
					:child(P.disc(kind.role, 7))
					:child(T(kind.label, "dim", SIZE.small + 0.5))
			)
		end
		summary:child(legend)
		body:child(summary)
		local cards = b.div():row():gap(8):wrap()
		for index, kind in ipairs(DISK) do
			local part = usage[kind.key]
			local id = "free:" .. kind.key
			local card = P.card():w(0):grow(1):min_w(210):gap(6)
			if S.system_pick == index then
				card:bg(alpha("accent", 0.13)):border(1, alpha("accent", 0.55))
			end
			card:press("part:" .. index)
			card:child(
				b.div()
					:row()
					:items_center()
					:gap(8)
					:child(
						b.div()
							:size(22, 22)
							:rounded(6)
							:row()
							:items_center()
							:justify_center()
							:bg(alpha(kind.role, 0.14))
							:child(P.icon(MARKS[kind.key], 13, kind.role))
					)
					:child(T(kind.label, "foreground", SIZE.body, 650):no_shrink())
					:child(b.spacer())
					:child(T(part.active .. "/" .. part.count .. " in use", "quiet", SIZE.small):no_shrink())
			)
			card:child(T(fmt.bytes(part.size), "foreground", 17, 600))
			card:child(
				b.div()
					:row()
					:items_center()
					:h(24)
					:child(
						T(
							part.reclaimable > 0 and (fmt.bytes(part.reclaimable) .. " unused") or "nothing unused",
							"dim",
							SIZE.small + 0.5
						)
					)
					:child(b.spacer())
					:child(
						P.button(
							id,
							"Free",
							{ variant = "ghost", size = "sm", icon = "trash-2", disabled = part.reclaimable == 0 }
						)
					)
			)
			cards:child(card)
		end
		body:child(cards)
	end
	if engine then
		local card = P.card():gap(2):p(14)
		card:child(T("ENGINE", "quiet", SIZE.tiny + 0.5, 600))
		card:child(P.fact("runs on", engine.name))
		card:child(P.fact("docker", engine.version))
		card:child(
			P.fact(
				"machine",
				engine.os
					.. "/"
					.. engine.arch
					.. " · "
					.. fmt.count(engine.cpus, "cpu")
					.. " · "
					.. fmt.memory(engine.memory)
			)
		)
		card:child(P.fact("socket", engine.endpoint ~= "" and engine.endpoint or "the docker command's own"))
		local count = counts()
		card:child(P.fact("containers", count.running .. " running of " .. count.all))
		if S.hostname ~= "" then
			card:child(P.fact("dockerpen on", S.hostname .. (S.remote and " (over ssh)" or "")))
		end
		body:child(card)
	end
	return col:child(
		b.div():col():id("system.scroll"):grow(1):min_h(0):scroll_y(ui:scroll_offset("system.scroll")):child(body)
	)
end

return {
	screens = screens,
}
