shader_type spatial;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	float grit = hash(floor(world_pos * 22.0));
	float stain = sin(world_pos.x * 1.8 + sin(world_pos.z * 2.1)) * 0.5 + 0.5;
	float tide = 1.0 - smoothstep(0.2, 1.6, world_pos.y + stain * 0.5);
	float moss = smoothstep(0.6, 0.95, stain) * max(world_normal.y, 0.0) * 0.35;
	vec3 limestone = COLOR.rgb * (0.94 + grit * 0.12);
	ALBEDO = mix(limestone, limestone * vec3(0.47, 0.59, 0.45), tide * 0.65 + moss);
	ROUGHNESS = 0.94;
	SPECULAR = 0.18;
}
