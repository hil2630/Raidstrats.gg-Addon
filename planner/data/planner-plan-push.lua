-- Raid leader: push in-place plan updates to group members on the same plan identity.
local addonName = ...
local AceAddon = LibStub("AceAddon-3.0")
local Addon =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)
if not Addon then return end
local Diar = Addon

local SEP = string.char(31)
local PLAN_UPDATE_TTL = 300
local PLAN_UPDATE_BATCH = 180
local UI = {
    PANEL   = {0.06, 0.06, 0.09, 0.96},
    BORDER  = {0.22, 0.24, 0.28, 1},
    ROW     = {0.09, 0.10, 0.13, 0.92},
    ROW_HOV = {0.14, 0.16, 0.20, 1},
    ACCENT  = {0.23, 0.51, 0.96, 1},
}
local SetBackdrop = Diar.SetBackdrop

local function CopyPlanData(val)
    if type(val) == "table" then
        local out = {}
        for k, v in pairs(val) do out[k] = CopyPlanData(v) end
        return out
    end
    return val
end

local function SplitSep(str)
    local out = {}
    local start = 1
    while true do
        local i = str:find(SEP, start, true)
        if not i then
            out[#out + 1] = str:sub(start)
            break
        end
        out[#out + 1] = str:sub(start, i - 1)
        start = i + 1
    end
    return out
end

local function CheckboxIsChecked(chk)
    if not chk then return false end
    if chk.GetChecked then return chk:GetChecked() and true or false end
    if chk.isChecked ~= nil then return chk.isChecked and true or false end
    return false
end

local function SenderLabel(sender)
    if not sender or sender == "" then return "Someone" end
    return Ambiguate and Ambiguate(sender, "short") or sender
end

local function PrunePlanUpdates(self)
    self._planUpdates = self._planUpdates or {}
    local now = GetTime()
    for id, entry in pairs(self._planUpdates) do
        if not entry or (now - (entry.t or 0)) > PLAN_UPDATE_TTL then
            self._planUpdates[id] = nil
        end
    end
end

-- Cross-player plan identity for push/sync — instanceKey isolates team copies of the same planId.
function Diar:GetPlanIdentityKey(data)
    data = data or self.plannerData
    if not data then return nil end
    if type(data.instanceKey) == "string" and data.instanceKey ~= "" then
        return "inst:" .. data.instanceKey
    end
    return nil
end

function Diar:AllowPlanIdPushFallback(channel)
    return channel == "RAID" or channel == "PARTY" or channel == "INSTANCE_CHAT"
end

function Diar:PlanDataMatchesPlanId(data, planId)
    if not data or not planId or planId == "" then return false end
    return tostring(data.planId or "") == tostring(planId)
end

function Diar:ReceiverHasMatchingPlan(planKey, opts)
    opts = opts or {}
    if planKey and self:GetPlanIdentityKey(self.plannerData) == planKey then
        return true
    end
    RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {} }
    for _, entry in ipairs(RaidstratsggSavedPlans.list) do
        if entry.data and self:GetPlanIdentityKey(entry.data) == planKey then
            return true
        end
    end

    -- Same raid/party: match public planId so teams sync after independent imports.
    -- Guild-only pushes stay instanceKey-only (avoids cross-team collisions in large guilds).
    local planId = opts.planId
    if planId and planId ~= "" and self:AllowPlanIdPushFallback(opts.channel) then
        if self:PlanDataMatchesPlanId(self.plannerData, planId) then
            return true
        end
        for _, entry in ipairs(RaidstratsggSavedPlans.list) do
            if self:PlanDataMatchesPlanId(entry.data, planId) then
                return true
            end
        end
    end
    return false
end

function Diar:IsPlanAutoImportEnabled(planKey, planId)
    if not planKey and not planId then return false end
    local s = self.GetPlannerSettings and self:GetPlannerSettings()
    local map = s and s.planAutoImport
    if not map then return false end
    if planKey and map[planKey] == true then return true end
    if planId and planId ~= "" then
        RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {} }
        for _, entry in ipairs(RaidstratsggSavedPlans.list) do
            if self:PlanDataMatchesPlanId(entry.data, planId) then
                local k = self:GetPlanIdentityKey(entry.data)
                if k and map[k] == true then return true end
            end
        end
        if self:PlanDataMatchesPlanId(self.plannerData, planId) then
            local k = self:GetPlanIdentityKey(self.plannerData)
            if k and map[k] == true then return true end
        end
    end
    return false
