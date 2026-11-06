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

--- Soft drop shadow for text placed over artwork.
function UI.Shadow(fontString)
    fontString:SetShadowOffset(1, -1)
    fontString:SetShadowColor(0, 0, 0, 0.9)
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

-- ---------------------------------------------------------------------------
-- Controls: toggle switch, slider, thin scroll bar, search box
-- ---------------------------------------------------------------------------

--- On/off switch. onChange(self, checked) runs on click.
--- API: SetChecked(bool), GetChecked(), SetEnabled(bool).
--- (Not "Toggle": UI:Toggle() is the window open/close used by /aplan.)
function UI.Switch(parent, onChange)
    local t = CreateFrame("Button", nil, parent)
    t:SetSize(30, 16)
    t.track = UI.RoundedTexture(t, "ARTWORK", 0)
    t.knob = UI.Circle(t, "OVERLAY", 12, { 1, 1, 1 })
    t.checked = false
    local function paint(self)
        local a = COLORS.accent
        local on = self:IsEnabled() and 1 or 0.35
        self.knob:ClearAllPoints()
        if self.checked then
            self.track:SetVertexColor(a[1], a[2], a[3], 0.95 * on)
            self.knob:SetPoint("RIGHT", -2, 0)
        else
            self.track:SetVertexColor(1, 1, 1, (self.hover and 0.24 or 0.14) * on)
            self.knob:SetPoint("LEFT", 2, 0)
        end
        self.knob:SetVertexColor(1, 1, 1, on)
    end
    function t:SetChecked(v)
        self.checked = v and true or false
        paint(self)
    end
    function t:GetChecked() return self.checked end
    t:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        if onChange then onChange(self, self.checked) end
    end)
    t:SetScript("OnEnter", function(self) self.hover = true; paint(self) end)
    t:SetScript("OnLeave", function(self) self.hover = false; paint(self) end)
    t:SetScript("OnEnable", paint)
    t:SetScript("OnDisable", paint)
    paint(t)
    return t
end

--- Horizontal slider: thin track, accent fill up to a round knob.
function UI.Slider(parent, minV, maxV, step, width)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(width, 16)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(4)
    track:SetColorTexture(1, 1, 1, 0.14)
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(CIRCLE)
    thumb:SetSize(14, 14)
    s:SetThumbTexture(thumb)
    local a = COLORS.accent
    local fill = s:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT", track)
    fill:SetPoint("RIGHT", thumb, "CENTER")
    fill:SetHeight(4)
    fill:SetColorTexture(a[1], a[2], a[3], 0.9)
    s:SetScript("OnEnter", function() thumb:SetVertexColor(a[1], a[2], a[3], 1) end)
    s:SetScript("OnLeave", function() thumb:SetVertexColor(1, 1, 1, 1) end)
    return s
end

--- Thin scroll bar for a plain ScrollFrame, placed to its right. Also
--- handles the mouse wheel. Hidden when everything fits.
function UI.ThinScrollBar(scroll)
    local bar = CreateFrame("Slider", nil, scroll:GetParent())
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(6)
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, -2)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 2)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(1, 1, 1, 0.05)
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(1, 1, 1, 1)
    thumb:SetSize(6, 40)
    thumb:SetVertexColor(1, 1, 1, 0.25)
    bar:SetThumbTexture(thumb)
    bar:SetMinMaxValues(0, 0)
    bar:SetValue(0)
    bar:Hide()

    bar:SetScript("OnValueChanged", function(_, v) scroll:SetVerticalScroll(v) end)
    bar:SetScript("OnEnter", function() thumb:SetVertexColor(1, 1, 1, 0.45) end)
    bar:SetScript("OnLeave", function() thumb:SetVertexColor(1, 1, 1, 0.25) end)
    scroll:SetScript("OnScrollRangeChanged", function(self, _, range)
        range = range or self:GetVerticalScrollRange()
        bar:SetMinMaxValues(0, range)
        local h = self:GetHeight()
        thumb:SetHeight(math.max(24, h * h / (h + range)))
        if bar:GetValue() > range then bar:SetValue(range) end
        bar:SetShown(range > 0.5)
    end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        bar:SetValue(bar:GetValue() - delta * 40)
    end)
    return bar
