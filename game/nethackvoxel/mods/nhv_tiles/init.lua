-- NetHack's tiles as items. Entities that use visual = "wielditem" with
-- one of these items render it as an extruded voxel sprite, which is how
-- monsters and floor objects get their 3D look.
--
-- All tiles live in one sprite sheet, textures/nhv_tiles.png (cols x rows
-- tiles, numbered left to right, top to bottom). Edit it freely; tile
-- numbers are listed in tilenames.lua.
local meta = dofile(core.get_modpath("nhv_tiles") .. "/tilenames.lua")

nhv_tiles = {
	count = meta.count,
	names = meta.names,
	cols = meta.cols,
	rows = meta.rows,
}

function nhv_tiles.item(tile)
	if not tile or tile < 0 or tile >= meta.count then
		tile = 0
	end
	return string.format("nhv_tiles:t%04d", tile)
end

-- texture string for one tile, cut from the sheet
function nhv_tiles.texture(tile)
	if not tile or tile < 0 or tile >= meta.count then
		tile = 0
	end
	return string.format("nhv_tiles.png^[sheet:%dx%d:%d,%d", meta.cols, meta.rows,
		tile % meta.cols, math.floor(tile / meta.cols))
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
end
