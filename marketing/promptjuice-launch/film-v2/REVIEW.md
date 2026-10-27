# Review: launch film v2

## Creative calls

- **Mascot-centred, no glass.** An early pass built a three.js glass droplet; it was
  dropped at the owner's request in favour of a fun, mascot-led film. The mascot carries
  the colour story: it *is* green or amber, and it changes colour with a rising juice line.
- **Anime-style bars.** Every capacity bar zips left → right on a spring, with a hot
  head, speed streaks, sparks and a glint when it lands. It's the same gesture at every
  scale, from the giant hero bar to the 6 pt bars in the panel.
- **The turn has a cause.** The reset clock rolls `2h 56m → 33m` *before* anything turns
  amber, so the colour change reads as "time ran down" rather than as decoration.
- **The Juicebar is shown, not mocked up.** It's rebuilt from the SwiftUI metrics and seen
  from four camera positions: unfolding under the menu bar, a low-angle 4.3× punch-in, a
  front-on dropdown, and a three-quarter angle with the legend. Tilts stay at or under 22°
  and every reading moment settles close to flat.
- **The benefit is a mechanism.** Tasks visibly drink from the 5-hour bar, the clock runs
  out, it refills green: "Nothing wasted." That shows why amber matters without a claim
  about anyone else's product.
- Copy: Plenty of juice left. / Resets soon. / You paid for the juice. / Don't waste it. /
  Use your strongest model. / Use higher effort. / Start another task. / Nothing wasted. /
  PromptJuice · Use it or lose it. · Free & open source · MIT.

## What was checked

- Contact sheets of every beat, strips across every transition, and a phone-width sheet
  (360 px). All titles, the punch-in row and the expanded panel read at phone width; the
  establishing panel shot (2.6×) is legible but small on a phone, by design, since the
  punch-in follows it.
- Fixed after review: a stray mascot during the panel scenes; the leap and "!" colliding
  with the title; the jump leaving frame before reaching the glyph; cards hidden while the
  panel unfolds (3D depth sorting); juice streams crossing labels; the refill overshooting
  to "107% left"; the wordmark wiping in under the moving mascot; tabular figures
  spacing out the hyphen in "5-hour"; panel shots too small for phones.
- Sound: every cue's peak lands one frame (~36 ms) after its picture, measured on the mix.
  The two outliers are a chime partly masked by a neighbouring whoosh. Integrated loudness
  is −16.9 LUFS with a −1.5 dBTP true peak. **The mix was measured, not heard.**

## Still weak / not done

- **Sound.** Music is Epidemic Sound's *intuition (Instrumental)* by dasloe, spliced on bar lines so
  the drop lands on the reset; the Juicebar whooshes and the droplet drip are Epidemic effects. The
  rest are Pixabay effects (`assets/sfx/CREDITS.md`). Licensed files live in `licensed/` (not in git).
- **Mascot expressions** are painted strokes over the 3D-rendered character. They read well
  at film size but are flatter than the original eyes up close (the alert face most of all).
- **The menu-bar beat** has no caption (it competed with the click); the glow drifting up to the glyph carries the eye instead.
- **The benefit task cards** are illustrations. Their labels are small on a phone; the title
  above them carries the meaning.
- **Fonts:** titles, captions and the logo are Instrument Sans; the Juicebar is Inter / Inter Display
  rather than SF Pro, so panel text sits a hair wider than the real app.
- The original film's BRIEF/SPEC/STORYBOARD/REVIEW and the landing page weren't reachable
  from this session, so copy came from the brief in the request and the repo README.
