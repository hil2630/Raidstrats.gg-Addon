-- Live raid/party roster on the planner canvas (website-style add to plan).
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
local PUI = Diar.PlannerUI
local UI = (PUI and PUI.UI) or {
    PANEL = {0.06, 0.06, 0.09, 0.96},
    BORDER = {0.22, 0.24, 0.28, 1},
    ROW = {0.09, 0.10, 0.13, 0.92},
    ROW_HOV = {0.14, 0.16, 0.20, 1},
}

local PANEL_W = 248
local ROW_H = 22
local HEADER_H = 20
local TAB_H = 22
local PAD = 6

local CLASS_FILE_TO_KEY = {
    WARRIOR = "warrior", PALADIN = "paladin", HUNTER = "hunter", ROGUE = "rogue",
    PRIEST = "priest", DEATHKNIGHT = "deathknight", SHAMAN = "shaman", MAGE = "mage",
    WARLOCK = "warlock", MONK = "monk", DRUID = "druid", DEMONHUNTER = "demonhunter",
    EVOKER = "evoker",
}

local specCache = {}
local inspectQueue = {}
local inspectBusy = false
local inspectUnit = nil

local function HasLoadedPlan(data)
    if not data then return false end
    if tostring(data.planName or "") == "No plan" then return false end
    if type(data.scenes) ~= "table" or #data.scenes == 0 then return false end
    return true
end

local function RosterChromeAllowed(pf)
    if not pf or not pf.canvas then return false end
    if pf.compactMode or pf.nsrtSceneActive then return false end
    if not HasLoadedPlan(Diar.plannerData) then return false end
    return true
end

local function ShortName(name)
    name = strtrim(tostring(name or ""))
    if name == "" then return nil end
    if Ambiguate then
        name = Ambiguate(name, "short") or name
    else
        name = name:match("^([^%-]+)") or name
    end
    return name
end

local function ClassKeyFromFile(classFile)
    if not classFile then return nil end
    return CLASS_FILE_TO_KEY[tostring(classFile):upper()]
end

local function SpecKeyFromId(classKey, specId)
    local map = Diar.SPEC_ID_BY_CLASS and classKey and Diar.SPEC_ID_BY_CLASS[classKey]
    if not map or not specId or specId <= 0 then return nil end
    local best
    for key, id in pairs(map) do
        if id == specId and type(key) == "string" and not key:find("%-") then
            if not best or #key < #best then
                best = key
            end
        end
    end
    return best
end

local function FirstSpecForClass(classKey)
    local map = Diar.SPEC_ID_BY_CLASS and classKey and Diar.SPEC_ID_BY_CLASS[classKey]
    if not map then return nil, nil end
    local bestKey, bestId
    for key, id in pairs(map) do
        if type(key) == "string" and type(id) == "number" and not key:find("%-") then
            if not bestKey or key < bestKey then
                bestKey, bestId = key, id
            end
        end
    end
    return bestKey, bestId
end

local function SpecIdForUnit(unit)
    if not unit or not UnitExists(unit) then return nil end
    if UnitIsUnit(unit, "player") then
        local idx = GetSpecialization and GetSpecialization()
        if idx and GetSpecializationInfo then
            local id = GetSpecializationInfo(idx)
            if id and id > 0 then return id end
        end
    end
    local guid = UnitGUID(unit)
    if guid and specCache[guid] then return specCache[guid] end
    if GetInspectSpecialization then
        local id = GetInspectSpecialization(unit)
        if id and id > 0 then
            if guid then specCache[guid] = id end
            return id
        end
    end
    return nil
end

local function SpecDisplayName(specId, specKey)
    if specId and specId > 0 then
        if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfoForSpecID then
            local _, name = C_SpecializationInfo.GetSpecializationInfoForSpecID(specId)
            if name and name ~= "" then return name end
        end
        if GetSpecializationInfoByID then
            local _, name = GetSpecializationInfoByID(specId)
            if name and name ~= "" then return name end
        end
    end
    if specKey and specKey ~= "" then
        return specKey:sub(1, 1):upper() .. specKey:sub(2)
    end
    return nil
end

local function ClassColor(classKey, classToken)
    local soak = Diar.PLANNER_SOAK_CLASS_COLORS and classKey and Diar.PLANNER_SOAK_CLASS_COLORS[classKey]
    if soak then return soak[1], soak[2], soak[3] end
    local rc = RAID_CLASS_COLORS and classToken and RAID_CLASS_COLORS[classToken]
    if rc then return rc.r, rc.g, rc.b end
    return 0.85, 0.85, 0.85
end

