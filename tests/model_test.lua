-- Unit tests for Model.lua, the plugin order as groups. No game client needed: luajit tests/model_test.lua
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./"
local ns = {}
assert(loadfile(here .. "../Model.lua"))("TitanArranger", ns)
local Model = ns.Model

local failures, count = 0, 0
local function test(name, fn)
	count = count + 1
	local ok, err = pcall(fn)
	if ok then
		print("PASS " .. name)
	else
		failures = failures + 1
		print("FAIL " .. name .. "\n     " .. tostring(err))
	end
end

local function same(got, want, what)
	local g, w = table.concat(got, ","), table.concat(want, ",")
	if g ~= w then
		error((what or "list") .. ": got {" .. g .. "}, want {" .. w .. "}", 2)
	end
end

-- A profile: ids with their bar, the right-side ones and the centre ones.
local function profile()
	local buttons = { "Location", "XP", "Clock", "Gold", "Volume", "Bag", "Gone", "Repair" }
	local locations = { "Bar", "Bar", "Bar", "Bar", "Bar", "Bar2", "Bar", "Bar" }
	local right = { Clock = true, Volume = true, Repair = true }
	local center = {}
	local loaded = { Gone = false }
	local function sideOf(id)
		if right[id] then
			return "right"
		elseif center[id] then
			return "center"
		end
		return "left"
	end
	local function visible(id)
		return loaded[id] ~= false
	end
	return buttons, locations, sideOf, visible, right, center
end

test("build groups by bar and side, in list order", function()
	local buttons, locations, sideOf = profile()
	local m = Model.Build(buttons, locations, sideOf)
	same(m.order, { "Bar", "Bar2" }, "bars")
	same(m.bars.Bar.left, { "Location", "XP", "Gold", "Gone" }, "Bar left")
	same(m.bars.Bar.right, { "Clock", "Volume", "Repair" }, "Bar right")
	same(m.bars.Bar2.left, { "Bag" }, "Bar2 left")
end)

test("a repeated id keeps its first place", function()
	local m = Model.Build({ "A", "B", "A" }, { "Bar", "Bar", "Bar2" }, function()
		return "left"
	end)
	same(m.bars.Bar.left, { "A", "B" })
	assert(m.bars.Bar2 == nil, "Bar2 should not exist")
end)

test("write keeps the parallel lists in step, centre after left", function()
	local buttons, locations, sideOf, _, _, center = profile()
	center.Gold = true
	local m = Model.Build(buttons, locations, sideOf)
	Model.Write(m, buttons, locations)
	same(buttons, { "Location", "XP", "Gone", "Gold", "Clock", "Volume", "Repair", "Bag" }, "buttons")
	same(locations, { "Bar", "Bar", "Bar", "Bar", "Bar", "Bar", "Bar", "Bar2" }, "locations")
end)

