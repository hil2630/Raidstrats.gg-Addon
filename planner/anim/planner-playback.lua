-- Raidstrats.gg Planner - animation playback controls (play/pause/stop)
local addonName = ...
local AceAddon = LibStub("AceAddon-3.0")
local Addon =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)
if not Addon then return end
local Diar = Addon
local PUI = Diar.PlannerUI
local SetPlannerBtnText = PUI.SetPlannerBtnText
local UI = PUI.UI
local RIGHT_COL_GAP = PUI.RIGHT_COL_GAP

local function SceneHasAnimations(pf)
    return pf and pf.sceneAnimations and #pf.sceneAnimations > 0
end

local function SetPlannerBtnEnabled(btn, enabled)
    if not btn then return end
    if enabled then
        btn:Enable()
        btn:SetAlpha(1)
        if btn.label then btn.label:SetTextColor(0.92, 0.92, 0.92) end
    else
        btn:Disable()
        btn:SetAlpha(0.5)
        if btn.label then btn.label:SetTextColor(0.42, 0.42, 0.42) end
        btn.selected = false
        if btn.SetBackdropColor then btn:SetBackdropColor(unpack(UI.ROW)) end
    end
end

function Diar:UpdatePlannerPlayhead()
    local pf = self.plannerFrame
    if not pf or not pf.timeline or not pf.timeline:IsShown() then return end
    if not SceneHasAnimations(pf) then return end
    local totalDur = Diar.GetSceneDuration(pf.sceneAnimations)
    if totalDur <= 0 then totalDur = 10 end
    local t
    if pf.animPaused and type(pf.pausedTime) == "number" then
        t = pf.pausedTime
    else
        t = pf.animStart and (GetTime() - pf.animStart) or 0
    end
    t = math.min(totalDur, math.max(0, t))
    local pct = math.min(1, math.max(0, t / totalDur))
    local track = pf.timelineBg or pf.timeline
    local tw = track:GetWidth()
    if tw <= 0 then tw = pf.timeline:GetWidth() - 12 end
    pf.playhead:SetPoint("LEFT", track, "LEFT", pct * tw, 0)
    pf.timelineLabel:SetText(string.format("%.1fs / %.1fs", t, totalDur))
end

function Diar:PlannerOnUpdate()
    local pf = self.plannerFrame
    local data = self.plannerData
    if not pf or not data or not data.scenes or not pf.selectedSceneIndex then return end
    local scene = data.scenes[pf.selectedSceneIndex]
    if not scene or not scene.items then return end
    local canvas = pf.canvas
    local cw, ch = Diar.GetPlannerRenderCanvasSize(pf, canvas)
    local root = Diar.GetPlannerItemRoot(pf, canvas)
    local t
    if type(pf.animStart) == "number" then
        t = GetTime() - pf.animStart
    elseif pf.animPaused and type(pf.pausedTime) == "number" then
        t = pf.pausedTime
    else
        -- Safety guard for transient scrub/play state races.
        pf:SetScript("OnUpdate", nil)
        pf.animPlaying = false
        return
    end
    local totalDur = Diar.GetSceneDuration(pf.sceneAnimations)
    if totalDur <= 0 or t >= totalDur then
        -- Animation ended: apply final state once, then stop without resetting scene
        if totalDur > 0 then
            Diar.ApplyAnimPosition(pf, scene, root, cw, ch, totalDur)
        end
        self:StopPlannerAnimation(true)
        return
    end
    Diar.ApplyAnimPosition(pf, scene, root, cw, ch, t)
    self:UpdatePlannerPlayhead()
end

function Diar:UpdatePlannerControlButtons()
    local pf = self.plannerFrame
    if not pf or not pf.playPauseBtn then return end

    local hasAnims = SceneHasAnimations(pf)
    if not hasAnims and pf.animPlaying then
        pf:SetScript("OnUpdate", nil)
        pf.animPlaying = false
        pf.animPaused = false
        pf.pausedTime = nil
        pf.animStart = nil
    end

    SetPlannerBtnText(pf.playPauseBtn, pf.animPlaying and "Pause" or "Play")
    SetPlannerBtnEnabled(pf.playPauseBtn, hasAnims)
    SetPlannerBtnEnabled(pf.stopBtn, hasAnims)

    if pf.timeline then
        if hasAnims and not pf.compactMode then
            pf.timeline:Show()
        else
            pf.timeline:Hide()
        end
    end

    if pf.savedPlansPanel and pf.patreonPanel and not pf.compactMode then
        pf.savedPlansPanel:ClearAllPoints()
        pf.savedPlansPanel:SetPoint("TOPLEFT", pf.patreonPanel, "BOTTOMLEFT", 0, -RIGHT_COL_GAP)
        local bottomAnchor = (hasAnims and pf.timeline and pf.timeline:IsShown()) and pf.timeline or pf.controls
        if bottomAnchor then
            pf.savedPlansPanel:SetPoint("BOTTOMLEFT", bottomAnchor, "BOTTOMRIGHT", 12, 0)
        end
    end
end

function Diar:PlayPlannerAnimation()
    local pf = self.plannerFrame
    if not pf or not SceneHasAnimations(pf) then return end
    pf.animPlaying = true
    if pf.animPaused and type(pf.pausedTime) == "number" then
        pf.animStart = GetTime() - pf.pausedTime
        pf.animPaused = false
        pf.pausedTime = nil
    else
        pf.animStart = GetTime()
    end
    self:UpdatePlannerControlButtons()
    pf:SetScript("OnUpdate", pf.plannerOnUpdateHandler)
end

function Diar:PausePlannerAnimation()
    local pf = self.plannerFrame
    if not pf or not pf.animPlaying then return end
    local totalDur = Diar.GetSceneDuration(pf.sceneAnimations)
    if totalDur and totalDur > 0 then
        local t = GetTime() - pf.animStart
        pf.pausedTime = math.min(totalDur, math.max(0, t))
    else
        pf.pausedTime = 0
    end
    pf:SetScript("OnUpdate", nil)
    pf.animPlaying = false
    pf.animPaused = true
    self:UpdatePlannerControlButtons()
end

-- keepEndState: if true, do not reset scene (used when animation ends naturally)
function Diar:StopPlannerAnimation(keepEndState)
    local pf = self.plannerFrame
    if not pf then return end
    pf:SetScript("OnUpdate", nil)
    pf.animPlaying = false
    pf.animPaused = false
    pf.pausedTime = nil
    pf.animStart = nil
    self:UpdatePlannerControlButtons()
    if not keepEndState then
        self:RefreshPlannerScene()
    else
        -- Update playhead to end so UI shows finished state
        local totalDur = Diar.GetSceneDuration(pf.sceneAnimations)
        if totalDur and totalDur > 0 then
            pf.animStart = GetTime() - totalDur
            self:UpdatePlannerPlayhead()
        end
        pf.animStart = nil
    end
end

