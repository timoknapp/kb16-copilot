#!/usr/bin/env python3
"""
KB16 status bridge: push Copilot CLI status to the KB16-01 RGB LEDs via Raw HID.

Each of the 16 LEDs is an independent "agent slot", so several concurrent
Copilot sessions are visible at once. Slots are assigned per session_id and held
for the life of that session. Idle slots are dark: the board shows activity,
never inactivity.

Two modes:
  1. One-shot:   kb16_status_bridge.py <status>
       status = idle | thinking | running | done | error
       Sets every slot at once. `idle` blanks the board.
  2. Watch mode: kb16_status_bridge.py --watch [SESSION_DIR]
       Polls SESSION_DIR (default ~/.copilot-kb16-status.d), one file per
       session named after its UUID and containing a status word.
       Falls back to the single-file ~/.copilot-kb16-status if the dir is absent.

Requires: pip install hidapi

Raw HID protocol (matches firmware/kb16_status_via/keymap.c):
  [0xC0, status]        set every slot
  [0xC1, slot, status]  set one agent slot (slot = LED index 0..15)
  [0xC2]                all slots back to idle
  status: idle=0 thinking=1 running=2 done=3 error=4

0xC0-0xC2 sit outside VIA's reserved command IDs (0x01-0x15, 0xFF) so the
firmware hook never shadows a real VIA command.

The KB16-01 uses VID 0xD010 / PID 0x1601. QMK Raw HID advertises usage_page
0xFF60, usage 0x61.
"""

import ctypes
import os
import sys
import time

try:
    import hid
except ImportError:
    sys.stderr.write("Missing dependency: pip install hidapi\n")
    sys.exit(2)

VID = 0xD010
PID = 0x1601
RAW_USAGE_PAGE = 0xFF60
RAW_USAGE = 0x61

# Custom command bytes; must match the KB16_CMD_* defines in the firmware keymap.
CMD_SET_STATUS = 0xC0
CMD_SET_AGENT = 0xC1
CMD_CLEAR = 0xC2

STATUS = {"idle": 0, "thinking": 1, "running": 2, "done": 3, "error": 4}
DEFAULT_STATE_FILE = os.path.expanduser("~/.copilot-kb16-status")
DEFAULT_SESSION_DIR = os.path.expanduser("~/.copilot-kb16-status.d")

# LED count on the KB16-01; also the maximum number of agents shown at once.
SLOT_COUNT = 16

# "done" is a transient celebration, not a state worth holding a slot lit for.
# After this long a finished session goes dark. This is checked against the
# file's mtime here, so it does not depend on anything else running.
DONE_FADE_SECONDS = 4.0

# A session whose file has not been touched in this long is treated as gone.
# Normally SessionEnd removes the file, but a crashed agent never gets to.
SESSION_TTL_SECONDS = 30 * 60


def allow_shared_hid_access():
    """Stop hidapi from seizing the HID interface (macOS only).

    On macOS hidapi opens devices with kIOHIDOptionsTypeSeizeDevice by
    default, which locks out every other client. While this bridge runs, the
    VIA web app then fails with "KB16-01 does not seem to respond like a
    VIA-enabled keyboard" -- the firmware is fine, it simply cannot be reached.

    The python binding does not expose hid_darwin_set_open_exclusive(), so call
    it directly in the bundled native library. Must run before any open.
    """
    if sys.platform != "darwin":
        return
    try:
        lib = ctypes.CDLL(hid.__file__)
        lib.hid_darwin_set_open_exclusive.argtypes = [ctypes.c_int]
        lib.hid_darwin_set_open_exclusive.restype = None
        lib.hid_darwin_set_open_exclusive(0)
    except (OSError, AttributeError):
        # Older hidapi without the symbol: the bridge still works, but VIA
        # will need this process stopped before it can talk to the board.
        sys.stderr.write(
            "warning: could not disable exclusive HID access; "
            "stop this bridge before using VIA\n"
        )


def find_raw_path():
    for d in hid.enumerate(VID, PID):
        if d.get("usage_page") == RAW_USAGE_PAGE and d.get("usage") == RAW_USAGE:
            return d["path"]
    return None


def open_device():
    allow_shared_hid_access()
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


def send_report(h, payload):
    """Write one Raw HID report. Returns True only if it actually went out."""
    # QMK Raw HID expects a leading report ID byte (0x00) on some platforms.
    report = [0x00] + payload + [0] * (32 - len(payload))
    # The write result must be checked. Unplugging the keyboard (which every
    # firmware flash requires) invalidates this handle without raising, so an
    # unchecked write silently succeeds forever while the LEDs never change.
    try:
        return h.write(report) == len(report)
    except (OSError, ValueError):
        return False


