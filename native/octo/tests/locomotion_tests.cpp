#include "octo/world.hpp"
#include "octo/arm_layout.hpp"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

using namespace octo;

namespace {
constexpr double pi=layout::pi;
Vec3 add(Vec3 a,Vec3 b){return {a.x+b.x,a.y+b.y,a.z+b.z};}
Vec3 sub(Vec3 a,Vec3 b){return {a.x-b.x,a.y-b.y,a.z-b.z};}
Vec3 mul(Vec3 a,double s){return {a.x*s,a.y*s,a.z*s};}
double dot(Vec3 a,Vec3 b){return a.x*b.x+a.y*b.y+a.z*b.z;}
Vec3 cross(Vec3 a,Vec3 b){return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x};}
double length(Vec3 a){return std::hypot(a.x,a.y,a.z);}
Vec3 unit(Vec3 a){const double n=length(a);return n>1e-12?mul(a,1/n):Vec3{0,1,0};}
double angle_error(double a,double b){return std::abs(std::remainder(a-b,2*pi));}
bool finite(Vec3 a){return std::isfinite(a.x)&&std::isfinite(a.y)&&std::isfinite(a.z);}
unsigned grips(const ArmSnapshot& a){return static_cast<unsigned>(std::count(a.attached.begin(),a.attached.end(),true));}
unsigned grips(const RenderSnapshot& s){unsigned n=0;for(const auto& a:s.animals[0].arms)n+=grips(a);return n;}
double yaw(const RenderSnapshot& s){const auto& b=s.animals[0].body_nodes;const Vec3 f=sub(b[5],b[6]);return std::atan2(f.x,f.z);}

struct Case {
    std::string name;
    bool passed=true;
    void check(bool condition,const char* message){
        if(!condition){passed=false;std::cout<<"CHECK_FAIL case="<<name<<" message=\""<<message<<"\"\n";}
    }
};

WorldConfig config(){
    WorldConfig c;
    c.animals=1;c.rigid_count=0;c.size_scale=1.5;c.spawn_height=.45;
    c.auto_suction=true;c.locomotion_assist=true;c.collisions=true;c.floor=true;
    return c;
}
double arm_length(const WorldConfig& c){return .9*c.size_scale;}
void quad(std::vector<Vec3>& out,Vec3 a,Vec3 b,Vec3 c,Vec3 d){out.insert(out.end(),{a,b,c,a,c,d});}
std::vector<Vec3> flat_map(double extent=20){
    std::vector<Vec3> map;
    quad(map,{-extent,0,-extent},{-extent,0,extent},{extent,0,extent},{extent,0,-extent});
    return map;
}
std::vector<Vec3> ramp_map(double slope,double extent){
    std::vector<Vec3> map;
    quad(map,{-extent,-slope*extent,-extent},{-extent,slope*extent,extent},
             {extent,slope*extent,extent},{extent,-slope*extent,-extent});
    return map;
}
std::vector<Vec3> step_map(double height,double extent,bool descent){
    std::vector<Vec3> map;
    const double before=descent?height:0,after=descent?0:height;
    quad(map,{-extent,before,-extent},{-extent,before,0},{extent,before,0},{extent,before,-extent});
    quad(map,{-extent,before,0},{-extent,after,0},{extent,after,0},{extent,before,0});
    quad(map,{-extent,after,0},{-extent,after,extent},{extent,after,extent},{extent,after,0});
    return map;
}
std::vector<Vec3> roughness_map(double height,double l){
    const double extent=20*l,rise=.9*l,plateau=.7*l,end=2*rise+plateau;
    std::vector<Vec3> out;
    const auto strip=[&](double z0,double y0,double z1,double y1){
        quad(out,{-extent,y0,z0},{-extent,y1,z1},{extent,y1,z1},{extent,y0,z0});
    };
    strip(-extent,0,0,0);strip(0,0,rise,height);strip(rise,height,rise+plateau,height);
    strip(rise+plateau,height,end,0);strip(end,0,extent,0);
    return out;
}
void map(PhysicsWorld& world,const std::vector<Vec3>& vertices){
    if(!world.static_geometry(vertices))throw std::runtime_error("static triangle fixture rejected");
}

