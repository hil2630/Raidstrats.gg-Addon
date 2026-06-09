-- Raidstrats.gg — addon version display and group version check
local addonName = ...
local AceAddon = LibStub("AceAddon-3.0")
local Raidstrats =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)

if not Raidstrats then return end

Raidstrats.ADDON_UPDATE_URL = "https://raidstrats.gg/addon"

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

local function ShowOutdatedAddonPopup(remoteVersion, senderName)
    local ours = Raidstrats:GetAddonVersion()
    local who = senderName and senderName ~= "" and (Ambiguate and Ambiguate(senderName, "short") or senderName) or "Someone"
    local url = Raidstrats.ADDON_UPDATE_URL or "https://raidstrats.gg/addon"

    if not StaticPopupDialogs then
        print(("|cffff9900[Raidstrats.gg]|r %s has v%s (you have v%s). Update: %s"):format(
            who, tostring(remoteVersion), tostring(ours), url))
        return
    end

    StaticPopupDialogs["RAIDSTRATSGG_VERSION_OUTDATED"] = StaticPopupDialogs["RAIDSTRATSGG_VERSION_OUTDATED"] or {
        button1 = "Copy link",
        button2 = "Later",
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        preferredIndex = 3,
    }

    local dialog = StaticPopupDialogs["RAIDSTRATSGG_VERSION_OUTDATED"]
    dialog.text = ("|cff00aaffRaidstrats.gg|r\n\n%s in your group is on |cff78a0ffv%s|r.\nYou have |cffff9900v%s|r.\n\nGet the latest addon at:\n|cff78a0ff%s|r"):format(
        who, tostring(remoteVersion), tostring(ours), url)
    dialog.button1 = "Copy link"
    dialog.button2 = "Later"
    dialog.OnAccept = function()
        if ChatEdit_InsertLink then
            ChatEdit_InsertLink(url)
        end
        print(("|cff00aaff[Raidstrats.gg]|r Update: |cff78a0ff|H%s|h[%s]|h|r"):format(url, url))
    end
    dialog.OnCancel = function() end

    if StaticPopup_Show then
        StaticPopup_Show("RAIDSTRATSGG_VERSION_OUTDATED")
    end
end

function Raidstrats:HandleAddonVersionComm(sender, remoteVersion)
    if not sender or sender == UnitName("player") then return end
    remoteVersion = tostring(remoteVersion or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if remoteVersion == "" then return end

    local ours = self:GetAddonVersion()
    if self:CompareAddonVersions(remoteVersion, ours) <= 0 then
        return
    end

    self._versionPromptSeen = self._versionPromptSeen or {}
    if self._versionPromptSeen[remoteVersion] then return end
    self._versionPromptSeen[remoteVersion] = true

    print(("|cffff9900[Raidstrats.gg]|r A newer addon is available (v%s — you have v%s)."):format(
        remoteVersion, ours))
    ShowOutdatedAddonPopup(remoteVersion, sender)
end

function Raidstrats:UpdatePlannerVersionLabel(pf)
    if not pf or not pf.versionLabel then return end
    local ver = self:GetAddonVersion()
    pf.versionLabel:SetText("Version " .. ver)
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
