--[[----------------------------------------------------------------------------
    WotLKCompat.lua  -  Stock 3.3.5a (WotLK, build 12340, Lua 5.1) compatibility
    layer for CompactRaidFrame.

    This addon is a backport of Blizzard's (Cataclysm-era) CompactRaidFrame
    system. Upstream it depended on the "!!!ClassicAPI" addon to provide modern
    retail API. This file makes the addon SELF-CONTAINED: it re-implements
    exactly what ClassicAPI supplied, using only stock 3.3.5a API.

    RULES followed here (learned across the WotLK backport project):
      * ONLY ADD new globals / new metatable methods, all guarded (`if not X`).
        Never reassign or wrap an existing Blizzard global -> that taints the
        secure UI and unrelated addons.
      * This file MUST load FIRST (before Libs / the addon's own Compat.lua,
        which captures IsInRaid/IsInGroup as upvalues at load time).
      * Library lookups (LibGroupTalents / LibResComm) are LAZY (done on first
        call), so this file may load before Libs\Load.xml.
------------------------------------------------------------------------------]]

local _G = _G

--========================================================================--
-- 1. WOW_PROJECT_* constants (all nil on 3.3.5a -> nil==nil traps).
--========================================================================--
if WOW_PROJECT_ID == nil then
    WOW_PROJECT_MAINLINE        = 1
    WOW_PROJECT_CLASSIC         = 2
    WOW_PROJECT_WRATH_CLASSIC   = 11
    WOW_PROJECT_ID              = WOW_PROJECT_WRATH_CLASSIC
end

--========================================================================--
-- 2. Group API (IsInRaid/IsInGroup/... are MoP+; build them from the
--    native 3.3.5a GetNumRaidMembers / GetNumPartyMembers).
--========================================================================--
if type(IsInGroup) ~= "function" then
    function IsInGroup()
        return (GetNumRaidMembers() > 0) or (GetNumPartyMembers() > 0)
    end
end

if type(IsInRaid) ~= "function" then
    function IsInRaid()
        return GetNumRaidMembers() > 0
    end
end

if type(GetNumSubgroupMembers) ~= "function" then
    function GetNumSubgroupMembers()
        return GetNumPartyMembers()
    end
end

if type(GetNumGroupMembers) ~= "function" then
    function GetNumGroupMembers()
        -- In a raid: number of raid members. In a party: party size + the player.
        local n = GetNumRaidMembers()
        if n > 0 then
            return n
        end
        n = GetNumPartyMembers()
        return (n > 0) and (n + 1) or 0
    end
end

--========================================================================--
-- 3. Leader / assistant helpers (UnitIsGroupLeader/Assistant are MoP+).
--========================================================================--
if type(UnitIsGroupLeader) ~= "function" then
    function UnitIsGroupLeader(unit)
        if not IsInGroup() then
            return false
        end
        if unit == "player" then
            return (IsInRaid() and IsRaidLeader() or IsPartyLeader()) and true or false
        end
        local index = unit and unit:match("%d+")
        return (index and GetPartyLeaderIndex() == tonumber(index)) and true or false
    end
end

if type(UnitIsGroupAssistant) ~= "function" then
    function UnitIsGroupAssistant(unit)
        if not IsInRaid() then
            return false
        end
        -- UnitIsRaidOfficer reports correctly for raid units on 3.3.5a.
        return (UnitIsRaidOfficer(unit) and not UnitIsGroupLeader(unit)) and true or false
    end
end

--========================================================================--
-- 4. Role assignment.
--    C_UnitGroupRolesAssigned(unit) -> single string TANK/HEALER/DAMAGER/NONE.
--    3.3.5a has no real role system, so we infer:
--      pure-dps class -> DAMAGER, otherwise LibGroupTalents talent inference.
--    (Some private cores expose a boolean UnitGroupRolesAssigned for LFG; we
--     use it when present.)
--========================================================================--
local nativeRolesFn = (type(UnitGroupRolesAssigned) == "function") and UnitGroupRolesAssigned or nil
local LibGT  -- lazily fetched
local LGT_TO_ROLE = { melee = "DAMAGER", caster = "DAMAGER", healer = "HEALER", tank = "TANK" }

