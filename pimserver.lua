local component = require("component")
local event = require("event")
local serialization = require("serialization")
local filesystem = require("filesystem")

local modem = component.modem
modem.open(0xffef)
modem.open(0xfffe)

-- ================== КОНФИГУРАЦИЯ ==================
local DB_PATH = "/home/playerdata.db"
local ADMIN_NAME = "Zozido"  -- замени на свой ник

-- ================== БАЗА ДАННЫХ ==================
local playerData = {}   -- [name] = {balance=0, emeralds=0, transactions=0, regDate=""}
local sessions = {}     -- [name] = {token=..., lastAction=...}
local ownerAddress = nil
local marketAddress = nil  -- адрес терминала market_01

-- Загрузка данных с диска
local function loadDatabase()
  if filesystem.exists(DB_PATH) then
    local file = io.open(DB_PATH, "r")
    local content = file:read("*all")
    file:close()
    local success, data = pcall(serialization.unserialize, content)
    if success and type(data) == "table" then
      playerData = data
    end
  end
end

-- Сохранение данных на диск
local function saveDatabase()
  local file = io.open(DB_PATH, "w")
  file:write(serialization.serialize(playerData))
  file:close()
end

-- Генерация токена (псевдослучайная строка)
local function generateToken()
  local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  local token = ""
  for i = 1, 32 do
    local rand = math.random(1, #chars)
    token = token .. chars:sub(rand, rand)
  end
  return token
end

-- Проверка админа
local function isAdmin(name)
  return name == ADMIN_NAME
end

-- Логирование с временной меткой
local function log(level, message)
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  print(string.format("[%s] [%s] %s", timestamp, level, message))
end

-- Обработка сообщения от клиента
local function processMessage(from, port, data)
  local success, msg = pcall(serialization.unserialize, data)
  if not success or type(msg) ~= "table" then
    log("WARN", "Невалидное сообщение от " .. from)
    return
  end

  local op = msg.op

  -- === РЕГИСТРАЦИЯ ТЕРМИНАЛА ===
  if op == "register" then
    if not ownerAddress then
      ownerAddress = from
      log("INFO", "Владелец зарегистрирован: " .. from)
      modem.send(from, port, serialization.serialize({op = "welcome", owner = true}))
    elseif not marketAddress and from ~= ownerAddress then
      marketAddress = from
      log("INFO", "Терминал маркета зарегистрирован: " .. from)
      modem.send(from, port, serialization.serialize({op = "welcome", owner = false}))
    else
      log("WARN", "Попытка повторной регистрации от " .. from)
    end
  -- === ВХОД ИГРОКА ===
  elseif op == "enter" then
    local player = msg.name
    if not player or type(player) ~= "string" then
      log("WARN", "Попытка входа без имени от " .. from)
      return
    end
    -- Игнорируем пустые имена
    if player == "" then
      log("WARN", "Пустое имя при входе")
      return
    end
    -- Защита от спама
    if sessions[player] and os.clock() - (sessions[player].lastAction or 0) < 5 then
      log("WARN", "Слишком частый вход: " .. player)
      return
    end
    -- Инициализация данных игрока
    if not playerData[player] then
      playerData[player] = {
        balance = 0,
        emeralds = 0,
        transactions = 0,
        regDate = os.date("%d.%m.%Y %H:%M:%S")
      }
      saveDatabase()
      log("INFO", "Новый игрок: " .. player)
    end
    -- Создание сессии с токеном
    local token = generateToken()
    sessions[player] = {token = token, lastAction = os.clock()}
    log("INFO", "Вход игрока " .. player .. " (терминал " .. from .. ")")
    modem.send(from, port, serialization.serialize({
      op = "welcome",
      status = "ok",
      token = token,
      balance = playerData[player].balance,
      emeralds = playerData[player].emeralds
    }))
  -- === ПОЛУЧЕНИЕ ДАННЫХ АККАУНТА ===
  elseif op == "getAccount" then
    local player = msg.name
    local token = msg.token
    if not player or not token then
      log("WARN", "Неполные данные аккаунта от " .. from)
      return
    end
    if sessions[player] and sessions[player].token == token then
      sessions[player].lastAction = os.clock()
      modem.send(from, port, serialization.serialize({
        op = "accountData",
        data = playerData[player],
        player = player
      }))
    else
      log("WARN", "Неверный токен для " .. player)
    end
  -- === ПОКУПКА (добавим позже) ===
  elseif op == "buy" then
    local player = msg.name
    local token = msg.token
    local amount = tonumber(msg.amount) or 0
    if not sessions[player] or sessions[player].token ~= token then
      log("WARN", "Невалидный токен при покупке: " .. player)
      return
    end
    if amount <= 0 or amount > playerData[player].balance then
      log("WARN", "Недостаточно средств: " .. player)
      return
    end
    playerData[player].balance = playerData[player].balance - amount
    playerData[player].transactions = playerData[player].transactions + 1
    saveDatabase()
    log("INFO", string.format("Покупка %s: -%.2f", player, amount))
    modem.send(from, port, serialization.serialize({
      op = "buyResult",
      status = "ok",
      balance = playerData[player].balance
    }))
  end
end

-- ================== ИНИЦИАЛИЗАЦИЯ ==================
math.randomseed(os.time())
loadDatabase()
log("INFO", "Сервер запущен")
print("Ожидание терминалов...")

-- ================== ГЛАВНЫЙ ЦИКЛ ==================
while true do
  local ev = {event.pull(0.5)}
  local name = ev[1]

  if name == "modem_message" then
    local from = ev[3]
    local raw = ev[6]
    processMessage(from, 0xffef, raw)
  end
end