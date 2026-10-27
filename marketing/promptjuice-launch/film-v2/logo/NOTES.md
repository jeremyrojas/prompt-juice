# PromptJuice end-card logo: three directions

All three are 1920×1080 SVG end cards on the near-black ground (#07080b). Each one has the real mascot PNG, the
"PromptJuice" wordmark as paths, the closing line **"Use it or lose it."** (`#tagline`, with "lose it." in amber)
and a small **"Free & open source · MIT"** pill (`#oss-pill`). Every lockup is centred and stays within 62–66 % of the frame width
(70 % is the limit). The wordmark's cap height is 129–140 px, so it is about 25 px tall in the 360 px preview and reads
easily. The tagline is about 9 px tall there and still reads. The pill text is about 4 px tall there and is only a texture at that size, which suits a quiet line.

| File | Preview |
| --- | --- |
| `option-1.svg` | `option-1.png`, `option-1-360.png` |
| `option-2.svg` | `option-2.png`, `option-2-360.png` |
| `option-3.svg` | `option-3.png`, `option-3-360.png` |

## Option 1: Juice Level

The mascot stands above the word. "Prompt" is solid white. The letters of "Juice" are drawn as glasses: a faint green tint with a thin rim.
Each one is filled with juice up to about 60 % of the cap height, with a wavy surface, a pale meniscus line and a few bubbles.
The dot of the i is the app's droplet (`DropletGeometry.swift`), drawn larger and in solid green, like a drop about to fall in. This option says what the
product does: it shows how much juice you have left. It also gives the strongest animation: the juice rises
through the letters. On a static frame it is the quietest of the three, because the mascot simply floats above the word.

## Option 2: Perch (recommended)

The mascot sits on the word. It rests on the flat lowercase run of "Prompt", between the P and the tall t. Its feet are on
the **m** and the **p**, and those two letters give slightly under its weight (5 % lower, 1 % wider). "Juice" is in the green
gradient. Juice drips from the bottom of the **J** and one drop has already let go. The dot of the i is again the droplet.
The mascot uses the ^ ^ joy expression. This is the option where the type and the character interact, so it looks like a logo
and not a picture beside a word. The squashed letters and the drip reward a second look without becoming cartoonish.
The mascot ends up only about 60 px left of the frame centre.

## Option 3: Peek

The wordmark is set largest here. The mascot stands behind the letters and its face shows above them, cut off along the x-height line.
A ground-coloured outline around every letter separates the type from the mascot. A capacity gauge runs under the word,
filled to 78 % with a bright tip. It passes behind the **p** descender, so the outline cuts it there and the bar looks woven
into the word. Of the three, this one is the boldest and the most legible on a phone. The outline makes it look more like a sticker and less premium,
and you never see the mascot's feet.

## Recommendation

**Option 2 (Perch).** It is the most characterful of the three while staying premium. The interaction between the mascot and the type is
the idea, so there is no extra ornament to look corny. It also animates as a short scene: the mascot lands, the letters squash,
the J drips. If you want the "juice level" idea too, borrow option 1's `#juice-fill` technique for the build-in, then settle on
Perch.

## Animation ids

Every animated group has no `transform` attribute, so `el.style.transform = …` is safe. Any built-in transforms, such as option 2's
squash, live on inner `<g>`s. Two classes set the pivots:

- `.pj-pivot` uses `transform-box: view-box` with an explicit inline `transform-origin` in SVG units. The **letters** (`#l-*`) pivot
  at the letter's centre on the baseline. **`#mascot`** pivots between its feet, where they touch the ground (not at the bottom
  edge of the PNG, which has a soft shadow below the feet). **`#drip`** pivots at its top.
- `.pj-anim` uses `transform-box: fill-box; transform-origin: 50% 100%` (bottom centre). It is on `#droplet-dot` and `#drip-drop`.
  `.pj-center` (centre) is on `#tagline`, `#oss-pill`, `#gauge-tip` and `#mascot-shadow`.

Do not replace the whole `style` attribute, or the inline `transform-origin` is lost. Set `style.transform` only.

Common to all three:

