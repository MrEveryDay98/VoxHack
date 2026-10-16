-- Being held by a monster (a mimic sticking to you, an owlbear's hug, an
-- eel wrapped around you...): a tendril (textures/nhv_tendril.png) reaches
-- from the monster to you, its loop around your waist. The image's top
-- half is the stem, stretched to reach; its bottom half is the loop.

local U = nhv.util
local nh = nhv.nh
local holds = {}
nhv.holds = holds

local TEX = "nhv_tendril.png"
-- (stem and loop as items, so they're drawn as thick pixel sprites like
-- everything else)
core.register_craftitem("nhv:tendril_stem", {
	description = "Tendril", inventory_image = TEX .. "^[sheet:1x2:0,0",
	groups = {not_in_creative_inventory = 1},
})
core.register_craftitem("nhv:tendril_loop", {
	description = "Tendril", inventory_image = TEX .. "^[sheet:1x2:0,1",
	groups = {not_in_creative_inventory = 1},
})

core.register_entity("nhv:tendril", {
	initial_properties = {
		visual = "wielditem", wield_item = "nhv:tendril_stem",
		visual_size = {x = 0.5, y = 0.5, z = 0.5},
		physical = false, pointable = false, static_save = false,
		glow = 4,
	},
})

-- wielditem size 1 draws an item this many nodes across
local ITEM_NODES = 1.0
local WAIST = 0.9        -- height of the loop above your feet
local LOOP_W = 0.5       -- the loop image, nodes across (scaled like the stem)
local STEM_W = 0.3       -- the stem image, nodes across (the stem is a few pixels of it)
local THICK = 0.12

local parts = nil -- {stem=, loop=}

local function remove()
	if parts then
		for _, o in ipairs({parts.stem, parts.loop}) do
			if o:get_pos() then
				o:remove()
			end
		end
		parts = nil
	end
end

local function add(pos, item)
	local o = core.add_entity(pos, "nhv:tendril")
	if o then
		o:set_properties({wield_item = item})
	end
	return o
end

-- where the holder reaches from: its body, at your waist height
local function holder_pos()
	local h = nh.snap and nh.snap.hero
	if not h or not U.has(h.flags, U.HERO.HELD) then
		return
	end
	for _, e in pairs(nhv.mobs.mons) do
		if e.mon and U.has(e.mon.flags or 0, U.MON_HOLDING) then
			return U.tile_center(e.x, e.y), e.h
		end
	end
end

-- a soft white glow at the screen's edges while you're held, slowly
-- pulsing
local vignette = nil -- {player=, id=, shown=}
local function set_vignette(player, on)
	if vignette and vignette.player ~= player then
		vignette = nil
	end
	if not on then
		if vignette then
			player:hud_remove(vignette.id)
			vignette = nil
		end
		return
	end
	if not vignette then
		vignette = {player = player, id = player:hud_add({
			type = "image", position = {x = 0.5, y = 0.5}, alignment = {x = 0, y = 0},
			scale = {x = -100, y = -100}, text = "blank.png", z_index = -10,
		})}
	end
	-- (steps of 16: few different textures)
	local t = core.get_us_time() / 1e6
	local a = math.floor((110 + 50 * math.sin(t * 3)) / 16) * 16
	local tex = ("nhv_vignette.png^[multiply:#ffffff^[opacity:%d"):format(a)
	if tex ~= vignette.shown then
		vignette.shown = tex
		player:hud_change(vignette.id, "text", tex)
	end
end

-- Swallowed: inside some engulfers the whole view is their insides
-- (overlay_<name>.png in nhv_tiles, drawn as it is, covering the screen;
-- the HUD stays on top)
local ENGULF_OVERLAYS = {["purple worm"] = "overlay_purpleworm.png"}
local overlay = nil -- {player=, id=, tex=}

