-- VoxHack main mod.
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

-- A world with a file named "nhv_intro" in it is the intro editor: the
-- opening's forest (tools/make_intro_world.py).
do
	local f = io.open(core.get_worldpath() .. DIR_DELIM .. "nhv_intro", "r")
	nhv.INTRO_EDITOR = f ~= nil
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
-- A world with a file named "nhv_atlas" (holding a seed) is the level
-- atlas: every level of a game with that seed, built side by side.
do
	local f = io.open(core.get_worldpath() .. DIR_DELIM .. "nhv_atlas", "r")
	nhv.ATLAS = f and (f:read("*l") or "") or nil
	if f then
		f:close()
	end
end
if nhv.ATLAS and not nhv.EDITOR then
	dofile(path .. "nh.lua")
	dofile(path .. "scale.lua")
	dofile(path .. "terrain.lua")
	dofile(path .. "areas.lua")
	dofile(path .. "doors.lua")
	dofile(path .. "atlas.lua")
	return
end
if nhv.INTRO_EDITOR then
	dofile(path .. "signart.lua")
	dofile(path .. "intro_blocks.lua")
	dofile(path .. "sky.lua")
	dofile(path .. "intro_play.lua")
	dofile(path .. "intro_editor.lua")
	return
end
if nhv.EDITOR then
	dofile(path .. "nh.lua") -- glyph helpers only; no game is started
	dofile(path .. "terrain.lua")
	dofile(path .. "areas.lua")
	dofile(path .. "doors.lua")
	dofile(path .. "scale.lua")
	dofile(path .. "editor.lua")
	dofile(path .. "editor_tools.lua")
	dofile(path .. "editor_draw.lua")
	dofile(path .. "monsteredit.lua")
	return
end
dofile(path .. "nh.lua")
dofile(path .. "scale.lua")
dofile(path .. "terrain.lua")
dofile(path .. "ascii.lua")
dofile(path .. "areas.lua")
dofile(path .. "sea.lua")
dofile(path .. "bubbles.lua")
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
		nhv.terrain.build_all(snap.map, snap.hero)
	else
		nhv.terrain.update(snap.map)
	end
	nhv.terrain.update_lights() -- (lamps, candles, glowing monsters)
	nhv.sim.sync()
	nhv.mobs.update(snap, changed)
end)

dofile(path .. "clock.lua")
dofile(path .. "player.lua")
dofile(path .. "wizard.lua")
dofile(path .. "hud.lua")
dofile(path .. "ui.lua")
dofile(path .. "graphics.lua")
dofile(path .. "guide.lua")
dofile(path .. "help.lua")
dofile(path .. "commands.lua")
dofile(path .. "nhopts.lua")
dofile(path .. "title.lua")
dofile(path .. "hotbar.lua")
dofile(path .. "containers.lua")
dofile(path .. "actions.lua")
dofile(path .. "cmdtable.lua")
dofile(path .. "jump.lua")
dofile(path .. "spells.lua")
dofile(path .. "wheel.lua")
dofile(path .. "missiles.lua")
dofile(path .. "lightning.lua")
dofile(path .. "rays.lua")
dofile(path .. "effects.lua")
dofile(path .. "msgfx.lua")
dofile(path .. "holds.lua")
dofile(path .. "signart.lua")
dofile(path .. "signs.lua")
-- (internet access - for the NetHackWiki viewer - is only granted to a
-- request made right here, in the mod's own init.lua)
nhv.http = core.request_http_api and core.request_http_api()
dofile(path .. "wiki.lua")
dofile(path .. "update.lua")
dofile(path .. "avatar.lua")
dofile(path .. "shadows.lua")
dofile(path .. "sky.lua")
dofile(path .. "showroom.lua")
dofile(path .. "intro.lua")
dofile(path .. "intro_blocks.lua")
dofile(path .. "intro_play.lua")
dofile(path .. "sound.lua")
dofile(path .. "achievements.lua")
dofile(path .. "cutscene.lua")
dofile(path .. "death.lua")
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
	-- (the title's backdrop gone - its sky, its held view, the HUD it
	-- hides - however the game was started; a new character's intro
	-- keeps it till it's told: intro.lua)
	if not nhv.intro.active then
		nhv.showroom.hide(player)
	end
	nhv.title.open = false
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
	nhv.hud.fade(1, 0) -- (black until the opening, or the title, fades in)
	-- the title screen: continue, new character, options, quit
	local function title(p)
		-- (the title's backdrop: no hand, weapon or HUD showing before the
		-- title screen comes)
		nhv.showroom.title(p)
		core.after(0.5, function()
			if p:is_player() then
				nhv.title.show(p, true)
			end
		end)
	end
	-- the opening first, if there's one (intro_play.lua)
	if nhv.intro_play.ready() then
		player:hud_set_flags({wielditem = false, crosshair = false, nhv_camera_lock = true})
		nhv.intro_play.start_game(player, title)
	else
		title(player)
	end
end)

