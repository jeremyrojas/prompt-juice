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
- Copy: Plenty left. / Resets soon. / You paid for the juice. / In your menu bar. /
  Use your strongest model. / Start another task. / Nothing wasted. / Don't waste the juice. /
  PromptJuice · promptjuice.app.

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

- **Stand-in sounds.** The approved palette is on the Mac and wasn't reachable. These are
  Pixabay stand-ins in the same roles; swap them via `SOUND-CUES.json` (see README).
- **No music bed.** It was not requested and there was no licensed source here. The film
  works muted, and the SFX carry it with sound on.
- **Mascot expressions** are painted strokes over the 3D-rendered character. They read well
  at film size but are flatter than the original eyes up close (the alert face most of all).
- **"In your menu bar."** is the quietest shot (a thin bar at the top of a dark frame,
  about 0.7 s). A tighter 3–4× crop on the bar would sell the glyph more.
- **The benefit task cards** are illustrations. Their labels are small on a phone; the title
  above them carries the meaning.
- **Fonts** are Inter / Inter Display rather than SF Pro; panel text sits a hair wider
  than the real app.
- The original film's BRIEF/SPEC/STORYBOARD/REVIEW and the landing page weren't reachable
  from this session, so copy came from the brief in the request and the repo README.
