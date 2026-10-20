extends RefCounted
## Textures GPU du globe, construites depuis WorldSim à cadence limitée :
## - data / species : src/map/world_texture_packer.gd (élévation, température, population, tech,
##   espèce dominante terrestre) ;
## - aux (RGBA flottant, même grille) : R = vie marine (0..1), G = vie terrestre (0..1),
##   B = espèce marine principale (-1 = aucune), A = plaque tectonique (-1 = inconnue) ;
## - prev_elevation (R flottant) : l'élévation d'avant le dernier changement de géographie, pour
##   un fondu doux quand les continents bougent (geography_fade 0 -> 1).
## La vie vient de WorldSim.region_niches (vie terrestre ET marine), balayée par morceaux sur
## plusieurs images pour ne jamais bloquer le thread principal.
## Branchement à la tectonique sans dépendance dure : `geography_version` (propriété ou méthode)
## et `plate_id` (PackedInt32Array par cellule) sont lus seulement s'ils existent.

const Packer := preload("res://src/map/world_texture_packer.gd")

## Pas d'échantillonnage de la vie (en cellules) : une requête region_niches par bloc LIFE_STEP².
const LIFE_STEP := 4
## Durée du fondu de géographie (secondes réelles).
const GEO_FADE_TIME := 2.5

var packer := Packer.new()
var width := 0
var height := 0
var aux_image: Image
var aux_texture: ImageTexture
var prev_elevation_image: Image
var prev_elevation_texture: ImageTexture
## 0 juste après un changement de géographie, 1 quand le fondu est terminé.
var geography_fade := 1.0
var geography_version := -1
## Moyennes exactes des rangées polaires (nord = rangée 0, sud = dernière rangée), pour que le shader
## fasse converger la texture vers une valeur unique à chaque pôle (pas d'étoile ni de rayons).
## data : (élévation, température, population, tech) ; aux : (vie marine, vie terrestre, 0, 0) ;
## prev : (élévation d'avant le changement de géographie, 0, 0, 0).
var pole_data := [Vector4.ZERO, Vector4.ZERO]
var pole_aux := [Vector4.ZERO, Vector4.ZERO]
var pole_prev := [Vector4.ZERO, Vector4.ZERO]
## Compteurs (tests, diagnostic).
var geography_uploads := 0
var life_sweeps := 0

var _aux := PackedFloat32Array()
var _last_elevation := PackedFloat32Array()
var _life_cursor := 0
var _has_geo_source := false


## Version de la géographie exposée par la simulation, ou -1 si elle n'en expose pas.
static func read_geography_version(sim: Object) -> int:
	if sim == null:
		return -1
	if sim.has_method("geography_version"):
		return int(sim.call("geography_version"))
	if "geography_version" in sim:
		return int(sim.get("geography_version"))
	return -1


## Empaquette les grilles. Renvoie false si la simulation n'est pas prête.
## Si la géographie a changé (geography_version), garde l'ancienne élévation pour le fondu et
## ré-écrit les plaques.
func pack(sim: Object) -> bool:
	if not packer.pack(sim):
		return false
	if packer.width != width or packer.height != height:
		_resize(packer.width, packer.height)
		_update_data_poles(sim)
		_snapshot_elevation(sim)
		_write_plates(sim)
		geography_version = read_geography_version(sim)
		_upload_aux()
		return true
	_update_data_poles(sim)
	var v := read_geography_version(sim)
	if v != geography_version:
		geography_version = v
		# L'image d'avant devient la source du fondu, puis on mémorise la nouvelle géographie.
		prev_elevation_image.set_data(width, height, false, Image.FORMAT_RF, _last_elevation.to_byte_array())
		prev_elevation_texture.update(prev_elevation_image)
		pole_prev = [Vector4(_row_mean(_last_elevation, 1, 0, 0), 0, 0, 0),
			Vector4(_row_mean(_last_elevation, 1, height - 1, 0), 0, 0, 0)]
		geography_fade = 0.0
		_snapshot_elevation(sim)
		_write_plates(sim)
		_upload_aux()
		geography_uploads += 1
	return true


func advance_fade(delta: float) -> void:
	geography_fade = minf(geography_fade + delta / GEO_FADE_TIME, 1.0)


