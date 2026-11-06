// Renders the article visuals at 2x: node docs/src/render.js
const { chromium } = require('playwright');
const path = require('path');
(async () => {
  const browser = await chromium.launch();
  const jobs = [['header', 1400, 700], ['diagram', 1400, 590], ['results', 1400, 650]];
  for (const [name, w, h] of jobs) {
    const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 2 });
    await page.goto('file://' + path.join(__dirname, name + '.html'));
    await page.screenshot({ path: path.join(__dirname, '..', name + '.png') });
    await page.close();
  }
  await browser.close();
})();
