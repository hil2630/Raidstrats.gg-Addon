-- Raidcheck panel: roster + who has the current plan open (any group member can enable).
local addonName = ...
local AceAddon = LibStub("AceAddon-3.0")
local Addon =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)
if not Addon then return end
local function L(key) return RSGG_L(key) end
local Diar = Addon

local SEP = string.char(31)
local SetBackdrop = Diar.SetBackdrop
local SkinScrollBar = Diar.SkinScrollBar
local CreateAnimatedCheckbox = Diar.CreateAnimatedCheckbox
local CreateButton = Diar.CreateButton

local PRESENCE_TTL = 45
local HEARTBEAT_INTERVAL = 15
local POLL_INTERVAL = 25
local RAID_VIEW_FRAC = 0.42
local RAID_VIEW_MIN_H = 96
local RAID_CHECK_BAR_H = 52
local RAID_NOTIF_BTN_H = 28
local ROW_H = 22
local POLL_ACK_WAIT = 4

local UI = {
    PANEL   = {0.06, 0.06, 0.09, 0.96},
    BORDER  = {0.22, 0.24, 0.28, 1},
    TOOLBAR = {0.05, 0.05, 0.08, 0.92},
    ROW     = {0.09, 0.10, 0.13, 0.92},
    ROW_HOV = {0.14, 0.16, 0.20, 1},
    ACCENT  = {0.23, 0.51, 0.96, 1},
    VIEWING = {0.35, 0.88, 0.45},
    OTHER   = {0.40, 0.68, 0.98},
    IDLE    = {0.42, 0.45, 0.50},
    LINK    = {0.45, 0.58, 0.78},
    LINK_HOV = {0.62, 0.76, 0.98},
    MISSING = {0.98, 0.62, 0.18},
    WRONGVER = {0.95, 0.72, 0.28},
    NOADDON = {0.92, 0.28, 0.28},
}

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

local function PlayerNameKey(name)
    name = strtrim(tostring(name or ""))
    if name == "" then return nil end
    local short = name:match("^([^%-]+)") or name
    return strlower(short)
end

local function SanitizeCommField(value)
    return tostring(value or ""):gsub(SEP, "")
end

local function GetClassColor(classFile)
    if not classFile or classFile == "" then return 0.82, 0.82, 0.82 end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c then return c.r, c.g, c.b end
    return 0.82, 0.82, 0.82
end

function Diar:HideRaidCheckMemberContextDismissOverlay()
    local o = self._raidCheckMemberCtxDismiss
    if not o then return end
    o:Hide()
    o:SetScript("OnClick", nil)
    o:SetScript("OnMouseUp", nil)
end

function Diar:HideRaidCheckMemberContextMenu()
    self:HideRaidCheckMemberContextDismissOverlay()
    local menu = self._raidCheckMemberCtxMenu
    if menu then
        menu:Hide()
    end
    if self._readyCheckRaidCheckCtxMenu then
        self._readyCheckRaidCheckCtxMenu:Hide()
    end
end

function Diar:ShowRaidCheckMemberContextMenu(anchor, memberName)
    memberName = strtrim(tostring(memberName or ""))
    if memberName == "" then return end
    self:HideRaidCheckMemberContextMenu()

    local menu = self._raidCheckMemberCtxMenu
    if not menu then
        menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        menu:SetSize(152, 40)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(540)
        menu:EnableMouse(true)
        if SetBackdrop then SetBackdrop(menu, UI.PANEL, UI.BORDER, 1) end

        local notifBtn = CreateFrame("Button", nil, menu, "BackdropTemplate")
        notifBtn:SetPoint("TOPLEFT", menu, "TOPLEFT", 6, -6)
        notifBtn:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -6, 6)
        if SetBackdrop then SetBackdrop(notifBtn, UI.ROW, UI.BORDER, 1) end
        local lbl = notifBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("CENTER")
        lbl:SetText(L("Send notif"))
        lbl:SetTextColor(0.92, 0.92, 0.92)
        notifBtn:SetScript("OnEnter", function(s)
            s:SetBackdropColor(unpack(UI.ROW_HOV))
            lbl:SetTextColor(1, 1, 1)
        end)
        notifBtn:SetScript("OnLeave", function(s)
            s:SetBackdropColor(unpack(UI.ROW))
            lbl:SetTextColor(0.92, 0.92, 0.92)
        end)
        notifBtn:SetScript("OnClick", function()
            local target = strtrim(tostring(menu and menu.memberName or ""))
            Diar:HideRaidCheckMemberContextMenu()
            if target ~= "" and Diar.SendRaidCheckNotifToMember then
                Diar:SendRaidCheckNotifToMember(target)
            end
        end)

        menu:SetScript("OnHide", function()
            Diar:HideRaidCheckMemberContextDismissOverlay()
        end)
        self._raidCheckMemberCtxMenu = menu
    end

    menu.memberName = memberName
    menu:ClearAllPoints()
    if anchor then
        menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    else
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    end
    menu:Show()
    if menu.Raise then menu:Raise() end

    if not self._raidCheckMemberCtxDismiss then
        local o = CreateFrame("Button", "RaidstratsRaidCheckMemberCtxDismiss", UIParent)
        o:SetAllPoints(UIParent)
        o:SetFrameStrata("FULLSCREEN_DIALOG")
        o:EnableMouse(true)
        o:SetAlpha(0.001)
        self._raidCheckMemberCtxDismiss = o
    end
    local dismiss = self._raidCheckMemberCtxDismiss
    dismiss:SetFrameLevel(math.max(0, (menu:GetFrameLevel() or 0) - 1))
    dismiss:SetScript("OnClick", nil)
    dismiss:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" or button == "RightButton" then
            Diar:HideRaidCheckMemberContextMenu()
        end
    end)
    dismiss:Show()
end

function Diar:ShouldShowRaidCheckBar()
    if IsInGroup() then return true end
    return self.IsRsggDebug and self:IsRsggDebug()
end

function Diar:IsRaidCheckEnabled(pf)
    pf = pf or self.plannerFrame
    return pf and pf.raidCheckEnabled == true
end

function Diar:SetRaidCheckEnabled(pf, enabled)
    pf = pf or self.plannerFrame
    if not pf then return end
    enabled = not not enabled
    pf.raidCheckEnabled = enabled
    if pf.raidCheckChk then
        pf.raidCheckChk:SetChecked(enabled)
    end
    if pf.raidCheckRefreshBtn then
        if enabled then pf.raidCheckRefreshBtn:Show() else pf.raidCheckRefreshBtn:Hide() end
    end
    if pf.raidCheckSummary then
        if enabled then pf.raidCheckSummary:Show() else pf.raidCheckSummary:Hide() end
    end
    if self.ApplyRaidLeadViewLayout then
        self:ApplyRaidLeadViewLayout(pf)
    end
    if not enabled and self.SetRaidCheckAutoSwitchEnabled then
        self:SetRaidCheckAutoSwitchEnabled(pf, false)
    end
    if enabled then
        self:SendPlanViewPoll()
        self:EnsurePlanViewPollTimer()
    end
end

local function NormalizeBoundPlanRef(ref)
    if type(ref) ~= "string" then return nil end
    local raw = strtrim(ref)
    if raw == "" then return nil end
    local view = raw:match("[?&]view=([^&#]+)")
    if view and view ~= "" then raw = view end
    local idOnly = raw:match("^([^/]+)/%d+$")
    if idOnly and idOnly ~= "" then raw = idOnly end
    return (raw ~= "" and raw) or nil
end

local function FindSavedPlanDataByPlanId(planId)
    planId = tostring(planId or "")
    if planId == "" then return nil end
    if Diar.PlanDataMatchesPlanId and Diar:PlanDataMatchesPlanId(Diar.plannerData, planId) then
        return Diar.plannerData
    end
    RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {} }
    for _, entry in ipairs(RaidstratsggSavedPlans.list or {}) do
        if entry and entry.data and Diar.PlanDataMatchesPlanId and Diar:PlanDataMatchesPlanId(entry.data, planId) then
            return entry.data
        end
    end
    return nil
end

