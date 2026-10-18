extends RefCounted
## Chaîne causale : journal borné des événements et file des conséquences différées.
##
## Chaque événement porte un `id` unique et un `cause_id` (-1 = la nature, sans cause divine).
## Les actions divines sont épinglées : elles survivent à la purge du journal, si bien qu'une
## chaîne causale remonte toujours jusqu'au geste de Dieu qui l'a déclenchée.

const MAX_HISTORY := 4096
const TRIM_BATCH := 512
const MAX_CHAIN := 512

var next_id := 1
## Événements en ordre chronologique (borné à MAX_HISTORY).
var history: Array[Dictionary] = []
var _by_id := {}
var _pinned := {}
## Conséquences différées : {year, kind, cause_id, region, species_id, chance, data}, triées par année.
var scheduled: Array[Dictionary] = []


func make_event(year: float, type: String, region: Vector2i, species_id: int, summary: String, cause_id: int) -> Dictionary:
	var ev := {
		year = year, type = type, region = region, species_id = species_id,
		summary = summary, cause_id = cause_id, id = next_id,
	}
	next_id += 1
	_record(ev)
	return ev


## Une action divine : racine de chaîne causale, jamais purgée.
func make_root(year: float, type: String, region: Vector2i, species_id: int, summary: String) -> Dictionary:
	var ev := make_event(year, type, region, species_id, summary, -1)
	_pinned[ev.id] = ev
	return ev


func _record(ev: Dictionary) -> void:
	history.append(ev)
	_by_id[ev.id] = ev
	if history.size() > MAX_HISTORY:
		for i in TRIM_BATCH:
			var old: Dictionary = history[i]
			if not _pinned.has(old.id):
				_by_id.erase(old.id)
		history = history.slice(TRIM_BATCH)


func get_event(id: int) -> Dictionary:
	return _by_id.get(id, _pinned.get(id, {}))


## Remonte la chaîne depuis `event_id` : [événement, sa cause, la cause de sa cause, ...].
## S'arrête à une racine (cause_id = -1) ou à un maillon purgé du journal.
func chain(event_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	var id := event_id
	while id > 0 and not seen.has(id) and out.size() < MAX_CHAIN:
		seen[id] = true
		var ev := get_event(id)
		if ev.is_empty():
			break
		out.append(ev)
		id = ev.cause_id
	return out


func schedule(year: float, kind: String, cause_id: int, region: Vector2i, species_id: int, chance := 1.0, data := {}) -> void:
	var entry := {year = year, kind = kind, cause_id = cause_id, region = region, species_id = species_id, chance = chance, data = data}
	var i := scheduled.size()
	while i > 0 and float(scheduled[i - 1].year) > year:
		i -= 1
	scheduled.insert(i, entry)


## Retire et renvoie les conséquences arrivées à échéance.
func pop_due(year: float) -> Array[Dictionary]:
	var due: Array[Dictionary] = []
	while not scheduled.is_empty() and float(scheduled[0].year) <= year:
		due.append(scheduled.pop_front())
	return due


func copy() -> RefCounted:
	var c: RefCounted = get_script().new()
	c.next_id = next_id
	c.history = history.duplicate(true)
	c.scheduled = scheduled.duplicate(true)
	# Reconstruit les index sur les copies (et non sur les dictionnaires d'origine).
	for ev in c.history:
		c._by_id[ev.id] = ev
	for id in _pinned:
		c._pinned[id] = c._by_id.get(id, _pinned[id].duplicate(true))
	return c
