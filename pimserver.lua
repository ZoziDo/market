local component = require("component")
local event = require("event")
local serialization = require("serialization")
local filesystem = require("filesystem")

local modem = component.modem
modem.open(0xffef)
modem.open(0xfffe)

-- ========== БАЗА ДАННЫХ ==========
local DB_PATH = "/home/players.db"
local players = {}
if filesystem.exists(DB_PATH) then
  local file = io.open(DB_PATH, "r")
  local raw = file:read("*a")
  file:close()
  if #raw > 0 then
    local success, data = pcall(serialization.unserialize, raw)
    if success and data then players = data end
  end
end

local function saveDB()
  local file = io.open(DB_PATH, "w")
  file:write(serialization.serialize(players))
  file:close()
end

-- ========== ПЕРЕМЕННЫЕ ==========
local owner = nil
local sessions = {}   -- [name] = {token, lastAction}

local function log(level, msg)
  print(string.format("[%s] [%s] %s", os.date("%Y-%m-%d %H:%M:%S"), level, msg))
end

local function getOrCreatePlayer(name)
  if not players[name] then
    players[name] = {balance = 0.0, transactions = 0, regDate = os.date("%d.%m.%Y %H:%M:%S")}
    saveDB()
  end
  return players[name]
end

local function validateSession(name, token)
  local s = sessions[name]
  return s and s.token == token and os.time() - (s.lastAction or 0) < 300
end

-- ========== ЦИКЛ ==========
log("INFO", "Сервер запущен. Ожидание терминалов...")

while true do
  local ev = {event.pull(0.5)}
  local name = ev[1]

  if name == "modem_message" then
    local from = ev[3]
    local raw = ev[6]
    local success, msg = pcall(serialization.unserialize, raw)
    if not success or not msg or type(msg) ~= "table" then goto continue end

    -- Анти-спам
    local last = sessions["__modem_"..from] or 0
    if os.time() - last < 0.5 then
      log("WARN", "Спам от " .. from)
      goto continue
    end
    sessions["__modem_"..from] = os.time()

    log("INFO", string.format("От %s | op=%s", from, tostring(msg.op)))

    if msg.op == "register" then
      if not owner then
        owner = from
        log("INFO", "✅ АДМИН ЗАРЕГИСТРИРОВАН: " .. from)
      end
      modem.send(from, 0xffef, serialization.serialize({op="welcome", owner=(from==owner)}))

    elseif msg.op == "enter" then
      local playerName = msg.name
      if not playerName or playerName == "" then
        log("WARN", "Вход без имени от " .. from)
        goto continue
      end
      local player = getOrCreatePlayer(playerName)
      local token = tostring(math.random(100000000, 999999999))
      sessions[playerName] = {token=token, lastAction=os.time()}
      log("INFO", "👤 " .. playerName .. " вошёл. Токен: " .. token)
      modem.send(from, 0xffef, serialization.serialize({
        op="welcome", status="ok", token=token,
        balance=player.balance, transactions=player.transactions,
        regDate=player.regDate
      }))

    elseif msg.op == "buy" or msg.op == "sell" then
      local player = players[msg.name]
      if not player or not validateSession(msg.name, msg.token) then
        log("WARN", "Неверный токен от " .. (msg.name or "?"))
        goto continue
      end
      -- Здесь будет обработка транзакций (пока заглушка)
      log("INFO", string.format("%s: %s сумма %s", msg.op, msg.name, tostring(msg.value)))
    end
  end
  ::continue::
end
