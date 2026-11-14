shader_type spatial;
render_mode diffuse_burley, specular_disabled, cull_disabled;
uniform sampler2D source_texture : source_color, filter_linear_mipmap;
uniform bool has_texture = false;
uniform bool preserve_face_atlas = false;
uniform vec4 hair_color : source_color = vec4(0.1, 0.038, 0.018, 1.0);
float in_rect(vec2 point, vec4 rect) {
	return step(rect.x, point.x) * step(rect.y, point.y) * step(point.x, rect.z) * step(point.y, rect.w);
}
void fragment() {
	vec4 original = has_texture ? texture(source_texture, UV) : vec4(1.0);
	float detail = 0.62 + 0.55 * dot(original.rgb, vec3(0.2126, 0.7152, 0.0722));
	float face = 0.0;
	if (preserve_face_atlas) {
		// Rin's source hair surface also contains whites, mouth, lashes and brows.
		// Keep those original atlas islands instead of tinting every head-weighted face.
		face = max(in_rect(UV, vec4(0.377, 0.264, 0.506, 0.389)),
			in_rect(UV, vec4(0.252, 0.50, 0.318, 0.637)));
		face = max(face, in_rect(UV, vec4(0.126, 0.632, 0.248, 0.691)));
		face = max(face, in_rect(UV, vec4(0.382, 0.642, 0.502, 0.716)));
	}
	ALBEDO = mix(hair_color.rgb * detail, original.rgb, face);
	ALPHA = original.a;
	ALPHA_SCISSOR_THRESHOLD = 0.4;
	ROUGHNESS = 0.92;
}
