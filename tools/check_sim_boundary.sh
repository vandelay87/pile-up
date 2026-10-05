#!/usr/bin/env bash
# Fails if anything under the given paths extends Node, Node2D or Resource, or references src/view/.
set -u

paths=("$@")
if [ ${#paths[@]} -eq 0 ]; then
	paths=(src/sim)
fi

status=0

if grep -rnE --include='*.gd' \
	'(^|[^[:alnum:]_])extends[[:space:]]+(Node|Node2D|Resource)([^[:alnum:]_]|$)' "${paths[@]}"; then
	echo "Simulation code must not extend Node, Node2D or Resource."
	status=1
fi

if grep -rn 'src/view/' "${paths[@]}"; then
	echo "Simulation code must not reference src/view/."
	status=1
fi

exit $status
