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

if not StaticPopupDialogs["RAIDSTRATSGG_PLAN_SEARCH"] then
    StaticPopupDialogs["RAIDSTRATSGG_PLAN_SEARCH"] = {
        text = "Search plans (name / raid / boss):",
        button1 = _G.OKAY or "OK",
        button2 = _G.CANCEL or "Cancel",
        hasEditBox = true,
        maxLetters = 80,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        OnShow = function(self)
            local eb = self.editBox or self.EditBox
            if not eb then return end
            local current = (self.data and self.data.current) or ""
            eb:SetText(current)
            eb:HighlightText()
            eb:SetFocus()
        end,
        OnAccept = function(self)
            local eb = self.editBox or self.EditBox
            local text = eb and eb:GetText() or ""
            if Diar and Diar.SetSavedPlansSearchQuery then
                Diar:SetSavedPlansSearchQuery(text)
            end
        end,
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
local RAID_FILTER_MENU_ROW_H = 22

local function IsCompactPlanLibraryMode()
    return Diar.IsCompactPlanLibraryEnabled and Diar:IsCompactPlanLibraryEnabled()
end

local function GetPlanCardHeight()
    if IsCompactPlanLibraryMode() then return 36 end
    return PLAN_CARD_H
end

local function GetSectionHeight()
    if IsCompactPlanLibraryMode() then return 18 end
    return SECTION_H
end

local function GetListGap()
    if IsCompactPlanLibraryMode() then return 4 end
    return LIST_GAP
end

local function CleanFilterText(value)
    return strtrim(tostring(value or ""))
end

local function MatchSearchQuery(entry, queryLower)
    if not queryLower or queryLower == "" then return true end
    local haystack = table.concat({
        tostring(entry and entry.planName or ""),
        tostring(entry and entry.expansion or ""),
        tostring(entry and entry.raid or ""),
        tostring(entry and entry.boss or ""),
    }, " "):lower()
    return haystack:find(queryLower, 1, true) ~= nil
end

local function CollectRaidFilterOptions(list)
    local seen = {}
    local out = {}
    for _, entry in ipairs(list or {}) do
        local raid = CleanFilterText(entry and entry.raid)
        if raid == "" then raid = "Other" end
        if not seen[raid] then
            seen[raid] = true
            out[#out + 1] = raid
        end
    end
    table.sort(out, function(a, b)
        if a == "Other" and b ~= "Other" then return false end
        if b == "Other" and a ~= "Other" then return true end
        return a < b
    end)
    return out
end

function Diar:SetSavedPlansSearchQuery(query)
    local pf = self.plannerFrame
    if not pf then return end
    local q = CleanFilterText(query)
    pf.savedPlansSearchQuery = q ~= "" and q or nil
    if pf.savedPlansSearchBox then
        local current = pf.savedPlansSearchBox:GetText() or ""
        local target = pf.savedPlansSearchQuery or ""
        if current ~= target then
            pf.savedPlansSearchBox:SetText(target)
        end
    end
    self:RefreshSavedPlansList()
end

function Diar:CycleSavedPlansRaidFilter()
    local pf = self.plannerFrame
    if not pf then return end
    local options = pf.savedPlansRaidFilterOptions or {}
    if #options == 0 then
        pf.savedPlansRaidFilter = nil
        self:RefreshSavedPlansList()
        return
    end
    local current = pf.savedPlansRaidFilter
    if not current then
        pf.savedPlansRaidFilter = options[1]
        self:RefreshSavedPlansList()
        return
    end
    local idx = nil
    for i, raid in ipairs(options) do
        if raid == current then
            idx = i
            break
        end
    end
    if not idx or idx >= #options then
        pf.savedPlansRaidFilter = nil
    else
        pf.savedPlansRaidFilter = options[idx + 1]
    end
    self:RefreshSavedPlansList()
end

function Diar:SetSavedPlansRaidFilter(raidName)
    local pf = self.plannerFrame
    if not pf then return end
    local value = CleanFilterText(raidName)
    if value == "" or value == "__all__" then
        value = nil
    end
    pf.savedPlansRaidFilter = value
    self:RefreshSavedPlansList()
end

function Diar:HideSavedPlansRaidFilterMenu()
    if self._savedPlansRaidFilterDismiss then
        self._savedPlansRaidFilterDismiss:Hide()
    end
    if self._savedPlansRaidFilterMenu then
        self._savedPlansRaidFilterMenu:Hide()
    end
end

function Diar:ShowSavedPlansRaidFilterMenu(anchorBtn, options)
    if not anchorBtn then return end
    local pf = self.plannerFrame
    if not pf then return end

    options = options or {}
    local values = { "__all__" }
    for _, raidName in ipairs(options) do
        values[#values + 1] = raidName
    end

    local menu = self._savedPlansRaidFilterMenu
    if not menu then
        menu = CreateFrame("Frame", "RaidstratsSavedRaidFilterMenu", UIParent, "BackdropTemplate")
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(560)
        menu:EnableMouse(true)
        if SetBackdrop then SetBackdrop(menu, UI.PANEL, UI.BORDER, 1) end
        menu.rows = {}
        menu:SetScript("OnHide", function()
            if Diar._savedPlansRaidFilterDismiss then
                Diar._savedPlansRaidFilterDismiss:Hide()
            end
        end)
        if UISpecialFrames then
            tinsert(UISpecialFrames, "RaidstratsSavedRaidFilterMenu")
        end
        self._savedPlansRaidFilterMenu = menu
    end

    local desiredW = math.max(anchorBtn:GetWidth() or 184, 200)
    local menuH = (#values * RAID_FILTER_MENU_ROW_H) + 8
    menu:SetSize(desiredW, menuH)

    for i, value in ipairs(values) do
        local row = menu.rows[i]
        if not row then
            row = CreateFrame("Button", nil, menu, "BackdropTemplate")
            row:SetHeight(RAID_FILTER_MENU_ROW_H)
            if SetBackdrop then SetBackdrop(row, UI.ROW, UI.BORDER, 1) end
            local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("LEFT", row, "LEFT", 8, 0)
            label:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            label:SetJustifyH("LEFT")
            row.label = label
            row:SetScript("OnEnter", function(s)
                s:SetBackdropColor(unpack(UI.ROW_HOV))
                if s.label then s.label:SetTextColor(1, 1, 1) end
            end)
            row:SetScript("OnLeave", function(s)
                s:SetBackdropColor(unpack(UI.ROW))
                if s.label then s.label:SetTextColor(0.92, 0.92, 0.92) end
            end)
            row:SetScript("OnClick", function(s)
                local selected = s.value
                Diar:HideSavedPlansRaidFilterMenu()
                Diar:SetSavedPlansRaidFilter(selected)
            end)
            menu.rows[i] = row
        end
        row.value = value
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - ((i - 1) * RAID_FILTER_MENU_ROW_H))
        row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, -4 - ((i - 1) * RAID_FILTER_MENU_ROW_H))
        row.label:SetText(value == "__all__" and "All raids" or value)
        row:Show()
    end
    for i = #values + 1, #menu.rows do
        if menu.rows[i] then menu.rows[i]:Hide() end
    end

    if not self._savedPlansRaidFilterDismiss then
        local dismiss = CreateFrame("Button", "RaidstratsSavedRaidFilterDismiss", UIParent)
        dismiss:SetAllPoints(UIParent)
        dismiss:SetFrameStrata("FULLSCREEN_DIALOG")
        dismiss:EnableMouse(true)
        dismiss:SetAlpha(0.001)
        dismiss:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" or button == "RightButton" then
                Diar:HideSavedPlansRaidFilterMenu()
            end
        end)
        dismiss:Hide()
        self._savedPlansRaidFilterDismiss = dismiss
    end

    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -2)
    self._savedPlansRaidFilterDismiss:SetFrameLevel(math.max(0, (menu:GetFrameLevel() or 0) - 1))
    self._savedPlansRaidFilterDismiss:Show()
    menu:Show()
    if menu.Raise then menu:Raise() end
