-- Minimap button via LibDataBroker-1.1 + LibDBIcon-1.0, so minimap button
-- collectors pick it up. The libraries are NOT embedded: LibDataBroker-1.1
-- has no explicit license, and the repo is MIT (CLAUDE.md §6, third-party
-- code). They are used when another installed addon already loaded them;
-- otherwise the native AddonCompartment entry (declared in the TOC) remains.
local ADDON_NAME, ns = ...
local L = ns.L

local MinimapButton = {}
ns.MinimapButton = MinimapButton

MinimapButton.available = false

--- Call after all addons are loaded (PLAYER_LOGIN). Returns true if registered.
function MinimapButton:Init()
    if self.available or not LibStub then return self.available end
    local ldb = LibStub("LibDataBroker-1.1", true)
    local dbicon = LibStub("LibDBIcon-1.0", true)
    if not (ldb and dbicon) then return false end

    local muted = ns.UI.COLORS.tipMuted
    local launcher = ldb:NewDataObject(ADDON_NAME, {
        type = "launcher",
        text = L["TITLE"],
        icon = "Interface\\AddOns\\AnimalitosPlanner\\Media\\icon",
        OnClick = function(_, button)
            if button == "RightButton" then
                ns.UI:Open("home")
            else
                ns.UI:Toggle()
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine(L["TITLE"], 1, 1, 1)
            tt:AddLine(L["MINIMAP_TIP"], muted[1], muted[2], muted[3])
        end,
    })
    if not launcher then return false end

    local ui = ns.Storage.db.ui
    ui.minimap = ui.minimap or {} -- LibDBIcon keeps hide/minimapPos here
    dbicon:Register(ADDON_NAME, launcher, ui.minimap)
    self.dbicon = dbicon
    self.available = true
    return true
end

function MinimapButton:IsShown()
    local m = ns.Storage.db.ui.minimap
    return not (m and m.hide)
end

function MinimapButton:SetShown(shown)
    local ui = ns.Storage.db.ui
    ui.minimap = ui.minimap or {}
    ui.minimap.hide = not shown
    if self.dbicon then
        if shown then self.dbicon:Show(ADDON_NAME) else self.dbicon:Hide(ADDON_NAME) end
    end
end
