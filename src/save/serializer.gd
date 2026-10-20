extends RefCounted
## Sérialiseur générique d'un graphe d'objets GDScript (WorldSim, Ecosystem, Causality, ParcelSim…).
##
## - Lit par réflexion toutes les variables de script de chaque objet : un champ ajouté plus tard est
##   sauvé sans rien changer ici, un champ disparu est ignoré au chargement, un champ nouveau garde sa
##   valeur par défaut (tolérance aux versions).
## - Les objets sont rangés dans une table (identité préservée : la parcelle et GameState pointent
##   vers le même monde). Les valeurs Godot (tableaux compacts, vecteurs, NaN, ±INF…) sont gardées
##   telles quelles : le tout passe ensuite par var_to_bytes.
## - Adaptateurs par classe (src/save/adapters.gd) : champs à ne pas sauver (références partagées,
##   mesures de temps), arguments de construction, reconstruction après chargement.
## - RandomNumberGenerator : graine et état exacts (déterminisme strict).
##
## Format : {objects: [{cls: chemin du script, f: {champ: valeur encodée}}], root: valeur encodée}.
## Référence d'objet : {"\u0001o": indice}. Objet non sérialisable (Thread, Mutex, nœud…) :
## {"\u0001skip": true}, et le champ garde sa valeur à la construction.

const Adapters := preload("res://src/save/adapters.gd")

const REF := "\u0001o"
const RNG := "\u0001rng"
const SKIP := "\u0001skip"


# =============================================================================================
# Encodage
# =============================================================================================

class Encoder:
	var objects: Array = []
	var ids := {}

	func value(v: Variant) -> Variant:
		match typeof(v):
			TYPE_OBJECT:
				return object(v)
			TYPE_DICTIONARY:
				var d := {}
				for k in v:
					if typeof(k) == TYPE_OBJECT:
						continue
					d[k] = value(v[k])
				return d
			TYPE_ARRAY:
				# Tableaux typés de valeurs simples : tels quels (aucun objet dedans).
				var a: Array = v
				if a.is_typed() and a.get_typed_builtin() != TYPE_OBJECT \
						and a.get_typed_builtin() != TYPE_DICTIONARY and a.get_typed_builtin() != TYPE_ARRAY:
					return a.duplicate()
				var out := []
				out.resize(a.size())
				for i in a.size():
					out[i] = value(a[i])
				return out
			TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
				return {SKIP: true}
		return v

	func object(o: Object) -> Variant:
		if o == null or not is_instance_valid(o):
			return null
		if o is RandomNumberGenerator:
			return {RNG: [o.seed, o.state]}
		var script: Script = o.get_script()
		if script == null or o is Node or o is Resource or o is Thread or o is Mutex:
			return {SKIP: true}
		var key := o.get_instance_id()
		if ids.has(key):
			return {REF: ids[key]}
		var index := objects.size()
		ids[key] = index
		objects.append({})
		var path := script.resource_path
		var skip: Array = Adapters.skip_fields(path)
		var fields := {}
		for p in o.get_property_list():
			if not (int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE):
				continue
			var name: String = p.name
			if name in skip:
				continue
			fields[name] = value(o.get(name))
		objects[index] = {cls = path, f = fields}
		return {REF: index}


## Encode une racine (dictionnaire de valeurs et d'objets).
static func encode(root: Variant) -> Dictionary:
	var e := Encoder.new()
	var r: Variant = e.value(root)
	return {objects = e.objects, root = r}


## Encode un seul objet (mesures, comparaisons de déterminisme).
static func encode_object(o: Object) -> Dictionary:
	return encode({o = o})


# =============================================================================================
# Décodage
# =============================================================================================

