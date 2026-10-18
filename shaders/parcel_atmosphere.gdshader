shader_type canvas_item;
// Voile d'atmosphère au-dessus de la parcelle, en un seul passage plein écran :
// pluie, neige, cendres, feuilles qui tombent, brouillard, ciel d'orage, éclairs,
// et voiles divins (givre, miasme de peste, rayons dorés).
// Dessiné dans un CanvasLayer non assombri par la nuit : la luminosité est gérée ici (daylight).

uniform vec2 parcel_size = vec2(1920.0, 1080.0);
uniform float daylight : hint_range(0.0, 1.0) = 1.0;
uniform vec2 wind = vec2(0.25, 0.0);

uniform float rain : hint_range(0.0, 1.0) = 0.0;
uniform float snow : hint_range(0.0, 1.0) = 0.0;
uniform float ash : hint_range(0.0, 1.0) = 0.0;
uniform float leaves : hint_range(0.0, 1.0) = 0.0;
uniform float fog : hint_range(0.0, 1.0) = 0.0;
uniform float storm : hint_range(0.0, 1.0) = 0.0;
uniform float lightning : hint_range(0.0, 1.0) = 0.0;

uniform float frost : hint_range(0.0, 1.0) = 0.0;
uniform float miasma : hint_range(0.0, 1.0) = 0.0;
uniform vec2 miasma_center = vec2(960.0, 540.0);
uniform float golden : hint_range(0.0, 1.0) = 0.0;
uniform vec2 golden_center = vec2(960.0, 540.0);

varying vec2 world_pos;

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
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.07 + vec2(11.3, 7.9);
		a *= 0.5;
	}
	return s / 0.9375;
}

// Pose une couleur par-dessus l'accumulation (opérateur « over »).
void over(inout vec4 acc, vec3 c, float a) {
	a = clamp(a, 0.0, 1.0);
	acc.rgb = mix(acc.rgb, c, a / max(acc.a + a * (1.0 - acc.a), 1e-4));
	acc.a = acc.a + a * (1.0 - acc.a);
}

// Particules qui tombent : une par cellule, position aléatoire, glissement par le vent.
float flakes(vec2 p, vec2 cell_size, vec2 velocity, float radius, float density, float seed) {
	vec2 q = (p - velocity * TIME) / cell_size;
	vec2 id = floor(q);
	vec2 f = fract(q);
	float present = step(hash12(id + seed), density);
	vec2 c = vec2(hash12(id + seed + 3.1), hash12(id + seed + 7.7)) * 0.8 + 0.1;
	c.x += sin(TIME * 1.3 + hash12(id) * 6.28) * 0.08;
	return present * (1.0 - smoothstep(radius * 0.5, radius, length((f - c) * cell_size)));
}

void vertex() {
	world_pos = VERTEX;
}

