import { chromium } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const baseURL = process.env.VOCO_WEBSITE_URL || 'http://127.0.0.1:4174';
const output = resolve('../.impeccable/review');
await mkdir(output, { recursive: true });
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const report = { baseURL, layouts: [], interactions: [], accessibility: [] };
try {
  for (const [name, width, height] of [['desktop', 1440, 1000], ['mobile', 390, 844], ['narrow', 320, 740]]) {
    const context = await browser.newContext({ viewport: { width, height }, reducedMotion: 'no-preference' });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(baseURL);
    await page.evaluate(() => document.fonts.ready);
    await page.waitForFunction(() => document.querySelector('#release-version').textContent === 'v0.2.1');
    assert.equal(await page.locator('h1').count(), 1);
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, `${name} overflows horizontally`);
    if (width < 641) {
      const toggle = page.getByRole('button', { name: 'Open navigation' });
      await toggle.click();
      await page.getByRole('button', { name: 'Close navigation' }).press('Escape');
      assert.equal(await page.locator('#mobile-nav').isVisible(), false);
      assert.equal(await toggle.evaluate(element => document.activeElement === element), true);
    }
    await page.getByRole('tab', { name: 'Your progress' }).click();
    assert.equal(await page.locator('#panel-stats').isVisible(), true);
    await page.getByRole('tab', { name: 'Your progress' }).press('ArrowRight');
    assert.equal(await page.getByRole('tab', { name: 'Your workspace' }).getAttribute('aria-selected'), 'true');
    const faq = page.getByRole('button', { name: 'Does my voice leave my Mac?' });
    await faq.click();
    assert.equal(await faq.getAttribute('aria-expanded'), 'true');
    await faq.click();
    assert.equal(await page.locator('#faq-2').evaluate(element => element.inert), true);
    if (name === 'desktop') {
      await page.getByRole('button', { name: 'Play demo' }).click();
      assert.equal(await page.locator('.demo').getAttribute('data-phase'), 'listening');
      assert.equal((await page.locator('#demo-output').textContent()).includes('afternoon'), false);
      await page.waitForFunction(() => document.querySelector('.demo').dataset.phase === 'complete');
      assert.match(await page.locator('#demo-output').textContent(), /first draft this afternoon/);
      await page.getByRole('button', { name: 'Play again' }).click();
      await page.emulateMedia({ reducedMotion: 'reduce' });
      await page.waitForFunction(() => document.querySelector('.demo').dataset.phase === 'complete');
      assert.equal(await page.locator('.demo').getAttribute('data-phase'), 'complete');
      report.interactions.push('Demo completes, replays, and respects reduced motion');
    }
    await page.getByRole('button', { name: 'View full size' }).click();
    assert.equal(await page.getByRole('dialog').isVisible(), true);
    assert.match(await page.locator('#screenshot-image').getAttribute('src'), /app-home.webp/);
    await page.getByRole('button', { name: 'Close', exact: true }).press('Escape');
    assert.equal(await page.getByRole('dialog').isVisible(), false);
    assert.equal(await page.locator('#gallery-enlarge').evaluate(element => document.activeElement === element), true);
    await page.emulateMedia({ reducedMotion: 'reduce' });
    for (const [name, text] of [['A quick note', 'first five minutes'], ['A message', 'thoughtful feedback']]) {
      await page.getByRole('button', { name, exact: true }).click();
      await page.getByRole('button', { name: 'Play demo', exact: true }).click();
      assert.equal(await page.locator('.demo').getAttribute('data-phase'), 'complete');
      assert.match(await page.locator('#demo-output').textContent(), new RegExp(text));
    }
    await page.getByRole('button', { name: 'An email', exact: true }).click();
    await page.emulateMedia({ reducedMotion: 'no-preference' });
    await page.getByRole('button', { name: 'Play dictation demo', exact: true }).click();
    assert.equal(await page.locator('.demo').getAttribute('data-phase'), 'listening');
    await page.getByRole('button', { name: 'Cancel', exact: true }).click();
    assert.equal(await page.locator('.demo').getAttribute('data-phase'), 'idle');
    assert.equal(await page.locator('#demo-play').isEnabled(), true);
    await page.getByRole('button', { name: 'Play demo', exact: true }).click();
    await page.getByRole('button', { name: 'A quick note', exact: true }).click();
    assert.equal(await page.locator('.demo').getAttribute('data-phase'), 'idle');
    await page.waitForTimeout(3800);
    assert.equal(await page.locator('.demo').getAttribute('data-phase'), 'idle', 'Canceled demo timer survived sample switch');
    await page.getByRole('button', { name: 'An email', exact: true }).click();
    for (const image of await page.locator('img:visible').all()) {
      await image.scrollIntoViewIfNeeded();
      await image.evaluate(element => element.decode());
    }
    await page.evaluate(() => window.scrollTo({ top: 0, behavior: 'instant' }));
    await page.waitForTimeout(600);
    report.layouts.push(await page.evaluate(name => ({ name, width: innerWidth, height: innerHeight, scrollWidth: document.documentElement.scrollWidth, headingSize: getComputedStyle(document.querySelector('h1')).fontSize }), name));
    await page.screenshot({ path: `${output}/${name}.png`, fullPage: true, animations: 'disabled' });
    if (name === 'desktop') await page.screenshot({ path: `${output}/hero.png`, animations: 'disabled' });
    const axe = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa']).analyze();
    report.accessibility.push({ name, violations: axe.violations.map(item => ({ id: item.id, impact: item.impact, nodes: item.nodes.map(node => ({ target: node.target, summary: node.failureSummary })) })) });
    assert.deepEqual(errors, [], 'Browser JavaScript errors');
    await context.close();
  }
  report.interactions.push('All demo samples, hero key, cancellation, sample switching, full-size screenshot dialog, Escape, and focus restoration verified at every viewport');
  const noScript = await browser.newContext({ javaScriptEnabled: false, viewport: { width: 390, height: 844 } });
  const plain = await noScript.newPage();
  await plain.goto(baseURL);
  assert.equal(await plain.locator('h1').isVisible(), true);
  assert.match(await plain.locator('#release-download').getAttribute('href'), /voco-releases\/releases\/download/);
  assert.equal(await plain.locator('#faq-2').isVisible(), true);
  report.interactions.push('Core copy, download link, and FAQ remain available without JavaScript');
  await noScript.close();
  const failureContext = await browser.newContext();
  const failurePage = await failureContext.newPage();
  await failurePage.route('**/release.json', route => route.fulfill({ status: 503, body: '' }));
  await failurePage.goto(baseURL);
  await failurePage.locator('#release-status').getByText('Latest release details are unavailable.', { exact: false }).waitFor();
  assert.match(await failurePage.locator('#release-download').getAttribute('href'), /voco-releases\/releases\/download/);
  report.interactions.push('Release-manifest failure preserves a real fallback download');
  await failureContext.close();
  await writeFile(`${output}/verification.json`, JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report, null, 2));
  assert.equal(report.accessibility.flatMap(item => item.violations).length, 0, 'Accessibility violations need repair');
} finally {
  await browser.close();
}
