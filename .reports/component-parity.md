# Component parity — showtime

| | |
|---|---|
| Upstream | `main` @ `f28a1d4` |
| Port | `ruby` @ `e191199` |
| Units with full (4-axis) parity | 16 / 18 |
| Units with an open gap | 2 / 18 — #1/#3/#5 `application.rb`/`window.rb` (single-window architecture), and a gap this report's unit list previously had no row for at all: upstream's `data/` directory (desktop entry, AppStream metainfo, GSettings schema) has no port counterpart |

This builds on `.reports/component-inventory.md` and the prior round's
`component-parity` (written at `ruby` @ `47105ff`), re-checked unit by unit
against the four axes (count, style, behaviour, text) after the two commits
made since: `6f102ac` (ports the missing-plugin Install flow) and `e191199`
(drives it for real in `test/drive_window.rb`).

## What changed since the last round: the install-plugin gap is now closed

The previous round's two named gaps for unit 3/5 (`window.rb`) were
retry-in-place and the install-plugin flow. The second is now built and
verified, not just claimed:

| Behaviour | Upstream | Port | Verdict |
|---|---|---|---|
| Install-plugin flow: `Gtk.Button` → PackageKit install → "Installing…" toast → re-probe | `window.py:795-850` | `window.rb:445-494` (`on_missing_plugin` → `install_callback` → `install_plugin` → `on_install_done`), `placeholder_page.rb`'s `button_row` gains `disable_on_activate` so a second click can't race the first install | **parity** |

Verified three ways, not one:
1. Read `window.rb:445-494` directly — `install_callback` gates on
   `GstPbutils.install_plugins_supported`, `install_plugin` calls
   `GstPbutils.install_plugins_async` with the real installer detail and
   shows `Translations.translate("Installing…")` as a toast, and
   `on_install_done` has the same three-way branch upstream's
   `window.py:815-830` has (success → `Gst.update_registry` + `try_again`;
   `NOT_FOUND` → "no plugin available" message; anything else → "install
   failed" message).
2. Read `placeholder_page.rb` — the button row only renders when
   `on_install` is non-nil, and `install_callback` now returns a real
   lambda whenever `GstPbutils.install_plugins_supported` is true, so the
   button appears on the systems upstream would show it on, not on none.
3. Ran `test/drive_window.rb` myself (`nix develop --command xvfb-run -a
   ruby test/drive_window.rb`) — checks 12-17 fire a genuine
   `GstPbutils` missing-decoder bus message through `Play`'s messenger (the
   same path `wire_play` registers in production) and drive
   `on_install_done`'s `NOT_FOUND`/`ERROR` branches with the real enum
   values `install_plugins_async`'s callback would hand them (this Xvfb
   environment has no PackageKit installer to actually call async against,
   which the drive script says plainly rather than faking a pass around
   it). Result: `41 of 41 checks passed`, `DRIVE OK`.

## Gap #1 (carried over, still open): single-window architecture

| Behaviour | Upstream | Port | Verdict |
|---|---|---|---|
| Every OS-window-opening action (`new-window`, each CLI file arg, retry-after-error) opens a **new** `Window` | `main.py:do_activate` has no reuse branch; `window.py:883-888`'s `_try_again` calls `do_activate` then closes the old window | `Window` is a single instance memoized per `Application`; `new-window`, CLI args, and retry all re-present/replay the same one | **gap** |

Unchanged from the last round. `window.rb`'s own class comment now states
this accurately (no "intentionally" framing — see
`.reports/accountability-ensurance.md` for what changed and why it matters)
but the behaviour itself is not built. A user who opens a second video via
`new-window` while one is already playing gets the window re-presented, not
a second window with the first video still playing in its own window, which
is upstream's actual behaviour.

## Gap #2 (new to this report, previously under-named): `data/` has no port counterpart

Upstream ships three non-code files this port has no equivalent for at all:

| File | Purpose | Port |
|---|---|---|
| `data/org.gnome.Showtime.desktop.in` | Desktop launcher entry (name, exec, icon, keywords) | — none |
| `data/org.gnome.Showtime.metainfo.xml.in` | AppStream metadata (description, screenshots, release notes) | — none |
| `data/org.gnome.Showtime.gschema.xml.in` | GSettings schema definitions | — none (`settings.rb` is a JSON-backed shim with the same key names, not the schema file itself) |

This was previously folded entirely into `.reports/translation-parity.md`'s
8-message gap count and a one-line "not components" mention in
`component-inventory.md`, with no row of its own in either inventory or
parity report. That undercounts its scope: it is not only a translation
gap (10 lost msgids), it is a missing deliverable in its own right — no
`.desktop` entry means the app has no discoverable launcher metadata, and
no `.metainfo.xml.in` means no AppStream listing. The house pattern this
fork should be following ships these: the pilot port, `gnome-contacts-rb`,
has its own `data/org.gnome.ContactsRb.desktop.in.in` and
`.metainfo.xml.in.in` (confirmed by listing that repo's `data/` directory
directly). `showtime-rb`'s `data/` directory contains only the icon SVGs.

## Units with parity (16)

Units 2, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 are unchanged from the
last round's "exists, mounted, driven, text matches" findings. Two items the
last round's inventory left as open "needs a closer read" questions are now
closed, re-verified this round by reading the code rather than carrying the
open question forward again:

- `app.shortcuts` is installed on the application (`application.rb:117`),
  not shadowed by any window-level action of the same name — confirmed by
  grepping every `lib/showtime/*.rb` file for the string `"shortcuts"` as an
  action name; one hit.
- `Window`'s upstream `rate` `GObject.Property` setter (pops the options
  popover down, emits `rate-changed`) is reproduced across
  `Options#rate=` (`options.rb:85-90`, does the popdown) and
  `Application#rate=`/MPRIS's `Rate` property-set branch
  (`application.rb:105-106`, `mpris.rb:242-243`) — same net effect, split
  differently across files, verified by reading all three rather than
  trusting the "split differently" framing on its own.
- `style.rb`'s CSS is byte-identical to upstream's `style.css` (diffed, not
  eyeballed — see `component-identification`).

Unit 18 (translations) is the mechanism, not a widget, and is covered in
full by `.reports/translation-parity.md`.

## Rules check against this skill

- Reported per unit, not as an app-wide total: two open units are named,
  not folded into "16/18 roughly fine".
- Every "parity" row cites what was read or run, including re-running
  `test/drive_window.rb` this round rather than reusing the prior round's
  number.
- The newly-named `data/` gap is reported as its own row with its own
  evidence (the pilot port's `data/` directory), not merged into the
  translation report's count where it was previously easy to miss.
