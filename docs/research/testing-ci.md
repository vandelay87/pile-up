# Testing and CI for Godot 4.7

Research for issue #5. Sources checked on 2026-10-04 against Godot 4.7.2-stable (released 2026-08-18).

## Answer

- **Test framework:** gdUnit4 (v6.2.x), run on GitHub Actions through its official action, `godot-gdunit-labs/gdUnit4-action`. GUT 9.7.1 is an equally valid choice on compatibility; gdUnit4 wins on CI ergonomics, because the action publishes results as a PR check.
- **Export builds:** both the Windows and the macOS build can be exported from a single `ubuntu-latest` job using the official export templates. A macOS or Windows runner is only needed for things this prototype does not need yet: notarisation via Xcode, `.dmg` packaging, or smoke-launching the built game on its real OS.
- **Performance:** the "1,000 enemies at 60 fps on a MacBook" target cannot be checked on standard GitHub-hosted runners, which have no GPU. CI can guard the CPU-side simulation (flow fields, spatial hash, enemy update) with a headless timing budget. Real frame time is measured locally on the MacBook, or on a self-hosted runner on that MacBook.

## 1. GUT versus gdUnit4

### Godot 4.7 compatibility

| | GUT | gdUnit4 |
|---|---|---|
| Version for 4.7 | 9.7.1 (2026-07-10) | 6.2.1 (2026-08-20) |
| Stated support | "9.7.1 (godot_4_7 branch): 4.7.x" [1] | "v6.2.0 / master (v6.2.1): ... v4.7, v4.7.1" [3] |
| Where to get it | Release zip only. The Asset Library entry is 9.6.1, which targets 4.6.x; `main` also targets 4.6.x [1] | Asset Library or release [3] |
| 4.7 caveat | 9.7.0 is a breaking release: 4.7's stricter return-type checks mean doubles now return a type default instead of `null` [2] | None noted in 6.2.x release notes [4] |

Neither project's compatibility table names 4.7.2 yet. Both name 4.7.x or 4.7.1, and 4.7.2 is a patch release, so this is a low risk. It is worth confirming on the first CI run.

### Running headless

**GUT** runs as a script, and returns exit code 0 if every test passes and 1 if any fail [5]:

```sh
godot --headless -d -s --path . addons/gut/gut_cmdln.gd \
  -gdir=res://test -gjunit_xml_file=results.xml -gexit
```

GUT detects headless mode, ignores `pause_before_teardown` and exits on its own [6]. JUnit XML output can be fed to a report action (for example `dorny/test-reporter`), but GUT ships no first-party GitHub Action.

**gdUnit4** runs through `addons/gdUnit4/runtest.sh -a res://test` (`runtest.cmd` on Windows) [7][8]. Exit codes: 0 means pass, 100 means failures, 101 means warnings [7]. It **refuses to run under `--headless`** unless `--ignoreHeadlessMode` is passed, because Godot does not deliver `InputEvent`s in headless mode and UI-interaction tests would silently do nothing [9]. The official action avoids this problem: on Ubuntu it runs the tests under `xvfb-run` with `--display-driver x11 --rendering-driver opengl3 --audio-driver Dummy` [10]. Before the run, it does the following [11]:

- downloads Godot from `godotengine/godot-builds`
- caches Godot
- imports the project (`godot -e --headless --quit-after 2000`)
- publishes a check run through `dorny/test-reporter`

The workflow therefore needs the `checks: write` permission.

```yaml
- uses: godot-gdunit-labs/gdUnit4-action@v1   # pin to a release SHA in practice
  with:
    godot-version: '4.7.2'
    version: 'v6.2.1'        # default is "latest"; pin it
    paths: 'res://test'
```

### Recommendation

Use **gdUnit4 with its official action**:

