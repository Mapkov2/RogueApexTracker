local _, RAT = ...

local registered = false
local category
local hasSectionHeader = false
local settingsByVariable = {}
local refreshingSettings = false
local mediaCallbackOwner = {}

local function GetLSM()
    local stub = rawget(_G, "LibStub")
    if type(stub) == "table" and type(stub.GetLibrary) == "function" then
        local ok, library = pcall(stub.GetLibrary, stub, "LibSharedMedia-3.0", true)
        if ok then return library end
    elseif type(stub) == "function" then
        local ok, library = pcall(stub, "LibSharedMedia-3.0", true)
        if ok then return library end
    end
end

local LSM = GetLSM()
local mediaPreview

local function HideMediaPreview()
    if mediaPreview then mediaPreview:Hide() end
end

local function EnsureMediaPreview()
    if mediaPreview then return mediaPreview end
    local frame = CreateFrame("Frame", "RogueApexTrackerMediaPreview", UIParent, "BackdropTemplate")
    frame:SetSize(360, 78)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.025, 0.025, 0.035, 0.97)
    frame:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)

    frame.Title = frame:CreateFontString(nil, "OVERLAY")
    frame.Title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -10)
    frame.Title:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    frame.Title:SetTextColor(1, 0.82, 0.08, 1)

    frame.Sample = frame:CreateFontString(nil, "OVERLAY")
    frame.Sample:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 14)
    frame.Sample:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 14)
    frame.Sample:SetFont("Fonts\\FRIZQT__.TTF", 19, "OUTLINE")
    frame.Sample:SetJustifyH("LEFT")

    frame.Texture = frame:CreateTexture(nil, "ARTWORK")
    frame.Texture:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 13)
    frame.Texture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 13)
    frame.Texture:SetHeight(22)
    frame:Hide()
    mediaPreview = frame
    return frame
end

local function ShowMediaPreview(owner, mediaType, name, path)
    local frame = EnsureMediaPreview()
    frame:ClearAllPoints()
    local ownerIsFrame = owner and type(owner.GetCenter) == "function"
    if ownerIsFrame then
        frame:SetPoint("LEFT", owner, "RIGHT", 12, 0)
    else
        -- Blizzard_Settings passes the option's data table to HighlightRadio's
        -- onEnter callback, not the concrete menu button. Anchor to UIParent in
        -- that path; region APIs on the data table would raise a wrong-type error.
        frame:SetPoint("TOP", UIParent, "TOP", 0, -110)
    end
    frame.Title:SetText(name)
    if mediaType == "font" then
        frame.Texture:Hide()
        frame.Sample:Show()
        if frame.Sample:SetFont(path, 19, "OUTLINE") == false then
            frame.Sample:SetFont("Fonts\\FRIZQT__.TTF", 19, "OUTLINE")
        end
        frame.Sample:SetText("Darkest Night   Aa Bb 123")
    else
        frame.Sample:Hide()
        frame.Texture:Show()
        frame.Texture:SetTexture(path)
    end
    if ownerIsFrame and not owner._ratPreviewLeaveHooked then
        owner._ratPreviewLeaveHooked = true
        owner:HookScript("OnLeave", HideMediaPreview)
    end
    frame:Show()
end

local function Remember(variable, setting)
    settingsByVariable[variable] = setting
    return setting
end

local function SetValueCallback(setting, callback)
    if not setting or type(setting.SetValueChangedCallback) ~= "function" then return end
    setting:SetValueChangedCallback(function(_, value)
        if refreshingSettings then return end
        if callback then callback(value)
        else RAT:NotifySettingsChanged() end
    end)
end

local function AddHeader(layout, text, tooltip)
    if not CreateSettingsListSectionHeaderInitializer then return end
    if hasSectionHeader and Settings and type(Settings.CreateElementInitializer) == "function" then
        layout:AddInitializer(Settings.CreateElementInitializer("RogueApexTrackerSectionHeaderTemplate", {
            name = text,
            tooltip = tooltip,
        }))
    else
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text, tooltip))
    end
    hasSectionHeader = true
end

