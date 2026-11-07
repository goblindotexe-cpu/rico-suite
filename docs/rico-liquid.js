(() => {
  "use strict";

  // Browser port of the procedural liquid in RicoUI.lua. Keep the geometry in
  // logical WoW pixels and let CSS scale the finished canvas to its display size.
  const { cos, min, PI, sin } = Math;
  const defaultTint = [0.28, 0.95, 0.39];
  const rgba = (r, g, b, a) => `rgba(${r * 255}, ${g * 255}, ${b * 255}, ${a})`;

  function drawWash(ctx, width, height, tint, health, compact) {
    const [r, g, b] = tint;
    const bands = health || compact ? 12 : 32;
    const bandHeight = height / bands;
    for (let i = 0; i < bands; i += 1) {
      const y = i / bands;
      const light = 0.08 + 0.25 * sin(y * PI) ** 2 + 0.08 * (1 - y);
      ctx.fillStyle = rgba(r * light, g * light, b * light, health ? 0.42 : 1);
      ctx.fillRect(0, height - (i + 1) * bandHeight - 0.35, width, bandHeight + 0.35);
    }
  }

  function wave(x, height, strand, time, health) {
    const phase = strand * 2.399;
    const u = x / (health ? 68 : 145);
    const first = (0.22 + strand * 0.012) * sin(u * (1.1 + strand * 0.13) + phase - time * (0.19 + strand * 0.017));
    const second = 0.095 * sin(u * (2.8 + strand * 0.11) - phase * 0.7 + time * 0.23);
    const third = 0.035 * cos(u * 5.2 + phase + time * 0.31);
    return height - height * (0.50 + first + second + third);
  }

  function strokeLine(ctx, x1, y1, x2, y2) {
    ctx.beginPath();
    ctx.moveTo(x1, y1);
    ctx.lineTo(x2, y2);
    ctx.stroke();
  }

  function drawRibbons(ctx, width, height, time, tint, health, compact) {
    const [r, g, b] = tint;
    const strands = health ? 3 : compact ? 2 : 5;
    const segments = health || compact ? 24 : 80;
    const glowWidth = compact ? 2.5 : health ? 5 : 9;
    const glow = rgba(r, g, b, health ? 0.12 : 0.10);
    for (let strand = 1; strand <= strands; strand += 1) {
      const points = Array.from({ length: segments + 1 }, (_, j) => {
        const x = width * j / segments;
        return [x, wave(x, height, strand, time, health)];
      });
      ctx.strokeStyle = glow;
      ctx.lineWidth = glowWidth;
      ctx.beginPath();
      ctx.moveTo(...points[0]);
      for (let j = 1; j <= segments; j += 1) ctx.lineTo(...points[j]);
      ctx.stroke();

      ctx.lineWidth = health ? 0.85 : 1.1;
      for (let j = 1; j <= segments; j += 1) {
        const [x, y] = points[j];
        const shine = 0.14 + 0.28 * sin(x * 0.021 + time * 0.38 + strand * 1.7) ** 4;
        ctx.strokeStyle = rgba(0.32 + r * 0.68, 0.26 + g * 0.74, 0.20 + b * 0.80, shine);
        strokeLine(ctx, ...points[j - 1], x, y);
      }
    }
  }

  function drawBubbles(ctx, width, height, time, tint, health, compact) {
    const [r, g, b] = tint;
    const count = health ? 3 : compact ? (height <= 4 ? 0 : 3) : 14;
    const scale = health ? 1.8 * 0.55 : 2.2;
    const segments = health ? 12 : 20;
    ctx.lineWidth = 0.8;
    for (let i = 1; i <= count; i += 1) {
      const life = (time * (0.045 + i * 0.002) + i * 0.173) % 1;
      const radius = (1.4 + (i * 7 % 5) * 0.52) * scale;
      const x = width * ((i * 0.271) % 0.96) + sin(time * 0.24 + i) * (health ? 4 : 14);
      const y = height - (-radius + life * (height + radius * 2));
      const opacity = min(1, life * 6, (1 - life) * 6) * 0.56;
      for (let j = 1; j <= segments; j += 1) {
        const a1 = (j - 1) * PI * 2 / segments;
        const a2 = j * PI * 2 / segments;
        const highlight = a1 >= PI / 6 && a1 <= PI * 5 / 6 ? 1 : 0.30;
        ctx.strokeStyle = rgba(0.30 + r * 0.7, 0.30 + g * 0.7, 0.25 + b * 0.75, opacity * highlight);
        strokeLine(ctx, x + cos(a1) * radius, y - sin(a1) * radius,
          x + cos(a2) * radius, y - sin(a2) * radius);
      }
    }
  }

  function paint(canvas, seconds, { tint = defaultTint, fill = 1, health = false, compact = false } = {}) {
    const { width, height } = canvas;
    const ctx = canvas.getContext("2d");
    if (!ctx || width <= 0 || height <= 0) return;
    const visibleWidth = width * (Number.isFinite(fill) ? Math.max(0, min(fill, 1)) : 1);
    const time = Number.isFinite(seconds) ? (seconds % 3600 + 3600) % 3600 : 0;

    ctx.save();
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, width, height);
    if (visibleWidth > 0) {
      // The status bar crops a full-width effect. Waves do not contract as HP falls.
      ctx.beginPath();
      ctx.rect(0, 0, visibleWidth, height);
      ctx.clip();
      ctx.globalAlpha = 1;
      ctx.globalCompositeOperation = "source-over";
      if (health) {
        ctx.fillStyle = rgba(...tint, 1);
        ctx.fillRect(0, 0, width, height);
      }
      drawWash(ctx, width, height, tint, health, compact);
      ctx.globalCompositeOperation = "lighter";
      ctx.lineCap = "butt";
      ctx.lineJoin = "round";
      drawRibbons(ctx, width, height, time, tint, health, compact);
      drawBubbles(ctx, width, height, time, tint, health, compact);
    }
    ctx.restore();
  }

  window.RicoLiquid = { paint };
})();
