extends RefCounted
## DeviceTier: which Apple devices run Live Light (iPhone 15 Pro and newer, M2 iPads and newer).

const DeviceTier := preload("res://src/art/device_tier.gd")


func test_pro_models(t: TestCtx) -> void:
	for m: String in ["iPhone16,1", "iPhone16,2", "iPhone17,3", "iPhone18,1", "iPad14,3", "iPad16,6"]:
		t.ok(DeviceTier.is_pro_model(m), "%s runs Live Light" % m)
	for m: String in ["iPhone15,4", "iPhone15,5", "iPhone15,2", "iPhone14,7", "iPad13,1", "iPod9,1", "x86_64", ""]:
		t.ok(not DeviceTier.is_pro_model(m), "%s does not" % m)
