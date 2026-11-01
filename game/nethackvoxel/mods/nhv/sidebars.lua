-- Side bars (Options > Graphics > HUD layout "Side bars"; the setting
-- nhv_hud_layout = sidebars): the HUD round the view instead of over it,
-- an old dungeon crawler's screen - the view in the middle, a bar each side
-- (the world under them hidden):
--   left:  your portrait, HP and Pw, your numbers (gold, AC, experience,
--          the stats, alignment and turns), what you wear (the inventory's
--          equipment slots), your two weapons side by side (the hotbar's,
--          hotbar.lua) and your quiver under them, and your ailments (the
--          status line's conditions, each in its colour)
--   right: the map and the level; a small box of what's said (speech.lua),
--          speakers' names in yellow, the newest at the bottom (the
--          speech bubbles over heads stay); your inventory, scrolled with
--          the mouse wheel (the big map's scroll comes first, when it's
--          open and wider than the screen); what's on the ground where you
--          stand (hud.lua), "F  Pick up" at the bottom of its box; and the
--          keys' hints (X Search, Q Invoke, P Pay, G Enhance: hotbar.lua,
--          hud.lua) at the bottom
-- The chat console (T, the command line) opens over the view only.
-- The action keys stay along the bottom of the view, the messages and the
-- compass along its top. Each bar is as wide as the
-- corner map needs (Map size), at most a quarter of the screen (the map
-- made smaller to fit); everything in them sized to the screen's height.

local U = nhv.util
local nh = nhv.nh

local sidebars = {}
nhv.sidebars = sidebars

