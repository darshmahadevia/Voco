import "./transitions.css";
import "./style.css";

/** @typedef {{version: string, downloadUrl: string, releaseUrl: string, fileSize?: string, notarized: boolean}} ReleaseManifest */
/** @typedef {'idle' | 'listening' | 'transcribing' | 'complete'} DemoPhase */

const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
const gallery = [
  {
    id: "home",
    description:
      "Your shortcut, recent words, and a clear sign you're ready to speak.",
  },
  {
    id: "settings",
    description:
      "Choose your output preferences, speech model, permissions, and dictation shortcut.",
  },
  {
    id: "stats",
    description:
      "A little perspective on the words you put into the world. Sample data is labeled in the preview.",
  },
];

const heroCopy = document.querySelector(".hero-copy");
if (!reducedMotion.matches) {
  heroCopy.classList.remove("is-shown");
  void heroCopy.offsetHeight;
  requestAnimationFrame(() => heroCopy.classList.add("is-shown"));
}

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
window.matchMedia("(min-width: 641px)").addEventListener("change", (event) => {
  if (event.matches) setMenu(false);
});

const demo = document.querySelector(".demo");
const playButton = document.querySelector("#demo-play");
const demoStatus = document.querySelector("#demo-status");
const demoOutput = document.querySelector("#demo-output");
const demoText =
  "Let's give this idea a little room to grow. I'll send over a first draft this afternoon.";
const demoPhases = {
  idle: {
    label: "Ready when you are",
    action: "Play demo",
    delay: 0,
    next: "listening",
  },
  listening: {
    label: "Listening to the example…",
    action: "Playing…",
    delay: 2600,
    next: "transcribing",
  },
  transcribing: {
    label: "Turning voice into words…",
    action: "Finishing…",
    delay: 1100,
    next: "complete",
  },
  complete: {
    label: "Your words, ready to go",
    action: "Play again",
    delay: 0,
    next: "listening",
  },
};
/** @type {{phase: DemoPhase, timer: ReturnType<typeof setTimeout> | null}} */
const demoState = { phase: "idle", timer: null };
function setDemoPhase(phase) {
  clearTimeout(demoState.timer);
  demoState.phase = phase;
  const current = demoPhases[phase];
  demo.dataset.phase = phase;
  demoStatus.textContent = current.label;
  playButton.querySelector("span").textContent = current.action;
  playButton.disabled = phase === "listening" || phase === "transcribing";
  demoOutput.textContent =
    phase === "complete" ? demoText : "Your next good idea goes here.";
  if (current.delay)
    demoState.timer = setTimeout(
      () => setDemoPhase(current.next),
      current.delay,
    );
}
playButton.addEventListener("click", () => {
  setDemoPhase(reducedMotion.matches ? "complete" : "listening");
});
reducedMotion.addEventListener("change", (event) => {
  if (event.matches && ["listening", "transcribing"].includes(demoState.phase))
    setDemoPhase("complete");
});
document.addEventListener("visibilitychange", () => {
  if (
    document.hidden &&
    ["listening", "transcribing"].includes(demoState.phase)
  )
    setDemoPhase("idle");
});

const galleryButtons = [...document.querySelectorAll("[data-gallery]")];
function selectGallery(index, focus = false) {
  galleryButtons.forEach((button, buttonIndex) => {
    const selected = index === buttonIndex;
    button.setAttribute("aria-selected", String(selected));
    button.tabIndex = selected ? 0 : -1;
    document.querySelector(`#panel-${gallery[buttonIndex].id}`).hidden =
      !selected;
  });
  document.querySelector("#gallery-description").textContent =
    gallery[index].description;
  if (focus) galleryButtons[index].focus();
}
galleryButtons.forEach((button, index) => {
  button.addEventListener("click", () => selectGallery(index));
  button.addEventListener("keydown", (event) => {
    let next;
    if (event.key === "ArrowRight") next = (index + 1) % gallery.length;
    if (event.key === "ArrowLeft")
      next = (index + gallery.length - 1) % gallery.length;
    if (event.key === "Home") next = 0;
    if (event.key === "End") next = gallery.length - 1;
    if (next !== undefined) {
      event.preventDefault();
      selectGallery(next, true);
    }
  });
});

for (const [index, accordion] of [
  ...document.querySelectorAll(".t-acc"),
].entries()) {
  const head = accordion.querySelector(".t-acc-head");
  const panel = accordion.querySelector(".t-acc-panel");
  const state = { open: index === 0 };
  function setOpen(open) {
    state.open = open;
    if (!open && panel.contains(document.activeElement)) head.focus();
    accordion.setAttribute("data-open", String(open));
    head.setAttribute("aria-expanded", String(open));
    panel.inert = !open;
    panel.setAttribute("aria-hidden", String(!open));
  }
  setOpen(state.open);
  head.addEventListener("click", () => setOpen(!state.open));
}

function parseRelease(value) {
  if (
    !value ||
    typeof value !== "object" ||
    !/^\d+\.\d+\.\d+(?:[-+][\w.-]+)?$/.test(value.version)
  )
    throw new Error("Invalid release version");
  for (const property of ["downloadUrl", "releaseUrl"]) {
    const url = new URL(value[property]);
    if (
      url.protocol !== "https:" ||
      url.hostname !== "github.com" ||
      !url.pathname.startsWith("/darshmahadevia/voco-releases/releases/")
    )
      throw new Error("Invalid release link");
  }
  if (
    value.notarized !== false ||
    (value.fileSize !== undefined && typeof value.fileSize !== "string")
  )
    throw new Error("Invalid release details");
  return /** @type {ReleaseManifest} */ (value);
}
async function loadRelease() {
  try {
    const response = await fetch("/release.json");
    if (!response.ok) throw new Error("Release details unavailable");
    const release = parseRelease(await response.json());
    document.querySelector("#release-version").textContent =
      `v${release.version}`;
    document.querySelector("#release-download").href = release.downloadUrl;
    document.querySelector("#release-notes").href = release.releaseUrl;
    document.querySelector("#download-label").textContent = "Download for Mac";
    document.querySelector("#download-meta").textContent =
      `Apple Silicon · macOS 26+${release.fileSize ? ` · ${release.fileSize}` : ""}`;
  } catch {
    document.querySelector("#release-status").textContent =
      "Latest release details are unavailable. The download and installation notes above are still available.";
  }
}
loadRelease();
document.querySelector("#year").textContent = String(new Date().getFullYear());
