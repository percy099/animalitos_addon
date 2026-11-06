-- Collection section: every mount the Mount Journal shows for this character
-- (same set as its counter), with search, All / Missing / Collected filter,
-- a progress bar and click-to-preview.
-- The list is virtualized: only the rows that fit on screen exist, and they
-- are re-filled as you scroll (no frame per mount).
local _, ns = ...
local L = ns.L

local CollectionPanel = {}
ns.CollectionPanel = CollectionPanel

local ROW_H = 26
local SCROLL_W = 14
local SEARCH_H = 24
local TOOLBAR_H = 24
local PROGRESS_H = 30
local LIST_TOP = SEARCH_H + 8 + TOOLBAR_H + 8 + PROGRESS_H

local FILTERS = {
    { key = "all",       text = "COL_FILTER_ALL" },
    { key = "missing",   text = "COL_FILTER_MISSING" },
    { key = "collected", text = "COL_FILTER_COLLECTED" },
    { key = "favorites", text = "COL_FILTER_FAV" },
}

local function fmt(n)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

local function filterKey()
    local ui = ns.Storage.db.ui
    return ui.collectionFilter or "all"
end

-- Selected source type (Mount Journal sourceType number), or nil = all.
local function sourceKey()
    return ns.Storage.db.ui.collectionSource
end

local function diffList(list)
    local names = {}
    for _, d in ipairs(list) do names[#names + 1] = ns.FarmList:DifficultyName(d) end
    return table.concat(names, ", ")
end

-- mountID -> { jid, ready = {difficulty...} } for mounts farmable right now
-- (visible instances only, same rule as the Farmable now list and Home).
local function farmableMap(entries)
    local map = {}
    for _, e in ipairs(entries or {}) do
        if e.readyCount > 0 and not e.hidden then
            for id, m in pairs(e.mounts) do
                if #m.ready > 0 and not map[id] then map[id] = { jid = e.jid, ready = m.ready } end
            end
        end
    end
    return map
end

-- Tooltip ---------------------------------------------------------------------
local function showTooltip(row)
    local m = row.mount
    if not m then return end
    local C = ns.UI.COLORS
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(m.name, 1, 1, 1)
    if row.farm then
        GameTooltip:AddLine(L["COL_TIP_FARMABLE"]:format(ns.FarmList:InstanceName(row.farm.jid), diffList(row.farm.ready)),
            C.success[1], C.success[2], C.success[3], true)
    end
    local extra = ns.MountJournal:GetMountExtra(m.mountID)
    if extra and extra.sourceText and extra.sourceText ~= "" then
        GameTooltip:AddLine(extra.sourceText, 1, 1, 1, true)
    end
    GameTooltip:AddLine(L["TIP_CLICK_PREVIEW"], C.accent[1], C.accent[2], C.accent[3])
    GameTooltip:Show()
end

-- Rows ------------------------------------------------------------------------
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
    r.icon:SetSize(20, 20)
    r.icon:SetPoint("LEFT", 4, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    r.status = ns.UI.fs(r, "GameFontHighlightSmall")
    r.status:SetPoint("RIGHT", -8, 0)
    r.status:SetWidth(78)
    r.status:SetJustifyH("RIGHT")
    r.dot = ns.UI.Circle(r, "ARTWORK", 8, { 1, 1, 1 })
    r.dot:SetPoint("RIGHT", r.status, "LEFT", -4, 0)

    r.source = ns.UI.fs(r, "GameFontHighlightSmall", ns.UI.COLORS.muted)
    r.source:SetPoint("RIGHT", r.dot, "LEFT", -14, 0)
    r.source:SetWidth(110)
    r.source:SetWordWrap(false)

    r.fav = ns.UI.FavStar(r, 14)
    r.fav:SetPoint("RIGHT", r.source, "LEFT", -8, 0)

    r.name = ns.UI.fs(r, "GameFontHighlight")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.name:SetPoint("RIGHT", r.fav, "LEFT", -6, 0)
    r.name:SetWordWrap(false)

    -- Achievement view only: thin progress bar under the name.
    r.ptrack = r:CreateTexture(nil, "ARTWORK")
    r.ptrack:SetPoint("BOTTOMLEFT", r.name, "BOTTOMLEFT", 0, -5)
    r.ptrack:SetSize(120, 2)
    r.ptrack:SetColorTexture(1, 1, 1, 0.1)
    r.pfill = r:CreateTexture(nil, "ARTWORK", nil, 1)
    r.pfill:SetPoint("TOPLEFT", r.ptrack)
    r.pfill:SetHeight(2)

    r:SetScript("OnEnter", function(self)
        if self.ach then
            -- Blizzard's achievement tooltip lists every criterion with progress.
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local link = ns.Achievements:Link(self.ach.id)
            if link then GameTooltip:SetHyperlink(link) else GameTooltip:AddLine(self.ach.name, 1, 1, 1) end
            local C = ns.UI.COLORS
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["COL_ACH_TIP"], C.accent[1], C.accent[2], C.accent[3])
            GameTooltip:Show()
        else
            showTooltip(self)
        end
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self, button)
        if self.ach then
            -- Click: mount detail with the 3D model (it lists the achievement
            -- too); right-click: straight to the Achievements window.
            if button ~= "RightButton" then
                ns.MountPreview:Toggle(self.ach.mountID)
            elseif not ns.Achievements:Open(self.ach.id) then
                ns:Print(L["JOURNAL_COMBAT"])
            end
        elseif self.mount then
            ns.MountPreview:Toggle(self.mount.mountID)
        end
    end)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    return r
