-- Raidstrats.gg Planner - first-time onboarding tour
-- Shows a "first time?" prompt and, if accepted, walks the user through the
-- main pieces of the planner (canvas, library, new plan, raidcheck, etc.) with
-- a highlight ring + step popup, like a website product tour.
local addonName = ...
local AceAddon = LibStub("AceAddon-3.0")
local Addon =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)
if not Addon then return end
local Diar = Addon
local SetBackdrop = Diar.SetBackdrop
local PUI = Diar.PlannerUI
local UI = PUI.UI
local CreatePlannerIconBtn = PUI.CreatePlannerIconBtn

local TOUR_STRATA = "TOOLTIP"
local POPUP_GAP = 16

-- Each step's anchor is a function so it is resolved lazily against the live
-- planner frame. `side` controls popup placement: "AUTO" (beside the element),
-- or "CENTER" (overlay in the middle of the target). Steps whose anchor is
-- missing/hidden at runtime are skipped automatically.
local function BuildTourSteps()
    local pf = Diar.plannerFrame
    if not pf then return {} end
    return {
        {
            key = "welcome",
            side = "CENTER",
            anchor = function() return pf end,
            title = "Welcome to Raidstrats.gg!",
            text = "This quick tour points out the main parts of the planner so you know where everything is. Use Next / Back to move around, or Skip at any time.",
        },
        {
            key = "canvas",
            side = "CENTER",
            anchor = function() return pf.canvas end,
            title = "The Canvas",
            text = "Your raid plan is drawn here. Boss positions, player spots, paths and assignments all show on top of the encounter map.",
        },
        {
            key = "palette",
            side = "AUTO",
            anchor = function() return pf.paletteToggleBtn end,
            title = "The Palette",
            text = "Toggle the object palette to drag shapes, raid markers, role icons and text onto the canvas. It's how you build the actual plan.",
        },
        {
            key = "lock",
            side = "AUTO",
            anchor = function() return pf.canvasLockBtn end,
            title = "Lock / Unlock Canvas",
            text = "Lock the canvas to safely view and pan a plan without moving anything by accident. Unlock it again when you want to edit spots and paths.",
        },
        {
            key = "scenes",
            side = "AUTO",
            anchor = function() return pf.sceneTabsContainer end,
            title = "Scenes",
            text = "Each scene is a moment/phase of the fight. Click a tab to jump to it, or use \"New Scene\" to add another step to your plan.",
        },
        {
            key = "library",
            side = "AUTO",
            anchor = function() return pf.savedPlansPanel end,
            title = "Plan Library",
            text = "All of your saved and imported plans live here. Click a plan to load it. Right-click a plan to rename it, create a group, or remove it from a group. Hold Ctrl and click to select several plans at once (then right-click to group them all), and drag plans in or out of groups.",
        },
        {
            key = "newplan",
            side = "AUTO",
            anchor = function() return pf.savedPlansNewBtn end,
            title = "New Plan",
            text = "Start a fresh plan from scratch — pick an encounter and begin placing your raid.",
        },
        {
            key = "import",
            side = "AUTO",
            anchor = function() return pf.savedPlansImportBtn end,
            title = "Import a Plan",
            text = "Paste an import string from the Raidstrats.gg website or a teammate to load their plan instantly.",
        },
        {
            key = "share",
            side = "AUTO",
            anchor = function() return pf.savedPlansShareBtn end,
            title = "Share to Group",
            text = "Send the current plan straight to your party or raid so everyone can load it with one click.",
        },
        {
            key = "pushupdate",
            side = "AUTO",
            anchor = function() return pf.pushUpdateBtn end,
            title = "Push Update",
            text = "Already shared this plan? After making changes, click Push Update to send the newest version to everyone who has it — their copy updates in place, no re-import needed.",
        },
        {
            key = "raidcheck",
            side = "AUTO",
            anchor = function() return pf.raidCheckChk or pf.raidCheckLabel or pf.raidCheckBar end,
            title = "Raidcheck",
            text = "Raid leaders can see who has the plan open and push assignments on ready check, so everyone is on the same page before the pull.",
        },
        {
            key = "compact",
            side = "AUTO",
            anchor = function() return pf.modeToggleBtn end,
            title = "Compact View",
            text = "Switch to a small overlay that shows just your assignment during the fight. It can also open automatically via NSRT notes.",
        },
        {
            key = "settings",
            side = "AUTO",
            anchor = function() return pf.settingsBtn end,
            title = "Settings",
            text = "Fine-tune everything here: compact view, assignment colors, NSRT timing, ready-check options and more.",
        },
        {
            key = "finish",
            side = "AUTO",
            anchor = function()
                local mb = Diar.minimapBtn
                if mb and mb.IsShown and mb:IsShown() then return mb end
                return pf
            end,
            title = "You're all set!",
            text = "Open the planner anytime from this minimap button, or type /rsgg. You can replay this tour with /rsggtour. Happy raiding!",
        },
    }
