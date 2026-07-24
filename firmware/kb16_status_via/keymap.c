/* Copyright 2026
 * DOIO KB16-01 (rev1) VIA keymap + Raw HID status LEDs.
 *
 * This keymap keeps full VIA support AND adds a Raw HID channel so a host
 * bridge can push a Copilot CLI status, which tints the 16 per-key RGB LEDs:
 *   0 idle=off/dim  1 thinking=blue  2 running=yellow  3 done=green  4 error=red
 *
 * VIA still owns the actual key/encoder assignments; this file only provides
 * default layers and the RGB status overlay.
 */

#include QMK_KEYBOARD_H
#include "raw_hid.h"

// ---- Status state (set via Raw HID) ----------------------------------------
enum copilot_status {
    ST_IDLE     = 0,
    ST_THINKING = 1,
    ST_RUNNING  = 2,
    ST_DONE     = 3,
    ST_ERROR    = 4,
};

static uint8_t copilot_status = ST_IDLE;

// ---- Keymap (VIA-editable; these are just defaults) ------------------------
// Layout order matches info.json LAYOUT: 4x4 keys + 3 encoder push keys.
const uint16_t PROGMEM keymaps[][MATRIX_ROWS][MATRIX_COLS] = {
    [0] = LAYOUT(
        KC_ESC,  LCTL(KC_C), KC_ENTER, LSFT(KC_TAB),
        HYPR(KC_1), HYPR(KC_2), HYPR(KC_3), HYPR(KC_4),
        HYPR(KC_5), HYPR(KC_6), HYPR(KC_7), HYPR(KC_8),
        HYPR(KC_9), HYPR(KC_0), HYPR(KC_MINS), HYPR(KC_EQL),
        // encoder push keys (E1, E2, E3):
        KC_ENTER, LSFT(KC_TAB), KC_MUTE
    ),
    [1] = LAYOUT(
        _______, _______, _______, _______,
        _______, _______, _______, _______,
        _______, _______, _______, _______,
        _______, _______, _______, _______,
        _______, _______, _______
    ),
    [2] = LAYOUT(
        _______, _______, _______, _______,
        _______, _______, _______, _______,
        _______, _______, _______, _______,
        _______, _______, _______, _______,
        _______, _______, _______
    ),
    [3] = LAYOUT(
        _______, _______, _______, _______,
        _______, _______, _______, _______,
        _______, _______, _______, _______,
        _______, _______, _______, _______,
        _______, _______, _______
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

// ---- Raw HID: receive a 1-byte status from the host ------------------------
// Protocol: byte[0] = command (0x01 = set status), byte[1] = status value.
void raw_hid_receive(uint8_t *data, uint8_t length) {
    if (length >= 2 && data[0] == 0x01) {
        if (data[1] <= ST_ERROR) {
            copilot_status = data[1];
        }
    }
    // Echo back so the host can confirm delivery.
    raw_hid_send(data, length);
}

// ---- RGB overlay: tint all keys by status ----------------------------------
// Runs after the active VIA animation; when status != idle it overrides colors.
bool rgb_matrix_indicators_user(void) {
    uint8_t r = 0, g = 0, b = 0;
    switch (copilot_status) {
        case ST_THINKING: r = 20;  g = 90;  b = 255; break; // blue
        case ST_RUNNING:  r = 255; g = 170; b = 0;   break; // yellow
        case ST_DONE:     r = 30;  g = 200; b = 90;  break; // green
        case ST_ERROR:    r = 240; g = 40;  b = 40;  break; // red
        case ST_IDLE:
        default:
            return false; // leave the normal VIA animation untouched
    }
    for (uint8_t i = 0; i < RGB_MATRIX_LED_COUNT; i++) {
        rgb_matrix_set_color(i, r, g, b);
    }
    return false;
}
