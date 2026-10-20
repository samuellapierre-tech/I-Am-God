extends RefCounted
## Tectonique des plaques (scénario Genèse) : des plaques rigides portent la croûte continentale,
## représentée par des particules (une par cellule de croûte au départ, plateaux compris).
##
## Cycle du supercontinent (Wilson), produit par l'état des plaques et non par des dates :
## - dispersion : les plaques s'écartent ;
## - rassemblement : elles convergent vers un point ; deux croûtes qui se touchent se soudent
##   (même vitesse) et soulèvent une chaîne de montagnes ;
## - supercontinent : quand la plus grande masse soudée porte SUPER_FRACTION de la croûte ; le
##   manteau s'échauffe dessous (isolation thermique) ;
## - fracture : après INSULATION_YEARS, les sutures se rouvrent, un océan s'ouvre, dispersion.
## Durées nominales calées sur la Terre (Pangée vers -335 Ma, fracture vers -175 Ma) ; les vitesses
## en découlent (distance / durée), bornées par des vitesses physiques.
##
## raster() est une fonction pure de l'état : elle tourne sur un fil de travail (WorldSim la lance
## et la rejoint à des sous-pas fixés, donc le résultat ne dépend pas de l'ordonnancement).

const W := 256
const H := 128
## Durées nominales (années) des phases du cycle.
const ASSEMBLY_YEARS := 280.0e6
const INSULATION_YEARS := 160.0e6
const DISPERSAL_YEARS := 240.0e6
## Durée observée d'un rassemblement (les fragments se retrouvent vite) : sert à caler le premier
## cycle ; un rassemblement qui s'éternise aboutit avec une masse moindre (SUPER_FALLBACK).
const ASSEMBLY_EXPECTED := 20.0e6
const ASSEMBLY_PATIENCE := 100.0e6
const SUPER_FALLBACK := 0.55
## Vitesses des plaques (cellules par million d'années ; une cellule ≈ 150 km).
const MIN_SPEED := 0.08
const MAX_SPEED := 0.6
const DISPERSAL_SPEED := 0.3
## Contact : cellules de croûte superposées entre deux plaques pour qu'elles se soudent.
const CONTACT_CELLS := 4
## Part de la croûte dans une seule masse soudée pour parler de supercontinent.
const SUPER_FRACTION := 0.7
## Soulèvement d'une collision et temps d'érosion des montagnes.
const OROGENY_UPLIFT := 0.12
const MAX_UPLIFT := 0.55
const EROSION_YEARS := 150.0e6
## Les plaques rebondissent avant les pôles.
const POLE_MARGIN := 10.0
## Bord de croûte : altitude de départ minimale d'une particule (plateaux compris).
const CRUST_MIN_ELEVATION := -0.3
const CRATER_FADE_YEARS := 60.0e6
## Largeur (cellules) de l'océan qui sépare les cratons au départ.
const CRATON_GAP := 6.0
## Après une fracture, les anciennes sutures se chevauchent encore : pas de nouvelle soudure avant.
const RESUTURE_GRACE := 40.0e6

const SUPERCONTINENT_NAMES := ["Vaalbara", "Kenorland", "Nuna", "Rodinia", "Pangée", "Amasie",
	"Novopangée", "Aurica"]

