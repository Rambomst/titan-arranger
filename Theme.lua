-- How Arranger's windows look. The panel and the options popup are Edit Mode style dialogs (they sit beside Edit
-- Mode's own window): Blizzard's translucent dialog border, with a title strip that is a real Titan bar in the
-- skin or colour the player's bars use, and Titan's font. A Titan skin is a bar-height strip, so it is only ever
-- drawn at bar height, never tiled down a window. The label on a dragged plugin is a tooltip, like Titan's.
-- The boxes over plugins keep Edit Mode's blue, to match the boxes Blizzard draws at the same time.
local _, ns = ...

local T = ns.Titan

local Theme = {}
ns.Theme = Theme

Theme.STRIP = 24 -- Titan_G.bars.HEIGHT, the height Titan draws its skins at

-- 1px lines on a frame's edges.
function Theme.Border(frame, r, g, b, a)
	local lines = frame.themeLines
	if not lines then
		lines = {}
		for i = 1, 4 do
			lines[i] = frame:CreateTexture(nil, "BORDER")
		end
		local top, bottom, left, right = lines[1], lines[2], lines[3], lines[4]
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
		frame.themeLines = lines
	end
	for _, line in ipairs(lines) do
		line:SetColorTexture(r, g, b, a)
	end
end

-- Blizzard's translucent dialog border and background, as Edit Mode's window has them.
function Theme.Dialog(frame)
	local ok, border = pcall(CreateFrame, "Frame", nil, frame, "DialogBorderTranslucentTemplate")
	if ok and border then
		border:SetAllPoints()
		border:SetFrameLevel(frame:GetFrameLevel())
		frame.dialogBorder = border
	else
		local bg = frame:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.04, 0.04, 0.05, 0.92)
		Theme.Border(frame, 0.5, 0.5, 0.5, 0.9)
	end
end

-- The look to copy: Titan's global skin or colour when one is set for every bar, otherwise the first shown bar's.
function Theme.Look()
	local vars = TitanBarDataVars
	if type(vars) ~= "table" or type(Titan_G) ~= "table" then
		return
	end
	local global = vars.Global
	if type(global) == "table" and global.texure and global.texure ~= Titan_G.NONE then
		return global, "Top"
	end
	for _, bar in ipairs(T.Bars()) do
		if T.BarShown(bar) then
			local data = TitanBarData[bar.frameName]
			return vars[bar.frameName], (data and data.vert == TITAN_BOTTOM) and "Bottom" or "Top"
		end
	end
end

-- Paints a title strip as Titan paints a bar (Titan_G.bars.SetTexture): the skin file tiled at its own size, or
-- the colour. Records the kind on owner for the tests.
function Theme.Strip(owner, strip)
	local tex = strip.tex or strip:CreateTexture(nil, "BACKGROUND")
	strip.tex = tex
	tex:SetAllPoints()
	tex:SetVertexColor(1, 1, 1, 1)
	local look, edge = Theme.Look()
	owner.themeKind = "none"
	if look and look.texure == Titan_G.SKIN and type(look.skin) == "table" and look.skin.path then
		tex:SetTexture(look.skin.path .. "TitanPanelBackground" .. edge .. "0", "REPEAT", "REPEAT")
		tex:SetHorizTile(true)
		tex:SetVertTile(true)
		tex:SetAlpha(look.skin.alpha or 0.7)
		owner.themeKind = "skin"
	elseif look and look.texure == Titan_G.COLOR and type(look.color) == "table" then
		local c = look.color
		tex:SetColorTexture(c.r or 0, c.g or 0, c.b or 0, c.alpha or 1)
		tex:SetAlpha(1)
		owner.themeKind = "color"
	else
		tex:SetColorTexture(0, 0, 0, 0)
	end
end

-- Titan's font (LibSharedMedia name and size, as Titan sets them on plugin text), delta points bigger.
function Theme.Font(fontString, delta)
	local media = LibStub and LibStub("LibSharedMedia-3.0", true)
	local name = Titan_G.vars.PanelGet("FontName")
	local size = tonumber(Titan_G.vars.PanelGet("FontSize")) or 10
	local path = media and name and media:Fetch("font", name, true)
	if path then
		fontString:SetFont(path, size + (delta or 0), "")
	end
end

-- A labelled slider row on Blizzard's Edit Mode slider (MinimalSliderWithSteppersTemplate), with the client's older
-- slider template as the fallback. get() reads the setting, set(value) writes it; every row with the same range
-- puts the same value at the same place. s.Set(value) moves it without calling set; s.Enable(on) greys it out.
function Theme.Slider(parent, label, minV, maxV, get, set, labelWidth)
	labelWidth = labelWidth or 60
	local s = { get = get }
	s.row = CreateFrame("Frame", nil, parent)
	s.row:SetHeight(26)
	s.label = s.row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	s.label:SetPoint("LEFT", 0, 0)
	s.label:SetWidth(labelWidth)
	s.label:SetJustifyH("LEFT")
	s.label:SetText(label)
	local function changed(value)
		value = math.floor(value + 0.5)
		if s.setting or value == s.get() then
			return
		end
		set(value)
		ns.A:Changed()
	end
	local ok, widget = pcall(CreateFrame, "Frame", nil, s.row, "MinimalSliderWithSteppersTemplate")
	if ok and widget and widget.Init and MinimalSliderWithSteppersMixin then
		widget:Init(minV, minV, maxV, maxV - minV, {
			[MinimalSliderWithSteppersMixin.Label.Right] = function(v)
				return tostring(math.floor(v + 0.5))
			end,
		})
		widget:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
			changed(value)
		end, s)
	else
		widget = CreateFrame("Slider", nil, s.row, "OptionsSliderTemplate")
		widget:SetMinMaxValues(minV, maxV)
		widget:SetValueStep(1)
		widget:SetObeyStepOnDrag(true)
		widget:SetScript("OnValueChanged", function(_, value)
			changed(value)
		end)
	end
	widget:SetPoint("LEFT", s.row, "LEFT", labelWidth + 4, 0)
	widget:SetPoint("RIGHT", s.row, "RIGHT", -30, 0)
	s.widget = widget
	s.min, s.max = minV, maxV
	function s.Set(value)
		s.setting = true
		widget:SetValue(value)
		s.setting = false
	end
	function s.Enable(on)
		s.enabled = on and true or false
		widget:SetEnabled(s.enabled)
		if s.enabled then
			s.label:SetTextColor(1, 1, 1)
		else
			s.label:SetTextColor(0.5, 0.5, 0.5)
		end
	end
	s.enabled = true
	return s
end

-- A frame in the standard tooltip look, falling back to plain textures where the template is missing.
function Theme.TooltipFrame(parent)
	local ok, f = pcall(CreateFrame, "Frame", nil, parent, "TooltipBackdropTemplate")
	if ok and f then
		return f
	end
	f = CreateFrame("Frame", nil, parent)
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.04, 0.04, 0.05, 0.92)
	Theme.Border(f, 0.6, 0.6, 0.6, 0.9)
	return f
end
