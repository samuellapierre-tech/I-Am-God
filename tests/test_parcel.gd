extends RefCounted
## Tests du contrat ParcelSim (src/sim/parcel_sim.gd) : champs présents, déterminisme, historique.
## Chaque test renvoie "" en cas de succès, sinon un message d'erreur.

const WorldSim := preload("res://src/sim/world_sim.gd")
const ParcelSim := preload("res://src/sim/parcel_sim.gd")

const CELL := Vector2i(70, 40)
const FAUNA_KEYS := ["species_id", "name", "count", "density", "trend", "role", "size"]


func _advance(sim: RefCounted, parcel: RefCounted, frames: int) -> void:
	for i in frames:
		parcel.update(sim.step(sim.ideal_step_years() * sim.max_substeps))


func test_contract_fields() -> String:
	var sim := WorldSim.new(7)
	var parcel := ParcelSim.new(sim, CELL)
	_advance(sim, parcel, 20)
	if not parcel.land_use in ParcelSim.LAND_USES:
		return "usage du sol inconnu : " + parcel.land_use
	if parcel.biome == "":
		return "biome vide"
	if not (is_finite(parcel.temperature_c) and is_finite(parcel.global_temperature_c)):
		return "température invalide"
	if parcel.fauna.size() > ParcelSim.MAX_FAUNA:
		return "trop d'espèces : %d" % parcel.fauna.size()
	for f in parcel.fauna:
		for key in FAUNA_KEYS:
			if not f.has(key):
				return "champ de faune manquant : " + key
		if f.count <= 0 or f.count > ParcelSim.MAX_VISIBLE:
			return "nombre d'individus hors bornes : %d" % f.count
		if not f.trend in [-1, 0, 1]:
			return "tendance invalide : %s" % str(f.trend)
	for s in parcel.structures:
		if s.pos.x < 0.0 or s.pos.x > 1.0 or s.pos.y < 0.0 or s.pos.y > 1.0:
			return "structure hors parcelle : %s" % str(s.pos)
	return ""


func test_history_grows_and_is_bounded() -> String:
	var sim := WorldSim.new(11)
	var parcel := ParcelSim.new(sim, CELL)
	_advance(sim, parcel, 30)
	if parcel.history.size() <= 1:
		return "historique vide"
	if parcel.history.size() > ParcelSim.HISTORY_SIZE:
		return "historique non borné"
	if parcel.history[-1].year < parcel.history[0].year:
		return "historique non chronologique"
	return ""


func test_deterministic() -> String:
	var a := WorldSim.new(42)
	var b := WorldSim.new(42)
	var pa := ParcelSim.new(a, CELL)
	var pb := ParcelSim.new(b, CELL)
	_advance(a, pa, 25)
	_advance(b, pb, 25)
	if pa.land_use != pb.land_use or str(pa.fauna) != str(pb.fauna) or str(pa.structures) != str(pb.structures):
		return "même graine, parcelles différentes"
	return ""
