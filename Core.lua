local addonName, RAT = ...

RAT = RAT or {}
_G.RogueApexTracker = RAT

local DARKEST_NIGHT_TALENT_ID = 457058
local DARKEST_NIGHT_AURA_ID = 457280
local ANCIENT_ARTS_AURA_ID = 1269163
local SHADOW_DANCE_AURA_ID = 185422
local SHADOW_DANCE_SPELL_ID = 185313
local SUBTLETY_SPEC_ID = 261
local EVISCERATE_RANGE_SPELL_ID = 196819
local BLACK_POWDER_SPELL_ID = 319175
local SECRET_TECHNIQUE_SPELL_ID = 280719
local DANCE_LEAD_WINDOW = 3
local DANCE_CAST_GRACE = 0.50
local RANGE_SCAN_INTERVAL = 0.20
local ROLE_DARKEST = "darkestNight"
local ROLE_ANCIENT = "ancientArts"
local ROLE_DANCE = "shadowDance"
local METRIC_DARKEST = "darkestNight"
local METRIC_BLACK_POWDER = "blackPowder"
local METRIC_SECRET_TECHNIQUE = "secretTechnique"
local METRIC_DEFS = {
    { key = METRIC_DARKEST, modeKey = "darkestNightMode", short = "DN", label = "DARKEST" },
    { key = METRIC_BLACK_POWDER, modeKey = "blackPowderMode", short = "BP", label = "BLACK POWDER" },
    { key = METRIC_SECRET_TECHNIQUE, modeKey = "secretTechniqueMode", short = "ST", label = "SECTECH" },
}
local DEFAULT_METRIC_ORDER = "darkestNight,blackPowder,secretTechnique"
local METRIC_ORDER_KEYS = {
    ["darkestNight,blackPowder,secretTechnique"] = {
        METRIC_DARKEST, METRIC_BLACK_POWDER, METRIC_SECRET_TECHNIQUE,
    },
    ["darkestNight,secretTechnique,blackPowder"] = {
        METRIC_DARKEST, METRIC_SECRET_TECHNIQUE, METRIC_BLACK_POWDER,
    },
    ["blackPowder,darkestNight,secretTechnique"] = {
        METRIC_BLACK_POWDER, METRIC_DARKEST, METRIC_SECRET_TECHNIQUE,
    },
    ["blackPowder,secretTechnique,darkestNight"] = {
        METRIC_BLACK_POWDER, METRIC_SECRET_TECHNIQUE, METRIC_DARKEST,
    },
    ["secretTechnique,darkestNight,blackPowder"] = {
        METRIC_SECRET_TECHNIQUE, METRIC_DARKEST, METRIC_BLACK_POWDER,
    },
    ["secretTechnique,blackPowder,darkestNight"] = {
        METRIC_SECRET_TECHNIQUE, METRIC_BLACK_POWDER, METRIC_DARKEST,
    },
}
local METRIC_DEF_BY_KEY = {}
for index = 1, #METRIC_DEFS do
    METRIC_DEF_BY_KEY[METRIC_DEFS[index].key] = METRIC_DEFS[index]
