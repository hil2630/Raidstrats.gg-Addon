-- In-game soak group editor: assign soakers from the raid or names already on the plan.
local addonName = ...
local AceAddon = LibStub("AceAddon-3.0")
local Addon =
    AceAddon:GetAddon(addonName, true) or
    AceAddon:GetAddon("Raidstratsgg", true) or
    AceAddon:GetAddon("raidstratsgg", true)
if not Addon then return end
local Diar = Addon
local SetBackdrop = Diar.SetBackdrop
local PUI = Diar.PlannerUI
local UI = PUI and PUI.UI or {
    PANEL   = {0.06, 0.06, 0.09, 0.96},
    BORDER  = {0.22, 0.24, 0.28, 1},
    TOOLBAR = {0.05, 0.05, 0.08, 0.92},
    ROW     = {0.09, 0.10, 0.13, 0.92},
    ROW_HOV = {0.14, 0.16, 0.20, 1},
    ACCENT  = {0.23, 0.51, 0.96, 1},
}
local CreatePlannerIconBtn = PUI and PUI.CreatePlannerIconBtn
local function L(key) return RSGG_L(key) end

local CLASS_ICON_TEX = {
    deathknight = "Interface\\Icons\\ClassIcon_DEATHKNIGHT",
    demonhunter = "Interface\\Icons\\ClassIcon_DEMONHUNTER",
    druid = "Interface\\Icons\\ClassIcon_DRUID",
    evoker = "Interface\\Icons\\ClassIcon_EVOKER",
    hunter = "Interface\\Icons\\ClassIcon_HUNTER",
    mage = "Interface\\Icons\\ClassIcon_MAGE",
    monk = "Interface\\Icons\\ClassIcon_MONK",
    paladin = "Interface\\Icons\\ClassIcon_PALADIN",
    priest = "Interface\\Icons\\ClassIcon_PRIEST",
    rogue = "Interface\\Icons\\ClassIcon_ROGUE",
    shaman = "Interface\\Icons\\ClassIcon_SHAMAN",
    warlock = "Interface\\Icons\\ClassIcon_WARLOCK",
    warrior = "Interface\\Icons\\ClassIcon_WARRIOR",
}

local function NameKey(name)
    if type(name) ~= "string" then return nil end
    local t = strlower(strtrim(name))
    if t == "" then return nil end
    return t:match("^([^%-]+)") or t
end

local function ClassKeyFromValue(value)
    if type(value) ~= "string" or value == "" then return nil end
    local key = value:lower():gsub("^.*/", ""):gsub("%.[^%.]+$", ""):gsub("[%s_-]", "")
    if Diar.PLANNER_SOAK_CLASS_COLORS and Diar.PLANNER_SOAK_CLASS_COLORS[key] then
        return key
    end
    return nil
end

local function ClassKeyFromPlayer(player)
    if not player then return nil end
    return ClassKeyFromValue(player.className)
        or ClassKeyFromValue(player.icon)
        or ClassKeyFromValue(player.class)
end

local function ClassTexture(classKey)
    return classKey and CLASS_ICON_TEX[classKey] or nil
end

local function CollectSoakZones()
    local zones = {}
    local data = Diar.plannerData
    if not data or type(data.scenes) ~= "table" then return zones end
    for sceneIndex, scene in ipairs(data.scenes) do
        if type(scene.items) == "table" then
            local soakNum = 0
            for itemIndex, item in ipairs(scene.items) do
                if item and tostring(item.kind or ""):lower() == "soakzone" then
                    soakNum = soakNum + 1
                    local slots = Diar.BuildPlannerSoakSlots and select(1, Diar.BuildPlannerSoakSlots(item)) or {}
                    zones[#zones + 1] = {
                        sceneIndex = sceneIndex,
                        itemIndex = itemIndex,
                        soakNum = soakNum,
                        sceneName = tostring(scene.name or ("Scene " .. sceneIndex)),
                        item = item,
                        slots = slots,
                    }
                end
            end
        end
    end
    return zones
end

