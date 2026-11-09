#!/usr/bin/env bash
# Checks tools/bench_pc.sh against a scratch clone whose origin holds a PR head, with fake gh,
# nvidia-smi and powershell.exe on PATH. The PR head carries a fake tools/bench_release.sh
# that prints the sha it ran on and its arguments, so a table shows which commit was benched.
set -u

cd "$(dirname "$0")/.." || exit 1
status=0
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
fakes="$scratch/fakes"
mkdir -p "$fakes"

cat >"$fakes/gh" <<'FAKE'
#!/usr/bin/env bash
echo "gh $*" >>"$FAKE_CALLS"
[ -n "${FAKE_GH_DOWN:-}" ] && echo "error connecting to api.github.com" >&2 && exit 1
case "$1 $2" in
"pr view")
	case $5 in
	body) printf '%s\n' "${FAKE_BODY:-}" ;;
	labels) printf '%s\n' "${FAKE_LABELS-bench-pc}" ;;
	esac
	;;
"pr comment")
	while [ $# -gt 0 ]; do
		[ "$1" = "--body-file" ] && cp "$2" "$FAKE_COMMENT"
		shift
	done
	;;
esac
FAKE

cat >"$fakes/nvidia-smi" <<'FAKE'
#!/usr/bin/env bash
echo "${FAKE_GPU:-3}"
FAKE

# Answers the busy check's two questions: CPU load, and game processes.
cat >"$fakes/powershell.exe" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
*LoadPercentage*) printf '%s\r\n' "${FAKE_CPU:-5}" ;;
*Get-Process*) [ -n "${FAKE_GAME:-}" ] && printf '%s\r\n' "$FAKE_GAME" ;;
esac
exit 0
FAKE
chmod +x "$fakes"/*

# The fake bench committed on the PR head: a table for its args, or $FAKE_BENCH's behaviour.
fake_bench() {
	cat <<'FAKE'
#!/usr/bin/env bash
echo "bench $*" >>"$FAKE_CALLS"
# powershell.exe reads stdin, so the bench must not get the case list.
cat >/dev/null
case "${FAKE_BENCH:-pass}" in
export-fails)
	echo "bench_release: the Windows Desktop export failed" >&2
	exit 1
	;;
crash)
	echo "### $*"
	echo '```text'
	echo "Segmentation fault" >&2
	exit 139
	;;
esac
echo "### $*"
echo
echo "| Commit | $(git rev-parse --short HEAD) |"
echo '```text'
echo "TABLE $*"
[ "${FAKE_BENCH:-pass}" = missed ] && echo "Target: tick p99 13.00 ms against 12.00 ms (FAIL)." && exit 1
echo "Target: (pass)."
echo '```'
FAKE
}

# A fresh origin with main and a PR head (refs/pull/7/head) one commit ahead, and a clone of
# main at $scratch/project, with no bench tree yet. $scratch/sha holds the PR head's sha.
project() {
	rm -rf "$scratch/origin" "$scratch/project" "$scratch/work" "$scratch/tree"
	git init -q --bare -b main "$scratch/origin"
	git init -q -b main "$scratch/work"
	(
		cd "$scratch/work" &&
			mkdir tools &&
			cp "$OLDPWD/tools/bench_pc.sh" tools/ &&
			printf '#!/usr/bin/env bash\nexit 3\n' >tools/bench_release.sh &&
			chmod +x tools/*.sh &&
			git add -A &&
			git -c user.name=t -c user.email=t@t commit -qm main &&
			git push -q "$scratch/origin" main &&
			fake_bench >tools/bench_release.sh &&
			git -c user.name=t -c user.email=t@t commit -qam pr &&
			git push -q "$scratch/origin" HEAD:refs/pull/7/head &&
			git rev-parse HEAD >"$scratch/sha"
	)
	git clone -q "$scratch/origin" "$scratch/project"
	: >"$scratch/calls"
	rm -f "$scratch/comment"
}

# Runs the script in the scratch clone with the given args, keeping stdout in $scratch/out and
# returning its exit status.
run() {
	(
		cd "$scratch/project" &&
			PATH="$fakes:$PATH" BENCH_PC_TREE="$scratch/tree" FAKE_CALLS="$scratch/calls" \
				FAKE_COMMENT="$scratch/comment" tools/bench_pc.sh "$@" >"$scratch/out" 2>"$scratch/err"
	)
}

fail() {
	echo "FAIL: $1"
	status=1
}

# $1 is the check's name, $2 a file and $3 a fixed string that must appear in it.
has() {
	grep -qF -- "$3" "$2" 2>/dev/null || fail "$1: no '$3' in $(basename "$2")"
}

# $1 is the check's name, $2 a file and $3 a fixed string that must not appear in it.
lacks() {
	! grep -qF -- "$3" "$2" 2>/dev/null || fail "$1: '$3' in $(basename "$2")"
}

project
short=$(cut -c1-7 "$scratch/sha")
FAKE_BODY=$'## Performance\n\n### bench_profile dense-1000\n\nx\n\n### bench_profile dense-1000 --army\n\n### bench_profile dense-1000\n' \
	run 7 || fail "a pass exited non-zero: $(cat "$scratch/err")"
has "the PR head is benched" "$scratch/comment" "| Commit | $short |"
has "the first heading is run" "$scratch/comment" "TABLE bench_profile dense-1000"
has "the second heading is run" "$scratch/comment" "TABLE bench_profile dense-1000 --army"
[ "$(grep -c '^bench ' "$scratch/calls")" -eq 2 ] || fail "a repeated heading is benched once: $(cat "$scratch/calls")"
has "the comment is titled for the Mac to find" "$scratch/comment" "## PC (3080)"
has "the comment says the numbers are for information" "$scratch/comment" "information only"
has "the label is swapped to done" "$scratch/calls" "pr edit 7 --remove-label bench-pc --add-label bench-pc-done"
[ "$(git -C "$scratch/tree" rev-parse HEAD)" = "$(cat "$scratch/sha")" ] || fail "the bench tree isn't on the PR head"
[ -z "$(git -C "$scratch/tree" symbolic-ref -q HEAD)" ] || fail "the bench tree isn't detached"
[ "$(git -C "$scratch/project" rev-parse --abbrev-ref HEAD)" = main ] || fail "the clone left main"
run 7 || fail "a second run in the same bench tree exited non-zero: $(cat "$scratch/err")"

project
run 7 || fail "a body with no headings exited non-zero: $(cat "$scratch/err")"
has "with no headings, dense-1000 is run" "$scratch/calls" "bench bench_profile dense-1000"
has "with no headings, dense-1000 --army is run" "$scratch/calls" "bench bench_profile dense-1000 --army"
lacks "a missing body heading runs no bench_frame" "$scratch/calls" "bench bench_frame"

project
FAKE_BODY=$'### bench_frame\n### bench_profile wave-20 --army' run 7 || fail "bench_frame heading exited non-zero"
has "a bench_frame heading is run" "$scratch/calls" "bench bench_frame"
has "a wave-20 heading is run" "$scratch/calls" "bench bench_profile wave-20 --army"

project
FAKE_BENCH=missed run 7 || fail "a missed target exited non-zero: $(cat "$scratch/err")"
has "a missed target is still posted" "$scratch/comment" "(FAIL)."
has "a missed target is still done" "$scratch/calls" "--add-label bench-pc-done"

project
FAKE_GAME="eldenring" run 7
[ $? -eq 75 ] || fail "a running game didn't exit 75"
has "a running game is named" "$scratch/out" "eldenring"
project
FAKE_GPU=85 run 7
[ $? -eq 75 ] || fail "a loaded GPU didn't exit 75"
project
FAKE_CPU=70 run 7
[ $? -eq 75 ] || fail "a loaded CPU didn't exit 75"
lacks "busy runs no bench" "$scratch/calls" "bench "
lacks "busy posts nothing" "$scratch/calls" "pr comment"
lacks "busy leaves the labels" "$scratch/calls" "pr edit"
[ ! -e "$scratch/tree" ] || fail "busy checked something out"

project
FAKE_LABELS="bench-pc-done" run 7 || fail "an unflagged PR exited non-zero"
lacks "an unflagged PR isn't benched" "$scratch/calls" "bench "
lacks "an unflagged PR gets no comment" "$scratch/calls" "pr comment"

project
FAKE_BENCH=export-fails run 7 && fail "a failed export exited zero"
has "a failure is posted with its error" "$scratch/comment" "the Windows Desktop export failed"
has "a failure names the case" "$scratch/comment" "bench_profile dense-1000"
has "a failure is labelled failed" "$scratch/calls" "pr edit 7 --remove-label bench-pc --add-label bench-pc-failed"
lacks "a failure stops at the first case" "$scratch/calls" "bench bench_profile dense-1000 --army"

project
FAKE_BENCH=crash run 7 && fail "a crash exited zero"
has "a crash is posted" "$scratch/comment" "Segmentation fault"
has "a crash is labelled failed" "$scratch/calls" "--add-label bench-pc-failed"

project
run 7 || fail "a first run exited non-zero"
echo "exit 9" >>"$scratch/tree/tools/bench_release.sh"
touch "$scratch/tree/stray"
run 7 || fail "a dirty bench tree exited non-zero: $(cat "$scratch/err")"
[ -z "$(git -C "$scratch/tree" status --porcelain)" ] || fail "the dirty bench tree wasn't cleaned"

project
FAKE_GH_DOWN=1 run 7
[ $? -eq 75 ] || fail "gh being down didn't exit 75"
has "gh being down says so" "$scratch/out" "error connecting"
[ ! -e "$scratch/tree" ] || fail "gh being down checked something out"

project
run && fail "no PR number exited zero"
lacks "no PR number calls gh" "$scratch/calls" "gh "

exit $status
