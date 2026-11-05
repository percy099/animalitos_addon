-- Mount preview: side panel next to the main window with the 3D model,
-- description and source of a mount, plus a shortcut to the Mount Journal.
-- Opened by clicking a mount row in "Farmable now".
local _, ns = ...
local L = ns.L

local Preview = {}
ns.MountPreview = Preview

local W, H = 280, 400
local MODEL_H = 210

local function create()
    local C = ns.UI.COLORS
    local main = ns.UI.frame
    local f = CreateFrame("Frame", nil, main, "BackdropTemplate")
    f:SetSize(W, H)
    f:SetPoint("TOPLEFT", main, "TOPRIGHT", 4, 0)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    ns.UI.StylePanel(f, C.background, { border = { C.accent[1], C.accent[2], C.accent[3], 0.45 }, noSheen = true })

    local close = ns.UI.CloseButton(f)
    close:SetPoint("TOPRIGHT", -6, -6)

    f.title = ns.UI.fs(f, "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 12, -12)
    f.title:SetPoint("RIGHT", close, "LEFT", -4, 0)
    f.title:SetWordWrap(false)

    local holder = CreateFrame("Frame", nil, f, "BackdropTemplate")
    holder:SetPoint("TOPLEFT", 10, -40)
    holder:SetPoint("TOPRIGHT", -10, -40)
    holder:SetHeight(MODEL_H)
    ns.UI.StylePanel(holder)

    -- Same scene type Blizzard's Mount Journal uses; plain model as fallback.
    local ok, scene = pcall(CreateFrame, "ModelScene", nil, holder, "ModelSceneMixinTemplate")
    if ok and scene then
        scene:SetPoint("TOPLEFT", 4, -4)
        scene:SetPoint("BOTTOMRIGHT", -4, 4)
        scene:EnableMouse(true)
        f.scene = scene
    end
    f.model = CreateFrame("PlayerModel", nil, holder)
    f.model:SetPoint("TOPLEFT", 4, -4)
    f.model:SetPoint("BOTTOMRIGHT", -4, 4)
    f.model:Hide()

    f.hint = ns.UI.fs(f, "GameFontDisableSmall")
    f.hint:SetPoint("TOPRIGHT", holder, "BOTTOMRIGHT", -2, -3)
    f.hint:SetJustifyH("RIGHT")
    f.hint:SetText(L["PREVIEW_DRAG"])

    f.desc = ns.UI.fs(f, "GameFontHighlightSmall", C.muted)
    f.desc:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 2, -20)
    f.desc:SetWidth(W - 24)
    f.desc:SetWordWrap(true)
    f.desc:SetMaxLines(7)

    f.source = ns.UI.fs(f, "GameFontHighlightSmall")
    f.source:SetPoint("TOPLEFT", f.desc, "BOTTOMLEFT", 0, -8)
    f.source:SetWidth(W - 24)
    f.source:SetWordWrap(true)
    f.source:SetMaxLines(5)

    f.journal = ns.UI.Button(f, "primary")
    ns.UI.SetButtonText(f.journal, L["BTN_OPEN_JOURNAL"], 160)
    f.journal:SetPoint("BOTTOM", 0, 12)
    return f
end

-- Returns true when the ModelScene path worked.
local function showInScene(f, extra)
    if not (f.scene and extra.uiModelSceneID and extra.creatureDisplayID) then return false end
    local ok, done = pcall(function()
        f.scene:TransitionToModelSceneID(extra.uiModelSceneID, CAMERA_TRANSITION_TYPE_IMMEDIATE,
            CAMERA_MODIFICATION_TYPE_DISCARD, true)
        local actor = f.scene:GetActorByTag("unwrapped")
        if not actor then return false end
        actor:SetModelByCreatureDisplayID(extra.creatureDisplayID, true)
        if extra.isSelfMount then
            actor:SetAnimationBlendOperation(Enum.ModelBlendOperation.None)
            actor:SetAnimation(618) -- mount-only "self mount" idle, as the Mount Journal does
        else
            actor:SetAnimationBlendOperation(Enum.ModelBlendOperation.Anim)
            actor:SetAnimation(0)
        end
        return true
    end)
    return ok and done
end

local function showModel(f, extra)
    if showInScene(f, extra) then
        f.model:Hide()
        f.scene:Show()
        f.hint:Show()
        return
    end
    if f.scene then f.scene:Hide() end
    f.hint:Hide()
    if extra.creatureDisplayID then
        f.model:SetDisplayInfo(extra.creatureDisplayID)
        f.model:Show()
    else
        f.model:Hide()
    end
end

function Preview:Show(mountID)
    self.frame = self.frame or create()
    local f = self.frame
    local m = ns.MountJournal:GetMount(mountID)
    local extra = ns.MountJournal:GetMountExtra(mountID) or {}
    f.mountID = mountID
    f.title:SetText(m and m.name or ("#" .. mountID))
    f.desc:SetText(extra.description or "")
    f.source:SetText(extra.sourceText or "")
    f.journal:SetScript("OnClick", function()
        if not ns.MountJournal:OpenInJournal(mountID) then ns:Print(L["JOURNAL_COMBAT"]) end
    end)
    f:Show()
    showModel(f, extra)
end

--- Click on the same mount again closes the preview.
function Preview:Toggle(mountID)
    local f = self.frame
    if f and f:IsShown() and f.mountID == mountID then
        f:Hide()
    else
        self:Show(mountID)
    end
end
