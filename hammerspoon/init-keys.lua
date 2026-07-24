-- DOIO KB16-01 -> GitHub Copilot CLI controls for iTerm on macOS
-- Uses the Hyper key (Ctrl+Alt+Cmd+Shift) to avoid clashing with
-- native macOS functions like F14/F15 brightness.
--
-- VIA mapping for the 12 Copilot keys (via the "Any" keycode):
--   HYPR(KC_1) HYPR(KC_2) HYPR(KC_3)
--   HYPR(KC_4) HYPR(KC_5) HYPR(KC_6)
--   HYPR(KC_7) HYPR(KC_8) HYPR(KC_9)
--   HYPR(KC_0) HYPR(KC_MINS) HYPR(KC_EQL)

local ITERM_BUNDLE_ID = "com.googlecode.iterm2"
local HYPER = { "ctrl", "alt", "cmd", "shift" }

local function focusIterm()
  hs.application.launchOrFocusByBundleID(ITERM_BUNDLE_ID)
end

local function insertInIterm(text)
  local app = hs.application.frontmostApplication()
  if not app or app:bundleID() ~= ITERM_BUNDLE_ID then
    hs.alert.show("KB16: zuerst iTerm aktivieren")
    return
  end
  -- Deliberately do not press Enter: review the command, then submit it
  -- with the dedicated Enter key on the KB16.
  hs.eventtap.keyStrokes(text)
end

local function bindCommand(key, command)
  hs.hotkey.bind(HYPER, key, function()
    insertInIterm(command)
  end)
end

-- Hyper+1 = focus/launch iTerm
hs.hotkey.bind(HYPER, "1", focusIterm)

-- Copilot CLI slash commands
bindCommand("2", "/model")
bindCommand("3", "/context")
bindCommand("4", "/diff")
bindCommand("5", "/compact")
bindCommand("6", "/review")
bindCommand("7", "/plan")
bindCommand("8", "/new")
bindCommand("9", "/resume")
bindCommand("0", "/copy")
bindCommand("-", "/undo")
bindCommand("=", "/help")

-- Encoder 3 iTerm tab switching:
--   Bind Hyper+N -> "Next Tab" and Hyper+P -> "Previous Tab" inside iTerm
--   (Settings > Keys > Key Bindings). VIA then sends HYPR(KC_N) / HYPR(KC_P)
--   on the encoder rotation. No Hammerspoon binding needed for those.

hs.alert.show("KB16 Copilot-Profil (Hyper) geladen ✅")
