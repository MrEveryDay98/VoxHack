-- Monster editor (in the prefab editor world): set how big each monster
-- and dungeon feature is drawn.
--
-- Press E (or /monsters). A list of every monster and feature appears on
-- the left; the selected one stands on a stage on the right, turning
-- slowly, with a grid of 1-node squares (the bright 3x3 square is one map
-- square) and an optional view of its hitbox. Drag the scale slider, or
-- reset it to the default. Scales are saved for all worlds immediately.

local scale = nhv.scale
local medit = {}
nhv.monsteredit = medit

-- the stage, out of the way of the prefab cells
local STAGE = vector.new(-40, 0, -40)   -- centre of the stage floor (y = floor top)
local STAGE_R = 4                        -- half-size of the floor in nodes
local CAM = vector.new(STAGE.x - 1.5, STAGE.y + 2.0, STAGE.z - 6.5)

-- ---------------------------------------------------------------- entries
local entries = nil   -- {kind = "mon"|"feat", key=, name=, tile=, size=}

local function build_entries()
	entries = {}
	for cmap, name in pairs(scale.FEATURE_NAMES) do
		local tiles = {S_tree = 1290, S_fountain = 1313, S_altar = 1307,
			S_throne = 1311, S_sink = 1312, S_grave = 1310}
		entries[#entries + 1] = {kind = "feat", key = cmap, name = name, tile = tiles[cmap]}
	end
	table.sort(entries, function(a, b) return a.name < b.name end)
	local ok = core.nh_load()
	if ok then
		for mndx = 0, (core.nh_num_monsters() or 0) - 1 do
			local mi = core.nh_mon_info(mndx)
			if mi and mi.name and mi.name ~= "" then
				entries[#entries + 1] = {kind = "mon", key = mi.name, name = mi.name,
					tile = mi.tile, size = mi.size}
			end
		end
	end
end

local function base_height(e)
	if e.kind == "feat" then
		return scale.FEATURE_H[e.key]
	end
	return scale.SIZE_H[e.size or 2] or 2
end

local function factor(e)
	if e.kind == "feat" then
		return scale.feat_factor(e.key)
	end
	return scale.mon_factor_by_name(e.key)
end

local function set_factor(e, f)
	if e.kind == "feat" then
		scale.set_feat(e.key, f)
	else
		scale.set_mon(e.key, f)
	end
	scale.save()
end

-- ---------------------------------------------------------------- stage
core.register_node("nhv:editor_grid", {
	description = "Stage floor",
	tiles = {"[fill:16x16:#4050D8^[fill:16x1:0,0:#B050C0^[fill:1x16:0,0:#B050C0"},
	paramtype = "light", light_source = 4,
	groups = {not_in_creative_inventory = 1}, drop = "", diggable = false,
})
core.register_node("nhv:editor_grid_square", {
	description = "Stage floor (one map square)",
	tiles = {"[fill:16x16:#5868F0^[fill:16x1:0,0:#E070F0^[fill:1x16:0,0:#E070F0"},
	paramtype = "light", light_source = 6,
	groups = {not_in_creative_inventory = 1}, drop = "", diggable = false,
})
core.register_node("nhv:editor_backdrop", {
	description = "Stage backdrop",
	tiles = {"[fill:16x16:#8A8A8A"},
	paramtype = "light", light_source = 8,
	groups = {not_in_creative_inventory = 1}, drop = "", diggable = false,
})

local function build_stage()
	for x = -STAGE_R, STAGE_R do
		for z = -STAGE_R, STAGE_R do
			local center = math.abs(x) <= 1 and math.abs(z) <= 1
			core.set_node(vector.new(STAGE.x + x, STAGE.y - 1, STAGE.z + z),
				{name = center and "nhv:editor_grid_square" or "nhv:editor_grid"})
		end
		for y = 0, 9 do
			core.set_node(vector.new(STAGE.x + x, STAGE.y + y, STAGE.z + STAGE_R + 1),
				{name = "nhv:editor_backdrop"})
		end
	end
	-- somewhere to stand
	for x = -2, 2 do
		for z = -2, 2 do
			core.set_node(vector.new(CAM.x + x, STAGE.y - 1, CAM.z + z), {name = "nhv:editor_ground"})
		end
	end
end

core.register_entity("nhv:editor_preview", {
	initial_properties = {
		visual = "wielditem", wield_item = nhv_tiles.item(0),
		physical = false, pointable = false, static_save = false,
		visual_size = {x = 1, y = 1, z = 1},
	},
	on_step = function(self, dtime)
		self.object:set_yaw((self.object:get_yaw() + dtime * 0.6) % (math.pi * 2))
	end,
})

core.register_entity("nhv:editor_hitbox", {
	initial_properties = {
		visual = "cube", physical = false, pointable = false, static_save = false,
		textures = {"[fill:16x16:#30FF3050^[fill:16x1:0,0:#30FF30^[fill:16x1:0,15:#30FF30"
			.. "^[fill:1x16:0,0:#30FF30^[fill:1x16:15,0:#30FF30"},
		use_texture_alpha = true, backface_culling = false,
		visual_size = {x = 1, y = 1, z = 1},
	},
})

-- per player editor state
local sessions = {}

local function clear_preview(s)
	for _, k in ipairs({"preview", "hitbox"}) do
		if s[k] and s[k]:get_pos() then
			s[k]:remove()
		end
		s[k] = nil
	end
end

local function show_preview(s)
	clear_preview(s)
	local e = entries[s.sel]
	if not e then
		return
	end
	local h = base_height(e) * factor(e)
	local pos = vector.new(STAGE.x, STAGE.y - 0.5 + h / 2, STAGE.z)
	s.preview = core.add_entity(pos, "nhv:editor_preview")
	if s.preview then
		s.preview:set_properties({wield_item = nhv_tiles.item(e.tile),
			visual_size = {x = h / 2, y = h / 2, z = h / 2}})
	end
	if s.show_hitbox and e.kind == "mon" then
		local w = scale.radius_for_height(h)
		s.hitbox = core.add_entity(pos, "nhv:editor_hitbox")
		if s.hitbox then
			s.hitbox:set_properties({visual_size = {x = w * 2, y = h, z = w * 2}})
		end
	end
end

-- ---------------------------------------------------------------- formspec
local E = core.formspec_escape

local function formspec(s)
	local fs = {"formspec_version[6]size[20,11]position[0.5,0.5]",
		"bgcolor[#00000000;false]",
		"box[0.2,0.2;9.6,10.6;#101018D8]",
		"style_type[button;bgcolor=#303040]",
		"label[3.6,0.7;Monster editor]"}
	local rows = #entries
	fs[#fs + 1] = "scroll_container[0.4,1.2;8.8,9.4;mlist;vertical]"
	for i, e in ipairs(entries) do
		local y = (i - 1) * 1.15
		fs[#fs + 1] = ("item_image[0.1,%f;1,1;%s]"):format(y, nhv_tiles.item(e.tile))
		if i == s.sel then
			fs[#fs + 1] = ("style[ent_%d;bgcolor=#2E8B3E]"):format(i)
		end
		local f = factor(e)
		local label = e.name .. (f ~= 1 and ("  (x" .. f .. ")") or "")
			.. (e.kind == "feat" and "  [feature]" or "")
		fs[#fs + 1] = ("button[1.3,%f;7.3,1;ent_%d;%s]"):format(y, i, E(label))
	end
	fs[#fs + 1] = "scroll_container_end[]"
	fs[#fs + 1] = ("scrollbaroptions[max=%d;smallstep=12;largestep=80]"):format(math.max(0, (rows - 8) * 12))
	fs[#fs + 1] = ("scrollbar[9.3,1.2;0.35,9.4;vertical;mlist;%d]"):format(s.scroll or 0)
	-- right side: the stage shows through; frame it and put controls below
	fs[#fs + 1] = "box[10.4,0.4;9.2,0.06;#000000]box[10.4,8.3;9.2,0.06;#000000]"
	fs[#fs + 1] = "box[10.4,0.4;0.06,7.96;#000000]box[19.54,0.4;0.06,7.96;#000000]"
	local e = entries[s.sel]
	if e then
		local f = factor(e)
		fs[#fs + 1] = "box[10.4,8.5;9.2,2.3;#101018D8]"
		fs[#fs + 1] = ("label[10.6,8.85;%s  -  scale x%.2f]"):format(E(e.name), f)
		fs[#fs + 1] = "button[16.6,8.6;2.9,0.7;reset;Reset to default]"
		fs[#fs + 1] = "scrollbaroptions[min=10;max=400;smallstep=5;largestep=25]"
		fs[#fs + 1] = ("scrollbar[10.6,9.5;8.9,0.45;horizontal;scale;%d]"):format(math.floor(f * 100 + 0.5))
		fs[#fs + 1] = "label[14.6,10.3;SCALE]"
		if e.kind == "mon" then
			fs[#fs + 1] = ("checkbox[10.6,10.3;hitbox;Show hitbox;%s]"):format(s.show_hitbox and "true" or "false")
		end
	end
	return table.concat(fs)
end

local function show(player)
	local s = sessions[player:get_player_name()]
	core.show_formspec(player:get_player_name(), "nhv:monsteredit", formspec(s))
end

function medit.open(player)
	if not entries then
		build_entries()
	end
	local name = player:get_player_name()
	local s = sessions[name]
	if not s then
		s = {sel = 1, scroll = 0, show_hitbox = true}
		sessions[name] = s
	end
	s.back = s.back or player:get_pos()
	build_stage()
	-- stand in front of the stage, looking a little left of it so it
	-- appears in the right half of the screen, beside the list
	player:set_pos(vector.new(CAM.x, CAM.y - 1.6, CAM.z))
	player:set_look_vertical(0.18)
	player:set_look_horizontal(0.42)
	player:set_physics_override({speed = 0, jump = 0, gravity = 0})
	show_preview(s)
	show(player)
end

local function close(player)
	local s = sessions[player:get_player_name()]
	if not s then
		return
	end
	clear_preview(s)
	player:set_physics_override({speed = 1, jump = 1, gravity = 1})
	if s.back then
		player:set_pos(s.back)
		s.back = nil
	end
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "nhv:monsteredit" then
		return
	end
	local s = sessions[player:get_player_name()]
	if not s then
		return true
	end
	if fields.mlist then
		local ev = core.explode_scrollbar_event(fields.mlist)
		if ev.type == "CHG" then
			s.scroll = ev.value
		end
	end
	for k in pairs(fields) do
		local i = k:match("^ent_(%d+)$")
		if i then
			s.sel = tonumber(i)
			show_preview(s)
			show(player)
			return true
		end
	end
	local e = entries[s.sel]
	if fields.scale and e then
		local ev = core.explode_scrollbar_event(fields.scale)
		if ev.type == "CHG" then
			set_factor(e, ev.value / 100)
			show_preview(s)
			show(player)
		end
	end
	if fields.reset and e then
		set_factor(e, 1)
		show_preview(s)
		show(player)
	end
	if fields.hitbox then
		s.show_hitbox = fields.hitbox == "true"
		show_preview(s)
	end
	if fields.quit then
		close(player)
	end
	return true
end)

core.register_chatcommand("monsters", {
	description = "Open the monster editor",
	func = function(name)
		local p = core.get_player_by_name(name)
		if p then
			medit.open(p)
		end
	end,
})

-- E opens it
local prev_aux = {}
core.register_globalstep(function()
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		local aux = player:get_player_control().aux1
		if aux and not prev_aux[name] then
			medit.open(player)
		end
		prev_aux[name] = aux
	end
end)

return medit
