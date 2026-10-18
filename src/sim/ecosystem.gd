extends RefCounted
## Écosystème régional multicoeur.
##
## La planète (256x128 cellules) est découpée en régions de RS x RS cellules (64x32 régions).
## Chaque région abrite jusqu'à K espèces (« niches ») avec une densité 0..1+. Une espèce marine
## vit de la part océanique de la région (r_sea, plateaux continentaux surtout), une espèce
## terrestre de ses terres (fertilité x ouverture des terres, fermées sans couche d'ozone), une
## espèce amphibie des deux. Les herbivores dépendent des producteurs de leur milieu quand la flore
## est explicite (prologue) ; sinon (scénario du Crétacé) la végétation est implicite.
## Un pas d'écosystème est un noyau WorkerThreadPool.add_group_task sur des bandes de lignées
## de régions : chaque bande lit le tampon courant (cur_*) et n'écrit que SES régions dans le
## tampon suivant (nxt_*), puis réécrit SES lignes de cellules dans les grilles fines publiques.
## Aucune écriture partagée => aucune course, et le résultat ne dépend pas de l'ordonnancement
## (aléa par hachage seed/pas/région, sommes par bande réduites dans un ordre fixe).
## Aucune allocation dans la boucle chaude : tout est préalloué en tableaux compacts.

const WorldGen := preload("res://src/sim/world_gen.gd")

const W := 256
const H := 128
const RS := 4
@warning_ignore("integer_division")
const RW := W / RS
@warning_ignore("integer_division")
const RH := H / RS
const NR := RW * RH
const K := 4
## Nombre maximal d'espèces vivantes simultanément (indices de table recyclés).
const MAXS := 128
const BANDS := 16
@warning_ignore("integer_division")
const ROWS_PER_BAND := RH / BANDS
const MAX_ALPHA := 0.7
const EXTINCT_EPS := 0.004

# --- Données régionales statiques ---
var r_land := PackedFloat32Array()   # part de terres émergées
var r_fert := PackedFloat32Array()   # fertilité moyenne des terres
var r_temp := PackedFloat32Array()   # température de base moyenne
var r_elev := PackedFloat32Array()   # altitude moyenne des terres
var r_sea := PackedFloat32Array()    # capacité marine (part d'océan, plateaux pondérés)
# --- Modificateurs régionaux (écrits par le thread principal entre deux pas) ---
var r_anom := PackedFloat32Array()   # anomalie thermique locale (volcans, impacts)
var r_bless := PackedFloat32Array()  # bonus de fertilité (bénédiction, limon)
# --- Double tampon des niches : indice de table d'espèce (-1 = vide) et densité ---
var cur_sp := PackedInt32Array()
var cur_pop := PackedFloat32Array()
var nxt_sp := PackedInt32Array()
var nxt_pop := PackedFloat32Array()
# --- Sorties régionales (chaque bande n'écrit que ses régions) ---
var r_dom := PackedInt32Array()      # indice de table de l'espèce dominante (hors espèces marines)
var r_mdom := PackedInt32Array()     # indice de table de l'espèce marine dominante
var r_dens := PackedFloat32Array()
var r_tech := PackedFloat32Array()
# --- Tables d'espèces indexées par indice de table (0..MAXS-1) ---
var t_alive := PackedInt32Array()
var t_id := PackedInt32Array()       # indice -> id public
var t_protect := PackedInt32Array()
var t_diet := PackedInt32Array()     # 0 herbivore, 1 omnivore, 2 carnivore, 3 autotrophe
var t_hab := PackedInt32Array()      # 0 marine, 1 amphibie, 2 terrestre
var t_cx := PackedFloat32Array()     # complexité 0..6
var t_anaer := PackedInt32Array()    # 1 = anaérobie (l'oxygène l'empoisonne)
var t_oxf := PackedFloat32Array()    # facteur de capacité dû à l'oxygène (set_oxygen)
var t_topt := PackedFloat32Array()
var t_tol := PackedFloat32Array()
var t_comp := PackedFloat32Array()
var t_icomp := PackedFloat32Array()
var t_growth := PackedFloat32Array() # taux (1/an)
var t_disp := PackedFloat32Array()   # taux (1/an)
var t_alpha := PackedFloat32Array()  # dérivés du pas courant
var t_mig := PackedFloat32Array()
var t_vis := PackedFloat32Array()    # poids pour désigner l'espèce dominante
var t_tech := PackedFloat32Array()   # 0..1
var t_capmul := PackedFloat32Array()
var t_ov := PackedFloat32Array()     # MAXS x MAXS chevauchement de niche
# --- Statistiques par bande, réduites ensuite dans un ordre fixe ---
var b_pop := PackedFloat32Array()
var b_cnt := PackedInt32Array()
var b_sample := PackedInt32Array()
var stat_pop := 0.0
var stat_cnt := 0
var stat_sample := -1
# --- Grilles fines (références partagées avec WorldSim) ---
var g_pop: PackedFloat32Array
var g_tech: PackedFloat32Array
var g_dom: PackedInt32Array
var g_temp: PackedFloat32Array
var g_base_temp: PackedFloat32Array
var g_elev: PackedFloat32Array
var g_moist: PackedFloat32Array
var g_biome: PackedByteArray
var g_detail := PackedFloat32Array() # variation intra-régionale 0.55..1 (relief)
var band_cells: Array[PackedInt32Array] = []
# --- Indices de table libres ---
var free_idx: Array[int] = []
var pending_free: Array[int] = []
var next_idx := 0
## false = exécute les bandes en série (mesures comparatives).
var threaded := true
## 1 = les herbivores ont besoin de producteurs (prologue) ; 0 = végétation implicite.
var explicit_flora := 0
## 0..1 : les terres sont-elles habitables (couche d'ozone) ? Écrit par set_oxygen().
var land_open := 1.0

