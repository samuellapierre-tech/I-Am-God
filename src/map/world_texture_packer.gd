extends RefCounted
## Empaquette les grilles de WorldSim dans deux textures RGBA flottantes envoyées au GPU.
## Les textures sont créées une seule fois puis mises à jour (ImageTexture.update) à chaque paquet.
##
## data_texture    : R = élévation (-1..1), G = température (0..1), B = population (0..1), A = tech (0..1)
## species_texture : R = id de l'espèce dominante (-1 = aucune), G = espèce vivante (0/1),
##                   B = espèce sapiente (0/1), A = réservé (0)
##
## Ne dépend que du contrat public de WorldSim (grilles compactes, WIDTH/HEIGHT, species).

var width := 0
var height := 0
var data_image: Image
var species_image: Image
var data_texture: ImageTexture
var species_texture: ImageTexture

var _data_buf := PackedFloat32Array()
var _species_buf := PackedFloat32Array()


## Dimensions de la grille d'une simulation (constantes WIDTH/HEIGHT du script, ou propriétés).
static func grid_size(sim: Object) -> Vector2i:
	var w := 0
	var h := 0
	var script: Script = sim.get_script()
	while script != null and (w == 0 or h == 0):
		var consts := script.get_script_constant_map()
		w = int(consts.get("WIDTH", w))
		h = int(consts.get("HEIGHT", h))
		script = script.get_base_script()
	if w == 0 or h == 0:
		w = int(sim.get("WIDTH")) if sim.get("WIDTH") != null else 0
		h = int(sim.get("HEIGHT")) if sim.get("HEIGHT") != null else 0
	return Vector2i(w, h)


## Remplit les images depuis la simulation et met à jour les textures GPU.
## Renvoie false si la simulation n'est pas prête (grilles absentes ou de mauvaise taille).
func pack(sim: Object) -> bool:
	if sim == null:
		return false
	var size := grid_size(sim)
	var n := size.x * size.y
	if n <= 0:
		return false
	var elev: PackedFloat32Array = sim.get("elevation")
	var temp: PackedFloat32Array = sim.get("temperature")
	var pop: PackedFloat32Array = sim.get("population")
	var tech: PackedFloat32Array = sim.get("tech")
	var dom: PackedInt32Array = sim.get("dominant_species")
	if elev.size() < n or temp.size() < n or pop.size() < n or tech.size() < n or dom.size() < n:
		return false
	var species: Dictionary = sim.get("species") if sim.get("species") is Dictionary else {}

	if size.x != width or size.y != height:
		width = size.x
		height = size.y
		_data_buf.resize(n * 4)
		_species_buf.resize(n * 4)
		data_texture = null
		species_texture = null

	# Entrelacement RGBA. Boucle unique sur des tableaux typés locaux (le plus rapide en GDScript).
	var d := _data_buf
	var s := _species_buf
	var last_id := -2
	var alive := 0.0
	var sapient := 0.0
	var j := 0
	for i in n:
		d[j] = elev[i]
		d[j + 1] = temp[i]
		d[j + 2] = pop[i]
		d[j + 3] = tech[i]
		var id := dom[i]
		if id != last_id:
			last_id = id
			var info = species.get(id)
			if info is Dictionary:
				alive = 1.0 if info.get("alive", true) else 0.0
				sapient = 1.0 if info.get("sapient", false) else 0.0
			else:
				alive = 1.0 if id >= 0 else 0.0
				sapient = 0.0
		s[j] = float(id)
		s[j + 1] = alive
		s[j + 2] = sapient
		s[j + 3] = 0.0
		j += 4
	_data_buf = d
	_species_buf = s

	if data_image == null:
		data_image = Image.create_from_data(width, height, false, Image.FORMAT_RGBAF, d.to_byte_array())
		species_image = Image.create_from_data(width, height, false, Image.FORMAT_RGBAF, s.to_byte_array())
	else:
		data_image.set_data(width, height, false, Image.FORMAT_RGBAF, d.to_byte_array())
		species_image.set_data(width, height, false, Image.FORMAT_RGBAF, s.to_byte_array())

	if data_texture == null:
		data_texture = ImageTexture.create_from_image(data_image)
		species_texture = ImageTexture.create_from_image(species_image)
	else:
		data_texture.update(data_image)
		species_texture.update(species_image)
	return true