local BAR = "ui_bricksidebar.png" -- the bars: its bricks across them
local BRICK = 32           -- (its size)
local EDGE = "#000000"    -- their edge on the view's side
local EDGE_W = 3
local PANEL = "#1A1A20"   -- the equipment panel
local SLOT_FRAME = "#50505A"
local SLOT_INNER = "#141418"
local PAD = 8
sidebars.STAT_LINES = 3    -- the stats' lines (hud.lua's show_status)
sidebars.AILMENT_LINES = 4 -- ailments the box shows
sidebars.HINT_LINES = 4    -- the keys' hints at the bottom right
local DIALOG_LINES = 4     -- what's said: its box's lines
local HERE_LINES = 6       -- what's on the ground: its box's lines (with F)

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
	-- right: the map, the level under it; what's said under that; the hints
	-- at the bottom, the ground's box over them; the inventory between
	g.map = {x = -(PAD + math.floor((inner - U.COLNO * s) / 2)), y = PAD}
	g.level_y = PAD + U.ROWNO * s + 4
	local top = g.level_y + line_h + 6
	g.hints_y = sh - PAD - sidebars.HINT_LINES * line_h
	local dh = DIALOG_LINES * line_h + 12
	g.log = {x = -(w - PAD), y = top, w = inner, h = dh}
	local hh = HERE_LINES * line_h + 12
	g.here = {x = -(w - PAD), y = g.hints_y - 8 - hh, w = inner, h = hh}
	-- (lines of the list the ground's box has room for, over "F  Pick up")
	g.here_max = HERE_LINES - 1
	local iy = top + dh + 8
	g.inv = {x = -(w - PAD), y = iy, w = inner, h = math.max(line_h + 12, g.here.y - 8 - iy)}
	g.inv_row = line_h + 4
	g.inv_rows = math.max(1, math.floor((g.inv.h - 12) / g.inv_row))
	g.log_rows = math.max(1, math.floor((g.log.h - 12) / line_h))
	-- (characters a line in a box)
	g.box_chars = math.max(8, math.floor((inner - 12) / char_w))
	g.k = k
	return g
end

-- ---------------------------------------------------------------- drawing
local ids = {}       -- element ids: bars, panel, boxes, slots
local slot_ids = {}  -- equipment slot id -> {icon=}
local shown = {}     -- equipment slot id -> texture shown
local log_rows = {}  -- the log's lines: {id=, text=, color=}
local inv_rows = {}  -- the inventory's lines: {icon=, text=, shown_icon=, shown_text=}
local inv_scroll = 0 -- (items scrolled past)

local function remove(player)
	for _, id in pairs(ids) do
		player:hud_remove(id)
	end
	for _, s in pairs(slot_ids) do
		player:hud_remove(s.bg)
		player:hud_remove(s.icon)
		player:hud_remove(s.label)
	end
	for _, row in ipairs(log_rows) do
		player:hud_remove(row.id)
	end
	for _, row in ipairs(inv_rows) do
		player:hud_remove(row.icon)
		player:hud_remove(row.text)
	end
	ids, slot_ids, shown, log_rows, inv_rows = {}, {}, {}, {}, {}
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
		if core.nhv_console_margins then
			core.nhv_console_margins(0, 0)
		end
		return
	end
	local W, H = g.w, math.ceil(g.sh)
	-- the bars, under everything else on the HUD (over the world): the
	-- bricks, the left bar's from its left edge, the right's from its right
	-- (each the mirror of the other's), a black edge on the view's side
	local function bricks(from_right)
		local t = {("[combine:%dx%d"):format(W, H)}
		for y = 0, H - 1, BRICK do
			for x = 0, W - 1, BRICK do
				t[#t + 1] = (":%d,%d=%s"):format(from_right and W - BRICK - x or x, y, BAR)
			end
		end
		return table.concat(t)
	end
	ids.left = add(player, {type = "image", position = LEFT, alignment = {x = 1, y = 1},
		offset = {x = 0, y = 0}, z_index = -100,
		text = ("%s^[fill:%dx%d:%d,0:%s"):format(bricks(false), EDGE_W, H, W - EDGE_W, EDGE)})
	ids.right = add(player, {type = "image", position = RIGHT, alignment = {x = -1, y = 1},
		offset = {x = 0, y = 0}, z_index = -100,
		text = ("%s^[fill:%dx%d:0,0:%s"):format(bricks(true), EDGE_W, H, EDGE)})
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
	-- the boxes: what's said, the inventory (its rows, and a mark of how
	-- far down it's scrolled), what's on the ground (sidebars.relayout)
	ids.log = add(player, {type = "image", position = RIGHT, alignment = {x = 1, y = 1},
		offset = {x = 0, y = 0}, z_index = -90, text = "blank.png"})
	ids.inv = add(player, {type = "image", position = RIGHT, alignment = {x = 1, y = 1},
		offset = {x = g.inv.x, y = g.inv.y}, z_index = -90,
		text = ("[fill:%dx%d:#000000"):format(g.inv.w, g.inv.h)})
	ids.inv_mark = add(player, {type = "image", position = RIGHT, alignment = {x = 1, y = 1},
		offset = {x = g.inv.x + g.inv.w - 4, y = g.inv.y}, z_index = -89, text = "blank.png"})
	local icon = g.inv_row - 4
	for r = 1, g.inv_rows do
		local y = g.inv.y + 6 + (r - 1) * g.inv_row
		inv_rows[r] = {
			icon = add(player, {type = "image", position = RIGHT, alignment = {x = 1, y = 1},
				offset = {x = g.inv.x + 6, y = y}, z_index = -88, text = "blank.png",
				scale = {x = icon / 16, y = icon / 16}}),
			text = add(player, {type = "text", position = RIGHT, alignment = {x = 1, y = 1},
				offset = {x = g.inv.x + 10 + icon, y = y + 2}, z_index = -88, number = 0xFFFFFF, text = ""}),
		}
	end
	ids.here = add(player, {type = "image", position = RIGHT, alignment = {x = 1, y = 1},
		offset = {x = 0, y = 0}, z_index = -90, text = "blank.png"})
	sidebars.relayout(player)
	sidebars.refresh(player, nh.snap and nh.snap.inventory)
	sidebars.render_inventory(player)
	-- (the chat console kept off the bars)
	if core.nhv_console_margins then
		local m = math.floor(g.w * g.k + 0.5)
		core.nhv_console_margins(m, m)
	end
end

-- the right bar's boxes placed again: what's said, what's on the ground
-- - the log's lines made for its height
function sidebars.relayout(player)
	local g = sidebars.geometry(player)
	if not (g and ids.log) then
		return
	end
	player:hud_change(ids.log, "offset", {x = g.log.x, y = g.log.y})
	player:hud_change(ids.log, "text", ("[fill:%dx%d:#000000"):format(g.log.w, math.max(1, g.log.h)))
	player:hud_change(ids.here, "offset", {x = g.here.x, y = g.here.y})
	player:hud_change(ids.here, "text", ("[fill:%dx%d:#000000"):format(g.here.w, math.max(1, g.here.h)))
	if #log_rows ~= g.log_rows then
		for _, row in ipairs(log_rows) do
			player:hud_remove(row.id)
		end
		log_rows = {}
		for r = 1, g.log_rows do
			log_rows[r] = {id = add(player, {type = "text", position = RIGHT, alignment = {x = 1, y = 1},
				offset = {x = g.log.x + 6, y = g.log.y + 6 + (r - 1) * g.line_h}, z_index = 31,
				number = 0xFFFFFF, text = "", style = nhv.hud.message_style()})}
		end
	else
		for r, row in ipairs(log_rows) do
			player:hud_change(row.id, "offset", {x = g.log.x + 6, y = g.log.y + 6 + (r - 1) * g.line_h})
		end
	end
	sidebars.render_log(player)
	if nhv.hud.place_here then
		nhv.hud.place_here(player)
	end
end

-- (a line of fields spread evenly across n characters: the stats)
function sidebars.spread(fields, n)
	local total = 0
	for _, f in ipairs(fields) do
		total = total + #f
	end
	local gaps = #fields - 1
	if gaps < 1 then
		return fields[1] or ""
	end
	local space = math.max(gaps, n - total)
	local out = {}
	for i, f in ipairs(fields) do
		out[#out + 1] = f
		if i <= gaps then
			-- (the leftover spaces to the first gaps)
			local k = math.floor(space / gaps) + ((i <= space % gaps) and 1 or 0)
			out[#out + 1] = (" "):rep(k)
		end
	end
	return table.concat(out)
end

-- (characters across the left bar, for the stats)
function sidebars.stat_chars(g)
	return math.max(10, math.floor((g.w - 2 * g.pad - 4) / g.char_w))
end

-- ---------------------------------------------------------------- inventory
-- what you carry, a line each (its picture, its letter and name), from
-- where it's scrolled to
function sidebars.render_inventory(player)
	player = player or nhv.player.get()
	local g = player and #inv_rows > 0 and sidebars.geometry(player)
	if not g then
		return
	end
	local inv = (nh.snap and nh.snap.inventory) or {}
	inv_scroll = math.max(0, math.min(inv_scroll, #inv - #inv_rows))
	local most = math.max(6, g.box_chars - 3)
	for r, row in ipairs(inv_rows) do
		local o = inv[inv_scroll + r]
		local icon = o and nhv_tiles.texture(o.tile) or "blank.png"
		local text = o and (o.invlet .. " - " .. o.name) or ""
		if #text > most then
			text = text:sub(1, most - 2) .. ".."
		end
		if row.shown_icon ~= icon then
			row.shown_icon = icon
			player:hud_change(row.icon, "text", icon)
		end
		if row.shown_text ~= text then
			row.shown_text = text
			player:hud_change(row.text, "text", text)
		end
	end
	-- (the mark: as tall as the part shown, where it is; none when all is)
	if ids.inv_mark then
		local tex = "blank.png"
		local off = {x = g.inv.x + g.inv.w - 4, y = g.inv.y}
		if #inv > #inv_rows then
			local h = math.max(6, math.floor(g.inv.h * #inv_rows / #inv))
			off.y = g.inv.y + math.floor((g.inv.h - h) * inv_scroll / (#inv - #inv_rows))
			tex = ("[fill:3x%d:#808080"):format(h)
		end
		player:hud_change(ids.inv_mark, "text", tex)
		player:hud_change(ids.inv_mark, "offset", off)
	end
end

-- the mouse wheel (notches: up positive): the inventory up or down
function sidebars.scroll_inventory(notches)
	if not (sidebars.on() and #inv_rows > 0) then
		return
	end
	inv_scroll = inv_scroll - notches * 3
	sidebars.render_inventory()
end

-- ---------------------------------------------------------------- the log
-- NetHack's messages and what's said, in order: {label=, text=, color=}
-- (a spoken line's text grows as it's said: speech.lua changes it and
-- draws the log again)
local log = {}
local LOG_MAX = 200
local MSG_COLOR, LABEL_COLOR = 0xFFFFE0, 0xFFD040

function sidebars.log_add(entry)
	log[#log + 1] = entry
	if #log > LOG_MAX then
		table.remove(log, 1)
	end
	sidebars.render_log()
	return entry
end

-- (words wrapped to n characters a line)
local function wrap(text, n)
	local out = {}
	for para in (text .. "\n"):gmatch("(.-)\n") do
		local line = ""
		for word in para:gmatch("%S+") do
			while #word > n do
				if line ~= "" then
					out[#out + 1] = line
					line = ""
				end
				out[#out + 1] = word:sub(1, n)
				word = word:sub(n + 1)
			end
			if line == "" then
				line = word
			elseif #line + 1 + #word <= n then
				line = line .. " " .. word
			else
				out[#out + 1] = line
				line = word
			end
		end
		if line ~= "" then
			out[#out + 1] = line
		end
	end
	return out
end

-- the log's last lines, the newest at the bottom
function sidebars.render_log(player)
	player = player or nhv.player.get()
	local g = player and #log_rows > 0 and sidebars.geometry(player)
	if not g then
		return
	end
	local lines = {}
	for k = #log, 1, -1 do
		local e = log[k]
		local block = {}
		if e.label then
			block[#block + 1] = {e.label .. ":", LABEL_COLOR}
		end
		for _, l in ipairs(wrap(e.text or "", g.box_chars)) do
			block[#block + 1] = {l, e.color or MSG_COLOR}
		end
		for j = #block, 1, -1 do
			table.insert(lines, 1, block[j])
		end
		if #lines >= #log_rows then
			break
		end
	end
	local start = #lines - #log_rows
	for r, row in ipairs(log_rows) do
		local ln = lines[start + r]
		local text, color = ln and ln[1] or "", ln and ln[2] or MSG_COLOR
		if row.text ~= text then
			row.text = text
			player:hud_change(row.id, "text", text)
		end
		if row.color ~= color then
			row.color = color
			player:hud_change(row.id, "number", color)
		end
	end
end

nh.on_snapshot(function(snap)
	local player = nhv.player.get()
	if snap and player then
		sidebars.refresh(player, snap.inventory)
		sidebars.render_inventory(player)
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
	ids, slot_ids, shown, size_seen, log_rows, inv_rows, inv_scroll = {}, {}, {}, nil, {}, {}, 0
	log = {}
	if core.nhv_console_margins then
		core.nhv_console_margins(0, 0)
	end
end)

return sidebars
