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
  std::cout<<"control v1 tests passed\n";
  return 0;
}catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}}
