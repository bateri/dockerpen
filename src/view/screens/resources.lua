-- Images, volumes and networks: the lists of what containers are made of and run on, as tables.

local lib_fmt = require("../lib/fmt")
local lib_kit = require("../lib/kit")
local lib_sizes = require("../lib/sizes")
local lib_virtual = require("../lib/virtual")
local model_containers = require("../model/containers")
local model_rows = require("../model/rows")
local model_state = require("../model/state")
local parts_table = require("../parts/table")
local parts_toolbar = require("../parts/toolbar")
local parts_ui = require("../parts/ui")
local alpha, b = lib_kit.alpha, lib_kit.b
local fmt = lib_fmt.fmt
local LIST_MEDIUM, LIST_WIDE, SIZE = lib_sizes.LIST_MEDIUM, lib_sizes.LIST_WIDE, lib_sizes.SIZE
local virtual = lib_virtual.virtual
local unix_now = model_containers.unix_now
local PANEL, marked, plain_rows, row_tops =
	model_rows.PANEL, model_rows.marked, model_rows.plain_rows, model_rows.row_tops
local S = model_state.S
local P, T, hovered = parts_ui.P, parts_ui.T, parts_ui.hovered

local screens = {}

-- How long ago a time (seconds since 1970) was, in a word of a few letters.
local function age(seconds)
	local at = unix_now()
	if seconds == nil or at == nil then
		return "–"
	end
	return fmt.span(at - seconds)
end

local function total_of(list, key)
	local total = 0
	for _, item in ipairs(list) do
		total += math.max(item[key] or 0, 0)
	end
	return total
end

-- The bar of a list: the field, the segments that narrow it (with how many each shows), and, where
-- something is marked, how many and the verb for them.
local function bar_of(section, width, segments)
	local extra = nil
	local marks = #marked(section)
	if marks > 0 then
		extra = b.div():row():items_center():gap(8):child(
			P.button(
				"act:remove",
				"Remove " .. marks,
				{ variant = "danger-ghost", size = "sm", icon = "trash-2", icon_size = 12 }
			)
		)
	end
	return parts_toolbar.plain(width, segments and {
		prefix = "pf:",
		options = segments,
		current = S.plain_filter[section] or "all",
	}, extra, "Filter " .. section)
end

-- A list as a table: the title, the bar, the head, the rows. `spec`: `title`, `sub`, `verbs`, the
-- `segments`, `tracks(width)` and `columns(width)` for the head, `cells(item, width, context)` for a row,
-- `lead` (the icon of a row) and what to say where there is nothing.
local function table_screen(section, spec, width)
	local rows = plain_rows(section)
	local col = b.div():col():grow(1):min_w(0):min_h(0)
	col:child(P.title(spec.title, spec.sub(), spec.verbs))
	col:child(bar_of(section, width, spec.segments and spec.segments()))
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
		return col:child(P.nothing("Looking…", nil, nil, width))
	end
	if #rows == 0 then
		if S.query ~= "" or (S.plain_filter[section] or "all") ~= "all" then
			return col:child(P.nothing("Nothing matches", "Try another filter.", "search-x", width))
		end
		return col:child(P.nothing(spec.empty, spec.empty_hint, spec.lead, width))
	end
	local tracks = spec.tracks(width)
	col:child(parts_table.head(tracks, spec.columns(width), section == "images" and S.image_sort or nil))
	local context = spec.context and spec.context() or nil
	col:child(virtual("list", #rows, SIZE.row, function(index)
		local row = rows[index]
		local id = "row:" .. row.id
		local cursor = S.cursor[section] == row.id
		local on = S.marks[section] and S.marks[section][row.id]
		local el = parts_table.row(tracks, id, cursor, hovered(id), on)
		el:child(parts_table.lead(row.id, on, nil, spec.lead_of and spec.lead_of(row.item) or spec.lead))
		for _, cell in ipairs(spec.cells(row.item, width, context)) do
			el:child(cell)
		end
		if spec.panel and spec.open(row.item) then
			return b.div():col():no_shrink():child(el):child(spec.panel(row.item, width))
		end
		return el
	end, { px = 8, pt = 6, tops = spec.panel and row_tops(section) or nil }))
	return col
end