MuscleCommand control(unsigned arm,bool extend,bool stroke,bool carry=false){
    MuscleCommand m;
    m.arm=arm;m.explicit_control=true;m.extend=extend;m.stroke=stroke;m.carry=carry;
    m.activation=extend||stroke?1.0:(carry?.35:0.0);
    m.extension=extend?1.48:(carry?.98:.58);
    m.curvature=extend?0:(carry?1.0:3.6);
    m.stiffness=extend?.25:.05;
    m.sweep=stroke?1.0:-1.0;
    return m;
}
void command(PhysicsWorld& world,unsigned arm,bool extend,bool stroke,bool carry=false){
    if(!world.command(control(arm,extend,stroke,carry)))throw std::runtime_error("valid explicit control rejected");
}
void pair_command(PhysicsWorld& world,const std::array<unsigned,2>& arms,bool extend,bool stroke){
    for(const unsigned arm:arms)command(world,arm,extend,stroke);
}

struct Monitor {
    std::array<bool,8> selected{};
    unsigned max_selected_grips=0,max_unused_grips=0,support_frames=0;
    double max_penetration=0,max_root_angle=0,max_proximal_angle=0;
    double min_proximal_separation=std::numeric_limits<double>::infinity(),max_reach=0;
    bool plane_enabled=false;
    Vec3 plane_normal{0,1,0};
    double plane_extent=0,min_plane_clearance=std::numeric_limits<double>::infinity(),max_plane_extent_used=0;
    bool height_window_enabled=false;
    double height_window_low=0,height_window_high=0,max_height_in_window=-std::numeric_limits<double>::infinity();
    bool all_finite=true;
    explicit Monitor(std::array<unsigned,2> arms={8,8}){for(unsigned k:arms)if(k<8)selected[k]=true;}
    void plane(double slope,double extent){plane_enabled=true;plane_normal=unit({0,1,-slope});plane_extent=extent;}
    void height_window(double low,double high){height_window_enabled=true;height_window_low=low;height_window_high=high;}
    void observe(const RenderSnapshot& s){
        if(s.animals.size()!=1)throw std::runtime_error("fixture requires one animal");
        const auto& animal=s.animals[0];const auto& body=animal.body_nodes;
        unsigned active=0,inactive=0;bool supported=false;
        all_finite=all_finite&&s.diagnostics.nonfinite_count==0&&finite(animal.center);
        if(height_window_enabled&&animal.center.z>=height_window_low&&animal.center.z<=height_window_high)
            max_height_in_window=std::max(max_height_in_window,animal.center.y);
        if(plane_enabled){
            min_plane_clearance=std::min(min_plane_clearance,dot(animal.center,plane_normal));
            max_plane_extent_used=std::max({max_plane_extent_used,std::abs(animal.center.x),std::abs(animal.center.z)});
        }
        max_penetration=std::max(max_penetration,s.diagnostics.max_penetration);
        const Vec3 up=unit(sub(body[3],body[4]));
        Vec3 forward=sub(body[5],body[6]);forward=unit(sub(forward,mul(up,dot(forward,up))));
        const Vec3 right=unit(cross(up,forward));
        for(unsigned k=0;k<8;++k){
            const auto& arm=animal.arms[k];
            if(selected[k]){active+=grips(arm);supported=supported||arm.phase==2;}
            else inactive+=grips(arm);
            const Vec3 root=sub(arm.nodes[0],animal.center);
            max_root_angle=std::max(max_root_angle,angle_error(std::atan2(dot(root,right),dot(root,forward)),layout::angle(k)));
            const unsigned proximal=std::min(3u,static_cast<unsigned>(arm.nodes.size()-1));
            const Vec3 span=sub(arm.nodes[proximal],arm.nodes[0]);
            const double planar=std::hypot(dot(span,right),dot(span,forward));
            if(planar>.02*s.size_scale)
                max_proximal_angle=std::max(max_proximal_angle,angle_error(std::atan2(dot(span,right),dot(span,forward)),layout::angle(k)));
            for(const Vec3 p:arm.nodes){
                all_finite=all_finite&&finite(p);max_reach=std::max(max_reach,length(sub(p,animal.center)));
                if(plane_enabled)max_plane_extent_used=std::max({max_plane_extent_used,std::abs(p.x),std::abs(p.z)});
            }
        }
        for(unsigned a=0;a<8;++a)for(unsigned b=a+1;b<8;++b)
            for(unsigned i=1;i<=3;++i)for(unsigned j=1;j<=3;++j){
                const auto& aa=animal.arms[a];const auto& bb=animal.arms[b];
                const double radii=aa.contact_radii[i]+bb.contact_radii[j];
                if(radii>0)min_proximal_separation=std::min(min_proximal_separation,length(sub(aa.nodes[i],bb.nodes[j]))/radii);
            }
        max_selected_grips=std::max(max_selected_grips,active);max_unused_grips=std::max(max_unused_grips,inactive);
        if(supported)++support_frames;
    }
    void print(const std::string& name)const{
        std::cout<<"METRIC case="<<name<<" selected_grips_max="<<max_selected_grips<<" unused_grips_max="<<max_unused_grips
                 <<" support_frames="<<support_frames<<" max_penetration_m="<<max_penetration
                 <<" root_angle_max_deg="<<max_root_angle*180/pi<<" proximal_angle_max_deg="<<max_proximal_angle*180/pi
                 <<" proximal_separation_radius_ratio_min="<<min_proximal_separation<<" reach_max_m="<<max_reach<<"\n";
        if(plane_enabled)std::cout<<"METRIC case="<<name<<" body_plane_clearance_min_m="<<min_plane_clearance
                                 <<" plane_extent_used_m="<<max_plane_extent_used<<" plane_half_extent_m="<<plane_extent<<"\n";
    }
    void stable(Case& test,double length_scale)const{
        test.check(all_finite,"all physical snapshots remain finite");
        test.check(max_reach<3.5*length_scale,"arm motion stays bounded relative to body");
        test.check(max_unused_grips==0,"uncommanded arms never acquire suction");
        if(plane_enabled){
            test.check(min_plane_clearance>=.10*length_scale,"body center remains at least ten percent arm length above the ramp plane");
            test.check(max_plane_extent_used<plane_extent,"all arm nodes and body center stay inside the physical ramp mesh");
        }
    }
    void proximal(Case& test)const{
        test.check(max_root_angle<25*pi/180,"root ordering stays within 25 degrees of home");
        test.check(max_proximal_angle<80*pi/180,"proximal arm sweep stays within 80 degrees of home");
        test.check(min_proximal_separation>.35,"proximal sites avoid overlap beyond 65 percent of radii sum");
    }
};
RenderSnapshot advance(PhysicsWorld& world,Monitor& monitor,unsigned frames){
    RenderSnapshot s=world.snapshot();
    for(unsigned i=0;i<frames;++i){
        if(!world.step())throw std::runtime_error("PhysicsWorld::step reported invalid state");
        s=world.snapshot();monitor.observe(s);
    }
    return s;
}

