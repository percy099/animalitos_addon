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
}

local function fmt(n)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

local function filterKey()
    local ui = ns.Storage.db.ui
    return ui.collectionFilter or "all"
end

-- Tooltip ---------------------------------------------------------------------
local function showTooltip(row)
    local m = row.mount
    if not m then return end
    local C = ns.UI.COLORS
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(m.name, 1, 1, 1)
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

    r.name = ns.UI.fs(r, "GameFontHighlight")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.name:SetPoint("RIGHT", r.source, "LEFT", -8, 0)
    r.name:SetWordWrap(false)

    r:SetScript("OnEnter", showTooltip)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self)
        if self.mount then ns.MountPreview:Toggle(self.mount.mountID) end
    end)
    return r
end

local function fillRow(r, m, index)
    local C = ns.UI.COLORS
    r.mount = m
    r.zebra:SetShown(index % 2 == 1)
    r.icon:SetTexture(m.icon or 134400) -- 134400 = question-mark icon
    r.icon:SetDesaturated(not m.isCollected)
    r.icon:SetAlpha(m.isCollected and 1 or 0.7)
    r.name:SetText(m.name)
    r.name:SetTextColor(1, 1, 1, m.isCollected and 1 or 0.78)
    r.source:SetText(ns.MountJournal:GetSourceTypeLabel(m.sourceType))
    local color = m.isCollected and C.success or C.muted
    r.status:SetText(m.isCollected and L["STATUS_COLLECTED"] or L["STATUS_MISSING"])
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
            fillRow(r, m, index)
            r:Show()
        else
            r.mount = nil
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

    p.search = ns.UI.SearchBox(p, L["COL_SEARCH_HINT"], function(text)
        p.query = strtrim(text):lower()
        if p.bar then p.bar:SetValue(0) end
        CollectionPanel:Refresh(p)
    end)
    p.search:SetPoint("TOPLEFT", 0, 0)
    p.search:SetPoint("TOPRIGHT", -SCROLL_W, 0)

    local items = {}
    for _, f in ipairs(FILTERS) do items[#items + 1] = { key = f.key, text = L[f.text] } end
    p.filter = ns.UI.Segmented(p, items, function(key)
        ns.Storage.db.ui.collectionFilter = key
        if p.bar then p.bar:SetValue(0) end
        CollectionPanel:Refresh(p)
    end)
    p.filter:SetPoint("TOPLEFT", 0, -(SEARCH_H + 8))

    p.count = ns.UI.fs(p, "small", C.muted)
    p.count:SetPoint("RIGHT", p, "TOPRIGHT", -SCROLL_W - 2, -(SEARCH_H + 8 + TOOLBAR_H / 2))
    p.count:SetJustifyH("RIGHT")

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

    local scroll = CreateFrame("ScrollFrame", nil, p)
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
    return p
end

-- Refresh ---------------------------------------------------------------------
function CollectionPanel:Refresh(p)
    local list = ns.Collection:GetList()
    local key = filterKey()
    p.filter:SetSelected(key)

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

    local items = {}
    local q = p.query or ""
    for _, m in ipairs(list or {}) do
        local keep = (key == "all") or (key == "missing" and not m.isCollected)
            or (key == "collected" and m.isCollected)
        if keep and q ~= "" then keep = m.name:lower():find(q, 1, true) ~= nil end
        if keep then items[#items + 1] = m end
    end
    p.items = items
    p.count:SetText(L["COL_COUNT"]:format(fmt(#items)))

    p.empty:SetShown(#items == 0)
    if #items == 0 then
        p.empty:SetText(list and L["COL_NONE"] or L["JOURNAL_NOT_READY_SHORT"])
    end
    p.child:SetHeight(math.max(#items * ROW_H, 1))
    p.scroll:UpdateScrollChildRect()
    render(p)
end
