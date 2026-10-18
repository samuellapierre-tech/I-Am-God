shader_type canvas_item;
// Vie d'ambiance entièrement calculée sur GPU (aucune mise à jour CPU par image) :
// kind 0 = vols de petits oiseaux en V, 1 = essaims d'insectes (lucioles la nuit),
// 2 = ombres de ptérosaures qui planent en cercles.
// Les instances sont posées à l'origine ; INSTANCE_CUSTOM : x = groupe, y = membre, z = graine.

uniform int kind = 0;
uniform vec2 parcel_size = vec2(1920.0, 1080.0);
uniform vec2 seed_offset = vec2(0.0);
uniform float night : hint_range(0.0, 1.0) = 0.0;
// Centres d'essaims (insectes) : posés par le CPU près de l'eau et de la végétation.
uniform vec2 swarm_centers[8];

varying vec2 local;
varying float flap;
varying float member_seed;

float h(vec2 p) {
	return fract(sin(dot(p + seed_offset * 37.0, vec2(127.1, 311.7))) * 43758.5453);
}

mat2 rot(float a) {
	return mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
}

void vertex() {
	float g = INSTANCE_CUSTOM.x;
	float m = INSTANCE_CUSTOM.y;
	member_seed = h(vec2(g, m));
	local = VERTEX * 2.0; // -1..1
	vec2 pos;
	float angle;
	float size;
	if (kind == 0) {
		float a0 = (h(vec2(g, 1.0)) * 2.0 - 1.0) * 0.6 + (h(vec2(g, 2.0)) > 0.5 ? PI : 0.0);
		vec2 dir = vec2(cos(a0), sin(a0));
		vec2 perp = vec2(-dir.y, dir.x);
		float period = 28.0 + 30.0 * h(vec2(g, 3.0));
		float s = fract(TIME / period + h(vec2(g, 4.0)));
		float span = length(parcel_size) + 500.0;
		vec2 center = parcel_size * 0.5 + perp * (h(vec2(g, 5.0)) - 0.5) * parcel_size.y * 0.8 + dir * (s - 0.5) * span;
		float row = floor((m + 1.0) * 0.5);
		float side = m < 0.5 ? 0.0 : (mod(m, 2.0) < 0.5 ? 1.0 : -1.0);
		vec2 wob = vec2(sin(TIME * 1.3 + m * 1.7), cos(TIME * 1.1 + m * 2.3)) * 4.0;
		pos = center - dir * row * 22.0 + perp * side * row * 16.0 + wob;
		angle = a0;
		size = 16.0;
		flap = sin(TIME * 13.0 + m * 1.9);
	} else if (kind == 1) {
		vec2 c = swarm_centers[int(g) % 8];
		float r = 18.0 + 22.0 * member_seed;
		float t = TIME * (0.8 + member_seed * 1.4);
		pos = c + vec2(sin(t + m * 2.1) * r, cos(t * 1.31 + m * 1.3) * r * 0.7)
			+ vec2(sin(TIME * 7.0 + m * 5.0), cos(TIME * 9.0 + m * 3.0)) * 2.0;
		angle = 0.0;
		size = mix(5.0, 14.0, night);
		flap = 0.5 + 0.5 * sin(TIME * (2.0 + member_seed * 3.0) + m * 7.0);
	} else {
		vec2 drift = vec2(cos(TIME * 0.021 + g * 2.0 + h(vec2(g, 1.0)) * 6.0), sin(TIME * 0.017 + g * 3.0)) * parcel_size * 0.33;
		vec2 c = parcel_size * 0.5 + drift;
		float dirn = h(vec2(g, 2.0)) > 0.5 ? 1.0 : -1.0;
		float a = TIME * 0.22 * dirn + g * 2.4;
		float radius = 160.0 + 120.0 * h(vec2(g, 3.0));
		pos = c + vec2(cos(a), sin(a)) * radius;
		angle = a + dirn * PI * 0.5;
		size = 120.0 + 40.0 * h(vec2(g, 4.0));
		flap = 0.25 * sin(TIME * 1.5 + g); // grands planeurs : quasi immobiles
	}
	VERTEX = rot(angle) * (VERTEX * size) + pos;
}

float ellipse(vec2 p, vec2 c, vec2 r) {
	return length((p - c) / r) - 1.0;
}

// Silhouette d'oiseau vue de dessus (ailes déployées selon flap), tête vers +x.
float bird(vec2 p, float f) {
	float body = ellipse(p, vec2(0.05, 0.0), vec2(0.4, 0.12));
	float span = 0.55 + 0.4 * f;
	vec2 q = vec2(p.x + abs(p.y) * 0.35, abs(p.y));
	float wing = ellipse(q, vec2(0.0, span * 0.5), vec2(0.17, span * 0.5));
	return min(body, wing);
}

void fragment() {
	vec2 p = local;
	if (kind == 0) {
		float d = bird(p, flap);
		float a = 1.0 - smoothstep(-0.05, 0.08, d);
		COLOR = vec4(vec3(0.12, 0.11, 0.12) * (1.0 - 0.5 * night), a * 0.9);
	} else if (kind == 1) {
		float d = length(p);
		if (night > 0.3) {
			float glow = (1.0 - smoothstep(0.0, 1.0, d)) * flap;
			float core = 1.0 - smoothstep(0.0, 0.25, d);
			COLOR = vec4(vec3(0.85, 1.0, 0.35) * (0.6 + core), max(glow * 0.55, core) * night * flap);
		} else {
			COLOR = vec4(vec3(0.1, 0.09, 0.07), (1.0 - smoothstep(0.3, 0.6, d)) * 0.75);
		}
	} else {
		// Ombre floue : on adoucit le bord selon la distance.
		float d = bird(p * vec2(1.0, 0.9), 0.6 + flap);
		float a = 1.0 - smoothstep(-0.15, 0.2, d);
		COLOR = vec4(vec3(0.0), a * 0.22 * (1.0 - 0.6 * night));
	}
}