# Paramètres du pas courant (lus par les tâches).
var _step_hash := 0
var _goff := 0.0
var _temp_dirty := true
var _biome_dirty := false


func _init() -> void:
	for a in [r_land, r_fert, r_temp, r_elev, r_sea, r_anom, r_bless, r_dens, r_tech]:
		a.resize(NR)
	for a in [r_dom, r_mdom]:
		a.resize(NR)
		a.fill(-1)
	for a in [cur_sp, nxt_sp]:
		a.resize(NR * K)
		a.fill(-1)
	cur_pop.resize(NR * K)
	nxt_pop.resize(NR * K)
	for a in [t_alive, t_id, t_protect, t_diet, t_hab, t_anaer]:
		a.resize(MAXS)
	t_hab.fill(2)
	for a in [t_topt, t_tol, t_comp, t_icomp, t_growth, t_disp, t_alpha, t_mig, t_vis, t_tech, t_capmul, t_cx, t_oxf]:
		a.resize(MAXS)
	t_cx.fill(6.0)
	t_oxf.fill(1.0)
	t_tol.fill(0.2)
	t_comp.fill(1.0)
	t_icomp.fill(1.0)
	t_ov.resize(MAXS * MAXS)
	b_pop.resize(BANDS * MAXS)
	b_cnt.resize(BANDS * MAXS)
	b_sample.resize(BANDS * MAXS)


## Branche les grilles fines de la simulation et calcule les agrégats régionaux.
func bind_grids(sim: RefCounted) -> void:
	g_pop = sim.population
	g_tech = sim.tech
	g_dom = sim.dominant_species
	g_temp = sim.temperature
	g_base_temp = sim._base_temp
	g_elev = sim.elevation
	g_moist = sim.moisture
	g_biome = sim.biome


func build_static() -> void:
	g_detail.resize(W * H)
	band_cells.clear()
	for b in BANDS:
		band_cells.append(PackedInt32Array())
	var land_cnt := PackedInt32Array()
	land_cnt.resize(NR)
	r_land.fill(0.0)
	r_fert.fill(0.0)
	r_temp.fill(0.0)
	r_elev.fill(0.0)
	r_sea.fill(0.0)
	for y in H:
		for x in W:
			var i := y * W + x
			@warning_ignore("integer_division")
			var r := (y / RS) * RW + x / RS
			var e := g_elev[i]
			r_temp[r] += g_base_temp[i]
			if e < 0.0:
				# Les mers peu profondes (plateaux) sont bien plus productives que les abysses.
				r_sea[r] += (0.9 if e > -0.35 else 0.25) / float(RS * RS)
			else:
				land_cnt[r] += 1
				r_fert[r] += WorldGen.BIOME_FERTILITY[g_biome[i]]
				r_elev[r] += e
				g_detail[i] = 1.0 - clampf(e, 0.0, 1.0) * 0.45
				@warning_ignore("integer_division")
				band_cells[(y / RS) / ROWS_PER_BAND].append(i)
	for r in NR:
		r_temp[r] /= float(RS * RS)
		var c := land_cnt[r]
		r_land[r] = float(c) / float(RS * RS)
		if c > 0:
			r_fert[r] /= float(c)
			r_elev[r] /= float(c)


