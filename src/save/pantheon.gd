extends RefCounted
## Panthéon : la mémoire des mondes passés, qui survit à la réincarnation (docs/GENESE.md).
## Les espèces marquantes que le joueur a vues naître (nom, description, traits, monde d'origine) et
## la liste de ses mondes. Fichier à part (user://pantheon), écrit comme une sauvegarde (atomique,
## compressé, versionné). Borné : MAX_ENTRIES espèces, MAX_WORLDS mondes.

const SaveStore := preload("res://src/save/save_store.gd")

const DIR := "user://pantheon"
const SLOT := "pantheon"
const MAX_ENTRIES := 300
const MAX_WORLDS := 100
## Espèces non conscientes retenues par monde : les plus répandues à leur apogée.
const TOP_REIGNING := 6

const CLADE_LABELS := {
	"microbe": "micro-organisme", "algue": "algue", "éponge": "éponge", "arthropode": "arthropode",
	"mollusque": "mollusque", "poisson": "poisson", "plante": "plante", "insecte": "insecte",
	"amphibien": "amphibien", "reptile": "reptile", "synapside": "synapside", "dinosaure": "dinosaure",
	"ptérosaure": "ptérosaure", "oiseau": "oiseau", "mammifère": "mammifère", "primate": "primate",
}
const HABITAT_LABELS := {marine = "marin", amphibious = "amphibie", land = "terrestre"}

## [{key, name, description, clade, traits, sapient, created_by_god, reason, world_name,
##   world_index, born_year, extinct_year, peak_regions}]
var entries: Array[Dictionary] = []
## [{index, name, seed, params, ended_year, species_total}]
var worlds: Array[Dictionary] = []
## Vies vécues (une par monde, réincarnations comprises).
var lives := 0
var dir := DIR


func _init(p_dir := DIR) -> void:
	dir = p_dir


func load_from_disk() -> bool:
	var res := SaveStore.load_slot(SLOT, dir)
	if res.error != SaveStore.ERR_NONE:
		return false
	var p: Dictionary = res.payload
	entries.assign(p.get("entries", []))
	worlds.assign(p.get("worlds", []))
	lives = int(p.get("lives", worlds.size()))
	return true


func save_to_disk() -> String:
	return SaveStore.save_slot(SLOT, {entries = entries, worlds = worlds, lives = lives},
		{entries = entries.size(), worlds = worlds.size()}, dir)


func has_key(key: String) -> bool:
	for e in entries:
		if e.key == key:
			return true
	return false


## Retient les espèces marquantes du monde `world` : les peuples conscients, celles que Dieu a
## créées (`created` : ids), et les TOP_REIGNING plus répandues à leur apogée (`peaks` : id ->
## régions). `info` : {world_name, world_index}. Renvoie les entrées ajoutées.
func harvest(world: RefCounted, info: Dictionary, peaks: Dictionary, created: Dictionary) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	var reigning := []
	for id in world.species:
		var sp: Dictionary = world.species[id]
		if sp.sapient:
			added.append_array(_add(world, int(id), info, peaks, created, "conscience"))
		elif created.has(int(id)):
			added.append_array(_add(world, int(id), info, peaks, created, "création"))
		else:
			reigning.append([int(peaks.get(int(id), int(sp.get("regions", 0)))), int(id)])
	reigning.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	for i in mini(TOP_REIGNING, reigning.size()):
		if reigning[i][0] > 0:
			added.append_array(_add(world, reigning[i][1], info, peaks, created, "règne"))
	_trim()
	return added


func _add(world: RefCounted, id: int, info: Dictionary, peaks: Dictionary, created: Dictionary, reason: String) -> Array[Dictionary]:
	var key := "%d:%d" % [int(info.get("world_index", 0)), id]
	if has_key(key):
		return []
	var sp: Dictionary = world.species[id]
	var traits: Dictionary = sp.get("traits", {}).duplicate(true)
	var e := {
		key = key, name = String(sp.name), description = describe(sp), clade = String(sp.get("clade", traits.get("clade", ""))),
		traits = traits, sapient = bool(sp.sapient), created_by_god = created.has(id), reason = reason,
		world_name = String(info.get("world_name", "")), world_index = int(info.get("world_index", 0)),
		born_year = float(sp.get("born_year", 0.0)), extinct_year = float(sp.get("extinct_year", NAN)),
		peak_regions = int(peaks.get(id, sp.get("regions", 0))),
	}
	entries.append(e)
	return [e]


## Description d'une espèce : celle de la simulation si elle existe, sinon composée d'après ses traits.
static func describe(sp: Dictionary) -> String:
	if String(sp.get("description", "")) != "":
		return String(sp.description)
	var t: Dictionary = sp.get("traits", {})
	var clade := String(CLADE_LABELS.get(String(t.get("clade", sp.get("clade", ""))), t.get("clade", "lignée")))
	var size := float(t.get("size", 0.0))
	var size_text := "minuscule" if size < 0.05 else ("petit" if size < 0.25 else ("de taille moyenne" if size < 0.55 else ("grand" if size < 0.8 else "colossal")))
	var diet := String(t.get("diet", ""))
	var habitat := String(HABITAT_LABELS.get(String(t.get("habitat", "")), ""))
	var parts := ["%s %s" % [clade.capitalize(), size_text]]
	if habitat != "":
		parts.append(habitat)
	if diet != "":
		parts.append(diet)
	var text := ", ".join(parts) + "."
	if bool(sp.get("sapient", false)):
		text += " Un peuple conscient."
	elif float(t.get("intelligence", 0.0)) >= 0.5:
		text += " Une intelligence vive."
	return text


## Enregistre un monde achevé (ou quitté par réincarnation).
func record_world(info: Dictionary) -> void:
	worlds.append(info.duplicate(true))
	while worlds.size() > MAX_WORLDS:
		worlds.pop_front()


## Borne le Panthéon : on retire d'abord les espèces de règne des mondes les plus anciens, jamais
## les peuples conscients ni les créations tant qu'il reste autre chose.
func _trim() -> void:
	while entries.size() > MAX_ENTRIES:
		var victim := 0
		for i in entries.size():
			var e: Dictionary = entries[i]
			if e.reason == "règne":
				victim = i
				break
		entries.remove_at(victim)


## Action de semence « façonnée » qui ressème une espèce du Panthéon sur `region`.
static func reseed_action(entry: Dictionary, region: Vector2i, radius := 4) -> Dictionary:
	return {
		type = "spawn_species", kind = "shaped", region = region, species_id = -1, radius = radius,
		traits = entry.get("traits", {}).duplicate(true), name = String(entry.get("name", "")), shaped = true,
		from_pantheon = String(entry.get("key", "")),
	}
