-- Settings section (docs/02-ux-ui.md §2): navigation mode, expansion filter,
-- minimap button and window position. Native widgets only (no Ace3).
local _, ns = ...
local L = ns.L

local SettingsPanel = {}
ns.SettingsPanel = SettingsPanel

local GAP = 8

local function box(parent, titleKey, top, height)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    ns.UI.StylePanel(f)
    f:SetPoint("TOPLEFT", 0, top)
    f:SetPoint("TOPRIGHT", 0, top)
    f:SetHeight(height)
    local t = ns.UI.SectionTitle(f, L[titleKey])
    t:SetPoint("TOPLEFT", 10, -11)
    return f
end

local function check(parent, x, y, labelKey, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", x, y)
    cb.label = ns.UI.fs(parent, "GameFontHighlight")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    cb.label:SetText(L[labelKey])
    cb:SetScript("OnClick", onClick)
    return cb
end

local function setCheckEnabled(cb, enabled)
    cb:SetEnabled(enabled)
    local c = enabled and { 1, 1, 1 } or ns.UI.COLORS.muted
    cb.label:SetTextColor(c[1], c[2], c[3])
end

local function note(parent, y, text)
    local n = ns.UI.fs(parent, "GameFontHighlightSmall", ns.UI.COLORS.muted)
    n:SetPoint("TOPLEFT", 12, y)
    n:SetPoint("RIGHT", -12, 0)
    n:SetWordWrap(true)
    n:SetText(text or "")
    return n
end

local function smallButton(parent, text, onClick)
    local b = ns.UI.Button(parent, "secondary")
    ns.UI.SetButtonText(b, text, 28)
    b:SetScript("OnClick", onClick)
    return b
end

function SettingsPanel:Create(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()
    local top = 0

    -- Navigation
    local nav = box(p, "SET_NAV", top, 92)
    p.native = check(nav, 10, -30, "SET_NAV_NATIVE", function()
        ns.Navigation:SetMode("native")
        ns.UI:Refresh()
    end)
    p.tomtom = check(nav, 220, -30, "SET_NAV_TOMTOM", function()
        ns.Navigation:SetMode("tomtom")
        ns.UI:Refresh()
    end)
    note(nav, -62, L["SET_NAV_NOTE"])
    top = top - 92 - GAP

    -- Expansion filter
    local tier = box(p, "SET_TIER", top, 84)
    local label = ns.UI.fs(tier, "GameFontHighlight")
    label:SetPoint("TOPLEFT", 12, -36)
    label:SetText(L["SET_TIER_LABEL"])
    local function step(delta)
        local s = ns.Storage.db.settings
        local n = math.max(1, math.min(ns.FarmList:NumTiers(), (s.maxTier or 10) + delta))
        s.maxTier = n
        ns.UI:Refresh()
    end
    p.tierNext = smallButton(tier, ">", function() step(1) end)
    p.tierNext:SetPoint("TOPRIGHT", -10, -32)
    p.tierName = ns.UI.fs(tier, "GameFontHighlight", ns.UI.COLORS.accent)
    p.tierName:SetPoint("RIGHT", p.tierNext, "LEFT", -8, 0)
    p.tierName:SetWidth(170)
    p.tierName:SetJustifyH("CENTER")
    p.tierPrev = smallButton(tier, "<", function() step(-1) end)
    p.tierPrev:SetPoint("RIGHT", p.tierName, "LEFT", -8, 0)
    note(tier, -62, L["SET_TIER_NOTE"])
    top = top - 84 - GAP

    -- Minimap button
    local mm = box(p, "SET_MINIMAP", top, 76)
    p.minimap = check(mm, 10, -30, "SET_MINIMAP_SHOW", function(self)
        ns.MinimapButton:SetShown(self:GetChecked())
    end)
    p.minimapNote = note(mm, -56, "")
    top = top - 76 - GAP

    -- Window
    local win = box(p, "SET_WINDOW", top, 40)
    local reset = smallButton(win, L["SET_RESET_POS"], function() ns.UI:ResetPosition() end)
    reset:SetPoint("TOPRIGHT", -10, -9)

    -- About
    local about = ns.UI.fs(p, "GameFontDisableSmall")
    about:SetPoint("BOTTOMLEFT", 4, 4)
    about:SetText(L["SET_ABOUT"]:format(ns.VERSION))
    return p
end

function SettingsPanel:Refresh(p)
    local mode = ns.Navigation:Mode()
    p.native:SetChecked(mode == "native")
    p.tomtom:SetChecked(mode == "tomtom")
    setCheckEnabled(p.tomtom, ns.Navigation:IsTomTomAvailable())
    p.tomtom.label:SetText(ns.Navigation:IsTomTomAvailable() and L["SET_NAV_TOMTOM"] or L["SET_NAV_TOMTOM_MISSING"])

    local maxTier = ns.Storage.db.settings.maxTier or 10
    p.tierName:SetText(ns.FarmList:TierName(maxTier))
    p.tierPrev:SetEnabled(maxTier > 1)
    p.tierNext:SetEnabled(maxTier < ns.FarmList:NumTiers())

    local available = ns.MinimapButton.available
    setCheckEnabled(p.minimap, available)
    p.minimap:SetChecked(available and ns.MinimapButton:IsShown())
    p.minimapNote:SetText(available and L["SET_MINIMAP_NOTE"] or L["SET_MINIMAP_MISSING"])
end
