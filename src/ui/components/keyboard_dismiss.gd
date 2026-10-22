extends Node
## Lets the player put the keyboard away (owner, 2026-10-23: "make sure the user can exit the
## keyboard state after typing in their username"): Return ends the editing, and a tap anywhere
## outside the field does too (the tap still reaches whatever it lands on).
##   KeyboardDismiss.attach(line_edit)

var field: LineEdit


static func attach(f: LineEdit) -> void:
	if f == null:
		return
	var n: Node = load("res://src/ui/components/keyboard_dismiss.gd").new()
	n.name = "KeyboardDismiss"
	n.set("field", f)
	f.add_child(n)
	f.text_submitted.connect(func(_t: String) -> void: n.call("close"))


func close() -> void:
	if field and is_instance_valid(field) and field.has_focus():
		field.release_focus()
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		DisplayServer.virtual_keyboard_hide()


func _input(event: InputEvent) -> void:
	if field == null or not is_instance_valid(field) or not field.has_focus():
		return
	var pos := Vector2.INF
	var mb := event as InputEventMouseButton
	if mb and mb.pressed:
		pos = mb.position
	var st := event as InputEventScreenTouch
	if st and st.pressed:
		pos = st.position
	if pos != Vector2.INF and not field.get_global_rect().has_point(pos):
		close()
