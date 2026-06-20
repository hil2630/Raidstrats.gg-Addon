-- Object palette: add shapes, markers, roles, and text to the current scene.
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

Diar.OBJECT_PALETTE_PANEL_W = 108
Diar.OBJECT_PALETTE_GAP = 8
Diar.OBJECT_PALETTE_UI_PAD = 16
Diar.OBJECT_PALETTE_TOOLBAR_TOP = 46
Diar.OBJECT_PALETTE_CANVAS_TOP = 90
Diar.OBJECT_PALETTE_ICON_W_PCT = 3.2

local ICON_BASE_PATH = "Interface\\AddOns\\" .. tostring(addonName) .. "\\icons\\"
local WHITE_TEX = "Interface\\Buttons\\WHITE8X8"
local CIRCLE_MASK = "Interface\\Masks\\CircleMaskScalable"
local RAID_TEX = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"

local RAID_MARKERS = {
    { key = "star", idx = 1 }, { key = "circle", idx = 2 }, { key = "diamond", idx = 3 },
    { key = "triangle", idx = 4 }, { key = "moon", idx = 5 }, { key = "square", idx = 6 },
    { key = "cross", idx = 7 }, { key = "skull", idx = 8 },
}
local RAID_MARKER_KEY_SET = {}
for _, marker in ipairs(RAID_MARKERS) do
    RAID_MARKER_KEY_SET[tostring(marker.key or ""):lower()] = true
end

local ROLE_ENTRIES = {
    { key = "tank", label = "Tank" },
    { key = "healer", label = "Healer" },
    { key = "rdps", label = "Ranged" },
    { key = "mdps", label = "Melee" },
}

local CLASS_ENTRIES = {
    { key = "deathknight", label = "Death Knight" },
    { key = "demonhunter", label = "Demon Hunter" },
    { key = "druid", label = "Druid" },
    { key = "evoker", label = "Evoker" },
    { key = "hunter", label = "Hunter" },
    { key = "mage", label = "Mage" },
    { key = "monk", label = "Monk" },
    { key = "paladin", label = "Paladin" },
    { key = "priest", label = "Priest" },
    { key = "rogue", label = "Rogue" },
    { key = "shaman", label = "Shaman" },
    { key = "warlock", label = "Warlock" },
    { key = "warrior", label = "Warrior" },
}

local SPEC_LABEL_BY_KEY = {
    beastmastery = "Beast Mastery",
    marksmanship = "Marksmanship",
    blood = "Blood",
    frost = "Frost",
    unholy = "Unholy",
    havoc = "Havoc",
    vengeance = "Vengeance",
    devourer = "Devourer",
    balance = "Balance",
    feral = "Feral",
    guardian = "Guardian",
    restoration = "Restoration",
    devastation = "Devastation",
    preservation = "Preservation",
    augmentation = "Augmentation",
    arcane = "Arcane",
    fire = "Fire",
    brewmaster = "Brewmaster",
    windwalker = "Windwalker",
    mistweaver = "Mistweaver",
    holy = "Holy",
    protection = "Protection",
    retribution = "Retribution",
    discipline = "Discipline",
    shadow = "Shadow",
    assassination = "Assassination",
    outlaw = "Outlaw",
    subtlety = "Subtlety",
    elemental = "Elemental",
    enhancement = "Enhancement",
    affliction = "Affliction",
    demonology = "Demonology",
    destruction = "Destruction",
    arms = "Arms",
    fury = "Fury",
    survival = "Survival",
}

local UI = {
    PANEL   = {0.06, 0.06, 0.09, 0.96},
    BORDER  = {0.22, 0.24, 0.28, 1},
    ROW     = {0.09, 0.10, 0.13, 0.92},
    ROW_HOV = {0.14, 0.16, 0.20, 1},
    ACCENT  = {0.23, 0.51, 0.96, 1},
}

local PALETTE_HINT_DEFAULT = "Palette: click item, then canvas · Right-click object to delete"
local PALETTE_HINT_H = 34

if not StaticPopupDialogs["RAIDSTRATSGG_PALETTE_TEXT"] then
    StaticPopupDialogs["RAIDSTRATSGG_PALETTE_TEXT"] = {
        text = "Enter label text:",
        button1 = _G.OKAY or "OK",
        button2 = _G.CANCEL or "Cancel",
        hasEditBox = true,
        maxLetters = 64,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        OnShow = function(self)
            local eb = self.editBox or self.EditBox
            if not eb then return end
            eb:SetText(self.data and self.data.defaultText or "Label")
            eb:HighlightText()
            eb:SetFocus()
        end,
        OnAccept = function(self)
            local eb = self.editBox or self.EditBox
            local text = eb and strtrim(eb:GetText()) or ""
            if text == "" then text = "Label" end
            local base = self.data and self.data.template
            if not base then return end
            local template = {}
            for k, v in pairs(base) do template[k] = v end
            template.label = text
            Diar:BeginPalettePlacement(template, "text")
        end,
    }
end

if not StaticPopupDialogs["RAIDSTRATSGG_DELETE_OBJECT"] then
    StaticPopupDialogs["RAIDSTRATSGG_DELETE_OBJECT"] = {
        text = "Delete this object?",
        button1 = _G.YES or "Yes",
        button2 = _G.NO or "No",
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        OnAccept = function(self)
            local itemIndex = self.data
            if itemIndex and Diar.DeletePlannerSceneItem then
                Diar:DeletePlannerSceneItem(itemIndex)
            end
        end,
    }
end

local PALETTE_COLS = 2
local PALETTE_TILE = 44
local PALETTE_TILE_MIN = 28
local PALETTE_TILE_MAX = 52
local PALETTE_TILE_GAP = 6
local PALETTE_HEADER_H = 18
local PALETTE_SECTION_GAP = 6
local PALETTE_CONTENT_PAD_X = 4
local PALETTE_ICON_CURSOR_OFFSET_X = -10
local PALETTE_ICON_CURSOR_OFFSET_Y = -10
-- Matches planner SETTINGS_ROW_H + UI_PAD so palette bottom aligns with timeline bottom.
local PALETTE_BOTTOM_INSET = 16

local function HasLoadedPlan(data)
    if not data then return false end
    if tostring(data.planName or "") == "No plan" then return false end
    if type(data.scenes) ~= "table" or #data.scenes == 0 then return false end
    return true
end

local function GetReferenceCanvasSize()
    local pf = Diar.plannerFrame
    local cw, ch = 1115, 627
    if pf and pf.canvas then
        cw, ch = pf.canvas:GetSize()
    end
    if not cw or cw <= 0 then cw = 1115 end
    if not ch or ch <= 0 then ch = 627 end
    return cw, ch
end

-- Item w/h are % of canvas width/height — match height % so placed icons stay square.
function Diar:SquareIconPercents(sizeWPct)
    sizeWPct = sizeWPct or self.OBJECT_PALETTE_ICON_W_PCT
    local cw, ch = GetReferenceCanvasSize()
    return sizeWPct, sizeWPct * cw / ch
end

-- Roles are the only palette icons loaded from addon files; everything else uses WoW textures.
local function RoleIconCandidates(roleKey)
    if not roleKey or roleKey == "" then return nil end
    local key = roleKey:lower():gsub("^/+", ""):gsub("^.*/", "")
    return {
        ICON_BASE_PATH .. "roles/" .. key .. ".tga",
        ICON_BASE_PATH .. "roles/" .. key .. ".blp",
    }
end

local function ApplyIngameIconTexture(tex, iconKey)
    if not tex or not iconKey then return false end
    if Diar.GetPlanIconTexture then
        local texPath, texCoord = Diar.GetPlanIconTexture(iconKey)
        if texPath then
            tex:SetTexture(texPath)
            if texCoord and #texCoord >= 4 then
                tex:SetTexCoord(texCoord[1], texCoord[2], texCoord[3], texCoord[4])
            else
                tex:SetTexCoord(0, 1, 0, 1)
            end
            tex:SetVertexColor(1, 1, 1, 1)
            tex:SetAlpha(1)
            return true
        end
    end
    return false
