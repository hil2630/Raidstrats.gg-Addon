-- Raidstrats.gg Planner - Path (move) animations. One file per animation type.
local addonName = ...
local AceAddon = LibStub("AceAddon-3.0")
local Addon =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)
if not Addon then return end
local Diar = Addon
Diar.PlannerPath = Diar.PlannerPath or {}

function Diar.PlannerPath.Apply(pf, scene, canvas, cw, ch, t, h)
    if not pf.sceneAnimations then return end
    -- Reuse table to avoid allocating every frame (memory leak)
    local pathPosByItem = pf.pathPosByItemRecycle
    if not pathPosByItem then
        pathPosByItem = {}
        pf.pathPosByItemRecycle = pathPosByItem
    else
        for k in pairs(pathPosByItem) do pathPosByItem[k] = nil end
    end
    for _, anim in ipairs(pf.sceneAnimations) do
        local startT = (anim.startTime and anim.startTime / 1000) or 0
        local dur = (anim.duration and anim.duration / 1000) or 1
        if anim.path and #anim.path >= 2 then
            local path = anim.__normalizedPath
            if not path then
                path = h.NormalizePath(anim.path)
                anim.__normalizedPath = path
                anim.__pathLengths = path and h.BuildPathLengths(path) or nil
            end
            local idx = h.ResolveAnimItemIndex(anim, scene, path)
            if path and #path >= 2 and scene.items[idx] and scene.items[idx].widget then
                local active, progress = h.GetAnimTimeState(t, startT, dur, false)
                local ended = t >= startT + dur
                local p = active and progress or (ended and 1 or 0)
                local xp, yp = h.GetPathPositionAtProgress(path, anim.__pathLengths, p)
                local xp01, yp01 = xp / 100, yp / 100
                local endTime = startT + dur
                local prev = pathPosByItem[idx]
                local use
                if not prev then
                    use = true
                elseif active then
                    use = not prev.active or (prev.active and startT > prev.startT)
                else
                    use = (not prev.active and ended and prev.endTime and endTime > prev.endTime)
                end
                if use then
                    pathPosByItem[idx] = { x = xp01, y = yp01, startT = startT, endTime = endTime, active = active }
                end
            end
        end
    end
    for idx, pos in pairs(pathPosByItem) do
        local item = scene.items[idx]
        if item and item.widget and not item.widget.__suppressed then
            h.SetItemPositionPercent(item, canvas, cw, ch, pos.x, pos.y)
        end
    end
end
