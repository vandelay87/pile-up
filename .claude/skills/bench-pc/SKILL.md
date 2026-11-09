---
name: bench-pc
description: Benchmarks pile-up PRs on the Windows PC (RTX 3080) as well as the M5. Use when a PR's Performance section needs the release bench, or to run this session as the PC's bench watcher.
---

# bench-pc

Two Claude sessions share the release bench (`tools/bench_release.sh`). The **Mac** session builds and flags PRs. The **PC** session watches and benches what the Mac flags, and posts the numbers back on the PR. It fixes PC-side bugs only as a separate dev step with the user (see PC.md). That gives every Performance section the M5 and the PC (RTX 3080).

The PR is the channel, and its labels are the state:

| Label | Meaning | Set by |
|---|---|---|
| `bench-pc` | waiting for the PC | the Mac |
| `bench-pc-done` | the PC posted its tables | the PC |
| `bench-pc-failed` | the PC posted an error and won't retry | the PC |

The PC's comment opens with `## PC (3080)`. History lives in those PR comments; there is no results file.

**Rules for both sides:**

- The PC's numbers are for information only. The spec's targets are judged on the M5.
- A ticket PR can merge without PC numbers. A version's performance re-measure waits for both machines.

## Which side are you?

- Developing on the Mac, with a PR whose Performance section the spec asks for: follow [MAC.md](MAC.md).
- On the Windows PC, asked to watch or bench: follow [PC.md](PC.md). Its one-time setup is there too.
