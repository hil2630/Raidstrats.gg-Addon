-- Custom roster editor (website-compatible plan.roster).
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

local GROUP_COUNT = 6
local SLOT_COUNT = 5
local MAX_GROUPS = 8
local CLASS_ORDER = {
    "deathknight", "demonhunter", "druid", "evoker", "hunter", "mage", "monk",
    "paladin", "priest", "rogue", "shaman", "warlock", "warrior",
}
local CLASS_LABEL = {
    deathknight = "Death Knight",
    demonhunter = "Demon Hunter",
    druid = "Druid",
    evoker = "Evoker",
    hunter = "Hunter",
    mage = "Mage",
    monk = "Monk",
    paladin = "Paladin",
    priest = "Priest",
    rogue = "Rogue",
    shaman = "Shaman",
    warlock = "Warlock",
    warrior = "Warrior",
}
local CLASS_SET = {}
for i = 1, #CLASS_ORDER do
    CLASS_SET[CLASS_ORDER[i]] = true
end

local function SpecDisplay(specId, specKey)
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
        local pretty = specKey:gsub("%-", " "):gsub("(%a)([%w]*)", function(a, b)
            return a:upper() .. b
        end)
        return L(pretty)
    end
    return L("Spec")
end

local function SpecsForClass(classKey)
    local out = {}
    local map = Diar.SPEC_ID_BY_CLASS and classKey and Diar.SPEC_ID_BY_CLASS[classKey]
    if type(map) ~= "table" then return out end
    local seen = {}
    for specKey, specId in pairs(map) do
        if type(specKey) == "string" and type(specId) == "number" and not specKey:find("%-") and not seen[specId] then
            seen[specId] = true
            out[#out + 1] = {
                key = specKey,
                specId = specId,
                label = SpecDisplay(specId, specKey),
                icon = ("specs/%s/%s"):format(classKey, specKey),
            }
        end
    end
    table.sort(out, function(a, b)
        return tostring(a.label or a.key) < tostring(b.label or b.key)
    end)
    return out
end

