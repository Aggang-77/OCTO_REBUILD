shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;
uniform float strength=1.0;
void fragment(){
	float edge=pow(1.0-clamp(dot(normalize(NORMAL),normalize(VIEW)),0.0,1.0),1.6);
	ALBEDO=vec3(0.34,0.88,0.97);
	EMISSION=vec3(0.10,0.26,0.30)*edge;
	ALPHA=(0.09+0.23*edge)*strength;
}
