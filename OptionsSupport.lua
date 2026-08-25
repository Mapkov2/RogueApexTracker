local _, RAT = ...

local LINK_WIDTH = 150
local LINK_HEIGHT = 26
local LINK_GAP = 12
local LINK_START_X = 37

local function SetLinkColor(button, highlighted)
    if not button or not button.Label then return end
    if highlighted then
        button.Label:SetTextColor(1, 0.82, 0.08, 1)
        button.Icon:SetAlpha(1)
    else
        button.Label:SetTextColor(0.72, 0.72, 0.75, 1)
        button.Icon:SetAlpha(0.78)
    end
end

local function CreateSupportButton(parent, index)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(LINK_WIDTH, LINK_HEIGHT)
    button:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT",
        LINK_START_X + ((index - 1) * (LINK_WIDTH + LINK_GAP)), 5)
    button:RegisterForClicks("LeftButtonUp")

    button.Icon = button:CreateTexture(nil, "ARTWORK")
    button.Icon:SetSize(18, 18)
    button.Icon:SetPoint("LEFT", button, "LEFT", 0, 0)

    button.Label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.Label:SetPoint("LEFT", button.Icon, "RIGHT", 7, 0)
    button.Label:SetPoint("RIGHT", button, "RIGHT", -2, 0)
    button.Label:SetJustifyH("LEFT")

    button:SetScript("OnEnter", function(self)
        SetLinkColor(self, true)
        if self.link and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(self.link.title, 1, 0.82, 0.08)
            GameTooltip:AddLine("Click to show the copyable support link.", 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function(self)
        SetLinkColor(self, false)
        if GameTooltip then GameTooltip:Hide() end
    end)
    button:SetScript("OnClick", function(self)
        if self.link and RAT and RAT.ShowCopyLink then
            RAT:ShowCopyLink(self.link.title, self.link.url)
        end
    end)
    SetLinkColor(button, false)
    return button
end

RogueApexTrackerSupportFooterMixin = CreateFromMixins(SettingsListElementMixin)

function RogueApexTrackerSupportFooterMixin:OnLoad()
    SettingsListElementMixin.OnLoad(self)
    self:SetHeight(64)

    self.Divider = self:CreateTexture(nil, "ARTWORK")
    self.Divider:SetColorTexture(1, 1, 1, 0.08)
    self.Divider:SetHeight(1)
    self.Divider:SetPoint("TOPLEFT", self, "TOPLEFT", 37, -5)
    self.Divider:SetPoint("TOPRIGHT", self, "TOPRIGHT", -20, -5)

    self.Caption = self:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.Caption:SetPoint("TOPLEFT", self, "TOPLEFT", 37, -16)
    self.Caption:SetText("Support development")
    self.Caption:SetTextColor(0.46, 0.46, 0.5, 1)

    self.Links = {}
    for index = 1, 3 do self.Links[index] = CreateSupportButton(self, index) end
end

function RogueApexTrackerSupportFooterMixin:Init(initializer)
    SettingsListElementMixin.Init(self, initializer)
    self.Text:Hide()
    self.Tooltip:Hide()
    self.NewFeature:Hide()
    local links = self.data and self.data.links or {}
    for index = 1, #self.Links do
        local button = self.Links[index]
        local link = links[index]
        button.link = link
        button:SetShown(link ~= nil)
        if link then
            button.Icon:SetTexture(link.icon)
            button.Label:SetText(link.title)
            SetLinkColor(button, false)
        end
    end
    self:EvaluateState()
end

function RogueApexTrackerSupportFooterMixin:Release()
    for index = 1, #self.Links do self.Links[index].link = nil end
    SettingsListElementMixin.Release(self)
end
