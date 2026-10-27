# PromptJuice launch film, v2

A 25.9 s, 1920×1080, 30 fps launch film for X, built around the mascot. It is a
second creative pass, made to sit next to the original HyperFrames film
(`promptjuice-launch/film`) for comparison. It uses no HyperFrames: one HTML
page draws every frame as a pure function of time (`render(t)`). Playwright
seeks it frame by frame and ffmpeg encodes the frames.

## Files

| Path | What it is |
| --- | --- |
| `index.html` | The film plus the preview player (play, scrub, mute; space toggles play) |
| `src/main.js` | Every scene, camera and beat. `BEATS` holds all key times in one place |
| `src/panel.js` | The Juicebar rebuilt from `PromptJuicePanelView.swift` metrics (1 px = 1 pt) |
| `src/anim.js` | Easing, closed-form springs, keyframes, seeded randomness |
| `assets/img/mascot-*.png` | Mascot colour and expression variants (see below) |
| `SOUND-CUES.json` | Every sound effect: time, file, gain, alignment |
| `SHOTS.md` | Shot list |
| `REVIEW.md` | Review notes: what was checked, what is still weak |
| `out/promptjuice-launch-1080p.mp4` | The delivery render (not in git: it carries licensed music) |

## Run it

```bash
npm install                 # esbuild (Playwright comes from your global install)
npm run build               # src → dist/film.js
python3 tools/mix_sound.py  # SOUND-CUES.json → dist/soundtrack.wav/.mp3
open index.html             # preview in a browser
node tools/render.mjs --workers 4 --out out/promptjuice-launch-1080p.mp4
```

`tools/render.mjs --scale 0.5` gives a fast 540p draft. `tools/snap.mjs dir 1.5,9.4`
writes stills at exact times; `tools/sheet.py dir sheet.png` makes a contact sheet.
Rendering needs Node 22, Playwright's Chromium and ffmpeg.

## Mascot variants

`tools/make_mascot_variants.py` builds the eight PNGs from
`design/assets/promptjuice-mascot-happy.png`. Nothing is redrawn:

- **amber** is a hue remap of the same pixels toward `#F0A32A`, keeping the shading.
- **blink**, **joy** (^ ^) and **alert** (wide eyes) paint over only the eyes and mouth.
  The body under them is inpainted from its own surrounding pixels.

## Sound

`SOUND-CUES.json` lists every effect (time, file, gain, alignment) and the music bed.
The music (Epidemic Sound, *intuition (Instrumental)* by dasloe) and the Epidemic effects
are licensed and live in `licensed/`, which is not in git: put the files there to rebuild
the soundtrack. The music is laid from three bar-aligned sections of the track
(`segments`), with dips, a fade-in, and a stop at a natural gap (`end_at`).

`align: "peak"` places each file's loudest moment one frame after the picture.
The mix is loudness-normalised to about −15 LUFS with a −1.5 dBTP ceiling.

## Accuracy notes

- All panel labels, colours, sizes and behaviour come from the Swift source:
  the `Use your Claude juice` header and `5-hour · 83% left · resets in 33m`
  subtitle (`UseSoonHeader`), `resets in …` formatting (`ResetFormatter`), the
  amber/green bar gradients, the collapsed card showing only the 5-hour limit,
  and the chevron rotating 90° to expand.
- Weekly 88% · 4d, Fable 98% · 4d and Codex Weekly 88% · 5d match a real
  capture. Codex Pro reports only a Weekly limit, so its card has no chevron,
  as in the app.
- The menu-bar glyph uses `DropletGeometry` and `PromptJuiceIcon`'s layout,
  quantised to 80% and tinted amber.
- The Juicebar uses Inter and Inter Display (SF Pro can't ship here); film titles and the logo use Instrument Sans. The menu bar
  icons and clock are generic stand-ins.
- The task cards in the benefit scene are illustrations, not PromptJuice UI.
