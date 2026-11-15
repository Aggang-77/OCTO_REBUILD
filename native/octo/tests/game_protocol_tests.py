"""Exercise the actual executable's atomic geometry upload and input contract."""
import json
import subprocess
import sys


def main():
    process = subprocess.Popen([sys.argv[1]], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, text=True)
    request_id = 0
    checks = 0

    def request(operation, expected=True, error=None):
        nonlocal request_id, checks
        request_id += 1
        process.stdin.write(f"1 {request_id} {operation}\n")
        process.stdin.flush()
        reply = json.loads(process.stdout.readline())
        assert reply["id"] == request_id and reply["ok"] is expected, reply
        if error is not None:
            assert reply["error"] == error, reply
        checks += 1
        return reply

    def frame(reply):
        return reply["snapshot"]["frame"]

    def step(extend=False, stroke=False, release=False):
        commands = []
        for arm in range(8):
            active = extend and arm in (0, 7)
            commands.append(f"0 {arm} {int(active)} 0 {1.48 if active else .58} "
                            f"0 .25 0 {1 if stroke else -1} "
                            f"{int(active)} {int(active and stroke)} 0")
        return request("step4 8 " + " ".join(commands) +
                       f" 0 0 0 0 0 0 0 0 {int(release)} 0 0")

    try:
        reset = request("game_reset4 0 .45 0 1.5 2 -20 -20 40 0 0 0 0")
        assert not frame(reset)["geometry_ready"]
        request("step4", False, "geometry_not_ready")
        request("mesh_begin 7", False, "bad_mesh_count")
        request("mesh_begin 6")
        request("mesh_chunk 0 3 0 0 0 1 0 0 nan 0 1", False, "bad_mesh_vertex")
        request("mesh_chunk 3 3 0 0 0 1 0 0 0 0 1", False, "bad_mesh_chunk")
        request("mesh_commit", False, "incomplete_mesh")
        request("mesh_chunk 0 3 -20 0 -20 -20 0 20 20 0 20")
        request("mesh_chunk 0 3 -20 0 -20 20 0 20 20 0 -20", False, "bad_mesh_chunk")
        request("mesh_commit", False, "incomplete_mesh")
        request("mesh_chunk 3 3 -20 0 -20 20 0 20 20 0 -20")
        ready = frame(request("mesh_commit"))
        assert ready["geometry_ready"] and ready["world"]["static_triangles"] == 2
        assert ready["world"]["size_scale"] == 1.5
        for _ in range(60):
            idle = frame(step())["world"]
            assert all(not any(arm["attached"]) for arm in idle["animals"][0]["arms"])
        active = frame(step(True, True))["world"]["animals"][0]["arms"]
        assert active[0]["extend"] and active[0]["stroke"]
        assert active[7]["extend"] and not active[1]["extend"]
        released = frame(step(True, False, True))["world"]["animals"][0]["arms"]
        assert all(not any(arm["attached"]) for arm in released)
        assert released[0]["rearm_required"]
        request("quit")
        assert process.wait(timeout=5) == 0
        print(f"GAME_PROTOCOL_PASS checks={checks} geometry_atomic ready scale flags idle release")
    finally:
        if process.poll() is None:
            process.kill()
        process.communicate()


if __name__ == "__main__":
    main()
