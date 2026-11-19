-- Everything Arranger reads from or writes to Titan Panel goes through here. Most of it is Titan's internal state
-- (Titan_G, TitanPanelSettings, TitanBarData), which changes between Titan releases, so Missing() checks it at load
-- and Arranger stays off when anything is not there.
local _, ns = ...

local T = {}
ns.Titan = T

local function fn(t, key)
	return type(t) == "table" and type(t[key]) == "function"
end

function T.Missing()
	local miss = {}
	local function need(ok, name)
		if not ok then
			miss[#miss + 1] = name
		end
	end
	local G = Titan_G
	need(type(G) == "table", "Titan_G")
	if type(G) == "table" then
		need(fn(G.bars, "ShowPlugins"), "Titan_G.bars.ShowPlugins")
		need(fn(G.bars, "Justify"), "Titan_G.bars.Justify")
		need(fn(G.plugins, "GetVar"), "Titan_G.plugins.GetVar")
		need(fn(G.plugins, "SetVar"), "Titan_G.plugins.SetVar")
		need(fn(G.plugins, "IsRegistered"), "Titan_G.plugins.IsRegistered")
		need(fn(G.plugins, "Get"), "Titan_G.plugins.Get")
		need(fn(G.plugins, "ToRight"), "Titan_G.plugins.ToRight")
		need(fn(G.plugins, "UpdateButton"), "Titan_G.plugins.UpdateButton")
		need(type(G.plugins) == "table" and type(G.plugins.index) == "table", "Titan_G.plugins.index")
		need(fn(G.vars, "GetFrameName"), "Titan_G.vars.GetFrameName")
		need(fn(G.vars, "PanelGet"), "Titan_G.vars.PanelGet")
		need(fn(G.vars, "PanelSet"), "Titan_G.vars.PanelSet")
	end
	need(type(TitanBarData) == "table", "TitanBarData")
	need(type(TitanBarDataVars) == "table", "TitanBarDataVars")
	need(type(TitanUtils_GetButton) == "function", "TitanUtils_GetButton")
	return miss
end

-- Titan fills TitanPanelSettings from the profile at PLAYER_ENTERING_WORLD.
function T.Ready()
	local p = TitanPanelSettings
	return type(p) == "table" and type(p.Buttons) == "table" and type(p.Location) == "table"
end

function T.Buttons()
	return TitanPanelSettings.Buttons
end

function T.Locations()
	return TitanPanelSettings.Location
end

function T.IsRegistered(id)
	return id ~= nil and Titan_G.plugins.IsRegistered(id) and true or false
end

function T.Registry(id)
	return Titan_G.plugins.Get(id)
end

function T.Button(id)
	return (TitanUtils_GetButton(id))
end

-- A plugin that is listed on a bar and drawn there.
function T.IsOnScreen(id)
	if not T.IsRegistered(id) then
		return false
	end
	local b = T.Button(id)
	return b ~= nil and b:IsShown()
end

function T.IsListed(id)
	for _, v in ipairs(T.Buttons()) do
		if v == id then
			return true
		end
	end
	return false
end

function T.GetVar(id, var)
	return Titan_G.plugins.GetVar(id, var)
end

function T.SetVar(id, var, value)
	Titan_G.plugins.SetVar(id, var, value)
end

function T.UpdateButton(id)
	Titan_G.plugins.UpdateButton(id, 1)
end

function T.ForceBar(id)
	local f = T.GetVar(id, "ForceBar")
	if type(f) == "string" and f ~= "" then
		return f
	end
end

-- Plugins Titan keeps on the right whatever their setting.
function T.IsPinnedRight(id)
	for _, v in ipairs(Titan_G.plugins.NonMovable_Plugins or {}) do
		if v == id then
			return true
		end
	end
	return false
end

-- The auto-hide pins and other bar plugins, which belong to one bar and stay out of the plugin list.
function T.IsBarPlugin(id)
	local r = T.Registry(id)
	local cats = Titan_G.categories
	return r ~= nil and cats ~= nil and r.category == cats.TitanBar
end

function T.SideOf(id, center)
	if Titan_G.plugins.ToRight(id) then
		return "right"
	elseif center[id] then
		return "center"
	end
	return "left"
end

function T.Name(id)
	local r = T.Registry(id)
	local name = r and (r.menuText_NC or r.menuText) or tostring(id)
	name = tostring(name):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return name
end

function T.Icon(id)
	local r = T.Registry(id)
	return r and r.icon
end

-- Registered plugin ids, sorted by name.
function T.PluginIds()
	local ids = {}
	for _, id in pairs(Titan_G.plugins.index) do
		if T.IsRegistered(id) then
			ids[#ids + 1] = id
		end
	end
	table.sort(ids, function(a, b)
		return T.Name(a):lower() < T.Name(b):lower()
	end)
	return ids
end

-- Titan's bars in its own order: { name, frameName, frame, short }.
function T.Bars()
	local list = {}
	for frameName, data in pairs(TitanBarData) do
		local frame = _G[frameName]
		if frame and type(data) == "table" and data.name then
			list[#list + 1] = {
				name = data.name,
				frameName = frameName,
				frame = frame,
				short = data.user_move and true or false,
				order = data.order or 99,
			}
		end
	end
	table.sort(list, function(a, b)
		return a.order < b.order
	end)
	return list
end

function T.Bar(name)
	for _, bar in ipairs(T.Bars()) do
		if bar.name == name then
			return bar
		end
	end
end

function T.BarShown(bar)
	local v = TitanBarDataVars[bar.frameName]
	return v ~= nil and v.show and bar.frame:IsShown() and true or false
end

-- The top edge, in screen pixels, of the highest full-width bar shown at the bottom of the screen, or nil.
function T.BottomBarsTop()
	local top
	for _, bar in ipairs(T.Bars()) do
		local data = TitanBarData[bar.frameName]
		local t = data and data.vert == TITAN_BOTTOM and T.BarShown(bar) and bar.frame:GetTop()
		if t then
			t = t * bar.frame:GetEffectiveScale()
			top = math.max(top or t, t)
		end
	end
	return top
end

function T.PluginYOffset(bar)
	local d, v = TitanBarData[bar.frameName], TitanBarDataVars[bar.frameName]
	return (d and d.plugin_y_offset or 0) + (v and v.plugin_off_y or 0)
end

function T.PluginXOffset(bar)
	local d = TitanBarData[bar.frameName]
	return d and d.plugin_x_offset or 0
end

function T.IsCentred(bar)
	local v = TitanBarDataVars[bar.frameName]
	return v ~= nil and TITAN_PANEL_BUTTONS_ALIGN_CENTER ~= nil and v.align == TITAN_PANEL_BUTTONS_ALIGN_CENTER
end

function T.Relayout(reason)
	Titan_G.bars.ShowPlugins("Arranger: " .. tostring(reason))
end

-- Titan's settings key for the profile in use: the one whose Panel table is TitanPanelSettings, which also follows
-- Titan's profile sync.
function T.ProfileKey()
	local all = TitanSettings
	if type(all) == "table" and type(all.Players) == "table" then
		for key, p in pairs(all.Players) do
			if type(p) == "table" and p.Panel == TitanPanelSettings then
				return key
			end
		end
	end
	return "?"
end

function T.Locked()
	return Titan_G.vars.PanelGet("LockButtons") and true or false
end

function T.SetLocked(locked)
	Titan_G.vars.PanelSet("LockButtons", locked and true or false)
end

-- What Titan's own drag closes first.
function T.CloseMenusAndTips()
	local c = Titan_G.control
	if c and type(c.CloseAllControlFrames) == "function" then
		pcall(c.CloseAllControlFrames)
	end
	if type(TitanPanelRightClickMenu_Close) == "function" then
		pcall(TitanPanelRightClickMenu_Close)
	end
	if TitanPanelTooltip and TitanPanelTooltip.Hide then
		TitanPanelTooltip:Hide()
	end
	GameTooltip:Hide()
end

-- Short bars: Titan saves a bar's place in its OnDragStop handler (bounds check, then SetBarPos), and Show puts a
-- bar where its saved values say.
function T.SaveBarPlace(bar)
	local stop = bar.frame:GetScript("OnDragStop")
	if stop then
		stop(bar.frame)
	end
end

function T.ShowBar(bar)
	if fn(Titan_G.bars, "Show") then
		Titan_G.bars.Show(bar.frameName)
	end
end

-- Titan's auto-hide: when the mouse leaves a full bar that has it, Titan starts a repeating AceTimer, owned by the
-- bar's frame name, which moves the bar off the screen and shows a thin hider strip in its place.
function T.AutoHides(frameName)
	local data, vars = TitanBarData[frameName], TitanBarDataVars[frameName]
	if type(data) ~= "table" or data.hider == nil or type(vars) ~= "table" then
		return false
	end
	return vars.show and vars.auto_hide and true or false
end

function T.StopHideTimer(frameName)
	local timers = LibStub and LibStub("AceTimer-3.0", true)
	if timers and T.AutoHides(frameName) then
		timers.CancelAllTimers(frameName)
	end
end

-- Titan's Show still keeps a bar away where its options say so (PvP, combat) and in pet battles.
function T.HoldBar(frameName)
	if T.AutoHides(frameName) and fn(Titan_G.bars, "Show") then
		T.StopHideTimer(frameName)
		Titan_G.bars.Show(frameName)
	end
end

-- As if the mouse had just left the bar: Titan hides it after its usual half second.
function T.ReleaseBar(frameName)
	if T.AutoHides(frameName) and fn(Titan_G.bars, "HideTimers") then
		Titan_G.bars.HideTimers(frameName, "Leave")
	end
end
