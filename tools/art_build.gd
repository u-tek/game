extends SceneTree
## HaloRig build tool: hero SVG -> per-part PNGs + <id>.rig.json + still + portrait.
## Spec: docs/dev/halorig.md. Usually run through the wrapper (it also imports):
##   tools/art_build [hero_id ...]
## Direct use (no import step):
##   tools/gd --headless --path . -s tools/art_build.gd -- [hero_id ...] [--check]
## --check validates only (no files written). Exit code 1 on any error.

const HEROES := "res://assets/art/heroes/"
const FORMAT_VERSION := 1
const PORTRAIT_PX := 384
const PAD := 2
const FORBIDDEN_ELEMENTS := ["filter", "style", "text", "tspan", "textPath", "image", "mask",
	"foreignObject", "pattern", "script", "feGaussianBlur", "marker", "symbol"]
const FORBIDDEN_ATTRS := ["filter", "mask", "mix-blend-mode", "style"]
const KNOWN_DATA := ["data-slot", "data-variant", "data-default", "data-bone", "data-parent",
	"data-pivot", "data-z", "data-spring", "data-bend", "data-axis", "data-length", "data-look",
	"data-tip", "data-note"]

## Standard skeleton names (docs/dev/halorig.md section 3). Non-standard names are allowed
## (hero extras) but must have a parent; they are reported as info so typos are visible.
const STANDARD := ["root", "hips", "torso", "chest", "chest_upper", "clavicle_l", "clavicle_r",
	"neck", "head", "toe_l", "toe_r",
	"eye_l", "eye_r", "brow_l", "brow_r", "mouth", "blush", "nose",
	"hair_back", "hair_top", "hair_side_l", "hair_side_r", "ahoge",
	"arm_upper_l", "arm_lower_l", "hand_l", "arm_upper_r", "arm_lower_r", "hand_r",
	"sleeve_l", "sleeve_r", "thigh_l", "shin_l", "foot_l", "thigh_r", "shin_r", "foot_r",
	"skirt_back", "skirt_front", "skirt_l", "skirt_r", "cape", "coat_l", "coat_r",
	"wing_l", "wing_r", "wing_upper_l", "wing_upper_r", "wing_lower_l", "wing_lower_r",
	"wing_head_l", "wing_head_r", "weapon", "weapon_off", "halo", "halo_back", "halo_front",
	"horn_l", "horn_r", "ear_l", "ear_r", "mantle", "collar", "belt", "shield"]
const STANDARD_PREFIX := ["hair_front_", "hair_back_", "hair_tail_", "ponytail_", "tail_",
	"ribbon_", "acc_", "fx_", "skirt_", "cape_", "wing_", "hair_side_", "sleeve_", "coat_"]

## Spring presets live in tools/art_spring_presets.json (shared with tools/art_warp_build.py).
var SPRING_PRESETS := {}

## Default head-turn ("look") parallax factors by bone name: [x, y]. 1.0 = moves with the face.
const LOOK_DEFAULTS := [
	["eye_", [1.0, 1.0]], ["brow_", [1.0, 1.05]], ["mouth", [0.95, 0.9]], ["blush", [0.9, 0.85]],
	["nose", [1.05, 0.95]], ["hair_front_", [0.7, 0.55]], ["ahoge", [0.45, 0.3]],
	["hair_top", [0.3, 0.25]], ["hair_side_", [0.25, 0.15]], ["hair_back", [-0.4, -0.25]],
	["halo_front", [0.15, 0.1]], ["halo_back", [-0.15, -0.1]], ["halo", [-0.1, -0.15]],
	["horn_", [-0.15, -0.1]], ["ear_", [-0.45, 0.2]], ["wing_head_", [-0.3, -0.1]],
]

var errors := 0
var warnings := 0
var check_only := false


