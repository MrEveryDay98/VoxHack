-- One craftitem per NetHack tile. Entities that use visual = "wielditem"
-- with one of these items render it as an extruded voxel sprite, which is
-- how monsters and floor objects get their 3D look.
local meta = dofile(core.get_modpath("nhv_tiles") .. "/tilenames.lua")

nhv_tiles = {
	count = meta.count,
	names = meta.names,
}

function nhv_tiles.item(tile)
	if not tile or tile < 0 or tile >= meta.count then
		tile = 0
	end
	return string.format("nhv_tiles:t%04d", tile)
end

function nhv_tiles.texture(tile)
	if not tile or tile < 0 or tile >= meta.count then
		tile = 0
	end
	return string.format("nhv_tile_%04d.png", tile)
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
