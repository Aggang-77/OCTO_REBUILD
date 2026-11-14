"""Verify shader-free fast renderer and controls-v1 across real Godot/OpenGL frames."""
from __future__ import annotations
import pathlib
import re
import sys
from struct import unpack

def main() -> int:
    log = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
    png = pathlib.Path(sys.argv[2]).read_bytes()
    assert "PROCEDURAL_LITE animals=2 shaders=0 procedural_mesh_rebuild=0" in log, log[-4000:]
    assert "CONTROL_V1_READY arms=8" in log, log[-4000:]
    assert "CONTROL_V1_CHECK animals=2 arm_segments=16 no_shader=true" in log, log[-4000:]
    assert "CONTROL_KEYS_CHECK simultaneous=true spring_return=true space_override=true" in log, log[-4000:]
    assert "KEYMAP_ALL16_CHECK passed=true" in log, log[-4000:]
    assert "SMOKE_OK" in log, log[-4000:]
    assert re.search(r"SCREENSHOT path=.*error=0", log), log[-4000:]
    assert png[:8] == b"\x89PNG\r\n\x1a\n"
    width, height = unpack(">II", png[16:24])
    assert (width,height) == (1280,720), (width,height)
    for error in ("SCRIPT ERROR", "SHADER ERROR", "Parse Error", "Invalid call."):
        assert error not in log, f"{error}: {log[-4000:]}"
    print("FAST_RENDER_PASS renderer=MultiMesh shaders=0 control=v1 screenshot=1280x720")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