end

function Diar:IsOnboardingTourCompleted()
    local s = self:GetPlannerSettings()
    return s.onboardingTourCompleted == true or s.onboardingTourCompleted == 1
end

function Diar:SetOnboardingTourCompleted(done)
    local s = self:GetPlannerSettings()
    s.onboardingTourCompleted = done and true or false
end

-- ------------------------------------------------------------------
-- Highlight ring
-- ------------------------------------------------------------------
local function EnsureTourHighlight()
    if Diar._tourHighlight then return Diar._tourHighlight end
    local hl = CreateFrame("Frame", "RaidstratsTourHighlight", UIParent)
    hl:SetFrameStrata(TOUR_STRATA)
    hl:SetFrameLevel(9000)
    hl:EnableMouse(false)
    hl:Hide()

    local accent = UI.ACCENT
    local thickness = 3
    local function MakeEdge()
        local t = hl:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(accent[1], accent[2], accent[3], 1)
        return t
    end
    local top, bottom, left, right = MakeEdge(), MakeEdge(), MakeEdge(), MakeEdge()
    top:SetPoint("TOPLEFT", hl, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", hl, "TOPRIGHT", 0, 0)
    top:SetHeight(thickness)
    bottom:SetPoint("BOTTOMLEFT", hl, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", hl, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(thickness)
    left:SetPoint("TOPLEFT", hl, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", hl, "BOTTOMLEFT", 0, 0)
    left:SetWidth(thickness)
    right:SetPoint("TOPRIGHT", hl, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", hl, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(thickness)

    local pulse = hl:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local a = pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.35)
    a:SetDuration(0.7)
    a:SetSmoothing("IN_OUT")
    hl.pulse = pulse

    Diar._tourHighlight = hl
    return hl
end

local function PositionHighlight(target)
    local hl = EnsureTourHighlight()
    if not target or not target.GetCenter or not target:GetCenter() then
        hl:Hide()
        return false
    end
    local pad = 4
    hl:ClearAllPoints()
    hl:SetPoint("TOPLEFT", target, "TOPLEFT", -pad, pad)
    hl:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", pad, -pad)
    hl:Show()
    if hl.pulse then hl.pulse:Play() end
    return true
end

-- ------------------------------------------------------------------
-- Step popup
-- ------------------------------------------------------------------
local function EnsureTourPopup()
    if Diar._tourPopup then return Diar._tourPopup end
    local f = CreateFrame("Frame", "RaidstratsTourPopup", UIParent, "BackdropTemplate")
    f:SetSize(320, 176)
    f:SetFrameStrata(TOUR_STRATA)
    f:SetFrameLevel(9100)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    SetBackdrop(f, UI.PANEL, UI.ACCENT, 2)
    f:Hide()

    local accentBar = f:CreateTexture(nil, "ARTWORK")
    accentBar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    accentBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    accentBar:SetHeight(3)
    accentBar:SetColorTexture(unpack(UI.ACCENT))

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -16)
    title:SetPoint("TOPRIGHT", f, "TOPRIGHT", -48, -16)
    title:SetJustifyH("LEFT")
    title:SetTextColor(0.98, 0.98, 0.98)
    f.title = title

    local step = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    step:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -18)
    step:SetJustifyH("RIGHT")
    step:SetTextColor(0.55, 0.60, 0.68)
    f.stepLabel = step

    local body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    body:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetTextColor(0.82, 0.85, 0.90)
    body:SetSpacing(3)
    f.body = body

    local skipBtn = CreatePlannerIconBtn(f, "Skip tour", 84, 24)
    skipBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 12)
    skipBtn:SetScript("OnClick", function() Diar:EndPlannerTour(true) end)
    f.skipBtn = skipBtn

    local nextBtn = CreatePlannerIconBtn(f, "Next", 74, 24)
    nextBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 12)
    nextBtn.selected = true
    nextBtn:SetBackdropColor(unpack(UI.ACCENT))
    nextBtn.label:SetTextColor(1, 1, 1)
    nextBtn:SetScript("OnClick", function() Diar:AdvanceTour(1) end)
    f.nextBtn = nextBtn

    local prevBtn = CreatePlannerIconBtn(f, "Back", 64, 24)
    prevBtn:SetPoint("RIGHT", nextBtn, "LEFT", -8, 0)
    prevBtn:SetScript("OnClick", function() Diar:AdvanceTour(-1) end)
    f.prevBtn = prevBtn

    Diar._tourPopup = f
    return f
