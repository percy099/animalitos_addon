-- Visual system shared by every panel: palette, fonts, crisp 1px panels,
-- buttons, close button, section titles, circles and number badges.
-- Text hierarchy uses white with alpha (selected 1.0, hover ~0.86, normal
-- ~0.62, muted ~0.45). Every texture and font comes from the game client.
local _, ns = ...

local UI = {}
ns.UI = UI

local WHITE = "Interface\\Buttons\\WHITE8x8"
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- white disc on transparent

UI.COLORS = {
    background = { 0.086, 0.075, 0.125, 0.97 }, -- window
    surface    = { 0.141, 0.122, 0.200, 1 },    -- panels, cards
    border     = { 1, 1, 1, 0.09 },
    accent     = { 0.659, 0.541, 0.843, 1 },    -- #A88AD7
    success    = { 0.553, 0.827, 0.659, 1 },    -- #8DD3A8
    warning    = { 0.878, 0.627, 0.251, 1 },    -- amber, Locked out
    text       = { 1, 1, 1, 1 },
    dim        = { 1, 1, 1, 0.62 },
    muted      = { 1, 1, 1, 0.45 },
    tipMuted   = { 0.70, 0.68, 0.76, 1 },       -- tooltips ignore alpha
}
local COLORS = UI.COLORS

-- Fonts: Friz Quadrata (WoW's classic font) for titles and numbers,
-- Arial Narrow for body text. Both ship with the client.
local TITLE_FONT = "Fonts\\FRIZQT__.TTF"
local BODY_FONT = "Fonts\\ARIALN.TTF"

local function makeFont(name, path, size)
    local f = CreateFont(name)
    f:SetFont(path, size, "")
    f:SetShadowOffset(1, -1)
    f:SetShadowColor(0, 0, 0, 0.75)
    f:SetTextColor(1, 1, 1, 1)
    return f
end

UI.FONTS = {
    body  = makeFont("AnimalitosFontBody", BODY_FONT, 14),
    small = makeFont("AnimalitosFontSmall", BODY_FONT, 12.5),
    tiny  = makeFont("AnimalitosFontTiny", BODY_FONT, 11.5),
    caps  = makeFont("AnimalitosFontCaps", BODY_FONT, 12),
    title = makeFont("AnimalitosFontTitle", TITLE_FONT, 12),
    large = makeFont("AnimalitosFontLarge", TITLE_FONT, 16),
    huge  = makeFont("AnimalitosFontHuge", TITLE_FONT, 24),
}

-- Template names used across the panels, mapped to our fonts.
local TEMPLATE_FONT = {
    GameFontHighlight      = "body",
    GameFontHighlightSmall = "small",
    GameFontNormalSmall    = "small",
    GameFontDisableSmall   = "tiny",
    GameFontNormal         = "title",
    GameFontNormalLarge    = "large",
    GameFontHighlightLarge = "large",
    GameFontHighlightHuge  = "huge",
}

--- Font string with our fonts. `template` is a legacy template name or a UI.FONTS key.
function UI.fs(parent, template, color)
    template = template or "GameFontHighlight"
    local f = parent:CreateFontString(nil, "OVERLAY")
    f:SetFontObject(UI.FONTS[TEMPLATE_FONT[template] or template] or UI.FONTS.body)
    local c = color or (template == "GameFontDisableSmall" and COLORS.muted) or COLORS.text
    f:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    f:SetJustifyH("LEFT")
    return f
end
local fs = UI.fs

--- Size in UI units that renders as exactly n physical pixels.
function UI.px(n)
    n = n or 1
    if PixelUtil and PixelUtil.GetNearestPixelSize then
        return PixelUtil.GetNearestPixelSize(n, UIParent:GetEffectiveScale(), n)
    end
    return n
end
local px = UI.px

-- Rounded corners: our own textures (pipeline/gen_ui_textures.py), 9-sliced
-- so corners keep their shape at any size. Falls back to square 1px
-- backdrops if the client lacks texture slicing.
local MEDIA = "Interface\\AddOns\\AnimalitosPlanner\\Media\\"
local ROUND_FILL, ROUND_EDGE, ROUND_MASK = MEDIA .. "round-fill", MEDIA .. "round-edge", MEDIA .. "round-mask"
local ROUND_MARGIN = 8 -- texture pixels kept unstretched at each corner

local roundedOK
local function canRound()
    if roundedOK == nil then
        local probe = UIParent:CreateTexture()
        roundedOK = probe.SetTextureSliceMargins ~= nil and Enum.UITextureSliceMode ~= nil
        probe:Hide()
    end
    return roundedOK
end

local function sliced(frame, layer, sublevel, file)
    local t = frame:CreateTexture(nil, layer, nil, sublevel)
    t:SetTexture(file)
    t:SetTextureSliceMargins(ROUND_MARGIN, ROUND_MARGIN, ROUND_MARGIN, ROUND_MARGIN)
    t:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
    t:SetAllPoints()
    return t
end

--- A white fill texture with rounded corners (square if unsupported); tint with SetVertexColor.
function UI.RoundedTexture(frame, layer, sublevel)
    if canRound() then return sliced(frame, layer, sublevel or 0, ROUND_FILL) end
    local t = frame:CreateTexture(nil, layer, nil, sublevel or 0)
    t:SetTexture(WHITE)
    t:SetAllPoints()
    return t
end

--- Recolors a panel styled with StylePanel (works for rounded and square).
function UI.SetPanelColors(frame, fill, border)
    if frame.apFill then
        frame.apFill:SetVertexColor(fill[1], fill[2], fill[3], fill[4] or 1)
        frame.apEdge:SetVertexColor(border[1], border[2], border[3], border[4] or 1)
    else
        frame:SetBackdropColor(fill[1], fill[2], fill[3], fill[4] or 1)
        frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
    end
end

--- Panel look: rounded fill and 1px border, plus a faint top-lit sheen on square panels.
--- opts.border = color, opts.noSheen = true (when something must match the flat fill),
--- opts.square = true (keep square corners).
function UI.StylePanel(frame, fill, opts)
    opts = opts or {}
    local c = fill or COLORS.surface
    local b = opts.border or COLORS.border
    if not opts.square and canRound() then
        if not frame.apFill then
            frame.apFill = sliced(frame, "BACKGROUND", -8, ROUND_FILL)
            frame.apEdge = sliced(frame, "BORDER", -8, ROUND_EDGE)
        end
        UI.SetPanelColors(frame, c, b)
        return
    end
    local e = px(1)
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = e })
    UI.SetPanelColors(frame, c, b)
    if not opts.noSheen and not frame.sheen then
        local s = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
        s:SetPoint("TOPLEFT", e, -e)
        s:SetPoint("BOTTOMRIGHT", -e, e)
        s:SetColorTexture(1, 1, 1, 1)
        s:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.045))
        frame.sheen = s
    end
