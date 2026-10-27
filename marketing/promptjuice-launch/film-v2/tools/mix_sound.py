"""Mix SOUND-CUES.json into dist/soundtrack.wav (+ .mp3 for the preview).

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
        at = cue["time"] + 1 / fps
        if cue.get("align", "peak") == "peak":
            at -= peak_index(x) / SR
        i0 = int(round(at * SR))
        if i0 < 0:
            x, i0 = x[-i0:], 0
        i1 = min(len(mix), i0 + len(x))
        mix[i0:i1] += x[: i1 - i0]
    mix = mix[: int(dur * SR)]
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
