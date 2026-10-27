// Snapshot frames: node tools/snap.mjs out/dir 0.5,2.1,... [--phone]
import { chromium } from "playwright";
import path from "node:path";
import fs from "node:fs";
const [, , outDir, list] = process.argv;
fs.mkdirSync(outDir, { recursive: true });
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
page.on("pageerror", (e) => console.log("pageerror:", e.message));
page.on("console", (m) => { if (m.type() === "error") console.log("console:", m.text()); });
await page.goto("file://" + path.resolve("index.html") + "?capture");
await page.evaluate(() => window.__film.ready);
for (const t of list.split(",").map(Number)) {
  await page.evaluate((tt) => window.__film.render(tt), t);
  await page.screenshot({ path: path.join(outDir, `t${t.toFixed(2).padStart(5, "0")}.png`) });
}
await browser.close();
