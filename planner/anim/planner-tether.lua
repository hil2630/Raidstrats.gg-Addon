-- Raidstrats.gg Planner - Tether animations (pullIn/pushOut). No tether lines drawn.
local addonName = ...
local AceAddon = LibStub("AceAddon-3.0")
local Addon =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)
if not Addon then return end
local Diar = Addon
Diar.PlannerTether = Diar.PlannerTether or {}

local function parseTargetPercent(tx, ty)
    tx = tonumber(tx)
    ty = tonumber(ty)
    if not tx or not ty then return nil, nil end
    local x = (tx >= 0 and tx <= 1) and tx or (tx / 100)
    local y = (ty >= 0 and ty <= 1) and ty or (ty / 100)
    return x, y
end

function Diar.PlannerTether.Apply(pf, scene, canvas, cw, ch, t, h)
    if not pf.sceneAnimations then return end
    for _, anim in ipairs(pf.sceneAnimations) do
        if anim.isTetherAnimation then
            local followerIdx = h.ResolveAnimItemIndex(anim, scene, nil)
            local parentItemIndex = tonumber(anim.parentItemIndex)
            local mainIdx = (parentItemIndex and parentItemIndex >= 0) and (math.floor(parentItemIndex + 0.0001) + 1) or nil
            local followerItem = scene.items[followerIdx]
            local mainItem = mainIdx and scene.items[mainIdx] or nil
            if not mainItem and followerItem and #scene.items > 1 then
                local fx = (followerItem.widget and followerItem.widget.baseX) or ((type(followerItem.x) == "number" and followerItem.x or 0) / 100)
                local fy = (followerItem.widget and followerItem.widget.baseY) or ((type(followerItem.y) == "number" and followerItem.y or 0) / 100)
                local bestIdx, bestDist = nil, 1e10
                for i, it in ipairs(scene.items) do
                    if it ~= followerItem and it.widget and not it.widget.__suppressed then
                        local ix = (it.widget and it.widget.baseX) or ((type(it.x) == "number" and it.x or 0) / 100)
                        local iy = (it.widget and it.widget.baseY) or ((type(it.y) == "number" and it.y or 0) / 100)
                        local dx = ix - fx
                        local dy = iy - fy
                        local d = dx * dx + dy * dy
                        if d < bestDist then bestDist = d; bestIdx = i end
                    end
                end
                if bestIdx then mainItem = scene.items[bestIdx] end
            end
            local fw = followerItem and followerItem.widget
            if followerItem and mainItem and fw and not fw.__suppressed then
                local startT = (anim.startTime and anim.startTime / 1000) or 0
                local dur = (anim.duration and anim.duration / 1000) or 1
                local active, progress = h.GetAnimTimeState(t, startT, dur, false)

                local initX = (followerItem.widget and followerItem.widget.baseX) or ((type(followerItem.x) == "number" and followerItem.x or 0) / 100)
                local initY = (followerItem.widget and followerItem.widget.baseY) or ((type(followerItem.y) == "number" and followerItem.y or 0) / 100)

                local mainX = (mainItem.widget and mainItem.widget.baseX) or mainItem.currentX or ((type(mainItem.x) == "number" and mainItem.x or 0) / 100)
                local mainY = (mainItem.widget and mainItem.widget.baseY) or mainItem.currentY or ((type(mainItem.y) == "number" and mainItem.y or 0) / 100)

                local targX, targY = parseTargetPercent(anim.targetPosition and (anim.targetPosition.x or anim.targetPosition.left), anim.targetPosition and (anim.targetPosition.y or anim.targetPosition.top))
                local tetherType = (anim.tetherType and tostring(anim.tetherType):lower()) or "pullin"
                if not targX or not targY then
                    if tetherType == "pushout" then
                        local dx = initX - mainX
                        local dy = initY - mainY
                        local len = math.sqrt(dx * dx + dy * dy)
                        if len > 0.0001 then
                            local dist = (tonumber(anim.tetherDistance) or 200) / (cw or 1115)
                            local pct = (tonumber(anim.tetherDistancePercent) or 100) / 100
                            local ux = dx / len
                            local uy = dy / len
                            targX = mainX + ux * dist * pct
                            targY = mainY + uy * dist * pct
                        else
                            targX, targY = mainX, mainY
                        end
                    else
                        targX, targY = mainX, mainY
                    end
                end

                local pct = active and progress or (t >= startT + dur and 1 or 0)
                local currX = initX + (targX - initX) * pct
                local currY = initY + (targY - initY) * pct
                h.SetItemPositionPercent(followerItem, canvas, cw, ch, currX, currY)
            end
        end
    end
end
