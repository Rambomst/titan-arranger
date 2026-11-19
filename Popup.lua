-- A plugin's options, for the plugin clicked while arranging: its side, the display choices Titan offers for it
-- (only those its registry lists), its margins, and Hide. The same dialog look as the panel: Blizzard's translucent border, a
-- Titan bar strip with the plugin's icon and name as the title.
local _, ns = ...

local T, Model, L = ns.Titan, ns.Model, ns.L

local Popup = {}
ns.Popup = Popup

local frame
local WIDTH = 240
local PAD = 16

local OPTIONS = {
	{ var = "ShowIcon", label = L.SHOW_ICON },
	{ var = "ShowLabelText", label = L.SHOW_LABEL },
	{ var = "ShowRegularText", label = L.SHOW_TEXT },
	{ var = "ShowColoredText", label = L.SHOW_COLOURED },
}
local SIDES = { { "left", L.LEFT }, { "center", L.CENTER }, { "right", L.RIGHT } }

local function moveToSide(id, side)
	local buttons, locations = T.Buttons(), T.Locations()
	local center = ns.A:CenterFlags()
	local m = Model.Build(buttons, locations, function(pid)
		return T.SideOf(pid, center)
	end)
	local bar = Model.Find(m, id)
	if not bar then
		return
	end
	local function visible(pid)
		return pid ~= id and T.IsOnScreen(pid)
	end
	-- The inner end of the new side, next to the middle, as Titan's own checkbox does it.
	Model.Move(m, id, bar, side, #Model.Visible(m, bar, side, visible) + 1, visible)
	Model.Write(m, buttons, locations)
	ns.A:SetSide(id, side)
	T.Relayout("side " .. tostring(id))
	ns.A:Changed()
end

local function build()
	local f = CreateFrame("Frame", "TitanArrangerPopup", UIParent)
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:SetSize(WIDTH, 200)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	ns.Theme.Dialog(f)

	f.strip = CreateFrame("Frame", nil, f)
	f.strip:SetPoint("TOPLEFT", 8, -8)
	f.strip:SetPoint("TOPRIGHT", -8, -8)
	f.strip:SetHeight(ns.Theme.STRIP)
	f.icon = f.strip:CreateTexture(nil, "ARTWORK")
	f.icon:SetSize(16, 16)
	f.icon:SetPoint("LEFT", 8, 0)
	f.title = f.strip:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	f.title:SetPoint("RIGHT", -24, 0)
	f.title:SetJustifyH("LEFT")
	f.title:SetTextColor(1, 0.82, 0)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 0, 0)
	close:SetScript("OnClick", function()
		Popup.Close()
		ns.Overlays.Select(nil)
	end)

	f.sideLabel = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	f.sideLabel:SetPoint("TOPLEFT", PAD, -44)
	f.sideLabel:SetText(L.SIDE)
	f.sides = {}
	local w = math.floor((WIDTH - 2 * PAD - 8) / 3)
	for i, s in ipairs(SIDES) do
		local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		b:SetSize(w, 22)
		b:SetText(s[2])
		b:SetPoint("TOPLEFT", PAD + (i - 1) * (w + 4), -64)
		b:SetScript("OnClick", function()
			moveToSide(f.id, s[1])
		end)
		b.side = s[1]
		f.sides[i] = b
	end
	f.checks = {}
	for i, o in ipairs(OPTIONS) do
		local c = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
		c:SetSize(26, 26)
		c.label = c:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		c.label:SetPoint("LEFT", c, "RIGHT", 4, 0)
		c.label:SetText(o.label)
		c.var = o.var
		c:SetScript("OnClick", function(self)
			T.SetVar(f.id, self.var, self:GetChecked() and 1 or false)
			T.UpdateButton(f.id)
			T.Relayout("option " .. tostring(f.id))
			ns.A:Changed()
		end)
		f.checks[i] = c
	end
	-- This plugin's margins, on top of its side's spacing: below 0 it moves towards its neighbour, as far as
	-- overlapping it.
	f.spaceLabel = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	f.spaceLabel:SetText(L.MARGIN)
	f.space = {}
	for i, side in ipairs({ "left", "right" }) do
		local s = ns.Theme.Slider(f, i == 1 and L.SPACE_LEFT or L.SPACE_RIGHT, -80, 80, function()
			return f.id and ns.A:Gap(f.id, side) or 0
		end, function(v)
			if f.id then
				ns.A:SetGap(f.id, side, v)
			end
		end, 44)
		s.side = side
		f.space[i] = s
	end
	f.hide = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.hide:SetSize(WIDTH - 2 * PAD, 24)
	f.hide:SetText(L.HIDE)
	f.hide:SetScript("OnClick", function()
		local id = f.id
		Popup.Close()
		ns.Overlays.Select(nil)
		ns.Drag.HidePlugin(id)
	end)
	f:Hide()
	return f
