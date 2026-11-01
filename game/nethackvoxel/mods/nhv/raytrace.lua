-- Raytraced light (Graphics: Raytraced light - the setting nhv_raytrace;
-- the VoxHack engine's nhv_raytrace.h). The engine traces the light
-- through the level's blocks, ray by ray: a lit room lit through and
-- through, its light going out of it only in straight lines - shafts out
-- of its doorways with straight edges, fading as they go - and lamps and
-- the light you carry casting hard shadows. Here: the engine told which
-- squares are lit rooms, and to look at the level's blocks again whenever
-- squares are built (terrain.lua; which then leaves out the rooms' light
-- blocks, and the lamps' - told to the engine instead).

local U = nhv.util

local raytrace = {}
nhv.raytrace = raytrace

function raytrace.on()
	return core.nhv_rt_scan ~= nil and core.settings:get_bool("nhv_raytrace", false)
end

-- the engine wants the level's blocks: raytraced, or square light (the
-- blocks' own light, block by block)
function raytrace.wanted()
	return nhv.terrain.raytrace or (core.nhv_rt_scan ~= nil
		and (core.settings:get("nhv_square_light") or "off") ~= "off")
end

-- (the engine's box of blocks: x 0..255, z 0..63)
local GX, GZ = 256, 64

local due = nil -- (us) when to tell the engine
function raytrace.dirty()
	due = due or core.get_us_time() + 100000
end

local function scan()
	local terrain = nhv.terrain
	local cols = {}
	for i = 1, GX * GZ do
		cols[i] = "0"
	end
	-- (a lit room's floor, not its doorways: its light goes out through them)
	for ty = 0, U.ROWNO - 1 do
		for tx = 1, U.COLNO - 1 do
			local sq = terrain.built[U.idx(tx, ty)]
			if sq and sq.lit and terrain.open_typ(sq.typ) and sq.typ ~= U.TYP.DOOR then
				local ox, oz = U.tile_origin(tx, ty)
				for z = oz, oz + U.TILE - 1 do
					for x = ox, ox + U.TILE - 1 do
						if x >= 0 and x < GX and z >= 0 and z < GZ then
							cols[z * GX + x + 1] = "1"
						end
					end
				end
			end
		end
	end
	raytrace.portals = core.nhv_rt_scan(table.concat(cols), U.FLOOR_Y)
end

core.register_globalstep(function()
	if not due or core.get_us_time() < due then
		return
	end
	due = nil
	if raytrace.wanted() then
		scan()
	end
end)

-- the setting changed (graphics.lua): the level built again with it - the
-- rooms' light blocks, the lamps' - and the engine told
function raytrace.changed()
	local map = nhv.nh.snap and nhv.nh.snap.map
	if map then
		nhv.terrain.update(map)
		nhv.terrain.update_lights()
	end
end

return raytrace
