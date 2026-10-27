// PromptJuice launch film. `render(t)` draws any frame from time alone, so the
// preview, scrubbing and the frame-by-frame capture all agree.
import { clamp, lerp, ease, seg, spring, wobble, keys, rng } from "./anim.js";
import { createPanel, gaugeSVG, poseBar } from "./panel.js";
import logoSvg from "../logo/option-1.svg";

export const DURATION = 24.9;
const W = 1920;
const H = 1080;
const GREEN = [95, 209, 31];
const AMBER = [240, 163, 42];
const MASCOT_ASPECT = 776 / 1115;

const film = document.getElementById("film");

function el(tag, cls, parent, html) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (html != null) e.innerHTML = html;
  (parent || film).appendChild(e);
  return e;
}
const rgba = (c, a) => `rgba(${c[0]},${c[1]},${c[2]},${a})`;
const mixC = (a, b, k) => a.map((v, i) => Math.round(lerp(v, b[i], k)));
const hop = (t, t0, d) => { const x = (t - t0) / d; return x <= 0 || x >= 1 ? 0 : 4 * x * (1 - x); };
const bump = (t, t0, d) => { const x = (t - t0) / d; return x <= 0 || x >= 1 ? 0 : Math.sin(Math.PI * x); };
const show = (e, on) => { e.style.display = on ? "" : "none"; };

// ---------------------------------------------------------------- layers
const bg = el("div", "layer");
const glow = el("div", "", bg); glow.id = "glow";
const bgFlash = el("div", "layer", bg);
const fxBack = el("canvas", "fx"); fxBack.width = W; fxBack.height = H;
const world = el("div", "layer");
const fxFront = el("canvas", "fx"); fxFront.width = W; fxFront.height = H;
const vignette = el("div", "layer"); vignette.id = "vignette";
const flash = el("div", ""); flash.id = "flash";
const bctx = fxBack.getContext("2d");
const fctx = fxFront.getContext("2d");

// ---------------------------------------------------------------- mascot rig
const EXPRS = ["happy", "blink", "joy", "alert"];
function createMascot(parent) {
  const shadow = el("div", "shadow", parent);
  const root = el("div", "mascot", parent);
  const imgs = { base: {}, top: {} };
  const add = (layer, holder) => {
    for (const c of ["green", "amber"]) for (const e of EXPRS) {
      const i = el("img", "", holder);
      i.src = `assets/img/mascot-${c}-${e}.png`;
      imgs[layer][`${c}-${e}`] = i;
    }
  };
  add("base", root);
  const top = el("div", "top", root);
  add("top", top);
  const bang = el("div", "bang", parent, "!");
  let shownBase = null, shownTop = null;

  function pose(p) {
    const vis = p.visible !== false && (p.opacity ?? 1) > 0.001;
    show(root, vis); show(shadow, vis && p.shadow !== false);
    if (!vis) { show(bang, false); return; }
    const h = p.h, w = h * MASCOT_ASPECT;
    const lift = p.lift ?? 0;
    root.style.width = `${w}px`;
    root.style.height = `${h}px`;
    root.style.opacity = p.opacity ?? 1;
    root.style.transform = `translate(${p.x - w / 2}px, ${p.ground - lift - h}px) rotate(${p.rot ?? 0}deg) scale(${p.sx ?? 1}, ${p.sy ?? 1})`;
    root.style.filter = p.silhouette ? "brightness(0)" : "";
    const expr = p.expr ?? "happy";
    const b = imgs.base[`${p.from ?? "green"}-${expr}`];
    if (shownBase !== b) { if (shownBase) show(shownBase, false); b.style.display = "block"; shownBase = b; }
    const k = p.k ?? 0;
    const tImg = imgs.top[`${p.to ?? "amber"}-${expr}`];
    if (k > 0.001) {
      if (shownTop !== tImg) { if (shownTop) show(shownTop, false); tImg.style.display = "block"; shownTop = tImg; }
      if (k >= 0.999) top.style.clipPath = "none";
      else {
        // A wavy juice line rising from the feet to the tip.
        const level = lerp(104, -4, k);
        const pts = [];
        for (let i = 0; i <= 20; i++) {
          const x = i * 5;
          const y = level + 2.4 * Math.sin(i * 0.9 + (p.t ?? 0) * 14) + 1.2 * Math.sin(i * 2.1 - (p.t ?? 0) * 9);
          pts.push(`${x}% ${y}%`);
        }
        top.style.clipPath = `polygon(${pts.join(",")}, 100% 100%, 0% 100%)`;
      }
    } else if (shownTop) { show(shownTop, false); shownTop = null; }
    // Contact shadow shrinks as the mascot leaves the ground.
    const sw = w * 0.78 * (1 - clamp(lift / 500) * 0.6) * (p.sx ?? 1);
    shadow.style.width = `${sw}px`;
    shadow.style.height = `${sw * 0.16}px`;
    shadow.style.transform = `translate(${p.x - sw / 2}px, ${p.ground - sw * 0.08}px)`;
    shadow.style.opacity = (p.opacity ?? 1) * (1 - clamp(lift / 600)) * (p.shadowOpacity ?? 1);
    // "!" pop.
    const bk = p.bang ?? 0;
    show(bang, bk > 0.01);
    if (bk > 0.01) {
      bang.style.fontSize = `${h * 0.24}px`;
      bang.style.transform = `translate(${p.x + w * 0.56}px, ${p.ground - lift - h * 0.92}px) rotate(14deg) scale(${bk})`;
    }
  }
  return { pose, root };
}

// ---------------------------------------------------------------- big zip bar
function createBigBar(parent, { x, y, w, h }) {
  const root = el("div", "bigbar", parent);
  Object.assign(root.style, { left: `${x}px`, top: `${y}px`, width: `${w}px`, height: `${h}px` });
  el("div", "track", root);
  const fill = el("div", "fill", root);
  const sweep = el("div", "fill", root);
  const head = el("div", "head", root);
  const streaks = [];
  const R = rng(7);
  for (let i = 0; i < 12; i++) {
    const s = el("div", "streak", root);
    streaks.push({ el: s, y: lerp(-0.9, 1.9, R()) * h, len: 120 + R() * 380, lag: R() * 90, th: 2 + R() * 4, a: 0.35 + R() * 0.6 });
  }
  const glint = el("div", "glint", root);
  const style = (c) => (c === "green"
    ? { background: "linear-gradient(90deg,#3fa512 0%,#5fd11f 62%,#8be24e 100%)", boxShadow: "0 0 34px rgba(95,209,31,.55), 0 0 4px rgba(190,255,140,.6)" }
    : { background: "linear-gradient(90deg,#d9880f 0%,#f0a32a 58%,#ffc15e 100%)", boxShadow: "0 0 34px rgba(240,163,42,.55), 0 0 4px rgba(255,220,150,.6)" });
  let lastColor = null, lastSweep = null;
  return {
    root, x, y, w, h,
    headX: (z) => x + w * z,
    pose({ z, color = "green", v = 0, glint: g = -1, sweepK = 0, sweepColor = "amber", opacity = 1, ty = 0 }) {
      root.style.opacity = opacity;
      root.style.transform = `translateY(${ty}px)`;
      if (lastColor !== color) { Object.assign(fill.style, style(color)); lastColor = color; }
      if (lastSweep !== sweepColor) { Object.assign(sweep.style, style(sweepColor)); lastSweep = sweepColor; }
      const fw = z > 0.002 ? Math.max(h, w * z) : 0;
      fill.style.width = `${fw}px`;
      sweep.style.width = `${Math.min(fw, Math.max(sweepK > 0 ? h : 0, fw * sweepK))}px`;
      sweep.style.opacity = sweepK > 0 ? 1 : 0;
      const hx = sweepK > 0 && sweepK < 1 ? fw * sweepK : fw;
      const vv = clamp(v);
      head.style.opacity = vv;
      head.style.transform = `translateX(${hx - 60}px) scaleX(${1 + vv * 1.6})`;
      const c = (sweepK > 0 && sweepK < 1 ? sweepColor : color) === "green" ? GREEN : AMBER;
      streaks.forEach((s) => {
        const len = s.len * vv * 0.75;
        s.el.style.opacity = vv * s.a;
        s.el.style.width = `${len}px`;
        s.el.style.height = `${s.th}px`;
        s.el.style.background = `linear-gradient(90deg, ${rgba(c, 0)}, ${rgba(mixC(c, [255, 255, 255], 0.55), 1)})`;
        s.el.style.transform = `translate(${hx - len - s.lag}px, ${s.y - h / 2}px)`;
      });
      glint.style.opacity = g >= 0 && g <= 1 ? Math.sin(g * Math.PI) : 0;
      glint.style.transform = `translateX(${lerp(-80, fw + 10, g)}px) skewX(-20deg)`;
      return x + hx;
    },
  };
}