end

function Diar:SetPlanAutoImport(planKey, enabled)
    if not planKey then return end
    local s = self.GetPlannerSettings and self:GetPlannerSettings()
    if not s then return end
    s.planAutoImport = s.planAutoImport or {}
    if enabled then
        s.planAutoImport[planKey] = true
    else
        s.planAutoImport[planKey] = nil
    end
    if self.RefreshSavedPlansList then self:RefreshSavedPlansList() end
end

function Diar:FindSavedEntryIdForPlanKey(planKey, planId)
    if planKey and self:GetPlanIdentityKey(self.plannerData) == planKey then
        return self.plannerData and self.plannerData.savedEntryId
    end
    RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {} }
    for _, entry in ipairs(RaidstratsggSavedPlans.list) do
        if entry.data and planKey and self:GetPlanIdentityKey(entry.data) == planKey then
            return entry.id
        end
    end
    if planId and planId ~= "" then
        if self:PlanDataMatchesPlanId(self.plannerData, planId) then
            return self.plannerData and self.plannerData.savedEntryId
        end
        for _, entry in ipairs(RaidstratsggSavedPlans.list) do
            if self:PlanDataMatchesPlanId(entry.data, planId) then
                return entry.id
            end
        end
    end
    return nil
end

function Diar:PlanUpdateMatchesCurrent(planKey, planId)
    if planKey and self:GetPlanIdentityKey(self.plannerData) == planKey then
        return true
    end
    if planId and self:PlanDataMatchesPlanId(self.plannerData, planId) then
        return true
    end
    return false
end

function Diar:ApplyPlanUpdateFromData(newData, planKey)
    if not newData or not planKey then return false end
    local planId = newData.planId and tostring(newData.planId) or nil
    local entryId = self:FindSavedEntryIdForPlanKey(planKey, planId)

    if entryId then
        RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {} }
        for _, entry in ipairs(RaidstratsggSavedPlans.list) do
            if entry.id == entryId then
                newData.savedEntryId = entryId
                if self.SanitizePlanData then self:SanitizePlanData(newData) end
                entry.data = CopyPlanData(newData)
                entry.data.savedEntryId = entryId
                if type(newData.planName) == "string" and newData.planName ~= "" then
                    entry.planName = newData.planName
                end
                if newData.expansion then entry.expansion = newData.expansion end
                if newData.raid then entry.raid = newData.raid end
                if newData.boss then entry.boss = newData.boss end
                break
            end
        end
    end

    local pf = self.plannerFrame
    local matchesCurrent = self:PlanUpdateMatchesCurrent(planKey, planId)
    if matchesCurrent then
        local sceneIdx = pf and pf.selectedSceneIndex or 1
        newData.savedEntryId = entryId or (self.plannerData and self.plannerData.savedEntryId)
        self.plannerData = CopyPlanData(newData)
        if pf and pf:IsShown() then
            -- Rebuild planner chrome/tabs so new scenes appear immediately after push updates.
            if self.ShowPlannerViewer then
                self:ShowPlannerViewer({ reloadOnly = true })
            end
            pf = self.plannerFrame
        end
        if pf and pf:IsShown() then
            if not pf.nsrtSceneActive and self.ApplyNsrtAssignmentForPlannerView then
                self:ApplyNsrtAssignmentForPlannerView(sceneIdx)
            end
            if self.RefreshPlannerScene then self:RefreshPlannerScene() end
        end
    end

    if self.RefreshSavedPlansList then self:RefreshSavedPlansList() end
    return true
