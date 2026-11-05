-- Main window: header, two tabs (Farmable now / Summary) and footer.
-- Native frames only; palette from the UX spec (docs/02-ux-ui.md §8).
local _, ns = ...
local L = ns.L

local UI = {}
ns.UI = UI

UI.COLORS = {
    background = { 0.106, 0.094, 0.157, 0.96 }, -- #1B1828
    surface    = { 0.188, 0.165, 0.251, 1 },    -- #302A40
    accent     = { 0.659, 0.541, 0.843, 1 },    -- #A88AD7
    success    = { 0.553, 0.827, 0.659, 1 },    -- #8DD3A8
    warning    = { 0.878, 0.627, 0.251, 1 },    -- amber, Locked out
    muted      = { 0.70, 0.68, 0.76, 1 },
}
local COLORS = UI.COLORS
local WHITE = "Interface\\Buttons\\WHITE8x8"
local MAX_SOURCE_ROWS = 8
UI.WIDTH, UI.HEIGHT = 460, 500
local WIDTH, HEIGHT = UI.WIDTH, UI.HEIGHT

function UI.fs(parent, template, color)
    local f = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    if color then f:SetTextColor(color[1], color[2], color[3]) end
    f:SetJustifyH("LEFT")
    return f
end
local fs = UI.fs

local function fmt(n)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