local function engulfer_name()
	local snap = nh.snap
	if not snap or not snap.hero or not U.has(snap.hero.flags, U.HERO.SWALLOWED) then
		return
	end
	for _, m in ipairs(snap.monsters or {}) do
		if U.has(m.flags, U.MON_ENGULFING) and m.mndx and m.mndx >= 0 then
			return core.nh_mon_name(m.mndx)
		end
	end
end

local function set_overlay(player, tex)
	if overlay and overlay.player ~= player then
		overlay = nil
	end
	if overlay and overlay.tex ~= tex then
		player:hud_remove(overlay.id)
		overlay = nil
	end
	if tex and not overlay then
		overlay = {player = player, tex = tex, id = player:hud_add({
			type = "image", position = {x = 0.5, y = 0.5}, alignment = {x = 0, y = 0},
			scale = {x = -100, y = -100}, text = tex, z_index = -20,
		})}
	end
end

local test_until = 0 -- (/nhvtendril: one from in front of you, to look at)
local ALWAYS = core.settings:get_bool("nhv_test_tendril", false) -- (for tests)

local function update(player)
	local from = holder_pos()
	set_vignette(player, from ~= nil)
	local inside = engulfer_name()
	set_overlay(player, inside and ENGULF_OVERLAYS[inside:lower()])
	-- (where you're pinned, not your body's position this step: that
	-- wobbles a little and the tendril would jitter with it)
	local ppos = nhv.player.held_at or player:get_pos()
	if not from and (core.get_us_time() < test_until or ALWAYS) then
		if ALWAYS then -- (a fixed view to look at it from)
			player:set_look_vertical(tonumber(core.settings:get("nhv_test_tendril_pitch")) or 0.5)
		end
		local d = player:get_look_dir()
		d.y = 0
		from = vector.add(ppos, vector.multiply(vector.normalize(d), 4))
	end
	if not from then
		remove()
		return
	end
	local waist = vector.add(ppos, vector.new(0, WAIST, 0))
	from = vector.new(from.x, waist.y, from.z)
	local d = vector.subtract(waist, from)
	local len = vector.length(d)
	if len < 0.05 then
		remove()
		return
	end
	if not parts or not parts.stem:get_pos() or not parts.loop:get_pos() then
		remove()
		local stem, loop = add(from, "nhv:tendril_stem"), add(waist, "nhv:tendril_loop")
		if not stem or not loop then
			return
		end
		parts = {stem = stem, loop = loop}
	end
	-- lying flat, pointing from the holder to you; the stem ends where the
	-- loop starts (the loop's top edge, toward the holder)
	local yaw = core.dir_to_yaw(d)
	local loop_r = LOOP_W / 2
	local stem_len = math.max(0.05, len - loop_r)
	local mid = vector.add(from, vector.multiply(d, stem_len / 2 / len))
	-- (only when something moved: moving entities every step makes them
	-- jitter)
	local key = ("%.2f %.2f %.2f %.2f %.2f %.2f"):format(from.x, from.y, from.z, waist.x, waist.y, waist.z)
	if key == parts.key then
		return
	end
	parts.key = key
	parts.stem:set_pos(mid)
	parts.stem:set_rotation(vector.new(math.pi / 2, yaw, 0))
	parts.stem:set_properties({visual_size = {x = STEM_W / ITEM_NODES,
		y = stem_len / ITEM_NODES, z = THICK / ITEM_NODES}})
	parts.loop:set_pos(waist)
	parts.loop:set_rotation(vector.new(math.pi / 2, yaw, 0))
	parts.loop:set_properties({visual_size = {x = LOOP_W / ITEM_NODES,
		y = LOOP_W / ITEM_NODES, z = THICK / ITEM_NODES}})
end

core.register_globalstep(function()
	local player = nhv.player.get()
	if player then
		update(player)
	else
		remove()
	end
end)

core.register_chatcommand("nhvtendril", {
	description = "Show the held-by-a-monster tendril for a few seconds",
	func = function()
		test_until = core.get_us_time() + 8e6
		return true, "Tendril shown for 8 seconds."
	end,
})

return holds
