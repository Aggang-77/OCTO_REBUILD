#include <octo/world.hpp>
#include <iostream>
#include <iomanip>
#include <sstream>
#include <string>
#include <cmath>
using namespace octo;
static void v(Vec3 p){std::cout<<'['<<p.x<<','<<p.y<<','<<p.z<<']';}
static void q(Quat p){std::cout<<'['<<p.x<<','<<p.y<<','<<p.z<<','<<p.w<<']';}
static const char* flag(bool value){return value?"true":"false";}
static void vectors(const std::vector<Vec3>& values){for(size_t j=0;j<values.size();++j){if(j)std::cout<<',';v(values[j]);}}
static void numbers(const std::vector<double>& values){for(size_t j=0;j<values.size();++j){if(j)std::cout<<',';std::cout<<values[j];}}
static void render_snapshot(const RenderSnapshot& s){
 std::cout<<"{\"tick\":"<<s.tick<<",\"time\":"<<s.time<<",\"size_scale\":"<<s.size_scale<<",\"static_triangles\":"<<s.static_triangles<<",\"animals\":[";
 for(size_t i=0;i<s.animals.size();++i){if(i)std::cout<<',';const auto& animal=s.animals[i];
  std::cout<<"{\"center\":";v(animal.center);std::cout<<",\"orientation\":";q(animal.orientation);
  std::cout<<",\"body_nodes\":[";vectors(animal.body_nodes);std::cout<<"],\"arms\":[";
  for(size_t k=0;k<8;++k){if(k)std::cout<<',';const auto& arm=animal.arms[k];
   std::cout<<"{\"phase\":"<<arm.phase<<",\"extend\":"<<flag(arm.extend)<<",\"stroke\":"<<flag(arm.stroke)<<",\"carry\":"<<flag(arm.carry)<<",\"rearm_required\":"<<flag(arm.rearm_required)<<",\"home_angle\":"<<arm.home_angle<<",\"model_arm\":"<<arm.model_arm<<",\"uncoil\":"<<arm.uncoil_progress;
   std::cout<<",\"nodes\":[";vectors(arm.nodes);
   std::cout<<"],\"sucker_directions\":[";vectors(arm.sucker_directions);
   std::cout<<"],\"contact_radii\":[";numbers(arm.contact_radii);
   std::cout<<"],\"grip_coverage\":[";numbers(arm.grip_coverage);
   std::cout<<"],\"roll\":[";numbers(arm.material_roll);
   std::cout<<"],\"radii\":[";for(size_t j=0;j<arm.radii.size();++j){if(j)std::cout<<',';std::cout<<'['<<arm.radii[j][0]<<','<<arm.radii[j][1]<<']';}
   std::cout<<"],\"tissue\":[";for(size_t j=0;j<arm.tissue_strain.size();++j){if(j)std::cout<<',';std::cout<<'['<<arm.tissue_strain[j][0]<<','<<arm.tissue_strain[j][1]<<']';}
   std::cout<<"],\"creep\":[";numbers(arm.creep_strain);
   std::cout<<"],\"elastic_strain\":[";numbers(arm.elastic_strain);
   std::cout<<"],\"volume_rings\":[";for(size_t j=0;j<arm.volume_rings.size();++j){if(j)std::cout<<',';std::cout<<'[';for(int n=0;n<4;++n){if(n)std::cout<<',';v(arm.volume_rings[j][n]);}std::cout<<']';}
   std::cout<<"],\"attached\":[";for(size_t j=0;j<arm.attached.size();++j){if(j)std::cout<<',';std::cout<<flag(arm.attached[j]);}std::cout<<"]}";
  }
  std::cout<<"]}";
 }
 std::cout<<"],\"rigids\":[";for(size_t i=0;i<s.rigids.size();++i){if(i)std::cout<<',';const auto& r=s.rigids[i];std::cout<<"{\"center\":";v(r.center);std::cout<<",\"orientation\":";q(r.orientation);std::cout<<",\"half_extents\":";v(r.half_extents);std::cout<<'}';}
 std::cout<<"],\"diagnostics\":{\"step_ms\":"<<s.diagnostics.step_ms<<",\"contact_count\":"<<s.diagnostics.contact_count<<",\"attachments\":"<<s.diagnostics.attachments<<",\"nonfinite_count\":"<<s.diagnostics.nonfinite_count<<"}}";
}
static bool read_muscles(std::istream& in,unsigned expected,bool sweep,bool explicit_controls,std::vector<MuscleCommand>& commands,std::string& error){
 unsigned count=0;in>>count;if(!in||count!=expected){error="bad_count";return false;}
 for(unsigned i=0;i<count;++i){MuscleCommand c;int attached=0,extend=0,stroke=0,carry=0;
  in>>c.animal>>c.arm>>c.activation>>c.curvature>>c.extension>>c.twist>>c.stiffness>>attached;
  if(sweep)in>>c.sweep;
  if(explicit_controls)in>>extend>>stroke>>carry;
  if(!in||c.animal!=i/8||c.arm!=i%8||!std::isfinite(c.activation)||!std::isfinite(c.curvature)||!std::isfinite(c.extension)||!std::isfinite(c.twist)||!std::isfinite(c.stiffness)||!std::isfinite(c.sweep)||(attached!=0&&attached!=1)||(extend!=0&&extend!=1)||(stroke!=0&&stroke!=1)||(carry!=0&&carry!=1)){error="bad_command";return false;}
  c.attach=attached!=0;c.explicit_control=explicit_controls;c.extend=extend!=0;c.stroke=stroke!=0;c.carry=carry!=0;commands.push_back(c);
 }
 return true;
}
static bool read_drag(std::istream& in,bool has_release,DragCommand& drag,int& release,std::string& error){
 int kind=0;in>>kind>>drag.index>>drag.arm>>drag.target.x>>drag.target.y>>drag.target.z>>drag.stiffness>>drag.max_force;
 if(has_release)in>>release;
 if(!in||kind<0||kind>3||!std::isfinite(drag.target.x)||!std::isfinite(drag.target.y)||!std::isfinite(drag.target.z)||!std::isfinite(drag.stiffness)||!std::isfinite(drag.max_force)||(release!=0&&release!=1)){error="bad_drag";return false;}
 drag.kind=static_cast<DragCommand::Kind>(kind);return true;
}
#ifndef OCTO_RENDER_LIBRARY
int main(){
 std::cout<<std::setprecision(6);WorldConfig cfg;PhysicsWorld world(cfg);std::string line;unsigned long long last=0;
 while(std::getline(std::cin,line)){
  std::istringstream in(line);int version=0;unsigned long long id=0;std::string op,error;in>>version>>id>>op;
  if(line.size()>65536)error="request_too_large";
  else if(!in||version!=1)error="bad_header";else if(id<=last)error="stale_id";
  else{last=id;
   if(op=="quit"){std::cout<<"{\"version\":1,\"id\":"<<id<<",\"ok\":true}"<<std::endl;break;}
   if(op=="reset"){
    unsigned count=0;double spacing=2.2,suction=0,volume=0,size=1;in>>count;
    std::vector<std::string> tokens;std::string token;while(in>>token)tokens.push_back(token);
    auto number=[&](size_t n,double& value){if(n>=tokens.size())return true;std::istringstream stream(tokens[n]);stream>>value;return bool(stream)&&stream.eof();};
    if(count<1||count>10||tokens.size()>4||!number(0,spacing)||!number(1,suction)||!number(2,volume)||!number(3,size)||!std::isfinite(spacing)||spacing<.5||spacing>4||(suction!=0&&suction!=1)||(volume!=0&&volume!=1)||!std::isfinite(size)||size<.5||size>3)error="bad_config";
    else{cfg.animals=count;cfg.spacing=spacing;cfg.auto_suction=suction!=0;cfg.volumetric_arm_prototype=volume!=0;cfg.size_scale=size;world.reset(cfg);}
   }else if(op=="step"||op=="step2"||op=="step4"){
    const bool sweep=op!="step",explicit_controls=op=="step4";std::vector<MuscleCommand> commands;DragCommand drag;int release=0;
    read_muscles(in,cfg.animals*8,sweep,explicit_controls,commands,error);
    if(error.empty())read_drag(in,sweep,drag,release,error);
    std::string extra;if(error.empty()&&(in>>extra))error="extra_data";
    if(error.empty()&&!world.drag(drag))error="drag_rejected";
    if(error.empty()){for(const auto& c:commands)world.command(c);world.release_all_suckers(release==1);if(!world.step())error="step_failed";}
   }else if(op!="snapshot")error="bad_operation";
  }
  std::cout<<"{\"version\":1,\"id\":"<<id<<",\"ok\":"<<flag(error.empty());
  if(error.empty()){std::cout<<",\"snapshot\":";render_snapshot(world.snapshot());}else std::cout<<",\"error\":\""<<error<<'"';
  std::cout<<'}'<<std::endl;
 }
 return 0;
}
#endif
