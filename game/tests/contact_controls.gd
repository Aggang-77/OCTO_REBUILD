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
    for key in CONTROLS.KEYS:
        unique[key] = true
    require(unique.size() == 8, "independent physical keys")
    for arm in 8:
        controls.reset()
        var cmd: Dictionary = controls.sample(arm, 0.0, true, false, false, false, false)
        require(controls.phases[arm] == "reach" and cmd.extension > 1.3,
            "reach begins before contact")
        cmd = controls.sample(arm, 0.19, true, false, false, false, false)
        require(controls.phases[arm] == "anchor", "reach changes to seal")
        cmd = controls.sample(arm, 0.25, true, false, false, false, false)
        require(controls.phases[arm] == "anchor" and cmd.extension > 1.2,
            "no powered pull without physical attachment")
        cmd = controls.sample(arm, 0.29, true, false, false, false, true)
        require(controls.phases[arm] == "pull" and cmd.extension < .75,
            "true sucker contact enables strong contraction")
        cmd = controls.sample(arm, 0.50, true, false, false, false, false)
        require(controls.phases[arm] == "release" and cmd.activation == 0,
            "lost grip stops powered pull")
        cmd = controls.sample(arm, 0.68, true, false, false, false, false)
        require(controls.phases[arm] == "reach" and cmd.extension > 1.3,
            "released stroke repeats")
        # Shift/Ctrl no longer control extension/brace in the gait module:
        # they are parsed separately as native grab/release actions.
        controls.reset()
        var normal: Dictionary = controls.sample(arm, 0.0, true, false, false, false, false)
        controls.reset()
        var old_shift: Dictionary = controls.sample(arm, 0.0, true, true, false, false, false)
        controls.reset()
        var old_ctrl: Dictionary = controls.sample(arm, 0.0, true, false, true, false, false)
        require(normal == old_shift and normal == old_ctrl,
            "deprecated Shift reach and Ctrl brace are removed")
        cmd = controls.sample(arm, 0.01, false, false, false, false, false)
        require(cmd.activation == 0 and cmd.extension == 1.04,
            "released arm keeps passive neutral length")
        controls.sample(arm, 0.0, true, false, false, false, false)
        require(controls.phases[arm] == "reach", "rewound time resets phase state")
    print("CONTACT_CONTROLS_PASS eight arms reach-seal-pull-release no_old_modifiers")
    quit(0)
