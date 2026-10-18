shader_type canvas_item;
// Marques au sol éphémères (une seule MultiMesh, anneau de N instances) : empreintes, poussière,
// brûlures, éclaboussures. Le CPU n'écrit une instance qu'à sa naissance ; l'âge et le fondu
// sont calculés ici à partir de `now`.
// INSTANCE_CUSTOM (demi-flottants en 2D !) : x = date de naissance modulo WRAP (s), y = type
// (-1 = vide), z = durée de vie (s, < WRAP).
// Types : 0 empreinte, 1 poussière, 2 brûlure, 3 éclaboussure.

const float WRAP = 128.0;
uniform float now = 0.0; // modulo WRAP

float age_of(float birth) {
	return mod(now - birth + WRAP, WRAP);
}

varying vec4 custom;
varying vec4 tint;

void vertex() {
	custom = INSTANCE_CUSTOM;
	tint = COLOR;
	float k = clamp(age_of(INSTANCE_CUSTOM.x) / max(INSTANCE_CUSTOM.z, 0.001), 0.0, 1.0);
	int kind = int(INSTANCE_CUSTOM.y + 0.5);
	if (kind == 1) {
		VERTEX *= 0.5 + 1.2 * sqrt(k); // le nuage gonfle
	} else if (kind == 3) {
		VERTEX *= 0.3 + 1.0 * k;
	}
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float age = age_of(custom.x);
	float k = age / max(custom.z, 0.001);
	if (custom.y < -0.5 || k >= 1.0) {
		discard;
	}
	int kind = int(custom.y + 0.5);
	vec2 p = UV * 2.0 - 1.0;
	float a = 0.0;
	vec3 c = tint.rgb;
	if (kind == 0) {
		// Empreinte à trois doigts (tête vers +x) : talon + doigts.
		float heel = 1.0 - smoothstep(0.25, 0.32, length((p - vec2(-0.25, 0.0)) / vec2(1.0, 0.8)));
		float toes = 0.0;
		for (int i = -1; i <= 1; i++) {
			vec2 dir = normalize(vec2(1.0, float(i) * 0.6));
			vec2 q = p - vec2(-0.1, 0.0);
			float along = dot(q, dir);
			float side = abs(dot(q, vec2(-dir.y, dir.x)));
			toes = max(toes, (1.0 - smoothstep(0.08, 0.13, side)) * step(0.0, along) * (1.0 - smoothstep(0.55, 0.65, along)));
		}
		a = max(heel, toes) * 0.4 * (1.0 - k);
	} else if (kind == 1) {
		float d = length(p);
		float puff = (1.0 - smoothstep(0.2, 1.0, d)) * (0.7 + 0.3 * hash(floor(p * 4.0) + custom.x));
		a = puff * 0.45 * (1.0 - k) * (1.0 - k);
	} else if (kind == 2) {
		float d = length(p) + (hash(floor(p * 9.0)) - 0.5) * 0.15;
		a = (1.0 - smoothstep(0.5, 1.0, d)) * 0.7 * (1.0 - k * k);
		c = mix(vec3(0.05, 0.04, 0.03), vec3(1.0, 0.35, 0.05), (1.0 - smoothstep(0.0, 0.35, d)) * (1.0 - smoothstep(0.0, 0.3, k)));
	} else {
		float d = length(p);
		a = (smoothstep(0.7, 0.85, d) * (1.0 - smoothstep(0.85, 1.0, d))) * 0.6 * (1.0 - k);
	}
	COLOR = vec4(c, a * tint.a);
}
