-- Raidstrats.gg Planner - user settings dialog and preferences
local addonName = ...
local AceAddon = LibStub("AceAddon-3.0")
local Addon =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)
if not Addon then return end
local Diar = Addon
local SetBackdrop = Diar.SetBackdrop
local CreateAnimatedCheckbox = Diar.CreateAnimatedCheckbox
local PUI = Diar.PlannerUI
local UI = PUI.UI
local CreatePlannerIconBtn = PUI.CreatePlannerIconBtn
local CheckboxIsChecked = PUI.CheckboxIsChecked
local SetColorSwatchTexture = PUI.SetColorSwatchTexture

local function SetPrimaryButtonStyle(btn)
    if not btn then return end
    btn.selected = true
    btn:SetBackdropColor(unpack(UI.ACCENT))
    if btn.label then
        btn.label:SetTextColor(1, 1, 1)
    end
end
function Diar:GetPlannerSettings()
    RaidstratsggSettings = RaidstratsggSettings or {}
    local s = RaidstratsggSettings
    if s.rsggShowBefore == nil then s.rsggShowBefore = 0 end
    if s.rsggShowAfter == nil then s.rsggShowAfter = 0 end
    if s.highlightMyName == nil then s.highlightMyName = true end
    if s.compactShowBackground == nil then s.compactShowBackground = true end
    if s.hideNsrtPlan == nil then
        if s.showNsrtPopups ~= nil then
            s.hideNsrtPlan = s.showNsrtPopups == false or s.showNsrtPopups == 0
        else
            s.hideNsrtPlan = false
        end
    end
    if s.debugMode == nil then s.debugMode = false end
    if s.showObjectPalette == nil then s.showObjectPalette = false end
    if s.compactSceneArrows == nil then s.compactSceneArrows = false end
    if s.compactZoomToAssignment == nil then s.compactZoomToAssignment = false end
    if s.compactAssignZoom == nil then s.compactAssignZoom = 1.7 end
    if s.classSpecCircleMode == nil then s.classSpecCircleMode = false end
    if s.compactPlanLibrary == nil then s.compactPlanLibrary = true end
    if s.hideRaidCheckNotifs == nil then s.hideRaidCheckNotifs = false end
    if type(s.assignMineFill) ~= "table" then s.assignMineFill = nil end
    if type(s.assignOtherFill) ~= "table" then s.assignOtherFill = nil end
    if type(s.assignMineRing) ~= "table" then s.assignMineRing = nil end
    if type(s.assignOtherRing) ~= "table" then s.assignOtherRing = nil end
    s.planAutoImport = s.planAutoImport or {}
    return s
end

local DEFAULT_ASSIGN_MINE_FILL  = { 0.15, 0.80, 0.24, 0.75 }
local DEFAULT_ASSIGN_MINE_RING  = { 0.20, 0.95, 0.30, 1.00 }
local DEFAULT_ASSIGN_OTHER_FILL = { 0.42, 0.45, 0.50, 0.55 }
local DEFAULT_ASSIGN_OTHER_RING = { 0.60, 0.63, 0.67, 1.00 }
local MIN_ASSIGN_FILL_ALPHA = 0.35
local MIN_ASSIGN_RING_ALPHA = 0.85

local function NormalizeAssignColor(raw, default)
    if type(raw) ~= "table" then return { default[1], default[2], default[3], default[4] } end
    local r = tonumber(raw[1]) or tonumber(raw.r) or default[1]
    local g = tonumber(raw[2]) or tonumber(raw.g) or default[2]
    local b = tonumber(raw[3]) or tonumber(raw.b) or default[3]
    local a = raw[4]
    if a == nil then a = raw.a end
    a = tonumber(a)
    if a == nil then a = default[4] end
    return { r, g, b, a }
end

local function AssignColorLuminance(c)
    return 0.299 * c[1] + 0.587 * c[2] + 0.114 * c[3]
end

local function EnsureAssignFillVisible(fill, minAlpha)
    return {
        fill[1], fill[2], fill[3],
        math.max(minAlpha or MIN_ASSIGN_FILL_ALPHA, fill[4] or 1),
    }
end

