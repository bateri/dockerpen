local lib_fmt = require("../lib/fmt")
local model_state = require("./state")
local fmt = lib_fmt.fmt
local S = model_state.S

-- ---- the system: the disk docker takes -----------------------------------------------------------------

local DISK = {
	{ key = "images", label = "Images", role = "accent", target = "unused_images", title = "Unused images" },
	{ key = "containers", label = "Containers", role = "success", target = "containers", title = "Stopped containers" },
	{ key = "volumes", label = "Volumes", role = "warning", target = "volumes", title = "Unused volumes" },
	{ key = "build_cache", label = "Build cache", role = "info", target = "build_cache", title = "Build cache" },
}

-- What a clean-up of everything would free, and what it would take away.
local function all_that_can_be_freed()
	local usage = S.system and S.system.usage
	local targets_, titles, freed = {}, {}, 0
	if usage == nil then
		return targets_, titles, 0
	end
	for _, kind in ipairs(DISK) do
		local part = usage[kind.key]
		if part and part.reclaimable > 0 then
			targets_[#targets_ + 1] = kind.target
			titles[#titles + 1] = kind.title .. " (" .. fmt.disk(part.reclaimable) .. ")"
			freed += part.reclaimable
		end
	end
	return targets_, titles, freed
end

return {
	DISK = DISK,
	all_that_can_be_freed = all_that_can_be_freed,
}