end
local VALID_STATS_LAYOUT = { compact = true, rangeRows = true, metricRows = true }
local VIEWER_NAMES = { "EssentialCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"

local defaults = {
    enabled = true,
    locked = false,
    showHeader = true,
    showBackground = false,
    fontPath = FALLBACK_FONT,
    fontName = "Friz Quadrata TT",
    outline = "OUTLINE",
    shadow = true,
    headerSize = 15,
    statsSize = 22,
    scale = 1,
    offsetX = 0,
    offsetY = 220,
    decimals = 1,
    headerColor = { 1, 0.82, 0.08, 1 },
    statsColor = { 1, 1, 1, 1 },
    backgroundColor = { 0.025, 0.025, 0.035, 1 },
    backgroundTextureName = "Solid",
    backgroundTexturePath = "Interface\\Buttons\\WHITE8X8",
    backgroundAlpha = 0.86,
    historyLimit = 20,
    historyOnlyWithAttempts = true,
    onlyCountBelowFourTargets = true,
    darkestNightMode = "show",
    blackPowderMode = "show",
    secretTechniqueMode = "show",
    statsLayout = "compact",
    metricOrder = DEFAULT_METRIC_ORDER,
    showCurrentCombat = true,
    showCurrentEncounter = false,
    showCurrentDungeon = true,
    showSession = true,
    showLastCombat = false,
    showLastEncounter = false,
    showLastDungeon = false,
    trainingMode = false,
    trainingLocked = true,
    trainingDuration = 2,
    trainingSize = 30,
    trainingScale = 1,
    trainingOffsetX = 0,
    trainingOffsetY = 120,
    trainingColor = { 1, 0.18, 0.08, 1 },
    historySelectionType = "combat",
    history = {},
}
RAT.DEFAULTS = defaults
RAT.METRIC_DEFS = METRIC_DEFS

local state = {
    encounterAttempts = 0,
    encounterSuccesses = 0,
    sessionAttempts = 0,
    sessionSuccesses = 0,
    pendingEviscerate = nil,
    recentPreDanceEviscerate = nil,
    pendingAoeFinisher = nil,
    lastDanceStartedAt = nil,
    preview = false,
    combatSegment = nil,
    encounterSegment = nil,
    keystoneSegment = nil,
    sessionID = nil,
    rangeSnapshotValid = false,
    inRangeTargetCount = 0,
    trainingAlertActive = false,
    trainingPreviewActive = false,
    trainingAlertGeneration = 0,
    encounterMetrics = {},
    sessionMetrics = {},
}

local roleByCooldownID = {}
local roleByFrame = {}
local activeByFrame = {}
local hookedFrames = {}
local hookedViewers = {}
local refreshBusy = false
local deathstalkerKnown = false
local display
local headerText
local statsText
local moverText
local trainingDisplay
local trainingText
local trainingMoverText
local trainingAlertTimer
local eventFrame
local rangeEventFrame
local rangeTimer
local rangeTimerGeneration = 0
local rangeScanPending = false
local rangeUnits = {}

local function IsSecret(value)
    return type(_G.issecretvalue) == "function" and _G.issecretvalue(value) == true
end

local function Clamp(value, low, high)
    value = tonumber(value) or low
    if value < low then return low end
    if value > high then return high end
    return value
end

local function CopyDefaults(target, source)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then target[key] = {} end
            CopyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

local function EpochNow()
    local getter = type(GetServerTime) == "function" and GetServerTime or time
    if type(getter) ~= "function" then return nil end
    local ok, value = pcall(getter)
    if ok and type(value) == "number" then return value end
end

local function MonotonicNow()
    if type(GetTime) ~= "function" then return nil end
    local ok, value = pcall(GetTime)
    if ok and type(value) == "number" and not IsSecret(value) then return value end
end

local function ClientStartedAt()
    local epoch = EpochNow()
    if type(epoch) ~= "number" or type(GetTime) ~= "function" then return nil end
    local ok, uptime = pcall(GetTime)
    if not ok or type(uptime) ~= "number" then return nil end
    return math.floor((epoch - uptime) + 0.5)
end

local function NewSessionID()
    local epoch = EpochNow()
    if type(date) == "function" then
        local ok, value
        if type(epoch) == "number" then ok, value = pcall(date, "%Y%m%d-%H%M%S", epoch)
        else ok, value = pcall(date, "%Y%m%d-%H%M%S") end
        if ok and type(value) == "string" then return value end
    end
    return tostring(epoch or 0)
end

local function Counter(value)
    value = math.floor(tonumber(value) or 0)
    return math.max(0, value)
end

local function NewMetricCounters()
    return {
        [METRIC_DARKEST] = { successes = 0, attempts = 0 },
        [METRIC_BLACK_POWDER] = { successes = 0, attempts = 0 },
        [METRIC_SECRET_TECHNIQUE] = { successes = 0, attempts = 0 },
    }
end

local function NormalizeMetricCounters(metrics)
    if type(metrics) ~= "table" then metrics = {} end
    for index = 1, #METRIC_DEFS do
        local key = METRIC_DEFS[index].key
        local counter = type(metrics[key]) == "table" and metrics[key] or {}
        counter.attempts = Counter(counter.attempts)
        counter.successes = math.min(Counter(counter.successes), counter.attempts)
        metrics[key] = counter
    end
    return metrics
end

local function CopyMetricCounters(metrics)
    metrics = NormalizeMetricCounters(metrics)
    local result = NewMetricCounters()
    for index = 1, #METRIC_DEFS do
        local key = METRIC_DEFS[index].key
        result[key].attempts = metrics[key].attempts
        result[key].successes = metrics[key].successes
    end
    return result
end

local function EnsureOwnerMetrics(owner)
    if type(owner) ~= "table" then return NewMetricCounters() end
    if type(owner.metrics) ~= "table" then
        owner.metrics = NewMetricCounters()
        -- Existing 1.3.x data represented only the Darkest Night statistic.
        owner.metrics[METRIC_DARKEST].attempts = Counter(owner.attempts)
        owner.metrics[METRIC_DARKEST].successes = math.min(
            Counter(owner.successes), owner.metrics[METRIC_DARKEST].attempts)
    end
    owner.metrics = NormalizeMetricCounters(owner.metrics)
    return owner.metrics
end

local function MetricTotals(metrics)
    local successes, attempts = 0, 0
    metrics = NormalizeMetricCounters(metrics)
    for index = 1, #METRIC_DEFS do
        local counter = metrics[METRIC_DEFS[index].key]
        successes = successes + counter.successes
        attempts = attempts + counter.attempts
    end
    return successes, attempts
end

local function SyncOwnerTotals(owner)
    if type(owner) ~= "table" then return end
    owner.successes, owner.attempts = MetricTotals(EnsureOwnerMetrics(owner))
end

local function MetricMode(metricKey)
    for index = 1, #METRIC_DEFS do
        local definition = METRIC_DEFS[index]
        if definition.key == metricKey then
            local mode = RAT.db and RAT.db[definition.modeKey]
            if mode == "off" or mode == "history" or mode == "show" then return mode end
            return "show"
        end
    end
    return "off"
end

local function MetricIsTracked(metricKey)
    return MetricMode(metricKey) ~= "off"
end

local function MetricIsShown(metricKey)
    return MetricMode(metricKey) == "show"
end

local function AnyMetricShown()
    for index = 1, #METRIC_DEFS do
        if MetricIsShown(METRIC_DEFS[index].key) then return true end
    end
    return false
end

local function SyncStateTotals()
    state.encounterMetrics = NormalizeMetricCounters(state.encounterMetrics)
    state.sessionMetrics = NormalizeMetricCounters(state.sessionMetrics)
    state.encounterSuccesses, state.encounterAttempts = MetricTotals(state.encounterMetrics)
    state.sessionSuccesses, state.sessionAttempts = MetricTotals(state.sessionMetrics)
end

local function SaveSessionState()
    if not RAT.db then return end
    SyncStateTotals()
    local saved = RAT.db.sessionState
    if type(saved) ~= "table" then
        saved = {}
        RAT.db.sessionState = saved
    end
    saved.id = state.sessionID
    saved.clientStartedAt = state.clientStartedAt
    saved.encounterAttempts = state.encounterAttempts
    saved.encounterSuccesses = state.encounterSuccesses
    saved.sessionAttempts = state.sessionAttempts
    saved.sessionSuccesses = state.sessionSuccesses
    saved.encounterMetrics = CopyMetricCounters(state.encounterMetrics)
    saved.sessionMetrics = CopyMetricCounters(state.sessionMetrics)
end

local function StartNewSession()
    state.encounterAttempts = 0
    state.encounterSuccesses = 0
    state.sessionAttempts = 0
    state.sessionSuccesses = 0
    state.encounterMetrics = NewMetricCounters()
    state.sessionMetrics = NewMetricCounters()
    state.sessionID = NewSessionID()
    state.clientStartedAt = ClientStartedAt()
    SaveSessionState()
end

local function RestoreSessionState()
    local saved = RAT.db and RAT.db.sessionState
    local clientStartedAt = ClientStartedAt()
    local savedClientStartedAt = type(saved) == "table" and tonumber(saved.clientStartedAt) or nil
    local sameClient = type(saved) == "table" and (
        clientStartedAt == nil
        or savedClientStartedAt == nil
        or math.abs(savedClientStartedAt - clientStartedAt) <= 5
    )

    if not sameClient then
        StartNewSession()
        return false
    end

    state.clientStartedAt = clientStartedAt or savedClientStartedAt
    state.sessionID = type(saved.id) == "string" and saved.id or NewSessionID()
    if type(saved.encounterMetrics) == "table" then
        state.encounterMetrics = CopyMetricCounters(saved.encounterMetrics)
    else
        state.encounterMetrics = NewMetricCounters()
        state.encounterMetrics[METRIC_DARKEST].attempts = Counter(saved.encounterAttempts)
        state.encounterMetrics[METRIC_DARKEST].successes = math.min(
            Counter(saved.encounterSuccesses), state.encounterMetrics[METRIC_DARKEST].attempts)
    end
    if type(saved.sessionMetrics) == "table" then
        state.sessionMetrics = CopyMetricCounters(saved.sessionMetrics)
    else
        state.sessionMetrics = NewMetricCounters()
        state.sessionMetrics[METRIC_DARKEST].attempts = Counter(saved.sessionAttempts)
        state.sessionMetrics[METRIC_DARKEST].successes = math.min(
            Counter(saved.sessionSuccesses), state.sessionMetrics[METRIC_DARKEST].attempts)
    end
    SyncStateTotals()
    SaveSessionState()
    return true
end

local function GetSpecID()
    if type(GetSpecialization) ~= "function" or type(GetSpecializationInfo) ~= "function" then return nil end
    local index = GetSpecialization()
    if not index then return nil end
    local specID = GetSpecializationInfo(index)
    if IsSecret(specID) then return nil end
    return specID
end

local function RefreshDeathstalkerKnown()
    deathstalkerKnown = false
    local isKnown = C_SpellBook and C_SpellBook.IsSpellKnown
    if type(isKnown) ~= "function" then return end
    local ok, known = pcall(isKnown, DARKEST_NIGHT_TALENT_ID)
    if ok and not IsSecret(known) then deathstalkerKnown = known == true end
end

local function IsEligible()
    return RAT.db and RAT.db.enabled == true
        and GetSpecID() == SUBTLETY_SPEC_ID
        and deathstalkerKnown == true
end

local function RangeTrackingActive()
    return IsEligible() and (
        RAT.db.onlyCountBelowFourTargets == true
        or MetricIsTracked(METRIC_BLACK_POWDER)
        or MetricIsTracked(METRIC_SECRET_TECHNIQUE)
    )
end

local function IsNameplateUnit(unit)
    return type(unit) == "string" and unit:match("^nameplate%d+$") ~= nil
end

local function InvalidateRangeSnapshot()
    state.rangeSnapshotValid = false
    state.inRangeTargetCount = 0
end

local function CancelRangeTimer()
    rangeTimerGeneration = rangeTimerGeneration + 1
    local timer = rangeTimer
    rangeTimer = nil
    if timer and type(timer.Cancel) == "function" then timer:Cancel() end
end

local function ClearRangeUnits()
    for unit in pairs(rangeUnits) do rangeUnits[unit] = nil end
    InvalidateRangeSnapshot()
end

local function SeedRangeUnits()
    for unit in pairs(rangeUnits) do rangeUnits[unit] = nil end
    local getNamePlates = C_NamePlate and C_NamePlate.GetNamePlates
    if type(getNamePlates) ~= "function" then return end
    local ok, nameplates = pcall(getNamePlates)
    if not ok or type(nameplates) ~= "table" then return end
    for index = 1, #nameplates do
        local nameplate = nameplates[index]
        local getUnit = nameplate and nameplate.GetUnit
        if type(getUnit) == "function" then
            local unitOK, unit = pcall(getUnit, nameplate)
            if unitOK and IsNameplateUnit(unit) then rangeUnits[unit] = true end
        end
    end
end

local ArmRangeTimer
local RunRangeScan

RunRangeScan = function()
    rangeScanPending = false
    if not RangeTrackingActive() then
        CancelRangeTimer()
        InvalidateRangeSnapshot()
        return
    end

    local inRange, invalid = 0, 0
    local rangeAPI = C_Spell and C_Spell.IsSpellInRange
    for unit in pairs(rangeUnits) do
        local existsOK, exists = pcall(UnitExists, unit)
        if not existsOK or IsSecret(exists) then
            invalid = invalid + 1
        elseif exists ~= true then
            rangeUnits[unit] = nil
        else
            local attackOK, canAttack = pcall(UnitCanAttack, "player", unit)
            local deadOK, isDead = pcall(UnitIsDeadOrGhost, unit)
            if not attackOK or not deadOK or IsSecret(canAttack) or IsSecret(isDead) then
                invalid = invalid + 1
            elseif canAttack == true and isDead ~= true then
                local rangeOK, result
                if type(rangeAPI) == "function" then
                    rangeOK, result = pcall(rangeAPI, EVISCERATE_RANGE_SPELL_ID, unit)
                end
                if not rangeOK or IsSecret(result) or result == nil then
                    invalid = invalid + 1
                elseif result == true or result == 1 then
                    inRange = inRange + 1
                end
            end
        end
    end

    state.rangeSnapshotValid = invalid == 0
    state.inRangeTargetCount = inRange
    ArmRangeTimer()
end

ArmRangeTimer = function()
    CancelRangeTimer()
    if not RangeTrackingActive() or next(rangeUnits) == nil then return end
    local generation = rangeTimerGeneration
    local function OnTimer()
        if generation ~= rangeTimerGeneration then return end
        rangeTimer = nil
        RunRangeScan()
    end
    if C_Timer and type(C_Timer.NewTimer) == "function" then
        rangeTimer = C_Timer.NewTimer(RANGE_SCAN_INTERVAL, OnTimer)
    elseif C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(RANGE_SCAN_INTERVAL, OnTimer)
    end
end

local function RequestRangeScan()
    if not RangeTrackingActive() or rangeScanPending then return end
    rangeScanPending = true
    local function Flush()
        rangeScanPending = false
        RunRangeScan()
    end
    if C_Timer and type(C_Timer.After) == "function" then C_Timer.After(0, Flush)
    else Flush() end
end

local function EnsureRangeEventFrame()
    if rangeEventFrame then return rangeEventFrame end
    rangeEventFrame = CreateFrame("Frame")
    rangeEventFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "NAME_PLATE_UNIT_ADDED" then
            if IsNameplateUnit(unit) then rangeUnits[unit] = true end
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            if IsNameplateUnit(unit) then rangeUnits[unit] = nil end
        else
            SeedRangeUnits()
        end
        InvalidateRangeSnapshot()
        RequestRangeScan()
    end)
    return rangeEventFrame
