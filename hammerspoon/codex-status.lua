-- DOIO KB16 / Codex-Micro-style Copilot status indicator (menubar, Variant B)
--
-- OPTIONAL. If you run the Variant A2 firmware, the keyboard LEDs already show
-- status -- and show every concurrent agent separately, which this dot cannot:
-- it collapses all sessions into one merged colour. Append this file only if
-- you also want a menubar dot.
--
-- Add this block to your existing ~/.hammerspoon/init.lua (keep the KB16
-- Copilot key bindings from before).
--
-- Reads ~/.copilot-kb16-status, written by the Copilot CLI hooks, and colors
-- a menubar dot: idle / thinking / running / done / error.

local STATUS_FILE = os.getenv("HOME") .. "/.copilot-kb16-status"

-- Enable the `hs` CLI so this config can be reloaded from a terminal with
-- `hs -c 'hs.reload()'`. Hammerspoon does NOT pick up init.lua changes by
-- itself -- if it was started before you edited init.lua it keeps running the
-- old code indefinitely, and the menubar dot silently stays grey.
require("hs.ipc")

local STATUS = {
  idle     = { color = { red = 0.55, green = 0.55, blue = 0.55 }, label = "Codex: idle" },
  thinking = { color = { red = 0.20, green = 0.55, blue = 1.00 }, label = "Codex: thinking" },
  running  = { color = { red = 1.00, green = 0.75, blue = 0.10 }, label = "Codex: running" },
  done     = { color = { red = 0.15, green = 0.80, blue = 0.45 }, label = "Codex: done" },
  error    = { color = { red = 0.95, green = 0.25, blue = 0.25 }, label = "Codex: error" },
}

local codexMenu = hs.menubar.new()
local lastStatus = nil
local doneResetTimer = nil

local function readStatus()
  local f = io.open(STATUS_FILE, "r")
  if not f then return "idle" end
  local s = f:read("*a") or ""
  f:close()
  s = s:gsub("%s+", "")
  if STATUS[s] then return s end
  return "idle"
end

local function render(statusKey)
  local st = STATUS[statusKey] or STATUS.idle
  -- Draw a colored dot as the menubar title.
  local dot = hs.styledtext.new("●", {
    color = st.color,
    font = { size = 14 },
  })
  codexMenu:setTitle(dot)
  codexMenu:setTooltip(st.label)
end

local function update()
  local s = readStatus()
  if s == lastStatus then return end
  lastStatus = s
  render(s)

  -- Auto-fade "done" back to idle after 4s for that Codex-Micro feel.
  if doneResetTimer then doneResetTimer:stop(); doneResetTimer = nil end
  if s == "done" then
    doneResetTimer = hs.timer.doAfter(4, function()
      local f = io.open(STATUS_FILE, "w")
      if f then f:write("idle"); f:close() end
    end)
  end
end

-- Poll the file 5x/sec. Cheap and reliable across shells/hook timing.
local codexTimer = hs.timer.new(0.2, update)
codexTimer:start()
render("idle")
hs.alert.show("Codex-Status-Indikator aktiv ✅")