void layout_scale_and_commands(Case& test){
    WorldConfig c=config();c.size_scale=1;c.gravity={0,0,0};c.floor=false;c.collisions=false;
    PhysicsWorld small(c);c.size_scale=1.5;PhysicsWorld large(c);
    const auto a=small.snapshot(),b=large.snapshot();double node_error=0,radius_error=0,layout_error=0;
    for(unsigned k=0;k<8;++k){
        const auto& aa=a.animals[0].arms[k];const auto& bb=b.animals[0].arms[k];
        test.check(angle_error(bb.home_angle,layout::angle(k))<1e-12,"home angle matches shared layout table");
        test.check(bb.model_arm==layout::model_arms[k],"model arm mapping matches shared layout table");
        const Vec3 radial=sub(bb.nodes.back(),bb.nodes.front());
        layout_error=std::max(layout_error,angle_error(std::atan2(radial.x,radial.z),layout::angle(k)));
        for(unsigned j=0;j<aa.nodes.size();++j){
            const Vec3 expected=add(b.animals[0].center,mul(sub(aa.nodes[j],a.animals[0].center),1.5));
            node_error=std::max(node_error,length(sub(bb.nodes[j],expected)));
            radius_error=std::max(radius_error,std::abs(bb.contact_radii[j]-1.5*aa.contact_radii[j]));
        }
        for(unsigned j=0;j<aa.radii.size();++j)for(unsigned axis=0;axis<2;++axis)
            radius_error=std::max(radius_error,std::abs(bb.radii[j][axis]-1.5*aa.radii[j][axis]));
        test.check(angle_error(bb.home_angle,-b.animals[0].arms[7-k].home_angle)<1e-12,"left and right home geometry is symmetric");
    }
    command(large,0,true,true);const auto after=large.snapshot();double teleport=0;
    for(unsigned k=0;k<8;++k)for(unsigned j=0;j<b.animals[0].arms[k].nodes.size();++j)
        teleport=std::max(teleport,length(sub(after.animals[0].arms[k].nodes[j],b.animals[0].arms[k].nodes[j])));
    for(unsigned j=0;j<b.animals[0].body_nodes.size();++j)
        teleport=std::max(teleport,length(sub(after.animals[0].body_nodes[j],b.animals[0].body_nodes[j])));
    test.check(node_error<1e-10&&radius_error<1e-10,"size 1.5 scales actual collision nodes and radii");
    test.check(layout_error<1e-10,"initial physical arms match symmetric home angles");
    test.check(teleport<1e-12,"command changes targets without moving physical coordinates");
    Monitor monitor({0,8});const auto moved=advance(large,monitor,1);
    const double first_motion=length(sub(moved.animals[0].arms[0].nodes.back(),b.animals[0].arms[0].nodes.back()));
    test.check(first_motion<.1*arm_length(c),"first force-driven step cannot teleport to an actuator target");
    std::cout<<"METRIC case="<<test.name<<" scale_node_error_m="<<node_error<<" scale_radius_error_m="<<radius_error
             <<" layout_error_deg="<<layout_error*180/pi<<" command_motion_m="<<teleport<<" first_step_tip_motion_m="<<first_motion<<"\n";
}

