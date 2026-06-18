-- NSRT note integration (RSGG-only): lines like time:11;ph:1;rsgg;scene:1
local addonName = ...
local AceAddon = LibStub("AceAddon-3.0")
local Raidstrats =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)

if not Raidstrats then return end

local function IsRaidDifficulty()
    local diff = select(3, GetInstanceInfo()) or 0
    return (diff >= 14 and diff <= 17) or diff == 220
end

local function ShouldHandleEncounter()
    if NSRT and NSRT.Settings and NSRT.Settings.Debug then return true end
    return IsRaidDifficulty()
end

local function GetActiveNoteText(encID)
    if not NSRT then return "" end
    local str = ""

    -- Named active reminder (what you select in the NSRT list)
    if NSRT.ActiveReminder and NSRT.Reminders and NSRT.Reminders[NSRT.ActiveReminder] then
        str = NSRT.Reminders[NSRT.ActiveReminder]
    elseif NSRT.StoredSharedReminder and NSRT.StoredSharedReminder ~= "" then
        str = NSRT.StoredSharedReminder
    end

    if NSAPI and NSAPI.GetReminderString then
        local personal, shared = NSAPI:GetReminderString(encID)
        -- Prefer live shared payload from NSAPI when available.
        -- NSRT.Reminders[ActiveReminder] can lag behind while editing.
        if shared and shared ~= "" then
            str = shared
        end
        local settings = NSRT.ReminderSettings or {}
        if settings.MRTNote and VMRT and VMRT.Note then
            local note = strtrim(VMRT.Note.Text1 or "")
            if note ~= "" then
                str = (str == "" and note) or (str .. "\n" .. note)
            end
            local persnote = strtrim(VMRT.Note.SelfText or "")
            if persnote ~= "" then
                str = (str == "" and persnote) or (str .. "\n" .. persnote)
            end
        end
        if settings.PersNote and personal and personal ~= "" then
            str = (str == "" and personal) or (str .. "\n" .. personal)
        end
    end

    return str or ""
end

