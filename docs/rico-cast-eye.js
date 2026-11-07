(() => {
  const assetBase = document.currentScript?.src || document.baseURI;
  const ringTexture = new URL("rico-cast-ring.png", assetBase).href;
  let instance = 0;

  function rgb(red, green, blue) {
    return `rgb(${red * 100}%, ${green * 100}%, ${blue * 100}%)`;
  }

  function line(x1, y1, x2, y2, width, color) {
    return `<line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" stroke-width="${width}" stroke="${color}"/>`;
  }

  // Plates.lua draws in coordinates measured up from each frame's bottom edge.
  const eyeShape = "M2 11 7 15 14 18 21 15 26 11 21 7 14 5 7 7Z";
  const eye = `
    <path d="${eyeShape}" fill="none" stroke="${rgb(.09, .01, .018)}" stroke-width="4.6" stroke-linejoin="bevel"/>
    ${line(8, 14, 20, 14, 4, rgb(.98, .77, .69))}
    ${line(4, 11, 24, 11, 4, rgb(.91, .54, .51))}
    ${line(8, 8, 20, 8, 3, rgb(.76, .35, .36))}
    <path d="${eyeShape}" fill="none" stroke="${rgb(.90, .12, .16)}" stroke-width="1.8" stroke-linejoin="bevel"/>
    ${line(5, 11, 10, 12, 1, rgb(.65, .04, .10))}
    ${line(19, 10, 23, 12, 1, rgb(.65, .04, .10))}
    ${line(8, 7, 7, 2, 2, rgb(.67, .05, .10))}
    ${line(18, 6, 19, 1, 2, rgb(.79, .07, .12))}
    ${line(12, 14, 16, 14, 2, rgb(.55, .04, .08))}
    ${line(11, 11, 17, 11, 4, rgb(.40, .02, .06))}
    ${line(12, 8, 16, 8, 2, rgb(.55, .04, .08))}
    <rect x="13" y="8" width="2" height="6" fill="${rgb(.045, .005, .012)}"/>
    <rect x="12" y="12" width="2" height="2" fill="${rgb(1, .88, .82)}"/>`;

  function remainingSweep(fraction) {
    if (fraction <= 0) return "";
    if (fraction >= 1) return "M0 0H58V44H0Z";
    const radius = 40;
    const angle = (1 - fraction) * 2 * Math.PI - Math.PI / 2;
    const x = 29 + radius * Math.cos(angle);
    const y = 22 + radius * Math.sin(angle);
    const longArc = fraction > .5 ? 1 : 0;
    return `M29 22L${x} ${y}A${radius} ${radius} 0 ${longArc} 1 29 ${22 - radius}Z`;
  }

  function mount(container) {
    const mask = `rico-cast-ring-${++instance}`;
    const bolt = "M7 14L3 8M3 8H7M7 8L3 1";
    container.innerHTML = `
      <svg viewBox="0 0 58 44" width="58" height="44" overflow="visible" role="img" aria-hidden="true">
        <defs>
          <mask id="${mask}" maskUnits="userSpaceOnUse" x="0" y="0" width="58" height="44" style="mask-type:alpha">
            <image width="58" height="44" preserveAspectRatio="none"/>
          </mask>
        </defs>
        <g data-cast-ring visibility="hidden" mask="url(#${mask})">
          <rect width="58" height="44" fill="${rgb(.46, .12, .095)}" opacity=".65"/>
          <path data-cast-sweep fill="${rgb(1, .44, .30)}"/>
        </g>
        <g transform="translate(29 24)">
          <g data-cast-pulse>
            <g transform="translate(-14 10.5) scale(1 -1)">${eye}</g>
          </g>
        </g>
        <g data-cast-interrupt transform="translate(52 31.5) scale(1 -1)" visibility="hidden" fill="none">
          <path d="${bolt}" stroke="${rgb(.06, .03, .015)}" stroke-width="4"/>
          <path data-cast-bolt d="${bolt}" stroke-width="2"/>
        </g>
      </svg>`;

    const svg = container.querySelector("svg");
    svg.querySelector("image").setAttribute("href", ringTexture);
    svg.setAttribute("visibility", "hidden");
    const ring = svg.querySelector("[data-cast-ring]");
    const sweep = svg.querySelector("[data-cast-sweep]");
    const pulse = svg.querySelector("[data-cast-pulse]");
    const interruptBadge = svg.querySelector("[data-cast-interrupt]");
    const boltStroke = svg.querySelector("[data-cast-bolt]");
    let animation;

    return function render({ aimed, casting, remaining, interrupt, seconds, reducedMotion }) {
      const warning = aimed && casting;
      const badge = warning && (interrupt === "ready" || interrupt === "possible");
      const label = warning && Number.isFinite(seconds)
        ? `Spell cast on you, ${Math.max(0, seconds).toFixed(1)} seconds remaining`
        : warning ? "Spell cast on you" : "Targeting you";

      svg.setAttribute("visibility", aimed ? "visible" : "hidden");
      svg.setAttribute("aria-hidden", String(!aimed));
      svg.setAttribute("aria-label", label);
      ring.setAttribute("visibility", warning ? "visible" : "hidden");
      sweep.setAttribute("d", remainingSweep(warning && Number.isFinite(remaining) ? remaining : 0));
      interruptBadge.setAttribute("visibility", badge ? "visible" : "hidden");
      if (badge) boltStroke.setAttribute("stroke", interrupt === "ready" ? rgb(.38, 1, .66) : rgb(1, .78, .35));

      pulse.style.transform = warning ? "scale(1.06)" : "";
      if (warning && !reducedMotion) {
        animation ??= pulse.animate?.([{ transform: "scale(1.06)" }, { transform: "scale(1.28)" }], {
          duration: 320,
          direction: "alternate",
          easing: "ease-in-out",
          iterations: Infinity,
        });
      } else if (animation) {
        animation.cancel();
        animation = undefined;
      }
    };
  }

  window.RicoCastEye = { mount };
})();
