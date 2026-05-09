local component = require("component")
local event = require("event")
local serialization = require("serialization")
local filesystem = require("filesystem")

local modem = component.modem
modem.open(0xffef)
modem.open(0xfffe)

-- ========== КОНФИГУРАЦИЯ ==========
local DB_PATH = "/home/players.db"

-- ========== ЗАГРУЗКА БАЗЫ ДАННЫХ ==========
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
local owner = nil           -- адрес модема владельца (админ)
local sessions = {}         -- [name] = {token = "...", lastAction = os.time()}

-- ========== УТИЛИТЫ ==========
local function log(level, msg)
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  print(string.format("[%s] [%s] %s", timestamp, level, msg))
end

local function getOrCreatePlayer(name)
  if not players[name] then
    players[name] = {
      uid = nil,
      balance = 0.00,
      transactions = 0,
      regDate = os.date("%d.%m.%Y %H:%M:%S")
    }
    saveDB()
  end
  return players[name]
end

local function validateSession(session, token)
  return session and session.token == token and os.time() - (session.lastAction or 0) < 300
end

-- ========== ОСНОВНОЙ ЦИКЛ ==========
log("INFO", "Сервер запущен")
log("INFO", "Ожидание терминалов...")

while true do
  local ev = {event.pull(0.5)}
  local name = ev[1]

  if name == "modem_message" then
    local from = ev[3]
    local raw = ev[6]
    local success, msg = pcall(serialization.unserialize, raw)
    if not success or not msg or type(msg) ~= "table" then goto continue end

    -- Анти-спам (0.5 сек между сообщениями от одного адреса)
    local lastTime = sessions["__modem_" .. from] or 0
    if os.time() - lastTime < 0.5 then
      log("WARN", "Спам от " .. from)
      goto continue
    end
    sessions["__modem_" .. from] = os.time()

    log("INFO", string.format("Получено от %s | op = %s", from, tostring(msg.op)))

    if msg.op == "register" then
      if not owner then
        owner = from
        log("INFO", "✅ ВЛАДЕЛЕЦ (АДМИН) ЗАРЕГИСТРИРОВАН: " .. from)
      end
      modem.send(from, 0xffef, serialization.serialize({
        op = "welcome",
        owner = (from == owner)
      }))

    elseif msg.op == "enter" then
      local playerName = msg.name
      if not playerName or playerName == "" then
        log("WARN", "Попытка входа без имени от " .. from)
        goto continue
      end

      -- Создаём/обновляем запись игрока
      local player = getOrCreatePlayer(playerName)

      -- Генерируем токен
      local token = tostring(math.random(100000000, 999999999))
      sessions[playerName] = {
        token = token,
        lastAction = os.time()
      }

      log("INFO", "👤 ИГРОК " .. playerName .. " ЗАШЁЛ (токен: " .. token .. ")")
      modem.send(from, 0xffef, serialization.serialize({
        op = "welcome",
        status = "ok",
        token = token,
        balance = player.balance,
        transactions = player.transactions,
        regDate = player.regDate
      }))

    elseif msg.op == "buy" then
      -- Обработка покупки (позже)
      -- Проверяем сессию: msg.token, msg.name
      local player = players[msg.name]
      if not player then goto continue end
      if not validateSession(sessions[msg.name], msg.token) then
        log("WARN", "Неверный токен для " .. msg.name)
        goto continue
      end
      log("INFO", "Покупка запрошена: " .. msg.name .. " сумма " .. tostring(msg.value))
      -- TODO: реализовать транзакцию

    elseif msg.op == "sell" then
      -- Обработка продажи (позже)
      local player = players[msg.name]
      if not player then goto continue end
      if not validateSession(sessions[msg.name], msg.token) then
        log("WARN", "Неверный токен для " .. msg.name)
        goto continue
      end
      log("INFO", "Продажа запрошена: " .. msg.name .. " сумма " .. tostring(msg.value))
    end
  end
  ::continue::
end
