# Changelog

All notable changes to this **stock 3.3.5a backport** of Compact Raid Frames.

## [1.14] — 2026-07-05

### Fixed
- **Lua error casting Sacred Shield on a sub-80 Paladin** (`AbsorbsMonitor-1.0.lua:1597:
  attempt to perform arithmetic on field '?' (a nil value)`). Divine Guardian is a
  level-80 talent, so `paladin_OnTalentUpdate` early-returned below 80 and never
  populated the player's scaling table; Sacred Shield (usable from level 74) then
  read `sourceScaling[1]` as nil and crashed. The talent handler now always seeds
  `playerScaling[1] = 1.0` before the level check, and `paladin_SacredShield_Create`
  guards against a missing *or* empty scaling table (also covering an empty table
  received over comm).

### Changed
- **Options panel restored to Blizzard's original two-column Cata layout.** Earlier
  releases reflowed the Raid Profiles panel into a single scrollable column out of
  concern that the Cata-era panel overflowed the stock 3.3.5a Interface Options
  container. It does not — the full layout (options column on the left, the
  Auto-Activate column on the right, the Frame Height / Frame Width sliders below,
  and the Reset Position button) fits the stock container as-is. Removed
  `CompactUnitFrameProfiles_FitToContainer` and its scroll-frame wrapper so the
  native XML layout renders unchanged, matching the stock Blizzard appearance.

## [1.13] — 2026-07-04

### Fixed
- **Widget-metatable shims (`SetSize`/`GetSize`) now install with `rawset`.** On
  this client the Frame-type method table carries a `__newindex` guard that
  silently swallows a plain `index.SetSize = fn` for a NEW key, so on a stock
  3.3.5a client (no ClassicAPI/awesome_wotlk) the shim was dropped and `SetSize`
  stayed nil — a latent crash at every `:SetSize` call site in LibUIDropDownMenu
  and the config panels. `WotLKCompat.lua` now adds these via `rawset` (bypassing
  the guard); the `not index.X` checks stay chain-aware so a native always wins.

## [1.13] — 2026-07-02

### Changed
- **Profiles and settings are now account-wide.** The database moved from
  per-character (`CompactRaidFrameDB`) to account-level
  (`CompactRaidFrameAccountDB`, `## SavedVariables`), so every character —
  including newly created ones — shares the same raid profiles, options and
  active profile. The **first** character you log in after updating seeds the
  account database with a copy of its existing profiles (log in with the
  character whose profiles you want to keep first); the old per-character
  data is left on disk as a backup but is no longer used.

Full audit pass against stock 3.3.5a (and awesome_wotlk): every registered
event, API call, XML template and locale string cross-checked. Three gaps
found and fixed.

### Fixed
- **Long dark vertical streaks across the screen when buffs with a duration
  were shown:** the aura buttons' Cooldown frame only had a retail-style
  CENTER anchor with no size — on 3.3.5a an instance `<Anchors>` block
  suppresses the template's inherited `setAllPoints`, and a Cooldown (model)
  with degenerate geometry renders its swipe as huge dark streaks. The
  Cooldown now has explicit `setAllPoints`, the dispel-debuff icon (the other
  anchorless region; retail auto-anchors those, 3.3.5a doesn't) got the same,
  and `CompactUnitFrame_UpdateCooldownFrame` now calls the native
  `CooldownFrame_SetTimer` directly so foreign retail-shim definitions of
  `CooldownFrame_Set` can't hijack the code path. Side effect (intended,
  matches retail): buffs/debuffs with a duration now show the radial cooldown
  swipe on their icons.
- **Incoming-resurrection icon never appeared/cleared** while someone was
  casting a res: `INCOMING_RESURRECT_CHANGED` is a Cata-era event that never
  fires on 3.3.5a. `CRFEventRelay.lua` now listens to the bundled
  LibResComm-1.0 callbacks (`ResStart`/`ResEnd`/`Ressed`/`ResExpired`) and
  refreshes the center status icon on all frames.
- **Role icons, manager role counts and "Sort By: Role" stayed stale** until
  the next roster change: LibGroupTalents learns roles asynchronously (talent
  inspection) and LFG assignment fires `PLAYER_ROLES_ASSIGNED`, but nothing
  refreshed the role displays. `CRFEventRelay.lua` now refreshes them
  (coalesced, one pass per 2 s; combat-deferred re-layout) on
  `LibGroupTalents_Update`/`_RoleChange` and `PLAYER_ROLES_ASSIGNED`.
- **Roster relay missed group-mode and party member frames:** the per-frame
  `GROUP_ROSTER_UPDATE` relay only covered `CompactRaidFrameN`; it now also
  covers `CompactRaidGroupNMemberM` ("Keep Groups Together") and
  `CompactPartyFrameMemberM` (compact party) via the new
  `CRF_ForEachCompactUnitFrame` iterator.
- **Manager visibility state driver was dead on stock:** `[@raid1,exists]`
  uses the `@` alias that only exists in 4.0+ (an unknown condition evaluates
  false, so the driver was a constant "hide" and only the event backstop kept
  the panel visible). Switched to the native `[target=raid1,exists]` form so
  the secure driver now shows/hides the manager properly, including in combat.
- **`SOUNDKIT` hardening:** entries are forced to bundled file paths if a
  foreign shim already defined them as retail numeric sound ids (which
  `PlaySoundFile` cannot play on 3.3.5a).

### Verified (no change needed)
- All registered events exist on stock 3.3.5a or are relayed/fired
  synthetically; the remaining Cata-only registrations
  (`UNIT_POWER_BAR_SHOW/HIDE`, `UNIT_HEAL_ABSORB_AMOUNT_CHANGED`) are harmless
  no-ops there and on awesome_wotlk.
- `UnitBuff`/`UnitDebuff` return-value positions, the `UnitPopup` "Set Focus"
  hider (`UIDROPDOWNMENU_INIT_MENU` is a frame and `UnitPopupShown` is nested
  per-level on 3.3.5a — checked against the 3.3.5 FrameXML source), secure
  templates, all `inherits=` targets, all texture paths and all locale
  strings.
- awesome_wotlk adds API/events on top of stock and removes nothing the addon
  uses; all shims are guarded so a native implementation always wins.

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