end

local function IsWorldMarkerPaletteItem(item)
    if type(item) ~= "table" then return false end
    if item.worldMarker == true or item.isWorldMarker == true then return true end
    if tostring(item.kind or ""):lower() ~= "icon" then return false end
    local raw = tostring(item.icon or ""):lower()
    if raw == "" then return false end
    raw = raw:gsub("\\", "/")
    local base = raw:match("([^/]+)$") or raw
    if RAID_MARKER_KEY_SET[base] then
        return true
    end
    if raw:find("/worldmarkers/", 1, true)
        or raw:find("worldmarkers/", 1, true)
        or raw:find("world-marker", 1, true)
        or raw:find("world_marker", 1, true)
        or raw:find("worldmarker", 1, true) then
        return true
    end
    if base:match("^worldmarker[_%-]?%d+$")
        or base:match("^world[_%-]?marker[_%-]?%d+$")
        or base:match("^wm%d+$") then
        return true
    end
    return false
end

local function SetTextureFromCandidates(tex, candidates)
    if not tex or not candidates then return false end
    for i = 1, #candidates do
        if tex:SetTexture(candidates[i]) then
            tex:SetTexCoord(0, 1, 0, 1)
            return true
        end
    end
    return false
end

local function SetSquareTileIcon(tex, parent, tileSize, scale)
    scale = scale or 1
    local pad = 3
    local iconSize = math.max(8, (tileSize - pad * 2) * scale)
    tex:ClearAllPoints()
    tex:SetSize(iconSize, iconSize)
    tex:SetPoint("CENTER", parent, "CENTER", 0, 0)
end

local function ApplyCircleTileIcon(tex, parent, tileSize)
    SetSquareTileIcon(tex, parent, tileSize)
    tex:SetTexture(WHITE_TEX)
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetVertexColor(0.92, 0.30, 0.30, 0.95)
    tex:SetAlpha(1)
    tex:Show()
    if not parent.paletteCircleMask then
        parent.paletteCircleMask = parent:CreateMaskTexture()
        parent.paletteCircleMask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    end
    parent.paletteCircleMask:ClearAllPoints()
    parent.paletteCircleMask:SetAllPoints(tex)
    if not parent.__paletteMaskOn then
        tex:AddMaskTexture(parent.paletteCircleMask)
        parent.__paletteMaskOn = true
    end
end

local function ApplyRectTileIcon(tex, parent, tileSize)
    local pad = 3
    local w = math.max(10, tileSize - pad * 2)
    local h = math.max(8, math.floor(w * 0.72 + 0.5))
    tex:ClearAllPoints()
    tex:SetSize(w, h)
    tex:SetPoint("CENTER", parent, "CENTER", 0, 0)
    tex:SetTexture(WHITE_TEX)
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetVertexColor(0.30, 0.55, 0.95, 0.95)
    tex:SetAlpha(1)
    tex:Show()
end

local function ApplyTextTileIcon(btn, tileSize)
    if btn.icon then btn.icon:Hide() end
    if not btn.letter then
        btn.letter = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        btn.letter:SetPoint("CENTER", btn, "CENTER", 0, 0)
    end
    local fontPx = math.max(16, math.min(26, math.floor(tileSize * 0.52 + 0.5)))
    btn.letter:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", fontPx, "OUTLINE")
    btn.letter:SetText("A")
    btn.letter:SetTextColor(0.92, 0.92, 0.92)
    btn.letter:Show()
end

local function ApplyPaletteTilePreview(btn, previewKind, tileSize)
    tileSize = tileSize or btn:GetWidth() or PALETTE_TILE
    if previewKind == "text" then
        ApplyTextTileIcon(btn, tileSize)
    elseif previewKind == "circle" then
        if btn.letter then btn.letter:Hide() end
        btn.icon:Show()
        ApplyCircleTileIcon(btn.icon, btn, tileSize)
    elseif previewKind == "rect" then
        if btn.letter then btn.letter:Hide() end
        btn.icon:Show()
        ApplyRectTileIcon(btn.icon, btn, tileSize)
    end
end

local function CopyTemplate(t)
    local out = {}
    for k, v in pairs(t) do
        if type(k) ~= "string" or k:sub(1, 2) ~= "__" then
            out[k] = v
        end
    end
    return out
end

