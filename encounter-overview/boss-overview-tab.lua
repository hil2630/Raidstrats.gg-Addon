local addonName = ...
local AceAddon = LibStub("AceAddon-3.0")
local Addon =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)
if not Addon then return end
local function L(key) return RSGG_L(key) end

-- Temporary kill-switch: keep the feature code in place, but do not run any
-- Encounter Journal overview behavior until we re-enable it.
local BOSS_OVERVIEW_FEATURE_ENABLED = false
if not BOSS_OVERVIEW_FEATURE_ENABLED then
    return
end

local OVERVIEW_TAB_NAME = "RaidstratsOverviewTab"
local OVERVIEW_WINDOW_NAME = "RaidstratsOverviewWindow"
local OVERVIEW_ICON = 1519351 -- Raidstrats.gg addon icon (same as the minimap button).
local PositionOverviewWindow
local SetOverviewPageShown
local UpdateOverviewContents
local currentOverviewRole = "dps"
local ROLE_ICONS = {
    tank = "Interface\\AddOns\\Raidstratsgg\\icons\\roles\\tank.tga",
    healer = "Interface\\AddOns\\Raidstratsgg\\icons\\roles\\healer.tga",
    dps = "Interface\\AddOns\\Raidstratsgg\\icons\\roles\\rdps.tga",
}
local overviewActive = false

local function GetSettingsTable()
    if Addon.GetPlannerSettings then
        return Addon:GetPlannerSettings()
    end
    RaidstratsggSettings = RaidstratsggSettings or {}
    return RaidstratsggSettings
end

function Addon:IsEncounterOverviewTabEnabled()
    local s = GetSettingsTable()
    if s.showEncounterOverviewTab == nil then
        s.showEncounterOverviewTab = true
    end
    return s.showEncounterOverviewTab == true or s.showEncounterOverviewTab == 1
end

local function SafeLower(value)
    return strlower(strtrim(tostring(value or "")))
end

local function GetSpellDisplayLink(spellId)
    local id = tonumber(spellId)
    if not id or id <= 0 then return nil end

    local link = nil
    if C_Spell and C_Spell.GetSpellLink then
        link = C_Spell.GetSpellLink(id)
    end
    if (not link or link == "") and type(GetSpellLink) == "function" then
        link = GetSpellLink(id)
    end
    if type(link) == "string" and link ~= "" then
        return link
    end

    local name = nil
    if C_Spell and C_Spell.GetSpellName then
        name = C_Spell.GetSpellName(id)
    end
    if (not name or name == "") and type(GetSpellInfo) == "function" then
        name = GetSpellInfo(id)
    end
    if type(name) == "string" and name ~= "" then
        return ("|cff71d5ff[%s]|r"):format(name)
    end
    return ("|cff71d5ff[Spell %d]|r"):format(id)
end

local function StripOverviewHtml(text)
    if type(text) ~= "string" or text == "" then return text end
    local out = text
    out = out:gsub("\r", "")
    out = out:gsub("<[bB][rR]%s*/?>", "\n")
    out = out:gsub("</[pP]>", "\n")
    out = out:gsub("<[pP][^>]*>", "")
    out = out:gsub("<[uU][lL][^>]*>", "")
    out = out:gsub("</[uU][lL]>", "\n")
    out = out:gsub("<[oO][lL][^>]*>", "")
    out = out:gsub("</[oO][lL]>", "\n")
    out = out:gsub("<[lL][iI][^>]*>", "- ")
    out = out:gsub("</[lL][iI]>", "\n")
    out = out:gsub("<[^>]+>", "")

    -- Common HTML entities from WYSIWYG export.
    out = out:gsub("&nbsp;", " ")
    out = out:gsub("&amp;", "&")
    out = out:gsub("&lt;", "<")
    out = out:gsub("&gt;", ">")
    out = out:gsub("&quot;", "\"")
    out = out:gsub("&#39;", "'")

    -- Cleanup excessive whitespace/newlines.
    out = out:gsub("[ \t]+\n", "\n")
    out = out:gsub("\n[ \t]+", "\n")
    out = out:gsub("\n\n\n+", "\n\n")
    return strtrim(out)
end

local function ExpandOverviewShortcodes(text)
    if type(text) ~= "string" or text == "" then return text end
    return text:gsub("%[spell=(%d+)%]", function(id)
        return GetSpellDisplayLink(id) or ("[spell=%s]"):format(id)
    end)
