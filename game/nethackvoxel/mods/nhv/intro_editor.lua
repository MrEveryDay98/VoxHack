-- The intro editor (a world with a file named "nhv_intro" in it:
-- tools/make_intro_world.py): the opening's forest, made by Luanti's world
-- generator - rolling grass, NetHack's trees - and the camera's way through
-- it, put down point by point.
--
-- The forest is the AREA from x, z 0 to 255 (the rest goes on, but isn't
-- kept). Fly about (you can), build and dig with what's in your inventory:
--
--   Camera point: put it where the camera's to be. It looks the way you were
--     looking; right-click it to set its line (what's said there, and by
--     whom), how the camera goes on to the next point - gliding there in the
--     line's own time or so many seconds, or fading to black or white and
--     jumping there - and how long it waits first. "Take my view" aims it
--     as you're looking now; "Look through it" puts you there to see.
--     Points go in the order of their numbers.
--   Sign: on a wall - right-click it for its words, a line each.
--   Monster or person: any NetHack monster's sprite standing there, turned
--     to you as they all are - right-click it for which (its name, as
--     NetHack has it) and how tall.
--   The sky is the game's: the one the VoxHack Editor's Sky tab gives
--   "opening" (the default sky if none).
--
--   /intro_play            play it from the first point (Enter stops it)
--   /intro_save [ymin ymax]  save it for the game (the forest from ymin to
--                          ymax: -8 to 56 if not given) - mod_data/nhv/intro

local intro_editor = {}
nhv.intro_editor = intro_editor

local AREA = 256
local storage = core.get_mod_storage()

-- ---------------------------------------------------------------- the forest
core.register_alias("mapgen_stone", "nhv:intro_dirt")
core.register_alias("mapgen_water_source", "nhv:intro_dirt")
core.register_alias("mapgen_river_water_source", "nhv:intro_dirt")
core.clear_registered_biomes()
core.clear_registered_decorations()

-- (the ground's top, as each piece is made: grass - now and then the other
-- kinds - and the trees on it, in clumps, thinner between)
local TREE_NOISE = {offset = 0, scale = 1, spread = {x = 40, y = 40, z = 40}, seed = 2207,
	octaves = 2, persistence = 0.6}
core.register_on_generated(function(minp, maxp, seed)
	local vm, emin, emax = core.get_mapgen_object("voxelmanip")
	local area = VoxelArea:new({MinEdge = emin, MaxEdge = emax})
	local data = vm:get_data()
	local air, dirt = core.get_content_id("air"), core.get_content_id("nhv:intro_dirt")
	local grass = {core.get_content_id("nhv:intro_grass"), core.get_content_id("nhv:intro_grass2"),
		core.get_content_id("nhv:intro_grass3")}
	local tree = core.get_content_id("nhv:intro_tree")
	local rand = PcgRandom(seed)
	local noise = core.get_perlin(TREE_NOISE)
	local changed = false
	for z = minp.z, maxp.z do
		for x = minp.x, maxp.x do
			for y = maxp.y, minp.y, -1 do
				local vi = area:index(x, y, z)
				if data[vi] == dirt then
					if data[area:index(x, y + 1, z)] == air then
						local r = rand:next(1, 100)
						data[vi] = grass[r <= 12 and 2 or r <= 20 and 3 or 1]
						changed = true
						local density = 0.01 + 0.05 * math.max(0, noise:get_2d({x = x, y = z}))
						if y + 1 <= emax.y and rand:next(1, 10000) <= density * 10000 then
							data[area:index(x, y + 1, z)] = tree
						end
					end
					break
				elseif data[vi] ~= air then
					break
				end
			end
		end
	end
	if changed then
		vm:set_data(data)
		vm:calc_lighting()
		vm:write_to_map()
	end
end)

