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

--- Localized label for a Mount Journal sourceType index.
--- The journal source filter reuses the BATTLE_PET_SOURCE_n global strings.
function MJ:GetSourceTypeLabel(sourceType)
    return (sourceType and _G["BATTLE_PET_SOURCE_" .. sourceType]) or ns.L["UNKNOWN_SOURCE"]
end
