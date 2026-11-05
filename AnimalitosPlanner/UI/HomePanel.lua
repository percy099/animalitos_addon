-- Home section (docs/02-ux-ui.md §3): greeting, collection ring, state
-- tiles, "Start here" (first instances of the farm list) and upcoming resets.
local _, ns = ...
local L = ns.L

local HomePanel = {}
ns.HomePanel = HomePanel

local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local GAP = 8
local HEADER_H = 52
local TILE_H = 112
local RING_TILE_W = 128
local RING_SIZE = 92
local RING_THICKNESS = 10
local RESETS_W = 200
local START_ROWS = 4
local START_ROW_H = 38
local RING_DURATION = 1000 -- the swipe is paused; only the ratio matters
local WEEKDAYS = { "SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY" }

local function fmt(n)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

local function panel(parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    ns.UI.StylePanel(f)
    return f
end

local function withTooltip(owner, fill)
    owner:EnableMouse(true)
    owner:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        fill(GameTooltip)
        GameTooltip:Show()
    end)
    owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Greeting --------------------------------------------------------------------
local function createGreeting(p)
    local C = ns.UI.COLORS
    local head = CreateFrame("Frame", nil, p)
    head:SetPoint("TOPLEFT")
    head:SetPoint("TOPRIGHT")
    head:SetHeight(HEADER_H)

    local grad = head:CreateTexture(nil, "BACKGROUND")
    grad:SetAllPoints()
    grad:SetColorTexture(1, 1, 1, 1)
    grad:SetGradient("HORIZONTAL",
        CreateColor(C.accent[1], C.accent[2], C.accent[3], 0.30),
        CreateColor(C.accent[1], C.accent[2], C.accent[3], 0))

    local ring = ns.UI.Circle(head, "ARTWORK", 46, C.accent)
    ring:SetPoint("LEFT", 6, 0)
    p.portrait = head:CreateTexture(nil, "ARTWORK", nil, 1)
    p.portrait:SetSize(42, 42)
    p.portrait:SetPoint("CENTER", ring)
    local mask = head:CreateMaskTexture()
    mask:SetAllPoints(p.portrait)
    mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    p.portrait:AddMaskTexture(mask)

    p.greeting = ns.UI.fs(head, "GameFontHighlightLarge")
    p.greeting:SetPoint("TOPLEFT", ring, "TOPRIGHT", 10, -6)
    local sub = ns.UI.fs(head, "GameFontHighlightSmall", C.muted)
    sub:SetPoint("TOPLEFT", p.greeting, "BOTTOMLEFT", 0, -3)
    sub:SetText(L["HOME_SUBTITLE"])
end

-- Collection ring -------------------------------------------------------------
-- A paused Cooldown swipe draws the filled arc; a disc on top makes it a ring.
local function setRing(cd, pct)
    pct = math.max(0, math.min(1, pct or 0))
    if cd.Resume then cd:Resume() end
    if pct <= 0 then
        cd:Clear()
        return
    end
    if pct >= 1 then pct = 0.9999 end
    cd:SetCooldown(GetTime() - RING_DURATION * (1 - pct), RING_DURATION)
    if cd.Pause then cd:Pause() end
end

