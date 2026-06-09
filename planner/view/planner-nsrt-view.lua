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
    if myKey and names then
        for spot, nm in ipairs(names) do
            if RosterNameMatchesPlayer(CleanRosterName(nm), myKey) then
                mySpots[spot] = true
            end
        end
    end
    return mySpots
end

local function BuildMySpotsFromMap(spotMap)
    local myKey = GetPlayerNameKey()
    local mySpots = {}
    if not myKey or type(spotMap) ~= "table" then return mySpots end
    for spot, names in pairs(spotMap) do
        local s = tonumber(spot)
        if s and s >= 1 and type(names) == "table" then
            for _, nm in ipairs(names) do
                if RosterNameMatchesPlayer(CleanRosterName(nm), myKey) then
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
        for _, byPhase in pairs(cues) do
            if type(byPhase) == "table" then
                for _, phaseCues in pairs(byPhase) do
                    if type(phaseCues) == "table" then
                        for _, cue in ipairs(phaseCues) do
                            if cue.sceneIndex == sceneIndex then
                                matchCount = matchCount + 1
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
        if chosenTag or (chosenTagNames and #chosenTagNames > 0) or chosenTagSpotMap then
            if self.AppendPlannerDebugLine and self.GetPlannerSettings and self:GetPlannerSettings().debugMode == true then
                self:AppendPlannerDebugLine(
                    ("FindNsrtAssignmentForScene scene=%s matches=%d picked=[%s] spotMap=%s line=%s raw=%s"):format(
                        tostring(sceneIndex),
                        matchCount,
                        JoinNames(chosenTagNames or { chosenTag or "-" }),
                        SpotNamesMapToString(chosenTagSpotMap),
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
    local tag, tagNames, tagSpotMap = self:FindNsrtAssignmentForScene(sceneIndex)
    local dbgNames = tagNames
    if tagSpotMap then dbgNames = FlattenSpotMapNames(tagSpotMap) end
    local myIdx = FindMyRosterIndex(dbgNames)
    self:AppendPlannerDebugLine(
        ("ApplyNsrtAssignment scene=%s tag=%s tagNames=[%s] spotMap=%s myIndexInTag=%s"):format(
            tostring(sceneIndex or 1),
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
    if opts.planName and opts.planName ~= "" and not self:LoadPlanByName(opts.planName) then
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

