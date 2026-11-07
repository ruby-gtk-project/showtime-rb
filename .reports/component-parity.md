# Component parity — showtime

| | |
|---|---|
| Upstream | `main` @ `f28a1d4` |
| Port | `ruby` @ `47105ff` |
| Units with full (4-axis) parity | 15 / 18 |
| Units with an open gap | 3 / 18 — #1 `application.rb`, #4 `placeholder_page.rb` (install-plugin flow), #5/#3 `window.rb` (retry-in-place, no second window) |

This builds on the unit inventory already written in
`.reports/component-inventory.md` (the `component-identification` output),
re-checked unit by unit against the four axes: count, style, behaviour, text.
The text axis is covered in full by `.reports/translation-parity.md`'s
hand-census and is summarized per unit below rather than repeated.

## Units with parity (15)

Units 2, 6, 7, 8, 9, 10, 12, 13, 14, 15, 16, 17 are unchanged from the
component-identification report's "exists, mounted, driven" findings, and the
text-axis census confirms every string each one shows is marked and
byte-identical (primary menu's 6 items, shortcuts dialog's 19 strings, sound
options, playback options, drag overlay, About dialog, utils, MPRIS, style,
settings, icons). Unit 18 (translations) is the mechanism, not a widget, and
is covered in full by `.reports/translation-parity.md`.

Unit 11 (About dialog) and unit 6 (restore overlay) both pass all four axes
including text — see the translation report's hand-census.

## Unit 1: `showtime/main.py` → `lib/showtime/application.rb` — partial

| Behaviour | Upstream | Port | Verdict |
|---|---|---|---|
| `HANDLES_OPEN` / `open` signal for CLI file args | `main.py:` `flags=HANDLES_OPEN`, `do_open` | `Gtk::Application.new(APP_ID, :handles_open)` (`application.rb:76`) | parity |
| `--new-window`/`-n` + `[VIDEO FILES]` | `main.py:59-64` | `application.rb:77-79` | parity |
| `handle-local-options` re-presenting a running instance | `main.py:` `do_handle_local_options` | `application.rb:57`, `:149-160` | parity |
| Idle inhibitor while playing | `app.inhibit_win`/`uninhibit_win` | `window.rb:171-192`, held on `@app` | parity (correspondence: moved onto `Window`, noted in both files' comments) |
| `playback_history.json` save/restore | `main.py` writes it; `settings.rb` defines `HISTORY_FILE` | `window.rb:113-114`, `:475`, `:522` call `save_current_play_position` on close | parity |
| `Gst.init()` | `main.py` | `play.rb:` idempotent in `Play#build` | parity |
| **One OS window per video file**, `do_open` calling `do_activate` once per `GFile` | `main.py` opens N windows for N CLI args | `Window` is a memoized singleton per `Application`; N CLI args play the last file in the one window | **gap** |

Six of the seven behaviours the component-identification report once listed
as missing for this unit are now built and wired (re-verified here by reading
`application.rb` and `window.rb` directly, not by trusting that report's
older text — see the stale-section warning at the top of
`.reports/component-inventory.md`). The seventh, multi-window-per-launch, is
still missing, and `.reports/accountability-ensurance.md` has the finding on
how it is described in the source.

## Unit 3/5: `window.py`/`window.blp` → `window.rb`/`video_page.rb` — two named gaps

| Widget / behaviour | Upstream | Port | Verdict |
|---|---|---|---|
| Every `win.*`/`app.*` action (21) | `window.py` `_create_action` × 18 + `main.py` × 3 | `window.rb` creates 18, `application.rb` creates 3 — `drive_window.rb` asserts the name and accelerator of all 21 by iterating the real action group | parity |
| `Gtk.FileDialog` × 3 (open video, subtitles, screenshot save) | `window.py` | `window.rb:270` (video), `:279` (subtitles), screenshot dialog built at the capture call site | parity |
| Retrying a failed stream opens a fresh attempt | `window.py:883-888`: `_try_again` calls `Application.do_activate(gfile)` — which **always constructs a brand-new `Window`** (`main.py:137-139`, no reuse check) — then closes the failing one | `window.rb`'s `_try_again` replays the file in the same, single, memoized `Window` instance | **gap** — verified by reading `do_activate`, which has no "reuse the existing window" branch at all; every upstream activation (first launch, `new-window`, retry-after-error, each CLI file argument) opens a distinct `Window`, and the port's single-window architecture diverges from all four, not just the CLI-file-arguments case the component-identification report already named |
| Install-plugin flow: `Gtk.Button` → PackageKit install → "Installing…" toast → re-probe | `window.py:825-850`, `placeholder_page.rb`'s equivalent `_present_install_plugin` region | `on_install` is always `nil` (`window.rb:31-33`); `placeholder_page.rb:148` only ever renders the button when `on_install` is truthy, so the button, the toast, and the re-probe never appear | **gap** |

The install-plugin gap is real and user-visible: on a system missing a
GStreamer plugin, upstream offers an "Install Plugin" button that drives
PackageKit and shows an "Installing…" toast; the port always falls through to
the "could not be found" wording instead, for every system, including ones
where installing the plugin would have worked. See
`.reports/accountability-ensurance.md` for how this is currently described in
`window.rb`'s own comment, which is the more serious finding.

## Unit 4: `placeholder_page.rb` — same install-plugin gap, from the other widget

`PlaceholderPage#show_missing_plugin` is the widget-side half of the gap
above: its three described states (full install flow / partial "try anyway" /
no installer) collapse to one in practice, because the caller never passes an
`on_install` callback. The widget code itself is otherwise complete — the
"codecs are required"/"codecs could not be found"/"no plugin available"
three-way message selection all exist and are driven by
`test/drive_placeholder.rb`'s two checks (`the description names the codec`,
`a system with no plugin installer gets the other message`) — but those two
checks only exercise the *message selection*, never the install button,
because nothing in the test harness supplies `on_install` either. The 94/94
drive-check gate therefore does not cover this gap; see
`.reports/test-parity.md`.

## Rules check against this skill

- Reported per unit, not as an app-wide total: the three open units are named,
  not folded into "15/18 roughly fine".
- No correspondence asserted without a location: every "parity" row above
  cites the file/line checked, including `do_activate`'s absence of any
  window-reuse branch, which is the fact the "retry-in-place" gap rests on.
- The single-window architecture is one root cause surfacing as three
  separate rows (unit 1's multi-window-per-launch, unit 3/5's retry-in-place,
  and the `new-window` action re-presenting instead of opening a second
  window) — recorded as three rows because each is a distinct behaviour a
  user can trigger, not collapsed into one to make the ledger shorter.
