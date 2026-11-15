#include "octo/world.hpp"
#include <algorithm>
#include <cmath>
#include <iostream>
#include <stdexcept>
using namespace octo;
static void require(bool b,const char* reason){if(!b)throw std::runtime_error(reason);}
static double dist(Vec3 a,Vec3 b){return std::hypot(std::hypot(a.x-b.x,a.y-b.y),a.z-b.z);}
int main(){
 try {
  WorldConfig config;
  config.animals=1;config.rigid_count=0;config.segments=16;
  config.volumetric_arm_prototype=true;
  config.auto_suction=false;
  config.locomotion_assist=false; // Isolate passive material/contact response.
  config.gravity={0,-9.81,0};config.floor=true;config.spawn_height=.13;
  config.upright_strength=0;
  PhysicsWorld world(config);
  auto initial=world.snapshot();
  const auto& initial_rings=initial.animals[0].arms[0].volume_rings;
  require(initial_rings.size()==9,"prototype 9 cross-section rings");
  require(initial.animals[0].arms[1].volume_rings.empty(),
          "other seven arms remain baseline during pilot");
  double min_height=1000,max_soft_error=0,maximum_change=0,contact_sum=0;
  for(int tick=0;tick<240;++tick){
   require(world.step(),"finite 3D arm under gravity and floor contact");
   auto s=world.snapshot();
   max_soft_error=std::max(max_soft_error,s.diagnostics.max_soft_volume_error);
   contact_sum+=s.diagnostics.contact_count;
   const auto& rings=s.animals[0].arms[0].volume_rings;
   require(rings.size()==9,"ring count conserved");
   for(size_t j=0;j<rings.size();++j){
    for(int k=0;k<4;++k){
     const Vec3 current=rings[j][k];
     require(std::isfinite(current.x)&&std::isfinite(current.y)&&std::isfinite(current.z),
             "finite physical surface coordinates");
     min_height=std::min(min_height,current.y);
     maximum_change=std::max(maximum_change,dist(current,initial_rings[j][k]));
    }
   }
  }
  require(min_height>=-.001,"flesh surface particles respect floor");
  require(contact_sum>0,"volumetric flesh physically contacts floor");
  require(maximum_change>.001,"physical arm flesh moves independently");
  // Full gameplay world fixture: two octopuses, rigid props and floor
  // in the exact same C++ collision space (not separate simulations).
  {WorldConfig gameplay=config;
   gameplay.animals=2;gameplay.rigid_count=3;gameplay.locomotion_assist=true;
   gameplay.auto_suction=true;gameplay.spacing=1.5;
   PhysicsWorld shared(gameplay);
   double max_cage_error=0,max_soft=0;
   for(int tick=0;tick<300;++tick){
    require(shared.step(),"volumetric arm remains finite in two-animal world");
    const auto snap=shared.snapshot();
    require(snap.diagnostics.nonfinite_count==0,"finite two-animal flesh");
    max_cage_error=std::max(max_cage_error,snap.diagnostics.max_volume_error);
    max_soft=std::max(max_soft,snap.diagnostics.max_soft_volume_error);
   }
   std::cout<<"VOLUMETRIC_SHARED_WORLD cage_error="<<max_cage_error
            <<" soft_error="<<max_soft<<"\n";
   require(max_cage_error<.5,
           "volumetric pilot must not destabilize original torso");
  }
  std::cout<<"VOLUMETRIC_CONTACT_PASS surface_rings="<<initial_rings.size()
           <<" max_soft_volume_error="<<max_soft_error
           <<" max_surface_displacement="<<maximum_change
           <<" min_surface_y="<<min_height<<"\n";
  return 0;
 }catch(const std::exception& ex){std::cerr<<ex.what()<<"\n";return 1;}
}