local function CollectPlanPlayers()
    local list, seen = {}, {}
    local function add(name, className, icon)
        local key = NameKey(name)
        if not key or seen[key] then return end
        seen[key] = true
        list[#list + 1] = {
            name = strtrim(tostring(name)),
            className = ClassKeyFromValue(className) or ClassKeyFromValue(icon),
            icon = icon,
            source = "plan",
        }
    end
    local data = Diar.plannerData
    if data and type(data.scenes) == "table" then
        for _, scene in ipairs(data.scenes) do
            if type(scene.items) == "table" then
                for _, item in ipairs(scene.items) do
                    if item then
                        if item.label and item.label ~= "" then
                            add(item.label, nil, item.icon)
                        end
                        if type(item.assignees) == "table" then
                            for _, assignee in ipairs(item.assignees) do
                                if assignee and assignee.name then
                                    add(assignee.name, assignee.className, assignee.icon)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    return list
end

local function CollectGroupPlayers()
    local members = {}
    if Diar.GetGroupMemberRoster then
        members = Diar:GetGroupMemberRoster() or {}
    end
    local out = {}
    for _, member in ipairs(members) do
        out[#out + 1] = {
            name = member.name,
            className = ClassKeyFromValue(member.icon) or ClassKeyFromValue(member.className),
            icon = member.icon,
            source = "group",
        }
    end
    return out
end

local function CopyAssignee(assignee)
    if not assignee then return nil end
    return {
        name = assignee.name,
        className = assignee.className,
        spec = assignee.spec,
        icon = assignee.icon,
        group = assignee.group,
    }
end

