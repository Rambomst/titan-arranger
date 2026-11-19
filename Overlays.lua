-- While arranging, every plugin on a bar gets a blue box over it, the way Edit Mode marks its frames. The boxes take
-- the clicks and drags, so plugins do nothing of their own until arranging stops. Short bars get a box too, to drag
-- the bar about and size it by its right edge. A selected plugin or Short bar moves with the arrow keys.
local _, ns = ...

local T, L = ns.Titan, ns.L

local Overlays = {}
ns.Overlays = Overlays

local plugins = {} -- plugin id -> box
local bars = {} -- bar frame name -> box
local selected -- { kind = "plugin", id = id } or { kind = "bar", bar = bar }
local keys

local COLOURS = {
	normal = { 0.25, 0.55, 1, 0.16 },
	hover = { 0.25, 0.55, 1, 0.34 },
	selected = { 1, 0.82, 0, 0.32 },
}

local function edges(f, r, g, b, a)
	local function line()
		local t = f:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(r, g, b, a)
		return t
	end
	local top, bottom, left, right = line(), line(), line(), line()
	top:SetPoint("TOPLEFT")
	top:SetPoint("TOPRIGHT")
	top:SetHeight(1)
	bottom:SetPoint("BOTTOMLEFT")
	bottom:SetPoint("BOTTOMRIGHT")
	bottom:SetHeight(1)
	left:SetPoint("TOPLEFT")
	left:SetPoint("BOTTOMLEFT")
	left:SetWidth(1)
	right:SetPoint("TOPRIGHT")
	right:SetPoint("BOTTOMRIGHT")
	right:SetWidth(1)
end

local function isSelected(kind, key)
	if not selected or selected.kind ~= kind then
		return false
	end
	return (kind == "plugin" and selected.id == key) or (kind == "bar" and selected.bar.frameName == key)
end

local function paint(box, kind, key)
	local c = isSelected(kind, key) and COLOURS.selected or (box.hover and COLOURS.hover or COLOURS.normal)
	box.fill:SetColorTexture(c[1], c[2], c[3], c[4])
end

local function repaintAll()
	for id, box in pairs(plugins) do
		paint(box, "plugin", id)
	end
	for name, box in pairs(bars) do
		if box.fill then
			paint(box, "bar", name)
		end
	end
end

local function tooltip(owner, title, ...)
	GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
	GameTooltip:SetText(title)
	for i = 1, select("#", ...) do
		GameTooltip:AddLine((select(i, ...)), 1, 1, 1)
	end
	GameTooltip:Show()
end

local function makePluginBox(id, button)
	local box = CreateFrame("Button", nil, button)
	box:SetAllPoints(button)
	box:EnableMouse(true)
	box:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	box:RegisterForDrag("LeftButton")
	box.fill = box:CreateTexture(nil, "ARTWORK")
	box.fill:SetAllPoints()
	edges(box, 0.4, 0.7, 1, 0.9)
	box.id = id
	box:SetScript("OnEnter", function(self)
		self.hover = true
		paint(self, "plugin", self.id)
		if not ns.Drag.IsDragging() then
			local click = self.id == ns.Plugin.ID and L.CLICK_TO_FINISH or L.CLICK_FOR_OPTIONS
			tooltip(self, T.Name(self.id), L.DRAG_TO_MOVE, click)
		end
	end)
	box:SetScript("OnLeave", function(self)
		self.hover = false
		paint(self, "plugin", self.id)
		GameTooltip:Hide()
	end)
	box:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		ns.Drag.Start(self.id, "bar", button)
	end)
	box:SetScript("OnDragStop", function()
		ns.Drag.Stop()
	end)
	box:SetScript("OnClick", function(self, mouse)
		-- Arranger's own button keeps its job while arranging: a click on it stops arranging.
		if mouse == "LeftButton" and self.id == ns.Plugin.ID then
			ns.A:Exit()
		elseif mouse == "LeftButton" then
			Overlays.Select({ kind = "plugin", id = self.id })
			ns.Popup.Open(self.id, self)
		else
			Overlays.Select(nil)
			ns.Popup.Close()
		end
	end)
	return box
end

local function saveBar(bar)
	T.SaveBarPlace(bar)
	ns.A:Changed()
end

