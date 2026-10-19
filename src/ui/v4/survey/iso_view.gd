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
## Motion (all off with Reduce motion): while `animate` is on the scene is alive. The view renders
## continuously but capped at fps_cap (every frame while a finger turns it), and each render tick
## emits `frame(dt)` so the screen moves its 3D content and re-places its 2D overlay in step with
## the picture (shaders animate on TIME). A slow auto-orbit (sway in yaw, pitch_sway in pitch)
## runs while idle and pauses under a finger; the phone's tilt adds a little parallax (tilt_yaw /
## tilt_pitch degrees per unit of the high-passed gravity, as main.gd computes "ui_tilt"). With
## Reduce motion it renders on demand only (a drag, request_render) and emits `turned`.
## Drag-to-turn: handle_input, called by the screen, which keeps the tap logic; the yaw follows the
## finger within yaw_range and eases back.

## The camera moved (on-demand mode; while animating, `frame` covers it).
signal turned
## A render tick while animating (dt: seconds since the last one): move 3D content, re-place 2D.
signal frame(dt: float)

var yaw := -30.0
var pitch := -32.0
## Visible world width (orthographic, the width is kept).
var ortho_width := 12.0
var target := Vector3.ZERO
## Shifts the picture on screen (world units, camera space): +x right, +y up.
var shift := Vector2.ZERO
## Idle orbit: yaw amplitude (degrees) and period (s), and the same for pitch.
var sway := 3.0
var sway_period := 16.0
var pitch_sway := 0.0
var pitch_period := 30.0
## Continuous turntable (degrees per second, 0 = none), added to yaw.
var spin := 0.0
## Tilt parallax: degrees of yaw / pitch per unit of device tilt (0 = none).
var tilt_yaw := 0.0
var tilt_pitch := 0.0
## Render continuously (capped at fps_cap) while motion is allowed.
var animate := true
var fps_cap := 30.0
## Seconds after a finger lifts before the idle orbit eases back in.
var idle_delay := 1.5
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
var _acc := 0.0
var _orbit_t := 0.0
var _idle_w := 1.0
var _idle_wait := 0.0
var _tilt := Vector2.ZERO
var _grav_base := Vector3.ZERO


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	# Linear like the main canvas when that is HDR; plain sRGB where HDR 2D is off (iOS), so the
	# texture composites in the same space as everything else.
	viewport.use_hdr_2d = get_tree().root.use_hdr_2d
	viewport.positional_shadow_atlas_size = 0
	# Rendered per tick: on every render tick while animating (capped, see _process), else on demand
	# (the camera moved, or the scene asked with request_render).
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
	if _place_camera():
		turned.emit()


## Renders the scene again next frame (call after moving or changing anything in `world`).
func request_render() -> void:
	if viewport:
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Viewport px per control px (the halftone cell is set in viewport px).
func render_scale() -> float:
	if viewport == null or size.x < 1.0:
		return 1.0
	return float(viewport.size.x) / size.x


## True while the scene animates (render ticks, orbit, parallax): `animate` and not Reduce motion.
func is_live() -> bool:
	return animate and Kit.motion_ok()


func _process(delta: float) -> void:
	_t += delta
	if not _holding:
		# Ease the drag offset back to rest (keeping a little of the flick).
		_drag += _drag_v * delta
		_drag_v = lerpf(_drag_v, 0.0, clampf(delta * 5.0, 0.0, 1.0))
		_drag = lerpf(_drag, 0.0, clampf(delta * 1.2, 0.0, 1.0))
		_drag = clampf(_drag, -yaw_range, yaw_range)
	var live := is_live()
	if live:
		_update_tilt(delta)
		# The idle orbit pauses under a finger (its phase holds, so nothing jumps) and eases back in
		# a moment after it lifts.
		if _holding:
			_idle_wait = idle_delay
		else:
			_idle_wait = maxf(_idle_wait - delta, 0.0)
		_idle_w = move_toward(_idle_w, 0.0 if (_holding or _idle_wait > 0.0) else 1.0, delta / 1.8)
		_orbit_t += delta * _idle_w
	# Render ticks: capped at fps_cap while idle (a little slack so 60 Hz lands on every 2nd
	# frame), every frame while a finger turns the view.
	_acc += delta
	var step := 1.0 / maxf(fps_cap, 1.0)
	if live and not _holding and _acc < step - 0.004:
		return
	var dt := _acc
	_acc = fmod(_acc, step) if _acc >= step else 0.0
	var moved := _place_camera()
	if live:
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		frame.emit(dt)
	elif moved:
		turned.emit()


## The device tilt, high-passed like main.gd's "ui_tilt" (gravity against its slow average), so
## holding the phone still at any angle is "level" and only moving it tilts the view.
func _update_tilt(delta: float) -> void:
	if tilt_yaw == 0.0 and tilt_pitch == 0.0:
		return
	var g := Input.get_gravity()
	var want := Vector2.ZERO
	if g.length_squared() > 0.01:
		if _grav_base == Vector3.ZERO:
			_grav_base = g
		_grav_base = _grav_base.lerp(g, clampf(delta * 0.6, 0.0, 1.0))
		var d := (g - _grav_base) / 9.8
		want = Vector2(d.x, -d.y) * 2.2
	_tilt = _tilt.lerp(want.limit_length(0.6), clampf(delta * 6.0, 0.0, 1.0))


## Current yaw including the orbit, spin, tilt and the drag offset.
func view_yaw() -> float:
	var y := yaw + _drag
	if Kit.motion_ok():
		y += sin(_orbit_t * TAU / maxf(sway_period, 0.1)) * sway + _t * spin + _tilt.x * tilt_yaw
	return y


## Current pitch including the orbit and tilt.
func view_pitch() -> float:
	var p := pitch
	if Kit.motion_ok():
		p += sin(_orbit_t * TAU / maxf(pitch_period, 0.1)) * pitch_sway + _tilt.y * tilt_pitch
	return p


## Places the camera; true when it moved (a render is queued then).
func _place_camera() -> bool:
	if camera == null:
		return false
	var b := Basis(Vector3.UP, deg_to_rad(view_yaw())) * Basis(Vector3.RIGHT, deg_to_rad(view_pitch()))
	var xf := Transform3D(b, target + b * Vector3(0.0, 0.0, 60.0) - b.x * shift.x - b.y * shift.y)
	camera.size = ortho_width
	if xf.is_equal_approx(_last_cam):
		return false
	camera.transform = xf
	_last_cam = xf
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	return true


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
