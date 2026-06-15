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
    return true
end

function Raidstrats:SaveImportedPlan(data)
    if not data then return end
    self:EnsurePlanInstanceKey(data)
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
                entry.data.savedEntryId = entry.id
                if type(data.planName) == "string" and data.planName ~= "" then
                    entry.planName = data.planName
                end
                entry.expansion = data.expansion or "Other"
                entry.raid = data.raid or "Other"
                entry.boss = data.boss or "Unknown"
                if self.SanitizePlanData then self:SanitizePlanData(entry.data) end
                data.savedEntryId = entry.id
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
    entry.data.savedEntryId = entry.id
    if self.SanitizePlanData then self:SanitizePlanData(entry.data) end
    RaidstratsggSavedPlans.nextId = RaidstratsggSavedPlans.nextId + 1
    table.insert(RaidstratsggSavedPlans.list, entry)
    data.savedEntryId = entry.id
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

function Raidstrats:ImportPlanFromPasteString(raw)
    local data = self:DecodePlanFromBase64(raw)
    if not data then return false end
    -- Website / fresh paste: new key. Team share payload already includes instanceKey.
    self:EnsurePlanInstanceKey(data)
    self.plannerData = data
    self:SaveImportedPlan(data)
    return true
end

local function CoerceNumber(v)
    local n = tonumber(v)
    if not n then return nil end
    return n
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

