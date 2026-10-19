extends Control
## IsoView (style v4 "Signal", poster look): a small 3D scene printed onto a 2D poster. It owns a
## transparent SubViewport with its own world and an orthographic camera turned by yaw / pitch, and
## shows it in a TextureRect that fills this control (premultiplied, so translucent vellum and ink
## composite over the paper exactly). The survey shaders are unshaded and do their own "print"
## shading (halftone dots, hatching, ink lines), so no lights are needed. Screens add meshes under
## `world` and draw type, leader lines and touch targets in 2D on top, placed with project()
## (world point -> local px) and re-placed whenever `turned` fires.
##
##   var v := IsoView.new(); v.yaw = -28; v.pitch = -32; v.ortho_width = 13.0; add_child(v)
##   v.world.add_child(mesh_instance)
##   var p := v.project(Vector3(0, 1, 0))      # local px in this control
##
## Motion: a slow idle sway (off with Reduce motion) and drag-to-turn (handle_input, called by the
## screen, which keeps the tap logic): the yaw follows the finger within yaw_range and eases back.

signal turned

var yaw := -30.0
var pitch := -32.0
## Visible world width (orthographic, the width is kept).
var ortho_width := 12.0
var target := Vector3.ZERO
## Shifts the picture on screen (world units, camera space): +x right, +y up.
var shift := Vector2.ZERO
## Idle sway amplitude (degrees of yaw) and period (s).
var sway := 3.0
var sway_period := 16.0
## Continuous turntable (degrees per second, 0 = none), added to yaw.
var spin := 0.0
var drag_turn := true
## Local rect where a drag turns the view (empty = the whole control).
var drag_rect := Rect2()
var yaw_range := 26.0
## Cap on the render scale (viewport px per control px).
var max_scale := 1.6

var viewport: SubViewport
var world: Node3D
var camera: Camera3D

var _tex: TextureRect
var _t := 0.0
var _drag := 0.0
var _drag_v := 0.0
var _holding := false
var _press_at := Vector2.ZERO
var _moved := false
var _last_cam := Transform3D()


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.use_hdr_2d = true
	viewport.positional_shadow_atlas_size = 0
	# Rendered on demand: a frame whenever the camera moves or the scene asks (request_render).
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.size = Vector2i(16, 16)
	add_child(viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	viewport.add_child(we)
	world = Node3D.new()
	world.name = "World"
	viewport.add_child(world)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.near = 0.1
	camera.far = 200.0
	camera.current = true
	viewport.add_child(camera)
	_tex = TextureRect.new()
	_tex.mouse_filter = MOUSE_FILTER_IGNORE
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_tex.texture = viewport.get_texture()
	var pm := CanvasItemMaterial.new()
	pm.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_tex.material = pm
	_tex.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_tex)
	resized.connect(_fit)
	_fit()
	_place_camera()


func _fit() -> void:
	if viewport == null or size.x < 2.0 or size.y < 2.0:
		return
	var k := 1.0
	var vp := get_viewport()
	if vp:
		var win := Vector2(DisplayServer.window_get_size())
		var vis := vp.get_visible_rect().size
		if vis.x > 0.0 and win.x > 0.0:
			k = clampf(win.x / vis.x, 1.0, max_scale)
	viewport.size = Vector2i(maxi(int(size.x * k), 16), maxi(int(size.y * k), 16))
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_last_cam = Transform3D()
	_place_camera()


## Renders the scene again next frame (call after moving or changing anything in `world`).
func request_render() -> void:
	if viewport:
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Viewport px per control px (the halftone cell is set in viewport px).
func render_scale() -> float:
	if viewport == null or size.x < 1.0:
		return 1.0
	return float(viewport.size.x) / size.x


func _process(delta: float) -> void:
	_t += delta
	if not _holding:
		# Ease the drag offset back to rest (keeping a little of the flick).
		_drag += _drag_v * delta
		_drag_v = lerpf(_drag_v, 0.0, clampf(delta * 5.0, 0.0, 1.0))
		_drag = lerpf(_drag, 0.0, clampf(delta * 1.2, 0.0, 1.0))
		_drag = clampf(_drag, -yaw_range, yaw_range)
	_place_camera()


## Current yaw including sway, spin and the drag offset.
func view_yaw() -> float:
	var y := yaw + _drag
	if Kit.motion_ok():
		y += sin(_t * TAU / maxf(sway_period, 0.1)) * sway + _t * spin
	return y


func _place_camera() -> void:
	if camera == null:
		return
	var b := Basis(Vector3.UP, deg_to_rad(view_yaw())) * Basis(Vector3.RIGHT, deg_to_rad(pitch))
	var xf := Transform3D(b, target + b * Vector3(0.0, 0.0, 60.0) - b.x * shift.x - b.y * shift.y)
	camera.size = ortho_width
	if not xf.is_equal_approx(_last_cam):
		camera.transform = xf
		_last_cam = xf
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		turned.emit()


## World point -> local px in this control.
func project(p: Vector3) -> Vector2:
	if camera == null or viewport == null:
		return Vector2.ZERO
	return camera.unproject_position(p) * size / Vector2(viewport.size)


## Pixels per world unit at the current zoom.
func px_per_unit() -> float:
	return size.x / maxf(ortho_width, 0.01)


## Drag-to-turn. The screen forwards its pointer input here and keeps the tap logic: returns true
## when the gesture was a drag (so the screen ignores its release).
func handle_input(event: InputEvent) -> bool:
	if not drag_turn:
		return false
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if drag_rect.size != Vector2.ZERO and not drag_rect.has_point(mb.position):
				return false
			_holding = true
			_moved = false
			_press_at = mb.position
			_drag_v = 0.0
			return false
		var was := _moved
		_holding = false
		_moved = false
		return was
	if event is InputEventMouseMotion and _holding:
		var mm := event as InputEventMouseMotion
		if not _moved and mm.position.distance_to(_press_at) > 14.0:
			_moved = true
		if _moved:
			_drag = clampf(_drag + mm.relative.x * 0.2, -yaw_range, yaw_range)
			_drag_v = clampf(mm.velocity.x * 0.2 * 0.2, -60.0, 60.0)
			return true
	return _moved
