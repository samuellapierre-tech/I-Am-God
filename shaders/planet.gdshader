shader_type canvas_item;
// Rendu GPU de la planète vue de haut (projection équirectangulaire, bouclage horizontal).
// Entrées : deux textures empaquetées par src/map/world_texture_packer.gd
//   data_tex    : R = élévation (-1..1), G = température (0..1), B = population (0..1), A = tech (0..1)
//   species_tex : R = id espèce dominante (-1 = aucune), G = vivante, B = sapiente
// Tout le reste (biomes, océans animés, nuages, jour/nuit, lumières des villes, étalonnage par ère,
// aperçu de zone d'effet, ondes de choc) est calculé ici, par pixel.

uniform sampler2D data_tex : filter_linear, repeat_enable;
uniform sampler2D species_tex : filter_nearest, repeat_enable;

uniform vec2 grid_size = vec2(256.0, 128.0);
uniform float cell_size = 8.0;
// 0 = biomes, 1 = espèces, 2 = technologie, 3 = température
uniform int layer = 0;
// Étalonnage par ère : transition douce de era_from vers era_to (era_t 0..1).
uniform int era_from = 0;
uniform int era_to = 0;
uniform float era_t = 1.0;
uniform float anim_time = 0.0;
// Longitude du soleil (0..1) et déclinaison saisonnière (-1..1).
uniform float sun_lon = 0.0;
uniform float season = 0.0;
uniform float zoom = 1.0;
uniform int selected_species = -1;
// Aperçu de la zone d'effet du pouvoir sélectionné (pixels monde).
uniform vec2 cursor_pos = vec2(0.0);
uniform float cursor_radius = 0.0;
uniform vec4 cursor_color : source_color = vec4(1.0);
uniform float cursor_visible = 0.0;
// 8 impacts : x, y (pixels monde), instant de départ, type de pouvoir (-1 = inactif).
uniform float impact_data[32];
// Éclair global (impact de météorite), 0..1.
uniform float flash = 0.0;