end

local function ApplyRangeTracking(forceDisabled)
    local events = EnsureRangeEventFrame()
    events:UnregisterAllEvents()
    CancelRangeTimer()
    rangeScanPending = false
    if forceDisabled == true or not RangeTrackingActive() then
        ClearRangeUnits()
        return
    end
    events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    SeedRangeUnits()
    RunRangeScan()
end

local function DarkestNightTargetRuleEligible()
    if not (RAT.db and RAT.db.onlyCountBelowFourTargets == true) then return true end
    return state.rangeSnapshotValid == true
        and state.inRangeTargetCount >= 1
        and state.inRangeTargetCount < 4
end

local function AoeTargetRuleEligible()
    return state.rangeSnapshotValid == true and state.inRangeTargetCount >= 4
end

local function SafeActive(frame)
    if not frame or type(frame.IsActive) ~= "function" then return false end
    local ok, active = pcall(frame.IsActive, frame)
    return ok and not IsSecret(active) and active == true
end

local function RoleIsActive(role)
    for frame, frameRole in pairs(roleByFrame) do
        if frameRole == role and activeByFrame[frame] == true then return true end
    end
    return false
end

local function RefreshRoleActivity()
    for frame in pairs(roleByFrame) do
        activeByFrame[frame] = SafeActive(frame)
    end
end

local function PlainSpellMatch(value, expected)
    return not IsSecret(value) and type(value) == "number" and value == expected
end

local function IsSpellOrBaseSpellID(spellID, expectedSpellID)
    if IsSecret(spellID) or type(spellID) ~= "number" then return false end
    if spellID == expectedSpellID then return true end
    local findBase = C_SpellBook and C_SpellBook.FindBaseSpellByID
    if type(findBase) ~= "function" then return false end
    local ok, baseSpellID = pcall(findBase, spellID)
    return ok and PlainSpellMatch(baseSpellID, expectedSpellID)
end

local function IsEviscerateSpellID(spellID)
    return IsSpellOrBaseSpellID(spellID, EVISCERATE_RANGE_SPELL_ID)
end

local function IsBlackPowderSpellID(spellID)
    return IsSpellOrBaseSpellID(spellID, BLACK_POWDER_SPELL_ID)
end

local function IsSecretTechniqueSpellID(spellID)
    return IsSpellOrBaseSpellID(spellID, SECRET_TECHNIQUE_SPELL_ID)
end

local function IsShadowDanceSpellID(spellID)
    return IsSpellOrBaseSpellID(spellID, SHADOW_DANCE_SPELL_ID)
end

local function CooldownInfoContainsSpell(info, spellID)
    if type(info) ~= "table" then return false end
    if PlainSpellMatch(info.spellID, spellID)
        or PlainSpellMatch(info.overrideSpellID, spellID)
        or PlainSpellMatch(info.overrideTooltipSpellID, spellID)
        or PlainSpellMatch(info.linkedSpellID, spellID) then
        return true
    end
    if type(info.linkedSpellIDs) == "table" then
        for index = 1, #info.linkedSpellIDs do
            if PlainSpellMatch(info.linkedSpellIDs[index], spellID) then return true end
        end
    end
    return false
end

local function ResolveFrameRole(frame)
    if not frame or type(frame.GetCooldownID) ~= "function" then return nil end
    local ok, cooldownID = pcall(frame.GetCooldownID, frame)
    if not ok or IsSecret(cooldownID) or type(cooldownID) ~= "number" then return nil end
    local cached = roleByCooldownID[cooldownID]
    if cached ~= nil then return cached or nil end

    local info
    if C_CooldownViewer and type(C_CooldownViewer.GetCooldownViewerCooldownInfo) == "function" then
        local infoOK, result = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
        if infoOK and not IsSecret(result) then info = result end
    end
    if not info and type(frame.GetCooldownInfo) == "function" then
        local infoOK, result = pcall(frame.GetCooldownInfo, frame)
        if infoOK and not IsSecret(result) then info = result end
    end

    local role
    if CooldownInfoContainsSpell(info, DARKEST_NIGHT_AURA_ID) then
        role = ROLE_DARKEST
    elseif CooldownInfoContainsSpell(info, ANCIENT_ARTS_AURA_ID) then
        role = ROLE_ANCIENT
    elseif CooldownInfoContainsSpell(info, SHADOW_DANCE_AURA_ID) then
        role = ROLE_DANCE
    end
    roleByCooldownID[cooldownID] = role or false
    return role
end

local function Percent(successes, attempts)
    return attempts > 0 and successes * 100 / attempts or 0
end

local function FormatPercent(value)
    local decimals = Clamp(RAT.db and RAT.db.decimals or 1, 0, 2)
    if decimals == 0 then return string.format("%.0f%%", value) end
    if decimals == 2 then return string.format("%.2f%%", value) end
    return string.format("%.1f%%", value)
end

local function SetShadow(fontString, enabled)
    if not fontString then return end
    if enabled then
        fontString:SetShadowColor(0, 0, 0, 0.95)
        fontString:SetShadowOffset(1, -1)
    else
        fontString:SetShadowColor(0, 0, 0, 0)
        fontString:SetShadowOffset(0, 0)
    end
end

local function ApplyFont(fontString, size)
    if not fontString then return end
    local path = RAT.db.fontPath or FALLBACK_FONT
    local outline = RAT.db.outline or "OUTLINE"
    local ok = fontString:SetFont(path, size, outline)
    if not ok then
        RAT.db.fontPath = FALLBACK_FONT
        RAT.db.fontName = defaults.fontName
        fontString:SetFont(FALLBACK_FONT, size, outline)
    end
end

