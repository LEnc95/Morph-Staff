import { system, world } from "@minecraft/server";
import { MORPH_CONFIG, getMobMorphConfig, isMorphableType } from "./config.js";
import {
  clearAllPlayerState,
  clearExpiredCooldowns,
  clearStaleInteractTicks,
  findStateByProxyId,
  forEachMorphState,
  getCooldownUntilTick,
  getLastEntityInteractTick,
  getLastItemUseTick,
  getMorphState,
  hasMorphState,
  isOnCooldown,
  setCooldownUntilTick,
  setLastEntityInteractTick,
  setLastItemUseTick,
  setMorphState
} from "./morphState.js";
import { playMorphSound, showActionBar, spawnMorphParticles } from "./effects.js";

const DIMENSION_IDS = ["overworld", "nether", "the_end"];

function getCurrentTick() {
  return typeof system.currentTick === "number" ? system.currentTick : 0;
}

function safeSubscribe(signal, handler) {
  if (!signal || typeof signal.subscribe !== "function") {
    return false;
  }

  try {
    signal.subscribe(handler);
    return true;
  } catch (e) {
    return false;
  }
}

function safeRunInterval(callback, intervalTicks) {
  try {
    system.runInterval(callback, intervalTicks);
    return true;
  } catch (e) {
    return false;
  }
}

function isEntityValid(entity) {
  if (!entity) {
    return false;
  }

  try {
    return entity.isValid();
  } catch (e) {
    return false;
  }
}

function isPlayerEntity(entity) {
  return !!entity && entity.typeId === "minecraft:player";
}

function normalizeDimensionId(rawDimensionId) {
  if (rawDimensionId === "minecraft:overworld" || rawDimensionId === "overworld") {
    return "overworld";
  }

  if (rawDimensionId === "minecraft:nether" || rawDimensionId === "nether") {
    return "nether";
  }

  if (rawDimensionId === "minecraft:the_end" || rawDimensionId === "the_end") {
    return "the_end";
  }

  return "overworld";
}

function getPlayerById(playerId) {
  for (const player of world.getAllPlayers()) {
    if (player.id === playerId) {
      return player;
    }
  }

  return undefined;
}

function getEntityById(entityId, preferredDimensionId) {
  if (!entityId) {
    return undefined;
  }

  // VERSION NOTE: world.getEntity exists on newer Bedrock Script API versions.
  try {
    if (typeof world.getEntity === "function") {
      const resolved = world.getEntity(entityId);
      if (resolved) {
        return resolved;
      }
    }
  } catch (e) {
    // Fall through to dimension scanning.
  }

  const preferred = normalizeDimensionId(preferredDimensionId);
  const dimensionsToScan = [preferred];
  for (const id of DIMENSION_IDS) {
    if (id !== preferred) {
      dimensionsToScan.push(id);
    }
  }

  for (const dimensionId of dimensionsToScan) {
    try {
      const dimension = world.getDimension(dimensionId);

      // VERSION NOTE: dimension.getEntity may be missing on older versions.
      if (typeof dimension.getEntity !== "function") {
        continue;
      }

      const resolved = dimension.getEntity(entityId);
      if (resolved) {
        return resolved;
      }
    } catch (e) {
      // Keep scanning.
    }
  }

  return undefined;
}

function getMainhandItem(player) {
  try {
    const inventory = player.getComponent("minecraft:inventory");
    const container = inventory ? inventory.container : undefined;
    if (!container) {
      return undefined;
    }

    return container.getItem(player.selectedSlotIndex);
  } catch (e) {
    return undefined;
  }
}

function isStaffItem(itemStack) {
  return !!itemStack && itemStack.typeId === MORPH_CONFIG.item.staffItemId;
}

function isHoldingMorphStaff(player, itemStack) {
  if (!isEntityValid(player)) {
    return false;
  }

  if (isStaffItem(itemStack)) {
    return true;
  }

  return isStaffItem(getMainhandItem(player));
}

function isAllowedMorphTarget(target) {
  if (!isEntityValid(target)) {
    return false;
  }

  if (isPlayerEntity(target)) {
    return false;
  }

  if (!isMorphableType(target.typeId)) {
    return false;
  }

  // Prevent morphing into another player's active proxy.
  if (findStateByProxyId(target.id)) {
    return false;
  }

  return true;
}

