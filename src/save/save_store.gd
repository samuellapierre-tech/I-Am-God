extends RefCounted
## Fichiers de sauvegarde dans user:// (compatible Steam Cloud plus tard) :
## - plusieurs emplacements (auto, quick, slot_1…slot_3) ;
## - compression zstd, enveloppe versionnée {magic, version, created_unix, meta, check, payload} ;
## - écriture atomique : fichier temporaire, relu et vérifié, puis renommé ; l'ancien fichier est gardé
##   en .bak le temps du remplacement et sert de secours si le principal est illisible ;
## - à côté, un petit .meta en JSON (lecture rapide pour le menu).
## Chargement : refus propre d'un fichier corrompu (somme de contrôle) ou d'une version future,
## migration des versions anciennes (MIGRATIONS).

const MAGIC := "IAMGOD-SAVE"
## Version du format. Chaque changement incompatible ajoute une migration depuis la précédente.
const VERSION := 1
const DIR := "user://saves"
const EXT := ".igsave"
const SLOTS := ["auto", "quick", "slot_1", "slot_2", "slot_3"]

## Erreurs renvoyées par load_slot().
const ERR_NONE := ""
const ERR_MISSING := "missing"
const ERR_CORRUPT := "corrupt"
const ERR_TOO_NEW := "too_new"
const ERR_WRITE := "write"


static func path_of(slot: String, dir := DIR) -> String:
	return dir.path_join(slot + EXT)


## Écrit l'emplacement de façon atomique. Renvoie ERR_NONE ("") ou ERR_WRITE.
static func save_slot(slot: String, payload: Dictionary, meta: Dictionary, dir := DIR) -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	var final := path_of(slot, dir)
	var tmp := final + ".tmp"
	var bak := final + ".bak"
	var envelope := {
		magic = MAGIC, version = VERSION, created_unix = Time.get_unix_time_from_system(),
		meta = meta, check = checksum(payload), payload = payload,
	}
	var f := FileAccess.open_compressed(tmp, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return ERR_WRITE
	f.store_var(envelope)
	f.close()
	# Relecture du temporaire : on ne remplace jamais une bonne sauvegarde par un fichier abîmé.
	if read_envelope(tmp).error != ERR_NONE:
		DirAccess.remove_absolute(tmp)
		return ERR_WRITE
	if FileAccess.file_exists(bak):
		DirAccess.remove_absolute(bak)
	if FileAccess.file_exists(final) and DirAccess.rename_absolute(final, bak) != OK:
		DirAccess.remove_absolute(tmp)
		return ERR_WRITE
	if DirAccess.rename_absolute(tmp, final) != OK:
		# Échec du renommage : on remet l'ancien fichier en place.
		if FileAccess.file_exists(bak):
			DirAccess.rename_absolute(bak, final)
		return ERR_WRITE
	if FileAccess.file_exists(bak):
		DirAccess.remove_absolute(bak)
	_write_meta(final + ".meta", meta, envelope.created_unix)
	return ERR_NONE



## Lit un emplacement : {error, payload, meta, version, created_unix, from_backup}.
## Le fichier principal illisible, on essaie la copie de secours (.bak) d'une écriture interrompue.
static func load_slot(slot: String, dir := DIR) -> Dictionary:
	var final := path_of(slot, dir)
	var res := read_envelope(final)
	if res.error != ERR_NONE and res.error != ERR_TOO_NEW and FileAccess.file_exists(final + ".bak"):
		var bak := read_envelope(final + ".bak")
		if bak.error == ERR_NONE:
			bak.from_backup = true
			return bak
	return res


## Lit et vérifie une enveloppe, puis la migre vers la version courante.
static func read_envelope(path: String) -> Dictionary:
	var out := {error = ERR_NONE, payload = {}, meta = {}, version = 0, created_unix = 0.0, from_backup = false}
	if not FileAccess.file_exists(path):
		out.error = ERR_MISSING
		return out
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null or f.get_length() == 0:
		out.error = ERR_CORRUPT
		return out
	var env: Variant = f.get_var()
	f.close()
	if typeof(env) != TYPE_DICTIONARY or env.get("magic", "") != MAGIC or typeof(env.get("payload")) != TYPE_DICTIONARY:
		out.error = ERR_CORRUPT
		return out
	var version := int(env.get("version", 0))
	if version > VERSION:
		out.error = ERR_TOO_NEW
		out.version = version
		return out
	if env.has("check") and int(env.check) != checksum(env.payload):
		out.error = ERR_CORRUPT
		return out
	var payload: Dictionary = env.payload
	var meta: Dictionary = env.get("meta", {})
	while version < VERSION:
		var migrated := migrate(version, payload, meta)
		if migrated.is_empty():
			out.error = ERR_CORRUPT
			return out
		payload = migrated.payload
		meta = migrated.meta
		version += 1
	out.payload = payload
	out.meta = meta
	out.version = int(env.get("version", 0))
	out.created_unix = float(env.get("created_unix", 0.0))
	return out


## Migre de `from` à `from + 1`. {payload, meta}, ou {} si impossible.
## v0 (prototype) : la charge utile n'avait que {world} ; v1 ajoute game, narrator, participants.
static func migrate(from: int, payload: Dictionary, meta: Dictionary) -> Dictionary:
	match from:
		0:
			if not payload.has("world"):
				return {}
			var p := payload.duplicate()
			if not p.has("game"):
				p.game = {play_time = 0.0, world_name = "", world_index = 1, planet = {}}
			if not p.has("participants"):
				p.participants = {}
			if not p.has("narrator"):
				p.narrator = {}
			return {payload = p, meta = meta}
	return {}


static func checksum(payload: Dictionary) -> int:
	return hash(var_to_bytes(payload))


## Emplacements présents : [{slot, meta, created_unix}], du plus récent au plus ancien (lecture
## des .meta seulement, sans décompresser les sauvegardes).
static func list_slots(dir := DIR) -> Array:
	var out := []
	for slot in SLOTS:
		var final := path_of(slot, dir)
		if not FileAccess.file_exists(final):
			continue
		var info := {slot = slot, meta = {}, created_unix = 0.0}
		var m := FileAccess.open(final + ".meta", FileAccess.READ)
		if m != null:
			var parsed: Variant = JSON.parse_string(m.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				info.meta = parsed.get("meta", {})
				info.created_unix = float(parsed.get("created_unix", 0.0))
		out.append(info)
	out.sort_custom(func(a, b): return a.created_unix > b.created_unix)
	return out


static func delete_slot(slot: String, dir := DIR) -> void:
	for suffix in ["", ".meta", ".bak", ".tmp"]:
		var p: String = path_of(slot, dir) + suffix
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


static func _write_meta(path: String, meta: Dictionary, created: float) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({meta = meta, created_unix = created, version = VERSION}))
		f.close()
