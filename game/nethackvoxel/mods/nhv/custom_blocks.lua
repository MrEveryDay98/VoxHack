-- Blocks made in the block editor (the browser tool's Blocks tab).
--
-- Definitions are in mods/nhv_blocks/blocks.json, their pictures in
-- mods/nhv_blocks/textures (or a sprite from the sheet). Each becomes the
-- block "nhv:x_<id>", in the prefab editor's palette. Fields:
--   name       shown in the palette
--   shape      cube | x (two crossed sprites, like grass) | floor (flat on
--              the ground) | slab | pane | object (an extruded 3D sprite
--              keeping the way it was placed) | invisible
--   texture    {"file": "name.png"} or {"sheet": <sprite number>}
--   scale      size of x / object sprites (1 = one block)
--   solid      you can't walk through it
--   climbable  like a ladder
--   turns      "" (cubes: always the same way), "south" or "north": turns as
--              you place it, that side facing you (slabs and panes always
--              turn; "north" flips them round too)
--   stretch    (cube) like doors: each box of these blocks touching each
--              other is drawn as one big block, each side's picture
--              stretched over it (drawn by doors.lua)
--   light      0-14
--   damage     dice ("1d4", "2") taken when you step into it ("" = none)
--   repeat     seconds between hits while you stay in it (0 = only on entry)
--   cause      what the death message says: "killed by <cause>"
--   spikes     iron spikes: iron boots protect you, and they may be poisoned
--              (1 in 6), as in a NetHack spiked pit
--   backfaces  {top=, bottom=, east=, west=, north=, south=}: sides whose
--              back is drawn too, so they're seen from inside the block
--              (cube, slab, pane, floor)
--   hidden     the same, for sides that aren't drawn at all
-- New or changed blocks need the game (or editor) restarted.

local cblocks = {defs = {}, stretch = {}}
nhv.custom_blocks = cblocks

local MODPATH = core.get_modpath("nhv_blocks")
local DATA = MODPATH and (MODPATH .. DIR_DELIM .. "blocks.json")

-- an animated picture (frames stacked top to bottom): its tile animation
local function animation_of(t)
	local frames = type(t) == "table" and tonumber(t.frames) or 1
	if frames > 1 and t.file and t.file ~= "" then
		return {type = "vertical_frames", aspect_w = 16, aspect_h = 16,
			length = tonumber(t.length) or 1}
	end
end

local function texture_of(t)
	if type(t) ~= "table" then
		return "blank.png"
	elseif t.file and t.file ~= "" then
		return t.file
	elseif t.sheet then
		return nhv_tiles.sheet_texture(tonumber(t.sheet) or 0)
	end
	return "blank.png"
end

local BOXES = {
	floor = {-0.5, -0.5, -0.5, 0.5, -0.4375, 0.5},
	slab = {-0.5, -0.5, -0.5, 0.5, 0, 0.5},
	pane = {-0.5, -0.5, -0.0625, 0.5, 0.5, 0.0625},
}

local function register(b)
	local id = tostring(b.id or ""):lower():gsub("[^a-z0-9_]", "_")
	if id == "" then
		return
	end
	local name = "nhv:x_" .. id
	local tex = texture_of(b.texture)
	local anim = animation_of(b.texture)
	local shape = b.shape or "cube"
	local solid = b.solid == true
	local light = math.max(0, math.min(14, tonumber(b.light) or 0))
	local groups = {editor = 1, nhv_custom = 1, not_in_creative_inventory = 1}
	local info = {
		damage = b.damage ~= "" and b.damage or nil,
		repeat_s = tonumber(b["repeat"]) or 0,
		cause = (b.cause and b.cause ~= "") and b.cause or (b.name or id),
		spikes = b.spikes == true,
	}
	if info.damage then
		groups.nhv_hurts = 1
	end
	local common = {
		walkable = solid, climbable = b.climbable == true,
		light_source = light > 0 and light or nil,
		_nhv_block = info,
	}
	if shape == "object" then
		common.groups = groups
		nhv.props.register(name, tex, b.name or id, common)
		cblocks.defs[name] = info
		return
	end
	-- one tile per side (+Y, -Y, +X, -X, +Z, -Z), each culled unless its
	-- back face is asked for
	local back = type(b.backfaces) == "table" and b.backfaces or {}
	local hide = type(b.hidden) == "table" and b.hidden or {}
	local tiles, any_hidden, any_back = {}, false, false
	local faces = {} -- per side: {tex=, frames=, length=} (stretched blocks)
	-- (its own top and bottom, if it has them: a tree trunk's rings; a bottom
	-- alone is the top's too)
	local top = b.texture_top or b.texture
	local bottom = b.texture_bottom or b.texture_top or b.texture
	local of_side = {top = top, bottom = bottom}
	for i, side in ipairs({"top", "bottom", "east", "west", "north", "south"}) do
		if hide[side] then
			tiles[i] = {name = "blank.png"} -- not drawn (fully see-through)
			any_hidden = true
			faces[i] = {tex = "blank.png", frames = 1}
		else
			local t = of_side[side] or b.texture
			tiles[i] = {name = texture_of(t), backface_culling = not back[side], animation = animation_of(t)}
			local a = tiles[i].animation
			faces[i] = {tex = tiles[i].name, frames = a and tonumber(t.frames) or 1, length = a and a.length}
			any_back = any_back or back[side] == true
		end
	end
	local def = {
		description = b.name or id,
		tiles = tiles, paramtype = "light",
		is_ground_content = false, drop = "", groups = groups,
		use_texture_alpha = "clip",
	}
	for k, v in pairs(common) do
		def[k] = v
	end
	if shape == "x" then
		def.tiles = {{name = tex, animation = anim}}
		def.drawtype = "plantlike"
		def.visual_scale = tonumber(b.scale) or 1
		def.sunlight_propagates = true
		def.inventory_image = tex
		def.selection_box = {type = "fixed", fixed = {-0.4, -0.5, -0.4, 0.4, 0.3, 0.4}}
	elseif BOXES[shape] then
		def.drawtype = "nodebox"
		def.node_box = {type = "fixed", fixed = BOXES[shape]}
		def.paramtype2 = "facedir"
		def.on_place = core.rotate_node
		def.sunlight_propagates = true
		if shape == "floor" then
			def.paramtype2 = nil
			def.on_place = nil
			def.walkable = false -- it's just on the floor
		end
	elseif shape == "invisible" then
		def.drawtype = "airlike"
		def.pointable = nhv.EDITOR
		def.sunlight_propagates = true
		def.inventory_image = tex
	else
		def.drawtype = "normal"
		-- (a cube with an undrawn side has to let you see through it)
		def.use_texture_alpha = any_hidden and "clip" or "opaque"
	end
	-- turning to face the way it's placed (as stairs do): the engine puts a
	-- facedir block's south side toward you; "north" turns it round after
	if (shape == "cube" or shape == "slab" or shape == "pane") and (b.turns == "south" or b.turns == "north") then
		def.paramtype2 = "facedir"
		if b.turns == "north" then
			def.after_place_node = function(pos)
				local n = core.get_node(pos)
				local axis, rot = math.floor(n.param2 / 4), n.param2 % 4
				n.param2 = axis * 4 + (rot + 2) % 4
				core.swap_node(pos, n)
			end
		end
	end
	-- stretched: the blocks aren't drawn themselves; doors.lua draws one
	-- box over each group of them touching
	if shape == "cube" and b.stretch == true then
		local still = faces[5].frames > 1 and ("%s^[verticalframe:%d:0"):format(faces[5].tex, faces[5].frames) or faces[5].tex
		def.drawtype = "airlike"
		def.sunlight_propagates = true
		def.pointable = true
		def.inventory_image = still
		def.wield_image = still
		groups.nhv_stretch = 1
		cblocks.stretch[name] = {faces = faces, backfaces = any_back}
	end
	core.register_node(":" .. name, def)
	cblocks.defs[name] = info
end

local function load()
	if not DATA then
		return
	end
	local f = io.open(DATA, "rb")
	if not f then
		return
	end
	local data = core.parse_json(f:read("*a"))
	f:close()
	if type(data) ~= "table" or type(data.blocks) ~= "table" then
		core.log("warning", "[nhv] mods/nhv_blocks/blocks.json isn't valid")
		return
	end
	for _, b in ipairs(data.blocks) do
		register(b)
	end
end
load()

-- ---------------------------------------------------------------- game blocks
-- The block editor's "Game blocks" tab: the game writes what its own blocks
-- look like (blocks_catalog.json in its mod data folder), and the changes
-- made there (mods/nhv_blocks/overrides.json: block name -> name, texture,
-- light, solid, climbable, damage, repeat, cause, backfaces) are applied
-- here once every mod has registered its blocks.
local OVERRIDES = MODPATH and (MODPATH .. DIR_DELIM .. "overrides.json")
local DATA_DIR = core.get_mod_data_path() -- (only available while mods load)
local CATALOG = DATA_DIR .. DIR_DELIM .. "blocks_catalog.json"
local SIDES = {"top", "bottom", "east", "west", "north", "south"}

local function first_tile(def)
	local t = def.tiles and def.tiles[1]
	if type(t) == "table" then
		t = t.name
	end
	return t or def.inventory_image or ""
end

local function write_catalog()
	local cat = {}
	for name, def in pairs(core.registered_nodes) do
		if name:match("^nhv:") and not name:match("^nhv:x_")
				and def.groups and (def.groups.editor or def.groups.nhv_prop) then
			cat[#cat + 1] = {
				name = name, description = def.description or name,
				drawtype = def.drawtype or "normal", texture = first_tile(def),
				solid = def.walkable ~= false, climbable = def.climbable == true,
				light = def.light_source or 0, prop = def.groups.nhv_prop and true or nil,
			}
		end
	end
	table.sort(cat, function(a, b) return a.name < b.name end)
	core.mkdir(DATA_DIR)
	core.safe_file_write(CATALOG, core.write_json(cat, true))
end

local function apply_override(name, o)
	local def = core.registered_nodes[name]
	if not def or type(o) ~= "table" then
		return
	end
	local ch = {}
	if o.name and o.name ~= "" then
		ch.description = o.name
	end
	local tiles = def.tiles
	if type(o.texture) == "table" and (o.texture.file or o.texture.sheet) then
		local tex = texture_of(o.texture)
		tiles = {}
		for i, t in ipairs(def.tiles or {tex}) do
			tiles[i] = {name = tex, backface_culling = type(t) == "table" and t.backface_culling or nil}
		end
		ch.tiles = tiles
		ch.inventory_image = tex
		if def.groups and def.groups.nhv_prop then
			ch.wield_image = tex -- objects are drawn from this
		end
	end
	local back = type(o.backfaces) == "table" and o.backfaces or {}
	local hide = type(o.hidden) == "table" and o.hidden or {}
	if next(back) or next(hide) then
		local out = {}
		for i, side in ipairs(SIDES) do
			local t = (tiles or {})[math.min(i, #(tiles or {}))] or first_tile(def)
			t = type(t) == "table" and table.copy(t) or {name = t}
			t.backface_culling = not back[side]
			if hide[side] then
				t = {name = "blank.png"} -- not drawn
			end
			out[i] = t
		end
		ch.tiles = out
		if next(hide) then
			ch.use_texture_alpha = "clip"
		end
	end
	if o.light ~= nil then
		ch.light_source = math.max(0, math.min(14, tonumber(o.light) or 0))
	end
	if o.solid ~= nil then
		ch.walkable = o.solid == true
	end
	if o.climbable ~= nil then
		ch.climbable = o.climbable == true
	end
	if next(ch) then
		core.override_item(name, ch)
	end
	if o.damage and o.damage ~= "" then
		cblocks.defs[name] = {damage = o.damage, repeat_s = tonumber(o["repeat"]) or 0,
			cause = (o.cause and o.cause ~= "") and o.cause or (o.name or def.description or name),
			spikes = o.spikes == true}
	end
end

core.register_on_mods_loaded(function()
	write_catalog() -- (before the changes: the editor shows both)
	local f = OVERRIDES and io.open(OVERRIDES, "rb")
	if not f then
		return
	end
	local data = core.parse_json(f:read("*a"))
	f:close()
	if type(data) ~= "table" then
		core.log("warning", "[nhv] mods/nhv_blocks/overrides.json isn't valid")
		return
	end
	for name, o in pairs(data.blocks or data) do
		apply_override(name, o)
	end
end)

-- ---------------------------------------------------------------- damage
-- "1d4" / "2d6+1" / "3" -> a roll
local function roll(dice)
	local n, s, plus = tostring(dice):match("^%s*(%d*)d(%d+)%s*([+-]?%s*%d*)%s*$")
	if s then
		local total = 0
		for _ = 1, math.max(1, tonumber(n) or 1) do
			total = total + math.random(tonumber(s))
		end
		local bonus = (plus or ""):gsub("%s", "") -- (keep only the string, not gsub's count)
		return total + (tonumber(bonus) or 0)
	end
	return tonumber(dice) or 0
end

-- the hurting block your body is in, if any
local function hurting_block(pos)
	for _, dy in ipairs({0.1, 0.9, 1.6}) do
		local p = vector.round(vector.new(pos.x, pos.y + dy, pos.z))
		local info = cblocks.defs[core.get_node(p).name]
		if info and info.damage then
			return core.get_node(p).name, info
		end
	end
end

-- the trap on the hero's square ("S_pit", "S_spiked_pit", ...)
local function square_cmap(h)
	local sq = h and nhv.terrain and nhv.terrain.built[nhv.util.idx(h.x, h.y)]
	return sq and sq.memcmap or ""
end

local inside, next_hit = nil, 0
local queue = {}

-- (iron spikes go through NetHack's spike rules: boots, poison)
local function hurt(dmg, cause, spikes)
	if dmg > 0 then
		queue[#queue + 1] = {{key = "#"}, {text = ("%s %d %s"):format(spikes and "nhvspike" or "nhvhurt", dmg, cause)}}
	end
end

-- Pits (NetHack doesn't hurt you for them in free mode): a plain pit hurts
-- when you drop to its bottom, like NetHack's fall (1d6); walking about
-- down there doesn't. A spiked pit hurts only through its spike blocks.
local PIT_DROP = 1.5 -- nodes you must fall (a jump inside the pit is less)
local fall_top -- height you started falling from, while falling

local function check_fall(pos, vel, h)
	if vel.y < -0.5 then
		fall_top = math.max(fall_top or pos.y, pos.y)
		return
	end
	if not fall_top or vel.y < -0.05 then
		return
	end
	local drop = fall_top - pos.y
	fall_top = nil
	if drop >= PIT_DROP and pos.y < nhv.util.STAND_Y - 1 then
		local cmap = square_cmap(h)
		if cmap == "S_pit" then
			nhv.hud.message("You fall into a pit!")
			hurt(math.random(6), "fell into a pit")
		elseif cmap == "S_spiked_pit" then
			nhv.hud.message("You fall into a pit of spikes!")
		end
	end
end

if not nhv.EDITOR then
	core.register_globalstep(function()
		local player = nhv.player and nhv.player.get()
		local nh = nhv.nh
		if not player or not nh.snap then
			return
		end
		check_fall(player:get_pos(), player:get_velocity(), nh.snap.hero)
		local name, info = hurting_block(player:get_pos())
		local now = core.get_us_time()
		if not name then
			inside = nil
		elseif inside ~= name or (info.repeat_s > 0 and now >= next_hit) then
			inside = name
			next_hit = now + info.repeat_s * 1e6
			hurt(roll(info.damage), info.cause, info.spikes)
		end
		while #queue > 0 and nh.ready() do
			nh.act(table.remove(queue, 1), {kind = "hurt"})
		end
	end)
end

return cblocks
