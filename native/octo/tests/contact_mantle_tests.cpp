#include "octo/world.hpp"
#include "octo/rod_math.hpp"
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
 {
  auto grip_cfg=cfg;grip_cfg.rigid_count=0;grip_cfg.auto_suction=true;
  grip_cfg.tissue_stiffness_ratio=.2;
  PhysicsWorld gripping(grip_cfg);MuscleCommand reach;
  reach.activation=1;reach.extension=1.48;
  require(gripping.command(reach),"reach command accepted for floor suction");
  std::uint64_t grips=0;
  for(int t=0;t<120;++t){require(gripping.step(),"floor grip stable");grips=std::max(grips,gripping.snapshot().diagnostics.attachments);}
  require(grips>0,"suckers grip the same conservative envelope used for floor collision");
  reach.activation=0;reach.extension=.76;
  require(gripping.command(reach),"peel command accepted");
  for(int t=0;t<60;++t)require(gripping.step(),"peeling stable");
  require(gripping.snapshot().diagnostics.attachments==0,"released arm cannot reacquire during peeling");
  std::cout<<"CONTACT_CYCLE native_grips="<<grips<<" after_release=0\n";
 }
 PhysicsWorld driven(cfg),control(cfg);
 const auto start=driven.snapshot();
 require(start.animals[0].body_nodes.size()==19,"mantle has twelve separate shell masses");
 DragCommand drag;drag.kind=DragCommand::Kind::ArmTip;drag.arm=0;
 drag.target={0,.28,1.55};drag.max_force=28;drag.stiffness=120;
 require(driven.drag(drag),"arm drag accepted");
 std::uint64_t surface_hits=0;double shell_difference=0,box_difference=0,volume_error=0,max_root_angle=0;
 for(int tick=0;tick<180;++tick){
  require(driven.step()&&control.step(),"loaded mantle and contacts remain finite");
  const auto a=driven.snapshot(),b=control.snapshot();
  namespace rm=rod_math;
  const auto& animal=a.animals[0];
  auto unit=[](Vec3 v){return rm::mul(v,1./std::max(rm::length(v),1e-8));};
  const Vec3 forward=unit(rm::sub(animal.body_nodes[5],animal.body_nodes[6]));
  const Vec3 up=unit(rm::sub(animal.body_nodes[3],animal.body_nodes[4]));
  const Vec3 right=unit(rm::cross(up,forward));
  for(int k=0;k<8;++k){
   double phi=k*std::acos(-1.)/4.;
   Vec3 axis=unit(rm::add(rm::mul(right,std::sin(phi)),rm::mul(forward,std::cos(phi))));
   Vec3 tangent=unit(rm::sub(animal.arms[k].nodes[1],animal.arms[k].nodes[0]));
   max_root_angle=std::max(max_root_angle,std::acos(std::clamp(rm::dot(axis,tangent),-1.,1.))*180./std::acos(-1.));
  }
  surface_hits+=a.diagnostics.arm_prop_surface_contacts;
  volume_error=std::max(volume_error,a.diagnostics.max_mantle_volume_error);
  // Mantle may lean, but its dorsal axis cannot rotate through the
  // proximal web's reference plane by ~180 degrees.
  {
   const auto& arms=animal.arms;
   const Vec3 web_forward=rm::sub(arms[0].nodes[2],arms[4].nodes[2]);
   const Vec3 web_right=rm::sub(arms[2].nodes[2],arms[6].nodes[2]);
   Vec3 web_normal=unit(rm::cross(web_forward,web_right));
   if(web_normal.y<0)web_normal=rm::mul(web_normal,-1.);
   const Vec3 dorsal_axis=unit(rm::sub(animal.body_nodes[3],animal.body_nodes[4]));
   const double orientation=rm::dot(web_normal,dorsal_axis);
   require(orientation>0.,
           "dorsal mantle must remain above the arm-web plane");
  }
  // The anatomical dorsal cage must not invert beneath the ventral cage.
  require(animal.body_nodes[3].y>=animal.body_nodes[4].y-.005,
          "mantle dorsal cage does not flip 180 degrees into the floor");
  double dorsal=0,ventral=0;
  for(int j=0;j<6;++j){
   ventral+=animal.body_nodes[7+j].y/6.;
   dorsal+=animal.body_nodes[13+j].y/6.;
  }
  require(dorsal>=ventral-.01,
          "mantle dorsal shell ring remains above ventral shell ring");
  // Physical mantle center and every shell mass must clear the new
  // skin envelope; particle-only collision would have allowed rendered
  // belly penetration even when the center was above the old radius.
  require(animal.body_nodes[0].y>=.17-1e-6,
          "inner mantle belly floor support");
  for(size_t j=7;j<19;++j){
   shell_difference=std::max(shell_difference,dist(a.animals[0].body_nodes[j],b.animals[0].body_nodes[j]));
   require(a.animals[0].body_nodes[j].y>=.125-1e-6,
           "outer mantle shell clears conservative floor skin envelope");
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
 std::cout<<"ROOT_MAX_ANGLE_DEG="<<max_root_angle<<'\n';
 require(max_root_angle<75.,"root cone remains bounded after contact projections");
 const auto passive=control.snapshot();
 double lower_z=0,upper_z=0;
 for(int j=0;j<6;++j){lower_z+=passive.animals[0].body_nodes[7+j].z/6.;upper_z+=passive.animals[0].body_nodes[13+j].z/6.;}
 std::cout<<"MANTLE_REAR_OFFSET="<<upper_z-lower_z<<'\n';
 require(upper_z<lower_z-.015,"upper mantle rests behind the lower arm junction");
 {
  WorldConfig soft;soft.animals=1;soft.rigid_count=0;
  soft.grounded_rest=true;soft.spawn_height=.27;soft.upright_strength=.08;
  soft.tissue_stiffness_ratio=.2;
  PhysicsWorld folding(soft);
  folding.reset(folding.config());
  require(folding.config().softness==soft.softness,"reset does not compound softness ratio");
  DragCommand pull;pull.kind=DragCommand::Kind::ArmTip;pull.arm=4;
  pull.target={0,.10,.85};pull.max_force=4;pull.stiffness=15;
  require(folding.drag(pull),"soft rear arm force accepted");
  double forward_motion=0;
  for(int i=0;i<600;++i){
   require(folding.step(),"twenty percent flesh remains finite");
   auto s=folding.snapshot();const auto& arm=s.animals[0].arms[4];
   forward_motion=std::max(forward_motion,arm.nodes.back().z-arm.nodes[0].z);
   for(const auto& limb:s.animals[0].arms)for(size_t j=0;j<limb.nodes.size();++j)
    require(limb.nodes[j].y>=soft.visual_arm_floor_radius*(1.-.38*double(j)/soft.segments)-1e-6,"soft arm native floor envelope stays above ground");
  }
  std::cout<<"SOFT_REAR_ARM_FORWARD_REACH_M="<<forward_motion<<'\n';
  require(forward_motion>.10,"soft rear arm can fold around to front under force");
  PhysicsWorld reclining(soft);
  for(int i=0;i<600;++i)require(reclining.step(),"passive rear fold remains finite");
  const auto relaxed=reclining.snapshot();
  const auto& cage=relaxed.animals[0].body_nodes;
  Vec3 heading=rod_math::sub(cage[5],cage[6]);
  heading=rod_math::mul(heading,1./rod_math::length(heading));
  Vec3 lo{},hi{};
  for(int i=0;i<6;++i){lo=rod_math::add(lo,rod_math::mul(cage[7+i],1./6));hi=rod_math::add(hi,rod_math::mul(cage[13+i],1./6));}
  std::cout<<"PASSIVE_MANTLE_LEAN="<<-rod_math::dot(rod_math::sub(hi,lo),heading)<<'\n';
  for(int k:{3,4}){
   const auto& ar=relaxed.animals[0].arms[k];
   const double z=rod_math::dot(rod_math::sub(ar.nodes[3],ar.nodes[0]),heading);
   std::cout<<"PASSIVE_REAR_FOLD arm="<<k<<" proximal_forward_z="<<z<<'\n';
   require(z>-.02,"reclining mantle lets rear proximal arm fold forward");
  }
 }
 return 0;
}catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}}
