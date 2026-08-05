-- Raidstrats.gg Planner - create new plan + arena picker
local addonName = ...
local AceAddon = LibStub("AceAddon-3.0")
local Addon =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)
if not Addon then return end
local function L(key) return RSGG_L(key) end
local Diar = Addon
local SetBackdrop = Diar.SetBackdrop
local PUI = Diar.PlannerUI
local UI = PUI.UI
local CreatePlannerIconBtn = PUI.CreatePlannerIconBtn
local BG_BASE_PATH = "Interface\\AddOns\\" .. tostring(addonName) .. "\\backgrounds\\"
local PREVIEW_ASPECT = 16 / 9
local PREVIEW_INSET = 6
local PREVIEW_CAPTION_H = 22
local CURRENT_TIER_RAID = "The Voidspire"
-- Manual raid order for the create-plan picker (top to bottom).
-- Update this list when a new tier launches.
local RAID_SORT_ORDER = {
    "The Voidspire",
    "The Dreamrift",
    "March on Quel'Danas",
    "Sporefall",
    "Tidebound Grotto",
    "Manaforge Omega",
    "The Venomous Abyss",
    "Liberation of Undermine",
    "Nerub-ar Palace",
    "Other",
}
-- Newest expansion first in picker tabs.
local EXPANSION_SORT_ORDER = {
    "Midnight",
    "The War Within",
    "Dragonflight",
    "Shadowlands",
    "Battle for Azeroth",
    "Legion",
}
local BOSS_SORT_ORDER_BY_RAID = {
    ["The Venomous Abyss"] = {
        "Nek'zali the Soulcoiler",
        "Entombed Sentinels",
        "Vashnik the Malignant",
        "The Lost Explorers",
        "Sszorak",
        "The Twin Fangs",
        "The Bargained Crown",
        "Ula'tek",
    },
}
local BACKGROUND_EXISTS_CACHE = {}
local BACKGROUND_PROBE_TEX = nil
local BACKGROUND_KEY_ALIASES = {
    -- Backward-compat for old misspelled keys.
    midnigh_falls = "midnight_falls",
    midnigh_falls_intermission = "midnight_falls_intermission",
    midnigh_falls_p2 = "midnight_falls_p2",
    midnigh_falls_p3_soaks = "midnight_falls_phase3_soaks",
    -- Optional alias if someone used p3_soaks without "phase".
    midnight_falls_p3_soaks = "midnight_falls_phase3_soaks",

    -- Venomous Abyss legacy WIP keys -> real background keys.
    tva_nekzali_the_soulcoiler_wip = "Soulcoiler",
    tva_entombed_sentinels_wip = "Entombed_Sentinels",
    tva_vashnik_the_malignant_wip = "vashnik",
    tva_the_lost_explorers_wip = "explorers_1",
    tva_sszorak_wip = "Sszorak",
    tva_the_twin_fangs_wip = "Twin_Fangs_2",
    tva_the_bargained_crown_wip = "bargained_crown",
    tva_ula_tek_wip = "ulatek1",

    -- Website UUID upload filename -> bundled TGA key.
    ["ebb83c6f-b84b-4c30-8823-38379405ab06"] = "tidebound-grotto",
}

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
    -- Midnight API-aligned mappings
    { key = "vorasius", label = "Vorasius", raid = "The Voidspire", boss = "Vorasius", expansion = "Midnight" },
    { key = "vorasius_close", label = "Vorasius (Close)", raid = "The Voidspire", boss = "Vorasius", expansion = "Midnight" },
    { key = "chimera_l2", label = "Chimaerus", raid = "The Dreamrift", boss = "Chimaerus the Undreamt God", expansion = "Midnight" },
    { key = "Dreamrift", label = "Dreamrift", raid = "The Dreamrift", boss = "Chimaerus the Undreamt God", expansion = "Midnight" },
    { key = "fallen-king_salhadaar", label = "Fallen King Salhadaar", raid = "The Voidspire", boss = "Fallen-King Salhadaar", expansion = "Midnight" },
    { key = "bolren_child_of_alar", label = "Belo'ren, Child of Al'ar", raid = "March on Quel'Danas", boss = "Belo'ren, Child of Al'ar", expansion = "Midnight" },
    { key = "imperator_averzian", label = "Imperator Averzian", raid = "The Voidspire", boss = "Imperator Averzian", expansion = "Midnight" },
    { key = "lighttblinded_vanguard", label = "Lightblinded Vanguard", raid = "The Voidspire", boss = "Lightblinded Vanguard", expansion = "Midnight" },
    { key = "midnight_falls", label = "Midnight Falls", raid = "March on Quel'Danas", boss = "Midnight Falls", expansion = "Midnight" },
    { key = "midnight_falls_intermission", label = "Midnight Falls (Intermission)", raid = "March on Quel'Danas", boss = "Midnight Falls", expansion = "Midnight" },
    { key = "midnight_falls_p2", label = "Midnight Falls (P2)", raid = "March on Quel'Danas", boss = "Midnight Falls", expansion = "Midnight" },
    { key = "midnight_falls_phase3_soaks", label = "Midnight Falls (Phase 3 Soaks)", raid = "March on Quel'Danas", boss = "Midnight Falls", expansion = "Midnight" },
    { key = "vaelgor_ezzorak", label = "Vaelgor & Ezzorak", raid = "The Voidspire", boss = "Vaelgor & Ezzorak", expansion = "Midnight" },
    { key = "cosmos", label = "Crown of the Cosmos", raid = "The Voidspire", boss = "Crown of the Cosmos", expansion = "Midnight" },
    { key = "rotmire_arena", label = "Rotmire", raid = "Sporefall", boss = "Rotmire", expansion = "Midnight" },
    { key = "tidebound-grotto", label = "Nymrissa Wavecaller", raid = "Tidebound Grotto", boss = "Nymrissa Wavecaller", expansion = "Midnight" },

    -- The Venomous Abyss
    { key = "Soulcoiler", label = "Nek'zali the Soulcoiler", raid = "The Venomous Abyss", boss = "Nek'zali the Soulcoiler", expansion = "Midnight" },
    { key = "Entombed_Sentinels", label = "Entombed Sentinels", raid = "The Venomous Abyss", boss = "Entombed Sentinels", expansion = "Midnight" },
    { key = "vashnik", label = "Vashnik the Malignant", raid = "The Venomous Abyss", boss = "Vashnik the Malignant", expansion = "Midnight" },
    { key = "explorers_1", label = "The Lost Explorers (Route 1)", raid = "The Venomous Abyss", boss = "The Lost Explorers", expansion = "Midnight" },
    { key = "Explorers_2", label = "The Lost Explorers (Route 2)", raid = "The Venomous Abyss", boss = "The Lost Explorers", expansion = "Midnight" },
    { key = "Sszorak", label = "Sszorak", raid = "The Venomous Abyss", boss = "Sszorak", expansion = "Midnight" },
    { key = "Twin_Fangs_2", label = "The Twin Fangs", raid = "The Venomous Abyss", boss = "The Twin Fangs", expansion = "Midnight" },
    { key = "bargained_crown", label = "The Bargained Crown", raid = "The Venomous Abyss", boss = "The Bargained Crown", expansion = "Midnight" },
    { key = "ulatek1", label = "Ula'tek", raid = "The Venomous Abyss", boss = "Ula'tek", expansion = "Midnight" },
}

