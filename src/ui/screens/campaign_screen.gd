extends Control
## Screen "campaign" (STUB). Replace with the real screen; keep `setup(params)`.

func setup(params: Dictionary) -> void:
	var l := Label.new()
	l.text = "campaign (coming soon)"
	l.position = Vector2(40, 200)
	add_child(l)
