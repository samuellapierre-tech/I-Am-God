extends RefCounted
## Arbre de la vie (src/life/phylogeny.gd) : construit depuis les événements de WorldSim, borné en
## mémoire, cohérent (pas de cycle, chaque parent existe ou est résumé), lisible par l'interface et
## par Ézéchiel. Chaque test renvoie "" en cas de succès, sinon un message d'erreur.

const WorldSim := preload("res://src/sim/world_sim.gd")
const Phylogeny := preload("res://src/life/phylogeny.gd")


func _count_tree(rows: Array) -> int:
	var n := 0
	var stack := rows.duplicate()
	while not stack.is_empty():
		var r: Dictionary = stack.pop_back()
		n += 1
		stack.append_array(r.children)
	return n


func _check_world(sim: RefCounted, tree: RefCounted) -> String:
	var err: String = tree.check()
	if err != "":
		return err
	for id in sim.get_alive_species():
		if not tree.has_species(id):
			return "espèce vivante %d (%s) absente de l'arbre" % [id, sim.species[id].name]
		if not tree.node(id).alive:
			return "espèce vivante %d marquée éteinte" % id
		var p := int(sim.species[id].parent)
		if p >= 0 and tree.parent_of(id) != p:
			return "parent de %d faux (%d au lieu de %d)" % [id, tree.parent_of(id), p]
	for id in tree.nodes:
		if sim.species.has(id) and not sim.species[id].alive and tree.node(id).alive:
			return "espèce éteinte %d vivante dans l'arbre" % id
	return ""


func test_phylogeny_follows_the_prologue() -> String:
	var sim := WorldSim.new(3, true, WorldSim.SCENARIO_PROLOGUE)
	var tree := Phylogeny.new()
	tree.sync(sim.species)
	var guard := 0
	while sim.year < -2.0e9 and guard < 4000:
		guard += 1
		var evs: Array[Dictionary] = sim.step(minf(sim.ideal_step_years() * 200.0, 2.0e7))
		tree.ingest(evs, sim.species)
	var err := _check_world(sim, tree)
	if err != "":
		return err
	var st: Dictionary = tree.stats()
	print("  prologue jusqu'à %.2f Ga : %s" % [sim.year / 1e9, str(st)])
	if int(st.nodes) < 10:
		return "trop peu d'espèces dans l'arbre"
	var rows: Array = tree.layout()
	if rows.size() != tree.nodes.size():
		return "layout incomplet (%d lignes pour %d nœuds)" % [rows.size(), tree.nodes.size()]
	if _count_tree(tree.to_tree()) != tree.nodes.size():
		return "to_tree incomplet"
	var alive: Array = sim.get_alive_species()
	var deepest := -1
	for id in alive:
		if deepest < 0 or tree.ancestors(id).size() > tree.ancestors(deepest).size():
			deepest = id
	var text: String = tree.descent_text(deepest)
	print("  " + text)
	if not text.contains(" descend ") or not text.ends_with("."):
		return "filiation illisible : %s" % text
	return ""


func test_phylogeny_tracks_divine_gestures() -> String:
	var sim := WorldSim.new(5, true, WorldSim.SCENARIO_CRETACEOUS)
	var tree := Phylogeny.new()
	tree.sync(sim.species)
	tree.ingest(sim.step(2.0e5), sim.species)
	var alive: Array = sim.get_alive_species()
	var target: int = alive[0]
	tree.ingest(sim.apply_divine_action({type = "uplift", species_id = target, region = Vector2i(70, 40)}), sim.species)
	if tree.node(target).touched.is_empty():
		return "l'élévation divine n'est pas notée"
	var before: int = tree.nodes.size()
	tree.ingest(sim.apply_divine_action({type = "spawn_species", species_id = -1, region = Vector2i(120, 50)}), sim.species)
	var created := -1
	for id in tree.nodes:
		if tree.node(id).created:
			created = id
	if tree.nodes.size() <= before or created < 0:
		return "la création divine n'apparaît pas dans l'arbre"
	tree.ingest(sim.apply_divine_action({type = "extinct", species_id = target, region = Vector2i(70, 40)}), sim.species)
	if not sim.species[target].alive and tree.node(target).alive:
		return "l'extinction divine n'est pas notée"
	for i in 40:
		tree.ingest(sim.step(1.0e6), sim.species)
	var err := _check_world(sim, tree)
	if err != "":
		return err
	if tree.descent_text(created) == "":
		return "pas de texte pour la créature façonnée"
	return ""


func test_phylogeny_is_bounded_and_coherent() -> String:
	var tree := Phylogeny.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var alive := []
	var next_id := 0
	var total := 0
	var year := -3.0e9
	for i in 6:
		tree.add_species(next_id, -1, year, {name = "Racine %d" % i, seeded = i == 0})
		alive.append(next_id)
		next_id += 1
		total += 1
	for step in 30000:
		year += 1.0e5
		# Une planète garde quelques centaines d'espèces vivantes au plus (Ecosystem.MAXS).
		if (rng.randf() < 0.55 and alive.size() < 300) or alive.size() < 3:
			var parent: int = alive[rng.randi_range(0, alive.size() - 1)]
			tree.add_species(next_id, parent, year, {name = "Espèce %d" % next_id, clade = ["poisson", "reptile", "insecte"][next_id % 3]})
			alive.append(next_id)
			next_id += 1
			total += 1
		elif alive.size() > 3:
			var k := rng.randi_range(0, alive.size() - 1)
			tree.mark_extinct(alive[k], year)
			alive.remove_at(k)
		if step % 997 == 0:
			tree.mark_touched(alive[0], "bless", year)
		if tree.nodes.size() > Phylogeny.MAX_NODES:
			return "arbre non borné : %d nœuds" % tree.nodes.size()
	var err: String = tree.check()
	if err != "":
		return err
	var st: Dictionary = tree.stats()
	if int(st.nodes) + int(st.hidden) != total:
		return "comptes perdus : %d nœuds + %d résumés != %d espèces" % [st.nodes, st.hidden, total]
	for id in alive:
		if not tree.has_species(id):
			return "une espèce vivante a été résumée"
	if not tree.has_species(0):
		return "la lignée semée par le joueur a été résumée"
	# Un parent inconnu devient un ancêtre résumé, et l'arbre reste sans cycle.
	tree.add_species(999999, 888888, year, {name = "Orpheline"})
	if not tree.has_species(888888) or not tree.node(888888).ghost:
		return "parent inconnu non résumé"
	if tree.check() != "":
		return tree.check()
	print("  %d espèces : %s" % [total, str(st)])
	# Sauvegarde : aller-retour identique.
	var copy: RefCounted = Phylogeny.from_dict(tree.to_dict())
	if copy.check() != "" or copy.nodes.size() != tree.nodes.size() or copy.stats().hidden != tree.stats().hidden:
		return "aller-retour de sauvegarde incohérent"
	if copy.descent_text(alive[0]) != tree.descent_text(alive[0]):
		return "filiation différente après rechargement"
	return ""
