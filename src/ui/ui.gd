extends Node
## Autoload "UI" (STUB - owned by the UI shell agent): navigation + feedback helpers that
## every screen uses. Contract: see docs/dev/architecture.md.

const SCREENS := {
	"home": "res://src/ui/screens/home_screen.gd",
	"campaign": "res://src/ui/screens/campaign_screen.gd",
	"battle": "res://src/ui/screens/battle_screen.gd",
	"heroes": "res://src/ui/screens/heroes_screen.gd",
	"hero_detail": "res://src/ui/screens/hero_detail_screen.gd",
	"formation": "res://src/ui/screens/formation_screen.gd",
	"summon": "res://src/ui/screens/summon_screen.gd",
	"quests": "res://src/ui/screens/quests_screen.gd",
	"shop": "res://src/ui/screens/shop_screen.gd",
	"settings": "res://src/ui/screens/settings_screen.gd",
}

var root: Control
var current_name := ""
var current: Control


func attach(app_root: Control) -> void:
	root = app_root


## Navigate to a screen by name with optional params.
func go(screen: String, params: Dictionary = {}) -> void:
	if current:
		current.queue_free()
	var s: Control = load(SCREENS[screen]).new()
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(s)
	current = s
	current_name = screen
	if s.has_method("setup"):
		s.setup(params)


## Go back to the previous screen (or home).
func back() -> void:
	go("home")


## Short message at the top of the screen.
func toast(text: String) -> void:
	print("[toast] ", text)


## Show a reward popup (Reward dictionary), then call `on_closed` if valid.
func show_reward(title: String, reward: Dictionary, on_closed: Callable = Callable()) -> void:
	print("[reward] ", title, " ", reward)
	if on_closed.is_valid():
		on_closed.call()
