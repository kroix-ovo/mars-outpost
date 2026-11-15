extends RefCounted
## Procedural art for the front end: a starfield sky, a stylised Mars globe with a thin dusty
## atmosphere, the transit ship that carries the lander, and the Martian ground for the intro.
## Everything is built from shaders and primitive meshes; no external textures.

const Lander := preload("res://scripts/world/lander_art.gd")
const Art := preload("res://scripts/world/module_art.gd")

const NOISE := """
float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm3(vec3 p) {
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		total += amp * noise3(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return total;
}
"""

const STAR_SKY := """
shader_type sky;
%s
void sky() {
	vec3 d = EYEDIR;
	vec3 cell = d * 260.0;
	vec3 id = floor(cell);
	float pick = hash3(id);
	float star = step(0.9955, pick) * smoothstep(0.42, 0.0, length(fract(cell) - 0.5));
	float twinkle = 0.75 + 0.25 * sin(TIME * (1.0 + 3.0 * hash3(id + 3.0)) + pick * 40.0);
	vec3 tint = mix(vec3(0.75, 0.82, 1.0), vec3(1.0, 0.86, 0.7), hash3(id + 9.0));
	float band = exp(-pow(dot(d, normalize(vec3(0.35, 1.0, 0.25))) * 3.2, 2.0));
	float dust = fbm3(d * 6.0) * band;
	vec3 color = vec3(0.006, 0.008, 0.02) + vec3(0.16, 0.12, 0.22) * dust * 0.55;
	color += tint * star * twinkle * (0.6 + 1.6 * hash3(id + 5.0));
	float sun = dot(d, LIGHT0_DIRECTION);
	color += vec3(1.0, 0.92, 0.8) * (smoothstep(0.9993, 0.9998, sun) * 6.0 + pow(max(sun, 0.0), 180.0) * 0.6);
	COLOR = color;
}
""" % NOISE

const MARS := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform float spin = 0.0;
varying vec3 local_dir;
%s
void vertex() {
	local_dir = normalize(VERTEX);
}
void fragment() {
	float c = cos(spin);
	float s = sin(spin);
	vec3 n = vec3(c * local_dir.x - s * local_dir.z, local_dir.y, s * local_dir.x + c * local_dir.z);
	float broad = fbm3(n * 2.6 + vec3(4.0));
	float fine = fbm3(n * 11.0);
	vec3 dark = vec3(0.30, 0.13, 0.08);
	vec3 rust = vec3(0.72, 0.34, 0.17);
	vec3 dust = vec3(0.88, 0.58, 0.38);
	vec3 col = mix(dark, rust, smoothstep(0.38, 0.62, broad));
	col = mix(col, dust, smoothstep(0.55, 0.78, fine) * 0.45);
	// A long canyon scar across the equator.
	float scar = abs(n.y + 0.08 + 0.05 * sin(n.x * 5.0 + n.z * 3.0));
	float along = smoothstep(-0.2, 0.5, n.z) * smoothstep(0.95, 0.2, n.z);
	col *= 1.0 - (1.0 - smoothstep(0.0, 0.035, scar)) * 0.45 * along;
	// Craters.
	float pits = smoothstep(0.78, 0.86, noise3(n * 24.0));
	col *= 1.0 - pits * 0.25;
	// Polar caps.
	float cap = smoothstep(0.92, 0.95, abs(n.y) + 0.04 * fine);
	col = mix(col, vec3(0.96, 0.94, 0.9), cap);
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
""" % NOISE

const ATMOSPHERE := """
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;
uniform vec3 sun_dir = vec3(-1.0, 0.3, 0.6);
uniform vec3 glow : source_color = vec3(1.0, 0.55, 0.32);
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.6);
	vec3 world_n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float lit = clamp(dot(world_n, normalize(sun_dir)) * 0.9 + 0.35, 0.0, 1.0);
	ALBEDO = glow * rim * lit * 1.4;
}
"""

const GROUND := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
varying vec3 world_pos;
%s
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 p = world_pos.xz;
	float broad = fbm3(vec3(p * 0.05, 1.0));
	float fine = fbm3(vec3(p * 0.6, 7.0));
	vec3 col = mix(vec3(0.55, 0.27, 0.15), vec3(0.78, 0.47, 0.30), broad);
	col = mix(col, vec3(0.42, 0.2, 0.12), smoothstep(0.55, 0.75, fine) * 0.5);
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
""" % NOISE


static func star_environment() -> Environment:
	var shader := Shader.new()
	shader.code = STAR_SKY
	var material := ShaderMaterial.new()
	material.shader = shader
	var sky := Sky.new()
	sky.sky_material = material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.3, 0.38)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.08
	return env


