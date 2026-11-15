// PhysicsWorld::Impl scene adapters. No registered map/scene input leaves the
// upstream flat-floor movement and material paths unchanged.
bool mapped_floor()const{return static_mesh.triangle_count()!=0||terrain_width>=2;}
int scene_particle(int arm,int node)const{
 if(animals.empty()||arm < -1||arm>7||node<0)return -1;
 const auto& animal=animals[0];
 if(arm<0){
  if(unsigned(node)<animal.body.size())return animal.body[node];
  const auto shell=unsigned(node)-unsigned(animal.body.size());
  return shell<animal.shell.size()?animal.shell[shell]:-1;
 }
 return unsigned(node)<animal.arms[arm].p.size()?animal.arms[arm].p[node]:-1;
}
bool external_floor_grip(const Arm& arm)const{
 return p[arm.p[0]].animal==0&&external_grip_mask[arm.arm_index];
}
geometry::SurfaceHit heightfield_surface(Vec3 at)const{
 geometry::SurfaceHit hit;
 if(terrain_width<2)return hit;
 const double x=std::clamp((at.x-terrain_x)/terrain_cell,0.,double(terrain_width-1));
 const double z=std::clamp((at.z-terrain_z)/terrain_cell,0.,double(terrain_width-1));
 const unsigned ix=std::min(unsigned(x),terrain_width-2),iz=std::min(unsigned(z),terrain_width-2);
 const double u=x-ix,v=z-iz;
 const double a=heights[iz*terrain_width+ix],b=heights[iz*terrain_width+ix+1];
 const double c=heights[(iz+1)*terrain_width+ix],d=heights[(iz+1)*terrain_width+ix+1];
 const double y=(1-v)*((1-u)*a+u*b)+v*((1-u)*c+u*d);
 const double dx=((1-v)*(b-a)+v*(d-c))/terrain_cell;
 const double dz=((1-u)*(c-a)+u*(d-b))/terrain_cell;
 hit.hit=true;hit.point={at.x,y,at.z};hit.normal=unit({-dx,1,-dz});
 hit.distance=dot(at-hit.point,hit.normal);return hit;
}
geometry::SurfaceHit mapped_support(Vec3 at)const{
 if(!static_mesh.triangle_count())return heightfield_surface(at);
 auto hit=static_mesh.ray(at+Vec3{0,.25,0},{0,-1,0},4.25);
 if(hit.hit)hit.distance=dot(at-hit.point,hit.normal);
 return hit;
}
Vec3 support_down(Vec3 at)const{
 if(mapped_floor()&&cfg.floor){const auto hit=mapped_support(at);if(hit.hit)return hit.normal*(-1);}
 return {0,-1,0};
}
Vec3 sucker_direction(const Arm& arm,unsigned node)const{
 const unsigned next=std::min(unsigned(cfg.segments),node+1),previous=node?node-1:0;
 const Vec3 tangent=unit(p[arm.p[next]].x-p[arm.p[previous]].x);
 const Vec3 down=support_down(p[arm.p[node]].x);
 Vec3 face=down-tangent*dot(down,tangent);
 return norm(face)<.25?Vec3{}:unit(face);
}
bool mapped_grounded(const P& site,double allowance)const{
 const auto ground=mapped_support(site.x);
 return ground.hit&&ground.distance<=floor_surface_radius(site)+allowance;
}
void mapped_project_floor(){
 const double h=cfg.fixed_dt/cfg.substeps;
 for(auto& site:p){
  const double support=floor_surface_radius(site);
  geometry::SurfaceHit surface;
  if(static_mesh.triangle_count()){
   const Vec3 move=site.x-site.old;const double travel=norm(move);
   surface=static_mesh.closest(site.x,support+travel+1e-7);
   if(surface.hit){
    // Preserve the side occupied at substep start if another constraint
    // pushed a point through a triangle during the solver sweep.
    if(dot(site.old-surface.point,surface.normal)<0)surface.normal=surface.normal*(-1);
    surface.distance=dot(site.x-surface.point,surface.normal);
   }
   if(travel>support*.4){
    auto crossed=static_mesh.ray(site.old,move,travel);
    if(crossed.hit){crossed.distance=dot(site.x-crossed.point,crossed.normal);surface=crossed;}
   }
  }else surface=heightfield_surface(site.x);
  if(!surface.hit||surface.distance>support+1e-7)continue;
  const Vec3 normal=surface.normal;
  const double depth=std::max(0.,support-surface.distance);
  if(depth>0){
   site.compression=std::max(site.compression,depth);diag.max_penetration=std::max(diag.max_penetration,depth);
   ++diag.contact_count;site.x=site.x+normal*depth;
  }
  Vec3 travel=site.x-site.old;travel=travel-normal*dot(travel,normal);
  const double displacement=norm(travel);if(displacement<1e-12)continue;
  const double normal_budget=std::max(depth,std::max(0.,-dot(cfg.gravity,normal))*h*h);
  double reduction=0;
  if(cfg.grounded_rest){
   reduction=displacement<=cfg.floor_static_friction*normal_budget?displacement:
    std::min(displacement,cfg.floor_kinetic_friction*normal_budget);
  }else reduction=std::min(displacement,cfg.friction*depth);
  site.x=site.x-travel*(reduction/displacement);
 }
}
void mapped_torso_above_arms(double h){
 for(auto& animal:animals){
  auto& center=p[animal.body[0]];const auto ground=mapped_support(center.x);if(!ground.hit)continue;
  const Vec3 normal=ground.normal;std::vector<int> grounded;double support_y=0;
  for(auto& arm:animal.arms)for(unsigned j=0;j<=std::min(4u,cfg.segments);++j){
   const int id=arm.p[j];if(mapped_grounded(p[id],.025)){grounded.push_back(id);support_y+=dot(p[id].x,normal);}
  }
  if(grounded.size()<2)continue;support_y/=grounded.size();
  const double force=std::clamp((support_y+.17-dot(center.x,normal))*26.,0.,2.8),impulse=force*h*h;
  center.x=center.x+normal*(impulse*center.inv);
  for(const int id:grounded)p[id].x=p[id].x-normal*(impulse*p[id].inv/grounded.size());
 }
}
void scene_constraints(double h){
 for(std::size_t i=0;i<scene_contacts.size();++i){
  const auto& contact=scene_contacts[i];auto& site=p[scene_particle(contact.arm,contact.node)];
  const double depth=site.r-dot(site.x-contact.point,contact.normal);
  if(depth<=0)continue;
  const Vec3 correction=contact.normal*std::min(depth,.025);
  site.x=site.x+correction;
  reactions[i].impulse=reactions[i].impulse-correction/(site.inv*h);
  ++diag.contact_count;
 }
}
