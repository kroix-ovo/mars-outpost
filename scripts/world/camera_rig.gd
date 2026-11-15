class_name WorldCameraRig
extends Node3D
## Planet Coaster style orbit/pan/zoom camera for the top-down outpost view.
##
## The rig node sits at the focus point on the ground; the child Camera3D is placed each frame
## from yaw/pitch/distance. All input is handled in _unhandled_input so Control nodes (Task 03
## HUD) consume their clicks first and never fight the camera.
##
## Controls: WASD / arrow keys or edge scrolling to pan, middle-mouse drag or Q/E to orbit,
## mouse wheel or Z/X to zoom, Home/End to tilt, F to reset. Edge scrolling follows Cities: Skylines 1; HUD panels suppress it.

signal focus_changed(focus_m: Vector3)

@export var edge_pan_enabled: bool = true
@export var edge_margin_px: float = 16.0
@export var pan_speed_m_per_s: float = 18.0
@export var orbit_speed_deg_per_px: float = 0.25
@export var pitch_min_deg: float = 25.0
@export var pitch_max_deg: float = 85.0
@export var distance_min_m: float = 6.0
@export var distance_max_m: float = 90.0
@export var zoom_step: float = 0.12
@export var smoothing: float = 10.0
@export var input_enabled: bool = true

var yaw_deg: float = 35.0
var pitch_deg: float = 55.0
var distance_m: float = 28.0
var bounds_min: Vector2 = Vector2.ZERO
var bounds_max: Vector2 = Vector2(16, 16)

var _target_focus: Vector3 = Vector3.ZERO
var _target_yaw: float = 35.0
var _target_pitch: float = 55.0
var _target_distance: float = 28.0
var _home_focus: Vector3 = Vector3.ZERO
var _orbiting: bool = false
var hud_width: float = 0.0
var _home_distance: float = 24.0

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
    if camera == null:
        camera = Camera3D.new()
        camera.name = "Camera3D"
        add_child(camera)
    camera.current = true
    _target_focus = position
    _home_focus = position
    _target_yaw = yaw_deg
    _target_pitch = pitch_deg
    _target_distance = distance_m
    _apply_camera()


func set_map_bounds(size_cells: Array, airlock_cell: Array) -> void:
    bounds_min = Vector2.ZERO
    bounds_max = Vector2(float(size_cells[0]), float(size_cells[1]))
    _home_focus = Vector3(float(airlock_cell[0]) + 0.5, 0.0, float(airlock_cell[1]) + 0.5)
    var diagonal := bounds_max.length()
    distance_max_m = maxf(distance_max_m, diagonal * 1.2)
    _home_distance = clampf(diagonal * 0.9, distance_min_m, distance_max_m)
    reset_view()


func frame_area(center: Vector3, radius_m: float) -> void:
    ## Makes the given area the home view (Home key) and moves there.
    _home_focus = Vector3(clampf(center.x, bounds_min.x, bounds_max.x), 0.0, clampf(center.z, bounds_min.y, bounds_max.y))
    _home_distance = clampf(radius_m * 2.6 + 6.0, 12.0, 34.0)
    reset_view()
    # Snap rather than glide so a restarted world opens already framed.
    position = _target_focus
    yaw_deg = _target_yaw
    pitch_deg = _target_pitch
    distance_m = _target_distance
    if is_inside_tree() and camera != null:
        _apply_camera()


func reset_view() -> void:
    _target_focus = _home_focus
    _target_yaw = 35.0
    _target_pitch = 50.0
    _target_distance = _home_distance


func focus_on(point_m: Vector3) -> void:
    _target_focus = Vector3(point_m.x, 0.0, point_m.z)


func _input(event: InputEvent) -> void:
    # A release over a HUD panel must still end a drag that began over the world.
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
        _orbiting = false


func _unhandled_input(event: InputEvent) -> void:
    if not input_enabled:
        return
    if event is InputEventMouseButton:
        var button := event as InputEventMouseButton
        match button.button_index:
            MOUSE_BUTTON_MIDDLE:
                _orbiting = button.pressed
            MOUSE_BUTTON_WHEEL_UP:
                if button.pressed and not _over_gui():
                    _target_distance = clampf(_target_distance * (1.0 - zoom_step), distance_min_m, distance_max_m)
            MOUSE_BUTTON_WHEEL_DOWN:
                if button.pressed and not _over_gui():
                    _target_distance = clampf(_target_distance * (1.0 + zoom_step), distance_min_m, distance_max_m)
    elif event is InputEventMouseMotion:
        var motion := event as InputEventMouseMotion
        if _orbiting:
            _target_yaw -= motion.relative.x * orbit_speed_deg_per_px
            _target_pitch = clampf(_target_pitch + motion.relative.y * orbit_speed_deg_per_px, pitch_min_deg, pitch_max_deg)
    elif event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_F:
            reset_view()


