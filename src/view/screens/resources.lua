local lib_kit = require("../lib/kit")
local lib_fmt = require("../lib/fmt")
local lib_sizes = require("../lib/sizes")
local lib_virtual = require("../lib/virtual")
local model_containers = require("../model/containers")
local model_rows = require("../model/rows")
local model_state = require("../model/state")
local parts_ui = require("../parts/ui")
local screens_containers = require("./containers")
local alpha, b = lib_kit.alpha, lib_kit.b
local fmt = lib_fmt.fmt
local LIST_MEDIUM, SIZE = lib_sizes.LIST_MEDIUM, lib_sizes.SIZE
local virtual = lib_virtual.virtual
local ago = model_containers.ago
local image_title, marked, plain_rows = model_rows.image_title, model_rows.marked, model_rows.plain_rows
local S = model_state.S
local P, T, hovered = parts_ui.P, parts_ui.T, parts_ui.hovered
local COL, columns = screens_containers.COL, screens_containers.columns

local screens = {}

-- ---- images, volumes, networks: lists of what containers are made of -----------------------------------

-- A list with one row for each of what `spec` says: its columns and its verb.
local function plain_screen(section, spec, width)
	local rows = plain_rows(section)
	local col = b.div():col():grow(1):min_w(0):min_h(0)
	col:child(P.title(spec.title, spec.subtitle(), spec.verbs))
	local bar = b.div():row():items_center():gap(8):h(SIZE.bar):px(20):no_shrink()
	bar:child(P.field(S.field == "list", spec.hint, width >= 700 and 260 or nil))
	bar:child(b.spacer())
	local chosen = marked(section)
	if #chosen > 0 then
		bar:child(T(#chosen .. " marked", "accent", SIZE.small + 0.5))
		bar:child(P.button("act:remove", "Remove…", { danger = true, key = "d", h = 24, size = SIZE.small + 0.5 }))
	end
	col:child(bar)
	if S.problems[section] then
		col:child(
			b.div()
				:row()
				:items_center()
				:h(26)
				:px(20)
				:no_shrink()
				:bg(alpha("error", 0.1))
				:child(T(S.problems[section], "error", SIZE.small):truncate())
		)
	end
	if S.lists[section] == nil and not S.problems[section] then
		return col:child(P.nothing("Looking…"))
	end
	if #rows == 0 then
		if S.query ~= "" then
			return col:child(P.nothing("Nothing matches “" .. S.query .. "”"))
		end
		return col:child(P.nothing(spec.empty))
	end
	local columns = spec.columns(width)
	local header = b.div():row():items_center():gap(10):h(24):px(18):no_shrink()
	header:child(b.div():w(COL.check):no_shrink())
	for _, column in ipairs(columns) do
		local cell = b.div():no_shrink()
		if column.width then
			cell:w(column.width)
		else
			cell:w(0):grow(column.grow or 1):min_w(40)
		end
		header:child(
			cell:child(
				T(string.upper(column.label), "quiet", SIZE.tiny + 0.5, 600):align(column.align or "start"):truncate()
			)
		)
	end
	header:child(b.div():w(COL.verb):no_shrink())
	col:child(header)
	col:child(virtual("list", #rows, SIZE.row, function(index)
		local row = rows[index]
		local id = "row:" .. row.id
		local cursor = S.cursor[section] == row.id
		local verb_id = "verb:" .. row.id
		local over = hovered(id) or hovered(verb_id) or hovered("mark:" .. row.id)
		local el = b.div():press(id):row():items_center():gap(10):h(SIZE.row):px(10):rounded(7):no_shrink()
		if cursor then
			el:bg(alpha("accent", 0.14)):border(1, alpha("accent", 0.55))
		elseif over then
			el:bg(alpha("foreground", 0.055))
		end
		local tick = b.div():press("mark:" .. row.id):w(COL.check):no_shrink()
		local on = S.marks[section] and S.marks[section][row.id]
		if on or over or cursor or S.any_marked then
			tick:child(P.check(on))
		end
		el:child(tick)
		for _, column in ipairs(columns) do
			local cell = b.div():no_shrink():row():items_center()
			if column.width then
				cell:w(column.width)
			else
				cell:w(0):grow(column.grow or 1):min_w(40)
			end
			if column.align == "end" then
				cell:justify_end()
			end
			el:child(cell:child(column.make(row.item)))
		end
		local verb = b.div():w(COL.verb):no_shrink():row():justify_end()
		if (cursor or over) and spec.verb_for(row.item) then
			verb:child(P.button(verb_id, spec.verb_for(row.item), { h = 22, px = 8, size = SIZE.small + 0.5 }))
		end
		return el:child(verb)
	end, { px = 10 }))
	return col
end

local function used_by(names, none)
	if #names == 0 then
		return P.line(none or "unused", "quiet", SIZE.small + 0.5)
	end
	local text = names[1]
	if #names > 1 then
		text = text .. "  +" .. (#names - 1)
	end
	return P.line(text, "foreground", SIZE.small + 0.5)
end

function screens.images(width)
	local images = S.lists.images or {}
	local unused = 0
	for _, image in ipairs(images) do
		if #image.containers == 0 then
			unused += 1
		end
	end
	return plain_screen("images", {
		title = "Images",
		hint = "Filter by name, id, container…",
		subtitle = function()
			return fmt.count(#images, "image") .. " · " .. unused .. " unused"
		end,
		verbs = {
			P.button("act:pull", "Pull…", { key = "u" }),
			P.button("act:clean", "Clean up…", { key = "c" }),
		},
		empty = "There are no images",
		verb_for = function()
			return "Remove…"
		end,
		columns = function(w)
			local list = {
				{
					label = "Image",
					grow = 2,
					make = function(image)
						local first = image.tags[1] or "<none>"
						local el = b.div():row():items_center():gap(8):min_w(0)
						el:child(P.line(first, image.dangling and "dim" or "foreground", SIZE.body, 600))
						if #image.tags > 1 then
							el:child(T("+" .. (#image.tags - 1), "quiet", SIZE.small):no_shrink())
						end
						if image.dangling then
							el:child(P.tag("dangling", "warning"))
						end
						return el
					end,
				},
				{
					label = "Size",
					width = 84,
					align = "end",
					make = function(image)
						return T(fmt.disk(image.size), "foreground", SIZE.small + 0.5)
					end,
				},
				{
					label = "Made",
					width = 74,
					align = "end",
					make = function(image)
						return T(image.created and (ago(image.created) or "–") or "–", "dim", SIZE.small + 0.5)
					end,
				},
				{
					label = "Used by",
					grow = 1.4,
					make = function(image)
						return b.div():pl(8):min_w(0):child(used_by(image.containers))
					end,
				},
			}
			if w >= LIST_MEDIUM then
				table.insert(list, 2, {
					label = "Id",
					width = 100,
					make = function(image)
						return P.line(image.id, "quiet", SIZE.small + 0.5)
					end,
				})
			end
			return list
		end,
	}, width)
end

function screens.volumes(width)
	local volumes = S.lists.volumes or {}
	local unused = 0
	for _, volume in ipairs(volumes) do
		if #volume.containers == 0 then
			unused += 1
		end
	end
	return plain_screen("volumes", {
		title = "Volumes",
		hint = "Filter by name, project…",
		subtitle = function()
			return fmt.count(#volumes, "volume") .. " · " .. unused .. " unused"
		end,
		verbs = { P.button("act:clean", "Clean up…", { key = "c" }) },
		empty = "There are no volumes",
		verb_for = function()
			return "Remove…"
		end,
		columns = function(w)
			local list = {
				{
					label = "Name",
					grow = 2,
					make = function(volume)
						local el = b.div():row():items_center():gap(8):min_w(0)
						el:child(
							P.line(
								volume.anonymous and fmt.cut(volume.name, 14) or volume.name,
								"foreground",
								SIZE.body,
								600
							)
						)
						if volume.anonymous then
							el:child(P.tag("anonymous", "dim"))
						end
						if volume.project then
							el:child(P.tag(volume.project, "info"))
						end
						return el
					end,
				},
				{
					label = "Size",
					width = 84,
					align = "end",
					make = function(volume)
						local size = S.volume_sizes and S.volume_sizes[volume.name]
						return T(
							size and fmt.disk(size) or (S.volume_sizes and "–" or "counting…"),
							size and "foreground" or "quiet",
							SIZE.small + 0.5
						)
					end,
				},
				{
					label = "Used by",
					grow = 1.4,
					make = function(volume)
						return used_by(volume.containers)
					end,
				},
			}
			if w >= LIST_MEDIUM then
				table.insert(list, 2, {
					label = "Driver",
					width = 70,
					make = function(volume)
						return P.line(volume.driver, "dim", SIZE.small + 0.5)
					end,
				})
			end
			return list
		end,
	}, width)
end

function screens.networks(width)
	local networks = S.lists.networks or {}
	return plain_screen("networks", {
		title = "Networks",
		hint = "Filter by name, subnet…",
		subtitle = function()
			return fmt.count(#networks, "network")
		end,
		verbs = { P.button("act:clean", "Clean up…", { key = "c" }) },
		empty = "There are no networks",
		verb_for = function(network)
			return (not network.builtin) and "Remove…" or nil
		end,
		columns = function(w)
			local list = {
				{
					label = "Name",
					grow = 2,
					make = function(network)
						local el = b.div():row():items_center():gap(8):min_w(0)
						el:child(P.line(network.name, "foreground", SIZE.body, 600))
						if network.builtin then
							el:child(P.tag("built in", "dim"))
						end
						if network.internal then
							el:child(P.tag("internal", "warning"))
						end
						if network.project then
							el:child(P.tag(network.project, "info"))
						end
						return el
					end,
				},
				{
					label = "Containers",
					grow = 1.6,
					make = function(network)
						return used_by(network.containers, "none")
					end,
				},
			}
			if w >= LIST_MEDIUM then
				table.insert(list, 2, {
					label = "Subnet",
					width = 150,
					make = function(network)
						return P.line(network.subnets[1] or "–", "dim", SIZE.small + 0.5)
					end,
				})
				table.insert(list, 2, {
					label = "Driver",
					width = 70,
					make = function(network)
						return P.line(network.driver, "dim", SIZE.small + 0.5)
					end,
				})
			end
			return list
		end,
	}, width)
end

-- The layers of an image: what made each, and how much it takes.
function screens.layers(width)
	local image
	for _, one in ipairs(S.lists.images or {}) do
		if one.id == S.layer_open then
			image = one
		end
	end
	local col = b.div():col():grow(1):min_w(0):min_h(0)
	if image == nil then
		return col:child(P.nothing("That image is gone"))
	end
	col:child(
		P.title(
			image_title(image),
			fmt.disk(image.size) .. " · " .. #image.tags .. " " .. (#image.tags == 1 and "tag" or "tags"),
			{
				P.button("layers:update", "Update", { key = "u", disabled = image.dangling }),
				P.button("layers:remove", "Remove…", { danger = true, key = "d" }),
				P.button("layers:back", "Back", { key = "Esc" }),
			}
		)
	)
	local layers = S.layers[image.id]
	if layers == nil or (layers.list == nil and layers.error == nil) then
		return col:child(P.nothing("Reading the layers…"))
	end
	if layers.error then
		return col:child(P.nothing(layers.error))
	end
	local list = layers.list
	col:child(
		b.div()
			:row()
			:gap(14)
			:px(28)
			:h(24)
			:items_center()
			:no_shrink()
			:child(T("SIZE", "quiet", SIZE.tiny + 0.5, 600):w(80):no_shrink())
			:child(T("MADE BY", "quiet", SIZE.tiny + 0.5, 600))
	)
	col:child(virtual("list", #list, SIZE.row, function(index)
		local layer = list[index]
		local command = string.gsub(layer.created_by, "^/bin/sh %-c #%(nop%) *", "")
		command = string.gsub(command, "^/bin/sh %-c ", "RUN ")
		command = string.gsub(command, "%s+", " ")
		return b.div()
			:row()
			:items_center()
			:gap(14)
			:h(SIZE.row)
			:px(18)
			:no_shrink()
			:child(
				b.div():w(80):no_shrink():child(
					T(
						layer.size > 0 and fmt.disk(layer.size) or "–",
						layer.size > 0 and "foreground" or "quiet",
						SIZE.small + 0.5
					):align("end")
				)
			)
			:child(b.div():grow(1):min_w(0):child(P.line(command, "dim", SIZE.small + 0.5)))
	end, { px = 10 }))
	return col
end

return {
	screens = screens,
}
