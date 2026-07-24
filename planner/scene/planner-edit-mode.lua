-- Raidstrats.gg Planner - Edit Mode integration helpers
local addonName = ...
local AceAddon = LibStub("AceAddon-3.0")
local Addon =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)
if not Addon then return end

local Diar = Addon
local SetBackdrop = Diar.SetBackdrop

local function AddEditModeDebugLine(msg)
    Diar._editModeDebugLog = Diar._editModeDebugLog or {}
    local line = ("[%s] %s"):format(date("%H:%M:%S"), tostring(msg or ""))
    Diar._editModeDebugLog[#Diar._editModeDebugLog + 1] = line
    if #Diar._editModeDebugLog > 40 then
        table.remove(Diar._editModeDebugLog, 1)
    end
end

local function IsPlannerEditModeActive()
    local em = EditModeManagerFrame
    if not em then return false end
    if type(em.IsEditModeActive) == "function" then
        local ok, active = pcall(em.IsEditModeActive, em)
        if ok and active then return true end
    end
    return em:IsShown() == true
end

local function TryCallRegisterSystemFrame(manager, frame)
    if not manager or type(manager.RegisterSystemFrame) ~= "function" then return false end
    local calls = {
        { label = "RegisterSystemFrame(frame)", fn = function() return manager:RegisterSystemFrame(frame) end },
        { label = "RegisterSystemFrame(frame,name)", fn = function() return manager:RegisterSystemFrame(frame, "Raidstrats Compact") end },
        { label = "RegisterSystemFrame(name,frame)", fn = function() return manager:RegisterSystemFrame("Raidstrats Compact", frame) end },
        { label = "RegisterSystemFrame(frame,name,clamped)", fn = function() return manager:RegisterSystemFrame(frame, "Raidstrats Compact", true) end },
    }
    for i = 1, #calls do
        local ok, resultOrErr = pcall(calls[i].fn)
        AddEditModeDebugLine(("%s -> %s"):format(calls[i].label, ok and "OK" or ("ERR: " .. tostring(resultOrErr))))
        if ok then
            return true
        end
    end
    return false
end

function Diar:PrintEditModeDebug()
    local pf = self.plannerFrame
    print("|cff00aaff[Raidstrats.gg]|r EditMode debug snapshot:")
    print(("|cff00aaff[Raidstrats.gg]|r EditModeManagerFrame: %s"):format(tostring(EditModeManagerFrame ~= nil)))
    print(("|cff00aaff[Raidstrats.gg]|r IsEditModeActive: %s"):format(tostring(IsPlannerEditModeActive())))
    print(("|cff00aaff[Raidstrats.gg]|r plannerFrame: %s"):format(tostring(pf ~= nil)))
    print(("|cff00aaff[Raidstrats.gg]|r compactMode: %s"):format(tostring(pf and pf.compactMode)))
    print(("|cff00aaff[Raidstrats.gg]|r blizzRegisterTried: %s"):format(tostring(pf and pf._blizzEditModeRegisterTried)))
    print(("|cff00aaff[Raidstrats.gg]|r blizzRegistered: %s"):format(tostring(pf and pf._blizzEditModeRegistered)))
    print(("|cff00aaff[Raidstrats.gg]|r emeRegistered: %s"):format(tostring(pf and pf._editModeExpandedRegistered)))
    local log = self._editModeDebugLog or {}
    if #log == 0 then
        print("|cff00aaff[Raidstrats.gg]|r EditMode log is empty.")
    else
        print(("|cff00aaff[Raidstrats.gg]|r EditMode log (%d):"):format(#log))
        for i = 1, #log do
            print(("|cff00aaff[Raidstrats.gg]|r %s"):format(log[i]))
        end
    end
end

function Diar:ResetEditModeDebug()
    local pf = self.plannerFrame
    self._editModeDebugLog = {}
    if pf then
        pf._blizzEditModeRegisterTried = nil
        pf._blizzEditModeRegistered = nil
        pf._editModeExpandedRegistered = nil
    end
    AddEditModeDebugLine("Manual reset requested.")
    self:EnsurePlannerEditModeIntegration()
end

function Diar:TryRegisterPlannerWithBlizzardEditMode()
    -- Disabled: direct RegisterSystemFrame taints/breaks Blizzard EditMode.
    AddEditModeDebugLine("Direct Blizzard registration disabled (unsafe).")
    return false
end

local function CloseCompactPreviewOnEditModeExit(reason)
    local pf = Diar and Diar.plannerFrame
    if not pf or not pf.compactPreviewActive then return end
    if not Diar.EndCompactPositionPreview then return end
    AddEditModeDebugLine((reason or "EditMode exit") .. ": closing active compact preview.")
    Diar:EndCompactPositionPreview(false)
end

-- Never run Edit Mode UI work inline from Blizzard hooks: hooksecurefunc/HookScript
-- continuations taint the rest of EnterEditMode (party frames, health color, etc.).
local function DeferEditModeWork(fn)
    if type(fn) ~= "function" then return end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, fn)
    else
        fn()
    end
end

function Diar:UpdatePlannerEditModeState()
    local pf = self.plannerFrame
    local editModeActive = IsPlannerEditModeActive()
    if pf then
        if not editModeActive and pf.compactPreviewActive then
            CloseCompactPreviewOnEditModeExit("UpdatePlannerEditModeState")
        end
        local overlay = pf.editModeCompactOverlay
        if overlay then
            if editModeActive and pf.compactMode then
                overlay:Show()
                overlay:SetFrameLevel((pf:GetFrameLevel() or 1) + 50)
                if pf.resizeGrip then
                    pf.resizeGrip:Show()
                end
            else
                overlay:Hide()
            end
        end
    end
    DeferEditModeWork(function()
        if Diar and Diar.EnsureEditModeManagerShortcutButton then
            Diar:EnsureEditModeManagerShortcutButton()
        end
    end)
end

local function GetEditModeBasicOptionsContainer()
    local em = EditModeManagerFrame
    local account = em and em.AccountSettings
    local scrollChild = account and account.SettingsContainer and account.SettingsContainer.ScrollChild
    return scrollChild and scrollChild.BasicOptionsContainer or nil
end

local function GetEditModeMiscOptionsContainer()
    local em = EditModeManagerFrame
    local account = em and em.AccountSettings
    local scrollChild = account and account.SettingsContainer and account.SettingsContainer.ScrollChild
    local advanced = scrollChild and scrollChild.AdvancedOptionsContainer
    return advanced and advanced.MiscContainer or nil
end

local function IsCompactPreviewActive()
    local pf = Diar and Diar.plannerFrame
    return pf and pf.compactPreviewActive == true
end

local function SyncEditModeRaidstratsCheck(chk)
    if not chk then return end
    local checked = IsCompactPreviewActive()
    Diar._editModeCheckSyncing = true
    if type(chk.SetControlChecked) == "function" then
        pcall(chk.SetControlChecked, chk, checked)
    elseif chk.Button and type(chk.Button.SetChecked) == "function" then
        chk.Button:SetChecked(checked)
    elseif type(chk.SetChecked) == "function" then
        chk:SetChecked(checked)
    end
    Diar._editModeCheckSyncing = nil
end

local function OnEditModeRaidstratsChecked(isChecked, isUserInput)
    if Diar._editModeCheckSyncing then return end
    if isUserInput == false then return end
    AddEditModeDebugLine(("EditMode Raidstrats checkbox -> %s"):format(tostring(isChecked)))
    local pf = Diar and Diar.plannerFrame
    if isChecked then
        if Diar.StartCompactPositionPreview then
            Diar:StartCompactPositionPreview({ fromEditModeShortcut = true })
        end
    else
        if pf and pf.compactPreviewActive and Diar.EndCompactPositionPreview then
            Diar:EndCompactPositionPreview(false)
        end
    end
    SyncEditModeRaidstratsCheck(Diar._editModeRaidstratsCheck)
end

--- Open Blizzard Edit Mode and start the Raidstrats compact position preview.
function Diar:OpenWowEditModeForCompactPreview()
    if C_AddOns and type(C_AddOns.LoadAddOn) == "function" then
        pcall(C_AddOns.LoadAddOn, "Blizzard_EditMode")
    elseif UIParentLoadAddOn then
        pcall(UIParentLoadAddOn, "Blizzard_EditMode")
    end

    local em = EditModeManagerFrame
    if not em then
        print("|cffff6666[Raidstrats.gg]|r Edit Mode is not available.")
        return false
    end

    if self.EnsureGlobalEditModeManagerHooks then
        self:EnsureGlobalEditModeManagerHooks()
    end

    AddEditModeDebugLine("Opening Blizzard Edit Mode for compact preview.")
    if type(ShowUIPanel) == "function" then
        ShowUIPanel(em)
    elseif type(em.Show) == "function" then
        em:Show()
    end

    -- EnterEditMode must finish untainted first; start our preview next frame.
    DeferEditModeWork(function()
        if not Diar then return end
        if Diar.EnsureEditModeManagerShortcutButton then
            Diar:EnsureEditModeManagerShortcutButton()
        end
        local pf = Diar.plannerFrame
        if not (pf and pf.compactPreviewActive) and Diar.StartCompactPositionPreview then
            Diar:StartCompactPositionPreview({ fromEditModeShortcut = true })
        end
        SyncEditModeRaidstratsCheck(Diar._editModeRaidstratsCheck)
    end)
    return true
end

function Diar:LayoutEditModeRaidstratsCheck()
    local chk = self._editModeRaidstratsCheck
    if not chk then return end
    local em = EditModeManagerFrame
    if not em then return end

    -- Only touch our checkbox + its option container. Never call EditModeManagerFrame:Layout
    -- (that re-enters Blizzard setup and is a common CompactUnitFrame taint source).
    local showAdvanced = type(em.AreAdvancedOptionsEnabled) == "function" and em:AreAdvancedOptionsEnabled()
    local basic = GetEditModeBasicOptionsContainer()
    local misc = GetEditModeMiscOptionsContainer()
    local parent = (showAdvanced and misc) or basic
    if not parent then return end

    chk:SetParent(parent)
    chk.layoutIndex = showAdvanced and (chk.advancedLayoutIndex or 50) or (chk.basicLayoutIndex or 50)
    chk:Show()
    if type(parent.Layout) == "function" then
        pcall(parent.Layout, parent)
    end
    SyncEditModeRaidstratsCheck(chk)
end

function Diar:EnsureEditModeManagerShortcutButton()
    local em = EditModeManagerFrame
    if not em or not em.AccountSettings or not em.AccountSettings.SettingsContainer then
        return
    end

    -- Retire the old side logo button if it still exists from a prior load.
    if self._editModeCompactShortcutBtn then
        self._editModeCompactShortcutBtn:Hide()
        self._editModeCompactShortcutBtn:SetParent(nil)
        self._editModeCompactShortcutBtn = nil
        AddEditModeDebugLine("Removed legacy EditMode logo shortcut button.")
    end

    if not self._editModeRaidstratsCheck then
        -- Parent under SettingsContainer initially; we reparent into Basic/Misc ourselves.
        -- Do NOT inject into account.settingsCheckButtons — writing that table taints
        -- Blizzard's LayoutSettings iteration during EnterEditMode.
        local parent = em.AccountSettings.SettingsContainer
        local chk
        local created = pcall(function()
            chk = CreateFrame("Frame", "RaidstratsEditModeCompactCheck", parent, "EditModeManagerSettingCheckButtonTemplate")
        end)
        if not created or not chk then
            created = pcall(function()
                chk = CreateFrame("Frame", "RaidstratsEditModeCompactCheck", parent, "EditModeCheckButtonTemplate")
            end)
        end
        if not created or not chk then
            AddEditModeDebugLine("Could not create EditMode checkbox template.")
            return
        end

        -- Brand label: RAIDSTRATS + blue .GG (#60a5fa, same as overview tab).
        local label = "RAIDSTRATS|cff60a5fa.GG|r"
        chk.labelText = label
        chk.isBasicOption = true
        chk.basicLayoutIndex = 50
        chk.advancedLayoutIndex = 50
        if EditModeManagerOptionsCategory and EditModeManagerOptionsCategory.Misc then
            chk.category = EditModeManagerOptionsCategory.Misc
        end
        if chk.Label and chk.Label.SetText then
            chk.Label:SetText(label)
        end
        if type(chk.OnLoad) == "function" then
            pcall(chk.OnLoad, chk)
        end
        if chk.Label and chk.Label.SetText then
            chk.Label:SetText(label)
        end

        if type(chk.SetCallback) == "function" then
            chk:SetCallback(OnEditModeRaidstratsChecked)
        elseif chk.Button then
            chk.Button:SetScript("OnClick", function(btn)
                OnEditModeRaidstratsChecked(btn:GetChecked() and true or false, true)
            end)
        end
        if type(chk.SetMouseOverCallback) == "function" then
            chk:SetMouseOverCallback(function() end)
        end

        self._editModeRaidstratsCheck = chk
        AddEditModeDebugLine("Created EditMode Raidstrats checkbox (manual layout, no Blizzard table inject).")

        local account = em.AccountSettings
        if not self._editModeLayoutSettingsHooked and type(account.LayoutSettings) == "function" then
            self._editModeLayoutSettingsHooked = true
            hooksecurefunc(account, "LayoutSettings", function()
                -- Deferred: running layout inline here taints the rest of EnterEditMode.
                DeferEditModeWork(function()
                    if Diar and Diar.LayoutEditModeRaidstratsCheck then
                        Diar:LayoutEditModeRaidstratsCheck()
                    end
                end)
            end)
        end
    end

    if IsPlannerEditModeActive() then
        self:LayoutEditModeRaidstratsCheck()
    elseif self._editModeRaidstratsCheck then
        SyncEditModeRaidstratsCheck(self._editModeRaidstratsCheck)
    end
end

function Diar:EnsureGlobalEditModeManagerHooks()
    if self._editModeManagerGlobalHooksInstalled then return end
    local em = EditModeManagerFrame
    if not em then return end
    self._editModeManagerGlobalHooksInstalled = true
    AddEditModeDebugLine("Installed global EditMode manager hooks.")

    if type(em.EnterEditMode) == "function" then
        hooksecurefunc(em, "EnterEditMode", function()
            DeferEditModeWork(function()
                if Diar and Diar.EnsureEditModeManagerShortcutButton then
                    Diar:EnsureEditModeManagerShortcutButton()
                end
            end)
        end)
    end
    if type(em.ExitEditMode) == "function" then
        hooksecurefunc(em, "ExitEditMode", function()
            DeferEditModeWork(function()
                CloseCompactPreviewOnEditModeExit("ExitEditMode")
                if Diar and Diar.EnsureEditModeManagerShortcutButton then
                    Diar:EnsureEditModeManagerShortcutButton()
                end
            end)
        end)
    end
    -- Intentionally no HookScript OnShow/OnHide on EditModeManagerFrame — those can
    -- taint Blizzard's show/enter path. EnterEditMode/ExitEditMode hooks are enough.
end

function Diar:EnsurePlannerEditModeIntegration()
    local pf = self.plannerFrame
    if not pf then return end
    AddEditModeDebugLine(("EnsurePlannerEditModeIntegration compact=%s shown=%s"):format(
        tostring(pf.compactMode), tostring(pf:IsShown())))

    if not pf.editModeCompactOverlay then
        local bar = CreateFrame("Frame", nil, pf, "BackdropTemplate")
        bar:SetHeight(24)
        bar:SetPoint("TOPLEFT", pf, "TOPLEFT", 6, -6)
        bar:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -6, -6)
        if SetBackdrop then
            SetBackdrop(bar, { 0.10, 0.18, 0.28, 0.94 }, { 0.34, 0.66, 1.0, 1 }, 1)
        end
        local txt = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        txt:SetPoint("LEFT", bar, "LEFT", 8, 0)
        txt:SetPoint("RIGHT", bar, "RIGHT", -8, 0)
        txt:SetJustifyH("CENTER")
        txt:SetTextColor(0.88, 0.95, 1)
        txt:SetText("Edit Mode: drag and resize Raidstrats compact frame")
        bar.text = txt
        bar:Hide()
        pf.editModeCompactOverlay = bar
    end

    if not self._plannerEditModeHooksInstalled and EditModeManagerFrame then
        self._plannerEditModeHooksInstalled = true
        AddEditModeDebugLine("Installed EditMode enter/exit hooks.")
        if type(EditModeManagerFrame.EnterEditMode) == "function" then
            hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
                DeferEditModeWork(function()
                    if Diar and Diar.UpdatePlannerEditModeState then
                        Diar:UpdatePlannerEditModeState()
                    end
                end)
            end)
        end
        if type(EditModeManagerFrame.ExitEditMode) == "function" then
            hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
                DeferEditModeWork(function()
                    if Diar and Diar.UpdatePlannerEditModeState then
                        Diar:UpdatePlannerEditModeState()
                    end
                end)
            end)
        end
    end

    if self.EnsureGlobalEditModeManagerHooks then
        self:EnsureGlobalEditModeManagerHooks()
    end
    DeferEditModeWork(function()
        if Diar and Diar.EnsureEditModeManagerShortcutButton then
            Diar:EnsureEditModeManagerShortcutButton()
        end
    end)

    -- Optional native integration when EditModeExpanded library is installed.
    if not pf._editModeExpandedRegistered and LibStub and type(LibStub.GetLibrary) == "function" then
        local ok, lib = pcall(LibStub.GetLibrary, LibStub, "EditModeExpanded-1.0", true)
        if ok and lib and type(lib.RegisterFrame) == "function" then
            local s = self:GetPlannerSettings()
            s.editModeCompactFrame = s.editModeCompactFrame or {}
            local regOk = pcall(lib.RegisterFrame, lib, pf, "Raidstrats Compact", s.editModeCompactFrame, UIParent, "BOTTOMLEFT", true)
            if regOk then
                pf._editModeExpandedRegistered = true
                AddEditModeDebugLine("EditModeExpanded registration succeeded.")
            else
                AddEditModeDebugLine("EditModeExpanded registration failed.")
            end
        elseif ok then
            AddEditModeDebugLine("EditModeExpanded library present but RegisterFrame missing.")
        else
            AddEditModeDebugLine("EditModeExpanded library unavailable.")
        end
    end

    self:UpdatePlannerEditModeState()
end

-- Create/show the EditMode manager shortcut whenever Blizzard EditMode loads.
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(_, event, arg1)
        if event == "PLAYER_LOGIN" or (event == "ADDON_LOADED" and arg1 == "Blizzard_EditMode") then
            if Diar and Diar.EnsureGlobalEditModeManagerHooks then
                Diar:EnsureGlobalEditModeManagerHooks()
            end
            DeferEditModeWork(function()
                if Diar and Diar.EnsureEditModeManagerShortcutButton then
                    Diar:EnsureEditModeManagerShortcutButton()
                end
            end)
        end
    end)
end
