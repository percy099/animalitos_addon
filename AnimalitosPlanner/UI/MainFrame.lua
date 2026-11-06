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
local HEADER_H = 40 -- one compact line; there is no footer
local SIDEBAR_W = 160
local NAV_BUTTON_H = 32
UI.CONTENT_WIDTH = WIDTH - SIDEBAR_W - PAD * 3

-- Sidebar sections, in display order. Icons are our own flat glyphs
-- (pipeline/gen_ui_textures.py): house, horseshoe, open book, gear.
local MEDIA = "Interface\\AddOns\\AnimalitosPlanner\\Media\\"
local SECTIONS = {
    { key = "home",       label = "NAV_HOME",       icon = MEDIA .. "nav-home" },
    { key = "farm",       label = "NAV_FARM",       icon = MEDIA .. "nav-farm" },
    { key = "collection", label = "NAV_COLLECTION", icon = MEDIA .. "nav-collection" },
    { key = "settings",   label = "NAV_SETTINGS",   icon = MEDIA .. "nav-settings" },
}
local DEFAULT_SECTION = "farm"

-- Text/icon alpha per nav state (selected / hover / normal).
local NAV_ALPHA = { selected = 1, hover = 0.86, normal = 0.62 }


-- ---------------------------------------------------------------------------
-- Sidebar
-- ---------------------------------------------------------------------------
local function paintNav(b)
    local alpha = b.isSelected and NAV_ALPHA.selected or (b.isHover and NAV_ALPHA.hover) or NAV_ALPHA.normal
    b.label:SetTextColor(1, 1, 1, alpha)
    -- Monochrome icons: white glyphs, accent when selected.
    local c = b.isSelected and COLORS.accent or COLORS.text
    b.icon:SetVertexColor(c[1], c[2], c[3], alpha)
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
    b.icon:SetSize(16, 16)
    b.icon:SetPoint("LEFT", 13, 0)
    b.icon:SetTexture(section.icon) -- white glyph, tinted in paintNav

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
    f:SetScale(self:GetScale())
    self:RestorePosition(f)
    tinsert(UISpecialFrames, f:GetName()) -- close with ESC

    -- Header (one line): logo, title › section ... character, refresh, close
    local band = UI.RoundedTexture(f, "BACKGROUND", 1)
    band:ClearAllPoints()
    band:SetPoint("TOPLEFT", UI.px(1), -UI.px(1))
    band:SetPoint("TOPRIGHT", -UI.px(1), -UI.px(1))
    band:SetHeight(HEADER_H - 1)
    band:SetVertexColor(0, 0, 0, 0.28)

    local close = UI.CloseButton(f)
    close:SetPoint("RIGHT", f, "TOPRIGHT", -8, -HEADER_H / 2)

    local refresh = CreateFrame("Button", nil, f)
    refresh:SetSize(22, 22)
    refresh:SetPoint("RIGHT", close, "LEFT", -4, 0)
    local glyph = refresh:CreateTexture(nil, "ARTWORK")
    glyph:SetSize(14, 14)
    glyph:SetPoint("CENTER")
    glyph:SetTexture(MEDIA .. "nav-refresh")
    glyph:SetVertexColor(1, 1, 1, 0.55)
    refresh:SetScript("OnEnter", function(self)
        glyph:SetVertexColor(1, 1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["REFRESH"], 1, 1, 1)
        GameTooltip:Show()
    end)
    refresh:SetScript("OnLeave", function()
        glyph:SetVertexColor(1, 1, 1, 0.55)
        GameTooltip:Hide()
    end)
    refresh:SetScript("OnClick", function()
        ns.Collection:Scan()
        ns.Lockouts:Request()
        UI:Refresh()
    end)

    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(26, 26)
    logo:SetPoint("LEFT", f, "TOPLEFT", PAD + 2, -HEADER_H / 2)
    logo:SetTexture("Interface\\AddOns\\AnimalitosPlanner\\Media\\icon")

    local title = fs(f, "large")
    title:SetPoint("LEFT", logo, "RIGHT", 9, 0)
    title:SetText(L["TITLE"])

    f.crumb = fs(f, "body", COLORS.dim)
    f.crumb:SetPoint("LEFT", title, "RIGHT", 8, -1)

    f.character = fs(f, "small", COLORS.dim)
    f.character:SetPoint("RIGHT", refresh, "LEFT", -10, 0)
    f.character:SetJustifyH("RIGHT")

    UI.GlowLine(f, -HEADER_H)

    -- Sidebar
    local sidebar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", PAD, -(HEADER_H + PAD))
    sidebar:SetPoint("BOTTOMLEFT", PAD, PAD)
    sidebar:SetWidth(SIDEBAR_W)
    UI.StylePanel(sidebar, { 0, 0, 0, 0.25 })

    -- Content area
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", PAD, 0)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)

    f.panels = {
        farm = ns.FarmPanel:Create(content),
        home = ns.HomePanel:Create(content),
        collection = ns.CollectionPanel:Create(content),
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
    for _, s in ipairs(SECTIONS) do
        if s.key == tab then f.crumb:SetText("›  " .. L[s.label]) end
    end
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

-- Window scale (Settings). The mount preview is a child, so it follows.
UI.SCALE_MIN, UI.SCALE_MAX = 0.8, 1.3

function UI:GetScale()
    local s = tonumber(ns.Storage.db.ui.scale) or 1
    return math.max(UI.SCALE_MIN, math.min(UI.SCALE_MAX, s))
end

function UI:SetScale(s)
    s = math.floor(s * 20 + 0.5) / 20
    ns.Storage.db.ui.scale = (s ~= 1) and s or nil
    if self.frame then self.frame:SetScale(self:GetScale()) end
end

function UI:ResetPosition()
    ns.Storage.db.ui.point = nil
    if self.frame then self:RestorePosition(self.frame) end
    ns:Print(L["RESET_POS"])
end

function UI:Refresh()
    local f = self.frame
    if not f or not f:IsShown() then return end
    local _, classFile = UnitClass("player")
    local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    local name = UnitName("player") or ""
    if cc and cc.colorStr then name = ("|c%s%s|r"):format(cc.colorStr, name) end
    f.character:SetText(("%s  %s"):format(name, UnitLevel("player") or ""))
    local entries = ns.FarmList:Build()
    local sum = ns.FarmList:Summarize(entries)
    f.nav.farm.badge:SetText(sum.ready > 0 and tostring(sum.ready) or "")
    if f.farm:IsShown() then ns.FarmPanel:Refresh(f.farm, entries, sum) end
    if f.summary:IsShown() then ns.HomePanel:Refresh(f.summary, entries, sum) end
    if f.panels.settings:IsShown() then ns.SettingsPanel:Refresh(f.panels.settings) end
    if f.panels.collection:IsShown() then ns.CollectionPanel:Refresh(f.panels.collection, entries) end
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
