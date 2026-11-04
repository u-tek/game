extends SceneTree
## Times RigPlayer updates per rig: a layered rig (skins/live/) against the same heroine's quick rig.
##   tools/gd --headless --path . -s tools/rig_bench.gd -- seraphiel uriela kessa
## Prints the mean milliseconds per frame of each rig's _process (idle, springs and skinning), over 300
## frames at 1/60 s. Headless, so it measures the CPU side only (the iPhone's GPU draws the meshes).

func _initialize() -> void:
	var ids := OS.get_cmdline_user_args()
	if ids.is_empty():
		ids = PackedStringArray(["seraphiel"])
	for id in ids:
		for art in ["", "live"]:
			if art != "" and not RigData.exists(id, art):
				continue
			var s: Node2D = HeroArt.make_sprite(id, "") if art == "live" or not HeroArt.is_live(id) else _quick(id)
			if s == null:
				continue
			root.add_child(s)
			var rig: Node = s.get("rig")
			var t0 := Time.get_ticks_usec()
			for i in 300:
				rig.call("_process", 1.0 / 60.0)
			var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / 300.0
			print("rig_bench: %-10s %-6s %.3f ms/frame" % [id, art if art != "" else "quick", ms])
			s.queue_free()
	quit()


## Her quick rig (the base painting), even where her live look is built.
func _quick(id: String) -> Node2D:
	var s: Node2D = HeroArt.make_sprite(id, "")
	s.call("setup", id, "")
	return s
