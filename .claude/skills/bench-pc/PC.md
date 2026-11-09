# bench-pc: the PC side

While the watch runs, this session only benches. Its only writes are the ones `tools/bench_pc.sh` makes: a detached checkout in its own bench worktree, one PR comment and a label swap. Nobody is watching it then, and the PR heads it checks out belong to other sessions.

**Fixing a PC-side bug** is a separate dev step, done with the user present. This covers a Windows-only failure in the bench scripts, in this skill or in the export, which only this machine can reproduce:

1. Stop the watcher Monitor.
2. In the clone, branch `feat/*` off the integration branch. The bench worktree stays out of it.
3. Fix it, run `tools/bench_pc_test.sh` and `shellcheck tools/*.sh`, and check the fix on this machine.
4. Commit, push, and open a PR into the integration branch, so the work goes through the same review as the Mac's.
5. Check out the integration branch again, then re-arm the watcher.

Each branch has one writer. Push only to the branch you made, never to the PR branch of a run you benched.

## One-time setup

Check each item, and walk the user through any that are missing:

- **Git Bash** is the shell. `tools/bench_pc.sh` and `tools/bench_release.sh` are bash and call `powershell.exe` and `nvidia-smi`.
- **`GODOT_BIN`** is set, user-wide, to Godot 4.7.2's **console** exe (`Godot_v4.7.2-stable_win64_console.exe`). With the GUI exe, Git Bash sees none of its output.
- **The export templates** for 4.7.2 are installed in that Godot.
- **`gh auth status`** shows a login that can comment on and label this repo's PRs, and download Actions artifacts. The dll comes from CI's `native-windows` artifact. When the sha has none, `scons` and a C++ toolchain build it, if they're installed.
- **Remote Control** is on for the session (`/remote-control`), so the Mac can nudge it.
- **No sleep** while the session is open: `powercfg /change standby-timeout-ac 0`.
- The bench worktree, `pile-up-bench-pc` beside the clone, is made on the first run. Leave it to the script.

## Each session

Start a fresh session about once per version. In the clone, check out the version's integration branch (or `main`) and pull. That way `tools/bench_pc*.sh` and this skill are current. The clone itself is never benched, so it stays on that branch.

### Watch

Start a `Monitor` on `tools/bench_pc_watch.sh` with `timeout_ms` at its maximum and the description `bench-pc PRs`. It polls GitHub every 5 minutes and prints a line only when there is work, so idling costs no tokens. When the monitor expires, re-arm it straight away. A `/loop` would spend a turn on every poll, so the Monitor is the watcher.

The watch is running when the Monitor is armed. Tell the user once, then wait.

### Bench

Each `bench-pc: #<pr> at <sha>` event, or a Remote Control message `bench-pc: #<pr>`, gets one run, one PR at a time:

```bash
tools/bench_pc.sh <pr>
```

A run takes minutes, and longer when it builds the dll with `scons`. Run it with `run_in_background`, so no timeout can kill it halfway. If it's killed, the PR stays flagged and gets benched again. Start the next run only after the current one exits. Its last line says what happened. Act on its exit status:

| Exit | What it did | You |
|---|---|---|
| 0 | posted the tables (comment and PR body) and set `bench-pc-done`, or found the PR no longer flagged | wait for the next event |
| 75 | touched nothing: the PC was busy (a game running, or CPU or GPU load over the limits in the script's header), or GitHub couldn't be read | wait. The next poll prints the PR again. |
| 1 | posted the error and set `bench-pc-failed` | move on. It isn't retried until someone relabels. |

Events that arrive during a run queue up, and the PR the run just finished may be printed again. Run it anyway: the script checks the label first, so a PR that's already done is a no-op.

A run is done when the script has exited. On 0 or 1, its comment is on the PR, and on 0 its tables are in the body too.
