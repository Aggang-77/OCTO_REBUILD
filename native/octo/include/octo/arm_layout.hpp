// Generated from config/arm_layout.json. Do not edit the duplicated tables.
#pragma once
#include <array>
namespace octo::layout {
inline constexpr double pi=3.14159265358979323846;
inline constexpr std::array<double,8> degrees{{22.5, 67.5, 112.5, 157.5, -157.5, -112.5, -67.5, -22.5}};
inline constexpr std::array<unsigned,8> model_arms{{7, 6, 5, 4, 3, 2, 1, 0}};
inline constexpr double angle(unsigned arm){return degrees[arm]*pi/180.0;}
}