local function createRingTile(p, top)
    local C = ns.UI.COLORS
    local t = panel(p)
    t:SetPoint("TOPLEFT", 0, top)
    t:SetSize(RING_TILE_W, TILE_H)

    local ring = CreateFrame("Frame", nil, t)
    ring:SetSize(RING_SIZE, RING_SIZE)
    ring:SetPoint("CENTER")
    local track = ns.UI.Circle(ring, "BACKGROUND", RING_SIZE, { C.accent[1], C.accent[2], C.accent[3], 0.18 })
    track:SetPoint("CENTER")

    local cd = CreateFrame("Cooldown", nil, ring, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetSwipeTexture(CIRCLE)
    cd:SetSwipeColor(C.accent[1], C.accent[2], C.accent[3], 1)
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:SetHideCountdownNumbers(true)
    p.ringCooldown = cd

    local cover = CreateFrame("Frame", nil, ring)
    cover:SetAllPoints()
    cover:SetFrameLevel(cd:GetFrameLevel() + 2)
    local hole = ns.UI.Circle(cover, "ARTWORK", RING_SIZE - RING_THICKNESS * 2, C.surface)
    hole:SetPoint("CENTER")

    p.ringPct = ns.UI.fs(cover, "GameFontHighlightLarge")
    p.ringPct:SetPoint("CENTER", 0, 6)
    p.ringPct:SetJustifyH("CENTER")
    p.ringValue = ns.UI.fs(cover, "GameFontHighlightSmall", C.muted)
    p.ringValue:SetPoint("TOP", p.ringPct, "BOTTOM", 0, -2)
    p.ringValue:SetJustifyH("CENTER")

    withTooltip(t, function(tt)
        tt:AddLine(L["COLLECTION_PROGRESS"], 1, 1, 1)
        tt:AddLine(L["NOTE_TOTALS"], C.muted[1], C.muted[2], C.muted[3], true)
        local s = ns.Collection.summary
        if s then
            tt:AddLine(L["ACCOUNT_LINE"]:format(fmt(s.collected), fmt(s.collectedHidden), fmt(s.missingHidden)),
                C.muted[1], C.muted[2], C.muted[3], true)
        end
    end)
end

-- State tiles -----------------------------------------------------------------
local STATS = {
    { key = "missing", label = "STAT_MISSING", color = { 1, 1, 1 } },
    { key = "ready",   label = "STAT_READY",   color = "success", opensFarm = true },
    { key = "locked",  label = "STAT_LOCKED",  color = "warning", opensFarm = true },
    { key = "verify",  label = "STAT_VERIFY",  color = "muted",   opensFarm = true },
}

local function createStatTiles(p, top)
    local C = ns.UI.COLORS
    local w = (ns.UI.CONTENT_WIDTH - RING_TILE_W - GAP * #STATS) / #STATS
    p.stats = {}
    for i, stat in ipairs(STATS) do
        local t = panel(p)
        t:SetSize(w, TILE_H)
        t:SetPoint("TOPLEFT", RING_TILE_W + GAP + (i - 1) * (w + GAP), top)
        local color = type(stat.color) == "string" and C[stat.color] or stat.color
        t.value = ns.UI.fs(t, "GameFontHighlightHuge", color)
        t.value:SetPoint("CENTER", 0, 12)
        t.value:SetJustifyH("CENTER")
        t.label = ns.UI.fs(t, "GameFontHighlightSmall", C.muted)
        t.label:SetPoint("TOP", t.value, "BOTTOM", 0, -6)
        t.label:SetWidth(w - 12)
        t.label:SetJustifyH("CENTER")
        t.label:SetText(L[stat.label])
        if stat.opensFarm then
            t:EnableMouse(true)
            t:SetScript("OnMouseUp", function() ns.UI:SelectTab("farm") end)
        end
        p.stats[stat.key] = t
    end

    withTooltip(p.stats.missing, function(tt)
        tt:AddLine(L["MISSING_BY_SOURCE"], 1, 1, 1)
        for _, src in ipairs(ns.Collection:GetMissingBySourceSorted()) do
            tt:AddDoubleLine(src.label, fmt(src.count), 1, 1, 1, C.success[1], C.success[2], C.success[3])
        end
    end)
end

-- "Start here" ----------------------------------------------------------------
local function createStart(p, top)
    local C = ns.UI.COLORS
    local box = panel(p)
    box:SetPoint("TOPLEFT", 0, top)
    box:SetPoint("BOTTOMRIGHT", -(RESETS_W + GAP), 0)

    local title = ns.UI.fs(box, "GameFontNormal", C.accent)
    title:SetPoint("TOPLEFT", 10, -10)
    title:SetText(L["HOME_START"])
    p.startSummary = ns.UI.fs(box, "GameFontHighlightSmall", C.muted)
    p.startSummary:SetPoint("TOPRIGHT", -10, -12)
    p.startSummary:SetJustifyH("RIGHT")

    p.startRows = {}
    for i = 1, START_ROWS do
        local r = CreateFrame("Frame", nil, box)
        r:SetPoint("TOPLEFT", 8, -32 - (i - 1) * START_ROW_H)
        r:SetPoint("RIGHT", -8, 0)
        r:SetHeight(START_ROW_H - 4)
        local bg = r:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.18)

        r.badge = ns.UI.NumberBadge(r, 20)
        r.badge:SetPoint("LEFT", 6, 0)
        r.badge.text:SetText(i)

        r.go = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        r.go:SetSize(50, 20)
        r.go:SetPoint("RIGHT", -6, 0)
        r.go:SetText(L["BTN_GO"])

        r.count = ns.UI.fs(r, "GameFontHighlightSmall", C.success)
        r.count:SetPoint("RIGHT", r.go, "LEFT", -8, 0)
        r.count:SetJustifyH("RIGHT")

        r.name = ns.UI.fs(r, "GameFontNormal")
        r.name:SetPoint("TOPLEFT", r.badge, "TOPRIGHT", 8, 3)
        r.name:SetPoint("RIGHT", r.count, "LEFT", -6, 0)
        r.name:SetWordWrap(false)
        r.detail = ns.UI.fs(r, "GameFontHighlightSmall", C.muted)
        r.detail:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -2)
        r.detail:SetPoint("RIGHT", r.count, "LEFT", -6, 0)
        r.detail:SetWordWrap(false)
        p.startRows[i] = r
    end

    p.startEmpty = ns.UI.fs(box, "GameFontHighlightSmall", C.muted)
    p.startEmpty:SetPoint("TOPLEFT", 10, -34)
    p.startEmpty:SetPoint("RIGHT", -10, 0)
    p.startEmpty:SetWordWrap(true)

    local seeAll = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    seeAll:SetHeight(22)
    seeAll:SetPoint("BOTTOMRIGHT", -8, 8)
    seeAll:SetText(L["HOME_SEE_ALL"])
    seeAll:SetWidth(seeAll:GetFontString():GetStringWidth() + 28)
    seeAll:SetScript("OnClick", function() ns.UI:SelectTab("farm") end)