end

local function fillAchRow(r, a, index)
    local C = ns.UI.COLORS
    local m = a.mount
    r.mount, r.farm, r.ach = nil, nil, a
    r.fav:SetMount(m.mountID)
    r.zebra:SetShown(index % 2 == 1)
    r.icon:SetTexture(m.icon or a.icon or 134400)
    r.icon:SetDesaturated(not m.isCollected)
    r.icon:SetAlpha(m.isCollected and 1 or 0.7)
    r.name:SetText(a.name)
    r.name:SetTextColor(1, 1, 1, m.isCollected and 1 or 0.85)
    r.source:SetText(m.name)
    local pct = a.total > 0 and a.done / a.total or 0
    local color, text
    if m.isCollected then
        color, text = C.accent, L["STATUS_COLLECTED"]
    elseif a.completed then
        color, text = C.success, L["COL_ACH_DONE"]
    else
        color, text = C.warning or C.dim, ("%d / %d"):format(a.done, a.total)
    end
    r.status:SetText(text)
    r.status:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    r.dot:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    r.ptrack:Show()
    r.pfill:SetShown(pct > 0)
    r.pfill:SetWidth(math.max(1, 120 * pct))
    r.pfill:SetColorTexture(color[1], color[2], color[3], 0.9)
end

local function fillRow(r, m, index, farm, sourceText)
    local C = ns.UI.COLORS
    r.mount, r.farm, r.ach = m, farm, nil
    r.fav:SetMount(m.mountID)
    r.ptrack:Hide()
    r.pfill:Hide()
    -- "Other drops" shows who and where instead of the source type.
    r.source:SetWidth(sourceText and 210 or 110)
    r.zebra:SetShown(index % 2 == 1)
    r.icon:SetTexture(m.icon or 134400) -- 134400 = question-mark icon
    r.icon:SetDesaturated(not m.isCollected)
    r.icon:SetAlpha(m.isCollected and 1 or 0.7)
    r.name:SetText(m.name)
    r.name:SetTextColor(1, 1, 1, m.isCollected and 1 or 0.78)
    r.source:SetText(sourceText or ns.MountJournal:GetSourceTypeLabel(m.sourceType))
    -- Green = farmable now (same meaning as in Farmable now), purple = collected.
    local color, text
    if m.isCollected then
        color, text = C.accent, L["STATUS_COLLECTED"]
    elseif farm then
        color, text = C.success, L["STATUS_FARMABLE"]
    else
        color, text = C.muted, L["STATUS_MISSING"]
    end
    r.status:SetText(text)
    r.status:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    r.dot:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
