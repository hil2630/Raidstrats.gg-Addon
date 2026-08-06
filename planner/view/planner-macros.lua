-- Raidstrats.gg Planner - plan macro recipe editor
local addonName = ...
local AceAddon = LibStub("AceAddon-3.0")
local Addon =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)
if not Addon then return end

local Diar = Addon
local PUI = Diar.PlannerUI or {}
local UI = PUI.UI or {
    PANEL = { 0.06, 0.06, 0.09, 0.98 },
    BORDER = { 0.22, 0.24, 0.28, 1 },
    ROW = { 0.09, 0.10, 0.13, 0.96 },
    ROW_HOV = { 0.14, 0.16, 0.20, 1 },
    ACCENT = { 0.23, 0.51, 0.96, 1 },
}
local SetBackdrop = Diar.SetBackdrop

local function L(key)
    return RSGG_L and RSGG_L(key) or key
end

local function Trim(value)
    return strtrim(tostring(value or ""))
end

local function CopyArray(value)
    local out = {}
    if type(value) == "table" then
        for i, item in ipairs(value) do out[i] = item end
    end
    return out
end

local function CopyMacro(raw)
    return {
        id = raw.id,
        name = raw.name,
        command = raw.command,
        type = raw.type,
        scope = raw.scope,
        sceneIndex = raw.sceneIndex,
        targets = CopyArray(raw.targets),
        label = raw.label,
        fill = raw.fill,
        stroke = raw.stroke,
    }
end

local function CreateButton(parent, text, width, height)
    if PUI.CreatePlannerIconBtn then
        return PUI.CreatePlannerIconBtn(parent, text, width, height)
    end
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width or 90, height or 26)
    SetBackdrop(button, UI.ROW, UI.BORDER, 1)
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER")
    label:SetText(text or "")
    button.label = label
    button.SetText = function(self, value) self.label:SetText(value or "") end
    return button
end

local function SetButtonText(button, text)
    if PUI.SetPlannerBtnText then
        PUI.SetPlannerBtnText(button, text)
    elseif button and button.SetText then
        button:SetText(text or "")
    end
end

local function CreateLabel(parent, text, anchor, relative, relativePoint, x, y, font)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    label:SetPoint(anchor, relative or parent, relativePoint or anchor, x or 0, y or 0)
    label:SetText(text or "")
    label:SetTextColor(0.78, 0.80, 0.86)
    return label
end

local function CreateEdit(parent, width, maxLetters)
    local wrap = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    wrap:SetSize(width or 180, 26)
    SetBackdrop(wrap, { 0.04, 0.04, 0.06, 1 }, UI.BORDER, 1)
    local edit = CreateFrame("EditBox", nil, wrap)
    edit:SetPoint("TOPLEFT", wrap, "TOPLEFT", 7, -3)
    edit:SetPoint("BOTTOMRIGHT", wrap, "BOTTOMRIGHT", -7, 3)
    edit:SetAutoFocus(false)
    edit:SetFontObject(GameFontHighlightSmall)
    edit:SetTextColor(0.95, 0.95, 0.95)
    edit:SetMaxLetters(maxLetters or 80)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEditFocusGained", function() wrap:SetBackdropBorderColor(unpack(UI.ACCENT)) end)
    edit:SetScript("OnEditFocusLost", function() wrap:SetBackdropBorderColor(unpack(UI.BORDER)) end)
    wrap.edit = edit
    return wrap, edit
end

local function MacroTypeText(macroType)
    return macroType == "set-object" and L("Set object") or L("Claim next spot")
end

local function MacroScopeText(scope)
    return scope == "global" and L("Any open plan") or L("This plan only")
end

local function MacroScopeListText(scope)
    return scope == "global" and L("Global") or L("Plan")
end

local function ItemDisplayName(item, index)
    local slot = tonumber(item and (item.slotIndex or item.embedIndex))
    local label = Trim(item and item.label)
    local kind = Trim(item and (item.shape or item.kind))
    local prefix = slot and ("#" .. tostring(math.floor(slot)) .. " ") or ""
    if label ~= "" then return prefix .. label end
    if kind ~= "" then return prefix .. kind .. " " .. tostring(index) end
    return prefix .. L("Object") .. " " .. tostring(index)
end

local function FindTargetIndex(targets, itemId)
    for i, id in ipairs(targets or {}) do
        if tostring(id) == tostring(itemId) then return i end
    end
    return nil
end

local function SetStatus(dialog, text, isError)
    if not dialog or not dialog.status then return end
    dialog.status:SetText(text or "")
    if isError then
        dialog.status:SetTextColor(1, 0.35, 0.35)
    else
        dialog.status:SetTextColor(0.42, 0.9, 0.55)
    end
end

