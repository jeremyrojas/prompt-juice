(() => {
  // src/anim.js
  var clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v)), lerp = (a, b, k) => a + (b - a) * k;
  var ease = {
    linear: (k) => k,
    inOut2: (k) => k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2,
    inOut3: (k) => k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2,
    inOut4: (k) => k < 0.5 ? 8 * k ** 4 : 1 - Math.pow(-2 * k + 2, 4) / 2,
    in2: (k) => k * k,
    in3: (k) => k * k * k,
    in4: (k) => k ** 4,
    out2: (k) => 1 - (1 - k) * (1 - k),
    out3: (k) => 1 - Math.pow(1 - k, 3),
    out4: (k) => 1 - Math.pow(1 - k, 4),
    outExpo: (k) => k >= 1 ? 1 : 1 - Math.pow(2, -10 * k),
    inExpo: (k) => k <= 0 ? 0 : Math.pow(2, 10 * k - 10),
    inOutExpo: (k) => k <= 0 ? 0 : k >= 1 ? 1 : k < 0.5 ? Math.pow(2, 20 * k - 10) / 2 : (2 - Math.pow(2, -20 * k + 10)) / 2,
    outBack: (k, s = 1.5) => 1 + (s + 1) * Math.pow(k - 1, 3) + s * Math.pow(k - 1, 2)
  };
  function seg(t, t0, t1, fn = ease.linear) {
    return t <= t0 ? 0 : t >= t1 ? 1 : fn((t - t0) / (t1 - t0));
  }
  function spring(t, t0, { zeta = 0.8, freq = 2.2 } = {}) {
    let x = t - t0;
    if (x <= 0) return 0;
    let w = 2 * Math.PI * freq;
    if (zeta >= 1) return 1 - (1 + w * x) * Math.exp(-w * x);
    let wd = w * Math.sqrt(1 - zeta * zeta);
    return 1 - Math.exp(-zeta * w * x) * (Math.cos(wd * x) + zeta * w / wd * Math.sin(wd * x));
  }
  function wobble(t, t0, { amp = 1, freq = 2.5, decay = 3.5 } = {}) {
    let x = t - t0;
    return x <= 0 ? 0 : amp * Math.sin(2 * Math.PI * freq * x) * Math.exp(-decay * x);
  }
  function keys(t, list) {
    if (t <= list[0][0]) return list[0][1];
    for (let i = 1; i < list.length; i++) {
      let [t1, v1, fn = ease.inOut3] = list[i], [t0, v0] = list[i - 1];
      if (t <= t1) {
        let k = fn((t - t0) / Math.max(1e-6, t1 - t0));
        return Array.isArray(v0) ? v0.map((a, j) => lerp(a, v1[j], k)) : lerp(v0, v1, k);
      }
    }
    return list[list.length - 1][1];
  }
  function rng(seed) {
    let a = seed >>> 0;
    return () => {
      a = a + 1831565813 | 0;
      let t = Math.imul(a ^ a >>> 15, 1 | a);
      return t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t, ((t ^ t >>> 14) >>> 0) / 4294967296;
    };
  }

  // src/panel.js
  var M = {
    width: 384,
    contentPadding: 14,
    headerHeight: 32,
    cardSpacing: 8,
    cardHeaderHeight: 16,
    cardPadding: 12,
    cardContentSpacing: 10,
    windowLineHeight: 16,
    windowBarSpacing: 5,
    mainBarHeight: 6,
    secondaryBarHeight: 3,
    radius: 22
  }, TIP = [0.5, 0.1208], SEGS = [
    [[0.5, 0.1208], [0.2083, 0.4708], [0.2083, 0.6667]],
    [[0.2083, 0.8292], [0.3375, 0.9333], [0.5, 0.9333]],
    [[0.6625, 0.9333], [0.7917, 0.8292], [0.7917, 0.6667]],
    [[0.7917, 0.4708], [0.5, 0.1208], [0.5, 0.1208]]
  ];
  function dropletPath(x, y, w, h) {
    let p = ([u, v]) => `${(x + u * w).toFixed(2)} ${(y + v * h).toFixed(2)}`;
    return `M${p(TIP)} ` + SEGS.map(([a, b, c]) => `C${p(a)} ${p(b)} ${p(c)}`).join(" ") + " Z";
  }
  function waterline(remaining) {
    return 0.17 + (1 - clamp(remaining)) * (0.92 - 0.17);
  }
  function gaugeSVG(id, { w, h, bx = 0, by = 0, bw = w, bh = h, remaining, tint, stroke }) {
    let wl = by + waterline(remaining) * bh, amp = bh * 0.02, wave = `M${bx} ${wl} Q${bx + bw * 0.25} ${wl - amp} ${bx + bw / 2} ${wl} Q${bx + bw * 0.75} ${wl + amp} ${bx + bw} ${wl} L${bx + bw} ${by + bh} L${bx} ${by + bh} Z`, shape = dropletPath(bx, by, bw, bh), fill = remaining >= 0.97 ? `<path d="${shape}" fill="${tint}"/>` : `<clipPath id="${id}"><path d="${shape}"/></clipPath><path d="${wave}" fill="${tint}" clip-path="url(#${id})"/>`;
    return `<svg width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">${fill}<path d="${shape}" fill="none" stroke="${tint}" stroke-width="${stroke}" stroke-linejoin="round"/></svg>`;
  }
  function cardHeight(n) {
    let rows = n * (M.windowLineHeight + M.windowBarSpacing) + M.mainBarHeight + (n - 1) * M.secondaryBarHeight;
    return M.cardPadding * 2 + M.cardHeaderHeight + n * M.cardContentSpacing + rows;
  }
  function el(tag, cls, parent, html) {
    let e = document.createElement(tag);
    return cls && (e.className = cls), html != null && (e.innerHTML = html), parent && parent.appendChild(e), e;
  }
  function zipBar(parent, { main, severity, pct, y, x, width, key }) {
    let h = main ? M.mainBarHeight : M.secondaryBarHeight, wrap = el("div", "pj-bar", parent);
    Object.assign(wrap.style, { left: `${x}px`, top: `${y}px`, width: `${width}px`, height: `${h}px` });
    let track = el("div", "pj-track", wrap), fill = el("div", `pj-fill ${severity}${main ? " main" : ""}`, wrap), head = el("div", `pj-head ${severity}`, wrap), streaks = el("div", "pj-streaks", wrap), lines = [];
    for (let i = 0; i < 5; i++) {
      let l = el("div", `pj-streak ${severity}`, streaks);
      lines.push(l);
    }
    let glint = el("div", "pj-glint", wrap);
    return { wrap, track, fill, head, streaks, lines, glint, h, width, pct, key, main };
  }
  function poseBar(b, z, v = 0, glint = -1, seed = 0) {
    let target = b.pct / 100, w = Math.max(z > 1e-3 ? b.h : 0, b.width * target * z);
    b.fill.style.width = `${w}px`, b.fill.style.opacity = z > 1e-3 ? 1 : 0;
    let hv = clamp(v);
    b.head.style.opacity = hv, b.head.style.transform = `translateX(${w - 14}px) scaleX(${1 + hv * 2.2})`, b.lines.forEach((l, i) => {
      let r = Math.sin((i + 1) * 12.9898 + seed * 78.233) * 43758.5453, f = r - Math.floor(r), len = (40 + f * 110) * hv, off = (i - 2) * (b.h * 0.9 + 2.2);
      l.style.opacity = hv * (0.35 + f * 0.6), l.style.width = `${len}px`, l.style.transform = `translate(${w - len - 6 - f * 30}px, ${off}px)`;
    }), b.glint.style.opacity = glint >= 0 && glint <= 1 ? Math.sin(glint * Math.PI) : 0, b.glint.style.transform = `translateX(${lerp(-30, w + 10, glint)}px) skewX(-20deg)`;
  }
  function createPanel(parent, data) {
    let root = el("div", "pj-panel", parent), mat = el("div", "pj-mat", root);
    el("div", "pj-sheen", root), el("div", "pj-stroke", root);
    let header = el("div", "pj-header", root), circ = el("div", "pj-hcircle", header);
    circ.innerHTML = gaugeSVG("hdrclip", { w: 17, h: 19, remaining: data.header.remaining, tint: data.header.tint, stroke: 1.6 });
    let htext = el("div", "pj-htext", header), title = el("div", "pj-title", htext, data.header.title), sub = el("div", "pj-sub", htext, data.header.subtitle), close = el("div", "pj-close", header, '<svg width="10" height="10" viewBox="0 0 10 10"><path d="M1.5 1.5 L8.5 8.5 M8.5 1.5 L1.5 8.5" stroke="rgba(255,255,255,0.55)" stroke-width="1.9" stroke-linecap="round"/></svg>'), cards = data.cards.map((c) => {
      let card = el("div", "pj-card", root), hdr = el("div", "pj-cardhdr", card);
      el("div", "pj-dot", hdr).style.background = c.color, el("div", "pj-name", hdr, c.name);
      let chevron = null;
      c.rows.length > 1 && (chevron = el("div", "pj-chevron", hdr, '<svg width="16" height="16" viewBox="0 0 16 16"><path d="M6 3.5 L10.5 8 L6 12.5" fill="none" stroke="rgba(255,255,255,0.35)" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/></svg>'));
      let body = el("div", "pj-cardbody", card), y = 0, rows = c.rows.map((r, i) => {
        let main = i === 0, row = el("div", "pj-row", body);
        row.style.top = `${y}px`;
        let line = el("div", "pj-line", row);
        el("div", `pj-label${r.severity === "low" ? " muted" : ""}`, line, r.label);
        let right = el("div", "pj-right", line);
        el("span", "pj-pct", right, `${r.pct}% left`), el("span", "pj-sep", right, "\xB7"), el("span", `pj-reset ${r.severity}`, right, r.reset);
        let bar = zipBar(row, { main, severity: r.severity, pct: r.pct, x: 0, y: M.windowLineHeight + M.windowBarSpacing, width: M.width - 2 * M.contentPadding - 2 * M.cardPadding, key: `${c.id}-${i}` }), top = y;
        return y += M.windowLineHeight + M.windowBarSpacing + (main ? M.mainBarHeight : M.secondaryBarHeight) + M.cardContentSpacing, { row, bar, top };
      });
      return { ...c, card, hdr, chevron, body, rows };
    });
    function layout(s) {
      let y = M.contentPadding + M.headerHeight + M.cardSpacing, geo = { cards: {} };
      cards.forEach((c, ci) => {
        let e = s.expand?.[c.id] ?? 0, n = c.rows.length, collapsedH = cardHeight(1), h = n > 1 ? lerp(collapsedH, cardHeight(n), e) : collapsedH, ap = s.appear?.[`card${ci}`] ?? 1;
        if (c.card.style.top = `${y}px`, c.card.style.height = `${h}px`, c.card.style.opacity = clamp(ap * 1.4), c.card.style.transform = `translateY(${(1 - ap) * -16}px) rotateX(${(1 - ap) * -40}deg)`, c.chevron) {
          let press = s.chevronPress?.[c.id] ?? 0;
          c.chevron.style.transform = `rotate(${clamp(e, 0, 1.08) * 90}deg) scale(${1 - press * 0.18})`;
        }
        c.rows.forEach((r, i) => {
          if (i === 0) return;
          let k = clamp((e - 0.15 - (i - 1) * 0.22) / 0.55);
          r.row.style.opacity = k, r.row.style.transform = `translateY(${(1 - k) * -10}px) rotateX(${(1 - k) * -70}deg)`;
        }), c.rows.forEach((r) => {
          let z = s.zip?.[r.bar.key] ?? [1, 0, -1];
          poseBar(r.bar, z[0], z[1], z[2], r.bar.key.length + z[0] * 3);
        }), geo.cards[c.id] = {
          x: M.contentPadding,
          y,
          w: M.width - 2 * M.contentPadding,
          h,
          chevron: c.chevron ? [M.width - M.contentPadding - M.cardPadding - 8, y + M.cardPadding + 8] : null,
          rows: c.rows.map((r) => ({ y: y + M.cardPadding + M.cardHeaderHeight + M.cardContentSpacing + r.top }))
        }, y += h + M.cardSpacing;
      });
      let H2 = y - M.cardSpacing + M.contentPadding;
      root.style.height = `${H2}px`;
      let ha = s.appear?.header ?? 1;
      return header.style.opacity = clamp(ha * 1.3), header.style.transform = `translateY(${(1 - ha) * -8}px)`, geo.height = H2, geo.glyph = [M.contentPadding + 4 + 15, M.contentPadding + 16], geo;
    }
    return { root, layout, cards };
  }

  // src/main.js
  var DURATION = 22.6, W = 1920, H = 1080, GREEN = [95, 209, 31], AMBER = [240, 163, 42], MASCOT_ASPECT = 776 / 1115, film = document.getElementById("film");
  function el2(tag, cls, parent, html) {
    let e = document.createElement(tag);
    return cls && (e.className = cls), html != null && (e.innerHTML = html), (parent || film).appendChild(e), e;
  }
  var rgba = (c, a) => `rgba(${c[0]},${c[1]},${c[2]},${a})`, mixC = (a, b, k) => a.map((v, i) => Math.round(lerp(v, b[i], k))), hop = (t, t0, d) => {
    let x = (t - t0) / d;
    return x <= 0 || x >= 1 ? 0 : 4 * x * (1 - x);
  }, bump = (t, t0, d) => {
    let x = (t - t0) / d;
    return x <= 0 || x >= 1 ? 0 : Math.sin(Math.PI * x);
  }, show = (e, on) => {
    e.style.display = on ? "" : "none";
  }, bg = el2("div", "layer"), glow = el2("div", "", bg);
  glow.id = "glow";
  var bgFlash = el2("div", "layer", bg), fxBack = el2("canvas", "fx");
  fxBack.width = W;
  fxBack.height = H;
  var world = el2("div", "layer"), fxFront = el2("canvas", "fx");
  fxFront.width = W;
  fxFront.height = H;
  var vignette = el2("div", "layer");
  vignette.id = "vignette";
  var flash = el2("div", "");
  flash.id = "flash";
  var bctx = fxBack.getContext("2d"), fctx = fxFront.getContext("2d"), EXPRS = ["happy", "blink", "joy", "alert"];
  function createMascot(parent) {
    let shadow = el2("div", "shadow", parent), root = el2("div", "mascot", parent), imgs = { base: {}, top: {} }, add = (layer, holder) => {
      for (let c of ["green", "amber"]) for (let e of EXPRS) {
        let i = el2("img", "", holder);
        i.src = `assets/img/mascot-${c}-${e}.png`, imgs[layer][`${c}-${e}`] = i;
      }
    };
    add("base", root);
    let top = el2("div", "top", root);
    add("top", top);
    let bang = el2("div", "bang", parent, "!"), shownBase = null, shownTop = null;
    function pose(p) {
      let vis = p.visible !== !1 && (p.opacity ?? 1) > 1e-3;
      if (show(root, vis), show(shadow, vis && p.shadow !== !1), !vis) {
        show(bang, !1);
        return;
      }
      let h = p.h, w = h * MASCOT_ASPECT, lift = p.lift ?? 0;
      root.style.width = `${w}px`, root.style.height = `${h}px`, root.style.opacity = p.opacity ?? 1, root.style.transform = `translate(${p.x - w / 2}px, ${p.ground - lift - h}px) rotate(${p.rot ?? 0}deg) scale(${p.sx ?? 1}, ${p.sy ?? 1})`, root.style.filter = p.silhouette ? "brightness(0)" : "";
      let expr = p.expr ?? "happy", b = imgs.base[`${p.from ?? "green"}-${expr}`];
      shownBase !== b && (shownBase && show(shownBase, !1), b.style.display = "block", shownBase = b);
      let k = p.k ?? 0, tImg = imgs.top[`${p.to ?? "amber"}-${expr}`];
      if (k > 1e-3)
        if (shownTop !== tImg && (shownTop && show(shownTop, !1), tImg.style.display = "block", shownTop = tImg), k >= 0.999) top.style.clipPath = "none";
        else {
          let level = lerp(104, -4, k), pts = [];
          for (let i = 0; i <= 20; i++) {
            let x = i * 5, y = level + 2.4 * Math.sin(i * 0.9 + (p.t ?? 0) * 14) + 1.2 * Math.sin(i * 2.1 - (p.t ?? 0) * 9);
            pts.push(`${x}% ${y}%`);
          }
          top.style.clipPath = `polygon(${pts.join(",")}, 100% 100%, 0% 100%)`;
        }
      else shownTop && (show(shownTop, !1), shownTop = null);
      let sw = w * 0.78 * (1 - clamp(lift / 500) * 0.6) * (p.sx ?? 1);
      shadow.style.width = `${sw}px`, shadow.style.height = `${sw * 0.16}px`, shadow.style.transform = `translate(${p.x - sw / 2}px, ${p.ground - sw * 0.08}px)`, shadow.style.opacity = (p.opacity ?? 1) * (1 - clamp(lift / 600)) * (p.shadowOpacity ?? 1);
      let bk = p.bang ?? 0;
      show(bang, bk > 0.01), bk > 0.01 && (bang.style.fontSize = `${h * 0.24}px`, bang.style.transform = `translate(${p.x + w * 0.56}px, ${p.ground - lift - h * 0.92}px) rotate(14deg) scale(${bk})`);
    }
    return { pose, root };
  }
  function createBigBar(parent, { x, y, w, h }) {
    let root = el2("div", "bigbar", parent);
    Object.assign(root.style, { left: `${x}px`, top: `${y}px`, width: `${w}px`, height: `${h}px` }), el2("div", "track", root);
    let fill = el2("div", "fill", root), sweep = el2("div", "fill", root), head = el2("div", "head", root), streaks = [], R = rng(7);
    for (let i = 0; i < 12; i++) {
      let s = el2("div", "streak", root);
      streaks.push({ el: s, y: lerp(-0.9, 1.9, R()) * h, len: 120 + R() * 380, lag: R() * 90, th: 2 + R() * 4, a: 0.35 + R() * 0.6 });
    }
    let glint = el2("div", "glint", root), style = (c) => c === "green" ? { background: "linear-gradient(90deg,#3fa512 0%,#5fd11f 62%,#8be24e 100%)", boxShadow: "0 0 34px rgba(95,209,31,.55), 0 0 4px rgba(190,255,140,.6)" } : { background: "linear-gradient(90deg,#d9880f 0%,#f0a32a 58%,#ffc15e 100%)", boxShadow: "0 0 34px rgba(240,163,42,.55), 0 0 4px rgba(255,220,150,.6)" }, lastColor = null, lastSweep = null;
    return {
      root,
      x,
      y,
      w,
      h,
      headX: (z) => x + w * z,
      pose({ z, color = "green", v = 0, glint: g = -1, sweepK = 0, sweepColor = "amber", opacity = 1, ty = 0 }) {
        root.style.opacity = opacity, root.style.transform = `translateY(${ty}px)`, lastColor !== color && (Object.assign(fill.style, style(color)), lastColor = color), lastSweep !== sweepColor && (Object.assign(sweep.style, style(sweepColor)), lastSweep = sweepColor);
        let fw = z > 2e-3 ? Math.max(h, w * z) : 0;
        fill.style.width = `${fw}px`, sweep.style.width = `${Math.min(fw, Math.max(sweepK > 0 ? h : 0, fw * sweepK))}px`, sweep.style.opacity = sweepK > 0 ? 1 : 0;
        let hx = sweepK > 0 && sweepK < 1 ? fw * sweepK : fw, vv = clamp(v);
        head.style.opacity = vv, head.style.transform = `translateX(${hx - 60}px) scaleX(${1 + vv * 1.6})`;
        let c = (sweepK > 0 && sweepK < 1 ? sweepColor : color) === "green" ? GREEN : AMBER;
        return streaks.forEach((s) => {
          let len = s.len * vv;
          s.el.style.opacity = vv * s.a, s.el.style.width = `${len}px`, s.el.style.height = `${s.th}px`, s.el.style.background = `linear-gradient(90deg, ${rgba(c, 0)}, ${rgba(mixC(c, [255, 255, 255], 0.55), 1)})`, s.el.style.transform = `translate(${hx - len - s.lag}px, ${s.y - h / 2}px)`;
        }), glint.style.opacity = g >= 0 && g <= 1 ? Math.sin(g * Math.PI) : 0, glint.style.transform = `translateX(${lerp(-80, fw + 10, g)}px) skewX(-20deg)`, x + hx;
      }
    };
  }
  function createTitle(parent, words, { size = 112, cls = "title" } = {}) {
    let root = el2("div", cls, parent);
    root.style.fontSize = `${size}px`;
    let spans = words.map(([text, c], i) => {
      let s = el2("span", `w ${c || ""}`, root, text);
      return i < words.length - 1 && root.appendChild(document.createTextNode(" ")), s;
    });
    return { root, spans, width: 0, measure() {
      this.width = root.offsetWidth, this.lefts = spans.map((s) => s.offsetLeft), this.widths = spans.map((s) => s.offsetWidth);
    } };
  }
  function wordIn(span, t, t0, kind) {
    let k = seg(t, t0, t0 + (kind === "slam" ? 0.22 : 0.3), ease.out3);
    if (kind === "slam") {
      let s = lerp(1.7, 1, ease.outExpo(clamp((t - t0) / 0.3)));
      span.style.transform = `scale(${s})`, span.style.filter = `blur(${(1 - k) * 14}px)`;
    } else
      span.style.transform = `translateY(${(1 - k) * 18}px)`, span.style.filter = `blur(${(1 - k) * 12}px)`;
    span.style.opacity = k;
  }
  function wordsOut(spans, t, t0) {
    spans.forEach((s, i) => {
      let k = seg(t, t0 + i * 0.03, t0 + i * 0.03 + 0.18, ease.in2);
      k <= 0 || (s.style.opacity = Math.min(parseFloat(s.style.opacity || 1), 1 - k), s.style.filter = `blur(${k * 12}px)`);
    });
  }
  function placeTitle(T, cx, y) {
    T.root.style.transform = `translate(${cx - T.width / 2}px, ${y}px)`;
  }
  function animateTitle(T, t, { t0, t1, kind = "blur", stagger = 0.07, cx = W / 2, y = 90 }) {
    let on = t >= t0 - 0.01 && t < t1 + 0.4;
    show(T.root, on), on && (placeTitle(T, cx, y), T.spans.forEach((s, i) => wordIn(s, t, t0 + i * stagger, kind)), wordsOut(T.spans, t, t1));
  }
  function focusLines(ctx, cx, cy, rInner, color, alpha, seed, count = 90) {
    if (alpha <= 0.01) return;
    let R = rng(seed);
    ctx.save(), ctx.translate(cx, cy);
    for (let i = 0; i < count; i++) {
      let a = R() * Math.PI * 2, wid = 4e-3 + R() * 0.012, r0 = rInner * (0.85 + R() * 0.6), r1 = 1500;
      ctx.fillStyle = rgba(color, alpha * (0.25 + R() * 0.75)), ctx.beginPath(), ctx.moveTo(Math.cos(a) * r0, Math.sin(a) * r0), ctx.lineTo(Math.cos(a - wid) * r1, Math.sin(a - wid) * r1), ctx.lineTo(Math.cos(a + wid) * r1, Math.sin(a + wid) * r1), ctx.closePath(), ctx.fill();
    }
    ctx.restore();
  }
  function rays(ctx, cx, cy, color, alpha, rot, n = 14) {
    if (alpha <= 0.01) return;
    ctx.save(), ctx.translate(cx, cy), ctx.rotate(rot);
    let g = ctx.createRadialGradient(0, 0, 60, 0, 0, 1100);
    g.addColorStop(0, rgba(color, alpha)), g.addColorStop(1, rgba(color, 0)), ctx.fillStyle = g;
    for (let i = 0; i < n; i++) {
      let a = i / n * Math.PI * 2;
      ctx.beginPath(), ctx.moveTo(0, 0), ctx.arc(0, 0, 1400, a, a + Math.PI / n * 0.9), ctx.closePath(), ctx.fill();
    }
    ctx.restore();
  }
  function sparkle(ctx, x, y, size, alpha, rot = 0, color = [255, 255, 255]) {
    if (!(alpha <= 0.01 || size <= 0.5)) {
      ctx.save(), ctx.translate(x, y), ctx.rotate(rot), ctx.fillStyle = rgba(color, alpha), ctx.shadowColor = rgba(color, alpha), ctx.shadowBlur = size * 0.8, ctx.beginPath();
      for (let i = 0; i < 4; i++) {
        let a = i * Math.PI / 2;
        ctx.lineTo(Math.cos(a) * size, Math.sin(a) * size), ctx.lineTo(Math.cos(a + Math.PI / 4) * size * 0.16, Math.sin(a + Math.PI / 4) * size * 0.16);
      }
      ctx.closePath(), ctx.fill(), ctx.restore();
    }
  }
  function burst(ctx, x, y, t, t0, color, { n = 10, r0 = 60, r1 = 170, dur = 0.32, width = 7, seed = 3 } = {}) {
    let k = (t - t0) / dur;
    if (k <= 0 || k >= 1) return;
    let R = rng(seed);
    ctx.save(), ctx.strokeStyle = rgba(color, 1 - k * k), ctx.lineCap = "round", ctx.lineWidth = width * (1 - k * 0.6);
    for (let i = 0; i < n; i++) {
      let a = i / n * Math.PI * 2 + R() * 0.3, e = ease.out3(k), a0 = lerp(r0, r1, e), a1 = lerp(r0, r1, clamp(e * 1.25 + 0.15)), s0 = Math.max(a0, a1 - 60 * (1 - k));
      ctx.beginPath(), ctx.moveTo(x + Math.cos(a) * s0, y + Math.sin(a) * s0), ctx.lineTo(x + Math.cos(a) * a1, y + Math.sin(a) * a1), ctx.stroke();
    }
    ctx.restore();
  }
  function sparks(ctx, x, y, t, t0, color, { n = 16, dur = 0.7, speed: speed2 = 520, seed = 11, dir = 0, spread = Math.PI * 2 } = {}) {
    let k = t - t0;
    if (k <= 0 || k >= dur) return;
    let R = rng(seed);
    for (let i = 0; i < n; i++) {
      let a = dir + (R() - 0.5) * spread, v = speed2 * (0.4 + R() * 0.8), px = x + Math.cos(a) * v * k, py = y + Math.sin(a) * v * k + 900 * k * k, life = 1 - k / (dur * (0.6 + R() * 0.4));
      life <= 0 || (ctx.fillStyle = rgba(color, life), ctx.beginPath(), ctx.arc(px, py, 3 + R() * 5 * life, 0, Math.PI * 2), ctx.fill());
    }
  }
  function shake(t, hits) {
    let x = 0, y = 0;
    return hits.forEach(([t0, amp], i) => {
      let d = t - t0;
      if (d < 0 || d > 0.5) return;
      let a = amp * Math.exp(-d * 11);
      x += a * Math.sin(d * 95 + i * 1.7), y += a * Math.cos(d * 83 + i * 2.3);
    }), [x, y];
  }
  var sceneA = el2("div", "layer", world), sceneD = el2("div", "layer", world), sceneE = el2("div", "layer", world), sceneF = el2("div", "layer", world), mascotLayer = el2("div", "layer", world), rowA = el2("div", "layer", sceneA), barA = createBigBar(rowA, { x: 210, y: 822, w: 1500, h: 44 }), labelA = el2("div", "caption", rowA, "5-hour limit");
  labelA.style.cssText += "color: rgba(255,255,255,.55); font-weight: 500;";
  var valueA = el2("div", "caption", rowA, '<span class="pct">83% left</span><span style="color:rgba(255,255,255,.3)"> \xB7 </span><span class="reset">resets in <span class="clk">2h 56m</span></span>'), valueAReset = valueA.querySelector(".reset"), valueAClk = valueA.querySelector(".clk"), titleA = createTitle(sceneA, [["Plenty"], ["left."], ["Resets", "amber"], ["soon.", "amber"]]), titleB = createTitle(sceneA, [["You"], ["paid"], ["for"], ["the"], ["juice.", "amber"]]), titleC = createTitle(sceneA, [["In"], ["your"], ["menu"], ["bar."]], { size: 84 }), MB_S = 2.4, menubar = el2("div", "", world);
  menubar.id = "menubar";
  menubar.style.width = `${W / MB_S}px`;
  var mbHL = el2("div", "hl", menubar), GLYPH_PT = 590, mbGlyph = el2("div", "item", menubar);
  Object.assign(mbGlyph.style, { left: `${GLYPH_PT - 13}px`, width: "26px" });
  mbGlyph.innerHTML = gaugeSVG("mbclip", { w: 18, h: 18, bx: 18 * 0.18, by: 18 * 0.05, bw: 18 * 0.64, bh: 18 * 0.9, remaining: 0.8, tint: "#f0a32a", stroke: 1.27 });
  var icons = [
    [624, '<svg width="17" height="13" viewBox="0 0 17 13"><path d="M8.5 12.2 L5.9 9.4 A3.8 3.8 0 0 1 11.1 9.4 Z" fill="#fff"/><path d="M3.6 7.2 A7 7 0 0 1 13.4 7.2" stroke="#fff" stroke-width="1.6" fill="none" stroke-linecap="round"/><path d="M1.2 4.6 A10.4 10.4 0 0 1 15.8 4.6" stroke="#fff" stroke-width="1.6" fill="none" stroke-linecap="round"/></svg>'],
    [660, '<svg width="27" height="13" viewBox="0 0 27 13"><rect x="0.75" y="0.75" width="22" height="11.5" rx="3.4" stroke="rgba(255,255,255,.55)" stroke-width="1.2" fill="none"/><rect x="2.6" y="2.6" width="15" height="7.8" rx="1.8" fill="#fff"/><path d="M24.6 4.6 v3.8" stroke="rgba(255,255,255,.55)" stroke-width="1.6" stroke-linecap="round"/></svg>'],
    [698, '<svg width="17" height="15" viewBox="0 0 17 15"><rect x="0.8" y="0.8" width="15.4" height="5.6" rx="2.8" stroke="#fff" stroke-width="1.3" fill="none"/><circle cx="12.6" cy="3.6" r="1.9" fill="#fff"/><rect x="0.8" y="8.6" width="15.4" height="5.6" rx="2.8" stroke="#fff" stroke-width="1.3" fill="none"/><circle cx="4.4" cy="11.4" r="1.9" fill="#fff"/></svg>']
  ];
  icons.forEach(([x, svg]) => {
    let i = el2("div", "item", menubar, svg);
    Object.assign(i.style, { left: `${x - 15}px`, width: "30px" });
  });
  var clock = el2("div", "item clock", menubar, "Tue 2:27 PM");
  Object.assign(clock.style, { left: "718px", width: "76px" });
  var panelStage = el2("div", "layer", sceneD);
  panelStage.id = "panelStage";
  var panelCam = el2("div", "", panelStage);
  panelCam.id = "panelCam";
  var panel = createPanel(panelCam, {
    header: { title: "Use your Claude juice", subtitle: "5-hour \xB7 83% left \xB7 resets in 33m", remaining: 0.83, tint: "#f0a32a" },
    cards: [
      { id: "claude", name: "Claude", color: "#ff9f0a", rows: [
        { label: "5-hour limit", pct: 83, reset: "resets in 33m", severity: "useSoon" },
        { label: "Weekly", pct: 88, reset: "resets in 4d", severity: "healthy" },
        { label: "Fable", pct: 98, reset: "resets in 4d", severity: "healthy" }
      ] },
      { id: "codex", name: "Codex", color: "#32d4de", rows: [
        { label: "Weekly", pct: 88, reset: "resets in 5d", severity: "healthy" }
      ] }
    ]
  }), legend = el2("div", "layer", sceneD), legAmber = el2("div", "legend", legend, '<img src="assets/img/mascot-amber-happy.png"><div><span style="color:var(--amber)">Resets soon.</span><small>Use your juice.</small></div>'), legGreen = el2("div", "legend", legend, '<img src="assets/img/mascot-green-happy.png"><div><span style="color:var(--green)">Plenty left.</span><small>No rush.</small></div>'), rowE = el2("div", "layer", sceneE), barE = createBigBar(rowE, { x: 260, y: 500, w: 1400, h: 46 }), labelE = el2("div", "caption", rowE, 'Claude <span style="color:rgba(255,255,255,.3)">\xB7</span> 5-hour limit');
  labelE.style.cssText += "color: rgba(255,255,255,.62); font-weight: 500; font-size: 46px; text-shadow: 0 0 14px #07080b, 0 0 6px #07080b;";
  var valueE = el2("div", "caption", rowE, '<span class="pct">83% left</span><span style="color:rgba(255,255,255,.3)"> \xB7 </span><span class="reset" style="color:var(--amber)">resets in 33m</span>');
  valueE.style.textShadow = "0 0 14px #07080b, 0 0 6px #07080b";
  var valueEPct = valueE.querySelector(".pct"), valueEReset = valueE.querySelector(".reset"), streamSvg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  streamSvg.id = "stream";
  streamSvg.setAttribute("width", W);
  streamSvg.setAttribute("height", H);
  sceneE.insertBefore(streamSvg, rowE);
  var TASKS = [
    { what: "Plan the big refactor", chip: "Strongest model" },
    { what: "Write the test suite", chip: "New task" },
    { what: "Fix the flaky CI job", chip: "New task" }
  ], taskEls = TASKS.map((tk, i) => {
    let c = el2("div", "task", sceneE, `<div class="who"><i></i>Claude</div><div class="what">${tk.what}</div><div class="chip">${tk.chip}</div><div class="prog"><b></b></div>`);
    c.style.left = `${260 + i * 480}px`, c.style.top = "680px";
    let path = document.createElementNS("http://www.w3.org/2000/svg", "path");
    return path.setAttribute("fill", "none"), path.setAttribute("stroke-linecap", "round"), streamSvg.appendChild(path), { el: c, prog: c.querySelector(".prog b"), chip: c.querySelector(".chip"), path, x: 260 + i * 480 };
  }), titleE1 = createTitle(sceneE, [["Use"], ["your"], ["strongest", "amber"], ["model.", "amber"]], { size: 100 }), titleE2 = createTitle(sceneE, [["Start"], ["another"], ["task.", "amber"]], { size: 100 }), titleE3 = createTitle(sceneE, [["Nothing", "green"], ["wasted."]], { size: 100 }), titleF = createTitle(sceneF, [["Don\u2019t"], ["waste"], ["the"], ["juice.", "green"]]), wordmark = el2("div", "wordmark", sceneF, 'Prompt<span style="color:var(--green)">Juice</span>'), url = el2("div", "url", sceneF, "promptjuice.app"), mascot = createMascot(mascotLayer), cursor = el2("div", "", world, '<svg width="46" height="68" viewBox="0 0 23 34"><path d="M1.5 1.5 L1.5 26.5 L7.6 20.8 L11.6 30.6 L15.6 29 L11.7 19.4 L20 19.4 Z" fill="#000" stroke="#fff" stroke-width="1.8" stroke-linejoin="round"/></svg>');
  cursor.id = "cursor";
  var BEATS = {
    popIn: 0,
    barZip: 0.3,
    barLand: 1,
    clockRoll: 1.72,
    turn: 2.05,
    resetsSoon: 2.24,
    youPaid: 3.42,
    jumpPrep: 5.32,
    jump: 5.47,
    glyphLand: 5.98,
    click: 6.74,
    panelOpen: 6.84,
    zipClaude: 7.1,
    zipCodex: 7.22,
    swing1: 8.36,
    glint: 9,
    chevronClick: 10.34,
    expand: 10.38,
    swing2: 11.2,
    legAmber: 11.46,
    legGreen: 11.72,
    whip: 12.62,
    strongest: 12.98,
    card1: 13.22,
    another: 14.66,
    card2: 14.88,
    card3: 15.3,
    reset: 16.36,
    nothingWasted: 16.52,
    finale: 17.96,
    mascotLand: 18.42,
    dontWaste: 18.5,
    lockup: 19.82,
    wordmarkIn: 20.22,
    endHop: 21
  }, B = BEATS, P_OPEN = [960, 76, 192, 0, 2.6, 0, 0], P_PUNCH = [960, 560, 192, 104, 4.3, 7, -13], P_PUNCH2 = [960, 560, 192, 104, 4.4, 6, -9], P_CARD = [960, 150, 192, 54, 3.4, 0, 0], P_ANGLE = [640, 560, 192, 152, 2.45, 5, 22];
  function zipZ(t, t0, opts = { zeta: 0.66, freq: 1.35 }) {
    return spring(t, t0, opts);
  }
  function speed(fn, t) {
    return Math.abs(fn(t) - fn(t - 1 / 60)) * 60;
  }
  function render(t) {
    bctx.clearRect(0, 0, W, H), fctx.clearRect(0, 0, W, H);
    let glowC = (t < B.turn ? 0 : t < B.reset ? 1 : 0) ? AMBER : GREEN, glowI = keys(t, [[0, 0.35], [0.6, 1, ease.out3], [12.6, 1], [12.75, 0.5], [13, 0.85], [17.9, 0.85], [18.4, 1.15], [22.6, 1]]), glowXY = t < 6.7 ? [960, 470] : t < 12.7 ? [960, 300] : t < 18 ? [960, 520] : t < B.lockup ? [960, 560] : [lerp(960, 760, seg(t, B.lockup, B.lockup + 0.5, ease.inOut3)), 540];
    glow.style.background = `radial-gradient(closest-side, ${rgba(glowC, 0.34 * glowI)}, ${rgba(glowC, 0.1 * glowI)} 42%, ${rgba(glowC, 0)} 72%)`, glow.style.transform = `translate(${glowXY[0] - 960}px, ${glowXY[1] - 540}px)`;
    let impact = t >= B.turn && t < B.turn + 0.07;
    bgFlash.style.background = impact ? "#f0a32a" : "", world.style.filter = impact ? "brightness(0)" : "", flash.style.background = "#fff", flash.style.opacity = t >= B.turn + 0.07 ? 0.5 * (1 - seg(t, B.turn + 0.07, B.turn + 0.3, ease.out2)) * (t < B.turn + 0.3 ? 1 : 0) : 0;
    let [sx, sy] = shake(t, [[B.turn, 16], [B.glyphLand, 5], [B.card1 + 0.04, 7], [B.card2 + 0.04, 6], [B.card3 + 0.04, 6], [B.mascotLand, 10]]);
    world.style.transform = `translate(${sx}px, ${sy}px)`, fxFront.style.transform = world.style.transform;
    let m = { visible: !0, x: 960, ground: 672, h: 390, from: "green", to: "amber", k: 0, expr: "happy", t }, inA = t < 3.5;
    if (show(sceneA, t < 6.9), show(rowA, inA), t < 6.9) {
      let pop = 0.7 + 0.3 * spring(t, B.popIn, { zeta: 0.42, freq: 2.3 }), land = wobble(t, B.barLand + 0.02, { amp: 0.08, freq: 3.2, decay: 6 });
      if (m.sx = pop * (1 + land * 0.6), m.sy = pop * (1 - land), m.lift = 46 * hop(t, B.barLand - 0.06, 0.34), m.expr = t > 0.62 && t < 0.71 || t > 1.48 && t < 1.56 ? "blink" : "happy", t >= B.turn) {
        m.expr = t < B.turn + 0.95 ? "alert" : t > 3.12 && t < 3.2 ? "blink" : "happy";
        let jump = hop(t, B.turn + 0.05, 0.5);
        m.lift = 70 * jump;
        let stretch = t < B.turn + 0.3 ? bump(t, B.turn + 0.02, 0.36) : 0, squash = wobble(t, B.turn + 0.55, { amp: 0.14, freq: 3, decay: 6 });
        m.sx = 1 - stretch * 0.12 + squash * 0.7, m.sy = 1 + stretch * 0.18 - squash, m.rot = wobble(t, B.turn + 0.05, { amp: -6, freq: 2.2, decay: 4 }), m.k = seg(t, B.turn + 0.06, B.turn + 0.52, ease.inOut2), m.bang = t < B.turn + 1.1 ? spring(t, B.turn + 0.1, { zeta: 0.4, freq: 3 }) * (1 - seg(t, B.turn + 0.95, B.turn + 1.1)) : 0, m.silhouette = impact;
      }
      let fl = t >= B.turn ? 1 - seg(t, B.turn + 0.1, B.turn + 0.65, ease.in2) : 0;
      if (focusLines(bctx, 960, 470, 300, AMBER, 0.5 * fl, 100 + Math.floor(t * 12)), sparks(fctx, 960, 470, t, B.turn + 0.07, [255, 205, 120], { n: 26, speed: 900, seed: 5 }), inA) {
        let z = (tt) => 0.83 * zipZ(tt, B.barZip), sweepF = (tt) => seg(tt, B.turn + 0.08, B.turn + 0.42, ease.outExpo), sw = sweepF(t), v = t < B.turn ? speed(z, t) / 1.6 : speed(sweepF, t) / 4, out = seg(t, 3.22, 3.46, ease.in3), headX = barA.pose({ z: z(t), color: "green", v, glint: (t - 1.02) / 0.42, sweepK: sw, sweepColor: "amber", opacity: 1 - out, ty: out * 60 });
        sparkle(fctx, headX, 844, 46 * bump(t, 0.98, 0.5), 1, t * 2), sparks(fctx, headX, 844, t, 0.4, [190, 255, 140], { n: 10, speed: 380, seed: 9, dir: Math.PI, spread: 1.2, dur: 0.6 });
        let rowIn = seg(t, 0.8, 1.15, ease.out3);
        labelA.style.transform = `translate(210px, ${750 + (1 - rowIn) * 20 + out * 60}px)`, labelA.style.opacity = rowIn * (1 - out), labelA.style.filter = `blur(${(1 - rowIn) * 8}px)`;
        let roll = seg(t, B.clockRoll, B.clockRoll + 0.3, ease.inOut2), mins = Math.round(lerp(176, 33, roll));
        valueAClk.textContent = mins >= 60 ? `${Math.floor(mins / 60)}h ${mins % 60}m` : `${mins}m`, valueAReset.style.color = t >= B.clockRoll + 0.3 ? "#f0a32a" : "rgba(255,255,255,.55)", valueA.style.transform = `translate(${1710 - valueA.offsetWidth}px, ${750 + (1 - rowIn) * 20 + out * 60}px) scale(${1 + 0.06 * bump(t, B.clockRoll + 0.25, 0.25)})`, valueA.style.transformOrigin = "100% 50%", valueA.style.opacity = rowIn * (1 - out), valueA.style.filter = `blur(${(1 - rowIn) * 8}px)`;
      }
      if (show(titleA.root, inA), inA) {
        let w12 = titleA.lefts[1] + titleA.widths[1], shift = seg(t, B.resetsSoon - 0.06, B.resetsSoon + 0.3, ease.outExpo), x0 = lerp(W / 2 - w12 / 2, W / 2 - titleA.width / 2, shift);
        titleA.root.style.transform = `translate(${x0}px, 86px)`, wordIn(titleA.spans[0], t, 0.42, "blur"), wordIn(titleA.spans[1], t, 0.5, "blur"), wordIn(titleA.spans[2], t, B.resetsSoon, "slam"), wordIn(titleA.spans[3], t, B.resetsSoon + 0.08, "slam"), wordsOut(titleA.spans, t, 3.2);
      }
      if (t >= 3.3) {
        let mv = seg(t, 3.3, 3.85, ease.inOut3);
        m.x = 960, m.ground = lerp(672, 790, mv), m.h = lerp(390, 480, mv), m.k = 1, m.from = "amber", m.to = "amber";
        let b1 = hop(t, 3.95, 0.3), b2 = hop(t, 4.3, 0.3);
        m.lift = 34 * (b1 + b2);
        let sq = wobble(t, 4.25, { amp: 0.06, freq: 3.5, decay: 7 }) + wobble(t, 4.6, { amp: 0.06, freq: 3.5, decay: 7 });
        m.sx = 1 + sq * 0.7, m.sy = 1 - sq, m.rot = 0, m.expr = t > 4.78 && t < 4.86 ? "blink" : t > 3.9 && t < 4.7 ? "joy" : "happy", m.bang = 0;
      }
      if (rays(bctx, 960, 560, AMBER, 0.07 * seg(t, 3.35, 3.9) * (1 - seg(t, 5.3, 5.6)), t * 0.12), animateTitle(titleB, t, { t0: B.youPaid, t1: 5.18, kind: "blur", y: 96 }), t >= B.jumpPrep) {
        let prep = bump(t, B.jumpPrep, 0.2), f = seg(t, B.jump, B.glyphLand, ease.inOut2), p0 = [960, 790], p1 = [1380, 420], p2 = [GLYPH_PT * MB_S, 52], bx = (1 - f) ** 2 * p0[0] + 2 * (1 - f) * f * p1[0] + f * f * p2[0], by = (1 - f) ** 2 * p0[1] + 2 * (1 - f) * f * p1[1] + f * f * p2[1];
        m.x = bx, m.ground = by, m.lift = 0, m.h = lerp(480, 40, ease.inOut2(f)), m.sx = 1 + prep * 0.14 - bump(t, B.jump, 0.5) * 0.12, m.sy = 1 - prep * 0.2 + bump(t, B.jump, 0.5) * 0.22, m.rot = 18 * bump(t, B.jump, 0.5), m.expr = t < B.jump + 0.3 ? "joy" : "happy", m.shadowOpacity = 1 - f, m.visible = t < B.glyphLand;
      }
      animateTitle(titleC, t, { t0: 6.06, t1: 6.6, kind: "blur", stagger: 0.05, y: 330 });
    } else
      show(titleA.root, !1);
    let mbIn = seg(t, 5.55, 5.9, ease.outExpo) * (1 - seg(t, 8.36, 8.66, ease.in3));
    show(menubar, mbIn > 1e-3 && t < 9), menubar.style.transform = `translate(0px, ${(1 - mbIn) * -70}px) scale(${MB_S})`;
    let glyphPop = t < B.glyphLand ? 0 : spring(t, B.glyphLand, { zeta: 0.38, freq: 2.6 });
    mbGlyph.style.transform = `scale(${glyphPop * (1 - 0.15 * bump(t, B.click, 0.12))})`, mbHL.style.cssText = `left:${GLYPH_PT - 15}px;width:30px;opacity:${t > B.click ? 1 : 0}`, burst(fctx, GLYPH_PT * MB_S, 29, t, B.glyphLand, AMBER, { n: 9, r0: 34, r1: 110, width: 5 });
    let inD = t >= B.panelOpen - 0.02 && t < 13;
    if (show(sceneD, inD), inD) {
      let pose = keys(t, [
        [B.panelOpen, P_OPEN],
        [B.swing1, P_OPEN],
        [B.swing1 + 0.6, P_PUNCH, ease.inOut4],
        [9.86, P_PUNCH2, ease.inOut2],
        [10.26, P_CARD, ease.inOut4],
        [B.swing2, P_CARD],
        [B.swing2 + 0.62, P_ANGLE, ease.inOut4],
        [12.62, [P_ANGLE[0] - 30, ...P_ANGLE.slice(1, 6), P_ANGLE[6] + 3], ease.inOut2]
      ]), [cx, cy, fx, fy, s, rx, ry] = pose, whip = seg(t, B.whip, B.whip + 0.2, ease.inExpo);
      panelStage.style.perspectiveOrigin = `${cx}px ${cy}px`, panelCam.style.transform = `translate3d(${cx - whip * 2300}px, ${cy}px, 0) rotateX(${rx}deg) rotateY(${ry}deg) scale(${s}) translate(${-fx}px, ${-fy}px)`, sceneD.style.filter = whip > 0 ? `blur(${whip * 16}px)` : "";
      let unfold = spring(t, B.panelOpen, { zeta: 0.62, freq: 1.45 });
      panel.root.style.transform = `rotateX(${(1 - unfold) * -92}deg)`, panel.root.style.opacity = clamp(seg(t, B.panelOpen, B.panelOpen + 0.12) * 1.2);
      let zc = (tt) => zipZ(tt, B.zipClaude), zx = (tt) => zipZ(tt, B.zipCodex), z1 = (tt) => zipZ(tt, B.expand + 0.16), z2 = (tt) => zipZ(tt, B.expand + 0.27), geo = panel.layout({
        expand: { claude: spring(t, B.expand, { zeta: 0.74, freq: 1.7 }) },
        appear: {
          header: seg(t, B.panelOpen + 0.02, B.panelOpen + 0.3, ease.out3),
          card0: seg(t, B.panelOpen + 0.06, B.panelOpen + 0.36, ease.out3),
          card1: seg(t, B.panelOpen + 0.11, B.panelOpen + 0.42, ease.out3)
        },
        chevronPress: { claude: bump(t, B.chevronClick - 0.03, 0.14) },
        zip: {
          "claude-0": [zc(t), speed(zc, t) / 2.4, (t - B.glint) / 0.4],
          "claude-1": [z1(t), speed(z1, t) / 2.4, -1],
          "claude-2": [z2(t), speed(z2, t) / 2.4, -1],
          "codex-0": [zx(t), speed(zx, t) / 2.4, -1]
        }
      }), headRect = panel.cards[0].rows[0].bar.fill.getBoundingClientRect(), vp = document.getElementById("viewport").getBoundingClientRect(), sc = vp.width / W, hx = (headRect.right - vp.left) / sc, hy = (headRect.top + headRect.height / 2 - vp.top) / sc;
      sparkle(fctx, hx - 6, hy, 64 * bump(t, B.glint + 0.3, 0.45), 1, t * 2, [255, 236, 190]), sparkle(fctx, hx - 6, hy, 30 * bump(t, B.zipClaude + 0.45, 0.4), 1, t * 2, [255, 236, 190]);
      let chevEl = panel.cards[0].chevron.getBoundingClientRect(), chev = [(chevEl.left + chevEl.width / 2 - vp.left) / sc, (chevEl.top + chevEl.height / 2 - vp.top) / sc], cIn = seg(t, 9.92, 10.3, ease.outExpo), cOut = seg(t, 10.62, 10.95, ease.in3), cpos = [lerp(lerp(1500, chev[0], cIn), 1700, cOut), lerp(lerp(1100, chev[1], cIn), 1150, cOut)];
      if (cursorPose(t > 9.9 && t < 10.95, cpos, bump(t, B.chevronClick - 0.04, 0.14)), t >= 6.9 && t < 9.9) {
        let away = seg(t, 6.92, 7.3, ease.in2);
        cursorPose(away < 1, [lerp(GLYPH_PT * MB_S + 6, 1760, away), lerp(34, 420, away)], 0);
      }
      let la = t < B.legAmber ? 0 : spring(t, B.legAmber, { zeta: 0.5, freq: 2.2 }), lg = t < B.legGreen ? 0 : spring(t, B.legGreen, { zeta: 0.5, freq: 2.2 }), lOut = whip;
      show(legend, t > B.legAmber), legAmber.style.transform = `translate(${1180 - lOut * 2300}px, 330px) scale(${la})`, legAmber.style.opacity = clamp(la * 2), legGreen.style.transform = `translate(${1180 - lOut * 2300}px, 560px) scale(${lg})`, legGreen.style.opacity = clamp(lg * 2), legAmber.style.transformOrigin = legGreen.style.transformOrigin = "60px 66px";
    }
    if (t >= B.click - 0.6 && t < 6.9) {
      let cin = seg(t, 6.18, 6.66, ease.outExpo);
      cursorPose(!0, [lerp(1720, GLYPH_PT * MB_S + 6, cin), lerp(1150, 34, cin)], bump(t, B.click - 0.04, 0.14));
    } else t >= 6.9 && t < 10.95 || cursorPose(!1);
    if (t > B.whip && t < B.whip + 0.42) {
      let k = bump(t, B.whip, 0.42), R = rng(77 + Math.floor(t * 30));
      for (let i = 0; i < 26; i++) {
        fctx.fillStyle = `rgba(255,255,255,${(0.15 + R() * 0.4) * k})`;
        let y = R() * H, len = 300 + R() * 900;
        fctx.fillRect(R() * W - len / 2, y, len, 1 + R() * 3);
      }
    }
    let inE = t >= B.whip + 0.08 && t < 18.6;
    if (show(sceneE, inE), inE) {
      let enter = seg(t, B.whip + 0.12, B.whip + 0.34, ease.outExpo);
      sceneE.style.transform = `translateX(${(1 - enter) * 1800}px)`, sceneE.style.filter = enter < 1 ? `blur(${(1 - enter) * 14}px)` : "";
      let fall = seg(t, B.finale, B.finale + 0.4, ease.in3), d1 = seg(t, B.card1 + 0.12, B.card1 + 0.8, ease.inOut2), d2 = seg(t, B.card2 + 0.12, B.card2 + 0.7, ease.inOut2), d3 = seg(t, B.card3 + 0.12, B.card3 + 0.72, ease.inOut2), level = (tt) => {
        let a = seg(tt, B.card1 + 0.12, B.card1 + 0.8, ease.inOut2), b2 = seg(tt, B.card2 + 0.12, B.card2 + 0.7, ease.inOut2), c = seg(tt, B.card3 + 0.12, B.card3 + 0.72, ease.inOut2);
        return 0.83 - 0.28 * a - 0.27 * b2 - 0.24 * c;
      }, refill = (tt) => tt < B.reset ? 0 : spring(tt, B.reset, { zeta: 0.85, freq: 1.1 }), reset = t >= B.reset, z = reset ? Math.min(1, lerp(0.04, 1, refill(t))) : level(t), v = reset ? speed(refill, t) / 1.4 : speed(level, t) / 1.2, headX = barE.pose({ z, color: reset ? "green" : "amber", v, glint: (t - (B.reset + 0.75)) / 0.45, opacity: 1 - fall, ty: fall * 500 });
      sparkle(fctx, headX - 8, 523, 52 * bump(t, B.reset + 0.6, 0.5), 1, t * 2, [210, 255, 170]);
      let pct = Math.round(z * 100);
      valueEPct.textContent = `${pct}% left`;
      let mins = reset ? null : Math.max(1, Math.round(33 - 10 * d1 - 11 * d2 - 11 * d3));
      valueEReset.textContent = reset ? "resets in 4h" : `resets in ${mins}m`, valueEReset.style.color = reset ? "rgba(255,255,255,.55)" : "#f0a32a";
      let rowIn = seg(t, B.whip + 0.2, B.whip + 0.5, ease.out3);
      labelE.style.transform = `translate(260px, ${578 + fall * 500}px)`, labelE.style.opacity = rowIn * (1 - fall), valueE.style.transform = `translate(${1660 - valueE.offsetWidth}px, ${574 + fall * 500}px)`, valueE.style.opacity = rowIn * (1 - fall);
      let slams = [B.card1, B.card2, B.card3], drains = [[B.card1 + 0.05, B.card1 + 0.85], [B.card2 + 0.05, B.card2 + 0.75], [B.card3 + 0.05, B.card3 + 0.78]];
      if (taskEls.forEach((tk, i) => {
        let t0 = slams[i], k = t < t0 ? 0 : spring(t, t0, { zeta: 0.55, freq: 2.1 }), a = seg(t, t0, t0 + 0.1), fl = seg(t, B.finale + i * 0.05, B.finale + 0.4 + i * 0.05, ease.in3);
        show(tk.el, t >= t0), tk.el.style.opacity = a, tk.el.style.transform = `translateY(${fl * 520}px) scale(${lerp(1.5, 1, k)}) rotate(${lerp(i % 2 ? 7 : -7, 0, k) + fl * (i - 1) * 8}deg)`, tk.el.style.filter = k < 0.6 ? `blur(${(1 - k / 0.6) * 10}px)` : "";
        let done = seg(t, B.reset + 0.1 + i * 0.08, B.reset + 0.5 + i * 0.08, ease.out3), work = seg(t, drains[i][0] + 0.3, drains[i][1] + 1.6, ease.inOut2);
        tk.prog.style.width = `${lerp(work * 70, 100, done)}%`, tk.prog.style.background = done > 0 ? "linear-gradient(90deg,#3fa512,#8be24e)" : "", done > 0.5 ? (tk.chip.textContent = "Done", tk.chip.style.color = "#5fd11f", tk.chip.style.background = "rgba(95,209,31,.14)", tk.chip.style.boxShadow = "inset 0 0 0 2px rgba(95,209,31,.35)") : (tk.chip.textContent = TASKS[i].chip, tk.chip.style.cssText = ""), burst(fctx, tk.x + 220, 768, t, t0 + 0.04, [255, 255, 255], { n: 12, r0: 230, r1: 330, width: 6, seed: 20 + i });
        let [s0, s1] = drains[i], sk = (t - s0) / (s1 - s0);
        if (sk > 0 && sk < 1.25) {
          let hxNow = barE.headX(level(t)), p = `M ${hxNow - 10} 546 C ${hxNow - 10} 640, ${tk.x + 220} 600, ${tk.x + 220} 682`;
          tk.path.setAttribute("d", p), tk.path.setAttribute("stroke", "#f0a32a"), tk.path.setAttribute("stroke-width", `${10 * (1 - clamp((sk - 1) * 4))}`), tk.path.setAttribute("stroke-dasharray", "26 18"), tk.path.setAttribute("stroke-dashoffset", `${-t * 240}`), tk.path.setAttribute("opacity", `${clamp(sk * 6) * (1 - clamp((sk - 1) * 4))}`), tk.path.style.filter = "drop-shadow(0 0 10px rgba(240,163,42,.8))";
        } else tk.path.setAttribute("opacity", "0");
      }), t < B.finale) {
        let hx = barE.headX(z);
        m.x = clamp(hx - 40, 380, 1600), m.ground = 500, m.h = 180, m.k = 1, m.lift = 0, m.from = "amber", m.to = "amber";
        let moving = clamp(v * 1.4);
        m.lift = 26 * Math.abs(Math.sin(t * 15)) * moving, m.expr = t > 13.9 && t < 13.98 || t > 15.95 && t < 16.03 ? "blink" : "happy", reset && (m.from = "amber", m.to = "green", m.k = seg(t, B.reset + 0.05, B.reset + 0.45, ease.inOut2), m.expr = "joy", m.lift = 90 * hop(t, B.reset + 0.05, 0.6) + 20 * moving);
        let ent = seg(t, B.whip + 0.3, B.whip + 0.6, ease.outBack);
        m.sx = m.sy = ent;
      }
      animateTitle(titleE1, t, { t0: B.strongest, t1: 14.48, kind: "blur", y: 120 }), animateTitle(titleE2, t, { t0: B.another, t1: 16.22, kind: "slam", stagger: 0.09, y: 120 }), animateTitle(titleE3, t, { t0: B.nothingWasted, t1: 17.85, kind: "slam", stagger: 0.1, y: 120 });
    }
    let inF = t >= B.finale;
    if (show(sceneF, inF), inF) {
      m.from = "green", m.to = "green", m.k = 0;
      let f = seg(t, B.finale + 0.05, B.mascotLand, ease.linear), start = [clamp(barE.headX(1) - 40, 380, 1600), 500, 180];
      m.x = lerp(start[0], 960, ease.inOut2(f)), m.ground = lerp(start[1], 800, ease.in2(f)), m.h = lerp(start[2], 430, ease.out2(f)), m.lift = 260 * Math.sin(Math.PI * f) * (1 - f * 0.4), m.rot = -14 * bump(t, B.finale + 0.05, B.mascotLand - B.finale);
      let sq = wobble(t, B.mascotLand, { amp: 0.16, freq: 3, decay: 6 });
      m.sx = 1 + sq * 0.7, m.sy = 1 - sq, m.expr = t < 19.3 ? "joy" : t > 19.55 && t < 19.63 || t > 21.7 && t < 21.78 ? "blink" : "happy", focusLines(bctx, 960, 560, 320, GREEN, 0.4 * (1 - seg(t, B.mascotLand + 0.05, B.mascotLand + 0.6, ease.in2)) * (t > B.mascotLand ? 1 : 0), 300 + Math.floor(t * 12)), rays(bctx, 960, 600, GREEN, 0.075 * seg(t, B.mascotLand, B.mascotLand + 0.5) * (1 - seg(t, B.lockup, B.lockup + 0.4)), t * 0.12), animateTitle(titleF, t, { t0: B.dontWaste, t1: 19.62, kind: "blur", y: 110 });
      let lk = seg(t, B.lockup, B.lockup + 0.5, ease.inOut3), wmW = wordmark.offsetWidth, mH = 380, mW = mH * MASCOT_ASPECT, gap = 56, total = mW + gap + wmW, left = W / 2 - total / 2;
      if (t >= B.lockup) {
        m.x = lerp(960, left + mW / 2, lk), m.ground = lerp(800, 740, lk), m.h = lerp(430, mH, lk), m.lift = 70 * hop(t, B.endHop, 0.42);
        let sq2 = wobble(t, B.endHop + 0.42, { amp: 0.1, freq: 3.2, decay: 7 }) - 0.1 * bump(t, B.endHop - 0.12, 0.14);
        m.sx = 1 + sq2 * 0.7, m.sy = 1 - sq2, m.rot = 0;
      }
      let wipe = seg(t, B.wordmarkIn, B.wordmarkIn + 0.55, ease.outExpo), wmX = left + mW + gap;
      wordmark.style.transform = `translate(${wmX - (1 - wipe) * 60}px, 440px)`, wordmark.style.clipPath = `inset(-20% ${(1 - wipe) * 100}% -20% 0)`, wordmark.style.opacity = wipe > 0 ? 1 : 0;
      let u = seg(t, B.wordmarkIn + 0.32, B.wordmarkIn + 0.7, ease.out3);
      url.style.transform = `translate(${wmX + 6}px, ${626 + (1 - u) * 14}px)`, url.style.opacity = u, url.style.filter = `blur(${(1 - u) * 8}px)`, sparkle(fctx, wmX + wmW - 10, 452, 40 * bump(t, B.wordmarkIn + 0.45, 0.55), 1, t * 2, [210, 255, 170]);
    }
    t >= B.glyphLand && t < B.whip + 0.08 && (m.visible = !1), mascot.pose(m);
  }
  function cursorPose(on, p = [0, 0], press = 0) {
    show(cursor, on), on && (cursor.style.transform = `translate(${p[0] - 6}px, ${p[1] - 4}px) scale(${1 - press * 0.16})`);
  }
  var params = new URLSearchParams(location.search), capture = params.has("capture"), ready = (async () => {
    await document.fonts.ready, await Promise.all([...document.images].map((i) => i.complete ? null : new Promise((r) => {
      i.onload = i.onerror = r;
    }))), [titleA, titleB, titleC, titleE1, titleE2, titleE3, titleF].forEach((T) => T.measure()), render(+(params.get("t") || 0));
  })();
  window.__film = { render, ready, duration: DURATION, beats: BEATS };
  if (!capture) {
    document.body.classList.add("preview");
    let vpEl = document.getElementById("viewport"), fit = () => {
      let s = Math.min((window.innerWidth - 32) / W, (window.innerHeight - 96) / H);
      vpEl.style.transform = `scale(${s})`, vpEl.style.width = `${W}px`, vpEl.parentElement.style.width = `${W * s}px`, document.body.style.setProperty("--s", s), vpEl.style.marginBottom = `${H * s - H}px`, vpEl.style.marginRight = `${W * s - W}px`;
    };
    fit(), window.addEventListener("resize", fit);
    let audio = document.getElementById("soundtrack"), scrub = document.getElementById("scrub"), time = document.getElementById("time"), btn = document.getElementById("play"), mute = document.getElementById("mute");
    scrub.max = DURATION;
    let playing = !1, t0 = 0, start = 0, cur = 0, draw = (t) => {
      cur = t, render(t), scrub.value = t, time.textContent = `${t.toFixed(2)} s`;
    }, tick = (now) => {
      if (!playing) return;
      let t = audio.paused || !isFinite(audio.currentTime) || audio.error ? t0 + (now - start) / 1e3 : audio.currentTime;
      if (t >= DURATION) {
        playing = !1, btn.textContent = "Replay", audio.pause(), draw(DURATION - 1e-3);
        return;
      }
      draw(t), requestAnimationFrame(tick);
    };
    btn.onclick = () => {
      if (playing) {
        playing = !1, audio.pause(), btn.textContent = "Play";
        return;
      }
      cur >= DURATION - 0.05 && (cur = 0), playing = !0, btn.textContent = "Pause", t0 = cur, start = performance.now();
      try {
        audio.currentTime = cur, audio.muted = mute.checked, audio.play().catch(() => {
        });
      } catch {
      }
      requestAnimationFrame(tick);
    }, mute.onchange = () => {
      audio.muted = mute.checked;
    }, scrub.oninput = () => {
      playing && (playing = !1, audio.pause(), btn.textContent = "Play"), draw(+scrub.value);
    }, window.addEventListener("keydown", (e) => {
      e.code === "Space" && (e.preventDefault(), btn.onclick());
    });
  }
})();
