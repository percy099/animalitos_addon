-- Mount detail: side panel next to the main window with the 3D model and
-- everything the addon knows about the mount: overall status, where it drops
-- (each dataset source with its state per difficulty, like /aplan why, and a
-- Go button), the achievements that reward it, and the journal's source and
-- description. Opened by clicking a mount anywhere in the window.
local _, ns = ...
local L = ns.L

local Preview = {}
ns.MountPreview = Preview

local W = 300
local MODEL_H = 170
local function height() return ns.UI.HEIGHT or 500 end

local function create()
    local C = ns.UI.COLORS
    local main = ns.UI.frame
    local f = CreateFrame("Frame", nil, main, "BackdropTemplate")
    f:SetSize(W, height())
    f:SetPoint("TOPLEFT", main, "TOPRIGHT", 4, 0)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    ns.UI.StylePanel(f, C.background, { border = { C.accent[1], C.accent[2], C.accent[3], 0.45 }, noSheen = true })

    local close = ns.UI.CloseButton(f)
    close:SetPoint("TOPRIGHT", -6, -6)

    f.star = ns.UI.FavStar(f, 18)
    f.star:SetPoint("RIGHT", close, "LEFT", -4, 0)

    f.title = ns.UI.fs(f, "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 12, -12)
    f.title:SetPoint("RIGHT", f.star, "LEFT", -4, 0)
    f.title:SetWordWrap(false)

    local holder = CreateFrame("Frame", nil, f, "BackdropTemplate")
    holder:SetPoint("TOPLEFT", 10, -40)
    holder:SetPoint("TOPRIGHT", -10, -40)
    holder:SetHeight(MODEL_H)
    ns.UI.StylePanel(holder)

    -- Same scene type Blizzard's Mount Journal uses; plain model as fallback.
    local ok, scene = pcall(CreateFrame, "ModelScene", nil, holder, "ModelSceneMixinTemplate")
    if ok and scene then
        scene:SetPoint("TOPLEFT", 4, -4)
        scene:SetPoint("BOTTOMRIGHT", -4, 4)
        scene:EnableMouse(true)
        f.scene = scene
    end
    f.model = CreateFrame("PlayerModel", nil, holder)
    f.model:SetPoint("TOPLEFT", 4, -4)
    f.model:SetPoint("BOTTOMRIGHT", -4, 4)
    f.model:Hide()

    f.hint = ns.UI.fs(f, "GameFontDisableSmall")
    f.hint:SetPoint("TOPRIGHT", holder, "BOTTOMRIGHT", -2, -3)
    f.hint:SetJustifyH("RIGHT")
    f.hint:SetText(L["PREVIEW_DRAG"])

    f.journal = ns.UI.Button(f, "primary")
    ns.UI.SetButtonText(f.journal, L["BTN_OPEN_JOURNAL"], 160)
    f.journal:SetPoint("BOTTOM", 0, 12)

    -- Detail sections scroll (mouse wheel) between the model and the
    -- button, so long texts never run under the button.
    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 2, -20)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 12 + 22 + 8)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(W - 24, 1)
    scroll:SetScrollChild(child)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local max = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.min(max, math.max(0, self:GetVerticalScroll() - delta * 28)))
    end)
    f.scroll, f.scrollChild = scroll, child
    -- Pools for the dynamic content (rebuilt on every Show).
    f.texts, f.gos, f.achRows = {}, {}, {}

    -- "More below" fade at the bottom edge while there is text left to scroll.
    local bg = C.background
    f.more = f:CreateTexture(nil, "OVERLAY")
    f.more:SetPoint("BOTTOMLEFT", scroll, "BOTTOMLEFT", -2, 0)
    f.more:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT")
    f.more:SetHeight(18)
    f.more:SetColorTexture(1, 1, 1, 1)
    f.more:SetGradient("VERTICAL", CreateColor(bg[1], bg[2], bg[3], 1), CreateColor(bg[1], bg[2], bg[3], 0))
    local function updateMore(self)
        f.more:SetShown(self:GetVerticalScroll() < self:GetVerticalScrollRange() - 1)
    end
    scroll:SetScript("OnVerticalScroll", updateMore)
    scroll:SetScript("OnScrollRangeChanged", updateMore) -- range settles after layout
    return f
end

