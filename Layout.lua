-- What Arranger adds to Titan's layout, applied after each Titan layout: the centre area, and the margins of single
-- plugins. Titan only knows left and right: centre plugins are left plugins to Titan, kept after the bar's other
-- left plugins (Model.Write) so no left plugin is anchored to them, and Arranger lays them out itself around the
-- bar's middle. A left or right group is laid out again only when one of its plugins has a margin (or the bar has a
-- centre area and Titan's "Center Text"); otherwise Titan's own anchors stand.
local _, ns = ...

local T, Model = ns.Titan, ns.Model

local Layout = {}
ns.Layout = Layout

local pending = false

function Layout.Pending()
	return pending
end

-- The centre gap, in Titan's spacing units: Arranger's own setting, or Titan's Button Spacing until one is set.
function Layout.CenterSpacing()
	local own = ns.A:Profile().centerSpacing
	return tonumber(own) or tonumber(Titan_G.vars.PanelGet("ButtonSpacing")) or 20
end

function Layout.SetCenterSpacing(value)
	ns.A:Profile().centerSpacing = value
	Layout.Apply()
end

-- A spacing setting as an anchor offset, the way Titan's ShowPlugins turns Button Spacing into one.
local function offset(spacing)
	local scale = tonumber(Titan_G.vars.PanelGet("Scale")) or 1
	return (tonumber(spacing) or 0) * scale * scale
end
Layout.Offset = offset

-- The plugins drawn on each bar, by side, in Titan's list order.
local function groupsByBar()
	local center = ns.A:CenterFlags()
	local buttons, locations = T.Buttons(), T.Locations()
	local out = {}
	for i = 1, #buttons do
		local id, bar = buttons[i], locations[i]
		if bar and T.IsOnScreen(id) then
			local g = out[bar]
			if not g then
				g = { left = {}, center = {}, right = {} }
				out[bar] = g
			end
			local list = g[T.SideOf(id, center)]
			list[#list + 1] = id
		end
	end
	return out
end

-- The bars that have a plugin in their centre area, as a set of bar names.
function Layout.CenterBars()
	local out = {}
	if T.Ready() then
		for bar, g in pairs(groupsByBar()) do
			if #g.center > 0 then
				out[bar] = true
			end
		end
	end
	return out
end

-- True when any shown bar has a plugin in its centre area.
function Layout.HasCenter()
	if not T.Ready() then
		return false
	end
	for _, g in pairs(groupsByBar()) do
		if #g.center > 0 then
			return true
		end
	end
	return false
end

local function hasMargins(list)
	local A = ns.A
	for _, id in ipairs(list) do
		if A:Gap(id, "left") ~= 0 or A:Gap(id, "right") ~= 0 then
			return true
		end
	end
	return false
end

-- The space from plugin a to the next one in a chain, b: the side's spacing plus the margins they turn to each other.
-- Negative margins may overlap the two, at most halfway over the narrower one: a whole overlap hid a narrow plugin
-- (a Titan Spacer) and its box under its neighbour. So half of each always shows, the order holds and a chain spans
-- from its first plugin's start to its last plugin's end.
local function link(base, a, aSide, b, bSide)
	local A = ns.A
	local space = base + offset(A:Gap(a, aSide)) + offset(A:Gap(b, bSide))
	return math.max(space, -math.min(T.Button(a):GetWidth(), T.Button(b):GetWidth()) / 2)
end

-- Left to right from a starting point: each plugin after the one before. start(b, total, firstMargin) anchors the
-- first plugin; total includes the outer margins, so a centred chain moves by half of them.
local function chainLeftToRight(list, base, start)
	local A = ns.A
	local links = {}
	local total = offset(A:Gap(list[1], "left")) + offset(A:Gap(list[#list], "right"))
	for i, id in ipairs(list) do
		total = total + T.Button(id):GetWidth()
		if i > 1 then
			links[i] = link(base, list[i - 1], "right", id, "left")
			total = total + links[i]
		end
	end
	for i, id in ipairs(list) do
		local b = T.Button(id)
		b:ClearAllPoints()
		if i == 1 then
			start(b, total, offset(A:Gap(id, "left")))
		else
			b:SetPoint("LEFT", T.Button(list[i - 1]), "RIGHT", links[i], 0)
		end
	end
end

function Layout.Apply()
	local A = ns.A
	if not A.active or not T.Ready() then
		return
	end
	-- Titan's own Justify stays out of combat too (its issue 856).
	if InCombatLockdown() then
		pending = true
		return
	end
	pending = false
	local scale = tonumber(Titan_G.vars.PanelGet("Scale")) or 1
	local all = groupsByBar()
	for _, bar in ipairs(T.Bars()) do
		local g = all[bar.name]
		if g then
			local y = T.PluginYOffset(bar)
			local frame = bar.frame
			-- Left group: Titan's, unless a plugin in it has a margin, or Titan's "Center Text" would centre it over
			-- a centre area.
			local centredByTitan = T.IsCentred(bar)
			if #g.left > 0 and (hasMargins(g.left) or (centredByTitan and #g.center > 0)) then
				chainLeftToRight(g.left, offset(Titan_G.vars.PanelGet("ButtonSpacing")), function(b, total, margin)
					if centredByTitan and #g.center == 0 then
						b:SetPoint("LEFT", frame, "CENTER", -total / 2 + margin, y)
					else
						-- A negative margin stops at the bar's left edge.
						b:SetPoint("LEFT", frame, "LEFT", math.max(T.PluginXOffset(bar) + margin, 0), y)
					end
				end)
			end
			-- Centre group: always Arranger's.
			if #g.center > 0 then
				chainLeftToRight(g.center, offset(Layout.CenterSpacing()), function(b, total, margin)
					b:SetPoint("LEFT", frame, "CENTER", -total / 2 + margin, y)
				end)
			end
			-- Right group: Titan's list runs right to left, the first against the bar's right edge (Titan's 5).
			if #g.right > 0 and hasMargins(g.right) then
				local base = offset(Titan_G.vars.PanelGet("IconSpacing"))
				for i, id in ipairs(g.right) do
					local b = T.Button(id)
					b:ClearAllPoints()
					if i == 1 then
						-- A negative margin stops at the bar's right edge.
						b:SetPoint("RIGHT", frame, "RIGHT", -math.max(5 * scale + offset(A:Gap(id, "right")), 0), y)
					else
						local prev = g.right[i - 1]
						b:SetPoint("RIGHT", T.Button(prev), "LEFT", -link(base, prev, "left", id, "right"), 0)
					end
				end
			end
		end
	end
end

-- Older name, kept for the hooks.
Layout.Center = Layout.Apply

-- Titan appends a plugin it shows at the end of its list, which can put a left plugin after centre ones, where it
-- would hang off them. Returns true when the list had to be put back in order.
function Layout.Normalize()
	local A = ns.A
	local center = A:CenterFlags()
	if next(center) == nil then
		return false
	end
	local buttons, locations = T.Buttons(), T.Locations()
	local seenCenter = {}
	local broken = false
	for i = 1, #buttons do
		local id, bar = buttons[i], locations[i]
		if bar and not Titan_G.plugins.ToRight(id) then
			if center[id] then
				seenCenter[bar] = true
			elseif seenCenter[bar] then
				broken = true
				break
			end
		end
	end
	if not broken then
		return false
	end
	local m = Model.Build(buttons, locations, function(id)
		return T.SideOf(id, center)
	end)
	Model.Write(m, buttons, locations)
	return true
end
