#!/usr/bin/env bash
# The sim-budget gate. Runs bench_sim on a PR checkout and on its base checkout, alternating, on
# the same machine, and fails when the PR's best tick mean is more than MAX_SLOWDOWN times the
# base's best. CI runners differ by about 2x, so comparing on one runner cancels that out where an
# absolute budget can't.
#
# The PR's runs must also pass bench_sim's own checks (determinism, a surge, drones repairing,
# grinders grinding, and its absolute backstop). The base's exit status is ignored, since an older
# base may fail a budget this PR changes; only its tick mean is used. With no base (a push to
# main), only the PR's runs are checked, and likewise when the bench's workload differs between
# the two (a version's umbrella PR grows the bench), since their tick means then measure different
# work.
#
# Usage: tools/sim_budget.sh <pr-dir> [<base-dir>]
set -u

GODOT=${GODOT:-godot}
RUNS=${RUNS:-2}
MAX_SLOWDOWN=${MAX_SLOWDOWN:-1.2}
pr=$1
base=${2:-}
status=0

# Runs bench_sim in the checkout at $1, echoing its report to stderr and the tick mean to stdout.
# Returns bench_sim's exit status.
bench() {
	local out code
	out=$("$GODOT" --headless --path "$1" --script res://tools/bench_sim.gd 2>&1)
	code=$?
	echo "$out" | grep -vE "^(Godot Engine|ERROR: .*[Rr]emote|   at: )" >&2
	echo "$out" | sed -n 's/^Tick mean \([0-9.]*\) ms.*/\1/p' | head -1
	return $code
}

# The smaller of two numbers, either of which may be empty.
lower() {
	if [ -z "$1" ]; then
		echo "$2"
	elif [ -z "$2" ]; then
		echo "$1"
	else
		awk -v a="$1" -v b="$2" 'BEGIN { print (a < b) ? a : b }'
	fi
}

BENCH_FILES="tools/bench_sim.gd tools/bench_crowd.gd"

if [ -n "$base" ]; then
	for file in $BENCH_FILES; do
		if ! cmp -s "$pr/$file" "$base/$file"; then
			echo "$file differs from the base's, so the tick means aren't comparable; checking only the PR's runs" >&2
			base=""
			break
		fi
	done
fi

pr_best=""
base_best=""
for run in $(seq "$RUNS"); do
	if [ -n "$base" ]; then
		echo "== base, run $run" >&2
		base_best=$(lower "$base_best" "$(bench "$base")")
	fi
	echo "== PR, run $run" >&2
	if ! mean=$(bench "$pr"); then
		echo "bench_sim failed its own checks on the PR" >&2
		status=1
	fi
	pr_best=$(lower "$pr_best" "$mean")
done

if [ -z "$pr_best" ]; then
	echo "bench_sim printed no tick mean for the PR" >&2
	exit 1
fi
if [ -z "$base" ]; then
	echo "PR best tick mean ${pr_best} ms (no base to compare against)"
	exit $status
fi
if [ -z "$base_best" ]; then
	echo "bench_sim printed no tick mean for the base" >&2
	exit 1
fi

limit=$(awk -v b="$base_best" -v m="$MAX_SLOWDOWN" 'BEGIN { printf "%.2f", b * m }')
echo "Best tick mean: PR ${pr_best} ms, base ${base_best} ms (limit ${limit} ms, ${MAX_SLOWDOWN}x)"
if awk -v p="$pr_best" -v l="$limit" 'BEGIN { exit !(p > l) }'; then
	echo "The PR's tick cost is more than ${MAX_SLOWDOWN}x its base's on this runner" >&2
	status=1
fi
exit $status
