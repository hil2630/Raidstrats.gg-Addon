-- Raidstrats.gg Planner - combat-safe macro actions
local addonName = ...
local AceAddon = LibStub("AceAddon-3.0")
local Addon =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)
if not Addon then return end

local Diar = Addon
local SEP = string.char(31)
local MAX_COMMAND_LEN = 24
local MAX_LABEL_LEN = 80
local MAX_TARGETS = 40

local function L(key)
    return RSGG_L and RSGG_L(key) or key
end

local function Trim(value)
    return strtrim(tostring(value or ""))
end

local function SafeField(value, maxLen)
    local out = tostring(value or ""):gsub(SEP, ""):gsub("[%z\1-\30\127]", "")
    if maxLen and #out > maxLen then out = out:sub(1, maxLen) end
    return out
end

local function NameKey(value)
    local out = SafeField(value, 80):lower()
    if out == "" then return nil end
    return out
end

local function ShortName(value)
    local out = SafeField(value, 80)
    if Ambiguate and out ~= "" then out = Ambiguate(out, "short") end
    return out:match("^([^%-]+)") or out
end

local function UnitNameWithRealm(unit)
    local name, realm
    if UnitFullName then
        name, realm = UnitFullName(unit)
    else
        name = UnitName(unit)
    end
    if not name or name == "" then return nil end
    if realm and realm ~= "" and not name:find("-", 1, true) then
        return name .. "-" .. realm, name
    end
    return name, name
end

local function PlayerFullName()
    return UnitNameWithRealm("player")
end

local function NamesMatch(left, right)
    local a, b = NameKey(left), NameKey(right)
    if not a or not b then return false end
    if a == b then return true end
    if a:find("-", 1, true) and b:find("-", 1, true) then return false end
    return ShortName(a):lower() == ShortName(b):lower()
end

local function IsHexColor(value)
    return type(value) == "string" and value:match("^#%x%x%x%x%x%x$") ~= nil
end

local function NormalizeCommand(value)
    local out = Trim(value):lower():gsub("%s+", "-"):gsub("[^%w_%-]", "")
    if #out > MAX_COMMAND_LEN then out = out:sub(1, MAX_COMMAND_LEN) end
    return out
end

local function NormalizeMacroId(value)
    local out = SafeField(value, 64):gsub("[^%w_%-]", "")
    if out == "" then return nil end
    return out
end

