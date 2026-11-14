#include "octo/world.hpp"
#include <cmath>
#include <iostream>
#include <limits>
#include <string>

namespace {
int failures=0;
void check(bool value,const std::string& name) {std::cout<<(value?"PASS ":"FAIL ")<<name<<'\n';if(!value) ++failures;}
double distance(octo::Vec3 a,octo::Vec3 b){return std::sqrt((a.x-b.x)*(a.x-b.x)+(a.y-b.y)*(a.y-b.y)+(a.z-b.z)*(a.z-b.z));}
bool finite(const octo::RenderSnapshot& s) {
    const auto f=[](octo::Vec3 p){return std::isfinite(p.x)&&std::isfinite(p.y)&&std::isfinite(p.z);};
    for(const auto& a:s.animals){if(!f(a.center))return false;for(auto p:a.body_nodes)if(!f(p))return false;for(const auto& r:a.arms)for(auto p:r.nodes)if(!f(p))return false;}
    for(const auto& r:s.rigids)if(!f(r.center))return false;
    return s.diagnostics.nonfinite_count==0;
}
void api_contract(){
    octo::WorldConfig cfg;cfg.animals=1;octo::PhysicsWorld w(cfg);
    auto first=w.snapshot();octo::MuscleCommand c;c.animal=2;check(!w.command(c),"invalid animal rejected");
    c.animal=0;c.arm=8;check(!w.command(c),"invalid arm rejected");c.arm=0;c.activation=std::numeric_limits<double>::quiet_NaN();check(!w.command(c),"NaN command rejected");
    c.activation=.8;c.curvature=2;c.extension=.8;check(w.command(c),"finite command accepted");
    check(distance(first.animals[0].arms[0].nodes.back(),w.snapshot().animals[0].arms[0].nodes.back())==0,"muscle command does not teleport");
    check(w.step(),"first step succeeds");check(w.snapshot().tick==1,"one call advances one fixed tick");
    check(std::abs(w.snapshot().time-cfg.fixed_dt)<1e-10,"clock equals fixed dt");
    check(first.tick==0&&first.animals[0].arms[0].nodes.size()==cfg.segments+1,"snapshot is owned and has stable shape");
    w.reset(cfg);check(w.snapshot().tick==0&&distance(first.animals[0].center,w.snapshot().animals[0].center)<1e-10,"reset reconstructs initial state");
}
void independent_input(){
    octo::WorldConfig cfg;cfg.animals=1;cfg.floor=false;cfg.collisions=false;cfg.gravity={0,0,0};cfg.rigid_count=0;
    octo::PhysicsWorld driven(cfg),passive(cfg);octo::MuscleCommand cmd;cmd.activation=1;cmd.curvature=2;cmd.extension=.75;cmd.stiffness=.5;driven.command(cmd);
    for(int i=0;i<120;++i){driven.step();passive.step();}
    const auto d=driven.snapshot(),p=passive.snapshot();
    const double moved=distance(d.animals[0].arms[0].nodes.back(),p.animals[0].arms[0].nodes.back());
    std::cout<<"METRIC active_arm_tip_delta_m="<<moved<<'\n';
    check(moved>.01&&finite(d),"selected muscle produces finite physical response");
    double root_motion=distance(d.animals[0].center,p.animals[0].center);
    std::cout<<"METRIC body_reaction_displacement_m="<<root_motion<<'\n';
    check(root_motion>1e-5,"internal actuation reacts on body");
}
void shared_world(){
    octo::WorldConfig cfg;cfg.animals=2;octo::PhysicsWorld w(cfg);
    bool ok=true;double worst_pen=0,worst_volume=0;std::uint64_t contacts=0;
    for(int tick=0;tick<600;++tick){
        octo::MuscleCommand c;c.animal=(tick/150)%2;c.arm=(tick/30)%8;c.activation=.8;c.extension=.85;c.curvature=1.5;w.command(c);
        if(!w.step()){ok=false;break;}const auto s=w.snapshot();ok=ok&&finite(s);contacts+=s.diagnostics.contact_count;worst_pen=std::max(worst_pen,s.diagnostics.max_penetration);worst_volume=std::max(worst_volume,s.diagnostics.max_volume_error);
    }
    check(ok,"two animals active 600 ticks finite");check(contacts>0,"shared-world fixture actually exercises contacts");
    std::cout<<"METRIC shared_max_penetration_m="<<worst_pen<<" shared_max_volume_error="<<worst_volume<<'\n';
    check(worst_pen<.03,"prototype sampled contacts below 30mm (not full skin gate)");
}
void soak(int count,int ticks){
    octo::WorldConfig cfg;cfg.animals=static_cast<unsigned>(count);octo::PhysicsWorld w(cfg);bool ok=true;double max_pen=0,max_vol=0;
    for(int tick=0;tick<ticks;++tick){
        if(tick%30==0)for(int animal=0;animal<count;++animal){octo::MuscleCommand c;c.animal=animal;c.arm=(tick/30+animal)%8;c.activation=.8;c.curvature=1.5;c.extension=(tick/120)%2?.85:1.1;c.attach=(tick/60)%2;ok=ok&&w.command(c);}
        if(!w.step()){ok=false;break;}
        if(tick%30==0){const auto s=w.snapshot();ok=ok&&finite(s);max_pen=std::max(max_pen,s.diagnostics.max_penetration);max_vol=std::max(max_vol,s.diagnostics.max_volume_error);}
    }
    const auto final=w.snapshot();ok=ok&&finite(final)&&final.tick==static_cast<std::uint64_t>(ticks);
    std::cout<<"METRIC soak_animals="<<count<<" ticks="<<final.tick<<" sampled_max_penetration_m="<<max_pen<<" sampled_max_volume_error="<<max_vol<<'\n';
    check(ok,"T12 long-run finite state and exact tick count");
}
}
int main(int argc,char**argv){
    if(argc>1&&std::string(argv[1])=="soak"){soak(argc>2?std::stoi(argv[2]):2,argc>3?std::stoi(argv[3]):10000);}
    else {api_contract();independent_input();shared_world();}
    std::cout<<"INTEGRATION_FAILURES="<<failures<<'\n';return failures?1:0;
}
