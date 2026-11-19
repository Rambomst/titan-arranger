-- Arranging on and off, the session's undo, Titan's layout hook, combat, Edit Mode, the slash command, the key
-- binding and the addon compartment entry.
local addonName, ns = ...

local T, Model, L = ns.Titan, ns.Model, ns.L

local A = { active = false, arranging = false }
ns.A = A
-- The addon's tables, for the scenario tests and for poking at it with /dump.
A.ns = ns
TitanArranger = A

-- The plugin settings and Titan settings an arranging session can change, restored by Revert.
local VARS = { "DisplayOnRightSide", "ShowIcon", "ShowLabelText", "ShowRegularText", "ShowColoredText" }
local PANEL_VARS = { "ButtonSpacing", "IconSpacing" }

local function say(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cffeda55f" .. L.TITLE .. "|r: " .. msg)
end
A.Say = say

local function copy(t)
	local out = {}
	for k, v in pairs(t) do
		out[k] = v
	end
	return out
end

local function refill(target, source)
	for i = #target, 1, -1 do
		target[i] = nil
	end
	for i, v in ipairs(source) do
		target[i] = v
	end
end

-- Auto-hide bars stay out while arranging: Titan slides a bar away half a second after the mouse leaves it, and a
-- box over a plugin, the panel and every drag count as leaving. Afterwards each bar goes back to Titan once the
-- mouse is off it; the bar's own OnLeave may already have fired (onto a box), so that is watched for here.
local releasing = {}
local releaser = CreateFrame("Frame")
releaser:Hide()
releaser:SetScript("OnUpdate", function(self)
	for frameName in pairs(releasing) do
		local frame = _G[frameName]
		if not (frame and frame:IsMouseOver()) then
			releasing[frameName] = nil
			T.ReleaseBar(frameName)
		end
	end
	if not next(releasing) then
		self:Hide()
	end
end)

local function holdBars()
	wipe(releasing)
	releaser:Hide()
	for _, bar in ipairs(T.Bars()) do
		T.HoldBar(bar.frameName)
	end
end

local function releaseBars()
	for _, bar in ipairs(T.Bars()) do
		if T.AutoHides(bar.frameName) then
			releasing[bar.frameName] = true
		end
	end
	if next(releasing) then
		releaser:Show()
	end
end

-- Titan prunes keys it does not know from its own saved data, so Arranger's per-profile settings (the centre flags
-- and the centre spacing) live here, keyed by Titan profile.
function A:Profile()
	local profiles = TitanArrangerDB.profiles
	local key = T.ProfileKey()
	local p = profiles[key]
	if not p then
		p = {}
		profiles[key] = p
	end
	p.center = p.center or {}
	return p
end

function A:CenterFlags()
	return self:Profile().center
end

-- A plugin's own margins, on top of its side's spacing, in Titan's spacing units: gaps[id] = { left = n, right = n }.
-- A negative one pulls the plugin towards its neighbour or the bar's edge.
function A:Gaps()
	local p = self:Profile()
	p.gaps = p.gaps or {}
	return p.gaps
end

function A:Gap(id, side)
	local g = self:Gaps()[id]
	return g and tonumber(g[side]) or 0
end

function A:SetGap(id, side, value)
	local gaps = self:Gaps()
	local g = gaps[id] or {}
	g[side] = value ~= 0 and value or nil
	gaps[id] = next(g) and g or nil
	-- Through Titan's own layout, so taking the last gap away gives the group back Titan's anchors.
	T.Relayout("gap " .. tostring(id))
end

function A:SetSide(id, side)
	T.SetVar(id, "DisplayOnRightSide", side == "right" and 1 or false)
	self:CenterFlags()[id] = side == "center" or nil
end

function A:Changed()
	self.dirty = true
	if self.arranging then
		ns.Overlays.Refresh()
		ns.Panel.Refresh()
		ns.Popup.Refresh()
	end
end

function A:Snapshot()
	local s = {
		buttons = copy(T.Buttons()),
		locations = copy(T.Locations()),
		center = copy(self:CenterFlags()),
		centerSpacing = self:Profile().centerSpacing,
		gaps = {},
		vars = {},
		bars = {},
		panel = {},
	}
	for _, var in ipairs(PANEL_VARS) do
		s.panel[var] = Titan_G.vars.PanelGet(var)
	end
	for id, g in pairs(self:Gaps()) do
		s.gaps[id] = copy(g)
	end
	for _, id in ipairs(T.PluginIds()) do
		local v = {}
		for _, var in ipairs(VARS) do
			v[var] = T.GetVar(id, var)
		end
		s.vars[id] = v
	end
	for _, bar in ipairs(T.Bars()) do
		local d = TitanBarDataVars[bar.frameName]
		if bar.short and d then
			s.bars[bar.frameName] = { off_x = d.off_x, off_y = d.off_y, off_w = d.off_w }
		end
	end
	self.snapshot = s
	self.dirty = false
