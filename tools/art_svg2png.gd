extends SceneTree
## Rasterize SVG files with Godot's own SVG renderer (ThorVG), exactly as the game sees them.
##   tools/gd --headless --path . -s tools/art_svg2png.gd -- in.svg out.png [scale] [in2.svg out2.png scale2 ...]
## Paths may be absolute or res://. Prints one line per file and any error.


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i + 1 < a.size():
		var src: String = a[i]
		var dst: String = a[i + 1]
		var sc := 1.0
		if i + 2 < a.size() and a[i + 2].is_valid_float():
			sc = a[i + 2].to_float()
			i += 1
		i += 2
		var txt := FileAccess.get_file_as_string(src)
		if txt == "":
			printerr("ERROR: cannot read ", src)
			continue
		var img := Image.new()
		var t0 := Time.get_ticks_msec()
		var err := img.load_svg_from_string(txt, sc)
		if err != OK:
			printerr("ERROR: svg render failed for ", src, " (", err, ")")
			continue
		img.save_png(dst)
		print("%s -> %s %dx%d (%d ms)" % [src.get_file(), dst.get_file(), img.get_width(), img.get_height(), Time.get_ticks_msec() - t0])
	quit()
