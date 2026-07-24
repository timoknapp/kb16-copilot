# Variant A2 — VIA + Raw HID status LEDs on the KB16-01

This adds **real per-key RGB status feedback** on the pad itself (like the Codex
Micro), while **keeping VIA** for key/encoder editing. It requires building and
flashing custom QMK firmware.

> ⚠️ This has **not** been tested end-to-end on real hardware by the author of
> these files. The firmware and bridge are written against the official QMK
> `doio/kb16/rev1` sources and the documented Raw HID API, and validated for
> syntax, but **you perform the first compile and flash**. DFU recovery is
> possible if a flash goes wrong.

## What you get

- 16 per-key LEDs tint to the Copilot status:
  - idle → normal VIA animation (untouched)
  - thinking → blue
  - running → yellow
  - done → green
  - error → red
- VIA still edits your key/encoder map.
- The menu-bar dot (Variant B) keeps working in parallel.

## Prerequisites

- A working **QMK build environment**:
  ```bash
  brew install qmk/qmk/qmk
  qmk setup            # clones qmk_firmware, installs toolchain
  ```
- Python `hid` for the bridge:
  ```bash
  python3 -m pip install -r bridge/requirements.txt
  ```

## 1. Add the keymap to QMK

Copy the keymap into your local qmk_firmware checkout:

```bash
QMK=~/qmk_firmware   # wherever `qmk setup` put it
mkdir -p "$QMK/keyboards/doio/kb16/rev1/keymaps/kb16_status_via"
cp firmware/kb16_status_via/keymap.c    "$QMK/keyboards/doio/kb16/rev1/keymaps/kb16_status_via/"
cp firmware/kb16_status_via/rules.mk    "$QMK/keyboards/doio/kb16/rev1/keymaps/kb16_status_via/"
```

## 2. Compile

```bash
qmk compile -kb doio/kb16/rev1 -km kb16_status_via
```

This produces a `.hex` in the qmk_firmware root.

## 3. Flash (DFU)

The KB16-01 uses `atmel-dfu`. Put the board into bootloader mode
(hold the reset/boot key or short the reset pads — see the DOIO manual), then:

```bash
qmk flash -kb doio/kb16/rev1 -km kb16_status_via
```

After flashing, re-open VIA — your key map is still editable. If VIA doesn't
detect it, re-load `via/kb16-01.json` (V2 definitions enabled).

## 4. Run the status bridge

Test one-shot (board plugged in):

```bash
python3 bridge/kb16_status_bridge.py running   # LEDs go yellow
python3 bridge/kb16_status_bridge.py idle       # back to normal animation
```

Run it as a watcher so it follows the same status file the menu bar uses:

```bash
python3 bridge/kb16_status_bridge.py --watch
```

To keep it always running, edit the paths in
`bridge/com.kb16.statusbridge.plist` and:

```bash
cp bridge/com.kb16.statusbridge.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.kb16.statusbridge.plist
```

The existing Copilot hooks already write the status file, so no hook changes are
needed — the bridge and the menu bar both read `~/.copilot-kb16-status`.

## Raw HID protocol

```
report bytes = [0x00, 0x01, status]
  0x00   report ID (platform padding)
  0x01   command: set status
  status 0=idle 1=thinking 2=running 3=done 4=error
```

## Reverting to plain VIA

Flash the stock DOIO/VIA firmware again (or any `via` keymap):

```bash
qmk flash -kb doio/kb16/rev1 -km via
```

## Known limitations

- No "waiting for approval" state (Copilot has no such hook event).
- LED tint currently colors **all** keys. To light only specific keys, edit the
  loop in `keymap.c` (`rgb_matrix_indicators_user`) to target LED indices.
- `RGB_MATRIX_LED_COUNT` must match the board (16); the stock rev1 defines this.
