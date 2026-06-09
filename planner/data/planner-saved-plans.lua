-- Raidstrats.gg Planner - saved plan library (list, load, delete)
local addonName = ...
local AceAddon = LibStub("AceAddon-3.0")
local Addon =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)
if not Addon then return end
local Diar = Addon
local SetBackdrop = Diar.SetBackdrop
local CreateAnimatedCheckbox = Diar.CreateAnimatedCheckbox
local PUI = Diar.PlannerUI
local UI = PUI.UI
local CreatePlannerIconBtn = PUI.CreatePlannerIconBtn
local SkinPlannerScroll = PUI.SkinPlannerScroll
-- Delete-plan confirmation popup
if not StaticPopupDialogs["RAIDSTRATSGG_DELETE_PLAN"] then
    StaticPopupDialogs["RAIDSTRATSGG_DELETE_PLAN"] = {
        text = "Delete plan \"%s\"?",
        button1 = _G.YES or "Yes",
        button2 = _G.CANCEL or "Cancel",
        OnAccept = function(self)
            local id = self.data
            if id and Diar and Diar.DeleteSavedPlan then Diar:DeleteSavedPlan(id) end
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
    }
end

-- Copy plan data so loading from saved doesn't share reference with storage.
local function CopyPlanData(val)
    if type(val) == "table" then
        local out = {}
        for k, v in pairs(val) do out[k] = CopyPlanData(v) end
        return out
    end
    return val
end

