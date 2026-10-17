import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
const b = await chromium.launch();
const p = await b.newPage({ viewport: { width: 1520, height: 1080 }, deviceScaleFactor: 1.5 });
await p.goto('file://' + process.argv[2]); await p.waitForTimeout(800);
await p.screenshot({ path: process.argv[3], fullPage: true });
await b.close();