-- ---------------------------------------------------------------- you
core.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	local privs = core.get_player_privs(name)
	privs.fly, privs.fast, privs.noclip, privs.interact = true, true, true, true
	core.set_player_privs(name, privs)
	player:set_armor_groups({immortal = 1})
	player:override_day_night_ratio(1)
	nhv.sky.scene = "opening"
	nhv.sky.update()
	core.set_timeofday(0.5)
	-- the palette (I): every block of the prefab editor's but its markers -
	-- the game's - and the opening's own
	nhv.palette.configure({skip = {markers = true},
		extra = {{"opening", "Opening", nhv.intro_blocks.PALETTE}}})
	nhv.palette.open(player)
	player:hud_set_hotbar_itemcount(10)
	local inv = player:get_inventory()
	inv:set_size("main", 32)
	for _, item in ipairs({"nhv:intro_cam 99", "nhv:intro_sign 99", "nhv:intro_figure 99", "nhv:intro_tree 99",
			"nhv:intro_grass 99", "nhv:intro_dirt 99"}) do
		if not inv:contains_item("main", ItemStack(item):get_name()) then
			inv:add_item("main", item)
		end
	end
	if not storage:get("visited") then
		storage:set_string("visited", "1")
		local y = core.get_spawn_level(AREA / 2, AREA / 2) or 20
		player:set_pos(vector.new(AREA / 2, y + 2, AREA / 2))
	end
	core.chat_send_player(name, "Intro editor: the forest is x, z 0 to " .. (AREA - 1)
		.. ". I = block palette (its Opening tab: camera points, signs, figures, the forest's own)."
		.. " /intro_play plays it, /intro_save saves it.")
end)
-- (always midday; the trees standing round you - the editor's whole forest
-- at once would be a lot)
local TREES_AROUND = 96
local tree_t = 0
core.register_globalstep(function(dtime)
	core.set_timeofday(0.5)
	tree_t = tree_t + dtime
	local player = core.get_connected_players()[1]
	if tree_t < 1 or not player or (nhv.intro_play and nhv.intro_play.active) then
		return
	end
	tree_t = 0
	local p = vector.round(player:get_pos())
	local r = vector.new(TREES_AROUND, 48, TREES_AROUND)
	nhv.intro_blocks.sprites(intro_editor.sprites(vector.subtract(p, r), vector.add(p, r), vector.zero()))
end)

-- ---------------------------------------------------------------- what's put down
-- (kept by place: the camera points' and signs' settings, for playing and
-- saving without the map loaded)
local function key(pos)
	return pos.x .. "," .. pos.y .. "," .. pos.z
end
local function load_list(name)
	return core.parse_json(storage:get_string(name) ~= "" and storage:get_string(name) or "{}") or {}
end
local function save_list(name, list)
	storage:set_string(name, core.write_json(list))
end

local function cams()
	return load_list("cams")
end
local function set_cam(pos, c)
	local list = cams()
	list[key(pos)] = c
	save_list("cams", list)
end

local function next_index()
	local n = 0
	for _, c in pairs(cams()) do
		n = math.max(n, tonumber(c.index) or 0)
	end
	return n + 1
end

local TRANSITIONS = {{"glide", "Glide to the next point"}, {"black", "Fade to black, then cut to it"},
	{"white", "Fade to white, then cut to it"}}

local function esc(s)
	return core.formspec_escape(tostring(s or ""))
end

local function cam_form(pos, c)
	local names, sel = {}, 1
	for i, t in ipairs(TRANSITIONS) do
		names[i] = t[2]
		if t[1] == c.transition then
			sel = i
		end
	end
	return table.concat({
		"formspec_version[6]size[11,10.6]",
		"label[0.4,0.5;Camera point ", esc(key(pos)), "]",
		"field[0.4,1.3;2,0.8;index;Number (order);", esc(c.index), "]",
		"field[2.8,1.3;3.6,0.8;voice;Said by;", esc(c.voice or "Narrator"), "]",
		"field[6.8,1.3;3.8,0.8;mood;Mood (angry, sad, afraid, calm, whisper);", esc(c.mood), "]",
		"textarea[0.4,2.6;10.2,2.2;line;What's said here;", esc(c.line), "]",
		"checkbox[0.4,5.4;sync;Go on to the next point in the time it takes to say;", c.sync ~= false and "true" or "false", "]",
		"field[0.4,6.4;3,0.8;seconds;Otherwise: seconds;", esc(c.seconds or 3), "]",
		"field[3.8,6.4;3,0.8;delay;Wait first: seconds;", esc(c.delay or 0), "]",
		"label[0.4,7.6;How it goes on]",
		"dropdown[0.4,7.9;7,0.8;transition;", table.concat(names, ","), ";", sel, ";true]",
		"button[0.4,9.3;3,0.8;view;Take my view]",
		"button[3.6,9.3;3.4,0.8;look;Look through it]",
		"button_exit[7.6,9.3;3,0.8;save;Save]",
	})
