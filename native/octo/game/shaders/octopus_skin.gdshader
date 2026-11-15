shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Reuses the actual imported GameReady vertex, UV, bone weights and bone
// transforms. Vertex displacement is applied BEFORE the existing GPU
// skeleton skinning; no second fake arm mesh or CPU per-frame remesh.
uniform vec4 base_albedo : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform bool vertex_color_albedo = false;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_albedo_tex = false;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool has_normal_tex = false;
uniform float base_roughness : hint_range(0.05, 1.0) = 0.42;
uniform sampler2D roughness_tex : filter_linear_mipmap, repeat_enable;
uniform bool has_roughness_tex = false;
uniform int roughness_channel = 0;
uniform sampler2D metallic_tex : filter_linear_mipmap, repeat_enable;
uniform bool has_metallic_tex = false;
uniform int metallic_channel = 0;
uniform float base_metallic : hint_range(0.0, 1.0) = 0.0;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.65;
uniform float vertex_softness : hint_range(0.0, 0.15) = 0.075;
uniform float papilla_strength : hint_range(0.0, 0.02) = 0.0025;

// ShaderUniform arrays are indexed by the *actual* imported GLB bone
// indices, not a guessed contiguous arm order. Updated from C++ tissue.
uniform float bone_compression[256];
uniform float bone_activity[256];
// Twelve native mantle-shell positions relative to their reset pose, in
// imported model coordinates. Only torso-root-weighted vertices use them.
uniform vec3 mantle_offsets[12];
uniform bool eye_surface = false;
varying float local_load;
varying float local_activity;
varying vec3 original_position;
varying vec4 vertex_tint;

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
    vertex_tint = COLOR;
    vec2 fields = skinned_fields(BONE_INDICES, BONE_WEIGHTS);
    local_load = clamp(fields.x, 0.0, 1.0);
    local_activity = clamp(fields.y, 0.0, 1.0);
    // Authored model calibration: keep the eye assembly high on the
    // cephalic region while the upper mantle extends rearwards (-Z).
    if (eye_surface) VERTEX.y += 0.065;
    float hood = smoothstep(0.28, 0.62, original_position.y);
    VERTEX.z -= hood * 0.10;
    float root_weight = 0.0;
    for (int i = 0; i < 4; i++) {
        if (BONE_INDICES[i] == uint(0)) root_weight += BONE_WEIGHTS[i];
    }
    vec2 radial = VERTEX.xz - vec2(0.0, 0.1);
    float radial_length = length(radial);
    float region = smoothstep(0.12, 0.28, VERTEX.y) *
                   (1.0 - smoothstep(0.68, 0.76, VERTEX.y)) *
                   (1.0 - smoothstep(0.37, 0.48, radial_length));
    if (root_weight > 0.01 && region > 0.001) {
        vec2 direction = radial / max(radial_length, 0.001);
        float height = smoothstep(0.20, 0.53, VERTEX.y);
        vec3 motion = vec3(0.0);
        float total = 0.0;
        for (int k = 0; k < 6; k++) {
            float angle = float(k) * 1.0471975512;
            float weight = pow(max(dot(direction, vec2(cos(angle), sin(angle))), 0.0), 8.0);
            motion += mix(mantle_offsets[k], mantle_offsets[6 + k], height) * weight;
            total += weight;
        }
        VERTEX += motion / max(total, 0.001) * root_weight * region;
    }
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
    vec2 tex_uv = UV * uv_scale + uv_offset;
    vec3 pigment = base_albedo.rgb;
    if (vertex_color_albedo) {
        pigment *= vertex_tint.rgb;
    }
    if (has_albedo_tex) {
        pigment *= texture(albedo_tex, tex_uv).rgb;
    }
    // Real octopus skin is not uniformly mirror-shiny. Pigment patterns,
    // microrelief and irregular wet specular breakup remain visible.
    float mottling = sin(original_position.x * 57.0 +
                         original_position.z * 22.0) *
                     sin(original_position.y * 39.0);
    // Chromatophore-inspired modulation: slow (not a jittering surface
    // wave) and stronger near active tissue. Imported pigment stays primary.
    float chroma = 0.028 * local_activity *
                   sin(TIME * 0.38 + original_position.x * 6.2
                       - original_position.z * 4.6);
    ALBEDO = pigment * (0.94 + 0.06 * mottling + chroma);
    float authored_roughness = base_roughness;
    if (has_roughness_tex) {
        vec4 authored_map = texture(roughness_tex, tex_uv);
        float tex_rough = roughness_channel == 4 ?
            dot(authored_map.rgb, vec3(0.3333333)) :
            authored_map[clamp(roughness_channel, 0, 3)];
        authored_roughness *= tex_rough;
    }
    float authored_metallic = base_metallic;
    if (has_metallic_tex) {
        vec4 metal_map = texture(metallic_tex, tex_uv);
        authored_metallic *= metallic_channel == 4 ?
            dot(metal_map.rgb, vec3(0.3333333)) :
            metal_map[clamp(metallic_channel, 0, 3)];
    }
    METALLIC = authored_metallic;
    ROUGHNESS = clamp(authored_roughness * 0.78 +
                      0.055 * mottling - 0.065 * local_load, 0.17, 0.75);
    SPECULAR = 0.48;
    if (has_normal_tex) {
        NORMAL_MAP = texture(normal_tex, tex_uv).rgb;
        NORMAL_MAP_DEPTH = normal_strength;
    }
}