local function RandomSuffix()
    local chars = "abcdefghijklmnopqrstuvwxyz0123456789"
    local s = ""
    for _ = 1, 9 do
        local r = math.random(1, #chars)
        s = s .. chars:sub(r, r)
    end
    return s
end

function Diar:GeneratePlannerItemId()
    -- Avoid time()*1000 — WoW Lua integers overflow (~2.1B); time() alone is enough with a random suffix.
    return string.format("obj-%s-%s", tostring(time() or 0), RandomSuffix())
end

function Diar:GetObjectPaletteExtraWidth()
    if not self.IsObjectPaletteEnabled or not self:IsObjectPaletteEnabled() then
        return 0
    end
    return self.OBJECT_PALETTE_PANEL_W + self.OBJECT_PALETTE_GAP
end

function Diar:GetPlannerContentLeft()
    return self.OBJECT_PALETTE_UI_PAD + self:GetObjectPaletteExtraWidth()
end

local function GetCanvasLocalPoint(canvas, pf)
    if not canvas then return nil end
    local scale = (pf and pf.GetEffectiveScale and pf:GetEffectiveScale()) or 1
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    local left, top = canvas:GetLeft(), canvas:GetTop()
    if not left or not top then return nil end
    local cw, ch = canvas:GetSize()
    if not cw or cw <= 0 then cw = 1 end
    if not ch or ch <= 0 then ch = 1 end
    local lx, ly = cx - left, top - cy
    if lx < 0 or ly < 0 or lx > cw or ly > ch then return nil end
    return lx, ly, cw, ch
end

local function GetCanvasLocalPointClamped(canvas, pf)
    if not canvas then return nil end
    local scale = (pf and pf.GetEffectiveScale and pf:GetEffectiveScale()) or 1
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    local left, top = canvas:GetLeft(), canvas:GetTop()
    if not left or not top then return nil end
    local cw, ch = canvas:GetSize()
    if not cw or cw <= 0 then cw = 1 end
    if not ch or ch <= 0 then ch = 1 end
    local lx = cx - left
    local ly = top - cy
    return lx, ly, cw, ch
end

local function CanvasLocalToItemPercent(pf, lx, ly, cw, ch)
    local vc = pf and pf.sceneViewContext
    local PV = Diar.PlannerView
    if PV and PV.ScreenToWorld and vc then
        local wx, wy = PV.ScreenToWorld(vc, lx, ly)
        return (wx / cw) * 100, (wy / ch) * 100
    end
    return (lx / cw) * 100, (ly / ch) * 100
end

local MIN_SHAPE_DRAG_PX = 6
local MIN_SHAPE_SIZE_PCT = 0.8

local function DefaultPreviewFill(template)
    local shape = template and tostring(template.shape or ""):lower() or ""
    if shape == "rect" or shape == "rectangle" or shape == "square" then
        return { 0.30, 0.55, 0.95, 0.35 }
    end
    return { 0.92, 0.30, 0.30, 0.35 }
end

local function IsBoxShape(shape)
    shape = tostring(shape or ""):lower()
    return shape == "rect" or shape == "rectangle" or shape == "square"
end

local function ParseTemplateFillColor(fill, fallback)
    fallback = fallback or { 0.5, 0.5, 0.5, 0.35 }
    if type(fill) ~= "string" or fill == "" then
        return fallback[1], fallback[2], fallback[3], fallback[4] or 1
    end
    local s = fill:lower():gsub("%s+", "")
    if s:sub(1, 1) == "#" then
        local hex = s:sub(2)
        if #hex == 3 then
            hex = hex:sub(1, 1):rep(2) .. hex:sub(2, 2):rep(2) .. hex:sub(3, 3):rep(2)
        end
        if #hex >= 6 then
            return (tonumber(hex:sub(1, 2), 16) or 255) / 255,
                (tonumber(hex:sub(3, 4), 16) or 255) / 255,
                (tonumber(hex:sub(5, 6), 16) or 255) / 255,
                (#hex >= 8 and (tonumber(hex:sub(7, 8), 16) or 255) / 255) or 1
        end
    end
    local r, g, b, a = s:match("^rgba?%((%d+),(%d+),(%d+),?([%d%.]*)%)$")
    if r and g and b then
        return (tonumber(r) or 0) / 255, (tonumber(g) or 0) / 255, (tonumber(b) or 0) / 255,
            (a and a ~= "" and tonumber(a)) or 1
    end
    return fallback[1], fallback[2], fallback[3], fallback[4] or 1
end

local function DragBoxToItemSize(pf, x1, y1, x2, y2, cw, ch, shape)
    shape = tostring(shape or ""):lower()
    local leftPx = math.min(x1, x2)
    local topPx = math.min(y1, y2)
    local wPx = math.abs(x2 - x1)
    local hPx = math.abs(y2 - y1)
    if shape == "circle" then
        local sizePx = math.max(wPx, hPx)
        local cx = (x1 + x2) * 0.5
        local cy = (y1 + y2) * 0.5
        leftPx = cx - sizePx * 0.5
        topPx = cy - sizePx * 0.5
        wPx = sizePx
        hPx = sizePx
    end
    local rightPx = leftPx + wPx
    local bottomPx = topPx + hPx
    local xPctA, yPctA = CanvasLocalToItemPercent(pf, leftPx, topPx, cw, ch)
    local xPctB, yPctB = CanvasLocalToItemPercent(pf, rightPx, bottomPx, cw, ch)
    local left = math.min(xPctA, xPctB)
    local top = math.min(yPctA, yPctB)
    local wPct = math.abs(xPctB - xPctA)
    local hPct = math.abs(yPctB - yPctA)
    wPct = math.max(MIN_SHAPE_SIZE_PCT, wPct)
    hPct = math.max(MIN_SHAPE_SIZE_PCT, hPct)
    return left, top, wPct, hPct
end

local function DefaultShapeAtPoint(template, px, py)
    local wPct = tonumber(template.w) or 4
    local hPct = tonumber(template.h) or 4
    local shape = tostring(template.shape or ""):lower()
    if shape == "circle" then
        wPct, hPct = Diar:SquareIconPercents(wPct)
    end
    local xPct = px - wPct * 0.5
    local yPct = py - hPct * 0.5
    return xPct, yPct, wPct, hPct
end

local function NormalizeCircleItemSize(item, wPct, hPct)
    if not item or tostring(item.shape or ""):lower() ~= "circle" then
        return wPct, hPct
    end
    return Diar:SquareIconPercents(wPct or item.w or 4)
end

function Diar:EnsurePaletteDragTicker(pf)
    if not pf.__paletteDragTicker then
        pf.__paletteDragTicker = CreateFrame("Frame", nil, pf)
    end
    return pf.__paletteDragTicker
end

function Diar:StartPaletteDragTracking(pf)
    pf.__paletteDragCanFinish = false
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if pf.__paletteDrag then pf.__paletteDragCanFinish = true end
        end)
    else
        pf.__paletteDragCanFinish = true
    end
    local ticker = self:EnsurePaletteDragTicker(pf)
    ticker:SetScript("OnUpdate", function()
        Diar:UpdatePaletteDragDraw()
        if pf.__paletteDragCanFinish and not IsMouseButtonDown("LeftButton") then
            Diar:FinishPaletteDragDraw()
        end
    end)
end

function Diar:StopPaletteDragTracking(pf)
    if not pf then return end
    if pf.__paletteDragTicker then
        pf.__paletteDragTicker:SetScript("OnUpdate", nil)
    end
    if pf.canvas then
        pf.canvas:SetScript("OnUpdate", nil)
    end
end

function Diar:EnsurePaletteGhostPreview(pf)
    local canvas = pf and pf.canvas
    if not canvas then return nil end
    if pf.__paletteGhostPreview and pf.__paletteGhostPreview:GetParent() == canvas then
        return pf.__paletteGhostPreview
    end
    local f = CreateFrame("Frame", nil, canvas)
    f:SetFrameLevel((canvas:GetFrameLevel() or 0) + 450)
    f:EnableMouse(false)
    f.tex = f:CreateTexture(nil, "OVERLAY")
    f.tex:SetAllPoints(f)
    f:Hide()
    pf.__paletteGhostPreview = f
    return f
end

function Diar:HidePaletteGhostPreview(pf)
    pf = pf or self.plannerFrame
    if not pf then return end
    if pf.__paletteGhostPreview then
        pf.__paletteGhostPreview:Hide()
        pf.__paletteGhostPreview.__ghostIconKey = nil
    end
end

function Diar:UpdatePaletteGhostPreview()
    local pf = self.plannerFrame
    local canvas = pf and pf.canvas
    local placement = pf and pf.__palettePlacement
    if not pf or not canvas or not placement then
        self:HidePaletteGhostPreview(pf)
        return
    end
    if placement.__dragDraw or placement.kind ~= "icon" then
        self:HidePaletteGhostPreview(pf)
        return
    end

    local lx, ly, cw, ch = GetCanvasLocalPoint(canvas, pf)
    if not lx then
        self:HidePaletteGhostPreview(pf)
        return
    end

    local ghost = self:EnsurePaletteGhostPreview(pf)
    if not ghost or not ghost.tex then return end
    local wpct, hpct = self:SquareIconPercents(placement.w or self.OBJECT_PALETTE_ICON_W_PCT)
    local iw = math.max(10, cw * (wpct / 100))
    local ih = math.max(10, ch * (hpct / 100))
    local px = math.max(0, math.min(cw, lx + PALETTE_ICON_CURSOR_OFFSET_X))
    local py = math.max(0, math.min(ch, ly + PALETTE_ICON_CURSOR_OFFSET_Y))
    ghost:ClearAllPoints()
    ghost:SetPoint("TOPLEFT", canvas, "TOPLEFT", px, -py)
    ghost:SetSize(iw, ih)

    local iconKey = placement.icon
    if ghost.__ghostIconKey ~= iconKey then
        ghost.__ghostIconKey = iconKey
        if not ApplyIngameIconTexture(ghost.tex, iconKey) then
            ghost.tex:SetColorTexture(0.35, 0.50, 0.70, 0.90)
            ghost.tex:SetTexCoord(0, 1, 0, 1)
        end
    end
    ghost:SetAlpha(0.55)
    ghost:Show()
end

function Diar:StartPaletteGhostTracking(pf)
    pf = pf or self.plannerFrame
    if not pf then return end
    if not pf.__paletteGhostTicker then
        pf.__paletteGhostTicker = CreateFrame("Frame", nil, pf)
    end
    pf.__paletteGhostTicker:SetScript("OnUpdate", function()
        Diar:UpdatePaletteGhostPreview()
    end)
end

function Diar:StopPaletteGhostTracking(pf)
    pf = pf or self.plannerFrame
    if not pf then return end
    if pf.__paletteGhostTicker then
        pf.__paletteGhostTicker:SetScript("OnUpdate", nil)
    end
    self:HidePaletteGhostPreview(pf)
end

function Diar:EnsurePaletteDragLayer(pf)
    if pf.__paletteDragLayer then return pf.__paletteDragLayer end
    local canvas = pf.canvas
    if not canvas then return nil end
    local layer = CreateFrame("Frame", nil, pf)
    layer:EnableMouse(true)
    layer:SetScript("OnMouseUp", function(_, button)
        if Diar.TryPaletteCanvasMouseUp then
            Diar:TryPaletteCanvasMouseUp(button)
        end
    end)
    pf.__paletteDragLayer = layer
    return layer
end

function Diar:ShowPaletteDragLayer(pf)
    local canvas = pf.canvas
    local layer = self:EnsurePaletteDragLayer(pf)
    if not layer or not canvas then return end
    layer:ClearAllPoints()
    layer:SetAllPoints(canvas)
    layer:SetFrameLevel(canvas:GetFrameLevel() + 500)
    layer:Show()
end

function Diar:HidePaletteDragLayer(pf)
    if pf and pf.__paletteDragLayer then
        pf.__paletteDragLayer:Hide()
    end
end

function Diar:CancelPaletteDragDraw()
    local pf = self.plannerFrame
    if not pf then return end
    pf.__paletteDrag = nil
    pf.__paletteDragCanFinish = nil
    if pf.__paletteDragPreview then pf.__paletteDragPreview:Hide() end
    self:HidePaletteDragLayer(pf)
    self:StopPaletteDragTracking(pf)
end

function Diar:EnsurePaletteDragPreview(pf)
    local layer = self:EnsurePaletteDragLayer(pf)
    if not layer then return nil end
    local existing = pf.__paletteDragPreview
    if existing and (existing:GetParent() ~= layer or existing.previewStroke or existing.borderTex) then
        existing:Hide()
        pf.__paletteDragPreview = nil
    end
    if pf.__paletteDragPreview then return pf.__paletteDragPreview end
    local f = CreateFrame("Frame", nil, layer, "BackdropTemplate")
    f:SetFrameLevel(layer:GetFrameLevel() + 2)
    f:EnableMouse(false)
    f.previewTex = f:CreateTexture(nil, "ARTWORK")
    f.previewTex:SetAllPoints(f)
    f.previewTex:SetTexture(WHITE_TEX)
    f.previewMask = f:CreateMaskTexture()
    f.previewMask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    f:Hide()
    pf.__paletteDragPreview = f
    return f
end

function Diar:UpdatePaletteDragPreview(pf, drag)
    local canvas = pf.canvas
    local preview = self:EnsurePaletteDragPreview(pf)
    if not preview or not drag or not canvas then return end
    self:ShowPaletteDragLayer(pf)
    local template = drag.template
    local shape = template and tostring(template.shape or ""):lower() or ""
    local x2 = drag.curX or drag.startX
    local y2 = drag.curY or drag.startY
    local left = math.min(drag.startX, x2)
    local top = math.min(drag.startY, y2)
    local w = math.max(2, math.abs(x2 - drag.startX))
    local h = math.max(2, math.abs(y2 - drag.startY))
    if shape == "circle" then
        local size = math.max(w, h)
        local cx = (drag.startX + x2) * 0.5
        local cy = (drag.startY + y2) * 0.5
        left = cx - size * 0.5
        top = cy - size * 0.5
        w, h = size, size
    end
    preview:ClearAllPoints()
    preview:SetPoint("TOPLEFT", canvas, "TOPLEFT", left, -top)
    preview:SetSize(w, h)
    local fr, fg, fb, fa = ParseTemplateFillColor(template and template.fill, DefaultPreviewFill(template))
    if shape == "circle" then
        preview.previewTex:Show()
        preview.previewTex:SetAllPoints(preview)
        preview.previewTex:SetVertexColor(fr, fg, fb, 1)
        preview.previewTex:SetAlpha(math.max(0.25, fa or 0.35))
        preview.previewMask:ClearAllPoints()
        preview.previewMask:SetAllPoints(preview.previewTex)
        if not preview.__maskOn then
            preview.previewTex:AddMaskTexture(preview.previewMask)
            preview.__maskOn = true
        end
        if preview.borderTex then preview.borderTex:Hide() end
        if preview.SetBackdrop then preview:SetBackdrop(nil) end
    else
        if preview.__maskOn then
            preview.previewTex:RemoveMaskTexture(preview.previewMask)
            preview.__maskOn = false
        end
        if preview.borderTex then preview.borderTex:Hide() end
        preview.previewTex:Hide()
        if preview.SetBackdrop then
            preview:SetBackdrop({
                bgFile = WHITE_TEX,
                edgeFile = WHITE_TEX,
                tile = false,
                edgeSize = 1,
            })
            preview:SetBackdropColor(fr, fg, fb, math.max(0.25, fa or 0.35))
            preview:SetBackdropBorderColor(1, 1, 1, 0.95)
        else
            preview.previewTex:Show()
            preview.previewTex:SetAllPoints(preview)
            preview.previewTex:SetVertexColor(fr, fg, fb, 1)
            preview.previewTex:SetAlpha(math.max(0.25, fa or 0.35))
        end
    end
    preview:Show()
end

function Diar:UpdatePaletteDragDraw()
    local pf = self.plannerFrame
    local drag = pf and pf.__paletteDrag
    if not drag or not pf.canvas then return end
    local lx, ly, cw, ch = GetCanvasLocalPointClamped(pf.canvas, pf)
    if not lx then return end
    drag.curX, drag.curY = lx, ly
    drag.cw, drag.ch = cw, ch
    self:UpdatePaletteDragPreview(pf, drag)
end

function Diar:FinishPaletteDragDraw()
    local pf = self.plannerFrame
    local drag = pf and pf.__paletteDrag
    if not drag then return end
    local template = drag.template
    local cw, ch = drag.cw or 1, drag.ch or 1
    local dx = math.abs((drag.curX or drag.startX) - drag.startX)
    local dy = math.abs((drag.curY or drag.startY) - drag.startY)
    local xPct, yPct, wPct, hPct
    if dx < MIN_SHAPE_DRAG_PX and dy < MIN_SHAPE_DRAG_PX then
        local px, py = CanvasLocalToItemPercent(pf, drag.startX, drag.startY, cw, ch)
        xPct, yPct, wPct, hPct = DefaultShapeAtPoint(template, px, py)
    else
        xPct, yPct, wPct, hPct = DragBoxToItemSize(
            pf, drag.startX, drag.startY, drag.curX or drag.startX, drag.curY or drag.startY, cw, ch, template.shape
        )
    end
    self:CancelPaletteDragDraw()
    self:ClearPalettePlacement()
    self:AddPlannerItemToScene(template, xPct, yPct, { wPct = wPct, hPct = hPct })
end

function Diar:AddPlannerItemToScene(template, xPct, yPct, opts)
    opts = opts or {}
    if self.IsPlannerCanvasLocked and self:IsPlannerCanvasLocked() then return false end
    local pf = self.plannerFrame
    local data = self.plannerData
    if not pf or not data or not data.scenes or not template then return false end
    local idx = pf.selectedSceneIndex or 1
    local scene = data.scenes[idx]
    if not scene then return false end
    scene.items = scene.items or {}

    local item = CopyTemplate(template)
    item.id = self:GeneratePlannerItemId()
    item.x = xPct
    item.y = yPct
    if opts.wPct then item.w = opts.wPct end
    if opts.hPct then item.h = opts.hPct end
    if item.kind == "shape" and tostring(item.shape or ""):lower() == "circle" then
        item.w, item.h = NormalizeCircleItemSize(item, item.w, item.h)
    end
    if item.kind == "icon" then
        local wPct, hPct = self:SquareIconPercents(item.w or self.OBJECT_PALETTE_ICON_W_PCT)
        item.w = wPct
        item.h = hPct
    end

    if not IsWorldMarkerPaletteItem(item) then
        local slotIndex = PUI.GetNextAvailableSlotIndex(scene)
        item.slotIndex = slotIndex
        item.embedIndex = slotIndex
    else
        item.slotIndex = nil
        item.embedIndex = nil
    end

    table.insert(scene.items, item)
    if self.PersistCurrentPlanToSaved then
        self:PersistCurrentPlanToSaved()
    end
    if self.RefreshPlannerScene then
        self:RefreshPlannerScene()
    end
    return true
end

function Diar:IsPlannerPaletteActive()
    local pf = self.plannerFrame
    if not pf or pf.compactMode or pf.nsrtSceneActive then return false end
    if not HasLoadedPlan(self.plannerData) then return false end
    if not self.IsObjectPaletteEnabled or not self:IsObjectPaletteEnabled() then return false end
    return true
end

function Diar:ClearPalettePlacement()
    local pf = self.plannerFrame
    if not pf then return end
    if self.HidePaletteSpecPicker then
        self:HidePaletteSpecPicker()
    end
    self:StopPaletteGhostTracking(pf)
    self:CancelPaletteDragDraw()
    pf.__palettePlacement = nil
    if pf.objectPaletteHint then
        pf.objectPaletteHint:SetText(PALETTE_HINT_DEFAULT)
        pf.objectPaletteHint:SetTextColor(0.45, 0.50, 0.58)
    end
end

function Diar:PromptPaletteTextLabel(template, label)
    if not self:IsPlannerPaletteActive() then return end
    if self.IsPlannerCanvasLocked and self:IsPlannerCanvasLocked() then return end
    StaticPopup_Show("RAIDSTRATSGG_PALETTE_TEXT", nil, nil, {
        template = template,
        defaultText = (template and template.label) or "Label",
    })
end

function Diar:BeginPalettePlacement(template, label, opts)
    if not self:IsPlannerPaletteActive() then return end
    if self.IsPlannerCanvasLocked and self:IsPlannerCanvasLocked() then return end
    local pf = self.plannerFrame
    if not pf then return end
    if self.HidePaletteSpecPicker then
        self:HidePaletteSpecPicker()
    end
    self:StopPaletteGhostTracking(pf)
    self:CancelPaletteDragDraw()
    pf.__palettePlacement = CopyTemplate(template)
    pf.__palettePlacement.__dragDraw = opts and opts.dragDraw or nil
    if pf.__palettePlacement.kind == "icon" and not pf.__palettePlacement.__dragDraw then
        self:StartPaletteGhostTracking(pf)
        self:UpdatePaletteGhostPreview()
    end
    if pf.objectPaletteHint then
        if pf.__palettePlacement.__dragDraw then
            pf.objectPaletteHint:SetText(("Drag on canvas to draw %s (right-click cancel)"):format(label or "shape"))
        else
            pf.objectPaletteHint:SetText(("Click canvas to place %s (right-click cancel)"):format(label or "object"))
        end
        pf.objectPaletteHint:SetTextColor(0.55, 0.78, 1, 1)
    end
end

function Diar:TryPaletteCanvasMouseDown(button)
    local pf = self.plannerFrame
    if not pf or not pf.__palettePlacement then return false end
    if self.IsPlannerCanvasLocked and self:IsPlannerCanvasLocked() then return false end
    if not self:IsPlannerPaletteActive() then
        self:ClearPalettePlacement()
        return false
    end

    if button == "RightButton" then
        self:ClearPalettePlacement()
        return true
    end
    if button ~= "LeftButton" then return false end

    local template = pf.__palettePlacement
    if template.__dragDraw then
        local canvas = pf.canvas
        local lx, ly, cw, ch = GetCanvasLocalPointClamped(canvas, pf)
        if not lx then return false end
        self:ShowPaletteDragLayer(pf)
        pf.__paletteDrag = {
            template = CopyTemplate(template),
            startX = lx,
            startY = ly,
            curX = lx,
            curY = ly,
            cw = cw,
            ch = ch,
        }
        self:UpdatePaletteDragPreview(pf, pf.__paletteDrag)
        self:StartPaletteDragTracking(pf)
        return true
    end

    local lx, ly, cw, ch = GetCanvasLocalPoint(pf.canvas, pf)
    if not lx then return false end
    if template.kind == "icon" then
        lx = lx + PALETTE_ICON_CURSOR_OFFSET_X
        ly = ly + PALETTE_ICON_CURSOR_OFFSET_Y
    end
    local xPct, yPct = CanvasLocalToItemPercent(pf, lx, ly, cw, ch)
    local placement = CopyTemplate(template)
    self:ClearPalettePlacement()
    self:AddPlannerItemToScene(placement, xPct, yPct)
    return true
end

function Diar:TryPaletteCanvasMouseUp(button)
    if button ~= "LeftButton" then return false end
    local pf = self.plannerFrame
    if not pf or not pf.__paletteDrag then return false end
    self:FinishPaletteDragDraw()
    return true
end

function Diar:TryPalettePlaceAtCursor(button)
    return self:TryPaletteCanvasMouseDown(button)
end

local function CreatePaletteTile(parent, size, tooltip, previewKind)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(size, size)
    b.previewKind = previewKind
    if SetBackdrop then SetBackdrop(b, UI.ROW, UI.BORDER, 1) end
    b.icon = b:CreateTexture(nil, "ARTWORK")
    if previewKind then
        ApplyPaletteTilePreview(b, previewKind, size)
    else
        SetSquareTileIcon(b.icon, b, size)
    end
    b:SetScript("OnEnter", function(s)
        s:SetBackdropColor(unpack(UI.ROW_HOV))
        if tooltip and GameTooltip then
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(s)
        s:SetBackdropColor(unpack(UI.ROW))
        if GameTooltip then GameTooltip:Hide() end
    end)
    return b
end

local function WirePaletteTile(btn, template, label, opts)
    opts = opts or {}
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(_, button)
        if Diar.IsPlannerCanvasLocked and Diar:IsPlannerCanvasLocked() then return end
        if button == "RightButton" then
            if opts.onRightClick then
                opts.onRightClick(btn, template, label)
            end
            return
        end
        if opts.promptText then
            Diar:PromptPaletteTextLabel(template, label)
        else
            Diar:BeginPalettePlacement(template, label, opts)
        end
    end)
