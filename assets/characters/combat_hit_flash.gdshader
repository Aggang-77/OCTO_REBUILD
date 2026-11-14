shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;
uniform float strength=0.0;
void fragment(){
	ALBEDO=vec3(1.0,0.12,0.10);
	ALPHA=strength;
}
