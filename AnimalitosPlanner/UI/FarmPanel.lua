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
local CARD_MIN_H = 70
local ROW_H = 22
local THUMB_W = 92  -- instance artwork on the left of each card
local THUMB_INSET = 6
local ROW_INDENT = THUMB_INSET + THUMB_W + 10
local SCROLL_W = 14 -- thin scroll bar + gap
local SEARCH_H = 24
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
    if info.event then -- world event boss (Dungeon Finder queue)
        GameTooltip:AddLine(("%s · %s"):format(info.event.name, info.event.event or ""),
            C.tipMuted[1], C.tipMuted[2], C.tipMuted[3])
        GameTooltip:AddLine(L["EVENT_DAILY"], C.tipMuted[1], C.tipMuted[2], C.tipMuted[3], true)
        GameTooltip:AddLine(L["TIP_CLICK_PREVIEW"], C.accent[1], C.accent[2], C.accent[3])
        GameTooltip:Show()
        return
    end
    GameTooltip:AddLine(("%s · %s"):format(ns.FarmList:BossName(m.source), ns.FarmList:InstanceName(info.jid)),
        C.tipMuted[1], C.tipMuted[2], C.tipMuted[3])
    if #m.ready > 0 then
        GameTooltip:AddLine(L["TIP_READY"]:format(diffList(m.ready)), C.success[1], C.success[2], C.success[3])
    end
    if #m.locked > 0 then
        GameTooltip:AddLine(L["TIP_LOCKED"]:format(diffList(m.locked), timeLeft(m.resetAt)),
            C.warning[1], C.warning[2], C.warning[3])
    end
    for _, v in ipairs(m.verify) do
        GameTooltip:AddLine(("%s: %s"):format(ns.FarmList:DifficultyName(v.difficulty), v.reason),
            C.tipMuted[1], C.tipMuted[2], C.tipMuted[3], true)
    end
    GameTooltip:AddLine(L["TIP_CLICK_PREVIEW"], C.accent[1], C.accent[2], C.accent[3])
    GameTooltip:Show()
end