end

--- Search field with magnifier, placeholder and clear button.
--- onChange(text) runs on every change; ESC clears, then drops focus.
function UI.SearchBox(parent, placeholder, onChange)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetHeight(24)
    box:SetAutoFocus(false)
    box:SetFontObject(UI.FONTS.small)
    box:SetTextColor(1, 1, 1, 1)
    box:SetTextInsets(24, 22, 0, 0)
    box:SetMaxLetters(40)
    local a = COLORS.accent
    UI.StylePanel(box, { 0, 0, 0, 0.25 }, { noSheen = true })

    local icon = box:CreateTexture(nil, "OVERLAY")
    icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", 6, -1)
    icon:SetVertexColor(1, 1, 1, 0.55)

    local hint = fs(box, "small", COLORS.muted)
    hint:SetPoint("LEFT", 24, 0)
    hint:SetText(placeholder or "")

    local clear = UI.CloseButton(box)
    clear:SetSize(18, 18)
    clear:SetPoint("RIGHT", -3, 0)
    clear:Hide()
    clear:SetScript("OnClick", function()
        box:SetText("")
        box:ClearFocus()
    end)

    local function border(focused)
        UI.SetPanelColors(box, { 0, 0, 0, 0.25 }, focused and { a[1], a[2], a[3], 0.8 } or COLORS.border)
    end
    box:SetScript("OnEditFocusGained", function() border(true) end)
    box:SetScript("OnEditFocusLost", function() border(false) end)
    box:SetScript("OnEnterPressed", box.ClearFocus)
    box:SetScript("OnEscapePressed", function(self)
        if self:GetText() ~= "" then self:SetText("") else self:ClearFocus() end
    end)
    box:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        hint:SetShown(text == "")
        clear:SetShown(text ~= "")
        if onChange then onChange(text) end
    end)
    return box
end

