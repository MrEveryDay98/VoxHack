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
--   Monsters and items: the palette's Monsters and Items tabs have every
--     NetHack sprite - pick one, put it down: it stands there turned to you
--     as they all are, as tall as the game makes it. Right-click it for
--     another (by its name, as NetHack has it) or another height. (The
--     Opening tab's "Monster or person" is one to name yourself.)
--   The sky is the game's: the one the VoxHack Editor's Sky tab gives
--   "opening" (the default sky if none).
--
--   /intro_play            play it from the first point (Enter stops it),
--                          as the game will: without the camera points'
--                          boxes or the signs' blocks
--   /intro_time [time]     the opening's time of day (its sky and light):
--                          a form to set it, or 6:30, dawn, noon, dusk, night
--   /intro_fog             the opening's fog: its colour, how far you see
--                          through it, where it starts (or the game's)
--   /intro_light [0-14]    the light that goes with the camera: how bright
--                          (a light level; 0 none) - round you here too
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
	-- (the light of the opening's time of day, the sky as then)
	player:override_day_night_ratio(nil)
	nhv.sky.scene = "opening"
	nhv.sky.time = intro_editor.time()
	nhv.sky.fog = intro_editor.fog()
	nhv.sky.update()
	nhv.intro_play.apply_fog(player)
	if core.nhv_hero_light then
		core.nhv_hero_light(intro_editor.light())
	end
	-- (camera points and signs hidden for a preview that didn't finish:
	-- back)
	intro_editor.show_markers()
	-- the palette (I): every block of the prefab editor's but its markers -
	-- the game's - and the opening's own
	local extra = {{"opening", "Opening", nhv.intro_blocks.PALETTE}}
	for _, t in ipairs(intro_editor.sprite_tabs()) do
		extra[#extra + 1] = t
	end
	nhv.palette.configure({skip = {markers = true}, extra = extra})
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
-- (the opening's time of day held; the trees standing round you - the
-- editor's whole forest at once would be a lot)
local TREES_AROUND = 96
local tree_t = 0
core.register_globalstep(function(dtime)
	core.set_timeofday(intro_editor.time())
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

local TRANSITIONS = {{"glide", "Glide to the next point"}, {"cut", "Cut to the next point"},
	{"black", "Fade out to black, then cut to it"}, {"white", "Fade out to white, then cut to it"}}
-- how it starts, as the camera gets here (nil: as the last point faded out
-- - the first point: from black)
local FADE_INS = {{nil, "As the last point faded out"}, {"", "No fade"}, {"black", "Fade in from black"},
	{"white", "Fade in from white"}}

local function esc(s)
	return core.formspec_escape(tostring(s or ""))
end

local function fade_in_names()
	local names = {}
	for i, f in ipairs(FADE_INS) do
		names[i] = f[2]
	end
	return table.concat(names, ",")
end
local function fade_in_index(v)
	for i, f in ipairs(FADE_INS) do
		if f[1] == v then
			return i
		end
	end
	return 1
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
		"dropdown[0.4,7.9;5.1,0.8;transition;", table.concat(names, ","), ";", sel, ";true]",
		"label[5.8,7.6;How it starts here]",
		"dropdown[5.8,7.9;4.8,0.8;fade_in;", fade_in_names(), ";", fade_in_index(c.fade_in), ";true]",
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

-- the monsters, people and things: what each is ({tile=, h=}, or {name=,
-- h=} named in its settings), by place
local DEFAULT_FIGURE = {name = "watchman", h = 1.8}

-- how tall the game makes a tile's sprite: a monster by its size (and
-- its scale: /scale), a thing as an object on the floor is, a feature as
-- it stands
local MONSTERS, OBJECTS_END = nhv_tiles.monsters or 789, 1272
local STATUES = 1515 -- (a monster's statue: its tile from here on, in the same order)
local FEATURES = {{"S_fountain", 1313, "fountain"}, {"S_altar", 1307, "altar"},
	{"S_throne", 1311, "throne"}, {"S_sink", 1312, "sink"}, {"S_grave", 1310, "grave"}}
local function tile_height(tile)
	if tile >= STATUES and tile < STATUES + MONSTERS then
		tile = tile - STATUES -- (a statue: as big as the monster)
	end
	if tile < MONSTERS then
		local mndx = math.floor(tile / 2)
		local mi = core.nh_mon_info and core.nh_mon_info(mndx)
		return nhv.scale.height(mi and mi.size, mndx)
	end
	for _, f in ipairs(FEATURES) do
		if f[2] == tile then
			return nhv.scale.feature_height(f[1]) or 2
		end
	end
	return nhv_tiles.name(tile) == "boulder" and 1.6 or 0.6
end
local function round(h)
	return math.floor(h * 100 + 0.5) / 100
end

-- the palette's sprites: an item each, the figure block carrying it
local function sprite_entry(tile, label)
	return {
		image = nhv_tiles.texture(tile), tooltip = label,
		give = function()
			local stack = ItemStack("nhv:intro_figure 99")
			local meta = stack:get_meta()
			meta:set_int("tile", tile)
			meta:set_string("description", label)
			meta:set_string("inventory_image", nhv_tiles.texture(tile))
			meta:set_string("wield_image", nhv_tiles.texture(tile))
			return stack
		end,
	}
end
local function pretty(name)
	return ((name or ""):gsub(",male$", ""):gsub(",female$", " (female)"))
end
function intro_editor.sprite_tabs()
	local monsters, items = {}, {}
	for t = 0, MONSTERS - 1 do
		local n = nhv_tiles.name(t) or ""
		-- (a female only where her sprite isn't his)
		local female = n:find(",female$")
		if not female or nhv_tiles.sheet_index(t) ~= nhv_tiles.sheet_index(t - 1) then
			monsters[#monsters + 1] = sprite_entry(t, pretty(n))
		end
	end
	for t = MONSTERS, OBJECTS_END - 1 do
		items[#items + 1] = sprite_entry(t, nhv_tiles.name(t) or "")
	end
	for _, f in ipairs(FEATURES) do
		items[#items + 1] = sprite_entry(f[2], f[3])
	end
	local statues = {}
	for t = 0, MONSTERS - 1 do
		local n = nhv_tiles.name(t) or ""
		if not n:find(",female$") or nhv_tiles.sheet_index(t) ~= nhv_tiles.sheet_index(t - 1) then
			statues[#statues + 1] = sprite_entry(STATUES + t, "statue of " .. pretty(n))
		end
	end
	return {{"monsters", "Monsters", monsters}, {"statues", "Statues", statues}, {"items", "Items", items}}
end
local function figure_form(f)
	local name = f.name or (f.tile and pretty(nhv_tiles.name(f.tile))) or ""
	return table.concat({
		"formspec_version[6]size[8,4.4]",
		"field[0.4,0.8;5,0.8;name;Which (NetHack's name: newt, watchman, gnome leader...);", esc(name), "]",
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
		local tile = tonumber(f.tile) or nhv.intro_blocks.tile_named(f.name)
		if tile then
			list[#list + 1] = {pos = vector.subtract(pos, at), tile = tile, h = tonumber(f.h) or tile_height(tile)}
		end
	end
	return list
end

core.override_item("nhv:intro_figure", {
	-- (from the palette's sprites: that one, as tall as the game makes it)
	after_place_node = function(pos, _, itemstack)
		local list = load_list("figures")
		local tile = itemstack and itemstack:get_meta():get("tile")
		tile = tonumber(tile)
		list[key(pos)] = tile and {tile = tile, h = round(tile_height(tile))} or table.copy(DEFAULT_FIGURE)
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
			local tile = nhv.intro_blocks.tile_named(fields.name)
			local f = {tile = tile, h = tonumber(fields.h) or (tile and round(tile_height(tile))) or 1.8}
			if not tile then
				-- (not a monster's name: asked again)
				f.name, f.bad = fields.name, fields.name
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
	local fi = tonumber(fields.fade_in)
	if fi and FADE_INS[fi] then
		c.fade_in = FADE_INS[fi][1]
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

-- your hand digs anything here at once (as in the prefab editor - the
-- palette's blocks are "editor" ones; the forest's its own kinds)
local INSTANT = {times = {[1] = 0.15, [2] = 0.15, [3] = 0.15}, uses = 0}
core.override_item("", {
	range = 10,
	tool_capabilities = {
		full_punch_interval = 0.2, max_drop_level = 0,
		groupcaps = {editor = INSTANT, crumbly = INSTANT, cracky = INSTANT, snappy = INSTANT,
			choppy = INSTANT, oddly_breakable_by_hand = INSTANT, dig_immediate = INSTANT},
		damage_groups = {},
	},
})

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
		-- (as in the game: the camera points' boxes and the signs' blocks
		-- out of the way meanwhile)
		intro_editor.hide_markers()
		nhv.intro_play.preview(player, {points = list, signs = {}, trees = trees, figures = figures,
			time = intro_editor.time(), fog = intro_editor.fog(), light = intro_editor.light(),
			min = vector.new(0, back.y, 0), max = vector.new(AREA - 1, back.y, AREA - 1)}, function(p)
			intro_editor.show_markers()
			p:set_pos(back)
			p:override_day_night_ratio(nil)
			nhv.sky.time = intro_editor.time()
		end)
		return true
	end,
})

-- ---------------------------------------------------------------- the time of day
-- the opening's (0 midnight, 0.5 noon)
function intro_editor.time()
	return tonumber(storage:get_string("time")) or 0.5
end
local function set_time(t)
	t = t % 1
	storage:set_string("time", tostring(t))
	nhv.sky.time = t
	core.set_timeofday(t)
	nhv.sky.update()
end
local function clock(t)
	local m = math.floor(t * 1440 + 0.5) % 1440
	return ("%d:%02d"):format(math.floor(m / 60), m % 60)
end
-- (dawn and dusk as the sky colours them: sky.lua's dawn)
local TIMES = {{"dawn", 0.2}, {"noon", 0.5}, {"dusk", 0.8}, {"night", 0}}
local function time_form()
	local t = intro_editor.time()
	local fs = {"formspec_version[6]size[10,4.2]",
		"label[0.4,0.5;The opening's time of day: ", clock(t), "]",
		"scrollbaroptions[min=0;max=1439;smallstep=15;largestep=60]",
		("scrollbar[0.4,1;9.2,0.6;horizontal;minute;%d]"):format(math.floor(t * 1440 + 0.5) % 1440)}
	for i, p in ipairs(TIMES) do
		fs[#fs + 1] = ("button[%f,2.2;2.1,0.8;time_%s;%s]"):format(0.4 + (i - 1) * 2.35, p[1],
			p[1]:sub(1, 1):upper() .. p[1]:sub(2))
	end
	fs[#fs + 1] = "button_exit[7.4,3.2;2.2,0.8;close;Done]"
	return table.concat(fs)
end
core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "nhv:intro_time" then
		return false
	end
	for _, p in ipairs(TIMES) do
		if fields["time_" .. p[1]] then
			set_time(p[2])
		end
	end
	local ev = fields.minute and core.explode_scrollbar_event(fields.minute)
	if ev and ev.type == "CHG" then
		set_time(ev.value / 1440)
	end
	if not fields.close and not fields.quit then
		core.show_formspec(player:get_player_name(), formname, time_form())
	end
	return true
end)
core.register_chatcommand("intro_time", {
	params = "[h:mm | dawn | noon | dusk | night]",
	description = "The opening's time of day (its sky and light)",
	func = function(name, param)
		param = param:lower():gsub("^%s+", ""):gsub("%s+$", "")
		if param == "" then
			core.show_formspec(name, "nhv:intro_time", time_form())
			return true
		end
		for _, p in ipairs(TIMES) do
			if p[1] == param then
				set_time(p[2])
				return true, "The opening's time: " .. clock(p[2])
			end
		end
		local h, m = param:match("^(%d+):(%d%d)$")
		if h and tonumber(h) < 24 and tonumber(m) < 60 then
			local t = (tonumber(h) * 60 + tonumber(m)) / 1440
			set_time(t)
			return true, "The opening's time: " .. clock(t)
		end
		return false, "A time like 6:30, or dawn, noon, dusk or night."
	end,
})

-- ---------------------------------------------------------------- the fog
-- the opening's ({on, color, distance (nodes: how far you see), start (0..1:
-- clear up to there)}; not on: the game's)
local FOG_DEFAULT = {on = false, color = "#B8C4CC", distance = 120, start = 0.3}
local FOG_COLORS = {{"Mist", "#C8D0D8"}, {"Grey", "#808890"}, {"Dusk", "#C08870"}, {"Night", "#101828"},
	{"Swamp", "#7C9068"}, {"Ghostly", "#9080B0"}}
function intro_editor.fog()
	local f = core.parse_json(storage:get_string("fog") ~= "" and storage:get_string("fog") or "null")
	if type(f) ~= "table" then
		f = table.copy(FOG_DEFAULT)
	end
	return f
end
local function set_fog(f)
	storage:set_string("fog", core.write_json(f))
	nhv.sky.fog = f
	for _, player in ipairs(core.get_connected_players()) do
		nhv.intro_play.apply_fog(player)
	end
end
local function fog_form()
	local f = intro_editor.fog()
	local fs = {"formspec_version[6]size[10.4,7.4]",
		"checkbox[0.4,0.6;on;Fog of its own (otherwise the game's);", f.on and "true" or "false", "]",
		"field[0.4,1.5;3,0.8;color;Colour;", esc(f.color), "]",
		"button[3.6,1.5;1.6,0.8;setcolor;Set]"}
	for i, c in ipairs(FOG_COLORS) do
		local x = 0.4 + (i - 1) * 1.62
		fs[#fs + 1] = ("style[fogc_%d;bgcolor=%s]"):format(i, c[2])
		fs[#fs + 1] = ("button[%f,2.6;1.5,0.8;fogc_%d;%s]"):format(x, i, c[1])
	end
	fs[#fs + 1] = ("label[0.4,3.9;How far you can see: %d blocks]"):format(f.distance)
	fs[#fs + 1] = "scrollbaroptions[min=10;max=400;smallstep=5;largestep=25]"
	fs[#fs + 1] = ("scrollbar[0.4,4.2;9.6,0.5;horizontal;distance;%d]"):format(f.distance)
	fs[#fs + 1] = ("label[0.4,5.2;Clear up to: %d%% of that]"):format(math.floor(f.start * 100 + 0.5))
	fs[#fs + 1] = "scrollbaroptions[min=0;max=95;smallstep=5;largestep=10]"
	fs[#fs + 1] = ("scrollbar[0.4,5.5;9.6,0.5;horizontal;start;%d]"):format(math.floor(f.start * 100 + 0.5))
	fs[#fs + 1] = "button_exit[7.8,6.4;2.2,0.8;close;Done]"
	return table.concat(fs)
end
core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "nhv:intro_fog" then
		return false
	end
	local f = intro_editor.fog()
	local changed = false
	if fields.on then
		f.on, changed = fields.on == "true", true
	end
	if fields.color and (fields.setcolor or fields.key_enter_field == "color")
			and fields.color:match("^#%x%x%x%x%x%x$") then
		f.color, changed = fields.color:upper(), true
	end
	for i, c in ipairs(FOG_COLORS) do
		if fields["fogc_" .. i] then
			f.color, f.on, changed = c[2], true, true
		end
	end
	for _, k in ipairs({"distance", "start"}) do
		local ev = fields[k] and core.explode_scrollbar_event(fields[k])
		if ev and ev.type == "CHG" then
			f[k] = k == "start" and ev.value / 100 or ev.value
			changed = true
		end
	end
	if changed then
		set_fog(f)
	end
	if not fields.close and not fields.quit then
		core.show_formspec(player:get_player_name(), formname, fog_form())
	end
	return true
end)
core.register_chatcommand("intro_fog", {
	description = "The opening's fog: its colour, how far you see, where it starts",
	func = function(name)
		core.show_formspec(name, "nhv:intro_fog", fog_form())
		return true
	end,
})

-- ---------------------------------------------------------------- the camera's light
-- how bright (a light level, 0 none)
function intro_editor.light()
	return tonumber(storage:get_string("light")) or 10
end
core.register_chatcommand("intro_light", {
	params = "[0-14]",
	description = "The light that goes with the opening's camera: how bright (0 none)",
	func = function(_, param)
		local n = tonumber(param)
		if not n then
			return true, "The camera's light: " .. intro_editor.light() .. " (0 none, 14 the brightest)."
		end
		n = math.max(0, math.min(14, math.floor(n + 0.5)))
		storage:set_string("light", tostring(n))
		if core.nhv_hero_light then
			core.nhv_hero_light(n)
		end
		return true, "The camera's light: " .. n .. "."
	end,
})

-- ---------------------------------------------------------------- markers out of the way
-- The camera points' boxes and the signs' blocks are only the editor's: a
-- preview takes them away (the signs' pictures stay) and puts them back
-- after - kept in storage meanwhile, so a preview cut short (the game
-- closed) gets them back next time.
function intro_editor.hide_markers()
	local hidden = load_list("hidden")
	for k in pairs(cams()) do
		local pos = core.string_to_pos("(" .. k .. ")")
		local node = core.get_node(pos)
		if node.name == "nhv:intro_cam" then
			hidden[k] = {name = node.name, param2 = node.param2}
			core.swap_node(pos, {name = "air"})
		end
	end
	for k in pairs(load_list("signs")) do
		local pos = core.string_to_pos("(" .. k .. ")")
		local node = core.get_node(pos)
		if node.name == "nhv:intro_sign" then
			hidden[k] = {name = node.name, param2 = node.param2}
			core.swap_node(pos, {name = "air"})
		end
	end
	save_list("hidden", hidden)
end
function intro_editor.show_markers()
	local hidden = load_list("hidden")
	local list = cams()
	local left = {} -- (where the map isn't loaded yet: next time)
	for k, n in pairs(hidden) do
		local pos = core.string_to_pos("(" .. k .. ")")
		local here = core.get_node(pos).name
		if here == "air" then
			core.swap_node(pos, {name = n.name, param2 = n.param2})
			if n.name == "nhv:intro_cam" and list[k] then
				core.get_meta(pos):set_string("infotext", "Camera point " .. list[k].index)
			end
		elseif here == "ignore" then
			left[k] = n
		end
	end
	save_list("hidden", left)
	if next(left) then
		core.after(2, intro_editor.show_markers)
	end
end

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
				time = intro_editor.time(), fog = intro_editor.fog(), light = intro_editor.light(),
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
