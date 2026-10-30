-- Getting an artifact: a moment of glory.
--
-- The first time each game an artifact comes into your hands (NetHack says
-- "artifact_get <o_id> <ART_* number>": nhv_artifact_obtained), once no menu
-- or question is on screen: time stands still, a beam of light comes down
-- on you, the camera goes out behind you and slowly circles round, and you
-- hold the artifact up over your head, for DURATION seconds. Its name
-- shows at the top, the edges of the screen darken, and the hook
-- "artifact_obtained" plays.
--
-- Nothing you press meanwhile does anything, nor is it kept for after
-- (nh.act, actions, the wheel, the hotbar keys and walking all wait on
-- cutscene.active). The artifacts already celebrated are kept in the
-- world's storage, by game, so a save and reload doesn't play them again.

local U = nhv.util
local nh = nhv.nh

local cutscene = {active = false}
nhv.cutscene = cutscene

local DURATION = 5          -- seconds
local PAN = math.rad(150)   -- how far the camera goes round you
local PITCH = 0.12          -- looking a little down (radians)
local ITEM_SIZE = 0.38

local storage = core.get_mod_storage()
local KEY = "artifacts_celebrated"

-- {game = id, got = {["<n>"] = true}}, for the game being played
local function celebrated()
	local gid = core.nh_game_id and tostring(core.nh_game_id()) or ""
	local d = core.parse_json(storage:get_string(KEY) ~= "" and storage:get_string(KEY) or "{}") or {}
	if d.game ~= gid or type(d.got) ~= "table" then
		d = {game = gid, got = {}}
	end
	return d
end

local pending = {} -- {o_id=, n=}, waiting for the screen to be clear
local scene = nil   -- the one playing

core.register_entity("nhv:glory_beam", {
	initial_properties = {
		-- (a round cone from the floor to the ceiling, brightest at the top:
		-- tools/make_glory_beam.py)
		visual = "mesh", mesh = "nhv_glory_beam.obj", visual_size = {x = 1, y = 1, z = 1},
		textures = {"nhv_glory_beam.png"},
		use_texture_alpha = true, backface_culling = false, glow = 14, shaded = false,
		physical = false, pointable = false, static_save = false, collisionbox = {0, 0, 0, 0, 0, 0},
	},
	on_step = function(self)
		if not ((scene and scene.beam == self.object) or (cutscene.beam_kept(self.object))) then
			self.object:remove()
		end
	end,
})

core.register_entity("nhv:glory_item", {
	initial_properties = {
		visual = "wielditem", wield_item = nhv_tiles.item(0),
		visual_size = {x = ITEM_SIZE, y = ITEM_SIZE, z = ITEM_SIZE}, glow = 14,
		physical = false, pointable = false, static_save = false, collisionbox = {0, 0, 0, 0, 0, 0},
	},
	on_step = function(self)
		if not (scene and scene.item == self.object) then
			self.object:remove()
		end
	end,
})

local function smooth(t)
	t = math.max(0, math.min(1, t))
	return t * t * (3 - 2 * t)
end

local function artifact_tile(o_id)
	for _, o in ipairs((nh.snap and nh.snap.inventory) or {}) do
		if o.id == o_id then
			return o.tile
		end
	end
end