end

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

local function LayoutSavedPlanRow(rowFrame)
    if not rowFrame then return end
    local compact = IsCompactPlanLibraryMode()
    local cardH = GetPlanCardHeight()
    rowFrame:SetHeight(cardH)
    if compact then
        rowFrame.label:ClearAllPoints()
        rowFrame.label:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 10, -6)
        rowFrame.label:SetPoint("RIGHT", rowFrame, "RIGHT", -PLAN_ROW_ACTIONS_W, 0)
        rowFrame.meta:ClearAllPoints()
        rowFrame.meta:SetPoint("TOPLEFT", rowFrame.label, "BOTTOMLEFT", 0, -1)
        rowFrame.meta:SetPoint("RIGHT", rowFrame, "RIGHT", -PLAN_ROW_ACTIONS_W, 0)
        rowFrame.meta:SetTextColor(0.48, 0.52, 0.58)
        if rowFrame.delBtn then
            rowFrame.delBtn:SetSize(18, 18)
            rowFrame.delBtn:ClearAllPoints()
            rowFrame.delBtn:SetPoint("RIGHT", rowFrame, "RIGHT", -4, 0)
        end
        if rowFrame.syncToggle and rowFrame.delBtn then
            rowFrame.syncToggle:ClearAllPoints()
            rowFrame.syncToggle:SetPoint("RIGHT", rowFrame.delBtn, "LEFT", -6, 0)
        end
    else
        rowFrame.label:ClearAllPoints()
        rowFrame.label:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 10, -8)
        rowFrame.label:SetPoint("RIGHT", rowFrame, "RIGHT", -PLAN_ROW_ACTIONS_W, 0)
        rowFrame.meta:ClearAllPoints()
        rowFrame.meta:SetPoint("TOPLEFT", rowFrame.label, "BOTTOMLEFT", 0, -2)
        rowFrame.meta:SetPoint("RIGHT", rowFrame, "RIGHT", -PLAN_ROW_ACTIONS_W, 0)
        rowFrame.meta:SetTextColor(0.50, 0.54, 0.60)
        if rowFrame.delBtn then
            rowFrame.delBtn:SetSize(20, 20)
            rowFrame.delBtn:ClearAllPoints()
            rowFrame.delBtn:SetPoint("RIGHT", rowFrame, "RIGHT", -4, 0)
        end
        if rowFrame.syncToggle and rowFrame.delBtn then
            rowFrame.syncToggle:ClearAllPoints()
            rowFrame.syncToggle:SetPoint("RIGHT", rowFrame.delBtn, "LEFT", -8, 0)
        end
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
    if delBtn.shadow then
        delBtn.shadow:SetAlpha(0)
        delBtn.shadow:Hide()
    end
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
        syncToggle:SetSize(16, 16)
        syncToggle:SetPoint("RIGHT", delBtn, "LEFT", -8, 0)
        if syncToggle.shadow then
            syncToggle.shadow:SetAlpha(0)
            syncToggle.shadow:Hide()
        end
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
    local query = CleanFilterText(pf.savedPlansSearchQuery)
    local queryLower = query ~= "" and query:lower() or nil
    local raidOptions = CollectRaidFilterOptions(list)
    pf.savedPlansRaidFilterOptions = raidOptions
    if pf.savedPlansRaidFilter then
        local stillValid = false
        for _, raidName in ipairs(raidOptions) do
            if raidName == pf.savedPlansRaidFilter then
                stillValid = true
                break
            end
        end
        if not stillValid then
            pf.savedPlansRaidFilter = nil
        end
    end
    if pf.savedPlansSearchBox then
        local target = pf.savedPlansSearchQuery or ""
        if (pf.savedPlansSearchBox:GetText() or "") ~= target then
            pf.savedPlansSearchBox:SetText(target)
        end
        if not pf.savedPlansSearchBox.__wired then
            pf.savedPlansSearchBox.__wired = true
            pf.savedPlansSearchBox:SetScript("OnTextChanged", function(box, userInput)
                if not userInput then return end
                Diar:SetSavedPlansSearchQuery(box:GetText())
            end)
        end
    end
    if pf.savedPlansRaidFilterBtn then
        local raidText = pf.savedPlansRaidFilter and ("Raid: " .. pf.savedPlansRaidFilter) or "Raid: All raids"
        if #raidText > 28 then
            raidText = raidText:sub(1, 25) .. "..."
        end
        pf.savedPlansRaidFilterBtn:SetText(raidText)
        if not pf.savedPlansRaidFilterBtn.__wired then
            pf.savedPlansRaidFilterBtn.__wired = true
            pf.savedPlansRaidFilterBtn:SetScript("OnClick", function()
                Diar:ShowSavedPlansRaidFilterMenu(pf.savedPlansRaidFilterBtn, pf.savedPlansRaidFilterOptions or {})
            end)
        end
    end

    local filtered = {}
    for _, entry in ipairs(list) do
        local raid = CleanFilterText(entry and entry.raid)
        if raid == "" then raid = "Other" end
        if (not pf.savedPlansRaidFilter or raid == pf.savedPlansRaidFilter)
            and MatchSearchQuery(entry, queryLower) then
            filtered[#filtered + 1] = entry
        end
    end

    if pf.savedPlansCount then
        if #list == 0 then
            pf.savedPlansCount:SetText("")
        elseif #filtered == #list then
            pf.savedPlansCount:SetText("(" .. #filtered .. ")")
        else
            pf.savedPlansCount:SetText(("(%d/%d)"):format(#filtered, #list))
        end
    end

    local sorted = {}
    for i = 1, #filtered do sorted[i] = filtered[i] end
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
            if #list == 0 then
                lbl:SetText("No plans saved yet")
            else
                lbl:SetText("No plans match filters")
            end
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
            if #list == 0 then
                hint:SetText("Use Import Plan below, or paste a share link from chat.")
            else
                hint:SetText("Try another search or raid filter.")
            end
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
            y = y - GetSectionHeight() - 2
        else
            planIndex = planIndex + 1
            local rowFrame = AcquireSavedPlanRow(pf, child, planIndex, w - 4)
            LayoutSavedPlanRow(rowFrame)
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
            y = y - GetPlanCardHeight() - GetListGap()
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
            if not deletedActive and self.plannerData and entry.data then
                local currentKey = self.GetPlanIdentityKey and self:GetPlanIdentityKey(self.plannerData) or nil
                local deletedKey = self.GetPlanIdentityKey and self:GetPlanIdentityKey(entry.data) or nil
                local currentPlanId = tostring(self.plannerData.planId or "")
                local deletedPlanId = tostring(entry.data.planId or "")
                if (currentKey and deletedKey and currentKey == deletedKey)
                    or (currentPlanId ~= "" and deletedPlanId ~= "" and currentPlanId == deletedPlanId) then
                    deletedActive = true
                end
            end
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
    if self.ShowPlannerViewer then
        -- Rebuild planner tabs/chrome so removed plan scenes are fully unloaded.
        self:ShowPlannerViewer({ reloadOnly = true })
    end
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