local function GetBackgroundLookupKeys(bgKey)
    if type(bgKey) ~= "string" or bgKey == "" then return {} end
    local clean = bgKey:gsub("^/+", ""):gsub("%.[^%.]+$", "")
    local out = { clean }
    local alias = BACKGROUND_KEY_ALIASES[clean] or BACKGROUND_KEY_ALIASES[strlower(clean)]
    if alias and alias ~= clean then
        -- Prefer the bundled TGA key first for preview/load.
        out = { alias, clean }
    end
    return out
end

local function GetArenaPreviewCandidates(bgKey)
    local keys = GetBackgroundLookupKeys(bgKey)
    if #keys == 0 then return nil end
    local out = {}
    for i = 1, #keys do
        local clean = keys[i]
        out[#out + 1] = BG_BASE_PATH .. clean .. ".tga"
        out[#out + 1] = BG_BASE_PATH .. clean .. ".blp"
        out[#out + 1] = BG_BASE_PATH .. clean .. ".png"
        out[#out + 1] = BG_BASE_PATH .. clean .. ".jpg"
    end
    return out
end

local function ArenaBackgroundExists(key)
    if not key or key == "" then return false end
    if BACKGROUND_EXISTS_CACHE[key] ~= nil then
        return BACKGROUND_EXISTS_CACHE[key]
    end
    if not BACKGROUND_PROBE_TEX then
        local holder = UIParent or WorldFrame
        if not holder then return false end
        BACKGROUND_PROBE_TEX = holder:CreateTexture(nil, "BACKGROUND")
    end
    local candidates = GetArenaPreviewCandidates(key) or {}
    for i = 1, #candidates do
        if BACKGROUND_PROBE_TEX:SetTexture(candidates[i]) then
            BACKGROUND_EXISTS_CACHE[key] = true
            return true
        end
    end
    BACKGROUND_EXISTS_CACHE[key] = false
    return false
end

local function GetAvailableArenas()
    local out = {}
    for _, arena in ipairs(ARENAS) do
        if arena.alwaysAvailable or ArenaBackgroundExists(arena.key) then
            out[#out + 1] = arena
        end
    end
    if #out == 0 then
        out[1] = { key = "cosmos", label = "Cosmos (Generic)", raid = "Other", boss = "Generic Arena", expansion = "Other" }
    end
    return out
end

local function BuildRaidOptions(arenas)
    local out = {}
    local byKey = {}
    for _, arena in ipairs(arenas or {}) do
        local raid = arena.raid or "Other"
        local key = tostring(raid)
        local node = byKey[key]
        if not node then
            node = {
                key = key,
                raid = raid,
                expansion = arena.expansion or "Other",
                arenas = {},
            }
            byKey[key] = node
            out[#out + 1] = node
        end
        node.arenas[#node.arenas + 1] = arena
    end
    if #out == 0 then
        out[1] = {
            key = "Other",
            raid = "Other",
            expansion = "Other",
            arenas = {
                { key = "cosmos", label = "Cosmos (Generic)", raid = "Other", boss = "Generic Arena", expansion = "Other" }
            },
        }
    end
    local order = {}
    for i, raidName in ipairs(RAID_SORT_ORDER or {}) do
        order[tostring(raidName)] = i
    end
    table.sort(out, function(a, b)
        local ar, br = tostring(a.raid or ""), tostring(b.raid or "")
        local ai, bi = order[ar], order[br]
        if ai and bi and ai ~= bi then return ai < bi end
        if ai and not bi then return true end
        if bi and not ai then return false end
        if ar == CURRENT_TIER_RAID and br ~= CURRENT_TIER_RAID then return true end
        if br == CURRENT_TIER_RAID and ar ~= CURRENT_TIER_RAID then return false end
        if (a.expansion or "") ~= (b.expansion or "") then
            return (a.expansion or "") > (b.expansion or "")
        end
        return ar < br
    end)
    return out
end

local function BuildExpansionOptions(arenas)
    local out = {}
    local seen = {}
    for _, arena in ipairs(arenas or {}) do
        local expansion = tostring(arena.expansion or "Other")
        if expansion ~= "" and not seen[expansion] then
            seen[expansion] = true
            out[#out + 1] = { expansion = expansion }
        end
    end
    local order = {}
    for i, name in ipairs(EXPANSION_SORT_ORDER or {}) do
        order[tostring(name)] = i
    end
    table.sort(out, function(a, b)
        local ae, be = tostring(a.expansion or ""), tostring(b.expansion or "")
        local ai, bi = order[ae], order[be]
        if ai and bi and ai ~= bi then return ai < bi end
        if ai and not bi then return true end
        if bi and not ai then return false end
        return ae < be
    end)
    return out
end

local function BuildBossOptionsForRaid(raidNode)
    local out = {}
    local byKey = {}
    local arenas = raidNode and raidNode.arenas or {}
    for _, arena in ipairs(arenas) do
        local boss = arena.boss or arena.label or arena.key or "Unknown"
        local key = tostring(boss)
        local node = byKey[key]
        if not node then
            node = {
                key = key,
                boss = boss,
                raid = arena.raid or (raidNode and raidNode.raid) or "Other",
                expansion = arena.expansion or (raidNode and raidNode.expansion) or "Other",
                arenas = {},
            }
            byKey[key] = node
            out[#out + 1] = node
        end
        node.arenas[#node.arenas + 1] = arena
    end
    local orderList = raidNode and BOSS_SORT_ORDER_BY_RAID[tostring(raidNode.raid or "")]
    local orderMap = {}
    if type(orderList) == "table" then
        for i, bossName in ipairs(orderList) do
            orderMap[tostring(bossName)] = i
        end
    end
    table.sort(out, function(a, b)
        local ab, bb = tostring(a.boss or ""), tostring(b.boss or "")
        local ai, bi = orderMap[ab], orderMap[bb]
        if ai and bi and ai ~= bi then return ai < bi end
        if ai and not bi then return true end
        if bi and not ai then return false end
        return ab < bb
    end)
    return out
end

local function SetPreviewTextureFromCandidates(tex, candidates)
    if not tex or not candidates then return false end
    for i = 1, #candidates do
        if tex:SetTexture(candidates[i]) then
            tex:SetTexCoord(0, 1, 0, 1)
            tex:SetVertexColor(1, 1, 1, 1)
            tex:SetAlpha(1)
            return true
        end
    end
    return false
end

local function UpdateCreatePlanPreview(f, arena)
    if not f or not f.previewTex then return end
    if not arena or not arena.key then
        f.previewTex:SetTexture(nil)
        if f.previewHint then
            f.previewHint:SetText(L("Select a background to preview"))
            f.previewHint:Show()
        end
        if f.previewCaption then f.previewCaption:SetText("") end
        return
    end
    local ok = SetPreviewTextureFromCandidates(f.previewTex, GetArenaPreviewCandidates(arena.key))
    if f.previewHint then
        if ok then
            f.previewHint:Hide()
        else
            f.previewHint:SetText(L("Preview not available for this background"))
            f.previewHint:Show()
        end
    end
    if f.previewCaption then
        f.previewCaption:SetText(arena.label or arena.key)
    end
end

local function RelayoutCreatePlanPreviewTexture(f)
    if not f or not f.previewPanel or not f.previewTex then return end
    local panelW = f.previewPanel:GetWidth() or 0
    local panelH = f.previewPanel:GetHeight() or 0
    local availW = math.max(1, panelW - PREVIEW_INSET * 2)
    local availH = math.max(1, panelH - PREVIEW_INSET - PREVIEW_CAPTION_H - PREVIEW_INSET)

    local w = availW
    local h = w / PREVIEW_ASPECT
    if h > availH then
        h = availH
        w = h * PREVIEW_ASPECT
    end

    f.previewTex:ClearAllPoints()
    f.previewTex:SetSize(math.floor(w + 0.5), math.floor(h + 0.5))
    f.previewTex:SetPoint("TOP", f.previewPanel, "TOP", 0, -PREVIEW_INSET)
end

local function MakeUniquePlanName(base)
    base = (type(base) == "string" and base ~= "") and base or L("Untitled Plan")
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

local function SuggestedPlanName(arena)
    if type(arena) ~= "table" then return L("Untitled Plan") end
    local boss = tostring(arena.boss or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if boss ~= "" and boss ~= "Unknown" then
        return boss
    end
    local label = tostring(arena.label or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if label ~= "" then return label end
    return L("Untitled Plan")
end

local function SetPrimaryButtonStyle(btn)
    if not btn then return end
    btn.selected = true
    btn:SetBackdropColor(unpack(UI.ACCENT))
    if btn.label then
        btn.label:SetTextColor(1, 1, 1)
    end
end

if not StaticPopupDialogs["RAIDSTRATSGG_CREATE_PLAN_NAME"] then
    StaticPopupDialogs["RAIDSTRATSGG_CREATE_PLAN_NAME"] = {
        text = L("Plan name:"),
        button1 = _G.OKAY or L("OK"),
        button2 = _G.CANCEL or L("Cancel"),
        hasEditBox = true,
        maxLetters = 64,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        OnShow = function(self)
            local eb = self.editBox or self.EditBox
            if not eb then return end
            local suggested = (self.data and self.data.suggestedName) or L("Untitled Plan")
            eb:SetText(suggested)
            eb:HighlightText()
            eb:SetFocus()
        end,
        OnAccept = function(self)
            local data = self.data
            if not data or not data.arena or not Diar then return end
            local eb = self.editBox or self.EditBox
            local name = eb and eb:GetText() or ""
            name = strtrim(tostring(name or ""))
            if name == "" then
                name = SuggestedPlanName(data.arena)
            end
            if Diar:CreateNewPlan(data.arena, { planName = name }) and data.dialog then
                data.dialog:Hide()
            end
        end,
    }
end

function Diar:PromptCreatePlanName(arena, dialog)
    if type(arena) ~= "table" or not arena.key then return end
    if not self.createPlanNameDialog then
        local f = CreateFrame("Frame", "RaidstratsCreatePlanNameDialog", UIParent, "BackdropTemplate")
        f:SetSize(420, 170)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetFrameLevel(650)
        f:EnableMouse(true)
        SetBackdrop(f, UI.PANEL, UI.BORDER, 2)
        tinsert(UISpecialFrames, "RaidstratsCreatePlanNameDialog")

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -16)
        title:SetText(L("Name your plan"))
        title:SetTextColor(0.92, 0.92, 0.92)

        local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
        subtitle:SetText(L("Choose a plan name before creating it."))
        subtitle:SetTextColor(0.55, 0.60, 0.66)

        local nameWrap = CreateFrame("Frame", nil, f, "BackdropTemplate")
        nameWrap:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -12)
        nameWrap:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -62)
        nameWrap:SetHeight(28)
        SetBackdrop(nameWrap, {0.05, 0.05, 0.07, 1}, UI.BORDER, 1)

        local nameEdit = CreateFrame("EditBox", nil, nameWrap)
        nameEdit:SetAutoFocus(false)
        nameEdit:SetPoint("TOPLEFT", nameWrap, "TOPLEFT", 8, -2)
        nameEdit:SetPoint("BOTTOMRIGHT", nameWrap, "BOTTOMRIGHT", -8, 2)
        nameEdit:SetTextInsets(0, 0, 0, 0)
        nameEdit:SetMaxLetters(64)
        nameEdit:SetFontObject(GameFontHighlightSmall)
        nameEdit:SetTextColor(0.92, 0.92, 0.92)
        nameEdit:SetScript("OnEditFocusGained", function()
            nameWrap:SetBackdropBorderColor(unpack(UI.ACCENT))
        end)
        nameEdit:SetScript("OnEditFocusLost", function()
            nameWrap:SetBackdropBorderColor(unpack(UI.BORDER))
        end)

        local btnRow = CreateFrame("Frame", nil, f)
        btnRow:SetHeight(30)
        btnRow:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 16)
        btnRow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)

        local okBtn = CreatePlannerIconBtn(btnRow, L("Okay"), 190, 30)
        okBtn:SetPoint("LEFT", btnRow, "LEFT", 0, 0)
        okBtn:SetPoint("RIGHT", btnRow, "CENTER", -4, 0)
        SetPrimaryButtonStyle(okBtn)

        local cancelBtn = CreatePlannerIconBtn(btnRow, L("Cancel"), 190, 30)
        cancelBtn:SetPoint("LEFT", btnRow, "CENTER", 4, 0)
        cancelBtn:SetPoint("RIGHT", btnRow, "RIGHT", 0, 0)
        cancelBtn:SetScript("OnClick", function()
            f:Hide()
        end)

        local function SubmitName()
            local data = f._createPlanNameData
            if not data or not data.arena then return end
            local name = strtrim(tostring(nameEdit:GetText() or ""))
            if name == "" then
                name = SuggestedPlanName(data.arena)
            end
            if Diar:CreateNewPlan(data.arena, { planName = name }) then
                if data.dialog then data.dialog:Hide() end
                f:Hide()
            end
        end

        okBtn:SetScript("OnClick", SubmitName)
        nameEdit:SetScript("OnEnterPressed", SubmitName)
        nameEdit:SetScript("OnEscapePressed", function()
            f:Hide()
        end)

        f.nameWrap = nameWrap
        f.nameEdit = nameEdit
        f.okBtn = okBtn
        f.cancelBtn = cancelBtn
        f.title = title
        self.createPlanNameDialog = f
    end

    local f = self.createPlanNameDialog
    f._createPlanNameData = {
        arena = arena,
        dialog = dialog,
        suggestedName = SuggestedPlanName(arena),
    }
    if self.PrepareModal then
        self:PrepareModal(f, dialog or self.createPlanDialog or self.plannerFrame or self.frame)
    end
    f:ClearAllPoints()
    if dialog and dialog.IsShown and dialog:IsShown() then
        f:SetPoint("CENTER", dialog, "CENTER", 0, 0)
        f:SetFrameLevel((dialog:GetFrameLevel() or 500) + 60)
    else
        f:SetPoint("CENTER")
        f:SetFrameLevel(650)
    end
    if f.nameEdit then
        f.nameEdit:SetText(f._createPlanNameData.suggestedName or L("Untitled Plan"))
        f.nameEdit:HighlightText()
    end
    f:Show()
    if f.nameEdit then
        f.nameEdit:SetFocus()
    end
end

function Diar:CreateNewPlan(arena, opts)
    opts = opts or {}
    if type(arena) == "string" then
        arena = { key = arena }
    end
    if type(arena) ~= "table" or not arena.key or arena.key == "" then
        return false
    end

    local planName = MakeUniquePlanName(opts.planName or L("Untitled Plan"))
    local data = {
        v = 2,
        planName = planName,
        expansion = arena.expansion or opts.expansion or "Other",
        raid = arena.raid or opts.raid or "Other",
        boss = arena.boss or opts.boss or "Unknown",
        scenes = {
            {
                name = "1",
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

    return true
end

function Diar:AddSceneFromArena(arena)
    if type(arena) ~= "table" or not arena.key or arena.key == "" then
        return false
    end
    local data = self.plannerData
    if not data then return false end
    if tostring(data.planName or "") == "No plan" then
        print("|cffff6666[Raidstrats.gg]|r " .. L("No plan loaded. Load a plan before adding scenes."))
        return false
    end
    data.scenes = data.scenes or {}
    local nextIndex = #data.scenes + 1
    data.scenes[nextIndex] = {
        name = tostring(nextIndex),
        bg = arena.key,
        items = {},
    }
    if self.PersistCurrentPlanToSaved then
        self:PersistCurrentPlanToSaved()
    end
    if self.ShowPlannerViewer then
        self:ShowPlannerViewer({ reloadOnly = true })
    end
    local pf = self.plannerFrame
    if pf then
        pf.selectedSceneIndex = nextIndex
        pf.__viewerViewportSceneIdx = nil
    end
    if self.StopPlannerAnimation then self:StopPlannerAnimation() end
    if self.UpdateSceneTabHighlight then self:UpdateSceneTabHighlight() end
    if self.RefreshPlannerScene then self:RefreshPlannerScene() end
    if self.OnPlannerSceneChanged then self:OnPlannerSceneChanged() end
    return true
end

function Diar:ShowCreateSceneDialog()
    local data = self.plannerData
    if not data or tostring(data.planName or "") == "No plan" then
        print("|cffff6666[Raidstrats.gg]|r " .. L("No plan loaded. Load a plan before adding scenes."))
        return
    end
    self:ShowCreatePlanDialog({ sceneMode = true })
end

function Diar:ShowCreatePlanDialog(opts)
    opts = opts or {}
    local sceneMode = opts.sceneMode == true
    if not self.createPlanDialog then
        local f = CreateFrame("Frame", "RaidstratsCreatePlanDialog", UIParent, "BackdropTemplate")
        f:SetSize(980, 540)
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
        title:SetText(L("Create new plan"))
        title:SetTextColor(0.9, 0.9, 0.9)

        local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOP", title, "BOTTOM", 0, -8)
        hint:SetWidth(940)
        hint:SetTextColor(0.55, 0.6, 0.65)
        hint:SetText(L("Select Expansion -> Raid -> Boss -> Background for Scene 1."))

        local expansionLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        expansionLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -74)
        expansionLabel:SetText(L("EXPANSIONS"))
        expansionLabel:SetTextColor(unpack(UI.ACCENT))

        local expansionTabsContainer = CreateFrame("Frame", nil, f)
        expansionTabsContainer:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -92)
        expansionTabsContainer:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -92)
        expansionTabsContainer:SetHeight(28)

        local raidLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        raidLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -126)
        raidLabel:SetText(L("RAIDS"))
        raidLabel:SetTextColor(unpack(UI.ACCENT))

        local bossLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        bossLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 330, -126)
        bossLabel:SetText(L("BOSSES"))
        bossLabel:SetTextColor(unpack(UI.ACCENT))

        local rightLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        rightLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 642, -126)
        rightLabel:SetText(L("BACKGROUNDS"))
        rightLabel:SetTextColor(unpack(UI.ACCENT))

        local raidScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        raidScroll:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -144)
        raidScroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", 302, 56)
        local raidChild = CreateFrame("Frame", nil, raidScroll)
        raidChild:SetWidth(276)
        raidChild:SetHeight(1)
        raidScroll:SetScrollChild(raidChild)
        if PUI.SkinPlannerScroll then PUI.SkinPlannerScroll(raidScroll) end

        local bossScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        bossScroll:SetPoint("TOPLEFT", f, "TOPLEFT", 328, -144)
        bossScroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", 614, 56)
        local bossChild = CreateFrame("Frame", nil, bossScroll)
        bossChild:SetWidth(276)
        bossChild:SetHeight(1)
        bossScroll:SetScrollChild(bossChild)
        if PUI.SkinPlannerScroll then PUI.SkinPlannerScroll(bossScroll) end

        local bgScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        bgScroll:SetPoint("TOPLEFT", f, "TOPLEFT", 640, -144)
        bgScroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 260)
        local bgChild = CreateFrame("Frame", nil, bgScroll)
        bgChild:SetWidth(300)
        bgChild:SetHeight(1)
        bgScroll:SetScrollChild(bgChild)
        if PUI.SkinPlannerScroll then PUI.SkinPlannerScroll(bgScroll) end

        local previewTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        previewTitle:SetPoint("TOPLEFT", bgScroll, "BOTTOMLEFT", 0, -4)
        previewTitle:SetText(L("PREVIEW"))
        previewTitle:SetTextColor(unpack(UI.ACCENT))

        local previewPanel = CreateFrame("Frame", nil, f, "BackdropTemplate")
        previewPanel:SetPoint("TOPLEFT", previewTitle, "BOTTOMLEFT", 0, -4)
        previewPanel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 72)
        SetBackdrop(previewPanel, UI.ROW, UI.BORDER, 1)

        local previewTex = previewPanel:CreateTexture(nil, "ARTWORK")
        previewTex:SetTexCoord(0, 1, 0, 1)

        local previewHint = previewPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        previewHint:SetPoint("CENTER", previewTex, "CENTER", 0, 0)
        previewHint:SetTextColor(0.55, 0.60, 0.66)
        previewHint:SetText(L("Select a background to preview"))

        local previewCaption = previewPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        previewCaption:SetPoint("BOTTOMLEFT", previewPanel, "BOTTOMLEFT", 8, 6)
        previewCaption:SetPoint("BOTTOMRIGHT", previewPanel, "BOTTOMRIGHT", -8, 6)
        previewCaption:SetJustifyH("LEFT")
        previewCaption:SetTextColor(0.85, 0.88, 0.92)
        previewPanel:SetScript("OnSizeChanged", function()
            RelayoutCreatePlanPreviewTexture(f)
        end)

        local btnRow = CreateFrame("Frame", nil, f)
        btnRow:SetHeight(36)
        btnRow:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 14)
        btnRow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 14)

        local createBtn = CreatePlannerIconBtn(btnRow, L("Create Plan"), 200, 36)
        createBtn:SetPoint("LEFT", btnRow, "LEFT", 0, 0)
        createBtn:SetPoint("RIGHT", btnRow, "CENTER", -4, 0)
        createBtn:Disable()
        createBtn:SetAlpha(0.45)
        if createBtn.label then createBtn.label:SetTextColor(0.55, 0.55, 0.55) end

        local cancelBtn = CreatePlannerIconBtn(btnRow, L("Cancel"), 200, 36)
        cancelBtn:SetPoint("LEFT", btnRow, "CENTER", 4, 0)
        cancelBtn:SetPoint("RIGHT", btnRow, "RIGHT", 0, 0)
        cancelBtn:SetScript("OnClick", function() f:Hide() end)

        f.raidScroll = raidScroll
        f.raidChild = raidChild
        f.bossScroll = bossScroll
        f.bossChild = bossChild
        f.bgScroll = bgScroll
        f.bgChild = bgChild
        f.previewPanel = previewPanel
        f.previewTex = previewTex
        f.previewHint = previewHint
        f.previewCaption = previewCaption
        f.expansionTabsContainer = expansionTabsContainer
        f.createBtn = createBtn
        f.title = title
        f.hint = hint
        self.createPlanDialog = f
    end

    local f = self.createPlanDialog
    local raidChild = f.raidChild
    local bossChild = f.bossChild
    local bgChild = f.bgChild
    local raidW = 276
    local bossW = 276
    local bgW = 300
    local rowH = 34
    local gap = 4

    if f.raidRows then
        for _, row in ipairs(f.raidRows) do
            row:Hide()
            row:SetParent(nil)
        end
    end
    if f.bossRows then
        for _, row in ipairs(f.bossRows) do
            row:Hide()
            row:SetParent(nil)
        end
    end
    if f.bgRows then
        for _, row in ipairs(f.bgRows) do
            row:Hide()
            row:SetParent(nil)
        end
    end
    if f.expansionTabs then
        for _, tab in ipairs(f.expansionTabs) do
            tab:Hide()
            tab:SetParent(nil)
        end
    end
    f.raidRows = {}
    f.bossRows = {}
    f.bgRows = {}
    f.expansionTabs = {}

    local arenas = GetAvailableArenas()
    f.expansions = BuildExpansionOptions(arenas)
    f.allRaids = BuildRaidOptions(arenas)
    f.raids = {}
    f.bosses = {}
    f.selectedExpansion = nil
    f.selectedRaidIndex = nil
    f.selectedBossIndex = nil
    f.selectedArena = nil
    RelayoutCreatePlanPreviewTexture(f)
    UpdateCreatePlanPreview(f, nil)

    local function RefreshCreateButton()
        if f.createBtn then
            if f.selectedArena then
                f.createBtn:Enable()
                f.createBtn:SetAlpha(1)
                SetPrimaryButtonStyle(f.createBtn)
            else
                f.createBtn:Disable()
                f.createBtn.selected = false
                f.createBtn:SetAlpha(0.45)
                f.createBtn:SetBackdropColor(unpack(UI.ROW))
                if f.createBtn.label then f.createBtn.label:SetTextColor(0.55, 0.55, 0.55) end
            end
        end
    end

    local function UpdateRaidRowState()
        for i, row in ipairs(f.raidRows or {}) do
            local selected = f.selectedRaidIndex == i
            row:SetBackdropColor(unpack(selected and UI.ROW_HOV or UI.ROW))
            if row.label then
                row.label:SetTextColor(selected and 1 or 0.92, selected and 1 or 0.92, selected and 1 or 0.92)
            end
        end
    end

    local function UpdateExpansionTabState()
        for i, tab in ipairs(f.expansionTabs or {}) do
            local selected = f.selectedExpansion == tab.expansion
            tab.selected = selected
            if selected then
                tab:SetBackdropColor(unpack(UI.ACCENT))
                if tab.label then tab.label:SetTextColor(1, 1, 1) end
            else
                tab:SetBackdropColor(unpack(UI.ROW))
                if tab.label then tab.label:SetTextColor(0.92, 0.92, 0.92) end
            end
        end
    end

    local function UpdateBossRowState()
        for i, row in ipairs(f.bossRows or {}) do
            local selected = f.selectedBossIndex == i
            row:SetBackdropColor(unpack(selected and UI.ROW_HOV or UI.ROW))
            if row.label then
                row.label:SetTextColor(selected and 1 or 0.92, selected and 1 or 0.92, selected and 1 or 0.92)
            end
        end
    end

    local function UpdateBackgroundRowState()
        for _, row in ipairs(f.bgRows or {}) do
            local selected = f.selectedArena == row.arena
            row:SetBackdropColor(unpack(selected and UI.ROW_HOV or UI.ROW))
            if row.label then
                row.label:SetTextColor(selected and 1 or 0.92, selected and 1 or 0.92, selected and 1 or 0.92)
            end
        end
    end

    local function RenderBackgroundsForBoss()
        if f.bgRows then
            for _, row in ipairs(f.bgRows) do
                row:Hide()
                row:SetParent(nil)
            end
        end
        f.bgRows = {}
        f.selectedArena = nil
        local y = -4
        local selectedBoss = f.selectedBossIndex and f.bosses[f.selectedBossIndex] or nil
        local list = selectedBoss and selectedBoss.arenas or {}
        for _, arena in ipairs(list) do
            local row = CreateFrame("Button", nil, bgChild, "BackdropTemplate")
            row:SetSize(bgW, rowH)
            row:SetPoint("TOPLEFT", bgChild, "TOPLEFT", 0, y)
            SetBackdrop(row, UI.ROW, UI.BORDER, 1)
            row.arena = arena
            local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            lbl:SetPoint("LEFT", row, "LEFT", 10, 0)
            lbl:SetPoint("RIGHT", row, "RIGHT", -10, 0)
            lbl:SetJustifyH("LEFT")
            lbl:SetText(arena.label or arena.key)
            lbl:SetTextColor(0.92, 0.92, 0.92)
            row.label = lbl
            row:SetScript("OnEnter", function(s)
                if f.selectedArena ~= s.arena then
                    s:SetBackdropColor(unpack(UI.ROW_HOV))
                end
            end)
            row:SetScript("OnLeave", function(s)
                if f.selectedArena ~= s.arena then
                    s:SetBackdropColor(unpack(UI.ROW))
                end
            end)
            row:SetScript("OnClick", function(s)
                f.selectedArena = s.arena
                UpdateBackgroundRowState()
                UpdateCreatePlanPreview(f, f.selectedArena)
                RefreshCreateButton()
            end)
            f.bgRows[#f.bgRows + 1] = row
            y = y - rowH - gap
        end
        if #list > 0 then
            f.selectedArena = list[1]
            UpdateBackgroundRowState()
            UpdateCreatePlanPreview(f, f.selectedArena)
        else
            UpdateCreatePlanPreview(f, nil)
        end
        bgChild:SetHeight(math.max(1, -y + 8))
        if f.bgScroll then f.bgScroll:SetVerticalScroll(0) end
        RefreshCreateButton()
    end

    local function RenderBossesForRaid()
        if f.bossRows then
            for _, row in ipairs(f.bossRows) do
                row:Hide()
                row:SetParent(nil)
            end
        end
        f.bossRows = {}
        f.selectedBossIndex = nil
        local y = -4
        local selectedRaid = f.selectedRaidIndex and f.raids[f.selectedRaidIndex] or nil
        f.bosses = BuildBossOptionsForRaid(selectedRaid)
        for i, bossNode in ipairs(f.bosses) do
            local bossIndex = i
            local row = CreateFrame("Button", nil, bossChild, "BackdropTemplate")
            row:SetSize(bossW, rowH)
            row:SetPoint("TOPLEFT", bossChild, "TOPLEFT", 0, y)
            SetBackdrop(row, UI.ROW, UI.BORDER, 1)
            local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            lbl:SetPoint("LEFT", row, "LEFT", 10, 5)
            lbl:SetPoint("RIGHT", row, "RIGHT", -10, 5)
            lbl:SetJustifyH("LEFT")
            lbl:SetText(bossNode.boss or L("Unknown"))
            lbl:SetTextColor(0.92, 0.92, 0.92)
            row.label = lbl
            local sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            sub:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -1)
            sub:SetPoint("RIGHT", row, "RIGHT", -10, 0)
            sub:SetJustifyH("LEFT")
            sub:SetText(L("%d backgrounds"):format(#(bossNode.arenas or {})))
            sub:SetTextColor(0.56, 0.60, 0.66)
            row:SetScript("OnEnter", function(s)
                if f.selectedBossIndex ~= bossIndex then
                    s:SetBackdropColor(unpack(UI.ROW_HOV))
                end
            end)
            row:SetScript("OnLeave", function(s)
                if f.selectedBossIndex ~= bossIndex then
                    s:SetBackdropColor(unpack(UI.ROW))
                end
            end)
            row:SetScript("OnClick", function()
                f.selectedBossIndex = bossIndex
                UpdateBossRowState()
                RenderBackgroundsForBoss()
            end)
            f.bossRows[#f.bossRows + 1] = row
            y = y - rowH - gap
        end
        bossChild:SetHeight(math.max(1, -y + 8))
        if f.bossScroll then f.bossScroll:SetVerticalScroll(0) end
        if #f.bosses > 0 then
            f.selectedBossIndex = 1
            UpdateBossRowState()
            RenderBackgroundsForBoss()
        else
            RenderBackgroundsForBoss()
        end
    end

    local function RenderRaidsForExpansion()
        if f.raidRows then
            for _, row in ipairs(f.raidRows) do
                row:Hide()
                row:SetParent(nil)
            end
        end
        f.raidRows = {}
        f.selectedRaidIndex = nil

        local filtered = {}
        local targetExpansion = tostring(f.selectedExpansion or "")
        for _, raidNode in ipairs(f.allRaids or {}) do
            if targetExpansion == "" or tostring(raidNode.expansion or "") == targetExpansion then
                filtered[#filtered + 1] = raidNode
            end
        end
        f.raids = filtered

        local y = -4
        for i, raidNode in ipairs(f.raids or {}) do
            local raidIndex = i
            local row = CreateFrame("Button", nil, raidChild, "BackdropTemplate")
            row:SetSize(raidW, rowH)
            row:SetPoint("TOPLEFT", raidChild, "TOPLEFT", 0, y)
            SetBackdrop(row, UI.ROW, UI.BORDER, 1)
            local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            lbl:SetPoint("LEFT", row, "LEFT", 10, 5)
            lbl:SetPoint("RIGHT", row, "RIGHT", -10, 5)
            lbl:SetJustifyH("LEFT")
            lbl:SetText(raidNode.raid or L("Other"))
            lbl:SetTextColor(0.92, 0.92, 0.92)
            row.label = lbl
            local sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            sub:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -1)
            sub:SetPoint("RIGHT", row, "RIGHT", -10, 0)
            sub:SetJustifyH("LEFT")
            local bossCount = #BuildBossOptionsForRaid(raidNode)
            sub:SetText(L("%s  (%d bosses)"):format(raidNode.expansion or L("Other"), bossCount))
            sub:SetTextColor(0.56, 0.60, 0.66)
            row:SetScript("OnEnter", function(s)
                if f.selectedRaidIndex ~= raidIndex then
                    s:SetBackdropColor(unpack(UI.ROW_HOV))
                end
            end)
            row:SetScript("OnLeave", function(s)
                if f.selectedRaidIndex ~= raidIndex then
                    s:SetBackdropColor(unpack(UI.ROW))
                end
            end)
            row:SetScript("OnClick", function()
                f.selectedRaidIndex = raidIndex
                UpdateRaidRowState()
                RenderBossesForRaid()
            end)
            f.raidRows[#f.raidRows + 1] = row
            y = y - rowH - gap
        end
        raidChild:SetHeight(math.max(1, -y + 8))
        if f.raidScroll then f.raidScroll:SetVerticalScroll(0) end

        if #f.raids > 0 then
            local defaultRaidIndex = 1
            for i, raidNode in ipairs(f.raids) do
                if raidNode.raid == CURRENT_TIER_RAID then
                    defaultRaidIndex = i
                    break
                end
            end
            f.selectedRaidIndex = defaultRaidIndex
            UpdateRaidRowState()
            RenderBossesForRaid()
        else
            RenderBossesForRaid()
        end
    end

    if f.createBtn then
        if f.createBtn.SetText then
            f.createBtn:SetText(sceneMode and L("Add Scene") or L("Create Plan"))
        end
        f.createBtn:SetScript("OnClick", function()
            local selected = f.selectedArena
            if not selected then return end
            if sceneMode then
                if Diar.AddSceneFromArena and Diar:AddSceneFromArena(selected) then
                    f:Hide()
                end
            elseif Diar.PromptCreatePlanName then
                Diar:PromptCreatePlanName(selected, f)
            else
                if Diar:CreateNewPlan(selected) then
                    f:Hide()
                end
            end
        end)
    end

    if f.expansionTabsContainer then
        local x = 0
        local tabGap = 6
        for i, expNode in ipairs(f.expansions or {}) do
            local exp = tostring(expNode.expansion or "Other")
            local tab = CreatePlannerIconBtn(f.expansionTabsContainer, exp, 120, 24)
            local w = math.min(180, math.max(76, 18 + (exp:len() * 7)))
            tab:SetWidth(w)
            tab:ClearAllPoints()
            tab:SetPoint("LEFT", f.expansionTabsContainer, "LEFT", x, 0)
            tab.expansion = exp
            tab:SetScript("OnClick", function(s)
                f.selectedExpansion = s.expansion
                UpdateExpansionTabState()
                RenderRaidsForExpansion()
            end)
            f.expansionTabs[#f.expansionTabs + 1] = tab
            x = x + w + tabGap
        end
    end

    if f.expansions and #f.expansions > 0 then
        f.selectedExpansion = tostring(f.expansions[1].expansion or "")
        UpdateExpansionTabState()
        RenderRaidsForExpansion()
    else
        RefreshCreateButton()
    end

    if f.title then
        f.title:SetText(sceneMode and L("Add new scene") or L("Create new plan"))
    end
    if f.hint then
        if sceneMode then
            f.hint:SetText(L("Select Expansion -> Raid -> Boss -> Background for the new scene."))
        else
            f.hint:SetText(L("Select Expansion -> Raid -> Boss -> Background for Scene 1."))
        end
    end

    Diar:PrepareModal(f, self.plannerFrame or self.frame)
    f:Show()
end