end

local PALETTE_SHAPES = {
    {
        label = "Circle",
        tooltip = "Circle shape",
        previewKind = "circle",
        template = {
            kind = "shape", shape = "circle", w = 4, h = 4,
            fill = "rgba(255, 0, 0, 0.2)", stroke = "#ffffff", strokeWidth = 0.32,
        },
    },
    {
        label = "Rectangle",
        tooltip = "Rectangle shape",
        previewKind = "rect",
        template = {
            kind = "shape", shape = "rect", w = 5, h = 3.5,
            fill = "rgba(0, 120, 255, 0.25)", stroke = "#ffffff", strokeWidth = 0.32,
        },
    },
    {
        label = "Text",
        tooltip = "Text label",
        previewKind = "text",
        template = {
            kind = "text", label = "Label", w = 10, h = 3, fontSize = 4,
            textColor = "#ffffff", stroke = "#000000", strokeWidth = 0.2,
        },
    },
}

local function SectionRowCount(section)
    local maxRow = -1
    for _, tile in ipairs(section.tiles or {}) do
        if tile.row > maxRow then maxRow = tile.row end
    end
    return math.max(1, maxRow + 1)
end

local function ComputePaletteTileSize(contentHeight, contentWidth, refs)
    contentHeight = contentHeight or 280
    if contentHeight <= 0 then contentHeight = 280 end

    local totalRows = 0
    local sections = refs and #refs or 3
    if refs then
        for _, section in ipairs(refs) do
            totalRows = totalRows + SectionRowCount(section)
        end
    end
    if totalRows <= 0 then totalRows = 8 end

    local overhead = sections * PALETTE_HEADER_H + (sections + 1) * PALETTE_SECTION_GAP
    local avail = math.max(80, contentHeight - overhead)
    local tileFromHeight = math.floor((avail - totalRows * PALETTE_TILE_GAP) / totalRows + 0.5)

    local cw = contentWidth or 0
    if cw <= 0 then
        cw = (Diar.OBJECT_PALETTE_PANEL_W or 108) - 16
    end
    local tileFromWidth = math.floor(
        (cw - PALETTE_CONTENT_PAD_X * 2 - (PALETTE_COLS - 1) * PALETTE_TILE_GAP) / PALETTE_COLS + 0.5
    )

    local tile = math.min(tileFromHeight, tileFromWidth)
    return math.min(PALETTE_TILE_MAX, math.max(20, tile))
