# Component identification — showtime

This round re-ran Step 1 of the skill (locate every upstream `.blp`/`.ui`
template and its backing source, confirm the file mapping) against
`origin/main` @ `f28a1d4` and cross-checked it line by line against the
inventory already on this branch, `.reports/component-inventory.md`. That
file is the canonical unit list — 18 components, file-to-file mapped,
widget/CSS/signal tables per unit — and this round found it **substantively
correct**, with two corrections:

## Correction 1 — the "16 exist / 2 missing" / stale-gap text is out of date in both directions

`.reports/component-inventory.md`'s own header flags itself stale as of an
earlier commit for the MPRIS/window-shell section, but a second, later
paragraph (describing `application.rb`'s remaining gaps: `HANDLES_OPEN`, the
idle inhibitor, `playback_history.json`) is *also* stale and the file does
not say so. Re-reading `application.rb` and `window.rb` directly (not
trusting either report) shows all three of those are now built — see
`.reports/component-parity.md`, unit 1, for the line numbers. Only one item
from that paragraph survives as a real, current gap: upstream opens a new
`Window` on every `do_activate` call (confirmed by reading `main.py:137-139`,
which has no window-reuse branch), and the port's single memoized `Window`
does not. That single surviving item is why unit 1 is still marked partial
in the parity report, not the whole list the stale paragraph names.

## Correction 2 — the install-plugin flow is a sub-component the inventory's unit-4 table undercounts

Unit 4 (`placeholder_page.rb`)'s table in the existing inventory lists the
"Install Plugin" `Adw.ButtonRow` as conditional ("only when
`GstPbutils.install_plugins_supported()`") without noting that the port's
call site never supplies the callback that would make the condition true on
any system. This is a behavioural finding, not a missing-widget one — the
widget-construction code for the button exists — so it belongs to
`component-parity` and `accountability-ensurance` rather than to this
skill's inventory, and both of those reports carry it. Recorded here only so
the inventory's own gap is named: a reader of the inventory table alone,
without the two cross-reference reports, would reasonably conclude this
button works.

## Everything else

The remaining 16 components' tables (widget counts, CSS classes, signals,
actions, the "not components" build-system exclusions) were spot-checked
against `origin/main` @ `f28a1d4` for two units chosen for the width of their
tables — unit 3 (`window.rb`, 21 actions) and unit 8 (`options.rb`, the
language/subtitle repeaters) — and both match upstream exactly, action name
for action name and repeater shape for repeater shape. No new component,
widget, action, or upstream file was found missing from the existing
inventory's unit list.
