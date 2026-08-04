-- Raidstrats.gg Planner - import dialog and progress overlay
local addonName = ...
local AceAddon = LibStub("AceAddon-3.0")
local Addon =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)
if not Addon then return end
local function L(key) return RSGG_L(key) end
local Diar = Addon
local SetBackdrop = Diar.SetBackdrop
local CreateButton = Diar.CreateButton
local CreateInput = Diar.CreateInput
local CreateAnimatedCheckbox = Diar.CreateAnimatedCheckbox
local IMPORT_PROGRESS_UPDATE_MIN_INTERVAL = 0.06
function Diar:UpdatePlannerPlanLink()
    local pf = self.plannerFrame
    if not pf or not pf.planLinkBox or not pf.planLinkEdit then return end
    local data = self.plannerData
    local url = (data and type(data.planLink) == "string" and data.planLink ~= "") and data.planLink
        or (data and type(data.planId) == "string" and data.planId ~= "") and ("https://raidstrats.gg/planner?view=" .. data.planId)
        or ""
    pf.planLinkEdit:SetText(url)
    if url and url ~= "" then
        pf.planLinkBox:Show()
    else
        pf.planLinkBox:Hide()
    end
end

-- Import plan dialog: paste !raidstrats-addon-... and click Import
function Diar:ShowImportPlanDialog()
    if not self.importPlanDialog then
        local f = CreateFrame("Frame", "RaidstratsImportPlanDialog", UIParent, "BackdropTemplate")
        f:SetSize(540, 360)
        f:SetPoint("CENTER", 0, 0)
        f:SetMovable(true)
        f:EnableMouse(true)
        SetBackdrop(f)
        tinsert(UISpecialFrames, "RaidstratsImportPlanDialog")
        f:SetScript("OnMouseDown", function(s, b) if b == "LeftButton" then s:StartMoving() end end)
        f:SetScript("OnMouseUp", function(s) s:StopMovingOrSizing() end)

        local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -5, -5)

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -18)
        title:SetText(L("Import plan"))
        title:SetTextColor(0.9, 0.9, 0.9)

        local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOP", title, "BOTTOM", 0, -8)
        hint:SetWidth(500)
        hint:SetTextColor(0.55, 0.6, 0.65)
        hint:SetText(
            L("Paste the export from raidstrats.gg (!raidstrats-addon-...)") .. "\n" ..
            L("Larger plans may cause your client to lag for a few seconds, this is normal.")
        )

        local btnRow = CreateFrame("Frame", nil, f)
        btnRow:SetHeight(40)
        btnRow:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 16)
        btnRow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)

        local inputFrame = CreateFrame("Frame", nil, f, "BackdropTemplate")
        inputFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -72)
        inputFrame:SetPoint("BOTTOMRIGHT", btnRow, "TOPRIGHT", 0, 14)
        SetBackdrop(inputFrame, {0.05, 0.05, 0.07, 1}, {0.2, 0.2, 0.2, 1}, 1)

        local scroll = CreateFrame("ScrollFrame", nil, inputFrame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", inputFrame, "TOPLEFT", 8, -8)
        scroll:SetPoint("BOTTOMRIGHT", inputFrame, "BOTTOMRIGHT", -24, 8)

        local eb = CreateFrame("EditBox", nil, scroll)
        eb:SetAutoFocus(false)
        eb:SetMultiLine(true)
        eb:SetMaxLetters(0)
        eb:SetWidth(math.max(1, scroll:GetWidth()))
        eb:SetTextInsets(4, 4, 4, 4)
        scroll:SetScrollChild(eb)
        eb:SetMaxLetters(0)
        eb:SetFontObject(GameFontHighlightSmall)
        eb:SetTextColor(0.92, 0.92, 0.92)

        local inactiveBorder = { 0.20, 0.20, 0.20, 1 }
        local activeBorder = { 0.30, 0.60, 1.00, 1 }
        eb:SetScript("OnEditFocusGained", function()
            inputFrame:SetBackdropBorderColor(unpack(activeBorder))
        end)
        eb:SetScript("OnEditFocusLost", function()
            inputFrame:SetBackdropBorderColor(unpack(inactiveBorder))
        end)
        inputFrame:EnableMouse(true)
        inputFrame:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" and eb and eb.SetFocus then
                eb:SetFocus()
            end
        end)
        scroll:EnableMouse(true)
        scroll:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" and eb and eb.SetFocus then
                eb:SetFocus()
            end
        end)

        inputFrame._scroll = scroll
        inputFrame._edit = eb
        inputFrame.SyncEditWidth = function(self)
            if not self or not self._scroll or not self._edit then return end
            local w = self:GetWidth()
            if not w or w <= 32 then return end
            local innerW = w - 32
            self._scroll:SetWidth(innerW)
            self._edit:SetWidth(innerW)
        end
        eb:SetScript("OnTextChanged", function()
            if inputFrame and inputFrame.SyncEditWidth then
                inputFrame:SyncEditWidth()
            end
        end)
        inputFrame:SetScript("OnSizeChanged", function(s)
            if s and s.SyncEditWidth then
                s:SyncEditWidth()
            end
        end)
        f.inputFrame = inputFrame
        f.inputFrame = inputFrame

        local importBtn = CreateButton and CreateButton(btnRow, L("IMPORT")) or CreateFrame("Button", nil, btnRow, "UIPanelButtonTemplate")
        if importBtn.SetText then importBtn:SetText(L("IMPORT")) end
        importBtn:SetPoint("LEFT", btnRow, "LEFT", 0, 0)
        importBtn:SetPoint("RIGHT", btnRow, "CENTER", -6, 0)
        importBtn:SetScript("OnClick", function()
            local raw = eb and eb:GetText() or ""
            if Diar.TryImportPlanFromText then
                Diar:TryImportPlanFromText(raw, { openPlanner = true, closeImportDialog = true })
            end
        end)

        local cancelBtn = CreateButton and CreateButton(btnRow, L("CANCEL")) or CreateFrame("Button", nil, btnRow, "UIPanelButtonTemplate")
        if cancelBtn.SetText then cancelBtn:SetText(L("CANCEL")) end
        cancelBtn:SetPoint("LEFT", btnRow, "CENTER", 6, 0)
        cancelBtn:SetPoint("RIGHT", btnRow, "RIGHT", 0, 0)
        cancelBtn:SetScript("OnClick", function() f:Hide() end)

        self.importPlanDialog = f
        self.importPlanDialogEdit = eb
    end

    self.importPlanDialogEdit:SetText("")
    Diar:PrepareModal(self.importPlanDialog, self.plannerFrame or self.frame)
    if self.importPlanDialog.inputFrame and self.importPlanDialog.inputFrame.SyncEditWidth then
        self.importPlanDialog.inputFrame:SyncEditWidth()
    end
    self.importPlanDialog:Show()
    if self.importPlanDialogEdit and self.importPlanDialogEdit.SetFocus then
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if Diar and Diar.importPlanDialog and Diar.importPlanDialog:IsShown() and Diar.importPlanDialogEdit then
                    Diar.importPlanDialogEdit:SetFocus()
                    if Diar.importPlanDialogEdit.HighlightText then
                        Diar.importPlanDialogEdit:HighlightText(0, 0)
                    end
                    if Diar.importPlanDialogEdit.SetCursorPosition then
                        Diar.importPlanDialogEdit:SetCursorPosition(0)
                    end
                end
            end)
        else
            self.importPlanDialogEdit:SetFocus()
            if self.importPlanDialogEdit.HighlightText then
                self.importPlanDialogEdit:HighlightText(0, 0)
            end
            if self.importPlanDialogEdit.SetCursorPosition then
                self.importPlanDialogEdit:SetCursorPosition(0)
            end
        end
    end
