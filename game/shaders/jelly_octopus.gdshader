shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform vec4 gel_color : source_color = vec4(0.68, 0.28, 0.32, 0.94);
uniform float jelly_strength : hint_range(0.0, 3.0) = 2.2;
uniform float arm_phase = 0.0;
uniform float recoil : hint_range(0.0, 1.0) = 0.0;
uniform bool mantle_mode = false;

varying float gel_crest;

void vertex() {
    float axial = UV.y;
    float theta = UV.x * 6.28318530718;
    float tm = TIME;
    float phase = arm_phase;

    // Three frequency bands: large slow displacement, traveling contraction,
    // and a short-range trembling ripple. UVs are laid out along each rod.
    float slow = sin(tm * 3.1 - axial * 17.0 + phase);
    float compression = sin(tm * 5.2 - axial * 29.0 + phase * 1.3 + theta * 1.0);
    float tremor = sin(tm * 9.2 + axial * 37.0 - theta * 3.0 + phase);

    float envelope = smoothstep(0.0, 0.14, axial)
                   * (1.0 - smoothstep(0.88, 1.0, axial));
    if (mantle_mode) {
        // A mantle is a soft bulb, not a tentacle: deform the whole surface.
        envelope = 0.7 + 0.3 * sin(axial * 3.14159265);
    }

    float wave = slow * 0.72 + compression * 0.36 + tremor * 0.11;
    float impulse = recoil * exp(-axial * 2.0)
                  * sin(tm * 13.0 - axial * 23.0 + phase);
    float displacement = jelly_strength * envelope
                       * (0.016 * wave + 0.010 * impulse);
    if (mantle_mode) {
        displacement *= 1.4;
    }

    // Only the rendered surface is displaced. The independent C++ simulation
    // still owns centerlines, radii, collisions, forces and authoritative state.
    VERTEX += NORMAL * displacement;
    gel_crest = clamp(0.5 + wave * 0.22, 0.0, 1.0);
}

void fragment() {
    vec3 flesh = gel_color.rgb * mix(0.77, 1.12, gel_crest);
    float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.4);
    ALBEDO = flesh;
    METALLIC = 0.0;
    SPECULAR = 0.8;
    ROUGHNESS = mix(0.21, 0.38, 1.0 - gel_crest);
    // A small warm internal glow suggests moist, translucent tissue
    // without depending on Forward+ SSS (project uses Compatibility/OpenGL).
    EMISSION = vec3(0.12, 0.035, 0.048) * rim * 0.25;
    ALPHA = gel_color.a;
}
