--=====================================================================
-- Diamanten-Strip-Mining-Drohne  --  OpenComputers EEPROM-Firmware
--
-- Startpunkt = Charger, Hopper direkt darunter. Dort ist (0,0,0).
-- Funkbefehle auf PORT: "home", "stop", "go", "status"
--=====================================================================

------------------------- Konfiguration -------------------------------
local PORT      = 123     -- Funkport
local BRANCHES  = 6       -- Anzahl Seitenstollen-Paare
local LENGTH    = 40      -- Laenge pro Seitenstollen
local SPACING   = 3       -- Abstand der Seitenstollen im Hauptstollen
local MIN_PWR   = 0.30    -- unter 30 % Akku -> heimfliegen
local SAFE_PWR  = 0.95    -- bis 95 % laden
local VEIN      = 3       -- wie tief einer Erzader gefolgt wird
local ACCEL     = 0.4

-- Was gesammelt wird (Teilstring im Blocknamen)
local WANTED    = { "diamond" }
-- Was toedlich ist
local DANGER    = { "lava", "water", "fire", "bedrock" }
-----------------------------------------------------------------------

local function need(t)
  local a = component.list(t)()
  if not a then error("Komponente fehlt: " .. t, 0) end
  return component.proxy(a)
end

local d = need("drone")
local g = need("geolyzer")
local m = need("modem")

local DOWN, UP, NORTH, SOUTH, WEST, EAST = 0, 1, 2, 3, 4, 5
local VEC = {
  [DOWN]  = { 0, -1,  0 }, [UP]    = { 0,  1,  0 },
  [NORTH] = { 0,  0, -1 }, [SOUTH] = { 0,  0,  1 },
  [WEST]  = {-1,  0,  0 }, [EAST]  = { 1,  0,  0 },
}
local OPP = { [0]=1, [1]=0, [2]=3, [3]=2, [4]=5, [5]=4 }

local pos    = { x = 0, y = 0, z = 0 }
local trail  = { { 0, 0, 0 } }   -- Brotkrumen-Pfad zurueck nach Hause
local recall = false
local running = true

--------------------------- Kommunikation -----------------------------
local function poll(timeout)
  local ev, _, _, port, _, cmd = computer.pullSignal(timeout)
  if ev == "modem_message" and port == PORT then
    if cmd == "home" then
      recall = true
    elseif cmd == "stop" then
      recall, running = true, false
    elseif cmd == "go" then
      recall = false
    elseif cmd == "status" then
      m.broadcast(PORT, "status", pos.x, pos.y, pos.z,
                  computer.energy() / computer.maxEnergy())
    end
  end
end

--------------------------- Bewegung ----------------------------------
local function moveTo(x, y, z)
  d.move(x - pos.x, y - pos.y, z - pos.z)
  pos.x, pos.y, pos.z = x, y, z
  local t0 = computer.uptime()
  while d.getOffset() > 0.4 do
    poll(0.05)
    if computer.uptime() - t0 > 15 then break end  -- Notbremse: blockiert
  end
end

local function step(side)
  local v = VEC[side]
  moveTo(pos.x + v[1], pos.y + v[2], pos.z + v[3])
  trail[#trail + 1] = { pos.x, pos.y, pos.z }
end

--------------------------- Blockanalyse ------------------------------
local function look(side)
  local ok, info = pcall(g.analyze, side)
  if ok and type(info) == "table" and info.name then return info.name end
  return "?"
end

local function matches(name, list)
  for _, s in ipairs(list) do
    if name:find(s, 1, true) then return true end
  end
  return false
end

local function isDanger(n) return matches(n, DANGER) end
local function isWanted(n) return matches(n, WANTED) end

--------------------------- Abbau -------------------------------------
local function dig(side)
  local n = look(side)
  if isDanger(n) then
    d.setStatusText("GEFAHR\n" .. n:sub(-12))
    return false
  end
  if n == "?" or n:find("air", 1, true) then return true end
  local ok = d.swing(side)
  d.suck(side)
  return ok ~= false
end

local function isFull()
  for i = 1, d.inventorySize() do
    if d.space(i) > 0 then return false end
  end
  return true
end

local function mineVein(side, depth)
  if depth <= 0 then return end
  if not dig(side) then return end
  step(side)
  local back = OPP[side]
  for s = 0, 5 do
    if s ~= back and isWanted(look(s)) then mineVein(s, depth - 1) end
  end
  step(back)
end

local function checkSides(forward)
  for s = 0, 5 do
    if s ~= forward and isWanted(look(s)) then
      d.setStatusText("Erz!")
      mineVein(s, VEIN)
    end
  end
end

--------------------------- Heimflug / Service ------------------------
local function goHome()
  d.setStatusText("heim")
  for i = #trail, 1, -1 do
    local p = trail[i]
    moveTo(p[1], p[2], p[3])
  end
  moveTo(0, 0, 0)
end

local function goBackToWork()
  d.setStatusText("zurueck")
  for i = 1, #trail do
    local p = trail[i]
    moveTo(p[1], p[2], p[3])
  end
end

local function unload()
  d.setStatusText("abladen")
  for i = 1, d.inventorySize() do
    d.select(i)
    d.drop(DOWN)
  end
  d.select(1)
end

local function charge()
  d.setStatusText("laden")
  while computer.energy() / computer.maxEnergy() < SAFE_PWR do
    poll(1)
    if not running then return end
  end
end

local function needService()
  return recall
      or isFull()
      or computer.energy() / computer.maxEnergy() < MIN_PWR
end

local function service()
  goHome()
  unload()
  charge()
  while recall and running do poll(1) end   -- auf "go" warten
  if running then goBackToWork() end
end

--------------------------- Stollen graben ----------------------------
local function tunnel(side, len)
  for _ = 1, len do
    if not running then return false end
    if needService() then service() end
    if not running then return false end
    if not dig(side) then return false end   -- Lava voraus -> abbrechen
    step(side)
    checkSides(OPP[side])
    d.setStatusText(string.format("%d %d %d\n%d%%",
      pos.x, pos.y, pos.z,
      math.floor(computer.energy() / computer.maxEnergy() * 100)))
  end
  return true
end

--------------------------- Hauptprogramm -----------------------------
m.open(PORT)
d.setAcceleration(ACCEL)
d.setStatusText("Start")

for b = 1, BRANCHES do
  if not running then break end
  if not tunnel(EAST, SPACING) then break end

  local jx, jy, jz = pos.x, pos.y, pos.z
  local mark = #trail

  tunnel(NORTH, LENGTH)
  moveTo(jx, jy, jz)
  for i = #trail, mark + 1, -1 do trail[i] = nil end

  tunnel(SOUTH, LENGTH)
  moveTo(jx, jy, jz)
  for i = #trail, mark + 1, -1 do trail[i] = nil end
end

goHome()
unload()
d.setStatusText("fertig")
m.broadcast(PORT, "done")
computer.shutdown()
