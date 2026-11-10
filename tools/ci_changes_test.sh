#!/usr/bin/env bash
# Checks tools/ci_changes.sh's verdicts: which runs are docs-only and which build macOS.
set -u

cd "$(dirname "$0")/.." || exit 1
status=0

linux_windows='[{"platform":"linux","os":"ubuntu-latest"},{"platform":"windows","os":"windows-latest"}]'
all_three='[{"platform":"linux","os":"ubuntu-latest"},{"platform":"windows","os":"windows-latest"},{"platform":"macos","os":"macos-latest"}]'

# expect <name> <docs_only> <platforms> <event> <base ref> [changed path...]
expect() {
	local name=$1 docs_only=$2 platforms=$3 event=$4 base=$5
	shift 5
	local want got macos=false
	[ "$platforms" = "$all_three" ] && macos=true
	want=$(printf 'docs_only=%s\nmacos=%s\nplatforms=%s' "$docs_only" "$macos" "$platforms")
	got=$(printf '%s\n' "$@" | grep -v '^$' | tools/ci_changes.sh "$event" "$base")
	if [ "$got" != "$want" ]; then
		printf 'FAIL: %s\n  want: %s\n  got:  %s\n' "$name" "$want" "$got"
		status=1
	fi
}

expect "a docs PR into main" true "$linux_windows" pull_request main \
	docs/design.md GLOSSARY.md
expect "a docs PR into a vN-build" true "$linux_windows" pull_request v6-build \
	docs/adr/0009-x.md
expect "a docs merge into main" true "$linux_windows" push "" \
	docs/design.md
expect "a feat PR into a vN-build" false "$linux_windows" pull_request v6-build \
	src/sim/wave.gd docs/design.md
expect "a native PR into a vN-build" false "$all_three" pull_request v6-build \
	native/src/flow_field.cpp
expect "a godot-cpp bump" false "$all_three" pull_request v6-build \
	native/godot-cpp
expect "the umbrella PR into main" false "$all_three" pull_request main \
	src/sim/wave.gd
expect "a code push to main" false "$all_three" push "" \
	src/sim/wave.gd
expect "a manual run" false "$all_three" workflow_dispatch ""
expect "a push with no paths" false "$all_three" push ""
expect "a PR with no paths" false "$all_three" pull_request v6-build
expect "a README-like file outside docs" true "$linux_windows" pull_request v6-build \
	tools/README.md
expect "a markdown-ish name that isn't" false "$linux_windows" pull_request v6-build \
	docs.gd

exit $status
