extends RefCounted
## Device tiers for features that need a strong GPU (the owner, 2026-10-22: "for 15 pro + models, do
## something to take advantage of the processing power available on device").
##   pro()         iPhone 15 Pro and newer (A17 Pro and up: model identifiers iPhone16,x and higher;
##                 the iPhone 15 and 15 Plus are iPhone15,4/15,5) and iPads with M2 or newer
##                 (iPad14,x and up). Desktop and older phones: false. --pro / --no-pro override it
##                 (screenshots, testing).
##   live_light()  pro() and the Settings switch (setting "live_light", on unless turned off).
##   light(sprite) turns Live Light on for a big hero view (HeroSprite.live) when it applies.

static var _pro := -1


static func pro() -> bool:
	if _pro < 0:
		_pro = 1 if _detect() else 0
	return _pro == 1


static func _detect() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("--no-pro"):
		return false
	if args.has("--pro"):
		return true
	if OS.get_name() != "iOS":
		return false
	return is_pro_model(OS.get_model_name())


## True for an Apple model identifier of a Pro-tier device ("iPhone16,1" yes, "iPhone15,4" no).
static func is_pro_model(m: String) -> bool:
	for fam: Array in [["iPhone", 16], ["iPad", 14]]:
		var pre := str(fam[0])
		if m.begins_with(pre):
			var major := m.trim_prefix(pre).get_slice(",", 0)
			return major.is_valid_int() and int(major) >= int(fam[1])
	return false


static func live_light() -> bool:
	if not pro():
		return false
	var g := Kit.autoload("Game")
	return g == null or g.call("setting", "live_light") != false


## Live Light on a big hero view (a HeroSprite), when this device runs it.
static func light(sprite: Node) -> void:
	if sprite and live_light() and "live" in sprite:
		sprite.set("live", true)
