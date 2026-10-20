shader_type sky;
// Fond spatial du globe : étoiles scintillantes, voie lactée discrète, Soleil.
// Près du sol, la coque d'atmosphère (globe_atmosphere.gdshader) recouvre ce fond.

uniform vec3 sun_dir = vec3(0.0, 0.0, 1.0);
uniform float time = 0.0;
// 0 dans l'espace, 1 au sol en plein jour : les étoiles s'effacent.
uniform float daylight_mask = 0.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 col = vec3(0.004, 0.005, 0.012);
	// Voie lactée : bande inclinée.
	float band = exp(-pow(dot(d, normalize(vec3(0.3, 1.0, 0.2))) * 3.2, 2.0));
	col += vec3(0.05, 0.05, 0.08) * band * (0.6 + 0.4 * hash13(floor(d * 90.0)));
	// Étoiles.
	vec3 cell = floor(d * 420.0);
	float h = hash13(cell);
	if (h > 0.9965) {
		vec3 center = (cell + 0.5) / 420.0;
		float s = 1.0 - smoothstep(0.0, 0.0018, length(d - normalize(center) * length(d)));
		float tw = 0.65 + 0.35 * sin(time * (1.0 + h * 5.0) + h * 60.0);
		vec3 tint = mix(vec3(1.0, 0.85, 0.7), vec3(0.75, 0.85, 1.0), hash13(cell + 7.0));
		col += tint * s * tw * (h - 0.9965) * 900.0;
	}
	col *= 1.0 - daylight_mask;
	// Soleil et halo.
	float sd = dot(d, normalize(sun_dir));
	col += vec3(1.0, 0.95, 0.85) * smoothstep(0.9996, 0.99985, sd) * 30.0;
	col += vec3(1.0, 0.8, 0.5) * pow(max(sd, 0.0), 400.0) * 1.5;
	COLOR = col;
}
