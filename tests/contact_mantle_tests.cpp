#include "octo/world.hpp"
#include <algorithm>
#include <cmath>
#include <iostream>
#include <stdexcept>
using namespace octo;
static void require(bool ok,const char* reason){if(!ok)throw std::runtime_error(reason);}
static double dist(Vec3 a,Vec3 b){return std::hypot(a.x-b.x,a.y-b.y,a.z-b.z);}
int main(){try{
 WorldConfig cfg;cfg.animals=1;cfg.rigid_count=3;cfg.grounded_rest=true;
 cfg.spawn_height=.27;cfg.upright_strength=.08;cfg.auto_suction=false;
 PhysicsWorld driven(cfg),control(cfg);
 const auto start=driven.snapshot();
 require(start.animals[0].body_nodes.size()==19,"mantle has twelve separate shell masses");
 DragCommand drag;drag.kind=DragCommand::Kind::ArmTip;drag.arm=0;
 drag.target={0,.28,1.55};drag.max_force=28;drag.stiffness=120;
 require(driven.drag(drag),"arm drag accepted");
 std::uint64_t surface_hits=0;double shell_difference=0,box_difference=0,volume_error=0;
 for(int tick=0;tick<180;++tick){
  require(driven.step()&&control.step(),"loaded mantle and contacts remain finite");
  const auto a=driven.snapshot(),b=control.snapshot();
  surface_hits+=a.diagnostics.arm_prop_surface_contacts;
  volume_error=std::max(volume_error,a.diagnostics.max_mantle_volume_error);
  for(size_t j=7;j<19;++j){
   shell_difference=std::max(shell_difference,dist(a.animals[0].body_nodes[j],b.animals[0].body_nodes[j]));
   require(a.animals[0].body_nodes[j].y>=cfg.visual_mantle_floor_radius-1e-6,
           "mantle shell does not sink through floor");
  }
  for(const auto& arm:a.animals[0].arms)for(size_t j=0;j<arm.nodes.size();++j){
   double u=double(j)/cfg.segments;
   require(arm.nodes[j].y>=cfg.visual_arm_floor_radius*(1.-.38*u)-1e-6,
           "arm visual envelope does not sink through floor");
  }
  for(size_t j=0;j<a.rigids.size();++j)
   box_difference=std::max(box_difference,dist(a.rigids[j].center,b.rigids[j].center));
 }
 std::cout<<"ARM_PROP_SURFACE hits="<<surface_hits<<" box_reaction_m="<<box_difference
          <<" shell_reaction_m="<<shell_difference<<" mantle_local_volume_error="<<volume_error<<'\n';
 require(surface_hits>0,"arm segment contacts box face");
 require(box_difference>.001,"box reacts to arm contact beyond passive fall");
 require(shell_difference>.002,"mantle shell responds to loaded arm");
 require(std::isfinite(volume_error)&&volume_error<.10,
         "loaded mantle local cells retain volume within ten percent");
 return 0;
}catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}}
