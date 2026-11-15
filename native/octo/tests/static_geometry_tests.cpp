#include "octo/static_geometry.hpp"
#include <cmath>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <vector>

using octo::Vec3;
using octo::geometry::StaticGeometry;

static void check(bool condition,const char* message) {
    if(!condition) throw std::runtime_error(message);
}
static bool near(double a,double b,double tolerance=1e-10) { return std::abs(a-b)<=tolerance; }
static void point_near(Vec3 a,Vec3 b,const char* message) {
    check(near(a.x,b.x)&&near(a.y,b.y)&&near(a.z,b.z),message);
}
static void quad(std::vector<Vec3>& out,Vec3 a,Vec3 b,Vec3 c,Vec3 d) {
    out.insert(out.end(),{a,b,c,a,c,d});
}

static void slope_and_rays() {
    StaticGeometry geometry;
    const double slope=std::tan(std::acos(-1.0)/6);
    std::vector<Vec3> map;
    quad(map,{-4,-4*slope,-4},{-4,-4*slope,4},{4,4*slope,4},{4,4*slope,-4});
    check(geometry.assign(map)&&geometry.triangle_count()==2,"assign 30 degree slope");
    const auto contact=geometry.closest({0,1,0},1);
    check(contact.hit&&near(contact.distance,std::sqrt(3.0)/2),"sphere distance to slope");
    point_near(contact.point,{std::sqrt(3.0)/4,.25,0},"sphere projects onto sloped face");
    point_near(contact.normal,{-.5,std::sqrt(3.0)/2,0},"sloped support normal");
    const auto below=geometry.closest({0,-1,0},1);
    point_near(below.normal,{.5,-std::sqrt(3.0)/2,0},"sphere query is two-sided");
    const auto down=geometry.ray({1,3,.4},{0,-7,0},4);
    check(down.hit&&near(down.distance,3-slope),"non-unit downward ray uses metre distance");
    point_near(down.point,{1,slope,.4},"downward ray lands on slope");
    check(!geometry.ray({1,3,.4},{0,-1,0},3-slope-.001).hit,"ray maximum clips support");
    const auto up=geometry.ray({1,-2,.4},{0,2,0},4);
    check(up.hit&&up.normal.y<0,"ray normal faces origin on back side");
    check(!geometry.ray({5,3,0},{0,-1,0},10).hit,"support ray misses outside map");

    // A suction footprint at an edge must reveal the unsupported samples.
    unsigned supported=0;
    for(const double x:{3.7,3.9,4.1,4.3}) supported+=geometry.ray({x,4,0},{0,-1,0},5).hit?1:0;
    check(supported==2,"surface-edge footprint distinguishes supported samples");
}

static void exact_segment_features() {
    StaticGeometry geometry;
    check(geometry.assign({{0,0,0},{2,0,0},{0,0,2}}),"assign single triangle");
    const auto crossing=geometry.closest_segment({.5,1,.5},{.5,-1,.5},0);
    check(crossing.hit&&near(crossing.distance,0)&&near(crossing.segment_t,.5),"segment face crossing");
    point_near(crossing.point,{.5,0,.5},"segment crossing point");
    point_near(crossing.normal,{0,1,0},"crossing normal faces first segment endpoint");
    const auto edge=geometry.closest_segment({.5,-1,-.2},{.5,1,-.2},.25);
    check(edge.hit&&near(edge.distance,.2)&&near(edge.segment_t,.5),"interior segment to edge minimum");
    point_near(edge.point,{.5,0,0},"segment closest triangle edge point");
    point_near(edge.normal,{0,0,-1},"segment edge normal");
    const auto parallel=geometry.closest_segment({-1,.25,1},{2,.25,1},.25);
    check(parallel.hit&&near(parallel.distance,.25)&&parallel.segment_t>0&&parallel.segment_t<1,
          "parallel segment crosses face with both endpoint projections outside");
    const auto coplanar=geometry.closest_segment({-1,0,1},{2,0,1},0);
    check(coplanar.hit&&near(coplanar.distance,0),"coplanar segment crosses triangle edges");
    const auto point=geometry.closest_segment({.5,.5,.5},{.5,.5,.5},.5);
    check(point.hit&&near(point.distance,.5)&&near(point.segment_t,0),"zero-length segment is a point");
    const auto vertex=geometry.closest({-.3,.4,-.4},1);
    check(vertex.hit&&near(vertex.distance,std::sqrt(.41)),"sphere closest vertex feature");
    point_near(vertex.point,{0,0,0},"sphere vertex point");
    check(!geometry.closest_segment({.5,-1,-.2},{.5,1,-.2},.199).hit,"capsule range excludes edge");
    const auto tangent=geometry.ray({-1,0,1},{3,0,0},2);
    check(tangent.hit&&near(tangent.distance,1),"coplanar ray clips triangle halfspaces");
    check(geometry.ray({.5,0,.5},{0,1,0},0).hit,"ray includes origin on surface");
}

