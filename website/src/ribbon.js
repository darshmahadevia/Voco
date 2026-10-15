/** @typedef {{x: number, y: number}} Pointer */

export function mountVoiceRibbon(canvas, reducedMotion) {
  const context = canvas.getContext("2d");
  if (!context) return;
  const glyphs = "·:+x*#";
  const pointer = { x: 0, y: 0 };
  const surface = [];
  const steps = 210;
  const lanes = 24;
  for (let row = 0; row < steps; row++) {
    const t = (row / steps) * Math.PI * 2;
    const x = Math.sin(2 * t) * 0.79;
    const y = Math.cos(t) * 1.26;
    const z = Math.sin(t) * 0.57;
    const tangentX = Math.cos(2 * t) * 1.58;
    const tangentY = -Math.sin(t) * 1.26;
    const length = Math.hypot(tangentX, tangentY);
    for (let lane = 0; lane < lanes; lane++) {
      const w = (lane / (lanes - 1) - 0.5) * 0.58;
      const twist = t * 0.8;
      surface.push({
        x: x - (tangentY / length) * w * Math.cos(twist),
        y: y + (tangentX / length) * w * Math.cos(twist),
        z: z + w * Math.sin(twist),
        t,
        lane,
      });
    }
  }
  let width = 0;
  let height = 0;
  let tick = 0;
  let timer = null;
  let inView = false;
  function draw() {
    if (!width || !height) return;
    context.clearRect(0, 0, width, height);
    const scale = Math.min(width / 3.6, height / 3.1);
    const phase = tick * 0.007;
    const rotateY = -0.25 + Math.sin(phase) * 0.16 + pointer.x * 0.09;
    const rotateZ = -0.3 + Math.sin(phase * 0.6) * 0.08 + pointer.y * 0.025;
    const cosY = Math.cos(rotateY);
    const sinY = Math.sin(rotateY);
    const cosZ = Math.cos(rotateZ);
    const sinZ = Math.sin(rotateZ);
    const points = surface
      .map((point) => {
        const drift = Math.sin(point.t * 3 + phase) * 0.028;
        const x = (point.x + drift) * cosY + point.z * sinY;
        const z = -(point.x + drift) * sinY + point.z * cosY;
        const y = point.y;
        const perspective = 3.8 / (3.8 + z);
        return {
          x: (x * cosZ - y * sinZ) * scale * perspective + width * 0.5,
          y: (x * sinZ + y * cosZ) * scale * perspective + height * 0.48,
          z,
          lane: point.lane,
          t: point.t,
        };
      })
      .sort((a, b) => b.z - a.z);
    const size = Math.max(5.8, Math.min(8.2, width / 68));
    context.font = `${size}px monospace`;
    context.textAlign = "center";
    context.textBaseline = "middle";
    for (const point of points) {
      const depth = Math.max(0.18, Math.min(1, 0.71 - point.z * 0.4));
      const edge = Math.min(point.lane, lanes - point.lane - 1);
      const alpha = depth * (edge < 2 ? 0.67 : 0.93);
      const brightness = Math.floor(depth * 35);
      context.fillStyle = `rgba(255,${107 + brightness},${39 + Math.floor(brightness * 0.8)},${alpha})`;
      const shade = Math.min(
        glyphs.length - 1,
        Math.floor(depth * glyphs.length),
      );
      context.fillText(glyphs[shade], point.x, point.y);
    }
  }
  function stop() {
    clearTimeout(timer);
    timer = null;
  }
  function animate() {
    timer = null;
    if (!inView || document.hidden || reducedMotion.matches) return;
    tick++;
    draw();
    timer = setTimeout(animate, 100);
  }
  function syncAnimation() {
    stop();
    draw();
    if (inView && !document.hidden && !reducedMotion.matches)
      timer = setTimeout(animate, 100);
  }
  new ResizeObserver(([entry]) => {
    width = entry.contentRect.width;
    height = entry.contentRect.height;
    const ratio = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.round(width * ratio);
    canvas.height = Math.round(height * ratio);
    context.setTransform(ratio, 0, 0, ratio, 0, 0);
    draw();
  }).observe(canvas);
  new IntersectionObserver(
    ([entry]) => {
      inView = entry.isIntersecting;
      syncAnimation();
    },
    { threshold: 0.05 },
  ).observe(canvas);
  canvas.parentElement.addEventListener(
    "pointermove",
    (event) => {
      if (reducedMotion.matches) return;
      const bounds = canvas.getBoundingClientRect();
      pointer.x = ((event.clientX - bounds.left) / bounds.width) * 2 - 1;
      pointer.y = ((event.clientY - bounds.top) / bounds.height) * 2 - 1;
    },
    { passive: true },
  );
  canvas.parentElement.addEventListener("pointerleave", () => {
    pointer.x = 0;
    pointer.y = 0;
  });
  document.addEventListener("visibilitychange", syncAnimation);
  reducedMotion.addEventListener("change", syncAnimation);
}