local function start(player, p)
	local arts = nhv.achievements and nhv.achievements.ARTIFACTS or {}
	local name = arts[p.n] and arts[p.n][2] or "an artifact"
	local tile = artifact_tile(p.o_id)
	cutscene.active = true
	nhv.actions.drop_waiting()
	nhv.clock.search_held = false
	nhv.player.refresh_speed()
	core.close_formspec(player:get_player_name(), "")
	local pos = player:get_pos()
	scene = {t = 0, yaw = player:get_look_horizontal(), pitch = player:get_look_vertical(),
		pos = pos, hud = {}}
	player:set_velocity(vector.zero())
	player:set_camera({mode = "third"})
	-- the beam, standing on your feet
	scene.beam = core.add_entity(pos, "nhv:glory_beam")
	-- the artifact, held up over your head (turned to face the camera, as
	-- your sprite is: avatar.lua)
	local me = nhv.avatar.self()
	scene.head = (me and me.h or 1.6) + 0.05
	if tile then
		scene.item = core.add_entity(pos, "nhv:glory_item")
		if scene.item then
			scene.item:set_properties({wield_item = nhv_tiles.item(tile)})
			scene.item:set_attach(player, "", vector.new(0, (scene.head + ITEM_SIZE * 0.5) * 10, 0), vector.new(0, 180, 0))
		end
	end
	-- motes of light drifting down the beam, and a ring of them at your feet
	scene.spawners = {
		core.add_particlespawner({
			amount = 90, time = DURATION, minpos = vector.new(pos.x - 0.5, pos.y + 0.2, pos.z - 0.5),
			maxpos = vector.new(pos.x + 0.5, pos.y + 4, pos.z + 0.5),
			minvel = vector.new(-0.05, -0.6, -0.05), maxvel = vector.new(0.05, -0.2, 0.05),
			minexptime = 1, maxexptime = 2.2, minsize = 0.5, maxsize = 1.1,
			texture = "[fill:2x2:#FFF4C0", glow = 14, playername = player:get_player_name(),
		}),
		core.add_particlespawner({
			amount = 40, time = 0.4, pos = vector.new(pos.x, pos.y + 0.1, pos.z),
			minvel = vector.new(-2, 0.1, -2), maxvel = vector.new(2, 0.4, 2),
			minexptime = 0.6, maxexptime = 1.2, minsize = 0.6, maxsize = 1.2,
			texture = "[fill:2x2:#FFE890", glow = 14, playername = player:get_player_name(),
		}),
	}
	-- the screen's edges darkened, and the artifact's name at the top
	scene.hud[#scene.hud + 1] = player:hud_add({
		type = "image", position = {x = 0.5, y = 0.5}, alignment = {x = 0, y = 0},
		scale = {x = -100, y = -100}, text = "nhv_vignette.png^[multiply:#000000^[opacity:200", z_index = 50,
	})
	for _, l in ipairs({{0x000000, 3}, {0xFFD25A, 0}}) do
		scene.hud[#scene.hud + 1] = player:hud_add({
			type = "text", position = {x = 0.5, y = 0.16}, alignment = {x = 0, y = 0},
			offset = {x = l[2], y = l[2]}, size = {x = 2, y = 0}, number = l[1], text = name, z_index = 51,
		})
	end
	nhv.sound.hook("artifact_obtained", {pos = vector.new(pos.x, pos.y + 1, pos.z)})
	core.log("action", "[nhv] artifact cutscene: " .. name)
end

local function finish(player)
	local s = scene
	scene = nil
	cutscene.active = false
	if not s then
		return
	end
	for _, id in ipairs(s.spawners or {}) do
		core.delete_particlespawner(id)
	end
	if s.beam then
		s.beam:remove()
	end
	if s.item then
		s.item:remove()
	end
	if player and player:is_player() then
		for _, id in ipairs(s.hud) do
			player:hud_remove(id)
		end
		player:set_look_horizontal(s.yaw)
		player:set_look_vertical(s.pitch)
		-- (back to first person, then free to change it again)
		player:set_camera({mode = "first"})
		core.after(0.2, function()
			if player:is_player() and not cutscene.active then
				player:set_camera({mode = "any"})
			end
		end)
	end
	nhv.actions.drop_waiting()
	nhv.player.refresh_speed()
end

-- (the screen is clear for one: no menu, question or title screen up, and
-- NetHack waiting for you)
local function can_start()
	return nh.ready() and not nhv.ui.open and not nhv.ui.menu_open and not nhv.ui.chat_open
		and not (nhv.title and nhv.title.open) and not nhv.hud.big_map
end