void idle_no_support(Case& test){
    const auto c=config();PhysicsWorld world(c);map(world,flat_map());Monitor monitor;
    const Vec3 start=world.snapshot().animals[0].center;const auto end=advance(world,monitor,180);
    monitor.print(test.name);monitor.stable(test,arm_length(c));
    test.check(grips(end)==0,"idle empty arms finish without static support");
    for(const auto& arm:end.animals[0].arms)test.check(arm.phase==0,"idle empty arms enter recover phase");
    std::cout<<"METRIC case="<<test.name<<" drift_x_m="<<end.animals[0].center.x-start.x
             <<" drift_z_m="<<end.animals[0].center.z-start.z<<"\n";
}

bool acquire(PhysicsWorld& world,Monitor& monitor,unsigned arm,unsigned minimum,unsigned limit=150){
    command(world,arm,true,false);
    for(unsigned frame=0;frame<limit;++frame)if(grips(advance(world,monitor,1).animals[0].arms[arm])>=minimum)return true;
    return false;
}

void release_peels_tip_first(Case& test){
    const auto c=config();PhysicsWorld world(c);map(world,flat_map());Monitor monitor({0,8});advance(world,monitor,45);
    const bool acquired=acquire(world,monitor,0,2);const auto before=world.snapshot().animals[0].arms[0];
    test.check(acquired,"at least two static suckers acquire before peel-order measurement");
    std::vector<unsigned> removed(before.attached.size(),999);command(world,0,false,false);
    bool releasing=false;unsigned post_release=0;
    for(unsigned tick=1;tick<=150;++tick){
        const auto s=advance(world,monitor,1);const auto& arm=s.animals[0].arms[0];releasing=releasing||arm.phase==3;
        for(unsigned j=0;j<before.attached.size();++j)if(before.attached[j]&&!arm.attached[j]&&removed[j]==999)removed[j]=tick;
        if(tick>24)post_release=std::max(post_release,grips(s));
    }
    unsigned violations=0,first=999,last=0,initial=grips(before);
    for(unsigned a=0;a<removed.size();++a)if(before.attached[a]){
        first=std::min(first,removed[a]);last=std::max(last,removed[a]);
        for(unsigned b=a+1;b<removed.size();++b)if(before.attached[b]&&removed[b]>removed[a])++violations;
    }
    test.check(violations==0,"distal suckers release no later than proximal suckers");
    test.check(last<=24,"all static suckers peel within 0.4 seconds");
    test.check(initial<2||releasing,"multi-sucker peel exposes releasing phase");
    test.check(post_release==0,"cooldown expiration never attaches a released arm without rising extend");
    monitor.stable(test,arm_length(c));monitor.print(test.name);
    std::cout<<"METRIC case="<<test.name<<" initially_attached="<<initial<<" first_release_tick="<<first
             <<" last_release_tick="<<last<<" order_violations="<<violations<<" post_cooldown_grips_max="<<post_release<<"\n";
}

