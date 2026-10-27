// Small, pure animation helpers. Everything is a function of time.

export const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
export const lerp = (a, b, k) => a + (b - a) * k;
export const mix = lerp;

export const ease = {
  linear: (k) => k,
  inOut2: (k) => (k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2),
  inOut3: (k) => (k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2),
  inOut4: (k) => (k < 0.5 ? 8 * k ** 4 : 1 - Math.pow(-2 * k + 2, 4) / 2),
  in2: (k) => k * k,
  in3: (k) => k * k * k,
  in4: (k) => k ** 4,
  out2: (k) => 1 - (1 - k) * (1 - k),
  out3: (k) => 1 - Math.pow(1 - k, 3),
  out4: (k) => 1 - Math.pow(1 - k, 4),
  outExpo: (k) => (k >= 1 ? 1 : 1 - Math.pow(2, -10 * k)),
  inExpo: (k) => (k <= 0 ? 0 : Math.pow(2, 10 * k - 10)),
  inOutExpo: (k) => (k <= 0 ? 0 : k >= 1 ? 1 : k < 0.5 ? Math.pow(2, 20 * k - 10) / 2 : (2 - Math.pow(2, -20 * k + 10)) / 2),
  outBack: (k, s = 1.5) => 1 + (s + 1) * Math.pow(k - 1, 3) + s * Math.pow(k - 1, 2),
};

/** Progress of t through [t0, t1], eased and clamped. */
export function seg(t, t0, t1, fn = ease.linear) {
  if (t <= t0) return 0;
  if (t >= t1) return 1;
  return fn((t - t0) / (t1 - t0));
}

/** Closed-form damped spring step response: 0 → 1 (may overshoot). */
export function spring(t, t0, { zeta = 0.8, freq = 2.2 } = {}) {
  const x = t - t0;
  if (x <= 0) return 0;
  const w = 2 * Math.PI * freq;
  if (zeta >= 1) return 1 - (1 + w * x) * Math.exp(-w * x);
  const wd = w * Math.sqrt(1 - zeta * zeta);
  return 1 - Math.exp(-zeta * w * x) * (Math.cos(wd * x) + (zeta * w / wd) * Math.sin(wd * x));
}

/** Damped oscillation that starts at 0 with a kick, for sloshes and wobbles. */
export function wobble(t, t0, { amp = 1, freq = 2.5, decay = 3.5 } = {}) {
  const x = t - t0;
  if (x <= 0) return 0;
  return amp * Math.sin(2 * Math.PI * freq * x) * Math.exp(-decay * x);
}

/**
 * Piecewise keyframes: [[time, value, easeIntoThisKey?], ...].
 * Values may be numbers or arrays of numbers.
 */
export function keys(t, list) {
  if (t <= list[0][0]) return list[0][1];
  for (let i = 1; i < list.length; i++) {
    const [t1, v1, fn = ease.inOut3] = list[i];
    const [t0, v0] = list[i - 1];
    if (t <= t1) {
      const k = fn((t - t0) / Math.max(1e-6, t1 - t0));
      return Array.isArray(v0) ? v0.map((a, j) => lerp(a, v1[j], k)) : lerp(v0, v1, k);
    }
  }
  return list[list.length - 1][1];
}

/** Visible-window helper: 1 inside [t0, t1), with optional fades. */
export function win(t, t0, t1, fadeIn = 0, fadeOut = 0, fn = ease.out3) {
  if (t < t0 || t >= t1) return 0;
  const a = fadeIn > 0 ? fn(clamp((t - t0) / fadeIn)) : 1;
  const b = fadeOut > 0 ? clamp((t1 - t) / fadeOut) : 1;
  return Math.min(a, b);
}

/** Seeded PRNG (mulberry32). */
export function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
