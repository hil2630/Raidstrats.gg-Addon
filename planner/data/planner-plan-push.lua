-- Raid leader: push in-place plan updates to group members on the same plan identity.
local addonName = ...
local AceAddon = LibStub("AceAddon-3.0")
local Addon =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)
if not Addon then return end
local Diar = Addon
local function L(key) return RSGG_L(key) end

local SEP = string.char(31)
local PLAN_UPDATE_TTL = 300
local PLAN_UPDATE_BATCH = 180
local UI = {
    PANEL   = {0.06, 0.06, 0.09, 0.96},
    BORDER  = {0.22, 0.24, 0.28, 1},
    ROW     = {0.09, 0.10, 0.13, 0.92},
    ROW_HOV = {0.14, 0.16, 0.20, 1},
    ACCENT  = {0.23, 0.51, 0.96, 1},
}
local SetBackdrop = Diar.SetBackdrop

local function CopyPlanData(val)
    if type(val) == "table" then
        local out = {}
        for k, v in pairs(val) do out[k] = CopyPlanData(v) end
        return out
    end
    return val
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

local function CheckboxIsChecked(chk)
    if not chk then return false end
    if chk.GetChecked then return chk:GetChecked() and true or false end
    if chk.isChecked ~= nil then return chk.isChecked and true or false end
    return false
end

local function SenderLabel(sender)
    if not sender or sender == "" then return L("Someone") end
    return Ambiguate and Ambiguate(sender, "short") or sender
end

-- Debug logging for plan-push/delta troubleshooting. Disabled by default; flip
-- PUSH_DEBUG to true to re-enable the verbose chat output during development.
local PUSH_DEBUG = false
local function PushDebug(msg)
    if not PUSH_DEBUG then return end
    print(("|cff66ccff[Raidstrats.gg Debug]|r %s"):format(tostring(msg or "")))
end

-- EncodeBase64/DecodeBase64 are file-local in main.lua, so we keep matching copies here.
local PUSH_B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function EncodeBase64Local(s)
    if not s then return "" end
    local t, r, b, out = {}, 0, 0, ""
    for i = 1, #PUSH_B64 do t[i - 1] = string.sub(PUSH_B64, i, i) end
    for i = 1, #s do
        b = bit.bor(bit.lshift(b, 8), string.byte(s, i))
        r = r + 8
        while r >= 6 do out = out .. t[bit.band(bit.rshift(b, r - 6), 0x3F)]; r = r - 6 end
    end
    if r > 0 then out = out .. t[bit.band(bit.lshift(b, 6 - r), 0x3F)] .. (r == 2 and "==" or "=") end
    return out
end

local function DecodeBase64Local(s)
    if not s or s == "" then return nil end
    s = s:gsub("%s+", "")
    local t = {}
    for i = 1, #PUSH_B64 do t[string.sub(PUSH_B64, i, i)] = i - 1 end
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