## Balaye au plus `budget` échantillons de vie ; téléverse la texture à la fin d'un balayage complet.
## Renvoie true quand un balayage vient de se terminer.
func update_life(sim: Object, budget: int) -> bool:
	if width == 0 or sim == null or not sim.has_method("region_niches"):
		return false
	@warning_ignore("integer_division")
	var sx := width / LIFE_STEP
	@warning_ignore("integer_division")
	var sy := height / LIFE_STEP
	var total := sx * sy
	var a := _aux
	for n in budget:
		var k := _life_cursor
		var bx := (k % sx) * LIFE_STEP
		@warning_ignore("integer_division")
		var by := (k / sx) * LIFE_STEP
		var marine := 0.0
		var land := 0.0
		var top_marine := -1
		var top_density := 0.0
		for niche in sim.call("region_niches", Vector2i(bx + (LIFE_STEP >> 1), by + (LIFE_STEP >> 1))):
			var d := float(niche.get("density", 0.0))
			match str(niche.get("habitat", "land")):
				"marine":
					marine += d
					if d > top_density:
						top_density = d
						top_marine = int(niche.get("species_id", -1))
				"amphibious":
					marine += d * 0.5
					land += d * 0.5
				_:
					land += d
		marine = clampf(marine, 0.0, 1.0)
		land = clampf(land, 0.0, 1.0)
		for y in range(by, by + LIFE_STEP):
			var j := (y * width + bx) * 4
			for x in LIFE_STEP:
				a[j] = marine
				a[j + 1] = land
				a[j + 2] = float(top_marine)
				j += 4
		_life_cursor = (k + 1) % total
		if _life_cursor == 0:
			_aux = a
			_update_aux_poles()
			_upload_aux()
			life_sweeps += 1
			return true
	_aux = a
	return false


## Moyenne d'un canal sur une rangée d'un tampon entrelacé (`stride` valeurs par cellule).
func _row_mean(buf: PackedFloat32Array, stride: int, row: int, channel: int) -> float:
	if width == 0 or buf.size() < (row + 1) * width * stride:
		return 0.0
	var sum := 0.0
	var j := row * width * stride + channel
	for x in width:
		sum += buf[j]
		j += stride
	return sum / width


func _update_data_poles(sim: Object) -> void:
	var fields := ["elevation", "temperature", "population", "tech"]
	for k in 2:
		var row := 0 if k == 0 else height - 1
		var v := Vector4.ZERO
		for c in 4:
			var arr: PackedFloat32Array = sim.get(fields[c])
			v[c] = _row_mean(arr, 1, row, 0)
		pole_data[k] = v


func _update_aux_poles() -> void:
	for k in 2:
		var row := 0 if k == 0 else height - 1
		pole_aux[k] = Vector4(_row_mean(_aux, 4, row, 0), _row_mean(_aux, 4, row, 1), 0, 0)


func has_plates() -> bool:
	return _has_geo_source


func _resize(w: int, h: int) -> void:
	width = w
	height = h
	_aux.resize(w * h * 4)
	for i in w * h:
		_aux[i * 4] = 0.0
		_aux[i * 4 + 1] = 0.0
		_aux[i * 4 + 2] = -1.0
		_aux[i * 4 + 3] = -1.0
	_last_elevation.resize(w * h)
	aux_image = Image.create_from_data(w, h, false, Image.FORMAT_RGBAF, _aux.to_byte_array())
	aux_texture = ImageTexture.create_from_image(aux_image)
	prev_elevation_image = Image.create_from_data(w, h, false, Image.FORMAT_RF, _last_elevation.to_byte_array())
	prev_elevation_texture = ImageTexture.create_from_image(prev_elevation_image)
	_life_cursor = 0
	geography_fade = 1.0


func _snapshot_elevation(sim: Object) -> void:
	var elev: PackedFloat32Array = sim.get("elevation")
	_last_elevation = elev.slice(0, width * height)
	if geography_fade >= 1.0:
		prev_elevation_image.set_data(width, height, false, Image.FORMAT_RF, _last_elevation.to_byte_array())
		prev_elevation_texture.update(prev_elevation_image)
		pole_prev = [Vector4(_row_mean(_last_elevation, 1, 0, 0), 0, 0, 0),
			Vector4(_row_mean(_last_elevation, 1, height - 1, 0), 0, 0, 0)]


func _write_plates(sim: Object) -> void:
	_has_geo_source = "plate_id" in sim
	var plates: PackedInt32Array = sim.get("plate_id") if _has_geo_source else PackedInt32Array()
	var n := width * height
	var ok := plates.size() >= n
	_has_geo_source = ok
	var a := _aux
	for i in n:
		a[i * 4 + 3] = float(plates[i]) if ok else -1.0
	_aux = a


func _upload_aux() -> void:
	aux_image.set_data(width, height, false, Image.FORMAT_RGBAF, _aux.to_byte_array())
	aux_texture.update(aux_image)
