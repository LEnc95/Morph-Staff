// Runtime-only state. This is intentionally in-memory for MVP.
// Bedrock currently does not guarantee script state persistence across restarts.

// playerId -> morph state object
const morphStateByPlayer = new Map();

// playerId -> tick number
const cooldownUntilByPlayer = new Map();
const lastEntityInteractTickByPlayer = new Map();
const lastItemUseTickByPlayer = new Map();

export function getMorphState(playerId) {
  return morphStateByPlayer.get(playerId);
}

export function hasMorphState(playerId) {
  return morphStateByPlayer.has(playerId);
}

export function setMorphState(playerId, state) {
  morphStateByPlayer.set(playerId, state);
}

export function deleteMorphState(playerId) {
  morphStateByPlayer.delete(playerId);
}

export function forEachMorphState(visitor) {
  for (const [playerId, state] of morphStateByPlayer.entries()) {
    visitor(playerId, state);
  }
}

export function findStateByProxyId(proxyId) {
  for (const state of morphStateByPlayer.values()) {
    if (state.proxyId === proxyId) {
      return state;
    }
  }

  return undefined;
}

export function setCooldownUntilTick(playerId, untilTick) {
  cooldownUntilByPlayer.set(playerId, untilTick);
}

export function getCooldownUntilTick(playerId) {
  const value = cooldownUntilByPlayer.get(playerId);
  return typeof value === "number" ? value : 0;
}

export function isOnCooldown(playerId, currentTick) {
  return getCooldownUntilTick(playerId) > currentTick;
}

export function clearExpiredCooldowns(currentTick) {
  for (const [playerId, untilTick] of cooldownUntilByPlayer.entries()) {
    if (untilTick <= currentTick) {
      cooldownUntilByPlayer.delete(playerId);
    }
  }
}

export function setLastEntityInteractTick(playerId, tick) {
  lastEntityInteractTickByPlayer.set(playerId, tick);
}

export function getLastEntityInteractTick(playerId) {
  return lastEntityInteractTickByPlayer.get(playerId);
}

export function setLastItemUseTick(playerId, tick) {
  lastItemUseTickByPlayer.set(playerId, tick);
}

export function getLastItemUseTick(playerId) {
  return lastItemUseTickByPlayer.get(playerId);
}

export function clearStaleInteractTicks(minimumTickToKeep) {
  for (const [playerId, tick] of lastEntityInteractTickByPlayer.entries()) {
    if (tick < minimumTickToKeep) {
      lastEntityInteractTickByPlayer.delete(playerId);
    }
  }

  for (const [playerId, tick] of lastItemUseTickByPlayer.entries()) {
    if (tick < minimumTickToKeep) {
      lastItemUseTickByPlayer.delete(playerId);
    }
  }
}

export function clearTransientPlayerState(playerId) {
  cooldownUntilByPlayer.delete(playerId);
  lastEntityInteractTickByPlayer.delete(playerId);
  lastItemUseTickByPlayer.delete(playerId);
}

export function clearAllPlayerState(playerId) {
  morphStateByPlayer.delete(playerId);
  clearTransientPlayerState(playerId);
}
