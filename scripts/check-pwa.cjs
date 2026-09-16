// Run with Node and Playwright available on NODE_PATH.
const assert = require('node:assert/strict');
const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  try {
    const context = await browser.newContext({ viewport: { width: 390, height: 844 } });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => { errors.push(error.message); console.error(error.stack); });
    page.on('console', message => { if (message.type() === 'error') console.error(message.text()); });
    await page.goto('http://127.0.0.1:8080/');
    assert.equal(await page.locator('link[rel=manifest]').count(), 0);
    assert.equal(await page.evaluate(() => navigator.serviceWorker.controller), null);
    await page.getByRole('link', { name: /Sentra/ }).click();
    await page.evaluate(() => navigator.serviceWorker.ready);
    await page.waitForFunction(() => navigator.serviceWorker.controller?.scriptURL.endsWith('/sentra/sw.js'));
    await page.waitForSelector('flutter-view');
    const manifest = await page.evaluate(async () => (await fetch('manifest.json')).json());
    assert.equal(manifest.scope, './');
    assert.equal(manifest.display, 'standalone');
    assert.equal(await page.evaluate(() => navigator.serviceWorker.controller.scriptURL),
      'http://127.0.0.1:8080/sentra/sw.js');
    const count = await page.evaluate(async () => {
      const keys = await caches.keys();
      const cache = await caches.open(keys.find(key => key.startsWith('sentra:')));
      return (await cache.keys()).length;
    });
    assert.ok(count > 10);
    await context.setOffline(true);
    await page.reload();
    await page.waitForSelector('flutter-view');
    await page.waitForTimeout(1500);
    await page.screenshot({ path: 'dist/sentra-offline.png' });
    assert.deepEqual(errors, []);
    await page.locator('flt-semantics-placeholder').evaluate(element => element.click());
    assert.equal(await page.getByRole('button', { name: /全部应用|Appocket/ }).count(), 0);
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.waitForTimeout(500);
    assert.equal(await page.getByRole('button', { name: /全部应用|Appocket/ }).count(), 0);
    assert.deepEqual(errors, []);
    console.log(`PWA checks passed: manifest, ${count} cached files, offline reload, scope isolation, launcher.`);
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