// ---------------------------------------------------------------- titles
function createTitle(parent, words, { size = 112, cls = "title" } = {}) {
  const root = el("div", cls, parent);
  root.style.fontSize = `${size}px`;
  const spans = words.map(([text, c], i) => {
    const s = el("span", `w ${c || ""}`, root, text);
    if (i < words.length - 1) root.appendChild(document.createTextNode(" "));
    return s;
  });
  return { root, spans, width: 0, measure() { this.width = root.offsetWidth; this.lefts = spans.map((s) => s.offsetLeft); this.widths = spans.map((s) => s.offsetWidth); } };
}
/** Per-word entrance; kinds: "blur" (soft focus-in), "slam" (punches in big). */
function wordIn(span, t, t0, kind) {
  const d = kind === "slam" ? 0.22 : 0.3;
  const k = seg(t, t0, t0 + d, ease.out3);
  if (kind === "slam") {
    const s = lerp(1.7, 1, ease.outExpo(clamp((t - t0) / 0.3)));
    span.style.transform = `scale(${s})`;
    span.style.filter = `blur(${(1 - k) * 14}px)`;
  } else {
    span.style.transform = `translateY(${(1 - k) * 18}px)`;
    span.style.filter = `blur(${(1 - k) * 12}px)`;
  }
  span.style.opacity = k;
}
function wordsOut(spans, t, t0) {
  spans.forEach((s, i) => {
    const k = seg(t, t0 + i * 0.03, t0 + i * 0.03 + 0.18, ease.in2);
    if (k <= 0) return;
    s.style.opacity = Math.min(parseFloat(s.style.opacity || 1), 1 - k);
    s.style.filter = `blur(${k * 12}px)`;
  });
}
function placeTitle(T, cx, y) {
  T.root.style.transform = `translate(${cx - T.width / 2}px, ${y}px)`;
}
function animateTitle(T, t, { t0, t1, kind = "blur", stagger = 0.07, cx = W / 2, y = 90 }) {
  const on = t >= t0 - 0.01 && t < t1 + 0.4;
  show(T.root, on);
  if (!on) return;
  // Measure while visible: a page that loaded hidden, or before its webfont
  // arrived, would otherwise centre every title on a width of 0.
  T.measure();
  placeTitle(T, cx, y);
  T.spans.forEach((s, i) => wordIn(s, t, t0 + i * stagger, kind));
  wordsOut(T.spans, t, t1);
}

// ---------------------------------------------------------------- FX drawing
function focusLines(ctx, cx, cy, rInner, color, alpha, seed, count = 90) {
  if (alpha <= 0.01) return;
  const R = rng(seed);
  ctx.save();
  ctx.translate(cx, cy);
  for (let i = 0; i < count; i++) {
    const a = R() * Math.PI * 2;
    const wid = 0.004 + R() * 0.012;
    const r0 = rInner * (0.85 + R() * 0.6);
    const r1 = 1500;
    ctx.fillStyle = rgba(color, alpha * (0.25 + R() * 0.75));
    ctx.beginPath();
    ctx.moveTo(Math.cos(a) * r0, Math.sin(a) * r0);
    ctx.lineTo(Math.cos(a - wid) * r1, Math.sin(a - wid) * r1);
    ctx.lineTo(Math.cos(a + wid) * r1, Math.sin(a + wid) * r1);
    ctx.closePath();
    ctx.fill();
  }
  ctx.restore();
}
function rays(ctx, cx, cy, color, alpha, rot, n = 14) {
  if (alpha <= 0.01) return;
  ctx.save();
  ctx.translate(cx, cy);
  ctx.rotate(rot);
  const g = ctx.createRadialGradient(0, 0, 60, 0, 0, 1100);
  g.addColorStop(0, rgba(color, alpha));
  g.addColorStop(1, rgba(color, 0));
  ctx.fillStyle = g;
  for (let i = 0; i < n; i++) {
    const a = (i / n) * Math.PI * 2;
    ctx.beginPath();
    ctx.moveTo(0, 0);
    ctx.arc(0, 0, 1400, a, a + Math.PI / n * 0.9);
    ctx.closePath();
    ctx.fill();
  }
  ctx.restore();
}
function sparkle(ctx, x, y, size, alpha, rot = 0, color = [255, 255, 255]) {
  if (alpha <= 0.01 || size <= 0.5) return;
  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(rot);
  ctx.fillStyle = rgba(color, alpha);
  ctx.shadowColor = rgba(color, alpha);
  ctx.shadowBlur = size * 0.8;
  ctx.beginPath();
  for (let i = 0; i < 4; i++) {
    const a = (i * Math.PI) / 2;
    ctx.lineTo(Math.cos(a) * size, Math.sin(a) * size);
    ctx.lineTo(Math.cos(a + Math.PI / 4) * size * 0.16, Math.sin(a + Math.PI / 4) * size * 0.16);
  }
  ctx.closePath();
  ctx.fill();
  ctx.restore();
}
/** Short anime "pop" dashes flying out from a point. */
function burst(ctx, x, y, t, t0, color, { n = 10, r0 = 60, r1 = 170, dur = 0.32, width = 7, seed = 3 } = {}) {
  const k = (t - t0) / dur;
  if (k <= 0 || k >= 1) return;
  const R = rng(seed);
  ctx.save();
  ctx.strokeStyle = rgba(color, 1 - k * k);
  ctx.lineCap = "round";
  ctx.lineWidth = width * (1 - k * 0.6);
  for (let i = 0; i < n; i++) {
    const a = (i / n) * Math.PI * 2 + R() * 0.3;
    const e = ease.out3(k);
    const a0 = lerp(r0, r1, e), a1 = lerp(r0, r1, clamp(e * 1.25 + 0.15));
    const s0 = Math.max(a0, a1 - 60 * (1 - k));
    ctx.beginPath();
    ctx.moveTo(x + Math.cos(a) * s0, y + Math.sin(a) * s0);
    ctx.lineTo(x + Math.cos(a) * a1, y + Math.sin(a) * a1);
    ctx.stroke();
  }
  ctx.restore();
}
function sparks(ctx, x, y, t, t0, color, { n = 16, dur = 0.7, speed = 520, seed = 11, dir = 0, spread = Math.PI * 2 } = {}) {
  const k = (t - t0);
  if (k <= 0 || k >= dur) return;
  const R = rng(seed);
  for (let i = 0; i < n; i++) {
    const a = dir + (R() - 0.5) * spread;
    const v = speed * (0.4 + R() * 0.8);
    const px = x + Math.cos(a) * v * k;
    const py = y + Math.sin(a) * v * k + 900 * k * k;
    const life = 1 - k / (dur * (0.6 + R() * 0.4));
    if (life <= 0) continue;
    ctx.fillStyle = rgba(color, life);
    ctx.beginPath();
    ctx.arc(px, py, 3 + R() * 5 * life, 0, Math.PI * 2);
    ctx.fill();
  }
}
function shake(t, hits) {
  let x = 0, y = 0;
  hits.forEach(([t0, amp], i) => {
    const d = t - t0;
    if (d < 0 || d > 0.5) return;
    const a = amp * Math.exp(-d * 11);
    x += a * Math.sin(d * 95 + i * 1.7);
    y += a * Math.cos(d * 83 + i * 2.3);
  });
  return [x, y];
}

