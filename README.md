# Compact Raid Frames — stock 3.3.5a backport

A backport of **Compact Raid Frames** (Blizzard's Cataclysm-era CompactRaidFrame
system, packaged as an addon by **Tsoukie**) to **stock World of Warcraft 3.3.5a /
Wrath of the Lich King (build 12340, Lua 5.1, interface `30300`)**.

The upstream version required the separate **`!!!ClassicAPI`** addon to supply modern
retail API. **This backport removes that dependency** — it is fully self-contained and
runs on a plain 3.3.5a client.

## What changed vs. upstream

* **No ClassicAPI dependency.** Everything ClassicAPI provided is re-implemented in a
  single first-loaded compatibility layer, [`CompactRaidFrame/WotLKCompat.lua`](CompactRaidFrame/WotLKCompat.lua):
  group API (`IsInRaid`/`IsInGroup`/`GetNumGroupMembers`/…), role inference
  (`C_UnitGroupRolesAssigned` via pure-DPS class + bundled LibGroupTalents), range
  checking (`C_UnitInRange`), `C_GetInstanceInfo`, an OnUpdate-based `C_Timer`,
  `C_UIDropDownMenu_*` (aliased to the native dropdown), `Mixin`/`BackdropTemplateMixin`/
  `CreateColor`, `SetSize`/`GetSize` widget shims, `CooldownFrame_Set/Clear`, `SOUNDKIT`,
  ready-check/heal-prediction/absorb fallbacks, and more — all additive and guarded so
  nothing taints the secure UI.
* **Bundled artwork.** The raid-frame textures that shipped inside ClassicAPI now live in
  [`CompactRaidFrame/Texture/`](CompactRaidFrame/Texture); all `!!!ClassicAPI\Texture\…`
  paths were repointed at the bundled copies.
* **XML:** `C_UIDropDownMenuTemplate` → native `UIDropDownMenuTemplate`; the manager
  visibility state-driver uses the 3.3.5a-safe `[@raid1,exists][@party1,exists]` form.

## Installation

Copy the **`CompactRaidFrame`** folder (the addon, *not* the repo root) into your client:

```
<WoW 3.3.5a>\Interface\AddOns\CompactRaidFrame\
```

> The folder **must** be named `CompactRaidFrame` — the bundled texture paths are
> `Interface\AddOns\CompactRaidFrame\Texture\…`.

## Credits

* Original raid-frame system: **Blizzard Entertainment**
* Addon / 3.3.5a packaging: **Tsoukie** — <https://gitlab.com/Tsoukie/compactraidframe-3.3.5>
* Stock-3.3.5a (no-ClassicAPI) backport: **Jedborg**
