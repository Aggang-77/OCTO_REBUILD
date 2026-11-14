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

        dense = request(1, "reset 2 1.0 0.8")
        assert dense["ok"] and dense["snapshot"]["tick"] == 0
        centers = [a["center"] for a in dense["snapshot"]["animals"]]
        assert abs(centers[1][0] - centers[0][0] - 1.0) < 1e-5

        invalid = request(2, "reset 2 -1")
        assert not invalid["ok"] and invalid["error"] == "bad_config"
        assert not request(3, "reset 2 1.0 2.0")["ok"], "out of range idle strength accepted"
        assert request(4, "snapshot")["snapshot"]["tick"] == 0

        arms = " ".join(f"{animal} {arm} 0 0 1 0 0 0" for animal in range(2) for arm in range(8))
        advanced = request(5, f"step 16 {arms} 0 0 0 0 0 0 30 20")
        assert advanced["ok"] and advanced["snapshot"]["tick"] == 1
        assert len(advanced["snapshot"]["animals"][0]["arms"][0]["nodes"]) == 25
        assert len(advanced["snapshot"]["animals"][0]["arms"][0]["roll"]) == 24
        radii = advanced["snapshot"]["animals"][0]["arms"][0]["radii"]
        assert len(radii) == 24 and all(len(pair) == 2 and min(pair) > 0 for pair in radii)
        assert not request(5, "snapshot")["ok"], "duplicate request ID accepted"
        small = request(6, "reset 2 1.0 0.0 16")
        assert small["ok"] and len(small["snapshot"]["animals"][0]["arms"][0]["nodes"]) == 17
        assert request(7, "quit")["ok"]
        proc.wait(timeout=5)
        assert proc.returncode == 0
    print("bridge protocol checks passed")


if __name__ == "__main__":
    main()
