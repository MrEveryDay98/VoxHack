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

-- texture string for a sheet position (the block editor picks these)
function nhv_tiles.sheet_texture(s)
	return string.format("nhv_tiles.png^[sheet:%dx%d:%d,%d", meta.cols, meta.rows,
		s % meta.cols, math.floor(s / meta.cols))
end

-- The sprites' own sheet: nhv_tiles.png, or with the setting
-- nhv_sprite_shadows off (Options > Drawn shadows), nhv_tiles_noshadow.png -
-- the same without the shadows drawn on the monsters and objects
-- (tools/make_noshadow_tiles.py makes it; the game's shadows are real:
-- nhv/shadows.lua). Read when the game starts.
nhv_tiles.SPRITES = core.settings:get_bool("nhv_sprite_shadows", true) and "nhv_tiles.png"
	or "nhv_tiles_noshadow.png"

-- texture string for a NetHack tile
function nhv_tiles.texture(tile)
	local s = nhv_tiles.sheet_index(tile)
	local tex = string.format("%s^[sheet:%dx%d:%d,%d", nhv_tiles.SPRITES, meta.cols, meta.rows,
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

-- Something invisible that you see anyway (See_invisible): Doom's
-- spectre fuzz - the monster faint and see-through, with fine specks of it
-- (darker, and in its own colours) crawling over it: FUZZ_FRAMES noise
-- masks (nhv_fuzz_<n>.png, FUZZ_RES square, finer than the sprite, which
-- is scaled up to match), swapped FUZZ_RATE times a second by whoever
-- draws it (mobs.lua, avatar.lua)
nhv_tiles.FUZZ_FRAMES = 8
nhv_tiles.FUZZ_RATE = 14
nhv_tiles.FUZZ_RES = 64
nhv_tiles.FUZZ_ALPHA = 120 -- (all of it see-through: 255 = only the gaps are)

function nhv_tiles.fuzz_textures(tile, frame)
	local n, r = nhv_tiles.FUZZ_FRAMES, nhv_tiles.FUZZ_RES
	local base = ("%s^[resize:%dx%d"):format(nhv_tiles.texture(tile), r, r)
	-- (faint, then darker specks, then specks in full colour)
	local tex = "((" .. base .. "^[opacity:70)"
		.. ("^(%s^[mask:nhv_fuzz_%d.png^[multiply:#505050^[opacity:200)"):format(base, frame % n)
		.. ("^(%s^[mask:nhv_fuzz_%d.png^[opacity:150)"):format(base, (frame + 3) % n)
		.. ")^[opacity:" .. nhv_tiles.FUZZ_ALPHA
	return {tex, tex .. "^[transformFX"}
end

-- the fuzz frame for now (everything fuzzy crawls in step)
function nhv_tiles.fuzz_frame()
	return math.floor(core.get_us_time() / 1e6 * nhv_tiles.FUZZ_RATE) % nhv_tiles.FUZZ_FRAMES
end

function nhv_tiles.fuzz_look(tile, height)
	return {
		visual = "upright_sprite", textures = nhv_tiles.fuzz_textures(tile, nhv_tiles.fuzz_frame()),
		visual_size = {x = height, y = height, z = height}, use_texture_alpha = true,
	}
end

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

-- a fist (a Monk's left hand fighting bare-handed; either hand in gloves;
-- the bare right hand is the hand item's picture, actions.lua). Its picture
-- is set per use (nhv_tiles.fist): mirrored for the left, the gloves' colour.
core.register_craftitem(":nhv:fist", {
	description = "Fist", inventory_image = "nhv_weapon_Fist.png",
	wield_image = "nhv_weapon_Fist.png", groups = {not_in_creative_inventory = 1},
})

-- the gloves' colours (tools/make_glove_colors.py): NetHack tile -> colour
local GLOVES = dofile(core.get_modpath("nhv_tiles") .. "/glove_colors.lua")
function nhv_tiles.glove_color(tile)
	return GLOVES[tile]
end

-- a fist's picture: the left hand's mirrored; in gloves, their colour over
-- the hand (where textures/nhv_glove_mask.png is white: to the wrist), the
-- fist's shading kept (grey, then tinted), the arm bare
function nhv_tiles.fist(left, color)
	local tex = "nhv_weapon_Fist.png"
	if color then
		tex = tex .. "^(nhv_weapon_Fist.png^[hsl:0:-100:15^[multiply:" .. color
			.. "^[mask:nhv_glove_mask.png)"
	end
	return left and (tex .. "^[transformFX") or tex
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