end

local function PaletteGridOrigin(contentWidth, tileSize)
    local cw = contentWidth or 0
    if cw <= 0 then
        cw = (Diar.OBJECT_PALETTE_PANEL_W or 108) - 16
    end
    local gridW = PALETTE_COLS * tileSize + (PALETTE_COLS - 1) * PALETTE_TILE_GAP
    return math.max(PALETTE_CONTENT_PAD_X, math.floor((cw - gridW) / 2 + 0.5))
end

local PALETTE_MARKER_ICON_SCALE = 0.62
local RAID_MARKER_ATLAS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local RAID_MARKER_ATLAS_COORDS = {
    [1] = { 0.00, 0.25, 0.00, 0.25 }, -- star
    [2] = { 0.25, 0.50, 0.00, 0.25 }, -- circle
    [3] = { 0.50, 0.75, 0.00, 0.25 }, -- diamond
    [4] = { 0.75, 1.00, 0.00, 0.25 }, -- triangle
    [5] = { 0.00, 0.25, 0.25, 0.50 }, -- moon
    [6] = { 0.25, 0.50, 0.25, 0.50 }, -- square
    [7] = { 0.50, 0.75, 0.25, 0.50 }, -- cross
    [8] = { 0.75, 1.00, 0.25, 0.50 }, -- skull
}

