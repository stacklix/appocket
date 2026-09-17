import { JSDOM } from 'jsdom';
// Node 25 also exposes Web Storage; explicitly use browser storage in DOM tests.
const browser = new JSDOM('', { url: 'https://sentra.test/' });
for (const key of ['localStorage', 'sessionStorage'] as const) {
  Object.defineProperty(globalThis, key, { configurable: true, value: browser.window[key] });
  Object.defineProperty(window, key, { configurable: true, value: browser.window[key] });
}
