-- Raidstrats.gg Planner - in-game help dialog
local addonName = ...
local AceAddon = LibStub("AceAddon-3.0")
local Addon =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)
if not Addon then return end
local Diar = Addon
local SetBackdrop = Diar.SetBackdrop
local CreateButton = Diar.CreateButton
local PUI = Diar.PlannerUI
local UI = PUI.UI
local CreatePlannerIconBtn = PUI.CreatePlannerIconBtn
local SCENE_TAB_H = PUI.SCENE_TAB_H

local HELP_NOTE =
    "Note: This system was made for assignments, not all shapes and icons are supported from Raidstrats. "
    .. "It's recommended to simply use circles and add indexes to them."

local function IsPlanLoaded()
    local data = Diar and Diar.plannerData
    if not data then return false end
    if data.savedEntryId then return true end
    return tostring(data.planName or "") ~= "No plan"
end

local HELP_SECTIONS = {
    {
        title = "Get a plan on raidstrats.gg",
        lines = {
            "Open raidstrats.gg/planner in your browser.",
            "Browse the library or build your own plan — place markers, shapes, and role icons on the boss arena.",
            "Save the plan when you are done. You can add multiple scenes for different phases.",
        },
    },
    {
        title = "Export for the addon",
        lines = {
            "In the web planner, open Export and choose Copy for addon.",
            "You get a long string starting with !raidstrats-addon-",
            "Copy that string — you will paste it into the addon on the next step.",
        },
    },
    {
        title = "Import in-game",
        lines = {
            "Open this planner and click Import Plan in the Plan Library (right panel).",
            "Paste the export string and confirm import.",
            "Your plan appears in the library. Click it to load.",
            "Raid leaders can also Share to Group or Push Update so the raid receives plans without pasting.",
        },
    },
    {
        title = "NSRT — automatic popups",
        lines = {
            "NSRT setup system guide: https://raidstrats.gg/addon",
            "Works with Northern Sky Raid Tools (NSRT). Add special rsgg lines to your NSRT note.",
            "Basic cue (everyone sees scene 1 at 11s in phase 1):",
            "  time:11;ph:1;rsgg;scene:1",
            "Define groups in the note, then reference them on a cue:",
            "  rsggGroup1: PlayerA PlayerB PlayerC",
            "  time:45;ph:1;rsgg;scene:2;tag:Group1",
            "Only players listed on the tag see that popup. Their assigned spot highlights green.",
        },
    },
    {
        title = "NSRT — tags and spot numbers",
        lines = {
            "Inline tag (positional): tag NameA NameB or tag:NameA NameB — spot 1, spot 2, etc.",
            "Group tag (single key): tag:Group1 — uses the rsggGroup1: roster line.",
            "Optional dur:4 on a cue sets how long the popup stays (seconds).",
            "Indexed tag (multiple per spot): tag 1: NameA NameB 2: NameC",
            "Spot numbers match Preview index on objects in the planner.",
            "Turn on Preview index in the bottom bar to see object numbers.",
            "Test your note outside raid with /rsggtest — also broadcasts to your group.",
            "Optional: /rsggtest 3183 2 for encounter 3183 phase 2.",
            "Timing (seconds before/after cue) is in Settings -> NSRT Timing.",
        },
    },
}

local function BuildHelpScrollContent(parent, width)
    local y = -8
    local lineH = 16
    local sectionGap = 14
    local titleGap = 6

    local note = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    note:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, y)
    note:SetWidth(width - 8)
    note:SetJustifyH("LEFT")
    note:SetWordWrap(true)
    note:SetNonSpaceWrap(false)
    note:SetText(HELP_NOTE)
    note:SetTextColor(1.00, 0.88, 0.45)
    local noteH = note:GetStringHeight() or lineH
    y = y - (noteH + sectionGap)

    for _, section in ipairs(HELP_SECTIONS) do
        local hdr = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        hdr:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, y)
        hdr:SetWidth(width - 8)
        hdr:SetJustifyH("LEFT")
        hdr:SetText(section.title)
        hdr:SetTextColor(unpack(UI.ACCENT))
        y = y - (lineH + titleGap)

        for _, line in ipairs(section.lines) do
            local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, y)
            fs:SetWidth(width - 8)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(true)
            fs:SetNonSpaceWrap(false)
            fs:SetText(line)
            fs:SetTextColor(0.78, 0.80, 0.84)
            local h = fs:GetStringHeight() or lineH
            y = y - (h + 4)
        end
        y = y - sectionGap
    end

    return math.max(1, -y + 12)
end

