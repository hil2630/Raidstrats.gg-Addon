-- Raidstrats.gg Planner - scene engine (viewport, render, viewer, animation)
local addonName = ...
local AceAddon = LibStub("AceAddon-3.0")
local Addon =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)
if not Addon then
    error(("Raidstratsgg planner: could not resolve addon instance (addonName=%s)"):format(tostring(addonName)))
end
local Diar = Addon
local SetBackdrop = Diar.SetBackdrop
local CreateAnimatedCheckbox = Diar.CreateAnimatedCheckbox
local CreateButton = Diar.CreateButton
local CreateInput = Diar.CreateInput
local SkinScrollBar = Diar.SkinScrollBar

local PUI = Diar.PlannerUI

if not StaticPopupDialogs["RAIDSTRATSGG_DELETE_SCENE"] then
    StaticPopupDialogs["RAIDSTRATSGG_DELETE_SCENE"] = {
        text = "Delete scene %d?",
        button1 = _G.YES or "Yes",
        button2 = _G.NO or "No",
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        OnAccept = function(self)
            local sceneIndex = self.data
            if sceneIndex and Diar and Diar.DeletePlannerScene then
                Diar:DeletePlannerScene(sceneIndex)
            end
        end,
    }
end

function Diar:HideSceneTabContextDismissOverlay()
    local o = self._sceneTabCtxDismiss
    if not o then return end
    o:Hide()
    o:SetScript("OnClick", nil)
    o:SetScript("OnMouseUp", nil)
end

function Diar:HideSceneTabContextMenu()
    self:HideSceneTabContextDismissOverlay()
    local menu = self._sceneTabCtxMenu
    if menu then
        menu:Hide()
    end
end

function Diar:ShowSceneTabContextMenu(anchor, sceneIndex)
    sceneIndex = tonumber(sceneIndex)
    if not sceneIndex or sceneIndex <= 1 then return end
    local data = self.plannerData
    if not data or not data.scenes or not data.scenes[sceneIndex] then return end

    self:HideSceneTabContextMenu()

    local menu = self._sceneTabCtxMenu
    if not menu then
        menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        menu:SetSize(132, 40)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(540)
        menu:EnableMouse(true)
        if SetBackdrop then SetBackdrop(menu, UI.PANEL, UI.BORDER, 1) end

        local delBtn = CreateFrame("Button", nil, menu, "BackdropTemplate")
        delBtn:SetPoint("TOPLEFT", menu, "TOPLEFT", 6, -6)
        delBtn:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -6, 6)
        if SetBackdrop then SetBackdrop(delBtn, UI.ROW, UI.BORDER, 1) end
        local lbl = delBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("CENTER")
        lbl:SetText("Delete")
        lbl:SetTextColor(0.92, 0.92, 0.92)
        delBtn:SetScript("OnEnter", function(s)
            s:SetBackdropColor(unpack(UI.ROW_HOV))
            lbl:SetTextColor(1, 1, 1)
        end)
        delBtn:SetScript("OnLeave", function(s)
            s:SetBackdropColor(unpack(UI.ROW))
            lbl:SetTextColor(0.92, 0.92, 0.92)
        end)
        delBtn:SetScript("OnClick", function()
            Diar:HideSceneTabContextMenu()
            local idx = tonumber(menu and menu.sceneIndex)
            if not idx then return end
            StaticPopup_Show("RAIDSTRATSGG_DELETE_SCENE", idx, nil, idx)
        end)

        menu:SetScript("OnHide", function()
            Diar:HideSceneTabContextDismissOverlay()
        end)
        self._sceneTabCtxMenu = menu
    end

    menu.sceneIndex = sceneIndex
    menu:ClearAllPoints()
    if anchor then
        menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    else
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    end
    menu:Show()
    if menu.Raise then menu:Raise() end

    if not self._sceneTabCtxDismiss then
        local o = CreateFrame("Button", "RaidstratsSceneTabCtxDismiss", UIParent)
        o:SetAllPoints(UIParent)
        o:SetFrameStrata("FULLSCREEN_DIALOG")
        o:EnableMouse(true)
        o:SetAlpha(0.001)
        self._sceneTabCtxDismiss = o
    end
    local dismiss = self._sceneTabCtxDismiss
    dismiss:SetFrameLevel(math.max(0, (menu:GetFrameLevel() or 0) - 1))
    dismiss:SetScript("OnClick", nil)
    dismiss:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" or button == "RightButton" then
            Diar:HideSceneTabContextMenu()
        end
    end)
    dismiss:Show()
end

function Diar:DeletePlannerScene(sceneIndex)
    sceneIndex = tonumber(sceneIndex)
    if not sceneIndex then return false end
    if sceneIndex <= 1 then
        print("|cffff6666[Raidstrats.gg]|r Scene 1 cannot be deleted.")
        return false
    end

    local pf = self.plannerFrame
    local data = self.plannerData
    if not pf or not data or not data.scenes or not data.scenes[sceneIndex] then
        return false
    end
    local scenes = data.scenes
    if #scenes <= 1 then
        print("|cffff6666[Raidstrats.gg]|r Scene 1 cannot be deleted.")
        return false
    end

    local currentIdx = pf.selectedSceneIndex or 1
    table.remove(scenes, sceneIndex)
    for i, scene in ipairs(scenes) do
        local nm = tostring(scene.name or "")
        if nm == "" or nm:match("^%d+$") or nm:match("^Scene%s+%d+$") then
            scene.name = tostring(i)
        end
    end

    local nextIdx = currentIdx
    if nextIdx > #scenes then nextIdx = #scenes end
    if currentIdx > sceneIndex then
        nextIdx = currentIdx - 1
    elseif currentIdx == sceneIndex then
        nextIdx = math.max(1, math.min(sceneIndex, #scenes))
    end

    if self.PersistCurrentPlanToSaved then
        self:PersistCurrentPlanToSaved()
    end
    if self.ShowPlannerViewer then
        self:ShowPlannerViewer({ reloadOnly = true })
    end
    pf = self.plannerFrame
    if pf then
        pf.selectedSceneIndex = nextIdx
        pf.__viewerViewportSceneIdx = nil
    end
    if self.StopPlannerAnimation then self:StopPlannerAnimation() end
    if self.UpdateSceneTabHighlight then self:UpdateSceneTabHighlight() end
    if self.RefreshPlannerScene then self:RefreshPlannerScene() end
    if self.OnPlannerSceneChanged then self:OnPlannerSceneChanged() end
    return true
end

function Diar:SelectPlannerScene(sceneIndex)
    local pf = self.plannerFrame
    local data = self.plannerData
    if not pf or not data or not data.scenes then return false end
    local idx = tonumber(sceneIndex)
    if not idx then return false end
    idx = math.max(1, math.min(#data.scenes, math.floor(idx + 0.0001)))
    if idx == (pf.selectedSceneIndex or 1) then
        if self.UpdateCompactSceneArrowButtons then
            self:UpdateCompactSceneArrowButtons(pf)
        end
        return false
    end
    pf.selectedSceneIndex = idx
    pf.__viewerViewportSceneIdx = nil
    if not pf.nsrtSceneActive then
        self:ApplyNsrtAssignmentForPlannerView(idx)
    else
        self.activeGroup = nil
    end
    self:StopPlannerAnimation()
    self:UpdateSceneTabHighlight()
    self:RefreshPlannerScene()
    if self.OnPlannerSceneChanged then self:OnPlannerSceneChanged() end
    if self.UpdateCompactSceneArrowButtons then
        self:UpdateCompactSceneArrowButtons(pf)
    end
    return true
end

function Diar:HasSavedCompactPosition()
    local s = self:GetPlannerSettings()
    local pos = s.nsrtCompactPos or s.compactPos
    return pos and type(pos.point) == "string"
end

function Diar:HasSavedExpandedPosition()
    local pos = self:GetPlannerSettings().expandedPos
    return pos and type(pos.point) == "string"
end

function Diar:SavePlannerFramePosition(pf)
    if not pf or pf.compactPreviewActive then return end
    local point, _, relPoint, x, y = pf:GetPoint(1)
    if not point then return end
    if pf.compactMode and pf.__skipCompactSaveOnce then
        pf.__skipCompactSaveOnce = nil
        return
    end
    local s = self:GetPlannerSettings()
    local pos = {
        point = point,
        relPoint = relPoint or point,
        x = x or 0,
        y = y or 0,
    }
    if pf.compactMode then
        if pf.nsrtSceneActive then
            s.nsrtCompactPos = pos
            if pf.compactCanvasScale then
                s.nsrtCompactScale = pf.compactCanvasScale
            end
        else
            s.compactPos = pos
            if pf.compactCanvasScale then
                s.compactScale = pf.compactCanvasScale
            end
        end
    else
        s.expandedPos = pos
    end
end

function Diar:ApplyPlannerFramePosition(pf)
    if not pf then return end
    local s = self:GetPlannerSettings()
    local pos
    if pf.compactMode then
        if pf.nsrtSceneActive then
            pos = s.nsrtCompactPos or s.compactPos
        else
            pos = s.compactPos
        end
    else
        pos = s.expandedPos
    end
    if not pos or not pos.point then return end
    pf:ClearAllPoints()
    pf:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
end

function Diar:SavePlannerCompactLayoutState(pf)
    if not pf or not pf.compactMode then return end
    self:SavePlannerFramePosition(pf)
end

function Diar:ApplyPlannerCompactPosition(pf)
    if not pf then return end
    local s = self:GetPlannerSettings()
    local pos = s.nsrtCompactPos or s.compactPos
    if not pos or not pos.point then return end
    pf:ClearAllPoints()
    pf:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
end

function Diar:SavePlannerNsrtCompactLayoutState(pf)
    if not pf then return end
    local point, _, relPoint, x, y = pf:GetPoint(1)
    if not point then return end
    local s = self:GetPlannerSettings()
    s.nsrtCompactPos = {
        point = point,
        relPoint = relPoint or point,
        x = x or 0,
        y = y or 0,
    }
    if pf.compactCanvasScale then
        s.nsrtCompactScale = pf.compactCanvasScale
    end
end

function Diar:ShowCompactPreviewChrome(pf, show)
    if not pf then return end
    if not pf.compactPreviewBar then
        local bar = CreateFrame("Frame", nil, pf, "BackdropTemplate")
        bar:SetHeight(34)
        bar:SetFrameStrata("DIALOG")
        if SetBackdrop then SetBackdrop(bar, UI.TOOLBAR, UI.BORDER, 1) end
        local lbl = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", bar, "LEFT", 10, 0)
        lbl:SetWidth(220)
        lbl:SetJustifyH("LEFT")
        lbl:SetText("Drag to set NSRT compact position")
        lbl:SetTextColor(0.85, 0.88, 0.92)
        bar.label = lbl
        local saveBtn = CreatePlannerIconBtn(bar, "Save", 64, 24)
        saveBtn:SetPoint("RIGHT", bar, "RIGHT", -74, 0)
        saveBtn:SetScript("OnClick", function()
            Diar:EndCompactPositionPreview(true)
        end)
        local cancelBtn = CreatePlannerIconBtn(bar, "Cancel", 64, 24)
        cancelBtn:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
        cancelBtn:SetScript("OnClick", function()
            Diar:EndCompactPositionPreview(false)
        end)
        pf.compactPreviewBar = bar
    end
    local bar = pf.compactPreviewBar
    if show then
        bar:ClearAllPoints()
        bar:SetPoint("BOTTOMLEFT", pf, "BOTTOMLEFT", 0, 0)
        bar:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", 0, 0)
        bar:SetFrameLevel(pf:GetFrameLevel() + 40)
        bar:Show()
        if pf.closeBtn then pf.closeBtn:Hide() end
        if pf.modeToggleBtn then pf.modeToggleBtn:Hide() end
    else
        bar:Hide()
    end
end

function Diar:StartCompactPositionPreview()
    if self.plannerSettingsDialog and self.plannerSettingsDialog:IsShown() then
        self.plannerSettingsDialog:Hide()
    end
    if not self.plannerData or not self.plannerData.scenes or #self.plannerData.scenes == 0 then
        print("|cffff6666[Raidstrats.gg]|r Load a plan first, then preview the compact position.")
        return
    end
    self:ShowPlannerViewer({ reloadOnly = self.plannerFrame and self.plannerFrame:IsShown() })
    local pf = self.plannerFrame
    if not pf then return end

    local point, _, relPoint, x, y = pf:GetPoint(1)
    pf.__previewRestorePos = point and {
        point = point, relPoint = relPoint or point, x = x or 0, y = y or 0,
    } or nil
    pf.__previewWasExpanded = not pf.compactMode
    pf.compactPreviewActive = true

    if not pf.compactMode then
        self:SavePlannerFramePosition(pf)
        self:SetPlannerCompactMode(true)
    end
    local s = self:GetPlannerSettings()
    pf.compactCanvasScale = tonumber(s.nsrtCompactScale) or tonumber(s.compactScale) or COMPACT_SCALE
    if self.ApplyPlannerCompactLayout then
        self.ApplyPlannerCompactLayout(pf)
    end
    self:ApplyPlannerCompactPosition(pf)
    self:RefreshPlannerScene()

    self:ShowCompactPreviewChrome(pf, true)
    if self.UpdatePlannerModeToggleBtn then self.UpdatePlannerModeToggleBtn(pf) end
    pf:Show()
end

function Diar:EndCompactPositionPreview(save)
    local pf = self.plannerFrame
    if not pf or not pf.compactPreviewActive then return end
    pf.compactPreviewActive = nil
    self:ShowCompactPreviewChrome(pf, false)
    if self.UpdatePlannerModeToggleBtn then self.UpdatePlannerModeToggleBtn(pf) end

    local wasExpanded = pf.__previewWasExpanded
    pf.__previewWasExpanded = nil
    pf.__previewRestorePos = nil

    if save then
        self:SavePlannerNsrtCompactLayoutState(pf)
        if pf.compactMode and self.SetPlannerCompactMode then
            pf.nsrtSceneActive = nil
            pf.__skipCompactSaveOnce = true
            self:SetPlannerCompactMode(false)
        end
        local reopen = self.ShowPlannerSettingsDialog
        if reopen then
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if Diar.ShowPlannerSettingsDialog then Diar:ShowPlannerSettingsDialog() end
                end)
            else
                self:ShowPlannerSettingsDialog()
            end
        end
    else
        if wasExpanded then
            if pf.compactMode and self.SetPlannerCompactMode then
                pf.nsrtSceneActive = nil
                pf.__skipCompactSaveOnce = true
                self:SetPlannerCompactMode(false)
            end
        else
            self:ApplyPlannerFramePosition(pf)
        end
    end
end

function Diar:PositionPlannerSettingsBtn(pf)
    self:PositionPlannerControlsBar(pf)
end

function Diar:IsPlannerPreviewIndexVisible()
    local pf = self.plannerFrame
    return pf and pf.previewIndexVisible == true
end

function Diar:UpdatePreviewIndexButton(pf)
    pf = pf or self.plannerFrame
    if not pf or not pf.previewIndexBtn then return end
    local on = pf.previewIndexVisible == true
    pf.previewIndexBtn.selected = on
    if on then
        pf.previewIndexBtn:SetBackdropColor(0.18, 0.38, 0.72, 1)
        pf.previewIndexBtn.label:SetTextColor(1, 1, 1)
    else
        pf.previewIndexBtn:SetBackdropColor(unpack(UI.ROW))
        pf.previewIndexBtn.label:SetTextColor(0.92, 0.92, 0.92)
    end
end

function Diar:TogglePlannerPreviewIndex()
    local pf = self.plannerFrame
    if not pf then return end
    pf.previewIndexVisible = not pf.previewIndexVisible
    self:UpdatePreviewIndexButton(pf)
    if self.RefreshPlannerScene then self:RefreshPlannerScene() end
end

function Diar:IsPlannerPreviewNamesVisible()
    local pf = self.plannerFrame
    return pf and pf.previewNamesVisible == true
end

function Diar:UpdatePreviewNamesButton(pf)
    pf = pf or self.plannerFrame
    local btn = pf and pf.previewNamesBtn
    if not btn then return end
    local on = pf.previewNamesVisible == true
    SetPlannerBtnText(btn, on and "Hide names" or "Preview names")
    btn.selected = on
    if on then
        btn:SetBackdropColor(0.18, 0.38, 0.72, 1)
        btn.label:SetTextColor(1, 1, 1)
    else
        btn:SetBackdropColor(unpack(UI.ROW))
        btn.label:SetTextColor(0.92, 0.92, 0.92)
    end
    if pf.compactMode then
        btn:Hide()
    else
        btn:Show()
    end
end

function Diar:TogglePlannerPreviewNames()
    local pf = self.plannerFrame
    if not pf then return end
    pf.previewNamesVisible = not pf.previewNamesVisible
    self:UpdatePreviewNamesButton(pf)
    if self.RefreshPlannerScene then self:RefreshPlannerScene() end
end

function Diar:EnsurePreviewNamesButton(pf)
    if not pf or not pf.canvas then return end
    local btn = pf.previewNamesBtn
    if not btn then
        -- Parent to frame (not canvas) so scene refresh doesn't recycle/hide it.
        btn = CreatePlannerIconBtn(pf, "Preview names", 104, 22)
        btn:SetScript("OnClick", function()
            Diar:TogglePlannerPreviewNames()
        end)
        pf.previewNamesBtn = btn
    end
    if btn:GetParent() ~= pf then
        btn:SetParent(pf)
    end
    btn:ClearAllPoints()
    btn:SetPoint("TOPRIGHT", pf.canvas, "TOPRIGHT", -6, -6)
    btn:SetFrameLevel((pf.canvas:GetFrameLevel() or pf:GetFrameLevel()) + 6)
    self:UpdatePreviewNamesButton(pf)
end

function Diar:EnsurePlannerControlsButtons(pf)
    if not pf or not pf.controls then return end
    if not pf.settingsBtn then
        pf.settingsBtn = CreatePlannerIconBtn(pf.controls, "Settings", 72, CONTROLS_H)
        pf.settingsBtn:SetScript("OnClick", function()
            Diar:ShowPlannerSettingsDialog()
        end)
    elseif pf.settingsBtn:GetParent() ~= pf.controls then
        pf.settingsBtn:SetParent(pf.controls)
        pf.settingsBtn:SetHeight(CONTROLS_H)
    end
    if not pf.previewIndexBtn then
        pf.previewIndexBtn = CreatePlannerIconBtn(pf.controls, "Preview index", 104, CONTROLS_H)
        pf.previewIndexBtn:SetScript("OnClick", function()
            Diar:TogglePlannerPreviewIndex()
        end)
    end
    self:UpdatePreviewIndexButton(pf)
end

function Diar:ShouldDefaultCanvasLocked()
    if not IsInGroup() then return false end
    return not UnitIsGroupLeader("player")
end

function Diar:IsPlannerCanvasLocked()
    local pf = self.plannerFrame
    if not pf or pf.compactMode or pf.nsrtSceneActive then return true end
    if pf.canvasLocked == nil then
        return self:ShouldDefaultCanvasLocked()
    end
    return pf.canvasLocked == true
end

function Diar:ResetPlannerCanvasLock()
    local pf = self.plannerFrame
    if not pf then return end
    pf.canvasLocked = nil
    self:UpdateCanvasLockButton(pf)
end

function Diar:EnsurePaletteToggleButton(pf)
    if not pf or not pf.controls or pf.paletteToggleBtn then return end
    local btn = CreatePlannerIconBtn(pf.controls, "Show palette", 96, CONTROLS_H)
    btn:SetScript("OnClick", function()
        Diar:ToggleObjectPalette()
    end)
    pf.paletteToggleBtn = btn
end

function Diar:UpdatePaletteToggleButton(pf)
    pf = pf or self.plannerFrame
    local btn = pf and pf.paletteToggleBtn
    if not btn then return end
    local on = self:IsObjectPaletteEnabled()
    SetPlannerBtnText(btn, on and "Hide palette" or "Show palette")
    btn.selected = on
    btn:Enable()
    if on then
        btn:SetBackdropColor(0.18, 0.38, 0.72, 1)
        if btn.label then btn.label:SetTextColor(1, 1, 1) end
    else
        btn:SetBackdropColor(unpack(UI.ROW))
        if btn.label then btn.label:SetTextColor(0.92, 0.92, 0.92) end
    end
end

function Diar:ToggleObjectPalette()
    local s = self:GetPlannerSettings()
    s.showObjectPalette = not self:IsObjectPaletteEnabled()
    local pf = self.plannerFrame
    if pf then
        if not pf.compactMode and self.ApplyPlannerNormalLayout then
            -- Keep canvas size stable; grow/shrink frame chrome immediately.
            self.ApplyPlannerNormalLayout(pf, false)
        elseif self.ApplyObjectPaletteLayout then
            self:ApplyObjectPaletteLayout(pf)
        end
        self:UpdatePaletteToggleButton(pf)
    end
end

function Diar:EnsureCanvasLockButton(pf)
    if not pf or not pf.controls or pf.canvasLockBtn then return end
    local btn = CreatePlannerIconBtn(pf.controls, "Unlock", 72, CONTROLS_H)
    btn:SetScript("OnClick", function()
        Diar:TogglePlannerCanvasLock()
    end)
    pf.canvasLockBtn = btn
end

function Diar:UpdateCanvasLockButton(pf)
    pf = pf or self.plannerFrame
    local btn = pf and pf.canvasLockBtn
    if not btn then return end
    local locked = self:IsPlannerCanvasLocked()
    SetPlannerBtnText(btn, locked and "Unlock" or "Lock")
    btn.selected = not locked
    if not locked then
        btn:SetBackdropColor(0.18, 0.38, 0.72, 1)
        if btn.label then btn.label:SetTextColor(1, 1, 1) end
    else
        btn:SetBackdropColor(unpack(UI.ROW))
        if btn.label then btn.label:SetTextColor(0.92, 0.92, 0.92) end
    end
    self:EnsureCanvasLockLabel(pf)
    if pf.canvasLockLabel then
        if locked and not pf.compactMode and not pf.nsrtSceneActive then
            pf.canvasLockLabel:Show()
        else
            pf.canvasLockLabel:Hide()
        end
    end
    if self.ApplyObjectPaletteLockedState then
        self:ApplyObjectPaletteLockedState(pf)
    end
end

function Diar:EnsureCanvasLockLabel(pf)
    if not pf or not pf.canvas or pf.canvasLockLabel then return end
    local lbl = pf.canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("BOTTOMLEFT", pf.canvas, "BOTTOMLEFT", 8, 6)
    lbl:SetText("Locked")
    lbl:SetTextColor(0.42, 0.45, 0.52, 0.9)
    pf.canvasLockLabel = lbl
    lbl:Hide()
end

function Diar:TogglePlannerCanvasLock()
    local pf = self.plannerFrame
    if not pf or pf.compactMode or pf.nsrtSceneActive then return end
    pf.canvasLocked = not self:IsPlannerCanvasLocked()
    self:UpdateCanvasLockButton(pf)
    if pf.canvasLocked and self.ClearPalettePlacement then
        self:ClearPalettePlacement()
    end
end

function Diar:PositionPlannerControlsBar(pf)
    if not pf or not pf.controls then return end
    self:EnsurePlannerControlsButtons(pf)
    self:EnsurePaletteToggleButton(pf)
    self:EnsureCanvasLockButton(pf)
    if pf.compactMode then
        if pf.settingsBtn then pf.settingsBtn:Hide() end
        if pf.previewIndexBtn then pf.previewIndexBtn:Hide() end
        if pf.paletteToggleBtn then pf.paletteToggleBtn:Hide() end
        if pf.canvasLockBtn then pf.canvasLockBtn:Hide() end
        if pf.previewNamesBtn then pf.previewNamesBtn:Hide() end
        return
    end
    if pf.paletteToggleBtn then
        pf.paletteToggleBtn:Show()
        pf.paletteToggleBtn:ClearAllPoints()
        pf.paletteToggleBtn:SetPoint("LEFT", pf.controls, "LEFT", 0, 0)
        pf.paletteToggleBtn:SetHeight(CONTROLS_H)
        self:UpdatePaletteToggleButton(pf)
    end
    if pf.canvasLockBtn then
        pf.canvasLockBtn:Show()
        pf.canvasLockBtn:ClearAllPoints()
        if pf.paletteToggleBtn then
            pf.canvasLockBtn:SetPoint("LEFT", pf.paletteToggleBtn, "RIGHT", 6, 0)
        else
            pf.canvasLockBtn:SetPoint("LEFT", pf.controls, "LEFT", 0, 0)
        end
        pf.canvasLockBtn:SetHeight(CONTROLS_H)
        self:UpdateCanvasLockButton(pf)
    end
    if pf.settingsBtn then
        pf.settingsBtn:Show()
        pf.settingsBtn:ClearAllPoints()
        pf.settingsBtn:SetPoint("RIGHT", pf.controls, "RIGHT", 0, 0)
        pf.settingsBtn:SetHeight(CONTROLS_H)
    end
    if pf.previewIndexBtn then
        pf.previewIndexBtn:Show()
        pf.previewIndexBtn:ClearAllPoints()
        pf.previewIndexBtn:SetPoint("RIGHT", pf.settingsBtn, "LEFT", -6, 0)
        pf.previewIndexBtn:SetHeight(CONTROLS_H)
        self:UpdatePreviewIndexButton(pf)
    end
    self:UpdatePreviewNamesButton(pf)
end

local DEBUG_PANEL_H = 146
local DEBUG_PANEL_GAP = 6

local function EnsurePlannerDebugPanel(pf)
    if not pf or pf.debugPanel then return end
    local panel = CreateFrame("Frame", nil, pf, "BackdropTemplate")
    panel:SetPoint("TOPLEFT", pf, "BOTTOMLEFT", 0, -DEBUG_PANEL_GAP)
    panel:SetPoint("TOPRIGHT", pf, "BOTTOMRIGHT", 0, -DEBUG_PANEL_GAP)
    panel:SetHeight(DEBUG_PANEL_H)
    SetBackdrop(panel, UI.TOOLBAR, UI.BORDER, 1)
    panel:Hide()
    pf.debugPanel = panel

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
    title:SetText("Planner debug output (copy/paste)")
    title:SetTextColor(0.78, 0.80, 0.84)
    panel.title = title

    local clearBtn = CreatePlannerIconBtn(panel, "Clear", 54, 18)
    clearBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -6)
    clearBtn:SetScript("OnClick", function()
        if Diar.ClearPlannerDebugLines then
            Diar:ClearPlannerDebugLines()
        end
    end)
    panel.clearBtn = clearBtn

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -28)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 8)
    SkinPlannerScroll(scroll)
    panel.scroll = scroll

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:EnableMouse(true)
    edit:SetMaxLetters(0)
    edit:SetFontObject("GameFontHighlightSmall")
    edit:SetTextInsets(4, 4, 4, 4)
    edit:SetTextColor(0.9, 0.92, 0.96, 1)
    edit:SetJustifyH("LEFT")
    edit:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            self:SetFocus()
            self:HighlightText()
        end
    end)
    edit:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnTextChanged", function(self)
        local textH = 0
        if self.GetStringHeight then
            textH = self:GetStringHeight() or 0
        elseif self.GetTextHeight then
            textH = self:GetTextHeight() or 0
        end
        local h = math.max(scroll:GetHeight(), math.ceil(textH) + 18)
        self:SetHeight(h)
        if self.__scrollToEnd then
            scroll:SetVerticalScroll(math.max(0, h - scroll:GetHeight()))
            self.__scrollToEnd = nil
        end
    end)
    scroll:SetScrollChild(edit)
    panel.edit = edit

    panel:SetScript("OnSizeChanged", function()
        local w = math.max(140, scroll:GetWidth() - 12)
        edit:SetWidth(w)
    end)
