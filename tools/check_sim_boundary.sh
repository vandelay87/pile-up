#!/usr/bin/env bash
# Fails if anything under the given paths extends a class other than RefCounted or a src/sim class, or references src/view/.
set -u

paths=("$@")
if [ ${#paths[@]} -eq 0 ]; then
	paths=(src/sim)
fi

class_names() {
	grep -rhoE --include='*.gd' '^class_name[[:space:]]+[[:alnum:]_]+' "$1" | awk '{ print $2 }' | paste -sd'|' -
}

sim_classes=$(class_names src/sim)
view_classes=$(class_names src/view)

find "${paths[@]}" -name '*.gd' -print0 | xargs -0 -r awk \
	-v allowed="^(RefCounted${sim_classes:+|$sim_classes})$" \
	-v view_classes="${view_classes:+(^|[^[:alnum:]_])($view_classes)([^[:alnum:]_]|$)}" '
	/^[[:space:]]*#/ { next }
	{ line = $0; sub(/#[^"]*$/, "", line) }
	match(line, /(^|[[:space:]])extends[[:space:]]+("[^"]*"|[^:[:space:]]+)/) {
		base = substr(line, RSTART, RLENGTH)
		sub(/.*extends[[:space:]]+/, "", base)
		if (base ~ /^"res:\/\/src\/sim\//) {
			ok = 1
		} else {
			split(base, parts, ".")
			ok = parts[1] ~ allowed
		}
		if (!ok) {
			print FILENAME ":" FNR ": extends " base
			bad_extends = 1
		}
	}
	line ~ /src\/view\/|\.\.\/view\// || (view_classes != "" && line ~ view_classes) {
		print FILENAME ":" FNR ": " $0
		bad_view = 1
	}
	END {
		if (bad_extends) print "Simulation code may only extend RefCounted or classes under src/sim/."
		if (bad_view) print "Simulation code must not reference src/view/."
		exit bad_extends || bad_view
	}
'
