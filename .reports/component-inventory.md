# Showtime component inventory

Surveyed against `origin/main` (upstream, PyGObject/Blueprint) from the `ruby`
branch's `lib/` (the port). This is a survey only — no app code was written for
this report.

Upstream unit = one Python class/module, together with the `.blp` template (if
any) that backs it. Port unit = the `lib/showtime/*.rb` file it maps to.

## Application class

| Upstream | Port | Kind | Present |
|---|---|---|---|
| `showtime/main.py` (`Application(Adw.Application)`) | `lib/showtime/application.rb` | application | yes |
| `showtime/mpris.py` (`MPRIS`) | `lib/showtime/mpris.rb` | service object (MPRIS D-Bus) | yes |

`Application` actions found in `main.py` (`app.*`): `new-window`
(`<primary>n`), `quit` (`<primary>q`). `shortcuts` is installed by the window
port's `application.rb` as `app.shortcuts` (upstream wires the same action
from the primary menu, defined via `_create_action` convention carried over
to the window/app split in the port). All three are present in
`lib/showtime/application.rb:115-117`.

## Main window

| Upstream | Port | Kind | Present |
|---|---|---|---|
| `showtime/widgets/window.py` (`Window(Adw.ApplicationWindow)`) | `lib/showtime/window.rb` | window | yes |
| `showtime/gtk/window.blp` (`template $Window`) | `lib/showtime/window.rb` (+ split-outs below) | window template | yes |

`window.blp`'s template is large and the port splits its sub-trees into their
own files, matching the "one upstream file maps to one `lib/*.rb`" rule only
loosely here because upstream itself keeps everything in one `.blp`. The port
instead gives each named sub-tree its own file:

| Sub-tree in `window.blp` | Port file | Kind | Present |
|---|---|---|---|
| `placeholder_page` (Adw.ToolbarView + its 3 `Adw.StatusPage`s: open/error/missing-plugin) | `lib/showtime/placeholder_page.rb` | page / empty+error states | yes |
| `video_page` (Overlay: controls, seek scale, timestamp row, header handles, picture) | `lib/showtime/video_page.rb` | page | yes |
| `restore_breakpoint_bin` / `restore_box` (resume / start-again prompt) | `lib/showtime/restore_overlay.rb` | overlay / dialog-like prompt | yes |
| `primary_menu` (menu model: New Window, Open, Show in Files, Screenshot, Keyboard Shortcuts, About) | `lib/showtime/primary_menu.rb` | menu | yes |
| drop target / drag overlay wiring (`$DragOverlay drag_overlay`) | `lib/showtime/drag_overlay.rb` (port of `showtime/widgets/drag_overlay.py`) | widget (Adw.Bin + Overlay + Revealer) | yes |

### Window actions (`win.*`, from `Window._create_actions` in `window.py:911-1026`)

| Action | Accelerators | Port (`lib/showtime/window.rb`) | Present |
|---|---|---|---|
| `close-window` | `<primary>w`, `q` | line 824 | yes |
| `about` | — | line 825 | yes |
| `toggle-fullscreen` | `F11`, `f` | line 826 | yes |
| `toggle-playback` | `p`, `k`, `space` | line 827 | yes |
| `increase-volume` | `Up` | line 828 | yes |
| `decrease-volume` | `Down` | line 829 | yes |
| `toggle-mute` | `m` | line 830 | yes |
| `backwards` | `Left` | line 831 | yes |
| `forwards` | `Right` | line 832 | yes |
| `decrease-rate` | `bracketleft` | line 833 | yes |
| `increase-rate` | `bracketright` | line 834 | yes |
| `screenshot` (disabled by default) | `<primary><alt>s` | line 835 | yes |
| `show-in-files` (disabled by default) | — | line 836 | yes |
| `open-video` | `<primary>o` | line 837 | yes |
| `choose-subtitles` | — | line 838 | yes |
| `select-subtitles` (stateful, `q`) | — | lines 863-876 | yes |
| `select-language` (stateful, `q`) | — | lines 881-890 | yes |
| `toggle-loop` (stateful, bool) | — | lines 895-907 | yes |

All 17 window actions from upstream are present in the port with matching
accelerators.

### Window signals (`window.py:125-128`)

`media-info-updated`, `volume-changed`, `rate-changed`, `seeked` — relayed
by `Application` to app-level signals of the same name when the emitting
window is the active one. Present in both `lib/showtime/window.rb` and
`lib/showtime/application.rb`.

## Dialogs