local function MemberFromUnit(unit, groupNum)
    if not unit or not UnitExists(unit) then return nil end
    local name = ShortName(UnitName(unit))
    if not name then return nil end
    local _, classFile = UnitClass(unit)
    local classKey = ClassKeyFromFile(classFile)
    local specId = SpecIdForUnit(unit)
    local specKey = SpecKeyFromId(classKey, specId)
    local icon
    if classKey and specKey then
        icon = ("specs/%s/%s"):format(classKey, specKey)
    elseif classKey then
        icon = "classes/" .. classKey
    end
    return {
        name = name,
        unit = unit,
        groupNum = groupNum or 1,
        classKey = classKey,
        classToken = classFile and classFile:upper() or nil,
        specId = specId,
        specKey = specKey,
        icon = icon,
        specLabel = SpecDisplayName(specId, specKey),
    }
end

local function SortMembers(members)
    table.sort(members, function(a, b)
        return tostring(a.name or ""):lower() < tostring(b.name or ""):lower()
    end)
end

local function GroupsFromMap(byGroup)
    local out = {}
    for g = 1, 8 do
        local members = byGroup[g]
        if members and #members > 0 then
            SortMembers(members)
            out[#out + 1] = { groupNum = g, members = members }
        end
    end
    return out
end

function Diar:GetPlannerLiveRosterGroups()
    if self.IsRsggDebug and self:IsRsggDebug() and self.GetDebugRosterEntries then
        local entries = self:GetDebugRosterEntries() or {}
        local byGroup = {}
        for i, entry in ipairs(entries) do
            local g = math.floor((i - 1) / 5) + 1
            local classKey = entry.icon and tostring(entry.icon):match("classes/([^/]+)")
            local specKey, specId = FirstSpecForClass(classKey)
            local icon = entry.icon
            if classKey and specKey then
                icon = ("specs/%s/%s"):format(classKey, specKey)
            end
            byGroup[g] = byGroup[g] or {}
            byGroup[g][#byGroup[g] + 1] = {
                name = ShortName(entry.name) or entry.name,
                groupNum = g,
                classKey = classKey,
                classToken = classKey and Diar.CLASS_TOKEN_BY_KEY and Diar.CLASS_TOKEN_BY_KEY[classKey] or nil,
                specId = specId,
                specKey = specKey,
                icon = icon,
                specLabel = SpecDisplayName(specId, specKey),
            }
        end
        return GroupsFromMap(byGroup)
    end

    local byGroup = {}
    local seen = {}
    local function addMember(member)
        if not member or not member.name then return end
        local key = member.name:lower()
        if seen[key] then return end
        seen[key] = true
        local g = member.groupNum or 1
        byGroup[g] = byGroup[g] or {}
        byGroup[g][#byGroup[g] + 1] = member
    end

    local num = GetNumGroupMembers and GetNumGroupMembers() or 0
    if num > 0 and IsInRaid and IsInRaid() then
        for i = 1, num do
            local _, _, subgroup = GetRaidRosterInfo(i)
            addMember(MemberFromUnit("raid" .. i, subgroup or 1))
        end
    elseif num > 0 then
        addMember(MemberFromUnit("player", 1))
        for i = 1, num - 1 do
            addMember(MemberFromUnit("party" .. i, 1))
        end
    else
        addMember(MemberFromUnit("player", 1))
    end
    return GroupsFromMap(byGroup)
end

local function ApplyMemberIcon(tex, member)
    if not tex then return end
    tex:SetTexCoord(0, 1, 0, 1)
    if member and member.specId and Diar.GetSpecTextureSafe then
        local specTex = Diar.GetSpecTextureSafe(member.specId)
        if specTex then
            tex:SetTexture(specTex)
            return
        end
    end
    if member and member.icon and Diar.GetPlanIconTexture then
        local path, coord = Diar.GetPlanIconTexture(member.icon)
        if path then
            tex:SetTexture(path)
            if coord and #coord >= 4 then
                tex:SetTexCoord(coord[1], coord[2], coord[3], coord[4])
            end
            return
        end
    end
    tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
end

local function RosterTemplate(member)
    if not member then return nil end
    return {
        kind = "icon",
        icon = member.icon or "classes/warrior",
        label = member.name,
        className = member.classKey,
        specIcon = member.specKey,
        rosterPlayerId = member.id,
        isRosterItem = true,
        w = Diar.OBJECT_PALETTE_ICON_W_PCT or 3.2,
    }
end

local function SelectPlaced(indices)
    local pf = Diar.plannerFrame
    if not pf then return end
    pf.__selectedItemSet = {}
    for i = 1, #indices do
        pf.__selectedItemSet[indices[i]] = true
    end
    if Diar.SyncPlannerSelectionOverlay then
        Diar:SyncPlannerSelectionOverlay()
    end
end

local function PlaceRosterMembers(members)
    if type(members) ~= "table" or #members == 0 then return false end
    if Diar.IsPlannerCanvasLocked and Diar:IsPlannerCanvasLocked() then
        if Diar.Print then
            Diar:Print(L("Objects locked"))
        end
        return false
    end
    local pf = Diar.plannerFrame
    local n = #members
    local placed = {}
    local cx, cy = 50, 50
    local rx, ry = 0, 0
    if n > 1 and pf and pf.canvas then
        local cw, ch = pf.canvas:GetSize()
        if cw and cw > 0 and ch and ch > 0 then
            local radiusPx = 60 + (n * 5)
            rx = (radiusPx / cw) * 100
            ry = (radiusPx / ch) * 100
        else
            rx, ry = 7 + n * 0.7, 7 + n * 0.7
        end
    end
    for i, member in ipairs(members) do
        local template = RosterTemplate(member)
        if template then
            local x, y = cx, cy
            if n > 1 then
                local angle = -math.pi / 2 + ((i - 1) * (2 * math.pi / n))
                x = math.max(4, math.min(96, cx + rx * math.cos(angle)))
                y = math.max(4, math.min(96, cy + ry * math.sin(angle)))
            end
            local ok, newIndex = Diar:AddPlannerItemToScene(template, x, y, {
                skipPersist = true,
                skipRefresh = true,
            })
            if ok and newIndex then
                placed[#placed + 1] = newIndex
            end
        end
    end
    if #placed == 0 then return false end
    if Diar.PersistCurrentPlanToSaved then
        Diar:PersistCurrentPlanToSaved()
    end
    SelectPlaced(placed)
    if Diar.RefreshPlannerScene then
        Diar:RefreshPlannerScene()
    else
        SelectPlaced(placed)
    end
    return true
end

local function HideRosterPanel(pf)
    pf = pf or Diar.plannerFrame
    if Diar.HidePlannerRosterPicker then
        Diar:HidePlannerRosterPicker()
    end
    if pf then
        pf.__rosterPanelOpen = false
        if pf.rosterPanel then pf.rosterPanel:Hide() end
    end
end

local function PumpInspect()
    if inspectBusy then return end
    local pf = Diar.plannerFrame
    if not pf or not pf.__rosterPanelOpen then
        inspectQueue = {}
        return
    end
    local unit
    while #inspectQueue > 0 do
        unit = table.remove(inspectQueue, 1)
        if unit and UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local guid = UnitGUID(unit)
            if not (guid and specCache[guid]) then
                break
            end
        end
        unit = nil
    end
    if not unit then return end
    if not CanInspect or not CanInspect(unit) then
        if C_Timer and C_Timer.After then
            C_Timer.After(0.15, PumpInspect)
        end
        return
    end
    inspectBusy = true
    inspectUnit = unit
    NotifyInspect(unit)
    if C_Timer and C_Timer.After then
        C_Timer.After(1.8, function()
            inspectBusy = false
            inspectUnit = nil
            PumpInspect()
        end)
    end
end

local function QueueMissingInspects(groups)
    inspectQueue = {}
    if InCombatLockdown and InCombatLockdown() then return end
    for _, group in ipairs(groups or {}) do
        for _, member in ipairs(group.members or {}) do
            if member.unit and not member.specId and not UnitIsUnit(member.unit, "player") then
                inspectQueue[#inspectQueue + 1] = member.unit
            end
        end
    end
    PumpInspect()
end

local function EnsureRosterRows(panel)
    panel.headers = panel.headers or {}
    panel.rows = panel.rows or {}
    panel.empty = panel.empty or panel.content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.empty:SetPoint("TOPLEFT", panel.content, "TOPLEFT", PAD, -PAD)
    panel.empty:SetPoint("RIGHT", panel.content, "RIGHT", -PAD, 0)
    panel.empty:SetJustifyH("LEFT")
    panel.empty:Hide()
end

local function StyleRow(btn, isHeader)
    if SetBackdrop then
        if isHeader then
            SetBackdrop(btn, {0.12, 0.16, 0.24, 0.96}, UI.BORDER, 1)
        else
            SetBackdrop(btn, UI.ROW, UI.BORDER, 1)
        end
    end
    btn:SetScript("OnEnter", function(s)
        if s:IsEnabled() then
            s:SetBackdropColor(unpack(UI.ROW_HOV))
        end
        if GameTooltip and s.tip then
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:SetText(s.tip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(s)
        if s.isHeader then
            s:SetBackdropColor(0.12, 0.16, 0.24, 0.96)
        else
            s:SetBackdropColor(unpack(UI.ROW))
        end
        if GameTooltip then GameTooltip:Hide() end
    end)
end

local function AcquireHeader(panel, i)
    local row = panel.headers[i]
    if row then return row end
    row = CreateFrame("Button", nil, panel.content, "BackdropTemplate")
    row:SetHeight(HEADER_H)
    row.isHeader = true
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.text:SetJustifyH("LEFT")
    StyleRow(row, true)
    panel.headers[i] = row
    return row
end

local function SetRowEditMode(row, editing)
    if not row then return end
    row.editing = editing and true or false
    if row.nameEdit then
        if row.editing then
            row.nameEdit:Show()
            if row.nameBg then row.nameBg:Show() end
            if row.text then row.text:Hide() end
        else
            row.nameEdit:ClearFocus()
            row.nameEdit:Hide()
            if row.nameBg then row.nameBg:Hide() end
            if row.text then row.text:Show() end
        end
    end
end

local function ApplyCustomMember(row)
    local member = row and row.member
    if row then row.pickingClass = false end
    if not member or not Diar.UpdatePlannerRosterPlayerAcrossPlan then
        SetRowEditMode(row, false)
        return
    end
    local name = row.nameEdit and (row.nameEdit:GetText() or "") or member.name
    name = name:match("^%s*(.-)%s*$") or ""
    row.pickingClass = false
    if name == "" then
        if row.nameEdit then row.nameEdit:SetText(member.name or "") end
        SetRowEditMode(row, false)
        return
    end
    if name == member.name and row.classKey == member.classKey and row.specKey == member.specKey then
        SetRowEditMode(row, false)
        return
    end
    SetRowEditMode(row, false)
    Diar:UpdatePlannerRosterPlayerAcrossPlan({
        id = member.id,
        oldName = member.name,
        name = name,
        class = row.classKey or member.classKey,
        spec = row.specKey or member.specKey,
    })
end

local function StartRowEdit(row)
    if not row or not row.member or not row.nameEdit or not row.editable then return end
    local panel = Diar.plannerFrame and Diar.plannerFrame.rosterPanel
    for _, other in ipairs((panel and panel.rows) or {}) do
        if other ~= row and other.editing then
            ApplyCustomMember(other)
        end
    end
    row.nameEdit:SetText(row.member.name or "")
    SetRowEditMode(row, true)
    row.nameEdit:SetFocus()
    row.nameEdit:HighlightText()
end

local function PlaceRowMember(row)
    if row and row.member and not row.editing then
        PlaceRosterMembers({ row.member })
    end
end

local function AcquireMember(panel, i)
    local row = panel.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, panel.content, "BackdropTemplate")
    row:SetHeight(ROW_H)
    row.iconBtn = CreateFrame("Button", nil, row)
    row.iconBtn:SetSize(18, 18)
    row.iconBtn:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.icon = row.iconBtn:CreateTexture(nil, "ARTWORK")
    row.icon:SetAllPoints(row.iconBtn)
    row.editBtn = CreateFrame("Button", nil, row)
    row.editBtn:SetSize(16, 16)
    row.editBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.editBtn.icon = row.editBtn:CreateTexture(nil, "ARTWORK")
    row.editBtn.icon:SetAllPoints(row.editBtn)
    row.editBtn.icon:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
    row.editBtn:Hide()
    row.nameEdit = CreateFrame("EditBox", nil, row)
    row.nameEdit:SetAutoFocus(false)
    row.nameEdit:SetFontObject(GameFontHighlightSmall)
    row.nameEdit:SetMaxLetters(24)
    row.nameEdit:SetTextInsets(3, 3, 0, 0)
    row.nameEdit:SetPoint("LEFT", row.iconBtn, "RIGHT", 4, 0)
    row.nameEdit:SetPoint("RIGHT", row.editBtn, "LEFT", -2, 0)
    row.nameEdit:SetHeight(ROW_H - 4)
    row.nameBg = row:CreateTexture(nil, "BACKGROUND")
    row.nameBg:SetColorTexture(0, 0, 0, 0.35)
    row.nameBg:SetPoint("TOPLEFT", row.nameEdit, "TOPLEFT", -1, 1)
    row.nameBg:SetPoint("BOTTOMRIGHT", row.nameEdit, "BOTTOMRIGHT", 1, -1)
    row.nameBg:Hide()
    row.nameEdit:Hide()
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row.iconBtn, "RIGHT", 4, 0)
    row.text:SetPoint("RIGHT", row.editBtn, "LEFT", -2, 0)
    row.text:SetJustifyH("LEFT")
    row.iconBtn:SetScript("OnEnter", function(s)
        local parent = s:GetParent()
        if GameTooltip and parent and parent.editable then
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:SetText(L("Change class and spec"), 1, 0.82, 0)
            GameTooltip:Show()
        end
    end)
    row.iconBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    row.editBtn:SetScript("OnEnter", function(s)
        s.icon:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
        s.icon:SetVertexColor(1, 0.86, 0.35)
        if GameTooltip then
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:SetText(L("Edit name"), 1, 0.82, 0)
            GameTooltip:Show()
        end
    end)
    row.editBtn:SetScript("OnLeave", function(s)
        s.icon:SetVertexColor(1, 1, 1)
        if GameTooltip then GameTooltip:Hide() end
    end)
    row.iconBtn:SetScript("OnClick", function(s)
        local parent = s:GetParent()
        if not parent or not parent.member then return end
        if parent.editable and Diar.PickPlannerRosterClassSpec then
            parent.pickingClass = true
            Diar:PickPlannerRosterClassSpec(s, parent.classKey, parent.specKey, function(classKey, specKey)
                parent.pickingClass = false
                parent.classKey = classKey
                parent.specKey = specKey
                ApplyCustomMember(parent)
            end)
            return
        end
        PlaceRowMember(parent)
    end)
    row.nameEdit:SetScript("OnEnterPressed", function(s)
        ApplyCustomMember(s:GetParent())
    end)
    row.nameEdit:SetScript("OnEditFocusLost", function(s)
        local parent = s:GetParent()
        if not parent or not parent.editing then return end
        local function finish()
            if parent.editing and not parent.pickingClass then
                ApplyCustomMember(parent)
            end
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0.05, finish)
        else
            finish()
        end
    end)
    row.nameEdit:SetScript("OnEscapePressed", function(s)
        local parent = s:GetParent()
        if parent and parent.member then
            s:SetText(parent.member.name or "")
            parent.classKey = parent.member.classKey
            parent.specKey = parent.member.specKey
        end
        SetRowEditMode(parent, false)
    end)
    row.editBtn:SetScript("OnClick", function(s)
        StartRowEdit(s:GetParent())
    end)
    row:SetScript("OnClick", function(s)
        PlaceRowMember(s)
    end)
    StyleRow(row, false)
    panel.rows[i] = row
    return row
end

local function StyleRosterTab(btn, selected)
    if selected then
        if SetBackdrop then
            SetBackdrop(btn, {0.18, 0.38, 0.72, 1}, UI.BORDER, 1)
        end
        btn.label:SetTextColor(1, 1, 1)
    else
        if SetBackdrop then
            SetBackdrop(btn, UI.ROW, UI.BORDER, 1)
        end
        btn.label:SetTextColor(0.82, 0.84, 0.88)
    end
    btn.selected = selected
end

local function EnsureRosterTabs(panel)
    if panel.tabParty then
        panel.tabParty.label:SetText(L("Current party"))
        panel.tabCustom.label:SetText(L("Custom"))
        return
    end
    local tabs = CreateFrame("Frame", nil, panel)
    tabs:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -4)
    tabs:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -4)
    tabs:SetHeight(TAB_H)
    local party = CreateFrame("Button", nil, tabs, "BackdropTemplate")
    party:SetPoint("TOPLEFT", tabs, "TOPLEFT", 0, 0)
    party:SetPoint("BOTTOMLEFT", tabs, "BOTTOMLEFT", 0, 0)
    party:SetPoint("RIGHT", tabs, "CENTER", -2, 0)
    party.label = party:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    party.label:SetPoint("CENTER")
    party.label:SetText(L("Current party"))
    party:SetScript("OnClick", function()
        local pf = Diar.plannerFrame
        if pf then pf.__rosterMode = "party" end
        if Diar.plannerCustomRosterDialog then
            Diar.plannerCustomRosterDialog:Hide()
        end
        if Diar.HidePlannerRosterPicker then
            Diar:HidePlannerRosterPicker()
        end
        Diar:RefreshPlannerRosterPanel()
    end)
    local custom = CreateFrame("Button", nil, tabs, "BackdropTemplate")
    custom:SetPoint("TOPRIGHT", tabs, "TOPRIGHT", 0, 0)
    custom:SetPoint("BOTTOMRIGHT", tabs, "BOTTOMRIGHT", 0, 0)
    custom:SetPoint("LEFT", tabs, "CENTER", 2, 0)
    custom.label = custom:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    custom.label:SetPoint("CENTER")
    custom.label:SetText(L("Custom"))
    custom:SetScript("OnClick", function()
        local pf = Diar.plannerFrame
        if pf then pf.__rosterMode = "custom" end
        Diar:RefreshPlannerRosterPanel()
    end)
    panel.tabRow = tabs
    panel.tabParty = party
    panel.tabCustom = custom
    if panel.scroll then
        panel.scroll:ClearAllPoints()
        panel.scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -(TAB_H + 8))
        panel.scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, 4)
    end
