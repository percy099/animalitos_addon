-- Main window: header with accent glow line, left sidebar navigation with
-- four sections (Home / Farmable now / Collection / Settings) and footer.
-- Look and widgets come from UI/Style.lua.
local _, ns = ...
local L = ns.L

local UI = ns.UI
local COLORS = UI.COLORS
local fs = UI.fs

-- Layout
UI.WIDTH, UI.HEIGHT = 720, 500
local WIDTH, HEIGHT = UI.WIDTH, UI.HEIGHT
local PAD = 10
local HEADER_H = 56
local FOOTER_H = 38
local SIDEBAR_W = 160
local NAV_BUTTON_H = 32
UI.CONTENT_WIDTH = WIDTH - SIDEBAR_W - PAD * 3

-- Sidebar sections, in display order. Icons are client icon files.
local SECTIONS = {
    { key = "home",       label = "NAV_HOME",       icon = "Interface\\Icons\\INV_Misc_Map_01" },
    { key = "farm",       label = "NAV_FARM",       icon = "Interface\\Icons\\Ability_Mount_RidingHorse" },
    { key = "collection", label = "NAV_COLLECTION", icon = "Interface\\Icons\\INV_Misc_Book_09" },
    { key = "settings",   label = "NAV_SETTINGS",   icon = "Interface\\Icons\\Trade_Engineering" },
}
local DEFAULT_SECTION = "farm"

-- Text/icon alpha per nav state (selected / hover / normal).
local NAV_ALPHA = { selected = 1, hover = 0.86, normal = 0.62 }

-- Placeholder for sections that arrive later.
local function createPlaceholder(parent, text)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()
    local t = fs(p, "GameFontHighlight", COLORS.dim)
    t:SetPoint("CENTER")
    t:SetWidth(UI.CONTENT_WIDTH - 80)
    t:SetJustifyH("CENTER")
    t:SetText(text or L["COMING_SOON"])
    return p
end

-- ---------------------------------------------------------------------------
-- Sidebar
-- ---------------------------------------------------------------------------
local function paintNav(b)
    local alpha = b.isSelected and NAV_ALPHA.selected or (b.isHover and NAV_ALPHA.hover) or NAV_ALPHA.normal
    b.label:SetTextColor(1, 1, 1, alpha)
    b.icon:SetAlpha(alpha)
    b.selected:SetShown(b.isSelected)
    b.bar:SetShown(b.isSelected)
    b.hover:SetShown(b.isHover and not b.isSelected)
end

