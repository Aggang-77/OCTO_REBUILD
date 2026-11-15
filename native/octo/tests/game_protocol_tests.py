"""Exercise the mantle-balloon game adapter through its actual executable."""
import json
import subprocess
import sys


def main():
    process = subprocess.Popen([sys.argv[1]], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
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

    def step(active=False, space=False, carry=False):
        commands = []
        for arm in range(8):
            held = active and arm == 0
            commands.append(f"0 {arm} {.78 if held else 0} 0 {1.10 if held else 1.04} 0 .02 0 0")
        mask = [int(carry)] + [0] * 7
        return request("step6 8 " + " ".join(commands) + f" 0 0 0 0 0 0 30 30 {int(space)} " + "0 0 0 0 0 " + " ".join(map(str, mask)) + " 0 0")

    try:
        reset = request("game_reset5 2 .4 -3 1.5 2 -20 -20 40 .4 .4 .4 .4")
        assert not frame(reset)["geometry_ready"]
        request("step6", False, "geometry_not_ready")
        request("mesh_begin 7", False, "bad_mesh_count")
        request("mesh_begin 6")
        request("mesh_chunk 0 3 0 0 0 1 0 0 nan 0 1", False, "bad_mesh_vertex")
        request("mesh_chunk 3 3 0 0 0 1 0 0 0 0 1", False, "bad_mesh_chunk")
        request("mesh_commit", False, "incomplete_mesh")
        request("mesh_chunk 0 3 -20 .4 -20 -20 .4 20 20 .4 20")
        request("mesh_chunk 0 3 -20 .4 -20 20 .4 20 20 .4 -20", False, "bad_mesh_chunk")
        request("mesh_commit", False, "incomplete_mesh")
        request("mesh_chunk 3 3 -20 .4 -20 20 .4 20 20 .4 -20")
        ready = frame(request("mesh_commit"))
        world = ready["world"]
        assert ready["geometry_ready"] and world["static_triangles"] == 2
        assert world["size_scale"] == 1.5
        assert world["source_commit"] == "9a2a7df438bb5098b9f8492bbb55897c96fb52c4"
        center = world["animals"][0]["center"]
        assert max(abs(a-b) for a, b in zip(center, (2, .805, -3))) < 1e-7, center
        for arm in world["animals"][0]["arms"]:
            assert len(arm["contact_radii"]) == len(arm["sucker_dirs"]) == 17
        for _ in range(60):
            idle = frame(step())["world"]
            assert all(not any(arm["attached"]) for arm in idle["animals"][0]["arms"])
        for _ in range(45):
            off = frame(step(True))["world"]
            assert all(not any(arm["attached"]) for arm in off["animals"][0]["arms"])
        acquired = False
        for _ in range(150):
            arms = frame(step(True, True))["world"]["animals"][0]["arms"]
            assert all(not any(arm["attached"]) for arm in arms[1:])
            if any(arms[0]["attached"]):
                acquired = True
                break
        assert acquired, "active source arm acquires real Space-enabled floor grip"
        carried = frame(step(True, True, True))["world"]["animals"][0]["arms"]
        assert not any(carried[0]["attached"]), "actor carry excludes simultaneous floor grip"
        released = frame(step(True, False))["world"]["animals"][0]["arms"]
        assert all(not any(arm["attached"]) for arm in released)
        request("quit")
        assert process.wait(timeout=5) == 0
        print(f"GAME_PROTOCOL_PASS checks={checks} atomic_geometry origin_scale source Space active_only carry")
    finally:
        if process.poll() is None:
            process.kill()
        process.communicate()


if __name__ == "__main__":
    main()