end

function Diar:ShowRosterExportDialog()
    if not self.rosterExportDialog then
        local f = CreateFrame("Frame", "RaidstratsRosterExportDialog", UIParent, "BackdropTemplate")
        f:SetSize(540, 360)
        f:SetPoint("CENTER", 0, 0)
        f:SetMovable(true)
        f:EnableMouse(true)
        SetBackdrop(f)
        tinsert(UISpecialFrames, "RaidstratsRosterExportDialog")
        f:SetScript("OnMouseDown", function(s, b) if b == "LeftButton" then s:StartMoving() end end)
        f:SetScript("OnMouseUp", function(s) s:StopMovingOrSizing() end)

        local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -5, -5)

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -18)
        title:SetText(L("Export roster"))
        title:SetTextColor(0.9, 0.9, 0.9)

        local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOP", title, "BOTTOM", 0, -8)
        hint:SetWidth(500)
        hint:SetTextColor(0.55, 0.6, 0.65)
        hint:SetText(L("Generate a roster string, then copy it and paste where needed."))

        local btnRow = CreateFrame("Frame", nil, f)
        btnRow:SetHeight(40)
        btnRow:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 16)
        btnRow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)

        local inputFrame = CreateFrame("Frame", nil, f, "BackdropTemplate")
        inputFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -72)
        inputFrame:SetPoint("BOTTOMRIGHT", btnRow, "TOPRIGHT", 0, 46)
        SetBackdrop(inputFrame, {0.05, 0.05, 0.07, 1}, {0.2, 0.2, 0.2, 1}, 1)

        local scroll = CreateFrame("ScrollFrame", nil, inputFrame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", inputFrame, "TOPLEFT", 8, -8)
        scroll:SetPoint("BOTTOMRIGHT", inputFrame, "BOTTOMRIGHT", -24, 8)

        local eb = CreateFrame("EditBox", nil, scroll)
        eb:SetAutoFocus(false)
        eb:SetMultiLine(true)
        eb:SetMaxLetters(0)
        eb:SetWidth(math.max(1, scroll:GetWidth()))
        eb:SetTextInsets(4, 4, 4, 4)
        scroll:SetScrollChild(eb)
        eb:SetFontObject(GameFontHighlightSmall)
        eb:SetTextColor(0.92, 0.92, 0.92)

        local inactiveBorder = { 0.20, 0.20, 0.20, 1 }
        local activeBorder = { 0.30, 0.60, 1.00, 1 }
        eb:SetScript("OnEditFocusGained", function()
            inputFrame:SetBackdropBorderColor(unpack(activeBorder))
        end)
        eb:SetScript("OnEditFocusLost", function()
            inputFrame:SetBackdropBorderColor(unpack(inactiveBorder))
        end)
        inputFrame:EnableMouse(true)
        inputFrame:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" and eb and eb.SetFocus then
                eb:SetFocus()
            end
        end)
        scroll:EnableMouse(true)
        scroll:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" and eb and eb.SetFocus then
                eb:SetFocus()
            end
        end)

        inputFrame._scroll = scroll
        inputFrame._edit = eb
        inputFrame.SyncEditWidth = function(self)
            if not self or not self._scroll or not self._edit then return end
            local w = self:GetWidth()
            if not w or w <= 32 then return end
            local innerW = w - 32
            self._scroll:SetWidth(innerW)
            self._edit:SetWidth(innerW)
        end
        eb:SetScript("OnTextChanged", function()
            if inputFrame and inputFrame.SyncEditWidth then
                inputFrame:SyncEditWidth()
            end
        end)
        inputFrame:SetScript("OnSizeChanged", function(s)
            if s and s.SyncEditWidth then
                s:SyncEditWidth()
            end
        end)

        local includeSpecChk = CreateAnimatedCheckbox and CreateAnimatedCheckbox(f, L("Include spec (slower)")) or nil
        if includeSpecChk then
            includeSpecChk:SetPoint("TOPLEFT", inputFrame, "BOTTOMLEFT", 0, -8)
            includeSpecChk:SetScript("OnClick", function(s)
                s.isChecked = not s.isChecked
                if s.UpdateVisuals then s:UpdateVisuals() end
            end)
        end

        local generateBtn = CreateButton and CreateButton(btnRow, L("GENERATE ROSTER")) or CreateFrame("Button", nil, btnRow, "UIPanelButtonTemplate")
        if generateBtn.SetText then generateBtn:SetText(L("GENERATE ROSTER")) end
        generateBtn:SetPoint("LEFT", btnRow, "LEFT", 0, 0)
        generateBtn:SetPoint("RIGHT", btnRow, "CENTER", -6, 0)

        local closeActionBtn = CreateButton and CreateButton(btnRow, L("CLOSE")) or CreateFrame("Button", nil, btnRow, "UIPanelButtonTemplate")
        if closeActionBtn.SetText then closeActionBtn:SetText(L("CLOSE")) end
        closeActionBtn:SetPoint("LEFT", btnRow, "CENTER", 6, 0)
        closeActionBtn:SetPoint("RIGHT", btnRow, "RIGHT", 0, 0)
        closeActionBtn:SetScript("OnClick", function() f:Hide() end)

        local stopBtn = CreateButton and CreateButton(btnRow, L("STOP")) or CreateFrame("Button", nil, btnRow, "UIPanelButtonTemplate")
        if stopBtn.SetText then stopBtn:SetText(L("STOP")) end
        stopBtn:SetSize(80, 28)
        stopBtn:SetPoint("RIGHT", generateBtn, "RIGHT", 0, 0)
        stopBtn:SetScript("OnClick", function()
            if Diar.StopScan then
                Diar:StopScan()
            end
        end)
        stopBtn:Hide()

        generateBtn:SetScript("OnClick", function()
            Diar.outputBox = eb
            Diar.specCheckbox = includeSpecChk
            Diar.stopBtn = stopBtn
            Diar.genBtn = nil
            if Diar.StartRosterScan then
                Diar:StartRosterScan()
            end
        end)

        f:SetScript("OnHide", function()
            if Diar.isScanning and Diar.StopScan then
                Diar:StopScan()
            end
        end)

        self.rosterExportDialog = f
        self.rosterExportDialogEdit = eb
        self.rosterExportStopBtn = stopBtn
        self.rosterExportSpecChk = includeSpecChk
    end

    self.outputBox = self.rosterExportDialogEdit
    self.specCheckbox = self.rosterExportSpecChk
    self.stopBtn = self.rosterExportStopBtn
    self.genBtn = nil
    self.rosterExportDialogEdit:SetText("")
    Diar:PrepareModal(self.rosterExportDialog, self.plannerFrame or self.frame)
    if self.rosterExportDialog.inputFrame and self.rosterExportDialog.inputFrame.SyncEditWidth then
        self.rosterExportDialog.inputFrame:SyncEditWidth()
    end
    self.rosterExportDialog:Show()
    if self.rosterExportDialogEdit and self.rosterExportDialogEdit.SetFocus then
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if Diar and Diar.rosterExportDialog and Diar.rosterExportDialog:IsShown() and Diar.rosterExportDialogEdit then
                    Diar.rosterExportDialogEdit:SetFocus()
                end
            end)
        else
            self.rosterExportDialogEdit:SetFocus()
        end
    end
