#include <octo/world.hpp>
#include <iostream>
#include <iomanip>
#include <sstream>
#include <string>
#include <cmath>
#include <chrono>
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
int main(){std::cout<<std::setprecision(17);WorldConfig cfg;PhysicsWorld world(cfg);std::string line;unsigned long long last=0;
 while(std::getline(std::cin,line)){if(line.size()>65536){std::cout<<"{\"version\":1,\"id\":0,\"ok\":false,\"error\":\"request_too_large\"}"<<std::endl;continue;}std::istringstream in(line);int version=0;unsigned long long id=0;std::string op;in>>version>>id>>op;std::string error;
 if(!in||version!=1)error="bad_header";else if(id<=last)error="stale_id";else {last=id;if(op=="quit"){std::cout<<"{\"version\":1,\"id\":"<<id<<",\"ok\":true}"<<std::endl;break;}else if(op=="reset"){unsigned n=0;in>>n;if(!in||n<1||n>10)error="bad_config";else{cfg.animals=n;world.reset(cfg);}}else if(op=="step"){unsigned n=0;in>>n;std::vector<MuscleCommand> commands; if(!in||n!=cfg.animals*8)error="bad_count";else{for(unsigned i=0;i<n;++i){MuscleCommand c;int attach=0;in>>c.animal>>c.arm>>c.activation>>c.curvature>>c.extension>>c.twist>>c.stiffness>>attach;c.attach=attach!=0;if(!in||c.animal!=i/8||c.arm!=i%8||!std::isfinite(c.activation)||!std::isfinite(c.curvature)||!std::isfinite(c.extension)||!std::isfinite(c.twist)||!std::isfinite(c.stiffness)||(attach!=0&&attach!=1)){error="bad_command";break;}commands.push_back(c);}DragCommand d;int kind=0;in>>kind>>d.index>>d.arm>>d.target.x>>d.target.y>>d.target.z>>d.stiffness>>d.max_force;if(!in||kind<0||kind>3||!std::isfinite(d.target.x)||!std::isfinite(d.target.y)||!std::isfinite(d.target.z)||!std::isfinite(d.stiffness)||!std::isfinite(d.max_force))error="bad_drag";d.kind=static_cast<DragCommand::Kind>(kind);if(error.empty()){for(auto& c:commands)if(!world.command(c)){error="command_rejected";break;}if(error.empty()&&!world.drag(d))error="drag_rejected";if(error.empty()&&!world.step())error="step_failed";}}}else if(op!="snapshot")error="bad_operation";}
 std::cout<<"{\"version\":1,\"id\":"<<id<<",\"ok\":"<<(error.empty()?"true":"false");if(!error.empty())std::cout<<",\"error\":\""<<error<<'"';else{std::cout<<",\"snapshot\":";snapshot(world.snapshot());}std::cout<<'}'<<std::endl;}
}