end

local function PrepareOverviewDisplayText(text)
    return ExpandOverviewShortcodes(StripOverviewHtml(text))
end

local function NormalizeRoleKey(role)
    local key = SafeLower(role)
    if key == "tank" or key == "healer" or key == "dps" then
        return key
    end
    return "dps"
end

local function ResolveRoleText(customEntry, roleKey)
    if type(customEntry) == "string" and customEntry ~= "" then
        return customEntry
    end
    if type(customEntry) ~= "table" then
        return nil
    end
    roleKey = NormalizeRoleKey(roleKey)
    local roles = customEntry.roles
    if type(roles) == "table" then
        local byRole = roles[roleKey]
        if type(byRole) == "string" and strtrim(byRole) ~= "" then
            return byRole
        end
    end
    local inlineRole = customEntry[roleKey]
    if type(inlineRole) == "string" and strtrim(inlineRole) ~= "" then
        return inlineRole
    end
    if type(customEntry.default) == "string" and strtrim(customEntry.default) ~= "" then
        return customEntry.default
    end
    return nil
end

local function ResolveBossOverviewText(encounterID, roleKey)
    if not encounterID then return nil, nil end
    local name, description = EJ_GetEncounterInfo(encounterID)
    local key = SafeLower(name)
    local customDb = Addon.BossOverviewData
    local customText = customDb and customDb.byName and customDb.byName[key]
    local roleText = ResolveRoleText(customText, roleKey)
    if type(roleText) == "string" and roleText ~= "" then
        return name, PrepareOverviewDisplayText(roleText)
    end
    if type(customText) == "string" and customText ~= "" then
        return name, PrepareOverviewDisplayText(customText)
    end
    if type(description) == "string" and strtrim(description) ~= "" then
        return name, PrepareOverviewDisplayText(description)
    end
    return name, PrepareOverviewDisplayText("No overview is available for this boss yet.")
end

