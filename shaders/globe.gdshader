shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;
// Planète vue en 3D : tout est calculé par pixel à partir des grilles de WorldSim
// (src/globe/globe_textures.gd). La position sur la sphère (espace objet, rayon 1) donne la
// latitude / longitude, donc les UV équirectangulaires : aucune couture de maillage.
//   data_tex     : R = élévation (-1..1), G = température (0..1), B = population (0..1), A = tech (0..1)
//   species_tex  : R = espèce dominante terrestre (-1 = aucune), G = vivante, B = sapiente
//   aux_tex      : R = vie marine, G = vie terrestre, B = espèce marine principale, A = plaque (-1)
//   prev_elev_tex: élévation avant le dernier changement de géographie (fondu geo_fade 0 -> 1)
// Mêmes conventions que src/globe/globe_math.gd.

uniform sampler2D data_tex : filter_linear, repeat_enable;
uniform sampler2D species_tex : filter_nearest, repeat_enable;
uniform sampler2D aux_tex : filter_nearest, repeat_enable;
// Même texture, filtrée : densités de vie lissées (les identifiants restent lus sans filtrage).
uniform sampler2D aux_smooth : filter_linear, repeat_enable;
uniform sampler2D prev_elev_tex : filter_linear, repeat_enable;
uniform float geo_fade = 1.0;
uniform vec2 grid_size = vec2(256.0, 128.0);

// 0 nature, 1 vie, 2 température, 3 ozone, 4 plaques, 5 espèces, 6 civilisations
uniform int layer = 0;
uniform float anim_time = 0.0;
uniform vec3 sun_dir = vec3(0.0, 0.0, 1.0);
// 0 en orbite haute, 1 au ras du sol.
uniform float detail = 0.0;

// État global de la planète (WorldSim) : 0..1 sauf sea_level (unités d'élévation).
uniform float oxygen = 1.0;
uniform float ozone = 1.0;
uniform float greenhouse = 0.0;
uniform float land_flora = 1.0;
uniform float snowball = 0.0;
uniform float sea_level = 0.0;
// Teinte de l'atmosphère vue en bord de disque (suit l'oxygène, calculée par globe.gd).
uniform vec3 atmo_color = vec3(0.3, 0.55, 1.0);

uniform int selected_species = -1;
// Aperçu de la zone d'effet du pouvoir (direction, rayon angulaire).
uniform vec3 cursor_dir = vec3(0.0, 0.0, 1.0);
uniform float cursor_angle = 0.05;
uniform vec4 cursor_color : source_color = vec4(1.0);
uniform float cursor_visible = 0.0;
// Lieu suivi (vue rapprochée) et épingles.
uniform vec3 parcel_dir = vec3(0.0, 0.0, 1.0);
uniform float parcel_visible = 1.0;
uniform vec3 pins[16];
uniform int pin_count = 0;
// 8 impacts : direction x, y, z, instant de départ, type de pouvoir (-1 = inactif).
uniform float impact_data[40];
uniform float flash = 0.0;

varying vec3 obj_pos;
varying vec3 cam_obj;

void vertex() {
	obj_pos = VERTEX;
	cam_obj = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}

// --- Bruit 3D (continu sur la sphère, sans couture ni pincement aux pôles) ---

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(hash13(i), hash13(i + vec3(1, 0, 0)), u.x);
	float b = mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), u.x);
	float c = mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), u.x);
	float d = mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), u.x);
	return mix(mix(a, b, u.y), mix(c, d, u.y), u.z);
}

