extends RefCounted
## PhysicalKit: the living growths (growth maps beside every growth render, come_alive, wither).

const SHAPES := ["tl", "tr", "br", "bl", "edge", "clump_a", "clump_b"]


func test_every_growth_has_a_map(t: TestCtx) -> void:
	var paths: Array[String] = []
	for fac: String in ["celestial", "fallen", "infernal"]:
		for shape: String in SHAPES:
			paths.append(PhysicalKit.DIR + PhysicalKit.growth_name(fac, shape) + ".png")
	paths.append("res://assets/art/ui/objects/thorns_corner.png")
	paths.append("res://assets/art/ui/objects/thorns_vine.png")
	for p in paths:
		var map := p.get_basename() + "_grow.png"
		t.ok(ResourceLoader.exists(map), "growth map for " + p)
		var inf := PhysicalKit.growth_info(p)
		var root: Array = inf.get("root", [])
		t.eq(root.size(), 2, "growth.json root for " + p)
		if root.size() == 2:
			t.ok(float(root[0]) >= 0.0 and float(root[0]) <= 1.0 and float(root[1]) >= 0.0 and float(root[1]) <= 1.0, "root in UV for " + p)
		t.ok(float(inf.get("len", 0.0)) > 50.0, "branch length for " + p)
		if ResourceLoader.exists(map) and ResourceLoader.exists(p):
			# Half the render's size, so it lines up with it in UV.
			var tex := load(p) as Texture2D
			var mt := load(map) as Texture2D
			t.eq(mt.get_width(), (tex.get_width() + 1) / 2, "map width for " + p)
			t.eq(mt.get_height(), (tex.get_height() + 1) / 2, "map height for " + p)


func test_growth_comes_alive_unsprouted(t: TestCtx) -> void:
	var parent := Control.new()
	var tr := PhysicalKit.growth("celestial", "tl", parent, Vector2(20, 20), 70.0)
	t.ok(tr != null, "growth placed")
	if tr == null:
		parent.free()
		return
	if Kit.motion_ok():
		var m := tr.material as ShaderMaterial
		t.ok(m != null and m.shader == PhysicalKit.GROWTH_SHADER, "growth material")
		if m:
			t.eq(float(m.get_shader_parameter("grow")), 0.0, "starts unsprouted")
			t.ok(float(m.get_shader_parameter("sway_px")) <= 2.6, "tips sway a few px at most")
			t.eq(m.get_shader_parameter("draw_size"), tr.size, "drawn size")
		t.ok(tr.get_node_or_null("Sprout") != null, "waits to sprout")
	parent.free()


func test_flipped_growth_mirrors_the_map(t: TestCtx) -> void:
	var parent := Control.new()
	var tr := TextureRect.new()
	tr.texture = load("res://assets/art/ui/objects/thorns_vine.png")
	tr.flip_h = true
	tr.size = Vector2(230, 282)
	parent.add_child(tr)
	var m := PhysicalKit.come_alive(tr)
	if Kit.motion_ok():
		t.ok(m != null, "rival thorns come alive")
		if m:
			t.eq(m.get_shader_parameter("flip"), Vector2(-1, 1), "mirrored like the render")
	parent.free()


func test_wither_without_tree_frees(t: TestCtx) -> void:
	var tr := TextureRect.new()
	PhysicalKit.wither(tr)
	t.ok(tr.is_queued_for_deletion(), "freed at once outside the tree")
