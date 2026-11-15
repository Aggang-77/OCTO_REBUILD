#pragma once
#include "octo/world.hpp"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <limits>
#include <new>
#include <vector>

namespace octo::geometry {

struct SurfaceHit {
    bool hit=false;
    Vec3 point{}, normal{0,1,0};
    double distance=0;
    double segment_t=0;
    unsigned triangle=0; // Original input triplet, including skipped degenerates.
};

// Immutable between assign/clear calls; concurrent const queries are safe.
// Vertices are an unindexed triangle list in world metres. Geometry is two-sided.
class StaticGeometry {
public:
    // Invalid input leaves the previous map intact. Empty/all-degenerate input
    // succeeds and clears the map. Nonfinite vertices are invalid even in a
    // degenerate triangle. Finite coordinates whose edge arithmetic overflows
    // are also rejected instead of introducing nonfinite BVH bounds/normals.
    bool assign(const std::vector<Vec3>& vertices) {
        if(vertices.size()>1000000 || vertices.size()%3!=0) return false;
        for(const Vec3 p:vertices) if(!finite(p)) return false;
        try {
            StaticGeometry next;
            next.triangles_.reserve(vertices.size()/3);
            for(std::size_t i=0;i<vertices.size();i+=3) {
                const Vec3 a=vertices[i], b=vertices[i+1], c=vertices[i+2];
                const Vec3 ab=sub(b,a), ac=sub(c,a), bc=sub(c,b);
                if(!finite(ab)||!finite(ac)||!finite(bc)) return false;
                const double scale=std::max(max_abs(ab),max_abs(ac));
                if(scale==0) continue;
                const Vec3 cross_scaled=cross(divide(ab,scale),divide(ac,scale));
                const double length=norm(cross_scaled);
                if(length==0) continue;
                Triangle tri;
                tri.a=a; tri.b=b; tri.c=c;
                tri.normal=divide(cross_scaled,length);
                tri.source=static_cast<unsigned>(i/3);
                tri.box.include(a); tri.box.include(b); tri.box.include(c);
                next.triangles_.push_back(tri);
            }
            if(!next.triangles_.empty()) {
                next.nodes_.reserve(next.triangles_.size()/2+1);
                next.build(0,static_cast<unsigned>(next.triangles_.size()));
            }
            triangles_.swap(next.triangles_);
            nodes_.swap(next.nodes_);
            return true;
        } catch(const std::bad_alloc&) {
            return false;
        }
    }

    void clear() { triangles_.clear(); nodes_.clear(); }
    std::size_t triangle_count() const { return triangles_.size(); }

    // The closest surface point within max_distance (inclusive). The normal
    // points from the surface toward point; on-surface it follows triangle winding.
    SurfaceHit closest(Vec3 point,double max_distance) const {
        if(!finite(point)||!valid_distance(max_distance)) return {};
        return nearest(max_distance,point,
            [&](const Box& box){ return point_box_distance2(point,box); },
            [&](const Triangle& tri){
                Candidate c;
                c.point=triangle_point(point,tri);
                c.query=point;
                c.distance2=length2(sub(point,c.point));
                return c;
            });
    }

    // Exact segment/triangle distance: endpoints, segment-plane intersection,
    // and all three segment/edge pairs. segment_t identifies the closest point
    // on a--b; point is the corresponding closest point on the triangle.
    SurfaceHit closest_segment(Vec3 a,Vec3 b,double max_distance) const {
        if(!finite(a)||!finite(b)||!finite(sub(b,a))||!valid_distance(max_distance)) return {};
        return nearest(max_distance,a,
            [&](const Box& box){ return segment_box_distance2(a,b,box); },
            [&](const Triangle& tri){ return segment_triangle(a,b,tri); });
    }