local function EncodeJson(value)
    if C_EncodingUtil and C_EncodingUtil.SerializeJSON then
        local ok, json = pcall(C_EncodingUtil.SerializeJSON, value, { ignoreSerializationErrors = true })
        if ok and type(json) == "string" and json ~= "" then
            return json
        end
    end
    if value == nil then return "null" end
    local valueType = type(value)
    if valueType == "boolean" then return value and "true" or "false" end
    if valueType == "number" then return tostring(value) end
    if valueType == "string" then
        local escaped = value:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
        return '"' .. escaped .. '"'
    end
    if valueType == "table" then
        local isArray, n = true, 0
        for k in pairs(value) do
            n = n + 1
            if type(k) ~= "number" or k ~= n then
                isArray = false
                break
            end
        end
        if isArray and n > 0 then
            for i = 1, n do
                if value[i] == nil then
                    isArray = false
                    break
                end
            end
        end
        if isArray then
            local parts = {}
            for i = 1, #value do
                parts[i] = EncodeJson(value[i])
            end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local parts = {}
        for k, v in pairs(value) do
            if type(k) == "string" then
                local ok, encoded = pcall(EncodeJson, v)
                parts[#parts + 1] = EncodeJson(k) .. ":" .. (ok and encoded or "null")
            end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end

local function DecodeJson(text)
    if not text or text == "" then return nil end
    if C_EncodingUtil and C_EncodingUtil.DeserializeJSON then
        local ok, parsed = pcall(C_EncodingUtil.DeserializeJSON, text)
        if ok and type(parsed) == "table" then
            return parsed
        end
    end
    local pos = 1
    local function peek()
        return text:sub(pos, pos)
    end
    local function consume(ch)
        if peek() ~= ch then return false end
        pos = pos + 1
        return true
    end
    local function skipWs()
        local _, i = text:find("^%s*", pos)
        pos = i + 1
    end
    local parseValue
    local function parseString()
        if not consume('"') then return nil end
        local out = {}
        while pos <= #text do
            local ch = text:sub(pos, pos)
            if ch == '"' then
                pos = pos + 1
                return table.concat(out)
            end
            if ch == "\\" then
                local esc = text:sub(pos + 1, pos + 1)
                if esc == "n" then out[#out + 1] = "\n"
                elseif esc == "r" then out[#out + 1] = "\r"
                elseif esc == "t" then out[#out + 1] = "\t"
                elseif esc == '"' or esc == "\\" or esc == "/" then out[#out + 1] = esc
                elseif esc == "u" then
                    local hex = text:sub(pos + 2, pos + 5)
                    local code = tonumber(hex, 16)
                    if code then out[#out + 1] = utf8 and utf8.char(code) or string.char(code) end
                    pos = pos + 4
                else
                    out[#out + 1] = esc
                end
                pos = pos + 2
            else
                out[#out + 1] = ch
                pos = pos + 1
            end
        end
        return nil
    end
    local function parseNumber()
        local startPos, endPos = text:find("^%-?%d+%.?%d*([eE][%+%-]?%d+)?", pos)
        if not startPos then return nil end
        local num = text:sub(startPos, endPos)
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
        if ch == "t" and text:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        end
        if ch == "f" and text:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        end
        if ch == "n" and text:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        end
        return parseNumber()
    end
    local result = parseValue()
    skipWs()
    if pos <= #text then return nil end
    return result
end

local function TableDeepEqual(a, b)
    if a == b then return true end
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return false end
    for k, va in pairs(a) do
        if not TableDeepEqual(va, b[k]) then
            return false
        end
    end
    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end

-- Top-level plan fields that are transient/runtime and must NOT count as "metadata
-- changes" when deciding whether a delta is possible. If any of these leak into one
-- snapshot but not the other, every delta path would bail to a full push.
local function IsVolatilePlanMetaKey(k)
    if type(k) ~= "string" then return false end
    if k:sub(1, 2) == "__" then return true end
    return k == "scenes"
        or k == "savedEntryId"
        or k == "syncVersion"
        or k == "widget"
end

local function CopyPlanWithoutScenes(data)
    local copy = {}
    if type(data) ~= "table" then return copy end
    for k, v in pairs(data) do
        if not IsVolatilePlanMetaKey(k) then
            copy[k] = CopyPlanData(v)
        end
    end
    return copy
end

-- Diagnostic: returns the first top-level key whose (non-volatile) value differs
-- between two plan snapshots, so a full-push fallback can explain itself.
local function FirstPlanMetaDiffKey(baseData, newData)
    if type(baseData) ~= "table" or type(newData) ~= "table" then return "<invalid>" end
    local seen = {}
    for k, v in pairs(baseData) do
        if not IsVolatilePlanMetaKey(k) then
            seen[k] = true
            if not TableDeepEqual(v, newData[k]) then return k end
        end
    end
    for k, v in pairs(newData) do
        if not IsVolatilePlanMetaKey(k) and not seen[k] then
            if not TableDeepEqual(v, baseData[k]) then return k end
        end
    end
    return nil
end

local function FindSingleChangedSceneIndex(baseData, newData)
    if type(baseData) ~= "table" or type(newData) ~= "table" then return nil, "invalid data" end
    local baseScenes = type(baseData.scenes) == "table" and baseData.scenes or nil
    local newScenes = type(newData.scenes) == "table" and newData.scenes or nil
    if not baseScenes or not newScenes then return nil, "missing scenes" end
    if #baseScenes ~= #newScenes then return nil, "scene count changed" end
    if not TableDeepEqual(CopyPlanWithoutScenes(baseData), CopyPlanWithoutScenes(newData)) then
        return nil, "non-scene plan metadata changed"
    end
    local changed = nil
    for i = 1, #newScenes do
        if not TableDeepEqual(baseScenes[i], newScenes[i]) then
            if changed ~= nil then
                return nil, "multiple scenes changed"
            end
            changed = i
        end
    end
    if not changed then
        return nil, "no scene delta detected"
    end
    return changed, nil
end

local function CopyWithoutPositionFields(item)
    if type(item) ~= "table" then return item end
    local out = {}
    for k, v in pairs(item) do
        local isRuntimeField = (type(k) == "string" and (k == "widget" or k:sub(1, 2) == "__"))
        if not isRuntimeField
            and k ~= "x"
            and k ~= "y"
            and k ~= "currentX"
            and k ~= "currentY"
            and k ~= "corners"
        then
            out[k] = CopyPlanData(v)
        end
    end
    return out
end

local function BuildObjectMoveDelta(baseData, newData)
    if type(baseData) ~= "table" or type(newData) ~= "table" then return nil, "invalid data" end
    local baseScenes = type(baseData.scenes) == "table" and baseData.scenes or nil
    local newScenes = type(newData.scenes) == "table" and newData.scenes or nil
    if not baseScenes or not newScenes or #baseScenes ~= #newScenes then return nil, "scene count changed" end
    if not TableDeepEqual(CopyPlanWithoutScenes(baseData), CopyPlanWithoutScenes(newData)) then
        return nil, "non-scene plan metadata changed"
    end

    local moves = {}
    for sceneIndex = 1, #newScenes do
        local oldScene = baseScenes[sceneIndex]
        local newScene = newScenes[sceneIndex]
        if type(oldScene) ~= "table" or type(newScene) ~= "table" then return nil, "invalid scene table" end
        local oldItems = type(oldScene.items) == "table" and oldScene.items or {}
        local newItems = type(newScene.items) == "table" and newScene.items or {}
        if #oldItems ~= #newItems then return nil, ("item count changed in scene %d"):format(sceneIndex) end

        local oldById = {}
        for oldIdx, oldItem in ipairs(oldItems) do
            local id = strtrim(tostring(oldItem and oldItem.id or ""))
            if id == "" then
                id = ("__idx__%d"):format(oldIdx)
            end
            if oldById[id] then return nil, ("duplicate item id in old scene %d"):format(sceneIndex) end
            oldById[id] = { item = oldItem, index = oldIdx }
        end

        for newIdx, newItem in ipairs(newItems) do
            local id = strtrim(tostring(newItem and newItem.id or ""))
            if id == "" then
                id = ("__idx__%d"):format(newIdx)
            end
            local oldEntry = oldById[id]
            if not oldEntry then return nil, ("item id mismatch in scene %d"):format(sceneIndex) end
            local oldItem = oldEntry.item

            if not TableDeepEqual(CopyWithoutPositionFields(oldItem), CopyWithoutPositionFields(newItem)) then
                return nil, ("non-position change on item %s in scene %d"):format(id, sceneIndex)
            end

            local oldX = tonumber(oldItem and oldItem.x) or 0
            local oldY = tonumber(oldItem and oldItem.y) or 0
            local newX = tonumber(newItem and newItem.x) or oldX
            local newY = tonumber(newItem and newItem.y) or oldY
            if math.abs(newX - oldX) > 0.0001 or math.abs(newY - oldY) > 0.0001 then
                moves[#moves + 1] = {
                    sceneIndex = sceneIndex,
                    itemId = id,
                    itemIndex = newIdx,
                    x = newX,
                    y = newY,
                }
            end
        end
    end

    if #moves == 0 then return nil, "no position changes detected" end
    return moves, nil
end

local function EncodeSceneDeltaPayload(scene)
    if type(scene) ~= "table" then return nil end
    local json = EncodeJson(scene)
    if not json or json == "" then return nil end
    local body = json
    local LibDeflate = LibStub("LibDeflate", true)
    if LibDeflate and LibDeflate.CompressDeflate then
        local ok, compressed = pcall(function() return LibDeflate:CompressDeflate(json, { level = 6 }) end)
        if ok and compressed and (#compressed + 1) < #json then
            body = string.char(0x01) .. compressed
        end
    end
    return EncodeBase64Local(body)
end

local function DecodeSceneDeltaPayload(payloadB64)
    if type(payloadB64) ~= "string" or payloadB64 == "" then return nil end
    local decoded = DecodeBase64Local(payloadB64)
    if not decoded or decoded == "" then return nil end
    local json = decoded
    if decoded:byte(1) == 0x01 then
        local LibDeflate = LibStub("LibDeflate", true)
        if not LibDeflate or not LibDeflate.DecompressDeflate then return nil end
        local inflated = LibDeflate:DecompressDeflate(decoded:sub(2))
        if not inflated or inflated == "" then return nil end
        json = inflated
    end
    return DecodeJson(json)
end

local function EncodeObjectMoveDeltaPayload(moves)
    if type(moves) ~= "table" or #moves == 0 then return nil end
    local json = EncodeJson({ moves = moves })
    if not json or json == "" then return nil end
    local body = json
    local LibDeflate = LibStub("LibDeflate", true)
    if LibDeflate and LibDeflate.CompressDeflate then
        local ok, compressed = pcall(function() return LibDeflate:CompressDeflate(json, { level = 6 }) end)
        if ok and compressed and (#compressed + 1) < #json then
            body = string.char(0x01) .. compressed
        end
    end
    return EncodeBase64Local(body)
end

local function DecodeObjectMoveDeltaPayload(payloadB64)
    if type(payloadB64) ~= "string" or payloadB64 == "" then return nil end
    local decoded = DecodeBase64Local(payloadB64)
    if not decoded or decoded == "" then return nil end
    local json = decoded
    if decoded:byte(1) == 0x01 then
        local LibDeflate = LibStub("LibDeflate", true)
        if not LibDeflate or not LibDeflate.DecompressDeflate then return nil end
        local inflated = LibDeflate:DecompressDeflate(decoded:sub(2))
        if not inflated or inflated == "" then return nil end
        json = inflated
    end
    local packet = DecodeJson(json)
    local moves = packet and packet.moves
    if type(moves) ~= "table" or #moves == 0 then return nil end
    return moves
end

local function StableItemId(item)
    if type(item) ~= "table" then return nil end
    local id = strtrim(tostring(item.id or ""))
    if id == "" then return nil end
    return id
end

local function SceneWithoutItems(scene)
    local out = {}
    if type(scene) ~= "table" then return out end
    for k, v in pairs(scene) do
        if k ~= "items" then out[k] = CopyPlanData(v) end
    end
    return out
end

-- Item-level delta. For scenes whose only change is their item list, send just the
-- added items, removed item ids, and edited item bodies -- not the whole scene.
-- The receiver applies these ON TOP of its existing items (see ApplyPlanItemUpdate),
-- so a partial/garbled payload can at worst miss an add, never wipe the scene.
local function BuildItemDelta(baseData, newData)
    if type(baseData) ~= "table" or type(newData) ~= "table" then return nil, "invalid data" end
    local baseScenes = type(baseData.scenes) == "table" and baseData.scenes or nil
    local newScenes = type(newData.scenes) == "table" and newData.scenes or nil
    if not baseScenes or not newScenes then return nil, "missing scenes" end
    if #baseScenes ~= #newScenes then return nil, "scene count changed" end
    if not TableDeepEqual(CopyPlanWithoutScenes(baseData), CopyPlanWithoutScenes(newData)) then
        return nil, "non-scene plan metadata changed"
    end

    local sceneOps = {}
    for sceneIndex = 1, #newScenes do
        local oldScene = baseScenes[sceneIndex]
        local newScene = newScenes[sceneIndex]
        if type(oldScene) ~= "table" or type(newScene) ~= "table" then return nil, "invalid scene table" end
        if not TableDeepEqual(SceneWithoutItems(oldScene), SceneWithoutItems(newScene)) then
            return nil, ("scene %d metadata changed"):format(sceneIndex)
        end
        local oldItems = type(oldScene.items) == "table" and oldScene.items or {}
        local newItems = type(newScene.items) == "table" and newScene.items or {}
        if not TableDeepEqual(oldItems, newItems) then
            local oldById, newById = {}, {}
            for _, it in ipairs(oldItems) do
                local id = StableItemId(it)
                if not id then return nil, ("item without id in scene %d"):format(sceneIndex) end
                if oldById[id] then return nil, ("duplicate item id in scene %d"):format(sceneIndex) end
                oldById[id] = it
            end
            for _, it in ipairs(newItems) do
                local id = StableItemId(it)
                if not id then return nil, ("item without id in scene %d"):format(sceneIndex) end
                if newById[id] then return nil, ("duplicate item id in scene %d"):format(sceneIndex) end
                newById[id] = it
            end
            local add, rem, set = {}, {}, {}
            for _, it in ipairs(oldItems) do
                local id = StableItemId(it)
                if not newById[id] then rem[#rem + 1] = id end
            end
            for _, it in ipairs(newItems) do
                local id = StableItemId(it)
                local oldIt = oldById[id]
                if not oldIt then
                    add[#add + 1] = CopyPlanData(it)
                elseif not TableDeepEqual(oldIt, it) then
                    set[#set + 1] = CopyPlanData(it)
                end
            end
            -- Only ordering changed (same ids, same bodies): let scene mode handle it.
            if #add == 0 and #rem == 0 and #set == 0 then
                return nil, ("scene %d reordered only"):format(sceneIndex)
            end
            sceneOps[#sceneOps + 1] = { sceneIndex = sceneIndex, add = add, rem = rem, set = set }
        end
    end

    if #sceneOps == 0 then return nil, "no item changes detected" end
    return { scenes = sceneOps }, nil
end

local function EncodeItemDeltaPayload(delta)
    if type(delta) ~= "table" or type(delta.scenes) ~= "table" or #delta.scenes == 0 then return nil end
    local json = EncodeJson(delta)
    if not json or json == "" then return nil end
    local body = json
    local LibDeflate = LibStub("LibDeflate", true)
    if LibDeflate and LibDeflate.CompressDeflate then
        local ok, compressed = pcall(function() return LibDeflate:CompressDeflate(json, { level = 6 }) end)
        if ok and compressed and (#compressed + 1) < #json then
            body = string.char(0x01) .. compressed
        end
    end
    return EncodeBase64Local(body)
end

local function DecodeItemDeltaPayload(payloadB64)
    if type(payloadB64) ~= "string" or payloadB64 == "" then return nil end
    local decoded = DecodeBase64Local(payloadB64)
    if not decoded or decoded == "" then return nil end
    local json = decoded
    if decoded:byte(1) == 0x01 then
        local LibDeflate = LibStub("LibDeflate", true)
        if not LibDeflate or not LibDeflate.DecompressDeflate then return nil end
        local inflated = LibDeflate:DecompressDeflate(decoded:sub(2))
        if not inflated or inflated == "" then return nil end
        json = inflated
    end
    local packet = DecodeJson(json)
    if type(packet) ~= "table" or type(packet.scenes) ~= "table" or #packet.scenes == 0 then return nil end
    return packet
end

-- Structural scene delta: only sends scenes that were added/changed plus the new total count.
-- Handles added scenes, removed-from-end scenes, and multi-scene edits without a full resend.
local function BuildSceneStructureDelta(baseData, newData)
    if type(baseData) ~= "table" or type(newData) ~= "table" then return nil, "invalid data" end
    local baseScenes = type(baseData.scenes) == "table" and baseData.scenes or nil
    local newScenes = type(newData.scenes) == "table" and newData.scenes or nil
    if not baseScenes or not newScenes then return nil, "missing scenes" end
    if not TableDeepEqual(CopyPlanWithoutScenes(baseData), CopyPlanWithoutScenes(newData)) then
        return nil, "non-scene plan metadata changed"
    end

    local newCount = #newScenes
    local ops = {}
    for i = 1, newCount do
        local baseScene = baseScenes[i]
        if not baseScene or not TableDeepEqual(baseScene, newScenes[i]) then
            ops[#ops + 1] = { index = i, scene = newScenes[i] }
        end
    end

    if #ops == 0 and newCount == #baseScenes then
        return nil, "no scene delta detected"
    end
    -- Only worth it if we're sending fewer scenes than the whole plan.
    if #ops >= newCount then
        return nil, "structural change touches every scene"
    end
    return { count = newCount, ops = ops }, nil
end

local function EncodeScenesDeltaPayload(delta)
    if type(delta) ~= "table" or type(delta.ops) ~= "table" then return nil end
    local json = EncodeJson({ count = delta.count, ops = delta.ops })
    if not json or json == "" then return nil end
    local body = json
    local LibDeflate = LibStub("LibDeflate", true)
    if LibDeflate and LibDeflate.CompressDeflate then
        local ok, compressed = pcall(function() return LibDeflate:CompressDeflate(json, { level = 6 }) end)
        if ok and compressed and (#compressed + 1) < #json then
            body = string.char(0x01) .. compressed
        end
    end
    return EncodeBase64Local(body)
end

local function DecodeScenesDeltaPayload(payloadB64)
    if type(payloadB64) ~= "string" or payloadB64 == "" then return nil end
    local decoded = DecodeBase64Local(payloadB64)
    if not decoded or decoded == "" then return nil end
    local json = decoded
    if decoded:byte(1) == 0x01 then
        local LibDeflate = LibStub("LibDeflate", true)
        if not LibDeflate or not LibDeflate.DecompressDeflate then return nil end
        local inflated = LibDeflate:DecompressDeflate(decoded:sub(2))
        if not inflated or inflated == "" then return nil end
        json = inflated
    end
    local packet = DecodeJson(json)
    if type(packet) ~= "table" then return nil end
    local count = tonumber(packet.count)
    if not count or count < 1 or type(packet.ops) ~= "table" then return nil end
    return { count = count, ops = packet.ops }
end

-- Scene deletion auto-renumbers scenes whose names are blank / "3" / "Scene 3" (see
-- DeletePlannerScene). Treat those as position labels so a delete still looks like a pure deletion.
local function IsAutoSceneName(name)
    local nm = tostring(name or "")
    return nm == "" or nm:match("^%d+$") ~= nil or nm:match("^Scene%s+%d+$") ~= nil
end

local function ScenesEqualIgnoringAutoName(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return TableDeepEqual(a, b) end
    if IsAutoSceneName(a.name) and IsAutoSceneName(b.name) then
        local ca, cb = {}, {}
        for k, v in pairs(a) do if k ~= "name" then ca[k] = v end end
        for k, v in pairs(b) do if k ~= "name" then cb[k] = v end end
        return TableDeepEqual(ca, cb)
    end
    return TableDeepEqual(a, b)
end

-- Mirror of DeletePlannerScene's renumbering so the receiver reproduces the sender's exact state.
local function RenumberAutoSceneNames(scenes)
    if type(scenes) ~= "table" then return end
    for i, scene in ipairs(scenes) do
        if type(scene) == "table" and IsAutoSceneName(scene.name) then
            scene.name = tostring(i)
        end
    end
end

-- Pure-deletion delta: new scenes are the base scenes minus some, same order, no edits/adds.
-- Sends only the removed base indices, so deleting scene N never needs a full resend.
local function BuildSceneRemoveDelta(baseData, newData)
    if type(baseData) ~= "table" or type(newData) ~= "table" then return nil, "invalid data" end
    local baseScenes = type(baseData.scenes) == "table" and baseData.scenes or nil
    local newScenes = type(newData.scenes) == "table" and newData.scenes or nil
    if not baseScenes or not newScenes then return nil, "missing scenes" end
    if not TableDeepEqual(CopyPlanWithoutScenes(baseData), CopyPlanWithoutScenes(newData)) then
        return nil, "non-scene plan metadata changed"
    end
    if #newScenes >= #baseScenes then return nil, "no scenes removed" end

    -- Greedy in-order match: base scenes that don't match the next new scene are removals.
    -- Auto sequential names are ignored so post-delete renumbering doesn't break the match.
    local removed = {}
    local bi = 1
    for ni = 1, #newScenes do
        local matched = false
        while bi <= #baseScenes do
            if ScenesEqualIgnoringAutoName(baseScenes[bi], newScenes[ni]) then
                bi = bi + 1
                matched = true
                break
            end
            removed[#removed + 1] = bi
            bi = bi + 1
        end
        if not matched then
            return nil, "new scene not found in base order (not a pure deletion)"
        end
    end
    while bi <= #baseScenes do
        removed[#removed + 1] = bi
        bi = bi + 1
    end

    if #removed ~= (#baseScenes - #newScenes) then
        return nil, "removal count mismatch"
    end
    return { removed = removed, count = #newScenes }, nil
end

local function EncodeSceneRemoveDeltaPayload(delta)
    if type(delta) ~= "table" or type(delta.removed) ~= "table" or #delta.removed == 0 then return nil end
    local json = EncodeJson({ removed = delta.removed, count = delta.count })
    if not json or json == "" then return nil end
    return EncodeBase64Local(json)
end

local function DecodeSceneRemoveDeltaPayload(payloadB64)
    if type(payloadB64) ~= "string" or payloadB64 == "" then return nil end
    local decoded = DecodeBase64Local(payloadB64)
    if not decoded or decoded == "" then return nil end
    local packet = DecodeJson(decoded)
    if type(packet) ~= "table" or type(packet.removed) ~= "table" or #packet.removed == 0 then return nil end
    return { removed = packet.removed, count = tonumber(packet.count) }
end

local function PrunePlanUpdates(self)
    self._planUpdates = self._planUpdates or {}
    local now = GetTime()
    for id, entry in pairs(self._planUpdates) do
        if not entry or (now - (entry.t or 0)) > PLAN_UPDATE_TTL then
            self._planUpdates[id] = nil
        end
    end
end

-- Cross-player plan identity for push/sync — instanceKey isolates team copies of the same planId.
function Diar:GetPlanIdentityKey(data)
    data = data or self.plannerData
    if not data then return nil end
    if type(data.instanceKey) == "string" and data.instanceKey ~= "" then
        return "inst:" .. data.instanceKey
    end
    return nil
end

function Diar:AllowPlanIdPushFallback(channel)
    return channel == "RAID" or channel == "PARTY" or channel == "INSTANCE_CHAT"
end

function Diar:PlanDataMatchesPlanId(data, planId)
    if not data or not planId or planId == "" then return false end
    return tostring(data.planId or "") == tostring(planId)
end

function Diar:ReceiverHasMatchingPlan(planKey, opts)
    opts = opts or {}
    if planKey and self:GetPlanIdentityKey(self.plannerData) == planKey then
        return true
    end
    RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {} }
    for _, entry in ipairs(RaidstratsggSavedPlans.list) do
        if entry.data and self:GetPlanIdentityKey(entry.data) == planKey then
            return true
        end
    end

    -- Same raid/party: match public planId so teams sync after independent imports.
    -- Guild-only pushes stay instanceKey-only (avoids cross-team collisions in large guilds).
    local planId = opts.planId
    if planId and planId ~= "" and self:AllowPlanIdPushFallback(opts.channel) then
        if self:PlanDataMatchesPlanId(self.plannerData, planId) then
            return true
        end
        for _, entry in ipairs(RaidstratsggSavedPlans.list) do
            if self:PlanDataMatchesPlanId(entry.data, planId) then
                return true
            end
        end
    end
    return false
end

function Diar:IsPlanAutoImportEnabled(planKey, planId)
    if not planKey and not planId then return false end
    local s = self.GetPlannerSettings and self:GetPlannerSettings()
    local map = s and s.planAutoImport
    if not map then return false end
    if planKey and map[planKey] == true then return true end
    if planId and planId ~= "" then
        RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {} }
        for _, entry in ipairs(RaidstratsggSavedPlans.list) do
            if self:PlanDataMatchesPlanId(entry.data, planId) then
                local k = self:GetPlanIdentityKey(entry.data)
                if k and map[k] == true then return true end
            end
        end
        if self:PlanDataMatchesPlanId(self.plannerData, planId) then
            local k = self:GetPlanIdentityKey(self.plannerData)
            if k and map[k] == true then return true end
        end
    end
    return false
end

function Diar:SetPlanAutoImport(planKey, enabled)
    if not planKey then return end
    local s = self.GetPlannerSettings and self:GetPlannerSettings()
    if not s then return end
    s.planAutoImport = s.planAutoImport or {}
    if enabled then
        s.planAutoImport[planKey] = true
    else
        s.planAutoImport[planKey] = nil
    end
    if self.RefreshSavedPlansList then self:RefreshSavedPlansList() end
end

function Diar:FindSavedEntryIdForPlanKey(planKey, planId)
    if planKey and self:GetPlanIdentityKey(self.plannerData) == planKey then
        return self.plannerData and self.plannerData.savedEntryId
    end
    RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {} }
    for _, entry in ipairs(RaidstratsggSavedPlans.list) do
        if entry.data and planKey and self:GetPlanIdentityKey(entry.data) == planKey then
            return entry.id
        end
    end
    if planId and planId ~= "" then
        if self:PlanDataMatchesPlanId(self.plannerData, planId) then
            return self.plannerData and self.plannerData.savedEntryId
        end
        for _, entry in ipairs(RaidstratsggSavedPlans.list) do
            if self:PlanDataMatchesPlanId(entry.data, planId) then
                return entry.id
            end
        end
    end
    return nil
end

function Diar:PlanUpdateMatchesCurrent(planKey, planId)
    if planKey and self:GetPlanIdentityKey(self.plannerData) == planKey then
        return true
    end
    if planId and self:PlanDataMatchesPlanId(self.plannerData, planId) then
        return true
    end
    return false
end

function Diar:ApplyPlanUpdateFromData(newData, planKey)
    if not newData or not planKey then return false end
    local planId = newData.planId and tostring(newData.planId) or nil
    local entryId = self:FindSavedEntryIdForPlanKey(planKey, planId)

    if entryId then
        RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {} }
        for _, entry in ipairs(RaidstratsggSavedPlans.list) do
            if entry.id == entryId then
                newData.savedEntryId = entryId
                if self.SanitizePlanData then self:SanitizePlanData(newData) end
                entry.data = CopyPlanData(newData)
                entry.data.savedEntryId = entryId
                if type(newData.planName) == "string" and newData.planName ~= "" then
                    entry.planName = newData.planName
                end
                if newData.expansion then entry.expansion = newData.expansion end
                if newData.raid then entry.raid = newData.raid end
                if newData.boss then entry.boss = newData.boss end
                break
            end
        end
    end

    local pf = self.plannerFrame
    local matchesCurrent = self:PlanUpdateMatchesCurrent(planKey, planId)
    if matchesCurrent then
        newData.savedEntryId = entryId or (self.plannerData and self.plannerData.savedEntryId)
        self.plannerData = CopyPlanData(newData)
        if pf and pf:IsShown() then
            -- Rebuild planner chrome/tabs so new scenes appear immediately, but keep the
            -- viewer on its current scene instead of snapping back to scene 1.
            if self.ShowPlannerViewer then
                self:ShowPlannerViewer({ reloadOnly = true, keepScene = true })
            end
            pf = self.plannerFrame
        end
        if pf and pf:IsShown() then
            if not pf.nsrtSceneActive and self.ApplyNsrtAssignmentForPlannerView then
                self:ApplyNsrtAssignmentForPlannerView(pf.selectedSceneIndex or 1)
            end
            if self.RefreshPlannerScene then self:RefreshPlannerScene() end
        end
    end

    if self.RefreshSavedPlansList then self:RefreshSavedPlansList() end
    return true
end

function Diar:ApplyPlanSceneUpdate(planKey, planId, sceneIndex, sceneData)
    sceneIndex = tonumber(sceneIndex)
    if not planKey or not sceneIndex or sceneIndex < 1 or type(sceneData) ~= "table" then
        return false
    end
    local entryId = self:FindSavedEntryIdForPlanKey(planKey, planId)
    if not entryId then return false end

    local updatedData = nil
    RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {} }
    for _, entry in ipairs(RaidstratsggSavedPlans.list) do
        if entry.id == entryId and type(entry.data) == "table" and type(entry.data.scenes) == "table" then
            if sceneIndex > #entry.data.scenes then
                return false
            end
            updatedData = CopyPlanData(entry.data)
            updatedData.scenes[sceneIndex] = CopyPlanData(sceneData)
            if self.SanitizePlanData then self:SanitizePlanData(updatedData) end
            updatedData.savedEntryId = entryId
            entry.data = CopyPlanData(updatedData)
            entry.data.savedEntryId = entryId
            if type(updatedData.planName) == "string" and updatedData.planName ~= "" then
                entry.planName = updatedData.planName
            end
            if updatedData.expansion then entry.expansion = updatedData.expansion end
            if updatedData.raid then entry.raid = updatedData.raid end
            if updatedData.boss then entry.boss = updatedData.boss end
            break
        end
    end
    if not updatedData then return false end

    local pf = self.plannerFrame
    local matchesCurrent = self:PlanUpdateMatchesCurrent(planKey, planId)
    if matchesCurrent then
        self.plannerData = CopyPlanData(updatedData)
        if pf and pf:IsShown() then
            -- Keep the receiver on their current scene across the reload.
            if self.ShowPlannerViewer then
                self:ShowPlannerViewer({ reloadOnly = true, keepScene = true })
            end
            pf = self.plannerFrame
        end
        if pf and pf:IsShown() then
            if not pf.nsrtSceneActive and self.ApplyNsrtAssignmentForPlannerView then
                self:ApplyNsrtAssignmentForPlannerView(pf.selectedSceneIndex or 1)
            end
            if self.RefreshPlannerScene then self:RefreshPlannerScene() end
        end
    end

    if self.RefreshSavedPlansList then self:RefreshSavedPlansList() end
    return true
end

function Diar:ApplyPlanItemUpdate(planKey, planId, sceneOps)
    if not planKey or type(sceneOps) ~= "table" or #sceneOps == 0 then return false end
    local entryId = self:FindSavedEntryIdForPlanKey(planKey, planId)
    if not entryId then return false end

    local updatedData = nil
    RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {} }
    for _, entry in ipairs(RaidstratsggSavedPlans.list) do
        if entry.id == entryId and type(entry.data) == "table" and type(entry.data.scenes) == "table" then
            updatedData = CopyPlanData(entry.data)
            for _, op in ipairs(sceneOps) do
                local idx = tonumber(op and op.sceneIndex)
                if not idx or idx < 1 or idx > #updatedData.scenes then return false end
                local scene = updatedData.scenes[idx]
                if type(scene) ~= "table" then return false end
                local items = type(scene.items) == "table" and scene.items or {}

                -- Index the delta by id.
                local removed = {}
                for _, id in ipairs(op.rem or {}) do removed[tostring(id)] = true end
                local setById = {}
                for _, body in ipairs(op.set or {}) do
                    local id = StableItemId(body)
                    if id then setById[id] = body end
                end

                -- Rebuild from EXISTING items: keep, replace, or drop -- never start empty.
                local rebuilt = {}
                for _, it in ipairs(items) do
                    local id = strtrim(tostring(it and it.id or ""))
                    if id ~= "" and removed[id] then
                        -- dropped
                    elseif id ~= "" and setById[id] ~= nil then
                        rebuilt[#rebuilt + 1] = CopyPlanData(setById[id])
                        setById[id] = nil
                    else
                        rebuilt[#rebuilt + 1] = it
                    end
                end
                -- Edited items we didn't find get treated as adds (keeps them, never loses).
                for _, body in ipairs(op.set or {}) do
                    local id = StableItemId(body)
                    if id and setById[id] ~= nil then
                        rebuilt[#rebuilt + 1] = CopyPlanData(body)
                        setById[id] = nil
                    end
                end
                -- New items append (matches how objects are added locally).
                for _, body in ipairs(op.add or {}) do
                    rebuilt[#rebuilt + 1] = CopyPlanData(body)
                end

                PushDebug(("Recv item op scene=%d existing=%d add=%d rem=%d set=%d -> %d"):format(
                    idx, #items, #(op.add or {}), #(op.rem or {}), #(op.set or {}), #rebuilt
                ))
                scene.items = rebuilt
            end
            if self.SanitizePlanData then self:SanitizePlanData(updatedData) end
            updatedData.savedEntryId = entryId
            entry.data = CopyPlanData(updatedData)
            entry.data.savedEntryId = entryId
            if type(updatedData.planName) == "string" and updatedData.planName ~= "" then
                entry.planName = updatedData.planName
            end
            if updatedData.expansion then entry.expansion = updatedData.expansion end
            if updatedData.raid then entry.raid = updatedData.raid end
            if updatedData.boss then entry.boss = updatedData.boss end
            break
        end
    end
    if not updatedData then return false end

    local pf = self.plannerFrame
    local matchesCurrent = self:PlanUpdateMatchesCurrent(planKey, planId)
    if matchesCurrent then
        self.plannerData = CopyPlanData(updatedData)
        if pf and pf:IsShown() then
            if self.ShowPlannerViewer then
                self:ShowPlannerViewer({ reloadOnly = true, keepScene = true })
            end
            pf = self.plannerFrame
        end
        if pf and pf:IsShown() then
            if not pf.nsrtSceneActive and self.ApplyNsrtAssignmentForPlannerView then
                self:ApplyNsrtAssignmentForPlannerView(pf.selectedSceneIndex or 1)
            end
            if self.RefreshPlannerScene then self:RefreshPlannerScene() end
        end
    end

    if self.RefreshSavedPlansList then self:RefreshSavedPlansList() end
    return true
end

function Diar:ApplyPlanScenesUpdate(planKey, planId, count, ops)
    count = tonumber(count)
    if not planKey or not count or count < 1 or type(ops) ~= "table" then
        return false
    end
    local entryId = self:FindSavedEntryIdForPlanKey(planKey, planId)
    if not entryId then return false end

    local updatedData = nil
    RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {} }
    for _, entry in ipairs(RaidstratsggSavedPlans.list) do
        if entry.id == entryId and type(entry.data) == "table" and type(entry.data.scenes) == "table" then
            updatedData = CopyPlanData(entry.data)
            updatedData.scenes = updatedData.scenes or {}
            for _, op in ipairs(ops) do
                local idx = tonumber(op and op.index)
                if not idx or idx < 1 or type(op.scene) ~= "table" then return false end
                updatedData.scenes[idx] = CopyPlanData(op.scene)
            end
            -- Trim any scenes beyond the new total count (handles removed-from-end).
            for i = #updatedData.scenes, count + 1, -1 do
                updatedData.scenes[i] = nil
            end
            if #updatedData.scenes ~= count then return false end
            if self.SanitizePlanData then self:SanitizePlanData(updatedData) end
            updatedData.savedEntryId = entryId
            entry.data = CopyPlanData(updatedData)
            entry.data.savedEntryId = entryId
            if type(updatedData.planName) == "string" and updatedData.planName ~= "" then
                entry.planName = updatedData.planName
            end
            if updatedData.expansion then entry.expansion = updatedData.expansion end
            if updatedData.raid then entry.raid = updatedData.raid end
            if updatedData.boss then entry.boss = updatedData.boss end
            break
        end
    end
    if not updatedData then return false end

    local pf = self.plannerFrame
    local matchesCurrent = self:PlanUpdateMatchesCurrent(planKey, planId)
    if matchesCurrent then
        self.plannerData = CopyPlanData(updatedData)
        if pf and pf:IsShown() then
            -- Keep the receiver on their current scene across the reload.
            if self.ShowPlannerViewer then
                self:ShowPlannerViewer({ reloadOnly = true, keepScene = true })
            end
            pf = self.plannerFrame
        end
        if pf and pf:IsShown() then
            if not pf.nsrtSceneActive and self.ApplyNsrtAssignmentForPlannerView then
                self:ApplyNsrtAssignmentForPlannerView(pf.selectedSceneIndex or 1)
            end
            if self.RefreshPlannerScene then self:RefreshPlannerScene() end
        end
    end

    if self.RefreshSavedPlansList then self:RefreshSavedPlansList() end
    return true
end

function Diar:ApplyPlanSceneRemoveUpdate(planKey, planId, removed, expectedCount)
    if not planKey or type(removed) ~= "table" or #removed == 0 then return false end
    local entryId = self:FindSavedEntryIdForPlanKey(planKey, planId)
    if not entryId then return false end

    -- Remove highest indices first so earlier indices stay valid.
    local sortedRemoved = {}
    for _, v in ipairs(removed) do
        local idx = tonumber(v)
        if not idx or idx < 1 then return false end
        sortedRemoved[#sortedRemoved + 1] = idx
    end
    table.sort(sortedRemoved, function(a, b) return a > b end)

    local updatedData = nil
    RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {} }
    for _, entry in ipairs(RaidstratsggSavedPlans.list) do
        if entry.id == entryId and type(entry.data) == "table" and type(entry.data.scenes) == "table" then
            updatedData = CopyPlanData(entry.data)
            for _, idx in ipairs(sortedRemoved) do
                if idx > #updatedData.scenes then return false end
                table.remove(updatedData.scenes, idx)
            end
            if #updatedData.scenes < 1 then return false end
            if expectedCount and #updatedData.scenes ~= expectedCount then return false end
            -- Match the sender's post-delete renumbering of auto-named scenes.
            RenumberAutoSceneNames(updatedData.scenes)
            if self.SanitizePlanData then self:SanitizePlanData(updatedData) end
            updatedData.savedEntryId = entryId
            entry.data = CopyPlanData(updatedData)
            entry.data.savedEntryId = entryId
            if type(updatedData.planName) == "string" and updatedData.planName ~= "" then
                entry.planName = updatedData.planName
            end
            if updatedData.expansion then entry.expansion = updatedData.expansion end
            if updatedData.raid then entry.raid = updatedData.raid end
            if updatedData.boss then entry.boss = updatedData.boss end
            break
        end
    end
    if not updatedData then return false end

    local pf = self.plannerFrame
    local matchesCurrent = self:PlanUpdateMatchesCurrent(planKey, planId)
    if matchesCurrent then
        -- Keep the viewer on the same scene by identity. Only if the scene they're on was
        -- removed do we fall back to the previous still-available scene.
        local oldSelected = pf and pf.selectedSceneIndex or 1
        local removedSet, removedBefore, selectedRemoved = {}, 0, false
        for _, v in ipairs(removed) do
            local idx = tonumber(v)
            if idx then
                removedSet[idx] = true
                if idx < oldSelected then removedBefore = removedBefore + 1 end
                if idx == oldSelected then selectedRemoved = true end
            end
        end
        local newSelected
        if selectedRemoved then
            newSelected = oldSelected - removedBefore - 1
        else
            newSelected = oldSelected - removedBefore
        end
        if newSelected < 1 then newSelected = 1 end
        if newSelected > #updatedData.scenes then newSelected = #updatedData.scenes end

        self.plannerData = CopyPlanData(updatedData)
        if pf then pf.selectedSceneIndex = newSelected end
        if pf and pf:IsShown() then
            if self.ShowPlannerViewer then
                self:ShowPlannerViewer({ reloadOnly = true, keepScene = true })
            end
            pf = self.plannerFrame
        end
        if pf and pf:IsShown() then
            if not pf.nsrtSceneActive and self.ApplyNsrtAssignmentForPlannerView then
                self:ApplyNsrtAssignmentForPlannerView(pf.selectedSceneIndex or 1)
            end
            if self.RefreshPlannerScene then self:RefreshPlannerScene() end
        end
    end

    if self.RefreshSavedPlansList then self:RefreshSavedPlansList() end
    return true
end

local function ApplyItemPosition(item, newX, newY)
    local oldX = tonumber(item.x) or newX
    local oldY = tonumber(item.y) or newY
    local dx = newX - oldX
    local dy = newY - oldY
    item.x = newX
    item.y = newY
    item.currentX = newX / 100
    item.currentY = newY / 100
    if type(item.corners) == "table" and #item.corners >= 3 and (math.abs(dx) > 0.0001 or math.abs(dy) > 0.0001) then
        for _, p in ipairs(item.corners) do
            if type(p) == "table" then
                local px = tonumber(p.x)
                local py = tonumber(p.y)
                if px and py then
                    p.x = px + dx
                    p.y = py + dy
                end
            end
        end
    end
end

function Diar:ApplyPlanObjectMovesUpdate(planKey, planId, moves)
    if not planKey or type(moves) ~= "table" or #moves == 0 then return false end
    local entryId = self:FindSavedEntryIdForPlanKey(planKey, planId)
    if not entryId then return false end

    local updatedData = nil
    RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {} }
    for _, entry in ipairs(RaidstratsggSavedPlans.list) do
        if entry.id == entryId and type(entry.data) == "table" and type(entry.data.scenes) == "table" then
            updatedData = CopyPlanData(entry.data)
            for _, op in ipairs(moves) do
                local sceneIndex = tonumber(op and op.sceneIndex)
                local scene = sceneIndex and updatedData.scenes[sceneIndex] or nil
                local items = scene and scene.items
                if type(items) ~= "table" then return false end

                local target = nil
                local itemId = strtrim(tostring(op and op.itemId or ""))
                if itemId ~= "" then
                    for _, it in ipairs(items) do
                        if strtrim(tostring(it and it.id or "")) == itemId then
                            target = it
                            break
                        end
                    end
                end
                if not target then
                    local idx = tonumber(op and op.itemIndex)
                    target = idx and items[idx] or nil
                end
                if not target then return false end

                local x = tonumber(op and op.x)
                local y = tonumber(op and op.y)
                if not x or not y then return false end
                ApplyItemPosition(target, x, y)
            end

            updatedData.savedEntryId = entryId
            entry.data = CopyPlanData(updatedData)
            entry.data.savedEntryId = entryId
            if type(updatedData.planName) == "string" and updatedData.planName ~= "" then
                entry.planName = updatedData.planName
            end
            if updatedData.expansion then entry.expansion = updatedData.expansion end
            if updatedData.raid then entry.raid = updatedData.raid end
            if updatedData.boss then entry.boss = updatedData.boss end
            break
        end
    end
    if not updatedData then return false end

    local pf = self.plannerFrame
    local matchesCurrent = self:PlanUpdateMatchesCurrent(planKey, planId)
    if matchesCurrent then
        self.plannerData = CopyPlanData(updatedData)
        if pf and pf:IsShown() then
            -- Keep the receiver on their current scene across the reload.
            if self.ShowPlannerViewer then
                self:ShowPlannerViewer({ reloadOnly = true, keepScene = true })
            end
            pf = self.plannerFrame
        end
        if pf and pf:IsShown() then
            if not pf.nsrtSceneActive and self.ApplyNsrtAssignmentForPlannerView then
                self:ApplyNsrtAssignmentForPlannerView(pf.selectedSceneIndex or 1)
            end
            if self.RefreshPlannerScene then self:RefreshPlannerScene() end
        end
    end

    if self.RefreshSavedPlansList then self:RefreshSavedPlansList() end
    return true
end

local function BuildPushBaselineData(self, data)
    if not data then return nil end
    local prepared = self and self.PreparePlanDataForShare and self:PreparePlanDataForShare(data) or nil
    if prepared then return prepared end
    return CopyPlanData(data)
end

-- Persisted per-plan sync state so delta push survives /reload:
--   store[planKey] = { version = <number>, data = <baseline plan>, t = <time> }
-- Leaders keep `data` (needed to diff); receivers only need `version`.
function Diar:GetPlanSyncStore()
    RaidstratsggSettings = RaidstratsggSettings or {}
    RaidstratsggSettings.planPushSync = RaidstratsggSettings.planPushSync or {}
    return RaidstratsggSettings.planPushSync
end

function Diar:GetPlanSyncVersion(planKey)
    if not planKey or planKey == "" then return nil end
    local rec = self:GetPlanSyncStore()[planKey]
    return rec and tonumber(rec.version) or nil
end

function Diar:EnsurePlanSyncVersionLabel(pf)
    pf = pf or self.plannerFrame
    if not pf or not pf.canvas then return nil end
    if pf.planSyncVersionLabel then return pf.planSyncVersionLabel end
    local label = pf.canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("BOTTOMRIGHT", pf.canvas, "BOTTOMRIGHT", -56, 6)
    label:SetJustifyH("RIGHT")
    label:SetTextColor(1, 1, 1, 0.9)
    label:SetText("")
    pf.planSyncVersionLabel = label
    return label
end

function Diar:UpdatePlanSyncVersionLabel(pf)
    pf = pf or self.plannerFrame
    local label = self:EnsurePlanSyncVersionLabel(pf)
    if not label then return end
    -- Keep style/position in sync for frames created before this tweak.
    label:ClearAllPoints()
    label:SetPoint("BOTTOMRIGHT", pf.canvas, "BOTTOMRIGHT", -56, 6)
    label:SetTextColor(1, 1, 1, 0.9)
    local data = self.plannerData
    if not data or type(data.scenes) ~= "table" or #data.scenes == 0 then
        label:SetText("")
        label:Hide()
        return
    end
    local planKey = self.GetPlanIdentityKey and self:GetPlanIdentityKey(data) or nil
    local ver = (planKey and self:GetPlanSyncVersion(planKey)) or nil
    local inst = tostring(data.instanceKey or "")
    if inst ~= "" then
        -- Short stable peek of the unique key body (strip "inst:" / "plan:" prefixes).
        inst = inst:gsub("^inst:", ""):gsub("^plan:", "")
        if #inst > 6 then inst = inst:sub(1, 6) end
    end
    local verText = ver and tostring(ver) or "—"
    if inst ~= "" then
        label:SetText(L("Version: %s-%s"):format(verText, inst))
    else
        label:SetText(L("Version: %s"):format(verText))
    end
    label:Show()
end

function Diar:GetPlanPushBaseline(planKey)
    if not planKey or planKey == "" then return nil end
    local rec = self:GetPlanSyncStore()[planKey]
    if type(rec) ~= "table" or type(rec.data) ~= "table" then return nil end
    return CopyPlanData(rec.data)
end

function Diar:SetPlanPushBaseline(planKey, data, version)
    if not planKey or planKey == "" then return end
    local store = self:GetPlanSyncStore()
    local rec = store[planKey] or {}
    if type(data) == "table" then
        rec.data = CopyPlanData(data)
    end
    if version ~= nil then
        rec.version = tonumber(version)
    end
    rec.t = time()
    store[planKey] = rec
end

-- Receiver side: remember the version we're on without storing a full baseline copy.
function Diar:SetPlanSyncVersion(planKey, version)
    if not planKey or planKey == "" or version == nil then return end
    local store = self:GetPlanSyncStore()
    local rec = store[planKey] or {}
    rec.version = tonumber(version)
    rec.t = time()
    store[planKey] = rec
    if self.UpdatePlanSyncVersionLabel then
        self:UpdatePlanSyncVersionLabel(self.plannerFrame)
    end
end

-- After edits persist, wait briefly then commit a sync version if content changed.
-- Debounced so dragging/moving doesn't bump every mouse-up — only once editing settles.
local PLAN_SYNC_VERSION_COMMIT_DELAY = 0.75
function Diar:SchedulePlanSyncVersionCommit()
    if self._planSyncVersionCommitTimer then
        self._planSyncVersionCommitTimer:Cancel()
        self._planSyncVersionCommitTimer = nil
    end
    local function commit()
        Diar._planSyncVersionCommitTimer = nil
        if Diar.plannerData and Diar.EnsurePlanSyncVersionMatchesContent then
            Diar:EnsurePlanSyncVersionMatchesContent(Diar.plannerData)
        elseif Diar.UpdatePlanSyncVersionLabel then
            Diar:UpdatePlanSyncVersionLabel(Diar.plannerFrame)
        end
    end
    if C_Timer and C_Timer.NewTimer then
        self._planSyncVersionCommitTimer = C_Timer.NewTimer(PLAN_SYNC_VERSION_COMMIT_DELAY, commit)
    else
        commit()
    end
end

-- If the current plan content differs from the last stamped sync baseline, bump the
-- sync version once and refresh the baseline. Called from readycheck/share/push and
-- (debounced) after plan edits persist so the canvas Version label stays live.
-- Returns the current sync version for the plan, or nil.
function Diar:EnsurePlanSyncVersionMatchesContent(data)
    if type(data) ~= "table" then return nil end
    if self.EnsurePlanInstanceKey then self:EnsurePlanInstanceKey(data) end
    if type(data.instanceKey) ~= "string" or data.instanceKey == "" then
        return nil
    end
    local planKey = "inst:" .. data.instanceKey
    local shareData = self.PreparePlanDataForShare and self:PreparePlanDataForShare(data) or nil
    if type(shareData) ~= "table" then
        return self:GetPlanSyncVersion(planKey)
    end
    shareData.syncVersion = nil

    local existing = self:GetPlanSyncVersion(planKey)
    local baseline = self:GetPlanPushBaseline(planKey)
    if existing and baseline and TableDeepEqual(baseline, shareData) then
        return existing
    end

    local version = (tonumber(existing) or 0) + 1
    self:SetPlanPushBaseline(planKey, shareData, version)
    if self.UpdatePlanSyncVersionLabel then
        self:UpdatePlanSyncVersionLabel(self.plannerFrame)
    end
    return version
end

-- Called when building a share payload. Ensures the plan has a sync version + baseline and
-- stamps `syncVersion` on the (already sanitized) share copy so importers start in sync,
-- letting the very first push apply as a delta instead of a full reimport.
-- Bumps only when content differs from the last baseline (same rule as Ensure above).
function Diar:StampShareSyncVersion(shareData, opts)
    if type(shareData) ~= "table" then return end
    if type(shareData.instanceKey) ~= "string" or shareData.instanceKey == "" then
        return
    end
    local planKey = "inst:" .. shareData.instanceKey
    local existing = self:GetPlanSyncVersion(planKey)
    local baseline = self:GetPlanPushBaseline(planKey)
    local version
    if opts and opts.reuseSyncVersion then
        -- Force reuse (no content check). Prefer EnsurePlanSyncVersionMatchesContent first.
        if existing then
            version = existing
            if not baseline then
                self:SetPlanPushBaseline(planKey, shareData, version)
            end
        else
            version = 1
            self:SetPlanPushBaseline(planKey, shareData, version)
        end
    elseif existing and baseline and TableDeepEqual(baseline, shareData) then
        -- Already in sync with what we last pushed/shared; reuse the version.
        version = existing
    else
        version = (tonumber(existing) or 0) + 1
        -- Persist the shared snapshot as our baseline (without the stamp) so a later push diffs against it.
        self:SetPlanPushBaseline(planKey, shareData, version)
    end
    shareData.syncVersion = version
    if self.UpdatePlanSyncVersionLabel then
        self:UpdatePlanSyncVersionLabel(self.plannerFrame)
    end
end

-- Called on import: seed our local version from a shared payload so we're ready for delta pushes.
function Diar:SeedPlanSyncVersionFromImport(planKey, version)
    version = tonumber(version)
    if not planKey or planKey == "" or not version then return end
    self:SetPlanSyncVersion(planKey, version)
end

function Diar:TryCompletePlanUpdate(transferId)
    local entry = self._planUpdates and self._planUpdates[transferId]
    if not entry or entry.status == "declined" then return end
    if entry.status ~= "accepted" and entry.status ~= "auto" then return end
    local total = entry.total
    if not total or total < 1 then return end
    for i = 1, total do
        if not entry.chunks[i] then return end
    end

    local b64 = table.concat(entry.chunks, "")
    PushDebug(("Recv update id=%s mode=%s chunks=%d bytes=%d"):format(
        tostring(transferId),
        tostring(entry.mode or "full"),
        tonumber(entry.total or 0),
        #b64
    ))
    self._planUpdates[transferId] = nil
    if self.HideImportProgress then self:HideImportProgress() end
    local who = SenderLabel(entry.sender)

    -- Deltas are only valid if our stored version matches the base the sender diffed from.
    if entry.mode == "scene" or entry.mode == "move" or entry.mode == "items" or entry.mode == "scenes" or entry.mode == "scenerm" then
        local localVersion = self:GetPlanSyncVersion(entry.planKey)
        if entry.baseVersion and localVersion ~= entry.baseVersion then
            PushDebug(("Delta version mismatch local=%s base=%s -> requesting full"):format(
                tostring(localVersion or "-"), tostring(entry.baseVersion)
            ))
            local label = entry.planName or L("plan")
            print("|cffffff99[Raidstrats.gg]|r " ..
                L("Your copy of \"%s\" is out of date — ask %s to re-share it."):format(label, who))
            return
        end
    end

    if entry.mode == "scene" then
        local sceneData = DecodeSceneDeltaPayload(b64)
        if sceneData and self:ApplyPlanSceneUpdate(entry.planKey, entry.planId, entry.sceneIndex, sceneData) then
            PushDebug(("Applied recv scene delta scene=%s plan=%s"):format(
                tostring(entry.sceneIndex), tostring(entry.planName or "?")
            ))
            if entry.newVersion then self:SetPlanSyncVersion(entry.planKey, entry.newVersion) end
            local label = entry.planName or L("plan")
            self:OpenPlanAfterUpdateIfNeeded(entry.planKey, entry.planId, nil)
            print("|cff00aaff[Raidstrats.gg]|r " ..
                L("Applied scene update to \"%s\" from %s."):format(label, who))
            return
        end
        print("|cffff6666[Raidstrats.gg]|r " .. L("Could not apply the scene update."))
        PushDebug("Failed to apply recv scene delta")
        return
    end

    if entry.mode == "move" then
        local moves = DecodeObjectMoveDeltaPayload(b64)
        if moves and self:ApplyPlanObjectMovesUpdate(entry.planKey, entry.planId, moves) then
            PushDebug(("Applied recv move delta moves=%d plan=%s"):format(#moves, tostring(entry.planName or "?")))
            if entry.newVersion then self:SetPlanSyncVersion(entry.planKey, entry.newVersion) end
            local label = entry.planName or L("plan")
            self:OpenPlanAfterUpdateIfNeeded(entry.planKey, entry.planId, nil)
            print("|cff00aaff[Raidstrats.gg]|r " ..
                L("Applied move update to \"%s\" from %s."):format(label, who))
            return
        end
        print("|cffff6666[Raidstrats.gg]|r " .. L("Could not apply the move update."))
        PushDebug("Failed to apply recv move delta")
        return
    end

    if entry.mode == "items" then
        local delta = DecodeItemDeltaPayload(b64)
        if delta and self:ApplyPlanItemUpdate(entry.planKey, entry.planId, delta.scenes) then
            PushDebug(("Applied recv item delta scenes=%d plan=%s"):format(
                #delta.scenes, tostring(entry.planName or "?")
            ))
            if entry.newVersion then self:SetPlanSyncVersion(entry.planKey, entry.newVersion) end
            local label = entry.planName or L("plan")
            self:OpenPlanAfterUpdateIfNeeded(entry.planKey, entry.planId, nil)
            print("|cff00aaff[Raidstrats.gg]|r " ..
                L("Applied object update to \"%s\" from %s."):format(label, who))
            return
        end
        print("|cffff6666[Raidstrats.gg]|r " .. L("Could not apply the object update."))
        PushDebug("Failed to apply recv item delta")
        return
    end

    if entry.mode == "scenes" then
        local delta = DecodeScenesDeltaPayload(b64)
        if delta and self:ApplyPlanScenesUpdate(entry.planKey, entry.planId, delta.count, delta.ops) then
            PushDebug(("Applied recv scenes delta ops=%d count=%d plan=%s"):format(
                #delta.ops, delta.count, tostring(entry.planName or "?")
            ))
            if entry.newVersion then self:SetPlanSyncVersion(entry.planKey, entry.newVersion) end
            local label = entry.planName or L("plan")
            self:OpenPlanAfterUpdateIfNeeded(entry.planKey, entry.planId, nil)
            print("|cff00aaff[Raidstrats.gg]|r " ..
                L("Applied scene update to \"%s\" from %s."):format(label, who))
            return
        end
        print("|cffff6666[Raidstrats.gg]|r " .. L("Could not apply the scene update."))
        PushDebug("Failed to apply recv scenes delta")
        return
    end

    if entry.mode == "scenerm" then
        local delta = DecodeSceneRemoveDeltaPayload(b64)
        if delta and self:ApplyPlanSceneRemoveUpdate(entry.planKey, entry.planId, delta.removed, delta.count) then
            PushDebug(("Applied recv scene-remove delta removed=%d plan=%s"):format(
                #delta.removed, tostring(entry.planName or "?")
            ))
            if entry.newVersion then self:SetPlanSyncVersion(entry.planKey, entry.newVersion) end
            local label = entry.planName or L("plan")
            self:OpenPlanAfterUpdateIfNeeded(entry.planKey, entry.planId, nil)
            print("|cff00aaff[Raidstrats.gg]|r " ..
                L("Applied scene update to \"%s\" from %s."):format(label, who))
            return
        end
        print("|cffff6666[Raidstrats.gg]|r " .. L("Could not apply the scene update."))
        PushDebug("Failed to apply recv scene-remove delta")
        return
    end

    local data = self.DecodePlanFromBase64 and self:DecodePlanFromBase64(b64)
    if not data then
        print("|cffff6666[Raidstrats.gg]|r " .. L("Could not apply the plan update."))
        PushDebug("Failed to decode recv full update payload")
        return
    end

    if self:ApplyPlanUpdateFromData(data, entry.planKey) then
        local label = entry.planName or data.planName or L("plan")
        if data.instanceKey then
            entry.planKey = "inst:" .. data.instanceKey
        end
        -- Full update establishes a known base version so later deltas can apply.
        if entry.newVersion then self:SetPlanSyncVersion(entry.planKey, entry.newVersion) end
        self:OpenPlanAfterUpdateIfNeeded(entry.planKey, entry.planId, data)
        print("|cff00aaff[Raidstrats.gg]|r " ..
            L("Applied update to \"%s\" from %s."):format(label, who))
    else
        print("|cffff6666[Raidstrats.gg]|r " .. L("Could not apply the plan update."))
    end
end

function Diar:OpenPlanAfterUpdateIfNeeded(planKey, planId, data)
    local pf = self.plannerFrame
    local plannerOpen = pf and pf:IsShown()
    if plannerOpen and self:PlanUpdateMatchesCurrent(planKey, planId) then
        return
    end
    local entryId = self:FindSavedEntryIdForPlanKey(planKey, planId)
    if entryId and self.LoadSavedPlanById then
        self:LoadSavedPlanById(entryId, { openPlanner = true })
        if self.LayoutOpenWindows then self:LayoutOpenWindows() end
        return
    end
    if data and self:PlanUpdateMatchesCurrent(planKey, planId) then
        if self.OpenPlannerAfterShareImport then
            self:OpenPlannerAfterShareImport({ reloadOnly = plannerOpen })
        elseif self.ShowPlannerViewer then
            self:ShowPlannerViewer(plannerOpen and { reloadOnly = true } or nil)
        end
    end
end

function Diar:HidePlanUpdatePopup()
    if self._planUpdatePopup then
        self._planUpdatePopup:Hide()
    end
end

function Diar:ShowPlanUpdatePopup(entry)
    if not entry then return end
    self:HidePlanUpdatePopup()

    local who = SenderLabel(entry.sender)
    local planLabel = (entry.planName and entry.planName ~= "") and entry.planName or L("the plan")
    local f = CreateFrame("Frame", "RaidstratsPlanUpdatePopup", UIParent, "BackdropTemplate")
    f:SetSize(380, 168)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)
    if SetBackdrop then SetBackdrop(f, UI.PANEL, UI.BORDER, 2) end
    tinsert(UISpecialFrames, "RaidstratsPlanUpdatePopup")

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText(L("Plan update — %s"):format(planLabel))
    title:SetTextColor(0.92, 0.92, 0.92)

    local msg = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    msg:SetPoint("TOP", title, "BOTTOM", 0, -10)
    msg:SetWidth(340)
    msg:SetJustifyH("CENTER")
    msg:SetText(L("%s has updated \"%s\".\nWould you like to import the changes?"):format(who, planLabel))
    msg:SetTextColor(0.78, 0.80, 0.84)

    local autoChk = Diar.CreateAnimatedCheckbox and
        Diar.CreateAnimatedCheckbox(f, L("Always import updates for this plan"))
    if autoChk then
        autoChk:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -88)
        if autoChk.label then
            autoChk.label:SetFontObject("GameFontHighlightSmall")
            autoChk.label:SetWidth(320)
            autoChk.label:SetJustifyH("LEFT")
            autoChk.label:SetTextColor(0.72, 0.75, 0.80)
        end
    end

    local function makeBtn(text, x, onClick)
        local b = CreateFrame("Button", nil, f, "BackdropTemplate")
        b:SetSize(118, 28)
        b:SetPoint("BOTTOM", x, 14)
        if SetBackdrop then SetBackdrop(b, UI.ROW, UI.BORDER, 1) end
        local lbl = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("CENTER")
        lbl:SetText(text)
        lbl:SetTextColor(0.9, 0.9, 0.9)
        b:SetScript("OnEnter", function(s)
            s:SetBackdropColor(unpack(UI.ROW_HOV))
            lbl:SetTextColor(1, 1, 1)
        end)
        b:SetScript("OnLeave", function(s)
            s:SetBackdropColor(unpack(UI.ROW))
            lbl:SetTextColor(0.9, 0.9, 0.9)
        end)
        b:SetScript("OnClick", onClick)
        return b
    end

    makeBtn(L("Not now"), -62, function()
        entry.status = "declined"
        Diar:HidePlanUpdatePopup()
    end)
    makeBtn(L("Import"), 62, function()
        if autoChk and CheckboxIsChecked(autoChk) then
            Diar:SetPlanAutoImport(entry.planKey, true)
        end
        entry.status = "accepted"
        Diar:HidePlanUpdatePopup()
        if Diar.ShowImportProgress then
            Diar:ShowImportProgress(true, 0, nil, L("Importing plan update..."))
        end
        Diar:TryCompletePlanUpdate(entry.id)
    end)

    f:SetScript("OnHide", function()
        if Diar._planUpdatePopup == f then
            Diar._planUpdatePopup = nil
        end
    end)

    self._planUpdatePopup = f
    if Diar.PrepareModal then
        Diar:PrepareModal(f, self.plannerFrame or self.frame)
    end
    f:ClearAllPoints()
    f:SetPoint("CENTER")
    f:Show()
    PlaySound(3190, "master")
end

function Diar:HandlePlanUpdatePush(msg, sender, channel)
    local parts = SplitSep(msg)
    if parts[1] ~= "PUSH" or #parts < 4 then return end
    local transferId, planKey, planName, planId = parts[2], parts[3], parts[4], parts[5]
    local mode = (parts[6] == "scene" and "scene")
        or (parts[6] == "move" and "move")
        or (parts[6] == "items" and "items")
        or (parts[6] == "scenes" and "scenes")
        or (parts[6] == "scenerm" and "scenerm")
        or "full"
    local sceneIndex = tonumber(parts[7] or "")
    local baseVersion = tonumber(parts[8] or "")
    local newVersion = tonumber(parts[9] or "")
    if not transferId or transferId == "" or not planKey or planKey == "" then return end
    if not self:ReceiverHasMatchingPlan(planKey, { planId = planId, channel = channel }) then return end
    if mode == "scene" and (not sceneIndex or sceneIndex < 1) then
        mode = "full"
    end
    PushDebug(("Recv PUSH id=%s mode=%s scene=%s from=%s channel=%s baseVer=%s newVer=%s"):format(
        tostring(transferId),
        tostring(mode),
        tostring(sceneIndex or ""),
        tostring(SenderLabel(sender)),
        tostring(channel or ""),
        tostring(baseVersion or "-"),
        tostring(newVersion or "-")
    ))

    PrunePlanUpdates(self)
    self._planUpdates = self._planUpdates or {}
    local status = self:IsPlanAutoImportEnabled(planKey, planId) and "auto" or "pending"
    self._planUpdates[transferId] = {
        id = transferId,
        planKey = planKey,
        planName = planName,
        planId = planId,
        sender = sender,
        chunks = {},
        total = nil,
        mode = mode,
        sceneIndex = sceneIndex,
        baseVersion = baseVersion,
        newVersion = newVersion,
        status = status,
        t = GetTime(),
    }

    if status == "auto" then
        if self.ShowImportProgress then
            self:ShowImportProgress(true, 0, nil, L("Importing plan update..."))
        end
        local label = (planName and planName ~= "") and planName or L("plan")
        print("|cff00aaff[Raidstrats.gg]|r " ..
            L("%s updated \"%s\" — importing..."):format(SenderLabel(sender), label))
    else
        self:ShowPlanUpdatePopup(self._planUpdates[transferId])
    end
end

function Diar:HandlePlanUpdateChunk(msg)
    local parts = SplitSep(msg)
    if parts[1] ~= "UPDD" or #parts < 5 then return end
    local transferId, iStr, nStr, chunk = parts[2], parts[3], parts[4], parts[5]
    local i, n = tonumber(iStr), tonumber(nStr)
    if not transferId or not i or not n or not chunk then return end

    PrunePlanUpdates(self)
    local entry = self._planUpdates and self._planUpdates[transferId]
    if not entry or entry.status == "declined" then return end

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

    self:TryCompletePlanUpdate(transferId)
end

function Diar:SendPlanUpdateChunks(chan, transferId, payload)
    if not chan or not transferId or not payload or payload == "" then return false end
    local prefix = self.COMM_PLAN_PREFIX or "RAIDSTRATS_PLAN"
    local total = math.ceil(#payload / PLAN_UPDATE_BATCH)
    for j = 1, total do
        local start = (j - 1) * PLAN_UPDATE_BATCH + 1
        local chunk = payload:sub(start, start + PLAN_UPDATE_BATCH - 1)
        self:SendCommMessage(
            prefix,
            table.concat({ "UPDD", transferId, j, total, chunk }, SEP),
            chan,
            nil,
            "BULK"
        )
    end
    return true
end

function Diar:PushPlanUpdateToGroup()
    if not self.IsPushUpdateLeader or not self:IsPushUpdateLeader() then
        print("|cffff6666[Raidstrats.gg]|r " ..
            L("Only the party or raid leader can push plan updates."))
        return false
    end
    local chan = self.GetGroupChatChannel and self:GetGroupChatChannel()
    if not chan then
        print("|cffff6666[Raidstrats.gg]|r " ..
            L("Join a party, raid, or guild to push updates."))
        return false
    end

    local data = self.plannerData
    if not self:HasActiveSavedPlan() then
        print("|cffff6666[Raidstrats.gg]|r " .. L("No plan loaded to push."))
        return false
    end

    local previousData = nil
    if self.FindSavedPlanEntry then
        local entry = self:FindSavedPlanEntry(data)
        if entry and entry.data then
            previousData = CopyPlanData(entry.data)
        end
    end
    self:EnsurePlanInstanceKey(data)
    if self.PersistCurrentPlanToSaved then
        self:PersistCurrentPlanToSaved()
    end

    local planKey = self:GetPlanIdentityKey(data)
    if not planKey then
        print("|cffff6666[Raidstrats.gg]|r " ..
            L("Couldn't resolve a team instance for this plan. Reload the planner and try again."))
        return false
    end

    local transferId = string.format("%x%x", time(), math.random(0, 0xFFFFFF))
    local planName = tostring(data.planName or L("Raid plan")):gsub(SEP, "")
    local planId = (data.planId and tostring(data.planId) ~= "") and tostring(data.planId):gsub(SEP, "") or ""
    local prefix = self.COMM_PLAN_PREFIX or "RAIDSTRATS_PLAN"

    -- Version stamp lets receivers verify they share our exact base before applying a delta.
    local baseVersion = self:GetPlanSyncVersion(planKey)
    local newVersion = (tonumber(baseVersion) or 0) + 1

    local mode = "full"
    local sceneIndex = nil
    local payload = nil
    local deltaData = BuildPushBaselineData(self, data)
    local trackedBaseline = self:GetPlanPushBaseline(planKey)
    local hasTrackedBaseline = trackedBaseline and true or false
    local deltaBase = trackedBaseline
    if not deltaBase and previousData then
        deltaBase = BuildPushBaselineData(self, previousData)
    end
    if not deltaData then
        print("|cffff6666[Raidstrats.gg]|r " .. L("Couldn't prepare the plan update."))
        return false
    end
    local objectMoves, moveReason = nil, nil
    if deltaBase and deltaData then
        objectMoves, moveReason = BuildObjectMoveDelta(deltaBase, deltaData)
    end
    if objectMoves and #objectMoves > 0 then
        local movePayload = EncodeObjectMoveDeltaPayload(objectMoves)
        if movePayload and movePayload ~= "" then
            mode = "move"
            payload = movePayload
            PushDebug(("Push select mode=move moves=%d"):format(#objectMoves))
        else
            PushDebug("Move delta detected but payload encode failed -> fallback")
        end
    elseif previousData then
        PushDebug(("Move delta unavailable: %s"):format(tostring(moveReason or "unknown reason")))
    end
    local itemDelta, itemReason = nil, nil
    if not payload and deltaBase and deltaData then
        itemDelta, itemReason = BuildItemDelta(deltaBase, deltaData)
    end
    if not payload and itemDelta then
        local itemPayload = EncodeItemDeltaPayload(itemDelta)
        if itemPayload and itemPayload ~= "" then
            mode = "items"
            payload = itemPayload
            local firstOp = itemDelta.scenes[1]
            PushDebug(("Push select mode=items scenes=%d scene1=%s add=%d rem=%d set=%d"):format(
                #itemDelta.scenes,
                tostring(firstOp and firstOp.sceneIndex or "?"),
                firstOp and #(firstOp.add or {}) or 0,
                firstOp and #(firstOp.rem or {}) or 0,
                firstOp and #(firstOp.set or {}) or 0
            ))
        else
            PushDebug("Item delta detected but payload encode failed -> fallback")
        end
    elseif not payload and previousData then
        PushDebug(("Item delta unavailable: %s"):format(tostring(itemReason or "unknown reason")))
    end
    local changedScene, sceneReason = nil, nil
    if deltaBase and deltaData then
        changedScene, sceneReason = FindSingleChangedSceneIndex(deltaBase, deltaData)
    end
    if not payload and changedScene and type(deltaData.scenes) == "table" and type(deltaData.scenes[changedScene]) == "table" then
        local scenePayload = EncodeSceneDeltaPayload(deltaData.scenes[changedScene])
        if scenePayload and scenePayload ~= "" then
            mode = "scene"
            sceneIndex = changedScene
            payload = scenePayload
            PushDebug(("Push select mode=scene scene=%d"):format(changedScene))
        else
            PushDebug("Scene delta detected but payload encode failed -> fallback")
        end
    elseif not payload and previousData then
        PushDebug(("Scene delta unavailable: %s"):format(tostring(sceneReason or "unknown reason")))
    end
    local removeDelta, removeReason = nil, nil
    if not payload and deltaBase and deltaData then
        removeDelta, removeReason = BuildSceneRemoveDelta(deltaBase, deltaData)
    end
    if not payload and removeDelta then
        local removePayload = EncodeSceneRemoveDeltaPayload(removeDelta)
        if removePayload and removePayload ~= "" then
            mode = "scenerm"
            payload = removePayload
            PushDebug(("Push select mode=scenerm removed=%d"):format(#removeDelta.removed))
        else
            PushDebug("Scene-remove delta detected but payload encode failed -> fallback")
        end
    elseif not payload and previousData then
        PushDebug(("Scene-remove delta unavailable: %s"):format(tostring(removeReason or "unknown reason")))
    end
    local scenesDelta, scenesReason = nil, nil
    if not payload and deltaBase and deltaData then
        scenesDelta, scenesReason = BuildSceneStructureDelta(deltaBase, deltaData)
    end
    if not payload and scenesDelta then
        local scenesPayload = EncodeScenesDeltaPayload(scenesDelta)
        if scenesPayload and scenesPayload ~= "" then
            mode = "scenes"
            payload = scenesPayload
            PushDebug(("Push select mode=scenes ops=%d count=%d"):format(#scenesDelta.ops, scenesDelta.count))
        else
            PushDebug("Scenes delta detected but payload encode failed -> fallback")
        end
    elseif not payload and previousData then
        PushDebug(("Scenes delta unavailable: %s"):format(tostring(scenesReason or "unknown reason")))
    end
    if not payload then
        if hasTrackedBaseline and deltaBase and TableDeepEqual(deltaBase, deltaData) then
            PushDebug("Push skipped: no changes since last pushed state")
            print("|cffffff99[Raidstrats.gg]|r " .. L("No changes to push."))
            return false
        end
        if not hasTrackedBaseline then
            PushDebug("No prior push baseline for this plan key -> sending full")
        elseif deltaBase and deltaData then
            local diffKey = FirstPlanMetaDiffKey(deltaBase, deltaData)
            if diffKey then
                PushDebug(("Full fallback: top-level plan field changed -> '%s'"):format(tostring(diffKey)))
            else
                PushDebug("Full fallback: scene structure changed on every scene")
            end
        end
        -- Push tracks its own version below, so don't let the share builder bump it.
        payload = self.BuildSharePayload and self:BuildSharePayload(data, { skipSyncVersionStamp = true })
        if not payload or payload == "" then
            print("|cffff6666[Raidstrats.gg]|r " .. L("Couldn't prepare the plan update."))
            return false
        end
        PushDebug("Push select mode=full")
    end

    self:SendCommMessage(
        prefix,
        table.concat({
            "PUSH", transferId, planKey, planName, planId, mode, sceneIndex or "",
            tostring(baseVersion or ""), tostring(newVersion),
        }, SEP),
        chan,
        nil,
        "BULK"
    )
    self:SendPlanUpdateChunks(chan, transferId, payload)
    PushDebug(("Sent PUSH id=%s mode=%s bytes=%d baseVer=%s newVer=%s"):format(
        tostring(transferId), tostring(mode), #payload,
        tostring(baseVersion or "-"), tostring(newVersion)
    ))
    self:SetPlanPushBaseline(planKey, deltaData, newVersion)

    if mode == "move" then
        print("|cff00aaff[Raidstrats.gg]|r " ..
            L("Pushed move update for \"%s\" to %s."):format(planName, chan:lower()))
    elseif mode == "items" then
        print("|cff00aaff[Raidstrats.gg]|r " ..
            L("Pushed object update for \"%s\" to %s."):format(planName, chan:lower()))
    elseif mode == "scene" or mode == "scenes" or mode == "scenerm" then
        print("|cff00aaff[Raidstrats.gg]|r " ..
            L("Pushed scene update for \"%s\" to %s."):format(planName, chan:lower()))
    else
        print("|cff00aaff[Raidstrats.gg]|r " ..
            L("Pushed plan update for \"%s\" to %s."):format(planName, chan:lower()))
    end
    return true
end

function Diar:HasActiveSavedPlan()
    local data = self.plannerData
    if not data then return false end
    if data.planName == "No plan" then return false end
    if not data.savedEntryId then return false end
    if type(data.scenes) ~= "table" or #data.scenes == 0 then return false end
    return true
end

function Diar:UpdatePushUpdateButton()
    local pf = self.plannerFrame
    local btn = pf and pf.pushUpdateBtn
    local shareBtn = pf and pf.savedPlansShareBtn
    local hasActivePlan = self:HasActiveSavedPlan()

    if shareBtn then
        if hasActivePlan then
            shareBtn:Enable()
            shareBtn:SetAlpha(1)
            if shareBtn.label then shareBtn.label:SetTextColor(0.92, 0.92, 0.92) end
        else
            shareBtn:Disable()
            shareBtn:SetAlpha(0.45)
            if shareBtn.label then shareBtn.label:SetTextColor(0.55, 0.55, 0.55) end
        end
    end

    if not btn then return end
    local pushAllowed = hasActivePlan
        and self.IsPushUpdateLeader
        and self:IsPushUpdateLeader()
    if pushAllowed then
        btn:Enable()
        btn:SetAlpha(1)
        if btn.label then btn.label:SetTextColor(0.92, 0.92, 0.92) end
    else
        btn:Disable()
        btn:SetAlpha(0.45)
        if btn.label then btn.label:SetTextColor(0.55, 0.55, 0.55) end
    end
end
