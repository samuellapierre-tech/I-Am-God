extends RefCounted
## Fonctions pures du globe (sans rendu ni autoload), testées par tests/test_globe.gd.
##
## Repère de la planète (espace objet, rayon 1) : Y vers le pôle Nord, longitude 0 vers +Z,
## longitude croissante vers +X (l'est est à droite quand on regarde le globe depuis +Z).
##   dir = (cos lat · sin lon, sin lat, cos lat · cos lon)
## Grille WorldSim équirectangulaire : uv.x = lon / TAU (modulo 1), uv.y = 0.5 - lat / PI
## (ligne 0 = pôle Nord), cellule = floor(uv · grille). Mêmes formules que shaders/globe.gdshader.

## Altitude de la caméra au-dessus de la surface, en rayons planétaires.
const MIN_ALTITUDE := 0.035
const MAX_ALTITUDE := 3.2
## Altitude atteinte en remontant du sol : on voit la courbure de la planète et ses côtes.
const ARRIVAL_ALTITUDE := 1.0
## Inclinaison maximale de la caméra vers l'horizon près du sol (radians).
const MAX_TILT := deg_to_rad(48.0)
## La caméra s'incline entre ces deux altitudes (droite au-dessus, inclinée près du sol).
const TILT_START_ALTITUDE := 0.45
## Latitude maximale du centre de vue (évite la singularité au pôle).
const MAX_VIEW_LAT := deg_to_rad(84.0)


static func lat_lon_to_dir(lat: float, lon: float) -> Vector3:
	var c := cos(lat)
	return Vector3(c * sin(lon), sin(lat), c * cos(lon))


## Direction (non nécessairement normée) -> (lat, lon) en radians, lon dans ]-PI, PI].
static func dir_to_lat_lon(dir: Vector3) -> Vector2:
	var d := dir.normalized()
	return Vector2(asin(clampf(d.y, -1.0, 1.0)), atan2(d.x, d.z))


static func dir_to_uv(dir: Vector3) -> Vector2:
	var ll := dir_to_lat_lon(dir)
	return Vector2(fposmod(ll.y / TAU, 1.0), 0.5 - ll.x / PI)


static func uv_to_dir(uv: Vector2) -> Vector3:
	return lat_lon_to_dir((0.5 - uv.y) * PI, uv.x * TAU)


## Bouclage en x (couture de la longitude), bornage en y (pôles).
static func uv_to_cell(uv: Vector2, grid: Vector2i) -> Vector2i:
	var x := posmod(int(floorf(uv.x * grid.x)), grid.x)
	var y := clampi(int(floorf(uv.y * grid.y)), 0, grid.y - 1)
	return Vector2i(x, y)


static func cell_to_uv(cell: Vector2i, grid: Vector2i) -> Vector2:
	return Vector2((posmod(cell.x, grid.x) + 0.5) / grid.x, (clampi(cell.y, 0, grid.y - 1) + 0.5) / grid.y)


static func cell_to_dir(cell: Vector2i, grid: Vector2i) -> Vector3:
	return uv_to_dir(cell_to_uv(cell, grid))


static func dir_to_cell(dir: Vector3, grid: Vector2i) -> Vector2i:
	return uv_to_cell(dir_to_uv(dir), grid)


static func cell_lat_lon(cell: Vector2i, grid: Vector2i) -> Vector2:
	var uv := cell_to_uv(cell, grid)
	return Vector2((0.5 - uv.y) * PI, uv.x * TAU)


## Distance du point d'entrée d'un rayon dans une sphère centrée à l'origine, ou -1 s'il la manque.
## Si l'origine est dans la sphère, renvoie la sortie.
static func ray_sphere(origin: Vector3, dir: Vector3, radius := 1.0) -> float:
	var d := dir.normalized()
	var b := origin.dot(d)
	var c := origin.length_squared() - radius * radius
	var disc := b * b - c
	if disc < 0.0:
		return -1.0
	var s := sqrt(disc)
	var t := -b - s
	if t < 0.0:
		t = -b + s
	return t if t >= 0.0 else -1.0


