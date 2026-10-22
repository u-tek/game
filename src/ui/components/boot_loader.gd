extends RefCounted
## The real work behind the boot screen's progress rule (main.gd _boot): what the Lobby shows first,
## made ready before it is built so it appears without a hitch.
## 1. On worker threads (ResourceLoader.load_threaded_request; the print run keeps moving; in place
##    when headless): the Lobby
##    hero's rig files (warp image, still, portrait, overlays) in the look she wears, the stills of
##    the team (the chrome's avatar and the Team screen), the Lobby's paper, growth, LED, acrylic and
##    disc renders.
## 2. On the main thread, one step a frame (steps()): her rig (mesh), the alpha bounds of her art
##    (framing), her blurred echo, the team's portrait crops.
## The loaded resources stay referenced while this object lives, so nothing is dropped from the cache
## before the Lobby takes them.
##   var bl := BootLoader.new(); bl.start(hero_id, skin)
##   while not bl.loaded(): boot.set_progress(bl.progress()); await frame
##   for s in bl.steps(): s.call(); await frame

const HomeScreen := preload("res://src/ui/screens/home_screen.gd")
const DISC := "res://assets/art/ui/objects/disc.png"
## Physical pieces the Lobby puts up (PhysicalKit names; the growth is added by faction).
const LOBBY_PIECES: Array[String] = ["paper_felt", "paper_felt_n", "paper_parch", "paper_parch_n",
	"led_red_on", "led_red_off", "led_green_on", "led_green_off", "acrylic_tab_t", "acrylic_tab_l"]

var hero_id := ""
var skin := ""
var _paths: Array[String] = []
var _done: Dictionary = {}
var _held: Array[Resource] = []


## Starts the threaded loads for the Lobby with `id` (in look `look`) as its hero.
func start(id: String, look: String) -> void:
	hero_id = id
	skin = look
	var want: Array[String] = []
	if id != "":
		want.append_array(rig_files(id, look))
		var fac := str(Game.hero_def(id).get("faction", "celestial"))
		for shape: String in ["tl", "bl"]:
			want.append(PhysicalKit.DIR + PhysicalKit.growth_name(fac, shape) + ".png")
	for f: Variant in Game.formation():
		var fid := str(f)
		if fid != "" and fid != id:
			var files := rig_files(fid, Kit.hero_look(fid), true)
			want.append_array(files)
	for n in LOBBY_PIECES:
		want.append(PhysicalKit.DIR + n + ".png")
	want.append(DISC)
	# Headless runs (tests, tools/check) load in place: the dummy renderer's texture store is not
	# safe to fill from worker threads (a texture comes out null now and then).
	var threaded := DisplayServer.get_name() != "headless"
	var seen: Dictionary = {}
	for p in want:
		if p == "" or seen.has(p) or not ResourceLoader.exists(p):
			continue
		seen[p] = true
		if not threaded:
			var r := load(p)
			if r:
				_held.append(r)
		elif ResourceLoader.load_threaded_request(p, "", false) == OK:
			_paths.append(p)


## Share of the threaded loads finished, 0..1 (collects each one as it lands).
func progress() -> float:
	if _paths.is_empty():
		return 1.0
	var sum := 0.0
	var pr := []
	for p in _paths:
		if _done.has(p):
			sum += 1.0
			continue
		match ResourceLoader.load_threaded_get_status(p, pr):
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				sum += float(pr[0]) if pr.size() > 0 else 0.0
			ResourceLoader.THREAD_LOAD_LOADED:
				var r := ResourceLoader.load_threaded_get(p)
				if r:
					_held.append(r)
				_done[p] = true
				sum += 1.0
			_:
				# Failed or unknown: the screen's own load() reports it.
				_done[p] = true
				sum += 1.0
	return sum / _paths.size()


func loaded() -> bool:
	return _done.size() >= _paths.size()


## The main-thread warm-ups, each worth a frame of its own.
func steps() -> Array[Callable]:
	var out: Array[Callable] = []
	if hero_id != "":
		var id := hero_id
		var look := skin
		# Her rig (meshes and overlays) and the still.
		out.append(func() -> void: HeroArt.texture(id, look))
		# Her outline (fit_sprite frames her by it) and her echo on the paper.
		out.append(func() -> void:
			var art := HeroArt.art_key(id, look).get_slice("@", 1)
			var rd := RigData.load_rig(id, art) if HeroArt.has_art(id) else null
			if rd and rd.image:
				HeroArt.used_rect(rd.image)
			HeroArt.used_rect(HeroArt.texture(id, look)))
		out.append(func() -> void: HomeScreen.echo_texture(HeroArt.art_key(id, look), HeroArt.texture(id, look)))
	for f: Variant in Game.formation():
		var fid := str(f)
		if fid != "":
			out.append(func() -> void: Kit.art_crop(fid, 1.0, 1.7, Kit.hero_look(fid)))
	return out


## The files a hero's rig loads in a look (RigData._load): the warp image, the still, the portrait and
## the overlay textures; still_only: just the still and the portrait.
static func rig_files(id: String, look: String, still_only: bool = false) -> Array[String]:
	var out: Array[String] = []
	if not HeroArt.has_art(id):
		return out
	var art := HeroArt.art_key(id, look).get_slice("@", 1)
	var base := RigData.file_base(id, art)
	var path := base + ".warp.json"
	if not FileAccess.file_exists(path):
		path = base + ".rig.json"
		if not FileAccess.file_exists(path):
			return out
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary):
		return out
	var dir := RigData.art_dir(id, art)
	for k: String in ["still", "portrait"]:
		if str(d.get(k, "")) != "":
			out.append(dir + str(d[k]))
	if still_only:
		return out
	if str(d.get("format", "")) == "halowarp":
		out.append(dir + str(d.get("image", id + ".png")))
	for sj: Variant in d.get("slots", []):
		if not (sj is Dictionary):
			continue
		var atts: Variant = (sj as Dictionary).get("attachments", {})
		if not (atts is Dictionary):
			continue
		for v: Variant in atts:
			var a: Variant = atts[v]
			if a is Dictionary and (a as Dictionary).has("texture"):
				out.append(dir + str(a["texture"]))
	return out
