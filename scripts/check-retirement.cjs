const { chromium } = require('playwright');
const { createServer } = require('node:http');
const { readFileSync } = require('node:fs');
const assert = require('node:assert/strict');
(async () => {
  let retired = false;
  const oldWorker = `self.addEventListener('install', e => e.waitUntil(self.skipWaiting()));
    self.addEventListener('activate', e => e.waitUntil((async () => {
      await caches.open('appocket:test'); await caches.open('sentra:test');
      await self.clients.claim();
    })()));`;
  const server = createServer((req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Content-Type', req.url === '/sw.js' ? 'application/javascript' : 'text/html');
    res.end(req.url === '/sw.js' ? (retired ? readFileSync('scripts/retire-root-sw.js') : oldWorker) : '<title>Migration test</title>');
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  try {
    const page = await browser.newPage();
    await page.goto(`http://127.0.0.1:${server.address().port}/`);
    await page.evaluate(async () => { await navigator.serviceWorker.register('/sw.js'); await navigator.serviceWorker.ready; });
    await page.waitForFunction(() => !!navigator.serviceWorker.controller);
    retired = true;
    await page.evaluate(async () => (await navigator.serviceWorker.getRegistration('/')).update());
    const deadline = Date.now() + 10000;
    while (await page.evaluate(async () => !!(await navigator.serviceWorker.getRegistration('/')) || (await caches.keys()).includes('appocket:test'))) {
      if (Date.now() > deadline) throw new Error('Legacy worker retirement timed out');
      await page.waitForTimeout(100);
    }
    const keys = await page.evaluate(() => caches.keys());
    assert.ok(keys.includes('sentra:test'));
    assert.ok(!keys.includes('appocket:test'));
    console.log('PASS: legacy root registration removed; Appocket cache cleared; Sentra cache retained.');
  } finally {
    await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
