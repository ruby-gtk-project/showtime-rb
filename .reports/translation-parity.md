# Translation parity — showtime

| | |
|---|---|
| Upstream | `main` @ `f28a1d4` |
| Port | `ruby` @ `47105ff` |
| Domain | `showtime` (upstream, from `po/meson.build`'s `bin_name`) — port has **no domain concept at all** (reads `.po` directly; no `.mo`, no `bindtextdomain`) |
| Upstream messages | 77 (code: 67 across `showtime/**/*.py` + `showtime/gtk/*.blp`; `data/`: 10 from `desktop.in`/`metainfo.xml.in`/`gschema.xml.in`) |
| Ported (by hand-census, see below) | 69 |
| Gaps | 8, all from `data/` |
| Extra (untranslated) | 2 (`Open the app with a new window`, `Translate`) — see note |
| Upstream occurrences | 87 across 77 messages (9 reused), 1 unresolved (`ngettext(` with a variable msgid at `showtime/widgets/options.py:90`) |
| Upstream languages | 57 `.po` files, 4,344 translated / 67 untranslated / 0 fuzzy |
| Languages shipped by the port | **57/57** — `po/` copied verbatim, `LINGUAS` byte-identical, confirmed by `diff` |
| Non-English string lookup verified on screen | **partial** — see "What was actually run" |

**`catalogue.rb`'s automated scan of the port reports 0 messages and is wrong.**
The port does not mark strings with `_()`/`N_()`/`ngettext()` — the markers
this skill's scanner recognizes — it routes every user-visible string through
`Showtime::Translations.translate(...)` / `.ngettext(...)`, a method call the
scanner has no rule for. Per this skill's "When the scanner is the thing that
is wrong" step, the fix (teaching the shared scanner a new marker name) is out
of scope for this round, so the numbers above come from a **by-hand census**:
`grep -rn 'Translations\.\(translate\|ngettext\)(' lib/ exe/`, followed by
reading every one of the 63 call sites to resolve the ones whose argument is a
local variable rather than a literal (`title`, `label`, `text`, `msgid`,
`APPLICATION_NAME`, `DEVELOPER_NAME`, `COMMENTS`) back to the literal table
each one is called from (`SECTIONS` in `shortcuts_dialog.rb` and
`primary_menu.rb`, the `overlaid_label` call sites in `restore_overlay.rb`,
the constants at the top of `about_dialog.rb`). **Report this scanner gap
upstream to the skill** — it is specific to this port's choice of method name,
not a one-off worth silently working around.

## The 8 real gaps — all `data/`

The port has **no `data/` directory at all** — no `.desktop.in`, no
`.metainfo.xml.in`, no `.gschema.xml.in` — a fact already on record in
`.reports/component-inventory.md` ("Not components" section) as a
component-parity gap. It is also a translation gap, because those three files
are three of this skill's non-code message sources and together own 10 of
upstream's 77 messages (2 of the 10, `New Window` and `Video Player`, are
already carried by other files the port does have, so they are not gaps):

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

Plus one genuine behavioural gap, independent of the missing-`data/` cause:
**`Installing…`** (`showtime/widgets/window.py:838`, the toast shown while a
missing codec is being installed) has no port site at all. This is not a
`data/` problem — it is the same gap `.reports/accountability-ensurance.md`
records against `window.rb:30-36`: the port never built the install-plugin
flow, so the toast that announces it has nothing to attach to.

## What the hand-census confirms is actually ported (69 of 77)

All of the following were checked by reading the call site, not by trusting
the grep:

- **`shortcuts_dialog.rb`'s `SECTIONS` table** carries 19 upstream strings
  (4 section titles — `General`, `Volume`, `View`, `Playback` — and 15 item
  titles) through `Translations.translate(title)` at lines 55 and 65. These
  did not show up in a naive `grep` for `Translations.translate("...")`
  because the argument is the loop variable, not a literal at the call site —
  the literals live in the table two lines up. Read individually, all 19
  match upstream's `showtime/gtk/shortcuts-dialog.blp` strings byte for byte.