end

function Diar:UpdatePlannerDebugPanel()
    local pf = self.plannerFrame
    if not pf then return end
    EnsurePlannerDebugPanel(pf)
    local panel = pf.debugPanel
    if not panel then return end
    local enabled = self.GetPlannerSettings and self:GetPlannerSettings().debugMode == true
    local visible = enabled and pf:IsShown() and not pf.compactMode
    if not visible then
        panel:Hide()
        return
    end
    panel:Show()
    local dump = self.GetPlannerDebugDump and self:GetPlannerDebugDump() or "Planner debug unavailable."
    if panel.edit:GetText() ~= dump then
        panel.edit.__scrollToEnd = true
        panel.edit:SetText(dump)
    end
end


local PLANNER_CANVAS_W = 1115
local PLANNER_CANVAS_H = 627
local DEFAULT_EXPANDED_LOAD_SCALE = 0.60

local function GetPlannerControlsMinWidth()
    local gap = 6
    local clusterGap = 12
    -- Left: Show palette + Lock | Center: Play + Stop | Right: Preview index + Settings
    return 96 + gap + 72 + clusterGap + 110 + gap * 2 + 110 + clusterGap + 104 + gap + 72
end

local MIN_CANVAS_W = math.max(math.floor(PLANNER_CANVAS_W * 0.5), GetPlannerControlsMinWidth())
local MIN_CANVAS_H = math.floor(PLANNER_CANVAS_H * 0.5)

local function GetPlannerChromeWidth(pf)
    local leftExtra = (Diar.GetObjectPaletteExtraWidth and Diar:GetObjectPaletteExtraWidth()) or 0
    return UI_PAD + leftExtra + 12 + RIGHT_PANEL_W + UI_PAD
end

local function GetPlannerContentLeft()
    if Diar.GetPlannerContentLeft then
        return Diar:GetPlannerContentLeft()
    end
    return UI_PAD
end

local function GetPlannerChromeHeight()
    return CANVAS_TOP + ROW_GAP + CONTROLS_H + ROW_GAP + TIMELINE_H + UI_PAD
end

local function GetPlannerCanvasDimensions(pf)
    if not pf then return PLANNER_CANVAS_W, PLANNER_CANVAS_H end
    local cw = pf.plannerCanvasW or PLANNER_CANVAS_W
    local ch = pf.plannerCanvasH or PLANNER_CANVAS_H
    return cw, ch
end

local function ComputeCanvasSizeFromFrame(pf, fw, fh)
    local availW = math.floor(fw - GetPlannerChromeWidth(pf) + 0.5)
    local availH = math.floor(fh - GetPlannerChromeHeight() + 0.5)
    local canvasW = math.min(PLANNER_CANVAS_W, availW)
    local canvasH = math.min(PLANNER_CANVAS_H, availH)
    return math.max(1, canvasW), math.max(1, canvasH)
end

local function GetPlannerRenderCanvasSize(pf, canvas)
    if canvas then
        local cw, ch = canvas:GetSize()
        if cw > 0 and ch > 0 then return cw, ch end
    end
    return GetPlannerCanvasDimensions(pf)
end

local HOVER_LEAVE_DELAY = 0.05

local function SetCompactControlButtonsVisible(pf, visible)
    if not pf then return end
    if pf.compactPreviewActive then visible = false end
    if pf.closeBtn then
        if visible then pf.closeBtn:Show() else pf.closeBtn:Hide() end
    end
    if pf.modeToggleBtn then
        if visible then pf.modeToggleBtn:Show() else pf.modeToggleBtn:Hide() end
    end
end

local function SetCompactSceneArrowButtonState(btn, enabled)
    if not btn then return end
    if enabled then
        btn:Enable()
        btn:SetAlpha(1)
        btn:SetBackdropColor(unpack(UI.ROW))
        if btn.label then btn.label:SetTextColor(0.92, 0.92, 0.92) end
    else
        btn:Disable()
        btn:SetAlpha(0.5)
        btn:SetBackdropColor(0.08, 0.09, 0.11, 0.92)
        if btn.label then btn.label:SetTextColor(0.50, 0.50, 0.50) end
    end
end

local function EnsureCompactSceneArrowButtons(pf)
    if not pf then return end
    if not pf.compactScenePrevBtn then
        local prevBtn = CreatePlannerIconBtn(pf, "<", 28, 34)
        prevBtn:SetScript("OnClick", function()
            if Diar.SelectPlannerScene then
                Diar:SelectPlannerScene((pf.selectedSceneIndex or 1) - 1)
            end
        end)
        pf.compactScenePrevBtn = prevBtn
    end
    if not pf.compactSceneNextBtn then
        local nextBtn = CreatePlannerIconBtn(pf, ">", 28, 34)
        nextBtn:SetScript("OnClick", function()
            if Diar.SelectPlannerScene then
                Diar:SelectPlannerScene((pf.selectedSceneIndex or 1) + 1)
            end
        end)
        pf.compactSceneNextBtn = nextBtn
    end
end

function Diar:UpdateCompactSceneArrowButtons(pf)
    pf = pf or self.plannerFrame
    if not pf then return end
    local data = self.plannerData
    local sceneCount = (data and data.scenes and #data.scenes) or 0
    local enabled = self.IsCompactSceneArrowsEnabled and self:IsCompactSceneArrowsEnabled()
    local show = enabled
        and pf.compactMode
        and not pf.compactPreviewActive
        and not pf.nsrtSceneActive
        and sceneCount > 1
    if not show then
        if pf.compactScenePrevBtn then pf.compactScenePrevBtn:Hide() end
        if pf.compactSceneNextBtn then pf.compactSceneNextBtn:Hide() end
        return
    end
    EnsureCompactSceneArrowButtons(pf)
    local prevBtn = pf.compactScenePrevBtn
    local nextBtn = pf.compactSceneNextBtn
    prevBtn:ClearAllPoints()
    nextBtn:ClearAllPoints()
    prevBtn:SetPoint("LEFT", pf, "LEFT", 6, 0)
    nextBtn:SetPoint("RIGHT", pf, "RIGHT", -6, 0)
    prevBtn:SetFrameStrata(pf:GetFrameStrata())
    nextBtn:SetFrameStrata(pf:GetFrameStrata())
    prevBtn:SetFrameLevel((pf:GetFrameLevel() or 0) + 25)
    nextBtn:SetFrameLevel((pf:GetFrameLevel() or 0) + 25)
    prevBtn:Show()
    nextBtn:Show()
    local idx = pf.selectedSceneIndex or 1
    SetCompactSceneArrowButtonState(prevBtn, idx > 1)
    SetCompactSceneArrowButtonState(nextBtn, idx < sceneCount)
end

local function IsMouseOverPlannerCompactChrome(pf)
    if not pf then return false end
    local check = { pf, pf.compactViewport, pf.canvas, pf.compactTopBar, pf.closeBtn, pf.modeToggleBtn }
    for i = 1, #check do
        local f = check[i]
        if f and f.IsShown and f:IsShown() and f.IsMouseOver and f:IsMouseOver() then
            return true
        end
    end
    return false
end

local function ScheduleCompactChromeHoverRefresh(pf)
    if not pf or pf.__compactChromeHoverRefreshScheduled then return end
    pf.__compactChromeHoverRefreshScheduled = true
    C_Timer.After(HOVER_LEAVE_DELAY, function()
        pf.__compactChromeHoverRefreshScheduled = nil
        if not pf or not pf.compactMode or pf.compactPreviewActive then return end
        SetCompactControlButtonsVisible(pf, IsMouseOverPlannerCompactChrome(pf))
    end)
end

local function HookCompactChromeHoverFrame(pf, f)
    if not pf or not f or f.__compactChromeHoverHooked then return end
    f.__compactChromeHoverHooked = true
    if f.EnableMouse then f:EnableMouse(true) end
    local function onEnter()
        if pf.compactMode and not pf.compactPreviewActive then SetCompactControlButtonsVisible(pf, true) end
    end
    local function onLeave()
        ScheduleCompactChromeHoverRefresh(pf)
    end
    if f.HookScript then
        f:HookScript("OnEnter", onEnter)
        f:HookScript("OnLeave", onLeave)
    else
        f:SetScript("OnEnter", onEnter)
        f:SetScript("OnLeave", onLeave)
    end
end

local function BindCompactChromeHover(pf)
    if not pf or pf.__compactChromeHoverBound then return end
    pf.__compactChromeHoverBound = true
    HookCompactChromeHoverFrame(pf, pf)
    HookCompactChromeHoverFrame(pf, pf.compactViewport)
    HookCompactChromeHoverFrame(pf, pf.canvas)
    HookCompactChromeHoverFrame(pf, pf.compactTopBar)
    HookCompactChromeHoverFrame(pf, pf.closeBtn)
    HookCompactChromeHoverFrame(pf, pf.modeToggleBtn)
end

local function RefreshCompactChromeHoverHooks(pf)
    if not pf or not pf.__compactChromeHoverBound then return end
    HookCompactChromeHoverFrame(pf, pf.compactViewport)
    HookCompactChromeHoverFrame(pf, pf.canvas)
    HookCompactChromeHoverFrame(pf, pf.compactTopBar)
    HookCompactChromeHoverFrame(pf, pf.closeBtn)
    HookCompactChromeHoverFrame(pf, pf.modeToggleBtn)
end

local function UnbindCompactChromeHover(pf)
    if not pf then return end
    pf.__compactChromeHoverBound = nil
end

local function UpdatePlannerModeToggleBtn(pf)
    if not pf or not pf.modeToggleBtn or not pf.closeBtn then return end
    pf.closeBtn:ClearAllPoints()
    pf.modeToggleBtn:ClearAllPoints()
    if pf.discordBtn then pf.discordBtn:ClearAllPoints() end
    if pf.creditsBtn then pf.creditsBtn:ClearAllPoints() end
    if pf.versionLabel then pf.versionLabel:ClearAllPoints() end
    if pf.compactMode then
        -- The Discord button is part of the expanded top bar only.
        if pf.discordBtn then pf.discordBtn:Hide() end
        if pf.creditsBtn then pf.creditsBtn:Hide() end
        if pf.versionLabel then pf.versionLabel:Hide() end
        if pf.compactPreviewActive then
            SetCompactControlButtonsVisible(pf, false)
            return
        end
        local anchor = pf
        if not pf.nsrtSceneActive and pf.compactTopBar and pf.compactTopBar:IsShown() then
            anchor = pf.compactTopBar
        end
        pf.closeBtn:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -2, -2)
        pf.modeToggleBtn:SetPoint("TOPRIGHT", pf.closeBtn, "TOPLEFT", -2, 0)
        SetPlannerBtnText(pf.modeToggleBtn, "Expand")
        BindCompactChromeHover(pf)
        RefreshCompactChromeHoverHooks(pf)
        if pf.closeBtn and pf.modeToggleBtn then
            local strata = pf.nsrtSceneActive and "TOOLTIP" or pf:GetFrameStrata()
            local lvl = pf.nsrtSceneActive and 600 or (pf:GetFrameLevel() + 20)
            pf.closeBtn:SetFrameStrata(strata)
            pf.closeBtn:SetFrameLevel(lvl)
            pf.modeToggleBtn:SetFrameStrata(strata)
            pf.modeToggleBtn:SetFrameLevel(lvl)
        end
        if pf.compactPreviewActive then
            SetCompactControlButtonsVisible(pf, false)
        elseif IsMouseOverPlannerCompactChrome(pf) then
            SetCompactControlButtonsVisible(pf, true)
        else
            SetCompactControlButtonsVisible(pf, false)
        end
    else
        UnbindCompactChromeHover(pf)
        pf.closeBtn:Show()
        pf.modeToggleBtn:Show()
        pf.closeBtn:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -6, -6)
        pf.modeToggleBtn:SetPoint("TOPRIGHT", pf.closeBtn, "TOPLEFT", -2, 1)
        SetPlannerBtnText(pf.modeToggleBtn, "Compact")
        if pf.discordBtn then
            pf.discordBtn:Show()
            pf.discordBtn:SetPoint("TOPRIGHT", pf.modeToggleBtn, "TOPLEFT", -2, 0)
        end
        if pf.creditsBtn then
            pf.creditsBtn:Show()
            if pf.discordBtn then
                pf.creditsBtn:SetPoint("TOPRIGHT", pf.discordBtn, "TOPLEFT", -2, 0)
            else
                pf.creditsBtn:SetPoint("TOPRIGHT", pf.modeToggleBtn, "TOPLEFT", -2, 0)
            end
        end
        if pf.versionLabel then
            pf.versionLabel:Show()
            pf.versionLabel:SetJustifyH("RIGHT")
            if pf.creditsBtn then
                pf.versionLabel:SetPoint("RIGHT", pf.creditsBtn, "LEFT", -8, 0)
            elseif pf.discordBtn then
                pf.versionLabel:SetPoint("RIGHT", pf.discordBtn, "LEFT", -8, 0)
            else
                pf.versionLabel:SetPoint("RIGHT", pf.modeToggleBtn, "LEFT", -8, 0)
            end
        end
    end
    if Diar.UpdateCompactSceneArrowButtons then
        Diar:UpdateCompactSceneArrowButtons(pf)
    end
end

Diar.UpdatePlannerModeToggleBtn = UpdatePlannerModeToggleBtn

local BG_BASE_PATH = "Interface\\AddOns\\" .. tostring(addonName) .. "\\backgrounds\\"
local ICON_BASE_PATH = "Interface\\AddOns\\" .. tostring(addonName) .. "\\icons\\"
local SHAPE_BASE_PATH = "Interface\\AddOns\\" .. tostring(addonName) .. "\\shapes\\"

-- Raid target markers: WoW API order (COMBATLOG_OBJECT_RAIDTARGET1-8) -> UI-RaidTargetingIcon_1-8
-- 1=Star, 2=Circle, 3=Diamond, 4=Triangle, 5=Moon, 6=Square, 7=Cross, 8=Skull
local RAID_ICON_MAP = { star = 1, circle = 2, diamond = 3, triangle = 4, moon = 5, square = 6, cross = 7, skull = 8 }

-- Class icons: site uses lowercase (warrior, warlock, deathknight, ...) -> Interface\Icons\ClassIcon_<Name>
local CLASS_ICON_MAP = {
    deathknight = "DeathKnight", demonhunter = "DemonHunter", druid = "Druid", evoker = "Evoker",
    hunter = "Hunter", mage = "Mage", monk = "Monk", paladin = "Paladin", priest = "Priest",
    rogue = "Rogue", shaman = "Shaman", warlock = "Warlock", warrior = "Warrior"
}

-- Spec IDs (modern API source of truth for specialization icons).
Diar.SPEC_ID_BY_CLASS = Diar.SPEC_ID_BY_CLASS or {
    deathknight = { blood = 250, frost = 251, unholy = 252 },
    demonhunter = { havoc = 577, vengeance = 581, devourer = 1480 },
    druid = { balance = 102, feral = 103, guardian = 104, restoration = 105 },
    evoker = { devastation = 1467, preservation = 1468, augmentation = 1473 },
    hunter = { beastmastery = 253, ["beast-mastery"] = 253, marksmanship = 254, survival = 255 },
    mage = { arcane = 62, fire = 63, frost = 64 },
    monk = { brewmaster = 268, windwalker = 269, mistweaver = 270 },
    paladin = { holy = 65, protection = 66, retribution = 70 },
    priest = { discipline = 256, holy = 257, shadow = 258 },
    rogue = { assassination = 259, outlaw = 260, subtlety = 261 },
    shaman = { elemental = 262, enhancement = 263, restoration = 264 },
    warlock = { affliction = 265, demonology = 266, destruction = 267 },
    warrior = { arms = 71, fury = 72, protection = 73 },
}

Diar.SPEC_KEY_ALIASES_BY_CLASS = Diar.SPEC_KEY_ALIASES_BY_CLASS or {
    demonhunter = {
        ["havoc-dh"] = "havoc",
        ["vengeance-dh"] = "vengeance",
        ["devouring"] = "devourer",
        ["devourer-demon-hunter"] = "devourer",
        ["devourerdemonhunter"] = "devourer",
        ["dps"] = "havoc",
        ["tank"] = "vengeance",
    },
}

-- Fallback spell icons if spec API lookup is unavailable.
Diar.SPEC_ICON_SPELL_BY_CLASS = Diar.SPEC_ICON_SPELL_BY_CLASS or {
    deathknight = { blood = 50842, frost = 49143, unholy = 55090 },
    demonhunter = { havoc = 162794, vengeance = 203720 },
    druid = { balance = 194153, feral = 22568, guardian = 6807, restoration = 774 },
    evoker = { devastation = 357211, preservation = 355936, augmentation = 395152 },
    hunter = { beastmastery = 19574, ["beast-mastery"] = 19574, marksmanship = 19434, survival = 190925 },
    mage = { arcane = 30451, fire = 133, frost = 116 },
    monk = { brewmaster = 115181, mistweaver = 116670, windwalker = 113656 },
    paladin = { holy = 82326, protection = 31935, retribution = 35395 },
    priest = { discipline = 47540, holy = 2061, shadow = 34914 },
    rogue = { assassination = 1329, outlaw = 315341, subtlety = 53 },
    shaman = { elemental = 188196, enhancement = 17364, restoration = 61295 },
    warlock = { affliction = 172, demonology = 105174, destruction = 17962 },
    warrior = { arms = 12294, fury = 23881, protection = 23922 },
}

-- Role icons: single texture UI-LFG-ICON-PORTRAITROLES (64x64), pixel regions from Blizzard Constants.lua
local ROLE_ICON_PATH = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local ROLE_ICON_COORDS = {
    tank  = { 0/64, 19/64, 22/64, 41/64 },
    healer = { 20/64, 39/64, 1/64, 20/64 },
    rdps  = { 20/64, 39/64, 22/64, 41/64 },
    mdps  = { 20/64, 39/64, 22/64, 41/64 },
}

Diar.CLASS_TOKEN_BY_KEY = Diar.CLASS_TOKEN_BY_KEY or {
    deathknight = "DEATHKNIGHT",
    demonhunter = "DEMONHUNTER",
    druid = "DRUID",
    evoker = "EVOKER",
    hunter = "HUNTER",
    mage = "MAGE",
    monk = "MONK",
    paladin = "PALADIN",
    priest = "PRIEST",
    rogue = "ROGUE",
    shaman = "SHAMAN",
    warlock = "WARLOCK",
    warrior = "WARRIOR",
}

local function GetCustomIconCandidates(iconKey)
    if not iconKey or iconKey == "" then return nil end
    local clean = iconKey:lower():gsub("^/+", ""):gsub("%.[^%.]+$", "")
    local key = clean:gsub("^.*/", "")
    return {
        ICON_BASE_PATH .. clean .. ".tga",
        ICON_BASE_PATH .. clean .. ".blp",
        ICON_BASE_PATH .. key .. ".tga",
        ICON_BASE_PATH .. key .. ".blp",
    }
end

local function SetTextureFromCandidates(tex, candidates)
    if not tex or not candidates then return false end
    for i = 1, #candidates do
        local ok = tex:SetTexture(candidates[i])
        if ok then return true end
    end
    return false
end