end

function A:Revert()
	local s = self.snapshot
	if not s or not self.arranging or InCombatLockdown() then
		return
	end
	ns.Drag.Cancel()
	ns.Popup.Close()
	ns.Overlays.Select(nil)
	local buttons, locations = T.Buttons(), T.Locations()
	local keep = {}
	for _, id in ipairs(s.buttons) do
		keep[id] = true
	end
	for _, id in ipairs(buttons) do
		local b = not keep[id] and T.Button(id)
		if b then
			b:Hide()
		end
	end
	refill(buttons, s.buttons)
	refill(locations, s.locations)
	for id, v in pairs(s.vars) do
		for _, var in ipairs(VARS) do
			T.SetVar(id, var, v[var])
		end
	end
	for _, var in ipairs(PANEL_VARS) do
		Titan_G.vars.PanelSet(var, s.panel[var])
	end
	local center = self:CenterFlags()
	for id in pairs(center) do
		center[id] = nil
	end
	for id, on in pairs(s.center) do
		center[id] = on
	end
	self:Profile().centerSpacing = s.centerSpacing
	local gaps = self:Gaps()
	for id in pairs(gaps) do
		gaps[id] = nil
	end
	for id, g in pairs(s.gaps) do
		gaps[id] = copy(g)
	end
	for _, bar in ipairs(T.Bars()) do
		local pos, d = s.bars[bar.frameName], TitanBarDataVars[bar.frameName]
		if pos and d then
			d.off_x, d.off_y, d.off_w = pos.off_x, pos.off_y, pos.off_w
			if T.BarShown(bar) then
				T.ShowBar(bar)
			end
		end
	end
	for _, id in ipairs(buttons) do
		if T.IsRegistered(id) then
			T.UpdateButton(id)
		end
	end
	T.Relayout("revert")
	self.dirty = false
	ns.Overlays.Refresh()
	ns.Panel.Refresh()
end

function A:Enter(reason)
	if not self.active or not T.Ready() then
		return
	end
	if self.arranging then
		if reason == "manual" then
			self.reason = "manual"
		end
		return
	end
	if InCombatLockdown() then
		say(L.NOT_IN_COMBAT)
		return
	end
	self.arranging = true
	self.reason = reason
	self.profile = T.ProfileKey()
	T.SetLocked(false)
	self:Snapshot()
	T.CloseMenusAndTips()
	holdBars()
	ns.Overlays.Refresh()
	ns.Panel.Show(reason)
end

function A:Exit()
	if not self.arranging then
		return
	end
	ns.Drag.Cancel()
	ns.Popup.Close()
	ns.Overlays.Select(nil)
	self.arranging = false
	self.reason = nil
	self.snapshot = nil
	self.dirty = false
	T.SetLocked(true)
	ns.Overlays.HideAll()
	ns.Panel.Hide()
	releaseBars()
end

function A:Toggle(reason)
	if self.arranging then
		self:Exit()
	else
		self:Enter(reason or "manual")
	end
end

function A:IsArranging()
	return self.arranging
end

-- One place left or right on screen, for the arrow keys.
function A:Step(id, dir)
	if not self.arranging or InCombatLockdown() then
		return
	end
	local buttons, locations = T.Buttons(), T.Locations()
	local center = self:CenterFlags()
	local m = Model.Build(buttons, locations, function(pid)
		return T.SideOf(pid, center)
	end)
	local bar, side, k = Model.StepTarget(m, id, dir, T.IsOnScreen, T.IsPinnedRight(id))
	if not bar then
		return
	end
	Model.Move(m, id, bar, side, k, function(pid)
		return pid ~= id and T.IsOnScreen(pid)
	end)
	Model.Write(m, buttons, locations)
	self:SetSide(id, side)
	T.Relayout("step " .. tostring(id))
	self:Changed()
end

-- After every Titan layout (profile load, a plugin shown or hidden, config changes).
function A:OnTitanLayout()
	if not self.active or not T.Ready() or self.inLayout then
		return
	end
	self.inLayout = true
	local ok, err = pcall(function()
		if not self.ready then
			self.ready = true
			ns.Plugin.WrapBarMenus()
		end
		-- Every Titan profile has its own Lock Buttons; whichever is in use stays locked unless arranging.
		if not self.arranging and not T.Locked() then
			T.SetLocked(true)
		end
		if self.arranging and self.profile ~= T.ProfileKey() then
			self:Exit()
			say(L.PROFILE_CHANGED)
		end
		-- A plugin Titan's own menu moved to the right is no longer in the centre.
		local center = self:CenterFlags()
		for id in pairs(center) do
			if Titan_G.plugins.ToRight(id) then
				center[id] = nil
			end
		end
		ns.Plugin.PlaceOnce()
		if ns.Layout.Normalize() then
			T.Relayout("order")
		end
		ns.Layout.Apply()
		if self.arranging then
			ns.Overlays.Refresh()
			ns.Panel.Refresh()
		end
	end)
	self.inLayout = false
	if not ok then
		geterrorhandler()(err)
	end
