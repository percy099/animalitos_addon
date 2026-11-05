-- "Farmable now" tab (docs/02-ux-ui.md §4): one card per instance with the
-- missing mounts that can drop this reset, a waypoint button and a
-- "hide until reset" button; then Locked out and Needs verification sections.
local _, ns = ...
local L = ns.L

local FarmPanel = {}
ns.FarmPanel = FarmPanel

local ROW_GAP = 6
local BUTTONS_WIDTH = 118
local WHITE = "Interface\\Buttons\\WHITE8x8"

local function mountName(id)
    local m = ns.MountJournal:GetMount(id)
    return m and m.name or ("#" .. id)
end

local function diffList(list)
    local names = {}
    for _, d in ipairs(list) do names[#names + 1] = ns.FarmList:DifficultyName(d) end
    return table.concat(names, ", ")
end

function FarmPanel:Create(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()

    local scroll = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -24, 0)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(ns.UI.WIDTH - 24 - 24, 1)
    scroll:SetScrollChild(child)

    p.scroll, p.child = scroll, child
    p.cards, p.lines = {}, {}

    p.unhide = CreateFrame("Button", nil, child, "UIPanelButtonTemplate")
    p.unhide:SetHeight(20)
    p.unhide:SetScript("OnClick", function()
        ns.FarmList:UnhideAll()
        ns.UI:Refresh()
    end)
    return p
end

-- Card pool -------------------------------------------------------------------
local function newCard(p)
    local c = CreateFrame("Frame", nil, p.child, "BackdropTemplate")
    c:SetBackdrop({ bgFile = WHITE })
    local s = ns.UI.COLORS.surface
    c:SetBackdropColor(s[1], s[2], s[3], 0.85)

    c.title = ns.UI.fs(c, "GameFontNormal")
    c.title:SetPoint("TOPLEFT", 8, -6)
    c.zone = ns.UI.fs(c, "GameFontHighlightSmall", ns.UI.COLORS.muted)
    c.zone:SetPoint("LEFT", c.title, "RIGHT", 6, 0)
    c.mounts = ns.UI.fs(c, "GameFontHighlightSmall", ns.UI.COLORS.success)
    c.mounts:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -4)
    c.mounts:SetWordWrap(true)

    c.hide = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    c.hide:SetSize(62, 20)
    c.hide:SetPoint("TOPRIGHT", -4, -5)
    c.hide:SetText(L["BTN_HIDE"])
    c.go = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    c.go:SetSize(50, 20)
    c.go:SetPoint("RIGHT", c.hide, "LEFT", -2, 0)
    c.go:SetText(L["BTN_GO"])
    return c
end

local function newLine(p)
    local l = ns.UI.fs(p.child, "GameFontHighlightSmall")
    l:SetWordWrap(true)
    return l
end

local function acquire(pool, index, factory, p)
    pool[index] = pool[index] or factory(p)
    return pool[index]
end