function Diar.SplitPathParts(path)
    local out = {}
    if type(path) ~= "string" or path == "" then return out end
    for part in path:gmatch("[^/]+") do
        out[#out + 1] = part
    end
    return out
end

function Diar.GetSpellTextureSafe(spellId)
    if not spellId then return nil end
    if C_Spell and type(C_Spell.GetSpellTexture) == "function" then
        local tex = C_Spell.GetSpellTexture(spellId)
        if tex then return tex end
    end
    if type(GetSpellTexture) == "function" then
        local tex = GetSpellTexture(spellId)
        if tex then return tex end
    end
    return nil
end

function Diar.GetSpecTextureSafe(specId)
    if not specId then return nil end
    if C_SpecializationInfo and type(C_SpecializationInfo.GetSpecializationInfoForSpecID) == "function" then
        local _, _, _, icon = C_SpecializationInfo.GetSpecializationInfoForSpecID(specId)
        if icon then return icon end
    end
    if type(GetSpecializationInfoByID) == "function" then
        local _, _, _, icon = GetSpecializationInfoByID(specId)
        if icon then return icon end
    end
    return nil
end

function Diar.ResolveSpecTextureFromIconKey(iconKey)
    if type(iconKey) ~= "string" or iconKey == "" then return nil end
    local clean = iconKey:lower():gsub("^/+", ""):gsub("%.[^%.]+$", "")
    local parts = Diar.SplitPathParts(clean)
    local specsIdx = nil
    for i = 1, #parts do
        if parts[i] == "specs" then
            specsIdx = i
            break
        end
    end
    if not specsIdx then return nil end
    local classKey = parts[specsIdx + 1]
    local specKey = parts[#parts]
    if not classKey or not specKey then return nil end
    classKey = classKey:gsub("%s+", ""):lower()
    specKey = specKey:gsub("%s+", ""):lower()
    local aliasMap = Diar.SPEC_KEY_ALIASES_BY_CLASS[classKey]
    if aliasMap and aliasMap[specKey] then
        specKey = aliasMap[specKey]
    end
    local alt = specKey:gsub("-", "")

    local specMap = Diar.SPEC_ID_BY_CLASS[classKey]
    if specMap then
        local specId = specMap[specKey] or specMap[alt]
        local specTex = Diar.GetSpecTextureSafe(specId)
        if specTex then return specTex end
    end

    -- Fallback: representative spell texture (older behavior).
    local spellMap = Diar.SPEC_ICON_SPELL_BY_CLASS[classKey]
    if not spellMap then return nil end
    local spellId = spellMap[specKey] or spellMap[alt]
    if not spellId then return nil end
    return Diar.GetSpellTextureSafe(spellId)
end

function Diar.ResolveClassKeyFromIconKey(iconKey)
    if type(iconKey) ~= "string" or iconKey == "" then return nil end
    local clean = iconKey:lower():gsub("^/+", ""):gsub("%.[^%.]+$", "")
    local parts = Diar.SplitPathParts(clean)
    for i = 1, #parts do
        if parts[i] == "classes" then
            return parts[i + 1]
        end
        if parts[i] == "specs" then
            return parts[i + 1]
        end
    end
    return nil
end

function Diar.GetClassCircleColor(classKey, opacity)
    local token = classKey and Diar.CLASS_TOKEN_BY_KEY[classKey]
    local cc = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    local a = (type(opacity) == "number") and opacity or 1
    if cc then
        return cc.r or 0.75, cc.g or 0.75, cc.b or 0.75, a
    end
    return 0.45, 0.58, 0.92, a
end

-- Pre-made shape texture paths (rect, circle, cone/triangle). Use these if present; else fall back to SetColorTexture/SetPortraitToTexture.
local FRONTAL_WHITE_TEX = "Interface\\Buttons\\WHITE8X8"

-- Parse a web fill into r,g,b,a (0..1). Understands #rgb / #rrggbb / #rrggbbaa,
-- rgb(...) and rgba(...). `opacity` (the object's opacity) multiplies the result.
local function ParseItemColor(fill, opacity)
    local mul = (type(opacity) == "number") and opacity or 1
    local r, g, b, fa = 0.96, 0.62, 0.07, 1
    if type(fill) == "string" and fill ~= "" then
        local s = fill:lower():gsub("%s+", "")
        if s:sub(1, 1) == "#" then
            local hex = s:sub(2)
            if #hex == 3 then
                hex = hex:sub(1, 1):rep(2) .. hex:sub(2, 2):rep(2) .. hex:sub(3, 3):rep(2)
            end
            if #hex >= 6 then
                r = (tonumber(hex:sub(1, 2), 16) or 245) / 255
                g = (tonumber(hex:sub(3, 4), 16) or 158) / 255
                b = (tonumber(hex:sub(5, 6), 16) or 11) / 255
                if #hex >= 8 then fa = (tonumber(hex:sub(7, 8), 16) or 255) / 255 end
            end
        else
            local rr, gg, bb, aa = s:match("^rgba?%((%d+),(%d+),(%d+),?([%d%.]*)%)$")
            if rr then
                r = (tonumber(rr) or 245) / 255
                g = (tonumber(gg) or 158) / 255
                b = (tonumber(bb) or 11) / 255
                if aa and aa ~= "" then fa = tonumber(aa) or 1 end
            end
        end
    end
    return r, g, b, mul * fa
end

local function HasStroke(item)
    if not item then return false end
    local sw = tonumber(item.strokeWidth)
    if sw and sw > 0 then return true end
    if type(item.stroke) ~= "string" then return false end
    local s = item.stroke:lower()
    return s ~= "" and s ~= "transparent" and s ~= "none"
end

local function GetShapeTextureCandidates(shapeType)
    if not shapeType or shapeType == "" then return nil end
    local st = shapeType:lower()
    local base = SHAPE_BASE_PATH
    if st == "rect" or st == "rectangle" then
        return { base .. "rect.tga", base .. "rect.blp", base .. "rectangle.tga", base .. "rectangle.blp" }
    end
    if st == "circle" then
        return { base .. "circle.tga", base .. "circle.blp" }
    end
    if st == "triangle" or st == "cone" then
        return { base .. "cone.tga", base .. "cone.blp", base .. "triangle.tga", base .. "triangle.blp" }
    end
    if st == "ellipse" then
        return { base .. "ellipse.tga", base .. "ellipse.blp" }
    end
    return nil
end

local function ApplyFrontalBeamFill(tex, r, g, b, a)
    -- Always use a flat color fill — shape .tga files are not reliable beam masks.
    tex:SetColorTexture(r, g, b, a)
    tex:SetAlpha(a)
end

local function IsFrontalAnim(anim)
    if not anim then return false end
    local flag = anim.isFrontalSweepAnimation
    return flag == true or flag == 1
end

local function IsFrontalItem(item)
    return item and (item.isFrontalBeam == true or item.isFrontalBeam == 1)
end

-- Fabric viewport mirror (public/js/canvas/viewport/zooming.js):
-- screen = world * zoom + pan; pan is normalized (panX = vpt[4]/canvas.width).
-- Everything (items, shapes, background) uses the SAME formula so they stay aligned.
-- All widgets are parented straight to the canvas frame, which clips to its bounds.
local PLANNER_MIN_ZOOM = 1
local PLANNER_MAX_ZOOM = 10

local function GetPlannerItemRoot(pf, canvas)
    return canvas
end

local function IsNoPlanLoaded(data)
    if not data then return true end
    if data.savedEntryId then return false end
    return tostring(data.planName or "") == "No plan"
end

local function SetNoPlanCanvasHint(pf, show)
    if not pf or not pf.canvas then return end
    if not pf.noPlanHint then
        local hint = pf.canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        hint:SetJustifyH("CENTER")
        hint:SetJustifyV("MIDDLE")
        hint:SetWordWrap(true)
        hint:SetText("No plan loaded. Select a plan in the plan library on the right.")
        hint:SetTextColor(0.62, 0.66, 0.72)
        pf.noPlanHint = hint
    end
    pf.noPlanHint:ClearAllPoints()
    pf.noPlanHint:SetPoint("CENTER", pf.canvas, "CENTER", 0, 0)
    pf.noPlanHint:SetWidth(math.max(220, (pf.canvas:GetWidth() or 600) - 80))
    if show then
        pf.noPlanHint:Show()
    else
        pf.noPlanHint:Hide()
    end
end

local function BuildPlannerInfoStripText()
    local addonVer = "v0.0.2"
    if Diar.GetAddonVersion then
        addonVer = "v" .. tostring(Diar:GetAddonVersion() or "0.0.2")
    end
    return ("Raidstrats.gg - Raidplanner & Assignments   |   Author: Nairyana   |   Website: raidstrats.gg   |   %s (alpha build)"):format(addonVer)
end

local function EnsurePlannerInfoStrip(pf)
    if not pf then return end
    if not pf.infoStrip then
        local strip = CreateFrame("Frame", nil, pf, "BackdropTemplate")
        strip:SetHeight(18)
        strip:SetPoint("TOPLEFT", pf, "BOTTOMLEFT", 0, 0)
        strip:SetPoint("TOPRIGHT", pf, "BOTTOMRIGHT", 0, 0)
        strip:EnableMouse(false)

        local bg = strip:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(strip)
        local tb = UI.TOOLBAR or {0.05, 0.05, 0.08, 0.92}
        bg:SetColorTexture(tb[1] or 0.05, tb[2] or 0.05, tb[3] or 0.08, tb[4] or 0.92)
        strip.bg = bg

        local txt = strip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        txt:SetPoint("CENTER", strip, "CENTER", 0, 0)
        txt:SetJustifyH("CENTER")
        txt:SetTextColor(0.56, 0.60, 0.66)
        strip.text = txt

        local topLine = strip:CreateTexture(nil, "ARTWORK")
        topLine:SetHeight(1)
        topLine:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, 0)
        topLine:SetPoint("TOPRIGHT", strip, "TOPRIGHT", 0, 0)
        topLine:SetColorTexture(unpack(UI.BORDER))
        strip.topLine = topLine

        pf.infoStrip = strip
    end
    if pf.infoStrip and pf.infoStrip.text then
        pf.infoStrip.text:SetText(BuildPlannerInfoStripText())
    end
end

-- Keep pan inside canvas/world bounds when zoomed in (mirrors ensureBackgroundVisible in panning.js).
local function ClampViewerViewportNormalized(vs)
    if not vs or type(vs.zoom) ~= "number" then return nil end
    local zoom = vs.zoom
    if zoom < PLANNER_MIN_ZOOM then zoom = PLANNER_MIN_ZOOM
    elseif zoom > PLANNER_MAX_ZOOM then zoom = PLANNER_MAX_ZOOM end
    if zoom <= 1.001 then return nil end
    local minPan = 1 - zoom
    local panX = (type(vs.panX) == "number") and vs.panX or 0
    local panY = (type(vs.panY) == "number") and vs.panY or 0
    panX = math.max(minPan, math.min(0, panX))
    panY = math.max(minPan, math.min(0, panY))
    return { zoom = zoom, panX = panX, panY = panY }
end

local function ParseSceneViewport(scene)
    local vs = scene and (scene.viewportState or scene.view)
    if type(vs) ~= "table" or type(vs.zoom) ~= "number" then return nil end
    local zoom = vs.zoom
    if zoom < PLANNER_MIN_ZOOM then zoom = PLANNER_MIN_ZOOM
    elseif zoom > PLANNER_MAX_ZOOM then zoom = PLANNER_MAX_ZOOM end
    return ClampViewerViewportNormalized({
        zoom = zoom,
        panX = (type(vs.panX) == "number") and vs.panX or 0,
        panY = (type(vs.panY) == "number") and vs.panY or 0,
    })
end

-- vc holds pan already converted to pixels (panX * cw). nil when at default view.
local function BuildSceneViewContext(vs, cw, ch)
    if not vs or type(vs.zoom) ~= "number" then return nil end
    local zoom = vs.zoom
    if zoom < PLANNER_MIN_ZOOM then zoom = PLANNER_MIN_ZOOM
    elseif zoom > PLANNER_MAX_ZOOM then zoom = PLANNER_MAX_ZOOM end
    local panX = (type(vs.panX) == "number") and (vs.panX * cw) or 0
    local panY = (type(vs.panY) == "number") and (vs.panY * ch) or 0
    if zoom <= 1.001 and math.abs(panX) < 0.5 and math.abs(panY) < 0.5 then
        return nil
    end
    return { zoom = zoom, panX = panX, panY = panY, cw = cw, ch = ch }
end

local function GetViewerViewportNormalized(pf)
    if not pf then return nil end
    local vs = pf.viewerViewport
    if type(vs) ~= "table" or type(vs.zoom) ~= "number" then return nil end
    return vs
end

local function SyncViewerViewportFromScene(pf, scene)
    if not pf then return end
    local sceneIdx = pf.selectedSceneIndex or 1
    if pf.__viewerViewportSceneIdx ~= sceneIdx then
        pf.viewerViewport = ParseSceneViewport(scene)
        pf.__viewerViewportSceneIdx = sceneIdx
    elseif pf.viewerViewport == nil and scene then
        pf.viewerViewport = ParseSceneViewport(scene)
    end
end

local function GetCanvasCursor(canvas, pf)
    local cw, ch = canvas:GetSize()
    if not cw or cw <= 0 then cw = PLANNER_CANVAS_W end
    if not ch or ch <= 0 then ch = PLANNER_CANVAS_H end
    local scale = (pf and pf.GetEffectiveScale and pf:GetEffectiveScale()) or 1
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    local left, top = canvas:GetLeft(), canvas:GetTop()
    if not left or not top then return cw * 0.5, ch * 0.5, cw, ch end
    return cx - left, top - cy, cw, ch
end

local function GetCanvasLocalCursor(canvas, pf)
    local x, y, cw, ch = GetCanvasCursor(canvas, pf)
    if x < 0 or y < 0 or x > cw or y > ch then
        return cw * 0.5, ch * 0.5, cw, ch, false
    end
    return x, y, cw, ch, true
end

local function PlannerZoomViewerAt(pf, factor, focalX, focalY, cw, ch)
    if not pf or not cw or cw <= 0 or not ch or ch <= 0 then return end
    local vs = GetViewerViewportNormalized(pf) or { zoom = 1, panX = 0, panY = 0 }
    local oldZoom = vs.zoom
    local newZoom = oldZoom * factor
    if newZoom > PLANNER_MAX_ZOOM then newZoom = PLANNER_MAX_ZOOM
    elseif newZoom < PLANNER_MIN_ZOOM then newZoom = PLANNER_MIN_ZOOM end
    if math.abs(newZoom - oldZoom) < 1e-6 then return end

    focalX = focalX or (cw * 0.5)
    focalY = focalY or (ch * 0.5)
    local panXpx = (vs.panX or 0) * cw
    local panYpx = (vs.panY or 0) * ch
    local wx = (focalX - panXpx) / oldZoom
    local wy = (focalY - panYpx) / oldZoom

    if newZoom <= 1.001 then
        pf.viewerViewport = nil
    else
        local newPanXpx = focalX - wx * newZoom
        local newPanYpx = focalY - wy * newZoom
        pf.viewerViewport = ClampViewerViewportNormalized({
            zoom = newZoom,
            panX = newPanXpx / cw,
            panY = newPanYpx / ch,
        })
    end
end

local function HandlePlannerCanvasWheel(delta)
    local pf = Diar.plannerFrame
    local canvas = pf and pf.canvas
    if not canvas then return end
    local x, y, cw, ch, overCanvas = GetCanvasLocalCursor(canvas, pf)
    if not overCanvas then return end
    local factor = (delta and delta > 0) and 1.2 or 0.833333
    PlannerZoomViewerAt(pf, factor, x, y, cw, ch)
    Diar:RefreshPlannerViewportDisplay(false)
end

local function UpdatePlannerZoomLabel(pf)
    if not pf or not pf.zoomLabel then return end
    local vs = GetViewerViewportNormalized(pf)
    local zoom = (vs and vs.zoom) or 1
    pf.zoomLabel:SetText(string.format("%d%%", math.floor(zoom * 100 + 0.5)))
end

local function EnsurePlannerZoomControls(pf, canvas)
    if not pf or not canvas or pf.zoomBar then return end
    local bar = CreateFrame("Frame", nil, canvas)
    bar:SetFrameLevel(canvas:GetFrameLevel() + 20)
    bar:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -6, -6)
    pf.zoomBar = bar

    local btnW, btnH, gap = 28, 22, 2
    local zoomOut = CreatePlannerIconBtn(bar, "-", btnW, btnH)
    zoomOut:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    zoomOut:SetScript("OnClick", function() Diar:PlannerZoomOut() end)

    local zoomLabel = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    zoomLabel:SetPoint("RIGHT", zoomOut, "LEFT", -gap, 0)
    zoomLabel:SetWidth(40)
    zoomLabel:SetJustifyH("CENTER")
    zoomLabel:SetTextColor(0.92, 0.92, 0.92)
    pf.zoomLabel = zoomLabel

    local zoomIn = CreatePlannerIconBtn(bar, "+", btnW, btnH)
    zoomIn:SetPoint("RIGHT", zoomLabel, "LEFT", -gap, 0)
    zoomIn:SetScript("OnClick", function() Diar:PlannerZoomIn() end)

    local resetBtn = CreatePlannerIconBtn(bar, "Reset", 44, btnH)
    resetBtn:SetPoint("RIGHT", zoomIn, "LEFT", -gap, 0)
    resetBtn:SetScript("OnClick", function() Diar:PlannerResetViewport() end)

    UpdatePlannerZoomLabel(pf)
end

local BeginPlannerFrameMove, FinishPlannerFrameMove

local function BindPlannerCanvasViewportInput(pf, canvas)
    if not pf or not canvas or pf.__canvasViewportBound then return end
    pf.__canvasViewportBound = true
    canvas:EnableMouse(true)
    canvas:EnableMouseWheel(true)
    pf:EnableMouseWheel(true)
    pf:SetScript("OnMouseWheel", function(_, delta)
        HandlePlannerCanvasWheel(delta)
    end)

    canvas:SetScript("OnMouseWheel", function(_, delta)
        HandlePlannerCanvasWheel(delta)
    end)

    canvas:SetScript("OnMouseDown", function(_, button)
        if Diar.TryPaletteCanvasMouseDown and Diar:TryPaletteCanvasMouseDown(button) then return end
        local pf2 = Diar.plannerFrame
        if pf2 and pf2.nsrtSceneActive and button == "LeftButton" then
            BeginPlannerFrameMove(pf2, button)
            return
        end
        if button ~= "LeftButton" and button ~= "MiddleButton" then return end
        local pf2 = Diar.plannerFrame
        local vs = pf2 and GetViewerViewportNormalized(pf2)
        if not pf2 or not vs or vs.zoom <= 1.001 then return end
        local c = pf2.canvas
        if not c then return end
        local x, y, cw, ch = GetCanvasCursor(c, pf2)
        pf2.__canvasPan = {
            x0 = x, y0 = y,
            panX = vs.panX or 0,
            panY = vs.panY or 0,
            zoom = vs.zoom,
            cw = cw, ch = ch,
        }
        c:SetScript("OnUpdate", function()
            local p = pf2.__canvasPan
            if not p then return end
            if not IsMouseButtonDown("LeftButton") and not IsMouseButtonDown("MiddleButton") then
                c:SetScript("OnUpdate", nil)
                pf2.__canvasPan = nil
                Diar:RefreshPlannerViewportDisplay(false)
                return
            end
            local cx, cy = GetCanvasCursor(c, pf2)
            local dx, dy = cx - p.x0, cy - p.y0
            pf2.viewerViewport = ClampViewerViewportNormalized({
                zoom = p.zoom,
                panX = p.panX + dx / p.cw,
                panY = p.panY + dy / p.ch,
            })
            Diar:RefreshPlannerViewportDisplay(true)
        end)
    end)

    canvas:SetScript("OnMouseUp", function(_, button)
        if Diar.TryPaletteCanvasMouseUp and Diar:TryPaletteCanvasMouseUp(button) then return end
        local pf2 = Diar.plannerFrame
        if pf2 and pf2.__plannerMoving and button == "LeftButton" then
            FinishPlannerFrameMove(pf2)
        end
    end)
end

local function SceneViewCoord(vc, wx, wy)
    if not vc then return wx, wy end
    return wx * vc.zoom + vc.panX, wy * vc.zoom + vc.panY
end

local function SceneViewScale(vc, value)
    if not vc or not value then return value end
    return value * vc.zoom
end

local function SceneViewPctToCanvas(vc, cw, ch, xp, yp)
    return SceneViewCoord(vc, cw * xp, ch * yp)
end

local function ResolveItemLayerIndex(item, fallbackIndex)
    local n = tonumber(item and (item.layerIndex or item.zIndex or item.layer or item.z))
    if not n then
        n = (fallbackIndex or 1) - 1
    end
    if n < 0 then n = 0 end
    if n > 900 then n = 900 end
    return math.floor(n + 0.5)
end

local function ResolveItemFrameLevel(root, item, fallbackIndex, boost)
    local base = (root and root.GetFrameLevel and root:GetFrameLevel()) or 0
    local z = ResolveItemLayerIndex(item, fallbackIndex)
    return base + 2 + z + (boost or 0)
end

local function CanvasScreenToWorld(vc, sx, sy)
    if not vc then return sx, sy end
    return (sx - vc.panX) / vc.zoom, (sy - vc.panY) / vc.zoom
end

local function EnsureWidgetWorldSize(w, cw, ch, wp, hp, minSize)
    if not w.baseWorldW or w.baseWorldW <= 0 then
        w.baseWorldW = math.max(minSize, cw * wp)
    end
    if not w.baseWorldH or w.baseWorldH <= 0 then
        w.baseWorldH = math.max(minSize, ch * hp)
    end
end

local UpdateCircleWidgetStroke

local function LayoutItemWidget(w, item, vc, cw, ch, root, minSize)
    local wp = (type(item.w) == "number" and item.w or 4) / 100
    local hp = (type(item.h) == "number" and item.h or 4) / 100
    local xp = item.currentX or ((type(item.x) == "number" and item.x or 0) / 100)
    local yp = item.currentY or ((type(item.y) == "number" and item.y or 0) / 100)
    EnsureWidgetWorldSize(w, cw, ch, wp, hp, minSize)
    local iw = math.max(minSize, SceneViewScale(vc, w.baseWorldW))
    local ih = math.max(minSize, SceneViewScale(vc, w.baseWorldH))
    w:SetSize(iw, ih)
    w.basePixelW = iw
    w.basePixelH = ih
    w:ClearAllPoints()
    local px, py = SceneViewPctToCanvas(vc, cw, ch, xp, yp)
    w:SetPoint("TOPLEFT", root, "TOPLEFT", px, -py)
    if item.kind == "shape" then
        local shp = tostring(item.shape or ""):lower()
        if shp == "circle" or shp == "ellipse" then
            UpdateCircleWidgetStroke(w, item, vc, ch)
        end
    end
end

local function LayoutTextWidgetFont(w, item, vc, ch)
    local fontPx = SceneViewScale(vc, ch * ((type(item.fontSize) == "number" and item.fontSize or 4) / 100))
    return math.max(6, math.min(fontPx, 64))
end

local function ApplyTextWidgetContent(w, item, label, vc, ch, minSize)
    if not w.text then
        w.text = w:CreateFontString(nil, "OVERLAY")
        w.text:SetJustifyH("LEFT")
        w.text:SetJustifyV("TOP")
    end
    w.text:ClearAllPoints()
    w.text:SetPoint("TOPLEFT", w, "TOPLEFT", 0, 0)
    local fontFlags = ""
    if HasStroke(item) then
        local sw = tonumber(item.strokeWidth) or 0
        fontFlags = (sw >= 2.5) and "THICKOUTLINE" or "OUTLINE"
    end
    w.text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", LayoutTextWidgetFont(w, item, vc, ch), fontFlags)
    local tr, tg, tb = 1, 1, 1
    if item.textColor or item.fill then
        tr, tg, tb = ParseItemColor(item.textColor or item.fill, 1)
    end
    w.__baseTextColor = { tr, tg, tb }
    w.text:SetTextColor(tr, tg, tb)
    local textValue = tostring(label or "")
    textValue = textValue:gsub("\r\n", "\n"):gsub("\r", "\n")
    local isMultiLine = textValue:find("\n", 1, true) ~= nil
    w.text:SetWordWrap(isMultiLine)
    if w.text.SetNonSpaceWrap then w.text:SetNonSpaceWrap(isMultiLine) end
    if w.text.SetMaxLines then w.text:SetMaxLines(0) end
    -- Use a large temporary width for measurement; width=0 can render as ellipsis on some clients.
    local measureW = isMultiLine and math.max(32, math.ceil((w.baseWorldW or w:GetWidth() or 0))) or 4096
    w.text:SetWidth(measureW)
    w.text:SetText(textValue)
    local measuredW = (not isMultiLine and w.text.GetUnboundedStringWidth)
        and w.text:GetUnboundedStringWidth()
        or w.text:GetStringWidth()
    local textW = math.max(minSize, math.ceil((measuredW or 0) + 8))
    local textH = math.max(minSize, math.ceil((w.text:GetStringHeight() or 0) + 2))
    w:SetSize(textW, textH)
    w.basePixelW = textW
    w.basePixelH = textH
    w.text:SetWidth(math.max(textW, measureW))
    w.text:Show()
    return tr, tg, tb
end

Diar.PlannerView = {
    Coord = SceneViewCoord,
    Scale = SceneViewScale,
    PctToCanvas = SceneViewPctToCanvas,
    ScreenToWorld = CanvasScreenToWorld,
    GetContext = function(pf) return pf and pf.sceneViewContext or nil end,
}

local function CreateFrontalBeamWidget(pf, canvas, anim, cw, ch)
    local wp = (type(anim.frontalW) == "number" and anim.frontalW or 5) / 100
    local hp = (type(anim.frontalH) == "number" and anim.frontalH or 18) / 100
    local beamWidthPx = math.max(4, cw * wp)
    local beamLenPx = math.max(12, ch * hp)
    local shapeName = (anim.frontalShape or "rect"):lower()
    local isCone = (shapeName == "triangle" or shapeName == "cone")

    -- A Line draws a thick segment between two arbitrary points: perfect for a beam that
    -- pivots from the boss and sweeps. planner-frontal.lua sets the endpoints each frame.
    local frame = CreateFrame("Frame", nil, canvas)
    frame:SetAllPoints(canvas)
    frame:SetFrameLevel(canvas:GetFrameLevel() + 1)
    frame.__isFrontalBeamWidget = true
    frame.frontalShape = shapeName
    frame.isCone = isCone
    frame.beamWidthPx = beamWidthPx
    frame.beamLenPx = beamLenPx

    local r, g, b, a = ParseItemColor(anim.frontalFill, anim.frontalOpacity)
    frame.fillR, frame.fillG, frame.fillB, frame.fillA = r, g, b, a

    local line = frame:CreateLine(nil, "ARTWORK")
    line:SetThickness(beamWidthPx)
    line:SetColorTexture(r, g, b, a)
    line:Hide()
    frame.line = line

    frame:Hide()
    return frame
end

local function BuildFrontalBeamWidgets(pf, scene, canvas, cw, ch)
    if pf.frontalBeamWidgets then
        for _, widget in pairs(pf.frontalBeamWidgets) do
            ReleasePlannerWidget(pf, widget)
        end
    end
    pf.frontalBeamWidgets = {}
    if not scene or not scene.animations then return end
    for ai, anim in ipairs(scene.animations) do
        if IsFrontalAnim(anim) then
            pf.frontalBeamWidgets[ai] = CreateFrontalBeamWidget(pf, canvas, anim, cw, ch)
        end
    end
end

-- Built-in scalable circle mask: lets us draw smooth filled circles/ellipses/dots
-- from a flat color texture with no shipped art assets.
local CIRCLE_MASK = "Interface\\Masks\\CircleMaskScalable"
local WHITE_TEX = "Interface\\Buttons\\WHITE8X8"

-- Stroke/line color helper (defaults to white when no stroke given).
local function ParseStrokeColor(stroke, opacity)
    if type(stroke) == "string" and stroke ~= "" then
        return ParseItemColor(stroke, opacity)
    end
    local a = (type(opacity) == "number") and opacity or 1
    return 1, 1, 1, a
end

local function HasFill(item)
    if not item then return false end
    if item.fill == nil or item.fill == false then return false end
    if type(item.fill) ~= "string" then return true end
    local s = item.fill:lower()
    return s ~= "" and s ~= "transparent" and s ~= "none"
end

local function StrokeThickPx(item, ch)
    -- Default ~0.4% canvas height when width omitted but stroke color is set.
    return math.max(3, ch * ((tonumber(item.strokeWidth) or 0.4) / 100))
end

local function HideWidgetStroke(w)
    if not w or not w._strokeLines then return end
    for _, ln in ipairs(w._strokeLines) do ln:Hide() end
end

local function ClearBackdropStroke(w)
    if w and w.SetBackdrop then w:SetBackdrop(nil) end
end

local function IsRectLikeShape(shp)
    shp = tostring(shp or ""):lower()
    return shp == "rect" or shp == "rectangle" or shp == "square" or shp == "polygon"
end

-- Filled rect/square via backdrop (avoids stale circle masks on recycled widgets).
local function ApplyBoxShapeVisual(w, item, ch)
    if not w or not w.tex then return end
    if w.__maskOn and w.circleMask then
        w.tex:RemoveMaskTexture(w.circleMask)
        w.__maskOn = false
    elseif w.__maskOn and w.circleMasks then
        for _, m in ipairs(w.circleMasks) do w.tex:RemoveMaskTexture(m) end
        w.__maskOn = false
    end
    local r, g, b, a = ParseItemColor(item.fill, item.opacity)
    if not w.SetBackdrop then Mixin(w, BackdropTemplateMixin) end
    local edgeSize = 0
    local sr, sg, sb, sa = 1, 1, 1, 1
    if HasStroke(item) then
        sr, sg, sb, sa = ParseStrokeColor(item.stroke, item.opacity)
        edgeSize = math.max(1, math.ceil(StrokeThickPx(item, ch)))
    end
    w:SetBackdrop({
        bgFile = WHITE_TEX,
        edgeFile = edgeSize > 0 and WHITE_TEX or nil,
        tile = false,
        edgeSize = edgeSize,
    })
    w:SetBackdropColor(r, g, b, a)
    if edgeSize > 0 then
        w:SetBackdropBorderColor(sr, sg, sb, sa)
    end
    w.tex:Hide()
end

-- Reliable rect/polygon stroke via backdrop border (moves with the widget).
local function ApplyBackdropStroke(w, item, ch)
    if not HasStroke(item) then
        ClearBackdropStroke(w)
        return
    end
    local sr, sg, sb, sa = ParseStrokeColor(item.stroke, item.opacity)
    local thick = math.max(1, math.ceil(StrokeThickPx(item, ch)))
    if not w.SetBackdrop then Mixin(w, BackdropTemplateMixin) end
    w:SetBackdrop({
        bgFile = nil,
        edgeFile = WHITE_TEX,
        tile = true,
        tileSize = 8,
        edgeSize = thick,
    })
    w:SetBackdropBorderColor(sr, sg, sb, sa)
end

local function GetItemCanvasRect(item, cw, ch, vc)
    local xp = (type(item.currentX) == "number") and item.currentX or ((tonumber(item.x) or 0) / 100)
    local yp = (type(item.currentY) == "number") and item.currentY or ((tonumber(item.y) or 0) / 100)
    local x, y = SceneViewCoord(vc, cw * xp, ch * yp)
    return x, y, SceneViewScale(vc, cw * ((tonumber(item.w) or 4) / 100)), SceneViewScale(vc, ch * ((tonumber(item.h) or 4) / 100))
end

local function ColorLine(ln, r, g, b, a, thick)
    ln:SetThickness(thick)
    if ln.SetColorTexture then
        ln:SetColorTexture(r, g, b, a)
    else
        ln:SetTexture(WHITE_TEX)
        ln:SetVertexColor(r, g, b, a)
    end
end

local function ApplyCircleWidgetVisual(w, item, override)
    if not w or not w.tex then return end
    if override or HasFill(item) then
        if not w.circleMask then
            w.circleMask = w:CreateMaskTexture()
            w.circleMask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        end
        local r, g, b, a
        if override then
            r, g, b, a = override[1], override[2], override[3], override[4] or 1
        else
            r, g, b, a = ParseItemColor(item.fill, item.opacity)
        end
        w.tex:SetTexture(WHITE_TEX)
        w.tex:SetVertexColor(r, g, b, a)
        w.tex:SetAlpha(a)
        w.circleMask:SetAllPoints(w.tex)
        if not w.__maskOn then
            w.tex:AddMaskTexture(w.circleMask)
            w.__maskOn = true
        end
        w.tex:Show()
    else
        w.tex:Hide()
        if w.__maskOn and w.circleMask then
            w.tex:RemoveMaskTexture(w.circleMask)
            w.__maskOn = false
        end
    end
end

UpdateCircleWidgetStroke = function(w, item, vc, ch)
    if not w then return end
    local override = w.__ringOverride
    if not HasStroke(item) and not override then
        if w._ringLines then
            for _, ln in ipairs(w._ringLines) do ln:Hide() end
        end
        w.__ringLayoutIw = nil
        w.__ringLayoutColor = nil
        return
    end
    local segs = 32
    w._ringLines = w._ringLines or {}
    local sr, sg, sb, sa
    if override then
        sr, sg, sb, sa = override[1], override[2], override[3], override[4] or 1
    else
        sr, sg, sb, sa = ParseStrokeColor(item.stroke, item.opacity)
    end
    local thick = SceneViewScale(vc, StrokeThickPx(item, ch))
    if override and w.__groupSpotMine then
        thick = thick * 1.35
    end
    local iw, ih = w:GetWidth(), w:GetHeight()
    if iw < 2 or ih < 2 then return end
    local colorSig = string.format("%.2f:%.2f:%.2f:%.2f", sr, sg, sb, sa)
    if w.__ringLayoutIw == iw and w.__ringLayoutIh == ih and w.__ringLayoutThick == thick
        and w.__ringLayoutColor == colorSig then return end
    w.__ringLayoutIw = iw
    w.__ringLayoutIh = ih
    w.__ringLayoutThick = thick
    w.__ringLayoutColor = colorSig
    local rx, ry = iw / 2, ih / 2
    local cx, cy = iw / 2, ih / 2
    for i = 1, segs do
        local ln = w._ringLines[i]
        if not ln then
            ln = w:CreateLine(nil, "OVERLAY")
            w._ringLines[i] = ln
        end
        ln:Show()
        ColorLine(ln, sr, sg, sb, sa, thick)
        local a1 = (i - 1) / segs * math.pi * 2
        local a2 = i / segs * math.pi * 2
        ln:SetStartPoint("TOPLEFT", w, cx + rx * math.cos(a1), -(cy + ry * math.sin(a1)))
        ln:SetEndPoint("TOPLEFT", w, cx + rx * math.cos(a2), -(cy + ry * math.sin(a2)))
    end
    for i = segs + 1, #w._ringLines do
        w._ringLines[i]:Hide()
    end
end

-- ----------------------------------------------------------------------------
-- Static vector shapes (donut, triangle/cone, line, arrow) drawn with Line
-- primitives. These are not animation targets; they live in a pooled set that
-- is rebuilt each scene refresh so frames/lines are reused (no leaks).
-- ----------------------------------------------------------------------------
local function ResetShapePool(pf)
    pf._shapePoolUsed = 0
    if not pf._shapePool then return end
    for _, f in ipairs(pf._shapePool) do
        if f._lines then for _, ln in ipairs(f._lines) do ln:Hide() end end
        if f._dots then for _, d in ipairs(f._dots) do d:Hide() end end
        f:SetAlpha(1)
        f:Hide()
    end
end

local function AcquireShapeFrame(pf, canvas, frameLevel)
    pf._shapePool = pf._shapePool or {}
    pf._shapePoolUsed = (pf._shapePoolUsed or 0) + 1
    local f = pf._shapePool[pf._shapePoolUsed]
    if not f then
        f = CreateFrame("Frame", nil, canvas)
        f._lines = {}
        f._dots = {}
        pf._shapePool[pf._shapePoolUsed] = f
    end
    f:SetParent(canvas)
    f:ClearAllPoints()
    f:SetAllPoints(canvas)
    f:SetFrameLevel(frameLevel or (canvas:GetFrameLevel() + 2))
    f:SetAlpha(1)
    f._lineUsed = 0
    f._dotUsed = 0
    f:Show()
    return f
end

local function ShapeLine(f)
    f._lineUsed = (f._lineUsed or 0) + 1
    local ln = f._lines[f._lineUsed]
    if not ln then
        ln = f:CreateLine(nil, "ARTWORK")
        f._lines[f._lineUsed] = ln
    end
    ln:Show()
    return ln
end

-- Ellipse outline on canvas coords (negative Y = down, same as lines/frontals).
-- Must be defined after ShapeLine (Lua does not hoist local functions).
local function DrawEllipseStroke(f, canvas, cx, cy, rx, ry, item, ch, segs)
    if not HasStroke(item) then return end
    local sr, sg, sb, sa = ParseStrokeColor(item.stroke, item.opacity)
    local thick = StrokeThickPx(item, ch)
    segs = segs or 40
    for i = 1, segs do
        local a1 = (i - 1) / segs * math.pi * 2
        local a2 = i / segs * math.pi * 2
        local x1 = cx + rx * math.cos(a1)
        local y1 = cy + ry * math.sin(a1)
        local x2 = cx + rx * math.cos(a2)
        local y2 = cy + ry * math.sin(a2)
        local ln = ShapeLine(f)
        ColorLine(ln, sr, sg, sb, sa, thick)
        ln:SetStartPoint("TOPLEFT", canvas, x1, -y1)
        ln:SetEndPoint("TOPLEFT", canvas, x2, -y2)
    end
end

local function DrawRectStroke(f, canvas, x, y, w, h, item, ch)
    if not HasStroke(item) then return end
    local sr, sg, sb, sa = ParseStrokeColor(item.stroke, item.opacity)
    local thick = StrokeThickPx(item, ch)
    local edges = {
        { x, y, x + w, y },
        { x + w, y, x + w, y + h },
        { x + w, y + h, x, y + h },
        { x, y + h, x, y },
    }
    for i = 1, 4 do
        local e = edges[i]
        local ln = ShapeLine(f)
        ColorLine(ln, sr, sg, sb, sa, thick)
        ln:SetStartPoint("TOPLEFT", canvas, e[1], -e[2])
        ln:SetEndPoint("TOPLEFT", canvas, e[3], -e[4])
    end
end

-- A round dot (flat color + circle mask). Stacking the same mask twice multiplies the
-- alpha falloff (a^2), sharpening the edge so it isn't blurry. Used for rounded rings.
local function ShapeDot(f)
    f._dotUsed = (f._dotUsed or 0) + 1
    local d = f._dots[f._dotUsed]
    if not d then
        d = f:CreateTexture(nil, "ARTWORK")
        for _ = 1, 2 do
            local mask = f:CreateMaskTexture()
            mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(d)
            d:AddMaskTexture(mask)
        end
        f._dots[f._dotUsed] = d
    end
    d:Show()
    return d
end

local function DrawLineShape(pf, canvas, item, cw, ch, frameLevel)
    local f = AcquireShapeFrame(pf, canvas, frameLevel)
    local vc = pf.sceneViewContext
    local r, g, b, a = ParseStrokeColor(item.stroke, item.opacity)
    local thick = SceneViewScale(vc, math.max(2, ch * ((type(item.strokeWidth) == "number" and item.strokeWidth or 0.6) / 100)))
    local x1, y1 = SceneViewCoord(vc, cw * ((tonumber(item.x1) or 0) / 100), ch * ((tonumber(item.y1) or 0) / 100))
    local x2, y2 = SceneViewCoord(vc, cw * ((tonumber(item.x2) or 0) / 100), ch * ((tonumber(item.y2) or 0) / 100))
    local ln = ShapeLine(f)
    ColorLine(ln, r, g, b, a, thick)
    ln:SetStartPoint("TOPLEFT", canvas, x1, -y1)
    ln:SetEndPoint("TOPLEFT", canvas, x2, -y2)

    if tostring(item.shape):lower() == "arrow" then
        local dx, dy = x2 - x1, y2 - y1
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0.001 then
            local ux, uy = dx / len, dy / len
            local headLen = SceneViewScale(vc, math.max(8, math.min(len * 0.3, thick * 4 + 10)))
            local ang = math.rad(28)
            local cosA, sinA = math.cos(ang), math.sin(ang)
            local bx, by = -ux, -uy
            local h1x, h1y = bx * cosA - by * sinA, bx * sinA + by * cosA
            local h2x, h2y = bx * cosA + by * sinA, -bx * sinA + by * cosA
            local a1 = ShapeLine(f)
            ColorLine(a1, r, g, b, a, thick)
            a1:SetStartPoint("TOPLEFT", canvas, x2, -y2)
            a1:SetEndPoint("TOPLEFT", canvas, x2 + h1x * headLen, -(y2 + h1y * headLen))
            local a2 = ShapeLine(f)
            ColorLine(a2, r, g, b, a, thick)
            a2:SetStartPoint("TOPLEFT", canvas, x2, -y2)
            a2:SetEndPoint("TOPLEFT", canvas, x2 + h2x * headLen, -(y2 + h2y * headLen))
        end
    end
    return f
end

-- Filled triangle/cone via horizontal scanlines (apex at top), with crisp edges on top.
-- Drawn at full color alpha inside the frame; the frame's alpha applies the real opacity
-- so overlapping fill rows don't stack into darker bands.
local function DrawTriangleShape(pf, canvas, item, cw, ch, frameLevel)
    local f = AcquireShapeFrame(pf, canvas, frameLevel)
    local vc = pf.sceneViewContext
    local r, g, b, a = ParseItemColor(item.fill, item.opacity)
    local x, y = SceneViewCoord(vc, cw * ((tonumber(item.x) or 0) / 100), ch * ((tonumber(item.y) or 0) / 100))
    local w = SceneViewScale(vc, cw * ((tonumber(item.w) or 6) / 100))
    local hh = SceneViewScale(vc, ch * ((tonumber(item.h) or 6) / 100))
    local cx = x + w / 2

    local rows = math.max(8, math.min(math.floor(hh), 160))
    local step = hh / rows
    local rowThick = step + 1.2
    for i = 0, rows - 1 do
        local ry = (i + 0.5) * step
        local half = (ry / hh) * (w / 2)
        if half > 0.4 then
            local ln = ShapeLine(f)
            ln:SetThickness(rowThick)
            ln:SetColorTexture(r, g, b, a)
            ln:SetStartPoint("TOPLEFT", canvas, cx - half, -(y + ry))
            ln:SetEndPoint("TOPLEFT", canvas, cx + half, -(y + ry))
        end
    end

    -- Stroke outline is drawn in RebuildStrokeOverlays (canvas coords, tracks animation).
    return f
end

-- Smooth donut/ring built from overlapping round dots around the mid-radius.
-- Rounded dots give clean inner/outer edges (no faceting); full-alpha dots + frame
-- alpha avoid the patchy overlap darkening of translucent segments.
local function DrawDonutShape(pf, canvas, item, cw, ch, frameLevel)
    local f = AcquireShapeFrame(pf, canvas, frameLevel)
    local vc = pf.sceneViewContext
    local r, g, b, a = ParseItemColor(item.fill, item.opacity)
    local wpx = SceneViewScale(vc, cw * ((tonumber(item.w) or 10) / 100))
    local hpx = SceneViewScale(vc, ch * ((tonumber(item.h) or 10) / 100))
    local bx, by = SceneViewCoord(vc, cw * ((tonumber(item.x) or 0) / 100), ch * ((tonumber(item.y) or 0) / 100))
    local cx = bx + wpx / 2
    local cy = by + hpx / 2
    local outerRx, outerRy = wpx / 2, hpx / 2
    local inner = tonumber(item.innerRatio) or 0.5
    if inner < 0 then inner = 0 elseif inner > 0.95 then inner = 0.95 end
    local midRx = outerRx * (1 + inner) / 2
    local midRy = outerRy * (1 + inner) / 2
    -- Band (dot diameter) = distance between outer and inner edge.
    local band = math.max(3, ((outerRx * (1 - inner)) + (outerRy * (1 - inner))) / 2)

    -- Enough dots so neighbours overlap (spacing <= ~half a dot) for a continuous ring.
    local circ = math.pi * (midRx + midRy)
    local segs = math.max(24, math.min(math.ceil(circ / math.max(2, band * 0.45)), 160))
    for s = 0, segs - 1 do
        local ang = (s / segs) * math.pi * 2
        local px = cx + midRx * math.cos(ang)
        local py = cy + midRy * math.sin(ang)
        local d = ShapeDot(f)
        d:SetColorTexture(r, g, b, a)
        d:SetSize(band, band)
        d:ClearAllPoints()
        d:SetPoint("CENTER", canvas, "TOPLEFT", px, -py)
    end

    return f
end

-- Skewed/rotated rectangles export their 4 oriented corners (percent coords) so we can
-- render the true parallelogram instead of an axis-aligned bounding box.
local function HasQuadCorners(item)
    return item and type(item.corners) == "table" and #item.corners >= 3
end

local function GetItemCornerPoints(item, cw, ch, vc)
    local c = item and item.corners
    if type(c) ~= "table" or #c < 3 then return nil end
    local pts = {}
    for i = 1, #c do
        local p = c[i]
        local pxPct = tonumber(p and p.x) or 0
        local pyPct = tonumber(p and p.y) or 0
        local px, py = SceneViewCoord(vc, cw * (pxPct / 100), ch * (pyPct / 100))
        pts[i] = { px, py }
    end
    return pts
end

-- Fill a convex polygon (canvas coords, y positive-down) using horizontal scanlines,
-- mirroring the triangle/cone fill approach so skewed rects render as solid parallelograms.
local function FillConvexPolygon(f, canvas, pts, r, g, b, a)
    local n = pts and #pts or 0
    if n < 3 then return end
    local minY, maxY = pts[1][2], pts[1][2]
    for i = 2, n do
        local py = pts[i][2]
        if py < minY then minY = py end
        if py > maxY then maxY = py end
    end
    local height = maxY - minY
    if height < 0.5 then return end
    local rows = math.max(8, math.min(math.floor(height), 200))
    local step = height / rows
    local rowThick = step + 1.2
    for i = 0, rows - 1 do
        local sy = minY + (i + 0.5) * step
        local xMin, xMax
        for e = 1, n do
            local pa = pts[e]
            local pb = pts[(e % n) + 1]
            local ay, by = pa[2], pb[2]
            if (ay <= sy and by > sy) or (by <= sy and ay > sy) then
                local t = (sy - ay) / (by - ay)
                local xi = pa[1] + t * (pb[1] - pa[1])
                if not xMin or xi < xMin then xMin = xi end
                if not xMax or xi > xMax then xMax = xi end
            end
        end
        if xMin and xMax and (xMax - xMin) > 0.4 then
            local ln = ShapeLine(f)
            ln:SetThickness(rowThick)
            ln:SetColorTexture(r, g, b, a)
            ln:SetStartPoint("TOPLEFT", canvas, xMin, -sy)
            ln:SetEndPoint("TOPLEFT", canvas, xMax, -sy)
        end
    end
end

local function DrawQuadShape(pf, canvas, item, cw, ch, frameLevel)
    local f = AcquireShapeFrame(pf, canvas, frameLevel)
    local vc = pf.sceneViewContext
    local pts = GetItemCornerPoints(item, cw, ch, vc)
    if not pts then return f end
    local r, g, b, a = ParseItemColor(item.fill, item.opacity)
    FillConvexPolygon(f, canvas, pts, r, g, b, a)
    return f
end

local function ResetStrokePool(pf)
    pf._strokePoolUsed = 0
    if not pf._strokePool then return end
    for _, f in ipairs(pf._strokePool) do
        if f._lines then for _, ln in ipairs(f._lines) do ln:Hide() end end
        f:Hide()
    end
end

local function AcquireStrokeFrame(pf, canvas, frameLevel)
    pf._strokePool = pf._strokePool or {}
    pf._strokePoolUsed = (pf._strokePoolUsed or 0) + 1
    local f = pf._strokePool[pf._strokePoolUsed]
    if not f then
        f = CreateFrame("Frame", nil, canvas)
        f._lines = {}
        pf._strokePool[pf._strokePoolUsed] = f
    end
    f:SetParent(canvas)
    f:ClearAllPoints()
    f:SetAllPoints(canvas)
    f:SetFrameLevel(frameLevel or (canvas:GetFrameLevel() + 4))
    f._lineUsed = 0
    f:Show()
    return f
end

-- Canvas-absolute strokes for donuts and triangles/cones (rects use backdrop border).
-- Rebuilt each animation frame so strokes track move animations.
local function RebuildStrokeOverlays(pf, scene, canvas, cw, ch)
    ResetStrokePool(pf)
    if not scene or not scene.items then return end
    local vc = pf.sceneViewContext
    for i, item in ipairs(scene.items) do
        if not HasStroke(item) or IsFrontalItem(item) then
        elseif item.kind == "line" then
        elseif item.kind == "shape" and HasQuadCorners(item) then
            local pts = GetItemCornerPoints(item, cw, ch, vc)
            if pts and #pts >= 2 then
                local f = AcquireStrokeFrame(pf, canvas, ResolveItemFrameLevel(canvas, item, i, 1))
                local er, eg, eb, ea = ParseStrokeColor(item.stroke, item.opacity)
                local et = StrokeThickPx(item, ch)
                for i = 1, #pts do
                    local p1 = pts[i]
                    local p2 = pts[(i % #pts) + 1]
                    local ln = ShapeLine(f)
                    ColorLine(ln, er, eg, eb, ea, et)
                    ln:SetStartPoint("TOPLEFT", canvas, p1[1], -p1[2])
                    ln:SetEndPoint("TOPLEFT", canvas, p2[1], -p2[2])
                end
            end
        elseif item.kind == "shape" then
            local shp = tostring(item.shape or ""):lower()
            local drawStroke = (shp == "donut" or shp == "triangle" or shp == "cone")
            if drawStroke then
                local x, y, iw, ih = GetItemCanvasRect(item, cw, ch, vc)
                local f = AcquireStrokeFrame(pf, canvas, ResolveItemFrameLevel(canvas, item, i, 1))
                if shp == "donut" then
                    local inner = tonumber(item.innerRatio) or 0.5
                    if inner < 0 then inner = 0 elseif inner > 0.95 then inner = 0.95 end
                    DrawEllipseStroke(f, canvas, x + iw / 2, y + ih / 2, iw / 2, ih / 2, item, ch, 48)
                    local innerRx, innerRy = (iw / 2) * inner, (ih / 2) * inner
                    if innerRx > 1 and innerRy > 1 then
                        DrawEllipseStroke(f, canvas, x + iw / 2, y + ih / 2, innerRx, innerRy, item, ch, 48)
                    end
                elseif shp == "triangle" or shp == "cone" then
                    local cx, hh = x + iw / 2, ih
                    local edgeR, edgeG, edgeB, edgeA = ParseStrokeColor(item.stroke, item.opacity)
                    local edgeThick = StrokeThickPx(item, ch)
                    local pts = { { cx, y }, { x, y + hh }, { x + iw, y + hh }, { cx, y } }
                    for i = 1, 3 do
                        local ln = ShapeLine(f)
                        ColorLine(ln, edgeR, edgeG, edgeB, edgeA, edgeThick)
                        ln:SetStartPoint("TOPLEFT", canvas, pts[i][1], -pts[i][2])
                        ln:SetEndPoint("TOPLEFT", canvas, pts[i + 1][1], -pts[i + 1][2])
                    end
                end
            end
        end
    end
end

local function BuildShapeWidgets(pf, scene, canvas, cw, ch)
    ResetShapePool(pf)
    if not scene or not scene.items then return end
    for i, item in ipairs(scene.items) do
        if not IsFrontalItem(item) then
            local k = item.kind
            local shp = tostring(item.shape or ""):lower()
            local itemFrameLevel = ResolveItemFrameLevel(canvas, item, i, 0)
            if k == "line" then
                DrawLineShape(pf, canvas, item, cw, ch, itemFrameLevel)
            elseif k == "shape" and HasQuadCorners(item) then
                DrawQuadShape(pf, canvas, item, cw, ch, itemFrameLevel)
            elseif k == "shape" and shp == "donut" then
                DrawDonutShape(pf, canvas, item, cw, ch, itemFrameLevel)
            elseif k == "shape" and (shp == "triangle" or shp == "cone") then
                DrawTriangleShape(pf, canvas, item, cw, ch, itemFrameLevel)
            end
        end
    end
end

-- Returns texturePath [, texCoord, customCandidates] for an icon key from the site.
-- texCoord is left, right, top, bottom for SetTexCoord (only for role icons).
local function GetPlanIconTexture(iconKey)
    if not iconKey or iconKey == "" then return nil end
    local key = iconKey:lower():gsub("^.*/", "")  -- "classes/warlock" -> "warlock"

    -- Specs (/icon/specs/<class>/<spec>.png) resolved to in-game spell textures.
    local specTex = Diar.ResolveSpecTextureFromIconKey(iconKey)
    if specTex then
        return specTex, nil, nil
    end

    -- Raid / markers (skull, cross, ...)
    local idx = RAID_ICON_MAP[key]
    if idx then
        return "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. idx, nil, nil
    end

    -- Classes
    local className = CLASS_ICON_MAP[key]
    if className then
        return "Interface\\Icons\\ClassIcon_" .. className, nil, nil
    end

    -- Roles (tank, healer, rdps, mdps) — only roles may use addon icon files.
    local coords = ROLE_ICON_COORDS[key]
    if coords then
        return ROLE_ICON_PATH, coords, GetCustomIconCandidates(iconKey)
    end

    return nil, nil, GetCustomIconCandidates(iconKey)
end

Diar.GetPlanIconTexture = GetPlanIconTexture

-- Parse fill string (rgba, rgb, or hex) to r,g,b,a in 0..1. Returns nil to use default.
local function ParseFillColor(fill)
    if not fill or type(fill) ~= "string" or fill == "" then return nil end
    local s = fill:gsub("%s+", ""):lower()
    -- rgba(255,0,0,0.2)
    local r, g, b, a = s:match("rgba%(([%d%.]+),([%d%.]+),([%d%.]+),([%d%.]+)%)")
    if r and g and b and a then
        return tonumber(r) / 255, tonumber(g) / 255, tonumber(b) / 255, tonumber(a)
    end
    -- rgb(255,0,0)
    r, g, b = s:match("rgb%(([%d%.]+),([%d%.]+),([%d%.]+)%)")
    if r and g and b then
        return tonumber(r) / 255, tonumber(g) / 255, tonumber(b) / 255, 1
    end
    -- #rrggbb or #rrggbbaa
    if s:match("^#%x%x%x%x%x%x%x%x$") then
        r = tonumber(s:sub(2, 3), 16) / 255
        g = tonumber(s:sub(4, 5), 16) / 255
        b = tonumber(s:sub(6, 7), 16) / 255
        a = tonumber(s:sub(8, 9), 16) / 255
        return r, g, b, a
    end
    if s:match("^#%x%x%x%x%x%x$") then
        r = tonumber(s:sub(2, 3), 16) / 255
        g = tonumber(s:sub(4, 5), 16) / 255
        b = tonumber(s:sub(6, 7), 16) / 255
        return r, g, b, 1
    end
    return nil
end

local function GetSceneDuration(animations)
    if not animations or #animations == 0 then return 0 end
    local maxEnd = 0
    for _, a in ipairs(animations) do
        local endT = (a.startTime or 0) + (a.duration or 1000)
        if endT > maxEnd then maxEnd = endT end
    end
    return maxEnd / 1000
end

-- Visible texture region for the cropped/scaled background, matching the item transform:
-- item screen = world*zoom + pan, so the canvas shows world in [-pan/zoom, (size-pan)/zoom].
local function GetBackgroundTexCoords(vc, cw, ch)
    if not vc then return 0, 1, 0, 1 end
    local zoom = vc.zoom
    local u0 = (-vc.panX / zoom) / cw
    local v0 = (-vc.panY / zoom) / ch
    local u1 = u0 + 1 / zoom
    local v1 = v0 + 1 / zoom
    return u0, u1, v0, v1
end

local function ClearFrameBackdrop(f)
    if not f then return end
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = nil, edgeFile = nil, tile = false, edgeSize = 0 })
        if f.SetBackdropColor then f:SetBackdropColor(0, 0, 0, 0) end
        if f.SetBackdropBorderColor then f:SetBackdropBorderColor(0, 0, 0, 0) end
    end
end

local function ApplyPlannerChromeTransparent(pf)
    if not pf then return end
    ClearFrameBackdrop(pf)
    ClearFrameBackdrop(pf.compactViewport)
    ClearFrameBackdrop(pf.canvas)
    if pf.importProgressOverlay and pf.importProgressOverlay:IsShown() then
        pf.importProgressOverlay:Hide()
    end
    local canvas = pf.canvas
    if canvas then
        if canvas.shadow then canvas.shadow:Hide() end
        canvas:SetAlpha(1)
    end
end

local function ApplySceneBackground(pf, scene, vc, cw, ch)
    if not pf or not pf.canvasBg then return end
    local canvas = pf.canvas
    if canvas then canvas:SetAlpha(1) end
    local nsrtOverlay = pf.nsrtSceneActive and pf.compactMode
    if nsrtOverlay then
        ApplyPlannerChromeTransparent(pf)
    end
    cw = cw or (pf.plannerCanvasW or PLANNER_CANVAS_W)
    ch = ch or (pf.plannerCanvasH or PLANNER_CANVAS_H)
    local u0, u1, v0, v1 = GetBackgroundTexCoords(vc, cw, ch)
    local bg = (scene and (scene.bg or scene.background)) or nil

    local function ApplyTransparentBackground()
        pf.canvasBg:Show()
        pf.canvasBg:SetTexture(nil)
        pf.canvasBg:SetColorTexture(0, 0, 0, 0)
        pf.canvasBg:SetAlpha(0)
        if canvas then
            canvas:SetBackdropColor(0, 0, 0, 0)
            if canvas.SetBackdropBorderColor then canvas:SetBackdropBorderColor(0, 0, 0, 0) end
            if canvas.shadow then canvas.shadow:Hide() end
        end
    end

    if pf.compactMode and not Diar:IsCompactBackgroundEnabled() then
        ApplyTransparentBackground()
        return
    end

    if type(bg) ~= "string" or bg == "" then
        ApplyTransparentBackground()
        return
    end

    -- Export sends bg as key (e.g. "chimera_l2"), user can drop matching files in Raidstratsgg/backgrounds/.
    local clean = bg:gsub("^.*/", ""):gsub("%.[^%.]+$", "")
    local candidates = {
        BG_BASE_PATH .. clean .. ".tga",
        BG_BASE_PATH .. clean .. ".blp",
        BG_BASE_PATH .. clean .. ".png",
        BG_BASE_PATH .. clean .. ".jpg",
    }

    for i = 1, #candidates do
        local path = candidates[i]
        local ok = pf.canvasBg:SetTexture(path)
        if ok then
            pf.canvasBg:Show()
            pf.canvasBg:SetAlpha(1)
            pf.canvasBg:SetTexCoord(u0, u1, v0, v1)
            pf.canvasBg:SetVertexColor(1, 1, 1, 1)
            -- Don't darken the image: make canvas backdrop and shadow invisible so the map shows at full brightness.
            if canvas then
                canvas:SetBackdropColor(0, 0, 0, 0)
                if canvas.shadow then canvas.shadow:Hide() end
            end
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if pf and pf.canvasBg then pf.canvasBg:SetVertexColor(1, 1, 1, 1) end
                end)
                C_Timer.After(0.15, function()
                    if pf and pf.canvasBg then pf.canvasBg:SetVertexColor(1, 1, 1, 1) end
                end)
            end
            return
        end
    end

    -- Fallback if no matching texture file exists.
    if nsrtOverlay then
        pf.canvasBg:Hide()
        pf.canvasBg:SetTexture(nil)
        pf.canvasBg:SetColorTexture(0, 0, 0, 0)
        pf.canvasBg:SetAlpha(0)
        if canvas then
            canvas:SetBackdropColor(0, 0, 0, 0)
            if canvas.shadow then canvas.shadow:Hide() end
        end
        return
    end
    pf.canvasBg:Show()
    pf.canvasBg:SetTexture(nil)
    pf.canvasBg:SetColorTexture(0.12, 0.14, 0.18, 1)
    pf.canvasBg:SetAlpha(1)
    if canvas then
        canvas:SetBackdropColor(0.08, 0.08, 0.12, 0.98)
        if canvas.shadow then canvas.shadow:Show() end
    end