if type(C_UnitGroupRolesAssigned) ~= "function" then
    function C_UnitGroupRolesAssigned(unit)
        if not unit or not UnitExists(unit) then
            return "NONE"
        end

        local _, class = UnitClass(unit)
        if class == "HUNTER" or class == "ROGUE" or class == "MAGE" or class == "WARLOCK" then
            return "DAMAGER"  -- these classes only ever dps in WotLK
        end

        local tank, heal, damage
        if nativeRolesFn then
            tank, heal, damage = nativeRolesFn(unit)
        end

        if not (tank or heal or damage) then
            if LibGT == nil then
                LibGT = (LibStub and LibStub:GetLibrary("LibGroupTalents-1.0", true)) or false
            end
            local role = LibGT and LibGT:GetUnitRole(unit)
            return LGT_TO_ROLE[role] or "NONE"
        end

        if tank then return "TANK" end
        if heal then return "HEALER" end
        if damage then return "DAMAGER" end
        return "NONE"
    end
end

if type(GetTexCoordsForRoleSmallCircle) ~= "function" then
    function GetTexCoordsForRoleSmallCircle(role)
        if role == "TANK" then
            return 0, 19/64, 22/64, 41/64
        elseif role == "HEALER" then
            return 20/64, 39/64, 1/64, 20/64
        elseif role == "DAMAGER" then
            return 20/64, 39/64, 22/64, 41/64
        else
            return 0, 0, 0, 0
        end
    end
end

--========================================================================--
-- 5. Range / distance.
--    UnitInRange(unit) is Cata+. We use the 40yd "Vial of the Sunwell" range
--    item (the standard healer range probe) and fall back to interact range.
--========================================================================--
local RANGE_ITEM = 34471  -- Vial of the Sunwell (40 yd)

if type(C_UnitInRange) ~= "function" then
    function C_UnitInRange(unit)
        if not unit or not UnitExists(unit) then
            return false, false  -- can't check -> treat as in range upstream
        end
        local r = IsItemInRange(RANGE_ITEM, unit)
        if r == 1 or r == true then
            return true, true
        elseif r == 0 or r == false then
            return false, true
        end
        -- nil: item not cached / not applicable -> interact-distance fallback (~28yd)
        return (CheckInteractDistance(unit, 1) == 1), true
    end
end

if type(UnitInRange) ~= "function" then
    -- Some addon code still calls the bare name; route it through ours.
    function UnitInRange(unit)
        return C_UnitInRange(unit)
    end
end

if type(UnitDistanceSquared) ~= "function" then
    function UnitDistanceSquared(unit)
        if unit and UnitIsConnected(unit) then
            local px, py = GetPlayerMapPosition("player")
            local ux, uy = GetPlayerMapPosition(unit)
            if px and ux and (px ~= 0 or py ~= 0) and (ux ~= 0 or uy ~= 0) then
                local dx, dy = (px - ux), (py - uy)
                return (dx * dx + dy * dy) * 100000, true
            end
        end
        return 0, false
    end
end

-- Ensure the range item is in the local item cache so IsItemInRange works.
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(self)
        GetItemInfo(RANGE_ITEM)
    end)
end

