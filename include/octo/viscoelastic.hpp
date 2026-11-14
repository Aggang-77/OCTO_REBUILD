#pragma once
#include <algorithm>
#include <cmath>

namespace octo::viscoelastic {
// Delayed rest-shape strain q for a standard-linear-solid-inspired
// internal variable. total_strain is displacement relative to the
// commanded anatomical rest shape; stress is proportional to
// (total_strain-q). No extra velocity or hidden spring mass is introduced.
//
// dq/dt = creep_rate * (total_strain - q) - recovery_rate*q
// Exact update for constant total_strain over dt, bounded to avoid
// excessive plastic-looking deformations from transient collisions.
inline double update_creep(double q,double total_strain,double dt,
                           double creep_rate,double recovery_rate,
                           double max_strain) {
    const double rate=creep_rate+recovery_rate;
    if(rate<=0.0||dt<=0.0)return std::clamp(q,-max_strain,max_strain);
    const double equilibrium=creep_rate*total_strain/rate;
    return std::clamp(equilibrium+(q-equilibrium)*std::exp(-rate*dt),
                      -max_strain,max_strain);
}
inline double elastic_stress_proxy(double total_strain,double q) {
    return total_strain-q;
}
} // namespace octo::viscoelastic
