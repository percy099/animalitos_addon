-- AnimalitosPlanner - Core
-- Shared namespace, localization table and a small event bus.
-- Other files receive the same `ns` table through the addon vararg.

local ADDON_NAME, ns = ...

ns.ADDON_NAME = ADDON_NAME
ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")) or "dev"

-- Localization: enUS fills defaults, other locales override.
-- Missing keys fall back to the key itself so the UI never shows nil.
ns.L = setmetatable({}, {
    __index = function(_, key) return key end,
})

-- ---------------------------------------------------------------------------
-- Event bus
-- ---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {} -- event -> { callback, ... }
ns.unknownEvents = {}

local function isEventValid(event)
    if C_EventUtils and C_EventUtils.IsEventValid then
        return C_EventUtils.IsEventValid(event)
    end
    return true
end

--- Register a callback for a game event. Unknown events are recorded instead
--- of raising an error, so the addon survives API changes between builds.
function ns:On(event, callback)
    if not handlers[event] then
        if not isEventValid(event) or not pcall(eventFrame.RegisterEvent, eventFrame, event) then
            ns.unknownEvents[event] = true
            return false
        end
        handlers[event] = {}
    end
    table.insert(handlers[event], callback)
    return true
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], event, ...)
        if not ok then
            ns:Print("|cffff5555Error|r " .. event .. ": " .. tostring(err))
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
function ns:Print(msg)
    print("|cffa88ad7AnimalitosPlanner|r: " .. tostring(msg))
end

--- Run `fn` once after `delay` seconds; repeated calls with the same key
--- inside the window collapse into a single call.
local pending = {}
function ns:Debounce(key, delay, fn)
    if pending[key] then return end
    pending[key] = true
    C_Timer.After(delay, function()
        pending[key] = nil
        fn()
    end)
end

--- Stable identity for the active character: name-realm-region.
function ns:GetCharacterKey()
    local name = UnitName("player") or "?"
    local realm = GetNormalizedRealmName() or GetRealmName() or "?"
    local region = GetCurrentRegionName and GetCurrentRegionName() or tostring(GetCurrentRegion and GetCurrentRegion() or "?")
    return name .. "-" .. realm .. "-" .. region
end
