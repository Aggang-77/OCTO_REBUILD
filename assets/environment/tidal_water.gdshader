shader_type spatial;
render_mode cull_disabled;

uniform vec3 deep_color : source_color = vec3(0.13, 0.31, 0.30);
uniform vec3 light_color : source_color = vec3(0.36, 0.53, 0.47);
uniform float wave_strength = 0.013;
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(world_pos.x * 2.1 + TIME * 0.7) * cos(world_pos.z * 1.7 - TIME * 0.5) * wave_strength;
}

void fragment() {
	vec2 p = world_pos.xz;
	float a = sin(p.x * 2.7 + p.y * 0.7 + sin(p.y * 0.8) + TIME * 0.8);
	float b = sin(p.y * 3.1 - p.x * 0.3 + sin(p.x * 0.6) - TIME * 0.65);
	float shimmer = smoothstep(0.92, 1.0, a * 0.55 + b * 0.45);
	ALBEDO = mix(deep_color, light_color, 0.10 + shimmer * 0.09);
	ROUGHNESS = 0.35;
	SPECULAR = 0.48;
	METALLIC = 0.0;
	NORMAL_MAP = vec3(0.5 + a * 0.025, 0.5 + b * 0.025, 1.0);
	NORMAL_MAP_DEPTH = 0.18;
}
