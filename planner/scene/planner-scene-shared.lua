local addonName = ...
local AceAddon = LibStub("AceAddon-3.0")
local Addon =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)
if not Addon then return end

local PUI = Addon.PlannerUI
if not PUI then return end

RIGHT_PANEL_W = PUI.RIGHT_PANEL_W
UI_PAD = PUI.UI_PAD
TITLE_TOP = PUI.TITLE_TOP
BRAND_TITLE_TEXT = PUI.BRAND_TITLE_TEXT
TruncatePlannerPlanTitle = PUI.TruncatePlannerPlanTitle
PositionPlannerBrandTitle = PUI.PositionPlannerBrandTitle
TOOLBAR_TOP = PUI.TOOLBAR_TOP
TOOLBAR_H = PUI.TOOLBAR_H
CANVAS_TOP = PUI.CANVAS_TOP
ROW_GAP = PUI.ROW_GAP
CONTROLS_H = PUI.CONTROLS_H
TIMELINE_H = PUI.TIMELINE_H
SCENE_TAB_H = PUI.SCENE_TAB_H
GROUP_LEADER_ICON = PUI.GROUP_LEADER_ICON
PATREON_BOX_H = PUI.PATREON_BOX_H
RIGHT_COL_GAP = PUI.RIGHT_COL_GAP
RIGHT_PANEL_BOTTOM_GAP = 68
UI = PUI.UI
SkinPlannerScroll = PUI.SkinPlannerScroll
SetPlannerBtnText = PUI.SetPlannerBtnText
CreatePlannerIconBtn = PUI.CreatePlannerIconBtn
HIGHLIGHT_TEXT = PUI.HIGHLIGHT_TEXT
GetPlayerNameKey = PUI.GetPlayerNameKey
LabelMatchesPlayer = PUI.LabelMatchesPlayer
SceneHasPlayerName = PUI.SceneHasPlayerName
ApplyNameHighlight = PUI.ApplyNameHighlight
ClearNameHighlight = PUI.ClearNameHighlight
CheckboxIsChecked = PUI.CheckboxIsChecked

FOOTER_BTN_H = 28
FOOTER_BTN_GAP = 8
FOOTER_HEIGHT = FOOTER_BTN_H * 2 + FOOTER_BTN_GAP
function LayoutSavedPlansFooter(pf)
    local footer = pf and pf.savedPlansFooter
    if not footer then return end
    footer:SetHeight(FOOTER_HEIGHT)

    local newBtn = pf.savedPlansNewBtn
    local importBtn = pf.savedPlansImportBtn
    local shareBtn = pf.savedPlansShareBtn
    local pushBtn = pf.pushUpdateBtn
    if not newBtn or not importBtn or not shareBtn or not pushBtn then return end

    newBtn:Show()
    newBtn:ClearAllPoints()
    newBtn:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
    newBtn:SetPoint("TOPRIGHT", footer, "TOP", -3, 0)
    newBtn:SetHeight(FOOTER_BTN_H)

    importBtn:ClearAllPoints()
    importBtn:SetPoint("TOPLEFT", footer, "TOP", 3, 0)
    importBtn:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)
    importBtn:SetHeight(FOOTER_BTN_H)

    shareBtn:ClearAllPoints()
    shareBtn:SetPoint("BOTTOMLEFT", footer, "BOTTOMLEFT", 0, 0)
    shareBtn:SetPoint("BOTTOMRIGHT", footer, "BOTTOM", -3, 0)
    shareBtn:SetHeight(FOOTER_BTN_H)

    pushBtn:ClearAllPoints()
    pushBtn:SetPoint("BOTTOMLEFT", footer, "BOTTOM", 3, 0)
    pushBtn:SetPoint("BOTTOMRIGHT", footer, "BOTTOMRIGHT", 0, 0)
    pushBtn:SetHeight(FOOTER_BTN_H)
end
