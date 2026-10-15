import "./style.css";

const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
const samples = {
  message: {
    destination: "A message to your team",
    context: "To the people building with you",
    title: "A little room to think",
    text: "I have an idea. Let's take the complicated part out and make the first five minutes feel effortless.",
  },
  note: {
    destination: "A note for your future self",
    context: "Before this one gets away",
    title: "An idea worth keeping",
    text: "What if the best version is the one with fewer steps? Start with the moment someone needs help, and work backwards.",
  },
  email: {
    destination: "An email, without the overthinking",
    context: "To Alex · A fresh pair of eyes",
    title: "About that first draft",
    text: "I've been thinking about your feedback. You were right about the opening. Let's give the idea more room and the introduction fewer words.",
  },
};
const phases = {
  idle: {
    label: "Illustrative demo. Microphone access is off.",
    action: "Replay the thought",
  },
  listening: {
    label: "Example listening. Your text field stays untouched.",
    action: "Following the thought",
    delay: 2300,
    next: "transcribing",
  },
  transcribing: {
    label: "Example transcription. Finishing on your Mac.",
    action: "Finishing the words",
    delay: 850,
    next: "complete",
  },
  complete: {
    label: "Words inserted together. Illustrative demo.",
    action: "Replay the thought",
  },
};
const state = { sample: "message", phase: "idle", timer: null };
const stage = document.querySelector(".voice-stage");
const play = document.querySelector("#demo-play");
const cancel = document.querySelector("#demo-cancel");
const sampleButtons = [...document.querySelectorAll("[data-sample]")];
function setPhase(phase) {
  clearTimeout(state.timer);
  state.timer = null;
  state.phase = phase;
  stage.dataset.phase = phase;
  const current = phases[phase];
  const sample = samples[state.sample];
  const active = phase === "listening" || phase === "transcribing";
  document.querySelector("#demo-action").textContent = current.action;
  document.querySelector("#demo-status").textContent = current.label;
  document.querySelector("#demo-destination").textContent = sample.destination;
  document.querySelector("#demo-context").textContent = sample.context;
  document.querySelector("#demo-title").textContent = sample.title;
  document.querySelector("#demo-output").textContent = active
    ? "Your thought is on its way."
    : sample.text;
  if (!active && document.activeElement === cancel)
    play.focus({ preventScroll: true });
  play.disabled = active;
  cancel.hidden = !active;
  if (current.delay)
    state.timer = setTimeout(() => setPhase(current.next), current.delay);
}
play.addEventListener("click", () => {
  setPhase(reducedMotion.matches ? "complete" : "listening");
  if (!cancel.hidden) cancel.focus({ preventScroll: true });
});
cancel.addEventListener("click", () => setPhase("idle"));
stage.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && !cancel.hidden) {
    setPhase("idle");
    play.focus({ preventScroll: true });
  }
});
sampleButtons.forEach((button) =>
  button.addEventListener("click", () => {
    state.sample = button.dataset.sample;
    sampleButtons.forEach((item) =>
      item.setAttribute("aria-pressed", String(item === button)),
    );
    setPhase("idle");
  }),
);
const menuButton = document.querySelector(".menu-toggle");
const mobileMenu = document.querySelector("#mobile-nav");
function setMenu(open) {
  menuButton.setAttribute("aria-expanded", String(open));
  menuButton.setAttribute(
    "aria-label",
    open ? "Close navigation" : "Open navigation",
  );
  mobileMenu.hidden = !open;
}
menuButton.addEventListener("click", () => setMenu(mobileMenu.hidden));
mobileMenu.addEventListener("click", (event) => {
  if (event.target.closest("a")) setMenu(false);
});
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && !mobileMenu.hidden) {
    setMenu(false);
    menuButton.focus();
  }
});
matchMedia("(min-width: 641px)").addEventListener("change", (event) => {
  if (event.matches) setMenu(false);
});
const galleryButtons = [...document.querySelectorAll("[data-gallery]")];
const descriptions = {
  home: "The actual Voco interface. Example transcripts and statistics are sample data.",
  settings:
    "Choose your output quality, local speech model, permissions, and dictation preferences.",
  stats:
    "A real interface capture with sample activity and estimated typing time saved.",
};
function selectGallery(index, focus = false) {
  galleryButtons.forEach((button, position) => {
    const selected = position === index;
    button.setAttribute("aria-selected", String(selected));
    button.tabIndex = selected ? 0 : -1;
    document.querySelector(`#panel-${button.dataset.gallery}`).hidden =
      !selected;
  });
  document.querySelector("#gallery-description").textContent =
    descriptions[galleryButtons[index].dataset.gallery];
  if (focus) galleryButtons[index].focus();
}
galleryButtons.forEach((button, index) => {
  button.addEventListener("click", () => selectGallery(index));
  button.addEventListener("keydown", (event) => {
    const navigation = {
      ArrowRight: (index + 1) % galleryButtons.length,
      ArrowLeft: (index + galleryButtons.length - 1) % galleryButtons.length,
      Home: 0,
      End: galleryButtons.length - 1,
    };
    if (event.key in navigation) {
      event.preventDefault();
      selectGallery(navigation[event.key], true);
    }
  });
});
const dialog = document.querySelector("#screenshot-dialog");
const enlarge = document.querySelector("#gallery-enlarge");
enlarge.addEventListener("click", () => {
  const selected = galleryButtons.find(
    (button) => button.getAttribute("aria-selected") === "true",
  );
  const original = document.querySelector(
    `#panel-${selected.dataset.gallery} img`,
  );
  const image = document.querySelector("#screenshot-image");
  image.src = original.src;
  image.alt = original.alt;
  document.querySelector("#screenshot-title").textContent =
    selected.textContent;
  dialog.showModal();
  document.body.classList.add("screenshot-open");
});
document
  .querySelector("#screenshot-close")
  .addEventListener("click", () => dialog.close());
