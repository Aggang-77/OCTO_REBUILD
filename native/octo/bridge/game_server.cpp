#define OCTO_RENDER_LIBRARY
#include "server.cpp"
static void game_snapshot(const RenderSnapshot& state,bool ready){
 std::cout<<"{\"geometry_ready\":"<<flag(ready)<<",\"world\":";render_snapshot(state);
 std::cout<<",\"body_nodes\":[";if(!state.animals.empty())vectors(state.animals[0].body_nodes);
 std::cout<<"],\"reactions\":[";bool comma=false;
 for(const auto& reaction:state.scene_reactions){if(!reaction.collider)continue;if(comma)std::cout<<',';comma=true;
  std::cout<<"{\"collider\":"<<reaction.collider<<",\"impulse\":";v(reaction.impulse);std::cout<<",\"point\":";v(reaction.point);std::cout<<'}';}
 std::cout<<"]}";
}
int main(){
 std::cout<<std::setprecision(6);WorldConfig cfg;cfg.animals=1;cfg.rigid_count=0;PhysicsWorld world(cfg);
 std::vector<Vec3> mesh_vertices;size_t mesh_expected=0;bool mesh_started=false,geometry_ready=true;
 std::string line;unsigned long long last=0;
 while(std::getline(std::cin,line)){
  std::istringstream in(line);int version=0;unsigned long long id=0;std::string op,error;in>>version>>id>>op;
  bool mesh_ack=false;
  if(line.size()>131072)error="request_too_large";
  else if(!in||version!=1)error="bad_header";else if(id<=last)error="stale_id";
  else{last=id;
   if(op=="quit"){std::cout<<"{\"version\":1,\"id\":"<<id<<",\"ok\":true}"<<std::endl;break;}
   if(op=="game_reset"||op=="game_reset4"){
    Vec3 spawn;double size=1;unsigned width=0;double x=0,z=0,cell=0;in>>spawn.x>>spawn.y>>spawn.z;if(op=="game_reset4")in>>size;in>>width>>x>>z>>cell;
    std::vector<double> heights;
    if(!in||!std::isfinite(spawn.x)||!std::isfinite(spawn.y)||!std::isfinite(spawn.z)||!std::isfinite(size)||size<.5||size>3||width<2||width>65)error="bad_config";
    else{heights.resize(size_t(width)*width);for(double& h:heights)in>>h;if(!in)error="bad_terrain";}
    std::string extra;if(error.empty()&&(in>>extra))error="extra_data";
    if(error.empty()){
     WorldConfig fresh;fresh.animals=1;fresh.rigid_count=0;fresh.auto_suction=true;fresh.spawn_height=spawn.y;fresh.spawn_origin={spawn.x,0,spawn.z};fresh.size_scale=size;
     PhysicsWorld candidate(fresh);if(!candidate.terrain(width,x,z,cell,heights))error="bad_terrain";
     else{world=std::move(candidate);cfg=fresh;geometry_ready=op!="game_reset4";mesh_started=false;mesh_vertices.clear();}
    }
   }else if(op=="mesh_begin"){
    size_t count=0;in>>count;std::string extra;
    if(!in||count>1000000||count%3||in>>extra)error="bad_mesh_count";
    else{mesh_expected=count;mesh_vertices.clear();mesh_vertices.reserve(count);mesh_started=true;geometry_ready=false;mesh_ack=true;}
   }else if(op=="mesh_chunk"){
    size_t offset=0,count=0;in>>offset>>count;std::vector<Vec3> chunk;
    if(!in||!mesh_started||offset!=mesh_vertices.size()||count>600||count>mesh_expected-mesh_vertices.size())error="bad_mesh_chunk";
    else{chunk.resize(count);for(auto& point:chunk){in>>point.x>>point.y>>point.z;if(!in||!std::isfinite(point.x)||!std::isfinite(point.y)||!std::isfinite(point.z)){error="bad_mesh_vertex";break;}}}
    std::string extra;if(error.empty()&&(in>>extra))error="extra_data";
    if(error.empty()){mesh_vertices.insert(mesh_vertices.end(),chunk.begin(),chunk.end());mesh_ack=true;}
   }else if(op=="mesh_commit"){
    std::string extra;
    if(!mesh_started||mesh_vertices.size()!=mesh_expected||in>>extra)error="incomplete_mesh";
    else if(!world.static_geometry(mesh_vertices))error="bad_mesh";
    else{geometry_ready=true;mesh_started=false;mesh_vertices.clear();}
   }else if(op=="step3"||op=="step4"){
    if(!geometry_ready)error="geometry_not_ready";
    std::vector<MuscleCommand> commands;DragCommand drag;int release=0;
    if(error.empty())read_muscles(in,8,true,op=="step4",commands,error);
    if(error.empty())read_drag(in,true,drag,release,error);
    if(error.empty()&&(drag.index!=0||drag.arm>7||drag.kind==DragCommand::Kind::Rigid))error="bad_drag";
    unsigned count=0;std::vector<SceneForce> forces;std::vector<SceneContact> contacts;
    if(error.empty()){in>>count;if(!in||count>64)error="bad_force_count";}
    for(unsigned i=0;i<count&&error.empty();++i){SceneForce force;in>>force.arm>>force.node>>force.force.x>>force.force.y>>force.force.z;forces.push_back(force);if(!in)error="bad_force";}
    if(error.empty()){in>>count;if(!in||count>192)error="bad_contact_count";}
    for(unsigned i=0;i<count&&error.empty();++i){SceneContact contact;in>>contact.arm>>contact.node>>contact.point.x>>contact.point.y>>contact.point.z>>contact.normal.x>>contact.normal.y>>contact.normal.z>>contact.collider;contacts.push_back(contact);if(!in)error="bad_contact";}
    std::string extra;if(error.empty()&&(in>>extra))error="extra_data";
    if(error.empty()&&!world.scene_inputs(forces,contacts))error="bad_scene_inputs";
    if(error.empty()&&!world.drag(drag))error="drag_rejected";
    if(error.empty()){for(const auto& command:commands)world.command(command);world.release_all_suckers(release==1);if(!world.step())error="step_failed";}
   }else if(op!="snapshot")error="bad_operation";
  }
  std::cout<<"{\"version\":1,\"id\":"<<id<<",\"ok\":"<<flag(error.empty());
  if(!error.empty())std::cout<<",\"error\":\""<<error<<'"';
  else if(mesh_ack)std::cout<<",\"mesh_upload\":true,\"offset\":"<<mesh_vertices.size();
  else{std::cout<<",\"snapshot\":{\"frame\":";game_snapshot(world.snapshot(),geometry_ready);std::cout<<'}';}
  std::cout<<'}'<<std::endl;
 }
 return 0;
}
