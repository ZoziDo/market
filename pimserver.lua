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

-- ========== ПОЛУЧЕНИЕ РЕАЛЬНОГО ВРЕМЕНИ ==========
local function getRealTime()
  if component.isAvailable("internet") then
    local ok, result = pcall(function()
      local internet = require("internet")
      local conn = internet.open("just-the-time.appspot.com", 80)
      conn:write("GET / HTTP/1.1\r\nHost: just-the-time.appspot.com\r\nConnection: close\r\n\r\n")
      conn:flush()
      local body = ""
      while true do
        local chunk = conn:read(1024)
        if not chunk then break end
        body = body .. chunk
      end
      conn:close()
      -- ИСПРАВЛЕННАЯ СТРОКА: %d для цифр, %- для тире
      local match = body:match("(%d+%-%d+%-%d+ %d+:%d+:%d+)")
      if match then
        local year, month, day, time = match:match("(%d+)%-(%d+)%-(%d+) (.+)")
        if year and month and day and time then
          return string.format("%s.%s.%s %s", day, month, year, time)
        end
      end
    end)
    if ok and result then return result end
  end
  return os.date("%d.%m.%Y %H:%M:%S")
end

-- ========== ПЕРЕМЕННЫЕ ==========
local owner = nil
local sessions = {}
local SESSION_TIMEOUT = 1800

local function log(level, msg)
  print(string.format("[%s] [%s] %s", os.date("%Y-%m-%d %H:%M:%S"), level, msg))
end

local function getOrCreatePlayer(name)
  if not players[name] then
    local realDate = getRealTime()
    players[name] = {
      balance = 0.0,
      transactions = 0,
      regDate = realDate
    }
    saveDB()
    log("INFO", "Создан игрок " .. name .. " с датой: " .. realDate)
  end
  return players[name]
end

local function validateSession(name, token)
  local s = sessions[name]
  return s and s.token == token and os.time() - (s.lastAction or 0) < SESSION_TIMEOUT
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

    local last = sessions["__modem_"..from] or 0
    if os.time() - last < 0.5 then
      log("WARN", "Спам от " .. from)
      goto continue
    end
    sessions["__modem_"..from] = os.time()

    log("INFO", string.format("От %s | op=%s | name=%s | token=%s", from, tostring(msg.op), msg.name or "?", msg.token or "нет"))

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

      local existingSession = sessions[playerName]
      local token
      if existingSession and os.time() - (existingSession.lastAction or 0) < SESSION_TIMEOUT then
        token = existingSession.token
        existingSession.lastAction = os.time()
        log("INFO", "👤 " .. playerName .. " продлил сессию. Токен: " .. token)
      else
        token = tostring(math.floor(math.random() * 900000000 + 100000000))
        sessions[playerName] = {token = token, lastAction = os.time()}
        log("INFO", "👤 " .. playerName .. " вошёл. Токен: " .. token)
      end

      modem.send(from, 0xffef, serialization.serialize({
        op="welcome", status="ok", token=token,
        balance=player.balance, transactions=player.transactions,
        regDate=player.regDate
      }))

    elseif msg.op == "getAccount" then
      if not validateSession(msg.name, msg.token) then
        log("WARN", "Неверный токен для getAccount от " .. (msg.name or "?"))
        modem.send(from, 0xffef, serialization.serialize({
          op="accountData",
          error = true,
          message = "Токен устарел, требуется повторный вход"
        }))
        goto continue
      end
      local player = players[msg.name]
      if not player then goto continue end
      sessions[msg.name].lastAction = os.time()
      modem.send(from, 0xffef, serialization.serialize({
        op="accountData",
        data = {
          balance = player.balance,
          transactions = player.transactions,
          regDate = player.regDate
        }
      }))
      log("INFO", "Аккаунт отправлен для " .. msg.name)

    elseif msg.op == "buy" or msg.op == "sell" then
      local player = players[msg.name]
      if not player or not validateSession(msg.name, msg.token) then
        log("WARN", "Неверный токен от " .. (msg.name or "?"))
        goto continue
      end
      sessions[msg.name].lastAction = os.time()
      log("INFO", string.format("%s: %s сумма %s", msg.op, msg.name, tostring(msg.value)))
    end
  end
  ::continue::
end
