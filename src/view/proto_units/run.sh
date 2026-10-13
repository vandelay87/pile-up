#!/bin/sh
# PROTOTYPE (#161): plays the real game with throwaway v4 soldier control on top.
cd "$(dirname "$0")/../../.." && exec /Applications/Godot.app/Contents/MacOS/Godot --path . res://src/view/proto_units/units_proto.tscn