local function EnsureOverviewWindow()
    if _G[OVERVIEW_WINDOW_NAME] then
        return _G[OVERVIEW_WINDOW_NAME]
    end

    -- Anchor to the right-side reading panel only (never the left boss list).
    local info = _G["EncounterJournalEncounterFrameInfo"]
    local parent = info or _G["EncounterJournalInset"] or (_G["EncounterJournal"] or UIParent)
    local win = CreateFrame("Frame", OVERVIEW_WINDOW_NAME, parent)
    win:EnableMouse(true)
    win:SetFrameStrata((parent and parent:GetFrameStrata()) or "MEDIUM")
    win:SetFrameLevel(((parent and parent:GetFrameLevel()) or 1) + 5)

    -- No custom background: we sit on Blizzard's native content parchment and just
    -- hide the right-side widgets, so the page is native and the left list is untouched.

    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", win, "TOPLEFT", 24, -18)
    title:SetPoint("TOPRIGHT", win, "TOPRIGHT", -24, -18)
    title:SetJustifyH("LEFT")
    title:SetText(L("Boss Overview"))
    title:SetTextColor(0.12, 0.12, 0.12, 1)
    if title.SetShadowOffset then title:SetShadowOffset(0, 0) end
    if title.SetShadowColor then title:SetShadowColor(0, 0, 0, 0) end
    win.title = title

    local subtitle = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetPoint("TOPRIGHT", win, "TOPRIGHT", -24, -4)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetTextColor(0.18, 0.18, 0.18, 1)
    if subtitle.SetShadowOffset then subtitle:SetShadowOffset(0, 0) end
    if subtitle.SetShadowColor then subtitle:SetShadowColor(0, 0, 0, 0) end
    subtitle:SetText(L("Raidstrats quick boss notes"))
    win.subtitle = subtitle

    local roleBar = CreateFrame("Frame", nil, win)
    roleBar:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -8)
    roleBar:SetSize(300, 24)
    win.roleBar = roleBar

    local roles = {
        { key = "tank", label = L("Tank") },
        { key = "healer", label = L("Healer") },
        { key = "dps", label = L("DPS") },
    }
    local roleButtons = {}
    local prev
    for _, role in ipairs(roles) do
        local b = CreateFrame("Button", nil, roleBar, "BackdropTemplate")
        b:SetSize(96, 22)
        if prev then
            b:SetPoint("LEFT", prev, "RIGHT", 4, 0)
        else
            b:SetPoint("LEFT", roleBar, "LEFT", 0, 0)
        end
        if b.SetBackdrop then
            b:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
                insets = { left = 0, right = 0, top = 0, bottom = 0 }
            })
            b:SetBackdropColor(0.08, 0.09, 0.12, 1.0)
            b:SetBackdropBorderColor(0.20, 0.24, 0.30, 1.0)
        end
        b:SetAlpha(1)
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("LEFT", b, "LEFT", 8, 0)
        icon:SetTexture(ROLE_ICONS[role.key])
        b.icon = icon
        local txt = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        txt:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        txt:SetText(role.label)
        txt:SetTextColor(0.86, 0.88, 0.92, 1)
        if txt.SetShadowOffset then txt:SetShadowOffset(0, 0) end
        if txt.SetShadowColor then txt:SetShadowColor(0, 0, 0, 0) end
        b.label = txt
        b.roleKey = role.key
        b.tooltipLabel = role.label
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.tooltipLabel or self.roleKey, 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
        b:SetScript("OnClick", function(self)
            currentOverviewRole = self.roleKey
            if win.UpdateRoleButtons then
                win:UpdateRoleButtons()
            end
            if UpdateOverviewContents then
                UpdateOverviewContents()
            end
            if overviewActive then
                SetOverviewPageShown(true)
            end
        end)
        table.insert(roleButtons, b)
        prev = b
    end
    win.roleButtons = roleButtons
    function win:UpdateRoleButtons()
        for _, b in ipairs(self.roleButtons or {}) do
            local selected = (b.roleKey == NormalizeRoleKey(currentOverviewRole))
            b.__selected = selected
            if b.label then
                if selected then
                    b.label:SetTextColor(1, 1, 1, 1)
                else
                    b.label:SetTextColor(0.86, 0.88, 0.92, 1)
                end
            end
        end
    end

    local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", win, "TOPLEFT", 24, -94)
    scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -34, 18)
    win.scroll = scroll

    local textHost = CreateFrame("Frame", nil, scroll)
    textHost:SetSize(1, 1)
    scroll:SetScrollChild(textHost)
    win.textHost = textHost

    local body = CreateFrame("SimpleHTML", nil, textHost)
    body:SetPoint("TOPLEFT", textHost, "TOPLEFT", 0, 0)
    body:SetWidth(1)
    body:SetHeight(1)
    body:SetFontObject("p", "GameFontHighlight")
    body:SetJustifyH("p", "LEFT")
    body:SetHyperlinksEnabled(true)
    body:EnableMouse(true)
    body:SetTextColor("p", 0.14, 0.14, 0.14, 1)
    body:SetShadowOffset("p", 0, 0)
    body:SetShadowColor("p", 0, 0, 0, 0)
    body:SetText("")
    body:SetScript("OnHyperlinkEnter", function(self, link)
        if not link or link == "" then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
        GameTooltip:SetHyperlink(link)
        GameTooltip:Show()
    end)
    body:SetScript("OnHyperlinkLeave", function()
        GameTooltip:Hide()
    end)
    body:SetScript("OnHyperlinkClick", function(self, link, text, button)
        if SetItemRef then
            SetItemRef(link, text or link, button, self)
        end
    end)
    win.body = body

    win:HookScript("OnSizeChanged", function(self)
        local width = math.max(1, self:GetWidth() - 52)
        if self.textHost then
            self.textHost:SetWidth(width)
        end
        if self.body then self.body:SetWidth(width) end
    end)

    win:SetAlpha(1)
    if win.UpdateRoleButtons then
        win:UpdateRoleButtons()
    end
    win:Hide()
    PositionOverviewWindow(win)
    return win
end

PositionOverviewWindow = function(win)
    if not win then return end
    win:ClearAllPoints()
    -- Match the right-side reading panel exactly so the left boss list stays visible.
    local info = _G["EncounterJournalEncounterFrameInfo"]
    local panel = info and (info.overviewScroll or info.detailsScroll)
    if panel then
        win:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 4)
        win:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
        return
    end
    if info then
        -- Fallback: inset the left edge so we clear the boss list column.
        win:SetPoint("TOPLEFT", info, "TOPLEFT", 220, -10)
        win:SetPoint("BOTTOMRIGHT", info, "BOTTOMRIGHT", -8, 8)
        return
    end
    local journal = _G["EncounterJournal"]
    if not journal then return end
    win:SetPoint("TOPLEFT", journal, "TOPLEFT", 280, -78)
    win:SetPoint("BOTTOMRIGHT", journal, "BOTTOMRIGHT", -26, 26)