function Raidstrats:DecodePlanFromBase64(raw)
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
    local data = DecodeJSON(json)
    if not data or SceneCount(data.scenes) == 0 then return nil end
    EnsureImportedBossPortraitFallback(data)
    if self.SanitizePlanData then self:SanitizePlanData(data) end
    return data
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
function Raidstrats:BuildSharePayload(data)
    data = self:PreparePlanDataForShare(data)
    if not data then return nil end
    local json = EncodeJSON(data)
    if not json or json == "" then return nil end
    local body = json
    local LibDeflate = LibStub("LibDeflate", true)
    if LibDeflate and LibDeflate.CompressDeflate then
        local ok, compressed = pcall(function() return LibDeflate:CompressDeflate(json, { level = 9 }) end)
        if ok and compressed and (#compressed + 1) < #json then
            body = string.char(0x01) .. compressed
        end
    end
    return EncodeBase64(body)
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

-- Share the current plan to chat, WeakAuras-style: post a plain-text token that each
-- addon user's chat filter renders as a clickable link. The plan itself is NOT sent now;
-- it is only transferred (on request) when someone clicks the link. No auto-import.
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

    if self:IsGuildOnlyShareChannel() and not opts.confirmedGuild then
        EnsureShareToGuildPopup()
        local planName = SanitizeShareName((type(data.planName) == "string" and data.planName ~= "") and data.planName or "Raid plan")
        StaticPopup_Show("RAIDSTRATSGG_SHARE_TO_GUILD", planName, nil, data)
        return false
    end

    local chan = self:GetGroupChatChannel()
    if not chan then
        print("|cffff6666[Raidstrats.gg]|r Join a party, raid, or guild to share a plan.")
        return false
    end

    local payload = self:BuildSharePayload(data)
    if not payload or payload == "" then
        print("|cffff6666[Raidstrats.gg]|r Couldn't prepare the plan for sharing.")
        return false
    end

    local planName = SanitizeShareName((type(data.planName) == "string" and data.planName ~= "") and data.planName or "Raid plan")

    -- Cache the payload so we can answer requests from clickers.
    self._sharedPlans = self._sharedPlans or {}
    self._sharedPlans[planName] = { payload = payload, t = time() }

    -- Post the plain-text token; clients with the addon turn it into a clickable link.
    SendChatMessage(("[Raidstrats: %s]"):format(planName), chan)

    print(("|cff00aaff[Raidstrats.gg]|r Shared \"%s\" to %s. Others click the link to import."):format(planName, ChannelLabel(chan)))
    return true
end

-- ----------------------------------------------------------------------------
-- Clickable share links (WeakAuras-style).
-- Blizzard strips custom hyperlinks from player chat, so we send a plain-text
-- token and rebuild the clickable link locally via a chat message filter. The
-- link encodes the sender + plan name; clicking it requests the plan over comms.
-- ----------------------------------------------------------------------------

-- Send the requester their requested plan, or import our own when we clicked our own link.
function Raidstrats:RequestSharedPlan(sender, planName)
    if not sender or not planName then return end

    local me = UnitName("player")
    local entry = self._sharedPlans and self._sharedPlans[planName]
    if entry and entry.payload and (sender == me or (Ambiguate and Ambiguate(sender, "short") == me)) then
        local ok = self:ImportPlanFromPasteString(PREFIX_PLANNER .. entry.payload)
        if ok then
            self:OpenPlannerAfterShareImport()
        else
            print("|cffff6666[Raidstrats.gg]|r Couldn't import the cached plan.")
        end
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
        "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
        "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
        "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
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

function Raidstrats:TryImportPlanFromText(raw, opts)
    opts = opts or {}
    if not raw or raw:gsub("%s+", "") == "" then
        print("|cffff6666[Raidstrats.gg]|r Paste a plan export string (starts with !raidstrats-addon-).")
        return false
    end
    if not self:ImportPlanFromPasteString(raw) then
        print("|cffff6666[Raidstrats.gg]|r Could not import plan. Check the string is complete and starts with !raidstrats-addon-.")
        return false
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

        print("|cff00aaff[Raidstrats.gg]|r Plan imported.")
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
        if self.genBtn then
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
    if self.genBtn then
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
    
    if self.genBtn then 
        self.genBtn:SetLoadingState(false)
    end
    
    if self.stopBtn then self.stopBtn:Hide() end
    if self.outputBox then self.outputBox:SetText("") end
end

function Raidstrats:FinishScan()
    self.isScanning = false
    if self.genBtn then 
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
    if self.frame then
        if not self.planInputBox then
            self.frame:Hide()
            self.frame = nil
        else
            self:UpdateSendButton()
            self.frame:Show()
            self:LayoutOpenWindows()
            return
        end
    end

    local f = CreateFrame("Frame", "RaidstratsFrame", UIParent, "BackdropTemplate")
    f:SetSize(500, 600)
    f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true)
    SetBackdrop(f); tinsert(UISpecialFrames, "RaidstratsFrame")
    
    f:SetScript("OnMouseDown", function(s,b) if b=="LeftButton" then s:StartMoving() end end)
    f:SetScript("OnMouseUp", function(s) s:StopMovingOrSizing() end)
    f:SetScript("OnShow", function()
        self:UpdateSendButton()
        self:LayoutOpenWindows()
    end)
    
    local c = CreateFrame("Button", nil, f, "UIPanelCloseButton"); c:SetPoint("TOPRIGHT", -5, -5)
    
    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(523*0.36, 52*0.36) 
    logo:SetPoint("TOPLEFT", 20, -16)
    logo:SetTexture("Interface\\AddOns\\Raidstratsgg\\title.tga") 

    local ec, eb = CreateInput(f, "Roster String", true)
    ec:SetPoint("TOP", 0, -76)
    ec:SetPoint("LEFT", f, "LEFT", 20, 0)
    ec:SetPoint("RIGHT", f, "RIGHT", -20, 0)
    ec:SetHeight(100)
    if ec.SyncEditWidth then ec:SyncEditWidth() end
    self.outputBox = eb

    local cb = CreateAnimatedCheckbox(f, "Include spec (slower)")
    cb:SetPoint("TOPLEFT", ec, "BOTTOMLEFT", 0, -12)
    self.specCheckbox = cb

    local bGen = CreateLoaderButton(f, "GENERATE ROSTER")
    bGen:SetPoint("TOP", cb, "BOTTOM", 0, -14)
    bGen:SetPoint("LEFT", 20, 0); bGen:SetPoint("RIGHT", -20, 0)
    bGen:SetScript("OnMouseDown", function(s, button) 
        if button == "LeftButton" and not self.isScanning then
            self:StartRosterScan() 
        end
    end)
    self.genBtn = bGen

    local bStop = CreateStopButton(f)
    bStop:SetPoint("RIGHT", bGen, "RIGHT", 0, 0)
    bStop:SetFrameLevel(bGen:GetFrameLevel() + 10)
    
    bStop:SetScript("OnClick", function() self:StopScan() end)
    bStop:Hide()
    self.stopBtn = bStop

    local div = f:CreateTexture(nil, "ARTWORK"); div:SetHeight(1); div:SetColorTexture(0.2,0.2,0.2,1)
    div:SetPoint("LEFT",20,0); div:SetPoint("RIGHT",-20,0); div:SetPoint("TOP", bGen, "BOTTOM", 0, -18)

    local lc, lb = CreateInput(f, "Web Link", false)
    lc:SetPoint("TOP", div, "BOTTOM", 0, -26)
    lc:SetPoint("LEFT", f, "LEFT", 20, 0)
    lc:SetPoint("RIGHT", f, "RIGHT", -20, 0)
    lc:SetHeight(38)
    
    local bSend = CreateButton(f, "BROADCAST TO GROUP")
    bSend:SetPoint("TOP", lc, "BOTTOM", 0, -12); bSend:SetPoint("LEFT", 20, 0); bSend:SetPoint("RIGHT", -20, 0)
    bSend:SetScript("OnClick", function()
        local allowed = self.IsPlanLeader and self:IsPlanLeader()
            or (not IsInRaid() or UnitIsGroupLeader("player"))
        if not allowed then return end
        local u, ch = lb:GetText(), IsInRaid() and "RAID" or "PARTY"
        if u and u~="" then self:SendCommMessage(COMM_PREFIX, u, ch); print("|cff00aaff[Raidstrats.gg]|r Sent to "..ch) end
    end)
    self.sendBtn = bSend

    local div2 = f:CreateTexture(nil, "ARTWORK")
    div2:SetHeight(1)
    div2:SetColorTexture(0.2, 0.2, 0.2, 1)
    div2:SetPoint("LEFT", 20, 0)
    div2:SetPoint("RIGHT", -20, 0)
    div2:SetPoint("TOP", bSend, "BOTTOM", 0, -18)

    local pc, pb = CreateInput(f, "Plan String", true)
    pc:SetPoint("TOP", div2, "BOTTOM", 0, -26)
    pc:SetPoint("LEFT", f, "LEFT", 20, 0)
    pc:SetPoint("RIGHT", f, "RIGHT", -20, 0)
    pc:SetHeight(85)
    if pc.SyncEditWidth then pc:SyncEditWidth() end
    pb:SetFontObject("GameFontHighlightSmall")
    self.planInputBox = pb

    local planBtnRow = CreateFrame("Frame", nil, f)
    planBtnRow:SetHeight(40)
    planBtnRow:SetPoint("TOPLEFT", pc, "BOTTOMLEFT", 0, -12)
    planBtnRow:SetPoint("TOPRIGHT", pc, "BOTTOMRIGHT", 0, -12)

    local bImportPlan = CreateButton(planBtnRow, "IMPORT PLAN")
    bImportPlan:SetPoint("LEFT", planBtnRow, "LEFT", 0, 0)
    bImportPlan:SetPoint("RIGHT", planBtnRow, "CENTER", -6, 0)
    bImportPlan:SetScript("OnClick", function()
        if self.planInputBox then
            self:TryImportPlanFromText(self.planInputBox:GetText(), {
                openPlanner = true,
                clearPlanInput = true,
                closeMainOnSuccess = true,
            })
        end
    end)

    local bOpenPlanner = CreateButton(planBtnRow, "OPEN PLANNER")
    bOpenPlanner:SetPoint("LEFT", planBtnRow, "CENTER", 6, 0)
    bOpenPlanner:SetPoint("RIGHT", planBtnRow, "RIGHT", 0, 0)
    bOpenPlanner:SetScript("OnClick", function()
        if self.frame then self.frame:Hide() end
        if self.ShowPlannerViewer then
            self:ShowPlannerViewer({ layoutWindows = true })
        end
    end)

    self.frame = f
    self:UpdateSendButton()
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
    line("/rs test [id] [phase]", "- Test NSRT plan cues (broadcasts to group; optional encounter id and phase)")
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
            local encID, phase = rest:match("^(%d+)%s+(%d+)$")
            encID = encID and tonumber(encID) or tonumber(rest)
            phase = phase and tonumber(phase) or 1
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

    -- Legacy single-message transfer (older addon versions).
    if m:sub(1, 5) == "PLAN:" then
        local payload = m:sub(6)
        if not payload or payload == "" then return end
        if self.ShowImportProgress then self:ShowImportProgress(true, 0, nil, "Importing shared plan...") end
        local ok = self:ImportPlanFromPasteString(PREFIX_PLANNER .. payload)
        if self.HideImportProgress then self:HideImportProgress() end
        if ok then
            self:OpenPlannerAfterShareImport()
            print(("|cff00aaff[Raidstrats.gg]|r Imported plan from %s!"):format(s or "Someone"))
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
        if ok then
            self:OpenPlannerAfterShareImport()
            print("|cff00aaff[Raidstrats.gg]|r Plan imported!")
        else
            print("|cffff6666[Raidstrats.gg]|r Received a shared plan but couldn't import it.")
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
        local encID, phase = m:match("^RSGGTEST:(%d+):(%d+)$")
        if encID and self.RunRsggTest then
            self:RunRsggTest(tonumber(encID), {
                phase = tonumber(phase) or 1,
                fromRemote = true,
                sender = s,
            })
        end
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