end

local function EnsureCustomActions(panel)
    if panel.actionRow and panel.createRow and panel.editRow then
        panel.createRow.label:SetText(L("Create roster"))
        panel.editRow.label:SetText(L("Edit roster"))
        return panel.actionRow
    end
    local host = CreateFrame("Frame", nil, panel.content)
    host:SetHeight(HEADER_H)
    local create = CreateFrame("Button", nil, host, "BackdropTemplate")
    create:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    create:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)
    create:SetPoint("RIGHT", host, "CENTER", -2, 0)
    create.label = create:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    create.label:SetPoint("CENTER")
    create.label:SetText(L("Create roster"))
    create:SetScript("OnClick", function()
        if Diar.ShowPlannerCustomRosterEditor then
            Diar:ShowPlannerCustomRosterEditor({ create = true })
        end
    end)
    local edit = CreateFrame("Button", nil, host, "BackdropTemplate")
    edit:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
    edit:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    edit:SetPoint("LEFT", host, "CENTER", 2, 0)
    edit.label = edit:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    edit.label:SetPoint("CENTER")
    edit.label:SetText(L("Edit roster"))
    edit:SetScript("OnClick", function()
        if Diar.ShowPlannerCustomRosterEditor then
            Diar:ShowPlannerCustomRosterEditor()
        end
    end)
    panel.actionRow = host
    panel.createRow = create
    panel.editRow = edit
    return host
