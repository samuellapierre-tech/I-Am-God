shader_type canvas_item;
// Onde de choc : anneau qui déforme l'image déjà rendue (texture d'écran), éclaircit son front.
// Dessinée sur un carré centré sur l'impact (UV 0..1 -> -1..1).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float strength = 28.0; // décalage max, en pixels écran
uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.5, 1.0);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float r = progress;
	float width = 0.08 + 0.1 * progress;
	float band = 1.0 - smoothstep(0.0, width, abs(d - r));
	float fade = 1.0 - progress;
	vec2 dir = d > 0.0001 ? p / d : vec2(0.0);
	vec2 offset = dir * band * fade * strength * SCREEN_PIXEL_SIZE;
	vec3 c = texture(screen_tex, SCREEN_UV - offset).rgb;
	c += tint.rgb * band * fade * 0.25;
	COLOR = vec4(c, clamp(band * fade * 4.0, 0.0, 1.0));
}