    // direction need not be normalized. distance and max_distance are metres,
    // and normal faces the ray origin. Rays include both endpoints and t=0.
    // Repeated rays across a suction disk can test real footprint coverage.
    SurfaceHit ray(Vec3 from,Vec3 direction,double max_distance) const {
        SurfaceHit best;
        if(nodes_.empty()||!finite(from)||!finite(direction)||!valid_distance(max_distance)) return best;
        const double direction_length=norm(direction);
        if(direction_length==0||!std::isfinite(direction_length)) return best;
        direction=divide(direction,direction_length);
        double best_distance=max_distance;
        std::array<Pending,64> stack{};
        unsigned count=0;
        double root_distance=0;
        if(!ray_box(from,direction,nodes_[0].box,best_distance,root_distance)) return best;
        stack[count++]={0,root_distance};
        while(count) {
            const Pending pending=stack[--count];
            if(pending.distance>best_distance) continue;
            const Node& node=nodes_[pending.index];
            if(node.count) {
                for(unsigned i=node.first;i<node.first+node.count;++i) {
                    const Triangle& tri=triangles_[i];
                    const double denominator=dot(tri.normal,direction);
                    double distance=0;
                    if(denominator==0) {
                        if(dot(sub(from,tri.a),tri.normal)!=0) continue;
                        // A coplanar ray clips against the triangle's three
                        // inward halfspaces, including an origin on its face.
                        double exit=best_distance;
                        const std::array<Vec3,3> vertices{tri.a,tri.b,tri.c};
                        bool misses=false;
                        for(unsigned edge=0;edge<3;++edge) {
                            const Vec3 inward=cross(tri.normal,sub(vertices[(edge+1)%3],vertices[edge]));
                            const double side=dot(inward,sub(from,vertices[edge]));
                            const double rate=dot(inward,direction);
                            if(rate>0) distance=std::max(distance,-side/rate);
                            else if(rate<0) exit=std::min(exit,-side/rate);
                            else if(side<0) { misses=true; break; }
                        }
                        if(misses||distance>exit) continue;
                    } else distance=dot(sub(tri.a,from),tri.normal)/denominator;
                    if(distance<0||distance>best_distance||!std::isfinite(distance)) continue;
                    const Vec3 point=add(from,mul(direction,distance));
                    if(!inside(point,tri,true)) continue;
                    if(best.hit&&distance==best_distance&&tri.source>=best.triangle) continue;
                    best.hit=true; best.point=point; best.distance=distance;
                    best.normal=denominator>0?mul(tri.normal,-1):tri.normal;
                    best.triangle=tri.source;
                    best_distance=distance;
                }
            } else {
                double left_distance=0,right_distance=0;
                const unsigned left=pending.index+1, right=node.right;
                const bool hit_left=ray_box(from,direction,nodes_[left].box,best_distance,left_distance);
                const bool hit_right=ray_box(from,direction,nodes_[right].box,best_distance,right_distance);
                push_children(stack,count,left,left_distance,hit_left,right,right_distance,hit_right);
            }
        }
        return best;
    }

private:
    static constexpr double infinity=std::numeric_limits<double>::infinity();
    static Vec3 add(Vec3 a,Vec3 b) { return {a.x+b.x,a.y+b.y,a.z+b.z}; }
    static Vec3 sub(Vec3 a,Vec3 b) { return {a.x-b.x,a.y-b.y,a.z-b.z}; }
    static Vec3 mul(Vec3 a,double b) { return {a.x*b,a.y*b,a.z*b}; }
    static Vec3 divide(Vec3 a,double b) { return {a.x/b,a.y/b,a.z/b}; }
    static double dot(Vec3 a,Vec3 b) { return a.x*b.x+a.y*b.y+a.z*b.z; }
    static Vec3 cross(Vec3 a,Vec3 b) { return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x}; }
    static double length2(Vec3 a) { return dot(a,a); }
    static double norm(Vec3 a) { return std::hypot(a.x,a.y,a.z); }
    static double max_abs(Vec3 a) { return std::max({std::abs(a.x),std::abs(a.y),std::abs(a.z)}); }
    static bool finite(Vec3 p) { return std::isfinite(p.x)&&std::isfinite(p.y)&&std::isfinite(p.z); }
    static bool valid_distance(double d) { return d>=0&&!std::isnan(d); }
    static double component(Vec3 p,unsigned axis) { return axis==0?p.x:(axis==1?p.y:p.z); }

