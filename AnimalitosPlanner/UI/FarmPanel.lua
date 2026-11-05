-- "Farmable now" (docs/02-ux-ui.md §4): instances grouped by continent (the
-- player's continent first), one numbered card per instance with a row per
-- missing mount (hover = tooltip, click = preview), then collapsible
-- "Locked out" and "Needs verification" sections.
local _, ns = ...
local L = ns.L

local FarmPanel = {}
ns.FarmPanel = FarmPanel

local CARD_GAP = 6
local GROUP_GAP = 12
local CARD_HEAD_H = 40
local ROW_H = 22
local ROW_INDENT = 34
local SCROLL_W = 24
local RIGHT_MARGIN = 8 -- keeps cards off the scroll bar
local PLUS = "Interface\\Buttons\\UI-PlusButton-Up"
local MINUS = "Interface\\Buttons\\UI-MinusButton-Up"
local MUTED_HEX = "|cffb3adc2"

local function mountName(id)
    local m = ns.MountJournal:GetMount(id)
    return m and m.name or ("#" .. id)
end

local function diffList(list)
    local names = {}
    for _, d in ipairs(list) do names[#names + 1] = ns.FarmList:DifficultyName(d) end
    return table.concat(names, ", ")
end

local function expanded()
    local ui = ns.Storage.db.ui
    ui.expanded = ui.expanded or {} -- [sectionKey] = true when open; collapsed by default
    return ui.expanded
end

local function timeLeft(resetAt)
    return resetAt and SecondsToTime(math.max(0, resetAt - time()), true, nil, 2) or "?"
end

-- Tooltip ---------------------------------------------------------------------
local function showMountTooltip(row)
    local C = ns.UI.COLORS
    local info = row.info
    local m = info.m
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(mountName(info.id), 1, 1, 1)
    GameTooltip:AddLine(("%s · %s"):format(ns.FarmList:BossName(m.source), ns.FarmList:InstanceName(info.jid)),
        C.muted[1], C.muted[2], C.muted[3])
    if #m.ready > 0 then
        GameTooltip:AddLine(L["TIP_READY"]:format(diffList(m.ready)), C.success[1], C.success[2], C.success[3])
    end
    if #m.locked > 0 then
        GameTooltip:AddLine(L["TIP_LOCKED"]:format(diffList(m.locked), timeLeft(m.resetAt)),
            C.warning[1], C.warning[2], C.warning[3])
    end
    for _, v in ipairs(m.verify) do
        GameTooltip:AddLine(("%s: %s"):format(ns.FarmList:DifficultyName(v.difficulty), v.reason),
            C.muted[1], C.muted[2], C.muted[3], true)
    end
    GameTooltip:AddLine(L["TIP_CLICK_PREVIEW"], C.accent[1], C.accent[2], C.accent[3])
    GameTooltip:Show()
end

-- Pools -----------------------------------------------------------------------
local function newCard(p)
    local c = CreateFrame("Frame", nil, p.child, "BackdropTemplate")
    local s = ns.UI.COLORS.surface
    ns.UI.StylePanel(c, { s[1], s[2], s[3], 0.85 })

    c.badge = ns.UI.NumberBadge(c, 20)
    c.badge:SetPoint("TOPLEFT", 8, -9)

    c.hide = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    c.hide:SetSize(62, 20)
    c.hide:SetPoint("TOPRIGHT", -6, -8)
    c.hide:SetText(L["BTN_HIDE"])
    c.go = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    c.go:SetSize(50, 20)
    c.go:SetPoint("RIGHT", c.hide, "LEFT", -2, 0)
    c.go:SetText(L["BTN_GO"])

    c.title = ns.UI.fs(c, "GameFontNormal")
    c.title:SetPoint("TOPLEFT", c.badge, "TOPRIGHT", 8, 3)
    c.title:SetPoint("RIGHT", c.go, "LEFT", -6, 0)
    c.title:SetWordWrap(false)
    c.detail = ns.UI.fs(c, "GameFontHighlightSmall", ns.UI.COLORS.muted)
    c.detail:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -2)
    c.detail:SetPoint("RIGHT", c.go, "LEFT", -6, 0)
    c.detail:SetWordWrap(false)
    return c
end

local function newRow(p)
    local r = CreateFrame("Button", nil, p.child)
    r:SetHeight(ROW_H)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.07)

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(18, 18)
    r.icon:SetPoint("LEFT", 2, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    r.status = ns.UI.fs(r, "GameFontHighlightSmall")
    r.status:SetPoint("RIGHT", -6, 0)
    r.status:SetJustifyH("RIGHT")
    r.dot = ns.UI.Circle(r, "ARTWORK", 8, { 1, 1, 1 })
    r.dot:SetPoint("RIGHT", r.status, "LEFT", -4, 0)

    r.text = ns.UI.fs(r, "GameFontHighlight")
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.text:SetPoint("RIGHT", r.dot, "LEFT", -8, 0)
    r.text:SetWordWrap(false)

    r:SetScript("OnEnter", showMountTooltip)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self) ns.MountPreview:Toggle(self.info.id) end)
    return r
