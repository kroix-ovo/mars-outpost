extends Node3D
## Title backdrop: the transit ship coasting toward a slowly turning Mars against a starfield.
## Call seek(t) for a deterministic frame (tests); otherwise it animates itself.

const SpaceArt := preload("res://scripts/frontend/space_art.gd")

const SUN_DIR := Vector3(-0.75, 0.35, 0.55)

var manual_time := false
var time := 0.0
var camera: Camera3D
var ship: Node3D
var mars: Node3D
var _mars_material: ShaderMaterial
var _plume: MeshInstance3D


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = SpaceArt.star_environment()
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.6
	sun.light_color = Color(1.0, 0.96, 0.9)
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, -SUN_DIR, Vector3.UP)
	mars = SpaceArt.mars_globe(17.0, SUN_DIR)
	mars.position = Vector3(19.0, -10.5, -40.0)
	mars.rotation_degrees = Vector3(4, 0, -14)
	add_child(mars)
	_mars_material = mars.get_node("Surface").material_override
	ship = SpaceArt.transit_ship()
	add_child(ship)
	_plume = ship.get_node("EnginePlume")
	camera = Camera3D.new()
	camera.fov = 50.0
	camera.position = Vector3(0, 0, 8)
	add_child(camera)
	camera.current = true
	seek(0.0)


func _process(delta: float) -> void:
	if not manual_time:
		seek(time + delta)


func seek(t: float) -> void:
	time = t
	if _mars_material != null:
		_mars_material.set_shader_parameter("spin", t * 0.012)
	if ship != null:
		# Nose toward Mars, drifting and rolling very slowly.
		ship.position = Vector3(3.4 + sin(t * 0.13) * 0.25, 1.75 + sin(t * 0.21) * 0.15, -6.0)
		ship.rotation = Vector3(0.55, -0.35 + sin(t * 0.08) * 0.04, -2.05)
		ship.rotate_object_local(Vector3.UP, t * 0.05)
		ship.scale = Vector3.ONE * 0.42
	if _plume != null:
		_plume.scale = Vector3(1.0, 0.85 + 0.15 * sin(t * 23.0), 1.0)
	if camera != null:
		camera.position = Vector3(sin(t * 0.05) * 0.2, cos(t * 0.04) * 0.12, 8.0)
		camera.look_at(Vector3(1.2, 0.0, -10.0), Vector3.UP)