local function NormalizeTargets(value)
    local out, seen = {}, {}
    if type(value) ~= "table" then return out end
    for _, raw in ipairs(value) do
        local id = SafeField(raw, 96)
        if id ~= "" and not seen[id] then
            out[#out + 1] = id
            seen[id] = true
            if #out >= MAX_TARGETS then break end
        end
    end
    return out
end

function Diar:GeneratePlannerMacroId()
    local stamp = tostring(time and time() or 0)
    local rand = tostring(math.random(100000, 999999))
    return "macro-" .. stamp .. "-" .. rand
end

function Diar:NormalizePlannerMacro(raw)
    if type(raw) ~= "table" then return nil end
    local macroType = raw.type
    if macroType ~= "claim-next" and macroType ~= "set-object" then return nil end
    local scope = raw.scope == "global" and "global" or "plan"
    if macroType == "set-object" then scope = "plan" end
    local macroId = NormalizeMacroId(raw.id)
    local command = NormalizeCommand(raw.command or raw.name)
    local name = SafeField(Trim(raw.name), 48)
    local targets = macroType == "set-object" and NormalizeTargets(raw.targets) or {}
    local sceneIndex = math.max(1, math.floor(tonumber(raw.sceneIndex) or 1))
    if not macroId or command == "" or name == "" then return nil end
    if macroType == "set-object" and #targets ~= 1 then return nil end
    local label = SafeField(raw.label, MAX_LABEL_LEN)
    local fill = IsHexColor(raw.fill) and raw.fill:lower() or nil
    local stroke = IsHexColor(raw.stroke) and raw.stroke:lower() or nil
    return {
        id = macroId,
        name = name,
        command = command,
        type = macroType,
        scope = scope,
        sceneIndex = sceneIndex,
        targets = targets,
        label = label,
        fill = fill,
        stroke = stroke,
    }
end

function Diar:GetPlannerPlanMacros(data)
    data = data or self.plannerData
    local out = {}
    if not data or type(data.macros) ~= "table" then return out end
    for _, raw in ipairs(data.macros) do
        local normalized = self:NormalizePlannerMacro(raw)
        if normalized and normalized.scope ~= "global" then out[#out + 1] = normalized end
    end
    return out
end

function Diar:GetPlannerGlobalMacros()
    RaidstratsggSettings = RaidstratsggSettings or {}
    local out = {}
    for _, raw in ipairs(type(RaidstratsggSettings.plannerGlobalMacros) == "table"
        and RaidstratsggSettings.plannerGlobalMacros or {}) do
        local normalized = self:NormalizePlannerMacro(raw)
        if normalized and normalized.type == "claim-next" then
            normalized.scope = "global"
            out[#out + 1] = normalized
        end
    end
    return out
end

function Diar:GetPlannerMacros(data)
    local out = self:GetPlannerPlanMacros(data)
    for _, macro in ipairs(self:GetPlannerGlobalMacros()) do out[#out + 1] = macro end
    return out
end

function Diar:FindPlannerMacro(data, token)
    token = Trim(token):lower()
    if token == "" then return nil end
    local planMacros = self:GetPlannerPlanMacros(data)
    local globalMacros = self:GetPlannerGlobalMacros()
    for _, macro in ipairs(planMacros) do
        if macro.id:lower() == token then return macro end
    end
    for _, macro in ipairs(globalMacros) do
        if macro.id:lower() == token then return macro end
    end
    local command = NormalizeCommand(token)
    for _, macro in ipairs(globalMacros) do
        if macro.command == command then return macro end
    end
    for _, macro in ipairs(planMacros) do
        if macro.command == command then return macro end
    end
    return nil
end

function Diar:GetPlannerMacroPlanKey(data)
    data = data or self.plannerData
    if self.GetPlanIdentityKey then
        local key = self:GetPlanIdentityKey(data)
        if key and key ~= "" then return key end
    end
    if data and data.planId and tostring(data.planId) ~= "" then
        return "id:" .. SafeField(data.planId, 96)
    end
    return nil
end

function Diar:GetPlannerMacroPlanData(planKey)
    if not planKey or planKey == "" then return nil end
    if self:GetPlannerMacroPlanKey(self.plannerData) == planKey then
        return self.plannerData
    end
    RaidstratsggSavedPlans = RaidstratsggSavedPlans or { list = {} }
    for _, entry in ipairs(RaidstratsggSavedPlans.list or {}) do
        if entry.data and self:GetPlannerMacroPlanKey(entry.data) == planKey then
            return entry.data
        end
    end
    return nil
end

local function FindSceneItem(data, sceneIndex, itemId)
    local scene = data and data.scenes and data.scenes[sceneIndex]
    if not scene or type(scene.items) ~= "table" then return nil end
    for index, item in ipairs(scene.items) do
        if tostring(item and item.id or "") == tostring(itemId or "") then
            return item, index
        end
    end
    return nil
end

function Diar:IsPlannerMacroTargetSupported(item)
    if type(item) ~= "table" or not item.id then return false end
    if item.kind == "line" then return false end
    if item.kind == "shape" then
        local shape = tostring(item.shape or ""):lower()
        if shape == "donut" or shape == "triangle" or shape == "cone" then return false end
        if item.frontal == true or item.isFrontal == true then return false end
    end
    return true
end

function Diar:GetPlannerMacroResolvedTargets(data, macro)
    local out = {}
    if not data or not macro then return out end
    if macro.type == "set-object" then
        for _, itemId in ipairs(macro.targets or {}) do out[#out + 1] = itemId end
        return out
    end
    local scene = data.scenes and data.scenes[macro.sceneIndex]
    local candidates = {}
    for itemIndex, item in ipairs((scene and scene.items) or {}) do
        local slot = tonumber(item and (item.slotIndex or item.embedIndex))
        if slot and slot >= 1 and self:IsPlannerMacroTargetSupported(item) then
            candidates[#candidates + 1] = {
                id = tostring(item.id),
                slot = math.floor(slot + 0.0001),
                itemIndex = itemIndex,
            }
        end
    end
    table.sort(candidates, function(a, b)
        if a.slot ~= b.slot then return a.slot < b.slot end
        return a.itemIndex < b.itemIndex
    end)
    for _, candidate in ipairs(candidates) do out[#out + 1] = candidate.id end
    return out
end

local function IsSenderInGroup(sender)
    local wanted = NameKey(sender)
    if not wanted then return false end
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    elseif IsInGroup() then
        units[#units + 1] = "player"
        for i = 1, math.max(0, GetNumSubgroupMembers()) do units[#units + 1] = "party" .. i end
    else
        return NamesMatch(wanted, PlayerFullName()) or NamesMatch(wanted, UnitName("player"))
    end
    for _, unit in ipairs(units) do
        local full, name = UnitNameWithRealm(unit)
        if full then
            if NamesMatch(wanted, full) or NamesMatch(wanted, name) then
                return true
            end
        end
    end
    return false
end

local function IsSenderGroupLeader(sender)
    local wanted = NameKey(sender)
    if not wanted then return false end
    local prefix = IsInRaid() and "raid" or "party"
    local count = IsInRaid() and GetNumGroupMembers() or GetNumSubgroupMembers()
    if not IsInGroup() then
        return NamesMatch(wanted, PlayerFullName()) or NamesMatch(wanted, UnitName("player"))
    end
    if not IsInRaid() and UnitIsGroupLeader("player") then
        local mine = PlayerFullName()
        return NamesMatch(wanted, mine)
    end
    for i = 1, count do
        local unit = prefix .. i
        if UnitIsGroupLeader(unit) then
            local full = UnitNameWithRealm(unit)
            return full and NamesMatch(wanted, full) or false
        end
    end
    return false
end

local function MacroState(self, planKey, macroId, create)
    self._plannerMacroState = self._plannerMacroState or {}
    local plan = self._plannerMacroState[planKey]
    if not plan and create then
        plan = {}
        self._plannerMacroState[planKey] = plan
    end
    if not plan then return nil end
    local state = plan[macroId]
    if not state and create then
        state = { sequence = 0, claimsByPlayer = {}, ownersByTarget = {}, nonces = {} }
        plan[macroId] = state
    end
    return state
end

local function NextPlanRevision(self, planKey)
    self._plannerMacroRevisions = self._plannerMacroRevisions or {}
    local revision = (tonumber(self._plannerMacroRevisions[planKey]) or 0) + 1
    self._plannerMacroRevisions[planKey] = revision
    return revision
end

local function RebuildEffectiveOverride(entry)
    if not entry or type(entry.contributions) ~= "table" then return nil end
    local best
    for _, contribution in pairs(entry.contributions) do
        if not best or (tonumber(contribution.revision) or 0) > (tonumber(best.revision) or 0) then
            best = contribution
        end
    end
    entry.effective = best
    return best
end

local function RefreshVisiblePlan(self, planKey, sceneIndex)
    local pf = self.plannerFrame
    if self:GetPlannerMacroPlanKey(self.plannerData) == planKey
        and pf and pf.IsShown and pf:IsShown()
        and (not sceneIndex or (pf.selectedSceneIndex or 1) == sceneIndex)
        and self.RefreshPlannerScene then
        self:RefreshPlannerScene()
    end
end

local function ReplaceMacroTokens(text, player, index)
    local out = tostring(text or "")
    out = out:gsub("{player}", SafeField(ShortName(player), 40))
    out = out:gsub("{index}", tostring(index or ""))
    return SafeField(out, MAX_LABEL_LEN)
end

function Diar:ApplyPlannerMacroAssignment(planKey, macroId, player, targetId, sequence, epoch, notifyPlayer, payload)
    local data = self:GetPlannerMacroPlanData(planKey)
    local macro = data and self:FindPlannerMacro(data, macroId)
    payload = type(payload) == "table" and payload or {}
    local sceneIndex = math.max(1, math.floor(tonumber(payload.sceneIndex or (macro and macro.sceneIndex)) or 1))
    if macro and macro.scope == "global" then macro.sceneIndex = sceneIndex end
    if not macro and payload.scope ~= "global" then return false end
    local item = FindSceneItem(data, sceneIndex, targetId)
    if not item or not self:IsPlannerMacroTargetSupported(item) then return false end

    local targetIndex = math.floor(tonumber(payload.targetIndex) or 0)
    if targetIndex < 1 and macro then
        for i, id in ipairs(self:GetPlannerMacroResolvedTargets(data, macro)) do
            if id == targetId then targetIndex = i break end
        end
    end
    if not targetIndex or targetIndex < 1 then return false end

    epoch = SafeField(epoch, 96)
    local expected = self._plannerMacroExpectedEpochKind
    if expected and epoch:match("^([^:]+)") ~= expected then return false end
    local currentEpoch = self._plannerMacroEpoch
    if currentEpoch and currentEpoch ~= "" and currentEpoch ~= epoch then return false end
    self._plannerMacroEpoch = epoch
    local stateKey = tostring(macroId) .. "@" .. tostring(sceneIndex)
    local state = MacroState(self, planKey, stateKey, true)
    sequence = math.floor(tonumber(sequence) or 0)
    if sequence < (state.sequence or 0) then return false end
    state.sequence = math.max(state.sequence or 0, sequence)
    local playerKey = NameKey(player)
    local macroType = macro and macro.type or payload.type
    if macroType == "claim-next" and playerKey then
        state.claimsByPlayer[playerKey] = targetId
        state.ownersByTarget[targetId] = playerKey
    end

    self._plannerMacroOverrides = self._plannerMacroOverrides or {}
    self._plannerMacroOverrides[planKey] = self._plannerMacroOverrides[planKey] or {}
    local scenes = self._plannerMacroOverrides[planKey]
    scenes[sceneIndex] = scenes[sceneIndex] or {}
    local entry = scenes[sceneIndex][targetId]
    if not entry then
        entry = { contributions = {} }
        scenes[sceneIndex][targetId] = entry
    end
    local existing = entry.contributions[macroId]
    if existing and (tonumber(existing.revision) or 0) >= sequence then return false end
    local renderedLabel = payload.renderedLabel
    if not payload.resolved and renderedLabel == nil and macro then
        renderedLabel = macro.label ~= "" and ReplaceMacroTokens(macro.label, player, targetIndex) or nil
    end
    local fill, stroke
    if payload.resolved then
        fill, stroke = payload.fill, payload.stroke
    else
        fill = payload.fill ~= nil and payload.fill or (macro and macro.fill)
        stroke = payload.stroke ~= nil and payload.stroke or (macro and macro.stroke)
    end
    local macroName = SafeField(payload.name or (macro and macro.name), 48)
    entry.contributions[macroId] = {
        label = renderedLabel and SafeField(renderedLabel, MAX_LABEL_LEN) or nil,
        fill = IsHexColor(fill) and fill:lower() or nil,
        stroke = IsHexColor(stroke) and stroke:lower() or nil,
        macroId = macroId,
        macroName = macroName,
        player = player,
        targetIndex = targetIndex,
        revision = sequence,
    }
    RebuildEffectiveOverride(entry)
    self._plannerMacroRevisions = self._plannerMacroRevisions or {}
    self._plannerMacroRevisions[planKey] = math.max(tonumber(self._plannerMacroRevisions[planKey]) or 0, sequence)
    RefreshVisiblePlan(self, planKey, sceneIndex)
    if notifyPlayer and NamesMatch(player, PlayerFullName()) then
        print(("|cff00aaff[Raidstrats.gg]|r %s"):format(
            L("Assigned to spot #%d (%s)."):format(targetIndex, macroName ~= "" and macroName or L("assignment"))
        ))
    end
    return true
end

function Diar:GetPlannerMacroItemOverride(sceneIndex, itemId)
    local planKey = self:GetPlannerMacroPlanKey(self.plannerData)
    local plan = planKey and self._plannerMacroOverrides and self._plannerMacroOverrides[planKey]
    local scene = plan and plan[sceneIndex]
    local entry = scene and scene[tostring(itemId or "")]
    return entry and (entry.effective or RebuildEffectiveOverride(entry)) or nil
end

function Diar:RenderPlannerItemWithMacroOverrides(pf, root, cw, ch, vc, minSize, item, itemIndex, sceneCtx, sceneIndex)
    local override = self:GetPlannerMacroItemOverride(sceneIndex, item and item.id)
    if not override then
        return Diar.RenderSceneItem(self, pf, root, cw, ch, vc, minSize, item, itemIndex, sceneCtx)
    end
    local oldLabel, oldFill, oldStroke = item.label, item.fill, item.stroke
    if override.label ~= nil then item.label = override.label end
    if override.fill ~= nil then item.fill = override.fill end
    if override.stroke ~= nil then item.stroke = override.stroke end
    sceneCtx.macroOverride = override
    local ok, err = xpcall(function()
        Diar.RenderSceneItem(self, pf, root, cw, ch, vc, minSize, item, itemIndex, sceneCtx)
    end, function(renderError)
        return renderError
    end)
    sceneCtx.macroOverride = nil
    item.label, item.fill, item.stroke = oldLabel, oldFill, oldStroke
    if not ok then error(err, 0) end
end

function Diar:ClearPlannerMacroState(planKey, macroId, epoch, refresh)
    if epoch and epoch ~= "" then self._plannerMacroEpoch = SafeField(epoch, 96) end
    if not planKey or planKey == "*" then
        self._plannerMacroState = {}
        self._plannerMacroOverrides = {}
        self._plannerMacroRevisions = {}
    elseif not macroId or macroId == "*" then
        if self._plannerMacroState then self._plannerMacroState[planKey] = nil end
        if self._plannerMacroOverrides then self._plannerMacroOverrides[planKey] = nil end
        if self._plannerMacroRevisions then self._plannerMacroRevisions[planKey] = nil end
    else
        local planState = self._plannerMacroState and self._plannerMacroState[planKey]
        if planState then
            for stateKey in pairs(planState) do
                if stateKey == macroId or stateKey:sub(1, #macroId + 1) == macroId .. "@" then
                    planState[stateKey] = nil
                end
            end
        end
        local planOverrides = self._plannerMacroOverrides and self._plannerMacroOverrides[planKey]
        if planOverrides then
            for _, scene in pairs(planOverrides) do
                for itemId, entry in pairs(scene) do
                    if entry.contributions then entry.contributions[macroId] = nil end
                    if not RebuildEffectiveOverride(entry) then scene[itemId] = nil end
                end
            end
        end
    end
    if refresh ~= false and self.RefreshPlannerScene and self.plannerFrame and self.plannerFrame:IsShown() then
        self:RefreshPlannerScene()
    end
end

function Diar:SyncPlannerMacroActivePlan()
    local key = self:GetPlannerMacroPlanKey(self.plannerData)
    if self._plannerMacroActivePlanKey and self._plannerMacroActivePlanKey ~= key then
        self:ClearPlannerMacroState("*", "*", nil, false)
    end
    local changed = self._plannerMacroActivePlanKey ~= key
    self._plannerMacroActivePlanKey = key
    if changed and key and IsInGroup() and not UnitIsGroupLeader("player") and self.RequestPlannerMacroSnapshot then
        self:RequestPlannerMacroSnapshot(key)
    end
end

local function SendMacroMessage(self, message, channel, target)
    local prefix = self.COMM_PLAN_PREFIX or "RAIDSTRATS_PLAN"
    if not self.SendCommMessage then return false end
    self:SendCommMessage(prefix, message, channel, target)
    return true
end

local function MacroGroupChannel(self)
    if self.GetPlanShareCommChannel then return self:GetPlanShareCommChannel() end
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

local function MakeLeaderEpoch(self, kind)
    self._plannerMacroEpochCounter = (self._plannerMacroEpochCounter or 0) + 1
    local guid = UnitGUID and UnitGUID("player") or "leader"
    local suffix = tostring(guid or "leader"):gsub("[^%w]", ""):sub(-12)
    self._plannerMacroEpoch = table.concat({
        SafeField(kind or "idle", 24),
        tostring(GetServerTime and GetServerTime() or time()),
        suffix,
        tostring(self._plannerMacroEpochCounter),
    }, ":")
    return self._plannerMacroEpoch
end

local function CurrentLeaderEpoch(self)
    if self._plannerMacroEpoch and self._plannerMacroEpoch ~= "" then return self._plannerMacroEpoch end
    if not IsInGroup() or UnitIsGroupLeader("player") then
        local kind = tostring(self._plannerMacroEncounterActiveId or self._plannerMacroExpectedEpochKind or "idle")
        return MakeLeaderEpoch(self, kind)
    end
    return nil
end

function Diar:BroadcastPlannerMacroAssignment(planKey, macroId, player, targetId, sequence, payload)
    local channel = MacroGroupChannel(self)
    if not channel then return false end
    local epoch = CurrentLeaderEpoch(self)
    if not epoch then return false end
    payload = type(payload) == "table" and payload or {}
    local msg = table.concat({
        "MCAS", "2", SafeField(planKey, 120), SafeField(macroId, 64), SafeField(epoch, 96),
        tostring(sequence or 0), SafeField(player, 80), SafeField(targetId, 96),
        tostring(payload.sceneIndex or 1), tostring(payload.targetIndex or 0),
        SafeField(payload.renderedLabel, MAX_LABEL_LEN), SafeField(payload.fill, 7),
        SafeField(payload.stroke, 7), SafeField(payload.name, 48), SafeField(payload.scope, 8),
    }, SEP)
    return SendMacroMessage(self, msg, channel)
end

function Diar:SendPlannerMacroError(target, nonce, reason)
    if not target or target == "" then return end
    local msg = table.concat({ "MCER", "2", SafeField(nonce, 64), SafeField(reason, 80) }, SEP)
    SendMacroMessage(self, msg, "WHISPER", target)
end

function Diar:ProcessPlannerMacroRequest(planKey, macroToken, player, nonce, requestedSceneIndex)
    if IsInGroup() and not UnitIsGroupLeader("player") then return false end
    local data = self:GetPlannerMacroPlanData(planKey)
    local macro = data and self:FindPlannerMacro(data, macroToken)
    if not macro then
        self:SendPlannerMacroError(player, nonce, L("Macro or plan not found."))
        return false
    end
    if macro.scope == "global" then
        macro.sceneIndex = math.max(1, math.floor(tonumber(requestedSceneIndex) or 1))
    end

    local stateKey = macro.id .. "@" .. tostring(macro.sceneIndex)
    local state = MacroState(self, planKey, stateKey, true)
    local safeNonce = SafeField(nonce, 64)
    local epoch = CurrentLeaderEpoch(self)
    self._plannerMacroHandledNonces = self._plannerMacroHandledNonces or {}
    local previous = safeNonce ~= "" and self._plannerMacroHandledNonces[safeNonce] or nil
    if previous then
        if previous.epoch == epoch and IsInGroup() then
            self:BroadcastPlannerMacroAssignment(planKey, macro.id, player, previous.targetId, previous.sequence, previous.payload)
        end
        return previous.epoch == epoch
    end
    local playerKey = NameKey(player)
    local targetId, targetIndex
    local resolvedTargets = self:GetPlannerMacroResolvedTargets(data, macro)
    if macro.type == "claim-next" then
        targetId = playerKey and state.claimsByPlayer[playerKey] or nil
        if not targetId then
            for index, candidate in ipairs(resolvedTargets) do
                local item = FindSceneItem(data, macro.sceneIndex, candidate)
                if item and self:IsPlannerMacroTargetSupported(item) and not state.ownersByTarget[candidate] then
                    targetId = candidate
                    targetIndex = index
                    break
                end
            end
        end
        if not targetId then
            self:SendPlannerMacroError(player, nonce, L("No free macro spots remain."))
            return false
        end
    else
        targetId = macro.targets[1]
    end
    if not targetIndex then
        for index, candidate in ipairs(resolvedTargets) do
            if candidate == targetId then targetIndex = index break end
        end
    end
    if not targetIndex then
        self:SendPlannerMacroError(player, nonce, L("The assigned object is no longer available."))
        return false
    end

    local revision = NextPlanRevision(self, planKey)
    state.sequence = revision
    local payload = {
        sceneIndex = macro.sceneIndex,
        targetIndex = targetIndex,
        renderedLabel = macro.label ~= "" and ReplaceMacroTokens(macro.label, player, targetIndex) or nil,
        fill = macro.fill,
        stroke = macro.stroke,
        name = macro.name,
        scope = macro.scope,
        type = macro.type,
        resolved = true,
    }
    if safeNonce ~= "" then
        state.nonces[safeNonce] = { targetId = targetId, sequence = revision }
        self._plannerMacroHandledNonces[safeNonce] = {
            targetId = targetId,
            sequence = revision,
            epoch = epoch,
            payload = payload,
            at = GetTime and GetTime() or 0,
        }
    end
    self:ApplyPlannerMacroAssignment(planKey, macro.id, player, targetId, revision, epoch, true, payload)
    if IsInGroup() then
        self:BroadcastPlannerMacroAssignment(planKey, macro.id, player, targetId, revision, payload)
    end
    return true
end

function Diar:RunPlannerMacro(token)
    local data = self.plannerData
    local macro = self:FindPlannerMacro(data, token)
    if not macro and (not IsInGroup() or UnitIsGroupLeader("player")) then
        print(L("|cffff6666[Raidstrats.gg]|r Macro not found on the current plan."))
        return false
    end
    local planKey = self:GetPlannerMacroPlanKey(data)
    if not planKey then
        print(L("|cffff6666[Raidstrats.gg]|r Save this plan before using its macros."))
        return false
    end
    local player = PlayerFullName()
    if not player then return false end
    local activeSceneIndex = self.plannerFrame and self.plannerFrame.selectedSceneIndex or 1
    local sceneIndex = macro and macro.scope ~= "global" and macro.sceneIndex or activeSceneIndex
    local requestToken = macro and macro.scope ~= "global" and macro.id
        or (macro and macro.command or NormalizeCommand(token))
    local nonce = tostring(GetServerTime and GetServerTime() or time()) .. "-" .. tostring(math.random(100000, 999999))
    if not IsInGroup() or UnitIsGroupLeader("player") then
        return self:ProcessPlannerMacroRequest(planKey, requestToken, player, nonce, sceneIndex)
    end
    local channel = MacroGroupChannel(self)
    if not channel then return false end
    local msg = table.concat({
        "MCRQ", "2", SafeField(planKey, 120), SafeField(requestToken, 64), SafeField(nonce, 64),
        tostring(sceneIndex),
    }, SEP)
    self._plannerMacroPending = self._plannerMacroPending or {}
    self._plannerMacroPending[nonce] = (GetTime and GetTime() or 0) + 10
    SendMacroMessage(self, msg, channel)
    return true
end

function Diar:BroadcastPlannerMacroReset(planKey, macroId, epoch)
    if IsInGroup() and not UnitIsGroupLeader("player") then return false end
    local channel = MacroGroupChannel(self)
    if not channel then return false end
    local msg = table.concat({
        "MCRS", "2", SafeField(planKey or "*", 120), SafeField(macroId or "*", 64),
        SafeField(epoch or CurrentLeaderEpoch(self), 96),
    }, SEP)
    return SendMacroMessage(self, msg, channel)
end

function Diar:ResetPlannerMacros(token)
    if IsInGroup() and not UnitIsGroupLeader("player") then
        print(L("|cffff6666[Raidstrats.gg]|r Only the group leader can reset shared macros."))
        return false
    end
    local planKey = self:GetPlannerMacroPlanKey(self.plannerData)
    if not planKey then return false end
    local macroId = "*"
    if Trim(token) ~= "" then
        local macro = self:FindPlannerMacro(self.plannerData, token)
        if not macro then
            print(L("|cffff6666[Raidstrats.gg]|r Macro not found on the current plan."))
            return false
        end
        macroId = macro.id
    end
    self._plannerMacroExpectedEpochKind = "reset"
    local epoch = MakeLeaderEpoch(self, "reset")
    self:ClearPlannerMacroState(planKey, macroId, epoch, true)
    if IsInGroup() then self:BroadcastPlannerMacroReset(planKey, macroId, epoch) end
    return true
end

function Diar:HandlePlannerMacroCommand(input)
    input = Trim(input)
    local command, rest = input:match("^(%S+)%s*(.*)$")
    if not command or command == "" then
        print(L("|cff00aaff[Raidstrats.gg]|r Usage: /rs macro <name>"))
        return
    end
    if command:lower() == "reset" then
        self:ResetPlannerMacros(rest)
    else
        self:RunPlannerMacro(command)
    end
end

local function SplitMessage(message)
    local out, startAt = {}, 1
    while true do
        local pos = message:find(SEP, startAt, true)
        if not pos then
            out[#out + 1] = message:sub(startAt)
            break
        end
        out[#out + 1] = message:sub(startAt, pos - 1)
        startAt = pos + 1
    end
    return out
end

function Diar:RequestPlannerMacroSnapshot(planKey)
    if not IsInGroup() or UnitIsGroupLeader("player") then return false end
    planKey = planKey or self:GetPlannerMacroPlanKey(self.plannerData)
    local channel = MacroGroupChannel(self)
    if not planKey or not channel then return false end
    local nonce = tostring(GetServerTime and GetServerTime() or time()) .. "-s-" .. tostring(math.random(100000, 999999))
    self._plannerMacroSnapshotPending = self._plannerMacroSnapshotPending or {}
    self._plannerMacroSnapshotPending[nonce] = (GetTime and GetTime() or 0) + 10
    local msg = table.concat({ "MCSQ", "2", SafeField(planKey, 120), SafeField(nonce, 64) }, SEP)
    return SendMacroMessage(self, msg, channel)
end

function Diar:SendPlannerMacroSnapshot(planKey, target, nonce)
    if IsInGroup() and not UnitIsGroupLeader("player") then return false end
    if not self:GetPlannerMacroPlanData(planKey) then return false end
    local epoch = CurrentLeaderEpoch(self)
    local planRevision = tonumber(self._plannerMacroRevisions and self._plannerMacroRevisions[planKey]) or 0
    local rows = {}
    local plan = self._plannerMacroOverrides and self._plannerMacroOverrides[planKey]
    for sceneIndex, scene in pairs(plan or {}) do
        for itemId, entry in pairs(scene) do
            for macroId, contribution in pairs(entry.contributions or {}) do
                rows[#rows + 1] = {
                    macroId = macroId,
                    targetId = itemId,
                    player = contribution.player,
                    revision = tonumber(contribution.revision) or 0,
                    sceneIndex = sceneIndex,
                    targetIndex = contribution.targetIndex,
                    label = contribution.label,
                    fill = contribution.fill,
                    stroke = contribution.stroke,
                    name = contribution.macroName,
                }
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.revision ~= b.revision then return a.revision < b.revision end
        if a.macroId ~= b.macroId then return a.macroId < b.macroId end
        return a.targetId < b.targetId
    end)
    local total = math.max(1, #rows)
    for index = 1, total do
        local row = rows[index] or {}
        local msg = table.concat({
            "MCSN", "2", SafeField(planKey, 120), SafeField(epoch, 96), tostring(planRevision),
            tostring(index), tostring(total), SafeField(row.macroId, 64), SafeField(row.targetId, 96),
            SafeField(row.player, 80), tostring(row.revision or 0), SafeField(nonce, 64),
            tostring(row.sceneIndex or 1), tostring(row.targetIndex or 0), SafeField(row.label, MAX_LABEL_LEN),
            SafeField(row.fill, 7), SafeField(row.stroke, 7), SafeField(row.name, 48),
        }, SEP)
        SendMacroMessage(self, msg, "WHISPER", target)
    end
    return true
end

function Diar:HandlePlannerMacroComm(message, sender)
    local parts = SplitMessage(message)
    local opcode = parts[1]
    if parts[2] ~= "2" then return end
    if opcode == "MCRQ" then
        if not UnitIsGroupLeader("player") or not IsSenderInGroup(sender) then return end
        local planKey, macroId, nonce = parts[3], parts[4], parts[5]
        self:ProcessPlannerMacroRequest(planKey, macroId, sender, nonce, parts[6])
    elseif opcode == "MCAS" then
        if not IsSenderGroupLeader(sender) then return end
        self:ApplyPlannerMacroAssignment(parts[3], parts[4], parts[7], parts[8], parts[6], parts[5], true, {
            sceneIndex = parts[9],
            targetIndex = parts[10],
            renderedLabel = parts[11] ~= "" and parts[11] or nil,
            fill = parts[12] ~= "" and parts[12] or nil,
            stroke = parts[13] ~= "" and parts[13] or nil,
            name = parts[14],
            scope = parts[15],
            type = "claim-next",
            resolved = true,
        })
    elseif opcode == "MCRS" then
        if not IsSenderGroupLeader(sender) then return end
        self._plannerMacroSnapshotPending = {}
        self._plannerMacroExpectedEpochKind = parts[5] and parts[5]:match("^([^:]+)") or nil
        self:ClearPlannerMacroState(parts[3], parts[4], parts[5], true)
    elseif opcode == "MCSQ" then
        if not UnitIsGroupLeader("player") or not IsSenderInGroup(sender) then return end
        self:SendPlannerMacroSnapshot(parts[3], sender, parts[4])
    elseif opcode == "MCSN" then
        if not IsSenderGroupLeader(sender) then return end
        local planKey, epoch = parts[3], parts[4]
        local index, total = tonumber(parts[6]), tonumber(parts[7])
        local nonce = parts[12]
        local expires = self._plannerMacroSnapshotPending and self._plannerMacroSnapshotPending[nonce]
        local now = GetTime and GetTime() or 0
        if not index or not total or not expires or expires < now then return end
        local epochKind = epoch and epoch:match("^([^:]+)") or nil
        if self._plannerMacroExpectedEpochKind and epochKind ~= self._plannerMacroExpectedEpochKind then return end
        if self._plannerMacroEpoch and self._plannerMacroEpoch ~= epoch then return end
        if index == 1 then
            self._plannerMacroExpectedEpochKind = epochKind
            self:ClearPlannerMacroState(planKey, "*", epoch, false)
            self._plannerMacroRevisions = self._plannerMacroRevisions or {}
            self._plannerMacroRevisions[planKey] = tonumber(parts[5]) or 0
        end
        if parts[8] and parts[8] ~= "" then
            self:ApplyPlannerMacroAssignment(planKey, parts[8], parts[10], parts[9], parts[11], epoch, false, {
                sceneIndex = parts[13],
                targetIndex = parts[14],
                renderedLabel = parts[15] ~= "" and parts[15] or nil,
                fill = parts[16] ~= "" and parts[16] or nil,
                stroke = parts[17] ~= "" and parts[17] or nil,
                name = parts[18],
                scope = "global",
                type = "claim-next",
                resolved = true,
            })
        end
        if index >= total then
            self._plannerMacroSnapshotPending[nonce] = nil
            RefreshVisiblePlan(self, planKey)
        end
    elseif opcode == "MCER" then
        local nonce = parts[3]
        local expires = self._plannerMacroPending and self._plannerMacroPending[nonce]
        local now = GetTime and GetTime() or 0
        if IsSenderGroupLeader(sender) and expires and expires >= now then
            self._plannerMacroPending[nonce] = nil
            print(("%s %s"):format(L("|cffff6666[Raidstrats.gg]|r"), SafeField(parts[4], 80)))
        end
    end
end

function Diar:OnPlannerMacroEncounterStart(encounterId)
    local kind = tostring(encounterId or 0)
    if self._plannerMacroEncounterActiveId == kind then return end
    self._plannerMacroEncounterActiveId = kind
    self._plannerMacroExpectedEpochKind = kind
    self._plannerMacroEpoch = nil
    self._plannerMacroSnapshotPending = {}
    if not IsInGroup() or UnitIsGroupLeader("player") then
        local epoch = MakeLeaderEpoch(self, kind)
        self:ClearPlannerMacroState("*", "*", epoch, true)
        if IsInGroup() then self:BroadcastPlannerMacroReset("*", "*", epoch) end
    else
        self:ClearPlannerMacroState("*", "*", nil, true)
    end
end

function Diar:OnPlannerMacroEncounterEnd()
    if not self._plannerMacroEncounterActiveId and self._plannerMacroExpectedEpochKind == "ended" then return end
    self._plannerMacroEncounterActiveId = nil
    self._plannerMacroExpectedEpochKind = "ended"
    self._plannerMacroEpoch = nil
    self._plannerMacroSnapshotPending = {}
    if not IsInGroup() or UnitIsGroupLeader("player") then
        local epoch = MakeLeaderEpoch(self, "ended")
        self:ClearPlannerMacroState("*", "*", epoch, true)
        if IsInGroup() then self:BroadcastPlannerMacroReset("*", "*", epoch) end
    else
        self:ClearPlannerMacroState("*", "*", nil, true)
    end
end

local function CurrentGroupLeaderKey()
    if not IsInGroup() then return nil end
    if UnitIsGroupLeader("player") then return NameKey(PlayerFullName()) end
    if IsInRaid() then
        for index = 1, GetNumGroupMembers() do
            local unit = "raid" .. index
            if UnitIsGroupLeader(unit) then return NameKey(UnitNameWithRealm(unit)) end
        end
    else
        for index = 1, GetNumSubgroupMembers() do
            local unit = "party" .. index
            if UnitIsGroupLeader(unit) then return NameKey(UnitNameWithRealm(unit)) end
        end
    end
    return nil
end

function Diar:RefreshPlannerMacroGroupAuthority()
    local leaderKey = CurrentGroupLeaderKey()
    if self._plannerMacroGroupLeaderKey == leaderKey then return end
    self._plannerMacroGroupLeaderKey = leaderKey
    self._plannerMacroEpoch = nil
    self._plannerMacroSnapshotPending = {}
    if not leaderKey then
        self:ClearPlannerMacroState("*", "*", nil, true)
        return
    end

    if UnitIsGroupLeader("player") then
        local kind = tostring(self._plannerMacroEncounterActiveId or self._plannerMacroExpectedEpochKind or "idle")
        self._plannerMacroExpectedEpochKind = kind
        local epoch = MakeLeaderEpoch(self, kind)
        self:ClearPlannerMacroState("*", "*", epoch, true)
        self:BroadcastPlannerMacroReset("*", "*", epoch)
    else
        local planKey = self:GetPlannerMacroPlanKey(self.plannerData)
        if planKey then self:RequestPlannerMacroSnapshot(planKey) end
    end
end

local macroGroupFrame = CreateFrame("Frame")
macroGroupFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
macroGroupFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
macroGroupFrame:SetScript("OnEvent", function()
    if Diar._plannerMacroGroupRefreshQueued then return end
    Diar._plannerMacroGroupRefreshQueued = true
    local function refresh()
        Diar._plannerMacroGroupRefreshQueued = nil
        Diar:RefreshPlannerMacroGroupAuthority()
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.5, refresh) else refresh() end
end)
