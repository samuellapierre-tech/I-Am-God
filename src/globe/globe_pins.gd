extends RefCounted
## Lieux épinglés sur le globe (au plus MAX_PINS), gardés d'une session à l'autre par graine de monde
## dans user://globe_pins.cfg. Une épingle : {name: String, cell: Vector2i}.

const MAX_PINS := 16
const PATH := "user://globe_pins.cfg"

var pins: Array[Dictionary] = []
var seed_key := ""


## Ajoute une épingle ; une cellule déjà épinglée n'est pas dupliquée. Renvoie l'indice, ou -1.
func add(cell: Vector2i, pin_name: String) -> int:
	for i in pins.size():
		if pins[i].cell == cell:
			return i
	if pins.size() >= MAX_PINS:
		pins.pop_front()
	pins.append({name = pin_name, cell = cell})
	return pins.size() - 1


func remove(index: int) -> void:
	if index >= 0 and index < pins.size():
		pins.remove_at(index)


func cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for p in pins:
		out.append(p.cell)
	return out


func load_for(world_seed: int) -> void:
	seed_key = str(world_seed)
	pins.clear()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for entry in cfg.get_value("pins", seed_key, []):
		if entry is Dictionary and entry.get("cell") is Vector2i:
			pins.append({name = str(entry.get("name", "")), cell = entry.cell})


func save() -> void:
	if seed_key == "":
		return
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("pins", seed_key, pins.duplicate(true))
	cfg.save(PATH)
