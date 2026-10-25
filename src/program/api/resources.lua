-- The calls about what containers are made of and run on: images (with their layers, pulling and
-- removing), volumes, networks, and the disk Docker takes with the clean-up of what nothing uses.
--
-- This is api/'s: the files of api/ know the page; docker/, state/ and terminal/ do not.

local pencere = require("pencere")
local json = pencere.json

local images = require("docker.images")
local links = require("state.links")
local networks = require("docker.networks")
local system = require("docker.system")
local volumes = require("docker.volumes")

local call = require("api.call")
local params = require("api.params")

local M = {}

local MOST = 500

-- The containers as last listed: what an answer names containers by.
local function listed(session)
	local snapshot = session.containers.last
	return snapshot and snapshot.containers or {}
end

-- Does `remove(item)` to each of `items` and says what became of each: one failing does not
-- stop the others.
local function remove_each(items, remove)
	local outcomes = {}
	for _, item in ipairs(items) do
		local ok, why = pcall(remove, item)
		outcomes[#outcomes + 1] = {
			id = item,
			name = item,
			ok = ok,
			error = (not ok) and (type(why) == "table" and why.message or tostring(why)) or nil,
		}
	end
	return outcomes
end

function M.calls(session)
	local calls = {}

	-- ---- images ----

	calls.images = call.new(params.nothing, function()
		return { images = links.images(images.list(), listed(session)) }
	end)

	-- The layers of an image, newest first.
	calls.image_layers = call.new(params.one_id, function(args)
		return { layers = images.history(args.id) }
	end)

	calls.image_remove = call.new(
		params.object({ ids = params.some(params.string(1), MOST), force = params.optional(params.boolean()) }),
		function(args)
			return {
				outcomes = remove_each(args.ids, function(id)
					images.remove(id, args.force == true)
				end),
			}
		end
	)

	-- Pulls an image or a tag; the pull is a job the page follows (the topic `jobs`).
	calls.pull = call.new(params.object({ reference = params.string(1) }), function(args)
		local reference = string.gsub(args.reference, "^%s*(.-)%s*$", "%1")
		if reference == "" or string.find(reference, "^%-") or string.find(reference, "%s") then
			error({ code = "bad-params", message = "that is not an image name" }, 0)
		end
		return { job = session.jobs:pull(reference) }
	end)

	-- ---- volumes ----

	calls.volumes = call.new(params.nothing, function()
		local list = links.volumes(volumes.list(), listed(session))
		local sizes = session.volume_sizes
		for _, volume in ipairs(list) do
			volume.size = sizes and sizes[volume.name] or json.null
		end
		return { volumes = list, sized = sizes ~= nil }
	end)

	-- How much each volume takes: the engine counts them, which can take a while, so the page
	-- asks for it apart from the list.
	calls.volume_sizes = call.new(params.nothing, function()
		local sizes = volumes.sizes()
		session.volume_sizes = sizes
		return { sizes = sizes }
	end)

	calls.volume_remove = call.new(params.object({ names = params.some(params.string(1), MOST) }), function(args)
		session.volume_sizes = nil
		return { outcomes = remove_each(args.names, volumes.remove) }
	end)

	-- ---- networks ----

	calls.networks = call.new(params.nothing, function()
		return { networks = networks.list() }
	end)

	calls.network_remove = call.new(params.object({ ids = params.some(params.string(1), MOST) }), function(args)
		return { outcomes = remove_each(args.ids, networks.remove) }
	end)

	-- ---- the disk, and the clean-up ----

	-- The disk Docker takes (what is in use, what nothing uses), and the engine it is.
	calls.system = call.new(params.nothing, function()
		local snapshot = session.containers.last
		local engine = snapshot and snapshot.engine
		if engine == nil then
			engine = system.info()
		end
		return { usage = system.usage(), engine = engine }
	end)

	-- Removes what nothing uses; the clean-up is a job the page follows (the topic `jobs`).
	calls.prune = call.new(
		params.object({
			targets = params.some(
				params.enum("containers", "dangling_images", "unused_images", "volumes", "networks", "build_cache"),
				6
			),
		}),
		function(args)
			return { job = session.jobs:prune(args.targets) }
		end
	)

	return calls
end

return M
