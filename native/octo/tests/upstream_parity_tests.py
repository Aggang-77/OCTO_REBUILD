"""Compare authoritative 8bb7434 and integrated native movement, without a map."""
import json
import subprocess
import sys


class Server:
    def __init__(self, executable):
        self.process = subprocess.Popen([executable], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        self.request_id = 0

    def request(self, operation):
        self.request_id += 1
        self.process.stdin.write(f"1 {self.request_id} {operation}\n")
        self.process.stdin.flush()
        response = json.loads(self.process.stdout.readline())
        assert response["ok"], response
        return response.get("snapshot", {})

    def close(self):
        if self.process.poll() is None:
            self.request("quit")
            self.process.wait(timeout=5)
        self.process.communicate()


def compare(reference, actual, path="state"):
    # Wall-clock cost varies; these are physical and render fields only.
    if isinstance(reference, dict):
        for key, value in reference.items():
            if key != "diagnostics":
                compare(value, actual[key], f"{path}.{key}")
    elif isinstance(reference, list):
        assert len(reference) == len(actual), path
        for index, value in enumerate(reference):
            compare(value, actual[index], f"{path}[{index}]")
    else:
        assert reference == actual, f"{path}: source={reference} integrated={actual}"


def command(frame, scenario):
    controls = []
    for arm in range(8):
        activation, extension, curvature, twist = 0, 1.04, 0, 0
        if frame >= 30 and arm in ((0, 7) if scenario == 0 else (1, 3, 5)):
            phase = (frame - 30 + arm * 3) % 70
            if phase < 11:
                activation, extension, curvature = .8, 1.38, .05
            elif phase < 35:
                activation, extension, curvature = .85, 1.32, .22
            elif phase < 60:
                activation, extension, curvature = 1, .67, .30
            if scenario:
                twist = 2 if arm % 2 else -2
        controls.append(f"0 {arm} {activation} {curvature} {extension} {twist} .02 0 0")
    space = int(frame % 95 < 90)
    drag = "1 0 0 .2 .4 1.2 30 4" if scenario and frame > 100 else "0 0 0 0 0 0 30 20"
    return "step2 8 " + " ".join(controls) + f" {drag} {space}"


def main():
    reference, integrated = (Server(path) for path in sys.argv[1:3])
    frames = 0
    try:
        for scenario in range(2):
            compare(reference.request("reset 1 2.2 1 0 1"), integrated.request("reset 1 2.2 1 0 1"))
            for tick in range(180):
                operation = command(tick, scenario)
                compare(reference.request(operation), integrated.request(operation))
                frames += 1
        print(f"UPSTREAM_PARITY_PASS frames={frames} source=8bb7434 exact_serialized_movement=true")
    finally:
        reference.close()
        integrated.close()


if __name__ == "__main__":
    main()