local function makeBarBox(bar)
	local box = CreateFrame("Frame", nil, bar.frame)
	box:SetAllPoints(bar.frame)
	box:SetFrameLevel(bar.frame:GetFrameLevel() + 1)
	box.labels = {}
	for _, spec in ipairs({ { "LEFT", L.LEFT, 8 }, { "CENTER", L.CENTER, 0 }, { "RIGHT", L.RIGHT, -8 } }) do
		local text = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		text:SetPoint(spec[1], box, spec[1], spec[3], 0)
		text:SetText(spec[2])
		text:Hide()
		box.labels[#box.labels + 1] = text
	end
	if bar.short then
		box.fill = box:CreateTexture(nil, "BACKGROUND")
		box.fill:SetAllPoints()
		edges(box, 0.4, 0.7, 1, 0.9)
		box:EnableMouse(true)
		box:RegisterForDrag("LeftButton")
		box:SetScript("OnEnter", function(self)
			self.hover = true
			paint(self, "bar", bar.frameName)
			if not ns.Drag.IsDragging() then
				tooltip(self, bar.frame.registry and bar.frame.registry.menuText or bar.name, L.SHORT_BAR_TIP)
			end
		end)
		box:SetScript("OnLeave", function(self)
			self.hover = false
			paint(self, "bar", bar.frameName)
			GameTooltip:Hide()
		end)
		box:SetScript("OnMouseUp", function(_, mouse)
			if mouse == "LeftButton" then
				Overlays.Select({ kind = "bar", bar = bar })
			end
		end)
		box:SetScript("OnDragStart", function(self)
			if InCombatLockdown() or not bar.frame:IsMovable() then
				return
			end
			GameTooltip:Hide()
			self.moving = true
			bar.frame:StartMoving()
		end)
		box:SetScript("OnDragStop", function(self)
			if self.moving then
				self.moving = nil
				bar.frame:StopMovingOrSizing()
				saveBar(bar)
			end
		end)
		local grip = CreateFrame("Frame", nil, box)
		grip:SetPoint("TOPRIGHT")
		grip:SetPoint("BOTTOMRIGHT")
		grip:SetWidth(8)
		grip:SetFrameLevel(box:GetFrameLevel() + 20)
		grip:EnableMouse(true)
		local mark = grip:CreateTexture(nil, "OVERLAY")
		mark:SetPoint("TOPRIGHT", -2, -4)
		mark:SetPoint("BOTTOMRIGHT", -2, 4)
		mark:SetWidth(2)
		mark:SetColorTexture(1, 0.82, 0, 0.9)
		grip:SetScript("OnMouseDown", function(self, mouse)
			if mouse == "LeftButton" and not InCombatLockdown() and bar.frame:IsResizable() then
				self.sizing = true
				bar.frame:StartSizing("RIGHT")
			end
		end)
		grip:SetScript("OnMouseUp", function(self)
			if self.sizing then
				self.sizing = nil
				bar.frame:StopMovingOrSizing()
				saveBar(bar)
			end
		end)
	end
	return box
end

local function nudge(bar, dx, dy)
	local f = bar.frame
	local l, b = f:GetLeft(), f:GetBottom()
	if not l then
		return
	end
	f:ClearAllPoints()
	f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l + dx, b + dy)
	saveBar(bar)
end

local function onKey(key)
	if not selected or not ns.A.arranging then
		return false
	end
	if key == "ESCAPE" then
		Overlays.Select(nil)
		ns.Popup.Close()
		return true
	end
	local dx = (key == "LEFT" and -1) or (key == "RIGHT" and 1) or 0
	local dy = (key == "DOWN" and -1) or (key == "UP" and 1) or 0
	if dx == 0 and dy == 0 then
		return false
	end
	if selected.kind == "plugin" then
		if dx == 0 then
			return false
		end
		ns.A:Step(selected.id, dx)
		ns.Popup.Close()
	else
		local step = IsShiftKeyDown() and 10 or 1
		nudge(selected.bar, dx * step, dy * step)
	end
	return true
end

Overlays.OnKey = onKey

function Overlays.Select(sel)
	selected = sel
	repaintAll()
	if not keys then
		keys = CreateFrame("Frame", nil, UIParent)
		keys:SetScript("OnKeyDown", function(self, key)
			local handled = onKey(key)
			if not InCombatLockdown() then
				self:SetPropagateKeyboardInput(not handled)
			end
		end)
	end
	keys:EnableKeyboard(sel ~= nil and ns.A.arranging and not InCombatLockdown())
end

function Overlays.Selected()
	return selected
end

-- Area names show on every bar while a plugin is being dragged.
-- Area names: all three on every bar while a plugin is dragged; otherwise, while arranging, "Centre" in the middle
-- of a bar whose centre area is empty, to show where it is.
local dragging = false

local function updateAreas()
	local filled = ns.Layout.CenterBars()
	for _, box in pairs(bars) do
		local on = box:IsShown()
		box.labels[1]:SetShown(on and dragging)
		box.labels[2]:SetShown(on and (dragging or (ns.A.arranging and not filled[box.barName])))
		box.labels[3]:SetShown(on and dragging)
	end
end

function Overlays.ShowAreas(on)
	dragging = on and true or false
	updateAreas()
end

function Overlays.Box(id)
	return plugins[id]
end

function Overlays.BarBox(frameName)
	return bars[frameName]
end

function Overlays.Refresh()
	if not ns.A.arranging or not T.Ready() then
		Overlays.HideAll()
		return
	end
	local levels = {}
	for _, bar in ipairs(T.Bars()) do
		local box = bars[bar.frameName] or makeBarBox(bar)
		bars[bar.frameName] = box
		box.barName = bar.name
		box:SetShown(T.BarShown(bar))
		levels[bar.name] = box:GetFrameLevel()
	end
	updateAreas()
	local shown = {}
	local buttons, locations = T.Buttons(), T.Locations()
	for i = 1, #buttons do
		local id = buttons[i]
		if T.IsOnScreen(id) then
			local button = T.Button(id)
			local box = plugins[id]
			if not box or box:GetParent() ~= button then
				box = makePluginBox(id, button)
				plugins[id] = box
			end
			box:SetFrameLevel(math.max(button:GetFrameLevel(), levels[locations[i]] or 0) + 10)
			box:Show()
			shown[id] = true
		end
	end
	for id, box in pairs(plugins) do
		if not shown[id] then
			box:Hide()
		end
	end
	if selected and selected.kind == "plugin" and not shown[selected.id] then
		Overlays.Select(nil)
	end
	repaintAll()
end

function Overlays.HideAll()
	for _, box in pairs(plugins) do
		box:Hide()
	end
	for _, box in pairs(bars) do
		box:Hide()
	end
	if selected then
		Overlays.Select(nil)
	end
end
