-- Freehand draw tool: sample, simplify, and store a compact polyline.
local addonName = ...
local AceAddon = LibStub("AceAddon-3.0")
local Addon =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)
if not Addon then return end
local Diar = Addon

local SAMPLE_MIN_PX = 5
local MAX_LIVE_POINTS = 160
local MAX_FINAL_POINTS = 72
local RDP_EPS_PX = 2.4

function Diar:IsPlannerDrawItem(item)
    return item and item.kind == "draw"
end

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
    return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy))
end

local function SimplifyRDP(pts, eps)
    if type(pts) ~= "table" or #pts < 3 then return pts end
    local function rec(a, b, out)
        local maxD, maxI = 0, nil
        for i = a + 1, b - 1 do
            local d = DistToSeg(pts[i].x, pts[i].y, pts[a].x, pts[a].y, pts[b].x, pts[b].y)
            if d > maxD then
                maxD, maxI = d, i
            end
        end
        if maxI and maxD > eps then
            rec(a, maxI, out)
            rec(maxI, b, out)
        else
            if #out == 0 then out[1] = pts[a] end
            out[#out + 1] = pts[b]
        end
    end
    local out = {}
    rec(1, #pts, out)
    return out
end

local function CapPoints(pts, maxN)
    if type(pts) ~= "table" or #pts <= maxN then return pts end
    local step = (#pts - 1) / (maxN - 1)
    local out = {}
    for i = 0, maxN - 2 do
        out[#out + 1] = pts[math.floor(i * step + 1)]
    end
    out[#out + 1] = pts[#pts]
    return out
end

function Diar:SimplifyPlannerDrawPoints(pts, epsPx)
    local simple = SimplifyRDP(pts, epsPx or RDP_EPS_PX)
    return CapPoints(simple, MAX_FINAL_POINTS)
end

local function HideDrawPreview(pf)
    local preview = pf and pf.__plannerDrawPreview
    if not preview then return end
    preview:Hide()
    for i = 1, #(preview._lines or {}) do
        preview._lines[i]:Hide()
    end
    preview._used = 0
end

function Diar:HidePlannerDrawPreview(pf)
    HideDrawPreview(pf or self.plannerFrame)
end

local function EnsureDrawPreview(pf)
    local canvas = pf and pf.canvas
    if not canvas then return nil end
    local host = pf.__paletteDragLayer or canvas
    local preview = pf.__plannerDrawPreview
    if preview and preview:GetParent() ~= host then
        preview:Hide()
        preview = nil
        pf.__plannerDrawPreview = nil
    end
    if not preview then
        preview = CreateFrame("Frame", nil, host)
        preview:EnableMouse(false)
        preview._lines = {}
        preview._used = 0
        pf.__plannerDrawPreview = preview
    end
    preview:SetParent(host)
    preview:ClearAllPoints()
    preview:SetAllPoints(canvas)
    preview:SetFrameLevel((host:GetFrameLevel() or 1) + 2)
    preview:Show()
    return preview
end

local function AcquirePreviewLine(preview)
    preview._used = (preview._used or 0) + 1
    local ln = preview._lines[preview._used]
    if not ln then
        ln = preview:CreateLine(nil, "ARTWORK")
        preview._lines[preview._used] = ln
    end
    ln:Show()
    return ln
end

function Diar:RefreshPlannerDrawPreview(pf, drag)
    if not pf or not drag or type(drag.pts) ~= "table" then
        HideDrawPreview(pf)
        return
    end
    local preview = EnsureDrawPreview(pf)
    if not preview then return end
    preview._used = 0
    local thick = math.max(2, tonumber(drag.thick) or 3)
    local r, g, b = drag.r or 1, drag.g or 1, drag.b or 1
    for i = 2, #drag.pts do
        local a, bpt = drag.pts[i - 1], drag.pts[i]
        local ln = AcquirePreviewLine(preview)
        ln:SetThickness(thick)
        ln:SetColorTexture(r, g, b, 0.95)
        ln:SetStartPoint("TOPLEFT", pf.canvas, a.x, -a.y)
        ln:SetEndPoint("TOPLEFT", pf.canvas, bpt.x, -bpt.y)
    end
    for i = preview._used + 1, #preview._lines do
        preview._lines[i]:Hide()
    end
end

function Diar:BeginPlannerDrawStroke(pf, x, y, cw, ch, template)
    if not pf then return nil end
    HideDrawPreview(pf)
    local stroke = tostring(template and template.stroke or "#ffffff")
    local hex = stroke:gsub("#", "")
    local r, g, b = 1, 1, 1
    if #hex >= 6 then
        r = (tonumber(hex:sub(1, 2), 16) or 255) / 255
        g = (tonumber(hex:sub(3, 4), 16) or 255) / 255
        b = (tonumber(hex:sub(5, 6), 16) or 255) / 255
    end
    local drag = {
        template = template,
        kind = "draw",
        pts = { { x = x, y = y } },
        lastX = x,
        lastY = y,
        startX = x,
        startY = y,
        curX = x,
        curY = y,
        cw = cw,
        ch = ch,
        r = r,
        g = g,
        b = b,
        thick = 3,
    }
    self:RefreshPlannerDrawPreview(pf, drag)
    return drag
end

function Diar:AddPlannerDrawSample(drag, x, y)
    if not drag or type(drag.pts) ~= "table" then return false end
    drag.curX, drag.curY = x, y
    local dx, dy = x - (drag.lastX or x), y - (drag.lastY or y)
    if (dx * dx + dy * dy) < (SAMPLE_MIN_PX * SAMPLE_MIN_PX) then
        return false
    end
    if #drag.pts >= MAX_LIVE_POINTS then
        return false
    end
    drag.pts[#drag.pts + 1] = { x = x, y = y }
    drag.lastX, drag.lastY = x, y
    return true
end

function Diar:BuildPlannerDrawItem(pf, drag)
    if not pf or not drag or type(drag.pts) ~= "table" then
        return nil
    end
    if drag.curX and drag.curY then
        local last = drag.pts[#drag.pts]
        if not last or last.x ~= drag.curX or last.y ~= drag.curY then
            drag.pts[#drag.pts + 1] = { x = drag.curX, y = drag.curY }
        end
    end
    if #drag.pts < 2 then
        return nil
    end
    local pts = self:SimplifyPlannerDrawPoints(drag.pts, RDP_EPS_PX)
    if #pts < 2 then return nil end
    local cw = drag.cw or 1
    local ch = drag.ch or 1
    if cw < 1 then cw = 1 end
    if ch < 1 then ch = 1 end
    local world = {}
    local minX, minY, maxX, maxY
    for i = 1, #pts do
        local px = (pts[i].x / cw) * 100
        local py = (pts[i].y / ch) * 100
        world[i] = { x = px, y = py }
        if not minX or px < minX then minX = px end
        if not minY or py < minY then minY = py end
        if not maxX or px > maxX then maxX = px end
        if not maxY or py > maxY then maxY = py end
    end
    local rel = {}
    for i = 1, #world do
        rel[i] = { x = world[i].x - minX, y = world[i].y - minY }
    end
    local template = drag.template or {}
    return {
        kind = "draw",
        shape = "freehand",
        x = minX,
        y = minY,
        w = math.max(0.4, maxX - minX),
        h = math.max(0.4, maxY - minY),
        points = rel,
        stroke = template.stroke or "#ffffff",
        strokeWidth = template.strokeWidth or 0.42,
    }
end

function Diar:CursorHitsPlannerDraw(item)
    local pf = self.plannerFrame
    local canvas = pf and pf.canvas
    if not pf or not canvas or not self:IsPlannerDrawItem(item) then return false end
    local pts = item.points
    if type(pts) ~= "table" or #pts < 2 then return false end
    local sx, sy
    if self.GetPlannerCanvasCursor then
        sx, sy = self:GetPlannerCanvasCursor()
    end
    if not sx then
        local scale = canvas.GetEffectiveScale and canvas:GetEffectiveScale() or 1
        local mx, my = GetCursorPosition()
        if not mx then return false end
        sx = (mx / scale) - canvas:GetLeft()
        sy = canvas:GetTop() - (my / scale)
    end
    local cw, ch = canvas:GetSize()
    if not cw or cw < 1 or not ch or ch < 1 then return false end
    local ox = tonumber(item.x) or 0
    local oy = tonumber(item.y) or 0
    local prevX, prevY
    for i = 1, #pts do
        local x = cw * ((ox + (tonumber(pts[i].x) or 0)) / 100)
        local y = ch * ((oy + (tonumber(pts[i].y) or 0)) / 100)
        if prevX and DistToSeg(sx, sy, prevX, prevY, x, y) <= 10 then
            return true
        end
        prevX, prevY = x, y
    end
    return false
end