local function EnsureAssignRingVisible(fill, ring, minRingAlpha)
    ring = {
        ring[1], ring[2], ring[3],
        math.max(minRingAlpha or MIN_ASSIGN_RING_ALPHA, ring[4] or 1),
    }
    local maxDiff = 0
    for i = 1, 3 do
        local d = math.abs((fill[i] or 0) - (ring[i] or 0))
        if d > maxDiff then maxDiff = d end
    end
    if maxDiff >= 0.10 then return ring end
    local boost = AssignColorLuminance(fill) > 0.55 and -0.22 or 0.22
    return {
        math.min(1, math.max(0, ring[1] + boost)),
        math.min(1, math.max(0, ring[2] + boost)),
        math.min(1, math.max(0, ring[3] + boost)),
        ring[4],
    }
end

local function DeriveAssignRing(fill, fillDefault, ringDefault)
    local ring = {
        math.min(1, math.max(0, fill[1] + (ringDefault[1] - fillDefault[1]))),
        math.min(1, math.max(0, fill[2] + (ringDefault[2] - fillDefault[2]))),
        math.min(1, math.max(0, fill[3] + (ringDefault[3] - fillDefault[3]))),
        ringDefault[4] or 1,
    }
    return EnsureAssignRingVisible(fill, ring)
end

local function FinalizeAssignColors(fill, ring, fillDefault, ringDefault)
    fill = EnsureAssignFillVisible(NormalizeAssignColor(fill, fillDefault))
    if type(ring) == "table" then
        ring = EnsureAssignRingVisible(fill, NormalizeAssignColor(ring, ringDefault))
    else
        ring = DeriveAssignRing(fill, fillDefault, ringDefault)
    end
    return fill, ring
end

function Diar:GetAssignmentSpotColors()
    local s = self:GetPlannerSettings()
    local mineFill, mineRing = FinalizeAssignColors(
        s.assignMineFill, s.assignMineRing, DEFAULT_ASSIGN_MINE_FILL, DEFAULT_ASSIGN_MINE_RING)
    local otherFill, otherRing = FinalizeAssignColors(
        s.assignOtherFill, s.assignOtherRing, DEFAULT_ASSIGN_OTHER_FILL, DEFAULT_ASSIGN_OTHER_RING)
    return {
        mineFill = mineFill,
        mineRing = mineRing,
        otherFill = otherFill,
        otherRing = otherRing,
    }
end

local function SetColorSwatchTexture(tex, color)
    if not tex or not color then return end
    tex:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
end

function Diar:OpenPlannerColorPicker(anchor, color, onChange)
    if not ColorPickerFrame or not color then return end
    local r0, g0, b0, a0 = color[1], color[2], color[3], color[4] or 1
    ColorPickerFrame:Hide()
    ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    if anchor and anchor.GetFrameLevel then
        ColorPickerFrame:SetFrameLevel(anchor:GetFrameLevel() + 20)
    end
    ColorPickerFrame:SetClampedToScreen(true)

    local function apply(r, g, b, a)
        if onChange then onChange(r, g, b, a) end
    end

    if ColorPickerFrame.SetupColorPickerAndShow then
        local info = {
            r = r0, g = g0, b = b0,
            hasOpacity = true,
            opacity = a0,
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                apply(r, g, b, ColorPickerFrame:GetColorAlpha())
            end,
            opacityFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                apply(r, g, b, ColorPickerFrame:GetColorAlpha())
            end,
            cancelFunc = function()
                apply(r0, g0, b0, a0)
            end,
        }
        ColorPickerFrame:SetupColorPickerAndShow(info)
    else
        ColorPickerFrame.hasOpacity = true
        ColorPickerFrame.func = function()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            local a = OpacitySliderFrame and OpacitySliderFrame:GetValue() or a0
            apply(r, g, b, a)
        end
        ColorPickerFrame.opacityFunc = ColorPickerFrame.func
        ColorPickerFrame.opacity = a0
        ColorPickerFrame:SetColorRGB(r0, g0, b0)
        ColorPickerFrame.cancelFunc = function()
            apply(r0, g0, b0, a0)
        end
        ColorPickerFrame:Show()
    end
end

function Diar:IsObjectPaletteEnabled()
    local v = self:GetPlannerSettings().showObjectPalette
    if v == false or v == 0 then return false end
    return true
end

function Diar:IsCompactBackgroundEnabled()
    local v = self:GetPlannerSettings().compactShowBackground
    if v == false or v == 0 then return false end
    return true
end

function Diar:IsHighlightMyNameEnabled()
    local v = self:GetPlannerSettings().highlightMyName
    if v == false or v == 0 then return false end
    return true
end

