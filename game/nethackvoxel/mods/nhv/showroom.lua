-- The new character screen's scene: your character on a pedestal, your
-- pet beside it, under the Astral Plane's sky - out in the empty space
-- where you wait before a game starts (init.lua parks you there). The
-- character creation form (title.lua) is a panel on the right; the scene
-- shows on the left, and changes as you choose: the role and gender pick
-- the picture (Random goes round them all), the pet its own (none: no
-- pet).
--
--   showroom.show(player)   set it up (or update it to the choices now)
--   showroom.title(player)  the backdrop alone (the title screen)
--   showroom.hide(player)   take it away
--   showroom.intro(player)  the camera moved so the figures are in the
--                           middle at the bottom (the intro's narration
--                           over them: intro.lua) - they stay as they are

local U = nhv.util
local showroom = {keep = {}} -- (keep: HUD elements shown over it)
nhv.showroom = showroom

local SIZE = {hero = 1.9, pet = {cat = 0.75, dog = 0.85, horse = 1.45}}
local PEDESTAL = {n = 3, h = 1} -- (blocks across and deep; tall)
local CYCLE_S = 1.4 -- Random: a new role (or gender) this often
local LOOK_DOWN = 0.12 -- (radians: the camera a little down)
-- the intro's camera, from the creator's: back, up and across, so the
-- figures are in the middle of the screen, low down, the narration above
local INTRO_CAMERA = vector.new(-1.7, 1.45, -1.6)
local GLIDE_S = 0.8 -- (the camera's move there)

-- the role's NetHack monster (its tiles are "<monster>,<gender>")
local ROLE_MON = {archeologist = "archeologist", barbarian = "barbarian", caveman = "cave dweller",
	healer = "healer", knight = "knight", monk = "monk", priest = "cleric", ranger = "ranger",
	rogue = "rogue", samurai = "samurai", tourist = "tourist", valkyrie = "valkyrie",
	wizard = "wizard"}
local ROLES = {"archeologist", "barbarian", "caveman", "healer", "knight", "monk", "priest",
	"ranger", "rogue", "samurai", "tourist", "valkyrie", "wizard"}
-- the pet each role starts with (NetHack's: a kitten or a little dog at
-- random for the rest - a kitten here)
local ROLE_PET = {knight = "horse", samurai = "dog", caveman = "dog", ranger = "dog", wizard = "cat"}
local PET_MON = {cat = "kitten", dog = "little dog", horse = "pony"}

local tile_cache = {}
local function tile_of(mon, gender)
	local key = mon .. "," .. gender
	if tile_cache[key] == nil then
		tile_cache[key] = false
		for t = 0, nhv_tiles.count - 1 do
			local n = nhv_tiles.name(t)
			if n == key then
				tile_cache[key] = t
				break
			end
		end
	end
	return tile_cache[key] or nil
end

core.register_entity("nhv:showroom", {
	initial_properties = {
		visual = "wielditem", wield_item = nhv_tiles.item(0), glow = 10,
		physical = false, pointable = false, static_save = false,
		collisionbox = {0, 0, 0, 0, 0, 0},
	},
	on_step = function(self)
		if not showroom.objs or showroom.objs[self.part] ~= self.object then
			self.object:remove()
		end
	end,
})

core.register_entity("nhv:showroom_pedestal", {
	initial_properties = {
		visual = "cube", glow = 6, textures = {"blank.png"}, -- (the game's own: look_of, below)
		visual_size = {x = 1, y = 1, z = 1}, -- (one block)
		physical = false, pointable = false, static_save = false,
		collisionbox = {0, 0, 0, 0, 0, 0},
	},
	on_step = function(self)
		if not showroom.objs or showroom.objs[self.part] ~= self.object then
			self.object:remove()
		end
	end,
})

-- the pedestal: 3 x 3 of the dungeon's wall blocks, its floor on top
-- (the game's own blocks' pictures)
local function tile_name(node)
	local def = core.registered_nodes[node]
	local t = def and def.tiles and def.tiles[1]
	return type(t) == "table" and t.name or t or "blank.png"
end
local function pedestal_look()
	local top, side = tile_name("nhv:floor"), tile_name("nhv:wall")
	return {textures = {top, top, side, side, side, side}}
end

-- where the scene stands: ahead of the creator's camera and to its left
-- (the form covers the right of the screen), a little below its eyes -
-- looking along +z: left is -x; close up, filling the left of the screen.
-- And the camera's eyes now (the figures turned to them).
local function places(player)
	local p = showroom.spot
	local base = vector.new(p.x - 1.5, p.y - 0.45, p.z + 3.2)
	local cam = player:get_pos()
	return vector.new(cam.x, cam.y + 1.6, cam.z), base
end

-- where the camera is to be (the creator's spot, or the intro's)
local function camera_goal()
	return showroom.centred and vector.add(showroom.spot, INTRO_CAMERA) or showroom.spot
end

local function sprite(part, pos, tile, h, eye)
	local objs = showroom.objs
	local obj = objs[part]
	if not tile then
		if obj then
			obj:remove()
			objs[part] = nil
		end
		-- (forgotten too: a new one is given its picture - not left the
		-- entity's own, tile 0, the giant ant)
		showroom.shown[part] = nil
		return
	end
	if not (obj and obj:get_pos()) then
		obj = core.add_entity(pos, "nhv:showroom")
		if not obj then
			return
		end
		obj:get_luaentity().part = part
		objs[part] = obj
		showroom.shown[part] = nil
		-- (unseen until it's turned to the camera: a frame of it at its
		-- first angle, otherwise)
		obj:set_properties({is_visible = false})
		core.after(0.15, function()
			if obj:get_pos() then
				obj:set_properties({is_visible = true})
			end
		end)
	end
	local key = tile .. "/" .. h
	if showroom.shown[part] ~= key then
		showroom.shown[part] = key
		obj:set_properties(nhv_tiles.look(tile, h))
	end
	obj:set_pos(vector.new(pos.x, pos.y + h / 2 + 0.12, pos.z)) -- (feet on the top, not in it)
	-- (its front to the camera)
	obj:set_rotation(vector.new(0, math.atan2(-(eye.x - pos.x), eye.z - pos.z) + nhv_tiles.facing_turn(), 0))
end

-- the role and gender to show now (Random: going round them)
local function chosen(o)
	local t = math.floor(core.get_us_time() / 1e6 / CYCLE_S)
	local role = o.get("role")
	if not ROLE_MON[role] then
		role = ROLES[t % #ROLES + 1]
	end
	local gender = o.get("gender")
	if gender ~= "male" and gender ~= "female" then
		gender = (t % 2 == 0) and "male" or "female"
	end
	return role, gender
end

local function pet_of(o, role)
	local p = o.get("pettype")
	if p == "none" then
		return nil
	end
	return ROLE_PET[role] or (p ~= "" and p) or "cat"
end

-- the intro: the character NetHack made (Random picked), and its pet
local function made()
	local snap = nhv.nh.snap
	local h = snap and snap.hero
	if not (h and h.tile) then
		return nil
	end
	for _, m in ipairs(snap.monsters or {}) do
		if U.has(m.flags, U.MON_PET) then
			local n = nhv_tiles.name(m.tile) or ""
			local kind = n:find("pony") and "horse" or n:find("dog") and "dog" or "cat"
			return h.tile, m.tile, kind
		end
	end
	return h.tile
end

local function draw(player)
	local o = nhv.nhopts
	local eye, base = places(player)
	local role, gender = chosen(o)
	local pet = pet_of(o, role)
	local htile, ptile_made, pet_made
	if showroom.centred then
		htile, ptile_made, pet_made = made()
	end
	local top = base.y + 0.3 -- (where the figures stand)
	-- the pedestal; the character on it, the pet beside (on your left)
	local half = (PEDESTAL.n - 1) / 2
	for i = 0, PEDESTAL.n - 1 do
		for j = 0, PEDESTAL.n - 1 do
			local part = "ped" .. i .. "_" .. j
			local at = vector.new(base.x - 0.2 + i - half, top - PEDESTAL.h / 2, base.z + 0.9 + j - half)
			local ped = showroom.objs[part]
			if not (ped and ped:get_pos()) then
				ped = core.add_entity(at, "nhv:showroom_pedestal")
				showroom.objs[part] = ped
				if ped then
					ped:get_luaentity().part = part
					ped:set_properties(pedestal_look())
				end
			end
			if ped then
				ped:set_pos(at)
			end
		end
	end
	sprite("hero", vector.new(base.x + 0.45, top, base.z), htile or tile_of(ROLE_MON[role], gender), SIZE.hero, eye)
	local ptile = pet and (tile_of(PET_MON[pet], "male") or tile_of(PET_MON[pet], "female"))
	if htile then
		ptile, pet = ptile_made, pet_made
	end
	sprite("pet", vector.new(base.x - 0.85, top, base.z - 0.15), ptile, pet and SIZE.pet[pet] or 1, eye)
end

-- the backdrop: the Astral Plane's sky, the camera still, no HUD (the
-- title screen has just this; the new character screen the figures too)
function showroom.backdrop(player)
	if showroom.bd then
		return
	end
	showroom.bd = true
	-- (out in the empty space where you wait before a game: init.lua's
	-- spot - after a game too, away from the level you were on; kept
	-- there, below)
	showroom.spot = vector.new(U.TILE * 40, U.CEIL_Y + 300, U.TILE * 10)
	showroom.cam, showroom.glide = showroom.spot, nil
	-- (the mouse doesn't move the view: the VoxHack engine's camera lock -
	-- first, so the look set below, and the globalstep's, are what it holds)
	player:hud_set_flags({wielditem = false, crosshair = false, nhv_camera_lock = true})
	player:set_pos(showroom.spot)
	player:set_velocity(vector.zero())
	player:set_look_horizontal(0)
	player:set_look_vertical(LOOK_DOWN)
	nhv.player.set_speed(player) -- (still, no gravity: player.lua)
	showroom.huds = {}
	showroom.hide_huds(player)
	if nhv.sky then
		nhv.sky.scene = "astral"
		nhv.sky.update()
	end
end

-- no HUD over it: every element moved off the screen, put back as it was
-- after (and any made meanwhile - the hotbar comes a moment after you join)
function showroom.hide_huds(player)
	-- (by where it is, not its number: a removed element's number is
	-- given to the next one made)
	for id, def in pairs(player:hud_get_all() or {}) do
		-- (not the black fade over the world: the title fades in with it;
		-- nor what's shown over the scene: the intro's narration)
		if def.position and def.position.x ~= 9 and id ~= nhv.hud.ids.fade
				and not showroom.keep[id] then
			showroom.huds[id] = def.position
			player:hud_change(id, "position", {x = 9, y = 9})
		end
	end
end

-- the figures away (the backdrop stays)
local function clear_figures()
	for _, obj in pairs(showroom.objs or {}) do
		if obj:get_pos() then
			obj:remove()
		end
	end
	showroom.objs, showroom.shown = nil, nil
end

function showroom.show(player)
	showroom.backdrop(player)
	if not showroom.objs then
		showroom.objs, showroom.shown = {}, {}
	end
	draw(player)
end

-- the title screen: the backdrop alone
function showroom.title(player)
	showroom.centred, showroom.glide = nil, nil
	showroom.cam = showroom.spot
	clear_figures()
	showroom.backdrop(player)
end

-- the intro: the scene as it is - the figures not touched - the camera
-- gliding to where they're in the middle, low down
function showroom.intro(player)
	showroom.centred = true
	showroom.show(player)
	showroom.glide = {from = showroom.cam or showroom.spot, t = 0}
end

function showroom.hide(player)
	showroom.centred, showroom.glide = nil, nil
	clear_figures()
	if not showroom.bd then
		return
	end
	showroom.bd = nil
	if player and player:is_player() then
		player:hud_set_flags({wielditem = true, crosshair = true, nhv_camera_lock = false})
		for id, pos in pairs(showroom.huds or {}) do
			local def = player:hud_get(id)
			if def and def.position and def.position.x == 9 then
				player:hud_change(id, "position", pos)
			end
		end
	end
	showroom.huds = nil
	if player and player:is_player() then
		nhv.player.set_speed(player) -- (walking, and gravity, again)
	end
	if nhv.sky then
		nhv.sky.scene = nil
		nhv.sky.update()
	end
end

-- (Random goes round: redrawn now and then; you're kept on your spot - the
-- camera's, gliding to the intro's)
local since = 0
core.register_globalstep(function(dtime)
	local player = showroom.bd and nhv.player.get()
	if player then
		local goal = camera_goal()
		local g = showroom.glide
		if g then
			g.t = math.min(1, g.t + dtime / GLIDE_S)
			local k = g.t * g.t * (3 - 2 * g.t) -- (eased in and out)
			showroom.cam = vector.add(g.from, vector.multiply(vector.subtract(goal, g.from), k))
			if g.t >= 1 then
				showroom.glide = nil
			end
		else
			showroom.cam = goal
		end
		if vector.distance(player:get_pos(), showroom.cam) > 0.01 then
			player:set_pos(showroom.cam)
			player:set_velocity(vector.zero())
		end
	end
	-- (and looking the same way: the mouse doesn't turn it)
	if player and (math.abs(player:get_look_horizontal()) > 0.001
			and math.abs(player:get_look_horizontal() - 2 * math.pi) > 0.001
			or math.abs(player:get_look_vertical() - LOOK_DOWN) > 0.001) then
		player:set_look_horizontal(0)
		player:set_look_vertical(LOOK_DOWN)
	end
	if player then
		showroom.hide_huds(player)
	end
	if not showroom.objs then
		return
	end
	since = since + dtime
	-- (while the camera moves, every step: the figures kept turned to it)
	if since > 0.25 or showroom.glide then
		since = 0
		local player = nhv.player.get()
		if player then
			draw(player)
		end
	end
end)

return showroom