local function CommitForm(dialog)
    local macro = dialog.draft and dialog.draft[dialog.selectedIndex or 0]
    if not macro then return end
    macro.name = Trim(dialog.nameEdit:GetText())
    macro.command = Trim(dialog.commandEdit:GetText()):lower()
    macro.type = dialog.selectedType == "set-object" and "set-object" or "claim-next"
    macro.scope = macro.type == "claim-next" and dialog.selectedScope == "global" and "global" or "plan"
    macro.sceneIndex = math.max(1, math.floor(tonumber(dialog.sceneEdit:GetText()) or 1))
    macro.label = Trim(dialog.labelEdit:GetText())
    macro.fill = Trim(dialog.fillEdit:GetText())
    macro.stroke = Trim(dialog.strokeEdit:GetText())
end

local function GetSelectedMacro(dialog)
    return dialog.draft and dialog.draft[dialog.selectedIndex or 0] or nil
end

local function GetMacroScene(dialog, macro)
    local data = Diar.plannerData
    local sceneIndex
    if macro and macro.scope == "global" then
        sceneIndex = Diar.plannerFrame and Diar.plannerFrame.selectedSceneIndex or 1
    else
        sceneIndex = math.max(1, math.floor(tonumber(macro and macro.sceneIndex) or 1))
    end
    return data and data.scenes and data.scenes[sceneIndex], sceneIndex
end

local function RefreshScopeControls(dialog)
    local macro = GetSelectedMacro(dialog)
    local isGlobal = macro and macro.type == "claim-next" and macro.scope == "global"
    dialog.selectedScope = isGlobal and "global" or "plan"
    SetButtonText(dialog.scopeButton, MacroScopeText(dialog.selectedScope))
    if isGlobal then
        dialog.sceneEdit:SetText(L("Open"))
        dialog.sceneEdit:Disable()
        dialog.scenePrev:Disable()
        dialog.sceneNext:Disable()
    else
        dialog.sceneEdit:Enable()
        dialog.scenePrev:Enable()
        dialog.sceneNext:Enable()
        dialog.sceneEdit:SetText(tostring(macro and macro.sceneIndex or 1))
    end
end

local function FirstSupportedTarget(scene)
    for _, item in ipairs((scene and scene.items) or {}) do
        if Diar:IsPlannerMacroTargetSupported(item) then return tostring(item.id) end
    end
    return nil
end

local function RefreshCommandPreview(dialog)
    local macro = GetSelectedMacro(dialog)
    local command = macro and Trim(dialog.commandEdit:GetText()) or ""
    dialog.commandPreview:SetText(command ~= "" and ("/rs macro " .. command) or "/rs macro <name>")
end

