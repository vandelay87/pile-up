#!/usr/bin/env bash
# Checks tools/bench_release.sh against a scratch project, with fake godot, uname, gh and scons
# on PATH. The fake godot's export writes a fake game binary that prints its arguments, and logs
# what the copied project's settings were at export time.
set -u

cd "$(dirname "$0")/.." || exit 1
status=0
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
fakes="$scratch/fakes"
mkdir -p "$fakes"

cat >"$fakes/godot" <<'FAKE'
#!/usr/bin/env bash
if [ "$1" = "--version" ]; then
	echo "4.7.2.stable.official.fake"
	exit 0
fi
while [ $# -gt 0 ]; do
	case $1 in
	--path) dir=$2 ;;
	--export-release)
		preset=$2
		out=$3
		;;
	esac
	shift
done
[ -n "${preset:-}" ] || exit 0
{
	echo "preset=$preset"
	grep '^run/main_scene=' "$dir/project.godot"
	sed -n "/^name=\"$preset\"/,/^\[preset\.[0-9]*\]$/p" "$dir/export_presets.cfg" | grep -E '^exclude_filter=|^debug/export_console_wrapper='
	for dll in "$dir"/bin/*.dll; do
		[ -f "$dll" ] && echo "dll=$(cat "$dll")"
	done
} >"$FAKE_LOG"
game=$out
case $out in
*.app) game="$out/Contents/MacOS/pile-up" ;;
*.exe) game="${out%.exe}.console.exe" ;;
esac
mkdir -p "$(dirname "$game")"
printf '#!/usr/bin/env bash\necho "Godot Engine v4.7.2.stable"\necho "TABLE $*"\nexit "${FAKE_BENCH_STATUS:-0}"\n' >"$game"
chmod +x "$game"
FAKE

cat >"$fakes/uname" <<'FAKE'
#!/usr/bin/env bash
echo "$FAKE_UNAME"
FAKE

cat >"$fakes/gh" <<'FAKE'
#!/usr/bin/env bash
echo "gh $*" >>"$FAKE_CALLS"
if [ -n "${FAKE_NO_ARTIFACT:-}" ]; then
	[ "$1 $2" = "run list" ] && exit 0
	exit 1
fi
case "$1 $2" in
"run list") echo 4242 ;;
"run download")
	while [ $# -gt 0 ]; do
		[ "$1" = "--dir" ] && dir=$2
		shift
	done
	mkdir -p "$dir"
	echo artifact >"$dir/libpileup.windows.template_release.x86_64.dll"
	;;
esac
FAKE

cat >"$fakes/scons" <<'FAKE'
#!/usr/bin/env bash
echo "scons $*" >>"$FAKE_CALLS"
echo scons >bin/libpileup.windows.template_release.x86_64.dll
FAKE
chmod +x "$fakes"/*

# A fresh scratch project, a git repo with a clean tree, at $scratch/project.
project() {
	rm -rf "$scratch/project"
	mkdir -p "$scratch/project/tools" "$scratch/project/bin" "$scratch/project/native"
	cp tools/bench_release.sh "$scratch/project/tools/"
	cp export_presets.cfg "$scratch/project/"
	printf '[application]\n\nrun/main_scene="res://src/view/main.tscn"\n' >"$scratch/project/project.godot"
	printf '/bin/*\n!/bin/pile_up.gdextension\n' >"$scratch/project/.gitignore"
	touch "$scratch/project/bin/pile_up.gdextension"
	echo dylib >"$scratch/project/bin/libpileup.macos.template_release.universal.dylib"
	(
		cd "$scratch/project" &&
			git init -q &&
			git add -A &&
			git -c user.name=t -c user.email=t@t commit -qm init
	)
	: >"$scratch/calls"
	: >"$scratch/export.log"
}

# Runs the script in the scratch project as uname $1 with the remaining args, keeping stdout in
# $scratch/out and returning its exit status.
run() {
	local os=$1
	shift
	(
		cd "$scratch/project" &&
			PATH="$fakes:$PATH" GODOT_BIN="$fakes/godot" FAKE_UNAME=$os FAKE_LOG="$scratch/export.log" \
				FAKE_CALLS="$scratch/calls" tools/bench_release.sh "$@" >"$scratch/out" 2>"$scratch/err"
	)
}

fail() {
	echo "FAIL: $1"
	status=1
}

# $1 is the check's name, $2 a file and $3 a fixed string that must appear in it.
has() {
	grep -qF -- "$3" "$2" || fail "$1: no '$3' in $(basename "$2")"
}

project
run Darwin bench_profile dense-1000 --army || fail "mac run exited non-zero: $(cat "$scratch/err")"
has "mac runs the export" "$scratch/out" "TABLE --fixed-fps 60 -- --case=dense-1000 --army"
has "mac exports the macOS preset" "$scratch/export.log" "preset=macOS"
has "the bench is the main scene" "$scratch/export.log" 'run/main_scene="res://tools/bench_profile.tscn"'
has "tools/* is exported" "$scratch/export.log" 'exclude_filter="test/*, addons/gdUnit4/*, reports/*"'
[ -z "$(cd "$scratch/project" && git status --porcelain)" ] || fail "the working tree changed"

project
run MINGW64_NT-10.0-26100 bench_profile dense-1000 --army || fail "windows run exited non-zero: $(cat "$scratch/err")"
has "windows runs the console wrapper" "$scratch/out" "TABLE --fixed-fps 60 -- --case=dense-1000 --army"
has "windows exports the Windows preset" "$scratch/export.log" "preset=Windows Desktop"
has "windows prints to the console" "$scratch/export.log" "debug/export_console_wrapper=2"
has "the dll comes from CI" "$scratch/export.log" "dll=artifact"
has "the artifact is the sha's" "$scratch/calls" "--commit $(cd "$scratch/project" && git rev-parse HEAD)"
[ ! -e "$scratch/project/bin/libpileup.windows.template_release.x86_64.dll" ] || fail "the artifact landed in the tree"

project
FAKE_NO_ARTIFACT=1 run MINGW64_NT-10.0-26100 bench_frame || fail "windows scons run exited non-zero: $(cat "$scratch/err")"
has "with no artifact, scons builds" "$scratch/calls" "scons -C native target=template_release"
has "with no artifact, the dll is scons's" "$scratch/export.log" "dll=scons"
has "bench_frame is the main scene" "$scratch/export.log" 'run/main_scene="res://tools/bench_frame.tscn"'
has "bench_frame takes no case" "$scratch/out" "TABLE --fixed-fps 60 --"

project
FAKE_BENCH_STATUS=1 run Darwin bench_profile wave-20 && fail "a missed target exited zero"
has "a missed target still prints the table" "$scratch/out" "TABLE --fixed-fps 60 -- --case=wave-20"
has "the output is headed by the run" "$scratch/out" "### bench_profile wave-20"
has "the fingerprint has the Godot version" "$scratch/out" "| Godot | 4.7.2.stable.official.fake |"
has "the fingerprint has the sha" "$scratch/out" "| Commit | $(cd "$scratch/project" && git rev-parse --short HEAD) |"
for row in CPU GPU OS Power Load; do
	has "the fingerprint has $row" "$scratch/out" "| $row |"
done
has "the table is in a code block" "$scratch/out" '```text'
grep -q "^Godot Engine" "$scratch/out" && fail "the engine banner is in the table"

exit $status
