import { chromium } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

const baseURL = process.env.VOCO_WEBSITE_URL || "http://127.0.0.1:4174";
const output = resolve("../.impeccable/review");
await mkdir(output, { recursive: true });
const browser = await chromium.launch({ channel: "chrome", headless: true });
const report = {
  baseURL,
  capturedAt: new Date().toISOString(),
  layouts: [],
  interactions: [],
  accessibility: [],
};
try {
  for (const [name, width, height] of [
    ["desktop", 1440, 1000],
    ["user-1280", 1280, 800],
    ["tablet", 768, 1024],
    ["mobile", 390, 844],
    ["narrow", 320, 740],
  ]) {
    const context = await browser.newContext({ viewport: { width, height } });
    const page = await context.newPage();
    const errors = [];
    page.on("pageerror", (error) => errors.push(error.message));
    const response = await page.goto(baseURL);
    report.artifactSha256 ??= createHash("sha256")
      .update(await response.text())
      .digest("hex");
    await page.evaluate(() => document.fonts.ready);
    assert.equal(await page.locator("h1").count(), 1);
    assert.equal(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
      true,
      `${name} horizontal overflow`,
    );
    assert.equal(
      await page
        .locator("html")
        .evaluate((el) => getComputedStyle(el).colorScheme),
      "dark",
    );
    if (width < 641) {
      await page.getByRole("button", { name: "Open navigation" }).click();
      assert.equal(await page.locator("#mobile-nav").isVisible(), true);
      await page
        .getByRole("button", { name: "Close navigation" })
        .press("Escape");
      assert.equal(await page.locator("#mobile-nav").isVisible(), false);
      assert.equal(
        await page
          .locator(".menu-toggle")
          .evaluate((el) => el === document.activeElement),
        true,
      );
    }
    await page.getByRole("tab", { name: "Your progress" }).click();
    assert.equal(await page.locator("#panel-stats").isVisible(), true);
    await page.getByRole("tab", { name: "Your progress" }).press("ArrowRight");
    assert.equal(
      await page
        .getByRole("tab", { name: "Workspace" })
        .getAttribute("aria-selected"),
      "true",
    );
    await page.getByRole("button", { name: "View full size" }).click();
    assert.equal(await page.locator("#screenshot-dialog").isVisible(), true);
    await page.keyboard.press("Escape");
    assert.equal(await page.locator("#screenshot-dialog").isVisible(), false);
    assert.equal(
      await page
        .locator("#gallery-enlarge")
        .evaluate((el) => el === document.activeElement),
      true,
    );
    const faq = page.getByText("Does my voice leave my Mac?", { exact: true });
    await faq.click();
    assert.equal(await faq.evaluate((el) => el.parentElement.open), true);
    await faq.click();
    if (name === "desktop") {
      await page.locator("#demo-play").click();
      assert.equal(
        await page.locator(".voice-stage").getAttribute("data-phase"),
        "listening",
      );
      assert.equal(
        await page.locator("#demo-output").textContent(),
        "Your thought is on its way.",
      );
      assert.equal(
        await page
          .locator("#demo-cancel")
          .evaluate((el) => el === document.activeElement),
        true,
      );
      await page.waitForFunction(
        () =>
          document.querySelector(".voice-stage").dataset.phase ===
          "transcribing",
      );
      assert.equal(
        await page.locator("#demo-output").textContent(),
        "Your thought is on its way.",
      );
      await page.waitForFunction(
        () =>
          document.querySelector(".voice-stage").dataset.phase === "complete",
      );
      assert.equal(
        await page.locator("#demo-output").textContent(),
        "I have an idea. Let's take the complicated part out and make the first five minutes feel effortless.",
      );
      await page.locator("#demo-play").click();
      await page.locator("#demo-cancel").press("Escape");
      assert.equal(
        await page.locator(".voice-stage").getAttribute("data-phase"),
        "idle",
      );
      await page.locator("#demo-play").click();
      await page.getByRole("button", { name: "An idea", exact: true }).click();
      await page.waitForTimeout(3400);
      assert.equal(
        await page.locator(".voice-stage").getAttribute("data-phase"),
        "idle",
      );
      assert.equal(
        await page.locator("#demo-output").textContent(),
        "What if the best version is the one with fewer steps? Start with the moment someone needs help, and work backwards.",
      );
      await page
        .getByRole("button", { name: "A message", exact: true })
        .click();
      const video = page.locator("#app-video");
      await video.scrollIntoViewIfNeeded();
      await page.locator("#walkthrough-play").click();
      await page.waitForFunction(
        () => document.querySelector("#app-video").controls,
      );
      assert.equal(await video.evaluate((el) => el.controls), true);
      assert.equal(await page.locator("#walkthrough-play").isVisible(), false);
      await page.waitForFunction(
        () => document.querySelector("#app-video").currentTime > 0.2,
      );
      assert.ok(await video.evaluate((el) => el.duration > 18));
      await video.evaluate((el) => el.pause());
      report.interactions.push(
        "Complete transcript only after processing, cancel, Escape, sample-switch timer cleanup, playable 18-second recording",
      );
    }
    await page.evaluate(() => scrollTo({ top: 0, behavior: "instant" }));
    await page.screenshot({
      path: resolve(output, `${name}.png`),
      fullPage: true,
      animations: "disabled",
    });
    await page.screenshot({
      path: resolve(output, `${name}-hero.png`),
      animations: "disabled",
    });
    if (name === "desktop" || name === "mobile") {
      const results = await new AxeBuilder({ page })
        .withTags(["wcag2a", "wcag2aa", "wcag21aa"])
        .analyze();
      report.accessibility.push({ name, violations: results.violations });
      assert.deepEqual(
        results.violations.map((v) => ({
          id: v.id,
          nodes: v.nodes.map((n) => n.target),
        })),
        [],
        `${name} accessibility`,
      );
    }
    assert.deepEqual(errors, [], `${name} browser exceptions`);
    report.layouts.push({ name, width, height, overflow: false, errors });
    await context.close();
  }
  const reduced = await browser.newContext({ reducedMotion: "reduce" });
  const page = await reduced.newPage();
  await page.goto(baseURL);
  await page.locator("#demo-play").click();
  assert.equal(
    await page.locator(".voice-stage").getAttribute("data-phase"),
    "complete",
  );
  report.interactions.push("Reduced-motion playback completes immediately");
  await reduced.close();
  const mediaFailure = await browser.newContext();
  const mediaPage = await mediaFailure.newPage();
  await mediaPage.route("**/videos/*.webm", (route) => route.abort("failed"));
  await mediaPage.goto(baseURL);
  await mediaPage.locator("#walkthrough-play").click();
  await mediaPage.locator("#walkthrough-error").waitFor();
  assert.match(
    await mediaPage.locator("#walkthrough-error").textContent(),
    /Try again/,
  );
  assert.equal(await mediaPage.locator("#walkthrough-play").isVisible(), true);
  assert.equal(await mediaPage.locator("#walkthrough-play").isEnabled(), true);
  await mediaPage.unroute("**/videos/*.webm");
  await mediaPage.locator("#walkthrough-play").click();
  await mediaPage.waitForFunction(
    () => document.querySelector("#app-video").currentTime > 0.2,
  );
  assert.equal(
    await mediaPage.locator("#walkthrough-error").isVisible(),
    false,
  );
  assert.equal(await mediaPage.locator("#walkthrough-play").isVisible(), false);
  await mediaFailure.close();
  report.interactions.push(
    "Unavailable recording exposes retry and screenshots; retry recovers after network returns",
  );
  const fallback = await browser.newContext();
  const failure = await fallback.newPage();
  await failure.route("**/release.json", (route) =>
    route.fulfill({ status: 503, body: "Unavailable" }),
  );
  await failure.goto(baseURL);
  await failure
    .locator("#release-status")
    .filter({ hasText: "unavailable" })
    .waitFor();
  assert.equal(
    await failure.locator("#release-download").getAttribute("href"),
    "https://github.com/darshmahadevia/voco-releases/releases/download/v0.2.1/Voco-0.2.1-arm64.dmg",
  );
  await failure.unroute("**/release.json");
  await failure.route("**/release.json", (route) =>
    route.fulfill({
      json: {
        version: "0.2.1",
        downloadUrl: "https://example.com/untrusted",
        releaseUrl: "https://example.com/release",
        notarized: false,
        fileSize: "147 MB",
      },
    }),
  );
  await failure.reload();
  await failure
    .locator("#release-status")
    .filter({ hasText: "unavailable" })
    .waitFor();
  assert.ok(
    (
      await failure.locator("#release-download").getAttribute("href")
    ).startsWith("https://github.com/"),
  );
  await fallback.close();
  const noJS = await browser.newContext({ javaScriptEnabled: false });
  const staticPage = await noJS.newPage();
  await staticPage.goto(baseURL);
  assert.equal(
    await staticPage.getByRole("heading", { level: 1 }).isVisible(),
    true,
  );
  assert.ok(
    (
      await staticPage.locator("#release-download").getAttribute("href")
    ).endsWith(".dmg"),
  );
  await noJS.close();
  report.interactions.push(
    "Failed and untrusted release metadata keep pinned download; readable page and download without JavaScript",
  );
  await writeFile(
    resolve(output, "browser-report.json"),
    JSON.stringify(report, null, 2),
  );
  console.log(JSON.stringify(report, null, 2));
} finally {
  await browser.close();
}