local function WriteSoakSlots(item, slots)
    if not item then return end
    local assignees = {}
    for slot, assignee in ipairs(slots) do
        if assignee then
            local copy = CopyAssignee(assignee)
            copy.slot = slot
            assignees[#assignees + 1] = copy
        end
    end
    item.assignees = assignees
end

local function CopySlotList(slots)
    local out = {}
    if type(slots) ~= "table" then return out end
    for i = 1, #slots do
        out[i] = slots[i]
    end
    return out
end

local function SwapSoakSlots(fromItem, fromSlot, toItem, toSlot)
    if not fromItem or not toItem or not fromSlot or not toSlot then return false end
    if fromItem == toItem and fromSlot == toSlot then return false end
    if not Diar.BuildPlannerSoakSlots then return false end
    local fromCopy = CopySlotList(select(1, Diar.BuildPlannerSoakSlots(fromItem)))
    local toCopy = (fromItem == toItem) and fromCopy or CopySlotList(select(1, Diar.BuildPlannerSoakSlots(toItem)))
    fromCopy[fromSlot], toCopy[toSlot] = toCopy[toSlot], fromCopy[fromSlot]
    WriteSoakSlots(fromItem, fromCopy)
    if toItem ~= fromItem then
        WriteSoakSlots(toItem, toCopy)
    end
    return true
end

local function ApplySoakSlot(item, slot, player)
    if not item or not slot then return false end
    item.assignees = type(item.assignees) == "table" and item.assignees or {}
    local slots = Diar.BuildPlannerSoakSlots and select(1, Diar.BuildPlannerSoakSlots(item)) or {}
    local occupant = slots[slot]
    local kept = {}
    for _, assignee in ipairs(item.assignees) do
        local existing = math.floor(tonumber(assignee and assignee.slot) or 0)
        if assignee ~= occupant and existing ~= slot then
            kept[#kept + 1] = assignee
        end
    end
    if player then
        local className = ClassKeyFromPlayer(player)
        local icon = player.icon
        if (not icon or icon == "") and className then
            icon = "classes/" .. className
        end
        kept[#kept + 1] = {
            name = strtrim(tostring(player.name or "")),
            className = className,
            spec = player.spec,
            icon = icon,
            slot = slot,
        }
    end
    item.assignees = kept
    return true
end

local function PersistSoakChange()
    if Diar.RefreshPlannerScene then
        Diar:RefreshPlannerScene()
    end
    if Diar.PersistCurrentPlanToSaved then
        Diar:PersistCurrentPlanToSaved()
    end
    if Diar.UpdatePushUpdateButton then
        Diar:UpdatePushUpdateButton()
    end
end

function Diar:HideSoakPlayerPicker()
    if self._soakPlayerPicker then
        self._soakPlayerPicker:Hide()
        self._soakPlayerPicker = nil
    end
end

function Diar:HideSoakGroupsDialog()
    self:HideSoakPlayerPicker()
    if self.plannerSoakGroupsDialog then
        self.plannerSoakGroupsDialog:Hide()
    end
end

function Diar:EnsurePlannerSoakGroupsButton(pf)
    if not pf or not pf.controls or not CreatePlannerIconBtn then return end
    if not pf.soakGroupsBtn then
        pf.soakGroupsBtn = CreatePlannerIconBtn(pf.controls, L("Soaks"), 64, PUI.CONTROLS_H or 30)
        pf.soakGroupsBtn:SetScript("OnClick", function()
            Diar:ShowSoakGroupsDialog()
        end)
    elseif pf.soakGroupsBtn:GetParent() ~= pf.controls then
        pf.soakGroupsBtn:SetParent(pf.controls)
        pf.soakGroupsBtn:SetHeight(PUI.CONTROLS_H or 30)
    end
    if pf.soakGroupsBtn.SetText then
        pf.soakGroupsBtn:SetText(L("Soaks"))
    end
end

local function SetIconTexture(tex, classKey)
    if not tex then return end
    local path = ClassTexture(classKey)
    if path then
        tex:SetTexture(path)
        tex:SetVertexColor(1, 1, 1, 1)
    else
        tex:SetColorTexture(0.25, 0.27, 0.32, 1)
    end
end

local function StyleRow(row, hover)
    if not row then return end
    if hover then
        row:SetBackdropColor(unpack(UI.ROW_HOV))
    else
        row:SetBackdropColor(unpack(row.__baseColor or UI.ROW))
    end
end

local DROP_COLOR = { 0.16, 0.32, 0.58, 0.96 }

local function CursorUI()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    return x / scale, y / scale
end

local function RowUnderCursor(rows, ignore)
    if type(rows) ~= "table" then return nil end
    for _, row in ipairs(rows) do
        if row ~= ignore and row:IsShown() and row.IsMouseOver and row:IsMouseOver() then
            return row
        end
    end
    return nil
end

local function EnsureSoakDragChrome(f)
    if f.dragGhost then return end
    local ghost = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    ghost:SetSize(220, 24)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:SetFrameLevel(400)
    ghost:EnableMouse(false)
    if SetBackdrop then SetBackdrop(ghost, { 0.16, 0.18, 0.24, 0.94 }, UI.ACCENT, 1) end
    local icon = ghost:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", 8, 0)
    ghost.icon = icon
    local lbl = ghost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    lbl:SetTextColor(1, 1, 1)
    ghost.label = lbl
    ghost:Hide()
    f.dragGhost = ghost

    local updater = CreateFrame("Frame", nil, f)
    updater:Hide()
    updater:SetScript("OnUpdate", function()
        local drag = f._soakDrag
        if not drag or (not drag.pending and not drag.active) then
            updater:Hide()
            return
        end
        if not IsMouseButtonDown("LeftButton") then
            local target = drag.active and RowUnderCursor(f.listChild and f.listChild._slotRows, drag.fromRow) or nil
            local fromRow = drag.fromRow
            if drag.active and target and fromRow and fromRow.__item and target.__item then
                if SwapSoakSlots(fromRow.__item, fromRow.__slot, target.__item, target.__slot) then
                    PersistSoakChange()
                    if fromRow then fromRow.__skipClick = true end
                    if Diar.RefreshSoakGroupsDialog then
                        Diar:RefreshSoakGroupsDialog()
                    end
                end
            elseif drag.active and fromRow then
                fromRow.__skipClick = true
            end
            if drag.highlight then
                StyleRow(drag.highlight, false)
            end
            ghost:Hide()
            f._soakDrag = nil
            updater:Hide()
            return
        end
        local x, y = CursorUI()
        if drag.pending then
            local dx, dy = x - drag.startX, y - drag.startY
            if (dx * dx + dy * dy) >= 36 then
                drag.active = true
                drag.pending = false
                if drag.fromRow then drag.fromRow.__skipClick = true end
                Diar:HideSoakPlayerPicker()
                local assignee = drag.fromRow and drag.fromRow.__assignee
                SetIconTexture(ghost.icon, assignee and ClassKeyFromValue(assignee.className or assignee.icon))
                ghost.label:SetText(assignee and assignee.name or "")
                ghost:Show()
            end
        end
        if drag.active then
            ghost:ClearAllPoints()
            ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x + 16, y - 6)
            local over = RowUnderCursor(f.listChild and f.listChild._slotRows, drag.fromRow)
            if drag.highlight and drag.highlight ~= over then
                StyleRow(drag.highlight, false)
            end
            if over then
                over:SetBackdropColor(unpack(DROP_COLOR))
            end
            drag.highlight = over
        end
    end)
    f.dragUpdater = updater
end

local function BeginSoakRowDrag(f, row)
    if not f or not row or not row.__assignee then return end
    local x, y = CursorUI()
    f._soakDrag = {
        pending = true,
        active = false,
        startX = x,
        startY = y,
        fromRow = row,
    }
    if f.dragUpdater then f.dragUpdater:Show() end
end

function Diar:ShowSoakPlayerPicker(zone, slot, currentName)
    self:HideSoakPlayerPicker()
    local groupPlayers = CollectGroupPlayers()
    local planPlayers = CollectPlanPlayers()
    local sections = {
        { title = L("In your group"), players = groupPlayers },
        { title = L("On the plan"), players = planPlayers },
    }

    local rowCount = 1
    for _, section in ipairs(sections) do
        rowCount = rowCount + 1 + math.max(1, #section.players)
    end
    local listH = math.min(320, rowCount * 28 + 12)
    local f = CreateFrame("Frame", "RaidstratsSoakPlayerPicker", UIParent, "BackdropTemplate")
    f:SetSize(280, 86 + listH)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(320)
    f:EnableMouse(true)
    f:SetMovable(true)
    if SetBackdrop then SetBackdrop(f, UI.PANEL, UI.BORDER, 2) end
    f:SetScript("OnMouseDown", function(s, b) if b == "LeftButton" then s:StartMoving() end end)
    f:SetScript("OnMouseUp", function(s) s:StopMovingOrSizing() end)

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() Diar:HideSoakPlayerPicker() end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -14)
    title:SetText(L("Assign soaker"))
    title:SetTextColor(0.96, 0.96, 0.96)

    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetTextColor(0.72, 0.76, 0.82)
    if currentName and currentName ~= "" then
        sub:SetText(L("Current: |cffeadb5f%s|r"):format(currentName))
    else
        sub:SetText(L("Empty"))
    end

    local clearBtn = CreatePlannerIconBtn and CreatePlannerIconBtn(f, L("Clear slot"), 88, 22)
    if clearBtn then
        clearBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -36, -16)
        clearBtn:SetScript("OnClick", function()
            ApplySoakSlot(zone.item, slot, nil)
            PersistSoakChange()
            Diar:HideSoakPlayerPicker()
            if Diar.RefreshSoakGroupsDialog then
                Diar:RefreshSoakGroupsDialog()
            end
        end)
    end

    local listPanel = CreateFrame("Frame", nil, f, "BackdropTemplate")
    listPanel:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -62)
    listPanel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
    if SetBackdrop then SetBackdrop(listPanel, UI.TOOLBAR, UI.BORDER, 1) end

    local scroll = CreateFrame("ScrollFrame", nil, listPanel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", listPanel, "BOTTOMRIGHT", -22, 6)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(226)
    scroll:SetScrollChild(child)
    if PUI and PUI.SkinPlannerScroll then PUI.SkinPlannerScroll(scroll) end

    local y = -2
    local function addHeader(text)
        local lbl = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("TOPLEFT", child, "TOPLEFT", 4, y)
        lbl:SetText(text)
        lbl:SetTextColor(0.70, 0.76, 0.88)
        y = y - 22
    end
    local function addEmpty()
        local lbl = child:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        lbl:SetPoint("TOPLEFT", child, "TOPLEFT", 8, y)
        lbl:SetText(L("No players found."))
        y = y - 24
    end
    local function addPlayer(player)
        local row = CreateFrame("Button", nil, child, "BackdropTemplate")
        row:SetSize(220, 24)
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 2, y)
        row.__baseColor = UI.ROW
        if SetBackdrop then SetBackdrop(row, UI.ROW, UI.BORDER, 1) end
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("LEFT", 6, 0)
        SetIconTexture(icon, ClassKeyFromPlayer(player))
        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        lbl:SetText(player.name)
        local current = NameKey(currentName) and NameKey(currentName) == NameKey(player.name)
        lbl:SetTextColor(current and 1 or 0.90, current and 0.92 or 0.90, current and 0.35 or 0.90)
        row:SetScript("OnEnter", function(s) StyleRow(s, true) end)
        row:SetScript("OnLeave", function(s) StyleRow(s, false) end)
        row:SetScript("OnClick", function()
            ApplySoakSlot(zone.item, slot, player)
            PersistSoakChange()
            Diar:HideSoakPlayerPicker()
            if Diar.RefreshSoakGroupsDialog then
                Diar:RefreshSoakGroupsDialog()
            end
        end)
        y = y - 26
    end

    for _, section in ipairs(sections) do
        addHeader(section.title)
        if #section.players == 0 then
            addEmpty()
        else
            for _, player in ipairs(section.players) do
                addPlayer(player)
            end
        end
    end
    child:SetHeight(math.max(1, -y + 4))

    self._soakPlayerPicker = f
    if self.PrepareModal then
        self:PrepareModal(f, self.plannerSoakGroupsDialog or self.plannerFrame)
    end
    f:ClearAllPoints()
    f:SetPoint("CENTER", self.plannerSoakGroupsDialog or UIParent, "CENTER", 40, 0)
    f:Show()
    f:Raise()
