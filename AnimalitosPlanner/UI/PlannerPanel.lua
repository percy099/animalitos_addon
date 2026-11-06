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
local COL = { done = 6, num = 30, step = 56, boss = 236, mount = 350 } -- x offsets
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
local function describe(r)
    local e, isRaid = r.e, r.inst.isRaid
    local rows, ready, locked, resetAt, verifyReason = {}, {}, {}, nil, nil
    for id, m in pairs(e.mounts) do
        local mj = ns.MountJournal:GetMount(id)
        local state = (#m.ready > 0 and "ready") or (#m.locked > 0 and "locked") or "verify"
        rows[#rows + 1] = { boss = ns.FarmList:BossName(m.source), mount = mj and mj.name or ("#" .. id),
            icon = mj and mj.icon or 134400, state = state }
        for _, d in ipairs(m.ready) do ready[d] = true end
        for _, d in ipairs(m.locked) do locked[d] = true end
        if m.resetAt then resetAt = math.min(resetAt or m.resetAt, m.resetAt) end
        if m.verify[1] and not verifyReason then verifyReason = m.verify[1].reason end
    end
    table.sort(rows, function(a, b)
        if a.boss ~= b.boss then return a.boss < b.boss end
        return a.mount < b.mount
    end)

    local diffs = next(ready) and ready or locked
    local list = {}
    for d in pairs(diffs) do list[#list + 1] = d end
    table.sort(list)
    local names = {}
    for _, d in ipairs(list) do names[#names + 1] = ns.FarmList:DifficultyName(d) end

    local notes = {}
    if not next(ready) and next(locked) then
        notes[#notes + 1] = L["PLAN_NOTE_LOCKED"]:format(timeLeft(resetAt))
    end
    if isRaid and (diffs[3] or diffs[4] or diffs[5] or diffs[6]) then
        notes[#notes + 1] = L["PLAN_NOTE_SHARED"]
    elseif not isRaid and diffs[2] then
        notes[#notes + 1] = L["PLAN_NOTE_HEROIC"]
    end
    if not next(ready) and not next(locked) and verifyReason then notes[#notes + 1] = verifyReason end

    local kind = isRaid and L["TYPE_RAID"] or L["TYPE_DUNGEON"]
    local detail = #names > 0 and ("%s · %s"):format(kind, table.concat(names, ", ")) or kind
    return rows, detail, table.concat(notes, " · ")
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
    local f = CreateFrame("Frame", nil, p.child)
    f:SetHeight(24)
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    line:SetColorTexture(1, 1, 1, 0.06)
    f.dash = ns.UI.fs(f, "small", ns.UI.COLORS.muted)
    f.dash:SetPoint("LEFT", COL.done + 4, 0)
    f.dash:SetText("—")
    f.text = ns.UI.fs(f, "body", ns.UI.COLORS.dim)
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

    f.boss = ns.UI.fs(f, "small", C.dim)
    f.boss:SetPoint("TOPLEFT", COL.boss, -9)
    f.boss:SetWidth(COL.mount - COL.boss - 8)
    f.boss:SetWordWrap(false)
    f.boss:SetSpacing(LINE_H - 13)
    f.mount = ns.UI.fs(f, "small")
    f.mount:SetPoint("TOPLEFT", COL.mount, -9)
    -- Fixed width (not anchored to the Go button) so multi-line text can grow down.
    f.mount:SetWidth(ns.UI.CONTENT_WIDTH - SCROLL_W - COL.mount - GO_W - 14)
    f.mount:SetWordWrap(false)
    f.mount:SetSpacing(LINE_H - 13)
    return f
end

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

    local function resetButton(textKey, which)
        local b = ns.UI.Button(p, "secondary")
        ns.UI.SetButtonText(b, L[textKey], 60)
        b:SetScript("OnClick", function()
            ns.Planner:ResetMarks(which)
            PlannerPanel:Refresh(p)
        end)
        return b
    end
    local all = resetButton("PLAN_RESET_ALL", "all")
    all:SetPoint("TOPLEFT", 0, -24)
    local dungeons = resetButton("PLAN_RESET_DUNGEONS", "dungeons")
    dungeons:SetPoint("LEFT", all, "RIGHT", 6, 0)
    local raids = resetButton("PLAN_RESET_RAIDS", "raids")
    raids:SetPoint("LEFT", dungeons, "RIGHT", 6, 0)

    p.hide = ns.UI.Switch(p, function(_, checked)
        ns.Storage.db.ui.plannerHideDone = checked or nil
        if p.bar then p.bar:SetValue(0) end
        PlannerPanel:Refresh(p)
    end)
    p.hide:SetPoint("RIGHT", p, "TOPRIGHT", -SCROLL_W - 2, -35)
    local hideLabel = ns.UI.fs(p, "small", C.dim)
    hideLabel:SetPoint("RIGHT", p.hide, "LEFT", -8, 0)
    hideLabel:SetText(L["PLAN_HIDE_DONE"])

    p.next = ns.UI.Button(p, "primary")
    ns.UI.SetButtonText(p.next, L["PLAN_NEXT"], 96)
    p.next:SetPoint("TOPRIGHT", -SCROLL_W, -56)
    p.next:SetScript("OnClick", function()
        if p.nextJid then ns.Navigation:GoToInstance(p.nextJid) end
    end)

    p.progress = ns.UI.fs(p, "small", C.dim)
    p.progress:SetPoint("TOPLEFT", 2, -58)
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

    p.empty = ns.UI.fs(child, "GameFontHighlightSmall", C.muted)
    p.empty:SetPoint("TOPLEFT", 4, -40)
    p.empty:SetPoint("RIGHT", -4, 0)
    p.empty:SetWordWrap(true)
    return p
end

-- Refresh -------------------------------------------------------------------------
local STATE_HEX = { ready = "|cffffffff", locked = "|cffe0a040", verify = "|cff8c8899" }

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

    local steps, sum = ns.Planner:Build(entries, hideDone)
    p.nextJid = sum.nextJid
    p.next:SetEnabled(sum.nextJid ~= nil)
    p.progress:SetFormattedText(L["PLAN_PROGRESS"], sum.done, sum.total)
    p.fill:SetWidth(math.max(1, p.trackW * (sum.total > 0 and sum.done / sum.total or 0)))

    local width = p.child:GetWidth()
    local y = 0
    for _, s in ipairs(steps) do
        local f
        if s.kind == "start" then
            f = take(p, "start")
            f.text:SetText(L["PLAN_START"]:format(s.text))
        elseif s.kind == "travel" then
            f = take(p, "travel")
            f.text:SetText(s.text)
        else
            f = take(p, "run")
            local rows, detail, note = describe(s)
            f.num:SetText(s.number)
            f.title:SetText(L["PLAN_RUN"]:format(ns.FarmList:InstanceName(s.jid)))
            f.detail:SetText(detail)
            f.note:SetText(note)
            local bosses, mounts = {}, {}
            for _, row in ipairs(rows) do
                bosses[#bosses + 1] = row.boss
                mounts[#mounts + 1] = ("|T%s:14:14:0:0|t %s%s|r"):format(row.icon, STATE_HEX[row.state], row.mount)
            end
            f.boss:SetText(table.concat(bosses, "\n"))
            f.mount:SetText(table.concat(mounts, "\n"))

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
            f.go:SetEnabled(s.inst.entrance ~= nil)
            f.go:SetScript("OnClick", function() ns.Navigation:GoToInstance(jid) end)
            f:SetAlpha(s.done and 0.5 or 1)

            local left = 8 + f.title:GetStringHeight() + 2 + f.detail:GetStringHeight()
                + (note ~= "" and (2 + f.note:GetStringHeight()) or 0)
            local right = 9 + math.max(f.boss:GetStringHeight(), f.mount:GetStringHeight())
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
        p.empty:SetText(ns.Lockouts.loaded and L["PLAN_EMPTY"] or L["NOW_LOCKOUTS_LOADING"])
    end
    p.child:SetHeight(math.max(y, 1))
end
