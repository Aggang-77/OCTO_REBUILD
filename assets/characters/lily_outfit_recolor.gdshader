shader_type spatial;
render_mode diffuse_burley, specular_disabled, cull_disabled;

uniform sampler2D source_texture : source_color, filter_linear_mipmap;
uniform vec4 blouse_color : source_color = vec4(1.0, 0.79, 0.86, 1.0);
uniform vec4 ribbon_color : source_color = vec4(1.0, 0.08, 0.25, 1.0);

void fragment() {
	vec4 original = texture(source_texture, UV);
	vec3 color = original.rgb;
	float value = max(color.r, max(color.g, color.b));
	float chroma = value - min(color.r, min(color.g, color.b));
	// Only the cool white/lavender fabric is pink. Skin and black armbands keep
	// their source pixels even though they share this upper-body atlas.
	float cloth = smoothstep(0.25, 0.55, value) * (1.0 - smoothstep(0.16, 0.27, chroma))
		* smoothstep(-0.02, 0.015, color.b - color.r);
	vec3 pink = blouse_color.rgb * mix(0.55, 1.0, smoothstep(0.35, 1.0, value));
	color = mix(color, pink, cloth);
	// The source neck ribbon is navy. Red source accents use the same palette.
	float navy = step(color.r * 1.8 + 0.015, original.b) * (1.0 - smoothstep(0.15, 0.35, value));
	float red = step(original.g * 1.8 + 0.03, original.r) * step(original.b * 1.6 + 0.02, original.r);
	float ribbon = max(navy, red);
	color = mix(color, ribbon_color.rgb * mix(0.58, 1.0, smoothstep(0.02, 0.75, value)), ribbon);
	ALBEDO = color;
	ALPHA = original.a;
	ALPHA_SCISSOR_THRESHOLD = 0.4;
	ROUGHNESS = 0.95;
}
