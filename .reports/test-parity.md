# Test parity — showtime

| | |
|---|---|
| Upstream | `main` @ `f28a1d4` |
| Port | `ruby` @ `47105ff` |
| Upstream tests | 0 |
| Ported | 0 |
| Gaps | 0 |
| Test command (documented) | `ruby -e 'require "rspec/core"; exit RSpec::Core::Runner.run([...])'` — printed by the dev-shell banner as "run the specs" |
| Test command actually used | `nix develop --command xvfb-run -a ruby test/drive_*.rb` |

Upstream has no test suite (verified: `find . -iname "*test*"` on
`/tmp/wt/upstream` (origin/main @ `f28a1d4`) returns nothing, and a grep for
`unittest|pytest|def test_` across `showtime/**/*.py` returns zero matches).
Parity is **0/0 and is met trivially — the port inherits no safety net**. Every
check below was written for the port and pins nothing upstream considered
worth pinning.

## The gate this round, run for real

```
test/drive_mpris.rb            16 of 16 checks passed   DRIVE OK
test/drive_placeholder.rb      16 of 16 checks passed   DRIVE OK
test/drive_window.rb           36 of 36 checks passed   DRIVE OK
test/drive_video_widgets.rb    26 of 26 checks passed   DRIVE OK
                                ------------------------
                                94 of 94 checks passed
```

94 is the real number: it is the count of `check(...)` calls actually executed
(`grep -c '\bcheck(' test/drive_*.rb` sums to 75 distinct call sites, several
inside loops that execute more than once per run — e.g. `drive_video_widgets.rb`
drives three audio-stream submenu rows and two subtitle rows in one `check`
each — which is how 75 static call sites produce 94 runtime passes). This
matches the runtime gate given for this round (`drive_ok=true`, 94/94, 18
components) and was reproduced here, not taken on faith, under
`nix develop --command xvfb-run -a ruby test/drive_<name>.rb` for each of the
four files.

`scripts/test-census.sh` (this skill) reports 124 rows for the port tree
because it also collects the `step(...)` grouping labels (49 of them) as if
they were assertions — they are not. Per this skill's Step 1 instruction to
"find the call that increments the pass counter", `test/gtk_driver.rb:78`
shows `check` is the only call that increments `@checks`; `step` only records
a name for a sub-section of the driver's output. 94, from `check`, is the
assertion count; 124 is a census-script overcount for this suite's shape and
should not be reported as the test count.

## The suite the dev shell tells you to run finds nothing

The dev-shell banner (`nix develop`) prints three lines, one of them labelled
"run the specs":

```
ruby -e 'require "rspec/core"; exit RSpec::Core::Runner.run(["--format", "progress", "--require", "spec_helper", "spec"])'
```

Run verbatim, headless, under `xvfb-run`:

```
NOTE: kettle-test isn't installed; running with plain RSpec.
No examples found.
0 examples, 0 failures
```

`spec/` contains only `spec_helper.rb` (harness boilerplate) and `README.md`
(prose describing helpers that no spec in this repository uses). There is no
`spec/*_spec.rb` anywhere in the tree, `.rspec_status` is empty, and
`showtime-rb.gemspec` declares no `rspec` test dependency. **The suite scaffold
exists; the suite does not.** The dev shell's own banner names a test command
whose current, actual, run result is zero examples — that is a documentation
gap, and one this skill is specifically built to catch: a command that "exists"
and produces nothing is not a safety net, and advertising it as "run the specs"
without a single spec in the repository is the kind of false-green claim
`accountability-ensurance` also flags (see that report).

## Extra

All of the port's actual, runnable verification lives here, outside the 0/0
count because none of it maps to an upstream test:

- `test/drive_mpris.rb` — 16 checks on the MPRIS2 D-Bus surface: Raise,
  Identity/DesktopEntry, CanPlay/CanSeek/CanRaise, LoopStatus, rate bucketing,
  introspection XML, GetAll, and that an unknown method or a call with nothing
  loaded returns a DBus error / no-op instead of crashing.
- `test/drive_placeholder.rb` — 16 checks on the welcome/error/missing-plugin
  states, the primary menu, the shortcuts and about dialogs, and the
  fullscreen action/accelerators.
- `test/drive_window.rb` — 36 checks on the window shell: both stack pages,
  every `win.*`/`app.*` action's presence and accelerators, the idle
  inhibitor, the drag-and-drop target, loop persistence to settings, and
  switching between the welcome and video pages.
- `test/drive_video_widgets.rb` — 26 checks on the four widgets the video
  page assembles: the drag overlay, sound-options popover (volume-icon
  thresholds), options popover (language/subtitle submenus, rate toggle
  group, rotation), and the restore overlay (resume/restart).
- `test/gtk_driver.rb` — the shared harness (`step`/`check`/screenshot
  machinery); not itself a test file.

No file in `test/` or `lib/` exercises `Showtime::Translations` end-to-end
(loading a non-English `.po` and asserting a translated string reaches a
widget) — see `.reports/translation-parity.md` for why that check could not
be run either.

## Rules check

- Counts equal: 0 upstream, 0 ported → trivially equal. ✓
- Suite actually runs: the port's own drive suite does (94/94, reproduced
  above); the suite the project's own tooling calls "the specs" does not (0
  examples). Both facts are reported; neither is hidden behind the other.
