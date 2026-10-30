-- The block palette (I to open): tabs of blocks; click one to put it in
-- your hotbar slot. The prefab editor's (editor.lua) and the intro
-- editor's (intro_editor.lua: not the markers - stair triggers, monster
-- paths, carving: the game's - but its own blocks).
--
--   palette.configure({skip = {tab id = true}, extra = {{id, name, {entries}}}})
--     an entry: a node's name, or {image=, tooltip=, give=function(player)
--     -> ItemStack} (a picture: the opening's sprites, intro_editor.lua)
--   palette.open(player)    make it the player's inventory screen (I)

local palette_mod = {}
nhv.palette = palette_mod

local BASE_TABS = {
	{"markers", "Markers"}, {"blocks", "Blocks"}, {"shapes", "Shapes", "Slabs, stairs, panes"},
	{"terrain", "Terrain"}, {"custom", "Your blocks"}, {"objects", "Objects"},
}
local TABS = BASE_TABS
local MARKERS = {["nhv:trigger"] = true, ["nhv:mpath"] = true, ["nhv:carve"] = true}
local palette = {}     -- tab id -> sorted node names
local tab_of = {}      -- player name -> tab index
local cfg = {skip = {}, extra = {}}

function palette_mod.configure(c)
	cfg = {skip = c.skip or {}, extra = c.extra or {}}
	TABS = {}
	for _, t in ipairs(BASE_TABS) do
		if not cfg.skip[t[1]] then
			TABS[#TABS + 1] = t
		end
	end
	for _, t in ipairs(cfg.extra) do
		TABS[#TABS + 1] = {t[1], t[2]}
	end
end

local function category(name, def)
	if MARKERS[name] then
		return "markers"
	elseif def.groups and def.groups.nhv_prop then
		return "objects"
	elseif def.groups and def.groups.nhv_custom then
		return "custom" -- made in the block editor
	elseif name:match("^nhv:b_") then
		for _, shape in ipairs({"_slab$", "_stair$", "_pane$", "_post$"}) do
			if name:match(shape) then
				return "shapes"
			end
		end
		return "blocks"
	end
	return "terrain"
end

local function build_palette()
	palette = {}
	for _, t in ipairs(TABS) do
		palette[t[1]] = {}
	end
	for name, def in pairs(core.registered_nodes) do
		if name:match("^nhv:") and def.groups and def.groups.editor then
			local list = palette[category(name, def)]
			if list then
				list[#list + 1] = name
			end
		end
	end
	for _, list in pairs(palette) do
		table.sort(list)
	end
	-- (the extra tabs: as they're given)
	for _, t in ipairs(cfg.extra) do
		palette[t[1]] = table.copy(t[3])
	end
end

local function first_tab()
	for i, t in ipairs(TABS) do
		if t[1] == "blocks" then
			return i
		end
	end
	return 1
end

local function palette_formspec(pname)
	local ti = tab_of[pname] or first_tab()
	if not TABS[ti] then
		ti = first_tab()
	end
	local list = palette[TABS[ti][1]] or {}
	local cols, step = 15, 1.05
	local rows = math.ceil(#list / cols)
	local view_h = 8.6
	local fs = {"formspec_version[6]size[17.2,11]"}
	-- the tabs: a row of buttons across the whole width, the one shown
	-- pressed in (what each has, and how many: its tooltip)
	local w = 16.6 / #TABS
	for i, t in ipairs(TABS) do
		if i == ti then
			fs[#fs + 1] = ("style[paltab_%d;bgimg=nhv_ui_button_pressed.png;bgcolor=#5A5A78;textcolor=#FFFF55]")
				:format(i)
		end
		fs[#fs + 1] = ("button[%f,0.25;%f,0.75;paltab_%d;%s]"):format(0.3 + (i - 1) * w, w, i,
			core.formspec_escape(t[2]))
		fs[#fs + 1] = ("tooltip[paltab_%d;%s]"):format(i,
			core.formspec_escape(("%s (%d)"):format(t[3] or t[2], #(palette[t[1]] or {}))))
	end
	fs[#fs + 1] = "label[0.4,1.3;Click a block to put it in your hotbar slot."
	fs[#fs + 1] = table.concat({
		TABS[ti][1] == "markers" and " Red = stairs trigger, green = monster path, yellow = carve (overlays)."
			or "", "]",
		("scroll_container[0.3,1.6;16.0,%f;palscroll;vertical;0.1]"):format(view_h)})
	for i, name in ipairs(list) do
		local x = 0.1 + ((i - 1) % cols) * step
		local y = 0.05 + math.floor((i - 1) / cols) * step
		if type(name) == "table" then
			fs[#fs + 1] = ("image_button[%f,%f;0.95,0.95;%s;palx_%d;]"):format(x, y,
				core.formspec_escape(name.image), i)
			fs[#fs + 1] = ("tooltip[palx_%d;%s]"):format(i, core.formspec_escape(name.tooltip or ""))
		else
			fs[#fs + 1] = ("item_image_button[%f,%f;0.95,0.95;%s;pal_%s;]"):format(x, y, name,
				name:gsub(":", "__"))
			fs[#fs + 1] = ("tooltip[pal_%s;%s]"):format(name:gsub(":", "__"),
				core.formspec_escape(core.registered_nodes[name].description or name))
		end
	end
	fs[#fs + 1] = "scroll_container_end[]"
	local overflow = math.max(0, rows * step + 0.1 - view_h)
	fs[#fs + 1] = ("scrollbaroptions[max=%d;smallstep=10;largestep=60]"):format(math.ceil(overflow * 10))
	fs[#fs + 1] = ("scrollbar[16.45,1.6;0.4,%f;vertical;palscroll;0]"):format(view_h)
	if #list == 0 then
		fs[#fs + 1] = "label[0.5,2.2;Nothing here yet.]"
	end
	return table.concat(fs)
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "" then
		return
	end
	local pname = player:get_player_name()
	for i in ipairs(TABS) do
		if fields["paltab_" .. i] then
			tab_of[pname] = i
			player:set_inventory_formspec(palette_formspec(pname))
			return true
		end
	end
	for k in pairs(fields) do
		local n = tonumber(k:match("^palx_(%d+)$") or "")
		if n then
			local t = TABS[tab_of[pname] or first_tab()]
			local e = t and palette[t[1]] and palette[t[1]][n]
			if type(e) == "table" and e.give then
				player:get_inventory():set_stack("main", player:get_wield_index(), e.give(player))
			end
			return true
		end
		local id = k:match("^pal_(.+)$")
		if id then
			local name = id:gsub("__", ":")
			if core.registered_nodes[name] then
				local inv = player:get_inventory()
				inv:set_stack("main", player:get_wield_index(), ItemStack(name .. " 99"))
				return true
			end
		end
	end
end)

function palette_mod.open(player)
	build_palette()
	player:set_inventory_formspec(palette_formspec(player:get_player_name()))
end

return palette_mod
