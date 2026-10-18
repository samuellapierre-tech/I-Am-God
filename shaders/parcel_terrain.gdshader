shader_type canvas_item;
// Terrain de la parcelle, vu de haut, entièrement procédural (GPU).
// Deux états de sol (a -> b) fondus par un motif de dissolution quand l'usage ou le biome change.
// Types de sol : voir ParcelLogic.Ground (src/parcel/parcel_logic.gd), mêmes indices.

uniform vec2 parcel_size = vec2(1920.0, 1080.0);
uniform vec2 seed_offset = vec2(0.0);

uniform int kind_a = 0;
uniform int kind_b = 0;
uniform float wear_a = 0.0;
uniform float wear_b = 0.0;
uniform float veg_a = 1.0;
uniform float veg_b = 1.0;
uniform float blend : hint_range(0.0, 1.0) = 1.0;

uniform float vegetation : hint_range(0.0, 1.0) = 0.5;
uniform float water : hint_range(0.0, 1.0) = 0.3;
uniform float temperature_c = 20.0;
uniform float tech : hint_range(0.0, 1.0) = 0.0;
// Saisons (horloge de la vue) : neige au sol, feuillage d'automne.
uniform float snow_cover : hint_range(0.0, 1.0) = 0.0;
uniform float autumn : hint_range(0.0, 1.0) = 0.0;

// Repères permanents (règle de continuité) : rivière en S et gros rocher plat clair.
uniform vec2 river_pts[24];
uniform float river_width = 44.0;
// (eau, gel, canal, pollution), lissé côté CPU.
uniform vec4 river_state = vec4(1.0, 0.0, 0.0, 0.0);
uniform vec2 rock_pos = vec2(500.0, 700.0);
uniform vec2 rock_radii = vec2(100.0, 70.0);
uniform float rock_angle = 0.0;

varying vec2 world_pos;

const int GRASS = 0;
const int LUSH = 1;
const int DRY = 2;
const int SAND = 3;
const int TUNDRA = 4;
const int SNOW = 5;
const int ROCK = 6;
const int WATER = 7;
const int MUD = 8;
const int CRATER = 9;
const int DIRT = 10;
const int PAVED = 11;
const int URBAN = 12;
const int RUBBLE = 13;
const int TAIGA = 14;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return s / 0.97;
}

// Cratère centré sur la parcelle : cuvette sombre, bourrelet clair, braises au fond.
vec3 crater_color(vec2 uv, float n) {
	vec2 d2 = (uv - 0.5) * vec2(parcel_size.x / parcel_size.y, 1.0);
	float d = length(d2) + (n - 0.5) * 0.06;
	vec3 rock = mix(vec3(0.22, 0.18, 0.16), vec3(0.34, 0.29, 0.25), n);
	vec3 rim = vec3(0.52, 0.45, 0.38);
	vec3 col = mix(rock * 0.7, rock, smoothstep(0.0, 0.35, d));
	col = mix(col, rim, smoothstep(0.30, 0.38, d) * (1.0 - smoothstep(0.38, 0.5, d)));
	col = mix(col, vec3(0.42, 0.36, 0.30), smoothstep(0.5, 0.7, d));
	float ember = (1.0 - smoothstep(0.0, 0.14, d)) * smoothstep(0.55, 0.75, n);
	col += vec3(1.0, 0.35, 0.05) * ember * (0.35 + 0.15 * sin(TIME * 1.7 + n * 12.0));
	return col;
}