// ---------------------------------------------------------------- build
const sceneA = el("div", "layer", world);
const sceneD = el("div", "layer", world);
const sceneE = el("div", "layer", world);
const sceneF = el("div", "layer", world);
const mascotLayer = el("div", "layer", world);

// A: hero row.
const rowA = el("div", "layer", sceneA);
const barA = createBigBar(rowA, { x: 210, y: 822, w: 1500, h: 44 });
const labelA = el("div", "caption", rowA, "5-hour limit");
labelA.style.cssText += "color: rgba(255,255,255,.55); font-weight: 500;";
const valueA = el("div", "caption", rowA, `<span class="pct">83% left</span><span style="color:rgba(255,255,255,.3)"> · </span><span class="reset">resets in <span class="clk">2h 56m</span></span>`);
const valueAReset = valueA.querySelector(".reset");
const valueAClk = valueA.querySelector(".clk");
const titleA = createTitle(sceneA, [["Plenty"], ["of"], ["juice"], ["left."], ["Resets", "amber"], ["soon.", "amber"]], { size: 96 });
const titleB1 = createTitle(sceneA, [["You"], ["paid"], ["for"], ["the"], ["juice.", "amber"]], { size: 104 });
const titleB2 = createTitle(sceneA, [["Don’t"], ["waste"], ["it."]], { size: 104 });
const titleC = createTitle(sceneA, [["In"], ["your"], ["menu"], ["bar."]], { size: 84 });

// Menu bar (pt units, scaled 2.4x).
const MB_S = 2.4;
const menubar = el("div", "", world); menubar.id = "menubar";
menubar.style.width = `${W / MB_S}px`;
const mbHL = el("div", "hl", menubar);
const GLYPH_PT = 590;
const mbGlyph = el("div", "item", menubar);
Object.assign(mbGlyph.style, { left: `${GLYPH_PT - 13}px`, width: "26px" });
mbGlyph.innerHTML = gaugeSVG("mbclip", { w: 18, h: 18, bx: 18 * 0.18, by: 18 * 0.05, bw: 18 * 0.64, bh: 18 * 0.9, remaining: 0.8, tint: "#f0a32a", stroke: 1.27 });
const icons = [
  [624, `<svg width="17" height="13" viewBox="0 0 17 13"><path d="M8.5 12.2 L5.9 9.4 A3.8 3.8 0 0 1 11.1 9.4 Z" fill="#fff"/><path d="M3.6 7.2 A7 7 0 0 1 13.4 7.2" stroke="#fff" stroke-width="1.6" fill="none" stroke-linecap="round"/><path d="M1.2 4.6 A10.4 10.4 0 0 1 15.8 4.6" stroke="#fff" stroke-width="1.6" fill="none" stroke-linecap="round"/></svg>`],
  [660, `<svg width="27" height="13" viewBox="0 0 27 13"><rect x="0.75" y="0.75" width="22" height="11.5" rx="3.4" stroke="rgba(255,255,255,.55)" stroke-width="1.2" fill="none"/><rect x="2.6" y="2.6" width="15" height="7.8" rx="1.8" fill="#fff"/><path d="M24.6 4.6 v3.8" stroke="rgba(255,255,255,.55)" stroke-width="1.6" stroke-linecap="round"/></svg>`],
  [698, `<svg width="17" height="15" viewBox="0 0 17 15"><rect x="0.8" y="0.8" width="15.4" height="5.6" rx="2.8" stroke="#fff" stroke-width="1.3" fill="none"/><circle cx="12.6" cy="3.6" r="1.9" fill="#fff"/><rect x="0.8" y="8.6" width="15.4" height="5.6" rx="2.8" stroke="#fff" stroke-width="1.3" fill="none"/><circle cx="4.4" cy="11.4" r="1.9" fill="#fff"/></svg>`],
];
icons.forEach(([x, svg]) => { const i = el("div", "item", menubar, svg); Object.assign(i.style, { left: `${x - 15}px`, width: "30px" }); });
const clock = el("div", "item clock", menubar, "Tue 2:27 PM");
Object.assign(clock.style, { left: "718px", width: "76px" });

// D: Juicebar.
const panelStage = el("div", "layer", sceneD); panelStage.id = "panelStage";
const panelCam = el("div", "", panelStage); panelCam.id = "panelCam";
const panel = createPanel(panelCam, {
  header: { title: "Use your Claude juice", subtitle: "5-hour · 83% left · resets in 33m", remaining: 0.83, tint: "#f0a32a" },
  cards: [
    { id: "claude", name: "Claude", color: "#ff9f0a", rows: [
      { label: "5-hour limit", pct: 83, reset: "resets in 33m", severity: "useSoon" },
      { label: "Weekly", pct: 88, reset: "resets in 4d", severity: "healthy" },
      { label: "Fable", pct: 98, reset: "resets in 4d", severity: "healthy" },
    ] },
    { id: "codex", name: "Codex", color: "#32d4de", rows: [
      { label: "Weekly", pct: 88, reset: "resets in 5d", severity: "healthy" },
    ] },
  ],
});
// Callouts: one mascot per provider, in that provider's state colour.
const legend = el("div", "layer", sceneD);
const legClaude = el("div", "legend", legend, `<img src="assets/img/mascot-amber-happy.png"><div><span class="who"><i style="background:var(--claude)"></i>Claude</span><span style="color:var(--amber)">Resets soon.</span></div>`);
const legCodex = el("div", "legend", legend, `<img src="assets/img/mascot-green-happy.png"><div><span class="who"><i style="background:var(--codex)"></i>Codex</span><span style="color:var(--green)">Plenty left.</span></div>`);

