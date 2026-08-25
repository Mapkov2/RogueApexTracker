local _, RAT = ...

local HISTORY_LATEST = -1
local CURRENT_TYPES = {
    currentCombat = "combat",
    currentEncounter = "encounter",
    currentKeystone = "keystone",
    session = "session",
}
local VALID_TYPES = {
    currentCombat = true,
    currentEncounter = true,
    currentKeystone = true,
    session = true,
    combat = true,
    encounter = true,
    keystone = true,
}
local selection = { type = "combat", index = HISTORY_LATEST }
local historyFrame

local function Counter(value)
    return math.max(0, math.floor(tonumber(value) or 0))
end

local function Percent(successes, attempts)
    return attempts > 0 and successes * 100 / attempts or 0
end

local function FormatPercent(value)
    local decimals = math.max(0, math.min(2, tonumber(RAT.db and RAT.db.decimals) or 1))
    if decimals == 0 then return string.format("%.0f%%", value) end
    if decimals == 2 then return string.format("%.2f%%", value) end
    return string.format("%.1f%%", value)
end

local function MetricMode(definition)
    local mode = RAT.db and RAT.db[definition.modeKey]
    return mode == "off" and "off" or mode == "history" and "history" or "show"
end

local function RowMetrics(row)
    local definitions = RAT.METRIC_DEFS or {}
    local metrics = type(row.metrics) == "table" and row.metrics or nil
    if not metrics then
        metrics = {}
        local darkest = definitions[1] and definitions[1].key or "darkestNight"
        metrics[darkest] = { successes = Counter(row.successes), attempts = Counter(row.attempts) }
    end
    for index = 1, #definitions do
        local key = definitions[index].key
        local counter = type(metrics[key]) == "table" and metrics[key] or {}
        counter.attempts = Counter(counter.attempts)
        counter.successes = math.min(Counter(counter.successes), counter.attempts)
        metrics[key] = counter
    end
    return metrics
end

local function FormatMetricSummary(row)
    local parts = {}
    local metrics = RowMetrics(row)
    local definitions = RAT.METRIC_DEFS or {}
    for index = 1, #definitions do
        local definition = definitions[index]
        if MetricMode(definition) ~= "off" then
            local counter = metrics[definition.key]
            parts[#parts + 1] = string.format("%s %d/%d %s", definition.label,
                counter.successes, counter.attempts,
                FormatPercent(Percent(counter.successes, counter.attempts)))
        end
    end
    return #parts > 0 and table.concat(parts, "   |   ") or "NO ENABLED APEX STATISTICS"
end

local function TypeLabel(historyType)
    if historyType == "currentCombat" then return "Current Combat" end
    if historyType == "currentEncounter" then return "Current Encounter" end
    if historyType == "currentKeystone" then return "Current Keystone Dungeon" end
    if historyType == "session" then return "Current Session" end
    if historyType == "encounter" then return "Encounter" end
    if historyType == "keystone" then return "Keystone Dungeon" end
    return "Last Combat"
end

local function ResultLabel(row)
    if row.current then return "Live" end
    if row.type == "encounter" then return row.killed and "Kill" or "Wipe" end
    if row.type == "keystone" then
        if not row.completed then return "Exited" end
        if row.onTime then
            local upgrades = tonumber(row.upgradeLevels) or 0
            return upgrades > 0 and string.format("Timed (+%d)", upgrades) or "Timed"
        end
        return "Completed"
    end
    return row.abandoned and "Ended" or "Completed"
end

local function FormatEncounter(index, row)
    return string.format("%d - %s (%s)", index, row.label or "Encounter", row.killed and "Kill" or "Wipe")
end

local function FormatKeystone(index, row)
    return string.format("%d - %s +%d (%s)", index, row.mapName or row.label or "Keystone",
        tonumber(row.level) or 0, ResultLabel(row))
end

local function SelectionText()
    if selection.type == "currentCombat" then
        return "Current Combat"
    elseif selection.type == "currentEncounter" then
        return "Current Encounter"
    elseif selection.type == "currentKeystone" then
        return "Current Keystone Dungeon"
    elseif selection.type == "session" then
        return "Current Session"
    elseif selection.type == "encounter" then
        if selection.index == HISTORY_LATEST then return "Last Encounter" end
        local row = RAT:GetHistoryEntry("encounter", selection.index)
        return row and FormatEncounter(selection.index, row) or "Last Encounter"
    elseif selection.type == "keystone" then
        if selection.index == HISTORY_LATEST then return "Last Keystone Dungeon" end
        local row = RAT:GetHistoryEntry("keystone", selection.index)
        return row and FormatKeystone(selection.index, row) or "Last Keystone Dungeon"
    end
    return "Last Combat"
