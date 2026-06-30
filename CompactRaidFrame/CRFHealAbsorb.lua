--[[----------------------------------------------------------------------------
    CRFHealAbsorb.lua  -  heal prediction (LibHealComm-4.0) + damage absorbs
    (AbsorbsMonitor-1.0) for the stock-3.3.5a backport.

    The source repo dropped these libs and relied on ClassicAPI no-ops. We bundle
    the proven WotLK libs and wire them into the CompactUnitFrame heal-prediction
    code path. Everything here is GUARDED: if a library is missing the unit-frame
    system is completely unaffected and the bars simply stay hidden (the no-op
    fallbacks in WotLKCompat.lua remain in force).

    Loads AFTER CompactUnitFrame.xml (needs CompactUnitFrame_OnLoad /
    DefaultCompactUnitFrameOptions) and AFTER Libs\Load.xml (needs the libs).
------------------------------------------------------------------------------]]

local HealComm  = LibStub and LibStub:GetLibrary("LibHealComm-4.0", true)
local LibAbsorb = LibStub and LibStub:GetLibrary("AbsorbsMonitor-1.0", true)

local UnitGUID, UnitExists, GetTime = UnitGUID, UnitExists, GetTime

--========================================================================--
-- Incoming heals.  CompactUnitFrame_UpdateHealPrediction calls:
--   UnitGetIncomingHeals(unit, "player")  -> heals on `unit` cast by me
--   UnitGetIncomingHeals(unit)            -> all incoming heals on `unit`
-- LibHealComm's GetHealAmount(guid, bitFlag, time, casterGUID) gives both.
--========================================================================--
if HealComm then
    -- ALL_HEALS = direct + channelled + HoTs. HoT ticks are predicted by LibHealComm
    -- the instant the HoT is applied, so the bar can sit ~1 tick ahead of the actual
    -- tick (an inherent LibHealComm-4.0 limitation on 3.3.5a), but the user prefers
    -- having HoT prediction over not having it.
    local HEAL_FLAGS = HealComm.ALL_HEALS
    function UnitGetIncomingHeals(unit, healer)
        if not unit then return end
        local guid = UnitGUID(unit)
        if not guid then return end
        if healer then
            local hguid = UnitGUID(healer)
            if not hguid then return end
            return HealComm:GetHealAmount(guid, HEAL_FLAGS, GetTime() + 5, hguid)
        end
        return HealComm:GetHealAmount(guid, HEAL_FLAGS, GetTime() + 5)
    end
end

--========================================================================--
-- Damage absorbs (Power Word: Shield, Divine Aegis, Sacred Shield, Ice Barrier,
-- Mana Shield, etc. — AbsorbsMonitor-1.0 tracks them via UNIT_AURA + combat log
-- and exposes a per-GUID total).
--========================================================================--
if LibAbsorb then
    function UnitGetTotalAbsorbs(unit)
        if not unit then return end
        local guid = UnitGUID(unit)
        local total = guid and LibAbsorb.Unit_Total(guid)
        if not total or total < 0 then return 0 end  -- guard the AbsorbMonitor TexCoord bug
        return total
    end
end

--========================================================================--
-- Per-frame callback wiring.  The libs broadcast global heal/absorb changes; we
-- re-flag the affected frame, and CompactUnitFrame's dirty-flag batching
-- (SetHealPredictionDirty -> OnUpdate) re-queries the real amount once per frame.
--========================================================================--
local function FireEvent(self, event)
    if CompactUnitFrame_OnEvent then
        CompactUnitFrame_OnEvent(self, event, self.unit or self.displayedUnit)
    end
end

local function HealCallback(self)
    if self.unit and UnitExists(self.unit) and UnitGUID(self.unit) then
        FireEvent(self, "UNIT_HEAL_PREDICTION")
    end
end

local function AbsorbCallback(self)
    if self.unit and UnitExists(self.unit) and UnitGUID(self.unit) then
        FireEvent(self, "UNIT_ABSORB_AMOUNT_CHANGED")
    end
end

function CompactUnitFrame_RegisterCallback(self)
    if self._crfHealAbsorbRegistered then return end
    self._crfHealAbsorbRegistered = true

    if HealComm then
        HealComm.RegisterCallback(self, "HealComm_HealStarted",     HealCallback, self)
        HealComm.RegisterCallback(self, "HealComm_HealUpdated",     HealCallback, self)
        HealComm.RegisterCallback(self, "HealComm_HealDelayed",     HealCallback, self)
        HealComm.RegisterCallback(self, "HealComm_HealStopped",     HealCallback, self)
        HealComm.RegisterCallback(self, "HealComm_ModifierChanged", HealCallback, self)
        HealComm.RegisterCallback(self, "HealComm_GUIDDisappeared", HealCallback, self)
    end

    if LibAbsorb then
        LibAbsorb.RegisterCallback(self, "EffectApplied", AbsorbCallback, self)
        LibAbsorb.RegisterCallback(self, "EffectUpdated", AbsorbCallback, self)
        LibAbsorb.RegisterCallback(self, "EffectRemoved", AbsorbCallback, self)
        LibAbsorb.RegisterCallback(self, "UnitUpdated",   AbsorbCallback, self)
        LibAbsorb.RegisterCallback(self, "UnitCleared",   AbsorbCallback, self)
    end
end

-- The source's CompactUnitFrame_OnLoad does not register lib callbacks (the
-- standalone's did). Hook it so every unit frame wires up on creation.
if (HealComm or LibAbsorb) and type(CompactUnitFrame_OnLoad) == "function" then
    hooksecurefunc("CompactUnitFrame_OnLoad", function(self)
        CompactUnitFrame_RegisterCallback(self)
    end)
end

--========================================================================--
-- Turn heal prediction ON by default (the source's option tables left it unset,
-- so the bars never drew even when a heal lib was present). The setup code
-- (DefaultCompactUnitFrameSetup) already creates the prediction/absorb textures.
--========================================================================--
if (HealComm or LibAbsorb) then
    if DefaultCompactUnitFrameOptions then
        DefaultCompactUnitFrameOptions.displayHealPrediction = true
    end
    if DefaultCompactMiniFrameOptions then
        DefaultCompactMiniFrameOptions.displayHealPrediction = true
    end
end
