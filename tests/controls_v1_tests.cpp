#include "octo/world.hpp"
#include <algorithm>
#include <cmath>
#include <iostream>
#include <stdexcept>
using namespace octo;

static void require(bool ok,const char* msg){if(!ok)throw std::runtime_error(msg);}
static double distance(Vec3 a,Vec3 b){return std::hypot(std::hypot(a.x-b.x,a.y-b.y),a.z-b.z);}

int main(){try{
  WorldConfig isolated;
  isolated.animals=1;isolated.rigid_count=0;isolated.gravity={0,0,0};
  isolated.floor=false;isolated.collisions=false;isolated.damping=.4;
  PhysicsWorld forward(isolated),backward(isolated);
  MuscleCommand m;m.arm=0;m.activation=1;m.curvature=0;m.extension=1.28;m.sweep=-1;
  auto initial=forward.snapshot();
  require(forward.command(m),"forward paddle accepted");
  m.sweep=1;require(backward.command(m),"backward paddle accepted");
  require(distance(initial.animals[0].arms[0].nodes.back(),
                   backward.snapshot().animals[0].arms[0].nodes.back())<1e-12,
          "command must not teleport arm");
  for(int i=0;i<90;++i){
    require(forward.step(),"forward paddle stable");
    require(backward.step(),"backward paddle stable");
  }
  auto a=forward.snapshot(),b=backward.snapshot();
  const double delta=distance(a.animals[0].arms[0].nodes.back(),b.animals[0].arms[0].nodes.back());
  std::cout<<"CONTROL_V1_MOTOR opposite_sweep_delta_m="<<delta<<"\n";
  require(delta>.003,"opposite strokes physically distinguishable");
  require(a.diagnostics.nonfinite_count==0&&b.diagnostics.nonfinite_count==0,"finite sweep state");

  // Actuator power must produce more arm motion than the previous
  // conservative baseline under identical physical initial conditions.
  WorldConfig weak_cfg=isolated, strong_cfg=isolated;
  weak_cfg.arm_motor_strength=1.0;
  strong_cfg.arm_motor_strength=4.0;
  PhysicsWorld weak(weak_cfg),strong(strong_cfg);
  MuscleCommand push;m.arm=0;
  push.arm=0;push.activation=1;push.curvature=0;push.extension=1.0;
  push.sweep=1.0;
  require(weak.command(push)&&strong.command(push),"test stroke command accepted");
  const Vec3 start_tip=weak.snapshot().animals[0].arms[0].nodes.back();
  for(int i=0;i<16;++i){
    require(weak.step(),"weak baseline remains finite");
    require(strong.step(),"strong motor remains finite");
  }
  const auto weak_snapshot=weak.snapshot(),strong_snapshot=strong.snapshot();
  const double weak_travel=distance(start_tip,weak_snapshot.animals[0].arms[0].nodes.back());
  const double strong_travel=distance(start_tip,strong_snapshot.animals[0].arms[0].nodes.back());
  std::cout<<"CONTROL_V1_POWER weak_tip_motion_m="<<weak_travel
           <<" strong_tip_motion_m="<<strong_travel<<"\n";
  require(strong_travel>weak_travel*1.05,
          "increased actuator strength must measurably increase stroke motion");
  require(strong_snapshot.diagnostics.nonfinite_count==0,
          "strong motor state remains finite");

  // Invalid / unbounded forces cannot silently enter the solver.
  {auto invalid=isolated; invalid.arm_motor_strength=15.;
   bool rejected=false;try{PhysicsWorld bad(invalid);}catch(const std::invalid_argument&){rejected=true;}
   require(rejected,"reject unsafe actuator strength");}
  WorldConfig floor;
  floor.animals=1;floor.rigid_count=0;floor.floor=true;floor.collisions=false;
  floor.gravity={0,-9.81,0};floor.spawn_height=.14;
  floor.auto_suction=true;floor.damping=.6;
  PhysicsWorld sticky(floor);
  std::uint64_t grip=0;
  for(int i=0;i<240;++i){
    require(sticky.step(),"automatic grip stable");
    grip=std::max(grip,sticky.snapshot().diagnostics.attachments);
  }
  std::cout<<"CONTROL_V1_GRIP max_auto_floor_contacts="<<grip<<"\n";
  require(grip>0,"stable real-contact floor probes should grip");
  sticky.release_all_suckers(true);
  require(sticky.step(),"Space release stable");
  require(sticky.snapshot().diagnostics.attachments==0,"Space releases every grip");
  for(int i=0;i<10;++i){
    require(sticky.step(),"held Space stable");
    require(sticky.snapshot().diagnostics.attachments==0,"held Space forbids new grip");
  }
  sticky.release_all_suckers(false);
  for(int i=0;i<5;++i){
    require(sticky.step(),"cooldown stable");
    require(sticky.snapshot().diagnostics.attachments==0,"no instantaneous regrip");
  }
  // Extension must seek an actual floor contact, then acquire an
  // ordinary suction constraint; no distant/teleported attachment.
  {auto reach_cfg=floor;reach_cfg.spawn_height=.75;reach_cfg.softness=5.;
   PhysicsWorld reaching(reach_cfg);
   MuscleCommand extend;extend.arm=0;extend.activation=1;
   extend.extension=1.48;extend.curvature=0;extend.sweep=-1;
   require(reaching.command(extend),"reach-for-floor command accepted");
   std::uint64_t acquired=0;
   for(int i=0;i<240;++i){
    require(reaching.step(),"reach-for-floor physics stays finite");
    acquired=std::max(acquired,reaching.snapshot().diagnostics.attachments);
   }
   std::cout<<"CONTROL_V1_REACH_GROUND max_contacts="<<acquired<<"\n";
   require(acquired>0,"extending arm eventually grips contacted floor");
   reaching.release_all_suckers(true);
   require(reaching.step(),"reach grip Space release stable");
   require(reaching.snapshot().diagnostics.attachments==0,
           "Space overrides reach-for-floor adhesion");
  }
  // Coil/uncoil progresses through the rod over time instead of
  // instantaneously resizing a straight tube.
  {auto c=isolated;c.auto_suction=false;c.coil_curvature=8.0;c.uncoil_speed=2.0;
   PhysicsWorld coiling(c);
   const double start=coiling.snapshot().animals[0].arms[0].uncoil_progress;
   require(start==0.0,"arm starts with an unreleased coil");
   MuscleCommand extend;extend.arm=0;extend.activation=1;
   extend.extension=1.48;extend.curvature=0;extend.sweep=0;
   require(coiling.command(extend),"uncoil command accepted");
   for(int i=0;i<15;++i)require(coiling.step(),"uncoiling is finite");
   const double mid=coiling.snapshot().animals[0].arms[0].uncoil_progress;
   require(mid>.35&&mid<.65,"base-to-tip uncoil wave travels gradually");
   for(int i=0;i<20;++i)require(coiling.step(),"uncoil reaches distal end");
   const double extended=coiling.snapshot().animals[0].arms[0].uncoil_progress;
   require(extended>.98,"whole arm uncoils after sufficient time");
   extend.extension=.58;extend.curvature=3.6;
   require(coiling.command(extend),"recoil command accepted");
   for(int i=0;i<15;++i)require(coiling.step(),"recoiling stays finite");
   const double returned=coiling.snapshot().animals[0].arms[0].uncoil_progress;
   require(returned<extended-.35,"recoil front retreats when key released");
   std::cout<<"UNCOIL_PASS start="<<start<<" mid="<<mid
            <<" extended="<<extended<<" returned="<<returned<<"\n";
  }
  // Upright correction is a physical field, not a graphics transform.
  // It must stay finite with collisions and gravity in the shared world.
  {auto c=floor;c.upright_strength=.45;c.arm_motor_strength=2.2;
   PhysicsWorld stable(c);
   for(int i=0;i<240;++i)require(stable.step(),"upright field remains stable");
   require(stable.snapshot().diagnostics.nonfinite_count==0,
           "upright constraint has finite physical state");
  }
  {auto invalid=isolated;invalid.upright_strength=3.0;
   bool rejected=false;try{PhysicsWorld no(invalid);}catch(const std::invalid_argument&){rejected=true;}
   require(rejected,"unbounded stabilization torque must be rejected");
  }
  // Start genuinely rolled over, not merely upright and motionless.
  // Both worlds have the same initial physical cage/arms. The unassisted
  // one keeps its initial roll in zero gravity; the corrected one must
  // develop a more upward top-to-bottom torso axis.
  {WorldConfig passive=isolated;
   passive.spawn_roll=2.65;passive.coil_curvature=0;
   passive.upright_strength=0;passive.damping=.5;
   WorldConfig assisted=passive;assisted.upright_strength=.45;
   PhysicsWorld untreated(passive),restored(assisted);
   auto cos_tilt=[](const RenderSnapshot& s)->double{
    const auto& body=s.animals[0].body_nodes;
    return (body[3].y-body[4].y)/distance(body[3],body[4]);
   };
   const double initial_tilt=cos_tilt(restored.snapshot());
   double best_assisted=initial_tilt,best_passive=initial_tilt;
   for(int i=0;i<240;++i){
    require(untreated.step()&&restored.step(),"tilted-body recovery finite");
    best_assisted=std::max(best_assisted,cos_tilt(restored.snapshot()));
    best_passive=std::max(best_passive,cos_tilt(untreated.snapshot()));
   }
   std::cout<<"UPRIGHT_RECOVERY initial="<<initial_tilt
            <<" best_assisted="<<best_assisted
            <<" best_passive="<<best_passive<<"\n";
   require(best_assisted>best_passive+.10,
           "upright motor measurably corrects a rolled-over body");
  }
  // Low-resolution mantle tissue is dynamic geometry with 12 genuine
  // colliding mass nodes, not a decorative rubber shader.
  {auto c=floor;c.spawn_height=.12;c.tissue_viscosity=10.0;
   PhysicsWorld tissue_world(c);
   auto start=tissue_world.snapshot();
   require(start.animals[0].body_nodes.size()==19,
           "mantle includes seven cage and twelve physical shell nodes");
   require(start.animals[0].arms[0].tissue_strain.size()==c.segments,
           "each arm section maintains two transverse material strains");
   double max_strain=0;
   for(int i=0;i<180;++i){
    require(tissue_world.step(),"viscoelastic mantle remains finite");
    auto snapshot=tissue_world.snapshot();
    for(auto strain:snapshot.animals[0].arms[0].tissue_strain){
     require(std::isfinite(strain[0])&&std::isfinite(strain[1]),
             "section strains always finite");
     require(strain[0]>=.49&&strain[0]<=2.51 &&
             strain[1]>=.39&&strain[1]<=1.51,
             "section strain stays inside mechanical yield bounds");
     require(std::abs(strain[0]*strain[1]-1.)<1e-9,
             "elliptic tissue redistributes transverse area");
     max_strain=std::max(max_strain,std::abs(strain[1]-1.));
    }
    for(const auto& node:snapshot.animals[0].body_nodes)
     require(node.y>=-.001,"colliding mantle nodes do not cross ground");
   }
   require(max_strain>.10,
           "floor contact must cause at least 10% local transverse deformation");
   std::cout<<"TISSUE_PASS mantle_nodes="<<
     tissue_world.snapshot().animals[0].body_nodes.size()<<
     " max_transverse_strain="<<max_strain<<"\n";
  }
  {auto invalid=isolated;invalid.tissue_viscosity=-3;
   bool rejected=false;try{PhysicsWorld no(invalid);}catch(const std::invalid_argument&){rejected=true;}
   require(rejected,"negative tissue viscosity is not accepted");
  }
  std::cout<<"control v1 tests passed\n";
  return 0;
}catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}}
