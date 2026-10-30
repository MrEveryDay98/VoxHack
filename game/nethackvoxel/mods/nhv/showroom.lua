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

local U = nhv.util
local showroom = {}
nhv.showroom = showroom

local SIZE = {hero = 1.9, pet = {cat = 0.75, dog = 0.85, horse = 1.45}}
local PEDESTAL = {w = 2.6, h = 0.6, d = 1.6}
local CYCLE_S = 1.4 -- Random: a new role (or gender) this often
local LOOK_DOWN = 0.12 -- (radians: the camera a little down)

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
		visual_size = {x = PEDESTAL.w, y = PEDESTAL.h, z = PEDESTAL.d},
		physical = false, pointable = false, static_save = false,
		collisionbox = {0, 0, 0, 0, 0, 0},
	},
	on_step = function(self)
		if not showroom.objs or showroom.objs.pedestal ~= self.object then
			self.object:remove()
		end
	end,
})

-- the pedestal's look: the dungeon's floor on top, its wall on the sides
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

-- where the scene stands, from where you are: ahead of you and to your left
-- (the form covers the right of the screen), a little below your eyes
local function places(player)
	local p = player:get_pos()
	local eye = vector.new(p.x, p.y + 1.6, p.z)
	-- (looking along +z: left is -x; close up, filling the left of the
	-- screen)
	local base = vector.new(p.x - 1.5, p.y - 0.45, p.z + 3.2)
	return eye, base
end

local function sprite(part, pos, tile, h, eye)
	local objs = showroom.objs
	local obj = objs[part]
	if not tile then
		if obj then
			obj:remove()
			objs[part] = nil
		end
		return
	end
	if not (obj and obj:get_pos()) then
		obj = core.add_entity(pos, "nhv:showroom")
		if not obj then
			return
		end
		obj:get_luaentity().part = part
		objs[part] = obj
	end
	local key = tile .. "/" .. h
	if showroom.shown[part] ~= key then
		showroom.shown[part] = key
		obj:set_properties(nhv_tiles.look(tile, h))
	end
	obj:set_pos(vector.new(pos.x, pos.y + h / 2 + 0.12, pos.z)) -- (feet on the top, not in it)
	-- (its front to the camera)
	obj:set_rotation(vector.new(0, math.atan2(-(eye.x - pos.x), eye.z - pos.z) + math.pi, 0))
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

local function draw(player)
	local o = nhv.nhopts
	local eye, base = places(player)
	local role, gender = chosen(o)
	local pet = pet_of(o, role)
	local top = base.y + PEDESTAL.h / 2
	-- the pedestal; the character on it, the pet beside (on your left)
	local ped = showroom.objs.pedestal
	if not (ped and ped:get_pos()) then
		ped = core.add_entity(base, "nhv:showroom_pedestal")
		showroom.objs.pedestal = ped
		if ped then
			ped:set_properties(pedestal_look())
		end
	end
	if ped then
		ped:set_pos(base)
	end
	sprite("hero", vector.new(base.x + 0.45, top, base.z), tile_of(ROLE_MON[role], gender), SIZE.hero, eye)
	local ptile = pet and (tile_of(PET_MON[pet], "male") or tile_of(PET_MON[pet], "female"))
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
	player:set_pos(showroom.spot)
	player:set_velocity(vector.zero())
	player:set_look_horizontal(0)
	player:set_look_vertical(LOOK_DOWN)
	player:hud_set_flags({wielditem = false, crosshair = false})
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
		if def.position and def.position.x ~= 9 then
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
	clear_figures()
	showroom.backdrop(player)
end

function showroom.hide(player)
	clear_figures()
	if not showroom.bd then
		return
	end
	showroom.bd = nil
	if player and player:is_player() then
		player:hud_set_flags({wielditem = true, crosshair = true})
		for id, pos in pairs(showroom.huds or {}) do
			local def = player:hud_get(id)
			if def and def.position and def.position.x == 9 then
				player:hud_change(id, "position", pos)
			end
		end
	end
	showroom.huds = nil
	if nhv.sky then
		nhv.sky.scene = nil
		nhv.sky.update()
	end
end

-- (Random goes round: redrawn now and then; you're kept on your spot)
local since = 0
core.register_globalstep(function(dtime)
	local player = showroom.bd and nhv.player.get()
	if player and vector.distance(player:get_pos(), showroom.spot) > 0.05 then
		player:set_pos(showroom.spot)
		player:set_velocity(vector.zero())
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
	if since > 0.25 then
		since = 0
		local player = nhv.player.get()
		if player then
			draw(player)
		end
	end
end)

return showroom
