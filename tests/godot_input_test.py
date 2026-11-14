"""Run synthetic Godot key and mouse events through the live C++ world."""
import os
from pathlib import Path
import re
import subprocess
import sys


godot, server, game, build = map(Path, sys.argv[1:5])
environment = os.environ.copy()
environment["OCTO_SERVER"] = str(server.resolve())
for key, folder in (("APPDATA", "appdata"), ("LOCALAPPDATA", "localappdata")):
    path = build / "godot-input" / folder
    path.mkdir(parents=True, exist_ok=True)
    environment[key] = str(path.resolve())

result = subprocess.run(
    [str(godot), "--headless", "--path", str(game), "--", "--animals=2",
     "--benchmark-ticks=120", "--test-input", "--procedural"],
    env=environment, capture_output=True, text=True, timeout=40,
)
print(result.stdout)
if result.stderr:
    print(result.stderr, file=sys.stderr)
assert result.returncode == 0, f"Godot exited {result.returncode}"
match = re.search(
    r"INPUT_CHECK selected=(\d+) arm=(\w+) drag=(\w+) phase=(\d+) "
    r"arm_delta_m=([\d.]+) center_delta_m=([\d.]+)", result.stdout,
)
assert match, "Godot did not report the input path"
selected, arm, drag, phase, arm_delta, center_delta = match.groups()
assert (selected, arm, drag, phase) == ("1", "true", "true", "4")
assert float(arm_delta) > .005 and float(center_delta) > .002
assert "SMOKE_OK tick=120" in result.stdout