local function RefreshTargetRows(dialog)
    for _, row in ipairs(dialog.targetRows or {}) do row:Hide() end
    dialog.targetRows = dialog.targetRows or {}
    local macro = GetSelectedMacro(dialog)
    if not macro then
        dialog.targetBox:ClearAllPoints()
        dialog.targetBox:SetPoint("TOPLEFT", dialog.form, "TOPLEFT", 14, -258)
        dialog.targetBox:SetPoint("TOPRIGHT", dialog.form, "TOPRIGHT", -14, -258)
        dialog.targetBox:SetHeight(72)
        dialog.targetScroll:Hide()
        dialog.workflowHelp:Hide()
        dialog.targetEmpty:SetText(L("Create or select a macro."))
        dialog.targetEmpty:SetTextColor(0.75, 0.78, 0.84)
        dialog.targetEmpty:Show()
        dialog.targetScrollChild:SetHeight(1)
        return
    end

    local scene = GetMacroScene(dialog, macro)
    if macro.type == "claim-next" then
        dialog.targetBox:ClearAllPoints()
        dialog.targetBox:SetPoint("TOPLEFT", dialog.form, "TOPLEFT", 14, -258)
        dialog.targetBox:SetPoint("TOPRIGHT", dialog.form, "TOPRIGHT", -14, -258)
        dialog.targetBox:SetHeight(72)
        dialog.targetScroll:Hide()
        dialog.workflowHelp:Show()
        local resolvedMacro = CopyMacro(macro)
        if resolvedMacro.scope == "global" then
            resolvedMacro.sceneIndex = Diar.plannerFrame and Diar.plannerFrame.selectedSceneIndex or 1
        end
        local resolved = Diar:GetPlannerMacroResolvedTargets(Diar.plannerData, resolvedMacro)
        if #resolved > 0 then
            dialog.targetEmpty:SetText(L("%d indexed spots found. Whoever clicks gets the next free spot: #1, #2, #3..."):format(#resolved))
            dialog.targetEmpty:SetTextColor(0.7, 0.9, 0.75)
        else
            dialog.targetEmpty:SetText(L("No indexed objects found in this scene. Add numbered objects to the plan first."))
            dialog.targetEmpty:SetTextColor(1, 0.4, 0.4)
        end
        dialog.targetEmpty:Show()
        dialog.targetScrollChild:SetHeight(1)
        return
    end
    dialog.targetBox:ClearAllPoints()
    dialog.targetBox:SetPoint("TOPLEFT", dialog.form, "TOPLEFT", 14, -258)
    dialog.targetBox:SetPoint("BOTTOMRIGHT", dialog.form, "BOTTOMRIGHT", -14, 72)
    dialog.targetScroll:Show()
    dialog.workflowHelp:Hide()
    dialog.targetEmpty:SetTextColor(0.75, 0.78, 0.84)
    local candidates = {}
    if scene and type(scene.items) == "table" then
        for index, item in ipairs(scene.items) do
            if Diar.IsPlannerMacroTargetSupported and Diar:IsPlannerMacroTargetSupported(item) then
                candidates[#candidates + 1] = { item = item, itemIndex = index, selected = FindTargetIndex(macro.targets, item.id) }
            end
        end
    end
    table.sort(candidates, function(a, b)
        if a.selected and b.selected then return a.selected < b.selected end
        if a.selected then return true end
        if b.selected then return false end
        local as = tonumber(a.item.slotIndex or a.item.embedIndex) or 9999
        local bs = tonumber(b.item.slotIndex or b.item.embedIndex) or 9999
        if as ~= bs then return as < bs end
        return a.itemIndex < b.itemIndex
    end)

    if #candidates == 0 then
        dialog.targetEmpty:SetText(L("This scene has no supported objects."))
        dialog.targetEmpty:Show()
        dialog.targetScrollChild:SetHeight(1)
        return
    end
    dialog.targetEmpty:Hide()

    local rowHeight = 30
    for rowIndex, candidate in ipairs(candidates) do
        local row = dialog.targetRows[rowIndex]
        if not row then
            row = CreateFrame("Button", nil, dialog.targetScrollChild, "BackdropTemplate")
            row:SetHeight(rowHeight - 2)
            SetBackdrop(row, UI.ROW, UI.BORDER, 1)
            row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.check:SetPoint("LEFT", row, "LEFT", 2, 0)
            row.check:SetSize(24, 24)
            row.order = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.order:SetPoint("LEFT", row.check, "RIGHT", 0, 0)
            row.order:SetWidth(24)
            row.order:SetJustifyH("CENTER")
            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.name:SetPoint("LEFT", row.order, "RIGHT", 4, 0)
            row.name:SetPoint("RIGHT", row, "RIGHT", -62, 0)
            row.name:SetJustifyH("LEFT")
            row.up = CreateButton(row, "▲", 25, 22)
            row.up:SetPoint("RIGHT", row, "RIGHT", -31, 0)
            row.down = CreateButton(row, "▼", 25, 22)
            row.down:SetPoint("RIGHT", row, "RIGHT", -3, 0)
            dialog.targetRows[rowIndex] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", dialog.targetScrollChild, "TOPLEFT", 0, -((rowIndex - 1) * rowHeight))
        row:SetPoint("RIGHT", dialog.targetScrollChild, "RIGHT", 0, 0)
        row.itemId = tostring(candidate.item.id)
        row.check:SetChecked(candidate.selected and true or false)
        row.order:SetText(candidate.selected and tostring(candidate.selected) or "")
        row.name:SetText(ItemDisplayName(candidate.item, candidate.itemIndex))
        row.up:SetShown(candidate.selected and candidate.selected > 1)
        row.down:SetShown(candidate.selected and candidate.selected < #macro.targets)
        row.check:SetScript("OnClick", function(check)
            local selectedMacro = GetSelectedMacro(dialog)
            if not selectedMacro then return end
            selectedMacro.targets = selectedMacro.targets or {}
            local position = FindTargetIndex(selectedMacro.targets, row.itemId)
            if check:GetChecked() then
                if not position then selectedMacro.targets[#selectedMacro.targets + 1] = row.itemId end
                if selectedMacro.type == "set-object" then
                    selectedMacro.targets = { row.itemId }
                end
            elseif position then
                table.remove(selectedMacro.targets, position)
            end
            RefreshTargetRows(dialog)
        end)
        row:SetScript("OnClick", function() row.check:Click() end)
        row.up:SetScript("OnClick", function()
            local selectedMacro = GetSelectedMacro(dialog)
            local position = selectedMacro and FindTargetIndex(selectedMacro.targets, row.itemId)
            if position and position > 1 then
                selectedMacro.targets[position], selectedMacro.targets[position - 1] =
                    selectedMacro.targets[position - 1], selectedMacro.targets[position]
                RefreshTargetRows(dialog)
            end
        end)
        row.down:SetScript("OnClick", function()
            local selectedMacro = GetSelectedMacro(dialog)
            local position = selectedMacro and FindTargetIndex(selectedMacro.targets, row.itemId)
            if position and position < #selectedMacro.targets then
                selectedMacro.targets[position], selectedMacro.targets[position + 1] =
                    selectedMacro.targets[position + 1], selectedMacro.targets[position]
                RefreshTargetRows(dialog)
            end
        end)
        row:Show()
    end
    dialog.targetScrollChild:SetHeight(math.max(1, #candidates * rowHeight))
end

local RefreshMacroList

local function LoadSelectedMacro(dialog)
    local macro = GetSelectedMacro(dialog)
    dialog.loadingForm = true
    if macro then
        dialog.nameEdit:SetText(macro.name or "")
        dialog.commandEdit:SetText(macro.command or "")
        dialog.selectedType = macro.type == "set-object" and "set-object" or "claim-next"
        dialog.selectedScope = macro.type == "claim-next" and macro.scope == "global" and "global" or "plan"
        SetButtonText(dialog.typeButton, MacroTypeText(dialog.selectedType))
        if dialog.targetTitle then
            dialog.targetTitle:SetText(dialog.selectedType == "set-object" and L("Target object") or L("Automatic indexed spots"))
        end
        dialog.sceneEdit:SetText(tostring(macro.sceneIndex or 1))
        dialog.labelEdit:SetText(macro.label or "")
        dialog.fillEdit:SetText(macro.fill or "")
        dialog.strokeEdit:SetText(macro.stroke or "")
    else
        dialog.nameEdit:SetText("")
        dialog.commandEdit:SetText("")
        dialog.selectedType = "claim-next"
        dialog.selectedScope = "global"
        SetButtonText(dialog.typeButton, MacroTypeText(dialog.selectedType))
        if dialog.targetTitle then dialog.targetTitle:SetText(L("Automatic indexed spots")) end
        dialog.sceneEdit:SetText("1")
        dialog.labelEdit:SetText("")
        dialog.fillEdit:SetText("")
        dialog.strokeEdit:SetText("")
    end
    dialog.loadingForm = nil
    RefreshScopeControls(dialog)
    RefreshCommandPreview(dialog)
    RefreshTargetRows(dialog)
end

RefreshMacroList = function(dialog)
    for _, row in ipairs(dialog.macroRows or {}) do row:Hide() end
    dialog.macroRows = dialog.macroRows or {}
    for index, macro in ipairs(dialog.draft or {}) do
        local row = dialog.macroRows[index]
        if row and not row.scope then
            row:Hide()
            dialog.macroRows[index] = nil
            row = nil
        end
        if not row then
            row = CreateFrame("Button", nil, dialog.macroScrollChild, "BackdropTemplate")
            row:SetHeight(40)
            row.scope = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.scope:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -6)
            row.scope:SetJustifyH("RIGHT")
            row.scope:SetWidth(48)
            if row.scope.SetWordWrap then row.scope:SetWordWrap(false) end
            if row.scope.SetMaxLines then row.scope:SetMaxLines(1) end
            row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 9, -6)
            row.title:SetPoint("RIGHT", row.scope, "LEFT", -6, 0)
            row.title:SetJustifyH("LEFT")
            if row.title.SetWordWrap then row.title:SetWordWrap(false) end
            if row.title.SetMaxLines then row.title:SetMaxLines(1) end
            row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.sub:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 9, 6)
            row.sub:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            row.sub:SetJustifyH("LEFT")
            row.sub:SetTextColor(0.5, 0.55, 0.65)
            if row.sub.SetWordWrap then row.sub:SetWordWrap(false) end
            if row.sub.SetMaxLines then row.sub:SetMaxLines(1) end
            dialog.macroRows[index] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", dialog.macroScrollChild, "TOPLEFT", 0, -((index - 1) * 44))
        row:SetPoint("RIGHT", dialog.macroScrollChild, "RIGHT", 0, 0)
        row.title:SetText(Trim(macro.name) ~= "" and macro.name or L("New macro"))
        row.scope:SetText(MacroScopeListText(macro.scope))
        if macro.scope == "global" then
            row.scope:SetTextColor(0.45, 0.78, 1)
        else
            row.scope:SetTextColor(0.55, 0.6, 0.7)
        end
        row.sub:SetText("/rs macro " .. (Trim(macro.command) ~= "" and macro.command or "?"))
        local selected = index == dialog.selectedIndex
        SetBackdrop(row, selected and { 0.16, 0.28, 0.48, 1 } or UI.ROW, selected and UI.ACCENT or UI.BORDER, 1)
        row:SetScript("OnClick", function()
            CommitForm(dialog)
            dialog.selectedIndex = index
            RefreshMacroList(dialog)
            LoadSelectedMacro(dialog)
        end)
        row:Show()
    end
    if dialog.macroEmpty then
        if #(dialog.draft or {}) == 0 then dialog.macroEmpty:Show() else dialog.macroEmpty:Hide() end
    end
    dialog.macroScrollChild:SetHeight(math.max(1, #(dialog.draft or {}) * 44))
end

local function NewMacro(dialog)
    CommitForm(dialog)
    local data = Diar.plannerData
    local sceneIndex = Diar.plannerFrame and Diar.plannerFrame.selectedSceneIndex or 1
    local commandBase = #dialog.draft == 0 and "claim" or ("claim" .. tostring(#dialog.draft + 1))
    local used = {}
    for _, macro in ipairs(dialog.draft) do used[Trim(macro.command):lower()] = true end
    local command, suffix = commandBase, 2
    while used[command] do
        command = commandBase .. tostring(suffix)
        suffix = suffix + 1
    end
    local scene = data and data.scenes and data.scenes[sceneIndex]
    dialog.draft[#dialog.draft + 1] = {
        id = Diar:GeneratePlannerMacroId(),
        name = L("Spot assignment"),
        command = command,
        type = "claim-next",
        scope = "global",
        sceneIndex = sceneIndex,
        targets = {},
        label = "{player}",
        fill = "",
        stroke = "",
    }
    dialog.selectedIndex = #dialog.draft
    RefreshMacroList(dialog)
    LoadSelectedMacro(dialog)
end

local function DeleteMacro(dialog)
    if not GetSelectedMacro(dialog) then return end
    table.remove(dialog.draft, dialog.selectedIndex)
    dialog.selectedIndex = math.min(dialog.selectedIndex, #dialog.draft)
    if dialog.selectedIndex < 1 and #dialog.draft > 0 then dialog.selectedIndex = 1 end
    RefreshMacroList(dialog)
    LoadSelectedMacro(dialog)
end

local function SaveMacros(dialog)
    CommitForm(dialog)
    local planMacros, globalMacros, commands, ids = {}, {}, {}, {}
    for index, raw in ipairs(dialog.draft or {}) do
        local macro = Diar:NormalizePlannerMacro(raw)
        if not macro then
            SetStatus(dialog, L("Assignment %d needs a name and command."):format(index), true)
            return
        end
        if Trim(raw.fill) ~= "" and not macro.fill then
            SetStatus(dialog, L("Macro %d has an invalid fill color. Use #RRGGBB."):format(index), true)
            return
        end
        if Trim(raw.stroke) ~= "" and not macro.stroke then
            SetStatus(dialog, L("Macro %d has an invalid stroke color. Use #RRGGBB."):format(index), true)
            return
        end
        if macro.label == "" and not macro.fill and not macro.stroke then
            SetStatus(dialog, L("Macro %d must change a label, fill, or stroke color."):format(index), true)
            return
        end
        local scene = Diar.plannerData and Diar.plannerData.scenes and Diar.plannerData.scenes[macro.sceneIndex]
        if macro.scope ~= "global" and not scene then
            SetStatus(dialog, L("Macro %d targets a scene that does not exist."):format(index), true)
            return
        end
        if macro.type == "claim-next" and macro.scope ~= "global" then
            local resolved = Diar:GetPlannerMacroResolvedTargets(Diar.plannerData, macro)
            if #resolved == 0 then
                SetStatus(dialog, L("Macro %d needs at least one indexed object in its scene."):format(index), true)
                return
            end
        else
            for _, targetId in ipairs(macro.targets) do
                local found
                for _, item in ipairs(scene.items or {}) do
                    if tostring(item.id or "") == targetId and Diar:IsPlannerMacroTargetSupported(item) then found = true break end
                end
                if not found then
                    SetStatus(dialog, L("Macro %d contains a missing or unsupported target."):format(index), true)
                    return
                end
            end
        end
        if commands[macro.command] then
            SetStatus(dialog, L("Macro commands must be unique."), true)
            return
        end
        if macro.command == "reset" then
            SetStatus(dialog, L("\"reset\" is reserved for clearing macro assignments."), true)
            return
        end
        if ids[macro.id] then
            SetStatus(dialog, L("Macro IDs must be unique."), true)
            return
        end
        commands[macro.command] = true
        ids[macro.id] = true
        if macro.scope == "global" then
            globalMacros[#globalMacros + 1] = macro
        else
            planMacros[#planMacros + 1] = macro
        end
    end
    Diar.plannerData.macros = planMacros
    RaidstratsggSettings = RaidstratsggSettings or {}
    RaidstratsggSettings.plannerGlobalMacros = globalMacros
    local saved = Diar.PersistCurrentPlanToSaved and Diar:PersistCurrentPlanToSaved()
    if Diar.UpdatePushUpdateButton then Diar:UpdatePushUpdateButton() end
    if Diar.OnPlannerPlanChanged then Diar:OnPlannerPlanChanged() end
    SetStatus(dialog, saved and L("Macros saved to this plan.") or L("Macros updated; save the plan to keep them."), not saved)
    dialog:Hide()
end

local function BuildDialog()
    local dialog = CreateFrame("Frame", "RaidstratsPlannerMacrosDialog", UIParent, "BackdropTemplate")
    dialog:SetSize(780, 620)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("DIALOG")
    dialog:SetFrameLevel(620)
    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    SetBackdrop(dialog, UI.PANEL, UI.BORDER, 2)
    table.insert(UISpecialFrames, "RaidstratsPlannerMacrosDialog")

    local title = CreateLabel(dialog, L("Combat Assignments"), "TOPLEFT", dialog, "TOPLEFT", 18, -17, "GameFontNormalLarge")
    title:SetTextColor(0.95, 0.95, 1)
    local subtitle = CreateLabel(dialog, L("Set this up before combat. During the pull, players only press one action-bar button."), "TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    subtitle:SetTextColor(0.55, 0.6, 0.7)
    local close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -4, -4)

    local left = CreateFrame("Frame", nil, dialog, "BackdropTemplate")
    left:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -62)
    left:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 16, 58)
    left:SetWidth(216)
    SetBackdrop(left, { 0.045, 0.045, 0.07, 1 }, UI.BORDER, 1)

    local macroScroll = CreateFrame("ScrollFrame", nil, left, "UIPanelScrollFrameTemplate")
    macroScroll:SetPoint("TOPLEFT", left, "TOPLEFT", 8, -8)
    macroScroll:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -26, 44)
    local macroScrollChild = CreateFrame("Frame", nil, macroScroll)
    macroScrollChild:SetWidth(174)
    macroScrollChild:SetHeight(1)
    macroScroll:SetScrollChild(macroScrollChild)
    if PUI.SkinPlannerScroll then PUI.SkinPlannerScroll(macroScroll) end
    dialog.macroScrollChild = macroScrollChild
    local macroEmpty = CreateLabel(left, L("No assignments yet.\nClick New to create one."), "CENTER", left, "CENTER", 0, 12)
    macroEmpty:SetWidth(165)
    macroEmpty:SetJustifyH("CENTER")
    macroEmpty:SetTextColor(0.5, 0.55, 0.65)
    dialog.macroEmpty = macroEmpty

    local add = CreateButton(left, L("New"), 88, 27)
    add:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 8, 8)
    local remove = CreateButton(left, L("Delete"), 88, 27)
    remove:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -8, 8)
    add:SetScript("OnClick", function() NewMacro(dialog) end)
    remove:SetScript("OnClick", function() DeleteMacro(dialog) end)

    local form = CreateFrame("Frame", nil, dialog, "BackdropTemplate")
    form:SetPoint("TOPLEFT", left, "TOPRIGHT", 12, 0)
    form:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -16, 58)
    SetBackdrop(form, { 0.055, 0.055, 0.085, 1 }, UI.BORDER, 1)
    dialog.form = form

    CreateLabel(form, L("Assignment name"), "TOPLEFT", form, "TOPLEFT", 14, -15)
    local nameWrap, nameEdit = CreateEdit(form, 240, 48)
    nameWrap:SetPoint("TOPLEFT", form, "TOPLEFT", 14, -32)
    dialog.nameEdit = nameEdit

    CreateLabel(form, L("Button command"), "TOPLEFT", form, "TOPLEFT", 270, -15)
    local commandWrap, commandEdit = CreateEdit(form, 170, 24)
    commandWrap:SetPoint("TOPLEFT", form, "TOPLEFT", 270, -32)
    dialog.commandEdit = commandEdit

    CreateLabel(form, L("Behavior"), "TOPLEFT", form, "TOPLEFT", 14, -70)
    local typeButton = CreateButton(form, L("Claim next spot"), 190, 27)
    typeButton:SetPoint("TOPLEFT", form, "TOPLEFT", 14, -87)
    dialog.typeButton = typeButton

    CreateLabel(form, L("Works with"), "TOPLEFT", form, "TOPLEFT", 220, -70)
    local scopeButton = CreateButton(form, L("Any open plan"), 145, 27)
    scopeButton:SetPoint("TOPLEFT", form, "TOPLEFT", 220, -87)
    dialog.scopeButton = scopeButton

    CreateLabel(form, L("Scene"), "TOPLEFT", form, "TOPLEFT", 379, -70)
    local sceneWrap, sceneEdit = CreateEdit(form, 48, 5)
    sceneWrap:SetPoint("TOPLEFT", form, "TOPLEFT", 379, -87)
    dialog.sceneEdit = sceneEdit
    local scenePrev = CreateButton(form, "−", 28, 27)
    scenePrev:SetPoint("LEFT", sceneWrap, "RIGHT", 5, 0)
    local sceneNext = CreateButton(form, "+", 28, 27)
    sceneNext:SetPoint("LEFT", scenePrev, "RIGHT", 4, 0)
    dialog.scenePrev = scenePrev
    dialog.sceneNext = sceneNext

    CreateLabel(form, L("Text shown on the assigned spot"), "TOPLEFT", form, "TOPLEFT", 14, -126)
    local labelWrap, labelEdit = CreateEdit(form, 250, 80)
    labelWrap:SetPoint("TOPLEFT", form, "TOPLEFT", 14, -143)
    dialog.labelEdit = labelEdit
    local tokens = CreateLabel(form, L("Tokens: {player}, {index}"), "LEFT", labelWrap, "RIGHT", 9, 0)
    tokens:SetTextColor(0.48, 0.53, 0.62)

    CreateLabel(form, L("Spot color (optional #RRGGBB)"), "TOPLEFT", form, "TOPLEFT", 14, -182)
    local fillWrap, fillEdit = CreateEdit(form, 145, 7)
    fillWrap:SetPoint("TOPLEFT", form, "TOPLEFT", 14, -199)
    dialog.fillEdit = fillEdit
    CreateLabel(form, L("Outline (optional #RRGGBB)"), "TOPLEFT", form, "TOPLEFT", 176, -182)
    local strokeWrap, strokeEdit = CreateEdit(form, 145, 7)
    strokeWrap:SetPoint("TOPLEFT", form, "TOPLEFT", 176, -199)
    dialog.strokeEdit = strokeEdit

    local targetTitle = CreateLabel(form, L("Target"), "TOPLEFT", form, "TOPLEFT", 14, -239)
    targetTitle:SetTextColor(0.88, 0.88, 0.92)
    dialog.targetTitle = targetTitle
    local targetBox = CreateFrame("Frame", nil, form, "BackdropTemplate")
    targetBox:SetPoint("TOPLEFT", form, "TOPLEFT", 14, -258)
    targetBox:SetPoint("BOTTOMRIGHT", form, "BOTTOMRIGHT", -14, 72)
    SetBackdrop(targetBox, { 0.035, 0.035, 0.055, 1 }, UI.BORDER, 1)
    dialog.targetBox = targetBox
    local targetScroll = CreateFrame("ScrollFrame", nil, targetBox, "UIPanelScrollFrameTemplate")
    targetScroll:SetPoint("TOPLEFT", targetBox, "TOPLEFT", 7, -7)
    targetScroll:SetPoint("BOTTOMRIGHT", targetBox, "BOTTOMRIGHT", -26, 7)
    local targetScrollChild = CreateFrame("Frame", nil, targetScroll)
    targetScrollChild:SetWidth(446)
    targetScrollChild:SetHeight(1)
    targetScroll:SetScrollChild(targetScrollChild)
    if PUI.SkinPlannerScroll then PUI.SkinPlannerScroll(targetScroll) end
    dialog.targetScroll = targetScroll
    dialog.targetScrollChild = targetScrollChild
    local targetEmpty = CreateLabel(targetBox, L("Create or select a macro."), "CENTER", targetBox, "CENTER", 0, 0)
    targetEmpty:SetWidth(430)
    targetEmpty:SetJustifyH("CENTER")
    dialog.targetEmpty = targetEmpty

    local workflowHelp = CreateLabel(form,
        L("IN COMBAT\n1. Each player presses the command below.\n2. The raid leader assigns the next spot.\n3. Everyone's plan updates immediately.\nAssignments reset for each encounter."),
        "TOPLEFT", targetBox, "BOTTOMLEFT", 3, -17)
    workflowHelp:SetWidth(430)
    workflowHelp:SetJustifyH("LEFT")
    workflowHelp:SetTextColor(0.58, 0.65, 0.76)
    dialog.workflowHelp = workflowHelp

    local commandHint = CreateLabel(form, L("Put this command in a WoW macro, then drag it to the action bar"), "BOTTOMLEFT", form, "BOTTOMLEFT", 14, 48)
    local previewWrap, commandPreview = CreateEdit(form, 300, 255)
    previewWrap:SetPoint("BOTTOMLEFT", form, "BOTTOMLEFT", 14, 14)
    commandPreview:SetText("/rs macro <name>")
    commandPreview:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    commandPreview:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    commandPreview:SetScript("OnEnterPressed", function(self) self:HighlightText() end)
    dialog.commandPreview = commandPreview

    typeButton:SetScript("OnClick", function()
        CommitForm(dialog)
        local macro = GetSelectedMacro(dialog)
        if not macro then return end
        macro.type = macro.type == "set-object" and "claim-next" or "set-object"
        local scene, activeSceneIndex = GetMacroScene(dialog, macro)
        if macro.type == "set-object" then
            macro.scope = "plan"
            macro.sceneIndex = activeSceneIndex
            local target = macro.targets and macro.targets[1] or FirstSupportedTarget(scene)
            macro.targets = target and { target } or {}
        else
            macro.targets = {}
        end
        dialog.selectedType = macro.type
        SetButtonText(typeButton, MacroTypeText(macro.type))
        dialog.targetTitle:SetText(macro.type == "set-object" and L("Target object") or L("Automatic indexed spots"))
        RefreshScopeControls(dialog)
        RefreshMacroList(dialog)
        RefreshTargetRows(dialog)
    end)
    scopeButton:SetScript("OnClick", function()
        CommitForm(dialog)
        local macro = GetSelectedMacro(dialog)
        if not macro or macro.type ~= "claim-next" then return end
        if macro.scope == "global" then
            macro.scope = "plan"
            macro.sceneIndex = Diar.plannerFrame and Diar.plannerFrame.selectedSceneIndex or 1
        else
            macro.scope = "global"
        end
        dialog.selectedScope = macro.scope
        RefreshScopeControls(dialog)
        RefreshMacroList(dialog)
        RefreshTargetRows(dialog)
    end)
    local function ChangeScene(delta)
        CommitForm(dialog)
        local macro = GetSelectedMacro(dialog)
        if not macro or macro.scope == "global" then return end
        local sceneCount = Diar.plannerData and Diar.plannerData.scenes and #Diar.plannerData.scenes or 1
        macro.sceneIndex = math.max(1, math.min(sceneCount, (tonumber(macro.sceneIndex) or 1) + delta))
        macro.targets = {}
        sceneEdit:SetText(tostring(macro.sceneIndex))
        RefreshTargetRows(dialog)
    end
    scenePrev:SetScript("OnClick", function() ChangeScene(-1) end)
    sceneNext:SetScript("OnClick", function() ChangeScene(1) end)
    sceneEdit:SetScript("OnEditFocusLost", function(self)
        local macro = GetSelectedMacro(dialog)
        if not macro or macro.scope == "global" then return end
        local old = tonumber(macro.sceneIndex) or 1
        local new = math.max(1, math.floor(tonumber(self:GetText()) or old))
        if new ~= old then
            macro.sceneIndex = new
            macro.targets = {}
            RefreshTargetRows(dialog)
        end
    end)
    commandEdit:SetScript("OnTextChanged", function()
        if not dialog.loadingForm then RefreshCommandPreview(dialog) end
    end)

    local status = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 18, 22)
    status:SetPoint("RIGHT", dialog, "CENTER", 60, 0)
    status:SetJustifyH("LEFT")
    dialog.status = status
    local cancel = CreateButton(dialog, L("Cancel"), 104, 30)
    cancel:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -132, 14)
    cancel:SetScript("OnClick", function() dialog:Hide() end)
    local save = CreateButton(dialog, L("Save"), 104, 30)
    save:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -16, 14)
    save:SetScript("OnClick", function() SaveMacros(dialog) end)
    return dialog
