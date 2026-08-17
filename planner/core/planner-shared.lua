-- Raidstrats.gg Planner - shared UI helpers and layout constants
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
local SkinScrollBar = Diar.SkinScrollBar

Diar.PlannerUI = Diar.PlannerUI or {}
local PUI = Diar.PlannerUI

PUI.RIGHT_PANEL_W = 248
PUI.UI_PAD = 16
PUI.TITLE_TOP = 16
PUI.TOOLBAR_TOP = 46
PUI.TOOLBAR_H = 34
PUI.CANVAS_TOP = 90
PUI.BRAND_TITLE_TEXT = L("Raidstrats.gg - Raidplanner & Assignments")
PUI.BRAND_TITLE_OFFSET_X = 20
PUI.PLAN_TITLE_MAX_LEN = 50
PUI.ROW_GAP = 10
PUI.CONTROLS_H = 30
PUI.TIMELINE_H = 30
PUI.SCENE_TAB_H = 18
PUI.GROUP_LEADER_ICON = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
PUI.PATREON_BOX_H = 52
PUI.RIGHT_COL_GAP = 8
PUI.UI = {
    PANEL   = {0.06, 0.06, 0.09, 0.96},
    BORDER  = {0.22, 0.24, 0.28, 1},
    TOOLBAR = {0.05, 0.05, 0.08, 0.92},
    ROW     = {0.09, 0.10, 0.13, 0.92},
    ROW_HOV = {0.14, 0.16, 0.20, 1},
    ACCENT  = {0.23, 0.51, 0.96, 1},
}

PUI.HIGHLIGHT_TEXT = { 1.00, 0.92, 0.35 }

-- Plan text can be any language regardless of client locale. Friz Quadrata
-- (FRIZQT__) is Latin-only; FRIZQT___CYR adds Cyrillic but not CJK. Pick a
-- bundled client font from the string so imported Chinese/Russian still
-- measures and draws on enUS clients (otherwise GetStringWidth is ~0 and
-- the widget collapses).
local CYR_FONT_CANDIDATES = {
    "Fonts\\FRIZQT___CYR.TTF",
    "Fonts\\ARIALN.TTF",
}

local function CjkFontCandidates()
    local loc = GetLocale and GetLocale() or ""
    if loc == "zhTW" then
        return { "Fonts\\bLEI00D.TTF", "Fonts\\ARHei.ttf", "Fonts\\ARKai_T.TTF" }
    end
    if loc == "koKR" then
        return { "Fonts\\2002.TTF", "Fonts\\ARKai_T.TTF", "Fonts\\ARHei.ttf" }
    end
    return { "Fonts\\ARKai_T.TTF", "Fonts\\ARHei.ttf", "Fonts\\bLEI00D.TTF", "Fonts\\2002.TTF" }
end

local function FontPathMatches(applied, path)
    if type(applied) ~= "string" or type(path) ~= "string" then return false end
    local normalized = applied:gsub("/", "\\"):lower()
    local want = path:gsub("/", "\\"):lower()
    if normalized == want then return true end
    local file = want:match("([^\\]+)$")
    return file and normalized:find(file, 1, true) and true or false
end

local function ProbeFontPath(candidates)
    local probe = PUI._fontProbe
    if not probe then
        probe = UIParent:CreateFontString(nil, "BACKGROUND")
        probe:Hide()
        PUI._fontProbe = probe
    end
    for i = 1, #candidates do
        local path = candidates[i]
        probe:SetFont(path, 12, "")
        if FontPathMatches(probe.GetFont and probe:GetFont(), path) then
            return path
        end
    end
    return nil
end

local function Utf8CodepointAt(s, i)
    local c = s:byte(i)
    if not c then return nil, i end
    if c < 0x80 then return c, i + 1 end
    local c2 = s:byte(i + 1)
    if c < 0xE0 then
        if not c2 then return c, i + 1 end
        return (c - 0xC0) * 0x40 + (c2 - 0x80), i + 2
    end
    local c3 = s:byte(i + 2)
    if c < 0xF0 then
        if not c2 or not c3 then return c, i + 1 end
        return (c - 0xE0) * 0x1000 + (c2 - 0x80) * 0x40 + (c3 - 0x80), i + 3
    end
    local c4 = s:byte(i + 3)
    if not c2 or not c3 or not c4 then return c, i + 1 end
    return (c - 0xF0) * 0x40000 + (c2 - 0x80) * 0x1000 + (c3 - 0x80) * 0x40 + (c4 - 0x80), i + 4
end

local function IsCyrillicCodepoint(cp)
    return (cp >= 0x0400 and cp <= 0x052F)
        or (cp >= 0x2DE0 and cp <= 0x2DFF)
        or (cp >= 0xA640 and cp <= 0xA69F)
end

local function IsHangulCodepoint(cp)
    return (cp >= 0x1100 and cp <= 0x11FF)
        or (cp >= 0x3130 and cp <= 0x318F)
        or (cp >= 0xAC00 and cp <= 0xD7AF)
end