--- Segmented control: one choice among a few. items = { {key=, text=}, ... }.
--- onSelect(key) runs on click. API: seg:SetSelected(key).
function UI.Segmented(parent, items, onSelect)
    local seg = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    seg:SetHeight(24)
    UI.StylePanel(seg, { 0, 0, 0, 0.25 }, { noSheen = true })
    local a = COLORS.accent
    seg.buttons = {}
    local x = 2
    local function paint(b)
        local on = b.key == seg.selected
        b.fill:SetShown(on)
        b.label:SetTextColor(1, 1, 1, on and 1 or (b.hover and 0.86 or 0.62))
    end
    for _, it in ipairs(items) do
        local b = CreateFrame("Button", nil, seg)
        b.key = it.key
        b.fill = UI.RoundedTexture(b, "BACKGROUND", 1)
        b.fill:SetVertexColor(a[1], a[2], a[3], 0.35)
        b.label = fs(b, "small")
        b.label:SetPoint("CENTER")
        b.label:SetText(it.text)
        local w = math.max(56, b.label:GetStringWidth() + 22)
        b:SetSize(w, 20)
        b:SetPoint("LEFT", x, 0)
        x = x + w + 2
        b:SetScript("OnEnter", function(self) self.hover = true; paint(self) end)
        b:SetScript("OnLeave", function(self) self.hover = false; paint(self) end)
        b:SetScript("OnClick", function(self)
            seg:SetSelected(self.key)
            if onSelect then onSelect(self.key) end
        end)
        seg.buttons[#seg.buttons + 1] = b
    end
    seg:SetWidth(x)
    function seg:SetSelected(key)
        self.selected = key
        for _, b in ipairs(self.buttons) do paint(b) end
    end
    return seg
end

--- Dropdown: a secondary button with a chevron that opens a menu below it.
--- dd:SetItems({ {value=, text=}, ... }), dd:SetText(text). onSelect(value)
--- runs when an item is clicked. A click anywhere else closes the menu.
local MENU_ROW_H = 22
function UI.Dropdown(parent, width, onSelect)
    local dd = UI.Button(parent, "secondary")
    dd:SetWidth(width)
    dd:GetFontString():ClearAllPoints()
    dd:GetFontString():SetPoint("LEFT", 10, 0)
    dd:GetFontString():SetPoint("RIGHT", -22, 0)
    dd:GetFontString():SetJustifyH("LEFT")
    dd:GetFontString():SetWordWrap(false)
    -- Chevron drawn with two lines (no font glyph needed)
    for i = 1, 2 do
        local l = dd:CreateLine(nil, "OVERLAY")
        l:SetThickness(1.5)
        l:SetColorTexture(1, 1, 1, 0.7)
        if i == 1 then
            l:SetStartPoint("RIGHT", -15, 2); l:SetEndPoint("RIGHT", -11, -2)
        else
            l:SetStartPoint("RIGHT", -11, -2); l:SetEndPoint("RIGHT", -7, 2)
        end
    end

    -- The menu is parented to UIParent with a fixed strata: as a child of the
    -- window it was re-levelled every time the (toplevel) window was raised
    -- and ended up under its click catcher, so items could not be clicked.
    local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    if menu.SetFixedFrameStrata then menu:SetFixedFrameStrata(true) end
    menu:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -2)
    menu:SetWidth(width)
    local a = COLORS.accent
    UI.StylePanel(menu, { COLORS.background[1], COLORS.background[2], COLORS.background[3], 1 },
        { border = { a[1], a[2], a[3], 0.45 }, noSheen = true })
    menu:EnableMouse(true)
    menu:Hide()

    -- Close on any click outside the menu and the button (event, no OnUpdate).
    menu:SetScript("OnShow", function(self)
        -- Match the window scale (Settings > Window size).
        self:SetScale(dd:GetEffectiveScale() / UIParent:GetEffectiveScale())
        pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN")
    end)
    menu:SetScript("OnHide", function(self) pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
    menu:SetScript("OnEvent", function(self)
        if not self:IsMouseOver() and not dd:IsMouseOver() then self:Hide() end
    end)
    dd:HookScript("OnHide", function() menu:Hide() end)

    menu.rows = {}
    function dd:SetItems(items)
        for i, it in ipairs(items) do
            local r = menu.rows[i]
            if not r then
                r = CreateFrame("Button", nil, menu)
                r:SetHeight(MENU_ROW_H)
                local hl = r:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(a[1], a[2], a[3], 0.25)
                r.label = fs(r, "small")
                r.label:SetPoint("LEFT", 10, 0)
                r.label:SetPoint("RIGHT", -10, 0)
                r.label:SetWordWrap(false)
                r:SetScript("OnClick", function(self)
                    menu:Hide()
                    if onSelect then onSelect(self.value) end
                end)
                menu.rows[i] = r
            end
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 2, -2 - (i - 1) * MENU_ROW_H)
            r:SetPoint("RIGHT", -2, 0)
            r.value = it.value
            r.label:SetText(it.text)
            r:Show()
        end
        for i = #items + 1, #menu.rows do menu.rows[i]:Hide() end
        menu:SetHeight(#items * MENU_ROW_H + 4)
    end
    dd:SetScript("OnClick", function() menu:SetShown(not menu:IsShown()) end)
    dd.menu = menu
    return dd
end

--- Client icon file shown as a monochrome glyph tinted with `color`.
function UI.Glyph(tex, file, color)
    tex:SetTexture(file)
    tex:SetDesaturated(true)
    local c = color or COLORS.text
    tex:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
end