end

-- Draws the rows for the current scroll offset.
local function render(p)
    local items = p.items or {}
    local offset = p.scroll:GetVerticalScroll()
    local first = math.floor(offset / ROW_H) + 1
    for i, r in ipairs(p.rows) do
        local index = first + i - 1
        local m = items[index]
        if m then
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_H)
            r:SetPoint("RIGHT", p.child, "RIGHT", -4, 0)
            if p.mode == "ach" then
                fillAchRow(r, m, index)
            elseif p.mode == "drops" then
                fillRow(r, m.mount, index, nil, m.label)
            else
                fillRow(r, m, index, p.farm and p.farm[m.mountID])
            end
            r:Show()
        else
            r.mount, r.ach = nil, nil
            r:Hide()
        end
    end
end

-- Create ----------------------------------------------------------------------
function CollectionPanel:Create(parent)
    local C = ns.UI.COLORS
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()
    p.query = ""

    -- View switch (List / By expansion), top right. Everything that belongs
    -- to the list lives in p.listView so a view change is one Show/Hide.
    p.view = ns.UI.Segmented(p, {
        { key = "list", text = L["COL_VIEW_LIST"] },
        { key = "exp",  text = L["COL_VIEW_EXP"] },
        { key = "ach",  text = L["COL_VIEW_ACH"] },
        { key = "drops", text = L["COL_VIEW_DROPS"] },
    }, function(key)
        if p.bar then p.bar:SetValue(0) end
        ns.Storage.db.ui.collectionView = key
        CollectionPanel:Refresh(p)
    end)
    p.view:SetPoint("TOPRIGHT", -SCROLL_W, 0)

    local lv = CreateFrame("Frame", nil, p)
    lv:SetAllPoints()
    p.listView = lv

    p.search = ns.UI.SearchBox(lv, L["COL_SEARCH_HINT"], function(text)
        p.query = strtrim(text):lower()
        if p.bar then p.bar:SetValue(0) end
        CollectionPanel:Refresh(p)
    end)
    p.search:SetPoint("TOPLEFT", 0, 0)
    p.search:SetPoint("RIGHT", p.view, "LEFT", -8, 0)

    local items = {}
    for _, f in ipairs(FILTERS) do
        items[#items + 1] = { key = f.key, text = f.key == "favorites" and ns.UI.STAR or L[f.text] }
    end
    p.filter = ns.UI.Segmented(lv, items, function(key)
        ns.Storage.db.ui.collectionFilter = key
        if p.bar then p.bar:SetValue(0) end
        CollectionPanel:Refresh(p)
    end)
    p.filter:SetPoint("TOPLEFT", 0, -(SEARCH_H + 8))

    p.source = ns.UI.Dropdown(lv, 170, function(value)
        -- Same menu, two meanings: source type (list) or category (achievements).
        local field = (p.mode == "ach") and "collectionAchCategory"
            or (p.mode == "drops") and "collectionDropsContinent" or "collectionSource"
        ns.Storage.db.ui[field] = (value ~= "all") and value or nil
        if p.bar then p.bar:SetValue(0) end
        CollectionPanel:Refresh(p)
    end)
    p.source:SetPoint("LEFT", p.filter, "RIGHT", 8, 0)

    p.count = ns.UI.fs(lv, "small", C.muted)
    p.count:SetPoint("RIGHT", p, "TOPRIGHT", -SCROLL_W - 2, -(SEARCH_H + 8 + TOOLBAR_H / 2))
    p.count:SetJustifyH("RIGHT")

    -- Expansion chip (set by clicking a tile in "By expansion"); X clears it.
    p.chip = ns.UI.Button(lv, "primary")
    p.chip:SetHeight(22)
    p.chip:SetPoint("RIGHT", p, "TOPRIGHT", -SCROLL_W, -(SEARCH_H + 8 + TOOLBAR_H / 2))
    p.chip:GetFontString():ClearAllPoints()
    p.chip:GetFontString():SetPoint("LEFT", 10, 0)
    local chipX = ns.UI.CloseButton(p.chip)
    chipX:SetSize(18, 18)
    chipX:SetPoint("RIGHT", -2, 0)
    local function clearTier()
        p.tierFilter = nil
        CollectionPanel:Refresh(p)
    end
    chipX:SetScript("OnClick", clearTier)
    p.chip:SetScript("OnClick", clearTier)
    p.chip:Hide()

    -- Note shown instead of the toolbar in the expansion view.
    p.expNote = ns.UI.fs(p, "tiny", C.dim) -- two short lines fit above the progress line
    p.expNote:SetPoint("TOPLEFT", 2, -(SEARCH_H + 6))
    p.expNote:SetPoint("RIGHT", -SCROLL_W, 0)
    p.expNote:SetWordWrap(true)

    -- Progress: "86 / 1,183 collected · 7.3 %" and a thin bar
    local top = -(SEARCH_H + 8 + TOOLBAR_H + 8)
    p.progressText = ns.UI.fs(p, "small", C.dim)
    p.progressText:SetPoint("TOPLEFT", 2, top)
    local track = p:CreateTexture(nil, "ARTWORK")
    track:SetPoint("TOPLEFT", 0, top - 18)
    track:SetPoint("TOPRIGHT", -SCROLL_W, top - 18)
    track:SetHeight(4)
    track:SetColorTexture(1, 1, 1, 0.08)
    p.progressFill = p:CreateTexture(nil, "ARTWORK", nil, 1)
    p.progressFill:SetPoint("TOPLEFT", track)
    p.progressFill:SetPoint("BOTTOMLEFT", track)
    p.progressFill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.9)
    p.progressTrack = track

    local scroll = CreateFrame("ScrollFrame", nil, lv)
    scroll:SetPoint("TOPLEFT", 0, -LIST_TOP)
    scroll:SetPoint("BOTTOMRIGHT", -SCROLL_W, 0)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(ns.UI.CONTENT_WIDTH - SCROLL_W, 1)
    scroll:SetScrollChild(child)
    p.scroll, p.child = scroll, child
    p.bar = ns.UI.ThinScrollBar(scroll)
    scroll:SetScript("OnVerticalScroll", function() render(p) end)

    -- Enough rows to cover the visible area plus one partly shown.
    p.rows = {}
    local visible = math.ceil((ns.UI.HEIGHT - LIST_TOP) / ROW_H) + 1
    for i = 1, visible do p.rows[i] = newRow(p) end

    p.empty = ns.UI.fs(child, "GameFontHighlightSmall", C.muted)
    p.empty:SetPoint("TOPLEFT", 4, -6)
    p.empty:SetPoint("RIGHT", -4, 0)
    p.empty:SetWordWrap(true)

    -- Expansion view: a grid of tiles under the progress line.
    p.expView = CreateFrame("Frame", nil, p)
    p.expView:SetPoint("TOPLEFT", 0, -LIST_TOP)
    p.expView:SetPoint("BOTTOMRIGHT", -SCROLL_W, 0)
    p.tiles = {}
    return p
