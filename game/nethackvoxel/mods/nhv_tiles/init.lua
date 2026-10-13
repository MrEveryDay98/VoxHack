-- NetHack's tiles as items. Entities that use visual = "wielditem" with
-- one of these items render it as an extruded voxel sprite, which is how
-- monsters and floor objects get their 3D look.
--
-- Sprites live in one sheet, textures/nhv_tiles.png (cols x rows sprites,
-- numbered left to right, top to bottom from 0). Edit it freely.
-- tilenames.lua maps NetHack's tile numbers onto sheet positions: a
-- monster's male and female tiles share a sprite unless they differ, and
-- statues reuse the monster's sprite with a stone colour filter.
local meta = dofile(core.get_modpath("nhv_tiles") .. "/tilenames.lua")

nhv_tiles = {
	count = meta.count,
	names = meta.names,
	cols = meta.cols,
	rows = meta.rows,
}

-- the colour filter that turns a sprite into a statue
nhv_tiles.STONE = "^[hsl:0:-100:-10"

function nhv_tiles.item(tile)
	if not tile or tile < 0 or tile >= meta.count then
		tile = 0
	end
	return string.format("nhv_tiles:t%04d", tile)
end

-- NetHack's name for a tile ("main walls horizontal", "newt", ...)
function nhv_tiles.name(tile)
	return meta.names[tile]
end

-- sheet position of a NetHack tile
function nhv_tiles.sheet_index(tile)
	if not tile or tile < 0 or tile >= meta.count then
		tile = 0
	end
	return meta.sheet[tile] or 0
end

-- texture string for a NetHack tile
function nhv_tiles.texture(tile)
	local s = nhv_tiles.sheet_index(tile)
	local tex = string.format("nhv_tiles.png^[sheet:%dx%d:%d,%d", meta.cols, meta.rows,
		s % meta.cols, math.floor(s / meta.cols))
	if meta.statue[tile] then
		tex = tex .. nhv_tiles.STONE
	end
	return tex
end

-- combat flashes for monster sprites: a faint white one when attacking,
-- red when hurt (entities swap to these items for a moment)
nhv_tiles.FLASH = {
	w = "^[colorize:#ffffff:70",
	r = "^[colorize:#ff2020:150",
}

-- Entity properties that draw a tile `height` nodes tall, either as an
-- extruded voxel model (default) or, with the setting nhv_flat_sprites,
-- as a flat sprite. kind: nil, or a FLASH key ("w"/"r") for a combat flash.
function nhv_tiles.flat()
	return core.settings:get_bool("nhv_flat_sprites", false)
end

function nhv_tiles.look(tile, height, kind)
	if nhv_tiles.flat() then
		local tex = nhv_tiles.texture(tile) .. (kind and nhv_tiles.FLASH[kind] or "")
		return {
			visual = "upright_sprite",
			textures = {tex, tex .. "^[transformFX"},
			visual_size = {x = height, y = height, z = height},
		}
	end
	local s = height / 2
	return {
		visual = "wielditem",
		wield_item = kind and nhv_tiles.flash_item(tile, kind) or nhv_tiles.item(tile),
		visual_size = {x = s, y = s, z = s},
	}
end

-- visual_size for a tile `height` nodes tall, squashed/stretched by w
function nhv_tiles.size(height, w)
	local s = nhv_tiles.flat() and height or height / 2
	w = w or 1
	return {x = s * w, y = s / w, z = s}
end

function nhv_tiles.flash_item(tile, kind)
	if not tile or tile < 0 or tile >= meta.monsters or not nhv_tiles.FLASH[kind] then
		return nhv_tiles.item(tile)
	end
	return string.format("nhv_tiles:t%04d_%s", tile, kind)
end

for i = 0, meta.count - 1 do
	local tex = nhv_tiles.texture(i)
	core.register_craftitem(nhv_tiles.item(i), {
		description = meta.names[i] or ("tile " .. i),
		inventory_image = tex,
		wield_image = tex,
		stack_max = 65535,
		groups = {not_in_creative_inventory = 1},
	})
	if i < meta.monsters then
		for kind, mod in pairs(nhv_tiles.FLASH) do
			core.register_craftitem(nhv_tiles.flash_item(i, kind), {
				description = meta.names[i] or ("tile " .. i),
				inventory_image = tex .. mod,
				groups = {not_in_creative_inventory = 1},
			})
		end
	end
end