end

local function newHeader(p)
    local h = CreateFrame("Frame", nil, p.child)
    h:SetHeight(20)
    h.text = ns.UI.fs(h, "GameFontNormal", ns.UI.COLORS.accent)
    h.text:SetPoint("LEFT", 2, 0)
    h.count = ns.UI.fs(h, "GameFontHighlightSmall", ns.UI.COLORS.muted)
    h.count:SetPoint("RIGHT", -2, 0)
    h.count:SetJustifyH("RIGHT")
    local line = h:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    local a = ns.UI.COLORS.accent
    line:SetColorTexture(a[1], a[2], a[3], 0.3)
    return h
end

local function newSection(p)
    local s = CreateFrame("Button", nil, p.child)
    s:SetHeight(24)
    local hl = s:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetSize(14, 14)
    s.icon:SetPoint("LEFT", 4, 0)
    s.text = ns.UI.fs(s, "GameFontNormal")
    s.text:SetPoint("LEFT", s.icon, "RIGHT", 6, 0)
    s:SetScript("OnClick", function(self)
        local ex = expanded()
        ex[self.key] = not ex[self.key] or nil
        ns.UI:Refresh()
    end)
    return s
end

local function newLine(p)
    local l = ns.UI.fs(p.child, "GameFontHighlightSmall")
    l:SetWordWrap(true)
    return l
end

local FACTORIES = { cards = newCard, rows = newRow, headers = newHeader, sections = newSection, lines = newLine }

local function take(p, kind)
    local n = (p.used[kind] or 0) + 1
    p.used[kind] = n
    local pool = p.pools[kind]
    pool[n] = pool[n] or FACTORIES[kind](p)
    return pool[n]
end

local function releaseAll(p)
    for _, pool in pairs(p.pools) do
        for _, o in ipairs(pool) do o:Hide() end
    end
    wipe(p.used)
end