local function BuildPlanMetaLine(entry)
    local parts = {}
    if entry.raid and entry.raid ~= "" and entry.raid ~= "Other" then
        parts[#parts + 1] = entry.raid
    end
    if entry.boss and entry.boss ~= "" and entry.boss ~= "Unknown" then
        parts[#parts + 1] = entry.boss
    end
    if #parts == 0 then return "Saved plan" end
    return table.concat(parts, " · ")
end

local PLAN_CARD_H = 46
local SECTION_H = 22
local LIST_GAP = 6
local PLAN_ROW_ACTIONS_W = 56

local function CreatePlanAutoToggle(parent)
    if not CreateAnimatedCheckbox then return nil end
    local toggle = CreateAnimatedCheckbox(parent, nil)
    toggle:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_LEFT")
        GameTooltip:SetText("Auto-import updates", 1, 1, 1)
        GameTooltip:AddLine("When enabled, pushed plan changes from your leader are applied automatically.", 0.78, 0.80, 0.84, true)
        GameTooltip:Show()
    end)
    toggle:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return toggle
end

local function ApplySavedPlanRowState(rowFrame, entry, isActive, planKey, autoEnabled)
    rowFrame.entryId = entry.id
    rowFrame.planKey = planKey

    local title = entry.planName or "Unnamed"
    rowFrame.label:SetText(title)
    rowFrame.meta:SetText(BuildPlanMetaLine(entry))

    if isActive then
        rowFrame.activeBar:Show()
        rowFrame:SetBackdropColor(0.12, 0.16, 0.24, 0.98)
        rowFrame.label:SetTextColor(0.95, 0.88, 0.45)
        rowFrame.meta:SetTextColor(0.62, 0.66, 0.72)
    else
        rowFrame.activeBar:Hide()
        rowFrame:SetBackdropColor(unpack(UI.ROW))
        rowFrame.label:SetTextColor(0.92, 0.92, 0.92)
        rowFrame.meta:SetTextColor(0.50, 0.54, 0.60)
    end

    if planKey and rowFrame.syncToggle then
        rowFrame.syncToggle.planKey = planKey
        rowFrame.syncToggle:SetChecked(autoEnabled and true or false)
        rowFrame.syncToggle:Show()
    elseif rowFrame.syncToggle then
        rowFrame.syncToggle:Hide()
    end
end

local function AcquireSavedPlanRow(pf, child, planIndex, w)
    pf.savedPlansRows = pf.savedPlansRows or {}
    local rowFrame = pf.savedPlansRows[planIndex]
    if rowFrame and rowFrame.__cardV5 and rowFrame.syncToggle then return rowFrame end
    if rowFrame then
        rowFrame:Hide()
        rowFrame:SetParent(nil)
    end

    rowFrame = CreateFrame("Button", nil, child, "BackdropTemplate")
    rowFrame.__cardV5 = true
    rowFrame:SetHeight(PLAN_CARD_H)
    rowFrame:SetWidth(w)
    SetBackdrop(rowFrame, UI.ROW, UI.BORDER, 1)

    local activeBar = rowFrame:CreateTexture(nil, "ARTWORK")
    activeBar:SetWidth(3)
    activeBar:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 1, -1)
    activeBar:SetPoint("BOTTOMLEFT", rowFrame, "BOTTOMLEFT", 1, 1)
    activeBar:SetColorTexture(unpack(UI.ACCENT))
    activeBar:Hide()
    rowFrame.activeBar = activeBar

    local label = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 10, -8)
    label:SetPoint("RIGHT", rowFrame, "RIGHT", -PLAN_ROW_ACTIONS_W, 0)
    label:SetJustifyH("LEFT")
    label:SetHeight(14)
    rowFrame.label = label

    local meta = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    meta:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
    meta:SetPoint("RIGHT", rowFrame, "RIGHT", -PLAN_ROW_ACTIONS_W, 0)
    meta:SetJustifyH("LEFT")
    meta:SetHeight(12)
    meta:SetTextColor(0.50, 0.54, 0.60)
    rowFrame.meta = meta

    local delBtn = CreateFrame("Button", nil, rowFrame, "BackdropTemplate")
    delBtn:SetSize(20, 20)
    delBtn:SetPoint("RIGHT", rowFrame, "RIGHT", -4, 0)
    SetBackdrop(delBtn, {0, 0, 0, 0}, {0.55, 0.22, 0.22, 0.95}, 1)
    local delFs = delBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    delFs:SetPoint("CENTER")
    delFs:SetText("×")
    delFs:SetTextColor(0.95, 0.45, 0.45)
    delBtn.label = delFs
    rowFrame.delBtn = delBtn
    delBtn:SetScript("OnEnter", function(s)
        s:SetBackdropColor(0.28, 0.10, 0.10, 0.75)
        s:SetBackdropBorderColor(0.85, 0.30, 0.30, 1)
        s.label:SetTextColor(1, 0.55, 0.55)
        GameTooltip:SetOwner(s, "ANCHOR_LEFT")
        GameTooltip:SetText("Delete plan", 1, 1, 1)
        GameTooltip:Show()
    end)
    delBtn:SetScript("OnLeave", function(s)
        s:SetBackdropColor(0, 0, 0, 0)
        s:SetBackdropBorderColor(0.55, 0.22, 0.22, 0.95)
        s.label:SetTextColor(0.95, 0.45, 0.45)
        GameTooltip:Hide()
    end)

    local syncToggle = CreatePlanAutoToggle(rowFrame)
    if syncToggle then
        syncToggle:SetPoint("RIGHT", delBtn, "LEFT", -8, 0)
        rowFrame.syncToggle = syncToggle
        syncToggle:HookScript("OnClick", function(s)
            if not s.planKey then return end
            if Diar.SetPlanAutoImport then
                Diar:SetPlanAutoImport(s.planKey, s.isChecked)
            end
        end)
        syncToggle:HookScript("OnMouseDown", function(_, btn)
            if btn == "LeftButton" then
                syncToggle.__blockRowClick = true
            end
        end)
    end

    rowFrame:SetScript("OnEnter", function(s)
        if s.entryId and s.entryId == (Diar.plannerData and Diar.plannerData.savedEntryId) then
            s:SetBackdropColor(0.14, 0.18, 0.26, 1)
        else
            s:SetBackdropColor(unpack(UI.ROW_HOV))
        end
        s.label:SetTextColor(1, 1, 1)
    end)
    rowFrame:SetScript("OnLeave", function(s)
        local active = s.entryId and s.entryId == (Diar.plannerData and Diar.plannerData.savedEntryId)
        if active then
            s:SetBackdropColor(0.12, 0.16, 0.24, 0.98)
            s.label:SetTextColor(0.95, 0.88, 0.45)
        else
            s:SetBackdropColor(unpack(UI.ROW))
            s.label:SetTextColor(0.92, 0.92, 0.92)
        end
    end)

    pf.savedPlansRows[planIndex] = rowFrame
    return rowFrame
end

