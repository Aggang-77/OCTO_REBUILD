#include "octo/world.hpp"
#include "octo/collision.hpp"
#include "octo/arm_profile.hpp"
#include "octo/rod_math.hpp"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <limits>
#include <stdexcept>
#include <unordered_map>
namespace octo {
namespace {
Vec3 operator+(Vec3 a,Vec3 b){return {a.x+b.x,a.y+b.y,a.z+b.z};}
Vec3 operator-(Vec3 a,Vec3 b){return {a.x-b.x,a.y-b.y,a.z-b.z};}
Vec3 operator*(Vec3 a,double s){return {a.x*s,a.y*s,a.z*s};}
Vec3 operator/(Vec3 a,double s){return a*(1/s);}
double dot(Vec3 a,Vec3 b){return a.x*b.x+a.y*b.y+a.z*b.z;}
Vec3 cross(Vec3 a,Vec3 b){return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x};}
double norm(Vec3 a){return std::sqrt(dot(a,a));}
Vec3 unit(Vec3 a){double n=norm(a);return n>1e-12?a/n:Vec3{0,1,0};}
bool finite(Vec3 a){return std::isfinite(a.x)&&std::isfinite(a.y)&&std::isfinite(a.z);}
Quat frame(Vec3 z){z=unit(z);Vec3 x=unit(cross(std::abs(z.y)<.95?Vec3{0,1,0}:Vec3{1,0,0},z)),y=cross(z,x);double t=x.x+y.y+z.z;Quat q;if(t>0){double s=2*std::sqrt(1+t);q={(y.z-z.y)/s,(z.x-x.z)/s,(x.y-y.x)/s,s/4};}else{ // robust tangent-aligned reference frame; physical material roll is applied separately
 double d=std::clamp(z.z,-1.,1.);if(d<-.999999)q={0,1,0,0};else {Vec3 c=cross({0,0,1},z);double s=std::sqrt(2*(1+d));q={c.x/s,c.y/s,c.z/s,s/2};}}
return q;}
Quat roll_frame(Quat q,double angle){const double half=.5*angle,s=std::sin(half),c=std::cos(half);return {q.x*c+q.y*s,q.y*c-q.x*s,q.z*c+q.w*s,q.w*c-q.z*s};}
}
struct PhysicsWorld::Impl {
struct P{Vec3 x,old,v;double inv,r;int animal,arm,node,rigid;double compression=0;};
struct Bounds { Vec3 lo, hi; };
struct D{int a,b;double rest,compliance,lambda=0;};
struct T{std::array<int,4> p;double rest,lambda=0;};
struct Roll{double angle=0,old=0,omega=0,inv_inertia=0,lambda=0;};
struct Director{Quat q{},old{};Vec3 omega{},bend_lambda{},shear_lambda{};double inv_inertia=0;};
struct Sucker{unsigned node=0;int attached=-1;Vec3 anchor{};double rest=0,dwell=0,cooldown=0;};
struct Arm{std::vector<Sucker> suckers;double peel_clock=0;std::vector<int> p;std::vector<double> radius;std::vector<double> squash,squash_velocity;std::vector<Roll> roll;std::vector<Director> directors;std::vector<Vec3> bend_lambda,preferred_curvature;std::vector<double> length_targets;MuscleCommand target{},active{};unsigned arm_index=0,animal_index=0;int attached=-1;Vec3 anchor{};double attach_rest=0;};
struct Animal{std::vector<int> body;std::array<Arm,8> arms;};
WorldConfig cfg;bool release_held=false;std::vector<P> p;std::vector<D> d;std::vector<T> tetra;std::vector<Animal> animals;std::vector<std::vector<int>> rigids;std::vector<Bounds> contact_bounds;std::vector<int> contact_order;DragCommand drag;Diagnostics diag;std::uint64_t tick=0;double time=0;
int particle(Vec3 x,double mass,double radius,int animal=-1,int arm=-1,int node=-1,int rigid=-1){p.push_back({x,x,{},1/mass,radius,animal,arm,node,rigid});return int(p.size()-1);}
void edge(int a,int b,double compliance){d.push_back({a,b,norm(p[a].x-p[b].x),compliance});}
double volume(const T&t)const{auto a=p[t.p[0]].x;return dot(p[t.p[1]].x-a,cross(p[t.p[2]].x-a,p[t.p[3]].x-a))/6;}
explicit Impl(WorldConfig c):cfg(c){
if(c.animals>64||c.segments<2||c.segments>64||c.substeps<1||c.substeps>64||c.iterations<1||c.iterations>100||!finite(c.gravity)||!std::isfinite(c.fixed_dt)||c.fixed_dt<=0||c.fixed_dt>.1||!std::isfinite(c.damping)||c.damping<0||!std::isfinite(c.friction)||c.friction<0||!std::isfinite(c.spacing)||c.spacing<0||!std::isfinite(c.spawn_height)||!std::isfinite(c.idle_wriggle)||c.idle_wriggle<0||c.idle_wriggle>1||c.rigid_count>128)throw std::invalid_argument("Invalid WorldConfig");
for(unsigned n=0;n<c.animals;++n){Animal a;Vec3 center{(double(n)-double(c.animals-1)/2)*c.spacing,c.spawn_height,0};
for(Vec3 off:std::array<Vec3,7>{{{0,0,0},{.2,0,0},{-.2,0,0},{0,.24,0},{0,-.16,0},{0,0,.2},{0,0,-.2}}})a.body.push_back(particle(center+off,.12,.065,int(n)));
for(int i=0;i<7;++i)for(int j=i+1;j<7;++j)edge(a.body[i],a.body[j],2e-5);
for(int x:{1,2})for(int y:{3,4})for(int z:{5,6}){T t{{a.body[0],a.body[x],a.body[y],a.body[z]},0};t.rest=volume(t);tetra.push_back(t);}
for(int k=0;k<8;++k){auto& ar=a.arms[k];ar.arm_index=k;ar.animal_index=n;double angle=k*std::acos(-1.)/4;Vec3 radial{std::sin(angle),0,std::cos(angle)};for(unsigned j=0;j<=c.segments;++j){double u=double(j)/c.segments;double radius=arm_rest_radius(u,c.organic_profile);ar.radius.push_back(radius);ar.p.push_back(particle(center+radial*(.2+.9*u),.012*16.0/c.segments,radius,int(n),k,int(j)));if(j)edge(ar.p[j-1],ar.p[j],3e-7);}
ar.squash.assign(c.segments,1.0);ar.squash_velocity.assign(c.segments,0.0);
for(unsigned j=0;j<c.segments;++j){const double radius=ar.radius[j],mass=.012*16.0/c.segments;ar.roll.push_back({0,0,0,j?2.0/(mass*radius*radius):0,0});}
for(unsigned j=0;j<c.segments;++j){const double length=.9/c.segments,radius=ar.radius[j];const double inertia=(.012*16.0/c.segments)*(length*length+3*radius*radius)/12;Quat q=frame(radial);ar.directors.push_back({q,q,{},{},{},1/inertia});}
ar.bend_lambda.resize(c.segments-1);ar.preferred_curvature.resize(c.segments);ar.length_targets.assign(c.segments,.9/c.segments);
const unsigned spacing=std::max(3u,c.segments/6);for(unsigned j=spacing;j<=c.segments;j+=spacing)ar.suckers.push_back({j});if(ar.suckers.empty()||ar.suckers.back().node!=c.segments)ar.suckers.push_back({c.segments});
// Root attached to every cage vertex; all reactions act on dynamic torso.
for(int b:a.body)edge(ar.p[0],b,1e-7);
}
animals.push_back(a);}
for(unsigned k=0;k<c.rigid_count;++k){std::vector<int> ids;Vec3 center{double(k)*.65-.65,.32,1.35};for(int x:{-1,1})for(int y:{-1,1})for(int z:{-1,1})ids.push_back(particle(center+Vec3{x*.16,y*.16,z*.16},.125,.08,-1,-1,-1,int(k)));for(int i=0;i<8;++i)for(int j=i+1;j<8;++j)edge(ids[i],ids[j],1e-9);rigids.push_back(ids);}}
void distance(D& e,double h){auto&a=p[e.a];auto&b=p[e.b];Vec3 delta=b.x-a.x;double l=norm(delta);if(l<1e-12)return;double alpha=e.compliance/(h*h),dl=(-(l-e.rest)-alpha*e.lambda)/(a.inv+b.inv+alpha);e.lambda+=dl;Vec3 impulse=delta*(dl/l);a.x=a.x-impulse*a.inv;b.x=b.x+impulse*b.inv;}
void volumes(double h){for(auto&t:tetra){auto a=p[t.p[0]].x,b=p[t.p[1]].x,c=p[t.p[2]].x,e=p[t.p[3]].x;std::array<Vec3,4> g;g[1]=cross(c-a,e-a)/6;g[2]=cross(e-a,b-a)/6;g[3]=cross(b-a,c-a)/6;g[0]=(g[1]+g[2]+g[3])*(-1);double alpha=1e-10/(h*h),den=alpha;for(int i=0;i<4;++i)den+=p[t.p[i]].inv*dot(g[i],g[i]);double dl=(-(volume(t)-t.rest)-alpha*t.lambda)/den;t.lambda+=dl;for(int i=0;i<4;++i){auto&v=p[t.p[i]];v.x=v.x+g[i]*(v.inv*dl);}}}

void update_preferred_curvature(double phase_time){
const double tau=2.0*std::acos(-1.0);
for(auto&animal:animals){
 Vec3 up=unit(p[animal.body[3]].x-p[animal.body[4]].x);
 for(auto&ar:animal.arms){
  Vec3 radial=unit(p[ar.p[1]].x-p[ar.p[0]].x);
  Vec3 lateral=cross(radial,up);
  if(norm(lateral)<1e-8)lateral=cross(radial,{1,0,0});
  lateral=unit(lateral);
  double raw_length_sum=0;
  for(unsigned j=0;j<cfg.segments;++j){
   const double u=(j+0.5)/cfg.segments;
   const double phase=tau*(.65*phase_time-1.05*u)+.77*ar.arm_index+.43*ar.animal_index;
   const double idle=cfg.idle_wriggle*(1.0-ar.active.activation)*(.25+.75*u);
   ar.preferred_curvature[j]=up*(ar.active.activation*ar.active.curvature+7.0*idle*std::sin(phase))
       +lateral*(4.2*idle*std::cos(phase));
   // Distributed longitudinal muscle contraction with local hydrostat volume.
   const double strain=.34*idle*std::sin(phase+.5);
   ar.length_targets[j]=std::exp(strain);
   raw_length_sum+=ar.length_targets[j];
  }
  // Distribute local extension along the arm without changing the total target.
  const double scale=.9*ar.active.extension/raw_length_sum;
  for(double& segment_length:ar.length_targets)segment_length*=scale;
 }
}
}
void bending(double h){for(auto&a:animals){for(auto&ar:a.arms){for(unsigned j=1;j<cfg.segments;++j){const double length=.5*(ar.length_targets[j-1]+ar.length_targets[j]);auto&l=p[ar.p[j-1]];auto&m=p[ar.p[j]];auto&r=p[ar.p[j+1]];Vec3 target=ar.preferred_curvature[j]*(length*length);Vec3 error=l.x-m.x*2+r.x-target;double alpha=(5e-5*std::pow(16.0/cfg.segments,3.0)*(1-.85*ar.active.stiffness))/(h*h);auto&lambda=ar.bend_lambda[j-1];Vec3 dl=(error+lambda*alpha)*(-1/(l.inv+4*m.inv+r.inv+alpha));lambda=lambda+dl;l.x=l.x+dl*l.inv;m.x=m.x-dl*(2*m.inv);r.x=r.x+dl*r.inv;}}}}
void torsion(double h){for(auto&a:animals)for(auto&ar:a.arms){const double desired=ar.active.activation*ar.active.twist*(.9/cfg.segments)*ar.active.extension;const double alpha=(1e-5*(1-.9*ar.active.stiffness))/(h*h);
// The first material section is attached to a deformable torso orientation.
// Opposite displacements at two cage nodes transmit its torque into the world.
const Vec3 axis=unit(p[ar.p[1]].x-p[ar.p[0]].x),up{0,1,0};Vec3 side=cross(axis,up);if(norm(side)<1e-5)side=cross(axis,Vec3{1,0,0});side=unit(side);
auto&top=p[a.body[3]];auto&bottom=p[a.body[4]];Vec3 span=top.x-bottom.x;double vertical=dot(span,up),lateral=dot(span,side),den=vertical*vertical+lateral*lateral;
if(den>1e-8){const double body_angle=std::atan2(lateral,vertical);Vec3 grad=(side*vertical-up*lateral)/den;auto&first=ar.roll[1];double error=first.angle-body_angle-desired;double weight=first.inv_inertia+(top.inv+bottom.inv)*dot(grad,grad);double delta=(-error-alpha*first.lambda)/(weight+alpha);first.lambda+=delta;first.angle+=first.inv_inertia*delta;top.x=top.x-grad*(top.inv*delta);bottom.x=bottom.x+grad*(bottom.inv*delta);span=top.x-bottom.x;ar.roll[0].angle=std::atan2(dot(span,side),dot(span,up));}
for(size_t j=2;j<ar.roll.size();++j){auto&left=ar.roll[j-1];auto&right=ar.roll[j];const double error=right.angle-left.angle-desired;const double delta=(-error-alpha*right.lambda)/(left.inv_inertia+right.inv_inertia+alpha);right.lambda+=delta;left.angle-=left.inv_inertia*delta;right.angle+=right.inv_inertia*delta;}}}
void director_constraints(double h){namespace rm=rod_math;
for(auto&a:animals)for(auto&ar:a.arms){
const double shear_alpha=3e-6/(h*h),bend_alpha=5e-5*(16.0/cfg.segments)*(1-.85*ar.active.stiffness)/(h*h);
for(size_t j=0;j<ar.directors.size();++j){const double segment_length=ar.length_targets[j];auto&director=ar.directors[j];auto&left=p[ar.p[j]];auto&right=p[ar.p[j+1]];
Vec3 e=rm::rotate(director.q,{0,0,1}),span=right.x-left.x;
Vec3 error=rm::sub(span,rm::mul(e,rm::dot(span,e)));
double den=left.inv+right.inv+segment_length*segment_length*director.inv_inertia+shear_alpha;
Vec3 correction=rm::mul(rm::add(error,rm::mul(director.shear_lambda,shear_alpha)),1/den);
director.shear_lambda=rm::sub(director.shear_lambda,correction);
left.x=left.x+correction*left.inv;right.x=right.x-correction*right.inv;
director.q=rm::integrate(director.q,rm::mul(rm::cross(e,correction),segment_length*director.inv_inertia),1);
}
for(size_t j=1;j<ar.directors.size();++j){auto&left=ar.directors[j-1];auto&right=ar.directors[j];
Vec3 tangent=rm::rotate(left.q,{0,0,1});
Vec3 axis=rm::cross(tangent,ar.preferred_curvature[j]);
const double bend_length=.5*(ar.length_targets[j-1]+ar.length_targets[j]);
Quat target=rm::multiply(rm::rotation(rm::mul(axis,bend_length)),left.q);
Vec3 error=rm::log_rotation(rm::multiply(target,rm::inverse(right.q)));
double den=left.inv_inertia+right.inv_inertia+bend_alpha;
Vec3 correction=rm::mul(rm::sub(error,rm::mul(right.bend_lambda,bend_alpha)),1/den);
right.bend_lambda=rm::add(right.bend_lambda,correction);
left.q=rm::integrate(left.q,rm::mul(correction,-left.inv_inertia),1);
right.q=rm::integrate(right.q,rm::mul(correction,right.inv_inertia),1);
}}}
bool excluded(const P&a,const P&b){if(a.rigid>=0&&a.rigid==b.rigid)return true;if(a.animal>=0&&a.animal==b.animal){if(a.arm<0&&b.arm<0)return true;if(a.arm==b.arm&&std::abs(a.node-b.node)<=2)return true;if(a.arm<0&&b.node<=2)return true;if(b.arm<0&&a.node<=2)return true;if(a.node<=2&&b.node<=2)return true;}return false;}
// A coarse whole-prop guard catches center paths that cross before individual
// corner constraints can resolve the coherent body's translation.
void rigid_center_sweeps(){if(!cfg.collisions)return;const double diameter=2*.16*std::sqrt(3.0);
for(size_t i=0;i<rigids.size();++i)for(size_t j=i+1;j<rigids.size();++j){Vec3 a0{},a1{},b0{},b1{};
for(int id:rigids[i]){a0=a0+p[id].old/8;a1=a1+p[id].x/8;}
for(int id:rigids[j]){b0=b0+p[id].old/8;b1=b1+p[id].x/8;}
auto hit=swept_sphere_toi(a0,a1,b0,b1,diameter);
Vec3 n=hit?hit->normal:unit(b1-a1);
if(!hit&&norm(b1-a1)>=diameter)continue;
double correction=diameter-dot(b1-a1,n);if(correction<=0)continue;
for(int id:rigids[i])p[id].x=p[id].x-n*(correction*.5);
for(int id:rigids[j])p[id].x=p[id].x+n*(correction*.5);
++diag.swept_contacts;
}}
void contacts(){if(cfg.floor)for(auto&a:p)if(a.x.y<a.r){double depth=a.r-a.x.y;a.compression=std::max(a.compression,depth);diag.max_penetration=std::max(diag.max_penetration,depth);++diag.contact_count;a.x.y=a.r;Vec3 tangent{a.x.x-a.old.x,0,a.x.z-a.old.z};double l=norm(tangent);if(l>0)a.x=a.x-tangent*(std::min(l,cfg.friction*depth)/l);}
if(!cfg.collisions)return;
// Swept AABB broadphase includes both endpoints so fast crossing paths remain candidates.
contact_bounds.resize(p.size());contact_order.resize(p.size());
for(size_t i=0;i<p.size();++i){const auto&v=p[i];contact_bounds[i]={{std::min(v.old.x,v.x.x)-v.r,std::min(v.old.y,v.x.y)-v.r,std::min(v.old.z,v.x.z)-v.r},{std::max(v.old.x,v.x.x)+v.r,std::max(v.old.y,v.x.y)+v.r,std::max(v.old.z,v.x.z)+v.r}};contact_order[i]=int(i);}
std::sort(contact_order.begin(),contact_order.end(),[&](int a,int b){return contact_bounds[a].lo.x<contact_bounds[b].lo.x;});
for(size_t i=0;i<contact_order.size();++i){auto&a=p[contact_order[i]];for(size_t j=i+1;j<contact_order.size();++j){auto&b=p[contact_order[j]];
const auto&ba=contact_bounds[contact_order[i]],&bb=contact_bounds[contact_order[j]];
if(bb.lo.x>ba.hi.x)break;
if(excluded(a,b)||ba.lo.y>bb.hi.y||bb.lo.y>ba.hi.y||ba.lo.z>bb.hi.z||bb.lo.z>ba.hi.z)continue;
++diag.candidate_pairs;
Vec3 end=b.x-a.x;double l=norm(end),depth=a.r+b.r-l;Vec3 n{};
if(depth>0){n=l>1e-10?end/l:Vec3{1,0,0};diag.max_penetration=std::max(diag.max_penetration,depth);}
else{auto hit=swept_sphere_toi(a.old,a.x,b.old,b.x,a.r+b.r);if(!hit)continue;
n=hit->normal;depth=a.r+b.r-dot(end,n);if(depth<=1e-12)continue;++diag.swept_contacts;}
++diag.contact_count;
a.compression=std::max(a.compression,depth*.5);b.compression=std::max(b.compression,depth*.5);
if(a.animal>=0&&b.animal>=0&&a.animal!=b.animal)++diag.cross_animal_contacts;
if((a.animal>=0&&b.rigid>=0)||(b.animal>=0&&a.rigid>=0))++diag.animal_prop_contacts;
double w=a.inv+b.inv;a.x=a.x-n*(depth*a.inv/w);b.x=b.x+n*(depth*b.inv/w);
Vec3 relative=(b.x-b.old)-(a.x-a.old);Vec3 tangent=relative-n*dot(relative,n);double tl=norm(tangent);
if(tl>0){Vec3 corr=tangent*(std::min(tl,cfg.friction*depth)/tl);a.x=a.x+corr*(a.inv/w);b.x=b.x-corr*(b.inv/w);}
}}}


void sweep_motors(double h){
 // ±60 degree anterior/posterior sweep relative to the body's own +Z axis.
 // Spring forces have equal-and-opposite torso reactions and cannot teleport.
 const double pi=std::acos(-1.0);
 for(auto&animal:animals){
  Vec3 forward=unit(p[animal.body[5]].x-p[animal.body[6]].x);
  Vec3 right=unit(cross({0,1,0},forward));
  for(auto&ar:animal.arms){
   if(std::abs(ar.active.sweep)<1e-5)continue;
   double angle=ar.arm_index*pi/4;
   Vec3 home=right*std::sin(angle)+forward*std::cos(angle);
   double turn=(ar.arm_index<4?1.0:-1.0)*(pi/3.0)*ar.active.sweep;
   Vec3 goal=home*std::cos(turn)+cross({0,1,0},home)*std::sin(turn);
   Vec3 root=p[ar.p[0]].x;
   for(unsigned j=std::max(2u,cfg.segments/3);j<=cfg.segments;++j){
    double u=double(j)/cfg.segments;
    auto&site=p[ar.p[j]];
    Vec3 error=root+goal*(.9*u*ar.active.extension)-site.x;
    double k=1.3;Vec3 force=error*k;double l=norm(force);
    if(l>.085)force=force*(.085/l);
    site.x=site.x+force*(site.inv*h*h);
    for(int body_id:animal.body)p[body_id].x=p[body_id].x-force*(p[body_id].inv*h*h/animal.body.size());
   }
  }
 }
}
void suction_constraints(double h){
 if(!cfg.auto_suction||release_held)return;
 for(auto&animal:animals)for(auto&ar:animal.arms)for(auto&s:ar.suckers){
  if(s.attached==-1)continue;
  auto&node=p[ar.p[s.node]];
  Vec3 target=s.attached==-2?s.anchor:p[s.attached].x;
  Vec3 delta=target-node.x;double length=norm(delta);
  if(length<1e-10)continue;
  double error=length-(s.attached==-2?0:s.rest);
  double inverse=node.inv+(s.attached>=0?p[s.attached].inv:0);
  double alpha=4e-7/(h*h),lam=error/(inverse+alpha);
  double site_area=std::max(.002,node.r/.035);
  if(std::abs(lam)/(h*h)>12.0*site_area*site_area){
   s.attached=-1;s.cooldown=.18;++diag.broken_attachments;continue;
  }
  Vec3 correction=delta*(lam/length);
  node.x=node.x+correction*node.inv;
  if(s.attached>=0)p[s.attached].x=p[s.attached].x-correction*p[s.attached].inv;
 }
}
void update_suckers(double h){
 if(!cfg.auto_suction)return;
 for(auto&animal:animals)for(auto&ar:animal.arms){
  if(ar.active.extension<.87)ar.peel_clock+=h;else ar.peel_clock=0;
  for(auto&s:ar.suckers){
   s.cooldown=std::max(0.0,s.cooldown-h);
   if(release_held){s.attached=-1;s.dwell=0;s.cooldown=.18;continue;}
   if(s.attached==-2&&ar.active.extension<.87){
    const double delay=(double(cfg.segments-s.node)/cfg.segments)*.22;
    if(ar.peel_clock>=delay){s.attached=-1;s.cooldown=.18;s.dwell=0;}
   }
   if(s.attached!=-1||s.cooldown>0)continue;
   auto&node=p[ar.p[s.node]];
   Vec3 tangent=unit(p[ar.p[std::min(unsigned(cfg.segments),s.node+1)]].x-p[ar.p[s.node-1]].x);
   Vec3 down{0,-1,0};
   Vec3 sucker_face=down-tangent*dot(down,tangent);
   if(norm(sucker_face)<.25){s.dwell=0;continue;}
   sucker_face=unit(sucker_face);
   if(norm(node.v)>.75){s.dwell=0;continue;}
   int target=-1;Vec3 anchor{};double rest=0;
   if(cfg.floor&&node.x.y-node.r<.014&&dot(sucker_face,down)>.45){
    target=-2;anchor={node.x.x,node.r,node.x.z};
   }else if(cfg.collisions){
    double best=.014;
    for(size_t j=0;j<p.size();++j){
     if(p[j].rigid<0)continue;
     Vec3 to=p[j].x-node.x;double gap=norm(to)-(p[j].r+node.r);
     if(gap<best&&norm(p[j].v-node.v)<.65&&dot(sucker_face,unit(to))>.3){
      target=int(j);rest=norm(to);best=gap;
     }
    }
   }
   const double area=std::acos(-1.)*node.r*node.r;
   if(target==-1||area<.00009){s.dwell=0;continue;}
   s.dwell+=h;
   if(s.dwell<.032)continue;
   s.attached=target;s.anchor=anchor;s.rest=rest;s.dwell=0;
  }
 }
}

void attachments(double h){for(auto&a:animals)for(auto&ar:a.arms){auto&tip=p[ar.p.back()];if(!ar.target.attach){ar.attached=-1;continue;}if(ar.attached==-1){if(cfg.floor&&tip.x.y-tip.r<.025){ar.attached=-2;ar.anchor={tip.x.x,tip.r,tip.x.z};}else for(size_t i=0;i<p.size();++i)if(p[i].rigid>=0&&norm(p[i].x-tip.x)<p[i].r+tip.r+.025){ar.attached=int(i);ar.attach_rest=norm(p[i].x-tip.x);break;}}
if(ar.attached==-1)continue;Vec3 target=ar.attached==-2?ar.anchor:p[ar.attached].x;Vec3 delta=target-tip.x;double l=norm(delta);double rest=ar.attached==-2?0:ar.attach_rest;double w=tip.inv+(ar.attached>=0?p[ar.attached].inv:0);double impulse=(l-rest)/(w+1e-7/(h*h));if(std::abs(impulse)/(h*h)>8){ar.attached=-1;++diag.broken_attachments;continue;}if(l>1e-10){Vec3 correction=delta*(impulse/l);tip.x=tip.x+correction*tip.inv;if(ar.attached>=0)p[ar.attached].x=p[ar.attached].x-correction*p[ar.attached].inv;}}}
bool step(){auto start=std::chrono::steady_clock::now();diag={};double h=cfg.fixed_dt/cfg.substeps;
for(unsigned sub=0;sub<cfg.substeps;++sub){for(auto&a:animals)for(auto&ar:a.arms){double f=1-std::exp(-h*12);auto blend=[&](double&v,double t){v+=(t-v)*f;};blend(ar.active.activation,ar.target.activation);blend(ar.active.curvature,ar.target.curvature);blend(ar.active.extension,ar.target.extension);blend(ar.active.stiffness,ar.target.stiffness);blend(ar.active.twist,ar.target.twist);blend(ar.active.sweep,ar.target.sweep);}
update_preferred_curvature(time+sub*h);
for(auto&particle:p)particle.compression=0;
for(auto&e:d){e.lambda=0;if(p[e.a].arm>=0&&p[e.a].arm==p[e.b].arm&&p[e.a].animal==p[e.b].animal&&std::abs(p[e.a].node-p[e.b].node)==1)e.rest=animals[p[e.a].animal].arms[p[e.a].arm].length_targets[std::min(p[e.a].node,p[e.b].node)];}
for(auto&t:tetra)t.lambda=0;
for(auto&a:animals)for(auto&ar:a.arms)std::fill(ar.bend_lambda.begin(),ar.bend_lambda.end(),Vec3{});
for(auto&a:animals)for(auto&ar:a.arms)for(auto&roll:ar.roll){roll.lambda=0;roll.old=roll.angle;roll.omega*=std::exp(-cfg.damping*h);roll.angle+=roll.omega*h;}
for(auto&a:animals)for(auto&ar:a.arms)for(auto&director:ar.directors){director.old=director.q;director.bend_lambda={};director.shear_lambda={};director.omega=director.omega*std::exp(-cfg.damping*h);director.q=rod_math::integrate(director.q,director.omega,h);}
int dragged=-1;if(drag.kind==DragCommand::Kind::Animal)dragged=animals[drag.index].body[0];if(drag.kind==DragCommand::Kind::ArmTip)dragged=animals[drag.index].arms[drag.arm].p.back();if(drag.kind==DragCommand::Kind::Rigid)dragged=rigids[drag.index][0];
for(size_t i=0;i<p.size();++i){auto&a=p[i];a.old=a.x;Vec3 force{};if(int(i)==dragged){force=(drag.target-a.x)*drag.stiffness;double l=norm(force);if(l>drag.max_force)force=force*(drag.max_force/l);}a.v=(a.v+(cfg.gravity+force*a.inv)*h)*std::exp(-cfg.damping*h);a.x=a.x+a.v*h;}
sweep_motors(h);
rigid_center_sweeps();
for(unsigned it=0;it<cfg.iterations;++it){auto c0=std::chrono::steady_clock::now();for(auto&e:d)distance(e,h);volumes(h);bending(h);torsion(h);if(it%4==0||it+1==cfg.iterations)director_constraints(h);attachments(h);suction_constraints(h);diag.constraints_ms+=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-c0).count();auto t0=std::chrono::steady_clock::now();contacts();diag.collision_ms+=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-t0).count();}
rigid_center_sweeps();
update_suckers(h);
for(auto&a:animals)for(auto&ar:a.arms)for(unsigned j=0;j<cfg.segments;++j){double l=norm(p[ar.p[j+1]].x-p[ar.p[j]].x);double pressure=std::max(p[ar.p[j]].compression,p[ar.p[j+1]].compression);// A pressed muscular hydrostat stays rounded, not a zero-thickness ribbon.
// Clamp the dynamic ellipse aspect ratio to keep the arm's cross section
// visibly voluminous; the area*length constraint remains exact.
double target=std::clamp(1-2*pressure/std::max(ar.radius[j],1e-5),.70,1.0);
const double omega=16.0,zeta=.65;
ar.squash_velocity[j]+=(omega*omega*(target-ar.squash[j])-2*zeta*omega*ar.squash_velocity[j])*h;
ar.squash[j]=std::clamp(ar.squash[j]+ar.squash_velocity[j]*h,.68,1.12);
if(ar.squash[j]<=.68||ar.squash[j]>=1.12)ar.squash_velocity[j]=0;p[ar.p[j]].r=ar.radius[j]*std::sqrt((.9/cfg.segments)/std::max(l,1e-5));p[ar.p[j]].r=std::min(.1,p[ar.p[j]].r);}
for(auto&a:p){a.v=(a.x-a.old)/h;if(!finite(a.x)||!finite(a.v)){++diag.nonfinite_count;return false;}}
for(auto&a:animals)for(auto&ar:a.arms)for(auto&roll:ar.roll){roll.omega=(roll.angle-roll.old)/h;if(!std::isfinite(roll.angle)||!std::isfinite(roll.omega)){++diag.nonfinite_count;return false;}}
for(auto&a:animals)for(auto&ar:a.arms)for(auto&director:ar.directors){director.q=rod_math::normalize(director.q);director.omega=rod_math::mul(rod_math::log_rotation(rod_math::multiply(director.q,rod_math::inverse(director.old))),1/h);if(!finite(director.omega)||!std::isfinite(director.q.w)){++diag.nonfinite_count;return false;}}
}
for(auto&a:p){diag.linear_momentum=diag.linear_momentum+a.v/a.inv;diag.angular_momentum=diag.angular_momentum+cross(a.x,a.v/a.inv);diag.kinetic_energy+=.5*dot(a.v,a.v)/a.inv;}for(auto&a:animals)for(auto&ar:a.arms){Vec3 axis=unit(p[ar.p[1]].x-p[ar.p[0]].x);for(auto&roll:ar.roll)if(roll.inv_inertia>0){diag.kinetic_energy+=.5*roll.omega*roll.omega/roll.inv_inertia;diag.angular_momentum=diag.angular_momentum+axis*(roll.omega/roll.inv_inertia);}for(size_t j=0;j<ar.directors.size();++j){auto&director=ar.directors[j];diag.kinetic_energy+=.5*dot(director.omega,director.omega)/director.inv_inertia;diag.angular_momentum=diag.angular_momentum+director.omega/director.inv_inertia;Vec3 tangent=unit(p[ar.p[j+1]].x-p[ar.p[j]].x),material=rod_math::rotate(director.q,{0,0,1});diag.max_shear_error=std::max(diag.max_shear_error,norm(cross(tangent,material)));}}for(auto&t:tetra)diag.max_volume_error=std::max(diag.max_volume_error,std::abs((volume(t)-t.rest)/t.rest));for(auto&a:animals)for(auto&ar:a.arms){if(ar.attached!=-1)++diag.attachments;for(const auto& suction:ar.suckers)if(suction.attached!=-1)++diag.attachments;}++tick;time+=cfg.fixed_dt;diag.step_ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();return true;}
RenderSnapshot snapshot()const{RenderSnapshot s;s.tick=tick;s.time=time;s.diagnostics=diag;for(auto&a:animals){AnimalSnapshot as;as.center=p[a.body[0]].x;as.orientation=frame(p[a.body[5]].x-p[a.body[6]].x);for(int b:a.body)as.body_nodes.push_back(p[b].x);for(int k=0;k<8;++k){auto&ar=a.arms[k];auto&out=as.arms[k];for(int id:ar.p)out.nodes.push_back(p[id].x);for(unsigned j=0;j<cfg.segments;++j){Vec3 tangent=p[ar.p[j+1]].x-p[ar.p[j]].x;out.frames.push_back(roll_frame(ar.directors[j].q,ar.roll[j].angle));out.angular_velocities.push_back(ar.directors[j].omega);out.material_roll.push_back(ar.roll[j].angle);double r=ar.radius[j]*std::sqrt((.9/cfg.segments)/std::max(norm(tangent),1e-12));out.radii.push_back({r/ar.squash[j],r*ar.squash[j]});bool held=j==cfg.segments-1&&ar.attached!=-1;
for(const auto& suction:ar.suckers)if(suction.attached!=-1&&suction.node==j+1)held=true;
out.attached.push_back(held);}}s.animals.push_back(as);}for(auto&ids:rigids){RigidSnapshot rs;for(int id:ids)rs.center=rs.center+p[id].x/8;rs.orientation=frame(p[ids[1]].x-p[ids[0]].x);s.rigids.push_back(rs);}return s;}
};
PhysicsWorld::PhysicsWorld(const WorldConfig& c):impl_(std::make_unique<Impl>(c)){}
PhysicsWorld::~PhysicsWorld()=default;PhysicsWorld::PhysicsWorld(PhysicsWorld&&) noexcept=default;PhysicsWorld&PhysicsWorld::operator=(PhysicsWorld&&) noexcept=default;
void PhysicsWorld::reset(const WorldConfig&c){auto fresh=std::make_unique<Impl>(c);impl_=std::move(fresh);}
const WorldConfig&PhysicsWorld::config()const{return impl_->cfg;}
bool PhysicsWorld::command(const MuscleCommand&c){if(c.animal>=impl_->animals.size()||c.arm>=8||!std::isfinite(c.activation)||!std::isfinite(c.curvature)||!std::isfinite(c.extension)||!std::isfinite(c.twist)||!std::isfinite(c.stiffness)||!std::isfinite(c.sweep))return false;auto v=c;v.activation=std::clamp(v.activation,0.,1.);v.curvature=std::clamp(v.curvature,-15.,15.);v.extension=std::clamp(v.extension,.65,1.35);v.twist=std::clamp(v.twist,-20.,20.);v.stiffness=std::clamp(v.stiffness,0.,1.);v.sweep=std::clamp(v.sweep,-1.,1.);impl_->animals[c.animal].arms[c.arm].target=v;return true;}
void PhysicsWorld::release_all_suckers(bool held){impl_->release_held=held;if(held)for(auto&a:impl_->animals)for(auto&ar:a.arms){ar.attached=-1;for(auto&s:ar.suckers){s.attached=-1;s.dwell=0;s.cooldown=std::max(s.cooldown,.18);}}}
bool PhysicsWorld::drag(const DragCommand&c){if(!finite(c.target)||!std::isfinite(c.stiffness)||!std::isfinite(c.max_force)||c.stiffness<0||c.max_force<0||c.stiffness>1e5||c.max_force>1e4)return false;switch(c.kind){case DragCommand::Kind::None:break;case DragCommand::Kind::Animal:if(c.index>=impl_->animals.size())return false;break;case DragCommand::Kind::ArmTip:if(c.index>=impl_->animals.size()||c.arm>=8)return false;break;case DragCommand::Kind::Rigid:if(c.index>=impl_->rigids.size())return false;break;default:return false;}impl_->drag=c;return true;}
bool PhysicsWorld::impulse_rigid(std::uint32_t index,Vec3 impulse){if(index>=impl_->rigids.size()||!finite(impulse))return false;const auto&ids=impl_->rigids[index];const Vec3 share=impulse/double(ids.size());for(int id:ids)impl_->p[id].v=impl_->p[id].v+share*impl_->p[id].inv;return true;}
bool PhysicsWorld::step(){return impl_->step();}RenderSnapshot PhysicsWorld::snapshot()const{return impl_->snapshot();}
}

