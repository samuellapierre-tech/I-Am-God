shader_type canvas_item;
// Créatures de la vue rapprochée (une MultiMeshInstance2D par espèce), vues de haut, tête vers +x.
// Sans texture : silhouette PARAMÉTRIQUE composée de primitives SDF (corps, tête, cou, queue,
// nageoire, membres, bras radiaux, colonie, cornes, coquille, cloche), réglée par espèce depuis ses
// traits (src/parcel/appearance.gd). Même shader pour toutes les espèces : aucune recompilation.
// Avec texture (assets/parcel/creatures/…) : l'image, légèrement animée.
// INSTANCE_CUSTOM : x = phase (0..1), y = état (0 marche, 1 broute, 2 dort, 3 court, 4 à terre),
//                   z = vitesse normalisée (0..1).
// Couleur d'instance : couleur principale de l'espèce, alpha = fondu d'apparition / disparition.

uniform bool use_texture = false;
// Déplacement : 0 marche, 1 nage, 2 fixé, 3 rampe, 4 vol (Appearance.Loco).
uniform int locomotion = 0;
uniform vec4 body = vec4(0.38, 0.19, 0.14, 0.0);   // demi-longueur, demi-largeur, tête, cou
uniform vec4 tailp = vec4(0.4, 0.0, 0.0, 0.0);     // queue, nageoire caudale, segments, voile dorsale
uniform vec4 limbs = vec4(2.0, 0.3, 0.0, 0.0);     // paires, longueur, type (0 patte, 1 nageoire, 2 aile), bipède
uniform vec4 radial = vec4(0.0);                    // bras, longueur, traînants (0 étoile .. 1 méduse), cellules de colonie
uniform vec4 extras = vec4(0.0, 0.0, 2.0, 0.0);    // cornes, coquille, yeux, cloche
uniform vec4 look = vec4(0.0, 0.0, 5.0, 0.0);      // couverture, motif, échelle du motif, translucidité
uniform float ring = 0.0;                           // éponge : oscule central
uniform vec4 color2 = vec4(0.2, 0.2, 0.2, 1.0);    // couleur du motif

varying vec4 custom;
varying vec4 tint;

const int WALK = 0;
const int SWIM = 1;
const int SESSILE = 2;
const int CRAWL = 3;
const int FLY = 4;

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

float ellipse(vec2 p, vec2 c, vec2 r) {
	vec2 q = (p - c) / max(r, vec2(1e-3));
	return (length(q) - 1.0) * min(r.x, r.y);
}

float capsule(vec2 p, vec2 a, vec2 b, float ra, float rb) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-5), 0.0, 1.0);
	return length(pa - ba * h) - mix(ra, rb, h);
}

vec2 head_center() {
	return vec2(body.x + body.w + body.z * 0.55, 0.0);
}

// Ondulation latérale du corps (nage, reptation, balancement des organismes fixés).
float body_wave(float x, float t, float moving) {
	if (locomotion == SWIM) {
		return sin(x * 7.0 - t * 9.0) * (0.03 + 0.05 * moving) * smoothstep(body.x, -body.x - tailp.x, x);
	}
	if (locomotion == CRAWL) {
		return sin(x * 9.0 - t * 6.0) * 0.03 * (0.2 + moving);
	}
	return 0.0;
}