func _init() -> void:
	var pj: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/art_spring_presets.json"))
	if pj is Dictionary:
		for k in pj:
			if not str(k).begins_with("_"):
				SPRING_PRESETS[k] = pj[k]
	var ids: Array[String] = []
	for a in OS.get_cmdline_user_args():
		if a == "--check":
			check_only = true
		else:
			ids.append(a)
	if ids.is_empty():
		for d in DirAccess.get_directories_at(HEROES):
			if FileAccess.file_exists(HEROES + d + "/" + d + ".svg"):
				ids.append(d)
	var t0 := Time.get_ticks_msec()
	for id in ids:
		_build(id)
	print("art_build: %d hero(es), %d error(s), %d warning(s), %d ms" % [ids.size(), errors, warnings, Time.get_ticks_msec() - t0])
	quit(1 if errors > 0 else 0)


func _err(id: String, msg: String) -> void:
	errors += 1
	printerr("ERROR: [%s] %s" % [id, msg])


func _warn(id: String, msg: String) -> void:
	warnings += 1
	print("WARNING: [%s] %s" % [id, msg])


# ------------------------------------------------------------------ XML

func _parse_xml(text: String) -> Dictionary:
	var p := XMLParser.new()
	p.open_buffer(text.to_utf8_buffer())
	var stack: Array = []
	var root: Dictionary = {}
	while p.read() == OK:
		var nt := p.get_node_type()
		if nt == XMLParser.NODE_ELEMENT:
			var el := {"name": p.get_node_name(), "attrs": {}, "children": [], "text": ""}
			for i in p.get_attribute_count():
				el.attrs[p.get_attribute_name(i)] = p.get_attribute_value(i)
			if stack.is_empty():
				if root.is_empty():
					root = el
			else:
				(stack.back().children as Array).append(el)
			if not p.is_empty():
				stack.append(el)
		elif nt == XMLParser.NODE_ELEMENT_END:
			if not stack.is_empty():
				stack.pop_back()
		elif nt == XMLParser.NODE_TEXT or nt == XMLParser.NODE_CDATA:
			if not stack.is_empty() and p.get_node_data().strip_edges() != "":
				stack.back().text += p.get_node_data().strip_edges()
	return root


func _ser(el: Dictionary, strip_data := true) -> String:
	var s := "<" + str(el.name)
	for k in el.attrs:
		if strip_data and str(k).begins_with("data-"):
			continue
		# alternates are hidden in the source SVG (display="none") so it previews correctly;
		# every part still renders on its own
		if strip_data and k == "display" and el.attrs.has("id") and el.attrs.has("data-z") or (k == "display" and el.attrs.has("data-slot")):
			continue
		s += ' %s="%s"' % [k, str(el.attrs[k]).replace("&", "&amp;").replace("\"", "&quot;").replace("<", "&lt;")]
	var kids: Array = el.children
	if kids.is_empty():
		return s + "/>"
	s += ">"
	for c in kids:
		s += _ser(c, strip_data)
	return s + "</%s>" % el.name


func _lint(id: String, el: Dictionary, where: String) -> void:
	var n := str(el.name)
	if n in FORBIDDEN_ELEMENTS or n.begins_with("fe"):
		_err(id, "%s: <%s> is not allowed (ThorVG-safe subset only)" % [where, n])
	for a in el.attrs:
		if a in FORBIDDEN_ATTRS:
			_err(id, "%s: attribute '%s' is not allowed" % [where, a])
	if el.text != "":
		_err(id, "%s: text content inside <%s> is not allowed" % [where, n])
	for c in el.children:
		_lint(id, c, where)


static func _vec(s: String) -> Vector2:
	var p := s.replace(" ", ",").split(",", false)
	if p.size() < 2:
		return Vector2(NAN, NAN)
	return Vector2(p[0].to_float(), p[1].to_float())


# ------------------------------------------------------------------ build

