# Component identification — showtime

| | |
|---|---|
| Upstream | `main` @ `f28a1d4` |
| Port | `ruby` @ `e191199` |

Re-ran Step 1 of the skill (locate every upstream `.blp`/`.ui` template and
its backing source, confirm the file mapping) against `origin/main` and
cross-checked it against the inventory already on this branch,
`.reports/component-inventory.md`. That file is the canonical unit list — 18
components, file-to-file mapped, widget/CSS/signal tables per unit. This
round re-verifies it is still accurate after the commits made since the last
parity round (`6f102ac` "Port the missing-plugin Install flow",
`e191199` "Drive the real missing-plugin/install-result path") and finds one
new thing to name that none of the five existing reports surfaced before:
upstream's `data/` directory (desktop entry, AppStream metainfo, GSettings
schema) has **no corresponding unit in the inventory at all**, not even as a
named gap — it is mentioned only as a side-note under "Not components" and
inside the translation report's 8-message count. That undercounts it: the
pilot port (`gnome-contacts-rb`) ships a `data/` directory with its own
`.desktop.in.in` and `.metainfo.xml.in.in`, so this is not a file type the
house style treats as out of scope for a Ruby port — `showtime-rb`'s `data/`
contains only the icon SVGs, nothing else. See `component-parity` for the
gap row this should have had from the start.

## Re-verified: the install-plugin flow is now a real, built component

The previous round's identification correctly flagged the "Install Plugin"
`Adw.ButtonRow` as a sub-component the old inventory's unit-4 table
undercounted, because the port's call site never supplied the callback that
would make the button appear. That finding is now stale in a good way:
`window.rb:464-467`'s `install_callback` does gate on
`GstPbutils.install_plugins_supported`, `install_plugin` (`:473-477`) drives
`GstPbutils.install_plugins_async` and shows the "Installing…" toast, and
`on_install_done` (`:482-494`) implements the three-way branch (success /
not-found / other failure) upstream's `window.py:815-830` has. Confirmed by
reading the code directly, not by trusting the commit message that claims it,
and confirmed again by running `test/drive_window.rb`, whose checks 12-17 now
fire a real `GstPbutils` missing-decoder message through `Play`'s messenger
and drive `on_install_done`'s NOT_FOUND/ERROR branches with the real enum
values (`DRIVE OK`, reproduced this round).

## Re-verified: the single-window architecture gap is still real and is now described honestly

`window.rb`'s class comment no longer says "intentionally not ported" (the
construction the last `accountability-ensurance` round flagged as the most
serious finding in that round). It now reads: "Nothing in `ruby-gnome` stops
the multi-window architecture from being built; it is simply not done yet."
That is an accurate description of a real, still-open gap — upstream's
`do_activate` constructs a fresh `Window` on every call (`main.py:137-139`,
no reuse branch), so `new-window`, each CLI file argument, and a failed
stream's "try again" all open a second OS window upstream; the port's single
memoized `Window` never does. The wording fix is real but the underlying
gap is not closed — see `component-parity` unit 1 and unit 3/5.

## Everything else

The remaining components' tables were spot-checked again this round for two
units not checked by name in the last identification pass — unit for
`style.rb` (CSS classes) and the `Window#rate`/`Options#rate=` accessor
chain the previous inventory round flagged as "needs a closer read" and
never closed out:

- `lib/showtime/style.rb`'s `CSS` heredoc is **byte-identical** to
  `origin/main:showtime/gtk/style.css` (`diff` against the extracted heredoc
  body returns nothing).
- The `rate` accessor chain upstream builds as a `GObject.Property` setter
  on `Window` (pops the options popover down, emits `rate-changed`) is
  reproduced end to end in the port, just split across three files instead
  of one: `Options#rate=` (`options.rb:85-90`) pops the popover down and
  calls `@on_rate`; `Application#rate=` (`application.rb:105-106`) is the
  settable surface MPRIS's `_set("Rate", ...)` branch (`mpris.rb:242-243`)
  calls into. This closes the "needs a closer read" item the component
  inventory left open under "Actions/components not yet confirmed covered"
  — it should be removed from that open-items list, not left sitting there
  now that it has an answer.
- `app.shortcuts`, the other item left open in that same inventory section,
  is confirmed installed on the **application**, not shadowed by a
  window-level action: `application.rb:117` is the only `add_action(...,
  "shortcuts")` call site in the port (`grep -n '"shortcuts"' lib/showtime/*.rb`
  shows one hit outside the require line).

No new component, widget, action, or upstream file was found missing from
the existing inventory's 18-unit list, beyond the `data/` undercounting
named above.