function formatMobName(typeId) {
  return typeId.replace("minecraft:", "");
}

function applyShortCooldown(playerId) {
  setCooldownUntilTick(playerId, getCurrentTick() + MORPH_CONFIG.timing.cooldownTicks);
}

function showCooldownMessage(player, nowTick) {
  const ticksLeft = Math.max(0, getCooldownUntilTick(player.id) - nowTick);
  const secondsLeft = (ticksLeft / 20).toFixed(1);
  showActionBar(player, `Cooldown: ${secondsLeft}s`);
}

function setPlayerInvisible(player, shouldBeInvisible) {
  if (!isEntityValid(player)) {
    return;
  }

  if (shouldBeInvisible) {
    try {
      player.addEffect("invisibility", MORPH_CONFIG.timing.invisibilityDurationTicks, {
        amplifier: 0,
        showParticles: false
      });
      return;
    } catch (e) {
      // Fall back to command when addEffect signature differs by version.
    }

    try {
      // VERSION NOTE: runCommandAsync fallback can require cheats depending on version/settings.
      const seconds = Math.max(1, Math.floor(MORPH_CONFIG.timing.invisibilityDurationTicks / 20));
      player.runCommandAsync(`effect @s invisibility ${seconds} 0 true`);
    } catch (e) {
      // Best-effort only.
    }

    return;
  }

  try {
    player.removeEffect("invisibility");
    return;
  } catch (e) {
    // Fall back to command.
  }

  try {
    player.runCommandAsync("effect @s clear invisibility");
  } catch (e) {
    // Best-effort only.
  }
}

function setPlayerMorphVisualTag(player, isMorphed) {
  if (!isEntityValid(player)) {
    return;
  }

  const tag = "morphstaff_morphed";
  try {
    if (isMorphed) {
      if (!player.hasTag(tag)) {
        player.addTag(tag);
      }
      return;
    }

    if (player.hasTag(tag)) {
      player.removeTag(tag);
    }
  } catch (e) {
    // Best-effort only.
  }
}

function getLookTargetEntity(player, maxDistance = MORPH_CONFIG.targeting.maxDistance) {
  if (!isEntityValid(player)) {
    return undefined;
  }

  // Preferred API on newer Bedrock versions.
  // VERSION NOTE: getEntitiesFromViewDirection is not available everywhere.
  if (typeof player.getEntitiesFromViewDirection === "function") {
    try {
      const hits = player.getEntitiesFromViewDirection({ maxDistance });
      if (Array.isArray(hits)) {
        for (const hit of hits) {
          const entity = hit ? hit.entity : undefined;
          if (isEntityValid(entity)) {
            return entity;
          }
        }
      }
    } catch (e) {
      // Continue with fallback.
    }
  }

  // Fallback for older runtimes: nearest morphable entity in a forward cone.
  try {
    if (typeof player.getViewDirection !== "function") {
      return undefined;
    }

    const view = player.getViewDirection();
    const nearby = player.dimension.getEntities({
      location: player.location,
      maxDistance
    });

    let best = undefined;
    let bestDistance = Number.POSITIVE_INFINITY;

    for (const entity of nearby) {
      if (!isAllowedMorphTarget(entity)) {
        continue;
      }

      const dx = entity.location.x - player.location.x;
      const dy = entity.location.y - player.location.y;
      const dz = entity.location.z - player.location.z;
      const distanceSq = dx * dx + dy * dy + dz * dz;
      if (distanceSq <= 0.0001) {
        continue;
      }

      const distance = Math.sqrt(distanceSq);
      const inv = 1 / distance;
      const dirX = dx * inv;
      const dirY = dy * inv;
      const dirZ = dz * inv;
      const dot = dirX * view.x + dirY * view.y + dirZ * view.z;

      if (dot >= MORPH_CONFIG.targeting.forwardConeDot && distance < bestDistance) {
        best = entity;
        bestDistance = distance;
      }
    }

    return best;
  } catch (e) {
    return undefined;
  }
}