- **`primary_menu.rb`'s `SECTIONS` table**, same shape: `_New Window`,
  `_Open…`, `Show in _Files`, `Take _Screenshot`, `_Keyboard Shortcuts`,
  `_About Video Player` — all 6, mnemonics and ellipsis character intact.
- **`restore_overlay.rb`**: `Resume` and `Start Again`, via
  `overlaid_label(text)` → `Translations.translate(text)` (line 178).
- **`about_dialog.rb`**: `translator-credits`, `Translate` (link label —
  see below), plus `APPLICATION_NAME`/`DEVELOPER_NAME`/`COMMENTS` constants
  resolved by reading the file; they hold the application name and developer
  credit strings, carried as marked, translated lookups rather than bare
  literals.
- Every other call site listed by the `grep` in `lib/showtime/*.rb` (window
  toasts, file-dialog filter names, the options popover's language/subtitle
  submenus and rotate/speed labels, the sound-options tooltip, the video
  page's button tooltips and the `“{}” codecs...` pair) matches its upstream
  msgid, including the one with embedded curly double-quotes.

## Extra: two port-only strings

- **`Open the app with a new window`** — `application.rb:79`, the `--new-window`
  CLI option's description. Upstream has the identical string at
  `showtime/main.py:64` (`new_window.description = "Open the app with a new
  window"`) but **does not mark it for translation** there either — it is a
  GLib `OptionEntry` description, which GLib's own `--help` machinery
  localizes separately from the app's `po/`. So this is not a message the
  port invented; it is a message upstream has and does not route through
  gettext, carried through the port's translation layer anyway. Harmless, and
  arguably better than upstream, but it is outside the 77-message count on
  both sides and is recorded here rather than silently folded into "ported".
- **`Translate`** — `about_dialog.rb:81`, the About dialog's link-button
  label. Upstream builds its About dialog with
  `Adw.AboutDialog.new_from_appdata`, which supplies this label itself (it is
  one of libadwaita's own built-in strings, translated by libadwaita's
  catalogue, not the app's). The port builds the dialog by hand and had to
  supply the label itself; routing it through `Translations.translate` is
  consistent with the rest of the file but the string was never upstream's to
  carry.

Neither is a regression and neither is counted toward "ported" or "gap" in
the 77-message total; both are listed because an extra string is an extra
string and the rule is to say so.

## What was actually run (Step 5)

```
nix develop --command ruby -e '
  $LOAD_PATH.unshift("lib"); require "showtime/translations"
  ENV["LANGUAGE"] = "de"; ENV["LC_ALL"] = "de_DE.UTF-8"
  puts Showtime::Translations.locale.inspect
  puts Showtime::Translations.translate("Watch Videos")
  puts Showtime::Translations.translate("Open…")
'
# => "de"
# => Videos ansehen
# => Öffnen …
```

This proves the lookup, plural-form parsing (`PLURAL_EXPRESSION`) and locale
selection all work against the real, copied `po/de.po`. **It does not prove a
widget shows German on screen** — that needs the app actually running headless
under `LANGUAGE=de` with a screenshot, which this round did not do. Report
that as the unrun half of Step 5, not as passed: the message-lookup layer is
verified; the GTK label actually displaying the looked-up string is not.

## Rules check against this skill

- Byte-identical msgids: verified by hand for all 69 ported rows above; no
  rewording found.
- No `n/a`/`by design`: the 8 gaps and the `Installing…` gap are stated as
  gaps, not waved off — the `data/`-absence cause is named, not used to close
  the row.
- Languages: 57/57, byte-identical `LINGUAS` and file set, confirmed by
  `diff`, not by eyeballing a count.
- Domain: does not match (`domain_matches: false` in the generated YAML is
  correct) — the port has no domain at all, which costs it `msgfmt -c`
  validation on the catalogue (nothing here ever compiles the `.po` files, so
  a syntactically broken one would only be caught by `Translations` raising
  at runtime, not by a build-time check). Recorded as an open item, not
  resolved.