func _build(id: String) -> void:
	var dir := HEROES + id + "/"
	var src := dir + id + ".svg"
	var text := FileAccess.get_file_as_string(src)
	if text == "":
		_err(id, "cannot read " + src)
		return
	var root := _parse_xml(text)
	if root.get("name", "") != "svg":
		_err(id, "root element is not <svg>")
		return
	var ra: Dictionary = root.attrs
	var vb := str(ra.get("viewBox", "0 0 1024 1280")).split(" ", false)
	var cw := int(vb[2].to_float()) if vb.size() == 4 else 1024
	var ch := int(vb[3].to_float()) if vb.size() == 4 else 1280
	var origin := _vec(str(ra.get("data-origin", "%d,%d" % [cw / 2, ch - 58])))
	var texel := float(str(ra.get("data-texel-scale", "1")))
	var look_px := _vec(str(ra.get("data-look-px", "14,8")))
	var header := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d">' % [cw, ch, cw, ch]

	# Defs (shared gradients/clip paths): each part file gets only the ones it references.
	var defs := ""
	var def_map := {}
	var groups: Array = []
	for c in root.children:
		if c.name == "defs":
			_lint(id, c, "defs")
			defs += _ser(c)
			for dc in c.children:
				if dc.attrs.has("id"):
					def_map[str(dc.attrs["id"])] = _ser(dc)
		elif c.name == "g":
			groups.append(c)
		else:
			_err(id, "top-level <%s> is not a part group; wrap it in <g id=...>" % c.name)

	# ---- collect parts
	var parts: Array = []   # {id, slot, variant, default, bone, el}
	var bone_defs := {}     # bone -> {parent, pivot, attrs}
	var seen_ids := {}
	for g in groups:
		var a: Dictionary = g.attrs
		var pid := str(a.get("id", ""))
		if pid == "":
			_err(id, "top-level <g> without id")
			continue
		if seen_ids.has(pid):
			_err(id, "duplicate id '%s'" % pid)
		seen_ids[pid] = true
		_lint(id, g, pid)
		for k in a:
			if str(k).begins_with("data-") and not (k in KNOWN_DATA):
				_warn(id, "%s: unknown attribute %s" % [pid, k])
		var slot := str(a.get("data-slot", pid))
		var bone := str(a.get("data-bone", slot))
		if a.has("data-pivot") or a.has("data-parent"):
			if bone_defs.has(bone):
				_err(id, "%s: bone '%s' is defined twice (pivot/parent on two groups)" % [pid, bone])
			else:
				bone_defs[bone] = {"parent": str(a.get("data-parent", "")), "pivot": _vec(str(a.get("data-pivot", ""))), "attrs": a, "from": pid}
		var drawable: bool = not (g.children as Array).is_empty()
		if drawable:
			parts.append({"id": pid, "slot": slot, "variant": str(a.get("data-variant", "default")),
				"default": str(a.get("data-default", "")) == "1", "bone": bone, "el": g,
				"z": int(str(a.get("data-z", "-99999")))})
			if not a.has("data-z") and not a.has("data-slot"):
				_err(id, "%s: missing data-z" % pid)

	if not bone_defs.has("root"):
		bone_defs["root"] = {"parent": "", "pivot": origin, "attrs": {}, "from": "(implicit)"}

	# ---- validate bones
	for b in bone_defs:
		var bd: Dictionary = bone_defs[b]
		var pv: Vector2 = bd.pivot
		if is_nan(pv.x):
			_err(id, "bone '%s' (%s): missing or bad data-pivot" % [b, bd.from])
			bd.pivot = origin
		if b != "root":
			if bd.parent == "":
				_err(id, "bone '%s' (%s): missing data-parent" % [b, bd.from])
				bd.parent = "root"
			elif not bone_defs.has(bd.parent):
				_err(id, "bone '%s': unknown parent '%s'" % [b, bd.parent])
				bd.parent = "root"
		if not (b in STANDARD) and not _has_std_prefix(b):
			print("  info: [%s] extra bone '%s' (parent %s)" % [id, b, bd.parent])
	for p in parts:
		if not bone_defs.has(p.bone):
			_err(id, "%s: bone '%s' is not defined (add data-pivot/data-parent)" % [p.id, p.bone])
			p.bone = "root"
	# cycles + order (parents first)
	var order: Array[String] = []
	var state := {}
	for b in bone_defs:
		_topo(id, b, bone_defs, state, order)

	# ---- slots
	var slots := {}   # slot -> {bone, z, variants {}, default}
	for p in parts:
		if not slots.has(p.slot):
			slots[p.slot] = {"bone": p.bone, "z": p.z, "variants": {}, "default": "", "first": p.variant}
		var s: Dictionary = slots[p.slot]
		if s.bone != p.bone:
			_err(id, "%s: all variants of slot '%s' must use the same bone" % [p.id, p.slot])
		if p.z != -99999 and s.z == -99999:
			s.z = p.z
		if s.variants.has(p.variant):
			_err(id, "%s: duplicate variant '%s' in slot '%s'" % [p.id, p.variant, p.slot])
		s.variants[p.variant] = p
		if p.default:
			s.default = p.variant
	var zs := {}
	for sn in slots:
		var s: Dictionary = slots[sn]
		if s.default == "":
			s.default = "default" if s.variants.has("default") else s.first
		if s.z == -99999:
			_err(id, "slot '%s': missing data-z" % sn)
		if zs.has(s.z):
			_err(id, "slots '%s' and '%s' share z=%d (draw order would be ambiguous)" % [zs[s.z], sn, s.z])
		zs[s.z] = sn
	var slot_names: Array = slots.keys()
	slot_names.sort_custom(func(x, y): return slots[x].z < slots[y].z)

	if errors > 0 and check_only:
		return

	# ---- rasterize parts
	var out_dir := dir + "parts/"
	if not check_only:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
		# remove stale part PNGs (renamed/deleted parts)
		var keep := {}
		for p in parts:
			keep[p.id + ".png"] = true
		for f in DirAccess.get_files_at(out_dir):
			var base := f.trim_suffix(".import")
			if base.ends_with(".png") and not keep.has(base):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(out_dir + f))
	var bone_imgs := {}  # bone -> Array[{img, rect}] for axis estimation
	var px_total := 0
	var url_re := RegEx.create_from_string("url\\(#([^)]+)\\)")
	for p in parts:
		var body := _ser(p.el)
		var used := {}
		for m in url_re.search_all(body):
			used[m.get_string(1)] = true
		var pdefs := "<defs>"
		for k in used:
			if def_map.has(k):
				pdefs += def_map[k]
			else:
				_err(id, "%s: references missing def #%s" % [p.id, k])
		pdefs += "</defs>"
		var svg: String = header + pdefs + body + "</svg>"
		var img := Image.new()
		if img.load_svg_from_string(svg, texel) != OK:
			_err(id, "%s: SVG render failed" % p.id)
			continue
		var r := img.get_used_rect()
		if r.size.x <= 0:
			_warn(id, "%s: renders empty" % p.id)
			p.rect = Rect2i()
			continue
		if r.position.x <= 0 or r.position.y <= 0 or r.end.x >= img.get_width() or r.end.y >= img.get_height():
			_warn(id, "%s: touches the canvas edge (art outside the canvas is cut off)" % p.id)
		r = r.grow(PAD).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		var crop := img.get_region(r)
		p.rect = r
		px_total += r.size.x * r.size.y
		if not check_only:
			crop.save_png(ProjectSettings.globalize_path(out_dir + p.id + ".png"))
			_write_import(out_dir + p.id + ".png")
		var sl: Dictionary = slots[p.slot]
		if sl.default == p.variant:
			if not bone_imgs.has(p.bone):
				bone_imgs[p.bone] = []
			bone_imgs[p.bone].append({"img": crop, "rect": r})

	# ---- bones json
	var bones_json: Array = []
	for b in order:
		var bd: Dictionary = bone_defs[b]
		var a: Dictionary = bd.attrs
		var piv: Vector2 = bd.pivot
		var ppiv: Vector2 = bone_defs[bd.parent].pivot if b != "root" else origin
		var bj := {"name": b, "parent": bd.parent if b != "root" else "",
			"x": _r(piv.x - origin.x), "y": _r(piv.y - origin.y),
			"lx": _r(piv.x - ppiv.x), "ly": _r(piv.y - ppiv.y)}
		# rest axis + length (for springs/bend): from art unless overridden
		var axis := Vector2(0, 1)
		var length := 0.0
		if bone_imgs.has(b):
			var est := _axis_estimate(bone_imgs[b], piv * texel)
			axis = est[0]
			length = est[1] / texel
		if a.has("data-axis"):
			axis = _vec(str(a["data-axis"])).normalized()
		if a.has("data-length"):
			length = float(str(a["data-length"]))
		bj["axis"] = [_r(axis.x, 1000.0), _r(axis.y, 1000.0)]
		bj["length"] = _r(length)
		var spring := _spring_for(id, b, str(a.get("data-spring", "")))
		if not spring.is_empty():
			if a.has("data-bend"):
				spring["b"] = float(str(a["data-bend"]))
			bj["spring"] = spring
			if length < 8.0:
				_warn(id, "bone '%s' has a spring but no measurable length; set data-length" % b)
		elif a.has("data-bend"):
			bj["bend"] = float(str(a["data-bend"]))
		var look := _look_for(b)
		if a.has("data-look"):
			var lv := _vec(str(a["data-look"]))
			look = [lv.x, lv.y]
		if look[0] != 0.0 or look[1] != 0.0:
			bj["look"] = look
		if a.has("data-tip"):
			var tip := _vec(str(a["data-tip"]))
			bj["tip"] = [_r(tip.x - piv.x), _r(tip.y - piv.y)]
		bones_json.append(bj)

	# ---- slots json
	var slots_json: Array = []
	for sn in slot_names:
		var s: Dictionary = slots[sn]
		var bpiv: Vector2 = bone_defs[s.bone].pivot
		var atts := {}
		for v in s.variants:
			var p: Dictionary = s.variants[v]
			var r: Rect2i = p.get("rect", Rect2i())
			if r.size.x <= 0:
				continue
			atts[v] = {"texture": "parts/%s.png" % p.id,
				"x": _r(r.position.x / texel - bpiv.x), "y": _r(r.position.y / texel - bpiv.y),
				"w": _r(r.size.x / texel), "h": _r(r.size.y / texel)}
		slots_json.append({"name": sn, "bone": s.bone, "z": s.z, "default": s.default, "attachments": atts})

	# ---- still + portrait (default attachments composed in z order)
	var comp := header + defs
	for sn in slot_names:
		var s: Dictionary = slots[sn]
		if s.variants.has(s.default):
			comp += _ser(s.variants[s.default].el)
	comp += "</svg>"
	var meta := {}
	for k in ra:
		var ks := str(k)
		if ks.begins_with("data-") and not (ks in ["data-origin", "data-texel-scale", "data-look-px", "data-portrait", "data-tint-variants"]):
			meta[ks.trim_prefix("data-").replace("-", "_")] = str(ra[k])
	var pr := str(ra.get("data-portrait", ""))
	var pc := Vector3(512, 420, 440)
	if pr != "":
		var pp := pr.split(",")
		pc = Vector3(pp[0].to_float(), pp[1].to_float(), pp[2].to_float())
	elif bone_defs.has("head"):
		var hp: Vector2 = bone_defs["head"].pivot
		pc = Vector3(hp.x, hp.y + 20, 520)
	var prect := Rect2(pc.x - pc.z * 0.5, pc.y - pc.z * 0.5, pc.z, pc.z)
	var json := {
		"format": "halorig", "version": FORMAT_VERSION, "id": id,
		"canvas": [cw, ch], "origin": [origin.x, origin.y], "texel_scale": texel,
		"look_px": [look_px.x, look_px.y],
		"still": "%s_still.png" % id, "portrait": "%s_portrait.png" % id,
		"portrait_rect": [prect.position.x, prect.position.y, prect.size.x, prect.size.y],
		"meta": meta, "bones": bones_json, "slots": slots_json,
	}
	if check_only:
		print("art_build: [%s] check ok: %d bones, %d slots" % [id, bones_json.size(), slots_json.size()])
		return
	var still := Image.new()
	if still.load_svg_from_string(comp, texel) == OK:
		still.save_png(ProjectSettings.globalize_path(dir + id + "_still.png"))
		_write_import(dir + id + "_still.png")
		var bb := still.get_used_rect()
		json["bounds"] = [_r(bb.position.x / texel - origin.x), _r(bb.position.y / texel - origin.y), _r(bb.size.x / texel), _r(bb.size.y / texel)]
	var psc := PORTRAIT_PX / pc.z
	var big := Image.new()
	if big.load_svg_from_string(comp, psc) == OK:
		var cr := Rect2i(int(prect.position.x * psc), int(prect.position.y * psc), PORTRAIT_PX, PORTRAIT_PX)
		var por := Image.create(PORTRAIT_PX, PORTRAIT_PX, false, Image.FORMAT_RGBA8)
		por.blit_rect(big, cr, Vector2i.ZERO)
		por.save_png(ProjectSettings.globalize_path(dir + id + "_portrait.png"))
		_write_import(dir + id + "_portrait.png")
		_tint_variants(id, dir, str(ra.get("data-tint-variants", "")), still, por)
	var f := FileAccess.open(dir + id + ".rig.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(json, "\t", false))
	f.close()
	print("art_build: [%s] %d bones, %d slots, %d part PNGs, %.1f Mpx of part texture" % [id, bones_json.size(), slots_json.size(), parts.size(), px_total / 1000000.0])


## data-tint-variants="celestial=f2c14e,infernal=d9412b": writes <id>_still_<name>.png and
## <id>_portrait_<name>.png through the same luminance gradient map the rig shader uses
## (dark #0d0a1c, mid = colour darkened 40%, light = colour lightened 35%).
func _tint_variants(id: String, dir: String, spec: String, still: Image, por: Image) -> void:
	if spec == "":
		return
	for item in spec.split(",", false):
		var kv := item.split("=")
		if kv.size() != 2:
			_warn(id, "bad data-tint-variants entry '%s'" % item)
			continue
		var c := Color(kv[1].strip_edges())
		var dark := Color("0d0a1c")
		var mid := c.darkened(0.4)
		var light := c.lightened(0.35)
		for pair in [["still", still], ["portrait", por]]:
			var img: Image = (pair[1] as Image).duplicate()
			for y in img.get_height():
				for x in img.get_width():
					var px := img.get_pixel(x, y)
					if px.a <= 0.0:
						continue
					var l := px.r * 0.299 + px.g * 0.587 + px.b * 0.114
					var m := dark.lerp(mid, l * 2.0) if l < 0.5 else mid.lerp(light, l * 2.0 - 1.0)
					img.set_pixel(x, y, Color(m, px.a))
			var path := "%s%s_%s_%s.png" % [dir, id, pair[0], kv[0].strip_edges()]
			img.save_png(ProjectSettings.globalize_path(path))
			_write_import(path)


func _has_std_prefix(b: String) -> bool:
	for p in STANDARD_PREFIX:
		if b.begins_with(p):
			return true
	return false


func _topo(id: String, b: String, defs: Dictionary, state: Dictionary, order: Array[String]) -> void:
	if state.get(b, 0) == 2:
		return
	if state.get(b, 0) == 1:
		_err(id, "bone cycle at '%s'" % b)
		return
	state[b] = 1
	var par: String = defs[b].parent
	if b != "root" and defs.has(par):
		_topo(id, par, defs, state, order)
	state[b] = 2
	order.append(b)


func _r(v: float, m := 10.0) -> float:
	return roundf(v * m) / m


## Alpha-weighted direction from the pivot to the art, and its reach along that direction.
func _axis_estimate(items: Array, pivot_px: Vector2) -> Array:
	var sum := Vector2.ZERO
	var wsum := 0.0
	var pts: Array[Vector2] = []
	for it in items:
		var img: Image = it.img
		var r: Rect2i = it.rect
		var step := maxi(2, int(maxf(img.get_width(), img.get_height()) / 64.0))
		for y in range(0, img.get_height(), step):
			for x in range(0, img.get_width(), step):
				var al := img.get_pixel(x, y).a
				if al > 0.5:
					var p := Vector2(r.position.x + x, r.position.y + y) - pivot_px
					sum += p * al
					wsum += al
					pts.append(p)
	if wsum <= 0.0:
		return [Vector2(0, 1), 0.0]
	var dir := (sum / wsum)
	if dir.length() < 1.0:
		dir = Vector2(0, 1)
	dir = dir.normalized()
	var reach := 0.0
	for p in pts:
		reach = maxf(reach, p.dot(dir))
	return [dir, reach]


func _spring_for(id: String, bone: String, spec: String) -> Dictionary:
	var preset := ""
	var over := {}
	if spec != "":
		var bits := spec.split(";", false)
		preset = bits[0].strip_edges()
		for i in range(1, bits.size()):
			var kv := bits[i].split("=")
			if kv.size() == 2:
				over[kv[0].strip_edges()] = kv[1].to_float()
		if preset == "none":
			return {}
	else:
		preset = _default_preset(bone)
		if preset == "":
			return {}
	if not SPRING_PRESETS.has(preset):
		_err(id, "bone '%s': unknown spring preset '%s'" % [bone, preset])
		return {}
	var s: Dictionary = SPRING_PRESETS[preset].duplicate()
	for k in over:
		if not s.has(k):
			_warn(id, "bone '%s': unknown spring key '%s'" % [bone, k])
		s[k] = over[k]
	s["preset"] = preset
	return s


func _default_preset(b: String) -> String:
	if b == "hair_back":
		return "hair_mass"
	if b.begins_with("hair_front_"):
		return "bangs"
	if b == "ahoge" or b.begins_with("hair_side_"):
		return "hair"
	if b.begins_with("hair_back_") or b.begins_with("hair_tail_") or b.begins_with("ponytail_"):
		return "hair_long"
	if b.begins_with("skirt_") or b.begins_with("coat_"):
		return "cloth"
	if b.begins_with("cape"):
		return "cape"
	if b.begins_with("ribbon_"):
		return "ribbon"
	if b.begins_with("sleeve_"):
		return "sleeve"
	if b.begins_with("wing_"):
		return "wing"
	if b.begins_with("tail"):
		return "tail"
	return ""


func _look_for(b: String) -> Array:
	for e in LOOK_DEFAULTS:
		if b.begins_with(e[0]):
			return (e[1] as Array).duplicate()
	return [0.0, 0.0]


## Texture import settings: lossless, mipmaps on (rigs are drawn scaled down), alpha border fix.
func _write_import(res_path: String) -> void:
	var ip := ProjectSettings.globalize_path(res_path + ".import")
	if FileAccess.file_exists(ip):
		var t := FileAccess.get_file_as_string(ip)
		if t.contains("mipmaps/generate=true"):
			return
		t = t.replace("mipmaps/generate=false", "mipmaps/generate=true")
		var fw := FileAccess.open(ip, FileAccess.WRITE)
		fw.store_string(t)
		fw.close()
		return
	var s := "[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\n\n[deps]\n\nsource_file=\"%s\"\n\n[params]\n\ncompress/mode=0\ncompress/high_quality=false\ncompress/lossy_quality=0.7\ncompress/uastc_level=0\ncompress/rdo_quality_loss=0.0\ncompress/hdr_compression=1\ncompress/normal_map=0\ncompress/channel_pack=0\nmipmaps/generate=true\nmipmaps/limit=-1\nroughness/mode=0\nroughness/src_normal=\"\"\nprocess/channel_remap/red=0\nprocess/channel_remap/green=1\nprocess/channel_remap/blue=2\nprocess/channel_remap/alpha=3\nprocess/fix_alpha_border=true\nprocess/premult_alpha=false\nprocess/normal_map_invert_y=false\nprocess/hdr_as_srgb=false\nprocess/hdr_clamp_exposure=false\nprocess/size_limit=0\ndetect_3d/compress_to=0\n" % res_path
	var f := FileAccess.open(ip, FileAccess.WRITE)
	f.store_string(s)
	f.close()