function removeProxyByState(state) {
  if (!state) {
    return;
  }

  const proxy = getEntityById(state.proxyId, state.dimensionId);
  if (!isEntityValid(proxy)) {
    return;
  }

  // Clear name tag first so no proxy keeps the player's name if remove() fails.
  try {
    proxy.nameTag = "";
  } catch (e) {
    // Best-effort only.
  }

  try {
    proxy.remove();
  } catch (e) {
    // Ignore cleanup removal failure.
  }
}

function createMorphState(player, proxy, mobTypeId, nowTick) {
  const mobConfig = getMobMorphConfig(mobTypeId) || { abilityProfile: "none" };

  return {
    playerId: player.id,
    proxyId: proxy.id,
    mobTypeId,
    abilityProfile: mobConfig.abilityProfile,
    dimensionId: normalizeDimensionId(player.dimension.id),
    startedTick: nowTick,
    lastInvisibilityRefreshTick: nowTick
  };
}

function startMorph(player, targetEntity) {
  if (!isEntityValid(player)) {
    return false;
  }

  if (!isAllowedMorphTarget(targetEntity)) {
    return false;
  }

  const mobTypeId = targetEntity.typeId;
  const now = getCurrentTick();

  if (hasMorphState(player.id)) {
    return false;
  }

  if (isOnCooldown(player.id, now)) {
    showCooldownMessage(player, now);
    return false;
  }

  let proxy;
  try {
    // Bedrock proxy approach: player is hidden and a mob entity is synced as visual shell.
    proxy = player.dimension.spawnEntity(mobTypeId, player.location);
  } catch (e) {
    showActionBar(player, "Morph failed: unable to spawn proxy.");
    return false;
  }

  if (!isEntityValid(proxy)) {
    showActionBar(player, "Morph failed: invalid proxy entity.");
    return false;
  }

  try {
    proxy.addTag(MORPH_CONFIG.proxy.tag);
  } catch (e) {
    // Optional metadata tag.
  }

  try {
    proxy.nameTag = player.name;
  } catch (e) {
    // Optional cosmetic.
  }

  setPlayerInvisible(player, true);
  setPlayerMorphVisualTag(player, true);

  const state = createMorphState(player, proxy, mobTypeId, now);
  setMorphState(player.id, state);
  applyShortCooldown(player.id);

  syncMorphProxy(player, state, proxy);

  showActionBar(player, `Morphed into ${formatMobName(mobTypeId)}.`);
  playMorphSound(player, MORPH_CONFIG.visuals.morphStartSoundId);
  spawnMorphParticles(player);

  return true;
}

function stopMorph(player, reason = "manual") {
  if (!isEntityValid(player)) {
    return false;
  }

  const state = getMorphState(player.id);
  if (!state) {
    return false;
  }

  removeProxyByState(state);
  clearAllPlayerState(player.id);
  setPlayerInvisible(player, false);
  setPlayerMorphVisualTag(player, false);
  applyShortCooldown(player.id);

  if (reason === "manual") {
    showActionBar(player, "Returned to player form.");
  } else if (reason === "death") {
    showActionBar(player, "Morph cleared on death.");
  } else if (reason === "proxy_invalid") {
    showActionBar(player, "Morph cleared: proxy was removed.");
  }

  playMorphSound(player, MORPH_CONFIG.visuals.morphStopSoundId);
  spawnMorphParticles(player);

  return true;
}

function cleanupMorphState(playerId, reason = "cleanup") {
  const state = getMorphState(playerId);
  if (!state) {
    clearAllPlayerState(playerId);
    return;
  }

  removeProxyByState(state);
  clearAllPlayerState(playerId);

  const player = getPlayerById(playerId);
  if (!isEntityValid(player)) {
    return;
  }

  setPlayerInvisible(player, false);
  setPlayerMorphVisualTag(player, false);

  if (reason === "death") {
    showActionBar(player, "Morph cleared on death.");
  } else if (reason === "proxy_invalid") {
    showActionBar(player, "Morph cleared: proxy invalid.");
  } else if (reason === "disconnect") {
    // Player has already left. No feedback needed.
  }

  if (reason !== "disconnect") {
    playMorphSound(player, MORPH_CONFIG.visuals.morphStopSoundId);
    spawnMorphParticles(player);
  }
}

