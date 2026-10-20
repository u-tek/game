#!/usr/bin/env bash
# Windows: run tools/art_preview.gd with the window parked where tools/shoot parks it (left monitor), no focus.
# Usage: tools/layered/run_preview.sh <jobs.json>
cd "/d/AI/claude game" || exit 1
export GODOT=/c/Users/jenso/tools/godot-4.5.1/Godot_v4.5.1-stable_win64_console.exe
[ -f override.cfg ] && { echo "override.cfg exists, abort"; exit 1; }
printf '%s\n' '[display]' '' 'window/size/no_focus=true' 'window/size/initial_position_type=0' \
  'window/size/initial_position=Vector2i(60,120)' > override.cfg
trap 'rm -f override.cfg' EXIT
timeout 900 "$GODOT" --path . --rendering-driver vulkan --resolution 64x64 -s tools/art_preview.gd -- "$1" 2>&1 \
  | grep -vE "Godot Engine|Vulkan|OpenGL API|^$" | grep -E "art_preview|SCRIPT ERROR|Parse Error|ERROR:" -A2 | head -40