end

local function GetPlannerWidgetRecycleBin(pf)
    if not pf then return nil end
    if not pf.widgetRecycleBin then
        local bin = CreateFrame("Frame", nil, UIParent)
        bin:Hide()
        pf.widgetRecycleBin = bin
    end
    return pf.widgetRecycleBin
end

local function IsPlannerWidgetFrame(w)
    return w and type(w.SetParent) == "function"
end

function Diar:SanitizePlanData(data)
    if not data or type(data.scenes) ~= "table" then return data end
    for _, scene in ipairs(data.scenes) do
        if scene.items then
            for _, item in ipairs(scene.items) do
                if type(item) == "table" then
                    local kindLower = tostring(item.kind or ""):lower()
                    local typeLower = tostring(item.type or item.objectType or ""):lower()
                    local isBossObject = (kindLower == "boss")
                        or (typeLower == "boss")
                        or (typeLower == "bossobject")
                        or (typeLower == "boss_icon")
                    local isTrashObject = (kindLower == "trash")
                        or (typeLower == "trash")
                        or (typeLower == "trash_icon")
                    if not isBossObject and (kindLower == "" or kindLower == "image" or kindLower == "icon") then
                        local hasBossHints = (item.boss == true)
                            or (item.isBoss == true)
                            or (item.bossId ~= nil)
                            or (item.encounterId ~= nil)
                            or (item.bossName ~= nil)
                            or (item.boss_image ~= nil)
                            or (item.bossImage ~= nil)
                            or (item.boss_render_image ~= nil)
                            or (item.bossRenderImage ~= nil)
                        if hasBossHints then
                            isBossObject = true
                        end
                    end
                    if isBossObject then
                        item.kind = "shape"
                        item.shape = "circle"
                        item.bossBadge = true
                        item.bossPortrait = nil
                        item.icon = nil
                        item.label = ""
                        item.labelAttached = nil
                        if type(item.x) ~= "number" then item.x = 42 end
                        if type(item.y) ~= "number" then item.y = 28 end
                        if type(item.w) ~= "number" then item.w = 12 end
                        if type(item.h) ~= "number" then item.h = 12 end
                        if type(item.fill) ~= "string" or item.fill == "" then
                            item.fill = "#7f1d1d"
                        end
                        if type(item.stroke) ~= "string" or item.stroke == "" then
                            item.stroke = "#f8fafc"
                        end
                        if type(item.strokeWidth) ~= "number" then
                            item.strokeWidth = 0.7
                        end
                        if type(item.opacity) ~= "number" then
                            item.opacity = 0.95
                        end
                    elseif isTrashObject then
                        local rawLabel = ""
                        if type(item.label) == "string" and item.label ~= "" then
                            rawLabel = item.label
                        elseif type(item.name) == "string" and item.name ~= "" then
                            rawLabel = item.name
                        end
                        item.kind = "shape"
                        item.shape = "circle"
                        item.trashBadgeLabel = rawLabel ~= "" and rawLabel or "Trash"
                        item.bossBadge = nil
                        item.bossPortrait = nil
                        item.icon = nil
                        item.label = ""
                        item.labelAttached = nil
                        if type(item.x) ~= "number" then item.x = 42 end
                        if type(item.y) ~= "number" then item.y = 28 end
                        if type(item.w) ~= "number" then item.w = 12 end
                        if type(item.h) ~= "number" then item.h = 12 end
                        if type(item.fill) ~= "string" or item.fill == "" then
                            item.fill = "#374151"
                        end
                        if type(item.stroke) ~= "string" or item.stroke == "" then
                            item.stroke = "#e5e7eb"
                        end
                        if type(item.strokeWidth) ~= "number" then
                            item.strokeWidth = 0.6
                        end
                        if type(item.opacity) ~= "number" then
                            item.opacity = 0.95
                        end
                    end
                end
                item.widget = nil
                item.currentX = nil
                item.currentY = nil
            end
        end
        if scene.animations then
            for _, anim in ipairs(scene.animations) do
                anim.__normalizedPath = nil
                anim.__pathLengths = nil
                anim.__resolvedItemIndex = nil
            end
        end
    end
    return data
