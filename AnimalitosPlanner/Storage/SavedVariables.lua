-- SavedVariables: initialization, schema version and sequential migrations.
local _, ns = ...

local Storage = {}
ns.Storage = Storage

Storage.SCHEMA_VERSION = 1

local function defaults()
    return {
        version = Storage.SCHEMA_VERSION,
        settings = {
            plannerMode = "hybrid",
            navigation = "native", -- "native" | "tomtom"
            maxTier = 10,          -- newest EJ tier in "farmable now" (10 = Dragonflight)
        },
        plans = {},
        characterData = {}, -- [characterKey] = { level, faction, class, lastSeen }
        userData = {
            favorites = {},
            excludedMounts = {},
            customTargets = {},
        },
        ui = {},
        diagnostics = nil, -- filled by /aplan probe
    }
end

-- Fill missing keys without touching existing user data.
local function fillDefaults(target, source)
    for k, v in pairs(source) do
        if target[k] == nil then
            target[k] = type(v) == "table" and CopyTable(v) or v
        elseif type(v) == "table" and type(target[k]) == "table" then
            fillDefaults(target[k], v)
        end
    end
end

-- migrations[n] upgrades a database from version n-1 to n.
-- Add new entries here; never edit an existing one after release.
local migrations = {
    -- [2] = function(db) ... end,
}

local function migrate(db)
    local from = tonumber(db.version) or 0
    for v = from + 1, Storage.SCHEMA_VERSION do
        local step = migrations[v]
        if step then
            local ok, err = pcall(step, db)
            if not ok then
                ns:Print("|cffff5555Migration to schema " .. v .. " failed:|r " .. tostring(err))
                return false -- keep the old version so the migration can be retried
            end
        end
        db.version = v -- only written after the step succeeded
    end
    return true
end

function Storage:Init()
    if type(AnimalitosPlannerDB) ~= "table" then
        AnimalitosPlannerDB = defaults()
    else
        if (tonumber(AnimalitosPlannerDB.version) or 0) < Storage.SCHEMA_VERSION then
            migrate(AnimalitosPlannerDB)
        end
        fillDefaults(AnimalitosPlannerDB, defaults())
    end
    self.db = AnimalitosPlannerDB
    return self.db
end

function Storage:TouchCharacter()
    local key = ns:GetCharacterKey()
    local _, classFile = UnitClass("player")
    self.db.characterData[key] = self.db.characterData[key] or {}
    local c = self.db.characterData[key]
    c.level = UnitLevel("player")
    c.faction = UnitFactionGroup("player")
    c.class = classFile
    c.lastSeen = time()
    return key
end