core.register_globalstep(function(dtime)
	local player = nhv.player.get()
	if scene then
		local h = nh.snap and nh.snap.hero
		if not player or (h and U.has(h.flags, U.HERO.DEAD)) then
			finish(player)
			return
		end
		scene.t = scene.t + dtime
		local k = scene.t / DURATION
		player:set_look_horizontal(scene.yaw + PAN * smooth(k))
		player:set_look_vertical(PITCH)
		-- (held up, bobbing a little)
		if scene.item then
			local bob = math.sin(scene.t * 2.4) * 0.06
			scene.item:set_attach(player, "", vector.new(0, (scene.head + ITEM_SIZE * 0.5 + bob) * 10, 0),
				vector.new(0, 180, 0))
		end
		if scene.t >= DURATION then
			finish(player)
		end
		return
	end
	if #pending > 0 and player and can_start() then
		start(player, table.remove(pending, 1))
	end
end)

nh.on_event(function(evs)
	for _, ev in ipairs(evs) do
		if ev.kind == "combat" then
			local o_id, n = ev.text:match("^artifact_get (%d+) (%d+)")
			n = tonumber(n)
			if n and n > 0 then
				local d = celebrated()
				if not d.got[tostring(n)] then
					d.got[tostring(n)] = true
					storage:set_string(KEY, core.write_json(d))
					pending[#pending + 1] = {o_id = tonumber(o_id), n = n}
				end
			end
		end
	end
end)

-- a new level or a new game: nothing left waiting
nh.on_snapshot(function(snap)
	if not snap then
		pending = {}
		if scene then
			finish(nhv.player.get())
		end
	end
end)

-- ---------------------------------------------------------------- ascension
-- Offering the Amulet on your own god's high altar: the game is won.
-- NetHack says it all at once and asks its last questions; here it plays
-- out. Time stands still, the camera circles above the altar, the music
-- turns to music_victory (when it has a sound) and a great beam of light
-- comes down on you:
--   1. "You offer the Amulet of Yendor to <god>..." and "An invisible
--      choir sings, and you are bathed in radiance..." (hook
--      "ascension_offered")
--   2. the voice of your god, read by SAM in God's voice (the voice
--      casting): "Mortal, thou hast done well!" and "In return for thy
--      service, I grant thee the gift of Immortality!"
--   3. "You ascend to the status of Demigod..." large in the middle, as you
--      rise into the light and are gone in a flash.
-- NetHack's questions wait till then (ui.lua: cutscene.take); the camera
-- goes on circling the light behind them and your gravestone.
--
-- The camera circles above the altar, placed by the VoxHack engine every
-- frame (core.nhv_camera_orbit: smooth, not stepping as the server's
-- moves would); you, on the altar, are drawn by a stand-in of your sprite
-- (nhv:asc_hero) - your own sprite goes (cutscene.hide_self), and nothing
-- is in your hand.

local ASC = {
	SPIN = math.rad(14),  -- the camera's turn round the altar, a second
	CAM_R = 5.5,          -- how far out it circles (nodes; less by walls)
	CAM_H = 4,            -- how high over your feet (less under a ceiling)
	CHOIR_AT = 2.6,       -- the choir line follows the offering
	VOICE_AT = 6,         -- the god speaks
	RISE = 6,             -- seconds you rise for
	RISE_H = 7,           -- nodes you rise
	FLASH = 1.2,          -- the flash you're gone in (seconds)
	BEAM = 2.4,           -- the beam's width, the artifact one's times this
	BEAM_H = 16,          -- its height, the artifact one's times this: up out
	                      -- of sight (about 70 blocks)
	ASK_AFTER = 1,        -- seconds after you're gone NetHack's question
	ASK_FADE = 1.5,       -- fades in, over this
	ASK_STEPS = 12,
}
local OFFER = "^You offer the Amulet of Yendor to (.-)%.%.%.$"
local CHOIR = "^An invisible choir sings, and you are bathed in radiance"
local VOICE = '^The voice of .-: "(.*)"$'
local IMMORTAL = "gift of Immortality!"
local ASCEND = "^You ascend to the status of Demigod"

