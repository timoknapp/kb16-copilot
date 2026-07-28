# Variant A — VIA + Raw HID status LEDs on the KB16-01

This adds **real per-key RGB status feedback** on the pad itself (like the Codex
Micro), while **keeping VIA** for key/encoder editing. It requires building and
flashing custom QMK firmware.

> ✅ Verified end-to-end on real hardware (KB16-01 **rev2**, STM32F103): built,
> flashed over stm32duino DFU, Raw HID interface confirmed at usage page
> `0xff60`/usage `0x61`, and all 16 LEDs observed tinting on a pushed status.
> A backup of the original firmware is in `firmware/backup/`.

> ℹ️ These instructions target **rev2** (STM32F103). If you have a rev1
> (ATmega32U4), substitute `rev1` for `rev2` everywhere and use
> `dfu-programmer` instead of `dfu-util` — see "Identify your revision" below.

## What you get

- One LED per concurrent Copilot agent, tinted by that agent's status:
  - idle → **off** (the board only ever shows activity)
  - thinking → blue
  - running → yellow
  - done → green, fading to off after 4s
  - error → red
- Up to 16 agents at once, each holding a stable LED for its whole session.
- VIA still edits your key/encoder map.
- The menu-bar dot (Variant B) is optional and redundant here — it can only show
  one merged status, while the LEDs show each agent separately.

## Prerequisites

- A working **QMK build environment**:
  ```bash
  brew install qmk/qmk/qmk
  qmk setup            # clones qmk_firmware, installs toolchain
  ```
- Python `hidapi` for the bridge, in a venv built on **Homebrew** Python:
  ```bash
  /opt/homebrew/bin/python3.13 -m venv ~/.venvs/kb16-bridge
  ~/.venvs/kb16-bridge/bin/pip install -r bridge/requirements.txt
  ```
  Apple's `/usr/bin/python3` and Xcode's `python3` will **not** work: SIP strips
  `DYLD_LIBRARY_PATH` from Apple-signed binaries, so they cannot resolve
  `libhidapi.dylib`. The `hidapi` wheel bundles its own copy of the native
  library, which sidesteps the problem entirely.

## 0. Identify your revision

Both revisions share the same USB VID/PID in normal mode (`0xD010:0x1601`), so
you **cannot** tell them apart while the keyboard is running. Put the board into
bootloader mode (unplug, hold the top-left key, plug back in) and look at what
enumerates:

```bash
dfu-util -l
```

| Bootloader reported | Revision | MCU | QMK target | Flash tool |
|---|---|---|---|---|
| `Found DFU: [1eaf:0003] ... STM32duino bootloader` | **rev2** | STM32F103 | `doio/kb16/rev2` | `dfu-util` |
| nothing; `dfu-programmer atmega32u4 get` responds | **rev1** | ATmega32U4 | `doio/kb16/rev1` | `dfu-programmer` |

Getting this wrong is the single easiest way to waste an afternoon: the two
MCUs share nothing, and firmware built for the wrong one will not flash.

## 1. Add the keymap to QMK

Copy the keymap into your local qmk_firmware checkout:

```bash
QMK=~/qmk_firmware   # wherever `qmk setup` put it
mkdir -p "$QMK/keyboards/doio/kb16/rev2/keymaps/kb16_status_via"
cp firmware/kb16_status_via/keymap.c    "$QMK/keyboards/doio/kb16/rev2/keymaps/kb16_status_via/"
cp firmware/kb16_status_via/rules.mk    "$QMK/keyboards/doio/kb16/rev2/keymaps/kb16_status_via/"
```

Re-copy after every edit — `qmk compile` builds from the checkout, not from
this repo.

## 2. Compile

```bash
qmk compile -kb doio/kb16/rev2 -km kb16_status_via
```

This produces `doio_kb16_rev2_kb16_status_via.bin` (and a `.hex`) in the
qmk_firmware root. STM32 targets are flashed from the `.bin`.

## 3. Flash (DFU)

rev2 uses the `stm32duino` (Maple) bootloader. Put the board into bootloader
mode — unplug, hold the top-left key, plug back in (bootmagic) — then:

