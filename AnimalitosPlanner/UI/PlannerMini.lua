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


    f.sep = f:CreateTexture(nil, "ARTWORK")
    f.sep:SetHeight(1)
    f.sep:SetColorTexture(1, 1, 1, 0.08)

    f.lines, f.mountBtns = {}, {}
    f:SetScript("OnHide", function() ns.MountPreview:HidePopup() end)
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

local function travelLines(f, travel, color)
    for i, text in ipairs(travel) do
        if i > MAX_TRAVEL then
            place(f, line(f, "tiny", color), ("   +%d"):format(#travel - MAX_TRAVEL), 1)
            break
        end
        place(f, line(f, "small", color), ("|T%s:14:14:0:0:64:64:5:59:5:59|t  %s"):format(ns.Planner:TravelIcon(text), text), 2)
    end
end

local function runTitle(s)
    return L[s.inst.worldBoss and "PLAN_KILL" or "PLAN_RUN"]:format(ns.FarmList:InstanceName(s.jid))
end

function Mini:Refresh()
    local f = self.frame
    if not f or not f:IsShown() then return end
    local C = ns.UI.COLORS
    for _, t in ipairs(f.lines) do t:Hide() end
    for _, b in ipairs(f.mountBtns) do b:Hide() end
    f.used = 0
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
    travelLines(f, cur.travel, C.dim)
    local s = cur.run
    place(f, line(f, "title", C.text), runTitle(s), #cur.travel > 0 and 6 or 0)
    local rows, detail, note = ns.PlannerPanel.Describe(s)
    place(f, line(f, "tiny", C.muted), detail, 2)
    -- One clickable line per mount: click shows its 3D model beside the window.
    local seen, n = {}, 0
    for _, r in ipairs(rows) do
        if r.state == "ready" and not seen[r.id] then
            seen[r.id] = true
            n = n + 1
            local b = mountButton(f, n)
            b.mountID = r.id
            b.text:SetText(("|T%s:14:14:0:0|t %s"):format(r.icon, r.mount))
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
    f.go:SetEnabled(s.inst.entrance ~= nil)
    f.go:SetScript("OnClick", function() ns.Navigation:GoToInstance(jid) end)
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