local function RefreshMarkerTile(btn, tile, tileSize)
    if btn.letter then btn.letter:Hide() end
    if not btn.icon then return end
    SetSquareTileIcon(btn.icon, btn, tileSize, PALETTE_MARKER_ICON_SCALE)
    btn.icon:Show()
    btn.icon:SetAlpha(1)
    local coords = tile and RAID_MARKER_ATLAS_COORDS[tile.raidIdx or 0]
    if coords then
        btn.icon:SetTexture(RAID_MARKER_ATLAS)
        btn.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        btn.icon:SetVertexColor(1, 1, 1, 1)
    elseif not ApplyIngameIconTexture(btn.icon, tile.markerKey) then
        btn.icon:SetTexture(RAID_TEX .. (tile.raidIdx or 1))
        btn.icon:SetTexCoord(0, 1, 0, 1)
        btn.icon:SetVertexColor(1, 1, 1, 1)
    end
end

local function RefreshRoleTile(btn, tile, tileSize)
    if btn.letter then btn.letter:Hide() end
    if not btn.icon then return end
    SetSquareTileIcon(btn.icon, btn, tileSize)
    btn.icon:Show()
    btn.icon:SetAlpha(1)
    if not SetTextureFromCandidates(btn.icon, RoleIconCandidates(tile.roleKey)) then
        btn.icon:SetColorTexture(0.35, 0.5, 0.7, 0.9)
        btn.icon:SetTexCoord(0, 1, 0, 1)
    end
end

local function RefreshClassTile(btn, tile, tileSize)
    if btn.letter then btn.letter:Hide() end
    if not btn.icon then return end
    SetSquareTileIcon(btn.icon, btn, tileSize)
    btn.icon:Show()
    btn.icon:SetAlpha(1)
    local iconKey = tile and tile.classKey and ("classes/" .. tile.classKey) or nil
    if iconKey and ApplyIngameIconTexture(btn.icon, iconKey) then
        return
    end
    btn.icon:SetColorTexture(0.70, 0.70, 0.78, 0.95)
    btn.icon:SetTexCoord(0, 1, 0, 1)
end

local function HumanizeSpecKey(specKey)
    if type(specKey) ~= "string" or specKey == "" then return "Spec" end
    local key = specKey:lower():gsub("%s+", ""):gsub("%-", "")
    if SPEC_LABEL_BY_KEY[key] then return SPEC_LABEL_BY_KEY[key] end
    return key:gsub("^%l", string.upper)
end

local function GetSpecDisplayInfo(classKey, specKey, specId)
    local label = HumanizeSpecKey(specKey)
    local texture = Diar.GetSpecTextureSafe and Diar.GetSpecTextureSafe(specId) or nil
    if C_SpecializationInfo and type(C_SpecializationInfo.GetSpecializationInfoForSpecID) == "function" then
        local _, specName, _, specIcon = C_SpecializationInfo.GetSpecializationInfoForSpecID(specId)
        if type(specName) == "string" and specName ~= "" then
            label = specName
        end
        if specIcon then texture = specIcon end
    elseif type(GetSpecializationInfoByID) == "function" then
        local _, specName, _, specIcon = GetSpecializationInfoByID(specId)
        if type(specName) == "string" and specName ~= "" then
            label = specName
        end
        if specIcon then texture = specIcon end
    end
    if not texture and Diar.ResolveSpecTextureFromIconKey then
        texture = Diar.ResolveSpecTextureFromIconKey(("specs/%s/%s"):format(classKey, specKey))
    end
    return label, texture
end

local function BuildClassSpecEntries(classKey)
    local out = {}
    local map = Diar.SPEC_ID_BY_CLASS and Diar.SPEC_ID_BY_CLASS[classKey]
    if type(map) ~= "table" then return out end
    local seenBySpecId = {}
    for specKey, specId in pairs(map) do
        if type(specKey) == "string" and type(specId) == "number" then
            -- Skip alternate key forms; include one canonical entry per spec ID.
            local canonical = specKey:gsub("%s+", "")
            if not canonical:find("%-") and not seenBySpecId[specId] then
                seenBySpecId[specId] = true
                local name, iconTexture = GetSpecDisplayInfo(classKey, specKey, specId)
                out[#out + 1] = {
                    key = canonical,
                    specId = specId,
                    label = name,
                    iconTexture = iconTexture,
                }
            end
        end
    end
    table.sort(out, function(a, b)
        return tostring(a.label or a.key) < tostring(b.label or b.key)
    end)
    return out
end

function Diar:HidePaletteSpecPicker()
    local pf = self.plannerFrame
    local menu = pf and pf._paletteSpecMenu
    if menu then
        menu:Hide()
    end
    if self.HidePaletteSpecDismissOverlay then
        self:HidePaletteSpecDismissOverlay()
    end
end

function Diar:HidePaletteSpecDismissOverlay()
    local o = self._paletteSpecDismissOverlay
    if not o then return end
    o:Hide()
    o:SetScript("OnClick", nil)
    o:SetScript("OnMouseUp", nil)
end

function Diar:ShowPaletteSpecDismissOverlay(menu)
    if not menu then return end
    if not self._paletteSpecDismissOverlay then
        local o = CreateFrame("Button", "RaidstratsPaletteSpecDismiss", UIParent)
        o:SetAllPoints(UIParent)
        o:SetFrameStrata("FULLSCREEN_DIALOG")
        o:EnableMouse(true)
        o:SetAlpha(0.001)
        self._paletteSpecDismissOverlay = o
    end
    local o = self._paletteSpecDismissOverlay
    o:SetScript("OnClick", nil)
    o:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" or button == "RightButton" then
            if Diar.HidePlannerTransientMenus then
                Diar:HidePlannerTransientMenus()
            else
                Diar:HidePaletteSpecPicker()
            end
        end
    end)
    o:SetFrameLevel(math.max(0, (menu:GetFrameLevel() or 0) - 1))
    o:Show()
end

