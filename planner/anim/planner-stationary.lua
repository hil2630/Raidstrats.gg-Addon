-- Raidstrats.gg Planner - Stationary animations (pulse, scaleUp, scaleDown, bounce, rotate, fade, etc.).
local addonName = ...
local AceAddon = LibStub("AceAddon-3.0")
local Addon =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)
if not Addon then return end
local Diar = Addon
Diar.PlannerStationary = Diar.PlannerStationary or {}

function Diar.PlannerStationary.Apply(pf, scene, canvas, cw, ch, t, h)
    if not pf.sceneAnimations then return end
    local PV = Diar.PlannerView
    local vc = PV and PV.GetContext(pf)
    for _, anim in ipairs(pf.sceneAnimations) do
        if anim.isStationaryAnimation then
            local idx = h.ResolveAnimItemIndex(anim, scene, nil)
            local item = scene.items[idx]
            local w = item and item.widget
            if w and not w.__suppressed then
                local startT = (anim.startTime and anim.startTime / 1000) or 0
                local dur = (anim.duration and anim.duration / 1000) or 1
                local active, progress, ended = h.GetAnimTimeState(t, startT, dur, anim.loop == true)
                local intensity = (type(anim.intensity) == "number" and anim.intensity or 1.2)
                local kind = anim.type or "pulse"

                local function applyScaleFromCenter(s)
                    local basePixelW = (w.basePixelW and w.basePixelW > 0) and w.basePixelW or w:GetWidth()
                    local basePixelH = (w.basePixelH and w.basePixelH > 0) and w.basePixelH or w:GetHeight()
                    if basePixelW <= 0 then basePixelW = PV.Scale(vc, cw * ((type(item.w) == "number" and item.w or 4) / 100)) end
                    if basePixelH <= 0 then basePixelH = PV.Scale(vc, ch * ((type(item.h) == "number" and item.h or 4) / 100)) end
                    -- basePixelW/H already include zoom; convert back to world fraction for the center.
                    local zoom = (vc and vc.zoom) or 1
                    local iw = (basePixelW / zoom) / cw
                    local ih = (basePixelH / zoom) / ch
                    local baseX = (item.widget and item.widget.baseX) or ((type(item.x) == "number" and item.x or 0) / 100)
                    local baseY = (item.widget and item.widget.baseY) or ((type(item.y) == "number" and item.y or 0) / 100)
                    local leftX = (type(item.currentX) == "number") and item.currentX or baseX
                    local leftY = (type(item.currentY) == "number") and item.currentY or baseY
                    local centerX = leftX + iw * 0.5
                    local centerY = leftY + ih * 0.5
                    local px, py = PV.Coord(vc, cw * centerX, ch * centerY)
                    w:ClearAllPoints()
                    w:SetPoint("CENTER", canvas, "TOPLEFT", px, -py)
                    w:SetSize(basePixelW * s, basePixelH * s)
                end

                if active then
                    if kind == "pulse" then
                        local s = 1 + (math.sin(progress * math.pi * 2) * (intensity - 1) * 0.5)
                        applyScaleFromCenter(s)
                    elseif kind == "scaleUp" then
                        local s = 1 + (progress * (intensity - 1))
                        applyScaleFromCenter(s)
                    elseif kind == "scaleDown" then
                        local s = intensity - (progress * (intensity - 1))
                        applyScaleFromCenter(s)
                    elseif kind == "rotate" then
                        local dir = (anim.clockwise == false) and -1 or 1
                        local deg = progress * 360 * intensity * dir
                        if w.tex then w.tex:SetRotation(math.rad(deg)) end
                    elseif kind == "fade" then
                        local alpha = h.Clamp(math.abs(math.sin(progress * math.pi * 2)) * intensity, 0.01, 1)
                        w:SetAlpha(alpha)
                    elseif kind == "fadeIn" then
                        w:SetAlpha(h.Clamp(progress * intensity, 0.01, 1))
                    elseif kind == "fadeOut" then
                        w:SetAlpha(h.Clamp((1 - progress) * intensity, 0.01, 1))
                    elseif kind == "bounce" then
                        local s = 1 + (math.abs(math.sin(progress * math.pi * 4)) * (intensity - 1) * 0.3)
                        applyScaleFromCenter(s)
                    end
                elseif ended and not anim.loop then
                    if kind == "fadeOut" and anim.stayVisibleAfterEnd ~= false then
                        w:SetAlpha(0.01)
                    elseif kind == "fadeIn" and anim.stayVisibleAfterEnd ~= false then
                        w:SetAlpha(1)
                    else
                        w:SetAlpha(1)
                        if w.tex then w.tex:SetRotation(0) end
                        local baseX = (item.widget and item.widget.baseX) or ((type(item.x) == "number" and item.x or 0) / 100)
                        local baseY = (item.widget and item.widget.baseY) or ((type(item.y) == "number" and item.y or 0) / 100)
                        local bw = (w.basePixelW and w.basePixelW > 0) and w.basePixelW or w:GetWidth()
                        local bh = (w.basePixelH and w.basePixelH > 0) and w.basePixelH or w:GetHeight()
                        local px, py = PV.PctToCanvas(vc, cw, ch, baseX, baseY)
                        w:ClearAllPoints()
                        w:SetPoint("TOPLEFT", canvas, "TOPLEFT", px, -py)
                        w:SetSize(bw, bh)
                        item.currentX = baseX
                        item.currentY = baseY
                    end
                end
            end
        end
    end
end
