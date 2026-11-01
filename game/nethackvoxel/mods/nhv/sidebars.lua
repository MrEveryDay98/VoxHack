-- Side bars (Options > Graphics > HUD layout "Side bars"; the setting
-- nhv_hud_layout = sidebars): the HUD round the view instead of over it,
-- an old dungeon crawler's screen - the view in the middle, a bar each side
-- (the world under them hidden):
--   left:  your portrait, HP and Pw, your numbers (gold, AC, experience,
--          the stats, alignment and turns), what you wear (the inventory's
--          equipment slots), your two weapons side by side (the hotbar's,
--          hotbar.lua) and your quiver under them, and your ailments (the
--          status line's conditions, each in its colour)
--   right: the map and the level, the dialogue box (speech.lua) and what's
--          on the ground where you stand (hud.lua), "F  Pick up" under it
-- The action keys stay along the bottom of the view, the messages and the
-- compass along its top. Each bar is as wide as the
-- corner map needs (Map size), at most a quarter of the screen (the map
-- made smaller to fit); everything in them sized to the screen's height.

local U = nhv.util
local nh = nhv.nh

local sidebars = {}
nhv.sidebars = sidebars

local BAR = "#6C91B6"     -- the bars
local EDGE = "#000000"    -- their edge on the view's side
local EDGE_W = 3
local PANEL = "#1A1A20"   -- the equipment panel
local SLOT_FRAME = "#50505A"
local SLOT_INNER = "#141418"
local PAD = 8
sidebars.STAT_LINES = 3    -- the stats' lines (hud.lua's show_status)
sidebars.AILMENT_LINES = 4 -- ailments the box shows

function sidebars.on()
	return core.settings:get("nhv_hud_layout") == "sidebars"
end

-- a line of HUD text: its height, and a character's width (the pixel
-- font's letters are all one width; the other's about the same)
local function text_metrics()
	local k = nhv.theme.box_scale()
	return math.ceil((nhv.theme.retro() and 15 or 18) * k), (nhv.theme.retro() and 8 or 8.6) * k
end
sidebars.text_metrics = text_metrics

