#!/usr/bin/env bash
# Benches one PR flagged `bench-pc` on the Windows PC and reports back on the PR, for the bench-pc
# skill (.claude/skills/bench-pc). Runs from a clone under Git Bash and leaves that clone alone:
# it checks out the PR's head sha detached in a bench worktree, $BENCH_PC_TREE (default
# pile-up-bench-pc beside the clone, made on the first run and forced clean on each), runs that commit's
# tools/bench_release.sh for each case the PR's Performance section has a `### bench_...` heading
# for (dense-1000 with and without the army when it has none), and posts one comment headed
# "PC (3080)" with the fingerprinted tables. A missed target is still a result: the PC's numbers
# are for information only.
#
# Exits 0 when it posted the tables and swapped the label to bench-pc-done (or the PR isn't
# flagged any more), 75 when the PC is busy (a game running, or the CPU or GPU loaded) and nothing
# was touched, and 1 when it failed: it then posts the error and swaps the label to
# bench-pc-failed.
#
# Usage: tools/bench_pc.sh <pr-number>
set -u

# The busy check's limits: a game process from these folders, or load above these percentages.
GAME_PATHS='steamapps\\common|Epic Games|XboxGames|GOG Games'
MAX_CPU=${BENCH_PC_MAX_CPU:-30}
MAX_GPU=${BENCH_PC_MAX_GPU:-20}

root=$(cd "$(dirname "$0")/.." && pwd)
tree=${BENCH_PC_TREE:-$root/../pile-up-bench-pc}

# Runs the PowerShell command $1, with Windows line endings stripped.
powershell() {
	powershell.exe -NoProfile -Command "$1" 2>/dev/null | tr -d '\r'
}

# Prints why the PC is busy, or nothing when it is free. A load it can't read counts as free.
busy_reason() {
	local game cpu gpu
	# The $s in single quotes are PowerShell's.
	# shellcheck disable=SC2016
	game=$(powershell "Get-Process | Where-Object { \$_.Path -match '$GAME_PATHS' } | Select-Object -ExpandProperty ProcessName" | head -1)
	if [ -n "$game" ]; then
		echo "a game is running ($game)"
		return
	fi
	cpu=$(powershell "(Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average" | cut -d. -f1)
	if [ -n "$cpu" ] && [ "$cpu" -gt "$MAX_CPU" ] 2>/dev/null; then
		echo "the CPU is at $cpu% (over $MAX_CPU%)"
		return
	fi
	gpu=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | tr -d '\r ' | sort -n | tail -1)
	if [ -n "$gpu" ] && [ "$gpu" -gt "$MAX_GPU" ] 2>/dev/null; then
		echo "the GPU is at $gpu% (over $MAX_GPU%)"
	fi
}

# Prints the bench_release.sh arguments to run, one case a line: the PR body's `### bench_...`
# headings in order without repeats, or the per-ticket pair when there are none.
cases() {
	local found
	found=$(tr -d '\r' | sed -nE 's/^### (bench_frame|bench_profile( (dense-1000|dense-1390|wave-20))?( --army)?)[[:space:]]*$/\1/p' | awk '!seen[$0]++')
	if [ -n "$found" ]; then
		echo "$found"
	else
		printf 'bench_profile dense-1000\nbench_profile dense-1000 --army\n'
	fi
}

# Posts the comment in $comment and swaps the bench-pc label for $1.
report() {
	gh pr comment "$pr" --body-file "$comment" >/dev/null &&
		gh pr edit "$pr" --remove-label bench-pc --add-label "$1" >/dev/null
}

# Posts a failure: $1 is what failed, $2 a file whose tail is the error. Exits 1.
failed() {
	{
		echo "## PC (3080): bench failed"
		echo
		echo "Commit ${sha:-unknown}: $1. Not retried; relabel \`bench-pc\` to run it again."
		echo
		echo '```text'
		tail -n 40 "$2"
		echo '```'
	} >"$comment"
	report bench-pc-failed
	echo "bench_pc: #$pr failed: $1" >&2
	exit 1
}

main() {
	pr=${1:-}
	if ! [[ $pr =~ ^[0-9]+$ ]]; then
		sed -n 's/^# Usage: /Usage: /p' "$0" >&2
		exit 2
	fi
	work=$(mktemp -d)
	trap 'rm -rf "$work"' EXIT
	comment="$work/comment.md"
	sha=""

	if ! gh pr view "$pr" --json labels --jq '.labels[].name' | grep -qx bench-pc; then
		echo "bench_pc: #$pr isn't flagged bench-pc, nothing to do"
		exit 0
	fi
	local reason
	reason=$(busy_reason)
	if [ -n "$reason" ]; then
		echo "bench_pc: busy, $reason; #$pr is left flagged for later"
		exit 75
	fi

	sha=$(gh pr view "$pr" --json headRefOid --jq .headRefOid)
	gh pr view "$pr" --json body --jq .body | cases >"$work/cases"
	# The submodule is for scons, when CI has no dll for the sha; it is cloned once per tree.
	if ! { git -C "$root" fetch -q origin "pull/$pr/head" &&
		if [ -e "$tree" ]; then
			git -C "$tree" checkout -q -f --detach "$sha" && git -C "$tree" clean -q -fd
		else
			git -C "$root" worktree add -q --detach "$tree" "$sha"
		fi && git -C "$tree" submodule -q update --init; } >"$work/git.log" 2>&1; then
		failed "checking out the PR head in $tree" "$work/git.log"
	fi
	cd "$tree" || exit 1

	{
		echo "## PC (3080)"
		echo
		echo "Commit $sha, \`tools/bench_release.sh\` on the PC. For information only: the targets are on the M5."
	} >"$comment"
	local args code
	while read -r args; do
		# Word splitting turns the case line into the script's arguments.
		# shellcheck disable=SC2086
		tools/bench_release.sh $args >"$work/out" 2>"$work/err"
		code=$?
		# A missed target exits 1 with a whole table, ending in a FAIL verdict.
		if [ "$code" -ne 0 ] && ! grep -q '(FAIL)\.$' "$work/out"; then
			cat "$work/out" >>"$work/err"
			failed "\`$args\` exited $code" "$work/err"
		fi
		{
			echo
			cat "$work/out"
		} >>"$comment"
	done <"$work/cases"

	report bench-pc-done || exit 1
	echo "bench_pc: #$pr benched at $sha and labelled bench-pc-done"
}

main "$@"