function Diar:EnsurePlannerHelpButton(pf)
    if not pf or not pf.toolbar or not pf.planLinkBtn then return end

    if not pf.newSceneBtn then
        local newSceneBtn = CreatePlannerIconBtn(pf.toolbar, "New Scene", 86, SCENE_TAB_H + 4)
        newSceneBtn:SetScript("OnClick", function()
            if not IsPlanLoaded() then
                print("|cffff6666[Raidstrats.gg]|r No plan loaded. Load a plan before adding scenes.")
                return
            end
            if Diar.ShowCreateSceneDialog then
                Diar:ShowCreateSceneDialog()
            elseif Diar.ShowCreatePlanDialog then
                Diar:ShowCreatePlanDialog({ sceneMode = true })
            end
        end)
        pf.newSceneBtn = newSceneBtn
    end

    if not pf.planHelpBtn then
        local helpBtn = CreatePlannerIconBtn(pf.toolbar, "Help", 52, SCENE_TAB_H + 4)
        helpBtn:SetScript("OnClick", function()
            Diar:ShowPlannerHelpDialog()
        end)
        pf.planHelpBtn = helpBtn
    end

    pf.planLinkBtn:ClearAllPoints()
    pf.planLinkBtn:SetPoint("RIGHT", pf.toolbar, "RIGHT", -8, 0)

    pf.planHelpBtn:ClearAllPoints()
    pf.planHelpBtn:SetPoint("RIGHT", pf.planLinkBtn, "LEFT", -6, 0)

    pf.newSceneBtn:ClearAllPoints()
    pf.newSceneBtn:SetPoint("RIGHT", pf.planHelpBtn, "LEFT", -6, 0)

    if pf.sceneTabsContainer then
        pf.sceneTabsContainer:ClearAllPoints()
        pf.sceneTabsContainer:SetPoint("TOPLEFT", pf.toolbar, "TOPLEFT", 8, -6)
        pf.sceneTabsContainer:SetPoint("BOTTOMRIGHT", pf.newSceneBtn, "BOTTOMLEFT", -10, 0)
    end

    if pf.newSceneBtn then
        local loaded = IsPlanLoaded()
        if loaded then
            pf.newSceneBtn:Enable()
            pf.newSceneBtn:SetAlpha(1)
            if pf.newSceneBtn.label then pf.newSceneBtn.label:SetTextColor(0.92, 0.92, 0.92) end
        else
            pf.newSceneBtn:Disable()
            pf.newSceneBtn:SetAlpha(0.45)
            if pf.newSceneBtn.label then pf.newSceneBtn.label:SetTextColor(0.55, 0.55, 0.55) end
        end
    end
end

function Diar:ShowPlannerHelpDialog()
    if not self.plannerHelpDialog then
        local f = CreateFrame("Frame", "RaidstratsPlannerHelpDialog", UIParent, "BackdropTemplate")
        f:SetSize(540, 520)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetFrameLevel(500)
        f:SetPoint("CENTER")
        f:SetMovable(true)
        f:EnableMouse(true)
        SetBackdrop(f, UI.PANEL, UI.BORDER, 2)
        tinsert(UISpecialFrames, "RaidstratsPlannerHelpDialog")
        f:SetScript("OnMouseDown", function(s, b) if b == "LeftButton" then s:StartMoving() end end)
        f:SetScript("OnMouseUp", function(s) s:StopMovingOrSizing() end)

        local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -4, -4)

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -16)
        title:SetText("Planner help")
        title:SetTextColor(0.92, 0.92, 0.92)

        local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
        subtitle:SetText("raidstrats.gg -> export -> import -> NSRT")
        subtitle:SetTextColor(0.50, 0.54, 0.60)

        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -52)
        scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 52)
        local child = CreateFrame("Frame", nil, scroll)
        child:SetWidth(480)
        local contentH = BuildHelpScrollContent(child, 480)
        child:SetHeight(contentH)
        scroll:SetScrollChild(child)
        if PUI.SkinPlannerScroll then PUI.SkinPlannerScroll(scroll) end
        f.scroll = scroll
        f.scrollChild = child

        local btnRow = CreateFrame("Frame", nil, f)
        btnRow:SetHeight(36)
        btnRow:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 18, 14)
        btnRow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 14)

        local closeAction = CreateButton and CreateButton(btnRow, "CLOSE") or CreateFrame("Button", nil, btnRow, "UIPanelButtonTemplate")
        if closeAction.SetText then closeAction:SetText("CLOSE") end
        closeAction:SetPoint("LEFT", btnRow, "LEFT", 0, 0)
        closeAction:SetPoint("RIGHT", btnRow, "RIGHT", 0, 0)
        closeAction:SetScript("OnClick", function() f:Hide() end)

        self.plannerHelpDialog = f
    end

    if self.PrepareModal then
        self:PrepareModal(self.plannerHelpDialog, self.plannerFrame)
    end
    if self.plannerHelpDialog.scroll then
        self.plannerHelpDialog.scroll:SetVerticalScroll(0)
    end
    self.plannerHelpDialog:Show()
end