static func mars_globe(radius: float, sun_dir: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Mars"
	var surface := MeshInstance3D.new()
	surface.name = "Surface"
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 96
	sphere.rings = 48
	surface.mesh = sphere
	var shader := Shader.new()
	shader.code = MARS
	var material := ShaderMaterial.new()
	material.shader = shader
	surface.material_override = material
	root.add_child(surface)
	var halo := MeshInstance3D.new()
	halo.name = "Atmosphere"
	var shell := SphereMesh.new()
	shell.radius = radius * 1.035
	shell.height = radius * 2.07
	shell.radial_segments = 96
	shell.rings = 48
	halo.mesh = shell
	var glow_shader := Shader.new()
	glow_shader.code = ATMOSPHERE
	var glow := ShaderMaterial.new()
	glow.shader = glow_shader
	glow.set_shader_parameter("sun_dir", sun_dir)
	halo.material_override = glow
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(halo)
	return root


static func transit_ship() -> Node3D:
	## The lander riding on a transfer stage with solar wings. Its long axis is local +Y
	## (lander nose first); rotate the returned node to point it along the flight path.
	var ship := Node3D.new()
	ship.name = "TransitShip"
	var lander := Node3D.new()
	lander.set_script(Lander)
	ship.add_child(lander)
	var shell := Art.mat(Art.SHELL, 0.6, 0.15)
	var dark := Art.mat(Art.CHARCOAL, 0.8, 0.2)
	var metal := Art.mat(Art.GRAPHITE, 0.45, 0.6)
	var amber := Art.mat(Art.AMBER, 0.6)
	_cyl(ship, 0.9, 0.9, 0.5, Vector3(0, 0.2, 0), metal)
	_cyl(ship, 1.05, 1.05, 3.2, Vector3(0, -1.65, 0), shell)
	_cyl(ship, 1.08, 1.08, 0.12, Vector3(0, -0.6, 0), amber)
	_cyl(ship, 1.08, 1.08, 0.12, Vector3(0, -2.7, 0), metal)
	_cyl(ship, 0.55, 0.95, 0.5, Vector3(0, -3.5, 0), dark)
	_cyl(ship, 0.9, 0.45, 1.1, Vector3(0, -4.25, 0), metal)
	var flame := StandardMaterial3D.new()
	flame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame.albedo_color = Color(0.55, 0.8, 1.0, 0.55)
	flame.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var plume := _cyl(ship, 0.75, 0.05, 2.4, Vector3(0, -6.0, 0), flame)
	plume.name = "EnginePlume"
	plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Solar wings: a truss and two blue panel blades on each side.
	var cells := StandardMaterial3D.new()
	cells.albedo_color = Color(0.13, 0.22, 0.46)
	cells.metallic = 0.5
	cells.roughness = 0.25
	for side in [-1.0, 1.0]:
		var sx: float = side
		_box(ship, Vector3(1.2, 0.12, 0.12), Vector3(sx * 1.6, -1.8, 0), metal)
		for k in 2:
			var blade := _box(ship, Vector3(2.6, 1.3, 0.05), Vector3(sx * (3.4 + k * 2.75), -1.8, 0), cells)
			blade.name = "SolarBlade"
			_box(ship, Vector3(2.62, 0.05, 0.06), Vector3(sx * (3.4 + k * 2.75), -1.8, 0), metal)
	# Radiators and a high-gain dish.
	_box(ship, Vector3(0.05, 1.6, 0.9), Vector3(0, -1.6, 1.1), metal)
	var dish := _cyl(ship, 0.55, 0.08, 0.2, Vector3(-0.9, -2.4, -0.9), Art.mat(Art.SHELL_WARM, 0.5, 0.2))
	dish.rotation_degrees = Vector3(60, 0, 30)
	return ship


static func mars_ground(size: float) -> MeshInstance3D:
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	plane.subdivide_width = 4
	plane.subdivide_depth = 4
	ground.mesh = plane
	var shader := Shader.new()
	shader.code = GROUND
	var material := ShaderMaterial.new()
	material.shader = shader
	ground.material_override = material
	return ground


static func rock(radius: float, seed_value: int) -> MeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var node := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 7
	sphere.rings = 4
	node.mesh = sphere
	node.scale = Vector3(rng.randf_range(0.9, 1.5), rng.randf_range(0.45, 0.8), rng.randf_range(0.8, 1.3))
	node.rotation.y = rng.randf() * TAU
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.42, 0.22, 0.14).lerp(Color(0.6, 0.36, 0.24), rng.randf())
	material.roughness = 1.0
	node.material_override = material
	return node


static func _cyl(parent: Node3D, top: float, bottom: float, height: float, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 28
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.material_override = material
	parent.add_child(node)
	return node


static func _box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.material_override = material
	parent.add_child(node)
	return node