end

function Diar:TryCompletePlanUpdate(transferId)
    local entry = self._planUpdates and self._planUpdates[transferId]
    if not entry or entry.status == "declined" then return end
    if entry.status ~= "accepted" and entry.status ~= "auto" then return end
    local total = entry.total
    if not total or total < 1 then return end
    for i = 1, total do
        if not entry.chunks[i] then return end
    end

    local b64 = table.concat(entry.chunks, "")
    local data = self.DecodePlanFromBase64 and self:DecodePlanFromBase64(b64)
    self._planUpdates[transferId] = nil
    if self.HideImportProgress then self:HideImportProgress() end

    if not data then
        print("|cffff6666[Raidstrats.gg]|r Could not apply the plan update.")
        return
    end

    if self:ApplyPlanUpdateFromData(data, entry.planKey) then
        local who = SenderLabel(entry.sender)
        local label = entry.planName or data.planName or "plan"
        if data.instanceKey then
            entry.planKey = "inst:" .. data.instanceKey
        end
        self:OpenPlanAfterUpdateIfNeeded(entry.planKey, entry.planId, data)
        print(("|cff00aaff[Raidstrats.gg]|r Applied update to \"%s\" from %s."):format(label, who))
    else
        print("|cffff6666[Raidstrats.gg]|r Could not apply the plan update.")
    end
end

function Diar:OpenPlanAfterUpdateIfNeeded(planKey, planId, data)
    local pf = self.plannerFrame
    local plannerOpen = pf and pf:IsShown()
    if plannerOpen and self:PlanUpdateMatchesCurrent(planKey, planId) then
        return
    end
    local entryId = self:FindSavedEntryIdForPlanKey(planKey, planId)
    if entryId and self.LoadSavedPlanById then
        self:LoadSavedPlanById(entryId, { openPlanner = true })
        if self.LayoutOpenWindows then self:LayoutOpenWindows() end
        return
    end
    if data and self:PlanUpdateMatchesCurrent(planKey, planId) then
        if self.OpenPlannerAfterShareImport then
            self:OpenPlannerAfterShareImport({ reloadOnly = plannerOpen })
        elseif self.ShowPlannerViewer then
            self:ShowPlannerViewer(plannerOpen and { reloadOnly = true } or nil)
        end
    end
end

function Diar:HidePlanUpdatePopup()
    if self._planUpdatePopup then
        self._planUpdatePopup:Hide()
    end
end

