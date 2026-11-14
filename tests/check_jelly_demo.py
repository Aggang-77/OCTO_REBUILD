"""Validate Godot's no-GLB jelly demo, including screenshot generation."""
from __future__ import annotations

import pathlib
import re
import sys
from struct import unpack


def main() -> int:
    log_path = pathlib.Path(sys.argv[1])
    picture = pathlib.Path(sys.argv[2])
    log = log_path.read_text(encoding="utf-8", errors="replace")
    assert "PROCEDURAL_JELLY animals=2 model_not_required=true" in log, log[-3000:]
    assert "JELLY_RENDERER_ON animals=2" in log, log[-3000:]
    match = re.search(r"JELLY_CHECK animals=2 arms=8 vertices_per_arm=(\d+)", log)
    assert match, log[-3000:]
    assert int(match.group(1)) >= 300, match.group(0)
    assert "SMOKE_OK" in log, log[-3000:]
    assert "SCREENSHOT path=" in log and "error=0" in log, log[-3000:]
    for error in ("SCRIPT ERROR", "SHADER ERROR", "Parse Error", "Invalid call.", "ERROR:"):
        assert error not in log, f"{error}: {log[-4000:]}"

    png = picture.read_bytes()
    assert png[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    width, height = unpack(">II", png[16:24])
    assert width >= 640 and height >= 360, (width, height)
    print(f"JELLY_RENDER_PASS vertices_per_arm={match.group(1)} screenshot={width}x{height}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