-- Returns true when the ModelScene path worked.
local function showInScene(f, extra)
    if not (f.scene and extra.uiModelSceneID and extra.creatureDisplayID) then return false end
    local ok, done = pcall(function()
        f.scene:TransitionToModelSceneID(extra.uiModelSceneID, CAMERA_TRANSITION_TYPE_IMMEDIATE,
            CAMERA_MODIFICATION_TYPE_DISCARD, true)
        local actor = f.scene:GetActorByTag("unwrapped")
        if not actor then return false end
        actor:SetModelByCreatureDisplayID(extra.creatureDisplayID, true)
        if extra.isSelfMount then
            actor:SetAnimationBlendOperation(Enum.ModelBlendOperation.None)
            actor:SetAnimation(618) -- mount-only "self mount" idle, as the Mount Journal does
        else
            actor:SetAnimationBlendOperation(Enum.ModelBlendOperation.Anim)
            actor:SetAnimation(0)
        end
        return true
    end)
    return ok and done
end

local function showModel(f, extra)
    if showInScene(f, extra) then
        f.model:Hide()
        f.scene:Show()
        f.hint:Show()
        return
    end
    if f.scene then f.scene:Hide() end
    f.hint:Hide()
    if extra.creatureDisplayID then
        f.model:SetDisplayInfo(extra.creatureDisplayID)
        f.model:Show()
    else
        f.model:Hide()
    end
end

-- Content builder ------------------------------------------------------------
local CONTENT_W = W - 28
local GO_W = 40

-- Layout cursor over the pools; reset() hides everything first.
local function newLayout(f)
    local lay = { f = f, y = 0, nText = 0, nGo = 0, nAch = 0 }
    for _, t in ipairs(f.texts) do t:Hide() end
    for _, b in ipairs(f.gos) do b:Hide() end
    for _, r in ipairs(f.achRows) do r:Hide() end
    return lay
end

local function text(lay, s, font, color, indent, gap, rightPad)
    local f = lay.f
    lay.nText = lay.nText + 1
    local t = f.texts[lay.nText]
    if not t then
        t = ns.UI.fs(f.scrollChild, "small")
        t:SetWordWrap(true)
        t:SetJustifyH("LEFT")
        f.texts[lay.nText] = t
    end
    t:SetFontObject(ns.UI.FONTS[font] or font)
    local c = color or ns.UI.COLORS.text
    t:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    lay.y = lay.y + (gap or 0)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", indent or 0, -lay.y)
    t:SetWidth(CONTENT_W - (indent or 0) - (rightPad or 0))
    t:SetText(s)
    t:Show()
    lay.y = lay.y + t:GetStringHeight()
    return t
end

local function header(lay, key)
    local C = ns.UI.COLORS
    text(lay, ns.UI.Upper(L[key]), "caps", C.accent, 0, lay.y > 0 and 14 or 0)
    lay.y = lay.y + 4
end

-- Small button at the right of a text line: "Go" (waypoint) or "Map".
local function lineButton(lay, anchor, label, enabled, onClick)
    local f = lay.f
    lay.nGo = lay.nGo + 1
    local b = f.gos[lay.nGo]
    if not b then
        b = ns.UI.Button(f.scrollChild, "primary")
        b:SetHeight(20)
        f.gos[lay.nGo] = b
    end
    ns.UI.SetButtonText(b, label, GO_W)
    b:SetHeight(20)
    b:ClearAllPoints()
    b:SetPoint("TOPRIGHT", f.scrollChild, "TOPRIGHT", 0, select(5, anchor:GetPoint(1)) + 2)
    b:SetEnabled(enabled)
    b:SetScript("OnClick", onClick)
    b:Show()
end

local function goButton(lay, anchor, jid)
    local inst = ns.Data.instances[jid]
    lineButton(lay, anchor, L["BTN_GO"], inst and inst.entrance ~= nil,
        function() ns.Navigation:GoToInstance(jid) end)
end

