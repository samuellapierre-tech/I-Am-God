shader_type canvas_item;
// Voile d'eau du prologue : la parcelle (sol + créatures) est vue à travers une mer chaude.
// Réfraction ondulante (texture d'écran), teinte et turbidité de l'époque (rouge-orangé avant
// l'oxygène, puis bleue), caustiques mouvantes, écume sur le rivage. Quand `submerged` baisse,
// les terres émergent d'abord sur les hauts-fonds (motif de relief), le rocher en premier.
// Dessiné dans le calque "Sky" (non assombri) : la lumière du jour est appliquée ici.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec2 parcel_size = vec2(1920.0, 1080.0);
uniform vec2 seed_offset = vec2(0.0);
uniform float submerged : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint = vec4(0.07, 0.36, 0.5, 0.28); // rgb + turbidité
uniform vec4 light : source_color = vec4(1.0);
uniform vec2 rock_pos = vec2(500.0, 700.0);
uniform vec2 rock_radii = vec2(100.0, 70.0);

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

void vertex() {
	world_pos = VERTEX;
}

void fragment() {
	vec2 p = world_pos;
	vec2 sp = p + seed_offset * 1000.0;
	// Relief : les hauts-fonds (et le rocher) émergent en premier.
	float high = fbm(sp * 0.0011 + 55.0) * 0.8;
	high += (1.0 - smoothstep(0.8, 2.2, length((p - rock_pos) / rock_radii))) * 0.2;
	float level = submerged * 1.32 - 0.1;
	float under = 1.0 - smoothstep(level - 0.03, level, high);
	if (under <= 0.001) {
		discard;
	}
	float depth = clamp((level - high) * 2.5, 0.0, 1.0);

	// Réfraction : l'image du fond ondule.
	vec2 wobble = vec2(sin(p.y * 0.03 + TIME * 1.3) + sin(p.x * 0.017 - TIME * 0.7),
		cos(p.x * 0.025 + TIME * 1.1) + cos(p.y * 0.021 + TIME * 0.8)) * 2.5;
	vec3 c = textureLod(screen_tex, SCREEN_UV + wobble * SCREEN_PIXEL_SIZE, 0.0).rgb;

	// Teinte de l'eau : plus trouble et plus colorée en profondeur.
	float turbidity = tint.a;
	c = mix(c, tint.rgb * light.rgb, clamp(turbidity * (0.45 + 0.55 * depth) + 0.12, 0.0, 0.92));

	// Caustiques : réseau lumineux mouvant, plus net en eau claire et peu profonde.
	float n_a = vnoise(sp * 0.014 + vec2(TIME * 0.18, TIME * 0.05));
	float n_b = vnoise(sp * 0.019 + vec2(-TIME * 0.12, TIME * 0.15) + 3.0);
	float caustic = pow(clamp(1.0 - abs(n_a - n_b) * 2.0, 0.0, 1.0), 4.0) * smoothstep(0.2, 0.7, vnoise(sp * 0.004 + TIME * 0.03));
	c += vec3(1.0, 0.97, 0.85) * light.rgb * caustic * 0.12 * (1.0 - turbidity * 0.7) * (1.0 - depth * 0.5);

	// Écume au bord des terres qui émergent.
	float shore = (1.0 - smoothstep(0.0, 0.012, abs(high - level + 0.015))) * step(0.02, 1.0 - submerged);
	c = mix(c, vec3(0.9, 0.92, 0.9) * light.rgb, shore * 0.35);

	COLOR = vec4(c, under);
}
