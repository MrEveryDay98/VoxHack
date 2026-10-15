-- NetHack Voxel main mod.
nhv = {}

local path = core.get_modpath("nhv") .. DIR_DELIM

-- A world with a file named "nhv_editor" in it is the prefab editor.
do
	local f = io.open(core.get_worldpath() .. DIR_DELIM .. "nhv_editor", "r")
	nhv.EDITOR = f ~= nil
	if f then
		f:close()
	end
end

dofile(path .. "util.lua")
dofile(path .. "theme.lua")
dofile(path .. "blocks.lua")
dofile(path .. "props.lua")
dofile(path .. "custom_blocks.lua")
dofile(path .. "prefabs.lua")
if nhv.EDITOR then
	dofile(path .. "nh.lua") -- glyph helpers only; no game is started
	dofile(path .. "terrain.lua")
	dofile(path .. "doors.lua")
	dofile(path .. "scale.lua")
	dofile(path .. "editor.lua")
	dofile(path .. "monsteredit.lua")
	return
end
dofile(path .. "nh.lua")
dofile(path .. "scale.lua")
dofile(path .. "terrain.lua")
dofile(path .. "doors.lua")
dofile(path .. "path.lua")
dofile(path .. "sim.lua")
dofile(path .. "mobs.lua")

local U = nhv.util
local nh = nhv.nh

-- World sync: rebuild terrain and entities from each snapshot.
-- (Registered before the player module so the world is up to date when
-- the player is repositioned.)
local world = {ledger = nil}
nhv.world = world
nh.on_snapshot(function(snap)
	if not snap then
		return
	end
	local changed = world.ledger ~= snap.hero.ledger
	world.ledger = snap.hero.ledger
	if changed then
		nhv.sim.clear()
		if nhv.missiles then
			nhv.missiles.clear()
			core.nh_clear_missiles()
			nhv.rays.clear()
			nhv.containers.clear()
			core.nh_clear_rays()
		end
		nhv.terrain.build_all(snap.map)
	else
		nhv.terrain.update(snap.map)
	end
	nhv.sim.sync()
	nhv.mobs.update(snap, changed)
end)

dofile(path .. "clock.lua")
dofile(path .. "player.lua")
dofile(path .. "hud.lua")
dofile(path .. "ui.lua")
dofile(path .. "graphics.lua")
dofile(path .. "nhopts.lua")
dofile(path .. "title.lua")
dofile(path .. "hotbar.lua")
dofile(path .. "containers.lua")
dofile(path .. "actions.lua")
dofile(path .. "spells.lua")
dofile(path .. "wheel.lua")
dofile(path .. "missiles.lua")
dofile(path .. "rays.lua")
dofile(path .. "effects.lua")
dofile(path .. "sound.lua")
dofile(path .. "loop.lua")

-- The whole dungeon level fits in a small box; make sure it exists
-- before NetHack starts drawing into it.
local AREA_MIN = vector.new(-16, U.FLOOR_Y - 16, -16)
local AREA_MAX = vector.new(U.COLNO * U.TILE + 16, U.CEIL_Y + 16, U.ROWNO * U.TILE + 16)

local area_ready = false
local function with_area(cb)
	if area_ready then
		cb()
		return
	end
	core.emerge_area(AREA_MIN, AREA_MAX, function(_, _, remaining)
		if remaining == 0 then
			area_ready = true
			cb()
		end
	end)
end

-- start (or continue) NetHack as character `name` (default: the usual)
function nhv.new_game(player, name)
	world.ledger = nil
	nhv.player.ledger = nil
	nhv.player.hero = nil
	nhv.mobs.clear()
	nhv.sim.clear()
	with_area(function()
		local ok, err = nh.start(name or nhv.nhopts.character_name(player:get_player_name()))
		if not ok then
			core.chat_send_all("Could not start NetHack: " .. tostring(err))
		end
	end)
end

core.register_on_joinplayer(function(player)
	-- park the player somewhere safe until the level is built
	player:set_pos(vector.new(U.TILE * 40, U.CEIL_Y + 300, U.TILE * 10))
	nhv.player.freeze(true)
	-- the title screen: continue, new character, options, quit
	core.after(0.5, function()
		if player:is_player() then
			nhv.title.show(player)
		end
	end)
end)