function recreateProxyInPlayerDimension(state, player) {
  removeProxyByState(state);

  let replacement;
  try {
    replacement = player.dimension.spawnEntity(state.mobTypeId, player.location);
  } catch (e) {
    cleanupMorphState(state.playerId, "proxy_invalid");
    return undefined;
  }

  if (!isEntityValid(replacement)) {
    cleanupMorphState(state.playerId, "proxy_invalid");
    return undefined;
  }

  try {
    replacement.addTag(MORPH_CONFIG.proxy.tag);
  } catch (e) {
    // Optional metadata tag.
  }

  state.proxyId = replacement.id;
  state.dimensionId = normalizeDimensionId(player.dimension.id);
  setMorphState(state.playerId, state);

  return replacement;
}

function syncMorphProxy(playerOverride, state, proxyOverride) {
  const player = playerOverride || getPlayerById(state.playerId);
  if (!isEntityValid(player)) {
    cleanupMorphState(state.playerId, "disconnect");
    return;
  }

  let proxy = proxyOverride || getEntityById(state.proxyId, state.dimensionId);
  if (!isEntityValid(proxy)) {
    cleanupMorphState(state.playerId, "proxy_invalid");
    return;
  }

  const playerDimensionId = normalizeDimensionId(player.dimension.id);
  const proxyDimensionId = normalizeDimensionId(proxy.dimension.id);
  if (playerDimensionId !== proxyDimensionId) {
    proxy = recreateProxyInPlayerDimension(state, player);
    if (!isEntityValid(proxy)) {
      return;
    }
  }

  try {
    // VERSION NOTE: teleport rotation option support can differ by API version.
    const teleportOptions = {
      dimension: player.dimension
    };

    if (typeof player.getRotation === "function") {
      teleportOptions.rotation = player.getRotation();
    }

    proxy.teleport(player.location, teleportOptions);
  } catch (e) {
    cleanupMorphState(state.playerId, "proxy_invalid");
  }
}

function applyMobAbilityTick(state, player, proxy) {
  // Extension hook for future custom mob abilities.
  // Example future profiles: "creeper_blast", "skeleton_ranged", "cow_milk".
  // Keep this side-effect-free unless you explicitly add ability behavior.
  switch (state.abilityProfile) {
    case "none":
    default:
      return;
  }
}

function handleMorphAttemptFromEntity(player, target) {
  const now = getCurrentTick();

  // Deduplicate if both beforeEvents and afterEvents fire on same interaction.
  if (getLastEntityInteractTick(player.id) === now) {
    return;
  }
  setLastEntityInteractTick(player.id, now);

  if (hasMorphState(player.id)) {
    showActionBar(player, "Already morphed. Use staff again to revert.");
    return;
  }

  if (isOnCooldown(player.id, now)) {
    showCooldownMessage(player, now);
    return;
  }

  if (!isAllowedMorphTarget(target)) {
    showActionBar(player, "That entity cannot be morphed.");
    return;
  }

  startMorph(player, target);
}

function handleStaffUse(player, itemStack) {
  if (!isHoldingMorphStaff(player, itemStack)) {
    return;
  }

  const now = getCurrentTick();

  // Deduplicate same-tick item use from beforeEvents + afterEvents.
  if (getLastItemUseTick(player.id) === now) {
    return;
  }
  setLastItemUseTick(player.id, now);

  const lastEntityInteractTick = getLastEntityInteractTick(player.id);
  if (
    typeof lastEntityInteractTick === "number" &&
    now - lastEntityInteractTick <= MORPH_CONFIG.timing.interactGraceTicks
  ) {
    return;
  }

  if (hasMorphState(player.id)) {
    stopMorph(player, "manual");
    return;
  }

  if (isOnCooldown(player.id, now)) {
    showCooldownMessage(player, now);
    return;
  }

  const lookTarget = getLookTargetEntity(player);
  if (!lookTarget) {
    showActionBar(player, "Use staff on a whitelisted mob.");
    return;
  }

  if (!isAllowedMorphTarget(lookTarget)) {
    showActionBar(player, "That entity cannot be morphed.");
    return;
  }

  startMorph(player, lookTarget);
}

