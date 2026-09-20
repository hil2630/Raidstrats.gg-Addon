-- Canvas object selection, multi-select, and resize handles (web-canvas style).
local addonName = ...
local AceAddon = LibStub("AceAddon-3.0")
local Addon =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)
if not Addon then return end

local Diar = Addon

local HANDLE_KEYS = { "nw", "n", "ne", "e", "se", "s", "sw", "w" }
local HANDLE_SIZE = 8
local MIN_SIZE_PCT = 0.8
local LINE_PAD = 0.01
local RESIZE_FPS = 24
local LINE_W = 1
local RING = { 0.35, 0.72, 1.0, 0.95 }
local ITEM_RING = { 1.0, 1.0, 1.0, 0.55 }
local HANDLE_RING = { 0.25, 0.58, 1.0, 1 }
local HANDLE_FILL = { 1.0, 1.0, 1.0, 1 }

local function CanEdit()
    return Diar.CanEditPlannerItems and Diar:CanEditPlannerItems()
end

local function IsMultiModifierDown()
    if IsControlKeyDown and IsControlKeyDown() then return true end
    if IsMetaKeyDown and IsMetaKeyDown() then return true end
    return false
end

local function IsAltDuplicateDown()
    if not (IsAltKeyDown and IsAltKeyDown()) then return false end
    if IsControlKeyDown and IsControlKeyDown() then return false end
    if IsMetaKeyDown and IsMetaKeyDown() then return false end
    return true
end

local function CopyPlanItem(item)
    local function copyAny(value, depth)
        if type(value) ~= "table" then return value end
        if depth > 10 then return nil end
        if value.GetObjectType or value.SetParent then return nil end
        local out = {}
        for key, child in pairs(value) do
            if key ~= "widget" and key ~= "currentX" and key ~= "currentY"
                and not (type(key) == "string" and key:sub(1, 2) == "__") then
                out[key] = copyAny(child, depth + 1)
            end
        end
        return out
    end
    return copyAny(item, 0)
end

local function GetScene(pf)
    local data = Diar.plannerData
    if not pf or not data or not data.scenes then return nil, nil end
    local sceneIdx = pf.selectedSceneIndex or 1
    return data.scenes[sceneIdx], sceneIdx
end

local function CurrentPlanKey()
    if Diar.GetPlanSyncKey then
        return tostring(Diar:GetPlanSyncKey() or "")
    end
    local data = Diar.plannerData
    return tostring(data and (data.planId or data.uuid or data.planName) or "")
end

local function SelectionMatchesPlan(pf)
    if not pf then return false end
    local key = CurrentPlanKey()
    if pf.__selectionPlanKey ~= key then
        pf.__selectedItemSet = {}
        pf.__selectionPlanKey = key
        return false
    end
    return true
end

local function SelectedSet(pf)
    pf.__selectedItemSet = pf.__selectedItemSet or {}
    return pf.__selectedItemSet
end

local function SelectedCount(set)
    local n = 0
    for _ in pairs(set or {}) do
        n = n + 1
    end
    return n
end

