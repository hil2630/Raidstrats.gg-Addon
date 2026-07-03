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

if not StaticPopupDialogs["RAIDSTRATSGG_CREATE_PLAN_GROUP"] then
    StaticPopupDialogs["RAIDSTRATSGG_CREATE_PLAN_GROUP"] = {
        text = "Create group:",
        button1 = _G.OKAY or "OK",
        button2 = _G.CANCEL or "Cancel",
        hasEditBox = true,
        maxLetters = 48,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        OnShow = function(self)
            local eb = self.editBox or self.EditBox
            if not eb then return end
            eb:SetText("")
            eb:SetFocus()
        end,
        OnAccept = function(self)
            local eb = self.editBox or self.EditBox
            local text = eb and eb:GetText() or ""
            local entryIds = self.data and self.data.entryIds
            if Diar and Diar.CreateSavedPlansGroupForEntries then
                Diar:CreateSavedPlansGroupForEntries(entryIds, text)
            end
        end,
    }
end

if not StaticPopupDialogs["RAIDSTRATSGG_DELETE_PLAN_GROUP"] then
    StaticPopupDialogs["RAIDSTRATSGG_DELETE_PLAN_GROUP"] = {
        text = "Delete group \"%s\"?\nPlans will be moved to Ungrouped.",
        button1 = _G.YES or "Yes",
        button2 = _G.CANCEL or "Cancel",
        OnAccept = function(self)
            local data = self.data
            local groupId = data and data.groupId
            if groupId and Diar and Diar.DeleteSavedPlansGroup then
                Diar:DeleteSavedPlansGroup(groupId, false)
            end
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
    }
end

if not StaticPopupDialogs["RAIDSTRATSGG_DELETE_PLAN_GROUP_AND_PLANS"] then
    StaticPopupDialogs["RAIDSTRATSGG_DELETE_PLAN_GROUP_AND_PLANS"] = {
        text = "Delete group \"%s\" and all plans in it?",
        button1 = _G.YES or "Yes",
        button2 = _G.CANCEL or "Cancel",
        OnAccept = function(self)
            local data = self.data
            local groupId = data and data.groupId
            if groupId and Diar and Diar.DeleteSavedPlansGroup then
                Diar:DeleteSavedPlansGroup(groupId, true)
            end
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
    }
end

function Diar:EnsureStyledCreatePlanGroupDialog()
    if self._createPlanGroupDialog then
        return self._createPlanGroupDialog
    end

    local f = CreateFrame("Frame", "RaidstratsCreatePlanGroupDialog", UIParent, "BackdropTemplate")
    f:SetSize(420, 190)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(620)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    if SetBackdrop then
        SetBackdrop(f, UI.PANEL, UI.BORDER, 1)
    end
    tinsert(UISpecialFrames, "RaidstratsCreatePlanGroupDialog")
    f:SetScript("OnMouseDown", function(s, button)
        if button == "LeftButton" then s:StartMoving() end
    end)
    f:SetScript("OnMouseUp", function(s)
        s:StopMovingOrSizing()
    end)

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -14)
    title:SetTextColor(0.92, 0.92, 0.96)
    title:SetText("Create Group")

    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    subtitle:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -6)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetTextColor(0.70, 0.74, 0.82)
    subtitle:SetText("Choose a group name for the selected plans.")

    local inputWrap = CreateFrame("Frame", nil, f, "BackdropTemplate")
    inputWrap:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -10)
    inputWrap:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -10)
    inputWrap:SetHeight(30)
    if SetBackdrop then
        SetBackdrop(inputWrap, UI.ROW, UI.BORDER, 1)
    end

    local edit = CreateFrame("EditBox", nil, inputWrap)
    edit:SetAutoFocus(false)
    edit:SetPoint("TOPLEFT", inputWrap, "TOPLEFT", 8, -3)
    edit:SetPoint("BOTTOMRIGHT", inputWrap, "BOTTOMRIGHT", -8, 3)
    edit:SetFontObject("GameFontHighlightSmall")
    edit:SetTextColor(0.94, 0.95, 0.98)
    edit:SetJustifyH("LEFT")
    edit:SetMaxLetters(48)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    edit:SetScript("OnEnterPressed", function()
        local text = strtrim(edit:GetText() or "")
        f:Hide()
        if Diar and Diar.CreateSavedPlansGroupForEntries then
            Diar:CreateSavedPlansGroupForEntries(f.entryIds, text)
        end
    end)
    f.editBox = edit

    local createBtn = CreatePlannerIconBtn(f, "Create", 100, 28)
    createBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 14)
    createBtn:SetScript("OnClick", function()
        local text = strtrim(edit:GetText() or "")
        f:Hide()
        if Diar and Diar.CreateSavedPlansGroupForEntries then
            Diar:CreateSavedPlansGroupForEntries(f.entryIds, text)
        end
    end)

    local cancelBtn = CreatePlannerIconBtn(f, "Cancel", 100, 28)
    cancelBtn:SetPoint("LEFT", createBtn, "RIGHT", 8, 0)
    cancelBtn:SetScript("OnClick", function()
        f:Hide()
    end)

    f:Hide()
    self._createPlanGroupDialog = f
    return f
end

function Diar:ShowStyledCreatePlanGroupDialog(entryIds)
    local dlg = self:EnsureStyledCreatePlanGroupDialog()
    if not dlg then return end
    local ids, seen = {}, {}
    if type(entryIds) == "table" then
        for _, raw in ipairs(entryIds) do
            local id = tonumber(raw)
            if id and not seen[id] then
                seen[id] = true
                ids[#ids + 1] = id
            end
        end
    end
    dlg.entryIds = ids
    dlg.editBox:SetText("")
    dlg:ClearAllPoints()
    dlg:SetPoint("CENTER")
    dlg:Show()
    dlg:Raise()
    dlg.editBox:SetFocus()
end

function Diar:EnsureStyledRenamePlanDialog()
    if self._renamePlanDialog then
        return self._renamePlanDialog
    end

    local f = CreateFrame("Frame", "RaidstratsRenamePlanDialog", UIParent, "BackdropTemplate")
    f:SetSize(420, 190)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(620)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    if SetBackdrop then
        SetBackdrop(f, UI.PANEL, UI.BORDER, 1)
    end
    tinsert(UISpecialFrames, "RaidstratsRenamePlanDialog")
    f:SetScript("OnMouseDown", function(s, button)
        if button == "LeftButton" then s:StartMoving() end
    end)
    f:SetScript("OnMouseUp", function(s)
        s:StopMovingOrSizing()
    end)

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -14)
    title:SetTextColor(0.92, 0.92, 0.96)
    title:SetText("Rename Plan")

    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    subtitle:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -6)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetTextColor(0.70, 0.74, 0.82)
    subtitle:SetText("Enter a new name for this plan.")

    local inputWrap = CreateFrame("Frame", nil, f, "BackdropTemplate")
    inputWrap:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -10)
    inputWrap:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -10)
    inputWrap:SetHeight(30)
    if SetBackdrop then
        SetBackdrop(inputWrap, UI.ROW, UI.BORDER, 1)
    end

    local edit = CreateFrame("EditBox", nil, inputWrap)
    edit:SetAutoFocus(false)
    edit:SetPoint("TOPLEFT", inputWrap, "TOPLEFT", 8, -3)
    edit:SetPoint("BOTTOMRIGHT", inputWrap, "BOTTOMRIGHT", -8, 3)
    edit:SetFontObject("GameFontHighlightSmall")
    edit:SetTextColor(0.94, 0.95, 0.98)
    edit:SetJustifyH("LEFT")
    edit:SetMaxLetters(96)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    edit:SetScript("OnEnterPressed", function()
        local text = strtrim(edit:GetText() or "")
        f:Hide()
        if Diar and Diar.RenameSavedPlan then
            Diar:RenameSavedPlan(f.entryId, text)
        end
    end)
    f.editBox = edit

    local renameBtn = CreatePlannerIconBtn(f, "Rename", 100, 28)
    renameBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 14)
    renameBtn:SetScript("OnClick", function()
        local text = strtrim(edit:GetText() or "")
        f:Hide()
        if Diar and Diar.RenameSavedPlan then
            Diar:RenameSavedPlan(f.entryId, text)
        end
    end)

    local cancelBtn = CreatePlannerIconBtn(f, "Cancel", 100, 28)
    cancelBtn:SetPoint("LEFT", renameBtn, "RIGHT", 8, 0)
    cancelBtn:SetScript("OnClick", function()
        f:Hide()
    end)

    f:Hide()
    self._renamePlanDialog = f
    return f
end

function Diar:ShowStyledRenamePlanDialog(entryId)
    local id = tonumber(entryId)
    if not id then return end
    RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {}, nextId = 1, nextGroupId = 1, groups = {} }
    local store = RaidstratsggSavedPlans
    local currentName = nil
    for _, entry in ipairs(store.list or {}) do
        if tonumber(entry and entry.id) == id then
            currentName = strtrim(tostring(entry.planName or ""))
            break
        end
    end
    if currentName == nil then return end
    local dlg = self:EnsureStyledRenamePlanDialog()
    if not dlg then return end
    dlg.entryId = id
    dlg.editBox:SetText(currentName)
    dlg:ClearAllPoints()
    dlg:SetPoint("CENTER")
    dlg:Show()
    dlg:Raise()
    dlg.editBox:SetFocus()
    dlg.editBox:HighlightText()
end

