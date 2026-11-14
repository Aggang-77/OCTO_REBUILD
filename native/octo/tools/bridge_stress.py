"""Isolate the C++ server's ten-animal active stream from the Godot pipe UI."""
import json
import queue
import subprocess
import sys
import threading
import time


def main() -> int:
    server = sys.argv[1]
    ticks = int(sys.argv[2]) if len(sys.argv) > 2 else 600
    proc = subprocess.Popen([server], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            text=True, bufsize=1)
    responses = queue.Queue()

    def reader():
        for line in proc.stdout:
            responses.put(line)

    threading.Thread(target=reader, daemon=True).start()
    arms = " ".join(f"{animal} {arm} 1 2 1 3 0 0"
                    for animal in range(10) for arm in range(8))
    try:
        start = time.perf_counter()
        for request_id in range(1, ticks + 2):
            command = "reset 10 1.0" if request_id == 1 else (
                f"step 80 {arms} 0 0 0 0 0 0 30 20")
            proc.stdin.write(f"1 {request_id} {command}\n")
            proc.stdin.flush()
            try:
                reply = json.loads(responses.get(timeout=3))
            except queue.Empty:
                raise RuntimeError(f"native response timeout at request {request_id}, "
                                   f"process_alive={proc.poll() is None}")
            assert reply["ok"] and reply["id"] == request_id
            assert reply["snapshot"]["tick"] == request_id - 1
        elapsed = time.perf_counter() - start
        print(f"SERVER_STRESS_OK ticks={ticks} elapsed_s={elapsed:.3f} "
              f"ticks_per_s={ticks / elapsed:.2f}")
        return 0
    finally:
        proc.kill()
        proc.wait(timeout=5)


if __name__ == "__main__":
    sys.exit(main())
