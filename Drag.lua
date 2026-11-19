-- Drag and drop. While a plugin is dragged, a label follows the cursor and a line marks where it will land; Titan's
-- data is only touched on the drop, in one step. Drop points are the edges of the plugins on the bar under the
-- cursor, the nearest one winning (the way Bazooka finds them), plus each empty area's own spot.
local _, ns = ...

local T, Model, L = ns.Titan, ns.Model, ns.L

local Drag = {}
ns.Drag = Drag

local state -- { id, from = "bar" or "tray", button, alpha, target }
local ghost, caret, keys

-- Screen pixels, the space GetCursorPosition answers in.
local function screenRect(frame)
	local l, b, w, h = frame:GetRect()
	if not l then
		return
	end
	local s = frame:GetEffectiveScale()
	return l * s, b * s, (l + w) * s, (b + h) * s
end

local function cursor()
	return GetCursorPosition()
end

-- Plugins drawn on a bar, by side, in Titan's list order, leaving out exclude.
local function members(bar, exclude)
	local groups = { left = {}, center = {}, right = {} }
	local center = ns.A:CenterFlags()
	local buttons, locations = T.Buttons(), T.Locations()
	for i = 1, #buttons do
		local id = buttons[i]
		if id ~= exclude and locations[i] == bar.name and T.IsOnScreen(id) then
			local list = groups[T.SideOf(id, center)]
			list[#list + 1] = T.Button(id)
		end
	end
	return groups
end

-- The drop point on one bar nearest to screen x.
function Drag.SlotOnBar(bar, id, x)
	local groups = members(bar, id)
	local bl, _, br = screenRect(bar.frame)
	if not bl then
		return
	end
	local s = bar.frame:GetEffectiveScale()
	local best
	local function add(side, k, px)
		local d = math.abs(x - px)
		if not best or d < best.d then
			best = { bar = bar, side = side, k = k, x = px, d = d }
		end
	end
	if not T.IsPinnedRight(id) then
		-- Left and centre groups run left to right on screen: a plugin's left edge is the slot before it.
		for _, side in ipairs({ "left", "center" }) do
			local g = groups[side]
			if #g == 0 then
				add(side, 1, side == "left" and bl + (T.PluginXOffset(bar) + 4) * s or (bl + br) / 2)
			end
			for i, b in ipairs(g) do
				local l, _, r = screenRect(b)
				if l then
					add(side, i, l)
					add(side, i + 1, r)
				end
			end
		end
	end
	-- The right group runs right to left: a plugin's right edge is the slot before it in Titan's list.
	local g = groups.right
	if #g == 0 then
		add("right", 1, br - 8 * s)
	end
	for i, b in ipairs(g) do
		local l, _, r = screenRect(b)
		if l then
			add("right", i, r)
			add("right", i + 1, l)
		end
	end
	return best
end

-- Where a drop at screen x, y would put id: the bar under the cursor (with some slack above and below), or nil.
function Drag.FindTarget(id, x, y)
	local force = T.ForceBar(id)
	local best, bestD
	for _, bar in ipairs(T.Bars()) do
		if T.BarShown(bar) and (not force or force == bar.name) then
			local l, b, r, t = screenRect(bar.frame)
			if l then
				local slack = (t - b) * 0.75
				if x >= l - 4 and x <= r + 4 and y >= b - slack and y <= t + slack then
					local d = math.abs(y - (b + t) / 2)
					if not bestD or d < bestD then
						best, bestD = bar, d
					end
				end
			end
		end
	end
	if best then
		return Drag.SlotOnBar(best, id, x)
	end
end

local function sideOfFn()
	local center = ns.A:CenterFlags()
	return function(id)
		return T.SideOf(id, center)
	end
end

-- Puts id at a target from FindTarget: one rewrite of Titan's lists, the plugin's side, then Titan's layout.
function Drag.Drop(id, target)
	local buttons, locations = T.Buttons(), T.Locations()
	local m = Model.Build(buttons, locations, sideOfFn())
	Model.Move(m, id, target.bar.name, target.side, target.k, function(pid)
		return pid ~= id and T.IsOnScreen(pid)
	end)
	Model.Write(m, buttons, locations)
	ns.A:SetSide(id, target.side)
	T.Relayout("drop " .. tostring(id))
	ns.A:Changed()
end

-- Takes a plugin off its bar, as Titan's Hide does, without Titan's RemovePlugin (which drops the last plugin when
-- the one asked for is on no bar).
function Drag.HidePlugin(id)
	local buttons, locations = T.Buttons(), T.Locations()
	local m = Model.Build(buttons, locations, sideOfFn())
	Model.Remove(m, id)
	Model.Write(m, buttons, locations)
	ns.A:CenterFlags()[id] = nil
	local b = T.Button(id)
	if b then
		b:Hide()
	end
	T.Relayout("hide " .. tostring(id))
	ns.A:Changed()
end

local function makeGhost()
	local f = ns.Theme.TooltipFrame(UIParent)
	f:SetFrameStrata("TOOLTIP")
	f:SetSize(120, 26)
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetSize(16, 16)
	f.icon:SetPoint("LEFT", 8, 0)
	f.text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	f.text:SetPoint("LEFT", f.icon, "RIGHT", 4, 0)
	f:Hide()
	return f
end

local function makeCaret()
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetFrameStrata("TOOLTIP")
	f:SetSize(3, 30)
	local line = f:CreateTexture(nil, "OVERLAY")
	line:SetAllPoints()
	line:SetColorTexture(1, 0.82, 0, 1)
	f:Hide()
	return f
end

local function placeGhost(x, y)
	local s = UIParent:GetEffectiveScale()
	ghost:ClearAllPoints()
	ghost:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s + 14, y / s - 10)
