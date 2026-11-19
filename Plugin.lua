-- Arranger's own Titan plugin, the Arranger button on the bar. Click it to start or stop arranging; its menu has the
-- same choices as the panel. Every Titan bar's right-click menu also gets an "Arrange plugins" line.
local addonName, ns = ...

local T, L = ns.Titan, ns.L

local Plugin = {}
ns.Plugin = Plugin

Plugin.ID = "Arranger"
-- Blizzard's reorder icon (the Cooldown Manager settings use it), turned a quarter anticlockwise so its tiles sit
-- side by side like plugins on a bar. The TOC's IconAtlas shows it upright: the addon list cannot turn an icon.
Plugin.ATLAS = "icon_buffreorder"
Plugin.FALLBACK = "Interface\\Cursor\\UI-Cursor-Move"

-- Titan draws registry.icon with SetTexture and passes registry.iconCoords to SetTexCoord on every update, so the
-- atlas goes in as its file and its own corners, in the turned order.
function Plugin.Art()
	local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(Plugin.ATLAS)
	local file = info and ((info.file or 0) > 0 and info.file or info.filename)
	if not file then
		return Plugin.FALLBACK
	end
	local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
	-- Corners in SetTexCoord's order (top left, bottom left, top right, bottom right): the art's top right corner
	-- comes to the top left.
	return file, { r, t, l, t, r, b, l, b }
end

local GetMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata

function TitanArranger_TooltipText()
	if ns.A.arranging then
		return L.ARRANGING .. "\n" .. L.CLICK_TO_LOCK
	end
	return L.LOCKED .. "\n" .. L.CLICK_TO_ARRANGE
end

local function menu(_, root)
	root:CreateCheckbox(L.ARRANGE, function()
		return ns.A.arranging
	end, function()
		ns.A:Toggle("manual")
	end)
	root:CreateCheckbox(L.WITH_EDIT_MODE, function()
		return TitanArrangerDB.settings.withEditMode and true or false
	end, function()
		local s = TitanArrangerDB.settings
		s.withEditMode = not s.withEditMode
		ns.Panel.Refresh()
	end)
	local revert = root:CreateButton(L.REVERT, function()
		ns.A:Revert()
	end)
	if revert and revert.SetEnabled then
		revert:SetEnabled(ns.A.arranging and ns.A.dirty and true or false)
	end
end

-- Titan's template queues the frame for registration when it is made; Titan reads the registry at
-- PLAYER_ENTERING_WORLD.
local button = CreateFrame("Button", "TitanPanel" .. Plugin.ID .. "Button", UIParent, "TitanPanelIconTemplate")
local icon, iconCoords = Plugin.Art()
button.registry = {
	id = Plugin.ID,
	category = "Interface",
	version = GetMetadata and GetMetadata(addonName, "Version") or "",
	menuText = L.NAME,
	tooltipTitle = L.TITLE,
	tooltipTextFunction = "TitanArranger_TooltipText",
	menuContextFunction = menu,
	icon = icon,
	iconCoords = iconCoords,
	iconWidth = 16,
	savedVariables = {
		ShowIcon = 1,
		DisplayOnRightSide = 1,
	},
}
button:SetScript("OnClick", function(self, mouse)
	if mouse == "LeftButton" then
		ns.A:Toggle("manual")
	else
		Titan_G.plugins.OnClick(self, mouse)
	end
end)
Plugin.button = button

-- Titan builds a bar's right-click menu from the bar's registry.menuContextFunction each time it opens.
function Plugin.WrapBarMenus()
	for _, bar in ipairs(T.Bars()) do
		local reg = bar.frame.registry
		if type(reg) == "table" and type(reg.menuContextFunction) == "function" and not reg.arrangerWrapped then
			local original = reg.menuContextFunction
			reg.menuContextFunction = function(owner, root, ...)
				original(owner, root, ...)
				root:CreateDivider()
				root:CreateCheckbox(L.ARRANGE, function()
					return ns.A.arranging
				end, function()
					ns.A:Toggle("manual")
				end)
			end
			reg.arrangerWrapped = true
		end
	end
end

-- The first time Arranger runs, its button goes on the first shown full-width bar, at the inner end of its right
-- side, so it can be found. After that it stays wherever it is put, hidden included. (The saved flag keeps the name
-- it had when the button was a padlock.)
function Plugin.PlaceOnce()
	local s = TitanArrangerDB.settings
	if s.padlockPlaced or not T.IsRegistered(Plugin.ID) then
		return
	end
	s.padlockPlaced = true
	if T.IsListed(Plugin.ID) then
		return
	end
	for _, bar in ipairs(T.Bars()) do
		if not bar.short and T.BarShown(bar) then
			ns.Drag.Drop(Plugin.ID, { bar = bar, side = "right", k = math.huge })
			return
		end
	end
end