end

-- Upcoming resets -------------------------------------------------------------
local function resetLine(parent, y, labelKey)
    local C = ns.UI.COLORS
    local label = ns.UI.fs(parent, "GameFontHighlight")
    label:SetPoint("TOPLEFT", 10, y)
    label:SetText(L[labelKey])
    local when = ns.UI.fs(parent, "GameFontHighlight", C.accent)
    when:SetPoint("TOPRIGHT", -10, y)
    when:SetJustifyH("RIGHT")
    local left = ns.UI.fs(parent, "GameFontHighlightSmall", C.muted)
    left:SetPoint("TOPRIGHT", when, "BOTTOMRIGHT", 0, -2)
    left:SetJustifyH("RIGHT")
    return { when = when, left = left }
end

local function createResets(p, top)
    local C = ns.UI.COLORS
    local box = panel(p)
    box:SetPoint("TOPRIGHT", 0, top)
    box:SetPoint("BOTTOMRIGHT")
    box:SetWidth(RESETS_W)

    local title = ns.UI.fs(box, "GameFontNormal", C.accent)
    title:SetPoint("TOPLEFT", 10, -10)
    title:SetText(L["HOME_RESETS"])

    p.daily = resetLine(box, -36, "RESET_DAILY")
    p.weekly = resetLine(box, -78, "RESET_WEEKLY")

    local note = ns.UI.fs(box, "GameFontDisableSmall")
    note:SetPoint("BOTTOMLEFT", 10, 10)
    note:SetWidth(RESETS_W - 20)
    note:SetWordWrap(true)
    note:SetText(L["RESET_NOTE"])
