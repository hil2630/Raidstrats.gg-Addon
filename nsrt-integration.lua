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
    local wantedEncID = encID and tonumber(encID) or nil

    local function noteHasRsggForEncounter(noteText)
        if type(noteText) ~= "string" or noteText == "" then return false end
        if not noteText:find("rsgg", 1, true) then return false end
        if not wantedEncID then return true end
        local headerEnc = noteText:match("EncounterID:(%d+)")
        if headerEnc and tonumber(headerEnc) == wantedEncID then
            return true
        end
        return false
    end

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

    -- On relog/reload NSRT active pointer can be stale/empty. Fallback to the
    -- configured autoload note for this encounter, then search reminders by encID.
    if (not noteHasRsggForEncounter(str)) and wantedEncID and NSRT.Reminders then
        local autoName = NSRT.AutoLoadNote and NSRT.AutoLoadNote[wantedEncID]
        local autoNote = autoName and NSRT.Reminders[autoName] or nil
        if noteHasRsggForEncounter(autoNote) then
            str = autoNote
        else
            for _, note in pairs(NSRT.Reminders) do
                if noteHasRsggForEncounter(note) then
                    str = note
                    break
                end
            end
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

local function ParsePhaseToken(raw)
    local phase = tonumber(raw)
    if not phase or phase < 1 then return 1 end
    return phase
end

local function PhaseKeyString(phase)
    phase = ParsePhaseToken(phase)
    local whole = math.floor(phase + 0.0000001)
    if math.abs(phase - whole) < 0.0001 then
        return tostring(whole)
    end
    local out = string.format("%.3f", phase)
    out = out:gsub("0+$", ""):gsub("%.$", "")
    return out
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
            local phase = line:match("ph:(%d*%.?%d+)") or line:match(";ph:(%d*%.?%d+)") or line:match(";ph(%d*%.?%d+)") or line:match("ph(%d*%.?%d+)")
            local sceneIndex = line:match("scene:(%d+)")
            local planToken = line:match("plan:([^;]+)")
            local dur = line:match("dur:(%d+)")
            local compact = line:match("compact:([^;]+)")
            local tag, tagNames, tagSpotMap = ParseTagField(line)
            time = time and tonumber(time)
            phase = ParsePhaseToken(phase)
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

local RegisterNsrtCallbacks
local TryHookNSRT

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
    if addon._readyCheckWatchActive and addon.TryOpenReadyCheckAssignments then
        addon:TryOpenReadyCheckAssignments(true)
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

local READY_CHECK_RETRY_INTERVAL = 0.65
local READY_CHECK_MAX_RETRIES = 6

function Raidstrats:CancelReadyCheckCloseTimer()
    if self._readyCheckCloseTimer then
        self._readyCheckCloseTimer:Cancel()
        self._readyCheckCloseTimer = nil
    end
end

function Raidstrats:CancelReadyCheckAssignmentWatchTimers()
    if self._readyCheckRetryTimer then
        self._readyCheckRetryTimer:Cancel()
        self._readyCheckRetryTimer = nil
    end
end

function Raidstrats:EndReadyCheckAssignmentWatch()
    self._readyCheckWatchActive = nil
    self._readyCheckRetryCount = nil
    self:CancelReadyCheckAssignmentWatchTimers()
    local pf = self.plannerFrame
    if not (pf and pf.readyCheckActive and self.CloseReadyCheckAssignments) then
        return
    end
    self:CancelReadyCheckCloseTimer()
    local grace = 5
    if self.GetReadyCheckGracePeriod then
        grace = tonumber(self:GetReadyCheckGracePeriod()) or grace
    end
    grace = math.max(0, grace)
    if grace <= 0 then
        self:CloseReadyCheckAssignments()
        return
    end
    self._readyCheckCloseTimer = C_Timer.NewTimer(grace, function()
        self._readyCheckCloseTimer = nil
        local frame = self.plannerFrame
        if frame and frame.readyCheckActive and self.CloseReadyCheckAssignments then
            self:CloseReadyCheckAssignments()
        end
    end)
end