end

-- Clone a single texture region from a native tab so our button matches it pixel-for-pixel.
local function CloneTabTexture(source, dest, layer)
    if not source then return nil end
    local tex = dest:CreateTexture(nil, layer or "ARTWORK")
    tex:SetAllPoints(dest)
    local atlas = source.GetAtlas and source:GetAtlas()
    if atlas then
        tex:SetAtlas(atlas, false)
    else
        local file = source.GetTexture and source:GetTexture()
        if file then
            tex:SetTexture(file)
            if source.GetTexCoord then
                tex:SetTexCoord(source:GetTexCoord())
            end
        end
    end
    return tex
end

local function CreateOverviewTriggerButton(parent)
    if _G[OVERVIEW_TAB_NAME] then
        return _G[OVERVIEW_TAB_NAME]
    end

    local modelTab = _G["EncounterJournalEncounterFrameInfoModelTab"]
        or (parent and parent.modelTab)
    local btn = CreateFrame("Button", OVERVIEW_TAB_NAME, parent, "BackdropTemplate")

    -- Match the native model tab's exact size and place it directly below.
    local tabW, tabH = 115, 24
    if modelTab and modelTab.GetSize then
        local w, h = modelTab:GetSize()
        if w and w > 4 then tabW = w end
        if h and h > 4 then tabH = h end
    end
    btn:SetSize(tabW, tabH)
    if modelTab then
        btn:SetPoint("TOPLEFT", modelTab, "BOTTOMLEFT", 0, -1)
    else
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -26)
    end

    -- Draw above the inset's right-edge border (EncounterJournal.NineSlice.RightEdge,
    -- frame level ~500) so the tab sits on top of that line instead of behind it.
    btn:SetFrameStrata("HIGH")
    if modelTab and modelTab.GetFrameLevel then
        btn:SetFrameLevel(modelTab:GetFrameLevel() + 5)
    end

    -- Clone the native side-tab's actual ".texture" region (this is what EJ tabs use,
    -- not a NormalTexture) so the chrome is pixel-identical to Overview/Boss/Loot/Model.
    local srcTex = (modelTab and modelTab.texture)
        or (modelTab and modelTab.GetNormalTexture and modelTab:GetNormalTexture())
    local tabTex = CloneTabTexture(srcTex, btn, "ARTWORK")
    if tabTex then
        tabTex:ClearAllPoints()
        tabTex:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        tabTex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
        tabTex:SetAlpha(0.8)
        btn.texture = tabTex
    elseif Addon.SetBackdrop then
        Addon.SetBackdrop(btn, { 0.08, 0.09, 0.12, 0.98 }, { 0.20, 0.24, 0.30, 1.0 }, 1)
    end

    -- Label: "RS" stacked over "GG" (GG in Raidstrats blue #60a5fa),
    -- using the native tab's font face when available.
    local srcFont = (modelTab and modelTab.text)
        or (modelTab and modelTab.GetFontString and modelTab:GetFontString())
    local fontObj = (srcFont and srcFont.GetFontObject and srcFont:GetFontObject())
    local fontFile, _, fontFlags
    if fontObj and fontObj.GetFont then
        fontFile, _, fontFlags = fontObj:GetFont()
    end
    local lineSize = 14
    -- Grow the tab vertically if needed so both bigger lines fit.
    local neededH = lineSize * 2 + 6
    if neededH > tabH then
        tabH = neededH
        btn:SetSize(tabW, tabH)
    end
    local function MakeLabel()
        local fs = btn:CreateFontString(nil, "OVERLAY")
        if fontFile then
            fs:SetFont(fontFile, lineSize, fontFlags)
        else
            fs:SetFontObject("GameFontNormalLarge")
        end
        return fs
    end

    local btnText = MakeLabel()
    btnText:SetPoint("BOTTOM", btn, "CENTER", 0, 1)
    btnText:SetText("RS")
    btnText:SetTextColor(1, 1, 1) -- always white
    btn.text = btnText

    local ggText = MakeLabel()
    ggText:SetPoint("TOP", btn, "CENTER", 0, -1)
    ggText:SetText("GG")
    ggText:SetTextColor(0.376, 0.647, 0.980) -- #60a5fa
    btn.gg = ggText

    -- Replicate Blizzard's native tab hover/press feedback.
    btn:SetScript("OnEnter", function(self)
        if self.texture then self.texture:SetAlpha(1.0) end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L("Raidstrats.gg overview"), 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        if self.texture and not self.__selected then self.texture:SetAlpha(0.8) end
        GameTooltip:Hide()
    end)
    btn:SetScript("OnMouseDown", function(self)
        if self.texture then
            self.texture:ClearAllPoints()
            self.texture:SetPoint("TOPLEFT", self, "TOPLEFT", 1, -1)
            self.texture:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 1, -1)
        end
    end)
    btn:SetScript("OnMouseUp", function(self)
        if self.texture then
            self.texture:ClearAllPoints()
            self.texture:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
            self.texture:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
        end
    end)

    btn.__selected = false
    local function SetSelected(self, selected)
        self.__selected = selected and true or false
        if self.texture then
            self.texture:SetAlpha(selected and 1.0 or 0.8)
        end
        if self.text then
            self.text:SetTextColor(1, 1, 1)
        end
    end
    btn.SetSelected = SetSelected
    btn:SetSelected(false)

    return btn