# --- Plaques (tableaux compacts, faciles à sauvegarder) ---
var n := 0
var p_cx := PackedFloat64Array()   # centre (cellules)
var p_cy := PackedFloat64Array()
var p_th := PackedFloat64Array()   # angle (radians)
var p_vx := PackedFloat64Array()   # vitesse (cellules / Ma)
var p_vy := PackedFloat64Array()
var p_om := PackedFloat64Array()   # rotation (radians / Ma)
var p_group := PackedInt32Array()  # masse soudée (racine d'union)
var p_cause := PackedInt32Array()  # dernier événement causal qui a poussé la plaque
var p_crust := PackedInt32Array()  # nombre de particules de croûte
# --- Particules de croûte : plaque, position dans le repère de la plaque, altitude ---
var c_plate := PackedInt32Array()
var c_ox := PackedFloat32Array()
var c_oy := PackedFloat32Array()
var c_elev := PackedFloat32Array()
var c_uplift := PackedFloat32Array()
# --- Cycle ---
var phase := "dispersal"
var phase_since := 0.0
var phase_length := DISPERSAL_YEARS
var cycles := 0
var target := Vector2(128, 64)
var supercontinent_fraction := 0.0
## Part de la croûte continentale dans la plus grande masse connexe (pilote le cycle).
var crust_fraction := 0.0
var supercontinent_name := ""
var no_suture_until := -INF
## Graine propre (cibles de rassemblement).
var _seed := 0


## Crée les plaques (Voronoï de graines tirées) et une particule par cellule de croûte.
func setup(seed_value: int, elevation: PackedFloat32Array, n_plates: int, start_year: float) -> void:
	_seed = seed_value
	n = maxi(2, n_plates)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("plaques:%d" % seed_value)
	for a in [p_cx, p_cy, p_th, p_vx, p_vy, p_om]:
		a.resize(n)
	for a in [p_group, p_cause, p_crust]:
		a.resize(n)
	for k in n:
		p_cx[k] = rng.randf_range(0.0, W)
		p_cy[k] = rng.randf_range(POLE_MARGIN + 4.0, H - POLE_MARGIN - 4.0)
		p_th[k] = 0.0
		var a := rng.randf_range(0.0, TAU)
		var s := rng.randf_range(MIN_SPEED, DISPERSAL_SPEED)
		p_vx[k] = cos(a) * s
		p_vy[k] = sin(a) * s * 0.5
		p_om[k] = rng.randf_range(-0.0006, 0.0006)
		p_group[k] = k
		p_cause[k] = -1
		p_crust[k] = 0
	# Cratons : la croûte du relief initial, découpée par les frontières de plaques (une bande
	# d'océan les sépare) : les continents commencent dispersés.
	var keep := PackedByteArray()
	keep.resize(elevation.size())
	var count := 0
	for i in elevation.size():
		if elevation[i] < CRUST_MIN_ELEVATION:
			continue
		var x := float(i % W)
		@warning_ignore("integer_division")
		var y := float(i / W)
		var d1 := INF
		var d2 := INF
		for k in n:
			var dx := _wrap_dx(x - p_cx[k])
			var dy := y - p_cy[k]
			var d := dx * dx + dy * dy
			if d < d1:
				d2 = d1
				d1 = d
			elif d < d2:
				d2 = d
		if sqrt(d2) - sqrt(d1) >= CRATON_GAP:
			keep[i] = 1
			count += 1
	for a in [c_plate]:
		a.resize(count)
	for a in [c_ox, c_oy, c_elev, c_uplift]:
		a.resize(count)
	var j := 0
	for i in elevation.size():
		var e := elevation[i]
		if keep[i] == 0:
			continue
		var x := float(i % W)
		@warning_ignore("integer_division")
		var y := float(i / W)
		var k := nearest_plate(x, y)
		c_plate[j] = k
		c_ox[j] = _wrap_dx(x - p_cx[k])
		c_oy[j] = y - p_cy[k]
		c_elev[j] = e
		c_uplift[j] = 0.0
		p_crust[k] += 1
		j += 1
	phase = "dispersal"
	phase_since = start_year
	# Durée de la première dispersion : un supercontinent nominal à -335 Ma (cycle terrestre).
	var period := ASSEMBLY_EXPECTED + INSULATION_YEARS + DISPERSAL_YEARS
	phase_length = fposmod(-335.0e6 - start_year - ASSEMBLY_EXPECTED, period)


func nearest_plate(x: float, y: float) -> int:
	var best := 0
	var best_d := INF
	for k in n:
		var dx := _wrap_dx(x - p_cx[k])
		var dy := y - p_cy[k]
		var d := dx * dx + dy * dy
		if d < best_d:
			best_d = d
			best = k
	return best