-- Plans currently used by the loaded NSRT note (unique rsgg-bind refs).
-- opts.reload: when true, reload cues/binds from the active NSRT note first.
function Diar:CollectReadyCheckRequiredPlans(opts)
    opts = opts or {}
    if opts.reload and self.ReloadRsggCuesFromActiveNote then
        self:ReloadRsggCuesFromActiveNote()
    end

    local out = {}
    local seen = {}
    local function addPlan(planId, planKey, planName, data, alias)
        planId = planId and tostring(planId) or ""
        planKey = planKey and tostring(planKey) or ""
        if planId == "" and planKey == "" then return end
        local sk = (planKey ~= "" and ("k:" .. planKey)) or ("id:" .. planId)
        if seen[sk] then return end
        seen[sk] = true
        out[#out + 1] = {
            planId = planId,
            planKey = planKey,
            planName = (planName and planName ~= "" and planName)
                or (alias and alias ~= "" and alias)
        or L("Raid plan"),
            data = data,
            alias = alias,
        }
    end

    local binds = self.rsggPlanBinds
    if type(binds) == "table" then
        for alias, ref in pairs(binds) do
            local planId = NormalizeBoundPlanRef(ref)
            if planId then
                local data = FindSavedPlanDataByPlanId(planId)
                local planKey = ""
                local planName = nil
                if data then
                    if self.EnsurePlanInstanceKey then self:EnsurePlanInstanceKey(data) end
                    -- Commit a new sync version only if content changed since last stamp.
                    -- Readycheck then compares raiders against this version (edits alone don't bump).
                    if self.EnsurePlanSyncVersionMatchesContent then
                        self:EnsurePlanSyncVersionMatchesContent(data)
                    end
                    planKey = (self.GetPlanIdentityKey and self:GetPlanIdentityKey(data)) or ""
                    planName = data.planName
                end
                addPlan(planId, planKey, planName, data, tostring(alias or ""))
            end
        end
    end

    table.sort(out, function(a, b)
        return tostring(a.planName or ""):lower() < tostring(b.planName or ""):lower()
    end)
    self._readyCheckRequiredPlans = out
    return out
end

function Diar:GetReadyCheckRequiredPlans()
    local plans = self._readyCheckRequiredPlans
    if type(plans) == "table" and #plans > 0 then
        return plans
    end
    return self:CollectReadyCheckRequiredPlans({ reload = true })
end

-- Every note-bound plan the leader/sender has saved locally (full note set).
function Diar:GetSendableReadyCheckNotePlans(opts)
    opts = opts or {}
    local plans = self:CollectReadyCheckRequiredPlans({ reload = opts.reload == true })
    if type(plans) ~= "table" or #plans == 0 then
        plans = self:CollectReadyCheckRequiredPlans({ reload = true })
    end
    local out = {}
    local seen = {}
    for _, plan in ipairs(plans or {}) do
        local data = plan.data
        if (not data or not data.scenes or #data.scenes == 0) and plan.planId and plan.planId ~= "" then
            data = FindSavedPlanDataByPlanId(plan.planId)
        end
        if data and data.scenes and #data.scenes > 0 then
            local planId = tostring(plan.planId or data.planId or "")
            local planKey = plan.planKey or (self.GetPlanIdentityKey and self:GetPlanIdentityKey(data)) or ""
            local sk = (planId ~= "" and ("id:" .. planId))
                or ((planKey ~= "" and ("k:" .. planKey)) or nil)
            if sk and not seen[sk] then
                seen[sk] = true
                out[#out + 1] = {
                    data = data,
                    planKey = planKey,
                    planId = planId,
                    planName = plan.planName or data.planName or plan.alias or "Raid plan",
                    alias = plan.alias,
                }
            end
        end
    end
    return out
end

function Diar:EnsurePlanLoadedForReadyCheckRaidCheck()
    -- Prefer already-loaded binds (assignments usually reloaded the note first).
    local plans = self:CollectReadyCheckRequiredPlans({ reload = false })
    if type(plans) == "table" and #plans > 0 then
        return true
    end
    plans = self:CollectReadyCheckRequiredPlans({ reload = true })
    return type(plans) == "table" and #plans > 0
end

local function ConfirmReadyCheckNotReady()
    if C_PartyInfo and C_PartyInfo.ConfirmReadyCheck then
        C_PartyInfo.ConfirmReadyCheck(false)
        return true
    end
    if ConfirmReadyCheck then
        ConfirmReadyCheck(nil)
        return true
    end
    return false
end

-- Ask the raid leader to whisper-send every note-bound plan (RNOT import popup).
function Diar:RequestMissingReadyCheckPlans(_ignored)
    -- Always request the full note plan set (every rsgg-bind), not assigned/missing only.
    local plans = self:CollectReadyCheckRequiredPlans({ reload = true })
    if type(plans) ~= "table" or #plans == 0 then
        return false
    end
    if not IsInGroup() then
        return false
    end
    -- Leader missing plans can't import from themselves via this path.
    if UnitIsGroupLeader("player") then
        return false
    end

    local parts = { "RCMI" }
    local any = false
    for _, plan in ipairs(plans) do
        local planKey = SanitizeCommField(plan.planKey)
        local planId = SanitizeCommField(plan.planId)
        local planName = SanitizeCommField(plan.planName or plan.alias)
        if planKey ~= "" or planId ~= "" then
            parts[#parts + 1] = planKey
            parts[#parts + 1] = planId
            parts[#parts + 1] = planName
            any = true
        end
    end
    if not any then
        return false
    end

    local chan = self.GetGroupChatChannel and self:GetGroupChatChannel()
    if not chan then
        return false
    end
    local prefix = self.COMM_PLAN_PREFIX or "RAIDSTRATS_PLAN"
    self:SendCommMessage(prefix, table.concat(parts, SEP), chan)
    return true
end

-- Leader: auto-send every note-bound plan so the player can import the full set.
function Diar:HandleRaidCheckMissingPlansComm(msg, sender)
    if type(msg) ~= "string" or msg:sub(1, 4) ~= "RCMI" then return end
    if not self:CanSendRaidCheckNotif() then return end

    local senderKey = PlayerNameKey(sender and (Ambiguate and Ambiguate(sender, "short") or sender) or sender)
    local myKey = PlayerNameKey(UnitName("player"))
    if not senderKey or (myKey and senderKey == myKey) then return end

    self._rcmiLastSendAt = self._rcmiLastSendAt or {}
    local now = GetTime()
    if self._rcmiLastSendAt[senderKey] and (now - self._rcmiLastSendAt[senderKey]) < 20 then
        return
    end
    self._rcmiLastSendAt[senderKey] = now

    local parts = SplitSep(msg, SEP)
    if parts[1] ~= "RCMI" then return end

    -- Always send the full note plan set (every rsgg-bind), not only requested/assigned ones.
    local sendable = self:GetSendableReadyCheckNotePlans({ reload = true })
    if #sendable == 0 then
        print(L("|cffff9900[Raidstrats.gg]|r %s needs the note plans, but you don't have them saved locally to send."):format(
            Ambiguate and Ambiguate(sender, "short") or sender))
        return
    end

    self:MarkReadyCheckAutoSent(senderKey)
    if self:SendReadyCheckNotePlansBundleToMember(sender, sendable) then
    print(L("|cff00aaff[Raidstrats.gg]|r Sent all %d note plan%s to %s. One import popup on their end."):format(
            #sendable,
            #sendable == 1 and "" or "s",
            Ambiguate and Ambiguate(sender, "short") or sender))
    end
    if self:IsReadyCheckRaidCheckPanelActive() and self.RefreshReadyCheckRaidCheckPanel then
        self:RefreshReadyCheckRaidCheckPanel()
    end
end

function Diar:MarkReadyCheckAutoSent(memberKey)
    memberKey = PlayerNameKey(memberKey)
    if not memberKey then return end
    self._readyCheckAutoSent = self._readyCheckAutoSent or {}
    self._readyCheckAutoSent[memberKey] = GetTime()
end

function Diar:WasReadyCheckAutoSent(memberName)
    local key = PlayerNameKey(memberName)
    if not key then return false end
    local at = self._readyCheckAutoSent and self._readyCheckAutoSent[key]
    if not at then return false end
    -- Keep the marker for this readycheck window session.
    return true
end

function Diar:ClearReadyCheckAutoSent()
    self._readyCheckAutoSent = nil
end

-- Each client can only set its own readycheck response. If this player is missing
-- any note-bound plan, auto-answer Not Ready (setting, on by default).
function Diar:MaybeAutoNotReadyForMissingPlans()
    if not self.IsReadyCheckAutoNotReadyMissingEnabled or not self:IsReadyCheckAutoNotReadyMissingEnabled() then
        return false
    end
    if not IsInGroup() then
        return false
    end

    local plans = self:CollectReadyCheckRequiredPlans({ reload = true })
    if type(plans) ~= "table" or #plans == 0 then
        return false
    end

    local missingPlans = {}
    local missingNames = {}
    for _, plan in ipairs(plans) do
        if not self:PlayerHasPlanKey(plan.planKey, plan.planId) then
            missingPlans[#missingPlans + 1] = plan
            missingNames[#missingNames + 1] = plan.planName or plan.alias or plan.planId or "plan"
        end
    end
    if #missingPlans == 0 then
        return false
    end

    local function doConfirm()
        if ConfirmReadyCheckNotReady() then
        print(L("|cffff9900[Raidstrats.gg]|r Clicked Not Ready for you. You're missing %d plan%s: %s"):format(
                #missingNames,
                #missingNames == 1 and "" or "s",
                table.concat(missingNames, ", ")
            ))
            if self.RequestMissingReadyCheckPlans then
                -- Request the full note plan set, not only the ones this player is assigned to.
                if self:RequestMissingReadyCheckPlans(plans) then
        print(L("|cff00aaff[Raidstrats.gg]|r Asked the raid lead for the note plans. Hit import when they pop up."))
                end
            end
        end
    end

    -- Small delay so we still win if another addon auto-answers Ready.
    if C_Timer and C_Timer.After then
        C_Timer.After(0.35, doConfirm)
    else
        doConfirm()
    end
    return true
end

function Diar:IsReadyCheckRaidCheckPanelActive()
    return self._readyCheckRaidCheckActive == true
        and self.readyCheckRaidCheckFrame
        and self.readyCheckRaidCheckFrame:IsShown()
end

local function EnsureReadyCheckRaidCheckSendAllBtn(f)
    if not f or f.sendAllBtn then return f and f.sendAllBtn or nil end
    local btn = CreateFrame("Button", nil, f, "BackdropTemplate")
    btn:SetHeight(24)
    btn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 8)
    btn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
    if SetBackdrop then SetBackdrop(btn, UI.ROW, UI.BORDER, 1) end
    local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("CENTER")
        lbl:SetText(L("Send to all missing"))
    lbl:SetTextColor(0.92, 0.92, 0.92)
    btn.label = lbl
    btn:SetScript("OnEnter", function(s)
        s:SetBackdropColor(unpack(UI.ROW_HOV))
        lbl:SetTextColor(1, 1, 1)
    end)
    btn:SetScript("OnLeave", function(s)
        s:SetBackdropColor(unpack(UI.ROW))
        lbl:SetTextColor(0.92, 0.92, 0.92)
    end)
    btn:SetScript("OnClick", function()
        if Diar.SendReadyCheckMissingPlansToAll then
            Diar:SendReadyCheckMissingPlansToAll()
        end
    end)
    f.sendAllBtn = btn
    return btn
end

function Diar:EnsureReadyCheckRaidCheckPanel()
    local f = self.readyCheckRaidCheckFrame
    if f then
        EnsureReadyCheckRaidCheckSendAllBtn(f)
        if f.listBox then
            f.listBox:ClearAllPoints()
            f.listBox:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -34)
            f.listBox:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 36)
        end
        return f
    end

    f = CreateFrame("Frame", "RaidstratsReadyCheckRaidCheck", UIParent, "BackdropTemplate")
    f:SetSize(248, 300)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(120)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    if SetBackdrop then SetBackdrop(f, UI.PANEL, UI.BORDER, 1) end
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
        title:SetText(L("Raidcheck"))
    title:SetTextColor(0.92, 0.94, 0.98)
    f.title = title

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function()
        Diar:CloseReadyCheckRaidCheckPanel()
    end)
    f.closeBtn = closeBtn

    local refreshBtn = CreateFrame("Button", nil, f)
    refreshBtn:SetSize(52, 20)
    refreshBtn:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", -2, -6)
    local refreshLbl = refreshBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    refreshLbl:SetPoint("CENTER")
    refreshLbl:SetText(L("Refresh"))
    refreshLbl:SetTextColor(unpack(UI.LINK))
    refreshBtn:SetScript("OnEnter", function()
        refreshLbl:SetTextColor(unpack(UI.LINK_HOV))
    end)
    refreshBtn:SetScript("OnLeave", function()
        refreshLbl:SetTextColor(unpack(UI.LINK))
    end)
    refreshBtn:SetScript("OnClick", function()
        if Diar.SendReadyCheckRequiredPlanPolls then
            Diar:SendReadyCheckRequiredPlanPolls()
        else
            Diar:SendPlanViewPoll()
        end
        Diar:RefreshReadyCheckRaidCheckPanel()
    end)
    f.refreshBtn = refreshBtn

    local summary = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("RIGHT", refreshBtn, "LEFT", -8, 0)
    summary:SetPoint("LEFT", title, "RIGHT", 8, 0)
    summary:SetJustifyH("RIGHT")
    summary:SetTextColor(0.48, 0.52, 0.58)
    summary:SetText("")
    f.summary = summary

    local drag = CreateFrame("Frame", nil, f)
    drag:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", refreshBtn, "TOPLEFT", -4, 6)
    drag:SetHeight(28)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function()
        f:StartMoving()
    end)
    drag:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        f._userMoved = true
    end)

    EnsureReadyCheckRaidCheckSendAllBtn(f)

    local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
    if SetBackdrop then SetBackdrop(box, UI.TOOLBAR, UI.BORDER, 1) end
    box:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -34)
    box:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 36)
    f.listBox = box

    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -6, 6)
    if SkinScrollBar then SkinScrollBar(scroll) end
    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetWidth(220)
    scrollChild:SetHeight(1)
    scroll:SetScrollChild(scrollChild)
    f.scroll = scroll
    f.scrollChild = scrollChild
    f.rows = {}

    self.readyCheckRaidCheckFrame = f
    return f
end

function Diar:LayoutReadyCheckRaidCheckPanel()
    local f = self.readyCheckRaidCheckFrame
    if not f or not f:IsShown() then return end
    if f._userMoved then return end

    local screenH = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 768
    local h = math.max(280, math.min(520, math.floor(screenH * 0.55 + 0.5)))
    f:SetWidth(248)
    f:SetHeight(h)
    f:ClearAllPoints()
    -- Pin toward the right side of the screen, inset so it isn't flush to the edge.
    f:SetPoint("RIGHT", UIParent, "RIGHT", -80, 0)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(120)
end

function Diar:CancelReadyCheckRaidCheckCloseTimer()
    if self._readyCheckRaidCheckCloseTimer then
        self._readyCheckRaidCheckCloseTimer:Cancel()
        self._readyCheckRaidCheckCloseTimer = nil
    end
end

function Diar:CloseReadyCheckRaidCheckPanel()
    self._readyCheckRaidCheckActive = nil
    self._readyCheckRequiredPlans = nil
    self:ClearReadyCheckAutoSent()
    self:CancelReadyCheckRaidCheckCloseTimer()
    if self._readyCheckRaidCheckLayoutTimer then
        self._readyCheckRaidCheckLayoutTimer:Cancel()
        self._readyCheckRaidCheckLayoutTimer = nil
    end
    if self._readyCheckRequiredPollTimer then
        self._readyCheckRequiredPollTimer:Cancel()
        self._readyCheckRequiredPollTimer = nil
    end
    local f = self.readyCheckRaidCheckFrame
    if f then
        f._userMoved = nil
        f:Hide()
    end
end

-- Keep the side raidcheck open after readycheck ends (or until closed).
local READYCHECK_RAIDCHECK_CLOSE_SECONDS = 30

function Diar:ScheduleCloseReadyCheckRaidCheckPanel()
    if not self:IsReadyCheckRaidCheckPanelActive() then
        return
    end
    self:CancelReadyCheckRaidCheckCloseTimer()
    if not C_Timer or not C_Timer.NewTimer then
        self:CloseReadyCheckRaidCheckPanel()
        return
    end
    self._readyCheckRaidCheckCloseTimer = C_Timer.NewTimer(READYCHECK_RAIDCHECK_CLOSE_SECONDS, function()
        Diar._readyCheckRaidCheckCloseTimer = nil
        if Diar._readyCheckRaidCheckActive then
            Diar:CloseReadyCheckRaidCheckPanel()
        end
    end)
end

-- Raid leaders: show a detached raidcheck roster beside readycheck (does not open the planner).
function Diar:OpenRaidCheckForReadyCheck()
    if not self.CanOpenReadyCheckRaidCheckAsLeader or not self:CanOpenReadyCheckRaidCheckAsLeader() then
        return false
    end
    if not self:EnsurePlanLoadedForReadyCheckRaidCheck() then
        print(L("|cffff9900[Raidstrats.gg]|r No plan binds in the loaded NSRT note, so raidcheck has nothing to check."))
        return false
    end

    self:CancelReadyCheckRaidCheckCloseTimer()
    self:ClearReadyCheckAutoSent()
    self._readyCheckRaidCheckActive = true
    local f = self:EnsureReadyCheckRaidCheckPanel()
    f._userMoved = nil
    f:Show()
    self:LayoutReadyCheckRaidCheckPanel()
    if self.SendReadyCheckRequiredPlanPolls then
        self:SendReadyCheckRequiredPlanPolls()
    else
        self:SendPlanViewPoll()
    end
    self:EnsurePlanViewPollTimer()
    self:RefreshReadyCheckRaidCheckPanel()

    -- Assignments may open a moment later; keep re-anchoring briefly to sit on their right.
    if self._readyCheckRaidCheckLayoutTimer then
        self._readyCheckRaidCheckLayoutTimer:Cancel()
        self._readyCheckRaidCheckLayoutTimer = nil
    end
    if C_Timer and C_Timer.NewTicker then
        local ticks = 0
        self._readyCheckRaidCheckLayoutTimer = C_Timer.NewTicker(0.35, function(ticker)
            ticks = ticks + 1
            if not Diar._readyCheckRaidCheckActive then
                ticker:Cancel()
                Diar._readyCheckRaidCheckLayoutTimer = nil
                return
            end
            Diar:LayoutReadyCheckRaidCheckPanel()
            if ticks >= 12 then
                ticker:Cancel()
                Diar._readyCheckRaidCheckLayoutTimer = nil
            end
        end)
    end
    return true
end

function Diar:IsRaidLeadViewActive()
    -- Planner-side raidcheck only. The readycheck side panel is separate and must
    -- not make this true, or compact readycheck assignments can get expanded chrome.
    if not self:ShouldShowRaidCheckBar() then return false end
    if not self:IsRaidCheckEnabled() then return false end
    local pf = self.plannerFrame
    if pf and pf.compactMode then return false end
    return true
end

function Diar:GetCurrentPlanPresenceKey()
    local data = self.plannerData
    if not data then return nil end
    if self.GetPlanIdentityKey then
        local key = self:GetPlanIdentityKey(data)
        if key then return key end
    end
    if self.GetPlanSyncKey then
        return self:GetPlanSyncKey()
    end
    return nil
end

function Diar:GetPlanViewPresenceSnapshot()
    self._planViewPresence = self._planViewPresence or {}
    local now = GetTime()
    local out = {}
    for key, entry in pairs(self._planViewPresence) do
        if entry and (now - (entry.t or 0)) <= PRESENCE_TTL then
            out[key] = entry
        else
            self._planViewPresence[key] = nil
        end
    end
    return out
end

function Diar:PlayerHasPlanKey(planKey, planId)
    if not self.ReceiverHasMatchingPlan then return false end
    planId = planId and tostring(planId) or ""
    if planKey and planKey ~= "" then
        return self:ReceiverHasMatchingPlan(planKey, { planId = planId, channel = "RAID" })
    end
    if planId ~= "" then
        return self:ReceiverHasMatchingPlan(nil, { planId = planId, channel = "RAID" })
    end
    return false
end

-- Local sync version for a polled target plan (by identity key and/or plan id).
function Diar:GetLocalPlanSyncVersionForTarget(planKey, planId)
    if not self.GetPlanSyncVersion then return nil end
    planKey = planKey and tostring(planKey) or ""
    planId = planId and tostring(planId) or ""
    if planKey ~= "" then
        local v = self:GetPlanSyncVersion(planKey)
        if v then return tonumber(v) end
    end
    if planId ~= "" then
        local data = FindSavedPlanDataByPlanId(planId)
        if data then
            if self.EnsurePlanInstanceKey then self:EnsurePlanInstanceKey(data) end
            local key = (self.GetPlanIdentityKey and self:GetPlanIdentityKey(data)) or ""
            if key ~= "" then
                return tonumber(self:GetPlanSyncVersion(key))
            end
        end
    end
    return nil
end

function Diar:GetCurrentPlanId()
    local data = self.plannerData
    if not data or not data.planId then return "" end
    return tostring(data.planId)
end

