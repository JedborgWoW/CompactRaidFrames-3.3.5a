--[[----------------------------------------------------------------------------
    CRFEventRelay.lua  -  backports for events that never fire on stock 3.3.5a.

    1. GROUP_ROSTER_UPDATE (MoP 5.0+). The whole CompactRaidFrame system depends
       on it (container, manager, profiles, group frames, and every unit frame's
       "update all" event), so without a relay the frames lay out exactly once
       (at profile apply) and then never refresh when the party/raid composition
       changes -> frames get stuck on stale unit tokens. On 3.3.5a the
       equivalent events are PARTY_MEMBERS_CHANGED and RAID_ROSTER_UPDATE; we
       listen to those and call the addon's existing GROUP_ROSTER_UPDATE
       handlers directly (their code branches on the event name). Combat is
       handled inside those handlers (they defer to PLAYER_REGEN_ENABLED).

    2. INCOMING_RESURRECT_CHANGED (Cata 4.x+). The center "rez" icon polls
       UnitHasIncomingResurrection (LibResComm-1.0 on this client), but nothing
       ever triggers the re-poll on stock. We listen to LibResComm's callbacks
       and refresh the center status icons directly (texture-only, combat-safe).

    3. Role updates. Roles on 3.3.5a come from LibGroupTalents talent
       inspection (async, seconds after joining) or LFG assignment
       (PLAYER_ROLES_ASSIGNED). Neither triggers the addon's role displays on
       its own, so role icons / manager role counts / role sorting stayed stale
       until the next roster change. We refresh them (coalesced to one pass per
       2s) when talent data arrives or LFG roles are assigned. The container
       re-layout goes through its GROUP_ROSTER_UPDATE handler, which defers to
       PLAYER_REGEN_ENABLED in combat.
------------------------------------------------------------------------------]]

--============================================================================--
-- Frame iteration. The addon creates unit frames under three name patterns:
--   CompactRaidFrameN         container frames ("flush" mode, pets, MT/MA)
--   CompactRaidGroupNMemberM  discrete "Keep Groups Together" mode
--   CompactPartyFrameMemberM  compact party frames
--============================================================================--
function CRF_ForEachCompactUnitFrame(func)
    for i = 1, 200 do
        local f = _G["CompactRaidFrame" .. i]
        if not f then break end
        func(f)
    end
    for g = 1, (MAX_RAID_GROUPS or 8) do
        if _G["CompactRaidGroup" .. g] then
            for m = 1, (MEMBERS_PER_RAID_GROUP or 5) do
                local f = _G["CompactRaidGroup" .. g .. "Member" .. m]
                if f then func(f) end
            end
        end
    end
    if CompactPartyFrame then
        for m = 1, (MEMBERS_PER_RAID_GROUP or 5) do
            local f = _G["CompactPartyFrameMember" .. m]
            if f then func(f) end
        end
    end
end

--============================================================================--
-- 1. GROUP_ROSTER_UPDATE relay.
--============================================================================--
local function RelayFrameRosterUpdate(f)
    -- Each unit frame uses GROUP_ROSTER_UPDATE as its "update all" event. The
    -- container/group relays re-lay-out (reassigning changed units), but frames
    -- that keep their unit still need an update for role / main-tank flags.
    if f.unit and f.updateAllEvent == "GROUP_ROSTER_UPDATE" then
        local handler = f:GetScript("OnEvent") or CompactUnitFrame_OnEvent
        handler(f, "GROUP_ROSTER_UPDATE")
    end
end

local function RelayGroupRosterUpdate()
    -- Core panels.
    if CompactRaidFrameContainer and CompactRaidFrameContainer_OnEvent then
        CompactRaidFrameContainer_OnEvent(CompactRaidFrameContainer, "GROUP_ROSTER_UPDATE")
    end
    if CompactRaidFrameManager and CompactRaidFrameManager_OnEvent then
        CompactRaidFrameManager_OnEvent(CompactRaidFrameManager, "GROUP_ROSTER_UPDATE")
    end
    if CompactUnitFrameProfiles and CompactUnitFrameProfiles_OnEvent then
        CompactUnitFrameProfiles_OnEvent(CompactUnitFrameProfiles, "GROUP_ROSTER_UPDATE")
    end

    -- Discrete-mode group frames (only exist when keepGroupsTogether is on):
    -- reassigns their member units.
    if CompactRaidGroup_OnEvent then
        for i = 1, (MAX_RAID_GROUPS or 8) do
            local g = _G["CompactRaidGroup" .. i]
            if g then CompactRaidGroup_OnEvent(g, "GROUP_ROSTER_UPDATE") end
        end
    end

    -- Every active unit frame (container, group members and party members).
    if CompactUnitFrame_OnEvent then
        CRF_ForEachCompactUnitFrame(RelayFrameRosterUpdate)
    end