varying vec2 world_pos;


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// --- Bruit périodique en x (pour un monde qui boucle sans couture) ---
// La période doit être un entier (les noeuds du réseau sont aux coordonnées entières).

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float pnoise(vec2 p, float period) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float x0 = mod(i.x, period);
	float x1 = mod(i.x + 1.0, period);
	float a = hash12(vec2(x0, i.y));
	float b = hash12(vec2(x1, i.y));
	float c = hash12(vec2(x0, i.y + 1.0));
	float d = hash12(vec2(x1, i.y + 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float pfbm(vec2 p, float period, int octaves) {
	float s = 0.0;
	float a = 0.5;
	float norm = 0.0;
	for (int i = 0; i < octaves; i++) {
		s += a * pnoise(p, period);
		norm += a;
		p = p * 2.0 + vec2(0.0, 17.3);
		period *= 2.0;
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

// Couleurs des pouvoirs : meteor, extinct, save, bless, plague, uplift, flood, ice_age, spawn_species.
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

// --- Étalonnage par ère ---

void era_grade_params(int era, out vec3 tint, out float sat, out float con, out vec3 haze, out float haze_amt) {
	tint = vec3(1.0); sat = 1.0; con = 1.0; haze = vec3(0.5); haze_amt = 0.0;
	if (era == 0) { tint = vec3(1.02, 1.06, 0.9); sat = 1.3; con = 1.05; haze = vec3(0.6, 0.7, 0.4); haze_amt = 0.04; }
	else if (era == 1) { tint = vec3(1.0, 1.03, 0.95); sat = 1.12; }
	else if (era == 2) { tint = vec3(1.04, 1.0, 0.92); sat = 0.95; }
	else if (era == 3) { tint = vec3(1.1, 1.0, 0.84); sat = 0.88; con = 1.03; }
	else if (era == 4) { tint = vec3(0.98, 0.97, 0.94); sat = 0.72; con = 1.1; }
	else if (era == 5) { tint = vec3(1.08, 1.01, 0.86); sat = 1.0; con = 1.05; }
	else if (era == 6) { tint = vec3(1.0, 0.94, 0.84); sat = 0.68; con = 1.05; haze = vec3(0.45, 0.4, 0.33); haze_amt = 0.14; }
	else if (era == 7) { tint = vec3(1.0, 1.0, 1.03); sat = 1.06; con = 1.06; }
	else if (era == 8) { tint = vec3(0.82, 0.9, 1.18); sat = 1.25; con = 1.18; haze = vec3(0.2, 0.05, 0.3); haze_amt = 0.12; }
	else if (era == 9) { tint = vec3(1.05, 1.05, 1.12); sat = 0.6; con = 0.92; haze = vec3(0.9, 0.95, 1.0); haze_amt = 0.1; }
}

vec3 era_grade(vec3 col, int era) {
	vec3 tint; float sat; float con; vec3 haze; float haze_amt;
	era_grade_params(era, tint, sat, con, haze, haze_amt);
	col *= tint;
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(l), col, sat);
	col = (col - 0.5) * con + 0.5;
	if (era == 8) {
		// Cyberpunk : ombres sarcelle, hautes lumières magenta.
		col += mix(vec3(0.0, 0.06, 0.08), vec3(0.08, -0.02, 0.06), smoothstep(0.2, 0.8, l));
	}
	return mix(col, haze, haze_amt);
}

// Intensité des lumières urbaines selon l'ère (feux de camp -> mégalopoles).
float era_light(int era) {
	if (era <= 1) return 0.0;
	if (era == 2) return 0.05;
	if (era == 3) return 0.12;
	if (era == 4) return 0.16;
	if (era == 5) return 0.28;
	if (era == 6) return 1.1;
	if (era == 7) return 1.8;
	if (era == 8) return 2.6;
	return 2.2;
}

vec3 era_light_color(int era, float h, float t) {
	if (era <= 5) return vec3(1.0, 0.55, 0.2);
	if (era == 6) return vec3(1.0, 0.72, 0.32);
	if (era == 7) return vec3(1.0, 0.88, 0.62);
	if (era == 8) {
		// Néons : magenta / cyan, avec scintillement.
		vec3 neon = h < 0.5 ? vec3(1.0, 0.12, 0.85) : vec3(0.1, 0.95, 1.0);
		if (h > 0.9) neon = vec3(0.65, 0.2, 1.0);
		return neon * (0.8 + 0.2 * sin(t * 9.0 + h * 40.0));
	}
	return vec3(0.75, 0.95, 1.0) * (0.85 + 0.15 * sin(t * 2.0 + h * 10.0));
}

// --- Biomes ---

vec3 biome_color(float e, float t, float moist) {
	// e : altitude des terres (0..1), t : température (0..1), moist : humidité (0..1)
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

vec3 heat_ramp(float x) {
	// Rampe « inferno » simplifiée pour la couche technologie.
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

float wrapped_dx(float dx, float period) {
	return dx - round(dx / period) * period;
}

float cloud_density(vec2 uv) {
	vec2 cp = vec2(uv.x * 6.0, uv.y * 3.0);
	float w = pfbm(cp * 2.0 + vec2(anim_time * 0.012, 0.0), 12.0, 3);
	float c = pfbm(cp + vec2(anim_time * 0.02 + w * 1.6, w * 0.8), 6.0, 5);
	float lat = abs(uv.y - 0.5) * 2.0;
	// Plus de nuages à l'équateur et aux latitudes moyennes, moins sous les tropiques.
	float band = 0.05 * cos(lat * PI * 3.0);
	return smoothstep(0.6 - band, 0.8 - band, c);
}

void fragment() {
	vec2 world_px = grid_size * cell_size;
	vec2 uv = world_pos / world_px;
	vec3 col;

	if (uv.y < 0.0 || uv.y > 1.0) {
		// Hors de la carte : espace étoilé et halo atmosphérique au bord.
		float edge = uv.y < 0.0 ? -uv.y : uv.y - 1.0;
		vec2 sp = floor(world_pos / 2.0);
		float star = step(0.996, hash12(sp)) * (0.5 + 0.5 * sin(anim_time * 2.0 + hash12(sp + 3.1) * 50.0));
		col = vec3(0.01, 0.012, 0.03) + vec3(star);
		col += vec3(0.25, 0.5, 1.0) * exp(-edge * world_px.y / 6.0) * 0.6;
	} else {
		vec2 texel = 1.0 / grid_size;
		vec2 suv = vec2(uv.x, clamp(uv.y, texel.y * 0.5, 1.0 - texel.y * 0.5));
		vec4 d = texture(data_tex, suv);
		vec4 sp = texture(species_tex, suv);
		float detail_fade = smoothstep(0.4, 2.0, zoom);

		// Détail fin de relief (bruit périodique) ajouté à l'élévation de la simulation.
		float detail = pfbm(vec2(uv.x * grid_size.x * 0.5, uv.y * grid_size.y * 0.5), grid_size.x * 0.5, 4) - 0.5;
		float elev = d.r + detail * 0.07;
		float temp = d.g;
		float pop = d.b;
		float tech = d.a;
		float moist = pfbm(vec2(uv.x * 12.0, uv.y * 6.0 + 40.0), 12.0, 4);

		// Ombrage du relief (normale approchée par différences finies).
		float eL = texture(data_tex, suv - vec2(texel.x, 0.0)).r;
		float eR = texture(data_tex, suv + vec2(texel.x, 0.0)).r;
		float eU = texture(data_tex, suv - vec2(0.0, texel.y)).r;
		float eD = texture(data_tex, suv + vec2(0.0, texel.y)).r;
		vec3 n = normalize(vec3((eL - eR) * 3.0 + detail * 0.3, (eU - eD) * 3.0, 1.0));
		float shade = clamp(dot(n, normalize(vec3(-0.6, -0.6, 0.55))) * 1.2, 0.0, 1.4);

		// Jour / nuit : terminateur qui balaie la planète.
		float lat = (0.5 - uv.y) * PI;
		float lon = fract(uv.x) * TAU;
		float decl = season * 0.41;
		float cosz = sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(lon - sun_lon * TAU);
		float day = smoothstep(-0.1, 0.12, cosz);
		float twilight = exp(-cosz * cosz * 70.0);

		bool ocean = elev < 0.0;
		if (ocean) {
			float depth = clamp(-elev, 0.0, 1.0);
			col = mix(vec3(0.08, 0.42, 0.55), vec3(0.03, 0.14, 0.34), smoothstep(0.0, 0.12, depth));
			col = mix(col, vec3(0.01, 0.05, 0.18), smoothstep(0.15, 0.6, depth));
			// Vagues animées (bruit périodique qui dérive + houle sinusoïdale).
			vec2 wp = vec2(uv.x * grid_size.x * 1.5, uv.y * grid_size.y * 1.5);
			float w1 = pnoise(wp + vec2(anim_time * 0.6, anim_time * 0.2), grid_size.x * 1.5);
			float w2 = pnoise(wp * 2.0 - vec2(anim_time * 0.9, 0.0), grid_size.x * 3.0);
			float swell = sin(uv.x * TAU * 64.0 + uv.y * 90.0 + anim_time * 1.5) * 0.5 + 0.5;
			float waves = (w1 * 0.6 + w2 * 0.4) * 0.7 + swell * 0.3;
			col *= 0.88 + waves * 0.24 * mix(0.5, 1.0, detail_fade);
			// Reflet du soleil sur l'eau.
			col += vec3(1.0, 0.9, 0.7) * pow(max(cosz, 0.0), 40.0) * (0.3 + waves * 0.7) * 0.6;
			// Écume côtière.
			float coast = 1.0 - smoothstep(0.0, 0.05, depth);
			float foam = smoothstep(0.55, 0.8, w2 + coast * 0.5 + 0.15 * sin(anim_time * 2.0 + depth * 80.0));
			col = mix(col, vec3(0.9, 0.95, 1.0), foam * coast * 0.7);
			// Banquise quand l'océan gèle (âge glaciaire).
			float sea_ice = 1.0 - smoothstep(0.06, 0.13, temp + detail * 0.05);
			col = mix(col, vec3(0.85, 0.92, 0.97) * (0.85 + shade * 0.15), sea_ice);
		} else {
			col = biome_color(clamp(elev, 0.0, 1.0), temp, moist);
			col *= 0.55 + 0.55 * shade;
		}

		// --- Civilisations ---
		float id = sp.r;
		float has_sp = step(0.0, id) * sp.g;
		float sapient = sp.b * has_sp;
		vec3 scol = species_color(id);
		// Frontières : un voisin proche (à l'échelle de l'écran) appartient à une autre espèce.
		float off = clamp(fwidth(uv.x * grid_size.x) * 1.2, 0.04, 0.45);
		float border = 0.0;
		border = max(border, step(0.5, abs(texture(species_tex, suv + vec2(off * texel.x, 0.0)).r - id)));
		border = max(border, step(0.5, abs(texture(species_tex, suv - vec2(off * texel.x, 0.0)).r - id)));
		border = max(border, step(0.5, abs(texture(species_tex, suv + vec2(0.0, off * texel.y)).r - id)));
		border = max(border, step(0.5, abs(texture(species_tex, suv - vec2(0.0, off * texel.y)).r - id)));
		border *= has_sp;
		float occupied = has_sp * smoothstep(0.02, 0.4, pop);
		float selected = (selected_species >= 0 && abs(id - float(selected_species)) < 0.5) ? 1.0 : 0.0;
		float sel_pulse = selected * (0.5 + 0.5 * sin(anim_time * 4.0));

		float era_lights = mix(era_light(era_from), era_light(era_to), era_t);
		int era_now = era_t < 0.5 ? era_from : era_to;
		float urban = sapient * pop * tech;

		if (layer == 0) {
			// Biomes : teinte légère des territoires, frontières des espèces sapientes, villes grises le jour.
			col = mix(col, scol, occupied * (0.12 + 0.12 * sapient));
			col = mix(col, scol, border * (0.1 + 0.6 * sapient));
			col = mix(col, vec3(0.42, 0.4, 0.38), clamp(urban * 1.4, 0.0, 0.6) * (ocean ? 0.0 : 1.0));
			col = mix(col, vec3(1.0), sel_pulse * occupied * 0.25);
		} else if (layer == 1) {
			// Espèces : couleurs franches par espèce dominante, intensité selon la population.
			float l = dot(col, vec3(0.3, 0.59, 0.11));
			vec3 base = vec3(l) * 0.35;
			vec3 c = scol * (0.35 + 0.65 * smoothstep(0.0, 0.8, pop));
			col = mix(base, c, has_sp * smoothstep(0.0, 0.05, pop));
			col = mix(col, scol * 1.3, border * 0.85);
			col = mix(col, vec3(1.0), sel_pulse * has_sp * 0.35);
		} else if (layer == 2) {
			// Technologie : carte de chaleur.
			float l = dot(col, vec3(0.3, 0.59, 0.11));
			col = mix(vec3(l) * 0.25, heat_ramp(tech), smoothstep(0.0, 0.02, tech) * 0.9 + 0.1 * pop);
		} else {
			// Température : rampe froid -> chaud avec isothermes.
			float l = dot(col, vec3(0.3, 0.59, 0.11));
			col = mix(temp_ramp(temp), vec3(l), 0.25) * (ocean ? 0.75 : 1.0);
			float iso = abs(fract(temp * 10.0) - 0.5);
			col = mix(col, vec3(0.05), (1.0 - smoothstep(0.0, fwidth(temp * 10.0) * 1.5, 0.5 - iso)) * 0.4);
		}

		// --- Nuages (bruit animé) et leur ombre ---
		float data_layer = layer == 0 ? 0.0 : 1.0;
		float cloud_alpha = 0.8 * mix(1.0, 0.2, smoothstep(1.5, 4.5, zoom)) * mix(1.0, 0.2, data_layer);
		float clouds = cloud_density(uv) * cloud_alpha;
		float cloud_shadow = cloud_density(uv + vec2(0.004, 0.006)) * cloud_alpha;
		col *= 1.0 - cloud_shadow * 0.35 * day;

		// --- Éclairage jour / nuit ---
		float min_light = mix(0.2, 0.6, data_layer);
		vec3 night_tint = vec3(0.35, 0.45, 0.8);
		vec3 lit = col * mix(night_tint * min_light, vec3(1.0), day);
		lit += col * vec3(1.0, 0.45, 0.15) * twilight * 0.25 * (1.0 - data_layer);

		vec3 ccol = mix(vec3(0.08, 0.09, 0.14), vec3(1.0), day) + vec3(1.0, 0.5, 0.25) * twilight * 0.4;
		lit = mix(lit, ccol, clouds * 0.85);

		// --- Lumières des villes (côté nuit) ---
		if (era_lights > 0.0) {
			float h = hash12(floor(world_pos / max(cell_size * 0.25, 1.0)));
			vec2 lp = vec2(uv.x * grid_size.x * 4.0, uv.y * grid_size.y * 4.0);
			// Agglomérations (grande échelle) parsemées de points lumineux (petite échelle).
			float clusters = smoothstep(0.3, 0.75, pnoise(lp * 0.25 + 9.0, grid_size.x));
			float dots = smoothstep(0.45, 0.85, pnoise(lp, grid_size.x * 4.0));
			float pattern = clusters * mix(0.5, 0.35 + dots, smoothstep(0.6, 2.5, zoom)) + 0.1;
			float amount = sapient * pow(pop, 0.8) * (0.15 + 0.85 * tech) * era_lights * pattern;
			// Halo (« glow ») : moyenne de population * tech autour du pixel.
			float halo = 0.0;
			for (int k = 0; k < 6; k++) {
				float a = float(k) * TAU / 6.0;
				vec4 dd = texture(data_tex, suv + vec2(cos(a), sin(a)) * texel * 1.8);
				halo += dd.b * dd.a;
			}
			halo = halo / 6.0 * era_lights * 0.35;
			vec3 lcol = era_light_color(era_now, h, anim_time);
			float night = 1.0 - day * (era_now == 8 ? 0.65 : 0.92);
			float through = (1.0 - clouds * 0.6) * (1.0 - data_layer * 0.75);
			lit += lcol * (amount + halo) * night * through;
			// Cyberpunk / post-singularité : trame lumineuse des mégalopoles.
			if (era_now >= 8) {
				vec2 gp = world_pos / (cell_size * 0.5);
				vec2 fw = fwidth(gp) * 1.5;
				vec2 fp = abs(fract(gp) - 0.5);
				float grid = max(smoothstep(0.5 - fw.x, 0.5, fp.x), smoothstep(0.5 - fw.y, 0.5, fp.y));
				vec3 gcol = era_now == 8 ? vec3(0.1, 0.9, 1.0) : vec3(0.9, 0.95, 1.0);
				lit += gcol * grid * smoothstep(0.4, 0.8, tech) * sapient * pop * night * 0.8 * detail_fade;
			}
			// Les nuages diffusent la lumière des villes par en dessous.
			lit += lcol * halo * clouds * night * 0.5;
		}

		col = lit;
		// Étalonnage par ère (transition douce).
		col = mix(era_grade(col, era_from), era_grade(col, era_to), era_t);
	}

	// --- Impacts divins : éclair, onde de choc, cratère ---
	for (int k = 0; k < 8; k++) {
		float kind = impact_data[k * 4 + 3];
		if (kind < 0.0) continue;
		float dt = anim_time - impact_data[k * 4 + 2];
		if (dt < 0.0 || dt > 4.0) continue;
		vec2 dp = world_pos - vec2(impact_data[k * 4], impact_data[k * 4 + 1]);
		dp.x = wrapped_dx(dp.x, world_px.x);
		float dist = length(dp);
		int ik = int(kind + 0.5);
		vec3 pc = power_color(ik);
		float fade = 1.0 - dt / 4.0;
		float speed = ik == 0 ? 160.0 : 90.0;
		float r = dt * speed;
		float ring = exp(-pow((dist - r) / (6.0 + dt * 6.0), 2.0)) * fade;
		col += pc * ring * 1.2;
		if (ik == 0) {
			col += vec3(1.0, 0.9, 0.7) * exp(-dist / 40.0) * exp(-dt * 3.0) * 3.0;
			col = mix(col, vec3(1.0, 0.3, 0.05), exp(-dist / 14.0) * exp(-dt * 0.6) * 0.9);
		} else {
			col += pc * exp(-dist / 30.0) * exp(-dt * 1.5) * 0.8;
		}
	}

	// --- Aperçu de la zone d'effet ---
	if (cursor_visible > 0.0) {
		vec2 dp = world_pos - cursor_pos;
		dp.x = wrapped_dx(dp.x, world_px.x);
		float dist = length(dp);
		float rad = max(cursor_radius, cell_size * 0.5);
		float fw = fwidth(dist) * 1.5;
		float ring = 1.0 - smoothstep(0.0, fw * 1.5, abs(dist - rad));
		float dash = step(0.4, fract(atan(dp.y, dp.x) / TAU * 32.0 + anim_time * 0.4));
		float fill = (1.0 - smoothstep(rad - fw, rad, dist)) * 0.12;
		col = mix(col, cursor_color.rgb, clamp(ring * (0.45 + 0.55 * dash) + fill, 0.0, 1.0) * cursor_visible);
	}

	col += vec3(1.0, 0.95, 0.85) * flash;
	// Compression douce des hautes lumières (néons, éclairs) pour éviter l'écrêtage.
	col = mix(col, col / (1.0 + max(col - 0.8, vec3(0.0))), step(vec3(0.8), col));
	// Vignette légère.
	vec2 v = SCREEN_UV - 0.5;
	col *= 1.0 - 0.35 * pow(length(v) * 1.25, 3.0);
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