// E: benefit.
const streamSvg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
streamSvg.id = "stream"; streamSvg.setAttribute("width", W); streamSvg.setAttribute("height", H);
sceneE.appendChild(streamSvg);
const rowE = el("div", "layer", sceneE);
const barE = createBigBar(rowE, { x: 260, y: 500, w: 1400, h: 46 });
const labelE = el("div", "caption", rowE, `Claude <span style="color:rgba(255,255,255,.3)">·</span> 5-hour limit`);
labelE.style.cssText += "color: rgba(255,255,255,.62); font-weight: 500; font-size: 46px; text-shadow: 0 0 14px #07080b, 0 0 6px #07080b;";
const valueE = el("div", "caption", rowE, `<span class="pct">83% left</span><span style="color:rgba(255,255,255,.3)"> · </span><span class="reset" style="color:var(--amber)">resets in 33m</span>`);
valueE.style.textShadow = "0 0 14px #07080b, 0 0 6px #07080b";
const valueEPct = valueE.querySelector(".pct");
const valueEReset = valueE.querySelector(".reset");
const TASKS = [
  { what: "Plan the big refactor", chip: "Strongest model" },
  { what: "Fix the memory leak", chip: "Higher effort" },
  { what: "Write the test suite", chip: "New task" },
];
const taskEls = TASKS.map((tk, i) => {
  const c = el("div", "task", sceneE, `<div class="who"><i></i>Claude</div><div class="what">${tk.what}</div><div class="chip">${tk.chip}</div><div class="prog"><b></b></div>`);
  c.style.left = `${260 + i * 480}px`;
  c.style.top = "680px";
  const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
  path.setAttribute("fill", "none");
  path.setAttribute("stroke-linecap", "round");
  streamSvg.appendChild(path);
  return { el: c, prog: c.querySelector(".prog b"), chip: c.querySelector(".chip"), path, x: 260 + i * 480 };
});
const titleE1 = createTitle(sceneE, [["Use"], ["your"], ["strongest", "amber"], ["model.", "amber"]], { size: 100 });
const titleE2 = createTitle(sceneE, [["Use"], ["higher", "amber"], ["effort.", "amber"]], { size: 100 });
const titleE2b = createTitle(sceneE, [["Start"], ["another"], ["task.", "amber"]], { size: 100 });
const titleE3 = createTitle(sceneE, [["Nothing", "green"], ["wasted."]], { size: 100 });

