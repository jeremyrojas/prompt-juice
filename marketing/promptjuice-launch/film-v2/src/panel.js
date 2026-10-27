// The Juicebar, rebuilt in DOM from PromptJuicePanelView.swift metrics
// (1 CSS px = 1 pt). Layout is computed here, not by the browser, so every
// frame of an expansion is exact and repeatable.
import { clamp, lerp } from "./anim.js";

export const PAL = {
  claude: "#ff9f0a",
  codex: "#32d4de",
  green: "#5fd11f",
  orange: "#f0a32a",
};

export const M = {
  width: 384, contentPadding: 14, headerHeight: 32, cardSpacing: 8,
  cardHeaderHeight: 16, cardPadding: 12, cardContentSpacing: 10,
  windowLineHeight: 16, windowBarSpacing: 5, mainBarHeight: 6, secondaryBarHeight: 3,
  radius: 22,
};

// DropletGeometry.swift, unit square y-down.
const TIP = [0.5, 0.1208];
const SEGS = [
  [[0.5, 0.1208], [0.2083, 0.4708], [0.2083, 0.6667]],
  [[0.2083, 0.8292], [0.3375, 0.9333], [0.5, 0.9333]],
  [[0.6625, 0.9333], [0.7917, 0.8292], [0.7917, 0.6667]],
  [[0.7917, 0.4708], [0.5, 0.1208], [0.5, 0.1208]],
];
export function dropletPath(x, y, w, h) {
  const p = ([u, v]) => `${(x + u * w).toFixed(2)} ${(y + v * h).toFixed(2)}`;
  return `M${p(TIP)} ` + SEGS.map(([a, b, c]) => `C${p(a)} ${p(b)} ${p(c)}`).join(" ") + " Z";
}
export function waterline(remaining) {
  const r = clamp(remaining);
  return 0.17 + (1 - r) * (0.92 - 0.17);
}
/** SVG markup for DropletGauge / the menu-bar glyph. */
export function gaugeSVG(id, { w, h, bx = 0, by = 0, bw = w, bh = h, remaining, tint, stroke }) {
  const wl = by + waterline(remaining) * bh;
  const amp = bh * 0.02;
  const wave = `M${bx} ${wl} Q${bx + bw * 0.25} ${wl - amp} ${bx + bw / 2} ${wl} Q${bx + bw * 0.75} ${wl + amp} ${bx + bw} ${wl} L${bx + bw} ${by + bh} L${bx} ${by + bh} Z`;
  const shape = dropletPath(bx, by, bw, bh);
  const fill = remaining >= 0.97
    ? `<path d="${shape}" fill="${tint}"/>`
    : `<clipPath id="${id}"><path d="${shape}"/></clipPath><path d="${wave}" fill="${tint}" clip-path="url(#${id})"/>`;
  return `<svg width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">${fill}<path d="${shape}" fill="none" stroke="${tint}" stroke-width="${stroke}" stroke-linejoin="round"/></svg>`;
}

function cardHeight(n) {
  const rows = n * (M.windowLineHeight + M.windowBarSpacing) + M.mainBarHeight + (n - 1) * M.secondaryBarHeight;
  return M.cardPadding * 2 + M.cardHeaderHeight + n * M.cardContentSpacing + rows;
}

function el(tag, cls, parent, html) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (html != null) e.innerHTML = html;
  if (parent) parent.appendChild(e);
  return e;
}

/** A capacity bar that can "zip" in from the left with an anime head. */
function zipBar(parent, { main, severity, pct, y, x, width, key }) {
  const h = main ? M.mainBarHeight : M.secondaryBarHeight;
  const wrap = el("div", "pj-bar", parent);
  Object.assign(wrap.style, { left: `${x}px`, top: `${y}px`, width: `${width}px`, height: `${h}px` });
  const track = el("div", "pj-track", wrap);
  const fill = el("div", `pj-fill ${severity}${main ? " main" : ""}`, wrap);
  const head = el("div", `pj-head ${severity}`, wrap);
  const streaks = el("div", "pj-streaks", wrap);
  const lines = [];
  for (let i = 0; i < 5; i++) {
    const l = el("div", `pj-streak ${severity}`, streaks);
    lines.push(l);
  }
  const glint = el("div", "pj-glint", wrap);
  return { wrap, track, fill, head, streaks, lines, glint, h, width, pct, key, main };
}

/** Pose a bar for a zip progress z (0..1, may overshoot), with speed v (0..1). */
export function poseBar(b, z, v = 0, glint = -1, seed = 0) {
  const target = b.pct / 100;
  const w = Math.max(z > 0.001 ? b.h : 0, b.width * target * z);
  b.fill.style.width = `${w}px`;
  b.fill.style.opacity = z > 0.001 ? 1 : 0;
  const hv = clamp(v);
  b.head.style.opacity = hv;
  b.head.style.transform = `translateX(${w - 14}px) scaleX(${1 + hv * 2.2})`;
  b.lines.forEach((l, i) => {
    const r = Math.sin((i + 1) * 12.9898 + seed * 78.233) * 43758.5453;
    const f = r - Math.floor(r);
    const len = (40 + f * 110) * hv;
    const off = (i - 2) * (b.h * 0.9 + 2.2);
    l.style.opacity = hv * (0.35 + f * 0.6);
    l.style.width = `${len}px`;
    l.style.transform = `translate(${w - len - 6 - f * 30}px, ${off}px)`;
  });
  b.glint.style.opacity = glint >= 0 && glint <= 1 ? Math.sin(glint * Math.PI) : 0;
  b.glint.style.transform = `translateX(${lerp(-30, w + 10, glint)}px) skewX(-20deg)`;
}