-- The panel under an image that is open: its tags, the containers made from it, its layers and what
-- made each. (Its height is `model/rows.lua`'s `image_panel_height`: the same rows, the same sizes.)
local function layers_panel(image, width)
	local slot = S.layers[image.id]
	local body =
		b.div():col():gap(PANEL.gap):p(PANEL.pad):rounded(10):bg("raised1"):ml(34):mr(6):mt(PANEL.top):mb(PANEL.bottom)
	if #image.tags > 0 then
		local tags = b.div():row():items_center():gap(6):h(PANEL.tags):clip()
		for _, tag in ipairs(image.tags) do
			tags:child(P.tag(tag))
		end
		body:child(tags)
	end
	if #image.containers > 0 then
		local used = b.div():row():items_center():gap(6):h(PANEL.used):clip()
		used:child(T("used by", "quiet", SIZE.small + 1))
		for _, name in ipairs(image.containers) do
			local id = "img:open:" .. name
			used:child(
				b.div()
					:row()
					:items_center()
					:h(22)
					:px(8)
					:rounded(11)
					:press(id)
					:bg(hovered(id) and "raised3" or "raised2")
					:child(T(name, hovered(id) and "foreground" or "dim", SIZE.small))
			)
		end
		body:child(used)
	end
	if slot == nil or (slot.list == nil and slot.error == nil) then
		body:child(b.div():h(PANEL.loading):rounded(6):bg(alpha("foreground", 0.05)))
	elseif slot.error then
		body:child(T(slot.error, "error", SIZE.small + 0.5):truncate())
	elseif #slot.list == 0 then
		body:child(T("no layers", "quiet", SIZE.small + 0.5))
	else
		local largest = 1
		for _, layer in ipairs(slot.list) do
			largest = math.max(largest, layer.size or 0)
		end
		local list = b.div():col():gap(PANEL.layer_gap)
		for _, layer in ipairs(slot.list) do
			local command = string.gsub(layer.created_by or "", "^/bin/sh %-c #%(nop%) *", "")
			command = string.gsub(command, "^/bin/sh %-c ", "RUN ")
			command = string.gsub(command, "%s+", " ")
			if command == "" then
				command = layer.comment ~= "" and layer.comment or string.sub(layer.id or "", 1, 12)
			end
			local size = layer.size or 0
			list:child(
				b.div()
					:row()
					:items_center()
					:gap(10)
					:h(PANEL.layer)
					:clip()
					:child(
						b.div():w(70):no_shrink():child(
							T(
								size > 0 and fmt.bytes(size) or "0",
								size > 0 and "foreground" or "quiet",
								SIZE.small + 0.5
							):align("end")
						)
					)
					:child(b.div():w(60):no_shrink():child(P.meter(size / largest, size > 0 and "accent" or "quiet")))
					:child(b.div():grow(1):min_w(0):child(P.line(command, "dim", SIZE.small + 0.5)))
			)
		end
		body:child(list)
	end
	return body
end

function screens.images(width)
	local images = S.lists.images or {}
	local used, unused, dangling = 0, 0, 0
	for _, image in ipairs(images) do
		if #image.containers > 0 then
			used += 1
		else
			unused += 1
		end
		if image.dangling then
			dangling += 1
		end
	end
	return table_screen("images", {
		title = "Images",
		sub = function()
			return S.lists.images and (fmt.count(#images, "image") .. " · " .. fmt.bytes(total_of(images, "size")))
				or "reading…"
		end,
		verbs = {
			parts_toolbar.verb("act:pull", "Pull", "download", width),
			parts_toolbar.verb("act:clean", "Clean up", "sparkles", width),
		},
		segments = function()
			return {
				{ id = "all", label = "All", count = #images },
				{ id = "used", label = "In use", count = used },
				{ id = "unused", label = "Unused", count = unused },
				{ id = "dangling", label = "Dangling", count = dangling },
			}
		end,
		lead = "layers",
		lead_of = function(image)
			return S.layer_open == image.id and "chevron-down" or "chevron-right"
		end,
		open = function(image)
			return S.layer_open == image.id
		end,
		panel = layers_panel,
		empty = "No images",
		empty_hint = "Pull one to start: press p.",
		tracks = function(w)
			if w >= LIST_WIDE then
				return { 26, b.range(140, 1), 110, 160, 56, b.range(120, 0.7) }
			elseif w >= LIST_MEDIUM then
				return { 26, b.range(140, 1), 160, 56, b.range(110, 0.6) }
			end
			return { 26, b.range(120, 1), 150, 56 }
		end,
		columns = function(w)
			local list = { { label = "Name", sort = "name" } }
			if w >= LIST_WIDE then
				list[#list + 1] = { label = "Id" }
			end
			list[#list + 1] = { label = "Size", sort = "size" }
			list[#list + 1] = { label = "Age", sort = "created" }
			if w >= LIST_MEDIUM then
				list[#list + 1] = { label = "Used by" }
			end
			return list
		end,
		context = function()
			local largest = 1
			for _, image in ipairs(images) do
				largest = math.max(largest, image.size or 0)
			end
			return largest
		end,
		cells = function(image, w, largest)
			local name = b.div():row():items_center():gap(8):min_w(0)
			name:child(
				P.line(
					image.tags[1] and fmt.image_name(image.tags[1]) or ("<none> " .. string.sub(image.id, 1, 12)),
					image.dangling and "quiet" or "foreground",
					SIZE.small + 1,
					600
				)
			)
			if #image.tags > 1 then
				name:child(P.tag("+" .. (#image.tags - 1)))
			end
			if image.dangling then
				name:child(P.tag("dangling", "warning"))
			end
			local cells = { name }
			if w >= LIST_WIDE then
				cells[#cells + 1] = P.line(string.sub(image.id, 1, 12), "quiet", SIZE.small + 1)
			end
			cells[#cells + 1] = parts_table.size_cell(
				fmt.bytes(image.size),
				(image.size or 0) / largest,
				#image.containers == 0 and "quiet" or "accent"
			)
			cells[#cells + 1] = P.line(age(image.created), "dim", SIZE.small + 1)
			if w >= LIST_MEDIUM then
				cells[#cells + 1] = parts_table.used_by(image.containers)
			end
			return cells
		end,
	}, width)
end

function screens.volumes(width)
	local volumes = S.lists.volumes or {}
	local used, unused, anonymous = 0, 0, 0
	for _, volume in ipairs(volumes) do
		if #volume.containers > 0 then
			used += 1
		else
			unused += 1
		end
		if volume.anonymous then
			anonymous += 1
		end
	end
	local sizes = S.volume_sizes
	return table_screen("volumes", {
		title = "Volumes",
		sub = function()
			if S.lists.volumes == nil then
				return "reading…"
			end
			local text = fmt.count(#volumes, "volume")
			if sizes then
				local total = 0
				for _, size in pairs(sizes) do
					total += math.max(size, 0)
				end
				text = text .. " · " .. fmt.bytes(total)
			end
			return text
		end,
		verbs = { parts_toolbar.verb("act:clean", "Clean up", "sparkles", width) },
		segments = function()
			return {
				{ id = "all", label = "All", count = #volumes },
				{ id = "used", label = "In use", count = used },
				{ id = "unused", label = "Unused", count = unused },
				{ id = "anonymous", label = "Anonymous", count = anonymous },
			}
		end,
		lead = "hard-drive",
		empty = "No volumes",
		tracks = function(w)
			if w >= LIST_MEDIUM then
				return { 26, b.range(140, 1), 170, b.range(110, 0.7), 72 }
			end
			return { 26, b.range(120, 1), 150 }
		end,
		columns = function(w)
			local list = { { label = "Name" }, { label = "Size" } }
			if w >= LIST_MEDIUM then
				list[#list + 1] = { label = "Used by" }
				list[#list + 1] = { label = "Driver" }
			end
			return list
		end,
		context = function()
			local largest = 1
			for _, size in pairs(sizes or {}) do
				largest = math.max(largest, size)
			end
			return largest
		end,
		cells = function(volume, w, largest)
			local name = b.div():row():items_center():gap(8):min_w(0)
			name:child(
				P.line(
					volume.anonymous and string.sub(volume.name, 1, 12) or volume.name,
					"foreground",
					SIZE.small + 1,
					600
				)
			)
			if volume.anonymous then
				name:child(P.tag("anonymous"))
			end
			if volume.project then
				name:child(P.tag(volume.project))
			end
			local size = sizes and sizes[volume.name]
			local cells = { name }
			if size and size >= 0 then
				cells[#cells + 1] = parts_table.size_cell(
					fmt.bytes(size),
					size / largest,
					#volume.containers == 0 and "quiet" or "accent"
				)
			else
				cells[#cells + 1] = T(sizes and "–" or "counting…", "quiet", SIZE.small + 1)
			end
			if w >= LIST_MEDIUM then
				cells[#cells + 1] = #volume.containers > 0
						and P.line(table.concat(volume.containers, ", "), "dim", SIZE.small + 1)
					or T("unused", "quiet", SIZE.small + 1)
				cells[#cells + 1] = P.line(volume.driver or "", "quiet", SIZE.small + 1)
			end
			return cells
		end,
	}, width)
end

function screens.networks(width)
	local networks = S.lists.networks or {}
	return table_screen("networks", {
		title = "Networks",
		sub = function()
			return S.lists.networks and fmt.count(#networks, "network") or "reading…"
		end,
		verbs = { parts_toolbar.verb("act:clean", "Clean up", "sparkles", width) },
		lead = "network",
		empty = "Nothing matches",
		tracks = function(w)
			if w >= LIST_WIDE then
				return { 26, b.range(140, 1), 84, 150, b.range(140, 1) }
			elseif w >= LIST_MEDIUM then
				return { 26, b.range(140, 1), 84, 150 }
			end
			return { 26, b.range(120, 1) }
		end,
		columns = function(w)
			local list = { { label = "Name" } }
			if w >= LIST_MEDIUM then
				list[#list + 1] = { label = "Driver" }
				list[#list + 1] = { label = "Subnet" }
			end
			if w >= LIST_WIDE then
				list[#list + 1] = { label = "Running containers" }
			end
			return list
		end,
		cells = function(network, w)
			local name = b.div():row():items_center():gap(8):min_w(0)
			name:child(P.line(network.name, "foreground", SIZE.small + 1, 600))
			if network.builtin then
				name:child(P.tag("built-in"))
			end
			if network.internal then
				name:child(P.tag("internal", "warning"))
			end
			if network.project then
				name:child(P.tag(network.project))
			end
			local cells = { name }
			if w >= LIST_MEDIUM then
				cells[#cells + 1] = P.line(network.driver or "", "dim", SIZE.small + 1)
				cells[#cells + 1] =
					P.line(#network.subnets > 0 and table.concat(network.subnets, ", ") or "–", "dim", SIZE.small + 1)
			end
			if w >= LIST_WIDE then
				cells[#cells + 1] = parts_table.used_by(network.containers, "none")
			end
			return cells
		end,
	}, width)
end

return {
	screens = screens,
}
