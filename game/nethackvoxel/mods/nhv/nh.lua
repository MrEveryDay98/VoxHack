-- Driver for the NetHack engine (nethack.dll via core.nh_*).
--
-- NetHack runs on its own thread and blocks whenever it needs input. Each
-- server step we check whether it is waiting; when it is, we take a
-- snapshot of the game, let the other modules update the world from it,
-- and then either answer the pending request or wait for the player.

local U = nhv.util
local nh = {
	state = "not_started",
	req = nil,        -- current request table (when waiting)
	snap = nil,       -- latest snapshot {map, hero, monsters, inventory}
	snap_serial = 0,  -- increments with each new snapshot
	listeners = {},   -- snapshot listeners
	event_listeners = {},
	req_listeners = {},
	pending_action = nil, -- action awaiting its result
	glyph_cache = {},
	cmap_cache = {},
}
nhv.nh = nh

function nhv.glyph_info(g)
	local gi = nh.glyph_cache[g]
	if not gi then
		gi = core.nh_glyph_info(g) or {kind = "none", index = -1, tile = -1}
		nh.glyph_cache[g] = gi
	end
	return gi
end

function nhv.cmap_name(i)
	local n = nh.cmap_cache[i]
	if not n then
		n = core.nh_cmap_name(i) or ""
		nh.cmap_cache[i] = n
	end
	return n
end

function nh.on_snapshot(fn)
	table.insert(nh.listeners, fn)
end

function nh.on_event(fn)
	table.insert(nh.event_listeners, fn)
end

-- fn(req) returns true if it handled the request
function nh.on_request(fn)
	table.insert(nh.req_listeners, fn)
end

local function datadir()
	return core.get_modpath("nhv") .. DIR_DELIM .. "nhdata"
end

local function userdir()
	return core.get_worldpath() .. DIR_DELIM .. "nethack"
end

