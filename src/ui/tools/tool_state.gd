extends Node
## Outil divin sélectionné (semence ou pouvoir, avec ses paramètres) et temps de recharge.
## Nœud partagé : ToolState.shared(get_tree()) renvoie /root/ToolState (créé au besoin). Il peut
## aussi être déclaré en autoload sous le nom « ToolState » ; shared() le retrouve alors.
## Utilisé par le HUD (palette de semences, barre des pouvoirs), le globe et la vue rapprochée :
##
##   var tools := ToolState.shared(get_tree())
##   var tool := tools.selected_tool()            # {} si rien n'est sélectionné
##   if tools.can_use(tool):
##       var action := tools.use(tool, cell)      # démarre la recharge, renvoie l'action
##       GameState.apply_divine_action(action)    # l'appelant applique
##
## Format d'un outil : {kind: "seed" | "power", id: String, params: Dictionary}
##   seed  : params {radius: int, traits: Dictionary}   (SeedCatalog)
##   power : params {radius: int, species_id: int}      (src/map/divine_powers.gd, -1 = dominante)
## Pas de budget : seulement une recharge par outil, en secondes réelles.

signal tool_changed(tool: Dictionary)
## Une recharge commence ou se termine.
signal cooldowns_changed
## Un outil vient de servir (action renvoyée à l'appelant).
signal tool_used(tool: Dictionary, action: Dictionary)

const Cooldowns := preload("res://src/ui/tools/cooldowns.gd")
const SeedCatalog := preload("res://src/ui/seeds/seed_catalog.gd")
const Powers := preload("res://src/map/divine_powers.gd")

const NODE_NAME := "ToolState"
## Recharge des pouvoirs (s), à défaut d'un champ `cooldown` dans le catalogue des pouvoirs.
const POWER_COOLDOWNS := {
	meteor = 90.0, extinct = 60.0, save = 30.0, bless = 20.0, plague = 45.0, uplift = 120.0,
	flood = 45.0, ice_age = 120.0, spawn_species = 60.0, volcano = 60.0, oxygenate = 45.0, soothe = 20.0,
}
const DEFAULT_POWER_COOLDOWN := 30.0

var cooldowns := Cooldowns.new()
var _tool: Dictionary = {}


## Le ToolState de l'arbre (autoload ou /root/ToolState), créé au premier appel.
static func shared(tree: SceneTree) -> Node:
	var root := tree.root
	var node := root.get_node_or_null(NODE_NAME)
	if node == null:
		node = (load("res://src/ui/tools/tool_state.gd") as Script).new()
		node.name = NODE_NAME
		root.add_child.call_deferred(node)
	return node


func _process(delta: float) -> void:
	if not cooldowns.tick(delta).is_empty():
		cooldowns_changed.emit()


# --- Sélection ---

## Copie de l'outil sélectionné ({} si aucun).
func selected_tool() -> Dictionary:
	return _tool.duplicate(true)


func has_tool() -> bool:
	return not _tool.is_empty()


func is_selected(kind: String, id: String) -> bool:
	return not _tool.is_empty() and _tool.kind == kind and _tool.id == id


func select(tool: Dictionary) -> void:
	var t := normalize(tool)
	if t == _tool:
		return
	_tool = t
	tool_changed.emit(selected_tool())


func select_seed(kind: String, traits: Dictionary = {}) -> void:
	var s := SeedCatalog.get_seed(kind)
	if s.is_empty():
		return
	select({kind = "seed", id = kind, params = {radius = int(s.radius),
		traits = traits if not traits.is_empty() else SeedCatalog.default_traits(kind)}})


func select_power(power_id: String, species_id: int = -1) -> void:
	var p := Powers.get_power(power_id)
	if p.is_empty():
		return
	select({kind = "power", id = power_id, params = {radius = int(p.radius), species_id = species_id}})


func clear() -> void:
	if _tool.is_empty():
		return
	_tool = {}
	tool_changed.emit({})


## Change un paramètre de l'outil sélectionné (rayon, traits, espèce visée…).
func set_param(key: String, value: Variant) -> void:
	if _tool.is_empty():
		return
	if key == "radius":
		var lo := SeedCatalog.MIN_RADIUS if _tool.kind == "seed" else Powers.MIN_RADIUS
		var hi := SeedCatalog.MAX_RADIUS if _tool.kind == "seed" else Powers.MAX_RADIUS
		value = clampi(int(value), lo, hi)
	if _tool.params.get(key) == value:
		return
	_tool.params[key] = value
	tool_changed.emit(selected_tool())


