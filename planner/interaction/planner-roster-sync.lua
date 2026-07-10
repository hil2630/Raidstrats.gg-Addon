-- Raid leader: right-click plan objects to assign raid member names and sync to group.
local addonName = ...
local AceAddon = LibStub("AceAddon-3.0")
local Addon =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)
if not Addon then return end
local Diar = Addon

local SEP = string.char(31)
local SetBackdrop = Diar.SetBackdrop
local UI = {
    PANEL   = {0.06, 0.06, 0.09, 0.96},
    BORDER  = {0.22, 0.24, 0.28, 1},
    TOOLBAR = {0.05, 0.05, 0.08, 0.92},
    ROW     = {0.09, 0.10, 0.13, 0.92},
    ROW_HOV = {0.14, 0.16, 0.20, 1},
    ACCENT  = {0.23, 0.51, 0.96, 1},
}
local CONE_LIVE_DRAG_FPS = 30

local function HideClickDismissOverlay()
    if Diar._clickDismissOverlay then
        Diar._clickDismissOverlay:Hide()
        Diar._clickDismissOverlay:SetScript("OnClick", nil)
        Diar._clickDismissOverlay:SetScript("OnMouseUp", nil)
    end
end

local function ShowClickDismissOverlay(anchorFrame, onDismiss)
    HideClickDismissOverlay()
    if not anchorFrame then return end
    if not Diar._clickDismissOverlay then
        local o = CreateFrame("Button", "RaidstratsClickDismiss", UIParent)
        o:SetAllPoints(UIParent)
        o:SetFrameStrata("FULLSCREEN_DIALOG")
        o:EnableMouse(true)
        o:SetAlpha(0.001)
        Diar._clickDismissOverlay = o
    end
    local o = Diar._clickDismissOverlay
    o:SetScript("OnClick", nil)
    o:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" or button == "RightButton" then
            if Diar and Diar.HidePlannerTransientMenus then
                Diar:HidePlannerTransientMenus()
            elseif onDismiss then
                onDismiss()
            end
            HideClickDismissOverlay()
        end
    end)
    o:SetFrameLevel(math.max(0, anchorFrame:GetFrameLevel() - 1))
    o:Show()
end

if not StaticPopupDialogs["RAIDSTRATSGG_CUSTOM_OBJECT_LABEL"] then
    StaticPopupDialogs["RAIDSTRATSGG_CUSTOM_OBJECT_LABEL"] = {
        text = "Custom label:",
        button1 = _G.OKAY or "OK",
        button2 = _G.CANCEL or "Cancel",
        hasEditBox = true,
        maxLetters = 64,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        OnShow = function(self)
            local eb = self.editBox or self.EditBox
            local current = self.data and self.data.currentLabel or ""
            if self.text then
                self.text:SetText((current ~= "" and "Edit label:" or "Add custom label:"))
            end
            if eb then
                eb:SetText(current)
                eb:HighlightText()
                eb:SetFocus()
            end
        end,
        OnAccept = function(self)
            local eb = self.editBox or self.EditBox
            local value = eb and strtrim(eb:GetText() or "") or ""
            if Diar and Diar.ApplyCustomItemLabel and self.data and self.data.itemIndex then
                Diar:ApplyCustomItemLabel(self.data.itemIndex, value)
            end
        end,
    }
end

local function StripScrollChrome(scroll)
    if not scroll then return end
    for _, region in ipairs({ scroll:GetRegions() }) do
        if region:GetObjectType() == "Texture" then
            region:SetTexture(nil)
            region:SetAlpha(0)
        end
    end
end