end

local function SelectedRow()
    local currentType = CURRENT_TYPES[selection.type]
    if currentType then return RAT:GetCurrentSnapshot(currentType) end
    return RAT:GetHistoryEntry(selection.type, selection.index)
end

local function UpdateHistoryFrame()
    if not historyFrame then return end
    local row = SelectedRow()
    historyFrame.HistoryDropdown:OverrideText(SelectionText())
    historyFrame.RangeValue:SetText(SelectionText())
    if not row then
        historyFrame.TypeText:SetText(string.upper(TypeLabel(selection.type)))
        historyFrame.SummaryText:SetText("NO DATA AVAILABLE")
        historyFrame.DetailText:SetText(CURRENT_TYPES[selection.type]
            and "No matching range is active right now."
            or "Complete a matching combat range to create a snapshot.")
        historyFrame.ResultText:SetText("")
        return
    end

    historyFrame.TypeText:SetText(string.upper(TypeLabel(row.current and selection.type or row.type)))
    historyFrame.SummaryText:SetText(FormatMetricSummary(row))
    local label = row.type == "keystone"
        and string.format("%s +%d", row.mapName or row.label or "Keystone", tonumber(row.level) or 0)
        or row.label or TypeLabel(row.type)
    if row.current then
        historyFrame.DetailText:SetText(string.format("%s   |   RIGHT NOW   |   %ds",
            label, tonumber(row.duration) or 0))
    else
        local stamp = row.timestamp and row.timestamp > 0
            and date("%Y-%m-%d %H:%M", row.timestamp) or "Unknown time"
        historyFrame.DetailText:SetText(string.format("%s   |   %s   |   %ds",
            label, stamp, tonumber(row.duration) or 0))
    end
    historyFrame.ResultText:SetText(ResultLabel(row))
end

local function SelectHistory(data)
    selection.type = data.type
    selection.index = data.index or HISTORY_LATEST
    RAT.db.historySelectionType = selection.type
    UpdateHistoryFrame()
    if MenuResponse then return MenuResponse.Refresh end
end

local function IsHistorySelected(data)
    return selection.type == data.type and selection.index == (data.index or HISTORY_LATEST)
end

local function SetupHistoryMenu(dropdown, rootDescription)
    rootDescription:CreateTitle("Select Statistics Range")
    rootDescription:SetScrollMode(320)

    local currentCombatData = { type = "currentCombat" }
    local rightNow = rootDescription:CreateRadio("Right Now", IsHistorySelected, SelectHistory, currentCombatData)
    rightNow:SetTitleAndTextTooltip("Right Now",
        "Live statistics for the active combat, encounter, keystone dungeon, or client session.")
    rightNow:CreateRadio("Current Combat", IsHistorySelected, SelectHistory, currentCombatData)
    rightNow:CreateRadio("Current Encounter", IsHistorySelected, SelectHistory,
        { type = "currentEncounter" })
    rightNow:CreateRadio("Current Keystone Dungeon", IsHistorySelected, SelectHistory,
        { type = "currentKeystone" })
    rightNow:CreateRadio("Current Session", IsHistorySelected, SelectHistory,
        { type = "session" })

    local combatData = { type = "combat", index = HISTORY_LATEST }
    local combat = rootDescription:CreateRadio("Last Combat", IsHistorySelected, SelectHistory, combatData)
    combat:SetTitleAndTextTooltip("Last Combat", "APEX results from the most recently completed combat.")

    local encounterData = { type = "encounter", index = HISTORY_LATEST }
    local encounters = rootDescription:CreateRadio("Encounters", IsHistorySelected, SelectHistory, encounterData)
    encounters:SetTitleAndTextTooltip("Encounters", "Boss snapshots captured by ENCOUNTER_START and ENCOUNTER_END.")
    encounters:SetScrollMode(300)
    encounters:CreateRadio("Last Encounter", IsHistorySelected, SelectHistory, encounterData)
    local encounterRows = RAT:GetHistoryByType("encounter")
    for index = 1, #encounterRows do
        encounters:CreateRadio(FormatEncounter(index, encounterRows[index]), IsHistorySelected, SelectHistory,
            { type = "encounter", index = index })
    end

    local keystoneData = { type = "keystone", index = HISTORY_LATEST }
    local keystones = rootDescription:CreateRadio("Keystone Dungeons", IsHistorySelected, SelectHistory, keystoneData)
    keystones:SetTitleAndTextTooltip("Keystone Dungeons",
        "Full Mythic+ snapshots captured from key start until completion or exit.")
    keystones:SetScrollMode(300)
    keystones:CreateRadio("Last Keystone Dungeon", IsHistorySelected, SelectHistory, keystoneData)
    local keystoneRows = RAT:GetHistoryByType("keystone")
    for index = 1, #keystoneRows do
        keystones:CreateRadio(FormatKeystone(index, keystoneRows[index]), IsHistorySelected, SelectHistory,
            { type = "keystone", index = index })
    end