end

function Diar:RefreshPlannerRosterPanel()
    local pf = self.plannerFrame
    local panel = pf and pf.rosterPanel
    if not panel or not pf.__rosterPanelOpen then return end
    EnsureRosterTabs(panel)
    EnsureRosterRows(panel)

    local mode = pf.__rosterMode or "party"
    if mode ~= "custom" then mode = "party" end
    StyleRosterTab(panel.tabParty, mode == "party")
    StyleRosterTab(panel.tabCustom, mode == "custom")

    local groups
    if mode == "custom" and self.GetPlannerCustomRosterGroups then
        groups = self:GetPlannerCustomRosterGroups()
    else
        groups = self:GetPlannerLiveRosterGroups()
    end
    local locked = self.IsPlannerCanvasLocked and self:IsPlannerCanvasLocked()
    local y = -PAD
    local headerI, rowI = 0, 0
    local isRaid = IsInRaid and IsInRaid()
    local contentW = PANEL_W - 10

    if mode == "custom" then
        local actions = EnsureCustomActions(panel)
        actions:ClearAllPoints()
        actions:SetPoint("TOPLEFT", panel.content, "TOPLEFT", PAD, y)
        actions:SetWidth(contentW - PAD)
        actions:Show()
        StyleRosterTab(panel.createRow, false)
        StyleRosterTab(panel.editRow, false)
        y = y - HEADER_H - 6
    elseif panel.actionRow then
        panel.actionRow:Hide()
    end
    for _, row in ipairs(panel.savedRows or {}) do
        row:Hide()
    end

    if #groups == 0 then
        if mode == "custom" then
            panel.empty:SetText(L("No custom roster yet."))
            panel.empty:ClearAllPoints()
            panel.empty:SetPoint("TOPLEFT", panel.content, "TOPLEFT", PAD, y)
            panel.empty:SetPoint("RIGHT", panel.content, "RIGHT", -PAD, 0)
            panel.empty:Show()
        else
            panel.empty:SetText(L("Join a party or raid to see your roster."))
            panel.empty:ClearAllPoints()
            panel.empty:SetPoint("TOPLEFT", panel.content, "TOPLEFT", PAD, y)
            panel.empty:SetPoint("RIGHT", panel.content, "RIGHT", -PAD, 0)
            panel.empty:Show()
        end
    else
        panel.empty:Hide()
    end

    for _, group in ipairs(groups) do
        headerI = headerI + 1
        local header = AcquireHeader(panel, headerI)
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", panel.content, "TOPLEFT", PAD, y)
        header:SetWidth(contentW - PAD)
        local title
        if mode == "custom" or isRaid or (self.IsRsggDebug and self:IsRsggDebug() and #groups > 1) then
            title = L("Group %d"):format(group.groupNum)
        else
            title = L("Party")
        end
        header.text:SetText(title)
        header.tip = L("Click to add this group")
        header.members = group.members
        if locked then
            header:Disable()
            header:SetAlpha(0.45)
        else
            header:Enable()
            header:SetAlpha(1)
        end
        header:SetScript("OnClick", function(s)
            PlaceRosterMembers(s.members)
        end)
        header:Show()
        y = y - HEADER_H - 3

        for _, member in ipairs(group.members) do
            rowI = rowI + 1
            local row = AcquireMember(panel, rowI)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", panel.content, "TOPLEFT", PAD + 8, y)
            row:SetWidth(contentW - PAD - 8)
            ApplyMemberIcon(row.icon, member)
            row.member = member
            row.classKey = member.classKey
            row.specKey = member.specKey
            row.editable = (mode == "custom")
            local r, g, b = ClassColor(member.classKey, member.classToken)
            local tip = member.name or ""
            if member.specLabel then
                tip = tip .. " — " .. member.specLabel
            end
            row.tip = tip
            row.text:SetText(member.name or "")
            row.text:SetTextColor(r, g, b)
            if row.nameEdit then
                row.nameEdit:SetTextColor(r, g, b)
            end
            if mode == "custom" and row.editBtn then
                row.editable = not locked
                row.editBtn:Show()
                if locked then
                    row.editBtn:Disable()
                    row.editBtn:SetAlpha(0.4)
                else
                    row.editBtn:Enable()
                    row.editBtn:SetAlpha(1)
                end
                if row.addBtn then row.addBtn:Hide() end
                if row.editing and row.nameEdit then
                    if not row.nameEdit:HasFocus() then
                        row.nameEdit:SetText(member.name or "")
                    end
                    SetRowEditMode(row, true)
                else
                    SetRowEditMode(row, false)
                end
            else
                row.editable = false
                row.editing = false
                if row.editBtn then row.editBtn:Hide() end
                if row.addBtn then row.addBtn:Hide() end
                SetRowEditMode(row, false)
            end
            row:EnableMouse(true)
            if locked then
                row:Disable()
                row:SetAlpha(0.45)
            else
                row:Enable()
                row:SetAlpha(1)
            end
            row:SetScript("OnClick", function(s)
                PlaceRowMember(s)
            end)
            row:Show()
            y = y - ROW_H - 2
        end
        y = y - 4
    end

    for i = headerI + 1, #panel.headers do
        panel.headers[i]:Hide()
    end
    for i = rowI + 1, #panel.rows do
        local leftover = panel.rows[i]
        leftover:Hide()
        leftover.editing = false
        if leftover.nameEdit then leftover.nameEdit:Hide() end
        if leftover.nameBg then leftover.nameBg:Hide() end
        if leftover.editBtn then leftover.editBtn:Hide() end
        if leftover.addBtn then leftover.addBtn:Hide() end
    end

    local contentH = math.max(40, -y + PAD)
    panel.content:SetSize(contentW, contentH)
    local canvasH = (pf.canvas and pf.canvas:GetHeight()) or 400
    local maxH = math.min(300, math.max(140, canvasH - 36))
    local chrome = TAB_H + 14
    panel:SetHeight(math.min(maxH, contentH + chrome))
    if panel.scroll then
        panel.scroll:SetHeight(panel:GetHeight() - chrome)
        panel.scroll:UpdateScrollChildRect()
        panel.scroll:SetVerticalScroll(0)
    end

    if mode == "party" then
        QueueMissingInspects(groups)
    else
        inspectQueue = {}
    end
end

local function EnsureRosterPanel(pf)
    if pf.rosterPanel then
        pf.rosterPanel:SetWidth(PANEL_W)
        EnsureRosterTabs(pf.rosterPanel)
        return pf.rosterPanel
    end
    local panel = CreateFrame("Frame", nil, pf, "BackdropTemplate")
    panel:SetWidth(PANEL_W)
    panel:SetHeight(160)
    if SetBackdrop then
        SetBackdrop(panel, UI.PANEL, UI.BORDER, 1)
    end
    panel:EnableMouse(true)
    panel:Hide()

    local scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -(TAB_H + 8))
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, 4)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local max = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(max, cur - delta * 28)))
    end)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(PANEL_W - 10, 40)
    scroll:SetScrollChild(content)
    panel.scroll = scroll
    panel.content = content
    pf.rosterPanel = panel
    EnsureRosterTabs(panel)
    return panel