dialog.addEventListener("click", (event) => {
  if (event.target !== dialog) return;
  const rect = dialog.getBoundingClientRect();
  if (
    event.clientX < rect.left ||
    event.clientX > rect.right ||
    event.clientY < rect.top ||
    event.clientY > rect.bottom
  )
    dialog.close();
});
dialog.addEventListener("close", () => {
  document.body.classList.remove("screenshot-open");
  enlarge.focus({ preventScroll: true });
});

const canvas = document.querySelector("#voice-canvas");
const ctx = canvas.getContext("2d");
let frame = null;
let visible = false;
let width = 1;
let height = 1;
let lastFrame = 0;
function draw(time = 0) {
  if (!ctx) return;
  if (time && time - lastFrame < 32) {
    frame = requestAnimationFrame(draw);
    return;
  }
  lastFrame = time;
  ctx.clearRect(0, 0, width, height);
  const phase = reducedMotion.matches ? 0 : time * 0.00025;
  const energy = state.phase === "listening" ? 1.3 : 0.65;
  for (let strand = 0; strand < 22; strand++) {
    ctx.beginPath();
    ctx.lineWidth = strand % 5 === 0 ? 1.15 : 0.55;
    ctx.strokeStyle = `rgba(255,116,47,${0.09 + (strand % 5) * 0.026})`;
    for (let x = -5; x <= width + 5; x += 4) {
      const position = x / width;
      const envelope = Math.sin(position * Math.PI) * 90 + 20;
      const y =
        height * 0.46 +
        Math.sin(position * Math.PI * 3.5 + phase + strand * 0.09) *
          envelope *
          energy +
        Math.cos(position * Math.PI * 2 - phase + strand * 0.12) * 32 +
        (strand - 11) * 5;
      if (x === -5) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.stroke();
  }
  frame = null;
  if (visible && !document.hidden && !reducedMotion.matches)
    frame = requestAnimationFrame(draw);
}
function syncAnimation() {
  if (frame !== null) cancelAnimationFrame(frame);
  frame = null;
  draw();
}
new ResizeObserver((entries) => {
  width = entries[0].contentRect.width;
  height = entries[0].contentRect.height;
  const ratio = Math.min(devicePixelRatio || 1, 2);
  canvas.width = width * ratio;
  canvas.height = height * ratio;
  ctx?.setTransform(ratio, 0, 0, ratio, 0, 0);
  syncAnimation();
}).observe(stage);
new IntersectionObserver((entries) => {
  visible = entries[0].isIntersecting;
  syncAnimation();
}).observe(stage);
reducedMotion.addEventListener("change", () => {
  if (
    reducedMotion.matches &&
    ["listening", "transcribing"].includes(state.phase)
  )
    setPhase("complete");
  syncAnimation();
});
document.addEventListener("visibilitychange", () => {
  if (document.hidden && ["listening", "transcribing"].includes(state.phase))
    setPhase("idle");
  syncAnimation();
});
async function loadRelease() {
  try {
    const response = await fetch("/release.json");
    if (!response.ok) throw new Error("Release manifest unavailable");
    const release = await response.json();
    if (!/^\d+\.\d+\.\d+(?:[-+][\w.-]+)?$/.test(release.version))
      throw new Error("Invalid version");
    for (const key of ["downloadUrl", "releaseUrl"]) {
      const url = new URL(release[key]);
      if (
        url.protocol !== "https:" ||
        url.hostname !== "github.com" ||
        !url.pathname.startsWith("/darshmahadevia/voco-releases/releases/")
      )
        throw new Error("Invalid release link");
    }
    if (release.notarized !== false || typeof release.fileSize !== "string")
      throw new Error("Invalid release details");
    document.querySelector("#release-version").textContent =
      `v${release.version}`;
    document.querySelector("#release-download").href = release.downloadUrl;
    document.querySelector("#release-notes").href = release.releaseUrl;
    document.querySelector("#download-meta").textContent =
      `Apple Silicon · macOS 26+ · ${release.fileSize}`;
  } catch {
    document.querySelector("#release-status").textContent =
      "Latest release details are unavailable. The download and installation help above are still available.";
  }
}
loadRelease();
document.querySelector("#year").textContent = new Date().getFullYear();
