// Centralized configuration only. Keep gameplay logic out of this file.
// This makes balance and extension work safer later.
export const MORPH_CONFIG = {
  item: {
    staffItemId: "morphstaff:wooden_staff",
    messagePrefix: "[Morph Staff]"
  },

  timing: {
    // Short anti-double-trigger cooldown (0.6s @ 20 TPS).
    cooldownTicks: 12,
    // Ignore immediate air-use when interact + item-use fire in same click.
    interactGraceTicks: 1,
    // Keep player invisible while morphed.
    invisibilityDurationTicks: 72000,
    invisibilityRefreshTicks: 200,
    proxySyncIntervalTicks: 1,
    garbageCollectIntervalTicks: 20,
    staleInteractForgetTicks: 120
  },

  targeting: {
    maxDistance: 6,
    forwardConeDot: 0.75
  },

  visuals: {
    enableActionBar: true,
    enableSound: true,
    enableParticles: true,
    morphStartSoundId: "random.totem",
    morphStopSoundId: "random.pop",
    morphParticleId: "minecraft:basic_flame_particle"
  },

  proxy: {
    tag: "morphstaff_proxy"
  },

  // Dedicated whitelist + per-mob extension slot.
  // abilityProfile is a placeholder hook for future custom mob abilities.
  mobs: {
    "minecraft:zombie": { abilityProfile: "none" },
    "minecraft:skeleton": { abilityProfile: "none" },
    "minecraft:cow": { abilityProfile: "none" },
    "minecraft:pig": { abilityProfile: "none" },
    "minecraft:sheep": { abilityProfile: "none" },
    "minecraft:creeper": { abilityProfile: "none" },
    "minecraft:villager": { abilityProfile: "none" }
  }
};

export const MORPHABLE_ENTITY_TYPES = new Set(Object.keys(MORPH_CONFIG.mobs));

export function isMorphableType(typeId) {
  return MORPHABLE_ENTITY_TYPES.has(typeId);
}

export function getMobMorphConfig(typeId) {
  return MORPH_CONFIG.mobs[typeId];
}