-- ---------------------------------------------------------------------------
-- Summary tab (collection progress)
-- ---------------------------------------------------------------------------
local function createSummary(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()

    local subtitle = fs(p, "GameFontHighlightSmall", COLORS.muted)
    subtitle:SetPoint("TOPLEFT", 4, -4)
    subtitle:SetText(L["COLLECTION_PROGRESS"])

    p.big = fs(p, "GameFontHighlightHuge")
    p.big:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -8)

    local bar = CreateFrame("StatusBar", nil, p)
    bar:SetPoint("TOPLEFT", p.big, "BOTTOMLEFT", 0, -8)
    bar:SetPoint("RIGHT", p, "RIGHT", -4, 0)
    bar:SetHeight(10)
    bar:SetStatusBarTexture(WHITE)
    bar:SetStatusBarColor(unpack(COLORS.accent))
    bar:SetMinMaxValues(0, 1)
    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    barBg:SetColorTexture(unpack(COLORS.surface))
    p.bar = bar

    p.visible = fs(p, "GameFontHighlight")
    p.visible:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -12)

    p.hidden = fs(p, "GameFontHighlightSmall", COLORS.muted)
    p.hidden:SetPoint("TOPLEFT", p.visible, "BOTTOMLEFT", 0, -4)
    p.hidden:SetPoint("RIGHT", p, "RIGHT", -4, 0)

    local sourcesHeader = fs(p, "GameFontNormal", COLORS.accent)
    sourcesHeader:SetPoint("TOPLEFT", p.hidden, "BOTTOMLEFT", 0, -14)
    sourcesHeader:SetText(L["MISSING_BY_SOURCE"])

    p.rows = {}
    local anchor = sourcesHeader
    for i = 1, MAX_SOURCE_ROWS do
        local label = fs(p, "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, i == 1 and -6 or -3)
        local value = fs(p, "GameFontHighlightSmall", COLORS.success)
        value:SetPoint("RIGHT", p, "RIGHT", -4, 0)
        value:SetPoint("TOP", label, "TOP")
        value:SetJustifyH("RIGHT")
        p.rows[i] = { label = label, value = value }
        anchor = label
    end

    local note = fs(p, "GameFontDisableSmall")
    note:SetPoint("BOTTOMLEFT", 4, 4)
    note:SetPoint("RIGHT", p, "RIGHT", -4, 0)
    note:SetText(L["NOTE_TOTALS"])
    return p
end

local function refreshSummary(p)
    local s = ns.Collection.summary or ns.Collection:Scan()
    if not s or s.total == 0 then
        p.big:SetText("—")
        p.bar:SetValue(0)
        p.visible:SetText(L["JOURNAL_NOT_READY"])
        p.hidden:SetText("")
        for _, row in ipairs(p.rows) do row.label:SetText(""); row.value:SetText("") end
        return
    end
    -- Headline matches Blizzard's Mount Journal (mounts visible for this character).
    local pct = s.visibleTotal > 0 and (s.collectedVisible / s.visibleTotal) or 0
    p.big:SetFormattedText("%s / %s  |cffa88ad7(%.1f%%)|r", fmt(s.collectedVisible), fmt(s.visibleTotal), pct * 100)
    p.bar:SetValue(pct)
    p.visible:SetFormattedText("%s: %s", L["MISSING_FOR_CHAR"], fmt(s.missingVisible))
    p.hidden:SetFormattedText(L["ACCOUNT_LINE"], fmt(s.collected), fmt(s.collectedHidden), fmt(s.missingHidden))
    local sources = ns.Collection:GetMissingBySourceSorted()
    for i, row in ipairs(p.rows) do
        local src = sources[i]
        row.label:SetText(src and src.label or "")
        row.value:SetText(src and fmt(src.count) or "")
    end
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------
local function tabButton(parent, text, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetHeight(22)
    b:SetText(text)
    b:SetWidth(b:GetFontString():GetStringWidth() + 28)
    b:SetScript("OnClick", onClick)
    return b
end

function UI:Create()
    if self.frame then return self.frame end

    local f = CreateFrame("Frame", "AnimalitosPlannerMainFrame", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(unpack(COLORS.background))
    f:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
    f:Hide()

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

    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(40, 40)
    logo:SetPoint("TOPLEFT", 12, -10)
    logo:SetTexture("Interface\\AddOns\\AnimalitosPlanner\\Media\\icon")

    local title = fs(f, "GameFontNormalLarge", COLORS.accent)
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 8, -4)
    title:SetText(L["TITLE"])

    f.character = fs(f, "GameFontHighlightSmall", COLORS.muted)
    f.character:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

    -- Tabs
    f.tabFarm = tabButton(f, L["TAB_FARM"], function() UI:SelectTab("farm") end)
    f.tabFarm:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -8)
    f.tabSummary = tabButton(f, L["TAB_SUMMARY"], function() UI:SelectTab("summary") end)
    f.tabSummary:SetPoint("LEFT", f.tabFarm, "RIGHT", 4, 0)

    -- Content area
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", f.tabFarm, "BOTTOMLEFT", 0, -8)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 40)
    f.summary = createSummary(content)
    f.farm = ns.FarmPanel:Create(content)

    -- Footer
    local refresh = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    refresh:SetSize(100, 22)
    refresh:SetPoint("BOTTOMRIGHT", -12, 10)
    refresh:SetText(L["REFRESH"])
    refresh:SetScript("OnClick", function()
        ns.Collection:Scan()
        ns.Lockouts:Request()
        UI:Refresh()
    end)

    local dataset = fs(f, "GameFontDisableSmall")
    dataset:SetPoint("BOTTOMLEFT", 14, 16)
    if ns.Data and ns.Data.sources then
        dataset:SetFormattedText(L["DATASET_LOADED"], #ns.Data.sources, ns.Data.version.client)
    else
        dataset:SetText(L["DATASET_NONE"])
    end

    f:SetScript("OnShow", function() UI:Refresh() end)
    self.frame = f
    self:SelectTab(ns.Storage.db.ui.tab or "farm")
    return f
end

function UI:SelectTab(tab)
    local f = self.frame
    ns.Storage.db.ui.tab = tab
    f.summary:SetShown(tab == "summary")
    f.farm:SetShown(tab == "farm")
    -- Selected tab stays enabled and highlighted (a disabled look read as "inactive").
    for button, name in pairs({ [f.tabFarm] = "farm", [f.tabSummary] = "summary" }) do
        if name == tab then
            button:LockHighlight()
            button:GetFontString():SetTextColor(1, 1, 1)
        else
            button:UnlockHighlight()
            button:GetFontString():SetTextColor(0.7, 0.68, 0.76)
        end
    end
    self:Refresh()
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
    f.character:SetText(UnitName("player") .. " · " .. (UnitLevel("player") or ""))
    local readyCount = ns.FarmPanel:Refresh(f.farm, f.farm:IsShown())
    f.tabFarm:SetText(L["TAB_FARM_COUNT"]:format(readyCount or 0))
    f.tabFarm:SetWidth(f.tabFarm:GetFontString():GetStringWidth() + 28)
    if f.summary:IsShown() then refreshSummary(f.summary) end
end

function UI:Toggle()
    local f = self:Create()
    f:SetShown(not f:IsShown())
end