class Decoder:
	var table: Array = []
	var built := {}
	## Objets à remplir en place au lieu d'en construire de nouveaux (indice -> objet vivant).
	var into := {}
	var errors: Array[String] = []

	func value(v: Variant) -> Variant:
		match typeof(v):
			TYPE_DICTIONARY:
				if v.has(REF):
					return object(int(v[REF]))
				if v.has(RNG):
					var rng := RandomNumberGenerator.new()
					rng.seed = int(v[RNG][0])
					rng.state = int(v[RNG][1])
					return rng
				if v.has(SKIP):
					return null
				var d := {}
				for k in v:
					d[k] = value(v[k])
				return d
			TYPE_ARRAY:
				var a: Array = v
				if a.is_typed():
					return a.duplicate()
				var out := []
				out.resize(a.size())
				for i in a.size():
					out[i] = value(a[i])
				return out
		return v

	func object(index: int) -> Object:
		if built.has(index):
			return built[index]
		if index < 0 or index >= table.size():
			errors.append("référence d'objet invalide %d" % index)
			return null
		var entry: Dictionary = table[index]
		var o: Object = into.get(index)
		if o == null:
			var script: Script = load(String(entry.cls)) if ResourceLoader.exists(String(entry.cls)) else null
			if script == null:
				errors.append("classe introuvable %s" % entry.cls)
				return null
			o = Adapters.construct(script, entry.f, self)
			if o == null:
				errors.append("construction impossible %s" % entry.cls)
				return null
		built[index] = o
		fill(o, entry.f)
		Adapters.post_load(o)
		return o

	## Remplit `o` avec les champs encodés : champs inconnus ignorés, types convertis au besoin,
	## tableaux typés réassignés, objets non sérialisables laissés tels quels.
	func fill(o: Object, fields: Dictionary) -> void:
		var known := {}
		for p in o.get_property_list():
			if int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
				known[p.name] = true
		for name in fields:
			if not known.has(name):
				continue
			var enc: Variant = fields[name]
			if typeof(enc) == TYPE_DICTIONARY and enc.has(SKIP):
				continue
			var cur: Variant = o.get(name)
			# Sous-objet vivant du même script (remplissage en place, ex. mémoire du narrateur).
			if typeof(enc) == TYPE_DICTIONARY and enc.has(REF) and typeof(cur) == TYPE_OBJECT and cur != null \
					and not built.has(int(enc[REF])) and not into.has(int(enc[REF])):
				var entry: Dictionary = table[int(enc[REF])] if int(enc[REF]) < table.size() else {}
				if cur.get_script() != null and cur.get_script().resource_path == String(entry.get("cls", "")):
					into[int(enc[REF])] = cur
			var v: Variant = value(enc)
			o.set(name, Decoder.conform(cur, v))

	## Adapte `v` au type du champ courant `cur` (tableaux typés, conversions numériques).
	static func conform(cur: Variant, v: Variant) -> Variant:
		if typeof(cur) == TYPE_ARRAY and typeof(v) == TYPE_ARRAY:
			var c: Array = cur
			if c.is_typed():
				var typed := c.duplicate()
				typed.clear()
				typed.assign(v)
				return typed
			return v
		if typeof(cur) == TYPE_DICTIONARY and typeof(v) == TYPE_DICTIONARY:
			var cd: Dictionary = cur
			if cd.is_typed():
				var typed := cd.duplicate()
				typed.clear()
				typed.assign(v)
				return typed
			return v
		if cur == null or typeof(v) == typeof(cur) or typeof(cur) == TYPE_OBJECT or v == null:
			return v
		if typeof(cur) in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_STRING, TYPE_STRING_NAME] \
				or typeof(cur) >= TYPE_PACKED_BYTE_ARRAY:
			return type_convert(v, typeof(cur))
		return v


## Décode une racine. {value, errors: Array[String]}. `into` : objets vivants à remplir en place,
## désignés par leur chemin dans la racine ({"narrator": objet} pour une racine {narrator: …}).
static func decode(data: Dictionary, into := {}) -> Dictionary:
	var d := Decoder.new()
	d.table = data.get("objects", [])
	var root: Variant = data.get("root")
	if typeof(root) == TYPE_DICTIONARY:
		for key in into:
			var enc: Variant = root.get(key)
			if typeof(enc) == TYPE_DICTIONARY and enc.has(REF):
				d.into[int(enc[REF])] = into[key]
	var v: Variant = d.value(root)
	return {value = v, errors = d.errors}


## Octets canoniques d'un objet (comparaison stricte : NaN compris), sans les champs volatils.
static func fingerprint(o: Object) -> PackedByteArray:
	return var_to_bytes(encode_object(o))