end

local relay = CreateFrame("Frame")
relay:RegisterEvent("PARTY_MEMBERS_CHANGED")   -- 3.3.5a party composition change
relay:RegisterEvent("RAID_ROSTER_UPDATE")      -- 3.3.5a raid composition change
relay:RegisterEvent("PARTY_LEADER_CHANGED")
relay:RegisterEvent("PLAYER_ROLES_ASSIGNED")   -- LFG role assignment (role refresh only)

-- Exposed so other modules can force a roster refresh if needed.
CRF_RelayGroupRosterUpdate = RelayGroupRosterUpdate

--============================================================================--
-- 3. Role refresh (LibGroupTalents / LFG). Coalesced: talent scans arrive in
--    bursts when joining a group, one pass per window is enough.
--============================================================================--
local rolePending

local function RoleRefresh()
    rolePending = nil

    -- Role icons (texture-only, safe in combat). Polling the role here also
    -- lets LibGroupTalents recompute it from the fresh talent data.
    if CompactUnitFrame_UpdateRoleIcon then
        CRF_ForEachCompactUnitFrame(function(f)
            if f.unit and f.optionTable then
                CompactUnitFrame_UpdateRoleIcon(f)
            end
        end)
    end

    -- Manager header/filter role counts (text-only, safe in combat).
    if CompactRaidFrameManager and CompactRaidFrameManager_UpdateDisplayCounts then
        CompactRaidFrameManager_UpdateDisplayCounts(CompactRaidFrameManager)
    end

    -- Re-sort/re-filter the container (matters for "Sort By: Role" and the
    -- manager role filters). Its handler defers to PLAYER_REGEN_ENABLED in
    -- combat, exactly like a real GROUP_ROSTER_UPDATE.
    if CompactRaidFrameContainer and CompactRaidFrameContainer_OnEvent then
        CompactRaidFrameContainer_OnEvent(CompactRaidFrameContainer, "GROUP_ROSTER_UPDATE")
    end
end

local function ScheduleRoleRefresh()
    if rolePending then return end
    rolePending = true
    C_Timer.After(2, RoleRefresh)
end

relay:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ROLES_ASSIGNED" then
        ScheduleRoleRefresh()
    else
        RelayGroupRosterUpdate()
    end
end)

do
    local LibGT = LibStub and LibStub:GetLibrary("LibGroupTalents-1.0", true)
    if LibGT and LibGT.RegisterCallback then
        local listener = {}
        -- Update = talent data arrived (the spontaneous signal); RoleChange =
        -- a recomputed role differs (fires lazily during our own re-poll, so
        -- the refresh converges one pass after roles stabilize).
        LibGT.RegisterCallback(listener, "LibGroupTalents_Update", ScheduleRoleRefresh)
        LibGT.RegisterCallback(listener, "LibGroupTalents_RoleChange", ScheduleRoleRefresh)
    end
end

--============================================================================--
-- 2. Incoming-resurrection icon refresh via LibResComm-1.0.
--============================================================================--
do
    local ResComm = LibStub and LibStub:GetLibrary("LibResComm-1.0", true)
    if ResComm and ResComm.RegisterCallback then
        local listener = {}
        local function UpdateResIcons()
            if not CompactUnitFrame_UpdateCenterStatusIcon then return end
            CRF_ForEachCompactUnitFrame(function(f)
                if f.unit and f.optionTable then
                    CompactUnitFrame_UpdateCenterStatusIcon(f)
                end
            end)
        end
        ResComm.RegisterCallback(listener, "ResComm_ResStart",   UpdateResIcons)
        ResComm.RegisterCallback(listener, "ResComm_ResEnd",     UpdateResIcons)
        ResComm.RegisterCallback(listener, "ResComm_Ressed",     UpdateResIcons)
        ResComm.RegisterCallback(listener, "ResComm_ResExpired", UpdateResIcons)
    end
end
