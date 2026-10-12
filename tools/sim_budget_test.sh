#!/usr/bin/env bash
# Checks tools/sim_budget.sh's verdicts with a fake godot that prints a canned bench_sim result
# for each checkout directory.
set -u

cd "$(dirname "$0")/.." || exit 1
status=0
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

cat >"$scratch/godot" <<'FAKE'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do
	if [ "$1" = "--path" ]; then
		dir=$2
	fi
	shift
done
cat "$dir/bench.txt"
exit "$(cat "$dir/status")"
FAKE
chmod +x "$scratch/godot"

# A checkout whose bench_sim prints a tick mean of $2 ms and exits $3.
checkout() {
	mkdir -p "$scratch/$1"
	printf 'Simulation budget: 1000 enemies\nTick mean %s ms, max 30.00 ms\n' "$2" >"$scratch/$1/bench.txt"
	echo "$3" >"$scratch/$1/status"
}

expect() {
	local want=$1 name=$2
	shift 2
	GODOT="$scratch/godot" tools/sim_budget.sh "$@" >/dev/null 2>&1
	local got=$?
	if [ "$want" = pass ] && [ $got -ne 0 ]; then
		echo "FAIL: $name failed"
		status=1
	elif [ "$want" = fail ] && [ $got -eq 0 ]; then
		echo "FAIL: $name passed"
		status=1
	fi
}

checkout base 40.0 0
checkout slower_10 44.0 0
checkout slower_25 50.0 0
checkout faster_but_broken 30.0 1
checkout base_over_its_budget 40.0 1
checkout over_the_backstop 85.0 1
checkout alone_ok 20.0 0

expect pass "a PR 10% slower than its base" "$scratch/slower_10" "$scratch/base"
expect fail "a PR 25% slower than its base" "$scratch/slower_25" "$scratch/base"
expect fail "a PR whose bench fails its checks" "$scratch/faster_but_broken" "$scratch/base"
expect pass "a base whose bench fails" "$scratch/slower_10" "$scratch/base_over_its_budget"
expect pass "no base, within the backstop" "$scratch/alone_ok"
expect fail "no base, over the backstop" "$scratch/over_the_backstop"

exit $status
