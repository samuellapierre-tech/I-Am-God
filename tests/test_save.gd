extends RefCounted
## Sauvegarde (src/save/) : aller-retour avec déterminisme strict, fichiers corrompus ou anciens,
## écriture atomique, emplacements, tolérance aux champs, bornes de mémoire et de taille.
## Chaque test renvoie "" en cas de succès, sinon un message d'erreur.

const WorldSim := preload("res://src/sim/world_sim.gd")
const ParcelSim := preload("res://src/sim/parcel_sim.gd")
const Serializer := preload("res://src/save/serializer.gd")
const SaveStore := preload("res://src/save/save_store.gd")
const Pantheon := preload("res://src/save/pantheon.gd")
const Planet := preload("res://src/save/planet.gd")


func _step(sim: RefCounted, parcel: RefCounted, frames: int) -> void:
	for i in frames:
		var ev: Array = sim.step(sim.ideal_step_years() * sim.max_substeps)
		parcel.update(ev)


static func _temp_dir(tag: String) -> String:
	var d := "user://test_save_%s_%d" % [tag, Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(d)
	return d


static func _clean(dir: String) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	for f in da.get_files():
		da.remove(f)
	DirAccess.remove_absolute(dir)


static func _write_raw_envelope(path: String, env: Variant) -> void:
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	f.store_var(env)
	f.close()


## Sauver, recharger, continuer N pas == continuer sans sauvegarde (octet pour octet).
func _roundtrip(seed_value: int, scenario: String, before: int, after: int) -> String:
	var sim: RefCounted
	if scenario == "planet":
		# Planète de réincarnation (paramètres passés à WorldSim) : tectonique et géographie actives.
		sim = Planet.make_world({seed = seed_value, ocean_fraction = 0.7, axial_tilt = 30.0, star_luminosity = 1.1, plates = 11})
	elif scenario == "":
		sim = WorldSim.new(seed_value)
	else:
		sim = WorldSim.new(seed_value, true, scenario)
	var parcel := ParcelSim.new(sim, Vector2i(70, 40))
	_step(sim, parcel, before)
	var data := Serializer.encode({sim = sim, parcel = parcel})
	var bytes := var_to_bytes(data)
	var res := Serializer.decode(bytes_to_var(bytes))
	if not res.errors.is_empty():
		return "erreurs de décodage : %s" % [res.errors]
	var sim2: RefCounted = res.value.sim
	var parcel2: RefCounted = res.value.parcel
	if parcel2.world != sim2:
		return "la parcelle rechargée ne pointe pas vers le monde rechargé"
	if Serializer.fingerprint(sim2) != Serializer.fingerprint(sim):
		return "état rechargé différent de l'état sauvé"
	_step(sim, parcel, after)
	_step(sim2, parcel2, after)
	if Serializer.fingerprint(sim2) != Serializer.fingerprint(sim):
		return "graine %d (%s) : divergence après %d pas" % [seed_value, scenario if scenario != "" else "prologue", after]
	if Serializer.fingerprint(parcel2) != Serializer.fingerprint(parcel):
		return "graine %d : la parcelle diverge après %d pas" % [seed_value, after]
	return ""


func test_roundtrip_is_deterministic() -> String:
	for c in [[7, "", 60, 120], [42, WorldSim.SCENARIO_CRETACEOUS, 200, 200], [13, "planet", 400, 300]]:
		var err := _roundtrip(c[0], c[1], c[2], c[3])
		if err != "":
			return err
	# Contrôle négatif : le test voit bien une différence d'aléa.
	var sim := WorldSim.new(7, true, WorldSim.SCENARIO_CRETACEOUS)
	var parcel := ParcelSim.new(sim, Vector2i(70, 40))
	_step(sim, parcel, 20)
	var res := Serializer.decode(Serializer.encode({sim = sim, parcel = parcel}))
	var sim2: RefCounted = res.value.sim
	sim2._rng.randi()
	_step(sim, parcel, 100)
	_step(sim2, res.value.parcel, 100)
	if Serializer.fingerprint(sim2) == Serializer.fingerprint(sim):
		return "contrôle négatif : un aléa décalé ne change rien (empreinte insensible)"
	return ""


func test_atomic_write_and_slots() -> String:
	var dir := _temp_dir("atomic")
	var err := _atomic(dir)
	_clean(dir)
	return err


func _atomic(dir: String) -> String:
	if SaveStore.save_slot("slot_1", {world = {}, n = 1}, {world_name = "Kalo"}, dir) != "":
		return "écriture refusée"
	var final := SaveStore.path_of("slot_1", dir)
	if not FileAccess.file_exists(final) or FileAccess.file_exists(final + ".tmp") or FileAccess.file_exists(final + ".bak"):
		return "fichiers après écriture : principal %s, tmp %s, bak %s" % [FileAccess.file_exists(final),
			FileAccess.file_exists(final + ".tmp"), FileAccess.file_exists(final + ".bak")]
	# Remplacement : la nouvelle version remplace l'ancienne.
	SaveStore.save_slot("slot_1", {world = {}, n = 2}, {world_name = "Kalo"}, dir)
	var r := SaveStore.load_slot("slot_1", dir)
	if r.error != "" or int(r.payload.n) != 2:
		return "relecture : %s / %s" % [r.error, r.payload]
	# Écriture interrompue : un .tmp abandonné ne gêne ni la lecture ni l'écriture suivante.
	var junk := FileAccess.open(final + ".tmp", FileAccess.WRITE)
	junk.store_string("à moitié écrit")
	junk.close()
	if SaveStore.load_slot("slot_1", dir).payload.get("n") != 2:
		return "un .tmp abandonné perturbe la lecture"
	if SaveStore.save_slot("slot_1", {world = {}, n = 3}, {}, dir) != "" or FileAccess.file_exists(final + ".tmp"):
		return "un .tmp abandonné bloque l'écriture"
	# Coupure entre les deux renommages : le principal est abîmé, la copie .bak le remplace.
	DirAccess.copy_absolute(final, final + ".bak")
	var bad := FileAccess.open(final, FileAccess.WRITE)
	bad.store_string("abîmé")
	bad.close()
	r = SaveStore.load_slot("slot_1", dir)
	if r.error != "" or not r.from_backup or int(r.payload.n) != 3:
		return "secours .bak non utilisé : %s" % [r]
	DirAccess.remove_absolute(final + ".bak")
	# Plusieurs emplacements, listés du plus récent au plus ancien, sans décompresser.
	SaveStore.save_slot("slot_1", {world = {}, n = 4}, {world_name = "Kalo"}, dir)
	OS.delay_msec(1100)
	SaveStore.save_slot("slot_2", {world = {}}, {world_name = "Ora"}, dir)
	var slots := SaveStore.list_slots(dir)
	if slots.size() != 2 or slots[0].slot != "slot_2" or slots[0].meta.get("world_name") != "Ora":
		return "emplacements : %s" % [slots]
	SaveStore.delete_slot("slot_2", dir)
	if SaveStore.list_slots(dir).size() != 1:
		return "suppression d'emplacement"
	return ""


func test_corrupt_or_old_files() -> String:
	var dir := _temp_dir("corrupt")
	var err := _corrupt(dir)
	_clean(dir)
	return err


func _corrupt(dir: String) -> String:
	var p := SaveStore.path_of("slot_1", dir)
	if SaveStore.load_slot("slot_1", dir).error != SaveStore.ERR_MISSING:
		return "emplacement absent non signalé"
	# Octets quelconques.
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_buffer(PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9]))
	f.close()
	if SaveStore.load_slot("slot_1", dir).error != SaveStore.ERR_CORRUPT:
		return "fichier quelconque accepté"
	# Mauvaise signature.
	_write_raw_envelope(p, {magic = "AUTRE", version = 1, payload = {}})
	if SaveStore.load_slot("slot_1", dir).error != SaveStore.ERR_CORRUPT:
		return "signature étrangère acceptée"
	# Somme de contrôle fausse (contenu altéré).
	_write_raw_envelope(p, {magic = SaveStore.MAGIC, version = SaveStore.VERSION, check = 12345,
		payload = {world = {}, game = {}}})
	if SaveStore.load_slot("slot_1", dir).error != SaveStore.ERR_CORRUPT:
		return "contenu altéré accepté"
	# Version future : refus propre.
	_write_raw_envelope(p, {magic = SaveStore.MAGIC, version = SaveStore.VERSION + 1, payload = {}})
	if SaveStore.load_slot("slot_1", dir).error != SaveStore.ERR_TOO_NEW:
		return "version future non refusée"
	# Ancienne version (v0, prototype) : migrée.
	_write_raw_envelope(p, {magic = SaveStore.MAGIC, version = 0, payload = {world = {objects = [], root = null}}})
	var r := SaveStore.load_slot("slot_1", dir)
	if r.error != "" or not r.payload.has("game") or not r.payload.has("participants"):
		return "migration v0 -> v1 : %s" % [r]
	# Ancienne version sans monde : refus.
	_write_raw_envelope(p, {magic = SaveStore.MAGIC, version = 0, payload = {autre = 1}})
	if SaveStore.load_slot("slot_1", dir).error != SaveStore.ERR_CORRUPT:
		return "v0 sans monde acceptée"
	# Graphe d'objets abîmé : erreurs signalées, pas de plantage.
	var res := Serializer.decode({objects = [{cls = "res://n_existe_pas.gd", f = {}}], root = {Serializer.REF: 0}})
	if res.errors.is_empty():
		return "classe introuvable non signalée"
	res = Serializer.decode({objects = [], root = {Serializer.REF: 7}})
	if res.errors.is_empty():
		return "référence invalide non signalée"
	return ""


