extends SceneTree
const CONTROLS = preload("res://scripts/arm_controls.gd")

func require(ok: bool, message: String) -> void:
    if not ok:
        printerr("CONTACT_CONTROLS_FAIL " + message)
        quit(2)
        assert(false, message)

func _initialize() -> void:
    var controls = CONTROLS.new()
    require(CONTROLS.KEYS.size() == 8, "eight arm keys")
    var unique := {}
    for key in CONTROLS.KEYS: unique[key] = true
    require(unique.size() == 8, "independent physical keys")
    for arm in 8:
        controls.reset()
        var cmd: Dictionary = controls.sample(arm, 0.0, true, false, false, false, false)
        require(cmd.extension > 1.4 and cmd.sweep == 0, "reach before contact")
        cmd = controls.sample(arm, 0.4, true, false, false, false, false)
        require(controls.phases[arm] == "reach", "cannot pull without physical attachment")
        cmd = controls.sample(arm, 0.5, true, false, false, false, true)
        require(controls.phases[arm] == "pull" and cmd.extension > 0.87 and cmd.sweep == 1, "contact gates pull")
        cmd = controls.sample(arm, 0.6, true, false, false, false, false)
        require(cmd.activation == 0 and cmd.extension < 0.87, "lost grip initiates peel")
        cmd = controls.sample(arm, 1.0, true, true, false, false, true)
        require(cmd.extension > 1.4 and cmd.sweep == 0, "Shift maintains reach")
        cmd = controls.sample(arm, 1.1, true, false, true, false, true)
        require(cmd.extension == 1.1 and cmd.sweep == 0, "Ctrl braces")
        cmd = controls.sample(arm, 1.2, true, true, true, true, true)
        require(cmd.activation == 0 and cmd.extension < 0.87, "Space overrides modifiers and grip")
        cmd = controls.sample(arm, 2.0, false, false, false, false, false)
        require(cmd.activation == 0 and cmd.extension == 1.1, "released arm settles into passive rest")
        controls.sample(arm, 0.0, true, false, false, false, false)
        require(controls.phases[arm] == "reach", "world reset clears phase time")
    print("CONTACT_CONTROLS_PASS eight arms contact gating modifiers release reset")
    quit(0)
