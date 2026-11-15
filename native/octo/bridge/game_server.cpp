#define OCTO_RENDER_LIBRARY
#include "server.cpp"
#include <array>
namespace {
constexpr const char* source_sha="9a2a7df438bb5098b9f8492bbb55897c96fb52c4";
struct MapTransform {
 Vec3 origin{};double scale=1.5;
 Vec3 world(Vec3 p)const{return {origin.x+scale*p.x,origin.y+scale*p.y,origin.z+scale*p.z};}
 Vec3 local(Vec3 p)const{return {(p.x-origin.x)/scale,(p.y-origin.y)/scale,(p.z-origin.z)/scale};}
 Vec3 vector(Vec3 p)const{return {scale*p.x,scale*p.y,scale*p.z};}
 Vec3 force(Vec3 p)const{return {p.x/scale,p.y/scale,p.z/scale};}
};
const char* flag(bool value){return value?"true":"false";}
bool finite_vector(Vec3 p){return std::isfinite(p.x)&&std::isfinite(p.y)&&std::isfinite(p.z);}
RenderSnapshot mapped(RenderSnapshot state,const MapTransform& map){
 for(auto& animal:state.animals){
  animal.center=map.world(animal.center);for(auto& p:animal.body_nodes)p=map.world(p);
  for(auto& arm:animal.arms){
   for(auto& p:arm.nodes)p=map.world(p);
   for(auto& r:arm.radii){r[0]*=map.scale;r[1]*=map.scale;}
   for(auto& r:arm.contact_radii)r*=map.scale;
   for(auto& r:arm.grab_radii)r*=map.scale;
   for(auto& ring:arm.volume_rings)for(auto& p:ring)p=map.world(p);
  }
 }
 for(auto& rigid:state.rigids){rigid.center=map.world(rigid.center);rigid.half_extents=map.vector(rigid.half_extents);}
 for(auto& reaction:state.scene_reactions){reaction.point=map.world(reaction.point);reaction.impulse=map.vector(reaction.impulse);}
 return state;
}
void frame_json(const PhysicsWorld& world,const MapTransform& map,bool ready){
 const auto state=mapped(world.snapshot(),map);
 // Reuse the source branch's renderer transport; append adapter metadata.
 std::ostringstream buffer;auto* output=std::cout.rdbuf(buffer.rdbuf());render_snapshot(state);std::cout.rdbuf(output);
 std::string json=buffer.str();json.pop_back();
 std::cout<<"{\"geometry_ready\":"<<flag(ready)<<",\"world\":"<<json
  <<",\"size_scale\":"<<map.scale<<",\"static_triangles\":"<<state.static_triangles
  <<",\"source_ref\":\"fix/contact-mantle-balloon\",\"source_commit\":\""<<source_sha<<"\"},\"body_nodes\":[";
 if(!state.animals.empty())for(size_t i=0;i<state.animals[0].body_nodes.size();++i){if(i)std::cout<<',';v(state.animals[0].body_nodes[i]);}
 std::cout<<"],\"reactions\":[";bool comma=false;
 for(const auto& reaction:state.scene_reactions){if(!reaction.collider)continue;if(comma)std::cout<<',';comma=true;
  std::cout<<"{\"collider\":"<<reaction.collider<<",\"impulse\":";v(reaction.impulse);std::cout<<",\"point\":";v(reaction.point);std::cout<<'}';}
 std::cout<<"]}";
}
bool read_step(std::istream& in,const MapTransform& map,std::vector<MuscleCommand>& commands,
 DragCommand& drag,bool& suction,std::array<bool,8>& carry,std::vector<SceneForce>& forces,
 std::vector<SceneContact>& contacts,std::string& error){
 unsigned count=0;in>>count;if(!in||count!=8){error="bad_count";return false;}
 for(unsigned i=0;i<count;++i){MuscleCommand command;int attach=0;
  in>>command.animal>>command.arm>>command.activation>>command.curvature>>command.extension
    >>command.twist>>command.stiffness>>attach>>command.sweep;
  if(!in||command.animal!=0||command.arm!=i||!std::isfinite(command.activation)||!std::isfinite(command.curvature)
    ||!std::isfinite(command.extension)||!std::isfinite(command.twist)||!std::isfinite(command.stiffness)
    ||!std::isfinite(command.sweep)||attach<0||attach>2){error="bad_command";return false;}
  command.attach=false;command.grab_mode=static_cast<unsigned>(attach);commands.push_back(command);
 }
 int kind=0,space=0;in>>kind>>drag.index>>drag.arm>>drag.target.x>>drag.target.y>>drag.target.z>>drag.stiffness>>drag.max_force>>space;
 if(!in||kind<0||kind>2||drag.index!=0||drag.arm>7||!finite_vector(drag.target)||!std::isfinite(drag.stiffness)
    ||!std::isfinite(drag.max_force)||drag.stiffness<0||drag.stiffness>1e5||drag.max_force<0||drag.max_force>1e4
    ||(space!=0&&space!=1)){error="bad_drag";return false;}
 drag.kind=static_cast<DragCommand::Kind>(kind);drag.target=map.local(drag.target);drag.max_force/=map.scale;
 if(drag.max_force>1e4){error="bad_drag";return false;}
 suction=space!=0;
 int target_kind=0,target_index=0;Vec3 target_point{};
 in>>target_kind>>target_index>>target_point.x>>target_point.y>>target_point.z;
 if(!in||target_kind<0||target_kind>3||target_index<0||!finite_vector(target_point)){error="bad_target";return false;}
 if(target_kind>0&&target_kind<3)for(auto& command:commands)if(command.grab_mode==1){
  command.grab_target_kind=static_cast<unsigned>(target_kind);
  command.grab_target_index=static_cast<unsigned>(target_index);
  command.grab_target_point=map.local(target_point);
 }
 for(bool& value:carry){int bit=0;in>>bit;if(!in||(bit!=0&&bit!=1)){error="bad_carry";return false;}value=bit!=0;}
 in>>count;if(!in||count>64){error="bad_force_count";return false;}
 for(unsigned i=0;i<count;++i){SceneForce force;in>>force.arm>>force.node>>force.force.x>>force.force.y>>force.force.z;
  if(!in||!finite_vector(force.force)){error="bad_force";return false;}force.force=map.force(force.force);forces.push_back(force);}
 in>>count;if(!in||count>192){error="bad_contact_count";return false;}
 for(unsigned i=0;i<count;++i){SceneContact contact;in>>contact.arm>>contact.node>>contact.point.x>>contact.point.y>>contact.point.z
    >>contact.normal.x>>contact.normal.y>>contact.normal.z>>contact.collider;
  if(!in||!finite_vector(contact.point)||!finite_vector(contact.normal)){error="bad_contact";return false;}
  contact.point=map.local(contact.point);contacts.push_back(contact);
 }
 std::string extra;if(in>>extra){error="extra_data";return false;}return true;
}
}
int main(){
 std::cout<<std::setprecision(9);WorldConfig config;config.animals=1;config.rigid_count=0;
 PhysicsWorld world(config);MapTransform map;bool ready=false,uploading=false;
 size_t expected=0;std::vector<Vec3> vertices;unsigned long long last=0;std::string line;
 while(std::getline(std::cin,line)){
  std::istringstream in(line);int version=0;unsigned long long id=0;std::string op,error;in>>version>>id>>op;bool ack=false;
  if(line.size()>131072)error="request_too_large";else if(!in||version!=1)error="bad_header";else if(id<=last)error="stale_id";
  else{last=id;
   if(op=="quit"){std::cout<<"{\"version\":1,\"id\":"<<id<<",\"ok\":true}"<<std::endl;break;}
   if(op=="game_reset5"){
    MapTransform next;unsigned width=0;double x=0,z=0,cell=0;in>>next.origin.x>>next.origin.y>>next.origin.z>>next.scale>>width>>x>>z>>cell;
    if(!in||!finite_vector(next.origin)||!std::isfinite(next.scale)||next.scale<.5||next.scale>3
      ||width<2||width>65||!std::isfinite(x)||!std::isfinite(z)||!std::isfinite(cell)||cell<=0)error="bad_config";
    std::vector<double> heights;
    if(error.empty()){heights.resize(size_t(width)*width);for(double& h:heights){in>>h;if(!in||!std::isfinite(h)||std::abs(h)>1000){error="bad_terrain";break;}h=(h-next.origin.y)/next.scale;}}
    std::string extra;if(error.empty()&&(in>>extra))error="extra_data";
    if(error.empty()){
     WorldConfig fresh;fresh.animals=1;fresh.rigid_count=0;fresh.auto_suction=true;fresh.grounded_rest=true;
     fresh.tissue_stiffness_ratio=.2;fresh.spawn_height=.27;fresh.upright_strength=.08;PhysicsWorld candidate(fresh);
     if(!candidate.terrain(width,(x-next.origin.x)/next.scale,(z-next.origin.z)/next.scale,cell/next.scale,heights))error="bad_terrain";
     else{world=std::move(candidate);config=fresh;map=next;world.set_suction_enabled(false);ready=false;uploading=false;vertices.clear();}
    }
   }else if(op=="mesh_begin"){
    size_t count=0;in>>count;std::string extra;if(!in||count>1000000||count%3||(in>>extra))error="bad_mesh_count";
    else{expected=count;vertices.clear();vertices.reserve(count);uploading=true;ready=false;ack=true;}
   }else if(op=="mesh_chunk"){
    size_t offset=0,count=0;in>>offset>>count;std::vector<Vec3> chunk;
    if(!in||!uploading||offset!=vertices.size()||count>600||count>expected-vertices.size())error="bad_mesh_chunk";
    if(error.empty()){chunk.resize(count);for(auto& p:chunk){in>>p.x>>p.y>>p.z;if(!in||!finite_vector(p)){error="bad_mesh_vertex";break;}p=map.local(p);}}
    std::string extra;if(error.empty()&&(in>>extra))error="extra_data";
    if(error.empty()){vertices.insert(vertices.end(),chunk.begin(),chunk.end());ack=true;}
   }else if(op=="mesh_commit"){
    std::string extra;if(!uploading||vertices.size()!=expected||(in>>extra))error="incomplete_mesh";
    else if(!world.static_geometry(vertices))error="bad_mesh";else{ready=true;uploading=false;vertices.clear();}
   }else if(op=="step6"){
    if(!ready)error="geometry_not_ready";
    std::vector<MuscleCommand> commands;DragCommand drag;bool suction=false;std::array<bool,8> carry{};
    std::vector<SceneForce> forces;std::vector<SceneContact> contacts;
    if(error.empty())read_step(in,map,commands,drag,suction,carry,forces,contacts,error);
    if(error.empty()&&!world.scene_inputs(forces,contacts))error="bad_scene_inputs";
    if(error.empty()&&!world.drag(drag))error="drag_rejected";
    if(error.empty()){
     world.release_all_suckers(false);world.set_suction_enabled(suction);world.external_grips(carry);
     for(const auto& command:commands)if(!world.command(command)){error="command_rejected";break;}
     if(error.empty()&&!world.step())error="step_failed";
    }
   }else if(op!="snapshot")error="bad_operation";
  }
  std::cout<<"{\"version\":1,\"id\":"<<id<<",\"ok\":"<<flag(error.empty());
  if(!error.empty())std::cout<<",\"error\":\""<<error<<'"';
  else if(ack)std::cout<<",\"mesh_upload\":true,\"offset\":"<<vertices.size();
  else{std::cout<<",\"snapshot\":{\"frame\":";frame_json(world,map,ready);std::cout<<'}';}
  std::cout<<'}'<<std::endl;
 }
}