-- Refresh ---------------------------------------------------------------------
--- Rebuilds the list. Returns the number of missing mounts farmable now
--- (excluding hidden instances), used for the tab label.
function FarmPanel:Refresh(p, visible)
    local entries = ns.FarmList:Build()
    local readyMounts, hiddenCount = {}, 0
    for _, e in ipairs(entries) do
        if e.readyCount > 0 then
            if e.hidden then
                hiddenCount = hiddenCount + 1
            else
                for id, m in pairs(e.mounts) do
                    if #m.ready > 0 then readyMounts[id] = true end
                end
            end
        end
    end
    local readyTotal = 0
    for _ in pairs(readyMounts) do readyTotal = readyTotal + 1 end
    if not visible then return readyTotal end

    for _, c in ipairs(p.cards) do c:Hide() end
    for _, l in ipairs(p.lines) do l:Hide() end
    p.unhide:Hide()

    local width = p.child:GetWidth()
    local y, nCards, nLines = 0, 0, 0
    local function line(text, color)
        nLines = nLines + 1
        local l = acquire(p.lines, nLines, newLine, p)
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", 4, -y)
        l:SetWidth(width - 8)
        local c = color or { 1, 1, 1 }
        l:SetTextColor(c[1], c[2], c[3])
        l:SetText(text)
        l:Show()
        y = y + l:GetStringHeight() + 4
    end

    if not ns.Lockouts.loaded then line(L["NOW_LOCKOUTS_LOADING"], ns.UI.COLORS.muted) end

    -- Ready instances
    for _, e in ipairs(entries) do
        if e.readyCount > 0 and not e.hidden then
            nCards = nCards + 1
            local c = acquire(p.cards, nCards, newCard, p)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", 0, -y)
            c:SetWidth(width)

            local star = e.near == 2 and " |cffa88ad7*|r" or ""
            c.title:SetText(ns.FarmList:InstanceName(e.jid) .. star)
            local zone = e.inst.entrance and C_Map.GetMapInfo(e.inst.entrance.uiMapID)
            c.zone:SetText(zone and zone.name or "")

            local parts = {}
            for id, m in pairs(e.mounts) do
                if #m.ready > 0 then parts[#parts + 1] = ("%s (%s)"):format(mountName(id), diffList(m.ready)) end
            end
            table.sort(parts)
            c.mounts:SetWidth(width - 16)
            c.mounts:SetText(table.concat(parts, "\n"))

            local jid, isRaid = e.jid, e.inst.isRaid
            c.go:SetEnabled(e.inst.entrance ~= nil)
            c.go:SetScript("OnClick", function() ns.Navigation:GoToInstance(jid) end)
            c.hide:SetScript("OnClick", function()
                ns.FarmList:Hide(jid, isRaid)
                ns.UI:Refresh()
            end)

            local h = 6 + c.title:GetStringHeight() + 4 + c.mounts:GetStringHeight() + 8
            c:SetHeight(math.max(h, 32))
            c:Show()
            y = y + c:GetHeight() + ROW_GAP
        end
    end
    if nCards == 0 then line(L["FARM_EMPTY"], ns.UI.COLORS.muted) end

    if hiddenCount > 0 then
        p.unhide:SetText(L["BTN_UNHIDE"]:format(hiddenCount))
        p.unhide:SetWidth(p.unhide:GetFontString():GetStringWidth() + 28)
        p.unhide:ClearAllPoints()
        p.unhide:SetPoint("TOPLEFT", 0, -y)
        p.unhide:Show()
        y = y + 26
    end

    -- Locked out this reset
    local header = false
    for _, e in ipairs(entries) do
        for id, m in pairs(e.mounts) do
            if #m.locked > 0 and #m.ready == 0 then
                if not header then
                    y = y + 4
                    line(L["NOW_LOCKED_HEADER"], ns.UI.COLORS.warning)
                    header = true
                end
                local left = m.resetAt and SecondsToTime(math.max(0, m.resetAt - time())) or "?"
                line(("|cffe0a040%s|r — %s (%s): %s"):format(mountName(id), ns.FarmList:InstanceName(e.jid),
                    diffList(m.locked), L["NOW_RESETS_IN"]:format(left)))
            end
        end
    end

    -- Needs verification
    header = false
    for _, e in ipairs(entries) do
        for id, m in pairs(e.mounts) do
            if #m.verify > 0 and #m.ready == 0 then
                if not header then
                    y = y + 4
                    line(L["NOW_VERIFY_HEADER"], ns.UI.COLORS.muted)
                    header = true
                end
                local v = m.verify[1]
                line(("%s — %s (%s): %s"):format(mountName(id), ns.FarmList:InstanceName(e.jid),
                    ns.FarmList:DifficultyName(v.difficulty), v.reason), ns.UI.COLORS.muted)
            end
        end
    end

    p.child:SetHeight(math.max(y, 1))
    return readyTotal
end