vec3 ground_color(int kind, vec2 p, vec2 uv, float n1, float n2, float wear) {
	vec3 col;
	if (kind == GRASS) {
		col = mix(vec3(0.30, 0.45, 0.20), vec3(0.42, 0.56, 0.26), n1);
	} else if (kind == LUSH) {
		col = mix(vec3(0.15, 0.37, 0.13), vec3(0.25, 0.48, 0.18), n1);
	} else if (kind == DRY) {
		col = mix(vec3(0.63, 0.58, 0.33), vec3(0.49, 0.51, 0.27), n1);
	} else if (kind == SAND) {
		float dunes = 0.5 + 0.5 * sin(p.x * 0.045 + p.y * 0.012 + n2 * 7.0);
		col = mix(vec3(0.80, 0.66, 0.44), vec3(0.88, 0.76, 0.53), dunes * 0.6 + n1 * 0.4);
	} else if (kind == TUNDRA) {
		col = mix(vec3(0.47, 0.50, 0.40), vec3(0.63, 0.63, 0.56), n1);
	} else if (kind == SNOW) {
		col = mix(vec3(0.84, 0.90, 0.96), vec3(0.97, 0.98, 1.0), n1);
		col = mix(col, vec3(0.62, 0.76, 0.88), smoothstep(0.62, 0.66, n2) * 0.5);
	} else if (kind == ROCK) {
		col = mix(vec3(0.40, 0.38, 0.36), vec3(0.58, 0.55, 0.51), n1);
		col *= 0.85 + 0.3 * smoothstep(0.45, 0.55, n2);
	} else if (kind == WATER) {
		float waves = sin(p.x * 0.03 + TIME * 0.9 + n2 * 6.0) * sin(p.y * 0.025 - TIME * 0.7);
		col = mix(vec3(0.06, 0.20, 0.36), vec3(0.11, 0.33, 0.50), n1) + waves * 0.025;
	} else if (kind == MUD) {
		col = mix(vec3(0.31, 0.26, 0.17), vec3(0.43, 0.37, 0.24), n1);
		float puddle = smoothstep(0.55, 0.58, n2);
		col = mix(col, vec3(0.24, 0.36, 0.40) + 0.03 * sin(TIME + n1 * 9.0), puddle);
	} else if (kind == CRATER) {
		col = crater_color(uv, n1);
	} else if (kind == DIRT) {
		col = mix(vec3(0.44, 0.35, 0.24), vec3(0.55, 0.45, 0.31), n1);
	} else if (kind == PAVED) {
		vec2 cellp = fract(p / 160.0);
		float street = 1.0 - step(0.08, min(cellp.x, cellp.y));
		col = mix(vec3(0.50, 0.49, 0.46), vec3(0.58, 0.57, 0.53), n1);
		col = mix(col, vec3(0.30, 0.30, 0.31), street);
	} else if (kind == URBAN) {
		vec2 cellp = fract(p / 120.0);
		float street = 1.0 - step(0.06, min(cellp.x, cellp.y));
		col = mix(vec3(0.12, 0.12, 0.17), vec3(0.18, 0.18, 0.24), n1);
		vec2 id = floor(p / 120.0);
		float neon_pick = hash12(id + seed_offset);
		vec3 neon = neon_pick > 0.5 ? vec3(0.1, 0.9, 1.0) : vec3(1.0, 0.2, 0.75);
		float pulse = 0.55 + 0.45 * sin(TIME * 2.0 + neon_pick * 30.0);
		col = mix(col, vec3(0.05, 0.05, 0.08), street);
		col += neon * street * pulse * 0.35 * smoothstep(0.3, 0.8, hash12(id * 1.7));
	} else if (kind == RUBBLE) {
		col = mix(vec3(0.40, 0.37, 0.32), vec3(0.52, 0.48, 0.42), n1);
		col *= 0.8 + 0.35 * step(0.7, vnoise(p * 0.12));
	} else { // TAIGA
		col = mix(vec3(0.22, 0.31, 0.22), vec3(0.31, 0.39, 0.28), n1);
	}
	// Sentiers piétinés / terre labourée.
	float path = smoothstep(0.47, 0.5, n2) * (1.0 - smoothstep(0.5, 0.53, n2));
	col = mix(col, vec3(0.47, 0.38, 0.26), clamp(wear * (path * 1.6 + n1 * 0.4), 0.0, 1.0));
	return col;
}