-- The bars' layout, in HUD units (nil: not on, or the window not known yet)
function sidebars.geometry(player)
	if not sidebars.on() then
		return nil
	end
	local info = player and core.get_player_window_information(player:get_player_name())
	if not (info and info.size and info.real_hud_scaling and info.real_hud_scaling > 0) then
		return nil
	end
	local k = info.real_hud_scaling
	local sw, sh = info.size.x / k, info.size.y / k
	local line_h, char_w = text_metrics()
	local hud = nhv.hud
	-- (the map: as big as Map size makes it, at most what a quarter of the
	-- screen holds - whole screen pixels a square)
	local s = hud.corner_scale(player)
	local most = math.floor((sw * 0.25 - 2 * PAD) / U.COLNO * k) / k
	if s > most then
		s = hud.hud_px(player, math.max(1 / k, most))
	end
	local w = math.floor(math.max(U.COLNO * s + 2 * PAD, 3 * 40 + 2 * PAD + 20, sw * 0.12))
	local g = {w = w, sw = sw, sh = sh, pad = PAD, map_s = s, line_h = line_h, char_w = char_w}
	-- left: portrait, bars, your numbers, the equipment, the weapons and
	-- the quiver, the ailments
	local inner = w - 2 * PAD
	local y = PAD
	local ph = math.floor(math.min(inner, sh * 0.16))
	g.portrait = {x = PAD, y = y, w = inner, h = ph}
	y = y + ph + 6
	local bh = math.floor(14 * nhv.theme.box_scale() + 6)
	g.bars = {x = PAD, y = {y, y + bh + 4}, w = inner, h = bh}
	y = y + 2 * bh + 4 + 6
	-- (the gold/AC/experience line, then the stats in STAT_LINES lines)
	g.info_y = y + line_h / 2
	g.stats_y = y + line_h + 2
	y = y + (1 + sidebars.STAT_LINES) * line_h + 10
	-- (the ailments' box at the bottom: AILMENT_LINES of them)
	local ah = sidebars.AILMENT_LINES * line_h + 12
	g.ailments = {x = PAD, y = sh - PAD - ah, w = inner, h = ah}
	-- (the wear slots and their captions, 4 rows; then the two weapons,
	-- bigger, side by side, and the quiver under them in the middle)
	local gap = 4
	local room = g.ailments.y - 8 - y
	local by_h = math.floor((room - 12 - 4 * (line_h + gap) - 16) / (4 + 2 * 1.4))
	local by_w = math.floor((inner - 12 - 2 * gap) / 3)
	local S = math.max(16, math.min(by_h, by_w))
	local step = S + line_h + gap
	local ph_eq = math.floor(6 + 3 * step + S + line_h + 6)
	g.equip = {x = PAD, y = y, w = inner, h = ph_eq, slot = S, step = step,
		col_gap = math.floor((inner - 12 - 3 * S) / 2)}
	y = y + ph_eq + 8
	local S2 = math.floor(math.min(S * 1.4, (inner - 8) / 2))
	g.weapons = {size = S2, {x = PAD + 2, y = y}, {x = w - PAD - 2 - S2, y = y}}
	g.quiver = {x = math.floor((w - S2) / 2), y = y + S2 + 8, size = S2}
	-- right: the map, the level under it, the dialogue box, the ground's box
	g.map = {x = -(PAD + math.floor((inner - U.COLNO * s) / 2)), y = PAD}
	g.level_y = PAD + U.ROWNO * s + 4
	local top = g.level_y + line_h + 6
	local rest = sh - top - PAD - 2 * line_h - 10
	local dh = math.floor(rest * 0.5)
	g.dialog = {x = -(w - PAD), y = top, w = inner, h = dh}
	g.items = {x = -(w - PAD), y = top + dh + 8, w = inner, h = rest - dh - 8}
	g.pickup_y = g.items.y + g.items.h + 6
	-- (characters a line in a box)
	g.box_chars = math.max(8, math.floor((inner - 12) / char_w))
	return g
end

-- ---------------------------------------------------------------- drawing
local ids = {}       -- element ids: bars, panel, boxes, slots
local slot_ids = {}  -- equipment slot id -> {icon=}
local shown = {}     -- equipment slot id -> texture shown

local function remove(player)
	for _, id in pairs(ids) do
		player:hud_remove(id)
	end
	for _, s in pairs(slot_ids) do
		player:hud_remove(s.bg)
		player:hud_remove(s.icon)
		player:hud_remove(s.label)
	end
	ids, slot_ids, shown = {}, {}, {}
end

local function add(player, def)
	def.scale = def.scale or {x = 1, y = 1}
	return player:hud_add(def)
end

local LEFT, RIGHT = {x = 0, y = 0}, {x = 1, y = 0}

-- what's worn and wielded, in the slots
function sidebars.refresh(player, inv)
	if not next(slot_ids) or not nhv.ui.EQUIP then
		return
	end
	for _, slot in ipairs(nhv.ui.EQUIP) do
		local s = slot_ids[slot.id]
		if s then
			local o = nhv.ui.equipped(slot, inv or {})
			local tex = o and nhv_tiles.texture(o.tile) or "blank.png"
			if shown[slot.id] ~= tex then
				shown[slot.id] = tex
				player:hud_change(s.icon, "text", tex)
			end
		end
	end
end

-- (built again: turned on or off, the window or the text a new size)
function sidebars.rebuild(player)
	remove(player)
	local g = sidebars.geometry(player)
	if not g then
		return
	end
	local W, H = g.w, math.ceil(g.sh)
	-- the bars, under everything else on the HUD (over the world)
	ids.left = add(player, {type = "image", position = LEFT, alignment = {x = 1, y = 1},
		offset = {x = 0, y = 0}, z_index = -100,
		text = ("[fill:%dx%d:%s^[fill:%dx%d:%d,0:%s"):format(W, H, BAR, EDGE_W, H, W - EDGE_W, EDGE)})
	ids.right = add(player, {type = "image", position = RIGHT, alignment = {x = -1, y = 1},
		offset = {x = 0, y = 0}, z_index = -100,
		text = ("[fill:%dx%d:%s^[fill:%dx%d:0,0:%s"):format(W, H, BAR, EDGE_W, H, EDGE)})
	-- the equipment panel and its slots
	local e = g.equip
	ids.panel = add(player, {type = "image", position = LEFT, alignment = {x = 1, y = 1},
		offset = {x = e.x, y = e.y}, z_index = -90,
		text = ("[fill:%dx%d:%s"):format(e.w, e.h, PANEL)})
	local S = e.slot
	local frame = ("[fill:%dx%d:%s^[fill:%dx%d:3,3:%s"):format(S, S, SLOT_FRAME, S - 6, S - 6, SLOT_INNER)
	for _, slot in ipairs(nhv.ui.EQUIP or {}) do
		local x = e.x + 6 + slot.col * (S + e.col_gap)
		local y = math.floor(e.y + 6 + slot.row * e.step)
		-- (the weapons are the hotbar's, side by side under the panel; the
		-- quiver's box under them, bigger, no caption)
		local size, caption = S, slot.short
		if slot.weapon then
			goto next_slot
		elseif slot.quiver then
			x, y, size, caption = g.quiver.x, g.quiver.y, g.quiver.size, ""
		end
		slot_ids[slot.id] = {
			bg = add(player, {type = "image", position = LEFT, alignment = {x = 1, y = 1},
				offset = {x = x, y = y}, z_index = -80,
				text = size == S and frame or ("[fill:%dx%d:%s^[fill:%dx%d:3,3:%s"):format(size, size,
					SLOT_FRAME, size - 6, size - 6, SLOT_INNER)}),
			icon = add(player, {type = "image", position = LEFT, alignment = {x = 0, y = 0},
				offset = {x = x + size / 2, y = y + size / 2}, z_index = -79, text = "blank.png",
				scale = {x = (size - 10) / 16, y = (size - 10) / 16}}),
			label = add(player, {type = "text", position = LEFT, alignment = {x = 1, y = 1},
				offset = {x = x, y = y + size + 1}, z_index = -79, number = 0xFFFFFF,
				text = caption}),
		}
		::next_slot::
	end
	-- the ailments' box (hud.lua writes them in it)
	local a = g.ailments
	ids.ailments = add(player, {type = "image", position = LEFT, alignment = {x = 1, y = 1},
		offset = {x = a.x, y = a.y}, z_index = -90, text = ("[fill:%dx%d:#000000"):format(a.w, a.h)})
	-- the dialogue box and the ground's box: black, always there
	for _, key in ipairs({"dialog", "items"}) do
		local b = g[key]
		ids[key] = add(player, {type = "image", position = RIGHT, alignment = {x = 1, y = 1},
			offset = {x = b.x, y = b.y}, z_index = -90,
			text = ("[fill:%dx%d:#000000"):format(b.w, math.max(1, b.h))})
	end
	sidebars.refresh(player, nh.snap and nh.snap.inventory)
end

nh.on_snapshot(function(snap)
	local player = nhv.player.get()
	if snap and player then
		sidebars.refresh(player, snap.inventory)
	end
end)

-- (the window's size known, or changed: everything placed again for it)
local size_seen, size_t = nil, 0
core.register_globalstep(function(dtime)
	size_t = size_t + dtime
	if size_t < 1 then
		return
	end
	size_t = 0
	local player = nhv.player.get()
	if not player then
		return
	end
	local info = core.get_player_window_information(player:get_player_name())
	local sig = info and info.size and (info.size.x .. "x" .. info.size.y .. "@" .. (info.real_hud_scaling or 0))
	if sig and sig ~= size_seen then
		size_seen = sig
		-- (also the first time it's known: on joining it isn't yet)
		if sidebars.on() then
			nhv.theme.apply(player)
		end
	end
end)

core.register_on_leaveplayer(function()
	ids, slot_ids, shown, size_seen = {}, {}, {}, nil
end)

return sidebars
