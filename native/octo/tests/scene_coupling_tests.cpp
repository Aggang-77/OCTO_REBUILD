#include "octo/world.hpp"
#include <algorithm>
#include <cmath>
#include <iostream>
#include <limits>
#include <stdexcept>
using namespace octo;
namespace {
void require(bool ok,const char* text){if(!ok)throw std::runtime_error(text);}
double distance(Vec3 a,Vec3 b){return std::hypot(a.x-b.x,a.y-b.y,a.z-b.z);}
unsigned grips(const ArmSnapshot& a){return unsigned(std::count(a.attached.begin(),a.attached.end(),true));}
WorldConfig profile(){WorldConfig c;c.animals=1;c.rigid_count=0;c.spawn_height=.27;c.grounded_rest=true;c.tissue_stiffness_ratio=.2;c.upright_strength=.08;c.auto_suction=true;return c;}
void steps(PhysicsWorld& w,unsigned n){for(unsigned i=0;i<n;++i)require(w.step(),"scene fixture remains finite");}
std::vector<Vec3> plane(double y,double slope=0){return {{-4,y-4*slope,-4},{-4,y+4*slope,4},{4,y+4*slope,4},{-4,y-4*slope,-4},{4,y+4*slope,4},{4,y-4*slope,-4}};}
void same_state(const RenderSnapshot& a,const RenderSnapshot& b){
 require(a.tick==b.tick&&a.time==b.time,"empty adapters preserve source clock");
 const auto& x=a.animals[0];const auto& y=b.animals[0];require(distance(x.center,y.center)==0,"empty adapters preserve exact center trajectory");
 for(unsigned j=0;j<x.body_nodes.size();++j)require(distance(x.body_nodes[j],y.body_nodes[j])==0,"empty adapters preserve mantle/web positions");
 for(unsigned k=0;k<8;++k){const auto& u=x.arms[k];const auto& v=y.arms[k];
  require(u.attached==v.attached&&u.material_roll==v.material_roll&&u.creep_strain==v.creep_strain&&u.elastic_strain==v.elastic_strain,"empty adapters preserve grips/material state");
  for(unsigned j=0;j<u.nodes.size();++j)require(distance(u.nodes[j],v.nodes[j])==0,"empty adapters preserve exact arm positions");
  for(unsigned j=0;j<u.frames.size();++j){const auto q=u.frames[j],r=v.frames[j];require(q.x==r.x&&q.y==r.y&&q.z==r.z&&q.w==r.w,"empty adapters preserve material directors");}
 }
}
void empty_adapters(){
 const auto c=profile();PhysicsWorld source(c),empty(c);require(empty.static_geometry({})&&empty.scene_inputs({},{}),"empty integration accepted");empty.external_grips({});
 const auto initial=source.snapshot();require(initial.animals[0].center.x==0&&initial.animals[0].center.z==0&&initial.animals[0].center.y==.27,"source native origin/reset height retained");
 require(std::abs(distance(initial.animals[0].arms[0].nodes.front(),initial.animals[0].arms[0].nodes.back())-.9)<1e-12,"native arm geometry remains unscaled");
 for(const auto& arm:initial.animals[0].arms){require(arm.contact_radii.size()==arm.nodes.size()&&arm.sucker_directions.size()==arm.nodes.size(),"metadata addresses actual node sites");require(arm.contact_radii[0]>=.18&&arm.sucker_directions[0].y<-.99,"source envelope and underside exposed");}
 for(unsigned tick=0;tick<60;++tick){
  if(tick==8||tick==28||tick==44){MuscleCommand m;m.arm=0;m.activation=tick==44?0:.9;m.extension=tick==8?1.3:(tick==28?.7:1.04);m.stiffness=.1;require(source.command(m)&&empty.command(m),"source muscle command accepted");}
  require(source.step()&&empty.step(),"flat parity finite");same_state(source.snapshot(),empty.snapshot());
 }
 require(empty.config().tissue_stiffness_ratio==.2&&empty.config().upright_strength==.08,"requested source profile retained");std::cout<<"SCENE_EMPTY_ADAPTER_PARITY_PASS frames=60\n";
}
void terrain_and_geometry(){
 auto c=profile();c.spawn_height=.7;c.auto_suction=false;PhysicsWorld field(c),mesh(c);
 require(!field.terrain(2,0,0,0,{0,0,0,0}),"zero terrain cell rejected");require(field.terrain(2,-4,-4,8,{.2,.2,.2,.2}),"native heightfield accepted");
 require(mesh.static_geometry(plane(.2)),"actual triangle geometry accepted");require(mesh.static_triangle_count()==2&&mesh.snapshot().static_triangles==2,"triangle count exposed immediately");
 const double nan=std::numeric_limits<double>::quiet_NaN();require(!mesh.static_geometry({{nan,0,0},{0,0,0},{1,0,0}})&&mesh.static_triangle_count()==2,"invalid map preserves geometry");
 require(!field.terrain(2,-4,-4,8,{.2,nan,.2,.2}),"invalid heights rejected without replacement");steps(field,90);steps(mesh,90);
 for(const auto* w:{&field,&mesh}){const auto s=w->snapshot();require(s.animals[0].center.y>.2,"mantle rests above mapped floor");for(const auto& arm:s.animals[0].arms)for(Vec3 p:arm.nodes)require(p.y>=.2-1e-6,"mapped floor supports actual arm centers");}
 require(mesh.snapshot().diagnostics.static_triangles==2,"diagnostics report actual triangle count");
 PhysicsWorld slope(c);require(slope.static_geometry(plane(.1,.15)),"inclined triangle map accepted");steps(slope,90);const auto s=slope.snapshot();
 for(const auto& arm:s.animals[0].arms)for(Vec3 p:arm.nodes)require(p.y-.1-.15*p.z>=-1e-5,"triangle collision follows inclined normal");std::cout<<"SCENE_TERRAIN_PASS\n";
}
void scene_loads(){
 WorldConfig c;c.animals=1;c.rigid_count=0;c.floor=false;c.collisions=false;c.gravity={};c.damping=0;PhysicsWorld baseline(c),loaded(c);
 require(loaded.scene_inputs({{0,8,{.2,0,0}}},{}),"bounded scene force accepted");require(!loaded.scene_inputs({{9,0,{1,0,0}}},{}),"invalid arm rejected");require(!loaded.scene_inputs({{0,8,{1000,0,0}}},{}),"unbounded load rejected");steps(baseline,1);steps(loaded,1);
 require(distance(baseline.snapshot().animals[0].arms[0].nodes[8],loaded.snapshot().animals[0].arms[0].nodes[8])>1e-7,"force reaches dynamics and survives invalid replacement");require(loaded.scene_inputs({{-1,18,{.01,0,0}}},{}),"mantle shell accepts scene load");
 PhysicsWorld contact(c);const auto initial=contact.snapshot();const Vec3 p=initial.animals[0].arms[0].nodes[8];const double radius=initial.animals[0].arms[0].contact_radii[8];
 require(contact.scene_inputs({},{{0,8,{p.x-radius*.5,p.y,p.z},{1,0,0},7}}),"scene plane accepted");require(!contact.scene_inputs({},{{0,8,p,{0,2,0},7}}),"nonunit plane rejected");steps(contact,1);const auto reactions=contact.snapshot().scene_reactions;
 require(reactions.size()==1&&reactions[0].collider==7&&reactions[0].impulse.x<0,"actual collider receives opposing native impulse");require(contact.scene_inputs({},{}),"scene inputs clear");steps(contact,1);require(contact.snapshot().scene_reactions.empty(),"no stale reactions after clearing");std::cout<<"SCENE_REACTION_PASS impulse_x="<<reactions[0].impulse.x<<"\n";
}
void floor_mask(){
 auto c=profile();c.spawn_height=.5;PhysicsWorld w(c);require(w.static_geometry(plane(.15)),"raised mapped suction fixture accepted");w.set_suction_enabled(true);MuscleCommand m;m.arm=0;m.activation=1;m.extension=1.2;m.stiffness=.02;require(w.command(m),"source controlled grip accepted");unsigned acquired=0;
 for(unsigned i=0;i<150&&!acquired;++i){steps(w,1);acquired=grips(w.snapshot().animals[0].arms[0]);}require(acquired>0,"real upstream floor grip acquired");
 std::array<bool,8> mask{};mask[0]=true;w.external_grips(mask);require(grips(w.snapshot().animals[0].arms[0])==0,"external carry immediately releases native floor grip");
 for(unsigned i=0;i<45;++i){steps(w,1);require(grips(w.snapshot().animals[0].arms[0])==0,"external carry blocks floor reacquisition");}w.external_grips({});unsigned reacquired=0;
 for(unsigned i=0;i<90&&!reacquired;++i){steps(w,1);reacquired=grips(w.snapshot().animals[0].arms[0]);}require(reacquired>0,"clearing mask restores source floor gripping");std::cout<<"SCENE_EXTERNAL_FLOOR_MASK_PASS\n";
}
void object_mask(){
 WorldConfig c;c.animals=1;c.rigid_count=1;c.floor=false;c.collisions=false;c.gravity={};c.spawn_height=.32;PhysicsWorld w(c);MuscleCommand m;m.arm=0;m.activation=1;m.extension=1.35;m.attach=true;w.command(m);
 DragCommand d;d.kind=DragCommand::Kind::ArmTip;d.arm=0;d.target={-.49,.16,1.19};d.stiffness=100;d.max_force=20;require(w.drag(d),"bounded object setup accepted");bool held=false;
 for(unsigned i=0;i<150&&!held;++i){steps(w,1);held=grips(w.snapshot().animals[0].arms[0])>0;}require(held,"real upstream native object grip acquired");std::array<bool,8> mask{};mask[0]=true;w.external_grips(mask);require(grips(w.snapshot().animals[0].arms[0])>0,"external floor mask retains native object attachment");std::cout<<"SCENE_NATIVE_OBJECT_MASK_PASS\n";
}
}
int main(){try{empty_adapters();terrain_and_geometry();scene_loads();floor_mask();object_mask();std::cout<<"SCENE_COUPLING_PASS\n";return 0;}catch(const std::exception& e){std::cerr<<"SCENE_COUPLING_FAIL "<<e.what()<<"\n";return 1;}}
