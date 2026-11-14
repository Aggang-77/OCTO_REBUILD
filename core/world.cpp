#include "octo/world.hpp"
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
Quat frame(Vec3 z){z=unit(z);Vec3 x=unit(cross(std::abs(z.y)<.95?Vec3{0,1,0}:Vec3{1,0,0},z)),y=cross(z,x);double t=x.x+y.y+z.z;Quat q;if(t>0){double s=2*std::sqrt(1+t);q={(y.z-z.y)/s,(z.x-x.z)/s,(x.y-y.x)/s,s/4};}else{ // robust rotation from +Z, roll is purely visual
 double d=std::clamp(z.z,-1.,1.);if(d<-.999999)q={0,1,0,0};else {Vec3 c=cross({0,0,1},z);double s=std::sqrt(2*(1+d));q={c.x/s,c.y/s,c.z/s,s/2};}}
return q;}
}
struct PhysicsWorld::Impl {
struct P{Vec3 x,old,v;double inv,r;int animal,arm,node,rigid;};
struct D{int a,b;double rest,compliance,lambda=0;};
struct T{std::array<int,4> p;double rest,lambda=0;};
struct Arm{std::vector<int> p;std::vector<double> radius;MuscleCommand target{},active{};int attached=-1;Vec3 anchor{};double attach_rest=0;};
struct Animal{std::vector<int> body;std::array<Arm,8> arms;};
WorldConfig cfg;std::vector<P> p;std::vector<D> d;std::vector<T> tetra;std::vector<Animal> animals;std::vector<std::vector<int>> rigids;DragCommand drag;Diagnostics diag;std::uint64_t tick=0;double time=0;
int particle(Vec3 x,double mass,double radius,int animal=-1,int arm=-1,int node=-1,int rigid=-1){p.push_back({x,x,{},1/mass,radius,animal,arm,node,rigid});return int(p.size()-1);}
void edge(int a,int b,double compliance){d.push_back({a,b,norm(p[a].x-p[b].x),compliance});}
double volume(const T&t)const{auto a=p[t.p[0]].x;return dot(p[t.p[1]].x-a,cross(p[t.p[2]].x-a,p[t.p[3]].x-a))/6;}
explicit Impl(WorldConfig c):cfg(c){
if(c.animals>64||c.segments<2||c.segments>64||c.substeps<1||c.substeps>64||c.iterations<1||c.iterations>100||!finite(c.gravity)||!std::isfinite(c.fixed_dt)||c.fixed_dt<=0||c.fixed_dt>.1||!std::isfinite(c.damping)||c.damping<0||!std::isfinite(c.friction)||c.friction<0||!std::isfinite(c.spacing)||c.spacing<0||!std::isfinite(c.spawn_height)||c.rigid_count>128)throw std::invalid_argument("Invalid WorldConfig");
for(unsigned n=0;n<c.animals;++n){Animal a;Vec3 center{(double(n)-double(c.animals-1)/2)*c.spacing,c.spawn_height,0};
for(Vec3 off:std::array<Vec3,7>{{{0,0,0},{.2,0,0},{-.2,0,0},{0,.24,0},{0,-.16,0},{0,0,.2},{0,0,-.2}}})a.body.push_back(particle(center+off,.12,.065,int(n)));
for(int i=0;i<7;++i)for(int j=i+1;j<7;++j)edge(a.body[i],a.body[j],2e-5);
for(int x:{1,2})for(int y:{3,4})for(int z:{5,6}){T t{{a.body[0],a.body[x],a.body[y],a.body[z]},0};t.rest=volume(t);tetra.push_back(t);}
for(int k=0;k<8;++k){auto& ar=a.arms[k];double angle=k*std::acos(-1.)/4;Vec3 radial{std::sin(angle),0,std::cos(angle)};for(unsigned j=0;j<=c.segments;++j){double u=double(j)/c.segments;double radius=.036*(1-.8*u);ar.radius.push_back(radius);ar.p.push_back(particle(center+radial*(.2+.9*u),.012,radius,int(n),k,int(j)));if(j)edge(ar.p[j-1],ar.p[j],3e-7);}
// Root attached to every cage vertex; all reactions act on dynamic torso.
for(int b:a.body)edge(ar.p[0],b,1e-7);
}
animals.push_back(a);}
for(unsigned k=0;k<c.rigid_count;++k){std::vector<int> ids;Vec3 center{double(k)*.65-.65,.32,1.35};for(int x:{-1,1})for(int y:{-1,1})for(int z:{-1,1})ids.push_back(particle(center+Vec3{x*.16,y*.16,z*.16},.125,.08,-1,-1,-1,int(k)));for(int i=0;i<8;++i)for(int j=i+1;j<8;++j)edge(ids[i],ids[j],1e-9);rigids.push_back(ids);}}
void distance(D& e,double h){auto&a=p[e.a];auto&b=p[e.b];Vec3 delta=b.x-a.x;double l=norm(delta);if(l<1e-12)return;double alpha=e.compliance/(h*h),dl=(-(l-e.rest)-alpha*e.lambda)/(a.inv+b.inv+alpha);e.lambda+=dl;Vec3 impulse=delta*(dl/l);a.x=a.x-impulse*a.inv;b.x=b.x+impulse*b.inv;}
void volumes(double h){for(auto&t:tetra){auto a=p[t.p[0]].x,b=p[t.p[1]].x,c=p[t.p[2]].x,e=p[t.p[3]].x;std::array<Vec3,4> g;g[1]=cross(c-a,e-a)/6;g[2]=cross(e-a,b-a)/6;g[3]=cross(b-a,c-a)/6;g[0]=(g[1]+g[2]+g[3])*(-1);double alpha=1e-10/(h*h),den=alpha;for(int i=0;i<4;++i)den+=p[t.p[i]].inv*dot(g[i],g[i]);double dl=(-(volume(t)-t.rest)-alpha*t.lambda)/den;t.lambda+=dl;for(int i=0;i<4;++i){auto&v=p[t.p[i]];v.x=v.x+g[i]*(v.inv*dl);}}}
void bending(double h){for(auto&a:animals){Vec3 up=unit(p[a.body[3]].x-p[a.body[4]].x);for(auto&ar:a.arms){double length=.9/cfg.segments*ar.active.extension;for(unsigned j=1;j<cfg.segments;++j){auto&l=p[ar.p[j-1]];auto&m=p[ar.p[j]];auto&r=p[ar.p[j+1]];Vec3 target=up*(ar.active.curvature*ar.active.activation*length*length);Vec3 error=l.x-m.x*2+r.x-target;double alpha=(2e-5*(1-.9*ar.active.stiffness))/(h*h);Vec3 dl=error*(-1/(l.inv+4*m.inv+r.inv+alpha));l.x=l.x+dl*l.inv;m.x=m.x-dl*(2*m.inv);r.x=r.x+dl*r.inv;}}}}
bool excluded(const P&a,const P&b){if(a.rigid>=0&&a.rigid==b.rigid)return true;if(a.animal>=0&&a.animal==b.animal){if(a.arm<0&&b.arm<0)return true;if(a.arm==b.arm&&std::abs(a.node-b.node)<=2)return true;if(a.arm<0&&b.node<=2)return true;if(b.arm<0&&a.node<=2)return true;if(a.node<=2&&b.node<=2)return true;}return false;}
void contacts(){if(cfg.floor)for(auto&a:p)if(a.x.y<a.r){double depth=a.r-a.x.y;diag.max_penetration=std::max(diag.max_penetration,depth);++diag.contact_count;a.x.y=a.r;Vec3 tangent{a.x.x-a.old.x,0,a.x.z-a.old.z};double l=norm(tangent);if(l>0)a.x=a.x-tangent*(std::min(l,cfg.friction*depth)/l);}
if(!cfg.collisions)return;
// Sweep broadphase: exact sphere pairs within sorted x intervals.
std::vector<int> order(p.size());for(size_t i=0;i<p.size();++i)order[i]=int(i);std::sort(order.begin(),order.end(),[&](int a,int b){return p[a].x.x-p[a].r<p[b].x.x-p[b].r;});
for(size_t i=0;i<order.size();++i){auto&a=p[order[i]];for(size_t j=i+1;j<order.size();++j){auto&b=p[order[j]];if(b.x.x-b.r>a.x.x+a.r)break;if(excluded(a,b))continue;++diag.candidate_pairs;Vec3 v=b.x-a.x;double l=norm(v),depth=a.r+b.r-l;if(depth<=0)continue;++diag.contact_count;diag.max_penetration=std::max(diag.max_penetration,depth);Vec3 n=l>1e-10?v/l:Vec3{1,0,0};double w=a.inv+b.inv;a.x=a.x-n*(depth*a.inv/w);b.x=b.x+n*(depth*b.inv/w);Vec3 relative=(b.x-b.old)-(a.x-a.old);Vec3 tangent=relative-n*dot(relative,n);double tl=norm(tangent);if(tl>0){Vec3 corr=tangent*(std::min(tl,cfg.friction*depth)/tl);a.x=a.x+corr*(a.inv/w);b.x=b.x-corr*(b.inv/w);}}}}
void attachments(double h){for(auto&a:animals)for(auto&ar:a.arms){auto&tip=p[ar.p.back()];if(!ar.target.attach){ar.attached=-1;continue;}if(ar.attached==-1){if(cfg.floor&&tip.x.y-tip.r<.025){ar.attached=-2;ar.anchor={tip.x.x,tip.r,tip.x.z};}else for(size_t i=0;i<p.size();++i)if(p[i].rigid>=0&&norm(p[i].x-tip.x)<p[i].r+tip.r+.025){ar.attached=int(i);ar.attach_rest=norm(p[i].x-tip.x);break;}}
if(ar.attached==-1)continue;Vec3 target=ar.attached==-2?ar.anchor:p[ar.attached].x;Vec3 delta=target-tip.x;double l=norm(delta);double rest=ar.attached==-2?0:ar.attach_rest;double w=tip.inv+(ar.attached>=0?p[ar.attached].inv:0);double impulse=(l-rest)/(w+1e-7/(h*h));if(std::abs(impulse)/(h*h)>8){ar.attached=-1;++diag.broken_attachments;continue;}if(l>1e-10){Vec3 correction=delta*(impulse/l);tip.x=tip.x+correction*tip.inv;if(ar.attached>=0)p[ar.attached].x=p[ar.attached].x-correction*p[ar.attached].inv;}}}
bool step(){auto start=std::chrono::steady_clock::now();diag={};double h=cfg.fixed_dt/cfg.substeps;
for(unsigned sub=0;sub<cfg.substeps;++sub){for(auto&a:animals)for(auto&ar:a.arms){double f=1-std::exp(-h*12);auto blend=[&](double&v,double t){v+=(t-v)*f;};blend(ar.active.activation,ar.target.activation);blend(ar.active.curvature,ar.target.curvature);blend(ar.active.extension,ar.target.extension);blend(ar.active.stiffness,ar.target.stiffness);blend(ar.active.twist,ar.target.twist);}
for(auto&e:d){e.lambda=0;if(p[e.a].arm>=0&&p[e.a].arm==p[e.b].arm&&p[e.a].animal==p[e.b].animal&&std::abs(p[e.a].node-p[e.b].node)==1)e.rest=.9/cfg.segments*animals[p[e.a].animal].arms[p[e.a].arm].active.extension;}
for(auto&t:tetra)t.lambda=0;
int dragged=-1;if(drag.kind==DragCommand::Kind::Animal)dragged=animals[drag.index].body[0];if(drag.kind==DragCommand::Kind::ArmTip)dragged=animals[drag.index].arms[drag.arm].p.back();if(drag.kind==DragCommand::Kind::Rigid)dragged=rigids[drag.index][0];
for(size_t i=0;i<p.size();++i){auto&a=p[i];a.old=a.x;Vec3 force{};if(int(i)==dragged){force=(drag.target-a.x)*drag.stiffness;double l=norm(force);if(l>drag.max_force)force=force*(drag.max_force/l);}a.v=(a.v+(cfg.gravity+force*a.inv)*h)*std::exp(-cfg.damping*h);a.x=a.x+a.v*h;}
for(unsigned it=0;it<cfg.iterations;++it){auto c0=std::chrono::steady_clock::now();for(auto&e:d)distance(e,h);volumes(h);bending(h);attachments(h);diag.constraints_ms+=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-c0).count();auto t0=std::chrono::steady_clock::now();contacts();diag.collision_ms+=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-t0).count();}
for(auto&a:animals)for(auto&ar:a.arms)for(unsigned j=0;j<cfg.segments;++j){double l=norm(p[ar.p[j+1]].x-p[ar.p[j]].x);p[ar.p[j]].r=ar.radius[j]*std::sqrt((.9/cfg.segments)/std::max(l,1e-5));p[ar.p[j]].r=std::min(.1,p[ar.p[j]].r);}
for(auto&a:p){a.v=(a.x-a.old)/h;if(!finite(a.x)||!finite(a.v)){++diag.nonfinite_count;return false;}}
}
for(auto&a:p){diag.linear_momentum=diag.linear_momentum+a.v/a.inv;diag.kinetic_energy+=.5*dot(a.v,a.v)/a.inv;}for(auto&t:tetra)diag.max_volume_error=std::max(diag.max_volume_error,std::abs((volume(t)-t.rest)/t.rest));for(auto&a:animals)for(auto&ar:a.arms)if(ar.attached!=-1)++diag.attachments;++tick;time+=cfg.fixed_dt;diag.step_ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();return true;}
RenderSnapshot snapshot()const{RenderSnapshot s;s.tick=tick;s.time=time;s.diagnostics=diag;for(auto&a:animals){AnimalSnapshot as;as.center=p[a.body[0]].x;as.orientation=frame(p[a.body[5]].x-p[a.body[6]].x);for(int b:a.body)as.body_nodes.push_back(p[b].x);for(int k=0;k<8;++k){auto&ar=a.arms[k];auto&out=as.arms[k];for(int id:ar.p)out.nodes.push_back(p[id].x);for(unsigned j=0;j<cfg.segments;++j){Vec3 tangent=p[ar.p[j+1]].x-p[ar.p[j]].x;Quat q=frame(tangent);double angle=ar.active.twist*(double(j)+.5)*.9/cfg.segments;Quat twist{0,0,std::sin(angle/2),std::cos(angle/2)};out.frames.push_back({q.w*twist.x+q.x*twist.w+q.y*twist.z-q.z*twist.y,q.w*twist.y-q.x*twist.z+q.y*twist.w+q.z*twist.x,q.w*twist.z+q.x*twist.y-q.y*twist.x+q.z*twist.w,q.w*twist.w-q.x*twist.x-q.y*twist.y-q.z*twist.z});double r=ar.radius[j]*std::sqrt((.9/cfg.segments)/std::max(norm(tangent),1e-12));out.radii.push_back({r,r});out.attached.push_back(j==cfg.segments-1&&ar.attached!=-1);}}s.animals.push_back(as);}for(auto&ids:rigids){RigidSnapshot rs;for(int id:ids)rs.center=rs.center+p[id].x/8;rs.orientation=frame(p[ids[1]].x-p[ids[0]].x);s.rigids.push_back(rs);}return s;}
};
PhysicsWorld::PhysicsWorld(const WorldConfig& c):impl_(std::make_unique<Impl>(c)){}
PhysicsWorld::~PhysicsWorld()=default;PhysicsWorld::PhysicsWorld(PhysicsWorld&&) noexcept=default;PhysicsWorld&PhysicsWorld::operator=(PhysicsWorld&&) noexcept=default;
void PhysicsWorld::reset(const WorldConfig&c){auto fresh=std::make_unique<Impl>(c);impl_=std::move(fresh);}
const WorldConfig&PhysicsWorld::config()const{return impl_->cfg;}
bool PhysicsWorld::command(const MuscleCommand&c){if(c.animal>=impl_->animals.size()||c.arm>=8||!std::isfinite(c.activation)||!std::isfinite(c.curvature)||!std::isfinite(c.extension)||!std::isfinite(c.twist)||c.twist!=0||!std::isfinite(c.stiffness))return false;auto v=c;v.activation=std::clamp(v.activation,0.,1.);v.curvature=std::clamp(v.curvature,-15.,15.);v.extension=std::clamp(v.extension,.65,1.35);v.twist=std::clamp(v.twist,-20.,20.);v.stiffness=std::clamp(v.stiffness,0.,1.);impl_->animals[c.animal].arms[c.arm].target=v;return true;}
bool PhysicsWorld::drag(const DragCommand&c){if(!finite(c.target)||!std::isfinite(c.stiffness)||!std::isfinite(c.max_force)||c.stiffness<0||c.max_force<0||c.stiffness>1e5||c.max_force>1e4)return false;switch(c.kind){case DragCommand::Kind::None:break;case DragCommand::Kind::Animal:if(c.index>=impl_->animals.size())return false;break;case DragCommand::Kind::ArmTip:if(c.index>=impl_->animals.size()||c.arm>=8)return false;break;case DragCommand::Kind::Rigid:if(c.index>=impl_->rigids.size())return false;break;default:return false;}impl_->drag=c;return true;}
bool PhysicsWorld::step(){return impl_->step();}RenderSnapshot PhysicsWorld::snapshot()const{return impl_->snapshot();}
}