static func _wrap_dx(dx: float) -> float:
	return fposmod(dx + W * 0.5, W) - W * 0.5


func group_of(k: int) -> int:
	var g := k
	var guard := 0
	while p_group[g] != g and guard < 64:
		g = p_group[g]
		guard += 1
	return g


## Avance les plaques de dt années (thread principal, O(plaques)). Renvoie les changements de
## phase : [{kind: "supercontinent"|"breakup"|"assembly", name}].
func advance(dt: float, year: float) -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	var dm := dt / 1.0e6
	_set_velocities()
	for k in n:
		p_cx[k] = fposmod(p_cx[k] + p_vx[k] * dm, W)
		p_cy[k] += p_vy[k] * dm
		p_th[k] += p_om[k] * dm
		if p_cy[k] < POLE_MARGIN and p_vy[k] < 0.0 or p_cy[k] > H - POLE_MARGIN and p_vy[k] > 0.0:
			p_vy[k] = -p_vy[k]
	match phase:
		"dispersal":
			if year - phase_since >= phase_length:
				phase = "assembly"
				phase_since = year
				phase_length = ASSEMBLY_YEARS
				for k in n:
					p_group[k] = k
				var rng := RandomNumberGenerator.new()
				rng.seed = hash("rassemblement:%d:%d" % [_seed, cycles])
				target = Vector2(rng.randf_range(0.0, W), rng.randf_range(H * 0.3, H * 0.7))
				changes.append({kind = "assembly", name = ""})
		"assembly":
			var waited := year - phase_since
			if crust_fraction >= SUPER_FRACTION or (waited >= ASSEMBLY_PATIENCE and crust_fraction >= SUPER_FALLBACK):
				phase = "supercontinent"
				phase_since = year
				phase_length = INSULATION_YEARS
				# Noms des supercontinents terrestres dans l'ordre ; celui des derniers 600 Ma est la Pangée.
				supercontinent_name = SUPERCONTINENT_NAMES[cycles % SUPERCONTINENT_NAMES.size()]
				if year >= -600.0e6 and year <= -150.0e6:
					supercontinent_name = "Pangée"
				elif supercontinent_name == "Pangée":
					supercontinent_name = "Pangée %s" % ["Ultime", "Nouvelle", "Seconde"][cycles % 3]
				changes.append({kind = "supercontinent", name = supercontinent_name})
		"supercontinent":
			if year - phase_since >= phase_length:
				changes.append({kind = "breakup", name = supercontinent_name})
				breakup(year)
	return changes


## Fracture : toutes les sutures se rouvrent, chaque plaque s'éloigne du centre de la masse.
func breakup(year: float) -> void:
	var c := _crust_centroid(-1)
	for k in n:
		p_group[k] = k
		var dx := _wrap_dx(p_cx[k] - c.x)
		var dy := p_cy[k] - c.y
		var l := maxf(sqrt(dx * dx + dy * dy), 1.0)
		p_vx[k] = dx / l * DISPERSAL_SPEED
		p_vy[k] = dy / l * DISPERSAL_SPEED * 0.6
		p_om[k] = 0.0005 * (1.0 if k % 2 == 0 else -1.0)
	phase = "dispersal"
	phase_since = year
	phase_length = DISPERSAL_YEARS
	no_suture_until = year + RESUTURE_GRACE
	cycles += 1
	supercontinent_fraction = 0.0
	crust_fraction = 0.0


## Pousse une plaque (geste divin) : elle quitte sa masse soudée et part dans la direction dir.
func push(k: int, dir: Vector2, strength: float, cause: int, year := 0.0) -> void:
	if k < 0 or k >= n:
		return
	no_suture_until = maxf(no_suture_until, year + RESUTURE_GRACE * 0.5)
	for o in n:
		if o != k and group_of(o) == k:
			p_group[o] = o
	p_group[k] = k
	var d := dir.normalized() if dir.length() > 0.0 else Vector2(1, 0)
	p_vx[k] += d.x * strength
	p_vy[k] += d.y * strength
	var s := Vector2(p_vx[k], p_vy[k]).length()
	if s > MAX_SPEED:
		p_vx[k] *= MAX_SPEED / s
		p_vy[k] *= MAX_SPEED / s
	p_cause[k] = cause


