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
		if not (scene and scene.beam == self.object) then
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

return cutscene