vec3 tree_color(int kind) {
	if (kind == TAIGA || kind == TUNDRA || kind == SNOW) return vec3(0.09, 0.23, 0.16);
	if (kind == LUSH) return vec3(0.09, 0.35, 0.10);
	if (kind == DRY || kind == SAND) return vec3(0.33, 0.40, 0.17);
	if (kind == RUBBLE) return vec3(0.20, 0.36, 0.15);
	return vec3(0.15, 0.33, 0.12);
}

// Feuillus : rougissent à l'automne (pas les conifères ni la forêt tropicale).
float deciduous(int kind) {
	return (kind == TAIGA || kind == TUNDRA || kind == SNOW || kind == LUSH) ? 0.0 : 1.0;
}

bool is_liquid(int kind) {
	return kind == WATER;
}

void vertex() {
	world_pos = VERTEX;
}

// Distance à la rivière (polyligne) et abscisse le long du cours (pour le courant).
vec2 river_distance(vec2 p) {
	float best = 1e6;
	float along = 0.0;
	float acc = 0.0;
	for (int k = 0; k < 23; k++) {
		vec2 a = river_pts[k];
		vec2 b = river_pts[k + 1];
		vec2 ba = b - a;
		float len = length(ba);
		float h = clamp(dot(p - a, ba) / max(len * len, 1e-4), 0.0, 1.0);
		float d = length(p - a - ba * h);
		if (d < best) {
			best = d;
			along = acc + h * len;
		}
		acc += len;
	}
	return vec2(best, along);
}

// Rivière : eau qui coule, berges ; lit sec, glace, canal maçonné ou eau polluée selon l'état.
vec3 apply_river(vec3 col, vec2 p, float n1, float urban, out float water_mask, out float river_d) {
	vec2 ra = river_distance(p);
	river_d = ra.x;
	float wet = river_state.x;
	float frozen = river_state.y;
	float canal = river_state.z;
	float polluted = river_state.w;
	float wobble = (vnoise(p * 0.02) - 0.5) * 10.0 * (1.0 - canal);
	float d = ra.x + wobble;
	float half_w = river_width * 0.5 * mix(0.6, 1.0, wet);
	float bed = 1.0 - smoothstep(half_w + 2.0, half_w + 5.0, d);
	water_mask = (1.0 - smoothstep(half_w - 3.0, half_w, d)) * wet;
	// Berges : galets et boue (nature) ou quai de pierre (canal).
	float bank = (1.0 - smoothstep(half_w + 4.0, half_w + 16.0, d)) * (1.0 - bed);
	vec3 bank_col = mix(vec3(0.42, 0.36, 0.26), vec3(0.6, 0.58, 0.55), canal);
	col = mix(col, bank_col, bank * mix(0.55, 0.95, canal));
	// Lit à sec : graviers clairs.
	vec3 gravel = mix(vec3(0.62, 0.56, 0.45), vec3(0.72, 0.67, 0.56), vnoise(p * 0.25));
	col = mix(col, gravel, bed * (1.0 - wet));
	// Eau : courant le long du lit.
	float flow = sin(ra.y * 0.09 - TIME * 3.0 + n1 * 4.0) * 0.5 + 0.5;
	vec3 water_col = mix(vec3(0.1, 0.3, 0.42), vec3(0.16, 0.42, 0.52), flow * (1.0 - smoothstep(0.0, half_w, d)));
	water_col = mix(water_col, vec3(0.33, 0.29, 0.2), polluted * 0.8);
	water_col = mix(water_col, vec3(0.06, 0.12, 0.2), canal * 0.4);
	// Reflets de néons dans le canal des mégapoles.
	water_col += vec3(0.2, 0.05, 0.25) * urban * canal * (0.5 + 0.5 * sin(ra.y * 0.05 + TIME * 2.0));
	vec3 ice = mix(vec3(0.78, 0.88, 0.95), vec3(0.92, 0.96, 1.0), vnoise(p * 0.05));
	ice *= 1.0 - 0.15 * step(0.92, vnoise(p * 0.3)); // fissures
	water_col = mix(water_col, ice, frozen);
	col = mix(col, water_col, water_mask);
	water_mask *= 1.0 - frozen;
	return col;
}