export function createPanel(parent, data) {
  const root = el("div", "pj-panel", parent);
  const mat = el("div", "pj-mat", root);
  el("div", "pj-sheen", root);
  el("div", "pj-stroke", root);

  // Header.
  const header = el("div", "pj-header", root);
  const circ = el("div", "pj-hcircle", header);
  circ.innerHTML = gaugeSVG("hdrclip", { w: 17, h: 19, remaining: data.header.remaining, tint: data.header.tint, stroke: 1.6 });
  const htext = el("div", "pj-htext", header);
  const title = el("div", "pj-title", htext, data.header.title);
  const sub = el("div", "pj-sub", htext, data.header.subtitle);
  const close = el("div", "pj-close", header, `<svg width="10" height="10" viewBox="0 0 10 10"><path d="M1.5 1.5 L8.5 8.5 M8.5 1.5 L1.5 8.5" stroke="rgba(255,255,255,0.55)" stroke-width="1.9" stroke-linecap="round"/></svg>`);

  const cards = data.cards.map((c) => {
    const card = el("div", "pj-card", root);
    const hdr = el("div", "pj-cardhdr", card);
    el("div", "pj-dot", hdr).style.background = c.color;
    el("div", "pj-name", hdr, c.name);
    let chevron = null;
    if (c.rows.length > 1) {
      chevron = el("div", "pj-chevron", hdr, `<svg width="16" height="16" viewBox="0 0 16 16"><path d="M6 3.5 L10.5 8 L6 12.5" fill="none" stroke="rgba(255,255,255,0.35)" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/></svg>`);
    }
    const body = el("div", "pj-cardbody", card);
    let y = 0;
    const rows = c.rows.map((r, i) => {
      const main = i === 0;
      const row = el("div", "pj-row", body);
      row.style.top = `${y}px`;
      const line = el("div", "pj-line", row);
      el("div", `pj-label${r.severity === "low" ? " muted" : ""}`, line, r.label);
      const right = el("div", "pj-right", line);
      el("span", "pj-pct", right, `${r.pct}% left`);
      el("span", "pj-sep", right, "·");
      el("span", `pj-reset ${r.severity}`, right, r.reset);
      const bar = zipBar(row, { main, severity: r.severity, pct: r.pct, x: 0, y: M.windowLineHeight + M.windowBarSpacing, width: M.width - 2 * M.contentPadding - 2 * M.cardPadding, key: `${c.id}-${i}` });
      const top = y;
      y += M.windowLineHeight + M.windowBarSpacing + (main ? M.mainBarHeight : M.secondaryBarHeight) + M.cardContentSpacing;
      return { row, bar, top };
    });
    return { ...c, card, hdr, chevron, body, rows };
  });

  /**
   * s: { expand: {id: 0..1+}, zip: {key: [z, v, glint]}, appear: 0..1 per part,
   *      chevronPress: {id: 0..1}, rowsIn: {id: 0..1 per secondary row} }
   */
  function layout(s) {
    let y = M.contentPadding + M.headerHeight + M.cardSpacing;
    const geo = { cards: {} };
    cards.forEach((c, ci) => {
      const e = s.expand?.[c.id] ?? 0;
      const n = c.rows.length;
      const collapsedH = cardHeight(1);
      const h = n > 1 ? lerp(collapsedH, cardHeight(n), e) : collapsedH;
      const ap = s.appear?.[`card${ci}`] ?? 1;
      c.card.style.top = `${y}px`;
      c.card.style.height = `${h}px`;
      c.card.style.opacity = clamp(ap * 1.4);
      c.card.style.transform = `translateY(${(1 - ap) * -16}px) rotateX(${(1 - ap) * -40}deg)`;
      if (c.chevron) {
        const press = s.chevronPress?.[c.id] ?? 0;
        c.chevron.style.transform = `rotate(${clamp(e, 0, 1.08) * 90}deg) scale(${1 - press * 0.18})`;
      }
      c.rows.forEach((r, i) => {
        if (i === 0) return;
        // Secondary rows unfold from a hinge at their top as the card opens.
        const k = clamp((e - 0.15 - (i - 1) * 0.22) / 0.55);
        r.row.style.opacity = k;
        r.row.style.transform = `translateY(${(1 - k) * -10}px) rotateX(${(1 - k) * -70}deg)`;
      });
      c.rows.forEach((r) => {
        const z = s.zip?.[r.bar.key] ?? [1, 0, -1];
        poseBar(r.bar, z[0], z[1], z[2], r.bar.key.length + z[0] * 3);
      });
      geo.cards[c.id] = {
        x: M.contentPadding, y, w: M.width - 2 * M.contentPadding, h,
        chevron: c.chevron ? [M.width - M.contentPadding - M.cardPadding - 8, y + M.cardPadding + 8] : null,
        rows: c.rows.map((r) => ({ y: y + M.cardPadding + M.cardHeaderHeight + M.cardContentSpacing + r.top })),
      };
      y += h + M.cardSpacing;
    });
    const H = y - M.cardSpacing + M.contentPadding;
    root.style.height = `${H}px`;
    const ha = s.appear?.header ?? 1;
    header.style.opacity = clamp(ha * 1.3);
    header.style.transform = `translateY(${(1 - ha) * -8}px)`;
    geo.height = H;
    geo.glyph = [M.contentPadding + 4 + 15, M.contentPadding + 16];
    return geo;
  }

  return { root, layout, cards };
}
