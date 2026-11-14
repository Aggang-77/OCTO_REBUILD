#pragma once
#include "octo/world.hpp"
#include <cmath>
#include <optional>

namespace octo {
struct SweepHit { double time; Vec3 normal; };

// Earliest contact of two linearly moving sphere centers over one substep.
// The normal points from A to B; an initially overlapping pair belongs to the
// ordinary penetration solver instead of this sweep.
inline std::optional<SweepHit> swept_sphere_toi(Vec3 a0, Vec3 a1, Vec3 b0, Vec3 b1, double radius) {
    const Vec3 r{b0.x-a0.x,b0.y-a0.y,b0.z-a0.z};
    const Vec3 v{(b1.x-b0.x)-(a1.x-a0.x),(b1.y-b0.y)-(a1.y-a0.y),(b1.z-b0.z)-(a1.z-a0.z)};
    const auto dot=[](Vec3 a,Vec3 b){return a.x*b.x+a.y*b.y+a.z*b.z;};
    const double c=dot(r,r)-radius*radius, aa=dot(v,v), b=dot(r,v);
    if(c<=0||aa<=1e-18||b>=0||!std::isfinite(c)||!std::isfinite(aa)||!std::isfinite(b))return std::nullopt;
    const double discriminant=b*b-aa*c;
    if(discriminant<0)return std::nullopt;
    const double t=(-b-std::sqrt(discriminant))/aa;
    if(t<0||t>1)return std::nullopt;
    const Vec3 point{r.x+v.x*t,r.y+v.y*t,r.z+v.z*t};
    const double length=std::sqrt(dot(point,point));
    if(length<=1e-12)return std::nullopt;
    return SweepHit{t,{point.x/length,point.y/length,point.z/length}};
}
} // namespace octo
