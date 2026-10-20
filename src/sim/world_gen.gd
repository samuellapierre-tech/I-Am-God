extends RefCounted
## Génération déterministe de la planète à partir de la graine :
## altitude (continents), température (latitude + relief), humidité, biomes.
## La planète est un cylindre : la carte se raccorde horizontalement (x = 0 voisin de x = W-1).

enum Biome { OCEAN_DEEP, OCEAN, ICE, TUNDRA, TAIGA, STEPPE, FOREST, DESERT, SAVANNA, RAINFOREST, MOUNTAIN }

const BIOME_NAMES := [
	"Abysses", "Océan", "Glace", "Toundra", "Taïga", "Steppe", "Forêt tempérée", "Désert",
	"Savane", "Forêt tropicale", "Montagnes",
]
## Fertilité (capacité biotique) par biome.
const BIOME_FERTILITY: Array[float] = [0.0, 0.0, 0.03, 0.25, 0.5, 0.7, 0.9, 0.15, 0.7, 1.0, 0.3]

## Part de la surface émergée.
const LAND_FRACTION := 0.36


static func _cyl_noise(noise: FastNoiseLite, x: int, y: int, w: int, _h: int, scale: float) -> float:
	var a := TAU * float(x) / float(w)
	var r := float(w) / TAU * scale
	return noise.get_noise_3d(cos(a) * r, sin(a) * r, float(y) * scale)


## Remplit elevation, temperature (température de base, sans anomalie), moisture, biome.
## params (facultatifs) : land_fraction (part des terres), axial_tilt (degrés : une forte
## inclinaison adoucit les pôles). temp_lat / moist_lat (facultatifs, même taille) reçoivent la
## part du climat qui ne dépend pas du relief : la tectonique les réutilise (derive_climate).
static func generate(seed_value: int, w: int, h: int, elevation: PackedFloat32Array,
		temperature: PackedFloat32Array, moisture: PackedFloat32Array, biome: PackedByteArray,
		params := {}, temp_lat := PackedFloat32Array(), moist_lat := PackedFloat32Array()) -> void:
	var land_fraction := clampf(float(params.get("land_fraction", LAND_FRACTION)), 0.05, 0.95)
	var tilt := float(params.get("axial_tilt", 23.4))
	var pole_cold := clampf(0.95 * (1.0 - (tilt - 23.4) / 70.0), 0.5, 1.2)
	var n := w * h
	var relief := FastNoiseLite.new()
	relief.seed = seed_value
	relief.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	relief.fractal_type = FastNoiseLite.FRACTAL_FBM
	relief.fractal_octaves = 5
	relief.frequency = 0.012
	var continents := FastNoiseLite.new()
	continents.seed = seed_value ^ 0x5bd1e995
	continents.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	continents.frequency = 0.004
	var wet := FastNoiseLite.new()
	wet.seed = seed_value ^ 0x1b873593
	wet.fractal_type = FastNoiseLite.FRACTAL_FBM
	wet.fractal_octaves = 3
	wet.frequency = 0.02

	var raw := PackedFloat32Array()
	raw.resize(n)
	for y in h:
		var lat := absf((float(y) + 0.5) / float(h) * 2.0 - 1.0)
		for x in w:
			# Les pôles sont légèrement poussés vers l'océan pour éviter des calottes continentales géantes.
			raw[y * w + x] = _cyl_noise(relief, x, y, w, h, 1.0) * 0.55 \
				+ _cyl_noise(continents, x, y, w, h, 1.0) * 0.8 - lat * lat * 0.25
	# Niveau de la mer au percentile voulu : la part de terres est garantie quelle que soit la graine.
	var sorted := raw.duplicate()
	sorted.sort()
	var sea := sorted[clampi(int(n * (1.0 - land_fraction)), 0, n - 1)]
	var lo := sorted[0]
	var hi := sorted[n - 1]
	for i in n:
		var v := raw[i]
		elevation[i] = (v - sea) / maxf(hi - sea, 1e-4) if v >= sea else -(sea - v) / maxf(sea - lo, 1e-4)

	for y in h:
		var lat := absf((float(y) + 0.5) / float(h) * 2.0 - 1.0)
		var base_t := 1.0 - pow(lat, 1.35) * pole_cold
		# Ceintures d'humidité : équateur humide, déserts subtropicaux, latitudes moyennes humides.
		var band_wet := 0.55 + 0.35 * cos(lat * PI * 3.0)
		for x in w:
			var i := y * w + x
			var e := elevation[i]
			var tl := base_t + _cyl_noise(wet, x, y, w, h, 2.0) * 0.04
			var ml := band_wet * 0.6 + (_cyl_noise(wet, x, y, w, h, 1.0) * 0.5 + 0.5) * 0.5
			if temp_lat.size() == n:
				temp_lat[i] = tl
				moist_lat[i] = ml
			temperature[i] = clampf(tl - maxf(e, 0.0) * 0.45, 0.0, 1.0)
			moisture[i] = clampf(ml - maxf(e, 0.0) * 0.2, 0.0, 1.0)
			biome[i] = classify(e, temperature[i], moisture[i])


static func classify(e: float, t: float, m: float) -> int:
	if e < 0.0:
		if t < 0.08:
			return Biome.ICE
		return Biome.OCEAN_DEEP if e < -0.35 else Biome.OCEAN
	if e > 0.62:
		return Biome.MOUNTAIN
	if t < 0.12:
		return Biome.ICE
	if t < 0.28:
		return Biome.TUNDRA
	if t < 0.45:
		return Biome.TAIGA if m > 0.4 else Biome.STEPPE
	if t < 0.7:
		if m < 0.3:
			return Biome.DESERT
		return Biome.FOREST if m > 0.5 else Biome.STEPPE
	if m < 0.3:
		return Biome.DESERT
	return Biome.RAINFOREST if m > 0.6 else Biome.SAVANNA


## Climat de base d'un relief donné (tectonique) : température (latitude, altitude), humidité
## (latitude, altitude, continentalité : l'intérieur des continents est plus sec), biome.
static func derive_climate(elevation: PackedFloat32Array, temp_lat: PackedFloat32Array,
		moist_lat: PackedFloat32Array, coast_dist: PackedFloat32Array, temperature: PackedFloat32Array,
		moisture: PackedFloat32Array, biome: PackedByteArray) -> void:
	for i in elevation.size():
		var e := elevation[i]
		var inland := smoothstep(3.0, 18.0, coast_dist[i]) if e >= 0.0 else 0.0
		temperature[i] = clampf(temp_lat[i] - maxf(e, 0.0) * 0.45 - inland * 0.03, 0.0, 1.0)
		moisture[i] = clampf(moist_lat[i] - maxf(e, 0.0) * 0.2 - inland * 0.25, 0.0, 1.0)
		biome[i] = classify(e, temperature[i], moisture[i])

