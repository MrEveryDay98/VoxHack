-- Jumping: hold Space (a tap still waits a turn). Held a moment, the
-- squares NetHack would let you jump to (a Knight's L-shaped ones, any
-- nearby with jumping boots...) light up green on the floor; the one you
-- look at is brighter, and letting go of Space jumps there (#nhvjump: the
-- same jump as NetHack's #jump, with all its checks). The body hops there
-- (player.lua). Looking at none of them, letting go does nothing. When you
-- can jump but not right now (burdened, levitating, held...), letting go
-- tries #jump, and NetHack says why.

local U = nhv.util
local nh = nhv.nh

local jump = {}
nhv.jump = jump

local HOLD_US = 250000 -- (held this long: aiming a jump, not a tap)
local MARK = "[fill:16x16:#30E83070^[fill:12x12:2,2:#30E83038"
local MARK_ON = "[fill:16x16:#60FF60D0^[fill:12x12:2,2:#60FF6078"

core.register_entity("nhv:jumpmark", {
	initial_properties = {
		visual = "upright_sprite",
		visual_size = {x = U.TILE * 0.86, y = U.TILE * 0.86},
		textures = {MARK, MARK},
		use_texture_alpha = true,
		physical = false,
		pointable = false,
		collisionbox = {0, 0, 0, 0, 0, 0},
		glow = 10,
		static_save = false,
	},
})

local state = nil -- nil, "pending" (just pressed), "aim", "not_now", "none"
local down_at = 0
local squares = {} -- {x=, y=, e=entity}
local target = nil -- the square looked at
local list_for = nil -- (the hero square the list is for)
local list_t = 0

local function clear_marks()
	for _, s in ipairs(squares) do
		if s.e and s.e:get_pos() then
			s.e:remove()
		end
	end
	squares, target, list_for = {}, nil, nil
end

-- (where a jump could land now, from NetHack, with a mark on each)
local function refresh(h)
	local list, status = core.nh_jump_squares()
	clear_marks()
	list_for = h.x .. "," .. h.y
	list_t = core.get_us_time()
	if status ~= "ok" then
		return status
	end
	for _, sq in ipairs(list) do
		local c = U.tile_center(sq.x, sq.y, nhv.terrain.stand_y(sq.x, sq.y) + 0.04)
		local e = core.add_entity(c, "nhv:jumpmark")
		if e then
			e:set_rotation(vector.new(math.pi / 2, 0, 0)) -- (lying on the floor)
		end
		squares[#squares + 1] = {x = sq.x, y = sq.y, e = e, c = c}
	end
	return "ok"
end

-- the square you look at: where your look meets the floor, or else the one
-- closest to the crosshair's direction
local function looked_at(player)
	local eye = vector.add(player:get_pos(), vector.new(0, 1.6, 0))
	local look = player:get_look_dir()
	local best, best_d
	if look.y < -0.05 then
		for _, s in ipairs(squares) do
			local t = (s.c.y - eye.y) / look.y
			local hit = vector.add(eye, vector.multiply(look, t))
			local d = math.max(math.abs(hit.x - s.c.x), math.abs(hit.z - s.c.z))
			if d < U.TILE * 0.75 and (not best_d or d < best_d) then
				best, best_d = s, d
			end
		end
	end
	if best then
		return best
	end
	local lx, lz = look.x, look.z
	local ll = math.sqrt(lx * lx + lz * lz)
	if ll < 1e-3 then
		return nil
	end
	for _, s in ipairs(squares) do
		local dx, dz = s.c.x - eye.x, s.c.z - eye.z
		local dl = math.sqrt(dx * dx + dz * dz)
		local a = dl > 1e-3 and math.acos(math.max(-1, math.min(1, (dx * lx + dz * lz) / (dl * ll)))) or math.pi
		if a < 0.35 and (not best_d or a < best_d) then
			best, best_d = s, a
		end
	end
	return best
end

local function set_target(s)
	if s == target then
		return
	end
	if target and target.e and target.e:get_pos() then
		target.e:set_properties({textures = {MARK, MARK}})
	end
	target = s
	if s and s.e and s.e:get_pos() then
		s.e:set_properties({textures = {MARK_ON, MARK_ON}})
	end
end

local function can_act()
	return nh.ready() and not nhv.clock.busy() and not nhv.ui.open and not nhv.ui.menu_open
		and not nhv.ui.chat_open
end

function jump.press()
	state, down_at = "pending", core.get_us_time()
end

-- each step, with whether Space is held
function jump.update(player, held)
	if not state then
		return
	end
	local h = nh.snap and nh.snap.hero
	if not h or nhv.ui.open or nhv.ui.menu_open or nhv.ui.chat_open then
		jump.cancel() -- (a question or a window came up: no jump)
		return
	end
	if held then
		if state == "pending" and core.get_us_time() - down_at >= HOLD_US then
			local status = refresh(h)
			state = status == "ok" and "aim" or status == "not_now" and "not_now" or "none"
		end
		if state == "aim" then
			-- (you walked on while aiming: where you can land now)
			if list_for ~= h.x .. "," .. h.y or core.get_us_time() - list_t > 1000000 then
				if refresh(h) ~= "ok" then
					state = "not_now"
					return
				end
			end
			set_target(looked_at(player))
		end
		return
	end
	-- let go
	local was, to = state, target
	state = nil
	clear_marks()
	if not can_act() then
		return
	end
	if was == "pending" or was == "none" then
		-- (a tap: wait a turn)
		nhv.clock.act({{key = "#"}, {text = "nhvtick"}}, {kind = "wait"})
	elseif was == "not_now" then
		nhv.clock.act({{key = "#"}, {text = "jump"}}, {kind = "jump"}) -- (NetHack says why not)
	elseif was == "aim" and to then
		nhv.clock.act({{key = "#"}, {text = ("nhvjump %d %d"):format(to.x, to.y)}},
			{kind = "jump", tx = to.x, ty = to.y, from_x = h.x, from_y = h.y})
	end
end

-- (a window or a level change while aiming: no marks left lying about)
function jump.cancel()
	state = nil
	clear_marks()
end

return jump