end

function Diar:RefreshSoakGroupsDialog()
    local f = self.plannerSoakGroupsDialog
    if not f or not f:IsShown() then return end
    if f.Rebuild then f:Rebuild() end
end

function Diar:ShowSoakGroupsDialog()
    self:HideSoakPlayerPicker()
    if self.HidePlannerTransientMenus then
        self:HidePlannerTransientMenus()
    end

    local f = self.plannerSoakGroupsDialog
    if not f then
        f = CreateFrame("Frame", "RaidstratsSoakGroupsDialog", UIParent, "BackdropTemplate")
        f:SetSize(460, 520)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:EnableMouse(true)
        f:SetMovable(true)
        f:SetClampedToScreen(true)
        if SetBackdrop then SetBackdrop(f, UI.PANEL, UI.BORDER, 2) end
        tinsert(UISpecialFrames, "RaidstratsSoakGroupsDialog")
        f:SetScript("OnMouseDown", function(s, b) if b == "LeftButton" then s:StartMoving() end end)
        f:SetScript("OnMouseUp", function(s) s:StopMovingOrSizing() end)

        local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -4, -4)

        local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
        header:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
        header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
        header:SetHeight(58)
        if SetBackdrop then SetBackdrop(header, UI.TOOLBAR, UI.BORDER, 1) end
        local accent = header:CreateTexture(nil, "ARTWORK")
        accent:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
        accent:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
        accent:SetHeight(2)
        accent:SetColorTexture(unpack(UI.ACCENT))

        local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", header, "TOPLEFT", 14, -12)
        title:SetText(L("Soak Groups"))
        title:SetTextColor(0.98, 0.98, 0.98)

        local subtitle = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
        subtitle:SetWidth(420)
        subtitle:SetJustifyH("LEFT")
        subtitle:SetText(L("Assign from your group or the plan. Drag assigned players to switch slots."))
        subtitle:SetTextColor(0.78, 0.82, 0.90)

        local body = CreateFrame("Frame", nil, f, "BackdropTemplate")
        body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 10, -10)
        body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 12)
        if SetBackdrop then SetBackdrop(body, { 0.045, 0.048, 0.062, 0.96 }, UI.BORDER, 1) end

        local scroll = CreateFrame("ScrollFrame", nil, body, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", body, "TOPLEFT", 8, -8)
        scroll:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -26, 8)
        local child = CreateFrame("Frame", nil, scroll)
        child:SetWidth(400)
        scroll:SetScrollChild(child)
        if PUI and PUI.SkinPlannerScroll then PUI.SkinPlannerScroll(scroll) end
        f.listChild = child
        f.listScroll = scroll
        EnsureSoakDragChrome(f)

        f.Rebuild = function()
            local host = f.listChild
            if host._rows then
                for _, row in ipairs(host._rows) do
                    row:Hide()
                    row:SetParent(nil)
                end
            end
            host._rows = {}
            host._slotRows = {}
            if f.dragGhost then f.dragGhost:Hide() end
            f._soakDrag = nil
            if f.dragUpdater then f.dragUpdater:Hide() end
            local y = -4
            local zones = CollectSoakZones()
            if #zones == 0 then
                local empty = host:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                empty:SetPoint("TOPLEFT", host, "TOPLEFT", 8, y)
                empty:SetWidth(380)
                empty:SetJustifyH("LEFT")
                empty:SetText(L("No soak zones in this plan."))
                empty:SetTextColor(0.72, 0.76, 0.82)
                host._rows[1] = empty
                host:SetHeight(40)
                return
            end

            local lastScene
            for _, zone in ipairs(zones) do
                if zone.sceneName ~= lastScene then
                    lastScene = zone.sceneName
                    local sceneLbl = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    sceneLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 4, y)
                    sceneLbl:SetText(zone.sceneName)
                    sceneLbl:SetTextColor(0.82, 0.88, 1)
                    host._rows[#host._rows + 1] = sceneLbl
                    y = y - 22
                end

                local assigned = 0
                for _, assignee in ipairs(zone.slots) do
                    if assignee then assigned = assigned + 1 end
                end
                local headerBtn = CreateFrame("Button", nil, host, "BackdropTemplate")
                headerBtn:SetSize(396, 26)
                headerBtn:SetPoint("TOPLEFT", host, "TOPLEFT", 0, y)
                headerBtn.__baseColor = { 0.08, 0.10, 0.14, 0.96 }
                if SetBackdrop then SetBackdrop(headerBtn, headerBtn.__baseColor, UI.BORDER, 1) end
                local headerLbl = headerBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                headerLbl:SetPoint("LEFT", 8, 0)
                headerLbl:SetText(L("Soak %d"):format(zone.soakNum) .. ("  %d/%d"):format(assigned, #zone.slots))
                headerLbl:SetTextColor(0.90, 0.93, 0.98)
                headerBtn:SetScript("OnEnter", function(s) StyleRow(s, true) end)
                headerBtn:SetScript("OnLeave", function(s) StyleRow(s, false) end)
                headerBtn:SetScript("OnClick", function()
                    if Diar.SelectPlannerScene then
                        Diar:SelectPlannerScene(zone.sceneIndex)
                    end
                end)
                host._rows[#host._rows + 1] = headerBtn
                y = y - 28

                for slot, assignee in ipairs(zone.slots) do
                    local row = CreateFrame("Button", nil, host, "BackdropTemplate")
                    row:SetSize(396, 26)
                    row:SetPoint("TOPLEFT", host, "TOPLEFT", 0, y)
                    row.__baseColor = UI.ROW
                    if SetBackdrop then SetBackdrop(row, UI.ROW, UI.BORDER, 1) end
                    local icon = row:CreateTexture(nil, "ARTWORK")
                    icon:SetSize(16, 16)
                    icon:SetPoint("LEFT", 10, 0)
                    SetIconTexture(icon, assignee and ClassKeyFromValue(assignee.className or assignee.icon))
                    local idx = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    idx:SetPoint("LEFT", icon, "RIGHT", 8, 0)
                    idx:SetWidth(22)
                    idx:SetJustifyH("LEFT")
                    idx:SetText(tostring(slot))
                    idx:SetTextColor(0.62, 0.66, 0.72)
                    local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    name:SetPoint("LEFT", idx, "RIGHT", 6, 0)
                    if assignee and assignee.name and assignee.name ~= "" then
                        name:SetText(assignee.name)
                        name:SetTextColor(0.93, 0.93, 0.95)
                    else
                        name:SetText(L("Empty"))
                        name:SetTextColor(0.55, 0.58, 0.64)
                    end
                    row.__item = zone.item
                    row.__slot = slot
                    row.__assignee = assignee or nil
                    row:SetScript("OnEnter", function(s)
                        if f._soakDrag and f._soakDrag.active then return end
                        StyleRow(s, true)
                    end)
                    row:SetScript("OnLeave", function(s)
                        if f._soakDrag and f._soakDrag.active then return end
                        StyleRow(s, false)
                    end)
                    row:SetScript("OnMouseDown", function(s, button)
                        if button == "LeftButton" and s.__assignee then
                            BeginSoakRowDrag(f, s)
                        end
                    end)
                    row:SetScript("OnClick", function(s)
                        if s.__skipClick then
                            s.__skipClick = nil
                            return
                        end
                        Diar:ShowSoakPlayerPicker(zone, slot, s.__assignee and s.__assignee.name)
                    end)
                    host._rows[#host._rows + 1] = row
                    host._slotRows[#host._slotRows + 1] = row
                    y = y - 28
                end
                y = y - 8
            end
            host:SetHeight(math.max(1, -y + 8))
        end

        f:SetScript("OnHide", function()
            Diar:HideSoakPlayerPicker()
            if f.dragGhost then f.dragGhost:Hide() end
            f._soakDrag = nil
            if f.dragUpdater then f.dragUpdater:Hide() end
        end)
        self.plannerSoakGroupsDialog = f
    end

    if self.PrepareModal then
        self:PrepareModal(f, self.plannerFrame)
    end
    f:ClearAllPoints()
    if self.plannerFrame and self.plannerFrame:IsShown() then
        f:SetPoint("CENTER", self.plannerFrame, "CENTER")
    else
        f:SetPoint("CENTER")
    end
    f:Show()
    f:Raise()
    f:Rebuild()
end
