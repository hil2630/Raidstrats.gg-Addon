local addonName, NS = ...
if type(NS) ~= "table" then return end
local AceAddon = LibStub("AceAddon-3.0")
local Addon =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)
-- Override our images to spell icons instead gg. 
NS.CUSTOM_RENDER_SPELL_BY_SRC = NS.CUSTOM_RENDER_SPELL_BY_SRC or {
    ["icon/raids/manaforge omega/bosses/beloren_child_of_alar/untitled-3_0000s_0000_layer-34.png"] = 1253022,
    ["raids/manaforge omega/bosses/beloren_child_of_alar/untitled-3_0000s_0000_layer-34"] = 1253022,
}

local function UrlDecodeSimple(value)
    if type(value) ~= "string" or value == "" then return value end
    return (value:gsub("%%(%x%x)", function(hex)
        local n = tonumber(hex, 16)
        if not n then return "%" .. hex end
        return string.char(n)
    end))
end

local function NormalizeSrcKey(src)
    if type(src) ~= "string" or src == "" then return nil end
    local s = src:lower():gsub("\\", "/")
    s = s:gsub("^https?://[^/]+", "")
    s = s:gsub("[?#].*$", "")
    s = s:gsub("^/+", "")
    if s == "" then return nil end
    return s
end

function NS.ResolveCustomSpellIdFromSrc(src)
    if type(src) ~= "string" or src == "" then return nil end
    local map = NS.CUSTOM_RENDER_SPELL_BY_SRC
    if type(map) ~= "table" then return nil end

    local function tryKeyVariants(base)
        if not base or base == "" then return nil end
        local variants = { base }
        if not base:find("^icon/", 1, true) then
            variants[#variants + 1] = "icon/" .. base
        else
            variants[#variants + 1] = base:gsub("^icon/", "")
        end
        if not base:match("%.[a-z0-9]+$") then
            variants[#variants + 1] = base .. ".png"
            variants[#variants + 1] = base .. ".jpg"
            variants[#variants + 1] = base .. ".webp"
        else
            variants[#variants + 1] = base:gsub("%.[a-z0-9]+$", "")
        end
        for i = 1, #variants do
            local id = map[variants[i]]
            if id then return id end
        end
        return nil
    end

    local key = NormalizeSrcKey(src)
    local id = tryKeyVariants(key)
    if id then return id end

    local decoded = NormalizeSrcKey(UrlDecodeSimple(src))
    if decoded and decoded ~= key then
        id = tryKeyVariants(decoded)
        if id then return id end
    end
    return nil
end

if Addon then
    Addon.ResolveCustomSpellIdFromSrc = NS.ResolveCustomSpellIdFromSrc
end