static void step_and_corner() {
    StaticGeometry geometry;
    std::vector<Vec3> map;
    quad(map,{-2,0,-2},{-2,0,2},{0,0,2},{0,0,-2});
    quad(map,{0,0,-2},{0,0,2},{0,1,2},{0,1,-2});
    quad(map,{0,1,-2},{0,1,2},{2,1,2},{2,1,-2});
    check(geometry.assign(map),"assign vertical step");
    const auto wall=geometry.closest({-.2,.5,0},.3);
    check(wall.hit&&near(wall.distance,.2),"sphere collides with vertical step");
    point_near(wall.normal,{-1,0,0},"step wall normal");
    const auto corner=geometry.closest({-.1,1.1,0},.2);
    check(corner.hit&&near(corner.distance,std::sqrt(.02)),"sphere contacts convex step corner");
    point_near(corner.point,{0,1,0},"step corner point");
    const auto lower=geometry.ray({-.5,2,0},{0,-1,0},3);
    const auto upper=geometry.ray({.5,2,0},{0,-1,0},3);
    check(lower.hit&&upper.hit&&near(lower.point.y,0)&&near(upper.point.y,1),"rays retain both step heights");
}

static void validation_and_replacement() {
    StaticGeometry geometry;
    check(geometry.assign({{0,0,0},{0,0,0},{0,0,0},{0,0,0},{2,0,0},{0,0,2}}),"skip degenerates");
    check(geometry.triangle_count()==1&&geometry.closest({.5,.1,.5},1).triangle==1,
          "triangle IDs retain original triplet indices");
    check(!geometry.assign({{1,2,3}})&&geometry.triangle_count()==1,"malformed assign preserves map");
    const double nan=std::numeric_limits<double>::quiet_NaN();
    const double inf=std::numeric_limits<double>::infinity();
    check(!geometry.assign({{nan,0,0},{0,0,0},{0,0,0}})&&geometry.triangle_count()==1,"NaN assign preserves map");
    check(!geometry.assign({{0,0,0},{inf,0,0},{0,0,0}})&&geometry.triangle_count()==1,"infinite assign preserves map");
    check(!geometry.assign(std::vector<Vec3>(1000002))&&geometry.triangle_count()==1,"oversize assign preserves map");
    check(!geometry.closest({nan,0,0},1).hit&&!geometry.closest({0,0,0},-1).hit,"invalid sphere query rejected");
    check(!geometry.closest_segment({0,0,0},{inf,0,0},1).hit,"invalid segment query rejected");
    check(!geometry.ray({0,1,0},{0,0,0},1).hit&&!geometry.ray({0,1,0},{0,-1,0},nan).hit,"invalid ray rejected");
    check(geometry.closest({.5,.1,.5},inf).hit,"unbounded closest query");
    check(geometry.assign({})&&geometry.triangle_count()==0,"empty assign replaces map");
    check(!geometry.closest({0,0,0},1).hit&&!geometry.ray({0,1,0},{0,-1,0},2).hit,"empty geometry misses");
    check(geometry.assign({{0,0,0},{1,0,0},{0,0,1}}),"replacement after clear");
    geometry.clear();
    check(geometry.triangle_count()==0&&!geometry.closest_segment({0,1,0},{0,-1,0},1).hit,"clear removes segment contacts");
}

