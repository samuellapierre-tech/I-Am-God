extends RefCounted
## Adaptateurs du sérialiseur, par classe (repérée par la fin du chemin de son script) :
## - SKIP : champs à ne jamais sauver (références partagées reconstruites, mesures de temps) ;
## - construction : arguments de _init passés par nom (préfixe « p_ » accepté), valeurs prises dans
##   les champs sauvés, surcharges (ex. ne pas regénérer la planète) ;
## - post_load : reconstruction de ce qui n'est pas sauvé ; un objet peut aussi exposer post_load().
## Tout le reste est générique (src/save/serializer.gd).

const SKIP := {
	"world_sim.gd": ["last_step_usec", "last_substeps"],
	"ecosystem.gd": ["g_pop", "g_tech", "g_dom", "g_temp", "g_base_temp", "g_elev", "g_moist", "g_biome"],
	"causality.gd": ["_by_id"],
}

## Arguments imposés à la construction (le reste vient des champs sauvés ou des valeurs par défaut).
const CONSTRUCT := {
	"world_sim.gd": {generate = false},
}


static func _key(path: String) -> String:
	return path.get_file()


static func skip_fields(path: String) -> Array:
	return SKIP.get(_key(path), [])


## Construit une instance de `script` : chaque argument de _init est pris, par nom, dans les
## surcharges de la classe puis dans les champs sauvés (décodés), sinon sa valeur par défaut.
static func construct(script: Script, fields: Dictionary, decoder: Object) -> Object:
	var forced: Dictionary = CONSTRUCT.get(_key(script.resource_path), {})
	var info := {}
	for m in script.get_script_method_list():
		if m.name == "_init":
			info = m
			break
	if info.is_empty():
		return script.new()
	var args := []
	var defaults: Array = info.get("default_args", [])
	var n: int = info.args.size()
	var first_default := n - defaults.size()
	for i in n:
		var name := String(info.args[i].name).trim_prefix("p_")
		if forced.has(name):
			args.append(forced[name])
		elif fields.has(name):
			args.append(decoder.value(fields[name]))
		elif i >= first_default:
			args.append(defaults[i - first_default])
		else:
			return null
	return script.new.callv(args)


## Reconstruit ce qui n'est pas sauvé, puis laisse l'objet compléter (post_load()).
static func post_load(o: Object) -> void:
	var path: String = o.get_script().resource_path if o.get_script() != null else ""
	match _key(path):
		"world_sim.gd":
			var eco: Object = o.get("_eco")
			if eco != null and eco.has_method("bind_grids"):
				eco.bind_grids(o)
		"causality.gd":
			_rebuild_causality(o)
	if o.has_method("post_load"):
		o.post_load()


## Index du journal causal : _by_id pointe vers les événements de l'historique ; les racines
## épinglées partagent le même dictionnaire que l'historique tant qu'il les contient.
static func _rebuild_causality(c: Object) -> void:
	var by_id := {}
	for ev in c.get("history"):
		by_id[ev.id] = ev
	c.set("_by_id", by_id)
	var pinned: Dictionary = c.get("_pinned")
	for id in pinned.keys():
		if by_id.has(id):
			pinned[id] = by_id[id]
		else:
			# Racine sortie de l'historique : le journal la garde indexée (jamais purgée).
			by_id[id] = pinned[id]
