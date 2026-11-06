-- Prices in the Mount Journal text and what this character owns: gold and
-- currencies. The journal writes a price as a number followed by an icon:
--   "Cost: 500|TInterface\MoneyFrame\UI-GoldIcon:0|t"   (gold)
--   "Cost: 2000|T1121394:0|t"                           (a currency's icon)
-- Labels are localized, so the price is found by its icon, never by "Cost:".
-- A currency is identified by its icon: every currency ID is read once with
-- C_CurrencyInfo.GetCurrencyInfo and indexed by iconFileID.
local _, ns = ...

local W = {}
ns.Wallet = W

local COIN = { goldicon = 10000, silvericon = 100, coppericon = 1 }

local function coinValue(tex)
    local lower = tostring(tex):lower()
    for key, v in pairs(COIN) do
        if lower:find(key, 1, true) then return v end
    end
    return nil
end

local function fileID(tex)
    local n = tonumber(tex)
    if n then return n end
    if GetFileIDFromPath then return GetFileIDFromPath(tex) end
    return nil
end

local byIcon -- [iconFileID] = currencyID
local function currencyByIcon()
    if byIcon then return byIcon end
    byIcon = {}
    if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return byIcon end
    local best = {}
    for id = 1, 4000 do
        local info = C_CurrencyInfo.GetCurrencyInfo(id)
        if info and info.iconFileID and info.name and info.name ~= "" then
            -- Several currencies can share an icon: prefer one the player
            -- has, then one discovered, then the lowest ID.
            local score = ((info.quantity or 0) > 0 and 2 or 0) + (info.discovered and 1 or 0)
            if not best[info.iconFileID] or score > best[info.iconFileID] then
                best[info.iconFileID] = score
                byIcon[info.iconFileID] = id
            end
        end
    end
    return byIcon
end

--- Price parts in a journal text, or nil when it has none:
--- { { kind = "gold", need = copper },
---   { kind = "currency" | "item", id, name, icon, need },
---   { kind = "unknown", icon, need } }
function W:ParseCost(text)
    if not text or text == "" then return nil end
    local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]*:", ""):gsub("|r", "")
    local parts, copper = {}, 0
    -- Linked prices name the currency or item exactly:
    --   "3940 |Hcurrency:3056|h|T...icon...|t|h"
    for amount, kind, id in plain:gmatch("([%d][%d,%.]*)%s*|H(%a+):(%d+)") do
        local n, cid = tonumber((amount:gsub("[^%d]", ""))), tonumber(id)
        if n and cid and kind == "currency" and C_CurrencyInfo then
            local info = C_CurrencyInfo.GetCurrencyInfo(cid)
            parts[#parts + 1] = { kind = "currency", id = cid, name = info and info.name,
                icon = info and info.iconFileID, need = n }
        elseif n and cid and kind == "item" then
            local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(cid)
            local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(cid)
            parts[#parts + 1] = { kind = "item", id = cid, name = name, icon = icon, need = n }
        end
    end
    plain = plain:gsub("|H.-|h.-|h", "") -- links read above; the rest is "number + icon"
    for amount, tex in plain:gmatch("([%d][%d,%.]*)%s*|T([^:|]+)[^|]*|t") do
        local n = tonumber((amount:gsub("[^%d]", "")))
        if n then
            local coin = coinValue(tex)
            if coin then
                copper = copper + n * coin
            else
                local icon = fileID(tex)
                local id = icon and currencyByIcon()[icon]
                local info = id and C_CurrencyInfo.GetCurrencyInfo(id)
                if info then
                    parts[#parts + 1] = { kind = "currency", id = id, name = info.name, icon = icon, need = n }
                else
                    parts[#parts + 1] = { kind = "unknown", icon = icon or tex, need = n }
                end
            end
        end
    end
    if copper > 0 then table.insert(parts, 1, { kind = "gold", need = copper }) end
    -- Two vendors with the same price list it twice: keep one.
    local seen, unique = {}, {}
    for _, p in ipairs(parts) do
        -- %s, not %d: gold prices in copper pass 2^31 (5 million gold = 5e10).
        local key = ("%s:%s:%s"):format(p.kind, tostring(p.id or p.icon), tostring(p.need))
        if not seen[key] then
            seen[key] = true
            unique[#unique + 1] = p
        end
    end
    return #unique > 0 and unique or nil
end

--- How much of a price part this character has (nil = cannot tell).
function W:Have(part)
    if part.kind == "gold" then return GetMoney() end
    if part.kind == "currency" then
        local info = C_CurrencyInfo.GetCurrencyInfo(part.id)
        return info and info.quantity or 0
    end
    if part.kind == "item" and C_Item and C_Item.GetItemCount then
        return C_Item.GetItemCount(part.id, true) -- bags and bank
    end
    return nil
end

local function big(n)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

--- Text for an amount: gold (whole gold, coin icon), a currency or item with its icon.
function W:Format(part, amount)
    if part.kind == "gold" then
        return ("%s|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"):format(big(math.floor(amount / 10000)))
    end
    local n = big(amount)
    return ("%s |T%s:14:14:0:0|t"):format(n, tostring(part.icon or 134400))
end