local function navButton(parent, section)
    local a = COLORS.accent
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(NAV_BUTTON_H)

    b.selected = b:CreateTexture(nil, "BACKGROUND")
    b.selected:SetAllPoints()
    b.selected:SetColorTexture(1, 1, 1, 1)
    b.selected:SetGradient("HORIZONTAL", CreateColor(a[1], a[2], a[3], 0.32), CreateColor(a[1], a[2], a[3], 0.02))
    b.hover = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    b.hover:SetAllPoints()
    b.hover:SetColorTexture(1, 1, 1, 0.04)
    b.bar = b:CreateTexture(nil, "ARTWORK")
    b.bar:SetPoint("TOPLEFT")
    b.bar:SetPoint("BOTTOMLEFT")
    b.bar:SetWidth(UI.px(2))
    b.bar:SetColorTexture(a[1], a[2], a[3], 1)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(18, 18)
    b.icon:SetPoint("LEFT", 12, 0)
    b.icon:SetTexture(section.icon)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- crop the icon border

    b.badge = fs(b, "small", COLORS.success)
    b.badge:SetPoint("RIGHT", -10, 0)
    b.badge:SetJustifyH("RIGHT")

    b.label = fs(b, "body")
    b.label:SetPoint("LEFT", b.icon, "RIGHT", 10, 0)
    b.label:SetPoint("RIGHT", b.badge, "LEFT", -4, 0)
    b.label:SetWordWrap(false)
    b.label:SetText(L[section.label])

    b:SetScript("OnEnter", function(self) self.isHover = true; paintNav(self) end)
    b:SetScript("OnLeave", function(self) self.isHover = false; paintNav(self) end)
    b:SetScript("OnClick", function() UI:SelectTab(section.key) end)
    paintNav(b)
    return b
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------
function UI:Create()
    if self.frame then return self.frame end
    local a = COLORS.accent

    local f = CreateFrame("Frame", "AnimalitosPlannerMainFrame", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    UI.StylePanel(f, COLORS.background, { border = { a[1], a[2], a[3], 0.45 }, noSheen = true })
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

    -- Header: darker band, logo, title, character line, accent glow line
    local band = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    band:SetPoint("TOPLEFT", UI.px(1), -UI.px(1))
    band:SetPoint("TOPRIGHT", -UI.px(1), -UI.px(1))
    band:SetHeight(HEADER_H - 1)
    band:SetColorTexture(0, 0, 0, 0.28)

    local close = UI.CloseButton(f)
    close:SetPoint("TOPRIGHT", -8, -8)

    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(38, 38)
    logo:SetPoint("TOPLEFT", PAD + 2, -9)
    logo:SetTexture("Interface\\AddOns\\AnimalitosPlanner\\Media\\icon")

    local title = fs(f, "large")
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -3)
    title:SetText(L["TITLE"])

    f.character = fs(f, "small", COLORS.dim)
    f.character:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

    UI.GlowLine(f, -HEADER_H)

    -- Sidebar
    local sidebar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", PAD, -(HEADER_H + PAD))
    sidebar:SetPoint("BOTTOMLEFT", PAD, FOOTER_H)
    sidebar:SetWidth(SIDEBAR_W)
    UI.StylePanel(sidebar, { 0, 0, 0, 0.25 })

    -- Content area
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", PAD, 0)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, FOOTER_H)

    f.panels = {
        farm = ns.FarmPanel:Create(content),
        home = ns.HomePanel:Create(content),
        collection = createPlaceholder(content, L["COLLECTION_SOON"]),
        settings = ns.SettingsPanel:Create(content),
    }
    f.farm, f.summary = f.panels.farm, f.panels.home

    f.nav = {}
    local anchorY = -6
    for _, section in ipairs(SECTIONS) do
        local b = navButton(sidebar, section)
        b:SetPoint("TOPLEFT", UI.px(1), anchorY)
        b:SetPoint("TOPRIGHT", -UI.px(1), anchorY)
        anchorY = anchorY - NAV_BUTTON_H - 2
        f.nav[section.key] = b
    end

    -- Footer
    local refresh = UI.Button(f, "secondary")
    UI.SetButtonText(refresh, L["REFRESH"], 96)
    refresh:SetPoint("BOTTOMRIGHT", -PAD, 9)
    refresh:SetScript("OnClick", function()
        ns.Collection:Scan()
        ns.Lockouts:Request()
        UI:Refresh()
    end)

    local dataset = fs(f, "tiny", COLORS.muted)
    dataset:SetPoint("BOTTOMLEFT", PAD + 4, 15)
    if ns.Data and ns.Data.sources then
        dataset:SetFormattedText(L["DATASET_LOADED"], #ns.Data.sources, ns.Data.version.client)
    else
        dataset:SetText(L["DATASET_NONE"])
    end

    f:SetScript("OnShow", function()
        ns.Lockouts:Request() -- fresh lockouts on every open; UPDATE_INSTANCE_INFO refreshes again
        UI:Refresh()
    end)
    self.frame = f
    self:SelectTab(DEFAULT_SECTION)
    return f
end

function UI:SelectTab(tab)
    local f = self.frame
    if tab == "summary" then tab = "home" end -- pre-redesign name
    if not f.panels[tab] then tab = DEFAULT_SECTION end
    ns.Storage.db.ui.tab = tab
    for key, panel in pairs(f.panels) do
        local on = key == tab
        panel:SetShown(on)
        local b = f.nav[key]
        b.isSelected = on
        paintNav(b)
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
    local className = UnitClass("player")
    f.character:SetText(("%s · %s · %s"):format(UnitName("player"), UnitLevel("player") or "", className or ""))
    local entries = ns.FarmList:Build()
    local sum = ns.FarmList:Summarize(entries)
    f.nav.farm.badge:SetText(sum.ready > 0 and tostring(sum.ready) or "")
    if f.farm:IsShown() then ns.FarmPanel:Refresh(f.farm, entries, sum) end
    if f.summary:IsShown() then ns.HomePanel:Refresh(f.summary, entries, sum) end
    if f.panels.settings:IsShown() then ns.SettingsPanel:Refresh(f.panels.settings) end
end

--- Shows the window on a given section (used by the minimap button).
function UI:Open(tab)
    local f = self:Create()
    self:SelectTab(tab or DEFAULT_SECTION)
    if f:IsShown() then
        self:Refresh()
    else
        f:Show()
    end
end

function UI:Toggle()
    local f = self:Create()
    if f:IsShown() then
        f:Hide()
    else
        self:SelectTab(DEFAULT_SECTION) -- every open starts on "Farmable now"
        f:Show()
    end
end