local function SplitSep(str, sep)
    local out = {}
    local start = 1
    while true do
        local i = str:find(sep, start, true)
        if not i then
            out[#out + 1] = str:sub(start)
            break
        end
        out[#out + 1] = str:sub(start, i - 1)
        start = i + 1
    end
    return out
end

local function NormalizeSlotIndex(value)
    local n = tonumber(value)
    if n and n >= 1 then return math.floor(n + 0.0001) end
    return nil
end

local function ItemSlotIndex(item)
    if not item then return nil end
    return NormalizeSlotIndex(item.slotIndex or item.embedIndex)
end

local function UsesTriangleHitTest(item)
    if not item or tostring(item.kind or ""):lower() ~= "shape" then
        return false
    end
    local shapeKey = tostring(item.shape or ""):lower()
    return shapeKey == "triangle" or shapeKey == "cone"
end

local function GetWidgetCursorPoint(widget)
    if not widget then return nil end
    local scale = widget:GetEffectiveScale()
    if not scale or scale <= 0 then return nil end
    local left = widget:GetLeft()
    local top = widget:GetTop()
    local width = widget:GetWidth()
    local height = widget:GetHeight()
    if not left or not top or not width or not height or width <= 0 or height <= 0 then
        return nil
    end
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    local lx = cx - left
    local ly = top - cy
    return lx, ly, width, height
end

local function IsInsideTriangleBounds(lx, ly, width, height)
    if not lx or not ly or not width or not height or width <= 0 or height <= 0 then
        return false
    end
    if lx < 0 or lx > width or ly < 0 or ly > height then
        return false
    end
    local halfW = width * 0.5
    local yRatio = ly / height
    local maxDistFromCenter = halfW * yRatio
    local distFromCenter = math.abs(lx - halfW)
    -- Small tolerance keeps edge clicks responsive.
    return distFromCenter <= (maxDistFromCenter + 2)
end

-- Cursor position as percent of the scene canvas (world space), matching how
-- item geometry (item.x/y, item.corners) is stored. Mirrors the drag math.
local function GetCursorCanvasPercent()
    local pf = Diar.plannerFrame
    local canvas = pf and pf.canvas
    if not canvas then return nil end
    local scale = canvas:GetEffectiveScale()
    if not scale or scale <= 0 then return nil end
    local left = canvas:GetLeft()
    local top = canvas:GetTop()
    if not left or not top then return nil end
    local cw, ch = canvas:GetSize()
    if not cw or not ch or cw <= 0 or ch <= 0 then return nil end
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    local lx = cx - left
    local ly = top - cy
    local vc = pf.sceneViewContext
    local screenToWorld = Diar.PlannerView and Diar.PlannerView.ScreenToWorld
    local wx, wy = lx, ly
    if screenToWorld then
        wx, wy = screenToWorld(vc, lx, ly)
    elseif vc and vc.zoom and vc.zoom ~= 0 then
        wx = (lx - (vc.panX or 0)) / vc.zoom
        wy = (ly - (vc.panY or 0)) / vc.zoom
    end
    return (wx / cw) * 100, (wy / ch) * 100
end

local function PointInPolygonPct(corners, x, y)
    local n = corners and #corners or 0
    if n < 3 then return false end
    local inside = false
    local j = n
    for i = 1, n do
        local pi = corners[i]
        local pj = corners[j]
        local xi, yi = tonumber(pi and pi.x), tonumber(pi and pi.y)
        local xj, yj = tonumber(pj and pj.x), tonumber(pj and pj.y)
        if xi and yi and xj and yj then
            if ((yi > y) ~= (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi) + xi) then
                inside = not inside
            end
        end
        j = i
    end
    return inside
end

local function DistanceToSegment(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local len2 = dx * dx + dy * dy
    if len2 < 1e-9 then
        local ex, ey = px - ax, py - ay
        return math.sqrt(ex * ex + ey * ey)
    end
    local t = ((px - ax) * dx + (py - ay) * dy) / len2
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local cx, cy = ax + t * dx, ay + t * dy
    local ex, ey = px - cx, py - cy
    return math.sqrt(ex * ex + ey * ey)
end

-- Point-in-polygon for items that store true (possibly rotated) geometry in
-- item.corners (cones, polygons, skewed rects). Includes a small edge tolerance
-- in percent units so clicks right on the visible outline still register.
local function CursorInsidePolygonCorners(item)
    local corners = item and item.corners
    if type(corners) ~= "table" or #corners < 3 then return nil end
    local x, y = GetCursorCanvasPercent()
    if not x then return false end
    if PointInPolygonPct(corners, x, y) then return true end
    local n = #corners
    local tol = 1.2
    for i = 1, n do
        local a = corners[i]
        local b = corners[(i % n) + 1]
        local ax, ay = tonumber(a and a.x), tonumber(a and a.y)
        local bx, by = tonumber(b and b.x), tonumber(b and b.y)
        if ax and ay and bx and by then
            if DistanceToSegment(x, y, ax, ay, bx, by) <= tol then
                return true
            end
        end
    end
    return false
end

local function CursorInsideItemShape(widget, item)
    -- Cones/polygons/skewed shapes carry their real outline in item.corners;
    -- hit test against that instead of the axis-aligned widget rect.
    local polyHit = CursorInsidePolygonCorners(item)
    if polyHit ~= nil then
        return polyHit
    end
    local lx, ly, width, height = GetWidgetCursorPoint(widget)
    if not lx then return false end
    if UsesTriangleHitTest(item) then
        return IsInsideTriangleBounds(lx, ly, width, height)
    end
    return lx >= 0 and lx <= width and ly >= 0 and ly <= height
end

local function GetLineDragAnchor(item)
    if type(item) ~= "table" then return nil, nil end
    local x1 = tonumber(item.x1)
    local y1 = tonumber(item.y1)
    local x2 = tonumber(item.x2)
    local y2 = tonumber(item.y2)
    if not x1 or not y1 or not x2 or not y2 then return nil, nil end
    local pad = 0.01
    return math.min(x1, x2) - pad, math.min(y1, y2) - pad
end

function Diar:IsRsggDebug()
    local s = self.GetPlannerSettings and self:GetPlannerSettings()
    return s and s.debugMode == true
end

function Diar:IsPlanLeader()
    if self:IsRsggDebug() then return true end
    -- Solo, party, or out of group: full assign/edit powers. In raid, raid lead only.
    if not IsInRaid() then return true end
    return UnitIsGroupLeader("player") == true
end

function Diar:IsPushUpdateLeader()
    if not IsInGroup() then return false end
    local isLeader = UnitIsGroupLeader("player") == true
    if self:IsRsggDebug() and not isLeader then
        return false
    end
    return isLeader
end

local DEBUG_FAKE_NAMES = {
    "Aldran", "Brynn", "Caelum", "Drevan", "Elowen",
    "Fennick", "Garrick", "Helena", "Ivara", "Jorund",
}

local DEBUG_FAKE_CLASSES = {
    "warrior", "paladin", "hunter", "rogue", "priest",
    "deathknight", "shaman", "mage", "warlock", "monk",
}

local CLASS_FILE_TO_ICON = {
    WARRIOR = "warrior",
    PALADIN = "paladin",
    HUNTER = "hunter",
    ROGUE = "rogue",
    PRIEST = "priest",
    DEATHKNIGHT = "deathknight",
    SHAMAN = "shaman",
    MAGE = "mage",
    WARLOCK = "warlock",
    MONK = "monk",
    DRUID = "druid",
    DEMONHUNTER = "demonhunter",
    EVOKER = "evoker",
}

local CLASS_WOW_ICON = {
    warrior = "Interface\\Icons\\ClassIcon_Warrior",
    paladin = "Interface\\Icons\\ClassIcon_Paladin",
    hunter = "Interface\\Icons\\ClassIcon_Hunter",
    rogue = "Interface\\Icons\\ClassIcon_Rogue",
    priest = "Interface\\Icons\\ClassIcon_Priest",
    deathknight = "Interface\\Icons\\ClassIcon_DeathKnight",
    shaman = "Interface\\Icons\\ClassIcon_Shaman",
    mage = "Interface\\Icons\\ClassIcon_Mage",
    warlock = "Interface\\Icons\\ClassIcon_Warlock",
    monk = "Interface\\Icons\\ClassIcon_Monk",
    druid = "Interface\\Icons\\ClassIcon_Druid",
    demonhunter = "Interface\\Icons\\ClassIcon_DemonHunter",
    evoker = "Interface\\Icons\\ClassIcon_Evoker",
}

local RAID_MARKER_KEYS = {
    star = true, circle = true, diamond = true, triangle = true,
    moon = true, square = true, cross = true, skull = true,
}
local RAID_MARKER_ORDER = { "star", "circle", "diamond", "triangle", "moon", "square", "cross", "skull" }
local RAID_MARKER_TEXTURE_BY_INDEX = {
    [1] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
    [2] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2",
    [3] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3",
    [4] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4",
    [5] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5",
    [6] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6",
    [7] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7",
    [8] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
}
local WORLD_MARKER_ALIAS_TO_KEY = {
    worldmarker1 = "star",
    worldmarker2 = "circle",
    worldmarker3 = "diamond",
    worldmarker4 = "triangle",
    worldmarker5 = "moon",
    worldmarker6 = "square",
    worldmarker7 = "cross",
    worldmarker8 = "skull",
    wm1 = "star",
    wm2 = "circle",
    wm3 = "diamond",
    wm4 = "triangle",
    wm5 = "moon",
    wm6 = "square",
    wm7 = "cross",
    wm8 = "skull",
}

local ROLE_ICON_KEYS = {
    tank = true, healer = true, rdps = true, mdps = true,
}

local function SetWorldMarkerTexture(tex, markerIndex)
    if not tex then return end
    markerIndex = tonumber(markerIndex)
    if not markerIndex or markerIndex < 1 or markerIndex > 8 then
        tex:SetTexture(nil)
        return
    end
    tex:SetTexCoord(0, 1, 0, 1)
    local texPath = RAID_MARKER_TEXTURE_BY_INDEX[markerIndex]
    if texPath then
        tex:SetTexture(texPath)
        return
    end
    if SetRaidTargetIconTexture then
        SetRaidTargetIconTexture(tex, markerIndex)
    else
        tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    end
end

local function ResolveWorldMarkerKey(item)
    if type(item) ~= "table" then return nil end
    if tostring(item.kind or ""):lower() ~= "icon" then return nil end
    local raw = tostring(item.icon or ""):lower():gsub("\\", "/")
    if raw == "" then return nil end
    local base = raw:match("([^/]+)$") or raw
    if RAID_MARKER_KEYS[base] then return base end
    if WORLD_MARKER_ALIAS_TO_KEY[base] then return WORLD_MARKER_ALIAS_TO_KEY[base] end
    if raw:find("/worldmarkers/", 1, true) or raw:find("worldmarkers/", 1, true)
        or raw:find("worldmarker", 1, true) or raw:find("world-marker", 1, true)
        or raw:find("world_marker", 1, true) then
        local n = tonumber(base:match("(%d+)")) or tonumber(raw:match("worldmarkers?/?(%d+)"))
        if n and n >= 1 and n <= 8 then
            return RAID_MARKER_ORDER[n]
        end
    end
    return nil
end

function Diar:CanAssignPlayerToItem(item)
    if not item then return false end
    if item.kind == "text" then return true end
    if item.kind == "line" then return false end
    if item.kind == "shape" then
        local shp = tostring(item.shape or ""):lower()
        if (shp == "circle" or shp == "ellipse") and ItemSlotIndex(item) then
            return true
        end
        return false
    end
    if item.kind ~= "icon" then return false end
    if item.playerCircle == true then return true end
    local raw = tostring(item.icon or ""):lower()
    local key = raw:gsub("^.*/", "")
    if RAID_MARKER_KEYS[key] then return false end
    if ROLE_ICON_KEYS[key] then return false end
    if raw:find("^roles/", 1, true) then return false end
    return true
end

local function SanitizeIconKey(iconKey)
    iconKey = strtrim(tostring(iconKey or "")):gsub(SEP, "")
    if iconKey == "" then return nil end
    return iconKey
end

local function GetTextureForIconKey(iconKey)
    if not iconKey then return nil end
    local key = iconKey:lower():gsub("^.*/", "")
    return CLASS_WOW_ICON[key]
end

local function GetClassIconKeyForUnit(unit)
    if not unit or not UnitExists(unit) then return nil end
    local _, classFile = UnitClass(unit)
    if not classFile then return nil end
    local key = CLASS_FILE_TO_ICON[classFile:upper()]
    if not key then return nil end
    return "classes/" .. key
end

local function IconKeyDisplayName(iconKey)
    if not iconKey then return nil end
    local key = iconKey:lower():gsub("^.*/", "")
    return key:sub(1, 1):upper() .. key:sub(2)
end

local function LabelNameKey(label)
    if not label or label == "" then return nil end
    local t = strlower(strtrim(label))
    return t:match("^([^%-]+)") or t
end

function Diar:GetDebugRosterNames()
    local list = {}
    local seen = {}
    local function add(name)
        name = strtrim(tostring(name or ""))
        if name == "" or seen[name:lower()] then return end
        seen[name:lower()] = true
        list[#list + 1] = name
    end
    local me = UnitName("player") or "You"
    add(me)
    local custom = self.GetPlannerSettings and self:GetPlannerSettings().debugRoster
    if type(custom) == "string" and custom ~= "" then
        for name in custom:gmatch("[^,;]+") do
            add(name)
        end
    end
    for _, name in ipairs(DEBUG_FAKE_NAMES) do
        add(name)
    end
    local others = {}
    for i = 2, #list do
        others[#others + 1] = list[i]
    end
    table.sort(others, function(a, b) return a:lower() < b:lower() end)
    local out = { me }
    for _, name in ipairs(others) do
        out[#out + 1] = name
    end
    return out
end

function Diar:GetDebugRosterEntries()
    local names = self:GetDebugRosterNames()
    local out = {}
    for i, name in ipairs(names) do
        local icon
        if i == 1 then
            icon = GetClassIconKeyForUnit("player")
        else
            local cls = DEBUG_FAKE_CLASSES[((i - 2) % #DEBUG_FAKE_CLASSES) + 1]
            icon = "classes/" .. cls
        end
        out[#out + 1] = { name = name, icon = icon }
    end
    return out
end

function Diar:FindGroupUnitByName(playerName)
    local want = LabelNameKey(playerName)
    if not want then return nil end
    local function match(unit)
        if not unit or not UnitExists(unit) then return nil end
        local name = UnitName(unit)
        if name and LabelNameKey(name) == want then return unit end
        return nil
    end
    local hit = match("player")
    if hit then return hit end
    local num = GetNumGroupMembers()
    if num == 0 then return nil end
    local prefix = IsInRaid() and "raid" or "party"
    for i = 1, num do
        local unit = (prefix == "party" and i == num) and "player" or (prefix .. i)
        hit = match(unit)
        if hit then return hit end
    end
    return nil
end

function Diar:GetClassIconKeyForPlayerName(playerName)
    local unit = self:FindGroupUnitByName(playerName)
    if unit then return GetClassIconKeyForUnit(unit) end
    if self:IsRsggDebug() and LabelNameKey(playerName) == LabelNameKey(UnitName("player") or "You") then
        return GetClassIconKeyForUnit("player")
    end
    return nil
end

function Diar:GetGroupMemberRoster()
    if self:IsRsggDebug() then
        return self:GetDebugRosterEntries()
    end
    local list = {}
    local seen = {}
    local function addUnit(unit)
        if not unit or not UnitExists(unit) then return end
        local name = UnitName(unit)
        if not name or name == "" or seen[name:lower()] then return end
        seen[name:lower()] = true
        list[#list + 1] = {
            name = name,
            icon = GetClassIconKeyForUnit(unit),
        }
    end
    local num = GetNumGroupMembers()
    if num == 0 then
        addUnit("player")
    else
        local prefix = IsInRaid() and "raid" or "party"
        for i = 1, num do
            local unit = (prefix == "party" and i == num) and "player" or (prefix .. i)
            addUnit(unit)
        end
    end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    return list
end

function Diar:FindPlanLabelUsage(name, excludeSceneIndex, excludeItemIndex)
    local data = self.plannerData
    local key = LabelNameKey(name)
    if not key or not data or not data.scenes then return nil end
    for si, scene in ipairs(data.scenes) do
        if scene.items then
            for ii, item in ipairs(scene.items) do
                if not (si == excludeSceneIndex and ii == excludeItemIndex) then
                    local lbl = item.label
                    if lbl and lbl ~= "" and LabelNameKey(lbl) == key then
                        return si, ii, lbl
                    end
                end
            end
        end
    end
    return nil
end

function Diar:GetSceneDisplayName(sceneIndex)
    local data = self.plannerData
    local scene = data and data.scenes and data.scenes[sceneIndex]
    if scene and scene.name and scene.name ~= "" then
        return tostring(scene.name)
    end
    return tostring(sceneIndex)
end

function Diar:HideDuplicateLabelWarning()
    if self._duplicateLabelWarn then
        self._duplicateLabelWarn:Hide()
    end
end

function Diar:ShowDuplicateLabelWarning(name, usageScene, itemIndex, anchor, iconKey)
    self:HideDuplicateLabelWarning()
    local sceneLabel = self:GetSceneDisplayName(usageScene)
    print(("|cffff9900[Raidstrats.gg]|r |cff00ff00%s|r is already on the plan (%s)."):format(name, sceneLabel))

    local pf = self.plannerFrame
    local f = CreateFrame("Frame", "RaidstratsDuplicateLabelWarn", UIParent, "BackdropTemplate")
    f:SetSize(320, 128)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)
    if SetBackdrop then SetBackdrop(f, UI.PANEL, UI.BORDER, 2) end
    tinsert(UISpecialFrames, "RaidstratsDuplicateLabelWarn")

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("Player already assigned")
    title:SetTextColor(1, 0.85, 0.35)

    local msg = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    msg:SetPoint("TOP", title, "BOTTOM", 0, -10)
    msg:SetWidth(280)
    msg:SetJustifyH("CENTER")
    msg:SetText(("%s is already on this plan (%s).\nAssign them here anyway?"):format(name, sceneLabel))
    msg:SetTextColor(0.82, 0.82, 0.82)

    local function makeBtn(text, x, onClick)
        local b = CreateFrame("Button", nil, f, "BackdropTemplate")
        b:SetSize(120, 28)
        b:SetPoint("BOTTOM", x, 16)
        if SetBackdrop then SetBackdrop(b, UI.ROW, UI.BORDER, 1) end
        local lbl = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("CENTER")
        lbl:SetText(text)
        lbl:SetTextColor(0.9, 0.9, 0.9)
        b:SetScript("OnEnter", function(s)
            s:SetBackdropColor(unpack(UI.ROW_HOV))
            lbl:SetTextColor(1, 1, 1)
        end)
        b:SetScript("OnLeave", function(s)
            s:SetBackdropColor(unpack(UI.ROW))
            lbl:SetTextColor(0.9, 0.9, 0.9)
        end)
        b:SetScript("OnClick", onClick)
        return b
    end

    makeBtn("Cancel", -66, function()
        Diar:HideDuplicateLabelWarning()
    end)
    makeBtn("Assign anyway", 66, function()
        Diar:HideDuplicateLabelWarning()
        Diar:HideMemberPicker()
        Diar:ApplyItemLabelRename(itemIndex, name, iconKey)
    end)

    f:SetScript("OnHide", function()
        if Diar._duplicateLabelWarn == f then
            Diar._duplicateLabelWarn = nil
        end
    end)

    self._duplicateLabelWarn = f
    if Diar.PrepareModal then
        Diar:PrepareModal(f, anchor or pf or self.frame)
    end
    f:ClearAllPoints()
    if anchor and anchor.IsShown and anchor:IsShown() then
        f:SetPoint("CENTER", anchor, "CENTER")
    elseif pf and pf:IsShown() then
        f:SetPoint("CENTER", pf, "CENTER")
    else
        f:SetPoint("CENTER")
    end
    f:SetFrameLevel((pf and pf:GetFrameLevel() or 500) + 120)
    f:Raise()
    f:Show()
end

function Diar:GetPlanSyncKey()
    local data = self.plannerData
    if not data then return nil end
    if data.savedEntryId then
        return "sv:" .. tostring(data.savedEntryId)
    end
    if data.planId and tostring(data.planId) ~= "" then
        return "id:" .. tostring(data.planId)
    end
    if data.planName and data.planName ~= "" then
        return "nm:" .. tostring(data.planName):gsub(SEP, "")
    end
    return nil
end

function Diar:IsPlayerCircleItem(item)
    if not item then return false end
    if item.playerCircle == true then return true end
    if item.kind ~= "shape" then return false end
    local shp = tostring(item.shape or ""):lower()
    return (shp == "circle" or shp == "ellipse") and ItemSlotIndex(item) ~= nil
end

local function BuildRgbaStringFromColor(r, g, b, a)
    local rr = math.max(0, math.min(255, math.floor(((tonumber(r) or 0) * 255) + 0.5)))
    local gg = math.max(0, math.min(255, math.floor(((tonumber(g) or 0) * 255) + 0.5)))
    local bb = math.max(0, math.min(255, math.floor(((tonumber(b) or 0) * 255) + 0.5)))
    local aa = tonumber(a)
    if type(aa) ~= "number" then aa = 1 end
    aa = math.max(0, math.min(1, aa))
    return ("rgba(%d,%d,%d,%.3f)"):format(rr, gg, bb, aa)
end

local function ResolveCircleFillFromIconKey(self, iconKey, item)
    if not self or type(iconKey) ~= "string" or iconKey == "" then return nil end
    local opacity = (type(item) == "table" and type(item.opacity) == "number") and item.opacity or 1
    if self.ResolveClassKeyFromIconKey and self.GetClassCircleColor then
        local classKey = self.ResolveClassKeyFromIconKey(iconKey)
        if classKey then
            local r, g, b, a = self.GetClassCircleColor(classKey, opacity)
            return BuildRgbaStringFromColor(r, g, b, a)
        end
    end
    if self.ResolveRoleKeyFromIconKey and self.GetRoleCircleColor then
        local roleKey = self.ResolveRoleKeyFromIconKey(iconKey)
        if roleKey then
            local r, g, b, a = self.GetRoleCircleColor(roleKey, opacity)
            return BuildRgbaStringFromColor(r, g, b, a)
        end
    end
    return nil
end

function Diar:ApplyIconToPlanItem(item, iconKey)
    if not item or not iconKey or iconKey == "" then return end
    if item.kind == "icon" then
        item.icon = iconKey
    elseif self.IsPlayerCircleItem and self:IsPlayerCircleItem(item) then
        item.kind = "icon"
        item.playerCircle = true
        item.shape = nil
        item.icon = iconKey
    end
    if self.IsPlayerCircleItem and self:IsPlayerCircleItem(item) then
        -- Reassignments should recolor spot circles to the assigned class/role color.
        local fill = ResolveCircleFillFromIconKey(self, iconKey, item)
        if fill then
            item.fill = fill
        end
    end
end

function Diar:RenamePlanActor(oldName, newName, iconKey, slotIndex)
    local data = self.plannerData
    if not data or not data.scenes then return 0 end
    local oldKey = LabelNameKey(oldName)
    newName = strtrim(tostring(newName or ""))
    iconKey = SanitizeIconKey(iconKey)
    if not oldKey or LabelNameKey(newName) == oldKey then return 0 end
    slotIndex = NormalizeSlotIndex(slotIndex)

    local count = 0
    for _, scene in ipairs(data.scenes) do
        if scene.items then
            for _, item in ipairs(scene.items) do
                local lbl = item.label
                if lbl and lbl ~= "" and LabelNameKey(lbl) == oldKey then
                    local itemSlot = ItemSlotIndex(item)
                    if not slotIndex or itemSlot == slotIndex then
                        item.label = newName
                        self:ApplyIconToPlanItem(item, iconKey)
                        count = count + 1
                    end
                end
            end
        end
    end
    return count
end

function Diar:BuildLabelSyncMsg(planKey, sceneIndex, itemIndex, label, iconKey)
    label = tostring(label or ""):gsub(SEP, "")
    iconKey = SanitizeIconKey(iconKey)
    local parts = { "LBL", planKey, tostring(sceneIndex), tostring(itemIndex), label }
    if iconKey then parts[#parts + 1] = iconKey end
    return table.concat(parts, SEP)
end

function Diar:BuildActorLabelSyncMsg(planKey, oldLabel, newLabel, iconKey, slotIndex)
    oldLabel = tostring(oldLabel or ""):gsub(SEP, "")
    newLabel = tostring(newLabel or ""):gsub(SEP, "")
    iconKey = SanitizeIconKey(iconKey)
    slotIndex = NormalizeSlotIndex(slotIndex)
    local parts = { "LBA", planKey, oldLabel, newLabel }
    if iconKey then parts[#parts + 1] = iconKey end
    if slotIndex then parts[#parts + 1] = tostring(slotIndex) end
    return table.concat(parts, SEP)
end

function Diar:ParseActorLabelSyncMsg(msg)
    if type(msg) ~= "string" or msg:sub(1, 3) ~= "LBA" then return nil end
    local parts = SplitSep(msg, SEP)
    if parts[1] ~= "LBA" or #parts < 4 then return nil end
    local icon = nil
    local slotIndex = nil
    if #parts >= 5 then
        icon = SanitizeIconKey(parts[5])
    end
    if #parts >= 6 then
        slotIndex = NormalizeSlotIndex(parts[6])
    end
    return {
        planKey = parts[2],
        oldLabel = parts[3],
        newLabel = parts[4],
        icon = icon,
        slotIndex = slotIndex,
    }
end

function Diar:ParseLabelSyncMsg(msg)
    if type(msg) ~= "string" or msg:sub(1, 3) ~= "LBL" then return nil end
    local parts = SplitSep(msg, SEP)
    if parts[1] ~= "LBL" or #parts < 5 then return nil end
    return {
        planKey = parts[2],
        sceneIndex = tonumber(parts[3]),
        itemIndex = tonumber(parts[4]),
        label = parts[5],
        icon = parts[6],
    }
end

function Diar:HidePlannerContextMenu()
    HideClickDismissOverlay()
    if self._plannerCtxMenu then
        self._plannerCtxMenu:Hide()
    end
    if self._worldMarkerReplaceMenu then
        self._worldMarkerReplaceMenu:Hide()
    end
end

function Diar:RemovePlannerItemIndex(itemIndex)
    if not (self.CanEditPlannerItems and self:CanEditPlannerItems()) then return false end
    local pf = self.plannerFrame
    local data = self.plannerData
    if not pf or not data or not data.scenes then return false end
    local sceneIdx = pf.selectedSceneIndex or 1
    local scene = data.scenes[sceneIdx]
    if not scene or not scene.items then return false end
    local item = scene.items[itemIndex]
    if not item then return false end
    if not ItemSlotIndex(item) then return false end

    item.slotIndex = nil
    item.embedIndex = nil

    if self.RefreshPlannerScene then
        self:RefreshPlannerScene()
    end
    local saved = self.PersistCurrentPlanToSaved and self:PersistCurrentPlanToSaved()
    print(("|cff00aaff[Raidstrats.gg]|r Index removed%s."):format(saved and " and saved locally" or ""))
    return true
end

function Diar:ReplaceWorldMarker(itemIndex, markerKey)
    markerKey = tostring(markerKey or ""):lower()
    if not RAID_MARKER_KEYS[markerKey] then return false end
    if not (self.CanEditPlannerItems and self:CanEditPlannerItems()) then return false end
    local pf = self.plannerFrame
    local data = self.plannerData
    if not pf or not data or not data.scenes then return false end
    local sceneIdx = pf.selectedSceneIndex or 1
    local scene = data.scenes[sceneIdx]
    if not scene or not scene.items then return false end
    local item = scene.items[itemIndex]
    if not item then return false end
    if not ResolveWorldMarkerKey(item) then return false end

    item.kind = "icon"
    item.icon = markerKey
    item.worldMarker = true
    item.isWorldMarker = true
    item.playerCircle = nil
    item.label = item.label or ""
    item.labelAttached = nil
    item.slotIndex = nil
    item.embedIndex = nil

    if self.RefreshPlannerScene then
        self:RefreshPlannerScene()
    end
    if self.PersistCurrentPlanToSaved then
        self:PersistCurrentPlanToSaved()
    end
    return true
end

function Diar:ShowWorldMarkerReplaceMenu(anchor, itemIndex, item)
    if not anchor or not item or not ResolveWorldMarkerKey(item) then return end
    if self:IsPlannerCompactMode() then return end
    if not (self.CanEditPlannerItems and self:CanEditPlannerItems()) then return end

    if self._worldMarkerReplaceMenu then
        self._worldMarkerReplaceMenu:Hide()
        self._worldMarkerReplaceMenu = nil
    end

    local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    menu:SetSize(148, 8 + (#RAID_MARKER_ORDER * 24) + 8)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(525)
    menu:EnableMouse(true)
    if SetBackdrop then SetBackdrop(menu, UI.ROW, UI.BORDER, 1) end
    menu:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)

    local y = -6
    for i = 1, #RAID_MARKER_ORDER do
        local key = RAID_MARKER_ORDER[i]
        local btn = CreateFrame("Button", nil, menu, "BackdropTemplate")
        btn:SetSize(132, 22)
        btn:SetPoint("TOP", menu, "TOP", 0, y)
        SetBackdrop(btn, UI.ROW, UI.BORDER, 1)
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(14, 14)
        icon:SetPoint("LEFT", btn, "LEFT", 8, 0)
        SetWorldMarkerTexture(icon, i)
        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        lbl:SetText(key:sub(1, 1):upper() .. key:sub(2))
        lbl:SetTextColor(0.92, 0.92, 0.92)
        btn:SetScript("OnEnter", function(s)
            s:SetBackdropColor(unpack(UI.ROW_HOV))
            lbl:SetTextColor(1, 1, 1)
        end)
        btn:SetScript("OnLeave", function(s)
            s:SetBackdropColor(unpack(UI.ROW))
            lbl:SetTextColor(0.92, 0.92, 0.92)
        end)
        btn:SetScript("OnClick", function()
            Diar:HidePlannerContextMenu()
            Diar:ReplaceWorldMarker(itemIndex, key)
        end)
        y = y - 24
    end

    menu:SetScript("OnHide", function()
        if Diar._worldMarkerReplaceMenu == menu then
            Diar._worldMarkerReplaceMenu = nil
        end
    end)
    self._worldMarkerReplaceMenu = menu
    menu:Show()
end

function Diar:ShowPlannerContextMenu(anchor, itemIndex, item)
    if self:IsPlannerCompactMode() then return end

    local canEdit = self.CanEditPlannerItems and self:CanEditPlannerItems()
    local canAssign = canEdit and item and self:CanAssignPlayerToItem(item) and self:IsPlanLeader()
    local canDelete = canEdit
    local canCustomLabel = canEdit and item ~= nil
    local canRemoveIndex = canEdit and item ~= nil and ItemSlotIndex(item) ~= nil
    local canReplaceMarker = canEdit and item ~= nil and ResolveWorldMarkerKey(item) ~= nil
    if not canAssign and not canDelete and not canCustomLabel and not canRemoveIndex and not canReplaceMarker then return end

    self:HidePlannerContextMenu()

    local menuH = 12
        + (canAssign and 30 or 0)
        + (canCustomLabel and 30 or 0)
        + (canRemoveIndex and 30 or 0)
        + (canReplaceMarker and 30 or 0)
        + (canDelete and 30 or 0)
    local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    menu:SetSize(148, menuH)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(520)
    menu:EnableMouse(true)
    if SetBackdrop then SetBackdrop(menu, UI.ROW, UI.BORDER, 1) end

    if anchor then
        menu:SetPoint("TOPLEFT", anchor, "BOTTOMRIGHT", 4, -4)
    else
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    end

    local function makeMenuBtn(text, yOffset, onClick)
        local btn = CreateFrame("Button", nil, menu, "BackdropTemplate")
        btn:SetSize(132, 26)
        btn:SetPoint("TOP", menu, "TOP", 0, yOffset)
        SetBackdrop(btn, UI.ROW, UI.BORDER, 1)
        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("CENTER")
        lbl:SetText(text)
        lbl:SetTextColor(0.92, 0.92, 0.92)
        btn:SetScript("OnEnter", function(s)
            s:SetBackdropColor(unpack(UI.ROW_HOV))
            lbl:SetTextColor(1, 1, 1)
        end)
        btn:SetScript("OnLeave", function(s)
            s:SetBackdropColor(unpack(UI.ROW))
            lbl:SetTextColor(0.92, 0.92, 0.92)
        end)
        btn:SetScript("OnClick", onClick)
        return btn
    end

    local y = -6
    if canAssign then
        makeMenuBtn("Assign member", y, function()
            Diar:HidePlannerContextMenu()
            Diar:ShowMemberPickerForItem(itemIndex)
        end)
        y = y - 30
    end
    if canCustomLabel then
        local currentLabel = strtrim(tostring(item and item.label or ""))
        local labelText = (currentLabel ~= "") and "Edit label" or "Add custom label"
        makeMenuBtn(labelText, y, function()
            Diar:HidePlannerContextMenu()
            Diar:PromptCustomItemLabel(itemIndex, item)
        end)
        y = y - 30
    end
    if canRemoveIndex then
        makeMenuBtn("Remove index", y, function()
            Diar:HidePlannerContextMenu()
            Diar:RemovePlannerItemIndex(itemIndex)
        end)
        y = y - 30
    end
    if canReplaceMarker then
        makeMenuBtn("Replace marker", y, function()
            Diar:ShowWorldMarkerReplaceMenu(menu, itemIndex, item)
        end)
        y = y - 30
    end
    if canDelete then
        makeMenuBtn("Delete", y, function()
            Diar:HidePlannerContextMenu()
            StaticPopup_Show("RAIDSTRATSGG_DELETE_OBJECT", nil, nil, itemIndex)
        end)
    end

    menu:SetScript("OnHide", function()
        HideClickDismissOverlay()
        if Diar._plannerCtxMenu == menu then
            Diar._plannerCtxMenu = nil
        end
    end)

    self._plannerCtxMenu = menu
    menu:Show()
    ShowClickDismissOverlay(menu, function()
        Diar:HidePlannerContextMenu()
    end)
end

function Diar:HideMemberPicker()
    HideClickDismissOverlay()
    self:HideDuplicateLabelWarning()
    if self._memberPicker then
        self._memberPicker:Hide()
    end
end

function Diar:HidePlannerTransientMenus()
    if self.HideSceneTabContextMenu then
        self:HideSceneTabContextMenu()
    end
    if self.HidePlannerContextMenu then
        self:HidePlannerContextMenu()
    end
    if self._worldMarkerReplaceMenu then
        self._worldMarkerReplaceMenu:Hide()
    end
    if self.HideMemberPicker then
        self:HideMemberPicker()
    end
    if self.HideDuplicateLabelWarning then
        self:HideDuplicateLabelWarning()
    end
    if self.HidePaletteSpecPicker then
        self:HidePaletteSpecPicker()
    end
end

function Diar:ShowMemberPickerForItem(itemIndex)
    if not self:IsPlanLeader() then return end
    self:HideMemberPicker()

    local members = self:GetGroupMemberRoster()
    if #members == 0 then
        print("|cffff6666[Raidstrats.gg]|r No group members found.")
        return
    end

    local pf = self.plannerFrame
    local data = self.plannerData
    local sceneIdx = pf and pf.selectedSceneIndex or 1
    local currentLabel = ""
    local item = nil
    if data and data.scenes and data.scenes[sceneIdx] and data.scenes[sceneIdx].items then
        item = data.scenes[sceneIdx].items[itemIndex]
        if item and item.label then currentLabel = item.label end
    end

    local headerH = currentLabel ~= "" and 56 or 44
    local listH = math.min(280, math.max(1, #members) * 30 + 8)
    local f = CreateFrame("Frame", "RaidstratsMemberPicker", UIParent, "BackdropTemplate")
    f:SetSize(268, headerH + listH + 24)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    if SetBackdrop then SetBackdrop(f, UI.PANEL, UI.BORDER, 2) end
    tinsert(UISpecialFrames, "RaidstratsMemberPicker")
    f:SetScript("OnMouseDown", function(s, b) if b == "LeftButton" then s:StartMoving() end end)
    f:SetScript("OnMouseUp", function(s) s:StopMovingOrSizing() end)

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Assign raid member")
    title:SetTextColor(0.92, 0.92, 0.92)

    local subY = -38
    if currentLabel ~= "" then
        local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sub:SetPoint("TOP", title, "BOTTOM", 0, -6)
        local slotNum = tonumber(item and (item.slotIndex or item.embedIndex))
        if slotNum and slotNum >= 1 then
            sub:SetText(("Current: |cffeadb5f%s|r (#%d)"):format(currentLabel, math.floor(slotNum)))
        else
            sub:SetText(("Current: |cffeadb5f%s|r"):format(currentLabel))
        end
        sub:SetTextColor(0.65, 0.68, 0.72)
        subY = -52
    end

    local listPanel = CreateFrame("Frame", nil, f, "BackdropTemplate")
    listPanel:SetPoint("TOPLEFT", f, "TOPLEFT", 12, subY)
    listPanel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
    if SetBackdrop then SetBackdrop(listPanel, UI.TOOLBAR, UI.BORDER, 1) end

    local scroll = CreateFrame("ScrollFrame", nil, listPanel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", listPanel, "BOTTOMRIGHT", -6, 6)
    StripScrollChrome(scroll)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(220)
    child:SetHeight(math.max(1, #members * 30))
    scroll:SetScrollChild(child)

    if Diar.SkinScrollBar then Diar.SkinScrollBar(scroll) end

    local y = -2
    for _, member in ipairs(members) do
        local name = member.name
        local iconKey = member.icon or Diar:GetClassIconKeyForPlayerName(name)
        local isCurrent = currentLabel ~= "" and LabelNameKey(name) == LabelNameKey(currentLabel)
        local usageScene = Diar:FindPlanLabelUsage(name, sceneIdx, itemIndex)
        local isOnPlan = usageScene ~= nil
        local row = CreateFrame("Button", nil, child, "BackdropTemplate")
        row:SetSize(216, 26)
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
        if SetBackdrop then
            SetBackdrop(row, isCurrent and {0.12, 0.11, 0.05, 0.95} or UI.ROW, UI.BORDER, 1)
        end
        local iconTex = row:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(18, 18)
        iconTex:SetPoint("LEFT", 8, 0)
        local texPath = GetTextureForIconKey(iconKey)
        if texPath then
            iconTex:SetTexture(texPath)
        else
            iconTex:SetColorTexture(0.25, 0.25, 0.28, 1)
        end
        local rowLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rowLbl:SetPoint("LEFT", iconTex, "RIGHT", 6, 0)
        rowLbl:SetText(isOnPlan and (name .. " (on plan)") or name)
        if isCurrent then
            rowLbl:SetTextColor(1.00, 0.92, 0.35)
        elseif isOnPlan then
            rowLbl:SetTextColor(1.00, 0.55, 0.35)
        else
            rowLbl:SetTextColor(0.88, 0.88, 0.88)
        end
        row:SetScript("OnEnter", function(s)
            s:SetBackdropColor(unpack(UI.ROW_HOV))
            rowLbl:SetTextColor(1, 1, 1)
        end)
        row:SetScript("OnLeave", function(s)
            if isCurrent then
                s:SetBackdropColor(0.12, 0.11, 0.05, 0.95)
                rowLbl:SetTextColor(1.00, 0.92, 0.35)
            elseif isOnPlan then
                s:SetBackdropColor(unpack(UI.ROW))
                rowLbl:SetTextColor(1.00, 0.55, 0.35)
            else
                s:SetBackdropColor(unpack(UI.ROW))
                rowLbl:SetTextColor(0.88, 0.88, 0.88)
            end
        end)
        row:SetScript("OnClick", function()
            if usageScene then
                Diar:ShowDuplicateLabelWarning(name, usageScene, itemIndex, f, iconKey)
                return
            end
            Diar:HideMemberPicker()
            Diar:ApplyItemLabelRename(itemIndex, name, iconKey)
        end)
        y = y - 30
    end

    f:SetScript("OnHide", function()
        HideClickDismissOverlay()
        if Diar._memberPicker == f then
            Diar._memberPicker = nil
        end
    end)

    self._memberPicker = f
    if Diar.PrepareModal then
        Diar:PrepareModal(f, pf or self.frame)
    end
    f:ClearAllPoints()
    if pf and pf:IsShown() then
        f:SetPoint("CENTER", pf, "CENTER")
    else
        f:SetPoint("CENTER")
    end
    f:Raise()
    f:Show()
    ShowClickDismissOverlay(f, function()
        Diar:HideMemberPicker()
    end)
end

function Diar:BroadcastLabelChange(sceneIndex, itemIndex, label, oldLabel, iconKey)
    if not self:IsPlanLeader() then return end
    local chan = self.GetGroupChatChannel and self:GetGroupChatChannel()
    if not chan then
        if self:IsRsggDebug() then
            return
        end
        print("|cffff6666[Raidstrats.gg]|r Join a party/raid to sync name changes.")
        return
    end
    local planKey = self:GetPlanSyncKey()
    if not planKey then return end
    local prefix = self.COMM_PLAN_PREFIX or "RAIDSTRATS_PLAN"
    local msg
    iconKey = SanitizeIconKey(iconKey)
    local slotIndex = nil
    local data = self.plannerData
    if data and data.scenes and data.scenes[sceneIndex] and data.scenes[sceneIndex].items then
        slotIndex = ItemSlotIndex(data.scenes[sceneIndex].items[itemIndex])
    end
    if oldLabel and oldLabel ~= "" and LabelNameKey(oldLabel) then
        msg = self:BuildActorLabelSyncMsg(planKey, oldLabel, label, iconKey, slotIndex)
    else
        msg = self:BuildLabelSyncMsg(planKey, sceneIndex, itemIndex, label, iconKey)
    end
    self:SendCommMessage(prefix, msg, chan)
end

function Diar:ApplyItemLabelRename(itemIndex, newName, iconKey)
    local pf = self.plannerFrame
    local data = self.plannerData
    if not pf or not data or not data.scenes then return end
    local sceneIdx = pf.selectedSceneIndex or 1
    local scene = data.scenes[sceneIdx]
    if not scene or not scene.items then return end
    local item = scene.items[itemIndex]
    if not item then return end

    newName = strtrim(tostring(newName or ""))
    iconKey = SanitizeIconKey(iconKey) or self:GetClassIconKeyForPlayerName(newName)
    local oldName = strtrim(tostring(item.label or ""))
    local slotIndex = ItemSlotIndex(item)
    local count
    if oldName ~= "" and LabelNameKey(oldName) then
        count = self:RenamePlanActor(oldName, newName, iconKey, slotIndex)
    else
        item.label = newName
        self:ApplyIconToPlanItem(item, iconKey)
        count = 1
    end
    if count == 0 then return end

    if self.RefreshPlannerScene then
        self:RefreshPlannerScene()
    end
    local saved = self.PersistCurrentPlanToSaved and self:PersistCurrentPlanToSaved()
    self:BroadcastLabelChange(sceneIdx, itemIndex, newName, oldName, iconKey)
    local sceneNote = count > 1 and (" (%d places)"):format(count) or ""
    local classNote = iconKey and (" |cff9fd3ff%s|r"):format(IconKeyDisplayName(iconKey) or "") or ""
    if self:IsRsggDebug() and GetNumGroupMembers() == 0 then
        print(("|cff00aaff[Raidstrats.gg]|r [debug] Assigned |cff00ff00%s|r%s%s%s."):format(
            newName, classNote, sceneNote, saved and " (saved)" or ""))
    else
        print(("|cff00aaff[Raidstrats.gg]|r Assigned |cff00ff00%s|r%s%s%s."):format(
            newName,
            classNote,
            sceneNote,
            saved and " and saved locally" or (GetNumGroupMembers() > 0 and " and synced to group" or "")))
    end
end

function Diar:PromptCustomItemLabel(itemIndex, item)
    if not (self.CanEditPlannerItems and self:CanEditPlannerItems()) then return end
    local current = strtrim(tostring((item and item.label) or ""))
    StaticPopup_Show("RAIDSTRATSGG_CUSTOM_OBJECT_LABEL", nil, nil, {
        itemIndex = itemIndex,
        currentLabel = current,
    })
end

function Diar:ApplyCustomItemLabel(itemIndex, newLabel)
    if not (self.CanEditPlannerItems and self:CanEditPlannerItems()) then return end
    local pf = self.plannerFrame
    local data = self.plannerData
    if not pf or not data or not data.scenes then return end
    local sceneIdx = pf.selectedSceneIndex or 1
    local scene = data.scenes[sceneIdx]
    if not scene or not scene.items then return end
    local item = scene.items[itemIndex]
    if not item then return end

    local oldLabel = strtrim(tostring(item.label or ""))
    local normalized = strtrim(tostring(newLabel or ""))
    if oldLabel == normalized then return end

    item.label = normalized
    if self.RefreshPlannerScene then
        self:RefreshPlannerScene()
    end
    local saved = self.PersistCurrentPlanToSaved and self:PersistCurrentPlanToSaved()
    if self.IsPlanLeader and self:IsPlanLeader() and self.BroadcastLabelChange then
        self:BroadcastLabelChange(sceneIdx, itemIndex, normalized, nil, SanitizeIconKey(item.icon))
    end
    if normalized ~= "" then
        print(("|cff00aaff[Raidstrats.gg]|r Label set to |cff00ff00%s|r%s."):format(
            normalized,
            saved and " and saved locally" or ""))
    else
        print(("|cff00aaff[Raidstrats.gg]|r Label cleared%s."):format(saved and " and saved locally" or ""))
    end
end

function Diar:HandleRsggDebugCommand(msg)
    local s = self:GetPlannerSettings()
    msg = strtrim(tostring(msg or "")):lower()

    if msg == "help" or msg == "?" then
        print("|cff00aaff[Raidstrats.gg]|r /rsggdebug — toggle fake raid leader (right-click rename, no group needed)")
        print("|cff00aaff[Raidstrats.gg]|r /rsggdebug on | off")
        print("|cff00aaff[Raidstrats.gg]|r /rsggdebug roster Name1,Name2,... — override fake roster names")
        print("|cff00aaff[Raidstrats.gg]|r /rsggdebug rings — dump current scene ring sizes")
        print("|cff00aaff[Raidstrats.gg]|r /rsggdebug editmode — dump EditMode integration status/log")
        print("|cff00aaff[Raidstrats.gg]|r /rsggdebug editmode reset — reset + retry EditMode registration")
        return
    end

    if msg == "editmode" or msg == "editmode log" then
        if self.PrintEditModeDebug then
            self:PrintEditModeDebug()
        else
            print("|cffff6666[Raidstrats.gg]|r EditMode debug is not available.")
        end
        return
    elseif msg == "editmode reset" then
        if self.ResetEditModeDebug then
            self:ResetEditModeDebug()
            if self.PrintEditModeDebug then
                self:PrintEditModeDebug()
            end
        else
            print("|cffff6666[Raidstrats.gg]|r EditMode debug reset is not available.")
        end
        return
    elseif msg == "off" then
        s.debugMode = false
    elseif msg == "on" then
        s.debugMode = true
    elseif msg:sub(1, 7) == "roster " then
        s.debugRoster = strtrim(msg:sub(8))
        print("|cff00aaff[Raidstrats.gg]|r Debug roster: " .. (s.debugRoster ~= "" and s.debugRoster or "(defaults)"))
        if self.RefreshPlannerScene then self:RefreshPlannerScene() end
        return
    elseif msg == "roster" then
        s.debugRoster = nil
        print("|cff00aaff[Raidstrats.gg]|r Debug roster reset to defaults.")
        return
    elseif msg == "rings" or msg == "sizes" then
        local pf = self.plannerFrame
        local data = self.plannerData
        local sceneIdx = (pf and pf.selectedSceneIndex) or 1
        local scene = data and data.scenes and data.scenes[sceneIdx]
        local canvas = pf and pf.canvas
        local cw = canvas and canvas.GetWidth and canvas:GetWidth() or nil
        local ch = canvas and canvas.GetHeight and canvas:GetHeight() or nil
        local vc = pf and pf.sceneViewContext or nil
        if self.DebugLogSceneRingSizes then
            self:DebugLogSceneRingSizes("manual", scene, sceneIdx, cw, ch, vc)
            print("|cff00aaff[Raidstrats.gg]|r Ring size debug dumped to planner debug log.")
        else
            print("|cffff6666[Raidstrats.gg]|r Ring size debug is not available.")
        end
        return
    else
        s.debugMode = not s.debugMode
    end

    if s.debugMode then
        print("|cff00aaff[Raidstrats.gg]|r Debug ON — fake raid leader + 10-name test roster in picker.")
    else
        print("|cff00aaff[Raidstrats.gg]|r Debug OFF.")
    end
    if self.AppendPlannerDebugLine then
        self:AppendPlannerDebugLine(("Debug mode %s via /rsggdebug"):format(s.debugMode and "ON" or "OFF"))
    end
    if self.UpdatePlannerDebugPanel then
        self:UpdatePlannerDebugPanel()
    end
    if self.UpdatePushUpdateButton then self:UpdatePushUpdateButton() end
    if self.RefreshPlannerScene then self:RefreshPlannerScene() end
end

function Diar:ApplyActorLabelSyncFromComm(msg, sender)
    local parsed = self:ParseActorLabelSyncMsg(msg)
    if not parsed or not parsed.oldLabel then return end
    if parsed.planKey ~= self:GetPlanSyncKey() then return end

    local count = self:RenamePlanActor(parsed.oldLabel, parsed.newLabel or "", parsed.icon, parsed.slotIndex)
    if count == 0 then return end

    local pf = self.plannerFrame
    if pf and pf:IsShown() and self.RefreshPlannerScene then
        self:RefreshPlannerScene()
    end
    if self.PersistCurrentPlanToSaved then
        self:PersistCurrentPlanToSaved()
    end

    local who = sender and (Ambiguate and Ambiguate(sender, "short") or sender) or "Raid leader"
    local sceneNote = count > 1 and (" (%d places)"):format(count) or ""
    local classNote = parsed.icon and (" |cff9fd3ff%s|r"):format(IconKeyDisplayName(parsed.icon) or "") or ""
    print(("|cff00aaff[Raidstrats.gg]|r %s assigned |cffeadb5f%s|r to |cff00ff00%s|r%s%s."):format(
        who, parsed.oldLabel, parsed.newLabel or "", classNote, sceneNote))
end

function Diar:ApplyLabelSyncFromComm(msg, sender)
    local parsed = self:ParseLabelSyncMsg(msg)
    if not parsed or not parsed.sceneIndex or not parsed.itemIndex then return end
    if parsed.planKey ~= self:GetPlanSyncKey() then return end

    local data = self.plannerData
    if not data or not data.scenes then return end
    local scene = data.scenes[parsed.sceneIndex]
    if not scene or not scene.items then return end
    local item = scene.items[parsed.itemIndex]
    if not item then return end

    item.label = parsed.label or ""
    self:ApplyIconToPlanItem(item, parsed.icon)
    local pf = self.plannerFrame
    if pf and pf:IsShown() and (pf.selectedSceneIndex or 1) == parsed.sceneIndex then
        if self.RefreshPlannerScene then
            self:RefreshPlannerScene()
        end
    end
    if self.PersistCurrentPlanToSaved then
        self:PersistCurrentPlanToSaved()
    end

    local who = sender and (Ambiguate and Ambiguate(sender, "short") or sender) or "Raid leader"
    local classNote = parsed.icon and (" |cff9fd3ff%s|r"):format(IconKeyDisplayName(parsed.icon) or "") or ""
    print(("|cff00aaff[Raidstrats.gg]|r %s assigned |cff00ff00%s|r%s."):format(who, parsed.label or "", classNote))
end

function Diar:IsPlannerCompactMode()
    local pf = self.plannerFrame
    return pf and pf.compactMode == true
end

function Diar:BeginPlannerItemDrag(widget)
    if self:IsPlannerCompactMode() or self._plannerDrag then return end
    if Diar.CanEditPlannerItems and not Diar:CanEditPlannerItems() then return end
    local pf = self.plannerFrame
    local canvas = pf and pf.canvas
    if not widget or not canvas or not widget.itemIndex then return end
    local cw, ch = canvas:GetSize()
    if cw <= 0 or ch <= 0 then return end

    local data = self.plannerData
    local sceneIdx = pf and (pf.selectedSceneIndex or 1) or 1
    local scene = data and data.scenes and data.scenes[sceneIdx]
    local item = scene and scene.items and scene.items[widget.itemIndex] or nil
    local shapeKey = item and tostring(item.shape or ""):lower() or ""
    local liveStaticShape = (item and item.kind == "line")
        or (item and item.kind == "shape" and (shapeKey == "triangle" or shapeKey == "cone" or shapeKey == "donut"))

    self._plannerDrag = {
        widget = widget,
        itemIndex = widget.itemIndex,
        canvas = canvas,
        cw = cw,
        ch = ch,
        sceneIndex = sceneIdx,
        liveStaticShape = liveStaticShape and true or false,
        liveNextAt = 0,
    }
    widget:SetFrameLevel(canvas:GetFrameLevel() + 24)
    widget:SetScript("OnUpdate", function(w)
        Diar:UpdatePlannerItemDrag(w)
    end)
end

function Diar:UpdatePlannerItemDrag(widget)
    local drag = self._plannerDrag
    if not drag or drag.widget ~= widget then return end
    if not IsMouseButtonDown("LeftButton") then
        self:EndPlannerItemDrag(widget)
        return
    end
    local canvas = drag.canvas
    local scale = canvas:GetEffectiveScale()
    if not scale or scale <= 0 then return end
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale

    local canvasLeft = canvas:GetLeft()
    local canvasTop = canvas:GetTop()
    if not canvasLeft or not canvasTop then return end

    local w, h = widget:GetWidth(), widget:GetHeight()
    local relX = cx - canvasLeft - (w / 2)
    local relY = canvasTop - cy - (h / 2)
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", canvas, "TOPLEFT", relX, -relY)

    if drag.liveStaticShape then
        local now = GetTime() or 0
        if now < (drag.liveNextAt or 0) then
            return
        end
        drag.liveNextAt = now + (1 / CONE_LIVE_DRAG_FPS)
        local pf = self.plannerFrame
        local vc = pf and pf.sceneViewContext
        local screenToWorld = Diar.PlannerView and Diar.PlannerView.ScreenToWorld
        local sx, sy = relX, relY
        local wx, wy = sx, sy
        if screenToWorld then
            wx, wy = screenToWorld(vc, sx, sy)
        elseif vc then
            wx = (sx - vc.panX) / vc.zoom
            wy = (sy - vc.panY) / vc.zoom
        end
        local xp = math.floor((wx / drag.cw) * 10000 + 0.5) / 100
        local yp = math.floor((wy / drag.ch) * 10000 + 0.5) / 100
        self:ApplyItemPositionChange(drag.itemIndex, xp, yp, {
            skipPersist = true,
            skipBroadcast = true,
            skipRefresh = false,
        })
    end
end

function Diar:EndPlannerItemDrag(widget)
    local drag = self._plannerDrag
    if not drag or drag.widget ~= widget then return end
    widget:SetScript("OnUpdate", nil)
    self._plannerDrag = nil

    local _, _, _, xOfs, yOfs = widget:GetPoint()
    if not xOfs or not yOfs then return end

    local pf = self.plannerFrame
    local vc = pf and pf.sceneViewContext
    local screenToWorld = Diar.PlannerView and Diar.PlannerView.ScreenToWorld
    local sx, sy = xOfs, -yOfs
    local wx, wy = sx, sy
    if screenToWorld then
        wx, wy = screenToWorld(vc, sx, sy)
    elseif vc then
        wx = (sx - vc.panX) / vc.zoom
        wy = (sy - vc.panY) / vc.zoom
    end

    local xp = math.floor((wx / drag.cw) * 10000 + 0.5) / 100
    local yp = math.floor((wy / drag.ch) * 10000 + 0.5) / 100
    self:ApplyItemPositionChange(drag.itemIndex, xp, yp)
end

function Diar:BuildPositionSyncMsg(planKey, sceneIndex, itemIndex, x, y)
    return table.concat({
        "POS", planKey, tostring(sceneIndex), tostring(itemIndex),
        tostring(x), tostring(y),
    }, SEP)
end

function Diar:ParsePositionSyncMsg(msg)
    if type(msg) ~= "string" or msg:sub(1, 3) ~= "POS" then return nil end
    local parts = SplitSep(msg, SEP)
    if parts[1] ~= "POS" or #parts < 6 then return nil end
    return {
        planKey = parts[2],
        sceneIndex = tonumber(parts[3]),
        itemIndex = tonumber(parts[4]),
        x = tonumber(parts[5]),
        y = tonumber(parts[6]),
    }
end

function Diar:BroadcastItemPositionChange(sceneIndex, itemIndex, x, y)
    if not self:IsPlanLeader() then return end
    local chan = self.GetGroupChatChannel and self:GetGroupChatChannel()
    if not chan then
        return
    end
    local planKey = self:GetPlanSyncKey()
    if not planKey then return end
    local msg = self:BuildPositionSyncMsg(planKey, sceneIndex, itemIndex, x, y)
    local prefix = self.COMM_PLAN_PREFIX or "RAIDSTRATS_PLAN"
    self:SendCommMessage(prefix, msg, chan)
end

function Diar:ApplyItemPositionChange(itemIndex, xPct, yPct, opts)
    opts = opts or {}
    local pf = self.plannerFrame
    local data = self.plannerData
    if not pf or not data or not data.scenes then return end
    local sceneIdx = pf.selectedSceneIndex or 1
    local scene = data.scenes[sceneIdx]
    if not scene or not scene.items then return end
    local item = scene.items[itemIndex]
    if not item then return end

    local dx, dy = 0, 0
    if item.kind == "line" then
        local oldAX, oldAY = GetLineDragAnchor(item)
        if oldAX and oldAY then
            dx = xPct - oldAX
            dy = yPct - oldAY
            item.x1 = (tonumber(item.x1) or oldAX) + dx
            item.y1 = (tonumber(item.y1) or oldAY) + dy
            item.x2 = (tonumber(item.x2) or oldAX) + dx
            item.y2 = (tonumber(item.y2) or oldAY) + dy
        end
        item.x = nil
        item.y = nil
        item.currentX = nil
        item.currentY = nil
    else
        local oldX = tonumber(item.x) or xPct
        local oldY = tonumber(item.y) or yPct
        dx = xPct - oldX
        dy = yPct - oldY
        item.x = xPct
        item.y = yPct
        item.currentX = xPct / 100
        item.currentY = yPct / 100
    end
    if type(item.corners) == "table" and #item.corners >= 3 and (math.abs(dx) > 0.0001 or math.abs(dy) > 0.0001) then
        for _, p in ipairs(item.corners) do
            if type(p) == "table" then
                local px = tonumber(p.x)
                local py = tonumber(p.y)
                if px and py then
                    p.x = px + dx
                    p.y = py + dy
                end
            end
        end
    end

    if pf:IsShown() and self.RefreshPlannerScene and not opts.skipRefresh then
        self:RefreshPlannerScene()
    end
    if not opts.skipPersist and self.PersistCurrentPlanToSaved then
        self:PersistCurrentPlanToSaved()
    end
    if not opts.skipBroadcast then
        self:BroadcastItemPositionChange(sceneIdx, itemIndex, xPct, yPct)
    end
end

function Diar:ApplyPositionSyncFromComm(msg, sender)
    local parsed = self:ParsePositionSyncMsg(msg)
    if not parsed or not parsed.sceneIndex or not parsed.itemIndex then return end
    if parsed.planKey ~= self:GetPlanSyncKey() then return end
    if not parsed.x or not parsed.y then return end

    local data = self.plannerData
    if not data or not data.scenes then return end
    local scene = data.scenes[parsed.sceneIndex]
    if not scene or not scene.items then return end
    local item = scene.items[parsed.itemIndex]
    if not item then return end

    item.x = parsed.x
    item.y = parsed.y
    item.currentX = parsed.x / 100
    item.currentY = parsed.y / 100

    local pf = self.plannerFrame
    if pf and pf:IsShown() and (pf.selectedSceneIndex or 1) == parsed.sceneIndex then
        if self.RefreshPlannerScene then
            self:RefreshPlannerScene()
        end
    end
    if self.PersistCurrentPlanToSaved then
        self:PersistCurrentPlanToSaved()
    end
end

function Diar:AttachPlannerItemContextMenu(widget, itemIndex, item)
    if not widget or widget.__suppressed or not item then return end

    local pf = self.plannerFrame
    local palettePlacementActive = pf and pf.__palettePlacement ~= nil
    if palettePlacementActive then
        -- While placing from palette, let canvas receive clicks for placement/draw.
        widget:EnableMouse(false)
        widget:SetScript("OnMouseDown", nil)
        widget:SetScript("OnMouseUp", nil)
        return
    end

    widget:EnableMouse(true)
    widget.itemIndex = itemIndex

    if self:IsPlannerCompactMode() then
        if pf and pf.nsrtSceneActive and self.IsNsrtCompactClickThroughEnabled and self:IsNsrtCompactClickThroughEnabled() and widget.EnableMouse then
            widget:EnableMouse(false)
        end
        widget:SetScript("OnMouseDown", nil)
        widget:SetScript("OnMouseUp", nil)
        return
    end

    widget:SetScript("OnMouseDown", function(w, button)
        if button == "LeftButton" and Diar.CanEditPlannerItems and Diar:CanEditPlannerItems() then
            if not CursorInsideItemShape(w, item) then return end
            Diar:BeginPlannerItemDrag(w)
        end
    end)
    widget:SetScript("OnMouseUp", function(w, button)
        if button == "LeftButton" then
            Diar:EndPlannerItemDrag(w)
        elseif button == "RightButton" then
            if not CursorInsideItemShape(w, item) then return end
            local canAssign = Diar:CanAssignPlayerToItem(item) and Diar:IsPlanLeader()
            local canDelete = Diar.CanEditPlannerItems and Diar:CanEditPlannerItems()
            local canCustomLabel = Diar.CanEditPlannerItems and Diar:CanEditPlannerItems()
            if not canAssign and not canDelete and not canCustomLabel then return end
            if Diar.ClearPalettePlacement then
                Diar:ClearPalettePlacement()
            end
            Diar:ShowPlannerContextMenu(w, w.itemIndex, item)
        end
    end)
end