--========================================================================--
-- 6. Instance info (C_GetInstanceInfo = GetInstanceInfo + battleground sizes,
--    matching ClassicAPI's contract used by the auto-activation logic).
--========================================================================--
if type(C_GetInstanceInfo) ~= "function" then
    function C_GetInstanceInfo()
        local name, instanceType, difficultyIndex, difficultyName, maxPlayers, dynamicDifficulty, isDynamic = GetInstanceInfo()
        if instanceType == "pvp" then
            local map = GetMapInfo()
            if map == "AlteracValley" or map == "IsleofConquest" or map == "LakeWintergrasp" then
                maxPlayers = 40
            elseif map == "ArathiBasin" or map == "NetherstormArena" or map == "StrandoftheAncients" then
                maxPlayers = 15
            elseif map == "WarsongGulch" then
                maxPlayers = 10
            end
        end
        return name, instanceType, difficultyIndex, difficultyName, maxPlayers, dynamicDifficulty, isDynamic
    end
end

--========================================================================--
-- 7. Phasing / other-party / raid-target (retail concepts; safe WotLK stubs).
--========================================================================--
if type(UnitPhaseReason) ~= "function" then
    function UnitPhaseReason(unit) return nil end  -- no phasing in WotLK
end

if type(UnitInPhase) ~= "function" then
    function UnitInPhase(unit) return true end
end

if type(UnitInOtherParty) ~= "function" then
    function UnitInOtherParty(unit) return false end
end

if type(CanBeRaidTarget) ~= "function" then
    function CanBeRaidTarget(unit)
        if not unit then return end
        if UnitExists(unit) and UnitIsConnected(unit) then
            return not (UnitIsPlayer(unit) and UnitIsEnemy("player", unit))
        end
    end
end

--========================================================================--
-- 8. Heal prediction / absorbs / incoming resurrect.
--    The source repo bundles NO heal/absorb library, so heal-prediction and
--    absorbs degrade to a robust no-op (the bars stay hidden; this matches the
--    addon's default options, which have displayHealPrediction off). Incoming
--    resurrection uses the bundled LibResComm-1.0 for a real result.
--========================================================================--
if type(UnitGetIncomingHeals) ~= "function" then
    function UnitGetIncomingHeals(unit, healer) return nil end
end
if type(UnitGetTotalAbsorbs) ~= "function" then
    function UnitGetTotalAbsorbs(unit) return nil end
end
if type(UnitGetTotalHealAbsorbs) ~= "function" then
    function UnitGetTotalHealAbsorbs(unit) return nil end
end

local LibResComm  -- lazily fetched
if type(UnitHasIncomingResurrection) ~= "function" then
    function UnitHasIncomingResurrection(unit)
        if not unit then return end
        if LibResComm == nil then
            LibResComm = (LibStub and LibStub:GetLibrary("LibResComm-1.0", true)) or false
        end
        if LibResComm then
            return LibResComm:IsUnitBeingRessed(UnitName(unit))
        end
    end
end

--========================================================================--
-- 9. Aura visibility filters (ClassicAPI shipped a curated spell table; we use
--    permissive defaults: show buffs you applied, no "custom" visibility, no
--    priority auras). Debuff display itself uses the native UnitDebuff path.
--========================================================================--
if type(SpellGetVisibilityInfo) ~= "function" then
    function SpellGetVisibilityInfo(spellId, visType)
        return false  -- hasCustom = false -> falls through to SpellIsSelfBuff path
    end
end
if type(SpellIsSelfBuff) ~= "function" then
    function SpellIsSelfBuff(spellId)
        -- returns: selfBuff, canApplyAura  -> show non-self buffs cast by the player
        return false, true
    end
end
if type(SpellIsPriorityAura) ~= "function" then
    function SpellIsPriorityAura(spellId) return false end
end

--========================================================================--
-- 10. C_Timer (After / NewTimer / NewTicker) via a single OnUpdate scheduler.
--========================================================================--
if type(C_Timer) ~= "table" then
    local GetTime = GetTime
    local geterrorhandler = geterrorhandler
    C_Timer = {}

    local timers = {}                 -- set of active timer objects
    local TimerMT = {}
    TimerMT.__index = TimerMT
    function TimerMT:Cancel()
        self._cancelled = true
        timers[self] = nil
    end
    function TimerMT:IsCancelled()
        return self._cancelled == true
    end

    local driver = CreateFrame("Frame")
    driver:Hide()

    driver:SetScript("OnUpdate", function()
        if not next(timers) then
            driver:Hide()  -- nothing pending: stop ticking
            return
        end
        local now = GetTime()
        local due
        for t in pairs(timers) do
            if not t._cancelled and now >= t._next then
                due = due or {}
                due[#due + 1] = t
            end
        end
        if due then
            for i = 1, #due do
                local t = due[i]
                if not t._cancelled then
                    if t._ticker then
                        if t._iterations then
                            t._iterations = t._iterations - 1
                            if t._iterations <= 0 then
                                timers[t] = nil
                                t._cancelled = true
                            end
                        end
                        t._next = now + t._interval
                    else
                        timers[t] = nil
                        t._cancelled = true
                    end
                    local cb = t._callback
                    if cb then
                        local ok, err = pcall(cb)
                        if not ok and geterrorhandler then geterrorhandler()(err) end
                    end
                end
            end
        end
    end)

    local function newTimer(duration, callback, iterations, ticker)
        duration = (type(duration) == "number" and duration > 0) and duration or 0.0
        local t = setmetatable({}, TimerMT)
        t._next       = GetTime() + duration
        t._interval   = duration
        t._callback   = callback
        t._iterations = iterations
        t._ticker     = ticker
        timers[t] = true
        driver:Show()
        return t
    end

    function C_Timer.After(duration, callback)
        newTimer(duration, callback, nil, false)
    end
    function C_Timer.NewTimer(duration, callback)
        return newTimer(duration, callback, nil, false)
    end
    function C_Timer.NewTicker(duration, callback, iterations)
        return newTimer(duration, callback, iterations, true)
    end
end

--========================================================================--
-- 11. Mixin / BackdropTemplateMixin / CreateColor / ColorMixin.
--========================================================================--
if type(Mixin) ~= "function" then
    function Mixin(object, ...)
        for i = 1, select("#", ...) do
            local mixin = select(i, ...)
            if mixin then
                for k, v in pairs(mixin) do
                    object[k] = v
                end
            end
        end
        return object
    end
end

if type(CreateFromMixins) ~= "function" then
    function CreateFromMixins(...)
        return Mixin({}, ...)
    end
end

-- CopyTable (Cata) — deep copy. CUFProfilesAPI.lua clones profile tables with it;
-- without this the profile system errors on first load and NO frames/settings are
-- ever applied (the manager panel still shows, but the container stays empty).
if type(CopyTable) ~= "function" then
    function CopyTable(tbl)
        local copy = {}
        for k, v in pairs(tbl) do
            if type(v) == "table" then
                copy[k] = CopyTable(v)
            else
                copy[k] = v
            end
        end
        return copy
    end
end

-- On 3.3.5a Frame:SetBackdrop is native, so the retail backdrop mixin only
-- needs to exist (empty) for the `Mixin(self, BackdropTemplateMixin)` call sites.
if type(BackdropTemplateMixin) ~= "table" then
    BackdropTemplateMixin = {}
end

if type(CreateColor) ~= "function" then
    ColorMixin = ColorMixin or {}
    function ColorMixin:GetRGB() return self.r, self.g, self.b end
    function ColorMixin:GetRGBA() return self.r, self.g, self.b, self.a end
    function ColorMixin:SetRGB(r, g, b) self.r, self.g, self.b = r, g, b end
    function ColorMixin:SetRGBA(r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a end
    local ColorMT = { __index = ColorMixin }
    function CreateColor(r, g, b, a)
        local c = setmetatable({}, ColorMT)
        c.r, c.g, c.b, c.a = r, g, b, (a or 1)
        return c
    end
end

--========================================================================--
-- 12. SetSize / GetSize (Cata) added to each widget metatable (each widget
--     type has its OWN metatable on 3.3.5a). This is the one safe metatable
--     extension: secure code never calls methods that didn't exist on 3.3.5a.
--========================================================================--
do
    local function addSize(obj)
        if not obj then return end
        local mt = getmetatable(obj)
        local index = mt and mt.__index
        if type(index) == "table" then
            if not index.SetSize then
                index.SetSize = function(self, w, h) self:SetWidth(w); self:SetHeight(h) end
            end
            if not index.GetSize then
                index.GetSize = function(self) return self:GetWidth(), self:GetHeight() end
            end
        end
    end

    local holder = CreateFrame("Frame")
    holder:Hide()
    addSize(holder)                                 -- Frame
    addSize(CreateFrame("Button", nil, holder))     -- Button
    addSize(CreateFrame("StatusBar", nil, holder))  -- StatusBar
    addSize(CreateFrame("Slider", nil, holder))     -- Slider
    addSize(CreateFrame("CheckButton", nil, holder))-- CheckButton
    addSize(holder:CreateTexture())                 -- Texture
    addSize(holder:CreateFontString())              -- FontString
end

--========================================================================--
-- 13. CooldownFrame_Set / CooldownFrame_Clear (Cata helpers; on 3.3.5a only
--     Cooldown:SetCooldown exists).
--========================================================================--
if type(CooldownFrame_Set) ~= "function" then
    function CooldownFrame_Set(self, start, duration, enable, forceShowDrawEdge, modRate)
        if enable and enable ~= 0 and start and start > 0 and duration and duration > 0 then
            if self.SetDrawEdge then self:SetDrawEdge(forceShowDrawEdge and true or false) end
            self:SetCooldown(start, duration)
        else
            self:Hide()
        end
    end
end
if type(CooldownFrame_Clear) ~= "function" then
    function CooldownFrame_Clear(self)
        self:Hide()
    end
end

--========================================================================--
-- 14. SOUNDKIT (checkbox click sound). PlaySoundFile needs a file path on
--     3.3.5a; we bundle the sound under Media\Sounds.
--========================================================================--
SOUNDKIT = SOUNDKIT or {}
SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON = SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
    or "Interface\\AddOns\\CompactRaidFrame\\Media\\Sounds\\SOUNDKIT\\856.ogg"
SOUNDKIT.IG_MAINMENU_OPTION = SOUNDKIT.IG_MAINMENU_OPTION
    or "Interface\\AddOns\\CompactRaidFrame\\Media\\Sounds\\SOUNDKIT\\852.ogg"

--========================================================================--
-- 15. Misc small helpers.
--========================================================================--
if type(GMError) ~= "function" then
    function GMError(...) end  -- silent on a live client
end

-- Interface Options panel setup. These ARE native on 3.3.5a (the InterfaceOptions
-- framework exists in WotLK); the guards are insurance so CompactUnitFrameProfiles_OnLoad
-- can never abort before InterfaceOptions_AddCategory (which would hide the whole
-- "Raid Profiles" options panel). The minimal form just records the okay/cancel/
-- default/refresh callbacks the way InterfaceOptions expects.
if type(BlizzardOptionsPanel_OnLoad) ~= "function" then
    function BlizzardOptionsPanel_OnLoad(panel, okay, cancel, default, refresh)
        if not panel then return end
        panel.okay    = okay
        panel.cancel  = cancel
        panel.default = default
        panel.refresh = refresh
    end
end
if type(BlizzardOptionsPanel_OnEvent) ~= "function" then
    function BlizzardOptionsPanel_OnEvent(panel, event, ...) end
end

-- "Everyone is assistant" toggle (raid-leader convenience button).
do
    local everyoneAssistant = false
    local assistantTicker

    if type(IsEveryoneAssistant) ~= "function" then
        function IsEveryoneAssistant()
            return everyoneAssistant
        end
    end

    if type(SetEveryoneIsAssistant) ~= "function" then
        function SetEveryoneIsAssistant(enable)
            if assistantTicker then
                assistantTicker:Cancel()
                assistantTicker = nil
            end
            everyoneAssistant = enable
            local total = GetRealNumRaidMembers and GetRealNumRaidMembers() or GetNumRaidMembers()
            if not total or total < 1 then return end
            local index = 1
            assistantTicker = C_Timer.NewTicker(0.15, function()
                local unit = "raid" .. index
                if everyoneAssistant then
                    if PromoteToAssistant then PromoteToAssistant(unit) end
                else
                    if DemoteAssistant then DemoteAssistant(unit) end
                end
                index = index + 1
            end, total)
        end
    end
end

-- Click-through for aura overlay buttons. On 3.3.5a a moused-over button also
-- captures clicks, so forward the click to the parent unit button (works out of
-- combat; in-combat protected targeting is simply skipped, which is fine).
if type(PropagateTooltipMouseClicks) ~= "function" then
    function PropagateTooltipMouseClicks(self)
        self:RegisterForClicks("AnyUp")
        self:SetScript("OnClick", function(s, button, down)
            local parent = s:GetParent()
            if parent and parent.Click and not InCombatLockdown() then
                parent:Click(button, down)
            end
        end)
    end
end

-- Ready-check status. These are native on stock 3.3.5a; the guards are
-- insurance so the addon never errors if a core lacks them (ready-check icons
-- then simply don't display).
if type(GetReadyCheckStatus) ~= "function" then
    function GetReadyCheckStatus(unit) return nil end
end
if type(GetReadyCheckTimeLeft) ~= "function" then
    function GetReadyCheckTimeLeft() return 0 end
end

--========================================================================--
-- 16. C_UIDropDownMenu_* -> native UIDropDownMenu_* (the XML templates were
--     switched from C_UIDropDownMenuTemplate to the native UIDropDownMenuTemplate).
--========================================================================--
C_UIDropDownMenu_SetWidth          = C_UIDropDownMenu_SetWidth          or UIDropDownMenu_SetWidth
C_UIDropDownMenu_Initialize        = C_UIDropDownMenu_Initialize        or UIDropDownMenu_Initialize
C_UIDropDownMenu_CreateInfo        = C_UIDropDownMenu_CreateInfo        or UIDropDownMenu_CreateInfo
C_UIDropDownMenu_AddButton         = C_UIDropDownMenu_AddButton         or UIDropDownMenu_AddButton
C_UIDropDownMenu_SetSelectedValue  = C_UIDropDownMenu_SetSelectedValue  or UIDropDownMenu_SetSelectedValue
C_UIDropDownMenu_SetText           = C_UIDropDownMenu_SetText           or UIDropDownMenu_SetText
C_UIDropDownMenu_DisableDropDown   = C_UIDropDownMenu_DisableDropDown   or UIDropDownMenu_DisableDropDown
C_UIDropDownMenu_EnableDropDown    = C_UIDropDownMenu_EnableDropDown    or UIDropDownMenu_EnableDropDown
C_UIDropDownMenu_GetSelectedValue  = C_UIDropDownMenu_GetSelectedValue  or UIDropDownMenu_GetSelectedValue

-- Marker so diagnostics can confirm the compat layer loaded.
CRF_WOTLKCOMPAT_LOADED = true