end

--- Horizontal accent line that fades out to the right, with a soft haze below.
function UI.GlowLine(parent, y)
    local a = COLORS.accent
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 0, y)
    line:SetPoint("TOPRIGHT", 0, y)
    line:SetHeight(px(1))
    line:SetColorTexture(1, 1, 1, 1)
    line:SetGradient("HORIZONTAL", CreateColor(a[1], a[2], a[3], 0.95), CreateColor(a[1], a[2], a[3], 0.05))
    local haze = parent:CreateTexture(nil, "BACKGROUND", nil, 2)
    haze:SetPoint("TOPLEFT", line, "BOTTOMLEFT")
    haze:SetPoint("TOPRIGHT", line, "BOTTOMRIGHT")
    haze:SetHeight(14)
    haze:SetColorTexture(1, 1, 1, 1)
    haze:SetGradient("VERTICAL", CreateColor(a[1], a[2], a[3], 0), CreateColor(a[1], a[2], a[3], 0.10))
    return line
end

--- Flat button. kind = "primary" (accent fill) or "secondary" (outline).
--- Supports SetText / GetFontString / SetEnabled like UIPanelButtonTemplate.
function UI.Button(parent, kind)
    local primary = kind == "primary"
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetHeight(22)
    local label = b:CreateFontString(nil, "OVERLAY")
    label:SetFontObject(UI.FONTS.small)
    label:SetPoint("CENTER")
    b:SetFontString(label)
    b:SetPushedTextOffset(0, -1)
    UI.StylePanel(b, nil, { noSheen = true })

    local a = COLORS.accent
    local function paint(hover)
        if primary then
            UI.SetPanelColors(b, { a[1], a[2], a[3], hover and 0.42 or 0.26 }, { a[1], a[2], a[3], hover and 1 or 0.75 })
            label:SetTextColor(1, 1, 1, 1)
        else
            UI.SetPanelColors(b, { 1, 1, 1, hover and 0.09 or 0.035 }, { 1, 1, 1, hover and 0.32 or 0.14 })
            label:SetTextColor(1, 1, 1, hover and 1 or 0.82)
        end
    end
    paint(false)
    b:SetScript("OnEnter", function(self) if self:IsEnabled() then paint(true) end end)
    b:SetScript("OnLeave", function() paint(false) end)
    b:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
    b:SetScript("OnDisable", function(self)
        self:SetAlpha(0.4)
        paint(false)
    end)
    return b
