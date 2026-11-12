-- Group communication for the group route. Hidden addon messages only
-- (C_ChatInfo.SendAddonMessage); nothing goes to chat. Never sent in
-- combat: queued until combat ends.
--
-- Part 1, presence: HELLO / HI <version> <faction> (HELLO on joining a
-- group or login, peers answer HI; HI is never answered, so no loops).
-- Part 2, status (STAT): each addon shares, per instance, the mounts in its
-- own route, every mount it still misses there (lootable now / killed this
-- reset / other) and its lockouts. The group route is the union of
-- everyone's routes; each step says, per player, CD and what they miss.
-- Part 3, progress: the leader shares which steps are done; the others
-- follow it.
-- Needs and progress can be longer than one message (255 bytes): they go
-- in numbered pieces "KIND <seq> <i> <n> <piece>" and are put together on
-- arrival.
local _, ns = ...

local Comm = {}
ns.Comm = Comm

local PREFIX = "AnimPlan" -- max 16 characters
local PIECE = 200         -- bytes of data per message (room for the header)
Comm.PREFIX = PREFIX
Comm.peers = {} -- [full name] = { name, version, faction, seen, needs, done }

local registered = false
local queued = {}     -- kind -> function to send again after combat
local incoming = {}   -- [sender][kind] = { seq, n, parts }
local seqOut = 0

local function channel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

local function register()
    if registered then return true end
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        registered = C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) and true or false
        -- Already registered (after /reload) also counts.
        if not registered and C_ChatInfo.IsAddonMessagePrefixRegistered then
            registered = C_ChatInfo.IsAddonMessagePrefixRegistered(PREFIX) and true or false
        end
    end
    return registered
end

local function myself()
    local name, realm = UnitFullName("player")
    return name and (name .. "-" .. (realm or GetNormalizedRealmName() or "")) or "?"
end

-- One raw message. Errors (restricted channel, throttling) are kept for
-- /aplan group instead of shown. Returns true when the client throttled it.
local THROTTLED = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.AddonMessageThrottle
local function rawSend(kind, msg)
    local ch = channel()
    if not ch or not register() then return false end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, ch)
    Comm.lastSend = { kind = kind, channel = ch, ok = ok, result = result, at = time() }
    return ok and THROTTLED ~= nil and result == THROTTLED
end

-- Pieces wait in a queue: a few at once, then one per second (the client
-- drops addon messages past a short burst).
local outbox, pumping = {}, false
local BURST = 6
local function pump()
    local sent = 0
    while outbox[1] do
        if sent >= BURST then break end
        local m = outbox[1]
        if rawSend(m[1], m[2]) then break end -- throttled: try again later
        table.remove(outbox, 1)
        sent = sent + 1
    end
    pumping = outbox[1] ~= nil
    if pumping then C_Timer.After(1.2, pump) end
end


local function send(kind, ...)
    local args = { ... }
    if InCombatLockdown() then
        queued[kind] = function() send(kind, unpack(args)) end
        return
    end
    rawSend(kind, table.concat({ kind, ... }, "\t"))
end

