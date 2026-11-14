#include <octo/world.hpp>
#include <cmath>
#include <iostream>
#include <limits>
using namespace octo;
static int failures=0;
static void check(bool v,const char* text){std::cout<<(v?"PASS: ":"FAIL: ")<<text<<'\n';if(!v)++failures;}
int main(){
 WorldConfig cfg;cfg.animals=1;cfg.rigid_count=0;cfg.spawn_height=.75;cfg.spawn_origin={2,0,3};
 PhysicsWorld world(cfg);
 check(world.snapshot().animals[0].center.x==2&&world.snapshot().animals[0].center.z==3,"Spawn uses map coordinates");
 check(!world.terrain(2,0,0,0,{0,0,0,0}),"Reject invalid terrain spacing");
 check(world.terrain(2,-20,-20,40,{.4,.4,.4,.4}),"Accept map heightfield");
 bool finite_steps=true;for(int i=0;i<180;++i)finite_steps=world.step()&&finite_steps;
 check(finite_steps,"Terrain simulation stays finite for 180 steps");
 check(world.snapshot().animals[0].center.y>.4,"Octopus rests above map floor rather than y=0");
 WorldConfig gripping_cfg=cfg;gripping_cfg.auto_suction=true;gripping_cfg.spawn_height=1.15;
 PhysicsWorld gripping(gripping_cfg);gripping.terrain(2,-20,-20,40,{.4,.4,.4,.4});
 MuscleCommand reach;reach.arm=0;reach.activation=1;reach.extension=1.48;reach.stiffness=.02;
 gripping.command(reach);for(int i=0;i<180;++i)gripping.step();
 const auto grip_state=gripping.snapshot();bool terrain_grip=false;
 for(bool held:grip_state.animals[0].arms[0].attached)terrain_grip=terrain_grip||held;
 check(terrain_grip,"Latest uncoiling arm reaches and grips raised map terrain");
 check(grip_state.animals[0].arms[0].uncoil_progress>.99,"Latest progressive uncoiling remains active with terrain coupling");
 check(grip_state.animals[0].body_nodes.size()==19,"Latest physical mantle shell is retained");
 check(world.scene_inputs({{-1,18,{.1,0,0}}},{}),"Physical mantle-shell sites accept external character reactions");
 check(!world.scene_inputs({{9,0,{1,0,0}}},{}),"Reject invalid solver site");
 check(!world.scene_inputs({},{{0,0,{},{0,2,0},1}}),"Reject non-unit contact normal");
 cfg.floor=false;cfg.gravity={};cfg.damping=0;
 PhysicsWorld baseline(cfg),loaded(cfg);
 check(loaded.scene_inputs({{0,8,{.2,0,0}}},{}),"Accept bounded external spring load");
 baseline.step();loaded.step();
 auto a=baseline.snapshot().animals[0].arms[0].nodes[8],b=loaded.snapshot().animals[0].arms[0].nodes[8];
 check(std::abs(a.x-b.x)>1e-7,"External spring force reaches actual native arm dynamics");
 PhysicsWorld contact(cfg);auto p=contact.snapshot().animals[0].arms[0].nodes[8];
 check(contact.scene_inputs({},{{0,8,{p.x-.02,p.y,p.z},{1,0,0},7}}),"Accept scene contact plane");
 contact.step();auto reactions=contact.snapshot().scene_reactions;
 check(reactions.size()==1&&reactions[0].collider==7&&reactions[0].impulse.x<0,"Native contact returns an opposing impulse for the actual scene collider");
 check(contact.scene_inputs({},{}),"Clear old contact inputs");contact.step();
 check(contact.snapshot().scene_reactions.empty(),"Clearing contacts removes stale scene reactions");
 std::cout<<"SCENE_COUPLING_RESULT failures="<<failures<<'\n';return failures?1:0;
}