| Upstream | Port | Kind | Present |
|---|---|---|---|
| About dialog (built in `window.py`'s `_present_about_dialog`, no separate `.blp`) | `lib/showtime/about_dialog.rb` | dialog (`Adw.AboutDialog`) | yes |
| `showtime/gtk/shortcuts-dialog.blp` (`Adw.ShortcutsDialog shortcuts_dialog`, 4 sections / 14 items) | `lib/showtime/shortcuts_dialog.rb` | dialog | yes |
| `open_video_dialog` / `choose_subtitles_dialog` (`Gtk.FileDialog`, declared at the bottom of `window.blp`) | built inline in `lib/showtime/window.rb` (`open_video`, `open_choose_subtitles`) | file dialogs | yes |

## Composite widgets

| Upstream | Port | Kind | Present |
|---|---|---|---|
| `showtime/widgets/options.py` + `showtime/gtk/options.blp` (`$Options: Adw.Bin`) | `lib/showtime/options.rb` | popover menu widget (language/subtitles submenus, repeat toggle, rotate buttons, speed `Adw.ToggleGroup`) | yes |
| `showtime/widgets/sound_options.py` + `showtime/gtk/sound-options.blp` (`$SoundOptions: Adw.Bin`) | `lib/showtime/sound_options.rb` | popover menu widget (mute toggle, volume `Gtk.Scale`) | yes |
| `showtime/widgets/drag_overlay.py` (`DragOverlay(Adw.Bin)`, ported from Loupe) | `lib/showtime/drag_overlay.rb` | widget (Overlay + Revealer, drop target) | yes |

## Non-widget / support layers

| Upstream | Port | Kind | Present |
|---|---|---|---|
| `showtime/play.py` (`Messenger`, `gst_play_setup`, GstPlay wiring) | `lib/showtime/play.rb` | playback engine wrapper | yes |
| `showtime/mpris.py` (`MPRIS` D-Bus service) | `lib/showtime/mpris.rb` | service | yes |
| `showtime/utils.py` (`get_title`, `lookup_action`, `nanoseconds_to_timestamp`, `screenshot`) | `lib/showtime/utils.rb` | helpers | yes |
| `showtime/__init__.py` (app constants: `APP_ID`, `VERSION`, `PREFIX`, `PROFILE`, `system`, `logger`, `log_file`, `state_settings`) | `lib/showtime/log.rb`, `lib/showtime/icons.rb`, settings/constants spread across `lib/showtime.rb` and `lib/showtime/rb.rb`/`rb/version.rb` | module constants / logging | yes |
| `showtime/gtk/style.css` | `lib/showtime/style.rb` | stylesheet (CSS classes: `drop-widget`, `background`, `showtime-dragging-area-highlight`, `highlighted`, `overlaid`, `timestamp`, etc.) | yes |
| `data/org.gnome.Showtime.gschema.xml.in` (schemas `org.gnome.Showtime` (empty) and `org.gnome.Showtime.State`: `end-timestamp-type` enum, `is-maximized` bool, `looping` bool) | `lib/showtime/settings.rb` | GSettings shim (JSON-backed) | yes |
| `showtime/showtime.gresource.xml.in` (bundles the `.ui`/`.blp`-compiled resources, icons, CSS) | n/a — port has no GResource step; widgets built declaratively in Ruby | build manifest | n/a (by design) |
| `po/*.po` (57 locales listed in `po/LINGUAS`) + `po/POTFILES.in` | `lib/showtime/translations.rb` (parses `po/*.po` directly, with its own Plural-Forms evaluator) | i18n | yes |

## Actions/components not yet confirmed covered

- `app.shortcuts`: confirmed wired in `application.rb:117`, but double-check
  it is installed on the **application** (as upstream's primary menu expects
  `app.shortcuts`) and not shadowed by a window-level action of the same name.
- Upstream's `Window.mute`/`Window.rate`/`Window.paused` are `GObject.Property`
  accessors with custom getter/setter side effects (e.g. `rate` setter pops
  down `options.popover` and emits `rate-changed`). Confirm
  `lib/showtime/window.rb`'s equivalent accessors reproduce those side
  effects, not just the value storage — this needs a closer read than this
  survey did, since it is behavioural parity rather than a missing file.
- `showtime/gtk/style.css`'s exact class list versus `lib/showtime/style.rb`
  was not diffed rule-by-rule in this pass; the mapping exists but a
  class-by-class comparison is left to the parity pass.

## Summary

Every upstream user-facing component — window, its three placeholder states,
the video playback page, the resume/restart overlay, both popover option
widgets, the drag-and-drop overlay, the about dialog, the shortcuts dialog,
the two file-chooser dialogs, the primary menu, all 17 window actions, the 3
app actions, GSettings-backed state, MPRIS, and the full `po/` catalogue — has
a corresponding file already present on `lib/` on the `ruby` branch. No
widget, dialog, menu, action or settings key found in `origin/main` is
missing a `lib/showtime/*.rb` counterpart.

This means the next useful pass on this fork is **not** scaffolding new files
but a `component-parity`-style read-through of the existing pairs (CSS classes,
dynamic icon/state bindings, breakpoint setters, and the two `GObject.Property`
side-effect setters flagged above) to confirm behavioural fidelity rather than
mere presence.