function Diar:RefreshSavedPlansList()
    local pf = self.plannerFrame
    if not pf or not pf.savedPlansScrollChild then return end
    RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {}, nextId = 1 }
    local list = RaidstratsggSavedPlans.list
    local child = pf.savedPlansScrollChild
    local w = pf.savedPlansListW or math.max(1, child:GetWidth())
    child:SetWidth(w)

    if pf.savedPlansTitle then
        pf.savedPlansTitle:SetText("Plan Library")
    end
    if pf.savedPlansCount then
        pf.savedPlansCount:SetText(#list > 0 and ("(" .. #list .. ")") or "")
    end
    if pf.savedPlansSubtitle then
        pf.savedPlansSubtitle:SetText(#list > 0 and "Use the checkbox to auto-import pushed updates" or "Import a plan to get started")
    end

    local sorted = {}
    for i = 1, #list do sorted[i] = list[i] end
    table.sort(sorted, function(a, b)
        if (a.expansion or "") ~= (b.expansion or "") then return (a.expansion or "") < (b.expansion or "") end
        if (a.raid or "") ~= (b.raid or "") then return (a.raid or "") < (b.raid or "") end
        if (a.boss or "") ~= (b.boss or "") then return (a.boss or "") < (b.boss or "") end
        return (a.planName or "") < (b.planName or "")
    end)

    local rows = {}
    if #sorted == 0 then
        rows[#rows + 1] = { type = "empty" }
    end
    local lastExpansion
    for _, entry in ipairs(sorted) do
        local expansion = entry.expansion or "Other"
        if expansion ~= lastExpansion then
            lastExpansion = expansion
            rows[#rows + 1] = { type = "section", text = expansion }
        end
        rows[#rows + 1] = { type = "plan", entry = entry }
    end

    pf.savedPlansHeaders = pf.savedPlansHeaders or {}
    local y = -2
    local headerIndex = 0
    local planIndex = 0
    local activeId = self.plannerData and self.plannerData.savedEntryId

    for _, row in ipairs(rows) do
        if row.type == "empty" then
            headerIndex = headerIndex + 1
            local lbl = pf.savedPlansHeaders[headerIndex]
            if not lbl then
                lbl = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                lbl:SetJustifyH("CENTER")
                pf.savedPlansHeaders[headerIndex] = lbl
            end
            lbl:ClearAllPoints()
            lbl:SetPoint("TOPLEFT", child, "TOPLEFT", 8, y - 18)
            lbl:SetWidth(w - 16)
            lbl:SetText("No plans saved yet")
            lbl:SetTextColor(0.52, 0.56, 0.62)
            lbl:Show()
            y = y - 52
            headerIndex = headerIndex + 1
            local hint = pf.savedPlansHeaders[headerIndex]
            if not hint then
                hint = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                hint:SetJustifyH("CENTER")
                pf.savedPlansHeaders[headerIndex] = hint
            end
            hint:ClearAllPoints()
            hint:SetPoint("TOPLEFT", child, "TOPLEFT", 12, y)
            hint:SetWidth(w - 24)
            hint:SetText("Use Import Plan below, or paste a share link from chat.")
            hint:SetTextColor(0.42, 0.46, 0.52)
            hint:Show()
            y = y - 36
        elseif row.type == "section" then
            headerIndex = headerIndex + 1
            local lbl = pf.savedPlansHeaders[headerIndex]
            if not lbl then
                lbl = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                lbl:SetJustifyH("LEFT")
                pf.savedPlansHeaders[headerIndex] = lbl
            end
            lbl:ClearAllPoints()
            lbl:SetPoint("TOPLEFT", child, "TOPLEFT", 2, y)
            lbl:SetWidth(w - 4)
            lbl:SetText(string.upper(row.text or ""))
            lbl:SetTextColor(unpack(UI.ACCENT))
            lbl:Show()
            y = y - SECTION_H - 2
        else
            planIndex = planIndex + 1
            local rowFrame = AcquireSavedPlanRow(pf, child, planIndex, w - 4)
            local entry = row.entry
            local planKey = self.GetPlanIdentityKey and self:GetPlanIdentityKey(entry.data)
            local autoEnabled = planKey and self.IsPlanAutoImportEnabled and self:IsPlanAutoImportEnabled(planKey)
            local isActive = activeId and entry.id == activeId
            ApplySavedPlanRowState(rowFrame, entry, isActive, planKey, autoEnabled)
            rowFrame:ClearAllPoints()
            rowFrame:SetPoint("TOPLEFT", child, "TOPLEFT", 2, y)
            rowFrame:SetScript("OnClick", function(_, btn)
                if btn == "RightButton" then return end
                if rowFrame.syncToggle and rowFrame.syncToggle.__blockRowClick then
                    rowFrame.syncToggle.__blockRowClick = nil
                    return
                end
                Diar:LoadSavedPlan(entry.id)
            end)
            rowFrame.delBtn:SetScript("OnClick", function(_, btn)
                if btn == "RightButton" then return end
                StaticPopup_Show("RAIDSTRATSGG_DELETE_PLAN", entry.planName or "Unnamed", nil, entry.id)
            end)
            rowFrame:Show()
            y = y - PLAN_CARD_H - LIST_GAP
        end
    end

    local totalH = math.max(1, -y + 12)
    for hi = headerIndex + 1, #(pf.savedPlansHeaders or {}) do
        if pf.savedPlansHeaders[hi] then pf.savedPlansHeaders[hi]:Hide() end
    end
    for pi = planIndex + 1, #(pf.savedPlansRows or {}) do
        if pf.savedPlansRows[pi] then pf.savedPlansRows[pi]:Hide() end
    end
    child:SetHeight(totalH)
    if pf.savedPlansScroll then
        pf.savedPlansScroll:SetVerticalScroll(0)
    end
    if self.UpdatePushUpdateButton then self:UpdatePushUpdateButton() end
end

function Diar:LoadSavedPlan(entryId)
    if not entryId then return end
    if self.LoadSavedPlanById then
        self:LoadSavedPlanById(entryId, { openPlanner = true })
    end
end

function Diar:LoadPlanByName(planName)
    if not planName or planName == "" then return false end
    planName = strtrim(planName)
    if self.plannerData and self.plannerData.planName == planName then return true end
    RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {}, nextId = 1 }
    for _, entry in ipairs(RaidstratsggSavedPlans.list) do
        if entry.planName == planName and entry.data then
            if self.ApplySavedPlanEntry then
                return self:ApplySavedPlanEntry(entry)
            end
            self.plannerData = CopyPlanData(entry.data)
            self.plannerData.savedEntryId = entry.id
            self:SanitizePlanData(self.plannerData)
            return true
        end
    end
    return false
end

function Diar:DeleteSavedPlan(entryId)
    if not entryId then return end
    RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {}, nextId = 1 }
    local deletedActive = false
    for i, entry in ipairs(RaidstratsggSavedPlans.list) do
        if entry.id == entryId then
            deletedActive = (self.plannerData and self.plannerData.savedEntryId == entryId)
            if entry.data and self.GetPlanIdentityKey then
                local planKey = self:GetPlanIdentityKey(entry.data)
                if planKey then
                    local s = self.GetPlannerSettings and self:GetPlannerSettings()
                    if s and s.planAutoImport then s.planAutoImport[planKey] = nil end
                end
            end
            table.remove(RaidstratsggSavedPlans.list, i)
            if deletedActive then
                -- Deleted plan was currently loaded; unload it immediately.
                self:ShowNoPlansState()
            else
                self:RefreshSavedPlansList()
                if #RaidstratsggSavedPlans.list == 0 then
                    self:ShowNoPlansState()
                end
            end
            return
        end
    end
end

-- When there are no saved plans: clear canvas, set empty data, show "No plans" + Import in list.
function Diar:ShowNoPlansState()
    self.plannerData = { planName = "No plan", scenes = { { name = "Empty", items = {} } } }
    self:ClearPlannerDisplay()
    self:RefreshSavedPlansList()
    local pf = self.plannerFrame
    if pf and pf.title then
        pf.title:SetText(PUI.TruncatePlannerPlanTitle("No plan"))
    end
    self:RefreshPlannerScene()
    self:UpdatePlannerPlanLink()
    if self.UpdatePushUpdateButton then self:UpdatePushUpdateButton() end
end

-- Delete the currently loaded plan from the saved list (if it's in there).
function Diar:DeleteCurrentPlanFromSaved()
    local data = self.plannerData
    if not data or not data.planName then return end
    RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {}, nextId = 1 }
    local raid = (type(data.raid) == "string" and data.raid ~= "") and data.raid or "Other"
    local boss = (type(data.boss) == "string" and data.boss ~= "") and data.boss or "Unknown"
    local planName = (type(data.planName) == "string" and data.planName ~= "") and data.planName or "Unnamed"
    for i, entry in ipairs(RaidstratsggSavedPlans.list) do
        if entry.planName == planName and (entry.raid or "Other") == raid and (entry.boss or "Unknown") == boss then
            local deletedActive = (self.plannerData and self.plannerData.savedEntryId == entry.id)
            table.remove(RaidstratsggSavedPlans.list, i)
            if deletedActive then
                -- Current viewer plan was removed from library; unload stale data.
                self:ShowNoPlansState()
            else
                self:RefreshSavedPlansList()
                if #RaidstratsggSavedPlans.list == 0 then
                    self:ShowNoPlansState()
                end
            end
            return
        end
    end
end

