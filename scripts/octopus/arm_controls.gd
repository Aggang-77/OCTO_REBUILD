extends RefCounted
## Contact-gated octopus push stroke; time is native simulation time.
## Mirror corrected against the observed GameReady skin orientation:
## physical arm indices 0..7 display as R,E,W,Q,P,O,I,U.
## Left hand: Q W E R. Right hand: U I O P.
const KEYS = [KEY_R, KEY_E, KEY_W, KEY_Q, KEY_P, KEY_O, KEY_I, KEY_U]
const PHASES = ["reach", "anchor", "pull", "release"]
const REACH_TIME := 0.18
const ANCHOR_TIMEOUT := 0.40
const ANCHOR_CONFIRM := 0.04
const PULL_TIME := 0.42
const RELEASE_TIME := 0.16
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
        brace: bool, release: bool, attached: bool, sweep_sign: float = 1.0,
        suction_enabled: bool = true) -> Dictionary:
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
        enter(arm, "reach", time)
    var elapsed := time - starts[arm]
    match phases[arm]:
        "reach":
            if elapsed >= REACH_TIME:
                enter(arm, "anchor", time)
        "anchor":
            # Real suction contact is mandatory for a suction-powered pull.
            # Without Space, allow a weaker friction-powered pull attempt.
            if attached and suction_enabled and elapsed >= ANCHOR_CONFIRM:
                enter(arm, "pull", time)
            elif not suction_enabled and elapsed >= 0.10:
                enter(arm, "pull", time)
            elif elapsed >= ANCHOR_TIMEOUT:
                enter(arm, "release", time)
        "pull":
            if (suction_enabled and not attached) or elapsed >= PULL_TIME:
                enter(arm, "release", time)
        "release":
            if elapsed >= RELEASE_TIME:
                enter(arm, "reach", time)
    match phases[arm]:
        "reach":
            return {"activation": 0.80, "extension": 1.38, "curvature": 0.05, "sweep": 0.0}
        "anchor":
            # Press arm sections onto the floor, giving real suckers time to seal.
            return {"activation": 0.85, "extension": 1.32, "curvature": 0.22, "sweep": 0.0}
        "pull":
            # Shorten ONLY the body-to-foothold tissue. A sealed sucker
            # stays attached during this phase (no forced peel on contraction).
            return {"activation": 1.0 if suction_enabled else 0.85,
                "extension": 0.67 if suction_enabled else 0.80,
                "curvature": 0.30, "sweep": 0.0}
        "release":
            return {"activation": 0.0, "extension": 1.04, "curvature": 0.0, "sweep": 0.0}
    return {"activation": 0.0, "extension": 1.04, "curvature": 0.0, "sweep": 0.0}
