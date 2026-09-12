local d = component.proxy(component.list("drone")())
local m = component.proxy(component.list("modem")())
local ga = component.list("geolyzer")()
m.setStrength(400)

local function say(...)
  m.broadcast(123, "log", table.concat({...}, "  "))
  computer.pullSignal(0.2)
end

say("Inventar:", tostring(d.inventorySize()))
say("Slot:", tostring(d.select()))
say("Geolyzer:", tostring(ga ~= nil))

if ga then
  local ok, info = pcall(component.proxy(ga).analyze, 0)
  say("analyze unten:", tostring(ok),
      type(info) == "table" and tostring(info.name) or tostring(info))
end

local ok, err = d.swing(0)
say("swing unten:", tostring(ok), tostring(err))
