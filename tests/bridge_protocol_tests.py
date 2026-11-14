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
        def step2(release: int) -> str:
            commands = " ".join(
                f"0 {arm} 1 0 1.28 0 0.15 0 {1 if arm == 7 else -1}"
                for arm in range(8))
            return f"step2 8 {commands} 0 0 0 0 0 0 30 20 {release}"
        moving = request(6, step2(0))
        assert moving["ok"] and moving["snapshot"]["tick"] == 1
        assert len(moving["snapshot"]["animals"][0]["arms"][0]["attached"]) == 16
        assert len(moving["snapshot"]["animals"][0]["body_nodes"]) == 19, "physical mantle shell absent from bridge"
        arm0 = moving["snapshot"]["animals"][0]["arms"][0]
        assert len(arm0["tissue"]) == 16, "sectional tissue strain absent from bridge"
        assert all(len(v) == 2 and min(v) > 0 for v in arm0["tissue"])
        assert all(abs(v[0]*v[1]-1.0) < 1e-4 for v in arm0["tissue"]), "volume-conserving section anisotropy"
        releasing = request(7, step2(1))
        assert releasing["ok"] and releasing["snapshot"]["tick"] == 2
        assert all(not any(a["attached"]) for a in releasing["snapshot"]["animals"][0]["arms"])
        bad_release = request(8, step2(3))
        assert not bad_release["ok"] and bad_release["error"] == "bad_drag"
        invalid_auto = request(9, "reset 2 2.2 3")
        assert not invalid_auto["ok"] and invalid_auto["error"] == "bad_config"
        assert request(10, "quit")["ok"]
        proc.wait(timeout=5)
        assert proc.returncode == 0
    print("bridge protocol checks passed")


if __name__ == "__main__":
    main()