def send_status(h, status_word):
    """Set every slot to one status (one-shot mode)."""
    value = STATUS.get(status_word.strip().lower())
    if value is None:
        return False
    return send_report(h, [CMD_SET_STATUS, value])


def send_agent(h, slot, status_word):
    """Set a single agent slot."""
    value = STATUS.get(status_word.strip().lower())
    if value is None:
        return False
    return send_report(h, [CMD_SET_AGENT, slot, value])


def read_state(state_file):
    try:
        with open(state_file, "r") as f:
            return f.read().strip().lower()
    except FileNotFoundError:
        return "idle"


def read_sessions(session_dir):
    """Map session_id -> status word, applying the done-fade and TTL.

    A session that finished more than DONE_FADE_SECONDS ago reads as idle, and
    one untouched for SESSION_TTL_SECONDS is dropped entirely so a crashed
    agent does not hold an LED slot forever.
    """
    sessions = {}
    now = time.time()
    try:
        names = os.listdir(session_dir)
    except OSError:
        return sessions

    for name in names:
        path = os.path.join(session_dir, name)
        try:
            age = now - os.path.getmtime(path)
            with open(path, "r") as f:
                status = f.read().strip().lower()
        except OSError:
            continue
        if status not in STATUS:
            continue
        if age > SESSION_TTL_SECONDS:
            try:
                os.unlink(path)
            except OSError:
                pass
            continue
        if status == "done" and age > DONE_FADE_SECONDS:
            status = "idle"
        sessions[name] = status
    return sessions


def assign_slots(sessions, slots):
    """Give each session a stable slot, freeing slots as sessions disappear.

    `slots` is mutated in place. A session keeps its slot for its whole life, so
    an agent's LED never moves under you while you are watching it.
    """
    for session_id in list(slots):
        if session_id not in sessions:
            del slots[session_id]

    used = set(slots.values())
    for session_id in sorted(sessions):
        if session_id in slots:
            continue
        free = next((i for i in range(SLOT_COUNT) if i not in used), None)
        if free is None:
            continue  # more than 16 concurrent agents; extras are not shown
        slots[session_id] = free
        used.add(free)
    return slots


def watch(target):
    """Follow either a session directory (per-agent) or a single status file."""
    h = None
    slots = {}
    shown = {}  # slot -> status word currently on the board
    per_agent = os.path.isdir(target)
    label = "per-agent" if per_agent else "single-status"
    print(f"Watching {target} ({label}) -> KB16 LEDs (Ctrl+C to stop)")

    try:
        while True:
            if not per_agent and os.path.isdir(DEFAULT_SESSION_DIR):
                # The hooks create this on their first run, which may be well
                # after the bridge started. Upgrade rather than stay degraded.
                target = DEFAULT_SESSION_DIR
                per_agent = True
                shown = {}
                print(f"session directory appeared, switching to per-agent mode")

            if per_agent:
                sessions = read_sessions(target)
                assign_slots(sessions, slots)
                desired = {slot: "idle" for slot in range(SLOT_COUNT)}
                for session_id, slot in slots.items():
                    desired[slot] = sessions[session_id]
            else:
                desired = {slot: read_state(target) for slot in range(SLOT_COUNT)}

            changed = {s: v for s, v in desired.items() if shown.get(s) != v}
            if changed:
                if h is None:
                    try:
                        h = open_device()
                        print("connected to KB16")
                        shown = {}  # board state unknown after a reconnect
                        changed = desired
                    except (RuntimeError, OSError) as exc:
                        print(f"waiting for KB16: {exc}")

                if h is not None:
                    for slot, value in sorted(changed.items()):
                        if send_agent(h, slot, value):
                            shown[slot] = value
                            if value != "idle":
                                print(f"slot {slot} -> {value}")
                        else:
                            # Handle went stale, almost always a replug. Drop it
                            # so the next poll reconnects; `shown` is not updated
                            # so this status is retried.
                            print("write failed, reconnecting")
                            try:
                                h.close()
                            except Exception:
                                pass
                            h = None
                            break
            time.sleep(0.2)
    except KeyboardInterrupt:
        pass
    finally:
        if h is not None:
            h.close()


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(1)

    if args[0] == "--watch":
        if len(args) > 1:
            target = args[1]
        else:
            # Prefer per-agent mode; fall back to the single file if the hooks
            # have not created the session directory yet.
            target = (
                DEFAULT_SESSION_DIR
                if os.path.isdir(DEFAULT_SESSION_DIR)
                else DEFAULT_STATE_FILE
            )
        watch(target)
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
