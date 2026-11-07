(() => {
  "use strict";

  const preview = document.querySelector("[data-rico-preview]");
  if (!preview || !window.RicoLiquid || !window.RicoCastEye) return;

  const scene = preview.querySelector(".demo-scene");
  const plate = preview.querySelector(".unit-plate");
  const health = preview.querySelector(".health canvas");
  const cast = preview.querySelector(".cast-bar");
  const status = preview.querySelector(".demo-status");
  const replay = preview.querySelector(".demo-replay");
  const interrupt = preview.querySelector(".demo-interrupt");
  const distance = preview.querySelector(".demo-distance");
  const motion = preview.querySelector(".demo-motion");
  const eye = window.RicoCastEye.mount(preview.querySelector(".demo-eye"));
  const reduced = matchMedia("(prefers-reduced-motion: reduce)");
  const headers = [...document.querySelectorAll(".header-liquid")];
  const liquid = window.RicoLiquid.paint;
  const healthOptions = { tint: [0.95, 0.16, 0.12], fill: 185 / 208, health: true };
  const duration = 4200;
  let ready = true;
  let distant = false;
  let paused = false;
  let now = 0;
  let castStart = null;
  let last = null;
  let frame = null;
  let lastLiquid = -Infinity;
  let lastCastStep = -Infinity;
  const visibleHeaders = new Set(headers);

  function paintHeader(canvas) {
    const width = Math.round(canvas.clientWidth);
    if (width < 1) return;
    if (canvas.width !== width) canvas.width = width;
    liquid(canvas, now / 1000, { tint: [0.22, 0.83, 0.49], compact: canvas.height < 40 });
  }

  function paintCast() {
    const casting = castStart !== null;
    const progress = casting ? Math.min(1, (now - castStart) / duration) : 0;
    const canInterrupt = ready && !distant;
    cast.hidden = !casting;
    cast.classList.toggle("is-ready", casting && canInterrupt);
    cast.style.setProperty("--cast-progress", progress);
    cast.style.setProperty("--cast-glow", reduced.matches ? 0.58 : 0.58 + 0.16 * Math.sin(now / 200));
    eye({
      aimed: true,
      casting,
      remaining: 1 - progress,
      interrupt: canInterrupt ? "ready" : "possible",
      seconds: duration * (1 - progress) / 1000,
      reducedMotion: paused || reduced.matches || document.hidden,
    });
  }

  function announce(finished = false) {
    let message;
    if (castStart !== null) {
      message = distant ? "Shadow Bolt is aimed at you. Out of interrupt range."
        : ready ? "Shadow Bolt is aimed at you. Interrupt ready."
          : "Shadow Bolt is aimed at you. Your interrupt is unavailable.";
    } else if (finished) {
      message = "Shadow Bolt finished. Moonrage Whitescalp is still targeting you.";
    } else {
      message = distant ? "Only the targeting eye is visible at this distance."
        : "Moonrage Whitescalp is targeting you.";
    }
    if (status.textContent !== message) status.textContent = message;
  }

  function shouldAnimate() {
    return !paused && !document.hidden && (!reduced.matches || castStart !== null);
  }

  function schedule() {
    if (frame === null && shouldAnimate()) frame = requestAnimationFrame(tick);
  }

  function tick(timestamp) {
    frame = null;
    if (!shouldAnimate()) { last = null; return; }
    if (last !== null) now += timestamp - last;
    last = timestamp;
    if (!reduced.matches && now - lastLiquid >= 1000 / 24) {
      visibleHeaders.forEach(paintHeader);
      if (!distant) liquid(health, now / 1000, healthOptions);
      lastLiquid = now;
    }
    if (castStart !== null) {
      if (now - castStart >= duration) {
        castStart = null;
        paintCast();
        announce(true);
      } else if (!reduced.matches || now - lastCastStep >= 250) {
        paintCast();
        lastCastStep = now;
      }
    }
    if (!shouldAnimate()) last = null;
    schedule();
  }

  function setPaused(value) {
    paused = value;
    motion.setAttribute("aria-pressed", String(paused));
    last = null;
    paintCast();
    schedule();
  }

  function startCast() {
    castStart = now;
    lastCastStep = now;
    if (paused) setPaused(false);
    paintCast();
    announce();
    schedule();
  }

  replay.addEventListener("click", startCast);
  interrupt.addEventListener("click", () => {
    ready = !ready;
    interrupt.setAttribute("aria-pressed", String(ready));
    paintCast();
    announce();
  });
  distance.addEventListener("click", () => {
    distant = !distant;
    distance.setAttribute("aria-pressed", String(distant));
    plate.hidden = distant;
    scene.classList.toggle("is-distant", distant);
    if (!distant) liquid(health, now / 1000, healthOptions);
    paintCast();
    announce();
  });
  motion.addEventListener("click", () => setPaused(!paused));
  reduced.addEventListener("change", () => {
    if (reduced.matches && paused) setPaused(false);
    motion.hidden = reduced.matches;
    paintCast();
    schedule();
  });
  document.addEventListener("visibilitychange", () => {
    last = null;
    paintCast();
    schedule();
  });

  if (window.ResizeObserver) {
    const resize = new ResizeObserver(entries => entries.forEach(({ target }) => paintHeader(target)));
    headers.forEach(canvas => resize.observe(canvas));
  } else {
    window.addEventListener("resize", () => headers.forEach(paintHeader));
  }
  if (window.IntersectionObserver) {
    const watch = new IntersectionObserver(entries => entries.forEach(({ target, isIntersecting }) => {
      if (isIntersecting) visibleHeaders.add(target);
      else visibleHeaders.delete(target);
    }));
    headers.forEach(canvas => watch.observe(canvas));
  }

  motion.hidden = reduced.matches;
  preview.querySelector(".demo-footer").hidden = false;
  headers.forEach(paintHeader);
  liquid(health, now, healthOptions);
  if (!reduced.matches) startCast();
  else paintCast();
})();
