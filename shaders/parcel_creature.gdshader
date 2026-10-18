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
// Variante de forme : 1 = nageur (anomalocaris pour ARTHROPOD, nautile pour MOLLUSK).
uniform int variant = 0;

varying vec4 custom;
varying vec4 tint;

const int QUADRUPED = 0;
const int BIPED = 1;
const int BIRD = 2;
const int LONG_NECK = 3;
const int REPTILE = 4;
const int HUMANOID = 5;
const int GENERIC = 6;
const int MICROBE = 7;
const int ALGA = 8;
const int SPONGE = 9;
const int ARTHROPOD = 10;
const int MYRIAPOD = 11;
const int MOLLUSK = 12;
const int JELLY = 13;
const int FISH = 14;
const int PLANT = 15;
const int AMPHIBIAN = 16;
const int DRAGONFLY = 17;
const int SYNAPSID = 18;

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

// Formes du prologue (et forme générique des clades inconnus). Fixées, nageuses, rampantes, volantes.
float prologue_sdf(vec2 p, float phase, float state, float speed, float walk, float sway) {
	float t = TIME + phase * 6.2831;
	float d = 1e3;
	if (shape == MICROBE) {
		// Colonie de cellules qui respirent.
		d = length(p) - 0.22 - 0.03 * sin(t * 1.5);
		for (int k = 0; k < 6; k++) {
			float a = float(k) * 1.047 + phase * 6.2831 + 0.2 * sin(t * 0.7 + float(k));
			d = min(d, length(p - vec2(cos(a), sin(a)) * 0.5) - 0.16 - 0.03 * sin(t * 2.0 + float(k)));
		}
		return d;
	}
	if (shape == ALGA || shape == PLANT) {
		// Frondes rayonnantes qui ondulent (algue dans le courant, fougère au vent).
		int n = shape == ALGA ? 5 : 7;
		for (int k = 0; k < n; k++) {
			float a = float(k) * 6.2831 / float(n) + phase * 3.0 + sin(t * (shape == ALGA ? 1.2 : 0.6) + float(k)) * (shape == ALGA ? 0.3 : 0.08);
			vec2 dir = vec2(cos(a), sin(a));
			d = min(d, capsule(p, vec2(0.0), dir * 0.9, shape == ALGA ? 0.09 : 0.11, 0.03));
		}
		return min(d, length(p) - 0.12);
	}
	if (shape == SPONGE) {
		// Vase vu de dessus : anneau épais autour de l'oscule, bord bosselé.
		float r = length(p);
		float bumps = 0.04 * sin(atan(p.y, p.x) * 7.0 + phase * 6.0);
		return abs(r - 0.55 - bumps) - 0.22;
	}
	if (shape == ARTHROPOD) {
		if (variant == 1) {
			// Anomalocaris : corps allongé, lobes latéraux qui ondulent, appendices frontaux.
			d = ellipse(p, vec2(0.0), vec2(0.62, 0.2));
			for (int k = 0; k < 5; k++) {
				float x = 0.4 - float(k) * 0.2;
				float w = 0.06 * sin(t * 6.0 - float(k) * 1.2);
				d = min(d, ellipse(p, vec2(x, 0.24 + w), vec2(0.09, 0.08)));
				d = min(d, ellipse(p, vec2(x, -0.24 - w), vec2(0.09, 0.08)));
			}
			d = min(d, capsule(p, vec2(0.55, 0.06), vec2(0.85, 0.2), 0.05, 0.02));
			d = min(d, capsule(p, vec2(0.55, -0.06), vec2(0.85, -0.2), 0.05, 0.02));
			return min(d, ellipse(p, vec2(-0.7, 0.0), vec2(0.12, 0.2)));
		}
		// Trilobite : bouclier ovale, antennes.
		d = ellipse(p, vec2(0.0), vec2(0.55, 0.38));
		d = min(d, capsule(p, vec2(0.5, 0.12), vec2(0.82, 0.3 + walk * 0.05), 0.025, 0.015));
		return min(d, capsule(p, vec2(0.5, -0.12), vec2(0.82, -0.3 - walk * 0.05), 0.025, 0.015));
	}
	if (shape == MYRIAPOD) {
		// Mille-pattes géant : chaîne d'anneaux qui ondule, pattes en vague.
		for (int k = 0; k < 9; k++) {
			float x = 0.82 - float(k) * 0.2;
			float y = sin(x * 5.0 + t * 5.0 * clamp(speed * 2.0, 0.2, 1.0)) * 0.07;
			d = min(d, length(p - vec2(x, y)) - 0.1);
			float leg = sin(t * 12.0 + float(k) * 1.3) * 0.05;
			d = min(d, capsule(p, vec2(x, y), vec2(x + leg, y + 0.2), 0.018, 0.01));
			d = min(d, capsule(p, vec2(x, y), vec2(x - leg, y - 0.2), 0.018, 0.01));
		}
		return d;
	}
	if (shape == MOLLUSK) {
		d = length(p - vec2(-0.1, 0.0)) - 0.5;
		if (variant == 1) {
			// Nautile : tentacules devant la coquille.
			for (int k = -2; k <= 2; k++) {
				float y = float(k) * 0.08;
				d = min(d, capsule(p, vec2(0.3, y), vec2(0.8, y * 2.0 + sin(t * 3.0 + float(k)) * 0.05), 0.03, 0.01));
			}
		}
		return d;
	}
	if (shape == JELLY) {
		// Méduse : cloche qui pulse, tentacules qui traînent derrière.
		float pulse = 1.0 + 0.12 * sin(t * 3.0);
		d = ellipse(p, vec2(0.3, 0.0), vec2(0.38 * pulse, 0.42 * pulse));
		for (int k = 0; k < 6; k++) {
			float y = (float(k) - 2.5) * 0.11;
			vec2 a = vec2(0.05, y);
			vec2 b = vec2(-0.9, y * 1.4 + sin(t * 2.0 + float(k)) * 0.1);
			d = min(d, capsule(p, a, b, 0.02, 0.008));
		}
		return d;
	}
	if (shape == FISH) {
		float tail = sin(t * 8.0 * clamp(speed * 2.0 + 0.3, 0.3, 1.5)) * 0.15;
		d = ellipse(p, vec2(0.08, 0.0), vec2(0.52, 0.17));
		d = min(d, capsule(p, vec2(-0.35, 0.0), vec2(-0.7, tail * 0.6), 0.09, 0.04));
		d = min(d, ellipse(p, vec2(-0.78, tail), vec2(0.08, 0.2)));
		d = min(d, ellipse(p, vec2(0.15, 0.17), vec2(0.1, 0.05)));
		return min(d, ellipse(p, vec2(0.15, -0.17), vec2(0.1, 0.05)));
	}
	if (shape == AMPHIBIAN) {
		d = ellipse(p, vec2(0.0), vec2(0.4, 0.19));
		d = min(d, ellipse(p, vec2(0.48, 0.0), vec2(0.18, 0.2)));
		d = min(d, capsule(p, vec2(-0.3, 0.0), vec2(-0.82, sway), 0.1, 0.02));
		float s = walk * 0.1;
		d = min(d, capsule(p, vec2(0.22, 0.1), vec2(0.3 + s, 0.38), 0.05, 0.04));
		d = min(d, capsule(p, vec2(0.22, -0.1), vec2(0.3 - s, -0.38), 0.05, 0.04));
		d = min(d, capsule(p, vec2(-0.22, 0.1), vec2(-0.3 - s, 0.38), 0.05, 0.04));
		return min(d, capsule(p, vec2(-0.22, -0.1), vec2(-0.3 + s, -0.38), 0.05, 0.04));
	}
	if (shape == DRAGONFLY) {
		// Libellule géante : abdomen fin, quatre ailes qui vibrent.
		float flap = 0.75 + 0.25 * sin(TIME * 45.0 + phase * 20.0);
		d = capsule(p, vec2(0.12, 0.0), vec2(-0.92, 0.0), 0.06, 0.035);
		d = min(d, ellipse(p, vec2(0.22, 0.0), vec2(0.13, 0.09)));
		d = min(d, length(p - vec2(0.38, 0.0)) - 0.08);
		d = min(d, ellipse(p, vec2(0.24, 0.45 * flap), vec2(0.08, 0.4 * flap)));
		d = min(d, ellipse(p, vec2(0.24, -0.45 * flap), vec2(0.08, 0.4 * flap)));
		d = min(d, ellipse(p, vec2(0.04, 0.42 * flap), vec2(0.07, 0.37 * flap)));
		return min(d, ellipse(p, vec2(0.04, -0.42 * flap), vec2(0.07, 0.37 * flap)));
	}
	// GENERIC : silhouette neutre (corps rond, tête marquée) pour tout clade inconnu.
	d = ellipse(p, vec2(0.0), vec2(0.45, 0.3));
	return min(d, ellipse(p, vec2(0.45, 0.0), vec2(0.17, 0.16)));
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
	if (shape >= GENERIC && shape != SYNAPSID) {
		return prologue_sdf(p, phase, state, speed, walk, tail_sway);
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

// Motifs de surface des formes du prologue (segments, spirale, noyaux, voile dorsale).
vec3 prologue_detail(vec3 c, vec2 p, float phase) {
	if (shape == ARTHROPOD && variant == 0) {
		// Trilobite : trois lobes et segments.
		float seg = smoothstep(0.35, 0.5, abs(fract(p.x * 5.0) - 0.5));
		float lobes = smoothstep(0.1, 0.13, abs(p.y));
		return c * (0.82 + 0.18 * seg) * mix(1.12, 0.92, lobes);
	}
	if (shape == MYRIAPOD || shape == ARTHROPOD) {
		return c * (0.85 + 0.15 * smoothstep(0.3, 0.5, abs(fract(p.x * 5.0) - 0.5)));
	}
	if (shape == MOLLUSK) {
		// Coquille spiralée.
		vec2 q = p - vec2(-0.1, 0.0);
		float a = atan(q.y, q.x);
		float spiral = sin(log(max(length(q), 1e-3)) * 9.0 - a);
		return c * (0.8 + 0.2 * smoothstep(-0.2, 0.2, spiral));
	}
	if (shape == MICROBE) {
		// Noyaux sombres dans chaque cellule.
		return mix(c, c * 0.55, smoothstep(0.08, 0.02, abs(length(p) - 0.0)) * 0.6);
	}
	if (shape == SPONGE) {
		return mix(c, c * 0.4, 1.0 - smoothstep(0.25, 0.35, length(p))); // oscule sombre
	}
	if (shape == FISH) {
		return mix(c * 1.15, c * 0.75, smoothstep(-0.1, 0.12, p.y)); // ventre clair, dos sombre
	}
	if (shape == SYNAPSID) {
		// Voile dorsale de dimétrodon : bande rayée le long de l'échine.
		float sail = (1.0 - smoothstep(0.04, 0.07, abs(p.y))) * step(-0.35, p.x) * step(p.x, 0.3);
		float ribs = 0.5 + 0.5 * sin(p.x * 60.0);
		return mix(c, mix(vec3(0.75, 0.35, 0.15), vec3(0.95, 0.6, 0.3), ribs), sail);
	}
	return c;
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
		float lift = (shape == BIRD && state > 2.5) || shape == DRAGONFLY ? 0.18 : (shape == JELLY || shape == FISH ? 0.12 : 0.07);
		if (shape == MICROBE || shape == ALGA) {
			lift = 0.03;
		}
		float ds = body_sdf(p - vec2(lift * 0.8, lift), phase, state, speed);
		float sh = (1.0 - smoothstep(-0.05, 0.05, ds)) * 0.35;
		// Dos plus clair (relief), contour sombre.
		float ridge = 1.0 - smoothstep(0.0, 0.2, abs(p.y));
		vec3 c = base.rgb * (0.85 + 0.25 * ridge);
		c = mix(c * 0.45, c, smoothstep(0.0, 0.05, -d));
		c = prologue_detail(c, p, phase);
		if (state > 1.5 && state < 2.5) {
			c *= 0.8;
		} else if (state > 3.5) {
			c = mix(c * 0.6, vec3(0.35, 0.3, 0.28), 0.3);
		}
		// Méduses et ailes de libellule : translucides.
		float body_alpha = shape == JELLY ? 0.55 : 1.0;
		if (shape == DRAGONFLY && abs(p.y) > 0.12) {
			body_alpha = 0.45;
			c = mix(c, vec3(0.85, 0.95, 1.0), 0.6);
		}
		inside *= body_alpha;
		col = vec4(c, max(inside, sh));
		col.rgb = mix(vec3(0.0), col.rgb, inside / max(col.a, 1e-4));
	}
	col.a *= base.a;
	COLOR = col;
}