local function AddCheckbox(categoryObject, variable, key, label, defaultValue, tooltip, callback, parent)
    local setting = Settings.RegisterAddOnSetting(
        categoryObject, variable, key, RAT.db, Settings.VarType.Boolean, label, defaultValue
    )
    Remember(variable, setting)
    SetValueCallback(setting, callback)
    local initializer = Settings.CreateCheckbox(categoryObject, setting, tooltip)
    if parent and initializer.SetParentInitializer then initializer:SetParentInitializer(parent) end
    return setting, initializer
end

local function AddSlider(categoryObject, variable, key, label, defaultValue,
    minimum, maximum, step, tooltip, formatter, callback, parent)
    local setting = Settings.RegisterAddOnSetting(
        categoryObject, variable, key, RAT.db, Settings.VarType.Number, label, defaultValue
    )
    Remember(variable, setting)
    SetValueCallback(setting, callback)
    local options = Settings.CreateSliderOptions(minimum, maximum, step)
    if options.SetLabelFormatter and MinimalSliderWithSteppersMixin
        and MinimalSliderWithSteppersMixin.Label then
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right,
            formatter or function(value)
                return tostring(math.floor(value + 0.5))
            end)
    end
    local initializer = Settings.CreateSlider(categoryObject, setting, options, tooltip)
    if parent and initializer.SetParentInitializer then initializer:SetParentInitializer(parent) end
    return setting, initializer
end

local function AddDropdown(categoryObject, variable, key, label, defaultValue,
    valuesProvider, tooltip, callback, parent, configureInitializer)
    local setting = Settings.RegisterAddOnSetting(
        categoryObject, variable, key, RAT.db, Settings.VarType.String, label, defaultValue
    )
    Remember(variable, setting)
    SetValueCallback(setting, callback)
    local function GetOptions()
        local container = Settings.CreateControlTextContainer()
        local values = valuesProvider()
        for index = 1, #values do
            local row = values[index]
            if type(row) == "table" then
                local option = container:Add(row.value, row.label)
                if option then
                    option.text = row.text
                    option.onEnter = row.onEnter
                end
            else
                container:Add(row, row)
            end
        end
        return container:GetData()
    end
    local initializer = Settings.CreateDropdown(categoryObject, setting, GetOptions, tooltip)
    initializer.getSelectionTextFunc = function()
        local selected = setting:GetValue()
        local values = valuesProvider()
        for index = 1, #values do
            local row = values[index]
            if type(row) == "table" and row.value == selected then
                return row.label
            elseif row == selected then
                return tostring(row)
            end
        end
        return tostring(selected or "")
    end
    if configureInitializer then configureInitializer(initializer, setting) end
    if parent and initializer.SetParentInitializer then initializer:SetParentInitializer(parent) end
    return setting, initializer
end

local function ColorToHex(color)
    color = type(color) == "table" and color or { 1, 1, 1, 1 }
    local function Byte(value)
        value = math.max(0, math.min(1, tonumber(value) or 0))
        return math.floor(value * 255 + 0.5)
    end
    return string.format("FF%02X%02X%02X", Byte(color[1]), Byte(color[2]), Byte(color[3]))
end

local function HexToColor(value, previous)
    local hex = type(value) == "string" and value:gsub("#", "") or "FFFFFFFF"
    if #hex == 6 then hex = "FF" .. hex end
    if #hex ~= 8 then hex = "FFFFFFFF" end
    return {
        (tonumber(hex:sub(3, 4), 16) or 255) / 255,
        (tonumber(hex:sub(5, 6), 16) or 255) / 255,
        (tonumber(hex:sub(7, 8), 16) or 255) / 255,
        type(previous) == "table" and previous[4] or 1,
    }
end

local function AddColor(categoryObject, variable, key, label, defaultValue, tooltip, parent)
    local setting = Settings.RegisterProxySetting(
        categoryObject, variable, Settings.VarType.String, label, ColorToHex(defaultValue),
        function() return ColorToHex(RAT.db[key]) end,
        function(value)
            RAT.db[key] = HexToColor(value, RAT.db[key])
            RAT:NotifySettingsChanged()
        end
    )
    Remember(variable, setting)
    local initializer = Settings.CreateColorSwatch(categoryObject, setting, tooltip)
    if parent and initializer.SetParentInitializer then initializer:SetParentInitializer(parent) end
    return setting, initializer
