-- Print the game's achievements (achievements.lua's list, as the game has
-- it) one a line: id <TAB> name <TAB> description <TAB> icon <TAB> group.
-- For make_steam_achievements.py: run with luajit, the path of
-- achievements.lua the argument. Everything the game itself would provide
-- is a stand-in that does nothing.
local stub
stub = setmetatable({}, {
	__index = function() return stub end,
	__call = function() return nil end,
})
core = stub
nhv = setmetatable({}, {__index = function() return stub end})
local f = assert(loadfile(arg[1]))
f()
for _, a in ipairs(nhv.achievements.list) do
	print(table.concat({a.id, a.name, a.desc, a.icon or "", a.group or ""}, "\t"))
end
