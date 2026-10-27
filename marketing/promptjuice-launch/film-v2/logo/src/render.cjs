// Renders logo/option-N.svg to option-N.png (1920x1080) and option-N-360.png (360 px wide).
// The SVG is inlined into an HTML page (as the film will do), with <base> pointing at logo/
// so the mascot's relative href resolves.   usage: node logo/src/render.cjs [1 2 3]
const { chromium } = require(process.env.PLAYWRIGHT || 'playwright');
const fs = require('fs'), path = require('path');
const dir = path.resolve(__dirname, '..');
(async () => {
  const opts = process.argv.slice(2).length ? process.argv.slice(2) : ['1', '2', '3'];
  const b = await chromium.launch();
  for (const n of opts) {
    const svg = fs.readFileSync(path.join(dir, `option-${n}.svg`), 'utf8');
    const html = `<!doctype html><html><head><meta charset="utf-8"><base href="file://${dir}/">
<style>html,body{margin:0;background:#07080b;overflow:hidden}svg{display:block;width:100vw;height:auto}</style></head><body>${svg}</body></html>`;
    const tmp = path.join(dir, `.render-${n}.html`);
    fs.writeFileSync(tmp, html);
    for (const [w, suffix] of [[1920, ''], [360, '-360']]) {
      const p = await b.newPage({ viewport: { width: w, height: Math.round(w * 9 / 16) } });
      await p.goto('file://' + tmp);
      await p.waitForFunction(() => [...document.images].concat([...document.querySelectorAll('image')]).length > 0);
      await p.waitForTimeout(300);
      await p.screenshot({ path: path.join(dir, `option-${n}${suffix}.png`) });
      await p.close();
    }
    fs.unlinkSync(tmp);
  }
  await b.close();
})();
