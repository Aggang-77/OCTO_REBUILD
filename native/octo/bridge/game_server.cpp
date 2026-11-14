// The original bridge remains buildable. The integrated game adds explicit
// terrain/contact/force inputs while keeping its versioned request envelope.
#define main original_bridge_main
#include "server.cpp"
#undef main

static void game_snapshot(const RenderSnapshot& s){
 std::cout<<"{\"world\":";render_snapshot(s);
 std::cout<<",\"body_nodes\":[";
 if(!s.animals.empty())for(size_t j=0;j<s.animals[0].body_nodes.size();++j){if(j)std::cout<<',';v(s.animals[0].body_nodes[j]);}
 std::cout<<"],\"reactions\":[";
 bool comma=false;for(const auto& r:s.scene_reactions){if(!r.collider)continue;if(comma)std::cout<<',';comma=true;
  std::cout<<"{\"collider\":"<<r.collider<<",\"impulse\":";v(r.impulse);std::cout<<",\"point\":";v(r.point);std::cout<<'}';
 }
 std::cout<<"]}";
}
int main(){
 std::cout<<std::setprecision(6);WorldConfig cfg;cfg.animals=1;cfg.rigid_count=0;PhysicsWorld world(cfg);
 std::string line;unsigned long long last=0;
 while(std::getline(std::cin,line)){
  std::istringstream in(line);int version=0;unsigned long long id=0;std::string op,error;in>>version>>id>>op;
  if(line.size()>131072)error="request_too_large";
  else if(!in||version!=1)error="bad_header";
  else if(id<=last)error="stale_id";
  else{
   last=id;
   if(op=="quit"){std::cout<<"{\"version\":1,\"id\":"<<id<<",\"ok\":true}"<<std::endl;break;}
   if(op=="game_reset"){
    Vec3 spawn;unsigned width=0;double x=0,z=0,cell=0;in>>spawn.x>>spawn.y>>spawn.z>>width>>x>>z>>cell;
    std::vector<double> heights;
    if(!in||!std::isfinite(spawn.x)||!std::isfinite(spawn.y)||!std::isfinite(spawn.z)||width<2||width>65)error="bad_config";
    else{heights.resize(size_t(width)*width);for(double& h:heights)in>>h;if(!in)error="bad_terrain";}
    std::string extra;if(in>>extra)error="extra_data";
    if(error.empty()){
     WorldConfig fresh;fresh.animals=1;fresh.rigid_count=0;fresh.auto_suction=true;fresh.spawn_height=spawn.y;fresh.spawn_origin={spawn.x,0,spawn.z};
     PhysicsWorld candidate(fresh);if(!candidate.terrain(width,x,z,cell,heights))error="bad_terrain";
     else{world=std::move(candidate);cfg=fresh;}
    }
   }else if(op=="step3"){
    unsigned n=0;in>>n;std::vector<MuscleCommand> commands;
    if(!in||n!=8)error="bad_count";
    for(unsigned i=0;i<n&&error.empty();++i){MuscleCommand c;int attached=0;
     in>>c.animal>>c.arm>>c.activation>>c.curvature>>c.extension>>c.twist>>c.stiffness>>attached>>c.sweep;
     if(!in||c.animal!=0||c.arm!=i||attached!=0||!std::isfinite(c.activation)||!std::isfinite(c.curvature)||!std::isfinite(c.extension)||!std::isfinite(c.twist)||!std::isfinite(c.stiffness)||!std::isfinite(c.sweep))error="bad_command";
     commands.push_back(c);
    }
    DragCommand drag;int kind=0,release=0;in>>kind>>drag.index>>drag.arm>>drag.target.x>>drag.target.y>>drag.target.z>>drag.stiffness>>drag.max_force>>release;
    if(!in||kind<0||kind>2||drag.index!=0||drag.arm>7||(release!=0&&release!=1))error="bad_drag";
    drag.kind=static_cast<DragCommand::Kind>(kind);
    unsigned count=0;in>>count;std::vector<SceneForce> forces;
    if(!in||count>64)error="bad_force_count";
    for(unsigned i=0;i<count&&error.empty();++i){SceneForce f;in>>f.arm>>f.node>>f.force.x>>f.force.y>>f.force.z;forces.push_back(f);}
    in>>count;std::vector<SceneContact> contacts;if(!in||count>192)error="bad_contact_count";
    for(unsigned i=0;i<count&&error.empty();++i){SceneContact c;in>>c.arm>>c.node>>c.point.x>>c.point.y>>c.point.z>>c.normal.x>>c.normal.y>>c.normal.z>>c.collider;contacts.push_back(c);}
    if(!in)error="incomplete_frame";
    std::string extra;if(in>>extra)error="extra_data";
    if(error.empty()&&!world.scene_inputs(forces,contacts))error="bad_scene_inputs";
    if(error.empty()&&!world.drag(drag))error="drag_rejected";
    if(error.empty()){
     for(const auto& c:commands)world.command(c);
     world.release_all_suckers(release==1);if(!world.step())error="step_failed";
    }
   }else if(op!="snapshot")error="bad_operation";
  }
  std::cout<<"{\"version\":1,\"id\":"<<id<<",\"ok\":"<<(error.empty()?"true":"false");
  if(!error.empty())std::cout<<",\"error\":\""<<error<<'"';
  else{std::cout<<",\"snapshot\":";
   // Flatten additions into the existing snapshot, consumed by the render client.
   std::cout<<"{\"frame\":";game_snapshot(world.snapshot());std::cout<<'}';}
  std::cout<<'}'<<std::endl;
 }
 return 0;
}
