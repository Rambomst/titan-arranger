-- The panel shown while arranging. An Edit Mode style dialog (Blizzard's translucent dialog border, Edit Mode's
-- slider, Blizzard's slim scroll bar) whose title is a Titan bar strip in the player's skin, in Titan's font. It
-- holds the plugins that are on no bar, grouped as Titan's own Plugins menu groups them (drag one onto a bar to show
-- it, drag a plugin from a bar onto the list to hide it), the spacing of the three areas, the Edit Mode choice,
-- Revert and Done. It is as tall as its list and grows or shrinks with it from a fixed top edge, up to 85% of the
-- screen and never down over the bottom bars; past that the list scrolls. Its corner sets the width, or a shorter
-- height. It moves; with Edit Mode open it sits to the left of Edit Mode's window, which is centred at the top of
-- the screen.
local _, ns = ...

local T, L = ns.Titan, ns.L

local Panel = {}
ns.Panel = Panel

local ROW = 22
local WIDTH = 320
local PAD = 16
-- From the top: the title strip, the hint and the list heading, each anchored under the one before, so a hint that
-- wraps to more lines pushes the list down (TOP is the usual total, for sizing). From the bottom: Done and Revert,
-- the Edit Mode choice, the three spacing rows and their heading.
local TOP = 118
local FOOT = 196
-- The list's area is never shorter than this many rows, so an empty list still reads as a place to drop plugins.
local MIN_ROWS = 2
local MIN_WIDTH, MAX_WIDTH = 280, 720
-- Kept free between the panel's bottom edge and the bottom bars, or the bottom of the screen.
local GAP = 8
Panel.ROW, Panel.TOP, Panel.FOOT, Panel.MIN_ROWS, Panel.GAP = ROW, TOP, FOOT, MIN_ROWS, GAP

local frame, rows = nil, {}

local function screenRect(f)
	local l, b, w, h = f:GetRect()
	if not l then
		return
	end
	local s = f:GetEffectiveScale()
	return l * s, b * s, (l + w) * s, (b + h) * s
end

local function settings()
	return TitanArrangerDB.settings
end

-- Kept by its top left corner, so a list that grows or shrinks moves only the bottom edge.
local function savePlace(f)
	local l, t = f:GetLeft(), f:GetTop()
	if not l then
		return
	end
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
	settings().panel = { "TOPLEFT", "BOTTOMLEFT", l, t }
end

local function place(f, reason)
	f:ClearAllPoints()
	local em = EditModeManagerFrame
	if reason == "editmode" and em and em:IsShown() then
		f:SetPoint("TOPRIGHT", em, "TOPLEFT", -8, 0)
		return
	end
	local p = settings().panel
	if type(p) == "table" and p[1] then
		f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
		-- Older saves hold whichever point the client picked when the drag stopped.
		if p[1] ~= "TOPLEFT" then
			savePlace(f)
		end
	else
		f:SetPoint("TOP", UIParent, "TOP", 0, -100)
	end
end

-- Titan's plugin groups, in its order, with Titan's localized names when it has them.
local function categories()
	local order = TITAN_PANEL_BUTTONS_PLUGIN_CATEGORY
		or { "Built-ins", "General", "Combat", "Information", "Interface", "Profession" }
	local names = {}
	local AceLocale = LibStub and LibStub("AceLocale-3.0", true)
	local loc = AceLocale and AceLocale:GetLocale("Titan", true)
	local localized = type(loc) == "table" and rawget(loc, "TITAN_PANEL_MENU_CATEGORIES")
	for i, cat in ipairs(order) do
		names[cat] = type(localized) == "table" and localized[i] or cat
	end
	return order, names
end

