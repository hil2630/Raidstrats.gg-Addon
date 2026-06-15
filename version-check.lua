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

local function EnsureVersionUpdateDialog()
    if Raidstrats._versionUpdateDialog then
        return Raidstrats._versionUpdateDialog
    end
    local SetBackdrop = Raidstrats.SetBackdrop
    local f = CreateFrame("Frame", "RaidstratsVersionUpdateDialog", UIParent, "BackdropTemplate")
    f:SetSize(430, 200)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(610)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    if SetBackdrop then
        SetBackdrop(f, { 0.04, 0.05, 0.08, 0.98 }, { 0.17, 0.45, 0.85, 1 }, 2)
    end
    tinsert(UISpecialFrames, "RaidstratsVersionUpdateDialog")

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -14)
    title:SetText("Raidstrats.gg Update Available")
    title:SetTextColor(0.92, 0.95, 1)
    f.title = title

    local body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -46)
    body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 50)
    body:SetJustifyH("CENTER")
    body:SetJustifyV("MIDDLE")
    body:SetWordWrap(true)
    body:SetTextColor(0.82, 0.86, 0.92)
    f.body = body

    local copyBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    copyBtn:SetSize(190, 30)
    copyBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 14)
    if SetBackdrop then
        SetBackdrop(copyBtn, { 0.15, 0.47, 0.90, 1 }, { 0.30, 0.62, 1, 1 }, 1)
    end
    local copyTxt = copyBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    copyTxt:SetPoint("CENTER")
    copyTxt:SetText("Okay")
    copyTxt:SetTextColor(1, 1, 1)
    copyBtn.label = copyTxt
    f.copyBtn = copyBtn

    local laterBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    laterBtn:SetSize(190, 30)
    laterBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 14)
    if SetBackdrop then
        SetBackdrop(laterBtn, { 0.10, 0.11, 0.15, 1 }, { 0.26, 0.28, 0.34, 1 }, 1)
    end
    local laterTxt = laterBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    laterTxt:SetPoint("CENTER")
    laterTxt:SetText("Later")
    laterTxt:SetTextColor(0.90, 0.92, 0.95)
    laterBtn.label = laterTxt
    f.laterBtn = laterBtn

    laterBtn:SetScript("OnClick", function() f:Hide() end)
    f:Hide()
    Raidstrats._versionUpdateDialog = f
    return f
end

local function ShowOutdatedAddonPopup(remoteVersion, senderName)
    local ours = Raidstrats:GetAddonVersion()
    local who = senderName and senderName ~= "" and (Ambiguate and Ambiguate(senderName, "short") or senderName) or "Someone"
    local url = Raidstrats.ADDON_UPDATE_URL or "https://raidstrats.gg/addon"

    if not CreateFrame then
        print(("|cffff9900[Raidstrats.gg]|r %s has v%s (you have v%s). Update: %s"):format(
            who, tostring(remoteVersion), tostring(ours), url))
        return
    end

    local dlg = EnsureVersionUpdateDialog()
    dlg.body:SetText("A new Raidstrats.gg addon update is available.\n\nDownload the latest version on CurseForge or Wago.")
    dlg.copyBtn:SetScript("OnClick", function()
        dlg:Hide()
    end)
    dlg:ClearAllPoints()
    dlg:SetPoint("CENTER", UIParent, "CENTER", 0, 90)
    dlg:Show()
    dlg:Raise()
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