end

-- Expansion tiles ---------------------------------------------------------------
local TILE_COLS, TILE_GAP = 4, 8

local function showTileTooltip(tile)
    local t = tile.info
    if not t then return end
    local C = ns.UI.COLORS
    local farm = tile.panel.farm or {}
    GameTooltip:SetOwner(tile, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ns.FarmList:TierName(t.tier), 1, 1, 1)
    for _, id in ipairs(t.mounts) do
        local m = ns.MountJournal:GetMount(id)
        local name = m and m.name or ("#" .. id)
        local c = (m and m.isCollected) and C.accent or (farm[id] and C.success) or C.tipMuted
        GameTooltip:AddLine(name, c[1], c[2], c[3])
    end
    GameTooltip:AddLine(L["COL_TIP_TILE_CLICK"], C.accent[1], C.accent[2], C.accent[3])
    GameTooltip:Show()
end

local function newTile(p)
    local C = ns.UI.COLORS
    local t = CreateFrame("Button", nil, p.expView, "BackdropTemplate")
    ns.UI.StylePanel(t, nil, { noSheen = true })
    t.panel = p
    t.art = ns.UI.ArtTexture(t, "BACKGROUND", 1)
    t.art:SetPoint("TOPLEFT", 1, -1)
    t.art:SetPoint("BOTTOMRIGHT", -1, 1)
    t.art:SetAlpha(0.45)
    local shade = t:CreateTexture(nil, "BACKGROUND", nil, 2)
    shade:SetAllPoints(t.art)
    shade:SetColorTexture(1, 1, 1, 1)
    local s = C.surface
    shade:SetGradient("VERTICAL", CreateColor(s[1], s[2], s[3], 0.95), CreateColor(s[1], s[2], s[3], 0.2))
    local hl = t:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(t.art)
    hl:SetColorTexture(1, 1, 1, 0.06)

    t.name = ns.UI.fs(t, "title")
    t.name:SetPoint("TOPLEFT", 9, -8)
    t.name:SetPoint("RIGHT", -8, 0)
    t.name:SetWordWrap(false)
    ns.UI.Shadow(t.name)

    t.value = ns.UI.fs(t, "large")
    t.value:SetPoint("BOTTOMLEFT", 9, 22)
    ns.UI.Shadow(t.value)
    t.farm = ns.UI.fs(t, "tiny", C.success)
    t.farm:SetPoint("BOTTOMRIGHT", -9, 24)
    t.farm:SetJustifyH("RIGHT")
    ns.UI.Shadow(t.farm)

    local track = t:CreateTexture(nil, "ARTWORK")
    track:SetPoint("BOTTOMLEFT", 9, 12)
    track:SetPoint("BOTTOMRIGHT", -9, 12)
    track:SetHeight(4)
    track:SetColorTexture(1, 1, 1, 0.12)
    t.fill = t:CreateTexture(nil, "ARTWORK", nil, 1)
    t.fill:SetPoint("TOPLEFT", track)
    t.fill:SetPoint("BOTTOMLEFT", track)
    t.fill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.95)

    t:SetScript("OnEnter", showTileTooltip)
    t:SetScript("OnLeave", function() GameTooltip:Hide() end)
    t:SetScript("OnClick", function(self)
        -- Show this expansion's mounts in the list view.
        p.tierFilter = self.info and self.info.tier
        ns.Storage.db.ui.collectionView = "list"
        if p.bar then p.bar:SetValue(0) end
        CollectionPanel:Refresh(p)
    end)
    return t
