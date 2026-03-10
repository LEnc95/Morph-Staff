import { MORPH_CONFIG } from "./config.js";

function runSafely(action) {
  try {
    action();
  } catch (e) {
    // Bedrock API surface can vary by version. Failing soft keeps gameplay alive.
  }
}

function formatMessage(text) {
  return `${MORPH_CONFIG.item.messagePrefix} ${text}`;
}

export function showActionBar(player, text) {
  if (!MORPH_CONFIG.visuals.enableActionBar || !player || !text) {
    return;
  }

  const message = formatMessage(text);

  runSafely(() => {
    // VERSION NOTE: onScreenDisplay exists on modern Script API builds.
    if (player.onScreenDisplay && typeof player.onScreenDisplay.setActionBar === "function") {
      player.onScreenDisplay.setActionBar(message);
      return;
    }

    if (typeof player.sendMessage === "function") {
      player.sendMessage(message);
    }
  });
}

export function playMorphSound(player, soundId) {
  if (!MORPH_CONFIG.visuals.enableSound || !player || !soundId) {
    return;
  }

  runSafely(() => {
    // Bedrock Script API sound call.
    player.dimension.playSound(soundId, player.location);
  });
}

export function spawnMorphParticles(player, particleId = MORPH_CONFIG.visuals.morphParticleId) {
  if (!MORPH_CONFIG.visuals.enableParticles || !player || !particleId) {
    return;
  }

  const location = {
    x: player.location.x,
    y: player.location.y + 1,
    z: player.location.z
  };

  runSafely(() => {
    // VERSION NOTE: spawnParticle may be absent on older builds.
    if (typeof player.dimension.spawnParticle === "function") {
      player.dimension.spawnParticle(particleId, location);
      return;
    }

    // Command fallback for older Bedrock versions.
    const x = location.x.toFixed(2);
    const y = location.y.toFixed(2);
    const z = location.z.toFixed(2);
    player.dimension.runCommandAsync(`particle ${particleId} ${x} ${y} ${z}`);
  });
}