## Tolérance aux versions de code : champ inconnu ignoré, champ nouveau gardé par défaut, type converti.
func test_tolerant_to_field_changes() -> String:
	var sim := WorldSim.new(3, true, WorldSim.SCENARIO_CRETACEOUS)
	var data := Serializer.encode({sim = sim})
	var fields: Dictionary = data.objects[0].f
	fields["champ_disparu_depuis"] = 42
	fields.erase("sea_level")
	fields["max_substeps"] = 6.0  # float au lieu d'int
	var res := Serializer.decode(data)
	if not res.errors.is_empty():
		return "erreurs : %s" % [res.errors]
	var s2: RefCounted = res.value.sim
	if s2.sea_level != WorldSim.new(1, false).sea_level or s2.max_substeps != 6 or typeof(s2.max_substeps) != TYPE_INT:
		return "tolérance : sea_level %s, max_substeps %s" % [s2.sea_level, s2.max_substeps]
	return ""


## Mémoire et taille bornées sur une très longue partie : la sauvegarde ne grossit plus.
func test_size_bounded_on_long_game() -> String:
	var dir := _temp_dir("long")
	var sim := WorldSim.new(11, true, WorldSim.SCENARIO_CRETACEOUS)
	var parcel := ParcelSim.new(sim, Vector2i(70, 40))
	var sizes := []
	for checkpoint in 4:
		_step(sim, parcel, 500)
		SaveStore.save_slot("auto", {world = Serializer.encode({sim = sim, parcel = parcel})}, {}, dir)
		var f := FileAccess.open(SaveStore.path_of("auto", dir), FileAccess.READ)
		sizes.append(f.get_length())
		f.close()
	_clean(dir)
	print("  tailles compressées : %s octets, ère %s, %d fiches d'espèces, journal %s" % [sizes, sim.current_era(),
		sim.species.size(), sim.causal_log.size_report()])
	if sizes.back() > 16 * 1024 * 1024:
		return "sauvegarde trop lourde : %d octets" % sizes.back()
	if float(sizes[3]) > float(sizes[1]) * 1.6:
		return "la sauvegarde grossit sans borne : %s" % [sizes]
	# Panthéon borné lui aussi.
	var pdir := _temp_dir("pantheon")
	var p := Pantheon.new(pdir)
	for i in Pantheon.MAX_ENTRIES + 50:
		p.entries.append({key = "x:%d" % i, reason = "règne"})
	p._trim()
	_clean(pdir)
	if p.entries.size() != Pantheon.MAX_ENTRIES:
		return "Panthéon non borné : %d" % p.entries.size()
	return ""