-- (the player's own choices come from Options > NetHack options, nhopts.lua)
nh.OPTIONS = table.concat({
	"OPTIONS=!tutorial,!legacy,!splash_screen,!rest_on_space",
	"OPTIONS=time,showexp,!mention_walls,suppress_alert:3.4.3,voices",
}, "\n")

function nh.start(name)
	if nh.state ~= "not_started" and nh.state ~= "ended" then
		return true
	end
	core.nh_unload()
	nh.glyph_cache, nh.cmap_cache = {}, {}
	nh.req, nh.snap, nh.pending_action = nil, nil, nil
	-- extra options from the player's config (e.g. to pre-pick a role)
	-- ("\n" in the setting separates lines)
	local extra = (core.settings:get("nhv_extra_options") or ""):gsub("\\n", "\n")
	-- a world with a file named "nhv_debug" in it plays in NetHack's debug
	-- (wizard) mode; NetHack also requires the character to be named "wizard"
	local dbg = io.open(core.get_worldpath() .. DIR_DELIM .. "nhv_debug", "r")
	if dbg then
		dbg:close()
		extra = extra .. "\nOPTIONS=playmode:debug"
	end
	local own = nhv.nhopts and nhv.nhopts.start_options() or ""
	local ok, err = core.nh_start(datadir(), userdir(), nh.OPTIONS .. "\n" .. own .. "\n" .. extra, name)
	if not ok then
		core.log("error", "[nhv] could not start NetHack: " .. tostring(err))
		return false, err
	end
	core.nh_set_freemove(true)
	nh.state = "busy"
	return true
end

function nh.ready()
	return nh.state == "waiting" and nh.req and nh.req.kind == "key" and nh.req.for_command
end

local function take_snapshot()
	local snap = {
		map = core.nh_get_map(),
		hero = core.nh_get_hero(),
		monsters = core.nh_get_monsters(),
		inventory = core.nh_get_inventory(),
	}
	-- before the game proper starts (character selection) there is no
	-- dungeon to look at yet
	if not snap.map or not snap.hero or snap.hero.ledger == 0 then
		return nil
	end
	nh.snap_serial = nh.snap_serial + 1
	snap.serial = nh.snap_serial
	return snap
end

-- Re-read the game state while NetHack is waiting (e.g. after monsters
-- changed squares) and notify listeners.
function nh.refresh()
	if nh.state ~= "waiting" then
		return
	end
	local snap = take_snapshot()
	if snap then
		nh.snap = snap
		for _, fn in ipairs(nh.listeners) do
			fn(snap, {kind = "refresh"})
		end
	end
end

-- Send keys for an action. keys: string (each char a key) or list of
-- {key=}/{text=}/{menu=} items. info is kept until the result arrives.
function nh.act(keys, info)
	if type(keys) == "string" then
		for c in keys:gmatch(".") do
			core.nh_send_key(c)
		end
	else
		for _, k in ipairs(keys) do
			if k.key then
				core.nh_send_key(k.key)
			elseif k.text then
				core.nh_send_text(k.text)
			elseif k.menu then
				core.nh_send_menu(k.menu)
			end
		end
	end
	nh.pending_action = info or {}
	nh.pending_action.t0 = core.get_us_time()
	nh.state = "busy"
	nh.req = nil
	-- most actions resolve within a few milliseconds; wait briefly so the
	-- result shows up in this same server step
	nh.pump(40)
end

-- Answer the current (non-command) request.
function nh.answer_key(k)
	core.nh_send_key(k)
	nh.state, nh.req = "busy", nil
	nh.pump(40)
end

function nh.answer_text(t)
	core.nh_send_text(t)
	nh.state, nh.req = "busy", nil
	nh.pump(40)
end

function nh.answer_menu(sels)
	core.nh_send_menu(sels)
	nh.state, nh.req = "busy", nil
	nh.pump(40)
end

local function dispatch_events()
	local evs = core.nh_poll_events()
	if #evs == 0 then
		return
	end
	for _, fn in ipairs(nh.event_listeners) do
		fn(evs)
	end
end

-- Poll the engine; waits up to wait_ms for it to settle.
function nh.pump(wait_ms)
	if nh.state == "not_started" then
		return
	end
	local st = core.nh_wait(wait_ms or 0)
	dispatch_events()
	if st == nh.state and st ~= "waiting" then
		return
	end
	if st == "waiting" then
		local was_waiting = nh.state == "waiting" and nh.req
		nh.state = "waiting"
		if was_waiting then
			return
		end
		nh.req = core.nh_request()
		local snap = take_snapshot()
		if snap then
			local action = nh.pending_action
			nh.pending_action = nil
			nh.snap = snap
			for _, fn in ipairs(nh.listeners) do
				fn(snap, action)
			end
		end
		for _, fn in ipairs(nh.req_listeners) do
			if fn(nh.req) then
				break
			end
		end
	elseif st == "ended" then
		nh.state = "ended"
		nh.req = nil
		dispatch_events()
		for _, fn in ipairs(nh.listeners) do
			fn(nil, {ended = true, exit_code = core.nh_exit_code()})
		end
	else
		nh.state = st
	end
end

core.register_globalstep(function()
	nh.pump(0)
end)

core.register_on_shutdown(function()
	-- Save the game when the world closes.
	if nh.state == "waiting" or nh.state == "busy" then
		core.nh_clear_input()
		if nh.state == "busy" then
			core.nh_wait(2000)
		end
		-- escape out of any prompt, then save
		for _ = 1, 4 do
			local r = core.nh_request()
			if not r or r.kind == "none" or (r.kind == "key" and r.for_command) then
				break
			end
			core.nh_send_key(27)
			core.nh_wait(500)
		end
		core.nh_send_key("S")
		core.nh_wait(500)
		local r = core.nh_request()
		if r and r.kind == "yn" then
			core.nh_send_key("y")
		end
		core.nh_wait(5000)
	end
end)

return nh