func _set_velocities() -> void:
	if phase == "dispersal":
		# Plaques soudées pendant la dispersion : elles dérivent ensemble (moyenne pondérée).
		var sums := {}
		for k in n:
			var g := group_of(k)
			var w := float(maxi(p_crust[k], 1))
			var acc: Array = sums.get(g, [0.0, 0.0, 0.0, 0])
			acc[0] += p_vx[k] * w
			acc[1] += p_vy[k] * w
			acc[2] += w
			acc[3] += 1
			sums[g] = acc
		for k in n:
			var acc: Array = sums[group_of(k)]
			if int(acc[3]) > 1:
				p_vx[k] = acc[0] / acc[2]
				p_vy[k] = acc[1] / acc[2]
				p_om[k] = 0.0
		return
	# Rassemblement (et supercontinent) : chaque masse soudée file vers la cible, d'autant plus
	# lentement qu'elle en est proche ; une masse soudée bouge d'un bloc, sans rotation.
	var remaining := maxf(ASSEMBLY_YEARS - 0.0, 1.0) / 1.0e6
	var groups := {}
	for k in n:
		var g := group_of(k)
		if not groups.has(g):
			groups[g] = []
		groups[g].append(k)
	for g in groups:
		var members: Array = groups[g]
		var c := _crust_centroid(g)
		var vx := 0.0
		var vy := 0.0
		if phase == "assembly":
			var dx := _wrap_dx(target.x - c.x)
			var dy := target.y - c.y
			var dist := sqrt(dx * dx + dy * dy)
			var speed := clampf(dist / remaining, MIN_SPEED, MAX_SPEED) * clampf(dist / 6.0, 0.0, 1.0)
			if dist > 0.01:
				vx = dx / dist * speed
				vy = dy / dist * speed
		for k in members:
			p_vx[k] = vx
			p_vy[k] = vy
			if members.size() > 1 or phase == "supercontinent":
				p_om[k] = 0.0


## Centre de la croûte d'une masse soudée (g = -1 : toute la croûte), moyenne circulaire en x.
func _crust_centroid(g: int) -> Vector2:
	var sx := 0.0
	var sy := 0.0
	var cy := 0.0
	var total := 0.0
	for k in n:
		if p_crust[k] == 0 or (g >= 0 and group_of(k) != g):
			continue
		var a := p_cx[k] / W * TAU
		var w := float(p_crust[k])
		sx += cos(a) * w
		sy += sin(a) * w
		cy += p_cy[k] * w
		total += w
	if total <= 0.0:
		return Vector2(W * 0.5, H * 0.5)
	return Vector2(fposmod(atan2(sy, sx) / TAU * W, W), cy / total)


