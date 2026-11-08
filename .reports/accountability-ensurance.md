# Accountability ensurance — showtime

| | |
|---|---|
| Upstream | `main` @ `f28a1d4` |
| Port | `ruby` @ `e191199` |

Scanned: `lib/`, `exe/`, `test/`, `.reports/` (there is no `PORTING.md` on
this branch) with `grep -rniE 'TODO|FIXME|not implemented|for now|in a
future|unported|not ported|intentionally'`, every hit read in context by
hand, not accepted on the grep alone.

```
lib/showtime/mpris.rb:19       "TODO"          — not an excuse: quotes the gio2 gem's own
                                                  NotImplementedError text, verbatim, to explain
                                                  why a workaround was needed
test/drive_video_widgets.rb:6  "not ported"    — still stale; unchanged from last round, not fixed
```

## The headline finding from the last round is resolved — and resolved for real, not just reworded

The previous round's most serious finding was that `window.rb:30-36` called
two unmade decisions ("the install-plugin button" and "the single-window
architecture") "intentionally not ported" while giving reasons that were
false ("no installer exists to drive in this environment" — a fact about the
sandbox, not the app). This round finds that:

1. **The install-plugin flow is now actually built**, not merely
   reworded past. Read `window.rb:445-494` directly: `install_callback`
   gates on `GstPbutils.install_plugins_supported`, `install_plugin` drives
   `GstPbutils.install_plugins_async`, `on_install_done` branches on the
   real `InstallPluginsReturn` enum. Ran `test/drive_window.rb` myself
   (`nix develop --command xvfb-run -a ruby test/drive_window.rb`) and got
   `41 of 41 checks passed`, `DRIVE OK`, with checks 12-17 specifically
   exercising this path through a real `GstPbutils` bus message. This is
   the thing this skill is built to force — not a rewritten excuse, an
   actual built feature, verified by running it, not by reading the commit
   message that claims it.

2. **The class comment was rewritten, and rewritten honestly.** It no
   longer says "intentionally not ported." It now reads (window.rb:30-36):

   > One upstream behaviour is not yet built here: upstream's `do_activate`
   > constructs a brand-new `Window` on every call... Nothing in
   > `ruby-gnome` stops the multi-window architecture from being built; it
   > is simply not done yet — see `.reports/accountability-ensurance.md`.

   This names the gap as owed, names the thing that would have to be built,
   and does not claim a binding limitation that doesn't exist. That is
   exactly the correction this skill asks for — not deleted, not softened
   into "future work," rewritten to say the true thing in the first
   person's place. The single-window gap itself is still open (see
   `component-parity`); what changed is that the source no longer
   misdescribes it as a decision.

## The stale hit that is still unfixed

`test/drive_video_widgets.rb:6` ("The window class that assembles them onto
a playing video is not ported yet, so this hosts them in a window of its
own...") was flagged as stale in the previous round's report —
`window.rb` has existed and been driven by its own file for several rounds
now — and **it is still there, unedited, this round**. Two commits touched
this area of the codebase since the last accountability round
(`6f102ac`, `e191199`) and neither one touched this comment. This is not a
live excuse hiding missing work (the window class plainly exists and is
driven elsewhere, so no reader is actually misled about whether `window.rb`
is built), but it is a second round in a row where a known-stale sentence
in a committed file was named and not corrected. Per this skill's own
"rewrite in place, never just flag it" instinct, the fact that naming a
stale comment twice without it getting fixed is itself worth recording: a
report that keeps saying the same true thing about a one-line fix, without
the fix landing, is low-cost to lose track of.

## A false-green risk this round checked directly rather than assuming closed

The runtime gate for this round is `drive_ok=true, 99/99, 18 components`.
The temptation with a clean gate and a fresh "gap closed" commit is to read
both as proof the port is now complete. Checked directly:

- **99/99 still does not cover the single-window gap.** No drive script
  opens, or asserts the existence of, a second `Gtk::Window`; the gate
  passing says nothing about this still-open behaviour. (`component-parity`
  and `test-parity` both carry this.)
- **The `data/` gap (desktop entry, AppStream metainfo, GSettings schema)
  has no drive-script coverage and, until this round, no explicit row in
  either `component-identification` or `component-parity` either** — it
  was buried inside `translation-parity`'s message count with no component
  identity of its own. That is not a lie, but it is the shape of
  under-reporting this skill exists to catch: a real gap that was
  technically on record somewhere, phrased in a way that made it easy to
  miss as "just 8 missing translation strings" rather than "three files the
  port does not ship at all." This round gives it its own row in
  `component-parity.md` rather than leaving it to be inferred from a
  translation count.
- **`spec/` still runs 0 examples.** Re-run this round
  (`nix develop --command xvfb-run -a ruby -e '...spec...'`) — unchanged
  from the last round, still a live documentation gap: the dev shell's own
  banner calls this "run the specs" and it finds nothing. Carried forward
  rather than silently dropped because it was already reported once.

None of these three are new claims being excused this round — they are
carried-forward gaps, checked again rather than assumed stable, and the one
new one (`data/`'s own identity) is being surfaced more clearly than before,
not softened.

## Rules check against this skill

- The live excuse this skill exists to catch was found resolved by actually
  reading the current source and running the current suite, not by trusting
  the commit messages that claim the resolution.
- The still-stale comment is named again rather than assumed fixed because
  a previous report mentioned it once.
- The `data/` gap's previous under-reporting (buried in a translation count,
  no component row of its own) is named as a reporting shortcoming in its
  own right, not just as a parity gap.
- No new excuse language (`TODO`/`FIXME`/`not implemented`/`for now`/`in a
  future`/`unported`/`not ported`/`intentionally`) was introduced by the two
  commits made since the last round, confirmed by diffing their changed
  lines against the grep pattern above.
