shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Reuses the actual imported GameReady vertex, UV, bone weights and bone
// transforms. Vertex displacement is applied BEFORE the existing GPU
// skeleton skinning; no second fake arm mesh or CPU per-frame remesh.
uniform vec4 base_albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_albedo_tex = false;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool has_normal_tex = false;
uniform float base_roughness : hint_range(0.05, 1.0) = 0.42;
uniform float base_metallic : hint_range(0.0, 1.0) = 0.0;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.65;
uniform float vertex_softness : hint_range(0.0, 0.15) = 0.075;
uniform float papilla_strength : hint_range(0.0, 0.02) = 0.0025;

// ShaderUniform arrays are indexed by the *actual* imported GLB bone
// indices, not a guessed contiguous arm order. Updated from C++ tissue.
uniform float bone_compression[256];
uniform float bone_activity[256];
varying float local_load;
varying float local_activity;
varying vec3 original_position;

vec2 skinned_fields(uvec4 bones, vec4 raw_weights) {
    ivec4 ids = ivec4(bones);
    ids = clamp(ids, ivec4(0), ivec4(255));
    vec4 weights = max(raw_weights, vec4(0.0));
    float total = dot(weights, vec4(1.0));
    if (total < 0.001) {
        return vec2(0.0);
    }
    vec4 compress = vec4(bone_compression[ids.x], bone_compression[ids.y],
                         bone_compression[ids.z], bone_compression[ids.w]);
    vec4 activity = vec4(bone_activity[ids.x], bone_activity[ids.y],
                         bone_activity[ids.z], bone_activity[ids.w]);
    return vec2(dot(compress, weights), dot(activity, weights)) / total;
}

void vertex() {
    original_position = VERTEX;
    vec2 fields = skinned_fields(BONE_INDICES, BONE_WEIGHTS);
    local_load = clamp(fields.x, 0.0, 1.0);
    local_activity = clamp(fields.y, 0.0, 1.0);
    // A fixed, non-random geometric pattern. No fast temporal sine waves:
    // avoiding the previous rubbery, constantly vibrating skin.
    float micro = sin(VERTEX.x * 71.0 + VERTEX.z * 31.0)
                * sin(VERTEX.y * 63.0 - VERTEX.x * 29.0);
    float broad = sin(VERTEX.x * 19.0) * sin(VERTEX.y * 23.0 + VERTEX.z * 17.0);
    // Under contact, the bottom surface sinks *up* into the flesh while
    // lateral normal directions expand. This is a controlled skin effect,
    // not a substitute for native contact geometry.
    float underside = max(-NORMAL.y, 0.0);
    float lateral = length(NORMAL.xz);
    VERTEX.y += vertex_softness * local_load * underside * 0.46;
    VERTEX.xz += NORMAL.xz * (vertex_softness * local_load * lateral * 0.34);
    float papillae = papilla_strength * max(NORMAL.y, 0.0) *
                     (0.45 + 0.35 * micro + 0.20 * broad) *
                     (0.4 + local_activity * 0.6);
    VERTEX += NORMAL * papillae;
}

void fragment() {
    vec3 pigment = base_albedo.rgb;
    if (has_albedo_tex) {
        pigment *= texture(albedo_tex, UV).rgb;
    }
    // Real octopus skin is not uniformly mirror-shiny. Pigment patterns,
    // microrelief and irregular wet specular breakup remain visible.
    float mottling = sin(original_position.x * 57.0 +
                         original_position.z * 22.0) *
                     sin(original_position.y * 39.0);
    ALBEDO = pigment * (0.94 + 0.06 * mottling);
    METALLIC = base_metallic;
    ROUGHNESS = clamp(base_roughness * 0.78 +
                      0.055 * mottling - 0.065 * local_load, 0.17, 0.75);
    SPECULAR = 0.48;
    if (has_normal_tex) {
        NORMAL_MAP = texture(normal_tex, UV).rgb;
        NORMAL_MAP_DEPTH = normal_strength;
    }
}
