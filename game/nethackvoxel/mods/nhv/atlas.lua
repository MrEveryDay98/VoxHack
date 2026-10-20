-- The level atlas: every level of a game, built side by side, to see how
-- the prefabs fit together in real levels.
--
-- A world with a file named "nhv_atlas" holding a seed (made by
-- tools/make_atlas_world.py) is an atlas. The first time it's opened a game
-- is started in debug mode with that seed (the same seed builds the same
-- dungeon) and every level is visited (#nhvgoto) and built with the game's
-- own terrain code - prefabs, hand-built areas, each dungeon's walls - but
-- no monsters or objects. Each level's blocks are copied out into the atlas
-- (the solid filler no open space touches left out, so you see each level's
-- shape): a column per dungeon (the Dungeons of Doom, the Gnomish Mines,
-- the Quest, Fort Ludios, Gehennom, the Elemental Planes), levels one above
-- the other by depth, the deepest at the bottom. The dungeons you climb
-- (Sokoban, Vlad's Tower) go off to the side instead: side by side at the
-- height of their entrance, the way in first. Then you fly about freely
-- (K: fly, H: noclip; always midday).
--
--   /atlas            the levels and their numbers
--   /atlas <number>   go to that level
--   /atlas ceilings   take every ceiling off (again: put them back)
--   /atlas ceilings   take every ceiling off (again: put them back)

local U = nhv.util
local nh = nhv.nh
local terrain = nhv.terrain
local prefabs = nhv.prefabs
local storage = core.get_mod_storage()

local atlas = {}
nhv.atlas = atlas

local SEED = math.max(1, math.floor(tonumber(nhv.ATLAS) or 1))
local LW, LD = U.COLNO * U.TILE, U.ROWNO * U.TILE -- (a level's width, depth)
local X0 = LW + 160      -- (the first column: clear of the live level at x 0)
local GAP_X = 48         -- (between columns)
local SPACING = prefabs.H + 7 -- (between levels, one above the other)
local SRC_MIN = vector.new(0, prefabs.Y0, 0)
local SRC_MAX = vector.new(LW - 1, prefabs.Y0 + prefabs.H - 1, LD - 1)
local DONE_KEY = "atlas_done_" .. SEED

-- where a level goes: the shift from the live level's place (x: the
-- dungeon's column, and along it for a dungeon you climb; y: by depth)
local function shift_for(x, depth)
	return vector.new(X0 + x, -(depth - 1) * SPACING, 0)
end

-- ---------------------------------------------------------------- labels
core.register_entity("nhv:atlas_label", {
	initial_properties = {
		visual = "sprite", textures = {"blank.png"}, physical = false, pointable = false,
		static_save = false, nametag_color = "#FFE070", nametag_bgcolor = "#000000A0",
	},
})

local function place_label(e)
	local p = vector.new(e.shift.x + LW / 2, e.shift.y + prefabs.Y0 + prefabs.H + 2, e.shift.z - 4)
	local obj = core.add_entity(p, "nhv:atlas_label")
	if obj then
		obj:set_nametag_attributes({text = ("%d  %s"):format(e.n, e.label)})
	end
end

-- doors and object sprites are entities (not saved): put back over a level
local function dress(e)
	local minp = vector.add(SRC_MIN, e.shift)
	local maxp = vector.add(SRC_MAX, e.shift)
	core.emerge_area(minp, maxp, function(_, _, remaining)
		if remaining == 0 then
			nhv.doors.refresh(minp, maxp)
			nhv.props.refresh(minp, maxp)
		end
	end)
end

-- ---------------------------------------------------------------- copying
-- blocks you can't see through (a full cube drawn solid): filler when every
-- side touches another such block
local opaque_cache = {}
local AIR = core.get_content_id("air")
local function opaque(id)
	local o = opaque_cache[id]
	if o == nil then
		local def = core.registered_nodes[core.get_name_from_content_id(id)]
		local dt = def and (def.drawtype or "normal")
		o = def ~= nil and dt == "normal" and def.use_texture_alpha ~= "clip"
			and def.use_texture_alpha ~= "blend"
		opaque_cache[id] = o
	end
	return o
end

-- the live level's blocks (just built at the usual place) to the atlas,
-- leaving out the filler: an opaque block with opaque blocks on all six
-- sides (beyond the level counts as solid) is never seen
local function copy_level(shift, done)
	local vm = core.get_voxel_manip()
	local e1, e2 = vm:read_from_map(SRC_MIN, SRC_MAX)
	local sa = VoxelArea(e1, e2)
	local ids, p2s = vm:get_data(), vm:get_param2_data()
	local keep = {}
	local sx, sy, sz = sa.ystride and 1, sa.ystride, sa.zstride
	for z = SRC_MIN.z, SRC_MAX.z do
		for y = SRC_MIN.y, SRC_MAX.y do
			local i = sa:index(SRC_MIN.x, y, z)
			for x = SRC_MIN.x, SRC_MAX.x do
				local id = ids[i]
				if not opaque(id) then
					keep[i] = true
				else
					local function open(dx, dy, dz, j)
						return x + dx >= SRC_MIN.x and x + dx <= SRC_MAX.x
							and y + dy >= SRC_MIN.y and y + dy <= SRC_MAX.y
							and z + dz >= SRC_MIN.z and z + dz <= SRC_MAX.z
							and not opaque(ids[j])
					end
					if open(-1, 0, 0, i - sx) or open(1, 0, 0, i + sx) or open(0, -1, 0, i - sy)
							or open(0, 1, 0, i + sy) or open(0, 0, -1, i - sz) or open(0, 0, 1, i + sz) then
						keep[i] = true
					end
				end
				i = i + 1
			end
		end
	end
	local dmin, dmax = vector.add(SRC_MIN, shift), vector.add(SRC_MAX, shift)
	core.emerge_area(dmin, dmax, function(_, _, remaining)
		if remaining > 0 then
			return
		end
		local dv = core.get_voxel_manip()
		local d1, d2 = dv:read_from_map(dmin, dmax)
		local da = VoxelArea(d1, d2)
		local dids, dp2 = dv:get_data(), dv:get_param2_data()
		for z = SRC_MIN.z, SRC_MAX.z do
			for y = SRC_MIN.y, SRC_MAX.y do
				local si = sa:index(SRC_MIN.x, y, z)
				local di = da:index(SRC_MIN.x + shift.x, y + shift.y, z + shift.z)
				for _ = SRC_MIN.x, SRC_MAX.x do
					if keep[si] then
						dids[di], dp2[di] = ids[si], p2s[si]
					else
						dids[di], dp2[di] = AIR, 0
					end
					si, di = si + 1, di + 1
				end
			end
		end
		dv:set_data(dids)
		dv:set_param2_data(dp2)
		dv:write_to_map(true)
		done()
	end)
end

-- ---------------------------------------------------------------- the run
local run = nil -- {queue = {...}, i = n, sent = bool, busy = bool}

local function say(text)
	core.log("action", "[nhv atlas] " .. text)
	core.chat_send_all(text)
end

local function make_queue()
	local queue, planes = {}, {}
	local x = 0 -- (the next column's left edge)
	for i, d in ipairs(core.nh_get_dungeons() or {}) do
		local dnum = i - 1
		-- (climbed: you come in at the last level, at the bottom)
		local climbed = d.levels > 1 and d.entry == d.levels
		local entry_depth = d.depth_start + d.levels - 1
		local n = 0
		for l = 1, d.levels do
			local proto = core.nh_level_proto(dnum, l) or ""
			if proto ~= "dummy" then
				local depth = d.depth_start + l - 1
				local e = {dnum = dnum, level = l, depth = depth,
					label = d.name .. " " .. l .. (proto ~= "" and (" - " .. proto) or "")
						.. "  (depth " .. depth .. ")"}
				if climbed then
					-- side by side at the entrance's height, the way in first
					e.shift = shift_for(x + (d.levels - l) * (LW + GAP_X), entry_depth)
				else
					e.shift = shift_for(x, depth)
				end
				n = n + 1
				-- (the Planes last: once there, the way back is gone)
				table.insert(d.name:find("Plane") and planes or queue, e)
			end
		end
		if n > 0 then
			x = x + (climbed and n or 1) * (LW + GAP_X)
		end
	end
	for _, e in ipairs(planes) do
		queue[#queue + 1] = e
	end
	for n, e in ipairs(queue) do
		e.n = n
	end
	return queue
end

local function finish()
	local list = {}
	for _, e in ipairs(run.queue) do
		if e.built then
			list[#list + 1] = {n = e.n, label = e.label, shift = e.shift}
		end
	end
	storage:set_string(DONE_KEY, core.serialize(list))
	atlas.list = list
	for _, e in ipairs(list) do
		place_label(e)
		dress(e)
	end
	run = nil
	say(("Atlas built: %d levels (seed %d). /atlas lists them, /atlas <number> takes you there.")
		:format(#list, SEED))
	local player = core.get_connected_players()[1]
	if player and list[1] then
		atlas.go(player, 1)
	end
end

-- any question NetHack asks on the way (a level's arrival message, "Die?"
-- in debug mode...): the safe answer
local function answer(r)
	if r.kind == "yn" then
		local c = r.choices or ""
		nh.answer_key((c == "" or c:find("n", 1, true)) and "n" or 27)
	elseif r.kind == "menu" then
		nh.answer_menu("")
	elseif r.kind == "line" then
		nh.answer_text("\27")
	else
		nh.answer_key(27)
	end
end

core.register_globalstep(function()
	if not run or run.busy or nh.state ~= "waiting" or not nh.req then
		return
	end
	local r = nh.req
	if not (r.kind == "key" and r.for_command) then
		answer(r)
		return
	end
	if not run.queue then
		run.queue, run.i = make_queue(), 1
		say(("Building the atlas: %d levels..."):format(#run.queue))
	end
	local e = run.queue[run.i]
	if not e then
		finish()
		return
	end
	if not run.sent then
		run.sent = true
		nh.act({{key = "#"}, {text = ("nhvgoto %d %d"):format(e.dnum, e.level)}}, {kind = "atlas"})
		return
	end
	-- (arrived: the level as the game builds it, copied out to its place)
	local snap = nh.snap
	if not snap or not snap.map then
		return
	end
	run.busy = true
	terrain.build_all(snap.map)
	copy_level(e.shift, function()
		e.built = true
		if e.n % 10 == 0 then
			say(("%d / %d levels"):format(e.n, #run.queue))
		end
		run.i, run.sent, run.busy = run.i + 1, false, false
	end)
end)

-- ---------------------------------------------------------------- player
-- always noon: the sun overhead (the clock put back now and then, rather
-- than a time_speed setting, which would end up in your settings)
local noon_t = 0
core.register_globalstep(function(dtime)
	noon_t = noon_t - dtime
	if noon_t <= 0 then
		noon_t = 5
		core.set_timeofday(0.5)
	end
end)

function atlas.go(player, n)
	local e = atlas.list and atlas.list[n]
	if not e then
		return false
	end
	player:set_pos(vector.new(e.shift.x + LW / 2, e.shift.y + prefabs.Y0 + prefabs.H + 4, e.shift.z - 12))
	player:set_look_horizontal(0)
	player:set_look_vertical(0.6)
	return true
end

core.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	local privs = core.get_player_privs(name)
	privs.fly, privs.fast, privs.noclip = true, true, true
	core.set_player_privs(name, privs)
	-- the world's own light and shading (room lights, the sun where there's
	-- no ceiling, shadows), always at midday
	player:set_sky({type = "regular", clouds = false})
	player:set_sun({visible = true, sunrise_visible = false})
	player:set_moon({visible = false})
	player:set_stars({visible = false})
	player:override_day_night_ratio(1)
	player:set_lighting({shadows = {intensity = 0.33}})
	player:hud_set_flags({nhv_fullbright = false, minimap = false, minimap_radar = false})
	player:set_physics_override({speed = 2, gravity = 0})
	player:set_properties({eye_height = 1.6, visual_size = {x = 0, y = 0}})
	local list = core.deserialize(storage:get_string(DONE_KEY))
	if list then
		atlas.list = list
		for _, e in ipairs(list) do
			place_label(e)
			dress(e)
		end
		core.after(1, function()
			if player:is_player() then
				atlas.go(player, 1)
				core.chat_send_player(name, ("Level atlas, seed %d: %d levels. /atlas lists them, "
					.. "/atlas <number> takes you there. K: fly, H: noclip."):format(SEED, #list))
			end
		end)
		return
	end
	-- (the first time: build it)
	player:set_pos(vector.new(X0, 200, -40))
	local dir = core.get_worldpath() .. DIR_DELIM .. "nethack"
	core.mkdir(dir)
	core.safe_file_write(dir .. DIR_DELIM .. "nhv_seed", tostring(SEED))
	run = {}
	core.after(1, function()
		local ok, err = nh.start("wizard", table.concat({
			"OPTIONS=playmode:debug,!tutorial,!autopickup,pettype:none",
			"OPTIONS=role:valkyrie,race:human,gender:female,align:neutral",
		}, "\n"))
		if not ok then
			say("Could not start NetHack for the atlas: " .. tostring(err))
			run = nil
		end
	end)
end)

-- the pause menu's Quit
core.register_chatcommand("nhvtitle", {
	description = "(VoxHack) leave",
	func = function(pname)
		core.disconnect_player(pname, "nhv:quit")
		return true
	end,
})

-- ---------------------------------------------------------------- ceilings
-- /atlas ceilings: every level's ceiling (the ceiling layer and anything
-- left above it) taken off, to look down into the levels; again puts them
-- back. What was taken off is kept in a file in the world
-- (atlas_ceilings.dat), so they come back after a restart too.
local CEIL_FILE = core.get_worldpath() .. DIR_DELIM .. "atlas_ceilings.dat"
local CEIL_MIN = vector.new(0, prefabs.Y0 + prefabs.CEIL, 0)
local CEIL_MAX = vector.new(LW - 1, prefabs.Y0 + prefabs.H - 1, LD - 1)

local function ceilings_off()
	local f = io.open(CEIL_FILE, "rb")
	if f then
		f:close()
		return true
	end
	return false
end

local function each_level_region(fn)
	for _, e in ipairs(atlas.list) do
		local minp, maxp = vector.add(CEIL_MIN, e.shift), vector.add(CEIL_MAX, e.shift)
		local vm = core.get_voxel_manip()
		local e1, e2 = vm:read_from_map(minp, maxp)
		local va = VoxelArea(e1, e2)
		local ids, p2 = vm:get_data(), vm:get_param2_data()
		-- (k: the node's place in minp..maxp, row by row)
		local k = 0
		local function each(visit)
			k = 0
			for z = minp.z, maxp.z do
				for y = minp.y, maxp.y do
					local i = va:index(minp.x, y, z)
					for _ = minp.x, maxp.x do
						k = k + 1
						visit(i, k)
						i = i + 1
					end
				end
			end
		end
		if fn(e, ids, p2, each) then
			vm:set_data(ids)
			vm:set_param2_data(p2)
			vm:write_to_map(true)
		end
	end
end

function atlas.toggle_ceilings()
	if not ceilings_off() then
		-- off: what's there is written down ("k name p2" per node), then air
		local saved = {}
		each_level_region(function(e, ids, p2, each)
			local out = {}
			each(function(i, k)
				if ids[i] ~= AIR then
					out[#out + 1] = ("%d %s %d"):format(k, core.get_name_from_content_id(ids[i]), p2[i])
					ids[i], p2[i] = AIR, 0
				end
			end)
			saved[#saved + 1] = e.n .. "\n" .. table.concat(out, "\n")
			return #out > 0
		end)
		core.safe_file_write(CEIL_FILE, core.compress(table.concat(saved, "\n\n"), "deflate"))
		return "Ceilings off (/atlas ceilings puts them back)."
	end
	-- back on
	local f = io.open(CEIL_FILE, "rb")
	local data = core.decompress(f:read("*a"), "deflate")
	f:close()
	local by_level = {}
	for block in (data .. "\n\n"):gmatch("(.-)\n\n") do
		local n, rest = block:match("^(%d+)\n?(.*)$")
		if n then
			by_level[tonumber(n)] = rest
		end
	end
	each_level_region(function(e, ids, p2, each)
		local rest = by_level[e.n]
		if not rest or rest == "" then
			return false
		end
		local put = {}
		for k, name, pp in rest:gmatch("(%d+) (%S+) (%d+)") do
			put[tonumber(k)] = {core.get_content_id(name), tonumber(pp)}
		end
		each(function(i, k)
			local v = put[k]
			if v then
				ids[i], p2[i] = v[1], v[2]
			end
		end)
		return true
	end)
	os.remove(CEIL_FILE)
	return "Ceilings back on."
end

core.register_chatcommand("atlas", {
	description = "(VoxHack level atlas) list the levels, go to one, or take the ceilings off / put them back",
	params = "[number | ceilings]",
	func = function(name, param)
		if not atlas.list then
			return false, "The atlas isn't built yet."
		end
		if param:match("^%s*ceil") then
			return true, atlas.toggle_ceilings()
		end
		local n = tonumber(param)
		if n then
			local player = core.get_player_by_name(name)
			local ok = player and atlas.go(player, n)
			return ok and true or false, ok and atlas.list[n].label or ("No level " .. n .. ".")
		end
		local out = {}
		for _, e in ipairs(atlas.list) do
			out[#out + 1] = ("%d  %s"):format(e.n, e.label)
		end
		return true, table.concat(out, "\n")
	end,
})

return atlas
