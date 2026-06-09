-- Raidstrats.gg Planner - create new plan + arena picker
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

local ARENAS = {
    { key = "loom-ithar-phase-1", label = "Loom'ithar", raid = "Manaforge Omega", boss = "Loom'ithar", expansion = "The War Within" },
    { key = "forgeweaver-araz-phase-1", label = "Forgeweaver Araz", raid = "Manaforge Omega", boss = "Forgeweaver Araz", expansion = "The War Within" },
    { key = "fractilus-phase-1", label = "Fractilus", raid = "Manaforge Omega", boss = "Fractilus", expansion = "The War Within" },
    { key = "plexus-sentinel-phase-1", label = "Plexus Sentinel", raid = "Manaforge Omega", boss = "Plexus Sentinel", expansion = "The War Within" },
    { key = "souldbinder-naazindhri-phase-1", label = "Soulbinder Naazindhri", raid = "Manaforge Omega", boss = "Soulbinder Naazindhri", expansion = "The War Within" },
    { key = "the-soul-hunters-phase-1", label = "The Soul Hunters", raid = "Manaforge Omega", boss = "The Soul Hunters", expansion = "The War Within" },
    { key = "nexus-king-slahadaar-center", label = "Nexus-King Salhadaar (Center)", raid = "Manaforge Omega", boss = "Nexus-King Salhadaar", expansion = "The War Within" },
    { key = "nexus-king-slahadaar-full", label = "Nexus-King Salhadaar (Full)", raid = "Manaforge Omega", boss = "Nexus-King Salhadaar", expansion = "The War Within" },
    { key = "nexus-king-slahadaar-left", label = "Nexus-King Salhadaar (Left)", raid = "Manaforge Omega", boss = "Nexus-King Salhadaar", expansion = "The War Within" },
    { key = "nexus-king-slahadaar-right", label = "Nexus-King Salhadaar (Right)", raid = "Manaforge Omega", boss = "Nexus-King Salhadaar", expansion = "The War Within" },
    { key = "dimensius-heart", label = "Dimensius (Heart)", raid = "Manaforge Omega", boss = "Dimensius", expansion = "The War Within" },
    { key = "dimensius-seat", label = "Dimensius (Seat)", raid = "Manaforge Omega", boss = "Dimensius", expansion = "The War Within" },
    { key = "dimensius-conquest", label = "Dimensius (Conquest)", raid = "Manaforge Omega", boss = "Dimensius", expansion = "The War Within" },
    { key = "dimensius-entropy", label = "Dimensius (Entropy)", raid = "Manaforge Omega", boss = "Dimensius", expansion = "The War Within" },
    { key = "vorasius", label = "Vorasius", raid = "Liberation of Undermine", boss = "Vorasius", expansion = "The War Within" },
    { key = "vorasius_close", label = "Vorasius (Close)", raid = "Liberation of Undermine", boss = "Vorasius", expansion = "The War Within" },
    { key = "silkencourt", label = "Silkencourt", raid = "Nerub-ar Palace", boss = "Silkencourt", expansion = "The War Within" },
    { key = "chimera_l2", label = "Chimera", raid = "Nerub-ar Palace", boss = "Chimera", expansion = "The War Within" },
    { key = "Dreamrift", label = "Dreamrift", raid = "Amirdrassil", boss = "Dreamrift", expansion = "Dragonflight" },
    { key = "fallen-king_salhadaar", label = "Fallen King Salhadaar", raid = "Other", boss = "Fallen King Salhadaar", expansion = "Midnight" },
    { key = "bolren_child_of_alar", label = "Bolren, Child of Alar", raid = "Other", boss = "Bolren", expansion = "Midnight" },
    { key = "imperator_averzian", label = "Imperator Averzian", raid = "Other", boss = "Imperator Averzian", expansion = "Midnight" },
    { key = "lighttblinded_vanguard", label = "Lightblinded Vanguard", raid = "Other", boss = "Lightblinded Vanguard", expansion = "Midnight" },
    { key = "midnigh_falls", label = "Midnight Falls", raid = "Other", boss = "Midnight Falls", expansion = "Midnight" },
    { key = "vaelgor_ezzorak", label = "Vaelgor & Ezzorak", raid = "Other", boss = "Vaelgor & Ezzorak", expansion = "Midnight" },
    { key = "cosmos", label = "Cosmos (Generic)", raid = "Other", boss = "Generic Arena", expansion = "Midnight" },
}

local function ArenaBackgroundExists(key)
    if not key or key == "" then return false end
    return true
end

local function GetAvailableArenas()
    local out = {}
    for _, arena in ipairs(ARENAS) do
        if ArenaBackgroundExists(arena.key) then
            out[#out + 1] = arena
        end
    end
    if #out == 0 then
        out[1] = { key = "cosmos", label = "Cosmos (Generic)", raid = "Other", boss = "Generic Arena", expansion = "Other" }
    end
    return out
end

local function MakeUniquePlanName(base)
    base = (type(base) == "string" and base ~= "") and base or "Untitled Plan"
    RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {}, nextId = 1 }
    local used = {}
    for _, entry in ipairs(RaidstratsggSavedPlans.list) do
        if type(entry.planName) == "string" and entry.planName ~= "" then
            used[entry.planName] = true
        end
    end
    if not used[base] then return base end
    local n = 2
    while used[base .. " " .. n] do
        n = n + 1
    end
    return base .. " " .. n
end