function Raidstrats:TryOpenReadyCheckAssignments(fromReminderSync)
    if not self._readyCheckWatchActive then return false end
    if not self.IsReadyCheckAssignmentsEnabled or not self:IsReadyCheckAssignmentsEnabled() then
        return false
    end
    if self.CanOpenReadyCheckAssignmentsInCurrentGroup and not self:CanOpenReadyCheckAssignmentsInCurrentGroup() then
        return false
    end
    if not C_AddOns.IsAddOnLoaded("NorthernSkyRaidTools") then
        return false
    end
    TryHookNSRT(self)
    RegisterNsrtCallbacks(self)

    if self.plannerFrame and self.plannerFrame.readyCheckActive then
        return true
    end

    local ok = self.OpenReadyCheckAssignments and self:OpenReadyCheckAssignments({ silent = true })
    if ok then
        self:CancelReadyCheckAssignmentWatchTimers()
        self._readyCheckRetryCount = nil
        -- Once opened successfully, stop watching so manual close (ESC/X)
        -- doesn't re-open the compact popup from later reminder callbacks.
        self._readyCheckWatchActive = nil
        return true
    end

    self._readyCheckRetryCount = (self._readyCheckRetryCount or 0) + 1
    if self._readyCheckRetryCount >= READY_CHECK_MAX_RETRIES then
        self:CancelReadyCheckAssignmentWatchTimers()
        if self.OpenReadyCheckAssignments then
            self:OpenReadyCheckAssignments({ verbose = true })
        end
        return false
    end

    if not fromReminderSync then
        self:CancelReadyCheckAssignmentWatchTimers()
        self._readyCheckRetryTimer = C_Timer.After(READY_CHECK_RETRY_INTERVAL, function()
            self._readyCheckRetryTimer = nil
            self:TryOpenReadyCheckAssignments(false)
        end)
    end
    return false
end

function Raidstrats:BeginReadyCheckAssignmentWatch()
    if not self.IsReadyCheckAssignmentsEnabled or not self:IsReadyCheckAssignmentsEnabled() then
        return
    end
    if self.CanOpenReadyCheckAssignmentsInCurrentGroup and not self:CanOpenReadyCheckAssignmentsInCurrentGroup() then
        return
    end
    self:CancelReadyCheckCloseTimer()
    self._readyCheckWatchActive = true
    self._readyCheckRetryCount = 0
    self:CancelReadyCheckAssignmentWatchTimers()
    self:TryOpenReadyCheckAssignments(false)
end

-- CallbackHandler-1.0 invokes callbacks as fn([owner,] eventName, payload...),
-- and NSRT's NSAPI wrapper may or may not prepend an owner arg. Locate the
-- event name in the arg list and return everything after it.
local function ExtractCallbackArgs(eventName, ...)
    for i = 1, select("#", ...) do
        if select(i, ...) == eventName then
            return select(i + 1, ...)
        end
    end
    return ...
end

RegisterNsrtCallbacks = function(addon)
    if addon._nsrtCallbacksRegistered then return true end
    if not NSAPI or not NSAPI.RegisterCallback then return false end

    NSAPI.RegisterCallback(addon, "NSRT_PHASE", function(...)
        local phase, encID, testrun = ExtractCallbackArgs("NSRT_PHASE", ...)
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
    end)

    NSAPI.RegisterCallback(addon, "NSRT_HIDE_REMINDERS", function()
        if addon.HideRaidPlanScene then
            addon:HideRaidPlanScene()
        end
        if addon.OnEncounterEnd then
            addon:OnEncounterEnd()
        end
    end)

    NSAPI.RegisterCallback(addon, "NSRT_REMINDER_CHANGED", function()
        OnNsrtReminderChanged(addon)
    end)

    addon._nsrtCallbacksRegistered = true
    return true
end

TryHookNSRT = function(addon)
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

