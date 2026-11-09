# bench-pc: the Mac side

For a PR whose Performance section the version's spec asks for.

## 1. Bench on the M5 and flag the PR

1. Push the branch and open the PR.
2. Run each case with `GODOT_BIN=<godot> tools/bench_release.sh bench_profile dense-1000 [--army]`, and any other case the spec asks for. Paste each output into the PR's `## Performance` section unchanged. Each one starts with its own `### bench_...` heading.
3. Flag the PR: `gh pr edit <pr> --add-label bench-pc`.

The PC runs exactly the cases whose `### bench_...` headings are in the PR body, each one once. With none, it runs dense-1000 with and without the army. So put the M5 tables in the body before you flag the PR.

Done when the M5 tables are in the PR body and the label is on.

## 2. Nudge the PC (optional)

The PC polls every 5 minutes. To start it straight away, run `ListAgents`, find the PC's Remote Control session, and `SendMessage` it `bench-pc: #<pr>`. If no PC session is listed, skip this. The poll will pick the PR up when the PC is on.

## 3. Check on the PC's result

The PC writes its tables into the PR body itself, as a `### PC (3080)` subsection at the end of `## Performance`, and posts them as a comment too. When the user asks, check the label: `gh pr view <pr> --json labels --jq '.labels[].name'`.

- `bench-pc` still on: the PC hasn't run yet, or it's busy. Leave it.
- `bench-pc-done`: the tables are in the body. Edit the body only after this, or pull it fresh before editing, so you don't write back a copy without them.
- `bench-pc-failed`: tell the user what the PC's comment says. Relabel `bench-pc` only if they ask.
