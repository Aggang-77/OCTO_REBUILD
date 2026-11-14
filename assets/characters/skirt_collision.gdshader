shader_type spatial;
render_mode world_vertex_coords, cull_disabled;
uniform sampler2D source_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_texture = false;
uniform vec4 base_color : source_color = vec4(1.0);
uniform mat4 hips_world;
uniform mat4 hips_inverse;
uniform float waist_height = 0.15;
uniform float coat_ease = 0.0;
uniform float coat_flare = 0.0;
uniform float coat_back_ease = 0.0;
uniform float coat_waist_ease = 0.0;
uniform vec3 garment_back = vec3(0.0,0.0,-1.0);
uniform vec4 leg_start[4]; // xyz = world-space endpoint, w = capsule radius + fabric margin.
uniform vec4 leg_end[4];

float sphere_exit(vec3 origin, vec3 direction, vec3 center, float radius) {
    vec3 offset = origin-center;
    float b=dot(offset,direction);
    float h=b*b-dot(offset,offset)+radius*radius;
    return h>=0.0 ? max(0.0,-b+sqrt(max(0.0,h))) : 0.0;
}

float capsule_exit(vec3 origin, vec3 direction, vec3 a, vec3 b, float radius) {
    vec3 ba=b-a;
    vec3 oa=origin-a;
    float length_sq=dot(ba,ba);
    float along_ray=dot(ba,direction);
    float along_point=dot(ba,oa);
    float qa=length_sq-along_ray*along_ray;
    float qb=length_sq*dot(direction,oa)-along_point*along_ray;
    float qc=length_sq*dot(oa,oa)-along_point*along_point-radius*radius*length_sq;
    float h=qb*qb-qa*qc;
    float result=max(sphere_exit(origin,direction,a,radius),sphere_exit(origin,direction,b,radius));
    if (h>=0.0 && qa>0.000001) {
        float t=(-qb+sqrt(max(0.0,h)))/qa;
        float y=along_point+t*along_ray;
        if (y>=0.0 && y<=length_sq) result=max(result,t);
    }
    return result;
}

void vertex() {
    vec3 local=(hips_inverse*vec4(VERTEX,1.0)).xyz;
    float radius=length(local.xz);
    float back_weight=smoothstep(0.05,0.65,dot(normalize(NORMAL),normalize(garment_back)));
    float upper_region=smoothstep(waist_height-0.20,waist_height,local.y)
        *(1.0-smoothstep(waist_height+0.36,waist_height+0.52,local.y));
    float back_room=coat_back_ease*mix(1.0,0.88,smoothstep(waist_height-0.04,waist_height+0.24,local.y));
    VERTEX+=garment_back*back_room*back_weight*upper_region;
    if(radius>0.001){
        float waist_blend=1.0-smoothstep(0.08,0.30,abs(local.y-waist_height+0.025));
        vec3 waist_out=normalize(mat3(hips_world)*vec3(local.x/radius,0.0,local.z/radius));
        VERTEX+=waist_out*coat_waist_ease*waist_blend;
    }
    float free_fabric=1.0-smoothstep(waist_height-0.065,waist_height-0.015,local.y);
    if (radius>0.001 && free_fabric>0.001) {
        // Enclose the entire animated leg cross-section, including a leg that
        // moved outside the old skirt outline between two physics frames.
        vec3 origin=(hips_world*vec4(0.0,local.y,0.0,1.0)).xyz;
        vec3 radial=normalize(mat3(hips_world)*vec3(local.x/radius,0.0,local.z/radius));
        float drop=clamp((waist_height-local.y)/0.30,0.0,1.0);
        float required=radius+(coat_ease+coat_flare*drop)*free_fabric;
        for (int i=0;i<4;i++) {
            required=max(required,capsule_exit(origin,radial,leg_start[i].xyz,leg_end[i].xyz,leg_start[i].w));
            // A smooth fabric envelope around the capsule silhouette prevents
            // isolated rays from pulling narrow points into knee-shaped tubes.
            vec3 a=(hips_inverse*vec4(leg_start[i].xyz,1.0)).xyz;
            vec3 b=(hips_inverse*vec4(leg_end[i].xyz,1.0)).xyz;
            for (int j=0;j<5;j++) {
                vec3 center=mix(a,b,float(j)*0.25);
                float dy=abs(local.y-center.y);
                float r=leg_start[i].w;
                float distance_from_axis=length(center.xz);
                if (dy<r && distance_from_axis>0.001) {
                    float slice_radius=sqrt(max(0.0,r*r-dy*dy));
                    float inner=asin(clamp(slice_radius/distance_from_axis,0.0,0.95));
                    float alignment=dot(local.xz/radius,center.xz/distance_from_axis);
                    float blend=smoothstep(cos(inner+0.32),cos(inner),alignment);
                    required=max(required,mix(radius,max(radius,distance_from_axis+slice_radius),blend));
                }
            }
        }
        VERTEX+=radial*max(0.0,required-radius)*free_fabric;
    }
}

void fragment() {
    vec4 color=base_color;
    if (has_texture) color*=texture(source_texture,UV);
    ALBEDO=color.rgb;
    ROUGHNESS=0.95;
    SPECULAR=0.12;
}