void space_requires_new_extend(Case& test){
    const auto c=config();PhysicsWorld world(c);map(world,flat_map());Monitor monitor({0,8});advance(world,monitor,45);
    test.check(acquire(world,monitor,0,1),"static grip acquired before Space test");
    world.release_all_suckers(true);test.check(grips(world.snapshot())==0,"Space immediately releases every grip");
    unsigned held_grips=0,released_grips=0;
    for(unsigned i=0;i<30;++i)held_grips=std::max(held_grips,grips(advance(world,monitor,1)));
    world.release_all_suckers(false);
    for(unsigned i=0;i<150;++i)released_grips=std::max(released_grips,grips(advance(world,monitor,1)));
    const auto blocked=world.snapshot().animals[0].arms[0];
    test.check(held_grips==0&&released_grips==0,"held extend cannot reattach during or after Space cooldown");
    test.check(blocked.extend&&blocked.rearm_required,"held input remains extended and explicitly requires rearm");
    command(world,0,false,false);advance(world,monitor,2);
    const bool reacquired=acquire(world,monitor,0,1);
    test.check(reacquired,"a new rising extend rearms real-contact suction");
    monitor.stable(test,arm_length(c));monitor.print(test.name);
    std::cout<<"METRIC case="<<test.name<<" space_held_grips_max="<<held_grips<<" space_released_held_extend_grips_max="<<released_grips
             <<" new_cycle_acquired="<<reacquired<<"\n";
}

void external_carry_flag(Case& test){
    const auto c=config();PhysicsWorld world(c);map(world,flat_map());Monitor monitor({0,8});advance(world,monitor,45);
    command(world,0,true,true,true);advance(world,monitor,12);command(world,0,false,false,true);
    bool carry_state=true;unsigned carry_grips=0;
    for(unsigned i=0;i<90;++i){
        const auto s=advance(world,monitor,1);const auto& arm=s.animals[0].arms[0];
        carry_state=carry_state&&arm.carry&&arm.phase==4&&!arm.extend&&!arm.stroke;carry_grips=std::max(carry_grips,grips(s));
    }
    test.check(carry_state,"external carryFlag retains carry phase after both input keys release");
    test.check(carry_grips==0,"external carryFlag forbids static suction");
    command(world,0,false,false,false);const auto end=advance(world,monitor,45);
    test.check(!end.animals[0].arms[0].carry&&end.animals[0].arms[0].phase==0,"clearing external carryFlag permits empty recovery");
    monitor.stable(test,arm_length(c));monitor.print(test.name);
    std::cout<<"METRIC case="<<test.name<<" carry_state_retained="<<carry_state<<" static_grips_during_carry_max="<<carry_grips<<"\n";
}

void drive_cycles(PhysicsWorld& world,Monitor& monitor,const std::array<unsigned,2>& arms,unsigned count,
                  PhysicsWorld* passive=nullptr,Monitor* passive_monitor=nullptr){
    for(unsigned cycle=0;cycle<count;++cycle){
        for(unsigned phase=0;phase<3;++phase){
            pair_command(world,arms,phase!=2,phase==1);
            const unsigned frames=phase==0?72:(phase==1?48:45);
            for(unsigned i=0;i<frames;++i){
                advance(world,monitor,1);
                if(passive&&passive_monitor)advance(*passive,*passive_monitor,1);
            }
        }
    }
}

void flat_two_arm_cycles(Case& test){
    const auto c=config();PhysicsWorld world(c),passive(c);map(world,flat_map());map(passive,flat_map());
    Monitor monitor({0,7}),baseline;advance(world,monitor,60);advance(passive,baseline,60);
    const Vec3 start=world.snapshot().animals[0].center,base_start=passive.snapshot().animals[0].center;
    drive_cycles(world,monitor,{0,7},3,&passive,&baseline);
    const auto end=world.snapshot();const Vec3 delta=sub(end.animals[0].center,start),base_delta=sub(passive.snapshot().animals[0].center,base_start);
    const double active_progress=delta.z-base_delta.z;
    test.check(monitor.max_selected_grips>0&&monitor.support_frames>0,"selected arms use actual suction support during drive cycle");
    test.check(active_progress>.05*arm_length(c),"three two-arm cycles move forward by more than five percent of arm length beyond passive drift");
    monitor.stable(test,arm_length(c));monitor.proximal(test);monitor.print(test.name);
    test.check(baseline.max_unused_grips==0,"matched passive world never gains automatic support");
    std::cout<<"METRIC case="<<test.name<<" cycles=3 delta_x_m="<<delta.x<<" delta_y_m="<<delta.y<<" delta_z_m="<<delta.z
             <<" passive_delta_z_m="<<base_delta.z<<" active_forward_progress_m="<<active_progress
             <<" required_progress_m="<<.05*arm_length(c)<<" yaw_deg="<<yaw(end)*180/pi<<"\n";
}

