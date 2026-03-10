# Bedrock Manual Test Matrix (Stable 1.21.x)

Use this matrix with `scripts/test/run-all.ps1`.

## Environment Setup

- Minecraft Bedrock Stable 1.21.x on Windows.
- Behavior pack installed and enabled.
- Resource pack installed and enabled (`Morph Staff RP`).
- Required experiments/toggles for Script API enabled in the world.
- Cheats enabled for command-driven scenarios.

## Global Commands

```mcfunction
/gamerule showtags true
/give @s morphstaff:wooden_staff
```

Morph target policy for this pack:
- Allow all living non-player entities by default.
- Denied entity ids:
  - `minecraft:player`
  - `minecraft:armor_stand`
  - `minecraft:agent`
  - `minecraft:npc`
  - `minecraft:ender_dragon`
  - `minecraft:wither`

## Scenario Matrix

### S01 - Pack load and world entry

Commands:
```mcfunction
/reload
```

Pass criteria:
- World loads with pack enabled.
- No fatal script/runtime error shown in logs or chat.
- Action bar readiness message appears on initial spawn.

### S02 - Staff grant

Commands:
```mcfunction
/clear @s morphstaff:wooden_staff
/give @s morphstaff:wooden_staff
```

Pass criteria:
- Give command succeeds.
- Staff appears in inventory and can be selected.

### S03 - Morph start on allowed mobs

Commands:
```mcfunction
/summon zombie ~2 ~ ~
/summon husk ~3 ~ ~
/summon drowned ~4 ~ ~
/summon skeleton ~5 ~ ~
/summon stray ~6 ~ ~
/summon cow ~7 ~ ~
/summon pig ~8 ~ ~
/summon sheep ~9 ~ ~
/summon creeper ~10 ~ ~
/summon villager ~11 ~ ~
/summon chicken ~12 ~ ~
```

Actions:
- Use staff directly on each mob type at least once.

Pass criteria:
- Morph starts for each listed mob.
- Player becomes invisible and proxy appears.
- Action bar and effects trigger without script errors.

### S04 - Manual revert

Actions:
- While morphed, use the staff in air.

Pass criteria:
- Morph stops and player returns to normal visibility.
- Proxy is removed.
- Revert feedback appears.

### S05 - Cooldown behavior

Actions:
- Attempt rapid re-use immediately after morph and immediately after revert.

Pass criteria:
- Cooldown message appears.
- Morph/revert cannot be spam-triggered within cooldown window.
- Behavior recovers after cooldown expires.

### S06 - Invalid target rejection

Commands:
```mcfunction
/summon armor_stand ~2 ~ ~
```

Actions:
- Try staff use on `minecraft:armor_stand`.

Pass criteria:
- Morph does not start.
- Rejection message appears.
- No new proxy persists.

### S07 - Proxy death cleanup

Actions:
- Start morph.
- Kill proxy (hit it or use kill command targeting it).

Pass criteria:
- Morph state clears automatically.
- Player becomes visible again.
- No orphan proxy remains.

### S08 - Player death cleanup

Actions:
- Start morph.
- Kill player.

Pass criteria:
- Morph state clears on death.
- Player respawns in normal state.
- No orphan proxy remains.

### S09 - Leave/rejoin cleanup

Actions:
- Start morph.
- Leave world and rejoin.

Pass criteria:
- No stuck invisibility.
- No stale proxy bound to prior session.
- Staff still functions on rejoin.

### S10 - Dimension transfer while morphed

Commands:
```mcfunction
/give @s flint_and_steel
/give @s obsidian 14
```

Actions:
- Start morph in Overworld.
- Move to Nether (or End) and continue moving.

Pass criteria:
- Proxy is recreated/synced in destination dimension.
- Morph remains functional or safely clears with explicit feedback.
- No persistent orphan proxy in source dimension.

### S11 - Repeatability stress (10 cycles)

Actions:
- Perform 10 consecutive morph -> revert cycles on an allowed mob.

Pass criteria:
- No cycle fails.
- No duplicate or orphan proxies accumulate.
- No stuck invisibility after final cycle.
- No new runtime errors in logs.

### S12 - Held item visibility while morphed

Actions:
- Hold a visible item (for example, `minecraft:diamond_sword`) in main hand.
- Start morph.
- Observe player in third person (F5) while moving and using the held item.
- Revert back to normal.

Pass criteria:
- While morphed, held hand items are hidden (no floating held-item visual).
- Item use still works while morphed.
- After revert, normal held-item visuals return.

## Recording Results

Update `manual-results.json` in your current run directory.

Required statuses:
- Every required scenario `S01` through `S12` must be `PASS` for a release gate pass.
- Any `FAIL`, `SKIP`, or missing scenario is a release blocker.
- When `S10`, `S11`, or `S12` are marked `PASS`, add non-empty notes in `manual-results.json` with what was observed.