local asc = nil -- the one playing

core.register_entity("nhv:asc_hero", {
	initial_properties = {
		visual = "wielditem", wield_item = nhv_tiles.item(0), glow = 6,
		physical = false, pointable = false, static_save = false,
		collisionbox = {0, 0, 0, 0, 0, 0},
	},
	on_step = function(self)
		if not (asc and asc.hero == self.object) then
			self.object:remove()
		end
	end,
})

-- (the beam is the ascension's: kept)
function cutscene.beam_kept(obj)
	return asc ~= nil and asc.beam == obj
end
cutscene.ascended = false -- (the game was won: ui.show_death's music)

-- how long SAM takes over a line (seconds; roughly)
local function speech_s(text)
	return 1.2 + #text * 0.075
end

local function text_hud(player, y, size, color, text)
	local ids = {}
	for _, l in ipairs({{0x000000, size + 1}, {color, 0}}) do
		ids[#ids + 1] = player:hud_add({
			type = "text", position = {x = 0.5, y = y}, alignment = {x = 0, y = 0},
			offset = {x = l[2], y = l[2]}, size = {x = size, y = 0}, number = l[1], text = text,
			z_index = 301, -- (over the flash, and everything)
		})
	end
	return ids
end

local function clear_text(player)
	for _, id in ipairs(asc.text or {}) do
		player:hud_remove(id)
	end
	asc.text = {}
end

-- the subtitle at the bottom: these lines, one under another
local function caption(player, lines)
	clear_text(player)
	for i, l in ipairs(lines) do
		for _, id in ipairs(text_hud(player, 0.70 + (i - 1) * 0.045, 1.6, l.color or 0xFFF4D0, l.text)) do
			asc.text[#asc.text + 1] = id
		end
	end
end

local function asc_start(player, god)
	if scene then
		finish(player)
	end
	cutscene.active, cutscene.ascended = true, true
	nhv.actions.drop_waiting()
	nhv.clock.search_held = false
	nhv.player.refresh_speed()
	core.close_formspec(player:get_player_name(), "")
	local pos = player:get_pos()
	-- (on the altar's square: the middle of it)
	local h = nh.snap and nh.snap.hero
	if h then
		local c = U.tile_center(h.x, h.y, pos.y)
		pos = vector.new(c.x, pos.y, c.z)
		player:set_pos(pos)
	end
	asc = {t = 0, pos = pos, yaw = player:get_look_horizontal(), pitch = player:get_look_vertical(),
		god = god or "your god", hud = {}, text = {}, said = {}, lines = {}}
	player:set_velocity(vector.zero())
	-- (the camera: you, out round the altar - first person, nothing in hand)
	player:set_camera({mode = "first"})
	player:hud_set_flags({wielditem = false, crosshair = false})
	cutscene.no_gravity = true
	nhv.player.refresh_speed()
	-- you, on the altar: a stand-in of your sprite
	local me = nhv.avatar.self()
	if me and me.tile then
		asc.hero = core.add_entity(pos, "nhv:asc_hero")
		if asc.hero then
			asc.hero:set_properties(nhv_tiles.look(me.tile, me.h))
			asc.hero_h = me.h
		end
	end
	cutscene.hide_self = true
	nhv.avatar.refresh()
	-- (the room over the altar: the camera stays under its ceiling)
	-- (and you rise to just under it)
	asc.cam_h, asc.rise_h = ASC.CAM_H, ASC.RISE_H
	for y = 1, math.max(ASC.CAM_H + 3, ASC.RISE_H + 3) do
		local def = core.registered_nodes[core.get_node(vector.round(vector.new(pos.x, pos.y + y, pos.z))).name]
		if def and def.walkable then
			asc.cam_h = math.min(ASC.CAM_H, math.max(1.2, y - 2.6))
			asc.rise_h = math.min(ASC.RISE_H, math.max(1, y - 0.5 - (asc.hero_h or 1.6)))
			break
		end
	end
	-- the camera, round and above the altar: as far out as the walls let
	-- it, all the way round
	local r = ASC.CAM_R
	for k = 0, 23 do
		local a = k / 24 * 2 * math.pi
		while r > 1.5 do
			local e = vector.new(pos.x - math.sin(a) * r, pos.y + asc.cam_h + 1.6, pos.z + math.cos(a) * r)
			local def = core.registered_nodes[core.get_node(vector.round(e)).name]
			if not (def and def.walkable) then
				break
			end
			r = r - 0.5
		end
	end
	if core.nhv_camera_orbit then
		core.nhv_camera_orbit({center = pos, radius = r, height = asc.cam_h + 1.6, speed = ASC.SPIN,
			angle = asc.yaw + math.pi, look_y = (asc.hero_h or 1.6) * 0.6})
	end
	-- the beam, wide, standing on the altar
	asc.beam = core.add_entity(pos, "nhv:glory_beam")
	if asc.beam then
		asc.beam:set_properties({visual_size = {x = ASC.BEAM, y = ASC.BEAM_H, z = ASC.BEAM}})
	end
	local pname = player:get_player_name()
	asc.spawners = {
		core.add_particlespawner({
			amount = 600, time = 0, minpos = vector.new(pos.x - 1.1, pos.y + 0.2, pos.z - 1.1),
			maxpos = vector.new(pos.x + 1.1, pos.y + 24, pos.z + 1.1),
			minvel = vector.new(-0.05, -0.8, -0.05), maxvel = vector.new(0.05, -0.2, 0.05),
			minexptime = 1.2, maxexptime = 2.8, minsize = 0.25, maxsize = 0.6,
			texture = "[fill:2x2:#FFF4C0", glow = 14, playername = pname,
		}),
	}
	-- the screen's edges, golden; the light on the screen (the flash, later)
	asc.hud[#asc.hud + 1] = player:hud_add({
		type = "image", position = {x = 0.5, y = 0.5}, alignment = {x = 0, y = 0},
		scale = {x = -100, y = -100}, text = "nhv_vignette.png^[multiply:#302000^[opacity:190", z_index = 50,
	})
	asc.white = player:hud_add({
		type = "image", position = {x = 0.5, y = 0.5}, alignment = {x = 0, y = 0},
		scale = {x = -100, y = -100}, text = "[fill:1x1:#FFFFFF^[opacity:0", z_index = 300,
	})
	asc.hud[#asc.hud + 1] = asc.white
	nhv.sound.set_music(nhv.sound.music_for_ascension())
	nhv.sound.hook("ascension_offered", {pos = vector.new(pos.x, pos.y + 1, pos.z)})
	core.log("action", "[nhv] ascension cutscene: " .. asc.god)
end

local function asc_finish()
	local s = asc
	asc = nil
	cutscene.active, cutscene.hide_self, cutscene.no_gravity, cutscene.menus_ok = false, false, false, false
	if not s then
		return
	end
	for _, id in ipairs(s.spawners or {}) do
		core.delete_particlespawner(id)
	end
	if s.beam then
		s.beam:remove()
	end
	if s.hero then
		s.hero:remove()
	end
	if core.nhv_camera_orbit then
		core.nhv_camera_orbit(nil)
	end
	local player = nhv.player.get()
	if player and player:is_player() then
		player:hud_set_flags({wielditem = true, crosshair = true})
		for _, id in ipairs(s.hud) do
			player:hud_remove(id)
		end
		for _, id in ipairs(s.text or {}) do
			player:hud_remove(id)
		end
		player:set_pos(s.pos)
		player:set_look_horizontal(s.yaw)
		player:set_look_vertical(s.pitch)
		player:set_camera({mode = "first"})
		core.after(0.2, function()
			if player:is_player() and not cutscene.active then
				player:set_camera({mode = "any"})
			end
		end)
	end
	nhv.avatar.refresh()
	nhv.player.refresh_speed()
end

-- the scene's lines, from what NetHack said (with NetHack's words if one
-- didn't come through)
local function line(key, default)
	return asc.lines[key] or default
end

local function flash_opacity(player, a)
	a = math.max(0, math.min(255, math.floor(a)))
	if asc.white_a ~= a then
		asc.white_a = a
		player:hud_change(asc.white, "text", "[fill:1x1:#FFFFFF^[opacity:" .. a)
	end
end

local function asc_step(player, dtime)
	asc.t = asc.t + dtime
	local t = asc.t
	-- you on the altar (risen `asc.rise` nodes), facing the camera
	local hh = asc.hero_h or 1.6
	local feet = vector.new(asc.pos.x, asc.pos.y + (asc.rise or 0), asc.pos.z)
	if asc.hero then
		asc.hero:set_pos(vector.new(feet.x, feet.y + hh / 2, feet.z))
		-- (turned to the camera, wherever the engine has it)
		local cam = core.nhv_camera and core.nhv_camera()
		if cam then
			asc.hero:set_rotation(vector.new(0, math.atan2(-(cam.x - feet.x), cam.z - feet.z) + nhv_tiles.facing_turn(), 0))
		end
	end
	player:set_velocity(vector.zero())
	if core.nhv_camera_orbit then
		core.nhv_camera_orbit({look_y = (asc.rise or 0) + hh * 0.6})
	end
	-- 1. the offering, then the choir
	if not asc.said.offer then
		asc.said.offer = true
		caption(player, {{text = line("offer", "You offer the Amulet of Yendor to " .. asc.god .. "...")}})
	end
	if t >= ASC.CHOIR_AT and not asc.said.choir then
		asc.said.choir = true
		caption(player, {{text = line("offer", "You offer the Amulet of Yendor to " .. asc.god .. "...")},
			{text = line("choir", "An invisible choir sings, and you are bathed in radiance...")}})
	end
	-- 2. the voice of your god
	local well = line("well", "Mortal, thou hast done well!")
	local gift = line("gift", "In return for thy service, I grant thee the gift of Immortality!")
	local gift_at = ASC.VOICE_AT + speech_s(well)
	local rise_at = gift_at + speech_s(gift)
	if t >= ASC.VOICE_AT and not asc.said.well then
		asc.said.well = true
		caption(player, {{text = line("voice", "The voice of " .. asc.god .. " booms out:")},
			{text = '"' .. well .. '"', color = 0xFFD25A}})
		nhv.sound.say("God", well, "god")
	end
	if t >= gift_at and not asc.said.gift then
		asc.said.gift = true
		caption(player, {{text = line("voice", "The voice of " .. asc.god .. " booms out:")},
			{text = '"' .. well .. '"', color = 0xFFD25A}, {text = '"' .. gift .. '"', color = 0xFFD25A}})
		nhv.sound.say("God", gift, "god")
	end
	-- 3. you ascend: rising into the light, gone in a flash
	if t >= rise_at then
		if not asc.said.ascend then
			asc.said.ascend = true
			clear_text(player)
			for _, id in ipairs(text_hud(player, 0.3, 3, 0xFFD25A,
					line("ascend", "You ascend to the status of Demigod..."))) do
				asc.text[#asc.text + 1] = id
			end
		end
		local k = smooth((t - rise_at) / ASC.RISE)
		asc.rise = asc.rise_h * k
		-- (the light grows on the screen as you rise; then the flash)
		local f = (t - rise_at - ASC.RISE + ASC.FLASH) / ASC.FLASH
		flash_opacity(player, f < 0 and 90 * k or 90 + 165 * math.min(1, f))
		if t >= rise_at + ASC.RISE and not asc.said.gone then
			asc.said.gone = true
			if asc.hero then
				asc.hero:remove()
				asc.hero = nil
			end
			core.add_particlespawner({
				amount = 120, time = 0.2, pos = vector.new(feet.x, feet.y + hh / 2, feet.z),
				minvel = vector.new(-3, -1, -3), maxvel = vector.new(3, 4, 3),
				minexptime = 0.8, maxexptime = 1.8, minsize = 0.3, maxsize = 0.8,
				texture = "[fill:2x2:#FFFFFF", glow = 14, playername = player:get_player_name(),
			})
		end
		-- the light fades back a little: NetHack's questions, over the
		-- light still circling where you were
		if t >= rise_at + ASC.RISE + 1.5 then
			flash_opacity(player, 255 - 120 * smooth((t - rise_at - ASC.RISE - 1.5) / 2))
		end
		-- NetHack's question, once you're gone: fading in a step at a time
		-- (then it stays, as any question; answered meanwhile - a key -
		-- it's gone)
		local ask_at = rise_at + ASC.RISE + ASC.ASK_AFTER
		if t >= ask_at and not asc.released then
			local req = nh.req
			if not asc.asking then
				asc.asking, asc.shown = true, 0
				cutscene.menus_ok = true -- (hotbar.lua: menus may open now)
				clear_text(player) -- (out of the question's way)
			end
			local step = math.min(ASC.ASK_STEPS, math.floor((t - ask_at) / ASC.ASK_FADE * ASC.ASK_STEPS) + 1)
			if not (asc.held and req and req.kind == "yn") then
				asc.released = true -- (nothing asked, or not a yes/no: as usual)
				if asc.held then
					nhv.ui.reshow()
				end
			elseif step > asc.shown then
				asc.shown = step
				nhv.ui.open = "nhv:req"
				core.show_formspec(player:get_player_name(), "nhv:req", nhv.ui.yn_fading(req, step / ASC.ASK_STEPS))
				if step == 1 then
					nhv.sound.hook("dialog_open")
				end
				if step == ASC.ASK_STEPS then
					asc.released = true
				end
			end
		end
	end
end

-- NetHack's last questions wait for the scene (ui.lua)
function cutscene.take(req)
	if asc and not asc.released then
		asc.held = true
		return true
	end
	return false
end

-- Is this one of the ascension's lines? (it's in the scene, not with the
-- messages; hud.lua). The batch that has the choir starts the scene.
function cutscene.ascension_check(evs)
	for _, ev in ipairs(evs) do
		if ev.kind == "message" and ev.text:find(CHOIR) and not asc then
			local player = nhv.player.get()
			local god
			for _, e in ipairs(evs) do
				god = god or (e.kind == "message" and e.text:match(OFFER))
			end
			if player then
				asc_start(player, god)
			end
		end
	end
end

function cutscene.ascension_line(text)
	if not asc then
		return false
	end
	local god = text:match(OFFER)
	local words = text:match(VOICE)
	if god then
		asc.lines.offer, asc.god = text, god
	elseif text:find(CHOIR) then
		asc.lines.choir = text
	elseif words then
		asc.lines.voice = text:gsub(' ?".*$', "")
		asc.lines.well = words
	elseif text:find(IMMORTAL, 1, true) then
		asc.lines.gift = text:gsub('^"', ""):gsub('"$', "")
	elseif text:find(ASCEND) then
		asc.lines.ascend = text
	else
		return false
	end
	return true
end

core.register_globalstep(function(dtime)
	if not asc then
		return
	end
	local player = nhv.player.get()
	if not player then
		asc_finish()
		return
	end
	asc_step(player, dtime)
end)

nh.on_snapshot(function(snap)
	local h = snap and snap.hero
	if not snap and asc then
		asc_finish() -- (the game is over: to the title screen)
	elseif h and not asc and not U.has(h.flags, U.HERO.DEAD) then
		cutscene.ascended = false -- (playing on: a new game)
	end
end)

return cutscene
