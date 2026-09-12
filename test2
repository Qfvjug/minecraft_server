local event = require("event")
require("component").modem.open(123)
while true do
  local _, _, _, p, _, cmd, txt = event.pull("modem_message")
  if p == 123 and cmd == "log" then print(txt) end
end
