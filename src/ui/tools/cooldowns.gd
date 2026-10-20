extends RefCounted
## Temps de recharge des outils (semences et pouvoirs), en secondes réelles. Pur et testable :
## ToolState le fait avancer à chaque image. Pas de budget : un outil rechargé est toujours libre.

## id -> secondes restantes (absent = prêt)
var _remaining := {}
## id -> durée de la dernière recharge (pour la jauge)
var _total := {}


## Démarre la recharge de `id` pour `seconds` (≤ 0 : rien à attendre).
func start(id: String, seconds: float) -> void:
	if seconds <= 0.0:
		_remaining.erase(id)
		_total.erase(id)
		return
	_remaining[id] = seconds
	_total[id] = seconds


## Avance toutes les recharges ; renvoie les ids redevenus prêts pendant ce pas.
func tick(delta: float) -> Array[String]:
	var done: Array[String] = []
	if delta <= 0.0:
		return done
	for id in _remaining.keys():
		var r: float = _remaining[id] - delta
		if r <= 0.0:
			_remaining.erase(id)
			_total.erase(id)
			done.append(String(id))
		else:
			_remaining[id] = r
	return done


func remaining(id: String) -> float:
	return float(_remaining.get(id, 0.0))


func is_ready(id: String) -> bool:
	return not _remaining.has(id)


## Part de la recharge encore à attendre (1 = vient de servir, 0 = prêt).
func ratio(id: String) -> float:
	var total := float(_total.get(id, 0.0))
	return clampf(remaining(id) / total, 0.0, 1.0) if total > 0.0 else 0.0


func active_ids() -> Array:
	return _remaining.keys()


func clear() -> void:
	_remaining.clear()
	_total.clear()


## « 12 s », « 1 min 05 » ; "" si prêt.
static func format_remaining(seconds: float) -> String:
	if seconds <= 0.0:
		return ""
	var s := int(ceilf(seconds))
	if s < 60:
		return "%d s" % s
	return "%d min %02d" % [s / 60, s % 60]
