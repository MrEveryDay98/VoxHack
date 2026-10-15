-- Options (the Options button in the inventory screen):
--   * time: Superhot (time moves when you move) or real time
--   * interface style: Retro (pixel font, old PC boxes) or Modern
--   * HUD size, menu size and map size
--   * sprites drawn extruded (voxel models) or flat
--   * a lower render resolution for a retro look (Luanti's "undersampling":
--     the world is drawn at 1/N size and scaled up with sharp pixels; the
--     HUD and menus stay full resolution)
--   * sharp or smoothed distant textures (Luanti's "mip_map": mipmaps blur
--     far-away textures to stop them shimmering)
-- Retro look (second column): a colour palette with dithering (VGA 256 or
-- EGA 16 colours), light in bands, PS1-style warped textures, blocky
-- lighting (Luanti's smooth_lighting; from the next start), darkness
-- closing in (black fog), and a 4:3 screen.
-- All apply immediately (but blocky lighting) and are remembered.

local graphics = {}
nhv.graphics = graphics

local E = core.formspec_escape
local theme = nhv.theme
local STYLE = {"Retro", "Modern"}
local TIME = {"Superhot", "Real time"}
local SPRITES = {"Extruded (3D)", "Flat"}
local DISTANT = {"Sharp", "Smoothed (blurry)"}
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
local MAP = {{0, "Hidden"}, {2, "Small"}, {3, "Normal"}, {4, "Large"}, {5, "Larger"}, {6, "Huge"}}
local PALETTE = {{0, "Off"}, {1, "VGA (256 colours)"}, {2, "EGA (16 colours)"}}
local BANDS = {{0, "Smooth"}, {5, "Banded"}, {3, "Few bands"}}
local WARP = {"Off", "On (PS1 style)"}
local LIGHTING = {"Smooth", "Blocky (from next start)"}
local DARK = {{0, "Off"}, {1, "Far"}, {2, "Near"}}
local SCREEN = {"Full", "4:3"}

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
local function row(y, label, name, items, sel, x)
	x = x or 0
	return ("label[%s,%s;%s]dropdown[%s,%s;5.3,0.8;%s;%s;%d;true]"):format(
		x + 0.5, y + 0.4, E(label), x + 4.2, y, name, items, sel)
end

function graphics.formspec()
	return table.concat({
		theme.head(19.6, 11.2),
		"label[0.5,0.6;", theme.title("Options"), "]",
		row(1.0, "Time", "time", table.concat(TIME, ","), nhv.clock.realtime() and 2 or 1),
		"label[0.5,2.1;", theme.dim("Graphics"), "]",
		row(2.4, "Interface", "style", table.concat(STYLE, ","), theme.retro() and 1 or 2),
		row(3.3, "HUD size", "hud", labels(HUD), pick(HUD, "hud_scaling", 1)),
		row(4.2, "Menu size", "menu", labels(MENU), pick(MENU, "gui_scaling", 1)),
		row(5.1, "Text size", "text", labels(text_list()), pick(text_list(), "nhv_text_scale", 1)),
		row(6.0, "Map size", "map", labels(MAP), pick(MAP, "nhv_map_scale", 3)),
		row(6.9, "Sprites", "sprites", table.concat(SPRITES, ","), nhv_tiles.flat() and 2 or 1),
		row(7.8, "Render resolution", "res", labels(RES), pick(RES, "undersampling", 1)),
		row(8.7, "Distant textures", "distant", table.concat(DISTANT, ","),
			core.settings:get_bool("mip_map", false) and 2 or 1),
		"label[10.1,2.1;", theme.dim("Retro look"), "]",
		row(2.4, "Palette", "palette", labels(PALETTE), pick(PALETTE, "nhv_palette", 0), 9.6),
		row(3.3, "Light", "bands", labels(BANDS), pick(BANDS, "nhv_light_bands", 0), 9.6),
		row(4.2, "Texture warping", "warp", table.concat(WARP, ","),
			core.settings:get_bool("nhv_affine", false) and 2 or 1, 9.6),
		row(5.1, "Lighting", "lighting", table.concat(LIGHTING, ","),
			core.settings:get_bool("smooth_lighting", true) and 1 or 2, 9.6),
		row(6.0, "Darkness", "dark", labels(DARK), pick(DARK, "nhv_darkness", 0), 9.6),
		row(6.9, "Screen shape", "screen", table.concat(SCREEN, ","),
			core.settings:get("nhv_screen") == "4:3" and 2 or 1, 9.6),
		"button[0.5,10.2;4.4,0.8;nhoptions;NetHack options...]",
		"button_exit[14.7,10.2;4.4,0.8;close;Done]",
	})
end

function graphics.show(player)
	core.show_formspec(player:get_player_name(), "nhv:graphics", graphics.formspec())
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
	if fields.nhoptions then
		nhv.nhopts.show(player)
		return true
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
	local s = tonumber(fields.sprites)
	if s and (s == 2) ~= nhv_tiles.flat() then
		core.settings:set_bool("nhv_flat_sprites", s == 2)
		nhv.mobs.refresh_sizes()
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
	-- retro look
	if set_num(PALETTE, fields.palette, "nhv_palette", 0) then
		changed = true
	end
	if set_num(BANDS, fields.bands, "nhv_light_bands", 0) then
		changed = true
	end
	local w = tonumber(fields.warp)
	if w and (w == 2) ~= core.settings:get_bool("nhv_affine", false) then
		core.settings:set_bool("nhv_affine", w == 2)
		changed = true
	end
	local li = tonumber(fields.lighting)
	if li and (li == 1) ~= core.settings:get_bool("smooth_lighting", true) then
		core.settings:set_bool("smooth_lighting", li == 1)
		changed = true
	end
	if set_num(DARK, fields.dark, "nhv_darkness", 0) then
		nhv.hud.apply_fog(player)
		changed = true
	end
	local sc = tonumber(fields.screen)
	if sc and (sc == 2) ~= (core.settings:get("nhv_screen") == "4:3") then
		core.settings:set("nhv_screen", sc == 2 and "4:3" or "full")
		nhv.hud.update_frame(player)
		changed = true
	end
	if changed then
		core.settings:write()
	end
	if reshow and not fields.quit then
		graphics.show(player) -- (redrawn in the new style / size)
	elseif (fields.quit or fields.close) and nhv.title and nhv.title.open then
		nhv.title.show(player) -- (opened from the title screen: back to it)
	end
	return true
end)

return graphics