end

local function AddText(parent, text, template, point, relative, relativePoint, x, y)
    local fontString = parent:CreateFontString(nil, "OVERLAY", template)
    fontString:SetFont("Fonts\\FRIZQT__.TTF", template == "GameFontHighlightLarge" and 16 or 12,
        template == "GameFontHighlightLarge" and "OUTLINE" or "")
    fontString:SetPoint(point, relative, relativePoint, x, y)
    fontString:SetText(text or "")
    return fontString
end

local function EnsureHistoryFrame()
    if historyFrame then return historyFrame end
    local frame = CreateFrame("Frame", "RogueApexTrackerHistoryFrame", UIParent, "BackdropTemplate")
    frame:SetSize(620, 265)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    frame.Title = AddText(frame, "Rogue Apex Tracker - Statistics", "GameFontHighlightLarge",
        "TOPLEFT", frame, "TOPLEFT", 24, -20)
    frame.RangeLabel = AddText(frame, "Statistics Range", "GameFontNormal", "TOPLEFT", frame, "TOPLEFT", 28, -62)
    frame.HistoryDropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
    frame.HistoryDropdown:SetPoint("LEFT", frame.RangeLabel, "RIGHT", 12, 0)
    frame.HistoryDropdown:SetWidth(245)
    frame.HistoryDropdown:SetupMenu(SetupHistoryMenu)

    frame.RangeValue = AddText(frame, "", "GameFontHighlightSmall", "TOPRIGHT", frame, "TOPRIGHT", -30, -66)
    frame.TypeText = AddText(frame, "", "GameFontNormal", "TOPLEFT", frame, "TOPLEFT", 30, -108)
    frame.TypeText:SetTextColor(1, 0.82, 0.08, 1)
    frame.SummaryText = AddText(frame, "", "GameFontHighlightLarge", "TOPLEFT", frame, "TOPLEFT", 30, -136)
    frame.DetailText = AddText(frame, "", "GameFontHighlightSmall", "TOPLEFT", frame, "TOPLEFT", 30, -177)
    frame.ResultText = AddText(frame, "", "GameFontNormal", "TOPRIGHT", frame, "TOPRIGHT", -30, -136)
    frame.ResultText:SetTextColor(0.35, 1, 0.45, 1)

    local optionsButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    optionsButton:SetSize(110, 24)
    optionsButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 28, 24)
    optionsButton:SetText("Options")
    optionsButton:SetScript("OnClick", function() RAT:OpenOptions() end)

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeButton:SetSize(110, 24)
    closeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 24)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function() frame:Hide() end)

    local topClose = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    topClose:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
    topClose:SetScript("OnClick", function() frame:Hide() end)

    frame:SetScript("OnShow", UpdateHistoryFrame)
    frame:Hide()
    if type(UISpecialFrames) == "table" then
        UISpecialFrames[#UISpecialFrames + 1] = "RogueApexTrackerHistoryFrame"
    end
    historyFrame = frame
    return frame
end

function RAT:RefreshHistory()
    if historyFrame and historyFrame:IsShown() then UpdateHistoryFrame() end
end

function RAT:OpenHistory(historyType, index)
    local savedType = historyType or (self.db and self.db.historySelectionType) or selection.type
    selection.type = VALID_TYPES[savedType] and savedType or "combat"
    selection.index = index or HISTORY_LATEST
    local frame = EnsureHistoryFrame()
    UpdateHistoryFrame()
    frame:Show()
end

RAT._HistoryTest = {
    Selection = selection,
    EnsureFrame = EnsureHistoryFrame,
    SetupMenu = SetupHistoryMenu,
    SelectHistory = SelectHistory,
    Update = UpdateHistoryFrame,
}
