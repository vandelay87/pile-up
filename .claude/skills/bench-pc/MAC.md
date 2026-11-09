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

## 3. Copy the PC's tables into the PR

When the user asks for them, or when a background wait you set up ends, check the label: `gh pr view <pr> --json labels --jq '.labels[].name'`.

- `bench-pc` still on: the PC hasn't run yet, or it's busy. Leave it.
- `bench-pc-failed`: tell the user what the PC's comment says. Relabel `bench-pc` only if they ask.
- `bench-pc-done`: take the PC's newest comment that starts with `## PC (3080)`:

  ```bash
  gh pr view <pr> --json comments \
    --jq '[.comments[] | select(.body | startswith("## PC (3080)\n"))] | last | .body'
  ```

  Add it as the last subsection of `## Performance`, one heading level down. `## PC (3080)` becomes `### PC (3080)`, and each `### bench_...` becomes `#### bench_...`. With `####` headings, a re-bench runs only the M5's `###` cases. Put it next to the M5 tables and keep those as they are. Write the body with `gh pr edit <pr> --body-file`.

Done when the PR body's Performance section has a `### PC (3080)` subsection matching the PC's newest comment.

To be told when the PC is done without polling by hand, run Bash with `run_in_background` and this loop. It ends on either outcome:

```bash
until gh pr view <pr> --json labels --jq '.labels[].name' | grep -qxE 'bench-pc-(done|failed)'; do sleep 300; done
```
