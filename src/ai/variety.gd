extends RefCounted
## Variété sur la durée (docs/STRATEGIE.md §10) : sur des parties de dizaines d'heures, aucun texte ne
## doit revenir à l'identique à peu de lignes d'écart.
## - Mémoire anti-répétition BORNÉE : les `window` derniers textes dits (anneau + compteurs, O(1)).
## - Rotation des gabarits : pour chaque famille de gabarits, on essaie d'abord les moins récemment
##   utilisés (ordre départagé par le hasard, déterministe à graine égale).
## Partagée par le narrateur entre le fil, la parcelle, la narration du monde et l'adversaire. Quand
## tout ce qu'un générateur sait dire a été dit récemment, il se tait plutôt que de se répéter.

## Nombre de textes retenus : aucun texte identique à moins de `window` lignes d'écart.
var window := 200

var _ring: Array[String] = []
var _next := 0
var _counts := {}
var _clock := 0
## famille -> {indice de gabarit -> dernier usage}
var _last_use := {}


func _init(p_window := 200) -> void:
	window = maxi(1, p_window)


## Ce texte a-t-il été dit parmi les `window` derniers ?
func seen(text: String) -> bool:
	return _counts.has(_key(text))


## Retient un texte dit (le plus ancien sort de la mémoire si elle est pleine).
func remember(text: String) -> void:
	var k := _key(text)
	if k == "":
		return
	if _ring.size() < window:
		_ring.append(k)
	else:
		var old := _ring[_next]
		var c := int(_counts.get(old, 0)) - 1
		if c <= 0:
			_counts.erase(old)
		else:
			_counts[old] = c
		_ring[_next] = k
		_next = (_next + 1) % window
	_counts[k] = int(_counts.get(k, 0)) + 1


## Retient le texte s'il est neuf ; false s'il vient d'être dit (à ne pas répéter).
func accept(text: String) -> bool:
	if seen(text):
		return false
	remember(text)
	return true


func size() -> int:
	return _ring.size()


## Ordre dans lequel essayer les `n` gabarits d'une famille : les moins récemment utilisés d'abord.
func order(family: String, n: int, rng: RandomNumberGenerator) -> Array:
	var uses: Dictionary = _last_use.get(family, {})
	var idx := []
	for i in n:
		idx.append([int(uses.get(i, -1)), rng.randf(), i])
	idx.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return idx.map(func(e: Array) -> int: return e[2])


## Note l'usage d'un gabarit (pour la rotation).
func used(family: String, i: int) -> void:
	_clock += 1
	if not _last_use.has(family):
		_last_use[family] = {}
	_last_use[family][i] = _clock
	# Borne : on ne garde la rotation que pour un nombre raisonnable de familles.
	if _last_use.size() > 256:
		_last_use.erase(_last_use.keys()[0])


static func _key(text: String) -> String:
	return text.strip_edges()
