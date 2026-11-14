shader_type spatial;
render_mode cull_back;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float broad = noise(p * 0.33) * 0.65 + noise(p * 1.5) * 0.35;
	float grain = noise(p * 26.0);
	float ridge = sin((p.x + p.y * 0.32) * 14.0 + noise(p * 1.6) * 9.0);
	float wet = 1.0 - smoothstep(-0.12, 0.17, world_pos.y);
	vec3 dry_mud = mix(vec3(0.11, 0.10, 0.075), vec3(0.22, 0.19, 0.14), broad);
	vec3 wet_mud = mix(vec3(0.045, 0.062, 0.050), vec3(0.12, 0.14, 0.108), broad);
	ALBEDO = mix(dry_mud, wet_mud, wet * 0.85) * (0.94 + grain * 0.09 + ridge * 0.025);
	ROUGHNESS = mix(0.92, 0.33, wet);
	SPECULAR = mix(0.22, 0.58, wet);
	NORMAL_MAP = vec3(0.5 + dFdx(ridge) * 0.035, 0.5 + dFdy(ridge) * 0.035, 1.0);
	NORMAL_MAP_DEPTH = 0.2;
}
