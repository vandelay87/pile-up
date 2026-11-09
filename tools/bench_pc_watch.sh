#!/usr/bin/env bash
# The bench-pc skill's watcher, run under a Monitor on the PC: polls GitHub for open PRs labelled
# bench-pc every $BENCH_PC_POLL seconds (default 300) and prints one line per flagged PR, so the
# session wakes only when there is work. A PR stays flagged while the PC is busy, so it is printed
# again on the next poll until it is benched. A failing poll prints once, until one succeeds.
#
# Usage: tools/bench_pc_watch.sh
set -u

poll=${BENCH_PC_POLL:-300}
failing=""
err=$(mktemp)
trap 'rm -f "$err"' EXIT
while true; do
	if prs=$(gh pr list --label bench-pc --state open --json number,headRefOid \
		--jq '.[] | "bench-pc: #\(.number) at \(.headRefOid)"' 2>"$err"); then
		failing=""
		[ -n "$prs" ] && echo "$prs"
	elif [ -z "$failing" ]; then
		failing=1
		echo "bench-pc watch: gh pr list failed: $(head -1 "$err")"
	fi
	sleep "$poll"
done