// Gros rocher plat et clair, toujours au même endroit ; place pavée autour en ville.
vec3 apply_rock(vec3 col, vec2 p, float paved, float urban, out float rock_mask) {
	vec2 q = p - rock_pos;
	float ca = cos(-rock_angle);
	float sa = sin(-rock_angle);
	q = vec2(q.x * ca - q.y * sa, q.x * sa + q.y * ca);
	float e = length(q / rock_radii) + (vnoise(p * 0.03) - 0.5) * 0.08;
	// Place (ville) puis anneau de néon (mégapole).
	float plaza = (1.0 - smoothstep(1.45, 1.5, e)) * paved;
	col = mix(col, mix(vec3(0.68, 0.66, 0.62), vec3(0.74, 0.72, 0.68), step(0.5, fract(e * 6.0))), plaza);
	col += vec3(0.1, 0.6, 0.8) * urban * (1.0 - smoothstep(0.02, 0.06, abs(e - 1.47))) * (0.6 + 0.4 * sin(TIME * 2.0));
	// Ombre portée vers le bas-droite.
	vec2 qs = (p - rock_pos - vec2(12.0, 16.0));
	qs = vec2(qs.x * ca - qs.y * sa, qs.x * sa + qs.y * ca);
	float shadow = 1.0 - smoothstep(0.9, 1.05, length(qs / rock_radii));
	col *= 1.0 - shadow * 0.35;
	rock_mask = 1.0 - smoothstep(0.96, 1.0, e);
	float light = clamp(0.85 - dot(normalize(q + 1e-3), vec2(0.6, 0.6)) * 0.15 * smoothstep(0.4, 1.0, e), 0.6, 1.0);
	vec3 stone = mix(vec3(0.74, 0.71, 0.64), vec3(0.84, 0.81, 0.74), vnoise(p * 0.06)) * light;
	stone *= 1.0 - 0.25 * (1.0 - smoothstep(0.0, 0.04, abs(vnoise(p * 0.035) - 0.5))); // fissures
	col = mix(col, stone, rock_mask);
	return col;
}

