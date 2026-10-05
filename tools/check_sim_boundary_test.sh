#!/usr/bin/env bash
set -u

cd "$(dirname "$0")/.."
status=0

for fixture in test/fixtures/sim_boundary/bad/*.gd; do
	if tools/check_sim_boundary.sh "$fixture" >/dev/null; then
		echo "FAIL: $fixture passed the boundary check"
		status=1
	fi
done

for fixture in test/fixtures/sim_boundary/good/*.gd src/sim; do
	if ! tools/check_sim_boundary.sh "$fixture"; then
		echo "FAIL: $fixture broke the boundary check"
		status=1
	fi
done

exit $status
