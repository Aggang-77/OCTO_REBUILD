#include <octo/world.hpp>
#include <iostream>
#include <iomanip>
#include <sstream>
#include <string>
#include <cmath>
#include <chrono>
#include <algorithm>
using namespace octo;
static void v(Vec3 p){std::cout<<'['<<p.x<<','<<p.y<<','<<p.z<<']';}
static void q(Quat p){std::cout<<'['<<p.x<<','<<p.y<<','<<p.z<<','<<p.w<<']';}
static void snapshot(const RenderSnapshot& s){
 std::cout<<"{\"tick\":"<<s.tick<<",\"time\":"<<s.time<<",\"animals\":[";
 for(size_t i=0;i<s.animals.size();++i){if(i)std::cout<<',';auto& a=s.animals[i];std::cout<<"{\"center\":";v(a.center);std::cout<<",\"orientation\":";q(a.orientation);std::cout<<",\"body_nodes\":[";for(size_t j=0;j<a.body_nodes.size();++j){if(j)std::cout<<',';v(a.body_nodes[j]);}std::cout<<"],\"arms\":[";
 for(size_t k=0;k<8;++k){if(k)std::cout<<',';auto& arm=a.arms[k];std::cout<<"{\"nodes\":[";for(size_t j=0;j<arm.nodes.size();++j){if(j)std::cout<<',';v(arm.nodes[j]);}std::cout<<"],\"frames\":[";for(size_t j=0;j<arm.frames.size();++j){if(j)std::cout<<',';q(arm.frames[j]);}std::cout<<"],\"radii\":[";for(size_t j=0;j<arm.radii.size();++j){if(j)std::cout<<',';std::cout<<'['<<arm.radii[j][0]<<','<<arm.radii[j][1]<<']';}std::cout<<"],\"attached\":[";for(size_t j=0;j<arm.attached.size();++j){if(j)std::cout<<',';std::cout<<(arm.attached[j]?"true":"false");}std::cout<<"]}";}std::cout<<"]}";}std::cout<<"],\"rigids\":[";
 for(size_t i=0;i<s.rigids.size();++i){if(i)std::cout<<',';auto& r=s.rigids[i];std::cout<<"{\"center\":";v(r.center);std::cout<<",\"orientation\":";q(r.orientation);std::cout<<",\"half_extents\":";v(r.half_extents);std::cout<<'}';}
 auto& d=s.diagnostics;std::cout<<"],\"diagnostics\":{\"step_ms\":"<<d.step_ms<<",\"constraints_ms\":"<<d.constraints_ms<<",\"collision_ms\":"<<d.collision_ms<<",\"max_penetration\":"<<d.max_penetration<<",\"max_volume_error\":"<<d.max_volume_error<<",\"kinetic_energy\":"<<d.kinetic_energy<<",\"linear_momentum\":";v(d.linear_momentum);std::cout<<",\"contact_count\":"<<d.contact_count<<",\"candidate_pairs\":"<<d.candidate_pairs<<",\"attachments\":"<<d.attachments<<",\"broken_attachments\":"<<d.broken_attachments<<",\"nonfinite_count\":"<<d.nonfinite_count<<"}}";
}
// Render protocol v1 only transmits fields consumed by the Godot scene.
// Full physical state remains in PhysicsWorld::snapshot for diagnostics/tests.
static void render_snapshot(const RenderSnapshot& s){
 std::cout<<"{\"tick\":"<<s.tick<<",\"time\":"<<s.time<<",\"animals\":[";
 for(size_t i=0;i<s.animals.size();++i){if(i)std::cout<<',';const auto& a=s.animals[i];std::cout<<"{\"center\":";v(a.center);std::cout<<",\"orientation\":";q(a.orientation);
  std::cout<<",\"body_nodes\":[";for(size_t j=0;j<a.body_nodes.size();++j){if(j)std::cout<<',';v(a.body_nodes[j]);}
  std::cout<<"],\"arms\":[";
  for(size_t k=0;k<8;++k){if(k)std::cout<<',';std::cout<<"{\"uncoil\":"<<a.arms[k].uncoil_progress<<",\"nodes\":[";const auto& nodes=a.arms[k].nodes;for(size_t j=0;j<nodes.size();++j){if(j)std::cout<<',';v(nodes[j]);}std::cout<<"],\"roll\":[";const auto& roll=a.arms[k].material_roll;for(size_t j=0;j<roll.size();++j){if(j)std::cout<<',';std::cout<<roll[j];}std::cout<<"],\"radii\":[";const auto& radii=a.arms[k].radii;for(size_t j=0;j<radii.size();++j){if(j)std::cout<<',';std::cout<<'['<<radii[j][0]<<','<<radii[j][1]<<']';}std::cout<<"],\"tissue\":[";const auto& strain=a.arms[k].tissue_strain;for(size_t j=0;j<strain.size();++j){if(j)std::cout<<',';std::cout<<'['<<strain[j][0]<<','<<strain[j][1]<<']';}
   std::cout<<"],\"creep\":[";const auto& creep=a.arms[k].creep_strain;for(size_t j=0;j<creep.size();++j){if(j)std::cout<<',';std::cout<<creep[j];}
   std::cout<<"],\"elastic_strain\":[";const auto& elastic=a.arms[k].elastic_strain;for(size_t j=0;j<elastic.size();++j){if(j)std::cout<<',';std::cout<<elastic[j];}
   std::cout<<"],\"volume_rings\":[";const auto& rings=a.arms[k].volume_rings;
   for(size_t j=0;j<rings.size();++j){if(j)std::cout<<',';std::cout<<'[';
    for(int vtx=0;vtx<4;++vtx){if(vtx)std::cout<<',';v(rings[j][vtx]);}
    std::cout<<']';}
   std::cout<<"],\"frames\":[";for(size_t j=0;j<a.arms[k].frames.size();++j){if(j)std::cout<<',';q(a.arms[k].frames[j]);}std::cout<<"],\"contact_radii\":[";for(size_t j=0;j<a.arms[k].contact_radii.size();++j){if(j)std::cout<<',';std::cout<<a.arms[k].contact_radii[j];}std::cout<<"],\"grab_radii\":[";for(size_t j=0;j<a.arms[k].grab_radii.size();++j){if(j)std::cout<<',';std::cout<<a.arms[k].grab_radii[j];}std::cout<<"],\"sucker_dirs\":[";for(size_t j=0;j<a.arms[k].sucker_directions.size();++j){if(j)std::cout<<',';v(a.arms[k].sucker_directions[j]);}std::cout<<"],\"grabbed\":"<<(a.arms[k].grabbed?"true":"false");std::cout<<",\"attached\":[";const auto& held=a.arms[k].attached;for(size_t j=0;j<held.size();++j){if(j)std::cout<<',';std::cout<<(held[j]?"true":"false");}std::cout<<"]}";}
  std::cout<<"]}";}
 std::cout<<"],\"rigids\":[";
 for(size_t i=0;i<s.rigids.size();++i){if(i)std::cout<<',';const auto& r=s.rigids[i];std::cout<<"{\"center\":";v(r.center);std::cout<<",\"orientation\":";q(r.orientation);std::cout<<",\"half_extents\":";v(r.half_extents);std::cout<<'}';}
 std::cout<<"],\"diagnostics\":{\"step_ms\":"<<s.diagnostics.step_ms<<",\"attachments\":"<<s.diagnostics.attachments<<",\"nonfinite_count\":"<<s.diagnostics.nonfinite_count<<",\"contact_count\":"<<s.diagnostics.contact_count<<",\"arm_prop_surface_contacts\":"<<s.diagnostics.arm_prop_surface_contacts<<",\"max_mantle_volume_error\":"<<s.diagnostics.max_mantle_volume_error<<"}}";
}
#ifndef OCTO_RENDER_LIBRARY
int main(){std::cout<<std::setprecision(6);WorldConfig cfg;PhysicsWorld world(cfg);std::string line;unsigned long long last=0;
 while(std::getline(std::cin,line)){if(line.size()>65536){std::cout<<"{\"version\":1,\"id\":0,\"ok\":false,\"error\":\"request_too_large\"}"<<std::endl;continue;}std::istringstream in(line);int version=0;unsigned long long id=0;std::string op;in>>version>>id>>op;std::string error;
 if(!in||version!=1)error="bad_header";else if(id<=last)error="stale_id";else {last=id;if(op=="quit"){std::cout<<"{\"version\":1,\"id\":"<<id<<",\"ok\":true}"<<std::endl;break;}else if(op=="reset"){
 unsigned n=0;double spacing=2.2,suction=0,volume_arm=0,grounded=0;in>>n;bool parsed=bool(in);
 std::vector<std::string> tokens;std::string token;while(in>>token)tokens.push_back(token);
 auto number=[&](size_t idx,double& v){if(idx>=tokens.size())return true;std::istringstream part(tokens[idx]);part>>v;return bool(part)&&part.eof();};
 parsed=parsed&&tokens.size()<=4&&number(0,spacing)&&number(1,suction)&&number(2,volume_arm)&&number(3,grounded);
 if(!parsed||n<1||n>10||!std::isfinite(spacing)||spacing<.5||spacing>4||!(suction==0||suction==1)||!(volume_arm==0||volume_arm==1)||!(grounded==0||grounded==1))error="bad_config";
 else{cfg.animals=n;cfg.spacing=spacing;cfg.auto_suction=suction==1;cfg.volumetric_arm_prototype=volume_arm==1;cfg.grounded_rest=grounded==1;cfg.tissue_stiffness_ratio=cfg.grounded_rest?.2:1.;cfg.spawn_height=cfg.grounded_rest?.27:.75;cfg.upright_strength=cfg.grounded_rest?.08:.45;world.reset(cfg);}
}else if(op=="step"||op=="step2"||op=="step3"){const bool v1=op!="step";const bool targeted=op=="step3";unsigned n=0;in>>n;std::vector<MuscleCommand> commands; if(!in||n!=cfg.animals*8)error="bad_count";else{for(unsigned i=0;i<n;++i){MuscleCommand c;int attach=0;in>>c.animal>>c.arm>>c.activation>>c.curvature>>c.extension>>c.twist>>c.stiffness>>attach;if(v1)in>>c.sweep;c.attach=!v1&&attach!=0;c.grab_mode=v1?unsigned(std::clamp(attach,0,2)):0;if(!in||c.animal!=i/8||c.arm!=i%8||!std::isfinite(c.activation)||!std::isfinite(c.curvature)||!std::isfinite(c.extension)||!std::isfinite(c.twist)||!std::isfinite(c.stiffness)||!std::isfinite(c.sweep)||(attach<0||attach>(v1?2:1))){error="bad_command";break;}commands.push_back(c);}DragCommand d;int kind=0;in>>kind>>d.index>>d.arm>>d.target.x>>d.target.y>>d.target.z>>d.stiffness>>d.max_force;int release=0;if(v1)in>>release;
int target_kind=0,target_index=0;
Vec3 clicked{};
if(targeted)in>>target_kind>>target_index>>clicked.x>>clicked.y>>clicked.z;
if(targeted&&in){
 for(auto& c:commands)if(c.grab_mode==1){
  c.grab_target_kind=static_cast<unsigned>(target_kind);
  c.grab_target_index=static_cast<unsigned>(target_index);
  c.grab_target_point=clicked;
 }
}
if(!in||kind<0||kind>3||!std::isfinite(d.target.x)||!std::isfinite(d.target.y)||!std::isfinite(d.target.z)||!std::isfinite(d.stiffness)||!std::isfinite(d.max_force)||(v1&&release!=0&&release!=1)||(targeted&&(target_kind<0||target_kind>2||target_index<0||!std::isfinite(clicked.x)||!std::isfinite(clicked.y)||!std::isfinite(clicked.z))))error="bad_drag";
std::string extra;if(in>>extra)error="extra_data";
d.kind=static_cast<DragCommand::Kind>(kind);if(error.empty()){world.release_all_suckers(false);if(v1)world.set_suction_enabled(release==1);for(auto& c:commands)if(!world.command(c)){error="command_rejected";break;}if(error.empty()&&!world.drag(d))error="drag_rejected";if(error.empty()&&!world.step())error="step_failed";}}}else if(op!="snapshot")error="bad_operation";}
 std::cout<<"{\"version\":1,\"id\":"<<id<<",\"ok\":"<<(error.empty()?"true":"false");if(!error.empty())std::cout<<",\"error\":\""<<error<<'"';else{std::cout<<",\"snapshot\":";render_snapshot(world.snapshot());}std::cout<<'}'<<std::endl;}
}
#endif
