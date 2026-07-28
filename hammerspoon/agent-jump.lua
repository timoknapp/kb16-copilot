-- DOIO KB16 / Agent-Sprung: leuchtende Taste druecken -> zur Session springen
--
-- Gehoert an ~/.hammerspoon/init.lua angehaengt (zusaetzlich zu init-keys.lua).
--
-- Auf Layer 1 der Tastatur sendet jede der 16 Tasten MEH+A .. MEH+P
-- (Ctrl+Alt+Shift + Buchstabe). Slot N == LED N == Taste N, zeilenweise von
-- oben links. Meh statt Hyper, weil Hyper+N / Hyper+P bereits in iTerm fuer
-- den Tabwechsel belegt sind.
--
-- Die Zuordnung Slot -> Session schreibt die Bridge nach
-- ~/.copilot-kb16-slots.json.

local SLOT_FILE = os.getenv("HOME") .. "/.copilot-kb16-slots.json"
local MEH = { "ctrl", "alt", "shift" }
local SLOT_KEYS = {
  "a", "b", "c", "d",
  "e", "f", "g", "h",
  "i", "j", "k", "l",
  "m", "n", "o", "p",
}

local function readSlots()
  local ok, data = pcall(hs.json.read, SLOT_FILE)
  if not ok or type(data) ~= "table" then return {} end
  return data
end

-- iTerm2 kennt das tty jeder Session, deshalb trifft das exakt die richtige
-- Session -- nicht nur das Fenster.
local function focusIterm(tty)
  -- Nur validierte ttys weiterreichen: der Wert landet im AppleScript-Quelltext.
  if not tty:match("^/dev/tty%w+$") then return false end

  local script = string.format([[
    tell application "iTerm2"
      repeat with w in windows
        repeat with t in tabs of w
          repeat with s in sessions of t
            if (tty of s) is "%s" then
              select w
              select t
              select s
              activate
              return "ok"
            end if
          end repeat
        end repeat
      end repeat
    end tell
    return "notfound"
  ]], tty)

  local ok, result = hs.osascript.applescript(script)
  return ok and result == "ok"
end

-- Der VS-Code-Extension-Host haengt an keinem tty, deshalb bleibt nur das cwd.
-- Damit laesst sich das Fenster finden, aber nicht der einzelne Chat darin --
-- ein Fenster kann mehrere Sessions enthalten.
local function focusVSCode(cwd)
  if not cwd or cwd == "" then return false end
  local folder = cwd:match("([^/]+)/?$")
  if not folder then return false end

  local app = hs.application.get("Code")
  if not app then return false end

  for _, win in ipairs(app:allWindows()) do
    if (win:title() or ""):find(folder, 1, true) then
      win:focus()
      return true
    end
  end

  -- Kein Titel passt: wenigstens die App nach vorne holen.
  app:activate()
  return false
end

local function jumpToSlot(slot)
  local entry = readSlots()[tostring(slot)]
  if not entry then
    hs.alert.show(string.format("Slot %d: kein Agent", slot))
    return
  end

  local label = (entry.cwd or ""):match("([^/]+)/?$") or entry.session:sub(1, 8)
  local jumped
  if entry.client == "cli" then
    jumped = focusIterm(entry.tty or "")
  else
    jumped = focusVSCode(entry.cwd)
  end

  if not jumped then
    -- Fenster weg, aber der Slot noch belegt: haeufig eine beendete Session,
    -- deren Datei noch nicht abgelaufen ist.
    hs.alert.show(string.format("Slot %d (%s): Fenster nicht gefunden", slot, label))
  end
end

for i, key in ipairs(SLOT_KEYS) do
  local slot = i - 1
  hs.hotkey.bind(MEH, key, function() jumpToSlot(slot) end)
end

hs.alert.show("KB16 Agent-Sprung aktiv ✅")