end

local function ReleasePlannerWidget(pf, widget)
    if not IsPlannerWidgetFrame(widget) then return end
    widget:Hide()
    widget:SetScale(1)
    if widget.tex then
        widget.tex:SetRotation(0)
        widget.tex:Hide()
    end
    if widget.label then widget.label:Hide() end
    if widget.text then widget.text:Hide() end
    if widget.slotBadge then widget.slotBadge:Hide() end
    widget.baseWorldW = nil
    widget.baseWorldH = nil
    HideWidgetStroke(widget)
    ClearBackdropStroke(widget)
    widget:ClearAllPoints()
    widget:SetScript("OnEnter", nil)
    widget:SetScript("OnLeave", nil)
    widget:SetScript("OnMouseUp", nil)
    local bin = GetPlannerWidgetRecycleBin(pf)
    widget:SetParent(bin or UIParent)
end

local function ActivatePlannerWidget(w, canvas)
    if not IsPlannerWidgetFrame(w) then return end
    w:SetParent(canvas)
    w:SetAlpha(1)
    w:SetScale(1)
    w:Show()
end

local function UpdateWidgetSlotBadge(widget, slotIndex)
    if not widget then return end
    slotIndex = tonumber(slotIndex)
    if not slotIndex or slotIndex < 1 then
        if widget.slotBadge then widget.slotBadge:Hide() end
        return
    end
    slotIndex = math.floor(slotIndex + 0.0001)
    if not widget.slotBadge then
        widget.slotBadge = widget:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        widget.slotBadge:SetPoint("TOPRIGHT", widget, "TOPRIGHT", 1, -1)
        widget.slotBadge:SetTextColor(1, 1, 1)
        widget.slotBadge:SetShadowColor(0, 0, 0, 1)
        widget.slotBadge:SetShadowOffset(1, -1)
    end
    widget.slotBadge:SetText(tostring(slotIndex))
    widget.slotBadge:Show()
end

local function GetItemSlotIndex(item)
    if not item then return nil end
    local n = tonumber(item.slotIndex or item.embedIndex)
    if n then return math.floor(n + 0.0001) end
    return nil
end

-- Dynamic group assignment (NSRT "tag" feature): numbered objects (slotIndex)
-- use configurable mine/other colors from planner settings.
local function NormalizeAssignName(name)
    if type(name) ~= "string" then return nil end
    local t = strlower(strtrim(name))
    if t == "" then return nil end
    return t:match("^([^%-]+)") or t
end

-- Determine which scene items are assignable "spots" and their spot number.
-- Priority: explicit slotIndex on ANY object type (circle, rect, icon, text, ...).
-- Fallback (nothing numbered): circle/ellipse reading order (rows top->bottom,
-- left->right), dropping any oversized "container" circle (area >= 2x median area).
-- Returns map[itemIndex] = spotNumber, or nil when there are no spots.
local function IsAutoSpotExcludedItem(item)
    if not item then return false end
    if item.bossBadge == true then return true end
    if type(item.trashBadgeLabel) == "string" and item.trashBadgeLabel ~= "" then return true end
    local k = tostring(item.kind or ""):lower()
    return k == "boss" or k == "trash"
end

