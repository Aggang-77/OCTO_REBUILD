# Contact-driven controls

The eight arm keys follow the octopus's body, with labels drawn over the
selected animal's arms. Camera orbit does not remap them.

| Arm | Key |
|---|---|
| Left front / right front | W / E |
| Left side-front / right side-front | Q / D |
| Left side-rear / right side-rear | A / C |
| Left rear / right rear | Z / X |

Hold one or several arm keys to repeat reach, actual grip, pull and release.
An arm waits for the authoritative C++ `attached` state before pulling. If
contact never happens, it retracts and retries after 1.5 seconds. Losing a
grip ends the pull. Releasing the key initiates peeling, then returns to
passive, asymmetric rest.

| Input | Action |
|---|---|
| Shift + arm | Reach continuously without entering the pull phase |
| Ctrl + arm | Reach/contact and brace without the stroke motor |
| Comma / period + arm | Opposite material twist targets |
| Arrow keys | Body-relative crawl assistance with staggered arm groups |
| Space | Immediately release all suckers; overrides every arm/modifier |
| Tab | Select the other octopus |
| Left drag / right drag | Bounded force picking / camera orbit |
| F5 | Reset the native world and control cycle clock |

Ctrl takes precedence over Shift if both modifiers are held. Manual arm
keys take precedence over the timed arm selection of the crawl assistant.
Arrow input selects arms and muscle targets; it never writes body position
or velocity. Sideways and backwards efficiency are not calibrated. Neither
the gait nor grip forces have been validated against animal kinematics.

The controller is advanced using simulation time. Repeated render frames
cannot accelerate the cycle. Per-arm states are retained separately per
animal and reset when simulation time resets. Native sucker acquisition
uses the same conservative floor support as native collision, and cannot
reacquire while extension is below the peel threshold.
