-- The title's Demos: the demos recorded (Options > Record demos - the
-- VoxHack engine records them, client/nhv_demo.h), newest first, each with
-- its class's picture and "<name>-<dlvl>-<xl>-<date>". One is played with
-- the game let go meanwhile (no game runs as a demo plays), then it's back
-- to the title. One from an older version of VoxHack is red: it asks to be
-- deleted - one this VoxHack can't play (another network protocol), or one
-- from before demos kept their details (it can still be played).
--
-- As you play, the game's details go to the engine (core.nhv_demo_info),
-- kept beside the demo being recorded - what the list shows.

local nh = nhv.nh
local theme = nhv.theme
local E = core.formspec_escape
local U = nhv.util

local demos = {}
nhv.demos = demos

local FORM, DELETE, DELETE_OLD = "nhv:demos", "nhv:demo_delete", "nhv:demo_delete_old"

-- ---------------------------------------------------------------- recording
-- the class: the hero's own monster (a valkyrie, a cave dweller...) - not
-- while polymorphed (what it was before kept)
local role, gender
local sent

nh.on_snapshot(function(snap)
	if not (snap and snap.hero and core.nhv_demo_info) then
		return
	end
	local h = snap.hero
	if h.name == "" then
		return
	end
	if not U.has(h.flags or 0, U.HERO.POLY) and h.mndx and h.mndx >= 0 then
		role = core.nh_mon_name(h.mndx)
		gender = U.has(h.flags or 0, U.HERO.FEMALE) and "female" or "male"
	end
	local info = {name = h.name, role = role or "", gender = gender or "", dlvl = h.depth,
		xl = h.xlvl, version = nhv.title.TAG}
	local key = table.concat({info.name, info.role, info.gender, info.dlvl, info.xl}, "|")
	if key ~= sent then
		sent = key
		core.nhv_demo_info(info)
	end
end)

-- ---------------------------------------------------------------- the list
local SHEET
-- the class's picture (none known: a dark square)
local function icon(d)
	if not SHEET then
		SHEET = {}
		for s, name in pairs(nhv_tiles.sheet_names or {}) do
			SHEET[name] = SHEET[name] or s
		end
	end
	local r, g = d.info.role or "", d.info.gender or ""
	local s = r ~= "" and (SHEET[r .. " (" .. (g ~= "" and g or "male") .. ")"] or SHEET[r])
	return s and nhv_tiles.sheet_texture(s) or "[fill:16x16:#1A1A22"
end

