extends RefCounted
## The Legendary holographic foil (HeroSprite.holo, src/art/holo_foil.gdshader): on for every look of
## the Legendary heroes, off for everyone else, switchable (battle units turn it off), the face
## ellipse comes from the rig source, the face bone never takes foil.


func _legendaries() -> Array[String]:
	var out: Array[String] = []
	for d: Dictionary in HeroData.all():
		if str(d.get("rarity", "")) == "legendary":
			out.append(str(d.id))
	return out


func test_legendaries_wear_the_foil_in_every_look(t: TestCtx) -> void:
	var ids := _legendaries()
	t.eq(ids.size(), 9, "nine Legendary heroes")
	for id in ids:
		var looks: Array[String] = [""]
		for sd: Dictionary in SkinData.for_hero(id):
			if HeroArt.has_skin_art(id, str(sd.id)):
				looks.append(str(sd.id))
		for sid in looks:
			var spr := HeroArt.make_sprite(id, sid) as HeroSprite
			t.ok(spr != null and spr.rig != null, "%s %s builds" % [id, sid])
			if spr == null or spr.rig == null:
				continue
			t.ok(spr.holo, "%s %s: holo on" % [id, sid])
			t.eq(spr.rig.warp_shader(), HeroSprite.HOLO_SHADER, "%s %s: drawn with the foil" % [id, sid])
			var fe: Variant = spr.rig.get_warp_param(&"face_ellipse")
			t.ok(fe is Vector4 and (fe as Vector4).z > 20.0 and (fe as Vector4).y < -300.0,
				"%s %s: a face ellipse above her feet (%s)" % [id, sid, str(fe)])
			var w: Variant = spr.rig.get_warp_param(&"bone_foil")
			var fb := spr.rig.rig.bone("face")
			t.ok(w is PackedFloat32Array and fb >= 0 and (w as PackedFloat32Array)[fb] == 0.0,
				"%s %s: no foil on the face bone" % [id, sid])
			spr.free()


func test_others_have_no_foil_and_it_switches(t: TestCtx) -> void:
	var legend := _legendaries()
	for d: Dictionary in HeroData.all():
		var id := str(d.id)
		if legend.has(id):
			continue
		var spr := HeroArt.make_sprite(id) as HeroSprite
		if spr == null or spr.rig == null:
			continue
		t.ok(not spr.holo, "%s: no holo" % id)
		t.ok(spr.rig.warp_shader() != HeroSprite.HOLO_SHADER, "%s: the plain warp shader" % id)
		spr.free()
	# A battle unit turns it off (unit_view.gd) and the plain warp shader comes back; on again works.
	var s := HeroArt.make_sprite(legend[0]) as HeroSprite
	s.holo = false
	t.eq(s.rig.warp_shader(), RigPlayer.WARP_SHADER, "holo off: the plain warp shader")
	t.eq(s.rig.get_warp_param(&"body_bone"), s.rig.rig.body_bone, "the skinning uniforms are set again")
	s.holo = true
	t.eq(s.rig.warp_shader(), HeroSprite.HOLO_SHADER, "holo on again")
	t.eq(s.rig.get_warp_param(&"motion"), 1.0, "moving with the tilt (Reduce motion off)")
	s.free()


func test_face_ellipse_from_the_rig_source(t: TestCtx) -> void:
	# seraphiel.warp_src.json (the v20 MOSS art s102800, 2026-10-24): face ellipse centre (460, 699), radius (77, 64);
	# origin (512, 1990).
	var r := RigData.load_rig("seraphiel")
	t.eq(r.face_ellipse(), Vector4(-52, -1291, 77, 64), "seraphiel: the face region from her rig source")
	# Without a source the portrait frame stands in (it is framed on the face).
	var est := RigData.new()
	est.origin = Vector2(512, 1990)
	est.portrait_rect = Rect2(353.5, 764.5, 369, 369)
	var e := est.face_ellipse()
	t.near(e.x, 26.0, 2.0, "estimate x")
	t.near(e.y, -1035.0, 8.0, "estimate y")
	t.near(e.z, 64.0, 4.0, "estimate radius x")