end

function Diar:HidePlannerRosterPanel()
    HideRosterPanel(self.plannerFrame)
    self:UpdatePlannerRosterButton()
end

function Diar:TogglePlannerRosterPanel()
    local pf = self.plannerFrame
    if not pf or not RosterChromeAllowed(pf) then return end
    pf.__rosterPanelOpen = not pf.__rosterPanelOpen
    if pf.__rosterPanelOpen then
        local panel = EnsureRosterPanel(pf)
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", pf.rosterBtn, "BOTTOMLEFT", 0, -4)
        panel:SetFrameLevel((pf.canvas:GetFrameLevel() or pf:GetFrameLevel()) + 8)
        panel:Show()
        if panel.Raise then panel:Raise() end
        self:RefreshPlannerRosterPanel()
    else
        HideRosterPanel(pf)
    end
    self:UpdatePlannerRosterButton()
end

function Diar:UpdatePlannerRosterButton(pf)
    pf = pf or self.plannerFrame
    local btn = pf and pf.rosterBtn
    if not btn then return end
    local allow = RosterChromeAllowed(pf)
    local open = pf.__rosterPanelOpen == true
    btn.selected = open
    if open then
        btn:SetBackdropColor(0.18, 0.38, 0.72, 1)
        btn.label:SetTextColor(1, 1, 1)
    else
        btn:SetBackdropColor(unpack(UI.ROW))
        btn.label:SetTextColor(0.92, 0.92, 0.92)
    end
    if allow then
        btn:Show()
        if pf.rosterPanel then
            if open then
                pf.rosterPanel:Show()
            else
                pf.rosterPanel:Hide()
            end
        end
    else
        btn:Hide()
        HideRosterPanel(pf)
    end