end

-- Make the native EJ side tabs look unselected (their selected state is the
-- ".texture" alpha: 0.8 idle / 1.0 selected).
local function DeselectNativeTabs()
    local info = _G["EncounterJournalEncounterFrameInfo"]
    if not info then return end
    for _, key in ipairs({ "overviewTab", "bossTab", "lootTab", "modelTab" }) do
        local t = info[key]
        if t and t.texture and t.texture.SetAlpha then
            t.texture:SetAlpha(0.8)
        end
    end
end

SetOverviewPageShown = function(shown)
    overviewActive = shown and true or false
    local win = _G[OVERVIEW_WINDOW_NAME]
    local tab = _G[OVERVIEW_TAB_NAME]
    if tab and tab.SetSelected then
        tab:SetSelected(shown)
    end
    if not win then return end
    if shown then
        PositionOverviewWindow(win)
        win:Show()
        -- Ours is active, so none of the native tabs should look active.
        DeselectNativeTabs()
        -- Hide only RIGHT-side content/text widgets. Never touch the left boss
        -- list (BossesScrollBox / bossesScroll), so boss selection stays usable.
        local info = _G["EncounterJournalEncounterFrameInfo"]
        if info then
            if info.overviewScroll then info.overviewScroll:Hide() end
            if info.detailsScroll then info.detailsScroll:Hide() end
            if info.LootContainer then info.LootContainer:Hide() end
            if info.model then info.model:Hide() end
            if info.encounterTitle then info.encounterTitle:Hide() end
            if info.difficulty then info.difficulty:Hide() end
            if info.reset then info.reset:Hide() end
            if info.instanceButton then info.instanceButton:Hide() end
            if info.rightShadow then info.rightShadow:Hide() end
        end
        local encounter = _G["EncounterJournal"] and EncounterJournal.encounter
        if encounter and encounter.instance then
            encounter.instance:Hide()
        end
        if _G["EncounterJournalEncounterFrameInfoModelScene"] then
            _G["EncounterJournalEncounterFrameInfoModelScene"]:Hide()
        end
        if _G["EncounterJournalEncounterFrameInfoModelFrame"] then
            _G["EncounterJournalEncounterFrameInfoModelFrame"]:Hide()
        end
        if _G["EncounterJournalEncounterFrameInfoDetailsScrollChild"] then
            _G["EncounterJournalEncounterFrameInfoDetailsScrollChild"]:Hide()
        end
        -- Hide the model/creature selector buttons (Model tab leftovers).
        if type(EncounterJournal_HideCreatures) == "function" then
            pcall(EncounterJournal_HideCreatures)
        end
        for i = 1, 20 do
            local creatureBtn = _G["EncounterJournalEncounterFrameInfoCreatureButton" .. i]
            if creatureBtn then creatureBtn:Hide() end
        end
    else
        win:Hide()
    end
end

