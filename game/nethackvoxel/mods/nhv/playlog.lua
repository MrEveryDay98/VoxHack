-- The play log, for finding what went wrong in a game: "/playlog on" (in
-- the command line, T) starts it, "/playlog off" stops it - on, it stays
-- on through restarts (the world's mod storage). Each time it starts, a
-- new file in the world's folder, playlogs/playlog_<date>_<time>.txt, with
-- every line timed (seconds since it started, and the game time in turns):
--   ACT     what you did (the keys sent NetHack, and what for)
--   ANS     an answer to a question (a key, text, a menu's choices)
--   REQ     what NetHack's asking (a command, a direction, a menu...)
--   EV      what NetHack said: messages, sounds, combat...
--   SNAP    a turn's result: turns passed, your HP, your square
--   CTRL    the keys and buttons you're holding, when that changes
--   STATE   the clock (its rate, an action's time still to play out),
--           whether NetHack's waiting, where you are and look - when it
--           changes, checked 4 times a second
--   MON     each monster within 20 nodes: its body, square, flags, what
--           it's after, its speed - when that changes
--   GONE    a monster out of the log's sight (dead, gone, too far)
-- Off, it does nothing.

local nh = nhv.nh

local playlog = {}
nhv.playlog = playlog

local storage = core.get_mod_storage()
local SAMPLE_S = 0.25 -- (seconds between looks at the state and monsters)
local FLUSH_S = 1     -- (seconds between writes to the file)
local NEAR = 20       -- (nodes: monsters farther than this aren't logged)

local path, buf, t0 = nil, {}, 0

local function stamp()
	local clock = nhv.clock
	return ("%8.2f %8.2f "):format((core.get_us_time() - t0) / 1e6, clock and clock.game or 0)
end

local function put(kind, text)
	if path then
		buf[#buf + 1] = stamp() .. kind .. " " .. text
	end
end
playlog.put = put

local function flush()
	if not (path and #buf > 0) then
		return
	end
	local f = io.open(path, "a")
	if f then
		f:write(table.concat(buf, "\n"), "\n")
		f:close()
	end
	buf = {}
end

-- keys as sent (a table of {key/text/menu} or a string): readable
local function keys_text(keys)
	local function k(c)
		if type(c) == "number" then
			c = string.char(c % 256)
		end
		local b = c:byte()
		if b and b < 32 then
			return "^" .. string.char(b + 64)
		end
		return c
	end
	if type(keys) == "string" then
		return (keys:gsub("%c", k))
	end
	local out = {}
	for _, it in ipairs(keys or {}) do
		out[#out + 1] = it.key and k(it.key) or it.text and ("[" .. it.text .. "]") or it.menu and ("{" .. it.menu .. "}")
			or "?"
	end
	return table.concat(out, " ")
end

local function info_text(info)
	if type(info) ~= "table" then
		return ""
	end
	local out = {}
	for key, v in pairs(info) do
		if type(v) ~= "table" and type(v) ~= "function" and type(v) ~= "userdata" then
			out[#out + 1] = key .. "=" .. tostring(v)
		end
	end
	table.sort(out)
	return table.concat(out, " ")
end

-- ---------------------------------------------------------------- hooks
-- (wrapped once, at load: each does nothing more while the log's off)
local act, answer_key, answer_text, answer_menu = nh.act, nh.answer_key, nh.answer_text, nh.answer_menu
function nh.act(keys, info)
	put("ACT", keys_text(keys) .. " | " .. info_text(info))
	return act(keys, info)
end
function nh.answer_key(k)
	put("ANS", "key " .. keys_text({{key = type(k) == "number" and string.char(k % 256) or k}}))
	return answer_key(k)
end
function nh.answer_text(t)
	put("ANS", "text [" .. tostring(t) .. "]")
	return answer_text(t)
end
function nh.answer_menu(sels)
	put("ANS", "menu {" .. tostring(sels) .. "}")
	return answer_menu(sels)
end

nh.on_event(function(evs)
	if not path then
		return
	end
	for _, ev in ipairs(evs) do
		put("EV", tostring(ev.kind) .. ": " .. tostring(ev.text):gsub("\n", " / "))
	end
end)

nh.on_snapshot(function(snap, action)
	if not (path and snap and snap.hero) then
		return
	end
	local h = snap.hero
	put("SNAP", ("moves=%s hp=%s/%s at %s,%s dlvl=%s | %s"):format(tostring(h.moves), tostring(h.hp),
		tostring(h.hpmax), tostring(h.x), tostring(h.y), tostring(h.depth), info_text(action)))
end)

-- ---------------------------------------------------------------- watching
local last = {}       -- what was last put for each thing watched
local mons_seen = {}  -- id -> true: logged last time

local function flag_names(flags)
	local MF = nhv.sim and nhv.sim.MF
	if not MF then
		return tostring(flags)
	end
	local out = {}
	for name, bit in pairs(MF) do
		if math.floor((flags or 0) / bit) % 2 == 1 then
			out[#out + 1] = name
		end
	end
	table.sort(out)
	return table.concat(out, ",")
end

local function changed(key, text)
	if last[key] == text then
		return false
	end
	last[key] = text
	return true
end

local function req_text()
	local r = nh.req
	if not r then
		return "-"
	end
	return ("%s%s %q"):format(tostring(r.kind), r.for_command and "(command)" or "", tostring(r.prompt or ""):sub(1, 80))
end

local CONTROLS = {"up", "down", "left", "right", "jump", "aux1", "sneak", "dig", "place", "zoom"}

local function sample(player)
	local clock = nhv.clock
	-- the keys held
	local c = player:get_player_control()
	local held = {}
	for _, k in ipairs(CONTROLS) do
		if c[k] then
			held[#held + 1] = k
		end
	end
	local ctrl = #held > 0 and table.concat(held, " ") or "-"
	if changed("ctrl", ctrl) then
		put("CTRL", ctrl)
	end
	-- the clock, NetHack, you
	local p = player:get_pos()
	local state = ("rate=%.2f owed=%.2f built=%.2f busy=%s | nh=%s req=%s ready=%s | at %s look %.0f/%.0f"):format(
		clock.scale, clock.debt, clock.acc, tostring(clock.busy()), tostring(nh.state), req_text(), tostring(nh.ready()),
		core.pos_to_string(p, 1), math.deg(player:get_look_horizontal()), math.deg(player:get_look_vertical()))
	if changed("state", state) then
		put("STATE", state)
	end
	if changed("req", req_text()) then
		put("REQ", req_text())
	end
	-- the monsters near
	local now = {}
	for id, e in pairs(nhv.sim and nhv.sim.mons or {}) do
		if e.pos and vector.distance(vector.new(e.pos.x, p.y, e.pos.z), p) <= NEAR then
			now[id] = true
			local text = ("%d %s body %s sq %s,%s [%s] target=%s speed=%s%s"):format(id,
				core.nh_mon_name(e.mndx or 0) or "?", core.pos_to_string(e.pos, 1), tostring(e.x), tostring(e.y),
				flag_names(e.flags), tostring(e.target or 0), tostring(e.speed), e.glide and " gliding" or "")
			if changed("mon" .. id, text) then
				put("MON", text)
			end
		end
	end
	for id in pairs(mons_seen) do
		if not now[id] then
			put("GONE", tostring(id))
			last["mon" .. id] = nil
		end
	end
	mons_seen = now
end

-- ---------------------------------------------------------------- on, off
function playlog.on()
	return path ~= nil
end

function playlog.start()
	local dir = core.get_worldpath() .. DIR_DELIM .. "playlogs"
	core.mkdir(dir)
	path = dir .. DIR_DELIM .. "playlog_" .. os.date("%Y%m%d_%H%M%S") .. ".txt"
	buf, last, mons_seen = {}, {}, {}
	t0 = core.get_us_time()
	storage:set_string("playlog", "on")
	put("LOG", "started " .. os.date("%Y-%m-%d %H:%M:%S") .. " (columns: seconds, game turns)")
	return path
end

function playlog.stop()
	put("LOG", "stopped")
	flush()
	path = nil
	storage:set_string("playlog", "")
end

core.register_chatcommand("playlog", {
	params = "[on|off]",
	description = "Log everything you do and what the game does, to the world's playlogs folder",
	func = function(_, param)
		param = param:lower()
		if param == "on" then
			if path then
				playlog.stop()
			end
			return true, "Play log on: " .. playlog.start()
		elseif param == "off" then
			if not path then
				return true, "The play log is off."
			end
			local was = path
			playlog.stop()
			return true, "Play log off. It's in " .. was
		end
		return true, path and ("The play log is on: " .. path) or "The play log is off. /playlog on starts it."
	end,
})

local sample_t, flush_t = 0, 0
core.register_globalstep(function(dtime)
	if not path then
		return
	end
	sample_t, flush_t = sample_t + dtime, flush_t + dtime
	local player = core.get_connected_players()[1]
	if player and sample_t >= SAMPLE_S then
		sample_t = 0
		sample(player)
	end
	if flush_t >= FLUSH_S then
		flush_t = 0
		flush()
	end
end)

core.register_on_shutdown(flush)

-- (on from last time: a new file)
if storage:get_string("playlog") == "on" then
	core.after(0, playlog.start)
end

return playlog
