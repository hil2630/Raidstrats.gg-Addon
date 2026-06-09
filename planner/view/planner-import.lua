-- Raidstrats.gg Planner - import dialog and progress overlay
local addonName = ...
local AceAddon = LibStub("AceAddon-3.0")
local Addon =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)
if not Addon then return end
local Diar = Addon
local SetBackdrop = Diar.SetBackdrop
local CreateButton = Diar.CreateButton
local CreateInput = Diar.CreateInput
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
        title:SetText("Import plan")
        title:SetTextColor(0.9, 0.9, 0.9)

        local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOP", title, "BOTTOM", 0, -8)
        hint:SetWidth(500)
        hint:SetTextColor(0.55, 0.6, 0.65)
        hint:SetText("Paste the export from raidstrats.gg (!raidstrats-addon-...)")

        local btnRow = CreateFrame("Frame", nil, f)
        btnRow:SetHeight(40)
        btnRow:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 16)
        btnRow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)

        local inputFrame, eb
        if CreateInput then
            inputFrame, eb = CreateInput(f, "Plan String", true)
            inputFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -72)
            inputFrame:SetPoint("BOTTOMRIGHT", btnRow, "TOPRIGHT", 0, 14)
            eb:SetFontObject("GameFontHighlightSmall")
        end
        f.inputFrame = inputFrame

        local importBtn = CreateButton and CreateButton(btnRow, "IMPORT") or CreateFrame("Button", nil, btnRow, "UIPanelButtonTemplate")
        if importBtn.SetText then importBtn:SetText("IMPORT") end
        importBtn:SetPoint("LEFT", btnRow, "LEFT", 0, 0)
        importBtn:SetPoint("RIGHT", btnRow, "CENTER", -6, 0)
        importBtn:SetScript("OnClick", function()
            local raw = eb and eb:GetText() or ""
            if Diar.TryImportPlanFromText then
                Diar:TryImportPlanFromText(raw, { openPlanner = true, closeImportDialog = true })
            end
        end)

        local cancelBtn = CreateFrame("Button", nil, btnRow, "UIPanelButtonTemplate")
        cancelBtn:SetHeight(40)
        cancelBtn:SetPoint("LEFT", btnRow, "CENTER", 6, 0)
        cancelBtn:SetPoint("RIGHT", btnRow, "RIGHT", 0, 0)
        cancelBtn:SetText("Cancel")
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
end

function Diar:ShowImportProgress(visible, received, total, status)
    local pf = self.plannerFrame
    if not pf or not pf.importProgressOverlay then return end
    local overlay = pf.importProgressOverlay
    if not visible then
        overlay:Hide()
        return
    end
    overlay:Show()
    if overlay.statusText then
        overlay.statusText:SetText(status or "Requesting plan...")
    end
    local pct = 0
    if total and total > 0 and received then
        pct = math.min(1, received / total)
        if overlay.statusText then
            overlay.statusText:SetText(("Importing plan... %d%%"):format(math.floor(pct * 100)))
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
    if overlay.statusText then
        overlay.statusText:SetText(("Importing plan... %d%%"):format(math.floor(pct * 100)))
    end
    local w = (overlay.barWidth or 316) * pct
    if overlay.barFill then
        overlay.barFill:SetWidth(math.max(0, w))
    end
end

function Diar:HideImportProgress()
    self:ShowImportProgress(false)
end