## Rayon (dans le repère de la planète) -> cellule touchée, ou (-1, -1) s'il manque la planète.
static func ray_to_cell(origin: Vector3, dir: Vector3, grid: Vector2i, radius := 1.0) -> Vector2i:
	var t := ray_sphere(origin, dir, radius)
	if t < 0.0:
		return Vector2i(-1, -1)
	return dir_to_cell(origin + dir.normalized() * t, grid)


## Rayon d'une caméra perspective (FOV vertical, comme Camera3D.KEEP_HEIGHT) passant par un point écran.
## Renvoie [origine, direction normée].
static func perspective_ray(screen: Vector2, viewport: Vector2, cam: Transform3D, fov_deg: float) -> Array:
	var ndc := Vector2(screen.x / viewport.x * 2.0 - 1.0, 1.0 - screen.y / viewport.y * 2.0)
	var th := tan(deg_to_rad(fov_deg) * 0.5)
	var local := Vector3(ndc.x * th * viewport.x / viewport.y, ndc.y * th, -1.0)
	return [cam.origin, (cam.basis * local).normalized()]


## Vecteur « nord » tangent à la sphère au point (lat, lon).
static func north_at(lat: float, lon: float) -> Vector3:
	return Vector3(-sin(lat) * sin(lon), cos(lat), -sin(lat) * cos(lon))


## Inclinaison de la caméra selon l'altitude : droite en orbite, vers l'horizon près du sol.
static func tilt_for_altitude(altitude: float) -> float:
	return MAX_TILT * (1.0 - smoothstep(MIN_ALTITUDE, TILT_START_ALTITUDE, altitude))


## Caméra orbitale qui regarde le point (lat, lon) de la surface, depuis `altitude` rayons,
## inclinée de `tilt` vers le nord. Le point visé est toujours au centre de l'écran.
static func orbit_transform(lat: float, lon: float, altitude: float, tilt := 0.0, radius := 1.0) -> Transform3D:
	var up := lat_lon_to_dir(lat, lon)
	var north := north_at(lat, lon)
	var target := up * radius
	var back := up * cos(tilt) - north * sin(tilt)
	var pos := target + back * altitude * radius
	var cam_up := north * cos(tilt) + up * sin(tilt)
	return Transform3D(Basis.looking_at(target - pos, cam_up), pos)


## Angle (radians) entre deux points de la sphère.
static func angle_between(a: Vector3, b: Vector3) -> float:
	return a.normalized().angle_to(b.normalized())


## Rotation (radians) par pixel de glissement, pour que la surface suive à peu près le curseur.
static func drag_rate(altitude: float, viewport_height: float, fov_deg: float) -> float:
	var visible := 2.0 * altitude * tan(deg_to_rad(fov_deg) * 0.5)
	return minf(visible, PI * 0.9) / maxf(viewport_height, 1.0)


## Molette : altitude suivante (facteur multiplicatif), bornée.
static func wheel_altitude(altitude: float, notches: float, step := 1.3) -> float:
	return clampf(altitude * pow(step, notches), MIN_ALTITUDE, MAX_ALTITUDE)


## Vrai quand un nouveau cran de molette vers l'avant doit faire descendre au sol :
## l'altitude visée est déjà au minimum et la caméra y est presque arrivée.
static func should_descend(target_altitude: float, altitude: float) -> bool:
	return target_altitude <= MIN_ALTITUDE * 1.001 and altitude <= MIN_ALTITUDE * 1.15


## Niveau de détail pour le shader : 0 en orbite haute, 1 au ras du sol.
static func detail_level(altitude: float) -> float:
	return 1.0 - smoothstep(MIN_ALTITUDE, 1.0, altitude)


## Écart de longitude ramené dans ]-PI, PI] (chemin le plus court autour de la couture).
static func wrap_angle(a: float) -> float:
	return wrapf(a, -PI, PI)


## Direction du Soleil dans le repère de la planète (même convention que le shader planet.gdshader :
## sun_lon 0..1, season -1..1 => déclinaison ±23,5°).
static func sun_direction(sun_lon: float, season: float) -> Vector3:
	return lat_lon_to_dir(season * 0.41, sun_lon * TAU)