function Diar:IsClassSpecCircleModeEnabled()
    local v = self:GetPlannerSettings().classSpecCircleMode
    if v == true or v == 1 then return true end
    return false
end

function Diar:IsCompactPlanLibraryEnabled()
    local v = self:GetPlannerSettings().compactPlanLibrary
    if v == true or v == 1 then return true end
    return false
end

function Diar:IsCompactSceneArrowsEnabled()
    local v = self:GetPlannerSettings().compactSceneArrows
    if v == false or v == 0 then return false end
    return true
end

function Diar:IsCompactZoomToAssignmentEnabled()
    local v = self:GetPlannerSettings().compactZoomToAssignment
    if v == true or v == 1 then return true end
    return false
end

function Diar:GetCompactAssignmentZoom()
    local v = tonumber(self:GetPlannerSettings().compactAssignZoom) or 1.7
    if v < 1.0 then v = 1.0 end
    if v > 3.0 then v = 3.0 end
    return v
end

function Diar:IsNsrtPopupsEnabled()
    local v = self:GetPlannerSettings().hideNsrtPlan
    if v == true or v == 1 then return false end
    return true
end

function Diar:GetRsggShowBefore()
    local v = self:GetPlannerSettings().rsggShowBefore
    if v == nil then return 0 end
    v = tonumber(v)
    if v == nil then return 0 end
    return math.max(0, v)
end

function Diar:GetRsggShowAfter()
    local v = self:GetPlannerSettings().rsggShowAfter
    if v == nil then return 0 end
    v = tonumber(v)
    if v == nil then return 0 end
    return math.max(0, v)
end

local function ParseSettingsSeconds(text)
    text = strtrim(text or "")
    if text == "" then return 0 end
    local n = tonumber(text)
    if n == nil then return nil end
    return math.max(0, math.floor(n + 0.0001))
end