UpdateOverviewContents = function()
    local parent = _G["EncounterJournalEncounterFrameInfo"]
    if not parent then return end

    local tab = CreateOverviewTriggerButton(parent)
    local win = EnsureOverviewWindow()
    if not tab or not win then return end

    local enabled = Addon:IsEncounterOverviewTabEnabled()
    if not enabled then
        tab:Hide()
        SetOverviewPageShown(false)
        return
    end
    tab:Show()

    local encounterID = EncounterJournal and EncounterJournal.encounterID
    local roleKey = NormalizeRoleKey(currentOverviewRole)
    local bossName, text = ResolveBossOverviewText(encounterID, roleKey)
    win.title:SetText(L("Boss Overview - %s"):format(bossName or L("Unknown")))
    if win.subtitle then
        local roleLabel = (roleKey == "tank" and L("Tank"))
            or (roleKey == "healer" and L("Healer"))
            or L("DPS")
        win.subtitle:SetText(L("Raidstrats quick boss notes - %s"):format(roleLabel))
    end
    win.body:SetText(text or "No overview available.")
    if win.UpdateRoleButtons then
        win:UpdateRoleButtons()
    end
    local textHeight = 0
    if win.body then
        if win.body.GetContentHeight then
            textHeight = tonumber(win.body:GetContentHeight()) or 0
        elseif win.body.GetStringHeight then
            textHeight = tonumber(win.body:GetStringHeight()) or 0
        end
    end
    if win.textHost then
        win.textHost:SetHeight(math.max(1, textHeight + 10))
    end

    -- Hide the scrollbar when the content fits (no scrolling needed yet).
    if win.scroll then
        local visibleH = win.scroll:GetHeight() or 0
        local needsScroll = textHeight > (visibleH + 1)
        local bar = win.scroll.ScrollBar or win.scroll.scrollBar
        if bar then
            if needsScroll then bar:Show() else bar:Hide() end
        end
        if not needsScroll and win.scroll.SetVerticalScroll then
            win.scroll:SetVerticalScroll(0)
        end
    end

    -- If our page was active (e.g. user switched bosses), keep it active and just
    -- swap to the new boss instead of falling back to a native tab.
    if overviewActive then
        SetOverviewPageShown(true)
    elseif win:IsShown() then
        PositionOverviewWindow(win)
    end
end

function Addon:UpdateEncounterJournalOverviewVisibility()
    UpdateOverviewContents()
end

local function HookEncounterJournal()
    local parent = _G["EncounterJournalEncounterFrameInfo"]
    if not parent then return false end

    local tab = CreateOverviewTriggerButton(parent)
    local win = EnsureOverviewWindow()
    if tab and win then
        tab:SetScript("OnClick", function()
            UpdateOverviewContents()
            SetOverviewPageShown(true)
        end)
    end
    UpdateOverviewContents()

    hooksecurefunc("EncounterJournal_DisplayEncounter", function()
        UpdateOverviewContents()
        -- Blizzard may finish drawing the encounter on a later frame; re-assert
        -- our page so switching bosses keeps the overview active on the new boss.
        if overviewActive then
            C_Timer.After(0, function()
                if overviewActive then
                    UpdateOverviewContents()
                    SetOverviewPageShown(true)
                end
            end)
        end
    end)
    hooksecurefunc("EncounterJournal_ToggleHeaders", function()
        UpdateOverviewContents()
    end)
    -- Unload our custom page when switching instance/raid (not boss).
    -- This keeps behavior clean when navigating to another raid or dungeon.
    hooksecurefunc("EncounterJournal_DisplayInstance", function()
        if overviewActive then
            SetOverviewPageShown(false)
        end
    end)

    local journal = _G["EncounterJournal"]
    if journal then
        journal:HookScript("OnHide", function()
            SetOverviewPageShown(false)
        end)
    end

    -- Only a genuine user click on a native tab should deactivate our page.
    -- Programmatic :Click() calls (e.g. during boss switching) must NOT, so the
    -- overview stays active and just follows the newly selected boss.
    local function IsUserClicking(frame)
        local focus
        if GetMouseFoci then
            local foci = GetMouseFoci()
            focus = foci and foci[1]
        elseif GetMouseFocus then
            focus = GetMouseFocus()
        end
        return focus == frame
    end
    local function HookNativeTab(t)
        if not t then return end
        t:HookScript("OnClick", function(self)
            if IsUserClicking(self) then
                SetOverviewPageShown(false)
            end
        end)
    end
    HookNativeTab(parent.overviewTab)
    HookNativeTab(parent.bossTab)
    HookNativeTab(parent.lootTab)
    HookNativeTab(parent.modelTab)
    return true
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Blizzard_EncounterJournal" then
        HookEncounterJournal()
        return
    end
    if event == "PLAYER_LOGIN" then
        if not HookEncounterJournal() then
            C_Timer.After(1.0, function()
                HookEncounterJournal()
            end)
        end
    end
end)