end

local function renderTiles(p)
    local data = ns.Collection:ByExpansion()
    p.expData = data
    -- "66 of 1,183 mounts": say up front how much of the collection this covers.
    local covered = 0
    for _, t in ipairs(data) do covered = covered + #t.mounts end
    local s = ns.Collection.summary
    p.expNote:SetFormattedText(L["COL_EXP_NOTE"], fmt(covered), fmt(s and s.visibleTotal or 0))
    local n = #data
    local rows = math.max(1, math.ceil(n / TILE_COLS))
    local areaW = ns.UI.CONTENT_WIDTH - SCROLL_W
    local areaH = ns.UI.HEIGHT - 40 - 20 - LIST_TOP -- window minus header and paddings
    local w = (areaW - (TILE_COLS - 1) * TILE_GAP) / TILE_COLS
    local h = math.min(110, (areaH - (rows - 1) * TILE_GAP) / rows)
    local farm = p.farm or {}
    for i, info in ipairs(data) do
        local t = p.tiles[i] or newTile(p)
        p.tiles[i] = t
        t.info = info
        local col, row = (i - 1) % TILE_COLS, math.floor((i - 1) / TILE_COLS)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", col * (w + TILE_GAP), -row * (h + TILE_GAP))
        t:SetSize(w, h)
        t.name:SetText(ns.FarmList:TierName(info.tier))
        t.value:SetFormattedText("%d / %d", info.collected, #info.mounts)
        local pct = #info.mounts > 0 and info.collected / #info.mounts or 0
        t.fill:SetWidth(math.max(1, (w - 18) * pct))
        local nFarm = 0
        for _, id in ipairs(info.mounts) do
            if farm[id] then nFarm = nFarm + 1 end
        end
        t.farm:SetText(nFarm > 0 and L["COL_TILE_FARMABLE"]:format(nFarm) or "")
        local art = info.artJid and ns.FarmList:InstanceArt(info.artJid)
        t.art:SetTexture(art)
        t.art:SetShown(art ~= nil)
        ns.UI.SetArtCrop(t.art, w - 2, h - 2)
        t:Show()
    end
    for i = n + 1, #p.tiles do p.tiles[i]:Hide() end
end

-- Achievements view -------------------------------------------------------------
-- Same list, search and All / Missing / Collected filter (by the mount);
-- the dropdown filters by achievement category instead of source.
local function refreshAchievements(p, key)
    local C = ns.UI.COLORS
    local all = ns.Collection:Achievements()
    p.chip:Hide()

    local cat = ns.Storage.db.ui.collectionAchCategory
    local menu = { { value = "all", text = L["COL_ACH_CAT_ALL"] } }
    local missingBy, names, order = {}, {}, {}
    for _, a in ipairs(all or {}) do
        if not names[a.top] then names[a.top] = a.topName; order[#order + 1] = a.top end
        if not a.mount.isCollected then missingBy[a.top] = (missingBy[a.top] or 0) + 1 end
    end
    table.sort(order, function(x, y)
        local mx, my = missingBy[x] or 0, missingBy[y] or 0
        if mx ~= my then return mx > my end
        return names[x] < names[y]
    end)
    for _, top in ipairs(order) do
        menu[#menu + 1] = { value = top, text = L["COL_SOURCE_ITEM"]:format(names[top], fmt(missingBy[top] or 0)) }
    end
    p.source:SetItems(menu)
    if cat and not names[cat] then cat = nil end
    p.source:SetText(L["COL_ACH_CAT_LABEL"]:format(cat and names[cat] or L["COL_SOURCE_ANY"]))

    local items, q = {}, p.query or ""
    local done, collected = 0, 0
    for _, a in ipairs(all or {}) do
        if a.completed then done = done + 1 end
        if a.mount.isCollected then collected = collected + 1 end
        local owned = a.mount.isCollected
        local keep = (key == "all") or (key == "missing" and not owned) or (key == "collected" and owned)
            or (key == "favorites" and ns.Collection:IsFavorite(a.mount.mountID))
        if keep and cat then keep = a.top == cat end
        if keep and q ~= "" then
            keep = a.name:lower():find(q, 1, true) ~= nil or a.mount.name:lower():find(q, 1, true) ~= nil
        end
        if keep then items[#items + 1] = a end
    end

    local total = all and #all or 0
    if total > 0 then
        p.progressText:SetFormattedText(L["COL_ACH_PROGRESS"], collected, total, done)
        p.progressFill:SetWidth(math.max(1, (ns.UI.CONTENT_WIDTH - SCROLL_W) * collected / total))
        p.progressFill:Show()
    else
        p.progressText:SetText(all and L["COL_ACH_NONE"] or L["JOURNAL_NOT_READY_SHORT"])
        p.progressFill:Hide()
    end

    p.items = items
    p.count:SetText(L["COL_COUNT"]:format(fmt(#items)))
    p.count:Show()
    p.empty:SetShown(#items == 0)
    if #items == 0 then p.empty:SetText(all and L["COL_NONE"] or L["JOURNAL_NOT_READY_SHORT"]) end
    p.child:SetHeight(math.max(#items * ROW_H, 1))
    p.scroll:UpdateScrollChildRect()
    render(p)
end

-- Other drops view ------------------------------------------------------------
-- Drop mounts with no dataset source (rares, trash, world drops): who and
-- where, as the Mount Journal says. Dropdown = continent of the zone.
local function refreshDrops(p, key)
    local all = ns.Collection:OtherDrops()
    p.chip:Hide()

    local cont = ns.Storage.db.ui.collectionDropsContinent
    local missingBy, present = {}, {}
    for _, e in ipairs(all or {}) do
        local first = e.drops[1]
        e.continent = first and first.zone and first.zone.continent or 0
        present[e.continent] = true
        if not e.mount.isCollected then missingBy[e.continent] = (missingBy[e.continent] or 0) + 1 end
        if first then
            e.label = first.zone and ("%s · %s"):format(first.who, first.zone.name) or first.who
            if #e.drops > 1 then e.label = e.label .. " +" .. (#e.drops - 1) end
        else
            e.label = L["COL_DROPS_UNKNOWN"]
        end
    end
    local function contName(c)
        if c == 0 then return L["COL_DROPS_NO_ZONE"] end
        local info = C_Map.GetMapInfo(c)
        return info and info.name or ("#" .. c)
    end
    local order = {}
    for c in pairs(present) do order[#order + 1] = c end
    table.sort(order, function(a, b)
        local ma, mb = missingBy[a] or 0, missingBy[b] or 0
        if ma ~= mb then return ma > mb end
        return a < b
    end)
    local menu = { { value = "all", text = L["COL_DROPS_ALL"] } }
    for _, c in ipairs(order) do
        menu[#menu + 1] = { value = c, text = L["COL_SOURCE_ITEM"]:format(contName(c), fmt(missingBy[c] or 0)) }
    end
    p.source:SetItems(menu)
    if cont and not present[cont] then cont = nil end
    p.source:SetText(L["COL_DROPS_LABEL"]:format(cont and contName(cont) or L["COL_SOURCE_ANY"]))

    local items, q, collected = {}, p.query or "", 0
    for _, e in ipairs(all or {}) do
        local owned = e.mount.isCollected
        if owned then collected = collected + 1 end
        local keep = (key == "all") or (key == "missing" and not owned) or (key == "collected" and owned)
            or (key == "favorites" and ns.Collection:IsFavorite(e.mount.mountID))
        if keep and cont then keep = e.continent == cont end
        if keep and q ~= "" then
            keep = e.mount.name:lower():find(q, 1, true) ~= nil or e.label:lower():find(q, 1, true) ~= nil
        end
        if keep then items[#items + 1] = e end
    end

    local total = all and #all or 0
    if total > 0 then
        p.progressText:SetFormattedText(L["COL_DROPS_PROGRESS"], collected, total)
        p.progressFill:SetWidth(math.max(1, (ns.UI.CONTENT_WIDTH - SCROLL_W) * collected / total))
        p.progressFill:Show()
    else
        p.progressText:SetText(all and L["COL_NONE"] or L["JOURNAL_NOT_READY_SHORT"])
        p.progressFill:Hide()
    end

    p.items = items
    p.count:SetText(L["COL_COUNT"]:format(fmt(#items)))
    p.count:Show()
    p.empty:SetShown(#items == 0)
    if #items == 0 then p.empty:SetText(all and L["COL_NONE"] or L["JOURNAL_NOT_READY_SHORT"]) end
    p.child:SetHeight(math.max(#items * ROW_H, 1))
    p.scroll:UpdateScrollChildRect()
    render(p)
end

-- Refresh ---------------------------------------------------------------------
--- entries (optional) = FarmList:Build() result, for the "Farmable" mark;
--- internal refreshes (search, filters) reuse the last one.
function CollectionPanel:Refresh(p, entries)
    if entries then p.farm = farmableMap(entries) end
    local list = ns.Collection:GetList()

    local view = ns.Storage.db.ui.collectionView or "list"
    p.mode = view
    p.view:SetSelected(view)
    p.listView:SetShown(view == "list" or view == "ach" or view == "drops")
    p.expView:SetShown(view == "exp")
    p.expNote:SetShown(view == "exp")

    local key = filterKey()
    p.filter:SetSelected(key)

    if view == "ach" then
        refreshAchievements(p, key)
        return
    end
    if view == "drops" then
        refreshDrops(p, key)
        return
    end

    -- Source menu: "All sources" + every source with how many are missing.
    local src = sourceKey()
    local menu = { { value = "all", text = L["COL_SOURCE_ALL"] } }
    local missingBy = {}
    local present = {}
    for _, m in ipairs(list or {}) do
        local st = m.sourceType or 0
        present[st] = true
        if not m.isCollected then missingBy[st] = (missingBy[st] or 0) + 1 end
    end
    local sources = {}
    for st in pairs(present) do sources[#sources + 1] = st end
    table.sort(sources, function(a, b)
        local ma, mb = missingBy[a] or 0, missingBy[b] or 0
        if ma ~= mb then return ma > mb end
        return a < b
    end)
    for _, st in ipairs(sources) do
        menu[#menu + 1] = { value = st, text = L["COL_SOURCE_ITEM"]:format(
            ns.MountJournal:GetSourceTypeLabel(st), fmt(missingBy[st] or 0)) }
    end
    p.source:SetItems(menu)
    if src and not present[src] then src = nil end
    p.source:SetText(L["COL_SOURCE_LABEL"]:format(src and ns.MountJournal:GetSourceTypeLabel(src) or L["COL_SOURCE_ANY"]))

    local s = ns.Collection.summary
    if s and s.visibleTotal > 0 then
        local pct = s.collectedVisible / s.visibleTotal
        p.progressText:SetFormattedText(L["COL_PROGRESS"], fmt(s.collectedVisible), fmt(s.visibleTotal), pct * 100)
        -- Known width: GetWidth() is 0 before the first layout pass.
        p.progressFill:SetWidth(math.max(1, (ns.UI.CONTENT_WIDTH - SCROLL_W) * pct))
        p.progressFill:Show()
    else
        p.progressText:SetText(L["JOURNAL_NOT_READY_SHORT"])
        p.progressFill:Hide()
    end

    if view == "exp" then
        renderTiles(p)
        return
    end

    -- Expansion filter from a tile click
    local tierSet
    if p.tierFilter then
        for _, t in ipairs(p.expData or ns.Collection:ByExpansion()) do
            if t.tier == p.tierFilter then tierSet = t.set end
        end
        if not tierSet then p.tierFilter = nil end
    end

    local items = {}
    local q = p.query or ""
    for _, m in ipairs(list or {}) do
        local keep = (key == "all") or (key == "missing" and not m.isCollected)
            or (key == "collected" and m.isCollected)
            or (key == "favorites" and ns.Collection:IsFavorite(m.mountID))
        if keep and src then keep = (m.sourceType or 0) == src end
        if keep and tierSet then keep = tierSet[m.mountID] == true end
        if keep and q ~= "" then keep = m.name:lower():find(q, 1, true) ~= nil end
        if keep then items[#items + 1] = m end
    end
    p.items = items
    p.count:SetText(L["COL_COUNT"]:format(fmt(#items)))
    p.count:SetShown(tierSet == nil)
    p.chip:SetShown(tierSet ~= nil)
    if tierSet then
        p.chip:SetText(L["COL_CHIP"]:format(ns.FarmList:TierName(p.tierFilter), #items))
        p.chip:SetWidth(p.chip:GetFontString():GetStringWidth() + 36)
    end

    p.empty:SetShown(#items == 0)
    if #items == 0 then
        p.empty:SetText(list and L["COL_NONE"] or L["JOURNAL_NOT_READY_SHORT"])
    end
    p.child:SetHeight(math.max(#items * ROW_H, 1))
    p.scroll:UpdateScrollChildRect()
    render(p)
end
