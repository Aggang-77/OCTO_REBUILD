#include "octo/viscoelastic.hpp"
#include <cmath>
#include <iostream>
#include <stdexcept>

static void check(bool ok,const char* text) {
    if(!ok)throw std::runtime_error(text);
}
int main(){
 try {
  using namespace octo::viscoelastic;
  constexpr double dt=1.0/240.0;
  double q=0;
  const double initial_stress=elastic_stress_proxy(.20,q);
  double at_one_second=0;
  for(int tick=0;tick<720;++tick){
   q=update_creep(q,.20,dt,.70,.06,.25);
   if(tick==239)at_one_second=q;
  }
  const double held_creep=q;
  const double relaxed_stress=elastic_stress_proxy(.20,q);
  check(at_one_second>.04,"sustained strain accumulates time-delayed creep");
  check(held_creep>at_one_second,"creep increases with holding time");
  check(relaxed_stress<initial_stress*.40,
        "constant deformation relaxes most of the elastic stress");
  const double after_hold=q;
  for(int tick=0;tick<1440;++tick)
   q=update_creep(q,0.,dt,.70,.06,.25);
  check(q<after_hold*.12,"unloaded material eventually recovers");
  // Exact exponential update must not be dependent on substep count.
  double coarse=0,fine=0;
  for(int i=0;i<60;++i)coarse=update_creep(coarse,.25,1./60.,.70,.06,.25);
  for(int i=0;i<240;++i)fine=update_creep(fine,.25,1./240.,.70,.06,.25);
  check(std::abs(coarse-fine)<1e-12,"creep invariant to substep time discretization");
  check(update_creep(0,5.0,10,.7,.06,.25)<=.25,
        "large collisions cannot create unbounded creep");
  check(update_creep(0,.2,.1,0,0,.25)==0,
        "zero creep rates retain purely elastic baseline");
  std::cout<<"CREEP_STRESS_PASS initial_stress="<<initial_stress
           <<" relaxed_stress="<<relaxed_stress
           <<" creep_1s="<<at_one_second
           <<" creep_3s="<<held_creep
           <<" recovered_6s="<<q<<"\n";
  return 0;
 } catch(const std::exception& e) {
  std::cerr<<e.what()<<"\n";
  return 1;
 }
}
