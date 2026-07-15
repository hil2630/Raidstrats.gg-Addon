-- Raidstrats.gg — addon version display and group version check
local addonName = ...
local AceAddon = LibStub("AceAddon-3.0")
local Raidstrats =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)

if not Raidstrats then return end

local VERSION_BROADCAST_COOLDOWN = 45
local VERSION_COMM_TAG = "RSGGVER:"
local FALLBACK_ADDON_VERSION = "0.0.2"

local function ReadAddOnMetadata(name, field)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(name, field)
    end
    if type(GetAddOnMetadata) == "function" then
        return GetAddOnMetadata(name, field)
    end
    return nil
end

local function ParseVersionParts(version)
    local parts = {}
    for n in tostring(version or ""):gmatch("%d+") do
        parts[#parts + 1] = tonumber(n) or 0
    end
    if #parts == 0 then
        parts[1] = 0
    end
    return parts
end

function Raidstrats:CompareAddonVersions(a, b)
    local pa = ParseVersionParts(a)
    local pb = ParseVersionParts(b)
    local n = math.max(#pa, #pb)
    for i = 1, n do
        local va = pa[i] or 0
        local vb = pb[i] or 0
        if va > vb then return 1 end
        if va < vb then return -1 end
    end
    return 0
end

function Raidstrats:GetAddonVersion()
    if self._addonVersion then return self._addonVersion end
    local v = ReadAddOnMetadata(addonName, "Version")
    if not v or v == "" then
        v = ReadAddOnMetadata("Raidstratsgg", "Version")
    end
    self._addonVersion = (v and v ~= "") and v or FALLBACK_ADDON_VERSION
    return self._addonVersion
end

function Raidstrats:GetGroupVersionCheckChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

function Raidstrats:BroadcastAddonVersion(force)
    local chan = self:GetGroupVersionCheckChannel()
    if not chan then return false end
    local now = GetTime()
    if not force and self._versionBroadcastAt and (now - self._versionBroadcastAt) < VERSION_BROADCAST_COOLDOWN then
        return false
    end
    self._versionBroadcastAt = now
    local prefix = self.COMM_PLAN_PREFIX or "RAIDSTRATS_PLAN"
    local version = self:GetAddonVersion()
    self:SendCommMessage(prefix, VERSION_COMM_TAG .. version, chan, nil, "NORMAL")
    return true
end

local function PrintOutdatedAddonNotice(remoteVersion, _senderName)
    local ours = Raidstrats:GetAddonVersion()
    print(("|cffff9900[Raidstrats.gg]|r There's a new version available, your current version is %s and newer version is %s. Please update on Wago or CurseForge."):format(
        tostring(ours), tostring(remoteVersion)))
end

local VERSION_PROMPT_DEBOUNCE = 3

function Raidstrats:HandleAddonVersionComm(sender, remoteVersion)
    if not sender or sender == UnitName("player") then return end
    remoteVersion = tostring(remoteVersion or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if remoteVersion == "" then return end

    local ours = self:GetAddonVersion()
    if self:CompareAddonVersions(remoteVersion, ours) <= 0 then
        return
    end

    -- Only ever notify once per session. When several raiders broadcast newer
    -- (and possibly differing) versions at once, collect the highest one and
    -- print a single message after a short debounce.
    if self._versionPromptShown then return end

    if not self._pendingNewerVersion
        or self:CompareAddonVersions(remoteVersion, self._pendingNewerVersion) > 0 then
        self._pendingNewerVersion = remoteVersion
    end

    if self._versionPromptTimer then return end
    self._versionPromptTimer = C_Timer.NewTimer(VERSION_PROMPT_DEBOUNCE, function()
        Raidstrats._versionPromptTimer = nil
        if Raidstrats._versionPromptShown then return end
        local newest = Raidstrats._pendingNewerVersion
        Raidstrats._pendingNewerVersion = nil
        if not newest then return end
        if Raidstrats:CompareAddonVersions(newest, Raidstrats:GetAddonVersion()) <= 0 then
            return
        end
        Raidstrats._versionPromptShown = true
        PrintOutdatedAddonNotice(newest)
    end)
end

function Raidstrats:UpdatePlannerVersionLabel(pf)
    if not pf or not pf.versionLabel then return end
    local ver = self:GetAddonVersion()
    pf.versionLabel:SetText("v" .. tostring(ver or "0.0.2"))
end

function Raidstrats:InitVersionChecker()
    if self._versionCheckerFrame then return end

    local frame = CreateFrame("Frame")
    self._versionCheckerFrame = frame
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")

    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LOGIN" then
            Raidstrats:GetAddonVersion()
            if Raidstrats.plannerFrame and Raidstrats.UpdatePlannerVersionLabel then
                Raidstrats:UpdatePlannerVersionLabel(Raidstrats.plannerFrame)
            end
        end
        if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
            if Raidstrats.BroadcastAddonVersion then
                Raidstrats:BroadcastAddonVersion(false)
            end
        end
    end)

    C_Timer.After(5, function()
        if Raidstrats.BroadcastAddonVersion then
            Raidstrats:BroadcastAddonVersion(false)
        end
    end)
end