func test_planet_params_are_tolerant() -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var params := Planet.random_params(rng)
	for k in ["seed", "ocean_fraction", "axial_tilt", "star_luminosity", "plates"]:
		if not params.has(k):
			return "paramètre manquant : %s" % k
	params.inconnu = "ignoré"
	var w: RefCounted = Planet.make_world(params)
	if w.seed != params.seed:
		return "graine non transmise"
	if Planet.world_name(params.seed) != Planet.world_name(params.seed) or Planet.world_name(1) == Planet.world_name(2):
		return "nom de planète non déterministe ou constant"
	return ""


const Stub := preload("res://tests/save_stub_world.gd")


## Contrat de la Planète : paramètres dans le dictionnaire `planet` de _init ; crochets
## prepare_save() avant lecture et post_load() après chargement.
func test_planet_dict_and_hooks() -> String:
	var params := {seed = 9, ocean_fraction = 0.6, axial_tilt = 20.0, star_luminosity = 1.1, plates = 7, autre = 1}
	var w: RefCounted = Planet.make_world(params, Stub)
	if w.seed != 9 or w.planet != {ocean_fraction = 0.6, axial_tilt = 20.0, star_luminosity = 1.1, plates = 7}:
		return "dictionnaire planet : %s" % [w.planet]
	if not "ocean_fraction" in Planet.supported_params(Stub):
		return "paramètres reconnus : %s" % [Planet.supported_params(Stub)]
	w._pending = 3.5
	var data := Serializer.encode({w = w})
	if w.prepared != 1 or w.data.size() != 1:
		return "prepare_save non appelée avant lecture"
	var res := Serializer.decode(data)
	var w2: RefCounted = res.value.w
	if w2.loaded != 1 or w2.data != w.data or w2.planet != w.planet or w2.seed != 9:
		return "rechargement : post_load %d, data %s, planet %s" % [w2.loaded, w2.data, w2.planet]
	return ""