end

local function sign_form(pos, s)
	return table.concat({
		"formspec_version[6]size[8,5.2]",
		"textarea[0.4,0.7;7.2,2.6;text;The sign's words (a line each - three at most);", esc(s.text), "]",
		"button_exit[4.6,4;3,0.8;save;Save]",
	})
end

-- the sign's picture on its wall (put up again as the map loads)
local boards = {}
local function show_board(pos)
	local k = key(pos)
	if boards[k] and boards[k]:get_pos() then
		boards[k]:remove()
	end
	boards[k] = nil
	local s = load_list("signs")[k]
	local node = core.get_node(pos)
	if not s or node.name ~= "nhv:intro_sign" then
		return
	end
	boards[k] = nhv.intro_blocks.board(pos, core.wallmounted_to_dir(node.param2), s.text)
end

local editing = {} -- player name -> {kind=, pos=}

-- the monsters and people: what each is ({name=, h=}), by place
local DEFAULT_FIGURE = {name = "watchman", h = 1.8}
local function figure_form(f)
	return table.concat({
		"formspec_version[6]size[8,4.4]",
		"field[0.4,0.8;5,0.8;name;Which (NetHack's name: newt, watchman, gnome leader...);", esc(f.name), "]",
		"field[5.8,0.8;1.8,0.8;h;Height;", esc(f.h), "]",
		"label[0.4,2.2;", esc(f.bad and ("No monster called " .. f.bad) or ""), "]",
		"button_exit[4.6,3.2;3,0.8;save;Save]",
	})
end

