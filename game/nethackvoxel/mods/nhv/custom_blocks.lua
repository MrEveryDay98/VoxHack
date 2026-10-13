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
--   light      0-14
--   damage     dice ("1d4", "2") taken when you step into it ("" = none)
--   repeat     seconds between hits while you stay in it (0 = only on entry)
--   cause      what the death message says: "killed by <cause>"
--   backfaces  {top=, bottom=, east=, west=, north=, south=}: sides whose
--              back is drawn too, so they're seen from inside the block
--              (cube, slab, pane, floor)
-- New or changed blocks need the game (or editor) restarted.

local cblocks = {defs = {}}
nhv.custom_blocks = cblocks

local MODPATH = core.get_modpath("nhv_blocks")
local DATA = MODPATH and (MODPATH .. DIR_DELIM .. "blocks.json")

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
	local shape = b.shape or "cube"
	local solid = b.solid == true
	local light = math.max(0, math.min(14, tonumber(b.light) or 0))
	local groups = {editor = 1, nhv_custom = 1, not_in_creative_inventory = 1}
	local info = {
		damage = b.damage ~= "" and b.damage or nil,
		repeat_s = tonumber(b["repeat"]) or 0,
		cause = (b.cause and b.cause ~= "") and b.cause or (b.name or id),
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
	local tiles = {}
	for i, side in ipairs({"top", "bottom", "east", "west", "north", "south"}) do
		tiles[i] = {name = tex, backface_culling = not back[side]}
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
		def.tiles = {tex}
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
		def.use_texture_alpha = "opaque"
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

-- on a NetHack pit the fall already hurt you (NetHack rolls that)
local function on_pit(h)
	local sq = h and nhv.terrain and nhv.terrain.built[nhv.util.idx(h.x, h.y)]
	local c = sq and sq.memcmap or ""
	return c:match("pit") ~= nil
end

local inside, next_hit = nil, 0
local queue = {}

if not nhv.EDITOR then
	core.register_globalstep(function()
		local player = nhv.player and nhv.player.get()
		local nh = nhv.nh
		if not player or not nh.snap then
			return
		end
		local name, info = hurting_block(player:get_pos())
		local now = core.get_us_time()
		if not name then
			inside = nil
		elseif inside ~= name or (info.repeat_s > 0 and now >= next_hit) then
			local entering = inside ~= name
			inside = name
			next_hit = now + info.repeat_s * 1e6
			if not (entering and on_pit(nh.snap.hero)) then
				local dmg = roll(info.damage)
				if dmg > 0 then
					queue[#queue + 1] = {{key = "#"}, {text = ("nhvhurt %d %s"):format(dmg, info.cause)}}
				end
			end
		end
		while #queue > 0 and nh.ready() do
			nh.act(table.remove(queue, 1), {kind = "hurt"})
		end
	end)
end

return cblocks