end

local function setReset(line, secs)
    if not secs or secs <= 0 then
        line.when:SetText("?")
        line.left:SetText("")
        return
    end
    -- Round to the minute: the countdown lags a few seconds, so 16:00 showed as 15:59.
    local t = math.floor((time() + secs + 30) / 60) * 60
    local day = _G["WEEKDAY_" .. WEEKDAYS[tonumber(date("%w", t)) + 1]] or date("%A", t)
    line.when:SetText(("%s %s"):format(day, date("%H:%M", t)))
    line.left:SetFormattedText(L["RESET_IN"], SecondsToTime(secs, true))
end

-- Public ----------------------------------------------------------------------
function HomePanel:Create(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()
    createGreeting(p)
    local top = -(HEADER_H + GAP)
    createRingTile(p, top)
    createStatTiles(p, top)
    top = top - TILE_H - GAP
    createStart(p, top)
    createResets(p, top)
    return p
end

--- entries/sum come from FarmList:Build() and FarmList:Summarize().
function HomePanel:Refresh(p, entries, sum)
    SetPortraitTexture(p.portrait, "player")
    p.greeting:SetFormattedText(L["HOME_GREETING"], UnitName("player"))

    local s = ns.Collection.summary or ns.Collection:Scan()
    if s and s.visibleTotal and s.visibleTotal > 0 then
        local pct = s.collectedVisible / s.visibleTotal
        setRing(p.ringCooldown, pct)
        p.ringPct:SetFormattedText("%.1f%%", pct * 100)
        p.ringValue:SetFormattedText("%s / %s", fmt(s.collectedVisible), fmt(s.visibleTotal))
        p.stats.missing.value:SetText(fmt(s.missingVisible))
    else
        setRing(p.ringCooldown, 0)
        p.ringPct:SetText("—")
        p.ringValue:SetText(L["JOURNAL_NOT_READY_SHORT"])
        p.stats.missing.value:SetText("—")
    end
    p.stats.ready.value:SetText(fmt(sum.ready))
    p.stats.locked.value:SetText(ns.Lockouts.loaded and fmt(sum.locked) or "…")
    p.stats.verify.value:SetText(fmt(sum.verify))

    -- First instances of the farm list (already ordered by proximity).
    local shown = 0
    for _, e in ipairs(entries) do
        if shown >= START_ROWS then break end
        if e.readyCount > 0 and not e.hidden then
            shown = shown + 1
            local r = p.startRows[shown]
            r.name:SetText(ns.FarmList:InstanceName(e.jid))
            local parts = { e.inst.isRaid and L["TYPE_RAID"] or L["TYPE_DUNGEON"] }
            local zone = e.inst.entrance and C_Map.GetMapInfo(e.inst.entrance.uiMapID)
            if zone then parts[#parts + 1] = zone.name end
            r.detail:SetText(table.concat(parts, " · "))
            r.count:SetText(e.readyCount == 1 and L["MOUNT_ONE"] or L["MOUNTS_N"]:format(e.readyCount))
            local jid = e.jid
            r.go:SetEnabled(e.inst.entrance ~= nil)
            r.go:SetScript("OnClick", function() ns.Navigation:GoToInstance(jid) end)
            r:Show()
        end
    end
    for i = shown + 1, START_ROWS do p.startRows[i]:Hide() end
    p.startEmpty:SetShown(shown == 0)
    if shown == 0 then
        p.startEmpty:SetText(ns.Lockouts.loaded and L["FARM_EMPTY"] or L["NOW_LOCKOUTS_LOADING"])
    end
    p.startSummary:SetFormattedText(L["HOME_START_SUMMARY"], sum.ready, sum.instances)

    local daily, weekly = ns.Lockouts:GetResetTimes()
    setReset(p.daily, daily)
    setReset(p.weekly, weekly)
end