-- Long data in numbered pieces.
local function sendData(kind, data)
    if InCombatLockdown() then
        queued[kind] = function() sendData(kind, data) end
        return
    end
    seqOut = seqOut % 9999 + 1
    local n = math.max(1, math.ceil(#data / PIECE))
    -- Drop the waiting pieces of an older copy, then queue the new ones.
    for i = #outbox, 1, -1 do
        if outbox[i][1] == kind then table.remove(outbox, i) end
    end
    for i = 1, n do
        outbox[#outbox + 1] = { kind, table.concat({ kind, seqOut, i, n, data:sub((i - 1) * PIECE + 1, i * PIECE) }, "\t") }
    end
    if not pumping then pump() end
end

local function hello(kind)
    send(kind, ns.VERSION, (UnitFactionGroup("player")) or "?")
end

-- Status -------------------------------------------------------------------------
-- What each player shares (STAT), per dataset instance:
--   [jid] = { pick = {mountID...},  -- mounts in the route this player chose
--             ready, locked, other,  -- every mount of the instance it still
--                                    -- misses: lootable now / killed this
--                                    -- reset / anything else (unknown, faction)
--             cd = {difficultyID...} } -- its lockouts there (even when it has
--                                      -- every mount: it may not enter)
-- A mount of the instance in none of the lists: the player has it.
local EMPTY = { pick = {}, ready = {}, locked = {}, other = {}, cd = {} }
Comm.EMPTY = EMPTY

local function collected(id)
    local m = ns.MountJournal:GetMount(id)
    if m then return m.isCollected and true or false end
    local info = { C_MountJournal.GetMountInfoByID(id) }
    return info[11] and true or false
end

local statusAt, statusCache
--- This player's status (same shape as a peer's), rebuilt once per frame.
function Comm:MyStatus()
    local now = GetTime()
    if statusCache and statusAt == now then return statusCache end
    local entries = ns.FarmList:Build()
    local full = {}
    for _, e in ipairs(entries or {}) do
        if type(e.jid) == "number" then full[e.jid] = e end
    end
    local out = {}
    local function get(jid)
        local s = out[jid]
        if not s then
            s = { pick = {}, ready = {}, locked = {}, other = {}, cd = {} }
            out[jid] = s
        end
        return s
    end
    local seen = {}
    for _, src in ipairs(ns.Data.sources) do
        local jid, id = src.journalInstanceID, src.mountID
        local key = jid .. ":" .. id
        if not seen[key] and not collected(id) then
            seen[key] = true
            local m = full[jid] and full[jid].mounts[id]
            local s = get(jid)
            if m and #m.ready > 0 then s.ready[#s.ready + 1] = id
            elseif m and #m.locked > 0 then s.locked[#s.locked + 1] = id
            else s.other[#s.other + 1] = id end
        end
    end
    -- The route this player picked (My route or the full one, its Show filter).
    for jid, e in pairs(full) do
        local own = ns.Planner:OwnStep(e)
        if own then
            local s = get(jid)
            for id in pairs(own.mounts) do s.pick[#s.pick + 1] = id end
        end
    end
    -- Lockouts.
    if ns.Lockouts.byMap then
        for jid, inst in pairs(ns.Data.instances) do
            local diffs = inst.mapID and ns.Lockouts.byMap[inst.mapID]
            if diffs and next(diffs) then
                local s = get(jid)
                for d in pairs(diffs) do s.cd[#s.cd + 1] = d end
            end
        end
    end
    statusCache, statusAt = out, now
    return out
end

-- Numbers in base 36 (shorter messages): "jid[*]:pick/ready/locked/other/cd;..."
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function b36(n)
    local neg = n < 0
    n = math.abs(n)
    local s = ""
    repeat
        local r = n % 36
        s = DIGITS:sub(r + 1, r + 1) .. s
        n = math.floor(n / 36)
    until n == 0
    return (neg and "-" or "") .. s
end

local function encodeList(list)
    local copy = {}
    for i, v in ipairs(list) do copy[i] = v end
    table.sort(copy)
    for i, v in ipairs(copy) do copy[i] = b36(v) end
    return table.concat(copy, ".")
end

local function encodeStatus()
    local status = Comm:MyStatus()
    local jids = {}
    for jid in pairs(status) do jids[#jids + 1] = jid end
    table.sort(jids)
    local parts = {}
    for _, jid in ipairs(jids) do
        local s = status[jid]
        parts[#parts + 1] = ("%s:%s/%s/%s/%s/%s"):format(b36(jid), encodeList(s.pick), encodeList(s.ready),
            encodeList(s.locked), encodeList(s.other), encodeList(s.cd))
    end
    return table.concat(parts, ";")
end

local function decodeList(s)
    local out = {}
    for v in (s or ""):gmatch("[%w]+") do out[#out + 1] = tonumber(v, 36) end
    return out
end

local function decodeStatus(data)
    local status = {}
    for item in data:gmatch("[^;]+") do
        local jid, pick, ready, locked, other, cd = item:match("^(%-?%w+):([%w%.]*)/([%w%.]*)/([%w%.]*)/([%w%.]*)/([%w%.]*)$")
        local n = jid and (jid:sub(1, 1) == "-" and -tonumber(jid:sub(2), 36) or tonumber(jid, 36))
        if n then
            status[n] = { pick = decodeList(pick), ready = decodeList(ready), locked = decodeList(locked),
                other = decodeList(other), cd = decodeList(cd) }
        end
    end
    return status
end
-- Done steps: "jid,jid,ev123,...".
local function decodeDone(data)
    local done = {}
    for key in data:gmatch("[^,]+") do done[tonumber(key) or key] = true end
    return done
end

-- Peers --------------------------------------------------------------------------
--- Peers still in the group (others only), sorted by name.
function Comm:Peers()
    local list = {}
    for _, p in pairs(self.peers) do list[#list + 1] = p end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- Drops peers who left the group.
local function prune()
    if not IsInGroup() then
        wipe(Comm.peers)
        wipe(incoming)
        return
    end
    for full, p in pairs(Comm.peers) do
        if not (UnitInParty(p.name) or UnitInRaid(p.name)) then
            Comm.peers[full] = nil
            incoming[full] = nil
        end
    end
end

local function changed()
    ns:Debounce("comm-ui", 0.5, function()
        ns.UI:Refresh()
        if ns.PlannerMini then ns.PlannerMini:Refresh() end
    end)
end

local lastNeeds, lastDone -- what was sent last (only changes are sent)

--- Shares this character's status (debounced; only when it changed, or
--- force after a new peer).
function Comm:ShareNeeds(force)
    if force then lastNeeds = nil end
    if not IsInGroup() or not next(self.peers) then return end
    ns:Debounce("comm-needs", 3, function()
        local data = encodeStatus()
        if data == lastNeeds then return end
        lastNeeds = data
        sendData("STAT", data)
    end)
end

--- Leader only: shares the done steps of the group route (signature-gated).
function Comm:ShareDone(keys)
    if not (IsInGroup() and UnitIsGroupLeader("player") and next(self.peers)) then return end
    local data = table.concat(keys, ",")
    if data == lastDone then return end
    lastDone = data
    ns:Debounce("comm-done", 1, function() sendData("DONE", lastDone or "") end)
end

--- Any player's Done / undo of a step: everyone with the group route on
--- applies it to its own marks. Not deduplicated, so quick clicks all arrive.
function Comm:ShareMark(jid, done)
    if not self:GroupActive() then return end
    outbox[#outbox + 1] = { "MARK", table.concat({ "MARK", tostring(jid), done and "1" or "0" }, "\t") }
    if not pumping then pump() end
end

-- Difficulty: members do not always see the one the leader picked, so
-- the leader sends it (DIFF <dungeon> <raid> <legacy size>) when it
-- changes, to a new peer and when asked.
function Comm:ShareDifficulty()
    if not (IsInGroup() and UnitIsGroupLeader("player") and next(self.peers)) then return end
    ns:Debounce("comm-diff", 0.5, function()
        send("DIFF", GetDungeonDifficultyID() or 0, GetRaidDifficultyID() or 0,
            GetLegacyRaidDifficultyID and GetLegacyRaidDifficultyID() or 0)
    end)
end

--- The difficulty the leader (a peer with the addon) has set, or nil:
--- { dungeon, raid, legacy }.
function Comm:LeaderDifficulty()
    local leader = self:LeaderPeer()
    return leader and leader.diff or nil
end

-- A status can get lost (dropped pieces) and is only sent again when it
-- changes: while a peer has none, ask everyone to send theirs again (ASK),
-- a few times.
local asks = 0
local function askMissing()
    local missing = false
    for _, p in pairs(Comm.peers) do
        if not p.status then missing = true end
    end
    if not missing or asks >= 4 or not IsInGroup() then return end
    asks = asks + 1
    send("ASK")
    C_Timer.After(15, askMissing)
end

--- All my manual Done marks (MARKS): the others add the ones they miss,
--- so marks made before the group (or a peer) was there reach everyone.
function Comm:ShareMarks()
    if not self:GroupActive() then return end
    local keys = {}
    for _, key in ipairs(ns.Planner:ManualMarks()) do keys[#keys + 1] = tostring(key) end
    ns:Debounce("comm-marks", 1, function() sendData("MARKS", table.concat(keys, ",")) end)
end

--- The Sync button: send everything again and ask the others for theirs.
function Comm:Sync()
    hello("HELLO")
    self:ShareNeeds(true)
    self:ShareDifficulty()
    self:ShareMarks()
    lastDone = nil
    asks = 0
    send("ASK")
end

local function received(sender, kind, data)
    local p = Comm.peers[sender]
    if not p then return end
    if kind == "STAT" then
        p.status = decodeStatus(data)
        p.statusAt = time()
    elseif kind == "DONE" then
        p.done = decodeDone(data)
    elseif kind == "MARKS" then
        if not Comm:GroupActive() then return end
        for key in data:gmatch("[^,]+") do
            local jid = tonumber(key) or key
            if not ns.Planner:IsManuallyDone(jid) then
                local inst = ns.Data.instances[jid]
                ns.Planner:SetManuallyDone(jid, inst and inst.isRaid, true, true)
            end
        end
    end
    changed()
end

ns:On("CHAT_MSG_ADDON", function(_, prefix, text, _, sender)
    if prefix ~= PREFIX or not sender then return end
    if sender == myself() or Ambiguate(sender, "none") == UnitName("player") then return end
    local kind, a, b, c, d = strsplit("\t", text, 5)
    if kind == "HELLO" or kind == "HI" then
        local known = Comm.peers[sender]
        local p = known or {}
        p.name, p.version, p.faction, p.seen = Ambiguate(sender, "none"), a or "?", b or "?", time()
        Comm.peers[sender] = p
        if kind == "HELLO" then hello("HI") end
        if not known then
            -- A new peer: send it what we know; check later that theirs arrived.
            Comm:ShareNeeds(true)
            Comm:ShareDifficulty()
            Comm:ShareMarks()
            lastDone = nil
            asks = 0
            C_Timer.After(10, askMissing)
            changed()
        end
    elseif kind == "ASK" then
        -- Someone misses a status: send ours again (debounced, so several
        -- askers cost one copy).
        if Comm.peers[sender] then
            Comm:ShareNeeds(true)
            Comm:ShareDifficulty()
            Comm:ShareMarks()
        end
    elseif kind == "DIFF" then
        local p = Comm.peers[sender]
        if p then
            p.diff = { dungeon = tonumber(a), raid = tonumber(b), legacy = tonumber(c) }
            changed()
        end
    elseif kind == "MARK" then
        if not (a and Comm.peers[sender] and Comm:GroupActive()) then return end
        local jid = tonumber(a) or a
        local inst = ns.Data.instances[jid]
        ns.Planner:SetManuallyDone(jid, inst and inst.isRaid, b == "1", true)
        changed()
    elseif kind == "STAT" or kind == "DONE" or kind == "MARKS" then
        local seq, i, n = tonumber(a), tonumber(b), tonumber(c)
        if not (seq and i and n) then return end
        incoming[sender] = incoming[sender] or {}
        local box = incoming[sender][kind]
        if not box or box.seq ~= seq then
            box = { seq = seq, n = n, parts = {}, got = 0 }
            incoming[sender][kind] = box
        end
        if not box.parts[i] then
            box.parts[i] = d or ""
            box.got = box.got + 1
        end
        if box.got == box.n then
            incoming[sender][kind] = nil
            received(sender, kind, table.concat(box.parts))
        end
    end
end)

-- Joining a group, someone joining, login / reload in a group: say hello.
ns:On("GROUP_ROSTER_UPDATE", function()
    local before = #Comm:Peers()
    prune()
    if #Comm:Peers() ~= before then changed() end
    ns:Debounce("comm-hello", 2, function() hello("HELLO") end)
end)
ns:On("PLAYER_ENTERING_WORLD", function()
    register()
    ns:Debounce("comm-hello", 4, function() hello("HELLO") end)
end)
ns:On("PLAYER_DIFFICULTY_CHANGED", function() Comm:ShareDifficulty() end)
ns:On("PLAYER_REGEN_ENABLED", function()
    local pending = queued
    queued = {}
    for _, fn in pairs(pending) do fn() end
end)
-- What can be looted changed: share the needs again (if they changed).
for _, event in ipairs({ "UPDATE_INSTANCE_INFO", "NEW_MOUNT_ADDED", "ENCOUNTER_END" }) do
    ns:On(event, function() Comm:ShareNeeds() end)
end

-- Group route ----------------------------------------------------------------------
--- Is the group route on? The Planner's Group switch, and someone else in
--- the group with the addon.
function Comm:GroupActive()
    return ns.Planner:GroupOn() and IsInGroup() and next(self.peers) ~= nil or false
end

--- The leader, when it is a peer with the addon (nil when it is me or it
--- has no addon).
function Comm:LeaderPeer()
    for _, p in pairs(self.peers) do
        if UnitIsGroupLeader(p.name) then return p end
    end
    return nil
end

--- Faction whose route order the group follows: the leader's.
function Comm:RouteFaction()
    local leader = self:LeaderPeer()
    if leader and (leader.faction == "Alliance" or leader.faction == "Horde") then return leader.faction end
    return nil
end

--- Did the leader mark this step done? (nil when I lead or the leader has
--- no addon.)
function Comm:LeaderDone(key)
    local leader = self:LeaderPeer()
    return leader and leader.done and leader.done[key] or false
end

--- Peers whose status arrived, by name: { { name, status = {[jid] = ...} } }.
function Comm:PeerStatuses()
    local out = {}
    for _, p in ipairs(self:Peers()) do
        if p.status then out[#out + 1] = { name = p.name, status = p.status } end
    end
    return out
end

--- /aplan group: peers, channel and the last send (to test the link).
function Comm:Debug()
    print(("  prefix %s registered=%s channel=%s group route=%s"):format(PREFIX, tostring(register()),
        tostring(channel()), tostring(self:GroupActive())))
    local last = self.lastSend
    if last then
        print(("  last send: %s on %s ok=%s result=%s (%ds ago)"):format(last.kind, last.channel,
            tostring(last.ok), tostring(last.result), time() - last.at))
    end
    local list = self:Peers()
    if #list == 0 then print("  " .. ns.L["COMM_NOBODY"]) end
    for _, p in ipairs(list) do
        local nNeeds, nDone = 0, 0
        for _, s in pairs(p.status or {}) do
            if #s.pick > 0 then nNeeds = nNeeds + 1 end
        end
        for _ in pairs(p.done or {}) do nDone = nDone + 1 end
        print(("  %s: v%s %s, leader=%s, picks in %d instances, done %d"):format(p.name, p.version, p.faction,
            tostring(UnitIsGroupLeader(p.name)), nNeeds, nDone))
        -- Did its status arrive, and is a copy half-way?
        local box = nil
        for full, q in pairs(self.peers) do
            if q == p then box = incoming[full] and incoming[full].STAT end
        end
        print(("    status=%s%s%s"):format(p.status and "yes" or "NO",
            p.statusAt and (" (%ds ago)"):format(time() - p.statusAt) or "",
            box and (", receiving %d/%d pieces"):format(box.got, box.n) or ""))
    end
    print(("  my status: %d bytes, %d pieces waiting to go out, asks %d"):format(#(lastNeeds or ""), #outbox, asks))
    hello("HELLO")
    self:ShareNeeds(true)
    asks = 0
    send("ASK")
end
