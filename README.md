# DOIO KB16-01 → GitHub Copilot CLI Command Center

Turn a **DOIO KB16-01** macro pad into a control surface for **GitHub Copilot CLI** on **macOS + iTerm2**, with
**Codex-Micro-style live status lighting** — one key LED per running agent.

Two status options, pick either or both:

| | Variant A — keyboard LEDs | Variant B — menu-bar dot |
|---|---|---|
| Shows | **one LED per concurrent agent** | one merged status |
| Needs | custom QMK firmware (flashing) | Hammerspoon only |
| Setup | VIA + Hammerspoon + hooks + bridge | VIA + Hammerspoon + hooks |

Key and encoder control needs **no custom firmware** — that runs entirely through
**VIA** + **Hammerspoon** + **Copilot CLI hooks**.

---

## Table of contents

- [What this does](#what-this-does)
- [Hardware](#hardware)
- [Architecture](#architecture)
- [Key map](#key-map)
- [Encoders](#encoders)
- [Live status](#live-status)
- [Installation](#installation)
- [Troubleshooting](#troubleshooting)
- [Repo layout](#repo-layout)
- [Design decisions & safety](#design-decisions--safety)

---

## What this does

- 16 keys drive Copilot CLI slash-commands and terminal control inside iTerm2.
- 3 rotary encoders scroll, navigate tabs, and control volume.
- **Each key LED tracks one Copilot agent** (idle / thinking / running / done /
  error), so several concurrent sessions are visible at a glance — inspired by
  the Work Louder **Codex Micro**. Idle is dark: the board shows activity, never
  inactivity.
- Works with both **Copilot CLI** and **VS Code Copilot Chat**, each session
  getting its own LED.
- An optional menu-bar dot can mirror a single merged status.

---

## Hardware

| Property     | Value             |
| ------------ | ----------------- |
| Device       | DOIO KB16-01      |
| Vendor ID    | `0xD010`          |
| Product ID   | `0x1601`          |
| Firmware     | QMK (VIA V2)      |
| Layout       | 16 keys, 3 encoders, 16-LED `rgb_matrix` |
| Matrix       | 4 rows × 5 cols   |

### Two hardware revisions, same name

The KB16-01 ships with two completely different MCUs, and **both report the same
USB VID/PID and product string in normal mode**. You cannot tell them apart while
the keyboard is running — only from the bootloader:

| `dfu-util -l` reports | Revision | MCU | QMK target | Flash tool |
|---|---|---|---|---|
| `[1eaf:0003] STM32duino bootloader` | **rev2** | STM32F103, 128 KB | `doio/kb16/rev2` | `dfu-util` |
| nothing; `dfu-programmer atmega32u4 get` answers | **rev1** | ATmega32U4, 32 KB | `doio/kb16/rev1` | `dfu-programmer` |

This only matters for Variant A. Check before flashing — firmware built for the
wrong MCU will not run.

VIA definition: `via/kb16-01.json` (from
[the-via/keyboards](https://github.com/the-via/keyboards/blob/master/src/doio/kb16/kb16-01.json)).
Load it in VIA with **"Use V2 definitions (deprecated)"** enabled.
`via/kb16-01.layout.json` is a saved key layout you can restore with VIA's
**Load Saved Layout** — flashing resets the keymap stored in EEPROM.

---

## Architecture

```
┌──────────────┐   Hyper/keycodes   ┌─────────────┐   keystrokes    ┌────────────┐
│  KB16-01     │ ─────────────────► │ macOS +     │ ──────────────► │  iTerm2 /  │
│  (QMK/VIA)   │                    │ Hammerspoon │                 │ Copilot CLI│
└──────▲───────┘                    └─────────────┘                 └─────┬──────┘
       │ Raw HID                                                          │ hooks
       │ [0xC1, slot, status]                                             ▼
┌──────┴───────┐   one file per session   ┌────────────────────────────────────┐
│ status bridge│ ◄──────────────────────  │ ~/.copilot-kb16-status.d/<uuid>    │
│ (LaunchAgent)│                          │ ~/.copilot-kb16-status  (aggregate)│
└──────────────┘                          └──────────────┬─────────────────────┘
                                                         │ optional
                                           menu-bar dot ◄─┘
```

- **Keys → Copilot:** VIA sends Hyper combos; Hammerspoon types the matching
  slash-command into iTerm (commands are **not** auto-submitted — you press the
  KB16 Enter key to run them).
- **Copilot → LEDs:** hooks write one status file per agent session, keyed by
  session UUID. The bridge assigns each session an LED slot and pushes changes
  over Raw HID.
- **Copilot → dot (optional):** the same hooks also write a single aggregate
  status word that Hammerspoon can poll.

---

## Key map

`Hyper` = `Ctrl+Alt+Cmd+Shift` (chosen to avoid clashing with native macOS
functions like F13–F24 brightness/media keys).

```
┌──────────┬──────────┬──────────┬──────────┐
│  Esc     │  Ctrl+C  │  Enter   │ Shift+Tab│   Row 1  (raw keycodes)
├──────────┼──────────┼──────────┼──────────┤
│  iTerm   │ /model   │ /context │ /diff    │   Row 2  (Hyper+1..4)
├──────────┼──────────┼──────────┼──────────┤
│ /compact │ /review  │ /plan    │ /new     │   Row 3  (Hyper+5..8)
├──────────┼──────────┼──────────┼──────────┤
│ /resume  │ /copy    │ /undo    │ /help    │   Row 4  (Hyper+9,0,-,=)
└──────────┴──────────┴──────────┴──────────┘
```

### VIA keycodes (entered via the **Any** field)

| Position         | Function        | VIA keycode         |
| ---------------- | --------------- | ------------------- |
| Row 1 · 1        | Esc / cancel    | `KC_ESC`            |
| Row 1 · 2        | Ctrl+C (SIGINT) | `LCTL(KC_C)`        |
| Row 1 · 3        | Enter / submit  | `KC_ENTER`          |
| Row 1 · 4        | Copilot mode    | `LSFT(KC_TAB)`      |
| Row 2 · 1        | Focus iTerm     | `HYPR(KC_1)`        |
| Row 2 · 2        | `/model`        | `HYPR(KC_2)`        |
| Row 2 · 3        | `/context`      | `HYPR(KC_3)`        |
| Row 2 · 4        | `/diff`         | `HYPR(KC_4)`        |
| Row 3 · 1        | `/compact`      | `HYPR(KC_5)`        |
| Row 3 · 2        | `/review`       | `HYPR(KC_6)`        |
| Row 3 · 3        | `/plan`         | `HYPR(KC_7)`        |
| Row 3 · 4        | `/new`          | `HYPR(KC_8)`        |
| Row 4 · 1        | `/resume`       | `HYPR(KC_9)`        |
| Row 4 · 2        | `/copy`         | `HYPR(KC_0)`        |
| Row 4 · 3        | `/undo`         | `HYPR(KC_MINS)`     |
| Row 4 · 4        | `/help`         | `HYPR(KC_EQL)`      |

> Row 1 keys work as pure keystrokes and do **not** need Hammerspoon.
> Rows 2–4 rely on Hammerspoon to translate the Hyper combo into a typed command.

---

## Encoders

| Encoder | Rotate CCW | Rotate CW  | Click            |
| ------- | ---------- | ---------- | ---------------- |
| E1 (L)  | `KC_UP`    | `KC_DOWN`  | `KC_ENTER`       |
| E2 (M)  | `KC_PGUP`  | `KC_PGDN`  | `LSFT(KC_TAB)`   |
| E3 (R)  | `HYPR(KC_P)`  | `HYPR(KC_N)`  | see below        |

**E3 also handles iTerm tab switching** via Hyper combos mapped to custom iTerm
key bindings:

- `HYPR(KC_N)` → iTerm **Next Tab** (bind `Hyper+N` to "Next Tab" in iTerm)
- `HYPR(KC_P)` → iTerm **Previous Tab** (bind `Hyper+P` to "Previous Tab" in iTerm)

> iTerm's default `Cmd+→` / `Ctrl+Tab` proved unreliable when injected via HID,
> so we bind dedicated Hyper shortcuts inside iTerm instead. See
> [Troubleshooting](#troubleshooting).

---

## Live status

### Keyboard LEDs (Variant A)

Each of the 16 key LEDs is an independent **agent slot**, assigned per Copilot
session and held for that session's life. Slots fill from the top-left,
row-major:

```
┌──────┐┌──────┐┌──────┐┌──────┐
│ sl 0 ││ sl 1 ││ sl 2 ││ sl 3 │
├──────┤├──────┤├──────┤├──────┤
│ sl 4 ││ sl 5 ││ sl 6 ││ sl 7 │
├──────┤├──────┤├──────┤├──────┤
│ sl 8 ││ sl 9 ││ sl10 ││ sl11 │
├──────┤├──────┤├──────┤├──────┤
│ sl12 ││ sl13 ││ sl14 ││ sl15 │
└──────┘└──────┘└──────┘└──────┘
```

| LED      | Status     | Trigger (Copilot hook)      |
| -------- | ---------- | --------------------------- |
| off      | `idle`     | `sessionStart` / `sessionEnd` |
| blue     | `thinking` | `userPromptSubmitted`, `postToolUse` |
| yellow   | `running`  | `preToolUse`                |
| green    | `done`     | `agentStop` (fades dark after 4s) |
| red      | `error`    | `errorOccurred`             |

Idle slots are driven to **black**, so the board stays dark unless something is
running. This suppresses the VIA animation while the bridge is active — stop the
bridge to get it back. Setup and protocol details:
[`firmware/README.md`](firmware/README.md).

### Menu-bar dot (Variant B, optional)

A single dot showing one merged status, in the same colours. Redundant if you
have the LEDs, since it cannot distinguish concurrent agents. Append
`hammerspoon/codex-status.lua` to enable it.

> **Note:** Copilot has no dedicated "waiting for approval" hook event.
> `preToolUse` fires before the approval prompt, so approvals show as `running`.

---

## Installation

### 1. VIA (key + encoder mapping)

1. Connect the KB16-01 via USB.
2. Open <https://usevia.app> in Chrome/Edge.
3. In VIA settings, enable **"Use V2 definitions (deprecated)"**.
4. Load `via/kb16-01.json` (Design tab), then go to **Configure**.
5. Set each key/encoder using the **Any** field per the tables above.
6. In iTerm, bind `Hyper+N` → **Next Tab** and `Hyper+P` → **Previous Tab**
   (Settings → Keys → Key Bindings → +).

### 2. Copilot CLI hooks

```bash
mkdir -p ~/.copilot/hooks
cp copilot/copilot-status.sh ~/.copilot/hooks/
cp copilot/kb16-status.json  ~/.copilot/hooks/
chmod +x ~/.copilot/hooks/copilot-status.sh
```

### 3. Hammerspoon

Install Hammerspoon and grant Accessibility permission
(System Settings → Privacy & Security → Accessibility).

```bash
brew install --cask hammerspoon
```

Append the key bindings to `~/.hammerspoon/init.lua`:

```bash
cat hammerspoon/init-keys.lua >> ~/.hammerspoon/init.lua
```

`hammerspoon/codex-status.lua` adds an **optional** menubar status dot. It is not
needed if you have the firmware LEDs (Variant A): the keyboard shows every
concurrent agent separately, whereas the dot can only ever show one merged
status. Append it only if you want the dot as well:

```bash
cat hammerspoon/codex-status.lua >> ~/.hammerspoon/init.lua   # optional
```

Then choose **Reload Config** from the Hammerspoon menu.

> ⚠️ Hammerspoon never re-reads `init.lua` on its own. If it was already running
> when you appended these files, it keeps executing the **old** config
> indefinitely and the dot silently stays grey — the config on disk looks
> perfectly correct the whole time. Compare the two if the dot never changes:
>
> ```bash
> ps -p $(pgrep -x Hammerspoon) -o lstart=   # when it started
> stat -f '%Sm' ~/.hammerspoon/init.lua      # when the config last changed
> ```
>
> `codex-status.lua` loads `hs.ipc`, so after the first manual reload you can
> script it: `hs -c 'hs.reload()'`.

### 4. Keyboard LEDs (Variant A, optional)

Build and flash the firmware, then run the status bridge. Full guide:
[`firmware/README.md`](firmware/README.md). **Check your board revision first** —
see [Hardware](#hardware).

### 5. Verify

```bash
# hooks are writing per-session state
ls ~/.copilot-kb16-status.d/

# the bridge is running and assigning slots
launchctl print gui/$(id -u)/com.kb16.statusbridge | grep -E 'state =|pid ='
tail -f ~/Library/Logs/kb16-statusbridge.log      # logs "slot N -> status"

# drive the LEDs directly, bypassing the hooks
~/.venvs/kb16-bridge/bin/python bridge/kb16_status_bridge.py running  # all keys yellow
~/.venvs/kb16-bridge/bin/python bridge/kb16_status_bridge.py idle     # all keys off

# menu-bar dot, if installed
echo running > ~/.copilot-kb16-status
echo idle    > ~/.copilot-kb16-status
```

---

## Troubleshooting

| Symptom | Fix |
| ------- | --- |
| VIA can't load the JSON | Enable **"Use V2 definitions (deprecated)"** first. |
| VIA: *"does not seem to respond like a VIA-enabled keyboard"* | Either the firmware reports VIA protocol 13 (newer than VIA supports), or the bridge has seized the HID interface. Both are covered in [`firmware/README.md`](firmware/README.md). |
| LEDs stopped changing after a flash | Every flash needs a replug, which invalidates the bridge's HID handle. It now reconnects automatically; restart it with `launchctl kickstart -k gui/$(id -u)/com.kb16.statusbridge`. |
| LEDs work in VS Code but not Copilot CLI | The two send different JSON field names (`session_id` vs `sessionId`). Fixed in `copilot/copilot-status.sh`; make sure `~/.copilot/hooks/` has the current copy. |
| Menu-bar dot never changes | Hammerspoon does not re-read `init.lua` by itself. Compare `ps -p $(pgrep -x Hammerspoon) -o lstart=` with `stat -f '%Sm' ~/.hammerspoon/init.lua`, then reload. |
| Keys stopped working after flashing | Flashing resets the VIA keymap in EEPROM. Restore `via/kb16-01.layout.json` with VIA's **Load Saved Layout**. |
| F14/F15 dim the screen | Use the Hyper combos in this repo, not raw F13–F24. |
| Status never changes at all | Check `~/.copilot/hooks/*.json` exists and `copilot-status.sh` is `+x`. Enable payload capture with `touch ~/.copilot-kb16-debug`. |
| `Ctrl+Tab` only bounces 2 tabs | That's iTerm's MRU cycle. Use dedicated `Hyper+N`/`Hyper+P` bound to Next/Previous Tab. |
| `Cmd+→` tab switch ignored | Cmd+Arrow injected via HID is unreliable; bind a Hyper shortcut in iTerm instead. |
| Slash keys type outside iTerm | By design — Hammerspoon only types when iTerm is frontmost, otherwise it shows an alert. |

---

## Repo layout

```
kb16-copilot/
├── README.md
├── via/
│   ├── kb16-01.json             # VIA V2 keyboard definition
│   └── kb16-01.layout.json      # saved key layout (restore after flashing)
├── hammerspoon/
│   ├── init-keys.lua            # KB16 → Copilot key bindings (Hyper)
│   └── codex-status.lua         # optional menu-bar status poller
├── copilot/
│   ├── copilot-status.sh        # hook script → per-session + aggregate status
│   └── kb16-status.json         # Copilot hook definitions
├── firmware/                    # Variant A: VIA + Raw HID status LEDs
│   ├── README.md                # build, flash, protocol & troubleshooting
│   ├── backup/                  # this board's original firmware (restorable)
│   └── kb16_status_via/
│       ├── keymap.c             # VIA keymap + Raw HID + per-agent RGB overlay
│       ├── keymap.json
│       └── rules.mk
└── bridge/                      # host → KB16 Raw HID status pusher
    ├── kb16_status_bridge.py    # one-shot + --watch (per-agent slots)
    ├── kb16-status-bridge       # wrapper so the login item has a real name
    ├── requirements.txt
    └── com.kb16.statusbridge.plist
```

---

## Design decisions & safety

- **Hyper key** avoids all macOS F13–F24 / media-key conflicts.
- **Commands are never auto-submitted.** The KB16 types the slash-command; you
  review it and press the KB16 Enter key to run it. Prevents accidental execution.
- **No key is mapped to `--allow-all-tools`** or any permanent approval, so a
  stray keypress can never silently grant shell access.
- **Keys and encoders need no firmware flashing** — VIA keeps the pad
  reconfigurable at any time. Only the status LEDs (Variant A) need custom
  firmware, and the original is backed up in `firmware/backup/` so the flash is
  reversible.
- **Session IDs are validated** before use as filenames, so a malformed or
  hostile one cannot escape the status directory.
- The status files are **tool-agnostic**: anything that writes a status word to
  `~/.copilot-kb16-status.d/<id>` (or the aggregate file) can drive the lights.
- **LEDs indicate activity, never inactivity** — an idle board is a dark board.

---

## License

MIT — do whatever you like. Attribution appreciated but not required.