-- Plugins on no bar: registered, not in Titan's list, and not one of Titan's own bar plugins. A plugin pinned to one
-- bar (the auto-hide pins) is only offered while that bar is shown.
function Panel.TrayIds()
	local ids = {}
	for _, id in ipairs(T.PluginIds()) do
		local force = T.ForceBar(id)
		local bar = force and T.Bar(force)
		if not T.IsListed(id) and not T.IsBarPlugin(id) and (not force or (bar and T.BarShown(bar))) then
			ids[#ids + 1] = id
		end
	end
	return ids
end

-- The list as rows: a heading per Titan group that has plugins, then its plugins by name.
function Panel.Items()
	local order, names = categories()
	local byCat, extra = {}, {}
	for _, id in ipairs(Panel.TrayIds()) do
		local reg = T.Registry(id)
		local cat = reg and reg.category or "General"
		if not names[cat] and not byCat[cat] then
			extra[#extra + 1] = cat
		end
		byCat[cat] = byCat[cat] or {}
		table.insert(byCat[cat], id)
	end
	local items = {}
	local function add(cat)
		if byCat[cat] then
			items[#items + 1] = { kind = "header", text = names[cat] or cat }
			for _, id in ipairs(byCat[cat]) do
				items[#items + 1] = { kind = "plugin", id = id }
			end
		end
	end
	for _, cat in ipairs(order) do
		add(cat)
	end
	for _, cat in ipairs(extra) do
		add(cat)
	end
	return items
end

local function makeRow(parent)
	local r = CreateFrame("Button", nil, parent)
	r:SetHeight(ROW)
	r:RegisterForDrag("LeftButton")
	r.hl = r:CreateTexture(nil, "HIGHLIGHT")
	r.hl:SetAllPoints()
	r.hl:SetColorTexture(1, 1, 1, 0.07)
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(18, 18)
	r.icon:SetPoint("LEFT", 6, 0)
	r.text = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	r.text:SetJustifyH("LEFT")
	r.rule = r:CreateTexture(nil, "ARTWORK")
	r.rule:SetHeight(1)
	r.rule:SetColorTexture(1, 0.82, 0, 0.25)
	r:SetScript("OnDragStart", function(self)
		if self.id then
			ns.Drag.Start(self.id, "tray", nil)
		end
	end)
	r:SetScript("OnDragStop", function()
		ns.Drag.Stop()
	end)
	return r
end

local function build()
	local f = CreateFrame("Frame", "TitanArrangerPanel", UIParent)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetSize(WIDTH, 460)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetResizable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		savePlace(self)
		-- The room below depends on where the top now is.
		Panel.Refresh()
	end)
	ns.Theme.Dialog(f)

	-- The title strip: a Titan bar in the player's skin.
	f.strip = CreateFrame("Frame", nil, f)
	f.strip:SetPoint("TOPLEFT", 8, -8)
	f.strip:SetPoint("TOPRIGHT", -8, -8)
	f.strip:SetHeight(ns.Theme.STRIP)
	f.title = f.strip:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	f.title:SetPoint("LEFT", 10, 0)
	f.title:SetText(L.TITLE)
	f.title:SetTextColor(1, 0.82, 0)
	f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.close:SetPoint("TOPRIGHT", 0, 0)
	f.close:SetScript("OnClick", function()
		ns.A:Exit()
	end)

	f.hint = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	-- Both anchors on the top edge: a RIGHT anchor would tie the hint's middle to the panel's middle.
	f.hint:SetPoint("TOPLEFT", PAD, -42)
	f.hint:SetPoint("TOPRIGHT", -PAD, -42)
	f.hint:SetJustifyH("LEFT")
	f.hint:SetText(L.HINT)

	f.head = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	f.head:SetPoint("TOPLEFT", f.hint, "BOTTOMLEFT", 0, -10)
	f.head:SetText(L.TRAY)

	local ok, scroll = pcall(CreateFrame, "ScrollFrame", "TitanArrangerPanelScroll", f, "ScrollFrameTemplate")
	if not ok or not scroll then
		scroll = CreateFrame("ScrollFrame", "TitanArrangerPanelScroll", f, "UIPanelScrollFrameTemplate")
	end
	if scroll.ScrollBar and scroll.ScrollBar.SetHideIfUnscrollable then
		scroll.ScrollBar:SetHideIfUnscrollable(true)
	end
	scroll:SetPoint("TOPLEFT", f.head, "BOTTOMLEFT", -4, -6)
	scroll:SetPoint("BOTTOMRIGHT", -PAD - 14, FOOT)
	f.list = CreateFrame("Frame", nil, scroll)
	f.list:SetSize(WIDTH - 2 * PAD, ROW)
	scroll:SetScrollChild(f.list)
	-- Anchored as Blizzard's own scroll children are (ChatConfigFrame, ArchaeologyUI).
	f.list:SetPoint("TOPLEFT")
	f.scroll = scroll

	-- Shown while a plugin from a bar is dragged over the panel: dropping it here hides it.
	f.drop = CreateFrame("Frame", nil, f)
	f.drop:SetPoint("TOPLEFT", scroll, "TOPLEFT", -2, 2)
	f.drop:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 2, -2)
	f.drop:SetFrameLevel(scroll:GetFrameLevel() + 20)
	local glow = f.drop:CreateTexture(nil, "OVERLAY")
	glow:SetAllPoints()
	glow:SetColorTexture(1, 0.82, 0, 0.12)
	ns.Theme.Border(f.drop, 1, 0.82, 0, 0.9)
	f.drop:Hide()

	f.empty = f:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	f.empty:SetPoint("TOPLEFT", scroll, "TOPLEFT", 6, -4)
	f.empty:SetText(L.TRAY_EMPTY)

	f.spacing = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	f.spacing:SetPoint("BOTTOMLEFT", PAD, FOOT - 26)
	f.spacing:SetText(L.SPACING)
	local Layout = ns.Layout
	-- One range for all three, so equal gaps sit at the same place on each slider. Titan's own options page offers
	-- 5 to 80 for Button Spacing and 0 to 20 for Icon Spacing; Titan lays out any value.
	local Slider = ns.Theme.Slider
	f.sliders = {
		Slider(f, L.SPACING_LEFT, 0, 80, function()
			return tonumber(Titan_G.vars.PanelGet("ButtonSpacing")) or 0
		end, function(v)
			-- What Titan's own slider does (TitanConfig.lua, "Config: Button spacing").
			Titan_G.vars.PanelSet("ButtonSpacing", v)
			T.Relayout("ButtonSpacing")
		end),
		Slider(f, L.SPACING_CENTER, 0, 80, function()
			return Layout.CenterSpacing()
		end, function(v)
			Layout.SetCenterSpacing(v)
		end),
		Slider(f, L.SPACING_RIGHT, 0, 80, function()
			return tonumber(Titan_G.vars.PanelGet("IconSpacing")) or 0
		end, function(v)
			Titan_G.vars.PanelSet("IconSpacing", v)
			T.Relayout("IconSpacing")
		end),
	}
	-- The centre slider says why it is grey while no bar has a centre plugin.
	local centre = f.sliders[2]
	centre.row:EnableMouse(true)
	centre.row:SetScript("OnEnter", function(self)
		if not centre.enabled then
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(L.SPACING_CENTER)
			GameTooltip:AddLine(L.CENTER_EMPTY, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	centre.row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	for i, s in ipairs(f.sliders) do
		local y = FOOT - 26 - i * 28
		s.row:SetPoint("BOTTOMLEFT", PAD, y)
		s.row:SetPoint("BOTTOMRIGHT", -PAD, y)
	end

	local check = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	check:SetSize(26, 26)
	check:SetPoint("BOTTOMLEFT", PAD - 4, 44)
	check.label = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	check.label:SetPoint("LEFT", check, "RIGHT", 4, 0)
	check.label:SetText(L.WITH_EDIT_MODE)
	check:SetScript("OnClick", function(self)
		settings().withEditMode = self:GetChecked() and true or false
	end)
	f.check = check

	f.revert = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	-- Revert and Done split the bottom row, so they fit at any width.
	f.revert:SetHeight(24)
	f.revert:SetPoint("BOTTOMLEFT", PAD, 14)
	f.revert:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 14)
	f.revert:SetText(L.REVERT)
	f.revert:SetScript("OnClick", function()
		ns.A:Revert()
	end)
	f.revert:SetMotionScriptsWhileDisabled(true)
	f.revert:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(L.REVERT)
		GameTooltip:AddLine(L.REVERT_TIP, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	f.revert:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	f.done = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.done:SetHeight(24)
	f.done:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 14)
	f.done:SetPoint("BOTTOMRIGHT", -PAD - 6, 14)
	f.done:SetText(L.DONE)
	f.done:SetScript("OnClick", function()
		ns.A:Exit()
	end)

	-- Drag the corner to resize. The width is kept; a height shorter than the list is kept too (the list scrolls),
	-- and one as tall or taller goes back to fitting the list.
	local grip = CreateFrame("Button", nil, f)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -6, 6)
	grip:SetFrameLevel(f:GetFrameLevel() + 10)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function()
		f.sizing = true
		f:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", function()
		f:StopMovingOrSizing()
		f.sizing = nil
		local h = math.floor(f:GetHeight() + 0.5)
		local cap = h < Panel.Measure(f, #Panel.Items()) - 1 and h or nil
		settings().panelSize = { math.floor(f:GetWidth() + 0.5), cap }
		savePlace(f)
		Panel.Refresh()
	end)
	f.grip = grip

	f:Hide()
	return f
end

local function applyLook(f)
	local Th = ns.Theme
	Th.Strip(f, f.strip)
	Th.Font(f.title, 3)
	Th.Font(f.hint)
	Th.Font(f.head, 2)
	Th.Font(f.empty, 1)
	Th.Font(f.spacing, 2)
	Th.Font(f.check.label, 1)
	for _, s in ipairs(f.sliders) do
		Th.Font(s.label, 1)
	end
end

-- The height that shows a list of count rows whole, and the least height, for MIN_ROWS rows. The list starts below a
-- hint that may wrap, so both are measured from where the list really starts.
function Panel.Measure(f, count)
	local top = f:GetTop() and f.scroll:GetTop() and (f:GetTop() - f.scroll:GetTop()) or TOP
	return top + math.max(count, MIN_ROWS) * ROW + FOOT + 4, top + MIN_ROWS * ROW + FOOT + 4
end

local function applyWidth(f)
	local saved = settings().panelSize
	local w = type(saved) == "table" and tonumber(saved[1]) or WIDTH
	f:SetWidth(math.min(math.max(w, MIN_WIDTH), MAX_WIDTH))
end

-- The most the panel grows to from where its top is: 85% of the screen, and never down over the bottom bars. Those
-- run the width of the screen, so moving the panel aside cannot uncover them, and a drop on the panel hides a plugin
-- instead of putting it on the bar under it.
local function room(f)
	local most = UIParent:GetHeight() * 0.85
	local top = f:GetTop()
	if top then
		local floor = (T.BottomBarsTop() or 0) / f:GetEffectiveScale()
		most = math.min(most, top - floor - GAP)
	end
	return most
end

-- As tall as the list, unless the player dragged the panel shorter or there is no room; past that the list scrolls.
local function fitHeight(f, count)
	local want, least = Panel.Measure(f, count)
	local most = math.max(room(f), least)
	f:SetResizeBounds(MIN_WIDTH, least, MAX_WIDTH, most)
	local saved = settings().panelSize
	local cap = type(saved) == "table" and tonumber(saved[2]) or most
	f:SetHeight(math.max(math.min(want, cap, most), least))
end

function Panel.Refresh()
	if not frame or not frame:IsShown() then
		return
	end
	local items = Panel.Items()
	for i, item in ipairs(items) do
		local r = rows[i] or makeRow(frame.list)
		rows[i] = r
		r.text:ClearAllPoints()
		if item.kind == "header" then
			r.id = nil
			r.icon:Hide()
			ns.Theme.Font(r.text, 1)
			r.text:SetPoint("LEFT", 2, -2)
			r.text:SetText(item.text)
			r.text:SetTextColor(1, 0.82, 0)
			r.rule:ClearAllPoints()
			r.rule:SetPoint("LEFT", r.text, "RIGHT", 6, 0)
			r.rule:SetPoint("RIGHT", -2, -2)
			r.rule:Show()
			r.hl:Hide()
			r:EnableMouse(false)
		else
			r.id = item.id
			local icon = T.Icon(item.id)
			r.icon:SetTexture(icon)
			r.icon:SetShown(icon ~= nil and icon ~= "")
			ns.Theme.Font(r.text, 1)
			r.text:SetPoint("LEFT", 30, 0)
			r.text:SetPoint("RIGHT", -4, 0)
			r.text:SetText(T.Name(item.id))
			r.text:SetTextColor(1, 1, 1)
			r.rule:Hide()
			r.hl:Show()
			r:EnableMouse(true)
		end
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
		r:SetPoint("TOPRIGHT", frame.list, "TOPRIGHT", 0, -(i - 1) * ROW)
		r:Show()
	end
	for i = #items + 1, #rows do
		rows[i]:Hide()
		rows[i].id = nil
	end
	-- Left alone while the corner is being dragged.
	if not frame.sizing then
		fitHeight(frame, #items)
	end
	frame.list:SetWidth(math.max(frame.scroll:GetWidth(), 100))
	frame.list:SetHeight(math.max(ROW, #items * ROW))
	frame.empty:SetShown(#items == 0)
	frame.check:SetChecked(settings().withEditMode and true or false)
	frame.revert:SetEnabled(ns.A.dirty and true or false)
	for _, s in ipairs(frame.sliders) do
		s.Set(s.get())
	end
	frame.sliders[2].Enable(ns.Layout.HasCenter())
end

function Panel.Show(reason)
	frame = frame or build()
	applyLook(frame)
	-- Width and place first: Refresh measures the height from where the list starts.
	applyWidth(frame)
	place(frame, reason)
	frame:Show()
	Panel.Refresh()
end

function Panel.Hide()
	if frame then
		frame:Hide()
	end
end

function Panel.Frame()
	return frame
end

function Panel.Rows()
	return rows
end

-- Screen pixels, as the drag uses.
function Panel.IsOver(x, y)
	if not frame or not frame:IsShown() then
		return false
	end
	local l, b, r, t = screenRect(frame)
	return l ~= nil and x >= l and x <= r and y >= b and y <= t
end

function Panel.Highlight(on)
	if frame then
		frame.drop:SetShown(on and true or false)
	end
end
