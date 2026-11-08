-- Planner section: the static route from Modules/Planner.lua as a table
-- (Done · # · Step · Boss · Mount · Go), like SimpleArmory's planner.
-- Travel steps have no check box; instance steps tick themselves when the
-- lockout says the bosses are dead, or by hand until the next reset.
local _, ns = ...
local L = ns.L

local PlannerPanel = {}
ns.PlannerPanel = PlannerPanel

local SCROLL_W = 14
local LIST_TOP = 92
local LINE_H = 15
local COL = { done = 6, num = 44, step = 64, boss = 240, mount = 352 } -- x offsets
local GO_W = 40

local function timeLeft(resetAt)
    return resetAt and SecondsToTime(math.max(0, resetAt - time()), true, nil, 2) or "?"
end

local function resetLine(secs)
    if not secs or secs <= 0 then return "?" end
    local t = math.floor((time() + secs + 30) / 60) * 60
    local day, clock = ns.Lockouts:FormatClock(t)
    return ("%s %s"):format(day, clock)
end

-- Step details --------------------------------------------------------------------
-- Rows of { boss, mount, icon, state } and the step's difficulty / note text.
-- World event boss step (Planner:Build `event` = FarmList:Holidays() item).
local function describeEvent(r)
    local ev = r.event
    local S = ns.Eligibility.STATES
    local state = (ev.state == S.READY and "ready") or (ev.state == S.LOCKED_OUT and "locked") or "verify"
    local rows = {}
    for _, id in ipairs(ev.mounts) do
        local mj = ns.MountJournal:GetMount(id)
        rows[#rows + 1] = { id = id, boss = ev.name, mount = mj and mj.name or ("#" .. id),
            icon = mj and mj.icon or 134400, state = state }
    end
    table.sort(rows, function(a, b) return a.mount < b.mount end)
    local note = (state == "locked" and L["PLAN_NOTE_LOCKED"]:format(timeLeft(ev.resetAt)))
        or (state == "verify" and L["EVENT_VERIFY"]) or ""
    return rows, ("%s · %s"):format(ev.event or "", L["EVENT_ONCE_DAY"]), note
end

local function describe(r)
    if r.event then return describeEvent(r) end
    local e, isRaid = r.e, r.inst.isRaid
    local rows, ready, locked, resetAt, verifyReason = {}, {}, {}, nil, nil
    for id, m in pairs(e.mounts) do
        local mj = ns.MountJournal:GetMount(id)
        -- "peer": a mount only someone else in the group route needs.
        local state = (m.peer and "peer") or (#m.ready > 0 and "ready") or (#m.locked > 0 and "locked") or "verify"
        -- One row per boss that drops it (Vault of Archavon: all four).
        for k, src in ipairs(m.sources or { m.source }) do
            rows[#rows + 1] = { id = id, boss = ns.FarmList:BossName(src), mount = mj and mj.name or ("#" .. id),
                icon = mj and mj.icon or 134400, state = state, extra = k > 1, order = ns.FarmList:BossOrder(src) }
        end
        for _, d in ipairs(m.ready) do ready[d] = true end
        for _, d in ipairs(m.locked) do locked[d] = true end
        if m.resetAt then resetAt = math.min(resetAt or m.resetAt, m.resetAt) end
        if m.verify[1] and not verifyReason then verifyReason = m.verify[1].reason end
    end
    -- Boss by boss, in the instance's order (Dragon Soul: Ultraxion, then
    -- the two Madness mounts), then by mount name.
    table.sort(rows, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        if a.mount ~= b.mount then return a.mount < b.mount end
        if a.extra ~= b.extra then return not a.extra end -- the journal's own boss first
        return a.boss < b.boss
    end)

    local diffs = next(ready) and ready or locked
    local list = {}
    for d in pairs(diffs) do list[#list + 1] = d end
    table.sort(list)
    local names = {}
    for _, d in ipairs(list) do names[#names + 1] = ns.FarmList:DifficultyName(d) end

    local notes = {}
    -- Group route: who needs this step (check = can loot it now).
    if r.who and #r.who > 0 then
        local parts = {}
        for _, w in ipairs(r.who) do
            local name = w.me and L["GROUP_YOU"] or w.name
            parts[#parts + 1] = (w.state == "ready") and ("|cff8dd3a8%s|r |A:common-icon-checkmark:11:11|a"):format(name)
                or ("|cffe0a040%s (%s)|r"):format(name, L["GROUP_LOCKED"])
        end
        notes[#notes + 1] = L["GROUP_WHO"]:format(table.concat(parts, "  "))
    end
    if not next(ready) and next(locked) then
        -- Locked: when it resets is the only thing that matters today.
        notes[#notes + 1] = L["PLAN_NOTE_LOCKED"]:format(timeLeft(resetAt))
    elseif isRaid and (diffs[3] or diffs[4] or diffs[5] or diffs[6]) then
        notes[#notes + 1] = L["PLAN_NOTE_SHARED"]
    elseif not isRaid and diffs[2] then
        -- Legacy normal dungeons have no lockout, only the 10 instances/hour cap.
        notes[#notes + 1] = diffs[1] and L["PLAN_NOTE_HEROIC_NORMAL"] or L["PLAN_NOTE_HEROIC"]
    end
    if not next(ready) and not next(locked) and verifyReason then notes[#notes + 1] = verifyReason end
    -- Raid skip to the mount's boss on the difficulty the mounts drop on.
    if next(ready) then
        local skip = ns.Difficulty:SkipNote(r.jid, ns.Difficulty:Pick(e))
        if skip then notes[#notes + 1] = skip end
    end

    local kind = ns.FarmList:TypeName(r.inst)
    local detail = #names > 0 and ("%s · %s"):format(kind, table.concat(names, ", ")) or kind
    return rows, detail, table.concat(notes, " · ")
end
PlannerPanel.Describe = describe -- also used by the mini window

--- "Run Zul'Gurub", "Kill Galleon", "Queue: Coren Direbrew".
function PlannerPanel.StepTitle(s)
    if s.event then return L["PLAN_QUEUE"]:format(s.event.name) end
    return L[s.inst.worldBoss and "PLAN_KILL" or "PLAN_RUN"]:format(ns.FarmList:InstanceName(s.jid))
end

-- Pools ---------------------------------------------------------------------------
local function newStart(p)
    local f = CreateFrame("Frame", nil, p.child)
    f:SetHeight(28)
    local a = ns.UI.COLORS.accent
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(a[1], a[2], a[3], 0.14)
    local bar = f:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("BOTTOMLEFT")
    bar:SetWidth(2)
    bar:SetColorTexture(a[1], a[2], a[3], 1)
    f.text = ns.UI.fs(f, "title")
    f.text:SetPoint("CENTER")
    return f
end

local function newTravel(p)
    -- A "leg of the road": darker band, thin accent bar, icon of the kind
    -- of travel (flight, portal / teleport spell, hearthstone, boat).
    local a = ns.UI.COLORS.accent
    local f = CreateFrame("Frame", nil, p.child)
    f:SetHeight(26)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 0, -1)
    bg:SetPoint("BOTTOMRIGHT", 0, 1)
    bg:SetColorTexture(0, 0, 0, 0.22)
    local bar = f:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT", 0, -1)
    bar:SetPoint("BOTTOMLEFT", 0, 1)
    bar:SetWidth(2)
    bar:SetColorTexture(a[1], a[2], a[3], 0.7)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(18, 18)
    f.icon:SetPoint("LEFT", COL.num - 6, 0)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.text = ns.UI.fs(f, "body", { 0.86, 0.80, 0.98, 1 })
    f.text:SetPoint("LEFT", COL.step, 0)
    f.text:SetPoint("RIGHT", -6, 0)
    f.text:SetWordWrap(false)
    return f
end

local function newCheck(parent)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(16, 16)
    ns.UI.StylePanel(b, { 0, 0, 0, 0.3 }, { noSheen = true, border = { 1, 1, 1, 0.3 } })
    b.mark = b:CreateTexture(nil, "OVERLAY")
    b.mark:SetPoint("CENTER")
    b.mark:SetSize(18, 18)
    ns.UI.Glyph(b.mark, "Interface\\Buttons\\UI-CheckBox-Check", ns.UI.COLORS.accent)
    return b
end

local function newRun(p)
    local C = ns.UI.COLORS
    local f = CreateFrame("Frame", nil, p.child)
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    line:SetColorTexture(1, 1, 1, 0.06)

    f.check = newCheck(f)
    f.check:SetPoint("TOPLEFT", COL.done, -9)
    f.num = ns.UI.fs(f, "small", C.dim)
    f.num:SetPoint("TOPLEFT", COL.num, -10)

    f.go = ns.UI.Button(f, "primary")
    ns.UI.SetButtonText(f.go, L["BTN_GO"], GO_W)
    f.go:SetPoint("TOPRIGHT", -4, -6)

    f.title = ns.UI.fs(f, "title")
    f.title:SetPoint("TOPLEFT", COL.step, -8)
    f.title:SetWidth(COL.boss - COL.step - 8)
    f.title:SetWordWrap(false)
    f.detail = ns.UI.fs(f, "small", C.muted)
    f.detail:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -2)
    f.detail:SetWidth(COL.boss - COL.step - 8)
    f.detail:SetWordWrap(false)
    f.note = ns.UI.fs(f, "tiny", C.dim)
    f.note:SetPoint("TOPLEFT", f.detail, "BOTTOMLEFT", 0, -2)
    f.note:SetWidth(COL.boss - COL.step - 8)
    f.note:SetWordWrap(true)
    -- Mount achievements with criteria in this instance (hover for the list).
    f.ach = ns.UI.fs(f, "tiny", C.warning or C.dim)
    f.ach:SetPoint("TOPLEFT", f.note, "BOTTOMLEFT", 0, -2)
    f.ach:SetWidth(COL.boss - COL.step - 8)
    f.ach:SetWordWrap(true)
    -- The achievement line is a link: icon, accent color, brighter on hover,
    -- click opens the achievement in Blizzard's window.
    f.achBtn = CreateFrame("Button", nil, f)
    f.achBtn:SetPoint("TOPLEFT", f.ach, "TOPLEFT", -3, 2)
    f.achBtn:SetPoint("BOTTOMRIGHT", f.ach, "BOTTOMRIGHT", 3, -2)
    ns.UI.Clickable(f.achBtn)
    f.achBtn:SetScript("OnClick", function()
        local link = f.achLinks and f.achLinks[1]
        if link and link.ach.id and not ns.Achievements:Open(link.ach.id) then ns:Print(L["JOURNAL_COMBAT"]) end
    end)
    f.achBtn:SetScript("OnEnter", function() f:GetScript("OnEnter")(f, true) end)
    f.achBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self, fromLink)
        if not self.achLinks then return end
        local C2 = ns.UI.COLORS
        GameTooltip:SetOwner(fromLink and self.achBtn or self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["PLAN_ACH_TIP_TITLE"], 1, 1, 1)
        for _, link in ipairs(self.achLinks) do
            local a = link.ach
            GameTooltip:AddLine(("|T%s:14:14:0:0|t %s  (%s)"):format(a.icon or 134400, a.name, a.mount.name),
                C2.warning[1], C2.warning[2], C2.warning[3])
            for _, text in ipairs(link.missing) do
                GameTooltip:AddLine("   · " .. text, 0.85, 0.85, 0.85, true)
            end
        end
        GameTooltip:AddLine(L["PLAN_ACH_TIP_NOTE"], C2.tipMuted[1], C2.tipMuted[2], C2.tipMuted[3], true)
        GameTooltip:AddLine(L["PLAN_ACH_CLICK"], C2.accent[1], C2.accent[2], C2.accent[3])
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- One single-line font string per boss / mount (a non-wrapping font
    -- string only shows its first line, so "\n" lists were cut to one).
    f.bossLines, f.mountLines = {}, {}
    return f
end

local function lineAt(f, list, i, x, width, color)
    local fsx = list[i]
    if not fsx then
        fsx = ns.UI.fs(f, "small", color)
        fsx:SetWidth(width)
        fsx:SetWordWrap(false)
        list[i] = fsx
    end
    fsx:ClearAllPoints()
    fsx:SetPoint("TOPLEFT", x, -9 - (i - 1) * LINE_H)
    fsx:Show()
    return fsx
end

-- Mount lines are buttons: click shows the mount detail with its 3D model.
local function mountLineAt(f, i, x, width)
    local b = f.mountLines[i]
    if not b then
        b = CreateFrame("Button", nil, f)
        b:SetSize(width, LINE_H)
        b.text = ns.UI.fs(b, "small")
        b.text:SetAllPoints()
        b.text:SetWordWrap(false)
        b:SetScript("OnEnter", function(self)
            self.text:SetAlpha(0.75)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["PLAN_MOUNT_TIP"], 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self)
            self.text:SetAlpha(1)
            GameTooltip:Hide()
        end)
        b:SetScript("OnClick", function(self)
            if self.mountID then ns.MountPreview:Toggle(self.mountID) end
        end)
        f.mountLines[i] = b
    end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", x, -9 - (i - 1) * LINE_H)
    b:Show()
    return b
end

local BOSS_W = COL.mount - COL.boss - 8
-- UI.CONTENT_WIDTH is set by MainFrame.lua, which loads after this file.
local function mountWidth() return ns.UI.CONTENT_WIDTH - SCROLL_W - COL.mount - GO_W - 14 end

local FACTORIES = { start = newStart, travel = newTravel, run = newRun }

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

-- Create --------------------------------------------------------------------------
function PlannerPanel:Create(parent)
    local C = ns.UI.COLORS
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()

    p.resets = ns.UI.fs(p, "small", C.dim)
    p.resets:SetPoint("TOPLEFT", 2, -2)

    -- One button: clears the manual check marks (they also expire on their
    -- own at the daily / weekly reset; game lockouts are not touched).
    local clear = ns.UI.Button(p, "secondary")
    ns.UI.SetButtonText(clear, L["PLAN_CLEAR_MARKS"], 60)
    clear:SetPoint("TOPLEFT", 0, -24)
    clear:SetScript("OnClick", function()
        ns.Planner:ResetMarks("all")
        PlannerPanel:Refresh(p)
    end)
    clear:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["PLAN_CLEAR_MARKS"], 1, 1, 1)
        GameTooltip:AddLine(L["PLAN_CLEAR_MARKS_TIP"], nil, nil, nil, true)
        GameTooltip:Show()
    end)
    clear:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Small floating window with the next step (stays open on its own).
    local mini = ns.UI.Button(p, "secondary")
    ns.UI.SetButtonText(mini, L["PLAN_MINI"], 60)
    mini:SetPoint("LEFT", clear, "RIGHT", 6, 0)
    mini:SetScript("OnClick", function() ns.PlannerMini:Toggle() end)
    mini:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["PLAN_MINI"], 1, 1, 1)
        GameTooltip:AddLine(L["PLAN_MINI_TIP"], nil, nil, nil, true)
        GameTooltip:Show()
    end)
    mini:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Which route: full, My route (only the mounts the player picked) or
    -- Group route (only shown when someone else in the group runs the addon).
    p.mode = ns.UI.Segmented(p, { { key = "full", text = L["PLAN_MODE_FULL"] },
        { key = "mine", text = L["PLAN_MODE_MINE"]:format(99) },
        { key = "group", text = L["PLAN_GROUP_ROUTE"] } }, function(key)
        ns.Planner:SetMode(key)
        if p.bar then p.bar:SetValue(0) end
        PlannerPanel:Refresh(p)
    end)
    p.mode:SetPoint("LEFT", mini, "RIGHT", 12, 0)
    p.mode.fullWidth = p.mode:GetWidth()
    p.mode.buttons[3]:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["PLAN_GROUP_ROUTE"], 1, 1, 1)
        GameTooltip:AddLine(L["PLAN_GROUP_ROUTE_TIP"], nil, nil, nil, true)
        GameTooltip:Show()
    end)
    p.mode.buttons[3]:HookScript("OnLeave", function() GameTooltip:Hide() end)
    p.mode.buttons[2]:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["PLAN_MODE_MINE"]:format(ns.Collection:RouteCount()), 1, 1, 1)
        GameTooltip:AddLine(L["PLAN_MODE_MINE_TIP"], nil, nil, nil, true)
        GameTooltip:Show()
    end)
    p.mode.buttons[2]:HookScript("OnLeave", function() GameTooltip:Hide() end)

    p.hide = ns.UI.Switch(p, function(_, checked)
        ns.Storage.db.ui.plannerHideDone = checked or nil
        if p.bar then p.bar:SetValue(0) end
        PlannerPanel:Refresh(p)
        ns.PlannerMini:Refresh() -- its travel follows this switch too
    end)
    p.hide:SetPoint("RIGHT", p, "TOPRIGHT", -SCROLL_W - 2, -35)
    local hideLabel = ns.UI.fs(p, "small", C.dim)
    hideLabel:SetPoint("RIGHT", p.hide, "LEFT", -8, 0)
    hideLabel:SetText(L["PLAN_HIDE_DONE"])


    -- What the route includes: a multi-select dropdown (favorites only,
    -- raids, dungeons, world bosses; at least one kind stays on). The menu
    -- stays open while ticking.
    p.kinds = ns.UI.Dropdown(p, 190, function(key)
        local on = not ns.Planner:Kinds()[key]
        if ns.Planner:SetKind(key, on) then
            if p.bar then p.bar:SetValue(0) end
            PlannerPanel:Refresh(p)
        end
    end)
    p.kinds:SetHeight(22)
    p.kinds:SetPoint("RIGHT", p, "TOPRIGHT", -SCROLL_W - 2, -9)
    p.kinds:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["PLAN_KINDS_TIP"], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    p.kinds:HookScript("OnLeave", function() GameTooltip:Hide() end)

    p.next = ns.UI.Button(p, "primary")
    ns.UI.SetButtonText(p.next, L["PLAN_NEXT"], 96)
    p.next:SetPoint("TOPRIGHT", -SCROLL_W, -56)
    p.next:SetScript("OnClick", function()
        if p.nextJid then ns.Navigation:GoToInstance(p.nextJid) end
    end)

    p.progress = ns.UI.fs(p, "small", C.dim)
    p.progress:SetPoint("TOPLEFT", 2, -58)
    p.progress:SetPoint("RIGHT", p.next, "LEFT", -12, 0)
    p.progress:SetJustifyH("LEFT")
    p.progress:SetWordWrap(false)
    local track = p:CreateTexture(nil, "ARTWORK")
    track:SetPoint("TOPLEFT", 0, -76)
    track:SetPoint("RIGHT", p.next, "LEFT", -12, 0)
    track:SetHeight(4)
    track:SetColorTexture(1, 1, 1, 0.08)
    p.fill = p:CreateTexture(nil, "ARTWORK", nil, 1)
    p.fill:SetPoint("TOPLEFT", track)
    p.fill:SetPoint("BOTTOMLEFT", track)
    p.fill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.9)
    p.trackW = ns.UI.CONTENT_WIDTH - SCROLL_W - 96 - 12

    -- Column header
    local head = CreateFrame("Frame", nil, p)
    head:SetPoint("TOPLEFT", 0, -LIST_TOP + 2)
    head:SetPoint("RIGHT", -SCROLL_W, 0)
    head:SetHeight(18)
    local function col(x, key)
        local t = ns.UI.fs(head, "caps", C.muted)
        t:SetPoint("LEFT", x, 0)
        t:SetText(ns.UI.Upper(L[key]))
    end
    col(COL.done - 2, "PLAN_COL_DONE")
    col(COL.num, "PLAN_COL_NUM")
    col(COL.step, "PLAN_COL_STEP")
    col(COL.boss, "PLAN_COL_BOSS")
    col(COL.mount, "PLAN_COL_MOUNT")
    local hl = head:CreateTexture(nil, "ARTWORK")
    hl:SetPoint("BOTTOMLEFT")
    hl:SetPoint("BOTTOMRIGHT")
    hl:SetHeight(1)
    hl:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.3)

    local scroll = CreateFrame("ScrollFrame", nil, p)
    scroll:SetPoint("TOPLEFT", 0, -(LIST_TOP + 20))
    scroll:SetPoint("BOTTOMRIGHT", -SCROLL_W, 0)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(ns.UI.CONTENT_WIDTH - SCROLL_W, 1)
    scroll:SetScrollChild(child)
    p.scroll, p.child = scroll, child
    p.bar = ns.UI.ThinScrollBar(scroll)

    p.pools, p.used = {}, {}
    for kind in pairs(FACTORIES) do p.pools[kind] = {} end

    -- A mage joining / leaving the group changes the travel steps (not the order).
    ns:On("GROUP_ROSTER_UPDATE", function()
        if p:IsVisible() and p.lastEntries then
            ns:Debounce("planner-roster", 0.5, function() PlannerPanel:Refresh(p) end)
        end
    end)

    p.empty = ns.UI.fs(child, "GameFontHighlightSmall", C.muted)
    p.empty:SetPoint("TOPLEFT", 4, -40)
    p.empty:SetPoint("RIGHT", -4, 0)
    p.empty:SetWordWrap(true)
    return p