    struct Box {
        Vec3 lower{infinity,infinity,infinity}, upper{-infinity,-infinity,-infinity};
        void include(Vec3 p) {
            lower={std::min(lower.x,p.x),std::min(lower.y,p.y),std::min(lower.z,p.z)};
            upper={std::max(upper.x,p.x),std::max(upper.y,p.y),std::max(upper.z,p.z)};
        }
        void include(const Box& box) { include(box.lower); include(box.upper); }
        double center(unsigned axis) const { return component(lower,axis)*.5+component(upper,axis)*.5; }
    };
    struct Triangle {
        Vec3 a{},b{},c{},normal{};
        Box box;
        unsigned source=0;
    };
    struct Node {
        Box box;
        unsigned first=0,count=0,right=0;
    };
    struct Candidate {
        Vec3 point{},query{};
        double distance2=infinity, segment_t=0;
    };
    struct Pending { unsigned index=0; double distance=0; };
    std::vector<Triangle> triangles_;
    std::vector<Node> nodes_;

    unsigned build(unsigned first,unsigned count) {
        const unsigned index=static_cast<unsigned>(nodes_.size());
        nodes_.push_back({});
        Box box,centers;
        for(unsigned i=first;i<first+count;++i) {
            const Box& b=triangles_[i].box;
            box.include(b);
            centers.include(Vec3{b.center(0),b.center(1),b.center(2)});
        }
        nodes_[index].box=box;
        if(count<=8) {
            nodes_[index].first=first;
            nodes_[index].count=count;
            return index;
        }
        const Vec3 extent=sub(centers.upper,centers.lower);
        const unsigned axis=extent.x>=extent.y&&extent.x>=extent.z?0:(extent.y>=extent.z?1:2);
        const unsigned middle=first+count/2;
        std::nth_element(triangles_.begin()+first,triangles_.begin()+middle,triangles_.begin()+first+count,
            [axis](const Triangle& a,const Triangle& b){
                const double ca=a.box.center(axis), cb=b.box.center(axis);
                return ca==cb?a.source<b.source:ca<cb;
            });
        build(first,middle-first); // Left child immediately follows its parent.
        const unsigned right=build(middle,first+count-middle);
        nodes_[index].right=right;
        return index;
    }

    static double point_box_distance2(Vec3 p,const Box& box) {
        const double x=std::max({box.lower.x-p.x,0.0,p.x-box.upper.x});
        const double y=std::max({box.lower.y-p.y,0.0,p.y-box.upper.y});
        const double z=std::max({box.lower.z-p.z,0.0,p.z-box.upper.z});
        return x*x+y*y+z*z;
    }

    // Distance to an AABB is a convex piecewise quadratic along a segment.
    // Split at its six slab crossings and minimize each quadratic exactly.
    static double segment_box_distance2(Vec3 a,Vec3 b,const Box& box) {
        const Vec3 d=sub(b,a);
        std::array<double,8> cuts{};
        unsigned count=2;
        cuts[0]=0; cuts[1]=1;
        for(unsigned axis=0;axis<3;++axis) {
            const double delta=component(d,axis);
            if(delta==0) continue;
            for(const double bound:{component(box.lower,axis),component(box.upper,axis)}) {
                const double t=(bound-component(a,axis))/delta;
                if(t>0&&t<1) cuts[count++]=t;
            }
        }
        std::sort(cuts.begin(),cuts.begin()+count);
        double best=std::min(point_box_distance2(a,box),point_box_distance2(b,box));
        for(unsigned i=1;i<count;++i) {
            const double lo=cuts[i-1],hi=cuts[i],mid=(lo+hi)*.5;
            double quadratic=0,linear=0;
            for(unsigned axis=0;axis<3;++axis) {
                const double start=component(a,axis), delta=component(d,axis), value=start+delta*mid;
                const double lower=component(box.lower,axis),upper=component(box.upper,axis);
                if(value<lower||value>upper) {
                    const double offset=start-(value<lower?lower:upper);
                    quadratic+=delta*delta;
                    linear+=delta*offset;
                }
            }
            if(quadratic==0) {
                best=std::min(best,point_box_distance2(add(a,mul(d,mid)),box));
            } else {
                const double t=std::clamp(-linear/quadratic,lo,hi);
                best=std::min(best,point_box_distance2(add(a,mul(d,t)),box));
            }
            if(best==0) return 0;
        }
        return best;
    }

