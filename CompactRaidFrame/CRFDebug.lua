--[[----------------------------------------------------------------------------
    CRFDebug.lua  -  temporary runtime diagnostics for the stock-3.3.5a backport.

    Nothing prints automatically. Slash commands:
      /crfdebug  (alias /crfdump)  - detailed live frame-lifecycle dump
      /crfforce                    - (out of combat) force a clean working state:
                                     useCompactPartyFrames=on, rebuild the default
                                     profile, apply it, show + relayout. pcall'd,
                                     so it prints the exact failing call instead of
                                     dying silently.
      /crfreset                    - wipe CompactRaidFrameDB and ReloadUI (use this
                                     once to clear stale saved state from older
                                     builds, then test fresh).

    Keep until the addon is confirmed working in-game; it only ADDS slash commands
    and reads state (no Blizzard globals changed).
------------------------------------------------------------------------------]]

local function p(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffCRF|r " .. tostring(msg))
end

local function yn(v)
    return v and "|cff44ff44yes|r" or "|cffff4444no|r"
end

local function safe(fn, ...)
    if type(fn) ~= "function" then return "|cffff8800<missing>|r" end
    local ok, a = pcall(fn, ...)
    if ok then return a end
    return "|cffff4444ERR:" .. tostring(a) .. "|r"
end

-- read a profile option through the public API (PROFILES is file-local in CUFProfilesAPI)
local function opt(profile, name)
    if not (profile and GetRaidProfileOption) then return "?" end
    local ok, v = pcall(GetRaidProfileOption, profile, name)
    if ok then return tostring(v) end
    return "ERR"
end

local function dump()
    p("===== CompactRaidFrame runtime dump =====")

    -- A. compat / load
    p(("A load: WotLKCompat=%s | CopyTable=%s Mixin=%s CreateFromMixins=%s C_Timer=%s"):format(
        yn(CRF_WOTLKCOMPAT_LOADED), type(CopyTable), type(Mixin), type(CreateFromMixins), type(C_Timer)))

    -- B. group state
    p(("B group: NumRaid=%s NumParty=%s | player=%s party1=%s raid1=%s"):format(
        tostring(safe(GetNumRaidMembers)), tostring(safe(GetNumPartyMembers)),
        yn(UnitExists("player")), yn(UnitExists("party1")), yn(UnitExists("raid1"))))
    p(("B group: IsInRaid=%s IsInGroup=%s NumGroup=%s NumSub=%s | GetDisplayedAllyFrames=%s"):format(
        tostring(safe(IsInRaid)), tostring(safe(IsInGroup)),
        tostring(safe(GetNumGroupMembers)), tostring(safe(GetNumSubgroupMembers)),
        tostring(safe(GetDisplayedAllyFrames))))

    -- C. saved config / profile
    local active = safe(GetActiveRaidProfile)
    p(("C config: useCompactPartyFrames=%s ACTIVE=%s | HasLoaded=%s NumProfiles=%s"):format(
        tostring(CUF_CVar and safe(function() return CUF_CVar:GetValue("useCompactPartyFrames") end)),
        tostring(active), tostring(safe(HasLoadedCUFProfiles)), tostring(safe(GetNumRaidProfiles))))
    if active and active ~= "" then
        p(("C profile[%s]: shown=%s locked=%s sortBy=%s keepGroupsTogether=%s displayPowerBar=%s"):format(
            tostring(active), opt(active, "shown"), opt(active, "locked"), opt(active, "sortBy"),
            opt(active, "keepGroupsTogether"), opt(active, "displayPowerBar")))
        p(("C profile[%s]: useClassColors=%s displayName=%s displayBorder=%s displayMainTankAndAssist=%s healthText=%s"):format(
            tostring(active), opt(active, "useClassColors"), opt(active, "displayName"),
            opt(active, "displayBorder"), opt(active, "displayMainTankAndAssist"), opt(active, "healthText")))
    end

    -- D. manager
    local m = CompactRaidFrameManager
    p(("D manager: exists=%s shown=%s visible=%s collapsed=%s"):format(
        yn(m ~= nil), yn(m and m:IsShown()), yn(m and m:IsVisible()), tostring(m and m.collapsed)))

    -- E. container (the gate)
    local c = CompactRaidFrameContainer
    if c then
        p(("E container: shown=%s visible=%s | groupMode=%s enabled=%s flowSort=%s flowFilter=%s groupFilter=%s"):format(
            yn(c:IsShown()), yn(c:IsVisible()), tostring(c.groupMode), tostring(c.enabled),
            type(c.flowSortFunc), yn(c.flowFilterFunc ~= nil), yn(c.groupFilterFunc ~= nil)))
        p(("E container: units=%s displayPets=%s displayFlagged=%s showBorder=%s size=%dx%d alpha=%.2f"):format(
            c.units and #c.units or "nil", tostring(c.displayPets), tostring(c.displayFlaggedMembers),
            tostring(c.showBorder), math.floor(c:GetWidth() or 0), math.floor(c:GetHeight() or 0), c:GetAlpha() or 0))
    else
        p("E container: |cffff4444DOES NOT EXIST|r")
    end

    -- F. manager settings (must be non-nil; IsShown=true is required to show the container)
    if CompactRaidFrameManager_GetSetting then
        local names = { "Locked", "SortMode", "KeepGroupsTogether", "DisplayPets",
                        "DisplayMainTankAndAssist", "IsShown", "ShowBorders", "HorizontalGroups" }
        local parts = {}
        for _, s in ipairs(names) do
            parts[#parts + 1] = s .. "=" .. tostring(safe(CompactRaidFrameManager_GetSetting, s))
        end
        p("F settings: " .. table.concat(parts, " "))
    end

    -- G. created unit frames (geometry detail for the first few)
    local n = 0
    local detail = {}
    for i = 1, 200 do
        local f = _G["CompactRaidFrame" .. i]
        if f then
            n = n + 1
            if n <= 8 then
                local par = f:GetParent()
                local hb = f.healthBar
                local hv, _, hmax = "?", nil, "?"
                if hb then hv = hb:GetValue(); local _, mx = hb:GetMinMaxValues(); hmax = mx end
                detail[#detail + 1] = ("   #%d %s unit=%s shown=%s vis=%s %dx%d a=%.2f lvl=%s hp=%s/%s parent=%s"):format(
                    i, f:GetName() or "?", tostring(f.unit), yn(f:IsShown()), yn(f:IsVisible()),
                    math.floor(f:GetWidth() or 0), math.floor(f:GetHeight() or 0), f:GetAlpha() or 0,
                    tostring(f:GetFrameLevel()), tostring(hv), tostring(hmax),
                    par and (par:GetName() or "<anon>") or "nil")
            end
        end
    end
    p("G created CompactRaidFrameN unit frames: " .. n)
    for _, l in ipairs(detail) do p(l) end

    -- H. group / party container frames
    local g = 0
    for i = 1, (MAX_RAID_GROUPS or 8) do if _G["CompactRaidGroup" .. i] then g = g + 1 end end
    p(("H group frames: CompactRaidGroupN=%d | CompactPartyFrame exists=%s shown=%s"):format(
        g, yn(CompactPartyFrame ~= nil), yn(CompactPartyFrame and CompactPartyFrame:IsShown())))

    -- I. heal/absorb backends
    p(("I heal/absorb: LibHealComm-4.0=%s AbsorbsMonitor-1.0=%s | UnitGetIncomingHeals(player)=%s UnitGetTotalAbsorbs(player)=%s"):format(
        yn(LibStub and LibStub:GetLibrary("LibHealComm-4.0", true) ~= nil),
        yn(LibStub and LibStub:GetLibrary("AbsorbsMonitor-1.0", true) ~= nil),
        tostring(safe(UnitGetIncomingHeals, "player")), tostring(safe(UnitGetTotalAbsorbs, "player"))))

    -- J. options panel (Interface -> AddOns -> "Raid Profiles")
    local panel = CompactUnitFrameProfiles
    local registered = false
    if panel and type(INTERFACEOPTIONS_ADDONCATEGORIES) == "table" then
        for _, cat in ipairs(INTERFACEOPTIONS_ADDONCATEGORIES) do
            if cat == panel then registered = true; break end
        end
    end
    p(("J options: BlizzardOptionsPanel_OnLoad=%s InterfaceOptions_AddCategory=%s OpenToCategory=%s"):format(
        type(BlizzardOptionsPanel_OnLoad), type(InterfaceOptions_AddCategory), type(InterfaceOptionsFrame_OpenToCategory)))
    p(("J options: panel exists=%s name=%s parent=%s registered=%s"):format(
        yn(panel ~= nil), tostring(panel and panel.name),
        tostring(panel and panel.parent), yn(registered)))
    local optc = InterfaceOptionsFramePanelContainer
    p(("J options: container=%dx%d panelScale=%.2f"):format(
        optc and math.floor(optc:GetWidth() or 0) or 0,
        optc and math.floor(optc:GetHeight() or 0) or 0,
        panel and (panel:GetScale() or 1) or 1))
    if panel then
        p(("J options: okay=%s refresh=%s GeneralOptions=%s ProfileSelector=%s SaveBtn=%s DeleteBtn=%s"):format(
            type(panel.okay), type(panel.refresh),
            yn(CompactUnitFrameProfilesGeneralOptionsFrame ~= nil),
            yn(_G["CompactRaidFrameManagerDisplayFrameProfileSelector"] ~= nil),
            yn(_G["CompactUnitFrameProfilesSaveButton"] ~= nil),
            yn(_G["CompactUnitFrameProfilesDeleteButton"] ~= nil)))
    end

    p("===== end dump  (/crfforce = force working state, /crfoptions = open panel, /crfreset = wipe DB + reload) =====")
end

local function force()
    if InCombatLockdown() then p("|cffff4444in combat - leave combat and retry|r"); return end
    p("forcing a clean working state ...")
    local ok, err = pcall(function()
        -- 1. ensure compact party frames are on (so a party shows compact frames)
        if CUF_CVar then CUF_CVar:SetValue("useCompactPartyFrames", "1") end
        -- 2. rebuild a fresh default profile (clears any stale/partial saved profile)
        if CompactUnitFrameProfiles_ResetToDefaults then
            CompactUnitFrameProfiles_ResetToDefaults()
        end
        -- 3. (re)apply + show + relayout
        if RaidOptionsFrame_UpdatePartyFrames then RaidOptionsFrame_UpdatePartyFrames() end
        if CompactRaidFrameManager_UpdateShown then CompactRaidFrameManager_UpdateShown(CompactRaidFrameManager) end
        if CompactRaidFrameContainer_TryUpdate then CompactRaidFrameContainer_TryUpdate(CompactRaidFrameContainer) end
        -- relay a roster update (GROUP_ROSTER_UPDATE never fires on 3.3.5a)
        if CRF_RelayGroupRosterUpdate then CRF_RelayGroupRosterUpdate() end
    end)
    if ok then
        p("|cff44ff44force OK|r - run /crfdebug to see the new state")
    else
        p("|cffff4444force ERROR:|r " .. tostring(err))
    end
end

-- Re-register and open the "Raid Profiles" options panel; report where it fails.
local function options()
    local panel = CompactUnitFrameProfiles
    if not panel then
        p("|cffff4444CompactUnitFrameProfiles frame does not exist|r - CUFProfiles XML failed to load")
        return
    end
    if not panel.name then panel.name = "Raid Profiles" end
    p("panel name = " .. tostring(panel.name))
    local ok, err = pcall(function()
        if type(InterfaceOptions_AddCategory) == "function" then
            InterfaceOptions_AddCategory(panel)
        end
        if type(InterfaceOptionsFrame_OpenToCategory) == "function" then
            InterfaceOptionsFrame_OpenToCategory(panel)
            InterfaceOptionsFrame_OpenToCategory(panel)  -- twice: 3.3.5a scroll quirk
        end
    end)
    if ok then
        p("|cff44ff44options OK|r - the panel should now be open / listed as '" .. tostring(panel.name) .. "'")
    else
        p("|cffff4444options ERROR:|r " .. tostring(err))
    end
end

local function reset()
    p("wiping CompactRaidFrameDB and reloading ...")
    _G["CompactRaidFrameDB"] = nil
    if type(wipe) == "function" and CompactRaidFrameDB then wipe(CompactRaidFrameDB) end
    ReloadUI()
end

SLASH_CRFDEBUG1 = "/crfdebug"
SLASH_CRFDEBUG2 = "/crfdump"
SlashCmdList["CRFDEBUG"] = dump

SLASH_CRFFORCE1 = "/crfforce"
SlashCmdList["CRFFORCE"] = force

SLASH_CRFOPTIONS1 = "/crfoptions"
SlashCmdList["CRFOPTIONS"] = options

SLASH_CRFRESET1 = "/crfreset"
SlashCmdList["CRFRESET"] = reset