local function ResolveSceneSpots(scene)
    if not scene or not scene.items then return nil end

    -- Explicit slotIndex wins, for any object type.
    local map = {}
    local anySlot = false
    local minSlot = nil
    for i, item in ipairs(scene.items) do
        local slot = GetItemSlotIndex(item)
        if slot then
            map[i] = slot
            anySlot = true
            if minSlot == nil or slot < minSlot then
                minSlot = slot
            end
        end
    end
    if anySlot then
        -- Some exports use 0-based slot indices (0..N-1). Normalize to 1-based.
        if minSlot == 0 then
            for itemIndex, slot in pairs(map) do
                map[itemIndex] = slot + 1
            end
        else
            -- Drop invalid/legacy non-positive slots in 1-based mode.
            for itemIndex, slot in pairs(map) do
                if slot < 1 then map[itemIndex] = nil end
            end
        end
        return map
    end

    -- Fallback: auto-order circles by reading position.
    -- Exclude boss/add badges from auto spots; they only get spots when explicitly indexed in import.
    local circles = {}
    for i, item in ipairs(scene.items) do
        if item.kind == "shape" and not IsAutoSpotExcludedItem(item) then
            local shp = tostring(item.shape or ""):lower()
            if shp == "circle" or shp == "ellipse" then
                local iw = tonumber(item.w) or 0
                local ih = tonumber(item.h) or 0
                local ix = tonumber(item.x) or 0
                local iy = tonumber(item.y) or 0
                circles[#circles + 1] = {
                    index = i,
                    cx = ix + iw / 2,
                    cy = iy + ih / 2,
                    h = ih,
                    area = iw * ih,
                }
            end
        end
    end
    if #circles == 0 then return nil end

    -- Auto: drop oversized container(s), then reading order.
    local areas = {}
    for _, c in ipairs(circles) do areas[#areas + 1] = c.area end
    table.sort(areas)
    local median = areas[math.ceil(#areas / 2)] or 0
    local spots = {}
    for _, c in ipairs(circles) do
        if not (median > 0 and c.area >= 2 * median) then
            spots[#spots + 1] = c
        end
    end
    if #spots == 0 then spots = circles end

    table.sort(spots, function(a, b) return a.cy < b.cy end)
    local avgH = 0
    for _, c in ipairs(spots) do avgH = avgH + (c.h > 0 and c.h or 0) end
    avgH = (#spots > 0) and (avgH / #spots) or 0
    local rowTol = (avgH > 0 and avgH * 0.6) or 5

    local rows = {}
    local cur = nil
    for _, c in ipairs(spots) do
        if cur and math.abs(c.cy - cur.cy0) <= rowTol then
            cur[#cur + 1] = c
        else
            cur = { c, cy0 = c.cy }
            rows[#rows + 1] = cur
        end
    end
    local spotNum = 0
    for _, row in ipairs(rows) do
        table.sort(row, function(a, b) return a.cx < b.cx end)
        for _, c in ipairs(row) do
            spotNum = spotNum + 1
            map[c.index] = spotNum
        end
    end
    return map
end

function Diar:DebugLogCurrentSceneAssignment(reason)
    if not (self.GetPlannerSettings and self:GetPlannerSettings().debugMode == true) then return end
    if not self.AppendPlannerDebugLine then return end
    local pf = self.plannerFrame
    local data = self.plannerData
    local sceneIndex = (pf and pf.selectedSceneIndex) or 1
    local scene = data and data.scenes and data.scenes[sceneIndex]
    if not scene then
        self:AppendPlannerDebugLine(("SceneAssignCheck reason=%s scene=%s no-scene"):format(
            tostring(reason or "-"), tostring(sceneIndex)))
        return
    end

    local sceneSpots = ResolveSceneSpots(scene)
    local spotCount = 0
    local spotMax = 0
    if sceneSpots then
        for _, slot in pairs(sceneSpots) do
            spotCount = spotCount + 1
            if slot > spotMax then spotMax = slot end
        end
    end

    local mySpots = self.activeGroup and self.activeGroup.mySpots or nil
    local myList = {}
    local hasMatch = false
    if type(mySpots) == "table" then
        for slot in pairs(mySpots) do
            myList[#myList + 1] = tonumber(slot) or 0
        end
    end
    table.sort(myList)
    if sceneSpots and #myList > 0 then
        for _, mySlot in ipairs(myList) do
            for _, sceneSlot in pairs(sceneSpots) do
                if sceneSlot == mySlot then
                    hasMatch = true
                    break
                end
            end
            if hasMatch then break end
        end
    end

    local myListStr = (#myList > 0) and table.concat(myList, ",") or "-"
    self:AppendPlannerDebugLine(
        ("SceneAssignCheck reason=%s scene=%s sceneSpots=%d maxSpot=%d mySpots=%s hasMatch=%s"):format(
            tostring(reason or "-"),
            tostring(sceneIndex),
            spotCount,
            spotMax,
            myListStr,
            tostring(hasMatch)
        )
    )
end

local function ClearCircleRingLayoutCache(w)
    if not w then return end
    w.__ringLayoutIw = nil
    w.__ringLayoutIh = nil
    w.__ringLayoutThick = nil
    w.__ringLayoutColor = nil
end

local function ApplyGroupSpotBorder(w, ring, thick)
    if not w or not ring then return end
    if not w.SetBackdrop then Mixin(w, BackdropTemplateMixin) end
    thick = math.max(2, thick or 2)
    w:SetBackdrop({ bgFile = nil, edgeFile = WHITE_TEX, edgeSize = thick })
    w:SetBackdropBorderColor(ring[1], ring[2], ring[3], ring[4] or 1)
    w.__groupSpotStroke = true
end

local function ApplyGroupSpotShape(w, item, mine, shp, ch)
    local colors = Diar:GetAssignmentSpotColors()
    local fill = mine and colors.mineFill or colors.otherFill
    local ring = mine and colors.mineRing or colors.otherRing
    w:SetAlpha(1)
    w.__groupSpotMine = mine and true or nil
    ClearCircleRingLayoutCache(w)
    if shp == "circle" or shp == "ellipse" then
        ApplyCircleWidgetVisual(w, item, fill)
        w.__ringOverride = ring
        ClearBackdropStroke(w)
    else
        w.tex:SetColorTexture(fill[1], fill[2], fill[3], fill[4])
        w.tex:Show()
        local thick = math.max(2, math.ceil(StrokeThickPx(item, ch)))
        if mine then thick = math.ceil(thick * 1.35) end
        ApplyGroupSpotBorder(w, ring, thick)
    end
end

local function ApplyGroupSpotIcon(w, mine, ch, item)
    if not w or not w.tex then return end
    local colors = Diar:GetAssignmentSpotColors()
    local fill = mine and colors.mineFill or colors.otherFill
    w:SetAlpha(1)
    w.__groupSpotMine = mine and true or nil
    w.tex:SetAlpha(1)
    -- Icons (roles/classes/etc) should be color-tinted for assignment state, not bordered.
    w.tex:SetVertexColor(fill[1], fill[2], fill[3], mine and 1 or 0.9)
    HideWidgetStroke(w)
    ClearBackdropStroke(w)
end

local function ApplyGroupSpotText(w, mine, ch, item)
    if not w then return end
    local colors = Diar:GetAssignmentSpotColors()
    local fill = mine and colors.mineFill or colors.otherFill
    local ring = mine and colors.mineRing or colors.otherRing
    w:SetAlpha(1)
    w.__groupSpotMine = mine and true or nil
    if not w.SetBackdrop then Mixin(w, BackdropTemplateMixin) end
    local thick = math.max(2, math.ceil(StrokeThickPx(item or {}, ch or 1)))
    if mine then thick = math.ceil(thick * 1.35) end
    w:SetBackdrop({
        bgFile = WHITE_TEX,
        edgeFile = WHITE_TEX,
        tile = false,
        edgeSize = thick,
    })
    w:SetBackdropColor(fill[1], fill[2], fill[3], fill[4])
    w:SetBackdropBorderColor(ring[1], ring[2], ring[3], ring[4] or 1)
    w.__groupSpotStroke = true
end

local function SetGroupSpotPreviewText(w, text, mine, item)
    if not w then return end
    if not text or text == "" then
        if w.spotPreviewText then w.spotPreviewText:Hide() end
        return
    end
    if not w.spotPreviewText then
        local fs = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("CENTER", w, "CENTER", 0, 0)
        fs:SetJustifyH("CENTER")
        fs:SetJustifyV("MIDDLE")
        w.spotPreviewText = fs
    end
    local out = tostring(text)
    if #out > 24 then out = out:sub(1, 21) .. "..." end
    w.spotPreviewText:SetText(out)
    if mine then
        w.spotPreviewText:SetTextColor(1, 0.95, 0.48, 1)
    else
        w.spotPreviewText:SetTextColor(0.95, 0.97, 1, 0.95)
    end
    local px = w:GetWidth() or 0
    local py = w:GetHeight() or 0
    local area = math.max(1, math.min(px, py))
    local fontSize = math.max(7, math.floor(area * 0.17))
    w.spotPreviewText:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
    w.spotPreviewText:Show()
end

function Diar.ApplyWidgetLabel(w, item, label, hasSelfOnPlan, playerKey, isNamesVisible)
    if not w then return end
    local isAttachedLabel = item and item.labelAttached == true
    local shouldShowLabel = (label ~= "") and ((not isAttachedLabel) or isNamesVisible)
    if shouldShowLabel then
        if not w.label then
            w.label = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            w.label:SetPoint("TOP", w, "BOTTOM", 0, -2)
            w.label:SetTextColor(0.85, 0.85, 0.85)
        end
        w.__baseTextColor = { 0.85, 0.85, 0.85 }
        w.label:SetText(label)
        w.label:Show()
        if hasSelfOnPlan and LabelMatchesPlayer(label, playerKey) then
            ApplyNameHighlight(w, true, true, 0.85, 0.85, 0.85, w.label)
        else
            ClearNameHighlight(w, w.label, 0.85, 0.85, 0.85)
        end
    elseif w.label then
        w.label:Hide()
    end
end

function Diar.RenderIconWidget(addon, w, item, label, hasSelfOnPlan, playerKey, spotNum, isMySpot, ch)
    HideWidgetStroke(w)
    ClearBackdropStroke(w)
    local skipHelper = (not item.icon or item.icon == "") and label == ""
    if skipHelper then
        w.__suppressed = true
        w:Hide()
        if w.text then w.text:Hide() end
        if w.label then w.label:Hide() end
        return
    end

    local classKey = Diar.ResolveClassKeyFromIconKey(item.icon)
    local useClassSpecCircle = classKey and addon.IsClassSpecCircleModeEnabled and addon:IsClassSpecCircleModeEnabled()
    if useClassSpecCircle then
        local cr, cg, cb, ca = Diar.GetClassCircleColor(classKey, item.opacity)
        ApplyCircleWidgetVisual(w, item, { cr, cg, cb, ca })
        ClearBackdropStroke(w)
        if w.text then w.text:Hide() end
    else
        local texPath, texCoord, customCandidates = GetPlanIconTexture(item.icon)
        local customLoaded = SetTextureFromCandidates(w.tex, customCandidates)
        if customLoaded or texPath then
            if not customLoaded then
                w.tex:SetTexture(texPath)
            end
            if (not customLoaded) and texCoord and #texCoord >= 4 then
                w.tex:SetTexCoord(texCoord[1], texCoord[2], texCoord[3], texCoord[4])
            else
                w.tex:SetTexCoord(0, 1, 0, 1)
            end
            w.tex:Show()
        else
            w.tex:SetTexCoord(0, 1, 0, 1)
            w.tex:SetColorTexture(0.35, 0.5, 0.7, 0.9)
            w.tex:Show()
        end
        if w.text then w.text:Hide() end
    end
    Diar.ApplyWidgetLabel(w, item, label, hasSelfOnPlan, playerKey, addon:IsPlannerPreviewNamesVisible())
    w:SetScript("OnEnter", function(f)
        local tip = (f.label and f.label:GetText() and f.label:GetText() ~= "") and f.label:GetText() or nil
        if tip then
            GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
            GameTooltip:SetText(tip, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    w:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if spotNum then
        ApplyGroupSpotIcon(w, isMySpot, ch, item)
    end
end

function Diar.RenderSceneItem(addon, pf, root, cw, ch, vc, minSize, item, itemIndex, sceneCtx)
    local k = item.kind
    local shp = tostring(item.shape or ""):lower()
    item.currentX = nil
    item.currentY = nil
    local xp = (type(item.x) == "number" and item.x or 0) / 100
    local yp = (type(item.y) == "number" and item.y or 0) / 100

    local isStatic = (k == "line")
        or (k == "shape" and (IsFrontalItem(item) or HasQuadCorners(item) or shp == "donut" or shp == "triangle" or shp == "cone"))
    local allowStaticDragProxy = (k == "shape" and (shp == "triangle" or shp == "cone"))

    if isStatic then
        if allowStaticDragProxy and not IsFrontalItem(item) then
            local wp = (type(item.w) == "number" and item.w or 4) / 100
            local hp = (type(item.h) == "number" and item.h or 4) / 100
            local w = item.widget
            if not IsPlannerWidgetFrame(w) then
                item.widget = nil
                w = CreateFrame("Frame", nil, root, "BackdropTemplate")
                item.widget = w
            end
            ActivatePlannerWidget(w, root)
            w:SetFrameLevel(ResolveItemFrameLevel(root, item, itemIndex, 35))
            w:ClearAllPoints()
            w.baseWorldW = math.max(minSize, cw * wp)
            w.baseWorldH = math.max(minSize, ch * hp)
            local iw = math.max(minSize, SceneViewScale(vc, w.baseWorldW))
            local ih = math.max(minSize, SceneViewScale(vc, w.baseWorldH))
            w:SetSize(iw, ih)
            w.basePixelW = iw
            w.basePixelH = ih
            local px, py = SceneViewPctToCanvas(vc, cw, ch, xp, yp)
            w:SetPoint("TOPLEFT", root, "TOPLEFT", px, -py)
            if w.tex then
                w.tex:Hide()
            end
            HideWidgetStroke(w)
            ClearBackdropStroke(w)
            if w.text then w.text:Hide() end
            if w.label then w.label:Hide() end
            w.__suppressed = nil
            w.__ringOverride = nil
            w.__groupSpotMine = nil
            w.itemIndex = itemIndex
            w.baseX = xp
            w.baseY = yp
            item.currentX = xp
            item.currentY = yp
            if addon.AttachPlannerItemContextMenu then
                addon:AttachPlannerItemContextMenu(w, itemIndex, item)
            end
            if w.slotBadge then
                w.slotBadge:Hide()
            end
            return
        end
        if IsPlannerWidgetFrame(item.widget) then
            ReleasePlannerWidget(pf, item.widget)
        end
        item.widget = nil
        return
    end

    local wp = (type(item.w) == "number" and item.w or 4) / 100
    local hp = (type(item.h) == "number" and item.h or 4) / 100
    local label = (item.label and item.label ~= "") and item.label or ""

    local w = item.widget
    if not IsPlannerWidgetFrame(w) then
        item.widget = nil
        w = CreateFrame("Frame", nil, root, "BackdropTemplate")
        item.widget = w
    end
    ActivatePlannerWidget(w, root)
    local layerBoost = (k == "text") and 40 or 0
    w:SetFrameLevel(ResolveItemFrameLevel(root, item, itemIndex, layerBoost))
    w:ClearAllPoints()
    w.baseWorldW = math.max(minSize, cw * wp)
    w.baseWorldH = math.max(minSize, ch * hp)
    local iw = math.max(minSize, SceneViewScale(vc, w.baseWorldW))
    local ih = math.max(minSize, SceneViewScale(vc, w.baseWorldH))
    w:SetSize(iw, ih)
    w.basePixelW = iw
    w.basePixelH = ih
    local px, py = SceneViewPctToCanvas(vc, cw, ch, xp, yp)
    w:SetPoint("TOPLEFT", root, "TOPLEFT", px, -py)

    if not w.tex then
        w.tex = w:CreateTexture(nil, "ARTWORK")
        w.tex:SetAllPoints(w)
    end
    w.tex:SetRotation(0)
    w.tex:SetTexCoord(0, 1, 0, 1)
    w.tex:SetVertexColor(1, 1, 1)
    w.tex:SetAlpha(1)
    if w.__maskOn and w.circleMask then
        w.tex:RemoveMaskTexture(w.circleMask)
        w.__maskOn = false
    elseif w.__maskOn and w.circleMasks then
        for _, m in ipairs(w.circleMasks) do w.tex:RemoveMaskTexture(m) end
        w.__maskOn = false
    end
    if w.borderTex then w.borderTex:Hide() end
    w:SetScript("OnEnter", nil)
    w:SetScript("OnLeave", nil)
    w.__suppressed = nil
    ClearNameHighlight(w)
    if w.spotPreviewText then w.spotPreviewText:Hide() end
    w.__ringOverride = nil
    w.__groupSpotMine = nil
    if w.__groupSpotStroke then
        w.__groupSpotStroke = nil
        ClearBackdropStroke(w)
    end

    local spotNum = sceneCtx.groupSpots and sceneCtx.groupSpots[itemIndex]
    local isMySpot = spotNum and sceneCtx.activeGroup and sceneCtx.activeGroup.mySpots and sceneCtx.activeGroup.mySpots[spotNum]
    local spotName = spotNum and sceneCtx.previewNamesOn and sceneCtx.groupSpotNames and sceneCtx.groupSpotNames[spotNum] or nil
    if sceneCtx.debugMineHits and spotNum and isMySpot then
        sceneCtx.debugMineHits[#sceneCtx.debugMineHits + 1] = ("%d@item%d:%s"):format(spotNum, itemIndex, k)
    end

    if k == "text" then
        w.tex:Hide()
        HideWidgetStroke(w)
        if w.label then w.label:Hide() end
        local tr, tg, tb = ApplyTextWidgetContent(w, item, label, vc, ch, minSize)
        if spotNum then
            ApplyGroupSpotText(w, isMySpot, ch, item)
        end
        if sceneCtx.hasSelfOnPlan and LabelMatchesPlayer(label, sceneCtx.playerKey) then
            ApplyNameHighlight(w, true, true, tr, tg, tb, w.text)
        else
            ClearNameHighlight(w, w.text, tr, tg, tb)
        end
    elseif k == "shape" then
        if w.text then w.text:Hide() end
        if w.label then w.label:Hide() end
        if spotNum then
            ApplyGroupSpotShape(w, item, isMySpot, shp, ch)
            if spotName and (shp == "circle" or shp == "ellipse") then
                SetGroupSpotPreviewText(w, spotName, isMySpot, item)
            end
        elseif shp == "circle" or shp == "ellipse" then
            ApplyCircleWidgetVisual(w, item)
            ClearBackdropStroke(w)
        elseif IsRectLikeShape(shp) then
            ApplyBoxShapeVisual(w, item, ch)
        else
            ClearBackdropStroke(w)
            local r, g, b, a = ParseItemColor(item.fill, item.opacity)
            w.tex:SetColorTexture(r, g, b, a)
            w.tex:Show()
        end
        if item.bossBadge == true or item.trashBadgeLabel then
            if not w.text then
                w.text = w:CreateFontString(nil, "OVERLAY")
                w.text:SetPoint("CENTER", w, "CENTER", 0, 0)
                w.text:SetJustifyH("CENTER")
                w.text:SetJustifyV("MIDDLE")
            end
            local area = math.max(10, math.min(w:GetWidth() or 10, w:GetHeight() or 10))
            local fontSize = math.max(8, math.floor(area * 0.24))
            w.text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
            w.text:SetTextColor(1, 1, 1, 1)
            if item.bossBadge == true then
                w.text:SetText("Boss")
            else
                w.text:SetText(tostring(item.trashBadgeLabel or "Trash"))
            end
            w.text:Show()
        else
            Diar.ApplyWidgetLabel(w, item, label, sceneCtx.hasSelfOnPlan, sceneCtx.playerKey, addon:IsPlannerPreviewNamesVisible())
        end
    else
        Diar.RenderIconWidget(addon, w, item, label, sceneCtx.hasSelfOnPlan, sceneCtx.playerKey, spotNum, isMySpot, ch)
    end

    w.itemIndex = itemIndex
    w.baseX = xp
    w.baseY = yp
    item.currentX = xp
    item.currentY = yp
    if addon.AttachPlannerItemContextMenu and not w.__suppressed then
        addon:AttachPlannerItemContextMenu(w, itemIndex, item)
    end
    if not w.__suppressed then
        if addon:IsPlannerPreviewIndexVisible() then
            local badgeIndex = sceneCtx.previewSpots and sceneCtx.previewSpots[itemIndex]
            UpdateWidgetSlotBadge(w, badgeIndex)
        elseif w.slotBadge then
            w.slotBadge:Hide()
        end
        if k == "shape" and (shp == "circle" or shp == "ellipse") then
            UpdateCircleWidgetStroke(w, item, vc, ch)
        end
    elseif w.slotBadge then
        w.slotBadge:Hide()
    end
end

-- Compact mode: same canvas as expanded, displayed smaller via SetScale (~52% default).
local COMPACT_SCALE = 0.52
local MIN_COMPACT_SCALE = 0.22
local COMPACT_TOP_CHROME_H = 32

local function GetPlannerCompactChromeWidth()
    return 0
end

local function GetPlannerCompactChromeHeight(pf)
    if pf and pf.nsrtSceneActive then return 0 end
    return COMPACT_TOP_CHROME_H
end

local function GetPlannerCompactScale(pf)
    if not pf then return COMPACT_SCALE end
    local s = pf.compactCanvasScale or COMPACT_SCALE
    return math.max(MIN_COMPACT_SCALE, math.min(COMPACT_SCALE, s))
end

local function FitCompactScaleInBox(availW, availH, canvasW, canvasH)
    if not canvasW or not canvasH or canvasW <= 0 or canvasH <= 0 then
        return COMPACT_SCALE
    end
    local scale = math.min(availW / canvasW, availH / canvasH)
    return math.max(MIN_COMPACT_SCALE, math.min(COMPACT_SCALE, scale))
end

local function GetPlannerCompactFrameSize(pf, scale)
    local cw, ch = GetPlannerCanvasDimensions(pf)
    scale = scale or GetPlannerCompactScale(pf)
    return GetPlannerCompactChromeWidth() + cw * scale, GetPlannerCompactChromeHeight(pf) + ch * scale
end

local function ApplyPlannerResizeBounds(pf)
    if not pf then return end
    local minW, minH, maxW, maxH
    if pf.compactMode then
        minW, minH = GetPlannerCompactFrameSize(pf, MIN_COMPACT_SCALE)
        maxW, maxH = GetPlannerCompactFrameSize(pf, COMPACT_SCALE)
    else
        minW = GetPlannerChromeWidth(pf) + MIN_CANVAS_W
        minH = GetPlannerChromeHeight() + MIN_CANVAS_H
        maxW = GetPlannerChromeWidth(pf) + PLANNER_CANVAS_W
        maxH = GetPlannerChromeHeight() + PLANNER_CANVAS_H
    end
    if pf.SetResizeBounds then
        pf:SetResizeBounds(minW, minH, maxW, maxH)
    elseif pf.SetMinResize then
        pf:SetMinResize(minW, minH)
        if pf.SetMaxResize then
            pf:SetMaxResize(maxW, maxH)
        end
    end
end

local function SetPlannerChromeVisible(pf, visible)
    if not pf then return end
    local elems = {
        pf.title, pf.brandTitle, pf.versionLabel, pf.creditsBtn, pf.toolbar, pf.controls, pf.timeline,
        pf.patreonPanel, pf.savedPlansPanel, pf.objectPalettePanel, pf.infoStrip,
    }
    for _, el in ipairs(elems) do
        if el then
            if visible then el:Show() else el:Hide() end
        end
    end
end

FinishPlannerFrameMove = function(pf)
    if not pf then return end
    pf:StopMovingOrSizing()
    pf.__plannerMoving = nil
    if pf.__moveCatcher then
        pf.__moveCatcher:SetScript("OnUpdate", nil)
        pf.__moveCatcher:Hide()
        pf.__moveCatcher:EnableMouse(false)
    end
    if pf.__nsrtMoveTicker then
        pf.__nsrtMoveTicker:Cancel()
        pf.__nsrtMoveTicker = nil
    end
    if pf.nsrtSceneActive then
        ApplyPlannerChromeTransparent(pf)
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if pf and pf.nsrtSceneActive then ApplyPlannerChromeTransparent(pf) end
            end)
        end
    end
    if not pf.compactPreviewActive and Diar.SavePlannerFramePosition then
        Diar:SavePlannerFramePosition(pf)
    end
end

BeginPlannerFrameMove = function(pf, button)
    if not pf or button ~= "LeftButton" then return end
    if pf.nsrtSceneActive then
        ApplyPlannerChromeTransparent(pf)
        if C_Timer and C_Timer.NewTicker and not pf.__nsrtMoveTicker then
            pf.__nsrtMoveTicker = C_Timer.NewTicker(0.05, function()
                if pf.__plannerMoving and pf.nsrtSceneActive then
                    ApplyPlannerChromeTransparent(pf)
                elseif pf.__nsrtMoveTicker then
                    pf.__nsrtMoveTicker:Cancel()
                    pf.__nsrtMoveTicker = nil
                end
            end)
        end
    end
    pf:StartMoving()
    pf.__plannerMoving = true
    local catcher = pf.__moveCatcher
    if not catcher then
        catcher = CreateFrame("Frame", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("FULLSCREEN_DIALOG")
        catcher:SetFrameLevel(200)
        catcher:EnableMouse(true)
        catcher:Hide()
        catcher:SetScript("OnMouseUp", function(_, btn)
            if btn == "LeftButton" then
                FinishPlannerFrameMove(pf)
            end
        end)
        pf.__moveCatcher = catcher
    end
    catcher:SetFrameStrata("FULLSCREEN")
    catcher:SetFrameLevel(10000)
    catcher:Show()
    catcher:EnableMouse(true)
    catcher:SetScript("OnUpdate", function()
        if not pf.__plannerMoving then
            catcher:SetScript("OnUpdate", nil)
            return
        end
        if not IsMouseButtonDown("LeftButton") then
            FinishPlannerFrameMove(pf)
        end
    end)
end

local function EnsureCompactTopBar(pf)
    if not pf then return nil end
    if not pf.compactTopBar then
        local bar = CreateFrame("Frame", nil, pf)
        bar:SetFrameLevel(pf:GetFrameLevel() + 15)
        bar:EnableMouse(true)
        pf.compactTopBar = bar
    end
    local bar = pf.compactTopBar
    bar:SetScript("OnMouseDown", function(_, button)
        BeginPlannerFrameMove(pf, button)
    end)
    bar:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            FinishPlannerFrameMove(pf)
        end
    end)
    return bar
end

-- Exact-sized clip rect below the compact top bar; canvas is scaled from its center inside.
local function EnsureCompactViewport(pf)
    if not pf then return nil end
    if not pf.compactViewport then
        local vp = CreateFrame("Frame", nil, pf)
        if pf.canvas then
            vp:SetFrameLevel(pf.canvas:GetFrameLevel())
        end
        if vp.SetClipsChildren then vp:SetClipsChildren(true) end
        vp:EnableMouse(true)
        pf.compactViewport = vp
    end
    return pf.compactViewport
end

local function RestorePlannerSceneBackground(pf)
    if not pf or not pf.canvas then return end
    local data = Diar.plannerData
    if not data or not data.scenes then return end
    local idx = pf.selectedSceneIndex or 1
    local scene = data.scenes[idx]
    if not scene then return end
    local cw, ch = GetPlannerCanvasDimensions(pf)
    SyncViewerViewportFromScene(pf, scene)
    pf.sceneViewContext = BuildSceneViewContext(pf.viewerViewport, cw, ch)
    ApplySceneBackground(pf, scene, pf.sceneViewContext, cw, ch)
end

local function ApplyPlannerNormalLayout(pf, keepFrameSize)
    if not pf or not pf.canvas then return end
    if pf.compactTopBar then pf.compactTopBar:Hide() end
    if pf.compactPreviewBar then pf.compactPreviewBar:Hide() end
    pf.rightPanelW = RIGHT_PANEL_W
    local canvasW, canvasH = GetPlannerCanvasDimensions(pf)
    if keepFrameSize then
        local fw, fh = pf:GetSize()
        canvasW, canvasH = ComputeCanvasSizeFromFrame(pf, fw, fh)
        pf.plannerCanvasW = canvasW
        pf.plannerCanvasH = canvasH
    else
        pf.plannerCanvasW = canvasW
        pf.plannerCanvasH = canvasH
        pf:SetSize(GetPlannerChromeWidth(pf) + canvasW, GetPlannerChromeHeight() + canvasH)
    end
    local contentLeft = GetPlannerContentLeft()
    if SetBackdrop then SetBackdrop(pf) end
    if pf.canvas and SetBackdrop then
        SetBackdrop(pf.canvas, {0.08, 0.08, 0.12, 0.98}, UI.BORDER, 2)
    end
    if pf.compactViewport then pf.compactViewport:Hide() end
    pf.canvas:SetParent(pf)

    if pf.versionLabel then
        pf.versionLabel:Show()
        pf.versionLabel:SetJustifyH("RIGHT")
        if Diar.UpdatePlannerVersionLabel then
            Diar:UpdatePlannerVersionLabel(pf)
        end
    end
    EnsurePlannerInfoStrip(pf)
    if pf.creditsBtn then
        pf.creditsBtn:Show()
    end
    if pf.brandTitle then
        pf.brandTitle:Show()
        PositionPlannerBrandTitle(pf.brandTitle, pf)
    end
    if pf.title then
        pf.title:Show()
        pf.title:ClearAllPoints()
        pf.title:SetPoint("TOPLEFT", UI_PAD, -TITLE_TOP)
    end
    if pf.toolbar then
        pf.toolbar:Show()
        pf.toolbar:SetSize(canvasW, TOOLBAR_H)
        pf.toolbar:ClearAllPoints()
        pf.toolbar:SetPoint("TOPLEFT", pf, "TOPLEFT", contentLeft, -TOOLBAR_TOP)
    end
    pf.canvas:SetScale(1)
    pf.canvas:SetSize(canvasW, canvasH)
    pf.canvas:ClearAllPoints()
    pf.canvas:SetPoint("TOPLEFT", pf, "TOPLEFT", contentLeft, -CANVAS_TOP)
    pf.canvas:Show()

    if pf.controls then
        pf.controls:Show()
        pf.controls:SetWidth(canvasW)
        pf.controls:ClearAllPoints()
        pf.controls:SetPoint("TOP", pf.canvas, "BOTTOM", 0, -ROW_GAP)
    end
    if pf.timeline then
        pf.timeline:SetWidth(canvasW)
        pf.timeline:ClearAllPoints()
        pf.timeline:SetPoint("TOP", pf.controls, "BOTTOM", 0, -ROW_GAP)
    end
    if pf.patreonPanel and pf.toolbar then
        pf.patreonPanel:Show()
        pf.patreonPanel:ClearAllPoints()
        pf.patreonPanel:SetPoint("TOPLEFT", pf.toolbar, "TOPRIGHT", 12, 0)
    end
    if pf.savedPlansPanel and pf.patreonPanel and pf.timeline then
        pf.savedPlansPanel:Show()
        pf.savedPlansPanel:ClearAllPoints()
        pf.savedPlansPanel:SetPoint("TOPLEFT", pf.patreonPanel, "BOTTOMLEFT", 0, -RIGHT_COL_GAP)
        pf.savedPlansPanel:SetPoint("BOTTOMLEFT", pf.timeline, "BOTTOMRIGHT", 12, RIGHT_PANEL_BOTTOM_GAP)
    end
    if pf.resizeGrip then
        pf.resizeGrip:Show()
        pf.resizeGrip:ClearAllPoints()
        pf.resizeGrip:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", -2, 2)
        pf.resizeGrip:SetFrameLevel(pf.canvas:GetFrameLevel() + 50)
    end
    ApplyPlannerResizeBounds(pf)
    UpdatePlannerModeToggleBtn(pf)
    Diar:PositionPlannerControlsBar(pf)
    if Diar.ApplyObjectPaletteLayout then Diar:ApplyObjectPaletteLayout(pf) end
    if Diar.ApplyRaidLeadViewLayout then Diar:ApplyRaidLeadViewLayout(pf) end
    if Diar.UpdatePlannerControlButtons then Diar:UpdatePlannerControlButtons() end
    if Diar.UpdatePlannerDebugPanel then Diar:UpdatePlannerDebugPanel() end
    RestorePlannerSceneBackground(pf)
end

Diar.ApplyPlannerNormalLayout = ApplyPlannerNormalLayout

local function ApplyPlannerCompactLayout(pf, keepFrameSize, snapFrame)
    if not pf or not pf.canvas then return end
    SetPlannerChromeVisible(pf, false)
    if pf.compactBar then pf.compactBar:Hide() end

    -- Same canvas pixel size as expanded; only the display scale changes.
    local canvasW, canvasH = GetPlannerCanvasDimensions(pf)
    local scale
    if keepFrameSize then
        local fw, fh = pf:GetSize()
        scale = FitCompactScaleInBox(
            fw - GetPlannerCompactChromeWidth(),
            fh - GetPlannerCompactChromeHeight(pf),
            canvasW, canvasH
        )
    else
        scale = GetPlannerCompactScale(pf)
    end
    pf.compactCanvasScale = scale

    local frameW, frameH = GetPlannerCompactFrameSize(pf, scale)
    if keepFrameSize and snapFrame then
        pf:SetSize(frameW, frameH)
    elseif not keepFrameSize then
        pf:SetSize(frameW, frameH)
    end

    if pf.SetBackdrop then
        pf:SetBackdrop(nil)
    end
    if pf.canvas and pf.canvas.SetBackdrop then
        pf.canvas:SetBackdrop(nil)
    end

    local chromeH = GetPlannerCompactChromeHeight(pf)
    local nsrtOverlay = pf.nsrtSceneActive and true or false
    local topBar = EnsureCompactTopBar(pf)
    if nsrtOverlay then
        topBar:Hide()
    else
        topBar:Show()
        topBar:SetHeight(COMPACT_TOP_CHROME_H)
        topBar:ClearAllPoints()
        topBar:SetPoint("TOPLEFT", pf, "TOPLEFT", 0, 0)
        topBar:SetPoint("TOPRIGHT", pf, "TOPRIGHT", 0, 0)
    end

    local viewW = canvasW * scale
    local viewH = canvasH * scale
    local viewport = EnsureCompactViewport(pf)
    viewport:Show()
    viewport:SetSize(viewW, viewH)
    viewport:ClearAllPoints()
    viewport:SetPoint("TOPLEFT", pf, "TOPLEFT", 0, -chromeH)

    pf.canvas:SetParent(viewport)
    pf.canvas:SetSize(canvasW, canvasH)
    pf.canvas:SetScale(scale)
    if pf.canvas.SetClipsChildren then pf.canvas:SetClipsChildren(true) end
    pf.canvas:ClearAllPoints()
    pf.canvas:SetPoint("CENTER", viewport, "CENTER", 0, 0)
    pf.canvas:Show()

    if pf.settingsBtn then pf.settingsBtn:Hide() end
    if pf.previewIndexBtn then pf.previewIndexBtn:Hide() end
    if pf.objectPalettePanel then pf.objectPalettePanel:Hide() end
    if Diar.ClearPalettePlacement then Diar:ClearPalettePlacement() end
    if pf.zoomBar then pf.zoomBar:Hide() end
    if pf.resizeGrip then
        if nsrtOverlay then
            pf.resizeGrip:Hide()
        else
            pf.resizeGrip:Show()
            pf.resizeGrip:ClearAllPoints()
            pf.resizeGrip:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", 0, 0)
            pf.resizeGrip:SetFrameLevel(pf.canvas:GetFrameLevel() + 50)
        end
    end
    if pf.closeBtn and pf.modeToggleBtn then
        local btnAnchor = nsrtOverlay and pf or topBar
        pf.closeBtn:SetFrameLevel(btnAnchor:GetFrameLevel() + 2)
        pf.modeToggleBtn:SetFrameLevel(btnAnchor:GetFrameLevel() + 2)
    end
    if nsrtOverlay then
        ApplyPlannerChromeTransparent(pf)
    end
    ApplyPlannerResizeBounds(pf)
    UpdatePlannerModeToggleBtn(pf)
    RefreshCompactChromeHoverHooks(pf)
    Diar:PositionPlannerControlsBar(pf)
    if Diar.UpdatePlannerDebugPanel then Diar:UpdatePlannerDebugPanel() end
end

Diar.ApplyPlannerCompactLayout = ApplyPlannerCompactLayout

local function BeginCompactProportionalResize(pf, grip)
    if not pf or not grip then return end
    local canvasW = GetPlannerCanvasDimensions(pf)
    local scale = GetPlannerCompactScale(pf)
    pf.__compactResize = {
        startScale = scale,
        startMouseX = GetCursorPosition() / pf:GetEffectiveScale(),
        canvasW = canvasW,
    }
    pf.__plannerSizing = true
    grip:SetScript("OnUpdate", function(self)
        if not IsMouseButtonDown("LeftButton") then
            self:SetScript("OnUpdate", nil)
            pf.__plannerSizing = nil
            pf.__compactResize = nil
            if not pf.compactPreviewActive and Diar.SavePlannerCompactLayoutState then
                Diar:SavePlannerCompactLayoutState(pf)
            end
            return
        end
        local r = pf.__compactResize
        if not r or not pf.compactMode then return end
        local cx = GetCursorPosition() / pf:GetEffectiveScale()
        local dx = cx - r.startMouseX
        local newScale = math.max(MIN_COMPACT_SCALE, math.min(COMPACT_SCALE, r.startScale + dx / r.canvasW))
        if math.abs(newScale - GetPlannerCompactScale(pf)) < 0.001 then return end
        pf.compactCanvasScale = newScale
        pf.__layoutSyncing = true
        ApplyPlannerCompactLayout(pf, false, false)
        pf.__layoutSyncing = nil
    end)
end

local function AttachPlannerResizeGrip(pf, grip)
    if not pf or not grip then return end
    grip:SetScript("OnMouseDown", function(self)
        pf.__plannerSizing = true
        if pf.compactMode then
            BeginCompactProportionalResize(pf, self)
        else
            pf:StartSizing("BOTTOMRIGHT")
        end
    end)
    grip:SetScript("OnMouseUp", function(self)
        if pf.compactMode then
            self:SetScript("OnUpdate", nil)
            pf.__plannerSizing = nil
            pf.__compactResize = nil
            if not pf.compactPreviewActive and Diar.SavePlannerCompactLayoutState then
                Diar:SavePlannerCompactLayoutState(pf)
            end
        else
            pf:StopMovingOrSizing()
            pf.__plannerSizing = nil
            pf.__layoutLiveRefreshScheduled = nil
            Diar:SyncPlannerLayoutFromFrame(true)
        end
    end)
end

local function InvalidateWidgetWorldSizes(scene)
    if not scene or not scene.items then return end
    for _, item in ipairs(scene.items) do
        local w = item.widget
        if w then
            w.baseWorldW = nil
            w.baseWorldH = nil
            w.__ringLayoutIw = nil
            w.__ringLayoutIh = nil
            w.__ringLayoutThick = nil
        end
    end
end

local function SchedulePlannerLayoutLiveRefresh(pf)
    if not pf or pf.__layoutLiveRefreshScheduled then return end
    pf.__layoutLiveRefreshScheduled = true
    local function run()
        pf.__layoutLiveRefreshScheduled = nil
        if pf.__plannerSizing and not pf.__layoutSyncing and Diar.RefreshPlannerLayoutLive then
            Diar:RefreshPlannerLayoutLive()
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.03, run)
    else
        run()
    end
end

function Diar:RefreshPlannerLayoutLive()
    local pf = self.plannerFrame
    local data = self.plannerData
    if not pf or not data or not data.scenes then return end
    local idx = pf.selectedSceneIndex or 1
    local scene = data.scenes[idx]
    if not scene or not scene.items then return end
    local canvas = pf.canvas
    if not canvas then return end

    local cw, ch = GetPlannerRenderCanvasSize(pf, canvas)
    pf.sceneViewContext = BuildSceneViewContext(pf.viewerViewport, cw, ch)
    local vc = pf.sceneViewContext
    local root = canvas
    local minSize = 2

    InvalidateWidgetWorldSizes(scene)
    ApplySceneBackground(pf, scene, vc, cw, ch)

    for _, item in ipairs(scene.items) do
        local w = item.widget
        if IsPlannerWidgetFrame(w) and w:IsShown() and not w.__suppressed then
            LayoutItemWidget(w, item, vc, cw, ch, root, minSize)
            if w.text and w.text:IsShown() and item.kind == "text" then
                local lbl = (item.label and item.label ~= "") and item.label or ""
                ApplyTextWidgetContent(w, item, lbl, vc, ch, minSize)
            end
        end
    end
end

function Diar:SyncPlannerLayoutFromFrame(snapFrame)
    local pf = self.plannerFrame
    if not pf or pf.__layoutSyncing then return end
    pf.__layoutSyncing = true
    if pf.compactMode then
        -- Compact resize only changes canvas scale; icons scale with the canvas.
        ApplyPlannerCompactLayout(pf, true, snapFrame)
    else
        ApplyPlannerNormalLayout(pf, true)
        if snapFrame then
            if self.RefreshPlannerScene then
                self:RefreshPlannerScene()
            end
        else
            SchedulePlannerLayoutLiveRefresh(pf)
        end
    end
    pf.__layoutSyncing = nil
end

function Diar:SetPlannerCompactMode(enabled)
    local pf = self.plannerFrame
    if not pf then return end
    enabled = not not enabled
    if pf.compactMode == enabled then return end
    if self._plannerDrag then
        local w = self._plannerDrag.widget
        if w then w:SetScript("OnUpdate", nil) end
        self._plannerDrag = nil
    end
    if enabled and self.StopPlannerAnimation then
        self:StopPlannerAnimation()
    end
    self:SavePlannerFramePosition(pf)
    pf.compactMode = enabled
    if enabled then
        local s = self:GetPlannerSettings()
        if pf.nsrtSceneActive then
            pf.compactCanvasScale = tonumber(s.nsrtCompactScale) or tonumber(s.compactScale) or COMPACT_SCALE
        else
            pf.compactCanvasScale = tonumber(s.compactScale) or COMPACT_SCALE
        end
        ApplyPlannerCompactLayout(pf)
        self:ApplyPlannerFramePosition(pf)
    else
        if pf.compactPreviewActive then
            self:EndCompactPositionPreview(false)
        end
        if pf.canvas then pf.canvas:SetScale(1) end
        ApplyPlannerNormalLayout(pf)
        self:ApplyPlannerFramePosition(pf)
        if not pf.nsrtSceneActive then
            self:ApplyNsrtAssignmentForPlannerView(pf.selectedSceneIndex or 1)
        end
    end
    if self.RefreshPlannerScene then
        self:RefreshPlannerScene()
    end
    if Diar.ApplyRaidLeadViewLayout then Diar:ApplyRaidLeadViewLayout(pf) end
end

function Diar:TogglePlannerCompactMode()
    local pf = self.plannerFrame
    if not pf or pf.compactPreviewActive then return end
    if pf.compactMode then
        pf.nsrtSceneActive = nil
    end
    self:SetPlannerCompactMode(not pf.compactMode)
end

function Diar:ShowPlannerViewer(opts)
    opts = opts or {}
    -- Clear any stale NSRT group coloring; ShowRaidPlanScene re-sets it after this runs.
    self.activeGroup = nil
    if not self.plannerData or not self.plannerData.scenes or #self.plannerData.scenes == 0 then
        self.plannerData = { planName = "No plan", scenes = { { name = "Empty", items = {} } } }
    end
    local data = self.plannerData

    -- Stop animation timers only; RefreshPlannerScene runs once below with the new data.
    local pfExisting = self.plannerFrame
    if pfExisting then
        pfExisting:SetScript("OnUpdate", nil)
        pfExisting.animPlaying = false
        pfExisting.animPaused = false
        pfExisting.pausedTime = nil
        pfExisting.animStart = nil
        self:UpdatePlannerControlButtons()
    end

    if self.plannerFrame and (not self.plannerFrame.savedPlansFooter or not self.plannerFrame.patreonPanel or not self.plannerFrame.patreonAnchoredToolbar) then
        self.plannerFrame:Hide()
        self.plannerFrame = nil
    end

    if not self.plannerFrame then
        local pf = CreateFrame("Frame", "RaidstratsPlannerFrame", UIParent, "BackdropTemplate")
        pf.rightPanelW = RIGHT_PANEL_W
        pf.savedPlansListW = RIGHT_PANEL_W - 36
        -- Single OnUpdate handler (reused on every Play) to avoid creating new closures and leaking memory
        pf.plannerOnUpdateHandler = function() Diar:PlannerOnUpdate() end
        local defaultCanvasW = math.max(MIN_CANVAS_W, math.floor(PLANNER_CANVAS_W * DEFAULT_EXPANDED_LOAD_SCALE + 0.5))
        local defaultCanvasH = math.max(MIN_CANVAS_H, math.floor(PLANNER_CANVAS_H * DEFAULT_EXPANDED_LOAD_SCALE + 0.5))
        pf.plannerCanvasW = defaultCanvasW
        pf.plannerCanvasH = defaultCanvasH
        local frameW = UI_PAD + (Diar.GetObjectPaletteExtraWidth and Diar:GetObjectPaletteExtraWidth() or 0) + defaultCanvasW + 12 + RIGHT_PANEL_W + UI_PAD
        local frameH = CANVAS_TOP + defaultCanvasH + ROW_GAP + CONTROLS_H + ROW_GAP + TIMELINE_H + UI_PAD
        pf:SetSize(frameW, frameH)
        local initPos = Diar:GetPlannerSettings().expandedPos
        if initPos and initPos.point then
            pf:SetPoint(initPos.point, UIParent, initPos.relPoint or initPos.point, initPos.x or 0, initPos.y or 0)
        else
            pf:SetPoint("CENTER")
        end
        pf:SetFrameStrata("DIALOG")
        pf:SetMovable(true)
        pf:SetResizable(true)
        pf:EnableMouse(true)
        pf:SetClampedToScreen(true)
        ApplyPlannerResizeBounds(pf)
        SetBackdrop(pf)
        tinsert(UISpecialFrames, "RaidstratsPlannerFrame")
        pf:SetScript("OnMouseDown", function(s, b)
            BeginPlannerFrameMove(s, b)
        end)
        pf:SetScript("OnMouseUp", function(s, b)
            if b == "LeftButton" and s.__plannerMoving then
                FinishPlannerFrameMove(s)
            end
        end)
        pf:SetScript("OnSizeChanged", function(s)
            if s.__layoutSyncing or not s.__plannerSizing or s.compactMode then return end
            Diar:SyncPlannerLayoutFromFrame(false)
        end)
        pf:SetScript("OnShow", function(s)
            if s.canvas then s.canvas:SetAlpha(1) end
            if s.nsrtSceneActive and s.compactMode then
                ApplyPlannerChromeTransparent(s)
            elseif s.canvasBg then
                s.canvasBg:SetVertexColor(1, 1, 1, 1)
            end
            if Diar.UpdatePlannerDebugPanel then
                Diar:UpdatePlannerDebugPanel()
            end
        end)
        pf:SetScript("OnHide", function(frame)
            if frame.compactPreviewActive and Diar.EndCompactPositionPreview then
                Diar:EndCompactPositionPreview(false)
            end
            -- If user closed while in manual compact mode, reopen in expanded mode.
            if frame.compactMode and not frame.nsrtSceneActive then
                frame.compactMode = false
                if frame.canvas then frame.canvas:SetScale(1) end
            end
            if Diar.HidePlannerTransientMenus then
                Diar:HidePlannerTransientMenus()
            end
            if frame.debugPanel then frame.debugPanel:Hide() end
            Diar:ClearPlannerDisplay()
        end)

        local closeBtn = CreateFrame("Button", nil, pf, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -6, -6)
        closeBtn:SetScript("OnClick", function()
            if pf.nsrtSceneActive and Diar.HideRaidPlanScene then
                Diar:HideRaidPlanScene()
            elseif pf and pf.Hide then
                if pf.compactMode then
                    pf.compactMode = false
                    if pf.canvas then pf.canvas:SetScale(1) end
                end
                pf:Hide()
            end
        end)
        pf.closeBtn = closeBtn
        pf.compactMode = false

        local modeToggleBtn = CreatePlannerIconBtn(pf, "Compact", 76, 22)
        modeToggleBtn:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", -2, 1)
        modeToggleBtn:SetScript("OnClick", function()
            Diar:TogglePlannerCompactMode()
        end)
        pf.modeToggleBtn = modeToggleBtn

        local discordBtn = CreatePlannerIconBtn(pf, "Discord", 76, 22)
        discordBtn:SetPoint("TOPRIGHT", modeToggleBtn, "TOPLEFT", -2, 0)
        discordBtn:SetScript("OnClick", function()
            Diar:ShowPlannerDiscordPopup()
        end)
        pf.discordBtn = discordBtn

        local resizeGrip = CreateFrame("Button", nil, pf)
        resizeGrip:SetSize(16, 16)
        resizeGrip:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", -2, 2)
        resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
        AttachPlannerResizeGrip(pf, resizeGrip)
        pf.resizeGrip = resizeGrip

        pf.brandTitle = pf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        pf.brandTitle:SetJustifyH("CENTER")
        pf.brandTitle:SetTextColor(0.95, 0.95, 0.95)
        pf.brandTitle:SetText(BRAND_TITLE_TEXT or "Raidstrats.gg - Raidplanner & Assignments")
        PositionPlannerBrandTitle(pf.brandTitle, pf)

        pf.title = pf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        pf.title:SetPoint("TOPLEFT", UI_PAD, -TITLE_TOP)
        pf.title:SetJustifyH("LEFT")
        pf.title:SetTextColor(0.95, 0.95, 0.95)

        local creditsBtn = CreatePlannerIconBtn(pf, "Credits", 72, 22)
        creditsBtn:SetPoint("TOPRIGHT", discordBtn, "TOPLEFT", -2, 0)
        creditsBtn:SetScript("OnClick", function()
            if Diar.ShowPlannerCreditsDialog then Diar:ShowPlannerCreditsDialog() end
        end)
        pf.creditsBtn = creditsBtn
        EnsurePlannerInfoStrip(pf)

        -- Toolbar: scene tabs (left) + plan link (right), spanning the canvas width
        local toolbar = CreateFrame("Frame", nil, pf, "BackdropTemplate")
        toolbar:SetSize(PLANNER_CANVAS_W, TOOLBAR_H)
        toolbar:SetPoint("TOPLEFT", pf, "TOPLEFT", GetPlannerContentLeft(), -TOOLBAR_TOP)
        SetBackdrop(toolbar, UI.TOOLBAR, UI.BORDER, 1)
        pf.toolbar = toolbar

        -- Link + Help buttons pinned to the right of the toolbar
        local linkBtn = CreatePlannerIconBtn(toolbar, "Link", 52, SCENE_TAB_H + 4)
        linkBtn:SetScript("OnClick", function()
            Diar:ShowPlannerPlanLinkPopup()
        end)
        pf.planLinkBtn = linkBtn

        local helpBtn = CreatePlannerIconBtn(toolbar, "Help", 52, SCENE_TAB_H + 4)
        helpBtn:SetScript("OnClick", function()
            if Diar.ShowPlannerHelpDialog then Diar:ShowPlannerHelpDialog() end
        end)
        pf.planHelpBtn = helpBtn

        -- Scene tabs fill the space left of the help button
        local tabsContainer = CreateFrame("Frame", nil, toolbar)
        tabsContainer:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 8, -6)
        pf.sceneTabsContainer = tabsContainer
        pf.sceneTabButtons = {}
        Diar:EnsurePlannerHelpButton(pf)

        local canvas = CreateFrame("Frame", nil, pf, "BackdropTemplate")
        canvas:SetSize(PLANNER_CANVAS_W, PLANNER_CANVAS_H)
        canvas:SetPoint("TOPLEFT", pf, "TOPLEFT", GetPlannerContentLeft(), -CANVAS_TOP)
        if canvas.SetClipsChildren then canvas:SetClipsChildren(true) end
        SetBackdrop(canvas, {0.08, 0.08, 0.12, 0.98}, UI.BORDER, 2)
        pf.canvas = canvas
        pf.canvasBg = canvas:CreateTexture(nil, "BACKGROUND")
        pf.canvasBg:SetAllPoints(canvas)
        pf.canvasBg:SetColorTexture(0.12, 0.14, 0.18, 1)
        EnsurePlannerZoomControls(pf, canvas)
        BindPlannerCanvasViewportInput(pf, canvas)
        Diar:EnsurePreviewNamesButton(pf)

        local controls = CreateFrame("Frame", nil, pf)
        controls:SetHeight(CONTROLS_H)
        controls:SetWidth(PLANNER_CANVAS_W)
        controls:SetPoint("TOP", canvas, "BOTTOM", 0, -ROW_GAP)
        pf.controls = controls

        local playPauseBtn = CreatePlannerIconBtn(controls, "Play", 110, CONTROLS_H)
        playPauseBtn:SetPoint("RIGHT", controls, "CENTER", -6, 0)
        pf.playPauseBtn = playPauseBtn

        local stopBtn = CreatePlannerIconBtn(controls, "Stop", 110, CONTROLS_H)
        stopBtn:SetPoint("LEFT", controls, "CENTER", 6, 0)
        pf.stopBtn = stopBtn

        local settingsBtn = CreatePlannerIconBtn(controls, "Settings", 72, CONTROLS_H)
        settingsBtn:SetPoint("RIGHT", controls, "RIGHT", 0, 0)
        settingsBtn:SetScript("OnClick", function()
            Diar:ShowPlannerSettingsDialog()
        end)
        pf.settingsBtn = settingsBtn

        local previewIndexBtn = CreatePlannerIconBtn(controls, "Preview index", 104, CONTROLS_H)
        previewIndexBtn:SetPoint("RIGHT", settingsBtn, "LEFT", -6, 0)
        previewIndexBtn:SetScript("OnClick", function()
            Diar:TogglePlannerPreviewIndex()
        end)
        pf.previewIndexBtn = previewIndexBtn
        Diar:UpdatePreviewIndexButton(pf)

        -- Import progress overlay (shown when receiving a shared plan)
        local importOverlay = CreateFrame("Frame", nil, pf, "BackdropTemplate")
        importOverlay:SetFrameLevel(pf.canvas:GetFrameLevel() + 10)
        importOverlay:SetPoint("TOPLEFT", pf.canvas, "TOPLEFT", 0, 0)
        importOverlay:SetPoint("BOTTOMRIGHT", pf.canvas, "BOTTOMRIGHT", 0, 0)
        importOverlay:EnableMouse(true)
        SetBackdrop(importOverlay, {0.06, 0.06, 0.1, 0.95}, {0.2, 0.2, 0.25, 1}, 2)
        importOverlay:Hide()
        pf.importProgressOverlay = importOverlay
        local progStatus = importOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        progStatus:SetPoint("CENTER", importOverlay, "CENTER", 0, 20)
        progStatus:SetTextColor(0.9, 0.9, 0.9)
        progStatus:SetText("Requesting plan...")
        importOverlay.statusText = progStatus
        local barBg = CreateFrame("Frame", nil, importOverlay, "BackdropTemplate")
        barBg:SetHeight(16)
        barBg:SetWidth(math.min(320, PLANNER_CANVAS_W - 80))
        barBg:SetPoint("CENTER", importOverlay, "CENTER", 0, -20)
        SetBackdrop(barBg, {0.1, 0.1, 0.14, 1}, {0.25, 0.25, 0.3, 1}, 1)
        importOverlay.barBg = barBg
        local barFill = barBg:CreateTexture(nil, "OVERLAY")
        barFill:SetPoint("TOPLEFT", barBg, "TOPLEFT", 2, -2)
        barFill:SetPoint("BOTTOMLEFT", barBg, "BOTTOMLEFT", 2, 2)
        barFill:SetWidth(0)
        barFill:SetColorTexture(0.2, 0.5, 0.9, 0.9)
        importOverlay.barFill = barFill
        importOverlay.barWidth = math.min(320, PLANNER_CANVAS_W - 80) - 4

        local timeline = CreateFrame("Frame", nil, pf, "BackdropTemplate")
        timeline:SetHeight(TIMELINE_H)
        timeline:SetWidth(PLANNER_CANVAS_W)
        timeline:SetPoint("TOP", controls, "BOTTOM", 0, -ROW_GAP)
        SetBackdrop(timeline, UI.TOOLBAR, UI.BORDER, 1)
        pf.timeline = timeline
        timeline:EnableMouse(true)

        local timelineBg = timeline:CreateTexture(nil, "BACKGROUND")
        timelineBg:SetPoint("TOPLEFT", 6, -5)
        timelineBg:SetPoint("BOTTOMRIGHT", -6, 5)
        timelineBg:SetColorTexture(0.08, 0.09, 0.12, 1)
        pf.timelineBg = timelineBg

        pf.playhead = timeline:CreateTexture(nil, "OVERLAY")
        pf.playhead:SetWidth(2)
        pf.playhead:SetColorTexture(unpack(UI.ACCENT))
        pf.playhead:SetPoint("TOP", timelineBg, "TOP", 0, 0)
        pf.playhead:SetPoint("BOTTOM", timelineBg, "BOTTOM", 0, 0)
        pf.playhead:SetPoint("LEFT", timelineBg, "LEFT", 0, 0)

        pf.timelineLabel = timeline:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        pf.timelineLabel:SetPoint("RIGHT", timeline, "RIGHT", -10, 0)
        pf.timelineLabel:SetTextColor(0.55, 0.58, 0.65)

        timeline:SetScript("OnMouseDown", function(t, button)
            if button ~= "LeftButton" then return end
            local pf = Diar.plannerFrame
            if not pf or not pf.sceneAnimations or #pf.sceneAnimations == 0 then return end
            local data = Diar.plannerData
            if not data or not data.scenes or not pf.selectedSceneIndex then return end
            local scene = data.scenes[pf.selectedSceneIndex]
            if not scene or not scene.items then return end
            local totalDur = GetSceneDuration(pf.sceneAnimations)
            local x = GetCursorPosition() / pf:GetEffectiveScale()
            local left = t:GetLeft()
            local w = t:GetWidth()
            local pct = (x - left) / w
            pct = math.max(0, math.min(1, pct))
            local seekTime = pct * totalDur
            Diar:StopPlannerAnimation()
            pf.animStart = GetTime() - seekTime
            pf.animPlaying = true
            Diar:UpdatePlannerControlButtons()
            local canvas = pf.canvas
            local cw, ch = GetPlannerRenderCanvasSize(pf, canvas)
            local root = GetPlannerItemRoot(pf, canvas)
            ApplyAnimPosition(pf, scene, root, cw, ch, seekTime)
            Diar:UpdatePlannerPlayhead()
            pf:SetScript("OnUpdate", pf.plannerOnUpdateHandler)
        end)

        local patreonPanel = CreateFrame("Frame", nil, pf, "BackdropTemplate")
        patreonPanel:SetSize(RIGHT_PANEL_W, PATREON_BOX_H)
        patreonPanel:SetPoint("TOPLEFT", toolbar, "TOPRIGHT", 12, 0)
        SetBackdrop(patreonPanel, UI.TOOLBAR, UI.BORDER, 1)
        pf.patreonPanel = patreonPanel
        pf.patreonAnchoredToolbar = true

        local patreonLabel = patreonPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        patreonLabel:SetPoint("TOPLEFT", patreonPanel, "TOPLEFT", 10, -10)
        patreonLabel:SetPoint("BOTTOMRIGHT", patreonPanel, "BOTTOMRIGHT", -10, 10)
        patreonLabel:SetJustifyH("LEFT")
        patreonLabel:SetJustifyV("MIDDLE")
        patreonLabel:SetWordWrap(true)
        patreonLabel:SetText("Like raidstrats? Support us on Patreon at |cff4a9effjoin.raidstrats.gg|r")
        patreonLabel:SetTextColor(0.55, 0.58, 0.65)
        pf.patreonLabel = patreonLabel

        local rightPanel = CreateFrame("Frame", nil, pf, "BackdropTemplate")
        rightPanel:SetWidth(RIGHT_PANEL_W)
        rightPanel:SetPoint("TOPLEFT", patreonPanel, "BOTTOMLEFT", 0, -RIGHT_COL_GAP)
        rightPanel:SetPoint("BOTTOMLEFT", timeline, "BOTTOMRIGHT", 12, 0)
        SetBackdrop(rightPanel, UI.PANEL, UI.BORDER, 1)
        pf.savedPlansPanel = rightPanel

        local savedTitle = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        savedTitle:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 12, -12)
        savedTitle:SetTextColor(0.92, 0.92, 0.92)
        savedTitle:SetText("Plan Library")
        pf.savedPlansTitle = savedTitle

        local savedCount = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        savedCount:SetPoint("LEFT", savedTitle, "RIGHT", 6, 0)
        savedCount:SetTextColor(0.45, 0.50, 0.58)
        pf.savedPlansCount = savedCount

        local savedSearchBoxWrap = CreateFrame("Frame", nil, rightPanel, "BackdropTemplate")
        savedSearchBoxWrap:SetPoint("TOPLEFT", savedTitle, "BOTTOMLEFT", 0, -8)
        savedSearchBoxWrap:SetPoint("RIGHT", rightPanel, "RIGHT", -12, 0)
        savedSearchBoxWrap:SetHeight(22)
        SetBackdrop(savedSearchBoxWrap, {0.05, 0.05, 0.07, 1}, UI.BORDER, 1)
        pf.savedPlansSearchBoxWrap = savedSearchBoxWrap

        local savedSearchBox = CreateFrame("EditBox", nil, savedSearchBoxWrap)
        savedSearchBox:SetAutoFocus(false)
        savedSearchBox:SetPoint("TOPLEFT", savedSearchBoxWrap, "TOPLEFT", 8, -2)
        savedSearchBox:SetPoint("BOTTOMRIGHT", savedSearchBoxWrap, "BOTTOMRIGHT", -8, 2)
        savedSearchBox:SetTextInsets(0, 0, 0, 0)
        savedSearchBox:SetMaxLetters(80)
        savedSearchBox:SetText("")
        savedSearchBox:SetFontObject(GameFontHighlightSmall)
        savedSearchBox:SetTextColor(0.92, 0.92, 0.92)
        savedSearchBox:SetScript("OnEditFocusGained", function()
            savedSearchBoxWrap:SetBackdropBorderColor(unpack(UI.ACCENT))
        end)
        savedSearchBox:SetScript("OnEditFocusLost", function()
            savedSearchBoxWrap:SetBackdropBorderColor(unpack(UI.BORDER))
        end)
        savedSearchBox:SetScript("OnEscapePressed", function(s)
            s:ClearFocus()
        end)
        savedSearchBox:SetScript("OnEnterPressed", function(s)
            s:ClearFocus()
        end)
        pf.savedPlansSearchBox = savedSearchBox

        local savedRaidFilterBtn = CreatePlannerIconBtn(rightPanel, "Raid: All", 184, 22)
        savedRaidFilterBtn:SetPoint("TOPLEFT", savedSearchBoxWrap, "BOTTOMLEFT", 0, -6)
        savedRaidFilterBtn:SetPoint("RIGHT", savedSearchBoxWrap, "RIGHT", 0, 0)
        pf.savedPlansRaidFilterBtn = savedRaidFilterBtn

        local savedDivider = rightPanel:CreateTexture(nil, "ARTWORK")
        savedDivider:SetHeight(1)
        savedDivider:SetPoint("TOP", savedRaidFilterBtn, "BOTTOM", 0, -8)
        savedDivider:SetPoint("LEFT", rightPanel, "LEFT", 10, 0)
        savedDivider:SetPoint("RIGHT", rightPanel, "RIGHT", -10, 0)
        savedDivider:SetColorTexture(unpack(UI.BORDER))
        pf.savedPlansDivider = savedDivider

        local footer = CreateFrame("Frame", nil, rightPanel)
        footer:SetHeight(FOOTER_HEIGHT)
        footer:SetPoint("BOTTOMLEFT", rightPanel, "BOTTOMLEFT", 10, 10)
        footer:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -10, 10)
        pf.savedPlansFooter = footer

        local scroll = CreateFrame("ScrollFrame", nil, rightPanel, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", savedDivider, "BOTTOMLEFT", -2, -8)
        scroll:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -6, 6)
        local scrollChild = CreateFrame("Frame", nil, scroll)
        scrollChild:SetWidth(pf.savedPlansListW)
        scrollChild:SetHeight(1)
        scroll:SetScrollChild(scrollChild)
        SkinPlannerScroll(scroll)
        pf.savedPlansScroll = scroll
        pf.savedPlansScrollChild = scrollChild

        local importBtn = CreatePlannerIconBtn(footer, "Import Plan", 200, FOOTER_BTN_H)
        pf.savedPlansImportBtn = importBtn
        importBtn:SetScript("OnClick", function()
            Diar:ShowImportPlanDialog()
        end)

        local newBtn = CreatePlannerIconBtn(footer, "New Plan", 200, FOOTER_BTN_H)
        pf.savedPlansNewBtn = newBtn
        newBtn:SetScript("OnClick", function()
            if Diar.ShowCreatePlanDialog then
                Diar:ShowCreatePlanDialog()
            end
        end)

        local shareBtn = CreatePlannerIconBtn(footer, "Share to Group", 200, FOOTER_BTN_H)
        shareBtn:SetScript("OnClick", function()
            if Diar.SharePlanToGroup then Diar:SharePlanToGroup(Diar.plannerData) end
        end)
        pf.savedPlansShareBtn = shareBtn

        local pushBtn = CreatePlannerIconBtn(footer, "Push Update", 200, FOOTER_BTN_H)
        pushBtn:SetScript("OnClick", function()
            if Diar.HasActiveSavedPlan and not Diar:HasActiveSavedPlan() then return end
            if Diar.PushPlanUpdateToGroup then Diar:PushPlanUpdateToGroup() end
        end)
        pf.pushUpdateBtn = pushBtn

        LayoutSavedPlansFooter(pf)

        if Diar.EnsureRaidLeadViewPanel then
            Diar:EnsureRaidLeadViewPanel(pf)
        end

        self.plannerFrame = pf
    end

    local pf = self.plannerFrame
    if pf.previewNamesVisible == nil then
        -- Imported attached labels should be visible by default; users can hide them via the toggle.
        pf.previewNamesVisible = true
    end
    pf:SetScript("OnSizeChanged", function(s)
        if s.__layoutSyncing or not s.__plannerSizing or s.compactMode then return end
        Diar:SyncPlannerLayoutFromFrame(false)
    end)
    if pf.canvas and pf.canvas.SetClipsChildren then
        pf.canvas:SetClipsChildren(true)
    end
    Diar:EnsurePreviewNamesButton(pf)
    Diar:EnsurePlannerControlsButtons(pf)
    if Diar.EnsurePlannerHelpButton then Diar:EnsurePlannerHelpButton(pf) end
    if Diar.EnsureRaidLeadViewPanel then Diar:EnsureRaidLeadViewPanel(pf) end
    if Diar.UpdatePlannerDebugPanel then Diar:UpdatePlannerDebugPanel() end
    if (not pf.pushUpdateBtn or not pf.savedPlansNewBtn) and pf.savedPlansShareBtn and pf.savedPlansFooter then
        local footer = pf.savedPlansFooter
        if not pf.savedPlansNewBtn then
            local newBtn = CreatePlannerIconBtn(footer, "New Plan", 200, FOOTER_BTN_H)
            newBtn:SetScript("OnClick", function()
                if Diar.ShowCreatePlanDialog then
                    Diar:ShowCreatePlanDialog()
                end
            end)
            pf.savedPlansNewBtn = newBtn
        end
        if not pf.pushUpdateBtn then
            local pushBtn = CreatePlannerIconBtn(footer, "Push Update", 200, FOOTER_BTN_H)
            pushBtn:SetScript("OnClick", function()
                if Diar.HasActiveSavedPlan and not Diar:HasActiveSavedPlan() then return end
                if Diar.PushPlanUpdateToGroup then Diar:PushPlanUpdateToGroup() end
            end)
            pf.pushUpdateBtn = pushBtn
        end
        LayoutSavedPlansFooter(pf)
    elseif pf.savedPlansFooter then
        LayoutSavedPlansFooter(pf)
    end
    if not pf.modeToggleBtn and pf.closeBtn then
        local modeToggleBtn = CreatePlannerIconBtn(pf, "Compact", 76, 22)
        modeToggleBtn:SetPoint("TOPRIGHT", pf.closeBtn, "TOPLEFT", -2, 1)
        modeToggleBtn:SetScript("OnClick", function()
            Diar:TogglePlannerCompactMode()
        end)
        pf.modeToggleBtn = modeToggleBtn
    end
    if not pf.discordBtn and pf.modeToggleBtn then
        local discordBtn = CreatePlannerIconBtn(pf, "Discord", 76, 22)
        discordBtn:SetPoint("TOPRIGHT", pf.modeToggleBtn, "TOPLEFT", -2, 0)
        discordBtn:SetScript("OnClick", function()
            Diar:ShowPlannerDiscordPopup()
        end)
        pf.discordBtn = discordBtn
    end
    if not pf.resizeGrip then
        local resizeGrip = CreateFrame("Button", nil, pf)
        resizeGrip:SetSize(16, 16)
        resizeGrip:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", -2, 2)
        resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
        AttachPlannerResizeGrip(pf, resizeGrip)
        pf.resizeGrip = resizeGrip
        pf:SetResizable(true)
        ApplyPlannerResizeBounds(pf)
    end
    if pf.resizeGrip then
        AttachPlannerResizeGrip(pf, pf.resizeGrip)
    end
    if pf.compactModeBtn then pf.compactModeBtn:Hide() end
    if pf.compactExpandBtn then pf.compactExpandBtn:Hide() end
    if pf.compactBar then pf.compactBar:Hide() end
    UpdatePlannerModeToggleBtn(pf)
    self:PositionPlannerControlsBar(pf)
    pf.title:SetText(TruncatePlannerPlanTitle(data.planName))
    self:UpdatePlannerPlanLink()

    local scenes = data.scenes
    local showSceneTabs = not IsNoPlanLoaded(data)
    -- Build scene tab buttons (reuse existing buttons to avoid leaking frames)
    local container = pf.sceneTabsContainer
    local tabButtons = pf.sceneTabButtons or {}
    pf.sceneTabButtons = {}
    local prevBtn = nil
    local visibleSceneCount = 0
    if showSceneTabs then
        for i, scene in ipairs(scenes) do
            local name = (scene.name and scene.name ~= "") and scene.name or tostring(i)
            local btn = tabButtons[i]
            if not btn then
                btn = CreatePlannerIconBtn(container, name, 56, SCENE_TAB_H)
            else
                btn:Show()
                btn:ClearAllPoints()
                btn:SetHeight(SCENE_TAB_H)
                SetPlannerBtnText(btn, name)
            end
            btn:SetScript("OnClick", function()
                self:SelectPlannerScene(i)
            end)
            btn:SetScript("OnMouseUp", function(s, button)
                if button ~= "RightButton" then return end
                if i <= 1 then return end
                if Diar.ShowSceneTabContextMenu then
                    Diar:ShowSceneTabContextMenu(s, i)
                end
            end)
            if btn.leaderBadge and btn.leaderBadge.GetObjectType and btn.leaderBadge:GetObjectType() ~= "Texture" then
                btn.leaderBadge:Hide()
                btn.leaderBadge = nil
            end
            if not btn.leaderBadge then
                local icon = btn:CreateTexture(nil, "OVERLAY")
                icon:SetSize(11, 11)
                icon:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1, -2)
                icon:SetTexture(GROUP_LEADER_ICON)
                icon:Hide()
                btn.leaderBadge = icon
            end
            btn:SetScript("OnEnter", function(s)
                s:SetBackdropColor(unpack(UI.ROW_HOV))
                if s.selected then
                    s.label:SetTextColor(1, 1, 1)
                elseif s.leaderScene then
                    s.label:SetTextColor(0.65, 1, 0.72)
                else
                    s.label:SetTextColor(1, 1, 1)
                end
                if s.leaderScene and GameTooltip then
                    GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
                    GameTooltip:SetText("Raid leader scene", 0.55, 0.98, 0.62)
                    GameTooltip:AddLine("Your leader is viewing this scene.", 0.78, 0.80, 0.84, true)
                    GameTooltip:Show()
                end
            end)
            btn:SetScript("OnLeave", function(s)
                if GameTooltip then GameTooltip:Hide() end
                Diar:UpdateSceneTabHighlight()
            end)
            if prevBtn then
                btn:SetPoint("LEFT", prevBtn, "RIGHT", 3, 0)
            else
                btn:SetPoint("LEFT", container, "LEFT", 0, 0)
            end
            do
                local w = 44
                if btn.label then w = btn.label:GetStringWidth() + 18 end
                btn:SetWidth(math.min(math.max(w, 40), 110))
            end
            tinsert(pf.sceneTabButtons, btn)
            prevBtn = btn
            visibleSceneCount = visibleSceneCount + 1
        end
    end
    for i = visibleSceneCount + 1, #tabButtons do
        if tabButtons[i] then tabButtons[i]:Hide() end
    end
    -- Control buttons (under canvas): Stop and Play/Pause
    pf.stopBtn:SetScript("OnClick", function() self:StopPlannerAnimation() end)
    pf.playPauseBtn:SetScript("OnClick", function()
        if pf.animPlaying then self:PausePlannerAnimation()
        else self:PlayPlannerAnimation() end
    end)
    self:UpdatePlannerControlButtons()

    pf.selectedSceneIndex = 1
    self:UpdateSceneTabHighlight()
    if pf.nsrtSceneActive or pf.compactMode then
        if pf.nsrtSceneActive and not pf.compactMode then
            pf.compactMode = true
            local s = self:GetPlannerSettings()
            pf.compactCanvasScale = tonumber(s.nsrtCompactScale) or tonumber(s.compactScale) or COMPACT_SCALE
        end
        ApplyPlannerCompactLayout(pf)
        if pf.nsrtSceneActive then ApplyPlannerChromeTransparent(pf) end
    else
        ApplyPlannerNormalLayout(pf)
    end
    self:ApplyPlannerFramePosition(pf)
    if pf.canvas then
        EnsurePlannerZoomControls(pf, pf.canvas)
        BindPlannerCanvasViewportInput(pf, pf.canvas)
    end
    if not pf.nsrtSceneActive then
        self:ApplyNsrtAssignmentForPlannerView(pf.selectedSceneIndex or 1)
    end
    self:RefreshPlannerScene()
    self:RefreshSavedPlansList()
    if self.UpdatePushUpdateButton then self:UpdatePushUpdateButton() end
    if self.ApplyRaidLeadViewLayout then self:ApplyRaidLeadViewLayout(pf) end
    if self.OnPlannerPlanChanged then self:OnPlannerPlanChanged() end
    self:ResetPlannerCanvasLock()

    if opts.reloadOnly then
        if not pf:IsShown() then pf:Show() end
        return
    end

    pf:Show()
    if opts.showMain and self.frame then
        self.frame:Show()
    end
    if opts.layoutWindows and Diar.LayoutOpenWindows then
        Diar:LayoutOpenWindows()
    end
end

local PLANNER_WEB_ORIGIN = "https://raidstrats.gg"

local function BuildPlannerViewUrl(planId, sceneIndex)
    if type(planId) ~= "string" or planId == "" then return nil end
    sceneIndex = tonumber(sceneIndex) or 0
    local view = planId
    local sceneNumber = sceneIndex + 1
    if sceneNumber > 1 then
        view = planId .. "/" .. sceneNumber
    end
    return PLANNER_WEB_ORIGIN .. "/planner?view=" .. view
end

function Diar:GetPlannerPlanLink()
    local data = self.plannerData
    if not data then return nil end

    local planId = type(data.planId) == "string" and data.planId ~= "" and data.planId or nil
    if planId then
        local pf = self.plannerFrame
        local sceneIdx = ((pf and pf.selectedSceneIndex) or 1) - 1
        return BuildPlannerViewUrl(planId, sceneIdx)
    end

    if type(data.planLink) == "string" and data.planLink ~= "" then
        return data.planLink
    end

    return nil
end

function Diar:UpdatePlannerPlanLink()
    local pf = self.plannerFrame
    if not pf or not pf.planLinkBtn then return end
    local link = self:GetPlannerPlanLink()
    if link then
        pf.planLinkBtn:Enable()
    else
        pf.planLinkBtn:Disable()
    end
end

function Diar:ShowPlannerPlanLinkPopup()
    local link = self:GetPlannerPlanLink()
    if not link then return end

    if not self.planLinkPopup then
        local f = CreateFrame("Frame", "RaidstratsPlanLinkPopup", UIParent, "BackdropTemplate")
        f:SetSize(480, 160)
        f:SetPoint("CENTER")
        f:SetMovable(true)
        f:EnableMouse(true)
        SetBackdrop(f)
        tinsert(UISpecialFrames, "RaidstratsPlanLinkPopup")
        f:SetScript("OnMouseDown", function(s, b) if b == "LeftButton" then s:StartMoving() end end)
        f:SetScript("OnMouseUp", function(s) s:StopMovingOrSizing() end)
        CreateFrame("Button", nil, f, "UIPanelCloseButton"):SetPoint("TOPRIGHT", -5, -5)
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.title:SetPoint("TOP", 0, -18)
        f.title:SetTextColor(0.9, 0.9, 0.9)
        f.title:SetText("Plan link")
        local bc, b = CreateInput(f, "Copy link", false)
        bc:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -52)
        bc:SetPoint("TOPRIGHT", f, "TOPRIGHT", -20, -52)
        bc:SetHeight(44)
        b:SetScript("OnEscapePressed", function() f:Hide() end)
        f.linkEdit = b
        local btn = CreateButton(f, "CLOSE")
        btn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 16)
        btn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
        btn:SetScript("OnClick", function() f:Hide() end)
        self.planLinkPopup = f
    end

    self.planLinkPopup.linkEdit:SetText(link)
    self.planLinkPopup.linkEdit:HighlightText()
    self.planLinkPopup.linkEdit:SetFocus()
    if self.PrepareModal then
        self:PrepareModal(self.planLinkPopup, self.plannerFrame)
    end
    self.planLinkPopup:Show()
end

local PLANNER_DISCORD_URL = "https://discord.gg/QtU244VZ8X"

function Diar:ShowPlannerDiscordPopup()
    if not self.discordPopup then
        local f = CreateFrame("Frame", "RaidstratsDiscordPopup", UIParent, "BackdropTemplate")
        f:SetSize(480, 170)
        f:SetPoint("CENTER")
        f:SetMovable(true)
        f:EnableMouse(true)
        SetBackdrop(f)
        tinsert(UISpecialFrames, "RaidstratsDiscordPopup")
        f:SetScript("OnMouseDown", function(s, b) if b == "LeftButton" then s:StartMoving() end end)
        f:SetScript("OnMouseUp", function(s) s:StopMovingOrSizing() end)
        CreateFrame("Button", nil, f, "UIPanelCloseButton"):SetPoint("TOPRIGHT", -5, -5)
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.title:SetPoint("TOP", 0, -18)
        f.title:SetTextColor(0.9, 0.9, 0.9)
        f.title:SetText("Raidstrats.gg Discord")
        f.desc = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.desc:SetPoint("TOP", f.title, "BOTTOM", 0, -6)
        f.desc:SetTextColor(0.7, 0.72, 0.75)
        f.desc:SetText("Copy the invite link below and open it in your browser.")
        local bc, b = CreateInput(f, "Copy link", false)
        bc:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -78)
        bc:SetPoint("TOPRIGHT", f, "TOPRIGHT", -20, -78)
        bc:SetHeight(44)
        b:SetScript("OnEscapePressed", function() f:Hide() end)
        f.linkEdit = b
        local btn = CreateButton(f, "CLOSE")
        btn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 16)
        btn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
        btn:SetScript("OnClick", function() f:Hide() end)
        self.discordPopup = f
    end

    self.discordPopup.linkEdit:SetText(PLANNER_DISCORD_URL)
    self.discordPopup.linkEdit:HighlightText()
    self.discordPopup.linkEdit:SetFocus()
    if self.PrepareModal then
        self:PrepareModal(self.discordPopup, self.plannerFrame)
    end
    self.discordPopup:Show()
end

function Diar:GetPlannerCreditsText()
    return tostring(PLANNER_CREDITS_TEXT or "")
end

function Diar:ShowPlannerCreditsDialog()
    if not self.plannerCreditsDialog then
        local f = CreateFrame("Frame", "RaidstratsPlannerCreditsDialog", UIParent, "BackdropTemplate")
        f:SetSize(560, 420)
        f:SetPoint("CENTER")
        f:SetMovable(true)
        f:EnableMouse(true)
        SetBackdrop(f)
        tinsert(UISpecialFrames, "RaidstratsPlannerCreditsDialog")
        f:SetScript("OnMouseDown", function(s, b) if b == "LeftButton" then s:StartMoving() end end)
        f:SetScript("OnMouseUp", function(s) s:StopMovingOrSizing() end)
        CreateFrame("Button", nil, f, "UIPanelCloseButton"):SetPoint("TOPRIGHT", -5, -5)

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.title:SetPoint("TOP", 0, -18)
        f.title:SetTextColor(0.9, 0.9, 0.9)
        f.title:SetText("Planner Credits")

        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -52)
        scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -36, 58)
        SkinPlannerScroll(scroll)
        local content = CreateFrame("Frame", nil, scroll)
        content:SetPoint("TOPLEFT")
        content:SetSize(1, 1)
        scroll:SetScrollChild(content)

        local body = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        body:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -2)
        body:SetJustifyH("LEFT")
        body:SetJustifyV("TOP")
        body:SetWordWrap(true)
        if body.SetNonSpaceWrap then body:SetNonSpaceWrap(true) end
        body:SetSpacing(4)
        body:SetTextColor(0.86, 0.88, 0.92)
        body:SetText("")
        local function syncCreditsScroll()
            local targetW = math.max(1, scroll:GetWidth() - 28)
            content:SetWidth(targetW)
            body:SetWidth(math.max(1, targetW - 4))
            local neededH = math.ceil(body:GetStringHeight()) + 8
            content:SetHeight(math.max(scroll:GetHeight(), neededH))
        end
        scroll:SetScript("OnSizeChanged", syncCreditsScroll)
        f.syncCreditsScroll = syncCreditsScroll
        f.creditsScroll = scroll
        f.creditsContent = content
        f.creditsText = body

        local closeBtn = CreateButton(f, "CLOSE")
        closeBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 16)
        closeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
        closeBtn:SetScript("OnClick", function() f:Hide() end)

        self.plannerCreditsDialog = f
    end

    self.plannerCreditsDialog.creditsText:SetText(self:GetPlannerCreditsText())
    if self.plannerCreditsDialog.syncCreditsScroll then
        self.plannerCreditsDialog.syncCreditsScroll()
    end
    if self.plannerCreditsDialog.creditsScroll then
        self.plannerCreditsDialog.creditsScroll:SetVerticalScroll(0)
    end
    if self.PrepareModal then
        self:PrepareModal(self.plannerCreditsDialog, self.plannerFrame)
    end
    self.plannerCreditsDialog:Show()