function Diar:SetPlanViewPresence(sender, open, activePlanKey, hasPlan, targetPlanKey, activeSceneIndex, targetPlanId, planVersion)
    local key = PlayerNameKey(sender and (Ambiguate and Ambiguate(sender, "short") or sender) or sender)
    if not key then return end
    self._planViewPresence = self._planViewPresence or {}
    local existing = self._planViewPresence[key] or {}
    existing.open = open and true or false
    existing.activePlanKey = activePlanKey or ""
    local versionNum = tonumber(planVersion)
    if hasPlan ~= nil then
        existing.hasPlan = hasPlan and true or false
        existing.hasPlanByKey = existing.hasPlanByKey or {}
        existing.hasPlanById = existing.hasPlanById or {}
        existing.planVersionByKey = existing.planVersionByKey or {}
        existing.planVersionById = existing.planVersionById or {}
        if targetPlanKey and targetPlanKey ~= "" then
            existing.hasPlanByKey[targetPlanKey] = hasPlan and true or false
            if hasPlan then
                existing.planVersionByKey[targetPlanKey] = versionNum
            else
                existing.planVersionByKey[targetPlanKey] = nil
            end
        end
        targetPlanId = targetPlanId and tostring(targetPlanId) or ""
        if targetPlanId ~= "" then
            existing.hasPlanById[targetPlanId] = hasPlan and true or false
            if hasPlan then
                existing.planVersionById[targetPlanId] = versionNum
            else
                existing.planVersionById[targetPlanId] = nil
            end
        end
    end
    if targetPlanKey and targetPlanKey ~= "" then
        existing.targetPlanKey = targetPlanKey
    end
    if targetPlanId and tostring(targetPlanId) ~= "" then
        existing.targetPlanId = tostring(targetPlanId)
    end
    if open and activeSceneIndex ~= nil then
        local idx = tonumber(activeSceneIndex)
        if idx and idx >= 1 then
            existing.activeSceneIndex = math.floor(idx + 0.0001)
        end
    elseif not open then
        existing.activeSceneIndex = nil
    end
    existing.t = GetTime()
    self._planViewPresence[key] = existing
end

function Diar:SetPlanViewAutoSwitchState(sender, planKey, approved)
    local key = PlayerNameKey(sender and (Ambiguate and Ambiguate(sender, "short") or sender) or sender)
    if not key then return end
    self._planViewPresence = self._planViewPresence or {}
    local existing = self._planViewPresence[key] or {}
    existing.autoSwitchPlanKey = planKey or ""
    existing.autoSwitchApproved = approved and true or false
    existing.autoSwitchAt = GetTime()
    self._planViewPresence[key] = existing
end

function Diar:BuildPlanViewMsg(open, targetPlanKey, planId)
    targetPlanKey = targetPlanKey or ""
    planId = planId and tostring(planId) or ""
    local activeKey = ""
    local sceneIndex = ""
    local pf = self.plannerFrame
    if open and pf and pf:IsShown() then
        activeKey = self:GetCurrentPlanPresenceKey() or ""
        sceneIndex = tostring(math.max(1, math.floor(tonumber(pf.selectedSceneIndex) or 1)))
    end
    local hasPlan = self:PlayerHasPlanKey(targetPlanKey, planId)
    local syncVer = ""
    if hasPlan then
        local v = self:GetLocalPlanSyncVersionForTarget(targetPlanKey, planId)
        if v then syncVer = tostring(v) end
    end
    return table.concat({
        "VIEW",
        open and "1" or "0",
        SanitizeCommField(activeKey),
        hasPlan and "1" or "0",
        SanitizeCommField(targetPlanKey),
        SanitizeCommField(sceneIndex),
        SanitizeCommField(planId),
        SanitizeCommField(syncVer),
    }, SEP)
end

function Diar:BroadcastPlanViewStatus(open, targetPlanKey, planId)
    if not IsInGroup() then return end
    local chan = self.GetGroupChatChannel and self:GetGroupChatChannel()
    if not chan then return end
    local prefix = self.COMM_PLAN_PREFIX or "RAIDSTRATS_PLAN"
    local msg = self:BuildPlanViewMsg(open, targetPlanKey, planId)
    self:SendCommMessage(prefix, msg, chan)
end

function Diar:BroadcastPlanViewPresence(open)
    local target = self._lastViewTargetKey
    local planId = self._lastViewTargetPlanId or ""
    local at = self._lastViewTargetAt
    if target and at and (GetTime() - at) <= PRESENCE_TTL then
        self:BroadcastPlanViewStatus(open, target, planId)
        return
    end
    local key = self:GetCurrentPlanPresenceKey() or ""
    self:BroadcastPlanViewStatus(open, key, self:GetCurrentPlanId())
end

function Diar:HandlePlanViewComm(msg, sender)
    if type(msg) ~= "string" or msg:sub(1, 4) ~= "VIEW" then return end
    local parts = SplitSep(msg, SEP)
    if parts[1] ~= "VIEW" then return end
    local open = parts[2] == "1"
    local sceneIdx = #parts >= 6 and tonumber(parts[6]) or nil
    local targetPlanId = #parts >= 7 and parts[7] or ""
    local planVersion = #parts >= 8 and parts[8] or nil
    if #parts >= 5 then
        self:SetPlanViewPresence(sender, open, parts[3] or "", parts[4] == "1", parts[5] or "", sceneIdx, targetPlanId, planVersion)
    else
        self:SetPlanViewPresence(sender, open, parts[3] or "", nil, "", sceneIdx, targetPlanId, planVersion)
    end
    local pf = self.plannerFrame
    if pf and pf:IsShown() and self.UpdateSceneTabHighlight then
        self:UpdateSceneTabHighlight()
    end
    if self:IsReadyCheckRaidCheckPanelActive() and self.RefreshReadyCheckRaidCheckPanel then
        self:RefreshReadyCheckRaidCheckPanel()
    elseif self:IsRaidLeadViewActive() then
        if pf and pf:IsShown() and self.RefreshRaidLeadView then
            self:RefreshRaidLeadView(pf)
        end
    end
end

function Diar:HandlePlanViewPoll(msg, sender)
    if type(msg) ~= "string" or msg:sub(1, 4) ~= "PRRQ" then return end
    local parts = SplitSep(msg, SEP)
    local wantKey = parts[2] or ""
    local wantPlanId = parts[3] or ""
    self._lastViewTargetKey = wantKey
    self._lastViewTargetPlanId = wantPlanId
    self._lastViewTargetAt = GetTime()
    local pf = self.plannerFrame
    local open = pf and pf:IsShown() or false
    self:BroadcastPlanViewStatus(open, wantKey, wantPlanId)
end

function Diar:ScheduleRaidCheckPollRefresh(extraDelay)
    if not C_Timer or not C_Timer.NewTimer then return end
    if self._planViewAckTimer then
        self._planViewAckTimer:Cancel()
        self._planViewAckTimer = nil
    end
    local delay = POLL_ACK_WAIT + 0.1 + (tonumber(extraDelay) or 0)
    self._planViewAckTimer = C_Timer.NewTimer(delay, function()
        Diar._planViewAckTimer = nil
        if Diar:IsReadyCheckRaidCheckPanelActive() and Diar.RefreshReadyCheckRaidCheckPanel then
            Diar:RefreshReadyCheckRaidCheckPanel()
            return
        end
        local pf = Diar.plannerFrame
        if pf and pf:IsShown() and Diar:IsRaidLeadViewActive() and Diar.RefreshRaidLeadView then
            Diar:RefreshRaidLeadView(pf)
        end
    end)
end

function Diar:SendPlanViewPollFor(planKey, planId)
    if not IsInGroup() then return end
    local chan = self.GetGroupChatChannel and self:GetGroupChatChannel()
    if not chan then return end
    local prefix = self.COMM_PLAN_PREFIX or "RAIDSTRATS_PLAN"
    planKey = SanitizeCommField(planKey)
    planId = SanitizeCommField(planId)
    self._lastViewTargetKey = planKey or ""
    self._lastViewTargetPlanId = planId or ""
    self._lastViewTargetAt = GetTime()
    self._planViewPollAt = GetTime()
    self:SendCommMessage(prefix, table.concat({ "PRRQ", planKey, planId }, SEP), chan)
end