-- <name>-<dlvl>-<xl>-<date> (one from before the game said: what's known)
function demos.title(d)
	local i = d.info
	local name = i.name or (d.name ~= "" and d.name) or "?"
	return ("%s-Dlvl%s-XL%s-%s"):format(name, i.dlvl or "?", i.xl or "?",
		d.date ~= "" and d.date:sub(1, 10) or d.file)
end

-- from an older version: can't be played, or doesn't say what's in it
local function older(d)
	return not d.playable or next(d.info) == nil
end

local function size_text(n)
	if n >= 1024 * 1024 then
		return ("%.1f MB"):format(n / (1024 * 1024))
	end
	return ("%d KB"):format(math.max(1, math.floor(n / 1024 + 0.5)))
end

local list = {} -- (as shown: the buttons' numbers)
local asked -- the one the delete question is about

local function formspec()
	list = core.nhv_demo_list and core.nhv_demo_list() or {}
	local W, H = 16, 10.5
	local LIST_H = H - 3.2
	local fs = {theme.head(W, H),
		"label[0.4,0.5;" .. theme.title("Demos") .. "]",
		("checkbox[0.4,1.25;record;%s;%s]"):format(E("Record demos in future runs"),
			tostring(core.settings:get_bool("nhv_demo_record", false))),
		("scroll_container[0.3,1.8;%s,%s;list;vertical;0.1]"):format(W - 0.9, LIST_H)}
	local y = 0
	if #list == 0 then
		fs[#fs + 1] = ("label[0.1,0.4;%s]"):format(theme.dim(E("No demos yet. With Record demos on, "
			.. "each game you play is recorded, from the next time VoxHack starts.")))
	end
	for i, d in ipairs(list) do
		fs[#fs + 1] = ("image[0.1,%s;0.8,0.8;%s]"):format(y, E(icon(d)))
		local label = demos.title(d)
		if older(d) then
			-- (red: from an older version - it asks to be deleted)
			fs[#fs + 1] = ("style[demo_%d;bgcolor=#B02020;textcolor=#FFFFFF]"):format(i)
			label = label .. "  (older version)"
		end
		fs[#fs + 1] = ("button[1.1,%s;%s,0.8;demo_%d;%s]"):format(y, W - 4.4, i, E(label))
		fs[#fs + 1] = ("label[%s,%s;%s]"):format(W - 3.15, y + 0.4, theme.dim(E(size_text(d.size))))
		y = y + 0.95
	end
	fs[#fs + 1] = "scroll_container_end[]"
	fs[#fs + 1] = ("scrollbaroptions[max=%d;smallstep=10;largestep=60]"):format(
		math.max(0, math.ceil((y - LIST_H) * 10)))
	fs[#fs + 1] = ("scrollbar[%s,1.8;0.3,%s;vertical;list;0]"):format(W - 0.55, LIST_H)
	fs[#fs + 1] = ("label[0.4,%s;%s]"):format(H - 1.25, theme.dim(E(
		"Space pauses a demo, W and S speed it up and slow it down, Esc leaves it.")))
	fs[#fs + 1] = ("button[%s,%s;3,0.8;back;Back]"):format(W / 2 - 1.5, H - 0.95)
	local n = 0
	for _, d in ipairs(list) do
		n = n + (older(d) and 1 or 0)
	end
	if n > 0 then
		fs[#fs + 1] = ("button[%s,%s;4.2,0.8;delete_old;%s]"):format(W - 4.6, H - 0.95,
			E(("Delete older demos (%d)"):format(n)))
	end
	return table.concat(fs)
end

local function delete_formspec(d)
	local why = d.playable and (", before demos kept who played them, how deep they got"
		.. " and their level. It may still play.") or ", and this one can't play it."
	local fs = theme.head(10, 4.6)
		.. "label[0.4,0.6;" .. theme.title("Delete this demo?") .. "]"
		.. ("textarea[0.4,1.1;9.2,2.1;;;%s]"):format(E(demos.title(d)
			.. " was recorded with an older version of VoxHack" .. why))
	if d.playable then
		return fs .. "button[0.4,3.4;2.9,0.9;delete;Delete it]button[3.55,3.4;2.9,0.9;play;Play it]"
			.. "button[6.7,3.4;2.9,0.9;keep;Keep it]"
	end
	return fs .. "button[0.4,3.4;4.4,0.9;delete;Delete it]button[5.2,3.4;4.4,0.9;keep;Keep it]"
end

local function delete_old_formspec(n)
	return theme.head(10, 4.6)
		.. "label[0.4,0.6;" .. theme.title("Delete the older demos?") .. "]"
		.. ("textarea[0.4,1.1;9.2,2.1;;;%s]"):format(E(("The %d demos in red, recorded with older"
			.. " versions of VoxHack, are deleted."):format(n)))
		.. "button[0.4,3.4;4.4,0.9;delete;Delete them]button[5.2,3.4;4.4,0.9;keep;Keep them]"
end

function demos.show(player)
	core.show_formspec(player:get_player_name(), FORM, formspec())
end

-- a demo played: the screen to black, the game let go (the engine plays it,
-- then comes back to the title - clientlauncher.cpp)
local function play(player, d)
	if not core.nhv_demo_play(d.file) then
		demos.show(player)
		return
	end
	local pname = player:get_player_name()
	nhv.title.open = false
	core.close_formspec(pname, FORM)
	nhv.hud.fade(1, 0.4)
	if nhv.sound then
		nhv.sound.stop_music()
	end
	core.after(0.5, function()
		if core.get_player_by_name(pname) then
			core.disconnect_player(pname, "nhv:demo")
		end
	end)
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname == FORM then
		if fields.record then
			-- (the engine starts recording as a session begins: from the next one)
			core.settings:set_bool("nhv_demo_record", fields.record == "true")
			core.settings:write()
			return true
		end
		for k in pairs(fields) do
			local i = tonumber(k:match("^demo_(%d+)$"))
			local d = i and list[i]
			if d then
				if not older(d) then
					play(player, d)
				else
					asked = d
					core.show_formspec(player:get_player_name(), DELETE, delete_formspec(d))
				end
				return true
			end
		end
		if fields.delete_old then
			local n = 0
			for _, d in ipairs(list) do
				n = n + (older(d) and 1 or 0)
			end
			core.show_formspec(player:get_player_name(), DELETE_OLD, delete_old_formspec(n))
		elseif fields.back or fields.quit then
			nhv.title.show(player)
		end
		return true
	elseif formname == DELETE then
		local d = asked
		asked = nil
		if fields.play and d and d.playable then
			play(player, d)
			return true
		end
		if fields.delete and d then
			core.nhv_demo_delete(d.file)
		end
		demos.show(player)
		return true
	elseif formname == DELETE_OLD then
		if fields.delete then
			for _, d in ipairs(list) do
				if older(d) then
					core.nhv_demo_delete(d.file)
				end
			end
		end
		demos.show(player)
		return true
	end
	return false
end)

return demos