function Raidstrats:StopRsggTest(opts)
    opts = opts or {}
    local wasRunning = self.rsggTestActive == true
    self:CancelRsggTimers()
    if self.HideRaidPlanScene then
        self:HideRaidPlanScene()
    end
    self.rsggTestActive = false
    if self.RefreshPlannerNsrtAssignmentIfOpen then
        self:RefreshPlannerNsrtAssignmentIfOpen()
    end
    if not opts.silent then
        if wasRunning then
            print("|cff00aaff[Raidstrats.gg]|r Stopped local /rsggtest run.")
        else
            print("|cffff9900[Raidstrats.gg]|r No /rsggtest run is currently active.")
        end
    end
    return wasRunning
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
    if not encID then return end

    local testMode = opts.testMode == true
    if self.IsNsrtPopupsEnabled and not self:IsNsrtPopupsEnabled() then
        if not testMode then return end
        print("|cffff9900[Raidstrats.gg]|r NSRT popups are disabled in Settings — running test anyway.")
    end

    local byEnc = self.rsggCues and self.rsggCues[encID]
    if not byEnc then return end

    local phaseRuns = {}
    if phase then
        local cues = byEnc[phase]
        if cues and #cues > 0 then
            phaseRuns[#phaseRuns + 1] = { phase = phase, cues = cues }
        end
    elseif testMode then
        local orderedPhases = {}
        for ph, cues in pairs(byEnc) do
            if type(ph) == "number" and type(cues) == "table" and #cues > 0 then
                orderedPhases[#orderedPhases + 1] = ph
            end
        end
        table.sort(orderedPhases)
        for _, ph in ipairs(orderedPhases) do
            phaseRuns[#phaseRuns + 1] = { phase = ph, cues = byEnc[ph] }
        end
    else
        return
    end
    if #phaseRuns == 0 then return end

    local showBefore, showAfter = self:GetRsggTiming()
    local keepCompactOpen = self.IsNsrtCompactAlwaysOpenEnabled and self:IsNsrtCompactAlwaysOpenEnabled()
    local testLeadIn = 1
    self.rsggTimers = {}
    self.rsggHideTimers = {}
    self.rsggShowGeneration = 0
    local scheduled = 0
    local timerIdx = 0
    local phaseOffset = 0
    local firstPersistentCue, firstPersistentCueRef
    local firstPersistentShowAt = nil

    for _, run in ipairs(phaseRuns) do
        local runPhase = run.phase
        local cues = run.cues
        local baseTime = nil
        local phaseWindow = testLeadIn
        if testMode then
            baseTime = cues[1].time
            for _, cue in ipairs(cues) do
                if cue.time < baseTime then baseTime = cue.time end
                local cueAfter = (cue.dur and cue.dur > 0) and cue.dur or showAfter
                local rel = cue.time - baseTime
                local maxHide = testLeadIn + rel + cueAfter
                if maxHide > phaseWindow then phaseWindow = maxHide end
            end
        end

        for _, cue in ipairs(cues) do
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
                    showAt = phaseOffset + testLeadIn + math.max(0, rel - showBefore)
                    hideAt = phaseOffset + testLeadIn + rel + after
                else
                    showAt = math.max(0, cue.time - showBefore)
                    hideAt = cue.time + after
                end
                if keepCompactOpen and (firstPersistentShowAt == nil or showAt < firstPersistentShowAt) then
                    firstPersistentShowAt = showAt
                    firstPersistentCue = cue
                    firstPersistentCueRef = cuePlanRef
                end
                scheduled = scheduled + 1
                timerIdx = timerIdx + 1
                local slot = timerIdx
                self.rsggTimers[slot] = C_Timer.NewTimer(showAt, function()
                    if not self.ShowRaidPlanScene then return end
                    self.rsggShowGeneration = (self.rsggShowGeneration or 0) + 1
                    local gen = self.rsggShowGeneration
                    local ok = self:ShowRaidPlanScene(cue.sceneIndex, {
                        planName = cue.planName,
                        planRef = cuePlanRef,
                        planAlias = cue.planToken,
                        compact = cue.compact,
                        skipAutoHide = true,
                        forceShow = testMode or keepCompactOpen,
                        dur = cue.dur,
                        tag = cue.tag,
                        tagNames = cue.tagNames,
                        tagSpotMap = cue.tagSpotMap,
                    })
                    if ok then
                        if testMode then
                            print(("|cff00aaff[Raidstrats.gg]|r Test: scene %d (phase %d, note cue %ds)."):format(
                                cue.sceneIndex, runPhase, cue.time))
                        else
                            print(("|cff00aaff[Raidstrats.gg]|r Showing scene %d (phase %d, cue %ds, −%ds/+%ds)."):format(
                                cue.sceneIndex, runPhase, cue.time, showBefore, showAfter))
                        end
                    else
                        print(("|cffff6666[Raidstrats.gg]|r Failed to show scene %d — import a plan first (/rsimport)."):format(
                            cue.sceneIndex))
                    end
                    if not keepCompactOpen then
                        local hideDelay = math.max(0.1, hideAt - showAt)
                        self.rsggHideTimers[slot] = C_Timer.NewTimer(hideDelay, function()
                            if self.rsggShowGeneration == gen and self.HideRaidPlanScene then
                                self:HideRaidPlanScene()
                            end
                        end)
                    end
                end)
            end
        end

        if testMode and not phase then
            phaseOffset = phaseOffset + phaseWindow + 1
        end
    end

    if testMode and scheduled == 0 then
        print("|cffff6666[Raidstrats.gg]|r No cues matched your player (check NSRT tag/group names).")
    end
    if keepCompactOpen and scheduled > 0 and firstPersistentCue and self.ShowRaidPlanScene then
        self:ShowRaidPlanScene(firstPersistentCue.sceneIndex, {
            planName = firstPersistentCue.planName,
            planRef = firstPersistentCueRef,
            planAlias = firstPersistentCue.planToken,
            compact = firstPersistentCue.compact,
            skipAutoHide = true,
            forceShow = true,
            dur = firstPersistentCue.dur,
            tag = firstPersistentCue.tag,
            tagNames = firstPersistentCue.tagNames,
            tagSpotMap = firstPersistentCue.tagSpotMap,
        })
    end
end

function Raidstrats:OnNSRTPhase(phase)
    if not self.rsggEncounterID then return end
    phase = ParsePhaseToken(phase)
    local key = ("%d:%s"):format(self.rsggEncounterID, PhaseKeyString(phase))
    local now = GetTime()
    if self._lastNsrtPhaseKey == key and (now - (self._lastNsrtPhaseAt or 0)) < 2 then
        return
    end
    self._lastNsrtPhaseKey = key
    self._lastNsrtPhaseAt = now
    if self.IsRsggDebug and self:IsRsggDebug() and InCombatLockdown() then
        print(("|cff66ccff[Raidstrats.gg Debug]|r Phase %s started (encounter %d)."):format(
            PhaseKeyString(phase), self.rsggEncounterID))
    end
    self:ScheduleRsggCues(self.rsggEncounterID, phase)
end

function Raidstrats:OnEncounterStart(encID)
    if not encID or not C_AddOns.IsAddOnLoaded("NorthernSkyRaidTools") then return end
    TryHookNSRT(self)
    self.rsggTestActive = false
    self.rsggEncounterID = encID
    self:ReloadRsggCues(encID)

    local byPhase = self.rsggCues and self.rsggCues[encID]
    local phaseCount, cueCount = 0, 0
    if type(byPhase) == "table" then
        for ph, cues in pairs(byPhase) do
            if type(ph) == "number" and type(cues) == "table" and #cues > 0 then
                phaseCount = phaseCount + 1
                cueCount = cueCount + #cues
            end
        end
    end
    if cueCount > 0 then
        print(("|cff00aaff[Raidstrats.gg]|r Loaded %d rsgg cue(s) across %d phase(s) for encounter %d."):format(
            cueCount, phaseCount, encID))
    end

    self:OnNSRTPhase(1)
end

function Raidstrats:OnEncounterEnd()
    self:CancelReadyCheckCloseTimer()
    self:CancelRsggTimers()
    self.rsggTestActive = false
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

    local phase = opts.phase ~= nil and tonumber(opts.phase) or nil
    local byEnc = self.rsggCues and self.rsggCues[encID]
    local phaseCues = (phase and byEnc) and byEnc[phase] or nil
    if phase then
        if not phaseCues or #phaseCues == 0 then
            print(("|cffff6666[Raidstrats.gg]|r No rsgg cues for encounter %d phase %d."):format(encID, phase))
            return false
        end
    else
        local availablePhases = 0
        local totalCues = 0
        if type(byEnc) == "table" then
            for ph, cues in pairs(byEnc) do
                if type(ph) == "number" and type(cues) == "table" and #cues > 0 then
                    availablePhases = availablePhases + 1
                    totalCues = totalCues + #cues
                end
            end
        end
        if availablePhases == 0 then
            print(("|cffff6666[Raidstrats.gg]|r No rsgg cues for encounter %d."):format(encID))
            return false
        end
        phaseCues = { __allPhaseCount = availablePhases, __allCueCount = totalCues }
    end

    if not self.plannerData or not self.plannerData.scenes or #self.plannerData.scenes == 0 then
        print("|cffff6666[Raidstrats.gg]|r No plan loaded — import one first (/rsimport).")
    end

    -- Local-only test: never broadcast to group.

    if phase then
        print(("|cff00aaff[Raidstrats.gg]|r Test started for encounter %d phase %d — %d cue(s), compressed timing."):format(
            encID, phase, #phaseCues))
    else
        print(("|cff00aaff[Raidstrats.gg]|r Test started for encounter %d (all phases) — %d phase(s), %d cue(s), compressed timing."):format(
            encID, phaseCues.__allPhaseCount or 0, phaseCues.__allCueCount or 0))
    end
    self.rsggTestActive = true
    self:ScheduleRsggCues(encID, phase, { testMode = true })
    if self.RefreshPlannerNsrtAssignmentIfOpen then
        self:RefreshPlannerNsrtAssignmentIfOpen()
    end
    return true
end

function Raidstrats:RunRsggPhaseDebug(phase, encID)
    phase = tonumber(phase)
    if not phase or phase < 1 then
        print("|cffff6666[Raidstrats.gg]|r Usage: /rsggphase <phase> [encounterId]")
        return false
    end
    encID = encID and tonumber(encID) or self.rsggEncounterID
    if not encID then
        print("|cffff6666[Raidstrats.gg]|r No active encounter id. Provide one: /rsggphase <phase> <encounterId>")
        return false
    end

    local noteText = GetActiveNoteText(encID)
    if noteText == "" then
        print("|cffff6666[Raidstrats.gg]|r No active NSRT note.")
        return false
    end
    self.rsggEncounterID = encID
    self.rsggCues = ParseRsggCues(noteText)
    self.rsggGroups = ParseRsggGroups(noteText)
    self.rsggPlanBinds = ParseRsggPlanBinds(noteText)

    local byEnc = self.rsggCues and self.rsggCues[encID]
    local phaseCues = byEnc and byEnc[phase] or nil
    if not phaseCues or #phaseCues == 0 then
        print(("|cffff6666[Raidstrats.gg]|r No rsgg cues for encounter %d phase %d."):format(encID, phase))
        return false
    end

    if self.HideRaidPlanScene then
        self:HideRaidPlanScene()
    end
    self:ScheduleRsggCues(encID, phase, { testMode = true })
    if self.RefreshPlannerNsrtAssignmentIfOpen then
        self:RefreshPlannerNsrtAssignmentIfOpen()
    end
    print(("|cff00aaff[Raidstrats.gg]|r Forced phase %d for encounter %d (%d cue(s), local debug)."):format(
        phase, encID, #phaseCues))
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
    frame:RegisterEvent("READY_CHECK")
    frame:RegisterEvent("READY_CHECK_FINISHED")

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
        elseif event == "READY_CHECK" then
            if Raidstrats.BeginReadyCheckAssignmentWatch then
                Raidstrats:BeginReadyCheckAssignmentWatch()
            end
        elseif event == "READY_CHECK_FINISHED" then
            if Raidstrats.EndReadyCheckAssignmentWatch then
                Raidstrats:EndReadyCheckAssignmentWatch()
            end
        end
    end)

    self:RegisterChatCommand("rsggtest", function(input)
        input = strtrim(input or "")
        if strlower(input) == "stop" then
            Raidstrats:StopRsggTest()
            return
        end
        local encID, phase = input:match("^(%d+)%s+(%d*%.?%d+)$")
        if encID then
            encID = tonumber(encID)
            phase = tonumber(phase)
        else
            encID = tonumber(input)
            phase = nil
        end
        Raidstrats:RunRsggTest(encID, { phase = phase })
    end)

    self:RegisterChatCommand("rsggphase", function(input)
        input = strtrim(input or "")
        local phase, encID = input:match("^(%d*%.?%d+)%s+(%d+)$")
        if phase then
            Raidstrats:RunRsggPhaseDebug(phase, encID)
            return
        end
        phase = tonumber(input)
        Raidstrats:RunRsggPhaseDebug(phase, nil)
    end)

    self:RegisterChatCommand("rsggrc", function()
        if not Raidstrats.IsReadyCheckAssignmentsEnabled or not Raidstrats:IsReadyCheckAssignmentsEnabled() then
            print("|cffff9900[Raidstrats.gg]|r Enable \"Show assignments on readycheck\" in Settings first.")
            return
        end
        if Raidstrats.CanOpenReadyCheckAssignmentsInCurrentGroup and not Raidstrats:CanOpenReadyCheckAssignmentsInCurrentGroup() then
            print("|cffff9900[Raidstrats.gg]|r Ready check assignments are raid-only while \"Show only readycheck in raid group\" is enabled.")
            return
        end
        if Raidstrats.CloseReadyCheckAssignments then
            Raidstrats:CloseReadyCheckAssignments()
        end
        Raidstrats._readyCheckWatchActive = true
        Raidstrats._readyCheckRetryCount = 0
        if Raidstrats.CancelReadyCheckAssignmentWatchTimers then
            Raidstrats:CancelReadyCheckAssignmentWatchTimers()
        end
        if Raidstrats.TryOpenReadyCheckAssignments then
            Raidstrats:TryOpenReadyCheckAssignments(false)
        end
    end)
end