end

local function placeCaret(target)
	if not target then
		caret:Hide()
		return
	end
	local s = UIParent:GetEffectiveScale()
	local _, b, _, t = screenRect(target.bar.frame)
	if not b then
		caret:Hide()
		return
	end
	caret:ClearAllPoints()
	caret:SetHeight((t - b) / s + 6)
	caret:SetPoint("CENTER", UIParent, "BOTTOMLEFT", target.x / s, ((b + t) / 2) / s)
	caret:Show()
end

local function update()
	if not state then
		return
	end
	local x, y = cursor()
	placeGhost(x, y)
	if ns.Panel.IsOver(x, y) and state.from == "bar" then
		state.target = "tray"
		caret:Hide()
		ns.Panel.Highlight(true)
		return
	end
	ns.Panel.Highlight(false)
	state.target = Drag.FindTarget(state.id, x, y)
	placeCaret(state.target)
end

local function finish()
	if state and state.button and state.alpha then
		state.button:SetAlpha(state.alpha)
	end
	state = nil
	if ghost then
		ghost:Hide()
		ghost:SetScript("OnUpdate", nil)
	end
	if caret then
		caret:Hide()
	end
	if keys then
		keys:EnableKeyboard(false)
	end
	ns.Panel.Highlight(false)
	ns.Overlays.ShowAreas(false)
end

function Drag.IsDragging()
	return state ~= nil
end

function Drag.Start(id, from, button)
	if state or InCombatLockdown() or not ns.A.arranging then
		return
	end
	ghost = ghost or makeGhost()
	caret = caret or makeCaret()
	if not keys then
		keys = CreateFrame("Frame", nil, UIParent)
		keys:SetScript("OnKeyDown", function(self, key)
			local mine = key == "ESCAPE"
			if not InCombatLockdown() then
				self:SetPropagateKeyboardInput(not mine)
			end
			if mine then
				Drag.Cancel()
			end
		end)
	end
	T.CloseMenusAndTips()
	ns.Popup.Close()
	state = { id = id, from = from, button = button }
	if button then
		state.alpha = button:GetAlpha()
		button:SetAlpha(0.35)
	end
	ns.Theme.Font(ghost.text, 1)
	local icon = T.Icon(id)
	ghost.icon:SetTexture(icon)
	ghost.icon:SetShown(icon ~= nil and icon ~= "")
	ghost.text:ClearAllPoints()
	if ghost.icon:IsShown() then
		ghost.text:SetPoint("LEFT", ghost.icon, "RIGHT", 6, 0)
	else
		ghost.text:SetPoint("LEFT", 8, 0)
	end
	ghost.text:SetText(T.Name(id))
	ghost:SetWidth(ghost.text:GetStringWidth() + (ghost.icon:IsShown() and 38 or 18))
	ghost:Show()
	ghost:SetScript("OnUpdate", update)
	keys:EnableKeyboard(true)
	ns.Overlays.ShowAreas(true)
	update()
end

function Drag.Stop()
	if not state then
		return
	end
	update()
	local id, target = state.id, state.target
	finish()
	if target == "tray" then
		Drag.HidePlugin(id)
	elseif target then
		Drag.Drop(id, target)
	end
end

function Drag.Cancel()
	finish()
end