func _over_gui() -> bool:
    ## Wheel steps over a HUD control scroll or are ignored; they never zoom the world.
    return get_viewport().gui_get_hovered_control() != null


func _process(delta: float) -> void:
    if input_enabled and not get_viewport().gui_get_focus_owner() is LineEdit:
        var move := Vector2.ZERO
        if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
            move.y -= 1.0
        if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
            move.y += 1.0
        if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
            move.x -= 1.0
        if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
            move.x += 1.0
        if move != Vector2.ZERO:
            _pan(move.normalized() * pan_speed_m_per_s * delta * (_target_distance / 28.0))
        if edge_pan_enabled and DisplayServer.get_name() != "headless" and get_window().has_focus() and not _orbiting and not _over_gui():
            var mouse := get_viewport().get_mouse_position()
            var viewport_size := get_viewport().get_visible_rect().size
            _edge_pan(mouse, viewport_size, delta)
        if Input.is_key_pressed(KEY_HOME):
            _target_pitch = clampf(_target_pitch + 50.0 * delta, pitch_min_deg, pitch_max_deg)
        if Input.is_key_pressed(KEY_END):
            _target_pitch = clampf(_target_pitch - 50.0 * delta, pitch_min_deg, pitch_max_deg)
        if Input.is_key_pressed(KEY_Z):
            _target_distance = maxf(distance_min_m, _target_distance * exp(-delta))
        if Input.is_key_pressed(KEY_X):
            _target_distance = minf(distance_max_m, _target_distance * exp(delta))
        if Input.is_key_pressed(KEY_Q):
            _target_yaw += 90.0 * delta
        if Input.is_key_pressed(KEY_E):
            _target_yaw -= 90.0 * delta
    var t := clampf(smoothing * delta, 0.0, 1.0)
    position = position.lerp(_target_focus, t)
    yaw_deg = lerp_angle(deg_to_rad(yaw_deg), deg_to_rad(_target_yaw), t) * 180.0 / PI
    pitch_deg = lerpf(pitch_deg, _target_pitch, t)
    distance_m = lerpf(distance_m, _target_distance, t)
    _apply_camera()


func _edge_pan(mouse: Vector2, viewport_size: Vector2, delta: float) -> void:
    if not Rect2(Vector2.ZERO, viewport_size).has_point(mouse):
        return
    var movement := Vector2.ZERO
    if mouse.x < edge_margin_px: movement.x = -1.0
    elif mouse.x > viewport_size.x - edge_margin_px: movement.x = 1.0
    if mouse.y < edge_margin_px: movement.y = -1.0
    elif mouse.y > viewport_size.y - edge_margin_px: movement.y = 1.0
    if movement != Vector2.ZERO:
        _pan(movement.normalized() * pan_speed_m_per_s * delta * (_target_distance / 28.0))


func _pan(screen_move: Vector2) -> void:
    ## screen_move.x is right/left, screen_move.y is forward(-)/back(+) relative to the yaw.
    var yaw := deg_to_rad(_target_yaw)
    var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
    var right := Vector3(cos(yaw), 0.0, -sin(yaw))
    var next := _target_focus + right * screen_move.x + forward * -screen_move.y
    next.x = clampf(next.x, bounds_min.x, bounds_max.x)
    next.z = clampf(next.z, bounds_min.y, bounds_max.y)
    _target_focus = next
    focus_changed.emit(_target_focus)


func _apply_camera() -> void:
    # Keep the focus in the exposed world area beside mission control. This
    # camera-local offset also preserves the existing picking projection.
    var height := get_viewport().get_visible_rect().size.y
    camera.h_offset = distance_m * tan(deg_to_rad(camera.fov * 0.5)) * hud_width / maxf(1.0, height)
    var yaw := deg_to_rad(yaw_deg)
    var pitch := deg_to_rad(pitch_deg)
    var offset := Vector3(
        sin(yaw) * cos(pitch) * distance_m,
        sin(pitch) * distance_m,
        cos(yaw) * cos(pitch) * distance_m)
    camera.position = offset
    camera.look_at(global_position, Vector3.UP)


func ground_point(screen_pos: Vector2, plane_height: float = 0.0) -> Variant:
    ## Intersects the mouse ray with the horizontal plane y = plane_height. Returns Vector3 or null.
    if camera == null:
        return null
    var origin := camera.project_ray_origin(screen_pos)
    var direction := camera.project_ray_normal(screen_pos)
    var plane := Plane(Vector3.UP, plane_height)
    return plane.intersects_ray(origin, direction)
