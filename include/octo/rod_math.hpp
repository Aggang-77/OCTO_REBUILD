#pragma once
#include "octo/world.hpp"
#include <algorithm>
#include <cmath>

namespace octo::rod_math {
inline Vec3 add(Vec3 a,Vec3 b){return {a.x+b.x,a.y+b.y,a.z+b.z};}
inline Vec3 sub(Vec3 a,Vec3 b){return {a.x-b.x,a.y-b.y,a.z-b.z};}
inline Vec3 mul(Vec3 a,double s){return {a.x*s,a.y*s,a.z*s};}
inline double dot(Vec3 a,Vec3 b){return a.x*b.x+a.y*b.y+a.z*b.z;}
inline Vec3 cross(Vec3 a,Vec3 b){return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x};}
inline double length(Vec3 a){return std::sqrt(dot(a,a));}
inline Quat multiply(Quat a,Quat b){return {a.w*b.x+a.x*b.w+a.y*b.z-a.z*b.y,a.w*b.y-a.x*b.z+a.y*b.w+a.z*b.x,a.w*b.z+a.x*b.y-a.y*b.x+a.z*b.w,a.w*b.w-a.x*b.x-a.y*b.y-a.z*b.z};}
inline Quat inverse(Quat q){return {-q.x,-q.y,-q.z,q.w};}
inline Quat normalize(Quat q){double l=std::sqrt(q.x*q.x+q.y*q.y+q.z*q.z+q.w*q.w);return l>1e-15?Quat{q.x/l,q.y/l,q.z/l,q.w/l}:Quat{};}
inline Quat rotation(Vec3 angle){double a=length(angle);if(a<1e-10)return normalize({angle.x*.5,angle.y*.5,angle.z*.5,1});double s=std::sin(a*.5)/a;return {angle.x*s,angle.y*s,angle.z*s,std::cos(a*.5)};}
inline Vec3 rotate(Quat q,Vec3 v){Vec3 u{q.x,q.y,q.z};Vec3 t=mul(cross(u,v),2);return add(v,add(mul(t,q.w),cross(u,t)));}
inline Vec3 log_rotation(Quat q){q=normalize(q);if(q.w<0)q={-q.x,-q.y,-q.z,-q.w};Vec3 v{q.x,q.y,q.z};double s=length(v);return s<1e-10?mul(v,2):mul(v,2*std::atan2(s,q.w)/s);}
inline Quat integrate(Quat q,Vec3 omega,double h){return normalize(multiply(rotation(mul(omega,h)),q));}
}