local function achRow(lay, a)
    local f, C = lay.f, ns.UI.COLORS
    lay.nAch = lay.nAch + 1
    local r = f.achRows[lay.nAch]
    if not r then
        r = CreateFrame("Button", nil, f.scrollChild)
        r:SetHeight(18)
        r.text = ns.UI.fs(r, "small")
        r.text:SetPoint("LEFT")
        r.text:SetPoint("RIGHT", -50, 0)
        r.text:SetWordWrap(false)
        r.text:SetJustifyH("LEFT")
        r.value = ns.UI.fs(r, "small")
        r.value:SetPoint("RIGHT")
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)
        r:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local link = ns.Achievements:Link(self.id)
            if link then GameTooltip:SetHyperlink(link) end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:SetScript("OnClick", function(self)
            if not ns.Achievements:Open(self.id) then ns:Print(L["JOURNAL_COMBAT"]) end
        end)
        f.achRows[lay.nAch] = r
    end
    r.id = a.id
    r.text:SetText(("|T%s:14:14:0:0|t %s"):format(a.icon or 134400, a.name))
    local c = a.completed and C.success or C.warning
    r.value:SetText(a.completed and L["COL_ACH_DONE"] or ("%d / %d"):format(a.done, a.total))
    r.value:SetTextColor(c[1], c[2], c[3])
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 0, -(lay.y + 2))
    r:SetPoint("RIGHT", f.scrollChild, "RIGHT")
    r:Show()
    lay.y = lay.y + 20
end

-- State colors and labels (same meaning as everywhere in the window).
local S = function() return ns.Eligibility.STATES end
local function stateStyle(state, reason)
    local C, st = ns.UI.COLORS, S()
    if state == st.UNAVAILABLE and reason == L["REASON_WQ_ROTATION"] then
        return C.muted, L["STATUS_NOT_THIS_WEEK"]
    end
    if state == st.READY then return C.success, L["STATUS_READY"] end
    if state == st.LOCKED_OUT then return C.warning, L["STAT_LOCKED"] end
    if state == st.COLLECTED then return C.accent, L["STATUS_COLLECTED"] end
    if state == st.VERIFY then return C.dim, L["STATUS_VERIFY"] end
    return C.muted, L["DETAIL_UNAVAILABLE"]
end

local function hex(c)
    return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
end

local function resetText(resetAt)
    return resetAt and SecondsToTime(math.max(0, resetAt - time()), true, nil, 2) or "?"
end