## Applique les contacts trouvés par raster() : soudures (et leurs causes). Renvoie les collisions
## nouvelles : [{a, b, cells}].
func apply_contacts(contacts: Dictionary, year: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# Pendant la dispersion, les plaques qui se croisent soulèvent des montagnes sans se souder :
	# seules les collisions d'un rassemblement bâtissent le supercontinent.
	if year < no_suture_until or phase == "dispersal":
		return out
	var keys := contacts.keys()
	keys.sort()
	for key in keys:
		var cells: int = contacts[key]
		if cells < CONTACT_CELLS:
			continue
		var a: int = key >> 8
		var b: int = key & 255
		var ga := group_of(a)
		var gb := group_of(b)
		if ga == gb:
			continue
		# Seules des plaques qui se rapprochent se soudent (deux plaques qui s'écartent après une
		# fracture se chevauchent encore un temps sans se ressouder).
		var dx := _wrap_dx(p_cx[b] - p_cx[a])
		var dy := p_cy[b] - p_cy[a]
		var closing := (p_vx[b] - p_vx[a]) * dx + (p_vy[b] - p_vy[a]) * dy
		if closing >= 0.0:
			continue
		p_group[maxi(ga, gb)] = mini(ga, gb)
		out.append({a = a, b = b, cells = cells})
	return out


func plate_position(k: int, ox: float, oy: float) -> Vector2:
	var c := cos(p_th[k])
	var s := sin(p_th[k])
	return Vector2(fposmod(p_cx[k] + ox * c - oy * s, W), p_cy[k] + ox * s + oy * c)


## Repère dans le repère d'une plaque (ancre) pour une cellule : la croûte qui s'y trouve.
func make_anchor(cell: Vector2i, plate: int) -> Dictionary:
	var k := clampi(plate, 0, n - 1)
	var dx := _wrap_dx(float(cell.x) - p_cx[k])
	var dy := float(cell.y) - p_cy[k]
	var c := cos(-p_th[k])
	var s := sin(-p_th[k])
	return {plate = k, ox = dx * c - dy * s, oy = dx * s + dy * c}


func anchor_cell(anchor: Dictionary) -> Vector2i:
	var p := plate_position(int(anchor.plate), float(anchor.ox), float(anchor.oy))
	return Vector2i(posmod(int(round(p.x)), W), clampi(int(round(p.y)), 0, H - 1))


## Instantané des plaques pour raster() (lecture seule côté fil de travail).
func snapshot() -> Dictionary:
	var groups := PackedInt32Array()
	groups.resize(n)
	for k in n:
		groups[k] = group_of(k)
	return {n = n, cx = p_cx.duplicate(), cy = p_cy.duplicate(), th = p_th.duplicate(),
		vx = p_vx.duplicate(), vy = p_vy.duplicate(), group = groups}


## Calcule la géographie (fil de travail). Écrit c_uplift (que seul ce calcul modifie pendant
## qu'il tourne). Renvoie {crust (altitude absolue, croûte), plate_id, boundary, coast_dist,
## contacts {a<<8|b: cellules}, supercontinent_fraction, land_fraction}.
func raster(snap: Dictionary, ocean_noise: PackedFloat32Array, sea_level: float, craters: Array) -> Dictionary:
	var count := W * H
	var crust := PackedFloat32Array()
	crust.resize(count)
	var owner := PackedInt32Array()
	owner.resize(count)
	owner.fill(-1)
	var thick := PackedFloat32Array()
	thick.resize(count)
	var contacts := {}
	var sn: int = snap.n
	var cx: PackedFloat64Array = snap.cx
	var cy: PackedFloat64Array = snap.cy
	var th: PackedFloat64Array = snap.th
	var cs := PackedFloat64Array()
	var sn_ := PackedFloat64Array()
	cs.resize(sn)
	sn_.resize(sn)
	for k in sn:
		cs[k] = cos(th[k])
		sn_[k] = sin(th[k])
	var erosion: float = snap.get("erosion", 1.0)
	if erosion < 0.9999:
		for j in c_uplift.size():
			c_uplift[j] *= erosion
	# 1) Croûte continentale : chaque particule tombe dans une cellule ; deux plaques sur une même
	#    cellule = collision (contact, épaississement, montagnes).
	for j in c_plate.size():
		var k := c_plate[j]
		var ox := c_ox[j]
		var oy := c_oy[j]
		var px := cx[k] + ox * cs[k] - oy * sn_[k]
		var py := cy[k] + ox * sn_[k] + oy * cs[k]
		var x := posmod(int(round(px)), W)
		var y := clampi(int(round(py)), 0, H - 1)
		var i := y * W + x
		var e := c_elev[j] + c_uplift[j]
		var o := owner[i]
		if o < 0:
			owner[i] = k
			crust[i] = e
			thick[i] = 1.0
		else:
			if o != k:
				var key := (mini(o, k) << 8) | maxi(o, k)
				contacts[key] = int(contacts.get(key, 0)) + 1
				c_uplift[j] = minf(MAX_UPLIFT, c_uplift[j] + OROGENY_UPLIFT)
			crust[i] = maxf(crust[i], e) + 0.02
			thick[i] += 1.0
	# 2) Trous de rotation : une cellule vide entourée de croûte en hérite.
	var filled := owner.duplicate()
	for y in range(1, H - 1):
		for x in W:
			var i := y * W + x
			if owner[i] >= 0:
				continue
			var nb := 0
			var se := 0.0
			var who := -1
			var left := y * W + (x + W - 1) % W
			var right := y * W + (x + 1) % W
			for jj in 4:
				var j2 := left if jj == 0 else (right if jj == 1 else (i - W if jj == 2 else i + W))
				if owner[j2] >= 0:
					nb += 1
					se += crust[j2]
					who = owner[j2]
			if nb >= 3:
				filled[i] = who
				crust[i] = se / nb
	owner = filled
	# 3) Distance à la croûte (chanfrein deux passes), pour les plateaux et les abysses.
	var dist := PackedFloat32Array()
	dist.resize(count)
	for i in count:
		dist[i] = 0.0 if owner[i] >= 0 else 99.0
	for y in H:
		for x in W:
			var i := y * W + x
			if dist[i] == 0.0:
				continue
			var best := dist[i]
			if y > 0:
				best = minf(best, dist[i - W] + 1.0)
			best = minf(best, dist[y * W + posmod(x - 1, W)] + 1.0)
			dist[i] = best
	for y in range(H - 1, -1, -1):
		for x in range(W - 1, -1, -1):
			var i := y * W + x
			if dist[i] == 0.0:
				continue
			var best := dist[i]
			if y < H - 1:
				best = minf(best, dist[i + W] + 1.0)
			best = minf(best, dist[y * W + posmod(x + 1, W)] + 1.0)
			dist[i] = best
	# 4) Plaques des cellules océaniques (Voronoï des centres), frontières, dorsales, fosses, arcs.
	var plate_id := PackedInt32Array()
	plate_id.resize(count)
	var vx: PackedFloat64Array = snap.vx
	var vy: PackedFloat64Array = snap.vy
	# Voronoï des centres de plaques calculé par bloc de 4x4 cellules (assez fin pour la carte).
	for by in range(0, H, 4):
		for bx in range(0, W, 4):
			var best := 0
			var bd := INF
			for k in sn:
				var dx := fposmod(float(bx + 2) - cx[k] + W * 0.5, W) - W * 0.5
				var dy := float(by + 2) - cy[k]
				var d := dx * dx + dy * dy
				if d < bd:
					bd = d
					best = k
			for y in range(by, by + 4):
				for x in range(bx, bx + 4):
					var i := y * W + x
					plate_id[i] = owner[i] if owner[i] >= 0 else best
	var boundary := PackedByteArray()
	boundary.resize(count)
	for y in H:
		for x in W:
			var i := y * W + x
			var a := plate_id[i]
			var xr := (x + 1) % W
			var jr := y * W + xr
			var jd := (y + 1) * W + x if y < H - 1 else i
			for side in 2:
				var jj := jr if side == 0 else jd
				var b := plate_id[jj]
				if b == a:
					continue
				# Mouvement relatif projeté sur la normale de la frontière : écartement ou rapprochement.
				var nx := 1.0 if side == 0 else 0.0
				var ny := 1.0 - nx
				var rel := (vx[b] - vx[a]) * nx + (vy[b] - vy[a]) * ny
				var kind := 3
				if rel > 0.05:
					kind = 1
				elif rel < -0.05:
					kind = 2
				boundary[i] = kind
				boundary[jj] = maxi(boundary[jj], kind)
	for i in count:
		if owner[i] >= 0:
			continue
		var d := dist[i]
		var e := lerpf(-0.08, -0.62, clampf((d - 1.0) / 9.0, 0.0, 1.0)) + ocean_noise[i] * 0.08
		match boundary[i]:
			1:
				e += 0.22  # dorsale
			2:
				e -= 0.18  # fosse
				var h := hash(i * 2654435761) & 1023
				if h < 180 and d > 3.0:
					e = 0.05 + float(h) / 4000.0  # arc volcanique insulaire
		crust[i] = e
	# 5) Cratères récents (ils s'effacent en CRATER_FADE_YEARS).
	for c in craters:
		var cell: Vector2i = c.cell
		var rad: int = c.radius
		var depth: float = 0.25 * float(c.fade)
		for dy in range(-rad, rad + 1):
			var y := cell.y + dy
			if y < 0 or y >= H:
				continue
			for dx in range(-rad, rad + 1):
				var d2 := float(dx * dx + dy * dy) / float(rad * rad)
				if d2 > 1.0:
					continue
				var i := y * W + posmod(cell.x + dx, W)
				crust[i] -= depth * (1.0 - d2)
	# 6) Altitude relative à la mer, part des terres et plus grande masse connexe de terres.
	var elevation := PackedFloat32Array()
	elevation.resize(count)
	var land := 0
	for i in count:
		var e := crust[i] - sea_level
		elevation[i] = clampf(e, -1.0, 1.0)
		if elevation[i] >= 0.0:
			land += 1
	var largest := _largest_mass(elevation)
	# Masse de croûte continentale (plateaux compris) : c'est elle qui fait le supercontinent,
	# même quand des mers peu profondes en couvrent une partie.
	var crust_mask := PackedFloat32Array()
	crust_mask.resize(count)
	var crust_cells := 0
	for i in count:
		crust_mask[i] = 1.0 if owner[i] >= 0 else -1.0
		if owner[i] >= 0:
			crust_cells += 1
	var crust_largest := _largest_mass(crust_mask)
	return {elevation = elevation, crust = crust, plate_id = plate_id, boundary = boundary,
		coast_dist = dist, contacts = contacts, land = land,
		supercontinent_fraction = float(largest) / float(maxi(land, 1)),
		crust_fraction = float(crust_largest) / float(maxi(crust_cells, 1))}


## Taille de la plus grande masse de terres connexe (4-voisinage, x bouclé).
static func _largest_mass(elevation: PackedFloat32Array) -> int:
	var count := W * H
	var seen := PackedByteArray()
	seen.resize(count)
	var stack := PackedInt32Array()
	var best := 0
	for start in count:
		if seen[start] == 1 or elevation[start] < 0.0:
			continue
		var size := 0
		stack.clear()
		stack.append(start)
		seen[start] = 1
		while not stack.is_empty():
			var i := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			size += 1
			var x := i % W
			@warning_ignore("integer_division")
			var y := i / W
			for side in 4:
				var j := -1
				match side:
					0:
						j = y * W + (x + 1) % W
					1:
						j = y * W + (x + W - 1) % W
					2:
						j = i - W if y > 0 else -1
					3:
						j = i + W if y < H - 1 else -1
				if j >= 0 and seen[j] == 0 and elevation[j] >= 0.0:
					seen[j] = 1
					stack.append(j)
		best = maxi(best, size)
	return best


## Copie profonde (fork).
func copy() -> RefCounted:
	var c: RefCounted = get_script().new()
	for prop in ["n", "phase", "phase_since", "phase_length", "cycles", "target", "supercontinent_fraction",
			"supercontinent_name", "_seed", "no_suture_until", "crust_fraction"]:
		c.set(prop, get(prop))
	for prop in ["p_cx", "p_cy", "p_th", "p_vx", "p_vy", "p_om", "p_group", "p_cause", "p_crust",
			"c_plate", "c_ox", "c_oy", "c_elev", "c_uplift"]:
		c.set(prop, get(prop).duplicate())
	return c
