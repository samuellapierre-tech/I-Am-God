shader_type canvas_item;
// Créatures de la parcelle (une MultiMeshInstance2D par espèce), vues de haut, tête vers +x.
// Sans texture : silhouette procédurale par forme (ParcelLogic.Shape). Avec texture
// (assets/parcel/creatures/<clade>.png) : l'image, animée par léger balancement.
// INSTANCE_CUSTOM : x = phase de marche (0..1), y = état (0 marche, 1 broute, 2 dort, 3 court,
//                   4 à terre),
//                   z = vitesse normalisée (0..1).
// Couleur d'instance : teinte de l'espèce, alpha = fondu d'apparition / disparition.

uniform bool use_texture = false;
uniform int shape = 0;

varying vec4 custom;
varying vec4 tint;

const int QUADRUPED = 0;
const int BIPED = 1;
const int BIRD = 2;
const int LONG_NECK = 3;
const int REPTILE = 4;
const int HUMANOID = 5;

float ellipse(vec2 p, vec2 c, vec2 r) {
	vec2 q = (p - c) / r;
	return (length(q) - 1.0) * min(r.x, r.y);
}

float capsule(vec2 p, vec2 a, vec2 b, float ra, float rb) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h) - mix(ra, rb, h);
}

// Distance signée de la silhouette (négative à l'intérieur). p dans [-1, 1]², tête vers +x.
float body_sdf(vec2 p, float phase, float state, float speed) {
	float walk = sin(phase * 6.2831) * clamp(speed * 1.5, 0.0, 1.0);
	float sleeping = step(1.5, state) * (1.0 - step(2.5, state));
	float grazing = step(0.5, state) * (1.0 - step(1.5, state));
	float bob = grazing * 0.04 * sin(TIME * 3.0 + phase * 20.0);
	float tail_sway = 0.12 * sin(TIME * 2.0 + phase * 6.2831) * (1.0 - sleeping);
	float d = 1e3;
	if (shape == HUMANOID) {
		d = ellipse(p, vec2(0.0), vec2(0.2, 0.42));
		d = min(d, ellipse(p, vec2(0.05, 0.0), vec2(0.2, 0.2)));
		d = min(d, ellipse(p, vec2(0.12 + walk * 0.2, 0.22), vec2(0.12, 0.08)));
		d = min(d, ellipse(p, vec2(0.12 - walk * 0.2, -0.22), vec2(0.12, 0.08)));
		return d;
	}
	if (shape == BIRD) {
		float flap = state > 2.5 || speed > 0.3 ? sin(TIME * 14.0 + phase * 30.0) : 0.3;
		d = ellipse(p, vec2(0.0), vec2(0.38, 0.14));
		d = min(d, ellipse(p, vec2(0.38, 0.0), vec2(0.12, 0.1)));
		float span = 0.55 + 0.35 * flap * (1.0 - sleeping);
		d = min(d, capsule(p, vec2(0.05, 0.0), vec2(-0.12, span), 0.12, 0.04));
		d = min(d, capsule(p, vec2(0.05, 0.0), vec2(-0.12, -span), 0.12, 0.04));
		d = min(d, capsule(p, vec2(-0.3, 0.0), vec2(-0.6, 0.0), 0.08, 0.12));
		return d;
	}
	if (state > 3.5 && shape != BIRD) {
		// À terre, couché sur le flanc : pattes raides d'un côté.
		d = ellipse(p, vec2(0.0, -0.05), vec2(0.42, 0.26));
		d = min(d, ellipse(p, vec2(0.5, -0.15), vec2(0.14, 0.11)));
		d = min(d, capsule(p, vec2(-0.35, -0.05), vec2(-0.85, -0.2), 0.08, 0.02));
		d = min(d, capsule(p, vec2(0.22, 0.15), vec2(0.3, 0.5), 0.05, 0.04));
		d = min(d, capsule(p, vec2(-0.2, 0.15), vec2(-0.15, 0.5), 0.05, 0.04));
		return d;
	}
	if (sleeping > 0.5) {
		// Roulé en boule, la queue enroulée sur le côté.
		d = ellipse(p, vec2(0.0), vec2(0.4, 0.3));
		d = min(d, ellipse(p, vec2(0.3, 0.22), vec2(0.14, 0.12)));
		d = min(d, capsule(p, vec2(-0.3, 0.0), vec2(-0.1, -0.42), 0.12, 0.05));
		return d;
	}
	if (shape == BIPED) {
		d = ellipse(p, vec2(0.0), vec2(0.36, 0.17));
		d = min(d, ellipse(p, vec2(0.42 + bob, 0.0), vec2(0.17, 0.12)));
		d = min(d, capsule(p, vec2(-0.25, 0.0), vec2(-0.92, tail_sway), 0.12, 0.02));
		d = min(d, ellipse(p, vec2(0.05 + walk * 0.18, 0.17), vec2(0.13, 0.06)));
		d = min(d, ellipse(p, vec2(0.05 - walk * 0.18, -0.17), vec2(0.13, 0.06)));
		return d;
	}
	if (shape == LONG_NECK) {
		d = ellipse(p, vec2(-0.1, 0.0), vec2(0.36, 0.22));
		d = min(d, capsule(p, vec2(0.15, 0.0), vec2(0.78 + bob, tail_sway * 0.5), 0.09, 0.05));
		d = min(d, ellipse(p, vec2(0.84 + bob, tail_sway * 0.5), vec2(0.09, 0.07)));
		d = min(d, capsule(p, vec2(-0.4, 0.0), vec2(-0.95, -tail_sway), 0.1, 0.02));
	} else if (shape == REPTILE) {
		d = ellipse(p, vec2(0.0), vec2(0.38, 0.13));
		d = min(d, ellipse(p, vec2(0.45, 0.0), vec2(0.17, 0.08)));
		d = min(d, capsule(p, vec2(-0.3, 0.0), vec2(-0.95, tail_sway * 1.5), 0.1, 0.02));
	} else { // QUADRUPED
		d = ellipse(p, vec2(0.0), vec2(0.42, 0.21));
		d = min(d, ellipse(p, vec2(0.52 + bob, 0.0), vec2(0.14, 0.12)));
		d = min(d, capsule(p, vec2(-0.38, 0.0), vec2(-0.72, tail_sway), 0.07, 0.02));
	}
	// Pattes : quatre taches qui avancent en diagonale.
	float stride = walk * 0.12;
	float side = shape == REPTILE ? 0.2 : 0.22;
	d = min(d, ellipse(p, vec2(0.25 + stride, side), vec2(0.08, 0.06)));
	d = min(d, ellipse(p, vec2(0.25 - stride, -side), vec2(0.08, 0.06)));
	d = min(d, ellipse(p, vec2(-0.25 - stride, side), vec2(0.08, 0.06)));
	d = min(d, ellipse(p, vec2(-0.25 + stride, -side), vec2(0.08, 0.06)));
	return d;
}