-- the trees and figures between p1 and p2, for intro_blocks.sprites (at:
-- taken off their places)
function intro_editor.sprites(p1, p2, at)
	local list = {}
	for _, pos in ipairs(core.find_nodes_in_area(p1, p2, {"nhv:intro_tree"})) do
		list[#list + 1] = nhv.intro_blocks.tree(vector.subtract(pos, at))
	end
	for _, pos in ipairs(core.find_nodes_in_area(p1, p2, nhv.intro_blocks.furniture_nodes())) do
		list[#list + 1] = nhv.intro_blocks.furniture(core.get_node(pos).name, vector.subtract(pos, at))
	end
	local figs = load_list("figures")
	for _, pos in ipairs(core.find_nodes_in_area(p1, p2, {"nhv:intro_figure"})) do
		local f = figs[key(pos)] or DEFAULT_FIGURE
		local tile = nhv.intro_blocks.tile_named(f.name)
		if tile then
			list[#list + 1] = {pos = vector.subtract(pos, at), tile = tile, h = tonumber(f.h) or 1.8}
		end
	end
	return list
end

core.override_item("nhv:intro_figure", {
	after_place_node = function(pos)
		local list = load_list("figures")
		list[key(pos)] = table.copy(DEFAULT_FIGURE)
		save_list("figures", list)
	end,
	after_dig_node = function(pos)
		local list = load_list("figures")
		list[key(pos)] = nil
		save_list("figures", list)
	end,
	on_rightclick = function(pos, _, clicker)
		local f = load_list("figures")[key(pos)] or table.copy(DEFAULT_FIGURE)
		editing[clicker:get_player_name()] = {kind = "figure", pos = pos}
		core.show_formspec(clicker:get_player_name(), "nhv:intro_figure", figure_form(f))
	end,
})

core.override_item("nhv:intro_cam", {
	after_place_node = function(pos, placer)
		local index = next_index()
		set_cam(pos, {index = index, yaw = placer:get_look_horizontal(),
			pitch = placer:get_look_vertical(), line = "", voice = "Narrator", mood = "",
			sync = true, seconds = 3, delay = 0, transition = "glide"})
		core.get_meta(pos):set_string("infotext", "Camera point " .. index)
	end,
	after_dig_node = function(pos)
		local list = cams()
		list[key(pos)] = nil
		save_list("cams", list)
	end,
	on_rightclick = function(pos, _, clicker)
		local c = cams()[key(pos)]
		if not c then
			return
		end
		editing[clicker:get_player_name()] = {kind = "cam", pos = pos}
		core.show_formspec(clicker:get_player_name(), "nhv:intro_cam", cam_form(pos, c))
	end,
})
core.override_item("nhv:intro_sign", {
	after_place_node = function(pos)
		local list = load_list("signs")
		list[key(pos)] = {text = ""}
		save_list("signs", list)
	end,
	after_dig_node = function(pos)
		local list = load_list("signs")
		list[key(pos)] = nil
		save_list("signs", list)
		show_board(pos)
	end,
	on_rightclick = function(pos, _, clicker)
		local s = load_list("signs")[key(pos)] or {text = ""}
		editing[clicker:get_player_name()] = {kind = "sign", pos = pos}
		core.show_formspec(clicker:get_player_name(), "nhv:intro_sign", sign_form(pos, s))
	end,
})
core.register_lbm({
	name = ":nhv:intro_sign_boards", nodenames = {"nhv:intro_sign"}, run_at_every_load = true,
	action = function(pos)
		show_board(pos)
	end,
})

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "nhv:intro_cam" and formname ~= "nhv:intro_sign" and formname ~= "nhv:intro_figure" then
		return false
	end
	local name = player:get_player_name()
	local e = editing[name]
	if not e then
		return true
	end
	if e.kind == "figure" then
		if fields.name then
			local f = {name = fields.name:lower(), h = tonumber(fields.h) or 1.8}
			if not nhv.intro_blocks.tile_named(f.name) then
				-- (not a monster's name: asked again)
				f.bad = fields.name
				core.show_formspec(name, formname, figure_form(f))
				return true
			end
			local list = load_list("figures")
			list[key(e.pos)] = f
			save_list("figures", list)
		end
		return true
	end
	if e.kind == "sign" then
		if fields.save or fields.text then
			local list = load_list("signs")
			list[key(e.pos)] = {text = fields.text or ""}
			save_list("signs", list)
			show_board(e.pos)
		end
		return true
	end
	local c = cams()[key(e.pos)]
	if not c then
		return true
	end
	if fields.index then
		c.index = tonumber(fields.index) or c.index
		c.voice = fields.voice ~= "" and fields.voice or "Narrator"
		c.mood = fields.mood or ""
		c.line = fields.line or ""
		c.seconds = tonumber(fields.seconds) or c.seconds
		c.delay = tonumber(fields.delay) or c.delay
	end
	if fields.sync then
		c.sync = fields.sync == "true"
	end
	local tr = tonumber(fields.transition)
	if tr and TRANSITIONS[tr] then
		c.transition = TRANSITIONS[tr][1]
	end
	if fields.view then
		c.yaw, c.pitch = player:get_look_horizontal(), player:get_look_vertical()
		core.chat_send_player(name, "Camera point " .. c.index .. " looks the way you are now.")
	end
	set_cam(e.pos, c)
	core.get_meta(e.pos):set_string("infotext", "Camera point " .. c.index)
	if fields.look then
		local eye = player:get_properties().eye_height or 1.625
		player:set_pos(vector.offset(e.pos, 0, -eye, 0))
		player:set_look_horizontal(c.yaw)
		player:set_look_vertical(c.pitch)
		core.close_formspec(name, formname)
	elseif fields.view then
		core.show_formspec(name, formname, cam_form(e.pos, c))
	end
	return true
end)

-- placing never uses up blocks (as in the prefab editor)
core.register_on_placenode(function()
	return true
end)

-- ---------------------------------------------------------------- playing, saving
-- the points in order, each where the camera's eyes are (its block's middle)
local function points(origin)
	local list = {}
	for k, c in pairs(cams()) do
		local pos = core.string_to_pos("(" .. k .. ")")
		local p = table.copy(c)
		p.pos = vector.subtract(pos, origin)
		list[#list + 1] = p
	end
	table.sort(list, function(a, b) return (tonumber(a.index) or 0) < (tonumber(b.index) or 0) end)
	return list
end

local function signs(origin)
	local list = {}
	for k, s in pairs(load_list("signs")) do
		local pos = core.string_to_pos("(" .. k .. ")")
		local node = core.get_node(pos)
		if node.name == "nhv:intro_sign" then
			list[#list + 1] = {pos = vector.subtract(pos, origin), dir = core.wallmounted_to_dir(node.param2),
				text = s.text}
		end
	end
	return list
end

core.register_chatcommand("intro_play", {
	description = "Play the opening from the first camera point (Enter stops it)",
	func = function(name)
		local player = core.get_player_by_name(name)
		local list = points(vector.zero())
		if not player or #list == 0 then
			return false, "No camera points yet."
		end
		local back = player:get_pos()
		-- (the signs are on the walls already)
		-- (the trees and figures all over the forest, while it plays)
		local all = intro_editor.sprites(vector.new(0, -32, 0), vector.new(AREA - 1, 96, AREA - 1), vector.zero())
		local trees, figures = {}, {}
		for _, sp in ipairs(all) do
			if sp.tile == nhv.intro_blocks.tree(sp.pos).tile then
				trees[#trees + 1] = sp.pos
			else
				figures[#figures + 1] = sp
			end
		end
		nhv.intro_play.preview(player, {points = list, signs = {}, trees = trees, figures = figures,
			min = vector.new(0, back.y, 0), max = vector.new(AREA - 1, back.y, AREA - 1)}, function(p)
			p:set_pos(back)
			p:override_day_night_ratio(1)
		end)
		return true
	end,
})

core.register_chatcommand("intro_save", {
	params = "[ymin ymax]",
	description = "Save the forest and its camera's way for the game",
	func = function(name, param)
		local ymin, ymax = param:match("^%s*(%-?%d+)%s+(%-?%d+)%s*$")
		ymin, ymax = tonumber(ymin) or -8, tonumber(ymax) or 56
		local p1, p2 = vector.new(0, ymin, 0), vector.new(AREA - 1, ymax, AREA - 1)
		local list = points(vector.zero())
		if #list == 0 then
			return false, "Put down some camera points first."
		end
		core.chat_send_player(name, "Saving the forest...")
		core.emerge_area(p1, p2, function(_, _, left)
			if left > 0 then
				return
			end
			core.mkdir(nhv.intro_play.DATA_DIR)
			if not core.create_schematic(p1, p2, nil, nhv.intro_play.SCHEMATIC) then
				core.chat_send_player(name, "Couldn't save the forest.")
				return
			end
			local data = {version = os.time(), min = p1, max = p2, points = list, signs = signs(vector.zero()),
				trees = core.find_nodes_in_area(p1, p2, {"nhv:intro_tree"}), figures = {}}
			for _, sp in ipairs(intro_editor.sprites(p1, p2, vector.zero())) do
				if sp.tile ~= nhv.intro_blocks.tree(sp.pos).tile then
					data.figures[#data.figures + 1] = sp
				end
			end
			local f = io.open(nhv.intro_play.JSON, "w")
			if not f then
				core.chat_send_player(name, "Couldn't save the camera's way.")
				return
			end
			f:write(core.write_json(data, true))
			f:close()
			core.chat_send_player(name, ("Saved: %d camera points, %d signs, %d trees, %d figures,"
				.. " the forest from y %d to %d."):format(#list, #data.signs, #data.trees, #data.figures, ymin, ymax))
		end)
		return true
	end,
})

return intro_editor
