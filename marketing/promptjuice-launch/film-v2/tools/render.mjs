// Frame-by-frame render: node tools/render.mjs [--scale 1] [--workers 4] [--out out/film.mp4]
// Each worker seeks the page to exact frame times and screenshots it; ffmpeg
// then encodes the frames with dist/soundtrack.wav.
import { chromium } from "playwright";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const arg = (k, d) => { const i = process.argv.indexOf(`--${k}`); return i > 0 ? process.argv[i + 1] : d; };
const scale = +arg("scale", 1);
const workers = +arg("workers", 4);
const out = arg("out", "out/promptjuice-launch.mp4");
const fps = 30;
const frameDir = path.resolve(arg("frames", `out/frames-${scale}`));
fs.mkdirSync(frameDir, { recursive: true });
fs.mkdirSync(path.dirname(path.resolve(out)), { recursive: true });

const browser = await chromium.launch();
const probe = await browser.newPage();
await probe.goto("file://" + path.resolve("index.html") + "?capture");
const duration = await probe.evaluate(async () => { await window.__film.ready; return window.__film.duration; });
await probe.close();
const total = Math.round(duration * fps);
console.log(`rendering ${total} frames at ${Math.round(1920 * scale)}x${Math.round(1080 * scale)} with ${workers} workers`);

const t0 = Date.now();
let done = 0;
await Promise.all(Array.from({ length: workers }, async (_, w) => {
  const ctx = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: scale });
  const page = await ctx.newPage();
  page.on("pageerror", (e) => console.log("pageerror:", e.message));
  await page.goto("file://" + path.resolve("index.html") + "?capture");
  await page.evaluate(() => window.__film.ready);
  for (let f = w; f < total; f += workers) {
    await page.evaluate((t) => window.__film.render(t), f / fps);
    await page.screenshot({ path: path.join(frameDir, `f${String(f).padStart(5, "0")}.png`) });
    if (++done % 60 === 0) console.log(`${done}/${total} frames, ${((Date.now() - t0) / 1000).toFixed(0)}s`);
  }
  await ctx.close();
}));
await browser.close();

const audio = fs.existsSync("dist/soundtrack.wav") ? ["-i", "dist/soundtrack.wav"] : [];
execFileSync("ffmpeg", [
  "-v", "error", "-y", "-framerate", String(fps), "-i", path.join(frameDir, "f%05d.png"), ...audio,
  "-c:v", "libx264", "-preset", scale < 1 ? "veryfast" : "slow", "-crf", scale < 1 ? "22" : "16",
  "-pix_fmt", "yuv420p", "-profile:v", "high", "-movflags", "+faststart",
  ...(audio.length ? ["-c:a", "aac", "-b:a", "192k", "-shortest"] : []),
  out,
], { stdio: "inherit" });
console.log(`wrote ${out} in ${((Date.now() - t0) / 1000).toFixed(0)}s`);