static void large_bvh() {
    StaticGeometry geometry;
    constexpr unsigned cells=224;
    std::vector<Vec3> map;
    map.reserve(cells*cells*6);
    for(unsigned z=0;z<cells;++z) for(unsigned x=0;x<cells;++x) {
        const double a=x*.5,b=z*.5;
        quad(map,{a,0,b},{a,0,b+.5},{a+.5,0,b+.5},{a+.5,0,b});
    }
    check(geometry.assign(map)&&geometry.triangle_count()==100352,"build 100k triangle BVH");
    for(unsigned i=0;i<1000;++i) {
        const unsigned ix=(i*73)%cells,iz=(i*127)%cells;
        const double x=ix*.5+.13,z=iz*.5+.21;
        const auto sphere=geometry.closest({x,.125,z},.125);
        const auto ray=geometry.ray({x,2,z},{0,-1,0},2);
        check(sphere.hit&&near(sphere.distance,.125)&&ray.hit&&near(ray.distance,2),"localized BVH sphere/ray lookup");
        check(sphere.triangle/2==iz*cells+ix&&ray.triangle/2==iz*cells+ix,"BVH retains correct map triangle IDs");
        check(!geometry.closest({x,.125,z},.124).hit,"BVH rejects radius below map distance");
        if(i%10==0) {
            const auto segment=geometry.closest_segment({x,.125,z},{x+.11,.125,z+.07},.125);
            check(segment.hit&&near(segment.distance,.125),"localized BVH segment lookup");
        }
    }
    check(!geometry.ray({-1,2,-1},{0,-1,0},3).hit,"BVH outside support miss");
}

static void bvh_matches_exhaustive_queries() {
    // Compare the hierarchy with separately registered triangles. This catches
    // pruning errors on oblique segment/box configurations and nonflat maps.
    unsigned state=123456789;
    auto random=[&](){ state=1664525*state+1013904223; return (state>>8)*(8.0/16777216.0)-4; };
    std::vector<Vec3> map;
    std::vector<StaticGeometry> triangles(128);
    for(unsigned i=0;i<triangles.size();++i) {
        const Vec3 a{random(),random(),random()};
        const Vec3 b{a.x+random()*.4,a.y+random()*.4,a.z+random()*.4};
        const Vec3 c{a.x+random()*.4,a.y+random()*.4,a.z+random()*.4};
        map.insert(map.end(),{a,b,c});
        check(triangles[i].assign({a,b,c}),"assign exhaustive triangle");
    }
    StaticGeometry geometry;
    check(geometry.assign(map),"assign nonflat BVH map");
    for(unsigned query=0;query<80;++query) {
        const Vec3 a{random(),random(),random()},b{random(),random(),random()};
        const auto sphere=geometry.closest(a,4);
        const auto segment=geometry.closest_segment(a,b,4);
        const auto ray=geometry.ray(a,{b.x-a.x,b.y-a.y,b.z-a.z},20);
        double sphere_distance=4,segment_distance=4,ray_distance=20;
        bool sphere_hit=false,segment_hit=false,ray_hit=false;
        for(const auto& triangle:triangles) {
            const auto p=triangle.closest(a,4);
            const auto s=triangle.closest_segment(a,b,4);
            const auto r=triangle.ray(a,{b.x-a.x,b.y-a.y,b.z-a.z},20);
            if(p.hit) { sphere_hit=true; sphere_distance=std::min(sphere_distance,p.distance); }
            if(s.hit) { segment_hit=true; segment_distance=std::min(segment_distance,s.distance); }
            if(r.hit) { ray_hit=true; ray_distance=std::min(ray_distance,r.distance); }
        }
        check(sphere.hit==sphere_hit&&(!sphere_hit||near(sphere.distance,sphere_distance)),"sphere BVH agrees with exhaustive query");
        check(segment.hit==segment_hit&&(!segment_hit||near(segment.distance,segment_distance)),"segment BVH agrees with exhaustive query");
        check(ray.hit==ray_hit&&(!ray_hit||near(ray.distance,ray_distance)),"ray BVH agrees with exhaustive query");
    }
}

int main() {
    try {
        slope_and_rays();
        exact_segment_features();
        step_and_corner();
        validation_and_replacement();
        large_bvh();
        bvh_matches_exhaustive_queries();
        std::cout<<"STATIC_GEOMETRY_PASS slope step corner segment validation bvh_triangles=100352\n";
        return 0;
    } catch(const std::exception& error) {
        std::cerr<<error.what()<<"\n";
        return 1;
    }
}
