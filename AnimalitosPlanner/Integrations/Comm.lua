-- Group communication for the group route. Hidden addon messages only
-- (C_ChatInfo.SendAddonMessage); nothing goes to chat. Never sent in
-- combat: queued until combat ends.
--
-- Part 1, presence: HELLO / HI <version> <faction> (HELLO on joining a
-- group or login, peers answer HI; HI is never answered, so no loops).
-- Part 2, needs: each addon shares, per instance, the mounts it can loot
-- now (ready) or already killed this reset (locked). The group route is
-- the union of everyone's steps.
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
-- /aplan group instead of shown.
local function rawSend(kind, msg)
    local ch = channel()
    if not ch or not register() then return end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, ch)
    Comm.lastSend = { kind = kind, channel = ch, ok = ok, result = result, at = time() }
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
    for i = 1, n do
        rawSend(kind, table.concat({ kind, seqOut, i, n, data:sub((i - 1) * PIECE + 1, i * PIECE) }, "\t"))
    end
end

local function hello(kind)
    send(kind, ns.VERSION, (UnitFactionGroup("player")) or "?")
end

-- Encoding ---------------------------------------------------------------------
-- Needs: "jid:ready.ready/locked.locked;jid:..." (mount IDs).
local function encodeNeeds()
    local parts = {}
    local entries = ns.FarmList:Build()
    -- Each player shares the route they chose (My route, Show filter); the
    -- group route is the union.
    local jids = {}
    for _, e in ipairs(entries or {}) do
        if type(e.jid) == "number" and e.jid > 0 then
            local own = ns.Planner:OwnStep(e)
            if own then jids[#jids + 1] = own end
        end
    end
    table.sort(jids, function(a, b) return a.jid < b.jid end)
    for _, e in ipairs(jids) do
        local ready, locked = {}, {}
        for id, m in pairs(e.mounts) do
            if #m.ready > 0 then ready[#ready + 1] = id
            elseif #m.locked > 0 then locked[#locked + 1] = id end
        end
        if #ready > 0 or #locked > 0 then
            table.sort(ready)
            table.sort(locked)
            parts[#parts + 1] = ("%d:%s/%s"):format(e.jid, table.concat(ready, "."), table.concat(locked, "."))
        end
    end
    return table.concat(parts, ";")
end

local function decodeIDs(s)
    local out = {}
    for id in (s or ""):gmatch("%d+") do out[#out + 1] = tonumber(id) end
    return out
end

local function decodeNeeds(data)
    local needs = {}
    for jid, ready, locked in data:gmatch("(%d+):([%d%.]*)/([%d%.]*)") do
        needs[tonumber(jid)] = { ready = decodeIDs(ready), locked = decodeIDs(locked) }
    end
    return needs
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

--- Shares this character's needs (debounced; only when they changed, or
--- force after a new peer).
function Comm:ShareNeeds(force)
    if force then lastNeeds = nil end
    if not IsInGroup() or not next(self.peers) then return end
    ns:Debounce("comm-needs", 3, function()
        local data = encodeNeeds()
        if data == lastNeeds then return end
        lastNeeds = data
        sendData("NEED", data)
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

local function received(sender, kind, data)
    local p = Comm.peers[sender]
    if not p then return end
    if kind == "NEED" then
        p.needs = decodeNeeds(data)
    elseif kind == "DONE" then
        p.done = decodeDone(data)
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
            -- A new peer: send it what we know.
            Comm:ShareNeeds(true)
            lastDone = nil
            changed()
        end
    elseif kind == "NEED" or kind == "DONE" then
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

--- [jid] = { { name, ready = {mountID...}, locked = {...} } } from the peers.
function Comm:NeedsByJid()
    local out = {}
    for _, p in pairs(self.peers) do
        for jid, n in pairs(p.needs or {}) do
            out[jid] = out[jid] or {}
            table.insert(out[jid], { name = p.name, ready = n.ready, locked = n.locked })
        end
    end
    for _, list in pairs(out) do table.sort(list, function(a, b) return a.name < b.name end) end
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
        for _ in pairs(p.needs or {}) do nNeeds = nNeeds + 1 end
        for _ in pairs(p.done or {}) do nDone = nDone + 1 end
        print(("  %s: v%s %s, leader=%s, needs %d instances, done %d"):format(p.name, p.version, p.faction,
            tostring(UnitIsGroupLeader(p.name)), nNeeds, nDone))
    end
    hello("HELLO")
    self:ShareNeeds(true)
end
