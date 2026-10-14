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

-- how big HUD text is compared with the HUD's own boxes (which grow with
-- the HUD size): boxes made this much bigger fit their text. The pixel
-- font's size is set by Text size alone (14, 28, ... pixels: it can't be
-- scaled by the HUD size's 1.5 etc.); Luanti's font grows with the HUD.
function theme.box_scale()
	local k = theme.text_scale()
	if theme.retro() then
		local hud = tonumber(core.settings:get("hud_scaling")) or 1
		return math.max(1, k / math.max(0.1, hud))
	end
	return k
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
	if nhv.hud and nhv.hud.rebuild_meters then
		nhv.hud.rebuild_meters(player) -- (HP / Pw bars too)
	end
end

core.register_on_joinplayer(function(player)
	-- (the game folder may have moved since: the font path is set each time)
	theme.apply(player)
end)

-- ---------------------------------------------------------------- widening
-- Bigger text (Text size) needs wider boxes: every game menu is stretched
-- sideways by the text size before it's shown. Positions and widths grow;
-- heights stay (text grows sideways, and menus already use most of the
-- screen's height); pictures and inventory slots keep their size, just
-- spread out. (Not in the editors.)

-- elements: "both" = scale x and the width, "pos" = scale x only
local WIDEN = {
	size = "size", button = "both", button_exit = "both", image_button = "both",
	image_button_exit = "both", field = "both", pwdfield = "both", textarea = "both",
	dropdown = "both", box = "both", scroll_container = "both", hypertext = "both",
	textlist = "both", table = "both", background = "both", tooltip = "both",
	scrollbar = "scrollbar", label = "pos", vertlabel = "pos", checkbox = "pos",
	container = "pos", image = "pos", item_image = "pos", item_image_button = "pos",
	animated_image = "pos", model = "pos", tabheader = "pos",
	list = "list", -- list[inv;name;x,y;w,h]: position is the 3rd part
}

local function num(v, k)
	return (("%.3f"):format(v * k):gsub("%.?0+$", ""))
end

-- "x,y" -> x scaled; "w,h" -> w scaled (nil if not numbers)
local function scale_first(part, k)
	local a, rest = part:match("^%s*(%-?[%d%.]+)(,.*)$")
	if not a or not tonumber(a) then
		return nil
	end
	return num(tonumber(a), k) .. rest
end

-- split on ";" that isn't escaped
local function split(args)
	local out, cur, i = {}, {}, 1
	while i <= #args do
		local c = args:sub(i, i)
		if c == "\\" then
			cur[#cur + 1] = args:sub(i, i + 1)
			i = i + 2
		else
			if c == ";" then
				out[#out + 1] = table.concat(cur)
				cur = {}
			else
				cur[#cur + 1] = c
			end
			i = i + 1
		end
	end
	out[#out + 1] = table.concat(cur)
	return out
end

local function widen_element(name, args, k)
	local how = WIDEN[name]
	if not how then
		return nil
	end
	local p = split(args)
	if how == "size" then
		p[1] = scale_first(p[1], k) or p[1]
	elseif how == "list" then
		if p[3] then
			p[3] = scale_first(p[3], k) or p[3]
		end
	else
		local pos = scale_first(p[1], k)
		if not pos then
			return nil -- (a form without a position, e.g. tooltip[name;text])
		end
		p[1] = pos
		-- (square ones are slots, icons: they keep their shape)
		local w, h = (p[2] or ""):match("^%s*([%d%.]+),([%d%.]+)")
		local square = w and tonumber(w) == tonumber(h)
		if how == "both" and p[2] and not square then
			p[2] = scale_first(p[2], k) or p[2]
		end
		-- scrollbars keep their thickness when vertical
		if how == "scrollbar" and p[2] and p[3] == "horizontal" then
			p[2] = scale_first(p[2], k) or p[2]
		end
	end
	return table.concat(p, ";")
end

function theme.widen(fs, k)
	k = k or (nhv.EDITOR and 1 or theme.text_scale())
	-- (screens with their own fixed layout, like the title, are left alone)
	if k <= 1.001 or type(fs) ~= "string" or fs:find("no_prepend[]", 1, true) then
		return fs
	end
	local out, i, n = {}, 1, #fs
	while i <= n do
		local s, e, name = fs:find("([%w_]+)%[", i)
		if not s then
			out[#out + 1] = fs:sub(i)
			break
		end
		out[#out + 1] = fs:sub(i, e)
		-- the element's arguments, up to the "]" that isn't escaped
		local j = e + 1
		while j <= n do
			local c = fs:sub(j, j)
			if c == "\\" then
				j = j + 2
			elseif c == "]" then
				break
			else
				j = j + 1
			end
		end
		local args = fs:sub(e + 1, j - 1)
		out[#out + 1] = widen_element(name, args, k) or args
		out[#out + 1] = "]"
		i = j + 1
	end
	return table.concat(out)
end

-- every menu goes through the widening
local show_formspec = core.show_formspec
function core.show_formspec(name, formname, fs)
	return show_formspec(name, formname, theme.widen(fs))
end
core.register_on_joinplayer(function(player)
	local meta = getmetatable(player)
	local methods = meta and (type(meta.__index) == "table" and meta.__index or meta)
	if methods and methods.set_inventory_formspec and not methods._nhv_widened then
		local set = methods.set_inventory_formspec
		methods.set_inventory_formspec = function(self, fs)
			return set(self, theme.widen(fs))
		end
		methods._nhv_widened = true
	end
end)

return theme
