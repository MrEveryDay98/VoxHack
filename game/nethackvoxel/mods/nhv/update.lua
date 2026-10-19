-- Update check: once a session, when the title screen first shows, the
-- game asks GitHub for VoxHack's releases (pre-releases too) and, if one
-- is newer than this copy (title.TAG), the title screen says so with a
-- link to that release on GitHub, to download it (its notes link to
-- itch.io too). Off with the setting nhv_update_check = false.

local update = {}
nhv.update = update

local http = nhv.http -- (requested in init.lua)
local RELEASES = "https://api.github.com/repos/MrEveryDay98/VoxHack/releases?per_page=20"
-- (a release's page, if the answer has none)
update.PAGE = "https://github.com/MrEveryDay98/VoxHack/releases/latest"
local USER_AGENT = "VoxHack update check (+https://github.com/MrEveryDay98/VoxHack)"

-- "v0.1.10" -> {0, 1, 10}; nil if it isn't a version
local function parse(v)
	local a, b, c = tostring(v or ""):match("^v?(%d+)%.(%d+)%.?(%d*)")
	if not a then
		return nil
	end
	return {tonumber(a), tonumber(b), tonumber(c) or 0}
end

local function newer(a, b)
	for k = 1, 3 do
		if a[k] ~= b[k] then
			return a[k] > b[k]
		end
	end
	return false
end

update.available = nil -- {tag=} once a newer release is known

function update.check()
	if update.checked or not http or not core.settings:get_bool("nhv_update_check", true) then
		return
	end
	update.checked = true
	local mine = parse(nhv.title.TAG)
	if not mine then
		return
	end
	http.fetch({url = RELEASES, timeout = 10, user_agent = USER_AGENT,
		extra_headers = {"Accept: application/vnd.github+json"}}, function(res)
		if not (res.succeeded and res.code == 200) then
			core.log("info", "[nhv] update check: no answer (" .. tostring(res.code) .. ")")
			return
		end
		local list = core.parse_json(res.data)
		if type(list) ~= "table" then
			return
		end
		local best, best_tag, best_url
		for _, r in ipairs(list) do
			local v = type(r) == "table" and not r.draft and parse(r.tag_name)
			if v and (not best or newer(v, best)) then
				best, best_tag = v, r.tag_name
				best_url = type(r.html_url) == "string" and r.html_url:match("^https://github%.com/") and r.html_url
			end
		end
		if best and newer(best, mine) then
			update.available = {tag = best_tag, url = best_url or update.PAGE}
			core.log("action", "[nhv] update check: " .. best_tag .. " is available")
			-- (the title screen up: shown again, with the news)
			local player = nhv.player.get()
			if player and nhv.title.open then
				nhv.title.show(player)
			end
		end
	end)
end

return update
