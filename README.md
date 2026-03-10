# Morph Staff (Bedrock BP + RP)

`Morph Staff` is a Minecraft Bedrock add-on with:

- `Morph Staff BP`: behavior pack gameplay + Script API runtime.
- `Morph Staff RP`: resource pack visuals (including held-item hiding while morphed).

## Current Release

- **BP:** `Morph Staff BP v1.1.21`
- **RP:** `Morph Staff RP v1.1.21`
- **Target:** Bedrock Stable/Preview 1.21.x (Windows)

### What Changed In v1.1.21

- Added RP client entity definitions for hostile proxy IDs so proxy morphs render correctly.
- Added Roaming-path deployment support to handle Bedrock installs that read from:
  - `C:\Users\<you>\AppData\Roaming\Minecraft Bedrock\...`
- Added stale-pack cleanup + redeploy workflow for duplicated old pack folders.
- Updated deploy pipeline so `deploy-prod` also syncs Roaming roots by default.
- Added stronger preflight checks to block BP proxy IDs that are missing RP client entities.

## License

This repository is licensed under **PolyForm Noncommercial License 1.0.0**.

- Commercial/profit use is **not permitted**.
- This project is public as a reference/example for noncommercial use.
- See `LICENSE` for full terms.
- See `NOTICE` for required notice lines that must be preserved when sharing copies.

## Why This Exists

Bedrock does not provide a clean, fully supported engine-level player model swap for arbitrary vanilla mobs. This add-on uses a proxy illusion pattern:

1. Hide the real player.
2. Spawn a mob proxy.
3. Sync proxy location/rotation to player every tick.
4. Revert and clean up on manual toggle, death, proxy invalidation, leave/rejoin, and other failure paths.

## Quick Start (Recommended)

Use one command to build, deploy, import, and optionally launch:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/import-local.ps1 -ForceCloseMinecraft -LaunchStable
```

This will:

- Build fresh `.mcpack/.mcaddon` artifacts.
- Deploy BP/RP folders.
- Trigger Bedrock import.
- Launch Stable Bedrock.

## Deployment Commands

### Standard deploy (LocalState + Roaming roots)

```powershell
powershell -ExecutionPolicy Bypass -File scripts/deploy-prod.ps1 -StableOnly
```

### Force cleanup of known stale test folders in Roaming roots

```powershell
powershell -ExecutionPolicy Bypass -File scripts/deploy-prod.ps1 -StableOnly -CleanRoamingKnownTestPacks
```

### Roaming-only deploy (advanced)

```powershell
powershell -ExecutionPolicy Bypass -File scripts/deploy-roaming.ps1 -CleanKnownTestPacks
```

## Important Windows Storage Note

Some Bedrock installs read pack data from Roaming locations (for example `AppData\Roaming\Minecraft Bedrock\Users\...\games\com.mojang`) instead of only UWP LocalState paths.

If you keep seeing old packs like `v1.0.7`, run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/deploy-prod.ps1 -StableOnly -CleanRoamingKnownTestPacks
```

Then fully close Bedrock and relaunch.

## Morph Target Policy

Configured in `scripts/config.js`:

- `allowAllLivingMobs: true` (all living non-player mobs allowed by default).
- Explicit deny list:
  - `minecraft:player`
  - `minecraft:armor_stand`
  - `minecraft:agent`
  - `minecraft:npc`
  - `minecraft:ender_dragon`
  - `minecraft:wither`

Hostile types routed to passive proxy shells:

- `minecraft:zombie` -> `morphstaff:zombie_proxy`
- `minecraft:husk` -> `morphstaff:husk_proxy`
- `minecraft:drowned` -> `morphstaff:drowned_proxy`
- `minecraft:skeleton` -> `morphstaff:skeleton_proxy`
- `minecraft:stray` -> `morphstaff:stray_proxy`
- `minecraft:creeper` -> `morphstaff:creeper_proxy`

## Gameplay Rules

- Staff item: `morphstaff:wooden_staff`
- Use on valid target to morph.
- Use again while morphed to revert.
- One active morph per player.
- Cooldown enforced after morph/unmorph.
- Cleanup on player death, proxy invalidation, leave/rejoin, and dimension transfer.
- Held items hidden while morphed via RP player render controller.

## File Overview

- `manifest.json`: BP manifest + script module wiring.
- `items/wooden_staff.item.json`: staff item definition.
- `recipes/*.json`: staff crafting recipes.
- `entities/*.entity.json`: BP proxy entity shells.
- `scripts/main.js`: morph lifecycle + event subscriptions.
- `scripts/config.js`: target policy, cooldowns, proxy mapping.
- `scripts/morphState.js`: per-player state and cooldown tracking.
- `scripts/effects.js`: action bar/sound/particle wrappers.
- `scripts/deploy-prod.ps1`: deploy to LocalState + Roaming roots.
- `scripts/deploy-roaming.ps1`: Roaming-root cleanup/deploy helper.
- `MorphStaff_RP/manifest.json`: RP manifest.
- `MorphStaff_RP/entity/*.entity.json`: RP client entity defs for proxies.
- `MorphStaff_RP/render_controllers/player.render_controllers.json`: hide held items when invisible.

## Test & Release Gate

Run full gate:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test/run-all.ps1
```

Manual matrix:

- `tests/bedrock-manual-matrix.md`

Artifacts:

- `artifacts/test-runs/<timestamp>/preflight-report.md`
- `artifacts/test-runs/<timestamp>/runtime-report.md`
- `artifacts/test-runs/<timestamp>/gate-summary.md`

## Compatibility Notes

- `min_engine_version`: `[1, 21, 0]`
- `@minecraft/server`: `1.13.0`
- RP item-hide behavior is tied to `query.is_invisible` and will affect any invisibility state.
- API/event availability can vary slightly across Bedrock builds; runtime code uses defensive fallbacks where possible.