local function SortedIndices(set)
    local list = {}
    for idx in pairs(set or {}) do
        if type(idx) == "number" then
            list[#list + 1] = idx
        end
    end
    table.sort(list)
    return list
end

local function IsLineLike(item)
    return item and item.kind == "line"
end
local LinePixelEnds

local function DistToSeg(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local len2 = dx * dx + dy * dy
    if len2 < 1e-9 then
        local ex, ey = px - ax, py - ay
        return math.sqrt(ex * ex + ey * ey)
    end
    local t = ((px - ax) * dx + (py - ay) * dy) / len2
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local cx, cy = ax + t * dx, ay + t * dy
    local ex, ey = px - cx, py - cy
    return math.sqrt(ex * ex + ey * ey)
end

local function LineAnchor(item)
    local x1 = tonumber(item and item.x1)
    local y1 = tonumber(item and item.y1)
    local x2 = tonumber(item and item.x2)
    local y2 = tonumber(item and item.y2)
    if not x1 or not y1 or not x2 or not y2 then return nil, nil end
    return math.min(x1, x2) - LINE_PAD, math.min(y1, y2) - LINE_PAD
end

local function ItemAnchor(item)
    if not item then return 0, 0 end
    if item.kind == "line" then
        local ax, ay = LineAnchor(item)
        if ax then return ax, ay end
    end
    return tonumber(item.x) or 0, tonumber(item.y) or 0
end

local function ItemBounds(item)
    if not item then return nil end
    if item.kind == "line" then
        local x1, y1, x2, y2 = tonumber(item.x1), tonumber(item.y1), tonumber(item.x2), tonumber(item.y2)
        if x1 and y1 and x2 and y2 then
            local left = math.min(x1, x2)
            local top = math.min(y1, y2)
            return left, top, math.max(MIN_SIZE_PCT, math.max(x1, x2) - left), math.max(MIN_SIZE_PCT, math.max(y1, y2) - top)
        end
    end
    local x = tonumber(item.x)
    local y = tonumber(item.y)
    if x and y then
        return x, y, math.max(MIN_SIZE_PCT, tonumber(item.w) or 4), math.max(MIN_SIZE_PCT, tonumber(item.h) or 4)
    end
    if type(item.corners) == "table" and #item.corners >= 3 then
        local minX, minY, maxX, maxY
        for i = 1, #item.corners do
            local px = tonumber(item.corners[i] and item.corners[i].x)
            local py = tonumber(item.corners[i] and item.corners[i].y)
            if px and py then
                if not minX or px < minX then minX = px end
                if not minY or py < minY then minY = py end
                if not maxX or px > maxX then maxX = px end
                if not maxY or py > maxY then maxY = py end
            end
        end
        if minX then
            return minX, minY, math.max(MIN_SIZE_PCT, maxX - minX), math.max(MIN_SIZE_PCT, maxY - minY)
        end
    end
    return nil
end

local function UnionBounds(scene, indices)
    local left, top, right, bottom
    for i = 1, #indices do
        local item = scene.items and scene.items[indices[i]]
        local x, y, w, h = ItemBounds(item)
        if x then
            if not left or x < left then left = x end
            if not top or y < top then top = y end
            if not right or (x + w) > right then right = x + w end
            if not bottom or (y + h) > bottom then bottom = y + h end
        end
    end
    if not left then return nil end
    return left, top, math.max(MIN_SIZE_PCT, right - left), math.max(MIN_SIZE_PCT, bottom - top)
end

local function CopyGeom(item)
    local geom = {
        x = tonumber(item.x),
        y = tonumber(item.y),
        w = tonumber(item.w),
        h = tonumber(item.h),
        x1 = tonumber(item.x1),
        y1 = tonumber(item.y1),
        x2 = tonumber(item.x2),
        y2 = tonumber(item.y2),
        fontSize = tonumber(item.fontSize),
        angle = tonumber(item.angle) or 0,
    }
    if type(item.corners) == "table" then
        geom.corners = {}
        for i, p in ipairs(item.corners) do
            geom.corners[i] = { x = tonumber(p and p.x), y = tonumber(p and p.y) }
        end
    end
    if type(item.points) == "table" then
        geom.points = {}
        for i, p in ipairs(item.points) do
            geom.points[i] = { x = tonumber(p and p.x), y = tonumber(p and p.y) }
        end
    end
    return geom
end

local function ScaleAbout(value, origin, scale)
    return origin + (value - origin) * scale
end

local function ApplyScaledGeom(item, geom, ox, oy, sx, sy)
    if geom.x and geom.y then
        item.x = ScaleAbout(geom.x, ox, sx)
        item.y = ScaleAbout(geom.y, oy, sy)
        if geom.w then item.w = math.max(MIN_SIZE_PCT, geom.w * sx) end
        if geom.h then item.h = math.max(MIN_SIZE_PCT, geom.h * sy) end
        item.currentX = item.x / 100
        item.currentY = item.y / 100
    end
    if geom.x1 and geom.y1 and geom.x2 and geom.y2 then
        item.x1 = ScaleAbout(geom.x1, ox, sx)
        item.y1 = ScaleAbout(geom.y1, oy, sy)
        item.x2 = ScaleAbout(geom.x2, ox, sx)
        item.y2 = ScaleAbout(geom.y2, oy, sy)
    end
    if geom.fontSize then
        item.fontSize = math.max(1, geom.fontSize * ((sx + sy) * 0.5))
    end
    if geom.corners then
        item.corners = item.corners or {}
        for i, p in ipairs(geom.corners) do
            item.corners[i] = item.corners[i] or {}
            if p.x and p.y then
                item.corners[i].x = ScaleAbout(p.x, ox, sx)
                item.corners[i].y = ScaleAbout(p.y, oy, sy)
            end
        end
    end
    if geom.points then
        item.points = {}
        local baseX, baseY = geom.x or 0, geom.y or 0
        local newX, newY = item.x or baseX, item.y or baseY
        for i, p in ipairs(geom.points) do
            local wx = ScaleAbout(baseX + (p.x or 0), ox, sx)
            local wy = ScaleAbout(baseY + (p.y or 0), oy, sy)
            item.points[i] = { x = wx - newX, y = wy - newY }
        end
    end
end

local function CursorPercent(pf)
    local canvas = pf and pf.canvas
    if not canvas then return nil end
    local scale = (pf.GetEffectiveScale and pf:GetEffectiveScale()) or 1
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    local left, top = canvas:GetLeft(), canvas:GetTop()
    if not left or not top then return nil end
    local cw, ch = canvas:GetSize()
    if not cw or cw <= 0 or not ch or ch <= 0 then return nil end
    local sx, sy = cx - left, top - cy
    local vc = pf.sceneViewContext
    local wx, wy = sx, sy
    local screenToWorld = Diar.PlannerView and Diar.PlannerView.ScreenToWorld
    if screenToWorld and vc then
        wx, wy = screenToWorld(vc, sx, sy)
    elseif vc then
        wx = (sx - (vc.panX or 0)) / (vc.zoom or 1)
        wy = (sy - (vc.panY or 0)) / (vc.zoom or 1)
    end
    return (wx / cw) * 100, (wy / ch) * 100
end

local function ScaleFromHandle(handle, box, cx, cy, freeResize)
    local left, top, w, h = box.l, box.t, box.w, box.h
    local right, bottom = left + w, top + h
    local ox, oy, sx, sy = left, top, 1, 1
    if handle == "se" then
        ox, oy = left, top
        sx, sy = (cx - left) / w, (cy - top) / h
    elseif handle == "nw" then
        ox, oy = right, bottom
        sx, sy = (right - cx) / w, (bottom - cy) / h
    elseif handle == "ne" then
        ox, oy = left, bottom
        sx, sy = (cx - left) / w, (bottom - cy) / h
    elseif handle == "sw" then
        ox, oy = right, top
        sx, sy = (right - cx) / w, (cy - top) / h
    elseif handle == "e" then
        ox, oy = left, top
        sx, sy = (cx - left) / w, 1
    elseif handle == "w" then
        ox, oy = right, top
        sx, sy = (right - cx) / w, 1
    elseif handle == "s" then
        ox, oy = left, top
        sx, sy = 1, (cy - top) / h
    elseif handle == "n" then
        ox, oy = left, bottom
        sx, sy = 1, (bottom - cy) / h
    end
    local minSx = MIN_SIZE_PCT / math.max(0.001, w)
    local minSy = MIN_SIZE_PCT / math.max(0.001, h)
    if not freeResize then
        local s
        if handle == "e" or handle == "w" then
            s = sx
            oy = top + h * 0.5
        elseif handle == "n" or handle == "s" then
            s = sy
            ox = left + w * 0.5
        else
            s = (math.abs(sx - 1) >= math.abs(sy - 1)) and sx or sy
        end
        local minS = math.max(minSx, minSy)
        if s < minS then s = minS end
        sx, sy = s, s
    else
        if sx < minSx then sx = minSx end
        if sy < minSy then sy = minSy end
    end
    return ox, oy, sx, sy
end

local function CanvasToPercent(pf, sx, sy)
    local canvas = pf and pf.canvas
    if not canvas then return 0, 0 end
    local cw, ch = canvas:GetSize()
    if not cw or cw <= 0 or not ch or ch <= 0 then return 0, 0 end
    local vc = pf.sceneViewContext
    local wx, wy = sx, sy
    local screenToWorld = Diar.PlannerView and Diar.PlannerView.ScreenToWorld
    if screenToWorld and vc then
        wx, wy = screenToWorld(vc, sx, sy)
    elseif vc then
        wx = (sx - (vc.panX or 0)) / (vc.zoom or 1)
        wy = (sy - (vc.panY or 0)) / (vc.zoom or 1)
    end
    return (wx / cw) * 100, (wy / ch) * 100
end

local function WorldToCanvas(pf, xp, yp)
    local canvas = pf.canvas
    local vc = pf.sceneViewContext
    local cw, ch = canvas:GetSize()
    if not cw or cw <= 0 then return 0, 0 end
    local pctToCanvas = Diar.PlannerView and Diar.PlannerView.PctToCanvas
    if pctToCanvas then
        return pctToCanvas(vc, cw, ch, xp / 100, yp / 100)
    end
    if vc then
        return (cw * (xp / 100)) * vc.zoom + (vc.panX or 0), (ch * (yp / 100)) * vc.zoom + (vc.panY or 0)
    end
    return cw * (xp / 100), ch * (yp / 100)
end

local function PaintTexture(parent, r, g, b, a)
    local tex = parent:CreateTexture(nil, "OVERLAY")
    tex:SetColorTexture(r, g, b, a)
    return tex
end

local function CreateEdgeBox(parent, r, g, b, a)
    local box = CreateFrame("Frame", nil, parent)
    box:EnableMouse(false)
    local top = PaintTexture(box, r, g, b, a)
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    top:SetHeight(LINE_W)
    local bottom = PaintTexture(box, r, g, b, a)
    bottom:SetPoint("BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT")
    bottom:SetHeight(LINE_W)
    local left = PaintTexture(box, r, g, b, a)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(LINE_W)
    local right = PaintTexture(box, r, g, b, a)
    right:SetPoint("TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT")
    right:SetWidth(LINE_W)
    return box
end

local function CreateHandle(parent, key)
    local handle = CreateFrame("Frame", nil, parent)
    handle:SetSize(HANDLE_SIZE, HANDLE_SIZE)
    handle:EnableMouse(true)
    handle:SetFrameLevel(20)
    local ring = handle:CreateTexture(nil, "BACKGROUND")
    ring:SetAllPoints()
    ring:SetColorTexture(HANDLE_RING[1], HANDLE_RING[2], HANDLE_RING[3], HANDLE_RING[4])
    local fill = handle:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    fill:SetColorTexture(HANDLE_FILL[1], HANDLE_FILL[2], HANDLE_FILL[3], HANDLE_FILL[4])
    handle.handleKey = key
    handle:SetScript("OnMouseDown", function(h, button)
        if button ~= "LeftButton" then return end
        if h.rotate then
            Diar:BeginPlannerSelectionRotate()
        elseif h.lineEnd and h.itemIndex then
            Diar:BeginPlannerLineEndpointDrag(h.itemIndex, h.lineEnd)
        else
            Diar:BeginPlannerSelectionResize(h.handleKey)
        end
    end)
    return handle
end

local function EnsureOverlay(pf)
    local overlay = pf.selectionOverlay
    if overlay and overlay.__selChromeV2 then return overlay end
    if overlay then
        overlay:Hide()
        pf.selectionOverlay = nil
    end
    overlay = CreateFrame("Frame", nil, pf)
    overlay.__selChromeV2 = true
    overlay:EnableMouse(false)
    if overlay.SetClipsChildren then
        overlay:SetClipsChildren(true)
    end
    overlay:Hide()
    pf.selectionOverlay = overlay

    overlay.box = CreateEdgeBox(overlay, RING[1], RING[2], RING[3], RING[4])
    overlay.itemBoxes = {}
    overlay.handles = {}
    for i = 1, #HANDLE_KEYS do
        local key = HANDLE_KEYS[i]
        overlay.handles[key] = CreateHandle(overlay, key)
    end
    return overlay
end

local function EnsureItemBox(overlay, i)
    local box = overlay.itemBoxes[i]
    if box then return box end
    box = CreateEdgeBox(overlay, ITEM_RING[1], ITEM_RING[2], ITEM_RING[3], ITEM_RING[4])
    overlay.itemBoxes[i] = box
    return box
end

local function ColorSelLine(ln, r, g, b, a, thick)
    if not ln then return end
    if ln.SetThickness then ln:SetThickness(thick or 2) end
    if ln.SetColorTexture then
        ln:SetColorTexture(r, g, b, a)
    elseif ln.SetVertexColor then
        ln:SetVertexColor(r, g, b, a)
    end
end

local function EnsureLineChrome(overlay, i)
    overlay.lineChroms = overlay.lineChroms or {}
    local chrome = overlay.lineChroms[i]
    if chrome then return chrome end
    local line = overlay:CreateLine()
    ColorSelLine(line, RING[1], RING[2], RING[3], 0.9, 2)
    local startH = CreateHandle(overlay, "line-start")
    startH.lineEnd = "start"
    local endH = CreateHandle(overlay, "line-end")
    endH.lineEnd = "end"
    chrome = { line = line, startH = startH, endH = endH }
    overlay.lineChroms[i] = chrome
    return chrome
end

local function HideLineChroms(overlay, fromIndex)
    local list = overlay and overlay.lineChroms
    if not list then return end
    for i = fromIndex or 1, #list do
        local chrome = list[i]
        if chrome.line then chrome.line:Hide() end
        if chrome.startH then chrome.startH:Hide() end
        if chrome.endH then chrome.endH:Hide() end
    end
end

local function PlaceEndpointHandle(handle, canvas, x, y)
    local cw, ch = canvas:GetSize()
    local inset = HANDLE_SIZE * 0.5
    if cw and ch and cw > inset * 2 and ch > inset * 2 then
        x = math.max(inset, math.min(cw - inset, x))
        y = math.max(inset, math.min(ch - inset, y))
    end
    handle:ClearAllPoints()
    handle:SetPoint("CENTER", canvas, "TOPLEFT", x, -y)
    handle:Show()
end

local function PlaceLineChrome(chrome, pf, item, itemIndex)
    local x1, y1, x2, y2 = LinePixelEnds(pf, item)
    if not x1 then
        if chrome.line then chrome.line:Hide() end
        if chrome.startH then chrome.startH:Hide() end
        if chrome.endH then chrome.endH:Hide() end
        return false
    end
    chrome.line:SetStartPoint("TOPLEFT", pf.canvas, x1, -y1)
    chrome.line:SetEndPoint("TOPLEFT", pf.canvas, x2, -y2)
    chrome.line:Show()
    chrome.startH.itemIndex = itemIndex
    chrome.startH.lineEnd = "start"
    chrome.endH.itemIndex = itemIndex
    chrome.endH.lineEnd = "end"
    PlaceEndpointHandle(chrome.startH, pf.canvas, x1, y1)
    PlaceEndpointHandle(chrome.endH, pf.canvas, x2, y2)
    return true
end

local function HideBoxHandles(overlay)
    if overlay.box then overlay.box:Hide() end
    for i = 1, #HANDLE_KEYS do
        local handle = overlay.handles and overlay.handles[HANDLE_KEYS[i]]
        if handle then handle:Hide() end
    end
end

local function EnsureRotateChrome(overlay)
    if not overlay then return end
    if not overlay.rotateHandle then
        overlay.rotateHandle = CreateHandle(overlay, "rotate")
        overlay.rotateHandle.rotate = true
        overlay.rotateHandle:SetSize(10, 10)
    end
    if not overlay.rotateStem and overlay.CreateLine then
        overlay.rotateStem = overlay:CreateLine()
        ColorSelLine(overlay.rotateStem, RING[1], RING[2], RING[3], 0.85, 1)
    end
end

local function HideRotEdges(overlay)
    local edges = overlay and overlay.rotEdges
    if not edges then return end
    for i = 1, 4 do
        if edges[i] then edges[i]:Hide() end
    end
end

local function EnsureRotEdges(overlay)
    EnsureRotateChrome(overlay)
    if overlay.rotEdges then return end
    overlay.rotEdges = {}
    for i = 1, 4 do
        local ln = overlay.CreateLine and overlay:CreateLine()
        ColorSelLine(ln, RING[1], RING[2], RING[3], RING[4], 1)
        overlay.rotEdges[i] = ln
    end
end

local function RotatePx(x, y, cx, cy, deg)
    local rad = math.rad(deg or 0)
    local c, s = math.cos(rad), math.sin(rad)
    local dx, dy = x - cx, y - cy
    return cx + dx * c - dy * s, cy + dx * s + dy * c
end

local function PlaceHandleAt(handle, canvas, hx, hy)
    if not handle then return end
    handle:ClearAllPoints()
    handle:SetPoint("CENTER", canvas, "TOPLEFT", hx, -hy)
    handle:Show()
end

local function PlaceRotatedChrome(overlay, canvas, left, top, pw, ph, angle, hideResize)
    EnsureRotEdges(overlay)
    angle = angle or 0
    pw = math.max(2, pw or 2)
    ph = math.max(2, ph or 2)
    local cx, cy = left + pw * 0.5, top + ph * 0.5
    local raw = {
        { left, top },
        { left + pw, top },
        { left + pw, top + ph },
        { left, top + ph },
    }
    local pts = {}
    for i = 1, 4 do
        local x, y = RotatePx(raw[i][1], raw[i][2], cx, cy, angle)
        pts[i] = { x, y }
    end
    if math.abs(angle) < 0.05 then
        HideRotEdges(overlay)
        if overlay.box then
            overlay.box:ClearAllPoints()
            overlay.box:SetPoint("TOPLEFT", canvas, "TOPLEFT", left, -top)
            overlay.box:SetSize(pw, ph)
            overlay.box:Show()
        end
    else
        if overlay.box then overlay.box:Hide() end
        for i = 1, 4 do
            local a = pts[i]
            local b = pts[(i % 4) + 1]
            local ln = overlay.rotEdges[i]
            if ln then
                ln:SetStartPoint("TOPLEFT", canvas, a[1], -a[2])
                ln:SetEndPoint("TOPLEFT", canvas, b[1], -b[2])
                ln:Show()
            end
        end
    end
    if hideResize then
        HideBoxHandles(overlay)
        if overlay.box then overlay.box:Hide() end
        HideRotEdges(overlay)
    else
        local mids = {
            nw = pts[1],
            ne = pts[2],
            se = pts[3],
            sw = pts[4],
            n = { (pts[1][1] + pts[2][1]) * 0.5, (pts[1][2] + pts[2][2]) * 0.5 },
            e = { (pts[2][1] + pts[3][1]) * 0.5, (pts[2][2] + pts[3][2]) * 0.5 },
            s = { (pts[3][1] + pts[4][1]) * 0.5, (pts[3][2] + pts[4][2]) * 0.5 },
            w = { (pts[4][1] + pts[1][1]) * 0.5, (pts[4][2] + pts[1][2]) * 0.5 },
        }
        for i = 1, #HANDLE_KEYS do
            local key = HANDLE_KEYS[i]
            local p = mids[key]
            PlaceHandleAt(overlay.handles[key], canvas, p[1], p[2])
        end
    end
    local nx = (pts[1][1] + pts[2][1]) * 0.5
    local ny = (pts[1][2] + pts[2][2]) * 0.5
    local dx, dy = nx - cx, ny - cy
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.5 then
        dx, dy, len = 0, -1, 1
    end
    local hx = nx + dx / len * 20
    local hy = ny + dy / len * 20
    if overlay.rotateStem then
        overlay.rotateStem:SetStartPoint("TOPLEFT", canvas, nx, -ny)
        overlay.rotateStem:SetEndPoint("TOPLEFT", canvas, hx, -hy)
        overlay.rotateStem:Show()
    end
    PlaceHandleAt(overlay.rotateHandle, canvas, hx, hy)
end

local function ClampBoxToCanvas(left, top, pw, ph, cw, ch)
    local right = left + pw
    local bottom = top + ph
    if right < 0 or bottom < 0 or left > cw or top > ch then
        return nil
    end
    left = math.max(0, left)
    top = math.max(0, top)
    right = math.min(cw, right)
    bottom = math.min(ch, bottom)
    return left, top, math.max(2, right - left), math.max(2, bottom - top)
end

local function PlaceRectPixels(frame, canvas, left, top, pw, ph)
    local cw, ch = canvas:GetSize()
    if cw and ch and cw > 0 and ch > 0 then
        left, top, pw, ph = ClampBoxToCanvas(left, top, pw or 2, ph or 2, cw, ch)
        if not left then
            frame:Hide()
            return nil
        end
    else
        pw = math.max(2, pw or 2)
        ph = math.max(2, ph or 2)
    end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", canvas, "TOPLEFT", left, -top)
    frame:SetSize(pw, ph)
    frame:Show()
    return left, top, pw, ph
end

local function PlaceRect(frame, pf, x, y, w, h)
    local left, top = WorldToCanvas(pf, x, y)
    local right, bottom = WorldToCanvas(pf, x + w, y + h)
    return PlaceRectPixels(frame, pf.canvas, left, top, right - left, bottom - top)
end

local function WidgetCanvasBox(canvas, widget)
    if not canvas or not widget or not widget.IsShown or not widget:IsShown() then
        return nil
    end
    local cl, ct = canvas:GetLeft(), canvas:GetTop()
    local wl, wt = widget:GetLeft(), widget:GetTop()
    if not cl or not ct or not wl or not wt then return nil end
    return wl - cl, ct - wt, widget:GetWidth(), widget:GetHeight()
end

local function CanvasCursor(pf)
    local canvas = pf and pf.canvas
    if not canvas then return nil end
    local scale = (pf.GetEffectiveScale and pf:GetEffectiveScale()) or 1
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    local left, top = canvas:GetLeft(), canvas:GetTop()
    if not left or not top then return nil end
    return cx - left, top - cy
end

local function LiveDragPixelDelta(pf)
    local group = Diar._plannerGroupDrag
    if group then
        local sx, sy = CanvasCursor(pf)
        if sx then return sx - group.startSx, sy - group.startSy end
        return 0, 0
    end
    local drag = Diar._plannerDrag
    local snap = Diar._plannerSelectionDrag
    if drag and drag.widget and snap and snap.grabXOfs and snap.grabYOfs then
        local _, _, _, xOfs, yOfs = drag.widget:GetPoint()
        if xOfs and yOfs then
            return xOfs - snap.grabXOfs, (-yOfs) - snap.grabYOfs
        end
    end
    return 0, 0
end

local function RotatePctPoint(pf, px, py, ox, oy, deltaDeg)
    local ax, ay = WorldToCanvas(pf, px, py)
    local cx, cy = WorldToCanvas(pf, ox, oy)
    local rad = math.rad(deltaDeg)
    local cos, sin = math.cos(rad), math.sin(rad)
    local dx, dy = ax - cx, ay - cy
    return CanvasToPercent(pf, cx + dx * cos - dy * sin, cy + dx * sin + dy * cos)
end

local function SyncBBoxFromCorners(item)
    if type(item.corners) ~= "table" or #item.corners < 1 then return end
    local minX, minY, maxX, maxY
    for i = 1, #item.corners do
        local px = tonumber(item.corners[i] and item.corners[i].x)
        local py = tonumber(item.corners[i] and item.corners[i].y)
        if px and py then
            if not minX or px < minX then minX = px end
            if not minY or py < minY then minY = py end
            if not maxX or px > maxX then maxX = px end
            if not maxY or py > maxY then maxY = py end
        end
    end
    if not minX then return end
    item.x = minX
    item.y = minY
    item.w = math.max(MIN_SIZE_PCT, maxX - minX)
    item.h = math.max(MIN_SIZE_PCT, maxY - minY)
    item.currentX = minX / 100
    item.currentY = minY / 100
end

local function RestoreGeom(item, geom)
    if not item or not geom then return end
    item.x, item.y, item.w, item.h = geom.x, geom.y, geom.w, geom.h
    item.x1, item.y1, item.x2, item.y2 = geom.x1, geom.y1, geom.x2, geom.y2
    item.fontSize = geom.fontSize
    item.angle = geom.angle or 0
    if geom.x then
        item.currentX = geom.x / 100
        item.currentY = (geom.y or 0) / 100
    end
    if geom.corners then
        item.corners = {}
        for i, p in ipairs(geom.corners) do
            item.corners[i] = { x = p.x, y = p.y }
        end
    end
    if geom.points then
        item.points = {}
        for i, p in ipairs(geom.points) do
            item.points[i] = { x = p.x, y = p.y }
        end
    end
end

local function ApplyRotatedGeom(pf, item, geom, ox, oy, deltaDeg)
    RestoreGeom(item, geom)
    if math.abs(deltaDeg) < 0.001 then return end
    if geom.x1 and geom.y1 and geom.x2 and geom.y2 then
        item.x1, item.y1 = RotatePctPoint(pf, geom.x1, geom.y1, ox, oy, deltaDeg)
        item.x2, item.y2 = RotatePctPoint(pf, geom.x2, geom.y2, ox, oy, deltaDeg)
    end
    if geom.corners then
        item.corners = item.corners or {}
        for i, p in ipairs(geom.corners) do
            if p.x and p.y then
                local nx, ny = RotatePctPoint(pf, p.x, p.y, ox, oy, deltaDeg)
                item.corners[i] = { x = nx, y = ny }
            end
        end
        SyncBBoxFromCorners(item)
    elseif geom.points and geom.x and geom.y then
        item.points = item.points or {}
        for i, p in ipairs(geom.points) do
            if p.x and p.y then
                local nx, ny = RotatePctPoint(pf, geom.x + p.x, geom.y + p.y, ox, oy, deltaDeg)
                item.points[i] = { x = nx, y = ny }
            end
        end
        local minX, minY, maxX, maxY
        for i = 1, #item.points do
            local px = tonumber(item.points[i] and item.points[i].x)
            local py = tonumber(item.points[i] and item.points[i].y)
            if px and py then
                if not minX or px < minX then minX = px end
                if not minY or py < minY then minY = py end
                if not maxX or px > maxX then maxX = px end
                if not maxY or py > maxY then maxY = py end
            end
        end
        if minX then
            for i = 1, #item.points do
                local p = item.points[i]
                if p then
                    p.x = (tonumber(p.x) or minX) - minX
                    p.y = (tonumber(p.y) or minY) - minY
                end
            end
            item.x, item.y = minX, minY
            item.w = math.max(MIN_SIZE_PCT, maxX - minX)
            item.h = math.max(MIN_SIZE_PCT, maxY - minY)
            item.currentX = minX / 100
            item.currentY = minY / 100
        end
    elseif geom.x and geom.y then
        local w = geom.w or 4
        local h = geom.h or 4
        local cx, cy = geom.x + w * 0.5, geom.y + h * 0.5
        local ncx, ncy = RotatePctPoint(pf, cx, cy, ox, oy, deltaDeg)
        item.x = ncx - w * 0.5
        item.y = ncy - h * 0.5
        item.w = w
        item.h = h
        item.currentX = item.x / 100
        item.currentY = item.y / 100
    end
    item.angle = (geom.angle or 0) + deltaDeg
end

function LinePixelEnds(pf, item)
    if not IsLineLike(item) then return nil end
    local x1, y1 = tonumber(item.x1), tonumber(item.y1)
    local x2, y2 = tonumber(item.x2), tonumber(item.y2)
    if not (x1 and y1 and x2 and y2) then return nil end
    local ax, ay = WorldToCanvas(pf, x1, y1)
    local bx, by = WorldToCanvas(pf, x2, y2)
    local dx, dy = LiveDragPixelDelta(pf)
    return ax + dx, ay + dy, bx + dx, by + dy
end

local function LiveItemPixelBox(pf, item)
    if IsLineLike(item) then
        local x1, y1, x2, y2 = LinePixelEnds(pf, item)
        if not x1 then return nil end
        local left, top = math.min(x1, x2), math.min(y1, y2)
        return left, top, math.max(2, math.abs(x2 - x1)), math.max(2, math.abs(y2 - y1))
    end
    local canvas = pf and pf.canvas
    local boxL, boxT, boxW, boxH = WidgetCanvasBox(canvas, item and item.widget)
    if boxL then return boxL, boxT, boxW, boxH end
    local x, y, w, h = ItemBounds(item)
    if not x then return nil end
    local left, top = WorldToCanvas(pf, x, y)
    local right, bottom = WorldToCanvas(pf, x + w, y + h)
    local dx, dy = LiveDragPixelDelta(pf)
    return left + dx, top + dy, right - left, bottom - top
end

local function LiveUnionPixelBox(pf, scene, indices)
    local left, top, right, bottom
    local boxes = {}
    for i = 1, #indices do
        local item = scene.items and scene.items[indices[i]]
        local l, t, w, h = LiveItemPixelBox(pf, item)
        if l then
            boxes[#boxes + 1] = { l, t, w, h }
            if not left or l < left then left = l end
            if not top or t < top then top = t end
            if not right or (l + w) > right then right = l + w end
            if not bottom or (t + h) > bottom then bottom = t + h end
        end
    end
    if not left then return nil end
    return left, top, math.max(2, right - left), math.max(2, bottom - top), boxes
end

local function PlaceHandle(handle, canvas, left, top, pw, ph, key)
    local hx, hy = left, top
    if key == "n" or key == "s" then
        hx = left + pw * 0.5
    elseif key == "ne" or key == "e" or key == "se" then
        hx = left + pw
    end
    if key == "w" or key == "e" then
        hy = top + ph * 0.5
    elseif key == "sw" or key == "s" or key == "se" then
        hy = top + ph
    end
    local cw, ch = canvas:GetSize()
    local inset = HANDLE_SIZE * 0.5
    if cw and ch and cw > inset * 2 and ch > inset * 2 then
        hx = math.max(inset, math.min(cw - inset, hx))
        hy = math.max(inset, math.min(ch - inset, hy))
    end
    handle:ClearAllPoints()
    handle:SetPoint("CENTER", canvas, "TOPLEFT", hx, -hy)
    handle:Show()
end

local function HideOverlay(pf)
    local overlay = pf and pf.selectionOverlay
    if not overlay then return end
    HideLineChroms(overlay, 1)
    HideRotEdges(overlay)
    if overlay.rotateHandle then overlay.rotateHandle:Hide() end
    if overlay.rotateStem then overlay.rotateStem:Hide() end
    overlay:Hide()
end

local function ClearSelXform(pf)
    if not pf then return end
    pf.__selBox = nil
    pf.__selAngle = nil
    pf.__selPivotX = nil
    pf.__selPivotY = nil
    pf.__selKey = nil
end

local function SelectionKey(indices)
    return table.concat(indices, ",")
end

local function ItemSelBox(pf, item)
    if not item or IsLineLike(item) then
        local x, y, w, h = ItemBounds(item)
        return x, y, w, h, 0
    end
    local angle = tonumber(item.angle) or 0
    local x, y, w, h = ItemBounds(item)
    if not x then return nil end
    if type(item.corners) == "table" and #item.corners >= 3 and math.abs(angle) > 0.05 and pf then
        local cx, cy = x + w * 0.5, y + h * 0.5
        local minX, minY, maxX, maxY
        for i = 1, #item.corners do
            local px = tonumber(item.corners[i] and item.corners[i].x)
            local py = tonumber(item.corners[i] and item.corners[i].y)
            if px and py then
                local lx, ly = RotatePctPoint(pf, px, py, cx, cy, -angle)
                if not minX or lx < minX then minX = lx end
                if not minY or ly < minY then minY = ly end
                if not maxX or lx > maxX then maxX = lx end
                if not maxY or ly > maxY then maxY = ly end
            end
        end
        if minX then
            return minX, minY, math.max(MIN_SIZE_PCT, maxX - minX), math.max(MIN_SIZE_PCT, maxY - minY), angle
        end
    end
    return x, y, w, h, angle
end

local function SharedItemAngle(scene, indices)
    local ang
    for i = 1, #indices do
        local item = scene.items and scene.items[indices[i]]
        if item and not IsLineLike(item) then
            local a = tonumber(item.angle) or 0
            if ang == nil then
                ang = a
            elseif math.abs(a - ang) > 0.5 then
                return 0
            end
        end
    end
    return ang or 0
end

local function EnsureSelXform(pf, scene, indices)
    local key = SelectionKey(indices)
    if pf.__selKey == key and pf.__selBox then
        return pf.__selBox, pf.__selAngle or 0, pf.__selPivotX, pf.__selPivotY
    end
    local l, t, w, h, ang
    if #indices == 1 then
        l, t, w, h, ang = ItemSelBox(pf, scene.items[indices[1]])
    else
        ang = SharedItemAngle(scene, indices)
        l, t, w, h = UnionBounds(scene, indices)
    end
    if not l then return nil end
    pf.__selKey = key
    pf.__selBox = { l = l, t = t, w = w, h = h }
    pf.__selAngle = ang or 0
    pf.__selPivotX = l + w * 0.5
    pf.__selPivotY = t + h * 0.5
    return pf.__selBox, pf.__selAngle, pf.__selPivotX, pf.__selPivotY
end

local function NudgeSelXform(pf, dx, dy)
    if not pf or not pf.__selBox then return end
    pf.__selBox.l = pf.__selBox.l + dx
    pf.__selBox.t = pf.__selBox.t + dy
    pf.__selPivotX = (pf.__selPivotX or 0) + dx
    pf.__selPivotY = (pf.__selPivotY or 0) + dy
end

function Diar:NudgePlannerSelXform(dx, dy)
    NudgeSelXform(self.plannerFrame, dx, dy)
end

local function ApplyLayerRotation(layer, rad)
    if layer and layer.SetRotation then
        layer:SetRotation(rad)
    end
end

local function PlaceLabelAroundItem(w, item, rad)
    local label = w.label
    if not label or not label.IsShown or not label:IsShown() then return end
    local ih = w:GetHeight() or 0
    local lh = (label.GetStringHeight and label:GetStringHeight()) or 12
    if lh < 1 then lh = 12 end
    local pf = Diar and Diar.plannerFrame
    local zoom = (pf and pf.__viewportDisplayZoom) or (pf and pf.viewerViewport and pf.viewerViewport.zoom) or 1
    local gap = math.max(1, 2 * zoom)
    local R = (ih * 0.5) + gap + (lh * 0.5)
    local alpha = math.rad(tonumber(item.angle) or 0)
    label:ClearAllPoints()
    label:SetPoint("CENTER", w, "CENTER", -R * math.sin(alpha), -R * math.cos(alpha))
    ApplyLayerRotation(label, rad)
end

function Diar.ApplyPlannerWidgetAngle(w, item)
    if not w or not item then return end
    local rad = -math.rad(tonumber(item.angle) or 0)
    ApplyLayerRotation(w.tex, rad)
    if w.text then
        local ww = w:GetWidth()
        if ww and ww > 0 and w.text.GetWidth and w.text.SetWidth then
            local tw = w.text:GetWidth()
            if tw and tw > ww + 2 then
                w.text:SetWidth(ww)
            end
        end
        ApplyLayerRotation(w.text, rad)
    end
    PlaceLabelAroundItem(w, item, rad)
    ApplyLayerRotation(w.spotPreviewText, rad)
    ApplyLayerRotation(w.textBgTex, rad)
end

function Diar:ClearPlannerSelection(silent)
    local pf = self.plannerFrame
    if not pf then return end
    pf.__selectedItemSet = {}
    ClearSelXform(pf)
    if not silent then
        self:SyncPlannerSelectionOverlay()
    else
        HideOverlay(pf)
    end
end

function Diar:DeletePlannerSelection()
    local pf = self.plannerFrame
    if not pf or not CanEdit() then return false end
    local indices = SortedIndices(pf.__selectedItemSet)
    if #indices == 0 then return false end
    for i = #indices, 1, -1 do
        self:DeletePlannerSceneItem(indices[i], { skipRefresh = true, skipPersist = true })
    end
    self:ClearPlannerSelection(true)
    if self.PersistCurrentPlanToSaved then
        self:PersistCurrentPlanToSaved()
    end
    if self.StopPlannerAnimation then
        self:StopPlannerAnimation()
    end
    if self.RefreshPlannerScene then
        self:RefreshPlannerScene()
    end
    return true
end

function Diar:IsPlannerItemSelected(itemIndex)
    local pf = self.plannerFrame
    return pf and pf.__selectedItemSet and pf.__selectedItemSet[itemIndex] == true
end

function Diar:IsPlannerMultiDragging()
    local snap = self._plannerSelectionDrag
    return snap and snap.indices and #snap.indices > 1
end

function Diar:NotifyPlannerItemIndexRemoved(itemIndex)
    local pf = self.plannerFrame
    if not pf or not pf.__selectedItemSet then return end
    local nextSet = {}
    for idx in pairs(pf.__selectedItemSet) do
        if idx < itemIndex then
            nextSet[idx] = true
        elseif idx > itemIndex then
            nextSet[idx - 1] = true
        end
    end
    pf.__selectedItemSet = nextSet
    ClearSelXform(pf)
end

function Diar:DuplicatePlannerSelection(grabIndex)
    local pf = self.plannerFrame
    local scene, sceneIdx = GetScene(pf)
    if not scene or not scene.items then return nil end
    local indices = SortedIndices(pf.__selectedItemSet)
    if #indices == 0 and grabIndex then
        indices = { grabIndex }
    end
    if #indices == 0 then return nil end

    local newSet = {}
    local newGrab
    local pui = self.PlannerUI
    for i = 1, #indices do
        local source = scene.items[indices[i]]
        local copy = source and CopyPlanItem(source)
        if copy then
            if self.GeneratePlannerItemId then
                copy.id = self:GeneratePlannerItemId()
            else
                copy.id = "obj-copy-" .. tostring(time() or 0) .. "-" .. tostring(i)
            end
            if (source.slotIndex or source.embedIndex) and pui and pui.GetNextAvailableSlotIndex then
                local slot = pui.GetNextAvailableSlotIndex(scene)
                copy.slotIndex = slot
                copy.embedIndex = slot
            else
                copy.slotIndex = nil
                copy.embedIndex = nil
            end
            scene.items[#scene.items + 1] = copy
            local newIdx = #scene.items
            newSet[newIdx] = true
            if grabIndex and indices[i] == grabIndex then
                newGrab = newIdx
            end
        end
    end
    if not next(newSet) then return nil end
    pf.__selectedItemSet = newSet
    pf.__selectedSceneIndex = sceneIdx
    if self.RefreshPlannerScene then
        self:RefreshPlannerScene()
    end
    return newGrab or SortedIndices(newSet)[1]
end

function Diar:HandlePlannerItemSelectClick(widget)
    local pf = self.plannerFrame
    if pf and pf.EnableKeyboard then
        pf:EnableKeyboard(true)
    end
    if not pf or not widget or not widget.itemIndex or not CanEdit() then return end
    if self.IsPlannerCompactMode and self:IsPlannerCompactMode() then return end
    local scene, sceneIdx = GetScene(pf)
    if not scene then return end
    SelectionMatchesPlan(pf)
    if pf.__selectedSceneIndex and pf.__selectedSceneIndex ~= sceneIdx then
        pf.__selectedItemSet = {}
    end
    pf.__selectedSceneIndex = sceneIdx
    pf.__selectionPlanKey = CurrentPlanKey()
    local set = SelectedSet(pf)
    local idx = widget.itemIndex
    if IsMultiModifierDown() then
        if set[idx] then
            set[idx] = nil
        else
            set[idx] = true
        end
    elseif not set[idx] then
        pf.__selectedItemSet = { [idx] = true }
    end
    self:SyncPlannerSelectionOverlay()
end

local function CursorHitsLineItem(pf, item)
    local x1, y1, x2, y2 = LinePixelEnds(pf, item)
    if not x1 then return false end
    local sx, sy = CanvasCursor(pf)
    if not sx then return false end
    return DistToSeg(sx, sy, x1, y1, x2, y2) <= 10
end

function Diar:CursorHitsPlannerLine(item)
    return CursorHitsLineItem(self.plannerFrame, item)
end

local function PointInCanvasPoly(pts, sx, sy)
    local n = pts and #pts or 0
    if n < 3 or not sx then return false end
    local inside = false
    local j = n
    for i = 1, n do
        local axi, ayi = pts[i][1], pts[i][2]
        local axj, ayj = pts[j][1], pts[j][2]
        if ((ayi > sy) ~= (ayj > sy)) and (sx < (axj - axi) * (sy - ayi) / (ayj - ayi) + axi) then
            inside = not inside
        end
        j = i
    end
    return inside
end

local function CursorHitsOrientedItem(pf, item)
    if not item then return false end
    if IsLineLike(item) then
        return CursorHitsLineItem(pf, item)
    end
    if item.kind == "draw" and Diar.CursorHitsPlannerDraw then
        return Diar:CursorHitsPlannerDraw(item)
    end
    local canvas = pf and pf.canvas
    if canvas and Diar.PlannerItemUsesOrientedHit and Diar.PlannerItemUsesOrientedHit(item)
        and Diar.GetPlannerItemCornerPoints then
        local cw, ch = canvas:GetSize()
        local pts = Diar.GetPlannerItemCornerPoints(item, cw, ch, pf.sceneViewContext)
        if pts and #pts >= 3 then
            local sx, sy = CanvasCursor(pf)
            return PointInCanvasPoly(pts, sx, sy)
        end
    end
    local cx, cy = CursorPercent(pf)
    local x, y, w, h = ItemBounds(item)
    if not (cx and x) then return false end
    local pad = 0.4
    return cx >= (x - pad) and cy >= (y - pad) and cx <= (x + w + pad) and cy <= (y + h + pad)
end

local function CursorInsideSelection(pf)
    local scene = GetScene(pf)
    local indices = SortedIndices(pf and pf.__selectedItemSet)
    if not scene or #indices == 0 then return false end
    for i = 1, #indices do
        if CursorHitsOrientedItem(pf, scene.items and scene.items[indices[i]]) then
            return true
        end
    end
    if pf.__selBox and math.abs(pf.__selAngle or 0) > 0.05 then
        local b = pf.__selBox
        local x1, y1 = WorldToCanvas(pf, b.l, b.t)
        local x2, y2 = WorldToCanvas(pf, b.l + b.w, b.t + b.h)
        local left, top, pw, ph = x1, y1, x2 - x1, y2 - y1
        local cx = left + pw * 0.5
        local cy = top + ph * 0.5
        local raw = {
            { left, top },
            { left + pw, top },
            { left + pw, top + ph },
            { left, top + ph },
        }
        local pts = {}
        for i = 1, 4 do
            local x, y = RotatePx(raw[i][1], raw[i][2], cx, cy, pf.__selAngle or 0)
            pts[i] = { x, y }
        end
        local sx, sy = CanvasCursor(pf)
        return PointInCanvasPoly(pts, sx, sy)
    end
    local l, t, w, h = UnionBounds(scene, indices)
    local cx, cy = CursorPercent(pf)
    if not (l and cx) then return false end
    local pad = 0.4
    return cx >= (l - pad) and cy >= (t - pad) and cx <= (l + w + pad) and cy <= (t + h + pad)
end

function Diar:TryPlannerCanvasDeselect(button)
    if button ~= "LeftButton" then return false end
    if self._plannerMarquee then return true end
    if self._plannerDrag or self._plannerResize or self._plannerGroupDrag or self._plannerRotate or self._plannerLineEndDrag then return false end
    local pf = self.plannerFrame
    if not pf or (pf.__palettePlacement ~= nil) then return false end
    if not CanEdit() then return false end
    if IsShiftKeyDown and IsShiftKeyDown() then
        self:BeginPlannerMarqueeSelect()
        return true
    end
    if CursorInsideSelection(pf) then
        self:BeginPlannerGroupBoxDrag()
        return true
    end
    local scene = GetScene(pf)
    if scene and scene.items then
        for i = #scene.items, 1, -1 do
            local item = scene.items[i]
            if CursorHitsOrientedItem(pf, item) then
                SelectionMatchesPlan(pf)
                if not IsMultiModifierDown() then
                    pf.__selectedItemSet = { [i] = true }
                else
                    local set = SelectedSet(pf)
                    set[i] = true
                end
                pf.__selectedSceneIndex = pf.selectedSceneIndex or 1
                pf.__selectionPlanKey = CurrentPlanKey()
                ClearSelXform(pf)
                self:SyncPlannerSelectionOverlay()
                if item.widget then
                    self:BeginPlannerItemDrag(item.widget)
                else
                    self:BeginPlannerGroupBoxDrag()
                end
                return true
            end
        end
    end
    if IsMultiModifierDown() then return false end
    self:ClearPlannerSelection()
    return false
end

function Diar:RetargetPlannerItemDragAfterCopy(oldWidget)
    local drag = self._plannerDrag
    local pf = self.plannerFrame
    if not drag or drag.altCopied or not IsAltDuplicateDown() then return oldWidget end
    local newIndex = self:DuplicatePlannerSelection(drag.itemIndex)
    if not newIndex then return oldWidget end
    local scene = GetScene(pf)
    local item = scene and scene.items and scene.items[newIndex]
    local widget = item and item.widget
    if oldWidget and oldWidget.SetScript then
        oldWidget:SetScript("OnUpdate", nil)
    end
    if not widget then return oldWidget end
    local _, _, _, xOfs, yOfs = widget:GetPoint()
    if not xOfs or not yOfs then
        local canvas = drag.canvas
        xOfs = (widget:GetLeft() or 0) - (canvas:GetLeft() or 0)
        yOfs = (widget:GetTop() or 0) - (canvas:GetTop() or 0)
    end
    drag.widget = widget
    drag.itemIndex = newIndex
    drag.startXOfs = xOfs
    drag.startYOfs = yOfs
    drag.altCopied = true
    widget:SetFrameLevel((drag.canvas:GetFrameLevel() or 1) + 24)
    widget:SetScript("OnUpdate", function(w)
        Diar:UpdatePlannerItemDrag(w)
    end)
    if self.PreparePlannerSelectionDrag then
        self:PreparePlannerSelectionDrag()
    end
    return widget
end

function Diar:RetargetPlannerGroupDragAfterCopy()
    local drag = self._plannerGroupDrag
    local pf = self.plannerFrame
    if not drag or drag.altCopied or not IsAltDuplicateDown() then return end
    if not self:DuplicatePlannerSelection() then return end
    local scene = GetScene(pf)
    local indices = SortedIndices(pf.__selectedItemSet)
    local starts = {}
    for i = 1, #indices do
        local idx = indices[i]
        local item = scene and scene.items and scene.items[idx]
        local ax, ay = ItemAnchor(item)
        local widget = item and item.widget
        local xOfs, yOfs
        if widget and widget.GetPoint then
            local _
            _, _, _, xOfs, yOfs = widget:GetPoint()
        end
        starts[idx] = { x = ax, y = ay, xOfs = xOfs, yOfs = yOfs, widget = widget }
    end
    drag.indices = indices
    drag.starts = starts
    drag.altCopied = true
end

function Diar:PreparePlannerSelectionDrag()
    local pf = self.plannerFrame
    local drag = self._plannerDrag
    if not pf or not drag then
        self._plannerSelectionDrag = nil
        return
    end
    local scene = GetScene(pf)
    local set = pf.__selectedItemSet or {}
    if not scene or not set[drag.itemIndex] then
        self._plannerSelectionDrag = nil
        return
    end
    local indices = SortedIndices(set)
    if #indices <= 1 then
        self._plannerSelectionDrag = nil
        return
    end
    local starts = {}
    for i = 1, #indices do
        local idx = indices[i]
        local item = scene.items[idx]
        local widget = item and item.widget
        local ax, ay = ItemAnchor(item)
        local xOfs, yOfs
        if widget and widget.GetPoint then
            local _
            _, _, _, xOfs, yOfs = widget:GetPoint()
        end
        starts[idx] = {
            x = ax,
            y = ay,
            xOfs = xOfs,
            yOfs = yOfs,
            widget = widget,
        }
    end
    local grabbed = starts[drag.itemIndex]
    self._plannerSelectionDrag = {
        indices = indices,
        starts = starts,
        grabX = grabbed and grabbed.x or 0,
        grabY = grabbed and grabbed.y or 0,
        grabXOfs = grabbed and grabbed.xOfs,
        grabYOfs = grabbed and grabbed.yOfs,
    }
end

function Diar:UpdatePlannerSelectionDrag(widget, relX, relY)
    local snap = self._plannerSelectionDrag
    local drag = self._plannerDrag
    if not snap or not drag or not widget then return end
    local startX = snap.grabXOfs
    local startY = snap.grabYOfs
    if not startX or not startY then return end
    local dx, dy = relX - startX, (-relY) - startY
    for i = 1, #snap.indices do
        local idx = snap.indices[i]
        if idx ~= drag.itemIndex then
            local start = snap.starts[idx]
            local other = start and start.widget
            if other and start.xOfs and start.yOfs then
                other:ClearAllPoints()
                other:SetPoint("TOPLEFT", drag.canvas, "TOPLEFT", start.xOfs + dx, start.yOfs + dy)
            end
        end
    end
    if self.SyncPlannerSelectionOverlay then
        self:SyncPlannerSelectionOverlay()
    end
end

function Diar:FinishPlannerSelectionDrag(xp, yp)
    local snap = self._plannerSelectionDrag
    self._plannerSelectionDrag = nil
    if not snap or #snap.indices <= 1 then return false end
    local dx = xp - snap.grabX
    local dy = yp - snap.grabY
    for i = 1, #snap.indices do
        local idx = snap.indices[i]
        local start = snap.starts[idx]
        if start then
            local opts = { skipRefresh = true, skipPersist = true, skipBroadcast = true }
            self:ApplyItemPositionChange(idx, start.x + dx, start.y + dy, opts)
        end
    end
    NudgeSelXform(self.plannerFrame, dx, dy)
    if self.PersistCurrentPlanToSaved then
        self:PersistCurrentPlanToSaved()
    end
    if self.RefreshPlannerScene then
        self:RefreshPlannerScene()
    end
    return true
end

local function EnsureResizeTicker(pf)
    if pf.__selResizeTicker then return pf.__selResizeTicker end
    local ticker = CreateFrame("Frame", nil, pf)
    ticker:Hide()
    pf.__selResizeTicker = ticker
    return ticker
end

local function TickerInUse()
    return Diar._plannerResize or Diar._plannerRotate or Diar._plannerGroupDrag
        or Diar._plannerLineEndDrag or Diar._plannerMarquee
end

local function StopTickerIfIdle(pf)
    if pf and pf.__selResizeTicker and not TickerInUse() then
        pf.__selResizeTicker:SetScript("OnUpdate", nil)
        pf.__selResizeTicker:Hide()
    end
end

local function PointInAabb(x, y, l, t, r, b)
    return x >= l and x <= r and y >= t and y <= b
end

local function AabbOverlap(aL, aT, aR, aB, bL, bT, bR, bB)
    return aL < bR and aR > bL and aT < bB and aB > bT
end

local function SegIntersectsAabb(x1, y1, x2, y2, l, t, r, b)
    local dx, dy = x2 - x1, y2 - y1
    local t0, t1 = 0, 1
    local function clip(p, q)
        if math.abs(p) < 1e-9 then
            return q >= 0
        end
        local u = q / p
        if p < 0 then
            if u > t1 then return false end
            if u > t0 then t0 = u end
        else
            if u < t0 then return false end
            if u < t1 then t1 = u end
        end
        return true
    end
    return clip(-dx, x1 - l) and clip(dx, r - x1) and clip(-dy, y1 - t) and clip(dy, b - y1)
end

local function ItemHitsMarquee(pf, item, l, t, r, b)
    if not item then return false end
    if IsLineLike(item) then
        local x1, y1, x2, y2 = LinePixelEnds(pf, item)
        if not x1 then return false end
        return PointInAabb(x1, y1, l, t, r, b)
            or PointInAabb(x2, y2, l, t, r, b)
            or SegIntersectsAabb(x1, y1, x2, y2, l, t, r, b)
    end
    local canvas = pf and pf.canvas
    if canvas and Diar.PlannerItemUsesOrientedHit and Diar.PlannerItemUsesOrientedHit(item)
        and Diar.GetPlannerItemCornerPoints then
        local cw, ch = canvas:GetSize()
        local pts = Diar.GetPlannerItemCornerPoints(item, cw, ch, pf.sceneViewContext)
        if pts and #pts >= 3 then
            for i = 1, #pts do
                if PointInAabb(pts[i][1], pts[i][2], l, t, r, b) then
                    return true
                end
            end
            if PointInCanvasPoly(pts, l, t) or PointInCanvasPoly(pts, r, t)
                or PointInCanvasPoly(pts, r, b) or PointInCanvasPoly(pts, l, b) then
                return true
            end
            for i = 1, #pts do
                local a = pts[i]
                local c = pts[(i % #pts) + 1]
                if SegIntersectsAabb(a[1], a[2], c[1], c[2], l, t, r, b) then
                    return true
                end
            end
            return false
        end
    end
    local il, it, iw, ih = LiveItemPixelBox(pf, item)
    if not il then return false end
    return AabbOverlap(il, it, il + iw, it + ih, l, t, r, b)
end

local function EnsureMarquee(pf)
    local m = pf.__selMarquee
    if m then return m end
    m = CreateFrame("Frame", nil, pf)
    m:EnableMouse(false)
    local fill = m:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(RING[1], RING[2], RING[3], 0.16)
    m.fill = fill
    m.edges = CreateEdgeBox(m, RING[1], RING[2], RING[3], 0.95)
    m.edges:SetAllPoints(m)
    pf.__selMarquee = m
    return m
end

local function HideMarquee(pf)
    if pf and pf.__selMarquee then
        pf.__selMarquee:Hide()
    end
end

local function PlaceMarquee(pf, x1, y1, x2, y2)
    local canvas = pf and pf.canvas
    if not canvas then return nil end
    local cw, ch = canvas:GetSize()
    if not cw or not ch then return nil end
    local left = math.max(0, math.min(x1, x2))
    local top = math.max(0, math.min(y1, y2))
    local right = math.min(cw, math.max(x1, x2))
    local bottom = math.min(ch, math.max(y1, y2))
    local pw = math.max(1, right - left)
    local ph = math.max(1, bottom - top)
    local m = EnsureMarquee(pf)
    m:SetParent(pf)
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", canvas, "TOPLEFT", left, -top)
    m:SetSize(pw, ph)
    m:SetFrameLevel((canvas:GetFrameLevel() or 1) + 70)
    m:Show()
    if m.edges then m.edges:Show() end
    return left, top, right, bottom
end

function Diar:BeginPlannerMarqueeSelect()
    local pf = self.plannerFrame
    if not pf or not CanEdit() then return end
    if self._plannerDrag or self._plannerResize or self._plannerGroupDrag
        or self._plannerRotate or self._plannerLineEndDrag then
        return
    end
    local sx, sy = CanvasCursor(pf)
    if not sx then return end
    self._plannerMarquee = { startSx = sx, startSy = sy, moved = false }
    local ticker = EnsureResizeTicker(pf)
    ticker:SetScript("OnUpdate", function()
        Diar:UpdatePlannerMarqueeSelect()
    end)
    ticker:Show()
end

function Diar:UpdatePlannerMarqueeSelect()
    local drag = self._plannerMarquee
    local pf = self.plannerFrame
    if not drag or not pf then return end
    if not IsMouseButtonDown("LeftButton") then
        self:EndPlannerMarqueeSelect()
        return
    end
    local sx, sy = CanvasCursor(pf)
    if not sx then return end
    local dx, dy = sx - drag.startSx, sy - drag.startSy
    if (dx * dx + dy * dy) >= 16 then
        drag.moved = true
    end
    if drag.moved then
        PlaceMarquee(pf, drag.startSx, drag.startSy, sx, sy)
    end
end

function Diar:EndPlannerMarqueeSelect()
    local drag = self._plannerMarquee
    self._plannerMarquee = nil
    local pf = self.plannerFrame
    HideMarquee(pf)
    StopTickerIfIdle(pf)
    if not drag or not pf or not CanEdit() then return end
    local scene = GetScene(pf)
    if not scene or not scene.items then return end
    SelectionMatchesPlan(pf)
    pf.__selectedSceneIndex = pf.selectedSceneIndex or 1
    pf.__selectionPlanKey = CurrentPlanKey()

    if not drag.moved then
        for i = #scene.items, 1, -1 do
            if CursorHitsOrientedItem(pf, scene.items[i]) then
                SelectedSet(pf)[i] = true
                ClearSelXform(pf)
                self:SyncPlannerSelectionOverlay()
                return
            end
        end
        return
    end

    local sx, sy = CanvasCursor(pf)
    if not sx then
        sx, sy = drag.startSx, drag.startSy
    end
    local box = { PlaceMarquee(pf, drag.startSx, drag.startSy, sx, sy) }
    HideMarquee(pf)
    local l, t, r, b = box[1], box[2], box[3], box[4]
    if not l then return end

    local addTo = IsMultiModifierDown()
    local set = addTo and SelectedSet(pf) or {}
    if not addTo then
        pf.__selectedItemSet = set
    end
    for i = 1, #scene.items do
        if ItemHitsMarquee(pf, scene.items[i], l, t, r, b) then
            set[i] = true
        end
    end
    ClearSelXform(pf)
    self:SyncPlannerSelectionOverlay()
end

function Diar:BeginPlannerGroupBoxDrag()
    local pf = self.plannerFrame
    if not pf or not CanEdit() or self._plannerDrag or self._plannerResize then return end
    local scene = GetScene(pf)
    local indices = SortedIndices(pf.__selectedItemSet)
    if not scene or #indices == 0 then return end
    local cx, cy = CursorPercent(pf)
    local sx, sy = CanvasCursor(pf)
    if not cx or not sx then return end
    local starts = {}
    for i = 1, #indices do
        local idx = indices[i]
        local item = scene.items[idx]
        local ax, ay = ItemAnchor(item)
        local widget = item and item.widget
        local xOfs, yOfs
        if widget and widget.GetPoint then
            local _
            _, _, _, xOfs, yOfs = widget:GetPoint()
        end
        starts[idx] = { x = ax, y = ay, xOfs = xOfs, yOfs = yOfs, widget = widget }
    end
    self._plannerGroupDrag = {
        startCx = cx,
        startCy = cy,
        startSx = sx,
        startSy = sy,
        starts = starts,
        indices = indices,
        canvas = pf.canvas,
        moved = false,
    }
    local ticker = EnsureResizeTicker(pf)
    ticker:SetScript("OnUpdate", function()
        Diar:UpdatePlannerGroupBoxDrag()
    end)
    ticker:Show()
end

function Diar:UpdatePlannerGroupBoxDrag()
    local drag = self._plannerGroupDrag
    local pf = self.plannerFrame
    if not drag or not pf then return end
    if not IsMouseButtonDown("LeftButton") then
        self:EndPlannerGroupBoxDrag()
        return
    end
    local sx, sy = CanvasCursor(pf)
    if not sx then return end
    if not drag.moved then
        local adx = sx - drag.startSx
        local ady = sy - drag.startSy
        if (adx * adx + ady * ady) < 16 then
            return
        end
        drag.moved = true
        if self.RetargetPlannerGroupDragAfterCopy then
            self:RetargetPlannerGroupDragAfterCopy()
            drag = self._plannerGroupDrag
            if not drag then return end
        end
    end
    local dx, dy = sx - drag.startSx, sy - drag.startSy
    for i = 1, #drag.indices do
        local start = drag.starts[drag.indices[i]]
        local widget = start and start.widget
        if widget and start.xOfs and start.yOfs then
            widget:ClearAllPoints()
            widget:SetPoint("TOPLEFT", drag.canvas, "TOPLEFT", start.xOfs + dx, start.yOfs - dy)
        end
    end
    if self.SyncPlannerSelectionOverlay then
        self:SyncPlannerSelectionOverlay()
    end
end

function Diar:EndPlannerGroupBoxDrag()
    local drag = self._plannerGroupDrag
    self._plannerGroupDrag = nil
    local pf = self.plannerFrame
    if pf and pf.__selResizeTicker and not self._plannerResize then
        pf.__selResizeTicker:SetScript("OnUpdate", nil)
        pf.__selResizeTicker:Hide()
    end
    if not drag or not drag.moved then return end
    local cx, cy = CursorPercent(pf)
    if not cx then
        if self.RefreshPlannerScene then self:RefreshPlannerScene() end
        return
    end
    local dx, dy = cx - drag.startCx, cy - drag.startCy
    for i = 1, #drag.indices do
        local idx = drag.indices[i]
        local start = drag.starts[idx]
        if start then
            self:ApplyItemPositionChange(idx, start.x + dx, start.y + dy, {
                skipRefresh = true,
                skipPersist = true,
                skipBroadcast = true,
            })
        end
    end
    NudgeSelXform(pf, dx, dy)
    if self.PersistCurrentPlanToSaved then
        self:PersistCurrentPlanToSaved()
    end
    if self.RefreshPlannerScene then
        self:RefreshPlannerScene()
    end
end

function Diar:BeginPlannerLineEndpointDrag(itemIndex, which)
    local pf = self.plannerFrame
    if not pf or not CanEdit() or self._plannerDrag or self._plannerResize or self._plannerGroupDrag then
        return
    end
    local scene, sceneIdx = GetScene(pf)
    local item = scene and scene.items and scene.items[itemIndex]
    if not IsLineLike(item) then return end
    self._plannerLineEndDrag = {
        itemIndex = itemIndex,
        which = which == "start" and "start" or "end",
        sceneIndex = sceneIdx,
        nextAt = 0,
    }
    local ticker = EnsureResizeTicker(pf)
    ticker:SetScript("OnUpdate", function()
        Diar:UpdatePlannerLineEndpointDrag()
    end)
    ticker:Show()
end

function Diar:UpdatePlannerLineEndpointDrag()
    local drag = self._plannerLineEndDrag
    local pf = self.plannerFrame
    if not drag or not pf then return end
    if not IsMouseButtonDown("LeftButton") then
        self:EndPlannerLineEndpointDrag()
        return
    end
    local cx, cy = CursorPercent(pf)
    if not cx then return end
    cx = math.max(0, math.min(100, cx))
    cy = math.max(0, math.min(100, cy))
    local scene = GetScene(pf)
    if not scene or (pf.selectedSceneIndex or 1) ~= drag.sceneIndex then
        self:EndPlannerLineEndpointDrag(true)
        return
    end
    local item = scene.items[drag.itemIndex]
    if not IsLineLike(item) then
        self:EndPlannerLineEndpointDrag(true)
        return
    end
    if drag.which == "start" then
        item.x1, item.y1 = cx, cy
    else
        item.x2, item.y2 = cx, cy
    end
    local now = GetTime() or 0
    if now >= (drag.nextAt or 0) then
        drag.nextAt = now + (1 / RESIZE_FPS)
        if self.RefreshPlannerScene then
            self:RefreshPlannerScene()
        end
    else
        self:SyncPlannerSelectionOverlay()
    end
end

function Diar:EndPlannerLineEndpointDrag(cancelPersist)
    local drag = self._plannerLineEndDrag
    self._plannerLineEndDrag = nil
    local pf = self.plannerFrame
    if pf and pf.__selResizeTicker and not self._plannerResize then
        pf.__selResizeTicker:SetScript("OnUpdate", nil)
        pf.__selResizeTicker:Hide()
    end
    if not drag then return end
    if not cancelPersist and self.PersistCurrentPlanToSaved then
        self:PersistCurrentPlanToSaved()
    end
    if self.RefreshPlannerScene then
        self:RefreshPlannerScene()
    end
end

function Diar:BeginPlannerSelectionResize(handleKey)
    if handleKey == "rotate" then
        self:BeginPlannerSelectionRotate()
        return
    end
    local pf = self.plannerFrame
    if not pf or not CanEdit() or self._plannerDrag or self._plannerGroupDrag or self._plannerRotate then return end
    local scene, sceneIdx = GetScene(pf)
    local indices = SortedIndices(pf.__selectedItemSet)
    if not scene or #indices == 0 then return end
    local box, ang = EnsureSelXform(pf, scene, indices)
    if not box then return end
    local geoms = {}
    for i = 1, #indices do
        local item = scene.items[indices[i]]
        if item then
            geoms[indices[i]] = CopyGeom(item)
        end
    end
    self._plannerResize = {
        handle = handleKey,
        sceneIndex = sceneIdx,
        indices = indices,
        geoms = geoms,
        box = { l = box.l, t = box.t, w = box.w, h = box.h },
        angle = ang or 0,
        nextAt = 0,
    }
    local ticker = EnsureResizeTicker(pf)
    ticker:SetScript("OnUpdate", function()
        Diar:UpdatePlannerSelectionResize()
    end)
    ticker:Show()
end

function Diar:UpdatePlannerSelectionResize()
    local resize = self._plannerResize
    local pf = self.plannerFrame
    if not resize or not pf then return end
    if not IsMouseButtonDown("LeftButton") then
        self:EndPlannerSelectionResize()
        return
    end
    local cx, cy = CursorPercent(pf)
    if not cx then return end
    local scene = GetScene(pf)
    if not scene or (pf.selectedSceneIndex or 1) ~= resize.sceneIndex then
        self:EndPlannerSelectionResize(true)
        return
    end
    cx = math.max(0, math.min(100, cx))
    cy = math.max(0, math.min(100, cy))
    local freeResize = IsShiftKeyDown and IsShiftKeyDown()
    local lx, ly = cx, cy
    local ang = resize.angle or 0
    if math.abs(ang) > 0.05 then
        local px = resize.box.l + resize.box.w * 0.5
        local py = resize.box.t + resize.box.h * 0.5
        lx, ly = RotatePctPoint(pf, cx, cy, px, py, -ang)
    end
    local ox, oy, sx, sy = ScaleFromHandle(resize.handle, resize.box, lx, ly, freeResize)
    for i = 1, #resize.indices do
        local idx = resize.indices[i]
        local item = scene.items[idx]
        local geom = resize.geoms[idx]
        if item and geom then
            ApplyScaledGeom(item, geom, ox, oy, sx, sy)
        end
    end
    ClearSelXform(pf)
    local now = GetTime() or 0
    if now >= (resize.nextAt or 0) then
        resize.nextAt = now + (1 / RESIZE_FPS)
        if self.RefreshPlannerScene then
            self:RefreshPlannerScene()
        end
    end
end

function Diar:BeginPlannerSelectionRotate()
    local pf = self.plannerFrame
    if not pf or not CanEdit() or self._plannerDrag or self._plannerResize or self._plannerGroupDrag or self._plannerLineEndDrag then
        return
    end
    local scene, sceneIdx = GetScene(pf)
    local indices = SortedIndices(pf.__selectedItemSet)
    if not scene or #indices == 0 then return end
    local box, baseAng, ox, oy = EnsureSelXform(pf, scene, indices)
    if not box then return end
    ox, oy = ox or (box.l + box.w * 0.5), oy or (box.t + box.h * 0.5)
    local cxp, cyp = WorldToCanvas(pf, ox, oy)
    local sx, sy = CanvasCursor(pf)
    if not sx then return end
    local geoms = {}
    for i = 1, #indices do
        local item = scene.items[indices[i]]
        if item then
            geoms[indices[i]] = CopyGeom(item)
        end
    end
    self._plannerRotate = {
        sceneIndex = sceneIdx,
        indices = indices,
        geoms = geoms,
        ox = ox,
        oy = oy,
        startAng = math.deg(math.atan2(sy - cyp, sx - cxp)),
        baseAng = baseAng or 0,
        nextAt = 0,
    }
    local ticker = EnsureResizeTicker(pf)
    ticker:SetScript("OnUpdate", function()
        Diar:UpdatePlannerSelectionRotate()
    end)
    ticker:Show()
end

function Diar:UpdatePlannerSelectionRotate()
    local rotate = self._plannerRotate
    local pf = self.plannerFrame
    if not rotate or not pf then return end
    if not IsMouseButtonDown("LeftButton") then
        self:EndPlannerSelectionRotate()
        return
    end
    local scene = GetScene(pf)
    if not scene or (pf.selectedSceneIndex or 1) ~= rotate.sceneIndex then
        self:EndPlannerSelectionRotate(true)
        return
    end
    local sx, sy = CanvasCursor(pf)
    if not sx then return end
    local cxp, cyp = WorldToCanvas(pf, rotate.ox, rotate.oy)
    local delta = math.deg(math.atan2(sy - cyp, sx - cxp)) - rotate.startAng
    if IsShiftKeyDown and IsShiftKeyDown() then
        delta = math.floor(delta / 15 + (delta >= 0 and 0.5 or -0.5)) * 15
    end
    pf.__selAngle = (rotate.baseAng or 0) + delta
    for i = 1, #rotate.indices do
        local idx = rotate.indices[i]
        local item = scene.items[idx]
        local geom = rotate.geoms[idx]
        if item and geom then
            ApplyRotatedGeom(pf, item, geom, rotate.ox, rotate.oy, delta)
        end
    end
    local now = GetTime() or 0
    if now >= (rotate.nextAt or 0) then
        rotate.nextAt = now + (1 / RESIZE_FPS)
        if self.RefreshPlannerScene then
            self:RefreshPlannerScene()
        end
    else
        self:SyncPlannerSelectionOverlay()
    end
end

function Diar:EndPlannerSelectionRotate(cancelPersist)
    local rotate = self._plannerRotate
    self._plannerRotate = nil
    local pf = self.plannerFrame
    if pf and pf.__selResizeTicker and not self._plannerResize and not self._plannerLineEndDrag then
        pf.__selResizeTicker:SetScript("OnUpdate", nil)
        pf.__selResizeTicker:Hide()
    end
    if not rotate then return end
    if not cancelPersist and self.PersistCurrentPlanToSaved then
        self:PersistCurrentPlanToSaved()
    end
    if self.RefreshPlannerScene then
        self:RefreshPlannerScene()
    end
end

function Diar:EndPlannerSelectionResize(cancelPersist)
    local resize = self._plannerResize
    self._plannerResize = nil
    local pf = self.plannerFrame
    if pf and pf.__selResizeTicker then
        pf.__selResizeTicker:SetScript("OnUpdate", nil)
        pf.__selResizeTicker:Hide()
    end
    if not resize then return end
    if not cancelPersist and self.PersistCurrentPlanToSaved then
        self:PersistCurrentPlanToSaved()
    end
    if self.RefreshPlannerScene then
        self:RefreshPlannerScene()
    end
end

function Diar:SyncPlannerSelectionOverlay()
    local pf = self.plannerFrame
    if not pf or not pf.canvas or not pf:IsShown() then return end
    if self.IsPlannerCompactMode and self:IsPlannerCompactMode() then
        HideOverlay(pf)
        return
    end
    if not CanEdit() then
        HideOverlay(pf)
        return
    end
    local scene, sceneIdx = GetScene(pf)
    if not scene then
        HideOverlay(pf)
        return
    end
    if not SelectionMatchesPlan(pf) then
        ClearSelXform(pf)
        HideOverlay(pf)
        return
    end
    if pf.__selectedSceneIndex and pf.__selectedSceneIndex ~= sceneIdx then
        pf.__selectedItemSet = {}
        ClearSelXform(pf)
        HideOverlay(pf)
        return
    end
    local set = pf.__selectedItemSet
    local indices = SortedIndices(set)
    if #indices == 0 then
        HideOverlay(pf)
        return
    end
    local valid = {}
    for i = 1, #indices do
        if scene.items[indices[i]] then
            valid[#valid + 1] = indices[i]
        else
            set[indices[i]] = nil
        end
    end
    if #valid == 0 then
        HideOverlay(pf)
        return
    end
    if (self._plannerDrag and self._plannerDrag.moved)
        or (self._plannerGroupDrag and self._plannerGroupDrag.moved) then
        HideOverlay(pf)
        return
    end
    local left, top, pw, ph, itemBoxes
    local angle = 0
    local box = EnsureSelXform(pf, scene, valid)
    if box then
        local x1, y1 = WorldToCanvas(pf, box.l, box.t)
        local x2, y2 = WorldToCanvas(pf, box.l + box.w, box.t + box.h)
        local dx, dy = 0, 0
        if self._plannerDrag or self._plannerGroupDrag then
            dx, dy = LiveDragPixelDelta(pf)
        end
        left, top, pw, ph = x1 + dx, y1 + dy, x2 - x1, y2 - y1
        angle = pf.__selAngle or 0
    end
    if #valid > 1 and math.abs(angle) < 0.05 then
        local _, _, _, _, liveBoxes = LiveUnionPixelBox(pf, scene, valid)
        itemBoxes = liveBoxes
    end
    if not left then
        HideOverlay(pf)
        return
    end

    local overlay = EnsureOverlay(pf)
    overlay:SetParent(pf)
    overlay:ClearAllPoints()
    overlay:SetAllPoints(pf.canvas)
    overlay:SetFrameLevel((pf.canvas:GetFrameLevel() or 1) + 60)
    if overlay.SetClipsChildren then
        overlay:SetClipsChildren(true)
    end
    overlay:Show()

    local allLines = true
    for i = 1, #valid do
        if not IsLineLike(scene.items[valid[i]]) then
            allLines = false
            break
        end
    end

    local lineIndex = 1
    if allLines then
        HideBoxHandles(overlay)
        for i = 1, #valid do
            PlaceLineChrome(EnsureLineChrome(overlay, lineIndex), pf, scene.items[valid[i]], valid[i])
            lineIndex = lineIndex + 1
        end
        HideLineChroms(overlay, lineIndex)
        for i = 1, #(overlay.itemBoxes or {}) do
            overlay.itemBoxes[i]:Hide()
        end
        PlaceRotatedChrome(overlay, pf.canvas, left, top, pw, ph, angle, true)
        return
    end

    local boxIndex = 1
    if #valid > 1 and itemBoxes and math.abs(angle) < 0.05 then
        for i = 1, #valid do
            local item = scene.items[valid[i]]
            if IsLineLike(item) then
                PlaceLineChrome(EnsureLineChrome(overlay, lineIndex), pf, item, valid[i])
                lineIndex = lineIndex + 1
            else
                local b = itemBoxes[i]
                if b then
                    PlaceRectPixels(EnsureItemBox(overlay, boxIndex), pf.canvas, b[1], b[2], b[3], b[4])
                    boxIndex = boxIndex + 1
                end
            end
        end
    end
    HideLineChroms(overlay, lineIndex)
    for i = boxIndex, #(overlay.itemBoxes or {}) do
        overlay.itemBoxes[i]:Hide()
    end
    PlaceRotatedChrome(overlay, pf.canvas, left, top, pw, ph, angle, false)
end

function Diar:HandlePlannerEscapeKey()
    if GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() then
        return false
    end
    local pf = self.plannerFrame
    if not pf or not pf.IsShown or not pf:IsShown() then return false end

    local handled = false
    if self._plannerMarquee then
        self._plannerMarquee = nil
        HideMarquee(pf)
        StopTickerIfIdle(pf)
        handled = true
    end
    if self._plannerResize then
        self:EndPlannerSelectionResize(true)
        handled = true
    end
    if self._plannerRotate then
        self:EndPlannerSelectionRotate(true)
        handled = true
    end
    if self._plannerDrag or self._plannerGroupDrag or self._plannerLineEndDrag then
        self._plannerDrag = nil
        self._plannerGroupDrag = nil
        self._plannerLineEndDrag = nil
        self._plannerSelectionDrag = nil
        StopTickerIfIdle(pf)
        if self.RefreshPlannerScene then
            self:RefreshPlannerScene()
        end
        handled = true
    end
    if pf.__palettePlacement and self.ClearPalettePlacement then
        self:ClearPalettePlacement()
        handled = true
    end

    local menuOpen = (self._plannerCtxMenu and self._plannerCtxMenu:IsShown())
        or (self._worldMarkerReplaceMenu and self._worldMarkerReplaceMenu:IsShown())
        or (self._memberPicker and self._memberPicker:IsShown())
    if self.HidePlannerTransientMenus then
        self:HidePlannerTransientMenus()
    end
    if menuOpen then handled = true end

    local set = pf.__selectedItemSet
    if type(set) == "table" then
        for _ in pairs(set) do
            self:ClearPlannerSelection()
            return true
        end
    end
    return handled
end

if not Diar._plannerEscapeHooked and type(CloseSpecialWindows) == "function" then
    Diar._plannerEscapeHooked = true
    local previous = CloseSpecialWindows
    function CloseSpecialWindows()
        if Diar.HandlePlannerEscapeKey and Diar:HandlePlannerEscapeKey() then
            return 1
        end
        return previous()
    end
end
