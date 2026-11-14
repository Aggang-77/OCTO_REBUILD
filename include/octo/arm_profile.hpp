#pragma once
#include <algorithm>
#include <cmath>

namespace octo {
// Semiaxis of the rest cross section in metres. Organic mode stays plump
// through the middle and narrows primarily in the final distal section.
inline double arm_rest_radius(double u, bool organic) {
    u = std::clamp(u, 0.0, 1.0);
    if (!organic) return 0.036 * (1.0 - 0.8 * u);
    return 0.009 + 0.039 * std::sqrt(std::max(0.0, 1.0 - std::pow(u, 5.0)));
}
}  // namespace octo
