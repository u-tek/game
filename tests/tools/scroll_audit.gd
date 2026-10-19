extends SceneTree
## Headless audit: opens every scrolling screen and lists the controls inside a ScrollContainer
## that would swallow a finger drag on a phone (mouse_filter STOP on something that isn't a control
## you press, and bigger than a small widget). On a touchscreen such a control stops the drag before
## it reaches the ScrollContainer, so the page can't be scrolled there. Exit 1 if any are found.
##   tools/gd --headless --path . -s tests/tools/scroll_audit.gd -- --rich

const SCREENS := [["settings", {}], ["heroes", {}], ["hero_detail", {"hero_id": "seraphiel"}], ["formation", {}], ["gear", {}],
	["shop", {}], ["shop", {"tab": 1}], ["shop", {"tab": 2}], ["quests", {}], ["summon", {}], ["campaign", {"intro": false}],
	["tower", {}], ["home", {"sheet": true}], ["profile", {}], ["profile", {"sheet": "avatar"}], ["prints", {}],
	["prints", {"filter": "holo"}], ["rival", {}]]
var _bad: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://src/main.tscn").instantiate()
	root.add_child(main)
	for i in 8:
		await process_frame
	var ui: Node = root.get_node("UI")
	for e: Array in SCREENS:
		if not ui.get("SCREENS").has(e[0]):
			continue
		ui.call("go", e[0], e[1])
		for i in 12:
			await process_frame
		for sc in root.find_children("*", "ScrollContainer", true, false):
			_walk(sc as ScrollContainer, sc as Control, str(e[0]))
	for b in _bad:
		printerr("E2E FAIL scroll blocker ", b)
	print("E2E scroll audit: %d failures" % _bad.size())
	quit(1 if _bad.size() > 0 else 0)


func _walk(sc: ScrollContainer, n: Node, screen: String) -> void:
	for c in n.get_children():
		if c is ScrollBar:
			continue
		if c is Control:
			var ctl := c as Control
			var press := ctl is BaseButton or ctl is LineEdit or ctl is TextEdit or ctl is Range or ctl is ScrollContainer or ctl is ItemList
			if ctl.mouse_filter == Control.MOUSE_FILTER_STOP and not press and ctl.is_visible_in_tree() and ctl.size.x * ctl.size.y > 120.0 * 120.0:
				var txt := ""
				for l in ctl.find_children("*", "Label", true, false):
					if (l as Label).text.strip_edges() != "":
						txt = (l as Label).text.strip_edges().left(30)
						break
				var owner_screen := str(sc.owner.name) if sc.owner else str(sc.get_parent().name)
				var key := "%s: %s/%s (%s %dx%d \"%s\")" % [screen, owner_screen, str(sc.get_path_to(ctl)), ctl.get_class(), int(ctl.size.x), int(ctl.size.y), txt]
				if not _bad.has(key):
					_bad.append(key)
		if c is ScrollContainer:
			continue
		_walk(sc, c, screen)
