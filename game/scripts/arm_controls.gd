extends RefCounted
## Contact-gated muscle targets. Time is native simulation time, never FPS.
const KEYS = [KEY_E, KEY_D, KEY_C, KEY_X, KEY_Z, KEY_A, KEY_Q, KEY_W]
const PHASES = ["reach", "pull", "release"]
var phases: Array[String] = []
var starts: Array[float] = []
var last_time := -1.0

func reset() -> void:
    phases.assign(["rest", "rest", "rest", "rest", "rest", "rest", "rest", "rest"])
    starts.assign([-1000.0, -1000.0, -1000.0, -1000.0, -1000.0, -1000.0, -1000.0, -1000.0])
    last_time = -1.0

func sample(arm: int, time: float, held: bool, stretch: bool,
        brace: bool, release: bool, attached: bool, sweep_sign: float = 1.0) -> Dictionary:
    if phases.is_empty() or time < last_time:
        reset()
    last_time = time
    if release or not held:
        if phases[arm] != "rest" or release:
            phases[arm] = "rest"
            starts[arm] = time
        return {"activation": 0.0, "extension": 0.78 if release or time - starts[arm] < 0.32 else 1.10,
            "curvature": 0.0, "sweep": 0.0}
    if stretch or brace:
        phases[arm] = "brace" if brace else "reach"
        starts[arm] = time
        return {"activation": 1.0, "extension": 1.10 if brace else 1.48,
            "curvature": 0.0, "sweep": 0.0}
    if phases[arm] == "rest" or phases[arm] == "brace":
        phases[arm] = "reach"
        starts[arm] = time
    var elapsed := time - starts[arm]
    var next := phases[arm]
    match phases[arm]:
        "reach":
            if attached and elapsed >= 0.12:
                next = "pull"
            elif elapsed >= 1.5:
                next = "release" # Retry, never invent a remote grip.
        "pull":
            if not attached or elapsed >= 0.65:
                next = "release"
        "release":
            if elapsed >= 0.32:
                next = "reach"
    if next != phases[arm]:
        phases[arm] = next
        starts[arm] = time
    match phases[arm]:
        "pull":
            return {"activation": 1.0, "extension": 0.92, "curvature": 1.1, "sweep": sweep_sign}
        "release":
            return {"activation": 0.0, "extension": 0.76, "curvature": 0.0, "sweep": 0.0}
    return {"activation": 1.0, "extension": 1.48, "curvature": 0.0, "sweep": 0.0}