func region_of_cell(cell: Vector2i) -> int:
	var x := posmod(cell.x, W)
	var y := clampi(cell.y, 0, H - 1)
	@warning_ignore("integer_division")
	return (y / RS) * RW + x / RS


func region_center_cell(r: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i((r % RW) * RS + RS / 2, (r / RW) * RS + RS / 2)


## Régions dans un disque (rayon en régions), la carte se raccordant en x.
func regions_in_radius(r: int, rad: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var cx := r % RW
	@warning_ignore("integer_division")
	var cy := r / RW
	for dy in range(-rad, rad + 1):
		var y := cy + dy
		if y < 0 or y >= RH:
			continue
		for dx in range(-rad, rad + 1):
			if dx * dx + dy * dy > rad * rad + rad:
				continue
			out.append(y * RW + posmod(cx + dx, RW))
	return out


func region_temperature(r: int, goff: float) -> float:
	return r_temp[r] + goff + r_anom[r]


func suitability(idx: int, r: int, goff: float) -> float:
	var d := (region_temperature(r, goff) - t_topt[idx]) / t_tol[idx]
	return maxf(0.0, 1.0 - d * d)


## Capacité de base (avant climat) d'une région pour une espèce, selon son milieu.
func habitat_base(idx: int, r: int) -> float:
	var sea := r_sea[r] * (1.0 + r_bless[r])
	var land := r_land[r] * (r_fert[r] + r_bless[r]) * land_open
	match t_hab[idx]:
		0:
			return sea
		1:
			return 0.6 * sea + 0.6 * land
	return land


## La région peut-elle accueillir ce milieu ?
func region_fits(idx: int, r: int) -> bool:
	match t_hab[idx]:
		0:
			return r_sea[r] > 0.0
		2:
			return r_land[r] > 0.0
	return r_land[r] > 0.0 or r_sea[r] > 0.0


## Facteurs de capacité dus à l'oxygène (thread principal, entre deux pas) : la vie complexe en
## exige, il empoisonne les anaérobies, et sans couche d'ozone les terres restent stériles.
## `complex_room` (0..1) : part de capacité laissée à la vie complexe (complexité ≥ 3) par la
## chaleur du Soleil vieillissant.
func set_oxygen(oxygen: float, needs: Array[float], complex_room := 1.0) -> void:
	land_open = smoothstep(0.08, 0.3, oxygen) if explicit_flora == 1 else 1.0
	for s in MAXS:
		if t_alive[s] == 0:
			continue
		var c := clampi(int(t_cx[s]), 0, needs.size() - 1)
		var need: float = needs[c]
		var f := 1.0 if need <= 0.0 else smoothstep(0.4 * need, need, oxygen)
		if t_anaer[s] == 1:
			f *= 1.0 - clampf(oxygen / 0.05, 0.0, 0.9)
		if t_cx[s] >= 3.0:
			f *= complex_room
		t_oxf[s] = maxf(f, 0.0)


# ---------------------------------------------------------------------------------------------
# Indices de table
# ---------------------------------------------------------------------------------------------

func alloc_index() -> int:
	if not free_idx.is_empty():
		return free_idx.pop_back()
	if next_idx < MAXS:
		next_idx += 1
		return next_idx - 1
	return -1


func capacity_left() -> int:
	return free_idx.size() + (MAXS - next_idx)


## Un indice libéré n'est recyclé qu'après un passage du noyau (qui purge les niches mortes).
func release_index(idx: int) -> void:
	t_alive[idx] = 0
	pending_free.append(idx)


func flush_free() -> void:
	free_idx.append_array(pending_free)
	pending_free.clear()


# ---------------------------------------------------------------------------------------------
# Pas multicoeur
# ---------------------------------------------------------------------------------------------

## Prépare les taux dépendant du pas (thread principal, O(MAXS)).
func prepare(dt: float, mig_mult: float) -> void:
	for s in MAXS:
		if t_alive[s] == 0:
			continue
		t_alpha[s] = minf(MAX_ALPHA, 1.0 - exp(-dt * t_growth[s]))
		t_mig[s] = 1.0 - exp(-dt * t_disp[s] * mig_mult)


func run(step_index: int, seed_hash: int, goff: float, temp_dirty: bool, biome_dirty: bool) -> void:
	_step_hash = (step_index * 73856093 + seed_hash) & 0x7fffffff
	_goff = goff
	_temp_dirty = temp_dirty
	_biome_dirty = biome_dirty
	# Garantit que chaque grille écrite par les tâches nous appartient en propre : si un autre
	# système en détient une copie (copy-on-write), la copie se fait ici, sur un seul thread.
	g_pop.set(0, g_pop[0])
	g_tech.set(0, g_tech[0])
	g_dom.set(0, g_dom[0])
	g_temp.set(0, g_temp[0])
	g_biome.set(0, g_biome[0])
	# Idem pour les tampons internes : duplicate() (fork) partage les données jusqu'à la première
	# écriture, et deux threads déclenchant la même copie en parallèle corromprait le tableau.
	nxt_sp.set(0, nxt_sp[0])
	nxt_pop.set(0, nxt_pop[0])
	r_dom.set(0, r_dom[0])
	r_mdom.set(0, r_mdom[0])
	r_dens.set(0, r_dens[0])
	r_tech.set(0, r_tech[0])
	b_pop.set(0, b_pop[0])
	b_cnt.set(0, b_cnt[0])
	b_sample.set(0, b_sample[0])
	if threaded:
		var id := WorkerThreadPool.add_group_task(_band_task, BANDS, -1, true, "WorldSim.ecosystem")
		WorkerThreadPool.wait_for_group_task_completion(id)
	else:
		for b in BANDS:
			_band_task(b)
	var ts := cur_sp
	cur_sp = nxt_sp
	nxt_sp = ts
	var tp := cur_pop
	cur_pop = nxt_pop
	nxt_pop = tp


func _band_task(b: int) -> void:
	var sp_in := cur_sp
	var pop_in := cur_pop
	var sp_out := nxt_sp
	var pop_out := nxt_pop
	var land := r_land
	var fert := r_fert
	var rtemp := r_temp
	var anom := r_anom
	var bless := r_bless
	var alive := t_alive
	var prot := t_protect
	var diet := t_diet
	var hab := t_hab
	var oxf := t_oxf
	var rsea := r_sea
	var mdom := r_mdom
	var needs_prod := explicit_flora == 1
	var lopen := land_open
	var topt := t_topt
	var tol := t_tol
	var comp := t_comp
	var icomp := t_icomp
	var alpha := t_alpha
	var mig := t_mig
	var vis := t_vis
	var ttech := t_tech
	var capmul := t_capmul
	var ov := t_ov
	var dom := r_dom
	var dens := r_dens
	var rtech := r_tech
	var bpop := b_pop
	var bcnt := b_cnt
	var bsample := b_sample
	var goff := _goff
	var step_hash := _step_hash
	var bo := b * MAXS
	for s in MAXS:
		bpop[bo + s] = 0.0
		bcnt[bo + s] = 0
		bsample[bo + s] = -1

	var ry0 := b * ROWS_PER_BAND
	for ry in range(ry0, ry0 + ROWS_PER_BAND):
		for rx in RW:
			var r := ry * RW + rx
			var lf := land[r]
			var sea_b := rsea[r] * (1.0 + bless[r])
			if lf <= 0.0 and sea_b <= 0.0:
				dom[r] = -1
				mdom[r] = -1
				dens[r] = 0.0
				rtech[r] = 0.0
				continue
			var base := r * K
			var temp := rtemp[r] + goff + anom[r]
			var land_b := lf * (fert[r] + bless[r]) * lopen
			var prey_sea := 0.0
			var prey_land := 0.0
			var prod_sea := 0.0
			var prod_land := 0.0
			for k in K:
				var s := sp_in[base + k]
				if s < 0:
					continue
				var p0 := pop_in[base + k]
				var h0 := hab[s]
				if diet[s] < 2:
					if h0 != 2:
						prey_sea += p0
					if h0 != 0:
						prey_land += p0
				elif diet[s] == 3:
					if h0 != 2:
						prod_sea += p0
					if h0 != 0:
						prod_land += p0

			# 1) Dynamique locale : retour vers l'équilibre de Lotka-Volterra (pas stable quel que soit dt).
			for k in K:
				var s := sp_in[base + k]
				if s < 0 or alive[s] == 0:
					sp_out[base + k] = -1
					pop_out[base + k] = 0.0
					continue
				var p := pop_in[base + k]
				var d := (temp - topt[s]) / tol[s]
				var hs := hab[s]
				var hbase := sea_b if hs == 0 else (land_b if hs == 2 else 0.6 * (sea_b + land_b))
				var cap := hbase * maxf(0.0, 1.0 - d * d) * capmul[s] * oxf[s]
				if diet[s] == 2:
					var prey := prey_sea if hs == 0 else (prey_land if hs == 2 else maxf(prey_sea, prey_land))
					cap *= minf(1.0, 0.15 + prey * 1.5)
				elif diet[s] == 0 and needs_prod:
					var prod := prod_sea if hs == 0 else (prod_land if hs == 2 else maxf(prod_sea, prod_land))
					cap *= minf(1.0, 0.1 + prod * 2.0)
				var press := 0.0
				var row := s * MAXS
				for j in K:
					if j != k:
						var sj := sp_in[base + j]
						if sj >= 0:
							press += ov[row + sj] * pop_in[base + j] * comp[sj]
				var target := maxf(0.0, cap - press * icomp[s])
				var np := p + (target - p) * alpha[s]
				if np < EXTINCT_EPS:
					if prot[s] == 1 and p > 0.0:
						np = EXTINCT_EPS * 2.0
					else:
						sp_out[base + k] = -1
						pop_out[base + k] = 0.0
						continue
				sp_out[base + k] = s
				pop_out[base + k] = np

			# 2) Colonisation depuis un voisin tiré par hachage (lecture du tampon courant uniquement).
			var h := (step_hash + r * 19349663) & 0x7fffffff
			h = (((h >> 13) ^ h) * 1274126177) & 0x7fffffff
			h = (h >> 16) ^ h
			var nx := rx
			var ny := ry
			var dir := h & 3
			if dir == 0:
				nx = (rx + 1) % RW
			elif dir == 1:
				nx = (rx + RW - 1) % RW
			elif dir == 2:
				ny = ry + 1
			else:
				ny = ry - 1
			if ny >= 0 and ny < RH:
				var nb := (ny * RW + nx) * K
				var roll := float((h >> 2) & 0xffff) / 65535.0
				for kk in K:
					var s := sp_in[nb + kk]
					if s < 0 or alive[s] == 0 or roll >= mig[s]:
						continue
					var src := pop_in[nb + kk]
					if src < 0.03:
						continue
					var present := false
					var empty := -1
					var weakest := -1
					var wval := 1e9
					for k in K:
						var so := sp_out[base + k]
						if so == s:
							present = true
							break
						if so < 0:
							if empty < 0:
								empty = k
						else:
							var v := pop_out[base + k] * comp[so]
							if v < wval:
								wval = v
								weakest = k
					if present:
						continue
					var d := (temp - topt[s]) / tol[s]
					var suit := 1.0 - d * d
					if suit < 0.1:
						continue
					var hs := hab[s]
					var hbase := sea_b if hs == 0 else (land_b if hs == 2 else 0.6 * (sea_b + land_b))
					var potential := hbase * suit * capmul[s] * oxf[s]
					if potential <= 0.001:
						continue
					var seed_pop := minf(src * 0.5, potential * 0.5)
					if empty < 0 and lf > 0.0 and sea_b > 0.0:
						# Rivage : la mer et la terre se partagent les niches au prorata de leur
						# surface ; un milieu qui déborde de sa part cède sa niche la plus faible.
						var land_side := hs != 0
						var quota := maxi(1, int(roundf(K * (lf if land_side else 1.0 - lf))))
						var other := 0
						var oweak := -1
						var oval := 1e9
						for k in K:
							var so := sp_out[base + k]
							if so >= 0 and (hab[so] == 0) == land_side:
								other += 1
								var v := pop_out[base + k] * comp[so]
								if v < oval and prot[so] == 0:
									oval = v
									oweak = k
						if other > K - quota and oweak >= 0:
							empty = oweak
					if empty >= 0:
						sp_out[base + empty] = s
						pop_out[base + empty] = seed_pop
						break
					# Invasion : déloge le plus faible, d'autant plus difficilement que sa niche diffère.
					var sw := sp_out[base + weakest]
					if potential * comp[s] > wval * (1.5 + 2.0 * (1.0 - ov[s * MAXS + sw])) and prot[sw] == 0:
						sp_out[base + weakest] = s
						pop_out[base + weakest] = seed_pop
						break

			# 3) Sorties régionales + statistiques de la bande.
			var best := -1
			var bestv := 0.0
			var bestp := 0.0
			var mbest := -1
			var mbestv := 0.0
			var tmax := 0.0
			for k in K:
				var s := sp_out[base + k]
				if s < 0:
					continue
				var p := pop_out[base + k]
				var v := p * vis[s]
				if hab[s] == 0:
					if v > mbestv:
						mbestv = v
						mbest = s
				elif v > bestv:
					bestv = v
					best = s
					bestp = p
				var tt := ttech[s] * minf(1.0, p * 2.0)
				if tt > tmax:
					tmax = tt
				bpop[bo + s] += p
				bcnt[bo + s] += 1
				bsample[bo + s] = r
			dom[r] = best
			mdom[r] = mbest
			dens[r] = minf(1.0, bestp)
			rtech[r] = tmax

	# 4) Grilles fines de la bande (uniquement ses lignes de cellules).
	var gpop := g_pop
	var gtech := g_tech
	var gdom := g_dom
	var detail := g_detail
	var tid := t_id
	for i in band_cells[b]:
		var r := (i >> 10) * RW + ((i & 255) >> 2)
		var dm := dom[r]
		if dm < 0:
			gdom[i] = -1
			gpop[i] = 0.0
			gtech[i] = 0.0
		else:
			var f := detail[i]
			gdom[i] = tid[dm]
			gpop[i] = dens[r] * f
			gtech[i] = rtech[r] * f
	if _temp_dirty:
		var gtemp := g_temp
		var btemp := g_base_temp
		var y0 := ry0 * RS
		for y in range(y0, y0 + ROWS_PER_BAND * RS):
			var rrow := (y >> 2) * RW
			for x in W:
				var i := y * W + x
				gtemp[i] = clampf(btemp[i] + goff + anom[rrow + (x >> 2)], 0.0, 1.0)
		if _biome_dirty:
			var gb := g_biome
			var ge := g_elev
			var gm := g_moist
			for i in range(y0 * W, (y0 + ROWS_PER_BAND * RS) * W):
				gb[i] = WorldGen.classify(ge[i], gtemp[i], gm[i])


## Réduit les statistiques des bandes pour un indice de table (ordre fixe => déterministe).
func reduce_stats(idx: int, pick: int) -> void:
	stat_pop = 0.0
	stat_cnt = 0
	stat_sample = -1
	var first := -1
	var nth := 0
	for b in BANDS:
		var o := b * MAXS + idx
		stat_pop += b_pop[o]
		var c := b_cnt[o]
		stat_cnt += c
		if c > 0:
			if first < 0:
				first = b_sample[o]
			if nth == pick % BANDS:
				stat_sample = b_sample[o]
			nth += 1
	if stat_sample < 0:
		stat_sample = first


# ---------------------------------------------------------------------------------------------
# Interventions (thread principal, entre deux pas, sur le tampon courant)
# ---------------------------------------------------------------------------------------------

## Tue une fraction des populations dans un disque. Renvoie {indice: true} des espèces touchées.
## Un filtre d'altitude (déluge) ne concerne que les terres : la vie marine est épargnée.
func kill_area(r: int, rad: int, frac: float, only_idx := -1, respect_protection := true, min_elev := -INF, max_elev := INF) -> Dictionary:
	var hit := {}
	var land_only := min_elev > -INF or max_elev < INF
	for rr in regions_in_radius(r, rad):
		if r_land[rr] <= 0.0 and (land_only or r_sea[rr] <= 0.0):
			continue
		var land_ok := r_land[rr] > 0.0 and r_elev[rr] >= min_elev and r_elev[rr] <= max_elev
		for k in K:
			var o := rr * K + k
			var s := cur_sp[o]
			if s < 0 or (only_idx >= 0 and s != only_idx):
				continue
			if (land_only and t_hab[s] == 0) or (t_hab[s] == 2 and not land_ok):
				continue
			var f := frac
			if respect_protection and t_protect[s] == 1:
				f *= 0.1
			hit[s] = true
			cur_pop[o] *= 1.0 - f
			if cur_pop[o] < EXTINCT_EPS:
				cur_sp[o] = -1
				cur_pop[o] = 0.0
	return hit


func scale_species(idx: int, factor: float) -> void:
	for o in NR * K:
		if cur_sp[o] == idx:
			cur_pop[o] *= factor
			if cur_pop[o] < EXTINCT_EPS:
				cur_sp[o] = -1
				cur_pop[o] = 0.0


## Installe une espèce dans un disque (niche vide, sinon la plus faible). Renvoie le nb de régions.
func place_species(idx: int, r: int, rad: int, pop: float, replace_idx := -1) -> int:
	var placed := 0
	for rr in regions_in_radius(r, rad):
		if not region_fits(idx, rr):
			continue
		var base := rr * K
		var slot := -1
		var wval := 1e9
		for k in K:
			var s := cur_sp[base + k]
			if s == idx:
				slot = -2
				break
			if replace_idx >= 0:
				if s == replace_idx:
					slot = k
					break
				continue
			if s < 0:
				slot = k
				wval = -1.0
			elif cur_pop[base + k] < wval and t_protect[s] == 0:
				wval = cur_pop[base + k]
				slot = k
		if slot < 0:
			continue
		var p := pop if replace_idx < 0 else maxf(cur_pop[base + slot], pop)
		cur_sp[base + slot] = idx
		cur_pop[base + slot] = p
		placed += 1
	return placed


func add_bless(r: int, rad: int, amount: float) -> void:
	for rr in regions_in_radius(r, rad):
		r_bless[rr] = minf(r_bless[rr] + amount, 1.0)


func add_anomaly(r: int, rad: int, amount: float) -> void:
	for rr in regions_in_radius(r, rad):
		r_anom[rr] += amount


## Décroissance exponentielle des modificateurs régionaux. Renvoie true s'il en reste.
func decay_modifiers(factor: float) -> bool:
	var active := false
	for r in NR:
		var a := r_anom[r]
		var bl := r_bless[r]
		if a != 0.0:
			a *= factor
			if absf(a) < 1e-3:
				a = 0.0
			else:
				active = true
			r_anom[r] = a
		if bl != 0.0:
			bl *= factor
			if bl < 1e-3:
				bl = 0.0
			else:
				active = true
			r_bless[r] = bl
	return active


func copy() -> RefCounted:
	var c: RefCounted = get_script().new()
	for prop in ["r_land", "r_fert", "r_temp", "r_elev", "r_sea", "r_anom", "r_bless", "cur_sp", "cur_pop",
			"nxt_sp", "nxt_pop", "r_dom", "r_mdom", "r_dens", "r_tech", "t_alive", "t_id", "t_protect", "t_diet",
			"t_hab", "t_cx", "t_anaer", "t_oxf",
			"t_topt", "t_tol", "t_comp", "t_icomp", "t_growth", "t_disp", "t_alpha", "t_mig", "t_vis",
			"t_tech", "t_capmul", "t_ov", "b_pop", "b_cnt", "b_sample", "g_detail"]:
		c.set(prop, get(prop).duplicate())
	c.explicit_flora = explicit_flora
	c.land_open = land_open
	# Listes de cellules : statiques, partagées en lecture seule entre timelines.
	c.band_cells = band_cells
	c.free_idx = free_idx.duplicate()
	c.pending_free = pending_free.duplicate()
	c.next_idx = next_idx
	c.threaded = threaded
	return c
