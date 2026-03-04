(() => {
  const canvas = document.getElementById("game");
  const ctx = canvas.getContext("2d");
  const scoreText = document.getElementById("scoreText");
  const waveText = document.getElementById("waveText");
  const energyText = document.getElementById("energyText");
  const messageBar = document.getElementById("messageBar");

  const WORLD_W = canvas.width;
  const WORLD_H = canvas.height;

  const state = {
    mode: "menu",
    time: 0,
    score: 0,
    highScore: 0,
    wave: 1,
    waveTimer: 0,
    spawnTimer: 0,
    pulses: [],
    particles: [],
    enemies: [],
    pickups: [],
    stars: [],
    input: {
      left: false,
      right: false,
      up: false,
      down: false,
      dash: false,
      pulse: false,
    },
    player: {
      x: WORLD_W / 2,
      y: WORLD_H / 2,
      vx: 0,
      vy: 0,
      speed: 460,
      radius: 18,
      energy: 100,
      dashCooldown: 0,
      pulseCooldown: 0,
      trail: [],
      dashInvuln: 0,
    },
    cameraShake: 0,
  };

  for (let i = 0; i < 180; i += 1) {
    state.stars.push({
      x: Math.random() * WORLD_W,
      y: Math.random() * WORLD_H,
      z: 0.4 + Math.random() * 1.4,
      tw: Math.random() * Math.PI * 2,
    });
  }

  function resetRun() {
    state.mode = "running";
    state.time = 0;
    state.score = 0;
    state.wave = 1;
    state.waveTimer = 0;
    state.spawnTimer = 0;
    state.pulses.length = 0;
    state.particles.length = 0;
    state.enemies.length = 0;
    state.pickups.length = 0;
    state.player.x = WORLD_W / 2;
    state.player.y = WORLD_H / 2;
    state.player.vx = 0;
    state.player.vy = 0;
    state.player.energy = 100;
    state.player.dashCooldown = 0;
    state.player.pulseCooldown = 0;
    state.player.trail.length = 0;
    state.player.dashInvuln = 0;
    messageBar.textContent = "Survive the void. Build score. Dash through danger.";
    for (let i = 0; i < 5; i += 1) {
      spawnEnemy();
    }
    for (let i = 0; i < 3; i += 1) {
      spawnPickup();
    }
  }

  function clamp(v, lo, hi) {
    return Math.max(lo, Math.min(hi, v));
  }

  function rand(lo, hi) {
    return lo + Math.random() * (hi - lo);
  }

  function spawnEnemy() {
    const side = Math.floor(Math.random() * 4);
    let x;
    let y;
    if (side === 0) {
      x = rand(0, WORLD_W);
      y = -40;
    } else if (side === 1) {
      x = WORLD_W + 40;
      y = rand(0, WORLD_H);
    } else if (side === 2) {
      x = rand(0, WORLD_W);
      y = WORLD_H + 40;
    } else {
      x = -40;
      y = rand(0, WORLD_H);
    }

    const tier = 1 + Math.floor(Math.random() * Math.min(4, 1 + Math.floor(state.wave / 2)));
    const radius = 12 + tier * 4;
    const speed = 80 + tier * 36 + state.wave * 8;
    const hp = 1 + Math.floor((tier + state.wave * 0.25) / 2);

    let tries = 0;
    while (Math.hypot(x - state.player.x, y - state.player.y) < 260 && tries < 10) {
      x = rand(-60, WORLD_W + 60);
      y = rand(-60, WORLD_H + 60);
      tries += 1;
    }

    state.enemies.push({
      x,
      y,
      vx: 0,
      vy: 0,
      radius,
      speed,
      hp,
      maxHp: hp,
      hue: 300 - tier * 28,
      orbit: Math.random() * Math.PI * 2,
    });
  }

  function spawnPickup() {
    const kind = Math.random() < 0.7 ? "energy" : "score";
    state.pickups.push({
      x: rand(80, WORLD_W - 80),
      y: rand(80, WORLD_H - 80),
      radius: kind === "energy" ? 10 : 8,
      kind,
      life: rand(12, 20),
      pulse: Math.random() * Math.PI * 2,
    });
  }

  function emitBurst(x, y, color, count) {
    for (let i = 0; i < count; i += 1) {
      const a = Math.random() * Math.PI * 2;
      const speed = rand(40, 280);
      state.particles.push({
        x,
        y,
        vx: Math.cos(a) * speed,
        vy: Math.sin(a) * speed,
        life: rand(0.4, 1.1),
        maxLife: 1,
        size: rand(1.5, 3.8),
        color,
      });
    }
  }

  function triggerPulse() {
    if (state.player.pulseCooldown > 0 || state.player.energy < 12 || state.mode !== "running") return;
    state.player.pulseCooldown = 1.2;
    state.player.energy = clamp(state.player.energy - 12, 0, 100);
    state.pulses.push({ x: state.player.x, y: state.player.y, r: 8, life: 0.55 });
    emitBurst(state.player.x, state.player.y, "#2ff6ff", 40);
  }

  function triggerDash() {
    if (state.player.dashCooldown > 0 || state.player.energy < 20 || state.mode !== "running") return;
    const ax = (state.input.right ? 1 : 0) - (state.input.left ? 1 : 0);
    const ay = (state.input.down ? 1 : 0) - (state.input.up ? 1 : 0);
    let nx = ax;
    let ny = ay;
    const len = Math.hypot(nx, ny);
    if (len < 0.001) {
      nx = 0;
      ny = -1;
    } else {
      nx /= len;
      ny /= len;
    }

    state.player.vx += nx * 740;
    state.player.vy += ny * 740;
    state.player.energy = clamp(state.player.energy - 20, 0, 100);
    state.player.dashCooldown = 2.1;
    state.player.dashInvuln = 0.28;
    state.cameraShake = Math.max(state.cameraShake, 10);
    emitBurst(state.player.x, state.player.y, "#ff3ea5", 45);
  }

  function damagePlayer(amount) {
    if (state.player.dashInvuln > 0 || state.mode !== "running") return;
    state.player.energy = clamp(state.player.energy - amount, 0, 100);
    state.cameraShake = Math.max(state.cameraShake, 14);
    emitBurst(state.player.x, state.player.y, "#ff5f8d", 35);
    if (state.player.energy <= 0) {
      state.mode = "gameover";
      state.highScore = Math.max(state.highScore, Math.floor(state.score));
      messageBar.textContent = `Run over. Score ${Math.floor(state.score)} | Press R to try again.`;
    }
  }

  function update(dt) {
    state.time += dt;

    if (state.mode === "menu") return;
    if (state.mode === "paused") return;

    const p = state.player;
    if (state.mode === "running") {
      p.energy = clamp(p.energy + dt * 2.2, 0, 100);
    }
    p.dashCooldown = Math.max(0, p.dashCooldown - dt);
    p.pulseCooldown = Math.max(0, p.pulseCooldown - dt);
    p.dashInvuln = Math.max(0, p.dashInvuln - dt);

    if (state.mode === "running") {
      state.score += dt * (6 + state.wave * 0.7);
      state.waveTimer += dt;
      if (state.waveTimer > 18) {
        state.wave += 1;
        state.waveTimer = 0;
        state.cameraShake = Math.max(state.cameraShake, 8);
        emitBurst(p.x, p.y, "#7c8dff", 50);
        messageBar.textContent = `Wave ${state.wave} incoming.`;
      }
    }

    const ax = (state.input.right ? 1 : 0) - (state.input.left ? 1 : 0);
    const ay = (state.input.down ? 1 : 0) - (state.input.up ? 1 : 0);
    const len = Math.hypot(ax, ay) || 1;

    p.vx += (ax / len) * p.speed * dt * 3.8;
    p.vy += (ay / len) * p.speed * dt * 3.8;
    p.vx *= 0.9;
    p.vy *= 0.9;

    p.x += p.vx * dt;
    p.y += p.vy * dt;

    if (p.x < p.radius) {
      p.x = p.radius;
      p.vx *= -0.22;
      damagePlayer(2);
    }
    if (p.x > WORLD_W - p.radius) {
      p.x = WORLD_W - p.radius;
      p.vx *= -0.22;
      damagePlayer(2);
    }
    if (p.y < p.radius) {
      p.y = p.radius;
      p.vy *= -0.22;
      damagePlayer(2);
    }
    if (p.y > WORLD_H - p.radius) {
      p.y = WORLD_H - p.radius;
      p.vy *= -0.22;
      damagePlayer(2);
    }

    p.trail.push({ x: p.x, y: p.y, t: state.time });
    while (p.trail.length > 22) p.trail.shift();

    state.spawnTimer -= dt;
    if (state.mode === "running" && state.spawnTimer <= 0) {
      state.spawnTimer = Math.max(0.22, 1.3 - state.wave * 0.08);
      spawnEnemy();
      if (Math.random() < 0.26) spawnPickup();
    }

    for (const enemy of state.enemies) {
      enemy.orbit += dt * (1.2 + enemy.speed / 260);
      const dx = p.x - enemy.x;
      const dy = p.y - enemy.y;
      const l = Math.hypot(dx, dy) || 1;
      const tx = dx / l;
      const ty = dy / l;
      const spiral = Math.sin(enemy.orbit) * 0.5;
      enemy.vx += (tx - ty * spiral) * enemy.speed * dt;
      enemy.vy += (ty + tx * spiral) * enemy.speed * dt;
      enemy.vx *= 0.95;
      enemy.vy *= 0.95;
      enemy.x += enemy.vx * dt;
      enemy.y += enemy.vy * dt;
    }

    for (const pulse of state.pulses) {
      pulse.r += 860 * dt;
      pulse.life -= dt;
    }
    state.pulses = state.pulses.filter((pulse) => pulse.life > 0);

    for (let i = state.enemies.length - 1; i >= 0; i -= 1) {
      const enemy = state.enemies[i];

      for (const pulse of state.pulses) {
        const d = Math.hypot(enemy.x - pulse.x, enemy.y - pulse.y);
        if (d < pulse.r + enemy.radius && d > pulse.r - 30) {
          enemy.hp -= 1;
          enemy.vx *= 0.5;
          enemy.vy *= 0.5;
          emitBurst(enemy.x, enemy.y, `hsl(${enemy.hue} 100% 65%)`, 15);
        }
      }

      const dp = Math.hypot(enemy.x - p.x, enemy.y - p.y);
      if (dp < enemy.radius + p.radius) {
        if (p.dashInvuln > 0) {
          enemy.hp = 0;
          state.score += 18;
          emitBurst(enemy.x, enemy.y, "#ffd65e", 24);
        } else {
          damagePlayer(14 + enemy.radius * 0.15);
        }
      }

      if (enemy.hp <= 0) {
        state.score += 10 + enemy.maxHp * 4;
        state.enemies.splice(i, 1);
      }
    }

    for (let i = state.pickups.length - 1; i >= 0; i -= 1) {
      const pickup = state.pickups[i];
      pickup.life -= dt;
      pickup.pulse += dt * 4;
      if (pickup.life <= 0) {
        state.pickups.splice(i, 1);
        continue;
      }
      const d = Math.hypot(pickup.x - p.x, pickup.y - p.y);
      if (d < pickup.radius + p.radius) {
        if (pickup.kind === "energy") {
          p.energy = clamp(p.energy + 26, 0, 100);
          messageBar.textContent = "Energy cell collected.";
          emitBurst(pickup.x, pickup.y, "#66ff99", 18);
        } else {
          state.score += 40;
          messageBar.textContent = "Score shard collected.";
          emitBurst(pickup.x, pickup.y, "#ffe066", 18);
        }
        state.pickups.splice(i, 1);
      }
    }

    for (const particle of state.particles) {
      particle.life -= dt;
      particle.x += particle.vx * dt;
      particle.y += particle.vy * dt;
      particle.vx *= 0.97;
      particle.vy *= 0.97;
    }
    state.particles = state.particles.filter((pt) => pt.life > 0);

    state.cameraShake = Math.max(0, state.cameraShake - dt * 26);

    scoreText.textContent = `Score: ${Math.floor(state.score)}`;
    waveText.textContent = `Wave: ${state.wave}`;
    energyText.textContent = `Energy: ${Math.floor(state.player.energy)}`;
  }

  function drawGrid() {
    const t = state.time;
    const grad = ctx.createLinearGradient(0, 0, 0, WORLD_H);
    grad.addColorStop(0, "#090f28");
    grad.addColorStop(1, "#140422");
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, WORLD_W, WORLD_H);

    for (const star of state.stars) {
      const tw = 0.35 + Math.sin(star.tw + t * star.z * 2) * 0.3;
      ctx.fillStyle = `rgba(152,220,255,${0.25 + tw})`;
      ctx.beginPath();
      ctx.arc(star.x, star.y, star.z * 1.5, 0, Math.PI * 2);
      ctx.fill();
    }

    ctx.lineWidth = 1;
    for (let x = -40; x <= WORLD_W + 40; x += 40) {
      ctx.strokeStyle = `rgba(34,130,220,${0.08 + Math.sin(t + x * 0.01) * 0.04})`;
      ctx.beginPath();
      ctx.moveTo(x + Math.sin(t * 2 + x * 0.04) * 5, 0);
      ctx.lineTo(x + Math.sin(t * 2 + x * 0.04) * 5, WORLD_H);
      ctx.stroke();
    }
    for (let y = -40; y <= WORLD_H + 40; y += 40) {
      ctx.strokeStyle = `rgba(56,220,255,${0.07 + Math.cos(t + y * 0.013) * 0.03})`;
      ctx.beginPath();
      ctx.moveTo(0, y + Math.cos(t * 1.8 + y * 0.03) * 5);
      ctx.lineTo(WORLD_W, y + Math.cos(t * 1.8 + y * 0.03) * 5);
      ctx.stroke();
    }
  }

  function drawPlayer() {
    const p = state.player;
    for (let i = 0; i < p.trail.length; i += 1) {
      const tr = p.trail[i];
      const alpha = i / p.trail.length;
      ctx.fillStyle = `rgba(255,64,168,${alpha * 0.3})`;
      ctx.beginPath();
      ctx.arc(tr.x, tr.y, p.radius * alpha * 0.8, 0, Math.PI * 2);
      ctx.fill();
    }

    const pulse = 0.6 + Math.sin(state.time * 12) * 0.2;
    ctx.save();
    ctx.translate(p.x, p.y);
    ctx.rotate(state.time * 1.6);

    ctx.shadowBlur = 24;
    ctx.shadowColor = "#3ad7ff";
    ctx.fillStyle = "rgba(32,239,255,0.22)";
    ctx.beginPath();
    ctx.arc(0, 0, p.radius * 1.8 * pulse, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = "#0fdfff";
    ctx.beginPath();
    ctx.moveTo(0, -p.radius);
    ctx.lineTo(p.radius * 0.8, p.radius * 0.9);
    ctx.lineTo(-p.radius * 0.8, p.radius * 0.9);
    ctx.closePath();
    ctx.fill();

    ctx.strokeStyle = "#ffffff";
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(0, -p.radius * 0.7);
    ctx.lineTo(0, p.radius * 0.55);
    ctx.stroke();

    if (p.dashInvuln > 0) {
      ctx.strokeStyle = "#ff3ea5";
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.arc(0, 0, p.radius * 1.6, 0, Math.PI * 2);
      ctx.stroke();
    }

    ctx.restore();
  }

  function drawEnemies() {
    for (const enemy of state.enemies) {
      ctx.save();
      ctx.translate(enemy.x, enemy.y);
      ctx.rotate(enemy.orbit * 0.7);
      ctx.shadowBlur = 20;
      ctx.shadowColor = `hsl(${enemy.hue} 100% 60%)`;

      ctx.strokeStyle = `hsl(${enemy.hue} 100% 58%)`;
      ctx.lineWidth = 2.5;
      ctx.beginPath();
      for (let k = 0; k < 6; k += 1) {
        const a = (Math.PI * 2 * k) / 6;
        const rr = enemy.radius * (k % 2 === 0 ? 1 : 0.6);
        const x = Math.cos(a) * rr;
        const y = Math.sin(a) * rr;
        if (k === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      }
      ctx.closePath();
      ctx.stroke();

      if (enemy.hp > 1) {
        ctx.fillStyle = "rgba(255,255,255,0.85)";
        ctx.fillRect(-enemy.radius, enemy.radius + 6, (enemy.radius * 2 * enemy.hp) / enemy.maxHp, 3);
      }
      ctx.restore();
    }
  }

  function drawPickups() {
    for (const pickup of state.pickups) {
      const pulse = 1 + Math.sin(pickup.pulse) * 0.2;
      const color = pickup.kind === "energy" ? "#66ff99" : "#ffe066";
      ctx.strokeStyle = color;
      ctx.fillStyle = `${color}33`;
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.arc(pickup.x, pickup.y, pickup.radius * pulse, 0, Math.PI * 2);
      ctx.fill();
      ctx.stroke();
    }
  }

  function drawPulses() {
    for (const pulse of state.pulses) {
      ctx.strokeStyle = `rgba(96,245,255,${pulse.life * 1.8})`;
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.arc(pulse.x, pulse.y, pulse.r, 0, Math.PI * 2);
      ctx.stroke();
    }
  }

  function drawParticles() {
    for (const pt of state.particles) {
      ctx.fillStyle = pt.color;
      ctx.globalAlpha = Math.max(0, pt.life / pt.maxLife);
      ctx.beginPath();
      ctx.arc(pt.x, pt.y, pt.size, 0, Math.PI * 2);
      ctx.fill();
      ctx.globalAlpha = 1;
    }
  }

  function drawModeOverlays() {
    if (state.mode === "menu") {
      ctx.fillStyle = "rgba(8,12,30,0.68)";
      ctx.fillRect(0, 0, WORLD_W, WORLD_H);
      ctx.textAlign = "center";
      ctx.fillStyle = "#ffffff";
      ctx.font = "700 68px 'Trebuchet MS'";
      ctx.fillText("NEON VOID RUNNER", WORLD_W / 2, WORLD_H / 2 - 80);
      ctx.font = "400 28px 'Trebuchet MS'";
      ctx.fillText("Press Enter to Start", WORLD_W / 2, WORLD_H / 2 - 22);
      ctx.font = "400 22px 'Trebuchet MS'";
      ctx.fillStyle = "#90c9ff";
      ctx.fillText("Survive waves, chain score, and use pulse + dash smartly.", WORLD_W / 2, WORLD_H / 2 + 24);
      ctx.fillText("WASD/Arrows move | Shift dash | Space pulse", WORLD_W / 2, WORLD_H / 2 + 60);
      ctx.fillText("P pause | R restart | F fullscreen", WORLD_W / 2, WORLD_H / 2 + 92);
    } else if (state.mode === "paused") {
      ctx.fillStyle = "rgba(3,6,16,0.58)";
      ctx.fillRect(0, 0, WORLD_W, WORLD_H);
      ctx.textAlign = "center";
      ctx.fillStyle = "#ffffff";
      ctx.font = "700 56px 'Trebuchet MS'";
      ctx.fillText("PAUSED", WORLD_W / 2, WORLD_H / 2 - 20);
      ctx.font = "400 24px 'Trebuchet MS'";
      ctx.fillStyle = "#9ec1ff";
      ctx.fillText("Press P (or Enter) to resume", WORLD_W / 2, WORLD_H / 2 + 24);
    } else if (state.mode === "gameover") {
      ctx.fillStyle = "rgba(6,2,18,0.62)";
      ctx.fillRect(0, 0, WORLD_W, WORLD_H);
      ctx.textAlign = "center";
      ctx.fillStyle = "#ff90be";
      ctx.font = "700 64px 'Trebuchet MS'";
      ctx.fillText("SYSTEM COLLAPSE", WORLD_W / 2, WORLD_H / 2 - 46);
      ctx.fillStyle = "#ffffff";
      ctx.font = "400 30px 'Trebuchet MS'";
      ctx.fillText(`Final Score: ${Math.floor(state.score)}`, WORLD_W / 2, WORLD_H / 2 + 4);
      ctx.fillText(`High Score: ${Math.floor(state.highScore)}`, WORLD_W / 2, WORLD_H / 2 + 42);
      ctx.font = "400 24px 'Trebuchet MS'";
      ctx.fillStyle = "#9cc4ff";
      ctx.fillText("Press R (or Enter) to restart", WORLD_W / 2, WORLD_H / 2 + 88);
    }
  }

  function render() {
    const shake = state.cameraShake;
    const sx = shake > 0 ? rand(-shake, shake) : 0;
    const sy = shake > 0 ? rand(-shake, shake) : 0;

    ctx.save();
    ctx.translate(sx, sy);
    drawGrid();
    drawPickups();
    drawPulses();
    drawEnemies();
    drawPlayer();
    drawParticles();
    ctx.restore();
    drawModeOverlays();
  }

  function loop(ts) {
    const now = ts * 0.001;
    const dt = Math.min(1 / 25, Math.max(1 / 120, now - (loop.last || now)));
    loop.last = now;
    update(dt);
    render();
    requestAnimationFrame(loop);
  }

  function setInputByKey(code, pressed) {
    if (code === "ArrowLeft" || code === "KeyA") state.input.left = pressed;
    if (code === "ArrowRight" || code === "KeyD") state.input.right = pressed;
    if (code === "ArrowUp" || code === "KeyW") state.input.up = pressed;
    if (code === "ArrowDown" || code === "KeyS") state.input.down = pressed;
  }

  function togglePause() {
    if (state.mode === "running") {
      state.mode = "paused";
      messageBar.textContent = "Paused.";
    } else if (state.mode === "paused") {
      state.mode = "running";
      messageBar.textContent = "Back in the void.";
    }
  }

  async function toggleFullscreen() {
    try {
      if (!document.fullscreenElement) {
        await canvas.requestFullscreen();
      } else {
        await document.exitFullscreen();
      }
    } catch {
      // Ignore fullscreen failures.
    }
  }

  window.addEventListener("keydown", (event) => {
    if (["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Space"].includes(event.code)) {
      event.preventDefault();
    }

    if (event.repeat) return;

    setInputByKey(event.code, true);

    if (event.code === "Enter" && state.mode === "menu") {
      resetRun();
    } else if (event.code === "Enter" && (state.mode === "running" || state.mode === "paused")) {
      togglePause();
    } else if (event.code === "Enter" && state.mode === "gameover") {
      resetRun();
    }
    if (event.code === "KeyR") {
      resetRun();
    }
    if (event.code === "KeyP") {
      togglePause();
    }
    if (event.code === "ShiftLeft" || event.code === "ShiftRight" || event.code === "KeyB") {
      triggerDash();
    }
    if (event.code === "Space" && state.mode === "gameover") {
      resetRun();
    } else if (event.code === "Space") {
      triggerPulse();
    }
    if (event.code === "KeyF") {
      toggleFullscreen();
    }
  });

  window.addEventListener("keyup", (event) => {
    setInputByKey(event.code, false);
  });

  const stickPad = document.getElementById("stickPad");
  const pulseBtn = document.getElementById("pulseBtn");
  const dashBtn = document.getElementById("dashBtn");

  if (stickPad) {
    let touching = false;
    stickPad.addEventListener("pointerdown", (event) => {
      touching = true;
      if (typeof stickPad.setPointerCapture === "function") {
        stickPad.setPointerCapture(event.pointerId);
      }
    });
    stickPad.addEventListener("pointermove", (event) => {
      if (!touching) return;
      const rect = stickPad.getBoundingClientRect();
      const cx = rect.left + rect.width / 2;
      const cy = rect.top + rect.height / 2;
      const dx = clamp((event.clientX - cx) / (rect.width / 2), -1, 1);
      const dy = clamp((event.clientY - cy) / (rect.height / 2), -1, 1);
      state.input.left = dx < -0.25;
      state.input.right = dx > 0.25;
      state.input.up = dy < -0.25;
      state.input.down = dy > 0.25;
    });
    const clearStick = () => {
      touching = false;
      state.input.left = false;
      state.input.right = false;
      state.input.up = false;
      state.input.down = false;
    };
    stickPad.addEventListener("pointerup", clearStick);
    stickPad.addEventListener("pointercancel", clearStick);
    stickPad.addEventListener("pointerleave", clearStick);
  }

  pulseBtn?.addEventListener("pointerdown", () => {
    if (state.mode === "menu") resetRun();
    triggerPulse();
  });

  dashBtn?.addEventListener("pointerdown", () => {
    if (state.mode === "menu") resetRun();
    triggerDash();
  });

  function renderGameToText() {
    const payload = {
      mode: state.mode,
      score: Math.floor(state.score),
      highScore: Math.floor(state.highScore),
      wave: state.wave,
      coordinateSystem: "origin=(0,0) top-left, x rightward, y downward",
      player: {
        x: Number(state.player.x.toFixed(1)),
        y: Number(state.player.y.toFixed(1)),
        vx: Number(state.player.vx.toFixed(1)),
        vy: Number(state.player.vy.toFixed(1)),
        radius: state.player.radius,
        energy: Number(state.player.energy.toFixed(1)),
        dashCooldown: Number(state.player.dashCooldown.toFixed(2)),
        pulseCooldown: Number(state.player.pulseCooldown.toFixed(2)),
        invulnerable: state.player.dashInvuln > 0,
      },
      enemies: state.enemies.slice(0, 20).map((e) => ({
        x: Number(e.x.toFixed(1)),
        y: Number(e.y.toFixed(1)),
        radius: e.radius,
        hp: e.hp,
        speed: Number(e.speed.toFixed(1)),
      })),
      pickups: state.pickups.slice(0, 20).map((p) => ({
        x: Number(p.x.toFixed(1)),
        y: Number(p.y.toFixed(1)),
        kind: p.kind,
        radius: p.radius,
        ttl: Number(p.life.toFixed(1)),
      })),
      pulses: state.pulses.length,
      particles: state.particles.length,
    };
    return JSON.stringify(payload);
  }

  window.render_game_to_text = renderGameToText;
  window.advanceTime = (ms) => {
    const step = 1000 / 60;
    const n = Math.max(1, Math.round(ms / step));
    for (let i = 0; i < n; i += 1) update(step / 1000);
    render();
  };

  requestAnimationFrame(loop);
})();