```bash
qmk flash -kb doio/kb16/rev2 -km kb16_status_via
```

While in DFU mode the keyboard does not type, so use your laptop keyboard.
After flashing, unplug and replug to boot the new firmware.

After flashing, re-open VIA — your key map is still editable. If VIA doesn't
detect it, re-load `via/kb16-01.json` (V2 definitions enabled).

### Your key assignments will be gone — restore them

Flashing resets the emulated EEPROM that VIA stores the dynamic keymap in, so
the board falls back to the defaults compiled into `keymap.c`. **Every key,
layer, macro and encoder you configured in VIA is replaced.** This is expected,
not a fault.

Export your layout from VIA (*Save Current Layout*) **before** flashing. A known
good export for this board is committed at `via/kb16-01.layout.json` — restore it
with VIA's *Load Saved Layout*. It carries all 4 layers, 16 macro slots and all 3
encoders.

## 4. Run the status bridge

Test one-shot (board plugged in):

```bash
~/.venvs/kb16-bridge/bin/python bridge/kb16_status_bridge.py running   # LEDs go yellow
~/.venvs/kb16-bridge/bin/python bridge/kb16_status_bridge.py idle      # back to normal animation
```

To confirm the firmware exposes Raw HID, look for usage page `0xff60`, usage
`0x61`:

```bash
~/.venvs/kb16-bridge/bin/python -c "import hid; print([(hex(d['usage_page']), hex(d['usage'])) for d in hid.enumerate(0xD010,0x1601)])"
```

Run it as a watcher so it follows the same status file the menu bar uses:

```bash
bridge/kb16-status-bridge          # wrapper: venv python + --watch
```

To keep it always running, generate the LaunchAgent with your real paths
substituted and load it:

```bash
sed -e "s|/Users/YOU/kb16-copilot|$PWD|g" -e "s|/Users/YOU|$HOME|g" \
    bridge/com.kb16.statusbridge.plist > ~/Library/LaunchAgents/com.kb16.statusbridge.plist
plutil -lint ~/Library/LaunchAgents/com.kb16.statusbridge.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.kb16.statusbridge.plist
```

Check it and watch the LED transitions:

```bash
launchctl print gui/$(id -u)/com.kb16.statusbridge | grep -E 'state =|pid ='
tail -f ~/Library/Logs/kb16-statusbridge.log
```

To stop it: `launchctl bootout gui/$(id -u)/com.kb16.statusbridge`.

Two details in the plist are deliberate:

- It runs `bridge/kb16-status-bridge`, a thin wrapper, rather than the venv
  interpreter directly. macOS names the entry in **System Settings > General >
  Login Items & Extensions** after the executable, so pointing it at the
  interpreter produces a bare, meaningless `python` item. (It will still say
  "Item from unidentified developer" — that only goes away with a paid Developer
  ID signature.)
- `PYTHONUNBUFFERED=1` is set. Without it Python block-buffers stdout when it is
  not a tty, and the log files stay permanently empty.

The existing Copilot hooks already write the status file, so no hook changes are
needed — the bridge and the menu bar both read `~/.copilot-kb16-status`.

## Raw HID protocol

```
[0x00, 0xC0, status]        set every slot at once
[0x00, 0xC1, slot, status]  set one agent slot (slot = LED index 0..15)
[0x00, 0xC2]                all slots back to idle

  0x00   report ID (platform padding)
  status 0=idle 1=thinking 2=running 3=done 4=error
```

Because `VIA_ENABLE` is on, QMK's `quantum/via.c` owns `raw_hid_receive()`, so
the keymap hooks the weak `via_command_kb()` instead. The command bytes `0xC0`-`0xC2`
sit outside VIA's reserved command IDs (`0x01`–`0x15` and `0xFF`), so the hook
never shadows a real VIA command — notably `0x01`, which is VIA's
`id_get_protocol_version` handshake.

## One LED per agent

Each of the 16 LEDs is an independent **agent slot**, so concurrent Copilot
sessions are visible at a glance. Slots are the RGB matrix LED indices, which on
this board run row-major from the top-left key:

