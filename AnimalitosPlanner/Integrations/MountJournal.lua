-- Adapter over C_MountJournal. All direct Mount Journal calls live here so
-- signature changes between client builds only need fixing in one place.
local _, ns = ...

local MJ = {}
ns.MountJournal = MJ

function MJ:IsAvailable()
    return C_MountJournal ~= nil
        and C_MountJournal.GetMountIDs ~= nil
        and C_MountJournal.GetMountInfoByID ~= nil
end

--- Returns a normalized record for a mountID, or nil.
--- Field order follows GetMountInfoByID as of 12.x; validated by /aplan probe.
function MJ:GetMount(mountID)
    local name, spellID, icon, _, isUsable, sourceType, isFavorite,
          isFactionSpecific, faction, shouldHideOnChar, isCollected, id =
        C_MountJournal.GetMountInfoByID(mountID)
    if not name then return nil end
    if not sourceType or sourceType == 0 then sourceType = MJ:InferSourceType(id or mountID) or sourceType end
    return {
        mountID = id or mountID,
        name = name,
        spellID = spellID,
        icon = icon,
        isUsable = isUsable,
        sourceType = sourceType,
        isFavorite = isFavorite,
        isFactionSpecific = isFactionSpecific,
        faction = faction,
        shouldHideOnChar = shouldHideOnChar,
        isCollected = isCollected,
    }
end

--- Model and text data for the preview panel, or nil.
--- Return order of GetMountInfoExtraByID as used by Blizzard's Mount Journal;
--- [3] sourceText was validated by /aplan probe (see CLAUDE.md §5).
function MJ:GetMountExtra(mountID)
    if not C_MountJournal.GetMountInfoExtraByID then return nil end
    local creatureDisplayID, description, sourceText, isSelfMount, mountTypeID,
          uiModelSceneID, animID, spellVisualKitID, disablePlayerMountPreview =
        C_MountJournal.GetMountInfoExtraByID(mountID)
    if not creatureDisplayID and not description then return nil end
    return {
        creatureDisplayID = creatureDisplayID,
        description = description,
        sourceText = sourceText,
        isSelfMount = isSelfMount,
        mountTypeID = mountTypeID,
        uiModelSceneID = uiModelSceneID,
        animID = animID,
        spellVisualKitID = spellVisualKitID,
        disablePlayerMountPreview = disablePlayerMountPreview,
    }
end

--- Opens Blizzard's Mount Journal on this mount. Returns false in combat.
function MJ:OpenInJournal(mountID)
    if InCombatLockdown() then return false end
    if not CollectionsJournal then
        local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
        if load then load("Blizzard_Collections") end
    end
    if SetCollectionsJournalShown then
        SetCollectionsJournalShown(true, COLLECTIONS_JOURNAL_TAB_INDEX_MOUNTS or 1)
    elseif ToggleCollectionsJournal then
        ToggleCollectionsJournal(1)
    end
    if MountJournal_SelectByMountID then MountJournal_SelectByMountID(mountID) end
    return true
end

--- Iterates every mount in the journal. Returns false if the journal is not ready.
function MJ:ForEach(callback)
    if not self:IsAvailable() then return false end
    local ids = C_MountJournal.GetMountIDs()
    if not ids or #ids == 0 then return false end
    for i = 1, #ids do
        local m = self:GetMount(ids[i])
        if m then callback(m) end
    end
    return true
end

--- mountID taught by an item, or nil (also nil while the item is not cached).
function MJ:GetMountFromItem(itemID)
    if not (itemID and C_MountJournal.GetMountFromItem) then return nil end
    return C_MountJournal.GetMountFromItem(itemID)
end

--- Journal source text without escape codes: old (|cAARRGGBB) and named
--- (|cnNAME:) colors, |r, textures, atlases, links; |n becomes a new line.
function MJ:PlainSourceText(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]*:", ""):gsub("|r", "")
    text = text:gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|H.-|h", ""):gsub("|h", "")
    text = text:gsub("|n", "\n"):gsub("\r", "")
    return text
end

--- /aplan unknown: mounts still without a source type, with their raw text
--- (pipes doubled so chat shows the codes).
function MJ:DebugUnknownSources()
    local n = 0
    self:ForEach(function(m)
        if (not m.sourceType or m.sourceType == 0) and not m.shouldHideOnChar then
            n = n + 1
            if n <= 15 then
                local extra = self:GetMountExtra(m.mountID)
                local raw = extra and extra.sourceText or "(nil)"
                print(("  %s (%d): %s"):format(m.name, m.mountID, raw:gsub("|", "||")))
            end
        end
    end)
    print(("  %d without a source type"):format(n))
end

-- Some newer mounts come with sourceType 0 ("Unknown source") although their
-- journal text starts with a source label ("Vendor: Ando the Gat"). That first
-- label is matched against the localized BATTLE_PET_SOURCE_n names. Cached
-- per mount (false = no match).
local inferred, labelToType = {}, nil
function MJ:InferSourceType(mountID)
    if inferred[mountID] ~= nil then return inferred[mountID] or nil end
    if not labelToType then
        labelToType = {}
        for n = 1, 20 do
            local label = _G["BATTLE_PET_SOURCE_" .. n]
            if label then labelToType[label:lower()] = n end
        end
    end
    local extra = self:GetMountExtra(mountID)
    local text = extra and extra.sourceText
    if not text or text == "" then return nil end -- not loaded yet: try again later
    -- Any label of the text that is a source name wins (in order): the
    -- first label is not always the source (icons, "Zone:", new color codes).
    local found = false
    local plain = self:PlainSourceText(text)
    for label in plain:gmatch("([^:\n]+):") do
        local n = labelToType[strtrim(label):lower()]
        if n then found = n break end
    end
    inferred[mountID] = found
    return found or nil
end

--- Localized label for a Mount Journal sourceType index.
--- The journal source filter reuses the BATTLE_PET_SOURCE_n global strings.
function MJ:GetSourceTypeLabel(sourceType)
    return (sourceType and _G["BATTLE_PET_SOURCE_" .. sourceType]) or ns.L["UNKNOWN_SOURCE"]
end