function Diar:ShowPlanUpdatePopup(entry)
    if not entry then return end
    self:HidePlanUpdatePopup()

    local who = SenderLabel(entry.sender)
    local planLabel = (entry.planName and entry.planName ~= "") and entry.planName or "the plan"
    local f = CreateFrame("Frame", "RaidstratsPlanUpdatePopup", UIParent, "BackdropTemplate")
    f:SetSize(380, 168)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)
    if SetBackdrop then SetBackdrop(f, UI.PANEL, UI.BORDER, 2) end
    tinsert(UISpecialFrames, "RaidstratsPlanUpdatePopup")

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText(("Plan update — %s"):format(planLabel))
    title:SetTextColor(0.92, 0.92, 0.92)

    local msg = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    msg:SetPoint("TOP", title, "BOTTOM", 0, -10)
    msg:SetWidth(340)
    msg:SetJustifyH("CENTER")
    msg:SetText(("%s has updated \"%s\".\nWould you like to import the changes?"):format(who, planLabel))
    msg:SetTextColor(0.78, 0.80, 0.84)

    local autoChk = Diar.CreateAnimatedCheckbox and Diar.CreateAnimatedCheckbox(f, "Always import updates for this plan")
    if autoChk then
        autoChk:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -88)
        if autoChk.label then
            autoChk.label:SetFontObject("GameFontHighlightSmall")
            autoChk.label:SetWidth(320)
            autoChk.label:SetJustifyH("LEFT")
            autoChk.label:SetTextColor(0.72, 0.75, 0.80)
        end
    end

    local function makeBtn(text, x, onClick)
        local b = CreateFrame("Button", nil, f, "BackdropTemplate")
        b:SetSize(118, 28)
        b:SetPoint("BOTTOM", x, 14)
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

    makeBtn("Not now", -62, function()
        entry.status = "declined"
        Diar:HidePlanUpdatePopup()
    end)
    makeBtn("Import", 62, function()
        if autoChk and CheckboxIsChecked(autoChk) then
            Diar:SetPlanAutoImport(entry.planKey, true)
        end
        entry.status = "accepted"
        Diar:HidePlanUpdatePopup()
        if Diar.ShowImportProgress then
            Diar:ShowImportProgress(true, 0, nil, "Importing plan update...")
        end
        Diar:TryCompletePlanUpdate(entry.id)
    end)

    f:SetScript("OnHide", function()
        if Diar._planUpdatePopup == f then
            Diar._planUpdatePopup = nil
        end
    end)

    self._planUpdatePopup = f
    if Diar.PrepareModal then
        Diar:PrepareModal(f, self.plannerFrame or self.frame)
    end
    f:ClearAllPoints()
    f:SetPoint("CENTER")
    f:Show()
    PlaySound(3190, "master")
end

function Diar:HandlePlanUpdatePush(msg, sender, channel)
    local parts = SplitSep(msg)
    if parts[1] ~= "PUSH" or #parts < 4 then return end
    local transferId, planKey, planName, planId = parts[2], parts[3], parts[4], parts[5]
    if not transferId or transferId == "" or not planKey or planKey == "" then return end
    if not self:ReceiverHasMatchingPlan(planKey, { planId = planId, channel = channel }) then return end

    PrunePlanUpdates(self)
    self._planUpdates = self._planUpdates or {}
    local status = self:IsPlanAutoImportEnabled(planKey, planId) and "auto" or "pending"
    self._planUpdates[transferId] = {
        id = transferId,
        planKey = planKey,
        planName = planName,
        planId = planId,
        sender = sender,
        chunks = {},
        total = nil,
        status = status,
        t = GetTime(),
    }

    if status == "auto" then
        if self.ShowImportProgress then
            self:ShowImportProgress(true, 0, nil, "Importing plan update...")
        end
        local label = (planName and planName ~= "") and planName or "plan"
        print(("|cff00aaff[Raidstrats.gg]|r %s updated \"%s\" — importing..."):format(
            SenderLabel(sender), label))
    else
        self:ShowPlanUpdatePopup(self._planUpdates[transferId])
    end
end

function Diar:HandlePlanUpdateChunk(msg)
    local parts = SplitSep(msg)
    if parts[1] ~= "UPDD" or #parts < 5 then return end
    local transferId, iStr, nStr, chunk = parts[2], parts[3], parts[4], parts[5]
    local i, n = tonumber(iStr), tonumber(nStr)
    if not transferId or not i or not n or not chunk then return end

    PrunePlanUpdates(self)
    local entry = self._planUpdates and self._planUpdates[transferId]
    if not entry or entry.status == "declined" then return end

    entry.total = entry.total or n
    entry.chunks[i] = chunk
    entry.t = GetTime()

    local count = 0
    for idx = 1, entry.total do
        if entry.chunks[idx] then count = count + 1 end
    end
    if self.UpdateImportProgress then
        self:UpdateImportProgress(count, entry.total)
    end

    self:TryCompletePlanUpdate(transferId)
end

