#!/bin/sh
# PROTOTYPE (#236): plays the real game with throwaway v5 jumpers, jumps and perching on top.
cd "$(dirname "$0")/../../.." && exec /Applications/Godot.app/Contents/MacOS/Godot --path . res://src/view/proto_jumps/jumps_proto.tscn