| Id | Suggested move |
| --- | --- |
| `#bg`, `#glow` | Ground and green halo. Fade `#glow` in as the mascot lands |
| `#mascot` (> `#mascot-img`) | Drop in and land with a squash spring (`scale(1.08,0.9)` → 1). Swap the expression by setting `href` on `#mascot-img` (`-blink` for a blink, `-joy` on the beat) |
| `#wordmark` > `#word-prompt`, `#word-juice` | The two halves |
| `#l-P #l-r #l-o #l-m #l-p #l-t #l-J #l-u #l-i #l-c #l-e` | One per letter (ids are case-sensitive: `#l-P` ≠ `#l-p`). Stagger a pop from the baseline: `translateY(30px) scale(0.6)` → 1 with overshoot, 30–40 ms apart |
| `#droplet-dot` | The dot of the i. Drop it in from above with `scale(0.9,1.15)` while it falls, then a squash on landing |
| `#tagline` > `#tagline-use`, `#tagline-lose` | Fade and rise. Bring in "lose it." about 150 ms later, or give it a small amber flash |
| `#oss-pill` | Fade in last, small and slow |

Option 1:

| Id | Suggested move |
| --- | --- |
| `#juice-level` | Fill and drain. `translateY(92px)` is empty, `0` is the rest level, about `-56px` is to the brim. Rise from empty with a slight overshoot |
| `#juice-wave` | Slosh. The wave repeats every 146 px, so `translateX((t*speed % 1) * 146px)` loops seamlessly. Only translate it to the right (0 → +146) |
| `#juice-bubbles` | Drift up a few px and fade |
| `#juice-vessel` | The empty glass. It can fade in before the fill |
| `#juice-clip` > `#jc-J … #jc-e` | `<use>` copies of the Juice glyphs. If you move a Juice letter while it holds juice, apply the same transform to its `#jc-*` too |

Option 2:

| Id | Suggested move |
| --- | --- |
| `#mascot` | Land on the m and p. At the moment of contact, push `#l-m` and `#l-p` down (`scaleY(0.9)` → 1 with a spring). The squash is built into an inner `<g>`, so this adds to it |
| `#mascot-shadow` | Contact shadow. Scale it with the mascot's height above the word |
| `#drip` | Stretch it down from the J (`scaleY(0.2)` → 1, then a small wobble) |
| `#drip-drop` | Let it fall and fade, or loop: it hangs, falls, then a new drip grows |

Option 3:

| Id | Suggested move |
| --- | --- |
| `#mascot` (inside `#mascot-peek`, clipped by `#peek-clip`) | Rise from behind the word: `translateY(300px)` → 0. It stays hidden below the x-height line |
| `#wordmark-knockout` | `<use>` clones of every `#l-*` with a ground-coloured stroke. They follow any letter transform automatically |
| `#gauge-fill`, `#gauge-track`, `#gauge-tip` | Fill the bar: set `transform-box: fill-box; transform-origin: 0 50%` on `#gauge-fill` and animate `scaleX`, or animate its `width`. `#gauge-tip` does not follow on its own: translate it by the same amount |

## Fonts and licences

- **Lettering:** Bricolage Grotesque 800 for the wordmark and 600 for the tagline and pill. The fonts come from the film's own
  `assets/fonts/BricolageGrotesque-*.woff2` files, which are © 2022 The Bricolage Grotesque Project Authors under the **SIL Open Font
  License 1.1** (`assets/fonts/BricolageGrotesque-OFL.txt`; it names no Reserved Font Name). The text is shaped with HarfBuzz
  (kerning on, tracked −12 units), cleaned of overlapping contours with skia-pathops and **converted to paths**. **All text,
  the tagline and pill included, is paths**, and none of the SVGs needs a font. The custom parts are drawn in code: the droplet in place of the dot of the i, the J drip, the m/p squash, the glass and juice
  treatment, and the gauge knockout.
- **Droplet:** the exact cubic curves from `app/PromptJuice/UI/DropletGeometry.swift`.
- **Mascot:** the repo's own PNGs, used as they are and referenced, not embedded.
- **Rebuild:** `pip install fonttools brotli uharfbuzz skia-pathops`, then `python3 logo/src/build.py` and
  `node logo/src/render.cjs` (set `PLAYWRIGHT=/path/to/playwright` if it is not resolvable).

## Weak spots

- The woff2 files are the static text-size cut of Bricolage. They look closer to a neutral grotesque than its quirky display
  optical size. The character comes from the customisations, not from the base letterforms.
- **Option 1:** the empty tops of the "Juice" letters are lower in contrast. They still read at 360 px, but "Juice" looks a little
  dimmer than "Prompt" on a static frame. The bubbles do not show at phone size.
- **Option 2:** the drip and the falling drop are only about 4 px wide on a phone, so they read as a dot. Give them motion. On a
  still frame the m/p squash could be taken for a mistake if nobody notices that the mascot causes it.
- **Option 3:** the outline makes it look like a sticker, the gauge tip has to be moved by hand, and the mascot is cut off.
- **All options:** the open-source pill is too small to read at 360 px. Enlarge it if it has to read on a phone.
