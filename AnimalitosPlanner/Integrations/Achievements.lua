-- Adapter over the achievement APIs: finds every achievement whose reward is
-- a mount and reads its progress. Everything comes from the client; nothing
-- is stored in the dataset.
local _, ns = ...

local Achievements = {}
ns.Achievements = Achievements

-- Top-level category (e.g. "Dungeons & Raids") of an achievement category.
local function topCategory(catID)
    local guard = 0
    while catID and guard < 6 do
        local _, parent = GetCategoryInfo(catID)
        if not parent or parent == -1 then return catID end
        catID, guard = parent, guard + 1
    end
    return catID
end

local function categoryName(catID)
    return (catID and GetCategoryInfo(catID)) or "?"
end

-- done, total for the progress bar.
local function progress(id, completed)
    local n = GetAchievementNumCriteria(id) or 0
    if n == 0 then return completed and 1 or 0, 1 end
    if n == 1 then
        local _, _, done, quantity, required = GetAchievementCriteriaInfo(id, 1)
        if required and required > 1 then
            return math.min(quantity or 0, required), required
        end
        return (done or completed) and 1 or 0, 1
    end
    local count = 0
    for i = 1, n do
        local _, _, done = GetAchievementCriteriaInfo(id, i)
        if done then count = count + 1 end
    end
    return count, n
end

-- "Reward: Rusted Proto-Drake" -> "rusted proto-drake" (prefix is localized).
local function rewardName(text)
    if not text or text == "" then return nil end
    local after = text:match("^[^:]+:%s*(.+)$") or text
    return strtrim(after):lower()
end

--- Every mount-reward achievement (account-wide progress).
--- mountsByName = { [lowercase mount name] = mountID } as a fallback when the
--- reward item is not cached or the mount is granted without an item.
--- Returns list, uncachedItemIDs.
---   entry = { id, name, icon, completed, mountID, done, total, top, topName, category }
function Achievements:ScanMounts(mountsByName)
    local out, uncached, seen = {}, {}, {}
    if not GetCategoryList then return out, uncached end
    for _, cat in ipairs(GetCategoryList() or {}) do
        local num = GetCategoryNumAchievements(cat, true) or 0
        for i = 1, num do
            local id, name, _, completed, _, _, _, _, _, icon, rewardText = GetAchievementInfo(cat, i)
            if id and not seen[id] and rewardText and rewardText ~= "" then
                seen[id] = true
                local itemID = C_AchievementInfo and C_AchievementInfo.GetRewardItemID
                    and C_AchievementInfo.GetRewardItemID(id)
                local mountID = ns.MountJournal:GetMountFromItem(itemID)
                if not mountID and mountsByName then
                    mountID = mountsByName[rewardName(rewardText) or ""]
                end
                if not mountID and itemID and C_Item and C_Item.IsItemDataCachedByID
                    and not C_Item.IsItemDataCachedByID(itemID) then
                    uncached[#uncached + 1] = itemID
                end
                if mountID then
                    local done, total = progress(id, completed)
                    local top = topCategory(cat)
                    out[#out + 1] = {
                        id = id, name = name, icon = icon, completed = completed,
                        mountID = mountID, done = done, total = total,
                        top = top, topName = categoryName(top), category = categoryName(cat),
                    }
                end
            end
        end
    end
    return out, uncached
end

-- Criteria type 8 = "complete another achievement" (assetID = its ID).
local CRITERIA_ACHIEVEMENT = 8

--- Criteria still missing for an achievement, each with the text that says
--- what to do: { text, search } (search = lowercase text, plus the
--- sub-achievement's name and description for meta achievements).
function Achievements:MissingCriteria(id)
    local out = {}
    local n = GetAchievementNumCriteria(id) or 0
    for i = 1, n do
        local text, ctype, done, _, _, _, _, assetID = GetAchievementCriteriaInfo(id, i)
        if not done then
            local search = text or ""
            if ctype == CRITERIA_ACHIEVEMENT and assetID and assetID > 0 then
                local _, subName, _, _, _, _, _, subDesc = GetAchievementInfo(assetID)
                search = ("%s %s %s"):format(search, subName or "", subDesc or "")
            end
            out[#out + 1] = { text = (text ~= "" and text) or "?", search = search:lower() }
        end
    end
    if n == 0 then
        -- Single-step achievement: its description says where.
        local _, name, _, completed, _, _, _, desc = GetAchievementInfo(id)
        if not completed then
            out[1] = { text = name or "?", search = ((name or "") .. " " .. (desc or "")):lower() }
        end
    end
    return out
end

--- Asks the client to cache reward items (a later scan can then resolve them).
function Achievements:RequestItems(itemIDs)
    if not (C_Item and C_Item.RequestLoadItemDataByID) then return end
    for _, id in ipairs(itemIDs) do C_Item.RequestLoadItemDataByID(id) end
end

--- Chat/tooltip link (the tooltip lists each criterion with your progress).
function Achievements:Link(id)
    return GetAchievementLink and GetAchievementLink(id)
end

--- Opens Blizzard's achievement window on this achievement (not in combat).
function Achievements:Open(id)
    if InCombatLockdown() then return false end
    if not AchievementFrame then
        local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
        if load then pcall(load, "Blizzard_AchievementUI") end
    end
    if OpenAchievementFrameToAchievement then
        OpenAchievementFrameToAchievement(id)
        return true
    end
    if AchievementFrame_SelectAchievement then
        if AchievementFrame and not AchievementFrame:IsShown() then ShowUIPanel(AchievementFrame) end
        AchievementFrame_SelectAchievement(id)
        return true
    end
    return false
end