end

local function AddProxyCheckbox(categoryObject, variable, label, defaultValue,
    getValue, setValue, tooltip, parent)
    local setting = Settings.RegisterProxySetting(
        categoryObject, variable, Settings.VarType.Boolean, label, defaultValue, getValue, setValue
    )
    Remember(variable, setting)
    local initializer = Settings.CreateCheckbox(categoryObject, setting, tooltip)
    if parent and initializer.SetParentInitializer then initializer:SetParentInitializer(parent) end
    return setting, initializer
end

local function AddButton(layout, name, buttonText, callback, tooltip)
    if not CreateSettingsButtonInitializer then return end
    layout:AddInitializer(CreateSettingsButtonInitializer(name, buttonText, callback, tooltip, true))
end

local supportLinks = {
    {
        title = "Patreon",
        url = "https://www.patreon.com/cw/MidnightSimpleUnitframes",
        icon = "Interface\\AddOns\\RogueApexTracker\\Media\\Support\\Patreon.png",
        tooltip = "Show the Patreon support link for copying.",
    },
    {
        title = "PayPal",
        url = "https://www.paypal.com/ncp/payment/H3N2P87S53KBQ",
        icon = "Interface\\AddOns\\RogueApexTracker\\Media\\Support\\PayPal.png",
        tooltip = "Show the PayPal support link for copying.",
    },
    {
        title = "Ko-fi",
        url = "https://ko-fi.com/midnightsimpleunitframes#linkModal",
        icon = "Interface\\AddOns\\RogueApexTracker\\Media\\Support\\Ko-Fi.png",
        tooltip = "Show the Ko-fi support link for copying.",
    },
}

local function AddSupportFooter(layout)
    if not (Settings and type(Settings.CreateElementInitializer) == "function") then return end
    local initializer = Settings.CreateElementInitializer("RogueApexTrackerSupportFooterTemplate", {
        name = "Support development",
        tooltip = "Patreon, PayPal, and Ko-fi support links.",
        links = supportLinks,
    })
    initializer.hideText = true
    layout:AddInitializer(initializer)
end

local copyLinkPopup

local function EnsureCopyLinkPopup()
    if copyLinkPopup then return copyLinkPopup end
    local frame = CreateFrame("Frame", "RogueApexTrackerCopyLinkPopup", UIParent, "BackdropTemplate")
    frame:SetSize(440, 152)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(100)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.02, 0.02, 0.03, 0.96)
    frame:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)

    frame.Title = frame:CreateFontString(nil, "OVERLAY")
    frame.Title:SetPoint("TOP", frame, "TOP", 0, -16)
    frame.Title:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    frame.Title:SetTextColor(1, 0.82, 0.08, 1)

    frame.Hint = frame:CreateFontString(nil, "OVERLAY")
    frame.Hint:SetPoint("TOP", frame.Title, "BOTTOM", 0, -8)
    frame.Hint:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    frame.Hint:SetText("Press Ctrl+C to copy:")
    frame.Hint:SetTextColor(0.9, 0.9, 0.9, 1)

    frame.EditBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.EditBox:SetAutoFocus(false)
    frame.EditBox:SetSize(380, 32)
    frame.EditBox:SetPoint("TOP", frame.Hint, "BOTTOM", 0, -12)
    frame.EditBox:SetScript("OnEscapePressed", function() frame:Hide() end)
    frame.EditBox:SetScript("OnEnterPressed", function() frame:Hide() end)

    frame.Close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.Close:SetSize(120, 24)
    frame.Close:SetPoint("BOTTOM", frame, "BOTTOM", 0, 12)
    frame.Close:SetText(OKAY or "Okay")
    frame.Close:RegisterForClicks("LeftButtonUp")
    frame.Close:SetScript("OnClick", function() frame:Hide() end)

    frame:SetScript("OnHide", function(self)
        self.EditBox:ClearFocus()
    end)
    frame:Hide()
    copyLinkPopup = frame
    return frame