void turning(Case& test,bool incline){
    const auto c=config();PhysicsWorld right(c),left(c);
    const auto triangles=incline?ramp_map(std::tan(pi/6),100*arm_length(c)):flat_map();
    map(right,triangles);map(left,triangles);
    // Measure rotation around the surface normal. World yaw would conflate
    // pitch on a steep ramp with the intended left/right turn.
    const Vec3 ahead=incline?Vec3{0,.5,std::sqrt(3.0)/2}:Vec3{0,0,1};
    const auto surface_yaw=[&](const RenderSnapshot& s){
        const auto& b=s.animals[0].body_nodes;const Vec3 forward=sub(b[5],b[6]);
        return std::atan2(forward.x,dot(forward,ahead));
    };
    Monitor mr({0,1}),ml({7,6});
    if(incline){mr.plane(std::tan(pi/6),100*arm_length(c));ml.plane(std::tan(pi/6),100*arm_length(c));}
    advance(right,mr,45);advance(left,ml,45);
    const double initial_right=surface_yaw(right.snapshot()),initial_left=surface_yaw(left.snapshot());
    const Vec3 start_right=right.snapshot().animals[0].center,start_left=left.snapshot().animals[0].center;
    drive_cycles(right,mr,{0,1},3);drive_cycles(left,ml,{7,6},3);
    const auto sr=right.snapshot(),sl=left.snapshot();
    const double yr=std::remainder(surface_yaw(sr)-initial_right,2*pi),yl=std::remainder(surface_yaw(sl)-initial_left,2*pi);
    test.check(yr*yl<0&&std::abs(yr)>.03&&std::abs(yl)>.03,"mirrored one-side cycles produce opposite physical turns exceeding 1.7 degrees");
    test.check(mr.max_selected_grips>0&&ml.max_selected_grips>0,"both turn directions use real selected-arm contacts");
    if(incline){
        test.check(sr.static_triangles==2&&sl.static_triangles==2,"ramp turning uses exact 30-degree triangle geometry");
        test.check(mr.max_penetration<.20*arm_length(c)&&ml.max_penetration<.20*arm_length(c),"ramp turn penetration remains bounded");
    }
    mr.stable(test,arm_length(c));ml.stable(test,arm_length(c));mr.proximal(test);ml.proximal(test);
    mr.print(test.name+"_right");ml.print(test.name+"_left");
    std::cout<<"METRIC case="<<test.name<<" slope_degrees="<<(incline?30:0)<<" right_pair_yaw_deg="<<yr*180/pi<<" left_pair_yaw_deg="<<yl*180/pi
             <<" right_delta_z_m="<<sr.animals[0].center.z-start_right.z<<" left_delta_z_m="<<sl.animals[0].center.z-start_left.z<<"\n";
}
void mirrored_turning(Case& test){turning(test,false);}

void ramp_travel(Case& test,bool descent){
    auto c=config();const double l=arm_length(c),slope=(descent?-1:1)*std::tan(pi/6);
    PhysicsWorld world(c);map(world,ramp_map(slope,100*l));Monitor monitor({0,7});monitor.plane(slope,100*l);advance(world,monitor,60);
    const Vec3 start=world.snapshot().animals[0].center;drive_cycles(world,monitor,{0,7},3);
    const auto end=world.snapshot();const Vec3 delta=sub(end.animals[0].center,start);
    test.check(end.static_triangles==2,"30-degree ramp is registered as exact triangle geometry");
    test.check(delta.z>.10*l,"ramp cycles make forward progress exceeding ten percent of arm length");
    test.check((descent?-delta.y:delta.y)>.05*l,"body height changes in the requested ramp direction");
    test.check(monitor.max_selected_grips>0,"ramp movement uses selected-arm suction contacts");
    test.check(monitor.max_penetration<.20*l,"ramp contact penetration remains bounded below twenty percent arm length");
    monitor.stable(test,l);monitor.proximal(test);monitor.print(test.name);
    std::cout<<"METRIC case="<<test.name<<" slope_degrees="<<(descent?-30:30)<<" delta_x_m="<<delta.x<<" delta_y_m="<<delta.y
             <<" delta_z_m="<<delta.z<<" along_ramp_m="<<(delta.z+slope*delta.y)/std::sqrt(1+slope*slope)
             <<" yaw_deg="<<yaw(end)*180/pi<<"\n";
}

