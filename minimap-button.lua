-- Minimap button: click to open the raid planner.
local addonName = ...
local AceAddon = LibStub("AceAddon-3.0")
local Addon =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)
if not Addon then return end

local MINIMAP_ICON = 1519351
local function L(key) return RSGG_L(key) end

local function GetSettings()
    RaidstratsggSettings = RaidstratsggSettings or {}
    local s = RaidstratsggSettings
    if s.minimapAngle == nil then s.minimapAngle = 220 end
    if s.minimapHidden == nil then s.minimapHidden = false end
    return s
end

local function GetMinimapOrbitRadius()
    local w = Minimap:GetWidth() or 140
    local h = Minimap:GetHeight() or 140
    if w <= 0 then w = 140 end
    if h <= 0 then h = 140 end
    -- Sit on the minimap rim (works with scaled / square minimaps too).
    return (math.min(w, h) / 2) + 2
end

local function PositionMinimapButton(btn, angle)
    angle = angle or GetSettings().minimapAngle or 220
    local rad = angle * math.pi / 180
    local radius = GetMinimapOrbitRadius()
    btn:ClearAllPoints()
    btn:SetPoint(
        "CENTER",
        Minimap,
        "CENTER",
        math.cos(rad) * radius,
        math.sin(rad) * radius
    )
end

function Addon:InitMinimapButton()
    if self.minimapBtn then
        if GetSettings().minimapHidden then
            self.minimapBtn:Hide()
        else
            self.minimapBtn:Show()
            PositionMinimapButton(self.minimapBtn, GetSettings().minimapAngle)
        end
        return
    end

    local btn = CreateFrame("Button", "RaidstratsggMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local overlay = btn:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetPoint("TOPLEFT")
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(21, 21)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture(MINIMAP_ICON)

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")

    btn:SetScript("OnClick", function(_, mouseBtn)
        if mouseBtn == "RightButton" then
            if Addon.CreateMainWindow then
                Addon:CreateMainWindow()
            end
            return
        end
        if Addon.ShowPlannerViewer then
            Addon:ShowPlannerViewer()
        end
    end)

    btn:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_LEFT")
        GameTooltip:SetText(L("Raidstrats.gg"), 1, 1, 1)
        GameTooltip:AddLine(L("Left-click: open planner"), 0.85, 0.88, 0.92)
        GameTooltip:AddLine(L("Right-click: roster export"), 0.65, 0.68, 0.72)
        GameTooltip:AddLine(L("Drag to move"), 0.55, 0.58, 0.62)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    btn:SetScript("OnDragStart", function(s)
        s:LockHighlight()
        s:SetScript("OnUpdate", function(self)
            local mx, my = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            cx, cy = cx / scale, cy / scale
            local angle = math.deg(math.atan2(cy - my, cx - mx))
            GetSettings().minimapAngle = angle
            PositionMinimapButton(self, angle)
        end)
    end)

    btn:SetScript("OnDragStop", function(s)
        s:SetScript("OnUpdate", nil)
        s:UnlockHighlight()
    end)

    self.minimapBtn = btn
    PositionMinimapButton(btn, GetSettings().minimapAngle)
    if GetSettings().minimapHidden then
        btn:Hide()
    end

    if not self._minimapSizeHooked then
        self._minimapSizeHooked = true
        Minimap:HookScript("OnSizeChanged", function()
            if Addon.minimapBtn and Addon.minimapBtn:IsShown() then
                PositionMinimapButton(Addon.minimapBtn, GetSettings().minimapAngle)
            end
        end)
    end
end
