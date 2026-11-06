#!/usr/bin/env bash
# Runs a bench in the release export, on the Mac or on the Windows PC under Git Bash, and prints
# a machine fingerprint and the bench's tables as Markdown ready to paste into a PR. Exits with the
# bench's status, so a missed target fails.
#
# Exports a copy of the project with the bench as the main scene and tools/* exported, so the
# working tree is left alone. Godot is $GODOT_BIN (on Windows the console exe, or Git Bash sees
# none of its output). On the Mac the native library is the local
# build in bin/; on Windows it is CI's native-windows artifact for HEAD's sha (through gh), or a
# local scons build when there is none.
#
# Usage: tools/bench_release.sh bench_profile [dense-1000|dense-1390|wave-20] [--army]
#        tools/bench_release.sh bench_frame
set -u

GODOT_BIN=${GODOT_BIN:-godot}
root=$(cd "$(dirname "$0")/.." && pwd)

usage() {
	sed -n 's/^# Usage: /       /p; s/^#        /       /p' "$0" | sed '1s/^       /Usage: /' >&2
	exit 2
}

bench=${1:-}
[ $# -gt 0 ] && shift
bench_args=()
title=$bench
case $bench in
bench_profile)
	bench_case=dense-1000
	army=""
	for arg in "$@"; do
		case $arg in
		dense-1000 | dense-1390 | wave-20) bench_case=$arg ;;
		--army) army=--army ;;
		*) usage ;;
		esac
	done
	bench_args=("--case=$bench_case")
	[ -n "$army" ] && bench_args+=("$army")
	title="$bench $bench_case${army:+ $army}"
	;;
bench_frame)
	[ $# -eq 0 ] || usage
	;;
*) usage ;;
esac

# The machine fingerprint, taken before the export so its load is the machine's own: sets cpu,
# gpu, os, power and load. Anything a probe can't read is left as "unknown".
fingerprint_mac() {
	local display low_power
	cpu=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
	display=$(system_profiler SPDisplaysDataType 2>/dev/null)
	gpu="$(echo "$display" | sed -n 's/^ *Chipset Model: //p' | head -1)"
	gpu="$gpu, $(echo "$display" | sed -n 's/^ *Total Number of Cores: //p' | head -1) cores"
	gpu="$gpu, $(echo "$display" | sed -n 's/^ *Metal Support: //p' | head -1)"
	os="macOS $(sw_vers -productVersion 2>/dev/null) ($(sw_vers -buildVersion 2>/dev/null))"
	low_power=$(pmset -g 2>/dev/null | awk '/lowpowermode/ { print ($2 == 1) ? "on" : "off" }')
	power="$(pmset -g batt 2>/dev/null | sed -n "s/^Now drawing from '\(.*\)'/\1/p"), low power mode ${low_power:-unknown}"
	load="CPU load average $(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{ print $1 }')"
	load="$load, GPU $(ioreg -r -d 1 -c IOAccelerator 2>/dev/null | sed -n 's/.*"Device Utilization %"=\([0-9]*\).*/\1/p' | head -1)%"
}

# Runs the PowerShell command $1, with Windows line endings stripped.
powershell() {
	powershell.exe -NoProfile -Command "$1" 2>/dev/null | tr -d '\r'
}