void fragment() {
	vec2 p = world_pos;
	vec2 uv = p / parcel_size;
	vec2 sp = p + seed_offset * 1000.0;

	float n1 = fbm(sp * 0.004);
	float n2 = fbm(sp * 0.0017 + 31.0);

	// Fondu entre les deux états de sol, par dissolution irrégulière.
	float dissolve = fbm(sp * 0.005 + 77.0);
	float t = smoothstep(dissolve - 0.1, dissolve + 0.1, blend * 1.4 - 0.2);

	vec3 col = mix(ground_color(kind_a, sp, uv, n1, n2, wear_a), ground_color(kind_b, sp, uv, n1, n2, wear_b), t);
	float liquid = mix(is_liquid(kind_a) ? 1.0 : 0.0, is_liquid(kind_b) ? 1.0 : 0.0, t);

	// Herbe fine : petit grain qui casse les aplats.
	col *= 0.93 + 0.14 * vnoise(sp * 0.35) * (1.0 - liquid);

	// Repères permanents : la rivière (sauf sous l'océan) et le rocher.
	float paved = mix(kind_a == PAVED || kind_a == URBAN ? 1.0 : 0.0, kind_b == PAVED || kind_b == URBAN ? 1.0 : 0.0, t);
	float urban = mix(kind_a == URBAN ? 1.0 : 0.0, kind_b == URBAN ? 1.0 : 0.0, t);
	float river_mask = 0.0;
	float river_d = 0.0;
	vec3 with_river = apply_river(col, p, n1, urban, river_mask, river_d);
	col = mix(with_river, col, liquid);
	river_mask *= 1.0 - liquid;
	float rock_mask = 0.0;
	col = apply_rock(col, p, paved, urban, rock_mask);
	float clear_ground = (1.0 - river_mask) * (1.0 - rock_mask);

	// Mares et ruisseaux selon l'humidité.
	float pond_noise = fbm(sp * 0.0026 + 40.0);
	float wet = clamp((water - 0.35) / 0.65, 0.0, 1.0);
	float pond_thr = mix(1.02, 0.5, wet);
	float pond = smoothstep(pond_thr, pond_thr + 0.015, pond_noise) * (1.0 - liquid) * clear_ground;
	float shore = smoothstep(pond_thr - 0.03, pond_thr, pond_noise) * (1.0 - pond) * (1.0 - liquid) * clear_ground;
	vec3 pond_col = mix(vec3(0.10, 0.30, 0.44), vec3(0.16, 0.40, 0.52), n1)
		+ 0.03 * sin(TIME * 1.4 + pond_noise * 60.0);
	col = mix(col, col * 0.75 + vec3(0.04, 0.03, 0.0), shore * 0.6);
	col = mix(col, pond_col, pond);

	// Végétation : couronnes d'arbres dont la couverture suit parcel.vegetation.
	float near_landmark = smoothstep(0.0, 1.0, (river_d - river_width * 0.5 - 6.0) / 14.0);
	float density = clamp(vegetation * mix(veg_a, veg_b, t), 0.0, 1.0) * (1.0 - pond) * (1.0 - rock_mask) * mix(1.0, near_landmark, river_state.x);
	vec2 sway = vec2(sin(TIME * 0.8 + p.y * 0.01), cos(TIME * 0.6 + p.x * 0.01)) * 1.2;
	float canopy = fbm(sp * 0.021 + sway * 0.021 + 5.0);
	float thr = mix(0.92, 0.3, density);
	float tree = smoothstep(thr, thr + 0.05, canopy);
	float shadow = smoothstep(thr, thr + 0.05, fbm((sp + vec2(-7.0, -9.0)) * 0.021 + 5.0)) * (1.0 - tree);
	vec3 leaves = mix(tree_color(kind_a), tree_color(kind_b), t);
	float fall = autumn * mix(deciduous(kind_a), deciduous(kind_b), t);
	vec3 fall_col = mix(vec3(0.85, 0.45, 0.1), vec3(0.7, 0.18, 0.08), vnoise(sp * 0.03 + 3.0));
	leaves = mix(leaves, fall_col, fall * smoothstep(0.3, 0.6, vnoise(sp * 0.015 + 9.0) + autumn * 0.4));
	leaves *= 0.8 + 0.6 * clamp((canopy - thr) * 5.0, 0.0, 1.0);
	col = mix(col, col * 0.6, shadow * 0.7 * step(0.001, density));
	col = mix(col, leaves, tree * step(0.001, density));

	// Neige saisonnière (sol puis cimes) ; mares gelées.
	float snow = snow_cover * (1.0 - liquid) * (1.0 - river_mask);
	col = mix(col, vec3(0.92, 0.95, 0.99) - 0.06 * n2, snow * smoothstep(0.25, 0.6, n1 + snow * 0.5));
	col = mix(col, vec3(0.75, 0.86, 0.95), pond * smoothstep(0.4, 0.8, snow_cover));

	// Ombres de nuages qui dérivent.
	float cloud = fbm(sp * 0.0012 + TIME * vec2(0.012, 0.005));
	col *= 1.0 - smoothstep(0.58, 0.78, cloud) * 0.2;

	// Halo de pollution lumineuse des parcelles très technologiques.
	col += vec3(0.05, 0.04, 0.08) * smoothstep(0.7, 1.0, tech);

	COLOR = vec4(col, 1.0);
}