-- Pools -----------------------------------------------------------------------
local function newCard(p)
    local c = CreateFrame("Frame", nil, p.child, "BackdropTemplate")
    local s = ns.UI.COLORS.surface
    ns.UI.StylePanel(c, { s[1], s[2], s[3], 0.85 })

    -- Instance artwork (Encounter Journal tile) with rounded corners; a
    -- placeholder tint shows when the client has no art for it.
    c.thumbBg = ns.UI.RoundedTexture(c, "ARTWORK", 0)
    c.thumbBg:ClearAllPoints()
    c.thumbBg:SetPoint("TOPLEFT", THUMB_INSET, -THUMB_INSET)
    c.thumbBg:SetPoint("BOTTOMLEFT", THUMB_INSET, THUMB_INSET)
    c.thumbBg:SetWidth(THUMB_W)
    local a = ns.UI.COLORS.accent
    c.thumbBg:SetVertexColor(a[1], a[2], a[3], 0.12)
    c.thumb = ns.UI.ArtTexture(c, "ARTWORK", 1)
    c.thumb:SetAllPoints(c.thumbBg)

    c.hide = ns.UI.Button(c, "secondary")
    ns.UI.SetButtonText(c.hide, L["BTN_HIDE"], 62)
    c.hide:SetPoint("TOPRIGHT", -8, -8)
    c.go = ns.UI.Button(c, "primary")
    ns.UI.SetButtonText(c.go, L["BTN_GO"], 50)
    c.go:SetPoint("RIGHT", c.hide, "LEFT", -6, 0)
    -- "Set 25H": the difficulty the Ready mounts drop on (only when it is
    -- not set yet; solo or group leader, outside the instance).
    c.diff = ns.UI.Button(c, "secondary")
    c.diff:SetPoint("RIGHT", c.go, "LEFT", -6, 0)
    c.diff:SetScript("OnLeave", function() GameTooltip:Hide() end)
    c.diff:Hide()

    c.title = ns.UI.fs(c, "GameFontNormal")
    c.title:SetPoint("TOPLEFT", ROW_INDENT, -9)
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
    r.zebra = r:CreateTexture(nil, "BACKGROUND")
    r.zebra:SetAllPoints()
    r.zebra:SetColorTexture(1, 1, 1, 0.03)
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
    h.text = ns.UI.SectionTitle(h)
    h.text:SetPoint("LEFT", 2, 0)
    h.count = ns.UI.fs(h, "small", ns.UI.COLORS.muted)
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
-- Cards to draw grouped by entrance continent (0 = no entrance). Each card
-- is { e = entry, ids = mount IDs to list }. Player's continent first, then
-- by number of mounts; "no location" last. Inside a group the FarmList
-- order (proximity, mounts, expansion) is kept.
local function groupByContinent(cards, playerContinent)
    local groups, byKey = {}, {}
    for _, card in ipairs(cards) do
        local e = card.e
        local key = (e.inst.entrance and e.inst.entrance.continent) or 0
        local g = byKey[key]
        if not g then
            g = { key = key, entries = {}, mounts = 0 }
            byKey[key] = g
            groups[#groups + 1] = g
        end
        g.entries[#g.entries + 1] = card
        g.mounts = g.mounts + #card.ids
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

    -- Search: filters by mount, instance or zone name while typing. Only the
    -- list is redrawn (with the last Build), so typing stays cheap.
    p.query = ""
    p.search = ns.UI.SearchBox(p, L["SEARCH_HINT"], function(text)
        p.query = strtrim(text):lower()
        if p.bar then p.bar:SetValue(0) end
        if p.lastEntries then FarmPanel:Refresh(p, p.lastEntries, p.lastSum) end
    end)
    p.search:SetPoint("TOPLEFT", 0, 0)
    p.search:SetPoint("TOPRIGHT", -SCROLL_W, 0)

    local scroll = CreateFrame("ScrollFrame", nil, p)
    scroll:SetPoint("TOPLEFT", 0, -(SEARCH_H + 8))
    scroll:SetPoint("BOTTOMRIGHT", -SCROLL_W, 0)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(ns.UI.CONTENT_WIDTH - SCROLL_W, 1)
    scroll:SetScrollChild(child)
    p.bar = ns.UI.ThinScrollBar(scroll)

    p.scroll, p.child = scroll, child
    p.pools, p.used = {}, {}
    for kind in pairs(FACTORIES) do p.pools[kind] = {} end

    p.unhide = ns.UI.Button(child, "secondary")
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
    p.lastEntries, p.lastSum = entries, sum

    -- Search filter (plain, case-insensitive substring).
    local q = p.query or ""
    local searching = q ~= ""
    local function hit(s) return s and s:lower():find(q, 1, true) ~= nil end
    local function instanceHit(e)
        if hit(ns.FarmList:InstanceName(e.jid)) then return true end
        local ent = e.inst.entrance
        if not ent then return false end
        local zone = C_Map.GetMapInfo(ent.uiMapID)
        return hit(zone and zone.name) or hit(continentName(ent.continent or 0))
    end

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
    local function mountRow(anchor, x, rowY, rightInset, id, m, jid, mode, zebra)
        local r = take(p, "rows")
        r.zebra:SetShown(zebra or false)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, -rowY)
        r:SetPoint("RIGHT", anchor, "RIGHT", -rightInset, 0)
        r:SetFrameLevel(anchor:GetFrameLevel() + 3)
        r.info = { id = id, m = m, jid = jid, event = mode == "event" and m or nil }

        local mj = ns.MountJournal:GetMount(id)
        r.icon:SetTexture(mj and mj.icon or 134400) -- 134400 = question-mark icon
        local name = (ns.Collection:IsFavorite(id) and (ns.UI.STAR .. " ") or "") .. (mj and mj.name or ("#" .. id))
        local color
        if mode == "event" then
            -- m = FarmList:Holidays() item
            local S = ns.Eligibility.STATES
            r.text:SetText(name)
            if m.state == S.READY then
                r.status:SetText(L["STATUS_READY"])
                color = C.success
            elseif m.state == S.LOCKED_OUT then
                r.status:SetText(L["RESET_IN"]:format(timeLeft(m.resetAt)))
                color = C.warning
            else
                r.status:SetText(L["STATUS_VERIFY"])
                color = C.muted
            end
        elseif mode == "ready" then
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

    -- "Show hidden" at the top, where it is seen without scrolling.
    if sum.hidden > 0 and not searching then
        ns.UI.SetButtonText(p.unhide, L["BTN_UNHIDE"]:format(sum.hidden))
        p.unhide:ClearAllPoints()
        p.unhide:SetPoint("TOPLEFT", 0, -y)
        p.unhide:Show()
        y = y + 30
    end

    -- World event bosses while their event is on: on top, one card each,
    -- "Queue" opens the Dungeon Finder (no travel).
    local events = {}
    for _, ev in ipairs(ns.FarmList:Holidays()) do
        local keep = not searching or hit(ev.name) or hit(ev.event)
        if not keep then
            for _, id in ipairs(ev.mounts) do keep = keep or hit(mountName(id)) end
        end
        if keep then events[#events + 1] = ev end
    end
    if #events > 0 then
        local h = take(p, "headers")
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", 0, -y)
        h:SetWidth(width)
        h.text:SetText(ns.UI.Upper(L["EVENT_HEADER"]))
        h.count:SetText("")
        h:Show()
        y = y + h:GetHeight() + 6
        for _, ev in ipairs(events) do
            local c = take(p, "cards")
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", 0, -y)
            c:SetWidth(width)
            c.title:SetText(ev.name)
            c.detail:SetText(("%s · %s"):format(ev.event or "", L["EVENT_DAILY_SHORT"]))
            ns.UI.SetButtonText(c.go, L["BTN_QUEUE"], 62)
            c.go:SetEnabled(true)
            local lfgID = ev.h.lfgDungeonID
            c.go:SetScript("OnClick", function()
                if not ns.Holidays:OpenQueue(lfgID) then ns:Print(L["JOURNAL_COMBAT"]) end
            end)
            c.hide:Hide()
            c.diff:Hide()
            c.title:SetPoint("RIGHT", c.go, "LEFT", -6, 0)
            c.detail:SetPoint("RIGHT", c.go, "LEFT", -6, 0)
            c.go:ClearAllPoints()
            c.go:SetPoint("TOPRIGHT", -8, -8)
            local rowY = CARD_HEAD_H
            for k, id in ipairs(ev.mounts) do
                mountRow(c, ROW_INDENT, rowY, 8, id, ev, nil, "event", k % 2 == 1)
                rowY = rowY + ROW_H
            end
            local ch = math.max(rowY + 6, CARD_MIN_H)
            c:SetHeight(ch)
            -- Artwork: the first mount's icon, square and centered (events
            -- have no journal tile; cropping the icon like art blew it up).
            local mj = ns.MountJournal:GetMount(ev.mounts[1])
            c.thumb:ClearAllPoints()
            c.thumb:SetPoint("CENTER", c.thumbBg)
            c.thumb:SetSize(44, 44)
            c.thumb:SetTexture(mj and mj.icon or nil)
            c.thumb:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            c.thumb:SetShown(mj ~= nil)
            c:Show()
            y = y + ch + CARD_GAP
        end
        y = y + GROUP_GAP - CARD_GAP
    end

    -- Ready instances, grouped by continent
    local playerContinent = ns.FarmList:PlayerContinent()
    local index = 0
    local cards = {}
    for _, e in ipairs(entries) do
        if e.readyCount > 0 and not e.hidden then
            local all = not searching or instanceHit(e)
            local ids = {}
            for id, m in pairs(e.mounts) do
                if #m.ready > 0 and (all or hit(mountName(id))) then ids[#ids + 1] = id end
            end
            if #ids > 0 then
                -- Boss order inside the instance, then name.
                table.sort(ids, function(a, b)
                    local oa = ns.FarmList:BossOrder(e.mounts[a].source)
                    local ob = ns.FarmList:BossOrder(e.mounts[b].source)
                    if oa ~= ob then return oa < ob end
                    return mountName(a) < mountName(b)
                end)
                cards[#cards + 1] = { e = e, ids = ids }
            end
        end
    end
    for gi, g in ipairs(groupByContinent(cards, playerContinent)) do
        if gi > 1 then y = y + GROUP_GAP - CARD_GAP end
        local h = take(p, "headers")
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", 0, -y)
        h:SetWidth(width)
        local title = ns.UI.Upper(continentName(g.key))
        if g.key ~= 0 and g.key == playerContinent then
            title = ("%s  |cff8dd3a8%s|r"):format(title, L["GROUP_HERE"])
        end
        h.text:SetText(title)
        h.count:SetText(ns.UI.CountsText(g.mounts, #g.entries))
        h:Show()
        y = y + h:GetHeight() + 6

        for _, card in ipairs(g.entries) do
            local e, ids = card.e, card.ids
            index = index + 1
            local c = take(p, "cards")
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", 0, -y)
            c:SetWidth(width)

            local near = e.near == 2 and ("  |cff8dd3a8" .. L["NEAR_HERE"] .. "|r") or ""
            c.title:SetText(ns.FarmList:InstanceName(e.jid) .. near)
            local parts = { ns.FarmList:TypeName(e.inst) }
            local zone = e.inst.entrance and C_Map.GetMapInfo(e.inst.entrance.uiMapID)
            if zone then parts[#parts + 1] = zone.name end
            parts[#parts + 1] = #ids == 1 and L["MOUNT_ONE"] or L["MOUNTS_N"]:format(#ids)
            -- Mount achievements with criteria here (details in the Planner tooltip).
            local links = ns.Collection:AchievementsByInstance()[e.jid]
            if links then parts[#parts + 1] = "|cffe0a040" .. L["FARM_ACH"]:format(#links) .. "|r" end
            c.detail:SetText(table.concat(parts, " · "))

            local jid, isRaid = e.jid, e.inst.isRaid
            -- Pooled cards may have been event cards: restore Go, Hide and the art.
            ns.UI.SetButtonText(c.go, L["BTN_GO"], 50)
            c.hide:Show()
            c.go:ClearAllPoints()
            c.go:SetPoint("RIGHT", c.hide, "LEFT", -6, 0)
            c.thumb:ClearAllPoints()
            c.thumb:SetAllPoints(c.thumbBg)
            c.go:SetEnabled(e.inst.entrance ~= nil)
            c.go:SetScript("OnClick", function() ns.Navigation:GoToInstance(jid) end)
            c.hide:SetScript("OnClick", function()
                ns.FarmList:Hide(jid, isRaid)
                ns.UI:Refresh()
            end)
            c.hide:SetScript("OnClick", function()
                ns.FarmList:Hide(jid, isRaid)
                ns.UI:Refresh()
            end)
            local D = ns.Difficulty
            local want = D:Pick(e)
            -- Members cannot set it (the leader does): no button for them.
            local showDiff = want and D:Settable(want) and not D:IsSet(want) and D:Inside(e) == nil
                and D:Blocked() ~= "leader"
            c.diff:SetShown(showDiff and true or false)
            if showDiff then
                local blocked = D:Blocked()
                ns.UI.SetButtonText(c.diff, L["MINI_DIFF_BTN"]:format(ns.FarmList:DifficultyName(want)), 70)
                c.diff:SetEnabled(blocked == nil)
                c.diff:SetScript("OnClick", function() D:Set(want) end)
                c.diff:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:AddLine(L["MINI_DIFF_NEED"]:format(D:Name(want)), 1, 1, 1)
                    local tip = (blocked == "leader" and L["MINI_DIFF_LEADER"]) or (blocked == "combat" and L["JOURNAL_COMBAT"])
                        or (blocked == "inside" and L["FARM_DIFF_INSIDE"]) or L["MINI_DIFF_TIP"]
                    GameTooltip:AddLine(tip, 0.8, 0.8, 0.8, true)
                    GameTooltip:Show()
                end)
            end
            local rightOf = showDiff and c.diff or c.go
            c.title:SetPoint("RIGHT", rightOf, "LEFT", -6, 0)
            c.detail:SetPoint("RIGHT", rightOf, "LEFT", -6, 0)
            local rowY = CARD_HEAD_H
            for k, id in ipairs(ids) do
                mountRow(c, ROW_INDENT, rowY, 8, id, e.mounts[id], jid, "ready", k % 2 == 1)
                rowY = rowY + ROW_H
            end
            local h = math.max(rowY + 6, CARD_MIN_H)
            c:SetHeight(h)
            local art = ns.FarmList:InstanceArt(jid)
            c.thumb:SetTexture(art)
            c.thumb:SetShown(art ~= nil)
            ns.UI.SetArtCrop(c.thumb, THUMB_W, h - THUMB_INSET * 2)
            c:Show()
            y = y + h + CARD_GAP
        end
    end
    if index == 0 and not searching then line(L["FARM_EMPTY"], C.muted) end

    -- Locked out / needs verification (same rules as FarmList:Summarize)
    local locked, verify = {}, {}
    for _, e in ipairs(entries) do
        local all = not searching or instanceHit(e)
        for id, m in pairs(e.mounts) do
            if #m.ready == 0 and (all or hit(mountName(id))) then
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
        local open = searching or expanded()[key] -- search results are always shown
        s.icon:SetTexture(open and MINUS or PLUS)
        s.text:SetText(("%s (%d)"):format(L[titleKey], #items))
        s.text:SetTextColor(color[1], color[2], color[3])
        s:Show()
        y = y + s:GetHeight() + 2
        if open then
            for k, it in ipairs(items) do
                mountRow(p.child, 8, y, RIGHT_MARGIN + 8, it.id, it.m, it.jid, mode, k % 2 == 1)
                y = y + ROW_H
            end
        end
    end
    section("locked", "SECTION_LOCKED", locked, C.warning, "locked")
    section("verify", "SECTION_VERIFY", verify, C.muted, "verify")

    if searching and index == 0 and #locked == 0 and #verify == 0 then
        line(L["SEARCH_NONE"]:format(p.search:GetText()), C.muted)
    end

    p.child:SetHeight(math.max(y, 1))
end