end

function Diar:UpdateSceneTabHighlight()
    local pf = self.plannerFrame
    if not pf or not pf.sceneTabButtons then
        self:UpdatePlannerPlanLink()
        return
    end
    local idx = pf.selectedSceneIndex or 1
    local leaderScene = self.GetRaidLeaderActiveSceneIndex and self:GetRaidLeaderActiveSceneIndex()
    local showLeaderHint = leaderScene and #pf.sceneTabButtons > 1

    for i, btn in ipairs(pf.sceneTabButtons) do
        if not btn then break end
        local selected = (i == idx)
        local isLeaderScene = showLeaderHint and (i == leaderScene)
        btn.selected = selected
        btn.leaderScene = isLeaderScene and not selected

        if btn.leaderBadge then
            if isLeaderScene then btn.leaderBadge:Show() else btn.leaderBadge:Hide() end
        end

        if selected then
            btn:SetBackdropColor(0.16, 0.20, 0.28, 1)
            if btn.label then btn.label:SetTextColor(1, 0.82, 0.2) end
        elseif isLeaderScene then
            btn:SetBackdropColor(0.10, 0.24, 0.14, 1)
            if btn.label then btn.label:SetTextColor(0.48, 0.94, 0.56) end
        else
            btn:SetBackdropColor(unpack(UI.ROW))
            if btn.label then btn.label:SetTextColor(0.85, 0.85, 0.85) end
        end
    end
    self:UpdatePlannerPlanLink()