end

local function ShowCopyLink(title, url)
    local frame = EnsureCopyLinkPopup()
    frame.Title:SetText(title or "Support link")
    frame.EditBox:SetText(url or "")
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:Show()
    frame.EditBox:SetFocus()
    frame.EditBox:HighlightText()
end

function RAT:ShowCopyLink(title, url)
    ShowCopyLink(title, url)
end

local function GetMediaNames(mediaType, selected)
    local result, seen = {}, {}
    local values = LSM and type(LSM.List) == "function" and LSM:List(mediaType) or nil
    if type(values) == "table" then
        for index = 1, #values do
            local value = values[index]
            if type(value) == "string" and value ~= "" and not seen[value] then
                seen[value] = true
                result[#result + 1] = value
            end
        end
    end
    if type(selected) == "string" and selected ~= "" and not seen[selected] then
        table.insert(result, 1, selected)
    end
    if #result == 0 then
        result[1] = mediaType == "font" and "Friz Quadrata TT" or "Solid"
    end
    return result
end

local function GetMediaRows(mediaType, selected)
    local names = GetMediaNames(mediaType, selected)
    local rows = {}
    for index = 1, #names do
        local name = names[index]
        local fallback = mediaType == "font" and RAT.DEFAULTS.fontPath
            or RAT.DEFAULTS.backgroundTexturePath
        local path = LSM and type(LSM.Fetch) == "function" and LSM:Fetch(mediaType, name, true) or nil
        path = type(path) == "string" and path ~= "" and path or fallback
        local previewType, previewName, previewPath = mediaType, name, path
        rows[#rows + 1] = {
            value = name,
            label = name,
            text = mediaType == "statusbar"
                and string.format("|T%s:14:86|t  %s", path, name) or name,
            onEnter = function(owner)
                ShowMediaPreview(owner, previewType, previewName, previewPath)
            end,
        }
    end
    return rows
end

local function ConfigureMediaDropdown(initializer, setting)
    initializer.customOptionHandler = function(rootDescription)
        rootDescription:SetScrollMode(300)
    end
    initializer.OnHide = HideMediaPreview
end

local function FetchMedia(mediaType, name, fallback)
    local value = LSM and type(LSM.Fetch) == "function" and LSM:Fetch(mediaType, name, true) or nil
    return type(value) == "string" and value ~= "" and value or fallback
end

local function SyncFontPath()
    RAT.db.fontPath = FetchMedia("font", RAT.db.fontName, RAT.DEFAULTS.fontPath)
end

local function SyncTexturePath()
    RAT.db.backgroundTexturePath = FetchMedia(
        "statusbar", RAT.db.backgroundTextureName, RAT.DEFAULTS.backgroundTexturePath
    )
end

local function RegisterMediaCallbacks()
    if not (LSM and type(LSM.RegisterCallback) == "function") then return end
    pcall(LSM.RegisterCallback, mediaCallbackOwner, "LibSharedMedia_Registered",
        function(_, mediaType, key)
            if mediaType == "font" and RAT.db and RAT.db.fontName == key then
                SyncFontPath()
                RAT:NotifySettingsChanged()
            elseif mediaType == "statusbar" and RAT.db and RAT.db.backgroundTextureName == key then
                SyncTexturePath()
                RAT:NotifySettingsChanged()
            end
        end)
end

local function SetRegisteredValue(variable, value)
    local setting = settingsByVariable[variable]
    if setting and type(setting.SetValue) == "function" then setting:SetValue(value) end
end

function RAT:RefreshOptions()
    refreshingSettings = true
    for _, setting in pairs(settingsByVariable) do
        if setting.IsModified and setting:IsModified() and setting.Revert then
            setting:Revert()
        elseif setting.NotifyUpdate then
            setting:NotifyUpdate()
        end
    end
    refreshingSettings = false
end

function RAT:BuildOptions()
    if registered or not self.db then return end
    if not (Settings and Settings.RegisterVerticalLayoutCategory
        and Settings.RegisterAddOnCategory and Settings.RegisterAddOnSetting
        and Settings.RegisterProxySetting) then
        return
    end
    registered = true

    SyncFontPath()
    SyncTexturePath()
    RegisterMediaCallbacks()

    local defaults = self.DEFAULTS
    local layout
    category, layout = Settings.RegisterVerticalLayoutCategory("Rogue Apex Tracker")
    hasSectionHeader = false

    AddHeader(layout, "Tracker", "Core display controls.")
    local _, enabledInitializer = AddCheckbox(
        category, "RAT_ENABLED", "enabled", "Enable tracker", defaults.enabled,
        "Show the Darkest Night empowerment statistics tracker.")
    AddCheckbox(category, "RAT_LOCKED", "locked", "Lock position", defaults.locked,
        "Disable this to drag the tracker directly in the game world.", nil, enabledInitializer)
    AddCheckbox(category, "RAT_BELOW_FOUR_TARGETS", "onlyCountBelowFourTargets",
        "Count Darkest Night only below 4 targets", defaults.onlyCountBelowFourTargets,
        "Use this addon's own Eviscerate nameplate-range counter. Only 1-3 in-range targets count as a Darkest Night APEX use; unknown snapshots and 4+ targets fail closed.",
        nil, enabledInitializer)

    AddHeader(layout, "Display")
    AddCheckbox(category, "RAT_SHOW_HEADER", "showHeader", "Show header", defaults.showHeader,
        "Show the Darkest Night empowerment title.", nil, enabledInitializer)
    local _, backgroundInitializer = AddCheckbox(
        category, "RAT_SHOW_BACKGROUND", "showBackground", "Show background", defaults.showBackground,
        "Draw a background behind the tracker.", nil, enabledInitializer)
    AddSlider(category, "RAT_SCALE", "scale", "Scale", defaults.scale, 0.5, 2, 0.05,
        "Scale the complete tracker.", function(value) return string.format("%.2f", value) end,
        nil, enabledInitializer)

    AddHeader(layout, "Typography")
    AddDropdown(category, "RAT_FONT", "fontName", "Font", defaults.fontName,
        function() return GetMediaRows("font", RAT.db.fontName) end,
        "LibSharedMedia font used by the tracker.", function()
            SyncFontPath()
            RAT:NotifySettingsChanged()
        end, enabledInitializer, ConfigureMediaDropdown)
    AddDropdown(category, "RAT_OUTLINE", "outline", "Font outline", defaults.outline,
        function()
            return {
                { value = "", label = "None" },
                { value = "OUTLINE", label = "Outline" },
                { value = "THICKOUTLINE", label = "Thick outline" },
                { value = "MONOCHROME,OUTLINE", label = "Monochrome outline" },
            }
        end, "Outline applied to both tracker text lines.", nil, enabledInitializer)
    AddCheckbox(category, "RAT_SHADOW", "shadow", "Font shadow", defaults.shadow,
        "Draw a soft shadow behind the tracker text.", nil, enabledInitializer)
    AddSlider(category, "RAT_HEADER_SIZE", "headerSize", "Header size", defaults.headerSize,
        9, 40, 1, "Header font size.", nil, nil, enabledInitializer)
    AddSlider(category, "RAT_STATS_SIZE", "statsSize", "Statistics size", defaults.statsSize,
        10, 48, 1, "Encounter and session statistics font size.", nil, nil, enabledInitializer)

    AddHeader(layout, "Colors and background")
    AddColor(category, "RAT_HEADER_COLOR", "headerColor", "Header color", defaults.headerColor,
        "Color of the tracker header.", enabledInitializer)
    AddColor(category, "RAT_STATS_COLOR", "statsColor", "Statistics color", defaults.statsColor,
        "Color of encounter and session statistics.", enabledInitializer)
    AddColor(category, "RAT_BACKGROUND_COLOR", "backgroundColor", "Background color", defaults.backgroundColor,
        "Background RGB color.", backgroundInitializer)
    AddDropdown(category, "RAT_BACKGROUND_TEXTURE", "backgroundTextureName", "Background texture",
        defaults.backgroundTextureName,
        function() return GetMediaRows("statusbar", RAT.db.backgroundTextureName) end,
        "LibSharedMedia texture used by the optional background.", function()
            SyncTexturePath()
            RAT:NotifySettingsChanged()
        end, backgroundInitializer, ConfigureMediaDropdown)
    AddSlider(category, "RAT_BACKGROUND_ALPHA", "backgroundAlpha", "Background opacity",
        defaults.backgroundAlpha, 0, 1, 0.05, "Opacity of the optional background.",
        function(value) return string.format("%d%%", math.floor(value * 100 + 0.5)) end,
        nil, backgroundInitializer)

    AddHeader(layout, "Position")
    AddSlider(category, "RAT_OFFSET_X", "offsetX", "Horizontal position", defaults.offsetX,
        -2000, 2000, 1, "Horizontal offset from screen center.", nil, nil, enabledInitializer)
    AddSlider(category, "RAT_OFFSET_Y", "offsetY", "Vertical position", defaults.offsetY,
        -1200, 1200, 1, "Vertical offset from screen center.", nil, nil, enabledInitializer)
    AddButton(layout, "Tracker position", "Reset position", function()
        SetRegisteredValue("RAT_OFFSET_X", defaults.offsetX)
        SetRegisteredValue("RAT_OFFSET_Y", defaults.offsetY)
    end, "Return the tracker to its default screen position.")

    AddHeader(layout, "Live statistics on tracker", "Choose which right-now ranges are shown directly on the movable tracker.")
    AddCheckbox(category, "RAT_SHOW_CURRENT_COMBAT", "showCurrentCombat",
        "Show current combat", defaults.showCurrentCombat,
        "Show the active combat's APEX results. Outside combat this range displays 0/0.",
        nil, enabledInitializer)
    AddCheckbox(category, "RAT_SHOW_CURRENT_ENCOUNTER", "showCurrentEncounter",
        "Show current encounter", defaults.showCurrentEncounter,
        "Show the active boss encounter as its own live range. Hidden while no encounter is active.",
        nil, enabledInitializer)
    AddCheckbox(category, "RAT_SHOW_CURRENT_DUNGEON", "showCurrentDungeon",
        "Show current dungeon", defaults.showCurrentDungeon,
        "Show the complete active keystone dungeon total across all of its combats. Hidden outside an active key.",
        nil, enabledInitializer)
    AddCheckbox(category, "RAT_SHOW_SESSION", "showSession", "Show current session",
        defaults.showSession, "Show the reload-safe current client-session total.", nil, enabledInitializer)

    AddHeader(layout, "History on tracker", "Optionally place the newest archived snapshots below the live statistics.")
    AddCheckbox(category, "RAT_SHOW_LAST_COMBAT", "showLastCombat", "Show last combat",
        defaults.showLastCombat, "Show the latest completed combat snapshot on the tracker.",
        nil, enabledInitializer)
    AddCheckbox(category, "RAT_SHOW_LAST_ENCOUNTER", "showLastEncounter", "Show last encounter",
        defaults.showLastEncounter, "Show the latest completed boss encounter snapshot on the tracker.",
        nil, enabledInitializer)
    AddCheckbox(category, "RAT_SHOW_LAST_DUNGEON", "showLastDungeon", "Show last dungeon",
        defaults.showLastDungeon, "Show the latest completed or exited keystone dungeon snapshot on the tracker.",
        nil, enabledInitializer)

    AddHeader(layout, "Training mode", "Immediate feedback when a confirmed Darkest Night empowerment happens outside Shadow Dance.")
    local _, trainingInitializer = AddCheckbox(
        category, "RAT_TRAINING_MODE", "trainingMode", "Enable training mode", defaults.trainingMode,
        "Show a separate warning immediately when Ancient Arts confirms an APEX Darkest Night use outside the real Shadow Dance buff.",
        nil, enabledInitializer)
    AddCheckbox(category, "RAT_TRAINING_LOCKED", "trainingLocked",
        "Lock training alert position", defaults.trainingLocked,
        "Disable this to keep the training alert visible and drag it independently from the statistics tracker.",
        nil, trainingInitializer)
    AddSlider(category, "RAT_TRAINING_DURATION", "trainingDuration", "Alert duration",
        defaults.trainingDuration, 0.5, 5, 0.1, "How long a failed APEX warning remains visible.",
        function(value) return string.format("%.1fs", value) end, nil, trainingInitializer)
    AddSlider(category, "RAT_TRAINING_SIZE", "trainingSize", "Alert text size",
        defaults.trainingSize, 12, 64, 1, "Font size of the failed APEX warning.",
        nil, nil, trainingInitializer)
    AddSlider(category, "RAT_TRAINING_SCALE", "trainingScale", "Alert scale",
        defaults.trainingScale, 0.5, 2, 0.05, "Scale the separate training alert.",
        function(value) return string.format("%.2f", value) end, nil, trainingInitializer)
    AddColor(category, "RAT_TRAINING_COLOR", "trainingColor", "Alert color",
        defaults.trainingColor, "Color of the failed APEX warning.", trainingInitializer)
    AddSlider(category, "RAT_TRAINING_OFFSET_X", "trainingOffsetX", "Alert horizontal position",
        defaults.trainingOffsetX, -2000, 2000, 1, "Horizontal offset of the separate training alert.",
        nil, nil, trainingInitializer)
    AddSlider(category, "RAT_TRAINING_OFFSET_Y", "trainingOffsetY", "Alert vertical position",
        defaults.trainingOffsetY, -1200, 1200, 1, "Vertical offset of the separate training alert.",
        nil, nil, trainingInitializer)
    AddButton(layout, "Training alert preview", "Show test warning", function()
        RAT:PreviewTrainingFailure()
    end, "Show the separate failed APEX warning for the configured duration.")
    AddButton(layout, "Training alert position", "Reset position", function()
        SetRegisteredValue("RAT_TRAINING_OFFSET_X", defaults.trainingOffsetX)
        SetRegisteredValue("RAT_TRAINING_OFFSET_Y", defaults.trainingOffsetY)
    end, "Return only the training alert to its default screen position.")

    AddHeader(layout, "Statistics storage and browser")
    AddSlider(category, "RAT_DECIMALS", "decimals", "Percentage decimals", defaults.decimals,
        0, 2, 1, "Number of decimal places shown in percentages.", nil, nil, enabledInitializer)
    AddSlider(category, "RAT_HISTORY_LIMIT", "historyLimit", "Stored history entries", defaults.historyLimit,
        1, 100, 1, "Maximum entries retained separately for combats, encounters, and keystones.", nil, nil, enabledInitializer)
    AddCheckbox(category, "RAT_HISTORY_ATTEMPTS", "historyOnlyWithAttempts",
        "Only store fights with APEX uses", defaults.historyOnlyWithAttempts,
        "Ignore fights where no Ancient Arts empowerment was recorded.", nil, enabledInitializer)
    AddButton(layout, "Statistics browser", "Open statistics", function() RAT:OpenHistory() end,
        "Inspect right-now Combat, Encounter, Dungeon, and Session totals plus archived history snapshots.")
    AddButton(layout, "Current session", "Reset statistics", function() RAT:ResetSession() end,
        "Reset encounter and session counters without deleting stored history.")
    AddButton(layout, "Stored history", "Clear history", function() RAT:ClearHistory() end,
        "Delete all stored combat, encounter, and keystone history.")

    AddHeader(layout, "Preview")
    AddProxyCheckbox(category, "RAT_PREVIEW", "Show preview", false,
        function() return RAT:IsPreviewActive() end,
        function(value) RAT:SetPreview(value) end,
        "Show sample live and archived statistics for the selected tracker ranges.", enabledInitializer)

    AddSupportFooter(layout)

    Settings.RegisterAddOnCategory(category)
end

function RAT:OpenOptions()
    if not registered then self:BuildOptions() end
    if category and Settings and type(Settings.OpenToCategory) == "function" then
        Settings.OpenToCategory(category:GetID())
    else
        print("Rogue Apex Tracker: Blizzard Settings is unavailable.")
    end
end