// F: end card — logo option 1 ("Juice Level"), inlined so its parts animate.
// Ids are prefixed so they can't collide with the film's own (e.g. #glow).
const logoWrap = el("div", "layer logo", sceneF);
logoWrap.innerHTML = logoSvg
  .replace(/id="([^"]+)"/g, 'id="lg-$1"')
  .replace(/url\(#([^)]+)\)/g, "url(#lg-$1)")
  .replace(/href="#([^"]+)"/g, 'href="#lg-$1"')
  .replace(/\.\.\/assets\//g, "assets/");
const LG = (id) => logoWrap.querySelector(`#lg-${id}`);
// The film draws its own ground, glow and mascot.
["bg", "glow", "mascot"].forEach((id) => { const e = LG(id); if (e) e.style.display = "none"; });
const PROMPT_LETTERS = ["l-P", "l-r", "l-o", "l-m", "l-p", "l-t"];
// The logo's mascot slot (same PNG crop as the rig: feet at 1109/1115).
const LOGO_MASCOT = (() => {
  const img = LG("mascot-img");
  const y = +img.getAttribute("y"), h = +img.getAttribute("height"), x = +img.getAttribute("x"), w = +img.getAttribute("width");
  return { x: x + w / 2, ground: y + h * (1109 / 1115), h };
})();

const mascot = createMascot(mascotLayer);

const cursor = el("div", "", world, `<svg width="46" height="68" viewBox="0 0 23 34"><path d="M1.5 1.5 L1.5 26.5 L7.6 20.8 L11.6 30.6 L15.6 29 L11.7 19.4 L20 19.4 Z" fill="#000" stroke="#fff" stroke-width="1.8" stroke-linejoin="round"/></svg>`);
cursor.id = "cursor";

// ---------------------------------------------------------------- timing
// Every beat in one place; SOUND-CUES.json is generated from these numbers.
export const BEATS = {
  popIn: 0.0, barZip: 0.45, barLand: 1.5, clockRoll: 1.85, turn: 2.4, resetsSoon: 2.72,
  youPaid: 4.05, dontWaste: 4.95,
  jumpPrep: 6.25, jump: 6.4, glyphLand: 7.05, menuCaption: 7.12, click: 7.85, panelOpen: 7.95,
  zipClaude: 8.2, zipCodex: 8.34, swing1: 8.95, glint: 9.95, toCard: 10.65, chevronClick: 11.4, expand: 11.44,
  swing2: 12.2, legClaude: 12.6, legCodex: 12.85, toBar: 14.4, handoff: 15.3,
  strongest: 15.55, card1: 15.85, effort: 16.95, card2: 17.18, another: 18.3, card3: 18.53, reset: 19.5, nothingWasted: 19.8,
  finale: 21.0, mascotLand: 21.7, juiceRise: 22.2, dotLand: 22.7, tagline: 23.2, endHop: 23.95,
};
const B = BEATS;

// Panel camera poses: focus point (fx, fy in panel pt) lands on screen (cx, cy).
// [cx, cy, fx, fy, scale, rotateX, rotateY]
const P_OPEN = [960, 76, 192, 0, 2.6, 0, 0];
const P_PUNCH = [960, 560, 192, 104, 4.3, 6, -12];
const P_PUNCH2 = [960, 560, 192, 104, 4.4, 5, -8];
const P_CARD = [960, 150, 192, 54, 3.4, 0, 0];
const P_ANGLE = [640, 560, 192, 152, 2.45, 5, 20];
const P_ANGLE2 = [620, 560, 192, 152, 2.5, 4, 17];
// The Claude 5-hour bar lands exactly on the benefit scene's big bar.
const P_BAR = [960, 523, 192, 116, 1400 / 332, 0, 0];

function zipZ(t, t0) { return spring(t, t0, { zeta: 0.82, freq: 1.0 }); }
function speed(fn, t) { return Math.abs(fn(t) - fn(t - 1 / 60)) * 60; }
const CALM = 0.5; // how much of the speed-streak effect to keep

// ---------------------------------------------------------------- render
export function render(t) {
  bctx.clearRect(0, 0, W, H);
  fctx.clearRect(0, 0, W, H);

  // Colour state: green → amber at the turn → green at the reset, as slow washes.
  const amberK = seg(t, B.turn, B.turn + 0.9, ease.inOut2) * (1 - seg(t, B.reset, B.reset + 0.9, ease.inOut2));
  const glowC = mixC(GREEN, AMBER, amberK);
  const glowI = keys(t, [[0, 0.3], [1.0, 1, ease.inOut2], [B.toBar, 1], [B.handoff + 0.3, 0.8], [B.reset, 0.85], [B.reset + 0.8, 1.05], [24.4, 1]]);
  const glowXY = keys(t, [[0, [960, 470]], [6.3, [960, 470]], [7.4, [960, 300]], [B.toBar, [960, 300]], [B.handoff + 0.4, [960, 520]], [B.finale, [960, 520]], [B.mascotLand, [960, 500]]]);
  glow.style.background = `radial-gradient(closest-side, ${rgba(glowC, 0.34 * glowI)}, ${rgba(glowC, 0.1 * glowI)} 42%, ${rgba(glowC, 0)} 72%)`;
  glow.style.transform = `translate(${glowXY[0] - 960}px, ${glowXY[1] - 540}px)`;
  // A slow dolly on the opening shots.
  const dolly = 1 + 0.035 * seg(t, 0, 6.2, ease.inOut2);
  world.style.transform = t < 6.3 ? `scale(${dolly})` : "";
  world.style.transformOrigin = "960px 560px";

  const m = { visible: true, x: 960, ground: 672, h: 390, from: "green", to: "amber", k: 0, expr: "happy", t };

  // ------------------------------------------------ A: green → amber (0 – 3.9)
  const inA = t < 3.95;
  show(sceneA, t < 7.9);
  show(rowA, inA);
  if (t < 7.9) {
    const intro = seg(t, 0, 0.9, ease.out3);
    m.opacity = 0.35 + 0.65 * seg(t, 0, 0.5);
    m.lift = 26 * (1 - intro);
    const settle = wobble(t, 0.62, { amp: 0.035, freq: 2.2, decay: 4 });
    m.sx = 1 + settle * 0.6; m.sy = 1 - settle;
    m.expr = (t > 0.95 && t < 1.04) || (t > 1.62 && t < 1.7) ? "blink" : "happy";
    // The turn: eyes widen, a small lift, amber rises through the body.
    if (t >= B.turn) {
      m.expr = t < B.turn + 1.0 ? "alert" : (t > 3.45 && t < 3.53) ? "blink" : "happy";
      m.lift = 18 * bump(t, B.turn + 0.05, 0.7);
      m.rot = wobble(t, B.turn + 0.1, { amp: -3, freq: 1.4, decay: 3 });
      m.k = seg(t, B.turn + 0.05, B.turn + 0.95, ease.inOut3);
    }

    if (inA) {
      const z = (tt) => 0.83 * zipZ(tt, B.barZip);
      const sweepF = (tt) => seg(tt, B.turn + 0.1, B.turn + 0.95, ease.inOut3);
      const sw = sweepF(t);
      const v = CALM * (t < B.turn ? speed(z, t) / 1.2 : speed(sweepF, t) / 2.2);
      const out = seg(t, 3.7, 4.0, ease.in2);
      const headX = barA.pose({ z: z(t), color: "green", v, glint: (t - (B.barLand - 0.1)) / 0.7, sweepK: sw, sweepColor: "amber", opacity: 1 - out, ty: out * 30 });
      sparkle(fctx, headX, 844, 34 * bump(t, B.barLand - 0.05, 0.8), 0.9, t * 0.8);
      const rowIn = seg(t, 1.0, 1.5, ease.out3);
      const ry = 750 + (1 - rowIn) * 16 + out * 30;
      labelA.style.transform = `translate(210px, ${ry}px)`;
      labelA.style.opacity = rowIn * (1 - out);
      labelA.style.filter = `blur(${(1 - rowIn) * 8}px)`;
      // The reset clock rolls 2h 56m → 33m: the cause of the turn.
      const roll = seg(t, B.clockRoll, B.clockRoll + 0.55, ease.inOut3);
      const mins = Math.round(lerp(176, 33, roll));
      valueAClk.textContent = mins >= 60 ? `${Math.floor(mins / 60)}h ${mins % 60}m` : `${mins}m`;
      const amberText = seg(t, B.clockRoll + 0.4, B.clockRoll + 0.75);
      valueAReset.style.color = `rgba(${Math.round(lerp(255, 240, amberText))},${Math.round(lerp(255, 163, amberText))},${Math.round(lerp(255, 42, amberText))},${lerp(0.55, 1, amberText)})`;
      valueA.style.transform = `translate(${1710 - valueA.offsetWidth}px, ${ry}px)`;
      valueA.style.opacity = rowIn * (1 - out);
      valueA.style.filter = `blur(${(1 - rowIn) * 8}px)`;
    }

    // "Plenty of juice left." then the line glides over for "Resets soon."
    show(titleA.root, inA);
    if (inA) {
      titleA.measure();
      const w4 = titleA.lefts[3] + titleA.widths[3];
      const shift = seg(t, B.resetsSoon - 0.1, B.resetsSoon + 0.6, ease.inOut3);
      const x0 = lerp(W / 2 - w4 / 2, W / 2 - titleA.width / 2, shift);
      titleA.root.style.transform = `translate(${x0}px, 92px)`;
      [0.5, 0.58, 0.66, 0.74].forEach((t0, i) => wordIn(titleA.spans[i], t, t0, "blur"));
      wordIn(titleA.spans[4], t, B.resetsSoon + 0.15, "blur");
      wordIn(titleA.spans[5], t, B.resetsSoon + 0.25, "blur");
      wordsOut(titleA.spans, t, 3.62);
    }

    // B: "You paid for the juice. Don't waste it."
    if (t >= 3.85) {
      const mv = seg(t, 3.85, 4.6, ease.inOut3);
      m.x = 960; m.ground = lerp(672, 830, mv); m.h = lerp(390, 450, mv);
      m.k = 1; m.from = "amber"; m.to = "amber"; m.rot = 0;
      m.lift = 14 * bump(t, 4.5, 0.55);
      const sq = wobble(t, 4.95, { amp: 0.03, freq: 2.4, decay: 5 });
      m.sx = 1 + sq * 0.6; m.sy = 1 - sq;
      m.expr = (t > 5.7 && t < 5.78) ? "blink" : (t > 4.4 && t < 5.4) ? "joy" : "happy";
    }
    rays(bctx, 960, 620, AMBER, 0.05 * seg(t, 3.9, 4.8) * (1 - seg(t, 6.0, 6.5)), t * 0.06);
    animateTitle(titleB1, t, { t0: B.youPaid, t1: 6.0, kind: "blur", y: 96 });
    animateTitle(titleB2, t, { t0: B.dontWaste, t1: 6.08, kind: "blur", y: 222 });

    // C: a hop up into the menu bar, where the mascot becomes the glyph.
    if (t >= B.jumpPrep) {
      const prep = bump(t, B.jumpPrep, 0.22);
      const f = seg(t, B.jump, B.glyphLand, ease.inOut3);
      const p0 = [960, 830], p1 = [1380, 420], p2 = [GLYPH_PT * MB_S, 52];
      m.x = (1 - f) ** 2 * p0[0] + 2 * (1 - f) * f * p1[0] + f * f * p2[0];
      m.ground = (1 - f) ** 2 * p0[1] + 2 * (1 - f) * f * p1[1] + f * f * p2[1];
      m.lift = 0;
      m.h = lerp(450, 40, ease.inOut2(f));
      m.sx = 1 + prep * 0.08 - bump(t, B.jump, 0.6) * 0.06;
      m.sy = 1 - prep * 0.1 + bump(t, B.jump, 0.6) * 0.1;
      m.rot = 10 * bump(t, B.jump, 0.65);
      m.expr = "joy";
      m.shadowOpacity = 1 - f;
      m.visible = t < B.glyphLand;
    }
    animateTitle(titleC, t, { t0: B.menuCaption, t1: 7.72, kind: "blur", stagger: 0.06, y: 330 });
  } else {
    show(titleA.root, false);
  }

  // Menu bar slides in for the hand-off and leaves when the camera swings.
  const mbIn = seg(t, 6.45, 6.9, ease.out3) * (1 - seg(t, B.swing1, B.swing1 + 0.4, ease.in2));
  show(menubar, mbIn > 0.001 && t < B.swing1 + 0.5);
  menubar.style.transform = `translate(0px, ${(1 - mbIn) * -70}px) scale(${MB_S})`;
  const glyphPop = t < B.glyphLand ? 0 : spring(t, B.glyphLand, { zeta: 0.62, freq: 2.0 });
  mbGlyph.style.transform = `scale(${glyphPop * (1 - 0.12 * bump(t, B.click, 0.14))})`;
  mbHL.style.cssText = `left:${GLYPH_PT - 15}px;width:30px;opacity:${seg(t, B.click, B.click + 0.08)}`;
  sparkle(fctx, GLYPH_PT * MB_S + 18, 22, 22 * bump(t, B.glyphLand + 0.05, 0.5), 0.9, t);

  // ------------------------------------------------ D: the Juicebar (7.9 – 15.4)
  const inD = t >= B.panelOpen - 0.02 && t < B.handoff + 0.35;
  show(sceneD, inD);
  if (inD) {
    const pose = keys(t, [
      [B.panelOpen, P_OPEN], [B.swing1, P_OPEN],
      [B.swing1 + 0.85, P_PUNCH, ease.inOut3], [B.toCard, P_PUNCH2, ease.inOut2],
      [B.toCard + 0.65, P_CARD, ease.inOut3], [B.swing2, P_CARD],
      [B.swing2 + 0.8, P_ANGLE, ease.inOut3], [B.toBar, P_ANGLE2, ease.inOut2],
      [B.toBar + 0.8, P_BAR, ease.inOut3],
    ]);
    const [cx, cy, fx, fy, s, rx, ry] = pose;
    panelStage.style.perspectiveOrigin = `${cx}px ${cy}px`;
    panelCam.style.transform = `translate3d(${cx}px, ${cy}px, 0) rotateX(${rx}deg) rotateY(${ry}deg) scale(${s}) translate(${-fx}px, ${-fy}px)`;
    sceneD.style.opacity = 1 - seg(t, B.handoff - 0.1, B.handoff + 0.25, ease.inOut2);

    const unfold = spring(t, B.panelOpen, { zeta: 0.78, freq: 1.25 });
    panel.root.style.transform = `rotateX(${(1 - unfold) * -92}deg)`;
    panel.root.style.opacity = clamp(seg(t, B.panelOpen, B.panelOpen + 0.15) * 1.2);
    const zc = (tt) => zipZ(tt, B.zipClaude);
    const zx = (tt) => zipZ(tt, B.zipCodex);
    const z1 = (tt) => zipZ(tt, B.expand + 0.2);
    const z2 = (tt) => zipZ(tt, B.expand + 0.32);
    panel.layout({
      expand: { claude: spring(t, B.expand, { zeta: 0.86, freq: 1.4 }) },
      appear: {
        header: seg(t, B.panelOpen + 0.03, B.panelOpen + 0.4, ease.out3),
        card0: seg(t, B.panelOpen + 0.08, B.panelOpen + 0.46, ease.out3),
        card1: seg(t, B.panelOpen + 0.14, B.panelOpen + 0.52, ease.out3),
      },
      chevronPress: { claude: bump(t, B.chevronClick - 0.03, 0.16) },
      zip: {
        "claude-0": [zc(t), CALM * speed(zc, t) / 2, (t - B.glint) / 0.7],
        "claude-1": [z1(t), CALM * speed(z1, t) / 2, -1],
        "claude-2": [z2(t), CALM * speed(z2, t) / 2, -1],
        "codex-0": [zx(t), CALM * speed(zx, t) / 2, -1],
      },
    });
    const vp = document.getElementById("viewport").getBoundingClientRect();
    const sc = vp.width / W;
    const headRect = panel.cards[0].rows[0].bar.fill.getBoundingClientRect();
    const hx = (headRect.right - vp.left) / sc, hy = (headRect.top + headRect.height / 2 - vp.top) / sc;
    sparkle(fctx, hx - 6, hy, 46 * bump(t, B.glint + 0.45, 0.7), 0.95, t * 0.8, [255, 236, 190]);

    // Cursor: leaves after the glyph click, returns for the Claude chevron.
    const chevEl = panel.cards[0].chevron.getBoundingClientRect();
    const chev = [(chevEl.left + chevEl.width / 2 - vp.left) / sc, (chevEl.top + chevEl.height / 2 - vp.top) / sc];
    const cIn = seg(t, B.chevronClick - 0.5, B.chevronClick - 0.06, ease.out3);
    const cOut = seg(t, B.chevronClick + 0.3, B.chevronClick + 0.7, ease.in2);
    const onChev = t > B.chevronClick - 0.5 && t < B.chevronClick + 0.7;
    if (onChev) cursorPose(true, [lerp(lerp(1500, chev[0], cIn), 1720, cOut), lerp(lerp(1100, chev[1], cIn), 1160, cOut)], bump(t, B.chevronClick - 0.04, 0.16));
    else if (t >= B.click + 0.05 && t < B.click + 0.6) {
      const away = seg(t, B.click + 0.12, B.click + 0.55, ease.in2);
      cursorPose(true, [lerp(GLYPH_PT * MB_S + 6, 1780, away), lerp(34, 460, away)], 0);
    } else cursorPose(false);

    // Callouts beside each card: Claude amber, Codex green.
    const lOut = seg(t, B.toBar - 0.1, B.toBar + 0.25, ease.in2);
    [[legClaude, B.legClaude, 393], [legCodex, B.legCodex, 565]].forEach(([e, t0, y]) => {
      const k = seg(t, t0, t0 + 0.55, ease.out3);
      show(e, k > 0);
      e.style.transform = `translate(1180px, ${y + (1 - k) * 22}px)`;
      e.style.opacity = k * (1 - lOut);
      e.style.filter = `blur(${(1 - k) * 8 + lOut * 8}px)`;
    });
  }
  if (t >= B.click - 0.65 && t < B.click + 0.05) {
    const cin = seg(t, B.click - 0.62, B.click - 0.08, ease.out3);
    cursorPose(true, [lerp(1720, GLYPH_PT * MB_S + 6, cin), lerp(1150, 34, cin)], bump(t, B.click - 0.04, 0.16));
  } else if (!inD) cursorPose(false);

  // ------------------------------------------------ E: benefit (15.1 – 20.6)
  const inE = t >= B.handoff - 0.08 && t < B.finale + 0.7;
  show(sceneE, inE);
  if (inE) {
    const fall = seg(t, B.finale, B.finale + 0.6, ease.inOut3);
    const d1 = seg(t, B.card1 + 0.15, B.card1 + 0.95, ease.inOut2);
    const d2 = seg(t, B.card2 + 0.15, B.card2 + 0.85, ease.inOut2);
    const d3 = seg(t, B.card3 + 0.15, B.card3 + 0.9, ease.inOut2);
    const level = (tt) => 0.83
      - 0.28 * seg(tt, B.card1 + 0.15, B.card1 + 0.95, ease.inOut2)
      - 0.27 * seg(tt, B.card2 + 0.15, B.card2 + 0.85, ease.inOut2)
      - 0.24 * seg(tt, B.card3 + 0.15, B.card3 + 0.9, ease.inOut2);
    // Fast refill: the head is at full speed when the music drops (0.2 s in).
    const refill = (tt) => (tt < B.reset ? 0 : spring(tt, B.reset, { zeta: 0.86, freq: 1.15 }));
    const reset = t >= B.reset;
    const z = reset ? Math.min(1, lerp(0.04, 1, refill(t))) : level(t);
    const v = CALM * (reset ? speed(refill, t) / 1.1 : speed(level, t));
    // The panel's bar becomes this bar: it arrives at the panel bar's thickness.
    const thick = lerp(6 * P_BAR[4] / 46, 1, seg(t, B.handoff, B.handoff + 0.5, ease.inOut3));
    barE.root.style.transformOrigin = "50% 50%";
    const headX = barE.pose({ z, color: reset ? "green" : "amber", v, glint: (t - (B.reset + 0.9)) / 0.7, opacity: 1 - fall, ty: fall * 120 });
    barE.root.style.transform += ` scaleY(${thick})`;
    sparkle(fctx, headX - 8, 523, 40 * bump(t, B.reset + 0.8, 0.8), 0.95, t * 0.8, [210, 255, 170]);

    valueEPct.textContent = `${Math.round(z * 100)}% left`;
    const mins = Math.max(1, Math.round(33 - 10 * d1 - 11 * d2 - 11 * d3));
    valueEReset.textContent = reset ? "resets in 4h" : `resets in ${mins}m`;
    valueEReset.style.color = reset ? "rgba(255,255,255,.55)" : "#f0a32a";
    const rowIn = seg(t, B.handoff + 0.2, B.handoff + 0.65, ease.out3);
    labelE.style.transform = `translate(260px, ${578 + (1 - rowIn) * 14 + fall * 120}px)`;
    labelE.style.opacity = rowIn * (1 - fall);
    labelE.style.filter = `blur(${(1 - rowIn) * 8}px)`;
    valueE.style.transform = `translate(${1660 - valueE.offsetWidth}px, ${574 + (1 - rowIn) * 14 + fall * 120}px)`;
    valueE.style.opacity = rowIn * (1 - fall);
    valueE.style.filter = `blur(${(1 - rowIn) * 8}px)`;

    // Task cards rise in; a stream of juice runs from the bar into each.
    const arrivals = [B.card1, B.card2, B.card3];
    const drains = [[B.card1 + 0.08, B.card1 + 1.0], [B.card2 + 0.08, B.card2 + 0.9], [B.card3 + 0.08, B.card3 + 0.95]];
    taskEls.forEach((tk, i) => {
      const t0 = arrivals[i];
      fitTaskTitle(tk);
      const k = seg(t, t0, t0 + 0.6, ease.out4);
      const fl = seg(t, B.finale + i * 0.06, B.finale + 0.55 + i * 0.06, ease.inOut3);
      show(tk.el, t >= t0);
      tk.el.style.opacity = k * (1 - fl);
      tk.el.style.transform = `translateY(${(1 - k) * 36 + fl * 90}px)`;
      tk.el.style.filter = k < 1 ? `blur(${(1 - k) * 10}px)` : "";
      const done = seg(t, B.reset + 0.2 + i * 0.12, B.reset + 0.7 + i * 0.12, ease.out3);
      const work = seg(t, drains[i][0] + 0.3, drains[i][1] + 1.6, ease.inOut2);
      tk.prog.style.width = `${lerp(work * 70, 100, done)}%`;
      tk.prog.style.background = done > 0 ? "linear-gradient(90deg,#3fa512,#8be24e)" : "";
      if (done > 0.5) { tk.chip.textContent = "Done"; tk.chip.style.color = "#5fd11f"; tk.chip.style.background = "rgba(95,209,31,.14)"; tk.chip.style.boxShadow = "inset 0 0 0 2px rgba(95,209,31,.35)"; }
      else { tk.chip.textContent = TASKS[i].chip; tk.chip.style.cssText = ""; }
      const [s0, s1] = drains[i];
      const sk = (t - s0) / (s1 - s0);
      if (sk > 0 && sk < 1.25) {
        const hxNow = barE.headX(level(t));
        tk.path.setAttribute("d", `M ${hxNow - 10} 546 C ${hxNow - 10} 640, ${tk.x + 220} 600, ${tk.x + 220} 682`);
        tk.path.setAttribute("stroke", "#f0a32a");
        tk.path.setAttribute("stroke-width", `${8 * (1 - clamp((sk - 1) * 4))}`);
        tk.path.setAttribute("stroke-dasharray", "22 16");
        tk.path.setAttribute("stroke-dashoffset", `${-t * 160}`);
        tk.path.setAttribute("opacity", `${0.85 * clamp(sk * 5) * (1 - clamp((sk - 1) * 4))}`);
        tk.path.style.filter = "drop-shadow(0 0 8px rgba(240,163,42,.7))";
      } else tk.path.setAttribute("opacity", "0");
    });

    // The mascot rides the juice level.
    if (t < B.finale) {
      const hx = barE.headX(z);
      const appear = seg(t, B.handoff + 0.25, B.handoff + 0.8, ease.out3);
      m.x = clamp(hx - 40, 380, 1600); m.ground = 500; m.h = 180;
      m.from = "amber"; m.to = "amber"; m.k = 1; m.rot = 0;
      m.opacity = appear;
      const moving = clamp(v * 2);
      m.lift = 26 * (1 - appear) + 7 * Math.abs(Math.sin(t * 9)) * moving;
      m.expr = (t > 16.6 && t < 16.68) || (t > 18.9 && t < 18.98) ? "blink" : "happy";
      if (reset) {
        m.to = "green";
        m.k = seg(t, B.reset + 0.1, B.reset + 0.9, ease.inOut3);
        m.expr = "joy";
        m.lift = 40 * bump(t, B.reset + 0.1, 0.7) + 6 * moving;
      }
    }
    animateTitle(titleE1, t, { t0: B.strongest, t1: B.effort - 0.2, kind: "blur", y: 120 });
    animateTitle(titleE2, t, { t0: B.effort, t1: B.another - 0.2, kind: "blur", stagger: 0.09, y: 120 });
    animateTitle(titleE2b, t, { t0: B.another, t1: B.reset - 0.15, kind: "blur", stagger: 0.09, y: 120 });
    animateTitle(titleE3, t, { t0: B.nothingWasted, t1: B.finale - 0.15, kind: "blur", stagger: 0.1, y: 120 });
  }

  // ------------------------------------------------ F: end card (21.0 – 24.9)
  const inF = t >= B.finale;
  show(sceneF, inF);
  if (inF) {
    // The film's mascot glides in and lands in the logo's mascot slot.
    const target = [LOGO_MASCOT.x, LOGO_MASCOT.ground, LOGO_MASCOT.h];
    const start = [clamp(barE.headX(1) - 40, 380, 1600), 500, 180];
    const f = seg(t, B.finale + 0.1, B.mascotLand, ease.inOut2);
    m.from = "green"; m.to = "green"; m.k = 0;
    m.x = lerp(start[0], target[0], f);
    m.ground = lerp(start[1], target[1], f);
    m.h = lerp(start[2], target[2], ease.out2(f));
    m.lift = 150 * Math.sin(Math.PI * f) + 36 * hop(t, B.endHop, 0.5);
    m.rot = -8 * bump(t, B.finale + 0.1, B.mascotLand - B.finale - 0.1);
    const sq = wobble(t, B.mascotLand, { amp: 0.06, freq: 2.4, decay: 5 }) + wobble(t, B.endHop + 0.5, { amp: 0.04, freq: 2.6, decay: 6 });
    m.sx = 1 + sq * 0.6; m.sy = 1 - sq;
    m.expr = t < B.mascotLand + 0.7 ? "joy" : (t > 24.2 && t < 24.28) ? "blink" : (t > B.endHop - 0.1 && t < B.endHop + 0.7) ? "joy" : "happy";
    m.shadowOpacity = 0.8;

    // "Prompt" rises in letter by letter.
    PROMPT_LETTERS.forEach((id, i) => {
      const k = seg(t, B.mascotLand + 0.02 + i * 0.05, B.mascotLand + 0.5 + i * 0.05, ease.out3);
      const e = LG(id);
      e.style.transform = `translateY(${(1 - k) * 46}px)`;
      e.style.opacity = k;
      e.style.filter = k < 1 ? `blur(${(1 - k) * 10}px)` : "";
    });
    // The "Juice" glasses appear, then fill with a slosh.
    const vessel = seg(t, B.mascotLand + 0.25, B.mascotLand + 0.6, ease.out3);
    LG("word-juice").style.opacity = vessel;
    const fill = t < B.juiceRise ? 0 : spring(t, B.juiceRise, { zeta: 0.55, freq: 1.3 });
    LG("juice-level").style.transform = `translateY(${92 * (1 - fill)}px)`;
    LG("juice-wave").style.transform = `translateX(${((t * 0.9) % 1) * 146}px)`;
    LG("juice-bubbles").style.transform = `translateY(${-10 * seg(t, B.juiceRise, B.juiceRise + 2.5)}px)`;
    LG("juice-bubbles").style.opacity = seg(t, B.juiceRise + 0.3, B.juiceRise + 0.7);
    // The droplet falls in as the dot of the i and squashes on landing.
    const fallK = seg(t, B.dotLand - 0.42, B.dotLand, ease.in2);
    const squash = wobble(t, B.dotLand, { amp: 0.28, freq: 3.2, decay: 7 });
    const dot = LG("droplet-dot");
    dot.style.opacity = t < B.dotLand - 0.42 ? 0 : 1;
    dot.style.transform = `translateY(${-300 * (1 - fallK)}px) scale(${1 + squash * 0.7}, ${1 - squash})`;
    // Tagline, then the open-source pill (enlarged so it reads on a phone).
    const tg = seg(t, B.tagline, B.tagline + 0.5, ease.out3);
    LG("tagline").style.opacity = tg;
    LG("tagline").style.transform = `translateY(${(1 - tg) * 16}px)`;
    LG("tagline").style.filter = tg < 1 ? `blur(${(1 - tg) * 8}px)` : "";
    const pill = seg(t, B.tagline + 0.35, B.tagline + 0.85, ease.out3);
    LG("oss-pill").style.opacity = pill;
    LG("oss-pill").style.transform = `translateY(${12 + (1 - pill) * 14}px) scale(1.5)`;
  }

  if (t >= B.glyphLand && t < B.handoff) m.visible = false;
  mascot.pose(m);
}

/** Task titles stay on one line: shrink one that would overflow its card. */
function fitTaskTitle(tk) {
  const what = tk.el.querySelector(".what");
  if (!what.clientWidth) return;
  let size = 42;
  what.style.fontSize = `${size}px`;
  while (what.scrollWidth > what.clientWidth && size > 30) what.style.fontSize = `${--size}px`;
}

function cursorPose(on, p = [0, 0], press = 0) {
  show(cursor, on);
  if (on) cursor.style.transform = `translate(${p[0] - 6}px, ${p[1] - 4}px) scale(${1 - press * 0.16})`;
}

// ---------------------------------------------------------------- boot
const params = new URLSearchParams(location.search);
const capture = params.has("capture");
const ready = (async () => {
  await document.fonts.ready;
  await Promise.all([...document.images].map((i) => (i.complete ? null : new Promise((r) => { i.onload = i.onerror = r; }))));
  [titleA, titleB1, titleB2, titleC, titleE1, titleE2, titleE2b, titleE3].forEach((T) => T.measure());

  render(+(params.get("t") || 0));
})();
window.__film = { render, ready, duration: DURATION, beats: BEATS };

if (!capture) {
  document.body.classList.add("preview");
  const vpEl = document.getElementById("viewport");
  const fit = () => {
    const s = Math.min((window.innerWidth - 32) / W, (window.innerHeight - 96) / H);
    vpEl.style.transform = `scale(${s})`;
    vpEl.style.width = `${W}px`;
    vpEl.parentElement.style.width = `${W * s}px`;
    document.body.style.setProperty("--s", s);
    vpEl.style.marginBottom = `${H * s - H}px`;
    vpEl.style.marginRight = `${W * s - W}px`;
  };
  fit();
  window.addEventListener("resize", fit);
  const audio = document.getElementById("soundtrack");
  const scrub = document.getElementById("scrub");
  const time = document.getElementById("time");
  const btn = document.getElementById("play");
  const mute = document.getElementById("mute");
  scrub.max = DURATION;
  let playing = false, t0 = 0, start = 0, cur = 0;
  const draw = (t) => { cur = t; render(t); scrub.value = t; time.textContent = `${t.toFixed(2)} s`; };
  const tick = (now) => {
    if (!playing) return;
    const t = audio.paused || !isFinite(audio.currentTime) || audio.error ? t0 + (now - start) / 1000 : audio.currentTime;
    if (t >= DURATION) { playing = false; btn.textContent = "Replay"; audio.pause(); draw(DURATION - 0.001); return; }
    draw(t);
    requestAnimationFrame(tick);
  };
  btn.onclick = () => {
    if (playing) { playing = false; audio.pause(); btn.textContent = "Play"; return; }
    if (cur >= DURATION - 0.05) cur = 0;
    playing = true; btn.textContent = "Pause";
    t0 = cur; start = performance.now();
    try { audio.currentTime = cur; audio.muted = mute.checked; audio.play().catch(() => {}); } catch (e) { /* silent preview */ }
    requestAnimationFrame(tick);
  };
  mute.onchange = () => { audio.muted = mute.checked; };
  scrub.oninput = () => { if (playing) { playing = false; audio.pause(); btn.textContent = "Play"; } draw(+scrub.value); };
  window.addEventListener("keydown", (e) => { if (e.code === "Space") { e.preventDefault(); btn.onclick(); } });
}