    static bool ray_box(Vec3 from,Vec3 direction,const Box& box,double maximum,double& entry) {
        double lo=0,hi=maximum;
        for(unsigned axis=0;axis<3;++axis) {
            const double start=component(from,axis),delta=component(direction,axis);
            const double lower=component(box.lower,axis),upper=component(box.upper,axis);
            if(delta==0) {
                if(start<lower||start>upper) return false;
            } else {
                double a=(lower-start)/delta,b=(upper-start)/delta;
                if(a>b) std::swap(a,b);
                lo=std::max(lo,a); hi=std::min(hi,b);
                if(lo>hi) return false;
            }
        }
        entry=lo;
        return true;
    }

    static Vec3 edge_point(Vec3 p,Vec3 a,Vec3 b) {
        const Vec3 d=sub(b,a);
        const double denominator=length2(d);
        const double t=denominator>0?std::clamp(dot(sub(p,a),d)/denominator,0.0,1.0):0;
        return add(a,mul(d,t));
    }

    static bool inside(Vec3 point,const Triangle& tri,bool roundoff_tolerance) {
        const std::array<Vec3,3> vertices{tri.a,tri.b,tri.c};
        for(unsigned i=0;i<3;++i) {
            const Vec3 inward=cross(tri.normal,sub(vertices[(i+1)%3],vertices[i]));
            const Vec3 delta=sub(point,vertices[i]);
            const double side=dot(inward,delta);
            const double error=roundoff_tolerance?32*std::numeric_limits<double>::epsilon()*
                (std::abs(inward.x*delta.x)+std::abs(inward.y*delta.y)+std::abs(inward.z*delta.z)):0;
            if(side < -error) return false;
        }
        return true;
    }

    static Vec3 triangle_point(Vec3 point,const Triangle& tri) {
        const Vec3 projection=sub(point,mul(tri.normal,dot(sub(point,tri.a),tri.normal)));
        if(inside(projection,tri,false)) return projection;
        Vec3 best=edge_point(point,tri.a,tri.b);
        double best_distance=length2(sub(point,best));
        for(const Vec3 next:{edge_point(point,tri.b,tri.c),edge_point(point,tri.c,tri.a)}) {
            const double distance=length2(sub(point,next));
            if(distance<best_distance) { best=next; best_distance=distance; }
        }
        return best;
    }

    static Candidate segment_edge(Vec3 a,Vec3 b,Vec3 c,Vec3 d) {
        const Vec3 u=sub(b,a),v=sub(d,c),r=sub(a,c);
        const double aa=length2(u),ee=length2(v),f=dot(v,r);
        double s=0,t=0;
        if(aa==0) { t=ee>0?std::clamp(f/ee,0.0,1.0):0; }
        else {
            const double cc=dot(u,r);
            if(ee==0) s=std::clamp(-cc/aa,0.0,1.0);
            else {
                const double bb=dot(u,v),denominator=aa*ee-bb*bb;
                if(denominator>0) s=std::clamp((bb*f-cc*ee)/denominator,0.0,1.0);
                t=(bb*s+f)/ee;
                if(t<0) { t=0; s=std::clamp(-cc/aa,0.0,1.0); }
                else if(t>1) { t=1; s=std::clamp((bb-cc)/aa,0.0,1.0); }
            }
        }
        Candidate out;
        out.query=add(a,mul(u,s)); out.point=add(c,mul(v,t)); out.segment_t=s;
        out.distance2=length2(sub(out.query,out.point));
        return out;
    }