end

-- Refresh -------------------------------------------------------------------------
local STATE_HEX = { ready = "|cffffffff", locked = "|cffe0a040", verify = "|cff8c8899", peer = "|cffb8b0c8" }

--- entries = FarmList:Build() result; internal refreshes reuse the last one.
function PlannerPanel:Refresh(p, entries)
    local C = ns.UI.COLORS
    if entries then p.lastEntries = entries end
    entries = p.lastEntries
    releaseAll(p)

    local daily, weekly = ns.Lockouts:GetResetTimes()
    p.resets:SetFormattedText(L["PLAN_RESETS"], resetLine(daily), resetLine(weekly))

    local hideDone = ns.Storage.db.ui.plannerHideDone and true or false
    p.hide:SetChecked(hideDone)
    local anyPeer = #ns.Comm:Peers() > 0
    local groupBtn = p.mode.buttons[3]
    groupBtn:SetShown(anyPeer)
    p.mode:SetWidth(anyPeer and p.mode.fullWidth or (p.mode.fullWidth - groupBtn:GetWidth() - 2))
    local mode = ns.Planner:Mode()
    -- Group route picked earlier but nobody with the addon now: the full route.
    if mode == "group" and not anyPeer then mode = "full" end
    p.mode:SetSelected(mode)
    p.mode.buttons[2].label:SetText(L["PLAN_MODE_MINE"]:format(ns.Collection:RouteCount()))
    local kinds = ns.Planner:Kinds()
    local KIND_KEYS = { { "favorites", "PLAN_KIND_FAV" }, { "raid", "PLAN_KIND_RAID" },
        { "dungeon", "PLAN_KIND_DUNGEON" }, { "worldBoss", "PLAN_KIND_WB" } }
    local menu, picked = {}, {}
    for _, kk in ipairs(KIND_KEYS) do
        local text = L[kk[2]]
        if kk[1] == "favorites" then text = ns.UI.STAR .. " " .. text end
        menu[#menu + 1] = { value = kk[1], text = text, checked = kinds[kk[1]] and true or false }
        if kinds[kk[1]] and kk[1] ~= "favorites" then picked[#picked + 1] = L[kk[2]] end
    end
    p.kinds:SetItems(menu)
    local summary = (#picked == 3) and L["PLAN_KIND_ALL"] or table.concat(picked, ", ")
    p.kinds:SetText(L["PLAN_KINDS"]:format((kinds.favorites and (ns.UI.STAR .. " ") or "") .. summary))

    local steps, sum = ns.Planner:Build(entries, hideDone, kinds)
    p.nextJid = sum.nextJid
    p.next:SetEnabled(sum.nextJid ~= nil)
    local text = L["PLAN_PROGRESS"]:format(sum.done, sum.total)
    if sum.minutes and sum.minutes > 0 then
        text = text .. "  ·  " .. L["PLAN_TIME_LEFT"]:format(SecondsToTime(sum.minutes * 60, true, nil, 2))
    end
    if sum.mage and sum.mage.self then
        text = text .. "  ·  " .. L["PLAN_MAGE_SELF"]
    elseif sum.mage and sum.mage.group then
        text = text .. "  ·  " .. L["PLAN_MAGE_GROUP"]:format(sum.mage.group)
    end
    -- Who in the group also runs the addon (group route, part 1).
    local peers = {}
    for _, peer in ipairs(ns.Comm:Peers()) do peers[#peers + 1] = peer.name end
    if #peers > 0 then
        text = text .. "  ·  |cff8dd3a8" .. L["PLAN_GROUP_ADDON"]:format(table.concat(peers, ", ")) .. "|r"
    end
    p.progress:SetText(text)
    p.fill:SetWidth(math.max(1, p.trackW * (sum.total > 0 and sum.done / sum.total or 0)))

    local width = p.child:GetWidth()
    local y = 0
    local achByInstance = ns.Collection:AchievementsByInstance()
    for _, s in ipairs(steps) do
        local f
        if s.kind == "start" then
            f = take(p, "start")
            f.text:SetText(L["PLAN_START"]:format(s.text))
        elseif s.kind == "travel" then
            f = take(p, "travel")
            f.text:SetText(s.text)
            f.icon:SetTexture(s.icon)
            -- Minimap tracking icons have no border to trim; spell icons do.
            local trim = type(s.icon) ~= "string" or s.icon:find("\\Icons\\", 1, true)
            if trim then f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) else f.icon:SetTexCoord(0, 1, 0, 1) end
        else
            f = take(p, "run")
            local rows, detail, note = describe(s)
            f.num:SetText(s.number)
            f.title:SetText(ns.PlannerPanel.StepTitle(s))
            f.detail:SetText(detail)
            f.note:SetText(note)
            local links = achByInstance[s.jid]
            f.achLinks = links
            local achText = ""
            if links then
                local n = 0
                for _, link in ipairs(links) do n = n + #link.missing end
                achText = (#links == 1)
                    and L["PLAN_ACH_ONE"]:format(links[1].ach.name, n)
                    or L["PLAN_ACH_MANY"]:format(#links, n)
                -- Link look: the achievement's icon in front, an arrow after.
                achText = ("|T%s:12:12:0:0:64:64:5:59:5:59|t %s  |cffa88ad7>|r"):format(links[1].ach.icon or 134400, achText)
            end
            f.ach:SetText(achText)
            f.achBtn:SetShown(achText ~= "")
            f.ach:ClearAllPoints()
            f.ach:SetPoint("TOPLEFT", note ~= "" and f.note or f.detail, "BOTTOMLEFT", 0, -2)
            -- Same boss twice in a row (two mounts) is written once; a mount
            -- several bosses drop is written on its first row only.
            local lastBoss, lastMount
            for i, row in ipairs(rows) do
                local b = lineAt(f, f.bossLines, i, COL.boss, BOSS_W, C.dim)
                b:SetText(row.boss ~= lastBoss and row.boss or "")
                lastBoss = row.boss
                -- "Queue" is wider than "Go": leave it room on event rows.
                local m = mountLineAt(f, i, COL.mount, mountWidth() - (s.event and 16 or 0))
                m.mountID = row.id
                m.text:SetText(row.id == lastMount and ""
                    or ("|T%s:14:14:0:0|t %s%s%s%s|r"):format(row.icon, ns.Collection:IsFavorite(row.id) and (ns.UI.STAR .. " ") or "",
                        (mode == "full" and ns.Collection:InRoute(row.id)) and (ns.UI.ROUTE_ICON .. " ") or "", STATE_HEX[row.state], row.mount))
                m:SetShown(row.id ~= lastMount)
                lastMount = row.id
            end
            for i = #rows + 1, #f.bossLines do f.bossLines[i]:Hide() end
            for i = #rows + 1, #f.mountLines do f.mountLines[i]:Hide() end

            f.check.mark:SetShown(s.done)
            local jid, isRaid, auto = s.jid, s.inst.isRaid, s.auto
            f.check:SetScript("OnClick", function()
                if auto then return end -- the lockout decides; a manual mark adds nothing
                ns.Planner:SetManuallyDone(jid, isRaid, not ns.Planner:IsManuallyDone(jid))
                PlannerPanel:Refresh(p)
            end)
            f.check:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(auto and L["PLAN_TIP_AUTO"] or L["PLAN_TIP_MANUAL"], 1, 1, 1, true)
                GameTooltip:Show()
            end)
            f.check:SetScript("OnLeave", function() GameTooltip:Hide() end)
            if s.event then
                -- World event boss: Queue opens the Dungeon Finder on it.
                local lfgID = s.event.h.lfgDungeonID
                ns.UI.SetButtonText(f.go, L["BTN_QUEUE"], GO_W)
                f.go:SetEnabled(true)
                f.go:SetScript("OnClick", function()
                    if not ns.Holidays:OpenQueue(lfgID) then ns:Print(L["JOURNAL_COMBAT"]) end
                end)
            else
                ns.UI.SetButtonText(f.go, L["BTN_GO"], GO_W) -- pooled rows may have been events
                f.go:SetEnabled(s.inst.entrance ~= nil)
                f.go:SetScript("OnClick", function() ns.Navigation:GoToInstance(jid) end)
            end
            f:SetAlpha(s.done and 0.5 or 1)

            local left = 8 + f.title:GetStringHeight() + 2 + f.detail:GetStringHeight()
                + (note ~= "" and (2 + f.note:GetStringHeight()) or 0)
                + (achText ~= "" and (2 + f.ach:GetStringHeight()) or 0)
            local right = 9 + #rows * LINE_H
            f:SetHeight(math.max(34, math.max(left, right) + 8))
        end
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", 0, -y)
        f:SetWidth(width)
        f:Show()
        y = y + f:GetHeight()
    end

    p.empty:SetShown(sum.total == 0)
    if sum.total == 0 then
        p.empty:SetText(not ns.Lockouts.loaded and L["NOW_LOCKOUTS_LOADING"]
            or (mode == "mine" and L["PLAN_EMPTY_MINE"])
            or (kinds.favorites and L["PLAN_EMPTY_FAV"]) or L["PLAN_EMPTY"])
    end
    p.child:SetHeight(math.max(y, 1))
    ns.PlannerMini:Refresh() -- marks / switches changed here too
end