end

function Popup.Open(id, anchor)
	frame = frame or build()
	local f = frame
	f.id, f.anchor = id, anchor
	ns.Theme.Strip(f, f.strip)
	ns.Theme.Font(f.title, 2)
	ns.Theme.Font(f.sideLabel, 1)
	local icon = T.Icon(id)
	f.icon:SetTexture(icon)
	f.icon:SetShown(icon ~= nil and icon ~= "")
	f.title:ClearAllPoints()
	f.title:SetPoint("LEFT", f.icon:IsShown() and 30 or 10, 0)
	f.title:SetPoint("RIGHT", -24, 0)
	f.title:SetText(T.Name(id))
	local side = T.SideOf(id, ns.A:CenterFlags())
	local pinned = T.IsPinnedRight(id)
	for _, b in ipairs(f.sides) do
		local current = b.side == side
		b:SetEnabled(not current and (not pinned or b.side == "right"))
		-- The current side reads as chosen: its button lit, the others plain.
		if b.LockHighlight then
			if current then
				b:LockHighlight()
			else
				b:UnlockHighlight()
			end
		end
	end
	local reg = T.Registry(id)
	local controls = reg and reg.controlVariables or {}
	local y = -96
	for _, c in ipairs(f.checks) do
		if controls[c.var] then
			ns.Theme.Font(c.label, 1)
			c:ClearAllPoints()
			c:SetPoint("TOPLEFT", PAD - 4, y)
			c:SetChecked(T.GetVar(id, c.var) and true or false)
			c:Show()
			y = y - 26
		else
			c:Hide()
		end
	end
	y = y - 8
	ns.Theme.Font(f.spaceLabel, 1)
	f.spaceLabel:ClearAllPoints()
	f.spaceLabel:SetPoint("TOPLEFT", PAD, y)
	y = y - 20
	for _, s in ipairs(f.space) do
		ns.Theme.Font(s.label, 1)
		s.row:ClearAllPoints()
		s.row:SetPoint("TOPLEFT", PAD, y)
		s.row:SetPoint("TOPRIGHT", -PAD, y)
		s.Set(s.get())
		y = y - 28
	end
	f.hide:ClearAllPoints()
	f.hide:SetPoint("TOPLEFT", PAD, y - 8)
	f:SetHeight(-y + 48)
	-- Below a plugin on the upper half of the screen, above one on the lower half.
	f:ClearAllPoints()
	local _, cy = anchor:GetCenter()
	if cy and cy * anchor:GetEffectiveScale() > (UIParent:GetHeight() * UIParent:GetEffectiveScale()) / 2 then
		f:SetPoint("TOP", anchor, "BOTTOM", 0, -6)
	else
		f:SetPoint("BOTTOM", anchor, "TOP", 0, 6)
	end
	f:Show()
end

function Popup.Close()
	if frame then
		frame:Hide()
		frame.id = nil
	end
end

function Popup.IsOpen()
	return frame ~= nil and frame:IsShown()
end

function Popup.Refresh()
	if frame and frame:IsShown() and frame.id then
		local box = ns.Overlays.Box(frame.id)
		if box and box:IsShown() then
			Popup.Open(frame.id, box)
		else
			Popup.Close()
		end
	end
end
