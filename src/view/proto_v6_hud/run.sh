#!/bin/sh
# PROTOTYPE (#286): plays the real game with v6's pace, alert, quota and Debrief faked over it.
cd "$(dirname "$0")/../../.." && exec /Applications/Godot.app/Contents/MacOS/Godot --path . res://src/view/proto_v6_hud/v6_hud_proto.tscn
