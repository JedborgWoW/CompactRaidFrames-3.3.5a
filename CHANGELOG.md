# Changelog

All notable changes to this **stock 3.3.5a backport** of Compact Raid Frames.

## [1.13] — 2026-06-30

First self-contained stock-3.3.5a release. Backported from Tsoukie's
Cataclysm-era CompactRaidFrame and **decoupled from the `!!!ClassicAPI` addon** —
it now runs on a plain WoW 3.3.5a client (build 12340, Lua 5.1, interface
`30300`) with no external dependencies.

### Removed
- Hard dependency on **`!!!ClassicAPI`** (`## RequiredDeps` gone).

### Added
- **`WotLKCompat.lua`** — first-loaded compatibility layer providing everything
  ClassicAPI used to supply, all additive and taint-safe: group API
  (`IsInRaid`/`IsInGroup`/`GetNumGroupMembers`/…), role inference
  (`C_UnitGroupRolesAssigned` via pure-DPS class + LibGroupTalents), range
  checking (`C_UnitInRange`), `C_GetInstanceInfo`, an OnUpdate-based `C_Timer`,
  `C_UIDropDownMenu_*` aliases, `CopyTable`, `Mixin`/`CreateColor`,
  `SetSize`/`GetSize` widget shims, `CooldownFrame_Set/Clear`, `SOUNDKIT`,
  guarded `BlizzardOptionsPanel_OnLoad`, ready-check fallbacks, and more.
- **`Templates.xml`** — native 3.3.5a re-implementations of ClassicAPI-only XML
  templates (`HorizontalSliderTemplate`, `UIMenuButtonStretchTemplate`).
- **`CRFEventRelay.lua`** — relays the stock `PARTY_MEMBERS_CHANGED` /
  `RAID_ROSTER_UPDATE` events to the addon's `GROUP_ROSTER_UPDATE` handlers
  (`GROUP_ROSTER_UPDATE` does not exist before MoP).
- **`CRFHealAbsorb.lua`** — heal prediction via **LibHealComm-4.0** and damage
  absorbs via **AbsorbsMonitor-1.0** (bundled with their Ace dependencies),
  wired into the CompactUnitFrame heal-prediction path.
- Bundled raid-frame artwork under **`Texture/`** (previously loaded from
  `!!!ClassicAPI\Texture\`).
- An options "ⓘ" button on the **Raid Members** manager panel that opens the
  **Raid Profiles** options page.

### Fixed
- **No frames / no config:** `CopyTable` (absent on 3.3.5a) crashed profile
  creation, so no profile activated and the container never displayed. Shimmed.
- **Frames didn't update on group changes:** the whole addon listened on the
  MoP-only `GROUP_ROSTER_UPDATE`; relayed from the real 3.3.5a roster events.
- **Options panel / sliders / manager buttons invisible:** several
  ClassicAPI-only XML templates (`UIPanelInfoButton`, `HorizontalSliderTemplate`,
  `UIMenuButtonStretchTemplate`, `DialogBorderDarkTemplate`,
  `C_UIDropDownMenuTemplate`) failed silently when ClassicAPI was removed;
  re-implemented or pointed at native templates.
- **Options panel overflowed the window:** the Cata-sized panel is larger than
  the stock Interface Options container (which doesn't scroll). Reflowed to a
  scrollable single column.
- **Stale SavedVariables:** robust defaults + AceDB-format migration so the
  panel and frames work without a manual reset.

### Notes
- Deploy the addon as the folder **`CompactRaidFrame`** (bundled texture paths
  are `Interface\AddOns\CompactRaidFrame\Texture\…`).
- Heal prediction includes HoTs; LibHealComm-4.0 can show a HoT tick ~1 tick
  ahead of when it lands (an inherent 3.3.5a limitation).
- Group/role filter buttons in the manager appear only in an actual raid.