void fragment() {
	vec2 p = world_pos;
	vec2 uv = p / parcel_size;
	float light = mix(0.35, 1.0, daylight);
	vec4 acc = vec4(0.0);

	// Ciel d'orage : assombrissement bleuté.
	over(acc, vec3(0.08, 0.1, 0.16), storm * 0.32);
	over(acc, vec3(0.3, 0.33, 0.4), rain * 0.1);

	// Brouillard qui dérive.
	if (fog > 0.001) {
		float n = fbm(p * 0.0025 + vec2(TIME * 0.015, TIME * 0.006));
		over(acc, vec3(0.82, 0.85, 0.88) * light, fog * smoothstep(0.25, 0.75, n) * 0.75);
	}

	// Pluie : traits obliques sur deux profondeurs.
	if (rain > 0.001) {
		for (int l = 0; l < 2; l++) {
			float fl = float(l);
			float slant = 0.22 + wind.x * 0.3;
			vec2 q = vec2(p.x + p.y * slant, p.y) / vec2(7.0 + fl * 4.0, 70.0 + fl * 40.0);
			q.y -= TIME * (14.0 + fl * 4.0);
			vec2 id = floor(q);
			vec2 f = fract(q);
			float x0 = hash12(id + fl * 17.0);
			float on = step(hash12(id.yx + fl * 5.0), rain * 0.55);
			float streak = (1.0 - smoothstep(0.0, 0.12, abs(f.x - x0))) * smoothstep(0.0, 0.5, f.y) * (1.0 - smoothstep(0.5, 1.0, f.y));
			over(acc, vec3(0.78, 0.84, 0.95) * light, streak * on * (0.45 - fl * 0.15));
		}
	}

	// Neige, cendres, feuilles mortes.
	if (snow > 0.001) {
		float s1 = flakes(p, vec2(46.0), vec2(wind.x * 60.0 - 10.0, 55.0), 4.0, snow * 0.7, 1.0);
		float s2 = flakes(p, vec2(70.0), vec2(wind.x * 80.0 + 8.0, 80.0), 6.0, snow * 0.5, 9.0);
		over(acc, vec3(0.97, 0.98, 1.0) * light, max(s1, s2) * 0.9);
		over(acc, vec3(0.9, 0.93, 0.97) * light, snow * 0.12);
	}
	if (ash > 0.001) {
		over(acc, vec3(0.32, 0.27, 0.24) * light, ash * 0.35);
		float a1 = flakes(p, vec2(52.0), vec2(wind.x * 30.0 + 6.0, 22.0), 3.5, ash * 0.8, 4.0);
		over(acc, vec3(0.55, 0.52, 0.5) * light, a1 * 0.8);
	}
	if (leaves > 0.001) {
		float l1 = flakes(p, vec2(110.0), vec2(wind.x * 90.0 + 25.0, 35.0), 5.0, leaves * 0.35, 13.0);
		over(acc, mix(vec3(0.85, 0.42, 0.1), vec3(0.75, 0.2, 0.08), hash12(floor(p / 110.0))) * light, l1 * 0.9);
	}

	// Givre divin : cristaux qui envahissent l'écran depuis les bords.
	if (frost > 0.001) {
		float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
		float crystals = fbm(p * 0.02) * 0.6 + vnoise(p * 0.12) * 0.4;
		float reach = frost * 0.55;
		float mask = 1.0 - smoothstep(reach - 0.08, reach, edge + crystals * 0.12);
		over(acc, mix(vec3(0.78, 0.9, 1.0), vec3(1.0), crystals), mask * (0.55 + 0.35 * crystals));
	}

	// Miasme de peste : brume verdâtre qui ondule autour du point frappé.
	if (miasma > 0.001) {
		float n = fbm(p * 0.004 + vec2(TIME * 0.05, -TIME * 0.03));
		float near = 1.0 - smoothstep(150.0, 750.0, length(p - miasma_center));
		over(acc, vec3(0.35, 0.55, 0.12), miasma * smoothstep(0.3, 0.8, n) * (0.25 + 0.5 * near));
	}

	// Bénédiction : rayons dorés obliques convergeant vers le point béni, poussière scintillante.
	if (golden > 0.001) {
		vec2 d = p - golden_center;
		float ang = atan(d.y, d.x);
		float beams = pow(0.5 + 0.5 * sin(ang * 9.0 + TIME * 0.6), 6.0);
		float fall = 1.0 - smoothstep(60.0, 900.0, length(d));
		over(acc, vec3(1.0, 0.85, 0.4), golden * beams * fall * 0.5);
		float sparkle = flakes(p, vec2(40.0), vec2(0.0, -20.0), 2.5, 0.4, 21.0) * fall;
		over(acc, vec3(1.0, 0.95, 0.7), golden * sparkle);
	}

	// Éclair : flash bleuté sur tout l'écran.
	over(acc, vec3(0.85, 0.9, 1.0), lightning * 0.6);

	COLOR = acc;
}