float fbm3(vec3 p, int octaves) {
	float s = 0.0;
	float a = 0.5;
	float norm = 0.0;
	for (int i = 0; i < octaves; i++) {
		s += a * noise3(p);
		norm += a;
		p = p * 2.03 + vec3(17.1, 3.7, 9.2);
		a *= 0.5;
	}
	return s / norm;
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

// DOIT rester identique à MapMath.species_color() (src/map/map_math.gd).
vec3 species_color(float id) {
	float h = fract(id * 0.618034 + 0.13);
	return hsv2rgb(vec3(h, 0.75, 0.95));
}

vec3 plate_color(float id) {
	return hsv2rgb(vec3(fract(id * 0.381966 + 0.57), 0.55, 0.85));
}

// Couleurs des pouvoirs (ordre de src/map/divine_powers.gd).
vec3 power_color(int kind) {
	if (kind == 0) return vec3(1.0, 0.55, 0.15);
	if (kind == 1) return vec3(0.85, 0.05, 0.12);
	if (kind == 2) return vec3(0.9, 0.95, 1.0);
	if (kind == 3) return vec3(1.0, 0.85, 0.3);
	if (kind == 4) return vec3(0.45, 0.9, 0.15);
	if (kind == 5) return vec3(0.7, 0.4, 1.0);
	if (kind == 6) return vec3(0.15, 0.5, 1.0);
	if (kind == 7) return vec3(0.65, 0.95, 1.0);
	return vec3(0.4, 1.0, 0.6);
}

vec3 biome_color(float e, float t, float moist) {
	vec3 ice = vec3(0.92, 0.95, 0.98);
	vec3 tundra = vec3(0.55, 0.56, 0.48);
	vec3 taiga = vec3(0.17, 0.33, 0.22);
	vec3 grass = vec3(0.42, 0.6, 0.25);
	vec3 forest = vec3(0.16, 0.42, 0.16);
	vec3 desert = vec3(0.86, 0.74, 0.48);
	vec3 savanna = vec3(0.66, 0.62, 0.3);
	vec3 jungle = vec3(0.07, 0.36, 0.12);
	vec3 rock = vec3(0.45, 0.4, 0.36);
	vec3 snow = vec3(0.96, 0.97, 1.0);
	vec3 sand = vec3(0.88, 0.82, 0.6);
	vec3 temperate = mix(grass, forest, smoothstep(0.4, 0.65, moist));
	vec3 hot = mix(desert, savanna, smoothstep(0.3, 0.5, moist));
	hot = mix(hot, jungle, smoothstep(0.55, 0.75, moist));
	vec3 col = mix(tundra, taiga, smoothstep(0.2, 0.3, t));
	col = mix(col, temperate, smoothstep(0.36, 0.46, t));
	col = mix(col, hot, smoothstep(0.66, 0.78, t));
	col = mix(col, sand, (1.0 - smoothstep(0.0, 0.025, e)) * smoothstep(0.3, 0.45, t) * 0.8);
	col = mix(col, rock, smoothstep(0.45, 0.7, e));
	col = mix(col, snow, smoothstep(0.72, 0.85, e + (0.5 - t) * 0.4));
	col = mix(col, ice, 1.0 - smoothstep(0.08, 0.16, t));
	return col;
}

// Terres sans plantes : basaltes sombres, régolithe ocre, coulées.
vec3 bare_color(float e, float n) {
	vec3 basalt = vec3(0.24, 0.22, 0.21);
	vec3 ochre = vec3(0.52, 0.36, 0.26);
	vec3 col = mix(basalt, ochre, smoothstep(0.35, 0.65, n));
	return mix(col, vec3(0.55, 0.52, 0.5), smoothstep(0.5, 0.85, e));
}

vec3 heat_ramp(float x) {
	vec3 c = mix(vec3(0.02, 0.01, 0.08), vec3(0.45, 0.05, 0.5), smoothstep(0.0, 0.33, x));
	c = mix(c, vec3(0.95, 0.35, 0.1), smoothstep(0.33, 0.66, x));
	return mix(c, vec3(1.0, 0.95, 0.6), smoothstep(0.66, 1.0, x));
}

vec3 temp_ramp(float x) {
	vec3 c = mix(vec3(0.1, 0.15, 0.6), vec3(0.2, 0.7, 0.95), smoothstep(0.0, 0.3, x));
	c = mix(c, vec3(0.3, 0.8, 0.3), smoothstep(0.3, 0.5, x));
	c = mix(c, vec3(0.98, 0.85, 0.2), smoothstep(0.5, 0.7, x));
	return mix(c, vec3(0.85, 0.12, 0.08), smoothstep(0.7, 1.0, x));
}

vec3 ozone_ramp(float x) {
	vec3 c = mix(vec3(0.35, 0.05, 0.4), vec3(0.15, 0.3, 0.85), smoothstep(0.0, 0.35, x));
	c = mix(c, vec3(0.2, 0.75, 0.6), smoothstep(0.35, 0.7, x));
	return mix(c, vec3(0.9, 0.95, 0.5), smoothstep(0.7, 1.0, x));
}

vec2 dir_to_uv(vec3 d) {
	float lat = asin(clamp(d.y, -1.0, 1.0));
	float lon = atan(d.x, d.z);
	return vec2(fract(lon / TAU), 0.5 - lat / PI);
}

float cloud_density(vec3 p) {
	// Rotation lente autour de l'axe des pôles (vents d'ouest) + déformation par un second bruit.
	float a = anim_time * 0.006;
	vec3 q = vec3(p.x * cos(a) - p.z * sin(a), p.y, p.x * sin(a) + p.z * cos(a));
	float w = fbm3(q * 2.2 + vec3(0.0, anim_time * 0.01, 0.0), 3);
	float c = fbm3(q * 3.5 + vec3(w * 1.8, w * 0.6, -w), 5);
	float lat = abs(p.y);
	float band = 0.06 * cos(lat * PI * 3.0);
	return smoothstep(0.56 - band, 0.78 - band, c);
}

void fragment() {
	vec3 p = normalize(obj_pos);
	vec2 uv = dir_to_uv(p);
	vec2 texel = 1.0 / grid_size;
	vec2 suv = vec2(uv.x, clamp(uv.y, texel.y * 0.5, 1.0 - texel.y * 0.5));
	float lat = asin(clamp(p.y, -1.0, 1.0));
	float lon = atan(p.x, p.z);
	vec3 east = vec3(cos(lon), 0.0, -sin(lon));
	vec3 north = vec3(-sin(lat) * sin(lon), cos(lat), -sin(lat) * cos(lon));

	vec4 d = textureLod(data_tex, suv, 0.0);
	vec4 sp = textureLod(species_tex, suv, 0.0);
	vec4 aux = textureLod(aux_tex, suv, 0.0);
	vec2 life_d = textureLod(aux_smooth, suv, 0.0).rg;
	aux.rg = life_d;
	float elev_now = d.r;
	float elev_prev = textureLod(prev_elev_tex, suv, 0.0).r;
	float elev0 = mix(elev_prev, elev_now, geo_fade) - sea_level;

	// Détail de relief qui apparaît en descendant vers le sol.
	float fine = fbm3(p * 90.0, 4) - 0.5;
	float coarse = fbm3(p * 18.0, 3) - 0.5;
	float elev = elev0 + coarse * 0.06 + fine * 0.05 * (0.3 + detail);
	float temp = d.g;
	float pop = d.b;
	float tech = d.a;
	float moist = fbm3(p * 4.0 + vec3(40.0), 4);
	bool ocean = elev < 0.0;

	// Normale perturbée par le relief (différences finies est / nord).
	float eE = textureLod(data_tex, suv + vec2(texel.x, 0.0), 0.0).r;
	float eW = textureLod(data_tex, suv - vec2(texel.x, 0.0), 0.0).r;
	float eN = textureLod(data_tex, suv - vec2(0.0, texel.y), 0.0).r;
	float eS = textureLod(data_tex, suv + vec2(0.0, texel.y), 0.0).r;
	// Près des pôles, les voisins en longitude se resserrent : relief atténué pour éviter un pincement.
	float bump = ocean ? 0.0 : 2.2 * smoothstep(0.02, 0.2, cos(lat));
	vec3 n = normalize(p - bump * ((eE - eW) * 0.5 * east + (eN - eS) * 0.5 * north)
		- (ocean ? 0.0 : 0.35) * (coarse * east + fine * north) * (0.4 + detail));

	vec3 view = normalize(cam_obj - obj_pos);
	vec3 sun = normalize(sun_dir);
	float cosz = dot(p, sun);
	float day = smoothstep(-0.08, 0.16, cosz);
	float twilight = exp(-cosz * cosz * 60.0);
	float ox = smoothstep(0.03, 0.4, oxygen);

	vec3 col;
	if (ocean) {
		float depth = clamp(-elev, 0.0, 1.0);
		// Mer oxygénée bleue ; mer anoxique riche en fer, rouge-orangé, avant l'oxygène.
		vec3 shallow = mix(vec3(0.62, 0.32, 0.12), vec3(0.08, 0.42, 0.55), ox);
		vec3 deep = mix(vec3(0.26, 0.09, 0.05), vec3(0.01, 0.06, 0.2), ox);
		col = mix(shallow, deep, smoothstep(0.0, 0.35, depth));
		// Vie marine : efflorescences de plancton (vert-turquoise) ou tapis microbiens (vert olive).
		vec3 bloom = mix(vec3(0.35, 0.42, 0.12), vec3(0.08, 0.5, 0.38), ox);
		float mlife = aux.r * (0.6 + 0.4 * fbm3(p * 30.0 + vec3(anim_time * 0.02), 3));
		col = mix(col, bloom, clamp(mlife * 0.55, 0.0, 0.55));
		// Houle au ras de l'eau.
		float waves = noise3(p * 600.0 + vec3(anim_time * 0.4, 0.0, anim_time * 0.3));
		col *= 0.92 + waves * 0.16 * detail;
		// Banquise.
		float sea_ice = 1.0 - smoothstep(0.06, 0.13, temp + coarse * 0.08);
		col = mix(col, vec3(0.86, 0.92, 0.97), max(sea_ice, snowball * 0.95));
	} else {
		vec3 green = biome_color(clamp(elev, 0.0, 1.0), temp, moist);
		vec3 bare = bare_color(clamp(elev, 0.0, 1.0), fbm3(p * 9.0, 3));
		float veg = clamp(land_flora, 0.0, 1.0);
		// Les terres glacées restent blanches même sans plantes.
		float icy = 1.0 - smoothstep(0.08, 0.16, temp);
		col = mix(mix(bare, green, veg), vec3(0.93, 0.95, 0.98), icy * (1.0 - veg));
		col = mix(col, vec3(0.93, 0.95, 0.98), snowball * 0.95);
	}

	// --- Vie, espèces et civilisations ---
	float id = sp.r;
	float has_sp = step(0.0, id) * sp.g;
	float sapient = sp.b * has_sp;
	float marine_id = aux.b;
	float shown_id = ocean ? marine_id : id;
	float shown_has = ocean ? step(0.0, marine_id) * step(0.02, aux.r) : has_sp;
	vec3 scol = species_color(shown_id);
	float off = 0.6;
	float nb_id = ocean ? textureLod(aux_tex, suv + vec2(off * texel.x, 0.0), 0.0).b
		: textureLod(species_tex, suv + vec2(off * texel.x, 0.0), 0.0).r;
	float nb_id2 = ocean ? textureLod(aux_tex, suv + vec2(0.0, off * texel.y), 0.0).b
		: textureLod(species_tex, suv + vec2(0.0, off * texel.y), 0.0).r;
	float border = max(step(0.5, abs(nb_id - shown_id)), step(0.5, abs(nb_id2 - shown_id))) * shown_has;
	float selected = (selected_species >= 0 && abs(shown_id - float(selected_species)) < 0.5) ? 1.0 : 0.0;
	float sel_pulse = selected * (0.5 + 0.5 * sin(anim_time * 4.0)) * shown_has;
	float urban = sapient * pop * tech;
	float data_layer = layer == 0 ? 0.0 : 1.0;
	float lum = dot(col, vec3(0.3, 0.59, 0.11));

	if (layer == 0) {
		col = mix(col, vec3(0.42, 0.4, 0.38), clamp(urban * 1.4, 0.0, 0.6) * (ocean ? 0.0 : 1.0));
		col = mix(col, scol, border * 0.35 * sapient);
		col = mix(col, vec3(1.0), sel_pulse * 0.3);
	} else if (layer == 1) {
		// Vie : terrestre en vert, marine en cyan, intensité selon la densité.
		vec3 base = vec3(lum) * 0.3;
		vec3 life = ocean ? vec3(0.1, 0.75, 0.9) * aux.r : vec3(0.35, 0.95, 0.25) * max(aux.g, pop * has_sp);
		col = base + life * 1.1;
	} else if (layer == 2) {
		col = mix(temp_ramp(temp), vec3(lum), 0.25) * (ocean ? 0.8 : 1.0);
		float iso = abs(fract(temp * 10.0) - 0.5);
		col = mix(col, vec3(0.05), (1.0 - smoothstep(0.0, fwidth(temp * 10.0) * 1.5, 0.5 - iso)) * 0.4);
	} else if (layer == 3) {
		// Ozone : couche plus mince aux pôles ; les terres exposées aux UV sont hachurées.
		float o = clamp(ozone * (0.7 + 0.3 * cos(lat * 2.0)), 0.0, 1.0);
		col = mix(ozone_ramp(o), vec3(lum), 0.3);
		float hatch = step(0.5, fract((p.x + p.y + p.z) * 160.0));
		col = mix(col, vec3(0.6, 0.1, 0.7), (1.0 - smoothstep(0.15, 0.4, o)) * hatch * (ocean ? 0.0 : 0.35));
	} else if (layer == 4) {
		// Plaques tectoniques (si la simulation les expose), frontières en surbrillance.
		float pid = aux.a;
		if (pid < 0.0) {
			col = vec3(lum) * 0.6;
		} else {
			col = mix(plate_color(pid), vec3(lum), 0.35);
			float pe = textureLod(aux_tex, suv + vec2(texel.x, 0.0), 0.0).a;
			float pn = textureLod(aux_tex, suv + vec2(0.0, texel.y), 0.0).a;
			float edge = max(step(0.5, abs(pe - pid)), step(0.5, abs(pn - pid)));
			col = mix(col, vec3(1.0, 0.45, 0.2), edge * 0.85);
		}
	} else if (layer == 5) {
		vec3 base = vec3(lum) * 0.3;
		float dens = ocean ? aux.r : pop;
		vec3 c = scol * (0.35 + 0.65 * smoothstep(0.0, 0.8, dens));
		col = mix(base, c, shown_has * smoothstep(0.0, 0.05, dens));
		col = mix(col, scol * 1.3, border * 0.8);
		col = mix(col, vec3(1.0), sel_pulse * 0.35);
	} else {
		// Civilisations : territoires des espèces conscientes et chaleur technologique.
		vec3 base = vec3(lum) * 0.25;
		col = mix(base, species_color(id) * 0.8, sapient * smoothstep(0.0, 0.1, pop) * 0.7);
		col += heat_ramp(tech) * smoothstep(0.0, 0.03, tech) * sapient * 0.8;
		col = mix(col, species_color(id) * 1.3, border * sapient);
	}

	// --- Nuages et ombre ---
	float cloud_alpha = mix(0.85, 0.25, data_layer) * (1.0 - 0.6 * smoothstep(0.4, 1.0, detail));
	float clouds = cloud_density(p) * cloud_alpha;
	float cloud_shadow = cloud_density(normalize(p - sun * 0.01)) * cloud_alpha;
	col *= 1.0 - cloud_shadow * 0.3 * day;

	// --- Éclairage ---
	float diffuse = clamp(dot(n, sun), 0.0, 1.0);
	// Clair de lune : la face de nuit reste lisible, davantage près du sol.
	float min_light = mix(mix(0.45, 0.85, detail), 0.7, data_layer);
	vec3 night_tint = vec3(0.55, 0.62, 0.9);
	vec3 lit_day = col * (0.22 + 0.95 * diffuse);
	vec3 lit = mix(col * night_tint * min_light, mix(lit_day, col, data_layer * 0.6), day);
	lit += col * vec3(1.0, 0.42, 0.12) * twilight * 0.3 * (1.0 - data_layer);
	if (ocean && layer == 0) {
		vec3 r = reflect(-sun, n);
		float spec = pow(max(dot(r, view), 0.0), 70.0);
		lit += vec3(1.0, 0.92, 0.75) * spec * day * 0.9 * (1.0 - snowball);
	}
	vec3 ccol = mix(vec3(0.05, 0.06, 0.1), vec3(1.0), day) + vec3(1.0, 0.5, 0.25) * twilight * 0.4;
	lit = mix(lit, ccol, clouds * 0.9);

	// --- Lumières des villes, côté nuit ---
	if (urban > 0.0005) {
		float dots = smoothstep(0.42, 0.8, noise3(p * 900.0));
		float clusters = smoothstep(0.3, 0.7, noise3(p * 160.0));
		float amount = pow(urban, 0.7) * (clusters * (0.4 + dots) + 0.1) * 3.0;
		vec3 warm = vec3(1.0, 0.68, 0.3);
		vec3 neon = mix(vec3(1.0, 0.15, 0.85), vec3(0.1, 0.95, 1.0), step(0.5, noise3(p * 400.0)));
		vec3 lcol = mix(warm, neon, smoothstep(0.8, 0.95, tech));
		lit += lcol * amount * (1.0 - day * 0.9) * (1.0 - clouds * 0.6) * (1.0 - data_layer * 0.7);
	}

	// --- Aurores : rideaux près des pôles, côté nuit. Vertes avec de l'oxygène, violettes sans. ---
	float alat = abs(lat);
	float aband = smoothstep(1.05, 1.17, alat) * (1.0 - smoothstep(1.25, 1.36, alat));
	if (aband > 0.0) {
		float curtain = noise3(vec3(lon * 6.0, anim_time * 0.25, alat * 3.0));
		curtain = pow(smoothstep(0.45, 0.9, curtain), 1.5);
		float flicker = 0.7 + 0.3 * sin(anim_time * 1.7 + lon * 20.0);
		vec3 acol = mix(vec3(0.55, 0.25, 0.95), vec3(0.2, 1.0, 0.45), ox);
		lit += acol * aband * curtain * flicker * (1.0 - day) * 0.6;
	}

	// --- Impacts divins : onde de choc, boule de feu, brûlure ---
	for (int k = 0; k < 8; k++) {
		float kind = impact_data[k * 5 + 4];
		if (kind < 0.0) continue;
		float dt = anim_time - impact_data[k * 5 + 3];
		if (dt < 0.0 || dt > 30.0) continue;
		vec3 c = vec3(impact_data[k * 5], impact_data[k * 5 + 1], impact_data[k * 5 + 2]);
		float ang = acos(clamp(dot(p, c), -1.0, 1.0));
		int ik = int(kind + 0.5);
		vec3 pc = power_color(ik);
		if (dt < 4.0) {
			float r = dt * (ik == 0 ? 0.09 : 0.05);
			float ring = exp(-pow((ang - r) / (0.006 + dt * 0.004), 2.0)) * (1.0 - dt / 4.0);
			lit += pc * ring * 1.5;
		}
		if (ik == 0) {
			lit += vec3(1.0, 0.85, 0.6) * exp(-ang / 0.02) * exp(-dt * 2.0) * 4.0;
			// Cratère incandescent qui refroidit lentement.
			lit = mix(lit, vec3(1.0, 0.3, 0.05) * 1.5, exp(-ang / 0.012) * exp(-dt * 0.12) * 0.85);
		} else {
			lit += pc * exp(-ang / 0.025) * exp(-dt * 1.2) * 0.9;
		}
	}

	// --- Lieu suivi, épingles, aperçu de zone ---
	float pa = acos(clamp(dot(p, parcel_dir), -1.0, 1.0));
	float pr = mix(0.03, 0.006, detail);
	float pring = 1.0 - smoothstep(0.0, max(fwidth(pa) * 1.5, 1e-4), abs(pa - pr));
	float pulse = 0.6 + 0.4 * sin(anim_time * 3.0);
	lit = mix(lit, vec3(1.0, 0.85, 0.35), pring * pulse * parcel_visible);
	lit += vec3(1.0, 0.85, 0.35) * (1.0 - smoothstep(0.0, pr * 0.35, pa)) * parcel_visible;
	for (int i = 0; i < 16; i++) {
		if (i >= pin_count) break;
		float a = acos(clamp(dot(p, normalize(pins[i])), -1.0, 1.0));
		float r = mix(0.012, 0.003, detail);
		lit = mix(lit, vec3(0.45, 0.85, 1.0), 1.0 - smoothstep(r * 0.7, r, a));
	}
	if (cursor_visible > 0.0) {
		float a = acos(clamp(dot(p, normalize(cursor_dir)), -1.0, 1.0));
		float rad = max(cursor_angle, 0.004);
		float w = max(fwidth(a) * 1.5, 1e-4);
		float ring = 1.0 - smoothstep(0.0, w, abs(a - rad));
		vec3 t = normalize(cross(normalize(cursor_dir), p) + vec3(1e-5));
		float dash = step(0.4, fract(atan(dot(t, north), dot(t, east)) / TAU * 32.0 + anim_time * 0.4));
		float fill = (1.0 - smoothstep(rad - w, rad, a)) * 0.12;
		lit = mix(lit, cursor_color.rgb, clamp(ring * (0.45 + 0.55 * dash) + fill, 0.0, 1.0) * cursor_visible);
	}

	// Voile d'atmosphère au bord du disque, côté jour.
	float rim = pow(1.0 - clamp(dot(p, view), 0.0, 1.0), 3.0) * (1.0 - 0.7 * detail);
	lit += atmo_color * rim * (0.15 + 0.85 * smoothstep(-0.2, 0.3, cosz)) * 0.8;
	lit += vec3(1.0, 0.95, 0.85) * flash;
	// Couleurs pensées en sRGB (comme la carte 2D) : passage en linéaire pour le rendu 3D.
	ALBEDO = pow(max(lit, vec3(0.0)), vec3(2.2));
}
