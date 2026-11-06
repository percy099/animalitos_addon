-- Mini planner: a small movable window with the next step of the Planner
-- route (how to get there, the instance, its mounts, Go / Done) and the
-- step after it. Same static order as the Planner; no OnUpdate, it
-- refreshes with the rest of the addon (lockouts, marks, roster).
local _, ns = ...
local L = ns.L

local Mini = {}
ns.PlannerMini = Mini

local W = 280
local PAD = 10
local INNER = W - PAD * 2
local MAX_TRAVEL = 4 -- travel lines shown per step (the rest as "+n")

local function db() return ns.Storage.db.ui end

Mini.undoStack = {} -- jids marked with Done in this session, newest last
local hideSecure -- defined with the travel buttons below; used by create()

-- Drops entries that are no longer marked (unticked in the Planner, reset).
local function pruneUndo()
    local s = Mini.undoStack
    for i = #s, 1, -1 do
        if not ns.Planner:IsManuallyDone(s[i]) then table.remove(s, i) end
    end
end

-- Font strings are reused from a small pool, laid out top to bottom.
local function line(f, font, color)
    f.used = f.used + 1
    local t = f.lines[f.used]
    if not t then
        t = ns.UI.fs(f, font)
        t:SetWordWrap(true)
        f.lines[f.used] = t
    end
    t:SetFontObject(ns.UI.FONTS[font] or ns.UI.FONTS.body)
    local c = color or ns.UI.COLORS.text
    t:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    t:SetWidth(INNER)
    t:ClearAllPoints()
    t:Show()
    return t
end

local function place(f, t, text, gap)
    t:SetText(text)
    t:SetPoint("TOPLEFT", PAD, -(f.y + (gap or 0)))
    f.y = f.y + (gap or 0) + t:GetStringHeight()
end