end

function Diar:ShowImportProgress(visible, received, total, status)
    local pf = self.plannerFrame
    if not pf or not pf.importProgressOverlay then return end
    local overlay = pf.importProgressOverlay
    if not visible then
        overlay._lastProgressUpdateAt = nil
        overlay._lastProgressPercent = nil
        overlay:Hide()
        return
    end
    overlay:Show()
    if overlay.statusText then
        overlay.statusText:SetText(status or L("Requesting plan..."))
    end
    local pct = 0
    if total and total > 0 and received then
        pct = math.min(1, received / total)
        if overlay.statusText then
            overlay.statusText:SetText(L("Importing plan... %d%%"):format(math.floor(pct * 100)))
        end
    end
    local w = (overlay.barWidth or 316) * pct
    if overlay.barFill then
        overlay.barFill:SetWidth(math.max(0, w))
    end
end

function Diar:UpdateImportProgress(received, total)
    local pf = self.plannerFrame
    if not pf or not pf.importProgressOverlay or not pf.importProgressOverlay:IsShown() then return end
    local overlay = pf.importProgressOverlay
    local pct = (total and total > 0 and received) and math.min(1, received / total) or 0
    local pctInt = math.floor(pct * 100)
    local now = GetTime and GetTime() or 0
    local lastAt = overlay._lastProgressUpdateAt or 0
    local lastPct = overlay._lastProgressPercent
    local done = total and total > 0 and received and received >= total
    if not done and lastPct == pctInt and (now - lastAt) < IMPORT_PROGRESS_UPDATE_MIN_INTERVAL then
        return
    end
    overlay._lastProgressUpdateAt = now
    overlay._lastProgressPercent = pctInt
    if overlay.statusText then
        overlay.statusText:SetText(L("Importing plan... %d%%"):format(pctInt))
    end
    local w = (overlay.barWidth or 316) * pct
    if overlay.barFill then
        overlay.barFill:SetWidth(math.max(0, w))
    end
end

function Diar:HideImportProgress()
    self:ShowImportProgress(false)
end

