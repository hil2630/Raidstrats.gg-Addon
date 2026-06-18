-- Raidstrats.gg Planner - NSRT scene view and group assignment highlighting
local addonName = ...
local AceAddon = LibStub("AceAddon-3.0")
local Addon =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)
if not Addon then return end
local Diar = Addon
local PUI = Diar.PlannerUI
local GetPlayerNameKey = PUI.GetPlayerNameKey
local RosterNameMatchesPlayer = PUI.RosterNameMatchesPlayer
local CleanRosterName

local function IsPlannerDebugEnabled()
    return Diar.GetPlannerSettings and Diar:GetPlannerSettings().debugMode == true
end

local function JoinNames(list)
    if type(list) ~= "table" or #list == 0 then return "-" end
    local out = {}
    for i = 1, #list do
        out[#out + 1] = tostring(list[i] or "")
    end
    return table.concat(out, ", ")
end

local function SpotMapToString(map)
    if type(map) ~= "table" then return "-" end
    local out = {}
    for k in pairs(map) do
        out[#out + 1] = tonumber(k) or 0
    end
    if #out == 0 then return "-" end
    table.sort(out)
    for i = 1, #out do out[i] = tostring(out[i]) end
    return table.concat(out, ",")
end

local function SpotNamesMapToString(spotMap)
    if type(spotMap) ~= "table" then return "-" end
    local keys = {}
    for spot in pairs(spotMap) do
        keys[#keys + 1] = tonumber(spot) or 0
    end
    if #keys == 0 then return "-" end
    table.sort(keys)
    local out = {}
    for _, spot in ipairs(keys) do
        local names = spotMap[spot]
        local cnt = (type(names) == "table") and #names or 0
        out[#out + 1] = ("%d:%d"):format(spot, cnt)
    end
    return table.concat(out, ";")
end

local function FlattenSpotMapNames(spotMap)
    if type(spotMap) ~= "table" then return nil end
    local out = {}
    local keys = {}
    for spot in pairs(spotMap) do
        keys[#keys + 1] = tonumber(spot) or 0
    end
    table.sort(keys)
    for _, spot in ipairs(keys) do
        local names = spotMap[spot]
        if type(names) == "table" then
            for _, nm in ipairs(names) do
                out[#out + 1] = nm
            end
        end
    end
    return out
end

local function BuildSpotNameMapFromList(names)
    local out = {}
    if type(names) ~= "table" then return out end
    for i, nm in ipairs(names) do
        local clean = CleanRosterName(nm)
        if clean and clean ~= "" then
            out[i] = clean
        end
    end
    return out
end

local function BuildSpotNameMapFromSpotMap(spotMap)
    local out = {}
    if type(spotMap) ~= "table" then return out end
    for spot, names in pairs(spotMap) do
        local s = tonumber(spot)
        if s and s >= 1 and type(names) == "table" and #names > 0 then
            local cleaned = {}
            for _, nm in ipairs(names) do
                local c = CleanRosterName(nm)
                if c and c ~= "" then
                    cleaned[#cleaned + 1] = c
                end
            end
            if #cleaned > 0 then
                out[s] = table.concat(cleaned, "/")
            end
        end
    end
    return out
end

function Diar:ClearPlannerDebugLines()
    self._plannerDebugLines = {}
    if self.UpdatePlannerDebugPanel then
        self:UpdatePlannerDebugPanel()
    end
end

function Diar:GetPlannerDebugDump()
    local lines = self._plannerDebugLines
    if type(lines) ~= "table" or #lines == 0 then
        return "No planner debug events yet."
    end
    return table.concat(lines, "\n")
end

function Diar:AppendPlannerDebugLine(msg)
    if not IsPlannerDebugEnabled() then return end
    local stamp = date("%H:%M:%S")
    local lines = self._plannerDebugLines or {}
    lines[#lines + 1] = ("[%s] %s"):format(stamp, tostring(msg or ""))
    while #lines > 220 do
        table.remove(lines, 1)
    end
    self._plannerDebugLines = lines
    if self.UpdatePlannerDebugPanel then
        self:UpdatePlannerDebugPanel()
    end
end

CleanRosterName = function(nm)
    if type(nm) ~= "string" then return nm end
    return nm:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

local function BuildMySpots(names)
    local myKey = GetPlayerNameKey()
    local mySpots = {}
    local playerName, playerRealm = UnitName("player")
    local fullPlayer = (playerName and playerName ~= "" and playerRealm and playerRealm ~= "")
        and (playerName .. "-" .. playerRealm)
        or (playerName or "")
    if myKey and names then
        for spot, nm in ipairs(names) do
            local cleaned = CleanRosterName(nm)
            local matched = RosterNameMatchesPlayer(cleaned, myKey)
            if matched then
                mySpots[spot] = true
            end
            if IsPlannerDebugEnabled() then
                Diar:AppendPlannerDebugLine(
                    ("BuildMySpots spot=%s player=%s full=%s myKey=%s raw=%s clean=%s matched=%s"):format(
                        tostring(spot),
                        tostring(playerName or "-"),
                        tostring(fullPlayer ~= "" and fullPlayer or "-"),
                        tostring(myKey or "-"),
                        tostring(nm or "-"),
                        tostring(cleaned or "-"),
                        tostring(matched)
                    )
                )
            end
        end
    elseif IsPlannerDebugEnabled() then
        Diar:AppendPlannerDebugLine(
            ("BuildMySpots skipped myKey=%s namesType=%s"):format(
                tostring(myKey or "-"),
                tostring(type(names))
            )
        )
    end
    return mySpots
end

local function BuildMySpotsFromMap(spotMap)
    local myKey = GetPlayerNameKey()
    local mySpots = {}
    local playerName, playerRealm = UnitName("player")
    local fullPlayer = (playerName and playerName ~= "" and playerRealm and playerRealm ~= "")
        and (playerName .. "-" .. playerRealm)
        or (playerName or "")
    if not myKey or type(spotMap) ~= "table" then return mySpots end
    for spot, names in pairs(spotMap) do
        local s = tonumber(spot)
        if s and s >= 1 and type(names) == "table" then
            for _, nm in ipairs(names) do
                local cleaned = CleanRosterName(nm)
                local matched = RosterNameMatchesPlayer(cleaned, myKey)
                if IsPlannerDebugEnabled() then
                    Diar:AppendPlannerDebugLine(
                        ("BuildMySpotsFromMap spot=%s player=%s full=%s myKey=%s raw=%s clean=%s matched=%s"):format(
                            tostring(s),
                            tostring(playerName or "-"),
                            tostring(fullPlayer ~= "" and fullPlayer or "-"),
                            tostring(myKey or "-"),
                            tostring(nm or "-"),
                            tostring(cleaned or "-"),
                            tostring(matched)
                        )
                    )
                end
                if matched then
                    mySpots[s] = true
                    break
                end
            end
        end
    end
    return mySpots
end

local function FindMyRosterIndex(names)
    local myKey = GetPlayerNameKey()
    if not myKey or type(names) ~= "table" then return nil end
    for spot, nm in ipairs(names) do
        if RosterNameMatchesPlayer(CleanRosterName(nm), myKey) then
            return spot
        end
    end
    return nil
end

local function CueContainsPlayer(cue, groups)
    local myKey = GetPlayerNameKey()
    if not myKey or type(cue) ~= "table" then return false end
    if cue.tagSpotMap then
        for _, names in pairs(cue.tagSpotMap) do
            if type(names) == "table" then
                for _, nm in ipairs(names) do
                    if RosterNameMatchesPlayer(CleanRosterName(nm), myKey) then
                        return true
                    end
                end
            end
        end
        return false
    end
    if cue.tagNames and #cue.tagNames > 0 then
        for _, nm in ipairs(cue.tagNames) do
            if RosterNameMatchesPlayer(CleanRosterName(nm), myKey) then
                return true
            end
        end
        return false
    end
    if cue.tag and cue.tag ~= "" and type(groups) == "table" then
        local roster = groups[tostring(cue.tag):lower()]
        if type(roster) == "table" then
            for _, nm in ipairs(roster) do
                if RosterNameMatchesPlayer(CleanRosterName(nm), myKey) then
                    return true
                end
            end
        end
    end
    return false
end

function Diar:GetPlannerSceneAssignmentOptions(sceneIndex)
    sceneIndex = tonumber(sceneIndex) or 1
    local options = {}
    local cues = self.rsggCues
    if type(cues) ~= "table" then return options, 1 end

    for _, byPhase in pairs(cues) do
        if type(byPhase) == "table" then
            for phaseNum, phaseCues in pairs(byPhase) do
                if type(phaseCues) == "table" then
                    for _, cue in ipairs(phaseCues) do
                        if cue.sceneIndex == sceneIndex and CueContainsPlayer(cue, self.rsggGroups) then
                            options[#options + 1] = {
                                tag = cue.tag,
                                tagNames = cue.tagNames,
                                tagSpotMap = cue.tagSpotMap,
                                time = tonumber(cue.time) or math.huge,
                                phase = tonumber(phaseNum) or tonumber(cue.phase) or 1,
                                sourceLineNo = tonumber(cue.sourceLineNo) or math.huge,
                                sourceLine = cue.sourceLine,
                            }
                        end
                    end
                end
            end
        end
    end

    table.sort(options, function(a, b)
        if a.time ~= b.time then return a.time < b.time end
        if a.phase ~= b.phase then return a.phase < b.phase end
        return a.sourceLineNo < b.sourceLineNo
    end)
    return options, 1
end

function Diar:GetSelectedPlannerSceneAssignment(sceneIndex)
    local pf = self.plannerFrame
    local options, defaultIndex = self:GetPlannerSceneAssignmentOptions(sceneIndex)
    if #options == 0 then return nil, nil, 0 end
    if not pf then return options[defaultIndex], defaultIndex, #options end
    pf.assignmentChoiceByScene = pf.assignmentChoiceByScene or {}
    local idx = tonumber(pf.assignmentChoiceByScene[sceneIndex]) or defaultIndex or 1
    idx = math.max(1, math.min(#options, math.floor(idx + 0.0001)))
    pf.assignmentChoiceByScene[sceneIndex] = idx
    return options[idx], idx, #options
end

function Diar:SetPlannerSceneAssignmentChoice(sceneIndex, choiceIndex)
    local pf = self.plannerFrame
    if not pf then return false end
    sceneIndex = tonumber(sceneIndex) or (pf.selectedSceneIndex or 1)
    local _, _, count = self:GetSelectedPlannerSceneAssignment(sceneIndex)
    if count <= 0 then return false end
    choiceIndex = tonumber(choiceIndex) or 1
    choiceIndex = math.max(1, math.min(count, math.floor(choiceIndex + 0.0001)))
    pf.assignmentChoiceByScene = pf.assignmentChoiceByScene or {}
    pf.assignmentChoiceByScene[sceneIndex] = choiceIndex
    if self.ApplyNsrtAssignmentForPlannerView then
        self:ApplyNsrtAssignmentForPlannerView(sceneIndex)
    end
    if self.RefreshPlannerScene then
        self:RefreshPlannerScene()
    end
    return true
end

function Diar:SetActiveGroupAssignment(tag, tagNames, tagSpotMap)
    local prev = self.activeGroup and self.activeGroup.mySpots or nil
    local names
    local mySpots
    local spotNames
    if tagSpotMap then
        names = FlattenSpotMapNames(tagSpotMap) or {}
        mySpots = BuildMySpotsFromMap(tagSpotMap)
        spotNames = BuildSpotNameMapFromSpotMap(tagSpotMap)
    elseif tagNames and #tagNames > 0 then
        names = tagNames
        mySpots = BuildMySpots(names)
        spotNames = BuildSpotNameMapFromList(names)
    elseif tag and tag ~= "" then
        local key = tostring(tag):lower()
        names = self.rsggGroups and self.rsggGroups[key]
        if not names then
            names = { tag }
        end
        mySpots = BuildMySpots(names)
        spotNames = BuildSpotNameMapFromList(names)
    else
        self.activeGroup = nil
        return
    end
    if not names then
        -- Tag set but no roster line found; still force spots grey (no green).
        self.activeGroup = { tag = tag, names = {}, mySpots = {} }
        return
    end
    self.activeGroup = { tag = tag, names = names, mySpots = mySpots, spotNames = spotNames }
    if IsPlannerDebugEnabled() then
        local pName, pRealm = UnitName("player")
        local pFull = (pName and pName ~= "" and pRealm and pRealm ~= "") and (pName .. "-" .. pRealm) or (pName or "")
        self:AppendPlannerDebugLine(
            ("SetActiveGroupAssignment player=%s full=%s myKey=%s"):format(
                tostring(pName or "-"),
                tostring(pFull ~= "" and pFull or "-"),
                tostring(GetPlayerNameKey() or "-")
            )
        )
    end
    self:AppendPlannerDebugLine(
        ("SetActiveGroupAssignment tag=%s names=[%s] spotMap=%s myIndex=%s mySpots=%s (prev=%s)"):format(
            tostring(tag or "-"),
            JoinNames(names),
            SpotNamesMapToString(tagSpotMap),
            tostring(FindMyRosterIndex(names) or "-"),
            SpotMapToString(mySpots),
            SpotMapToString(prev)
        )
    )
    if self.DebugLogCurrentSceneAssignment then
        self:DebugLogCurrentSceneAssignment("SetActiveGroupAssignment")
    end
end

-- Returns true when the player should see a tagged cue (in the roster, or no tag).
function Diar:IsPlayerInRsggGroup(tag, tagNames, tagSpotMap)
    local names
    if tagSpotMap then
        names = FlattenSpotMapNames(tagSpotMap)
    elseif tagNames and #tagNames > 0 then
        names = tagNames
    elseif tag and tag ~= "" then
        names = self.rsggGroups and self.rsggGroups[tostring(tag):lower()]
    else
        return true
    end
    if not names or #names == 0 then return false end
    local myKey = GetPlayerNameKey()
    if not myKey then return false end
    for _, nm in ipairs(names) do
        if RosterNameMatchesPlayer(CleanRosterName(nm), myKey) then
            return true
        end
    end
    return false
end

-- Pick the NSRT roster that applies to a scene (tagged cue first, then legacy group lines).
function Diar:FindNsrtAssignmentForScene(sceneIndex)
    sceneIndex = tonumber(sceneIndex) or 1
    local cues = self.rsggCues
    if cues then
        local chosenTag, chosenTagNames, chosenTagSpotMap = nil, nil, nil
        local matchCount = 0
        local chosenCue = nil
        local chosenLineNo = -1
        local chosenRank = -1
        local chosenHasPlayer = false
        local myKey = GetPlayerNameKey()
        local function cueRank(cue)
            if cue and cue.tagSpotMap then return 3 end
            if cue and cue.tagNames and #cue.tagNames > 0 then return 2 end
            if cue and cue.tag and cue.tag ~= "" then return 1 end
            return 0
        end
        local function cueHasPlayer(cue)
            if not myKey then return false end
            return CueContainsPlayer(cue, self.rsggGroups)
        end
        local function shouldChoose(cue)
            local lineNo = tonumber(cue and cue.sourceLineNo) or 0
            local rank = cueRank(cue)
            local hasPlayer = cueHasPlayer(cue)
            if not chosenCue then return true end
            -- When multiple rsgg lines target the same scene, prefer the one
            -- containing the current player assignment for this client.
            if hasPlayer ~= chosenHasPlayer then
                return hasPlayer
            end
            if lineNo > chosenLineNo then return true end
            if lineNo == chosenLineNo and rank > chosenRank then return true end
            return false
        end
        for _, byPhase in pairs(cues) do
            if type(byPhase) == "table" then
                for _, phaseCues in pairs(byPhase) do
                    if type(phaseCues) == "table" then
                        for _, cue in ipairs(phaseCues) do
                            if cue.sceneIndex == sceneIndex then
                                matchCount = matchCount + 1
                                if shouldChoose(cue) then
                                    chosenLineNo = tonumber(cue.sourceLineNo) or 0
                                    chosenRank = cueRank(cue)
                                    chosenHasPlayer = cueHasPlayer(cue)
                                    if cue.tagSpotMap then
                                        chosenTag = nil
                                        chosenTagNames = nil
                                        chosenTagSpotMap = cue.tagSpotMap
                                        chosenCue = cue
                                    elseif cue.tagNames and #cue.tagNames > 0 then
                                        chosenTag = nil
                                        chosenTagNames = cue.tagNames
                                        chosenTagSpotMap = nil
                                        chosenCue = cue
                                    elseif cue.tag and cue.tag ~= "" then
                                        chosenTag = cue.tag
                                        chosenTagNames = nil
                                        chosenTagSpotMap = nil
                                        chosenCue = cue
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        if chosenTag or (chosenTagNames and #chosenTagNames > 0) or chosenTagSpotMap then
            if self.AppendPlannerDebugLine and self.GetPlannerSettings and self:GetPlannerSettings().debugMode == true then
                self:AppendPlannerDebugLine(
                    ("FindNsrtAssignmentForScene scene=%s matches=%d picked=[%s] spotMap=%s hasPlayer=%s line=%s raw=%s"):format(
                        tostring(sceneIndex),
                        matchCount,
                        JoinNames(chosenTagNames or { chosenTag or "-" }),
                        SpotNamesMapToString(chosenTagSpotMap),
                        tostring(chosenHasPlayer),
                        tostring(chosenCue and chosenCue.sourceLineNo or "-"),
                        tostring(chosenCue and chosenCue.sourceLine or "-")
                    )
                )
            end
            return chosenTag, chosenTagNames, chosenTagSpotMap
        end
    end
    if self.rsggGroups then
        for tag, names in pairs(self.rsggGroups) do
            if type(names) == "table" and #names > 0 and self:IsPlayerInRsggGroup(tag) then
                return tag, nil
            end
        end
    end
    return nil, nil, nil
end

function Diar:RefreshPlannerNsrtAssignmentIfOpen()
    local pf = self.plannerFrame
    if not pf or not pf:IsShown() or pf.nsrtSceneActive then return end
    self:AppendPlannerDebugLine(("RefreshPlannerNsrtAssignmentIfOpen scene=%d"):format(pf.selectedSceneIndex or 1))
    if self.ApplyNsrtAssignmentForPlannerView then
        self:ApplyNsrtAssignmentForPlannerView(pf.selectedSceneIndex or 1)
    end
    if self.RefreshPlannerScene then
        self:RefreshPlannerScene()
    end
end

-- When the expanded planner is open, highlight the player's assigned spot from the active NSRT note.
function Diar:ApplyNsrtAssignmentForPlannerView(sceneIndex)
    if self.ReloadRsggCuesFromActiveNote then
        self:ReloadRsggCuesFromActiveNote()
    end
    local selected, selectedIndex, selectedTotal = self:GetSelectedPlannerSceneAssignment(sceneIndex)
    local tag, tagNames, tagSpotMap
    if selected then
        tag = selected.tag
        tagNames = selected.tagNames
        tagSpotMap = selected.tagSpotMap
    else
        tag, tagNames, tagSpotMap = self:FindNsrtAssignmentForScene(sceneIndex)
    end
    local dbgNames = tagNames
    if tagSpotMap then dbgNames = FlattenSpotMapNames(tagSpotMap) end
    local myIdx = FindMyRosterIndex(dbgNames)
    self:AppendPlannerDebugLine(
        ("ApplyNsrtAssignment scene=%s assign=%s/%s tag=%s tagNames=[%s] spotMap=%s myIndexInTag=%s"):format(
            tostring(sceneIndex or 1),
            tostring(selectedIndex or "-"),
            tostring(selectedTotal or "-"),
            tostring(tag or "-"),
            JoinNames(dbgNames),
            SpotNamesMapToString(tagSpotMap),
            tostring(myIdx or "-")
        )
    )
    if tag or (tagNames and #tagNames > 0) or tagSpotMap then
        self:SetActiveGroupAssignment(tag, tagNames, tagSpotMap)
    else
        self.activeGroup = nil
        self:AppendPlannerDebugLine("ApplyNsrtAssignment -> activeGroup cleared")
        if self.DebugLogCurrentSceneAssignment then
            self:DebugLogCurrentSceneAssignment("ApplyNsrtAssignmentCleared")
        end
    end
end

local function NormalizeBoundPlanRef(ref)
    if type(ref) ~= "string" then return nil end
    local raw = strtrim(ref)
    if raw == "" then return nil end
    -- Accept full planner URL: ...?view=<planId>[/scene]
    local view = raw:match("[?&]view=([^&#]+)")
    if view and view ~= "" then raw = view end
    -- Handle optional /scene suffix in view param values.
    local idOnly = raw:match("^([^/]+)/%d+$")
    if idOnly and idOnly ~= "" then raw = idOnly end
    return (raw ~= "" and raw) or nil
end

function Diar:LoadPlanByRef(planRef)
    local planId = NormalizeBoundPlanRef(planRef)
    if not planId then return false end
    if self.plannerData and tostring(self.plannerData.planId or "") == tostring(planId) then
        return true
    end
    RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {}, nextId = 1 }
    for _, entry in ipairs(RaidstratsggSavedPlans.list) do
        local entryPlanId = entry and entry.data and tostring(entry.data.planId or "")
        if entryPlanId ~= "" and entryPlanId == tostring(planId) then
            if self.ApplySavedPlanEntry then
                return self:ApplySavedPlanEntry(entry)
            end
            return false
        end
    end
    return false
end

function Diar:ShowRaidPlanScene(sceneIndex, opts)
    opts = opts or {}
    if not opts.forceShow and not self:IsNsrtPopupsEnabled() then
        return false
    end
    sceneIndex = tonumber(sceneIndex) or 1
    if opts.tagSpotMap or (opts.tagNames and #opts.tagNames > 0) or (opts.tag and opts.tag ~= "") then
        if not self:IsPlayerInRsggGroup(opts.tag, opts.tagNames, opts.tagSpotMap) then
            return false
        end
    end
    if opts.planRef and opts.planRef ~= "" then
        if not self:LoadPlanByRef(opts.planRef) then
            local alias = opts.planAlias and tostring(opts.planAlias) or "?"
            print(("|cffff6666[Raidstrats.gg]|r Could not resolve bound plan \"%s\" (ref: %s)."):format(
                alias, tostring(opts.planRef)))
            return false
        end
    end
    if (not (opts.planRef and opts.planRef ~= "")) and opts.planName and opts.planName ~= "" and not self:LoadPlanByName(opts.planName) then
        print(("|cffff6666[Raidstrats.gg]|r Could not find saved plan \"%s\"."):format(opts.planName))
        return false
    end
    if not self.plannerData or not self.plannerData.scenes or #self.plannerData.scenes == 0 then
        print("|cffff6666[Raidstrats.gg]|r No plan loaded — import one with /rsimport.")
        return false
    end
    sceneIndex = math.max(1, math.min(sceneIndex, #self.plannerData.scenes))

    if self.plannerFrame then
        self.plannerFrame.nsrtSceneActive = true
    end
    local wasShown = self.plannerFrame and self.plannerFrame:IsShown()
    self:ShowPlannerViewer({ reloadOnly = wasShown })

    local pf = self.plannerFrame
    if not pf then return false end

    pf.nsrtSceneActive = true
    pf.selectedSceneIndex = sceneIndex
    pf.__viewerViewportSceneIdx = nil
    self:SetActiveGroupAssignment(opts.tag, opts.tagNames, opts.tagSpotMap)
    self:UpdateSceneTabHighlight()
    self:StopPlannerAnimation()
    self:SetPlannerCompactMode(opts.compact ~= false)
    self:RefreshPlannerScene()
    if self.OnPlannerSceneChanged then self:OnPlannerSceneChanged() end
    Diar.ApplyPlannerChromeTransparent(pf)

    pf:Show()

    if self.nsrtSceneHideTimer then
        self.nsrtSceneHideTimer:Cancel()
        self.nsrtSceneHideTimer = nil
    end
    if not opts.skipAutoHide then
        local dur = tonumber(opts.dur)
        if dur and dur > 0 then
            self.nsrtSceneHideTimer = C_Timer.NewTimer(dur, function()
                Diar:HideRaidPlanScene()
            end)
        end
    end
    return true
end

function Diar:HideRaidPlanScene()
    if self.nsrtSceneHideTimer then
        self.nsrtSceneHideTimer:Cancel()
        self.nsrtSceneHideTimer = nil
    end
    local pf = self.plannerFrame
    local closedNsrtPopup = pf and pf.nsrtSceneActive
    if closedNsrtPopup then
        pf.nsrtSceneActive = nil
        -- Ensure NSRT compact zoom/pan never leaks into normal viewer mode.
        pf.viewerViewport = nil
        pf.__viewerViewportSceneIdx = nil
        pf.__viewportDisplayZoom = 1
        pf.__ignoreNextSceneViewportSync = true
        if pf.compactMode and pf:IsShown() then
            pf:Hide()
        end
    end
    if pf and pf:IsShown() and not pf.nsrtSceneActive then
        if self.ApplyNsrtAssignmentForPlannerView then
            self:ApplyNsrtAssignmentForPlannerView(pf.selectedSceneIndex or 1)
        end
        if self.RefreshPlannerScene then
            self:RefreshPlannerScene()
        end
    else
        self.activeGroup = nil
    end
end

