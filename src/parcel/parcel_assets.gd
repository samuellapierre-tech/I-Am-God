extends RefCounted
## Images définitives de la parcelle, si elles existent (convention : assets/parcel/README.md).
## Sinon null : l'appelant dessine son placeholder. Résultats mis en cache.

const ParcelLogic := preload("res://src/parcel/parcel_logic.gd")

var _cache := {}


func creature_texture(clade: String, role: String) -> Texture2D:
	return _load_first(ParcelLogic.creature_asset_candidates(clade, role))


func structure_texture(kind: String, land_use: String) -> Texture2D:
	return _load_first(ParcelLogic.structure_asset_candidates(kind, land_use))


func _load_first(candidates: PackedStringArray) -> Texture2D:
	var key := ",".join(candidates)
	if _cache.has(key):
		return _cache[key]
	var path := ParcelLogic.resolve_asset(candidates, _exists)
	var tex := _load(path) if path != "" else null
	_cache[key] = tex
	return tex


func _exists(path: String) -> bool:
	return ResourceLoader.exists(path) or FileAccess.file_exists(path)


## Image importée par l'éditeur, sinon PNG brut (déposé sans réimport, utile pendant la production).
func _load(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)