- The human reviewer treats CI as proof. A published check run listing each test is stronger evidence than a log line, and gdUnit4 provides one with no glue code.
- Its compatibility table explicitly covers 4.7.x, and it ships from its main line (GUT's 4.7 build lives on a side branch and is missing from the Asset Library).
- Its scene runner and input simulation will matter for v2 (rally points, minion orders). The action's xvfb setup lets those tests run in CI where pure `--headless` cannot.

GUT is the fallback if gdUnit4's xvfb/OpenGL path proves flaky. Its one-line headless invocation is simpler, and most pile-up logic (pile levels, flow-field costs, wave scaling) is plain GDScript that either framework tests equally well.

## 2. Windows and macOS export builds in CI

### Mechanics

- Exporting needs the export templates for the exact engine version, installed under the editor's templates directory (on Linux: `~/.local/share/godot/export_templates/4.7.2.stable/`) [12][13].
- For 4.7.2 the bundle is `Godot_v4.7.2-stable_export_templates.tpz`, about **1.2 GB** [14]. It should be cached between runs; both setup options below do this.
- Command-line export [15]:

  ```sh
  godot --headless --export-release "Windows Desktop" build/windows/pile-up.exe
  godot --headless --export-release "macOS" build/macos/pile-up.zip
  ```

  - `--export-release` uses the named preset from `export_presets.cfg`. That file "can be safely committed".
  - Secrets live in `.godot/export_credentials.cfg`, which should not be committed [13].
  - `--export-debug` implies `--import` [15].

### Setup options

| Option | What it is | Notes |
|---|---|---|
| `chickensoft-games/setup-godot@v2` (v2.4.3, 2026-10-01) | Installs Godot and optionally the templates (`include-templates: true`) directly on the runner, with caching. Works on Linux, macOS and Windows runners [16] | Same action can serve tests, exports and any native-OS job |
| `barichello/godot-ci:4.7.2` container | Docker image with Godot, templates and `osslsigncode` preinstalled; tag 4.7.2-stable published 2026-08-18 [17] | Its sample workflow exports Windows from `ubuntu-24.04`; templates must be moved from `/root` to `$HOME` [18] |

Recommendation: **`setup-godot`**, because it runs natively, works the same on any OS, and does not pin the workflow to a container image's update cadence.

### Per platform from a Linux host

- **Windows:** exports from Linux. Godot converts the project icon to `.ico` itself. Code signing from a non-Windows host uses `osslsigncode` [19]. For a prototype, unsigned is fine.
- **macOS:**
  - The export is a Universal 2 `.app`, delivered as a `.zip` from any host. `.dmg` is "only supported when exporting from macOS" [20].
  - Signing and notarisation from Linux or Windows use `rcodesign`, and need an Apple Developer ID certificate [20].
  - Without notarisation, Gatekeeper blocks the app when it is downloaded. Ad-hoc signing makes local launch easier [20].
  - For a private prototype passed to a handful of testers, an ad-hoc-signed `.zip` is enough. Notarisation is a Steam-release concern.

### Runner cost (private repo)

GitHub's former "minute multipliers" page now redirects to per-minute rates [21]. Public repos run standard runners free. Private repos draw on the plan's monthly quota: 2,000 minutes on Free, 3,000 on Pro [22]. Standard runner rates [23]:

| Runner | USD/min | Relative to Linux |
|---|---|---|
| Linux 2-core | $0.006 | 1x |
| Windows 2-core | $0.010 | ~1.7x |
| macOS 3/4-core | $0.062 | ~10x |

These ratios are derived from the published rates. The old multipliers were 1x, 2x and 10x. The billing dashboard reports usage as spend that "already reflects any applicable minute costs" [22]. In practice, a 5-minute macOS job costs about as much as 50 Linux minutes. All export work should therefore stay on `ubuntu-latest`. Any native macOS or Windows job, such as a smoke launch of the exported build, should run only on tags or manual dispatch, not on every PR.

## 3. Can a 1,000-enemy performance check run in CI?

Not for the target as written. The target is 60 fps rendering on a MacBook.

- Standard GitHub-hosted runners have no GPU. GPU runners exist only as paid "larger runners" (Tesla T4, Ubuntu and Windows). Larger runners "are always charged for", even with quota left [24][25].
- `--headless` swaps in the headless display driver and the Dummy audio driver [15], so nothing is drawn. Under xvfb, Godot renders through `opengl3` on a software rasteriser [10]. Neither environment tells anything about frame time on a MacBook GPU.
- Shared VMs also give noisy CPU timings. A tight millisecond threshold would make CI flaky, and a flaky check is useless as proof.

What CI can do reliably:

1. **Simulation budget test (CI).** Run the enemy update with 1,000 enemies for N fixed ticks in a headless test. This covers flow-field lookup, spatial-hash separation and pile slow. Fail only on a generous budget, for example several times the expected cost, so the test catches algorithmic regressions (such as an O(n²) neighbour check) rather than noise. Godot's `--fixed-fps` disables real-time sync, which keeps tick counts deterministic [15].
2. **Frame-time benchmark (local).** Keep a benchmark scene that spawns 1,000 enemies and logs average and worst frame time. Run it on the MacBook with `--print-fps` or `--benchmark` [15]. Paste the numbers into PRs that touch enemies or rendering.
3. **Optional: a self-hosted runner on the MacBook.** Self-hosted runners are free [22]. This turns step 2 into a real CI check, but only while the laptop is on and idle. It is not worth setting up until step 2 becomes a chore.

## Sources

1. GUT README, version table: https://github.com/bitwes/Gut (README.md)
2. GUT v9.7.0 release notes: https://github.com/bitwes/Gut/releases/tag/v9.7.0
3. gdUnit4 README, "Compatibility Overview": https://github.com/godot-gdunit-labs/gdUnit4
4. gdUnit4 v6.2.0 and v6.2.1 release notes: https://github.com/godot-gdunit-labs/gdUnit4/releases
5. GUT command line docs: https://gut.readthedocs.io/en/v9.7.1/Command-Line.html
6. GUT CHANGES.md (headless auto-exit): https://github.com/bitwes/Gut/blob/main/CHANGES.md
7. gdUnit4 command line docs: https://godot-gdunit-labs.github.io/gdUnit4/latest/advanced_testing/cmd/
8. gdUnit4 `addons/gdUnit4/runtest.sh`: https://github.com/godot-gdunit-labs/gdUnit4/blob/master/addons/gdUnit4/runtest.sh
9. gdUnit4 `GdUnitTestCIRunner.gd` (`--ignoreHeadlessMode`): https://github.com/godot-gdunit-labs/gdUnit4/blob/master/addons/gdUnit4/src/core/runners/GdUnitTestCIRunner.gd
10. gdUnit4-action test launcher: https://github.com/godot-gdunit-labs/gdUnit4-action/blob/master/.gdunit4_action/unit-test/index.js
11. gdUnit4-action `action.yml` and README: https://github.com/godot-gdunit-labs/gdUnit4-action
12. godot-ci Dockerfile (template install path): https://github.com/abarichello/godot-ci/blob/master/Dockerfile
13. Godot docs, Exporting projects: https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html
14. Godot 4.7.2-stable release assets: https://github.com/godotengine/godot/releases/tag/4.7.2-stable
15. Godot docs, Command line tutorial (4.7): https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html
16. chickensoft-games/setup-godot README: https://github.com/chickensoft-games/setup-godot
17. abarichello/godot-ci releases: https://github.com/abarichello/godot-ci/releases
18. godot-ci sample workflow: https://github.com/abarichello/godot-ci/blob/master/.github/workflows/godot-ci.yml
19. Godot docs, Exporting for Windows: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_windows.html
20. Godot docs, Exporting for macOS: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_macos.html
21. GitHub docs source, `actions-runner-pricing.md` (redirect from `actions-minute-multipliers`): https://github.com/github/docs/blob/main/content/billing/reference/actions-runner-pricing.md
22. GitHub docs, GitHub Actions billing: https://docs.github.com/en/billing/concepts/product-billing/github-actions
23. GitHub docs, Actions runner pricing: https://docs.github.com/en/billing/reference/actions-runner-pricing
24. GitHub docs, Larger runners reference (GPU specs): https://docs.github.com/en/actions/reference/runners/larger-runners
25. GitHub docs, Actions billing note on larger runners: https://docs.github.com/en/billing/concepts/product-billing/github-actions#free-use-of-github-actions