function Diar:EnsureStyledDeletePlanGroupDialog()
    if self._deletePlanGroupDialog then
        return self._deletePlanGroupDialog
    end

    local f = CreateFrame("Frame", "RaidstratsDeletePlanGroupDialog", UIParent, "BackdropTemplate")
    f:SetSize(440, 184)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(620)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    if SetBackdrop then
        SetBackdrop(f, UI.PANEL, UI.BORDER, 1)
    end
    tinsert(UISpecialFrames, "RaidstratsDeletePlanGroupDialog")
    f:SetScript("OnMouseDown", function(s, button)
        if button == "LeftButton" then s:StartMoving() end
    end)
    f:SetScript("OnMouseUp", function(s)
        s:StopMovingOrSizing()
    end)

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -14)
    title:SetTextColor(0.96, 0.88, 0.88)
    title:SetText("Delete Group")
    f.title = title

    local body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    body:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -10)
    body:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 54)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetWordWrap(true)
    body:SetTextColor(0.84, 0.86, 0.91)
    f.body = body

    local confirmBtn = CreatePlannerIconBtn(f, "Delete", 100, 28)
    confirmBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 14)
    local cancelBtn = CreatePlannerIconBtn(f, "Cancel", 100, 28)
    cancelBtn:SetPoint("LEFT", confirmBtn, "RIGHT", 8, 0)

    confirmBtn:SetScript("OnClick", function()
        local groupId = f.groupId
        local deletePlans = f.deletePlans == true
        f:Hide()
        if groupId and Diar and Diar.DeleteSavedPlansGroup then
            Diar:DeleteSavedPlansGroup(groupId, deletePlans)
        end
    end)
    cancelBtn:SetScript("OnClick", function()
        f:Hide()
    end)

    f:Hide()
    self._deletePlanGroupDialog = f
    return f
end

function Diar:ShowStyledDeletePlanGroupDialog(groupId, groupName, deletePlans)
    groupId = tonumber(groupId)
    if not groupId then return end
    local dlg = self:EnsureStyledDeletePlanGroupDialog()
    if not dlg then return end
    local name = tostring(groupName or "Group")
    dlg.groupId = groupId
    dlg.groupName = name
    dlg.deletePlans = deletePlans == true
    if dlg.deletePlans then
        dlg.body:SetText(("Delete group \"%s\" and all plans in it?"):format(name))
    else
        dlg.body:SetText(("Delete group \"%s\"?\nPlans will be moved to Ungrouped."):format(name))
    end
    dlg:ClearAllPoints()
    dlg:SetPoint("CENTER")
    dlg:Show()
    dlg:Raise()
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
local GROUP_HEADER_H = 24
local PLAN_ROW_ACTIONS_W = 56
local RAID_FILTER_MENU_ROW_H = 22
local GROUP_SHARE_BATCH = 180
local SHARED_GROUP_TTL = 3600
local SEP = string.char(31)

local function EncodeJson(value)
    if C_EncodingUtil and C_EncodingUtil.SerializeJSON then
        local ok, json = pcall(C_EncodingUtil.SerializeJSON, value, { ignoreSerializationErrors = true })
        if ok and type(json) == "string" and json ~= "" then
            return json
        end
    end
    return nil
end

local function DecodeJson(text)
    if C_EncodingUtil and C_EncodingUtil.DeserializeJSON then
        local ok, parsed = pcall(C_EncodingUtil.DeserializeJSON, text)
        if ok and type(parsed) == "table" then
            return parsed
        end
    end
    return nil
end

local function EnsureSavedPlansStorage()
    RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {}, nextId = 1 }
    local store = RaidstratsggSavedPlans
    store.list = store.list or {}
    if store.nextId == nil then store.nextId = 1 end
    store.groups = store.groups or {}
    if store.nextGroupId == nil then
        local maxId = 0
        for _, grp in ipairs(store.groups) do
            local gid = tonumber(grp and grp.id)
            if gid and gid > maxId then maxId = gid end
        end
        store.nextGroupId = maxId + 1
    end
    return store
end

local function GetSavedPlansGroupCollapseMap()
    RaidstratsggSettings = RaidstratsggSettings or {}
    RaidstratsggSettings.planLibraryCollapsedGroups = RaidstratsggSettings.planLibraryCollapsedGroups or {}
    return RaidstratsggSettings.planLibraryCollapsedGroups
end

