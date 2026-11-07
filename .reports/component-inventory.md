# showtime — upstream component inventory

Survey step for the full-parity Ruby GTK4/Libadwaita port. Upstream is the
PyGObject + blueprint app on `origin/main` (`showtime/`, `data/`, `po/`); the
port is this `ruby` branch (`lib/showtime/`).

Read with the `component-identification` skill: a component is a widget plus its
CSS classes, its signals, the actions it fires and the file that owns it. Upstream
splits almost every component across a `.py` and a `.blp`, so the rows below union
both halves of each pair.

## What exists on `ruby` today

**Stale as of `6de1bc6`** ("Port the MPRIS2 D-Bus interface"): the table and
the "16 exist / 2 missing" count below predate `3899b8f` ("Port the window
shell") and this round's MPRIS commit. `window.rb` (component 3) and
`mpris.rb` (component 14) both now exist, are `require_relative`'d from
`lib/showtime.rb`, and are driven by `test/drive_window.rb` (26 checks) and
`test/drive_mpris.rb` (16 checks) respectively, alongside `test/drive_placeholder.rb`
(16) and `test/drive_video_widgets.rb` (26) — 84 checks total, all passing
under `nix develop --command xvfb-run -a ruby test/drive_*.rb`. Every
component below is now implemented and wired; none of the "missing" or
"not mounted" labels in this file are current. `play.rb` and `video_page.rb`
are loaded and driven, not just parsed.

Re-checked at `b499202` ("Port components written during an interrupted run",
on top of "Inventory upstream components" and "Port the translations,
settings, stylesheet, icons, helpers and placeholder UI") — the rest of this
section is kept for its upstream-component detail, not for its status column.

| File | Lines | What it is |
|---|---:|---|
| `lib/showtime.rb` | 19 | requires every component below, `play.rb`/`video_page.rb` included |
| `lib/showtime/translations.rb` | 316 | translation layer |
| `lib/showtime/settings.rb` | 180 | the three `…State` keys + `playback_history.json` position history |
| `lib/showtime/utils.rb` | 178 | timestamp / title / screenshot helpers |
| `lib/showtime/style.rb` | 224 | the stylesheet as a `Gtk::CssProvider` |
| `lib/showtime/icons.rb` | 63 | the 8 app-shipped symbolic icons |
| `lib/showtime/primary_menu.rb` | 63 | the 6-item menu model |
| `lib/showtime/drag_overlay.rb` | 73 | drop-target overlay — mounted in `window.rb` as `toast_overlay.child` |
| `lib/showtime/sound_options.rb` | 174 | volume popover — mounted inside `video_page.rb` |
| `lib/showtime/options.rb` | 392 | playback-options popover — mounted inside `video_page.rb` |
| `lib/showtime/restore_overlay.rb` | 185 | resume/restart prompt — mounted inside `video_page.rb` |
| `lib/showtime/placeholder_page.rb` | 175 | welcome / error / missing-plugin states |
| `lib/showtime/video_page.rb` | 576 | player + overlays — required from `window.rb`, loaded and driven (26 checks in `drive_window.rb`/`drive_video_widgets.rb`) |
| `lib/showtime/play.rb` | 418 | GStreamer pipeline/bus — required from `window.rb` (`Window#play`), loaded and driven |
| `lib/showtime/shortcuts_dialog.rb` | 72 | the 4-section shortcuts dialog |
| `lib/showtime/about_dialog.rb` | 101 | About |
| `lib/showtime/application.rb` | 104 | the app singleton — **partial** (see component 1) |
| `lib/showtime/mpris.rb` | 429 | MPRIS2 D-Bus interface — required from `application.rb`, driven by `drive_mpris.rb` (16 checks) |
| `lib/showtime/window.rb` | 938 | the window shell — required from `application.rb`, driven by `drive_window.rb` (26 checks) |
| `lib/showtime/rb/version.rb` | 13 | gem version |
| `exe/showtime` | 6 | `Showtime::Application.new.build.run` |

So of the 18 components below, **all 18 exist as files, are `require_relative`'d
from `lib/showtime.rb` (transitively, through `application.rb` → `window.rb` →
`video_page.rb`), and are exercised by the four drive scripts** — 84 of 84
checks passing under `nix develop --command xvfb-run -a ruby test/drive_*.rb`.
Component 1 (`application.rb`) is the one exception: it exists and is wired,
but is genuinely partial — see its own section below for the named gaps.

The window shell (`window.rb`) now mounts everything: the placeholder page is
the opening stack child, and switching to a video swaps in `video_page.rb` with
its options/sound-options/restore-overlay children, driven by `play.rb`'s
GStreamer pipeline. `application.rb` no longer stands in for the window shell —
it delegates to `Window.new(app, settings:)` on activate — but it still creates
only 3 `app.*` actions (`quit`, `new-window`, `shortcuts`); the other 18 of
upstream's 21 `win.*` actions are created by `window.rb` itself, which this
report's earlier draft miscounted as application.rb's job. The six components
(5, 6, 7, 8, 9, 12) that the previous draft of this report listed as
"written but reachable from nothing" are now all reachable: `window.rb`
`require_relative`s and mounts every one of them, and the drive scripts above
exercise all six.

The port is namespaced (`module Showtime`, `lib/showtime/*.rb`) because the
branch is already packaged as a gem, so the house rule "one upstream source file
→ one `lib/<thing>.rb`" is read here as one upstream source file → one
`lib/showtime/<thing>.rb`.

## Upstream totals

- 5 Python widget/app source files, 4 blueprint files, 1 stylesheet
- 4 `Adw.StatusPage`s, 2 `Gtk.FileDialog`s, 1 menu model with 6 items, 1 popover menu with 4 sections
- 24 actions: 3 `app.*`, 21 `win.*` (3 of them stateful)
- 1 GSettings schema (`…State`: `end-timestamp-type`, `is-maximized`, `looping`) plus one enum
- 57 locales in `po/`
- 8 app-shipped icons in `data/icons/scalable/actions/`

## Components, in the order a user meets them

### 1. `showtime/main.py` (+ `showtime/__init__.py.in`) → `lib/showtime/application.rb` — the application singleton — **exists, partial**

| Widget / object | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.Application` | 1 | — | `window-removed`, `shutdown` | `HANDLES_OPEN` flag; port must use `Gtk::Application` (the Adwaita application binding is broken) |
| `Adw.StyleManager` | 1 | — | — | forces `PREFER_DARK` |

Actions: `app.new-window` (`<primary>n`), `app.quit` (`<primary>q`), `app.shortcuts`
(referenced by the menu and the shortcuts dialog; registered with the shortcuts
dialog). Signals it re-emits for MPRIS: `media-info-updated`, `state-changed`,
`volume-changed`, `rate-changed`, `seeked`. Also: `--new-window` / `-n` CLI option,
`[VIDEO FILES]` parameter string, `do_open` for file arguments, idle inhibitor
("Playing a video"), play-position history in `playback_history.json` (max 1000
entries, sha256 of the URI), `is-maximized` binding, rotating log file,
`Gst.init()`.

Gap, re-checked against the current `application.rb` and `window.rb`:
`application.rb` sets the dark colour scheme, loads the stylesheet and the
icons, and creates only the 3 `app.*` actions (`quit`, `new-window`,
`shortcuts`); `window.rb` now creates the other 18 of upstream's 21 `win.*`
actions (component 3 exists and owns them, so that part of the old gap is
closed). Still missing, confirmed by reading `application.rb` directly:
`HANDLES_OPEN` and `do_open` for file arguments passed on the command line
(the app has no code path that opens a file given on `argv`), the
`--new-window` / `-n` CLI option and `[VIDEO FILES]` parameter string, one
window per video (`app.activate` on `new-window` re-presents the single
memoized `Window`, it does not open a second one), the idle inhibitor
(`window.rb`'s own comment block names this as unported — no
`app.inhibit_win`/`uninhibit_win` counterpart exists), the
`playback_history.json` position history actually being read/written around
play/close (`settings.rb` defines the `HISTORY_FILE` constant but nothing in
`application.rb` or `window.rb` calls into it on save/restore), the rotating
log file feeding the About dialog's debug info, and `Gst.init()`. The five
MPRIS re-emit signals (`media-info-updated`, `state-changed`,
`volume-changed`, `rate-changed`, `seeked`) are not missing in the way the
previous draft of this report implied — `mpris.rb` reads them directly off
`play`/`window.rb`'s signals rather than off re-emitted `app.*` signals, which
is a different wiring than upstream's but not a gap `mpris.rb`'s own
16/16 drive checks miss.

### 2. `showtime/gtk/window.blp` (`menu primary_menu`) → `lib/showtime/primary_menu.rb` — the main menu — **exists**

| Item | Action | Notes |
|---|---|---|
| `_New Window` | `app.new-window` | |
| `_Open…` | `win.open-video` | |
| `Show in _Files` | `win.show-in-files` | `hidden-when: action-disabled` |
| `Take _Screenshot` | `win.screenshot` | `hidden-when: action-disabled` |
| `_Keyboard Shortcuts` | `app.shortcuts` | |
| `_About Video Player` | `win.about` | |

4 sections, 6 items. Used by two `Gtk.MenuButton`s (placeholder header and video
overlay), so it is one model with two consumers.

### 3. `showtime/widgets/window.py` + `showtime/gtk/window.blp` → `lib/showtime/window.rb` — the window shell — **exists, mounted, driven (26/26 in `drive_window.rb`)**

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.ApplicationWindow` | 1 | — | `realize` → `_on_realize`, `move-focus` → `_on_motion`, `notify::fullscreened`, `notify::paused` | 800×500, min 360×202 (16:9), `gravity: center`, title "Video Player" |
| `Adw.ToastOverlay` | 1 | — | — | hosts "Details copied", "Installing…", "Screenshot captured" (HIGH priority, "Show in Files" button) |
| `Gtk.Stack` (`stack`) | 1 | — | — | `placeholder_page` ⇄ `video_page` |
| `Adw.Breakpoint` | 1 | — | — | `min-width: 550px` → toolbar margins 24, restore bin margin 90 |
| `Gtk.FileDialog` (`open_video_dialog`) | 1 | — | — | filter "Video", `video/*` |
| `Gtk.FileDialog` (`choose_subtitles_dialog`) | 1 | — | — | filter "Subtitles": `application/x-subrip`, `text/x-ssa`, `text/vtt`; suffixes srt/ssa/ass/vtt |
| `Gtk.FileDialog` (screenshot save) | 1 | — | — | built in source, initial name `<title> <hh:mm:ss>.png` |
| `Adw.TimedAnimation` / `Adw.PropertyAnimationTarget` | n | — | — | window resize (500ms, `EASE_OUT_EXPO`) and every overlay fade |

Actions installed here (21, `win.` prefix) — **none of these names is a literal
the scan can see; they come from `_create_action` call sites**:

| Action | Accelerators | Notes |
|---|---|---|
| `close-window` | `<primary>w`, `q` | |
| `about` | — | opens the About dialog |
| `toggle-fullscreen` | `F11`, `f` | Escape exits (documented in the shortcuts dialog) |
| `toggle-playback` | `p`, `k`, `space` | |
| `increase-volume` | `Up` | +0.05 |
| `decrease-volume` | `Down` | −0.05 |
| `toggle-mute` | `m` | |
| `backwards` | `Left` | −10 s |
| `forwards` | `Right` | +10 s |
| `decrease-rate` | `bracketleft` | steps the rate toggle group |
| `increase-rate` | `bracketright` | |
| `screenshot` | `<primary><alt>s` | starts **disabled** |
| `show-in-files` | — | starts **disabled**; `Gtk.FileLauncher.open_containing_folder` |
| `open-video` | `<primary>o` | |
| `choose-subtitles` | — | |
| `select-subtitles` | — | stateful, `q` (uint16); `MAXUINT16` = None |
| `select-language` | — | stateful, `q` (uint16) |
| `toggle-loop` | — | stateful boolean, persisted to `looping` |

Repeaters: none. Conditional: `show-in-files` and `screenshot` are enabled only
once a video is loaded, which is what hides their menu items.

Note: upstream keeps the whole window tree in one 1200-line `.py` plus one
500-line `.blp`. The port splits the tree into the four files 3–6 below and keeps
`window.rb` as the shell (window, stack, toast overlay, actions, dialogs,
GStreamer wiring).

### 4. `showtime/gtk/window.blp` (`placeholder_page`) → `lib/showtime/placeholder_page.rb` — the no-video / error states — **exists**

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.ToolbarView` | 1 | — | — | |
| `Adw.HeaderBar` | 1 | — | — | |
| `Gtk.MenuButton` | 1 | — | — | primary, `open-menu-symbolic`, tooltip "Main Menu", `primary_menu` |
| `Gtk.WindowHandle` | 1 | — | — | |
| `Gtk.Stack` (`placeholder_stack`) | 1 | — | — | open ⇄ error ⇄ missing-plugin |
| `Adw.StatusPage` (open) | 1 | — | — | `video-x-generic-symbolic`, "Watch Videos", "Drag and drop videos here" |
| `Gtk.Button` (`button_open`) | 1 | `pill`, `suggested-action` | — | "Open…", `win.open-video` |
| `Adw.StatusPage` (error) | 1 | — | — | `dialog-error-symbolic`, "Unable to Play Video"; description is the GStreamer error |
| `Adw.StatusPage` (missing plugin) | 1 | — | — | `puzzle-piece-symbolic`, "Missing Plugin" |
| `Adw.PreferencesGroup` | 2 | — | — | built in source: `halign: center`, `width-request: 250`, `separate-rows` |
| `Adw.ButtonRow` | 2–4 | `suggested-action` (on "Try Again" / "Install Plugin") | `activated` | "Try Again", "Copy Technical Details"; and in the missing-plugin case "Install Plugin" and "Try Anyway" |

Conditional: the "Install Plugin" row only when `GstPbutils.install_plugins_supported()`;
"Try Anyway" only when the plugin set is *partially* missing. Three distinct
missing-plugin descriptions: `"{}" codecs are required to play this video`,
`No plugin available for this media type`, `Unable to install the required plugin`,
plus `The "{}" codecs required to play this video could not be found` when
installation is unsupported. Toasts: "Details copied", "Installing…".

### 5. `showtime/gtk/window.blp` (`video_page`) → `lib/showtime/video_page.rb` — the player and its overlays — **exists, mounted, driven**

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Gtk.WindowHandle` (`video_page`) | 3 | — | — | the page plus `header_handle_start` / `header_handle_end` |
| `Gtk.Overlay` | 1 | — | — | |
| `Gtk.GraphicsOffload` | 1 | — | — | `black-background: true` |
| `Gtk.Picture` | 1 | — | — | paintable from `gtk4paintablesink` |
| `Adw.Clamp` | 1 | `shade` | — | max 1920, tightening 1920; `shade` is the gradient scrim |
| `Gtk.Box` | 8 | `bottom-overlay-box` (name) | — | toolbar, controls, bottom overlay, timestamp, header start/end, resume/restart boxes |
| `Gtk.Button` (backwards) | 1 | `circular`, `highlighted`, `overlaid` | `win.backwards` | name `backwards-button`, a11y "Go Back 10 Seconds" |
| `Gtk.Button` (play) | 1 | `circular`, `highlighted`, `overlaid` | `win.toggle-playback` | name `play-button`, icon bound to `paused` → `media-playback-start-symbolic` / `…-pause-symbolic`, a11y label swaps "Play"/"Pause" |
| `Gtk.Button` (forwards) | 1 | `circular`, `highlighted`, `overlaid` | `win.forwards` | name `forwards-button`, a11y "Go Forward 10 Seconds" |
| `Gtk.Button` (fullscreen) | 1 | `circular`, `highlighted`, `overlaid` | `win.toggle-fullscreen` | icon bound to `fullscreened`, tooltip "Toggle Fullscreen" |
| `Gtk.Label` (`title_label`) | 1 | `title-4`, `overlaid` | — | ellipsized video title |
| `Gtk.Scale` (`seek_scale`) | 1 | `highlighted`, `overlaid` | `change-value` → `_seek` | adjustment 0–500 (×500 so seeking isn't rough), labelled by `title_label` |
| `Gtk.Label` (`position_label`) | 1 | `caption-heading`, `numeric`, `timestamp`, `overlaid` | — | "0:00" |
| `Gtk.Button` (`end_timestamp_button`) | 1 | `caption-heading`, `numeric`, `timestamp`, `highlighted`, `overlaid` | `clicked` → `_cycle_end_timestamp_type` | name `end-timestamp-button`, tooltip "Toggle Duration/Remaining", persists `end-timestamp-type` |
| `Gtk.WindowControls` | 2 | `overlaid` | — | start and end, each hidden when empty |
| `Adw.Spinner` | 1 | `overlaid` | — | 18×18, opacity animated while buffering |
| `Gtk.MenuButton` (`video_primary_menu_button`) | 1 | `circular`, `highlighted`, `overlaid` | — | primary, `primary_menu`, tooltip "Main Menu" |
| `Gtk.GestureClick` | 2 | — | button 1 `released` → `_on_primary_click_released`; button 3 `pressed` → `_on_secondary_click_pressed` | controller, not a widget |
| `Gtk.EventControllerMotion` | 1 | — | `motion` → `_on_motion` | controller; drives the auto-hide of every overlay |

Behaviour that no widget declares: overlays fade in/out on motion and hide after
an idle timeout; the window resizes itself to the video (40% of screen area, 80%
on screens ≤ 1280×1024); rotation via `Gtk.Picture` transform; `do_size_allocate`
override.

### 6. `showtime/gtk/window.blp` (`restore_breakpoint_bin`) → `lib/showtime/restore_overlay.rb` — resume-or-restart prompt — **exists, mounted, driven**

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.BreakpointBin` | 1 | — | — | 1×1 request, opacity 0 until a saved position exists |
| `Gtk.Button` (`resume_button`) | 1 | `overlaid`, `highlighted` | `clicked` → `_resume` | labelled by `resume_label` |
| `Gtk.Button` (`restart_button`) | 1 | `overlaid`, `highlighted` | `clicked` → `_play_again` | labelled by `restart_label` |
| `Gtk.Image` | 2 | `overlaid` | — | `media-playback-start-symbolic`, `arrow-circular-top-right-symbolic` (app icon) |
| `Gtk.Label` | 2 | `overlaid` | — | "Resume", "Start Again" |
| `Adw.Breakpoint` | 2 | — | — | ≤320×720 hides both labels; ≥320px high switches both buttons to 126×120 vertical |

### 7. `showtime/widgets/sound_options.py` + `showtime/gtk/sound-options.blp` → `lib/showtime/sound_options.rb` — volume popover — **exists, mounted, driven**

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.Bin` (template) | 1 | — | `schedule-volume-change(f)` (own signal) | properties `mute` (default true), `volume` |
| `Gtk.MenuButton` | 1 | `circular`, `highlighted`, `overlaid` | — | icon bound to `_get_volume_icon(mute, volume)`: muted / high (>0.7) / medium (>0.3) / low; a11y "Adjust Volume"; `direction: up` |
| `Gtk.Popover` | 1 | — | — | 250 wide |
| `Gtk.ToggleButton` | 1 | `circular`, `flat` | `active` ⇄ `mute` | `audio-volume-muted-symbolic`, a11y "Mute/Unmute" |
| `Gtk.Scale` | 1 | — | `notify::value` → `_schedule_volume_change` | adjustment 0–1, step 0.2 |

### 8. `showtime/widgets/options.py` + `showtime/gtk/options.blp` → `lib/showtime/options.rb` — playback options popover — **exists, mounted, driven**

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Adw.Bin` (template) | 1 | — | `rotate-left`, `rotate-right` (own signals) | property `rate` (string) |
| `Gtk.MenuButton` | 1 | `circular`, `highlighted`, `overlaid` | — | `settings-symbolic` (app icon), `direction: up`, a11y "Playback Options" |
| `Gtk.ShortcutController` | 1 | — | `<shift>F10` → `activate` | scope managed |
| `Gtk.PopoverMenu` | 1 | — | `closed` (when reparented for right-click) | `flags: nested`; reparented to the window on secondary click with `has_arrow: false` |
| menu model | 1 | — | — | 4 sections: `_Language` submenu, `_Subtitles` submenu; `_Repeat` → `win.toggle-loop`; "Rotate" inline-buttons section; speed section |
| `Gtk.Button` (rotate left) | 1 | `flat` | `clicked` → `_rotate_left` | custom slot `rotate-left`, `object-rotate-left-symbolic`, tooltip "Rotate Left" |
| `Gtk.Button` (rotate right) | 1 | `flat` | `clicked` → `_rotate_right` | custom slot `rotate-right`, tooltip "Rotate Right" |
| `Gtk.Label` | 1 | `heading` | — | "Playback Speed", in the `speed` custom slot |
| `Adw.ToggleGroup` | 1 | `round`, `flat` | `active-name` ⇄ `rate` | homogeneous |
| `Adw.Toggle` | 5 | — | — | 0.5× 1.0× 1.25× 1.5× 2.0× |

Repeaters (built in source, invisible to any scan): the language menu gets one
item per audio stream (`win.select-language(uint16 N)`), labelled
`<language> - <title>`, falling back to "Undetermined, {} Channel(s)" /
"Undetermined", with "No Audio" pointing at `nonexistent.action` when there are
none; the subtitles menu gets "None" (`MAXUINT16`), one item per subtitle stream
("Undetermined Language" fallback), then "Add Subtitle File…" →
`win.choose-subtitles`.

### 9. `showtime/widgets/drag_overlay.py` → `lib/showtime/drag_overlay.rb` — drop target overlay — **exists, mounted, driven**

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.Bin` (subclass) | 1 | css name `showtime-drag-overlay`, `drop-widget` where used | — | properties `child`, `overlayed`, `drop_target` |
| `Gtk.Overlay` | 1 | — | — | |
| `Gtk.Revealer` | 1 | — | — | `CROSSFADE`, not targetable, revealed on `notify::current-drop` |
| `Gtk.DropTarget` | 1 | — | `drop` → `_on_drop` | formats `GFile`, action copy (declared in `window.blp`) |
| `Adw.Bin` (overlayed) | 1 | `background` | — | not targetable |
| `Adw.StatusPage` | 1 | `showtime-dragging-area-highlight` | — | "Drop Video to Play", `video-x-generic-symbolic` |

Taken from Loupe upstream; the port writes it from scratch.

### 10. `showtime/gtk/shortcuts-dialog.blp` → `lib/showtime/shortcuts_dialog.rb` — keyboard shortcuts — **exists**

Standalone blueprint object with no backing source file, so it is its own unit.
`Adw.ShortcutsDialog` with 4 `Adw.ShortcutsSection`s and 15 `Adw.ShortcutsItem`s:

- **General** — Show Shortcuts (`app.shortcuts`), Open Video (`win.open-video`), Video Options (`<shift>F10`), Take Screenshot (`win.screenshot`), New Window (`app.new-window`), Close Window (`win.close-window`), Quit (`app.quit`)
- **Volume** — Increase Volume, Decrease Volume, Mute/Unmute
- **View** — Toggle Fullscreen (`win.toggle-fullscreen`), Exit Fullscreen (`Escape`)
- **Playback** — Play/Pause, Go Back 10 Seconds, Go Forward 10 Seconds

In the Ruby bindings `Adwaita::ShortcutsItem.new` takes its title and accelerator
**positionally**; items whose accelerator comes from an action name have to be
given the accelerator this port actually binds.

### 11. `showtime/widgets/window.py` (`_present_about_dialog`) + `data/org.gnome.Showtime.metainfo.xml.in` → `lib/showtime/about_dialog.rb` — About — **exists**

`Adw.AboutDialog.new_from_appdata`, developer "kramo", designers Tobias Bernard,
Allan Day, kramo, copyright "© 2024-2025 kramo", `translator-credits`, debug info
read from the rotating log file with `debug_info_filename` set. The port has no
GResource, so it builds the dialog's fields directly rather than from appdata.

### 12. `showtime/play.py` → `lib/showtime/play.rb` — GStreamer pipeline and bus — **exists, required, driven**

Not a widget: `gtk4paintablesink` (optionally wrapped in `glsinkbin`), `GstPlay.Play`,
and a `Messenger` GObject re-emitting 10 bus signals (`state-changed`,
`duration-changed`, `position-updated`, `seek-done`, `media-info-updated`,
`volume-changed`, `end-of-stream`, `warning`, `error`, `missing-plugin`), plus
subtitle font description tracking `gtk-xft-dpi` and the qtdemux unknown-fourcc
filter. Everything the video page shows is driven from here, so it is a hard
prerequisite, not an optional extra.

### 13. `showtime/utils.py` → `lib/showtime/utils.rb` — helpers — **exists**

`screenshot` (paintable → `Gdk.Texture` via `Gtk.Snapshot` and `Graphene.Rect`),
`nanoseconds_to_timestamp` (`1:23` / `1:23:45` / forced `01:23:45`), `get_title`
(media-info title, ignoring the literals "Video"/"Audio", else the URI stem),
`lookup_action`, `get_subtitle_font_desc`.

### 14. `showtime/mpris.py` → `lib/showtime/mpris.rb` — MPRIS2 D-Bus interface — **exists, required, driven (16/16 in `drive_mpris.rb`)**

`org.mpris.MediaPlayer2` and `…MediaPlayer2.Player` on the session bus: Raise,
Quit, Play, Pause, PlayPause, Stop, Seek, SetPosition, plus the metadata, rate,
volume and playback-status properties. Taken from GNOME Music upstream. Not
user-visible inside the window, but it is what makes the system media controls
work, so it is part of parity.

### 15. `showtime/gtk/style.css` → `lib/showtime/style.rb` — the stylesheet — **exists**

Must ship as a `Gtk::CssProvider` loaded from a string, since the port has no
GResource. Defines the classes the widget tables above reference and nothing else
does: `highlighted`, `overlaid`, `shade`, `timestamp`, `selection-toolbar`,
`showtime-dragging-area-highlight`, `drop-widget`, and rules keyed on the widget
names `video-page`, `play-button`, `backwards-button`, `forwards-button`,
`bottom-overlay-box`, `end-timestamp-button`. Also a `prefers-contrast: more`
block. Dropping this file is how the port ends up a grey copy: the overlay
buttons lose their drop shadows and the video scrim disappears.

### 16. `data/org.gnome.Showtime.gschema.xml.in` → `lib/showtime/settings.rb` — persisted state — **exists**

Schema `…State`: `end-timestamp-type` (enum Duration/Remaining), `is-maximized` (b),
`looping` (b). `settings.rb` now also carries the playback-position history file
(`playback_history.json`, sha256-of-URI keys, 1000-entry cap) that `main.py`
keeps beside the schema; `play_position`/`save_play_position` are what the
restore-overlay prompt (component 6) would read once it is wired to a window.

### 17. `data/icons/scalable/actions/*.svg` + `showtime/showtime.gresource.xml.in` → `lib/showtime/icons.rb` — app-shipped icons — **exists**

8 symbolic icons that are **not** in the system theme and are referenced by name
from the widget tables above: `settings-symbolic`, `puzzle-piece-symbolic`,
`skip-backwards-10-symbolic`, `skip-forward-10-symbolic`, `speedometer2/3/4-symbolic`,
`arrow-circular-top-right-symbolic`. Without a loader that adds a search path (or
inline `Gtk::IconTheme` resources) the play controls, the options button and the
missing-plugin page all render as broken-image icons.

### 18. `po/` (57 locales, `po/POTFILES.in`) → `lib/showtime/translations.rb` — translations — **exists**

Upstream marks its strings with `_()` / `ngettext()` across the 4 blueprint files
and 4 Python files listed in `POTFILES.in`. The port currently has no translation
layer at all; see the `translation-parity` skill before deciding the shape.

## Not components

- `meson.build`, `meson.options`, `po/meson.build`, `data/meson.build`, `showtime/meson.build`, `pyproject.toml`, `build-aux/flatpak/*` — build system; the port is a gem.
- `data/org.gnome.Showtime.desktop.in`, `…service.in`, `…metainfo.xml.in` — packaging metadata. The desktop file's `new-window` action and its MIME list are behaviour the port's CLI has to match; the metainfo is read by the About dialog (component 11).
- `showtime/showtime.in`, `showtime/__builtins__.pyi`, `showtime.doap`, `data/screenshots/1.png`, app icons under `data/icons/hicolor/`.

## Status of the former blockers, and what is actually left

1. ~~**GStreamer.**~~ Resolved: `nix develop --command xvfb-run -a ruby test/drive_window.rb` (and the other three drive scripts) load `play.rb`/`video_page.rb` under the real dev shell and pass, so the typelibs and `gtk4paintablesink` are confirmed present.
2. ~~**No GResource.**~~ Resolved: `style.rb` loads the stylesheet from a string through `Gtk::CssProvider` and `icons.rb` adds a search path.
3. ~~**Blueprint property bindings.**~~ Resolved as far as the drive scripts check: `video_page.rb`/`window.rb` wire `notify::` connections in place of every `bind` expression upstream's blueprint used (play/pause icon, mute toggle, rate group), and `drive_window.rb`/`drive_video_widgets.rb` exercise them without crashing or looping.
4. ~~**MPRIS.**~~ Resolved: `mpris.rb` exists, is required from `application.rb`, and `drive_mpris.rb` passes 16/16, including the D-Bus method-call and property-get/set paths.
5. ~~**Mounting order.**~~ Resolved: `window.rb` exists and requires/mounts every one of components 5, 6, 7, 8, 9 and 12; `lib/showtime.rb` requires all of them.

**Component 1, resolved as far as the single-window architecture goes**:
`application.rb` now sets `:handles_open`, adds the `--new-window`/`-n` main
option and `[VIDEO FILES]` parameter string, and wires the `open` signal (for
CLI file arguments) and `handle-local-options` (upstream's
`do_handle_local_options`: a file-less second launch registers, finds the
first instance already running, and warns instead of re-presenting). `Gst.init`
already happens idempotently inside `Play#build`. The idle inhibitor
(`Window#inhibit_idle`/`#uninhibit_idle`, held on `@app` while playing,
released on pause/stop/close) and the playback-history save on window close
(`close-request` → `save_current_play_position`, `uninhibit_idle`,
`play.stop`) are both wired. Logging now goes through `Showtime::Log`, a
console-plus-1MB-rotating-file logger under `$XDG_STATE_HOME/showtime`,
matching upstream's `RotatingFileHandler`.
One piece is intentionally **not** ported: upstream opens one OS window per
video file (`do_open` calling `do_activate` once per `GFile`). This port's
`Window` is a single memoized controller per `Application`, by original
design (see `window.rb`'s class comment on the retry-in-place behaviour), so
multiple CLI file arguments play the last file in that one window rather than
opening several windows. Making that true would mean turning `Window` from a
singleton into one instance per `activate`/`open` call, which is a larger
change than this round's remaining budget — noted here rather than stubbed.
