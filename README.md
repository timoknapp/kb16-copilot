# DOIO KB16-01 → GitHub Copilot CLI Command Center

Turn a **DOIO KB16-01** macro pad into a control surface for **GitHub Copilot CLI** on **macOS + iTerm2**, complete with a
**Codex-Micro-style live status light** in the macOS menu bar.

No custom firmware required — everything runs through **VIA** + **Hammerspoon** +
**Copilot CLI hooks**.

---

## Table of contents

- [What this does](#what-this-does)
- [Hardware](#hardware)
- [Architecture](#architecture)
- [Key map](#key-map)
- [Encoders](#encoders)
- [Live status light](#live-status-light)
- [Installation](#installation)
- [Troubleshooting](#troubleshooting)
- [Repo layout](#repo-layout)
- [Design decisions & safety](#design-decisions--safety)
- [Future work (Variant A)](#future-work-variant-a)

---

## What this does

- 16 keys drive Copilot CLI slash-commands and terminal control inside iTerm2.
- 3 rotary encoders scroll, navigate tabs, and control volume.
- A menu-bar dot mirrors Copilot's live state (idle / thinking / running / done / error),
  inspired by the Work Louder **Codex Micro**.
- Works identically whether you launch `copilot` directly.

---

## Hardware

| Property     | Value             |
| ------------ | ----------------- |
| Device       | DOIO KB16-01      |
| Vendor ID    | `0xD010`          |
| Product ID   | `0x1601`          |
| Firmware     | QMK (VIA V2)      |
| Layout       | 16 keys, 3 encoders, RGB underglow |
| Matrix       | 4 rows × 5 cols   |

VIA definition: `via/kb16-01.json` (from
[the-via/keyboards](https://github.com/the-via/keyboards/blob/master/src/doio/kb16/kb16-01.json)).
Load it in VIA with **"Use V2 definitions (deprecated)"** enabled.

---

## Architecture

```
┌──────────────┐   Hyper/keycodes   ┌─────────────┐   keystrokes    ┌────────────┐
│  KB16-01     │ ─────────────────► │ macOS +     │ ──────────────► │  iTerm2 /  │
│  (QMK/VIA)   │                    │ Hammerspoon │                 │ Copilot CLI│
└──────────────┘                    └─────────────┘                 └─────┬──────┘
                                                                          │ hooks
                        ┌──────────────────────────┐   status word       │
   menu-bar dot  ◄──────│ Hammerspoon status poller│ ◄───── file ────────┘
                        └──────────────────────────┘   ~/.copilot-kb16-status
```

- **Keys → Copilot:** VIA sends Hyper combos; Hammerspoon types the matching
  slash-command into iTerm (commands are **not** auto-submitted — you press the
  KB16 Enter key to run them).
- **Copilot → status light:** Copilot CLI hooks write a status word to
  `~/.copilot-kb16-status`; Hammerspoon polls it and recolors a menu-bar dot.

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

## Live status light

A colored dot in the macOS menu bar reflects Copilot's current state.

| Dot      | Status     | Trigger (Copilot hook)      |
| -------- | ---------- | --------------------------- |
| ● grey   | `idle`     | `sessionStart` / `sessionEnd` |
| ● blue   | `thinking` | `userPromptSubmitted`, `postToolUse` |
| ● yellow | `running`  | `preToolUse`                |
| ● green  | `done`     | `agentStop` (fades to idle after 4s) |
| ● red    | `error`    | `errorOccurred`             |

> **Note:** Copilot CLI has no dedicated "waiting for approval" hook event.
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
needed if you have the firmware LEDs (Variant A2): the keyboard shows every
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

### 4. Verify

```bash
echo running > ~/.copilot-kb16-status   # dot turns yellow
echo idle    > ~/.copilot-kb16-status   # dot turns grey
copilot                                 # send a prompt, watch the dot cycle
```

---

## Troubleshooting

| Symptom | Fix |
| ------- | --- |
| VIA can't load the JSON | Enable **"Use V2 definitions (deprecated)"** first. |
| F14/F15 dim the screen | Use the Hyper combos in this repo, not raw F13–F24. |
| Status dot never changes | Check `~/.copilot/hooks/*.json` exists and `copilot-status.sh` is `+x`. Test: `echo done > ~/.copilot-kb16-status`. |
| `Ctrl+Tab` only bounces 2 tabs | That's iTerm's MRU cycle. Use dedicated `Hyper+N`/`Hyper+P` bound to Next/Previous Tab. |
| `Cmd+→` tab switch ignored | Cmd+Arrow injected via HID is unreliable; bind a Hyper shortcut in iTerm instead. |
| Slash keys type outside iTerm | By design — Hammerspoon only types when iTerm is frontmost, otherwise it shows an alert. |

---

## Repo layout

```
kb16-copilot-setup/
├── README.md
├── via/
│   └── kb16-01.json            # VIA V2 keyboard definition
├── hammerspoon/
│   ├── init-keys.lua           # KB16 → Copilot key bindings (Hyper)
│   └── codex-status.lua        # menu-bar status poller
├── copilot/
│   ├── copilot-status.sh       # hook script → writes status word
│   └── kb16-status.json        # Copilot CLI hook definitions
├── firmware/                   # Variant A2: VIA + Raw HID status LEDs
│   ├── README.md               # build & flash guide
│   └── kb16_status_via/
│       ├── keymap.c            # VIA keymap + Raw HID + RGB status overlay
│       ├── keymap.json
│       └── rules.mk
└── bridge/                     # host → KB16 Raw HID status pusher
    ├── kb16_status_bridge.py   # one-shot + --watch modes
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
- **No firmware flashing** — VIA keeps the pad reconfigurable at any time.
- The status file is **tool-agnostic**: anything that can write a status word to
  `~/.copilot-kb16-status` can drive the light.

---

## Future work (Variant A)

True per-key RGB feedback on the pad (like the Codex Micro, where each Agent key
glows with live status) is **implemented in Variant A2** — see
[`firmware/README.md`](firmware/README.md). It keeps VIA editing and adds a Raw
HID channel that a host bridge (`bridge/kb16_status_bridge.py`) uses to tint the
16 per-key LEDs by Copilot status.

Requires building/flashing custom QMK firmware. Verified end-to-end on a KB16-01
**rev2** (STM32F103, stm32duino bootloader); a backup of the original firmware
is in `firmware/backup/`. Both revisions expose a `ws2812` **rgb_matrix** with 16
per-key LEDs, so per-key status coloring is fully supported.

Trade-off vs. the menu-bar approach (Variant B): more setup and a firmware
flash, but the status is visible on the keys themselves.

---

## License

MIT — do whatever you like. Attribution appreciated but not required.