local function create()
    local C = ns.UI.COLORS
    local a = C.accent
    local f = CreateFrame("Frame", "AnimalitosPlannerMini", UIParent, "BackdropTemplate")
    f:SetSize(W, 120)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    ns.UI.StylePanel(f, C.background, { border = { a[1], a[2], a[3], 0.45 }, noSheen = true })
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        db().miniPoint = { point, relPoint, x, y }
    end)
    local p = db().miniPoint
    if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else f:SetPoint("RIGHT", -60, 120) end
    f:SetScale(ns.UI:GetScale())

    f.head = ns.UI.fs(f, "caps", C.accent)
    f.head:SetPoint("TOPLEFT", PAD, -9)
    local close = ns.UI.CloseButton(f)
    close:SetPoint("TOPRIGHT", -4, -3)
    close:SetScript("OnClick", function() Mini:SetShown(false) end)
    -- Click the header to open the full Planner.
    local open = CreateFrame("Button", nil, f)
    open:SetPoint("TOPLEFT", 0, 0)
    open:SetPoint("TOPRIGHT", close, "TOPLEFT", -4, 0)
    open:SetHeight(26)
    open:RegisterForDrag("LeftButton")
    open:SetScript("OnDragStart", function() f:StartMoving() end)
    open:SetScript("OnDragStop", function() f:GetScript("OnDragStop")(f) end)
    open:SetScript("OnClick", function() ns.UI:Open("planner") end)
    open:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["MINI_TIP"], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    open:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.go = ns.UI.Button(f, "primary")
    ns.UI.SetButtonText(f.go, L["BTN_GO"], 48)
    f.done = ns.UI.Button(f, "secondary")
    ns.UI.SetButtonText(f.done, L["MINI_DONE"], 60)
    -- Undo: unticks the last steps marked with Done here (a stack, so a
    -- few accidental clicks can be undone one by one).
    f.undo = ns.UI.Button(f, "secondary")
    ns.UI.SetButtonText(f.undo, L["MINI_UNDO"], 56)
    f.undo:SetScript("OnClick", function()
        local jid = table.remove(Mini.undoStack)
        if jid then
            ns.Planner:SetManuallyDone(jid, nil, false)
            Mini:Refresh()
            ns.UI:Refresh()
        end
    end)
    f.undo:SetScript("OnEnter", function(self)
        local jid = Mini.undoStack[#Mini.undoStack]
        if not jid then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["MINI_UNDO_TIP"]:format(ns.FarmList:InstanceName(jid)), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.undo:SetScript("OnLeave", function() GameTooltip:Hide() end)


    -- Instance helper: sets the difficulty the mounts drop on.
    f.diff = ns.UI.Button(f, "primary")
    f.diff:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ns:On("PLAYER_DIFFICULTY_CHANGED", function()
        if f:IsShown() then ns:Debounce("mini-diff", 0.3, function() Mini:Refresh() end) end
    end)
    f.sep = f:CreateTexture(nil, "ARTWORK")
    f.sep:SetHeight(1)
    f.sep:SetColorTexture(1, 1, 1, 0.08)

    f.lines, f.mountBtns = {}, {}
    f:SetScript("OnHide", function()
        ns.MountPreview:HidePopup()
        if not InCombatLockdown() then hideSecure() end
    end)
    -- Secure travel buttons: away during combat, back after it.
    ns:On("PLAYER_REGEN_DISABLED", hideSecure)
    ns:On("PLAYER_REGEN_ENABLED", function()
        if f:IsShown() then Mini:Refresh() end
    end)
    -- A mage joining / leaving changes the travel steps.
    ns:On("GROUP_ROSTER_UPDATE", function()
        if f:IsShown() then ns:Debounce("mini-roster", 0.5, function() Mini:Refresh() end) end
    end)
    return f
end

local function mountButton(f, i)
    local b = f.mountBtns[i]
    if not b then
        b = CreateFrame("Button", nil, f)
        b:SetSize(INNER, 16)
        b.text = ns.UI.fs(b, "small")
        b.text:SetAllPoints()
        b.text:SetWordWrap(false)
        b:SetScript("OnEnter", function(self)
            self.text:SetAlpha(0.75)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(L["MINI_MOUNT_TIP"], 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self)
            self.text:SetAlpha(1)
            GameTooltip:Hide()
        end)
        b:SetScript("OnClick", function(self)
            if self.mountID then ns.MountPreview:TogglePopup(self.mountID, f) end
        end)
        f.mountBtns[i] = b
    end
    b:ClearAllPoints()
    b:Show()
    return b
end

-- Clickable travel lines (teleport, portal, hearthstone, travel toys):
-- casting needs secure buttons. They live on UIParent, not on the mini
-- window, so the window never becomes protected; when combat starts they
-- are hidden and unanchored (still allowed in PLAYER_REGEN_DISABLED) and
-- they come back with the refresh after combat.
local secure = {}
function hideSecure() -- the local declared at the top
    for _, b in ipairs(secure) do
        b:Hide()
        b:ClearAllPoints()
    end
end

local function secureButton(i)
    local b = secure[i]
    if not b then
        b = CreateFrame("Button", "AnimalitosPlannerTravel" .. i, UIParent, "SecureActionButtonTemplate")
        b:RegisterForClicks("AnyUp", "AnyDown")
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["MINI_TRAVEL_TIP"]:format(self.actionName or "?"), 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        secure[i] = b
    end
    return b
end

-- clickable: true for the current step (its first hop is where you are).
local function travelLines(f, travel, color, clickable)
    for i, text in ipairs(travel) do
        if i > MAX_TRAVEL then
            place(f, line(f, "tiny", color), ("   +%d"):format(#travel - MAX_TRAVEL), 1)
            break
        end
        local action = clickable and not InCombatLockdown() and ns.Planner:TravelAction(text)
        local t = line(f, "small", action and ns.UI.COLORS.text or color)
        place(f, t, ("|T%s:14:14:0:0:64:64:5:59:5:59|t  %s"):format(ns.Planner:TravelIcon(text), text), 2)
        if action then
            f.secureUsed = f.secureUsed + 1
            local b = secureButton(f.secureUsed)
            b:SetAttribute("type", action.type)
            b:SetAttribute("spell", action.spell)
            b:SetAttribute("toy", action.toy)
            b:SetAttribute("item", action.item)
            b.actionName = action.name
            b:SetFrameStrata(f:GetFrameStrata())
            b:SetFrameLevel(f:GetFrameLevel() + 20)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", t, "TOPLEFT", -4, 2)
            b:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 4, -2)
            b:Show()
        end
    end
end

local function runTitle(s)
    return ns.PlannerPanel.StepTitle(s)
end

-- Difficulty line (and its button) for a step at its entrance or inside.
local DIFF_BLOCKED = { combat = "JOURNAL_COMBAT", leader = "MINI_DIFF_LEADER" }
local function helper(f, e)
    local C = ns.UI.COLORS
    local D = ns.Difficulty
    local want = D:Pick(e)
    if not want then return end
    local inside = D:Inside(e)
    if inside then
        if D:Drops(e, inside) then
            place(f, line(f, "small", C.success), "|A:common-icon-checkmark:12:12|a  " .. L["MINI_DIFF_OK"]:format(D:Name(inside)), 6)
        else
            place(f, line(f, "small", C.warning), L["MINI_DIFF_WRONG"]:format(D:Name(inside), D:Name(want)), 6)
        end
        return
    end
    if D:IsSet(want) then
        place(f, line(f, "small", C.success), "|A:common-icon-checkmark:12:12|a  " .. L["MINI_DIFF_SET"]:format(D:Name(want)), 6)
        return
    end
    place(f, line(f, "small", C.text), L["MINI_DIFF_NEED"]:format(D:Name(want)), 6)
    if not D:Settable(want) then return end
    local blocked = D:Blocked()
    ns.UI.SetButtonText(f.diff, L["MINI_DIFF_BTN"]:format(ns.FarmList:DifficultyName(want)), 90)
    f.diff:ClearAllPoints()
    f.diff:SetPoint("TOPLEFT", PAD, -(f.y + 4))
    f.diff:SetEnabled(blocked == nil)
    f.diff:SetScript("OnClick", function()
        if not D:Set(want) then ns:Print(L[DIFF_BLOCKED[D:Blocked()] or "MINI_DIFF_LEADER"]) end
    end)
    f.diff:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(blocked and L[DIFF_BLOCKED[blocked] or "MINI_DIFF_LEADER"] or L["MINI_DIFF_TIP"], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.diff:Show()
    f.y = f.y + 4 + 22
end
function Mini:Refresh()
    local f = self.frame
    if not f or not f:IsShown() then return end
    local C = ns.UI.COLORS
    for _, t in ipairs(f.lines) do t:Hide() end
    for _, b in ipairs(f.mountBtns) do b:Hide() end
    f.used = 0
    f.secureUsed = 0
    if not InCombatLockdown() then hideSecure() end
    f.y = 30

    local entries = ns.FarmList:Build()
    local cur, after, sum = ns.Planner:Upcoming(entries)
    -- Header: progress and a short time left (the button row has no room).
    local left = ""
    if sum.minutes and sum.minutes > 0 then
        left = "   |cff8c8899" .. L["PLAN_TIME_LEFT"]:format(SecondsToTime(sum.minutes * 60, true, nil, 1)) .. "|r"
    end
    f.head:SetText(ns.UI.Upper(L["MINI_NEXT"]) .. ("   |cffffffff%d / %d|r"):format(sum.done, sum.total) .. left)

    if not cur then
        place(f, line(f, "small", C.muted),
            ns.Lockouts.loaded and L["PLAN_EMPTY"] or L["NOW_LOCKOUTS_LOADING"], 0)
        f.go:Hide()
        f.done:Hide()
        -- Everything done: Undo stays reachable for the last click.
        pruneUndo()
        f.undo:ClearAllPoints()
        f.undo:SetPoint("TOPLEFT", PAD, -(f.y + 6))
        f.undo:SetShown(#Mini.undoStack > 0)
        if #Mini.undoStack > 0 then f.y = f.y + 30 end

        f.sep:Hide()
        f:SetHeight(f.y + PAD + 4)
        return
    end

    -- Current step: how to get there, the instance, its mounts.
    local s = cur.run
    -- Already inside the instance: the way there is no longer needed.
    local inside = not s.event and s.e and ns.Difficulty:Inside(s.e) ~= nil
    local travel = inside and {} or cur.travel
    travelLines(f, travel, C.dim, true)
    place(f, line(f, "title", C.text), runTitle(s), #travel > 0 and 6 or 0)
    local rows, detail, note = ns.PlannerPanel.Describe(s)
    place(f, line(f, "tiny", C.muted), detail, 2)
    -- At the entrance or inside: the difficulty the mounts drop on, and the
    -- boss in front of each mount.
    local here = not s.event and s.e and (s.e.near == 2 or ns.Difficulty:Inside(s.e) ~= nil)
    f.diff:Hide()
    if here then helper(f, s.e) end
    -- One clickable line per mount: click shows its 3D model beside the window.
    local seen, n = {}, 0
    for _, r in ipairs(rows) do
        if r.state == "ready" and not seen[r.id] then
            seen[r.id] = true
            n = n + 1
            local b = mountButton(f, n)
            b.mountID = r.id
            local label = r.mount
            local m = here and s.e.mounts[r.id]
            if m then label = ("%s  |cff999999%s|r"):format(r.mount, ns.FarmList:BossName(m.source)) end
            b.text:SetText(("|T%s:14:14:0:0|t %s"):format(r.icon, label))
            b:SetPoint("TOPLEFT", PAD, -(f.y + 3))
            f.y = f.y + 3 + 16
        end
    end
    if note ~= "" then place(f, line(f, "tiny", C.dim), note, 2) end

    -- Buttons
    f.y = f.y + 8
    local jid, isRaid = s.jid, s.inst.isRaid
    f.go:ClearAllPoints()
    f.go:SetPoint("TOPLEFT", PAD, -f.y)
    if s.event then
        -- World event boss: no travel, Queue opens the Dungeon Finder.
        local lfgID = s.event.h.lfgDungeonID
        ns.UI.SetButtonText(f.go, L["BTN_QUEUE"], 48)
        f.go:SetEnabled(true)
        f.go:SetScript("OnClick", function()
            if not ns.Holidays:OpenQueue(lfgID) then ns:Print(L["JOURNAL_COMBAT"]) end
        end)
    else
        ns.UI.SetButtonText(f.go, L["BTN_GO"], 48)
        f.go:SetEnabled(s.inst.entrance ~= nil)
        f.go:SetScript("OnClick", function() ns.Navigation:GoToInstance(jid) end)
    end
    f.go:Show()
    f.done:ClearAllPoints()
    f.done:SetPoint("LEFT", f.go, "RIGHT", 6, 0)
    f.done:SetScript("OnClick", function()
        ns.Planner:SetManuallyDone(jid, isRaid, true)
        table.insert(Mini.undoStack, jid)
        Mini:Refresh()
        ns.UI:Refresh()
    end)
    f.done:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["PLAN_TIP_MANUAL"], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.done:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.done:Show()
    pruneUndo()
    f.undo:ClearAllPoints()
    f.undo:SetPoint("LEFT", f.done, "RIGHT", 6, 0)
    f.undo:SetShown(#Mini.undoStack > 0)

    f.y = f.y + 22

    -- The step after it, dimmer.
    if after then
        f.y = f.y + 8
        f.sep:ClearAllPoints()
        f.sep:SetPoint("TOPLEFT", PAD, -f.y)
        f.sep:SetPoint("TOPRIGHT", -PAD, -f.y)
        f.sep:Show()
        f.y = f.y + 6
        place(f, line(f, "caps", C.muted), ns.UI.Upper(L["MINI_AFTER"]), 0)
        travelLines(f, after.travel, C.muted)
        place(f, line(f, "body", C.dim), runTitle(after.run), #after.travel > 0 and 4 or 2)
    else
        f.sep:Hide()
    end
    f:SetHeight(f.y + PAD)
end

--- Shows or hides the mini window; remembered across sessions.
function Mini:SetShown(show)
    db().miniShown = show or nil
    if show then
        self.frame = self.frame or create()
        self.frame:Show()
        self:Refresh()
    elseif self.frame then
        self.frame:Hide()
    end
end

function Mini:Toggle()
    self:SetShown(not (self.frame and self.frame:IsShown()))
end

function Mini:Restore()
    if db().miniShown then self:SetShown(true) end
end
