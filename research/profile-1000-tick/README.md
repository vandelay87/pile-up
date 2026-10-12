# Profile a 1,000-enemy tick (#157): raw runs

Throwaway branch, never merged. `src/sim/prof.gd` and the `Prof.add` marks time each tick system;
`tools/bench_profile.tscn` runs a scenario and prints the tables in this folder.

How the release runs were made: a copy of the project with `run/main_scene` set to
`res://tools/bench_profile.tscn` and `tools/*` dropped from the macOS preset's exclude filter,
exported with the official 4.7.2 release template, then

    pile-up.app/Contents/MacOS/pile-up --fixed-fps 60 -- --scenario=dense-1000   # or dense-1390, wave-20

`--fixed-fps 60` gives one tick per frame. Files: `rel-<scenario>-<run>.txt` (release, Apple M5),
`debug-1000-1.txt` (editor binary, before `--fixed-fps` and the even/odd shadow-pass split).

The "view process" row in the helper tables is not trustworthy (it does not agree with
bench_frame's frame CPU split); ignore it and use `tools/bench_frame.tscn` for frame costs.