end

function A:Init()
	TitanArrangerDB = type(TitanArrangerDB) == "table" and TitanArrangerDB or {}
	local db = TitanArrangerDB
	db.settings = type(db.settings) == "table" and db.settings or {}
	db.profiles = type(db.profiles) == "table" and db.profiles or {}
	if db.settings.withEditMode == nil then
		db.settings.withEditMode = true
	end

	local missing = T.Missing()
	if #missing > 0 then
		say(L.UNSUPPORTED:format(table.concat(missing, ", ")))
		return
	end
	self.active = true

	hooksecurefunc(Titan_G.bars, "ShowPlugins", function()
		A:OnTitanLayout()
	end)
	hooksecurefunc(Titan_G.bars, "Justify", function()
		if not A.inLayout then
			ns.Layout.Apply()
		end
	end)
	-- While arranging, Titan's auto-hide timer is stopped as soon as it starts, and a bar Titan hides again (a zone
	-- change, its pin, its options) comes straight back.
	if type(Titan_G.bars.HideTimers) == "function" then
		hooksecurefunc(Titan_G.bars, "HideTimers", function(frameName, action)
			if A.arranging and action == "Leave" then
				T.StopHideTimer(frameName)
			end
		end)
	end
	if type(Titan_G.bars.HideInit) == "function" then
		hooksecurefunc(Titan_G.bars, "HideInit", function(frameName)
			if A.arranging then
				T.HoldBar(frameName)
			end
		end)
	end
	-- A bar shown or hidden from Titan's options or bar menu moves the boxes, and how far down the panel may grow.
	if type(Titan_G.bars.DisplayBarsWanted) == "function" then
		hooksecurefunc(Titan_G.bars, "DisplayBarsWanted", function()
			if A.arranging then
				ns.Overlays.Refresh()
				ns.Panel.Refresh()
			end
		end)
	end
	-- Titan's "Lock Buttons" option, ticked or unticked in its config, starts or stops arranging.
	if type(Titan_G.vars.PanelToggle) == "function" then
		hooksecurefunc(Titan_G.vars, "PanelToggle", function(var)
			if var ~= "LockButtons" or not A.ready then
				return
			end
			if T.Locked() then
				A:Exit()
			else
				A:Enter("manual")
			end
		end)
	end
	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("EditMode.Enter", function()
			if TitanArrangerDB.settings.withEditMode then
				A:Enter("editmode")
			end
		end, A)
		EventRegistry:RegisterCallback("EditMode.Exit", function()
			if A.arranging and A.reason == "editmode" then
				A:Exit()
			end
		end, A)
	end
	if T.Ready() then
		self:OnTitanLayout()
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(self, event, arg)
	if event == "ADDON_LOADED" then
		if arg == addonName then
			self:UnregisterEvent("ADDON_LOADED")
			A:Init()
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		if A.arranging then
			A:Exit()
			say(L.COMBAT_STOPPED)
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if ns.Layout.Pending() then
			ns.Layout.Apply()
		end
	end
end)

SLASH_TITANARRANGER1 = "/arranger"
SLASH_TITANARRANGER2 = "/titanarranger"
SlashCmdList.TITANARRANGER = function(msg)
	local cmd = (msg or ""):lower():match("^%s*(%S*)")
	if cmd == "" or cmd == "toggle" then
		A:Toggle("manual")
	elseif cmd == "lock" then
		A:Exit()
	elseif cmd == "unlock" then
		A:Enter("manual")
	elseif cmd == "revert" then
		A:Revert()
	else
		say(L.SLASH_HELP)
	end
end

function TitanArranger_Toggle()
	A:Toggle("manual")
end

function TitanArranger_OnAddonCompartmentClick()
	A:Toggle("manual")
end

function TitanArranger_OnAddonCompartmentEnter(_, frame)
	GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
	GameTooltip:SetText(L.TITLE)
	GameTooltip:AddLine(A.arranging and L.ARRANGING or L.LOCKED, 1, 1, 1)
	GameTooltip:AddLine(A.arranging and L.CLICK_TO_LOCK or L.CLICK_TO_ARRANGE, 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

function TitanArranger_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end