void step_travel(Case& test,double fraction,bool descent){
    auto c=config();const double l=arm_length(c),height=fraction*l;
    // Keep the initial torso and its collision radii clear of the riser.
    // Only the selected forward arms can initially reach the next plateau.
    c.spawn_origin.z=-.35*l;c.spawn_height+=descent?height:0;
    PhysicsWorld world(c);map(world,step_map(height,8*l,descent));Monitor monitor({0,7});advance(world,monitor,60);
    const Vec3 start=world.snapshot().animals[0].center;drive_cycles(world,monitor,{0,7},4);
    const auto end=world.snapshot();const Vec3 delta=sub(end.animals[0].center,start);
    test.check(end.static_triangles==6,"step has two plateaus and a real vertical riser");
    test.check(end.animals[0].center.z>.15*l,"body center traverses the step edge by fifteen percent arm length");
    test.check((descent?-delta.y:delta.y)>.5*height,"body gains or loses at least half the physical step height");
    test.check(monitor.max_selected_grips>0,"step traversal uses selected-arm suction contacts");
    test.check(monitor.max_penetration<.20*l,"step penetration stays below twenty percent arm length");
    monitor.stable(test,l);monitor.proximal(test);monitor.print(test.name);
    std::cout<<"METRIC case="<<test.name<<" step_arm_fraction="<<fraction<<" step_height_m="<<height
             <<" start_z_m="<<start.z<<" end_z_m="<<end.animals[0].center.z<<" delta_x_m="<<delta.x
             <<" delta_y_m="<<delta.y<<" delta_z_m="<<delta.z<<"\n";
}

void roughness_traverse(Case& test,double fraction){
    auto c=config();const double l=arm_length(c),height=fraction*l,rise=.9*l,plateau=.7*l,end_z=2*rise+plateau;
    c.spawn_origin.z=-.35*l;
    PhysicsWorld world(c);map(world,roughness_map(height,l));Monitor monitor({0,7});monitor.plane(0,20*l);
    advance(world,monitor,60);const Vec3 start=world.snapshot().animals[0].center;
    monitor.height_window(rise,rise+plateau);
    unsigned cycles=0;
    while(cycles<24&&world.snapshot().animals[0].center.z<end_z+.15*l){
        drive_cycles(world,monitor,{0,7},1);++cycles;
    }
    const auto end=world.snapshot();const Vec3 delta=sub(end.animals[0].center,start);
    const double peak_gain=monitor.max_height_in_window-start.y;
    const double recovered_height=monitor.max_height_in_window-end.animals[0].center.y;
    test.check(end.static_triangles==10,"roughness has two slopes, a plateau and two base flats in real triangles");
    test.check(end.animals[0].center.z>end_z+.15*l,"body center traverses both sides and the plateau of the complete bump");
    test.check(std::isfinite(peak_gain)&&peak_gain>.5*height,"body gains at least half bump height while its center is over the plateau");
    test.check(std::isfinite(recovered_height)&&recovered_height>.4*height,"body loses gained height after descending the bump");
    test.check(std::abs(end.animals[0].center.y-start.y)<.35*height+.03*l,"body returns toward its original base height after roughness");
    test.check(monitor.max_selected_grips>0&&monitor.support_frames>0,"roughness traversal uses real selected-arm suction support");
    test.check(monitor.max_penetration<.10*l,"roughness penetration remains below ten percent arm length");
    monitor.stable(test,l);monitor.proximal(test);monitor.print(test.name);
    std::cout<<"METRIC case="<<test.name<<" bump_arm_fraction="<<fraction<<" bump_height_m="<<height
             <<" side_run_m="<<rise<<" side_degrees="<<std::atan(height/rise)*180/pi<<" plateau_m="<<plateau
             <<" cycles="<<cycles<<" cycle_limit=24 start_z_m="<<start.z<<" end_z_m="<<end.animals[0].center.z
             <<" required_end_z_m="<<end_z+.15*l<<" delta_z_m="<<delta.z<<" plateau_height_gain_m="<<peak_gain
             <<" post_bump_height_drop_m="<<recovered_height<<" final_height_delta_m="<<delta.y<<"\n";
}

