-- Which containers use which image, volume and network: the lists of Docker know their own
-- things, and what ties them to each other is worked out here from the containers.

local M = {}

-- Whether a container that was made from `reference` (what `docker ps` says: a name, or the
-- first digits of an image id) was made from `image`.
local function made_from(image, reference)
	if reference == nil or reference == "" then
		return false
	end
	if string.sub(image.id, 1, #reference) == reference then
		return true
	end
	for _, tag in ipairs(image.tags) do
		if tag == reference or tag == reference .. ":latest" then
			return true
		end
	end
	return false
end

-- Gives each image the names of the containers made from it (`containers`), and says which are
-- running (`running`).
function M.images(images, containers)
	for _, image in ipairs(images) do
		image.containers, image.running = {}, 0
		for _, container in ipairs(containers) do
			if made_from(image, container.image) then
				image.containers[#image.containers + 1] = container.name
				if container.state == "running" then
					image.running += 1
				end
			end
		end
		table.sort(image.containers)
	end
	return images
end

-- Gives each volume the names of the containers that mount it.
function M.volumes(volumes, containers)
	for _, volume in ipairs(volumes) do
		volume.containers = {}
		for _, container in ipairs(containers) do
			for _, mount in ipairs(container.mounts) do
				if mount == volume.name then
					volume.containers[#volume.containers + 1] = container.name
					break
				end
			end
		end
		table.sort(volume.containers)
	end
	return volumes
end

return M