function Diar:SendPlanUpdateChunks(chan, transferId, payload)
    if not chan or not transferId or not payload or payload == "" then return false end
    local prefix = self.COMM_PLAN_PREFIX or "RAIDSTRATS_PLAN"
    local total = math.ceil(#payload / PLAN_UPDATE_BATCH)
    for j = 1, total do
        local start = (j - 1) * PLAN_UPDATE_BATCH + 1
        local chunk = payload:sub(start, start + PLAN_UPDATE_BATCH - 1)
        self:SendCommMessage(
            prefix,
            table.concat({ "UPDD", transferId, j, total, chunk }, SEP),
            chan,
            nil,
            "BULK"
        )
    end
    return true
end

function Diar:PushPlanUpdateToGroup()
    if not self.IsPushUpdateLeader or not self:IsPushUpdateLeader() then
        print("|cffff6666[Raidstrats.gg]|r Only the party or raid leader can push plan updates.")
        return false
    end
    local chan = self.GetGroupChatChannel and self:GetGroupChatChannel()
    if not chan then
        print("|cffff6666[Raidstrats.gg]|r Join a party, raid, or guild to push updates.")
        return false
    end

    local data = self.plannerData
    if not self:HasActiveSavedPlan() then
        print("|cffff6666[Raidstrats.gg]|r No plan loaded to push.")
        return false
    end

    self:EnsurePlanInstanceKey(data)
    if self.PersistCurrentPlanToSaved then
        self:PersistCurrentPlanToSaved()
    end

    local planKey = self:GetPlanIdentityKey(data)
    if not planKey then
        print("|cffff6666[Raidstrats.gg]|r Couldn't resolve a team instance for this plan. Reload the planner and try again.")
        return false
    end

    local payload = self.BuildSharePayload and self:BuildSharePayload(data)
    if not payload or payload == "" then
        print("|cffff6666[Raidstrats.gg]|r Couldn't prepare the plan update.")
        return false
    end

    local transferId = string.format("%x%x", time(), math.random(0, 0xFFFFFF))
    local planName = tostring(data.planName or "Raid plan"):gsub(SEP, "")
    local planId = (data.planId and tostring(data.planId) ~= "") and tostring(data.planId):gsub(SEP, "") or ""
    local prefix = self.COMM_PLAN_PREFIX or "RAIDSTRATS_PLAN"

    self:SendCommMessage(
        prefix,
        table.concat({ "PUSH", transferId, planKey, planName, planId }, SEP),
        chan,
        nil,
        "BULK"
    )
    self:SendPlanUpdateChunks(chan, transferId, payload)

    print(("|cff00aaff[Raidstrats.gg]|r Pushed plan update for \"%s\" to %s."):format(
        planName, chan:lower()))
    return true
end

function Diar:HasActiveSavedPlan()
    local data = self.plannerData
    if not data then return false end
    if data.planName == "No plan" then return false end
    if not data.savedEntryId then return false end
    if type(data.scenes) ~= "table" or #data.scenes == 0 then return false end
    return true
end

function Diar:UpdatePushUpdateButton()
    local pf = self.plannerFrame
    local btn = pf and pf.pushUpdateBtn
    local shareBtn = pf and pf.savedPlansShareBtn
    local hasActivePlan = self:HasActiveSavedPlan()

    if shareBtn then
        if hasActivePlan then
            shareBtn:Enable()
            shareBtn:SetAlpha(1)
            if shareBtn.label then shareBtn.label:SetTextColor(0.92, 0.92, 0.92) end
        else
            shareBtn:Disable()
            shareBtn:SetAlpha(0.45)
            if shareBtn.label then shareBtn.label:SetTextColor(0.55, 0.55, 0.55) end
        end
    end

    if not btn then return end
    local pushAllowed = hasActivePlan
        and self.IsPushUpdateLeader
        and self:IsPushUpdateLeader()
    if pushAllowed then
        btn:Enable()
        btn:SetAlpha(1)
        if btn.label then btn.label:SetTextColor(0.92, 0.92, 0.92) end
    else
        btn:Disable()
        btn:SetAlpha(0.45)
        if btn.label then btn.label:SetTextColor(0.55, 0.55, 0.55) end
    end
end