void passive_ramp_slip(Case& test){
    const auto c=config();const double l=arm_length(c),slope=std::tan(pi/6);
    PhysicsWorld world(c);map(world,ramp_map(slope,100*l));Monitor monitor;monitor.plane(slope,100*l);advance(world,monitor,45);
    const Vec3 start=world.snapshot().animals[0].center;const auto end=advance(world,monitor,180);
    const Vec3 delta=sub(end.animals[0].center,start);const double downhill=-(delta.z+slope*delta.y)/std::sqrt(1+slope*slope);
    test.check(monitor.max_unused_grips==0,"passive incline has no automatic suction support");
    test.check(downhill>.02*l,"idle body can slip downhill instead of receiving hidden support");
    monitor.stable(test,l);monitor.print(test.name);
    std::cout<<"METRIC case="<<test.name<<" passive_seconds=3 downhill_slip_m="<<downhill<<" delta_y_m="<<delta.y<<" delta_z_m="<<delta.z<<"\n";
}
} // namespace

int main(int argc,char** argv){
    std::cout<<std::setprecision(8);
    const std::string mode=argc>1?argv[1]:"all";
    const std::array<std::string,16> modes{{"all","flat","contracts","grip","cycle","terrain","ramp","rampturn","step10","step20","roughness","rough10","rough20","turn","slip","idle"}};
    if(std::find(modes.begin(),modes.end(),mode)==modes.end()){
        std::cerr<<"usage: locomotion_tests [all|flat|contracts|grip|cycle|terrain|ramp|rampturn|step10|step20|roughness|rough10|rough20|turn|slip|idle]\n";return 2;
    }
    unsigned passed=0,failed=0;
    auto run=[&](const std::string& name,auto test){
        Case result{name};
        try{test(result);}catch(const std::exception& error){result.passed=false;std::cout<<"CASE_EXCEPTION case="<<name<<" message=\""<<error.what()<<"\"\n";}
        std::cout<<"CASE_"<<(result.passed?"PASS":"FAIL")<<" case="<<name<<"\n";
        if(result.passed)++passed;else ++failed;
    };
    if(mode=="all"||mode=="flat"||mode=="contracts")run("layout_scale_command",layout_scale_and_commands);
    if(mode=="all"||mode=="flat"||mode=="idle")run("idle_no_support",idle_no_support);
    if(mode=="all"||mode=="flat"||mode=="grip"){
        run("tip_first_static_peel",release_peels_tip_first);
        run("space_extend_rearm",space_requires_new_extend);
        run("external_carry_flag",external_carry_flag);
    }
    if(mode=="all"||mode=="flat"||mode=="cycle")run("flat_two_arm_cycles",flat_two_arm_cycles);
    if(mode=="all"||mode=="flat"||mode=="turn")run("mirrored_turning",mirrored_turning);
    if(mode=="all"||mode=="terrain"||mode=="ramp"){
        run("ramp_30_up",[](Case& t){ramp_travel(t,false);});
        run("ramp_30_down",[](Case& t){ramp_travel(t,true);});
    }
    if(mode=="all"||mode=="terrain"||mode=="ramp"||mode=="rampturn")run("ramp_30_turn",[](Case& t){turning(t,true);});
    if(mode=="all"||mode=="terrain"||mode=="step10"){
        run("step_10_up",[](Case& t){step_travel(t,.10,false);});
        run("step_10_down",[](Case& t){step_travel(t,.10,true);});
    }
    if(mode=="all"||mode=="terrain"||mode=="step20"){
        run("step_20_up",[](Case& t){step_travel(t,.20,false);});
        run("step_20_down",[](Case& t){step_travel(t,.20,true);});
    }
    if(mode=="all"||mode=="terrain"||mode=="roughness"||mode=="rough10")run("rough_10",[](Case& t){roughness_traverse(t,.10);});
    if(mode=="all"||mode=="terrain"||mode=="roughness"||mode=="rough20")run("rough_20",[](Case& t){roughness_traverse(t,.20);});
    if(mode=="all"||mode=="terrain"||mode=="slip")run("passive_ramp_slip",passive_ramp_slip);
    std::cout<<"LOCOMOTION_SUMMARY mode="<<mode<<" passed="<<passed<<" failed="<<failed<<"\n";
    return failed?1:0;
}
