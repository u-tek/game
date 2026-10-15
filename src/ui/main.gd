extends Control
## App root (STUB - owned by the UI shell agent). Hosts background, top bar, current
## screen, bottom nav, toasts and modals. Registers itself with the UI autoload.

func _ready() -> void:
	UI.attach(self)
	UI.go("home")
