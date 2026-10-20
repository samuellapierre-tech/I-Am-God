extends RefCounted
## Fabriques de particules GPU (GPUParticles2D + ParticleProcessMaterial) pour la parcelle :
## fumée (incendies, cratère fumant), étincelles et débris (impacts).

## Halo doux (pas de cache statique : une ressource gardée en variable statique survit à la
## fermeture du jeu et serait signalée comme fuite ; on n'en crée qu'à chaque fumée ou gerbe).
static func puff_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var puff := GradientTexture2D.new()
	puff.gradient = g
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(1.0, 0.5)
	puff.width = 64
	puff.height = 64
	return puff


static func _ramp(colors: Array, offsets: PackedFloat32Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = offsets
	g.colors = PackedColorArray(colors)
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex


## Fumée qui monte et dérive. extents : demi-taille de la zone d'émission (monde).
static func make_smoke(extents: Vector2, amount: int, dark := true) -> GPUParticles2D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(extents.x, extents.y, 0.0)
	pm.direction = Vector3(0.35, -1.0, 0.0)
	pm.spread = 25.0
	pm.initial_velocity_min = 15.0
	pm.initial_velocity_max = 45.0
	pm.gravity = Vector3(10.0, -12.0, 0.0)
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.35))
	curve.add_point(Vector2(1.0, 1.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var base := Color(0.16, 0.14, 0.13) if dark else Color(0.75, 0.75, 0.75)
	pm.color_ramp = _ramp([Color(base, 0.0), Color(base, 0.45), Color(base.lightened(0.3), 0.0)],
		PackedFloat32Array([0.0, 0.2, 1.0]))
	var p := GPUParticles2D.new()
	p.process_material = pm
	p.texture = puff_texture()
	p.amount = amount
	p.lifetime = 6.0
	# Large : la fumée monte et dérive loin de sa zone d'émission (évite les coupures nettes).
	p.visibility_rect = Rect2(-extents - Vector2(1500, 1500), extents * 2.0 + Vector2(3000, 3000))
	# Les halos font 64 px : on agrandit par l'échelle.
	pm.scale_min *= 1.5
	pm.scale_max *= 2.5
	return p


## Gerbe d'étincelles et de débris (une seule fois). radius : portée approximative.
static func make_sparks(radius: float, color: Color) -> GPUParticles2D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 10.0
	pm.direction = Vector3(1, 0, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = radius * 0.8
	pm.initial_velocity_max = radius * 2.0
	pm.gravity = Vector3.ZERO
	pm.damping_min = radius * 0.8
	pm.damping_max = radius * 1.4
	pm.scale_min = 0.08
	pm.scale_max = 0.25
	pm.color_ramp = _ramp([Color(1, 1, 0.8, 1), color, Color(color.darkened(0.6), 0.0)],
		PackedFloat32Array([0.0, 0.3, 1.0]))
	var p := GPUParticles2D.new()
	p.process_material = pm
	p.texture = puff_texture()
	p.amount = 90
	p.lifetime = 1.4
	p.one_shot = true
	p.explosiveness = 0.95
	p.visibility_rect = Rect2(-Vector2.ONE * radius * 3.0, Vector2.ONE * radius * 6.0)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	return p