function Diar:ShowPaletteSpecPicker(anchorBtn, classEntry)
    local pf = self.plannerFrame
    if not pf or not classEntry or not classEntry.key then return end
    if self.IsPlannerCanvasLocked and self:IsPlannerCanvasLocked() then return end

    local specs = BuildClassSpecEntries(classEntry.key)
    if #specs == 0 then
        print("|cffff6666[Raidstrats.gg]|r No specs found for this class.")
        return
    end

    local menu = pf._paletteSpecMenu
    if not menu then
        menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(530)
        menu:EnableMouse(true)
        menu.buttons = {}
        menu.title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        menu.title:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, -8)
        menu.title:SetTextColor(unpack(UI.ACCENT))
        if SetBackdrop then SetBackdrop(menu, UI.PANEL, UI.BORDER, 1) end
        menu:SetScript("OnHide", function(m)
            if m and m.buttons then
                for i = 1, #m.buttons do
                    m.buttons[i]:Hide()
                end
            end
            if Diar.HidePaletteSpecDismissOverlay then
                Diar:HidePaletteSpecDismissOverlay()
            end
        end)
        pf._paletteSpecMenu = menu
    end

    local rowH = 24
    local menuW = 184
    local menuH = 14 + rowH * #specs + 18
    -- Force-refresh placement/content even if already open, so repeated right-click works reliably.
    menu:Hide()
    menu:SetSize(menuW, menuH)
    menu:ClearAllPoints()
    if anchorBtn then
        menu:SetPoint("TOPLEFT", anchorBtn, "TOPRIGHT", 6, 0)
    else
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    end
    menu.title:SetText(("Specs: %s"):format(classEntry.label or classEntry.key))

    for i = 1, #specs do
        local spec = specs[i]
        local row = menu.buttons[i]
        if not row then
            row = CreateFrame("Button", nil, menu, "BackdropTemplate")
            row:SetSize(menuW - 12, rowH - 2)
            if SetBackdrop then SetBackdrop(row, UI.ROW, UI.BORDER, 1) end
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(16, 16)
            row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.text:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            row.text:SetJustifyH("LEFT")
            row:SetScript("OnEnter", function(s) s:SetBackdropColor(unpack(UI.ROW_HOV)) end)
            row:SetScript("OnLeave", function(s) s:SetBackdropColor(unpack(UI.ROW)) end)
            menu.buttons[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", menu, "TOPLEFT", 6, -14 - ((i - 1) * rowH) - 14)
        row.spec = spec
        row.classEntry = classEntry
        row.icon:SetTexCoord(0, 1, 0, 1)
        if spec.iconTexture then
            row.icon:SetTexture(spec.iconTexture)
            row.icon:SetVertexColor(1, 1, 1, 1)
        else
            row.icon:SetTexture(WHITE_TEX)
            row.icon:SetVertexColor(0.45, 0.60, 0.92, 0.95)
        end
        row.text:SetText(spec.label or HumanizeSpecKey(spec.key))
        row:SetScript("OnClick", function(s)
            local cls = s.classEntry
            local sp = s.spec
            if not cls or not sp then return end
            Diar:HidePaletteSpecPicker()
            Diar:BeginPalettePlacement({
                kind = "icon",
                icon = ("specs/%s/%s"):format(cls.key, sp.key),
                w = Diar.OBJECT_PALETTE_ICON_W_PCT,
            }, ("%s %s"):format(sp.label or HumanizeSpecKey(sp.key), cls.label or cls.key))
        end)
        row:Show()
    end
    for i = #specs + 1, #menu.buttons do
        menu.buttons[i]:Hide()
    end
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(530)
    menu:Show()
    if menu.Raise then menu:Raise() end
    if self.ShowPaletteSpecDismissOverlay then
        self:ShowPaletteSpecDismissOverlay(menu)
    end
end

function Diar:RelayoutObjectPaletteTiles(pf)
    local content = pf and pf.objectPaletteContent
    local refs = pf and pf.objectPaletteTileRefs
    if not content or not refs or #refs == 0 then return end

    local contentH = content:GetHeight()
    if not contentH or contentH <= 0 then
        contentH = 280
    end
    local contentW = content:GetWidth()
    if not contentW or contentW <= 0 then
        contentW = (Diar.OBJECT_PALETTE_PANEL_W or 108) - 16
    end

    local tileSize = ComputePaletteTileSize(contentH, contentW, refs)
    local step = tileSize + PALETTE_TILE_GAP
    local x0 = PaletteGridOrigin(contentW, tileSize)
    local y = 0

    for _, section in ipairs(refs) do
        if section.header then
            section.header:ClearAllPoints()
            section.header:SetPoint("TOPLEFT", content, "TOPLEFT", x0, y)
            y = y - PALETTE_HEADER_H
        end
        y = y - PALETTE_SECTION_GAP
        for _, tile in ipairs(section.tiles) do
            local btn = tile.btn
            if btn then
                btn:Show()
                btn:SetSize(tileSize, tileSize)
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", content, "TOPLEFT", x0 + tile.col * step, y - tile.row * step)
                if btn.previewKind then
                    ApplyPaletteTilePreview(btn, btn.previewKind, tileSize)
                elseif tile.markerKey then
                    RefreshMarkerTile(btn, tile, tileSize)
                elseif tile.classKey then
                    RefreshClassTile(btn, tile, tileSize)
                elseif tile.roleKey then
                    RefreshRoleTile(btn, tile, tileSize)
                elseif btn.icon then
                    btn.icon:Show()
                    SetSquareTileIcon(btn.icon, btn, tileSize)
                end
            end
        end
        y = y - SectionRowCount(section) * step
    end
    if self.ApplyObjectPaletteLockedState then
        self:ApplyObjectPaletteLockedState(pf)
    end
end

function Diar:EnsureObjectPalettePanel(pf)
    if pf.objectPalettePanel and pf.objectPalettePanel.__paletteV6 then return end
    if pf.objectPalettePanel then
        pf.objectPalettePanel:Hide()
        pf.objectPalettePanel = nil
        pf.objectPaletteHint = nil
        pf.objectPaletteContent = nil
        pf.objectPaletteTileRefs = nil
    end

    local panel = CreateFrame("Frame", nil, pf, "BackdropTemplate")
    panel.__paletteV6 = true
    panel:SetWidth(self.OBJECT_PALETTE_PANEL_W)
    panel:EnableMouse(true)
    panel:SetFrameLevel((pf:GetFrameLevel() or 0) + 8)
    if SetBackdrop then SetBackdrop(panel, UI.PANEL, UI.BORDER, 1) end
    pf.objectPalettePanel = panel

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 8)
    hint:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, 8)
    hint:SetHeight(PALETTE_HINT_H)
    hint:SetJustifyH("LEFT")
    hint:SetJustifyV("BOTTOM")
    hint:SetWordWrap(true)
    hint:SetTextColor(0.45, 0.50, 0.58)
    hint:SetText(PALETTE_HINT_DEFAULT)
    pf.objectPaletteHint = hint

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
    title:SetText("Objects")
    title:SetTextColor(0.92, 0.92, 0.92)

    local child = CreateFrame("Frame", nil, panel)
    child:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -28)
    child:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, PALETTE_HINT_H + 10)
    if child.SetClipsChildren then child:SetClipsChildren(true) end
    pf.objectPaletteContent = child
    child:SetScript("OnSizeChanged", function()
        if Diar.RelayoutObjectPaletteTiles then
            Diar:RelayoutObjectPaletteTiles(pf)
        end
    end)

    pf.objectPaletteTileRefs = {}

    local function AddSection(titleText)
        local section = { header = nil, tiles = {} }
        local hdr = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hdr:SetText(titleText)
        hdr:SetTextColor(unpack(UI.ACCENT))
        section.header = hdr
        pf.objectPaletteTileRefs[#pf.objectPaletteTileRefs + 1] = section
        return section
    end

    local shapesSec = AddSection("SHAPES")
    local shapeCol, shapeRow = 0, 0
    for _, entry in ipairs(PALETTE_SHAPES) do
        local btn = CreatePaletteTile(child, PALETTE_TILE, entry.tooltip or entry.label, entry.previewKind)
        shapesSec.tiles[#shapesSec.tiles + 1] = { btn = btn, col = shapeCol, row = shapeRow }
        if entry.template.kind == "text" then
            WirePaletteTile(btn, entry.template, entry.label, { promptText = true })
        elseif entry.previewKind == "circle" or entry.previewKind == "rect" then
            WirePaletteTile(btn, entry.template, entry.label, { dragDraw = true })
        else
            WirePaletteTile(btn, entry.template, entry.label)
        end
        shapeCol = shapeCol + 1
        if shapeCol >= PALETTE_COLS then
            shapeCol = 0
            shapeRow = shapeRow + 1
        end
    end

    local markersSec = AddSection("MARKERS")
    local col, row = 0, 0
    for _, marker in ipairs(RAID_MARKERS) do
        local btn = CreatePaletteTile(child, PALETTE_TILE, marker.key:gsub("^%l", string.upper))
        markersSec.tiles[#markersSec.tiles + 1] = {
            btn = btn, col = col, row = row, markerKey = marker.key, raidIdx = marker.idx,
        }
        RefreshMarkerTile(btn, markersSec.tiles[#markersSec.tiles], PALETTE_TILE)
        WirePaletteTile(btn, {
            kind = "icon", icon = marker.key, w = Diar.OBJECT_PALETTE_ICON_W_PCT,
        }, marker.key)
        col = col + 1
        if col >= PALETTE_COLS then
            col = 0
            row = row + 1
        end
    end

    local rolesSec = AddSection("ROLES")
    col, row = 0, 0
    for _, role in ipairs(ROLE_ENTRIES) do
        local btn = CreatePaletteTile(child, PALETTE_TILE, role.label)
        local roleTile = { btn = btn, col = col, row = row, roleKey = role.key }
        rolesSec.tiles[#rolesSec.tiles + 1] = roleTile
        RefreshRoleTile(btn, roleTile, PALETTE_TILE)
        WirePaletteTile(btn, {
            kind = "icon", icon = "roles/" .. role.key, w = Diar.OBJECT_PALETTE_ICON_W_PCT,
        }, role.label)
        col = col + 1
        if col >= PALETTE_COLS then
            col = 0
            row = row + 1
        end
    end

    local classesSec = AddSection("CLASSES")
    col, row = 0, 0
    for _, classEntry in ipairs(CLASS_ENTRIES) do
        local classData = classEntry
        local btn = CreatePaletteTile(child, PALETTE_TILE, classEntry.label)
        local classTile = { btn = btn, col = col, row = row, classKey = classEntry.key }
        classesSec.tiles[#classesSec.tiles + 1] = classTile
        RefreshClassTile(btn, classTile, PALETTE_TILE)
        WirePaletteTile(btn, {
            kind = "icon", icon = "classes/" .. classEntry.key, w = Diar.OBJECT_PALETTE_ICON_W_PCT,
        }, classEntry.label, {
            onRightClick = function(anchorBtn)
                Diar:ShowPaletteSpecPicker(anchorBtn, classData)
            end,
        })
        col = col + 1
        if col >= PALETTE_COLS then
            col = 0
            row = row + 1
        end
    end

    self:RelayoutObjectPaletteTiles(pf)
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if pf.objectPalettePanel and pf.objectPalettePanel.__paletteV6 then
                Diar:RelayoutObjectPaletteTiles(pf)
            end
        end)
    end
end

function Diar:ApplyObjectPaletteLockedState(pf)
    pf = pf or self.plannerFrame
    local refs = pf and pf.objectPaletteTileRefs
    if not refs then return end
    local noPlan = not HasLoadedPlan(self.plannerData)
    local locked = noPlan or (self.IsPlannerCanvasLocked and self:IsPlannerCanvasLocked())
    for _, section in ipairs(refs) do
        if section.header then
            section.header:SetAlpha(locked and 0.42 or 1)
        end
        for _, tile in ipairs(section.tiles or {}) do
            local btn = tile.btn
            if not btn then
            elseif locked then
                btn:SetAlpha(0.35)
                btn:Disable()
                if btn.icon and btn.icon.SetDesaturated then
                    btn.icon:SetDesaturated(true)
                end
            else
                btn:SetAlpha(1)
                btn:Enable()
                if btn.icon and btn.icon.SetDesaturated then
                    btn.icon:SetDesaturated(false)
                end
            end
        end
    end
    if locked and self.HidePaletteSpecPicker then
        self:HidePaletteSpecPicker()
    end
    if pf.objectPaletteHint and not pf.__palettePlacement then
        if noPlan then
            pf.objectPaletteHint:SetText("Load a plan to use the palette")
            pf.objectPaletteHint:SetTextColor(0.40, 0.43, 0.48)
        elseif locked then
            pf.objectPaletteHint:SetText("Objects locked")
            pf.objectPaletteHint:SetTextColor(0.40, 0.43, 0.48)
        else
            pf.objectPaletteHint:SetText(PALETTE_HINT_DEFAULT)
            pf.objectPaletteHint:SetTextColor(0.45, 0.50, 0.58)
        end
    end
end

function Diar:ApplyObjectPaletteLayout(pf)
    if not pf then return end
    local hasPlan = HasLoadedPlan(self.plannerData)
    if not pf.compactMode and self:IsObjectPaletteEnabled() then
        self:EnsureObjectPalettePanel(pf)
    end
    local panel = pf.objectPalettePanel
    if not panel then return end

    if not self:IsObjectPaletteEnabled() or pf.compactMode then
        if self.HidePaletteSpecPicker then
            self:HidePaletteSpecPicker()
        end
        panel:Hide()
        self:ClearPalettePlacement()
        return
    end

    panel:SetFrameLevel((pf:GetFrameLevel() or 0) + 8)
    panel:Show()
    panel:ClearAllPoints()
    local left = self.OBJECT_PALETTE_UI_PAD
    panel:SetPoint("TOPLEFT", pf, "TOPLEFT", left, -self.OBJECT_PALETTE_TOOLBAR_TOP)
    panel:SetPoint("BOTTOMLEFT", pf, "BOTTOMLEFT", left, PALETTE_BOTTOM_INSET)

    if pf.objectPaletteContent then
        local content = pf.objectPaletteContent
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -28)
        content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, PALETTE_HINT_H + 10)
        if content.SetClipsChildren then content:SetClipsChildren(true) end
        self:RelayoutObjectPaletteTiles(pf)
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if pf.objectPalettePanel and pf.objectPalettePanel:IsShown() then
                Diar:RelayoutObjectPaletteTiles(pf)
            end
        end)
    end
    self:ApplyObjectPaletteLockedState(pf)
end

function Diar:CanEditPlannerItems()
    local pf = self.plannerFrame
    if not pf or pf.compactMode or pf.nsrtSceneActive then return false end
    if self.IsPlannerCanvasLocked and self:IsPlannerCanvasLocked() then return false end
    return true
end

function Diar:DeletePlannerSceneItem(itemIndex)
    if not self:CanEditPlannerItems() then return false end
    local pf = self.plannerFrame
    local data = self.plannerData
    if not pf or not data or not data.scenes then return false end
    local sceneIdx = pf.selectedSceneIndex or 1
    local scene = data.scenes[sceneIdx]
    if not scene or not scene.items or not scene.items[itemIndex] then return false end

    local removed = scene.items[itemIndex]
    local removedId = removed.id and tostring(removed.id) or nil
    table.remove(scene.items, itemIndex)

    if scene.animations then
        local kept = {}
        local removedZeroIdx = itemIndex - 1
        for _, anim in ipairs(scene.animations) do
            local drop = false
            if anim.itemIndex ~= nil and anim.itemIndex == removedZeroIdx then
                drop = true
            elseif removedId and anim.objectId and tostring(anim.objectId) == removedId then
                drop = true
            end
            if not drop then
                if type(anim.itemIndex) == "number" and anim.itemIndex > removedZeroIdx then
                    anim.itemIndex = anim.itemIndex - 1
                end
                anim.__resolvedItemIndex = nil
                anim.__normalizedPath = nil
                anim.__pathLengths = nil
                kept[#kept + 1] = anim
            end
        end
        scene.animations = kept
    end

    if self.PersistCurrentPlanToSaved then
        self:PersistCurrentPlanToSaved()
    end
    if self.StopPlannerAnimation then
        self:StopPlannerAnimation()
    end
    if self.RefreshPlannerScene then
        self:RefreshPlannerScene()
    end
    return true
end
