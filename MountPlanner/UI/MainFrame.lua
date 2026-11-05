-- Minimal main window for Foundation v0.1: account-wide collection totals.
-- Native frames only; palette from the UX spec (doc 02, section 10).
local _, ns = ...
local L = ns.L

local UI = {}
ns.UI = UI

local COLORS = {
    background = { 0.106, 0.094, 0.157, 0.96 }, -- #1B1828
    surface    = { 0.188, 0.165, 0.251, 1 },    -- #302A40
    accent     = { 0.659, 0.541, 0.843, 1 },    -- #A88AD7
    success    = { 0.553, 0.827, 0.659, 1 },    -- #8DD3A8
    muted      = { 0.70, 0.68, 0.76, 1 },
}
local WHITE = "Interface\\Buttons\\WHITE8x8"
local MAX_SOURCE_ROWS = 8
local WIDTH, HEIGHT = 380, 380

local function fs(parent, template, r, g, b)
    local f = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    if r then f:SetTextColor(r, g, b) end
    f:SetJustifyH("LEFT")
    return f
end

local function fmt(n)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

function UI:Create()
    if self.frame then return self.frame end

    local f = CreateFrame("Frame", "MountPlannerMainFrame", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(unpack(COLORS.background))
    f:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
    f:Hide()

    -- Dragging + saved position
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        ns.Storage.db.ui.point = { point, relPoint, x, y }
    end)
    self:RestorePosition(f)
    tinsert(UISpecialFrames, f:GetName()) -- close with ESC

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    local title = fs(f, "GameFontNormalLarge", unpack(COLORS.accent))
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText(L["TITLE"])

    local subtitle = fs(f, "GameFontHighlightSmall", unpack(COLORS.muted))
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetText(L["COLLECTION_PROGRESS"])

    local big = fs(f, "GameFontHighlightHuge")
    big:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -10)
    f.big = big

    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetPoint("TOPLEFT", big, "BOTTOMLEFT", 0, -8)
    bar:SetSize(WIDTH - 32, 10)
    bar:SetStatusBarTexture(WHITE)
    bar:SetStatusBarColor(unpack(COLORS.accent))
    bar:SetMinMaxValues(0, 1)
    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    barBg:SetColorTexture(unpack(COLORS.surface))
    f.bar = bar

    local visible = fs(f, "GameFontHighlight")
    visible:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -12)
    f.visible = visible

    local hidden = fs(f, "GameFontHighlightSmall", unpack(COLORS.muted))
    hidden:SetPoint("TOPLEFT", visible, "BOTTOMLEFT", 0, -4)
    hidden:SetWidth(WIDTH - 32)
    f.hidden = hidden

    local sourcesHeader = fs(f, "GameFontNormal", unpack(COLORS.accent))
    sourcesHeader:SetPoint("TOPLEFT", hidden, "BOTTOMLEFT", 0, -14)
    sourcesHeader:SetText(L["MISSING_BY_SOURCE"])

    f.rows = {}
    local anchor = sourcesHeader
    for i = 1, MAX_SOURCE_ROWS do
        local label = fs(f, "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, i == 1 and -6 or -3)
        local value = fs(f, "GameFontHighlightSmall", unpack(COLORS.success))
        value:SetPoint("RIGHT", f, "RIGHT", -16, 0)
        value:SetPoint("TOP", label, "TOP")
        value:SetJustifyH("RIGHT")
        f.rows[i] = { label = label, value = value }
        anchor = label
    end

    local refresh = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    refresh:SetSize(100, 22)
    refresh:SetPoint("BOTTOMRIGHT", -14, 12)
    refresh:SetText(L["REFRESH"])
    refresh:SetScript("OnClick", function()
        ns.Collection:Scan()
        UI:Refresh()
    end)

    local footer = fs(f, "GameFontDisableSmall")
    footer:SetPoint("BOTTOMLEFT", 16, 30)
    footer:SetWidth(WIDTH - 140)
    footer:SetText(L["NOTE_TOTALS"])

    local dataset = fs(f, "GameFontDisableSmall")
    dataset:SetPoint("BOTTOMLEFT", 16, 14)
    dataset:SetText(L["DATASET_NONE"])

    f:SetScript("OnShow", function() UI:Refresh() end)

    self.frame = f
    return f
end

function UI:RestorePosition(f)
    f:ClearAllPoints()
    local p = ns.Storage.db.ui.point
    if p then
        f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        f:SetPoint("CENTER")
    end
end

function UI:ResetPosition()
    ns.Storage.db.ui.point = nil
    if self.frame then self:RestorePosition(self.frame) end
    ns:Print(L["RESET_POS"])
end

function UI:Refresh()
    local f = self.frame
    if not f or not f:IsShown() then return end
    local s = ns.Collection.summary or ns.Collection:Scan()

    if not s or s.total == 0 then
        f.big:SetText("—")
        f.bar:SetValue(0)
        f.visible:SetText(L["JOURNAL_NOT_READY"])
        f.hidden:SetText("")
        for _, row in ipairs(f.rows) do row.label:SetText(""); row.value:SetText("") end
        return
    end

    local pct = s.collected / s.total
    f.big:SetFormattedText("%s / %s  |cffa88ad7(%.1f%%)|r", fmt(s.collected), fmt(s.total), pct * 100)
    f.bar:SetValue(pct)
    f.visible:SetFormattedText("%s: %s", L["MISSING_FOR_CHAR"], fmt(s.missingVisible))
    f.hidden:SetFormattedText("%s: %s", L["HIDDEN_FOR_CHAR"], fmt(s.missingHidden))

    local sources = ns.Collection:GetMissingBySourceSorted()
    for i, row in ipairs(f.rows) do
        local src = sources[i]
        row.label:SetText(src and src.label or "")
        row.value:SetText(src and fmt(src.count) or "")
    end
end

function UI:Toggle()
    local f = self:Create()
    f:SetShown(not f:IsShown())
end
