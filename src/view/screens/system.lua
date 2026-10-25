local lib_kit = require("../lib/kit")
local lib_fmt = require("../lib/fmt")
local lib_sizes = require("../lib/sizes")
local model_disk = require("../model/disk")
local model_rows = require("../model/rows")
local model_state = require("../model/state")
local parts_ui = require("../parts/ui")
local b, ui = lib_kit.b, lib_kit.ui
local fmt = lib_fmt.fmt
local SIZE = lib_sizes.SIZE
local DISK = model_disk.DISK
local counts = model_rows.counts
local S = model_state.S
local P, T = parts_ui.P, parts_ui.T

local screens = {}

function screens.system(width)
	local col = b.div():col():grow(1):min_w(0):min_h(0)
	local engine = (S.system and S.system.engine) or S.engine
	col:child(P.title("System", engine and (engine.name .. " · Docker " .. engine.version) or nil, {
		P.button("act:clean", "Clean up…", { key = "c", primary = true }),
	}))
	local body = b.div():col():gap(10):px(20):pb(20):no_shrink()
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
		local summary = P.card():gap(10)
		summary:child(
			b.div()
				:row()
				:items_center()
				:gap(10)
				:child(T("DISK", "quiet", SIZE.tiny + 0.5, 600))
				:child(T(fmt.disk(total), "foreground", 20, 650))
				:child(T(fmt.disk(freed) .. " can be freed", freed > 0 and "success" or "dim", SIZE.body))
		)
		local bar = b.div():row():h(10):rounded(5):clip():gap(1):bg("raised2")
		for _, kind in ipairs(DISK) do
			local size = usage[kind.key].size
			if size > 0 then
				bar:child(b.div():w(0):grow(size):h(10):bg(kind.role))
			end
		end
		summary:child(bar)
		local legend = b.div():row():gap(14):wrap()
		for _, kind in ipairs(DISK) do
			legend:child(
				b.div()
					:row()
					:items_center()
					:gap(6)
					:child(P.dot(kind.role, true, 8))
					:child(T(kind.label, "dim", SIZE.small))
			)
		end
		summary:child(legend)
		body:child(summary)
		local cards = b.div():row():gap(8):wrap()
		for _, kind in ipairs(DISK) do
			local part = usage[kind.key]
			local id = "free:" .. kind.target
			cards:child(
				P.card()
					:w(0)
					:grow(1)
					:min_w(170)
					:gap(6)
					:child(
						b.div()
							:row()
							:items_center()
							:gap(8)
							:child(P.dot(kind.role, true, 8))
							:child(T(kind.label, "foreground", SIZE.body, 600):no_shrink())
							:child(b.spacer())
							:child(T(part.active .. "/" .. part.count .. " in use", "quiet", SIZE.small):no_shrink())
					)
					:child(T(fmt.disk(part.size), "foreground", 18, 650))
					:child(
						b.div()
							:row()
							:items_center()
							:h(26)
							:child(
								T(
									part.reclaimable > 0 and (fmt.disk(part.reclaimable) .. " unused")
										or "nothing unused",
									"dim",
									SIZE.small
								)
							)
							:child(b.spacer())
							:child(
								P.button(
									id,
									"Free…",
									{ h = 22, px = 8, size = SIZE.small + 0.5, disabled = part.reclaimable == 0 }
								)
							)
					)
			)
		end
		body:child(cards)
	end
	if engine then
		local card = P.card():gap(2)
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
					.. fmt.bytes(engine.memory)
			)
		)
		card:child(P.fact("endpoint", engine.endpoint ~= "" and engine.endpoint or "the docker command's own"))
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