end

function Diar:EnsurePlannerRosterButton(pf)
    pf = pf or self.plannerFrame
    if not pf or not pf.canvas then return end
    local btn = pf.rosterBtn
    if not btn and PUI and PUI.CreatePlannerIconBtn then
        btn = PUI.CreatePlannerIconBtn(pf, L("Roster"), 72, 22)
        btn:SetScript("OnClick", function()
            Diar:TogglePlannerRosterPanel()
        end)
        btn:SetScript("OnEnter", function(s)
            s:SetBackdropColor(unpack(UI.ROW_HOV))
            s.label:SetTextColor(1, 1, 1)
            if GameTooltip then
                GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
                GameTooltip:SetText(L("Roster"), 1, 0.82, 0)
                GameTooltip:AddLine(L("Add your current group to the plan."), 0.82, 0.84, 0.88, true)
                GameTooltip:AddLine(L("Or build a custom roster that stays with the plan."), 0.82, 0.84, 0.88, true)
                GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function(s)
            if GameTooltip then GameTooltip:Hide() end
            if s.selected then
                s:SetBackdropColor(0.18, 0.38, 0.72, 1)
                s.label:SetTextColor(1, 1, 1)
            else
                s:SetBackdropColor(unpack(UI.ROW))
                s.label:SetTextColor(0.92, 0.92, 0.92)
            end
        end)
        if PUI.SetPlannerBtnShadowHidden then
            PUI.SetPlannerBtnShadowHidden(btn)
        end
        pf.rosterBtn = btn
    end
    if not btn then return end
    if btn:GetParent() ~= pf then
        btn:SetParent(pf)
    end
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", pf.canvas, "TOPLEFT", 6, -6)
    btn:SetFrameLevel((pf.canvas:GetFrameLevel() or pf:GetFrameLevel()) + 6)
    if pf.rosterPanel then
        pf.rosterPanel:SetFrameLevel((pf.canvas:GetFrameLevel() or pf:GetFrameLevel()) + 8)
        pf.rosterPanel:ClearAllPoints()
        pf.rosterPanel:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -4)
    end
    self:UpdatePlannerRosterButton(pf)
end

local events = CreateFrame("Frame")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
events:RegisterEvent("INSPECT_READY")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "INSPECT_READY" then
        local unit = inspectUnit
        if unit and UnitExists(unit) and UnitGUID(unit) == arg1 then
            local specId = GetInspectSpecialization and GetInspectSpecialization(unit)
            if specId and specId > 0 then
                specCache[arg1] = specId
            end
        end
        inspectBusy = false
        inspectUnit = nil
        if Diar.plannerFrame and Diar.plannerFrame.__rosterPanelOpen then
            Diar:RefreshPlannerRosterPanel()
        end
        PumpInspect()
        return
    end
    if event == "PLAYER_SPECIALIZATION_CHANGED" and arg1 == "player" then
        local guid = UnitGUID("player")
        if guid then specCache[guid] = nil end
    end
    if Diar.plannerFrame and Diar.plannerFrame.__rosterPanelOpen then
        Diar:RefreshPlannerRosterPanel()
    end
end)
