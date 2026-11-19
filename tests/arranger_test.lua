-- Scenario tests for Titan Panel [Arranger] on forever_sim, the headless Forever client from cjber/forever-core,
-- with the real Titan Panel and its built-in plugins. Run with tests/run.sh, which sets FOREVER_SIM,
-- TITANARRANGER_SIM_CACHE and TITAN_DIR (a folder holding Titan's own addon folders, as its zip unpacks).
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./"
local SIM = assert(os.getenv("FOREVER_SIM"), "FOREVER_SIM is not set: run tests/run.sh")
local CACHE = assert(os.getenv("TITANARRANGER_SIM_CACHE"), "TITANARRANGER_SIM_CACHE is not set: run tests/run.sh")
local TITAN = assert(os.getenv("TITAN_DIR"), "TITAN_DIR is not set: run tests/run.sh")
-- TITANARRANGER_ADDON_DIR runs the scenarios against another copy, such as an installed one.
local ADDON_DIR = os.getenv("TITANARRANGER_ADDON_DIR") or (here .. "..")

local Sim = dofile(SIM .. "sim.lua")

-- Titan's own addons that boot in the sim. Clock and Volume build option frames the sim's templates lack, and
-- Ammo, Regen and Classic are not for this client.
local TITAN_ADDONS = {
	"Titan",
	"TitanAlts",
	"TitanBag",
	"TitanGold",
	"TitanLocation",
	"TitanLootType",
	"TitanPerformance",
	"TitanPost",
	"TitanRepair",
	"TitanUI",
	"TitanXP",
}

local Session = {}
Session.__index = Session

-- What Titan calls that the sim does not boot or define (chat, item level, realms, GetText), and getfenv(0),
-- which Titan reads its globals through and which must answer the client's globals, as in the game.
local function standIns(G)
	G.ChatFrameUtil = G.ChatFrameUtil or {
		DisplayTimePlayed = function() end,
	}
	G.GetAverageItemLevel = G.GetAverageItemLevel or function()
		return 0, 0, 0
	end
	G.GetInventoryItemLink = G.GetInventoryItemLink or function() end
	G.GetAutoCompleteRealms = G.GetAutoCompleteRealms or function()
		return {}
	end
	G.GetText = G.GetText or function(token)
		return token
	end
	-- Titan names its profile from the GUID's name and realm; without a name it builds a key it resets on reload.
	G.GetPlayerInfoByGUID = function()
		return "Warrior", "WARRIOR", "Human", "Human", 2, G.UnitName("player"), G.GetRealmName()
	end
	local real = getfenv
	G.getfenv = function(level)
		if level == 0 then
			return G
		end
		return real(level)
	end
end

-- The client runs an addon's files and then puts its saved variables in place; the sim puts them in first. Titan's
-- TitanGlobal.lua sets TitanSettings and TitanAll to nil at load, so on the sim it would lose them: put them back
-- after each addon's files, as the client has them.
local function savedAfterFiles(sim, saved)
	local load = sim.loader.load
	sim.loader.load = function(name, ...)
		local result = load(name, ...)
		for _, entry in ipairs(sim.loader.addons) do
			if entry.name == name then
				for _, var in ipairs(sim.loader.savedVariables(entry)) do
					if saved[var] ~= nil then
						sim.G[var] = saved[var]
						sim.taint.globalTaint[var] = entry.name
					end
				end
			end
		end
		return result
	end
end

local function boot(opts)
	opts = opts or {}
	local sim = Sim.new({ cache = CACHE })
	standIns(sim.G)
	if opts.saved then
		savedAfterFiles(sim, opts.saved)
	end
	for _, name in ipairs(TITAN_ADDONS) do
		sim:addon(TITAN .. "/" .. name)
	end
	if opts.addon ~= false then
		sim:addon(ADDON_DIR)
	end
	sim:login({ savedVariables = opts.saved })
	local s = setmetatable({ sim = sim, G = sim.G }, Session)
	s.A = sim.G.TitanArranger
	s.ns = s.A and s.A.ns
	-- The sim's own boot errors in Blizzard code (gamepad bars, splash frame) are not under test.
	s.bootErrors = sim:takeErrors()
	return s
end

function Session:reload()
	local saved = self.sim:savedState()
	return boot({ saved = saved })
end

function Session:run(fn, ...)
	return self.sim.run(fn, ...)
end

function Session:advance(t)
	self.sim:advance(t or 0.05)
end

function Session:list()
	local out = {}
	for i, id in ipairs(self.G.TitanPanelSettings.Buttons) do
		out[i] = id
	end
	return out
end

function Session:index(id)
	for i, v in ipairs(self.G.TitanPanelSettings.Buttons) do
		if v == id then
			return i
		end
	end
end

function Session:barOf(id)
	local i = self:index(id)
	return i and self.G.TitanPanelSettings.Location[i]
end

-- On-screen plugins of a bar by side, in Titan's list order.
function Session:groups(bar)
	local T, A = self.ns.Titan, self.A
	local center = A:CenterFlags()
	local out = { left = {}, center = {}, right = {} }
	local buttons, locations = T.Buttons(), T.Locations()
	for i = 1, #buttons do
		if locations[i] == bar and T.IsOnScreen(buttons[i]) then
			local list = out[T.SideOf(buttons[i], center)]
			list[#list + 1] = buttons[i]
		end
	end
	return out
end

-- TitanUtils_GetButton also returns the id; only the frame, so it is never taken for a mouse button.
function Session:button(id)
	return (self.G.TitanUtils_GetButton(id))
end

function Session:barFrame(name)
	return self.G["Titan_Bar__Display_" .. name]
end

-- Screen pixels: left, bottom, right, top.
function Session:rect(frame)
	local l, b, w, h = frame:GetRect()
	assert(l, "frame has no rect")
	local s = frame:GetEffectiveScale()
	return l * s, b * s, (l + w) * s, (b + h) * s
end

function Session:barMid(name)
	local _, b, _, t = self:rect(self:barFrame(name))
	return (b + t) / 2
end

function Session:arrange()
	self:run(function()
		self.A:Enter("manual")
	end)
	self:advance()
	assert(self.A.arranging, "arranging did not start")
end

-- A drag the way the client runs one: OnDragStart on the box under the cursor, the cursor moves, OnDragStop.
function Session:dragFrame(frame, x, y)
	local sim = self.sim
	local l, b, r, t = self:rect(frame)
	sim.mouseX, sim.mouseY = (l + r) / 2, (b + t) / 2
	sim:input(function()
		sim.widgets.dispatch(frame, "OnDragStart", "LeftButton")
	end)
	self:advance()
	sim.mouseX, sim.mouseY = x, y
	self:advance()
	sim:input(function()
		sim.widgets.dispatch(frame, "OnDragStop")
	end)
	self:advance()
end

function Session:drag(id, x, y)
	local box = self.ns.Overlays.Box(id)
	assert(box and box:IsShown(), "no box over " .. id)
	self:dragFrame(box, x, y)
end

function Session:key(key)
	local handled
	self:run(function()
		handled = self.ns.Overlays.OnKey(key)
	end)
	self:advance()
	return handled
end

local function same(got, want, what)
	local g, w = table.concat(got, ","), table.concat(want, ",")
	if g ~= w then
		error((what or "list") .. ": got {" .. g .. "}, want {" .. w .. "}", 2)
	end
end

local function near(a, b, slack, what)
	if math.abs(a - b) > (slack or 1) then
		error(string.format("%s: %.1f is not near %.1f", what or "value", a, b), 2)
	end
end

local scenarios = {}
local function scenario(name, fn)
	scenarios[#scenarios + 1] = { name = name, fn = fn }
end

---------------------------------------------------------------------------------------------------------------------

scenario("Titan boots with Arranger, which locks the plugins and puts its button on the bar once", function()
	local s = boot()
	assert(s.A and s.A.active, "Arranger is not active")
	assert(s.A.ready, "Arranger never saw Titan's layout")
	assert(s.G.Titan_G.vars.PanelGet("LockButtons"), "Titan's Lock Buttons is off")
	local count = 0
	for _, id in ipairs(s:list()) do
		if id == "Arranger" then
			count = count + 1
		end
	end
	assert(count == 1, "Arranger button listed " .. count .. " times")
	assert(s:barOf("Arranger") == "Bar", "Arranger button not on the top bar")
	assert(s.G.Titan_G.plugins.ToRight("Arranger"), "Arranger button not on the right")
	assert(s:button("Arranger"):IsShown(), "Arranger button not drawn")
	local again = s:reload()
	count = 0
	for _, id in ipairs(again:list()) do
		if id == "Arranger" then
			count = count + 1
		end
	end
	assert(count == 1, "Arranger button listed " .. count .. " times after a reload")
	again.sim:expectNoErrors("TitanArranger")
	return s
end)

scenario("arranging puts a box over every plugin on a bar, and stopping takes them away", function()
	local s = boot()
	s:arrange()
	assert(not s.G.Titan_G.vars.PanelGet("LockButtons"), "Lock Buttons still on while arranging")
	assert(s.ns.Panel.Frame():IsShown(), "panel not shown")
	local boxes = 0
	for _, id in ipairs(s:list()) do
		if s.ns.Titan.IsOnScreen(id) then
			local box = s.ns.Overlays.Box(id)
			assert(box and box:IsShown(), "no box over " .. id)
			local bl, bb, br, bt = s:rect(box)
			local l, b, r, t = s:rect(s:button(id))
			near(bl, l, 0.5, id .. " box left")
			near(br, r, 0.5, id .. " box right")
			boxes = boxes + 1
		end
	end
	assert(boxes >= 4, "only " .. boxes .. " plugins on screen")
	s:run(function()
		s.A:Exit()
	end)
	assert(not s.A.arranging, "still arranging")
	assert(s.G.Titan_G.vars.PanelGet("LockButtons"), "Lock Buttons off after arranging")
	assert(not s.ns.Panel.Frame():IsShown(), "panel still shown")
	for _, id in ipairs(s:list()) do
		local box = s.ns.Overlays.Box(id)
		assert(not box or not box:IsShown(), "box left over " .. id)
	end
	return s
end)

scenario("Edit Mode starts and stops arranging, unless that is switched off", function()
	local s = boot()
	local ER = s.G.EventRegistry
	s:run(function()
		ER:TriggerEvent("EditMode.Enter")
	end)
	assert(s.A.arranging and s.A.reason == "editmode", "Edit Mode did not start arranging")
	s:run(function()
		ER:TriggerEvent("EditMode.Exit")
	end)
	assert(not s.A.arranging, "Edit Mode closing did not stop arranging")
	-- Started by hand, arranging outlasts Edit Mode.
	s:arrange()
	s:run(function()
		ER:TriggerEvent("EditMode.Enter")
		ER:TriggerEvent("EditMode.Exit")
	end)
	assert(s.A.arranging, "Edit Mode closing stopped arranging that was started by hand")
	s:run(function()
		s.A:Exit()
	end)
	s.G.TitanArrangerDB.settings.withEditMode = false
	s:run(function()
		ER:TriggerEvent("EditMode.Enter")
	end)
	assert(not s.A.arranging, "Edit Mode started arranging although that is switched off")
	return s
end)

scenario("a plugin dropped before the first of its side goes first", function()
	local s = boot()
	s:arrange()
	local left = s:groups("Bar").left
	assert(#left >= 2, "need two left plugins, have " .. #left)
	local last, first = left[#left], left[1]
	local l = s:rect(s:button(first))
	s:drag(last, l - 2, s:barMid("Bar"))
	local after = s:groups("Bar").left
	assert(after[1] == last, "first is now " .. tostring(after[1]) .. ", not " .. last)
	assert(#after == #left, "left side changed size")
	-- Titan laid it out there too.
	assert(s:rect(s:button(last)) < s:rect(s:button(first)), last .. " is not left of " .. first)
	return s
end)

scenario("a plugin dropped among the right ones moves to the right side", function()
	local s = boot()
	s:arrange()
	local g = s:groups("Bar")
	local mover = g.left[1]
	local inner = g.right[#g.right]
	local l = s:rect(s:button(inner))
	s:drag(mover, l - 2, s:barMid("Bar"))
	local after = s:groups("Bar")
	assert(after.right[#after.right] == mover, mover .. " is not the inner right plugin")
	assert(s.G.Titan_G.plugins.GetVar(mover, "DisplayOnRightSide"), "DisplayOnRightSide not set")
	return s
end)

scenario("the centre area holds plugins around the middle of the bar", function()
	local s = boot()
	s:arrange()
	local g = s:groups("Bar")
	local mover = g.left[1]
	local bl, _, br = s:rect(s:barFrame("Bar"))
	s:drag(mover, (bl + br) / 2, s:barMid("Bar"))
	local after = s:groups("Bar")
	same(after.center, { mover }, "centre")
	assert(s.A:CenterFlags()[mover], "no centre flag")
	assert(not s.G.Titan_G.plugins.GetVar(mover, "DisplayOnRightSide"), "centre plugin marked right")
	local l, _, r = s:rect(s:button(mover))
	near((l + r) / 2, (bl + br) / 2, 1.5, "centre plugin's middle")
	-- Every other left plugin comes before it in Titan's list, so none hangs off it.
	for _, id in ipairs(after.left) do
		assert(s:index(id) < s:index(mover), id .. " comes after the centre plugin")
	end
	-- A second one joins it, and the pair stays centred.
	local second = after.left[1]
	local cl, _, cr = s:rect(s:button(mover))
	s:drag(second, cr + 1, s:barMid("Bar"))
	same(s:groups("Bar").center, { mover, second }, "centre")
	local l1 = s:rect(s:button(mover))
	local _, _, r2 = s:rect(s:button(second))
	near((l1 + r2) / 2, (bl + br) / 2, 1.5, "centre pair's middle")
	return s
end)

scenario("a plugin Titan adds after centre ones is put back in front of them", function()
	local s = boot()
	s:arrange()
	local g = s:groups("Bar")
	local mover = g.left[1]
	local bl, _, br = s:rect(s:barFrame("Bar"))
	s:drag(mover, (bl + br) / 2, s:barMid("Bar"))
	s:run(function()
		s.A:Exit()
	end)
	assert(not s:index("Performance"), "Performance already listed")
	-- Titan's own way of showing a plugin: its Plugins menu calls AddOnBar, which appends to the list.
	s:run(function()
		s.G.Titan_G.plugins.AddOnBar("Bar", "Performance")
	end)
	s:advance()
	assert(s:index("Performance"), "Performance not shown")
	assert(s:index("Performance") < s:index(mover), "Performance stayed after the centre plugin")
	local l, _, r = s:rect(s:button(mover))
	near((l + r) / 2, (bl + br) / 2, 1.5, "centre plugin's middle")
	return s
end)

scenario("dropping a plugin on the panel hides it, and dragging it from the panel shows it", function()
	local s = boot()
	s:arrange()
	local victim = s:groups("Bar").left[1]
	local panel = s.ns.Panel.Frame()
	local pl, pb, pr, pt = s:rect(panel)
	s:drag(victim, (pl + pr) / 2, (pb + pt) / 2)
	assert(not s:index(victim), victim .. " still listed")
	assert(not s:button(victim):IsShown(), victim .. " still drawn")
	local inTray = false
	for _, id in ipairs(s.ns.Panel.TrayIds()) do
		inTray = inTray or id == victim
	end
	assert(inTray, victim .. " not in the panel's list")
	-- Back from the panel onto the right side.
	local row
	for _, r in ipairs(s.ns.Panel.Rows()) do
		if r.id == victim and r:IsShown() then
			row = r
		end
	end
	assert(row, "no row for " .. victim)
	local inner = s:groups("Bar").right
	local l = s:rect(s:button(inner[#inner]))
	s:dragFrame(row, l - 2, s:barMid("Bar"))
	assert(s:barOf(victim) == "Bar", victim .. " not back on the bar")
	assert(s:button(victim):IsShown(), victim .. " not drawn")
	assert(s.G.Titan_G.plugins.GetVar(victim, "DisplayOnRightSide"), victim .. " not on the right")
	return s
end)

scenario("an LDB plugin is arranged like any other", function()
	local s = boot()
	s:run(function()
		s.G.LibStub("LibDataBroker-1.1"):NewDataObject("ArrangerTestBroker", {
			type = "data source",
			label = "Test",
			text = "42",
		})
	end)
	s:advance(0.5)
	assert(s.G.Titan_G.plugins.IsRegistered("ArrangerTestBroker"), "Titan did not take the LDB object")
	s:arrange()
	local row
	for _, r in ipairs(s.ns.Panel.Rows()) do
		if r.id == "ArrangerTestBroker" and r:IsShown() then
			row = r
		end
	end
	assert(row, "LDB plugin not in the panel's list")
	local first = s:groups("Bar").left[1]
	s:dragFrame(row, s:rect(s:button(first)) - 2, s:barMid("Bar"))
	assert(s:groups("Bar").left[1] == "ArrangerTestBroker", "LDB plugin not first on the left")
	-- And dragged again, like the built-in ones.
	local g = s:groups("Bar")
	local l = s:rect(s:button(g.right[#g.right]))
	s:drag("ArrangerTestBroker", l - 2, s:barMid("Bar"))
	local after = s:groups("Bar")
	assert(after.right[#after.right] == "ArrangerTestBroker", "LDB plugin not moved to the right")
	return s
end)

scenario("arrow keys move the selected plugin one place, then into the next area", function()
	local s = boot()
	s:arrange()
	local left = s:groups("Bar").left
	local id = left[1]
	s:run(function()
		s.ns.Overlays.Select({ kind = "plugin", id = id })
	end)
	assert(s:key("RIGHT"), "RIGHT not handled")
	assert(s:groups("Bar").left[2] == id, id .. " did not move one place right")
	for _ = 3, #left do
		s:key("RIGHT")
	end
	assert(s:groups("Bar").left[#left] == id, id .. " is not last on the left")
	s:key("RIGHT")
	same(s:groups("Bar").center, { id }, "centre after stepping past the left side")
	s:key("RIGHT")
	local g = s:groups("Bar")
	assert(g.right[#g.right] == id, id .. " is not the inner right plugin")
	s:key("LEFT")
	same(s:groups("Bar").center, { id }, "centre after stepping back")
	assert(not s:key("UP"), "UP should pass through for a plugin")
	return s
end)

scenario("Revert puts plugins, sides, centre and options back", function()
	local s = boot()
	local before = s:list()
	local beforeRight = {}
	for _, id in ipairs(before) do
		beforeRight[id] = s.G.Titan_G.plugins.GetVar(id, "DisplayOnRightSide")
	end
	s:arrange()
	local g = s:groups("Bar")
	local a, b = g.left[1], g.left[2]
	local bl, _, br = s:rect(s:barFrame("Bar"))
	s:drag(a, (bl + br) / 2, s:barMid("Bar"))
	local inner = s:groups("Bar").right
	s:drag(b, s:rect(s:button(inner[#inner])) - 2, s:barMid("Bar"))
	local label = s.G.Titan_G.plugins.GetVar(a, "ShowLabelText")
	s.G.Titan_G.plugins.SetVar(a, "ShowLabelText", not label and 1 or false)
	assert(s.A.dirty, "changes not noticed")
	s:run(function()
		s.A:Revert()
	end)
	s:advance()
	same(s:list(), before, "list after Revert")
	for _, id in ipairs(before) do
		assert(
			(s.G.Titan_G.plugins.GetVar(id, "DisplayOnRightSide") and true or false)
				== (beforeRight[id] and true or false),
			id .. " side not restored"
		)
	end
	assert(next(s.A:CenterFlags()) == nil, "centre flags left after Revert")
	assert(
		(s.G.Titan_G.plugins.GetVar(a, "ShowLabelText") and true or false) == (label and true or false),
		"option not restored"
	)
	assert(s.A.arranging, "Revert stopped arranging")
	return s
end)

scenario("the options popup changes a plugin's side and display choices", function()
	local s = boot()
	s:arrange()
	local id = s:groups("Bar").left[1]
	s.sim:click(s.ns.Overlays.Box(id))
	assert(s.ns.Popup.IsOpen(), "popup not open")
	local popup = s.G.TitanArrangerPopup
	local right
	for _, b in ipairs(popup.sides) do
		if b.side == "right" then
			right = b
		end
	end
	s.sim:click(right)
	local g = s:groups("Bar")
	assert(g.right[#g.right] == id, id .. " not moved to the right by the popup")
	local check
	for _, c in ipairs(popup.checks) do
		if c:IsShown() and c.var == "ShowLabelText" then
			check = c
		end
	end
	assert(check, "no Show label option for " .. id)
	local was = s.G.Titan_G.plugins.GetVar(id, "ShowLabelText") and true or false
	s.sim:click(check)
	assert((s.G.Titan_G.plugins.GetVar(id, "ShowLabelText") and true or false) ~= was, "Show label not toggled")
	return s
end)

scenario("Short bars take plugins and move with the arrow keys, saved by Titan", function()
	local s = boot()
	local frameName = "Titan_Bar__Display_Short01"
	s:run(function()
		s.G.TitanBarDataVars[frameName].show = true
		s.G.Titan_G.bars.DisplayBarsWanted("test")
	end)
	s:advance()
	s:arrange()
	local box = s.ns.Overlays.BarBox(frameName)
	assert(box and box:IsShown(), "no box over Short01")
	local mover = s:groups("Bar").left[1]
	local sl, _, sr = s:rect(s:barFrame("Short01"))
	s:drag(mover, sl + 4, s:barMid("Short01"))
	assert(s:barOf(mover) == "Short01", mover .. " not on Short01")
	local x0 = s.G.TitanBarDataVars[frameName].off_x
	local left0 = s:rect(s:barFrame("Short01"))
	s:run(function()
		s.ns.Overlays.Select({ kind = "bar", bar = s.ns.Titan.Bar("Short01") })
	end)
	assert(s:key("RIGHT"), "RIGHT not handled for a Short bar")
	near(s.G.TitanBarDataVars[frameName].off_x, x0 + 1, 0.51, "saved x after one nudge")
	near(s:rect(s:barFrame("Short01")), left0 + 1, 0.51, "bar's left after one nudge")
	return s
end)

scenario("combat stops arranging and keeps it from starting", function()
	local s = boot()
	s:arrange()
	s.sim:enterCombat()
	assert(not s.A.arranging, "still arranging in combat")
	assert(s.G.Titan_G.vars.PanelGet("LockButtons"), "Lock Buttons off in combat")
	s:run(function()
		s.A:Enter("manual")
	end)
	assert(not s.A.arranging, "arranging started in combat")
	s.sim:leaveCombat()
	s:arrange()
	return s
end)

scenario("a layout with a centre area survives a reload", function()
	local s = boot()
	s:arrange()
	local mover = s:groups("Bar").left[1]
	local bl, _, br = s:rect(s:barFrame("Bar"))
	s:drag(mover, (bl + br) / 2, s:barMid("Bar"))
	s:run(function()
		s.A:Exit()
	end)
	local after = s:reload()
	same(after:groups("Bar").center, { mover }, "centre after a reload")
	local l, _, r = after:rect(after:button(mover))
	near((l + r) / 2, (bl + br) / 2, 1.5, "centre plugin's middle after a reload")
	assert(not after.A.arranging, "arranging after a reload")
	assert(after.G.Titan_G.vars.PanelGet("LockButtons"), "unlocked after a reload")
	after.sim:expectNoErrors("TitanArranger")
	return s
end)

scenario("the slash command and Titan's Lock Buttons option both toggle arranging", function()
	local s = boot()
	s.sim:slash("/arranger")
	assert(s.A.arranging, "/arranger did not start arranging")
	s.sim:slash("/arranger")
	assert(not s.A.arranging, "/arranger did not stop arranging")
	s:run(function()
		s.G.Titan_G.vars.PanelToggle("LockButtons")
	end)
	assert(s.A.arranging, "unticking Lock Buttons did not start arranging")
	s:run(function()
		s.G.Titan_G.vars.PanelToggle("LockButtons")
	end)
	assert(not s.A.arranging, "ticking Lock Buttons did not stop arranging")
	return s
end)

scenario("the Arranger button shows the reorder tiles on their side, and starts and stops arranging", function()
	local s = boot()
	local G = s.G
	local Plugin = s.ns.Plugin
	local function corners(...)
		local out = {}
		for i = 1, select("#", ...) do
			out[i] = string.format("%.3f", (select(i, ...)))
		end
		return table.concat(out, ",")
	end
	-- Drawn by Titan's own update: the atlas's file with its corners turned a quarter anticlockwise. (The sim's
	-- atlases span their whole file and have no file id, so the name stands in for the file.)
	local reg = G.Titan_G.plugins.Get("Arranger")
	assert(reg.icon == "icon_buffreorder", "icon: " .. tostring(reg.icon))
	local icon = G[s:button("Arranger"):GetName() .. "Icon"]
	local got = corners(icon:GetTexCoord())
	assert(got == corners(1, 0, 0, 0, 1, 1, 0, 1), "icon corners: " .. got)
	-- With the client's real values: the atlas's own box within its file, turned the same way.
	local C_Texture = G.C_Texture
	G.C_Texture = {
		GetAtlasInfo = function(name)
			assert(name == "icon_buffreorder", "asked for atlas " .. tostring(name))
			return { file = 4567, leftTexCoord = 0.25, rightTexCoord = 0.5, topTexCoord = 0.125, bottomTexCoord = 0.375 }
		end,
	}
	local file, coords = Plugin.Art()
	assert(file == 4567, "file " .. tostring(file))
	assert(
		corners(unpack(coords)) == corners(0.5, 0.125, 0.25, 0.125, 0.5, 0.375, 0.25, 0.375),
		"turned box: " .. corners(unpack(coords))
	)
	-- A client without the atlas gets the move cursor, untouched.
	G.C_Texture = { GetAtlasInfo = function() end }
	file, coords = Plugin.Art()
	G.C_Texture = C_Texture
	assert(file == Plugin.FALLBACK and coords == nil, "fallback " .. tostring(file) .. " " .. tostring(coords))
	s.sim:click(s:button("Arranger"))
	assert(s.A.arranging, "Arranger button click did not start arranging")
	-- While arranging the button has a box over it like every plugin; its tooltip says a click on it finishes.
	local box = s.ns.Overlays.Box("Arranger")
	assert(box and box:IsShown(), "no box over the Arranger button")
	s.sim:hover(box)
	local lines = {}
	for i = 1, G.GameTooltip:NumLines() do
		lines[#lines + 1] = G["GameTooltipTextLeft" .. i]:GetText()
	end
	s.sim:leave()
	local text = table.concat(lines, "|")
	assert(text:find(s.ns.L.CLICK_TO_FINISH, 1, true), "box tooltip: " .. text)
	assert(not text:find(s.ns.L.CLICK_FOR_OPTIONS, 1, true), "box tooltip offers options: " .. text)
	s.sim:click(box)
	assert(not s.A.arranging, "Arranger button click while arranging did not stop it")
	assert(not s.ns.Popup.IsOpen(), "Arranger button click opened the options popup")
	-- The panel's Done does the same.
	s:arrange()
	local done
	for _, child in ipairs({ s.ns.Panel.Frame():GetChildren() }) do
		if child.GetText and child:GetText() == s.ns.L.DONE then
			done = child
		end
	end
	assert(done, "no Done button")
	s.sim:click(done)
	assert(not s.A.arranging, "Done did not stop arranging")
	return s
end)

scenario("the panel, popup and drag label wear Titan's skin or colour and its font", function()
	local s = boot()
	s:arrange()
	local f = s.ns.Panel.Frame()
	assert(f.themeKind == "skin", "panel look is " .. tostring(f.themeKind))
	local tex = tostring(f.strip.tex:GetTexture())
	assert(tex:find("TitanPanelBackgroundTop0", 1, true), "skin texture is " .. tex)
	-- The skin is a bar-height strip: drawn once at Titan's bar height, not tiled down the panel.
	near(f.strip:GetHeight(), 24, 0.1, "title strip height")
	local function skinTextures(frame, found)
		for _, region in ipairs({ frame:GetRegions() }) do
			if region:GetObjectType() == "Texture" and tostring(region:GetTexture()):find("TitanPanelBackground") then
				found[#found + 1] = region
			end
		end
		for _, child in ipairs({ frame:GetChildren() }) do
			skinTextures(child, found)
		end
		return found
	end
	local skins = skinTextures(f, {})
	assert(#skins == 1, #skins .. " textures use Titan's skin")
	assert(f.dialogBorder, "no dialog border")
	local _, size = f.title:GetFont()
	near(size, (tonumber(s.G.Titan_G.vars.PanelGet("FontSize")) or 10) + 3, 0.1, "title font size")
	-- A bar drawn in a colour instead of a skin: the windows take the colour.
	s:run(function()
		s.A:Exit()
	end)
	local v = s.G.TitanBarDataVars["Titan_Bar__Display_Bar"]
	v.texure = s.G.Titan_G.COLOR
	v.color = { r = 0.2, g = 0.4, b = 0.6, alpha = 0.8 }
	s:arrange()
	assert(f.themeKind == "color", "panel look is " .. tostring(f.themeKind) .. " for a coloured bar")
	local id = s:groups("Bar").left[1]
	s.sim:click(s.ns.Overlays.Box(id))
	assert(s.G.TitanArrangerPopup.themeKind == "color", "popup look is " .. tostring(s.G.TitanArrangerPopup.themeKind))
	return s
end)

scenario("the spacing sliders set Titan's Button and Icon Spacing, and Revert restores them", function()
	local s = boot()
	local function get(var)
		return s.G.Titan_G.vars.PanelGet(var)
	end
	local b0, i0 = get("ButtonSpacing"), get("IconSpacing")
	s:arrange()
	local f = s.ns.Panel.Frame()
	local right = s:groups("Bar").right
	assert(#right >= 2, "need two right plugins, have " .. #right)
	-- Titan's right group runs right to left: the first is the rightmost.
	local function gap()
		local l1 = s:rect(s:button(right[1]))
		local _, _, r2 = s:rect(s:button(right[2]))
		return l1 - r2
	end
	local before = gap()
	local slider = f.sliders[3].widget
	s:run(function()
		local thumb = slider.Slider or slider
		thumb:SetValue(12)
	end)
	s:advance()
	assert(get("IconSpacing") == 12, "IconSpacing is " .. tostring(get("IconSpacing")))
	assert(gap() > before + 5, string.format("right-side gap went from %.1f to %.1f", before, gap()))
	slider = f.sliders[1].widget
	s:run(function()
		local thumb = slider.Slider or slider
		thumb:SetValue(40)
	end)
	s:advance()
	assert(get("ButtonSpacing") == 40, "ButtonSpacing is " .. tostring(get("ButtonSpacing")))
	assert(s.A.dirty, "spacing change not noticed")
	s:run(function()
		s.A:Revert()
	end)
	assert(get("ButtonSpacing") == b0 and get("IconSpacing") == i0, "spacing not restored by Revert")
	return s
end)

scenario("with Edit Mode open the panel sits beside its window; a resized panel keeps its width and height", function()
	local s = boot()
	local G = s.G
	-- The sim cannot run all of Blizzard's EnterEditMode, so the window is shown and the event sent by hand.
	s:run(function()
		G.EditModeManagerFrame:Show()
	end)
	s:run(function()
		G.EventRegistry:TriggerEvent("EditMode.Enter")
	end)
	assert(s.A.arranging, "Edit Mode did not start arranging")
	local f = s.ns.Panel.Frame()
	local point, rel, relPoint = f:GetPoint(1)
	assert(
		rel == G.EditModeManagerFrame and point == "TOPRIGHT" and relPoint == "TOPLEFT",
		"panel not beside Edit Mode's window"
	)
	s:run(function()
		G.EventRegistry:TriggerEvent("EditMode.Exit")
	end)
	G.TitanArrangerDB.settings.panelSize = { 420, 480 }
	s:arrange()
	near(f:GetWidth(), 420, 0.5, "panel width")
	local P = s.ns.Panel
	near(f:GetHeight(), math.min(P.Measure(f, #P.Items()), 480), 0.5, "panel height")
	return s
end)

scenario("the panel is as tall as its list, grows and shrinks below a fixed top, and can be dragged shorter", function()
	local s = boot()
	local G = s.G
	s:arrange()
	local P = s.ns.Panel
	local f = P.Frame()
	-- The list's area holds its rows (MIN_ROWS at least) and the 4 under them, no more.
	local function fits(what)
		local _, sb, _, st = s:rect(f.scroll)
		near(st - sb, math.max(#P.Items(), P.MIN_ROWS) * P.ROW + 4, 0.6, what)
	end
	fits("list area as it opens")
	local _, _, _, top = s:rect(f)
	local g = s:groups("Bar")
	local ids = {}
	for _, id in ipairs({ g.left[1], g.left[2], g.right[1], g.right[2] }) do
		if id ~= s.ns.Plugin.ID and #ids < 3 then
			ids[#ids + 1] = id
		end
	end
	for _, id in ipairs(ids) do
		local count = #P.Items()
		local l, b, r, t = s:rect(f)
		s:drag(id, (l + r) / 2, (b + t) / 2)
		assert(#P.Items() > count, id .. " did not join the list")
		fits("list area after hiding " .. id)
		local _, _, _, t2 = s:rect(f)
		near(t2, top, 0.5, "panel top after hiding " .. id)
	end
	local row
	for _, r in ipairs(P.Rows()) do
		if r.id == ids[1] and r:IsShown() then
			row = r
		end
	end
	assert(row, "no row for " .. ids[1])
	local count = #P.Items()
	local bl = s:rect(s:barFrame("Bar"))
	s:dragFrame(row, bl + 3, s:barMid("Bar"))
	assert(s:barOf(ids[1]) == "Bar", ids[1] .. " not back on the bar")
	assert(#P.Items() < count, "the list kept " .. ids[1])
	fits("list area after showing " .. ids[1])
	local _, _, _, t3 = s:rect(f)
	near(t3, top, 0.5, "panel top after the list shrank")
	-- The corner, as the client drags it (the sim has no StartSizing).
	f.StartSizing = f.StartSizing or function() end
	local function resize(h)
		s.sim:input(function()
			s.sim.widgets.dispatch(f.grip, "OnMouseDown", "LeftButton")
			f:SetHeight(h)
			s.sim.widgets.dispatch(f.grip, "OnMouseUp", "LeftButton")
		end)
		s:advance()
	end
	local want = P.Measure(f, #P.Items())
	local short = math.floor(want - 2 * P.ROW + 0.5)
	resize(short)
	near(f:GetHeight(), short, 0.5, "panel height after dragging it shorter")
	assert(G.TitanArrangerDB.settings.panelSize[2] == short, "shorter height not kept")
	local _, sb, _, st = s:rect(f.scroll)
	assert(st - sb < #P.Items() * P.ROW, "the list does not scroll in a shorter panel")
	s:run(function()
		s.A:Exit()
	end)
	s:arrange()
	near(f:GetHeight(), short, 0.5, "shorter height when arranging again")
	-- Dragged taller than its list, it goes back to fitting it.
	resize(want + 100)
	assert(G.TitanArrangerDB.settings.panelSize[2] == nil, "a taller height was kept as a limit")
	fits("list area after dragging it taller")
	return s
end)

scenario("the panel stops above Titan's bottom bars, and its list scrolls instead", function()
	local s = boot()
	local G = s.G
	s:arrange()
	local P = s.ns.Panel
	local f = P.Frame()
	local g = s:groups("Bar")
	local hidden = 0
	for _, id in ipairs({ g.left[1], g.left[2], g.right[1], g.right[2] }) do
		if id ~= s.ns.Plugin.ID and hidden < 3 then
			local l, b, r, t = s:rect(f)
			s:drag(id, (l + r) / 2, (b + t) / 2)
			hidden = hidden + 1
		end
	end
	assert(#P.Items() >= P.MIN_ROWS + 2, "list too short for this check")
	s:run(function()
		s.A:Exit()
	end)
	-- Titan's bottom bar on, as its Bars options do it.
	local name = "Titan_Bar__Display_AuxBar"
	s:run(function()
		G.TitanBarDataVars[name].show = true
		G.Titan_G.bars.DisplayBarsWanted("test")
	end)
	s:advance()
	local aux = G[name]
	assert(aux:IsShown(), "bottom bar not shown")
	local _, _, _, auxTop = s:rect(aux)
	-- The panel's top placed so that one row more than its least fits above the bar.
	local scale = f:GetEffectiveScale()
	local _, least = P.Measure(f, 0)
	local top = auxTop / scale + P.GAP + least + P.ROW
	G.TitanArrangerDB.settings.panel = { "TOPLEFT", "BOTTOMLEFT", 100, top }
	s:arrange()
	local _, pb, _, pt = s:rect(f)
	near(pt / scale, top, 0.5, "panel top")
	near(pb / scale, auxTop / scale + P.GAP, 0.6, "panel bottom above the bottom bar")
	local _, sb, _, st = s:rect(f.scroll)
	assert(st - sb < #P.Items() * P.ROW, "the list does not scroll")
	-- With the bar switched off while arranging, the panel grows on down.
	s:run(function()
		G.TitanBarDataVars[name].show = false
		G.Titan_G.bars.DisplayBarsWanted("test")
	end)
	s:advance()
	local _, pb2 = s:rect(f)
	assert(pb2 < pb - 1, "the panel did not grow with the bottom bar gone")
	return s
end)

scenario("the panel lists plugins under Titan's own groups, tall enough to show them", function()
	local s = boot()
	s:arrange()
	local items = s.ns.Panel.Items()
	assert(items[1] and items[1].kind == "header", "the list does not start with a group heading")
	local seen = {}
	local current
	for _, item in ipairs(items) do
		if item.kind == "header" then
			current = item.text
			assert(not seen[current], "group " .. current .. " listed twice")
			seen[current] = true
		else
			local reg = s.G.Titan_G.plugins.Get(item.id)
			local cat = reg.category or "General"
			local order = s.G.TITAN_PANEL_BUTTONS_PLUGIN_CATEGORY
			local index
			for i, c in ipairs(order) do
				if c == cat then
					index = i
				end
			end
			local loc = s.G.LibStub("AceLocale-3.0"):GetLocale("Titan", true)
			local want = index and rawget(loc, "TITAN_PANEL_MENU_CATEGORIES")[index] or cat
			assert(current == want, item.id .. " is under " .. tostring(current) .. ", not " .. tostring(want))
		end
	end
	-- The whole list fits without scrolling.
	local f = s.ns.Panel.Frame()
	local _, sb, _, st = s:rect(f.scroll)
	assert(st - sb >= #items * s.ns.Panel.ROW - 0.5, "panel too short for its list")
	return s
end)

scenario("the panel's parts stay apart and inside it, as it opens and at its smallest", function()
	local s = boot()
	s:arrange()
	local f = s.ns.Panel.Frame()
	local function check(what)
		local fl, fb, fr, ft = s:rect(f)
		local parts =
			{ { "title strip", f.strip }, { "hint", f.hint }, { "list heading", f.head }, { "list", f.scroll } }
		parts[#parts + 1] = { "spacing heading", f.spacing }
		for i, sl in ipairs(f.sliders) do
			parts[#parts + 1] = { "spacing row " .. i, sl.row }
		end
		parts[#parts + 1] = { "Edit Mode choice", f.check }
		parts[#parts + 1] = { "Revert", f.revert }
		for _, p in ipairs(parts) do
			local l, b, r, t = s:rect(p[2])
			assert(
				l >= fl - 0.5 and r <= fr + 0.5 and b >= fb - 0.5 and t <= ft + 0.5,
				p[1] .. " pokes out of the panel " .. what
			)
		end
		-- Top to bottom, each part ends above the next one starts.
		for i = 1, #parts - 1 do
			local _, b1 = s:rect(parts[i][2])
			local _, _, _, t2 = s:rect(parts[i + 1][2])
			assert(b1 >= t2 - 0.5, parts[i][1] .. " overlaps " .. parts[i + 1][1] .. " " .. what)
		end
		local _, _, rr = s:rect(f.revert)
		local dl = s:rect(f.done)
		assert(rr <= dl, "Revert overlaps Done " .. what)
	end
	check("as it opens")
	-- The smallest it goes: a width and a height limit below its least.
	s:run(function()
		s.A:Exit()
	end)
	s.G.TitanArrangerDB.settings.panelSize = { 1, 1 }
	s:arrange()
	local minW, minH = f:GetResizeBounds()
	near(f:GetWidth(), minW, 0.5, "smallest width")
	near(f:GetHeight(), minH, 0.5, "smallest height")
	check("at its smallest")
	return s
end)

scenario("the options popup's parts stay apart and inside it", function()
	local s = boot()
	s:arrange()
	local id = s:groups("Bar").left[1]
	s.sim:click(s.ns.Overlays.Box(id))
	local f = s.G.TitanArrangerPopup
	assert(f:IsShown(), "popup not open")
	local parts = { { "title strip", f.strip }, { "side heading", f.sideLabel }, { "side buttons", f.sides[1] } }
	for _, c in ipairs(f.checks) do
		if c:IsShown() then
			parts[#parts + 1] = { c.var, c }
		end
	end
	parts[#parts + 1] = { "margin heading", f.spaceLabel }
	for i, sl in ipairs(f.space) do
		parts[#parts + 1] = { "margin row " .. i, sl.row }
	end
	parts[#parts + 1] = { "Hide", f.hide }
	local fl, fb, fr, ft = s:rect(f)
	for i, p in ipairs(parts) do
		local l, b, r, t = s:rect(p[2])
		assert(l >= fl - 0.5 and r <= fr + 0.5 and b >= fb - 0.5 and t <= ft + 0.5, p[1] .. " pokes out of the popup")
		if parts[i + 1] then
			local _, _, _, t2 = s:rect(parts[i + 1][2])
			assert(b >= t2 - 0.5, p[1] .. " overlaps " .. parts[i + 1][1])
		end
	end
	local _, _, r1 = s:rect(f.sides[1])
	local l2 = s:rect(f.sides[2])
	local _, _, r3 = s:rect(f.sides[3])
	assert(r1 <= l2 and r3 <= fr, "side buttons overlap or poke out")
	return s
end)

scenario("the centre area has its own spacing, following Titan's Button Spacing until set", function()
	local s = boot()
	s:arrange()
	local f = s.ns.Panel.Frame()
	local g = s:groups("Bar")
	local a, b = g.left[1], g.left[2]
	local bl, _, br = s:rect(s:barFrame("Bar"))
	s:drag(a, (bl + br) / 2, s:barMid("Bar"))
	local _, _, ar = s:rect(s:button(a))
	s:drag(b, ar + 1, s:barMid("Bar"))
	same(s:groups("Bar").center, { a, b }, "centre")
	local function gap()
		local _, _, r1 = s:rect(s:button(a))
		local l2 = s:rect(s:button(b))
		return l2 - r1
	end
	local function middle()
		local l1 = s:rect(s:button(a))
		local _, _, r2 = s:rect(s:button(b))
		return (l1 + r2) / 2
	end
	near(gap(), s.G.Titan_G.vars.PanelGet("ButtonSpacing"), 0.6, "centre gap before it is set")
	local slider = f.sliders[2].widget
	s:run(function()
		local thumb = slider.Slider or slider
		thumb:SetValue(4)
	end)
	s:advance()
	assert(s.A:Profile().centerSpacing == 4, "centre spacing not saved")
	near(gap(), 4, 0.6, "centre gap")
	near(middle(), (bl + br) / 2, 1.5, "centre pair's middle")
	-- The left side keeps Titan's own spacing.
	assert(s.G.Titan_G.vars.PanelGet("ButtonSpacing") ~= 4, "Button Spacing changed with the centre")
	s:run(function()
		s.A:Revert()
	end)
	assert(s.A:Profile().centerSpacing == nil, "centre spacing not restored by Revert")
	return s
end)

scenario("the spacing sliders share one range, and Centre is greyed until a plugin is in the centre", function()
	local s = boot()
	s:arrange()
	local f = s.ns.Panel.Frame()
	for i, sl in ipairs(f.sliders) do
		assert(sl.min == 0 and sl.max == 80, "slider " .. i .. " runs " .. sl.min .. " to " .. sl.max)
	end
	assert(not f.sliders[2].enabled, "Centre slider enabled with nothing in the centre")
	local box = s.ns.Overlays.BarBox("Titan_Bar__Display_Bar")
	assert(box.labels[2]:IsShown(), "the bar does not say Centre")
	assert(not box.labels[1]:IsShown() and not box.labels[3]:IsShown(), "Left and Right shown while not dragging")
	local g = s:groups("Bar")
	local bl, _, br = s:rect(s:barFrame("Bar"))
	s:drag(g.left[1], (bl + br) / 2, s:barMid("Bar"))
	assert(f.sliders[2].enabled, "Centre slider still grey with a plugin in the centre")
	assert(not box.labels[2]:IsShown(), "the bar still says Centre over a centre plugin")
	return s
end)

scenario("margins on single plugins, on either side, from the popup, through Revert and a reload", function()
	local s = boot()
	local A = s.A
	s:arrange()
	local g = s:groups("Bar")
	local a, b = g.left[1], g.left[2]
	local r1, r2 = g.right[1], g.right[2]
	local before = {}
	for _, id in ipairs({ a, b, r1, r2 }) do
		before[id] = { s:rect(s:button(id)) }
	end
	local spacing = s.G.Titan_G.vars.PanelGet("ButtonSpacing")
	local icon = s.G.Titan_G.vars.PanelGet("IconSpacing")
	-- From the right edge of x to the left edge of y.
	local function between(x, y)
		local _, _, xr = s:rect(s:button(x))
		local yl = s:rect(s:button(y))
		return yl - xr
	end
	s:run(function()
		A:SetGap(a, "right", 15)
	end)
	s:advance()
	near(between(a, b), spacing + 15, 0.6, "gap after " .. a)
	s:run(function()
		A:SetGap(b, "left", 5)
	end)
	s:advance()
	near(between(a, b), spacing + 20, 0.6, "gap after " .. a .. " and before " .. b)
	-- The first left plugin's own left space moves it off the bar's edge.
	s:run(function()
		A:SetGap(a, "left", 10)
	end)
	s:advance()
	near(s:rect(s:button(a)), before[a][1] + 10, 0.6, a .. "'s left edge")
	-- The right side runs right to left: r2 sits left of r1.
	s:run(function()
		A:SetGap(r1, "left", 12)
	end)
	s:advance()
	near(between(r2, r1), icon + 12, 0.6, "gap left of " .. r1)
	s:run(function()
		A:SetGap(r1, "right", 7)
	end)
	s:advance()
	local _, _, rr = s:rect(s:button(r1))
	near(rr, before[r1][3] - 7, 0.6, r1 .. "'s right edge")
	-- The popup's sliders set the same thing.
	s.sim:click(s.ns.Overlays.Box(b))
	local popup = s.G.TitanArrangerPopup
	local slider = popup.space[2].widget
	s:run(function()
		local thumb = slider.Slider or slider
		thumb:SetValue(9)
	end)
	s:advance()
	assert(A:Gap(b, "right") == 9, "the popup's slider did not set the gap")
	-- Revert takes every gap away, and Titan's own places come back.
	s:run(function()
		A:Revert()
	end)
	s:advance()
	assert(next(A:Gaps()) == nil, "gaps left after Revert")
	for id, r in pairs(before) do
		local l, _, right = s:rect(s:button(id))
		near(l, r[1], 0.6, id .. "'s left after Revert")
		near(right, r[3], 0.6, id .. "'s right after Revert")
	end
	-- A gap is kept across a reload.
	s:run(function()
		A:SetGap(a, "right", 15)
		A:Exit()
	end)
	local again = s:reload()
	assert(again.A:Gap(a, "right") == 15, "gap lost on reload")
	local _, _, ar = again:rect(again:button(a))
	near(again:rect(again:button(b)) - ar, spacing + 15, 0.6, "gap after a reload")
	again.sim:expectNoErrors("TitanArranger")
	return s
end)

scenario("negative margins pull a plugin in, at most halfway over its neighbour and never off the bar", function()
	local s = boot()
	local A, G = s.A, s.G
	s:arrange()
	local g = s:groups("Bar")
	local a, b = g.left[1], g.left[2]
	local r1, r2 = g.right[1], g.right[2]
	local before = {}
	for _, id in ipairs({ a, b, r1, r2 }) do
		before[id] = { s:rect(s:button(id)) }
	end
	local spacing = G.Titan_G.vars.PanelGet("ButtonSpacing")
	local icon = G.Titan_G.vars.PanelGet("IconSpacing")
	local barL, _, barR = s:rect(s:barFrame("Bar"))
	local function set(id, side, v)
		s:run(function()
			A:SetGap(id, side, v)
		end)
		s:advance()
	end
	local function edges(id)
		local l, _, r = s:rect(s:button(id))
		return l, r
	end
	-- From the right edge of x to the left edge of y.
	local function between(x, y)
		local _, xr = edges(x)
		return (edges(y)) - xr
	end
	local function width(id)
		local l, r = edges(id)
		return r - l
	end
	set(b, "left", -8)
	near(between(a, b), spacing - 8, 0.6, "space before " .. b)
	-- Pulled as far as it goes, b lies halfway over the narrower of the two, so half of each still shows.
	set(a, "right", -80)
	set(b, "left", -80)
	local narrower = math.min(width(a), width(b))
	assert(spacing - 160 < -narrower / 2, "the plugins are too wide for this check to reach the limit")
	near(between(a, b), -narrower / 2, 0.6, b .. " over " .. a)
	local al, ar = edges(a)
	local bl, br = edges(b)
	assert(bl - al >= narrower / 2 - 0.6 and br - ar >= narrower / 2 - 0.6, b .. " hid more than half of " .. a)
	-- The first plugin stops at the bar's left edge.
	set(a, "left", -3)
	near((edges(a)), before[a][1] - 3, 0.6, a .. "'s left edge")
	set(a, "left", -80)
	near((edges(a)), barL, 0.6, a .. " at the bar's left edge")
	-- On the right the first stops at the bar's right edge, and the next may overlap it.
	set(r1, "right", -80)
	local _, rr = edges(r1)
	near(rr, barR, 0.6, r1 .. " at the bar's right edge")
	set(r1, "left", -6)
	near(between(r2, r1), icon - 6, 0.6, "space left of " .. r1)
	-- The popup's sliders go below zero too. (Its box, not the Arranger button's: a click on that one stops arranging.)
	s.sim:click(s.ns.Overlays.Box(b))
	local sl = G.TitanArrangerPopup.space[1]
	assert(sl.min == -80 and sl.max == 80, "margin slider runs " .. sl.min .. " to " .. sl.max)
	s:run(function()
		local thumb = sl.widget.Slider or sl.widget
		thumb:SetValue(-5)
	end)
	s:advance()
	assert(A:Gap(b, "left") == -5, "the popup's slider did not set a negative margin")
	-- Margins back at zero are gone, and Titan's own places come back.
	for _, id in ipairs({ a, b, r1, r2 }) do
		set(id, "left", 0)
		set(id, "right", 0)
	end
	assert(next(A:Gaps()) == nil, "zero margins kept")
	for id, r in pairs(before) do
		local l, right = edges(id)
		near(l, r[1], 0.6, id .. "'s left with no margins")
		near(right, r[3], 0.6, id .. "'s right with no margins")
	end
	-- A centre pair pulled together as far as it goes stays centred on the bar.
	s:drag(a, (barL + barR) / 2, s:barMid("Bar"))
	local _, ar2 = edges(a)
	s:drag(b, ar2 + 1, s:barMid("Bar"))
	same(s:groups("Bar").center, { a, b }, "centre")
	set(a, "right", -80)
	set(b, "left", -80)
	al, ar = edges(a)
	bl, br = edges(b)
	assert(bl - al >= narrower / 2 - 0.6 and br - ar >= narrower / 2 - 0.6, b .. " hid " .. a .. " in the centre")
	near((al + br) / 2, (barL + barR) / 2, 1.5, "centre pair's middle")
	return s
end)

scenario("auto-hide bars stay out while arranging, and slide away again once the mouse leaves", function()
	local s = boot()
	local G = s.G
	local frameName = G.Titan_G.vars.GetFrameName("Bar")
	local bar = G[frameName]
	-- Titan hides a bar by moving it off the screen and showing its hider strip in its place.
	local hider = G[G.TitanBarData[frameName].hider]
	local function out()
		return not hider:IsShown()
	end
	s:run(function()
		G.Titan_G.bars.ToggleHide("Bar")
	end)
	assert(not out(), "Titan's auto-hide did not hide the top bar")
	s:arrange()
	assert(out(), "arranging did not bring the auto-hide bar out")
	-- From the bar onto a plugin's box (the bar's OnLeave starts Titan's timer), then away to the panel.
	s.sim:hover(bar)
	s.sim:hover(s.ns.Overlays.Box("Arranger"))
	s.sim:hover(s.ns.Panel.Frame())
	s:advance(1.5)
	assert(out(), "the bar slid away while arranging")
	-- What a zone change runs: Titan puts every bar back as its options say, which hides auto-hide bars.
	s:run(function()
		G.Titan_G.bars.DisplayBarsWanted("test")
	end)
	s:advance(1.5)
	assert(out(), "the bar slid away after Titan redid its bars while arranging")
	-- Stopping with the mouse on the bar keeps it out until the mouse goes, as Titan does.
	s.sim:hover(s.ns.Overlays.Box("Arranger"))
	s.sim:slash("/arranger")
	assert(not s.A.arranging, "/arranger did not stop arranging")
	s:advance(1.5)
	assert(out(), "the bar slid away from under the mouse")
	s.sim:hover(G.UIParent)
	s:advance(1.5)
	assert(not out(), "the bar did not slide away after arranging")
	return s
end)

scenario("every client surface, in and out of combat and across a reload, with arranging on", function()
	local s = boot()
	s:arrange()
	s.sim:exercise({ addons = { "TitanArranger" } })
	return s
end)

---------------------------------------------------------------------------------------------------------------------

local filter = arg[1]
local passed, failed = 0, 0
for _, sc in ipairs(scenarios) do
	if not filter or sc.name:find(filter, 1, true) then
		local ok, result = pcall(sc.fn)
		if ok and type(result) == "table" and result.sim then
			ok, result = pcall(result.sim.expectNoErrors, result.sim, "TitanArranger")
		end
		if ok then
			passed = passed + 1
			print("PASS " .. sc.name)
		else
			failed = failed + 1
			print("FAIL " .. sc.name .. "\n     " .. tostring(result):gsub("\n", "\n     "))
		end
	end
end
print(passed .. " passed, " .. failed .. " failed")
os.exit(failed == 0 and 0 or 1)
