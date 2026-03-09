# Morph Staff (BP + RP)

A Minecraft Bedrock add-on split into:

- `Morph Staff BP` (behavior pack): gameplay logic + Script API morph system.
- `Morph Staff RP` (resource pack): client render override that hides held hand items while morphed.

## License

This repository is licensed under **PolyForm Noncommercial License 1.0.0**.

- Commercial/profit use is **not permitted**.
- This project is public as a reference/example for noncommercial use.
- See `LICENSE` for full terms.
- See `NOTICE` for required notice lines that must be preserved when sharing copies.

## Release Notes

### v1.0.8 (BP) + v1.0.2 (RP)

- Hardened runtime log discovery for gate execution (stable + preview paths, including `minecraftpe/NonAssertErrorLog.txt`).
- Added deterministic runtime log path override support:
  - `scripts/test/run-all.ps1 -LogPathOverride <path>`
  - `MORPHSTAFF_BEDROCK_LOG_PATHS` environment variable (semicolon-delimited paths)
- Strengthened manual QA evidence requirements:
  - `tester`, `minecraftVersion`, and `worldName` are required in manual results.
  - `S10`, `S11`, and `S12` require non-empty notes when marked `PASS`.
- Kept RP held-item hiding behavior tied to player invisibility state.
- Added cache reset helper for stale Bedrock pack index state:
  - `scripts/reset-stable-pack-cache.ps1`

## Why This Pack Exists

Bedrock add-ons cannot safely replace the player model at engine level for arbitrary mobs in a clean/stable way. This pack uses a practical proxy morph pattern:

- Hide the real player with invisibility.
- Spawn a mob proxy.
- Sync the proxy to player position/rotation every tick.
- Revert and clean up on manual toggle, death, proxy loss, or world leave.

## File Overview

- `manifest.json`: Behavior Pack + Script API wiring.
- `items/wooden_staff.item.json`: `morphstaff:wooden_staff` item definition.
- `recipes/wooden_staff.recipe.json`: Crafting recipe for the staff.
- `scripts/config.js`: Item id, mob whitelist, cooldown, feature toggles.
- `scripts/morphState.js`: Active morph map + cooldown/interaction state.
- `scripts/effects.js`: Action bar, sound, and particle wrappers.
- `scripts/main.js`: Event subscriptions, morph lifecycle, sync, cleanup.
- `MorphStaff_RP/manifest.json`: Resource pack manifest.
- `MorphStaff_RP/render_controllers/player.render_controllers.json`: Player render override that hides `rightItem`/`leftItem` when the player is invisible.

## Whitelist (MVP)

Current morph targets:

- `minecraft:zombie`
- `minecraft:skeleton`
- `minecraft:cow`
- `minecraft:pig`
- `minecraft:sheep`
- `minecraft:creeper`
- `minecraft:villager`

Extend by adding entity ids in `scripts/config.js` (`MORPHABLE_ENTITY_TYPES`).

## Installation (Windows)

1. Copy this repo (behavior pack root) into:
   - `%LOCALAPPDATA%\Packages\Microsoft.MinecraftUWP_8wekyb3d8bbwe\LocalState\games\com.mojang\behavior_packs\MorphStaff_BP`
2. Copy `MorphStaff_RP` into:
   - `%LOCALAPPDATA%\Packages\Microsoft.MinecraftUWP_8wekyb3d8bbwe\LocalState\games\com.mojang\resource_packs\MorphStaff_RP`
3. Start Minecraft Bedrock (stable or preview with Script API support).
4. Create/edit a world and enable:
   - `Behavior Packs` -> `Morph Staff BP`
   - `Resource Packs` -> `Morph Staff RP`
   - `Experimental` toggles needed for your version (for scripting/API).
5. Enter the world.

## Deploy To Local Production Folder

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/deploy-prod.ps1
```

This copies:

- BP files to `%LOCALAPPDATA%\\Packages\\Microsoft.MinecraftUWP_8wekyb3d8bbwe\\LocalState\\games\\com.mojang\\behavior_packs\\MorphStaff_BP`
- RP files to `%LOCALAPPDATA%\\Packages\\Microsoft.MinecraftUWP_8wekyb3d8bbwe\\LocalState\\games\\com.mojang\\resource_packs\\MorphStaff_RP`

For Preview builds, use:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/deploy-prod.ps1 -PreviewBuild
```

## Quick Test Steps

1. Get the item:
   - `/give @s morphstaff:wooden_staff`
2. Spawn test mobs from the whitelist, then right-click/use staff on one.
3. Confirm morph starts (action bar + sound/particle + proxy follows player).
   - Held items are hidden while morphed (no floating item in hand).
4. Right-click/use staff in air to revert.
   - Held items become visible again after revert.
5. Verify cleanup paths:
   - Kill player while morphed.
   - Kill proxy while morphed.
   - Leave world while morphed.

## Automated Test Harness (Strict Gate)

Run the end-to-end test pipeline:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test/run-all.ps1
```

Optional log override examples:

```powershell
$env:MORPHSTAFF_BEDROCK_LOG_PATHS = "$env:LOCALAPPDATA\\Packages\\Microsoft.MinecraftUWP_8wekyb3d8bbwe\\LocalState\\games\\com.mojang\\minecraftpe"
powershell -ExecutionPolicy Bypass -File scripts/test/run-all.ps1
```

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test/run-all.ps1 -LogPathOverride "C:\\Path\\To\\NonAssertErrorLog.txt"
```

Initialize manual results metadata for a run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test/init-manual-results.ps1 -RunDir "artifacts/test-runs/<timestamp>" -MinecraftVersion "1.21.x" -WorldName "YourWorld"
```

Find the latest passing gate artifact:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test/find-latest-pass.ps1
```

What it does:

- Runs static preflight checks.
- Captures Bedrock runtime logs before/after gameplay validation.
- Evaluates a strict release gate from preflight + runtime + manual scenario results.

Artifacts are written to:

- `artifacts/test-runs/<timestamp>/preflight-report.md`
- `artifacts/test-runs/<timestamp>/runtime-report.md`
- `artifacts/test-runs/<timestamp>/gate-summary.md`

Manual test instructions live in:

- `tests/bedrock-manual-matrix.md`

## Gameplay Rules Implemented

- Staff is the only trigger item.
- Use on valid whitelisted mob to morph.
- Use in air while morphed to revert.
- One active morph per player; no stacking.
- Cooldown: 2.0 seconds after morph/unmorph.
- Invalid target or unsupported proxy attempts fail safely.

## Compatibility Notes

- Targeted for stable-first setup:
  - `min_engine_version`: `[1, 21, 0]`
  - `@minecraft/server`: `1.13.0`
- RP item-hide behavior is tied to `query.is_invisible` for the player render controller, which matches morph state but also applies to other invisibility states.
- Sound/particle ids vary between versions; effect helpers fail safely if unavailable.
