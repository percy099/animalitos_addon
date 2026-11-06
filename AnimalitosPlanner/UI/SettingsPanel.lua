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

-- Toggle switch with its label; clicking the label also toggles.
local function check(parent, x, y, labelKey, onClick)
    local cb = ns.UI.Switch(parent, onClick)
    cb:SetPoint("TOPLEFT", x + 4, y - 4)
    cb.label = ns.UI.fs(parent, "GameFontHighlight")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 8, 0)
    cb.label:SetText(L[labelKey])
    return cb
end

local function setLabel(cb, text)
    cb.label:SetText(text)
    cb:SetHitRectInsets(0, -(cb.label:GetStringWidth() + 8), -4, -4)
end

local function setCheckEnabled(cb, enabled)
    cb:SetEnabled(enabled)
    local c = enabled and { 1, 1, 1 } or ns.UI.COLORS.muted
    cb.label:SetTextColor(c[1], c[2], c[3], c[4] or 1)
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
    setLabel(p.minimap, L["SET_MINIMAP_SHOW"])
    p.minimapNote = note(mm, -56, "")
    top = top - 76 - GAP

    -- Window: scale slider and reset position
    local win = box(p, "SET_WINDOW", top, 70)
    local reset = smallButton(win, L["SET_RESET_POS"], function() ns.UI:ResetPosition() end)
    reset:SetPoint("TOPRIGHT", -10, -9)
    local scaleLabel = ns.UI.fs(win, "GameFontHighlight")
    scaleLabel:SetPoint("TOPLEFT", 12, -40)
    scaleLabel:SetText(L["SET_SCALE"])
    p.scaleValue = ns.UI.fs(win, "GameFontHighlight", ns.UI.COLORS.accent)
    p.scaleValue:SetPoint("TOPRIGHT", -12, -40)
    p.scaleValue:SetWidth(44)
    p.scaleValue:SetJustifyH("RIGHT")
    p.scale = ns.UI.Slider(win, ns.UI.SCALE_MIN, ns.UI.SCALE_MAX, 0.05, 220)
    p.scale:SetPoint("RIGHT", p.scaleValue, "LEFT", -10, 0)
    -- Live percentage while dragging; the window rescales on release so
    -- the slider does not move under the cursor.
    p.scale:SetScript("OnValueChanged", function(_, v)
        p.scaleValue:SetText(("%d%%"):format(v * 100 + 0.5))
    end)
    p.scale:SetScript("OnMouseUp", function(self) ns.UI:SetScale(self:GetValue()) end)

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
    setLabel(p.native, L["SET_NAV_NATIVE"])
    setLabel(p.tomtom, ns.Navigation:IsTomTomAvailable() and L["SET_NAV_TOMTOM"] or L["SET_NAV_TOMTOM_MISSING"])
    p.scale:SetValue(ns.UI:GetScale())

    local maxTier = ns.Storage.db.settings.maxTier or 10
    p.tierName:SetText(ns.FarmList:TierName(maxTier))
    p.tierPrev:SetEnabled(maxTier > 1)
    p.tierNext:SetEnabled(maxTier < ns.FarmList:NumTiers())

    local available = ns.MinimapButton.available
    setCheckEnabled(p.minimap, available)
    p.minimap:SetChecked(available and ns.MinimapButton:IsShown())
    p.minimapNote:SetText(available and L["SET_MINIMAP_NOTE"] or L["SET_MINIMAP_MISSING"])
end
