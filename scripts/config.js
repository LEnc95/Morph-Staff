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
    tag: "morphstaff_proxy",
    proxyEntityOverrides: {
      // Hostile vanilla mob AI can still trigger hit-camera loops on some builds.
      // Use passive custom proxy shells that render as the matching mob.
      "minecraft:zombie": "morphstaff:zombie_proxy",
      "minecraft:husk": "morphstaff:husk_proxy",
      "minecraft:drowned": "morphstaff:drowned_proxy",
      "minecraft:skeleton": "morphstaff:skeleton_proxy",
      "minecraft:stray": "morphstaff:stray_proxy",
      "minecraft:creeper": "morphstaff:creeper_proxy"
    }
  },

  morphTargets: {
    // When true, any living non-player entity can be morphed unless denylisted below.
    // This is the default "expand to every mob" behavior.
    allowAllLivingMobs: true,
    deniedEntityTypes: [
      // Players are always denied even when allowAllLivingMobs is true.
      "minecraft:player",
      // Utility/technical entities that are not gameplay mobs.
      "minecraft:armor_stand",
      "minecraft:agent",
      "minecraft:npc",
      // Bosses denied for stability/performance and grief-risk in proxy mode.
      "minecraft:ender_dragon",
      "minecraft:wither"
    ]
  },

  // Per-mob extension slot. Keep abilityProfile entries here.
  // This map is still used even when allowAllLivingMobs is enabled.
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

const DEFAULT_MOB_MORPH_CONFIG = { abilityProfile: "none" };
export const MORPHABLE_ENTITY_TYPES = new Set(Object.keys(MORPH_CONFIG.mobs));
export const DENIED_MORPH_ENTITY_TYPES = new Set(MORPH_CONFIG.morphTargets.deniedEntityTypes || []);

export function isMorphableType(typeId) {
  if (!typeId || DENIED_MORPH_ENTITY_TYPES.has(typeId)) {
    return false;
  }

  if (MORPH_CONFIG.morphTargets.allowAllLivingMobs) {
    return true;
  }

  return MORPHABLE_ENTITY_TYPES.has(typeId);
}

export function getMobMorphConfig(typeId) {
  return MORPH_CONFIG.mobs[typeId] || DEFAULT_MOB_MORPH_CONFIG;
}

export function getProxyEntityTypeForMob(typeId) {
  const overrides = MORPH_CONFIG.proxy && MORPH_CONFIG.proxy.proxyEntityOverrides;
  if (overrides && overrides[typeId]) {
    return overrides[typeId];
  }

  return typeId;
}