local function SpecsWithClassChoice(classKey)
    local items = {}
    if classKey then
        items[1] = {
            key = "",
            classOnly = true,
            label = L(CLASS_LABEL[classKey] or classKey),
            icon = "classes/" .. classKey,
        }
    end
    local specs = SpecsForClass(classKey)
    for i = 1, #specs do
        items[#items + 1] = specs[i]
    end
    return items
end

local function NormClass(value)
    local v = tostring(value or ""):lower():gsub("[%s%-_]", "")
    if CLASS_SET[v] then return v end
    return nil
end

local function NormSpec(classKey, value)
    local spec = tostring(value or ""):lower():gsub("[%s_]", ""):gsub("%-", "")
    if spec == "" then return nil end
    local map = Diar.SPEC_ID_BY_CLASS and classKey and Diar.SPEC_ID_BY_CLASS[classKey]
    if type(map) ~= "table" then return spec end
    if map[spec] then return spec end
    for key in pairs(map) do
        if type(key) == "string" and key:gsub("%-", "") == spec then
            return key:gsub("%-", "")
        end
    end
    return spec
end

local function SaveSpecKey(classKey, specKey)
    if classKey == "hunter" and specKey == "beastmastery" then
        return "beast-mastery"
    end
    return specKey or ""
end

local function NewPlayerId()
    return "p" .. tostring(time and time() or 0) .. "-" .. tostring(math.random(1000, 9999))
end

local function EmptyPlayer()
    return { class = "", spec = "", name = "", id = nil }
end

local function CopyPlayer(src)
    if type(src) ~= "table" then return EmptyPlayer() end
    local classKey = NormClass(src.class) or ""
    local specKey = classKey ~= "" and NormSpec(classKey, src.spec) or nil
    local name = type(src.name) == "string" and src.name or ""
    local id = type(src.id) == "string" and src.id ~= "" and src.id or nil
    if name:match("%S") and not id then
        id = NewPlayerId()
    end
    return {
        class = classKey,
        spec = SaveSpecKey(classKey, specKey),
        name = name,
        id = id,
    }
end

local function NormalizeGroup(groupNum, src)
    local players = {}
    local srcPlayers = type(src) == "table" and src.players or nil
    for i = 1, SLOT_COUNT do
        players[i] = CopyPlayer(srcPlayers and srcPlayers[i])
    end
    if type(srcPlayers) == "table" then
        for i = SLOT_COUNT + 1, #srcPlayers do
            local extra = CopyPlayer(srcPlayers[i])
            if extra.name:match("%S") then
                players[#players + 1] = extra
            end
        end
    end
    return {
        groupNum = groupNum,
        enabled = not (type(src) == "table" and src.enabled == false),
        players = players,
    }
end

function Diar:NormalizePlannerRoster(src)
    local byNum = {}
    if type(src) == "table" and type(src.groups) == "table" then
        for _, group in ipairs(src.groups) do
            if type(group) == "table" then
                local n = tonumber(group.groupNum)
                if not n then n = #byNum + 1 end
                n = math.max(1, math.min(MAX_GROUPS, math.floor(n)))
                byNum[n] = group
            end
        end
    end
    local maxG = GROUP_COUNT
    for n in pairs(byNum) do
        if n > maxG then maxG = n end
    end
    local groups = {}
    for n = 1, maxG do
        groups[n] = NormalizeGroup(n, byNum[n])
    end
    local out = { version = "1.0", groups = groups }
    if type(src) == "table" then
        if type(src.name) == "string" and src.name:match("%S") then
            out.name = src.name
        end
        if type(src.id) == "string" and src.id ~= "" then
            out.id = src.id
        end
    end
    return out
end

local function RosterHasPlayers(roster)
    if type(roster) ~= "table" then return false end
    for _, group in ipairs(roster.groups or {}) do
        for _, player in ipairs(group.players or {}) do
            if type(player.name) == "string" and player.name:match("%S") then
                return true
            end
        end
    end
    return false
end

local function SavedRosterDB()
    RaidstratsggSettings = RaidstratsggSettings or {}
    if type(RaidstratsggSettings.savedRosters) ~= "table" then
        RaidstratsggSettings.savedRosters = {}
    end
    return RaidstratsggSettings.savedRosters
end

local function NewRosterId()
    return "r" .. tostring(time and time() or 0) .. "-" .. tostring(math.random(1000, 9999))
end

function Diar:ListSavedPlannerRosters()
    local out = {}
    for _, entry in ipairs(SavedRosterDB()) do
        if type(entry) == "table" and type(entry.roster) == "table" then
            out[#out + 1] = {
                id = tostring(entry.id or ""),
                name = (type(entry.name) == "string" and entry.name:match("%S") and entry.name) or L("Custom roster"),
                roster = entry.roster,
            }
        end
    end
    table.sort(out, function(a, b)
        return tostring(a.name or ""):lower() < tostring(b.name or ""):lower()
    end)
    return out
end

function Diar:GetSavedPlannerRoster(id)
    if not id or id == "" then return nil end
    for _, entry in ipairs(SavedRosterDB()) do
        if type(entry) == "table" and entry.id == id then
            return entry
        end
    end
    return nil
end

function Diar:UpsertSavedPlannerRoster(name, roster, id)
    name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
    if name == "" then name = L("Custom roster") end
    roster = self:NormalizePlannerRoster(roster)
    roster.name = name
    id = (type(id) == "string" and id ~= "" and id) or roster.id or NewRosterId()
    roster.id = id
    local db = SavedRosterDB()
    for _, entry in ipairs(db) do
        if entry.id == id then
            entry.name = name
            entry.roster = roster
            return id
        end
    end
    db[#db + 1] = { id = id, name = name, roster = roster }
    return id
end

function Diar:DeleteSavedPlannerRoster(id)
    if not id or id == "" then return end
    local db = SavedRosterDB()
    for i, entry in ipairs(db) do
        if entry.id == id then
            table.remove(db, i)
            break
        end
    end
    if self.RefreshPlannerRosterPanel then
        self:RefreshPlannerRosterPanel()
    end
end

function Diar:ApplyImportedPlanRoster(data)
    if type(data) ~= "table" then return end
    local roster = self:NormalizePlannerRoster(data.roster)
    if not RosterHasPlayers(roster) then return end
    local planName = type(data.planName) == "string" and data.planName:match("^%s*(.-)%s*$") or ""
    if planName == "" then planName = L("Plan") end
    local name = planName .. "-roster"
    local id = type(roster.id) == "string" and roster.id ~= "" and roster.id or nil
    if not id and type(data.planId) == "string" and data.planId ~= "" then
        id = "plan-roster:" .. data.planId
    end
    if not id then
        for _, entry in ipairs(self:ListSavedPlannerRosters()) do
            if entry.name == name then
                id = entry.id
                break
            end
        end
    end
    id = self:UpsertSavedPlannerRoster(name, roster, id)
    roster.id = id
    roster.name = name
    data.roster = roster
end

function Diar:ApplySavedPlannerRoster(id)
    local entry = self:GetSavedPlannerRoster(id)
    if not entry then return false end
    local roster = self:NormalizePlannerRoster(entry.roster)
    roster.id = entry.id
    roster.name = entry.name
    self:SetPlannerPlanRoster(roster)
    return true
end

function Diar:PlannerCustomRosterHasPlayers()
    return RosterHasPlayers(self:GetPlannerPlanRoster())
end

function Diar:GetPlannerPlanRoster()
    local data = self.plannerData
    return self:NormalizePlannerRoster(data and data.roster)
end

function Diar:SetPlannerPlanRoster(roster)
    if type(self.plannerData) ~= "table" then return end
    self.plannerData.roster = self:NormalizePlannerRoster(roster)
    if self.PersistCurrentPlanToSaved then
        self:PersistCurrentPlanToSaved()
    end
    if self.RefreshPlannerRosterPanel then
        self:RefreshPlannerRosterPanel()
    end
end

local function PlayerToMember(player, groupNum)
    if type(player) ~= "table" then return nil end
    local name = type(player.name) == "string" and player.name:match("%S") and player.name or nil
    if not name then return nil end
    local classKey = NormClass(player.class)
    local specKey = classKey and NormSpec(classKey, player.spec) or nil
    local specId = classKey and specKey and Diar.SPEC_ID_BY_CLASS and Diar.SPEC_ID_BY_CLASS[classKey] and Diar.SPEC_ID_BY_CLASS[classKey][specKey]
    local icon
    if classKey and specKey then
        icon = ("specs/%s/%s"):format(classKey, specKey)
    elseif classKey then
        icon = "classes/" .. classKey
    end
    return {
        id = type(player.id) == "string" and player.id ~= "" and player.id or nil,
        name = name,
        groupNum = groupNum or 1,
        classKey = classKey,
        classToken = classKey and Diar.CLASS_TOKEN_BY_KEY and Diar.CLASS_TOKEN_BY_KEY[classKey] or nil,
        specId = specId,
        specKey = specKey,
        icon = icon,
        specLabel = SpecDisplay(specId, specKey),
    }
end

function Diar:EnsurePlannerRosterPlayerIds()
    local data = self.plannerData
    if type(data) ~= "table" or type(data.roster) ~= "table" then return end
    local changed
    for _, group in ipairs(data.roster.groups or {}) do
        if type(group.players) == "table" then
            for _, player in ipairs(group.players) do
                if type(player) == "table" and type(player.name) == "string" and player.name:match("%S") then
                    if type(player.id) ~= "string" or player.id == "" then
                        player.id = NewPlayerId()
                        changed = true
                    end
                end
            end
        end
    end
    if changed and self.PersistCurrentPlanToSaved then
        self:PersistCurrentPlanToSaved()
    end
end

function Diar:GetPlannerCustomRosterGroups()
    self:EnsurePlannerRosterPlayerIds()
    local roster = self:GetPlannerPlanRoster()
    local groups = {}
    for _, group in ipairs(roster.groups or {}) do
        if group.enabled ~= false then
            local members = {}
            for slot, player in ipairs(group.players or {}) do
                local member = PlayerToMember(player, group.groupNum)
                if member then
                    member.slotIndex = slot
                    members[#members + 1] = member
                end
            end
            if #members > 0 then
                groups[#groups + 1] = {
                    title = L("Group %d"):format(group.groupNum),
                    groupNum = group.groupNum,
                    members = members,
                }
            end
        end
    end
    return groups
end

local function RosterItemIcon(classKey, specKey)
    if classKey and specKey then
        return ("specs/%s/%s"):format(classKey, specKey)
    end
    if classKey then
        return "classes/" .. classKey
    end
    return nil
end

local function NamesMatch(a, b)
    a = type(a) == "string" and a:match("^%s*(.-)%s*$") or ""
    b = type(b) == "string" and b:match("^%s*(.-)%s*$") or ""
    return a ~= "" and a:lower() == b:lower()
end

local function ItemLooksLikeRosterPerson(item)
    if type(item) ~= "table" then return false end
    if item.isRosterItem or item.rosterPlayerId then return true end
    if item.className or item.specIcon then return true end
    local icon = tostring(item.icon or "")
    return icon:find("classes/", 1, true) or icon:find("specs/", 1, true)
end

function Diar:UpdatePlannerRosterPlayerAcrossPlan(opts)
    opts = type(opts) == "table" and opts or {}
    local newName = type(opts.name) == "string" and opts.name:match("^%s*(.-)%s*$") or ""
    if newName == "" then return false end
    local oldName = type(opts.oldName) == "string" and opts.oldName:match("^%s*(.-)%s*$") or ""
    local classKey = NormClass(opts.class)
    local specKey = classKey and NormSpec(classKey, opts.spec) or nil
    local icon = RosterItemIcon(classKey, specKey)
    local playerId = type(opts.id) == "string" and opts.id ~= "" and opts.id or nil
    local data = self.plannerData
    if type(data) ~= "table" then return false end
    if not opts.skipRosterWrite then
        self:EnsurePlannerRosterPlayerIds()
    end

    if not opts.skipRosterWrite then
        local roster = self:GetPlannerPlanRoster()
        local found
        for _, group in ipairs(roster.groups or {}) do
            for _, player in ipairs(group.players or {}) do
                local hit = (playerId and player.id == playerId)
                    or (not found and oldName ~= "" and NamesMatch(player.name, oldName))
                if hit then
                    if not player.id then
                        player.id = playerId or NewPlayerId()
                    end
                    playerId = player.id
                    player.name = newName
                    player.class = classKey or ""
                    player.spec = SaveSpecKey(classKey, specKey)
                    found = true
                    break
                end
            end
            if found then break end
        end
        if found then
            self.plannerData.roster = roster
            if roster.id then
                self:UpsertSavedPlannerRoster(roster.name, roster, roster.id)
            end
        end
    end

    local function touchPerson(item)
        if not ItemLooksLikeRosterPerson(item) then return false end
        if playerId and item.rosterPlayerId and item.rosterPlayerId ~= playerId then
            return false
        end
        if playerId and item.rosterPlayerId == playerId then
            return true
        end
        return oldName ~= "" and NamesMatch(item.label, oldName)
    end

    for _, scene in ipairs(data.scenes or {}) do
        if type(scene.items) == "table" then
            for _, item in ipairs(scene.items) do
                if touchPerson(item) then
                    item.rosterPlayerId = playerId or item.rosterPlayerId
                    item.label = newName
                    item.className = classKey
                    item.specIcon = specKey
                    if icon then item.icon = icon end
                    item.isRosterItem = true
                end
                if type(item.assignees) == "table" and oldName ~= "" then
                    for _, assignee in ipairs(item.assignees) do
                        if assignee and NamesMatch(assignee.name, oldName) then
                            assignee.name = newName
                            assignee.className = classKey
                            assignee.spec = specKey
                            if icon then assignee.icon = icon end
                        end
                    end
                end
            end
        end
    end

    if not opts.skipPersist and self.PersistCurrentPlanToSaved then
        self:PersistCurrentPlanToSaved()
    end
    if not opts.skipRefresh then
        if self.RefreshPlannerRosterPanel then
            self:RefreshPlannerRosterPanel()
        end
        if self.RefreshPlannerScene then
            self:RefreshPlannerScene()
        end
    end
    return true
end

local function ApplyChoiceIcon(tex, iconKey, specId)
    if not tex then return false end
    tex:SetTexCoord(0, 1, 0, 1)
    if specId and specId > 0 and Diar.GetSpecTextureSafe then
        local specTex = Diar.GetSpecTextureSafe(specId)
        if specTex then
            tex:SetTexture(specTex)
            return true
        end
    end
    if iconKey and Diar.GetPlanIconTexture then
        local path, coord = Diar.GetPlanIconTexture(iconKey)
        if path then
            tex:SetTexture(path)
            if coord and #coord >= 4 then
                tex:SetTexCoord(coord[1], coord[2], coord[3], coord[4])
            end
            return true
        end
    end
    tex:SetTexture(nil)
    return false
end

local function PlaceChoiceLabel(btn, hasIcon)
    if not btn or not btn.label then return end
    btn.label:ClearAllPoints()
    if hasIcon and btn.icon then
        btn.label:SetPoint("LEFT", btn.icon, "RIGHT", 6, 0)
        btn.label:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
        btn.label:SetJustifyH("LEFT")
    else
        btn.label:SetPoint("CENTER")
        btn.label:SetJustifyH("CENTER")
    end
end

local function SetChoiceIcon(btn, iconKey, specId)
    if not btn then return end
    if not btn.icon then
        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetSize(16, 16)
        btn.icon:SetPoint("LEFT", btn, "LEFT", 6, 0)
    end
    local shown = ApplyChoiceIcon(btn.icon, iconKey, specId)
    if shown then
        btn.icon:Show()
    else
        btn.icon:Hide()
    end
    PlaceChoiceLabel(btn, shown)
end

local picker
local function HideRosterPicker()
    if picker then picker:Hide() end
end

local function ShowRosterPicker(anchor, items, onPick)
    HideRosterPicker()
    if type(items) ~= "table" or #items == 0 or not anchor then return end
    if not picker then
        picker = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        picker:SetFrameStrata("TOOLTIP")
        picker:EnableMouse(true)
        picker.buttons = {}
        if SetBackdrop then
            SetBackdrop(picker, {0.08, 0.09, 0.12, 0.98}, {0.22, 0.24, 0.28, 1}, 1)
        end
    end
    picker:SetParent(UIParent)
    picker:SetFrameLevel((anchor:GetFrameLevel() or 100) + 20)
    local w = math.max(140, anchor:GetWidth() or 140)
    local y = -4
    for i, item in ipairs(items) do
        local btn = picker.buttons[i]
        if not btn then
            btn = CreateFrame("Button", nil, picker, "BackdropTemplate")
            btn:SetHeight(22)
            btn.icon = btn:CreateTexture(nil, "ARTWORK")
            btn.icon:SetSize(16, 16)
            btn.icon:SetPoint("LEFT", 6, 0)
            btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn.text:SetPoint("LEFT", btn.icon, "RIGHT", 6, 0)
            btn.text:SetPoint("RIGHT", -8, 0)
            btn.text:SetJustifyH("LEFT")
            if SetBackdrop then
                SetBackdrop(btn, {0.10, 0.11, 0.14, 0.96}, {0.22, 0.24, 0.28, 1}, 1)
            end
            btn:SetScript("OnEnter", function(s)
                s:SetBackdropColor(0.18, 0.38, 0.72, 1)
            end)
            btn:SetScript("OnLeave", function(s)
                s:SetBackdropColor(0.10, 0.11, 0.14, 0.96)
            end)
            picker.buttons[i] = btn
        end
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", picker, "TOPLEFT", 4, y)
        btn:SetWidth(w - 8)
        if ApplyChoiceIcon(btn.icon, item.icon, item.specId) then
            btn.icon:Show()
            btn.text:ClearAllPoints()
            btn.text:SetPoint("LEFT", btn.icon, "RIGHT", 6, 0)
            btn.text:SetPoint("RIGHT", -8, 0)
        else
            btn.icon:Hide()
            btn.text:ClearAllPoints()
            btn.text:SetPoint("LEFT", 8, 0)
            btn.text:SetPoint("RIGHT", -8, 0)
        end
        btn.text:SetText(item.label or item.key or "")
        btn:SetScript("OnClick", function()
            HideRosterPicker()
            if onPick then onPick(item) end
        end)
        btn:Show()
        y = y - 24
    end
    for i = #items + 1, #picker.buttons do
        picker.buttons[i]:Hide()
    end
    picker:ClearAllPoints()
    picker:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    picker:SetSize(w, -y + 4)
    picker:Show()
end

function Diar:HidePlannerRosterPicker()
    HideRosterPicker()
end

function Diar:PickPlannerRosterClassSpec(anchor, classKey, specKey, onDone)
    if not anchor then return end
    local items = {}
    for _, key in ipairs(CLASS_ORDER) do
        items[#items + 1] = {
            key = key,
            label = L(CLASS_LABEL[key]),
            icon = "classes/" .. key,
        }
    end
    ShowRosterPicker(anchor, items, function(item)
        ShowRosterPicker(anchor, SpecsWithClassChoice(item.key), function(spec)
            if onDone then
                onDone(item.key, spec.classOnly and nil or spec.key)
            end
        end)
    end)
end

local function StyleChoice(btn)
    if SetBackdrop then
        SetBackdrop(btn, {0.09, 0.10, 0.13, 0.96}, {0.22, 0.24, 0.28, 1}, 1)
    end
    btn:SetScript("OnEnter", function(s)
        if s:IsEnabled() then
            s:SetBackdropColor(0.14, 0.16, 0.20, 1)
        end
    end)
    btn:SetScript("OnLeave", function(s)
        s:SetBackdropColor(0.09, 0.10, 0.13, 0.96)
    end)
end

local function FlushEditorRows(dialog)
    if not dialog or not dialog.rows or not dialog.draft then return end
    local group = dialog.draft.groups[dialog.groupNum]
    if not group then return end
    for i, row in ipairs(dialog.rows) do
        local player = group.players[i]
        if player and row.nameEdit then
            player.name = row.nameEdit:GetText() or ""
        end
    end
end

local function FillEditorRows(dialog)
    if not dialog or not dialog.rows or not dialog.draft then return end
    local group = dialog.draft.groups[dialog.groupNum]
    local canEdit = dialog.canEdit
    for i, row in ipairs(dialog.rows) do
        local player = group and group.players[i] or EmptyPlayer()
        row.player = player
        local classKey = NormClass(player.class)
        local specKey = classKey and NormSpec(classKey, player.spec) or nil
        local specId = classKey and specKey and Diar.SPEC_ID_BY_CLASS and Diar.SPEC_ID_BY_CLASS[classKey] and Diar.SPEC_ID_BY_CLASS[classKey][specKey]
        row.classBtn.label:SetText(classKey and L(CLASS_LABEL[classKey] or classKey) or L("Class"))
        row.specBtn.label:SetText(specKey and SpecDisplay(specId, specKey) or L("Spec"))
        SetChoiceIcon(row.classBtn, classKey and ("classes/" .. classKey) or nil)
        SetChoiceIcon(row.specBtn, (classKey and specKey) and ("specs/%s/%s"):format(classKey, specKey) or nil, specId)
        row.nameEdit:SetText(player.name or "")
        if canEdit then
            row.classBtn:Enable()
            row.specBtn:Enable()
            row.nameEdit:Enable()
            row.clearBtn:Enable()
            row:SetAlpha(1)
        else
            row.classBtn:Disable()
            row.specBtn:Disable()
            row.nameEdit:Disable()
            row.clearBtn:Disable()
            row:SetAlpha(0.55)
        end
    end
end

local function StyleGroupTab(btn, selected)
    if selected then
        if SetBackdrop then
            SetBackdrop(btn, {0.18, 0.38, 0.72, 1}, {0.22, 0.24, 0.28, 1}, 1)
        end
        btn.label:SetTextColor(1, 1, 1)
    else
        if SetBackdrop then
            SetBackdrop(btn, {0.09, 0.10, 0.13, 0.96}, {0.22, 0.24, 0.28, 1}, 1)
        end
        btn.label:SetTextColor(0.82, 0.84, 0.88)
    end
end

local function RefreshGroupTabs(dialog)
    for i, tab in ipairs(dialog.groupTabs or {}) do
        StyleGroupTab(tab, i == dialog.groupNum)
    end
end

local function RefreshSavedPicker(dialog)
    if not dialog or not dialog.savedBtn then return end
    local label = L("Saved rosters")
    if dialog.draft and type(dialog.draft.name) == "string" and dialog.draft.name:match("%S") then
        label = dialog.draft.name
    elseif dialog.rosterId then
        local saved = Diar:GetSavedPlannerRoster(dialog.rosterId)
        if saved and saved.name then label = saved.name end
    end
    dialog.savedBtn.label:SetText(label)
    if dialog.deleteBtn then
        if dialog.rosterId then
            dialog.deleteBtn:Enable()
            dialog.deleteBtn:SetAlpha(1)
        else
            dialog.deleteBtn:Disable()
            dialog.deleteBtn:SetAlpha(0.4)
        end
    end
end

local function SnapshotRosterNames(dialog)
    if not dialog then return end
    dialog.nameById = {}
    dialog.nameBySlot = {}
    if not dialog.draft then return end
    for gi, group in ipairs(dialog.draft.groups or {}) do
        for si, player in ipairs(group.players or {}) do
            if type(player.name) == "string" and player.name:match("%S") then
                dialog.nameBySlot[gi .. ":" .. si] = player.name
                if player.id then
                    dialog.nameById[player.id] = player.name
                end
            end
        end
    end
end

local function LoadEditorDraft(dialog, roster, id, name, createMode)
    if not dialog then return end
    dialog.createMode = createMode and true or false
    dialog.rosterId = id
    dialog.draft = Diar:NormalizePlannerRoster(roster)
    dialog.draft.id = id
    dialog.draft.name = name
    dialog.groupNum = 1
    SnapshotRosterNames(dialog)
    if dialog.nameEdit then
        dialog.nameEdit:SetText(name or "")
    end
    RefreshSavedPicker(dialog)
    RefreshGroupTabs(dialog)
    FillEditorRows(dialog)
end

local function PersistEditor(dialog)
    if not dialog or not dialog.draft or not dialog.canEdit then return end
    FlushEditorRows(dialog)
    local name = ""
    if dialog.nameEdit then
        name = (dialog.nameEdit:GetText() or ""):match("^%s*(.-)%s*$") or ""
    end
    if name == "" then
        name = (type(dialog.draft.name) == "string" and dialog.draft.name) or ""
    end
    if dialog.createMode and not RosterHasPlayers(dialog.draft) then
        return
    end
    if name == "" then name = L("Custom roster") end
    dialog.draft.name = name
    local id = Diar:UpsertSavedPlannerRoster(name, dialog.draft, dialog.rosterId)
    dialog.rosterId = id
    dialog.createMode = false
    dialog.draft.id = id
    dialog.draft.name = name
    Diar:SetPlannerPlanRoster(dialog.draft)
    RefreshSavedPicker(dialog)
    local snapshot = dialog.nameById or {}
    local slotSnap = dialog.nameBySlot or {}
    for gi, group in ipairs(dialog.draft.groups or {}) do
        for si, player in ipairs(group.players or {}) do
            if type(player.name) == "string" and player.name:match("%S") then
                local oldName = (player.id and snapshot[player.id]) or slotSnap[gi .. ":" .. si] or player.name
                Diar:UpdatePlannerRosterPlayerAcrossPlan({
                    id = player.id,
                    oldName = oldName,
                    name = player.name,
                    class = player.class,
                    spec = player.spec,
                    skipRosterWrite = true,
                    skipPersist = true,
                    skipRefresh = true,
                })
            end
        end
    end
    SnapshotRosterNames(dialog)
    if Diar.PersistCurrentPlanToSaved then
        Diar:PersistCurrentPlanToSaved()
    end
    if Diar.RefreshPlannerScene then
        Diar:RefreshPlannerScene()
    end
    if Diar.RefreshPlannerRosterPanel then
        Diar:RefreshPlannerRosterPanel()
    end
end

if not StaticPopupDialogs["RAIDSTRATSGG_DELETE_ROSTER"] then
    StaticPopupDialogs["RAIDSTRATSGG_DELETE_ROSTER"] = {
        text = L("Delete roster \"%s\"?"),
        button1 = _G.YES or L("Yes"),
        button2 = _G.CANCEL or L("Cancel"),
        OnAccept = function(self)
            local id = self.data
            if id and Diar.DeleteSavedPlannerRoster then
                Diar:DeleteSavedPlannerRoster(id)
            end
            local dialog = Diar.plannerCustomRosterDialog
            if dialog and dialog.rosterId == id then
                LoadEditorDraft(dialog, nil, nil, "", true)
            end
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
    }
end

function Diar:ShowPlannerCustomRosterEditor(opts)
    if not self.plannerData then return end
    if self.HidePlannerRosterPicker then
        self:HidePlannerRosterPicker()
    end
    opts = type(opts) == "table" and opts or {}
    local canEdit = true
    if self.plannerFrame and (self.plannerFrame.compactMode or self.plannerFrame.nsrtSceneActive) then
        canEdit = false
    end
    if not self.plannerCustomRosterDialog then
        local f = CreateFrame("Frame", "RaidstratsCustomRosterDialog", UIParent, "BackdropTemplate")
        f:SetSize(600, 492)
        f:SetPoint("CENTER", 0, 0)
        f:SetMovable(true)
        f:EnableMouse(true)
        if SetBackdrop then SetBackdrop(f) end
        tinsert(UISpecialFrames, "RaidstratsCustomRosterDialog")
        f:SetScript("OnMouseDown", function(s, button)
            HideRosterPicker()
            if button == "LeftButton" then s:StartMoving() end
        end)
        f:SetScript("OnMouseUp", function(s) s:StopMovingOrSizing() end)
        f:SetScript("OnHide", function(s)
            HideRosterPicker()
            PersistEditor(s)
        end)

        local closeX = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeX:SetPoint("TOPRIGHT", -5, -5)

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.title:SetPoint("TOP", 0, -16)
        f.title:SetTextColor(0.9, 0.9, 0.9)

        f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.hint:SetPoint("TOP", f.title, "BOTTOM", 0, -6)
        f.hint:SetWidth(540)
        f.hint:SetTextColor(0.55, 0.6, 0.65)

        f.savedLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.savedLabel:SetPoint("TOPLEFT", 20, -86)
        f.savedLabel:SetTextColor(0.7, 0.74, 0.78)

        f.deleteBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        f.deleteBtn:SetSize(28, 26)
        f.deleteBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -20, -104)
        f.deleteBtn.label = f.deleteBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.deleteBtn.label:SetPoint("CENTER")
        f.deleteBtn.label:SetText("x")
        StyleChoice(f.deleteBtn)
        f.deleteBtn:SetScript("OnClick", function()
            if not f.rosterId then return end
            local name = (f.draft and f.draft.name) or L("Custom roster")
            StaticPopup_Show("RAIDSTRATSGG_DELETE_ROSTER", name, nil, f.rosterId)
        end)

        f.savedBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        f.savedBtn:SetHeight(26)
        f.savedBtn:SetPoint("TOPLEFT", f.savedLabel, "BOTTOMLEFT", 0, -4)
        f.savedBtn:SetPoint("RIGHT", f.deleteBtn, "LEFT", -8, 0)
        f.savedBtn.label = f.savedBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.savedBtn.label:SetPoint("LEFT", 10, 0)
        f.savedBtn.label:SetPoint("RIGHT", -10, 0)
        f.savedBtn.label:SetJustifyH("LEFT")
        StyleChoice(f.savedBtn)
        f.savedBtn:SetScript("OnClick", function()
            local items = {
                { key = "__new", label = L("New roster"), create = true },
            }
            for _, entry in ipairs(Diar:ListSavedPlannerRosters()) do
                items[#items + 1] = {
                    key = entry.id,
                    label = entry.name,
                    id = entry.id,
                    roster = entry.roster,
                }
            end
            ShowRosterPicker(f.savedBtn, items, function(item)
                if item.create then
                    LoadEditorDraft(f, nil, nil, "", true)
                else
                    LoadEditorDraft(f, item.roster, item.id, item.label, false)
                    if RosterHasPlayers(f.draft) then
                        Diar:SetPlannerPlanRoster(f.draft)
                    end
                end
            end)
        end)

        f.nameLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.nameLabel:SetPoint("TOPLEFT", f.savedBtn, "BOTTOMLEFT", 0, -10)
        f.nameLabel:SetTextColor(0.7, 0.74, 0.78)

        f.nameBox = CreateFrame("Frame", nil, f, "BackdropTemplate")
        f.nameBox:SetPoint("TOPLEFT", f.nameLabel, "BOTTOMLEFT", 0, -4)
        f.nameBox:SetPoint("RIGHT", f, "RIGHT", -20, 0)
        f.nameBox:SetHeight(26)
        if SetBackdrop then
            SetBackdrop(f.nameBox, {0.05, 0.05, 0.07, 1}, {0.2, 0.2, 0.2, 1}, 1)
        end
        f.nameEdit = CreateFrame("EditBox", nil, f.nameBox)
        f.nameEdit:SetAutoFocus(false)
        f.nameEdit:SetFontObject(GameFontHighlightSmall)
        f.nameEdit:SetTextInsets(8, 8, 0, 0)
        f.nameEdit:SetPoint("TOPLEFT", 2, -2)
        f.nameEdit:SetPoint("BOTTOMRIGHT", -2, 2)
        f.nameEdit:SetScript("OnEditFocusGained", function()
            HideRosterPicker()
            f.nameBox:SetBackdropBorderColor(0.30, 0.60, 1.00, 1)
        end)
        f.nameEdit:SetScript("OnEditFocusLost", function()
            f.nameBox:SetBackdropBorderColor(0.20, 0.20, 0.20, 1)
        end)
        f.nameEdit:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
        f.nameEdit:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)

        local tabRow = CreateFrame("Frame", nil, f)
        tabRow:SetPoint("TOPLEFT", f.nameBox, "BOTTOMLEFT", 0, -10)
        tabRow:SetPoint("TOPRIGHT", f.nameBox, "BOTTOMRIGHT", 0, -10)
        tabRow:SetHeight(24)
        f.tabRow = tabRow
        f.groupTabs = {}
        for i = 1, GROUP_COUNT do
            local tab = CreateFrame("Button", nil, tabRow, "BackdropTemplate")
            tab:SetHeight(22)
            tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            tab.label:SetPoint("CENTER")
            tab:SetScript("OnClick", function()
                HideRosterPicker()
                FlushEditorRows(f)
                f.groupNum = i
                RefreshGroupTabs(f)
                FillEditorRows(f)
            end)
            f.groupTabs[i] = tab
        end

        local slotHost = CreateFrame("Frame", nil, f)
        slotHost:SetPoint("TOPLEFT", tabRow, "BOTTOMLEFT", 0, -10)
        slotHost:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 56)
        f.rows = {}
        for i = 1, SLOT_COUNT do
            local row = CreateFrame("Frame", nil, slotHost)
            row:SetHeight(36)
            row:SetPoint("TOPLEFT", slotHost, "TOPLEFT", 0, -((i - 1) * 42))
            row:SetPoint("RIGHT", slotHost, "RIGHT", 0, 0)

            local classBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
            classBtn:SetSize(156, 28)
            classBtn:SetPoint("LEFT", row, "LEFT", 0, 0)
            classBtn.icon = classBtn:CreateTexture(nil, "ARTWORK")
            classBtn.icon:SetSize(16, 16)
            classBtn.icon:SetPoint("LEFT", classBtn, "LEFT", 6, 0)
            classBtn.icon:Hide()
            classBtn.label = classBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            classBtn.label:SetPoint("CENTER")
            StyleChoice(classBtn)
            classBtn:SetScript("OnClick", function()
                if not f.canEdit then return end
                local items = {}
                for _, key in ipairs(CLASS_ORDER) do
                    items[#items + 1] = {
                        key = key,
                        label = L(CLASS_LABEL[key]),
                        icon = "classes/" .. key,
                    }
                end
                ShowRosterPicker(classBtn, items, function(item)
                    local player = row.player
                    if not player then return end
                    player.class = item.key
                    local specs = SpecsForClass(item.key)
                    local keep = NormSpec(item.key, player.spec)
                    local map = Diar.SPEC_ID_BY_CLASS and Diar.SPEC_ID_BY_CLASS[item.key]
                    if not keep or not (map and map[keep]) then
                        player.spec = specs[1] and SaveSpecKey(item.key, specs[1].key) or ""
                    else
                        player.spec = SaveSpecKey(item.key, keep)
                    end
                    FillEditorRows(f)
                end)
            end)

            local specBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
            specBtn:SetSize(148, 28)
            specBtn:SetPoint("LEFT", classBtn, "RIGHT", 8, 0)
            specBtn.icon = specBtn:CreateTexture(nil, "ARTWORK")
            specBtn.icon:SetSize(16, 16)
            specBtn.icon:SetPoint("LEFT", specBtn, "LEFT", 6, 0)
            specBtn.icon:Hide()
            specBtn.label = specBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            specBtn.label:SetPoint("CENTER")
            StyleChoice(specBtn)
            specBtn:SetScript("OnClick", function()
                if not f.canEdit then return end
                local player = row.player
                local classKey = player and NormClass(player.class)
                if not classKey then return end
                ShowRosterPicker(specBtn, SpecsWithClassChoice(classKey), function(item)
                    player.spec = item.classOnly and "" or SaveSpecKey(classKey, item.key)
                    FillEditorRows(f)
                end)
            end)

            local clearBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
            clearBtn:SetSize(28, 28)
            clearBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            clearBtn.label = clearBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            clearBtn.label:SetPoint("CENTER")
            StyleChoice(clearBtn)
            clearBtn:SetScript("OnClick", function()
                if not f.canEdit or not row.player then return end
                row.player.class = ""
                row.player.spec = ""
                row.player.name = ""
                FillEditorRows(f)
            end)

            local nameBox = CreateFrame("Frame", nil, row, "BackdropTemplate")
            nameBox:SetPoint("LEFT", specBtn, "RIGHT", 8, 0)
            nameBox:SetPoint("RIGHT", clearBtn, "LEFT", -8, 0)
            nameBox:SetHeight(28)
            if SetBackdrop then
                SetBackdrop(nameBox, {0.05, 0.05, 0.07, 1}, {0.2, 0.2, 0.2, 1}, 1)
            end
            local eb = CreateFrame("EditBox", nil, nameBox)
            eb:SetAutoFocus(false)
            eb:SetFontObject(GameFontHighlightSmall)
            eb:SetTextInsets(8, 8, 0, 0)
            eb:SetPoint("TOPLEFT", 2, -2)
            eb:SetPoint("BOTTOMRIGHT", -2, 2)
            eb:SetScript("OnEditFocusGained", function()
                HideRosterPicker()
                nameBox:SetBackdropBorderColor(0.30, 0.60, 1.00, 1)
            end)
            eb:SetScript("OnEditFocusLost", function()
                nameBox:SetBackdropBorderColor(0.20, 0.20, 0.20, 1)
                if row.player then
                    row.player.name = eb:GetText() or ""
                end
            end)
            eb:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
            eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
            eb:SetScript("OnTextChanged", function(s)
                if row.player then
                    row.player.name = s:GetText() or ""
                end
            end)

            row.classBtn = classBtn
            row.specBtn = specBtn
            row.clearBtn = clearBtn
            row.nameEdit = eb
            f.rows[i] = row
        end

        local btnRow = CreateFrame("Frame", nil, f)
        btnRow:SetHeight(28)
        btnRow:SetPoint("BOTTOMLEFT", 20, 16)
        btnRow:SetPoint("BOTTOMRIGHT", -20, 16)
        if PUI and PUI.CreatePlannerIconBtn then
            f.saveBtn = PUI.CreatePlannerIconBtn(btnRow, L("Save"), 90, 26)
            f.closeBtn = PUI.CreatePlannerIconBtn(btnRow, L("Close"), 90, 26)
        else
            f.saveBtn = CreateFrame("Button", nil, btnRow, "UIPanelButtonTemplate")
            f.saveBtn:SetSize(90, 26)
            f.closeBtn = CreateFrame("Button", nil, btnRow, "UIPanelButtonTemplate")
            f.closeBtn:SetSize(90, 26)
        end
        f.saveBtn:SetPoint("RIGHT", btnRow, "CENTER", -8, 0)
        f.closeBtn:SetPoint("LEFT", btnRow, "CENTER", 8, 0)
        f.saveBtn:SetScript("OnClick", function()
            PersistEditor(f)
        end)
        f.closeBtn:SetScript("OnClick", function()
            f:Hide()
        end)

        self.plannerCustomRosterDialog = f
    end

    local f = self.plannerCustomRosterDialog
    if f:IsShown() and f.draft and f.canEdit then
        PersistEditor(f)
    end
    self:EnsurePlannerRosterPlayerIds()
    f.canEdit = canEdit
    f.groupNum = 1
    if opts.create then
        f.createMode = true
        f.rosterId = nil
        f.draft = self:NormalizePlannerRoster(nil)
    else
        f.createMode = false
        local saved = opts.id and self:GetSavedPlannerRoster(opts.id)
        if saved then
            f.rosterId = saved.id
            f.draft = self:NormalizePlannerRoster(saved.roster)
            f.draft.id = saved.id
            f.draft.name = saved.name
        else
            f.draft = self:GetPlannerPlanRoster()
            f.rosterId = f.draft.id
        end
    end
    SnapshotRosterNames(f)
    f.title:SetText(opts.create and L("Create roster") or L("Edit roster"))
    f.hint:SetText(L("Pick a saved roster, or save this one by name."))
    if f.savedLabel then
        f.savedLabel:SetText(L("Saved rosters"))
    end
    if f.nameLabel then
        f.nameLabel:SetText(L("Roster name"))
    end
    RefreshSavedPicker(f)
    if f.nameEdit then
        f.nameEdit:SetText(f.draft.name or "")
        if canEdit then
            f.nameEdit:Enable()
        else
            f.nameEdit:Disable()
        end
    end
    for i, tab in ipairs(f.groupTabs) do
        tab:ClearAllPoints()
        local w = (560 - ((GROUP_COUNT - 1) * 6)) / GROUP_COUNT
        tab:SetWidth(w)
        if i == 1 then
            tab:SetPoint("LEFT", tab:GetParent(), "LEFT", 0, 0)
        else
            tab:SetPoint("LEFT", f.groupTabs[i - 1], "RIGHT", 6, 0)
        end
        tab.label:SetText(L("Group %d"):format(i))
    end
    for _, row in ipairs(f.rows) do
        row.clearBtn.label:SetText("x")
    end
    if f.saveBtn.SetText then f.saveBtn:SetText(L("Save")) end
    if f.saveBtn.label then f.saveBtn.label:SetText(L("Save")) end
    if f.closeBtn.SetText then f.closeBtn:SetText(L("Close")) end
    if f.closeBtn.label then f.closeBtn.label:SetText(L("Close")) end
    if canEdit then
        f.saveBtn:Show()
        f.saveBtn:Enable()
    else
        f.saveBtn:Hide()
    end
    RefreshGroupTabs(f)
    FillEditorRows(f)
    if self.PrepareModal then
        self:PrepareModal(f, self.plannerFrame or self.frame)
    end
    f:Show()
    if f.Raise then f:Raise() end
end
