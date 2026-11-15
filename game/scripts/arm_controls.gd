extends RefCounted
## Contact-gated octopus push stroke; time is native simulation time.
## Mirror corrected against the observed GameReady skin orientation:
## physical arm indices 0..7 display as R,E,W,Q,P,O,I,U.
## Left hand: Q W E R. Right hand: U I O P.
const KEYS = [KEY_R, KEY_E, KEY_W, KEY_Q, KEY_P, KEY_O, KEY_I, KEY_U]
const PHASES = ["shorten", "anchor", "elongate", "release"]
const SHORTEN_TIME := 0.18
const ANCHOR_TIMEOUT := 0.42
const ANCHOR_CONFIRM := 0.04
const ELONGATE_TIME := 0.34
const RELEASE_TIME := 0.19
var phases: Array[String] = []
var starts: Array[float] = []
var last_time := -1.0

func reset() -> void:
    phases.assign(["rest", "rest", "rest", "rest", "rest", "rest", "rest", "rest"])
    starts.assign([-1000.0, -1000.0, -1000.0, -1000.0, -1000.0, -1000.0, -1000.0, -1000.0])
    last_time = -1.0

func enter(arm: int, phase: String, time: float) -> void:
    phases[arm] = phase
    starts[arm] = time

func sample(arm: int, time: float, held: bool, stretch: bool,
        brace: bool, release: bool, attached: bool, sweep_sign: float = 1.0) -> Dictionary:
    if phases.is_empty() or time < last_time:
        reset()
    last_time = time
    if release or not held:
        if phases[arm] != "rest":
            enter(arm, "rest", time)
        return {"activation": 0.0, "extension": 0.78 if release else 1.04,
            "curvature": 0.0, "sweep": 0.0}
    # Manual overrides: Shift extends without a power stroke; Ctrl braces.
    if stretch or brace:
        if phases[arm] not in ["brace", "reach"]:
            enter(arm, "brace" if brace else "reach", time)
        return {"activation": 0.78, "extension": 1.10 if brace else 1.35,
            "curvature": 0.0, "sweep": 0.0}
    if phases[arm] not in PHASES:
        enter(arm, "shorten", time)
    var elapsed := time - starts[arm]
    match phases[arm]:
        "shorten":
            if elapsed >= SHORTEN_TIME:
                enter(arm, "anchor", time)
        "anchor":
            if attached and elapsed >= ANCHOR_CONFIRM:
                enter(arm, "elongate", time)
            elif elapsed >= ANCHOR_TIMEOUT:
                enter(arm, "release", time)
        "elongate":
            if not attached or elapsed >= ELONGATE_TIME:
                enter(arm, "release", time)
        "release":
            if elapsed >= RELEASE_TIME:
                enter(arm, "shorten", time)
    match phases[arm]:
        "shorten":
            return {"activation": 0.52, "extension": 0.90, "curvature": 0.8, "sweep": 0.0}
        "anchor":
            return {"activation": 0.78, "extension": 1.05, "curvature": 0.25, "sweep": 0.0}
        "elongate":
            # The sucker anchor resists displacement while proximal tissue
            # lengthens: motion arises through XPBD reaction, not a body push.
            return {"activation": 0.90, "extension": 1.38, "curvature": 0.0, "sweep": 0.0}
        "release":
            return {"activation": 0.0, "extension": 0.76, "curvature": 0.0, "sweep": 0.0}
    return {"activation": 0.0, "extension": 1.04, "curvature": 0.0, "sweep": 0.0}
