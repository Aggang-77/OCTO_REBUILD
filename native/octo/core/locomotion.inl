// PhysicsWorld::Impl methods. All control/recovery corrections are bounded
// internal muscle forces; contact corrections belong to the C++ solver.
double arm_length()const{return .9*cfg.size_scale;}
double mass_scale()const{return cfg.size_scale*cfg.size_scale*cfg.size_scale;}
bool extend_input(const Arm& ar)const{
 return ar.target.explicit_control?ar.target.extend:
        (ar.target.attach||(ar.target.activation>.5&&ar.target.extension>=1.0));
}
bool stroke_input(const Arm& ar)const{
 return ar.target.explicit_control?ar.target.stroke:
        (ar.target.activation>.5&&std::abs(ar.target.sweep)>.2);
}
bool carrying(const Arm& ar)const{
 if(release_held)return false;
 if(ar.target.carry||ar.attached>=0)return true;
 for(const auto& s:ar.suckers)if(s.attached>=0)return true;
 return false;
}
bool quiet(const Arm& ar)const{
 if(extend_input(ar)||stroke_input(ar)||carrying(ar))return false;
 for(const auto& s:ar.suckers)if(s.attached==-2)return false;
 return true;
}
double pose_compliance(const Arm& ar)const{return cfg.locomotion_assist&&quiet(ar)?80.0:1.0;}
double contact_friction(const P& site)const{
 if(site.animal<0)return cfg.friction;
 if(site.arm<0)return cfg.body_friction;
 const auto& ar=animals[site.animal].arms[site.arm];
 return extend_input(ar)&&!carrying(ar)?cfg.friction:cfg.friction*cfg.idle_friction_ratio;
}
Vec3 body_spin(const Animal& animal)const{
 Vec3 center{},velocity{},torque{};const double count=double(animal.body.size());
 for(int id:animal.body){center=center+p[id].x/count;velocity=velocity+p[id].v/count;}
 double a=0,b=0,c=0,d=0,e=0,f=0;
 for(int id:animal.body){const Vec3 r=p[id].x-center;
  torque=torque+cross(r,p[id].v-velocity);
  a+=r.y*r.y+r.z*r.z;b-=r.x*r.y;c-=r.x*r.z;d+=r.x*r.x+r.z*r.z;e-=r.y*r.z;f+=r.x*r.x+r.y*r.y;
 }
 const double det=a*(d*f-e*e)-b*(b*f-c*e)+c*(b*e-c*d);
 if(std::abs(det)<1e-12)return {};
 return {((d*f-e*e)*torque.x+(c*e-b*f)*torque.y+(b*e-c*d)*torque.z)/det,
         ((c*e-b*f)*torque.x+(a*f-c*c)*torque.y+(b*c-a*e)*torque.z)/det,
         ((b*e-c*d)*torque.x+(b*c-a*e)*torque.y+(a*d-b*b)*torque.z)/det};
}
void arm_force(Animal& animal,P& site,Vec3 force,double h){
 site.x=site.x+force*(site.inv*h*h);
 Vec3 center{};for(int id:animal.body)center=center+p[id].x/double(animal.body.size());
 const Vec3 torque=cross(site.x-center,force)*(-1);
 double a=0,b=0,c=0,d=0,e=0,f=0;
 for(int id:animal.body){const Vec3 r=p[id].x-center;a+=r.y*r.y+r.z*r.z;b-=r.x*r.y;c-=r.x*r.z;d+=r.x*r.x+r.z*r.z;e-=r.y*r.z;f+=r.x*r.x+r.y*r.y;}
 const double determinant=a*(d*f-e*e)-b*(b*f-c*e)+c*(b*e-c*d);
 Vec3 rotation{};
 if(std::abs(determinant)>1e-12)rotation={
  ((d*f-e*e)*torque.x+(c*e-b*f)*torque.y+(b*e-c*d)*torque.z)/determinant,
  ((c*e-b*f)*torque.x+(a*f-c*c)*torque.y+(b*c-a*e)*torque.z)/determinant,
  ((b*e-c*d)*torque.x+(b*c-a*e)*torque.y+(a*d-b*b)*torque.z)/determinant};
 for(int id:animal.body){
  const Vec3 reaction=force*(-1.0/animal.body.size())+cross(rotation,p[id].x-center);
  p[id].x=p[id].x+reaction*(p[id].inv*h*h);
 }
}
void body_torque(Animal& animal,Vec3 torque,double h){
 Vec3 center{};for(int id:animal.body)center=center+p[id].x/double(animal.body.size());
 double a=0,b=0,c=0,d=0,e=0,f=0;
 for(int id:animal.body){const Vec3 r=p[id].x-center;a+=r.y*r.y+r.z*r.z;b-=r.x*r.y;c-=r.x*r.z;d+=r.x*r.x+r.z*r.z;e-=r.y*r.z;f+=r.x*r.x+r.y*r.y;}
 const double det=a*(d*f-e*e)-b*(b*f-c*e)+c*(b*e-c*d);
 if(std::abs(det)<1e-12)return;
 const Vec3 rotation{
  ((d*f-e*e)*torque.x+(c*e-b*f)*torque.y+(b*e-c*d)*torque.z)/det,
  ((c*e-b*f)*torque.x+(a*f-c*c)*torque.y+(b*c-a*e)*torque.z)/det,
  ((b*e-c*d)*torque.x+(b*c-a*e)*torque.y+(a*d-b*b)*torque.z)/det};
 for(int id:animal.body)p[id].x=p[id].x+cross(rotation,p[id].x-center)*(p[id].inv*h*h);
}
void align_contact_material(Animal& animal,Arm& ar,unsigned node,Vec3 normal,double h){
 namespace rm=rod_math;
 const unsigned index=std::min(unsigned(ar.directors.size()-1),node?node-1:0u);
 auto& director=ar.directors[index];
 const Vec3 axis=rm::rotate(director.q,{0,0,1});
 Vec3 desired=normal-axis*dot(normal,axis);
 if(norm(desired)<.12)return;
 desired=unit(desired);
 const Vec3 material_up=sucker_face(ar,node)*(-1);
 double angle=std::atan2(dot(axis,cross(material_up,desired)),dot(material_up,desired));
 if(std::abs(angle)>3.13)angle=(ar.arm_index<4?1:-1)*std::abs(angle);
 const double scale=mass_scale()*cfg.size_scale*cfg.size_scale;
 const double stiffness=.02*scale,damping=2*std::sqrt(stiffness/director.inv_inertia);
 const double speed=dot(director.omega,axis)+ar.roll[index].omega;
 const double torque=std::clamp((angle*stiffness-speed*damping)/
   (1+damping*director.inv_inertia*h+stiffness*director.inv_inertia*h*h),-.008*scale,.008*scale);
 director.q=rm::integrate(director.q,axis*(torque*director.inv_inertia*h*h),1);
 body_torque(animal,axis*(-torque),h);
}
void terrain_material_motors(double h){
 if(!cfg.locomotion_assist||!cfg.auto_suction||!cfg.floor||release_held)return;
 for(auto& animal:animals)for(auto& ar:animal.arms){
  if(!extend_input(ar)||carrying(ar))continue;
  for(const auto& sucker:ar.suckers){
   const auto& site=p[ar.p[sucker.node]];
   if(!site.static_contact)continue;
   geometry::SurfaceHit surface;
   if(static_mesh.triangle_count())surface=static_mesh.closest(site.x,site.r+.006*cfg.size_scale);
   else{surface.hit=true;surface.point={site.x.x,floor_height(site.x),site.x.z};surface.normal=floor_normal(site.x);surface.distance=dot(site.x-surface.point,surface.normal);}
   if(!surface.hit||surface.distance>site.r+.006*cfg.size_scale||surface.normal.y>.9999)continue;
   // A terrain-contact torque turns the actual material sucker face. Tangents
   // and positions remain free; attachment still checks the real face/contact.
   align_contact_material(animal,ar,sucker.node,surface.normal,h);
  }
 }
}
geometry::SurfaceHit support_surface(Vec3 at,double above=.25,double below=4.0)const{
 geometry::SurfaceHit hit;
 if(!cfg.floor)return hit;
 if(static_mesh.triangle_count())return static_mesh.ray(at+Vec3{0,above,0},{0,-1,0},above+below);
 hit.hit=true;hit.point={at.x,floor_height(at),at.z};hit.normal=floor_normal(at);
 hit.distance=at.y+above-hit.point.y;
 if(hit.distance<0||hit.distance>above+below)hit.hit=false;
 return hit;
}
Vec3 support_up(Vec3 at)const{
 const auto hit=support_surface(at,.45*cfg.size_scale,2.5*cfg.size_scale);
 return hit.hit&&hit.normal.y>.2?hit.normal:Vec3{0,1,0};
}
Vec3 sucker_face(const Arm& ar,unsigned node)const{
 const auto j=std::min(unsigned(ar.directors.size()-1),node?node-1:0u);
 return unit(rod_math::rotate(roll_frame(ar.directors[j].q,ar.roll[j].angle),{0,-1,0}));
}
double footprint_coverage(Vec3 contact,Vec3 normal,double radius)const{
 if(!static_mesh.triangle_count())return 1.0;
 Vec3 tangent=unit(cross(normal,std::abs(normal.y)<.9?Vec3{0,1,0}:Vec3{1,0,0}));
 const Vec3 side=cross(normal,tangent);
 const double tolerance=std::max(.002*cfg.size_scale,radius*.12);
 unsigned supported=0;
 for(unsigned i=0;i<8;++i){
  const double angle=2*layout::pi*i/8.;
  const Vec3 sample=contact+(tangent*std::cos(angle)+side*std::sin(angle))*(radius*.72);
  const auto patch=static_mesh.ray(sample+normal*tolerance,normal*(-1),tolerance*2);
  if(patch.hit&&dot(patch.normal,normal)>.75)++supported;
 }
 return double(supported)/8.;
}
void update_locomotion(){
 for(auto& animal:animals)for(auto& ar:animal.arms){
  const bool extending=extend_input(ar),cargo=carrying(ar);
  if(ar.phase==Carry&&!cargo)ar.rearm_required=true;
  if(extending&&!ar.previous_extend&&!release_held){
   ++ar.cycle;ar.rearm_required=false;ar.ever_supported=false;ar.peel_clock=0;
   for(auto& s:ar.suckers){if(s.attached==-2)s.attached=-1;s.dwell=0;}
  }
  if(!extending&&ar.previous_extend)ar.peel_clock=0;
  bool floor_grip=false;
  for(auto& s:ar.suckers){
   if(release_held){s.attached=-1;s.dwell=0;s.cooldown=.18;}
   if(cargo&&s.attached==-2){s.attached=-1;s.dwell=0;}
   floor_grip=floor_grip||s.attached==-2;
  }
  if(release_held)ar.rearm_required=true;
  if(extending&&ar.ever_supported&&!floor_grip&&!cargo)ar.rearm_required=true;
  ar.phase=cargo?Carry:(extending?(floor_grip?Support:Prepare):
      (floor_grip?Releasing:(stroke_input(ar)?AirStroke:Recover)));
  ar.previous_extend=extending;
 }
}
void static_contacts(){
 if(!cfg.floor)return;
 const bool mesh=static_mesh.triangle_count()!=0;
 for(auto& site:p){
  site.static_contact=false;
  geometry::SurfaceHit surface;
  if(mesh){
   surface=static_mesh.closest(site.x,site.r+.006*cfg.size_scale);
   const Vec3 move=site.x-site.old;const double travel=norm(move);
   if(travel>site.r*.4){
    const auto crossed=static_mesh.ray(site.old,move,travel);
    if(crossed.hit){surface=crossed;surface.distance=dot(site.x-crossed.point,crossed.normal);}
   }
  }else{
   surface.hit=true;surface.point={site.x.x,floor_height(site.x),site.x.z};surface.normal=floor_normal(site.x);
   surface.distance=dot(site.x-surface.point,surface.normal);
  }
  if(!surface.hit||surface.distance>site.r+.004*cfg.size_scale)continue;
  site.static_contact=true;site.surface_normal=surface.normal;
  const double depth=site.r-surface.distance;if(depth<=0)continue;
  site.compression=std::max(site.compression,depth);
  diag.max_penetration=std::max(diag.max_penetration,depth);++diag.contact_count;
  site.x=site.x+surface.normal*depth;
  Vec3 tangent=site.x-site.old;tangent=tangent-surface.normal*dot(tangent,surface.normal);
  const double length=norm(tangent);
  if(length>0)site.x=site.x-tangent*(std::min(length,contact_friction(site)*depth)/length);
 }
 if(!mesh)return;
 // Check the entire tapered segment, not only its endpoints. Thin uneven
 // terrain and stair edges cannot slip between discretization sites.
 for(auto& animal:animals)for(auto& ar:animal.arms)for(unsigned j=0;j<cfg.segments;++j){
  auto& a=p[ar.p[j]];auto& b=p[ar.p[j+1]];
  const auto surface=static_mesh.closest_segment(a.x,b.x,std::max(a.r,b.r));
  if(!surface.hit)continue;
  const double t=surface.segment_t,radius=a.r*(1-t)+b.r*t;
  const double depth=radius-surface.distance;if(depth<=0)continue;
  Vec3 normal=surface.normal;
  if(surface.distance<1e-8&&dot(a.old*(1-t)+b.old*t-surface.point,normal)<0)normal=normal*(-1);
  const double denominator=(1-t)*(1-t)*a.inv+t*t*b.inv;
  if(denominator<=0)continue;
  const Vec3 correction=normal*(depth/denominator);
  a.x=a.x+correction*((1-t)*a.inv);b.x=b.x+correction*(t*b.inv);
  a.static_contact=b.static_contact=true;a.surface_normal=b.surface_normal=normal;
  a.compression=std::max(a.compression,depth*(1-t));b.compression=std::max(b.compression,depth*t);
  ++diag.contact_count;
 }
}
void record_sucker_frame(Arm& ar,Sucker& s){
 const auto& site=p[ar.p[s.node]];
 const Vec3 axial=p[ar.p[std::min(unsigned(cfg.segments),s.node+1)]].x-p[ar.p[s.node-1]].x;
 Vec3 normal=s.contact_normal;double radius=0;
 if(s.attached>=0){normal=unit(site.x-p[s.attached].x);radius=p[s.attached].r+site.r;}
 Vec3 tangent=axial-normal*dot(axial,normal);
 if(s.attached==-2){
  const auto& animal=animals[site.animal];
  Vec3 ahead=p[animal.body[5]].x-p[animal.body[6]].x;ahead=unit(ahead-normal*dot(ahead,normal));
  const Vec3 right=unit(cross(normal,ahead));
  const Vec3 home=right*std::sin(layout::angle(ar.arm_index))+ahead*std::cos(layout::angle(ar.arm_index));
  if(norm(tangent)<norm(axial)*.25||dot(tangent,home)<0)tangent=home;
 }
 if(norm(tangent)<1e-6)tangent=cross(normal,std::abs(normal.y)<.9?Vec3{0,1,0}:Vec3{1,0,0});
 s.contact_normal=unit(normal);s.contact_tangent=unit(tangent);
 s.contact_binormal=unit(cross(normal,tangent));s.wrap_radius=radius;
}
void recover_arms(double h){
 if(!cfg.locomotion_assist)return;
 for(auto& animal:animals){
  const Vec3 center=p[animal.body[0]].x,body_v=p[animal.body[0]].v,spin=body_spin(animal);
  // Proximal ordering belongs to the animal's material frame. Projecting its
  // heading onto the floor flips the home direction as a pitched torso passes
  // vertical, precisely when recovery must remain continuous.
  const Vec3 up=unit(p[animal.body[3]].x-p[animal.body[4]].x);
  Vec3 forward=p[animal.body[5]].x-p[animal.body[6]].x;
  forward=unit(forward-up*dot(forward,up));
  const Vec3 right=unit(cross(up,forward));
  Vec3 travel=body_v-up*dot(body_v,up);const double speed=norm(travel);
  travel=speed>.08?travel/speed:Vec3{};
  for(auto& ar:animal.arms){
   const bool empty=quiet(ar);
   const Vec3 home=right*std::sin(layout::angle(ar.arm_index))+forward*std::cos(layout::angle(ar.arm_index));
   const Vec3 root=p[ar.p[0]].x;
   for(unsigned j=1;j<=cfg.segments;++j){
    auto& site=p[ar.p[j]];const double u=double(j)/cfg.segments;
    if(j<=3){
     Vec3 span=site.x-root;
     const double length=arm_length()*ar.active.extension*u;
     Vec3 goal=root+home*(length*.85)+up*std::clamp(dot(span,up),-length*.45,length*.35);
     const Vec3 goal_velocity=body_v+cross(spin,goal-center);
     Vec3 force=(goal-site.x)*(180.0*mass_scale())+(goal_velocity-site.v)*(3.0*mass_scale());
     const double cap=(empty?1.2:8.0)*mass_scale();
     if(norm(force)>cap)force=force*(cap/norm(force));
     arm_force(animal,site,force,h);
    }
    // Root and proximal sections keep their ordering. Distal gripping sections
    // retain their freedom; a carry only receives the weak proximal boundary.
    if(j<=cfg.segments*2/3&&(!carrying(ar)||j<=3)){
     Vec3 radial=site.x-root;radial=radial-up*dot(radial,up);
     const double radius=norm(radial);
     if(radius>.015*cfg.size_scale){
      const double angle=std::atan2(dot(radial,right),dot(radial,forward));
      double error=std::remainder(angle-layout::angle(ar.arm_index),2*layout::pi);
      const double limit=(j<=3?18.0+4.0*j:48.0)*layout::pi/180.;
      if(std::abs(error)>limit){
       const double aim=layout::angle(ar.arm_index)+std::copysign(limit,error);
       Vec3 force=((right*std::sin(aim)+forward*std::cos(aim))*radius-radial)*(2.0*mass_scale());
       const double cap=(j<=3?(empty?.40:1.20):(empty?.10:.35))*mass_scale();
       if(norm(force)>cap)force=force*(cap/norm(force));
       arm_force(animal,site,force,h);
      }
     }
    }
    if(!empty)continue;
    // A short loose U beside the torso, lifted off the floor. Its target travels
    // with the body and trails motion rather than anchoring to an old location.
    Vec3 goal=root+home*(arm_length()*(.18*std::sin(layout::pi*u)+.08*u*u))
                  +up*(arm_length()*.18*(1-std::cos(layout::pi*u))*.5)
                  -travel*(std::min(arm_length()*.10,speed*.12)*u*u);
    for(double weight:{0.0,.5,1.0}){
     const Vec3 sample=site.x*(1-weight)+goal*weight+body_v*.10;
     const auto floor=support_surface(sample,.6*cfg.size_scale,2.0*cfg.size_scale);
     if(floor.hit&&floor.normal.y>.15){
      double clearance=(site.static_contact?.16:.09)*cfg.size_scale;
      goal.y=std::max(goal.y,floor.point.y+site.r+clearance*std::sin(layout::pi*u*.5));
     }
    }
    Vec3 force=(goal-site.x)*(1.2*mass_scale())+(body_v+cross(spin,goal-center)-site.v)*(.025*mass_scale());
    const double cap=.055*mass_scale();if(norm(force)>cap)force=force*(cap/norm(force));
    arm_force(animal,site,force,h);
   }
  }
 }
}
void sweep_motors(double h){
 for(auto& animal:animals){
  Vec3 forward=unit(p[animal.body[5]].x-p[animal.body[6]].x);
  for(auto& ar:animal.arms){
   if(quiet(ar)||ar.phase==Releasing||ar.active.activation<.05||carrying(ar))continue;
   if(!ar.target.explicit_control&&std::abs(ar.active.sweep)<1e-5)continue;
   Vec3 up=support_up(p[ar.p[cfg.segments/2]].x);
   Vec3 ahead=unit(forward-up*dot(forward,up)),right=unit(cross(up,ahead));
   const double angle=layout::angle(ar.arm_index);
   Vec3 home=right*std::sin(angle)+ahead*std::cos(angle);
   double turn=(ar.arm_index<4?1.0:-1.0)*cfg.sweep_limit_degrees*layout::pi/180.*ar.active.sweep;
   // Paired front/rear arms keep a small central lane. A ±27° command
   // must not make the two mirror arms aim through one another.
   if(ar.arm_index==0)turn=std::max(turn,5*layout::pi/180.-angle);
   if(ar.arm_index==7)turn=std::min(turn,-5*layout::pi/180.-angle);
   if(ar.arm_index==3)turn=std::min(turn,175*layout::pi/180.-angle);
   if(ar.arm_index==4)turn=std::max(turn,-175*layout::pi/180.-angle);
   const Vec3 goal=home*std::cos(turn)+cross(up,home)*std::sin(turn);
   const Vec3 root=p[ar.p[0]].x;
   for(unsigned j=std::max(2u,cfg.segments/3);j<=cfg.segments;++j){
    auto& site=p[ar.p[j]];const double u=double(j)/cfg.segments;
    Vec3 target=root+goal*(arm_length()*u*ar.active.extension);
    // Horizontal placement and sweep are independent of the contact normal.
    // A planted arm must not be pulled off its support by a torso-height target.
    Vec3 error=target-site.x;error=error-up*dot(error,up);
    Vec3 relative=site.v-p[animal.body[0]].v;relative=relative-up*dot(relative,up);
    Vec3 force=error*(3.0*cfg.arm_motor_strength*mass_scale())-relative*(.7*mass_scale());
    const double cap=.65*cfg.arm_motor_strength*mass_scale()*ar.active.activation;
    if(norm(force)>cap)force=force*(cap/norm(force));
    arm_force(animal,site,force,h);
   }
  }
 }
}
void follow_surface(double h){
 if(!cfg.auto_suction||release_held)return;
 for(auto& animal:animals)for(auto& ar:animal.arms){
  if(!extend_input(ar))continue;
  const Sucker* last=nullptr;
  for(const auto& s:ar.suckers)if(s.attached!=-1&&(!last||s.node>last->node))last=&s;
  if(!last)continue;
  for(auto& s:ar.suckers){
   if(s.attached!=-1||s.cooldown>0||s.node+cfg.segments/3<last->node)continue;
   auto& site=p[ar.p[s.node]];
   const double along=(arm_length()/cfg.segments)*(int(s.node)-int(last->node));
   Vec3 goal=last->anchor+last->contact_tangent*along;
   if(last->attached>=0){
    const auto& object=p[last->attached];const double r=std::max(.025*cfg.size_scale,object.r+site.r);
    const double a=std::clamp(along/r,-1.5,1.5);
    goal=object.x+unit(last->contact_normal*std::cos(a)+last->contact_tangent*std::sin(a))*r;
   }else{
    const auto ground=support_surface(goal,.6*cfg.size_scale,2*cfg.size_scale);
    if(!ground.hit)continue;
    goal=ground.point+ground.normal*site.r;
   }
   Vec3 force=(goal-site.x)*(.8*mass_scale());const double cap=.10*mass_scale();
   if(norm(force)>cap)force=force*(cap/norm(force));arm_force(animal,site,force,h);
  }
 }
}
void seek_floor_contact(double h){
 if(!cfg.auto_suction||!cfg.floor||!cfg.reach_ground_on_extend||release_held)return;
 for(auto& animal:animals)for(auto& ar:animal.arms){
  if(!extend_input(ar)||carrying(ar)||ar.rearm_required)continue;
  for(unsigned j=std::max(2u,cfg.segments/2);j<=cfg.segments;++j){
   auto& site=p[ar.p[j]];
   const auto ground=support_surface(site.x,.15*cfg.size_scale,arm_length()*1.8);
   if(!ground.hit)continue;
   const double gap=dot(site.x-ground.point,ground.normal)-site.r;
   if(gap<.008*cfg.size_scale)continue;
   const double magnitude=std::min(.08*mass_scale(),.6*mass_scale()*gap)*double(j)/cfg.segments;
   arm_force(animal,site,ground.normal*(-magnitude),h);
  }
 }
}
void suction_constraints(double h){
 if(!cfg.auto_suction||release_held)return;
 for(auto& animal:animals)for(auto& ar:animal.arms)for(auto& s:ar.suckers){
  if(s.attached==-1)continue;auto& site=p[ar.p[s.node]];
  Vec3 target=s.attached==-2?s.anchor:p[s.attached].x;
  Vec3 delta=target-site.x;double length=norm(delta);if(length<1e-10)continue;
  const double error=length-(s.attached==-2?0:s.rest);
  const double weight=site.inv+(s.attached>=0?p[s.attached].inv:0);
  const double lambda=error/(weight+4e-7/(h*h));
  const double area=std::max(.002,site.r/.035);
  if(std::abs(lambda)/(h*h)>48*cfg.sucker_strength*area*area*s.coverage){
   s.attached=-1;s.dwell=0;s.cooldown=.18;continue;
  }
  const Vec3 move=delta*(lambda/length);site.x=site.x+move*site.inv;
  if(s.attached>=0)p[s.attached].x=p[s.attached].x-move*p[s.attached].inv;
 }
}
void update_suckers(double h){
 if(!cfg.auto_suction)return;
 for(auto& animal:animals)for(auto& ar:animal.arms){
  const bool extended=extend_input(ar),cargo=carrying(ar);
  if(!extended)ar.peel_clock+=h;
  bool any_static=false;
  for(auto& s:ar.suckers){
   s.cooldown=std::max(0.0,s.cooldown-h);
   if(release_held){s.attached=-1;s.dwell=0;s.cooldown=.18;continue;}
   if(s.attached==-2&&(!extended||cargo)){
    const double delay=double(&ar.suckers.back()-&s)*.035;
    if(cargo||ar.peel_clock>=delay){s.attached=-1;s.cooldown=.18;s.dwell=0;}
   }
   if(s.attached!=-1){record_sucker_frame(ar,s);any_static=any_static||s.attached==-2;continue;}
   // A timer expiring never rearms suction. Only a new extend cycle does.
   if(!extended||cargo||ar.rearm_required||s.last_cycle==ar.cycle||s.cooldown>0){s.dwell=0;continue;}
   auto& site=p[ar.p[s.node]];
   const Vec3 face=sucker_face(ar,s.node);
   int target=-1;Vec3 anchor{},normal{};double rest=0,coverage=0;
   if(cfg.collisions){
    double best=.004*cfg.size_scale;
    for(size_t j=0;j<p.size();++j){
     if(p[j].rigid<0)continue;const Vec3 toward=p[j].x-site.x;
     const double gap=norm(toward)-p[j].r-site.r;
     if(gap<best&&norm(p[j].v-site.v)<1.2*cfg.size_scale&&dot(face,unit(toward))>.45){
      target=int(j);normal=unit(toward)*(-1);rest=norm(toward);best=gap;coverage=.8;
     }
    }
   }
   if(target==-1&&cfg.floor){
    geometry::SurfaceHit surface;
    if(static_mesh.triangle_count())surface=static_mesh.closest(site.x,site.r+.004*cfg.size_scale);
    else{
     surface.hit=true;surface.point={site.x.x,floor_height(site.x),site.x.z};surface.normal=floor_normal(site.x);
     surface.distance=dot(site.x-surface.point,surface.normal);
    }
    if(surface.hit&&surface.distance<=site.r+.004*cfg.size_scale&&dot(face,surface.normal*(-1))>.45){
     coverage=footprint_coverage(surface.point,surface.normal,site.r);
     if(coverage>=.25){target=-2;normal=surface.normal;anchor=surface.point+normal*site.r;}
    }
   }
   if(target==-1||layout::pi*site.r*site.r*coverage<.000025){s.dwell=0;continue;}
   const Vec3 velocity=site.v-(target>=0?p[target].v:Vec3{});
   const double normal_speed=std::abs(dot(velocity,normal));
   const double tangent_speed=norm(velocity-normal*dot(velocity,normal));
   // A stable seal needs low separating speed. Sliding contact may begin a
   // finite-strength grip, which can still tear under excessive tangential load.
   if(normal_speed>.35*cfg.size_scale||tangent_speed>3.0*cfg.size_scale){s.dwell=0;continue;}
   s.dwell+=h;if(s.dwell<.025)continue;
   s.attached=target;s.anchor=anchor;s.rest=rest;s.coverage=coverage;s.contact_normal=normal;
   s.last_cycle=ar.cycle;s.dwell=0;record_sucker_frame(ar,s);
   any_static=any_static||target==-2;
  }
  if(any_static){ar.ever_supported=true;ar.phase=Support;}
  else if(extended&&ar.ever_supported&&!cargo){ar.rearm_required=true;ar.phase=Prepare;}
  else if(!extended&&!cargo)ar.phase=stroke_input(ar)?AirStroke:Recover;
  if(any_static&&!extended&&!cargo)ar.phase=Releasing;
 }
}