function Diar:SendReadyCheckRequiredPlanPolls()
    if not IsInGroup() then return end
    local plans = self:GetReadyCheckRequiredPlans()
    if type(plans) ~= "table" or #plans == 0 then
        self:SendPlanViewPoll()
        return
    end
    if self._readyCheckRequiredPollTimer then
        self._readyCheckRequiredPollTimer:Cancel()
        self._readyCheckRequiredPollTimer = nil
    end

    local stagger = 0.35
    for i, plan in ipairs(plans) do
        local planKey = plan.planKey or ""
        local planId = plan.planId or ""
        local delay = (i - 1) * stagger
        if delay <= 0 then
            self:SendPlanViewPollFor(planKey, planId)
        elseif C_Timer and C_Timer.After then
            C_Timer.After(delay, function()
                if Diar._readyCheckRaidCheckActive then
                    Diar:SendPlanViewPollFor(planKey, planId)
                end
            end)
        else
            self:SendPlanViewPollFor(planKey, planId)
        end
    end
    self:ScheduleRaidCheckPollRefresh((#plans - 1) * stagger)
    self:EnsurePlanViewPollTimer()
end

function Diar:SendPlanViewPoll()
    if self:IsReadyCheckRaidCheckPanelActive() and self.SendReadyCheckRequiredPlanPolls then
        self:SendReadyCheckRequiredPlanPolls()
        return
    end
    if not IsInGroup() then return end
    local chan = self.GetGroupChatChannel and self:GetGroupChatChannel()
    if not chan then return end
    self:SendPlanViewPollFor(self:GetCurrentPlanPresenceKey(), self:GetCurrentPlanId())
    if self:IsRaidLeadViewActive() or self:IsReadyCheckRaidCheckPanelActive() then
        self:ScheduleRaidCheckPollRefresh()
    end
end

function Diar:StopPlanViewHeartbeat()
    if self._planViewHeartbeat then
        self._planViewHeartbeat:Cancel()
        self._planViewHeartbeat = nil
    end
    if self._planViewPollTimer then
        self._planViewPollTimer:Cancel()
        self._planViewPollTimer = nil
    end
    if self._planViewAckTimer then
        self._planViewAckTimer:Cancel()
        self._planViewAckTimer = nil
    end
end

function Diar:EnsureGroupPlanViewAckTicker()
    if not C_Timer or not C_Timer.NewTicker then return end
    if self._groupViewAckTicker then return end
    self._groupViewAckTicker = C_Timer.NewTicker(30, function()
        if not IsInGroup() then return end
        local pf = Diar.plannerFrame
        Diar:BroadcastPlanViewPresence(pf and pf:IsShown() or false)
    end)
end

function Diar:EnsurePlanViewHeartbeat()
    if not C_Timer or not C_Timer.NewTicker then return end
    if self._planViewHeartbeat then return end
    self._planViewHeartbeat = C_Timer.NewTicker(HEARTBEAT_INTERVAL, function()
        local pf = Diar.plannerFrame
        if pf and pf:IsShown() then
            Diar:BroadcastPlanViewPresence(true)
        end
    end)
end

function Diar:EnsurePlanViewPollTimer()
    if not C_Timer or not C_Timer.NewTicker then return end
    if self._planViewPollTimer then return end
    self._planViewPollTimer = C_Timer.NewTicker(POLL_INTERVAL, function()
        if Diar:IsRaidLeadViewActive() or Diar:IsReadyCheckRaidCheckPanelActive() then
            Diar:SendPlanViewPoll()
        end
    end)
end

function Diar:OnPlannerFrameShown()
    self:BroadcastPlanViewPresence(true)
    self:EnsurePlanViewHeartbeat()
    if self:IsRaidLeadViewActive() then
        self:SendPlanViewPoll()
        self:EnsurePlanViewPollTimer()
        local pf = self.plannerFrame
        if pf and self.RefreshRaidLeadView then
            self:RefreshRaidLeadView(pf)
        end
    end
end

function Diar:OnPlannerFrameHidden()
    self:BroadcastPlanViewPresence(false)
    if self:IsRaidLeadViewActive() then
        local pf = self.plannerFrame
        if pf and self.RefreshRaidLeadView then
            self:RefreshRaidLeadView(pf)
        end
    end
end

function Diar:OnPlannerPlanChanged()
    self:BroadcastPlanViewPresence(self.plannerFrame and self.plannerFrame:IsShown())
    if self:IsRaidLeadViewActive() then
        self:SendPlanViewPoll()
        local pf = self.plannerFrame
        if pf and self.RefreshRaidLeadView then
            self:RefreshRaidLeadView(pf)
        end
    end
end

function Diar:GetGroupLeaderNameKey()
    if not IsInGroup() then return nil end
    local num = GetNumGroupMembers()
    if num == 0 then return nil end
    local prefix = IsInRaid() and "raid" or "party"
    for i = 1, num do
        local unit = (prefix == "party" and i == num) and "player" or (prefix .. i)
        if UnitExists(unit) and UnitIsGroupLeader(unit) then
            return PlayerNameKey(UnitName(unit))
        end
    end
    if UnitIsGroupLeader("player") then
        return PlayerNameKey(UnitName("player"))
    end
    return nil
end

function Diar:GetRaidLeaderActiveSceneIndex()
    if not IsInGroup() or UnitIsGroupLeader("player") then return nil end
    local leaderKey = self:GetGroupLeaderNameKey()
    if not leaderKey then return nil end

    local presence = self:GetPlanViewPresenceSnapshot()
    local entry = presence[leaderKey]
    if not entry or not entry.open then return nil end

    local currentKey = self:GetCurrentPlanPresenceKey() or ""
    if entry.activePlanKey and entry.activePlanKey ~= "" and currentKey ~= ""
        and entry.activePlanKey ~= currentKey then
        return nil
    end

    local sceneIdx = tonumber(entry.activeSceneIndex)
    if not sceneIdx or sceneIdx < 1 then return nil end

    local data = self.plannerData
    local scenes = data and data.scenes
    if not scenes or sceneIdx > #scenes then return nil end
    return math.floor(sceneIdx + 0.0001)
end

function Diar:OnPlannerSceneChanged()
    self:BroadcastPlanViewPresence(self.plannerFrame and self.plannerFrame:IsShown())
    if self.BroadcastRaidCheckSceneSwitch and self:IsRaidCheckAutoSwitchEnabled() then
        local pf = self.plannerFrame
        self:BroadcastRaidCheckSceneSwitch((pf and pf.selectedSceneIndex) or 1)
    end
    if self.UpdateSceneTabHighlight then
        self:UpdateSceneTabHighlight()
    end
end

local function PresenceEntryFresh(entry)
    return entry and entry.t and (GetTime() - entry.t) <= PRESENCE_TTL
end

local function PollAckWindowClosed()
    local pollAt = Diar._planViewPollAt
    if not pollAt then return false end
    return (GetTime() - pollAt) >= POLL_ACK_WAIT
end

local function MemberViewStatus(memberName, presence, currentKey, currentPlanId, localViewing, localHasPlan, localHasAddon)
    local key = PlayerNameKey(memberName)
    if not key then return "idle", "—" end
    if localViewing then
        if localHasPlan or currentKey == "" then
            return "viewing", L("Viewing")
        end
        return "missing", L("Missing plan")
    end
    if localHasAddon then
        if not localHasPlan and currentKey ~= "" then
            return "missing", L("Missing plan")
        end
        return "idle", "—"
    end

    local entry = presence[key]
    if not PresenceEntryFresh(entry) then
        if PollAckWindowClosed() then
            return "noaddon", L("Missing addon")
        end
        return "idle", "—"
    end

    if entry.targetPlanKey and entry.targetPlanKey ~= "" and currentKey ~= ""
        and entry.targetPlanKey ~= currentKey then
        return "idle", "—"
    end

    if entry.hasPlan == false then
        return "missing", L("Missing plan")
    end

    if not entry.open then
        return "idle", "—"
    end

    local activeKey = entry.activePlanKey or entry.planKey or ""
    if currentKey ~= "" and activeKey == currentKey then
        return "viewing", L("Viewing")
    end
    if activeKey ~= "" then
        return "other", L("Other plan")
    end
    return "viewing", L("Viewing")
end

local DEBUG_RAIDCHECK_STATUSES = {
    { "viewing", L("Viewing") },
    { "other", L("Other plan") },
    { "wrongversion", L("Wrong version") },
    { "missing", L("Missing plan") },
    { "noaddon", L("Missing addon") },
    { "idle", "—" },
}

local function DebugMemberViewStatus(name, rosterIndex)
    local key = PlayerNameKey(name) or tostring(name)
    local hash = rosterIndex or 0
    for i = 1, #key do
        hash = (hash * 33 + key:byte(i) + i * 13) % 1000003
    end
    local pick = (hash % #DEBUG_RAIDCHECK_STATUSES) + 1
    local entry = DEBUG_RAIDCHECK_STATUSES[pick]
    return entry[1], entry[2]
end

local function PresenceAnswerForPlan(entry, plan)
    if not entry or not plan then return nil end
    local planKey = plan.planKey or ""
    local planId = plan.planId and tostring(plan.planId) or ""
    if planKey ~= "" and entry.hasPlanByKey and entry.hasPlanByKey[planKey] ~= nil then
        return entry.hasPlanByKey[planKey] == true
    end
    if planId ~= "" and entry.hasPlanById and entry.hasPlanById[planId] ~= nil then
        return entry.hasPlanById[planId] == true
    end
    return nil
end

local function PresenceVersionForPlan(entry, plan)
    if not entry or not plan then return nil end
    local planKey = plan.planKey or ""
    local planId = plan.planId and tostring(plan.planId) or ""
    if planKey ~= "" and entry.planVersionByKey and entry.planVersionByKey[planKey] ~= nil then
        return tonumber(entry.planVersionByKey[planKey])
    end
    if planId ~= "" and entry.planVersionById and entry.planVersionById[planId] ~= nil then
        return tonumber(entry.planVersionById[planId])
    end
    return nil
end

local function ExpectedVersionForPlan(plan)
    if not plan then return nil end
    -- Always read live — do not cache at readycheck open (sends can update sync state).
    local planKey = plan.planKey or ""
    if planKey ~= "" and Diar.GetPlanSyncVersion then
        local v = tonumber(Diar:GetPlanSyncVersion(planKey))
        if v then return v end
    end
    local planId = plan.planId and tostring(plan.planId) or ""
    if planId ~= "" and Diar.GetLocalPlanSyncVersionForTarget then
        return tonumber(Diar:GetLocalPlanSyncVersionForTarget(planKey, planId))
    end
    return nil
end

local function BuildReadyCheckStatusTooltip(missing, wrong)
    local lines = {}
    if wrong and #wrong > 0 then
        lines[#lines + 1] = (#wrong == 1) and L("Wrong version") or L("Wrong versions")
        for _, item in ipairs(wrong) do
            local name = item.planName or item.alias or item.planId or L("Plan")
            local theirs = item.theirsVersion ~= nil and tostring(item.theirsVersion) or "?"
            local correct = item.expectedVersion ~= nil and tostring(item.expectedVersion) or "?"
            lines[#lines + 1] = L("%s — theirs: %s · correct: %s"):format(name, theirs, correct)
        end
    end
    if missing and #missing > 0 then
        if #lines > 0 then
            lines[#lines + 1] = " "
        end
        lines[#lines + 1] = (#missing == 1) and L("Missing plan") or L("Missing plans")
        for _, plan in ipairs(missing) do
            lines[#lines + 1] = plan.planName or plan.alias or plan.planId or L("Plan")
        end
    end
    return lines
end

function Diar:GetReadyCheckMemberPlanStatus(memberName, presence)
    local plans = self:GetReadyCheckRequiredPlans()
    local total = #plans
    local missing = {}
    local wrong = {}
    if total == 0 then
        return {
            have = 0,
            total = 0,
            missing = missing,
            wrong = wrong,
            sendPlans = {},
            tooltipLines = {},
            status = "idle",
            label = "—",
        }
    end

    local myKey = PlayerNameKey(UnitName("player"))
    local isMe = myKey and PlayerNameKey(memberName) == myKey
    local key = PlayerNameKey(memberName)
    local entry = key and presence and presence[key] or nil
    local closed = PollAckWindowClosed()
    local have = 0
    local answered = 0
    local pending = false

    for _, plan in ipairs(plans) do
        local answer
        local theirsVersion
        if isMe then
            answer = self:PlayerHasPlanKey(plan.planKey, plan.planId) and true or false
            if answer then
                theirsVersion = self:GetLocalPlanSyncVersionForTarget(plan.planKey, plan.planId)
            end
        else
            answer = PresenceAnswerForPlan(entry, plan)
            if answer == true then
                theirsVersion = PresenceVersionForPlan(entry, plan)
            end
        end
        if answer == true then
            answered = answered + 1
            local expected = ExpectedVersionForPlan(plan)
            local checkVersions = Diar.IsReadyCheckCheckPlanVersionsEnabled
                and Diar:IsReadyCheckCheckPlanVersionsEnabled()
            -- Only flag when enabled and both sides report a version and they differ.
            if checkVersions and expected and theirsVersion and theirsVersion ~= expected then
                wrong[#wrong + 1] = {
                    planId = plan.planId,
                    planKey = plan.planKey,
                    planName = plan.planName,
                    alias = plan.alias,
                    data = plan.data,
                    expectedVersion = expected,
                    theirsVersion = theirsVersion,
                }
            else
                have = have + 1
            end
        elseif answer == false then
            answered = answered + 1
            missing[#missing + 1] = plan
        elseif closed then
            missing[#missing + 1] = plan
        else
            pending = true
        end
    end

    local status, label
    if not isMe and answered == 0 and not PresenceEntryFresh(entry) then
        if closed then
            status, label = "noaddon", L("Missing addon")
            missing = {}
            wrong = {}
            for _, plan in ipairs(plans) do
                missing[#missing + 1] = plan
            end
        else
            status, label = "idle", ("—/%d"):format(total)
        end
    else
        label = ("%d/%d"):format(have, total)
        if #missing > 0 then
            status = "missing"
        elseif #wrong > 0 then
            status, label = "wrongversion", L("Wrong version")
        elseif pending then
            status = "idle"
        else
            status = "viewing"
        end
    end

    -- After we auto-sent missing/outdated plans, show that until they finish importing.
    if not isMe and (status == "missing" or status == "wrongversion")
        and self:WasReadyCheckAutoSent(memberName) then
        status, label = "autosent", L("Auto-sent")
    end

    local sendPlans = {}
    for _, plan in ipairs(missing) do
        sendPlans[#sendPlans + 1] = plan
    end
    for _, plan in ipairs(wrong) do
        sendPlans[#sendPlans + 1] = plan
    end

    return {
        have = have,
        total = total,
        missing = missing,
        wrong = wrong,
        sendPlans = sendPlans,
        tooltipLines = BuildReadyCheckStatusTooltip(missing, wrong),
        status = status,
        label = label,
    }
end

function Diar:RefreshReadyCheckRaidCheckPanel()
    local f = self.readyCheckRaidCheckFrame
    if not f or not f.scrollChild or not self:IsReadyCheckRaidCheckPanelActive() then
        return
    end

    local plans = self:GetReadyCheckRequiredPlans()
    local planTotal = #plans
    if f.title then
        if planTotal > 1 then
            f.title:SetText(L("Raidcheck (%d plans)"):format(planTotal))
        else
            f.title:SetText(L("Raidcheck"))
        end
    end

    local child = f.scrollChild
    local width = math.max(160, (f.listBox and f.listBox:GetWidth() or 232) - 20)
    child:SetWidth(width)

    for _, row in ipairs(f.rows or {}) do
        if row then row:Hide() end
    end
    f.rows = f.rows or {}

    local members = self.GetGroupMemberRoster and self:GetGroupMemberRoster() or {}
    local presence = self:GetPlanViewPresenceSnapshot()
    local debugMode = self.IsRsggDebug and self:IsRsggDebug()
    local myKey = PlayerNameKey(UnitName("player"))

    local sorted = {}
    for i, member in ipairs(members) do
        local isMe = myKey and PlayerNameKey(member.name) == myKey
        local info
        if debugMode and not isMe then
            local status, label = DebugMemberViewStatus(member.name, i)
            local have = (status == "viewing") and planTotal
                or ((status == "missing" or status == "wrongversion" or status == "noaddon") and 0
                    or math.floor(planTotal / 2))
            local missing, wrong = {}, {}
            if status == "wrongversion" and planTotal > 0 then
                local plan = plans[1]
                wrong[1] = {
                    planId = plan.planId,
                    planKey = plan.planKey,
                    planName = plan.planName,
                    alias = plan.alias,
                    expectedVersion = 5,
                    theirsVersion = 3,
                }
                for pi = 2, planTotal do
                    missing[#missing + 1] = plans[pi]
                end
                status, label = "wrongversion", L("Wrong version")
            elseif have < planTotal then
                for pi = have + 1, planTotal do
                    missing[#missing + 1] = plans[pi]
                end
                if status ~= "noaddon" then
                    status = (have >= planTotal and planTotal > 0) and "viewing" or "missing"
                    label = ("%d/%d"):format(have, planTotal)
                end
            else
                status, label = "viewing", ("%d/%d"):format(have, planTotal)
            end
            if status == "noaddon" then
                label = L("Missing addon")
            end
            info = {
                status = status,
                label = label,
                have = have,
                total = planTotal,
                missing = missing,
                wrong = wrong,
                sendPlans = missing,
                tooltipLines = BuildReadyCheckStatusTooltip(missing, wrong),
            }
        else
            info = self:GetReadyCheckMemberPlanStatus(member.name, presence)
        end
        sorted[#sorted + 1] = {
            name = member.name,
            status = info.status,
            statusLabel = info.label,
            have = info.have,
            total = info.total,
            missing = info.missing,
            wrong = info.wrong,
            sendPlans = info.sendPlans or info.missing,
            tooltipLines = info.tooltipLines,
        }
    end

    table.sort(sorted, function(a, b)
        local rank = { viewing = 0, autosent = 1, other = 2, wrongversion = 3, missing = 4, noaddon = 5, idle = 6 }
        local ra, rb = rank[a.status] or 6, rank[b.status] or 6
        if ra ~= rb then return ra < rb end
        local ha, hb = a.have or 0, b.have or 0
        if ha ~= hb then return ha > hb end
        return a.name:lower() < b.name:lower()
    end)

    local y = 0
    local completeCount = 0
    local missingPeople = 0
    for i, member in ipairs(sorted) do
        local row = f.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, child)
            row:SetHeight(ROW_H)
            row:EnableMouse(true)
            row.dot = row:CreateTexture(nil, "ARTWORK")
            row.dot:SetSize(8, 8)
            row.dot:SetPoint("LEFT", 2, 0)
            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.nameText:SetPoint("LEFT", row.dot, "RIGHT", 6, 0)
            row.nameText:SetJustifyH("LEFT")
            row.statusText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.statusText:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            row.statusText:SetJustifyH("RIGHT")
            row:SetScript("OnMouseUp", function(s, button)
                if button ~= "RightButton" then return end
                if not s.memberName or s.memberName == "" then return end
                if Diar.ShowReadyCheckRaidCheckMemberMenu then
                    Diar:ShowReadyCheckRaidCheckMemberMenu(s, s.memberName, s.missingPlans)
                end
            end)
            row:SetScript("OnEnter", function(s)
                local lines = s.tooltipLines
                if type(lines) ~= "table" or #lines == 0 then return end
                GameTooltip:SetOwner(s, "ANCHOR_LEFT")
                GameTooltip:ClearLines()
                for li, line in ipairs(lines) do
                    if li == 1 then
                        GameTooltip:SetText(line, 1, 1, 1, 1, true)
                    else
                        GameTooltip:AddLine(line, 0.85, 0.85, 0.85, true)
                    end
                end
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            f.rows[i] = row
        end
        row:Show()
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -y)

        local unit = self.FindGroupUnitByName and self:FindGroupUnitByName(member.name)
        local _, classFile = unit and UnitClass(unit) or nil
        local cr, cg, cb = GetClassColor(classFile)
        row.memberName = member.name
        row.missingPlans = member.sendPlans or member.missing
        row.tooltipLines = member.tooltipLines
        row.nameText:SetText(member.name)
        row.nameText:SetTextColor(cr, cg, cb)

        local status = member.status
        if status == "viewing" then
            completeCount = completeCount + 1
            row.dot:SetColorTexture(unpack(UI.VIEWING))
            row.statusText:SetTextColor(unpack(UI.VIEWING))
        elseif status == "autosent" then
            row.dot:SetColorTexture(unpack(UI.OTHER))
            row.statusText:SetTextColor(unpack(UI.OTHER))
        elseif status == "other" then
            row.dot:SetColorTexture(unpack(UI.OTHER))
            row.statusText:SetTextColor(unpack(UI.OTHER))
        elseif status == "wrongversion" then
            missingPeople = missingPeople + 1
            row.dot:SetColorTexture(unpack(UI.WRONGVER))
            row.statusText:SetTextColor(unpack(UI.WRONGVER))
        elseif status == "missing" then
            missingPeople = missingPeople + 1
            row.dot:SetColorTexture(unpack(UI.MISSING))
            row.statusText:SetTextColor(unpack(UI.MISSING))
        elseif status == "noaddon" then
            row.dot:SetColorTexture(unpack(UI.NOADDON))
            row.statusText:SetTextColor(unpack(UI.NOADDON))
        else
            row.dot:SetColorTexture(unpack(UI.IDLE))
            row.statusText:SetTextColor(unpack(UI.IDLE))
        end
        row.statusText:SetText(member.statusLabel)
        y = y + ROW_H
    end

    child:SetHeight(math.max(1, y))
    if f.summary then
        f.summary:SetText(L("%d / %d complete"):format(completeCount, #sorted))
    end
    if f.sendAllBtn then
        if missingPeople > 0 and self:CanSendRaidCheckNotif() then
            f.sendAllBtn:Enable()
            f.sendAllBtn:SetAlpha(1)
            if f.sendAllBtn.label then
                f.sendAllBtn.label:SetText(L("Send to all missing (%d)"):format(missingPeople))
            end
        else
            f.sendAllBtn:Disable()
            f.sendAllBtn:SetAlpha(0.45)
            if f.sendAllBtn.label then
                f.sendAllBtn.label:SetText(L("Send to all missing"))
            end
        end
    end
end

function Diar:RefreshRaidLeadView(pf)
    if self:IsReadyCheckRaidCheckPanelActive() then
        self:RefreshReadyCheckRaidCheckPanel()
    end
    pf = pf or self.plannerFrame
    if not pf or not pf.raidLeadScrollChild then return end
    if not self:ShouldShowRaidCheckBar() then return end
    if not self:IsRaidCheckEnabled(pf) then return end
    if pf.compactMode then return end

    local child = pf.raidLeadScrollChild
    for _, row in ipairs(pf.raidLeadRows or {}) do
        if row then row:Hide() end
    end
    pf.raidLeadRows = pf.raidLeadRows or {}

    local members = self.GetGroupMemberRoster and self:GetGroupMemberRoster() or {}
    local presence = self:GetPlanViewPresenceSnapshot()
    local currentKey = self:GetCurrentPlanPresenceKey() or ""
    local currentPlanId = self:GetCurrentPlanId()
    local viewingCount = 0
    local myKey = PlayerNameKey(UnitName("player"))
    local iAmViewing = pf:IsShown()
    local iHavePlan = self:PlayerHasPlanKey(currentKey, currentPlanId)
    local debugMode = self.IsRsggDebug and self:IsRsggDebug()
    local showAutoSwitchState = self:IsRaidCheckAutoSwitchEnabled(pf)

    local sorted = {}
    for i, member in ipairs(members) do
        local isMe = myKey and PlayerNameKey(member.name) == myKey
        local status, label
        if debugMode and not isMe then
            status, label = DebugMemberViewStatus(member.name, i)
        else
            status, label = MemberViewStatus(
                member.name, presence, currentKey, currentPlanId,
                isMe and iAmViewing, isMe and iHavePlan, isMe and not iAmViewing
            )
        end
        if status == "viewing" then viewingCount = viewingCount + 1 end
        local key = PlayerNameKey(member.name)
        local entry = key and presence[key] or nil
        local autoSwitchApproved = nil
        if showAutoSwitchState and status == "viewing" then
            if isMe then
                autoSwitchApproved = true
            elseif entry and PresenceEntryFresh(entry) then
                if currentKey == "" or entry.autoSwitchPlanKey == "" or entry.autoSwitchPlanKey == currentKey then
                    autoSwitchApproved = entry.autoSwitchApproved == true
                else
                    autoSwitchApproved = false
                end
            else
                autoSwitchApproved = false
            end
        end
        sorted[#sorted + 1] = {
            name = member.name,
            status = status,
            statusLabel = label,
            autoSwitchApproved = autoSwitchApproved,
        }
    end

    table.sort(sorted, function(a, b)
        local rank = { viewing = 0, other = 1, missing = 2, noaddon = 3, idle = 4 }
        local ra, rb = rank[a.status] or 4, rank[b.status] or 4
        if ra ~= rb then return ra < rb end
        return a.name:lower() < b.name:lower()
    end)

    local y = 0
    for i, member in ipairs(sorted) do
        local row = pf.raidLeadRows[i]
        if not row then
            row = CreateFrame("Frame", nil, child)
            row:SetHeight(ROW_H)
            row:EnableMouse(true)
            row.dot = row:CreateTexture(nil, "ARTWORK")
            row.dot:SetSize(8, 8)
            row.dot:SetPoint("LEFT", 2, 0)
            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.nameText:SetPoint("LEFT", row.dot, "RIGHT", 6, 0)
            row.nameText:SetJustifyH("LEFT")
            row.statusText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.statusText:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            row.statusText:SetJustifyH("RIGHT")

            local autoSwitchBtn = CreateFrame("Button", nil, row)
            autoSwitchBtn:SetSize(14, 14)
            autoSwitchBtn:SetPoint("RIGHT", row.statusText, "LEFT", -4, 0)
            autoSwitchBtn:EnableMouse(true)
            autoSwitchBtn.icon = autoSwitchBtn:CreateTexture(nil, "OVERLAY")
            autoSwitchBtn.icon:SetAllPoints(autoSwitchBtn)
            autoSwitchBtn:Hide()
            autoSwitchBtn:SetScript("OnEnter", function(s)
                if not s.tooltipText then return end
                GameTooltip:SetOwner(s, "ANCHOR_LEFT")
                GameTooltip:SetText(s.tooltipText, 1, 1, 1)
                GameTooltip:Show()
            end)
            autoSwitchBtn:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            row.autoSwitchBtn = autoSwitchBtn
            row:SetScript("OnMouseUp", function(s, button)
                if button ~= "RightButton" then return end
                if not s.memberName or s.memberName == "" then return end
                if Diar.ShowRaidCheckMemberContextMenu then
                    Diar:ShowRaidCheckMemberContextMenu(s, s.memberName)
                end
            end)
            pf.raidLeadRows[i] = row
        end
        row:Show()
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -y)

        local unit = self.FindGroupUnitByName and self:FindGroupUnitByName(member.name)
        local _, classFile = unit and UnitClass(unit) or nil
        local cr, cg, cb = GetClassColor(classFile)
        row.memberName = member.name
        row.nameText:SetText(member.name)
        row.nameText:SetTextColor(cr, cg, cb)

        local status = member.status
        if status == "viewing" then
            row.dot:SetColorTexture(unpack(UI.VIEWING))
            row.statusText:SetTextColor(unpack(UI.VIEWING))
        elseif status == "other" then
            row.dot:SetColorTexture(unpack(UI.OTHER))
            row.statusText:SetTextColor(unpack(UI.OTHER))
        elseif status == "missing" then
            row.dot:SetColorTexture(unpack(UI.MISSING))
            row.statusText:SetTextColor(unpack(UI.MISSING))
        elseif status == "noaddon" then
            row.dot:SetColorTexture(unpack(UI.NOADDON))
            row.statusText:SetTextColor(unpack(UI.NOADDON))
        else
            row.dot:SetColorTexture(unpack(UI.IDLE))
            row.statusText:SetTextColor(unpack(UI.IDLE))
        end
        row.statusText:SetText(member.statusLabel)
        if row.autoSwitchBtn then
            if showAutoSwitchState and status == "viewing" then
                row.autoSwitchBtn:Show()
                if member.autoSwitchApproved then
                    row.autoSwitchBtn.icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
                    row.autoSwitchBtn.tooltipText = L("Auto-switch enabled")
                else
                    row.autoSwitchBtn.icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
                    row.autoSwitchBtn.tooltipText = L("Auto-switch not enabled")
                end
            else
                row.autoSwitchBtn:Hide()
                row.autoSwitchBtn.tooltipText = nil
            end
        end

        y = y + ROW_H
    end

    child:SetHeight(math.max(1, y))
    if pf.raidCheckSummary then
        pf.raidCheckSummary:SetText(L("%d / %d viewing"):format(viewingCount, #sorted))
    end
    self:UpdateRaidCheckNotifBtn(pf)
end

function Diar:IsRaidCheckNotifsEnabled()
    local v = self.GetPlannerSettings and self:GetPlannerSettings().hideRaidCheckNotifs
    if v == true or v == 1 then return false end
    return true
end

function Diar:CanSendRaidCheckNotif()
    if not (self.IsPushUpdateLeader and self:IsPushUpdateLeader()) then return false end
    if not IsInGroup() then return false end
    return true
end

function Diar:IsRaidCheckAutoSwitchEnabled(pf)
    pf = pf or self.plannerFrame
    return pf and pf.raidCheckAutoSwitchEnabled == true
end

local function IsSenderGroupLeader(sender)
    local senderKey = PlayerNameKey(sender and (Ambiguate and Ambiguate(sender, "short") or sender) or sender)
    if not senderKey then return false end
    return senderKey == Diar:GetGroupLeaderNameKey()
end

function Diar:BuildRaidCheckAutoSwitchMsg(enabled)
    local planKey = SanitizeCommField(self:GetCurrentPlanPresenceKey())
    return table.concat({ "RASC", enabled and "1" or "0", planKey }, SEP)
end

function Diar:BuildRaidCheckAutoSwitchResponseMsg(planKey, approved)
    return table.concat({ "RASR", approved and "1" or "0", SanitizeCommField(planKey) }, SEP)
end

function Diar:BroadcastRaidCheckAutoSwitchState(enabled)
    if not self:CanSendRaidCheckNotif() then return false end
    local chan = self.GetGroupChatChannel and self:GetGroupChatChannel()
    if not chan then return false end
    local prefix = self.COMM_PLAN_PREFIX or "RAIDSTRATS_PLAN"
    self:SendCommMessage(prefix, self:BuildRaidCheckAutoSwitchMsg(enabled), chan)
    return true
end

function Diar:BroadcastRaidCheckAutoSwitchResponse(planKey, approved)
    if not IsInGroup() then return false end
    local chan = self.GetGroupChatChannel and self:GetGroupChatChannel()
    if not chan then return false end
    local prefix = self.COMM_PLAN_PREFIX or "RAIDSTRATS_PLAN"
    self:SendCommMessage(prefix, self:BuildRaidCheckAutoSwitchResponseMsg(planKey, approved), chan)
    return true
end

function Diar:BuildRaidCheckSceneSwitchMsg(sceneIndex)
    sceneIndex = tonumber(sceneIndex) or 1
    sceneIndex = math.max(1, math.floor(sceneIndex + 0.0001))
    local planKey = SanitizeCommField(self:GetCurrentPlanPresenceKey())
    return table.concat({ "RSSC", tostring(sceneIndex), planKey }, SEP)
end

function Diar:BroadcastRaidCheckSceneSwitch(sceneIndex)
    if not self:IsRaidCheckAutoSwitchEnabled() then return false end
    if not self:CanSendRaidCheckNotif() then return false end
    local chan = self.GetGroupChatChannel and self:GetGroupChatChannel()
    if not chan then return false end
    local prefix = self.COMM_PLAN_PREFIX or "RAIDSTRATS_PLAN"
    self:SendCommMessage(prefix, self:BuildRaidCheckSceneSwitchMsg(sceneIndex), chan)
    return true
end

function Diar:SetRaidCheckAutoSwitchEnabled(pf, enabled, opts)
    pf = pf or self.plannerFrame
    if not pf then return false end
    enabled = not not enabled
    opts = opts or {}

    if enabled and not self:CanSendRaidCheckNotif() then
        print(L("|cffff6666[Raidstrats.gg]|r Only the raid leader can enable Auto-switch scene for all."))
        enabled = false
    end
    if enabled and not self:IsRaidCheckEnabled(pf) then
        enabled = false
    end

    local changed = (pf.raidCheckAutoSwitchEnabled == true) ~= enabled
    pf.raidCheckAutoSwitchEnabled = enabled
    if pf.raidCheckAutoSwitchChk then
        pf.raidCheckAutoSwitchChk:SetChecked(enabled)
    end
    if pf.raidCheckAutoSwitchLabel then
        if enabled then
            pf.raidCheckAutoSwitchLabel:SetTextColor(0.78, 0.95, 0.82)
        else
            pf.raidCheckAutoSwitchLabel:SetTextColor(0.66, 0.69, 0.74)
        end
    end

    if changed and opts.broadcast ~= false then
        if self:BroadcastRaidCheckAutoSwitchState(enabled) then
            local stateText = enabled and L("enabled") or L("disabled")
            print(L("|cff00aaff[Raidstrats.gg]|r Auto-switch scene for all %s."):format(stateText))
        end
    end

    if changed and enabled then
        local key = self:GetCurrentPlanPresenceKey() or ""
        self:SetPlanViewAutoSwitchState(UnitName("player"), key, true)
    elseif changed and not enabled then
        local key = self:GetCurrentPlanPresenceKey() or ""
        self:SetPlanViewAutoSwitchState(UnitName("player"), key, false)
    end
    if pf:IsShown() and self:IsRaidLeadViewActive() and self.RefreshRaidLeadView then
        self:RefreshRaidLeadView(pf)
    end
    return changed
end

function Diar:HideRaidCheckAutoSwitchPrompt()
    if self._raidCheckAutoSwitchPopup then
        self._raidCheckAutoSwitchPopup:Hide()
    end
end

function Diar:ShowRaidCheckAutoSwitchPrompt(sender, planKey)
    self:HideRaidCheckAutoSwitchPrompt()
    local who = sender and (Ambiguate and Ambiguate(sender, "short") or sender) or L("Raid leader")

    local f = CreateFrame("Frame", "RaidstratsAutoSwitchPromptPopup", UIParent, "BackdropTemplate")
    f:SetSize(390, 168)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)
    if SetBackdrop then SetBackdrop(f, UI.PANEL, UI.BORDER, 2) end
    tinsert(UISpecialFrames, "RaidstratsAutoSwitchPromptPopup")

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText(L("Auto-switch scene request"))
    title:SetTextColor(0.92, 0.92, 0.92)

    local msg = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    msg:SetPoint("TOP", title, "BOTTOM", 0, -10)
    msg:SetWidth(338)
    msg:SetJustifyH("CENTER")
    msg:SetText(L("%s enabled auto-switch scene for the group.\nAllow scene changes from raid lead?"):format(who))
    msg:SetTextColor(0.78, 0.80, 0.84)

    local function MakeBtn(text, x, onClick)
        local b = CreateFrame("Button", nil, f, "BackdropTemplate")
        b:SetSize(126, 28)
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

    MakeBtn(L("Deny"), -70, function()
        Diar._raidCheckRemoteAutoSwitchEnabled = false
        Diar._raidCheckRemoteAutoSwitchApproved = false
        Diar._raidCheckRemoteAutoSwitchPlanKey = planKey or ""
        Diar:BroadcastRaidCheckAutoSwitchResponse(planKey, false)
        Diar:HideRaidCheckAutoSwitchPrompt()
        print(L("|cff00aaff[Raidstrats.gg]|r Auto-switch scene denied."))
    end)
    MakeBtn(L("Approve"), 70, function()
        Diar._raidCheckRemoteAutoSwitchEnabled = true
        Diar._raidCheckRemoteAutoSwitchApproved = true
        Diar._raidCheckRemoteAutoSwitchPlanKey = planKey or ""
        Diar:BroadcastRaidCheckAutoSwitchResponse(planKey, true)
        Diar:HideRaidCheckAutoSwitchPrompt()
        print(L("|cff00aaff[Raidstrats.gg]|r Auto-switch scene approved."))
    end)

    f:SetScript("OnHide", function()
        if Diar._raidCheckAutoSwitchPopup == f then
            Diar._raidCheckAutoSwitchPopup = nil
        end
    end)

    self._raidCheckAutoSwitchPopup = f
    if self.PrepareModal then
        self:PrepareModal(f, self.plannerFrame or self.frame)
    end
    f:ClearAllPoints()
    f:SetPoint("CENTER")
    f:Show()
    if PlaySound then PlaySound(3190, "master") end
end

function Diar:HandleRaidCheckAutoSwitchComm(msg, sender)
    if type(msg) ~= "string" or msg:sub(1, 4) ~= "RASC" then return end
    if not IsSenderGroupLeader(sender) then return end
    local parts = SplitSep(msg, SEP)
    if parts[1] ~= "RASC" then return end
    local enabled = parts[2] == "1"
    local planKey = parts[3] or ""
    local senderName = sender and (Ambiguate and Ambiguate(sender, "short") or sender) or L("Raid leader")
    local stateText = enabled and L("enabled") or L("disabled")
    print(L("|cff00aaff[Raidstrats.gg]|r %s %s Auto-switch scene for all."):format(senderName, stateText))
    if enabled then
        self._raidCheckRemoteAutoSwitchEnabled = false
        self._raidCheckRemoteAutoSwitchApproved = false
        self._raidCheckRemoteAutoSwitchPlanKey = planKey
        self:ShowRaidCheckAutoSwitchPrompt(sender, planKey)
    else
        self._raidCheckRemoteAutoSwitchEnabled = false
        self._raidCheckRemoteAutoSwitchApproved = false
        self._raidCheckRemoteAutoSwitchPlanKey = planKey
        self:HideRaidCheckAutoSwitchPrompt()
    end
end

function Diar:ApplyRaidCheckRemoteSceneSwitch(sceneIndex)
    local pf = self.plannerFrame
    local data = self.plannerData
    if not pf or not pf:IsShown() or not data or not data.scenes then return false end
    local idx = tonumber(sceneIndex)
    if not idx then return false end
    idx = math.floor(idx + 0.0001)
    if idx < 1 or idx > #data.scenes then return false end
    if (pf.selectedSceneIndex or 1) == idx then return false end

    pf.selectedSceneIndex = idx
    pf.__viewerViewportSceneIdx = nil
    if not pf.nsrtSceneActive then
        self:ApplyNsrtAssignmentForPlannerView(idx)
    else
        self.activeGroup = nil
    end
    self:StopPlannerAnimation()
    self:UpdateSceneTabHighlight()
    self:RefreshPlannerScene()
    if self.OnPlannerSceneChanged then self:OnPlannerSceneChanged() end
    return true
end

function Diar:HandleRaidCheckSceneSwitchComm(msg, sender)
    if type(msg) ~= "string" or msg:sub(1, 4) ~= "RSSC" then return end
    if not IsSenderGroupLeader(sender) then return end
    if not self._raidCheckRemoteAutoSwitchEnabled or not self._raidCheckRemoteAutoSwitchApproved then return end
    local parts = SplitSep(msg, SEP)
    if parts[1] ~= "RSSC" then return end
    local sceneIndex = tonumber(parts[2] or "")
    local planKey = parts[3] or ""
    if not sceneIndex then return end
    local approvedPlanKey = self._raidCheckRemoteAutoSwitchPlanKey or ""
    if approvedPlanKey ~= "" and planKey ~= "" and planKey ~= approvedPlanKey then
        return
    end
    if planKey ~= "" then
        local currentKey = self:GetCurrentPlanPresenceKey() or ""
        if currentKey ~= "" and currentKey ~= planKey then
            return
        end
    end
    self:ApplyRaidCheckRemoteSceneSwitch(sceneIndex)
end

function Diar:HandleRaidCheckAutoSwitchResponseComm(msg, sender)
    if type(msg) ~= "string" or msg:sub(1, 4) ~= "RASR" then return end
    if not self:CanSendRaidCheckNotif() then return end
    local parts = SplitSep(msg, SEP)
    if parts[1] ~= "RASR" then return end
    local approved = parts[2] == "1"
    local planKey = parts[3] or ""
    self:SetPlanViewAutoSwitchState(sender, planKey, approved)
    local pf = self.plannerFrame
    if pf and pf:IsShown() and self:IsRaidLeadViewActive() and self.RefreshRaidLeadView then
        self:RefreshRaidLeadView(pf)
    end
end

function Diar:UpdateRaidCheckNotifBtn(pf)
    pf = pf or self.plannerFrame
    local btn = pf and pf.raidCheckNotifBtn
    local scroll = pf and pf.raidLeadScroll
    local box = pf and pf.raidLeadPanel
    local autoChk = pf and pf.raidCheckAutoSwitchChk
    local autoLbl = pf and pf.raidCheckAutoSwitchLabel
    if not btn or not scroll or not box then return end

    local show = self:IsRaidLeadViewActive() and self:CanSendRaidCheckNotif()
    if autoChk and autoLbl then
        if show then
            autoChk:Show()
            autoLbl:Show()
        else
            autoChk:Hide()
            autoLbl:Hide()
            if self:IsRaidCheckAutoSwitchEnabled(pf) then
                self:SetRaidCheckAutoSwitchEnabled(pf, false, { broadcast = false })
            end
        end
    end
    if show then
        btn:Show()
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -6)
        scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -6, 6 + RAID_NOTIF_BTN_H + 26)
    else
        btn:Hide()
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -6)
        scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -6, 6)
    end
end

function Diar:SendRaidCheckNotif()
    if not self:CanSendRaidCheckNotif() then
        print(L("|cffff6666[Raidstrats.gg]|r Only the raid lead can send those."))
        return
    end

    local chan = self.GetGroupChatChannel and self:GetGroupChatChannel()
    if not chan then
        print(L("|cffff6666[Raidstrats.gg]|r Hop in a party or raid first."))
        return
    end

    local data = self.plannerData
    if not data or not data.scenes or #data.scenes == 0 then
        print(L("|cffff6666[Raidstrats.gg]|r Load a plan first."))
        return
    end
    if self.EnsurePlanInstanceKey then self:EnsurePlanInstanceKey(data) end
    if self.PersistCurrentPlanToSaved then self:PersistCurrentPlanToSaved() end

    -- Smart stamp: bump only if content differs from last sync baseline.
    local payload = self.BuildSharePayload and self:BuildSharePayload(data)
    if not payload or payload == "" then
        print(L("|cffff6666[Raidstrats.gg]|r Couldn't pack that plan up to send."))
        return
    end

    local planName = (data.planName and data.planName ~= "") and data.planName or L("Raid plan")
    local planKey = SanitizeCommField(self:GetCurrentPlanPresenceKey())
    local planId = SanitizeCommField(self:GetCurrentPlanId())
    local transferId = string.format("rc%x%x", time(), math.random(0, 0xFFFFFF))
    self._sharedPlans = self._sharedPlans or {}
    self._sharedPlans[transferId] = { payload = payload, t = time() }

    local owner = self.GetPlayerShareName and self:GetPlayerShareName()
        or (UnitName("player") or "Unknown")
    local prefix = self.COMM_PLAN_PREFIX or "RAIDSTRATS_PLAN"
    local msg = table.concat({
        "RNOT", SanitizeCommField(planName), planKey, planId,
        SanitizeCommField(transferId), SanitizeCommField(owner),
    }, SEP)
    self:SendCommMessage(prefix, msg, chan)
    print(L("|cff00aaff[Raidstrats.gg]|r Pinged the %s about \"%s\"."):format(
        chan == "RAID" and L("raid") or (chan == "PARTY" and L("party") or L("group")), planName))
end

local function BuildWhisperTargetFromMember(name)
    local trimmed = strtrim(tostring(name or ""))
    if trimmed == "" then return nil end
    local unit = Diar.FindGroupUnitByName and Diar:FindGroupUnitByName(trimmed)
    if not unit then return trimmed end
    local unitName, unitRealm = UnitName(unit)
    unitName = strtrim(tostring(unitName or ""))
    unitRealm = strtrim(tostring(unitRealm or ""))
    if unitName == "" then return trimmed end
    if unitRealm ~= "" then
        return unitName .. "-" .. unitRealm
    end
    return unitName
end

function Diar:SendRaidCheckNotifToMember(memberName)
    return self:SendRaidCheckPlanToMember(memberName, {
        data = self.plannerData,
        planKey = self:GetCurrentPlanPresenceKey(),
        planId = self:GetCurrentPlanId(),
        planName = self.plannerData and self.plannerData.planName,
    })
end

function Diar:SendRaidCheckPlanToMember(memberName, plan)
    if not self:CanSendRaidCheckNotif() then
        print(L("|cffff6666[Raidstrats.gg]|r Only the raid lead can send those."))
        return false
    end

    local target = BuildWhisperTargetFromMember(memberName)
    if not target or target == "" then
        print(L("|cffff6666[Raidstrats.gg]|r Couldn't find that player to whisper."))
        return false
    end

    plan = plan or {}
    local data = plan.data
    if (not data or not data.scenes or #data.scenes == 0) and plan.planId and plan.planId ~= "" then
        data = FindSavedPlanDataByPlanId(plan.planId)
    end
    if not data or not data.scenes or #data.scenes == 0 then
        print(L("|cffff6666[Raidstrats.gg]|r You don't have \"%s\" saved locally, so nothing to send."):format(
            tostring(plan.planName or plan.alias or plan.planId or L("plan"))))
        return false
    end
    if self.EnsurePlanInstanceKey then self:EnsurePlanInstanceKey(data) end

    -- Smart stamp: bump only if content differs from last sync baseline.
    local payload = self.BuildSharePayload and self:BuildSharePayload(data)
    if not payload or payload == "" then
        print(L("|cffff6666[Raidstrats.gg]|r Couldn't pack that plan up to send."))
        return false
    end

    local planName = (plan.planName and plan.planName ~= "") and plan.planName
        or ((data.planName and data.planName ~= "") and data.planName or L("Raid plan"))
    local planKey = SanitizeCommField(plan.planKey or (self.GetPlanIdentityKey and self:GetPlanIdentityKey(data)) or "")
    local planId = SanitizeCommField(plan.planId or data.planId or "")
    local transferId = string.format("rc%x%x", time(), math.random(0, 0xFFFFFF))
    self._sharedPlans = self._sharedPlans or {}
    self._sharedPlans[transferId] = { payload = payload, t = time() }

    local owner = self.GetPlayerShareName and self:GetPlayerShareName()
        or (UnitName("player") or "Unknown")
    local prefix = self.COMM_PLAN_PREFIX or "RAIDSTRATS_PLAN"
    local msg = table.concat({
        "RNOT", SanitizeCommField(planName), planKey, planId,
        SanitizeCommField(transferId), SanitizeCommField(owner),
    }, SEP)
    self:SendCommMessage(prefix, msg, "WHISPER", target, "NORMAL")
    print(L("|cff00aaff[Raidstrats.gg]|r Sent \"%s\" to %s."):format(
        planName, Ambiguate and Ambiguate(target, "short") or target))
    return true
end

-- One whisper offer for the full note plan set; receiver gets a single Import N plans modal.
function Diar:SendReadyCheckNotePlansBundleToMember(memberName, sendable)
    if not self:CanSendRaidCheckNotif() then
        print(L("|cffff6666[Raidstrats.gg]|r Only the raid lead can send those."))
        return false
    end
    local target = BuildWhisperTargetFromMember(memberName)
    if not target or target == "" then
        print(L("|cffff6666[Raidstrats.gg]|r Couldn't find that player to whisper."))
        return false
    end
    sendable = sendable or self:GetSendableReadyCheckNotePlans({ reload = true })
    if type(sendable) ~= "table" or #sendable == 0 then
        print(L("|cffff6666[Raidstrats.gg]|r You don't have the note plans saved locally."))
        return false
    end
    if not self.BuildAndCachePlansShareBundle then
        print(L("|cffff6666[Raidstrats.gg]|r Plan bundle share isn't available."))
        return false
    end
    local linkLabel, count = self:BuildAndCachePlansShareBundle(sendable, L("Note plans"))
    if not linkLabel or not count or count < 1 then
        print(L("|cffff6666[Raidstrats.gg]|r Couldn't pack the note plans to send."))
        return false
    end
    local owner = self.GetPlayerShareName and self:GetPlayerShareName()
        or (UnitName("player") or "Unknown")
    local prefix = self.COMM_PLAN_PREFIX or "RAIDSTRATS_PLAN"
    local msg = table.concat({
        "RNGB",
        SanitizeCommField(linkLabel),
        tostring(count),
        SanitizeCommField(owner),
    }, SEP)
    self:SendCommMessage(prefix, msg, "WHISPER", target, "NORMAL")
    return true
end

function Diar:SendReadyCheckMissingPlansToMember(memberName, missingPlans)
    memberName = strtrim(tostring(memberName or ""))
    if memberName == "" then return false end
    local sendable = self:GetSendableReadyCheckNotePlans({ reload = true })
    if #sendable == 0 then
        print(L("|cffff6666[Raidstrats.gg]|r You don't have the note plans saved locally."))
        return false
    end

    self:MarkReadyCheckAutoSent(memberName)
    local ok = self:SendReadyCheckNotePlansBundleToMember(memberName, sendable)
    if ok then
        print(L("|cff00aaff[Raidstrats.gg]|r Sent all %d note plan%s to %s."):format(
            #sendable,
            #sendable == 1 and "" or "s",
            Ambiguate and Ambiguate(memberName, "short") or memberName))
    end
    if self:IsReadyCheckRaidCheckPanelActive() and self.RefreshReadyCheckRaidCheckPanel then
        self:RefreshReadyCheckRaidCheckPanel()
    end
    return ok
end

function Diar:SendReadyCheckMissingPlansToAll()
    if not self:CanSendRaidCheckNotif() then
        print(L("|cffff6666[Raidstrats.gg]|r Only the raid lead can send those."))
        return false
    end
    local members = self.GetGroupMemberRoster and self:GetGroupMemberRoster() or {}
    local presence = self:GetPlanViewPresenceSnapshot()
    local myKey = PlayerNameKey(UnitName("player"))
    local queue = {}
    for _, member in ipairs(members) do
        if not (myKey and PlayerNameKey(member.name) == myKey) then
            local info = self:GetReadyCheckMemberPlanStatus(member.name, presence)
            local sendPlans = info and (info.sendPlans or info.missing) or nil
            if info and (info.status == "missing" or info.status == "wrongversion")
                and sendPlans and #sendPlans > 0 then
                queue[#queue + 1] = { name = member.name, missing = sendPlans }
            end
        end
    end
    if #queue == 0 then
        print(L("|cffff9900[Raidstrats.gg]|r Everyone already has the correct note plans."))
        return false
    end

    local sendable = self:GetSendableReadyCheckNotePlans({ reload = true })
    if #sendable == 0 then
        print(L("|cffff6666[Raidstrats.gg]|r You don't have the note plans saved locally."))
        return false
    end

    local people = 0
    for _, item in ipairs(queue) do
        self:MarkReadyCheckAutoSent(item.name)
        if self:SendReadyCheckNotePlansBundleToMember(item.name, sendable) then
            people = people + 1
        end
    end
    if people == 0 then
        print(L("|cffff6666[Raidstrats.gg]|r Couldn't send the note plans to anyone."))
        return false
    end
    print(L("|cff00aaff[Raidstrats.gg]|r Sent all %d note plan%s to %d player%s..."):format(
        #sendable,
        #sendable == 1 and "" or "s",
        people,
        people == 1 and "" or "s"))
    if self:IsReadyCheckRaidCheckPanelActive() and self.RefreshReadyCheckRaidCheckPanel then
        self:RefreshReadyCheckRaidCheckPanel()
    end
    return true
end

function Diar:ShowReadyCheckRaidCheckMemberMenu(anchor, memberName, missingPlans)
    memberName = strtrim(tostring(memberName or ""))
    if memberName == "" then return end
    missingPlans = missingPlans or {}
    if #missingPlans == 0 then
        local presence = self:GetPlanViewPresenceSnapshot()
        local info = self:GetReadyCheckMemberPlanStatus(memberName, presence)
        missingPlans = info and (info.sendPlans or info.missing) or {}
    end
    if #missingPlans == 0 then
        return
    end
    if not self:CanSendRaidCheckNotif() then
        print(L("|cffff6666[Raidstrats.gg]|r Only the raid lead can send those."))
        return
    end

    local sendable = self:GetSendableReadyCheckNotePlans({ reload = true })
    local sendCount = #sendable
    if sendCount == 0 then
        print(L("|cffff6666[Raidstrats.gg]|r You don't have the note plans saved locally."))
        return
    end

    self:HideRaidCheckMemberContextMenu()

    local menu = self._readyCheckRaidCheckCtxMenu
    if not menu then
        menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        menu:SetSize(188, 40)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(540)
        menu:EnableMouse(true)
        if SetBackdrop then SetBackdrop(menu, UI.PANEL, UI.BORDER, 1) end

        local sendBtn = CreateFrame("Button", nil, menu, "BackdropTemplate")
        sendBtn:SetPoint("TOPLEFT", menu, "TOPLEFT", 6, -6)
        sendBtn:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -6, 6)
        if SetBackdrop then SetBackdrop(sendBtn, UI.ROW, UI.BORDER, 1) end
        local lbl = sendBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("CENTER")
        lbl:SetText(L("Send all note plans"))
        lbl:SetTextColor(0.92, 0.92, 0.92)
        sendBtn.label = lbl
        sendBtn:SetScript("OnEnter", function(s)
            s:SetBackdropColor(unpack(UI.ROW_HOV))
            lbl:SetTextColor(1, 1, 1)
        end)
        sendBtn:SetScript("OnLeave", function(s)
            s:SetBackdropColor(unpack(UI.ROW))
            lbl:SetTextColor(0.92, 0.92, 0.92)
        end)
        sendBtn:SetScript("OnClick", function()
            local target = strtrim(tostring(menu and menu.memberName or ""))
            Diar:HideRaidCheckMemberContextMenu()
            if menu then menu:Hide() end
            if target ~= "" then
                Diar:SendReadyCheckMissingPlansToMember(target)
            end
        end)
        menu.sendBtn = sendBtn
        menu:SetScript("OnHide", function()
            Diar:HideRaidCheckMemberContextDismissOverlay()
        end)
        self._readyCheckRaidCheckCtxMenu = menu
    end

    menu.memberName = memberName
    menu.missingPlans = missingPlans
    if menu.sendBtn and menu.sendBtn.label then
        menu.sendBtn.label:SetText(sendCount > 1 and L("Send all note plans (%d)"):format(sendCount) or L("Send note plan"))
    end
    menu:ClearAllPoints()
    if anchor then
        menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    else
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    end
    menu:Show()
    if menu.Raise then menu:Raise() end

    if not self._raidCheckMemberCtxDismiss then
        local o = CreateFrame("Button", "RaidstratsRaidCheckMemberCtxDismiss", UIParent)
        o:SetAllPoints(UIParent)
        o:SetFrameStrata("FULLSCREEN_DIALOG")
        o:EnableMouse(true)
        o:SetAlpha(0.001)
        self._raidCheckMemberCtxDismiss = o
    end
    local dismiss = self._raidCheckMemberCtxDismiss
    dismiss:SetFrameLevel(math.max(0, (menu:GetFrameLevel() or 0) - 1))
    dismiss:SetScript("OnClick", nil)
    dismiss:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" or button == "RightButton" then
            Diar:HideRaidCheckMemberContextMenu()
            if Diar._readyCheckRaidCheckCtxMenu then
                Diar._readyCheckRaidCheckCtxMenu:Hide()
            end
        end
    end)
    dismiss:Show()
end

function Diar:HideRaidCheckNotifPopup()
    if self._raidCheckNotifPopup then
        self._raidCheckNotifPopup:Hide()
    end
    if self._raidCheckBundleNotifPopup then
        self._raidCheckBundleNotifPopup:Hide()
    end
end

function Diar:OpenPlanFromRaidCheckNotif(planKey, planName, planId)
    planId = planId and tostring(planId) or ""
    if self:PlayerHasPlanKey(planKey, planId) then
        if planKey and planKey ~= "" and self.GetPlanIdentityKey then
            if self:GetPlanIdentityKey(self.plannerData) == planKey then
                if self.ShowPlannerViewer then self:ShowPlannerViewer() end
                return true
            end
            if self.FindSavedEntryIdForPlanKey then
                local id = self:FindSavedEntryIdForPlanKey(planKey, planId ~= "" and planId or nil)
                if id and self.LoadSavedPlanById then
                    self:LoadSavedPlanById(id, { openPlanner = true })
                    return true
                end
            end
        end
        if planName and planName ~= "" and self.LoadPlanByName and self:LoadPlanByName(planName) then
            if self.ShowPlannerViewer then self:ShowPlannerViewer() end
            return true
        end
    end
    return false
end

function Diar:ImportPlanFromRaidCheckNotif(sender, transferId, owner, planName)
    transferId = strtrim(tostring(transferId or ""))
    owner = strtrim(tostring(owner or ""))
    if transferId == "" or owner == "" then
        if self.ShowImportPlanDialog then self:ShowImportPlanDialog() end
        return false
    end

    if not sender or sender == "" then
        if self.ShowImportPlanDialog then self:ShowImportPlanDialog() end
        return false
    end

    self._incomingPlan = {
        owner = owner,
        id = transferId,
        chunks = {},
        total = nil,
        t = GetTime(),
        planName = planName,
        sender = sender,
    }

    -- Same fast path as chat share: REQ, then one AceComm PLAN: whisper (NORMAL).
    local prefix = self.COMM_PLAN_PREFIX or "RAIDSTRATS_PLAN"
    local whisperTo = (self.ResolveWhisperTarget and self:ResolveWhisperTarget(sender)) or sender
    if self.ArmShareRequestTimeout then
        self:ArmShareRequestTimeout(sender, transferId, L("requesting plan"))
    end
    self:SendCommMessage(prefix, "REQ:" .. transferId, "WHISPER", whisperTo, "NORMAL")

    local displayName = (planName and planName ~= "") and planName or L("Raid plan")
    self.plannerData = {
        planName = displayName,
        scenes = { { name = "Empty", items = {} } },
    }
    if self.OpenPlannerAfterShareImport then
        self:OpenPlannerAfterShareImport()
    elseif self.ShowPlannerViewer then
        self:ShowPlannerViewer()
    end

    if self.ShowImportProgress then
        self:ShowImportProgress(true, 0, nil, L("Requesting plan..."))
    end

    local who = sender and (Ambiguate and Ambiguate(sender, "short") or sender) or L("Raid leader")
    print(L("|cff00aaff[Raidstrats.gg]|r Grabbing \"%s\" from %s..."):format(
        planName and planName ~= "" and planName or L("raid plan"), who))
    return true
end

local function EnsureRaidCheckNotifPopupFrame(selfRef, globalName, fieldName)
    local f = selfRef[fieldName]
    if f and f.title and f.acceptBtn then
        return f
    end
    f = _G[globalName]
    if not (f and f.title and f.acceptBtn) then
        f = CreateFrame("Frame", globalName, UIParent, "BackdropTemplate")
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:EnableMouse(true)
        if SetBackdrop then SetBackdrop(f, UI.PANEL, UI.BORDER, 2) end
        tinsert(UISpecialFrames, globalName)

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.title:SetPoint("TOP", 0, -14)
        f.title:SetTextColor(0.92, 0.92, 0.92)

        f.msg = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.msg:SetPoint("TOP", f.title, "BOTTOM", 0, -10)
        f.msg:SetWidth(320)
        f.msg:SetJustifyH("CENTER")
        f.msg:SetTextColor(0.78, 0.80, 0.84)

        local function makeBtn(parent, text)
            local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
            b:SetSize(118, 28)
            if SetBackdrop then SetBackdrop(b, UI.ROW, UI.BORDER, 1) end
            local lbl = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            lbl:SetPoint("CENTER")
            lbl:SetText(text)
            lbl:SetTextColor(0.9, 0.9, 0.9)
            b.label = lbl
            b:SetScript("OnEnter", function(s)
                s:SetBackdropColor(unpack(UI.ROW_HOV))
                lbl:SetTextColor(1, 1, 1)
            end)
            b:SetScript("OnLeave", function(s)
                s:SetBackdropColor(unpack(UI.ROW))
                lbl:SetTextColor(0.9, 0.9, 0.9)
            end)
            return b
        end

        f.declineBtn = makeBtn(f, L("Not now"))
        f.declineBtn:SetPoint("BOTTOM", -62, 14)
        f.acceptBtn = makeBtn(f, L("Import plan"))
        f.acceptBtn:SetPoint("BOTTOM", 62, 14)
    end
    selfRef[fieldName] = f
    return f
end

function Diar:ShowRaidCheckNotifPopup(sender, planName, planKey, planId, transferId, owner)
    if not self:IsRaidCheckNotifsEnabled() then return end
    if self._raidCheckBundleNotifPopup then self._raidCheckBundleNotifPopup:Hide() end

    local who = sender and (Ambiguate and Ambiguate(sender, "short") or sender) or L("Raid leader")
    planName = (planName and planName ~= "") and planName or L("the raid plan")
    planId = planId and tostring(planId) or ""
    local hasPlan = self:PlayerHasPlanKey(planKey, planId)

    local f = EnsureRaidCheckNotifPopupFrame(self, "RaidstratsRaidCheckNotifPopup", "_raidCheckNotifPopup")
    f:SetSize(360, hasPlan and 148 or 158)
    f.title:SetText(hasPlan and L("Review the raid plan") or L("Import the raid plan"))
    if hasPlan then
        f.msg:SetText(L("%s wants you to open \"%s\" in the planner."):format(who, planName))
    else
        f.msg:SetText(L("%s wants you to review \"%s\".\nImport the plan to follow along."):format(who, planName))
    end
    if f.acceptBtn.label then
        f.acceptBtn.label:SetText(hasPlan and L("Open plan") or L("Import plan"))
    end

    f.declineBtn:SetScript("OnClick", function()
        Diar:HideRaidCheckNotifPopup()
    end)
    f.acceptBtn:SetScript("OnClick", function()
        Diar:HideRaidCheckNotifPopup()
        if hasPlan then
            Diar:OpenPlanFromRaidCheckNotif(planKey, planName, planId)
        else
            Diar:ImportPlanFromRaidCheckNotif(sender, transferId, owner, planName)
        end
    end)

    if self.PrepareModal then
        self:PrepareModal(f, self.plannerFrame or self.frame)
    end
    f:ClearAllPoints()
    f:SetPoint("CENTER")
    f:Show()
    if PlaySound then PlaySound(3190, "master") end
end

-- One modal for the full note-plan bundle (RNGB).
function Diar:ShowRaidCheckBundleNotifPopup(sender, linkLabel, count, owner)
    if not self:IsRaidCheckNotifsEnabled() then return end
    if self._raidCheckNotifPopup then self._raidCheckNotifPopup:Hide() end

    local who = sender and (Ambiguate and Ambiguate(sender, "short") or sender) or L("Raid leader")
    count = math.max(1, tonumber(count) or 1)
    linkLabel = strtrim(tostring(linkLabel or ""))
    if linkLabel == "" then return end

    local f = EnsureRaidCheckNotifPopupFrame(self, "RaidstratsRaidCheckBundleNotifPopup", "_raidCheckBundleNotifPopup")
    f:SetSize(360, 158)
    f.title:SetText(count == 1 and L("Import 1 plan") or L("Import %d plans"):format(count))
    f.msg:SetText(L("%s wants you to import the note plans.\nOne click grabs all %d."):format(who, count))
    if f.acceptBtn.label then
        f.acceptBtn.label:SetText(count == 1 and L("Import plan") or L("Import plans"))
    end

    f.declineBtn:SetScript("OnClick", function()
        Diar:HideRaidCheckNotifPopup()
    end)
    f.acceptBtn:SetScript("OnClick", function()
        Diar:HideRaidCheckNotifPopup()
        if Diar.RequestSharedPlan then
            Diar:RequestSharedPlan(sender, linkLabel)
        end
    end)

    if self.PrepareModal then
        self:PrepareModal(f, self.plannerFrame or self.frame)
    end
    f:ClearAllPoints()
    f:SetPoint("CENTER")
    f:Show()
    if PlaySound then PlaySound(3190, "master") end
end

function Diar:HandleRaidCheckNotifComm(msg, sender)
    if type(msg) ~= "string" or msg:sub(1, 4) ~= "RNOT" then return end
    if not self:IsRaidCheckNotifsEnabled() then return end
    local parts = SplitSep(msg, SEP)
    if parts[1] ~= "RNOT" then return end
    local planName = parts[2] or ""
    local planKey = parts[3] or ""
    local planId = parts[4] or ""
    local transferId = parts[5] or ""
    local owner = parts[6] or ""
    self:ShowRaidCheckNotifPopup(sender, planName, planKey, planId, transferId, owner)
end

function Diar:HandleRaidCheckNoteBundleComm(msg, sender)
    if type(msg) ~= "string" or msg:sub(1, 4) ~= "RNGB" then return end
    if not self:IsRaidCheckNotifsEnabled() then return end
    local parts = SplitSep(msg, SEP)
    if parts[1] ~= "RNGB" then return end
    local linkLabel = parts[2] or ""
    local count = tonumber(parts[3]) or 0
    local owner = parts[4] or ""
    self:ShowRaidCheckBundleNotifPopup(sender, linkLabel, count, owner)
end

local function EnsureRaidCheckExpandedHost(pf)
    if not pf then return nil end
    if not pf.raidCheckExpandedHost then
        local host = CreateFrame("Frame", nil, pf, "BackdropTemplate")
        if SetBackdrop then SetBackdrop(host, UI.PANEL, UI.BORDER, 1) end

        local hdr = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        hdr:SetPoint("TOPLEFT", host, "TOPLEFT", 12, -10)
        hdr:SetText(L("Raidcheck"))
        hdr:SetTextColor(0.92, 0.94, 0.98)
        host.title = hdr

        local summary = host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        summary:SetPoint("RIGHT", host, "RIGHT", -62, -10)
        summary:SetJustifyH("RIGHT")
        summary:SetTextColor(0.48, 0.52, 0.58)
        summary:SetText("")
        host.summary = summary

        local refreshBtn = CreateFrame("Button", nil, host)
        refreshBtn:SetSize(52, 20)
        refreshBtn:SetPoint("TOPRIGHT", host, "TOPRIGHT", -8, -6)
        local refreshLbl = refreshBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        refreshLbl:SetPoint("CENTER")
        refreshLbl:SetText(L("Refresh"))
        refreshLbl:SetTextColor(unpack(UI.LINK))
        refreshBtn:SetScript("OnEnter", function()
            refreshLbl:SetTextColor(unpack(UI.LINK_HOV))
        end)
        refreshBtn:SetScript("OnLeave", function()
            refreshLbl:SetTextColor(unpack(UI.LINK))
        end)
        refreshBtn:SetScript("OnClick", function()
            Diar:SendPlanViewPoll()
            Diar:RefreshRaidLeadView(pf)
        end)
        host.refreshBtn = refreshBtn

        host:Hide()
        pf.raidCheckExpandedHost = host
    end
    return pf.raidCheckExpandedHost
end

function Diar:ApplyRaidLeadViewLayout(pf)
    pf = pf or self.plannerFrame
    if not pf or not pf.savedPlansPanel then return end

    local panel = pf.savedPlansPanel
    local footer = pf.savedPlansFooter
    local title = pf.savedPlansTitle
    local count = pf.savedPlansCount
    local subtitle = pf.savedPlansSubtitle
    local searchBox = pf.savedPlansSearchBoxWrap or pf.savedPlansSearchBtn
    local raidFilterBtn = pf.savedPlansRaidFilterBtn
    local divider = pf.savedPlansDivider
    local scroll = pf.savedPlansScroll
    local bar = pf.raidCheckBar

    if not (panel and footer and title and divider and scroll) then return end

    -- Compact mode is canvas-only. Never show raidcheck/saved-plan side chrome here,
    -- even if this layout function is called by a later refresh.
    if pf.compactMode then
        if pf.raidCheckBar then pf.raidCheckBar:Hide() end
        if pf.raidLeadPanel then pf.raidLeadPanel:Hide() end
        if pf.raidLeadBottomDivider then pf.raidLeadBottomDivider:Hide() end
        if pf.raidCheckExpandedHost then pf.raidCheckExpandedHost:Hide() end
        return
    end

    local showRaidcheckControls = self:ShouldShowRaidCheckBar()
    local active = showRaidcheckControls and self:IsRaidCheckEnabled(pf)
    local useRaidcheckExpanded = active and self.IsRaidCheckExpandedEnabled and self:IsRaidCheckExpandedEnabled()

    if bar then
        bar:Show()
    end
    if pf.raidCheckChk then
        if showRaidcheckControls then pf.raidCheckChk:Show() else pf.raidCheckChk:Hide() end
    end
    if pf.raidCheckLabel then
        if showRaidcheckControls then pf.raidCheckLabel:Show() else pf.raidCheckLabel:Hide() end
    end
    if pf.raidCheckRefreshBtn then
        if active then pf.raidCheckRefreshBtn:Show() else pf.raidCheckRefreshBtn:Hide() end
    end
    if pf.raidCheckSummary then
        if active then pf.raidCheckSummary:Show() else pf.raidCheckSummary:Hide() end
    end
    if pf.raidLeadPanel then
        if active then pf.raidLeadPanel:Show() else pf.raidLeadPanel:Hide() end
    end
    if pf.raidLeadBottomDivider then
        if active then pf.raidLeadBottomDivider:Show() else pf.raidLeadBottomDivider:Hide() end
    end

    if useRaidcheckExpanded then
        local host = EnsureRaidCheckExpandedHost(pf)
        if host then
            local hostW = (pf.rightPanelW or (panel.GetWidth and panel:GetWidth()) or 248)
            host:ClearAllPoints()
            host:SetPoint("TOPLEFT", pf, "TOPRIGHT", 12, 0)
            host:SetPoint("BOTTOMLEFT", pf, "BOTTOMRIGHT", 12, 0)
            host:SetWidth(hostW)
            host:SetFrameStrata(pf:GetFrameStrata())
            host:SetFrameLevel((pf:GetFrameLevel() or 0) + 5)
            host:Show()
            if host.title then host.title:Show() end
            if host.summary and pf.raidCheckSummary then
                host.summary:SetText(pf.raidCheckSummary:GetText() or "")
                host.summary:Show()
            end
            if host.refreshBtn then
                if active then host.refreshBtn:Show() else host.refreshBtn:Hide() end
            end
        end
        panel:Show()

        if bar then
            -- Keep the existing raidcheck toggle/header where it already lives.
            if bar:GetParent() ~= panel then bar:SetParent(panel) end
            bar:Show()
        end
        if pf.raidLeadPanel then
            if host and pf.raidLeadPanel:GetParent() ~= host then pf.raidLeadPanel:SetParent(host) end
            pf.raidLeadPanel:ClearAllPoints()
            pf.raidLeadPanel:SetPoint("TOPLEFT", host or panel, "TOPLEFT", 8, -34)
            pf.raidLeadPanel:SetPoint("BOTTOMRIGHT", host or panel, "BOTTOMRIGHT", -8, 8)
            pf.raidLeadPanel:Show()
        end
        if pf.raidLeadBottomDivider then
            pf.raidLeadBottomDivider:Hide()
        end
        self:RefreshRaidLeadView(pf)
        if host and host.summary and pf.raidCheckSummary then
            host.summary:SetText(pf.raidCheckSummary:GetText() or "")
        end
        self:UpdateRaidCheckNotifBtn(pf)
        return
    end

    if pf.raidCheckExpandedHost then
        pf.raidCheckExpandedHost:Hide()
    end
    if bar and bar:GetParent() ~= panel then
        bar:SetParent(panel)
    end
    if pf.raidLeadPanel and pf.raidLeadPanel:GetParent() ~= panel then
        pf.raidLeadPanel:SetParent(panel)
    end
    panel:Show()

    if title then title:Show() end
    if count then count:Show() end
    if subtitle then subtitle:Show() end
    if searchBox then searchBox:Show() end
    if raidFilterBtn then raidFilterBtn:Show() end
    if divider then divider:Show() end
    if scroll then scroll:Show() end
    if footer then footer:Show() end

    local topAnchor = panel
    local topInset = -12

    if bar then
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -8)
        bar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -8)
        bar:SetHeight(RAID_CHECK_BAR_H)
        topAnchor = bar
        topInset = -6
    end

    if active and pf.raidLeadPanel then
        local panelH = panel:GetHeight() or 400
        local footerH = footer:GetHeight() or 72
        local barH = RAID_CHECK_BAR_H + 14
        local notifH = self:CanSendRaidCheckNotif() and (RAID_NOTIF_BTN_H + 8) or 0
        local raidH = math.max(RAID_VIEW_MIN_H, math.floor((panelH - footerH - barH - notifH - 24) * RAID_VIEW_FRAC))

        pf.raidLeadPanel:ClearAllPoints()
        pf.raidLeadPanel:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", -2, topInset)
        pf.raidLeadPanel:SetPoint("TOPRIGHT", topAnchor, "BOTTOMRIGHT", 2, topInset)
        pf.raidLeadPanel:SetHeight(raidH)

        if pf.raidLeadBottomDivider then
            pf.raidLeadBottomDivider:ClearAllPoints()
            pf.raidLeadBottomDivider:SetPoint("TOPLEFT", pf.raidLeadPanel, "BOTTOMLEFT", 0, -6)
            pf.raidLeadBottomDivider:SetPoint("TOPRIGHT", pf.raidLeadPanel, "BOTTOMRIGHT", 0, -6)
        end

        topAnchor = pf.raidLeadBottomDivider or pf.raidLeadPanel
        topInset = -10
    end

    title:ClearAllPoints()
    if bar or active then
        title:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", bar and 2 or 0, topInset)
    else
        title:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -12)
    end
    count:ClearAllPoints()
    count:SetPoint("LEFT", title, "RIGHT", 6, 0)
    if searchBox then
        searchBox:ClearAllPoints()
        searchBox:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
        searchBox:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
    end
    if raidFilterBtn then
        raidFilterBtn:ClearAllPoints()
        if searchBox then
            raidFilterBtn:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", 0, -6)
            raidFilterBtn:SetPoint("RIGHT", searchBox, "RIGHT", 0, 0)
        else
            raidFilterBtn:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
            raidFilterBtn:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
        end
    end
    if subtitle then
        subtitle:ClearAllPoints()
        subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
        subtitle:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
    end
    divider:ClearAllPoints()
    if raidFilterBtn then
        divider:SetPoint("TOP", raidFilterBtn, "BOTTOM", 0, -8)
    elseif searchBox then
        divider:SetPoint("TOP", searchBox, "BOTTOM", 0, -8)
    elseif subtitle then
        divider:SetPoint("TOP", subtitle, "BOTTOM", 0, -8)
    else
        divider:SetPoint("TOP", title, "BOTTOM", 0, -10)
    end
    divider:SetPoint("LEFT", panel, "LEFT", 10, 0)
    divider:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", -2, -8)
    scroll:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -6, 6)

    if active then
        self:RefreshRaidLeadView(pf)
        self:UpdateRaidCheckNotifBtn(pf)
    end
end

local function CreateRaidCheckNotifBtn(box, pf)
    local autoChk = CreateAnimatedCheckbox and CreateAnimatedCheckbox(box, nil)
    if autoChk then
        autoChk:SetSize(20, 20)
        autoChk:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 10, 37)
        autoChk:SetScript("OnClick", function(s)
            s.isChecked = not s.isChecked
            if s.UpdateVisuals then s:UpdateVisuals() end
            Diar:SetRaidCheckAutoSwitchEnabled(pf, s.isChecked)
        end)
        pf.raidCheckAutoSwitchChk = autoChk

        local autoLbl = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        autoLbl:SetPoint("LEFT", autoChk, "RIGHT", 6, 0)
        autoLbl:SetText(L("Auto-switch scene for all"))
        autoLbl:SetTextColor(0.66, 0.69, 0.74)
        autoChk:Hide()
        autoLbl:Hide()
        pf.raidCheckAutoSwitchLabel = autoLbl
    end

    local notifBtn = CreateFrame("Button", nil, box, "BackdropTemplate")
    notifBtn:SetHeight(RAID_NOTIF_BTN_H)
    notifBtn:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 8, 8)
    notifBtn:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 8)
    if SetBackdrop then SetBackdrop(notifBtn, UI.ROW, UI.BORDER, 1) end
    local notifLbl = notifBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    notifLbl:SetPoint("CENTER")
    notifLbl:SetText(L("Send notif"))
    notifLbl:SetTextColor(0.88, 0.88, 0.88)
    notifBtn:SetScript("OnEnter", function(s)
        s:SetBackdropColor(unpack(UI.ROW_HOV))
        notifLbl:SetTextColor(1, 1, 1)
    end)
    notifBtn:SetScript("OnLeave", function(s)
        s:SetBackdropColor(unpack(UI.ROW))
        notifLbl:SetTextColor(0.88, 0.88, 0.88)
    end)
    notifBtn:SetScript("OnClick", function()
        Diar:SendRaidCheckNotif()
    end)
    notifBtn:Hide()
    pf.raidCheckNotifBtn = notifBtn
    return notifBtn
end

function Diar:EnsureRaidLeadViewPanel(pf)
    if not pf then return end
    local panel = pf.savedPlansPanel
    if not panel then return end

    if pf.raidCheckBar and pf.raidCheckNotifBtn then return end

    if pf.raidCheckBar and not pf.raidCheckNotifBtn and pf.raidLeadPanel then
        CreateRaidCheckNotifBtn(pf.raidLeadPanel, pf)
        self:UpdateRaidCheckNotifBtn(pf)
        return
    end

    if pf.raidCheckBar then return end

    if pf.raidLeadPanel then
        pf.raidLeadPanel:Hide()
        pf.raidLeadPanel = nil
    end
    if pf.raidLeadBottomDivider then
        pf.raidLeadBottomDivider:Hide()
        pf.raidLeadBottomDivider = nil
    end

    local bar = CreateFrame("Frame", nil, panel)
    bar:SetHeight(RAID_CHECK_BAR_H)
    pf.raidCheckBar = bar

    local exportBtn = CreateButton and CreateButton(bar, L("EXPORT ROSTER")) or CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    if exportBtn.SetText then exportBtn:SetText(L("EXPORT ROSTER")) end
    exportBtn:SetHeight(22)
    exportBtn:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    exportBtn:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    exportBtn:SetScript("OnClick", function()
        if Diar.ShowRosterExportDialog then
            Diar:ShowRosterExportDialog()
        elseif Diar.CreateMainWindow then
            Diar:CreateMainWindow()
        end
    end)
    pf.rosterExportBtn = exportBtn

    local chk = CreateAnimatedCheckbox and CreateAnimatedCheckbox(bar, nil)
    if chk then
        chk:SetSize(20, 20)
        chk:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 1)
        chk:SetScript("OnClick", function(s)
            s.isChecked = not s.isChecked
            if s.UpdateVisuals then s:UpdateVisuals() end
            Diar:SetRaidCheckEnabled(pf, s.isChecked)
        end)
        pf.raidCheckChk = chk
    end

    local label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", chk or bar, chk and "RIGHT" or "LEFT", chk and 8 or 0, chk and 0 or 1)
    label:SetText(L("Raidcheck"))
    label:SetTextColor(0.78, 0.80, 0.84)
    pf.raidCheckLabel = label

    local summary = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("RIGHT", bar, "RIGHT", -56, 1)
    summary:SetPoint("LEFT", label, "RIGHT", 8, 0)
    summary:SetJustifyH("RIGHT")
    summary:SetTextColor(0.48, 0.52, 0.58)
    summary:SetText("")
    summary:Hide()
    pf.raidCheckSummary = summary

    local refreshBtn = CreateFrame("Button", nil, bar)
    refreshBtn:SetSize(52, 20)
    refreshBtn:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 1)
    local refreshLbl = refreshBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    refreshLbl:SetPoint("CENTER")
    refreshLbl:SetText(L("Refresh"))
    refreshLbl:SetTextColor(unpack(UI.LINK))
    refreshBtn:SetScript("OnEnter", function()
        refreshLbl:SetTextColor(unpack(UI.LINK_HOV))
    end)
    refreshBtn:SetScript("OnLeave", function()
        refreshLbl:SetTextColor(unpack(UI.LINK))
    end)
    refreshBtn:SetScript("OnClick", function()
        Diar:SendPlanViewPoll()
        Diar:RefreshRaidLeadView(pf)
    end)
    refreshBtn:Hide()
    pf.raidCheckRefreshBtn = refreshBtn

    local box = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    if SetBackdrop then SetBackdrop(box, UI.TOOLBAR, UI.BORDER, 1) end
    pf.raidLeadPanel = box

    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -6, 6)
    if SkinScrollBar then SkinScrollBar(scroll) end
    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetWidth((pf.savedPlansListW or 200) - 16)
    scrollChild:SetHeight(1)
    scroll:SetScrollChild(scrollChild)
    pf.raidLeadScroll = scroll
    pf.raidLeadScrollChild = scrollChild
    pf.raidLeadRows = {}

    CreateRaidCheckNotifBtn(box, pf)

    local bottomDivider = panel:CreateTexture(nil, "ARTWORK")
    bottomDivider:SetHeight(1)
    bottomDivider:SetColorTexture(unpack(UI.BORDER))
    pf.raidLeadBottomDivider = bottomDivider

    pf.raidCheckEnabled = false

    local oldOnShow = pf:GetScript("OnShow")
    pf:SetScript("OnShow", function(frame)
        if Diar.OnPlannerFrameShown then Diar:OnPlannerFrameShown() end
        if oldOnShow then oldOnShow(frame) end
    end)

    local oldOnHide = pf:GetScript("OnHide")
    pf:SetScript("OnHide", function(frame)
        if Diar.OnPlannerFrameHidden then Diar:OnPlannerFrameHidden() end
        if oldOnHide then oldOnHide(frame) end
    end)

    box:Hide()
    bar:Hide()
    self:ApplyRaidLeadViewLayout(pf)
end

function Diar:OnGroupRosterChangedForRaidLeadView()
    local pf = self.plannerFrame
    if pf and pf:IsShown() then
        if self.ApplyRaidLeadViewLayout then self:ApplyRaidLeadViewLayout(pf) end
        if self:IsRaidLeadViewActive() then
            self:SendPlanViewPoll()
        elseif self.UpdateRaidCheckNotifBtn then
            self:UpdateRaidCheckNotifBtn(pf)
        end
    end
end
