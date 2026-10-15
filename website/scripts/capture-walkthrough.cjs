const { chromium } = require("@playwright/test");
const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const { mkdir, mkdtemp, rm } = require("node:fs/promises");
const { tmpdir } = require("node:os");
const { resolve, join } = require("node:path");

const output = resolve(__dirname, "../public/videos");
const baseURL = process.env.VOCO_RENDERER_URL || "http://127.0.0.1:5173";
const viewport = { width: 1100, height: 880 };
const scenes = [
  { navigation: null, heading: "Hello, Alex.", duration: 4000 },
  { navigation: "Settings", heading: "Settings", duration: 3000 },
  { tab: "Models", heading: "Settings", duration: 3000 },
  { navigation: "Stats", heading: "Stats", duration: 5000 },
  { navigation: "Home", heading: "Hello, Alex.", duration: 3000 },
];

async function capture() {
  await mkdir(output, { recursive: true });
  const temporary = await mkdtemp(join(tmpdir(), "voco-walkthrough-"));
  const browser = await chromium.launch({ channel: "chrome", headless: true });
  try {
    const context = await browser.newContext({
      viewport,
      deviceScaleFactor: 1,
      colorScheme: "dark",
      reducedMotion: "no-preference",
      recordVideo: { dir: temporary, size: viewport },
    });
    const page = await context.newPage();
    const errors = [];
    page.on("pageerror", (error) => errors.push(error.message));
    await page.goto(`${baseURL}/?preview=ready&page=home`);
    await page.evaluate(() => document.fonts.ready);
    await page
      .getByRole("heading", { name: "Hello, Alex.", exact: true })
      .waitFor();
    await page.waitForTimeout(800);
    assert.match(
      await page.locator(".preview-notice").textContent(),
      /Native actions are inactive/,
    );
    await page.screenshot({
      path: join(output, "voco-walkthrough-poster.png"),
    });
    const started = Date.now();
    for (const scene of scenes) {
      if (scene.navigation) {
        await page
          .getByRole("button", { name: scene.navigation, exact: true })
          .click();
      }
      if (scene.tab)
        await page.getByRole("tab", { name: scene.tab, exact: true }).click();
      await page
        .getByRole("heading", { name: scene.heading, exact: true })
        .waitFor();
      if (scene.navigation === "Stats") {
        await page
          .getByText("Sample progress · preview", { exact: true })
          .waitFor();
        assert.ok(await page.locator('.heatmap-day[data-level="4"]').count());
      }
      await page.waitForTimeout(scene.duration);
    }
    const sceneDuration = (Date.now() - started) / 1000;
    const video = page.video();
    await context.close();
    assert.deepEqual(errors, [], "Renderer errors during capture");
    const source = await video.path();
    const metadata = JSON.parse(
      execFileSync(
        "ffprobe",
        ["-v", "error", "-show_format", "-show_streams", "-of", "json", source],
        { encoding: "utf8" },
      ),
    );
    const warmup = Math.max(
      0,
      Number(metadata.format.duration) - sceneDuration,
    );
    const destination = join(output, "voco-walkthrough.webm");
    execFileSync("ffmpeg", [
      "-y",
      "-v",
      "error",
      "-ss",
      String(warmup),
      "-i",
      source,
      "-t",
      String(sceneDuration),
      "-an",
      "-c:v",
      "libvpx-vp9",
      "-crf",
      "30",
      "-b:v",
      "0",
      "-pix_fmt",
      "yuv420p",
      destination,
    ]);
    const result = JSON.parse(
      execFileSync(
        "ffprobe",
        [
          "-v",
          "error",
          "-show_format",
          "-show_streams",
          "-of",
          "json",
          destination,
        ],
        { encoding: "utf8" },
      ),
    );
    const stream = result.streams.find((item) => item.codec_type === "video");
    assert.equal(stream.width, viewport.width);
    assert.equal(stream.height, viewport.height);
    assert.ok(
      Number(result.format.duration) >= 18 &&
        Number(result.format.duration) < 21,
    );
    console.log(
      JSON.stringify(
        {
          file: destination,
          duration: Number(result.format.duration),
          width: stream.width,
          height: stream.height,
          bytes: Number(result.format.size),
          provenance:
            "Actual Voco React renderer in Chrome. Ready-state preview with sample transcripts and progress. Native actions are inactive. No speech recognition is recorded.",
          scenes,
        },
        null,
        2,
      ),
    );
  } finally {
    await browser.close();
    await rm(temporary, { recursive: true, force: true });
  }
}

capture().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