# The $s in single quotes are PowerShell's.
# shellcheck disable=SC2016
fingerprint_windows() {
	cpu=$(powershell "(Get-CimInstance Win32_Processor).Name")
	gpu=$(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null | tr -d '\r' | sed 's/, /, driver /')
	if [ -z "$gpu" ]; then
		gpu=$(powershell '$g = Get-CimInstance Win32_VideoController | Select-Object -First 1; "$($g.Name), driver $($g.DriverVersion)"')
	fi
	os=$(powershell '$o = Get-CimInstance Win32_OperatingSystem; "$($o.Caption) $($o.Version)"')
	power=$(powercfg -getactivescheme 2>/dev/null | tr -d '\r' | sed -n 's/.*(\(.*\)).*/\1/p')
	[ -n "$power" ] && power="$power power plan"
	load="CPU $(powershell "(Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average")%"
	load="$load, GPU $(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | tr -d '\r')%"
}

copy=$(mktemp -d)
trap 'rm -rf "$copy"' EXIT
(cd "$root" && tar -cf - --exclude=./.git --exclude=./native --exclude=./build --exclude=./reports .) |
	(cd "$copy" && tar -xf -)

# Rewrites the copy's file $1 through the filter command that follows (no sed -i: it differs on
# the Mac).
rewrite() {
	local file="$copy/$1"
	shift
	"$@" <"$file" >"$file.new" && mv "$file.new" "$file"
}

rewrite project.godot sed "s|^run/main_scene=.*|run/main_scene=\"res://tools/$bench.tscn\"|"
rewrite export_presets.cfg sed 's|^\(exclude_filter=.*\)tools/\*, |\1|'

dll=libpileup.windows.template_release.x86_64.dll

# Puts the Windows dll in the copy's bin: CI's native-windows artifact for this sha when there is
# one, or else a local release build. Any completed run will do, newest first: a run that failed
# elsewhere still has the artifact, until it expires.
fetch_dll() {
	local sha run
	sha=$(git -C "$root" rev-parse HEAD)
	for run in $(gh run list --commit "$sha" --workflow ci.yml --status completed --json databaseId --jq '.[].databaseId' 2>/dev/null); do
		if gh run download "$run" --name native-windows --dir "$copy/native-windows" >&2 &&
			[ -f "$copy/native-windows/$dll" ]; then
			echo "Native library: CI artifact from run $run" >&2
			cp "$copy/native-windows/$dll" "$copy/bin/"
			rm -rf "$copy/native-windows"
			return
		fi
	done
	echo "Native library: no CI artifact for $sha, building with scons" >&2
	(cd "$root" && scons -C native target=template_release >&2) || exit 1
	cp "$root/bin/$dll" "$copy/bin/"
}

commit=$(git -C "$root" rev-parse --short HEAD)
[ -n "$(git -C "$root" status --porcelain)" ] && commit="$commit, with uncommitted changes"

case $(uname -s) in
Darwin)
	if [ ! -f "$root/bin/libpileup.macos.template_release.universal.dylib" ]; then
		echo "bench_release: no native library in bin/; build it with: scons -C native target=template_release" >&2
		exit 1
	fi
	fingerprint_mac
	preset="macOS"
	out="$copy/build/pile-up.app"
	game="$out/Contents/MacOS/pile-up"
	;;
MINGW* | MSYS* | CYGWIN*)
	fingerprint_windows
	preset="Windows Desktop"
	out="$copy/build/pile-up.exe"
	# A release exe is a GUI app, so Git Bash only sees its output through the console wrapper.
	game="$copy/build/pile-up.console.exe"
	# The $s in single quotes are awk's.
	# shellcheck disable=SC2016
	rewrite export_presets.cfg awk -v name="name=\"$preset\"" '
		$0 == name { found = 1 }
		{ print }
		found && /^\[preset\.[0-9]+\.options\]$/ { print "debug/export_console_wrapper=2"; found = 0 }
	'
	fetch_dll
	;;
*)
	echo "bench_release: unsupported OS $(uname -s)" >&2
	exit 1
	;;
esac

mkdir -p "$copy/build"
"$GODOT_BIN" --headless --path "$copy" --import >&2
if ! "$GODOT_BIN" --headless --path "$copy" --export-release "$preset" "$out" >&2 || [ ! -e "$game" ]; then
	echo "bench_release: the $preset export failed" >&2
	exit 1
fi

echo "### $title"
echo
echo "| | |"
echo "|---|---|"
echo "| CPU | ${cpu:-unknown} |"
echo "| GPU | ${gpu:-unknown} |"
echo "| OS | ${os:-unknown} |"
echo "| Power | ${power:-unknown} |"
echo "| Load | ${load:-unknown} |"
godot_version=$("$GODOT_BIN" --version 2>/dev/null | tr -d '\r')
echo "| Godot | ${godot_version:-unknown} |"
echo "| Commit | $commit |"
echo
echo '```text'
"$game" --fixed-fps 60 -- ${bench_args[@]+"${bench_args[@]}"} 2>&1 | tr -d '\r' | grep -v '^Godot Engine v'
code=${PIPESTATUS[0]}
echo '```'
exit "$code"
