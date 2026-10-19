extends Control
## The big rarity word of a summon reveal ("LEGENDARY", "EPIC", "RARE"): widely tracked
## condensed caps filled with a vertical gradient in the rarity colors, a dark outline, an
## additive glow band behind and thin light lines either side. sheen(0..1) sweeps a glint
## across the letters (the reveal drives it). Left-aligned: the control's minimum size is
## the text's size.

const Fx := preload("res://src/ui/summon/summon_fx.gd")

const SHADER_CODE := """
shader_type canvas_item;
uniform vec4 top_color : source_color = vec4(1.0, 0.95, 0.7, 1.0);
uniform vec4 bottom_color : source_color = vec4(1.0, 0.6, 0.1, 1.0);
uniform float top_y = 0.0;
uniform float bottom_y = 100.0;
uniform float sheen_x = -1000.0;
uniform float sheen_w = 50.0;
varying vec2 local_pos;
void vertex() {
	local_pos = VERTEX;
}
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	// Recolor only the white fill; the dark outline and shadow keep their color.
	float fill = step(0.7, min(COLOR.r, min(COLOR.g, COLOR.b)));
	float t = clamp((local_pos.y - top_y) / max(bottom_y - top_y, 1.0), 0.0, 1.0);
	vec3 g = mix(top_color.rgb, bottom_color.rgb, t);
	float s = 1.0 - smoothstep(0.0, sheen_w, abs(local_pos.x + (local_pos.y - top_y) * 0.4 - sheen_x));
	g = mix(g, vec3(1.0), s * 0.85);
	c.rgb = mix(c.rgb, g, fill);
	COLOR = c;
}
"""

static var _shader: Shader

var rarity := "rare"
var font_size := 96
var color := Color.WHITE
## 0..1: the glint position across the word (< 0 or > 1 = off).
var sheen := -1.0:
	set(v):
		sheen = v
		_apply_sheen()
## 0..1 glow band strength.
var glow := 1.0

var _label: Label
var _mat: ShaderMaterial
var _text_size := Vector2.ZERO


func setup(r: String, size_px: int) -> void:
	rarity = r
	font_size = size_px
	color = Kit.rarity_color(r)
	mouse_filter = MOUSE_FILTER_IGNORE
	var text := str(Kit.RARITY_NAMES.get(r, r.capitalize())).to_upper()
	var fv := FontVariation.new()
	fv.base_font = Kit.font("title")
	fv.spacing_glyph = int(size_px * 0.08)
	_label = Label.new()
	_label.text = text
	_label.mouse_filter = MOUSE_FILTER_IGNORE
	_label.add_theme_font_override("font", fv)
	_label.add_theme_font_size_override("font_size", size_px)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color(0.03, 0.02, 0.08, 0.95))
	_label.add_theme_constant_override("outline_size", maxi(6, int(size_px * 0.11)))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	_label.add_theme_constant_override("shadow_offset_x", 0)
	_label.add_theme_constant_override("shadow_offset_y", int(size_px * 0.06))
	_label.add_theme_constant_override("shadow_outline_size", maxi(6, int(size_px * 0.11)))
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	var top := color.lerp(Color.WHITE, 0.72)
	var bottom := color
	match r:
		"legendary":
			top = Color("fff6c8")
			bottom = Color("ff9b1e")
		"epic":
			top = Color("f3dcff")
			bottom = Color("a95cf2")
		_:
			top = Color("e2f6ff")
			bottom = Color("3b9cf2")
	_mat.set_shader_parameter("top_color", top)
	_mat.set_shader_parameter("bottom_color", bottom)
	_label.material = _mat
	add_child(_label)
	_text_size = _label.get_combined_minimum_size()
	custom_minimum_size = _text_size
	size = _text_size
	_label.size = _text_size
	# The glyphs' cap height sits roughly in the middle 70% of the line box.
	_mat.set_shader_parameter("top_y", _text_size.y * 0.2)
	_mat.set_shader_parameter("bottom_y", _text_size.y * 0.8)
	_mat.set_shader_parameter("sheen_w", size_px * 0.5)
	_apply_sheen()


func _apply_sheen() -> void:
	if _mat:
		var x := -1000.0 if sheen < 0.0 or sheen > 1.0 else lerpf(-font_size * 0.6, _text_size.x + font_size * 0.6, sheen)
		_mat.set_shader_parameter("sheen_x", x)


func _ready() -> void:
	material = Fx.additive()
	# The label keeps normal blending (only this control's own drawing is additive).
	if _label:
		_label.use_parent_material = false


func _draw() -> void:
	if glow <= 0.01:
		return
	var soft := Fx.soft_dot()
	var c := Vector2(_text_size.x * 0.45, _text_size.y * 0.52)
	var w := _text_size.x * 1.5
	var h := _text_size.y * 1.1
	draw_texture_rect(soft, Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h)), false, Color(color, 0.55 * glow))
	# Light lines trailing off to the right of the word.
	var y := _text_size.y * 0.5
	var x0 := _text_size.x + 14.0
	draw_line(Vector2(x0, y - 6.0), Vector2(x0 + 180.0, y - 6.0), Color(color.lerp(Color.WHITE, 0.4), 0.6 * glow), 2.0, true)
	draw_line(Vector2(x0 + 20.0, y + 4.0), Vector2(x0 + 110.0, y + 4.0), Color(color, 0.45 * glow), 2.0, true)