```
 slot 0   slot 1   slot 2   slot 3
 slot 4   slot 5   slot 6   slot 7
 slot 8   slot 9   slot 10  slot 11
 slot 12  slot 13  slot 14  slot 15
```

The three encoder push-keys have no LEDs and are never used.

**Idle slots are driven to black**, not left alone — the board indicates
activity and never inactivity, so it stays dark when nothing is running. This
means the VIA animation is suppressed while the bridge is active; stop the
bridge (or send `0xC2`) to get it back.

The one exception is **layer 1, the agent layer**: there idle slots glow faintly
white, so the selectable grid is visible and you can tell you are in select mode.
Layer 1 is reached with `OSL(1)` on the large bottom encoder push — a one-shot
layer, so one keypress later the board is back on layer 0 by itself. Pressing a
slot key sends `MEH+A..P`, which Hammerspoon turns into "focus that session's
window" using the `tty` / `cwd` recorded by the hook.

> The `LAYOUT` macro takes 19 positions in `info.json` order, and the three
> encoder push switches sit at column 4 — **interleaved at positions 4, 9 and
> 14, not appended at the end**. Getting that wrong silently shifts the whole
> board by one key, and only shows up after an EEPROM reset.

How a session gets a slot:

1. Copilot pipes event JSON to the hook on stdin, including a stable session
   UUID.
2. `copilot-status.sh` writes `~/.copilot-kb16-status.d/<session_id>` with the
   status word, and removes it on `SessionEnd`. It also still writes the
   aggregate `~/.copilot-kb16-status`, which the optional menubar dot reads and
   which the bridge falls back to if the session directory is missing.
3. The bridge assigns each session the lowest free slot and **holds it for the
   life of that session**, so an agent's LED never moves while you watch it. A
   freed slot is reused by the next new session.

### Frontends disagree on field names

The two Copilot frontends do not send the same JSON, so the hook checks both:

| Field | VS Code Copilot Chat | Copilot CLI |
|---|---|---|
| session UUID | `session_id` | `sessionId` |
| event name | `hook_event_name` | *not sent* |
| timestamp | ISO 8601 string | epoch milliseconds |

Matching only `session_id` is a trap: CLI sessions then never get a per-session
file, so they never light an LED — while the menubar dot keeps working, because
it reads the aggregate file which is always written. The result looks like "it
works in VS Code but not the CLI".

Because the CLI sends no event name, its sessions cannot be detected ending, so
they are reclaimed by the TTL below rather than immediately at `SessionEnd`.
Their LED still goes dark as soon as the status is idle.

To see exactly what a frontend sends:

```bash
touch ~/.copilot-kb16-debug      # enable capture
# ...run an agent...
cat ~/.copilot-kb16-debug.log    # time, status, session id, raw payload
rm ~/.copilot-kb16-debug         # disable
```

Two timers keep the display honest:

- `done` shows green then fades dark after `DONE_FADE_SECONDS` (4s). This is the
  bridge's own check against the file's mtime, so it does not depend on
  Hammerspoon running.
- A session file untouched for `SESSION_TTL_SECONDS` (30 min) is deleted and its
  slot freed. `SessionEnd` normally handles this, but a crashed agent never gets
  to send it and would otherwise hold an LED forever.

More than 16 concurrent agents is not representable; extras simply get no LED.

Inspect the live state with:

```bash
for f in ~/.copilot-kb16-status.d/*; do printf '%s = %s\n' "$(basename $f)" "$(cat $f)"; done
tail -f ~/Library/Logs/kb16-statusbridge.log     # logs "slot N -> status"
```

## Troubleshooting

### LEDs stopped changing after a flash

Every flash needs a replug, and that invalidates the bridge's open HID handle.
The bridge now checks each write and reconnects, logging:

```
write failed, reconnecting
connected to KB16
```

If you are running an older copy that ignored the write result, it logs
`status -> running` perfectly happily while writing to a dead handle and nothing
ever lights up. Restart it:

```bash
launchctl kickstart -k gui/$(id -u)/com.kb16.statusbridge
```