end

--- Sets the text and sizes the button to fit it.
function UI.SetButtonText(b, text, minWidth)
    b:SetText(text)
    b:SetWidth(math.max(minWidth or 0, b:GetFontString():GetStringWidth() + 24))
end

--- Thin "X" close button that hides `target` (default: parent).
function UI.CloseButton(parent, target)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(22, 22)
    local lines = {}
    for i = 1, 2 do
        local l = b:CreateLine(nil, "ARTWORK")
        l:SetThickness(1.5)
        l:SetColorTexture(1, 1, 1, 1)
        lines[i] = l
    end
    lines[1]:SetStartPoint("TOPLEFT", 6, -6)
    lines[1]:SetEndPoint("BOTTOMRIGHT", -6, 6)
    lines[2]:SetStartPoint("TOPRIGHT", -6, -6)
    lines[2]:SetEndPoint("BOTTOMLEFT", 6, 6)
    local function tint(alpha)
        for _, l in ipairs(lines) do l:SetVertexColor(1, 1, 1, alpha) end
    end
    tint(0.55)
    b:SetScript("OnEnter", function() tint(1) end)
    b:SetScript("OnLeave", function() tint(0.55) end)
    b:SetScript("OnClick", function() (target or parent):Hide() end)
    return b
end

-- Uppercase that also handles Spanish accented letters (string.upper is ASCII-only).
local UPPER = { ["á"] = "Á", ["é"] = "É", ["í"] = "Í", ["ó"] = "Ó", ["ú"] = "Ú", ["ñ"] = "Ñ", ["ü"] = "Ü" }
function UI.Upper(s)
    return (s:gsub("\195[\128-\191]", UPPER):upper())
end

--- "2 mounts · 1 instance" with singular/plural handled.
function UI.CountsText(mounts, instances)
    local L = ns.L
    local m = mounts == 1 and L["MOUNT_ONE"] or L["MOUNTS_N"]:format(mounts)
    local i = instances == 1 and L["INSTANCE_ONE"] or L["INSTANCES_N"]:format(instances)
    return m .. " · " .. i
end

--- Small uppercase, dimmed section label ("START HERE", "NAVIGATION").
function UI.SectionTitle(parent, text)
    local f = fs(parent, "caps", COLORS.dim)
    f:SetText(UI.Upper(text or ""))
    return f
end

-- Instance artwork from the Encounter Journal (EJ_GetInstanceInfo buttonImage1).
-- The picture fills the top-left 174x95 of a 256x128 texture.
local ART_U, ART_V, ART_ASPECT = 174 / 256, 95 / 128, 174 / 95

--- Crops instance artwork so it fills a w*h area without stretching (centered).
function UI.SetArtCrop(tex, w, h)
    if not (w and h) or w <= 0 or h <= 0 then return end
    local a = w / h
    if a >= ART_ASPECT then
        local v = ART_V * ART_ASPECT / a
        local top = (ART_V - v) / 2
        tex:SetTexCoord(0, ART_U, top, top + v)
    else
        local u = ART_U * a / ART_ASPECT
        local left = (ART_U - u) / 2
        tex:SetTexCoord(left, left + u, 0, ART_V)
    end
end

--- Texture for instance artwork with rounded corners (mask).
function UI.ArtTexture(parent, layer, sublevel)
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel or 0)
    local m = parent:CreateMaskTexture()
    m:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints(t)
    t:AddMaskTexture(m)
    return t
end

--- Filled circle tinted with `color` (rings, discs, status dots).
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
    local a = COLORS.accent
    local disc = UI.Circle(b, "ARTWORK", size, { a[1], a[2], a[3], 0.9 })
    disc:SetPoint("CENTER")
    b.text = fs(b, "small")
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetJustifyH("CENTER")
    return b
end
