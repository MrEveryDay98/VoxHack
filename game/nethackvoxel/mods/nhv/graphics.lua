-- Options (the Options button in the inventory screen):
--   * time: Superhot (time moves when you move) or real time
--   * interface style: Retro (pixel font, old PC boxes) or Modern
--   * HUD size, menu size and map size
--   * sprites drawn extruded (voxel models) or flat
--   * ASCII mode: the world as NetHack's characters (ascii.lua; F4)
--   * a lower render resolution for a retro look (Luanti's "undersampling":
--     the world is drawn at 1/N size and scaled up with sharp pixels; the
--     HUD and menus stay full resolution)
--   * sharp or smoothed distant textures (Luanti's "mip_map": mipmaps blur
--     far-away textures to stop them shimmering)
--   * retro mode (the VoxHack engine's nhv_retro): the whole game - world,
--     HUD, menus - a small screen (640x480, 800x600, 1024x768) scaled up
--     into the window with sharp pixels (as big as fits, or by whole
--     numbers), in VGA's 256 colours or EGA's 16 (dithered or not), the
--     light in steps. Its HUD, menu, text and map sizes are fixed, made for
--     it (the window's are kept for coming back).
-- The list scrolls (where it was is kept as it's redrawn).
-- All apply immediately and are remembered in the settings.

local graphics = {}
nhv.graphics = graphics

local E = core.formspec_escape
local theme = nhv.theme
local STYLE = {"Retro", "Modern"}
local TIME = {"Superhot", "Real time"}
local SPRITES = {"Extruded (3D)", "Flat"}
local ASCII = {"Off", "On (F4)"}
local DISTANT = {"Sharp", "Smoothed (blurry)"}
local SHADOWS = {"On", "Off"}
local SHADOW_OPACITY = {{20, "20%"}, {40, "40%"}, {60, "60%"}, {80, "80%"}, {100, "100% (solid)"}}
local DRAWN = {"Kept", "Removed (after a restart)"}
-- recording demos (the VoxHack engine's nhv_demo: each session from its
-- start, to engine/demos; played with Launchers\Play Demo.bat)
local DEMOS = {"Off", "On (next start)"}
local RETRO = {"Off", "On"}
local RETRO_RES = {"640x480", "800x600", "1024x768"}
local RETRO_PALETTE = {{"vga", "VGA (256 colours)"}, {"ega", "EGA (16 colours)"}, {"full", "Full colour"}}
local RETRO_DITHER = {{0, "Off"}, {0.5, "Light"}, {1, "Normal"}, {1.6, "Strong"}}
local RETRO_BANDS = {{0, "Smooth"}, {4, "4 steps"}, {6, "6 steps"}, {8, "8 steps"}, {12, "12 steps"}}
local RETRO_SCALE = {"As big as fits", "Whole pixels"}
-- the sizes retro mode fixes (the window's kept for coming back): HUD,
-- menus, text (the pixel font as it is), map - for each of its screens
local SIZES = {"hud_scaling", "gui_scaling", "nhv_text_scale", "nhv_map_scale"}
local RETRO_SIZES = {
	["640x480"] = {0.75, 1, 1, 2}, ["800x600"] = {1, 1, 1, 3}, ["1024x768"] = {1.25, 1, 1, 3},
}
local RES = {
	{1, "Full"}, {2, "1/2"}, {3, "1/3"}, {4, "1/4 (retro)"}, {6, "1/6"}, {8, "1/8 (very chunky)"},
}
local HUD = {{0.75, "Small"}, {1, "Normal"}, {1.25, "Large"}, {1.5, "Larger"}, {2, "Huge"}, {3, "Giant"}}
local MENU = {{0.75, "Small"}, {1, "Normal"}, {1.25, "Large"}, {1.5, "Larger"}, {2, "Huge"}}
-- (the pixel font only has whole steps)
local TEXT_RETRO = {{1, "1x (14 px)"}, {2, "2x (28 px)"}, {3, "3x (42 px)"}, {4, "4x (56 px)"}}
local TEXT_MODERN = {{0.85, "Small"}, {1, "Normal"}, {1.25, "Large"}, {1.5, "Larger"}, {2, "Huge"}}
local function text_list()
	return theme.retro() and TEXT_RETRO or TEXT_MODERN
end
local MAP_ICONS = {"On their squares", "Where they are"}
local MAP = {{0, "Hidden"}, {2, "Small"}, {3, "Normal"}, {4, "Large"}, {5, "Larger"}, {6, "Huge"}}

-- index of the choice nearest the setting's value
local function pick(list, setting, default)
	local v = tonumber(core.settings:get(setting)) or default
	local best, dist = 1, math.huge
	for i, c in ipairs(list) do
		if math.abs(c[1] - v) < dist then
			best, dist = i, math.abs(c[1] - v)
		end
	end
	return best
end

local function labels(list)
	local out = {}
	for i, c in ipairs(list) do
		out[i] = E(c[2])
	end
	return table.concat(out, ",")
end

-- one labelled dropdown row
local function row(y, label, name, items, sel)
	return ("label[0.5,%s;%s]dropdown[6.4,%s;5.6,0.8;%s;%s;%d;true]"):format(
		y + 0.4, E(label), y, name, items, sel)
end

-- a row retro mode decides
local function fixed(y, label)
	return ("label[0.5,%s;%s]label[6.4,%s;%s]"):format(y + 0.4, E(label), y + 0.4,
		theme.dim(E("Fixed in retro mode")))
end

local function choice(list, setting, default)
	local v = core.settings:get(setting) or default
	for i, c in ipairs(list) do
		if (type(c) == "table" and c[1] or c) == v then
			return i
		end
	end
	return 1
end

local function names(list)
	local out = {}
	for i, c in ipairs(list) do
		out[i] = E(type(c) == "table" and c[2] or c)
	end
	return table.concat(out, ",")
end

local VIEW_H = 9.6  -- (the list's visible height)
local scroll = 0     -- (where it's scrolled to, kept as it's redrawn)

function graphics.formspec()
	local retro = core.settings:get_bool("nhv_retro", false)
	local rows = {}
	local y = 0
	local function add(text, h)
		rows[#rows + 1] = text
		y = y + (h or 0.9)
	end
	add(row(y, "Time", "time", table.concat(TIME, ","), nhv.clock.realtime() and 2 or 1))
	add("label[0.5," .. (y + 0.5) .. ";" .. theme.dim("Graphics") .. "]", 1.0)
	add(row(y, "Interface", "style", table.concat(STYLE, ","), theme.retro() and 1 or 2))
	if retro then
		add(fixed(y, "HUD size"))
		add(fixed(y, "Menu size"))
		add(fixed(y, "Text size"))
		add(fixed(y, "Map size"))
	else
		add(row(y, "HUD size", "hud", labels(HUD), pick(HUD, "hud_scaling", 1)))
		add(row(y, "Menu size", "menu", labels(MENU), pick(MENU, "gui_scaling", 1)))
		add(row(y, "Text size", "text", labels(text_list()), pick(text_list(), "nhv_text_scale", 1)))
		add(row(y, "Map size", "map", labels(MAP), pick(MAP, "nhv_map_scale", 3)))
	end
	add(row(y, "Map icons", "map_icons", table.concat(MAP_ICONS, ","), nhv.hud.exact_icons() and 2 or 1))
	add(row(y, "Sprites", "sprites", table.concat(SPRITES, ","),
		core.settings:get_bool("nhv_flat_sprites", false) and 2 or 1))
	add(row(y, "ASCII mode", "ascii", table.concat(ASCII, ","), core.settings:get_bool("nhv_ascii", false) and 2 or 1))
	if retro then
		add(fixed(y, "Render resolution"))
	else
		add(row(y, "Render resolution", "res", labels(RES), pick(RES, "undersampling", 1)))
	end
	add(row(y, "Distant textures", "distant", table.concat(DISTANT, ","),
		core.settings:get_bool("mip_map", false) and 2 or 1))
	add(row(y, "Shadows", "shadows", table.concat(SHADOWS, ","), core.settings:get_bool("nhv_shadows", false) and 1 or 2))
	add(row(y, "Shadow opacity", "shadow_opacity", labels(SHADOW_OPACITY), pick(SHADOW_OPACITY, "nhv_shadow_opacity", 60)))
	add(row(y, "Shadows drawn on sprites", "drawn", table.concat(DRAWN, ","),
		core.settings:get_bool("nhv_sprite_shadows", true) and 1 or 2))
	add(row(y, "Record demos", "demos", table.concat(DEMOS, ","),
		core.settings:get_bool("nhv_demo_record", false) and 2 or 1))
	add("label[0.5," .. (y + 0.5) .. ";" .. theme.dim("Retro mode: a small old screen, scaled up") .. "]", 1.0)
	add(row(y, "Retro mode", "retro", table.concat(RETRO, ","), retro and 2 or 1))
	add(row(y, "Resolution", "retro_res", names(RETRO_RES), choice(RETRO_RES, "nhv_retro_res", "800x600")))
	add(row(y, "Colours", "retro_palette", names(RETRO_PALETTE), choice(RETRO_PALETTE, "nhv_retro_palette", "vga")))
	add(row(y, "Dithering", "retro_dither", labels(RETRO_DITHER), pick(RETRO_DITHER, "nhv_retro_dither", 1)))
	add(row(y, "Light", "retro_bands", labels(RETRO_BANDS), pick(RETRO_BANDS, "nhv_retro_bands", 6)))
	add(row(y, "Scaling", "retro_scale", names(RETRO_SCALE),
		core.settings:get_bool("nhv_retro_whole", false) and 2 or 1))
	-- (scrollbar steps of a tenth of a unit)
	local max = math.max(0, math.ceil((y - VIEW_H) * 10))
	scroll = math.min(scroll, max)
	return table.concat({
		theme.head(13, 12),
		"label[0.5,0.6;", theme.title("Options"), "]",
		-- (the buttons first: a list opened from a dropdown near the bottom
		-- is drawn over them, not under)
		"button[0.5,11.0;5.6,0.8;guide;Controls & guide...]",
		"button_exit[6.4,11.0;5.6,0.8;close;Done]",
		("scrollbaroptions[max=%d;smallstep=9;largestep=45]"):format(max),
		("scrollbar[12.3,1.0;0.4,%s;vertical;scroll;%d]"):format(VIEW_H, scroll),
		("scroll_container[0,1.0;12.2,%s;scroll;vertical;0.1]"):format(VIEW_H),
		table.concat(rows),
		"scroll_container_end[]",
	})
end

function graphics.show(player)
	core.show_formspec(player:get_player_name(), "nhv:graphics", graphics.formspec())
end

-- retro mode on or off: its sizes fixed (made for its small screen), the
-- window's kept for coming back
local function retro_sizes(player)
	local sizes = RETRO_SIZES[core.settings:get("nhv_retro_res") or ""] or RETRO_SIZES["800x600"]
	for i, setting in ipairs(SIZES) do
		core.settings:set(setting, tostring(sizes[i]))
	end
	theme.apply(player)
	nhv.hud.place_map(player)
end

function graphics.set_retro(player, on)
	if on then
		local kept = {}
		for i, setting in ipairs(SIZES) do
			kept[i] = core.settings:get(setting) or ""
		end
		core.settings:set("nhv_sizes_window", table.concat(kept, "|"))
	else
		local saved = (core.settings:get("nhv_sizes_window") or ""):split("|", true)
		for i, setting in ipairs(SIZES) do
			if saved[i] and saved[i] ~= "" then
				core.settings:set(setting, saved[i])
			end
		end
	end
	core.settings:set_bool("nhv_retro", on) -- (the engine switches at the next frame)
	nhv.hud.place_compass(player)
	if on then
		retro_sizes(player)
	else
		theme.apply(player)
		nhv.hud.place_map(player)
	end
end

-- store a numeric choice; true if it changed
local function set_num(list, idx, setting, default)
	idx = tonumber(idx)
	if not idx or not list[idx] or idx == pick(list, setting, default) then
		return false
	end
	core.settings:set(setting, tostring(list[idx][1]))
	return true
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname == "" and fields.graphics then
		graphics.show(player)
		return true
	end
	if formname ~= "nhv:graphics" then
		return false
	end
	if fields.guide then
		nhv.guide.from_options = true
		nhv.guide.show(player, 1)
		return true
	end
	if fields.scroll then
		local ev = core.explode_scrollbar_event(fields.scroll)
		if ev.type == "CHG" or ev.type == "VAL" then
			scroll = ev.value
		end
	end
	local changed, reshow = false, false
	local tm = tonumber(fields.time)
	if tm and (tm == 2) ~= nhv.clock.realtime() then
		core.settings:set("nhv_time_mode", tm == 2 and "realtime" or "superhot")
		changed = true
	end
	local st = tonumber(fields.style)
	local restyled = st and (st == 1) ~= theme.retro()
	if restyled then
		core.settings:set("nhv_interface", st == 1 and "retro" or "modern")
		theme.apply(player)
		changed, reshow = true, true
	end
	if set_num(HUD, fields.hud, "hud_scaling", 1) then
		theme.apply(player) -- (hotbar and meters refit their text)
		changed = true
	end
	-- (the text size list differs between styles: skip it on a style change)
	if not restyled and set_num(text_list(), fields.text, "nhv_text_scale", 1) then
		theme.apply(player)
		changed, reshow = true, true
	end
	if set_num(MENU, fields.menu, "gui_scaling", 1) then
		changed, reshow = true, true
	end
	if set_num(MAP, fields.map, "nhv_map_scale", 3) then
		nhv.hud.place_map(player)
		changed = true
	end
	local mi = tonumber(fields.map_icons)
	if mi and (mi == 2) ~= nhv.hud.exact_icons() then
		core.settings:set_bool("nhv_map_exact", mi == 2)
		nhv.hud.place_map(player) -- (the squares redrawn with or without them)
		changed = true
	end
	local s = tonumber(fields.sprites)
	if s and (s == 2) ~= core.settings:get_bool("nhv_flat_sprites", false) then
		core.settings:set_bool("nhv_flat_sprites", s == 2)
		nhv.mobs.refresh_sizes()
		changed = true
	end
	local a = tonumber(fields.ascii)
	if a and (a == 2) ~= core.settings:get_bool("nhv_ascii", false) then
		core.settings:set_bool("nhv_ascii", a == 2)
		nhv.ascii.redraw()
		changed = true
	end
	local d = tonumber(fields.distant)
	if d and (d == 2) ~= core.settings:get_bool("mip_map", false) then
		core.settings:set_bool("mip_map", d == 2)
		nhv.mobs.refresh_sizes() -- sprites pick up the new filtering
		changed = true
	end
	if set_num(RES, fields.res, "undersampling", 1) then
		changed = true
	end
	local sh = tonumber(fields.shadows)
	if sh and (sh == 1) ~= core.settings:get_bool("nhv_shadows", false) then
		core.settings:set_bool("nhv_shadows", sh == 1) -- (shadows.lua, at once)
		changed = true
	end
	local dr = tonumber(fields.drawn)
	if dr and (dr == 1) ~= core.settings:get_bool("nhv_sprite_shadows", true) then
		-- (the sprites' sheet: nhv_tiles reads it when the game starts)
		core.settings:set_bool("nhv_sprite_shadows", dr == 1)
		changed = true
	end
	local dm = tonumber(fields.demos)
	if dm and (dm == 2) ~= core.settings:get_bool("nhv_demo_record", false) then
		-- (the engine starts recording as a session begins: from the next one)
		core.settings:set_bool("nhv_demo_record", dm == 2)
		changed = true
	end
	if set_num(SHADOW_OPACITY, fields.shadow_opacity, "nhv_shadow_opacity", 60) then
		changed = true -- (shadows.lua redraws them at once)
	end
	local rm = tonumber(fields.retro)
	if rm and (rm == 2) ~= core.settings:get_bool("nhv_retro", false) then
		graphics.set_retro(player, rm == 2)
		changed, reshow = true, true
	end
	-- (the rest of retro mode: the engine takes them at once)
	local rr = tonumber(fields.retro_res)
	if rr and RETRO_RES[rr] and RETRO_RES[rr] ~= core.settings:get("nhv_retro_res") then
		core.settings:set("nhv_retro_res", RETRO_RES[rr])
		if core.settings:get_bool("nhv_retro", false) then
			retro_sizes(player) -- (the sizes made for that screen)
		end
		changed, reshow = true, true -- (redrawn for the new screen)
	end
	local rp = tonumber(fields.retro_palette)
	if rp and RETRO_PALETTE[rp] and RETRO_PALETTE[rp][1] ~= core.settings:get("nhv_retro_palette") then
		core.settings:set("nhv_retro_palette", RETRO_PALETTE[rp][1])
		changed = true
	end
	if set_num(RETRO_DITHER, fields.retro_dither, "nhv_retro_dither", 1) then
		changed = true
	end
	if set_num(RETRO_BANDS, fields.retro_bands, "nhv_retro_bands", 6) then
		changed = true
	end
	local rs = tonumber(fields.retro_scale)
	if rs and (rs == 2) ~= core.settings:get_bool("nhv_retro_whole", false) then
		core.settings:set_bool("nhv_retro_whole", rs == 2)
		changed = true
	end

	if changed then
		core.settings:write()
	end
	if reshow and not fields.quit then
		graphics.show(player) -- (redrawn in the new style / size)
	elseif (fields.quit or fields.close) and nhv.title then
		nhv.title.back_from(player) -- (opened from the title screen: back to it)
	end
	return true
end)

return graphics