local function SanitizeGroupShareLabel(name, count)
    local clean = tostring(name or ""):gsub("[%[%]|%c:]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if clean == "" then clean = "Group" end
    if #clean > 40 then clean = clean:sub(1, 40) end
    local n = tonumber(count) or 0
    local suffix = (n == 1) and "Plan" or "Plans"
    return ('Group "%s" - %d %s'):format(clean, n, suffix)
end

local function NormalizeEntryIdList(entryIds)
    local out, seen = {}, {}
    if type(entryIds) ~= "table" then return out end
    for _, raw in ipairs(entryIds) do
        local id = tonumber(raw)
        if id and not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    return out
end

local function GetSavedPlanSelectionIds(pf)
    local selected = {}
    if not pf then return selected end
    local map = pf.savedPlansSelectedIds
    if type(map) ~= "table" then return selected end
    for id, enabled in pairs(map) do
        if enabled then
            local n = tonumber(id)
            if n then selected[#selected + 1] = n end
        end
    end
    table.sort(selected)
    return selected
end

local function SplitSep(str)
    local out = {}
    local start = 1
    while true do
        local i = str:find(SEP, start, true)
        if not i then
            out[#out + 1] = str:sub(start)
            break
        end
        out[#out + 1] = str:sub(start, i - 1)
        start = i + 1
    end
    return out
end

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

local function NormalizeSavedPlanGroupKey(groupId)
    local gid = tonumber(groupId)
    if gid then return gid end
    return "__ungrouped__"
end

local function EntryInSavedPlanGroup(entry, groupKey)
    return NormalizeSavedPlanGroupKey(entry and entry.groupId) == NormalizeSavedPlanGroupKey(groupKey)
end

local function ComparePlanEntries(a, b)
    local aOrder = tonumber(a and a.manualOrder)
    local bOrder = tonumber(b and b.manualOrder)
    if aOrder and bOrder and aOrder ~= bOrder then return aOrder < bOrder end
    if aOrder and not bOrder then return true end
    if bOrder and not aOrder then return false end
    if (a.expansion or "") ~= (b.expansion or "") then return (a.expansion or "") < (b.expansion or "") end
    if (a.raid or "") ~= (b.raid or "") then return (a.raid or "") < (b.raid or "") end
    if (a.boss or "") ~= (b.boss or "") then return (a.boss or "") < (b.boss or "") end
    return (a.planName or "") < (b.planName or "")
end

function Diar:SetSavedPlanGroup(entryId, groupId)
    local store = EnsureSavedPlansStorage()
    local targetId = tonumber(entryId)
    if not targetId then return false end
    local normalizedGroupId = tonumber(groupId)
    local validGroup = false
    if normalizedGroupId then
        for _, grp in ipairs(store.groups) do
            if tonumber(grp and grp.id) == normalizedGroupId then
                validGroup = true
                break
            end
        end
        if not validGroup then
            normalizedGroupId = nil
        end
    end
    for i, entry in ipairs(store.list) do
        if tonumber(entry and entry.id) == targetId then
            local oldGroupKey = NormalizeSavedPlanGroupKey(entry and entry.groupId)
            local newGroupKey = NormalizeSavedPlanGroupKey(normalizedGroupId)
            entry.groupId = normalizedGroupId
            entry.manualOrder = nil
            table.remove(store.list, i)
            local insertAt = #store.list + 1
            for li = #store.list, 1, -1 do
                if EntryInSavedPlanGroup(store.list[li], newGroupKey) then
                    insertAt = li + 1
                    break
                end
            end
            table.insert(store.list, insertAt, entry)
            if self.ReindexSavedPlanManualOrder then
                self:ReindexSavedPlanManualOrder(oldGroupKey)
                if oldGroupKey ~= newGroupKey then
                    self:ReindexSavedPlanManualOrder(newGroupKey)
                end
            end
            self:RefreshSavedPlansList()
            return true
        end
    end
    return false
end

function Diar:ReindexSavedPlanManualOrder(groupId)
    local store = EnsureSavedPlansStorage()
    local targetGroupKey = NormalizeSavedPlanGroupKey(groupId)
    local nextOrder = 1
    for _, entry in ipairs(store.list or {}) do
        if EntryInSavedPlanGroup(entry, targetGroupKey) then
            entry.manualOrder = nextOrder
            nextOrder = nextOrder + 1
        end
    end
end

function Diar:ReorderSavedPlanEntry(dragEntryId, targetEntryId, dropGroupId, insertAfter)
    local store = EnsureSavedPlansStorage()
    local dragId = tonumber(dragEntryId)
    local targetId = tonumber(targetEntryId)
    if not dragId or not targetId or dragId == targetId then return false end

    local dragIndex, dragEntry = nil, nil
    for idx, entry in ipairs(store.list or {}) do
        if tonumber(entry and entry.id) == dragId then
            dragIndex = idx
            dragEntry = entry
            break
        end
    end
    if not dragIndex or not dragEntry then return false end

    local oldGroupKey = NormalizeSavedPlanGroupKey(dragEntry.groupId)
    local newGroupId = (dropGroupId == "__ungrouped__") and nil or tonumber(dropGroupId)
    local newGroupKey = NormalizeSavedPlanGroupKey(newGroupId)
    dragEntry.groupId = newGroupId
    dragEntry.manualOrder = nil

    table.remove(store.list, dragIndex)

    local targetIndex = nil
    for idx, entry in ipairs(store.list or {}) do
        if tonumber(entry and entry.id) == targetId then
            targetIndex = idx
            break
        end
    end

    local insertIndex = #store.list + 1
    if targetIndex then
        insertIndex = targetIndex + ((insertAfter == true) and 1 or 0)
    else
        for idx = #store.list, 1, -1 do
            if EntryInSavedPlanGroup(store.list[idx], newGroupKey) then
                insertIndex = idx + 1
                break
            end
        end
    end

    table.insert(store.list, insertIndex, dragEntry)
    self:ReindexSavedPlanManualOrder(oldGroupKey)
    if oldGroupKey ~= newGroupKey then
        self:ReindexSavedPlanManualOrder(newGroupKey)
    end
    self:RefreshSavedPlansList()
    return true
end

function Diar:RenameSavedPlan(entryId, newName)
    local id = tonumber(entryId)
    if not id then return false end
    local name = strtrim(tostring(newName or ""))
    if name == "" then
        print("|cffff6666[Raidstrats.gg]|r Plan name cannot be empty.")
        return false
    end
    local store = EnsureSavedPlansStorage()
    local renamed = false
    for _, entry in ipairs(store.list or {}) do
        if tonumber(entry and entry.id) == id then
            entry.planName = name
            if entry.data and type(entry.data) == "table" then
                entry.data.planName = name
            end
            renamed = true
            break
        end
    end
    if not renamed then return false end

    if self.plannerData and tonumber(self.plannerData.savedEntryId) == id then
        self.plannerData.planName = name
        if self.plannerFrame and self.plannerFrame:IsShown() and self.ShowPlannerViewer then
            self:ShowPlannerViewer({ reloadOnly = true })
        end
    end

    self:RefreshSavedPlansList()
    print(("|cff00aaff[Raidstrats.gg]|r Renamed plan to |cff00ff00%s|r."):format(name))
    return true
end

function Diar:CreateSavedPlansGroupForEntries(entryIds, groupName)
    local name = strtrim(tostring(groupName or ""))
    if name == "" then
        print("|cffff6666[Raidstrats.gg]|r Group name cannot be empty.")
        return false
    end
    local store = EnsureSavedPlansStorage()
    local ids = NormalizeEntryIdList(entryIds)
    if #ids == 0 then return false end
    local group = {
        id = store.nextGroupId,
        name = name,
    }
    store.nextGroupId = store.nextGroupId + 1
    store.groups[#store.groups + 1] = group
    local changedAny = false
    for _, id in ipairs(ids) do
        if self:SetSavedPlanGroup(id, group.id) then
            changedAny = true
        end
    end
    if not changedAny then
        table.remove(store.groups, #store.groups)
        store.nextGroupId = math.max(1, store.nextGroupId - 1)
        return false
    end
    print(("|cff00aaff[Raidstrats.gg]|r Created group |cff00ff00%s|r (%d plan%s)."):format(
        name, #ids, (#ids == 1 and "" or "s")))
    return true
end

function Diar:CreateSavedPlansGroupForEntry(entryId, groupName)
    local id = tonumber(entryId)
    if not id then return false end
    return self:CreateSavedPlansGroupForEntries({ id }, groupName)
end

function Diar:RemoveSavedPlansFromGroups(entryIds)
    local ids = NormalizeEntryIdList(entryIds)
    if #ids == 0 then return false end
    local store = EnsureSavedPlansStorage()
    local idSet = {}
    for _, id in ipairs(ids) do idSet[id] = true end
    local changed = 0
    for _, entry in ipairs(store.list or {}) do
        local id = tonumber(entry and entry.id)
        if id and idSet[id] and entry.groupId ~= nil then
            entry.groupId = nil
            changed = changed + 1
        end
    end
    if changed > 0 then
        self:RefreshSavedPlansList()
        print(("|cff00aaff[Raidstrats.gg]|r Removed %d plan%s from group%s."):format(
            changed, (changed == 1 and "" or "s"), (changed == 1 and "" or "s")))
        return true
    end
    return false
end

function Diar:DeleteSavedPlansGroup(groupId, deletePlansInGroup)
    local gid = tonumber(groupId)
    if not gid then return false end
    local store = EnsureSavedPlansStorage()
    local groupIndex, groupName = nil, nil
    for i, grp in ipairs(store.groups or {}) do
        if tonumber(grp and grp.id) == gid then
            groupIndex = i
            groupName = strtrim(tostring(grp.name or ""))
            break
        end
    end
    if not groupIndex then return false end
    if groupName == "" then groupName = "Group" end

    local touched = 0
    local deletedActive = false
    if deletePlansInGroup then
        for i = #store.list, 1, -1 do
            local entry = store.list[i]
            if tonumber(entry and entry.groupId) == gid then
                touched = touched + 1
                local entryId = tonumber(entry and entry.id)
                deletedActive = deletedActive or (self.plannerData and self.plannerData.savedEntryId == entryId)
                if not deletedActive and self.plannerData and entry and entry.data then
                    local currentKey = self.GetPlanIdentityKey and self:GetPlanIdentityKey(self.plannerData) or nil
                    local deletedKey = self.GetPlanIdentityKey and self:GetPlanIdentityKey(entry.data) or nil
                    local currentPlanId = tostring(self.plannerData.planId or "")
                    local deletedPlanId = tostring(entry.data.planId or "")
                    if (currentKey and deletedKey and currentKey == deletedKey)
                        or (currentPlanId ~= "" and deletedPlanId ~= "" and currentPlanId == deletedPlanId) then
                        deletedActive = true
                    end
                end
                if entry and entry.data and self.GetPlanIdentityKey then
                    local planKey = self:GetPlanIdentityKey(entry.data)
                    if planKey then
                        local s = self.GetPlannerSettings and self:GetPlannerSettings()
                        if s and s.planAutoImport then s.planAutoImport[planKey] = nil end
                    end
                end
                table.remove(store.list, i)
            end
        end
    else
        for _, entry in ipairs(store.list or {}) do
            if tonumber(entry and entry.groupId) == gid then
                entry.groupId = nil
                touched = touched + 1
            end
        end
    end

    table.remove(store.groups, groupIndex)
    local collapsed = GetSavedPlansGroupCollapseMap()
    collapsed[tostring(gid)] = nil

    if deletePlansInGroup and touched > 0 then
        local pf = self.plannerFrame
        if pf and type(pf.savedPlansSelectedIds) == "table" then
            for id, _ in pairs(pf.savedPlansSelectedIds) do
                local n = tonumber(id)
                if n then
                    local keep = false
                    for _, entry in ipairs(store.list or {}) do
                        if tonumber(entry and entry.id) == n then
                            keep = true
                            break
                        end
                    end
                    if not keep then
                        pf.savedPlansSelectedIds[id] = nil
                    end
                end
            end
        end
    end

    if deletePlansInGroup and deletedActive then
        self:ShowNoPlansState()
    else
        self:RefreshSavedPlansList()
        if deletePlansInGroup and #store.list == 0 then
            self:ShowNoPlansState()
        end
    end

    if deletePlansInGroup then
        print(("|cff00aaff[Raidstrats.gg]|r Deleted group |cff00ff00%s|r and %d plan%s."):format(
            groupName, touched, (touched == 1 and "" or "s")))
    else
        print(("|cff00aaff[Raidstrats.gg]|r Deleted group |cff00ff00%s|r. Moved %d plan%s to Ungrouped."):format(
            groupName, touched, (touched == 1 and "" or "s")))
    end
    return true
end

function Diar:ToggleSavedPlansGroupCollapsed(groupId)
    if groupId == nil then return end
    local collapsed = GetSavedPlansGroupCollapseMap()
    local key = tostring(groupId)
    collapsed[key] = not (collapsed[key] == true)
    self:RefreshSavedPlansList()
end

function Diar:HideSavedPlanContextMenu()
    if self._savedPlanCtxDismiss then
        self._savedPlanCtxDismiss:Hide()
    end
    if self._savedPlanCtxMenu then
        self._savedPlanCtxMenu:Hide()
    end
end

function Diar:HideSavedPlanGroupContextMenu()
    if self._savedPlanGroupCtxDismiss then
        self._savedPlanGroupCtxDismiss:Hide()
    end
    if self._savedPlanGroupCtxMenu then
        self._savedPlanGroupCtxMenu:Hide()
    end
end

function Diar:ShareSavedPlanGroupToGroup(groupId)
    local gid = tonumber(groupId)
    if not gid then return false end
    local chan = self.GetPlanShareChatChannel and self:GetPlanShareChatChannel()
        or (self.GetGroupChatChannel and self:GetGroupChatChannel())
    if chan == "GUILD" or not chan then
        chan = "SAY"
    end
    local store = EnsureSavedPlansStorage()
    local groupName = nil
    for _, g in ipairs(store.groups or {}) do
        if tonumber(g and g.id) == gid then
            groupName = strtrim(tostring(g.name or ""))
            break
        end
    end
    if not groupName or groupName == "" then
        print("|cffff6666[Raidstrats.gg]|r Could not find that group.")
        return false
    end
    local plans = {}
    for _, entry in ipairs(store.list or {}) do
        if tonumber(entry and entry.groupId) == gid and entry.data then
            if self.EnsureSavedEntryInstanceKey then
                self:EnsureSavedEntryInstanceKey(entry)
            end
            local payload = self.BuildSharePayload and self:BuildSharePayload(entry.data) or nil
            if payload and payload ~= "" then
                plans[#plans + 1] = {
                    name = tostring(entry.planName or "Plan"),
                    payload = payload,
                }
            end
        end
    end
    if #plans == 0 then
        print("|cffff6666[Raidstrats.gg]|r Group has no sharable plans.")
        return false
    end

    local packet = {
        groupName = groupName,
        plans = plans,
    }
    local json = EncodeJson(packet)
    if not json or json == "" then
        print("|cffff6666[Raidstrats.gg]|r Could not encode group share payload.")
        return false
    end

    local linkLabel = SanitizeGroupShareLabel(groupName, #plans)
    self._sharedPlanGroups = self._sharedPlanGroups or {}
    self._sharedPlanGroups[linkLabel] = {
        payload = json,
        t = time(),
        groupName = groupName,
        count = #plans,
    }
    SendChatMessage(("[Raidstrats: %s]"):format(linkLabel), chan)
    print(("|cff00aaff[Raidstrats.gg]|r Shared \"%s\" to %s. Others click the link to import."):format(
        linkLabel, tostring(chan):lower()))
    return true
end

function Diar:BuildSavedPlanGroupShareToken(groupId)
    local gid = tonumber(groupId)
    if not gid then return nil end
    local store = EnsureSavedPlansStorage()
    local groupName = nil
    for _, g in ipairs(store.groups or {}) do
        if tonumber(g and g.id) == gid then
            groupName = strtrim(tostring(g.name or ""))
            break
        end
    end
    if not groupName or groupName == "" then
        return nil
    end
    local plans = {}
    for _, entry in ipairs(store.list or {}) do
        if tonumber(entry and entry.groupId) == gid and entry.data then
            if self.EnsureSavedEntryInstanceKey then
                self:EnsureSavedEntryInstanceKey(entry)
            end
            local payload = self.BuildSharePayload and self:BuildSharePayload(entry.data) or nil
            if payload and payload ~= "" then
                plans[#plans + 1] = {
                    name = tostring(entry.planName or "Plan"),
                    payload = payload,
                }
            end
        end
    end
    if #plans == 0 then
        return nil
    end
    local packet = {
        groupName = groupName,
        plans = plans,
    }
    local json = EncodeJson(packet)
    if not json or json == "" then
        return nil
    end
    local linkLabel = SanitizeGroupShareLabel(groupName, #plans)
    self._sharedPlanGroups = self._sharedPlanGroups or {}
    self._sharedPlanGroups[linkLabel] = {
        payload = json,
        t = time(),
        groupName = groupName,
        count = #plans,
    }
    return ("[Raidstrats: %s]"):format(linkLabel)
end

function Diar:InsertSavedPlanGroupShareTokenIntoActiveChat(groupId)
    local token = self:BuildSavedPlanGroupShareToken(groupId)
    if not token then return false end
    if self.InsertShareTokenIntoActiveChat then
        return self:InsertShareTokenIntoActiveChat(token)
    end
    return false
end

function Diar:ShowSavedPlanGroupContextMenu(anchorBtn, groupId)
    if not anchorBtn then return end
    local gid = tonumber(groupId)
    if not gid then return end
    local store = EnsureSavedPlansStorage()
    local groupName = "Group"
    for _, g in ipairs(store.groups or {}) do
        if tonumber(g and g.id) == gid then
            local name = strtrim(tostring(g.name or ""))
            if name ~= "" then groupName = name end
            break
        end
    end

    local menu = self._savedPlanGroupCtxMenu
    if not menu then
        menu = CreateFrame("Frame", "RaidstratsSavedPlanGroupContextMenu", UIParent, "BackdropTemplate")
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(560)
        menu:SetSize(196, 82)
        menu:EnableMouse(true)
        if SetBackdrop then SetBackdrop(menu, UI.PANEL, UI.BORDER, 1) end

        local shareBtn = CreateFrame("Button", nil, menu, "BackdropTemplate")
        shareBtn:SetHeight(22)
        shareBtn:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4)
        shareBtn:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, -4)
        if SetBackdrop then SetBackdrop(shareBtn, UI.ROW, UI.BORDER, 1) end
        local shareLbl = shareBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        shareLbl:SetPoint("LEFT", shareBtn, "LEFT", 8, 0)
        shareLbl:SetPoint("RIGHT", shareBtn, "RIGHT", -8, 0)
        shareLbl:SetJustifyH("LEFT")
        shareLbl:SetText("Share to group")
        shareBtn:SetScript("OnEnter", function(s) s:SetBackdropColor(unpack(UI.ROW_HOV)) end)
        shareBtn:SetScript("OnLeave", function(s) s:SetBackdropColor(unpack(UI.ROW)) end)
        shareBtn:SetScript("OnClick", function()
            local id = tonumber(menu.groupId)
            Diar:HideSavedPlanGroupContextMenu()
            if id and Diar.ShareSavedPlanGroupToGroup then
                Diar:ShareSavedPlanGroupToGroup(id)
            end
        end)
        menu.shareBtn = shareBtn
        menu.shareLbl = shareLbl

        local deleteGroupBtn = CreateFrame("Button", nil, menu, "BackdropTemplate")
        deleteGroupBtn:SetHeight(22)
        deleteGroupBtn:SetPoint("TOPLEFT", shareBtn, "BOTTOMLEFT", 0, -2)
        deleteGroupBtn:SetPoint("TOPRIGHT", shareBtn, "BOTTOMRIGHT", 0, -2)
        if SetBackdrop then SetBackdrop(deleteGroupBtn, UI.ROW, UI.BORDER, 1) end
        local deleteGroupLbl = deleteGroupBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        deleteGroupLbl:SetPoint("LEFT", deleteGroupBtn, "LEFT", 8, 0)
        deleteGroupLbl:SetPoint("RIGHT", deleteGroupBtn, "RIGHT", -8, 0)
        deleteGroupLbl:SetJustifyH("LEFT")
        deleteGroupLbl:SetText("Delete group")
        deleteGroupBtn:SetScript("OnEnter", function(s) s:SetBackdropColor(unpack(UI.ROW_HOV)) end)
        deleteGroupBtn:SetScript("OnLeave", function(s) s:SetBackdropColor(unpack(UI.ROW)) end)
        deleteGroupBtn:SetScript("OnClick", function()
            local id = tonumber(menu.groupId)
            local name = tostring(menu.groupName or "Group")
            Diar:HideSavedPlanGroupContextMenu()
            if id then
                Diar:ShowStyledDeletePlanGroupDialog(id, name, false)
            end
        end)
        menu.deleteGroupBtn = deleteGroupBtn
        menu.deleteGroupLbl = deleteGroupLbl

        local deleteAllBtn = CreateFrame("Button", nil, menu, "BackdropTemplate")
        deleteAllBtn:SetHeight(22)
        deleteAllBtn:SetPoint("TOPLEFT", deleteGroupBtn, "BOTTOMLEFT", 0, -2)
        deleteAllBtn:SetPoint("TOPRIGHT", deleteGroupBtn, "BOTTOMRIGHT", 0, -2)
        if SetBackdrop then SetBackdrop(deleteAllBtn, UI.ROW, UI.BORDER, 1) end
        local deleteAllLbl = deleteAllBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        deleteAllLbl:SetPoint("LEFT", deleteAllBtn, "LEFT", 8, 0)
        deleteAllLbl:SetPoint("RIGHT", deleteAllBtn, "RIGHT", -8, 0)
        deleteAllLbl:SetJustifyH("LEFT")
        deleteAllLbl:SetText("Delete group + plans")
        deleteAllBtn:SetScript("OnEnter", function(s) s:SetBackdropColor(unpack(UI.ROW_HOV)) end)
        deleteAllBtn:SetScript("OnLeave", function(s) s:SetBackdropColor(unpack(UI.ROW)) end)
        deleteAllBtn:SetScript("OnClick", function()
            local id = tonumber(menu.groupId)
            local name = tostring(menu.groupName or "Group")
            Diar:HideSavedPlanGroupContextMenu()
            if id then
                Diar:ShowStyledDeletePlanGroupDialog(id, name, true)
            end
        end)
        menu.deleteAllBtn = deleteAllBtn
        menu.deleteAllLbl = deleteAllLbl

        menu:SetScript("OnHide", function()
            if Diar._savedPlanGroupCtxDismiss then
                Diar._savedPlanGroupCtxDismiss:Hide()
            end
        end)
        if UISpecialFrames then
            tinsert(UISpecialFrames, "RaidstratsSavedPlanGroupContextMenu")
        end
        self._savedPlanGroupCtxMenu = menu
    end

    if not self._savedPlanGroupCtxDismiss then
        local dismiss = CreateFrame("Button", "RaidstratsSavedPlanGroupContextDismiss", UIParent)
        dismiss:SetAllPoints(UIParent)
        dismiss:SetFrameStrata("FULLSCREEN_DIALOG")
        dismiss:EnableMouse(true)
        dismiss:SetAlpha(0.001)
        dismiss:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" or button == "RightButton" then
                Diar:HideSavedPlanGroupContextMenu()
            end
        end)
        dismiss:Hide()
        self._savedPlanGroupCtxDismiss = dismiss
    end

    menu.groupId = gid
    menu.groupName = groupName
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -2)
    self._savedPlanGroupCtxDismiss:SetFrameLevel(math.max(0, (menu:GetFrameLevel() or 0) - 1))
    self._savedPlanGroupCtxDismiss:Show()
    menu:Show()
    if menu.Raise then menu:Raise() end
end

function Diar:EnsureSavedPlansGroupByName(groupName)
    local name = strtrim(tostring(groupName or ""))
    if name == "" then return nil end
    local store = EnsureSavedPlansStorage()
    for _, grp in ipairs(store.groups or {}) do
        if strlower(strtrim(tostring(grp.name or ""))) == strlower(name) then
            return tonumber(grp.id)
        end
    end
    local group = { id = store.nextGroupId, name = name }
    store.nextGroupId = store.nextGroupId + 1
    store.groups[#store.groups + 1] = group
    return group.id
end

function Diar:SendSharedPlanGroupWhisper(target, linkLabel, payloadJson)
    if not target or not linkLabel or not payloadJson or payloadJson == "" then return false end
    local total = math.ceil(#payloadJson / GROUP_SHARE_BATCH)
    local prefix = self.COMM_PLAN_PREFIX or "RAIDSTRATS_PLAN"
    for j = 1, total do
        local start = (j - 1) * GROUP_SHARE_BATCH + 1
        local chunk = payloadJson:sub(start, start + GROUP_SHARE_BATCH - 1)
        self:SendCommMessage(prefix, table.concat({ "GDAT", linkLabel, tostring(j), tostring(total), chunk }, SEP), "WHISPER", target, "BULK")
    end
    return true
end

function Diar:ImportSharedPlanGroupPayload(payloadJson, sender)
    if type(payloadJson) ~= "string" or payloadJson == "" then return false end
    local parsed = DecodeJson(payloadJson)
    if type(parsed) ~= "table" or type(parsed.plans) ~= "table" then
        print("|cffff6666[Raidstrats.gg]|r Could not import shared plan group.")
        return false
    end
    local imported = 0
    local importedEntryIds = {}
    local prevPlannerData = self.plannerData and CopyPlanData(self.plannerData) or nil
    for _, plan in ipairs(parsed.plans) do
        local payload = type(plan) == "table" and plan.payload or nil
        if type(payload) == "string" and payload ~= "" and self.ImportPlanFromPasteString then
            local ok = self:ImportPlanFromPasteString("!raidstrats-addon-" .. payload)
            if ok then
                imported = imported + 1
                local entryId = self.plannerData and tonumber(self.plannerData.savedEntryId)
                if entryId then importedEntryIds[#importedEntryIds + 1] = entryId end
            end
        end
    end
    if prevPlannerData then
        self.plannerData = prevPlannerData
        if self.plannerFrame and self.plannerFrame:IsShown() and self.ShowPlannerViewer then
            self:ShowPlannerViewer({ reloadOnly = true })
        end
    end
    if imported > 0 then
        local groupId = self:EnsureSavedPlansGroupByName(parsed.groupName)
        if groupId then
            for _, entryId in ipairs(importedEntryIds) do
                self:SetSavedPlanGroup(entryId, groupId)
            end
        end
        if self.OpenPlannerAfterShareImport then
            self:OpenPlannerAfterShareImport()
        end
        if self.RefreshSavedPlansList then self:RefreshSavedPlansList() end
        if self.HideImportProgress then self:HideImportProgress() end
        print(("|cff00aaff[Raidstrats.gg]|r Imported shared group \"%s\" (%d plan%s) from %s."):format(
            tostring(parsed.groupName or "Group"), imported, (imported == 1 and "" or "s"), tostring(sender or "someone")))
        return true
    end
    if self.HideImportProgress then self:HideImportProgress() end
    print("|cffff6666[Raidstrats.gg]|r Shared group received, but no plans could be imported.")
    return false
end

function Diar:TryCompleteSharedPlanGroupImport(transferId, sender)
    local incomingMap = self._sharedPlanGroupsIncoming
    local entry = incomingMap and incomingMap[transferId]
    if not entry or not entry.total or entry.total < 1 then return false end
    for i = 1, entry.total do
        if not entry.chunks[i] then return false end
    end
    local json = table.concat(entry.chunks, "")
    incomingMap[transferId] = nil
    return self:ImportSharedPlanGroupPayload(json, sender)
end

function Diar:HandleSharedPlanGroupComm(msg, sender)
    if type(msg) ~= "string" then return false end
    local parts = SplitSep(msg)
    local tag = parts[1]
    if tag == "GSHR" then
        local transferId = parts[2]
        local groupName = parts[3]
        if not transferId or transferId == "" then return true end
        self._sharedPlanGroupsIncoming = self._sharedPlanGroupsIncoming or {}
        self._sharedPlanGroupsIncoming[transferId] = {
            groupName = groupName or "Group",
            totalPlans = tonumber(parts[4]) or 0,
            chunks = {},
            total = nil,
            sender = sender,
            t = GetTime(),
        }
        return true
    elseif tag == "GREQ" then
        local linkLabel = parts[2]
        if not linkLabel or linkLabel == "" then return true end
        self._sharedPlanGroups = self._sharedPlanGroups or {}
        local shared = self._sharedPlanGroups[linkLabel]
        if not shared or type(shared.payload) ~= "string" or shared.payload == "" then return true end
        if (time() - (shared.t or 0)) > SHARED_GROUP_TTL then
            self._sharedPlanGroups[linkLabel] = nil
            return true
        end
        self:SendSharedPlanGroupWhisper(sender, linkLabel, shared.payload)
        return true
    elseif tag == "GDAT" then
        local transferId = parts[2]
        local i = tonumber(parts[3])
        local n = tonumber(parts[4])
        local chunk = parts[5]
        if not transferId or not i or not n or type(chunk) ~= "string" then return true end
        self._sharedPlanGroupsIncoming = self._sharedPlanGroupsIncoming or {}
        local entry = self._sharedPlanGroupsIncoming[transferId]
        if not entry then
            entry = { chunks = {}, total = n, sender = sender, t = GetTime(), groupName = "Group" }
            self._sharedPlanGroupsIncoming[transferId] = entry
        end
        entry.total = entry.total or n
        entry.chunks[i] = chunk
        entry.t = GetTime()
        local count = 0
        for idx = 1, entry.total do
            if entry.chunks[idx] then count = count + 1 end
        end
        if self.UpdateImportProgress then
            self:UpdateImportProgress(count, entry.total)
        end
        self:TryCompleteSharedPlanGroupImport(transferId, sender)
        return true
    end
    return false
end

function Diar:ShowSavedPlanContextMenu(anchorBtn, entryIds)
    if not anchorBtn then return end
    local ids = NormalizeEntryIdList(entryIds)
    if #ids == 0 then return end
    local store = EnsureSavedPlansStorage()
    local byId = {}
    for _, entry in ipairs(store.list or {}) do
        local id = tonumber(entry and entry.id)
        if id then byId[id] = entry end
    end
    local canRemoveFromGroup = false
    local canRename = (#ids == 1)
    for _, id in ipairs(ids) do
        local entry = byId[id]
        if entry and entry.groupId ~= nil then
            canRemoveFromGroup = true
            break
        end
    end

    local menu = self._savedPlanCtxMenu
    if not menu then
        menu = CreateFrame("Frame", "RaidstratsSavedPlanContextMenu", UIParent, "BackdropTemplate")
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(560)
        menu:SetSize(196, 92)
        menu:EnableMouse(true)
        if SetBackdrop then SetBackdrop(menu, UI.PANEL, UI.BORDER, 1) end
        local createBtn = CreateFrame("Button", nil, menu, "BackdropTemplate")
        createBtn:SetHeight(24)
        createBtn:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4)
        createBtn:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, -4)
        if SetBackdrop then SetBackdrop(createBtn, UI.ROW, UI.BORDER, 1) end
        local createLbl = createBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        createLbl:SetPoint("LEFT", createBtn, "LEFT", 8, 0)
        createLbl:SetPoint("RIGHT", createBtn, "RIGHT", -8, 0)
        createLbl:SetJustifyH("LEFT")
        createLbl:SetText("Create group")
        createBtn:SetScript("OnEnter", function(s)
            s:SetBackdropColor(unpack(UI.ROW_HOV))
        end)
        createBtn:SetScript("OnLeave", function(s)
            s:SetBackdropColor(unpack(UI.ROW))
        end)
        createBtn:SetScript("OnClick", function()
            Diar:HideSavedPlanContextMenu()
            Diar:ShowStyledCreatePlanGroupDialog(menu.entryIds)
        end)
        menu.createGroupBtn = createBtn
        menu.createGroupLabel = createLbl

        local renameBtn = CreateFrame("Button", nil, menu, "BackdropTemplate")
        renameBtn:SetHeight(24)
        renameBtn:SetPoint("TOPLEFT", createBtn, "BOTTOMLEFT", 0, -4)
        renameBtn:SetPoint("TOPRIGHT", createBtn, "BOTTOMRIGHT", 0, -4)
        if SetBackdrop then SetBackdrop(renameBtn, UI.ROW, UI.BORDER, 1) end
        local renameLbl = renameBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        renameLbl:SetPoint("LEFT", renameBtn, "LEFT", 8, 0)
        renameLbl:SetPoint("RIGHT", renameBtn, "RIGHT", -8, 0)
        renameLbl:SetJustifyH("LEFT")
        renameLbl:SetText("Rename")
        renameBtn:SetScript("OnEnter", function(s)
            s:SetBackdropColor(unpack(UI.ROW_HOV))
        end)
        renameBtn:SetScript("OnLeave", function(s)
            s:SetBackdropColor(unpack(UI.ROW))
        end)
        renameBtn:SetScript("OnClick", function()
            local id = menu.entryIds and tonumber(menu.entryIds[1])
            Diar:HideSavedPlanContextMenu()
            if id and Diar.ShowStyledRenamePlanDialog then
                Diar:ShowStyledRenamePlanDialog(id)
            end
        end)
        menu.renameBtn = renameBtn
        menu.renameLabel = renameLbl

        local removeBtn = CreateFrame("Button", nil, menu, "BackdropTemplate")
        removeBtn:SetHeight(24)
        removeBtn:SetPoint("TOPLEFT", renameBtn, "BOTTOMLEFT", 0, -4)
        removeBtn:SetPoint("TOPRIGHT", renameBtn, "BOTTOMRIGHT", 0, -4)
        if SetBackdrop then SetBackdrop(removeBtn, UI.ROW, UI.BORDER, 1) end
        local removeLbl = removeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        removeLbl:SetPoint("LEFT", removeBtn, "LEFT", 8, 0)
        removeLbl:SetPoint("RIGHT", removeBtn, "RIGHT", -8, 0)
        removeLbl:SetJustifyH("LEFT")
        removeLbl:SetText("Remove from group")
        removeBtn:SetScript("OnEnter", function(s)
            s:SetBackdropColor(unpack(UI.ROW_HOV))
        end)
        removeBtn:SetScript("OnLeave", function(s)
            s:SetBackdropColor(unpack(UI.ROW))
        end)
        removeBtn:SetScript("OnClick", function()
            Diar:HideSavedPlanContextMenu()
            if menu.entryIds and Diar.RemoveSavedPlansFromGroups then
                Diar:RemoveSavedPlansFromGroups(menu.entryIds)
            end
        end)
        menu.removeGroupBtn = removeBtn
        menu.removeGroupLabel = removeLbl
        menu:SetScript("OnHide", function()
            if Diar._savedPlanCtxDismiss then
                Diar._savedPlanCtxDismiss:Hide()
            end
        end)
        if UISpecialFrames then
            tinsert(UISpecialFrames, "RaidstratsSavedPlanContextMenu")
        end
        self._savedPlanCtxMenu = menu
    end

    if not self._savedPlanCtxDismiss then
        local dismiss = CreateFrame("Button", "RaidstratsSavedPlanContextDismiss", UIParent)
        dismiss:SetAllPoints(UIParent)
        dismiss:SetFrameStrata("FULLSCREEN_DIALOG")
        dismiss:EnableMouse(true)
        dismiss:SetAlpha(0.001)
        dismiss:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" or button == "RightButton" then
                Diar:HideSavedPlanContextMenu()
            end
        end)
        dismiss:Hide()
        self._savedPlanCtxDismiss = dismiss
    end

    menu.entryIds = ids
    local label = "Create group"
    if #ids > 1 then
        label = ("Create group (%d selected)"):format(#ids)
    end
    if menu.createGroupLabel then
        menu.createGroupLabel:SetText(label)
    end
    if menu.renameBtn then
        if canRename then
            menu.renameBtn:Show()
        else
            menu.renameBtn:Hide()
        end
    end
    if menu.removeGroupBtn then
        local removeLabel = (#ids > 1) and ("Remove from group (%d selected)"):format(#ids) or "Remove from group"
        if menu.removeGroupLabel then
            menu.removeGroupLabel:SetText(removeLabel)
        end
        if canRemoveFromGroup then
            menu.removeGroupBtn:Show()
            if canRename then
                menu.removeGroupBtn:ClearAllPoints()
                menu.removeGroupBtn:SetPoint("TOPLEFT", menu.renameBtn, "BOTTOMLEFT", 0, -4)
                menu.removeGroupBtn:SetPoint("TOPRIGHT", menu.renameBtn, "BOTTOMRIGHT", 0, -4)
                menu:SetHeight(88)
            else
                menu.removeGroupBtn:ClearAllPoints()
                menu.removeGroupBtn:SetPoint("TOPLEFT", menu.createGroupBtn, "BOTTOMLEFT", 0, -4)
                menu.removeGroupBtn:SetPoint("TOPRIGHT", menu.createGroupBtn, "BOTTOMRIGHT", 0, -4)
                menu:SetHeight(60)
            end
        else
            menu.removeGroupBtn:Hide()
            if canRename then
                menu:SetHeight(60)
            else
                menu:SetHeight(32)
            end
        end
    end
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -2)
    self._savedPlanCtxDismiss:SetFrameLevel(math.max(0, (menu:GetFrameLevel() or 0) - 1))
    self._savedPlanCtxDismiss:Show()
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

local function ApplySavedPlanRowState(rowFrame, entry, isActive, planKey, autoEnabled, isSelected, isMultiSelected, deleteConfirm)
    rowFrame.entryId = entry.id
    rowFrame.planKey = planKey

    local title = entry.planName or "Unnamed"
    rowFrame.label:SetText(title)
    rowFrame.meta:SetText(BuildPlanMetaLine(entry))

    if isActive then
        rowFrame.activeBar:Show()
        if isMultiSelected and isSelected then
            rowFrame.activeBar:SetColorTexture(0.72, 0.42, 0.96, 1)
        else
            rowFrame.activeBar:SetColorTexture(unpack(UI.ACCENT))
        end
        rowFrame:SetBackdropColor(0.12, 0.16, 0.24, 0.98)
        rowFrame.label:SetTextColor(0.95, 0.88, 0.45)
        rowFrame.meta:SetTextColor(0.62, 0.66, 0.72)
    elseif isSelected then
        rowFrame.activeBar:Show()
        if isMultiSelected then
            rowFrame.activeBar:SetColorTexture(0.72, 0.42, 0.96, 1)
        else
            rowFrame.activeBar:SetColorTexture(unpack(UI.ACCENT))
        end
        rowFrame:SetBackdropColor(0.10, 0.14, 0.22, 0.98)
        rowFrame.label:SetTextColor(0.85, 0.92, 1.00)
        rowFrame.meta:SetTextColor(0.56, 0.62, 0.72)
    else
        rowFrame.activeBar:Hide()
        rowFrame:SetBackdropColor(unpack(UI.ROW))
        rowFrame.label:SetTextColor(0.92, 0.92, 0.92)
        rowFrame.meta:SetTextColor(0.50, 0.54, 0.60)
    end

    if not isSelected then
        rowFrame.activeBar:SetColorTexture(unpack(UI.ACCENT))
    end

    if planKey and rowFrame.syncToggle then
        rowFrame.syncToggle.planKey = planKey
        rowFrame.syncToggle:SetChecked(autoEnabled and true or false)
        rowFrame.syncToggle:Show()
    elseif rowFrame.syncToggle then
        rowFrame.syncToggle:Hide()
    end

    if deleteConfirm then
        rowFrame.meta:SetText("Are you sure?")
        rowFrame.meta:SetTextColor(0.94, 0.72, 0.72)
        if rowFrame.delBtn then rowFrame.delBtn:Hide() end
        if rowFrame.delCancelBtn then rowFrame.delCancelBtn:Show() end
        if rowFrame.delConfirmBtn then rowFrame.delConfirmBtn:Show() end
        if rowFrame.syncToggle then rowFrame.syncToggle:Hide() end
    else
        if rowFrame.delBtn then rowFrame.delBtn:Show() end
        if rowFrame.delCancelBtn then rowFrame.delCancelBtn:Hide() end
        if rowFrame.delConfirmBtn then rowFrame.delConfirmBtn:Hide() end
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
        if rowFrame.delConfirmBtn then
            rowFrame.delConfirmBtn:SetSize(26, 18)
            rowFrame.delConfirmBtn:ClearAllPoints()
            rowFrame.delConfirmBtn:SetPoint("RIGHT", rowFrame, "RIGHT", -4, 0)
        end
        if rowFrame.delCancelBtn and rowFrame.delConfirmBtn then
            rowFrame.delCancelBtn:SetSize(26, 18)
            rowFrame.delCancelBtn:ClearAllPoints()
            rowFrame.delCancelBtn:SetPoint("RIGHT", rowFrame.delConfirmBtn, "LEFT", -4, 0)
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
        if rowFrame.delConfirmBtn then
            rowFrame.delConfirmBtn:SetSize(28, 20)
            rowFrame.delConfirmBtn:ClearAllPoints()
            rowFrame.delConfirmBtn:SetPoint("RIGHT", rowFrame, "RIGHT", -4, 0)
        end
        if rowFrame.delCancelBtn and rowFrame.delConfirmBtn then
            rowFrame.delCancelBtn:SetSize(28, 20)
            rowFrame.delCancelBtn:ClearAllPoints()
            rowFrame.delCancelBtn:SetPoint("RIGHT", rowFrame.delConfirmBtn, "LEFT", -4, 0)
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
    if rowFrame and rowFrame.__cardV6 and rowFrame.syncToggle then return rowFrame end
    if rowFrame then
        rowFrame:Hide()
        rowFrame:SetParent(nil)
    end

    rowFrame = CreateFrame("Button", nil, child, "BackdropTemplate")
    rowFrame.__cardV6 = true
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
    delBtn:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" then
            rowFrame.__blockRowClick = true
        end
    end)

    local delConfirmBtn = CreateFrame("Button", nil, rowFrame, "BackdropTemplate")
    delConfirmBtn:SetSize(28, 20)
    delConfirmBtn:SetPoint("RIGHT", rowFrame, "RIGHT", -4, 0)
    SetBackdrop(delConfirmBtn, {0, 0, 0, 0}, {0.22, 0.55, 0.22, 0.95}, 1)
    local confirmFs = delConfirmBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    confirmFs:SetPoint("CENTER")
    confirmFs:SetText("Yes")
    confirmFs:SetTextColor(0.70, 0.98, 0.70)
    delConfirmBtn.label = confirmFs
    delConfirmBtn:SetScript("OnEnter", function(s)
        s:SetBackdropColor(0.08, 0.24, 0.08, 0.75)
        s:SetBackdropBorderColor(0.30, 0.85, 0.30, 1)
        s.label:SetTextColor(0.75, 1, 0.75)
        GameTooltip:SetOwner(s, "ANCHOR_LEFT")
        GameTooltip:SetText("Confirm delete", 1, 1, 1)
        GameTooltip:Show()
    end)
    delConfirmBtn:SetScript("OnLeave", function(s)
        s:SetBackdropColor(0, 0, 0, 0)
        s:SetBackdropBorderColor(0.22, 0.55, 0.22, 0.95)
        s.label:SetTextColor(0.70, 0.98, 0.70)
        GameTooltip:Hide()
    end)
    delConfirmBtn:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" then
            rowFrame.__blockRowClick = true
        end
    end)
    delConfirmBtn:Hide()
    rowFrame.delConfirmBtn = delConfirmBtn

    local delCancelBtn = CreateFrame("Button", nil, rowFrame, "BackdropTemplate")
    delCancelBtn:SetSize(28, 20)
    delCancelBtn:SetPoint("RIGHT", delConfirmBtn, "LEFT", -4, 0)
    SetBackdrop(delCancelBtn, {0, 0, 0, 0}, {0.55, 0.22, 0.22, 0.95}, 1)
    local cancelFs = delCancelBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cancelFs:SetPoint("CENTER")
    cancelFs:SetText("No")
    cancelFs:SetTextColor(0.98, 0.70, 0.70)
    delCancelBtn.label = cancelFs
    delCancelBtn:SetScript("OnEnter", function(s)
        s:SetBackdropColor(0.28, 0.10, 0.10, 0.75)
        s:SetBackdropBorderColor(0.85, 0.30, 0.30, 1)
        s.label:SetTextColor(1, 0.55, 0.55)
        GameTooltip:SetOwner(s, "ANCHOR_LEFT")
        GameTooltip:SetText("Cancel delete", 1, 1, 1)
        GameTooltip:Show()
    end)
    delCancelBtn:SetScript("OnLeave", function(s)
        s:SetBackdropColor(0, 0, 0, 0)
        s:SetBackdropBorderColor(0.55, 0.22, 0.22, 0.95)
        s.label:SetTextColor(0.98, 0.70, 0.70)
        GameTooltip:Hide()
    end)
    delCancelBtn:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" then
            rowFrame.__blockRowClick = true
        end
    end)
    delCancelBtn:Hide()
    rowFrame.delCancelBtn = delCancelBtn

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

local function AcquireSavedPlanGroupRow(pf, child, groupIndex, w)
    pf.savedPlansGroupRows = pf.savedPlansGroupRows or {}
    local row = pf.savedPlansGroupRows[groupIndex]
    if row and row.__groupRowV1 then return row end
    if row then
        row:Hide()
        row:SetParent(nil)
    end

    row = CreateFrame("Button", nil, child, "BackdropTemplate")
    row.__groupRowV1 = true
    row:SetHeight(GROUP_HEADER_H)
    row:SetWidth(w)
    SetBackdrop(row, UI.TOOLBAR, UI.BORDER, 1)

    local marker = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    marker:SetPoint("LEFT", row, "LEFT", 8, 0)
    marker:SetWidth(14)
    marker:SetJustifyH("CENTER")
    row.marker = marker

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", marker, "RIGHT", 6, 0)
    label:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    label:SetJustifyH("LEFT")
    row.label = label

    row:SetScript("OnEnter", function(s)
        s:SetBackdropColor(unpack(UI.ROW_HOV))
    end)
    row:SetScript("OnLeave", function(s)
        s:SetBackdropColor(unpack(UI.TOOLBAR))
    end)

    pf.savedPlansGroupRows[groupIndex] = row
    return row
end

local function ResolveSavedPlanDropTarget(pf)
    local function ReadDropTargetFromFocus(focus)
        local guard = 0
        while focus and guard < 24 do
            if focus.__savedPlanGroupDropId ~= nil then
                return focus.__savedPlanGroupDropId, focus
            end
            if type(focus.GetParent) ~= "function" then break end
            focus = focus:GetParent()
            guard = guard + 1
        end
        return nil, nil
    end

    if type(GetMouseFocus) == "function" then
        local focus = GetMouseFocus()
        local byFocusId, byFocusFrame = ReadDropTargetFromFocus(focus)
        if byFocusId ~= nil then return byFocusId, byFocusFrame end
    end

    if type(MouseIsOver) == "function" and pf then
        if type(pf.savedPlansRows) == "table" then
            for _, planRow in ipairs(pf.savedPlansRows) do
                if planRow and planRow:IsShown() and MouseIsOver(planRow) and planRow.__savedPlanGroupDropId ~= nil then
                    return planRow.__savedPlanGroupDropId, planRow
                end
            end
        end
        if type(pf.savedPlansGroupRows) == "table" then
            for _, headerRow in ipairs(pf.savedPlansGroupRows) do
                if headerRow and headerRow:IsShown() and MouseIsOver(headerRow) then
                    return headerRow.__savedPlanGroupDropId, headerRow
                end
            end
        end
    end
    return nil, nil
end

local function SetSavedPlanDropHoverFrame(pf, frame)
    if not pf then return end
    local prev = pf.__savedPlanDropHoverFrame
    if prev and prev ~= frame and prev.SetBackdropBorderColor then
        prev:SetBackdropBorderColor(unpack(UI.BORDER))
    end
    pf.__savedPlanDropHoverFrame = frame
    if frame and frame.SetBackdropBorderColor then
        frame:SetBackdropBorderColor(unpack(UI.ACCENT))
    end
end

local function EnsureSavedPlanDropIndicator(pf)
    if not pf then return nil end
    if pf.__savedPlanDropIndicator then return pf.__savedPlanDropIndicator end
    local line = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    line:SetFrameStrata("FULLSCREEN_DIALOG")
    line:SetFrameLevel(705)
    line:SetHeight(3)
    line:EnableMouse(false)
    if SetBackdrop then
        SetBackdrop(line, {0.15, 0.45, 0.95, 0.95}, {0.30, 0.65, 1.0, 1.0}, 1)
    end
    line:Hide()
    pf.__savedPlanDropIndicator = line
    return line
end

local function GetSavedPlanDropAfter(targetFrame)
    if not targetFrame or not targetFrame.__savedPlanEntryId then
        return false
    end
    if type(targetFrame.GetCenter) ~= "function" then
        return false
    end
    local centerY = select(2, targetFrame:GetCenter())
    if not centerY then return false end
    local scale = targetFrame:GetEffectiveScale() or 1
    local _, cursorY = GetCursorPosition()
    cursorY = cursorY / scale
    return cursorY < centerY
end

local function SetSavedPlanDropIndicator(pf, targetFrame)
    if not pf then return end
    local line = EnsureSavedPlanDropIndicator(pf)
    if not line then return end
    if not targetFrame or not targetFrame.IsShown or not targetFrame:IsShown() then
        line:Hide()
        return
    end

    line:ClearAllPoints()
    line:SetParent(UIParent)
    local width = math.max(120, (targetFrame:GetWidth() or 180) - 14)
    line:SetWidth(width)

    if targetFrame.__savedPlanEntryId then
        if GetSavedPlanDropAfter(targetFrame) then
            line:SetPoint("TOP", targetFrame, "BOTTOM", 0, -1)
        else
            line:SetPoint("TOP", targetFrame, "TOP", 0, 1)
        end
    else
        line:SetPoint("TOP", targetFrame, "BOTTOM", 0, -1)
    end
    line:Show()
end

local function EnsureSavedPlanDragGhost(pf)
    if not pf then return nil end
    if pf.__savedPlanDragGhost then return pf.__savedPlanDragGhost end
    local ghost = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    ghost:SetFrameStrata("FULLSCREEN_DIALOG")
    ghost:SetFrameLevel(700)
    ghost:SetSize(180, 24)
    ghost:EnableMouse(false)
    if SetBackdrop then SetBackdrop(ghost, UI.TOOLBAR, UI.ACCENT, 1) end
    local label = ghost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", ghost, "LEFT", 8, 0)
    label:SetPoint("RIGHT", ghost, "RIGHT", -8, 0)
    label:SetJustifyH("LEFT")
    label:SetTextColor(1, 1, 1)
    ghost.label = label
    ghost:Hide()
    ghost.__updateFn = function(self)
        local owner = self.__ownerPf
        if not owner or not owner.__draggingSavedPlanEntryId then
            self:Hide()
            self:SetScript("OnUpdate", nil)
            SetSavedPlanDropHoverFrame(owner, nil)
            if owner and owner.__savedPlanDropIndicator then
                owner.__savedPlanDropIndicator:Hide()
            end
            return
        end
        local scale = UIParent:GetEffectiveScale()
        local x, y = GetCursorPosition()
        x, y = x / scale, y / scale
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x + 14, y - 14)
        local _, targetFrame = ResolveSavedPlanDropTarget(owner)
        SetSavedPlanDropHoverFrame(owner, targetFrame)
        SetSavedPlanDropIndicator(owner, targetFrame)
    end
    pf.__savedPlanDragGhost = ghost
    return ghost
end

local function StartSavedPlanDragGhost(pf, planName)
    local ghost = EnsureSavedPlanDragGhost(pf)
    if not ghost then return end
    local text = strtrim(tostring(planName or "Plan"))
    if text == "" then text = "Plan" end
    if #text > 28 then text = text:sub(1, 28) .. "..." end
    ghost.label:SetText(("Move: %s"):format(text))
    local tw = ghost.label:GetStringWidth() or 120
    ghost:SetWidth(math.max(140, math.min(260, tw + 20)))
    ghost.__ownerPf = pf
    ghost:SetScript("OnUpdate", ghost.__updateFn)
    ghost:Show()
end

local function StopSavedPlanDragGhost(pf)
    if not pf then return end
    local ghost = pf.__savedPlanDragGhost
    if ghost then
        ghost.__ownerPf = nil
        ghost:SetScript("OnUpdate", nil)
        ghost:Hide()
    end
    SetSavedPlanDropHoverFrame(pf, nil)
    if pf.__savedPlanDropIndicator then
        pf.__savedPlanDropIndicator:Hide()
    end
end

local function ResolveSavedPlanDropGroupId(pf)
    local dropGroupId = ResolveSavedPlanDropTarget(pf)
    if dropGroupId ~= nil then return dropGroupId end
    if type(MouseIsOver) == "function" and pf and type(pf.savedPlansGroupRows) == "table" then
        for _, headerRow in ipairs(pf.savedPlansGroupRows) do
            if headerRow and headerRow:IsShown() and MouseIsOver(headerRow) then
                return headerRow.__savedPlanGroupDropId
            end
        end
    end
    return nil
end

function Diar:RefreshSavedPlansList()
    local pf = self.plannerFrame
    if not pf or not pf.savedPlansScrollChild then return end
    pf.savedPlansSelectedIds = pf.savedPlansSelectedIds or {}
    RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {}, nextId = 1 }
    local list = RaidstratsggSavedPlans.list
    if pf.savedPlansDeleteConfirmId then
        local keep = false
        for _, e in ipairs(list or {}) do
            if tonumber(e and e.id) == tonumber(pf.savedPlansDeleteConfirmId) then
                keep = true
                break
            end
        end
        if not keep then
            pf.savedPlansDeleteConfirmId = nil
        end
    end
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

    local store = EnsureSavedPlansStorage()
    local groupsById = {}
    for _, group in ipairs(store.groups or {}) do
        local gid = tonumber(group and group.id)
        local gname = strtrim(tostring(group and group.name or ""))
        if gid and gname ~= "" then
            groupsById[gid] = { id = gid, name = gname, plans = {} }
        end
    end

    local ungrouped = {}
    for _, entry in ipairs(filtered) do
        local gid = tonumber(entry and entry.groupId)
        local grp = gid and groupsById[gid] or nil
        if grp then
            grp.plans[#grp.plans + 1] = entry
        else
            ungrouped[#ungrouped + 1] = entry
        end
    end
    table.sort(ungrouped, ComparePlanEntries)

    local sortedGroups = {}
    for _, grp in pairs(groupsById) do
        if #grp.plans > 0 then
            table.sort(grp.plans, ComparePlanEntries)
            sortedGroups[#sortedGroups + 1] = grp
        end
    end
    table.sort(sortedGroups, function(a, b)
        return strlower(a.name) < strlower(b.name)
    end)

    local collapsedMap = GetSavedPlansGroupCollapseMap()
    local rows = {}
    if #filtered == 0 then
        rows[#rows + 1] = { type = "empty" }
    else
        for _, grp in ipairs(sortedGroups) do
            local isCollapsed = collapsedMap[tostring(grp.id)] == true
            rows[#rows + 1] = {
                type = "group_header",
                groupId = grp.id,
                text = grp.name,
                count = #grp.plans,
                collapsed = isCollapsed,
            }
            if not isCollapsed then
                for _, entry in ipairs(grp.plans) do
                    rows[#rows + 1] = { type = "plan", entry = entry }
                end
            end
        end
        local ungroupedKey = "__ungrouped__"
        local ungroupedCollapsed = collapsedMap[ungroupedKey]
        if ungroupedCollapsed == nil then
            -- Default behavior: keep ungrouped collapsed until user changes it.
            ungroupedCollapsed = true
        else
            ungroupedCollapsed = (ungroupedCollapsed == true)
        end
        rows[#rows + 1] = {
            type = "group_header",
            groupId = ungroupedKey,
            text = "Ungrouped",
            count = #ungrouped,
            collapsed = ungroupedCollapsed,
        }
        if not ungroupedCollapsed then
            for _, entry in ipairs(ungrouped) do
                rows[#rows + 1] = { type = "plan", entry = entry }
            end
        end
    end

    pf.savedPlansHeaders = pf.savedPlansHeaders or {}
    local selectedCount = 0
    for _, enabled in pairs(pf.savedPlansSelectedIds or {}) do
        if enabled then selectedCount = selectedCount + 1 end
    end

    local y = -2
    local headerIndex = 0
    local groupHeaderIndex = 0
    local planIndex = 0
    pf.__savedPlanVisibleEntryIds = {}
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
        elseif row.type == "group_header" then
            groupHeaderIndex = groupHeaderIndex + 1
            local headerRow = AcquireSavedPlanGroupRow(pf, child, groupHeaderIndex, w - 4)
            headerRow:ClearAllPoints()
            headerRow:SetPoint("TOPLEFT", child, "TOPLEFT", 2, y)
            headerRow:SetHeight(GROUP_HEADER_H)
            headerRow:SetWidth(w - 4)
            headerRow.__savedPlanGroupDropId = row.groupId
            local isUngrouped = row.groupId == "__ungrouped__"
            local markerText = row.collapsed and "+" or "-"
            headerRow.marker:SetText(markerText)
            headerRow.marker:SetTextColor(0.72, 0.78, 0.90)
            headerRow.label:SetText(("%s (%d)"):format(row.text or "Group", tonumber(row.count) or 0))
            headerRow.label:SetTextColor(unpack(UI.ACCENT))
            headerRow:SetScript("OnMouseUp", function(_, btn)
                if btn == "RightButton" then
                    if not isUngrouped then
                        Diar:ShowSavedPlanGroupContextMenu(headerRow, row.groupId)
                    end
                    return
                end
                if btn ~= "LeftButton" then return end
                local draggedIds = NormalizeEntryIdList(pf.__draggingSavedPlanEntryIds or {})
                if #draggedIds == 0 then
                    local one = tonumber(pf.__draggingSavedPlanEntryId)
                    if one then draggedIds = { one } end
                end
                if #draggedIds > 0 then
                    for _, draggedEntryId in ipairs(draggedIds) do
                        if row.groupId == "__ungrouped__" then
                            Diar:SetSavedPlanGroup(draggedEntryId, nil)
                        else
                            Diar:SetSavedPlanGroup(draggedEntryId, row.groupId)
                        end
                    end
                    pf.__draggingSavedPlanEntryId = nil
                    pf.__draggingSavedPlanEntryIds = nil
                    StopSavedPlanDragGhost(pf)
                    headerRow.__suppressClickUntil = GetTime() + 0.2
                end
            end)
            headerRow:SetScript("OnClick", function(_, btn)
                if btn ~= "LeftButton" then return end
                if headerRow.__suppressClickUntil and headerRow.__suppressClickUntil > GetTime() then
                    return
                end
                if (not isUngrouped) and IsShiftKeyDown and IsShiftKeyDown() then
                    if Diar.InsertSavedPlanGroupShareTokenIntoActiveChat
                        and Diar:InsertSavedPlanGroupShareTokenIntoActiveChat(row.groupId) then
                        return
                    end
                end
                Diar:ToggleSavedPlansGroupCollapsed(row.groupId)
            end)
            headerRow:Show()
            y = y - GROUP_HEADER_H - 2
        else
            planIndex = planIndex + 1
            local rowFrame = AcquireSavedPlanRow(pf, child, planIndex, w - 4)
            LayoutSavedPlanRow(rowFrame)
            local entry = row.entry
            pf.__savedPlanVisibleEntryIds[#pf.__savedPlanVisibleEntryIds + 1] = entry.id
            local planKey = self.GetPlanIdentityKey and self:GetPlanIdentityKey(entry.data)
            local autoEnabled = planKey and self.IsPlanAutoImportEnabled and self:IsPlanAutoImportEnabled(planKey)
            local isActive = activeId and entry.id == activeId
            local isSelected = pf.savedPlansSelectedIds and pf.savedPlansSelectedIds[entry.id] == true
            local isDeleteConfirm = tonumber(pf.savedPlansDeleteConfirmId) == tonumber(entry.id)
            ApplySavedPlanRowState(rowFrame, entry, isActive, planKey, autoEnabled, isSelected, selectedCount > 1, isDeleteConfirm)
            rowFrame:ClearAllPoints()
            rowFrame:SetPoint("TOPLEFT", child, "TOPLEFT", 2, y)
            rowFrame.__savedPlanGroupDropId = tonumber(entry and entry.groupId) or "__ungrouped__"
            rowFrame.__savedPlanEntryId = tonumber(entry and entry.id)
            rowFrame:SetScript("OnClick", function(_, btn)
                if btn == "RightButton" then return end
                if rowFrame.__blockRowClick then
                    rowFrame.__blockRowClick = nil
                    return
                end
                if rowFrame.syncToggle and rowFrame.syncToggle.__blockRowClick then
                    rowFrame.syncToggle.__blockRowClick = nil
                    return
                end
                if rowFrame.__dragSuppressUntil and rowFrame.__dragSuppressUntil > GetTime() then
                    return
                end
                if IsShiftKeyDown and IsShiftKeyDown() then
                    if Diar.InsertPlanShareTokenIntoActiveChat and Diar:InsertPlanShareTokenIntoActiveChat(entry and entry.data) then
                        return
                    end
                    local ids = pf.__savedPlanVisibleEntryIds or {}
                    local clickedId = tonumber(entry.id)
                    if clickedId then
                        local selected = pf.savedPlansSelectedIds or {}
                        local anchorId = tonumber(pf.savedPlansSelectionAnchorId)
                        if not anchorId then
                            anchorId = tonumber(activeId)
                        end
                        local anchorPos, clickPos = nil, nil
                        for idx, id in ipairs(ids) do
                            local n = tonumber(id)
                            if n == anchorId then anchorPos = idx end
                            if n == clickedId then clickPos = idx end
                        end
                        if anchorPos and clickPos then
                            local fromIdx = math.min(anchorPos, clickPos)
                            local toIdx = math.max(anchorPos, clickPos)
                            for idx = fromIdx, toIdx do
                                local n = tonumber(ids[idx])
                                if n then selected[n] = true end
                            end
                            if anchorId then
                                selected[anchorId] = true
                            end
                        else
                            selected[clickedId] = true
                            if anchorId then
                                selected[anchorId] = true
                            end
                        end
                        pf.savedPlansSelectedIds = selected
                        pf.savedPlansSelectionAnchorId = anchorId or clickedId
                    end
                    Diar:RefreshSavedPlansList()
                    return
                end
                pf.savedPlansSelectedIds = {}
                pf.savedPlansSelectionAnchorId = nil
                Diar:LoadSavedPlan(entry.id)
            end)
            rowFrame:RegisterForDrag("LeftButton")
            rowFrame:SetScript("OnDragStart", function(s)
                local dragIds = nil
                local selectedMap = pf.savedPlansSelectedIds or {}
                local selectedCount = 0
                for _, enabled in pairs(selectedMap) do
                    if enabled then selectedCount = selectedCount + 1 end
                end
                if selectedCount > 1 and selectedMap[entry.id] then
                    dragIds = GetSavedPlanSelectionIds(pf)
                else
                    dragIds = { entry.id }
                end
                s.__draggingPlanEntryId = entry.id
                pf.__draggingSavedPlanEntryId = entry.id
                pf.__draggingSavedPlanEntryIds = dragIds
                StartSavedPlanDragGhost(pf, selectedCount > 1 and (selectedCount .. " plans") or (entry.planName or "Plan"))
            end)
            rowFrame:SetScript("OnDragStop", function(s)
                local dropGroupId, dropFrame = ResolveSavedPlanDropTarget(pf)
                local dropEntryId = tonumber(dropFrame and dropFrame.__savedPlanEntryId)
                local dropAfter = false
                if dropEntryId and dropFrame and type(dropFrame.GetCenter) == "function" then
                    local centerY = select(2, dropFrame:GetCenter())
                    local scale = dropFrame:GetEffectiveScale() or 1
                    local _, cursorY = GetCursorPosition()
                    cursorY = cursorY / scale
                    dropAfter = centerY and cursorY and (cursorY < centerY) or false
                end
                s.__draggingPlanEntryId = nil
                pf.__draggingSavedPlanEntryId = nil
                local dragIds = NormalizeEntryIdList(pf.__draggingSavedPlanEntryIds or { entry.id })
                pf.__draggingSavedPlanEntryIds = nil
                StopSavedPlanDragGhost(pf)
                s.__dragSuppressUntil = GetTime() + 0.15
                if dropGroupId == nil then return end
                if #dragIds == 1 and dropEntryId and self.ReorderSavedPlanEntry then
                    self:ReorderSavedPlanEntry(dragIds[1], dropEntryId, dropGroupId, dropAfter)
                    return
                end
                for _, moveId in ipairs(dragIds) do
                    if dropGroupId == "__ungrouped__" then
                        Diar:SetSavedPlanGroup(moveId, nil)
                    else
                        Diar:SetSavedPlanGroup(moveId, dropGroupId)
                    end
                end
            end)
            rowFrame:SetScript("OnMouseUp", function(_, btn)
                if btn == "RightButton" then
                    local selected = GetSavedPlanSelectionIds(pf)
                    local useIds = {}
                    local includesClicked = false
                    for _, id in ipairs(selected) do
                        useIds[#useIds + 1] = id
                        if id == entry.id then includesClicked = true end
                    end
                    if #useIds == 0 or not includesClicked then
                        useIds = { entry.id }
                        pf.savedPlansSelectedIds = { [entry.id] = true }
                        pf.savedPlansSelectionAnchorId = entry.id
                    end
                    Diar:ShowSavedPlanContextMenu(rowFrame, useIds)
                end
            end)
            rowFrame.delBtn:SetScript("OnClick", function(_, btn)
                if btn == "RightButton" then return end
                pf.savedPlansDeleteConfirmId = entry.id
                Diar:RefreshSavedPlansList()
            end)
            if rowFrame.delCancelBtn then
                rowFrame.delCancelBtn:SetScript("OnClick", function(_, btn)
                    if btn == "RightButton" then return end
                    if tonumber(pf.savedPlansDeleteConfirmId) == tonumber(entry.id) then
                        pf.savedPlansDeleteConfirmId = nil
                        Diar:RefreshSavedPlansList()
                    end
                end)
            end
            if rowFrame.delConfirmBtn then
                rowFrame.delConfirmBtn:SetScript("OnClick", function(_, btn)
                    if btn == "RightButton" then return end
                    pf.savedPlansDeleteConfirmId = nil
                    if entry and entry.id and Diar and Diar.DeleteSavedPlan then
                        Diar:DeleteSavedPlan(entry.id)
                    end
                end)
            end
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
    for gi = groupHeaderIndex + 1, #(pf.savedPlansGroupRows or {}) do
        if pf.savedPlansGroupRows[gi] then pf.savedPlansGroupRows[gi]:Hide() end
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

