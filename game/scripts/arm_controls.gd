extends RefCounted
## Contact-gated muscle targets. Time is native simulation time, never FPS.
## Physical layout: left hand Q/W/A/S controls arms 7/6/5/4;
## right hand U/I/J/K controls arms 0/1/2/3.
const KEYS = [KEY_U, KEY_I, KEY_J, KEY_K, KEY_S, KEY_A, KEY_W, KEY_Q]
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
        return {"activation": 0.0, "extension": 0.86 if release or time - starts[arm] < 0.18 else 1.04,
            "curvature": 0.0, "sweep": 0.0}
    if stretch or brace:
        phases[arm] = "brace" if brace else "reach"
        starts[arm] = time
        return {"activation": 0.78, "extension": 1.10 if brace else 1.35,
            "curvature": 0.0, "sweep": 0.0}
    if phases[arm] == "rest" or phases[arm] == "brace":
        phases[arm] = "reach"
        starts[arm] = time
    var elapsed := time - starts[arm]
    var next := phases[arm]
    match phases[arm]:
        "reach":
            if attached and elapsed >= 0.07:
                next = "pull"
            elif elapsed >= 0.75:
                next = "release" # Retry, never invent a remote grip.
        "pull":
            if not attached or elapsed >= 0.16:
                next = "release"
        "release":
            if elapsed >= 0.32:
                next = "reach"
    if next != phases[arm]:
        phases[arm] = next
        starts[arm] = time
    match phases[arm]:
        "pull":
            return {"activation": 0.78, "extension": 0.95, "curvature": 0.9, "sweep": sweep_sign}
        "release":
            return {"activation": 0.0, "extension": 0.86, "curvature": 0.0, "sweep": 0.0}
    return {"activation": 0.78, "extension": 1.35, "curvature": 0.0, "sweep": 0.0}