void vertex() {
	custom = INSTANCE_CUSTOM;
	tint = COLOR;
	if (use_texture) {
		// Respiration / pas : légère pulsation latérale.
		float s = 1.0 + 0.04 * sin(INSTANCE_CUSTOM.x * 12.566) * INSTANCE_CUSTOM.z;
		VERTEX.y *= s;
	}
}

void fragment() {
	float phase = custom.x;
	float state = custom.y;
	float speed = custom.z;
	vec4 base = tint;
	vec4 col = vec4(0.0);
	if (use_texture) {
		vec4 tex = texture(TEXTURE, UV);
		// Ombre portée : la texture décalée, assombrie.
		float sh = texture(TEXTURE, UV - vec2(0.04, 0.05)).a * 0.35;
		col.rgb = mix(vec3(0.0), tex.rgb * mix(vec3(1.0), base.rgb, 0.15), tex.a);
		col.a = max(tex.a, sh);
		if (state > 1.5 && state < 2.5) {
			col.rgb *= 0.8;
		} else if (state > 3.5) {
			col.rgb *= 0.6;
		}
	} else {
		vec2 p = UV * 2.0 - 1.0;
		float d = body_sdf(p, phase, state, speed);
		float aa = fwidth(d) * 1.2 + 1e-4;
		float inside = 1.0 - smoothstep(-aa, aa, d);
		float lift = shape == BIRD && state > 2.5 ? 0.18 : 0.07;
		float ds = body_sdf(p - vec2(lift * 0.8, lift), phase, state, speed);
		float sh = (1.0 - smoothstep(-0.05, 0.05, ds)) * 0.35;
		// Dos plus clair (relief), contour sombre.
		float ridge = 1.0 - smoothstep(0.0, 0.2, abs(p.y));
		vec3 c = base.rgb * (0.85 + 0.25 * ridge);
		c = mix(c * 0.45, c, smoothstep(0.0, 0.05, -d));
		if (state > 1.5 && state < 2.5) {
			c *= 0.8;
		} else if (state > 3.5) {
			c = mix(c * 0.6, vec3(0.35, 0.3, 0.28), 0.3);
		}
		col = vec4(c, max(inside, sh));
		col.rgb = mix(vec3(0.0), col.rgb, inside / max(col.a, 1e-4));
	}
	col.a *= base.a;
	COLOR = col;
}
