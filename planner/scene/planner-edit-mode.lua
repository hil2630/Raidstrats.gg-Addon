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
local RSGG_TITLE_TEXTURE = "Interface\\AddOns\\" .. tostring(addonName) .. "\\title.tga"
local RSGG_TITLE_W = 523
local RSGG_TITLE_H = 52
local RSGG_TITLE_SCALE = 0.36 -- Match size used in CreateMainWindow logo.
local RSGG_BTN_W = math.floor(RSGG_TITLE_H * RSGG_TITLE_SCALE + 0.5) -- rotated vertical
local RSGG_BTN_H = math.floor(RSGG_TITLE_W * RSGG_TITLE_SCALE + 0.5)

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

function Diar:UpdatePlannerEditModeState()
    local pf = self.plannerFrame
    if pf then
        local overlay = pf.editModeCompactOverlay
        if overlay then
            if IsPlannerEditModeActive() and pf.compactMode then
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
    if self.EnsureEditModeManagerShortcutButton then
        self:EnsureEditModeManagerShortcutButton()
    end
end

function Diar:EnsureEditModeManagerShortcutButton()
    local em = EditModeManagerFrame
    if not em then return end
    if not self._editModeCompactShortcutBtn then
        local btn = CreateFrame("Button", nil, em, "BackdropTemplate")
        btn:SetSize(RSGG_BTN_W, RSGG_BTN_H)
        btn:SetPoint("RIGHT", em, "LEFT", -6, 0)
        btn:SetFrameStrata("TOOLTIP")
        btn:SetFrameLevel((em:GetFrameLevel() or 1) + 120)
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(btn)
        icon:SetTexture(RSGG_TITLE_TEXTURE)
        -- Rotate via texcoords to avoid SetRotation squish/distortion.
        -- 180deg from previous orientation.
        icon:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1)
        icon:SetVertexColor(1, 1, 1, 1)
        btn.icon = icon
        btn:SetScript("OnClick", function()
            AddEditModeDebugLine("EditMode manager shortcut button clicked.")
            local pf = Diar and Diar.plannerFrame
            if pf and pf.compactPreviewActive and Diar.EndCompactPositionPreview then
                Diar:EndCompactPositionPreview(false)
                return
            end
            if Diar.StartCompactPositionPreview then
                Diar:StartCompactPositionPreview({ fromEditModeShortcut = true })
            end
        end)
        btn:SetScript("OnEnter", function(s)
            if s.icon then
                s.icon:SetVertexColor(0.88, 0.96, 1.00, 1)
            end
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:SetText("Raidstrats compact positioning", 1, 1, 1)
            GameTooltip:AddLine("Click to toggle compact position mode.", 0.80, 0.88, 1.00, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(s)
            if s.icon then
                s.icon:SetVertexColor(1, 1, 1, 1)
            end
            GameTooltip:Hide()
        end)
        self._editModeCompactShortcutBtn = btn
        AddEditModeDebugLine("Created EditMode manager shortcut button.")
    else
        local btn = self._editModeCompactShortcutBtn
        btn:SetSize(RSGG_BTN_W, RSGG_BTN_H)
        btn:ClearAllPoints()
        btn:SetPoint("RIGHT", em, "LEFT", -6, 0)
        btn:SetFrameStrata("TOOLTIP")
        btn:SetFrameLevel((em:GetFrameLevel() or 1) + 120)
    end
    self._editModeCompactShortcutBtn:SetShown(IsPlannerEditModeActive())
end

function Diar:EnsureGlobalEditModeManagerHooks()
    if self._editModeManagerGlobalHooksInstalled then return end
    local em = EditModeManagerFrame
    if not em then return end
    self._editModeManagerGlobalHooksInstalled = true
    AddEditModeDebugLine("Installed global EditMode manager hooks.")

    if type(em.EnterEditMode) == "function" then
        hooksecurefunc(em, "EnterEditMode", function()
            if Diar and Diar.EnsureEditModeManagerShortcutButton then
                Diar:EnsureEditModeManagerShortcutButton()
            end
        end)
    end
    if type(em.ExitEditMode) == "function" then
        hooksecurefunc(em, "ExitEditMode", function()
            local pf = Diar and Diar.plannerFrame
            if pf and pf.compactPreviewActive and pf.__previewFromEditModeShortcut and Diar.EndCompactPositionPreview then
                AddEditModeDebugLine("ExitEditMode: closing active compact preview.")
                Diar:EndCompactPositionPreview(false)
            end
            if Diar and Diar.EnsureEditModeManagerShortcutButton then
                Diar:EnsureEditModeManagerShortcutButton()
            end
        end)
    end
    if type(em.HookScript) == "function" then
        em:HookScript("OnShow", function()
            if Diar and Diar.EnsureEditModeManagerShortcutButton then
                Diar:EnsureEditModeManagerShortcutButton()
            end
        end)
        em:HookScript("OnHide", function()
            local pf = Diar and Diar.plannerFrame
            if pf and pf.compactPreviewActive and pf.__previewFromEditModeShortcut and Diar.EndCompactPositionPreview then
                AddEditModeDebugLine("EditMode frame hidden: closing active compact preview.")
                Diar:EndCompactPositionPreview(false)
            end
            if Diar and Diar.EnsureEditModeManagerShortcutButton then
                Diar:EnsureEditModeManagerShortcutButton()
            end
        end)
    end
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
                if Diar and Diar.UpdatePlannerEditModeState then
                    Diar:UpdatePlannerEditModeState()
                end
            end)
        end
        if type(EditModeManagerFrame.ExitEditMode) == "function" then
            hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
                if Diar and Diar.UpdatePlannerEditModeState then
                    Diar:UpdatePlannerEditModeState()
                end
            end)
        end
    end

    if self.EnsureEditModeManagerShortcutButton then
        self:EnsureEditModeManagerShortcutButton()
    end
    if self.EnsureGlobalEditModeManagerHooks then
        self:EnsureGlobalEditModeManagerHooks()
    end

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
            if Diar and Diar.EnsureEditModeManagerShortcutButton then
                Diar:EnsureEditModeManagerShortcutButton()
            end
        end
    end)
end