Also check `launchctl print gui/$(id -u)/com.kb16.statusbridge | grep runs` — if
`runs = 1` and the process predates your last replug, it is holding a stale
handle.

### VIA says the board isn't VIA-enabled

> KB16-01 does not seem to respond like a VIA-enabled keyboard.

Two distinct causes produce this identical message, and neither means the
firmware is broken. Query the board directly to tell them apart:

```bash
~/.venvs/kb16-bridge/bin/python - <<'EOF'
import hid
d = next(d for d in hid.enumerate(0xD010,0x1601)
         if d.get('usage_page')==0xFF60 and d.get('usage')==0x61)
h = hid.device(); h.open_path(d['path']); h.set_nonblocking(0)
h.write([0x00,0x01]+[0]*30)                  # id_get_protocol_version
r = h.read(32, timeout_ms=1000)
print('protocol version:', (r[1]<<8)|r[2] if r else 'NO RESPONSE')
EOF
```

**1. Protocol version too new.** If it prints `13`, QMK is newer than the VIA
web app supports (VIA tops out at 12) and rejects the board. `keymap.c` answers
`id_get_protocol_version` with 12 to work around this — v13 is purely additive
over v12, so nothing is lost. See the comment in `via_command_kb()`.

**2. The bridge seized the HID interface.** If the open itself fails, this
bridge is holding the device exclusively. hidapi on macOS opens with
`kIOHIDOptionsTypeSeizeDevice` by default, locking out every other client
including VIA. `allow_shared_hid_access()` in the bridge disables this via
`hid_darwin_set_open_exclusive(0)`, so both can use the board at once. As a
one-off check you can stop the bridge instead:

```bash
launchctl bootout gui/$(id -u)/com.kb16.statusbridge
```

## Reverting the flash

Yes, this is reversible. The stm32duino bootloader lives in the first 8 KB of
flash (`0x8000000`–`0x8002000`) and is never touched when flashing the
application region at `0x8002000`, so you can always re-enter DFU mode and flash
something else.

A backup of this board's original firmware is committed at
`firmware/backup/stock-kb16-rev2-alt2.bin`:

- 122880 bytes — the whole 120 KB application region (128 KB flash − 8 KB bootloader)
- read from alt setting 2, base `0x8002000`
- `sha256 ca62245db21a17a1a369c8fc2a5eb8fd4a346b06c50d15a4562d7b72478a5bdd`

It was captured with the board in DFU mode:

```bash
dfu-util -d 1eaf:0003 -a 2 -U firmware/backup/stock-kb16-rev2-alt2.bin
```

> `dfu-util` ends this read with `Error during upload (LIBUSB_ERROR_PIPE)` after
> the final block. That is the Maple bootloader failing to terminate the
> transfer cleanly, not a failed backup — verify by checking the file is 122880
> bytes and starts with a valid ARM vector table (first word `0x20000400`, a SRAM
> stack pointer; second word `0x08002239`, the reset handler).

To restore it, put the board back into DFU mode and write the same region:

```bash
dfu-util -d 1eaf:0003 -a 2 -D firmware/backup/stock-kb16-rev2-alt2.bin
```

Alternatively, flash QMK's stock keymap — but note it has **no VIA support**, so
you lose key/encoder editing:

```bash
qmk flash -kb doio/kb16/rev2 -km default
```

Flashing resets the EEPROM that stores your VIA layout, so export it from the
VIA app first — or restore the copy committed at `via/kb16-01.layout.json`.

With the bridge stopped the board returns to its normal VIA animation, since
nothing is painting the LEDs any more.

## Known limitations

- No "waiting for approval" state (Copilot has no such hook event), so
  approvals appear as `running`.
- At most 16 concurrent agents; beyond that, extra sessions get no LED.
- While the bridge runs, the VIA animation is suppressed — idle slots are
  actively painted black. Stop the bridge, or send `0xC2`, to get it back.
- Copilot CLI sends no `hook_event_name`, so its sessions cannot be detected
  ending and are reclaimed by the 30-minute TTL instead of immediately.
- `RGB_MATRIX_LED_COUNT` must match the board (16); both revisions define this.
