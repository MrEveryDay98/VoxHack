-- Graphics options (the Graphics button in the inventory screen):
--   * sprites drawn extruded (voxel models) or flat
--   * a lower render resolution for a retro look (Luanti's "undersampling":
--     the world is drawn at 1/N size and scaled up with sharp pixels; the
--     HUD and menus stay full resolution)
-- Both apply immediately and are remembered in the settings.

local graphics = {}
nhv.graphics = graphics

local E = core.formspec_escape
local SPRITES = {"Extruded (3D)", "Flat"}
local RES = {
	{1, "Full"}, {2, "1/2"}, {3, "1/3"}, {4, "1/4 (retro)"}, {6, "1/6"}, {8, "1/8 (very chunky)"},
}

local function res_index()
	local u = tonumber(core.settings:get("undersampling")) or 1
	for i, r in ipairs(RES) do
		if r[1] == u then
			return i
		end
	end
	return 1
end

function graphics.formspec()
	local res_labels = {}
	for i, r in ipairs(RES) do
		res_labels[i] = E(r[2])
	end
	return table.concat({
		"formspec_version[6]size[9,5.4]",
		"bgcolor[#000000C0;true]style_type[button;bgcolor=#303040]",
		"style_type[label;textcolor=#E0E0E0]",
		"label[0.5,0.6;", core.colorize("#FFD080", "Graphics"), "]",
		"label[0.5,1.4;Sprites]",
		"dropdown[3.6,1.0;5,0.8;sprites;", table.concat(SPRITES, ","), ";",
		nhv_tiles.flat() and 2 or 1, ";true]",
		"label[0.5,2.4;Render resolution]",
		"dropdown[3.6,2.0;5,0.8;res;", table.concat(res_labels, ","), ";", res_index(), ";true]",
		"label[0.5,3.4;", core.colorize("#A0A0A0",
			E("Lower resolutions draw the world with big, sharp pixels.")), "]",
		"label[0.5,3.8;", core.colorize("#A0A0A0", E("The HUD and menus stay sharp.")), "]",
		"button_exit[3.25,4.4;2.5,0.8;close;Done]",
	})
end

function graphics.show(player)
	core.show_formspec(player:get_player_name(), "nhv:graphics", graphics.formspec())
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname == "" and fields.graphics then
		graphics.show(player)
		return true
	end
	if formname ~= "nhv:graphics" then
		return false
	end
	local changed = false
	local s = tonumber(fields.sprites)
	if s and (s == 2) ~= nhv_tiles.flat() then
		core.settings:set_bool("nhv_flat_sprites", s == 2)
		nhv.mobs.refresh_sizes()
		changed = true
	end
	local r = tonumber(fields.res)
	if r and RES[r] and r ~= res_index() then
		core.settings:set("undersampling", tostring(RES[r][1]))
		changed = true
	end
	if changed then
		core.settings:write()
	end
	return true
end)

return graphics
