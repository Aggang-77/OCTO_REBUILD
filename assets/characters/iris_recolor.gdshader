shader_type spatial;
render_mode diffuse_burley, specular_disabled, cull_disabled;

uniform sampler2D source_texture : source_color, filter_linear_mipmap;
uniform vec4 iris_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 iris_dark : source_color = vec4(0.2, 0.02, 0.1, 1.0);
uniform vec4 iris_color : source_color = vec4(1.0, 0.1, 0.3, 1.0);
uniform vec4 iris_light : source_color = vec4(1.0, 0.4, 0.6, 1.0);

void fragment() {
	vec4 original = texture(source_texture, UV);
	float region = step(iris_rect.x, UV.x) * step(iris_rect.y, UV.y)
		* step(UV.x, iris_rect.z) * step(UV.y, iris_rect.w);
	float value = max(original.r, max(original.g, original.b));
	float chroma = value - min(original.r, min(original.g, original.b));
	// Preserve painted white reflections, pupil detail, and the original alpha.
	float reflection = smoothstep(0.80, 0.97, value) * (1.0 - smoothstep(0.04, 0.15, chroma));
	vec3 iris = mix(iris_dark.rgb, iris_color.rgb, smoothstep(0.025, 0.55, value));
	iris = mix(iris, iris_light.rgb, smoothstep(0.60, 1.0, value));
	ALBEDO = mix(original.rgb, iris, region * (1.0 - reflection));
	ALPHA = original.a;
	ALPHA_SCISSOR_THRESHOLD = 0.4;
	ROUGHNESS = 0.85;
}
