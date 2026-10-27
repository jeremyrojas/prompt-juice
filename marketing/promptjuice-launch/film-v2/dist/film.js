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

  // logo/option-1.svg
  var option_1_default = `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 1920 1080" width="1920" height="1080">
  <title>PromptJuice \u2014 Juice Level</title>
  <desc>End card option 1: mascot above a wordmark whose 'Juice' letters are glasses filled with juice; the i's dot is the app droplet.</desc>
  <style>
    .pj-anim { transform-box: fill-box; transform-origin: 50% 100%; }
    .pj-pivot { transform-box: view-box; }
    .pj-center { transform-box: fill-box; transform-origin: 50% 50%; }
  </style>
  <defs>
    <linearGradient id="amber-grad" gradientUnits="userSpaceOnUse" x1="0" y1="796.4" x2="0" y2="830.9">
      <stop offset="0" stop-color="#FFC15E"/><stop offset="0.55" stop-color="#F0A32A"/><stop offset="1" stop-color="#D9880F"/>
    </linearGradient>
    <linearGradient id="juice-grad" gradientUnits="userSpaceOnUse" x1="0" y1="624.6" x2="0" y2="729.2">
      <stop offset="0" stop-color="#8BE24E"/>
      <stop offset="0.5" stop-color="#5FD11F"/>
      <stop offset="1" stop-color="#3FA512"/>
    </linearGradient>
    <linearGradient id="drop-grad" gradientUnits="userSpaceOnUse" x1="0" y1="549.8" x2="0" y2="609.8">
      <stop offset="0" stop-color="#8BE24E"/>
      <stop offset="0.5" stop-color="#5FD11F"/>
      <stop offset="1" stop-color="#3FA512"/>
    </linearGradient>
    <radialGradient id="glow-mascot" gradientUnits="userSpaceOnUse" cx="960" cy="383.5" r="420" gradientTransform="translate(960 383.5) scale(1 0.9) translate(-960 -383.5)">
      <stop offset="0" stop-color="#5FD11F" stop-opacity="0.2"/>
      <stop offset="0.55" stop-color="#5FD11F" stop-opacity="0.070"/>
      <stop offset="1" stop-color="#5FD11F" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="glow-floor" gradientUnits="userSpaceOnUse" cx="960" cy="662.8" r="760" gradientTransform="translate(960 662.8) scale(1 0.2) translate(-960 -662.8)">
      <stop offset="0" stop-color="#5FD11F" stop-opacity="0.07"/>
      <stop offset="0.55" stop-color="#5FD11F" stop-opacity="0.025"/>
      <stop offset="1" stop-color="#5FD11F" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="vignette" gradientUnits="userSpaceOnUse" cx="960" cy="540" r="1150">
      <stop offset="0.55" stop-color="#000" stop-opacity="0"/>
      <stop offset="1" stop-color="#000" stop-opacity="0.55"/>
    </radialGradient>
    <clipPath id="juice-clip">
      <use id="jc-J" href="#gl-J"/>
      <use id="jc-u" href="#gl-u"/>
      <use id="jc-i" href="#gl-i"/>
      <use id="jc-c" href="#gl-c"/>
      <use id="jc-e" href="#gl-e"/>
    </clipPath>
  </defs>
  <g id="bg">
    <rect width="1920" height="1080" fill="#07080b"/>
    <rect id="glow" width="1920" height="1080" fill="url(#glow-mascot)"/>
    <rect width="1920" height="1080" fill="url(#glow-floor)"/>
    <rect width="1920" height="1080" fill="url(#vignette)"/>
  </g>
  <g id="lockup">
    <g id="mascot" class="pj-pivot" style="transform-origin: 960px 548.1px">
      <image id="mascot-img" href="../assets/img/mascot-green-happy.png" x="823.6" y="186" width="272.8" height="392" preserveAspectRatio="xMidYMax meet"/>
    </g>
    <g id="wordmark">
      <g id="word-prompt" fill="#ffffff">
      <g id="l-P" class="pj-pivot" style="transform-origin: 445.4px 719.2px"><path id="gl-P" d="M389.3 719.2H419.5V666.1H456.4Q471.9 666.1 483.1 660.5Q494.4 654.9 500.7 645Q506.9 635 506.9 621.8Q506.9 608.7 500.8 598.9Q494.6 589.1 483.3 583.6Q472.1 578.1 456.4 578.1H389.3ZM419.5 643V601.2H454.8Q465.2 601.2 471 606.9Q476.8 612.6 476.8 622Q476.8 631.4 471 637.2Q465.2 643 454.8 643H419.5Z"/></g>
      <g id="l-r" class="pj-pivot" style="transform-origin: 547.1px 719.2px"><path id="gl-r" d="M520.7 719.2H550.1V667.1Q550.1 654.9 556.7 650Q563.4 645 577.5 645Q580.1 645 581.8 645.1Q583.6 645.1 584.6 645.5V618.1Q582.8 617.3 579.1 617.3Q567.1 617.3 559.1 624Q553 629 549.5 637.6V619.3H520.7Z"/></g>
      <g id="l-o" class="pj-pivot" style="transform-origin: 642.2px 719.2px"><path id="gl-o" d="M642.2 721.2Q658.7 721.2 671.1 714.6Q683.5 708.1 690.5 696.2Q697.5 684.3 697.5 668.9Q697.5 653.4 690.6 641.8Q683.7 630.3 671.3 623.8Q658.8 617.3 642.2 617.3Q625.7 617.3 613.3 623.8Q600.8 630.3 593.9 641.8Q586.9 653.4 586.9 668.9Q586.9 684.3 593.9 696.2Q600.8 708.1 613.3 714.6Q625.7 721.2 642.2 721.2ZM642.2 698.1Q635.3 698.1 629.7 694.5Q624.2 691 620.8 684.4Q617.5 677.9 617.5 668.7Q617.5 655.3 624.6 647.9Q631.8 640.4 642.2 640.4Q652.6 640.4 659.7 647.8Q666.9 655.1 666.9 668.7Q666.9 677.9 663.6 684.4Q660.2 691 654.6 694.5Q649 698.1 642.2 698.1Z"/></g>
      <g id="l-m" class="pj-pivot" style="transform-origin: 792.1px 719.2px"><path id="gl-m" d="M710.8 719.2H740.2V664Q740.2 656.9 743.1 651.7Q746.1 646.5 751.3 643.7Q756.5 640.8 762.7 640.8Q770 640.8 774 644.5Q778 648.1 778 655.7V719.2H807.4V664Q807.4 656.9 810.4 651.7Q813.3 646.5 818.5 643.7Q823.7 640.8 830 640.8Q837.2 640.8 841.2 644.5Q845.2 648.1 845.2 655.7V719.2H874.6V650.2Q874.6 635.5 865.9 626.4Q857.2 617.3 840.9 617.3Q827.2 617.3 817.5 623.9Q810 628.9 805.4 636.6Q803.3 630.7 798.7 626.1Q790 617.3 774.3 617.3Q761.2 617.3 751.8 623.9Q744.3 629.2 739.6 637.5V619.3H710.8Z"/></g>
      <g id="l-p" class="pj-pivot" style="transform-origin: 943px 719.2px"><path id="gl-p" d="M955.6 721.2Q969.5 721.2 979.7 714.7Q989.9 708.3 995.6 696.5Q1001.3 684.7 1001.3 668.9Q1001.3 653.2 995.9 641.6Q990.5 630.1 980.6 623.7Q970.7 617.3 957.2 617.3Q943 617.3 933.4 623.7Q926.5 628.3 923.4 635.3V619.3H894.6V759.4H924V702.8Q926.6 709.9 932.7 714.5Q941.3 721.2 955.6 721.2ZM947.4 697.7Q936.8 697.7 930.2 690.3Q923.6 683 923.6 669.3Q923.6 655.5 930.2 648.2Q936.8 640.8 947 640.8Q957.6 640.8 964.1 648.1Q970.7 655.3 970.7 669.1Q970.7 682.8 964.2 690.2Q957.7 697.7 947.4 697.7Z"/></g>
      <g id="l-t" class="pj-pivot" style="transform-origin: 1042.3px 719.2px"><path id="gl-t" d="M1060.1 721.4Q1065.7 721.4 1070.3 720.6Q1075 719.8 1077.5 718.5V696.1Q1075 696.9 1072.4 697.5Q1069.9 698.1 1066.9 698.1Q1059.1 698.1 1055.4 694.7Q1051.6 691.4 1051.6 684.7V641.6H1077.5V619.3H1051.6V586L1022.2 596.9V619.3H1003.6V641.6H1022.2V683.8Q1022.2 702.8 1031.5 712.1Q1040.9 721.4 1060.1 721.4Z"/></g>
      </g>
      <g id="word-juice">
        <!-- empty "glass": the letter shapes, faintly tinted, with a thin rim -->
        <g id="juice-vessel" fill="#5FD11F" fill-opacity="0.17" stroke="#8BE24E" stroke-opacity="0.55" stroke-width="2">
        <g id="l-J" class="pj-pivot" style="transform-origin: 1120.7px 719.2px"><path id="gl-J" d="M1107.7 721.2Q1129.8 721.2 1141.4 711.5Q1153 701.8 1153 682.2V578.1H1122.8V680.8Q1122.8 690.4 1117.8 694.1Q1112.8 697.7 1101.8 697.7Q1096.7 697.7 1091.8 696.7Q1086.9 695.7 1083.4 694.3V717.5Q1086.5 719 1093.4 720.1Q1100.2 721.2 1107.7 721.2Z"/></g>
        <g id="l-u" class="pj-pivot" style="transform-origin: 1215.3px 719.2px"><path id="gl-u" d="M1201.8 721.2Q1215.1 721.2 1224.5 714.5Q1232.2 709.1 1236.9 700.9V719.2H1265.7V619.3H1236.3V673Q1236.3 680.2 1233.2 685.8Q1230.2 691.4 1225.1 694.5Q1220 697.7 1213.3 697.7Q1205.9 697.7 1201.8 693.6Q1197.7 689.4 1197.7 681.2V619.3H1168.3V686.9Q1168.3 696.5 1172.2 704.2Q1176.1 712 1183.6 716.6Q1191.2 721.2 1201.8 721.2Z"/></g>
        <g id="l-i" class="pj-pivot" style="transform-origin: 1296.8px 719.2px"><path id="gl-i" d="M1282.3 719.2H1311.7V619.3H1282.3Z"/></g>
        <g id="l-c" class="pj-pivot" style="transform-origin: 1375.5px 719.2px"><path id="gl-c" d="M1377.8 721.2Q1390.9 721.2 1401.4 716.4Q1411.9 711.6 1418.6 703.2Q1425.4 694.7 1427.4 683.4H1398.9Q1396.8 690.6 1391.2 694.3Q1385.6 698.1 1378.2 698.1Q1371.1 698.1 1365.9 694.5Q1360.7 691 1358 684.5Q1355.2 678.1 1355.2 669.3Q1355.2 660.4 1358 654Q1360.7 647.5 1365.9 644Q1371.1 640.4 1378.2 640.4Q1385.6 640.4 1391.2 644.2Q1396.8 647.9 1398.9 655.1H1427.4Q1425.4 643.8 1418.6 635.3Q1411.9 626.9 1401.4 622.1Q1390.9 617.3 1377.8 617.3Q1362.1 617.3 1350.1 624Q1338.2 630.6 1331.4 642.4Q1324.7 654.2 1324.7 669.3Q1324.7 684.3 1331.4 696.1Q1338.2 707.9 1350.1 714.5Q1362.1 721.2 1377.8 721.2Z"/></g>
        <g id="l-e" class="pj-pivot" style="transform-origin: 1484.2px 719.2px"><path id="gl-e" d="M1486.8 721.2Q1505.4 721.2 1517.2 712.9Q1529.1 704.5 1534 690H1506.4Q1503.8 695.3 1498.7 697.7Q1493.6 700 1486.6 700Q1473.8 700 1467.4 692.6Q1462.9 687.3 1461.6 678.1H1535.8Q1536.1 675.7 1536.3 673.1Q1536.5 670.4 1536.5 667.3Q1536.5 652.2 1530.3 641Q1524 629.9 1512.6 623.6Q1501.3 617.3 1485.8 617.3Q1469.7 617.3 1457.5 623.9Q1445.4 630.4 1438.6 642.1Q1431.9 653.8 1431.9 669.3Q1431.9 684.5 1438.6 696.3Q1445.4 708.1 1457.7 714.6Q1470.1 721.2 1486.8 721.2ZM1462.1 658.7Q1463.6 651.1 1467.4 646.3Q1473.8 638.5 1485.4 638.5Q1495.4 638.5 1501.2 644.3Q1506.1 649.2 1506.8 658.7H1462.1Z"/></g>
        </g>
        <!-- the juice: translate #juice-level on y to fill/drain, slide #juice-wave on x to slosh -->
        <g id="juice-fill" clip-path="url(#juice-clip)">
          <g id="juice-level">
            <g id="juice-wave">
              <path id="juice-body" d="M821.4 759.2L821.4 634.6C847.7 623.9 868.1 623.9 894.4 634.6C920.7 645.2 941.1 645.2 967.4 634.6C993.7 623.9 1014.1 623.9 1040.4 634.6C1066.7 645.2 1087.1 645.2 1113.4 634.6C1139.7 623.9 1160.1 623.9 1186.4 634.6C1212.7 645.2 1233.1 645.2 1259.4 634.6C1285.7 623.9 1306.1 623.9 1332.4 634.6C1358.7 645.2 1379.1 645.2 1405.4 634.6C1431.7 623.9 1452.1 623.9 1478.4 634.6C1504.7 645.2 1525.1 645.2 1551.4 634.6C1577.7 623.9 1598.1 623.9 1624.4 634.6L1624.4 759.2Z" fill="url(#juice-grad)"/>
              <path id="juice-meniscus" d="M821.4 634.6C847.7 623.9 868.1 623.9 894.4 634.6C920.7 645.2 941.1 645.2 967.4 634.6C993.7 623.9 1014.1 623.9 1040.4 634.6C1066.7 645.2 1087.1 645.2 1113.4 634.6C1139.7 623.9 1160.1 623.9 1186.4 634.6C1212.7 645.2 1233.1 645.2 1259.4 634.6C1285.7 623.9 1306.1 623.9 1332.4 634.6C1358.7 645.2 1379.1 645.2 1405.4 634.6C1431.7 623.9 1452.1 623.9 1478.4 634.6C1504.7 645.2 1525.1 645.2 1551.4 634.6C1577.7 623.9 1598.1 623.9 1624.4 634.6" fill="none" stroke="#D4FF9E" stroke-opacity="0.9" stroke-width="3.5"/>
            </g>
            <g id="juice-bubbles" fill="#ffffff" fill-opacity="0.32"><circle cx="1181.4" cy="668.6" r="7"/><circle cx="1244.8" cy="692.6" r="4.5"/><circle cx="1377.1" cy="664.6" r="5.5"/><circle cx="1479.7" cy="690.6" r="4"/></g>
          </g>
        </g>
      </g>
      <g id="droplet-dot" class="pj-anim"><path d="M1297 549.8C1297 549.8 1276.4 574.5 1276.4 588.3C1276.4 599.8 1285.6 607.1 1297 607.1C1308.5 607.1 1317.6 599.8 1317.6 588.3C1317.6 574.5 1297 549.8 1297 549.8Z" fill="url(#drop-grad)"/></g>
    </g>
    <g id="tagline" class="pj-center">
      <path id="tagline-use" d="M809.9 831.4Q817 831.4 820.6 827.4Q824.2 823.4 824.2 816V796.4H818V817Q818 821.7 815.9 824Q813.7 826.3 810 826.3Q806.2 826.3 804 824Q801.9 821.7 801.9 816.9V796.4H795.7V816Q795.7 823.4 799.3 827.4Q802.9 831.4 809.9 831.4ZM838.8 831.4Q843.6 831.4 846.3 829.5Q849 827.6 849 824.1Q849 821.3 847.2 819.3Q845.3 817.3 841.7 816.5L837.5 815.5Q835.6 815 834.8 814.4Q834 813.7 834 812.8Q834 811.5 835 810.9Q836.1 810.2 838.1 810.2Q840.3 810.2 841.6 811Q842.9 811.8 843.1 813.3H848.6Q848.4 809.8 845.6 807.9Q842.8 806 838.3 806Q833.7 806 831 807.9Q828.4 809.8 828.4 813.3Q828.4 816 830.4 817.9Q832.3 819.7 836.4 820.6L840.3 821.5Q842.2 821.9 842.8 822.6Q843.5 823.2 843.5 824.2Q843.5 825.6 842.3 826.4Q841.2 827.1 838.8 827.1Q836.2 827.1 834.7 826.2Q833.1 825.2 832.9 823.3H827.4Q827.7 827.1 830.7 829.3Q833.7 831.4 838.8 831.4ZM864.7 831.4Q869 831.4 871.9 829.4Q874.8 827.4 876 823.9H870.2Q869.6 825.4 868.1 826.1Q866.7 826.8 864.8 826.8Q861.5 826.8 859.7 824.8Q858.3 823.2 858 820.5H876.4Q876.5 819.9 876.6 819.4Q876.6 818.8 876.6 818.1Q876.6 814.5 875.1 811.7Q873.6 809 871 807.5Q868.3 806 864.6 806Q860.8 806 857.9 807.6Q855 809.2 853.4 812Q851.8 814.9 851.8 818.6Q851.8 822.4 853.4 825.3Q855 828.1 857.9 829.8Q860.8 831.4 864.7 831.4ZM858.1 816.3Q858.5 814 859.7 812.6Q861.5 810.5 864.5 810.5Q867.4 810.5 868.9 812.2Q870.3 813.7 870.5 816.3H858.1ZM889.8 830.9H895.9V806.4H889.8ZM889.5 802.4H896.1V795.7H889.5ZM912.7 831.4Q914 831.4 915.1 831.2Q916.1 831.1 916.7 830.8V826.1Q916.1 826.3 915.5 826.4Q914.8 826.5 914 826.5Q912 826.5 911 825.6Q910 824.8 910 823V811.2H916.7V806.4H910V798.6L903.9 800.9V806.4H899.2V811.2H903.9V822.9Q903.9 827.1 906.1 829.3Q908.2 831.4 912.7 831.4ZM941 831.4Q944.9 831.4 947.9 829.8Q950.8 828.1 952.4 825.2Q954.1 822.3 954.1 818.6Q954.1 814.8 952.5 812Q950.8 809.2 947.9 807.6Q945 806 941 806Q937.2 806 934.2 807.6Q931.2 809.2 929.6 812Q928 814.8 928 818.6Q928 822.3 929.6 825.2Q931.2 828.1 934.2 829.8Q937.2 831.4 941 831.4ZM941 826.6Q939.1 826.6 937.6 825.6Q936 824.6 935.2 822.8Q934.3 821 934.3 818.5Q934.3 814.9 936.2 812.9Q938.1 810.8 941 810.8Q944 810.8 945.9 812.9Q947.8 814.9 947.8 818.5Q947.8 821 946.9 822.8Q946 824.6 944.5 825.6Q943 826.6 941 826.6ZM958.3 830.9H964.3V818.2Q964.3 814.8 966 813.3Q967.8 811.7 971.3 811.7Q971.9 811.7 972.3 811.7Q972.8 811.8 973 811.9V806.2Q972.6 806 971.6 806Q968.7 806 966.6 807.6Q965.1 808.8 964.2 810.9V806.4H958.3Z" fill="#ffffff" fill-opacity="0.9"/>
      <path id="tagline-lose" d="M985.7 830.9H991.7V796.4H985.7ZM1009 831.4Q1012.9 831.4 1015.8 829.8Q1018.8 828.1 1020.4 825.2Q1022.1 822.3 1022.1 818.6Q1022.1 814.8 1020.4 812Q1018.8 809.2 1015.9 807.6Q1012.9 806 1009 806Q1005.1 806 1002.2 807.6Q999.2 809.2 997.6 812Q996 814.8 996 818.6Q996 822.3 997.6 825.2Q999.2 828.1 1002.2 829.8Q1005.1 831.4 1009 831.4ZM1009 826.6Q1007 826.6 1005.5 825.6Q1004 824.6 1003.1 822.8Q1002.2 821 1002.2 818.5Q1002.2 814.9 1004.2 812.9Q1006.1 810.8 1009 810.8Q1011.9 810.8 1013.8 812.9Q1015.7 814.9 1015.7 818.5Q1015.7 821 1014.9 822.8Q1014 824.6 1012.5 825.6Q1010.9 826.6 1009 826.6ZM1035.7 831.4Q1040.5 831.4 1043.2 829.5Q1045.9 827.6 1045.9 824.1Q1045.9 821.3 1044.1 819.3Q1042.2 817.3 1038.6 816.5L1034.4 815.5Q1032.5 815 1031.7 814.4Q1030.8 813.7 1030.8 812.8Q1030.8 811.5 1031.9 810.9Q1033 810.2 1035 810.2Q1037.2 810.2 1038.5 811Q1039.8 811.8 1040 813.3H1045.5Q1045.2 809.8 1042.5 807.9Q1039.7 806 1035.2 806Q1030.6 806 1027.9 807.9Q1025.3 809.8 1025.3 813.3Q1025.3 816 1027.3 817.9Q1029.2 819.7 1033.2 820.6L1037.2 821.5Q1039.1 821.9 1039.7 822.6Q1040.4 823.2 1040.4 824.2Q1040.4 825.6 1039.2 826.4Q1038 827.1 1035.7 827.1Q1033.1 827.1 1031.6 826.2Q1030 825.2 1029.8 823.3H1024.3Q1024.6 827.1 1027.6 829.3Q1030.6 831.4 1035.7 831.4ZM1061.6 831.4Q1065.9 831.4 1068.8 829.4Q1071.6 827.4 1072.8 823.9H1067.1Q1066.5 825.4 1065 826.1Q1063.6 826.8 1061.7 826.8Q1058.4 826.8 1056.6 824.8Q1055.2 823.2 1054.9 820.5H1073.3Q1073.4 819.9 1073.5 819.4Q1073.5 818.8 1073.5 818.1Q1073.5 814.5 1072 811.7Q1070.5 809 1067.9 807.5Q1065.2 806 1061.5 806Q1057.7 806 1054.8 807.6Q1051.9 809.2 1050.3 812Q1048.7 814.9 1048.7 818.6Q1048.7 822.4 1050.3 825.3Q1051.9 828.1 1054.8 829.8Q1057.7 831.4 1061.6 831.4ZM1055 816.3Q1055.4 814 1056.6 812.6Q1058.4 810.5 1061.4 810.5Q1064.3 810.5 1065.8 812.2Q1067.1 813.7 1067.4 816.3H1055ZM1086.7 830.9H1092.8V806.4H1086.7ZM1086.4 802.4H1093V795.7H1086.4ZM1109.6 831.4Q1110.9 831.4 1112 831.2Q1113 831.1 1113.6 830.8V826.1Q1113 826.3 1112.4 826.4Q1111.7 826.5 1110.9 826.5Q1108.8 826.5 1107.9 825.6Q1106.9 824.8 1106.9 823V811.2H1113.6V806.4H1106.9V798.6L1100.8 800.9V806.4H1096.1V811.2H1100.8V822.9Q1100.8 827.1 1103 829.3Q1105.1 831.4 1109.6 831.4ZM1116.9 830.9H1123.8V824H1116.9Z" fill="url(#amber-grad)"/>
    </g>
    <g id="oss-pill" class="pj-center">
      <rect id="oss-pill-bg" x="808.9" y="864.9" width="302.2" height="42" rx="21.0" fill="#ffffff" fill-opacity="0.04" stroke="#ffffff" stroke-opacity="0.15" stroke-width="1.5"/>
      <path id="oss-pill-icon" d="M833 877.4C833 877.4 826.9 884.7 826.9 888.8C826.9 892.2 829.6 894.4 833 894.4C836.4 894.4 839.1 892.2 839.1 888.8C839.1 884.7 833 877.4 833 877.4Z" fill="#5FD11F"/>
      <path id="oss-pill-text" d="M849.4 893.5H852.1V887.4H859.2V885.2H852.1V880.5H859.7V878.4H849.4ZM862.1 893.5H864.8V887.9Q864.8 886.4 865.5 885.8Q866.3 885.1 867.8 885.1Q868.1 885.1 868.3 885.1Q868.4 885.1 868.6 885.1V882.6Q868.4 882.6 867.9 882.6Q866.7 882.6 865.8 883.3Q865.1 883.8 864.7 884.7V882.8H862.1ZM875 893.7Q876.9 893.7 878.1 892.8Q879.4 891.9 879.9 890.4H877.4Q877.1 891.1 876.5 891.4Q875.9 891.7 875 891.7Q873.6 891.7 872.8 890.8Q872.2 890.1 872 888.9H880.1Q880.2 888.7 880.2 888.4Q880.2 888.2 880.2 887.9Q880.2 886.3 879.6 885.1Q878.9 883.9 877.7 883.2Q876.6 882.6 875 882.6Q873.3 882.6 872 883.3Q870.8 884 870.1 885.2Q869.3 886.5 869.3 888.1Q869.3 889.7 870.1 891Q870.8 892.3 872 893Q873.3 893.7 875 893.7ZM872.1 887.1Q872.3 886.1 872.8 885.5Q873.6 884.6 874.9 884.6Q876.2 884.6 876.8 885.3Q877.4 885.9 877.5 887.1H872.1ZM887.3 893.7Q889.2 893.7 890.4 892.8Q891.7 891.9 892.2 890.4H889.7Q889.4 891.1 888.8 891.4Q888.1 891.7 887.3 891.7Q885.8 891.7 885 890.8Q884.4 890.1 884.3 888.9H892.4Q892.4 888.7 892.4 888.4Q892.5 888.2 892.5 887.9Q892.5 886.3 891.8 885.1Q891.2 883.9 890 883.2Q888.8 882.6 887.2 882.6Q885.5 882.6 884.3 883.3Q883 884 882.3 885.2Q881.6 886.5 881.6 888.1Q881.6 889.7 882.3 891Q883 892.3 884.3 893Q885.6 893.7 887.3 893.7ZM884.3 887.1Q884.5 886.1 885 885.5Q885.8 884.6 887.2 884.6Q888.4 884.6 889.1 885.3Q889.7 885.9 889.8 887.1H884.3ZM909.8 893.5H913.2L910.3 890.6Q910.4 890.5 910.4 890.4Q911.1 889.4 911.5 888.1Q911.9 886.8 911.9 885.3H909.4Q909.4 887 909 888.1Q908.8 888.5 908.6 888.9L905.4 885.5Q906.7 884.9 907.5 884.1Q908.5 883 908.5 881.7Q908.5 880.6 907.9 879.8Q907.4 879 906.4 878.6Q905.4 878.2 904.3 878.2Q903 878.2 902.1 878.6Q901.1 879.1 900.6 879.9Q900.1 880.6 900.1 881.6Q900.1 882.2 900.2 882.7Q900.4 883.3 900.8 883.8Q901.1 884.3 901.5 884.8Q900 885.4 899.1 886.3Q897.9 887.5 897.9 889.2Q897.9 890.6 898.7 891.6Q899.4 892.6 900.7 893.1Q902 893.7 903.8 893.7Q905.2 893.7 906.4 893.3Q907.6 892.9 908.6 892.2ZM902.9 886.3 907.1 890.6Q906.6 891 906.1 891.1Q905.1 891.5 904 891.5Q902.4 891.5 901.5 890.8Q900.6 890.2 900.6 889Q900.6 888.3 900.9 887.8Q901.2 887.2 901.9 886.8Q902.4 886.5 902.9 886.3ZM903.9 884Q903.6 883.6 903.3 883.3Q902.9 882.7 902.7 882.4Q902.6 882 902.6 881.6Q902.6 881 903 880.5Q903.5 880 904.3 880Q905.1 880 905.6 880.5Q906.1 881 906.1 881.7Q906.1 882.5 905.5 883.1Q904.9 883.7 903.9 884ZM924.1 893.7Q925.8 893.7 927 893Q928.3 892.3 929 891Q929.8 889.7 929.8 888.1Q929.8 886.4 929.1 885.2Q928.3 884 927.1 883.3Q925.8 882.6 924.1 882.6Q922.4 882.6 921.1 883.3Q919.8 884 919.1 885.2Q918.3 886.4 918.3 888.1Q918.3 889.7 919.1 891Q919.8 892.3 921.1 893Q922.4 893.7 924.1 893.7ZM924.1 891.6Q923.2 891.6 922.5 891.1Q921.9 890.7 921.5 889.9Q921.1 889.1 921.1 888.1Q921.1 886.5 921.9 885.6Q922.8 884.7 924.1 884.7Q925.3 884.7 926.2 885.6Q927 886.5 927 888.1Q927 889.1 926.6 889.9Q926.2 890.7 925.6 891.1Q924.9 891.6 924.1 891.6ZM938 893.7Q939.4 893.7 940.5 893Q941.6 892.3 942.2 891Q942.8 889.8 942.8 888.1Q942.8 886.4 942.3 885.2Q941.7 883.9 940.6 883.2Q939.6 882.6 938.1 882.6Q936.6 882.6 935.6 883.3Q934.8 883.8 934.4 884.5V882.8H931.8V897.8H934.5V891.7Q934.8 892.5 935.5 893Q936.4 893.7 938 893.7ZM937.3 891.5Q936 891.5 935.2 890.6Q934.4 889.7 934.4 888.1Q934.4 886.5 935.2 885.6Q936 884.7 937.3 884.7Q938.5 884.7 939.3 885.6Q940.1 886.5 940.1 888.1Q940.1 889.7 939.3 890.6Q938.6 891.5 937.3 891.5ZM950 893.7Q951.9 893.7 953.1 892.8Q954.4 891.9 954.9 890.4H952.4Q952.1 891.1 951.5 891.4Q950.8 891.7 950 891.7Q948.5 891.7 947.8 890.8Q947.2 890.1 947 888.9H955.1Q955.1 888.7 955.2 888.4Q955.2 888.2 955.2 887.9Q955.2 886.3 954.5 885.1Q953.9 883.9 952.7 883.2Q951.5 882.6 949.9 882.6Q948.2 882.6 947 883.3Q945.7 884 945 885.2Q944.3 886.5 944.3 888.1Q944.3 889.7 945 891Q945.7 892.3 947 893Q948.3 893.7 950 893.7ZM947.1 887.1Q947.2 886.1 947.8 885.5Q948.5 884.6 949.9 884.6Q951.1 884.6 951.8 885.3Q952.4 885.9 952.5 887.1H947.1ZM957.3 893.5H959.9V887.7Q959.9 886.8 960.3 886.2Q960.7 885.5 961.3 885.1Q962 884.7 962.8 884.7Q963.8 884.7 964.3 885.2Q964.8 885.7 964.8 886.7V893.5H967.5V886.2Q967.5 884.5 966.5 883.5Q965.5 882.6 963.8 882.6Q962.3 882.6 961.2 883.3Q960.4 883.8 959.9 884.7V882.8H957.3ZM978.5 893.7Q980.6 893.7 981.8 892.9Q983 892 983 890.5Q983 889.3 982.2 888.4Q981.4 887.5 979.8 887.2L978 886.7Q977.1 886.5 976.8 886.2Q976.4 886 976.4 885.5Q976.4 885 976.9 884.7Q977.3 884.4 978.2 884.4Q979.2 884.4 979.8 884.8Q980.3 885.1 980.4 885.8H982.8Q982.7 884.3 981.5 883.4Q980.3 882.6 978.3 882.6Q976.3 882.6 975.1 883.4Q974 884.3 974 885.8Q974 887 974.8 887.8Q975.7 888.6 977.5 889L979.2 889.4Q980 889.6 980.3 889.8Q980.6 890.1 980.6 890.6Q980.6 891.2 980.1 891.5Q979.6 891.8 978.5 891.8Q977.4 891.8 976.7 891.4Q976.1 891 975.9 890.2H973.5Q973.7 891.8 975 892.8Q976.3 893.7 978.5 893.7ZM990.2 893.7Q991.9 893.7 993.1 893Q994.4 892.3 995.1 891Q995.9 889.7 995.9 888.1Q995.9 886.4 995.2 885.2Q994.4 884 993.2 883.3Q991.9 882.6 990.2 882.6Q988.5 882.6 987.2 883.3Q985.9 884 985.2 885.2Q984.5 886.4 984.5 888.1Q984.5 889.7 985.2 891Q985.9 892.3 987.2 893Q988.5 893.7 990.2 893.7ZM990.2 891.6Q989.3 891.6 988.6 891.1Q988 890.7 987.6 889.9Q987.2 889.1 987.2 888.1Q987.2 886.5 988 885.6Q988.9 884.7 990.2 884.7Q991.4 884.7 992.3 885.6Q993.1 886.5 993.1 888.1Q993.1 889.1 992.7 889.9Q992.3 890.7 991.7 891.1Q991 891.6 990.2 891.6ZM1001.4 893.7Q1002.8 893.7 1003.9 893Q1004.7 892.4 1005.2 891.5V893.5H1007.8V882.8H1005.2V888.5Q1005.2 889.4 1004.8 890.1Q1004.4 890.8 1003.8 891.1Q1003.2 891.5 1002.4 891.5Q1001.5 891.5 1001 891Q1000.5 890.5 1000.5 889.5V882.8H997.8V890.1Q997.8 891.1 998.3 891.9Q998.7 892.7 999.5 893.2Q1000.3 893.7 1001.4 893.7ZM1010.8 893.5H1013.4V887.9Q1013.4 886.4 1014.2 885.8Q1014.9 885.1 1016.5 885.1Q1016.7 885.1 1016.9 885.1Q1017.1 885.1 1017.2 885.1V882.6Q1017 882.6 1016.6 882.6Q1015.3 882.6 1014.4 883.3Q1013.7 883.8 1013.3 884.7V882.8H1010.8ZM1023.5 893.7Q1024.8 893.7 1025.9 893.2Q1026.9 892.7 1027.6 891.8Q1028.3 890.9 1028.5 889.7H1026Q1025.8 890.6 1025.1 891.1Q1024.5 891.6 1023.5 891.6Q1022.7 891.6 1022.1 891.1Q1021.4 890.7 1021.1 889.9Q1020.8 889.2 1020.8 888.1Q1020.8 887.1 1021.1 886.3Q1021.4 885.5 1022.1 885.1Q1022.7 884.7 1023.5 884.7Q1024.5 884.7 1025.1 885.2Q1025.8 885.6 1026 886.5H1028.5Q1028.3 885.3 1027.6 884.4Q1027 883.5 1025.9 883.1Q1024.8 882.6 1023.5 882.6Q1021.9 882.6 1020.6 883.3Q1019.4 884 1018.7 885.2Q1018 886.5 1018 888.1Q1018 889.7 1018.7 891Q1019.4 892.3 1020.6 893Q1021.9 893.7 1023.5 893.7ZM1035.3 893.7Q1037.2 893.7 1038.5 892.8Q1039.7 891.9 1040.2 890.4H1037.7Q1037.4 891.1 1036.8 891.4Q1036.2 891.7 1035.3 891.7Q1033.9 891.7 1033.1 890.8Q1032.5 890.1 1032.4 888.9H1040.4Q1040.5 888.7 1040.5 888.4Q1040.5 888.2 1040.5 887.9Q1040.5 886.3 1039.9 885.1Q1039.2 883.9 1038 883.2Q1036.9 882.6 1035.3 882.6Q1033.6 882.6 1032.3 883.3Q1031.1 884 1030.4 885.2Q1029.7 886.5 1029.7 888.1Q1029.7 889.7 1030.4 891Q1031.1 892.3 1032.3 893Q1033.6 893.7 1035.3 893.7ZM1032.4 887.1Q1032.6 886.1 1033.1 885.5Q1033.9 884.6 1035.2 884.6Q1036.5 884.6 1037.2 885.3Q1037.7 885.9 1037.8 887.1H1032.4ZM1045.4 887.1H1048.4V884.1H1045.4ZM1054 893.5H1056.6V880.7L1060.6 893.5H1063.5L1067.6 880.7V893.5H1070.3V878.4H1066L1062.1 890.6L1058.3 878.4H1054ZM1073 893.5H1075.7V878.4H1073ZM1082.8 893.5H1085.5V880.5H1090.5V878.4H1077.8V880.5H1082.8Z" fill="#ffffff" fill-opacity="0.62"/>
    </g>
  </g>
</svg>
`;

  // src/main.js
  var DURATION = 25.9, W = 1920, H = 1080, GREEN = [95, 209, 31], AMBER = [240, 163, 42], MASCOT_ASPECT = 776 / 1115, film = document.getElementById("film");
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
  var fadeOut = el2("div", "layer");
  fadeOut.style.background = "#000";
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
          let len = s.len * vv * 0.75;
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
    show(T.root, on), on && (T.measure(), placeTitle(T, cx, y), T.spans.forEach((s, i) => wordIn(s, t, t0 + i * stagger, kind)), wordsOut(T.spans, t, t1));
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
  var sceneA = el2("div", "layer", world), sceneD = el2("div", "layer", world), sceneE = el2("div", "layer", world), sceneF = el2("div", "layer", world), mascotLayer = el2("div", "layer", world), rowA = el2("div", "layer", sceneA), barA = createBigBar(rowA, { x: 210, y: 822, w: 1500, h: 44 }), labelA = el2("div", "caption", rowA, "5-hour limit");
  labelA.style.cssText += "color: rgba(255,255,255,.55); font-weight: 500;";
  var valueA = el2("div", "caption", rowA, '<span class="pct">83% left</span><span style="color:rgba(255,255,255,.3)"> \xB7 </span><span class="reset">resets in <span class="clk">2h 56m</span></span>'), valueAReset = valueA.querySelector(".reset"), valueAClk = valueA.querySelector(".clk"), titleA = createTitle(sceneA, [["Plenty"], ["of"], ["juice"], ["left."], ["Resets", "amber"], ["soon.", "amber"]], { size: 96 }), titleB1 = createTitle(sceneA, [["You"], ["paid"], ["for"], ["the"], ["juice.", "amber"]], { size: 104 }), titleB2 = createTitle(sceneA, [["Don\u2019t"], ["waste"], ["it."]], { size: 76 }), MB_S = 2.4, menubar = el2("div", "", world);
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
  }), legend = el2("div", "layer", sceneD), legClaude = el2("div", "legend", legend, '<img src="assets/img/mascot-amber-happy.png"><div><span class="who"><i style="background:var(--claude)"></i>Claude</span><span style="color:var(--amber)">Resets soon.</span></div>'), legCodex = el2("div", "legend", legend, '<img src="assets/img/mascot-green-happy.png"><div><span class="who"><i style="background:var(--codex)"></i>Codex</span><span style="color:var(--green)">Plenty left.</span></div>'), streamSvg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  streamSvg.id = "stream";
  streamSvg.setAttribute("width", W);
  streamSvg.setAttribute("height", H);
  sceneE.appendChild(streamSvg);
  var rowE = el2("div", "layer", sceneE), barE = createBigBar(rowE, { x: 260, y: 540, w: 1400, h: 46 }), labelE = el2("div", "caption", rowE, 'Claude <span style="color:rgba(255,255,255,.3)">\xB7</span> 5-hour limit');
  labelE.style.cssText += "color: rgba(255,255,255,.62); font-weight: 500; font-size: 46px; text-shadow: 0 0 14px #07080b, 0 0 6px #07080b;";
  var valueE = el2("div", "caption", rowE, '<span class="pct">83% left</span><span style="color:rgba(255,255,255,.3)"> \xB7 </span><span class="reset" style="color:var(--amber)">resets in 33m</span>');
  valueE.style.textShadow = "0 0 14px #07080b, 0 0 6px #07080b";
  var valueEPct = valueE.querySelector(".pct"), valueEReset = valueE.querySelector(".reset"), TASKS = [
    { what: "Plan the big refactor", chip: "Strongest model" },
    { what: "Fix the memory leak", chip: "Higher effort" },
    { what: "Write the test suite", chip: "New task" }
  ], taskEls = TASKS.map((tk, i) => {
    let c = el2("div", "task", sceneE, `<div class="who"><i></i>Claude</div><div class="what">${tk.what}</div><div class="chip">${tk.chip}</div><div class="prog"><b></b></div>`);
    c.style.left = `${260 + i * 480}px`, c.style.top = "720px";
    let path = document.createElementNS("http://www.w3.org/2000/svg", "path");
    return path.setAttribute("fill", "none"), path.setAttribute("stroke-linecap", "round"), streamSvg.appendChild(path), { drops: Array.from({ length: 4 }, () => {
      let d = document.createElementNS("http://www.w3.org/2000/svg", "circle");
      return d.setAttribute("r", "7"), d.setAttribute("fill", "#ffd27a"), d.style.filter = "drop-shadow(0 0 6px rgba(255,190,90,.9))", streamSvg.appendChild(d), d;
    }), el: c, prog: c.querySelector(".prog b"), chip: c.querySelector(".chip"), path, x: 260 + i * 480 };
  }), titleE1 = createTitle(sceneE, [["Use"], ["your"], ["strongest", "amber"], ["model.", "amber"]], { size: 100 }), titleE2 = createTitle(sceneE, [["Use"], ["higher", "amber"], ["effort.", "amber"]], { size: 100 }), titleE2b = createTitle(sceneE, [["Start"], ["another"], ["task.", "amber"]], { size: 100 }), titleE3 = createTitle(sceneE, [["Nothing", "green"], ["wasted."]], { size: 100 }), logoWrap = el2("div", "layer logo", sceneF);
  logoWrap.innerHTML = option_1_default.replace(/id="([^"]+)"/g, 'id="lg-$1"').replace(/url\(#([^)]+)\)/g, "url(#lg-$1)").replace(/href="#([^"]+)"/g, 'href="#lg-$1"').replace(/\.\.\/assets\//g, "assets/");
  var LG = (id) => logoWrap.querySelector(`#lg-${id}`);
  ["bg", "glow", "mascot"].forEach((id) => {
    let e = LG(id);
    e && (e.style.display = "none");
  });
  var PROMPT_LETTERS = ["l-P", "l-r", "l-o", "l-m", "l-p", "l-t"], LOGO_MASCOT = (() => {
    let img = LG("mascot-img"), y = +img.getAttribute("y"), h = +img.getAttribute("height"), x = +img.getAttribute("x"), w = +img.getAttribute("width");
    return { x: x + w / 2, ground: y + h * (1109 / 1115), h };
  })(), mascot = createMascot(mascotLayer), cursor = el2("div", "", world, '<svg width="46" height="68" viewBox="0 0 23 34"><path d="M1.5 1.5 L1.5 26.5 L7.6 20.8 L11.6 30.6 L15.6 29 L11.7 19.4 L20 19.4 Z" fill="#000" stroke="#fff" stroke-width="1.8" stroke-linejoin="round"/></svg>');
  cursor.id = "cursor";
  var BEATS = {
    popIn: 0,
    barZip: 0.45,
    barLand: 1.5,
    clockRoll: 1.85,
    turn: 2.4,
    resetsSoon: 2.72,
    youPaid: 4.05,
    dontWaste: 4.95,
    jumpPrep: 6.25,
    jump: 6.4,
    glyphLand: 7.05,
    click: 7.85,
    panelOpen: 7.95,
    zipClaude: 8.2,
    zipCodex: 8.34,
    swing1: 8.95,
    glint: 9.95,
    toCard: 10.65,
    chevronClick: 11.4,
    expand: 11.44,
    swing2: 12.2,
    legClaude: 12.6,
    legCodex: 12.85,
    toBar: 14.4,
    handoff: 15.3,
    strongest: 15.55,
    card1: 15.85,
    effort: 16.95,
    card2: 17.18,
    another: 18.3,
    card3: 18.53,
    reset: 19.5,
    nothingWasted: 19.8,
    finale: 21,
    mascotLand: 21.7,
    juiceRise: 22.2,
    dotLand: 22.7,
    tagline: 23.2,
    endHop: 23.95
  }, B = BEATS, P_OPEN = [960, 76, 192, 0, 2.6, 0, 0], P_PUNCH = [960, 560, 192, 104, 4.3, 6, -12], P_PUNCH2 = [960, 560, 192, 104, 4.4, 5, -8], P_CARD = [960, 150, 192, 54, 3.4, 0, 0], P_ANGLE = [640, 560, 192, 152, 2.45, 5, 20], P_ANGLE2 = [620, 560, 192, 152, 2.5, 4, 17], P_BAR = [960, 563, 192, 116, 1400 / 332, 0, 0];
  function zipZ(t, t0) {
    return spring(t, t0, { zeta: 0.82, freq: 1 });
  }
  function speed(fn, t) {
    return Math.abs(fn(t) - fn(t - 1 / 60)) * 60;
  }
  var CALM = 0.5;
  function render(t) {
    bctx.clearRect(0, 0, W, H), fctx.clearRect(0, 0, W, H);
    let amberK = seg(t, B.turn, B.turn + 0.9, ease.inOut2) * (1 - seg(t, B.reset, B.reset + 0.9, ease.inOut2)), glowC = mixC(GREEN, AMBER, amberK), glowI = keys(t, [[0, 0.3], [1, 1, ease.inOut2], [B.toBar, 1], [B.handoff + 0.3, 0.8], [B.reset, 0.85], [B.reset + 0.8, 1.05], [24.4, 1]]), glowXY = keys(t, [[0, [960, 470]], [6.3, [960, 470]], [7.35, [1340, 200], ease.inOut2], [B.click, [1340, 200]], [B.swing1 + 0.6, [960, 300], ease.inOut2], [B.toBar, [960, 300]], [B.handoff + 0.4, [960, 520]], [B.finale, [960, 520]], [B.mascotLand, [960, 500]]]);
    glow.style.background = `radial-gradient(closest-side, ${rgba(glowC, 0.34 * glowI)}, ${rgba(glowC, 0.1 * glowI)} 42%, ${rgba(glowC, 0)} 72%)`, glow.style.transform = `translate(${glowXY[0] - 960}px, ${glowXY[1] - 540}px)`;
    let dolly = 1 + 0.035 * seg(t, 0, 6.2, ease.inOut2);
    world.style.transform = t < 6.3 ? `scale(${dolly})` : "", world.style.transformOrigin = "960px 560px";
    let m = { visible: !0, x: 960, ground: 672, h: 390, from: "green", to: "amber", k: 0, expr: "happy", t }, inA = t < 3.95;
    if (show(sceneA, t < 7.9), show(rowA, inA), t < 7.9) {
      let intro = seg(t, 0, 0.9, ease.out3);
      m.opacity = 0.35 + 0.65 * seg(t, 0, 0.5), m.lift = 26 * (1 - intro);
      let settle = wobble(t, 0.62, { amp: 0.035, freq: 2.2, decay: 4 });
      if (m.sx = 1 + settle * 0.6, m.sy = 1 - settle, m.expr = t > 0.95 && t < 1.04 || t > 1.62 && t < 1.7 ? "blink" : "happy", t >= B.turn && (m.expr = t < B.turn + 1 ? "alert" : t > 3.45 && t < 3.53 ? "blink" : "happy", m.lift = 18 * bump(t, B.turn + 0.05, 0.7), m.rot = wobble(t, B.turn + 0.1, { amp: -3, freq: 1.4, decay: 3 }), m.k = seg(t, B.turn + 0.05, B.turn + 0.95, ease.inOut3)), inA) {
        let z = (tt) => 0.83 * zipZ(tt, B.barZip), sweepF = (tt) => seg(tt, B.turn + 0.1, B.turn + 0.95, ease.inOut3), sw = sweepF(t), v = CALM * (t < B.turn ? speed(z, t) / 1.2 : speed(sweepF, t) / 2.2), out = seg(t, 3.7, 4, ease.in2), headX = barA.pose({ z: z(t), color: "green", v, glint: (t - (B.barLand - 0.1)) / 0.7, sweepK: sw, sweepColor: "amber", opacity: 1 - out, ty: out * 30 });
        sparkle(fctx, headX, 844, 34 * bump(t, B.barLand - 0.05, 0.8), 0.9, t * 0.8);
        let rowIn = seg(t, 1, 1.5, ease.out3), ry = 750 + (1 - rowIn) * 16 + out * 30;
        labelA.style.transform = `translate(210px, ${ry}px)`, labelA.style.opacity = rowIn * (1 - out), labelA.style.filter = `blur(${(1 - rowIn) * 8}px)`;
        let roll = seg(t, B.clockRoll, B.clockRoll + 0.55, ease.inOut3), mins = Math.round(lerp(176, 33, roll));
        valueAClk.textContent = mins >= 60 ? `${Math.floor(mins / 60)}h ${mins % 60}m` : `${mins}m`;
        let amberText = seg(t, B.clockRoll + 0.4, B.clockRoll + 0.75);
        valueAReset.style.color = `rgba(${Math.round(lerp(255, 240, amberText))},${Math.round(lerp(255, 163, amberText))},${Math.round(lerp(255, 42, amberText))},${lerp(0.55, 1, amberText)})`, valueA.style.transform = `translate(${1710 - valueA.offsetWidth}px, ${ry}px)`, valueA.style.opacity = rowIn * (1 - out), valueA.style.filter = `blur(${(1 - rowIn) * 8}px)`;
      }
      if (show(titleA.root, inA), inA) {
        titleA.measure();
        let w4 = titleA.lefts[3] + titleA.widths[3], shift = seg(t, B.resetsSoon - 0.1, B.resetsSoon + 0.6, ease.inOut3), x0 = lerp(W / 2 - w4 / 2, W / 2 - titleA.width / 2, shift);
        titleA.root.style.transform = `translate(${x0}px, 92px)`, [0.5, 0.58, 0.66, 0.74].forEach((t0, i) => wordIn(titleA.spans[i], t, t0, "blur")), wordIn(titleA.spans[4], t, B.resetsSoon + 0.15, "blur"), wordIn(titleA.spans[5], t, B.resetsSoon + 0.25, "blur"), wordsOut(titleA.spans, t, 3.62);
      }
      if (t >= 3.85) {
        let mv = seg(t, 3.85, 4.6, ease.inOut3);
        m.x = 960, m.ground = lerp(672, 830, mv), m.h = lerp(390, 450, mv), m.k = 1, m.from = "amber", m.to = "amber", m.rot = 0, m.lift = 14 * bump(t, 4.5, 0.55);
        let sq = wobble(t, 4.95, { amp: 0.03, freq: 2.4, decay: 5 });
        m.sx = 1 + sq * 0.6, m.sy = 1 - sq, m.expr = t > 5.7 && t < 5.78 ? "blink" : t > 4.4 && t < 5.4 ? "joy" : "happy";
      }
      if (rays(bctx, 960, 620, AMBER, 0.05 * seg(t, 3.9, 4.8) * (1 - seg(t, 6, 6.5)), t * 0.06), animateTitle(titleB1, t, { t0: B.youPaid, t1: 6, kind: "blur", y: 96 }), animateTitle(titleB2, t, { t0: B.dontWaste, t1: 6.08, kind: "blur", y: 218 }), t >= B.jumpPrep) {
        let prep = bump(t, B.jumpPrep, 0.22), f = seg(t, B.jump, B.glyphLand, ease.inOut3), p0 = [960, 830], p1 = [1380, 420], p2 = [GLYPH_PT * MB_S, 52];
        m.x = (1 - f) ** 2 * p0[0] + 2 * (1 - f) * f * p1[0] + f * f * p2[0], m.ground = (1 - f) ** 2 * p0[1] + 2 * (1 - f) * f * p1[1] + f * f * p2[1], m.lift = 0, m.h = lerp(450, 40, ease.inOut2(f)), m.sx = 1 + prep * 0.08 - bump(t, B.jump, 0.6) * 0.06, m.sy = 1 - prep * 0.1 + bump(t, B.jump, 0.6) * 0.1, m.rot = 10 * bump(t, B.jump, 0.65), m.expr = "joy", m.shadowOpacity = 1 - f, m.visible = t < B.glyphLand;
      }
    } else
      show(titleA.root, !1);
    let mbIn = seg(t, 6.45, 6.9, ease.out3) * (1 - seg(t, B.swing1, B.swing1 + 0.4, ease.in2));
    show(menubar, mbIn > 1e-3 && t < B.swing1 + 0.5), menubar.style.transform = `translate(0px, ${(1 - mbIn) * -70}px) scale(${MB_S})`;
    let glyphPop = t < B.glyphLand ? 0 : spring(t, B.glyphLand, { zeta: 0.62, freq: 2 });
    mbGlyph.style.transform = `scale(${glyphPop * (1 - 0.12 * bump(t, B.click, 0.14))})`, mbHL.style.cssText = `left:${GLYPH_PT - 15}px;width:30px;opacity:${seg(t, B.click, B.click + 0.08)}`, sparkle(fctx, GLYPH_PT * MB_S + 18, 22, 22 * bump(t, B.glyphLand + 0.05, 0.5), 0.9, t);
    let inD = t >= B.panelOpen - 0.02 && t < B.handoff + 0.35;
    if (show(sceneD, inD), inD) {
      let pose = keys(t, [
        [B.panelOpen, P_OPEN],
        [B.swing1, P_OPEN],
        [B.swing1 + 0.85, P_PUNCH, ease.inOut3],
        [B.toCard, P_PUNCH2, ease.inOut2],
        [B.toCard + 0.65, P_CARD, ease.inOut3],
        [B.swing2, P_CARD],
        [B.swing2 + 0.8, P_ANGLE, ease.inOut3],
        [B.toBar, P_ANGLE2, ease.inOut2],
        [B.toBar + 0.8, P_BAR, ease.inOut3]
      ]), [cx, cy, fx, fy, s, rx, ry] = pose;
      panelStage.style.perspectiveOrigin = `${cx}px ${cy}px`, panelCam.style.transform = `translate3d(${cx}px, ${cy}px, 0) rotateX(${rx}deg) rotateY(${ry}deg) scale(${s}) translate(${-fx}px, ${-fy}px)`, sceneD.style.opacity = 1 - seg(t, B.handoff - 0.1, B.handoff + 0.25, ease.inOut2);
      let unfold = spring(t, B.panelOpen, { zeta: 0.78, freq: 1.25 });
      panel.root.style.transform = `rotateX(${(1 - unfold) * -92}deg)`, panel.root.style.opacity = clamp(seg(t, B.panelOpen, B.panelOpen + 0.15) * 1.2);
      let zc = (tt) => zipZ(tt, B.zipClaude), zx = (tt) => zipZ(tt, B.zipCodex), z1 = (tt) => zipZ(tt, B.expand + 0.2), z2 = (tt) => zipZ(tt, B.expand + 0.32);
      panel.layout({
        expand: { claude: spring(t, B.expand, { zeta: 0.86, freq: 1.4 }) },
        appear: {
          header: seg(t, B.panelOpen + 0.03, B.panelOpen + 0.4, ease.out3),
          card0: seg(t, B.panelOpen + 0.08, B.panelOpen + 0.46, ease.out3),
          card1: seg(t, B.panelOpen + 0.14, B.panelOpen + 0.52, ease.out3)
        },
        chevronPress: { claude: bump(t, B.chevronClick - 0.03, 0.16) },
        zip: {
          "claude-0": [zc(t), CALM * speed(zc, t) / 2, (t - B.glint) / 0.7],
          "claude-1": [z1(t), CALM * speed(z1, t) / 2, -1],
          "claude-2": [z2(t), CALM * speed(z2, t) / 2, -1],
          "codex-0": [zx(t), CALM * speed(zx, t) / 2, -1]
        }
      });
      let vp = document.getElementById("viewport").getBoundingClientRect(), sc = vp.width / W, headRect = panel.cards[0].rows[0].bar.fill.getBoundingClientRect(), hx = (headRect.right - vp.left) / sc, hy = (headRect.top + headRect.height / 2 - vp.top) / sc;
      sparkle(fctx, hx - 6, hy, 46 * bump(t, B.glint + 0.45, 0.7), 0.95, t * 0.8, [255, 236, 190]);
      let chevEl = panel.cards[0].chevron.getBoundingClientRect(), chev = [(chevEl.left + chevEl.width / 2 - vp.left) / sc, (chevEl.top + chevEl.height / 2 - vp.top) / sc], cIn = seg(t, B.chevronClick - 0.5, B.chevronClick - 0.06, ease.out3), cOut = seg(t, B.chevronClick + 0.3, B.chevronClick + 0.7, ease.in2);
      if (t > B.chevronClick - 0.5 && t < B.chevronClick + 0.7) cursorPose(!0, [lerp(lerp(1500, chev[0], cIn), 1720, cOut), lerp(lerp(1100, chev[1], cIn), 1160, cOut)], bump(t, B.chevronClick - 0.04, 0.16));
      else if (t >= B.click + 0.05 && t < B.click + 0.6) {
        let away = seg(t, B.click + 0.12, B.click + 0.55, ease.in2);
        cursorPose(!0, [lerp(GLYPH_PT * MB_S + 6, 1780, away), lerp(34, 460, away)], 0);
      } else cursorPose(!1);
      let lOut = seg(t, B.toBar - 0.1, B.toBar + 0.25, ease.in2);
      [[legClaude, B.legClaude, 393], [legCodex, B.legCodex, 565]].forEach(([e, t0, y]) => {
        let k = seg(t, t0, t0 + 0.55, ease.out3);
        show(e, k > 0), e.style.transform = `translate(1180px, ${y + (1 - k) * 22}px)`, e.style.opacity = k * (1 - lOut), e.style.filter = `blur(${(1 - k) * 8 + lOut * 8}px)`;
      });
    }
    if (t >= B.click - 0.65 && t < B.click + 0.05) {
      let cin = seg(t, B.click - 0.62, B.click - 0.08, ease.out3);
      cursorPose(!0, [lerp(1720, GLYPH_PT * MB_S + 6, cin), lerp(1150, 34, cin)], bump(t, B.click - 0.04, 0.16));
    } else inD || cursorPose(!1);
    let inE = t >= B.handoff - 0.08 && t < B.finale + 0.7;
    if (show(sceneE, inE), !inE) for (let layer of [mascotLayer, fxFront]) layer.style.transform = "";
    if (inE) {
      let fall = seg(t, B.finale, B.finale + 0.6, ease.inOut3), push = keys(t, [[B.handoff + 0.3, 1], [B.reset, 1.07, ease.inOut2], [B.reset + 1, 1, ease.out3]]);
      for (let layer of [sceneE, mascotLayer, fxFront])
        layer.style.transformOrigin = "960px 600px", layer.style.transform = `scale(${push})`;
      let d1 = seg(t, B.card1 + 0.15, B.card1 + 0.95, ease.inOut2), d2 = seg(t, B.card2 + 0.15, B.card2 + 0.85, ease.inOut2), d3 = seg(t, B.card3 + 0.15, B.card3 + 0.9, ease.inOut2), level = (tt) => 0.83 - 0.28 * seg(tt, B.card1 + 0.15, B.card1 + 0.95, ease.inOut2) - 0.27 * seg(tt, B.card2 + 0.15, B.card2 + 0.85, ease.inOut2) - 0.24 * seg(tt, B.card3 + 0.15, B.card3 + 0.9, ease.inOut2), refill = (tt) => tt < B.reset ? 0 : spring(tt, B.reset, { zeta: 0.86, freq: 1.15 }), reset = t >= B.reset, z = reset ? Math.min(1, lerp(0.04, 1, refill(t))) : level(t), v = CALM * (reset ? speed(refill, t) / 1.1 : speed(level, t)), thick = lerp(6 * P_BAR[4] / 46, 1, seg(t, B.handoff, B.handoff + 0.5, ease.inOut3));
      barE.root.style.transformOrigin = "50% 50%";
      let headX = barE.pose({ z, color: reset ? "green" : "amber", v, glint: (t - (B.reset + 0.9)) / 0.7, opacity: 1 - fall, ty: fall * 120 });
      barE.root.style.transform += ` scaleY(${thick})`, sparkle(fctx, headX - 8, 563, 40 * bump(t, B.reset + 0.8, 0.8), 0.95, t * 0.8, [210, 255, 170]), valueEPct.textContent = `${Math.round(z * 100)}% left`;
      let mins = Math.max(1, Math.round(33 - 10 * d1 - 11 * d2 - 11 * d3));
      valueEReset.textContent = reset ? "resets in 4h" : `resets in ${mins}m`, valueEReset.style.color = reset ? "rgba(255,255,255,.55)" : "#f0a32a";
      let rowIn = seg(t, B.handoff + 0.2, B.handoff + 0.65, ease.out3);
      labelE.style.transform = `translate(260px, ${618 + (1 - rowIn) * 14 + fall * 120}px)`, labelE.style.opacity = rowIn * (1 - fall), labelE.style.filter = `blur(${(1 - rowIn) * 8}px)`, valueE.style.transform = `translate(${1660 - valueE.offsetWidth}px, ${614 + (1 - rowIn) * 14 + fall * 120}px)`, valueE.style.opacity = rowIn * (1 - fall), valueE.style.filter = `blur(${(1 - rowIn) * 8}px)`;
      let arrivals = [B.card1, B.card2, B.card3], drains = [[B.card1 + 0.08, B.card1 + 1], [B.card2 + 0.08, B.card2 + 0.9], [B.card3 + 0.08, B.card3 + 0.95]];
      if (taskEls.forEach((tk, i) => {
        let t0 = arrivals[i];
        fitTaskTitle(tk);
        let k = seg(t, t0, t0 + 0.6, ease.out4), fl = seg(t, B.finale + i * 0.06, B.finale + 0.55 + i * 0.06, ease.inOut3);
        show(tk.el, t >= t0), tk.el.style.opacity = k * (1 - fl), tk.el.style.transform = `translateY(${(1 - k) * 36 + fl * 90}px)`, tk.el.style.filter = k < 1 ? `blur(${(1 - k) * 10}px)` : "";
        let done = seg(t, B.reset + 0.2 + i * 0.12, B.reset + 0.7 + i * 0.12, ease.out3), work = seg(t, drains[i][0] + 0.3, drains[i][1] + 1.6, ease.inOut2);
        tk.prog.style.width = `${lerp(work * 70, 100, done)}%`;
        let p = (t * 0.9 + i * 0.3) % 1 * 140 - 20;
        tk.prog.style.background = done > 0 ? "linear-gradient(90deg,#3fa512,#8be24e)" : work > 0 && work < 1 ? `linear-gradient(90deg, #d9880f 0%, #f0a32a ${p - 18}%, #fff1cf ${p}%, #f0a32a ${p + 18}%, #ffc15e 100%)` : "", done > 0.5 ? (tk.chip.textContent = "Done", tk.chip.style.color = "#5fd11f", tk.chip.style.background = "rgba(95,209,31,.14)", tk.chip.style.boxShadow = "inset 0 0 0 2px rgba(95,209,31,.35)") : (tk.chip.textContent = TASKS[i].chip, tk.chip.style.cssText = "");
        let [s0, s1] = drains[i], sk = (t - s0) / (s1 - s0);
        if (sk > 0 && sk < 1.25) {
          let hxNow = barE.headX(level(t));
          tk.path.setAttribute("d", `M ${hxNow - 10} 586 C ${hxNow - 10} 680, ${tk.x + 220} 640, ${tk.x + 220} 722`), tk.path.setAttribute("stroke", "#f0a32a"), tk.path.setAttribute("stroke-width", `${9 * (1 - clamp((sk - 1) * 4))}`), tk.path.setAttribute("stroke-dasharray", "22 16"), tk.path.setAttribute("stroke-dashoffset", `${-t * 160}`);
          let sv = clamp(sk * 5) * (1 - clamp((sk - 1) * 4));
          tk.path.setAttribute("opacity", `${sv}`), tk.path.style.filter = "drop-shadow(0 0 10px rgba(240,163,42,.85))";
          let len = tk.path.getTotalLength();
          tk.drops.forEach((d, j) => {
            let u = ((t - s0) * 1.4 + j / 4) % 1, pt = tk.path.getPointAtLength(len * u);
            d.setAttribute("cx", pt.x), d.setAttribute("cy", pt.y), d.setAttribute("opacity", `${sv * Math.sin(Math.PI * u) * (sk < 1 ? 1 : 0)}`);
          });
        } else
          tk.path.setAttribute("opacity", "0"), tk.drops.forEach((d) => d.setAttribute("opacity", "0"));
      }), t < B.finale) {
        let hx = barE.headX(z), appear = seg(t, B.handoff + 0.25, B.handoff + 0.8, ease.out3);
        m.x = clamp(hx - 40, 380, 1600), m.ground = 540, m.h = 180, m.from = "amber", m.to = "amber", m.k = 1, m.rot = 0, m.opacity = appear;
        let moving = clamp(v * 2);
        m.lift = 26 * (1 - appear) + 7 * Math.abs(Math.sin(t * 9)) * moving, m.expr = t > 16.6 && t < 16.68 || t > 18.9 && t < 18.98 ? "blink" : "happy", reset && (m.to = "green", m.k = seg(t, B.reset + 0.1, B.reset + 0.9, ease.inOut3), m.expr = "joy", m.lift = 40 * bump(t, B.reset + 0.1, 0.7) + 6 * moving);
      }
      animateTitle(titleE1, t, { t0: B.strongest, t1: B.effort - 0.2, kind: "blur", y: 120 }), animateTitle(titleE2, t, { t0: B.effort, t1: B.another - 0.2, kind: "blur", stagger: 0.09, y: 120 }), animateTitle(titleE2b, t, { t0: B.another, t1: B.reset - 0.15, kind: "blur", stagger: 0.09, y: 120 }), animateTitle(titleE3, t, { t0: B.nothingWasted, t1: B.finale - 0.15, kind: "blur", stagger: 0.1, y: 120 });
    }
    let inF = t >= B.finale;
    if (show(sceneF, inF), inF) {
      let target = [LOGO_MASCOT.x, LOGO_MASCOT.ground, LOGO_MASCOT.h], start = [clamp(barE.headX(1) - 40, 380, 1600), 540, 180], f = seg(t, B.finale + 0.1, B.mascotLand, ease.inOut2);
      m.from = "green", m.to = "green", m.k = 0, m.x = lerp(start[0], target[0], f), m.ground = lerp(start[1], target[1], f), m.h = lerp(start[2], target[2], ease.out2(f)), m.lift = 150 * Math.sin(Math.PI * f) + 36 * hop(t, B.endHop, 0.5), m.rot = -8 * bump(t, B.finale + 0.1, B.mascotLand - B.finale - 0.1);
      let sq = wobble(t, B.mascotLand, { amp: 0.06, freq: 2.4, decay: 5 }) + wobble(t, B.endHop + 0.5, { amp: 0.04, freq: 2.6, decay: 6 });
      m.sx = 1 + sq * 0.6, m.sy = 1 - sq, m.expr = t < B.mascotLand + 0.7 ? "joy" : t > 24.2 && t < 24.28 || t > 25.15 && t < 25.23 ? "blink" : t > B.endHop - 0.1 && t < B.endHop + 0.7 ? "joy" : "happy", m.shadowOpacity = 0.8, PROMPT_LETTERS.forEach((id, i) => {
        let k = seg(t, B.mascotLand + 0.02 + i * 0.05, B.mascotLand + 0.5 + i * 0.05, ease.out3), e = LG(id);
        e.style.transform = `translateY(${(1 - k) * 46}px)`, e.style.opacity = k, e.style.filter = k < 1 ? `blur(${(1 - k) * 10}px)` : "";
      });
      let vessel = seg(t, B.mascotLand + 0.25, B.mascotLand + 0.6, ease.out3);
      LG("word-juice").style.opacity = vessel;
      let fill = t < B.juiceRise ? 0 : spring(t, B.juiceRise, { zeta: 0.55, freq: 1.3 });
      LG("juice-level").style.transform = `translateY(${92 * (1 - fill)}px)`, LG("juice-wave").style.transform = `translateX(${t * 0.9 % 1 * 146}px)`, LG("juice-bubbles").style.transform = `translateY(${-10 * seg(t, B.juiceRise, B.juiceRise + 2.5)}px)`, LG("juice-bubbles").style.opacity = seg(t, B.juiceRise + 0.3, B.juiceRise + 0.7);
      let fallK = seg(t, B.dotLand - 0.42, B.dotLand, ease.in2), squash = wobble(t, B.dotLand, { amp: 0.28, freq: 3.2, decay: 7 }), dot = LG("droplet-dot");
      dot.style.opacity = t < B.dotLand - 0.42 ? 0 : 1, dot.style.transform = `translateY(${-300 * (1 - fallK)}px) scale(${1 + squash * 0.7}, ${1 - squash})`;
      let tg = seg(t, B.tagline, B.tagline + 0.5, ease.out3);
      LG("tagline").style.opacity = tg, LG("tagline").style.transform = `translateY(${(1 - tg) * 16}px)`, LG("tagline").style.filter = tg < 1 ? `blur(${(1 - tg) * 8}px)` : "";
      let pill = seg(t, B.tagline + 0.35, B.tagline + 0.85, ease.out3);
      LG("oss-pill").style.opacity = pill, LG("oss-pill").style.transform = `translateY(${12 + (1 - pill) * 14}px) scale(1.5)`;
    }
    t >= B.glyphLand && t < B.handoff && (m.visible = !1), fadeOut.style.opacity = seg(t, DURATION - 0.55, DURATION - 0.02, ease.inOut2), mascot.pose(m);
  }
  function fitTaskTitle(tk) {
    let what = tk.el.querySelector(".what");
    if (!what.clientWidth) return;
    let size = 42;
    for (what.style.fontSize = `${size}px`; what.scrollWidth > what.clientWidth && size > 30; ) what.style.fontSize = `${--size}px`;
  }
  function cursorPose(on, p = [0, 0], press = 0) {
    show(cursor, on), on && (cursor.style.transform = `translate(${p[0] - 6}px, ${p[1] - 4}px) scale(${1 - press * 0.16})`);
  }
  var params = new URLSearchParams(location.search), capture = params.has("capture"), ready = (async () => {
    await document.fonts.ready, await Promise.all([...document.images].map((i) => i.complete ? null : new Promise((r) => {
      i.onload = i.onerror = r;
    }))), [titleA, titleB1, titleB2, titleE1, titleE2, titleE2b, titleE3].forEach((T) => T.measure()), render(+(params.get("t") || 0));
  })();
  window.__film = { render, ready, duration: DURATION, beats: BEATS };
  if (!capture) {
    document.body.classList.add("preview");
    let vpEl = document.getElementById("viewport"), fit = () => {
      let vw = document.documentElement.clientWidth || window.innerWidth, vh = document.documentElement.clientHeight || window.innerHeight, s = Math.max(0.05, Math.min((vw - 32) / W, (vh - 100) / H));
      Object.assign(vpEl.style, {
        position: "absolute",
        margin: "0",
        transformOrigin: "0 0",
        transform: `scale(${s})`,
        left: `${Math.round((vw - W * s) / 2)}px`,
        top: `${Math.round(Math.max(16, (vh - 84 - H * s) / 2))}px`
      }), document.body.style.setProperty("--s", s);
    };
    fit(), window.addEventListener("resize", fit), new ResizeObserver(fit).observe(document.documentElement), document.addEventListener("visibilitychange", fit);
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