local function ParseTagField(line)
    local rest, usedColon = nil, false
    local colonRest = line:match("tag:(.+)$")
    if colonRest then
        rest = colonRest
        usedColon = true
    else
        rest = line:match("tag%s+(.+)$")
    end
    if not rest or rest == "" then return nil, nil, nil end
    rest = rest:match("^([^;]+)") or rest
    rest = rest:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    rest = rest:gsub(",", " ")

    -- Indexed assignment format:
    --   tag 1: NameA NameB 2: NameC
    -- Returns map[spotIndex] = {names...}
    local spotMap = {}
    local foundIndexed = false
    local pos = 1
    while true do
        local s, e, spotText = rest:find("(%d+)%s*:%s*", pos)
        if not s then break end
        foundIndexed = true
        local nextS = rest:find("(%d+)%s*:%s*", e + 1)
        local chunk = nextS and rest:sub(e + 1, nextS - 1) or rest:sub(e + 1)
        local names = {}
        for nm in chunk:gmatch("%S+") do
            names[#names + 1] = nm
        end
        local spot = tonumber(spotText)
        if spot and spot >= 1 and #names > 0 then
            spotMap[math.floor(spot + 0.0001)] = names
        end
        if not nextS then break end
        pos = nextS
    end
    if foundIndexed then
        local hasAny = false
        for _ in pairs(spotMap) do
            hasAny = true
            break
        end
        if hasAny then
            return nil, nil, spotMap
        end
        return nil, nil, nil
    end

    local parts = {}
    for nm in rest:gmatch("%S+") do
        parts[#parts + 1] = nm
    end
    if #parts == 0 then return nil, nil, nil end
    -- tag:Group1 — single token after colon is a group key (rsggGroup1: line).
    if usedColon and #parts == 1 then
        return parts[1], nil, nil
    end
    -- tag NameA NameB or tag:NameA NameB — inline roster (positional spots).
    return nil, parts, nil
end

local function ParseRsggCues(noteText)
    local cues = {}
    if not noteText or noteText == "" then return cues end
    if not noteText:match("\n$") then
        noteText = noteText .. "\n"
    end
    local activeEncID = nil
    local lineNo = 0
    for line in noteText:gmatch("([^\n]*)\n") do
        lineNo = lineNo + 1
        if line:find("EncounterID:", 1, true) then
            local id = line:match("EncounterID:(%d+)")
            if id then activeEncID = tonumber(id) end
        end
        if line:find("rsgg", 1, true) then
            local encID = activeEncID
            if not encID then
                -- Accept one-line compact forms that include EncounterID together with cue text.
                local inline = line:match("EncounterID:(%d+)")
                encID = inline and tonumber(inline) or nil
            end
            -- Be tolerant of legacy/manual typos like "time4" (missing colon).
            local time = line:match("time:(%d*%.?%d+)") or line:match("time(%d*%.?%d+)")
            local phase = line:match("ph:(%d+)") or line:match(";ph:(%d+)") or line:match(";ph(%d+)") or line:match("ph(%d+)")
            local sceneIndex = line:match("scene:(%d+)")
            local planToken = line:match("plan:([^;]+)")
            local dur = line:match("dur:(%d+)")
            local compact = line:match("compact:([^;]+)")
            local tag, tagNames, tagSpotMap = ParseTagField(line)
            time = time and tonumber(time)
            phase = phase and tonumber(phase) or 1
            sceneIndex = sceneIndex and tonumber(sceneIndex)
            planToken = planToken and strtrim(planToken) or nil
            if encID and encID ~= 0 and time and sceneIndex then
                cues[encID] = cues[encID] or {}
                cues[encID][phase] = cues[encID][phase] or {}
                cues[encID][phase][#cues[encID][phase] + 1] = {
                    time = time,
                    sceneIndex = sceneIndex,
                    -- Legacy semantics: plan:<value> used saved plan name directly.
                    -- New semantics: when value matches a bind alias, resolve to that ref first.
                    planName = planToken,
                    planToken = planToken,
                    dur = dur and tonumber(dur) or 30,
                    compact = compact ~= "false",
                    tag = tag,
                    tagNames = tagNames,
                    tagSpotMap = tagSpotMap,
                    sourceLine = line,
                    sourceLineNo = lineNo,
                }
            end
        end
    end
    return cues
end

local function NormalizePlanBindKey(raw)
    if type(raw) ~= "string" then return nil end
    local trimmed = strtrim(raw)
    if trimmed == "" then return nil end
    return strlower(trimmed)
end

-- Parse plan bindings from NSRT note, e.g.:
--   rsgg-bind;plan:A;ref:abcd1234
-- Returns map keyed by lowercased plan alias => ref string.
local function ParseRsggPlanBinds(noteText)
    local binds = {}
    if not noteText or noteText == "" then return binds end
    if not noteText:match("\n$") then
        noteText = noteText .. "\n"
    end
    for line in noteText:gmatch("([^\n]*)\n") do
        if line:find("rsgg%-bind", 1, false) then
            local planAlias = line:match("plan:([^;]+)")
            local planRef = line:match("ref:([^;]+)")
            local key = NormalizePlanBindKey(planAlias)
            local ref = planRef and strtrim(planRef) or nil
            if key and ref and ref ~= "" then
                binds[key] = ref
            end
        end
    end
    return binds
end

-- Roster lines map names to spots positionally, e.g.:
--   rsggGroup1: Name1 Name2 Name3 Name4
-- Name at position i is assigned to spot i. Returns { group1 = {"Name1",...}, ... }
-- keyed by lowercased tag.
local function ParseRsggGroups(noteText)
    local groups = {}
    if not noteText or noteText == "" then return groups end
    if not noteText:match("\n$") then
        noteText = noteText .. "\n"
    end
    for line in noteText:gmatch("([^\n]*)\n") do
        local tag, rest = line:match("^%s*rsgg(%w+)%s*:%s*(.+)$")
        if tag and rest then
            rest = rest:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub(",", " ")
            local names = {}
            for nm in rest:gmatch("%S+") do
                names[#names + 1] = nm
            end
            if #names > 0 then
                groups[tag:lower()] = names
            end
        end
    end
    return groups
end

local function ResolveCuePlanRef(addon, cue)
    if type(cue) ~= "table" then return nil end
    local key = NormalizePlanBindKey(cue.planToken or cue.planName)
    if not key then return nil end
    local binds = addon and addon.rsggPlanBinds
    if type(binds) ~= "table" then return nil end
    local ref = binds[key]
    if type(ref) ~= "string" or ref == "" then return nil end
    return ref
end

local function FindNSI()
    if not NSAPI then return nil end
    if not debug or not debug.getupvalue then return nil end
    local fns = {
        NSAPI.GetReminderString,
        NSAPI.DebugEncounter,
        NSAPI.RegisterCallback,
    }
    for _, fn in ipairs(fns) do
        if type(fn) == "function" then
            for i = 1, 32 do
                local name, val = debug.getupvalue(fn, i)
                if not name then break end
                if type(val) == "table" and val.StartReminders and val.EventHandler then
                    return val
                end
            end
        end
    end
    return nil
end

local function OnNsrtReminderChanged(addon)
    if addon.AppendPlannerDebugLine then
        local pf = addon.plannerFrame
        addon:AppendPlannerDebugLine(("NSRT_REMINDER_CHANGED scene=%s"):format(
            tostring((pf and pf.selectedSceneIndex) or 1)))
    end
    if addon.ReloadRsggCuesFromActiveNote then
        addon:ReloadRsggCuesFromActiveNote()
    elseif addon.rsggEncounterID then
        addon:ReloadRsggCues(addon.rsggEncounterID)
    end
    if addon.RefreshPlannerNsrtAssignmentIfOpen then
        addon:RefreshPlannerNsrtAssignmentIfOpen()
    else
        local pf = addon.plannerFrame
        if pf and pf:IsShown() and not pf.nsrtSceneActive and addon.ApplyNsrtAssignmentForPlannerView then
            addon:ApplyNsrtAssignmentForPlannerView(pf.selectedSceneIndex or 1)
            if addon.RefreshPlannerScene then
                addon:RefreshPlannerScene()
            end
        end
    end
end

local function RegisterNsrtCallbacks(addon)
    if addon._nsrtCallbacksRegistered then return true end
    if not NSAPI or not NSAPI.RegisterCallback then return false end

    NSAPI:RegisterCallback("NSRT_PHASE", function(phase, encID, testrun)
        if testrun then return end
        phase = tonumber(phase) or 1
        encID = encID and tonumber(encID) or nil
        if encID then
            addon.rsggEncounterID = encID
            addon:ReloadRsggCues(encID)
        end
        if addon.HideRaidPlanScene then
            addon:HideRaidPlanScene()
        end
        if addon.OnNSRTPhase then
            addon:OnNSRTPhase(phase)
        end
    end, addon)

    NSAPI:RegisterCallback("NSRT_HIDE_REMINDERS", function()
        if addon.HideRaidPlanScene then
            addon:HideRaidPlanScene()
        end
        if addon.OnEncounterEnd then
            addon:OnEncounterEnd()
        end
    end, addon)

    NSAPI:RegisterCallback("NSRT_REMINDER_CHANGED", function()
        OnNsrtReminderChanged(addon)
    end, addon)

    addon._nsrtCallbacksRegistered = true
    return true
end

local function TryHookNSRT(addon)
    if addon._nsrtHooked then return true end
    RegisterNsrtCallbacks(addon)

    local nsI = FindNSI()
    if nsI then
        hooksecurefunc(nsI, "StartReminders", function(_, phase, testrun)
            if not testrun and addon.OnNSRTPhase then
                addon:OnNSRTPhase(phase)
            end
        end)

        hooksecurefunc(nsI, "HideAllReminders", function(_, fullReset)
            if addon.HideRaidPlanScene then
                addon:HideRaidPlanScene()
            end
            if fullReset and addon.OnEncounterEnd then
                addon:OnEncounterEnd()
            end
        end)

        hooksecurefunc(nsI, "EventHandler", function(_, e, wowevent, internal, ...)
            if not internal then return end
            if e == "ENCOUNTER_START" then
                local encID = ...
                if encID and addon.OnEncounterStart then
                    addon:OnEncounterStart(encID)
                end
            elseif e == "ENCOUNTER_END" then
                if addon.OnEncounterEnd then
                    addon:OnEncounterEnd()
                end
            end
        end)
    end

    -- Fallback when debug.getupvalue is unavailable
    if NSAPI and NSAPI.DebugEncounter then
        hooksecurefunc(NSAPI, "DebugEncounter", function(encID, stop)
            if stop then
                if addon.OnEncounterEnd then addon:OnEncounterEnd() end
            elseif encID and addon.OnEncounterStart then
                addon:OnEncounterStart(encID)
            end
        end)
    end

    addon._nsrtHooked = true
    return true
end

function Raidstrats:CancelRsggTimers()
    if self.rsggTimers then
        for _, timer in ipairs(self.rsggTimers) do
            if timer and timer.Cancel then timer:Cancel() end
        end
    end
    if self.rsggHideTimers then
        for _, timer in ipairs(self.rsggHideTimers) do
            if timer and timer.Cancel then timer:Cancel() end
        end
    end
    self.rsggTimers = nil
    self.rsggHideTimers = nil
    self.rsggShowGeneration = 0
end

function Raidstrats:GetRsggTiming()
    local before, after = 0, 0
    if self.GetRsggShowBefore then before = self:GetRsggShowBefore() end
    if self.GetRsggShowAfter then after = self:GetRsggShowAfter() end
    return before, after
end

function Raidstrats:ReloadRsggCues(encID)
    encID = encID or self.rsggEncounterID
    if not encID then return end
    local note = GetActiveNoteText(encID)
    self.rsggCues = ParseRsggCues(note)
    self.rsggGroups = ParseRsggGroups(note)
    self.rsggPlanBinds = ParseRsggPlanBinds(note)
end

-- Load rsgg cues/groups from the currently active NSRT note (works outside encounter too).
function Raidstrats:ReloadRsggCuesFromActiveNote()
    if not C_AddOns.IsAddOnLoaded("NorthernSkyRaidTools") then return false end
    local encID = self.rsggEncounterID
    local note = GetActiveNoteText(encID)
    if (not note or note == "") and not encID then
        note = GetActiveNoteText(nil)
    end
    if not note or note == "" then
        self.rsggCues = {}
        self.rsggGroups = {}
        self.rsggPlanBinds = {}
        return false
    end
    if not encID then
        local parsed = note:match("EncounterID:(%d+)")
        encID = parsed and tonumber(parsed) or nil
    end
    self.rsggCues = ParseRsggCues(note)
    self.rsggGroups = ParseRsggGroups(note)
    self.rsggPlanBinds = ParseRsggPlanBinds(note)
    return true
end

function Raidstrats:ScheduleRsggCues(encID, phase, opts)
    opts = opts or {}
    self:CancelRsggTimers()
    if not encID or not phase then return end

    local testMode = opts.testMode == true
    if self.IsNsrtPopupsEnabled and not self:IsNsrtPopupsEnabled() then
        if not testMode then return end
        print("|cffff9900[Raidstrats.gg]|r NSRT popups are disabled in Settings — running test anyway.")
    end

    local byEnc = self.rsggCues and self.rsggCues[encID]
    local cues = byEnc and byEnc[phase]
    if not cues or #cues == 0 then return end

    local showBefore, showAfter = self:GetRsggTiming()
    local testLeadIn = 1
    local baseTime = nil
    if testMode then
        baseTime = cues[1].time
        for _, cue in ipairs(cues) do
            if cue.time < baseTime then baseTime = cue.time end
        end
    end

    self.rsggTimers = {}
    self.rsggHideTimers = {}
    self.rsggShowGeneration = 0
    local scheduled = 0

    for i, cue in ipairs(cues) do
        local skip = false
        if cue.tagSpotMap then
            skip = self.IsPlayerInRsggGroup and not self:IsPlayerInRsggGroup(nil, nil, cue.tagSpotMap)
        elseif cue.tagNames and #cue.tagNames > 0 then
            skip = self.IsPlayerInRsggGroup and not self:IsPlayerInRsggGroup(nil, cue.tagNames)
        elseif cue.tag and cue.tag ~= "" then
            skip = self.IsPlayerInRsggGroup and not self:IsPlayerInRsggGroup(cue.tag)
        end
        if skip then
            -- Same scene can fire for multiple groups; skip cues you're not rostered on.
        else
            local cuePlanRef = ResolveCuePlanRef(self, cue)
            local after = (cue.dur and cue.dur > 0) and cue.dur or showAfter
            local showAt, hideAt
            if testMode and baseTime then
                local rel = cue.time - baseTime
                showAt = testLeadIn + math.max(0, rel - showBefore)
                hideAt = testLeadIn + rel + after
            else
                showAt = math.max(0, cue.time - showBefore)
                hideAt = cue.time + after
            end
            scheduled = scheduled + 1
            self.rsggTimers[i] = C_Timer.NewTimer(showAt, function()
                if not self.ShowRaidPlanScene then return end
                self.rsggShowGeneration = (self.rsggShowGeneration or 0) + 1
                local gen = self.rsggShowGeneration
                local ok = self:ShowRaidPlanScene(cue.sceneIndex, {
                    planName = cue.planName,
                    planRef = cuePlanRef,
                    planAlias = cue.planToken,
                    compact = cue.compact,
                    skipAutoHide = true,
                    forceShow = testMode,
                    dur = cue.dur,
                    tag = cue.tag,
                    tagNames = cue.tagNames,
                    tagSpotMap = cue.tagSpotMap,
                })
                if ok then
                    if testMode then
                        print(("|cff00aaff[Raidstrats.gg]|r Test: scene %d (phase %d, note cue %ds)."):format(
                            cue.sceneIndex, phase, cue.time))
                    else
                        print(("|cff00aaff[Raidstrats.gg]|r Showing scene %d (phase %d, cue %ds, −%ds/+%ds)."):format(
                            cue.sceneIndex, phase, cue.time, showBefore, showAfter))
                    end
                else
                    print(("|cffff6666[Raidstrats.gg]|r Failed to show scene %d — import a plan first (/rsimport)."):format(
                        cue.sceneIndex))
                end
                local hideDelay = math.max(0.1, hideAt - showAt)
                self.rsggHideTimers[i] = C_Timer.NewTimer(hideDelay, function()
                    if self.rsggShowGeneration == gen and self.HideRaidPlanScene then
                        self:HideRaidPlanScene()
                    end
                end)
            end)
        end
    end

    if testMode and scheduled == 0 then
        print("|cffff6666[Raidstrats.gg]|r No cues matched your player (check NSRT tag/group names).")
    end
end

function Raidstrats:OnNSRTPhase(phase)
    if not self.rsggEncounterID then return end
    phase = tonumber(phase) or 1
    local key = ("%d:%d"):format(self.rsggEncounterID, phase)
    local now = GetTime()
    if self._lastNsrtPhaseKey == key and (now - (self._lastNsrtPhaseAt or 0)) < 2 then
        return
    end
    self._lastNsrtPhaseKey = key
    self._lastNsrtPhaseAt = now
    self:ScheduleRsggCues(self.rsggEncounterID, phase)
end

function Raidstrats:OnEncounterStart(encID)
    if not encID or not C_AddOns.IsAddOnLoaded("NorthernSkyRaidTools") then return end
    TryHookNSRT(self)
    self.rsggEncounterID = encID
    self:ReloadRsggCues(encID)

    local phase1 = self.rsggCues and self.rsggCues[encID] and self.rsggCues[encID][1]
    if phase1 and #phase1 > 0 then
        print(("|cff00aaff[Raidstrats.gg]|r Loaded %d rsgg cue(s) for encounter %d."):format(#phase1, encID))
    end

    self:OnNSRTPhase(1)
end

function Raidstrats:OnEncounterEnd()
    self:CancelRsggTimers()
    if self.HideRaidPlanScene then
        self:HideRaidPlanScene()
    end
    self.rsggEncounterID = nil
    self._lastNsrtPhaseKey = nil
    self._lastNsrtPhaseAt = nil
end

local function ResolveEncIdFromCues(cues, preferredEncID, noteEncID)
    preferredEncID = preferredEncID and tonumber(preferredEncID) or nil
    noteEncID = noteEncID and tonumber(noteEncID) or nil
    if preferredEncID and cues[preferredEncID] then return preferredEncID end
    if noteEncID and cues[noteEncID] then return noteEncID end
    if preferredEncID then return preferredEncID end
    if noteEncID then return noteEncID end
    for id in pairs(cues) do
        if type(id) == "number" then return id end
    end
    return nil
end

function Raidstrats:RunRsggTest(encID, opts)
    opts = opts or {}
    if not C_AddOns.IsAddOnLoaded("NorthernSkyRaidTools") then
        print("|cffff6666[Raidstrats.gg]|r Northern Sky Raid Tools is not loaded.")
        return false
    end
    TryHookNSRT(self)

    local noteText = GetActiveNoteText(encID)
    if noteText == "" then
        print("|cffff6666[Raidstrats.gg]|r No active NSRT note. Open NSRT, save your note, and click it so it shows as active.")
        return false
    end

    local noteEncID = noteText:match("EncounterID:(%d+)")
    noteEncID = noteEncID and tonumber(noteEncID) or nil
    encID = encID and tonumber(encID) or noteEncID
    if not encID then
        print("|cffff6666[Raidstrats.gg]|r Note needs EncounterID:#### on the first line.")
        return false
    end

    self.rsggEncounterID = encID
    self.rsggCues = ParseRsggCues(noteText)
    self.rsggGroups = ParseRsggGroups(noteText)
    self.rsggPlanBinds = ParseRsggPlanBinds(noteText)
    encID = ResolveEncIdFromCues(self.rsggCues, encID, noteEncID)
    if not encID then
        print("|cffff6666[Raidstrats.gg]|r No rsgg lines in active note. Add: time:5;ph:1;rsgg;scene:1")
        return false
    end
    self.rsggEncounterID = encID

    local phase = tonumber(opts.phase) or 1
    local phaseCues = self.rsggCues[encID] and self.rsggCues[encID][phase]
    if not phaseCues or #phaseCues == 0 then
        print(("|cffff6666[Raidstrats.gg]|r No rsgg cues for encounter %d phase %d."):format(encID, phase))
        return false
    end

    if not self.plannerData or not self.plannerData.scenes or #self.plannerData.scenes == 0 then
        print("|cffff6666[Raidstrats.gg]|r No plan loaded — import one first (/rsimport).")
    end

    if not opts.fromRemote then
        local chan = self.GetGroupChatChannel and self:GetGroupChatChannel()
        if chan then
            local prefix = self.COMM_PLAN_PREFIX or "RAIDSTRATS_PLAN"
            self:SendCommMessage(
                prefix,
                ("RSGGTEST:%d:%d"):format(encID, phase),
                chan,
                nil,
                "NORMAL"
            )
            print(("|cff00aaff[Raidstrats.gg]|r Broadcasting NSRT test to %s..."):format(
                chan == "INSTANCE_CHAT" and "instance" or chan:lower()))
        end
    elseif opts.sender and opts.sender ~= "" then
        local who = Ambiguate and Ambiguate(opts.sender, "short") or opts.sender
        print(("|cff00aaff[Raidstrats.gg]|r NSRT test started by %s."):format(who))
    end

    print(("|cff00aaff[Raidstrats.gg]|r Test started for encounter %d phase %d — %d cue(s), compressed timing."):format(
        encID, phase, #phaseCues))
    self:ScheduleRsggCues(encID, phase, { testMode = true })
    if self.RefreshPlannerNsrtAssignmentIfOpen then
        self:RefreshPlannerNsrtAssignmentIfOpen()
    end
    return true
end

function Raidstrats:InitNSRTIntegration()
    if self._nsrtIntegrationFrame then return end

    local frame = CreateFrame("Frame")
    self._nsrtIntegrationFrame = frame
    frame:RegisterEvent("ADDON_LOADED")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("ENCOUNTER_START")
    frame:RegisterEvent("ENCOUNTER_END")

    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "ADDON_LOADED" then
            if (...) == "NorthernSkyRaidTools" then
                RegisterNsrtCallbacks(Raidstrats)
                TryHookNSRT(Raidstrats)
            end
        elseif event == "PLAYER_LOGIN" then
            if C_AddOns.IsAddOnLoaded("NorthernSkyRaidTools") then
                RegisterNsrtCallbacks(Raidstrats)
                TryHookNSRT(Raidstrats)
            end
        elseif event == "ENCOUNTER_START" then
            if not ShouldHandleEncounter() then return end
            Raidstrats:OnEncounterStart(...)
        elseif event == "ENCOUNTER_END" then
            Raidstrats:OnEncounterEnd()
        end
    end)

    self:RegisterChatCommand("rsggtest", function(input)
        input = strtrim(input or "")
        local encID, phase = input:match("^(%d+)%s+(%d+)$")
        encID = encID and tonumber(encID) or tonumber(input)
        phase = phase and tonumber(phase) or 1
        Raidstrats:RunRsggTest(encID, { phase = phase })
    end)
end
