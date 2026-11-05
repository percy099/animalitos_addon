-- Main window (redesign, part 1): header, left sidebar navigation with four
-- sections (Home / Farmable now / Collection / Settings) and footer.
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
local BORDER = "Interface\\Tooltips\\UI-Tooltip-Border" -- client texture with softly rounded corners

-- Layout
UI.WIDTH, UI.HEIGHT = 720, 500
local WIDTH, HEIGHT = UI.WIDTH, UI.HEIGHT
local PAD = 10
local HEADER_H = 52
local FOOTER_H = 36
local SIDEBAR_W = 160
local NAV_BUTTON_H = 30
UI.CONTENT_WIDTH = WIDTH - SIDEBAR_W - PAD * 3

-- Sidebar sections, in display order. Icons are client icon files.
local SECTIONS = {
    { key = "home",       label = "NAV_HOME",       icon = "Interface\\Icons\\INV_Misc_Map_01" },
    { key = "farm",       label = "NAV_FARM",       icon = "Interface\\Icons\\Ability_Mount_RidingHorse" },
    { key = "collection", label = "NAV_COLLECTION", icon = "Interface\\Icons\\INV_Misc_Book_09" },
    { key = "settings",   label = "NAV_SETTINGS",   icon = "Interface\\Icons\\Trade_Engineering" },
}
local DEFAULT_SECTION = "farm"

function UI.fs(parent, template, color)
    local f = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    if color then f:SetTextColor(color[1], color[2], color[3]) end
    f:SetJustifyH("LEFT")
    return f
end
local fs = UI.fs

--- Applies the panel look: flat fill plus a tinted, softly rounded border.
function UI.StylePanel(frame, fill, edgeSize)
    local e = edgeSize or 12
    frame:SetBackdrop({
        bgFile = WHITE, edgeFile = BORDER, edgeSize = e,
        insets = { left = e / 4, right = e / 4, top = e / 4, bottom = e / 4 },
    })
    local c = fill or COLORS.surface
    frame:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
    frame:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.55)
end

local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- white disc on transparent

--- Filled circle tinted with `color` (used for rings, discs and badges).
function UI.Circle(parent, layer, size, color, sublevel)
    local t = parent:CreateTexture(nil, layer, nil, sublevel or 0)
    t:SetSize(size, size)
    t:SetTexture(CIRCLE)
    t:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    return t
end

--- Small numbered disc (1, 2, 3...). Set the number with badge.text:SetText(n).
function UI.NumberBadge(parent, size)
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(size, size)
    local disc = UI.Circle(b, "ARTWORK", size, COLORS.accent)
    disc:SetPoint("CENTER")
    b.text = fs(b, "GameFontHighlightSmall")
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetJustifyH("CENTER")
    return b
end

-- Placeholder for sections that arrive in later parts.
local function createPlaceholder(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()
    local t = fs(p, "GameFontHighlight", COLORS.muted)
    t:SetPoint("CENTER")
    t:SetJustifyH("CENTER")
    t:SetText(L["COMING_SOON"])
    return p
end

-- ---------------------------------------------------------------------------
-- Sidebar
-- ---------------------------------------------------------------------------
local function navButton(parent, section)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(NAV_BUTTON_H)

    b.selected = b:CreateTexture(nil, "BACKGROUND")
    b.selected:SetAllPoints()
    b.selected:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.22)
    b.bar = b:CreateTexture(nil, "ARTWORK")
    b.bar:SetPoint("TOPLEFT")
    b.bar:SetPoint("BOTTOMLEFT")
    b.bar:SetWidth(3)
    b.bar:SetColorTexture(unpack(COLORS.accent))

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(18, 18)
    b.icon:SetPoint("LEFT", 10, 0)
    b.icon:SetTexture(section.icon)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- crop the icon border

    b.badge = fs(b, "GameFontHighlightSmall", COLORS.success)
    b.badge:SetPoint("RIGHT", -8, 0)
    b.badge:SetJustifyH("RIGHT")

    b.label = fs(b, "GameFontHighlight")
    b.label:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
    b.label:SetPoint("RIGHT", b.badge, "LEFT", -4, 0)
    b.label:SetWordWrap(false)
    b.label:SetText(L[section.label])

    b:SetScript("OnClick", function() UI:SelectTab(section.key) end)
    return b
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------
function UI:Create()
    if self.frame then return self.frame end

    local f = CreateFrame("Frame", "AnimalitosPlannerMainFrame", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    UI.StylePanel(f, COLORS.background, 16)
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

    -- Header
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(36, 36)
    logo:SetPoint("TOPLEFT", PAD + 2, -PAD)
    logo:SetTexture("Interface\\AddOns\\AnimalitosPlanner\\Media\\icon")

    local title = fs(f, "GameFontNormalLarge", COLORS.accent)
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 8, -3)
    title:SetText(L["TITLE"])

    f.character = fs(f, "GameFontHighlightSmall", COLORS.muted)
    f.character:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)

    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", PAD, -HEADER_H)
    divider:SetPoint("TOPRIGHT", -PAD, -HEADER_H)
    divider:SetHeight(1)
    divider:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.35)

    -- Sidebar
    local sidebar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", PAD, -(HEADER_H + PAD))
    sidebar:SetPoint("BOTTOMLEFT", PAD, FOOTER_H)
    sidebar:SetWidth(SIDEBAR_W)
    UI.StylePanel(sidebar, { COLORS.surface[1], COLORS.surface[2], COLORS.surface[3], 0.6 })

    -- Content area
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", PAD, 0)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, FOOTER_H)

    f.panels = {
        farm = ns.FarmPanel:Create(content),
        home = ns.HomePanel:Create(content),
        collection = createPlaceholder(content),
        settings = createPlaceholder(content),
    }
    f.farm, f.summary = f.panels.farm, f.panels.home

    f.nav = {}
    local anchorY = -6
    for _, section in ipairs(SECTIONS) do
        local b = navButton(sidebar, section)
        b:SetPoint("TOPLEFT", 4, anchorY)
        b:SetPoint("TOPRIGHT", -4, anchorY)
        anchorY = anchorY - NAV_BUTTON_H - 2
        f.nav[section.key] = b
    end

    -- Footer
    local refresh = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    refresh:SetSize(100, 22)
    refresh:SetPoint("BOTTOMRIGHT", -PAD, 8)
    refresh:SetText(L["REFRESH"])
    refresh:SetScript("OnClick", function()
        ns.Collection:Scan()
        ns.Lockouts:Request()
        UI:Refresh()
    end)

    local dataset = fs(f, "GameFontDisableSmall")
    dataset:SetPoint("BOTTOMLEFT", PAD + 4, 14)
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
        b.selected:SetShown(on)
        b.bar:SetShown(on)
        local c = on and { 1, 1, 1 } or COLORS.muted
        b.label:SetTextColor(c[1], c[2], c[3])
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