# --- Recharges ---

## Clé de recharge : « seed:spark », « power:meteor ».
static func key_of(tool: Dictionary) -> String:
	return "%s:%s" % [tool.get("kind", ""), tool.get("id", "")] if not tool.is_empty() else ""


## Durée de recharge de l'outil (s).
static func cooldown_of(tool: Dictionary) -> float:
	match str(tool.get("kind", "")):
		"seed":
			return float(SeedCatalog.get_seed(str(tool.get("id", ""))).get("cooldown", 0.0))
		"power":
			var p := Powers.get_power(str(tool.get("id", "")))
			if p.has("cooldown"):
				return float(p.cooldown)
			return float(POWER_COOLDOWNS.get(str(tool.get("id", "")), DEFAULT_POWER_COOLDOWN))
	return 0.0


func remaining(tool: Dictionary) -> float:
	return cooldowns.remaining(key_of(tool))


## 1 = vient de servir, 0 = prêt (pour dessiner la jauge sur le bouton).
func recharge_ratio(tool: Dictionary) -> float:
	return cooldowns.ratio(key_of(tool))


## L'outil est-il connu, valide et rechargé ? (outil sélectionné par défaut)
func can_use(tool: Dictionary = {}) -> bool:
	var t := normalize(tool if not tool.is_empty() else _tool)
	return not t.is_empty() and cooldowns.is_ready(key_of(t))


## Utilise l'outil sur `region` : démarre sa recharge et renvoie l'action à appliquer
## ({} si l'outil n'est pas prêt ou si l'action serait invalide).
func use(tool: Dictionary = {}, region := Vector2i(-1, -1)) -> Dictionary:
	var t := normalize(tool if not tool.is_empty() else _tool)
	if t.is_empty() or not cooldowns.is_ready(key_of(t)):
		return {}
	var action := build_action(t, region)
	if action.is_empty():
		return {}
	cooldowns.start(key_of(t), cooldown_of(t))
	cooldowns_changed.emit()
	tool_used.emit(t, action)
	return action


## Une action a été appliquée sans passer par use() (p. ex. clic traité ailleurs) : démarre la
## recharge de l'outil correspondant s'il était prêt. Renvoie l'outil reconnu ({} sinon).
func notify_applied(action: Dictionary) -> Dictionary:
	var t := tool_for_action(action)
	if t.is_empty() or not cooldowns.is_ready(key_of(t)):
		return t
	cooldowns.start(key_of(t), cooldown_of(t))
	cooldowns_changed.emit()
	return t


## Outil qui produit cette action ({kind, id}, {} si inconnu).
static func tool_for_action(action: Dictionary) -> Dictionary:
	var type := str(action.get("type", ""))
	if type == "seed":
		return normalize({kind = "seed", id = str(action.get("kind", ""))})
	return normalize({kind = "power", id = type})


## Action au format de GameState.apply_divine_action ({} si invalide).
static func build_action(tool: Dictionary, region: Vector2i) -> Dictionary:
	var params: Dictionary = tool.get("params", {})
	match str(tool.get("kind", "")):
		"seed":
			var a := SeedCatalog.make_action(str(tool.id), params.get("traits", {}), region,
				int(params.get("radius", 4)))
			return a if SeedCatalog.validate_action(a) == "" else {}
		"power":
			return Powers.make_action(str(tool.id), region, int(params.get("species_id", -1)),
				int(params.get("radius", 8)))
	return {}


## Outil complété (paramètres par défaut) ou {} s'il est inconnu.
static func normalize(tool: Dictionary) -> Dictionary:
	if tool.is_empty():
		return {}
	var kind := str(tool.get("kind", ""))
	var id := str(tool.get("id", ""))
	var params: Dictionary = (tool.get("params", {}) as Dictionary).duplicate(true) if tool.get("params") is Dictionary else {}
	match kind:
		"seed":
			var s := SeedCatalog.get_seed(id)
			if s.is_empty():
				return {}
			if not params.has("radius"):
				params.radius = int(s.radius)
			if not params.has("traits"):
				params.traits = SeedCatalog.default_traits(id)
		"power":
			var p := Powers.get_power(id)
			if p.is_empty():
				return {}
			if not params.has("radius"):
				params.radius = int(p.radius)
			if not params.has("species_id"):
				params.species_id = -1
		_:
			return {}
	return {kind = kind, id = id, params = params}