// Silhouette (distance signée, négative à l'intérieur). p dans [-1, 1]², tête vers +x.
float sd_creature(vec2 p, float phase, float state, float speed) {
	float t = TIME + phase * 6.2831;
	float moving = clamp(speed * 1.6, 0.0, 1.0);
	float sleeping = (state > 1.5 && state < 2.5) ? 1.0 : 0.0;
	float down = state > 3.5 ? 1.0 : 0.0;
	vec2 q = vec2(p.x, p.y - body_wave(p.x, t, moving));
	if (down > 0.5) {
		q.y += 0.06; // couché sur le flanc
	}
	float L = body.x;
	float W = body.y * (1.0 + 0.08 * sleeping);
	float d = 1e3;

	// Colonie (microbes) : cellules groupées qui respirent.
	int cells = int(radial.w + 0.5);
	if (cells > 0) {
		d = length(q) - L - 0.03 * sin(t * 1.5);
		for (int k = 0; k < 8; k++) {
			if (k >= cells) break;
			float a = float(k) * 6.2831 / float(cells) + 0.2 * sin(t * 0.7 + float(k));
			d = min(d, length(q - vec2(cos(a), sin(a)) * (L + 0.22)) - 0.16 - 0.03 * sin(t * 2.0 + float(k)));
		}
		return d;
	}

	// Corps (segments : étranglements réguliers ; cloche : pulsation).
	float bw = W;
	if (tailp.z > 0.5) {
		bw *= 1.0 - 0.14 * abs(sin((q.x / max(L, 0.05) + 1.0) * tailp.z * 1.5708));
	}
	if (extras.w > 0.5) {
		float pulse = 1.0 + 0.12 * sin(t * 3.0);
		d = ellipse(q, vec2(L * 0.35, 0.0), vec2(L, bw) * pulse);
	} else {
		d = ellipse(q, vec2(0.0), vec2(L, bw));
	}
	if (ring > 0.5) {
		// Éponge : anneau bosselé.
		float bumps = 0.04 * sin(atan(q.y, q.x) * 7.0 + phase * 6.0);
		d = abs(length(q) - L * 0.7 - bumps) - L * 0.35;
	}

	// Tête, cou, cornes (ou antennes).
	if (body.z > 0.005) {
		vec2 hc = head_center();
		float bob = (state > 0.5 && state < 1.5) ? 0.03 * sin(TIME * 3.0 + phase * 20.0) : 0.0;
		hc.x += bob;
		if (body.w > 0.01) {
			d = min(d, capsule(q, vec2(L * 0.6, 0.0), hc, bw * 0.4, body.z * 0.55));
		}
		d = min(d, length(q - hc) - body.z);
		if (extras.x > 0.05) {
			for (int s = -1; s <= 1; s += 2) {
				vec2 a = hc + vec2(body.z * 0.3, float(s) * body.z * 0.5);
				vec2 b = hc + vec2(body.z + extras.x * 0.28, float(s) * (body.z * 0.7 + extras.x * 0.12));
				d = min(d, capsule(q, a, b, 0.025, 0.012));
			}
		}
	}

	// Queue et nageoire caudale.
	if (tailp.x > 0.01) {
		float sway = sin(t * 2.0) * 0.1 * (1.0 - sleeping) + body_wave(-L - tailp.x, t, moving);
		vec2 a = vec2(-L * 0.8, 0.0);
		vec2 b = vec2(-L - tailp.x, sway);
		d = min(d, capsule(q, a, b, bw * 0.45, 0.015));
		if (tailp.y > 0.01) {
			d = min(d, ellipse(q, b + vec2(-0.03, 0.0), vec2(0.06, tailp.y)));
		}
	} else if (tailp.y > 0.01) {
		d = min(d, ellipse(q, vec2(-L - 0.04, 0.0), vec2(0.06, tailp.y)));
	}

	// Membres : pattes qui balancent, nageoires paires, ailes qui battent.
	int pairs = int(limbs.x + 0.5);
	int kind = int(limbs.z + 0.5);
	if (kind == 2 && pairs > 0) {
		float flap = locomotion == FLY ? 0.55 + 0.45 * sin(t * 14.0) : 0.3;
		float span = limbs.y * 1.4 * flap;
		vec2 qa = vec2(q.x + abs(q.y) * 0.35, abs(q.y));
		d = min(d, ellipse(qa, vec2(L * 0.1, bw + span * 0.5), vec2(0.16, span * 0.5 + 0.02)));
		pairs -= 1; // les autres paires restent des pattes
		kind = 0;
	}
	for (int k = 0; k < 6; k++) {
		if (k >= pairs) break;
		float f = pairs > 1 ? float(k) / float(pairs - 1) : 0.5;
		float x = mix(L * 0.55, -L * 0.55, f);
		float len = limbs.y;
		if (limbs.w > 0.5 && k == 0 && pairs > 1) {
			len *= 0.45; // bipède : bras courts
		}
		for (int s = -1; s <= 1; s += 2) {
			float side = float(s);
			vec2 a = vec2(x, side * bw * 0.7);
			if (kind == 1) {
				float row = sin(t * 5.0 + float(k)) * 0.04;
				d = min(d, ellipse(q, a + vec2(-0.02 + row, side * len * 0.45), vec2(0.07, len * 0.45)));
			} else {
				float swing = sin(t * 7.0 + float(k) * 1.6 + side * 1.57) * len * 0.5 * moving;
				// Pattes charnues pour les vertébrés, fines pour les carapaces (arthropodes).
				float thick = int(look.x + 0.5) == 4 ? 0.028 : clamp(bw * 0.32, 0.03, 0.075);
				d = min(d, capsule(q, a, a + vec2(swing, side * len), thick, thick * 0.65));
			}
		}
	}

	// Bras radiaux : étoile (étalés), frondes (ondulent), tentacules (traînent derrière).
	int arms = int(radial.x + 0.5);
	for (int k = 0; k < 10; k++) {
		if (k >= arms) break;
		float fk = arms > 1 ? float(k) / float(arms - 1) : 0.5;
		float spread = float(k) * 6.2831 / float(max(arms, 1));
		float trail = 3.1416 + (fk - 0.5) * 1.1;
		float a = mix(spread, trail, radial.z) + sin(t * (locomotion == SESSILE ? 1.1 : 2.2) + float(k)) * 0.18;
		vec2 dir = vec2(cos(a), sin(a));
		vec2 root = radial.z > 0.5 ? vec2(L * 0.1, (fk - 0.5) * bw * 1.4) : dir * bw * 0.5;
		d = min(d, capsule(q, root, root + dir * radial.y, 0.045 * (1.0 - radial.z * 0.6), 0.012));
	}
	return d;
}

