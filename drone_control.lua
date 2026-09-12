-- Steuerprogramm fuer die Mining-Drohne (OpenOS, Computer mit Wireless Card)
-- Aufruf:  drone_control.lua

local component = require("component")
local event     = require("event")
local term      = require("term")

local m    = component.modem
local PORT = 123

m.open(PORT)
m.setStrength(400)

print("Befehle:  h = heimrufen   g = weitermachen")
print("          s = Status      x = Drohne stoppen   q = beenden")
print("")

-- Antworten der Drohne im Hintergrund anzeigen
local function onMessage(_, _, _, port, _, cmd, a, b, c, e)
  if port ~= PORT then return end
  if cmd == "status" then
    print(string.format("Position %d %d %d   Akku %.0f%%", a, b, c, (e or 0) * 100))
  elseif cmd == "done" then
    print("Drohne meldet: fertig.")
  end
end
event.listen("modem_message", onMessage)

while true do
  local _, _, ch = event.pull("key_down")
  ch = string.char(ch or 0)
  if ch == "h" then
    m.broadcast(PORT, "home");   print("-> heimrufen")
  elseif ch == "g" then
    m.broadcast(PORT, "go");     print("-> weitermachen")
  elseif ch == "s" then
    m.broadcast(PORT, "status")
  elseif ch == "x" then
    m.broadcast(PORT, "stop");   print("-> stoppen")
  elseif ch == "q" then
    break
  end
end

event.ignore("modem_message", onMessage)
print("beendet")