function Diar:CreateNewPlan(arena, opts)
    opts = opts or {}
    if type(arena) == "string" then
        arena = { key = arena }
    end
    if type(arena) ~= "table" or not arena.key or arena.key == "" then
        return false
    end

    local planName = MakeUniquePlanName(opts.planName or "Untitled Plan")
    local data = {
        v = 2,
        planName = planName,
        expansion = arena.expansion or opts.expansion or "Other",
        raid = arena.raid or opts.raid or "Other",
        boss = arena.boss or opts.boss or "Unknown",
        scenes = {
            {
                name = "Scene 1",
                bg = arena.key,
                items = {},
            },
        },
    }

    if self.EnsurePlanInstanceKey then
        self:EnsurePlanInstanceKey(data, true)
    end
    if self.SaveImportedPlan then
        self:SaveImportedPlan(data)
    else
        return false
    end

    self.plannerData = data

    local settings = self.GetPlannerSettings and self:GetPlannerSettings()
    if settings then
        settings.showObjectPalette = true
    end

    if self.ShowPlannerViewer then
        self:ShowPlannerViewer({ reloadOnly = false })
    end
    if self.RefreshSavedPlansList then
        self:RefreshSavedPlansList()
    end
    if self.UpdatePushUpdateButton then
        self:UpdatePushUpdateButton()
    end
    if self.ApplyObjectPaletteLayout and self.plannerFrame then
        self:ApplyObjectPaletteLayout(self.plannerFrame)
    end

    print(("|cff00aaff[Raidstrats.gg]|r Created new plan \"%s\" with arena %s."):format(planName, arena.label or arena.key))
    return true
end

function Diar:ShowCreatePlanDialog()
    if not self.createPlanDialog then
        local f = CreateFrame("Frame", "RaidstratsCreatePlanDialog", UIParent, "BackdropTemplate")
        f:SetSize(520, 460)
        f:SetPoint("CENTER", 0, 0)
        f:SetMovable(true)
        f:EnableMouse(true)
        SetBackdrop(f)
        tinsert(UISpecialFrames, "RaidstratsCreatePlanDialog")
        f:SetScript("OnMouseDown", function(s, b) if b == "LeftButton" then s:StartMoving() end end)
        f:SetScript("OnMouseUp", function(s) s:StopMovingOrSizing() end)

        local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -5, -5)

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -18)
        title:SetText("Create new plan")
        title:SetTextColor(0.9, 0.9, 0.9)

        local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOP", title, "BOTTOM", 0, -8)
        hint:SetWidth(480)
        hint:SetTextColor(0.55, 0.6, 0.65)
        hint:SetText("Choose an arena background for your first scene. You can add more scenes later on the website.")

        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -72)
        scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -36, 56)
        local child = CreateFrame("Frame", nil, scroll)
        child:SetWidth(460)
        child:SetHeight(1)
        scroll:SetScrollChild(child)
        if PUI.SkinPlannerScroll then PUI.SkinPlannerScroll(scroll) end

        local btnRow = CreateFrame("Frame", nil, f)
        btnRow:SetHeight(36)
        btnRow:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 14)
        btnRow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 14)

        local cancelBtn = CreateFrame("Button", nil, btnRow, "UIPanelButtonTemplate")
        cancelBtn:SetHeight(36)
        cancelBtn:SetPoint("LEFT", btnRow, "LEFT", 0, 0)
        cancelBtn:SetPoint("RIGHT", btnRow, "RIGHT", 0, 0)
        cancelBtn:SetText("Cancel")
        cancelBtn:SetScript("OnClick", function() f:Hide() end)

        f.scroll = scroll
        f.scrollChild = child
        self.createPlanDialog = f
    end

    local f = self.createPlanDialog
    local child = f.scrollChild
    local w = 460
    local rowH = 34
    local gap = 4
    local y = -4

    if f.arenaRows then
        for _, row in ipairs(f.arenaRows) do
            row:Hide()
            row:SetParent(nil)
        end
    end
    f.arenaRows = {}

    local arenas = GetAvailableArenas()
    local lastRaid
    for _, arena in ipairs(arenas) do
        if arena.raid and arena.raid ~= lastRaid then
            lastRaid = arena.raid
            local hdr = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            hdr:SetPoint("TOPLEFT", child, "TOPLEFT", 4, y)
            hdr:SetWidth(w - 8)
            hdr:SetJustifyH("LEFT")
            hdr:SetText(string.upper(lastRaid))
            hdr:SetTextColor(unpack(UI.ACCENT))
            f.arenaRows[#f.arenaRows + 1] = hdr
            y = y - 20
        end

        local row = CreateFrame("Button", nil, child, "BackdropTemplate")
        row:SetSize(w, rowH)
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
        SetBackdrop(row, UI.ROW, UI.BORDER, 1)
        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("LEFT", row, "LEFT", 10, 0)
        lbl:SetText(arena.label or arena.key)
        lbl:SetTextColor(0.92, 0.92, 0.92)
        row:SetScript("OnEnter", function(s)
            s:SetBackdropColor(unpack(UI.ROW_HOV))
            lbl:SetTextColor(1, 1, 1)
        end)
        row:SetScript("OnLeave", function(s)
            s:SetBackdropColor(unpack(UI.ROW))
            lbl:SetTextColor(0.92, 0.92, 0.92)
        end)
        row:SetScript("OnClick", function()
            if Diar:CreateNewPlan(arena) then
                f:Hide()
            end
        end)
        f.arenaRows[#f.arenaRows + 1] = row
        y = y - rowH - gap
    end

    child:SetHeight(math.max(1, -y + 8))
    f.scroll:SetVerticalScroll(0)
    Diar:PrepareModal(f, self.plannerFrame or self.frame)
    f:Show()
end
