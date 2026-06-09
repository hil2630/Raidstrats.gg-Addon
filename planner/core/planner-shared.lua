-- Raidstrats.gg Planner - shared UI helpers and layout constants
local addonName = ...
local AceAddon = LibStub("AceAddon-3.0")
local Addon =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)
if not Addon then return end
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
PUI.BRAND_TITLE_TEXT = "Raidstrats.gg - Raidplanner & Assignments"
PUI.BRAND_TITLE_OFFSET_X = 65
PUI.PLAN_TITLE_MAX_LEN = 20
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

function PUI.SkinPlannerScroll(scrollFrame)
    if SkinScrollBar then SkinScrollBar(scrollFrame) end
end

function PUI.TruncatePlannerPlanTitle(name, maxLen)
    maxLen = maxLen or PUI.PLAN_TITLE_MAX_LEN or 20
    name = strtrim(tostring(name or ""))
    if name == "" then return "Raid plan" end
    if #name <= maxLen then return name end
    if maxLen <= 3 then return name:sub(1, maxLen) end
    return name:sub(1, maxLen - 3) .. "..."
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

function PUI.GetPlayerNameKey()
    local name = UnitName("player")
    if not name or name == "" then return nil end
    local short = name:match("^([^%-]+)") or name
    return strlower(strtrim(short))
end

function PUI.LabelMatchesPlayer(label, playerKey)
    if not playerKey or not label or label == "" then return false end
    local t = strlower(strtrim(label))
    local short = t:match("^([^%-]+)") or t
    return short == playerKey or t == playerKey
end

function PUI.RosterNameMatchesPlayer(rosterName, playerKey)
    if not playerKey or not rosterName or rosterName == "" then return false end
    if PUI.LabelMatchesPlayer(rosterName, playerKey) then return true end
    local full = UnitName("player")
    if not full or full == "" then return false end
    local rosterLower = strlower(strtrim(rosterName))
    local fullLower = strlower(strtrim(full))
    if rosterLower == fullLower then return true end
    local rosterShort = rosterLower:match("^([^%-]+)") or rosterLower
    local fullShort = fullLower:match("^([^%-]+)") or fullLower
    return rosterShort == fullShort
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