local function IsCjkCodepoint(cp)
    return (cp >= 0x2E80 and cp <= 0x9FFF)
        or (cp >= 0xF900 and cp <= 0xFAFF)
        or (cp >= 0xFE30 and cp <= 0xFE4F)
        or (cp >= 0xFF00 and cp <= 0xFFEF)
        or (cp >= 0x20000 and cp <= 0x2FA1F)
end

function PUI.ScriptForText(text)
    local s = tostring(text or "")
    local cjk, cyr, hangul = 0, 0, 0
    local i, n = 1, #s
    while i <= n do
        local cp
        cp, i = Utf8CodepointAt(s, i)
        if not cp then break end
        if IsHangulCodepoint(cp) then
            hangul = hangul + 1
        elseif IsCjkCodepoint(cp) then
            cjk = cjk + 1
        elseif IsCyrillicCodepoint(cp) then
            cyr = cyr + 1
        end
    end
    if hangul > 0 and hangul >= cjk and hangul >= cyr then return "ko" end
    if cjk > 0 and cjk >= cyr then return "cjk" end
    if cyr > 0 then return "cyr" end
    return "latin"
end

function PUI.GetPlannerContentFont(text)
    local script = PUI.ScriptForText(text)
    local cache = PUI._contentFontByScript
    if type(cache) ~= "table" then
        cache = {}
        PUI._contentFontByScript = cache
    end
    if cache[script] then return cache[script] end

    local path
    if script == "cjk" then
        path = ProbeFontPath(CjkFontCandidates())
    elseif script == "ko" then
        path = ProbeFontPath({ "Fonts\\2002.TTF", "Fonts\\ARKai_T.TTF", "Fonts\\ARHei.ttf" })
    else
        path = ProbeFontPath(CYR_FONT_CANDIDATES)
    end
    path = path or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    cache[script] = path
    if script == "latin" then
        PUI._contentFont = path
    end
    return path
end

function PUI.SetPlannerContentFont(fs, size, flags, text)
    if not fs or not fs.SetFont then return end
    fs:SetFont(PUI.GetPlannerContentFont(text), size or 12, flags or "")
end

function PUI.TruncateUtf8(s, maxBytes)
    s = tostring(s or "")
    maxBytes = tonumber(maxBytes) or 0
    if maxBytes <= 0 then return "" end
    if #s <= maxBytes then return s end
    local i, last = 1, 0
    while i <= maxBytes do
        local c = s:byte(i)
        if not c then break end
        local len = 1
        if c >= 0xF0 then len = 4
        elseif c >= 0xE0 then len = 3
        elseif c >= 0xC0 then len = 2
        end
        if i + len - 1 > maxBytes then break end
        last = i + len - 1
        i = i + len
    end
    return s:sub(1, last)
end

function PUI.SkinPlannerScroll(scrollFrame)
    if SkinScrollBar then SkinScrollBar(scrollFrame) end
end

function PUI.TruncatePlannerPlanTitle(name, maxLen)
    maxLen = maxLen or PUI.PLAN_TITLE_MAX_LEN or 20
    name = strtrim(tostring(name or ""))
    if name == "" then return L("Raid plan") end
    if #name <= maxLen then return name end
    if maxLen <= 3 then return PUI.TruncateUtf8(name, maxLen) end
    return PUI.TruncateUtf8(name, maxLen - 3) .. "..."
end

function PUI.PositionPlannerBrandTitle(brandTitle, parent)
    if not brandTitle or not parent then return end
    brandTitle:ClearAllPoints()
    brandTitle:SetPoint("TOP", parent, "TOP", PUI.BRAND_TITLE_OFFSET_X or 0, -(PUI.TITLE_TOP or 16))
end

function PUI.SetPlannerBtnText(btn, text)
    if not btn then return end
    if btn.label then btn.label:SetText(text or "")
    elseif btn.SetText then btn:SetText(text or "") end
end

function PUI.CreatePlannerIconBtn(parent, text, w, h)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w or 88, h or 28)
    SetBackdrop(b, PUI.UI.ROW, PUI.UI.BORDER, 1)
    local t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("CENTER")
    t:SetText(text or "")
    t:SetTextColor(0.92, 0.92, 0.92)
    b.label = t
    b.SetText = function(self, txt) self.label:SetText(txt or "") end
    b:SetScript("OnEnter", function(s)
        s:SetBackdropColor(unpack(PUI.UI.ROW_HOV))
        s.label:SetTextColor(1, 1, 1)
    end)
    b:SetScript("OnLeave", function(s)
        if s.selected then return end
        s:SetBackdropColor(unpack(PUI.UI.ROW))
        s.label:SetTextColor(0.92, 0.92, 0.92)
    end)
    return b
end

function PUI.SetPlannerBtnShadowHidden(btn)
    if not btn then return end
    if btn.shadow then
        btn.shadow:SetAlpha(0)
        btn.shadow:Hide()
    end
end

