shader_type spatial;
render_mode unshaded, blend_add, cull_front, depth_draw_never, shadows_disabled;
// Atmosphère de la planète : coque légèrement plus grande que le globe, dont on ne dessine que la face
// intérieure (arrière). Vu de l'espace, elle forme un halo autour du disque (le globe cache le reste) ;
// vue de près du sol, elle devient le ciel. Couleur pilotée par l'atmosphère simulée :
// bleu de Rayleigh avec l'oxygène et l'ozone, brume orangée de méthane avant l'oxygène.

uniform vec3 sun_dir = vec3(0.0, 0.0, 1.0);
uniform float oxygen = 1.0;
uniform float ozone = 1.0;
uniform float greenhouse = 0.0;
uniform float planet_radius = 1.0;
uniform float scale_height = 0.028;
uniform float intensity = 0.75;

varying vec3 obj_pos;
varying vec3 cam_obj;

void vertex() {
	obj_pos = VERTEX;
	cam_obj = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}

void fragment() {
	vec3 dir = normalize(obj_pos - cam_obj);
	// Point du rayon de vue le plus proche du centre (vers l'avant seulement).
	float t = max(dot(-cam_obj, dir), 0.0);
	vec3 c = cam_obj + dir * t;
	float h = length(c);
	float density = exp(-max(h - planet_radius, 0.0) / scale_height);
	vec3 sun = normalize(sun_dir);
	float sunlit = smoothstep(-0.35, 0.25, dot(normalize(c), sun));
	float terminator = exp(-pow(dot(normalize(c), sun) * 4.0, 2.0));

	float ox = smoothstep(0.03, 0.4, oxygen);
	vec3 rayleigh = mix(vec3(0.25, 0.45, 1.0), vec3(0.22, 0.5, 1.0), ozone);
	vec3 haze = vec3(1.0, 0.55, 0.2);
	vec3 col = mix(haze, rayleigh, ox);
	col = mix(col, vec3(1.0, 0.7, 0.45), clamp(greenhouse, 0.0, 1.0) * 0.35);
	// Lumière rasante du couchant.
	col = mix(col, vec3(1.0, 0.42, 0.15), terminator * 0.6);
	float glow = density * (0.08 + 0.92 * sunlit) * intensity;
	// Vers le Soleil, diffusion vers l'avant.
	glow *= 1.0 + 1.5 * pow(max(dot(dir, sun), 0.0), 8.0);
	ALBEDO = col * glow;
	ALPHA = 1.0;
}