// Motifs et matières : couverture (écailles, plumes, poils, carapace, gelée), motif (rayures,
// taches, bandes, marbrures), voile dorsale, yeux.
vec3 surface(vec3 c, vec2 p, float d, float phase) {
	vec2 q = p;
	int cover = int(look.x + 0.5);
	int pattern = int(look.y + 0.5);
	float sc = look.z;
	float L = max(body.x, 0.05);
	// Dos plus clair (relief), flancs plus sombres.
	float ridge = 1.0 - smoothstep(0.0, max(body.y, 0.05) * 1.2, abs(q.y));
	c *= 0.82 + 0.28 * ridge;
	if (pattern == 1) {
		c = mix(c, color2.rgb, step(0.55, fract(q.x * sc)) * 0.85);
	} else if (pattern == 2) {
		c = mix(c, color2.rgb, smoothstep(0.62, 0.68, vnoise(q * sc * 2.0 + phase * 13.0)));
	} else if (pattern == 3) {
		c = mix(c, color2.rgb, (1.0 - smoothstep(body.y * 0.2, body.y * 0.3, abs(q.y))) * 0.9);
	} else if (pattern == 4) {
		c = mix(c, color2.rgb, smoothstep(0.35, 0.75, vnoise(q * sc + 4.0)) * 0.7);
	}
	if (cover == 1) {
		vec2 g = fract(q * 28.0 + vec2(0.0, floor(q.x * 28.0) * 0.5));
		c *= 0.92 + 0.1 * smoothstep(0.2, 0.5, min(g.x, g.y));
	} else if (cover == 2) {
		c *= 0.9 + 0.12 * sin(q.y * 70.0 + q.x * 25.0);
	} else if (cover == 3) {
		c *= 0.9 + 0.15 * vnoise(q * 60.0);
	} else if (cover == 4) {
		float plates = smoothstep(0.42, 0.5, abs(fract((q.x / L) * max(tailp.z, 3.0) * 0.5) - 0.5));
		c = c * (0.85 + 0.15 * plates) + vec3(0.12) * smoothstep(0.6, 1.0, ridge) * (1.0 - plates);
		if (extras.y > 0.5) {
			// Coquille spiralée.
			float a = atan(q.y, q.x);
			c *= 0.82 + 0.18 * smoothstep(-0.2, 0.2, sin(log(max(length(q), 1e-3)) * 9.0 - a));
		}
	} else if (cover == 5) {
		c = mix(c, vec3(1.0), 0.18 * (1.0 - smoothstep(-0.2, 0.0, d)));
	}
	if (tailp.w > 0.05) {
		float sail = (1.0 - smoothstep(0.03, 0.06, abs(q.y))) * step(-L * 0.9, q.x) * step(q.x, L * 0.8);
		c = mix(c, mix(color2.rgb, vec3(0.95, 0.6, 0.3), 0.5 + 0.5 * sin(q.x * 60.0)), sail * tailp.w);
	}
	if (ring > 0.5) {
		c = mix(c, c * 0.35, 1.0 - smoothstep(L * 0.25, L * 0.4, length(q)));
	}
	int eyes = int(extras.z + 0.5);
	if (eyes > 0 && body.z > 0.005) {
		vec2 hc = head_center();
		float r = body.z * 0.22;
		for (int k = 0; k < 8; k++) {
			if (k >= eyes) break;
			float row = float(k / 2);
			float side = (k % 2 == 0) ? 1.0 : -1.0;
			if (eyes % 2 == 1 && k == eyes - 1) side = 0.0;
			vec2 e = hc + vec2(body.z * (0.45 - row * 0.35), side * body.z * 0.48);
			float de = length(q - e);
			c = mix(c, vec3(0.04), 1.0 - smoothstep(r * 0.8, r, de));
			c = mix(c, vec3(1.0), 1.0 - smoothstep(r * 0.15, r * 0.3, length(q - e - vec2(r * 0.3, r * 0.3))));
		}
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
		float d = sd_creature(p, phase, state, speed);
		float aa = fwidth(d) * 1.2 + 1e-4;
		float inside = 1.0 - smoothstep(-aa, aa, d);
		// Ombre portée : plus décalée pour ce qui vole ou flotte, presque nulle pour ce qui est fixé.
		float lift = locomotion == FLY ? 0.16 : (locomotion == SWIM ? 0.1 : (locomotion == SESSILE ? 0.025 : 0.06));
		float ds = sd_creature(p - vec2(lift * 0.8, lift), phase, state, speed);
		float sh = (1.0 - smoothstep(-0.05, 0.05, ds)) * 0.35;
		vec3 c = surface(base.rgb, p, d, phase);
		c = mix(c * 0.45, c, smoothstep(0.0, 0.05, -d)); // contour sombre
		if (state > 1.5 && state < 2.5) {
			c *= 0.8;
		} else if (state > 3.5) {
			c = mix(c * 0.6, vec3(0.35, 0.3, 0.28), 0.3);
		}
		// Ailes et gelées : translucides.
		float alpha = 1.0 - look.w;
		if (int(limbs.z + 0.5) == 2 && abs(p.y) > body.y * 1.1) {
			alpha = min(alpha, 0.6);
			c = mix(c, vec3(0.9, 0.95, 1.0), 0.25);
		}
		inside *= alpha;
		col = vec4(c, max(inside, sh));
		col.rgb = mix(vec3(0.0), col.rgb, inside / max(col.a, 1e-4));
	}
	col.a *= base.a;
	COLOR = col;
}
