# Test parity — showtime

| | |
|---|---|
| Upstream | `main` @ `f28a1d4` |
| Port | `ruby` @ `e191199` |
| Upstream tests | 0 |
| Ported | 0 |
| Gaps | 0 |
| Test command (documented) | `ruby -e 'require "rspec/core"; exit RSpec::Core::Runner.run([...])'` — printed by the dev-shell banner as "run the specs" |
| Test command actually used | `nix develop --command xvfb-run -a ruby test/drive_*.rb` |

Upstream has no test suite (verified this round: `git ls-tree -r --name-only
origin/main` lists nothing matching `test`, and the Python source has no
`unittest`/`pytest`/`def test_` anywhere). Parity is **0/0 and is met
trivially — the port inherits no safety net from upstream**. Every check
below was written for the port and pins nothing upstream considered worth
pinning.

## The runtime gate, reproduced this round

```
test/drive_mpris.rb            16 of 16 checks passed   DRIVE OK
test/drive_placeholder.rb      16 of 16 checks passed   DRIVE OK
test/drive_video_widgets.rb    26 of 26 checks passed   DRIVE OK
test/drive_window.rb           41 of 41 checks passed   DRIVE OK
                                ------------------------
                                99 of 99 checks passed
```

This is the number quoted for this round's gate (`drive_ok=true`, 99/99, 18
components) and it was reproduced here by actually running each of the four
files (`nix develop --command xvfb-run -a ruby test/drive_<name>.rb`), not
taken on the round's word. `drive_window.rb`'s count rose from 36 (the
number the last `test-parity` round recorded) to 41 because of the commit
made since — `e191199` added five checks (12-17 cover "a real missing-plugin
message reaches the window" through both `on_install_done` branches) that
drive the install-plugin wiring `6f102ac` built. That addition is real: read
`test/drive_window.rb:100-170` and it fires a genuine `GstPbutils`
missing-decoder bus message through `Play`'s real messenger pub/sub, then
calls `on_install_done` directly with the actual `GstPbutils::
InstallPluginsReturn` enum values, rather than faking the result shape.

**This closes a gap the previous `test-parity` round named explicitly**: "the
94/94 gate does not cover the install-plugin flow" is no longer true — it is
covered now, by name, with its own five checks. The gap the previous round
did not raise — multi-window architecture — is still uncovered: no drive
script opens, or asserts the existence of, a second `Gtk::Window`. That is
still a real coverage hole, not resolved by this round's work, and belongs
with `.reports/component-parity.md`'s open gap #1.

## The suite the dev shell tells you to run still finds nothing

Run verbatim this round, headless, under `xvfb-run`, exactly as the dev
shell's own banner prints it:

```
nix develop --command xvfb-run -a ruby -e 'require "rspec/core"; exit RSpec::Core::Runner.run(["--format", "progress", "--require", "spec_helper", "spec"])'
```

```
NOTE: kettle-test isn't installed; running with plain RSpec.
No examples found.
0 examples, 0 failures
```

`spec/` still contains only `spec_helper.rb` (harness boilerplate) and
`README.md` (prose describing helpers no spec in the repository uses). There
is still no `spec/*_spec.rb` anywhere in the tree. **This is unchanged from
the previous round and was not addressed by either of the two commits made
since** — both of those commits added coverage to `test/drive_window.rb`,
the ad hoc headless harness, not to `spec/`. The dev shell's own banner
names a test command whose actual run result is zero examples; that gap is
still live, and advertising it as "run the specs" is still the kind of
false-green surface `accountability-ensurance` flags independently.

## Extra: what the port's real suite covers, unmapped to any upstream test

- `test/drive_mpris.rb` — 16 checks on the MPRIS2 D-Bus surface.
- `test/drive_placeholder.rb` — 16 checks on the welcome/error/missing-plugin
  states (message selection only — see below), the primary menu, the
  shortcuts and about dialogs, fullscreen action/accelerators.
- `test/drive_video_widgets.rb` — 26 checks on the drag overlay, sound
  options, options popover, and restore overlay.
- `test/drive_window.rb` — 41 checks on the window shell: both stack pages,
  every `win.*`/`app.*` action's presence and accelerator, the idle
  inhibitor, drag-and-drop, loop persistence, welcome/video page switching,
  and (new this round) the real missing-plugin → install-result path.
- `test/gtk_driver.rb` — the shared harness; not itself a test file.

Still true, re-checked this round: `drive_placeholder.rb`'s own missing-plugin
checks exercise message *selection* only (they hand-construct an `on_install`
callback rather than going through `Window`'s real wiring) — that coverage
gap is now filled by `drive_window.rb` instead, so it is no longer an
uncovered gap overall, just covered by a different file than the one that
originally claimed to test it. Worth naming so a future reader does not
assume `drive_placeholder.rb` covers the install flow when it is
`drive_window.rb` that actually does.

No file in `test/` or `lib/` exercises `Showtime::Translations` end-to-end
(loading a non-English `.po` and asserting a translated string reaches a
widget on screen) — unchanged from the previous round. See
`.reports/translation-parity.md`.

## Rules check

- Counts equal: 0 upstream, 0 ported → trivially equal. ✓
- Suite actually runs: the port's own drive suite does (99/99, reproduced
  this round under `xvfb-run`, not assumed from the harness notification);
  the suite the project's own tooling calls "the specs" does not (0
  examples, reproduced this round too). Both facts are reported; neither is
  hidden behind the other.
- A suite that has never been executed is named as a gap, not folded into
  "passing": `spec/` is reported as 0/0 run, not omitted because `test/`
  looks healthy.
