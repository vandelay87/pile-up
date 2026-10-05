#!/usr/bin/env bash
set -u

cd "$(dirname "$0")/.."
status=0

for fixture in test/fixtures/sim_boundary/*.gd; do
	if tools/check_sim_boundary.sh "$fixture" >/dev/null; then
		echo "FAIL: $fixture passed the boundary check"
		status=1
	fi
done

if ! tools/check_sim_boundary.sh src/sim; then
	echo "FAIL: src/sim broke the boundary check"
	status=1
fi

exit $status