end



function Diar:RefreshPlannerScene()
    local pf = self.plannerFrame
    local data = self.plannerData
    if not pf or not data or not data.scenes then return end
    local noPlanLoaded = IsNoPlanLoaded(data)

    local idx = pf.selectedSceneIndex or 1
    if idx < 1 or idx > #data.scenes then
        idx = 1
        pf.selectedSceneIndex = idx
        self:UpdateSceneTabHighlight()
    end
    if self.UpdateCompactSceneArrowButtons then
        self:UpdateCompactSceneArrowButtons(pf)
    end
    local scene = data.scenes[idx]
    if not scene then
        local canvas = pf.canvas
        if canvas then
            local children = { canvas:GetChildren() }
            for i = 1, #children do
                ReleasePlannerWidget(pf, children[i])
            end
        end
        ResetShapePool(pf)
        ResetStrokePool(pf)
        pf.sceneAnimations = {}
        pf.animStart = nil
        pf.animPlaying = false
        pf.animPaused = false
        pf.pausedTime = nil
        pf.sceneViewContext = nil
        pf.viewerViewport = nil
        pf.__viewerViewportSceneIdx = nil
        SetNoPlanCanvasHint(pf, noPlanLoaded)
        Diar:UpdatePlannerControlButtons()
        Diar:UpdatePlannerPlayhead()
        if self.UpdateCompactSceneArrowButtons then
            self:UpdateCompactSceneArrowButtons(pf)
        end
        return
    end
    SetNoPlanCanvasHint(pf, noPlanLoaded)
    scene.items = scene.items or {}

    local canvas = pf.canvas
    local cw, ch = GetPlannerRenderCanvasSize(pf, canvas)
    SyncViewerViewportFromScene(pf, scene)
    pf.sceneViewContext = BuildSceneViewContext(pf.viewerViewport, cw, ch)
    pf.__viewportDisplayZoom = pf.viewerViewport and pf.viewerViewport.zoom or 1
    local vc = pf.sceneViewContext
    local root = canvas

    if pf.frontalBeamWidgets then
        for _, widget in pairs(pf.frontalBeamWidgets) do
            ReleasePlannerWidget(pf, widget)
        end
        pf.frontalBeamWidgets = nil
    end
    -- Release previous scene widgets into a hidden recycle bin so no frames remain on screen.
    local children = { root:GetChildren() }
    for i = 1, #children do
        ReleasePlannerWidget(pf, children[i])
    end
    for i = 1, #scene.items do
        local it = scene.items[i]
        it.currentX = nil
        it.currentY = nil
    end
    if scene.animations then
        for _, anim in ipairs(scene.animations) do
            anim.__normalizedPath = nil
            anim.__pathLengths = nil
            anim.__resolvedItemIndex = nil
        end
    end

    if canvas then canvas:SetAlpha(1) end
    ApplySceneBackground(pf, scene, vc, cw, ch)
    local playerKey = GetPlayerNameKey()
    local hasSelfOnPlan = self:IsHighlightMyNameEnabled() and SceneHasPlayerName(scene, playerKey)

    -- Dynamic group assignment: when an NSRT tag is active, recolor spot circles.
    local sceneSpots = ResolveSceneSpots(scene)
    local activeGroup = self.activeGroup
    local groupSpots = activeGroup and sceneSpots or nil
    local groupSpotNames = activeGroup and activeGroup.spotNames or nil
    local previewNamesOn = self:IsPlannerPreviewNamesVisible() and groupSpotNames
    local previewSpots = self:IsPlannerPreviewIndexVisible() and sceneSpots or nil
    local debugTrackSpots = self.GetPlannerSettings and self:GetPlannerSettings().debugMode == true
    local debugMineHits = debugTrackSpots and {} or nil

    -- Render pass. Icons, text, and box shapes (rect/circle/ellipse/polygon) get an
    -- animatable item.widget. Frontal beams, donuts, triangles/cones, lines and arrows
    -- are drawn separately (pf.frontalBeamWidgets / pooled static shapes) and have no widget.
    local minSize = 2
    local sceneCtx = {
        hasSelfOnPlan = hasSelfOnPlan,
        playerKey = playerKey,
        groupSpots = groupSpots,
        activeGroup = activeGroup,
        groupSpotNames = groupSpotNames,
        previewNamesOn = previewNamesOn,
        previewSpots = previewSpots,
        debugMineHits = debugMineHits,
    }
    for i, item in ipairs(scene.items) do
        Diar.RenderSceneItem(self, pf, root, cw, ch, vc, minSize, item, i, sceneCtx)
    end

    BuildFrontalBeamWidgets(pf, scene, root, cw, ch)
    BuildShapeWidgets(pf, scene, root, cw, ch)
    RebuildStrokeOverlays(pf, scene, root, cw, ch)

    if debugMineHits and self.AppendPlannerDebugLine then
        table.sort(debugMineHits)
        local mySpots = activeGroup and activeGroup.mySpots
        local myList = {}
        if type(mySpots) == "table" then
            for slot in pairs(mySpots) do myList[#myList + 1] = tonumber(slot) or 0 end
            table.sort(myList)
        end
        local myListStr = (#myList > 0) and table.concat(myList, ",") or "-"
        local hitStr = (#debugMineHits > 0) and table.concat(debugMineHits, "; ") or "-"
        local sig = ("scene=%s|my=%s|hits=%s"):format(tostring(idx), myListStr, hitStr)
        if self._plannerDebugLastRenderSig ~= sig then
            self._plannerDebugLastRenderSig = sig
            self:AppendPlannerDebugLine(
                ("RenderMySpot scene=%s mySpots=%s hits=%s"):format(tostring(idx), myListStr, hitStr)
            )
        end
    end

    pf.sceneAnimations = scene.animations or {}
    pf.animStart = nil
    pf.animPlaying = false
    pf.animPaused = false
    pf.pausedTime = nil
    Diar:UpdatePlannerControlButtons()
    Diar:UpdatePlannerPlayhead()
    UpdatePlannerZoomLabel(pf)
    if pf.nsrtSceneActive and pf.compactMode then
        ApplyPlannerChromeTransparent(pf)
        UpdatePlannerModeToggleBtn(pf)
    end
    if self.UpdateCompactSceneArrowButtons then
        self:UpdateCompactSceneArrowButtons(pf)
    end
end

-- Normalize path to list of {x,y} in 0..100. Handles nested [[x,y],...] or flat [x,y,x,y,...] from JSON.
-- If values look like 0..1 (all <= 1.5), scale by 100.
local function NormalizePath(path)
    if not path or type(path) ~= "table" or #path < 2 then return nil end
    local out = {}
    local first = path[1]
    if type(first) == "table" then
        for i = 1, #path do
            local pt = path[i]
            if type(pt) == "table" and (type(pt[1]) == "number" and type(pt[2]) == "number") then
                local x, y = pt[1], pt[2]
                if x <= 1.5 and y <= 1.5 then x, y = x * 100, y * 100 end
                out[#out + 1] = { x, y }
            end
        end
    else
        for i = 1, #path - 1, 2 do
            local x, y = path[i], path[i + 1]
            if type(x) == "number" and type(y) == "number" then
                if x <= 1.5 and y <= 1.5 then x, y = x * 100, y * 100 end
                out[#out + 1] = { x, y }
            end
        end
    end
    return #out >= 2 and out or nil
end

-- Precompute segment lengths and total for arc-length parameterization (constant speed along path).
local function BuildPathLengths(points)
    if not points or #points < 2 then return nil end
    local lengths = {}
    local total = 0
    for i = 1, #points - 1 do
        local a, b = points[i], points[i + 1]
        local dx = (b[1] or 0) - (a[1] or 0)
        local dy = (b[2] or 0) - (a[2] or 0)
        local len = math.sqrt(dx * dx + dy * dy)
        lengths[i] = len
        total = total + len
    end
    lengths.total = total
    return lengths
end

-- Get x,y (0..100) at progress 0..1 along path using arc-length; lengths from BuildPathLengths.
local function GetPathPositionAtProgress(points, lengths, progress)
    if not points or #points < 2 then
        local p = points and points[1]
        return p and (p[1] or 0) or 0, p and (p[2] or 0) or 0
    end
    if not lengths or (lengths.total or 0) <= 0 then
        -- Fallback: linear by segment index (no arc-length)
        local n = #points
        local pos = progress * (n - 1)
        local seg = math.max(0, math.min(math.floor(pos), n - 2))
        local localP = pos - seg
        local p0, p1 = points[seg + 1], points[seg + 2]
        local x = (p0[1] or 0) + ((p1[1] or 0) - (p0[1] or 0)) * localP
        local y = (p0[2] or 0) + ((p1[2] or 0) - (p0[2] or 0)) * localP
        return x, y
    end
    progress = math.max(0, math.min(1, progress))
    local dist = progress * lengths.total
    local acc = 0
    for seg = 1, #points - 1 do
        local segLen = lengths[seg] or 0
        if acc + segLen >= dist or seg == #points - 1 then
            local localT = segLen > 0 and (dist - acc) / segLen or 1
            localT = math.max(0, math.min(1, localT))
            local p0, p1 = points[seg], points[seg + 1]
            local x = (p0[1] or 0) + ((p1[1] or 0) - (p0[1] or 0)) * localT
            local y = (p0[2] or 0) + ((p1[2] or 0) - (p0[2] or 0)) * localT
            return x, y
        end
        acc = acc + segLen
    end
    local last = points[#points]
    return last[1] or 0, last[2] or 0
end

local function Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function GetAnimTimeState(t, startT, dur, loop)
    dur = (dur and dur > 0) and dur or 0.001
    if t < startT then
        return false, 0, false
    end
    if loop then
        local elapsed = t - startT
        return true, (elapsed % dur) / dur, false
    end
    local ended = t >= (startT + dur)
    if ended then
        return false, 1, true
    end
    return true, Clamp((t - startT) / dur, 0, 1), false
end

local function ResolveAnimItemIndex(anim, scene, path)
    if anim.itemIndex and anim.itemIndex >= 0 then
        return anim.itemIndex + 1
    end
    if anim.objectId then
        local oid = tostring(anim.objectId)
        for i, it in ipairs(scene.items) do
            if it and it.id and tostring(it.id) == oid then
                anim.__resolvedItemIndex = i
                return i
            end
        end
    end
    if anim.__resolvedItemIndex then
        return anim.__resolvedItemIndex
    end
    if path and #path >= 1 and path[1] then
        local sx, sy = path[1][1] or 0, path[1][2] or 0
        local bestI, bestD = nil, nil
        for i, it in ipairs(scene.items) do
            if type(it.x) == "number" and type(it.y) == "number" then
                local dx = it.x - sx
                local dy = it.y - sy
                local d = dx * dx + dy * dy
                if not bestD or d < bestD then
                    bestD = d
                    bestI = i
                end
            end
        end
        anim.__resolvedItemIndex = bestI or 1
        return anim.__resolvedItemIndex
    end
    return 1
end

local function SetItemPositionPercent(item, canvas, cw, ch, xp, yp, vc)
    if not item or not item.widget then return end
    if vc == nil and Diar.plannerFrame then vc = Diar.plannerFrame.sceneViewContext end
    item.currentX = xp
    item.currentY = yp
    item.widget:ClearAllPoints()
    local px, py = SceneViewPctToCanvas(vc, cw, ch, xp, yp)
    item.widget:SetPoint("TOPLEFT", canvas, "TOPLEFT", px, -py)
end

local function ApplyAnimPosition(pf, scene, canvas, cw, ch, t)
    if not pf.sceneAnimations then return end
    local root = canvas
    local vc = pf.sceneViewContext

    -- Reset all widgets to base state every frame (use widget.baseX/baseY so shapes are correct).
    if pf.frontalBeamWidgets then
        for _, beam in pairs(pf.frontalBeamWidgets) do
            if IsPlannerWidgetFrame(beam) then
                beam:Hide()
                if beam.line then beam.line:Hide() end
                if beam:GetParent() ~= root then
                    beam:SetParent(root)
                end
            end
        end
    end
    for i, item in ipairs(scene.items) do
        local w = item and item.widget
        if w and not w.__suppressed then
            if IsFrontalItem(item) then
                w:Hide()
                w:SetAlpha(1)
                if w.tex then
                    w.tex:SetAlpha((type(item.opacity) == "number") and item.opacity or 0.65)
                    w.tex:SetRotation(0)
                end
            else
                local bx = (item.widget and item.widget.baseX) or ((type(item.x) == "number" and item.x or 0) / 100)
                local by = (item.widget and item.widget.baseY) or ((type(item.y) == "number" and item.y or 0) / 100)
                SetItemPositionPercent(item, root, cw, ch, bx, by, vc)
                w:SetScale(1)
                if w.basePixelW and w.basePixelH and w.basePixelW > 0 and w.basePixelH > 0 then
                    w:SetSize(w.basePixelW, w.basePixelH)
                end
                w:SetAlpha(1)
                if w:GetParent() == root then
                    w:Show()
                    if w.tex then
                        w.tex:Show()
                        w.tex:SetRotation(0)
                    end
                end
            end
        end
    end

    -- Reuse helpers table to avoid allocating every frame (memory leak)
    if not pf.animHelpers then
        pf.animHelpers = {
            NormalizePath = NormalizePath,
            BuildPathLengths = BuildPathLengths,
            GetPathPositionAtProgress = GetPathPositionAtProgress,
            GetAnimTimeState = GetAnimTimeState,
            ResolveAnimItemIndex = ResolveAnimItemIndex,
            SetItemPositionPercent = SetItemPositionPercent,
            Clamp = Clamp,
        }
    end

    if Diar.PlannerPath and Diar.PlannerPath.Apply then Diar.PlannerPath.Apply(pf, scene, root, cw, ch, t, pf.animHelpers) end
    if Diar.PlannerStationary and Diar.PlannerStationary.Apply then Diar.PlannerStationary.Apply(pf, scene, root, cw, ch, t, pf.animHelpers) end
    if Diar.PlannerFrontal and Diar.PlannerFrontal.Apply then Diar.PlannerFrontal.Apply(pf, scene, root, cw, ch, t, pf.animHelpers) end
    if Diar.PlannerTether and Diar.PlannerTether.Apply then Diar.PlannerTether.Apply(pf, scene, root, cw, ch, t, pf.animHelpers) end

    RebuildStrokeOverlays(pf, scene, root, cw, ch)
end

Diar.GetSceneDuration = GetSceneDuration
Diar.GetPlannerRenderCanvasSize = GetPlannerRenderCanvasSize
Diar.GetPlannerItemRoot = GetPlannerItemRoot
Diar.ApplyAnimPosition = ApplyAnimPosition
Diar.ApplyPlannerChromeTransparent = ApplyPlannerChromeTransparent
Diar.NormalizeAssignName = NormalizeAssignName

function Diar:RefreshPlannerViewportDisplay(panOnly)
    local pf = self.plannerFrame
    local data = self.plannerData
    if not pf or not data or not data.scenes then return end
    local idx = pf.selectedSceneIndex or 1
    local scene = data.scenes[idx]
    if not scene or not scene.items then return end
    local canvas = pf.canvas
    if not canvas then return end
    local cw, ch = GetPlannerRenderCanvasSize(pf, canvas)
    if pf.viewerViewport then
        pf.viewerViewport = ClampViewerViewportNormalized(pf.viewerViewport)
    end
    pf.sceneViewContext = BuildSceneViewContext(pf.viewerViewport, cw, ch)
    local vc = pf.sceneViewContext
    local root = canvas
    local zoom = (pf.viewerViewport and pf.viewerViewport.zoom) or 1
    pf.__viewportDisplayZoom = zoom

    ApplySceneBackground(pf, scene, vc, cw, ch)
    local minSize = 2
    for _, item in ipairs(scene.items) do
        local w = item.widget
        if IsPlannerWidgetFrame(w) and w:IsShown() and not w.__suppressed then
            LayoutItemWidget(w, item, vc, cw, ch, root, minSize)
            if w.text and w.text:IsShown() and item.kind == "text" then
                local lbl = (item.label and item.label ~= "") and item.label or ""
                ApplyTextWidgetContent(w, item, lbl, vc, ch, minSize)
            end
        end
    end

    -- During live pan, only reposition cheap widget layers; rebuild vector shapes once on release.
    if not panOnly then
        BuildShapeWidgets(pf, scene, root, cw, ch)
        RebuildStrokeOverlays(pf, scene, root, cw, ch)
        BuildFrontalBeamWidgets(pf, scene, root, cw, ch)
    end

    if pf.animPlaying and pf.animStart then
        local t = pf.animPaused and (pf.pausedTime or 0) or (GetTime() - pf.animStart)
        ApplyAnimPosition(pf, scene, root, cw, ch, t)
    end
    UpdatePlannerZoomLabel(pf)
end

function Diar:PlannerZoomBy(factor)
    local pf = self.plannerFrame
    local canvas = pf and pf.canvas
    if not canvas then return end
    local x, y, cw, ch = GetCanvasLocalCursor(canvas, pf)
    PlannerZoomViewerAt(pf, factor, x, y, cw, ch)
    self:RefreshPlannerViewportDisplay(false)
end

function Diar:PlannerZoomIn()
    self:PlannerZoomBy(1.2)
end

function Diar:PlannerZoomOut()
    self:PlannerZoomBy(0.833333)
end

function Diar:PlannerResetViewport()
    local pf = self.plannerFrame
    if not pf then return end
    pf.viewerViewport = nil
    pf.__viewportDisplayZoom = nil
    self:RefreshPlannerViewportDisplay(false)
end

-- Called when the planner window is closed (OnHide). Clears all icons/widgets from the canvas so nothing stays on screen.
function Diar:ClearPlannerDisplay()
    local pf = self.plannerFrame
    if not pf then return end
    -- Stop animation without RefreshPlannerScene (that would re-show icons while closing).
    pf:SetScript("OnUpdate", nil)
    pf.animPlaying = false
    pf.animPaused = false
    pf.pausedTime = nil
    pf.animStart = nil
    if pf.noPlanHint then
        pf.noPlanHint:Hide()
    end
    self:UpdatePlannerControlButtons()
    GameTooltip:Hide()
    -- Clear all item widget refs so we don't hold references to frames we're removing
    local data = self.plannerData
    if data and data.scenes then
        for _, scene in ipairs(data.scenes) do
            if scene and scene.items then
                for _, item in ipairs(scene.items) do
                    if item then
                        if IsPlannerWidgetFrame(item.widget) then
                            ReleasePlannerWidget(pf, item.widget)
                        end
                        item.widget = nil
                        item.currentX = nil
                        item.currentY = nil
                    end
                end
            end
        end
    end
    if pf.frontalBeamWidgets then
        for _, widget in pairs(pf.frontalBeamWidgets) do
            ReleasePlannerWidget(pf, widget)
        end
        pf.frontalBeamWidgets = nil
    end
    ResetShapePool(pf)
    ResetStrokePool(pf)
    -- Remove and hide every direct child of the canvas so no dormant icons remain on screen
    local canvas = pf.canvas
    if canvas then
        local kids = { canvas:GetChildren() }
        for _, child in ipairs(kids) do
            ReleasePlannerWidget(pf, child)
        end
    end
    local bin = pf.widgetRecycleBin
    if bin then
        local recycled = { bin:GetChildren() }
        for _, child in ipairs(recycled) do
            child:Hide()
        end
        bin:Hide()
    end
end