test("write refills the same tables Titan holds", function()
	local buttons, locations, sideOf = profile()
	local b, l = buttons, locations
	local m = Model.Build(buttons, locations, sideOf)
	Model.Write(m, buttons, locations)
	assert(b == buttons and l == locations, "tables replaced")
	assert(#buttons == #locations, "lists differ in length")
end)

test("move within the left group, counting only loaded plugins", function()
	local buttons, locations, sideOf, visible = profile()
	local m = Model.Build(buttons, locations, sideOf)
	-- "Gone" is not loaded, so the visible left group is Location, XP, Gold; put Gold first.
	Model.Move(m, "Gold", "Bar", "left", 1, visible)
	same(m.bars.Bar.left, { "Gold", "Location", "XP", "Gone" })
end)

test("move to the end of a group goes after the last loaded member", function()
	local buttons, locations, sideOf, visible = profile()
	local m = Model.Build(buttons, locations, sideOf)
	Model.Move(m, "Location", "Bar", "left", 3, visible)
	same(m.bars.Bar.left, { "XP", "Gold", "Location", "Gone" })
end)

test("move to another bar and side", function()
	local buttons, locations, sideOf, visible = profile()
	local m = Model.Build(buttons, locations, sideOf)
	Model.Move(m, "XP", "Bar2", "right", 1, visible)
	same(m.bars.Bar.left, { "Location", "Gold", "Gone" })
	same(m.bars.Bar2.right, { "XP" })
	Model.Write(m, buttons, locations)
	same(buttons, { "Location", "Gold", "Gone", "Clock", "Volume", "Repair", "Bag", "XP" }, "buttons")
	same(locations, { "Bar", "Bar", "Bar", "Bar", "Bar", "Bar", "Bar2", "Bar2" }, "locations")
end)

test("move to a bar that has no plugins yet", function()
	local buttons, locations, sideOf, visible = profile()
	local m = Model.Build(buttons, locations, sideOf)
	Model.Move(m, "Bag", "Short01", "left", 1, visible)
	same(m.order, { "Bar", "Bar2", "Short01" }, "bars")
	same(m.bars.Short01.left, { "Bag" })
	Model.Write(m, buttons, locations)
	assert(locations[#locations] == "Short01", "Bag not on Short01")
end)

test("insert a plugin that was on no bar", function()
	local buttons, locations, sideOf, visible = profile()
	local m = Model.Build(buttons, locations, sideOf)
	Model.Insert(m, "Mail", "Bar", "right", 2, visible)
	same(m.bars.Bar.right, { "Clock", "Mail", "Volume", "Repair" })
end)

test("remove takes the plugin out and nothing else", function()
	local buttons, locations, sideOf = profile()
	local m = Model.Build(buttons, locations, sideOf)
	local bar, side, i = Model.Remove(m, "Volume")
	assert(bar == "Bar" and side == "right" and i == 2, "wrong place")
	Model.Write(m, buttons, locations)
	same(buttons, { "Location", "XP", "Gold", "Gone", "Clock", "Repair", "Bag" })
	-- Removing a plugin that is on no bar changes nothing (Titan's own RemovePlugin dropped the last one here).
	local before = table.concat(buttons, ",")
	m = Model.Build(buttons, locations, sideOf)
	assert(Model.Remove(m, "Nowhere") == nil, "found a plugin that is not there")
	Model.Write(m, buttons, locations)
	assert(table.concat(buttons, ",") == before, "list changed")
end)

test("step right through the left group, into the centre, then the right group", function()
	local buttons, locations, sideOf, visible = profile()
	local m = Model.Build(buttons, locations, sideOf)
	local function step(id, dir)
		local bar, side, k = Model.StepTarget(m, id, dir, visible)
		if bar then
			Model.Move(m, id, bar, side, k, visible)
		end
		return side
	end
	assert(step("Location", 1) == "left")
	same(m.bars.Bar.left, { "XP", "Location", "Gold", "Gone" })
	assert(step("Location", 1) == "left")
	same(m.bars.Bar.left, { "XP", "Gold", "Location", "Gone" })
	-- Last loaded left plugin: the next step right is the centre.
	assert(step("Location", 1) == "center")
	same(m.bars.Bar.center, { "Location" })
	-- From the centre, right goes to the inner (leftmost on screen) end of the right group: the end of its list.
	assert(step("Location", 1) == "right")
	same(m.bars.Bar.right, { "Clock", "Volume", "Repair", "Location" })
	-- On screen the right group reads Location, Repair, Volume, Clock; stepping right passes Repair.
	assert(step("Location", 1) == "right")
	same(m.bars.Bar.right, { "Clock", "Volume", "Location", "Repair" })
end)

test("step left from the right group goes back through the centre", function()
	local buttons, locations, sideOf, visible = profile()
	local m = Model.Build(buttons, locations, sideOf)
	local bar, side, k = Model.StepTarget(m, "Repair", -1, visible)
	assert(side == "center" and k == 1, "expected the centre, got " .. tostring(side))
	Model.Move(m, "Repair", bar, side, k, visible)
	bar, side, k = Model.StepTarget(m, "Repair", -1, visible)
	assert(
		side == "left" and k == 4,
		"expected the end of the left group, got " .. tostring(side) .. " " .. tostring(k)
	)
end)

test("no step past either end of the bar, and right-only plugins stay right", function()
	local buttons, locations, sideOf, visible = profile()
	local m = Model.Build(buttons, locations, sideOf)
	assert(Model.StepTarget(m, "Location", -1, visible) == nil, "stepped off the left end")
	assert(Model.StepTarget(m, "Clock", 1, visible) == nil, "stepped off the right end")
	-- Repair is the leftmost right plugin on screen; pinned right, it cannot step into the centre.
	assert(Model.StepTarget(m, "Repair", -1, visible, true) == nil, "pinned plugin left the right group")
end)

print(count - failures .. " of " .. count .. " passed")
os.exit(failures == 0 and 0 or 1)