function Diar:ShowPlannerSettingsDialog()
    local settings = self:GetPlannerSettings()

    if self.plannerSettingsDialog and not self.plannerSettingsDialog.__settingsV9 then
        self.plannerSettingsDialog:Hide()
        self.plannerSettingsDialog = nil
    end

    if not self.plannerSettingsDialog then
        local f = CreateFrame("Frame", "RaidstratsPlannerSettingsDialog", UIParent, "BackdropTemplate")
        f.__settingsV9 = true
        f:SetSize(468, 668)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetFrameLevel(500)
        f:SetPoint("CENTER")
        f:SetMovable(true)
        f:EnableMouse(true)
        SetBackdrop(f, UI.PANEL, UI.BORDER, 2)
        tinsert(UISpecialFrames, "RaidstratsPlannerSettingsDialog")
        f:SetScript("OnMouseDown", function(s, b) if b == "LeftButton" then s:StartMoving() end end)
        f:SetScript("OnMouseUp", function(s) s:StopMovingOrSizing() end)

        local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -4, -4)

        local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
        header:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
        header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
        header:SetHeight(56)
        SetBackdrop(header, UI.TOOLBAR, UI.BORDER, 1)

        local headerAccent = header:CreateTexture(nil, "ARTWORK")
        headerAccent:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
        headerAccent:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
        headerAccent:SetHeight(2)
        headerAccent:SetColorTexture(unpack(UI.ACCENT))

        local body = CreateFrame("Frame", nil, f, "BackdropTemplate")
        body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 8, -8)
        body:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -8, -8)
        body:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 48)
        body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 48)
        SetBackdrop(body, { 0.045, 0.048, 0.062, 0.96 }, UI.BORDER, 1)
        header:SetFrameLevel((body:GetFrameLevel() or 1) + 5)

        local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", header, "TOPLEFT", 14, -12)
        title:SetText("Planner Settings")
        title:SetTextColor(0.98, 0.98, 0.98)

        local subtitle = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
        subtitle:SetText("NSRT cues, display, and compact layout")
        subtitle:SetTextColor(0.82, 0.86, 0.93)

        local function AddSectionHeader(text, y)
            local hdr = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            hdr:SetPoint("TOPLEFT", body, "TOPLEFT", 12, y)
            hdr:SetText(string.upper(text))
            hdr:SetTextColor(unpack(UI.ACCENT))
            local line = body:CreateTexture(nil, "ARTWORK")
            line:SetHeight(1)
            line:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -4)
            line:SetPoint("TOPRIGHT", body, "TOPRIGHT", -12, y - 4)
            line:SetColorTexture(unpack(UI.BORDER))
            return y - 22
        end

        local function AddSecondsRow(y, labelText, key)
            local lbl = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            lbl:SetPoint("TOPLEFT", body, "TOPLEFT", 14, y)
            lbl:SetWidth(300)
            lbl:SetJustifyH("LEFT")
            lbl:SetText(labelText)
            lbl:SetTextColor(0.82, 0.84, 0.88)

            local box = CreateFrame("Frame", nil, body, "BackdropTemplate")
            box:SetSize(74, 24)
            box:SetPoint("TOPRIGHT", body, "TOPRIGHT", -14, y + 2)
            SetBackdrop(box, {0.03, 0.03, 0.05, 1}, UI.BORDER, 1)

            local eb = CreateFrame("EditBox", nil, box)
            eb:SetSize(36, 18)
            eb:SetPoint("LEFT", box, "LEFT", 8, 0)
            eb:SetFontObject(GameFontHighlightSmall)
            eb:SetAutoFocus(false)
            eb:SetNumeric(true)
            eb:SetMaxLetters(3)
            eb:SetTextColor(0.92, 0.92, 0.92)

            local unit = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            unit:SetPoint("RIGHT", box, "RIGHT", -8, 0)
            unit:SetText("sec")
            unit:SetTextColor(0.48, 0.52, 0.58)

            f[key] = eb
            return y - 30
        end

        local function AddCheckbox(y, key, text)
            local chk = CreateAnimatedCheckbox and CreateAnimatedCheckbox(body, text)
            if not chk then return y - 28 end
            chk:SetPoint("TOPLEFT", body, "TOPLEFT", 14, y)
            if chk.label then
                chk.label:SetFontObject("GameFontHighlightSmall")
                chk.label:SetTextColor(0.82, 0.84, 0.88)
            end
            f[key] = chk
            return y - 28
        end

        local function AddAssignmentColorRow(y, labelText, key, defaultColor)
            local lbl = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            lbl:SetPoint("TOPLEFT", body, "TOPLEFT", 14, y)
            lbl:SetWidth(300)
            lbl:SetJustifyH("LEFT")
            lbl:SetText(labelText)
            lbl:SetTextColor(0.82, 0.84, 0.88)

            local btn = CreateFrame("Button", nil, body, "BackdropTemplate")
            btn:SetSize(56, 24)
            btn:SetPoint("TOPRIGHT", body, "TOPRIGHT", -14, y + 2)
            SetBackdrop(btn, { 0.05, 0.05, 0.07, 1 }, UI.BORDER, 1)
            btn.swatch = btn:CreateTexture(nil, "ARTWORK")
            btn.swatch:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
            btn.swatch:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 3)
            btn.__color = { defaultColor[1], defaultColor[2], defaultColor[3], defaultColor[4] }
            SetColorSwatchTexture(btn.swatch, btn.__color)
            btn:SetScript("OnClick", function()
                Diar:OpenPlannerColorPicker(btn, btn.__color, function(r, g, b, a)
                    btn.__color = { r, g, b, a }
                    SetColorSwatchTexture(btn.swatch, btn.__color)
                end)
            end)
            f[key] = btn
            return y - 28
        end

        local function ClampAssignZoom(v)
            v = tonumber(v) or 1.7
            if v < 1.0 then v = 1.0 end
            if v > 3.0 then v = 3.0 end
            return v
        end

        local y = -18
        y = AddSectionHeader("NSRT timing", y)
        y = AddSecondsRow(y, "Show plan before cue", "beforeEdit")
        y = AddSecondsRow(y, "Keep plan visible after cue", "afterEdit")

        y = y - 8
        y = AddSectionHeader("Display", y)
        y = AddCheckbox(y, "highlightChk", "Highlight my name on the plan")
        y = AddCheckbox(y, "compactBgChk", "Show background in compact view")
        y = AddCheckbox(y, "classSpecCircleChk", "Render class/spec icons as circles")
        y = AddCheckbox(y, "compactSceneArrowsChk", "Arrows in compact mode")
        y = AddCheckbox(y, "compactZoomAssignChk", "Zoom to my assignment in compact mode")
        do
            -- Keep zoom controls directly under the zoom-toggle option.
            local rowY = y
            local zoomLabel = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            zoomLabel:SetPoint("TOPLEFT", body, "TOPLEFT", 34, rowY)
            zoomLabel:SetWidth(180)
            zoomLabel:SetJustifyH("LEFT")
            zoomLabel:SetText("Zoom level")
            zoomLabel:SetTextColor(0.72, 0.75, 0.80)
            f.compactAssignZoomLabel = zoomLabel

            local previewZoomBtn = CreatePlannerIconBtn(body, "Preview zoom", 118, 24)
            previewZoomBtn:SetPoint("TOPRIGHT", body, "TOPRIGHT", -14, rowY + 2)
            previewZoomBtn:SetScript("OnClick", function()
                if Diar.PreviewCompactAssignmentZoomFromSettings then
                    Diar:PreviewCompactAssignmentZoomFromSettings(f)
                end
            end)
            f.compactZoomPreviewBtn = previewZoomBtn

            local plusBtn = CreatePlannerIconBtn(body, "+", 24, 24)
            plusBtn:SetPoint("RIGHT", previewZoomBtn, "LEFT", -12, 0)
            local zoomValue = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            zoomValue:SetPoint("RIGHT", plusBtn, "LEFT", -10, 0)
            zoomValue:SetWidth(56)
            zoomValue:SetJustifyH("CENTER")
            zoomValue:SetTextColor(0.92, 0.92, 0.96)
            local minusBtn = CreatePlannerIconBtn(body, "-", 24, 24)
            minusBtn:SetPoint("RIGHT", zoomValue, "LEFT", -10, 0)
            f.compactAssignZoomValue = zoomValue

            local function RefreshAssignZoomValue()
                f.compactAssignZoom = ClampAssignZoom(f.compactAssignZoom)
                zoomValue:SetText(("%.2fx"):format(f.compactAssignZoom))
            end
            minusBtn:SetScript("OnClick", function()
                f.compactAssignZoom = ClampAssignZoom((f.compactAssignZoom or 1.7) - 0.10)
                RefreshAssignZoomValue()
                if Diar._compactZoomPreviewState and Diar.PreviewCompactAssignmentZoomFromSettings then
                    Diar:PreviewCompactAssignmentZoomFromSettings(f)
                end
            end)
            plusBtn:SetScript("OnClick", function()
                f.compactAssignZoom = ClampAssignZoom((f.compactAssignZoom or 1.7) + 0.10)
                RefreshAssignZoomValue()
                if Diar._compactZoomPreviewState and Diar.PreviewCompactAssignmentZoomFromSettings then
                    Diar:PreviewCompactAssignmentZoomFromSettings(f)
                end
            end)
            f.compactAssignZoomMinusBtn = minusBtn
            f.compactAssignZoomPlusBtn = plusBtn
            f.RefreshAssignZoomValue = RefreshAssignZoomValue
            y = y - 30
        end
        y = AddCheckbox(y, "compactLibraryChk", "Compact plan library")
        y = AddCheckbox(y, "nsrtPopupChk", "Hide plan popups (even if assigned)")
        y = AddCheckbox(y, "raidCheckNotifChk", "Hide raidcheck notifications from raid leader")
        y = AddCheckbox(y, "plannerDebugChk", "Show planner debug panel")

        y = y - 8
        y = AddSectionHeader("Assignment colors", y)
        y = AddAssignmentColorRow(y, "My assignment spot", "assignMineColorBtn", DEFAULT_ASSIGN_MINE_FILL)
        y = AddAssignmentColorRow(y, "Other assignment spots", "assignOtherColorBtn", DEFAULT_ASSIGN_OTHER_FILL)

        y = y - 8
        y = AddSectionHeader("Compact position", y)

        local compactStatus = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        compactStatus:SetPoint("TOPLEFT", body, "TOPLEFT", 14, y)
        compactStatus:SetWidth(290)
        compactStatus:SetJustifyH("LEFT")
        compactStatus:SetTextColor(0.67, 0.70, 0.75)
        f.compactPosStatus = compactStatus

        local previewBtn = CreatePlannerIconBtn(body, "Preview & Set", 148, 30)
        previewBtn:SetPoint("TOPRIGHT", body, "TOPRIGHT", -14, y - 2)
        SetPrimaryButtonStyle(previewBtn)
        previewBtn:SetScript("OnClick", function()
            -- Apply current Display controls immediately so Preview reflects
            -- what the user currently selected, even before Save.
            local s = Diar:GetPlannerSettings()
            s.highlightMyName = CheckboxIsChecked(f.highlightChk)
            s.compactShowBackground = CheckboxIsChecked(f.compactBgChk)
            s.classSpecCircleMode = CheckboxIsChecked(f.classSpecCircleChk)
            s.compactSceneArrows = CheckboxIsChecked(f.compactSceneArrowsChk)
            s.compactZoomToAssignment = CheckboxIsChecked(f.compactZoomAssignChk)
            s.compactAssignZoom = ClampAssignZoom(f.compactAssignZoom)
            f:Hide()
            if Diar.StartCompactPositionPreview then
                Diar:StartCompactPositionPreview()
            end
        end)
        f.compactPreviewBtn = previewBtn

        local btnRow = CreateFrame("Frame", nil, f)
        btnRow:SetHeight(30)
        btnRow:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 18, 14)
        btnRow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 14)

        local footerLine = f:CreateTexture(nil, "ARTWORK")
        footerLine:SetHeight(1)
        footerLine:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 46)
        footerLine:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 46)
        footerLine:SetColorTexture(unpack(UI.BORDER))

        local cancelBtn = CreatePlannerIconBtn(btnRow, "Cancel", 100, 28)
        cancelBtn:SetPoint("RIGHT", btnRow, "CENTER", -6, 0)
        cancelBtn:SetScript("OnClick", function() f:Hide() end)

        local saveBtn = CreatePlannerIconBtn(btnRow, "Save", 100, 28)
        saveBtn:SetPoint("LEFT", btnRow, "CENTER", 6, 0)
        SetPrimaryButtonStyle(saveBtn)
        saveBtn:SetScript("OnClick", function()
            local s = Diar:GetPlannerSettings()
            local before = ParseSettingsSeconds(f.beforeEdit:GetText())
            local after = ParseSettingsSeconds(f.afterEdit:GetText())
            if before == nil or after == nil then
                print("|cffff6666[Raidstrats.gg]|r Enter a number of seconds (0 or higher).")
                return
            end
            s.rsggShowBefore = before
            s.rsggShowAfter = after
            s.highlightMyName = CheckboxIsChecked(f.highlightChk)
            s.compactShowBackground = CheckboxIsChecked(f.compactBgChk)
            s.classSpecCircleMode = CheckboxIsChecked(f.classSpecCircleChk)
            s.compactSceneArrows = CheckboxIsChecked(f.compactSceneArrowsChk)
            s.compactZoomToAssignment = CheckboxIsChecked(f.compactZoomAssignChk)
            s.compactAssignZoom = ClampAssignZoom(f.compactAssignZoom)
            s.compactPlanLibrary = CheckboxIsChecked(f.compactLibraryChk)
            s.hideNsrtPlan = CheckboxIsChecked(f.nsrtPopupChk)
            s.hideRaidCheckNotifs = CheckboxIsChecked(f.raidCheckNotifChk)
            s.debugMode = CheckboxIsChecked(f.plannerDebugChk)
            if f.assignMineColorBtn and f.assignMineColorBtn.__color then
                local c = f.assignMineColorBtn.__color
                s.assignMineFill = { c[1], c[2], c[3], c[4] }
                local mineFill, mineRing = FinalizeAssignColors(
                    s.assignMineFill, nil, DEFAULT_ASSIGN_MINE_FILL, DEFAULT_ASSIGN_MINE_RING)
                s.assignMineFill = mineFill
                s.assignMineRing = mineRing
            end
            if f.assignOtherColorBtn and f.assignOtherColorBtn.__color then
                local c = f.assignOtherColorBtn.__color
                s.assignOtherFill = { c[1], c[2], c[3], c[4] }
                local otherFill, otherRing = FinalizeAssignColors(
                    s.assignOtherFill, nil, DEFAULT_ASSIGN_OTHER_FILL, DEFAULT_ASSIGN_OTHER_RING)
                s.assignOtherFill = otherFill
                s.assignOtherRing = otherRing
            end
            f.beforeEdit:SetText(tostring(before))
            f.afterEdit:SetText(tostring(after))
            local pf = Diar.plannerFrame
            if pf and pf.compactMode and Diar.SetPlannerCompactMode then
                pf.nsrtSceneActive = nil
                Diar:SetPlannerCompactMode(false)
            elseif pf and not pf.compactMode and Diar.ApplyPlannerNormalLayout then
                Diar.ApplyPlannerNormalLayout(pf, true)
                if Diar.ApplyObjectPaletteLayout then Diar:ApplyObjectPaletteLayout(pf) end
            end
            if pf and pf:IsShown() and not pf.nsrtSceneActive and Diar.ApplyNsrtAssignmentForPlannerView then
                Diar:ApplyNsrtAssignmentForPlannerView(pf.selectedSceneIndex or 1)
            end
            if Diar.RefreshPlannerScene then
                Diar:RefreshPlannerScene()
            end
            if Diar.RefreshSavedPlansList then
                Diar:RefreshSavedPlansList()
            end
            if Diar.UpdatePlannerDebugPanel then
                Diar:UpdatePlannerDebugPanel()
            end
            if Diar.UpdatePushUpdateButton then
                Diar:UpdatePushUpdateButton()
            end
            if s.debugMode and Diar.AppendPlannerDebugLine then
                Diar:AppendPlannerDebugLine("Planner debug mode enabled")
            end
            f:Hide()
        end)

        if f.HookScript then
            f:HookScript("OnHide", function()
                if Diar.EndCompactAssignmentZoomPreviewFromSettings then
                    Diar:EndCompactAssignmentZoomPreviewFromSettings()
                end
            end)
        end

        self.plannerSettingsDialog = f
    end

    local dlg = self.plannerSettingsDialog
    dlg.beforeEdit:SetText(tostring(settings.rsggShowBefore ~= nil and settings.rsggShowBefore or 0))
    dlg.afterEdit:SetText(tostring(settings.rsggShowAfter ~= nil and settings.rsggShowAfter or 0))
    dlg.highlightChk:SetChecked(self:IsHighlightMyNameEnabled())
    dlg.compactBgChk:SetChecked(self:IsCompactBackgroundEnabled())
    if dlg.classSpecCircleChk then
        dlg.classSpecCircleChk:SetChecked(self:IsClassSpecCircleModeEnabled())
    end
    if dlg.compactSceneArrowsChk then
        dlg.compactSceneArrowsChk:SetChecked(self:IsCompactSceneArrowsEnabled())
    end
    if dlg.compactZoomAssignChk then
        dlg.compactZoomAssignChk:SetChecked(self:IsCompactZoomToAssignmentEnabled())
    end
    if dlg.compactAssignZoomValue then
        dlg.compactAssignZoom = self:GetCompactAssignmentZoom()
        if dlg.RefreshAssignZoomValue then
            dlg:RefreshAssignZoomValue()
        end
    end
    if dlg.compactLibraryChk then
        dlg.compactLibraryChk:SetChecked(self:IsCompactPlanLibraryEnabled())
    end
    dlg.nsrtPopupChk:SetChecked(settings.hideNsrtPlan == true or settings.hideNsrtPlan == 1)
    if dlg.raidCheckNotifChk then
        dlg.raidCheckNotifChk:SetChecked(settings.hideRaidCheckNotifs == true or settings.hideRaidCheckNotifs == 1)
    end
    if dlg.plannerDebugChk then
        dlg.plannerDebugChk:SetChecked(settings.debugMode == true or settings.debugMode == 1)
    end
    if dlg.assignMineColorBtn then
        local c = NormalizeAssignColor(settings.assignMineFill, DEFAULT_ASSIGN_MINE_FILL)
        dlg.assignMineColorBtn.__color = { c[1], c[2], c[3], c[4] }
        SetColorSwatchTexture(dlg.assignMineColorBtn.swatch, c)
    end
    if dlg.assignOtherColorBtn then
        local c = NormalizeAssignColor(settings.assignOtherFill, DEFAULT_ASSIGN_OTHER_FILL)
        dlg.assignOtherColorBtn.__color = { c[1], c[2], c[3], c[4] }
        SetColorSwatchTexture(dlg.assignOtherColorBtn.swatch, c)
    end
    if dlg.compactPosStatus then
        if self:HasSavedCompactPosition() then
            dlg.compactPosStatus:SetText("Saved — used for NSRT compact scenes")
        else
            dlg.compactPosStatus:SetText("Not set — uses default position")
        end
    end
    local anchor = UIParent
    Diar:PrepareModal(dlg, anchor)
    dlg:ClearAllPoints()
    dlg:SetPoint("CENTER", UIParent, "CENTER")
    dlg:SetFrameStrata("FULLSCREEN_DIALOG")
    dlg:SetFrameLevel((anchor and anchor:GetFrameLevel() or 0) + 100)
    dlg:Raise()
    dlg:Show()
end