end

local function PositionPopup(popup, target, side)
    popup:ClearAllPoints()
    if side == "CENTER" or not target or not target.GetCenter or not target:GetCenter() then
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        return
    end
    local cx = target:GetCenter()
    local screenCx = UIParent:GetWidth() / 2
    if cx and cx <= screenCx then
        -- Element is on the left half → place popup to its right.
        popup:SetPoint("LEFT", target, "RIGHT", POPUP_GAP, 0)
    else
        popup:SetPoint("RIGHT", target, "LEFT", -POPUP_GAP, 0)
    end
end

-- ------------------------------------------------------------------
-- Tour flow
-- ------------------------------------------------------------------
function Diar:ShowTourStep(index)
    if not self._tourActive or not self._tourSteps then return end
    local steps = self._tourSteps
    index = math.max(1, math.min(index, #steps))

    -- Skip forward over any steps whose anchor isn't available right now.
    local dir = (index >= (self._tourIndex or 1)) and 1 or -1
    local step = steps[index]
    local target = step and step.anchor and step.anchor()
    local guard = 0
    while step and (not target or (target.IsShown and not target:IsShown()) or (target.GetCenter and not target:GetCenter())) do
        index = index + dir
        guard = guard + 1
        if index < 1 or index > #steps or guard > #steps then
            -- Nothing valid left in this direction: finish gracefully.
            self:EndPlannerTour(true)
            return
        end
        step = steps[index]
        target = step and step.anchor and step.anchor()
    end
    if not step then return end

    self._tourIndex = index
    local popup = EnsureTourPopup()
    popup.title:SetText(step.title or "")
    popup.body:SetText(step.text or "")
    popup.stepLabel:SetText(("%d / %d"):format(index, #steps))

    PositionHighlight(target)

    local isLast = index >= #steps
    popup.nextBtn:SetText(isLast and "Finish" or "Next")
    if index <= 1 then
        popup.prevBtn:Hide()
    else
        popup.prevBtn:Show()
    end

    PositionPopup(popup, target, step.side or "AUTO")
    popup:Show()
    popup:Raise()
end

function Diar:AdvanceTour(delta)
    if not self._tourActive then return end
    local nextIndex = (self._tourIndex or 1) + (delta or 1)
    if nextIndex > #(self._tourSteps or {}) then
        self:EndPlannerTour(true)
        return
    end
    if nextIndex < 1 then nextIndex = 1 end
    self:ShowTourStep(nextIndex)
end

function Diar:StartPlannerTour()
    local steps = BuildTourSteps()
    if #steps == 0 then return false end
    local pf = self.plannerFrame
    if pf and not pf.__tourHideHooked then
        pf.__tourHideHooked = true
        pf:HookScript("OnHide", function()
            if Diar._tourActive then
                Diar:EndPlannerTour(false)
            end
        end)
    end
    self._tourActive = true
    self._tourSteps = steps
    self._tourIndex = 1
    self:ShowTourStep(1)
    return true
end

function Diar:EndPlannerTour(markComplete)
    self._tourActive = false
    self._tourSteps = nil
    self._tourIndex = nil
    if self._tourHighlight then
        if self._tourHighlight.pulse then self._tourHighlight.pulse:Stop() end
        self._tourHighlight:Hide()
    end
    if self._tourPopup then
        self._tourPopup:Hide()
    end
    if markComplete then
        self:SetOnboardingTourCompleted(true)
    end
end

-- ------------------------------------------------------------------
-- First-time prompt
-- ------------------------------------------------------------------
function Diar:ShowFirstTimePrompt()
    if self._tourActive then return end
    if self:IsOnboardingTourCompleted() then return end
    if not (self.plannerFrame and self.plannerFrame:IsShown()) then return end

    if not self._firstTimePrompt then
        local f = CreateFrame("Frame", "RaidstratsTourPrompt", UIParent, "BackdropTemplate")
        f:SetSize(360, 176)
        f:SetFrameStrata(TOUR_STRATA)
        f:SetFrameLevel(9200)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
        f:EnableMouse(true)
        f:SetClampedToScreen(true)
        SetBackdrop(f, UI.PANEL, UI.ACCENT, 2)

        local accentBar = f:CreateTexture(nil, "ARTWORK")
        accentBar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
        accentBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
        accentBar:SetHeight(3)
        accentBar:SetColorTexture(unpack(UI.ACCENT))

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", f, "TOP", 0, -18)
        title:SetText("Is this your first time?")
        title:SetTextColor(0.98, 0.98, 0.98)

        local body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        body:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -50)
        body:SetPoint("TOPRIGHT", f, "TOPRIGHT", -20, -50)
        body:SetJustifyH("CENTER")
        body:SetSpacing(3)
        body:SetText("Welcome to Raidstrats.gg! Would you like a short tour of the planner? You can always replay it later with /rsggtour.")
        body:SetTextColor(0.82, 0.85, 0.90)

        local yesBtn = CreatePlannerIconBtn(f, "Yes, show me around", 168, 28)
        yesBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 16)
        yesBtn.selected = true
        yesBtn:SetBackdropColor(unpack(UI.ACCENT))
        yesBtn.label:SetTextColor(1, 1, 1)
        yesBtn:SetScript("OnClick", function()
            f:Hide()
            Diar:StartPlannerTour()
        end)

        local noBtn = CreatePlannerIconBtn(f, "No thanks", 140, 28)
        noBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)
        noBtn:SetScript("OnClick", function()
            Diar:SetOnboardingTourCompleted(true)
            f:Hide()
        end)

        self._firstTimePrompt = f
    end

    self._firstTimePrompt:Show()
    self._firstTimePrompt:Raise()
end

-- Called at the end of ShowPlannerViewer when the planner opens normally.
function Diar:MaybeStartFirstTimeTour()
    if InCombatLockdown() then return end
    if self:IsOnboardingTourCompleted() then return end
    if self._tourPromptShownThisSession then return end
    if self._tourActive then return end
    local pf = self.plannerFrame
    if not pf or not pf:IsShown() then return end
    if pf.nsrtSceneActive or pf.compactMode then return end
    self._tourPromptShownThisSession = true
    C_Timer.After(0.4, function()
        Diar:ShowFirstTimePrompt()
    end)
end

-- Replay entry point: open the planner (normal mode) then start the tour.
function Diar:StartPlannerTourFromCommand()
    if InCombatLockdown() then
        print("|cffff9900[Raidstrats.gg]|r Can't start the tour during combat.")
        return
    end
    if self._firstTimePrompt then self._firstTimePrompt:Hide() end
    local pf = self.plannerFrame
    local needsOpen = not (pf and pf:IsShown()) or (pf and (pf.nsrtSceneActive or pf.compactMode))
    if needsOpen and self.ShowPlannerViewer then
        self:ShowPlannerViewer()
    end
    C_Timer.After(needsOpen and 0.35 or 0, function()
        Diar:EndPlannerTour(false)
        Diar:StartPlannerTour()
    end)
end