-- Fills the scroll area for one mount. Returns the content height.
local function build(f, mountID, m, extra)
    local C, st = ns.UI.COLORS, S()
    local lay = newLayout(f)

    -- Every dataset source of this mount, evaluated per difficulty.
    local blocks, best = {}, nil
    local rank = { [st.READY] = 1, [st.LOCKED_OUT] = 2, [st.VERIFY] = 3 }
    local bestReset
    for _, src in ipairs(ns.Data.sources) do
        if src.mountID == mountID then
            local rows = {}
            for _, d in ipairs(src.difficulties) do
                local state, reason, resetAt = ns.Eligibility:Evaluate(src, d)
                rows[#rows + 1] = { d = d, state = state, reason = reason, resetAt = resetAt }
                if rank[state] and (not best or rank[state] < rank[best]) then best = state end
                if state == st.LOCKED_OUT and resetAt then bestReset = math.min(bestReset or resetAt, resetAt) end
            end
            blocks[#blocks + 1] = { src = src, rows = rows }
        end
    end

    -- Overall status line.
    local status, label
    if m and m.isCollected then
        status, label = C.accent, L["STATUS_COLLECTED"]
    elseif best then
        status, label = stateStyle(best)
        if best == st.LOCKED_OUT then label = label .. " · " .. L["NOW_RESETS_IN"]:format(resetText(bestReset)) end
    elseif m and m.shouldHideOnChar then
        status, label = C.muted, L["DETAIL_UNAVAILABLE"]
    else
        status, label = C.muted, L["STATUS_MISSING"]
    end
    text(lay, "● " .. label, "body", status)

    -- Where to get it (dataset): instance, boss, state per difficulty.
    if #blocks > 0 then
        header(lay, "DETAIL_WHERE")
        for i, b in ipairs(blocks) do
            local jid, inst = b.src.journalInstanceID, ns.Data.instances[b.src.journalInstanceID]
            local title = text(lay, ns.FarmList:InstanceName(jid), "title", C.text, 0, i > 1 and 10 or 2, GO_W + 6)
            goButton(lay, title, jid)
            local parts = { inst and ns.FarmList:TypeName(inst) or "?" }
            local zone = inst and inst.entrance and C_Map.GetMapInfo(inst.entrance.uiMapID)
            if zone then parts[#parts + 1] = zone.name end
            if not (inst and inst.worldBoss) then parts[#parts + 1] = ns.FarmList:BossName(b.src) end
            text(lay, table.concat(parts, " · "), "small", C.dim, 0, 1, GO_W + 6)
            if not (m and m.isCollected) then
                for _, r in ipairs(b.rows) do
                    local c, stateLabel = stateStyle(r.state, r.reason)
                    local line = ("%s%s|r  %s%s|r"):format("|cffffffff", ns.FarmList:DifficultyName(r.d), hex(c), stateLabel)
                    if r.state == st.LOCKED_OUT then
                        line = line .. "  |cff999999" .. L["NOW_RESETS_IN"]:format(resetText(r.resetAt)) .. "|r"
                    end
                    text(lay, line, "small", C.text, 8, 3)
                    if r.reason and r.state ~= st.READY and r.state ~= st.LOCKED_OUT then
                        text(lay, r.reason, "tiny", C.muted, 16, 1)
                    end
                end
            end
        end
    end

    -- Not in the dataset: who drops it and where, from the journal text.
    -- No coordinates (the game does not give them) and no kill status.
    local drops = (#blocks == 0) and ns.Collection:DropInfo(mountID) or nil
    if drops and #drops > 0 then
        header(lay, "DETAIL_WHERE")
        for i, d in ipairs(drops) do
            local title = text(lay, d.who, "title", C.text, 0, i > 1 and 10 or 2, GO_W + 6)
            local zoneID = d.zone and d.zone.uiMapID
            lineButton(lay, title, L["BTN_MAP"], zoneID ~= nil, function()
                if not ns.Navigation:OpenMap(zoneID) then ns:Print(L["JOURNAL_COMBAT"]) end
            end)
            if d.zone then text(lay, d.zone.name, "small", C.dim, 0, 1, GO_W + 6) end
            for _, e in ipairs(d.extra) do text(lay, e, "tiny", C.muted, 0, 1) end
        end
        if not (m and m.isCollected) then
            text(lay, L["DETAIL_DROP_NOTE"], "tiny", C.muted, 0, 6)
        end
    end

    -- Vendor mounts: what the vendor asks for and whether this character has
    -- it (tooltip of the item + journal text; the price is not checked).
    local req = not (m and m.isCollected) and ns.Requirements:Get(mountID) or nil
    if req then
        header(lay, "DETAIL_REQS")
        local summary = {
            met = { L["REQ_ALL_MET"], C.success }, none = { L["REQ_NONE"], C.dim },
            missing = { L["REQ_MISSING"], C.warning }, unknown = { L["REQ_UNKNOWN"], C.dim },
            loading = { L["REQ_LOADING"], C.muted }, remix = { L["REQ_REMIX"], C.muted },
        }
        local s = summary[req.status] or summary.unknown
        text(lay, s[1], "body", s[2], 0, 2)
        if req.status ~= "remix" then
            for _, r in ipairs(req.reqs) do
                local icon = ns.Requirements.ICON[r.met] or ns.Requirements.ICON_UNKNOWN
                text(lay, icon .. "  " .. r.text, "small", C.text, 8, 3)
            end
            text(lay, L["REQ_NOTE"], "tiny", C.muted, 0, 4)
        end
    end

    -- Achievements that reward this mount (built in the background).
    local achs = ns.Collection:Achievements()
    local mine = {}
    for _, a in ipairs(achs or {}) do
        if a.mountID == mountID then mine[#mine + 1] = a end
    end
    if #mine > 0 then
        header(lay, "DETAIL_ACHIEVEMENTS")
        for _, a in ipairs(mine) do achRow(lay, a) end
    end

    -- What the Mount Journal says.
    if extra.sourceText and extra.sourceText ~= "" then
        header(lay, "DETAIL_SOURCE")
        text(lay, extra.sourceText, "small", C.text)
    end
    if extra.description and extra.description ~= "" then
        text(lay, extra.description, "small", C.muted, 0, 8)
    end
    if #blocks == 0 and #mine == 0 and not req and not (drops and #drops > 0) and not (m and m.isCollected) then
        text(lay, L["DETAIL_NO_DATA"], "tiny", C.muted, 0, 10)
    end
    return lay.y
end

function Preview:Show(mountID)
    self.frame = self.frame or create()
    local f = self.frame
    local m = ns.MountJournal:GetMount(mountID)
    local extra = ns.MountJournal:GetMountExtra(mountID) or {}
    f.mountID = mountID
    f.star:SetMount(mountID)
    f.title:SetText(m and m.name or ("#" .. mountID))
    f.scrollChild:SetHeight(math.max(1, build(f, mountID, m, extra)))
    f.scroll:SetVerticalScroll(0)
    f.scroll:UpdateScrollChildRect()
    f.journal:SetScript("OnClick", function()
        if not ns.MountJournal:OpenInJournal(mountID) then ns:Print(L["JOURNAL_COMBAT"]) end
    end)
    f:Show()
    showModel(f, extra)
end

--- Re-reads states (lockouts / achievements arrived) if the panel is open.
function Preview:Refresh()
    local f = self.frame
    if f and f:IsShown() and f.mountID then
        local scrollPos = f.scroll:GetVerticalScroll()
        local m = ns.MountJournal:GetMount(f.mountID)
        local extra = ns.MountJournal:GetMountExtra(f.mountID) or {}
        f.scrollChild:SetHeight(math.max(1, build(f, f.mountID, m, extra)))
        f.scroll:UpdateScrollChildRect()
        f.scroll:SetVerticalScroll(math.min(scrollPos, f.scroll:GetVerticalScrollRange()))
    end
end

-- Small model popup (mini window): only the 3D model, next to `anchor`.
-- Independent of the main window, which may be closed.
local POP_W, POP_H = 220, 200
local function createPopup()
    local C = ns.UI.COLORS
    local f = CreateFrame("Frame", "AnimalitosPlannerModelPopup", UIParent, "BackdropTemplate")
    f:SetSize(POP_W, POP_H + 30)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    ns.UI.StylePanel(f, C.background, { border = { C.accent[1], C.accent[2], C.accent[3], 0.45 }, noSheen = true })
    local close = ns.UI.CloseButton(f)
    close:SetPoint("TOPRIGHT", -4, -3)
    f.title = ns.UI.fs(f, "title")
    f.title:SetPoint("TOPLEFT", 10, -9)
    f.title:SetPoint("RIGHT", close, "LEFT", -4, 0)
    f.title:SetWordWrap(false)
    local holder = CreateFrame("Frame", nil, f, "BackdropTemplate")
    holder:SetPoint("TOPLEFT", 6, -28)
    holder:SetPoint("BOTTOMRIGHT", -6, 6)
    ns.UI.StylePanel(holder)
    local ok, scene = pcall(CreateFrame, "ModelScene", nil, holder, "ModelSceneMixinTemplate")
    if ok and scene then
        scene:SetPoint("TOPLEFT", 4, -4)
        scene:SetPoint("BOTTOMRIGHT", -4, 4)
        scene:EnableMouse(true)
        f.scene = scene
    end
    f.model = CreateFrame("PlayerModel", nil, holder)
    f.model:SetPoint("TOPLEFT", 4, -4)
    f.model:SetPoint("BOTTOMRIGHT", -4, 4)
    f.model:Hide()
    f.hint = ns.UI.fs(holder, "GameFontDisableSmall")
    f.hint:SetPoint("BOTTOMRIGHT", -6, 4)
    f.hint:SetText(L["PREVIEW_DRAG"])
    return f
end

--- Shows (or, same mount again, hides) the model popup beside `anchor`.
function Preview:TogglePopup(mountID, anchor)
    local f = self.popup
    if f and f:IsShown() and f.mountID == mountID then
        f:Hide()
        return
    end
    self.popup = f or createPopup()
    f = self.popup
    local m = ns.MountJournal:GetMount(mountID)
    f.mountID = mountID
    f.title:SetText(m and m.name or ("#" .. mountID))
    f:SetScale(anchor:GetEffectiveScale() / UIParent:GetEffectiveScale())
    f:ClearAllPoints()
    -- Beside the anchor, on the side with more room.
    if (anchor:GetLeft() or 0) > GetScreenWidth() / 2 then
        f:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -4, 0)
    else
        f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
    end
    f:Show()
    showModel(f, ns.MountJournal:GetMountExtra(mountID) or {})
end

function Preview:HidePopup()
    if self.popup then self.popup:Hide() end
end

--- Click on the same mount again closes the preview.
function Preview:Toggle(mountID)
    local f = self.frame
    if f and f:IsShown() and f.mountID == mountID then
        f:Hide()
    else
        self:Show(mountID)
    end
end