function PUI.GetPlayerNameKey()
    local function NormalizeNameToken(name)
        if type(name) ~= "string" then return nil end
        local t = name
        -- Strip WoW color/link wrappers if they leak into parsed roster text.
        t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        t = t:gsub("|H[^|]-|h([^|]-)|h", "%1")
        t = t:gsub("|[^|]-|h", "")
        t = t:gsub("[%z\1-\31\127]", "")
        t = strtrim(t)
        if t == "" then return nil end
        return strlower(t)
    end

    local name, realm = UnitName("player")
    if not name or name == "" then return nil end
    local full = name
    if realm and realm ~= "" then
        full = name .. "-" .. realm
    end
    local key = NormalizeNameToken(full) or NormalizeNameToken(name)
    if not key then return nil end
    local short = key:match("^([^%-]+)") or key
    return short
end

function PUI.LabelMatchesPlayer(label, playerKey)
    if not playerKey or not label or label == "" then return false end
    local t = tostring(label)
    t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    t = t:gsub("|H[^|]-|h([^|]-)|h", "%1")
    t = t:gsub("[%z\1-\31\127]", "")
    t = strlower(strtrim(t))
    if t == "" then return false end
    local short = t:match("^([^%-]+)") or t
    return short == playerKey or t == playerKey
end

function PUI.RosterNameMatchesPlayer(rosterName, playerKey)
    if not playerKey or not rosterName or rosterName == "" then return false end
    if PUI.LabelMatchesPlayer(rosterName, playerKey) then return true end

    local function normalize(name)
        if type(name) ~= "string" then return nil end
        local t = name
        t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        t = t:gsub("|H[^|]-|h([^|]-)|h", "%1")
        t = t:gsub("|[^|]-|h", "")
        t = t:gsub("[%z\1-\31\127]", "")
        t = strlower(strtrim(t))
        if t == "" then return nil end
        return t
    end

    local roster = normalize(rosterName)
    if not roster then return false end
    local rosterShort = roster:match("^([^%-]+)") or roster
    if roster == playerKey or rosterShort == playerKey then return true end

    local name, realm = UnitName("player")
    if not name or name == "" then return false end
    local full = realm and realm ~= "" and (name .. "-" .. realm) or name
    local fullNorm = normalize(full)
    local nameNorm = normalize(name)
    if fullNorm and (roster == fullNorm or rosterShort == fullNorm:match("^([^%-]+)") or fullNorm:match("^([^%-]+)") == rosterShort) then
        return true
    end
    if nameNorm and (roster == nameNorm or rosterShort == nameNorm) then
        return true
    end
    return false
end

function PUI.SceneHasPlayerName(scene, playerKey)
    if not playerKey or not scene or not scene.items then return false end
    for _, item in ipairs(scene.items) do
        local lbl = item.label
        if lbl and lbl ~= "" and PUI.LabelMatchesPlayer(lbl, playerKey) then
            return true
        end
    end
    return false
end

function PUI.ApplyNameHighlight(widget, isMine, hasSelfOnPlan, baseR, baseG, baseB, textFs)
    if not hasSelfOnPlan or not widget or not isMine then return end
    local fs = textFs or widget.text or widget.label
    widget:SetAlpha(1)
    if fs then
        fs:SetTextColor(PUI.HIGHLIGHT_TEXT[1], PUI.HIGHLIGHT_TEXT[2], PUI.HIGHLIGHT_TEXT[3], 1)
    end
    if widget.__groupSpotStroke then return end
    if widget.SetBackdrop and not widget.__highlightBd then
        widget.__highlightBd = true
        widget:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeSize = 1,
        })
        widget:SetBackdropColor(0.12, 0.10, 0.02, 0.35)
        widget:SetBackdropBorderColor(1, 0.85, 0.2, 0.9)
    end
end

function PUI.ClearNameHighlight(widget, textFs, baseR, baseG, baseB)
    if not widget then return end
    widget:SetAlpha(1)
    if widget.__highlightBd and widget.SetBackdrop then
        widget.__highlightBd = nil
        widget:SetBackdrop(nil)
    end
    local fs = textFs or widget.text or widget.label
    if fs then
        if baseR then
            fs:SetTextColor(baseR, baseG, baseB, 1)
        elseif widget.__baseTextColor then
            local c = widget.__baseTextColor
            fs:SetTextColor(c[1], c[2], c[3], 1)
        end
    end
end

function PUI.GetNextAvailableSlotIndex(scene)
    if not scene or type(scene.items) ~= "table" then return 1 end
    local used = {}
    for _, item in ipairs(scene.items) do
        local n = tonumber(item and (item.slotIndex or item.embedIndex))
        if n and n >= 1 then
            used[math.floor(n + 0.0001)] = true
        end
    end
    local idx = 1
    while used[idx] do
        idx = idx + 1
    end
    return idx
end

function PUI.CheckboxIsChecked(cb)
    if not cb then return false end
    if cb.GetChecked then return cb:GetChecked() and true or false end
    if cb.isChecked ~= nil then return cb.isChecked and true or false end
    return false
end

function PUI.SetColorSwatchTexture(tex, color)
    if not tex or not color then return end
    tex:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
end
