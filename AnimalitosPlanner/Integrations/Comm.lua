-- Group communication (part 1 of the group route): finds who in the party
-- or raid also runs AnimalitosPlanner, with their version and faction.
-- Hidden addon messages only (C_ChatInfo.SendAddonMessage); nothing goes
-- to chat. Never sent in combat: queued until combat ends.
--
-- Messages are "KIND\tfield\tfield...":
--   HELLO <version> <faction>  on joining a group / login; peers answer HI
--   HI    <version> <faction>  answer to HELLO (never answered, no loops)
local _, ns = ...

local Comm = {}
ns.Comm = Comm

local PREFIX = "AnimPlan" -- max 16 characters
Comm.PREFIX = PREFIX
Comm.peers = {} -- [full name] = { name, version, faction, seen }

local registered = false
local queued = {} -- messages waiting for combat to end

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

-- Sends now, or after combat. Errors (restricted channel, throttling) are
-- kept for /aplan group instead of shown.
local function send(kind, ...)
    local ch = channel()
    if not ch or not register() then return end
    local msg = table.concat({ kind, ... }, "\t")
    if InCombatLockdown() then
        queued[kind] = msg
        return
    end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, ch)
    Comm.lastSend = { kind = kind, channel = ch, ok = ok, result = result, at = time() }
end

local function hello(kind)
    send(kind, ns.VERSION, (UnitFactionGroup("player")) or "?")
end

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
        return
    end
    for full, p in pairs(Comm.peers) do
        if not (UnitInParty(p.name) or UnitInRaid(p.name)) then Comm.peers[full] = nil end
    end
end

local function changed()
    ns:Debounce("comm-ui", 0.5, function() ns.UI:Refresh() end)
end

ns:On("CHAT_MSG_ADDON", function(_, prefix, text, _, sender)
    if prefix ~= PREFIX or not sender then return end
    if sender == myself() or Ambiguate(sender, "none") == UnitName("player") then return end
    local kind, version, faction = strsplit("\t", text)
    if kind ~= "HELLO" and kind ~= "HI" then return end
    local known = Comm.peers[sender]
    Comm.peers[sender] = { name = Ambiguate(sender, "none"), version = version or "?",
        faction = faction or "?", seen = time() }
    if kind == "HELLO" then hello("HI") end
    if not known then changed() end
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
    for kind in pairs(pending) do hello(kind) end
end)

--- /aplan group: peers, channel and the last send (to test the link).
function Comm:Debug()
    print(("  prefix %s registered=%s channel=%s"):format(PREFIX, tostring(register()), tostring(channel())))
    local last = self.lastSend
    if last then
        print(("  last send: %s on %s ok=%s result=%s (%ds ago)"):format(last.kind, last.channel,
            tostring(last.ok), tostring(last.result), time() - last.at))
    end
    local list = self:Peers()
    if #list == 0 then print("  " .. ns.L["COMM_NOBODY"]) end
    for _, p in ipairs(list) do
        print(("  %s: v%s %s"):format(p.name, p.version, p.faction))
    end
    hello("HELLO")
end
