local addonName, NS = ...
local Raidstrats = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceComm-3.0", "AceEvent-3.0", "AceTimer-3.0")

local COMM_PREFIX = "RAIDSTRATS_LINK"
local COMM_PLAN_PREFIX = "RAIDSTRATS_PLAN"
Raidstrats.COMM_PLAN_PREFIX = COMM_PLAN_PREFIX
local PREFIX_BRANDING = "!raidstrats-"
local PREFIX_PLANNER  = "!raidstrats-addon-"
local SHARED_PLAN_TTL = 3600

--Colors
local C_BG      = {0.10, 0.10, 0.12, 0.95}
local C_BORDER  = {0.00, 0.00, 0.00, 1.00}
local C_ACCENT  = {0.23, 0.51, 0.96, 1.00}
local C_HOVER   = {0.10, 0.55, 1.00, 1.00}
local C_INPUT   = {0.05, 0.05, 0.06, 1.00}
local C_DISABLED= {0.30, 0.30, 0.30, 1.00}
local C_RED     = {0.85, 0.20, 0.20, 1.00}

local B64       = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local SPEC_ID_MAP = {
    [250]="BLOOD", [251]="FROST", [252]="UNHOLY",
    [577]="HAVOC", [581]="VENGEANCE",
    [102]="BALANCE", [103]="FERAL", [104]="GUARDIAN", [105]="RESTORATION",
    [1467]="DEVASTATION", [1468]="PRESERVATION", [1473]="AUGMENTATION",
    [253]="BEAST MASTERY", [254]="MARKSMANSHIP", [255]="SURVIVAL",
    [62]="ARCANE", [63]="FIRE", [64]="FROST",
    [268]="BREWMASTER", [270]="MISTWEAVER", [269]="WINDWALKER",
    [65]="HOLY", [66]="PROTECTION", [70]="RETRIBUTION",
    [256]="DISCIPLINE", [257]="HOLY", [258]="SHADOW",
    [259]="ASSASSINATION", [260]="OUTLAW", [261]="SUBTLETY",
    [262]="ELEMENTAL", [263]="ENHANCEMENT", [264]="RESTORATION",
    [265]="AFFLICTION", [266]="DEMONOLOGY", [267]="DESTRUCTION",
    [71]="ARMS", [72]="FURY", [73]="PROTECTION",
}

Raidstrats.inspectQueue = {}
Raidstrats.rosterData = {}
Raidstrats.isScanning = false
Raidstrats.currentUnit = nil
Raidstrats.currentGUID = nil
Raidstrats.currentEntry = nil
Raidstrats.scanTimer = nil
Raidstrats.totalToScan = 0
Raidstrats.includeSpecs = false
Raidstrats.plannerData = nil

local function EncodeBase64(s)
    if not s then return "" end
    local t, r, b, out = {}, 0, 0, ""
    for i=1,#B64 do t[i-1]=string.sub(B64,i,i) end
    for i=1,#s do
        b = bit.bor(bit.lshift(b, 8), string.byte(s, i))
        r = r + 8
        while r >= 6 do out = out .. t[bit.band(bit.rshift(b, r - 6), 0x3F)]; r = r - 6 end
    end
    if r > 0 then out = out .. t[bit.band(bit.lshift(b, 6 - r), 0x3F)] .. (r==2 and "==" or "=") end
    return out
end