-- Grouping --------------------------------------------------------------------
-- Visible ready instances grouped by entrance continent (0 = no entrance).
-- Player's continent first, then by number of mounts; "no location" last.
-- Inside a group the FarmList order (proximity, mounts, expansion) is kept.
local function groupByContinent(entries, playerContinent)
    local groups, byKey = {}, {}
    for _, e in ipairs(entries) do
        if e.readyCount > 0 and not e.hidden then
            local key = (e.inst.entrance and e.inst.entrance.continent) or 0
            local g = byKey[key]
            if not g then
                g = { key = key, entries = {}, mounts = 0 }
                byKey[key] = g
                groups[#groups + 1] = g
            end
            g.entries[#g.entries + 1] = e
            g.mounts = g.mounts + e.readyCount
        end
    end
    table.sort(groups, function(a, b)
        if (a.key == 0) ~= (b.key == 0) then return b.key == 0 end
        local aHere, bHere = a.key == playerContinent, b.key == playerContinent
        if aHere ~= bHere then return aHere end
        if a.mounts ~= b.mounts then return a.mounts > b.mounts end
        return a.key < b.key
    end)
    return groups
end

local function continentName(key)
    if key == 0 then return L["GROUP_NO_LOCATION"] end
    local info = C_Map.GetMapInfo(key)
    return info and info.name or ("#" .. key)
end

-- Create ----------------------------------------------------------------------
function FarmPanel:Create(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()

    local scroll = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -SCROLL_W, 0)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(ns.UI.CONTENT_WIDTH - SCROLL_W, 1)
    scroll:SetScrollChild(child)

    p.scroll, p.child = scroll, child
    p.pools, p.used = {}, {}
    for kind in pairs(FACTORIES) do p.pools[kind] = {} end

    p.unhide = CreateFrame("Button", nil, child, "UIPanelButtonTemplate")
    p.unhide:SetHeight(20)
    p.unhide:SetScript("OnClick", function()
        ns.FarmList:UnhideAll()
        ns.UI:Refresh()
    end)
    return p
end

-- Refresh ---------------------------------------------------------------------
--- Rebuilds the list. entries/sum come from FarmList:Build() and FarmList:Summarize().
function FarmPanel:Refresh(p, entries, sum)
    local C = ns.UI.COLORS
    releaseAll(p)
    p.unhide:Hide()

    local width = p.child:GetWidth() - RIGHT_MARGIN
    local y = 0

    local function line(text, color)
        local l = take(p, "lines")
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", 4, -y)
        l:SetWidth(width - 8)
        l:SetTextColor(color[1], color[2], color[3])
        l:SetText(text)
        l:Show()
        y = y + l:GetStringHeight() + 6
    end

    -- mode: "ready" (inside a card), "locked" or "verify" (section rows)
    local function mountRow(anchor, x, rowY, rightInset, id, m, jid, mode)
        local r = take(p, "rows")
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, -rowY)
        r:SetPoint("RIGHT", anchor, "RIGHT", -rightInset, 0)
        r:SetFrameLevel(anchor:GetFrameLevel() + 3)
        r.info = { id = id, m = m, jid = jid }

        local mj = ns.MountJournal:GetMount(id)
        r.icon:SetTexture(mj and mj.icon or 134400) -- 134400 = question-mark icon
        local name = mj and mj.name or ("#" .. id)
        local color
        if mode == "ready" then
            r.text:SetText(("%s  %s(%s)|r"):format(name, MUTED_HEX, diffList(m.ready)))
            r.status:SetText(L["STATUS_READY"])
            color = C.success
        elseif mode == "locked" then
            r.text:SetText(("%s  %s%s (%s)|r"):format(name, MUTED_HEX, ns.FarmList:InstanceName(jid), diffList(m.locked)))
            r.status:SetText(L["RESET_IN"]:format(timeLeft(m.resetAt)))
            color = C.warning
        else
            local v = m.verify[1]
            r.text:SetText(("%s  %s%s (%s)|r"):format(name, MUTED_HEX, ns.FarmList:InstanceName(jid),
                ns.FarmList:DifficultyName(v.difficulty)))
            r.status:SetText(L["STATUS_VERIFY"])
            color = C.muted
        end
        r.status:SetTextColor(color[1], color[2], color[3])
        r.dot:SetVertexColor(color[1], color[2], color[3])
        r:Show()
    end

    if not ns.Lockouts.loaded then line(L["NOW_LOCKOUTS_LOADING"], C.muted) end

    -- Ready instances, grouped by continent
    local playerContinent = ns.FarmList:PlayerContinent()
    local index = 0
    for gi, g in ipairs(groupByContinent(entries, playerContinent)) do
        if gi > 1 then y = y + GROUP_GAP - CARD_GAP end
        local h = take(p, "headers")
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", 0, -y)
        h:SetWidth(width)
        local title = continentName(g.key)
        if g.key ~= 0 and g.key == playerContinent then
            title = ("%s  |cff8dd3a8%s|r"):format(title, L["GROUP_HERE"])
        end
        h.text:SetText(title)
        h.count:SetFormattedText(L["HOME_START_SUMMARY"], g.mounts, #g.entries)
        h:Show()
        y = y + h:GetHeight() + 6

        for _, e in ipairs(g.entries) do
            index = index + 1
            local c = take(p, "cards")
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", 0, -y)
            c:SetWidth(width)
            c.badge.text:SetText(index)

            local near = e.near == 2 and ("  |cff8dd3a8" .. L["NEAR_HERE"] .. "|r") or ""
            c.title:SetText(ns.FarmList:InstanceName(e.jid) .. near)
            local parts = { e.inst.isRaid and L["TYPE_RAID"] or L["TYPE_DUNGEON"] }
            local zone = e.inst.entrance and C_Map.GetMapInfo(e.inst.entrance.uiMapID)
            if zone then parts[#parts + 1] = zone.name end
            parts[#parts + 1] = e.readyCount == 1 and L["MOUNT_ONE"] or L["MOUNTS_N"]:format(e.readyCount)
            c.detail:SetText(table.concat(parts, " · "))

            local jid, isRaid = e.jid, e.inst.isRaid
            c.go:SetEnabled(e.inst.entrance ~= nil)
            c.go:SetScript("OnClick", function() ns.Navigation:GoToInstance(jid) end)
            c.hide:SetScript("OnClick", function()
                ns.FarmList:Hide(jid, isRaid)
                ns.UI:Refresh()
            end)

            local ids = {}
            for id, m in pairs(e.mounts) do
                if #m.ready > 0 then ids[#ids + 1] = id end
            end
            table.sort(ids, function(a, b) return mountName(a) < mountName(b) end)
            local rowY = CARD_HEAD_H
            for _, id in ipairs(ids) do
                mountRow(c, ROW_INDENT, rowY, 8, id, e.mounts[id], jid, "ready")
                rowY = rowY + ROW_H
            end
            c:SetHeight(rowY + 6)
            c:Show()
            y = y + c:GetHeight() + CARD_GAP
        end
    end
    if index == 0 then line(L["FARM_EMPTY"], C.muted) end

    if sum.hidden > 0 then
        p.unhide:SetText(L["BTN_UNHIDE"]:format(sum.hidden))
        p.unhide:SetWidth(p.unhide:GetFontString():GetStringWidth() + 28)
        p.unhide:ClearAllPoints()
        p.unhide:SetPoint("TOPLEFT", 0, -y)
        p.unhide:Show()
        y = y + 26
    end

    -- Locked out / needs verification (same rules as FarmList:Summarize)
    local locked, verify = {}, {}
    for _, e in ipairs(entries) do
        for id, m in pairs(e.mounts) do
            if #m.ready == 0 then
                if #m.locked > 0 then
                    locked[#locked + 1] = { id = id, m = m, jid = e.jid }
                elseif #m.verify > 0 then
                    verify[#verify + 1] = { id = id, m = m, jid = e.jid }
                end
            end
        end
    end
    table.sort(locked, function(a, b) return (a.m.resetAt or 0) < (b.m.resetAt or 0) end)
    table.sort(verify, function(a, b) return mountName(a.id) < mountName(b.id) end)

    local function section(key, titleKey, items, color, mode)
        if #items == 0 then return end
        y = y + 4
        local s = take(p, "sections")
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", 0, -y)
        s:SetWidth(width)
        s.key = key
        local open = expanded()[key]
        s.icon:SetTexture(open and MINUS or PLUS)
        s.text:SetText(("%s (%d)"):format(L[titleKey], #items))
        s.text:SetTextColor(color[1], color[2], color[3])
        s:Show()
        y = y + s:GetHeight() + 2
        if open then
            for _, it in ipairs(items) do
                mountRow(p.child, 8, y, RIGHT_MARGIN + 8, it.id, it.m, it.jid, mode)
                y = y + ROW_H
            end
        end
    end
    section("locked", "SECTION_LOCKED", locked, C.warning, "locked")
    section("verify", "SECTION_VERIFY", verify, C.muted, "verify")

    p.child:SetHeight(math.max(y, 1))
end
