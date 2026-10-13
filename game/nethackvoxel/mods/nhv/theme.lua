-- Interface style and sizes (set in Inventory > Graphics):
--   * "Retro" (old PC style: NetHack's own IBM PC pixel font, bevelled grey
--     boxes, the 16-colour palette) or "Modern" (Luanti's font and look)
--   * HUD size (Luanti's "hud_scaling"), menu size ("gui_scaling"), text
--     size ("nhv_text_scale": the font size, in menus and on the HUD) and
--     map size (the corner map; the big map fits the window)
-- Every screen gets the style through the player's formspec prepend;
-- screens built with theme.head() get it as well.

local theme = {}
nhv.theme = theme

local FONT = core.get_modpath("nhv") .. DIR_DELIM .. "fonts" .. DIR_DELIM .. "nhv_retro.ttf"
local FONT_PX = 14 -- the font's pixel height: sizes snap to multiples of it

function theme.retro()
	return core.settings:get("nhv_interface") ~= "modern"
end

local RETRO = table.concat({
	"bgcolor[#000000A0;true]",
	"background9[0,0;0,0;nhv_ui_panel.png;true;4]",
	"style_type[button,button_exit,image_button,image_button_exit,item_image_button;border=false;",
	"bgimg=nhv_ui_button.png;bgimg_hovered=nhv_ui_button_hover.png;",
	"bgimg_pressed=nhv_ui_button_pressed.png;bgimg_middle=2;textcolor=#FFFFFF]",
	"style_type[label;textcolor=#AAAAAA]",
	"style_type[field,pwdfield,textarea;textcolor=#FFFFFF]",
	"listcolors[#14141EFF;#0000AAFF;#555555FF;#000000;#FFFFFF]",
})
local MODERN = "bgcolor[#000000C0;true]style_type[button;bgcolor=#303040]"
	.. "style_type[label;textcolor=#E0E0E0]"

-- the style elements every screen starts with
function theme.styles()
	return theme.retro() and RETRO or MODERN
end

-- a screen's opening: version, size and style
function theme.head(w, h)
	return ("formspec_version[6]size[%s,%s]"):format(w, h) .. theme.styles()
end

-- headings and dimmed notes, in the style's colours
function theme.title(text)
	return core.colorize(theme.retro() and "#FFFF55" or "#FFD080", text)
end
function theme.dim(text)
	return core.colorize(theme.retro() and "#55FFFF" or "#A0A0A0", text)
end

-- ---------------------------------------------------------------- font
-- Retro uses the pixel font at whole multiples of its height so it stays
-- sharp; Modern removes those settings (back to Luanti's own font).
-- Text size multiplies the font size: whole steps only with the pixel font.
local MODERN_PX = 16 -- Luanti's default font size

function theme.text_scale()
	local k = tonumber(core.settings:get("nhv_text_scale")) or 1
	if theme.retro() then
		return math.max(1, math.floor(k + 0.01))
	end
	return math.max(0.5, math.min(4, k))
end

local function font_settings()
	local k = theme.text_scale()
	if theme.retro() then
		local px = tostring(FONT_PX * k)
		return {
			font_path = FONT, mono_font_path = FONT, font_size = px, mono_font_size = px,
			font_size_divisible_by = tostring(FONT_PX), mono_font_size_divisible_by = tostring(FONT_PX),
		}
	end
	local px = k ~= 1 and tostring(math.floor(MODERN_PX * k + 0.5)) or nil
	return {font_size = px, mono_font_size = px} -- (nil: Luanti's default)
end
local FONT_KEYS = {"font_path", "mono_font_path", "font_size", "mono_font_size",
	"font_size_divisible_by", "mono_font_size_divisible_by"}

function theme.apply_font()
	local changed = false
	local want_all = font_settings()
	for _, k in ipairs(FONT_KEYS) do
		local want = want_all[k]
		if core.settings:get(k) ~= want then
			if want then
				core.settings:set(k, want)
			else
				core.settings:remove(k)
			end
			changed = true
		end
	end
	if changed then
		core.settings:write()
	end
end

function theme.apply(player)
	theme.apply_font()
	player:set_formspec_prepend(theme.styles())
	if nhv.hotbar and nhv.hotbar.rebuild then
		nhv.hotbar.rebuild(player) -- (slots sized for the text)
	end
end

core.register_on_joinplayer(function(player)
	-- (the game folder may have moved since: the font path is set each time)
	theme.apply(player)
end)

return theme