    static Candidate segment_triangle(Vec3 a,Vec3 b,const Triangle& tri) {
        const Vec3 direction=sub(b,a);
        const double denominator=dot(direction,tri.normal);
        if(denominator!=0) {
            const double t=dot(sub(tri.a,a),tri.normal)/denominator;
            if(t>=0&&t<=1) {
                const Vec3 point=add(a,mul(direction,t));
                if(inside(point,tri,true)) return {point,point,0,t};
            }
        }
        Candidate best;
        best.point=triangle_point(a,tri); best.query=a;
        best.distance2=length2(sub(a,best.point));
        const Vec3 point_b=triangle_point(b,tri);
        const double distance_b=length2(sub(b,point_b));
        if(distance_b<best.distance2) best={point_b,b,distance_b,1};
        for(const Candidate next:{segment_edge(a,b,tri.a,tri.b),segment_edge(a,b,tri.b,tri.c),segment_edge(a,b,tri.c,tri.a)})
            if(next.distance2<best.distance2) best=next;
        return best;
    }

    static void push_children(std::array<Pending,64>& stack,unsigned& count,
                              unsigned left,double dl,bool has_left,unsigned right,double dr,bool has_right) {
        // Median splitting bounds tree depth below 20 for the accepted input
        // size. A 64-entry local stack never allocates during physics queries.
        if(has_left&&has_right) {
            if(dl<dr) { stack[count++]={right,dr}; stack[count++]={left,dl}; }
            else { stack[count++]={left,dl}; stack[count++]={right,dr}; }
        } else if(has_left) stack[count++]={left,dl};
        else if(has_right) stack[count++]={right,dr};
    }

    template<class BoundDistance,class Evaluate>
    SurfaceHit nearest(double max_distance,Vec3 normal_reference,BoundDistance bound_distance,Evaluate evaluate) const {
        SurfaceHit best;
        if(nodes_.empty()) return best;
        double best_distance2=max_distance*max_distance;
        std::array<Pending,64> stack{};
        unsigned count=0;
        const double root_distance=bound_distance(nodes_[0].box);
        if(root_distance>best_distance2) return best;
        stack[count++]={0,root_distance};
        while(count) {
            const Pending pending=stack[--count];
            if(pending.distance>best_distance2) continue;
            const Node& node=nodes_[pending.index];
            if(node.count) {
                for(unsigned i=node.first;i<node.first+node.count;++i) {
                    const Triangle& tri=triangles_[i];
                    if(bound_distance(tri.box)>best_distance2) continue;
                    const Candidate candidate=evaluate(tri);
                    if(!std::isfinite(candidate.distance2)||candidate.distance2>best_distance2) continue;
                    if(best.hit&&candidate.distance2==best_distance2&&tri.source>=best.triangle) continue;
                    best_distance2=candidate.distance2;
                    best.hit=true; best.point=candidate.point;
                    best.distance=std::sqrt(candidate.distance2);
                    best.segment_t=candidate.segment_t; best.triangle=tri.source;
                    if(best.distance>0) best.normal=divide(sub(candidate.query,candidate.point),best.distance);
                    else {
                        best.normal=tri.normal;
                        // At zero distance either side is valid. The query
                        // endpoint determines the side for crossing segments.
                        if(dot(sub(normal_reference,tri.a),best.normal)<0) best.normal=mul(best.normal,-1);
                    }
                }
            } else {
                const unsigned left=pending.index+1,right=node.right;
                const double dl=bound_distance(nodes_[left].box),dr=bound_distance(nodes_[right].box);
                push_children(stack,count,left,dl,dl<=best_distance2,right,dr,dr<=best_distance2);
            }
        }
        return best;
    }
};

} // namespace octo::geometry
