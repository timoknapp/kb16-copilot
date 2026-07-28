/* Copyright 2026
 * DOIO KB16-01 (rev2) VIA keymap + Raw HID per-agent status LEDs.
 *
 * This keymap keeps full VIA support AND adds a Raw HID channel so a host
 * bridge can push Copilot CLI status. Each of the 16 per-key RGB LEDs is an
 * independent "agent slot", so several concurrent sessions are visible at once:
 *   0 idle=off  1 thinking=blue  2 running=yellow  3 done=green  4 error=red
 *
 * Idle slots are driven to black rather than left alone, so the board stays
 * dark unless something is actually happening -- the LEDs indicate activity,
 * never inactivity.
 *
 * VIA still owns the actual key/encoder assignments; this file only provides
 * default layers and the RGB status overlay.
 */

#include QMK_KEYBOARD_H
#include "raw_hid.h"
#include "via.h"

// Custom Raw HID command bytes. These must stay outside VIA's reserved command
// IDs (0x01-0x15 and 0xFF, see enum via_command_id in quantum/via.h) so that
// intercepting them never shadows a real VIA command.
#define KB16_CMD_SET_STATUS 0xC0 // [0xC0, status]       set every slot at once
#define KB16_CMD_SET_AGENT  0xC1 // [0xC1, slot, status] set one agent slot
#define KB16_CMD_CLEAR      0xC2 // [0xC2]               all slots back to idle

// Layer whose 16 keys select an agent (MEH+A..P, handled by Hammerspoon).
// Reached with OSL(1) on the large bottom encoder push.
#define KB16_AGENT_LAYER 1

// ---- Status state (set via Raw HID) ----------------------------------------
enum copilot_status {
    ST_IDLE     = 0,
    ST_THINKING = 1,
    ST_RUNNING  = 2,
    ST_DONE     = 3,
    ST_ERROR    = 4,
};

// One status per LED. Index == agent slot == RGB matrix LED index, which for
// this board is row-major from the top-left key.
static uint8_t agent_status[RGB_MATRIX_LED_COUNT] = {0};

// ---- Keymap (VIA-editable; these are just defaults) ------------------------
// LAYOUT takes 19 positions in info.json order, and the encoder push switches
// sit at column 4 -- i.e. *interleaved* at positions 4, 9 and 14, not appended
// at the end. Getting that wrong shifts the whole board by one key, which only
// becomes visible after an EEPROM reset.
const uint16_t PROGMEM keymaps[][MATRIX_ROWS][MATRIX_COLS] = {
    // Layer 0: control. Matches via/kb16-01.layout.json.
    [0] = LAYOUT(
    //  col 0        col 1        col 2         col 3          encoder push
        KC_ESC,      LCTL(KC_C),  KC_ENTER,     KC_TAB,        KC_ENTER,
        HYPR(KC_1),  HYPR(KC_2),  HYPR(KC_3),   HYPR(KC_4),    KC_MUTE,
        HYPR(KC_5),  HYPR(KC_6),  HYPR(KC_7),   HYPR(KC_8),    OSL(KB16_AGENT_LAYER),
        HYPR(KC_9),  HYPR(KC_0),  HYPR(KC_MINS),HYPR(KC_EQL)
    ),
    // Layer 1: agent jump. Each key selects the agent in the matching LED slot;
    // Hammerspoon maps MEH+A..P to "focus that session's window". Meh rather
    // than Hyper because Hyper+N / Hyper+P are already iTerm tab switching.
    [1] = LAYOUT(
        MEH(KC_A),   MEH(KC_B),   MEH(KC_C),    MEH(KC_D),     _______,
        MEH(KC_E),   MEH(KC_F),   MEH(KC_G),    MEH(KC_H),     _______,
        MEH(KC_I),   MEH(KC_J),   MEH(KC_K),    MEH(KC_L),     _______,
        MEH(KC_M),   MEH(KC_N),   MEH(KC_O),    MEH(KC_P)
    ),
    [2] = LAYOUT(
        _______, _______, _______, _______, _______,
        _______, _______, _______, _______, _______,
        _______, _______, _______, _______, _______,
        _______, _______, _______, _______
    ),
    [3] = LAYOUT(
        _______, _______, _______, _______, _______,
        _______, _______, _______, _______, _______,
        _______, _______, _______, _______, _______,
        _______, _______, _______, _______
    ),
};