end

function Diar:ShowPlannerMacrosDialog()
    if InCombatLockdown and InCombatLockdown() then
        print(L("|cffff6666[Raidstrats.gg]|r Combat assignments can only be edited outside combat. Use the prepared action-bar macro during combat."))
        return
    end
    if not self.plannerData or type(self.plannerData.scenes) ~= "table" then
        print(L("|cffff6666[Raidstrats.gg]|r Open a plan before editing macros."))
        return
    end
    if not self.plannerMacrosDialog then
        self.plannerMacrosDialog = BuildDialog()
    end
    local dialog = self.plannerMacrosDialog
    dialog.draft = {}
    for _, macro in ipairs(self:GetPlannerPlanMacros(self.plannerData)) do
        dialog.draft[#dialog.draft + 1] = CopyMacro(macro)
    end
    for _, macro in ipairs(self:GetPlannerGlobalMacros()) do
        dialog.draft[#dialog.draft + 1] = CopyMacro(macro)
    end
    dialog.selectedIndex = #dialog.draft > 0 and 1 or nil
    SetStatus(dialog, "", false)
    RefreshMacroList(dialog)
    LoadSelectedMacro(dialog)
    if self.PrepareModal then self:PrepareModal(dialog, self.plannerFrame or self.frame) end
    dialog:ClearAllPoints()
    dialog:SetPoint("CENTER", self.plannerFrame or UIParent, "CENTER")
    dialog:Show()
    dialog:Raise()
end
