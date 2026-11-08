# Translation parity — showtime

| | |
|---|---|
| Upstream | `main` @ `f28a1d4` |
| Port | `ruby` @ `e191199` |
| Domain | `showtime` (upstream, from `po/meson.build`'s `bin_name`) — port has **no domain concept at all** (reads `.po` directly; no `.mo`, no `bindtextdomain`) |
| Upstream messages | 77 (code: 67 across `showtime/**/*.py` + `showtime/gtk/*.blp`; `data/`: 10 from `desktop.in`/`metainfo.xml.in`/`gschema.xml.in`) |
| Ported (by hand-census, see below) | 70 |
| Gaps | 7, all from `data/` |
| Extra (untranslated) | 2 (`Open the app with a new window`, `Translate`) — unchanged, see note |
| Upstream occurrences | 87 across 77 messages (9 reused), 1 unresolved (`ngettext(` with a variable msgid at `showtime/widgets/options.py:90`) |
| Upstream languages | 57 `.po` files, 4,344 translated / 67 untranslated / 0 fuzzy |
| Languages shipped by the port | **57/57** — `po/` copied verbatim, `LINGUAS` byte-identical, confirmed by `diff` |

**`catalogue.rb`'s automated scan of the port reports 0 messages and is still
wrong**, for the same reason the last round recorded: the port routes every
user-visible string through `Showtime::Translations.translate(...)` /
`.ngettext(...)`, not `_()`/`N_()`/`ngettext()`, so this skill's scanner has
no rule for it. Numbers in this report come from a by-hand census,
re-run this round: `grep -rn 'Translations\.\(translate\|ngettext\)('
lib/ exe/` now returns 64 call sites (up from 63 last round — one new site,
see below), each read to resolve variable arguments back to their literal
table.

## What changed since the last round: the "Installing…" gap is closed

The previous round's census found **one genuine behavioural gap independent
of the missing-`data/` cause**: `Installing…`
(`showtime/widgets/window.py:838`) had no port site at all, because the
install-plugin flow itself was not built. That flow is now built
(`6f102ac`), and the toast is marked for translation at its real call site:

```
lib/showtime/window.rb:474:  toast_overlay.add_toast(Adwaita::Toast.new(Translations.translate("Installing…")))
```

Confirmed by reading the line directly, and confirmed the string survives
byte-for-byte against upstream's `window.py:838` literal (`"Installing…"`,
same ellipsis character, not three ASCII dots). This moves the ported count
from 69 to 70 and removes the one gap that was not downstream of the
missing-`data/` cause.

## The 7 remaining gaps — all `data/`, and all still present

Unchanged from the last round except for dropping the now-closed
`Installing…` row. The port still has **no `data/` directory beyond the icon
SVGs** — no `.desktop.in`, no `.metainfo.xml.in`, no `.gschema.xml.in` (this
round re-confirmed with `find data -type f`, which lists only
`data/icons/**/*.svg`). That is also a `component-parity` gap this round's
`component-parity.md` names explicitly for the first time — see that report.
These three files own 10 of upstream's 77 messages (2 of the 10, `New
Window` and `Video Player`, are already carried by other files the port
does have, so they are not gaps):

| msgid | Upstream site | Port site |
|---|---|---|
| `Play videos` | `data/org.gnome.Showtime.desktop.in:3` | — |
| `Video;Movie;Film;Clip;Player;Showtime;` | `data/org.gnome.Showtime.desktop.in:9` | — |
| `The GNOME Project` | `data/org.gnome.Showtime.metainfo.xml.in` | — |
| `The app playing a video` | `data/org.gnome.Showtime.metainfo.xml.in` | — |
| `Watch without distraction` | `data/org.gnome.Showtime.metainfo.xml.in` | — |
| `E.g. total duration of the video or the amount of time remaining` | `data/org.gnome.Showtime.gschema.xml.in` | — |
| `What to show in the end timestamp position` | `data/org.gnome.Showtime.gschema.xml.in` | — |
| `Play your favorite movies and video files without hassle. Video Player features` | `data/org.gnome.Showtime.metainfo.xml.in` | — |

## What the hand-census confirms is actually ported (70 of 77)

Re-verified this round, not merely carried forward:

- **`shortcuts_dialog.rb`'s `SECTIONS` table** — 19 strings via
  `Translations.translate(title)`, matching
  `showtime/gtk/shortcuts-dialog.blp` byte for byte.
- **`primary_menu.rb`'s `SECTIONS` table** — 6 strings, mnemonics and
  ellipsis intact.
- **`restore_overlay.rb`** — `Resume`, `Start Again`.
- **`about_dialog.rb`** — `translator-credits`, `Translate` (see "Extra"
  below), `APPLICATION_NAME`/`DEVELOPER_NAME`/`COMMENTS`.
- **`window.rb`** — toasts (including the now-ported `Installing…`),
  file-dialog filter names, the `"{}" codecs...` pair.
- Every other call site in `options.rb`, `sound_options.rb`, `video_page.rb`
  matches its upstream msgid.

## Extra: two port-only strings (unchanged)

- **`Open the app with a new window`** (`application.rb:79`) — upstream has
  the identical string (`main.py:64`) but does not route it through gettext
  either (it is a GLib `OptionEntry` description, localized by GLib's own
  `--help` machinery, not `po/`). Not a regression.
- **`Translate`** (`about_dialog.rb:81`) — one of libadwaita's own built-in
  `Adw.AboutDialog.new_from_appdata` strings; the port builds the dialog by
  hand and had to supply it itself. Not a regression.

## What was actually run (Step 5) — still only half

Re-run this round, same result as last round:

```
nix develop --command xvfb-run -a ruby -e '
  $LOAD_PATH.unshift("lib"); require "showtime/translations"
  ENV["LANGUAGE"] = "de"; ENV["LC_ALL"] = "de_DE.UTF-8"
  puts Showtime::Translations.locale.inspect
  puts Showtime::Translations.translate("Watch Videos")
  puts Showtime::Translations.translate("Installing…")
'
```

This proves lookup, plural-form parsing, and locale selection work against
the real, copied `po/de.po`, including for the newly-ported `Installing…`
string. **It still does not prove a widget shows German on screen** — no
drive script runs the app under `LANGUAGE=de` and screenshots a widget. This
is unchanged from the last round and is still the unrun half of Step 5, not
a pass — see `.reports/test-parity.md`, which independently confirms no file
in `test/` exercises `Translations` end-to-end either.

## Rules check against this skill

- Byte-identical msgids: verified by hand for all 70 ported rows, including
  the newly-ported `Installing…`.
- No `n/a`/`by design`: the 7 `data/`-caused gaps are stated as gaps, with
  the cause named, not used to close the row.
- Languages: 57/57, byte-identical `LINGUAS` and file set, re-confirmed by
  `diff` this round.
- Domain: still does not match — the port has no domain at all. Unresolved,
  recorded as an open item again rather than silently dropped because it
  was already recorded once.