#if defined(ENCODER_MAP_ENABLE)
const uint16_t PROGMEM encoder_map[][NUM_ENCODERS][NUM_DIRECTIONS] = {
    [0] = { ENCODER_CCW_CW(KC_UP, KC_DOWN),
            ENCODER_CCW_CW(KC_PGUP, KC_PGDN),
            ENCODER_CCW_CW(KC_VOLD, KC_VOLU) },
    [1] = { ENCODER_CCW_CW(_______, _______), ENCODER_CCW_CW(_______, _______), ENCODER_CCW_CW(_______, _______) },
    [2] = { ENCODER_CCW_CW(_______, _______), ENCODER_CCW_CW(_______, _______), ENCODER_CCW_CW(_______, _______) },
    [3] = { ENCODER_CCW_CW(_______, _______), ENCODER_CCW_CW(_______, _______), ENCODER_CCW_CW(_______, _______) },
};
#endif

// ---- Raw HID: receive agent status from the host ---------------------------
// With VIA_ENABLE, quantum/via.c owns raw_hid_receive(), so we hook the weak
// via_command_kb() instead. Returning true means "fully handled, including the
// raw_hid_send() reply"; returning false lets VIA process the report normally.
bool via_command_kb(uint8_t *data, uint8_t length) {
    // [0xC0, status] -- set every slot. Used by the one-shot CLI and to reset.
    if (length >= 2 && data[0] == KB16_CMD_SET_STATUS) {
        if (data[1] <= ST_ERROR) {
            for (uint8_t i = 0; i < RGB_MATRIX_LED_COUNT; i++) {
                agent_status[i] = data[1];
            }
        }
        raw_hid_send(data, length); // echo so the host can confirm delivery
        return true;
    }

    // [0xC1, slot, status] -- set a single agent's LED.
    if (length >= 3 && data[0] == KB16_CMD_SET_AGENT) {
        if (data[1] < RGB_MATRIX_LED_COUNT && data[2] <= ST_ERROR) {
            agent_status[data[1]] = data[2];
        }
        raw_hid_send(data, length);
        return true;
    }

    // [0xC2] -- all slots back to idle (board goes dark).
    if (length >= 1 && data[0] == KB16_CMD_CLEAR) {
        for (uint8_t i = 0; i < RGB_MATRIX_LED_COUNT; i++) {
            agent_status[i] = ST_IDLE;
        }
        raw_hid_send(data, length);
        return true;
    }

    // QMK reports VIA_PROTOCOL_VERSION 0x000D (v13), but the VIA web app only
    // supports up to 0x000C (v12) and rejects anything newer with "does not
    // seem to respond like a VIA-enabled keyboard". v13 is purely additive over
    // v12 -- it only adds the id_keycodes_version (0x06) keyboard-value ID and
    // changes no existing command -- so answering 12 is safe: a v12 client
    // never asks for the one thing that differs.
    //
    // via.h hard-#defines VIA_PROTOCOL_VERSION with no #ifndef guard, so it
    // cannot be overridden from config.h. via_command_kb() is consulted before
    // via.c's own switch, which makes this the only override point that does
    // not require patching the QMK tree. Remove once VIA supports v13.
    if (length >= 3 && data[0] == id_get_protocol_version) {
        data[1] = 0x00;
        data[2] = 0x0C;
        raw_hid_send(data, length);
        return true;
    }

    return false;
}

// ---- RGB overlay: one LED per agent ----------------------------------------
// Runs after the active VIA animation and repaints every LED, so the board
// shows activity and nothing else: an idle slot is driven to black rather than
// left showing the underlying animation.
//
// The one exception is the agent layer, where idle slots glow faintly. That is
// the only feedback that you are in select mode, and it shows which keys are
// selectable at all -- without it an empty board looks identical on both
// layers.
bool rgb_matrix_indicators_user(void) {
    bool agent_layer = get_highest_layer(layer_state) == KB16_AGENT_LAYER;

    for (uint8_t i = 0; i < RGB_MATRIX_LED_COUNT; i++) {
        uint8_t r = 0, g = 0, b = 0; // idle -> off
        switch (agent_status[i]) {
            case ST_THINKING: r = 20;  g = 90;  b = 255; break; // blue
            case ST_RUNNING:  r = 255; g = 170; b = 0;   break; // yellow
            case ST_DONE:     r = 30;  g = 200; b = 90;  break; // green
            case ST_ERROR:    r = 240; g = 40;  b = 40;  break; // red
            default:
                if (agent_layer) {
                    r = 12; g = 12; b = 12; // dim white: free but selectable
                }
                break;
        }
        rgb_matrix_set_color(i, r, g, b);
    }
    return false;
}
