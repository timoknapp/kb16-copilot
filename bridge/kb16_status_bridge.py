#!/usr/bin/env python3
"""
KB16 status bridge: push Copilot CLI status to the KB16-01 RGB LEDs via Raw HID.

Two modes:
  1. One-shot:   kb16_status_bridge.py <status>
       status = idle | thinking | running | done | error
  2. Watch mode: kb16_status_bridge.py --watch [STATE_FILE]
       Polls STATE_FILE (default ~/.copilot-kb16-status) and pushes on change.

Requires: pip install hid   (hidapi)

Raw HID protocol (matches firmware/kb16_status_via/keymap.c):
  report bytes = [0x01, status_value]
  status_value: idle=0 thinking=1 running=2 done=3 error=4

The KB16-01 uses VID 0xD010 / PID 0x1601. QMK Raw HID advertises usage_page
0xFF60, usage 0x61.
"""

import os
import sys
import time

try:
    import hid
except ImportError:
    sys.stderr.write("Missing dependency: pip install hid\n")
    sys.exit(2)

VID = 0xD010
PID = 0x1601
RAW_USAGE_PAGE = 0xFF60
RAW_USAGE = 0x61

STATUS = {"idle": 0, "thinking": 1, "running": 2, "done": 3, "error": 4}
DEFAULT_STATE_FILE = os.path.expanduser("~/.copilot-kb16-status")


def find_raw_path():
    for d in hid.enumerate(VID, PID):
        if d.get("usage_page") == RAW_USAGE_PAGE and d.get("usage") == RAW_USAGE:
            return d["path"]
    return None


def open_device():
    path = find_raw_path()
    if not path:
        raise RuntimeError(
            "KB16 Raw HID interface not found. Is the board plugged in and "
            "flashed with the kb16_status_via firmware?"
        )
    h = hid.device()
    h.open_path(path)
    h.set_nonblocking(1)
    return h


def send_status(h, status_word):
    value = STATUS.get(status_word.strip().lower())
    if value is None:
        return False
    # QMK Raw HID expects a leading report ID byte (0x00) on some platforms.
    report = [0x00, 0x01, value] + [0] * 30
    h.write(report)
    return True


def read_state(state_file):
    try:
        with open(state_file, "r") as f:
            return f.read().strip().lower()
    except FileNotFoundError:
        return "idle"


def watch(state_file):
    h = open_device()
    last = None
    print(f"Watching {state_file} -> KB16 LEDs (Ctrl+C to stop)")
    try:
        while True:
            s = read_state(state_file)
            if s != last and s in STATUS:
                if send_status(h, s):
                    last = s
                    print(f"status -> {s}")
            time.sleep(0.2)
    except KeyboardInterrupt:
        pass
    finally:
        h.close()


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(1)

    if args[0] == "--watch":
        state_file = args[1] if len(args) > 1 else DEFAULT_STATE_FILE
        watch(state_file)
        return

    status_word = args[0]
    if status_word not in STATUS:
        sys.stderr.write(f"Unknown status: {status_word}\n")
        sys.exit(1)
    h = open_device()
    try:
        ok = send_status(h, status_word)
        print(("sent " if ok else "failed ") + status_word)
    finally:
        h.close()


if __name__ == "__main__":
    main()
