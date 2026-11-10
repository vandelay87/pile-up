#!/usr/bin/env bash
# Classifies a CI run for .github/workflows/ci.yml, so docs-only runs skip the build and macOS
# (10x the minutes) builds only where it's needed.
#
# Usage: tools/ci_changes.sh <event> <base ref> < changed-paths
#   <event>     github.event_name: pull_request, push or workflow_dispatch
#   <base ref>  the PR's base branch (empty for a push or a manual run)
#   stdin       the changed paths, one per line; none means they're unknown, so build everything
#
# Prints GITHUB_OUTPUT lines:
#   docs_only=true|false  every path is under docs/ or is a *.md
#   platforms=<json>      the native build matrix: Linux and Windows always, macOS on a push to
#                         main, a PR into main, a manual run, or a change under native/
set -u

event=$1
base=$2

paths=()
while IFS= read -r path; do
	[ -n "$path" ] && paths+=("$path")
done

docs_only=false
macos=false
if [ ${#paths[@]} -eq 0 ]; then
	macos=true
else
	docs_only=true
	for path in "${paths[@]}"; do
		case $path in
		docs/* | *.md) ;;
		*) docs_only=false ;;
		esac
		case $path in
		native/* | native) macos=true ;;
		esac
	done
fi

case $event in
push | workflow_dispatch) macos=true ;;
pull_request) [ "$base" = main ] && macos=true ;;
esac

platforms='{"platform":"linux","os":"ubuntu-latest"},{"platform":"windows","os":"windows-latest"}'
if [ "$docs_only" = false ] && [ "$macos" = true ]; then
	platforms+=',{"platform":"macos","os":"macos-latest"}'
fi

echo "docs_only=$docs_only"
echo "platforms=[$platforms]"
