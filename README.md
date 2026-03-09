# Morph Staff BP

A Minecraft Bedrock Behavior Pack that adds a `Wooden Staff` item for proxy-based morphing.

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

1. Zip the `MorphStaff_BP` folder contents, or copy the folder directly into:
   - `%LOCALAPPDATA%\Packages\Microsoft.MinecraftUWP_8wekyb3d8bbwe\LocalState\games\com.mojang\behavior_packs\MorphStaff_BP`
2. Start Minecraft Bedrock (stable or preview with Script API support).
3. Create/edit a world and enable:
   - `Behavior Packs` -> `Morph Staff BP`
   - `Experimental` toggles needed for your version (for scripting/API).
4. Enter the world.

## Quick Test Steps

1. Get the item:
   - `/give @s morphstaff:wooden_staff`
2. Spawn test mobs from the whitelist, then right-click/use staff on one.
3. Confirm morph starts (action bar + sound/particle + proxy follows player).
4. Right-click/use staff in air to revert.
5. Verify cleanup paths:
   - Kill player while morphed.
   - Kill proxy while morphed.
   - Leave world while morphed.

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
  - `@minecraft/server`: `2.5.0`
- Sound/particle ids vary between versions; effect helpers fail safely if unavailable.
