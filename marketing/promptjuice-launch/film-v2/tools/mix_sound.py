"""Mix SOUND-CUES.json (effects, plus an optional music bed) into
dist/soundtrack.wav (+ .mp3 for the preview).

    python3 tools/mix_sound.py [--cues SOUND-CUES.json]

Each cue places one file at a film time. align="peak" (the default) lands the
file's loudest moment one frame after the picture; align="start" starts it there. Repeated
files get a small, deterministic pitch/level variation so they don't read as
the same take.
"""
import argparse
import json
import subprocess
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SR = 48000


def decode(path):
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"],
        check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).copy()


def peak_index(x):
    env = np.abs(x).max(axis=1)
    win = max(1, SR // 200)
    smooth = np.convolve(env, np.ones(win) / win, mode="same")
    return int(np.argmax(smooth))


def music_bed(src, music, n):
    """Lay the music track along the film. "segments" is a list of
    {"from": source seconds, "at": film seconds}; each plays until the next
    one starts, joined by a short equal-power crossfade (cut on bar lines)."""
    segs = music.get("segments") or [{"from": 0.0, "at": 0.0}]
    xf = int(music.get("xfade", 0.04) * SR)
    bed = np.zeros((n, 2), np.float32)
    for i, seg in enumerate(segs):
        a = int(round(seg["at"] * SR))
        b = int(round(segs[i + 1]["at"] * SR)) if i + 1 < len(segs) else n
        s0 = int(round(seg["from"] * SR))
        lo, hi = max(0, a - (xf if i else 0)), min(n, b + (xf if i + 1 < len(segs) else 0))
        chunk = src[s0 - (a - lo): s0 - (a - lo) + (hi - lo)]
        chunk = np.pad(chunk, ((0, (hi - lo) - len(chunk)), (0, 0)))
        w = np.ones(hi - lo, np.float32)
        if i and xf:
            w[: 2 * xf] = np.sin(np.linspace(0, np.pi / 2, 2 * xf))
        if i + 1 < len(segs) and xf:
            w[-2 * xf:] = np.cos(np.linspace(0, np.pi / 2, 2 * xf))
        bed[lo:hi] += chunk * w[:, None]
    # Dips: pull a moment of the track down (e.g. a stab the picture doesn't
    # want), with 40 ms ramps so the edit can't click.
    for dip in music.get("dips", []):
        a0, a1 = int(dip["from"] * SR), int(dip["to"] * SR)
        g = np.ones(n, np.float32)
        g[a0:a1] = 10 ** (dip.get("db", -12) / 20)
        ramp = int(0.04 * SR)
        g = np.convolve(g, np.ones(ramp) / ramp, mode="same").astype(np.float32)
        bed *= g[:, None]
    if music.get("end_at"):
        # Stop the track at a natural gap, with a 20 ms ramp so it can't click.
        e = int(music["end_at"] * SR)
        r = int(0.02 * SR)
        bed[e:] = 0
        bed[max(0, e - r):e] *= np.linspace(1, 0, min(r, e))[:, None]
    fi = int(music.get("fade_in", 0.0) * SR)
    if fi:
        bed[:fi] *= np.linspace(0, 1, fi)[:, None] ** 2
    fo = int(music.get("fade_out", 0.0) * SR)
    if fo:
        bed[-fo:] *= np.linspace(1, 0, fo)[:, None]
    return bed


def repitch(x, ratio):
    if abs(ratio - 1) < 1e-4:
        return x
    n = int(len(x) / ratio)
    src = np.arange(n) * ratio
    return np.stack([np.interp(src, np.arange(len(x)), x[:, c]) for c in range(2)], axis=1).astype(np.float32)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cues", default=str(ROOT / "SOUND-CUES.json"))
    args = ap.parse_args()
    spec = json.loads(Path(args.cues).read_text())
    fps, dur = spec["fps"], spec["duration"]
    mix = np.zeros((int((dur + 1) * SR), 2), np.float32)
    cache, uses = {}, {}
    for cue in spec["cues"]:
        f = cue["file"]
        if f not in cache:
            cache[f] = decode(ROOT / f)
        n = uses.get(f, 0)
        uses[f] = n + 1
        variation = [1.0, 1.045, 0.962, 1.02, 0.98][n % 5]
        x = repitch(cache[f], variation) * cue.get("gain", 1.0)
        if cue.get("fade_in"):
            # Ease the sample in (e.g. a long swell whose start arrives too early).
            fi = min(len(x), int(cue["fade_in"] * SR))
            x = x.copy()
            x[:fi] *= (np.linspace(0, 1, fi) ** 2)[:, None]
        at = cue["time"] + 1 / fps
        if cue.get("align", "peak") == "peak":
            at -= peak_index(x) / SR
        i0 = int(round(at * SR))
        if i0 < 0:
            x, i0 = x[-i0:], 0
        i1 = min(len(mix), i0 + len(x))
        mix[i0:i1] += x[: i1 - i0]
    mix = mix[: int(dur * SR)]
    music = spec.get("music")
    if music and (ROOT / music["file"]).exists():
        # Music bed under the effects. It dips a few dB while an effect rings
        # so the hits stay clear without the bed pumping.
        bed = music_bed(decode(ROOT / music["file"]), music, len(mix)) * music.get("gain", 0.8)
        env = np.abs(mix).max(axis=1)
        win = int(0.12 * SR)
        env = np.convolve(env, np.ones(win) / win, mode="same")
        duck_db = music.get("duck_db", 4.0)
        gain = 10 ** (-duck_db * np.clip(env / (env.max() + 1e-9) * 3, 0, 1) / 20)
        mix = mix + bed * gain[:, None].astype(np.float32)
    # Gentle bus: soft-clip and normalise the peak to -1 dBFS.
    mix = np.tanh(mix * 1.2) / np.tanh(1.2)
    peak = np.abs(mix).max()
    if peak > 0:
        mix *= (10 ** (-1 / 20)) / peak
    fade = int(0.4 * SR)
    mix[-fade:] *= np.linspace(1, 0, fade)[:, None]
    out = ROOT / "dist"
    out.mkdir(exist_ok=True)
    wav = out / "soundtrack.wav"
    # Social loudness: about -15 LUFS integrated, true peak under -1.5 dBTP.
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", "-",
                    "-af", "loudnorm=I=-15:TP=-1.5:LRA=14", "-ar", str(SR),
                    "-c:a", "pcm_s16le", str(wav)], input=mix.astype(np.float32).tobytes(), check=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(wav), "-c:a", "libmp3lame", "-b:a", "192k", str(out / "soundtrack.mp3")], check=True)
    print(f"mixed {len(spec['cues'])} cues → {wav}")


if __name__ == "__main__":
    main()
