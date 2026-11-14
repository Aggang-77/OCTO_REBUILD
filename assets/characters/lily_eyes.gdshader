shader_type spatial;
render_mode diffuse_burley, specular_disabled, cull_disabled;

uniform sampler2D source_texture : source_color, filter_linear_mipmap;
uniform vec4 iris_dark : source_color = vec4(0.28, 0.04, 0.14, 1.0);
uniform vec4 iris_color : source_color = vec4(1.0, 0.1, 0.3, 1.0);
uniform vec4 iris_light : source_color = vec4(1.0, 0.4, 0.6, 1.0);

void fragment() {
	vec4 original = texture(source_texture, UV);
	// UV2 is projected continuously across each whole eyeball. The source UV
	// has separate upper/lower islands and would split the iris at its equator.
	vec2 p = UV2;
	float radius = length(p);
	float inside = 1.0 - smoothstep(0.97, 1.02, radius);
	float vertical = smoothstep(-0.8, 0.65, p.y);
	vec3 iris = mix(iris_dark.rgb, iris_color.rgb, vertical);
	iris = mix(iris, iris_light.rgb, smoothstep(0.40, 1.0, p.y) * 0.65);
	float pupil = 1.0 - smoothstep(0.95, 1.08, length((p - vec2(0.0, -0.07)) / vec2(0.25, 0.46)));
	iris = mix(iris, iris_dark.rgb * 0.38, pupil * 0.8);
	iris *= mix(1.0, 0.48, smoothstep(0.82, 1.0, radius));
	float highlight = 1.0 - smoothstep(0.12, 0.18, length(p - vec2(-0.28, -0.45)));
	highlight = max(highlight, (1.0 - smoothstep(0.05, 0.09, length(p - vec2(0.26, 0.40)))) * 0.8);
	iris = mix(iris, vec3(1.0), highlight);
	ALBEDO = mix(original.rgb, iris, inside);
	ALPHA = original.a;
	ALPHA_SCISSOR_THRESHOLD = 0.4;
	ROUGHNESS = 0.85;
}
