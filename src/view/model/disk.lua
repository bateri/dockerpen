-- The disk docker takes, as the system screen and the clean-up part it: what a part is called, what
-- colour it has, and which clean-ups free it.

local DISK = {
	{ key = "images", label = "Images", role = "accent", targets = { "dangling_images", "unused_images" } },
	{ key = "containers", label = "Containers", role = "success", targets = { "containers" } },
	{ key = "volumes", label = "Volumes", role = "warning", targets = { "volumes" } },
	{ key = "build_cache", label = "Build cache", role = "info", targets = { "build_cache" } },
}

return {
	DISK = DISK,
}
