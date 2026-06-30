--[[----------------------------------------------------------------------------
    CRFEventRelay.lua  -  GROUP_ROSTER_UPDATE backport.

    GROUP_ROSTER_UPDATE is a MoP (5.0)+ event and NEVER fires on stock 3.3.5a.
    The whole CompactRaidFrame system depends on it (container, manager, profiles,
    group frames, and every unit frame's "update all" event), so without a relay
    the frames lay out exactly once (at profile apply) and then never refresh when
    the party/raid composition changes -> frames get stuck on stale unit tokens
    (e.g. raid1/raid2 after a raid disbands to a party).

    On 3.3.5a the equivalent events are PARTY_MEMBERS_CHANGED and
    RAID_ROSTER_UPDATE. We listen to those and call the addon's existing
    GROUP_ROSTER_UPDATE handlers directly (their code branches on the event name).
    Combat is handled inside those handlers (they defer to PLAYER_REGEN_ENABLED).
------------------------------------------------------------------------------]]

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

    -- Discrete-mode group frames (only exist when keepGroupsTogether is on).
    if CompactRaidGroup_OnEvent then
        for i = 1, (MAX_RAID_GROUPS or 8) do
            local g = _G["CompactRaidGroup" .. i]
            if g then CompactRaidGroup_OnEvent(g, "GROUP_ROSTER_UPDATE") end
        end
    end

    -- Each unit frame uses GROUP_ROSTER_UPDATE as its "update all" event. The
    -- container relay above re-lays-out (reassigning changed units), but frames
    -- that keep their unit still need an update for role / main-tank flags.
    if CompactUnitFrame_OnEvent then
        for i = 1, 200 do
            local f = _G["CompactRaidFrame" .. i]
            if not f then break end
            if f.unit and f.updateAllEvent == "GROUP_ROSTER_UPDATE" then
                local handler = f:GetScript("OnEvent") or CompactUnitFrame_OnEvent
                handler(f, "GROUP_ROSTER_UPDATE")
            end
        end
    end
end

local relay = CreateFrame("Frame")
relay:RegisterEvent("PARTY_MEMBERS_CHANGED")   -- 3.3.5a party composition change
relay:RegisterEvent("RAID_ROSTER_UPDATE")      -- 3.3.5a raid composition change
relay:RegisterEvent("PARTY_LEADER_CHANGED")
relay:SetScript("OnEvent", function()
    RelayGroupRosterUpdate()
end)

-- Exposed so other modules can force a roster refresh if needed.
CRF_RelayGroupRosterUpdate = RelayGroupRosterUpdate