local function RefreshText()
    if not statsText then return end

    local orderedKeys = METRIC_ORDER_KEYS[RAT.db and RAT.db.metricOrder]
        or METRIC_ORDER_KEYS[DEFAULT_METRIC_ORDER]
    local visibleMetrics = {}
    for index = 1, #orderedKeys do
        local definition = METRIC_DEF_BY_KEY[orderedKeys[index]]
        if definition and MetricIsShown(definition.key) then
            visibleMetrics[#visibleMetrics + 1] = definition
        end
    end
    if #visibleMetrics == 0 then
        statsText:SetText("")
        statsText:Hide()
        if display then display:SetHeight(72) end
        if RAT.RefreshOptions then RAT:RefreshOptions() end
        if RAT.RefreshHistory then RAT:RefreshHistory() end
        return
    end

    local function PreviewMetrics(seed)
        local metrics = NewMetricCounters()
        metrics[METRIC_DARKEST].successes, metrics[METRIC_DARKEST].attempts = seed, seed + 1
        metrics[METRIC_BLACK_POWDER].successes, metrics[METRIC_BLACK_POWDER].attempts = seed + 1, seed + 2
        metrics[METRIC_SECRET_TECHNIQUE].successes, metrics[METRIC_SECRET_TECHNIQUE].attempts = seed + 2, seed + 2
        return metrics
    end

    local function FormatRange(label, metrics)
        metrics = NormalizeMetricCounters(metrics)
        if #visibleMetrics == 0 then return nil end

        local parts = { label }
        for index = 1, #visibleMetrics do
            local definition = visibleMetrics[index]
            local counter = metrics[definition.key]
            if #visibleMetrics == 1 then
                parts[#parts + 1] = string.format("%s %d/%d %s", definition.label,
                    counter.successes, counter.attempts,
                    FormatPercent(Percent(counter.successes, counter.attempts)))
            else
                parts[#parts + 1] = string.format("%s %d/%d", definition.short,
                    counter.successes, counter.attempts)
            end
        end
        return table.concat(parts, "   ")
    end

    local function AddRange(parts, enabled, label, row, previewSeed)
        if enabled ~= true then return end
        local metrics
        if state.preview then
            metrics = PreviewMetrics(previewSeed)
        elseif row then
            metrics = EnsureOwnerMetrics(row)
        end
        if metrics then
            parts[#parts + 1] = {
                label = label,
                metrics = metrics,
                text = FormatRange(label, metrics),
            }
        end
    end

    local function LatestHistory(historyType)
        local history = RAT.db and RAT.db.history or {}
        for index = 1, #history do
            local row = history[index]
            if type(row) == "table" and row.type == historyType then return row end
        end
    end

    local current, archived = {}, {}
    local combat = state.combatSegment or { metrics = NewMetricCounters() }
    AddRange(current, RAT.db.showCurrentCombat, "COMBAT", combat, 1)
    AddRange(current, RAT.db.showCurrentEncounter, "ENCOUNTER", state.encounterSegment, 2)
    AddRange(current, RAT.db.showCurrentDungeon, "DUNGEON", state.keystoneSegment, 3)
    AddRange(current, RAT.db.showSession, "SESSION", {
        metrics = state.sessionMetrics,
    }, 4)

    AddRange(archived, RAT.db.showLastCombat, "LAST COMBAT", LatestHistory("combat"), 5)
    AddRange(archived, RAT.db.showLastEncounter, "LAST ENCOUNTER", LatestHistory("encounter"), 6)
    AddRange(archived, RAT.db.showLastDungeon, "LAST DUNGEON", LatestHistory("keystone"), 7)

    local lines = {}
    local layout = VALID_STATS_LAYOUT[RAT.db and RAT.db.statsLayout]
        and RAT.db.statsLayout or defaults.statsLayout
    if layout == "metricRows" then
        local ranges = {}
        for index = 1, #current do ranges[#ranges + 1] = current[index] end
        for index = 1, #archived do ranges[#ranges + 1] = archived[index] end
        for metricIndex = 1, #visibleMetrics do
            local definition = visibleMetrics[metricIndex]
            local parts = { definition.label }
            for rangeIndex = 1, #ranges do
                local range = ranges[rangeIndex]
                local counter = range.metrics[definition.key]
                parts[#parts + 1] = string.format("%s %d/%d %s", range.label,
                    counter.successes, counter.attempts,
                    FormatPercent(Percent(counter.successes, counter.attempts)))
            end
            lines[#lines + 1] = table.concat(parts, "   ")
        end
    elseif layout == "rangeRows" then
        for index = 1, #current do lines[#lines + 1] = current[index].text end
        for index = 1, #archived do lines[#lines + 1] = archived[index].text end
    else
        local function AppendWrapped(parts)
            if #parts == 0 then return end
            if #parts <= 3 then
                local texts = {}
                for index = 1, #parts do texts[index] = parts[index].text end
                lines[#lines + 1] = table.concat(texts, "   ")
            else
                lines[#lines + 1] = parts[1].text .. "   " .. parts[2].text
                lines[#lines + 1] = parts[3].text .. "   " .. parts[4].text
            end
        end
        AppendWrapped(current)
        AppendWrapped(archived)
    end

    statsText:SetText(table.concat(lines, "\n"))
    statsText:SetShown(#lines > 0)
    if display then
        local statsSize = Clamp(RAT.db and RAT.db.statsSize or defaults.statsSize, 10, 48)
        display:SetHeight(math.max(72, 72 + ((#lines - 1) * (statsSize + 10))))
    end
    if RAT.RefreshOptions then RAT:RefreshOptions() end
    if RAT.RefreshHistory then RAT:RefreshHistory() end
end

local function StorePosition()
    if not display or not RAT.db then return end
    local centerX, centerY = display:GetCenter()
    local rootX, rootY = UIParent:GetCenter()
    if not centerX or not centerY or not rootX or not rootY then return end
    local frameScale = display:GetEffectiveScale() or 1
    local rootScale = UIParent:GetEffectiveScale() or frameScale
    if frameScale <= 0 then frameScale = 1 end
    if rootScale <= 0 then rootScale = frameScale end
    RAT.db.offsetX = math.floor((((centerX * frameScale) - (rootX * rootScale)) / frameScale) + 0.5)
    RAT.db.offsetY = math.floor((((centerY * frameScale) - (rootY * rootScale)) / frameScale) + 0.5)
end

local function StoreTrainingPosition()
    if not trainingDisplay or not RAT.db then return end
    local centerX, centerY = trainingDisplay:GetCenter()
    local rootX, rootY = UIParent:GetCenter()
    if not centerX or not centerY or not rootX or not rootY then return end
    local frameScale = trainingDisplay:GetEffectiveScale() or 1
    local rootScale = UIParent:GetEffectiveScale() or frameScale
    if frameScale <= 0 then frameScale = 1 end
    if rootScale <= 0 then rootScale = frameScale end
    RAT.db.trainingOffsetX = math.floor((((centerX * frameScale) - (rootX * rootScale)) / frameScale) + 0.5)
    RAT.db.trainingOffsetY = math.floor((((centerY * frameScale) - (rootY * rootScale)) / frameScale) + 0.5)
end

local function EnsureTrainingDisplay()
    trainingDisplay = trainingDisplay or _G.RogueApexTrackerTrainingFrame
    if not trainingDisplay then
        trainingDisplay = CreateFrame("Frame", "RogueApexTrackerTrainingFrame", UIParent)
    end
    if not trainingDisplay._ratConfigured then
        trainingDisplay:SetSize(620, 64)
        trainingDisplay:SetFrameStrata("DIALOG")
        trainingDisplay:SetClampedToScreen(true)
        trainingDisplay:SetMovable(true)
        trainingDisplay:RegisterForDrag("LeftButton")
        trainingDisplay:SetScript("OnDragStart", function(self)
            if RAT.db.trainingLocked then return end
            self:StartMoving()
        end)
        trainingDisplay:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            StoreTrainingPosition()
            RAT:ApplySettings()
            if RAT.RefreshOptions then RAT:RefreshOptions() end
        end)
        trainingDisplay:SetScript("OnMouseUp", function(_, button)
            if button == "RightButton" then RAT:OpenOptions() end
        end)
        trainingDisplay._ratConfigured = true
    end

    trainingText = trainingText or trainingDisplay._ratTrainingText
    if not trainingText then
        trainingText = trainingDisplay:CreateFontString(nil, "OVERLAY")
        trainingDisplay._ratTrainingText = trainingText
        trainingText:SetPoint("CENTER", trainingDisplay, "CENTER", 0, 0)
        trainingText:SetFont(FALLBACK_FONT, defaults.trainingSize, defaults.outline)
        trainingText:SetText("APEX MISSED - BEFORE SHADOW DANCE")
    end

    trainingMoverText = trainingMoverText or trainingDisplay._ratTrainingMoverText
    if not trainingMoverText then
        trainingMoverText = trainingDisplay:CreateFontString(nil, "OVERLAY")
        trainingDisplay._ratTrainingMoverText = trainingMoverText
        trainingMoverText:SetPoint("BOTTOM", trainingDisplay, "TOP", 0, 2)
        trainingMoverText:SetFont(FALLBACK_FONT, 11, "OUTLINE")
        trainingMoverText:SetTextColor(0.22, 0.78, 0.94, 1)
        trainingMoverText:SetText("TRAINING ALERT - DRAG TO MOVE")
        trainingMoverText:Hide()
    end
    return trainingDisplay
end

local function CancelTrainingAlertTimer()
    state.trainingAlertGeneration = state.trainingAlertGeneration + 1
    local timer = trainingAlertTimer
    trainingAlertTimer = nil
    if timer and type(timer.Cancel) == "function" then timer:Cancel() end
end

local function ApplyTrainingSettings()
    if not RAT.db then return end
    local frame = EnsureTrainingDisplay()
    local enabled = RAT.db.trainingMode == true or state.trainingPreviewActive == true
    if RAT.db.trainingMode ~= true and state.trainingAlertActive and state.trainingPreviewActive ~= true then
        CancelTrainingAlertTimer()
        state.trainingAlertActive = false
    end
    local unlocked = enabled and RAT.db.trainingLocked ~= true
    frame:SetScale(Clamp(RAT.db.trainingScale, 0.5, 2))
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER",
        Clamp(RAT.db.trainingOffsetX, -2000, 2000),
        Clamp(RAT.db.trainingOffsetY, -1200, 1200))
    frame:EnableMouse(unlocked)
    trainingMoverText:SetShown(unlocked)
    trainingText:SetText(state.trainingAlertActive
        and "APEX MISSED - BEFORE SHADOW DANCE" or "APEX TRAINING")
    ApplyFont(trainingText, Clamp(RAT.db.trainingSize, 12, 64))
    local color = RAT.db.trainingColor or defaults.trainingColor
    trainingText:SetTextColor(color[1] or 1, color[2] or 0.18, color[3] or 0.08, color[4] or 1)
    SetShadow(trainingText, RAT.db.shadow ~= false)
    frame:SetAlpha(state.trainingAlertActive and 1 or 0.65)
    frame:SetShown(enabled and (state.trainingAlertActive or unlocked))
end

local function ShowTrainingFailure(preview)
    if not RAT.db or (RAT.db.trainingMode ~= true and preview ~= true) then return false end
    CancelTrainingAlertTimer()
    state.trainingAlertActive = true
    state.trainingPreviewActive = preview == true
    local generation = state.trainingAlertGeneration
    ApplyTrainingSettings()
    local function HideAlert()
        if generation ~= state.trainingAlertGeneration then return end
        trainingAlertTimer = nil
        state.trainingAlertActive = false
        state.trainingPreviewActive = false
        ApplyTrainingSettings()
    end
    local duration = Clamp(RAT.db.trainingDuration, 0.5, 5)
    if C_Timer and type(C_Timer.NewTimer) == "function" then
        trainingAlertTimer = C_Timer.NewTimer(duration, HideAlert)
    elseif C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(duration, HideAlert)
    end
    return true
end

local function EnsureDisplay()
    display = display or _G.RogueApexTrackerFrame
    if not display then
        display = CreateFrame("Frame", "RogueApexTrackerFrame", UIParent, "BackdropTemplate")
    end
    if not display._ratConfigured then
        display:SetSize(680, 72)
        display:SetFrameStrata("DIALOG")
        display:SetClampedToScreen(true)
        display:SetMovable(true)
        display:RegisterForDrag("LeftButton")
        display:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        display:SetScript("OnDragStart", function(self)
            if RAT.db.locked then return end
            self:StartMoving()
        end)
        display:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            StorePosition()
            RAT:ApplySettings()
            if RAT.RefreshOptions then RAT:RefreshOptions() end
        end)
        display:SetScript("OnMouseUp", function(_, button)
            if button == "RightButton" then RAT:OpenOptions() end
        end)
        display._ratConfigured = true
    end

    headerText = headerText or display._ratHeaderText
    if not headerText then
        headerText = display:CreateFontString(nil, "OVERLAY")
        display._ratHeaderText = headerText
        headerText:SetPoint("BOTTOM", display, "CENTER", 0, 4)
        headerText:SetFont(FALLBACK_FONT, defaults.headerSize, defaults.outline)
        headerText:SetText("APEX EMPOWERMENT")
    end

    statsText = statsText or display._ratStatsText
    if not statsText then
        statsText = display:CreateFontString(nil, "OVERLAY")
        display._ratStatsText = statsText
        statsText:SetPoint("TOP", display, "CENTER", 0, -1)
        statsText:SetFont(FALLBACK_FONT, defaults.statsSize, defaults.outline)
    end

    moverText = moverText or display._ratMoverText
    if not moverText then
        moverText = display:CreateFontString(nil, "OVERLAY")
        display._ratMoverText = moverText
        moverText:SetPoint("BOTTOM", display, "TOP", 0, 2)
        moverText:SetFont(FALLBACK_FONT, 11, "OUTLINE")
        moverText:SetTextColor(0.22, 0.78, 0.94, 1)
        moverText:SetText("DRAG TO MOVE  •  RIGHT CLICK FOR OPTIONS")
        moverText:Hide()
    end
    return display
end

function RAT:ApplySettings()
    if not self.db then return end
    local frame = EnsureDisplay()
    local headerSize = Clamp(self.db.headerSize, 9, 40)
    local statsSize = Clamp(self.db.statsSize, 10, 48)
    frame:SetScale(Clamp(self.db.scale, 0.5, 2))
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", Clamp(self.db.offsetX, -2000, 2000), Clamp(self.db.offsetY, -1200, 1200))
    frame:EnableMouse(self.db.locked ~= true)
    moverText:SetShown(self.db.locked ~= true)
    headerText:SetShown(self.db.showHeader ~= false)
    ApplyFont(headerText, headerSize)
    ApplyFont(statsText, statsSize)
    local hc = self.db.headerColor or defaults.headerColor
    local sc = self.db.statsColor or defaults.statsColor
    local bc = self.db.backgroundColor or defaults.backgroundColor
    local backgroundPath = type(self.db.backgroundTexturePath) == "string"
        and self.db.backgroundTexturePath ~= "" and self.db.backgroundTexturePath
        or defaults.backgroundTexturePath
    if frame._ratBackgroundPath ~= backgroundPath then
        frame:SetBackdrop({
            bgFile = backgroundPath,
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        frame._ratBackgroundPath = backgroundPath
    end
    headerText:SetTextColor(hc[1] or 1, hc[2] or 0.82, hc[3] or 0.08, hc[4] or 1)
    statsText:SetTextColor(sc[1] or 1, sc[2] or 1, sc[3] or 1, sc[4] or 1)
    SetShadow(headerText, self.db.shadow ~= false)
    SetShadow(statsText, self.db.shadow ~= false)
    if self.db.showBackground == true then
        frame:SetBackdropColor(bc[1] or 0.025, bc[2] or 0.025, bc[3] or 0.035, Clamp(self.db.backgroundAlpha, 0, 1))
        frame:SetBackdropBorderColor(0.22, 0.78, 0.94, 0.55)
    else
        frame:SetBackdropColor(0, 0, 0, 0)
        frame:SetBackdropBorderColor(0, 0, 0, 0)
    end
    RefreshText()
    frame:SetShown(state.preview or (IsEligible() and AnyMetricShown()))
    ApplyTrainingSettings()
end

local function TrimHistory()
    local history = RAT.db.history
    local limit = math.floor(Clamp(RAT.db.historyLimit, 1, 100))
    local counts = {}
    local index = 1
    while index <= #history do
        local row = history[index]
        local historyType = type(row) == "table" and row.type or nil
        if historyType ~= "combat" and historyType ~= "encounter" and historyType ~= "keystone" then
            historyType = type(row) == "table" and row.label == "Combat" and "combat" or "encounter"
            if type(row) == "table" then row.type = historyType end
        end
        counts[historyType] = (counts[historyType] or 0) + 1
        if counts[historyType] > limit then
            table.remove(history, index)
        else
            index = index + 1
        end
    end
end

local function NotifyHistoryChanged()
    RefreshText()
end

local function NewSegment(historyType, label, metadata)
    local segment = {
        type = historyType,
        label = label,
        attempts = 0,
        successes = 0,
        metrics = NewMetricCounters(),
        startedAt = type(GetTime) == "function" and GetTime() or 0,
        timestamp = type(time) == "function" and time() or 0,
    }
    if type(metadata) == "table" then
        for key, value in pairs(metadata) do segment[key] = value end
    end
    return segment
end

local function ArchiveSegment(segmentKey, result)
    local segment = state[segmentKey]
    if not segment then return end
    state[segmentKey] = nil
    if type(result) == "table" then
        for key, value in pairs(result) do segment[key] = value end
    end
    SyncOwnerTotals(segment)
    if segment.attempts == 0 and RAT.db.historyOnlyWithAttempts ~= false then
        NotifyHistoryChanged()
        return
    end
    table.insert(RAT.db.history, 1, {
        type = segment.type,
        timestamp = segment.timestamp,
        sessionID = state.sessionID,
        label = segment.label or "Combat",
        successes = segment.successes,
        attempts = segment.attempts,
        metrics = CopyMetricCounters(segment.metrics),
        duration = math.max(0, math.floor(((type(GetTime) == "function" and GetTime() or segment.startedAt) - segment.startedAt) + 0.5)),
        encounterID = segment.encounterID,
        difficultyID = segment.difficultyID,
        killed = segment.killed == true,
        mapID = segment.mapID,
        mapName = segment.mapName,
        level = segment.level,
        completed = segment.completed == true,
        onTime = segment.onTime == true,
        upgradeLevels = segment.upgradeLevels,
        abandoned = segment.abandoned == true,
    })
    TrimHistory()
    NotifyHistoryChanged()
end

local function ResetLiveRange()
    state.encounterAttempts = 0
    state.encounterSuccesses = 0
    state.pendingEviscerate = nil
    state.recentPreDanceEviscerate = nil
    state.lastDanceStartedAt = nil
    state.pendingAoeFinisher = nil
    state.encounterMetrics = NewMetricCounters()
    SyncStateTotals()
    RefreshText()
end

local function BeginCombatSegment()
    if state.combatSegment then
        ArchiveSegment("combatSegment", { abandoned = true })
    end
    state.combatSegment = NewSegment("combat", "Combat")
    ResetLiveRange()
end

local function BeginEncounterSegment(encounterID, encounterName, difficultyID)
    if state.encounterSegment then
        ArchiveSegment("encounterSegment", { killed = false, abandoned = true })
    end
    state.encounterSegment = NewSegment("encounter", encounterName or "Encounter", {
        encounterID = encounterID,
        difficultyID = difficultyID,
    })
    ResetLiveRange()
end

local function BeginKeystoneSegment(eventMapID)
    if state.keystoneSegment then
        ArchiveSegment("keystoneSegment", { completed = false, abandoned = true })
    end
    local mapID = eventMapID
    if type(mapID) ~= "number" and C_ChallengeMode
        and type(C_ChallengeMode.GetActiveChallengeMapID) == "function" then
        local ok, value = pcall(C_ChallengeMode.GetActiveChallengeMapID)
        if ok then mapID = value end
    end
    local mapName = "Keystone Dungeon"
    if type(mapID) == "number" and C_ChallengeMode
        and type(C_ChallengeMode.GetMapUIInfo) == "function" then
        local ok, value = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
        if ok and type(value) == "string" then mapName = value end
    end
    local level = 0
    if C_ChallengeMode and type(C_ChallengeMode.GetActiveKeystoneInfo) == "function" then
        local ok, value = pcall(C_ChallengeMode.GetActiveKeystoneInfo)
        if ok and type(value) == "number" then level = value end
    end
    state.keystoneSegment = NewSegment("keystone", mapName, {
        mapID = mapID,
        mapName = mapName,
        level = level,
    })
    NotifyHistoryChanged()
end

local function IncrementSegment(segment, metricKey, succeeded)
    if not segment then return end
    local metrics = EnsureOwnerMetrics(segment)
    local counter = metrics[metricKey]
    if not counter then return end
    counter.attempts = counter.attempts + 1
    if succeeded then counter.successes = counter.successes + 1 end
    SyncOwnerTotals(segment)
end

local function RecordEmpower(metricKey, succeeded)
    if type(metricKey) == "boolean" then
        succeeded = metricKey
        metricKey = METRIC_DARKEST
    end
    if not IsEligible() then return false end
    if not MetricIsTracked(metricKey) then return false end
    if not state.combatSegment then BeginCombatSegment() end
    succeeded = succeeded == true
    local encounterCounter = NormalizeMetricCounters(state.encounterMetrics)[metricKey]
    local sessionCounter = NormalizeMetricCounters(state.sessionMetrics)[metricKey]
    if not encounterCounter or not sessionCounter then return false end
    encounterCounter.attempts = encounterCounter.attempts + 1
    sessionCounter.attempts = sessionCounter.attempts + 1
    if succeeded then
        encounterCounter.successes = encounterCounter.successes + 1
        sessionCounter.successes = sessionCounter.successes + 1
    elseif metricKey == METRIC_DARKEST then
        ShowTrainingFailure()
    end
    SyncStateTotals()
    IncrementSegment(state.combatSegment, metricKey, succeeded)
    IncrementSegment(state.encounterSegment, metricKey, succeeded)
    IncrementSegment(state.keystoneSegment, metricKey, succeeded)
    SaveSessionState()
    RefreshText()
    return true
end

local function PlainCastGUID(castGUID)
    if IsSecret(castGUID) or type(castGUID) ~= "string" then return nil end
    return castGUID
end

local function IsPlayerUnit(unit)
    return not IsSecret(unit) and type(unit) == "string" and unit == "player"
end

local function CaptureEviscerate(castGUID)
    state.pendingEviscerate = nil
    if not MetricIsTracked(METRIC_DARKEST) then return false end
    if RangeTrackingActive() then RunRangeScan() end
    RefreshRoleActivity()
    if not IsEligible()
        or not RoleIsActive(ROLE_DARKEST)
        or not RoleIsActive(ROLE_ANCIENT)
        or not DarkestNightTargetRuleEligible() then return false end
    state.pendingEviscerate = {
        castGUID = PlainCastGUID(castGUID),
        inDance = RoleIsActive(ROLE_DANCE),
    }
    return true
end

local function HasChargedPowerPoint()
    local getter = _G.GetUnitChargedPowerPoints
    if type(getter) ~= "function" then return false end
    local ok, result = pcall(function()
        local indices = getter("player")
        local canAccess = _G.canaccesstable
        if indices == nil or IsSecret(indices) or type(indices) ~= "table"
            or (type(canAccess) == "function" and canAccess(indices) == false) then return false end
        for index = 1, #indices do
            local point = indices[index]
            if not IsSecret(point) and type(point) == "number" and point >= 1 then return true end
        end
        return false
    end)
    return ok and result == true
end

local function AoeMetricForSpell(spellID)
    if IsBlackPowderSpellID(spellID) then return METRIC_BLACK_POWDER end
    if IsSecretTechniqueSpellID(spellID) then return METRIC_SECRET_TECHNIQUE end
end

local function CaptureAoeFinisher(castGUID, spellID)
    state.pendingAoeFinisher = nil
    local metricKey = AoeMetricForSpell(spellID)
    if not metricKey or not MetricIsTracked(metricKey) or not IsEligible() then return false end
    if RangeTrackingActive() then RunRangeScan() end
    if not AoeTargetRuleEligible() then return false end
    if metricKey == METRIC_BLACK_POWDER and not HasChargedPowerPoint() then return false end
    RefreshRoleActivity()
    state.pendingAoeFinisher = {
        metricKey = metricKey,
        castGUID = PlainCastGUID(castGUID),
        empowered = RoleIsActive(ROLE_ANCIENT),
    }
    return true
end

local function PendingCastMatches(pending, castGUID)
    if not pending then return false end
    if pending.castGUID == nil then return true end
    local plainCastGUID = PlainCastGUID(castGUID)
    return plainCastGUID ~= nil and plainCastGUID == pending.castGUID
end

local function OnEviscerateSent(unit, castGUID, spellID)
    if not IsPlayerUnit(unit) or not IsEviscerateSpellID(spellID) then return false end
    return CaptureEviscerate(castGUID)
end

local function OnPlayerSpellcastSent(unit, castGUID, spellID)
    if not IsPlayerUnit(unit) then return false end
    if IsEviscerateSpellID(spellID) then return CaptureEviscerate(castGUID) end
    return CaptureAoeFinisher(castGUID, spellID)
end

local function OnEviscerateSucceeded(unit, castGUID, spellID)
    if not IsPlayerUnit(unit) then return false end
    if not IsEviscerateSpellID(spellID) then
        if IsSecret(spellID) then state.pendingEviscerate = nil end
        return false
    end
    local pending = state.pendingEviscerate
    if not pending then
        CaptureEviscerate(castGUID)
        pending = state.pendingEviscerate
    end
    state.pendingEviscerate = nil
    if not PendingCastMatches(pending, castGUID) then return false end
    RefreshRoleActivity()
    local now = MonotonicNow()
    local danceJustStarted = now ~= nil
        and state.lastDanceStartedAt ~= nil
        and now >= state.lastDanceStartedAt
        and now - state.lastDanceStartedAt <= DANCE_CAST_GRACE
    if pending.inDance == true or RoleIsActive(ROLE_DANCE) or danceJustStarted then
        state.recentPreDanceEviscerate = nil
        return RecordEmpower(METRIC_DARKEST, true)
    end

    -- A normal empowered Eviscerate outside Shadow Dance is valid gameplay and
    -- is not part of this statistic. Keep it only long enough to determine
    -- whether Shadow Dance actually starts immediately afterwards.
    if now ~= nil then
        state.recentPreDanceEviscerate = { usedAt = now }
    end
    return false
end

local function OnAoeFinisherSucceeded(unit, castGUID, spellID)
    if not IsPlayerUnit(unit) then return false end
    local metricKey = AoeMetricForSpell(spellID)
    if not metricKey then
        if IsSecret(spellID) then state.pendingAoeFinisher = nil end
        return false
    end
    local pending = state.pendingAoeFinisher
    state.pendingAoeFinisher = nil
    if not pending or pending.metricKey ~= metricKey
        or not PendingCastMatches(pending, castGUID) then return false end
    return RecordEmpower(metricKey, pending.empowered == true)
end

local function OnEviscerateFailed(unit, castGUID, spellID)
    if not IsPlayerUnit(unit) or not state.pendingEviscerate then return false end
    if IsSecret(spellID) then
        state.pendingEviscerate = nil
        return false
    end
    if IsEviscerateSpellID(spellID)
        and PendingCastMatches(state.pendingEviscerate, castGUID) then
        state.pendingEviscerate = nil
    end
    return false
end

local function OnAoeFinisherFailed(unit, castGUID, spellID)
    if not IsPlayerUnit(unit) or not state.pendingAoeFinisher then return false end
    if IsSecret(spellID) then
        state.pendingAoeFinisher = nil
        return false
    end
    local metricKey = AoeMetricForSpell(spellID)
    if metricKey and state.pendingAoeFinisher.metricKey == metricKey
        and PendingCastMatches(state.pendingAoeFinisher, castGUID) then
        state.pendingAoeFinisher = nil
    end
    return false
end

local function OnPlayerSpellcastFailed(unit, castGUID, spellID)
    OnAoeFinisherFailed(unit, castGUID, spellID)
    return OnEviscerateFailed(unit, castGUID, spellID)
end

local function OnShadowDanceStarted()
    local now = MonotonicNow()
    state.lastDanceStartedAt = now
    local recent = state.recentPreDanceEviscerate
    state.recentPreDanceEviscerate = nil
    if now == nil or type(recent) ~= "table" or type(recent.usedAt) ~= "number" then return false end
    local elapsed = now - recent.usedAt
    if elapsed < 0 or elapsed > DANCE_LEAD_WINDOW then return false end
    return RecordEmpower(METRIC_DARKEST, false)
end

local function OnPlayerSpellcastSucceeded(unit, castGUID, spellID)
    if not IsPlayerUnit(unit) then return false end
    if IsShadowDanceSpellID(spellID) then return OnShadowDanceStarted() end
    if IsBlackPowderSpellID(spellID) or IsSecretTechniqueSpellID(spellID) then
        return OnAoeFinisherSucceeded(unit, castGUID, spellID)
    end
    return OnEviscerateSucceeded(unit, castGUID, spellID)
end

local function OnItemActiveStateChanged(frame)
    local role = roleByFrame[frame]
    if not role then return end
    local wasActive = activeByFrame[frame] == true
    local isActive = SafeActive(frame)
    activeByFrame[frame] = isActive
    if role == ROLE_DANCE and isActive and not wasActive then OnShadowDanceStarted() end
end

function RAT:RefreshDrivers()
    if refreshBusy or not self.db then return end
    refreshBusy = true
    for frame in pairs(roleByFrame) do roleByFrame[frame] = nil end
    for frame in pairs(activeByFrame) do activeByFrame[frame] = nil end

    for viewerIndex = 1, #VIEWER_NAMES do
        local viewer = _G[VIEWER_NAMES[viewerIndex]]
        if viewer and type(viewer.GetItemFrames) == "function" then
            if not hookedViewers[viewer] and type(hooksecurefunc) == "function" and type(viewer.RefreshData) == "function" then
                hookedViewers[viewer] = true
                hooksecurefunc(viewer, "RefreshData", function() RAT:RefreshDrivers() end)
            end
            local ok, frames = pcall(viewer.GetItemFrames, viewer)
            if ok and type(frames) == "table" then
                for index = 1, #frames do
                    local frame = frames[index]
                    local role = ResolveFrameRole(frame)
                    -- Essential cooldown items represent layout/cooldown state, not
                    -- the active Shadow Dance aura. Only buff viewers can own Dance.
                    if role == ROLE_DANCE and viewerIndex == 1 then role = nil end
                    if role then
                        roleByFrame[frame] = role
                        activeByFrame[frame] = SafeActive(frame)
                        if not hookedFrames[frame]
                            and type(hooksecurefunc) == "function"
                            and type(frame.OnActiveStateChanged) == "function" then
                            hookedFrames[frame] = true
                            hooksecurefunc(frame, "OnActiveStateChanged", OnItemActiveStateChanged)
                        end
                    end
                end
            end
        end
    end
    refreshBusy = false
end

local function RefreshRuntime()
    RefreshDeathstalkerKnown()
    ApplyRangeTracking()
    if IsEligible() then RAT:RefreshDrivers() end
    RAT:ApplySettings()
end

function RAT:GetStats()
    SyncStateTotals()
    return state.encounterSuccesses, state.encounterAttempts, state.sessionSuccesses, state.sessionAttempts
end


function RAT:GetMetricStats(metricKey)
    if not MetricIsTracked(metricKey) then return 0, 0, 0, 0 end
    local encounter = NormalizeMetricCounters(state.encounterMetrics)[metricKey]
    local session = NormalizeMetricCounters(state.sessionMetrics)[metricKey]
    if not encounter or not session then return 0, 0, 0, 0 end
    return encounter.successes, encounter.attempts, session.successes, session.attempts
end

function RAT:GetCurrentSnapshot(rangeType)
    if rangeType == "session" then
        local duration = 0
        local epoch = EpochNow()
        if type(epoch) == "number" and type(state.clientStartedAt) == "number" then
            duration = math.max(0, math.floor(epoch - state.clientStartedAt + 0.5))
        end
        local snapshot = {
            type = "session",
            label = "Current Session",
            metrics = CopyMetricCounters(state.sessionMetrics),
            duration = duration,
            current = true,
        }
        SyncOwnerTotals(snapshot)
        return snapshot
    end

    local segment = rangeType == "combat" and state.combatSegment
        or rangeType == "encounter" and state.encounterSegment
        or rangeType == "keystone" and state.keystoneSegment
        or nil
    if not segment then return nil end
    local snapshot = {}
    for key, value in pairs(segment) do snapshot[key] = value end
    snapshot.current = true
    snapshot.duration = math.max(0, math.floor(
        ((type(GetTime) == "function" and GetTime() or segment.startedAt) - segment.startedAt) + 0.5))
    return snapshot
end

function RAT:GetHistory()
    return self.db and self.db.history or {}
end

function RAT:GetHistoryByType(historyType)
    local filtered = {}
    local history = self:GetHistory()
    for index = 1, #history do
        if history[index].type == historyType then filtered[#filtered + 1] = history[index] end
    end
    return filtered
end

function RAT:GetHistoryEntry(historyType, index)
    local entries = self:GetHistoryByType(historyType)
    if index == nil or index == -1 then return entries[1] end
    return entries[index]
end

function RAT:SetPreview(enabled)
    state.preview = enabled == true
    self:ApplySettings()
    return state.preview
end

function RAT:TogglePreview()
    return self:SetPreview(not state.preview)
end

function RAT:IsPreviewActive()
    return state.preview
end

function RAT:PreviewTrainingFailure()
    return ShowTrainingFailure(true)
end

function RAT:IsTrainingAlertActive()
    return state.trainingAlertActive == true
end

function RAT:ResetSession()
    StartNewSession()
    state.pendingEviscerate = nil
    state.pendingAoeFinisher = nil
    state.recentPreDanceEviscerate = nil
    state.lastDanceStartedAt = nil
    RefreshText()
end

function RAT:ClearHistory()
    if self.db then self.db.history = {} end
    NotifyHistoryChanged()
end

function RAT:ResetAppearance()
    if not self.db then return end
    local history = self.db.history
    local sessionState = self.db.sessionState
    local enabled = self.db.enabled
    for key in pairs(self.db) do self.db[key] = nil end
    CopyDefaults(self.db, defaults)
    self.db.history = history or {}
    self.db.sessionState = sessionState or {}
    self.db.enabled = enabled ~= false
    self:ApplySettings()
end

function RAT:NotifySettingsChanged()
    TrimHistory()
    RefreshRuntime()
end

function RAT:PrintHistory()
    local history = RAT:GetHistory()
    print("|cffc79cffRogue Apex Tracker|r — history")
    if #history == 0 then
        print("No recorded encounters yet.")
        return
    end
    for index = 1, math.min(#history, 10) do
        local row = history[index]
        print(string.format("%d. %s — %d/%d (%s), %ds",
            index, row.label or "Combat", row.successes or 0, row.attempts or 0,
            FormatPercent(Percent(row.successes or 0, row.attempts or 0)), row.duration or 0))
    end
end

local function HandleSlash(message)
    local command = string.lower((message or ""):match("^%s*(.-)%s*$"))
    if command == "lock" then
        RAT.db.locked = true
        RAT:ApplySettings()
    elseif command == "unlock" then
        RAT.db.locked = false
        RAT:ApplySettings()
    elseif command == "preview" then
        RAT:TogglePreview()
    elseif command == "reset" then
        RAT:ResetSession()
    elseif command == "clear" then
        RAT:ClearHistory()
    elseif command == "history" then
        if RAT.OpenHistory then RAT:OpenHistory() else RAT:PrintHistory() end
    else
        RAT:OpenOptions()
    end
end

local function InitializeDB()
    local currentDB = _G.RogueApexTrackerDB
    local legacyDB = _G.MidnightRogueApexTrackerDB
    if type(currentDB) ~= "table" then
        currentDB = type(legacyDB) == "table" and legacyDB or {}
        _G.RogueApexTrackerDB = currentDB
    end
    _G.MidnightRogueApexTrackerDB = nil
    RAT.db = currentDB
    CopyDefaults(RAT.db, defaults)
    if RAT.db.fontName == "Friz Quadrata" then
        RAT.db.fontName = defaults.fontName
    end
    local validOutline = RAT.db.outline == ""
        or RAT.db.outline == "OUTLINE"
        or RAT.db.outline == "THICKOUTLINE"
        or RAT.db.outline == "MONOCHROME,OUTLINE"
    if not validOutline then RAT.db.outline = defaults.outline end
    if type(RAT.db.history) ~= "table" then RAT.db.history = {} end
    for index = 1, #METRIC_DEFS do
        local modeKey = METRIC_DEFS[index].modeKey
        local mode = RAT.db[modeKey]
        if mode ~= "show" and mode ~= "history" and mode ~= "off" then
            RAT.db[modeKey] = defaults[modeKey]
        end
    end
    if not VALID_STATS_LAYOUT[RAT.db.statsLayout] then
        RAT.db.statsLayout = defaults.statsLayout
    end
    if not METRIC_ORDER_KEYS[RAT.db.metricOrder] then
        RAT.db.metricOrder = defaults.metricOrder
    end
    for index = 1, #RAT.db.history do
        local row = RAT.db.history[index]
        if type(row) == "table" and row.type ~= "combat"
            and row.type ~= "encounter" and row.type ~= "keystone" then
            row.type = row.label == "Combat" and "combat" or "encounter"
        end
        if type(row) == "table" then
            EnsureOwnerMetrics(row)
            SyncOwnerTotals(row)
        end
    end
    TrimHistory()
    RestoreSessionState()
    EnsureDisplay()
    RefreshRuntime()
    if RAT.BuildOptions then RAT:BuildOptions() end
end

eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
eventFrame:RegisterEvent("SPELLS_CHANGED")
eventFrame:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
eventFrame:RegisterEvent("ENCOUNTER_START")
eventFrame:RegisterEvent("ENCOUNTER_END")
eventFrame:RegisterEvent("CHALLENGE_MODE_START")
eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
eventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    local arg1, arg2, arg3, arg4, arg5 = ...
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            InitializeDB()
            SLASH_ROGUEAPEXTRACKER1 = "/rat"
            SLASH_ROGUEAPEXTRACKER2 = "/rogueapex"
            SlashCmdList.ROGUEAPEXTRACKER = HandleSlash
            SLASH_ROGUEAPEXTRACKERMENU1 = "/ratmenu"
            SlashCmdList.ROGUEAPEXTRACKERMENU = function() RAT:OpenOptions() end
            SLASH_ROGUEAPEXTRACKERHISTORY1 = "/rathistory"
            SlashCmdList.ROGUEAPEXTRACKERHISTORY = function()
                if RAT.OpenHistory then RAT:OpenHistory() else RAT:PrintHistory() end
            end
        elseif arg1 == "Blizzard_CooldownViewer" and RAT.db then
            C_Timer.After(0, function() RAT:RefreshDrivers() end)
        end
    elseif not RAT.db then
        return
    elseif event == "UNIT_SPELLCAST_SENT" then
        OnPlayerSpellcastSent(arg1, arg3, arg4)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnPlayerSpellcastSucceeded(arg1, arg2, arg3)
    elseif event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_FAILED_QUIET"
        or event == "UNIT_SPELLCAST_INTERRUPTED" then
        OnPlayerSpellcastFailed(arg1, arg2, arg3)
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not state.keystoneSegment and C_ChallengeMode
            and type(C_ChallengeMode.GetActiveChallengeMapID) == "function" then
            local ok, mapID = pcall(C_ChallengeMode.GetActiveChallengeMapID)
            if ok and type(mapID) == "number" then BeginKeystoneSegment(mapID) end
        end
        C_Timer.After(0, RefreshRuntime)
    elseif event == "PLAYER_LOGIN" then
        RefreshRuntime()
    elseif event == "PLAYER_REGEN_DISABLED" then
        BeginCombatSegment()
    elseif event == "ENCOUNTER_START" then
        BeginEncounterSegment(arg1, type(arg2) == "string" and arg2 or "Encounter", arg3)
    elseif event == "ENCOUNTER_END" then
        if state.encounterSegment and state.encounterSegment.encounterID == arg1 then
            ArchiveSegment("encounterSegment", { killed = arg5 == 1 })
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        state.pendingEviscerate = nil
        state.pendingAoeFinisher = nil
        state.recentPreDanceEviscerate = nil
        state.lastDanceStartedAt = nil
        ArchiveSegment("combatSegment")
    elseif event == "CHALLENGE_MODE_START" then
        BeginKeystoneSegment(arg1)
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        local result = { completed = true }
        if C_ChallengeMode and type(C_ChallengeMode.GetChallengeCompletionInfo) == "function" then
            local ok, info = pcall(C_ChallengeMode.GetChallengeCompletionInfo)
            if ok and type(info) == "table" then
                result.onTime = info.onTime == true
                result.upgradeLevels = info.keystoneUpgradeLevels
                if type(info.level) == "number" and state.keystoneSegment then
                    state.keystoneSegment.level = info.level
                end
            end
        end
        ArchiveSegment("keystoneSegment", result)
    elseif event == "PLAYER_LEAVING_WORLD" then
        if state.keystoneSegment then
            ArchiveSegment("keystoneSegment", { completed = false, abandoned = true })
        end
    elseif event == "PLAYER_LOGOUT" then
        SaveSessionState()
        state.pendingAoeFinisher = nil
        ApplyRangeTracking(true)
        ArchiveSegment("encounterSegment", { killed = false, abandoned = true })
        ArchiveSegment("combatSegment", { abandoned = true })
        ArchiveSegment("keystoneSegment", { completed = false, abandoned = true })
    else
        C_Timer.After(0, RefreshRuntime)
    end
end)

function RAT_AddonCompartment_OnClick()
    RAT:OpenOptions()
end

function RAT_AddonCompartment_OnEnter(frame)
    GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
    GameTooltip:AddLine("Rogue Apex Tracker", 0.79, 0.62, 1)
    GameTooltip:AddLine("Click to open options.", 1, 1, 1)
    GameTooltip:Show()
end

function RAT_AddonCompartment_OnLeave()
    GameTooltip:Hide()
end

RAT._Test = {
    State = state,
    RecordEmpower = RecordEmpower,
    CaptureEviscerate = CaptureEviscerate,
    OnEviscerateSent = OnEviscerateSent,
    OnEviscerateSucceeded = OnEviscerateSucceeded,
    OnEviscerateFailed = OnEviscerateFailed,
    CaptureAoeFinisher = CaptureAoeFinisher,
    OnAoeFinisherSucceeded = OnAoeFinisherSucceeded,
    OnPlayerSpellcastSent = OnPlayerSpellcastSent,
    OnPlayerSpellcastFailed = OnPlayerSpellcastFailed,
    OnShadowDanceStarted = OnShadowDanceStarted,
    OnPlayerSpellcastSucceeded = OnPlayerSpellcastSucceeded,
    BeginCombatSegment = BeginCombatSegment,
    BeginEncounterSegment = BeginEncounterSegment,
    BeginKeystoneSegment = BeginKeystoneSegment,
    ArchiveSegment = ArchiveSegment,
    RoleIsActive = RoleIsActive,
    RoleByFrame = roleByFrame,
    ActiveByFrame = activeByFrame,
    DarkestNightTargetRuleEligible = DarkestNightTargetRuleEligible,
    AoeTargetRuleEligible = AoeTargetRuleEligible,
    HasChargedPowerPoint = HasChargedPowerPoint,
    ShowTrainingFailure = ShowTrainingFailure,
    RestoreSessionState = RestoreSessionState,
    SaveSessionState = SaveSessionState,
    ClientStartedAt = ClientStartedAt,
    ApplyRangeTracking = ApplyRangeTracking,
    RunRangeScan = RunRangeScan,
    RangeUnits = rangeUnits,
}