local function DecodeBase64(s)
    if not s or s == "" then return nil end
    s = s:gsub("%s+", "")
    local t = {}
    for i = 1, #B64 do t[string.sub(B64, i, i)] = i - 1 end
    local out, acc, bits = {}, 0, 0
    for i = 1, #s do
        local ch = s:sub(i, i)
        if ch == "=" then break end
        local v = t[ch]
        if v == nil then return nil end
        acc = bit.bor(bit.lshift(acc, 6), v)
        bits = bits + 6
        if bits >= 8 then
            bits = bits - 8
            out[#out + 1] = string.char(bit.band(bit.rshift(acc, bits), 0xFF))
        end
    end
    return table.concat(out)
end

local function EncodeJSON(val)
    if C_EncodingUtil and C_EncodingUtil.SerializeJSON then
        local ok, result = pcall(C_EncodingUtil.SerializeJSON, val, { ignoreSerializationErrors = true })
        if ok and type(result) == "string" and result ~= "" then
            return result
        end
    end
    if val == nil then return "null" end
    if type(val) == "boolean" then return val and "true" or "false" end
    if type(val) == "number" then return tostring(val) end
    if type(val) == "string" then
        local escaped = val:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
        return '"' .. escaped .. '"'
    end
    if type(val) == "table" then
        local isArray, n = true, 0
        for k in pairs(val) do
            n = n + 1
            if type(k) ~= "number" or k ~= n then isArray = false break end
        end
        if isArray and n > 0 then
            for i = 1, n do if val[i] == nil then isArray = false break end end
        end
        if isArray then
            local parts = {}
            for i = 1, #val do parts[i] = EncodeJSON(val[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local parts = {}
        for k, v in pairs(val) do
            if type(k) == "string" then
                local ok, vs = pcall(EncodeJSON, v)
                parts[#parts + 1] = EncodeJSON(k) .. ":" .. (ok and vs or "null")
            end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end

local function DecodeJSON(str)
    if not str or str == "" then return nil end
    if C_EncodingUtil and C_EncodingUtil.DeserializeJSON then
        local ok, result = pcall(C_EncodingUtil.DeserializeJSON, str)
        if ok and type(result) == "table" then return result end
    end
    local pos = 1
    local function peek() return str:sub(pos, pos) end
    local function consume(ch)
        if peek() ~= ch then return false end
        pos = pos + 1
        return true
    end
    local function skipWs()
        local _, i = str:find("^%s*", pos)
        pos = i + 1
    end
    local parseValue
    local function parseString()
        if not consume('"') then return nil end
        local out = {}
        while pos <= #str do
            local ch = str:sub(pos, pos)
            if ch == '"' then
                pos = pos + 1
                return table.concat(out)
            end
            if ch == "\\" then
                local esc = str:sub(pos + 1, pos + 1)
                if esc == "n" then out[#out + 1] = "\n"
                elseif esc == "r" then out[#out + 1] = "\r"
                elseif esc == "t" then out[#out + 1] = "\t"
                elseif esc == '"' or esc == "\\" or esc == "/" then out[#out + 1] = esc
                elseif esc == "u" then
                    local hex = str:sub(pos + 2, pos + 5)
                    local code = tonumber(hex, 16)
                    if code then out[#out + 1] = utf8 and utf8.char(code) or string.char(code) end
                    pos = pos + 4
                else out[#out + 1] = esc end
                pos = pos + 2
            else
                out[#out + 1] = ch
                pos = pos + 1
            end
        end
        return nil
    end
    local function parseNumber()
        local start, endPos = str:find("^%-?%d+%.?%d*([eE][%+%-]?%d+)?", pos)
        if not start then return nil end
        local num = str:sub(start, endPos)
        pos = endPos + 1
        return tonumber(num)
    end
    local function parseArray()
        if not consume("[") then return nil end
        skipWs()
        local arr = {}
        if consume("]") then return arr end
        while true do
            skipWs()
            arr[#arr + 1] = parseValue()
            skipWs()
            if consume("]") then return arr end
            if not consume(",") then return nil end
        end
    end
    local function parseObject()
        if not consume("{") then return nil end
        skipWs()
        local obj = {}
        if consume("}") then return obj end
        while true do
            skipWs()
            local key = parseString()
            if not key then return nil end
            skipWs()
            if not consume(":") then return nil end
            skipWs()
            obj[key] = parseValue()
            skipWs()
            if consume("}") then return obj end
            if not consume(",") then return nil end
        end
    end
    function parseValue()
        skipWs()
        local ch = peek()
        if ch == '"' then return parseString() end
        if ch == "{" then return parseObject() end
        if ch == "[" then return parseArray() end
        if ch == "t" and str:sub(pos, pos + 3) == "true" then pos = pos + 4 return true end
        if ch == "f" and str:sub(pos, pos + 4) == "false" then pos = pos + 5 return false end
        if ch == "n" and str:sub(pos, pos + 3) == "null" then pos = pos + 4 return nil end
        return parseNumber()
    end
    local result = parseValue()
    skipWs()
    if pos <= #str then return nil end
    return result
end

local function CopyPlanData(val)
    if type(val) == "table" then
        local out = {}
        for k, v in pairs(val) do out[k] = CopyPlanData(v) end
        return out
    end
    return val
end

local function SceneCount(scenes)
    if type(scenes) ~= "table" then return 0 end
    local n = #scenes
    if n > 0 then return n end
    local c = 0
    for _ in ipairs(scenes) do c = c + 1 end
    return c
end

function Raidstrats:GenerateInstanceKey()
    -- WoW Lua math.random max is below 2^32; use four 16-bit parts.
    return string.format(
        "%04x%04x%04x%04x",
        math.random(0, 0xFFFF),
        math.random(0, 0xFFFF),
        math.random(0, 0xFFFF),
        math.random(0, 0xFFFF)
    )
end

-- Each import gets its own instanceKey unless the payload already has one (team share/push).
function Raidstrats:EnsurePlanInstanceKey(data, forceNew)
    if not data then return nil end
    if not forceNew and type(data.instanceKey) == "string" and data.instanceKey ~= "" then
        return data.instanceKey
    end
    data.instanceKey = self:GenerateInstanceKey()
    return data.instanceKey
end

function Raidstrats:EnsureSavedEntryInstanceKey(entry)
    if not entry or not entry.data then return end
    if type(entry.data.instanceKey) == "string" and entry.data.instanceKey ~= "" then return end
    self:EnsurePlanInstanceKey(entry.data)
    entry.data.savedEntryId = entry.id
end

function Raidstrats:MigrateSavedPlanInstanceKeys()
    RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {}, nextId = 1 }
    for _, entry in ipairs(RaidstratsggSavedPlans.list) do
        self:EnsureSavedEntryInstanceKey(entry)
    end
end

function Raidstrats:PreparePlanDataForShare(data)
    if not data then return nil end
    local copy = CopyPlanData(data)
    if self.SanitizePlanData then self:SanitizePlanData(copy) end
    copy.savedEntryId = nil
    return copy
end

function Raidstrats:FindSavedPlanEntry(data)
    if not data then return nil end
    RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {}, nextId = 1 }
    if data.savedEntryId then
        for _, entry in ipairs(RaidstratsggSavedPlans.list) do
            if entry.id == data.savedEntryId then
                return entry
            end
        end
    end
    if type(data.planName) == "string" and data.planName ~= "" then
        for _, entry in ipairs(RaidstratsggSavedPlans.list) do
            if entry.planName == data.planName then
                return entry
            end
        end
    end
    return nil
end

function Raidstrats:FindSavedPlanEntryByInstanceKey(instanceKey)
    local key = strtrim(tostring(instanceKey or ""))
    if key == "" then return nil end
    RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {}, nextId = 1 }
    for _, entry in ipairs(RaidstratsggSavedPlans.list or {}) do
        local entryKey = entry and entry.data and strtrim(tostring(entry.data.instanceKey or "")) or ""
        if entryKey ~= "" and entryKey == key then
            return entry
        end
    end
    return nil
end

local function NormalizePlanIdentityValue(value)
    local raw = strtrim(tostring(value or ""))
    if raw == "" then return nil end
    local lowered = strlower(raw)

    local view = lowered:match("[?&]view=([^&#]+)")
        or lowered:match("[?&]plan=([^&#]+)")
        or lowered:match("/planner%?view=([^&#]+)")
    if view and strtrim(view) ~= "" then
        return strtrim(view)
    end

    if lowered:find("^https?://") then
        return nil
    end

    return lowered
end

function Raidstrats:GetImportedPlanIdentityToken(data, opts)
    if type(data) ~= "table" then return nil end
    opts = opts or {}
    local includeInstanceKey = opts.includeInstanceKey ~= false
    local candidates = {}
    if includeInstanceKey then
        candidates[#candidates + 1] = data.instanceKey
    end
    candidates[#candidates + 1] = data.uuid
    candidates[#candidates + 1] = data.planUUID
    candidates[#candidates + 1] = data.planUuid
    candidates[#candidates + 1] = data.plan_id
    candidates[#candidates + 1] = data.planId
    candidates[#candidates + 1] = data.planLink
    candidates[#candidates + 1] = data.id
    candidates[#candidates + 1] = data.ref
    candidates[#candidates + 1] = data.planRef
    candidates[#candidates + 1] = data.sourcePlanId
    candidates[#candidates + 1] = data.source_plan_id
    candidates[#candidates + 1] = data.payloadId
    candidates[#candidates + 1] = data.payload_id
    local meta = type(data.meta) == "table" and data.meta or nil
    if meta then
        candidates[#candidates + 1] = meta.uuid
        candidates[#candidates + 1] = meta.planId
        candidates[#candidates + 1] = meta.plan_id
        candidates[#candidates + 1] = meta.planLink
        candidates[#candidates + 1] = meta.ref
    end
    for _, candidate in ipairs(candidates) do
        local token = NormalizePlanIdentityValue(candidate)
        if token then
            return token
        end
    end
    return nil
end

function Raidstrats:FindSavedPlanEntryByImportIdentity(data)
    if type(data) ~= "table" then return nil end
    local byInstance = self:FindSavedPlanEntryByInstanceKey(data.instanceKey)
    if byInstance then return byInstance end

    local incomingToken = self:GetImportedPlanIdentityToken(data, { includeInstanceKey = false })
    if not incomingToken then return nil end

    RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {}, nextId = 1 }
    for _, entry in ipairs(RaidstratsggSavedPlans.list or {}) do
        local entryData = entry and entry.data
        if type(entryData) == "table" then
            local entryToken = self:GetImportedPlanIdentityToken(entryData, { includeInstanceKey = false })
            if entryToken and entryToken == incomingToken then
                return entry
            end
        end
    end
    return nil
end

function Raidstrats:PersistCurrentPlanToSaved()
    local data = self.plannerData
    if not data or type(data.scenes) ~= "table" or #data.scenes == 0 then
        return false
    end
    local entry = self:FindSavedPlanEntry(data)
    if not entry then return false end
    data.savedEntryId = entry.id
    entry.data = CopyPlanData(data)
    entry.data.savedEntryId = entry.id
    if self.SanitizePlanData then self:SanitizePlanData(entry.data) end
    -- Debounced sync-version commit so Version: X updates live after edits settle.
    if self.SchedulePlanSyncVersionCommit then
        self:SchedulePlanSyncVersionCommit()
    elseif self.UpdatePlanSyncVersionLabel then
        self:UpdatePlanSyncVersionLabel(self.plannerFrame)
    end
    return true
end

function Raidstrats:SaveImportedPlan(data)
    if not data then return end
    local importAlreadySanitized = data.__rsggImportedSanitized == true
    local sharedVersion = tonumber(data.__rsggSharedVersion)
    data.__rsggSharedVersion = nil
    self:EnsurePlanInstanceKey(data)
    -- Seed our sync version from the shared payload so the first push applies as a delta.
    if sharedVersion and self.SeedPlanSyncVersionFromImport
        and type(data.instanceKey) == "string" and data.instanceKey ~= "" then
        self:SeedPlanSyncVersionFromImport("inst:" .. data.instanceKey, sharedVersion)
    end
    RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {}, nextId = 1 }
    local function cleanMeta(value)
        if type(value) ~= "string" then return nil end
        local out = strtrim(value)
        if out == "" then return nil end
        return out
    end
    local function canonicalMeta(value)
        local out = cleanMeta(value)
        if not out then return nil end
        if strlower(out) == "other" then return nil end
        return out
    end
    local function inferExpansion(importData)
        local explicit = canonicalMeta(importData and importData.expansion)
        if explicit then return explicit end
        local raid = canonicalMeta(importData and importData.raid)
        local boss = canonicalMeta(importData and importData.boss)
        local byRaid = {
            ["the voidspire"] = "Midnight",
            ["the dreamrift"] = "Midnight",
            ["march on quel'danas"] = "Midnight",
            ["sporefall"] = "Midnight",
            ["the venomous abyss"] = "Midnight",
            ["manaforge omega"] = "The War Within",
            ["liberation of undermine"] = "The War Within",
            ["nerub-ar palace"] = "The War Within",
        }
        if raid then
            local hit = byRaid[strlower(raid)]
            if hit then return hit end
        end
        local byBoss = {
            ["imperator averzian"] = "Midnight",
            ["vorasius"] = "Midnight",
            ["fallen-king salhadaar"] = "Midnight",
            ["vaelgor & ezzorak"] = "Midnight",
            ["lightblinded vanguard"] = "Midnight",
            ["crown of the cosmos"] = "Midnight",
            ["chimaerus the undreamt god"] = "Midnight",
            ["belo'ren, child of al'ar"] = "Midnight",
            ["midnight falls"] = "Midnight",
            ["rotmire"] = "Midnight",
        }
        if boss then
            local hit = byBoss[strlower(boss)]
            if hit then return hit end
        end
        if raid then return raid end
        return "Other"
    end
    data.expansion = inferExpansion(data)
    data.raid = cleanMeta(data.raid) or "Other"
    data.boss = cleanMeta(data.boss) or "Unknown"
    if type(data.instanceKey) == "string" and data.instanceKey ~= "" then
        for _, entry in ipairs(RaidstratsggSavedPlans.list) do
            if entry.data and entry.data.instanceKey == data.instanceKey then
                entry.data = CopyPlanData(data)
                entry.data.__rsggImportedSanitized = nil
                entry.data.savedEntryId = entry.id
                if type(data.planName) == "string" and data.planName ~= "" then
                    entry.planName = data.planName
                end
                entry.expansion = data.expansion or "Other"
                entry.raid = data.raid or "Other"
                entry.boss = data.boss or "Unknown"
                if self.SanitizePlanData and not importAlreadySanitized then
                    self:SanitizePlanData(entry.data)
                end
                data.savedEntryId = entry.id
                data.__rsggImportedSanitized = nil
                self:SetLastLoadedPlanId(entry.id)
                return entry.id
            end
        end
    end
    local entry = {
        id = RaidstratsggSavedPlans.nextId,
        planName = (type(data.planName) == "string" and data.planName ~= "") and data.planName or "Imported plan",
        expansion = data.expansion or "Other",
        raid = data.raid or "Other",
        boss = data.boss or "Unknown",
        data = CopyPlanData(data),
    }
    entry.data.__rsggImportedSanitized = nil
    entry.data.savedEntryId = entry.id
    if self.SanitizePlanData and not importAlreadySanitized then
        self:SanitizePlanData(entry.data)
    end
    RaidstratsggSavedPlans.nextId = RaidstratsggSavedPlans.nextId + 1
    table.insert(RaidstratsggSavedPlans.list, entry)
    data.savedEntryId = entry.id
    data.__rsggImportedSanitized = nil
    self:SetLastLoadedPlanId(entry.id)
    return entry.id
end

function Raidstrats:SetLastLoadedPlanId(entryId)
    if not entryId then return end
    RaidstratsggSettings = RaidstratsggSettings or {}
    RaidstratsggSettings.lastLoadedPlanId = entryId
end

function Raidstrats:ApplySavedPlanEntry(entry)
    if not entry or not entry.data then return false end
    if SceneCount(entry.data.scenes) == 0 then return false end
    self:EnsureSavedEntryInstanceKey(entry)
    self.plannerData = CopyPlanData(entry.data)
    self.plannerData.savedEntryId = entry.id
    if self.SanitizePlanData then self:SanitizePlanData(self.plannerData) end
    self:SetLastLoadedPlanId(entry.id)
    return true
end

function Raidstrats:LoadSavedPlanById(entryId, opts)
    opts = opts or {}
    if not entryId then return false end
    RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {}, nextId = 1 }
    for _, entry in ipairs(RaidstratsggSavedPlans.list) do
        if entry.id == entryId then
            if not self:ApplySavedPlanEntry(entry) then return false end
            if opts.openPlanner and self.ShowPlannerViewer then
                self:ShowPlannerViewer({ reloadOnly = true })
            end
            return true
        end
    end
    return false
end

function Raidstrats:LoadLastSavedPlan()
    RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {}, nextId = 1 }
    local list = RaidstratsggSavedPlans.list
    if not list or #list == 0 then return false end

    RaidstratsggSettings = RaidstratsggSettings or {}
    local lastId = RaidstratsggSettings.lastLoadedPlanId
    if lastId and self:LoadSavedPlanById(lastId) then
        return true
    end

    for i = #list, 1, -1 do
        if self:ApplySavedPlanEntry(list[i]) then
            return true
        end
    end
    return false
end

function Raidstrats:FindSavedPlansGroupByName(groupName)
    local name = strtrim(tostring(groupName or ""))
    if name == "" then return nil end
    RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {}, nextId = 1 }
    local groups = RaidstratsggSavedPlans.groups or {}
    local target = strlower(name)
    for _, grp in ipairs(groups) do
        local gid = tonumber(grp and grp.id)
        local gname = strtrim(tostring(grp and grp.name or ""))
        if gid and gname ~= "" and strlower(gname) == target then
            return gid, gname
        end
    end
    return nil
end

function Raidstrats:CountSavedPlansInGroup(groupId)
    local gid = tonumber(groupId)
    if not gid then return 0 end
    RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {}, nextId = 1 }
    local count = 0
    for _, entry in ipairs(RaidstratsggSavedPlans.list or {}) do
        if tonumber(entry and entry.groupId) == gid then
            count = count + 1
        end
    end
    return count
end

function Raidstrats:ShowGroupImportConflictDialog(groupName, existingCount)
    local normalizedName = strtrim(tostring(groupName or "group-1"))
    if normalizedName == "" then normalizedName = "group-1" end
    local count = tonumber(existingCount) or 0

    if not self.groupImportConflictDialog then
        local f = CreateFrame("Frame", "RaidstratsGroupImportConflictDialog", UIParent, "BackdropTemplate")
        f:SetSize(520, 260)
        f:SetPoint("CENTER", 0, 0)
        f:SetMovable(true)
        f:EnableMouse(true)
        if self.SetBackdrop then
            self.SetBackdrop(f)
        end
        tinsert(UISpecialFrames, "RaidstratsGroupImportConflictDialog")
        f:SetScript("OnMouseDown", function(s, b) if b == "LeftButton" then s:StartMoving() end end)
        f:SetScript("OnMouseUp", function(s) s:StopMovingOrSizing() end)

        local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -5, -5)
        closeBtn:SetScript("OnClick", function()
            if Raidstrats then
                Raidstrats._pendingGroupedImport = nil
                Raidstrats._pendingGroupedImportUiOpts = nil
            end
            f:Hide()
        end)

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -18)
        title:SetText("Group Import Conflict")
        title:SetTextColor(0.9, 0.9, 0.9)

        local body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        body:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -60)
        body:SetPoint("TOPRIGHT", f, "TOPRIGHT", -24, -60)
        body:SetJustifyH("LEFT")
        body:SetJustifyV("TOP")
        body:SetSpacing(4)
        body:SetTextColor(0.75, 0.80, 0.88)
        f.bodyText = body

        local overrideBtn = self.CreateButton and self.CreateButton(f, "OVERRIDE GROUP") or CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        overrideBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 24, 20)
        overrideBtn:SetPoint("RIGHT", f, "CENTER", -8, 0)
        overrideBtn:SetScript("OnClick", function()
            local pending = f.pendingData
            f:Hide()
            if Raidstrats and Raidstrats.FinalizePendingGroupedImport then
                Raidstrats:FinalizePendingGroupedImport("override", pending)
            end
        end)

        local dupBtn = self.CreateButton and self.CreateButton(f, "IMPORT DUPLICATES") or CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        dupBtn:SetPoint("LEFT", f, "CENTER", 8, 0)
        dupBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 20)
        dupBtn:SetScript("OnClick", function()
            local pending = f.pendingData
            f:Hide()
            if Raidstrats and Raidstrats.FinalizePendingGroupedImport then
                Raidstrats:FinalizePendingGroupedImport("duplicates", pending)
            end
        end)

        self.groupImportConflictDialog = f
    end

    local dialog = self.groupImportConflictDialog
    dialog.pendingData = self._pendingGroupedImport
    if dialog.bodyText then
        dialog.bodyText:SetText(
            ("Group \"%s\" already exists with %d plan(s).\n\nChoose how to import:\n- Override: replace existing plans in this group.\n- Import duplicates: keep current plans and add imported plans.")
                :format(normalizedName, count)
        )
    end
    if self.importPlanDialog and self.importPlanDialog:IsShown() then
        self.importPlanDialog:Hide()
    end
    if self.PrepareModal then
        self:PrepareModal(dialog, self.plannerFrame or self.frame)
    end
    dialog:Show()
end

function Raidstrats:ShowPlanImportConflictDialog(existingEntry, incomingData)
    local existingName = strtrim(tostring(existingEntry and existingEntry.planName or "Existing plan"))
    if existingName == "" then existingName = "Existing plan" end
    local incomingName = strtrim(tostring(incomingData and incomingData.planName or "Imported plan"))
    if incomingName == "" then incomingName = "Imported plan" end

    if not self.planImportConflictDialog then
        local f = CreateFrame("Frame", "RaidstratsPlanImportConflictDialog", UIParent, "BackdropTemplate")
        f:SetSize(520, 250)
        f:SetPoint("CENTER", 0, 0)
        f:SetMovable(true)
        f:EnableMouse(true)
        if self.SetBackdrop then
            self.SetBackdrop(f)
        end
        tinsert(UISpecialFrames, "RaidstratsPlanImportConflictDialog")
        f:SetScript("OnMouseDown", function(s, b) if b == "LeftButton" then s:StartMoving() end end)
        f:SetScript("OnMouseUp", function(s) s:StopMovingOrSizing() end)

        local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -5, -5)
        closeBtn:SetScript("OnClick", function()
            if Raidstrats then
                Raidstrats._pendingSingleImport = nil
                Raidstrats._pendingSingleImportUiOpts = nil
            end
            f:Hide()
        end)

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -18)
        title:SetText("Plan UUID Conflict")
        title:SetTextColor(0.9, 0.9, 0.9)

        local body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        body:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -60)
        body:SetPoint("TOPRIGHT", f, "TOPRIGHT", -24, -60)
        body:SetJustifyH("LEFT")
        body:SetJustifyV("TOP")
        body:SetSpacing(4)
        body:SetTextColor(0.75, 0.80, 0.88)
        f.bodyText = body

        local overrideBtn = self.CreateButton and self.CreateButton(f, "OVERRIDE") or CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        overrideBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 24, 20)
        overrideBtn:SetPoint("RIGHT", f, "CENTER", -8, 0)
        overrideBtn:SetScript("OnClick", function()
            local pending = f.pendingData
            f:Hide()
            if Raidstrats and Raidstrats.FinalizePendingSingleImport then
                Raidstrats:FinalizePendingSingleImport("override", pending)
            end
        end)

        local skipBtn = self.CreateButton and self.CreateButton(f, "SKIP IMPORT") or CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        skipBtn:SetPoint("LEFT", f, "CENTER", 8, 0)
        skipBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 20)
        skipBtn:SetScript("OnClick", function()
            local pending = f.pendingData
            f:Hide()
            if Raidstrats and Raidstrats.FinalizePendingSingleImport then
                Raidstrats:FinalizePendingSingleImport("skip", pending)
            end
        end)

        self.planImportConflictDialog = f
    end

    local dialog = self.planImportConflictDialog
    dialog.pendingData = self._pendingSingleImport
    if dialog.bodyText then
        dialog.bodyText:SetText(
            ("A plan with this UUID already exists.\n\nExisting: \"%s\"\nIncoming: \"%s\"\n\nChoose:\n- Override: replace the existing plan.\n- Skip import: keep the current saved plan.")
                :format(existingName, incomingName)
        )
    end
    if self.importPlanDialog and self.importPlanDialog:IsShown() then
        self.importPlanDialog:Hide()
    end
    if self.PrepareModal then
        self:PrepareModal(dialog, self.plannerFrame or self.frame)
    end
    dialog:Show()
end

function Raidstrats:FinalizePendingSingleImport(mode, pendingData)
    local pending = pendingData or self._pendingSingleImport
    self._pendingSingleImport = nil
    if type(pending) ~= "table" then return false end

    if mode ~= "override" then
        self._pendingSingleImportUiOpts = nil
        print("|cffffff66[Raidstrats.gg]|r Import skipped (existing UUID kept).")
        return true
    end

    local data = pending.data
    if type(data) ~= "table" or SceneCount(data.scenes) == 0 then
        self._pendingSingleImportUiOpts = nil
        return false
    end

    self.plannerData = data
    self:SaveImportedPlan(data)

    local uiOpts = self._pendingSingleImportUiOpts
    self._pendingSingleImportUiOpts = nil
    if type(uiOpts) == "table" then
        local mainWasOpen = self.frame and self.frame:IsShown()
        local plannerWasOpen = self.plannerFrame and self.plannerFrame:IsShown()
        if uiOpts.clearPlanInput and self.planInputBox then
            self.planInputBox:SetText("")
        end
        if uiOpts.closeMainOnSuccess and self.frame then
            self.frame:Hide()
            mainWasOpen = false
        end
        if (uiOpts.openPlanner or plannerWasOpen) and self.ShowPlannerViewer then
            if plannerWasOpen then
                self:ShowPlannerViewer({ reloadOnly = true })
            else
                self:ShowPlannerViewer()
            end
        end
        if mainWasOpen and self.frame then
            self.frame:Show()
        end
        if self.LayoutOpenWindows and (mainWasOpen or (uiOpts.openPlanner and not plannerWasOpen)) then
            self:LayoutOpenWindows()
        end
        if uiOpts.closeImportDialog and self.importPlanDialog then
            self.importPlanDialog:Hide()
        end
    else
        if self.ShowPlannerViewer then
            self:ShowPlannerViewer({ reloadOnly = self.plannerFrame and self.plannerFrame:IsShown() })
        end
        if self.LayoutOpenWindows then
            self:LayoutOpenWindows()
        end
    end

    print("|cff00aaff[Raidstrats.gg]|r Plan imported.")
    return true
end

function Raidstrats:FinalizePendingGroupedImport(mode, pendingData)
    local pending = pendingData or self._pendingGroupedImport
    self._pendingGroupedImport = nil
    if type(pending) ~= "table" then return false end

    local payload = pending.payload
    local groupName = pending.groupName
    if type(payload) ~= "table" or type(payload.plans) ~= "table" or #payload.plans == 0 then
        return false
    end
    if type(groupName) ~= "string" or strtrim(groupName) == "" then
        groupName = "group-1"
    end
    groupName = strtrim(groupName)

    local importedEntryIds = {}
    local importedCount = 0
    local skippedExistingCount = 0
    local failedCount = 0
    local seenIncomingIdentity = {}
    local lastImportedData = nil
    local overrideExisting = (mode == "override-existing")

    for _, planEntry in ipairs(payload.plans) do
        local candidate = nil
        if type(planEntry) == "table" then
            if type(planEntry.payload) == "table" then
                candidate = planEntry.payload
            elseif type(planEntry.data) == "table" then
                candidate = planEntry.data
            else
                candidate = planEntry
            end
        end

        local data = self:NormalizeDecodedPlanPayload(candidate)
        if data then
            local importedName = type(planEntry) == "table" and planEntry.planName or nil
            if type(importedName) == "string" and strtrim(importedName) ~= "" then
                data.planName = strtrim(importedName)
            end
            -- Always check UUID/plan identity on any import, including group imports.
            if type(data.instanceKey) ~= "string" or data.instanceKey == "" then
                local token = self:GetImportedPlanIdentityToken(data)
                if token then
                    data.instanceKey = "plan:" .. token
                end
            end
            self:EnsurePlanInstanceKey(data)

            local incomingIdentity = self:GetImportedPlanIdentityToken(data, { includeInstanceKey = false })
            if not incomingIdentity then
                incomingIdentity = "inst:" .. tostring(data.instanceKey or "")
            end
            if incomingIdentity and seenIncomingIdentity[incomingIdentity] then
                skippedExistingCount = skippedExistingCount + 1
            else
                if incomingIdentity then seenIncomingIdentity[incomingIdentity] = true end
                local existing = self:FindSavedPlanEntryByImportIdentity(data)
                if existing then
                    if overrideExisting then
                        local existingKey = existing and existing.data and tostring(existing.data.instanceKey or "") or ""
                        if existingKey ~= "" then
                            data.instanceKey = existingKey
                        end
                        local savedEntryId = self:SaveImportedPlan(data)
                        if savedEntryId then
                            importedEntryIds[#importedEntryIds + 1] = savedEntryId
                            importedCount = importedCount + 1
                            lastImportedData = data
                        else
                            failedCount = failedCount + 1
                        end
                    else
                        skippedExistingCount = skippedExistingCount + 1
                    end
                else
                    local savedEntryId = self:SaveImportedPlan(data)
                    if savedEntryId then
                        importedEntryIds[#importedEntryIds + 1] = savedEntryId
                        importedCount = importedCount + 1
                        lastImportedData = data
                    else
                        failedCount = failedCount + 1
                    end
                end
            end
        else
            failedCount = failedCount + 1
        end
    end

    if #importedEntryIds > 0 and self.EnsureSavedPlansGroupByName and self.SetSavedPlanGroup then
        local groupId = self:EnsureSavedPlansGroupByName(groupName)
        if groupId then
            for _, entryId in ipairs(importedEntryIds) do
                self:SetSavedPlanGroup(entryId, groupId)
            end
        end
    end

    if self.RefreshSavedPlansList then
        self:RefreshSavedPlansList()
    end
    if lastImportedData then
        self.plannerData = lastImportedData
    end
    if self.ShowPlannerViewer and self.plannerFrame and self.plannerFrame:IsShown() then
        self:ShowPlannerViewer({ reloadOnly = true })
    end
    if importedCount > 0 then
        print(("|cff00aaff[Raidstrats.gg]|r Imported %d plan(s) to group \"%s\"."):format(
            importedCount,
            groupName
        ))
    else
        print(("|cffffff66[Raidstrats.gg]|r No new plans imported for group \"%s\"."):format(groupName))
    end
    if skippedExistingCount > 0 then
        print(("|cffffff66[Raidstrats.gg]|r Skipped %d plan(s) already saved (same UUID/plan identity)."):format(skippedExistingCount))
    end
    if failedCount > 0 then
        print(("|cffff6666[Raidstrats.gg]|r %d plan(s) could not be imported."):format(failedCount))
    end

    local uiOpts = self._pendingGroupedImportUiOpts
    self._pendingGroupedImportUiOpts = nil
    if type(uiOpts) == "table" then
        if uiOpts.clearPlanInput and self.planInputBox then
            self.planInputBox:SetText("")
        end
        local mainWasOpen = self.frame and self.frame:IsShown()
        local plannerWasOpen = self.plannerFrame and self.plannerFrame:IsShown()
        if uiOpts.closeMainOnSuccess and self.frame then
            self.frame:Hide()
            mainWasOpen = false
        end
        if (uiOpts.openPlanner or plannerWasOpen) and self.ShowPlannerViewer then
            if plannerWasOpen then
                self:ShowPlannerViewer({ reloadOnly = true })
            else
                self:ShowPlannerViewer()
            end
        end
        if mainWasOpen and self.frame then
            self.frame:Show()
        end
        if self.LayoutOpenWindows and (mainWasOpen or (uiOpts.openPlanner and not plannerWasOpen)) then
            self:LayoutOpenWindows()
        end
        if uiOpts.closeImportDialog and self.importPlanDialog then
            self.importPlanDialog:Hide()
        end
        if importedCount > 0 then
            print("|cff00aaff[Raidstrats.gg]|r Plan imported.")
        end
    end
    return importedCount > 0 or skippedExistingCount > 0
end

function Raidstrats:ImportPlanFromPasteString(raw)
    return self:ImportPlanFromPasteStringWithOpts(raw, nil)
end

function Raidstrats:ImportPlanFromPasteStringWithOpts(raw, opts)
    opts = opts or {}
    local payload = self:DecodeAddonImportPayload(raw)
    if not payload then return false end

    if type(payload.plans) == "table" and #payload.plans > 0 then
        local groupName = (type(payload.groupName) == "string" and strtrim(payload.groupName) ~= "")
            and strtrim(payload.groupName)
            or "group-1"
        local mode = (opts._existingMode == "override") and "override-existing" or ((opts._existingMode == "skip") and "skip-existing" or nil)
        if not mode then
            local seenIncomingIdentity = {}
            local existingCount = 0
            for _, planEntry in ipairs(payload.plans) do
                local candidate = nil
                if type(planEntry) == "table" then
                    if type(planEntry.payload) == "table" then
                        candidate = planEntry.payload
                    elseif type(planEntry.data) == "table" then
                        candidate = planEntry.data
                    else
                        candidate = planEntry
                    end
                end
                local data = self:NormalizeDecodedPlanPayload(candidate)
                if data then
                    local importedName = type(planEntry) == "table" and planEntry.planName or nil
                    if type(importedName) == "string" and strtrim(importedName) ~= "" then
                        data.planName = strtrim(importedName)
                    end
                    if type(data.instanceKey) ~= "string" or data.instanceKey == "" then
                        local token = self:GetImportedPlanIdentityToken(data)
                        if token then
                            data.instanceKey = "plan:" .. token
                        end
                    end
                    self:EnsurePlanInstanceKey(data)
                    local incomingIdentity = self:GetImportedPlanIdentityToken(data, { includeInstanceKey = false })
                    if not incomingIdentity then
                        incomingIdentity = "inst:" .. tostring(data.instanceKey or "")
                    end
                    if incomingIdentity and not seenIncomingIdentity[incomingIdentity] then
                        seenIncomingIdentity[incomingIdentity] = true
                        if self:FindSavedPlanEntryByImportIdentity(data) then
                            existingCount = existingCount + 1
                        end
                    end
                end
            end
            if existingCount > 0 then
                self:ShowExistingImportConflictDialog(raw, opts, existingCount, #payload.plans)
                return "pending"
            end
            mode = "skip-existing"
        end
        return self:FinalizePendingGroupedImport(mode, {
            payload = payload,
            groupName = groupName,
            existingGroupId = nil,
            existingCount = 0,
        })
    end

    local data = self:NormalizeDecodedPlanPayload(payload)
    if not data then return false end
    -- If the payload carries a stable website identity (planId/uuid/link), promote
    -- it to instanceKey so repeated website exports map to the same saved plan.
    if type(data.instanceKey) ~= "string" or data.instanceKey == "" then
        local token = self:GetImportedPlanIdentityToken(data)
        if token then
            data.instanceKey = "plan:" .. token
        end
    end
    -- Website / fresh paste: new key when no stable identity exists.
    self:EnsurePlanInstanceKey(data)
    local existingEntry = self:FindSavedPlanEntryByImportIdentity(data)
    if existingEntry then
        self._pendingSingleImport = {
            data = CopyPlanData(data),
            existingEntryId = existingEntry.id,
            existingPlanName = existingEntry.planName,
        }
        self:ShowPlanImportConflictDialog(existingEntry, data)
        return "pending"
    end
    self.plannerData = data
    self:SaveImportedPlan(data)
    return true
end

local function CoerceNumber(v)
    local n = tonumber(v)
    if not n then return nil end
    return n
end

local function CoerceBool(v)
    if v == true or v == 1 then return true end
    if type(v) == "string" then
        local lowered = strlower(strtrim(v))
        return lowered == "true" or lowered == "1"
    end
    return false
end

local function ValueToPercent(v, dim)
    local n = tonumber(v)
    if not n then return nil end
    if n >= 0 and n <= 100 then return n end
    if dim and dim > 0 then
        return (n / dim) * 100
    end
    return n
end

local function ResolveObjectBBoxPercent(obj, canvasW, canvasH)
    local pct = type(obj.__percentData) == "table" and obj.__percentData or nil
    local x = CoerceNumber(pct and pct.__bboxXPct)
    local y = CoerceNumber(pct and pct.__bboxYPct)
    local w = CoerceNumber(pct and pct.__bboxWPct)
    local h = CoerceNumber(pct and pct.__bboxHPct)
    if x and y and w and h then
        return x, y, w, h
    end

    local left = ValueToPercent((pct and pct.left) or obj.left, canvasW)
    local top = ValueToPercent((pct and pct.top) or obj.top, canvasH)
    local scaleX = CoerceNumber(obj.scaleX) or 1
    local scaleY = CoerceNumber(obj.scaleY) or 1
    local rawW = CoerceNumber(obj.width)
    local rawH = CoerceNumber(obj.height)
    local widthPct = ValueToPercent(rawW and (rawW * scaleX) or nil, canvasW)
    local heightPct = ValueToPercent(rawH and (rawH * scaleY) or nil, canvasH)
    if not left or not top or not widthPct or not heightPct then
        return nil, nil, nil, nil
    end

    local originX = strlower(tostring((pct and pct.originX) or obj.originX or "left"))
    local originY = strlower(tostring((pct and pct.originY) or obj.originY or "top"))
    local xPct = left
    local yPct = top
    if originX == "center" then xPct = xPct - widthPct * 0.5
    elseif originX == "right" then xPct = xPct - widthPct end
    if originY == "center" then yPct = yPct - heightPct * 0.5
    elseif originY == "bottom" then yPct = yPct - heightPct end
    return xPct, yPct, widthPct, heightPct
end

local function ResolveObjectBBoxPercentRaw(obj, canvasW, canvasH)
    local pct = type(obj.__percentData) == "table" and obj.__percentData or nil
    local left = ValueToPercent((pct and pct.left) or obj.left, canvasW)
    local top = ValueToPercent((pct and pct.top) or obj.top, canvasH)
    local scaleX = CoerceNumber(obj.scaleX) or 1
    local scaleY = CoerceNumber(obj.scaleY) or 1
    local rawW = CoerceNumber(obj.width)
    local rawH = CoerceNumber(obj.height)
    local widthPct = ValueToPercent(rawW and (rawW * scaleX) or nil, canvasW)
    local heightPct = ValueToPercent(rawH and (rawH * scaleY) or nil, canvasH)
    if not left or not top or not widthPct or not heightPct then
        return nil, nil, nil, nil
    end

    local originX = strlower(tostring((pct and pct.originX) or obj.originX or "left"))
    local originY = strlower(tostring((pct and pct.originY) or obj.originY or "top"))
    local xPct = left
    local yPct = top
    if originX == "center" then xPct = xPct - widthPct * 0.5
    elseif originX == "right" then xPct = xPct - widthPct end
    if originY == "center" then yPct = yPct - heightPct * 0.5
    elseif originY == "bottom" then yPct = yPct - heightPct end
    return xPct, yPct, widthPct, heightPct
end

local function ResolveIconKeyFromSrc(src)
    if type(src) ~= "string" or src == "" then return nil end
    local clean = strlower(src:gsub("\\", "/"))
    local marker = clean:find("/icon/", 1, true)
    if not marker then
        marker = clean:find("icon/", 1, true)
        if not marker then return nil end
    end
    local key = clean:sub(marker + 6):gsub("^/+", ""):gsub("%.[^%.]+$", "")
    return (key ~= "" and key) or nil
end

local function ResolveSpellIdFromWebObject(obj)
    if type(obj) ~= "table" then return nil end
    local abilityData = type(obj.abilityData) == "table" and obj.abilityData or nil
    if NS and type(NS.ResolveCustomSpellIdFromSrc) == "function" then
        local mapped = NS.ResolveCustomSpellIdFromSrc(obj.src)
            or NS.ResolveCustomSpellIdFromSrc(abilityData and abilityData.icon or nil)
        local mappedNum = tonumber(mapped)
        if mappedNum and mappedNum > 0 then
            return math.floor(mappedNum + 0.0001)
        end
    end
    local candidates = {
        obj.spellId,
        obj.spellID,
        obj.spell_id,
        abilityData and abilityData.spellId,
        abilityData and abilityData.spellID,
        abilityData and abilityData.spell_id,
        abilityData and abilityData.id,
    }
    for i = 1, #candidates do
        local id = tonumber(candidates[i])
        if id and id > 0 then
            return math.floor(id + 0.0001)
        end
    end
    local iconKey = ResolveIconKeyFromSrc(obj.src)
        or ResolveIconKeyFromSrc(abilityData and abilityData.icon or nil)
    if type(iconKey) == "string" and iconKey ~= "" then
        local file = iconKey:match("([^/]+)$") or iconKey
        local fromPrefix = tonumber(file:match("^(%d+)[_%-]"))
            or tonumber(file:match("^(%d+)$"))
            or tonumber(iconKey:match("/(%d+)[_%-]"))
        if fromPrefix and fromPrefix > 0 then
            return math.floor(fromPrefix + 0.0001)
        end
    end
    return nil
end

local function RegisterSceneItemId(map, id, index)
    if not map or not id then return end
    map[tostring(id)] = index
end

local function ReadWebObjectSlotIndex(obj)
    if type(obj) ~= "table" then return nil end
    local idx = CoerceNumber(obj.embedIndex)
    if idx and idx > 0 then
        return math.floor(idx + 0.0001)
    end
    local key = type(obj.indexKey) == "string" and obj.indexKey or nil
    if key then
        local m = key:match("^%s*index(%d+)%s*$")
        if m then
            local parsed = tonumber(m)
            if parsed and parsed > 0 then
                return math.floor(parsed + 0.0001)
            end
        end
    end
    return nil
end

local function ConvertWebSceneObjects(scene, canvasW, canvasH)
    if type(scene) ~= "table" then
        return nil, nil, nil
    end
    local objects = nil
    if type(scene.__objectsTable) == "table" then
        objects = scene.__objectsTable
    elseif type(scene.objectsJSON) == "string" and scene.objectsJSON ~= "" then
        local parsed = DecodeJSON(scene.objectsJSON)
        if type(parsed) == "table" then
            objects = parsed.objects or parsed.canvasObjects or parsed
        end
    end
    if type(objects) ~= "table" then return nil, nil, nil end

    local items = {}
    local idToIndex = {}
    local pathByAnimId = {}
    local objectById = {}

    -- Some web exports also emit a group's inner circle/text children (and a
    -- separate "bottom" label) as top-level objects positioned at left/top 0,0.
    -- Those would otherwise render as stray text stacked in the corner, so we
    -- collect the ids that live inside groups and skip the duplicates/labels.
    local groupChildIds = {}
    for _, obj in ipairs(objects) do
        if type(obj) == "table" and strlower(tostring(obj.type or "")) == "group" and type(obj.objects) == "table" then
            for _, child in ipairs(obj.objects) do
                if type(child) == "table" then
                    if child.id then groupChildIds[tostring(child.id)] = true end
                    if child.__objectGroupId then groupChildIds[tostring(child.__objectGroupId)] = true end
                end
            end
        end
    end

    local function IsRedundantLabelText(obj)
        local objType = strlower(tostring(obj.type or ""))
        if objType ~= "text" and objType ~= "i-text" and objType ~= "textbox" then return false end
        -- Explicit attached labels are already drawn under their parent circle.
        if CoerceBool(obj["data-is-label"]) then return true end
        local parentId = obj["data-parent-id"]
        if parentId ~= nil and tostring(parentId) ~= "" then return true end
        -- Duplicates of a circle group's inner text child.
        local id = obj.id and tostring(obj.id) or nil
        local gid = obj.__objectGroupId and tostring(obj.__objectGroupId) or nil
        if (id and groupChildIds[id]) or (gid and groupChildIds[gid]) then return true end
        return false
    end

    for _, obj in ipairs(objects) do
        if type(obj) == "table" then
            if CoerceBool(obj.__isAnimationPath) then
                local animId = obj.__animationId or obj.id or obj.__objectGroupId
                if animId then pathByAnimId[tostring(animId)] = obj end
            elseif IsRedundantLabelText(obj) then
                -- Skip stray duplicate/label text emitted alongside grouped circles.
            else
                local x, y, w, h = ResolveObjectBBoxPercent(obj, canvasW, canvasH)
                if x and y and w and h then
                    local item = nil
                    local objType = strlower(tostring(obj.type or ""))
                    if objType == "image" then
                        local spellId = ResolveSpellIdFromWebObject(obj)
                        local iconKey = ResolveIconKeyFromSrc(obj.src)
                            or ResolveIconKeyFromSrc(type(obj.abilityData) == "table" and obj.abilityData.icon or nil)
                        item = {
                            kind = "icon",
                            x = x,
                            y = y,
                            w = w,
                            h = h,
                            icon = iconKey,
                            spellId = spellId,
                            label = (type(obj.name) == "string" and obj.name ~= "") and obj.name or "",
                        }
                    elseif objType == "textbox" or objType == "text" or objType == "i-text" then
                        local slotIndex = ReadWebObjectSlotIndex(obj)
                        if slotIndex then
                            -- Use raw width/height + object scale for spot circles.
                            -- Some exports carry stale __bbox* values that ignore scale.
                            local sx, sy, sw, sh = ResolveObjectBBoxPercentRaw(obj, canvasW, canvasH)
                            if sx and sy and sw and sh then
                                x, y, w, h = sx, sy, sw, sh
                            end
                            -- Indexed text entries are player spots in some exports:
                            -- import as player circles (assignable/movable) with label below.
                            item = {
                                kind = "icon",
                                x = x,
                                y = y,
                                w = w,
                                h = h,
                                icon = "markers/circle",
                                playerCircle = true,
                                label = strtrim(tostring(obj.text or obj.name or "")),
                                slotIndex = slotIndex,
                                fill = obj.fill,
                                opacity = CoerceNumber(obj.opacity),
                                stroke = obj.stroke,
                                strokeWidth = ValueToPercent(CoerceNumber(obj.strokeWidth), canvasH),
                            }
                        else
                            item = {
                                kind = "text",
                                x = x,
                                y = y,
                                w = w,
                                h = h,
                                label = tostring(obj.text or obj.name or ""),
                                textColor = obj.fill,
                            }
                            local fs = CoerceNumber(obj.fontSize)
                            if fs then item.fontSize = ValueToPercent(fs * (CoerceNumber(obj.scaleY) or 1), canvasH) end
                            local rawAlign = strlower(tostring(obj.textAlign or ""))
                            if rawAlign == "center" or rawAlign == "right" then item.textAlign = rawAlign end
                            local textBg = obj.backgroundColor or obj.textBackgroundColor
                            if type(textBg) == "string" and textBg ~= "" then item.textBg = textBg end
                        end
                    elseif objType == "group" and type(obj.objects) == "table" and #obj.objects > 0 then
                        -- Web plans can store actor circles as grouped { circle + text } objects.
                        -- Import them as player-circle icons so they stay assignable/movable
                        -- and render like icon-circle mode with labels below.
                        local circleChild = nil
                        local textChild = nil
                        for _, child in ipairs(obj.objects) do
                            local childType = strlower(tostring(child and child.type or ""))
                            if (childType == "circle" or childType == "ellipse") and not circleChild then
                                circleChild = child
                            elseif (childType == "text" or childType == "i-text" or childType == "textbox") and not textChild then
                                textChild = child
                            end
                        end

                        if circleChild then
                            -- Use raw width/height + object scale for grouped player circles.
                            -- Some scene exports carry stale __bbox* values on group wrappers.
                            local sx, sy, sw, sh = ResolveObjectBBoxPercentRaw(obj, canvasW, canvasH)
                            if sx and sy and sw and sh then
                                x, y, w, h = sx, sy, sw, sh
                            end
                            -- Prefer the actual circle child geometry for size, multiplied by
                            -- both child + group scales. Wrapper group bbox can be polluted by
                            -- text bounds and stale export snapshots on later scenes.
                            local childScaleX = CoerceNumber(circleChild.scaleX) or 1
                            local childScaleY = CoerceNumber(circleChild.scaleY) or 1
                            local groupScaleX = CoerceNumber(obj.scaleX) or 1
                            local groupScaleY = CoerceNumber(obj.scaleY) or 1
                            local childRawW = CoerceNumber(circleChild.width)
                            local childRawH = CoerceNumber(circleChild.height)
                            local circleW = ValueToPercent(
                                childRawW and (childRawW * childScaleX * groupScaleX) or nil,
                                canvasW
                            )
                            local circleH = ValueToPercent(
                                childRawH and (childRawH * childScaleY * groupScaleY) or nil,
                                canvasH
                            )
                            if circleW and circleH and circleW > 0 and circleH > 0 then
                                w, h = circleW, circleH
                            end
                            item = {
                                kind = "icon",
                                x = x,
                                y = y,
                                w = w,
                                h = h,
                                icon = "markers/circle",
                                playerCircle = true,
                                fill = circleChild.fill or obj.fill,
                                opacity = CoerceNumber(circleChild.opacity or obj.opacity),
                                stroke = circleChild.stroke or obj.stroke,
                                strokeWidth = ValueToPercent(CoerceNumber(circleChild.strokeWidth or obj.strokeWidth), canvasH),
                                label = strtrim(tostring((textChild and textChild.text) or obj.name or "")),
                            }
                            local slotIndex = ReadWebObjectSlotIndex(obj)
                                or (textChild and ReadWebObjectSlotIndex(textChild))
                                or (circleChild and ReadWebObjectSlotIndex(circleChild))
                            if slotIndex then item.slotIndex = slotIndex end
                        end
                    elseif objType == "rect" or objType == "triangle" or objType == "circle" or objType == "ellipse" then
                        item = {
                            kind = "shape",
                            shape = (objType == "rect" and "rect") or (objType == "triangle" and "triangle") or objType,
                            x = x,
                            y = y,
                            w = w,
                            h = h,
                            fill = obj.fill,
                            opacity = CoerceNumber(obj.opacity),
                            stroke = obj.stroke,
                            strokeWidth = ValueToPercent(CoerceNumber(obj.strokeWidth), canvasH),
                        }
                    end

                    if item then
                        local idx = #items + 1
                        local itemId = obj.id or obj.__objectGroupId
                        if itemId then item.id = tostring(itemId) end
                        if CoerceBool(obj.__isFrontalBeam) then
                            item.isFrontalBeam = true
                            if obj.__frontalParentId then item.frontalParentId = tostring(obj.__frontalParentId) end
                            local cfg = type(obj.__frontalConfig) == "table" and obj.__frontalConfig or nil
                            if cfg and cfg.shapeType == "cone" then item.shape = "triangle" end
                            item.startAngle = CoerceNumber((cfg and cfg.startAngle) or obj.angle) or 0
                            item.endAngle = CoerceNumber((cfg and cfg.endAngle) or item.startAngle) or item.startAngle
                            item.frontalAnimationType = strlower(tostring((cfg and cfg.animation and cfg.animation.type) or "sweep"))
                            item.frontalW = w
                            item.frontalH = h
                            item.frontalFill = (cfg and cfg.color) or obj.fill
                            item.frontalOpacity = CoerceNumber((cfg and cfg.opacity) or obj.opacity)
                        end
                        items[idx] = item
                        RegisterSceneItemId(idToIndex, obj.id, idx)
                        RegisterSceneItemId(idToIndex, obj.__objectGroupId, idx)
                        if obj.id then objectById[tostring(obj.id)] = obj end
                        if obj.__objectGroupId then objectById[tostring(obj.__objectGroupId)] = obj end
                    end
                end
            end
        end
    end

    return items, idToIndex, pathByAnimId, objectById
end

local function NormalizeAnimPathPoints(pathPoints, canvasW, canvasH)
    if type(pathPoints) ~= "table" or #pathPoints < 4 then return nil end
    local out = {}
    for i = 1, #pathPoints - 1, 2 do
        local x = CoerceNumber(pathPoints[i])
        local y = CoerceNumber(pathPoints[i + 1])
        if x and y then
            if x > 100 or y > 100 then
                x = ValueToPercent(x, canvasW)
                y = ValueToPercent(y, canvasH)
            end
            out[#out + 1] = { x, y }
        end
    end
    return (#out >= 2) and out or nil
end

local function ConvertWebSceneAnimations(scene, idToIndex, pathByAnimId, objectById, canvasW, canvasH)
    if type(scene) ~= "table" or type(scene.animationsJSON) ~= "string" or scene.animationsJSON == "" then
        return nil
    end
    local parsed = DecodeJSON(scene.animationsJSON)
    if type(parsed) ~= "table" then return nil end
    local out = {}
    for _, anim in ipairs(parsed) do
        if type(anim) == "table" then
            local entry = {
                startTime = CoerceNumber(anim.startTime) or 0,
                duration = CoerceNumber(anim.duration) or 1000,
            }

            local objectId = anim.objectId and tostring(anim.objectId) or nil
            local itemIndex = objectId and idToIndex and idToIndex[objectId] or nil
            if itemIndex then
                entry.itemIndex = itemIndex - 1
                entry.objectId = objectId
            end

            local animPath = NormalizeAnimPathPoints(anim.pathPoints, canvasW, canvasH)
            if not animPath and anim.pathId and pathByAnimId then
                local pathObj = pathByAnimId[tostring(anim.pathId)]
                animPath = pathObj and NormalizeAnimPathPoints(pathObj.__pathPoints, canvasW, canvasH) or nil
            end
            if animPath then entry.path = animPath end

            local isFrontal = CoerceBool(anim.isFrontalSweepAnimation)
            if isFrontal then
                entry.isFrontalSweepAnimation = true
                entry.frontalAnimationType = anim.frontalAnimationType
                entry.startAngle = CoerceNumber(anim.startAngle)
                entry.endAngle = CoerceNumber(anim.endAngle)
                entry.pulseWobbleDeg = CoerceNumber(anim.pulseWobbleDeg)
                local parentId = anim.parentObjectId and tostring(anim.parentObjectId) or nil
                local parentIdx = parentId and idToIndex and idToIndex[parentId] or nil
                if parentIdx then entry.parentItemIndex = parentIdx - 1 end

                local beamObj = objectId and objectById and objectById[objectId] or nil
                local beamCfg = beamObj and type(beamObj.__frontalConfig) == "table" and beamObj.__frontalConfig or nil
                if not entry.startAngle then entry.startAngle = CoerceNumber(beamCfg and beamCfg.startAngle) or CoerceNumber(beamObj and beamObj.angle) end
                if not entry.endAngle then entry.endAngle = CoerceNumber(anim.endAngle) or entry.startAngle end
                if beamCfg and beamCfg.color and not entry.frontalFill then entry.frontalFill = beamCfg.color end
                if beamCfg and beamCfg.opacity and not entry.frontalOpacity then entry.frontalOpacity = CoerceNumber(beamCfg.opacity) end
            end

            if CoerceBool(anim.isTetherAnimation) then
                entry.isTetherAnimation = true
                entry.tetherType = anim.tetherType
                entry.tetherDistance = CoerceNumber(anim.tetherDistance)
                entry.tetherDistancePercent = CoerceNumber(anim.tetherDistancePercent)
                local parentId = anim.tetherMainObjectId and tostring(anim.tetherMainObjectId) or nil
                local parentIdx = parentId and idToIndex and idToIndex[parentId] or nil
                if parentIdx then entry.parentItemIndex = parentIdx - 1 end
            end

            if CoerceBool(anim.isStationaryAnimation) then
                entry.isStationaryAnimation = true
                entry.type = anim.type
                entry.intensity = CoerceNumber(anim.intensity)
                entry.loop = CoerceBool(anim.loop)
            end

            if entry.itemIndex ~= nil or entry.path or entry.isFrontalSweepAnimation or entry.isTetherAnimation or entry.isStationaryAnimation then
                out[#out + 1] = entry
            end
        end
    end
    return out
end

local function ConvertWebPlannerScenes(data)
    if type(data) ~= "table" or type(data.scenes) ~= "table" then return end
    local canvasW, canvasH = 1115, 627
    for sceneIndex, scene in ipairs(data.scenes) do
        if type(scene) == "table" and (type(scene.objectsJSON) == "string" or type(scene.animationsJSON) == "string" or sceneIndex == 1) then
            -- Prefer scene.objectsJSON: it usually contains full grouped actor circles.
            -- canvasData.objects can be a flattened/partial snapshot (missing group children).
            local items, idToIndex, pathByAnimId, objectById = ConvertWebSceneObjects(scene, canvasW, canvasH)
            if (not items or #items == 0) and sceneIndex == 1 and type(data.canvasData) == "table" and type(data.canvasData.objects) == "table" then
                local fallbackScene = {
                    __objectsTable = data.canvasData.objects,
                }
                items, idToIndex, pathByAnimId, objectById = ConvertWebSceneObjects(fallbackScene, canvasW, canvasH)
            end
            if items and #items > 0 then
                -- Always prefer objectsJSON-derived items for web scenes.
                -- Some payloads include a stale scene.items snapshot alongside objectsJSON;
                -- that snapshot can carry unscaled group spot sizes on later scenes.
                scene.items = items
            end
            local anims = ConvertWebSceneAnimations(scene, idToIndex or {}, pathByAnimId or {}, objectById or {}, canvasW, canvasH)
            if anims and #anims > 0 and (type(scene.animations) ~= "table" or #scene.animations == 0) then
                scene.animations = anims
            end

            -- Fallback for scenes that carry frontal beam objects but no explicit frontal animations.
            if type(scene.items) == "table" and #scene.items > 0 then
                scene.animations = scene.animations or {}
                local hasFrontalAnimByItem = {}
                for _, anim in ipairs(scene.animations) do
                    if CoerceBool(anim and anim.isFrontalSweepAnimation) and CoerceNumber(anim.itemIndex) then
                        hasFrontalAnimByItem[math.floor(CoerceNumber(anim.itemIndex) + 0.0001)] = true
                    end
                end
                for itemIdx, item in ipairs(scene.items) do
                    if type(item) == "table" and CoerceBool(item.isFrontalBeam) and not hasFrontalAnimByItem[itemIdx - 1] then
                        local parentIdx = item.frontalParentId and idToIndex and idToIndex[tostring(item.frontalParentId)] or nil
                        if parentIdx then
                            scene.animations[#scene.animations + 1] = {
                                startTime = 0,
                                duration = 1000,
                                itemIndex = itemIdx - 1,
                                parentItemIndex = parentIdx - 1,
                                isFrontalSweepAnimation = true,
                                frontalAnimationType = item.frontalAnimationType or "sweep",
                                startAngle = CoerceNumber(item.startAngle) or 0,
                                endAngle = CoerceNumber(item.endAngle) or CoerceNumber(item.startAngle) or 0,
                                frontalShape = item.shape or "rect",
                                frontalW = CoerceNumber(item.frontalW) or CoerceNumber(item.w) or 5,
                                frontalH = CoerceNumber(item.frontalH) or CoerceNumber(item.h) or 18,
                                frontalFill = item.frontalFill or item.fill,
                                frontalOpacity = CoerceNumber(item.frontalOpacity) or CoerceNumber(item.opacity) or 0.55,
                            }
                        end
                    end
                end
            end
        end
    end
end

local function EnsureImportedBossPortraitFallback(data)
    if type(data) ~= "table" or type(data.scenes) ~= "table" then return end
    local hasBossImageMeta = (data.boss_image ~= nil) or (data.bossImage ~= nil)
        or (data.boss_render_image ~= nil) or (data.bossRenderImage ~= nil)
    if not hasBossImageMeta then
        return
    end
    for _, scene in ipairs(data.scenes) do
        scene.items = scene.items or {}
        if #scene.items == 0 then
            scene.items[1] = {
                kind = "icon",
                x = 42,
                y = 28,
                w = 16,
                h = 24,
                bossPortrait = true,
                label = "",
            }
        else
            for _, item in ipairs(scene.items) do
                if type(item) == "table" then
                    local looksLikeImageItem = (item.kind == "image") or (item.kind == "icon" and not item.icon)
                    local hasImageRef = (item.image ~= nil) or (item.src ~= nil) or (item.url ~= nil)
                        or (item.boss_image ~= nil) or (item.bossImage ~= nil)
                    if looksLikeImageItem and hasImageRef then
                        item.bossPortrait = true
                        if item.kind ~= "icon" then item.kind = "icon" end
                        item.x = CoerceNumber(item.x) or 42
                        item.y = CoerceNumber(item.y) or 28
                        item.w = CoerceNumber(item.w) or 16
                        item.h = CoerceNumber(item.h) or 24
                    end
                end
            end
        end
    end
end

local function BuildImportedItemId(usedIds)
    local attempt = 0
    while attempt < 32 do
        attempt = attempt + 1
        local candidate = ("obj-%s-%06x"):format(tostring(time() or 0), math.random(0, 0xFFFFFF))
        if candidate ~= "" and not usedIds[candidate] then
            return candidate
        end
    end
    local fallbackBase = ("obj-%s"):format(tostring(time() or 0))
    local idx = 1
    while true do
        local candidate = ("%s-%d"):format(fallbackBase, idx)
        if not usedIds[candidate] then
            return candidate
        end
        idx = idx + 1
    end
end

local function EnsureImportedItemIds(data)
    if type(data) ~= "table" or type(data.scenes) ~= "table" then return end
    local used = {}

    -- First pass: reserve existing unique ids.
    for _, scene in ipairs(data.scenes) do
        if type(scene) == "table" and type(scene.items) == "table" then
            for _, item in ipairs(scene.items) do
                if type(item) == "table" then
                    local id = strtrim(tostring(item.id or ""))
                    if id ~= "" and not used[id] then
                        used[id] = true
                    end
                end
            end
        end
    end

    -- Second pass: fill missing or duplicate ids.
    local seenInPlan = {}
    for _, scene in ipairs(data.scenes) do
        if type(scene) == "table" and type(scene.items) == "table" then
            for _, item in ipairs(scene.items) do
                if type(item) == "table" then
                    local id = strtrim(tostring(item.id or ""))
                    if id == "" or seenInPlan[id] then
                        id = BuildImportedItemId(used)
                        item.id = id
                        used[id] = true
                    end
                    seenInPlan[id] = true
                end
            end
        end
    end
end

function Raidstrats:DecodeAddonImportPayload(raw)
    if not raw or raw == "" then return nil end
    local b64 = raw:gsub("^%s+", ""):gsub("%s+$", "")
    if b64:sub(1, #PREFIX_PLANNER) == PREFIX_PLANNER then
        b64 = b64:sub(#PREFIX_PLANNER + 1)
    end
    b64 = b64:gsub("%s+", "")
    local decoded = DecodeBase64(b64)
    if not decoded or decoded == "" then return nil end
    local json = decoded
    if decoded:byte(1) == 0x01 then
        local LibDeflate = LibStub("LibDeflate", true)
        if not LibDeflate or not LibDeflate.DecompressDeflate then return nil end
        local inflated = LibDeflate:DecompressDeflate(decoded:sub(2))
        if not inflated or inflated == "" then return nil end
        json = inflated
    end
    return DecodeJSON(json)
end

function Raidstrats:ExtractAddonImportStrings(raw)
    local text = tostring(raw or "")
    local chunks = {}
    local starts = {}
    local pos = 1

    while true do
        local s = text:find(PREFIX_PLANNER, pos, true)
        if not s then break end
        starts[#starts + 1] = s
        pos = s + #PREFIX_PLANNER
    end

    if #starts == 0 then
        local single = strtrim(text)
        if single ~= "" then
            chunks[#chunks + 1] = single
        end
        return chunks
    end

    for i, s in ipairs(starts) do
        local e = (starts[i + 1] and (starts[i + 1] - 1)) or #text
        local part = strtrim(text:sub(s, e))
        if part ~= "" then
            chunks[#chunks + 1] = part
        end
    end

    return chunks
end

function Raidstrats:NormalizeDecodedPlanPayload(data)
    if type(data) ~= "table" or SceneCount(data.scenes) == 0 then return nil end
    -- Capture the shared sync version, then strip it so it never counts as plan content.
    local sharedVersion = tonumber(data.syncVersion)
    data.syncVersion = nil
    ConvertWebPlannerScenes(data)
    EnsureImportedBossPortraitFallback(data)
    EnsureImportedItemIds(data)
    if self.SanitizePlanData then self:SanitizePlanData(data) end
    data.__rsggImportedSanitized = true
    if sharedVersion then data.__rsggSharedVersion = sharedVersion end
    return data
end

function Raidstrats:DecodePlanFromBase64(raw)
    local data = self:DecodeAddonImportPayload(raw)
    return self:NormalizeDecodedPlanPayload(data)
end

function Raidstrats:GetPlayerShareName()
    local name = UnitName("player") or "Unknown"
    local realm = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName()
    if realm and realm ~= "" then return name .. "-" .. realm end
    return name
end

function Raidstrats:GetPlanShareLink(data)
    if not data or not data.scenes or #data.scenes == 0 then return nil end
    local json = EncodeJSON(data)
    if not json or json == "" then return nil end
    local b64 = EncodeBase64(json)
    if not b64 or b64 == "" then return nil end
    local id = string.format("%x%x", time(), math.random(0, 0xFFFFFF))
    self._sharedPlans = self._sharedPlans or {}
    self._sharedPlans[id] = { payload = b64, t = time() }
    return string.format("[Raidstrats: %s - %s]", self:GetPlayerShareName(), id)
end

function Raidstrats:GetPlanShareLinkDisplay(owner, id)
    local label = string.format("[Raidstrats: %s - %s]", owner, id)
    return "|cff00aaff|Hgarrmission:raidstrats:" .. label .. "|h" .. label .. "|h|r"
end

function Raidstrats:EchoToChat(msg)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(msg)
    else
        print(msg)
    end
end

-- Resolve the chat channel for sharing (instance > raid > party > guild). Returns nil if no channel.
function Raidstrats:GetGroupChatChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    if IsInGuild() then return "GUILD" end
    return nil
end

function Raidstrats:IsGuildOnlyShareChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return false end
    if IsInRaid() then return false end
    if IsInGroup() then return false end
    return IsInGuild() and true or false
end

function Raidstrats:GetPlanShareChatChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return "SAY"
end

-- AceComm channel for preloading the plan payload to the group (nil when solo / say-only).
function Raidstrats:GetPlanShareCommChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

function Raidstrats:NormalizeShareSender(name)
    if type(name) ~= "string" or name == "" then return "" end
    if Ambiguate then
        name = Ambiguate(name, "none") or name
    end
    return strlower(name)
end

function Raidstrats:MakeReceivedShareKey(sender, planName)
    return self:NormalizeShareSender(sender) .. "\0" .. tostring(planName or "")
end

function Raidstrats:CacheReceivedSharedPlan(sender, planName, payload)
    if type(payload) ~= "string" or payload == "" or not planName or planName == "" then return end
    self._receivedSharedPlans = self._receivedSharedPlans or {}
    local key = self:MakeReceivedShareKey(sender, planName)
    self._receivedSharedPlans[key] = {
        payload = payload,
        sender = sender,
        planName = planName,
        t = time(),
    }
    if self.IsRsggDebug and self:IsRsggDebug() then
        local short = Ambiguate and Ambiguate(sender, "short") or sender
        local msg = ("Share cache received: plan=\"%s\" from=%s bytes=%d"):format(
            tostring(planName), tostring(short), #payload)
        if self.AppendPlannerDebugLine then
            self:AppendPlannerDebugLine(msg)
        end
        print("|cff66ccff[Raidstrats.gg Debug]|r " .. msg)
    end
end

function Raidstrats:GetReceivedSharedPlan(sender, planName)
    local map = self._receivedSharedPlans
    if not map or not planName or planName == "" then return nil end
    local now = time()
    local key = self:MakeReceivedShareKey(sender, planName)
    local entry = map[key]
    if entry and entry.payload and entry.payload ~= "" and (now - (entry.t or 0)) <= SHARED_PLAN_TTL then
        return entry
    end
    -- Fallback: unique match on plan name (same raid usually only has one active share).
    local found = nil
    for _, e in pairs(map) do
        if e and e.planName == planName and e.payload and e.payload ~= ""
            and (now - (e.t or 0)) <= SHARED_PLAN_TTL then
            if found then return nil end
            found = e
        end
    end
    return found
end

function Raidstrats:CacheReceivedSharedPlanGroup(sender, linkLabel, payload)
    if type(payload) ~= "string" or payload == "" or not linkLabel or linkLabel == "" then return end
    self._receivedSharedPlanGroups = self._receivedSharedPlanGroups or {}
    local key = self:MakeReceivedShareKey(sender, linkLabel)
    self._receivedSharedPlanGroups[key] = {
        payload = payload,
        sender = sender,
        planName = linkLabel,
        t = time(),
    }
    if self.IsRsggDebug and self:IsRsggDebug() then
        local short = Ambiguate and Ambiguate(sender, "short") or sender
        local msg = ("Share group cache received: group=\"%s\" from=%s bytes=%d"):format(
            tostring(linkLabel), tostring(short), #payload)
        if self.AppendPlannerDebugLine then
            self:AppendPlannerDebugLine(msg)
        end
        print("|cff66ccff[Raidstrats.gg Debug]|r " .. msg)
    end
end

function Raidstrats:GetReceivedSharedPlanGroup(sender, linkLabel)
    local map = self._receivedSharedPlanGroups
    if not map or not linkLabel or linkLabel == "" then return nil end
    local now = time()
    local key = self:MakeReceivedShareKey(sender, linkLabel)
    local entry = map[key]
    if entry and entry.payload and entry.payload ~= "" and (now - (entry.t or 0)) <= SHARED_PLAN_TTL then
        return entry
    end
    local found = nil
    for _, e in pairs(map) do
        if e and e.planName == linkLabel and e.payload and e.payload ~= ""
            and (now - (e.t or 0)) <= SHARED_PLAN_TTL then
            if found then return nil end
            found = e
        end
    end
    return found
end

local function EnsureShareToGuildPopup()
    if StaticPopupDialogs["RAIDSTRATSGG_SHARE_TO_GUILD"] then return end
    StaticPopupDialogs["RAIDSTRATSGG_SHARE_TO_GUILD"] = {
        text = "You are not in a party or raid. Share \"%s\" to guild chat? Everyone in your guild will see this link.",
        button1 = _G.YES or "Yes",
        button2 = _G.CANCEL or "Cancel",
        OnAccept = function(popup)
            local data = popup.data
            if data then
                Raidstrats:SharePlanToGroup(data, { confirmedGuild = true })
            end
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
    }
end

local function ChannelLabel(chan)
    if chan == "INSTANCE_CHAT" then return "instance" end
    if chan == "RAID" then return "raid" end
    if chan == "PARTY" then return "party" end
    if chan == "SAY" then return "say" end
    if chan == "GUILD" then return "guild" end
    return tostring(chan)
end

-- Strip characters that would break the chat token / hyperlink and cap length.
local function SanitizeShareName(name)
    name = tostring(name or ""):gsub("[%[%]|%c:]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then name = "Raid plan" end
    if #name > 50 then name = name:sub(1, 50) end
    return name
end

-- Build the base64 plan payload, compressed (0x01 marker) when LibDeflate is available.
-- Matches ImportPlanFromPasteString, which inflates a 0x01-prefixed deflate stream.
function Raidstrats:BuildSharePayload(data, opts)
    -- Ensure a stable team identity before sharing so sync versions line up on import.
    if data then self:EnsurePlanInstanceKey(data) end
    data = self:PreparePlanDataForShare(data)
    if not data then return nil end
    -- Stamp the sync version so importers are immediately ready for delta push updates.
    -- Push updates manage their own version, so they opt out via skipSyncVersionStamp.
    -- Stamp bumps only when content differs from the last sync baseline.
    if self.StampShareSyncVersion and not (opts and opts.skipSyncVersionStamp) then
        self:StampShareSyncVersion(data, opts)
    end
    local json = EncodeJSON(data)
    if not json or json == "" then return nil end
    local body = json
    local LibDeflate = LibStub("LibDeflate", true)
    if LibDeflate and LibDeflate.CompressDeflate then
        -- Use a slightly lower level for better send-time responsiveness.
        local ok, compressed = pcall(function() return LibDeflate:CompressDeflate(json, { level = 6 }) end)
        if ok and compressed and (#compressed + 1) < #json then
            body = string.char(0x01) .. compressed
        end
    end
    return EncodeBase64(body)
end

function Raidstrats:BuildPlanShareToken(data)
    if not data or type(data.scenes) ~= "table" or #data.scenes == 0 then
        return nil
    end
    local payload = self:BuildSharePayload(data)
    if not payload or payload == "" then
        return nil
    end
    local planName = SanitizeShareName((type(data.planName) == "string" and data.planName ~= "") and data.planName or "Raid plan")
    self._sharedPlans = self._sharedPlans or {}
    self._sharedPlans[planName] = { payload = payload, t = time() }
    return ("[Raidstrats: %s]"):format(planName)
end

function Raidstrats:InsertShareTokenIntoActiveChat(token)
    if type(token) ~= "string" or token == "" then
        return false
    end
    local edit = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
    if not edit or (edit.IsShown and not edit:IsShown()) then
        return false
    end

    local inserted = false
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        inserted = ChatFrameUtil.InsertLink(token) and true or false
    elseif ChatEdit_InsertLink then
        inserted = ChatEdit_InsertLink(token) and true or false
    end

    if not inserted and edit and edit.Insert then
        local text = edit:GetText() or ""
        if text ~= "" and not text:match("%s$") then
            edit:Insert(" ")
        end
        edit:Insert(token)
        inserted = true
    end
    return inserted
end

function Raidstrats:InsertPlanShareTokenIntoActiveChat(data)
    local token = self:BuildPlanShareToken(data)
    if not token then return false end
    return self:InsertShareTokenIntoActiveChat(token)
end

local SHARE_PLAN_BATCH = 180

function Raidstrats:SendSharedPlanWhisper(target, planName, payload)
    if not target or not planName or not payload or payload == "" then return false end
    local totalChunks = math.ceil(#payload / SHARE_PLAN_BATCH)
    for j = 1, totalChunks do
        local start = (j - 1) * SHARE_PLAN_BATCH + 1
        local chunk = payload:sub(start, start + SHARE_PLAN_BATCH - 1)
        self:SendCommMessage(
            COMM_PLAN_PREFIX,
            ("DATA:%s:%d:%d:%s"):format(planName, j, totalChunks, chunk),
            "WHISPER",
            target,
            "BULK"
        )
    end
    return true
end

-- Push the full plan once to party/raid/instance so clickers can import locally.
-- Whisper REQ remains the fallback for late joiners / missed broadcasts.
function Raidstrats:SendSharedPlanBroadcast(planName, payload)
    local chan = self.GetPlanShareCommChannel and self:GetPlanShareCommChannel() or nil
    if not chan or not planName or not payload or payload == "" then return false end
    local totalChunks = math.ceil(#payload / SHARE_PLAN_BATCH)
    for j = 1, totalChunks do
        local start = (j - 1) * SHARE_PLAN_BATCH + 1
        local chunk = payload:sub(start, start + SHARE_PLAN_BATCH - 1)
        self:SendCommMessage(
            COMM_PLAN_PREFIX,
            ("BDAT:%s:%d:%d:%s"):format(planName, j, totalChunks, chunk),
            chan,
            nil,
            "BULK"
        )
    end
    return true
end

function Raidstrats:HandleSharedPlanBroadcastChunk(sender, planName, index, total, chunk)
    if not sender or not planName or not index or not total or type(chunk) ~= "string" then return end
    self._broadcastPlanIncoming = self._broadcastPlanIncoming or {}
    local key = self:MakeReceivedShareKey(sender, planName)
    local entry = self._broadcastPlanIncoming[key]
    if not entry then
        entry = { planName = planName, sender = sender, chunks = {}, total = total, t = GetTime() }
        self._broadcastPlanIncoming[key] = entry
    end
    entry.total = total
    entry.chunks[index] = chunk
    entry.t = GetTime()
    for i = 1, entry.total do
        if not entry.chunks[i] then return end
    end
    local payload = table.concat(entry.chunks, "")
    self._broadcastPlanIncoming[key] = nil
    self:CacheReceivedSharedPlan(sender, planName, payload)
end

-- Share the current plan to chat, WeakAuras-style: post a plain-text token that each
-- addon user's chat filter renders as a clickable link. Also preload the payload once
-- over group AceComm so many simultaneous clicks don't each whisper-download it.
function Raidstrats:SharePlanToGroup(data, opts)
    opts = opts or {}
    data = data or self.plannerData
    if not data or type(data.scenes) ~= "table" or #data.scenes == 0 then
        print("|cffff6666[Raidstrats.gg]|r No plan loaded to share.")
        return false
    end

    self:EnsurePlanInstanceKey(data)
    if self.PersistCurrentPlanToSaved then
        self:PersistCurrentPlanToSaved()
    end

    local chan = self.GetPlanShareChatChannel and self:GetPlanShareChatChannel() or self:GetGroupChatChannel()
    if chan == "GUILD" then
        chan = "SAY"
    end
    if not chan then
        chan = "SAY"
    end
    if not chan then
        print("|cffff6666[Raidstrats.gg]|r Couldn't resolve a chat channel for sharing.")
        return false
    end

    local payload = self:BuildSharePayload(data)
    if not payload or payload == "" then
        print("|cffff6666[Raidstrats.gg]|r Couldn't prepare the plan for sharing.")
        return false
    end

    local planName = SanitizeShareName((type(data.planName) == "string" and data.planName ~= "") and data.planName or "Raid plan")

    -- Cache the payload so we can answer whisper fallback requests from clickers.
    self._sharedPlans = self._sharedPlans or {}
    self._sharedPlans[planName] = { payload = payload, t = time() }

    -- Preload once to the group; clickers import from this cache when available.
    local broadcasted = self:SendSharedPlanBroadcast(planName, payload)

    -- Post the plain-text token; clients with the addon turn it into a clickable link.
    SendChatMessage(("[Raidstrats: %s]"):format(planName), chan)

    if broadcasted then
        print(("|cff00aaff[Raidstrats.gg]|r Shared \"%s\" to %s (preloaded to group). Others click the link to import."):format(planName, ChannelLabel(chan)))
    else
        print(("|cff00aaff[Raidstrats.gg]|r Shared \"%s\" to %s. Others click the link to import."):format(planName, ChannelLabel(chan)))
    end
    return true
end

-- ----------------------------------------------------------------------------
-- Clickable share links (WeakAuras-style).
-- Blizzard strips custom hyperlinks from player chat, so we send a plain-text
-- token and rebuild the clickable link locally via a chat message filter. The
-- link encodes the sender + plan name; clicking it requests the plan over comms.
-- ----------------------------------------------------------------------------

-- Import from local preload/cache when possible; otherwise whisper-request from the sharer.
function Raidstrats:RequestSharedPlan(sender, planName)
    if not sender or not planName then return end

    local me = UnitName("player")
    local isSelf = sender == me or (Ambiguate and Ambiguate(sender, "short") == me)

    local groupEntry = self._sharedPlanGroups and self._sharedPlanGroups[planName]
    if groupEntry and groupEntry.payload and isSelf then
        self:OpenPlannerAfterShareImport()
        if self.ShowImportProgress then self:ShowImportProgress(true, 0, nil, "Importing shared group...") end
        if self.ImportSharedPlanGroupPayload then
            self:ImportSharedPlanGroupPayload(groupEntry.payload, sender)
        else
            if self.HideImportProgress then self:HideImportProgress() end
            print("|cffff6666[Raidstrats.gg]|r Couldn't import the cached plan group.")
        end
        return
    end

    local entry = self._sharedPlans and self._sharedPlans[planName]
    if entry and entry.payload and isSelf then
        local ok = self:ImportPlanFromPasteString(PREFIX_PLANNER .. entry.payload)
        if ok == true then
            self:OpenPlannerAfterShareImport()
        elseif ok == "pending" then
            -- Waiting on user conflict choice (override/skip).
        else
            print("|cffff6666[Raidstrats.gg]|r Couldn't import the cached plan.")
        end
        return
    end

    local isGroupShareToken = type(planName) == "string"
        and planName:find('Group "', 1, true) == 1
        and planName:find(" Plan", 1, true) ~= nil

    -- Prefer the group AceComm preload so 10 simultaneous clicks don't each whisper-download.
    if isGroupShareToken then
        local receivedGroup = self.GetReceivedSharedPlanGroup and self:GetReceivedSharedPlanGroup(sender, planName)
        if receivedGroup and receivedGroup.payload and self.ImportSharedPlanGroupPayload then
            self:OpenPlannerAfterShareImport()
            if self.ShowImportProgress then self:ShowImportProgress(true, 0, nil, "Importing shared group...") end
            self:ImportSharedPlanGroupPayload(receivedGroup.payload, receivedGroup.sender or sender)
            return
        end
    else
        local received = self.GetReceivedSharedPlan and self:GetReceivedSharedPlan(sender, planName)
        if received and received.payload then
            if self.ShowImportProgress then self:ShowImportProgress(true, 0, nil, "Importing shared plan...") end
            local ok = self:ImportPlanFromPasteString(PREFIX_PLANNER .. received.payload)
            if self.HideImportProgress then self:HideImportProgress() end
            if ok == true then
                self:OpenPlannerAfterShareImport()
                print("|cff00aaff[Raidstrats.gg]|r Plan imported!")
            elseif ok == "pending" then
                -- Waiting on user conflict choice (override/skip).
            else
                print("|cffff6666[Raidstrats.gg]|r Couldn't import the cached plan.")
            end
            return
        end
    end

    if isGroupShareToken and self.HandleSharedPlanGroupComm then
        self._sharedPlanGroupsIncoming = self._sharedPlanGroupsIncoming or {}
        self._sharedPlanGroupsIncoming[planName] = { id = planName, chunks = {}, total = nil, t = GetTime(), sender = sender }
        self:OpenPlannerAfterShareImport()
        if self.ShowImportProgress then self:ShowImportProgress(true, 0, nil, "Requesting group...") end
        self:SendCommMessage(COMM_PLAN_PREFIX, "GREQ" .. string.char(31) .. planName, "WHISPER", sender, "BULK")
        print(("|cff00aaff[Raidstrats.gg]|r Requesting \"%s\" from %s..."):format(planName, Ambiguate and Ambiguate(sender, "short") or sender))
        return
    end
    self._incomingPlan = { owner = sender, id = planName, chunks = {}, total = nil, t = GetTime() }
    self:OpenPlannerAfterShareImport()
    if self.ShowImportProgress then self:ShowImportProgress(true, 0, nil, "Requesting plan...") end
    print(("|cff00aaff[Raidstrats.gg]|r Requesting \"%s\" from %s..."):format(planName, Ambiguate and Ambiguate(sender, "short") or sender))
    self:SendCommMessage(COMM_PLAN_PREFIX, "REQ:" .. planName, "WHISPER", sender, "BULK")
end

function Raidstrats:SetupSharedPlanLinks()
    if self._shareLinksReady then return end
    self._shareLinksReady = true

    local function MakeLink(sender, planName)
        return ("|cff00aaff|Hgarrmission:raidstrats:%s:%s|h[Raidstrats: %s]|h|r"):format(sender, planName, planName)
    end

    local function ChatFilter(_, _, msg, sender, ...)
        if type(msg) ~= "string" or not msg:find("%[Raidstrats: ") then
            return false
        end
        local from = sender
        local newMsg = msg:gsub("%[Raidstrats: (.-)%]", function(name)
            return MakeLink(from, name)
        end)
        return false, newMsg, sender, ...
    end

    for _, event in ipairs({
        "CHAT_MSG_SAY", "CHAT_MSG_YELL",
        "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
        "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
        "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
        "CHAT_MSG_CHANNEL",
        "CHAT_MSG_BATTLEGROUND", "CHAT_MSG_BATTLEGROUND_LEADER",
        "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
        "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    }) do
        ChatFrame_AddMessageEventFilter(event, ChatFilter)
    end

    hooksecurefunc("SetItemRef", function(link)
        if type(link) ~= "string" then return end
        local sender, planName = link:match("^garrmission:raidstrats:([^:]+):(.+)$")
        if sender and planName then
            Raidstrats:RequestSharedPlan(sender, planName)
        end
    end)
end

--UI
local function SkinScrollBar(scrollFrame)
    if not scrollFrame then return end
    local sb = scrollFrame.ScrollBar
    if not sb then return end
    if sb.ScrollUpButton then sb.ScrollUpButton:Hide(); sb.ScrollUpButton:SetScript("OnShow", function(s) s:Hide() end) end
    if sb.ScrollDownButton then sb.ScrollDownButton:Hide(); sb.ScrollDownButton:SetScript("OnShow", function(s) s:Hide() end) end
    for _, region in ipairs({sb:GetRegions()}) do
        if region:GetObjectType() == "Texture" then region:SetTexture(nil) end
    end
    if sb.ThumbTexture then 
        sb.ThumbTexture:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        sb.ThumbTexture:SetVertexColor(0.25, 0.25, 0.25, 1)
        sb.ThumbTexture:SetWidth(4)
    end
    sb:SetWidth(6)
end

local function SetBackdrop(f, c, borderColor, edgeSize)
    if not f.SetBackdrop then Mixin(f, BackdropTemplateMixin) end
    local es = edgeSize or 1
    f:SetBackdrop({bgFile="Interface\\ChatFrame\\ChatFrameBackground", edgeFile="Interface\\ChatFrame\\ChatFrameBackground", edgeSize=es})
    f:SetBackdropColor(unpack(c or C_BG))
    f:SetBackdropBorderColor(unpack(borderColor or C_BORDER))
    
    if not f.shadow then
        f.shadow = f:CreateTexture(nil, "BACKGROUND", nil, -1)
        f.shadow:SetPoint("TOPLEFT", -6, 6)
        f.shadow:SetPoint("BOTTOMRIGHT", 6, -6)
        f.shadow:SetColorTexture(0, 0, 0, 0.5)
    end
end

local function CreateAnimatedCheckbox(p, label)
    local b = CreateFrame("Button", nil, p, "BackdropTemplate")
    b:SetSize(22, 22)
    SetBackdrop(b, C_INPUT, {0.2, 0.2, 0.2, 1}, 2)
    
    local fill = b:CreateTexture(nil, "ARTWORK")
    fill:SetColorTexture(unpack(C_ACCENT))
    fill:SetPoint("TOPLEFT", 5, -5)
    fill:SetPoint("BOTTOMRIGHT", -5, 5)
    
    fill:Hide() 
    b.Fill = fill
    
    b.isChecked = false

    local function UpdateVisuals(self)
        if self.isChecked then
            self.Fill:Show()
            self:SetBackdropBorderColor(unpack(C_ACCENT))
        else
            self.Fill:Hide()
            self:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
        end
    end

    b.UpdateVisuals = UpdateVisuals

    if label and label ~= "" then
        local t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
        t:SetText(label)
        t:SetPoint("LEFT", b, "RIGHT", 10, 0)
        t:SetTextColor(0.8, 0.8, 0.8)
        b.label = t
    end

    b.GetChecked = function(self)
        return self.isChecked and true or false
    end

    b.SetChecked = function(self, on)
        self.isChecked = on and true or false
        UpdateVisuals(self)
    end
    
    b:SetScript("OnEnter", function(s)
        if not s.isChecked then
            s:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        end
        s:SetBackdropColor(0.15, 0.15, 0.18, 1)
    end)
    
    b:SetScript("OnLeave", function(s)
        UpdateVisuals(s)
        s:SetBackdropColor(unpack(C_INPUT))
    end)

    b:SetScript("OnClick", function(s)
        s.isChecked = not s.isChecked
        UpdateVisuals(s)
    end)
    
    return b
end

local function CreateLoaderButton(p, txt)
    local b = CreateFrame("StatusBar", nil, p, "BackdropTemplate")
    b:SetHeight(40)
    b:SetStatusBarTexture("Interface\\ChatFrame\\ChatFrameBackground")
    b:SetStatusBarColor(unpack(C_ACCENT))
    SetBackdrop(b, C_BG) 
    
    local t = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetText(txt); t:SetTextColor(1,1,1,1); t:SetPoint("CENTER")
    b.Text = t

    b:EnableMouse(true)
    b:SetScript("OnEnter", function(s) 
        if s:IsMouseEnabled() then 
            s:SetBackdropColor(0.15, 0.15, 0.18, 1) 
            s:SetStatusBarColor(unpack(C_HOVER))
        end 
    end)
    b:SetScript("OnLeave", function(s) 
        if s:IsMouseEnabled() then 
            s:SetBackdropColor(unpack(C_BG))
            s:SetStatusBarColor(unpack(C_ACCENT))
        end 
    end)
    
    b:SetMinMaxValues(0, 1); b:SetValue(0)
    
    b.scanProgress = 0
    b.scanTotal = 0
    b.isScanning = false
    b.dotTimer = 0
    b.dotCount = 1

    b:SetScript("OnUpdate", function(self, elapsed)
        if not self.isScanning then return end
        
        self.dotTimer = self.dotTimer + elapsed
        if self.dotTimer > 0.33 then 
            self.dotTimer = 0
            self.dotCount = (self.dotCount % 3) + 1
            
            local dots = string.rep(".", self.dotCount)
            self.Text:SetText(string.format("SCANNING %d/%d%s", self.scanProgress, self.scanTotal, dots))
        end
    end)
    
    b.SetLoadingState = function(self, isScanning, progress, total)
        if isScanning then
            if not self.isScanning then
                self.dotCount = 1
                self.dotTimer = 0
            end
            
            self.isScanning = true
            self.scanProgress = progress or 0
            self.scanTotal = total or 0
            
            self:EnableMouse(false)
            self:SetMinMaxValues(0, self.scanTotal)
            self:SetValue(self.scanProgress)
            
            local dots = string.rep(".", self.dotCount)
            self.Text:SetText(string.format("SCANNING %d/%d%s", self.scanProgress, self.scanTotal, dots))
            
            self:SetBackdropColor(unpack(C_BG))
            self:SetStatusBarColor(unpack(C_ACCENT))
        else
            self.isScanning = false
            self:EnableMouse(true)
            self:SetMinMaxValues(0, 1)
            self:SetValue(1)
            self.Text:SetText(txt)
            self:SetStatusBarColor(unpack(C_ACCENT))
        end
    end
    
    b:SetLoadingState(false)
    return b
end

local function CreateStopButton(p)
    local b = CreateFrame("Button", nil, p, "BackdropTemplate")
    b:SetSize(40, 40)
    SetBackdrop(b, C_RED)
    
    if b.shadow then b.shadow:Hide() end
    
    local t = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetText("X")
    t:SetTextColor(1, 1, 1, 1)
    t:SetShadowOffset(0, 0)
    t:SetPoint("CENTER", 0, 0)
    
    b:SetScript("OnEnter", function(s) s:SetBackdropColor(1, 0.3, 0.3, 1) end)
    b:SetScript("OnLeave", function(s) s:SetBackdropColor(unpack(C_RED)) end)
    
    return b
end

local function CreateButton(p, txt)
    local b = CreateFrame("Button", nil, p, "BackdropTemplate")
    b:SetHeight(40); SetBackdrop(b, C_ACCENT)
    local t = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetText(txt); t:SetTextColor(1,1,1,1); t:SetPoint("CENTER")
    
    b:SetScript("OnEnter", function(s) if s:IsEnabled() then s:SetBackdropColor(unpack(C_HOVER)) end end)
    b:SetScript("OnLeave", function(s) if s:IsEnabled() then s:SetBackdropColor(unpack(C_ACCENT)) end end)
    b:SetScript("OnDisable", function(s) s:SetBackdropColor(unpack(C_DISABLED)); s:SetAlpha(0.6) end)
    b:SetScript("OnEnable", function(s) s:SetBackdropColor(unpack(C_ACCENT)); s:SetAlpha(1) end)
    
    return b
end

local function CreateInput(p, lbl, multi)
    local f = CreateFrame("Frame", nil, p, "BackdropTemplate")
    SetBackdrop(f, C_INPUT); f:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
    if lbl then
        local l = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
        l:SetText(lbl:upper()); l:SetTextColor(0.6,0.6,0.6); l:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 6)
    end
    local eb
    if multi then
        local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 8, -8); sf:SetPoint("BOTTOMRIGHT", -24, 8)
        SkinScrollBar(sf)
        eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetMaxLetters(0)
        eb:SetWidth(math.max(1, sf:GetWidth()))
        sf:SetScrollChild(eb)
        sf:EnableMouse(true)
        sf:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" and eb and eb.SetFocus then
                eb:SetFocus()
            end
        end)
        f._scroll = sf
        f._edit = eb
        f.SyncEditWidth = function(self)
            local w = self:GetWidth()
            if w and w > 32 and self._scroll and self._edit then
                local innerW = w - 32
                self._scroll:SetWidth(innerW)
                self._edit:SetWidth(innerW)
                local innerH = math.max(1, self._scroll:GetHeight())
                local textH = 0
                if self._edit.GetStringHeight then
                    textH = tonumber(self._edit:GetStringHeight()) or 0
                elseif self._edit.GetTextHeight then
                    textH = tonumber(self._edit:GetTextHeight()) or 0
                else
                    -- Conservative fallback for clients where height APIs are unavailable.
                    local _, fontSize = self._edit:GetFont()
                    local fs = tonumber(fontSize) or 14
                    textH = fs * 1.4
                end
                textH = math.ceil(textH + 16)
                self._edit:SetHeight(math.max(innerH, textH))
            end
        end
        eb:SetScript("OnTextChanged", function()
            if f and f.SyncEditWidth then f:SyncEditWidth() end
        end)
        f:SetScript("OnSizeChanged", function(s) s:SyncEditWidth() end)
    else
        eb = CreateFrame("EditBox", nil, f); eb:SetPoint("LEFT",10,0); eb:SetPoint("RIGHT",-10,0); eb:SetHeight(30)
    end
    eb:SetFontObject("GameFontHighlightLarge"); eb:SetAutoFocus(false); eb:SetTextInsets(4, 4, 4, 4)
    return f, eb
end

function Raidstrats:PrepareModal(modal, anchor)
    if not modal then return end
    modal:SetFrameStrata("FULLSCREEN_DIALOG")
    local level = 500
    if anchor and anchor.IsShown and anchor:IsShown() then
        level = anchor:GetFrameLevel() + 100
    elseif self.plannerFrame and self.plannerFrame:IsShown() then
        level = self.plannerFrame:GetFrameLevel() + 100
    elseif self.frame and self.frame:IsShown() then
        level = self.frame:GetFrameLevel() + 100
    end
    modal:SetFrameLevel(level)
    modal:Raise()
end

function Raidstrats:LayoutOpenWindows()
    local main = self.frame
    local planner = self.plannerFrame
    local mainShown = main and main:IsShown()
    local plannerShown = planner and planner:IsShown()
    if mainShown and plannerShown then
        main:ClearAllPoints()
        main:SetPoint("CENTER", -400, 0)
        planner:ClearAllPoints()
        planner:SetPoint("CENTER", 400, 0)
    elseif mainShown then
        main:ClearAllPoints()
        main:SetPoint("CENTER", 0, 0)
    elseif plannerShown then
        planner:ClearAllPoints()
        planner:SetPoint("CENTER", 0, 0)
    end
end

-- After a share-link or comm import: hide roster window, show only the planner.
function Raidstrats:OpenPlannerAfterShareImport(opts)
    opts = opts or {}
    if self.frame then
        self.frame:Hide()
    end
    if self.importPlanDialog then
        self.importPlanDialog:Hide()
    end
    if not self.ShowPlannerViewer then return end
    local reloadOnly = opts.reloadOnly
    if reloadOnly == nil then
        reloadOnly = self.plannerFrame and self.plannerFrame:IsShown()
    end
    if reloadOnly then
        self:ShowPlannerViewer({ reloadOnly = true })
    else
        self:ShowPlannerViewer()
    end
    if self.LayoutOpenWindows then
        self:LayoutOpenWindows()
    end
end

function Raidstrats:ShowMultiImportConfirmDialog(raw, opts, count)
    local total = tonumber(count) or 0
    if total < 2 then total = 2 end
    self._pendingMultiImport = {
        raw = raw,
        opts = opts,
        count = total,
    }

    if not self.multiImportConfirmDialog then
        local f = CreateFrame("Frame", "RaidstratsMultiImportConfirmDialog", UIParent, "BackdropTemplate")
        f:SetSize(520, 240)
        f:SetPoint("CENTER", 0, 0)
        f:SetMovable(true)
        f:EnableMouse(true)
        if self.SetBackdrop then
            self.SetBackdrop(f)
        end
        tinsert(UISpecialFrames, "RaidstratsMultiImportConfirmDialog")
        f:SetScript("OnMouseDown", function(s, b) if b == "LeftButton" then s:StartMoving() end end)
        f:SetScript("OnMouseUp", function(s) s:StopMovingOrSizing() end)

        local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -5, -5)
        closeBtn:SetScript("OnClick", function()
            if Raidstrats then
                Raidstrats._pendingMultiImport = nil
            end
            f:Hide()
        end)

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -18)
        title:SetText("Import Multiple Plans")
        title:SetTextColor(0.9, 0.9, 0.9)

        local body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        body:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -62)
        body:SetPoint("TOPRIGHT", f, "TOPRIGHT", -24, -62)
        body:SetJustifyH("LEFT")
        body:SetJustifyV("TOP")
        body:SetSpacing(4)
        body:SetTextColor(0.75, 0.80, 0.88)
        f.bodyText = body

        local importBtn = self.CreateButton and self.CreateButton(f, "IMPORT ALL") or CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        importBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 24, 20)
        importBtn:SetPoint("RIGHT", f, "CENTER", -8, 0)
        importBtn:SetScript("OnClick", function()
            local pending = f.pendingData
            f:Hide()
            if not pending or not Raidstrats or not Raidstrats.TryImportPlanFromText then return end
            Raidstrats._pendingMultiImport = nil
            local copiedOpts = {}
            if type(pending.opts) == "table" then
                for k, v in pairs(pending.opts) do
                    copiedOpts[k] = v
                end
            end
            copiedOpts._confirmedMultiImport = true
            Raidstrats:TryImportPlanFromText(pending.raw, copiedOpts)
        end)

        local cancelBtn = self.CreateButton and self.CreateButton(f, "CANCEL") or CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        cancelBtn:SetPoint("LEFT", f, "CENTER", 8, 0)
        cancelBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 20)
        cancelBtn:SetScript("OnClick", function()
            if Raidstrats then
                Raidstrats._pendingMultiImport = nil
            end
            f:Hide()
        end)

        self.multiImportConfirmDialog = f
    end

    local dialog = self.multiImportConfirmDialog
    dialog.pendingData = self._pendingMultiImport
    if dialog.bodyText then
        dialog.bodyText:SetText(
            ("Found %d plan export strings in this paste.\n\nImport all of them now?"):format(total)
        )
    end
    if self.importPlanDialog and self.importPlanDialog:IsShown() then
        self.importPlanDialog:Hide()
    end
    if self.PrepareModal then
        self:PrepareModal(dialog, self.importPlanDialog or self.plannerFrame or self.frame)
    end
    dialog:Show()
end

function Raidstrats:ShowExistingImportConflictDialog(raw, opts, existingCount, totalCount)
    local existing = tonumber(existingCount) or 0
    local total = tonumber(totalCount) or 0
    if existing < 1 then existing = 1 end
    if total < existing then total = existing end
    self._pendingExistingImport = {
        raw = raw,
        opts = opts,
        existingCount = existing,
        totalCount = total,
    }

    if not self.existingImportConflictDialog then
        local f = CreateFrame("Frame", "RaidstratsExistingImportConflictDialog", UIParent, "BackdropTemplate")
        f:SetSize(560, 260)
        f:SetPoint("CENTER", 0, 0)
        f:SetMovable(true)
        f:EnableMouse(true)
        if self.SetBackdrop then self.SetBackdrop(f) end
        tinsert(UISpecialFrames, "RaidstratsExistingImportConflictDialog")
        f:SetScript("OnMouseDown", function(s, b) if b == "LeftButton" then s:StartMoving() end end)
        f:SetScript("OnMouseUp", function(s) s:StopMovingOrSizing() end)

        local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -5, -5)
        closeBtn:SetScript("OnClick", function()
            if Raidstrats then
                Raidstrats._pendingExistingImport = nil
            end
            f:Hide()
        end)

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -18)
        title:SetText("Import UUID Conflicts")
        title:SetTextColor(0.9, 0.9, 0.9)

        local body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        body:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -62)
        body:SetPoint("TOPRIGHT", f, "TOPRIGHT", -24, -62)
        body:SetJustifyH("LEFT")
        body:SetJustifyV("TOP")
        body:SetSpacing(4)
        body:SetTextColor(0.75, 0.80, 0.88)
        f.bodyText = body

        local overrideBtn = self.CreateButton and self.CreateButton(f, "OVERRIDE CONFLICTS") or CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        overrideBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 24, 20)
        overrideBtn:SetPoint("RIGHT", f, "CENTER", -8, 0)
        overrideBtn:SetScript("OnClick", function()
            local pending = f.pendingData
            f:Hide()
            if not pending or not Raidstrats or not Raidstrats.TryImportPlanFromText then return end
            Raidstrats._pendingExistingImport = nil
            local copiedOpts = {}
            if type(pending.opts) == "table" then
                for k, v in pairs(pending.opts) do copiedOpts[k] = v end
            end
            copiedOpts._confirmedMultiImport = true
            copiedOpts._existingMode = "override"
            Raidstrats:TryImportPlanFromText(pending.raw, copiedOpts)
        end)

        local skipBtn = self.CreateButton and self.CreateButton(f, "SKIP CONFLICTS") or CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        skipBtn:SetPoint("LEFT", f, "CENTER", 8, 0)
        skipBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 20)
        skipBtn:SetScript("OnClick", function()
            local pending = f.pendingData
            f:Hide()
            if not pending or not Raidstrats or not Raidstrats.TryImportPlanFromText then return end
            Raidstrats._pendingExistingImport = nil
            local copiedOpts = {}
            if type(pending.opts) == "table" then
                for k, v in pairs(pending.opts) do copiedOpts[k] = v end
            end
            copiedOpts._confirmedMultiImport = true
            copiedOpts._existingMode = "skip"
            Raidstrats:TryImportPlanFromText(pending.raw, copiedOpts)
        end)

        self.existingImportConflictDialog = f
    end

    local dialog = self.existingImportConflictDialog
    dialog.pendingData = self._pendingExistingImport
    if dialog.bodyText then
        dialog.bodyText:SetText(
            ("%d out of %d plan(s) already exist (same UUID/plan identity).\n\nHow should conflicts be handled?\n- Override conflicts: replace existing plans with incoming versions.\n- Skip conflicts: keep existing plans and only import missing ones.")
                :format(existing, total)
        )
    end
    if self.importPlanDialog and self.importPlanDialog:IsShown() then
        self.importPlanDialog:Hide()
    end
    if self.PrepareModal then
        self:PrepareModal(dialog, self.plannerFrame or self.frame)
    end
    dialog:Show()
end

function Raidstrats:TryImportPlanFromText(raw, opts)
    opts = opts or {}
    if not raw or raw:gsub("%s+", "") == "" then
        print("|cffff6666[Raidstrats.gg]|r Paste a plan export string (starts with !raidstrats-addon-).")
        return false
    end

    local importStrings = self.ExtractAddonImportStrings and self:ExtractAddonImportStrings(raw) or { raw }
    if type(importStrings) ~= "table" or #importStrings == 0 then
        print("|cffff6666[Raidstrats.gg]|r Could not find a valid import string in your paste.")
        return false
    end

    if #importStrings > 1 and not opts._confirmedMultiImport then
        self:ShowMultiImportConfirmDialog(raw, opts, #importStrings)
        return true
    end

    local importResult
    local importedCount = 0
    local failedCount = 0
    local skippedExistingCount = 0
    local skippedDuplicatePasteCount = 0
    local pendingConflict = false
    local existingMode = (opts._existingMode == "override" or opts._existingMode == "skip") and opts._existingMode or nil
    if #importStrings == 1 then
        importResult = self:ImportPlanFromPasteStringWithOpts(importStrings[1], opts)
        if importResult == true then
            importedCount = 1
        end
    else
        importResult = true
        local staged = {}
        local seenIncomingIdentity = {}

        -- Pre-check all pasted plans first so we only import missing UUIDs.
        for _, one in ipairs(importStrings) do
            local payload = self:DecodeAddonImportPayload(one)
            if not payload then
                failedCount = failedCount + 1
            elseif type(payload.plans) == "table" and #payload.plans > 0 then
                -- Group payloads keep their own flow.
                staged[#staged + 1] = { kind = "group", raw = one }
            else
                local data = self:NormalizeDecodedPlanPayload(payload)
                if not data then
                    failedCount = failedCount + 1
                else
                    if type(data.instanceKey) ~= "string" or data.instanceKey == "" then
                        local token = self:GetImportedPlanIdentityToken(data)
                        if token then
                            data.instanceKey = "plan:" .. token
                        end
                    end
                    self:EnsurePlanInstanceKey(data)

                    local identity = self:GetImportedPlanIdentityToken(data, { includeInstanceKey = false })
                    if not identity then
                        identity = "inst:" .. tostring(data.instanceKey or "")
                    end

                    if identity and seenIncomingIdentity[identity] then
                        skippedDuplicatePasteCount = skippedDuplicatePasteCount + 1
                    else
                        if identity then seenIncomingIdentity[identity] = true end
                        local existing = self:FindSavedPlanEntryByImportIdentity(data)
                        staged[#staged + 1] = { kind = "single", data = data, existing = existing }
                    end
                end
            end
        end

        if not existingMode then
            local existingConflictCount = 0
            for _, job in ipairs(staged) do
                if job.kind == "single" and job.existing then
                    existingConflictCount = existingConflictCount + 1
                end
            end
            if existingConflictCount > 0 then
                self:ShowExistingImportConflictDialog(raw, opts, existingConflictCount, #importStrings)
                return true
            end
            existingMode = "skip"
        end

        -- Execute only plans that are not already present.
        for _, job in ipairs(staged) do
            if job.kind == "single" then
                if job.existing then
                    if existingMode == "override" then
                        local existingKey = job.existing and job.existing.data and tostring(job.existing.data.instanceKey or "") or ""
                        if existingKey ~= "" then
                            job.data.instanceKey = existingKey
                        end
                        self.plannerData = job.data
                        local savedId = self:SaveImportedPlan(job.data)
                        if savedId then
                            importedCount = importedCount + 1
                        else
                            failedCount = failedCount + 1
                        end
                    else
                        skippedExistingCount = skippedExistingCount + 1
                    end
                else
                    self.plannerData = job.data
                    local savedId = self:SaveImportedPlan(job.data)
                    if savedId then
                        importedCount = importedCount + 1
                    else
                        failedCount = failedCount + 1
                    end
                end
            else
                local oneResult = self:ImportPlanFromPasteStringWithOpts(job.raw, { _existingMode = existingMode, _confirmedMultiImport = true })
                if oneResult == true then
                    importedCount = importedCount + 1
                elseif oneResult == "pending" then
                    pendingConflict = true
                    break
                else
                    failedCount = failedCount + 1
                end
            end
        end

        if pendingConflict then
            importResult = "pending"
        elseif importedCount == 0 and skippedExistingCount == 0 and skippedDuplicatePasteCount == 0 then
            importResult = false
        end
    end

    if not importResult then
        print("|cffff6666[Raidstrats.gg]|r Could not import plan. Check the string is complete and starts with !raidstrats-addon-.")
        return false
    end
    if importResult == "pending" then
        local pendingOpts = {
            clearPlanInput = opts.clearPlanInput,
            closeMainOnSuccess = opts.closeMainOnSuccess,
            openPlanner = opts.openPlanner,
            closeImportDialog = opts.closeImportDialog,
        }
        if self._pendingGroupedImport then
            self._pendingGroupedImportUiOpts = pendingOpts
        end
        if self._pendingSingleImport then
            self._pendingSingleImportUiOpts = pendingOpts
        end
        if importedCount > 0 and #importStrings > 1 then
            print(("|cff00aaff[Raidstrats.gg]|r Imported %d/%d plan(s). Resolve the conflict popup to continue."):format(importedCount, #importStrings))
        end
        return true
    end

    local addon = self
    local function finishImport()
        if opts.clearPlanInput and addon.planInputBox then
            addon.planInputBox:SetText("")
        end

        local mainWasOpen = addon.frame and addon.frame:IsShown()
        local plannerWasOpen = addon.plannerFrame and addon.plannerFrame:IsShown()

        -- Close the main window on a successful import (e.g. the Import Plan button).
        if opts.closeMainOnSuccess and addon.frame then
            addon.frame:Hide()
            mainWasOpen = false
        end

        if (opts.openPlanner or plannerWasOpen) and addon.ShowPlannerViewer then
            if plannerWasOpen then
                addon:ShowPlannerViewer({ reloadOnly = true })
            else
                addon:ShowPlannerViewer()
            end
        end

        if mainWasOpen and addon.frame then
            addon.frame:Show()
        end
        -- Only reposition when tiling with main or when freshly opening the planner.
        if mainWasOpen or (opts.openPlanner and not plannerWasOpen) then
            addon:LayoutOpenWindows()
        end

        if opts.closeImportDialog and addon.importPlanDialog then
            addon.importPlanDialog:Hide()
        end

        if #importStrings > 1 then
            print(("|cff00aaff[Raidstrats.gg]|r Imported %d/%d plan(s)."):format(importedCount, #importStrings))
            if skippedExistingCount > 0 then
                print(("|cffffff66[Raidstrats.gg]|r Skipped %d plan(s) already saved (same UUID/plan identity)."):format(skippedExistingCount))
            end
            if skippedDuplicatePasteCount > 0 then
                print(("|cffffff66[Raidstrats.gg]|r Skipped %d duplicate plan(s) inside the same paste."):format(skippedDuplicatePasteCount))
            end
            if failedCount > 0 then
                print(("|cffffff66[Raidstrats.gg]|r %d plan(s) could not be imported."):format(failedCount))
            end
        else
            print("|cff00aaff[Raidstrats.gg]|r Plan imported.")
        end
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0, finishImport)
    else
        finishImport()
    end
    return true
end

function Raidstrats:StartRosterScan()
    if self.isScanning then return end
    self.isScanning = true
    
    if self.stopBtn then 
        self.stopBtn:Show() 
    end
    
    self.includeSpecs = self.specCheckbox and self.specCheckbox.isChecked or false
    
    if self.outputBox then self.outputBox:SetText("") end

    self.inspectQueue = {}
    self.rosterData = {}
    
    local num = GetNumGroupMembers()
    local pre = IsInRaid() and "raid" or "party"
    local rawUnits = {}
    
    if num == 0 then 
        table.insert(rawUnits, "player") 
    else 
        for i=1, num do 
            table.insert(rawUnits, (pre=="party" and i==num) and "player" or pre..i) 
        end 
    end

    local seen = {}
    
    for _, u in ipairs(rawUnits) do
        local n, r = UnitName(u)
        if n then
            local fullName = (r and r~="") and n.."-"..r or n
            if not seen[fullName] then
                seen[fullName] = true
                local _, c = UnitClass(u)
                local isPlayer = UnitIsUnit(u, "player")
                
                local entry = {
                    unit = u,
                    name = n,
                    class = c or "Unknown",
                    spec = "UNKNOWN",
                    guid = UnitGUID(u),
                    isPlayer = isPlayer,
                    retries = 0 
                }
                
                if isPlayer then
                    local s = GetSpecialization()
                    local id = s and GetSpecializationInfo(s)
                    if id and SPEC_ID_MAP[id] then
                        entry.spec = SPEC_ID_MAP[id]
                    end
                    table.insert(self.rosterData, entry)
                else
                    if self.includeSpecs then
                        table.insert(self.inspectQueue, entry)
                    else
                        table.insert(self.rosterData, entry)
                    end
                end
            end
        end
    end
    
    if self.includeSpecs and #self.inspectQueue > 0 then
        self.totalToScan = #self.rosterData + #self.inspectQueue
        if self.genBtn and self.genBtn.SetLoadingState then
            self.genBtn:SetLoadingState(true, #self.rosterData, self.totalToScan)
        end
        self:ProcessNextInQueue()
    else
        self:FinishScan()
    end
end

function Raidstrats:ProcessNextInQueue()
    if not self.isScanning then return end 

    local done = #self.rosterData
    if self.genBtn and self.genBtn.SetLoadingState then
        self.genBtn:SetLoadingState(true, done, self.totalToScan)
    end

    if #self.inspectQueue == 0 then
        self:FinishScan()
        return
    end

    local entry = table.remove(self.inspectQueue, 1)
    self.currentUnit = entry.unit
    self.currentGUID = entry.guid
    self.currentEntry = entry

    if not UnitIsConnected(self.currentUnit) then
        table.insert(self.rosterData, self.currentEntry)
        self:ScheduleTimer("ProcessNextInQueue", 0.05)
        return
    end
    
    local id = GetInspectSpecialization(self.currentUnit)
    if id and id > 0 and SPEC_ID_MAP[id] then
        self.currentEntry.spec = SPEC_ID_MAP[id]
        table.insert(self.rosterData, self.currentEntry)
        self:ScheduleTimer("ProcessNextInQueue", 0.05)
        return
    end

    self:RegisterEvent("INSPECT_READY")
    NotifyInspect(self.currentUnit)
    
    self.scanTimer = self:ScheduleTimer("ScanTimeout", 1.5)
end

function Raidstrats:INSPECT_READY(event, guid)
    if guid == self.currentGUID then
        self:CancelTimer(self.scanTimer)
        self:UnregisterEvent("INSPECT_READY")
        
        local id = GetInspectSpecialization(self.currentUnit)
        if id and id > 0 and SPEC_ID_MAP[id] then
            self.currentEntry.spec = SPEC_ID_MAP[id]
            table.insert(self.rosterData, self.currentEntry)
            self:ScheduleTimer("ProcessNextInQueue", 0.1)
        else
            self:ScanTimeout()
        end
    end
end

function Raidstrats:ScanTimeout()
    if not self.isScanning then return end
    
    self:UnregisterEvent("INSPECT_READY")

    local id = GetInspectSpecialization(self.currentUnit)
    if id and id > 0 and SPEC_ID_MAP[id] then
        self.currentEntry.spec = SPEC_ID_MAP[id]
        table.insert(self.rosterData, self.currentEntry)
        self:ProcessNextInQueue()
    else
        --Retry
        self.currentEntry.retries = self.currentEntry.retries + 1
        table.insert(self.inspectQueue, 1, self.currentEntry)
        self:ProcessNextInQueue()
    end
end

function Raidstrats:StopScan()
    self.isScanning = false
    self:CancelAllTimers()
    self:UnregisterEvent("INSPECT_READY")
    
    if self.genBtn and self.genBtn.SetLoadingState then 
        self.genBtn:SetLoadingState(false)
    end
    
    if self.stopBtn then self.stopBtn:Hide() end
    if self.outputBox then self.outputBox:SetText("") end
end

function Raidstrats:FinishScan()
    self.isScanning = false
    if self.genBtn and self.genBtn.SetLoadingState then 
        self.genBtn:SetLoadingState(false) 
    end
    if self.stopBtn then self.stopBtn:Hide() end

    local parts = {}
    for _, d in ipairs(self.rosterData) do
        table.insert(parts, string.format('{"name":"%s","class":"%s","spec":"%s"}', d.name, d.class, d.spec))
    end
    local json = "[" .. table.concat(parts, ",") .. "]"
    
    if self.outputBox then
        self.outputBox:SetText(PREFIX_BRANDING..EncodeBase64(json))
        self.outputBox:HighlightText()
        self.outputBox:SetFocus()
    end
end

function Raidstrats:CreateMainWindow()
    if self.ShowRosterExportDialog then
        self:ShowRosterExportDialog()
        return
    end
end

function Raidstrats:UpdateSendButton()
    if not self.sendBtn then return end
    local allowed = self.IsPlanLeader and self:IsPlanLeader()
        or (not IsInRaid() or UnitIsGroupLeader("player"))
    if allowed then
        self.sendBtn:Enable()
    else
        self.sendBtn:Disable()
    end
end

function Raidstrats:ShowReceiverPopup(sender, url)
    if not self.pf then
        local f = CreateFrame("Frame", "RaidstratsPopup", UIParent, "BackdropTemplate")
        f:SetSize(440, 200)
        f:SetPoint("CENTER", 0, 80)
        f:SetMovable(true); f:EnableMouse(true)
        SetBackdrop(f)
        tinsert(UISpecialFrames, "RaidstratsPopup")
        f:SetScript("OnMouseDown", function(s, b) if b == "LeftButton" then s:StartMoving() end end)
        f:SetScript("OnMouseUp", function(s) s:StopMovingOrSizing() end)
        local c = CreateFrame("Button", nil, f, "UIPanelCloseButton"); c:SetPoint("TOPRIGHT", -5, -5)
        f.t = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.t:SetPoint("TOP", 0, -18)
        f.t:SetTextColor(0.9, 0.9, 0.9)
        local bc, b = CreateInput(f, "Web Link", false)
        bc:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -52)
        bc:SetPoint("TOPRIGHT", f, "TOPRIGHT", -20, -52)
        bc:SetHeight(44)
        b:SetScript("OnEscapePressed", function() f:Hide() end)
        f.eb = b
        local btn = CreateButton(f, "CLOSE")
        btn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 16)
        btn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
        btn:SetScript("OnClick", function() f:Hide() end)
        self.pf = f
    end
    self.pf.t:SetText(("|cff00aaff%s|r sent a plan:"):format(sender))
    self.pf.eb:SetText(url)
    self.pf.eb:HighlightText()
    self:PrepareModal(self.pf, self.frame)
    self.pf:Show()
end

function Raidstrats:PrintRsHelp()
    local function line(cmd, desc)
        print("|cff00aaff[Raidstrats.gg]|r |cff78a0ff" .. cmd .. "|r " .. desc)
    end
    print("|cff00aaff[Raidstrats.gg]|r Commands:")
    line("/rs", "- Open the raid planner")
    line("/rs plan", "- Open the raid planner")
    line("/rs import", "- Import a plan string or share link")
    line("/rs roster", "- Open the roster export window")
    line("/rs test [id] [phase]", "- Test NSRT plan cues locally (optional encounter id and phase)")
    line("/rs test stop", "- Stop an active local NSRT test run")
    line("/rsggphase <phase> [id]", "- Force a local phase callback simulation")
    line("/rs help", "- Show this list")
    print("|cff00aaff[Raidstrats.gg]|r Aliases: /rsplan, /rsimport, /raidstrats, /rsgg, /rsggtest")
end

function Raidstrats:HandleRsCommand(msg)
    msg = strtrim(msg or ""):lower()
    local cmd, rest = msg:match("^(%S+)%s*(.*)$")
    if not cmd or cmd == "" then
        if self.ShowPlannerViewer then
            self:ShowPlannerViewer()
        end
        return
    end
    rest = strtrim(rest or "")

    if cmd == "help" or cmd == "?" then
        self:PrintRsHelp()
        return
    end

    if cmd == "plan" or cmd == "planner" then
        if self.ShowPlannerViewer then
            self:ShowPlannerViewer()
        end
        return
    end

    if cmd == "import" then
        if self.ShowImportPlanDialog then
            self:ShowImportPlanDialog()
        end
        return
    end

    if cmd == "roster" or cmd == "export" then
        self:CreateMainWindow()
        return
    end

    if cmd == "test" then
        if self.RunRsggTest then
            rest = strtrim(rest or "")
            if rest:lower() == "stop" then
                if self.StopRsggTest then
                    self:StopRsggTest()
                else
                    print("|cffff6666[Raidstrats.gg]|r NSRT test stop is not available.")
                end
                return
            end
            local encID, phase = rest:match("^(%d+)%s+(%d+)$")
            if encID then
                encID = tonumber(encID)
                phase = tonumber(phase)
            else
                encID = tonumber(rest)
                phase = nil
            end
            self:RunRsggTest(encID, { phase = phase })
        else
            print("|cffff6666[Raidstrats.gg]|r NSRT integration is not available.")
        end
        return
    end

    if cmd == "debug" then
        if self.HandleRsggDebugCommand then
            self:HandleRsggDebugCommand(rest)
        else
            print("|cffff6666[Raidstrats.gg]|r Debug commands are not available.")
        end
        return
    end

    print("|cffff6666[Raidstrats.gg]|r Unknown /rs command. Type |cff78a0ff/rs help|r.")
end

function Raidstrats:OnInitialize()
    if math and math.randomseed then
        math.randomseed(time())
    end
    self:RegisterComm(COMM_PREFIX)
    self:RegisterComm(COMM_PLAN_PREFIX)
    self:RegisterChatCommand("rs", "HandleRsCommand")
    local openPlannerCmd = function()
        if self.ShowPlannerViewer then
            self:ShowPlannerViewer()
        end
    end
    self:RegisterChatCommand("raidstrats", openPlannerCmd)
    self:RegisterChatCommand("rsgg", openPlannerCmd)
    self:RegisterChatCommand("rsplan", function()
        if self.ShowPlannerViewer then
            self:ShowPlannerViewer()
        end
    end)
    self:RegisterChatCommand("rsimport", function()
        if self.ShowImportPlanDialog then
            self:ShowImportPlanDialog()
        end
    end)
    self:RegisterChatCommand("rsggdebug", function(msg)
        if self.HandleRsggDebugCommand then
            self:HandleRsggDebugCommand(msg)
        end
    end)
    self:RegisterChatCommand("rsggtour", function()
        if self.StartPlannerTourFromCommand then
            self:StartPlannerTourFromCommand()
        end
    end)

    self:SetupSharedPlanLinks()

    if self.InitNSRTIntegration then
        self:InitNSRTIntegration()
    end

    self:LoadLastSavedPlan()

    if self.InitMinimapButton then
        self:InitMinimapButton()
    end

    if self.EnsureGroupPlanViewAckTicker then
        self:EnsureGroupPlanViewAckTicker()
    end

    if self.InitVersionChecker then
        self:InitVersionChecker()
    end

    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:SetScript("OnEvent", function()
        if self.frame and self.frame:IsShown() then
            self:UpdateSendButton()
        end
        if self.UpdatePushUpdateButton then
            self:UpdatePushUpdateButton()
        end
        if self.OnGroupRosterChangedForRaidLeadView then
            self:OnGroupRosterChangedForRaidLeadView()
        end
    end)
end

function Raidstrats:OnCommReceived(p, m, d, s)
    if p == COMM_PREFIX and s ~= UnitName("player") then
        PlaySound(3190, "master")
        self:ShowReceiverPopup(s, m)
        return
    end

    if p ~= COMM_PLAN_PREFIX or s == UnitName("player") or type(m) ~= "string" then
        return
    end

    -- A clicker asked us for one of our shared plans: whisper them the payload.
    if m:sub(1, 4) == "REQ:" then
        local planName = m:sub(5)
        if not planName or planName == "" then return end
        local entry = self._sharedPlans and self._sharedPlans[planName]
        if not entry or not entry.payload or entry.payload == "" then return end
        if (time() - (entry.t or 0)) > SHARED_PLAN_TTL then
            self._sharedPlans[planName] = nil
            return
        end
        self:SendSharedPlanWhisper(s, planName, entry.payload)
        return
    end

    -- Group preload broadcast (cache only — import happens when they click the chat link).
    if m:sub(1, 5) == "BDAT:" then
        local rest = m:sub(6)
        local planName, iStr, nStr, chunk = rest:match("^([^:]+):(%d+):(%d+):(.*)$")
        local i, n = tonumber(iStr), tonumber(nStr)
        if planName and i and n and chunk ~= nil then
            self:HandleSharedPlanBroadcastChunk(s, planName, i, n, chunk)
        end
        return
    end

    -- Legacy single-message transfer (older addon versions).
    if m:sub(1, 5) == "PLAN:" then
        local payload = m:sub(6)
        if not payload or payload == "" then return end
        if self.ShowImportProgress then self:ShowImportProgress(true, 0, nil, "Importing shared plan...") end
        local ok = self:ImportPlanFromPasteString(PREFIX_PLANNER .. payload)
        if self.HideImportProgress then self:HideImportProgress() end
        if ok == true then
            self:OpenPlannerAfterShareImport()
            print(("|cff00aaff[Raidstrats.gg]|r Imported plan from %s!"):format(s or "Someone"))
        elseif ok == "pending" then
            -- Waiting on user conflict choice (override/skip).
        else
            print("|cffff6666[Raidstrats.gg]|r Received a shared plan but couldn't import it.")
        end
        return
    end

    if m:sub(1, 6) == "SHARE:" then
        local id, owner = m:sub(7):match("^([^:]+):(.+)$")
        if not id or not owner or owner == "" then return end
        local chan = (d == "RAID" or d == "PARTY" or d == "INSTANCE_CHAT") and d or nil
        if not chan then return end
        self._incomingPlan = { owner = owner, id = id, chunks = {}, total = nil, t = GetTime() }
        self:SendCommMessage(COMM_PLAN_PREFIX, ("REQG:%s:%s"):format(id, owner), chan)
        self.plannerData = { planName = "No plan", scenes = { { name = "Empty", items = {} } } }
        self:OpenPlannerAfterShareImport()
        if self.ShowImportProgress then self:ShowImportProgress(true, 0, nil, "Requesting plan...") end
        print("|cff00aaff[Raidstrats.gg]|r " .. s .. " shared a plan — requesting...")
        return
    end

    if m:sub(1, 5) == "REQG:" then
        local reqId, owner = m:sub(6):match("^([^:]+):(.+)$")
        if not reqId or reqId == "" or not s or s == UnitName("player") then return end
        local entry = self._sharedPlans and self._sharedPlans[reqId]
        if not entry or not entry.payload or entry.payload == "" then return end
        if (time() - (entry.t or 0)) > SHARED_PLAN_TTL then
            self._sharedPlans[reqId] = nil
            return
        end
        self:SendSharedPlanWhisper(s, reqId, entry.payload)
        return
    end

    if m:sub(1, 5) == "DATA:" then
        local rest = m:sub(6)
        local reqId, iStr, nStr, chunk = rest:match("^([^:]+):(%d+):(%d+):(.*)$")
        local incoming = self._incomingPlan
        if not reqId or not incoming or incoming.id ~= reqId or not iStr or not nStr or not chunk then return end
        local i, n = tonumber(iStr), tonumber(nStr)
        if not i or not n then return end
        incoming.total = incoming.total or n
        incoming.chunks[i] = chunk
        incoming.t = GetTime()
        local count = 0
        for idx = 1, incoming.total do if incoming.chunks[idx] then count = count + 1 end end
        if self.UpdateImportProgress then self:UpdateImportProgress(count, incoming.total) end
        for idx = 1, incoming.total do
            if not incoming.chunks[idx] then return end
        end
        local b64 = table.concat(incoming.chunks, "")
        self._incomingPlan = nil
        if self.HideImportProgress then self:HideImportProgress() end
        local ok = self:ImportPlanFromPasteString(PREFIX_PLANNER .. b64)
        if ok == true then
            self:OpenPlannerAfterShareImport()
            print("|cff00aaff[Raidstrats.gg]|r Plan imported!")
        elseif ok == "pending" then
            -- Waiting on user conflict choice (override/skip).
        else
            print("|cffff6666[Raidstrats.gg]|r Received a shared plan but couldn't import it.")
        end
        return
    end

    -- Shared plan group bundle (multiple plans in one transfer / group preload).
    if m:sub(1, 4) == "GSHR" or m:sub(1, 4) == "GDAT" or m:sub(1, 4) == "GREQ" or m:sub(1, 4) == "GBDT" then
        if self.HandleSharedPlanGroupComm then
            self:HandleSharedPlanGroupComm(m, s)
        end
        return
    end

    -- Group addon version check (party / raid / instance).
    if m:sub(1, 8) == "RSGGVER:" then
        if self.HandleAddonVersionComm then
            self:HandleAddonVersionComm(s, m:sub(9))
        end
        return
    end

    -- Group NSRT test broadcast (/rsggtest, /rs test).
    if m:sub(1, 9) == "RSGGTEST:" then
        -- /rsggtest is local-only; ignore remote test triggers.
        return
    end

    -- Raid leader pushed a plan update (same plan identity, in-place merge on accept).
    if m:sub(1, 4) == "PUSH" then
        if self.HandlePlanUpdatePush then self:HandlePlanUpdatePush(m, s, d) end
        return
    end

    if m:sub(1, 4) == "UPDD" then
        if self.HandlePlanUpdateChunk then self:HandlePlanUpdateChunk(m, s, d) end
        return
    end

    -- Raid leader renamed an actor across the plan (all scenes).
    if m:sub(1, 3) == "LBA" then
        if self.ApplyActorLabelSyncFromComm then
            self:ApplyActorLabelSyncFromComm(m, s)
        end
        return
    end

    -- Raid leader renamed a single empty-slot label on the open plan.
    if m:sub(1, 3) == "LBL" then
        if self.ApplyLabelSyncFromComm then
            self:ApplyLabelSyncFromComm(m, s)
        end
        return
    end

    -- Raid leader moved a marker on the open plan.
    if m:sub(1, 3) == "POS" then
        if self.ApplyPositionSyncFromComm then
            self:ApplyPositionSyncFromComm(m, s)
        end
        return
    end

    -- Plan view presence (raid lead attendance panel).
    if m:sub(1, 4) == "VIEW" then
        if self.HandlePlanViewComm then self:HandlePlanViewComm(m, s) end
        return
    end
    if m:sub(1, 4) == "PRRQ" then
        if self.HandlePlanViewPoll then self:HandlePlanViewPoll(m, s) end
        return
    end
    if m:sub(1, 4) == "RNOT" then
        if self.HandleRaidCheckNotifComm then self:HandleRaidCheckNotifComm(m, s) end
        return
    end
    if m:sub(1, 4) == "RNGB" then
        if self.HandleRaidCheckNoteBundleComm then self:HandleRaidCheckNoteBundleComm(m, s) end
        return
    end
    if m:sub(1, 4) == "RCMI" then
        if self.HandleRaidCheckMissingPlansComm then self:HandleRaidCheckMissingPlansComm(m, s) end
        return
    end
    if m:sub(1, 4) == "RASC" then
        if self.HandleRaidCheckAutoSwitchComm then self:HandleRaidCheckAutoSwitchComm(m, s) end
        return
    end
    if m:sub(1, 4) == "RSSC" then
        if self.HandleRaidCheckSceneSwitchComm then self:HandleRaidCheckSceneSwitchComm(m, s) end
        return
    end
    if m:sub(1, 4) == "RASR" then
        if self.HandleRaidCheckAutoSwitchResponseComm then self:HandleRaidCheckAutoSwitchResponseComm(m, s) end
        return
    end
end

-- Expose for planner module (do not wrap methods here — that overwrites them and causes infinite recursion)
Raidstrats.SetBackdrop = SetBackdrop
Raidstrats.CreateButton = CreateButton
Raidstrats.CreateInput = CreateInput
Raidstrats.SkinScrollBar = SkinScrollBar
Raidstrats.CreateAnimatedCheckbox = CreateAnimatedCheckbox