function syncAllMorphs() {
  const now = getCurrentTick();

  forEachMorphState((playerId, state) => {
    const player = getPlayerById(playerId);
    if (!isEntityValid(player)) {
      cleanupMorphState(playerId, "disconnect");
      return;
    }

    const proxy = getEntityById(state.proxyId, state.dimensionId);
    if (!isEntityValid(proxy)) {
      cleanupMorphState(playerId, "proxy_invalid");
      return;
    }

    syncMorphProxy(player, state, proxy);
    applyMobAbilityTick(state, player, proxy);

    if (now - state.lastInvisibilityRefreshTick >= MORPH_CONFIG.timing.invisibilityRefreshTicks) {
      setPlayerInvisible(player, true);
      state.lastInvisibilityRefreshTick = now;
      setMorphState(playerId, state);
    }
  });
}

function garbageCollectMorphs() {
  const now = getCurrentTick();

  forEachMorphState((playerId) => {
    const player = getPlayerById(playerId);
    if (!isEntityValid(player)) {
      cleanupMorphState(playerId, "disconnect");
    }
  });

  clearExpiredCooldowns(now);
  clearStaleInteractTicks(now - MORPH_CONFIG.timing.staleInteractForgetTicks);
}

function onPlayerInteractWithEntity(event) {
  const player = event ? event.player || event.source : undefined;
  const target = event ? event.target || event.targetEntity : undefined;

  if (!isEntityValid(player) || !isEntityValid(target)) {
    return;
  }

  if (!isHoldingMorphStaff(player)) {
    return;
  }

  handleMorphAttemptFromEntity(player, target);
}

function onItemUse(event) {
  const player = event ? event.source : undefined;
  if (!isPlayerEntity(player)) {
    return;
  }

  handleStaffUse(player, event.itemStack);
}

function onEntityDie(event) {
  const deadEntity = event ? event.deadEntity : undefined;
  if (!isEntityValid(deadEntity)) {
    return;
  }

  // Player death cleanup.
  if (hasMorphState(deadEntity.id)) {
    cleanupMorphState(deadEntity.id, "death");
    return;
  }

  // Proxy death cleanup.
  const ownerState = findStateByProxyId(deadEntity.id);
  if (ownerState) {
    cleanupMorphState(ownerState.playerId, "proxy_invalid");
  }
}

function onPlayerLeave(event) {
  const playerId = event ? event.playerId : undefined;
  if (!playerId) {
    return;
  }

  cleanupMorphState(playerId, "disconnect");
}

function onPlayerSpawn(event) {
  const player = event ? event.player : undefined;
  if (!isEntityValid(player)) {
    return;
  }

  // Defensive cleanup in case a previous session ended unexpectedly.
  setPlayerMorphVisualTag(player, false);

  // Friendly readiness feedback.
  // VERSION NOTE: event.initialSpawn may not exist on some older builds.
  if (event.initialSpawn === false) {
    return;
  }

  showActionBar(player, "Staff ready. Use on a whitelisted mob.");
}

const afterEvents = world.afterEvents || {};
const beforeEvents = world.beforeEvents || {};

// VERSION NOTE: beforeEvents signals are not present on every Bedrock build.
safeSubscribe(afterEvents.playerInteractWithEntity, onPlayerInteractWithEntity);
safeSubscribe(beforeEvents.playerInteractWithEntity, onPlayerInteractWithEntity);

safeSubscribe(afterEvents.itemUse, onItemUse);
safeSubscribe(beforeEvents.itemUse, onItemUse);

safeSubscribe(afterEvents.entityDie, onEntityDie);
safeSubscribe(afterEvents.playerLeave, onPlayerLeave);
safeSubscribe(afterEvents.playerSpawn, onPlayerSpawn);

safeRunInterval(syncAllMorphs, MORPH_CONFIG.timing.proxySyncIntervalTicks);
safeRunInterval(garbageCollectMorphs, MORPH_CONFIG.timing.garbageCollectIntervalTicks);
