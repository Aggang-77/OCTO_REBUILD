"""Exercise the native server's versioned wire contract and dense reset."""
import json
import subprocess
import sys


def main() -> None:
    with subprocess.Popen([sys.argv[1]], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1) as proc:
        def request(index: int, command: str) -> dict:
            proc.stdin.write(f"1 {index} {command}\n")
            proc.stdin.flush()
            line = proc.stdout.readline()
            assert line, f"server closed before reply {index}"
            reply = json.loads(line)
            assert reply["version"] == 1 and reply["id"] == index
            return reply

        dense = request(1, "reset 2 1.0")
        assert dense["ok"] and dense["snapshot"]["tick"] == 0
        centers = [a["center"] for a in dense["snapshot"]["animals"]]
        assert abs(centers[1][0] - centers[0][0] - 1.0) < 1e-5

        invalid = request(2, "reset 2 -1")
        assert not invalid["ok"] and invalid["error"] == "bad_config"
        assert request(3, "snapshot")["snapshot"]["tick"] == 0

        arms = " ".join(f"{animal} {arm} 0 0 1 0 0 0" for animal in range(2) for arm in range(8))
        advanced = request(4, f"step 16 {arms} 0 0 0 0 0 0 30 20")
        assert advanced["ok"] and advanced["snapshot"]["tick"] == 1
        assert len(advanced["snapshot"]["animals"][0]["arms"][0]["roll"]) == 16
        radii = advanced["snapshot"]["animals"][0]["arms"][0]["radii"]
        assert len(radii) == 16 and all(len(pair) == 2 and min(pair) > 0 for pair in radii)
        assert not request(4, "snapshot")["ok"], "duplicate request ID accepted"
        enabled = request(5, "reset 1 2.2 1")
        assert enabled["ok"] and enabled["snapshot"]["tick"] == 0
        def step2(suction_on: int) -> str:
            commands = " ".join(
                f"0 {arm} 1 0 1.28 0 0.15 0 {1 if arm == 7 else -1}"
                for arm in range(8))
            return f"step2 8 {commands} 0 0 0 0 0 0 30 20 {suction_on}"
        moving = request(6, step2(0))
        assert moving["ok"] and moving["snapshot"]["tick"] == 1
        assert len(moving["snapshot"]["animals"][0]["arms"][0]["attached"]) == 16
        assert moving["snapshot"]["animals"][0]["arms"][0]["grabbed"] is False, "new object grab state is explicitly reported"
        assert len(moving["snapshot"]["animals"][0]["arms"][0]["creep"]) == 16
        assert len(moving["snapshot"]["animals"][0]["arms"][0]["elastic_strain"]) == 16
        assert len(moving["snapshot"]["animals"][0]["body_nodes"]) == 19, "physical mantle shell absent from bridge"
        arm0 = moving["snapshot"]["animals"][0]["arms"][0]
        assert len(arm0["tissue"]) == 16, "sectional tissue strain absent from bridge"
        assert all(len(v) == 2 and min(v) > 0 for v in arm0["tissue"])
        assert all(abs(v[0]*v[1]-1.0) < 1e-4 for v in arm0["tissue"]), "volume-conserving section anisotropy"
        suction_active = request(7, step2(1))
        assert suction_active["ok"] and suction_active["snapshot"]["tick"] == 2
        # Space-held turns on acquisition; contact is not guaranteed in one tick.
        assert all(isinstance(a["attached"], list) for a in suction_active["snapshot"]["animals"][0]["arms"])
        bad_release = request(8, step2(3))
        assert not bad_release["ok"] and bad_release["error"] == "bad_drag"
        invalid_auto = request(9, "reset 2 2.2 3")
        assert not invalid_auto["ok"] and invalid_auto["error"] == "bad_config"
        enabled_volume = request(10, "reset 1 2.2 1 1")
        assert enabled_volume["ok"]
        volume_arms = enabled_volume["snapshot"]["animals"][0]["arms"]
        assert len(volume_arms[0]["volume_rings"]) == 9
        assert all(len(ring) == 4 for ring in volume_arms[0]["volume_rings"])
        assert len(volume_arms[1]["volume_rings"]) == 0
        assert request(11, "reset 1 2.2 1 2")["error"] == "bad_config"
        grounded = request(12, "reset 1 2.2 1 0 1")
        assert grounded["ok"], "grounded low-mantle reset accepted"
        assert grounded["snapshot"]["animals"][0]["center"][1] < 0.35
        assert request(13, "reset 1 2.2 1 0 2")["error"] == "bad_config"
        suction_disabled = request(14, step2(0))
        assert suction_disabled["ok"]
        assert all(not any(a["attached"]) for a in suction_disabled["snapshot"]["animals"][0]["arms"]), "Space-up clears all grips"
        # New step3 carries an explicit mouse-selected target after the
        # backwards-compatible Space flag; an absent target must not grab.
        target_commands = " ".join(
            f"0 {arm} 0.9 0 1.4 0 0.02 {1 if arm == 7 else 0} 0"
            for arm in range(8))
        targeted = request(15, f"step3 8 {target_commands} 0 0 0 0 0 0 30 20 0 2 0 0.1 0.2 0.3")
        assert targeted["ok"] and targeted["snapshot"]["tick"] == 2
        invalid_target = request(16, f"step3 8 {target_commands} 0 0 0 0 0 0 30 20 0 3 0 0 0 0")
        assert not invalid_target["ok"] and invalid_target["error"] == "bad_drag"
        assert request(17, "quit")["ok"]
        proc.wait(timeout=5)
        assert proc.returncode == 0
    print("bridge protocol checks passed")


if __name__ == "__main__":
    main()
