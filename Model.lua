-- The plugin order Titan keeps, as groups. Titan stores one list of plugin ids (TitanPanelSettings.Buttons) with a
-- parallel list of bar names (TitanPanelSettings.Location). On each bar it lays the left plugins out from the left
-- edge and the right plugins from the right edge, each anchored to the one before it in the list. Only the order
-- inside one bar and side matters, so the list is handled as bar -> { left, center, right } and written back whole.
-- No game API in here: the tests load this file on its own.
local _, ns = ...
ns = ns or {}

local Model = {}
ns.Model = Model

local SIDES = { "left", "center", "right" }
Model.SIDES = SIDES

local function newBar()
	return { left = {}, center = {}, right = {} }
end

-- sideOf(id) answers "left", "center" or "right". A missing bar name counts as Titan's top bar. A repeated id keeps
-- its first place, as Titan's own lookups do.
function Model.Build(buttons, locations, sideOf)
	local m = { bars = {}, order = {}, has = {} }
	for i = 1, #buttons do
		local id = buttons[i]
		if id ~= nil and not m.has[id] then
			m.has[id] = true
			local bar = locations[i] or "Bar"
			local b = m.bars[bar]
			if not b then
				b = newBar()
				m.bars[bar] = b
				m.order[#m.order + 1] = bar
			end
			local list = b[sideOf(id) or "left"] or b.left
			list[#list + 1] = id
		end
	end
	return m
end

function Model.Group(m, bar, side)
	local b = m.bars[bar]
	if not b then
		b = newBar()
		m.bars[bar] = b
		m.order[#m.order + 1] = bar
	end
	return b[side]
end

function Model.Find(m, id)
	for _, bar in ipairs(m.order) do
		local b = m.bars[bar]
		for _, side in ipairs(SIDES) do
			local list = b[side]
			for i = 1, #list do
				if list[i] == id then
					return bar, side, i
				end
			end
		end
	end
end

function Model.Remove(m, id)
	local bar, side, i = Model.Find(m, id)
	if bar then
		table.remove(m.bars[bar][side], i)
		m.has[id] = nil
	end
	return bar, side, i
end

-- Puts id before the k-th member of the group that isVisible accepts; a k past the last of them puts it right
-- after that last one. Plugins that are not loaded stay in the list but take no place on screen, so positions count
-- only the visible ones, and a plugin that is not loaded keeps its place next to the ones around it.
function Model.Insert(m, id, bar, side, k, isVisible)
	local list = Model.Group(m, bar, side)
	local seen, lastVisible = 0, 0
	for i = 1, #list do
		if not isVisible or isVisible(list[i]) then
			seen = seen + 1
			if seen == k then
				table.insert(list, i, id)
				m.has[id] = true
				return
			end
			lastVisible = i
		end
	end
	table.insert(list, lastVisible + 1, id)
	m.has[id] = true
end

function Model.Move(m, id, bar, side, k, isVisible)
	Model.Remove(m, id)
	Model.Insert(m, id, bar, side, k, isVisible)
end

-- Members of a group that isVisible accepts, in list order, leaving out exclude.
function Model.Visible(m, bar, side, isVisible, exclude)
	local out = {}
	local b = m.bars[bar]
	if b then
		for _, id in ipairs(b[side]) do
			if id ~= exclude and (not isVisible or isVisible(id)) then
				out[#out + 1] = id
			end
		end
	end
	return out
end

-- Centre plugins are written after the left ones, so no left plugin is anchored to a centre one.
function Model.Write(m, buttons, locations)
	for i = #buttons, 1, -1 do
		buttons[i] = nil
	end
	for i = #locations, 1, -1 do
		locations[i] = nil
	end
	for _, bar in ipairs(m.order) do
		local b = m.bars[bar]
		for _, side in ipairs(SIDES) do
			for _, id in ipairs(b[side]) do
				buttons[#buttons + 1] = id
				locations[#locations + 1] = bar
			end
		end
	end
end

-- Where one step left (dir -1) or right (dir 1) on screen takes id: side and k as Insert takes them, or nil at the
-- end of the bar. Titan lays a right group out right to left, so its list runs the other way on screen. Past the
-- end of its group a plugin moves into the next group along: left, center, right. rightOnly keeps it on the right.
function Model.StepTarget(m, id, dir, isVisible, rightOnly)
	local bar, side = Model.Find(m, id)
	if not bar then
		return
	end
	local mine = Model.Visible(m, bar, side, isVisible)
	local pos
	for i, pid in ipairs(mine) do
		if pid == id then
			pos = i
		end
	end
	if not pos then
		return
	end
	local listDir = side == "right" and -dir or dir
	local to = pos + listDir
	if to >= 1 and to <= #mine then
		return bar, side, to
	end
	local function into(nextSide, atListEnd)
		if rightOnly and nextSide ~= "right" then
			return
		end
		local others = Model.Visible(m, bar, nextSide, isVisible, id)
		return bar, nextSide, atListEnd and #others + 1 or 1
	end
	if dir > 0 then
		if side == "left" then
			return into("center", false)
		elseif side == "center" then
			return into("right", true)
		end
	else
		if side == "right" then
			return into("center", true)
		elseif side == "center" then
			return into("left", true)
		end
	end
end

return Model
