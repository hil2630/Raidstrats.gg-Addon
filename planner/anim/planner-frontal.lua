-- Raidstrats.gg Planner - Frontal sweep/pulse (matches website Fabric behavior).
-- A beam is drawn as a Line from the boss center outward; sweeping = rotating the end point.
-- Fabric: 0deg = up (north), positive = clockwise. dir = (sin a, cos a) in (x right, y up).
local addonName = ...
local AceAddon = LibStub("AceAddon-3.0")
local Addon =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)
if not Addon then return end
local Diar = Addon
Diar.PlannerFrontal = Diar.PlannerFrontal or {}

local function IsFrontalAnim(anim)
    if not anim then return false end
    local flag = anim.isFrontalSweepAnimation
    return flag == true or flag == 1
end

local function ResolveFrontalParentIndex(anim, scene)
    if type(anim.parentItemIndex) == "number" and anim.parentItemIndex >= 0 then
        return anim.parentItemIndex + 1
    end
    return nil
end

-- Icon center as canvas TOPLEFT offsets (x right positive, y down negative for SetPoint).
-- Items are placed with the viewport transform baked into coords, so the widget's real
-- screen position is already correct; the no-widget fallback applies the transform itself.
local function GetIconCenterOnCanvas(parentItem, parentWidget, canvas, cw, ch)
    if parentWidget and parentWidget.GetLeft and parentWidget:IsShown() then
        local w, h = parentWidget:GetSize()
        if w and h and w > 0 and h > 0 then
            local left = parentWidget:GetLeft()
            local top = parentWidget:GetTop()
            local canvasLeft = canvas:GetLeft()
            local canvasTop = canvas:GetTop()
            if left and top and canvasLeft and canvasTop then
                return (left - canvasLeft) + w * 0.5, -((canvasTop - top) + h * 0.5)
            end
        end
    end
    local vc = Diar.plannerFrame and Diar.plannerFrame.sceneViewContext
    local PV = Diar.PlannerView
    if not parentItem then
        if PV then
            local px, py = PV.Coord(vc, cw * 0.5, ch * 0.5)
            return px, -py
        end
        return cw * 0.5, -(ch * 0.5)
    end
    local xp = parentItem.currentX
    if xp == nil and type(parentItem.x) == "number" then xp = parentItem.x / 100 end
    xp = xp or 0
    local yp = parentItem.currentY
    if yp == nil and type(parentItem.y) == "number" then yp = parentItem.y / 100 end
    yp = yp or 0
    local iw = (type(parentItem.w) == "number" and cw * parentItem.w / 100) or 24
    local ih = (type(parentItem.h) == "number" and ch * parentItem.h / 100) or 24
    local centerWx = cw * xp + iw * 0.5
    local centerWy = ch * yp + ih * 0.5
    if PV then
        local px, py = PV.Coord(vc, centerWx, centerWy)
        return px, -py
    end
    return centerWx, -centerWy
end

function Diar.PlannerFrontal.Apply(pf, scene, canvas, cw, ch, t, h)
    if not pf.sceneAnimations or not pf.frontalBeamWidgets then return end
    for ai, anim in ipairs(pf.sceneAnimations) do
        if IsFrontalAnim(anim) then
            local beam = pf.frontalBeamWidgets[ai]
            local line = beam and beam.line
            if beam and line then
                local startT = (anim.startTime and anim.startTime / 1000) or 0
                local dur = (anim.duration and anim.duration / 1000) or 1

                if t < startT then
                    beam:Hide()
                    line:Hide()
                else
                    local parentIdx = ResolveFrontalParentIndex(anim, scene)
                    local parentItem = parentIdx and scene.items[parentIdx] or nil
                    local parentWidget = parentItem and parentItem.widget

                    local startA = (type(anim.startAngle) == "number") and anim.startAngle or 0
                    local endA = (type(anim.endAngle) == "number") and anim.endAngle or startA
                    local frontalType = anim.frontalAnimationType or "sweep"
                    local baseAlpha = (type(anim.frontalOpacity) == "number") and anim.frontalOpacity or 0.55

                    local facing
                    local alpha = baseAlpha
                    if t >= startT + dur then
                        facing = (frontalType == "pulse") and startA or endA
                    else
                        local animProgress = (t - startT) / dur
                        if frontalType == "pulse" then
                            local wobbleDeg = (type(anim.pulseWobbleDeg) == "number") and anim.pulseWobbleDeg or 10
                            facing = startA + math.sin(animProgress * math.pi * 2 * 5) * wobbleDeg
                            local opacityPulse = 0.6 + 0.4 * (0.5 + 0.5 * math.sin(animProgress * math.pi * 2 * 6))
                            alpha = math.min(1, baseAlpha * opacityPulse)
                        else
                            facing = startA + (endA - startA) * animProgress
                        end
                    end

                    local vc = Diar.plannerFrame and Diar.plannerFrame.sceneViewContext
                    local PV = Diar.PlannerView
                    local zoom = (PV and vc and PV.Scale(vc, 1)) or 1
                    local pivotX, pivotY = GetIconCenterOnCanvas(parentItem, parentWidget, canvas, cw, ch)
                    local rad = math.rad(facing)
                    local dirX = math.sin(rad)
                    local dirY = math.cos(rad)
                    local len = (beam.beamLenPx or 48) * zoom
                    local endX = pivotX + dirX * len
                    local endY = pivotY + dirY * len

                    if beam:GetParent() ~= canvas then beam:SetParent(canvas) end
                    beam:SetAllPoints(canvas)
                    beam:SetFrameLevel(canvas:GetFrameLevel() + 1)
                    beam:Show()

                    line:SetThickness((beam.beamWidthPx or 8) * zoom)
                    line:SetColorTexture(beam.fillR or 0.96, beam.fillG or 0.42, beam.fillB or 0.42, alpha)
                    line:SetStartPoint("TOPLEFT", canvas, pivotX, pivotY)
                    line:SetEndPoint("TOPLEFT", canvas, endX, endY)
                    line:Show()
                end
            end
        end
    end
end
