local component = require("component")
local gpu = component.gpu
local term = require("term")
local event = require("event")
local keyboard = require("keyboard")
local unicode = require("unicode")
local computer = require("computer")
Serialization = require("serialization")
Filesystem = require("filesystem")

if not component.isAvailable("modem") then
  error("Не найден модем. Установите сетевую карту/модем.", 0)
end

modem = component.modem

-- В некоторых сборках OpenComputers модуль json.lua регистрирует глобальную
-- таблицу json/JSON, но ничего не возвращает из require(). Из-за этого
-- конструкция local json = require("json") создаёт локальную переменную nil.
-- Здесь модуль подключается безопасно, а если готового декодера нет,
-- используется встроенный JSON-декодер.
local jsonLibrary = nil
do
  local ok, result = pcall(require, "json")
  if ok then
    jsonLibrary = result or rawget(_G, "json") or rawget(_G, "JSON")
  end
end

local function codepointToUtf8(codepoint)
  if unicode and type(unicode.char) == "function" then
    local ok, result = pcall(unicode.char, codepoint)
    if ok and result then return result end
  end

  if codepoint <= 0x7F then
    return string.char(codepoint)
  elseif codepoint <= 0x7FF then
    return string.char(
      0xC0 + math.floor(codepoint / 0x40),
      0x80 + (codepoint % 0x40)
    )
  elseif codepoint <= 0xFFFF then
    return string.char(
      0xE0 + math.floor(codepoint / 0x1000),
      0x80 + (math.floor(codepoint / 0x40) % 0x40),
      0x80 + (codepoint % 0x40)
    )
  elseif codepoint <= 0x10FFFF then
    return string.char(
      0xF0 + math.floor(codepoint / 0x40000),
      0x80 + (math.floor(codepoint / 0x1000) % 0x40),
      0x80 + (math.floor(codepoint / 0x40) % 0x40),
      0x80 + (codepoint % 0x40)
    )
  end

  return "?"
end

local function decodeJsonFallback(source)
  if type(source) ~= "string" then
    error("JSON должен быть строкой", 0)
  end

  local position = 1
  local length = #source
  local JSON_NULL = {}

  local function fail(message)
    error("Ошибка JSON в позиции " .. tostring(position) .. ": " .. message, 0)
  end

  local function skipWhitespace()
    while position <= length do
      local c = source:sub(position, position)
      if c == " " or c == "\t" or c == "\r" or c == "\n" then
        position = position + 1
      else
        break
      end
    end
  end

  local parseValue

  local function parseString()
    if source:sub(position, position) ~= '"' then
      fail("ожидалась строка")
    end

    position = position + 1
    local result = {}

    while position <= length do
      local c = source:sub(position, position)

      if c == '"' then
        position = position + 1
        return table.concat(result)
      end

      if c == "\\" then
        position = position + 1
        if position > length then
          fail("незавершённая escape-последовательность")
        end

        local escaped = source:sub(position, position)
        local replacements = {
          ['"'] = '"',
          ['\\'] = '\\',
          ['/'] = '/',
          ['b'] = '\b',
          ['f'] = '\f',
          ['n'] = '\n',
          ['r'] = '\r',
          ['t'] = '\t',
        }

        if replacements[escaped] then
          result[#result + 1] = replacements[escaped]
          position = position + 1
        elseif escaped == "u" then
          local hex = source:sub(position + 1, position + 4)
          if #hex ~= 4 or not hex:match("^[0-9a-fA-F]+$") then
            fail("неверная последовательность \\uXXXX")
          end

          local codepoint = tonumber(hex, 16)
          position = position + 5

          if codepoint >= 0xD800 and codepoint <= 0xDBFF then
            if source:sub(position, position + 1) == "\\u" then
              local lowHex = source:sub(position + 2, position + 5)
              local low = tonumber(lowHex, 16)
              if low and low >= 0xDC00 and low <= 0xDFFF then
                codepoint = 0x10000 + (codepoint - 0xD800) * 0x400 + (low - 0xDC00)
                position = position + 6
              end
            end
          end

          result[#result + 1] = codepointToUtf8(codepoint)
        else
          fail("неизвестная escape-последовательность")
        end
      else
        local byte = c:byte()
        if byte and byte < 32 then
          fail("управляющий символ внутри строки")
        end
        result[#result + 1] = c
        position = position + 1
      end
    end

    fail("строка не закрыта")
  end

  local function parseNumber()
    local startPosition = position

    if source:sub(position, position) == "-" then
      position = position + 1
    end

    local first = source:sub(position, position)
    if first == "0" then
      position = position + 1
    elseif first:match("%d") then
      repeat
        position = position + 1
      until not source:sub(position, position):match("%d")
    else
      fail("неверное число")
    end

    if source:sub(position, position) == "." then
      position = position + 1
      if not source:sub(position, position):match("%d") then
        fail("после точки ожидалась цифра")
      end
      repeat
        position = position + 1
      until not source:sub(position, position):match("%d")
    end

    local exponent = source:sub(position, position)
    if exponent == "e" or exponent == "E" then
      position = position + 1
      local sign = source:sub(position, position)
      if sign == "+" or sign == "-" then
        position = position + 1
      end
      if not source:sub(position, position):match("%d") then
        fail("неверная степень числа")
      end
      repeat
        position = position + 1
      until not source:sub(position, position):match("%d")
    end

    local numberText = source:sub(startPosition, position - 1)
    local number = tonumber(numberText)
    if number == nil then
      fail("не удалось преобразовать число")
    end
    return number
  end

  local function parseArray()
    position = position + 1
    skipWhitespace()

    local result = {}
    if source:sub(position, position) == "]" then
      position = position + 1
      return result
    end

    while true do
      result[#result + 1] = parseValue()
      skipWhitespace()

      local c = source:sub(position, position)
      if c == "]" then
        position = position + 1
        return result
      elseif c ~= "," then
        fail("в массиве ожидалась запятая или ]")
      end

      position = position + 1
      skipWhitespace()
    end
  end

  local function parseObject()
    position = position + 1
    skipWhitespace()

    local result = {}
    if source:sub(position, position) == "}" then
      position = position + 1
      return result
    end

    while true do
      if source:sub(position, position) ~= '"' then
        fail("ключ объекта должен быть строкой")
      end

      local key = parseString()
      skipWhitespace()

      if source:sub(position, position) ~= ":" then
        fail("после ключа ожидался символ :")
      end

      position = position + 1
      skipWhitespace()
      result[key] = parseValue()
      skipWhitespace()

      local c = source:sub(position, position)
      if c == "}" then
        position = position + 1
        return result
      elseif c ~= "," then
        fail("в объекте ожидалась запятая или }")
      end

      position = position + 1
      skipWhitespace()
    end
  end

  parseValue = function()
    skipWhitespace()
    local c = source:sub(position, position)

    if c == '"' then
      return parseString()
    elseif c == "{" then
      return parseObject()
    elseif c == "[" then
      return parseArray()
    elseif c == "-" or c:match("%d") then
      return parseNumber()
    elseif source:sub(position, position + 3) == "true" then
      position = position + 4
      return true
    elseif source:sub(position, position + 4) == "false" then
      position = position + 5
      return false
    elseif source:sub(position, position + 3) == "null" then
      position = position + 4
      return JSON_NULL
    end

    fail("неожиданное значение")
  end

  local value = parseValue()
  skipWhitespace()
  if position <= length then
    fail("лишние данные после JSON")
  end

  return value
end

local function decodeJson(source)
  local candidates = {}

  local function addCandidate(owner, fn)
    if type(fn) == "function" then
      candidates[#candidates + 1] = {owner = owner, fn = fn}
    end
  end

  if type(jsonLibrary) == "function" then
    addCandidate(nil, jsonLibrary)
  elseif type(jsonLibrary) == "table" then
    addCandidate(jsonLibrary, jsonLibrary.decode)
    addCandidate(jsonLibrary, jsonLibrary.parse)
  end

  local globalJson = rawget(_G, "json")
  if type(globalJson) == "table" and globalJson ~= jsonLibrary then
    addCandidate(globalJson, globalJson.decode)
    addCandidate(globalJson, globalJson.parse)
  end

  local globalJSON = rawget(_G, "JSON")
  if type(globalJSON) == "table" and globalJSON ~= jsonLibrary and globalJSON ~= globalJson then
    addCandidate(globalJSON, globalJSON.decode)
    addCandidate(globalJSON, globalJSON.parse)
  end

  for _, candidate in ipairs(candidates) do
    local ok, result = pcall(candidate.fn, source)
    if ok and type(result) == "table" then
      return result, nil
    end

    if candidate.owner then
      ok, result = pcall(candidate.fn, candidate.owner, source)
      if ok and type(result) == "table" then
        return result, nil
      end
    end
  end

  local ok, result = pcall(decodeJsonFallback, source)
  if ok and type(result) == "table" then
    return result, nil
  end

  return nil, tostring(result or "Неизвестная ошибка JSON")
end

-- Безопасный JSON-кодировщик для POST-запросов.
-- Сначала используются encode/stringify из подключённой библиотеки, затем
-- встроенный кодировщик для простых таблиц, строк, чисел и boolean.
local function escapeJsonString(value)
  return tostring(value)
    :gsub('\\', '\\\\')
    :gsub('"', '\\"')
    :gsub('\b', '\\b')
    :gsub('\f', '\\f')
    :gsub('\n', '\\n')
    :gsub('\r', '\\r')
    :gsub('\t', '\\t')
end

local function encodeJsonFallback(value, seen)
  local valueType = type(value)

  if valueType == "nil" then
    return "null"
  elseif valueType == "boolean" then
    return value and "true" or "false"
  elseif valueType == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      return "null"
    end
    return tostring(value)
  elseif valueType == "string" then
    return '"' .. escapeJsonString(value) .. '"'
  elseif valueType ~= "table" then
    return '"' .. escapeJsonString(tostring(value)) .. '"'
  end

  seen = seen or {}
  if seen[value] then
    error("Циклическая таблица не может быть преобразована в JSON", 0)
  end
  seen[value] = true

  local isArray = true
  local maxIndex = 0
  local count = 0
  for key in pairs(value) do
    count = count + 1
    if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
      isArray = false
      break
    end
    if key > maxIndex then maxIndex = key end
  end
  if isArray and maxIndex ~= count then isArray = false end

  local result = {}
  if isArray then
    for index = 1, maxIndex do
      result[#result + 1] = encodeJsonFallback(value[index], seen)
    end
    seen[value] = nil
    return "[" .. table.concat(result, ",") .. "]"
  end

  for key, item in pairs(value) do
    result[#result + 1] =
      '"' .. escapeJsonString(key) .. '":' .. encodeJsonFallback(item, seen)
  end
  seen[value] = nil
  return "{" .. table.concat(result, ",") .. "}"
end

local function encodeJson(value)
  local candidates = {}
  local function add(owner, fn)
    if type(fn) == "function" then
      candidates[#candidates + 1] = {owner = owner, fn = fn}
    end
  end

  if type(jsonLibrary) == "table" then
    add(jsonLibrary, jsonLibrary.encode)
    add(jsonLibrary, jsonLibrary.stringify)
  end
  local globalJson = rawget(_G, "json")
  local globalJSON = rawget(_G, "JSON")
  if type(globalJson) == "table" then
    add(globalJson, globalJson.encode)
    add(globalJson, globalJson.stringify)
  end
  if type(globalJSON) == "table" then
    add(globalJSON, globalJSON.encode)
    add(globalJSON, globalJSON.stringify)
  end

  for _, candidate in ipairs(candidates) do
    local ok, result = pcall(candidate.fn, value)
    if ok and type(result) == "string" then return result end
    if candidate.owner then
      ok, result = pcall(candidate.fn, candidate.owner, value)
      if ok and type(result) == "string" then return result end
    end
  end

  local ok, result = pcall(encodeJsonFallback, value)
  if ok then return result end
  return nil, tostring(result)
end

-- ============================================================
-- ЛОКАЛЬНАЯ MODEM-СЕТЬ VIP-SHOP
-- Интернет-карта, TimeWeb и VPS больше не используются.
-- ============================================================

MODEM_PROTOCOL = "VIPSHOP-MODEM-1"
MODEM_NETWORK_KEY = "VIPSHOP_ZOZIDO_REALM9_SECRET_2026"
MODEM_SERVER_PORT = 3410
MODEM_CLIENT_PORT = 3411
MODEM_SERVER_ADDRESS = "f98e9e2e-1ebe-4bcf-82eb-74f0710a965b"
TERMINAL_ID = "AUTO"
if TERMINAL_ID == "AUTO" or TERMINAL_ID == "" then
  TERMINAL_ID = "VIP-TERM-" .. tostring(modem.address):sub(1, 8)
end

MODEM_CACHE_DIR = "/home/vipshop_cache"
MODEM_CACHE_BUY = MODEM_CACHE_DIR .. "/catalog_buy.db"
MODEM_CACHE_SELL = MODEM_CACHE_DIR .. "/catalog_sell.db"
MODEM_CACHE_META = MODEM_CACHE_DIR .. "/versions.db"
modem.open(MODEM_CLIENT_PORT)

local WEB_BASE_URL = "modem://vipshop"
local CATALOG_URL = WEB_BASE_URL .. "/catalog_buy"
local SELL_ITEMS_URL = WEB_BASE_URL .. "/catalog_sell"
local USERS_URL = WEB_BASE_URL .. "/users"
local BALANCE_UPDATE_URL = WEB_BASE_URL .. "/update_balance"
REGISTER_PLAYER_URL = WEB_BASE_URL .. "/register_player"
local TRANSACTION_URL = WEB_BASE_URL .. "/transaction"
local VPS_SYNC_URL = WEB_BASE_URL .. "/sync"

SecurePurchase = SecurePurchase or {}
SecurePurchase.url = WEB_BASE_URL .. "/api"
SecurePurchase.timeout = 4
SecureSale = SecureSale or {}

ModemRPC = ModemRPC or {}
ModemRPC.serverAddress = MODEM_SERVER_ADDRESS
ModemRPC.requestCounter = 0
ModemRPC.pushQueue = {}
ModemRPC.sessionData = nil
ModemRPC.cacheMeta = nil
ModemRPC.nextHeartbeat = 0
ModemRPC.heartbeatInterval = 30
ModemRPC.timeout = 4
ModemRPC.lastError = nil
ModemRPC.globalMaintenance = false
ModemRPC.terminalPaused = false

function ModemRPC.copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, nested in pairs(value) do
    result[key] = ModemRPC.copy(nested)
  end
  return result
end

Performance = Performance or {}
Performance.searchDelay = 0.12
Performance.searchDirty = false
Performance.nextSearchAt = 0
Performance.lastInputAt = 0
Performance.networkIdleDelay = 0.75
Performance.catalogMaxAge = 3600
Performance.buyCatalogLoadedAt = 0
Performance.sellCatalogLoadedAt = 0
Performance.idleFor = 0
Performance.pendingScroll = 0
Performance.nextScrollAt = 0
Performance.scrollInterval = 0.04

SelectorCache = SelectorCache or {}
SelectorCache.key = nil

Maintenance = Maintenance or {}
Maintenance.configUrl = WEB_BASE_URL .. "/state"
Maintenance.signalUrl = WEB_BASE_URL .. "/push"
Maintenance.active = false
Maintenance.screenDrawn = false
Maintenance.lastSignalTime = -1
Maintenance.nextSignalCheck = math.huge
Maintenance.nextConfigCheck = math.huge
Maintenance.signalInterval = 3600
Maintenance.configInterval = 3600
Maintenance.requestTimeout = 4

BanSystem = BanSystem or {}
BanSystem.checkUrl = WEB_BASE_URL .. "/check_ban"
BanSystem.signalUrl = WEB_BASE_URL .. "/push"
BanSystem.requestTimeout = 4
BanSystem.checkInterval = 3600
BanSystem.nextCheck = math.huge
BanSystem.lastSignalTime = -1
BanSystem.blockedPlayer = nil
BanSystem.info = nil
BanSystem.screenDrawn = false
BanSystem.lastError = nil

local HTTP_TIMEOUT = 8
local PURCHASE_HTTP_TIMEOUT = 4
local PIM_CHECK_INTERVAL = 0.65
local AUTH_DELAY = 2
local ME_EXPORT_DIRECTION = "up"
SellFlow = SellFlow or {}
SellFlow.pushDirection = "down"
SellFlow.endpoint = WEB_BASE_URL .. "/api"
SellFlow.inventorySnapshot = nil
SellFlow.inventorySnapshotAt = 0
SellFlow.inventorySnapshotMaxAge = 0.75

local WIDTH, HEIGHT = gpu.getResolution()
local maxW, maxH = gpu.maxResolution()
if WIDTH < maxW or HEIGHT < maxH then
  gpu.setResolution(maxW, maxH)
  WIDTH, HEIGHT = gpu.getResolution()
end

local C = {
  bg = 0x0C0C0C, white = 0xFFFFFF, gray = 0xAAAAAA, darkGray = 0x555555,
  green = 0x55FF55, yellow = 0xFF4F00, red = 0xFF5555, cyan = 0x55FFFF,
  coin = 0x55FFFF, ema = 0xFF4F00,
  infoDescription = 0x88D978,
  selectedBg = 0x002440, selectedName = 0x00e6b1, star = 0x077d42,
  vipTitle = 0x0c9a76, underLine = 0x428A72, mainLine = 0x7FFFD4,
  sectionLine = 0x27BDEC, headerBg = 0x1A2D33, notFound = 0xF50016,
  buttonBuy = 0x03c03c, buttonClear = 0x8b1a1a, buttonSales = 0xc37629,
  autocraftAccent = 0xFFE400, buttonCraft = 0x27BDEC, buttonFilter = 0x943391,
  inputBg = 0x1a1a1a, inputFg = 0xFFFFFF, accent = 0x0c9a76, frame = 0x27BDEC,
  maintenanceOrange = 0xFF5A00, maintenanceOrangeDark = 0xD94800,
  maintenanceOrangeLight = 0xFF8C42, maintenanceOrangePale = 0xFFC09A,
  maintenanceWhite = 0xFFFFFF, maintenanceWhiteShade = 0xD8D8D8,
  maintenanceBlack = 0x000000, maintenanceGray = 0xCFCFCF,
  banRed = 0xFF3535, banRedDark = 0x8B1010, banYellow = 0xFFE400,
  banWhite = 0xFFFFFF, banGray = 0xAAAAAA, banBg = 0x090909,
}

local function setBG(c) gpu.setBackground(c) end
local function setFG(c) gpu.setForeground(c) end
local function fill(x, y, w, h, c) setBG(c) gpu.fill(x, y, w, h, " ") end
local function text(x, y, str, fg, bg)
  if bg then setBG(bg) end
  if fg then setFG(fg) end
  gpu.set(x, y, str)
end
local function sectionHeader(x, y, w, title, lineColor, titleColor)
  lineColor = lineColor or C.sectionLine
  titleColor = titleColor or C.white
  setBG(C.bg) setFG(lineColor)
  gpu.set(x, y, string.rep("-", w))
  setFG(titleColor)
  gpu.set(x + 1, y, title)
end
local function truncate(str, maxLen)
  str = tostring(str or "")
  if unicode.len(str) <= maxLen then return str end
  return unicode.sub(str, 1, math.max(0, maxLen - 3)) .. "..."
end

local function lowerText(str)
  str = tostring(str or "")
  if unicode.lower then
    return unicode.lower(str)
  end
  return string.lower(str)
end

local function trimNumber(value, decimals)
  local n = tonumber(value) or 0
  if n == math.floor(n) then
    return tostring(math.floor(n))
  end

  local result = string.format("%." .. tostring(decimals or 4) .. "f", n)
  result = result:gsub("0+$", ""):gsub("%.$", "")
  return result
end

local function formatQuantity(value)
  local n = tonumber(value) or 0
  if n >= 1000000000 then
    return trimNumber(n / 1000000000, 1) .. "b"
  elseif n >= 1000000 then
    return trimNumber(n / 1000000, 1) .. "m"
  elseif n >= 1000 then
    return trimNumber(n / 1000, 1) .. "k"
  end
  return tostring(math.floor(n))
end

local TOP_H = 3
local BOT_H = 3
local MAIN_Y = 4
local MAIN_H = HEIGHT - TOP_H - BOT_H
local LEFT_W = math.floor(WIDTH * 0.60)
local SCROLL_X = LEFT_W - 2
local SEPARATOR1 = LEFT_W
local SEPARATOR2 = LEFT_W + 1
local LIST_X = 2
local LIST_Y = MAIN_Y + 3
local LIST_H = MAIN_H - 4
local LIST_W = SCROLL_X - LIST_X
local COL_NAME_X = 3
local COL_ME_X = SCROLL_X - 26
local COL_COINA_X = SCROLL_X - 16
local COL_EMA_X = SCROLL_X - 7
local RIGHT_INNER_X = LEFT_W + 3
local RIGHT_INNER_W = WIDTH - RIGHT_INNER_X - 1
local INFO_Y = MAIN_Y + 1
local QTY_Y = INFO_Y + 8
local TOTAL_Y = QTY_Y + 5
local BTN_Y = TOTAL_Y + 2
local ACC_Y = BTN_Y + 3
local BOT_Y = HEIGHT - 2

local allItems = {}
buyItemsCache = nil
sellItemsCache = nil
local currentShopMode = "buy"
availabilityFilter = "all" -- all / available / unavailable
availabilityMenuOpen = false
local catalogStatus = "Загрузка каталога..."
local catalogLoadError = nil

local session = {
  active = false,
  playerName = nil,
}

local pimOwner = nil
local lastPimCheck = 0
local uiState = "idle" -- idle / auth / shop
local authDeadline = nil

-- Блокировка терминала: управлять магазином может только игрок,
-- который открыл текущую PIM-сессию.
function isPimOwner(playerName)
  if not session.active or not pimOwner then return false end
  if type(playerName) ~= "string" or playerName == "" then return false end
  return lowerText(playerName) == lowerText(pimOwner)
end

-- Запись диагностических логов отключена.
-- Функция сохранена как пустая, чтобы не менять остальную логику магазина.
function writeDebugLog(_)
end

-- Удаляем старый диагностический файл, если он остался от предыдущих версий.
pcall(function()
  if os and type(os.remove) == "function" then
    os.remove("/home/vip_shop_debug.log")
  end
end)

-- Ctrl+C/interrupt и другие ошибки event.pull не должны завершать магазин.
function safeEventPull(timeout)
  local result = {pcall(event.pull, timeout)}
  if not result[1] then
    writeDebugLog("⚠️ Попытка прервать скрипт: " .. tostring(result[2]))
    return {}
  end
  table.remove(result, 1)
  return result
end

local blacklist = {
  ["customnpcs:npcMoney"] = true,
}

-- Разбор обычного HTTP-адреса: http://host:port/path

function ModemRPC.ensureDirectory(path)
  if not Filesystem.exists(path) then Filesystem.makeDirectory(path) end
end

function ModemRPC.readTable(path)
  if not Filesystem.exists(path) then return nil end
  local file = io.open(path, "r")
  if not file then return nil end
  local raw = file:read("*a")
  file:close()
  if not raw or raw == "" then return nil end
  local ok, value = pcall(Serialization.unserialize, raw)
  if ok and type(value) == "table" then return value end
  return nil
end

function ModemRPC.writeTable(path, value)
  ModemRPC.ensureDirectory(MODEM_CACHE_DIR)
  local raw = Serialization.serialize(value)
  local tempPath = path .. ".tmp"
  local file = io.open(tempPath, "w")
  if not file then return false end
  file:write(raw)
  file:close()
  if Filesystem.exists(path) then Filesystem.remove(path) end
  local ok = pcall(Filesystem.rename, tempPath, path)
  if ok and Filesystem.exists(path) then return true end
  local fallback = io.open(path, "w")
  if not fallback then return false end
  fallback:write(raw)
  fallback:close()
  pcall(Filesystem.remove, tempPath)
  return true
end

function ModemRPC.loadMeta()
  if type(ModemRPC.cacheMeta) == "table" then return ModemRPC.cacheMeta end
  ModemRPC.cacheMeta = ModemRPC.readTable(MODEM_CACHE_META) or {buyVersion=0,sellVersion=0}
  return ModemRPC.cacheMeta
end

function ModemRPC.saveMeta()
  return ModemRPC.writeTable(MODEM_CACHE_META, ModemRPC.cacheMeta or {})
end

function ModemRPC.newRequestId()
  ModemRPC.requestCounter = ModemRPC.requestCounter + 1
  return table.concat({TERMINAL_ID,tostring(math.floor(computer.uptime()*1000)),tostring(ModemRPC.requestCounter),tostring(math.random(100000,999999))}, "-")
end

function ModemRPC.queuePush(action, data)
  ModemRPC.pushQueue[#ModemRPC.pushQueue+1] = {action=tostring(action or ""),data=type(data)=="table" and data or {}}
end

function ModemRPC.popPush()
  if #ModemRPC.pushQueue == 0 then return nil end
  return table.remove(ModemRPC.pushQueue,1)
end

function ModemRPC.acceptPushEvent(ev)
  if type(ev)~="table" or ev[1]~="modem_message" then return false end
  if ev[4]~=MODEM_CLIENT_PORT or ev[6]~=MODEM_PROTOCOL or ev[7]~="push" or ev[8]~=MODEM_NETWORK_KEY then return false end
  local ok,data=pcall(Serialization.unserialize,tostring(ev[10] or ""))
  if not ok or type(data)~="table" then data={} end
  ModemRPC.queuePush(ev[9],data)
  return true
end

function ModemRPC.discover(timeout)
  if ModemRPC.serverAddress and ModemRPC.serverAddress~="" then return ModemRPC.serverAddress end
  local requestId=ModemRPC.newRequestId()
  modem.broadcast(MODEM_SERVER_PORT,MODEM_PROTOCOL,"discover",MODEM_NETWORK_KEY,requestId,MODEM_CLIENT_PORT)
  local deadline=computer.uptime()+(tonumber(timeout) or 3)
  while computer.uptime()<deadline do
    local ev={event.pull(math.max(0.05,deadline-computer.uptime()),"modem_message")}
    if ev[1]=="modem_message" and ev[4]==MODEM_CLIENT_PORT and ev[6]==MODEM_PROTOCOL and ev[7]=="discover_reply" and ev[8]==MODEM_NETWORK_KEY and tostring(ev[9] or "")==requestId then
      ModemRPC.serverAddress=tostring(ev[3] or ev[10] or "")
      ModemRPC.lastError=nil
      return ModemRPC.serverAddress
    end
    ModemRPC.acceptPushEvent(ev)
  end
  ModemRPC.lastError="Центральный server.lua не найден"
  return nil
end

function ModemRPC.sendRequest(requestId,payload)
  local address=ModemRPC.discover(2)
  if not address then return false end
  payload=type(payload)=="table" and payload or {}
  payload.terminalId=TERMINAL_ID
  return modem.send(address,MODEM_SERVER_PORT,MODEM_PROTOCOL,"request",MODEM_NETWORK_KEY,requestId,MODEM_CLIENT_PORT,Serialization.serialize(payload))
end

function ModemRPC.request(payload,timeout)
  timeout=tonumber(timeout) or ModemRPC.timeout
  local requestId=ModemRPC.newRequestId()
  local chunks={}
  local expectedTotal=nil
  for attempt=1,2 do
    if ModemRPC.sendRequest(requestId,payload) then
      local deadline=computer.uptime()+timeout
      while computer.uptime()<deadline do
        local ev={event.pull(math.max(0.05,deadline-computer.uptime()),"modem_message")}
        if ev[1]=="modem_message" then
          if not ModemRPC.acceptPushEvent(ev) and ev[4]==MODEM_CLIENT_PORT and ev[6]==MODEM_PROTOCOL and ev[7]=="chunk" and ev[8]==MODEM_NETWORK_KEY and tostring(ev[9] or "")==requestId then
            local index,total,chunk=tonumber(ev[10]),tonumber(ev[11]),ev[12]
            if index and total and type(chunk)=="string" then
              chunks[index]=chunk
              expectedTotal=total
              local ready=true
              for part=1,expectedTotal do if type(chunks[part])~="string" then ready=false break end end
              if ready then
                local ok,response=pcall(Serialization.unserialize,table.concat(chunks))
                if ok and type(response)=="table" then ModemRPC.lastError=nil return response,nil end
                return nil,"Повреждённый ответ центрального сервера"
              end
            end
          end
        end
      end
    end
    ModemRPC.serverAddress=""
  end
  ModemRPC.lastError="Центральный сервер не отвечает"
  return nil,ModemRPC.lastError
end

function ModemRPC.catalogFromCache(kind)
  return ModemRPC.readTable(kind=="sell" and MODEM_CACHE_SELL or MODEM_CACHE_BUY)
end

function ModemRPC.saveCatalogCache(kind,data,version)
  ModemRPC.writeTable(kind=="sell" and MODEM_CACHE_SELL or MODEM_CACHE_BUY,data)
  local meta=ModemRPC.loadMeta()
  if kind=="sell" then meta.sellVersion=tonumber(version) or 0 else meta.buyVersion=tonumber(version) or 0 end
  ModemRPC.saveMeta()
end

function ModemRPC.getCatalog(kind,timeout)
  local meta=ModemRPC.loadMeta()
  local sessionData=ModemRPC.sessionData or {}
  local serverVersion=kind=="sell" and tonumber(sessionData.sellVersion) or tonumber(sessionData.buyVersion)
  local localVersion=kind=="sell" and tonumber(meta.sellVersion) or tonumber(meta.buyVersion)
  if serverVersion and localVersion==serverVersion then
    local cached=ModemRPC.catalogFromCache(kind)
    if type(cached)=="table" then return cached,nil end
  end
  local response,err=ModemRPC.request({action="get_catalog",catalog=kind},timeout or 8)
  if response and response.status=="ok" and type(response.data)=="table" then
    local data=response.data
    local version=tonumber(data.version) or serverVersion or 0
    ModemRPC.saveCatalogCache(kind,data,version)
    if ModemRPC.sessionData then if kind=="sell" then ModemRPC.sessionData.sellVersion=version else ModemRPC.sessionData.buyVersion=version end end
    return data,nil
  end
  local cached=ModemRPC.catalogFromCache(kind)
  if type(cached)=="table" then return cached,err or (response and response.message) end
  return nil,err or (response and response.message) or "Каталог отсутствует"
end

function ModemRPC.sessionOpen(playerName)
  local response,err=ModemRPC.request({action="session_open",name=playerName},5)
  if response and response.status=="ok" and type(response.data)=="table" then
    ModemRPC.sessionData=response.data
    ModemRPC.globalMaintenance=response.data.maintenance==true
    ModemRPC.terminalPaused=response.data.terminalPaused==true
  end
  return response,err
end

local function parseUrl(url)
  local schemaEnd = url:find("://", 1, true)
  if not schemaEnd then
    return nil, nil, nil
  end

  local rest = url:sub(schemaEnd + 3)
  local slashPos = rest:find("/", 1, true)
  local hostPort
  local path

  if slashPos then
    hostPort = rest:sub(1, slashPos - 1)
    path = rest:sub(slashPos)
  else
    hostPort = rest
    path = "/"
  end

  local host = hostPort
  local port = 80
  local colonPos = hostPort:match("^.*():")
  if colonPos then
    local parsedPort = tonumber(hostPort:sub(colonPos + 1))
    if parsedPort then
      host = hostPort:sub(1, colonPos - 1)
      port = parsedPort
    end
  end

  return host, port, path
end

-- Рабочая HTTP-функция перенесена из старого магазина.
local function httpRequest(url, timeout)
  url=tostring(url or "")
  if url==CATALOG_URL or url:find("catalog_buy",1,true) then return ModemRPC.getCatalog("buy",timeout) end
  if url==SELL_ITEMS_URL or url:find("catalog_sell",1,true) then return ModemRPC.getCatalog("sell",timeout) end
  if url==Maintenance.configUrl or url:find("/state",1,true) then
    local response,err=ModemRPC.request({action="get_state"},timeout)
    if response and response.status=="ok" then
      local data=response.data or {}
      ModemRPC.globalMaintenance=data.maintenance==true
      ModemRPC.terminalPaused=data.terminalPaused==true
      return {paused=ModemRPC.globalMaintenance or ModemRPC.terminalPaused,maintenance=ModemRPC.globalMaintenance,terminalPaused=ModemRPC.terminalPaused},nil
    end
    return nil,err or (response and response.message)
  end
  if url==Maintenance.signalUrl then return {},nil end
  if url:find("check_ban",1,true) then
    local playerName=url:match("[?&]name=([^&]+)")
    local response,err=ModemRPC.sessionOpen(playerName or "")
    if response and response.status=="ok" then
      local user=(response.data and response.data.user) or {}
      return {banned=user.banned==true,reason=user.banReason,duration=user.banDuration,admin=user.bannedBy,date=user.bannedAt},nil
    end
    return nil,err or (response and response.message)
  end
  return nil,"Неизвестный modem-ресурс: "..url
end

local function httpPostJson(url,payload,timeout)
  payload=type(payload)=="table" and ModemRPC.copy(payload) or {}
  if url==REGISTER_PLAYER_URL and not payload.action then
    payload.action="update_balance" payload.coin=tonumber(payload.coin) or 0 payload.ema=tonumber(payload.ema) or 0 payload.transactions=tonumber(payload.transactions) or 0 payload.agreed=true
  end
  if payload.action=="get_balance" and ModemRPC.sessionData and type(ModemRPC.sessionData.user)=="table" and tostring(ModemRPC.sessionData.user.name or ""):lower()==tostring(payload.name or ""):lower() then
    return {status="ok",data=ModemRPC.copy(ModemRPC.sessionData.user)},nil
  end
  return ModemRPC.request(payload,timeout)
end

local function getMEQuantities()
  local quantities = {}
  local craftableFlags = {}

  if not component.isAvailable("me_interface") then
    return quantities, craftableFlags
  end

  local me = component.me_interface
  local ok, networkItems = pcall(me.getItemsInNetwork)
  if not ok or type(networkItems) ~= "table" then
    return quantities, craftableFlags
  end

  for _, meItem in pairs(networkItems) do
    if type(meItem) == "table" then
      -- NBT-предметы в этой сборке приходят как
      -- {size=..., fingerprint={id=..., dmg=..., nbt_hash=...}}.
      -- Обычные предметы могут по-прежнему иметь поля id/name сверху.
      local fingerprint = type(meItem.fingerprint) == "table"
        and meItem.fingerprint or meItem
      local internalName = fingerprint.name or fingerprint.id
        or meItem.name or meItem.id
      if internalName and not blacklist[internalName] then
        local damage = tonumber(
          fingerprint.damage or fingerprint.dmg
          or meItem.damage or meItem.dmg
        ) or 0
        local amount = tonumber(
          meItem.size or meItem.qty or meItem.count or meItem.amount
          or fingerprint.size or fingerprint.qty
        ) or 0
        local key = tostring(internalName) .. ":" .. tostring(damage)
        quantities[key] = (quantities[key] or 0) + amount

        if meItem.isCraftable == true or fingerprint.isCraftable == true then
          craftableFlags[key] = true
        end
      end
    end
  end

  return quantities, craftableFlags
end

local function parseCatalogKey(key, mapping)
  mapping = mapping or {}

  local internalName = mapping.internalName or mapping.id
  local damage = tonumber(mapping.damage) or 0

  if not internalName then
    local parsedName, parsedDamage = tostring(key):match("^(.*):(-?%d+)$")
    if parsedName then
      internalName = parsedName
      damage = tonumber(parsedDamage) or 0
    else
      internalName = tostring(key)
    end
  end

  return internalName, damage
end

local function addCatalogItem(target, mapKey, mapping, meQuantities, meCraftableFlags)
  if type(mapping) ~= "table" then return end

  local internalName, damage = parseCatalogKey(mapKey, mapping)
  if not internalName or blacklist[internalName] then return end

  local priceCoin = tonumber(mapping.priceCoin or mapping.coina or mapping.coin) or 0
  local priceEma = tonumber(mapping.priceEma or mapping.ema) or 0
  if priceCoin <= 0 and priceEma <= 0 then return end

  local stockKey = internalName .. ":" .. tostring(damage)
  local qty = tonumber(meQuantities[stockKey]) or 0
  local displayName = mapping.displayName or mapping.label or mapping.name or internalName

  target[#target + 1] = {
    name = tostring(displayName),
    me = formatQuantity(qty),
    meRaw = qty,
    coina = trimNumber(priceCoin, 4),
    ema = trimNumber(priceEma, 4),
    star = qty > 0,
    internalName = internalName,
    damage = damage,
    priceCoin = priceCoin,
    priceEma = priceEma,
    qty = qty,
    craftable = meCraftableFlags and meCraftableFlags[stockKey] == true or false,
    -- Необязательный точный NBT-вариант. Если hash в каталоге не указан,
    -- магазин сам выберет доступные варианты предмета из МЭ.
    nbt_hash = mapping.nbt_hash or mapping.nbtHash,
    article = mapping.article or mapping.sku or mapping.code,
    _searchName = lowerText(tostring(displayName)),
  }
end

local function sortLoadedItems(loadedItems)
  table.sort(loadedItems, function(a, b)
    return lowerText(a.name) < lowerText(b.name)
  end)

  for index, item in ipairs(loadedItems) do
    if not item.article or tostring(item.article) == "" then
      item.article = string.format("#VIP-%03d", index)
    else
      item.article = tostring(item.article)
      if item.article:sub(1, 1) ~= "#" then
        item.article = "#" .. item.article
      end
    end
  end
end

local function loadCatalogItems()
  catalogStatus = "Загрузка каталога покупок..."
  catalogLoadError = nil

  local catalog, err = httpRequest(CATALOG_URL, HTTP_TIMEOUT)
  if not catalog then
    allItems = {}
    catalogLoadError = err or "Неизвестная ошибка"
    catalogStatus = "ОШИБКА ЗАГРУЗКИ КАТАЛОГА: " .. catalogLoadError
    return false, catalogLoadError
  end

  -- Поддержка прямого catalog.json и обёрток {catalog={...}} / {items={...}}.
  if type(catalog.catalog) == "table" then
    catalog = catalog.catalog
  elseif type(catalog.items) == "table" then
    catalog = catalog.items
  end

  local meQuantities, meCraftableFlags = getMEQuantities()
  local loadedItems = {}

  if #catalog > 0 then
    for index, mapping in ipairs(catalog) do
      local key = mapping.internalName or mapping.id or mapping.name or tostring(index)
      if mapping.damage ~= nil then
        key = key .. ":" .. tostring(mapping.damage)
      end
      addCatalogItem(loadedItems, key, mapping, meQuantities, meCraftableFlags)
    end
  else
    for mapKey, mapping in pairs(catalog) do
      addCatalogItem(loadedItems, mapKey, mapping, meQuantities, meCraftableFlags)
    end
  end

  sortLoadedItems(loadedItems)
  buyItemsCache = loadedItems
  allItems = buyItemsCache
  catalogStatus = "Каталог покупок загружен: " .. tostring(#allItems) .. " товаров"
  Performance.buyCatalogLoadedAt = computer.uptime()
  return true, nil
end

local function addSellItem(target, mapping, fallbackKey)
  if type(mapping) ~= "table" then return end

  local internalName = mapping.internalName or mapping.id or mapping.name or fallbackKey
  -- customnpcs:npcMoney запрещён только в каталоге ПОКУПОК.
  -- В sell_items.json этот предмет является обычным товаром продажи и
  -- пополняет EMA, поэтому здесь blacklist намеренно не применяется.
  if not internalName then return end

  local priceCoin = tonumber(mapping.priceCoin or mapping.coina or mapping.coin) or 0
  local priceEma = tonumber(mapping.priceEma or mapping.ema) or 0
  if priceCoin <= 0 and priceEma <= 0 then return end

  local damage = tonumber(mapping.damage) or 0
  local displayName = mapping.displayName or mapping.label or mapping.name or internalName
  local configuredQty = tonumber(mapping.qty or mapping.amount or mapping.count) or 0

  target[#target + 1] = {
    name = tostring(displayName),
    -- В режиме продажи это не остаток МЭ, поэтому выводим значение из файла,
    -- а если его нет — прочерк.
    me = configuredQty > 0 and formatQuantity(configuredQty) or "-",
    meRaw = configuredQty,
    coina = trimNumber(priceCoin, 4),
    ema = trimNumber(priceEma, 4),
    star = true,
    internalName = tostring(internalName),
    damage = damage,
    priceCoin = priceCoin,
    priceEma = priceEma,
    qty = configuredQty,
    canSell = true,
    article = mapping.article or mapping.sku or mapping.code,
    _searchName = lowerText(tostring(displayName)),
  }
end

local function loadSellItems()
  catalogStatus = "Загрузка каталога продаж..."
  catalogLoadError = nil

  local result, err = httpRequest(SELL_ITEMS_URL, HTTP_TIMEOUT)
  if not result then
    allItems = {}
    catalogLoadError = err or "Неизвестная ошибка"
    catalogStatus = "ОШИБКА ЗАГРУЗКИ sell_items.json: " .. catalogLoadError
    return false, catalogLoadError
  end

  -- В старом коде файл приходит как {sellItems=[...]}, но поддерживаем
  -- также прямой массив и обёртку {items=[...]}.
  local sellData = result
  if type(result.sellItems) == "table" then
    sellData = result.sellItems
  elseif type(result.items) == "table" then
    sellData = result.items
  end

  local loadedItems = {}
  if #sellData > 0 then
    for index, mapping in ipairs(sellData) do
      addSellItem(loadedItems, mapping, tostring(index))
    end
  else
    for key, mapping in pairs(sellData) do
      if type(mapping) == "table" then
        local copy = mapping
        if not copy.internalName and not copy.id and not copy.name then
          copy = {}
          for field, value in pairs(mapping) do
            copy[field] = value
          end
          copy.internalName = key
        end
        addSellItem(loadedItems, copy, key)
      end
    end
  end

  sortLoadedItems(loadedItems)
  sellItemsCache = loadedItems
  allItems = sellItemsCache
  catalogStatus = "Каталог продаж загружен: " .. tostring(#allItems) .. " товаров"
  Performance.sellCatalogLoadedAt = computer.uptime()
  return true, nil
end

local function loadItemsForCurrentMode(forceReload)
  local now = computer.uptime()

  if currentShopMode == "sell" then
    local cacheFresh = sellItemsCache
      and Performance.sellCatalogLoadedAt > 0
      and now - Performance.sellCatalogLoadedAt
        < Performance.catalogMaxAge

    if cacheFresh and not forceReload then
      allItems = sellItemsCache
      catalogLoadError = nil
      catalogStatus =
        "Каталог продаж загружен: "
        .. tostring(#allItems) .. " товаров"
      return true, nil
    end

    return loadSellItems()
  end

  local cacheFresh = buyItemsCache
    and Performance.buyCatalogLoadedAt > 0
    and now - Performance.buyCatalogLoadedAt
      < Performance.catalogMaxAge

  if cacheFresh and not forceReload then
    allItems = buyItemsCache
    catalogLoadError = nil
    catalogStatus =
      "Каталог покупок загружен: "
      .. tostring(#allItems) .. " товаров"
    return true, nil
  end

  return loadCatalogItems()
end

local items = {}
for i, v in ipairs(allItems) do items[i] = v end

local selectedIndex = 1
local scrollOffset = 0
local quantity = ""
local searchQuery = ""
local searchFocused = false
local qtyFocused = false

-- Поиск и поля ввода имеют рамку [ ... ].
local SEARCH_X = 2
local SEARCH_Y = 3
local SEARCH_CLEAR_TEXT = "[ СТЕРЕТЬ ]"

local AVAILABILITY_FILTER_LABELS = {
  all = "ВСЕ ТОВАРЫ",
  available = "В НАЛИЧИИ",
  unavailable = "НЕ В НАЛИЧИИ",
}

local function getAvailabilityButtonText()
  local label = AVAILABILITY_FILTER_LABELS[availabilityFilter]
    or AVAILABILITY_FILTER_LABELS.all
  return "[ " .. label .. " ˅ ]"
end

local SEARCH_CLEAR_W = unicode.len(SEARCH_CLEAR_TEXT) + 2
local AVAILABILITY_BUTTON_MAX_TEXT = "[ НЕ В НАЛИЧИИ ˅ ]"
local AVAILABILITY_BUTTON_MAX_W = unicode.len(AVAILABILITY_BUTTON_MAX_TEXT) + 2
local SEARCH_W = math.max(
  12,
  math.min(40, LEFT_W - SEARCH_X - SEARCH_CLEAR_W - AVAILABILITY_BUTTON_MAX_W - 3)
)
local SEARCH_CLEAR_X = SEARCH_X + SEARCH_W + 1
local AVAILABILITY_BUTTON_MAX_X = SEARCH_CLEAR_X + SEARCH_CLEAR_W + 1
local AVAILABILITY_BUTTON_RIGHT = AVAILABILITY_BUTTON_MAX_X + AVAILABILITY_BUTTON_MAX_W - 1
AVAILABILITY_BUTTON_W = AVAILABILITY_BUTTON_MAX_W
AVAILABILITY_BUTTON_X = AVAILABILITY_BUTTON_MAX_X

local function updateAvailabilityButtonGeometry(label)
  label = label or getAvailabilityButtonText()
  AVAILABILITY_BUTTON_W = unicode.len(label) + 2
  AVAILABILITY_BUTTON_X = AVAILABILITY_BUTTON_RIGHT - AVAILABILITY_BUTTON_W + 1
  return label
end
AVAILABILITY_MENU_OPTIONS = {
  {key="all", label="[ ВСЕ ТОВАРЫ ]"},
  {key="available", label="[ В НАЛИЧИИ ]"},
  {key="unavailable", label="[ НЕ В НАЛИЧИИ ]"},
}

local availabilityMenuMaxLabel = 0
for _, option in ipairs(AVAILABILITY_MENU_OPTIONS) do
  availabilityMenuMaxLabel = math.max(
    availabilityMenuMaxLabel,
    unicode.len(option.label)
  )
end

-- Два символа нужны для маркера "> ", ещё два — для внутренних отступов.
AVAILABILITY_MENU_W = availabilityMenuMaxLabel + 4
AVAILABILITY_MENU_X = math.max(
  2,
  math.min(AVAILABILITY_BUTTON_X, LEFT_W - AVAILABILITY_MENU_W - 2)
)
AVAILABILITY_MENU_Y = SEARCH_Y + 1

local BOTTOM_BUY_TEXT = "[ Покупки ]"
local BOTTOM_SELL_TEXT = "[ Продажи ]"
local BOTTOM_BUY_W = unicode.len(BOTTOM_BUY_TEXT) + 2
local BOTTOM_SELL_W = unicode.len(BOTTOM_SELL_TEXT) + 2
local BOTTOM_BUY_X = 2
local BOTTOM_SELL_X = BOTTOM_BUY_X + BOTTOM_BUY_W + 2

-- Глобальные значения, чтобы не увеличивать число local-переменных
-- в основном блоке Lua, где действует ограничение 200 local.
BOTTOM_AUTOCRAFT_TEXT = "[ Автокрафт ]"
BOTTOM_AUTOCRAFT_W = unicode.len(BOTTOM_AUTOCRAFT_TEXT) + 2
BOTTOM_AUTOCRAFT_X = BOTTOM_SELL_X + BOTTOM_SELL_W + 2

local QTY_CLEAR_TEXT = "[ Стереть ]"
local QTY_CLEAR_W = unicode.len(QTY_CLEAR_TEXT) + 2

local account = {
  nick = "Ожидание игрока",
  coina = "0",
  ema = "0",
  regDate = "-",
  trans = "0",
  balanceCoin = 0,
  balanceEma = 0,
  transactions = 0,
  agreed = false,
}

local popupState = nil
local popupButtons = {}
local transactionLock = false

-- Эти функции объявлены заранее, потому что PIM-сессия использует их
-- до расположенных ниже реализаций интерфейса.
local drawAccountInfo
local drawRightPanel
local drawIdleScreen
local drawAuthScreen
local redrawAll
local filterItems
local closePopup

-- SELECTOR: используем адрес компонента и component.invoke. Это надёжнее
-- прямого вызова proxy.setSlot на разных сборках OpenPeripheral.
local selector = nil
selectorAddress = nil

local function findSelector()
  local componentTypes = {
    "openperipheral_selector",
    "item_selector",
    "selector",
  }

  for _, componentType in ipairs(componentTypes) do
    for address in component.list(componentType) do
      local ok, proxy = pcall(component.proxy, address)
      if ok and proxy then
        return proxy, address
      end
    end
  end

  return nil, nil
end

function ensureSelector()
  if selector and selectorAddress then
    local ok, detectedType = pcall(component.type, selectorAddress)
    if ok and detectedType then return true end
  end

  selector, selectorAddress = findSelector()
  return selector ~= nil and selectorAddress ~= nil
end

function normalizeSelectorStack(stack)
  if not stack then return nil, nil, nil end

  local id = tostring(stack.id or stack.name or "")
  local damage = tonumber(stack.dmg or stack.damage) or 0

  -- Некоторые catalog/sell_items содержат ключ вида mod:item:damage.
  -- SELECTOR принимает только mod:item, поэтому metadata отделяем.
  local baseId, trailingDamage = id:match("^(.-):(-?%d+)$")
  if baseId and baseId:find(":", 1, true) then
    id = baseId
    if stack.dmg == nil and stack.damage == nil then
      damage = tonumber(trailingDamage) or 0
    end
  end

  if id ~= "" and not id:find(":", 1, true) then
    id = "minecraft:" .. id
  end

  return id, damage, {
    {id=id, dmg=damage},
    {id=id, damage=damage},
    {name=id, damage=damage},
    {name=id, dmg=damage},
  }
end

function setSelectorSlot(slot, stack)
  if not ensureSelector() then return false end

  if stack == nil then
    local attempts = {
      function() return component.invoke(selectorAddress, "setSlot", slot, nil) end,
      function() return selector.setSlot(slot, nil) end,
      function() return selector.setSlot(selector, slot, nil) end,
    }
    for _, attempt in ipairs(attempts) do
      local ok = pcall(attempt)
      if ok then return true end
    end
    return false
  end

  local id, damage, variants = normalizeSelectorStack(stack)
  if not id or id == "" then return false end

  for _, variant in ipairs(variants) do
    local attempts = {
      function() return component.invoke(selectorAddress, "setSlot", slot, variant) end,
      function() return selector.setSlot(slot, variant) end,
      function() return selector.setSlot(selector, slot, variant) end,
    }
    for _, attempt in ipairs(attempts) do
      local ok = pcall(attempt)
      if ok then return true end
    end
  end

  -- Запасной вариант для реализаций setSlot(slot, id, damage).
  local ok = pcall(component.invoke, selectorAddress, "setSlot", slot, id, damage)
  if ok then return true end

  selector = nil
  selectorAddress = nil
  return false
end

function clearSelector()
  if SelectorCache.key == "__clear__" then return end

  setSelectorSlot(0, nil)
  setSelectorSlot(1, nil)
  SelectorCache.key = "__clear__"
end

function updateSelectorDisplay(item)
  if not item then
    clearSelector()
    return
  end

  local id = item.internalName or item.id or item.name
  if not id or id == "" then
    clearSelector()
    return
  end

  local damage = tonumber(item.damage) or 0
  local selectorKey = tostring(id) .. ":" .. tostring(damage)

  -- При поиске и частичной перерисовке один и тот же предмет больше не
  -- отправляется в Item Selector повторно.
  if SelectorCache.key == selectorKey then return end

  local stack = {
    id = tostring(id),
    dmg = damage,
  }

  local firstOk = setSelectorSlot(0, stack)
  local secondOk = setSelectorSlot(1, stack)

  if firstOk or secondOk then
    SelectorCache.key = selectorKey
  else
    SelectorCache.key = nil
  end
end

selector, selectorAddress = findSelector()
clearSelector()

local function resetAccount()
  account.nick = "Ожидание игрока"
  account.coina = "0"
  account.ema = "0"
  account.regDate = "-"
  account.trans = "0"
  account.balanceCoin = 0
  account.balanceEma = 0
  account.transactions = 0
  account.agreed = false
  account.banned = false
  account.banReason = nil
  account.banDuration = 0
  account.bannedBy = nil
  account.bannedAt = nil
end

local function findPlayerRecord(users, playerName)
  if type(users) ~= "table" then return nil end

  if type(users.users) == "table" then
    users = users.users
  elseif type(users.players) == "table" then
    users = users.players
  elseif type(users.data) == "table" then
    users = users.data
  end

  if type(users[playerName]) == "table" then
    return users[playerName]
  end

  local target = lowerText(playerName)
  for key, value in pairs(users) do
    if type(value) == "table" then
      local recordName = value.name or value.nick or value.player or key
      if lowerText(recordName) == target then
        return value
      end
    end
  end

  return nil
end

-- Автоматическая регистрация нового игрока на основном хостинге.
-- Используется отдельный register_player.php: он создаёт только отсутствующего
-- игрока и никогда не обнуляет баланс уже существующей записи.
function createPlayerOnHosting(playerName)
  if type(playerName)~="string" or playerName=="" or playerName=="null" then return false,"Имя игрока не определено",nil end
  local response,requestError=ModemRPC.request({action="update_balance",name=playerName,coin=0,ema=0,transactions=0,agreed=true,regDate="Новый аккаунт"},5)
  if not response or response.status~="ok" then return false,requestError or (response and response.message) or "Центральный сервер не ответил",nil end
  local player=type(response.data)=="table" and response.data or {}
  player.name=tostring(player.name or playerName)
  return true,nil,player
end

local function loadAccountForPlayer(playerName)
  if not playerName or playerName == "" or playerName == "null" then
    return false, "Имя игрока не определено"
  end

  account.nick = tostring(playerName)
  account.coina = "..."
  account.ema = "..."
  account.regDate = "Загрузка..."
  account.trans = "..."

  if uiState == "shop" and drawAccountInfo then
    drawAccountInfo()
  end

  -- VPS является единственным источником баланса.
  local response, err = httpPostJson(
    SecurePurchase.url,
    {
      action = "get_balance",
      name = playerName,
    },
    SecurePurchase.timeout
  )

  if not response or response.status ~= "ok" then
    account.balanceCoin = 0
    account.balanceEma = 0
    account.transactions = 0
    account.agreed = false
    account.coina = "0"
    account.ema = "0"
    account.regDate = "Ошибка загрузки"
    account.trans = "0"
    return false, err or response and response.message
      or "Центральный сервер не ответил"
  end

  local player = type(response.data) == "table"
    and response.data
    or response

  if player.found == false then
    -- Создаём/получаем запись на основном хостинге.
    local created, createError, registeredPlayer =
      createPlayerOnHosting(playerName)

    if not created then
      account.balanceCoin = 0
      account.balanceEma = 0
      account.transactions = 0
      account.agreed = false
      account.coina = "0"
      account.ema = "0"
      account.regDate = "Ошибка регистрации"
      account.trans = "0"
      return false, createError
    end

    local updateResponse, updateError = httpPostJson(
      SecurePurchase.url,
      {
        action = "update_balance",
        source = "hosting",
        name = tostring(registeredPlayer.name or playerName),
        coin = tonumber(
          registeredPlayer.balanceCoin
          or registeredPlayer.coin
          or registeredPlayer.coina
        ) or 0,
        ema = tonumber(
          registeredPlayer.balanceEma
          or registeredPlayer.ema
        ) or 0,
        transactions = tonumber(
          registeredPlayer.transactions
          or registeredPlayer.trans
        ) or 0,
        agreed = registeredPlayer.agreed == true,
        regDate = registeredPlayer.regDate
          or registeredPlayer.registrationDate,
      },
      SecurePurchase.timeout
    )

    if not updateResponse or updateResponse.status ~= "ok" then
      return false,
        updateError
        or updateResponse and updateResponse.message
        or "Не удалось создать аккаунт на центральном сервере"
    end

    player = type(updateResponse.data) == "table"
      and updateResponse.data
      or updateResponse

    player.agreed = registeredPlayer.agreed == true
    player.regDate = registeredPlayer.regDate
      or registeredPlayer.registrationDate
  end

  account.nick = tostring(
    player.name or player.nick or player.player or playerName
  )
  account.balanceCoin = tonumber(
    player.balanceCoin
    or player.coin
    or player.coina
    or player.balance
  ) or 0
  account.balanceEma = tonumber(
    player.balanceEma or player.ema
  ) or 0
  account.transactions = tonumber(
    player.transactions
    or player.trans
    or player.transactionCount
  ) or 0
  account.agreed = player.agreed == true
  account.coina = trimNumber(account.balanceCoin, 4)
  account.ema = trimNumber(account.balanceEma, 4)
  account.regDate = tostring(
    player.regDate
    or player.registrationDate
    or player.registeredAt
    or "Неизвестно"
  )
  account.trans = tostring(math.floor(account.transactions))
  account.banned = player.banned == true
  account.banReason = player.banReason or player.reason
  account.banDuration = tonumber(
    player.banDuration or player.duration or player.expires
  ) or 0
  account.bannedBy = player.bannedBy
    or player.banAdmin
    or player.admin
  account.bannedAt = player.bannedAt
    or player.banDate
    or player.date

  -- Запросы ниже выполняются только при наличии незавершённых
  -- операций на HDD.
  if SecurePurchase
    and type(SecurePurchase.retryForPlayer) == "function"
  then
    SecurePurchase.retryForPlayer(playerName)
  end

  if SecureSale
    and type(SecureSale.retryForPlayer) == "function"
  then
    SecureSale.retryForPlayer(playerName)
  end

  return true, nil
end

local function getPimAddr()
  for address in component.list("pim") do
    return address
  end
  return nil
end

local function getPimProxy()
  local address = getPimAddr()
  if not address then return nil end

  local ok, proxy = pcall(component.proxy, address)
  if ok then return proxy end
  return nil
end

local function callPimMethod(pim, methodName)
  if not pim or type(pim[methodName]) ~= "function" then
    return nil
  end

  local ok, result = pcall(pim[methodName])
  if ok then return result end

  ok, result = pcall(pim[methodName], pim)
  if ok then return result end
  return nil
end

local function normalizePlayerName(value)
  if type(value) == "table" then
    value = value.name or value.playerName or value.username or value.nick
  end

  if type(value) ~= "string" then return nil end
  if value == "" or value == "null" then return nil end
  return value
end

local function getPlayerOnPim()
  local pim = getPimProxy()
  if not pim then return nil end

  local methods = {"getPlayer", "getPlayerName", "getUsername"}
  for _, methodName in ipairs(methods) do
    local name = normalizePlayerName(callPimMethod(pim, methodName))
    if name then return name end
  end

  local ok, value = pcall(function() return pim.player end)
  if ok then
    return normalizePlayerName(value)
  end

  return nil
end

local function isPlayerStandingOnPim()
  local pim = getPimProxy()
  if not pim then return nil end

  -- На McSkill именно размер инвентаря PIM является надёжным датчиком:
  -- 40 (или другое положительное число) — игрок стоит на плите;
  -- 0, nil или ошибка вызова — игрок ушёл.
  -- Проверяем это ДО методов имени, потому что getPlayer/getPlayerName
  -- на некоторых сборках ещё некоторое время возвращают старый ник.
  if type(pim.getInventorySize) == "function" then
    local size = callPimMethod(pim, "getInventorySize")
    if size == nil then
      return false
    end
    return (tonumber(size) or 0) > 0
  end

  -- Запасной вариант только для PIM без getInventorySize.
  if getPlayerOnPim() then
    return true
  end

  return nil
end

-- Сканирование предмета в инвентаре игрока через PIM.
-- Используется для каталога продаж, блокировки кнопки и подтверждения сделки.
function SellFlow.normalizeInventoryItemName(value)
  value = tostring(value or "")
  value = value:gsub("§.", "")
  value = value:gsub("%$[0-9a-fA-Fk-oK-OrR]", "")
  value = value:gsub("^%s+", ""):gsub("%s+$", "")
  return lowerText(value)
end

-- У некоторых sell_items.json ID может случайно приходить как
-- minecraft:iron_ingot:0. Последнее число в таком случае является damage,
-- а не частью настоящего ID предмета.
function SellFlow.normalizeInventoryItemId(value, damage)
  value = SellFlow.normalizeInventoryItemName(value)
  local base, suffix = value:match("^(.*):(-?%d+)$")
  if base and tonumber(suffix) == (tonumber(damage) or 0) then
    value = base
  end
  return value
end

function SellFlow.shortInventoryItemName(value)
  value = SellFlow.normalizeInventoryItemName(value)
  return value:match("^[^:]+:(.+)$") or value
end

function SellFlow.inventoryStackMatches(stack, item)
  if type(stack) ~= "table" or not item then return false end

  local stackDamage = tonumber(stack.damage or stack.dmg or stack.meta) or 0
  local itemDamage = tonumber(item.damage) or 0

  local stackName = SellFlow.normalizeInventoryItemId(
    stack.name or stack.id or stack.internalName,
    stackDamage
  )
  local itemName = SellFlow.normalizeInventoryItemId(
    item.internalName or item.id,
    itemDamage
  )
  local stackLabel = SellFlow.normalizeInventoryItemName(
    stack.label or stack.displayName or stack.display_name
  )
  local displayName = SellFlow.normalizeInventoryItemName(
    item.name or item.displayName
  )

  local nameMatches = stackName ~= "" and itemName ~= "" and (
    stackName == itemName
    or SellFlow.shortInventoryItemName(stackName) == SellFlow.shortInventoryItemName(itemName)
  )
  local labelMatches = stackLabel ~= "" and displayName ~= ""
    and stackLabel == displayName

  -- -1 и 32767 используются некоторыми каталогами как wildcard damage.
  local damageMatches = itemDamage == -1 or itemDamage == 32767
    or stackDamage == itemDamage

  return (nameMatches or labelMatches) and damageMatches
end

function SellFlow.getInventorySizeForScan(pim)
  local size = pim and tonumber(callPimMethod(pim, "getInventorySize")) or 40
  -- На текущей PIM размер равен 40. Ограничение 64 защищает от ошибочного
  -- ответа компонента, но не обрезает хотбар и дополнительные слоты.
  return math.max(1, math.min(math.floor(size or 40), 64))
end

function SellFlow.getInventoryStack(pimAddress, pim, slot)
  local ok, stack = pcall(component.invoke, pimAddress, "getStackInSlot", slot)
  if ok and type(stack) == "table" then return stack end

  if pim and type(pim.getStackInSlot) == "function" then
    ok, stack = pcall(pim.getStackInSlot, slot)
    if ok and type(stack) == "table" then return stack end

    ok, stack = pcall(pim.getStackInSlot, pim, slot)
    if ok and type(stack) == "table" then return stack end
  end

  return nil
end

function SellFlow.invalidateInventorySnapshot()
  SellFlow.inventorySnapshot = nil
  SellFlow.inventorySnapshotAt = 0
end

function SellFlow.getInventorySnapshot(force)
  local now = computer.uptime()

  if not force
    and type(SellFlow.inventorySnapshot) == "table"
    and now - (SellFlow.inventorySnapshotAt or 0)
      <= SellFlow.inventorySnapshotMaxAge
  then
    return SellFlow.inventorySnapshot
  end

  local snapshot = {}
  local pimAddress = getPimAddr()

  if not pimAddress then
    SellFlow.inventorySnapshot = snapshot
    SellFlow.inventorySnapshotAt = now
    return snapshot
  end

  local pim = getPimProxy()
  local inventorySize = SellFlow.getInventorySizeForScan(pim)

  for slot = 0, inventorySize do
    local stack = SellFlow.getInventoryStack(
      pimAddress,
      pim,
      slot
    )

    if type(stack) == "table" then
      snapshot[#snapshot + 1] = stack
    end
  end

  SellFlow.inventorySnapshot = snapshot
  SellFlow.inventorySnapshotAt = computer.uptime()
  return snapshot
end

function SellFlow.scanPlayerInventoryItem(item, force)
  if not item then return 0 end

  local total = 0
  local snapshot = SellFlow.getInventorySnapshot(force == true)

  for _, stack in ipairs(snapshot) do
    if SellFlow.inventoryStackMatches(stack, item) then
      total = total + math.max(
        0,
        tonumber(
          stack.size
          or stack.qty
          or stack.count
          or stack.amount
        ) or 0
      )
    end
  end

  return math.floor(total)
end

function SellFlow.refreshSellInventory(item, force)
  if currentShopMode ~= "sell" or not item then return 0 end

  local amount = SellFlow.scanPlayerInventoryItem(
    item,
    force == true
  )
  item.inventoryQty = amount
  return amount
end

function SellFlow.parseMovedCount(result, requested)
  if type(result) == "number" then
    return math.max(0, math.floor(result))
  elseif result == true then
    return requested
  elseif type(result) == "table" then
    return math.max(0, math.floor(tonumber(result.count or result.amount or result.size) or 0))
  end
  return 0
end

function SellFlow.movePlayerItemToME(item, amount)
  amount = math.max(0, math.floor(tonumber(amount) or 0))
  if amount <= 0 or not item then return 0 end

  local pimAddress = getPimAddr()
  if not pimAddress then return 0 end
  local pim = getPimProxy()
  local inventorySize = SellFlow.getInventorySizeForScan(pim)

  local movedTotal = 0
  for slot = 0, inventorySize do
    if movedTotal >= amount then break end

    local stack = SellFlow.getInventoryStack(pimAddress, pim, slot)
    if SellFlow.inventoryStackMatches(stack, item) then
      local stackAmount = math.max(0, tonumber(stack.size or stack.qty or stack.count) or 0)
      local toMove = math.min(stackAmount, amount - movedTotal)
      if toMove > 0 then
        local okMove, result = pcall(
          component.invoke,
          pimAddress,
          "pushItem",
          SellFlow.pushDirection,
          slot,
          toMove
        )
        if okMove then
          local moved = SellFlow.parseMovedCount(result, toMove)
          if moved > 0 then movedTotal = movedTotal + moved end
        end
      end
    end
  end

  SellFlow.invalidateInventorySnapshot()
  return movedTotal
end

local function extractPlayerNameFromEvent(ev)
  -- В старом рабочем коде имя обычно приходит вторым аргументом события.
  -- Дополнительный проход нужен для вариантов, где вторым идёт адрес компонента.
  for index = 2, math.min(#ev, 7) do
    local value = ev[index]
    if type(value) == "string" and value ~= "" and value ~= "null" then
      local looksLikeAddress = value:match("^[0-9a-fA-F%-]+$") and #value >= 30
      if not looksLikeAddress and value:match("^[%w_]+$") then
        return value
      end
    end
  end

  return getPlayerOnPim()
end

local function createSession(playerName)
  if Maintenance and Maintenance.active then
    if type(Maintenance.draw) == "function" then Maintenance.draw(false) end
    return false, "VIP-SHOP временно закрыт на технические работы"
  end

  playerName = normalizePlayerName(playerName)
  if not playerName then
    return false, "Имя игрока не определено"
  end

  if BanSystem and BanSystem.blockedPlayer then
    if type(BanSystem.samePlayer) == "function"
      and BanSystem.samePlayer(BanSystem.blockedPlayer, playerName)
    then
      if type(BanSystem.draw) == "function" then BanSystem.draw(false) end
      return false, "Доступ к VIP-SHOP ограничен"
    end

    -- Если на PIM уже стоит другой игрок, старое заблокированное состояние
    -- больше не должно мешать новой авторизации.
    if type(BanSystem.clear) == "function" then
      BanSystem.clear(false, true)
    end
  end

  if session.active then
    return session.playerName == playerName
  end

  clearSelector()
  SellFlow.invalidateInventorySnapshot()
  session.active = true
  session.playerName = playerName
  pimOwner = playerName
  uiState = "auth"
  authDeadline = computer.uptime() + AUTH_DELAY

  resetAccount()
  account.nick = playerName
  drawAuthScreen(playerName)

  -- ВАЖНО: здесь больше нет HTTP-запросов и вложенного event.pull().
  -- createSession сразу возвращает управление основному циклу, а переход
  -- в магазин выполняется по authDeadline ровно через две секунды.
  return true, nil
end

local function destroySession()
  if session and session.active and session.playerName then pcall(ModemRPC.request,{action="session_close",name=session.playerName},1) end
  clearSelector()
  SellFlow.invalidateInventorySnapshot()

  session.active = false
  session.playerName = nil
  pimOwner = nil
  uiState = "idle"
  authDeadline = nil
  popupState = nil
  popupButtons = {}
  transactionLock = false

  quantity = ""
  qtyFocused = false
  searchQuery = ""
  searchFocused = false
  selectedIndex = 0
  scrollOffset = 0
  Performance.pendingScroll = 0
  Performance.nextScrollAt = 0
  items = {}
  allItems = {}

  resetAccount()
  if Maintenance and Maintenance.active and type(Maintenance.draw) == "function" then
    uiState = "maintenance"
    Maintenance.draw(true)
  else
    drawIdleScreen()
  end
end

local function finishAuthorization()
  if Maintenance and Maintenance.active then
    if type(Maintenance.setActive) == "function" then
      Maintenance.setActive(true, false)
    end
    return
  end

  if uiState ~= "auth" or not session.active then
    return
  end

  -- Если за две секунды игрок успел уйти, магазин не открываем.
  if isPlayerStandingOnPim() == false then
    destroySession()
    return
  end

  local playerName = session.playerName
  authDeadline = nil

  -- Перед загрузкой каталога проверяем бан напрямую на основном хостинге.
  -- Это не зависит от задержки синхронизации users.json на центральном сервере.
  if BanSystem and type(BanSystem.checkPlayer) == "function" then
    local banned, banInfo = BanSystem.checkPlayer(playerName, false)

    if Maintenance.active or not session.active then
      return
    end

    if banned == true then
      BanSystem.blockPlayer(playerName, banInfo, true)
      return
    end

    if banned == nil then
      drawAuthScreen(
        playerName,
        "Центральный сервер недоступен. Повтор через 5 секунд..."
      )
      authDeadline = computer.uptime() + 5
      return
    end
  end

  -- Магазин открывается только ПОСЛЕ полной загрузки каталога и аккаунта.
  -- Поэтому при появлении GUI товары и реальные данные игрока уже на месте.
  drawAuthScreen(playerName, "Загрузка каталога и аккаунта...")

  currentShopMode = "buy"
  searchQuery = ""
  searchFocused = false
  Performance.searchDirty = false
  Performance.nextSearchAt = 0
  quantity = ""
  qtyFocused = false
  selectedIndex = 1
  scrollOffset = 0

  loadItemsForCurrentMode(true)

  -- Каталог продаж не загружаем заранее. Он понадобится только при
  -- первом открытии раздела «Продажи», поэтому обычный вход стал быстрее.

  -- Сетевой запрос блокирующий, поэтому после него повторно проверяем PIM.
  if not session.active
    or session.playerName ~= playerName
    or isPlayerStandingOnPim() == false
  then
    if session.active then destroySession() end
    return
  end

  loadAccountForPlayer(playerName)

  -- Резервная проверка по users.json, если отдельный check_ban.php временно
  -- не ответил, но актуальная запись игрока уже пришла через VPS.
  if account.banned == true and BanSystem then
    BanSystem.blockPlayer(playerName, {
      banned = true,
      reason = account.banReason,
      duration = account.banDuration,
      admin = account.bannedBy,
      date = account.bannedAt,
    }, true)
    return
  end

  if not session.active
    or session.playerName ~= playerName
    or isPlayerStandingOnPim() == false
  then
    if session.active then destroySession() end
    return
  end

  filterItems()
  if #items == 0 then
    selectedIndex = 0
  else
    selectedIndex = 1
  end

  uiState = "shop"
  presentShopFrame(true)
end

filterItems = function()
  items = {}
  local query = lowerText(searchQuery)
  local sourceItems = type(allItems) == "table" and allItems or {}

  for _, value in ipairs(sourceItems) do
    if type(value) == "table" then
      local searchableName = value._searchName
        or lowerText(tostring(
          value.name
          or value.displayName
          or value.internalName
          or ""
        ))
      local matchesSearch = searchQuery == ""
        or searchableName:find(query, 1, true) ~= nil

      local matchesAvailability = true
      if currentShopMode == "buy" then
        local stock = tonumber(value.meRaw or value.qty) or 0
        if availabilityFilter == "available" then
          matchesAvailability = stock > 0
        elseif availabilityFilter == "unavailable" then
          matchesAvailability = stock <= 0
        end
      end

      if matchesSearch and matchesAvailability then
        items[#items + 1] = value
      end
    end
  end

  selectedIndex = (#items > 0) and 1 or 0
  scrollOffset = 0
  quantity = ""

  if selectedIndex == 0 then
    clearSelector()
  elseif currentShopMode == "sell" then
    SellFlow.refreshSellInventory(items[selectedIndex])
  end
end

local function drawPaddedButton(x, y, label, bg, fg)
  local width = unicode.len(label) + 2
  fill(x, y, width, 1, bg)
  text(x + 1, y, label, fg or C.white, bg)
  return width
end

function drawAvailabilityFilterButton()
  local fg = C.white
  local label = updateAvailabilityButtonGeometry(getAvailabilityButtonText())

  -- Сначала очищаем область самого длинного варианта. Затем рисуем кнопку
  -- фактической ширины и прижимаем её к одному правому краю. Благодаря этому
  -- слева и справа от текста всегда остаётся ровно по одному пробелу.
  fill(
    AVAILABILITY_BUTTON_MAX_X,
    SEARCH_Y,
    AVAILABILITY_BUTTON_MAX_W,
    1,
    0x0A0A0A
  )
  fill(
    AVAILABILITY_BUTTON_X,
    SEARCH_Y,
    AVAILABILITY_BUTTON_W,
    1,
    C.buttonFilter
  )
  text(
    AVAILABILITY_BUTTON_X + 1,
    SEARCH_Y,
    label,
    fg,
    C.buttonFilter
  )
end

function drawAvailabilityMenu()
  if not availabilityMenuOpen then return end

  for index, option in ipairs(AVAILABILITY_MENU_OPTIONS) do
    local y = AVAILABILITY_MENU_Y + index - 1
    local selected = availabilityFilter == option.key
    local bg = selected and C.selectedBg or C.inputBg
    local fg = selected and C.selectedName or C.white
    fill(AVAILABILITY_MENU_X, y, AVAILABILITY_MENU_W, 1, bg)
    local marker = selected and "> " or "  "
    -- Ширина меню заранее рассчитана по полной строке, поэтому текст
    -- "НЕ В НАЛИЧИИ" никогда не сокращается многоточием.
    text(
      AVAILABILITY_MENU_X + 1,
      y,
      marker .. option.label,
      fg,
      bg
    )
  end
end

local function redrawSearchField()
  local searchText
  local searchColor

  if searchFocused then
    searchText = searchQuery .. "_"
    searchColor = C.accent
  elseif searchQuery == "" then
    searchText = "Поиск..."
    searchColor = C.darkGray
  else
    searchText = searchQuery
    searchColor = C.inputFg
  end

  -- Сначала полностью восстанавливаем рамку [ ... ], затем внутреннее поле.
  setBG(0x0A0A0A)
  setFG(C.frame)
  gpu.set(
    SEARCH_X,
    SEARCH_Y,
    "[" .. string.rep(" ", math.max(0, SEARCH_W - 2)) .. "]"
  )
  fill(SEARCH_X + 1, SEARCH_Y, SEARCH_W - 2, 1, C.inputBg)
  text(
    SEARCH_X + 2,
    SEARCH_Y,
    unicode.sub(searchText, 1, math.max(0, SEARCH_W - 4)),
    searchColor,
    C.inputBg
  )

  local searchClearDisabled = searchQuery == ""
  drawPaddedButton(
    SEARCH_CLEAR_X,
    SEARCH_Y,
    SEARCH_CLEAR_TEXT,
    searchClearDisabled and C.darkGray or C.buttonClear,
    searchClearDisabled and C.gray or C.white
  )
  drawAvailabilityFilterButton()

  setBG(C.bg)
end

do
local welcomeDiamond = {
  "                                  ███                                  ",
  "                                  ███                                  ",
  "                                                                       ",
  "         ███                     █████                     ███         ",
  "         ███          ███       ███████       ███          ███         ",
  "            ██        ███      █████████      ███        ██            ",
  "            ████     █████   █████████████   █████     ████            ",
  "             █████  ███████ ███████████████ ███████  █████             ",
  "              ███████████████████████████████████████████              ",
  "              ████████ █████████████████████████ ████████              ",
  "               █████████████████████████████████████████               ",
  "               █████████████████████████████████████████               ",
  "                ███████████████████████████████████████                ",
  "                ███████████████████████████████████████                ",
  "                 █████████████████████████████████████                 ",
  "                  ███████████████████████████████████                  ",
  "               █████████████████████████████████████████               ",
  "               █████████████████████████████████████████               ",
}


local welcomeRainbow = {
  0xFF0000, -- bottom: red
  0xFF8C00, -- orange
  0xFFFF00, -- yellow
  0x00C853, -- green
  0x00E5FF, -- cyan
  0x1E5BFF, -- blue
  0x8B00FF, -- top: violet
}

local function centeredX(value)
  return math.max(1, math.floor((WIDTH - unicode.len(value)) / 2) + 1)
end

-- Размер пикселя подобран с учётом пропорций символов OpenComputers.
-- Исходный рисунок уменьшается равномерно и целиком помещается на мониторе.
local WELCOME_PIXEL_W = 2
local WELCOME_PIXEL_H = 2

local function welcomeSourceWidth()
  local maxLen = 0
  for _, line in ipairs(welcomeDiamond) do
    local len = unicode.len(line)
    if len > maxLen then maxLen = len end
  end
  return maxLen
end

local function welcomeSourceSolid(row, col)
  local line = welcomeDiamond[row]
  if not line or col < 1 or col > unicode.len(line) then return false end
  local ch = unicode.sub(line, col, col)
  return ch ~= "" and ch ~= " "
end

local function splitColor(color)
  local r = math.floor(color / 0x10000) % 0x100
  local g = math.floor(color / 0x100) % 0x100
  local b = color % 0x100
  return r, g, b
end

local function joinColor(r, g, b)
  r = math.max(0, math.min(255, math.floor(r + 0.5)))
  g = math.max(0, math.min(255, math.floor(g + 0.5)))
  b = math.max(0, math.min(255, math.floor(b + 0.5)))
  return r * 0x10000 + g * 0x100 + b
end

local function mixColor(colorA, colorB, t)
  local ar, ag, ab = splitColor(colorA)
  local br, bg, bb = splitColor(colorB)
  return joinColor(
    ar + (br - ar) * t,
    ag + (bg - ag) * t,
    ab + (bb - ab) * t
  )
end

-- Глобальная функция нужна и другим частям магазина.
function activateFrontBuffer()
  if type(gpu.setActiveBuffer) == "function" then
    pcall(gpu.setActiveBuffer, 0)
  end
end

local welcomeAnim = {
  originX = 0,
  originY = 0,
  cols = 0,
  rows = 0,
  textY = 0,
  visible = false,
  lastAt = -1,
  seeded = false,
  pixels = {},
  grid = {},
  timerId = nil,

  -- Медленная независимая анимация каждого квадрата.
  interval = 0.85,
  minBlend = 0.055,
  maxBlend = 0.11,
  newTargetChance = 0.012,
}

function welcomeAnim.seedRandom()
  if welcomeAnim.seeded then return end

  local seed = math.floor((tonumber(computer.uptime()) or 0) * 100000)
  if os and type(os.time) == "function" then
    local ok, value = pcall(os.time)
    if ok and tonumber(value) then seed = seed + tonumber(value) end
  end

  pcall(math.randomseed, seed)
  math.random()
  math.random()
  math.random()
  welcomeAnim.seeded = true
end

function welcomeAnim.randomColor()
  welcomeAnim.seedRandom()

  local position = math.random()
  local scaled = position * #welcomeRainbow
  local base = math.floor(scaled)
  local leftIndex = (base % #welcomeRainbow) + 1
  local rightIndex = (leftIndex % #welcomeRainbow) + 1

  return mixColor(
    welcomeRainbow[leftIndex],
    welcomeRainbow[rightIndex],
    scaled - base
  )
end

function welcomeAnim.distance(colorA, colorB)
  local ar, ag, ab = splitColor(colorA)
  local br, bg, bb = splitColor(colorB)
  return math.abs(ar - br) + math.abs(ag - bg) + math.abs(ab - bb)
end

function welcomeAnim.buildGrid()
  local sourceW = welcomeSourceWidth()
  local sourceH = #welcomeDiamond
  local maxCols = math.max(1, math.floor((WIDTH - 4) / WELCOME_PIXEL_W))
  local maxRows = math.max(1, math.floor((HEIGHT - 8) / WELCOME_PIXEL_H))

  -- Масштабируем корону равномерно по X и Y, чтобы не сплющивать рисунок.
  local scaleX = maxCols / math.max(1, sourceW)
  local scaleY = maxRows / math.max(1, sourceH)
  local scale = math.min(1, scaleX, scaleY)

  local cols = math.max(1, math.floor(sourceW * scale + 0.5))
  local rows = math.max(1, math.floor(sourceH * scale + 0.5))

  if cols > maxCols then cols = maxCols end
  if rows > maxRows then rows = maxRows end

  local grid = {}
  for targetRow = 1, rows do
    grid[targetRow] = {}

    local sourceY1 = math.floor((targetRow - 1) * sourceH / rows) + 1
    local sourceY2 = math.max(sourceY1, math.floor(targetRow * sourceH / rows))

    for targetCol = 1, cols do
      local sourceX1 = math.floor((targetCol - 1) * sourceW / cols) + 1
      local sourceX2 = math.max(sourceX1, math.floor(targetCol * sourceW / cols))
      local solid = 0
      local total = 0

      for sourceRow = sourceY1, sourceY2 do
        for sourceCol = sourceX1, sourceX2 do
          total = total + 1
          if welcomeSourceSolid(sourceRow, sourceCol) then
            solid = solid + 1
          end
        end
      end

      -- Низкий порог сохраняет тонкие зубцы короны после уменьшения.
      grid[targetRow][targetCol] = solid >= math.max(1, math.floor(total * 0.18))
    end
  end

  welcomeAnim.cols = cols
  welcomeAnim.rows = rows
  welcomeAnim.grid = grid
  welcomeAnim.pixels = {}
end

function welcomeAnim.isSolid(row, col)
  return welcomeAnim.grid[row]
    and welcomeAnim.grid[row][col] == true
end

function welcomeAnim.isOutline(row, col)
  if not welcomeAnim.isSolid(row, col) then return false end

  -- Белая обводка толщиной в один квадрат.
  return not welcomeAnim.isSolid(row - 1, col)
    or not welcomeAnim.isSolid(row + 1, col)
    or not welcomeAnim.isSolid(row, col - 1)
    or not welcomeAnim.isSolid(row, col + 1)
end

function welcomeAnim.getPixel(row, col)
  local rowStates = welcomeAnim.pixels[row]
  if not rowStates then
    rowStates = {}
    welcomeAnim.pixels[row] = rowStates
  end

  local state = rowStates[col]
  if not state then
    state = {
      current = welcomeAnim.randomColor(),
      target = welcomeAnim.randomColor(),
      blend = welcomeAnim.minBlend
        + math.random() * (welcomeAnim.maxBlend - welcomeAnim.minBlend),
    }
    rowStates[col] = state
  end

  return state
end

function welcomeAnim.getColor(row, col, advance)
  -- Статичный плавный радужный градиент. Положение оттенка зависит
  -- от обоих координат, поэтому соседние квадраты меняются постепенно,
  -- без резких полос и случайных цветовых скачков.
  local x = welcomeAnim.cols > 1 and (col - 1) / (welcomeAnim.cols - 1) or 0
  local y = welcomeAnim.rows > 1 and (row - 1) / (welcomeAnim.rows - 1) or 0
  local position = math.max(0, math.min(1, x * 0.82 + (1 - y) * 0.18))
  local scaled = position * (#welcomeRainbow - 1)
  local leftIndex = math.floor(scaled) + 1
  local rightIndex = math.min(#welcomeRainbow, leftIndex + 1)
  local fraction = scaled - math.floor(scaled)

  if leftIndex >= #welcomeRainbow then
    return welcomeRainbow[#welcomeRainbow]
  end

  return mixColor(welcomeRainbow[leftIndex], welcomeRainbow[rightIndex], fraction)
end

function welcomeAnim.drawPixel(row, col, color)
  local x = welcomeAnim.originX + (col - 1) * WELCOME_PIXEL_W
  local y = welcomeAnim.originY + (row - 1) * WELCOME_PIXEL_H
  fill(x, y, WELCOME_PIXEL_W, WELCOME_PIXEL_H, color)
end

function welcomeAnim.draw(includeOutline, advanceColors)
  if welcomeAnim.originX <= 0 or welcomeAnim.originY <= 0 then return end

  for row = 1, welcomeAnim.rows do
    for col = 1, welcomeAnim.cols do
      if welcomeAnim.isSolid(row, col) then
        local outline = welcomeAnim.isOutline(row, col)
        if includeOutline or not outline then
          local color = outline and C.white
            or welcomeAnim.getColor(row, col, advanceColors == true)
          welcomeAnim.drawPixel(row, col, color)
        end
      end
    end
  end

  setBG(C.bg)
end

animateWelcomeFrame = function(now)
  -- Анимация отключена: корона остаётся статичной.
  return
end

function welcomeAnim.startTimer()
  -- Таймер намеренно не создаётся.
  welcomeAnim.timerId = nil
end

function welcomeAnim.stopTimer()
  if welcomeAnim.timerId and type(event.cancel) == "function" then
    pcall(event.cancel, welcomeAnim.timerId)
  end
  welcomeAnim.timerId = nil
end

local function drawWelcomeFrame()
  activateFrontBuffer()
  fill(1, 1, WIDTH, HEIGHT, C.bg)

  setBG(C.bg)
  setFG(C.frame)
  gpu.set(1, 1, "┌" .. string.rep("─", math.max(0, WIDTH - 2)) .. "┐")
  for y = 2, HEIGHT - 1 do
    gpu.set(1, y, "│")
    gpu.set(WIDTH, y, "│")
  end
  gpu.set(1, HEIGHT, "└" .. string.rep("─", math.max(0, WIDTH - 2)) .. "┘")

  welcomeAnim.buildGrid()

  local artWidth = welcomeAnim.cols * WELCOME_PIXEL_W
  local artHeight = welcomeAnim.rows * WELCOME_PIXEL_H
  local blockHeight = artHeight + 4

  welcomeAnim.originY = math.max(2, math.floor((HEIGHT - blockHeight) / 2))
  welcomeAnim.originX = math.max(2, math.floor((WIDTH - artWidth) / 2) + 1)
  welcomeAnim.lastAt = computer.uptime()
  welcomeAnim.draw(true, false)

  welcomeAnim.textY = welcomeAnim.originY + artHeight
  welcomeAnim.visible = true
  return welcomeAnim.textY
end

local function prepareWelcomeTextArea()
  if not welcomeAnim.visible then drawWelcomeFrame() end

  -- Очищаем пять строк: текст приветствия и авторизации теперь расположен
  -- на две строки ниже прежней позиции.
  fill(2, welcomeAnim.textY + 1, math.max(1, WIDTH - 2), 5, C.bg)
  return welcomeAnim.textY
end

invalidateWelcomeFrame = function()
  welcomeAnim.stopTimer()
  welcomeAnim.visible = false
  welcomeAnim.textY = 0
end

drawIdleScreen = function()
  local textY = prepareWelcomeTextArea()

  text(centeredX("VIP SHOP"), textY + 3, "VIP SHOP", C.white, C.bg)
  text(centeredX("◆ McSkill HiTech ◆"), textY + 4, "◆ McSkill HiTech ◆", C.yellow, C.bg)
  text(
    centeredX("Встаньте на PIM для входа"),
    textY + 5,
    "Встаньте на PIM для входа",
    C.gray,
    C.bg
  )
end

drawAuthScreen = function(playerName, statusText)
  -- Корона не перерисовывается: меняются только три строки текста,
  -- а независимая анимация квадратов продолжает работать таймером.
  local textY = prepareWelcomeTextArea()

  text(centeredX("АВТОРИЗАЦИЯ..."), textY + 3, "АВТОРИЗАЦИЯ...", C.accent, C.bg)
  local playerText = "Игрок: " .. tostring(playerName or "")
  text(centeredX(playerText), textY + 4, playerText, C.white, C.bg)

  statusText = statusText or "Пожалуйста, подождите 2 секунды"
  text(
    centeredX(statusText),
    textY + 5,
    statusText,
    C.gray,
    C.bg
  )
end

end -- welcome renderer scope

-- ============================================================================
-- РЕЖИМ ТЕХНИЧЕСКИХ РАБОТ
-- ============================================================================
-- ASCII-рисунок технических работ взят из предоставленного макета.
-- Все видимые символы рисунка выводятся ярко-оранжевым цветом.
Maintenance.art = {
  "                                                                          ",
  "                                                                          ",
  "                                   ████████████                           ",
  "                                  ███████████████                         ",
  "                                  ████       ████                         ",
  "                      ██████      ████       ████      █████              ",
  "                    ██████████   █████       █████   █████████            ",
  "                  ██████ ████████████         ███████████ ██████          ",
  "                 ██████    ████████             ███████     ██████        ",
  "                █████                                         █████       ",
  "                █████                                         █████       ",
  "                 ██████           ███████████████           ██████        ",
  "                   █████       ████████████████████        █████          ",
  "                     ███      ██████           ██████      █████          ",
  "                       ███████████               ██████     ████          ",
  "                     ████████████                  ████      ██████████   ",
  "             ████   █████    ████    ████           ████      ██████████  ",
  "           ██████████████    ██████████████          ████           ████  ",
  "          ██████████████      ██████████████         ████           ████  ",
  "        █████    ████           █████   ██████       ████           ████  ",
  "        ████                              ████      █████           ████  ",
  "        █████         ██████████        ██████      ████     ███████████  ",
  "          ████     ███████████████      ████       ████      ██████████   ",
  "      ███████     ██████      ██████    ███████  █████      ████          ",
  "    █████████    █████          █████    ████████████      █████          ",
  "    ██████      █████            █████      ██████         █████          ",
  "    ████        ████              ████        ████          ██████        ",
  "    ████        ████              ████        ████            █████       ",
  "    ███████     █████            █████    ████████  ██        █████       ",
  "     ████████    █████          █████    ████████  █████    ██████        ",
  "         █████    ██████████████████    ████        ████████████          ",
  "         █████      ██████████████      █████         ████████            ",
  "        █████          ████████          █████          ████              ",
  "        ████                              ████                            ",
  "        ██████  ███████        ███████  █████                             ",
  "          ██████████████      ██████████████                               ",
  "            ██████  █████    █████  ██████                                ",
  "                     ████████████                                          ",
  "                     ████████████                                          ",
  "                        ██████                                             ",
  "                                                                          ",
  "                                                                          ",
  "                                                                          ",
  "                                                                          ",
  "                                                                          ",
  "                                                                          ",
}

function Maintenance.centeredX(value)
  return math.max(1, math.floor((WIDTH - unicode.len(tostring(value or ""))) / 2) + 1)
end

function Maintenance.lineBounds(line)
  local first = nil
  local last = nil
  local length = unicode.len(line or "")
  for index = 1, length do
    if unicode.sub(line, index, index) ~= " " then
      if not first then first = index end
      last = index
    end
  end
  return first, last
end

function Maintenance.resetSession()
  clearSelector()

  session.active = false
  session.playerName = nil
  pimOwner = nil
  authDeadline = nil

  popupState = nil
  popupButtons = {}
  transactionLock = false
  popupBackupValid = false
  lastPopupBox = nil
  popupDirtyRect = nil
  availabilityMenuOpen = false

  quantity = ""
  qtyFocused = false
  searchQuery = ""
  searchFocused = false
  selectedIndex = 0
  scrollOffset = 0
  items = {}
  allItems = {}

  resetAccount()
end

function Maintenance.isWhiteConeBand(row, column)
  -- Стоящий конус слева: две белые горизонтальные полосы.
  if column <= 31 and row <= 23 then
    return (row >= 6 and row <= 10) or (row >= 15 and row <= 17)
  end

  -- Лежащий конус: полосы идут поперёк его диагональной оси.
  -- Ось приблизительно проходит от носика слева-снизу к основанию справа-сверху.
  local axisX = 42
  local axisY = -13
  local relativeX = column - 18
  local relativeY = row - 24
  local axisLengthSquared = axisX * axisX + axisY * axisY
  local position = (relativeX * axisX + relativeY * axisY) / axisLengthSquared

  return (position >= 0.18 and position <= 0.34)
      or (position >= 0.48 and position <= 0.63)
end

function Maintenance.artColor(row, column, ch)
  if ch == nil or ch == "" or ch == " " then return nil end

  -- Новый ASCII-рисунок выводится одним ярко-оранжевым цветом.
  return C.maintenanceOrange
end

function Maintenance.draw(force)
  if not Maintenance.active then return end
  if Maintenance.screenDrawn and force ~= true then return end

  activateFrontBuffer()
  if type(invalidateWelcomeFrame) == "function" then
    invalidateWelcomeFrame()
  end

  fill(1, 1, WIDTH, HEIGHT, C.maintenanceBlack)

  local sourceHeight = #Maintenance.art
  local sourceWidth = 0
  for _, line in ipairs(Maintenance.art) do
    sourceWidth = math.max(sourceWidth, unicode.len(line))
  end

  local availableHeight = math.max(8, HEIGHT - 7)
  local outputHeight = math.min(sourceHeight, availableHeight)
  local startX = math.max(1, math.floor((WIDTH - sourceWidth) / 2) + 1)
  local startY = math.max(1, math.floor((HEIGHT - (outputHeight + 6)) / 2) + 1)

  for outputRow = 1, outputHeight do
    local sourceRow
    if outputHeight == sourceHeight then
      sourceRow = outputRow
    else
      sourceRow = math.floor((outputRow - 1) * (sourceHeight - 1) / math.max(1, outputHeight - 1)) + 1
    end

    local line = Maintenance.art[sourceRow] or ""
    local lineLength = unicode.len(line)
    local screenY = startY + outputRow - 1

    if screenY >= 1 and screenY <= HEIGHT then
      local runX = nil
      local runColor = nil
      local runText = ""

      local function flushRun()
        if runX and runText ~= "" then
          text(runX, screenY, runText, runColor, C.maintenanceBlack)
        end
        runX = nil
        runColor = nil
        runText = ""
      end

      for column = 1, lineLength + 1 do
        local ch = column <= lineLength and unicode.sub(line, column, column) or " "
        local screenX = startX + column - 1
        local color = nil

        if screenX >= 1 and screenX <= WIDTH then
          color = Maintenance.artColor(sourceRow, column, ch)
        end

        if color and runX and color == runColor then
          runText = runText .. ch
        elseif color then
          flushRun()
          runX = screenX
          runColor = color
          runText = ch
        else
          flushRun()
        end
      end
    end
  end

  local titleY = math.min(HEIGHT - 3, startY + outputHeight + 1)
  local waitY = math.min(HEIGHT - 1, titleY + 2)
  local statusY = math.min(HEIGHT, waitY + 1)

  text(
    Maintenance.centeredX("ТЕХ.РАБОТЫ"),
    titleY,
    "ТЕХ.РАБОТЫ",
    C.maintenanceOrange,
    C.maintenanceBlack
  )
  text(
    Maintenance.centeredX("Пожалуйста, подождите"),
    waitY,
    "Пожалуйста, подождите",
    C.maintenanceWhite,
    C.maintenanceBlack
  )
  if statusY > waitY and statusY <= HEIGHT then
    text(
      Maintenance.centeredX("PIM временно недоступен"),
      statusY,
      "PIM временно недоступен",
      C.maintenanceGray,
      C.maintenanceBlack
    )
  end

  Maintenance.screenDrawn = true
end

function Maintenance.setActive(value, silent)
  local enabled = value == true
  local changed = Maintenance.active ~= enabled
  Maintenance.active = enabled

  if enabled then
    -- Повторное чтение того же состояния не должно каждые несколько секунд
    -- сбрасывать интерфейс и заново рисовать экран технических работ.
    if changed or uiState ~= "maintenance" then
      Maintenance.resetSession()
      uiState = "maintenance"
      Maintenance.screenDrawn = false
      if silent ~= true then Maintenance.draw(true) end
    elseif silent ~= true then
      Maintenance.draw(false)
    end
    return changed
  end

  if changed or uiState == "maintenance" then
    Maintenance.screenDrawn = false

    if BanSystem and BanSystem.blockedPlayer then
      uiState = "banned"
      BanSystem.screenDrawn = false
      if silent ~= true and type(BanSystem.draw) == "function" then
        BanSystem.draw(true)
      end
    else
      uiState = "idle"
      if type(invalidateWelcomeFrame) == "function" then
        invalidateWelcomeFrame()
      end
      if silent ~= true then drawIdleScreen() end
    end
  end
  return changed
end

function Maintenance.extractPaused(data)
  if type(data) ~= "table" then return nil end
  if data.paused ~= nil then return data.paused == true end
  if type(data.config) == "table" and data.config.paused ~= nil then
    return data.config.paused == true
  end
  if type(data.data) == "table" and data.data.paused ~= nil then
    return data.data.paused == true
  end
  return nil
end

function Maintenance.checkConfig(silent)
  local data, err = httpRequest(Maintenance.configUrl, Maintenance.requestTimeout)
  if type(data) ~= "table" then
    Maintenance.lastError = err
    return false
  end

  local paused = Maintenance.extractPaused(data)
  if paused == nil then return false end
  Maintenance.lastError = nil
  Maintenance.setActive(paused, silent == true)
  return true
end

function Maintenance.checkSignal(silent)
  local data, err = httpRequest(Maintenance.signalUrl, Maintenance.requestTimeout)
  if type(data) ~= "table" then
    Maintenance.lastError = err
    return false
  end

  -- signal.json общий для магазина. Перед обработкой техработ передаём
  -- бан-сигналы отдельному менеджеру доступа.
  if BanSystem and type(BanSystem.handleSignal) == "function" then
    local handled = BanSystem.handleSignal(data)
    if handled then return true end
  end

  local signalSection = lowerText(tostring(data.section or ""))
  if signalSection == "shop" or signalSection == "catalog" then
    local catalogType = lowerText(tostring(data.catalog or ""))

    if catalogType == "sell" then
      sellItemsCache = nil
      Performance.sellCatalogLoadedAt = 0
    elseif catalogType == "buy" then
      buyItemsCache = nil
      Performance.buyCatalogLoadedAt = 0
    else
      buyItemsCache = nil
      sellItemsCache = nil
      Performance.buyCatalogLoadedAt = 0
      Performance.sellCatalogLoadedAt = 0
    end

    return true
  end

  if tostring(data.section or "") ~= "config"
    or tostring(data.action or "") ~= "pause"
    or data.paused == nil
  then
    return false
  end

  local signalTime = tonumber(data.time) or 0
  if signalTime <= Maintenance.lastSignalTime then return false end
  Maintenance.lastSignalTime = signalTime
  Maintenance.lastError = nil
  Maintenance.setActive(data.paused == true, silent == true)
  return true
end

function Maintenance.bootstrap()
  local response=ModemRPC.request({action="get_state"},4)
  if response and response.status=="ok" and type(response.data)=="table" then
    ModemRPC.globalMaintenance=response.data.maintenance==true
    ModemRPC.terminalPaused=response.data.terminalPaused==true
    Maintenance.setActive(ModemRPC.globalMaintenance or ModemRPC.terminalPaused,true)
  end
end

function Maintenance.poll(now)
  return
end

-- ============================================================
-- СИСТЕМА БАНОВ VIP-SHOP
-- ============================================================

function BanSystem.samePlayer(firstName, secondName)
  if firstName == nil or secondName == nil then return false end
  return lowerText(tostring(firstName)) == lowerText(tostring(secondName))
end

function BanSystem.urlEncode(value)
  return tostring(value or ""):gsub("([^%w_%-%.~])", function(character)
    return string.format("%%%02X", string.byte(character))
  end)
end

function BanSystem.centeredX(value)
  return math.max(1, math.floor((WIDTH - unicode.len(tostring(value or ""))) / 2) + 1)
end

function BanSystem.wrap(value, maximumWidth, maximumLines)
  local source = tostring(value or "")
  local width = math.max(8, tonumber(maximumWidth) or 50)
  local limit = math.max(1, tonumber(maximumLines) or 3)
  local result = {}

  while unicode.len(source) > width and #result < limit - 1 do
    local splitAt = width
    for index = width, 1, -1 do
      if unicode.sub(source, index, index) == " " then
        splitAt = index
        break
      end
    end

    local part = unicode.sub(source, 1, splitAt)
    part = part:gsub("^%s+", ""):gsub("%s+$", "")
    result[#result + 1] = part
    source = unicode.sub(source, splitAt + 1)
    source = source:gsub("^%s+", "")
  end

  if #result < limit and source ~= "" then
    if unicode.len(source) > width then
      source = unicode.sub(source, 1, math.max(1, width - 3)) .. "..."
    end
    result[#result + 1] = source
  end

  if #result == 0 then result[1] = "Причина не указана" end
  return result
end

function BanSystem.durationText(value)
  local duration = tonumber(value) or 0
  if duration <= 0 then return "БЕССРОЧНО" end
  return tostring(math.floor(duration)) .. " мин."
end

function BanSystem.draw(force)
  if not BanSystem.blockedPlayer then return end
  if Maintenance and Maintenance.active then
    if type(Maintenance.draw) == "function" then Maintenance.draw(force == true) end
    return
  end
  if BanSystem.screenDrawn and force ~= true then return end

  activateFrontBuffer()
  fill(1, 1, WIDTH, HEIGHT, C.banBg)

  local boxWidth = math.min(84, WIDTH - 8)
  local boxHeight = math.min(24, HEIGHT - 6)
  local boxX = math.floor((WIDTH - boxWidth) / 2) + 1
  local boxY = math.floor((HEIGHT - boxHeight) / 2) + 1
  local rightX = boxX + boxWidth - 1
  local bottomY = boxY + boxHeight - 1

  setBG(C.banBg)
  setFG(C.banRed)
  text(boxX, boxY, "╔" .. string.rep("═", boxWidth - 2) .. "╗", C.banRed, C.banBg)
  for row = boxY + 1, bottomY - 1 do
    text(boxX, row, "║", C.banRed, C.banBg)
    text(rightX, row, "║", C.banRed, C.banBg)
  end
  text(boxX, bottomY, "╚" .. string.rep("═", boxWidth - 2) .. "╝", C.banRed, C.banBg)

  text(
    BanSystem.centeredX("ДОСТУП К VIP-SHOP ОГРАНИЧЕН"),
    boxY + 2,
    "ДОСТУП К VIP-SHOP ОГРАНИЧЕН",
    C.banRed,
    C.banBg
  )
  text(
    BanSystem.centeredX("АККАУНТ ЗАБЛОКИРОВАН"),
    boxY + 4,
    "АККАУНТ ЗАБЛОКИРОВАН",
    C.banYellow,
    C.banBg
  )

  local info = type(BanSystem.info) == "table" and BanSystem.info or {}
  local playerLine = "Игрок: " .. tostring(BanSystem.blockedPlayer)
  text(BanSystem.centeredX(playerLine), boxY + 6, playerLine, C.cyan, C.banBg)

  text(BanSystem.centeredX("Причина:"), boxY + 8, "Причина:", C.banGray, C.banBg)
  local reasonLines = BanSystem.wrap(info.reason or "Нарушение правил магазина", boxWidth - 10, 3)
  local reasonY = boxY + 9
  for index, line in ipairs(reasonLines) do
    text(BanSystem.centeredX(line), reasonY + index - 1, line, C.banWhite, C.banBg)
  end

  local detailsY = boxY + 13
  local adminLine = "Администратор: " .. tostring(info.admin or "Система")
  local durationLine = "Срок ограничения: " .. BanSystem.durationText(info.duration or info.expires)
  local dateLine = "Дата: " .. tostring(info.date or "Неизвестно")
  text(BanSystem.centeredX(adminLine), detailsY, adminLine, C.banGray, C.banBg)
  text(BanSystem.centeredX(durationLine), detailsY + 1, durationLine, C.banYellow, C.banBg)
  text(BanSystem.centeredX(dateLine), detailsY + 2, dateLine, C.banGray, C.banBg)

  local accessLine = "Меню, покупки, продажи и автокрафт недоступны."
  text(BanSystem.centeredX(accessLine), boxY + 17, accessLine, C.banRed, C.banBg)
  local appealLine = "Для обжалования обратитесь к администрации."
  text(BanSystem.centeredX(appealLine), boxY + 19, appealLine, C.banWhite, C.banBg)
  local leaveLine = "Сойдите с PIM"
  text(BanSystem.centeredX(leaveLine), boxY + 21, leaveLine, C.banGray, C.banBg)

  BanSystem.screenDrawn = true
end

function BanSystem.blockPlayer(playerName, info, forceDraw)
  local normalizedName = normalizePlayerName(playerName) or tostring(playerName or "Неизвестный")
  BanSystem.blockedPlayer = normalizedName
  BanSystem.info = type(info) == "table" and info or {}
  BanSystem.info.banned = true
  BanSystem.screenDrawn = false
  BanSystem.nextCheck = computer.uptime() + BanSystem.checkInterval

  -- Закрываем текущий магазин и полностью блокируем ввод, но сохраняем имя
  -- игрока отдельно, чтобы показать причину ограничения.
  if Maintenance and type(Maintenance.resetSession) == "function" then
    Maintenance.resetSession()
  end

  if Maintenance and Maintenance.active then
    uiState = "maintenance"
    Maintenance.draw(forceDraw == true)
  else
    uiState = "banned"
    BanSystem.draw(forceDraw == true)
  end

  writeDebugLog(
    "Доступ заблокирован для " .. tostring(normalizedName)
      .. ": " .. tostring(BanSystem.info.reason or "Причина не указана")
  )
end

function BanSystem.clear(restartAuthorization, silent)
  local previousPlayer = BanSystem.blockedPlayer
  BanSystem.blockedPlayer = nil
  BanSystem.info = nil
  BanSystem.screenDrawn = false
  BanSystem.lastError = nil

  if Maintenance and Maintenance.active then
    uiState = "maintenance"
    if silent ~= true then Maintenance.draw(true) end
    return
  end

  uiState = "idle"
  if type(invalidateWelcomeFrame) == "function" then invalidateWelcomeFrame() end
  if silent ~= true then drawIdleScreen() end

  if restartAuthorization == true
    and previousPlayer
    and isPlayerStandingOnPim() == true
  then
    local detectedPlayer = getPlayerOnPim() or previousPlayer
    if BanSystem.samePlayer(previousPlayer, detectedPlayer) then
      createSession(detectedPlayer)
    end
  end
end

function BanSystem.checkPlayer(playerName,applyState)
  playerName=normalizePlayerName(playerName)
  if not playerName then return nil,"Имя игрока не определено" end
  local response,err=ModemRPC.sessionOpen(playerName)
  if not response or response.status~="ok" then BanSystem.lastError=err or (response and response.message) or "Центральный сервер не отвечает" return nil,BanSystem.lastError end
  local data=response.data or {}
  local user=type(data.user)=="table" and data.user or {}
  ModemRPC.globalMaintenance=data.maintenance==true
  ModemRPC.terminalPaused=data.terminalPaused==true
  if ModemRPC.globalMaintenance or ModemRPC.terminalPaused then Maintenance.setActive(true,false) return nil,"Терминал временно недоступен" end
  if user.banned==true then
    local info={banned=true,reason=user.banReason or "Нарушение правил магазина",admin=user.bannedBy or "Система",date=user.bannedAt or "Неизвестно",duration=tonumber(user.banDuration) or 0}
    if applyState==true then BanSystem.blockPlayer(playerName,info,true) end
    return true,info
  end
  if applyState==true and BanSystem.blockedPlayer and BanSystem.samePlayer(BanSystem.blockedPlayer,playerName) then BanSystem.clear(true,false) end
  return false,user
end

function BanSystem.handleSignal(data)
  if type(data) ~= "table" then return false end
  if tostring(data.section or "") ~= "ban" then return false end

  local signalTime = tonumber(data.time) or 0
  if signalTime <= BanSystem.lastSignalTime then return true end
  BanSystem.lastSignalTime = signalTime

  local targetPlayer = normalizePlayerName(data.player or data.name)
  local action = lowerText(tostring(data.action or ""))
  if not targetPlayer then return true end

  if action == "new" or action == "ban" then
    local currentPlayer = session.active and session.playerName or BanSystem.blockedPlayer
    if currentPlayer and BanSystem.samePlayer(currentPlayer, targetPlayer) then
      BanSystem.blockPlayer(targetPlayer, {
        banned = true,
        reason = data.reason or "Нарушение правил магазина",
        admin = data.admin or "Система",
        date = data.date or "Неизвестно",
        duration = tonumber(data.duration) or 0,
      }, true)
    end
    return true
  end

  if action == "unban" then
    if BanSystem.blockedPlayer and BanSystem.samePlayer(BanSystem.blockedPlayer, targetPlayer) then
      BanSystem.clear(true, false)
    end
    return true
  end

  return true
end

function BanSystem.bootstrap()
  BanSystem.nextCheck=math.huge
end

function BanSystem.poll(now)
  return
end

local function drawBackground()
  fill(1, 1, WIDTH, HEIGHT, C.bg)
end

local function drawTopBar()
  fill(1, 1, WIDTH, 3, 0x0A0A0A)

  local title = "──── VIP-SHOP ────"
  text(
    math.floor((WIDTH - unicode.len(title)) / 2) + 1,
    1,
    title,
    C.vipTitle,
    0x0A0A0A
  )

  setFG(C.underLine)
  setBG(0x0A0A0A)
  gpu.set(1, 2, string.rep("=", WIDTH))

  redrawSearchField()
end

local function drawMainFrames()
  setBG(C.bg)
  setFG(C.mainLine)
  gpu.set(1, MAIN_Y, "+" .. string.rep("=", WIDTH - 2) .. "+")
  for y = MAIN_Y + 1, MAIN_Y + MAIN_H - 2 do
    gpu.set(1, y, "|")
    gpu.set(WIDTH, y, "|")
  end
  gpu.set(1, MAIN_Y + MAIN_H - 1, "+" .. string.rep("=", WIDTH - 2) .. "+")
end

local function drawLeftHeader()
  local title = currentShopMode == "sell" and "КАТАЛОГ ПРОДАЖ" or "КАТАЛОГ ПОКУПОК"
  sectionHeader(2, MAIN_Y + 1, LEFT_W - 3, title, C.mainLine, C.white)
  local colY = MAIN_Y + 2
  fill(2, colY, LEFT_W - 3, 1, C.headerBg)
  text(COL_NAME_X, colY, "ТОВАР", C.white, C.headerBg)
  text(COL_ME_X, colY, "В ME", C.white, C.headerBg)
  text(COL_COINA_X, colY, "COINA", C.coin, C.headerBg)
  text(COL_EMA_X, colY, "EMA", C.ema, C.headerBg)
end

local function drawSeparator()
  setBG(C.bg)
  setFG(C.mainLine)
  for y = MAIN_Y + 1, MAIN_Y + MAIN_H - 2 do
    gpu.set(SEPARATOR1, y, "|")
    gpu.set(SEPARATOR2, y, "|")
  end
  gpu.set(SEPARATOR1, MAIN_Y, "+")
  gpu.set(SEPARATOR2, MAIN_Y, "+")
  gpu.set(SEPARATOR1, MAIN_Y + MAIN_H - 1, "+")
  gpu.set(SEPARATOR2, MAIN_Y + MAIN_H - 1, "+")
end

local scrollbarState = {
  initialized = false,
}

local function resetScrollbarState()
  scrollbarState.initialized = false
end

-- Нижние доли ячейки: позволяют перемещать ползунок не только целыми
-- строками, но и восьмыми долями строки. На текстовом экране OC это
-- выглядит заметно плавнее обычного округления math.floor().
local SCROLL_BLOCKS = {
  " ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"
}

local function scrollBlock(parts)
  parts = math.max(0, math.min(8, math.floor(parts or 0)))
  return SCROLL_BLOCKS[parts + 1]
end

local function drawScrollbar(force)
  local total = #items
  local trackColor = C.inputBg

  -- Перерисовывается только один столбец полосы, поэтому моргания нет.
  fill(SCROLL_X, LIST_Y, 1, LIST_H, trackColor)
  scrollbarState.initialized = true

  if total <= LIST_H then
    fill(SCROLL_X, LIST_Y, 1, LIST_H, C.bg)
    setBG(C.bg)
    return
  end

  local thumbH = math.max(3, math.floor(LIST_H * LIST_H / total))
  thumbH = math.min(thumbH, LIST_H)

  local maxScroll = math.max(1, total - LIST_H)
  local maxThumbMove = math.max(0, LIST_H - thumbH)
  local rawPosition = (scrollOffset * maxThumbMove) / maxScroll
  local base = math.floor(rawPosition)
  local fraction = rawPosition - base
  local eighths = math.max(0, math.min(7, math.floor(fraction * 8 + 0.5)))

  if eighths == 0 then
    fill(SCROLL_X, LIST_Y + base, 1, thumbH, C.accent)
  else
    -- Верхняя неполная ячейка: цвет ползунка занимает нижнюю часть.
    setBG(trackColor)
    setFG(C.accent)
    gpu.set(SCROLL_X, LIST_Y + base, scrollBlock(8 - eighths))

    -- Полностью заполненная середина ползунка.
    if thumbH > 1 then
      fill(SCROLL_X, LIST_Y + base + 1, 1, thumbH - 1, C.accent)
    end

    -- Нижняя неполная ячейка: фон ползунка остаётся сверху, а нижняя
    -- часть закрашивается цветом дорожки.
    local bottomY = LIST_Y + base + thumbH
    if bottomY <= LIST_Y + LIST_H - 1 then
      setBG(C.accent)
      setFG(trackColor)
      gpu.set(SCROLL_X, bottomY, scrollBlock(8 - eighths))
    end
  end

  setBG(C.bg)
end

local function drawItemRow(index, y)
  local item = items[index]
  if not item then return end

  local isSelected = (index == selectedIndex)
  local noStock = currentShopMode == "buy"
    and (tonumber(item.meRaw or item.qty) or 0) <= 0

  if isSelected then
    fill(LIST_X, y, LIST_W, 1, C.selectedBg)
  else
    fill(LIST_X, y, LIST_W, 1, C.bg)
  end

  local rowBG = isSelected and C.selectedBg or C.bg
  local nameColor = noStock and C.darkGray
    or (isSelected and C.selectedName or C.white)
  local meColor = noStock and C.darkGray
    or (item.star and C.green or C.red)
  local coinaColor = noStock and C.darkGray or C.coin
  local emaColor = noStock and C.darkGray or C.ema
  local markerColor = noStock and C.darkGray
    or (isSelected and C.selectedName or (item.star and C.star or C.darkGray))

  if isSelected then
    text(COL_NAME_X, y, "> ", markerColor, rowBG)
  else
    text(COL_NAME_X, y, item.star and "* " or "- ", markerColor, rowBG)
  end
  local maxNameLen = COL_ME_X - COL_NAME_X - 2
  local displayName = truncate(item.name, maxNameLen - 2)
  text(COL_NAME_X + 2, y, displayName, nameColor, rowBG)

  -- Жёстко ограничиваем каждый числовой столбец. Это не даёт последней
  -- цифре старого значения оставаться возле скроллбара после gpu.copy.
  local meWidth = math.max(1, COL_COINA_X - COL_ME_X - 1)
  local coinWidth = math.max(1, COL_EMA_X - COL_COINA_X - 1)
  local emaWidth = math.max(1, SCROLL_X - COL_EMA_X)

  fill(COL_ME_X, y, meWidth, 1, rowBG)
  fill(COL_COINA_X, y, coinWidth, 1, rowBG)
  fill(COL_EMA_X, y, emaWidth, 1, rowBG)

  text(COL_ME_X, y, truncate(item.me, meWidth), meColor, rowBG)
  text(COL_COINA_X, y, truncate(item.coina, coinWidth), coinaColor, rowBG)
  text(COL_EMA_X, y, truncate(item.ema, emaWidth), emaColor, rowBG)
end

local function drawProductList()
  fill(LIST_X, LIST_Y, LIST_W, LIST_H, C.bg)
  if #items == 0 then
    local msg
    local msgColor = C.notFound

    if searchQuery ~= "" then
      msg = "ПО ТВОЕМУ ЗАПРОСУ, НИЧЕГО НЕ НАЙДЕНО!"
    elseif catalogLoadError then
      msg = catalogStatus
      msgColor = C.red
    else
      msg = "В КАТАЛОГЕ НЕТ ТОВАРОВ"
    end

    msg = truncate(msg, math.max(10, LIST_W - 4))
    local mx = LIST_X + math.max(0, math.floor((LIST_W - unicode.len(msg)) / 2))
    local my = LIST_Y + math.floor(LIST_H / 2)
    text(mx, my, msg, msgColor, C.bg)
    return
  end
  local startIdx = scrollOffset + 1
  local endIdx = math.min(#items, startIdx + LIST_H - 1)
  for i = startIdx, endIdx do
    drawItemRow(i, LIST_Y + (i - startIdx))
  end
end

local function drawInfoBlock()
  fill(RIGHT_INNER_X, INFO_Y, RIGHT_INNER_W, 7, C.bg)
  sectionHeader(RIGHT_INNER_X, INFO_Y, RIGHT_INNER_W, "ИНФОРМАЦИЯ О ТОВАРЕ", C.sectionLine, C.white)
  local item = items[selectedIndex]
  if not item then return end

  local noStock = currentShopMode == "buy"
    and (tonumber(item.meRaw or item.qty) or 0) <= 0
  local sellInventory = currentShopMode == "sell"
    and (tonumber(item.inventoryQty) or 0) or 0
  local noSellItems = currentShopMode == "sell" and sellInventory <= 0
  local nameColor = (noStock or noSellItems) and C.darkGray or C.white
  local amountColor = (noStock or noSellItems) and C.darkGray or C.green
  local coinColor = (noStock or noSellItems) and C.darkGray or C.coin
  local emaColor = (noStock or noSellItems) and C.darkGray or C.ema

  local maxLen = RIGHT_INNER_W - 13
  local y = INFO_Y + 2
  text(RIGHT_INNER_X, y, "Товар: " .. truncate(item.name, maxLen), nameColor, C.bg)
  y = y + 1
  if currentShopMode == "buy" then
    local craftText = item.craftable == true and "Автокрафт: ДОСТУПЕН" or "Автокрафт: НЕТ"
    local craftColor = item.craftable == true and C.cyan or C.darkGray
    text(RIGHT_INNER_X, y, craftText, craftColor, C.bg)
    y = y + 1
    text(RIGHT_INNER_X, y, "В МЭ: " .. item.me, amountColor, C.bg)
    y = y + 1
  else
    text(RIGHT_INNER_X, y, "В инвентаре: " .. tostring(sellInventory) .. " шт.", amountColor, C.bg)
    y = y + 1
  end
  text(RIGHT_INNER_X, y, "COINA: " .. item.coina, coinColor, C.bg)
  y = y + 1
  text(RIGHT_INNER_X, y, "EMA: " .. item.ema, emaColor, C.bg)
end

local function getQuantityInputLimit()
  local item = items[selectedIndex]
  if not item then return 0 end

  if currentShopMode == "sell" then
    return math.max(0, math.floor(tonumber(item.inventoryQty) or 0))
  end

  -- Для автокрафтового товара разрешаем вводить количество больше остатка МЭ.
  -- Фактический лимит поля — восемь цифр, как и раньше.
  if item.craftable == true then
    return 99999999
  end

  return math.max(0, math.floor(tonumber(item.meRaw or item.qty) or 0))
end

local function appendQuantityDigit(charCode)
  local digit = unicode.char(charCode)
  local candidate = quantity .. digit
  local candidateNumber = math.max(0, math.floor(tonumber(candidate) or 0))
  local limit = getQuantityInputLimit()

  -- Нельзя ввести больше, чем реально доступно:
  -- в режиме покупки — остаток в МЭ, в режиме продажи — предметы игрока.
  if candidateNumber > limit then
    candidateNumber = limit
  end

  quantity = tostring(candidateNumber)
end

local function getQuantityButtonLayout()
  local item = items[selectedIndex]
  local requestedQty = math.max(0, math.floor(tonumber(quantity) or 0))
  local stock = item and math.max(0, math.floor(tonumber(item.meRaw or item.qty) or 0)) or 0

  local actionText
  if currentShopMode == "sell" then
    actionText = "[ Продать ]"
  elseif item and requestedQty > stock and item.craftable == true then
    actionText = "[ Автокрафт ]"
  else
    actionText = "[ Купить ]"
  end

  local actionW = unicode.len(actionText) + 2
  local actionX = RIGHT_INNER_X
  local clearX = actionX + actionW + 2

  return actionText, actionX, actionW, clearX, QTY_CLEAR_W
end

local function drawQuantitySection()
  fill(RIGHT_INNER_X, QTY_Y, RIGHT_INNER_W, 9, C.bg)
  sectionHeader(RIGHT_INNER_X, QTY_Y, RIGHT_INNER_W, "КОЛИЧЕСТВО", C.sectionLine, C.white)

  local fieldY = QTY_Y + 2
  setFG(C.frame)
  setBG(C.bg)
  gpu.set(
    RIGHT_INNER_X,
    fieldY,
    "[" .. string.rep(" ", math.max(0, RIGHT_INNER_W - 2)) .. "]"
  )
  fill(RIGHT_INNER_X + 1, fieldY, RIGHT_INNER_W - 2, 1, C.inputBg)

  local fieldText
  local fieldColor
  if qtyFocused then
    fieldText = quantity .. "_"
    fieldColor = C.accent
  elseif quantity == "" then
    fieldText = "Введите количество..."
    fieldColor = C.darkGray
  else
    fieldText = quantity
    fieldColor = C.inputFg
  end

  text(
    RIGHT_INNER_X + 2,
    fieldY,
    unicode.sub(fieldText, 1, math.max(0, RIGHT_INNER_W - 4)),
    fieldColor,
    C.inputBg
  )

  local item = items[selectedIndex]
  local requestedQty = math.max(0, math.floor(tonumber(quantity) or 0))
  local effectiveQty = requestedQty
  local totalCoina = 0
  local totalEma = 0

  if item then
    if currentShopMode == "sell" then
      local inventoryQty = math.max(0, math.floor(tonumber(item.inventoryQty) or 0))
      -- Пустое поле означает продажу всего найденного количества.
      if effectiveQty <= 0 then effectiveQty = inventoryQty end
      effectiveQty = math.min(effectiveQty, inventoryQty)
    end
    totalCoina = effectiveQty * (tonumber(item.coina) or 0)
    totalEma = effectiveQty * (tonumber(item.ema) or 0)
  end

  if currentShopMode == "sell" and item then
    local summary = string.format("Итог: %s × %d шт.", item.name, effectiveQty)
    text(RIGHT_INNER_X, TOTAL_Y, truncate(summary, RIGHT_INNER_W), C.white, C.bg)
  else
    local prefix = "Итог: COINA "
    local coinText = trimNumber(totalCoina, 4)
    local separator = " | EMA "
    local emaText = trimNumber(totalEma, 4)
    local maxX = RIGHT_INNER_X + RIGHT_INNER_W - 1
    local x = RIGHT_INNER_X

    text(x, TOTAL_Y, prefix, C.white, C.bg)
    x = x + unicode.len(prefix)
    if x <= maxX then text(x, TOTAL_Y, truncate(coinText, maxX - x + 1), C.coin, C.bg) end
    x = x + unicode.len(coinText)
    if x <= maxX then text(x, TOTAL_Y, truncate(separator, maxX - x + 1), C.white, C.bg) end
    x = x + unicode.len(separator)
    if x <= maxX then text(x, TOTAL_Y, truncate(emaText, maxX - x + 1), C.ema, C.bg) end
  end

  local actionText, actionX, _, clearX = getQuantityButtonLayout()
  local stock = item and math.max(0, math.floor(tonumber(item.meRaw or item.qty) or 0)) or 0
  local buyUnavailable = currentShopMode == "buy"
    and (not item or (stock <= 0 and item.craftable ~= true))
  local sellUnavailable = currentShopMode == "sell"
    and (not item or (tonumber(item.inventoryQty) or 0) <= 0)
  local buyQuantityMissing = currentShopMode == "buy" and requestedQty <= 0
  local actionDisabled = buyUnavailable or sellUnavailable or buyQuantityMissing
  local needsCraft = currentShopMode == "buy"
    and item and requestedQty > stock and item.craftable == true
  local actionColor
  if actionDisabled then
    actionColor = C.darkGray
  elseif currentShopMode == "sell" then
    actionColor = C.buttonSales
  elseif needsCraft then
    actionColor = C.buttonCraft
  else
    actionColor = C.buttonBuy
  end

  local clearColor = quantity == "" and C.darkGray or C.buttonClear
  local disabledTextColor = C.gray
  drawPaddedButton(
    actionX, BTN_Y, actionText, actionColor,
    actionDisabled and disabledTextColor or C.white
  )
  drawPaddedButton(
    clearX, BTN_Y, QTY_CLEAR_TEXT, clearColor,
    quantity == "" and disabledTextColor or C.white
  )
end

drawAccountInfo = function()
  fill(RIGHT_INNER_X, ACC_Y, RIGHT_INNER_W, 7, C.bg)
  sectionHeader(RIGHT_INNER_X, ACC_Y, RIGHT_INNER_W, "АККАУНТ", C.sectionLine, C.white)
  local y = ACC_Y + 2
  text(RIGHT_INNER_X, y, "Имя: " .. account.nick, C.white, C.bg)
  y = y + 1
  local balancePrefix = "Баланс: "
  local coinLabel = "COINA " .. account.coina
  local balanceSeparator = " | "
  local emaLabel = "EMA " .. account.ema
  local balanceX = RIGHT_INNER_X
  text(balanceX, y, balancePrefix, C.white, C.bg)
  balanceX = balanceX + unicode.len(balancePrefix)
  text(balanceX, y, coinLabel, C.coin, C.bg)
  balanceX = balanceX + unicode.len(coinLabel)
  text(balanceX, y, balanceSeparator, C.white, C.bg)
  balanceX = balanceX + unicode.len(balanceSeparator)
  text(balanceX, y, emaLabel, C.ema, C.bg)
  y = y + 1
  text(RIGHT_INNER_X, y, "Регистрация: " .. account.regDate, C.gray, C.bg)
  y = y + 1
  text(RIGHT_INNER_X, y, "Транзакции: " .. account.trans, C.cyan, C.bg)
end

local function drawInformationSection()
  local infoY = ACC_Y + 7
  local maxRows = math.max(0, BOT_Y - infoY - 1)
  if maxRows <= 0 then return end

  fill(RIGHT_INNER_X, infoY, RIGHT_INNER_W, maxRows, C.bg)
  sectionHeader(RIGHT_INNER_X, infoY, RIGHT_INNER_W, "ИНФОРМАЦИЯ", C.sectionLine, C.white)

  local blocks = {
    {
      title = "АВТОКРАФТ",
      titleColor = C.autocraftAccent,
      lines = {
        "Если товара не хватает в МЭ,",
        "магазин предложит докрафтить",
        "недостающее количество и затем",
        "автоматически выдаст покупку.",
      },
    },
    {
      title = "COINA",
      titleColor = C.coin,
      lines = {
        "Основная валюта магазина.",
        "Ею оплачивается большая часть",
        "товаров в каталоге.",
      },
    },
    {
      title = "EMA",
      titleColor = C.ema,
      lines = {
        "Дополнительная ценная валюта.",
        "Используется для редких и",
        "особо важных товаров.",
      },
    },
  }

  local y = infoY + 2
  for _, block in ipairs(blocks) do
    if y >= BOT_Y - 1 then break end
    text(RIGHT_INNER_X, y, truncate(block.title, RIGHT_INNER_W), block.titleColor, C.bg)
    y = y + 1
    for _, lineText in ipairs(block.lines) do
      if y >= BOT_Y - 1 then break end
      text(RIGHT_INNER_X + 1, y, truncate("- " .. lineText, RIGHT_INNER_W - 1), C.infoDescription, C.bg)
      y = y + 1
    end
    if y < BOT_Y - 1 then y = y + 1 end
  end
end

drawRightPanel = function()
  drawInfoBlock()
  drawQuantitySection()
  drawAccountInfo()
  drawInformationSection()
end

local function drawBottomBar()
  fill(1, BOT_Y, WIDTH, 2, 0x0A0A0A)
  setFG(C.mainLine)
  setBG(C.bg)
  gpu.set(1, BOT_Y - 1, "+" .. string.rep("=", WIDTH - 2) .. "+")

  drawPaddedButton(
    BOTTOM_BUY_X,
    BOT_Y,
    BOTTOM_BUY_TEXT,
    C.buttonBuy,
    C.white
  )

  drawPaddedButton(
    BOTTOM_SELL_X,
    BOT_Y,
    BOTTOM_SELL_TEXT,
    C.buttonSales,
    C.white
  )

  drawPaddedButton(
    BOTTOM_AUTOCRAFT_X,
    BOT_Y,
    BOTTOM_AUTOCRAFT_TEXT,
    C.buttonCraft,
    0x000000
  )
end

local function drawBottomBorder()
  local footerText = "[ ZoziDo ] [ v_3.0.1 ]"
  local footerLen = unicode.len(footerText)
  local footerX = math.max(2, WIDTH - footerLen - 2)

  setFG(C.mainLine)
  setBG(C.bg)
  gpu.set(1, HEIGHT, "+" .. string.rep("=", WIDTH - 2) .. "+")

  -- Подпись встроена в правую часть нижней рамки. Перед закрывающим плюсом
  -- остаются два символа '=', как в формате +===Автор...==+.
  text(footerX, HEIGHT, footerText, C.darkGray, C.bg)
end

redrawAll = function()
  drawBackground()
  drawTopBar()
  drawMainFrames()
  drawLeftHeader()
  drawProductList()
  resetScrollbarState()
  drawScrollbar(true)
  drawRightPanel()
  drawBottomBar()
  drawBottomBorder()
  drawSeparator()
end

renderBuffer = nil
renderBufferChecked = false

function ensureRenderBuffer()
  if renderBufferChecked then return renderBuffer end
  renderBufferChecked = true

  if type(gpu.allocateBuffer) ~= "function"
    or type(gpu.setActiveBuffer) ~= "function"
    or type(gpu.bitblt) ~= "function"
  then
    return nil
  end

  local ok, buffer = pcall(gpu.allocateBuffer, WIDTH, HEIGHT)
  if ok and type(buffer) == "number" then
    renderBuffer = buffer
  end
  return renderBuffer
end

function renderAtomically(drawFunction, fallbackFunction)
  local buffer = ensureRenderBuffer()
  if not buffer then
    (fallbackFunction or drawFunction)()
    return
  end

  local previousBuffer = 0
  if type(gpu.getActiveBuffer) == "function" then
    local ok, value = pcall(gpu.getActiveBuffer)
    if ok and type(value) == "number" then previousBuffer = value end
  end

  local activated = pcall(gpu.setActiveBuffer, buffer)
  if not activated then
    (fallbackFunction or drawFunction)()
    return
  end

  local ok, err = pcall(drawFunction)
  pcall(gpu.setActiveBuffer, 0)

  if ok then
    local copied = pcall(gpu.bitblt, 0, 1, 1, WIDTH, HEIGHT, buffer, 1, 1)
    if not copied then
      (fallbackFunction or drawFunction)()
    end
  else
    pcall(gpu.setActiveBuffer, 0)
    error(err, 0)
  end

  -- Все последующие частичные перерисовки должны идти на реальный экран,
  -- а не случайно оставаться во вспомогательном буфере.
  pcall(gpu.setActiveBuffer, 0)
end

-- Атомарная перерисовка только области каталога и скроллбара.
-- Используется при клике по дорожке, когда смещение может быть большим.
-- Остальная часть магазина вообще не затрагивается.
function renderCatalogViewportAtomically()
  local function drawViewport()
    drawProductList()
    resetScrollbarState()
    drawScrollbar(true)
  end

  local buffer = ensureRenderBuffer()
  if not buffer
    or type(gpu.setActiveBuffer) ~= "function"
    or type(gpu.bitblt) ~= "function"
  then
    drawViewport()
    return false
  end

  local activated = pcall(gpu.setActiveBuffer, buffer)
  if not activated then
    activateFrontBuffer()
    drawViewport()
    return false
  end

  local ok = pcall(drawViewport)
  pcall(gpu.setActiveBuffer, 0)

  if not ok then
    activateFrontBuffer()
    drawViewport()
    return false
  end

  local viewportWidth = SCROLL_X - LIST_X + 1
  local copied, result = pcall(
    gpu.bitblt,
    0,
    LIST_X,
    LIST_Y,
    viewportWidth,
    LIST_H,
    buffer,
    LIST_X,
    LIST_Y
  )

  pcall(gpu.setActiveBuffer, 0)

  if not copied or result == false then
    activateFrontBuffer()
    drawViewport()
    return false
  end

  return true
end

-- V11: надёжное удаление POPUP для многомониторного OpenComputers.
-- После восстановления буфера магазин всегда перерисовывает свои слои
-- напрямую, но никогда не очищает весь экран.
lastPopupBox = nil
popupBackupBuffer = nil
popupBackupChecked = false
popupBackupValid = false
popupDirtyRect = nil

-- Запас очистки вокруг POPUP. Восстанавливается не весь экран, а только
-- область окна плюс 10 символов с каждой стороны. Это убирает остатки рамок
-- и при этом не вызывает моргание всего интерфейса.
popupClearMarginX = 10
popupClearMarginY = 10

function ensurePopupBackupBuffer()
  if popupBackupChecked then return popupBackupBuffer end
  popupBackupChecked = true

  if type(gpu.allocateBuffer) ~= "function" or type(gpu.bitblt) ~= "function" then
    return nil
  end

  local ok, buffer = pcall(gpu.allocateBuffer, WIDTH, HEIGHT)
  if ok and type(buffer) == "number" then
    popupBackupBuffer = buffer
  end
  return popupBackupBuffer
end

function getExpandedPopupRect(box)
  if not box then return nil end

  local x1 = math.max(1, (tonumber(box.x) or 1) - popupClearMarginX)
  local y1 = math.max(1, (tonumber(box.y) or 1) - popupClearMarginY)
  local x2 = math.min(WIDTH, (tonumber(box.x) or 1) + (tonumber(box.w) or 1) - 1 + popupClearMarginX)
  local y2 = math.min(HEIGHT, (tonumber(box.y) or 1) + (tonumber(box.h) or 1) - 1 + popupClearMarginY)

  return {
    x = x1,
    y = y1,
    w = math.max(1, x2 - x1 + 1),
    h = math.max(1, y2 - y1 + 1),
  }
end


-- Объединяет области всех POPUP, показанных в одной цепочке.
-- Это важно, когда широкое окно сменяется узким: линии старого окна
-- находятся за пределами последнего POPUP и иначе не очищаются.
function mergePopupDirtyRect(rect)
  if not rect then return end

  if not popupDirtyRect then
    popupDirtyRect = {
      x = rect.x,
      y = rect.y,
      w = rect.w,
      h = rect.h,
    }
    return
  end

  local x1 = math.min(popupDirtyRect.x, rect.x)
  local y1 = math.min(popupDirtyRect.y, rect.y)
  local x2 = math.max(
    popupDirtyRect.x + popupDirtyRect.w - 1,
    rect.x + rect.w - 1
  )
  local y2 = math.max(
    popupDirtyRect.y + popupDirtyRect.h - 1,
    rect.y + rect.h - 1
  )

  popupDirtyRect.x = x1
  popupDirtyRect.y = y1
  popupDirtyRect.w = x2 - x1 + 1
  popupDirtyRect.h = y2 - y1 + 1
end

function rememberPopupBox(box)
  lastPopupBox = box
  mergePopupDirtyRect(getExpandedPopupRect(box))
end

function savePopupBackground()
  local buffer = ensurePopupBackupBuffer()
  popupBackupValid = false
  if not buffer then return false end

  activateFrontBuffer()
  local ok, result = pcall(gpu.bitblt, buffer, 1, 1, WIDTH, HEIGHT, 0, 1, 1)
  popupBackupValid = ok and result ~= false
  return popupBackupValid
end

-- Собирает чистый магазин в скрытом GPU-буфере и переносит на монитор
-- только нужную область. Поэтому старый POPUP исчезает без очистки всего
-- экрана, без моргания и без зависимости от ранее сохранённого фона.
function redrawCleanShopRegion(rect)
  if not rect then return false end

  local buffer = ensureRenderBuffer()
  if not buffer or type(gpu.setActiveBuffer) ~= "function" or type(gpu.bitblt) ~= "function" then
    return false
  end

  local activated = pcall(gpu.setActiveBuffer, buffer)
  if not activated then
    pcall(gpu.setActiveBuffer, 0)
    return false
  end

  local ok, err = pcall(redrawAll)
  pcall(gpu.setActiveBuffer, 0)
  if not ok then
    return false
  end

  local copied, result = pcall(
    gpu.bitblt,
    0,
    rect.x,
    rect.y,
    rect.w,
    rect.h,
    buffer,
    rect.x,
    rect.y
  )

  pcall(gpu.setActiveBuffer, 0)
  return copied and result ~= false
end

function restorePopupBackground()
  local rect = popupDirtyRect
  if not rect and lastPopupBox then
    rect = getExpandedPopupRect(lastPopupBox)
  end

  if not rect then
    popupBackupValid = false
    lastPopupBox = nil
    popupDirtyRect = nil
    return false
  end

  -- Сначала пробуем быстро вернуть область из чистого скрытого кадра.
  -- На некоторых многомониторных сборках bitblt оставляет отдельные
  -- символы рамки, поэтому одного этого шага недостаточно.
  local restored = redrawCleanShopRegion(rect)

  if not restored and popupBackupValid and popupBackupBuffer then
    activateFrontBuffer()
    local ok, result = pcall(
      gpu.bitblt,
      0,
      rect.x,
      rect.y,
      rect.w,
      rect.h,
      popupBackupBuffer,
      rect.x,
      rect.y
    )
    restored = ok and result ~= false
  end

  popupBackupValid = false

  -- Если буферный перенос не сработал, локально очищаем всю объединённую
  -- область и восстанавливаем интерфейс напрямую. Это резервный путь.
  if not restored and uiState == "shop" and session.active then
    activateFrontBuffer()
    fill(rect.x, rect.y, rect.w, rect.h, C.bg)
  end

  -- Обязательный надёжный проход: поверх возможных остатков POPUP
  -- напрямую перерисовываются все элементы магазина. Фон экрана не
  -- очищается, term.clear() не вызывается, поэтому чёрного кадра и
  -- моргания от полной очистки нет. Этот проход исправляет вертикальные
  -- и горизонтальные линии, которые bitblt не восстановил на мониторах.
  if uiState == "shop" and session.active
    and type(redrawShopWithoutBlanking) == "function"
  then
    activateFrontBuffer()
    local ok = pcall(redrawShopWithoutBlanking)
    if ok then
      restored = true
      pcall(updateSelectorDisplay, items[selectedIndex])
    end
  end

  lastPopupBox = nil
  popupDirtyRect = nil
  return restored
end

function redrawShopWithoutBlanking()
  if lastPopupBox then
    local rect = getExpandedPopupRect(lastPopupBox)
    if rect then
      fill(rect.x, rect.y, rect.w, rect.h, C.bg)
    else
      fill(lastPopupBox.x, lastPopupBox.y, lastPopupBox.w, lastPopupBox.h, C.bg)
    end
  end
  drawTopBar()
  drawMainFrames()
  drawLeftHeader()
  drawProductList()
  resetScrollbarState()
  drawScrollbar(true)
  drawRightPanel()
  drawBottomBar()
  drawBottomBorder()
  drawSeparator()
end

presentShopFrame = function(forceFullRedraw)
  availabilityMenuOpen = false

  if forceFullRedraw then
    -- При переходе с приветствия нужно заменить абсолютно весь кадр.
    -- Иначе в сборках без GPU-буферов могут оставаться линии алмаза и рамки.
    activateFrontBuffer()
    renderAtomically(redrawAll, redrawAll)
  else
    renderAtomically(redrawAll, redrawShopWithoutBlanking)
  end

  lastPopupBox = nil
  if type(invalidateWelcomeFrame) == "function" then
    invalidateWelcomeFrame()
  end
  updateSelectorDisplay(items[selectedIndex])
end

local function redrawCatalogContent()
  -- Используется поиском: верхняя панель, рамки, аккаунт и низ не трогаются.
  drawProductList()
  resetScrollbarState()
  drawScrollbar(true)
  drawInfoBlock()
  drawQuantitySection()
  updateSelectorDisplay(items[selectedIndex])
end

function Performance.markInput()
  Performance.lastInputAt = computer.uptime()
end

function Performance.scheduleSearch()
  Performance.searchDirty = true
  Performance.nextSearchAt =
    computer.uptime() + Performance.searchDelay
end

function Performance.applySearchNow()
  if not Performance.searchDirty then return false end

  Performance.searchDirty = false
  Performance.nextSearchAt = 0
  filterItems()
  redrawCatalogContent()
  return true
end

local function drawVisibleItem(index)
  if not index or index < 1 then return end

  local row = index - scrollOffset
  if row >= 1 and row <= LIST_H then
    drawItemRow(index, LIST_Y + row - 1)
  end
end

local function setScrollOffset(newOffset)
  local maxScroll = math.max(0, #items - LIST_H)
  newOffset = math.max(0, math.min(maxScroll, newOffset))

  local oldOffset = scrollOffset
  if newOffset == oldOffset then
    return false
  end

  local delta = newOffset - oldOffset
  local copied = false

  -- Для одного шага сдвигаем готовые строки видеопамяти.
  -- Это значительно быстрее полной очистки и убирает моргание.
  if math.abs(delta) == 1 and LIST_H > 1 and #items > LIST_H then
    if delta > 0 then
      copied = pcall(
        gpu.copy,
        LIST_X,
        LIST_Y + 1,
        LIST_W,
        LIST_H - 1,
        0,
        -1
      )

      if copied then
        scrollOffset = newOffset
        local bottomY = LIST_Y + LIST_H - 1
        fill(LIST_X, bottomY, LIST_W, 1, C.bg)

        local newIndex = scrollOffset + LIST_H
        if newIndex <= #items then
          drawItemRow(newIndex, bottomY)
        end
      end
    else
      copied = pcall(
        gpu.copy,
        LIST_X,
        LIST_Y,
        LIST_W,
        LIST_H - 1,
        0,
        1
      )

      if copied then
        scrollOffset = newOffset
        fill(LIST_X, LIST_Y, LIST_W, 1, C.bg)

        local newIndex = scrollOffset + 1
        if newIndex <= #items then
          drawItemRow(newIndex, LIST_Y)
        end
      end
    end
  end

  if not copied then
    scrollOffset = newOffset

    -- При большом переходе (например, кликом по дорожке) не рисуем строки
    -- каталога прямо на видимом экране по одной. Сначала формируем весь
    -- участок каталога во вспомогательном GPU-буфере, затем переносим его
    -- на экран одним кадром. Это убирает моргание и видимые рывки.
    if type(renderCatalogViewportAtomically) == "function" then
      renderCatalogViewportAtomically()
    else
      drawProductList()
      resetScrollbarState()
      drawScrollbar(true)
    end
  else
    drawScrollbar(false)
  end

  return true
end

local function selectItem(index)
  if #items == 0 then return end

  index = math.max(1, math.min(#items, index))
  if index == selectedIndex then return end

  local oldIndex = selectedIndex
  local newOffset = scrollOffset

  if index - 1 < newOffset then
    newOffset = index - 1
  elseif index > newOffset + LIST_H then
    newOffset = index - LIST_H
  end

  selectedIndex = index
  quantity = ""

  if currentShopMode == "sell" then
    SellFlow.refreshSellInventory(items[selectedIndex])
  end

  setScrollOffset(newOffset)

  -- После gpu.copy убираем старое выделение и рисуем новое.
  drawVisibleItem(oldIndex)
  drawVisibleItem(selectedIndex)

  -- Аккаунт не менялся, поэтому его лишний раз не перерисовываем.
  drawInfoBlock()
  drawQuantitySection()
  updateSelectorDisplay(items[selectedIndex])
end

local function scroll(delta)
  if not delta or delta == 0 then return end
  setScrollOffset(scrollOffset + delta)
end

function Performance.queueScroll(delta)
  delta = tonumber(delta) or 0
  if delta == 0 then return end

  Performance.pendingScroll =
    (tonumber(Performance.pendingScroll) or 0) + delta

  if Performance.nextScrollAt <= computer.uptime() then
    Performance.nextScrollAt =
      computer.uptime() + Performance.scrollInterval
  end
end

function Performance.applyPendingScroll(now)
  now = tonumber(now) or computer.uptime()

  if Performance.pendingScroll == 0
    or now < Performance.nextScrollAt
  then
    return false
  end

  Performance.scrollStep = math.max(
    -6,
    math.min(6, Performance.pendingScroll)
  )

  Performance.pendingScroll =
    Performance.pendingScroll - Performance.scrollStep

  scroll(Performance.scrollStep)

  if Performance.pendingScroll ~= 0 then
    Performance.nextScrollAt =
      computer.uptime() + Performance.scrollInterval
  else
    Performance.nextScrollAt = 0
  end

  return true
end

-- Переход к месту нажатия на дорожке скроллбара.
-- Ползунок центрируется относительно строки, по которой нажал игрок.
local function jumpToScrollbarPosition(y)
  local total = #items
  if total <= LIST_H then return false end
  if y < LIST_Y or y > LIST_Y + LIST_H - 1 then return false end

  local thumbH = math.max(3, math.floor(LIST_H * LIST_H / total))
  thumbH = math.min(thumbH, LIST_H)

  local maxScroll = math.max(0, total - LIST_H)
  local maxThumbMove = math.max(0, LIST_H - thumbH)
  if maxScroll <= 0 or maxThumbMove <= 0 then return false end

  local clickedRow = y - LIST_Y
  local wantedThumbTop = clickedRow - math.floor(thumbH / 2)
  wantedThumbTop = math.max(0, math.min(maxThumbMove, wantedThumbTop))

  local targetOffset = math.floor(
    (wantedThumbTop * maxScroll / maxThumbMove) + 0.5
  )

  return setScrollOffset(targetOffset)
end

local function switchShopMode(mode)
  if mode ~= "buy" and mode ~= "sell" then return end
  if mode == currentShopMode and uiState == "shop" then return end

  currentShopMode = mode
  availabilityMenuOpen = false
  -- availabilityFilter не сбрасываем: выбранное состояние должно
  -- сохраняться при переходе между ПОКУПКАМИ и ПРОДАЖАМИ.
  searchQuery = ""
  searchFocused = false
  quantity = ""
  qtyFocused = false
  selectedIndex = 1
  scrollOffset = 0
  Performance.pendingScroll = 0
  Performance.nextScrollAt = 0

  -- Используем свежий кэш. Сигнал сайта инвалидирует нужный каталог,
  -- а максимальный возраст кэша не даёт ценам устареть надолго.
  loadItemsForCurrentMode(false)
  filterItems()
  presentShopFrame()
end

local function blurSearch()
  if searchFocused then
    Performance.applySearchNow()
    searchFocused = false
    redrawSearchField()
  end
end

local function drawPopupFrame(width, height, title, borderColor, useDouble)
  width = math.max(38, math.min(width, WIDTH - 4))
  height = math.max(10, math.min(height, HEIGHT - 2))

  local x = math.floor((WIDTH - width) / 2) + 1
  local y = math.floor((HEIGHT - height) / 2) + 1
  local bg = 0x050505
  local chars
  if useDouble then
    chars = {tl="╔", tr="╗", bl="╚", br="╝", h="═", v="║", ml="╠", mr="╣"}
  else
    chars = {tl="┌", tr="┐", bl="└", br="┘", h="─", v="│", ml="├", mr="┤"}
  end

  fill(x, y, width, height, bg)
  setBG(bg)
  setFG(borderColor or C.mainLine)
  gpu.set(x, y, chars.tl .. string.rep(chars.h, width - 2) .. chars.tr)
  gpu.set(x, y + height - 1, chars.bl .. string.rep(chars.h, width - 2) .. chars.br)
  for row = y + 1, y + height - 2 do
    gpu.set(x, row, chars.v)
    gpu.set(x + width - 1, row, chars.v)
  end
  gpu.set(x, y + 2, chars.ml .. string.rep(chars.h, width - 2) .. chars.mr)

  local clippedTitle = truncate(title, width - 6)
  text(x + math.floor((width - unicode.len(clippedTitle)) / 2), y + 1, clippedTitle, borderColor or C.white, bg)

  popupButtons = {}
  local box = {x=x, y=y, w=width, h=height, bg=bg}
  rememberPopupBox(box)
  return box
end

local function popupWrite(box, row, value, color, alignment)
  local valueText = truncate(tostring(value or ""), box.w - 6)
  local x = box.x + 3
  if alignment == "center" then
    x = box.x + math.floor((box.w - unicode.len(valueText)) / 2)
  elseif alignment == "right" then
    x = box.x + box.w - unicode.len(valueText) - 3
  end
  text(x, box.y + row, valueText, color or C.white, box.bg)
end

local function popupButton(box, label, row, bg, fg, action, x)
  local width = unicode.len(label) + 2
  x = x or (box.x + math.floor((box.w - width) / 2))
  local y = box.y + row
  drawPaddedButton(x, y, label, bg, fg)
  popupButtons[#popupButtons + 1] = {
    x=x, y=y, w=width, action=action
  }
  return x + width
end

local function drawInsufficientFundsPopup()
  if not popupState or popupState.type ~= "insufficient" then return end
  local data = popupState
  local box = drawPopupFrame(60, 18, "⚡ НУЖНО БОЛЬШЕ СРЕДСТВ!", C.red, true)
  local itemName = truncate(data.item.name, box.w - 24)

  popupWrite(box, 4, 'Чтобы купить "' .. itemName .. '"', C.white)
  popupWrite(box, 5, "вам нужно:", C.white)
  popupWrite(box, 7, string.format("💰 %.2f ₵  (у вас %.2f)", data.requiredCoin, data.balanceCoin), C.coin)
  popupWrite(box, 8, string.format("✨ %.2f ۞  (у вас %.2f)", data.requiredEma, data.balanceEma), C.ema)
  popupWrite(box, 10, "─── Как пополнить? ───", C.gray, "center")
  popupWrite(box, 11, "▶ Продать предметы в магазине", C.white)

  local sellLabel = "[ ПРОДАЖА ]"
  local closeLabel = "[ ЗАКРЫТЬ ]"
  local gap = 3
  local total = unicode.len(sellLabel) + 2 + gap + unicode.len(closeLabel) + 2
  local startX = box.x + math.floor((box.w - total) / 2)
  local nextX = popupButton(box, sellLabel, 14, C.buttonSales, C.white, "sell", startX)
  popupButton(box, closeLabel, 14, C.buttonClear, C.white, "close", nextX + gap)
end

local function drawInventoryFullPopup()
  if not popupState or popupState.type ~= "inventory_full" then return end
  local data = popupState

  if data.deliveryError then
    local box = drawPopupFrame(60, 17, "⚠ ОШИБКА ВЫДАЧИ!", C.red, true)
    popupWrite(box, 4, "МЭ не смогла выдать выбранный предмет", C.red)
    popupWrite(box, 6, "Вы пытаетесь купить:", C.white)
    popupWrite(box, 7, "✦ " .. truncate(data.item.name, box.w - 18) .. " (" .. tostring(data.qty) .. " шт.)", C.cyan)
    popupWrite(box, 9, "Инвентарь не считается заполненным.", C.gray)
    popupWrite(box, 10, "Повторите попытку через несколько секунд.", C.gray)
    popupButton(box, "[  ПОНЯТНО  ]", 14, C.buttonBuy, C.white, "close")
    return
  end

  local box = drawPopupFrame(60, 17, "📦 ИНВЕНТАРЬ ПОЛОН!", C.yellow, true)
  popupWrite(box, 4, "⚠ В вашем инвентаре нет места", C.yellow)
  popupWrite(box, 6, "Вы пытаетесь купить:", C.white)
  popupWrite(box, 7, "✦ " .. truncate(data.item.name, box.w - 18) .. " (" .. tostring(data.qty) .. " шт.)", C.cyan)
  popupWrite(box, 9, "📌 Решение:", C.white)
  popupWrite(box, 10, "Освободите 1 слот в инвентаре", C.gray)
  popupWrite(box, 11, "и попробуйте снова", C.gray)
  popupButton(box, "[  ПОНЯТНО  ]", 14, C.buttonBuy, C.white, "close")
end

local function drawReceiptPopup()
  if not popupState or popupState.type ~= "receipt" then return end
  local data = popupState
  local box = drawPopupFrame(66, 25, "🧾 ЧЕК ПОКУПКИ", C.mainLine, false)

  popupWrite(box, 3, "═══════════════════════════════", C.mainLine, "center")
  popupWrite(box, 4, "Магазин VIP SHOP", C.vipTitle, "center")
  popupWrite(box, 5, "═══════════════════════════════", C.mainLine, "center")
  popupWrite(box, 7, "Товар: " .. data.item.name, C.white)
  popupWrite(box, 8, "Артикул: " .. tostring(data.item.article or "#VIP-000"), C.gray)
  popupWrite(box, 9, "Кол-во: " .. tostring(data.qty) .. " шт.", C.white)
  popupWrite(box, 11, "─── ЦЕНА ───", C.gray, "center")
  popupWrite(box, 12, string.format("Coina: %.2f ₵ × %d = %.2f", data.unitCoin, data.qty, data.totalCoin), C.coin)
  popupWrite(box, 13, string.format("ЭМЫ:   %.2f ۞ × %d = %.2f", data.unitEma, data.qty, data.totalEma), C.ema)
  popupWrite(box, 15, "─── БАЛАНС ───", C.gray, "center")
  popupWrite(box, 16, string.format("Coina: до %.2f ₵  →  после %.2f ₵", data.beforeCoin, data.afterCoin), C.coin)
  popupWrite(box, 17, string.format("ЭМЫ:   до %.2f ۞  →  после %.2f ۞", data.beforeEma, data.afterEma), C.ema)
  popupWrite(box, 20, "✅ Транзакция #" .. tostring(data.transaction), C.green, "center")
  popupButton(box, "[  СПАСИБО ЗА ПОКУПКУ!  ]", 22, C.buttonBuy, C.white, "close")
end

function drawAutocraftReceiptPopup()
  if not popupState or popupState.type ~= "autocraft_receipt" then return end
  local data = popupState

  -- Двойная жёлтая рамка, как у окна ожидания автокрафта.
  -- Высота увеличена: кнопка находится выше нижней границы,
  -- после кнопки остаётся пустая строка.
  local box = drawPopupFrame(
    74,
    30,
    "⚙ АВТОКРАФТ УСПЕШНО ЗАВЕРШЁН",
    C.autocraftAccent,
    true
  )

  -- Внутренняя рамка результата рисуется по фиксированным координатам.
  -- Верх, низ и обе боковые стороны имеют одинаковую ширину, поэтому
  -- правая сторона больше не съезжает относительно нижнего угла.
  local resultX = box.x + 3
  local resultY = box.y + 3
  local resultW = box.w - 6
  local resultRight = resultX + resultW - 1

  setBG(box.bg)
  setFG(C.autocraftAccent)
  gpu.set(resultX, resultY, "┌" .. string.rep("─", resultW - 2) .. "┐")
  gpu.set(resultX, resultY + 1, "│")
  gpu.set(resultRight, resultY + 1, "│")
  gpu.set(resultX, resultY + 2, "│")
  gpu.set(resultRight, resultY + 2, "│")
  gpu.set(resultX, resultY + 3, "└" .. string.rep("─", resultW - 2) .. "┘")

  text(resultX + 2, resultY, " РЕЗУЛЬТАТ ", C.autocraftAccent, box.bg)
  text(resultX + 3, resultY + 1,
    "Товар: " .. truncate(data.item.name, resultW - 12),
    C.white,
    box.bg
  )
  text(resultX + 3, resultY + 2,
    "Артикул: " .. truncate(tostring(data.item.article or "#VIP-000"), resultW - 14),
    C.gray,
    box.bg
  )

  popupWrite(box, 8, string.format("Запрошено игроком:  %d шт.", data.qty), C.white)
  popupWrite(box, 9, string.format("Было в МЭ:          %d шт.", data.stockBefore or 0), C.gray)
  popupWrite(box, 10, string.format("Не хватало:          %d шт.", data.missing or 0), C.cyan)
  popupWrite(box, 11, string.format("Операций крафта:     %d", data.operations or 0), C.autocraftAccent)
  popupWrite(box, 12, string.format("Создано по шаблону:  %d шт.", data.produced or 0), C.green)
  popupWrite(box, 13, string.format("Выдано игроку:       %d шт.", data.qty), C.green)
  popupWrite(box, 14, string.format("Осталось в МЭ:       %d шт.", data.stockRemaining or 0), C.gray)

  popupWrite(box, 16, "─── ОПЛАТА ───", C.gray, "center")
  popupWrite(box, 17, string.format("COINA: %.2f ₵ × %d = %.2f ₵", data.unitCoin, data.qty, data.totalCoin), C.coin)
  popupWrite(box, 18, string.format("EMA:   %.2f ۞ × %d = %.2f ۞", data.unitEma, data.qty, data.totalEma), C.ema)

  popupWrite(box, 20, "─── БАЛАНС ПОСЛЕ ПОКУПКИ ───", C.gray, "center")
  popupWrite(box, 21, string.format("COINA: %.2f → %.2f ₵", data.beforeCoin, data.afterCoin), C.coin)
  popupWrite(box, 22, string.format("EMA:   %.2f → %.2f ۞", data.beforeEma, data.afterEma), C.ema)

  popupWrite(box, 24, "✓ Товар создан, оплачен и выдан игроку.", C.green, "center")
  popupWrite(box, 25, "Транзакция #" .. tostring(data.transaction), C.gray, "center")

  -- Строка 26: пустой отступ после транзакции.
  -- Строка 27: кнопка.
  -- Строка 28: пустой отступ после кнопки.
  -- Строка 29: нижняя двойная граница POPUP.
  popupButton(box, "[  ГОТОВО  ]", 27, C.buttonCraft, 0x000000, "close")
end

local function drawSaleReceiptPopup()
  if not popupState or popupState.type ~= "sale_receipt" then return end
  local data = popupState
  local box = drawPopupFrame(66, 23, "🧾 ЧЕК ПРОДАЖИ", C.mainLine, false)

  popupWrite(box, 3, "═══════════════════════════════", C.mainLine, "center")
  popupWrite(box, 4, "Магазин VIP SHOP", C.vipTitle, "center")
  popupWrite(box, 5, "═══════════════════════════════", C.mainLine, "center")
  popupWrite(box, 7, "Товар: " .. data.item.name, C.white)
  popupWrite(box, 8, "Артикул: " .. tostring(data.item.article or "#VIP-000"), C.gray)
  popupWrite(box, 9, "Кол-во: " .. tostring(data.qty) .. " шт.", C.white)
  popupWrite(box, 11, "─── ЦЕНА ───", C.gray, "center")
  popupWrite(box, 12, string.format("Coina: %.2f ₵ × %d = %.2f", data.unitCoin, data.qty, data.totalCoin), C.coin)
  popupWrite(box, 13, string.format("ЭМЫ:   %.2f ۞ × %d = %.2f", data.unitEma, data.qty, data.totalEma), C.ema)
  popupWrite(box, 15, "─── БАЛАНС ───", C.gray, "center")
  popupWrite(box, 16, string.format("Coina: до %.2f ₵  →  после %.2f ₵", data.beforeCoin, data.afterCoin), C.coin)
  popupWrite(box, 17, string.format("ЭМЫ:   до %.2f ۞  →  после %.2f ۞", data.beforeEma, data.afterEma), C.ema)
  popupWrite(box, 19, "✅ Транзакция #" .. tostring(data.transaction), C.green)
  popupWrite(box, 20, "📅 " .. tostring(data.date), C.gray)
  popupButton(box, "[  СПАСИБО ЗА ПРОДАЖУ!  ]", 21, C.buttonSales, C.white, "close")
end


function SellFlow.drawSaleConfirmPopup()
  if not popupState or popupState.type ~= "sale_confirm" then return end
  local data = popupState
  local box = drawPopupFrame(74, 23, "💰 ПРОДАЖА ТОВАРА", C.mainLine, true)
  local innerWidth = box.w - 8
  local innerLine = string.rep("─", math.max(8, innerWidth - 2))

  popupWrite(box, 3, "┌─ ПРЕДМЕТ " .. string.rep("─", math.max(1, innerWidth - 12)) .. "┐", C.mainLine)
  popupWrite(box, 4, "│  ✦ " .. truncate(data.item.name, innerWidth - 7), C.white)
  popupWrite(box, 5, "│  ID: " .. truncate(data.item.internalName, innerWidth - 8), C.gray)
  popupWrite(box, 6, "└" .. innerLine .. "┘", C.mainLine)

  popupWrite(box, 8, string.format("В инвентаре: %d шт.", data.inventoryQty), C.white)
  popupWrite(box, 9, string.format("Продаётся:  %d шт.", data.sellQty), C.green)

  popupWrite(box, 11, "┌─ РАСЧЁТ " .. string.rep("─", math.max(1, innerWidth - 11)) .. "┐", C.mainLine)
  if data.unitCoin > 0 then
    popupWrite(box, 12, string.format("│  Цена Coina: %.2f ₵ за 1 шт.", data.unitCoin), C.coin)
    popupWrite(box, 13, string.format("│  Итого Coina: %.2f ₵", data.totalCoin), C.coin)
  else
    popupWrite(box, 12, "│  Цена Coina: 0.00 ₵", C.darkGray)
    popupWrite(box, 13, "│  Итого Coina: 0.00 ₵", C.darkGray)
  end
  if data.unitEma > 0 then
    popupWrite(box, 14, string.format("│  Итого EMA: %.2f ۞", data.totalEma), C.ema)
  else
    popupWrite(box, 14, "│  Итого EMA: 0.00 ۞", C.darkGray)
  end
  popupWrite(box, 15, "└" .. innerLine .. "┘", C.mainLine)

  popupWrite(box, 17, "После продажи:", C.white)
  popupWrite(box, 18, string.format("Coina: %.2f → %.2f ₵", data.beforeCoin, data.afterCoin), C.coin)
  popupWrite(box, 19, string.format("EMA:   %.2f → %.2f ۞", data.beforeEma, data.afterEma), C.ema)

  local cancelLabel = "[ ОТМЕНА ]"
  local sellLabel = "[ ПРОДАТЬ ]"
  local gap = 4
  local totalWidth = unicode.len(cancelLabel) + 2 + gap + unicode.len(sellLabel) + 2
  local startX = box.x + math.floor((box.w - totalWidth) / 2)
  local nextX = popupButton(box, cancelLabel, 21, C.buttonClear, C.white, "sale_cancel", startX)
  popupButton(box, sellLabel, 21, C.buttonSales, C.white, "sale_confirm", nextX + gap)
end


local function drawAutocraftConfirmPopup()
  if not popupState or popupState.type ~= "autocraft_confirm" then return end
  local data = popupState
  local box = drawPopupFrame(74, 24, "⚙ АВТОКРАФТ ТОВАРА", C.autocraftAccent, true)
  local innerWidth = box.w - 8
  local innerLine = string.rep("─", math.max(8, innerWidth - 2))

  popupWrite(box, 3, "┌─ ПРЕДМЕТ " .. string.rep("─", math.max(1, innerWidth - 12)) .. "┐", C.autocraftAccent)
  popupWrite(box, 4, "│  ✦ " .. truncate(data.item.name, innerWidth - 7), C.white)
  popupWrite(box, 5, "│  ID: " .. truncate(data.item.internalName, innerWidth - 8), C.gray)
  popupWrite(box, 6, "└" .. innerLine .. "┘", C.autocraftAccent)

  popupWrite(box, 8, string.format("В МЭ сейчас:       %d шт.", data.stock), C.white)
  popupWrite(box, 9, string.format("Игрок покупает:    %d шт.", data.requestedQty), C.green)
  popupWrite(box, 10, string.format("Нужно докрафтить:  %d шт.", data.missing), C.cyan)

  popupWrite(box, 12, "┌─ ПЛАН КРАФТА " .. string.rep("─", math.max(1, innerWidth - 16)) .. "┐", C.mainLine)
  popupWrite(box, 13, string.format("│  Выход шаблона: %d шт. за операцию", data.output), C.white)
  popupWrite(box, 14, string.format("│  Операций МЭ:   %d", data.operations), C.white)
  popupWrite(box, 15, string.format("│  Будет создано: %d шт.", data.produced), C.green)
  popupWrite(box, 16, string.format("│  Лишнее останется в МЭ: %d шт.", data.surplus), C.gray)
  popupWrite(box, 17, "└" .. innerLine .. "┘", C.mainLine)

  popupWrite(box, 19, string.format("Итого COINA: %.2f ₵", data.totalCoin), C.coin)
  popupWrite(box, 20, string.format("Итого EMA:   %.2f ۞", data.totalEma), C.ema)

  local cancelLabel = "[ ОТМЕНА ]"
  local craftLabel = "[ ЗАПУСТИТЬ АВТОКРАФТ ]"
  local gap = 4
  local totalWidth = unicode.len(cancelLabel) + 2 + gap + unicode.len(craftLabel) + 2
  local startX = box.x + math.floor((box.w - totalWidth) / 2)
  local nextX = popupButton(box, cancelLabel, 22, C.buttonClear, C.white, "autocraft_cancel", startX)
  popupButton(box, craftLabel, 22, C.buttonCraft, C.white, "autocraft_confirm", nextX + gap)
end

function drawAutocraftHelpPopup()
  if not popupState or popupState.type ~= "autocraft_help" then return end

  local box = drawPopupFrame(
    74,
    33,
    "⚙ КАК РАБОТАЕТ АВТОКРАФТ",
    C.autocraftAccent,
    true
  )

  popupWrite(box, 4, "1. Выберите товар и укажите нужное количество.", C.white)
  popupWrite(box, 5, "2. Проверьте строку: Автокрафт: ДОСТУПЕН.", C.cyan)
  popupWrite(box, 6, "3. При нехватке товара появится кнопка АВТОКРАФТ.", C.white)
  popupWrite(box, 7, "4. Подтвердите запуск и дождитесь завершения МЭ.", C.white)

  popupWrite(box, 9, "── ДЕНЬГИ ──", C.autocraftAccent, "center")
  popupWrite(box, 10, "Баланс проверяется перед запуском крафта.", C.coin)
  popupWrite(box, 11, "Деньги списываются только после успешной выдачи.", C.coin)
  popupWrite(box, 12, "При ошибке или нехватке ресурсов списания нет.", C.gray)

  popupWrite(box, 14, "── ЕСЛИ УЙТИ С PIM ──", C.autocraftAccent, "center")
  popupWrite(box, 15, "Сессия закроется, товар игроку не выдастся.", C.white)
  popupWrite(box, 16, "Деньги не спишутся.", C.green)
  popupWrite(box, 17, "Готовый предмет может остаться в МЭ-системе.", C.gray)

  popupWrite(box, 19, "── ВАЖНО ──", C.autocraftAccent, "center")
  popupWrite(box, 20, "Можно крафтить товар с остатком 0 в МЭ,", C.cyan)
  popupWrite(box, 21, "если для этого предмета существует шаблон.", C.cyan)
  popupWrite(box, 22, "Не уходите с PIM и освободите место в инвентаре.", C.yellow)

  popupWrite(box, 24, "── ПРЕДУПРЕЖДЕНИЕ ──", C.red, "center")
  popupWrite(box, 25, "Обход системы, накрутка и чрезмерное использование", C.red, "center")
  popupWrite(box, 26, "караются полной блокировкой доступа к VIP-SHOP.", C.red, "center")
  popupWrite(box, 27, "Все действия и данные операций логируются.", C.gray, "center")

  popupButton(box, "[  ПОНЯТНО  ]", 30, C.buttonCraft, 0x000000, "close")
end

local function drawAutocraftSearchPopup()
  if not popupState or popupState.type ~= "autocraft_search" then return end
  local data = popupState
  local box = drawPopupFrame(62, 13, "⚙ ПРОВЕРКА АВТОКРАФТА", C.autocraftAccent, true)

  popupWrite(box, 4, "✦ " .. truncate(data.item and data.item.name or "Товар", box.w - 12), C.white, "center")
  popupWrite(box, 6, tostring(data.statusText or "Поиск шаблона в МЭ..."), C.cyan, "center")
  popupWrite(box, 8, "Пожалуйста, подождите — магазин работает.", C.yellow, "center")
  popupWrite(box, 10, "Первый поиск может занять несколько секунд.", C.gray, "center")
end

local function drawAutocraftProgressPopup()
  if not popupState or popupState.type ~= "autocraft_progress" then return end
  local data = popupState
  local box = drawPopupFrame(68, 19, "⚙ АВТОКРАФТ ВЫПОЛНЯЕТСЯ", C.autocraftAccent, true)

  popupWrite(box, 4, "✦ " .. truncate(data.item.name, box.w - 12), C.white, "center")
  popupWrite(box, 6, tostring(data.statusText or "Подготовка..."), C.cyan, "center")
  popupWrite(box, 8, string.format("Требуется игроку: %d шт.", data.requestedQty), C.white)
  popupWrite(box, 9, string.format("Было в МЭ:        %d шт.", data.stockBefore), C.gray)
  popupWrite(box, 10, string.format("Заказано операций: %d", data.operations), C.white)
  popupWrite(box, 11, string.format("Ожидаемый выпуск:  %d шт.", data.produced), C.green)
  popupWrite(box, 13, string.format("Сейчас в МЭ:       %d шт.", tonumber(data.currentStock) or 0), C.coin)
  popupWrite(box, 14, string.format("Прошло времени:    %d сек.", tonumber(data.elapsed) or 0), C.gray)
  popupWrite(box, 16, "Не сходите с PIM до завершения выдачи.", C.yellow, "center")
end



function SecureSale.drawPurchaseErrorPopup()
  if not popupState or popupState.type ~= "purchase_error" then return end

  local data = popupState
  local box = drawPopupFrame(68, 17, "⚠ ПОКУПКА ОТКЛОНЕНА", C.red, true)

  popupWrite(box, 4, "Покупка не выполнена.", C.red, "center")
  popupWrite(
    box,
    6,
    truncate(data.item and data.item.name or "Неизвестный товар", box.w - 12),
    C.white,
    "center"
  )
  popupWrite(
    box,
    8,
    tostring(data.message or "Сервер отклонил операцию."),
    C.yellow,
    "center"
  )
  popupWrite(box, 10, "Товар не выдан.", C.red, "center")
  popupWrite(box, 11, "Деньги не списаны.", C.green, "center")
  popupButton(box, "[  ПОНЯТНО  ]", 14, C.buttonClear, C.white, "close")
end

function SecureSale.drawSalePendingPopup()
  if not popupState or popupState.type ~= "sale_pending" then return end

  local data = popupState
  local box = drawPopupFrame(72, 19, "⚠ ПРОДАЖА ОЖИДАЕТ НАЧИСЛЕНИЯ", C.yellow, true)

  popupWrite(box, 4, "Предметы уже приняты магазином.", C.white, "center")
  popupWrite(
    box,
    6,
    truncate(data.item and data.item.name or "Неизвестный товар", box.w - 12),
    C.white,
    "center"
  )
  popupWrite(
    box,
    7,
    "Количество: " .. tostring(data.qty or 0) .. " шт.",
    C.gray,
    "center"
  )
  popupWrite(box, 9, tostring(data.message or "Сервер временно недоступен."), C.yellow, "center")
  popupWrite(box, 11, "Операция сохранена на HDD.", C.cyan, "center")
  popupWrite(box, 12, "Начисление повторится при следующем входе.", C.green, "center")
  popupWrite(box, 14, "Повторно продавать эти предметы не нужно.", C.red, "center")
  popupButton(box, "[  ПОНЯТНО  ]", 16, C.buttonBuy, C.white, "close")
end

local function drawNetworkErrorPopup()
  if not popupState or popupState.type ~= "network_error" then return end

  local data = popupState
  local box = drawPopupFrame(68, 17, "⚠ НЕТ СВЯЗИ С СЕРВЕРОМ", C.red, true)

  popupWrite(box, 4, "Покупка временно недоступна.", C.red, "center")
  popupWrite(
    box,
    6,
    truncate(data.item and data.item.name or "Неизвестный товар", box.w - 12),
    C.white,
    "center"
  )
  popupWrite(
    box,
    8,
    tostring(data.message or "Сервер магазина не отвечает."),
    C.yellow,
    "center"
  )
  popupWrite(box, 10, "Товар не выдан.", C.red, "center")

  if data.pendingPurchase then
    popupWrite(
      box,
      11,
      "Статус оплаты сохранён и будет проверен при входе.",
      C.yellow,
      "center"
    )
    popupWrite(
      box,
      12,
      "Повторно нажимать покупку сейчас не нужно.",
      C.gray,
      "center"
    )
  else
    popupWrite(box, 11, "Деньги не списаны.", C.green, "center")
    popupWrite(
      box,
      12,
      "Повторите попытку после восстановления связи.",
      C.gray,
      "center"
    )
  end
  popupButton(box, "[  ПОНЯТНО  ]", 14, C.buttonClear, C.white, "close")
end

local function drawAutocraftErrorPopup()
  if not popupState or popupState.type ~= "autocraft_error" then return end
  local data = popupState
  local box = drawPopupFrame(66, 17, "⚠ ОШИБКА АВТОКРАФТА", C.red, true)

  popupWrite(box, 4, "Не удалось завершить автокрафт:", C.red, "center")
  popupWrite(box, 6, truncate(data.item and data.item.name or "Неизвестный товар", box.w - 12), C.white, "center")
  popupWrite(box, 8, tostring(data.message or "Неизвестная ошибка"), C.yellow, "center")
  popupWrite(box, 10, "Деньги не списаны.", C.green, "center")
  popupWrite(box, 11, "Готовые предметы, если они появились, остались в МЭ.", C.gray, "center")
  popupButton(box, "[  ПОНЯТНО  ]", 14, C.buttonClear, C.white, "close")
end

local function drawCurrentPopup()
  if not popupState then return end
  if popupState.type == "insufficient" then
    drawInsufficientFundsPopup()
  elseif popupState.type == "inventory_full" then
    drawInventoryFullPopup()
  elseif popupState.type == "receipt" then
    drawReceiptPopup()
  elseif popupState.type == "autocraft_receipt" then
    drawAutocraftReceiptPopup()
  elseif popupState.type == "sale_receipt" then
    drawSaleReceiptPopup()
  elseif popupState.type == "sale_confirm" then
    SellFlow.drawSaleConfirmPopup()
  elseif popupState.type == "autocraft_confirm" then
    drawAutocraftConfirmPopup()
  elseif popupState.type == "autocraft_help" then
    drawAutocraftHelpPopup()
  elseif popupState.type == "autocraft_search" then
    drawAutocraftSearchPopup()
  elseif popupState.type == "autocraft_progress" then
    drawAutocraftProgressPopup()
  elseif popupState.type == "autocraft_error" then
    drawAutocraftErrorPopup()
  elseif popupState.type == "network_error" then
    drawNetworkErrorPopup()
  elseif popupState.type == "purchase_error" then
    SecureSale.drawPurchaseErrorPopup()
  elseif popupState.type == "sale_pending" then
    SecureSale.drawSalePendingPopup()
  end
end

function resetPopupBuffers()
  popupBackupValid = false
  lastPopupBox = nil
  popupDirtyRect = nil
end

-- Рисует POPUP во вспомогательном GPU-буфере и переносит на экран только
-- его расширенную область. Остальной интерфейс вообще не перерисовывается.
function drawPopupRegionAtomically()
  popupButtons = {}

  local buffer = ensureRenderBuffer()
  if not buffer
    or type(gpu.setActiveBuffer) ~= "function"
    or type(gpu.bitblt) ~= "function"
  then
    activateFrontBuffer()
    drawCurrentPopup()
    return true
  end

  activateFrontBuffer()
  local copied, copyResult = pcall(
    gpu.bitblt,
    buffer,
    1,
    1,
    WIDTH,
    HEIGHT,
    0,
    1,
    1
  )

  if not copied or copyResult == false then
    activateFrontBuffer()
    drawCurrentPopup()
    return true
  end

  local activated = pcall(gpu.setActiveBuffer, buffer)
  if not activated then
    activateFrontBuffer()
    drawCurrentPopup()
    return true
  end

  local ok, err = pcall(drawCurrentPopup)
  pcall(gpu.setActiveBuffer, 0)

  if not ok then
    error(err, 0)
  end

  local rect = getExpandedPopupRect(lastPopupBox)
  if not rect then
    activateFrontBuffer()
    drawCurrentPopup()
    return true
  end

  local blitted, blitResult = pcall(
    gpu.bitblt,
    0,
    rect.x,
    rect.y,
    rect.w,
    rect.h,
    buffer,
    rect.x,
    rect.y
  )

  pcall(gpu.setActiveBuffer, 0)

  if not blitted or blitResult == false then
    activateFrontBuffer()
    drawCurrentPopup()
  end

  return true
end

-- Обновление уже открытого POPUP, например счётчика времени автокрафта.
-- Фон магазина не сохраняется заново и весь экран не копируется на монитор.
function refreshCurrentPopup()
  if not popupState then return false end
  return drawPopupRegionAtomically()
end

function forceCleanShopRedraw()
  -- restorePopupBackground() сам выполняет надёжную прямую перерисовку
  -- интерфейса без очистки экрана. Дополнительный полный проход не нужен.
  if restorePopupBackground() then
    return true
  end

  if uiState == "shop" and session.active then
    activateFrontBuffer()
    redrawShopWithoutBlanking()
    updateSelectorDisplay(items[selectedIndex])
  end
  resetPopupBuffers()
  return false
end

presentCurrentPopup = function()
  availabilityMenuOpen = false

  -- Перед новым POPUP убираем объединённую область всех предыдущих окон
  -- в текущей цепочке. Поэтому широкая старая рамка не останется за
  -- пределами более узкого нового POPUP.
  if lastPopupBox then
    forceCleanShopRedraw()
  end

  -- Сохраняем чистый кадр перед новым окном. Копирование происходит внутри
  -- видеопамяти и не вызывает видимого моргания.
  savePopupBackground()
  drawPopupRegionAtomically()
end

closePopup = function()
  popupState = nil
  popupButtons = {}
  forceCleanShopRedraw()
end

function clearPopupForReplacement()
  popupState = nil
  popupButtons = {}
  forceCleanShopRedraw()
end

local function handlePopupClick(x, y)
  if not popupState then return false end
  for _, button in ipairs(popupButtons) do
    if y == button.y and x >= button.x and x < button.x + button.w then
      local action = button.action
      if action == "sell" then
        popupState = nil
        popupButtons = {}
        restorePopupBackground()
        switchShopMode("sell")
      elseif action == "sale_confirm" then
        if SellFlow.confirm then SellFlow.confirm() end
      elseif action == "sale_cancel" then
        closePopup()
      elseif action == "autocraft_confirm" then
        AutoCraft.confirm()
      elseif action == "autocraft_cancel" then
        closePopup()
      else
        closePopup()
      end
      return true
    end
  end
  return true
end

local function proxyCallWithArgs(proxy, methodName, ...)
  if not proxy or type(proxy[methodName]) ~= "function" then return false, nil end
  local fn = proxy[methodName]
  local ok, result = pcall(fn, ...)
  if ok then return true, result end
  ok, result = pcall(fn, proxy, ...)
  if ok then return true, result end
  return false, result
end

local function getActualItemQuantity(item)
  if not item then return 0 end
  local key = tostring(item.internalName) .. ":" .. tostring(tonumber(item.damage) or 0)
  local quantities = getMEQuantities()
  return tonumber(quantities[key]) or 0
end

local function getMaxStackSize(me, item)
  local attempts = {
    function() return me.getItemDetail(item.internalName, item.damage or 0) end,
    function() return me.getItemDetail(me, item.internalName, item.damage or 0) end,
    function() return me.getItemDetail({id=item.internalName, dmg=item.damage or 0}) end,
  }
  for _, attempt in ipairs(attempts) do
    local ok, detail = pcall(attempt)
    if ok and type(detail) == "table" then
      local maxSize = tonumber(detail.maxSize or detail.maxStackSize)
      if maxSize and maxSize > 0 then return maxSize end
    end
  end
  return 64
end

local function inventoryHasSpace(item, qty, maxStackSize)
  local pim = getPimProxy()
  if not pim or type(pim.getStackInSlot) ~= "function" then return nil end

  local size = tonumber(callPimMethod(pim, "getInventorySize")) or 40
  size = math.max(1, math.min(math.floor(size), 64))
  local capacity = 0
  local readAnySlot = false

  -- На текущей PIM слоты нумеруются с нуля: при размере 40 это 0..39.
  -- Дополнительный крайний индекс безопасен и помогает сборкам с нумерацией с 1.
  for slot = 0, size do
    local ok, stack = proxyCallWithArgs(pim, "getStackInSlot", slot)
    if ok then
      readAnySlot = true
      local stackName = type(stack) == "table" and (stack.name or stack.id) or nil
      local stackSize = type(stack) == "table" and tonumber(stack.size or stack.qty or stack.count) or 0

      if not stackName or stackSize <= 0 then
        capacity = capacity + maxStackSize
      else
        local stackDamage = tonumber(stack.damage or stack.dmg) or 0
        if tostring(stackName) == tostring(item.internalName)
          and stackDamage == (tonumber(item.damage) or 0)
        then
          local stackMax = tonumber(stack.maxSize or stack.maxStackSize) or maxStackSize
          capacity = capacity + math.max(0, stackMax - stackSize)
        end
      end

      if capacity >= qty then return true end
    end
  end

  if not readAnySlot then return nil end
  return capacity >= qty
end

MEExport = MEExport or {}

-- exportItem в этой сборке возвращает таблицу вида
-- {size=1, fingerprint={id=..., dmg=..., nbt_hash=...}}, а не число.
function MEExport.parseCount(result, requested)
  if type(result) == "number" then
    return math.max(0, math.floor(result))
  end
  if result == true then
    return math.max(0, math.floor(tonumber(requested) or 0))
  end
  if type(result) == "table" then
    return math.max(0, math.floor(tonumber(
      result.size or result.count or result.amount or result.qty
    ) or 0))
  end
  return 0
end

function MEExport.normalizeId(value)
  local id = tostring(value or "")
  if id ~= "" and not id:find(":", 1, true) then
    id = "minecraft:" .. id
  end
  return id
end

function MEExport.getAddress(me)
  if me and type(me.address) == "string" and me.address ~= "" then
    return me.address
  end

  for address in component.list("me_interface") do
    return address
  end
  for address in component.list("me_bridge") do
    return address
  end

  return nil
end

-- В диагностике рабочими оказались именно component.invoke и режим NONE.
-- Без NONE getAvailableItems на этой сборке может вернуть proxy-объекты,
-- из которых магазин не видит fingerprint и получает вариантов=0.
function MEExport.callList(me, methodName, details)
  local address = MEExport.getAddress(me)

  if address then
    local ok, result
    if details ~= nil then
      ok, result = pcall(component.invoke, address, methodName, details)
    else
      ok, result = pcall(component.invoke, address, methodName)
    end
    if ok and type(result) == "table" then
      return result
    end
    if not ok then
      writeDebugLog("Ошибка " .. tostring(methodName) .. " через component.invoke: " .. tostring(result))
    end
  end

  if not me or type(me[methodName]) ~= "function" then return nil end

  local ok, result
  if details ~= nil then
    ok, result = pcall(me[methodName], details)
  else
    ok, result = pcall(me[methodName])
  end
  if ok and type(result) == "table" then return result end

  if details ~= nil then
    ok, result = pcall(me[methodName], me, details)
  else
    ok, result = pcall(me[methodName], me)
  end
  if ok and type(result) == "table" then return result end

  return nil
end

-- Получает только fingerprint нужного товара. Большой список МЭ не сохраняется
-- в магазине: после прохода остаются лишь несколько маленьких записей.
function MEExport.findVariants(me, item)
  local targetId = MEExport.normalizeId(item and item.internalName)
  local targetDamage = tonumber(item and item.damage) or 0
  local wantedHash = item and (item.nbt_hash or item.nbtHash) or nil
  local variants = {}
  local seen = {}
  local scanned = 0

  -- Повторяем ТОЧНО тот способ, который сработал в диагностике:
  -- component.invoke(address, "getAvailableItems", "NONE").
  local networkItems = MEExport.callList(me, "getAvailableItems", "NONE")
  if type(networkItems) ~= "table" then
    -- Резерв для сборок, где аргумент NONE не поддерживается.
    networkItems = MEExport.callList(me, "getAvailableItems")
  end

  if type(networkItems) == "table" then
    for _, entry in pairs(networkItems) do
      if type(entry) == "table" then
        scanned = scanned + 1
        local fingerprint = type(entry.fingerprint) == "table"
          and entry.fingerprint or entry

        if type(fingerprint) == "table" then
          local id = MEExport.normalizeId(
            fingerprint.id or fingerprint.name
            or entry.id or entry.name
          )
          local damage = tonumber(
            fingerprint.dmg or fingerprint.damage or fingerprint.meta
            or entry.dmg or entry.damage or entry.meta
          ) or 0
          local hash = fingerprint.nbt_hash or fingerprint.nbtHash
            or fingerprint.tag_hash or fingerprint.tagHash
            or entry.nbt_hash or entry.nbtHash
            or entry.tag_hash or entry.tagHash
          local count = tonumber(
            entry.size or entry.qty or entry.count or entry.amount
            or entry.available
            or fingerprint.size or fingerprint.qty
          ) or 0

          local hashMatches = not wantedHash
            or tostring(hash or "") == tostring(wantedHash)

          if id == targetId and damage == targetDamage
            and count > 0 and hashMatches
          then
            local key = id .. ":" .. tostring(damage) .. ":" .. tostring(hash or "")
            if not seen[key] then
              seen[key] = true
              variants[#variants + 1] = {
                -- Передаём RAW fingerprint без пересоздания таблицы.
                fingerprint = fingerprint,
                count = math.floor(count),
                nbt_hash = hash,
              }
            end
          end
        end
      end
    end
  end

  networkItems = nil

  table.sort(variants, function(a, b)
    return (tonumber(a.count) or 0) > (tonumber(b.count) or 0)
  end)

  writeDebugLog(string.format(
    "МЭ fingerprint: %s dmg=%s, просмотрено=%d, вариантов=%d, hash каталога=%s",
    targetId,
    tostring(targetDamage),
    scanned,
    #variants,
    tostring(wantedHash)
  ))

  return variants
end

function MEExport.invokeExport(me, fingerprint, amount)
  local address = MEExport.getAddress(me)
  local ok, result

  -- Рабочий диагностический вызов: component.invoke по адресу МЭ.
  if address then
    ok, result = pcall(
      component.invoke,
      address,
      "exportItem",
      fingerprint,
      ME_EXPORT_DIRECTION,
      amount
    )
  end

  -- Резерв оставлен для обычных предметов и других сборок.
  if not ok then
    ok, result = pcall(
      me.exportItem,
      fingerprint,
      ME_EXPORT_DIRECTION,
      amount
    )
  end
  if not ok then
    ok, result = pcall(
      me.exportItem,
      me,
      fingerprint,
      ME_EXPORT_DIRECTION,
      amount
    )
  end

  if not ok then
    writeDebugLog("Ошибка exportItem: " .. tostring(result))
    return 0, result
  end

  local moved = MEExport.parseCount(result, amount)
  local resultHash = nil
  if type(result) == "table" and type(result.fingerprint) == "table" then
    resultHash = result.fingerprint.nbt_hash or result.fingerprint.nbtHash
  end
  if not resultHash and type(fingerprint) == "table" then
    resultHash = fingerprint.nbt_hash or fingerprint.nbtHash
  end

  writeDebugLog(string.format(
    "exportItem: requested=%d, moved=%d, resultType=%s, hash=%s",
    tonumber(amount) or 0,
    moved,
    type(result),
    tostring(resultHash)
  ))
  return moved, result
end

function MEExport.exportToPlayer(me, item, qty, maxStackSize)
  qty = math.max(0, math.floor(tonumber(qty) or 0))
  if qty <= 0 or not me or not item then return 0 end

  local remaining = qty
  local extracted = 0
  local chunkLimit = math.max(1, math.floor(tonumber(maxStackSize) or 64))
  local variants = MEExport.findVariants(me, item)

  -- Основной способ: точные RAW fingerprint из getAvailableItems(), включая
  -- nbt_hash для зарядов, чар и других уникальных данных.
  for _, variant in ipairs(variants) do
    local available = math.max(0, math.floor(tonumber(variant.count) or 0))

    while remaining > 0 and available > 0 do
      local toTake = math.min(remaining, available, chunkLimit)
      local moved = MEExport.invokeExport(me, variant.fingerprint, toTake)
      if moved <= 0 then break end

      extracted = extracted + moved
      remaining = remaining - moved
      available = available - moved
    end

    if remaining <= 0 then break end
  end

  -- Резерв старого поведения. Он нужен для обычных предметов на сборках,
  -- где список МЭ временно не читается, но exportItem({id,dmg}, ...) работает.
  if remaining > 0 then
    local legacyFingerprint = {
      id = MEExport.normalizeId(item.internalName),
      dmg = tonumber(item.damage) or 0,
    }

    while remaining > 0 do
      local toTake = math.min(remaining, chunkLimit)
      local moved = MEExport.invokeExport(me, legacyFingerprint, toTake)
      if moved <= 0 then break end

      extracted = extracted + moved
      remaining = remaining - moved
    end
  end

  writeDebugLog(string.format(
    "Итог выдачи: item=%s, requested=%d, extracted=%d",
    tostring(item.internalName),
    qty,
    extracted
  ))

  return extracted
end


function SecurePurchase.createId(playerName)
  SecurePurchase.idCounter =
    (tonumber(SecurePurchase.idCounter) or 0) + 1

  local randomPart = math.random(100000, 999999)
  local uptimePart = math.floor((computer.uptime() or 0) * 1000)

  local addressPart = "oc"
  if type(computer.address) == "function" then
    local ok, value = pcall(computer.address)
    if ok and value then
      addressPart = tostring(value):gsub("[^%w]", ""):sub(1, 12)
    end
  end

  return table.concat({
    tostring(playerName or "unknown"),
    addressPart,
    tostring(uptimePart),
    tostring(SecurePurchase.idCounter),
    tostring(randomPart),
  }, "-")
end

function SecurePurchase.charge(playerName, item, qty, transactionId)
  local response, requestError = httpPostJson(
    SecurePurchase.url,
    {
      action = "purchase",
      name = playerName,
      item = item.internalName,
      damage = tonumber(item.damage) or 0,
      qty = qty,
      transactionId = transactionId,
    },
    SecurePurchase.timeout
  )

  if not response then
    return nil,
      "Нет связи с сервером. Товар не выдан. "
        .. tostring(requestError or ""),
      "network"
  end

  if response.status ~= "ok" then
    return nil,
      tostring(response.message or response.error
        or "Сервер отклонил покупку"),
      "server"
  end

  local data = type(response.data) == "table" and response.data or response
  return data, nil, nil
end

function SecurePurchase.adjust(playerName, transactionId, deliveredQty)
  local response, requestError = httpPostJson(
    SecurePurchase.url,
    {
      action = "adjust_purchase",
      name = playerName,
      transactionId = transactionId,
      deliveredQty = math.max(0, math.floor(tonumber(deliveredQty) or 0)),
    },
    SecurePurchase.timeout
  )

  if not response then
    return nil, requestError or "Нет связи с сервером возврата"
  end
  if response.status ~= "ok" then
    return nil, tostring(response.message or response.error or "Возврат отклонён")
  end

  return type(response.data) == "table" and response.data or response, nil
end

function SecurePurchase.finalize(playerName, transactionId)
  event.timer(0.1, function()
    pcall(
      httpPostJson,
      SecurePurchase.url,
      {
        action = "finalize_purchase",
        name = playerName,
        transactionId = transactionId,
      },
      SecurePurchase.timeout
    )
    return false
  end)
end


SecurePurchase.pendingFile = "/home/pending_purchases.json"
SecurePurchase.pending = SecurePurchase.pending or nil

function SecurePurchase.loadPending()
  if type(SecurePurchase.pending) == "table" then
    return SecurePurchase.pending
  end

  SecurePurchase.pending = {}

  -- После аварии во время атомарной замены основной файл может ещё
  -- находиться под именем .bak или .tmp.
  local candidates = {
    SecurePurchase.pendingFile,
    SecurePurchase.pendingFile .. ".bak",
    SecurePurchase.pendingFile .. ".tmp",
  }

  for _, path in ipairs(candidates) do
    local file = io.open(path, "r")
    if file then
      local raw = file:read("*a")
      file:close()

      local decoded = decodeJson(raw or "")
      if type(decoded) == "table" then
        SecurePurchase.pending = decoded

        if path ~= SecurePurchase.pendingFile then
          SecurePurchase.savePending()
        end

        return SecurePurchase.pending
      end
    end
  end

  return SecurePurchase.pending
end

function SecurePurchase.savePending()
  local pending = SecurePurchase.pending or {}

  if #pending == 0 then
    os.remove(SecurePurchase.pendingFile)
    os.remove(SecurePurchase.pendingFile .. ".tmp")
    os.remove(SecurePurchase.pendingFile .. ".bak")
    return true
  end

  local encoded = encodeJson(pending)
  if not encoded then return false end

  local tempPath = SecurePurchase.pendingFile .. ".tmp"
  local file = io.open(tempPath, "w")
  if not file then return false end

  file:write(encoded)
  file:close()

  local oldPath = SecurePurchase.pendingFile .. ".bak"
  os.remove(oldPath)
  os.rename(SecurePurchase.pendingFile, oldPath)

  if os.rename(tempPath, SecurePurchase.pendingFile) then
    os.remove(oldPath)
    return true
  end

  os.rename(oldPath, SecurePurchase.pendingFile)
  os.remove(tempPath)
  return false
end

function SecurePurchase.findPending(transactionId)
  local pending = SecurePurchase.loadPending()
  for index, operation in ipairs(pending) do
    if tostring(operation.transactionId or "") ==
        tostring(transactionId or "") then
      return operation, index
    end
  end
  return nil, nil
end

function SecurePurchase.upsertPending(operation)
  local pending = SecurePurchase.loadPending()
  local existing, index = SecurePurchase.findPending(
    operation.transactionId
  )

  if existing and index then
    pending[index] = operation
  else
    pending[#pending + 1] = operation
  end

  return SecurePurchase.savePending()
end

function SecurePurchase.removePending(transactionId)
  local pending = SecurePurchase.loadPending()
  local remaining = {}

  for _, operation in ipairs(pending) do
    if tostring(operation.transactionId or "") ~=
        tostring(transactionId or "") then
      remaining[#remaining + 1] = operation
    end
  end

  SecurePurchase.pending = remaining
  return SecurePurchase.savePending()
end

function SecurePurchase.retryForPlayer(playerName)
  local pending = SecurePurchase.loadPending()
  if #pending == 0 then return 0, 0 end

  local recovered = 0
  local manual = 0

  for _, operation in ipairs(pending) do
    if lowerText(tostring(operation.player or "")) ==
        lowerText(tostring(playerName or "")) then

      local status = tostring(operation.status or "requesting")

      if status == "delivery_started" then
        -- После аварийного выключения во время физической выдачи нельзя
        -- безопасно определить, успел ли игрок получить предмет.
        manual = manual + 1

      elseif status == "adjust_needed" then
        local adjusted = SecurePurchase.adjust(
          operation.player,
          operation.transactionId,
          tonumber(operation.deliveredQty) or 0
        )

        if adjusted then
          account.balanceCoin = tonumber(adjusted.balanceCoin)
            or account.balanceCoin
            or 0
          account.balanceEma = tonumber(adjusted.balanceEma)
            or account.balanceEma
            or 0
          account.coina = trimNumber(account.balanceCoin, 4)
          account.ema = trimNumber(account.balanceEma, 4)
          SecurePurchase.removePending(operation.transactionId)
          recovered = recovered + 1
        end

      else
        local item = {
          internalName = operation.item,
          damage = tonumber(operation.damage) or 0,
          name = operation.name or operation.item,
        }

        local chargedData = operation.response
        if type(chargedData) ~= "table" then
          local chargeError
          local chargeErrorType

          chargedData, chargeError, chargeErrorType =
            SecurePurchase.charge(
              operation.player,
              item,
              tonumber(operation.qty) or 0,
              operation.transactionId
            )

          if not chargedData then
            if chargeErrorType == "server" then
              SecurePurchase.removePending(operation.transactionId)
            end
            goto continue_pending_purchase
          end
        end

        operation.status = "charged"
        operation.response = chargedData
        SecurePurchase.upsertPending(operation)

        if not component.isAvailable("me_interface") then
          goto continue_pending_purchase
        end

        local me = component.me_interface
        local qty = math.max(
          1,
          math.floor(tonumber(operation.qty) or 0)
        )

        local stock = getActualItemQuantity(item)
        local maxStackSize = getMaxStackSize(me, item)
        local hasSpace = inventoryHasSpace(item, qty, maxStackSize)

        if stock < qty or hasSpace == false then
          goto continue_pending_purchase
        end

        operation.status = "delivery_started"
        if not SecurePurchase.upsertPending(operation) then
          goto continue_pending_purchase
        end

        local extracted = MEExport.exportToPlayer(
          me,
          item,
          qty,
          maxStackSize
        )

        if extracted < qty then
          operation.status = "adjust_needed"
          operation.deliveredQty = extracted
          SecurePurchase.upsertPending(operation)

          local adjusted = SecurePurchase.adjust(
            operation.player,
            operation.transactionId,
            extracted
          )

          if adjusted then
            account.balanceCoin = tonumber(adjusted.balanceCoin)
              or account.balanceCoin
              or 0
            account.balanceEma = tonumber(adjusted.balanceEma)
              or account.balanceEma
              or 0
            account.coina = trimNumber(account.balanceCoin, 4)
            account.ema = trimNumber(account.balanceEma, 4)
            SecurePurchase.removePending(operation.transactionId)
            recovered = recovered + 1
          end
        else
          account.balanceCoin = tonumber(chargedData.balanceCoin)
            or account.balanceCoin
            or 0
          account.balanceEma = tonumber(chargedData.balanceEma)
            or account.balanceEma
            or 0
          account.transactions = tonumber(chargedData.transactions)
            or account.transactions
            or 0
          account.coina = trimNumber(account.balanceCoin, 4)
          account.ema = trimNumber(account.balanceEma, 4)
          account.trans = tostring(math.floor(account.transactions))

          SecurePurchase.finalize(
            operation.player,
            operation.transactionId
          )
          SecurePurchase.removePending(operation.transactionId)
          recovered = recovered + 1
        end
      end
    end

    ::continue_pending_purchase::
  end

  return recovered, manual
end


SecureSale = SecureSale or {}
SecureSale.url = SecurePurchase.url
SecureSale.timeout = SecurePurchase.timeout
SecureSale.pendingFile = "/home/pending_sales.json"
SecureSale.pending = SecureSale.pending or nil

function SecureSale.loadPending()
  if type(SecureSale.pending) == "table" then
    return SecureSale.pending
  end

  SecureSale.pending = {}

  -- После аварии во время атомарной замены основной файл может ещё
  -- находиться под именем .bak или .tmp.
  local candidates = {
    SecureSale.pendingFile,
    SecureSale.pendingFile .. ".bak",
    SecureSale.pendingFile .. ".tmp",
  }

  for _, path in ipairs(candidates) do
    local file = io.open(path, "r")
    if file then
      local raw = file:read("*a")
      file:close()

      local decoded = decodeJson(raw or "")
      if type(decoded) == "table" then
        SecureSale.pending = decoded

        if path ~= SecureSale.pendingFile then
          SecureSale.savePending()
        end

        return SecureSale.pending
      end
    end
  end

  return SecureSale.pending
end

function SecureSale.savePending()
  local pending = SecureSale.pending or {}

  if #pending == 0 then
    os.remove(SecureSale.pendingFile)
    os.remove(SecureSale.pendingFile .. ".tmp")
    os.remove(SecureSale.pendingFile .. ".bak")
    return true
  end

  local encoded = encodeJson(pending)
  if not encoded then return false end

  local tempPath = SecureSale.pendingFile .. ".tmp"
  local file = io.open(tempPath, "w")
  if not file then return false end

  file:write(encoded)
  file:close()

  local oldPath = SecureSale.pendingFile .. ".bak"
  os.remove(oldPath)
  os.rename(SecureSale.pendingFile, oldPath)

  if os.rename(tempPath, SecureSale.pendingFile) then
    os.remove(oldPath)
    return true
  end

  os.rename(oldPath, SecureSale.pendingFile)
  os.remove(tempPath)
  return false
end

function SecureSale.findPending(transactionId)
  local pending = SecureSale.loadPending()

  for index, operation in ipairs(pending) do
    if tostring(operation.transactionId or "") ==
        tostring(transactionId or "") then
      return operation, index
    end
  end

  return nil, nil
end

function SecureSale.queue(operation)
  local pending = SecureSale.loadPending()
  local existing, index = SecureSale.findPending(
    operation.transactionId
  )

  if existing and index then
    pending[index] = operation
  else
    pending[#pending + 1] = operation
  end

  return SecureSale.savePending()
end

function SecureSale.remove(transactionId)
  local pending = SecureSale.loadPending()
  local remaining = {}

  for _, operation in ipairs(pending) do
    if tostring(operation.transactionId or "") ~=
        tostring(transactionId or "") then
      remaining[#remaining + 1] = operation
    end
  end

  SecureSale.pending = remaining
  return SecureSale.savePending()
end

function SecureSale.credit(playerName, item, qty, transactionId)
  local response, requestError = httpPostJson(
    SecureSale.url,
    {
      action = "sell",
      name = playerName,
      item = item.internalName,
      damage = tonumber(item.damage) or 0,
      qty = qty,
      transactionId = transactionId,
    },
    SecureSale.timeout
  )

  if not response then
    return nil,
      "Нет связи с сервером начисления. "
        .. tostring(requestError or ""),
      "network"
  end

  if response.status ~= "ok" then
    return nil,
      tostring(response.message or response.error
        or "Сервер отклонил продажу"),
      "server"
  end

  return type(response.data) == "table" and response.data or response,
    nil,
    nil
end

function SecureSale.retryForPlayer(playerName)
  local pending = SecureSale.loadPending()
  if #pending == 0 then return 0, 0 end

  local completed = 0
  local manual = 0

  for _, operation in ipairs(pending) do
    if lowerText(tostring(operation.player or "")) ==
        lowerText(tostring(playerName or "")) then

      local status = tostring(operation.status or "moved")

      if status == "prepared" then
        -- Предмет мог не успеть переместиться. Автоматически начислять
        -- такую запись нельзя.
        manual = manual + 1
      else
        local item = {
          internalName = operation.item,
          damage = tonumber(operation.damage) or 0,
        }

        local data = SecureSale.credit(
          operation.player,
          item,
          tonumber(operation.qty) or 0,
          operation.transactionId
        )

        if data then
          completed = completed + 1
          account.balanceCoin = tonumber(data.balanceCoin)
            or account.balanceCoin
            or 0
          account.balanceEma = tonumber(data.balanceEma)
            or account.balanceEma
            or 0
          account.transactions = tonumber(data.transactions)
            or account.transactions
            or 0
          account.coina = trimNumber(account.balanceCoin, 4)
          account.ema = trimNumber(account.balanceEma, 4)
          account.trans = tostring(math.floor(account.transactions))
          SecureSale.remove(operation.transactionId)
        end
      end
    end
  end

  return completed, manual
end

local function updateItemStock(item, newStock)
  newStock = math.max(0, tonumber(newStock) or 0)
  item.meRaw = newStock
  item.qty = newStock
  item.me = formatQuantity(newStock)
  item.star = newStock > 0
end

AutoCraft = AutoCraft or {}
AutoCraft.timeout = 180
AutoCraft.itemWaitTimeout = 12
AutoCraft.recipeCache = AutoCraft.recipeCache or {}

-- Постоянный кэш шаблонов хранится на HDD OpenComputers.
-- В файл записываются только безопасные данные: индекс шаблона, ID предмета,
-- damage, NBT-хэш и размер выхода рецепта. Прокси-объекты AE2 в JSON не пишутся.
AutoCraft.cacheFile = "/home/autocraft_recipe_cache.json"
AutoCraft.cacheTempFile = "/home/autocraft_recipe_cache.tmp"
AutoCraft.persistentCache = AutoCraft.persistentCache or {
  version = 1,
  recipes = {},
}
AutoCraft.craftablesSnapshot = AutoCraft.craftablesSnapshot or nil

function AutoCraft.getRecipeKey(item)
  if not item then return "" end
  return table.concat({
    AutoCraft.normalizeId and AutoCraft.normalizeId(item.internalName) or tostring(item.internalName or ""),
    tostring(tonumber(item.damage) or 0),
    tostring(item.nbt_hash or item.nbtHash or ""),
  }, "|")
end

function AutoCraft.normalizeId(value)
  local id = tostring(value or "")
  if id ~= "" and not id:find(":", 1, true) then
    id = "minecraft:" .. id
  end
  return id
end

function AutoCraft.loadPersistentCache()
  local file = io.open(AutoCraft.cacheFile, "r")
  if not file then
    AutoCraft.persistentCache = {version = 1, recipes = {}}
    return false
  end

  local content = file:read("*all")
  file:close()

  local decoded = nil
  if type(content) == "string" and content ~= "" then
    decoded = select(1, decodeJson(content))
  end

  if type(decoded) == "table" and type(decoded.recipes) == "table" then
    AutoCraft.persistentCache = decoded
    AutoCraft.persistentCache.version = tonumber(decoded.version) or 1
    return true
  end

  AutoCraft.persistentCache = {version = 1, recipes = {}}
  return false
end

function AutoCraft.savePersistentCache()
  if type(AutoCraft.persistentCache) ~= "table" then
    AutoCraft.persistentCache = {version = 1, recipes = {}}
  end
  if type(AutoCraft.persistentCache.recipes) ~= "table" then
    AutoCraft.persistentCache.recipes = {}
  end

  local encoded = encodeJson(AutoCraft.persistentCache)
  if type(encoded) ~= "string" or encoded == "" then
    return false
  end

  local file = io.open(AutoCraft.cacheTempFile, "w")
  if not file then return false end
  file:write(encoded)
  file:flush()
  file:close()

  pcall(os.remove, AutoCraft.cacheFile)
  local renamed = os.rename(AutoCraft.cacheTempFile, AutoCraft.cacheFile)
  if not renamed then
    local fallback = io.open(AutoCraft.cacheFile, "w")
    if not fallback then return false end
    fallback:write(encoded)
    fallback:close()
    pcall(os.remove, AutoCraft.cacheTempFile)
  end

  return true
end

function AutoCraft.getCraftablesSnapshot(me, forceRefresh)
  if not forceRefresh and type(AutoCraft.craftablesSnapshot) == "table" then
    return AutoCraft.craftablesSnapshot, nil
  end

  local ok, craftables = pcall(me.getCraftables)
  if not ok or type(craftables) ~= "table" then
    ok, craftables = pcall(me.getCraftables, me)
  end
  if not ok or type(craftables) ~= "table" then
    return nil, "Не удалось получить шаблоны автокрафта"
  end

  AutoCraft.craftablesSnapshot = craftables
  return craftables, nil
end

function AutoCraft.callProxyMethod(object, methodName, ...)
  if object == nil then return false, nil end
  local okField, method = pcall(function() return object[methodName] end)
  if not okField or method == nil then return false, method end

  local args = {...}
  local results = {pcall(function() return method(table.unpack(args)) end)}
  local ok = table.remove(results, 1)
  if ok then return true, table.unpack(results) end

  results = {pcall(function() return method(object, table.unpack(args)) end)}
  ok = table.remove(results, 1)
  if ok then return true, table.unpack(results) end

  return false, results[1]
end

function AutoCraft.matchStack(stack, item)
  if type(stack) ~= "table" or not item then return false, 1 end

  local fingerprint = type(stack.fingerprint) == "table" and stack.fingerprint or stack
  local id = AutoCraft.normalizeId(
    fingerprint.id or fingerprint.name or stack.id or stack.name
  )
  local damage = tonumber(
    fingerprint.dmg or fingerprint.damage or stack.dmg or stack.damage
  ) or 0
  local hash = fingerprint.nbt_hash or fingerprint.nbtHash
    or stack.nbt_hash or stack.nbtHash

  local targetId = AutoCraft.normalizeId(item.internalName)
  local targetDamage = tonumber(item.damage) or 0
  local targetHash = item.nbt_hash or item.nbtHash
  local hashMatches = not targetHash
    or tostring(hash or "") == tostring(targetHash)

  local output = math.max(1, math.floor(tonumber(
    stack.size or stack.qty or stack.count or stack.amount
    or fingerprint.size or fingerprint.qty
  ) or 1))

  return id == targetId and damage == targetDamage and hashMatches, output
end

function AutoCraft.rememberRecipe(cacheKey, craftableIndex, item, output)
  if type(AutoCraft.persistentCache) ~= "table" then
    AutoCraft.persistentCache = {version = 1, recipes = {}}
  end
  if type(AutoCraft.persistentCache.recipes) ~= "table" then
    AutoCraft.persistentCache.recipes = {}
  end

  AutoCraft.persistentCache.recipes[cacheKey] = {
    index = tonumber(craftableIndex) or craftableIndex,
    internalName = AutoCraft.normalizeId(item.internalName),
    damage = tonumber(item.damage) or 0,
    nbtHash = tostring(item.nbt_hash or item.nbtHash or ""),
    output = math.max(1, tonumber(output) or 1),
    updatedAt = math.floor(computer.uptime()),
  }
  AutoCraft.savePersistentCache()
end

function AutoCraft.tryPersistentRecipe(craftables, item, cacheKey)
  local recipes = AutoCraft.persistentCache and AutoCraft.persistentCache.recipes
  local saved = type(recipes) == "table" and recipes[cacheKey] or nil
  if type(saved) ~= "table" then return nil end

  local savedIndex = tonumber(saved.index) or saved.index
  local craftable = craftables[savedIndex]
  if not craftable then return nil end

  local stackOk, stack = AutoCraft.callProxyMethod(craftable, "getItemStack")
  if not stackOk then return nil end

  local matches, output = AutoCraft.matchStack(stack, item)
  if not matches then return nil end

  local recipe = {
    craftable = craftable,
    stack = stack,
    output = output,
    persistent = true,
    index = savedIndex,
  }
  AutoCraft.recipeCache[cacheKey] = recipe
  return recipe
end

function AutoCraft.scanAndRemember(craftables, item, cacheKey)
  for craftableIndex, craftable in pairs(craftables) do
    local stackOk, stack = AutoCraft.callProxyMethod(craftable, "getItemStack")
    if stackOk and type(stack) == "table" then
      local matches, output = AutoCraft.matchStack(stack, item)
      if matches then
        local recipe = {
          craftable = craftable,
          stack = stack,
          output = output,
          persistent = false,
          index = craftableIndex,
        }
        AutoCraft.recipeCache[cacheKey] = recipe
        AutoCraft.rememberRecipe(cacheKey, craftableIndex, item, output)
        return recipe
      end
    end
  end
  return nil
end

function AutoCraft.findRecipe(me, item)
  if not me or not item then return nil, "Нет МЭ или товара" end

  local cacheKey = AutoCraft.getRecipeKey(item)
  local cached = AutoCraft.recipeCache[cacheKey]
  if cached and cached.craftable then
    return cached, nil
  end

  local craftables, craftablesError = AutoCraft.getCraftablesSnapshot(me, false)
  if not craftables then
    return nil, craftablesError or "Не удалось получить шаблоны автокрафта"
  end

  -- Быстрый путь после перезапуска: берём сохранённый индекс и проверяем
  -- только один шаблон вместо перебора всей сети.
  local persistentRecipe = AutoCraft.tryPersistentRecipe(craftables, item, cacheKey)
  if persistentRecipe then
    return persistentRecipe, nil
  end

  -- Первый игрок, выбравший этот предмет, один раз запускает полный поиск.
  -- Найденный индекс сразу записывается на HDD для всех следующих игроков.
  local recipe = AutoCraft.scanAndRemember(craftables, item, cacheKey)
  if recipe then return recipe, nil end

  -- Если шаблоны менялись во время работы магазина, обновляем список один раз
  -- и повторяем поиск. Это также автоматически чинит устаревший файл-кэш.
  craftables = select(1, AutoCraft.getCraftablesSnapshot(me, true))
  if type(craftables) == "table" then
    recipe = AutoCraft.scanAndRemember(craftables, item, cacheKey)
    if recipe then return recipe, nil end
  end

  return nil, "Шаблон автокрафта для товара не найден"
end

-- Загружаем постоянный кэш сразу при запуске магазина.
AutoCraft.loadPersistentCache()

function AutoCraft.readStatus(status, methodName)
  local ok, value = AutoCraft.callProxyMethod(status, methodName)
  if not ok then return nil end
  return value
end

local function showAutocraftError(item, message)
  transactionLock = false
  if popupState then clearPopupForReplacement() end
  popupState = {
    type = "autocraft_error",
    item = item,
    message = tostring(message or "Неизвестная ошибка автокрафта"),
  }
  presentCurrentPopup()
end

local function finalizePurchase(item, qty, craftInfo)
  if not item or qty <= 0 or currentShopMode ~= "buy" then return false end

  local actualStock = getActualItemQuantity(item)
  updateItemStock(item, actualStock)

  if actualStock < qty then
    showAutocraftError(
      item,
      "После крафта в МЭ недостаточно товара: "
        .. tostring(actualStock) .. " из " .. tostring(qty)
    )
    return false
  end

  local beforeCoin = tonumber(account.balanceCoin) or tonumber(account.coina) or 0
  local beforeEma = tonumber(account.balanceEma) or tonumber(account.ema) or 0
  local totalCoin = (tonumber(item.priceCoin) or 0) * qty
  local totalEma = (tonumber(item.priceEma) or 0) * qty

  if beforeCoin < totalCoin or beforeEma < totalEma then
    transactionLock = false
    popupState = {
      type = "insufficient",
      item = item,
      qty = qty,
      requiredCoin = totalCoin,
      requiredEma = totalEma,
      balanceCoin = beforeCoin,
      balanceEma = beforeEma,
    }
    presentCurrentPopup()
    return false
  end

  if not component.isAvailable("me_interface") then
    showAutocraftError(item, "МЭ-интерфейс не найден")
    return false
  end

  local me = component.me_interface
  local maxStackSize = getMaxStackSize(me, item)
  local hasSpace = inventoryHasSpace(item, qty, maxStackSize)
  if hasSpace == false then
    transactionLock = false
    popupState = {type="inventory_full", item=item, qty=qty}
    presentCurrentPopup()
    return false
  end

  -- КРИТИЧЕСКАЯ ЗАЩИТА:
  -- Сначала VPS атомарно проверяет цену и баланс, списывает деньги,
  -- сохраняет транзакцию и только после ответа status="ok" разрешается выдача.
  transactionLock = true
  local transactionId = SecurePurchase.createId(session.playerName)
  local purchaseOperation = {
    transactionId = transactionId,
    player = session.playerName,
    item = item.internalName,
    damage = tonumber(item.damage) or 0,
    name = item.name,
    qty = qty,
    status = "requesting",
  }

  -- Сначала записываем ID операции на HDD. При потере ответа
  -- повтор будет выполнен с тем же ID и не спишет деньги дважды.
  if not SecurePurchase.upsertPending(purchaseOperation) then
    transactionLock = false
    popupState = {
      type = "purchase_error",
      item = item,
      message = "Не удалось создать журнал покупки на HDD.",
    }
    presentCurrentPopup()
    return false
  end

  local chargedData, chargeError, chargeErrorType =
    SecurePurchase.charge(
      session.playerName,
      item,
      qty,
      transactionId
    )

  if not chargedData then
    transactionLock = false

    if chargeErrorType == "server" then
      SecurePurchase.removePending(transactionId)
    end

    popupState = {
      type = chargeErrorType == "network"
        and "network_error"
        or "purchase_error",
      item = item,
      pendingPurchase = chargeErrorType == "network",
      message = chargeError or "Не удалось подтвердить списание",
    }
    presentCurrentPopup()
    return false
  end

  purchaseOperation.status = "charged"
  purchaseOperation.response = chargedData
  SecurePurchase.upsertPending(purchaseOperation)

  local serverBeforeCoin = tonumber(chargedData.beforeCoin) or beforeCoin
  local serverBeforeEma = tonumber(chargedData.beforeEma) or beforeEma
  local serverAfterCoin = tonumber(chargedData.balanceCoin) or 0
  local serverAfterEma = tonumber(chargedData.balanceEma) or 0

  -- Деньги уже подтверждённо списаны на центральном сервере.
  -- Перед физической выдачей фиксируем состояние на HDD.
  purchaseOperation.status = "delivery_started"
  if not SecurePurchase.upsertPending(purchaseOperation) then
    transactionLock = false
    popupState = {
      type = "purchase_error",
      item = item,
      message = "Оплата подтверждена, но журнал выдачи не сохранился. "
        .. "Товар пока не выдан.",
    }
    presentCurrentPopup()
    return false
  end

  local extracted = MEExport.exportToPlayer(me, item, qty, maxStackSize)

  -- Если выдано меньше заказанного, VPS возвращает стоимость невыданной части.
  -- При extracted=0 происходит полный возврат.
  if extracted < qty then
    purchaseOperation.status = "adjust_needed"
    purchaseOperation.deliveredQty = extracted
    SecurePurchase.upsertPending(purchaseOperation)

    local adjustedData, adjustError = SecurePurchase.adjust(
      session.playerName,
      transactionId,
      extracted
    )

    if adjustedData then
      serverAfterCoin = tonumber(adjustedData.balanceCoin) or serverAfterCoin
      serverAfterEma = tonumber(adjustedData.balanceEma) or serverAfterEma
      SecurePurchase.removePending(transactionId)
    else
      -- Очень редкий случай: деньги списались, но возврат не подтвердился.
      -- Новые покупки блокируются до повторного входа, чтобы не скрыть проблему.
      transactionLock = false
      popupState = {
        type = "autocraft_error",
        item = item,
        message = "Выдано " .. tostring(extracted) .. " из " .. tostring(qty)
          .. ". Сервер возврата недоступен: " .. tostring(adjustError)
          .. ". Обратитесь к администрации.",
      }
      presentCurrentPopup()
      return false
    end
  end

  transactionLock = false

  if extracted <= 0 then
    account.balanceCoin = serverAfterCoin
    account.balanceEma = serverAfterEma
    account.coina = trimNumber(serverAfterCoin, 4)
    account.ema = trimNumber(serverAfterEma, 4)

    popupState = {
      type = "inventory_full",
      item = item,
      qty = qty,
      deliveryError = true,
    }
    presentCurrentPopup()
    return false
  end

  local chargedCoin = (tonumber(item.priceCoin) or 0) * extracted
  local chargedEma = (tonumber(item.priceEma) or 0) * extracted

  account.balanceCoin = serverAfterCoin
  account.balanceEma = serverAfterEma
  account.transactions = tonumber(chargedData.transactions)
    or (tonumber(account.transactions) or tonumber(account.trans) or 0) + 1
  account.coina = trimNumber(serverAfterCoin, 4)
  account.ema = trimNumber(serverAfterEma, 4)
  account.trans = tostring(math.floor(account.transactions))

  local newStock = getActualItemQuantity(item)
  updateItemStock(item, newStock)
  quantity = ""
  qtyFocused = false

  if popupState then clearPopupForReplacement() end

  drawVisibleItem(selectedIndex)
  drawInfoBlock()
  drawQuantitySection()
  drawAccountInfo()

  popupState = {
    type = craftInfo and "autocraft_receipt" or "receipt",
    item = item,
    qty = extracted,
    unitCoin = tonumber(item.priceCoin) or 0,
    unitEma = tonumber(item.priceEma) or 0,
    totalCoin = chargedCoin,
    totalEma = chargedEma,
    beforeCoin = serverBeforeCoin,
    beforeEma = serverBeforeEma,
    afterCoin = serverAfterCoin,
    afterEma = serverAfterEma,
    transaction = math.floor(account.transactions),
    transactionId = transactionId,
    date = os.date("%d.%m.%Y %H:%M:%S"),
    stockBefore = craftInfo and tonumber(craftInfo.stockBefore) or nil,
    missing = craftInfo and tonumber(craftInfo.missing) or nil,
    operations = craftInfo and tonumber(craftInfo.operations) or nil,
    produced = craftInfo and tonumber(craftInfo.produced) or nil,
    stockRemaining = newStock,
  }
  presentCurrentPopup()

  -- Подтверждение фактической выдачи отправляется в фоне и не задерживает GUI.
  -- Только после него VPS зеркалирует транзакцию на основной хостинг.
  if extracted >= qty then
    SecurePurchase.finalize(session.playerName, transactionId)
    SecurePurchase.removePending(transactionId)
  end

  -- Старый syncPurchase здесь намеренно НЕ вызывается:
  -- VPS уже списал баланс и записал транзакцию атомарно.
  return true
end

function AutoCraft.openConfirm(item, requestedQty, actualStock, recipe)
  local missing = math.max(0, requestedQty - actualStock)
  local output = math.max(1, tonumber(recipe.output) or 1)
  local operations = math.max(1, math.ceil(missing / output))
  local produced = operations * output

  local beforeCoin = tonumber(account.balanceCoin) or tonumber(account.coina) or 0
  local beforeEma = tonumber(account.balanceEma) or tonumber(account.ema) or 0
  local totalCoin = (tonumber(item.priceCoin) or 0) * requestedQty
  local totalEma = (tonumber(item.priceEma) or 0) * requestedQty

  if beforeCoin < totalCoin or beforeEma < totalEma then
    popupState = {
      type = "insufficient",
      item = item,
      qty = requestedQty,
      requiredCoin = totalCoin,
      requiredEma = totalEma,
      balanceCoin = beforeCoin,
      balanceEma = beforeEma,
    }
    presentCurrentPopup()
    return
  end

  if popupState then clearPopupForReplacement() end
  popupState = {
    type = "autocraft_confirm",
    item = item,
    requestedQty = requestedQty,
    stock = actualStock,
    missing = missing,
    output = output,
    operations = operations,
    produced = produced,
    surplus = math.max(0, produced - missing),
    totalCoin = totalCoin,
    totalEma = totalEma,
    recipe = recipe,
  }
  presentCurrentPopup()
end

function AutoCraft.confirm()
  if transactionLock or not popupState or popupState.type ~= "autocraft_confirm" then
    return
  end

  local data = popupState
  local item = data.item
  local requestedQty = math.max(1, math.floor(tonumber(data.requestedQty) or 0))

  if not session.active or currentShopMode ~= "buy" then
    closePopup()
    return
  end

  if not component.isAvailable("me_interface") then
    showAutocraftError(item, "МЭ-интерфейс не найден")
    return
  end

  local actualStock = getActualItemQuantity(item)
  updateItemStock(item, actualStock)

  if actualStock >= requestedQty then
    popupState = nil
    popupButtons = {}
    finalizePurchase(item, requestedQty)
    return
  end

  local missing = requestedQty - actualStock
  local me = component.me_interface

  -- Сразу показываем игроку, что нажатие принято. Поиск среди большого
  -- количества шаблонов может занять несколько секунд при первом обращении.
  popupState = {
    type = "autocraft_search",
    item = item,
    statusText = "Поиск подходящего шаблона в МЭ...",
  }
  presentCurrentPopup()

  local recipe, recipeError = AutoCraft.findRecipe(me, item)
  if not recipe then
    item.craftable = false
    showAutocraftError(item, recipeError)
    return
  end

  local output = math.max(1, tonumber(recipe.output) or 1)
  local operations = math.max(1, math.ceil(missing / output))
  local produced = operations * output

  transactionLock = true
  clearPopupForReplacement()
  popupState = {
    type = "autocraft_progress",
    item = item,
    requestedQty = requestedQty,
    stockBefore = actualStock,
    missing = missing,
    output = output,
    operations = operations,
    produced = produced,
    statusText = "Отправка задания в МЭ...",
    elapsed = 0,
    currentStock = actualStock,
  }
  presentCurrentPopup()

  local requestOk, status = AutoCraft.callProxyMethod(
    recipe.craftable,
    "request",
    operations
  )

  if not requestOk or status == nil then
    showAutocraftError(item, "МЭ не приняла задание автокрафта")
    return
  end

  local startedAt = computer.uptime()
  local finished = false
  local canceled = false

  while computer.uptime() - startedAt < AutoCraft.timeout do
    if not session.active or isPlayerStandingOnPim() == false then
      transactionLock = false
      popupState = nil
      popupButtons = {}
      return
    end

    local elapsed = math.floor(computer.uptime() - startedAt)
    local doneValue = AutoCraft.readStatus(status, "isDone")
    local canceledValue = AutoCraft.readStatus(status, "isCanceled")
    local currentStock = getActualItemQuantity(item)

    popupState.elapsed = elapsed
    popupState.currentStock = currentStock

    if canceledValue == true then
      canceled = true
      break
    elseif doneValue == true then
      finished = true
      break
    else
      popupState.statusText = "Крафт выполняется..."
      refreshCurrentPopup()
    end

    os.sleep(0.5)
  end

  if canceled then
    showAutocraftError(item, "Задание отменено МЭ-системой")
    return
  end

  if not finished then
    showAutocraftError(item, "Превышено время ожидания автокрафта")
    return
  end

  popupState.statusText = "Ожидание появления товара в МЭ..."
  refreshCurrentPopup()

  local waitStarted = computer.uptime()
  local stockAfter = getActualItemQuantity(item)
  while stockAfter < requestedQty
    and computer.uptime() - waitStarted < AutoCraft.itemWaitTimeout
  do
    stockAfter = getActualItemQuantity(item)
    popupState.currentStock = stockAfter
    refreshCurrentPopup()
    os.sleep(0.35)
  end

  updateItemStock(item, stockAfter)
  transactionLock = false

  if stockAfter < requestedQty then
    showAutocraftError(
      item,
      "Крафт завершён, но товар ещё не появился в нужном количестве"
    )
    return
  end

  popupState = nil
  popupButtons = {}
  finalizePurchase(item, requestedQty, {
    stockBefore = actualStock,
    missing = missing,
    operations = operations,
    produced = produced,
    stockAfter = stockAfter,
  })
end

local function performBuy()
  if transactionLock or popupState or currentShopMode ~= "buy" then return end

  local item = items[selectedIndex]
  local requestedQty = math.floor(tonumber(quantity) or 0)
  if not item or requestedQty <= 0 then return end

  local actualStock = getActualItemQuantity(item)
  updateItemStock(item, actualStock)

  if actualStock >= requestedQty then
    finalizePurchase(item, requestedQty)
    return
  end

  if not component.isAvailable("me_interface") then
    showAutocraftError(item, "МЭ-интерфейс не найден")
    return
  end

  local me = component.me_interface

  popupState = {
    type = "autocraft_search",
    item = item,
    statusText = "Поиск подходящего шаблона в МЭ...",
  }
  presentCurrentPopup()

  local recipe, recipeError = AutoCraft.findRecipe(me, item)
  if not recipe then
    item.craftable = false
    drawVisibleItem(selectedIndex)
    drawInfoBlock()
    drawQuantitySection()
    showAutocraftError(
      item,
      recipeError or "Для товара нет шаблона автокрафта"
    )
    return
  end

  item.craftable = true
  AutoCraft.openConfirm(item, requestedQty, actualStock, recipe)
end

function SellFlow.openSaleConfirmPopup()
  if transactionLock or popupState or currentShopMode ~= "sell" then return end
  local item = items[selectedIndex]
  if not item then return end

  local inventoryQty = SellFlow.refreshSellInventory(item, true)
  if inventoryQty <= 0 then
    drawVisibleItem(selectedIndex)
    drawInfoBlock()
    drawQuantitySection()
    return
  end

  local requestedQty = math.floor(tonumber(quantity) or 0)
  local sellQty = requestedQty > 0 and math.min(requestedQty, inventoryQty) or inventoryQty
  if sellQty <= 0 then return end

  if requestedQty > inventoryQty then
    quantity = tostring(inventoryQty)
    drawQuantitySection()
  end

  local beforeCoin = tonumber(account.balanceCoin) or tonumber(account.coina) or 0
  local beforeEma = tonumber(account.balanceEma) or tonumber(account.ema) or 0
  local unitCoin = tonumber(item.priceCoin) or 0
  local unitEma = tonumber(item.priceEma) or 0
  local totalCoin = unitCoin * sellQty
  local totalEma = unitEma * sellQty

  popupState = {
    type = "sale_confirm",
    item = item,
    inventoryQty = inventoryQty,
    sellQty = sellQty,
    unitCoin = unitCoin,
    unitEma = unitEma,
    totalCoin = totalCoin,
    totalEma = totalEma,
    beforeCoin = beforeCoin,
    beforeEma = beforeEma,
    afterCoin = beforeCoin + totalCoin,
    afterEma = beforeEma + totalEma,
  }
  presentCurrentPopup()
end

function SellFlow.confirm()
  if transactionLock
    or not popupState
    or popupState.type ~= "sale_confirm"
  then
    return
  end

  if currentShopMode ~= "sell" or not session.active then
    closePopup()
    return
  end

  local data = popupState
  local item = data.item
  local availableNow = SellFlow.scanPlayerInventoryItem(item, true)
  local sellQty = math.min(
    math.floor(data.sellQty or 0),
    availableNow
  )

  if sellQty <= 0 then
    item.inventoryQty = 0
    popupState = nil
    popupButtons = {}
    presentShopFrame()
    return
  end

  transactionLock = true

  local transactionId =
    "SELL-" .. SecurePurchase.createId(session.playerName)

  local saleOperation = {
    transactionId = transactionId,
    player = session.playerName,
    item = item.internalName,
    damage = tonumber(item.damage) or 0,
    name = item.name,
    plannedQty = sellQty,
    qty = 0,
    status = "prepared",
  }

  -- Журнал создаётся ДО перемещения предметов.
  if not SecureSale.queue(saleOperation) then
    transactionLock = false
    popupState = {
      type = "purchase_error",
      item = item,
      message = "Не удалось создать журнал продажи на HDD. "
        .. "Предметы не приняты.",
    }
    presentCurrentPopup()
    return
  end

  local moved = SellFlow.movePlayerItemToME(item, sellQty)

  if moved <= 0 then
    SecureSale.remove(transactionId)
    transactionLock = false
    item.inventoryQty = SellFlow.scanPlayerInventoryItem(item)
    popupState = nil
    popupButtons = {}
    presentShopFrame()
    return
  end

  saleOperation.qty = moved
  saleOperation.status = "moved"

  if not SecureSale.queue(saleOperation) then
    transactionLock = false
    item.inventoryQty = math.max(0, availableNow - moved)
    popupState = {
      type = "sale_pending",
      item = item,
      qty = moved,
      message = "Предметы приняты, но журнал HDD не обновился. "
        .. "Сообщите администрации ID: " .. transactionId,
    }
    presentCurrentPopup()
    return
  end

  local saleData, saleError = SecureSale.credit(
    session.playerName,
    item,
    moved,
    transactionId
  )

  transactionLock = false
  item.inventoryQty = math.max(0, availableNow - moved)
  quantity = ""
  qtyFocused = false

  if not saleData then
    popupState = {
      type = "sale_pending",
      item = item,
      qty = moved,
      message = saleError
        or "Сервер начисления временно недоступен.",
    }
    presentCurrentPopup()
    return
  end

  SecureSale.remove(transactionId)

  local beforeCoin = tonumber(saleData.beforeCoin)
    or tonumber(account.balanceCoin)
    or 0
  local beforeEma = tonumber(saleData.beforeEma)
    or tonumber(account.balanceEma)
    or 0
  local afterCoin = tonumber(saleData.balanceCoin) or beforeCoin
  local afterEma = tonumber(saleData.balanceEma) or beforeEma
  local earnedCoin = tonumber(saleData.earnedCoin)
    or (
      (tonumber(saleData.unitCoin)
        or tonumber(item.priceCoin)
        or 0)
      * moved
    )
  local earnedEma = tonumber(saleData.earnedEma)
    or (
      (tonumber(saleData.unitEma)
        or tonumber(item.priceEma)
        or 0)
      * moved
    )

  account.balanceCoin = afterCoin
  account.balanceEma = afterEma
  account.transactions = tonumber(saleData.transactions)
    or ((tonumber(account.transactions) or 0) + 1)
  account.coina = trimNumber(afterCoin, 4)
  account.ema = trimNumber(afterEma, 4)
  account.trans = tostring(math.floor(account.transactions))

  popupState = nil
  popupButtons = {}

  if not restorePopupBackground() then
    redrawShopWithoutBlanking()
  end

  drawProductList()
  resetScrollbarState()
  drawScrollbar(true)
  drawInfoBlock()
  drawQuantitySection()
  drawAccountInfo()

  popupState = {
    type = "sale_receipt",
    item = item,
    qty = moved,
    unitCoin = tonumber(saleData.unitCoin)
      or tonumber(item.priceCoin)
      or 0,
    unitEma = tonumber(saleData.unitEma)
      or tonumber(item.priceEma)
      or 0,
    totalCoin = earnedCoin,
    totalEma = earnedEma,
    beforeCoin = beforeCoin,
    beforeEma = beforeEma,
    afterCoin = afterCoin,
    afterEma = afterEma,
    transaction = tonumber(saleData.transaction)
      or math.floor(account.transactions),
    date = os.date("%d.%m.%Y %H:%M:%S"),
  }

  presentCurrentPopup()
end

local function handleClick(x, y)
  if uiState ~= "shop" or not session.active then return end
  if popupState then
    handlePopupClick(x, y)
    return
  end

  if availabilityMenuOpen then
    if x >= AVAILABILITY_MENU_X
      and x < AVAILABILITY_MENU_X + AVAILABILITY_MENU_W
      and y >= AVAILABILITY_MENU_Y
      and y < AVAILABILITY_MENU_Y + #AVAILABILITY_MENU_OPTIONS
    then
      local optionIndex = y - AVAILABILITY_MENU_Y + 1
      local option = AVAILABILITY_MENU_OPTIONS[optionIndex]
      if option then availabilityFilter = option.key end
      availabilityMenuOpen = false
      filterItems()
      presentShopFrame()
      return
    end

    availabilityMenuOpen = false
    presentShopFrame()
    return
  end

  local wasQtyFocused = qtyFocused

  if y == SEARCH_Y
    and x >= SEARCH_CLEAR_X
    and x < SEARCH_CLEAR_X + SEARCH_CLEAR_W
  then
    if searchQuery == "" then return end
    if wasQtyFocused then
      qtyFocused = false
      drawQuantitySection()
    end

    searchQuery = ""
    searchFocused = false
    Performance.searchDirty = false
    Performance.nextSearchAt = 0
    filterItems()
    redrawSearchField()
    redrawCatalogContent()
    return
  end

  if y == SEARCH_Y
    and x >= AVAILABILITY_BUTTON_X
    and x < AVAILABILITY_BUTTON_X + AVAILABILITY_BUTTON_W
  then
    if wasQtyFocused then
      qtyFocused = false
      drawQuantitySection()
    end
    searchFocused = false
    redrawSearchField()
    availabilityMenuOpen = true
    drawAvailabilityMenu()
    return
  end

  if y == SEARCH_Y
    and x >= SEARCH_X
    and x < SEARCH_X + SEARCH_W
  then
    if wasQtyFocused then
      qtyFocused = false
      drawQuantitySection()
    end

    searchFocused = true
    redrawSearchField()
    return
  end

  blurSearch()

  local fieldY = QTY_Y + 2
  if y == fieldY
    and x >= RIGHT_INNER_X
    and x < RIGHT_INNER_X + RIGHT_INNER_W
  then
    qtyFocused = true
    drawQuantitySection()
    return
  end

  if wasQtyFocused then
    qtyFocused = false
    drawQuantitySection()
  end

  if y == BOT_Y then
    if x >= BOTTOM_BUY_X and x < BOTTOM_BUY_X + BOTTOM_BUY_W then
      switchShopMode("buy")
      return
    elseif x >= BOTTOM_SELL_X and x < BOTTOM_SELL_X + BOTTOM_SELL_W then
      switchShopMode("sell")
      return
    elseif x >= BOTTOM_AUTOCRAFT_X
      and x < BOTTOM_AUTOCRAFT_X + BOTTOM_AUTOCRAFT_W
    then
      popupState = {type = "autocraft_help"}
      presentCurrentPopup()
      return
    end
  end

  -- Нажатие на дорожку скроллбара сразу переносит каталог
  -- к соответствующей позиции. Колёсико мыши продолжает работать отдельно.
  if x == SCROLL_X
    and y >= LIST_Y
    and y <= LIST_Y + LIST_H - 1
  then
    jumpToScrollbarPosition(y)
    return
  end

  if x >= LIST_X
    and x < SCROLL_X
    and y >= LIST_Y
    and y <= LIST_Y + LIST_H - 1
  then
    local row = y - LIST_Y
    local index = scrollOffset + row + 1

    if index >= 1 and index <= #items then
      selectItem(index)
    end
    return
  end

  local _, actionX, actionW, clearX, clearW = getQuantityButtonLayout()

  if y == BTN_Y and x >= actionX and x < actionX + actionW then
    local selectedItem = items[selectedIndex]
    if currentShopMode == "sell" and selectedItem then
      SellFlow.refreshSellInventory(selectedItem, false)
    end

    local selectedStock = selectedItem
      and math.max(0, math.floor(tonumber(selectedItem.meRaw or selectedItem.qty) or 0))
      or 0
    local buyUnavailable = currentShopMode == "buy"
      and (not selectedItem
        or (selectedStock <= 0 and selectedItem.craftable ~= true))
    local sellUnavailable = currentShopMode == "sell"
      and (not selectedItem
        or (tonumber(selectedItem.inventoryQty) or 0) <= 0)
    local buyQuantityMissing = currentShopMode == "buy"
      and math.floor(tonumber(quantity) or 0) <= 0

    -- Покупка разрешена при достаточном остатке или при наличии шаблона
    -- автокрафта. В режиме продажи предмет должен находиться у игрока.
    if buyUnavailable or sellUnavailable or buyQuantityMissing then
      if sellUnavailable then
        drawInfoBlock()
        drawQuantitySection()
      end
      return
    end

    if currentShopMode == "buy" then
      performBuy()
    else
      -- openSaleConfirmPopup выполняет одну обязательную свежую проверку.
      SellFlow.openSaleConfirmPopup()
    end
    return
  end

  if y == BTN_Y and x >= clearX and x < clearX + clearW then
    if quantity == "" then return end
    quantity = ""
    drawQuantitySection()
  end
end

function ModemRPC.processPushes()
  local message=ModemRPC.popPush()
  while message do
    local action=tostring(message.action or "")
    local data=type(message.data)=="table" and message.data or {}
    if action=="maintenance_changed" then
      ModemRPC.globalMaintenance=data.maintenance==true
      Maintenance.setActive(ModemRPC.globalMaintenance or ModemRPC.terminalPaused,false)
    elseif action=="terminal_paused" then
      ModemRPC.terminalPaused=true Maintenance.setActive(true,false)
    elseif action=="terminal_resumed" then
      ModemRPC.terminalPaused=false Maintenance.setActive(ModemRPC.globalMaintenance,false)
    elseif action=="user_banned" then
      local target=data.player
      local current=session.active and session.playerName or BanSystem.blockedPlayer
      if current and BanSystem.samePlayer(current,target) then
        local user=type(data.user)=="table" and data.user or data
        BanSystem.blockPlayer(target,{banned=true,reason=user.banReason or data.reason,duration=user.banDuration or data.duration,admin=user.bannedBy or data.admin,date=user.bannedAt or data.date},true)
      end
    elseif action=="user_unbanned" then
      if BanSystem.blockedPlayer and BanSystem.samePlayer(BanSystem.blockedPlayer,data.player) then BanSystem.clear(true,false) end
    elseif action=="user_updated" then
      local user=type(data.user)=="table" and data.user or {}
      if session.active and BanSystem.samePlayer(session.playerName,data.player) then
        account.balanceCoin=tonumber(user.balanceCoin) or account.balanceCoin or 0
        account.balanceEma=tonumber(user.balanceEma) or account.balanceEma or 0
        account.transactions=tonumber(user.transactions) or account.transactions or 0
        account.coina=trimNumber(account.balanceCoin,4)
        account.ema=trimNumber(account.balanceEma,4)
        account.trans=tostring(math.floor(account.transactions))
        if uiState=="shop" then drawAccountInfo() end
      end
    elseif action=="catalog_updated" then
      local kind=tostring(data.catalog or "buy")
      local meta=ModemRPC.loadMeta()
      if kind=="sell" then
        sellItemsCache=nil meta.sellVersion=-1 Performance.sellCatalogLoadedAt=0
        if ModemRPC.sessionData then ModemRPC.sessionData.sellVersion=tonumber(data.version) or 0 end
      else
        buyItemsCache=nil meta.buyVersion=-1 Performance.buyCatalogLoadedAt=0
        if ModemRPC.sessionData then ModemRPC.sessionData.buyVersion=tonumber(data.version) or 0 end
      end
      ModemRPC.saveMeta()
      if session.active and uiState=="shop" and not transactionLock and ((kind=="sell" and currentShopMode=="sell") or (kind~="sell" and currentShopMode=="buy")) then
        loadItemsForCurrentMode(true) filterItems() selectedIndex=#items>0 and 1 or 0 scrollOffset=0 presentShopFrame(true)
      end
    end
    message=ModemRPC.popPush()
  end
end

function ModemRPC.heartbeat(now)
  now = tonumber(now) or computer.uptime()
  if now < ModemRPC.nextHeartbeat then return end
  ModemRPC.nextHeartbeat = now + ModemRPC.heartbeatInterval

  local ok, response = pcall(
    ModemRPC.request,
    {action = "heartbeat"},
    1.25
  )

  if not ok or type(response) ~= "table"
    or response.status ~= "ok"
    or type(response.data) ~= "table"
  then
    return
  end

  local data = response.data
  local newMaintenance = data.maintenance == true
  local newPaused = data.terminalPaused == true

  if newMaintenance ~= ModemRPC.globalMaintenance then
    ModemRPC.queuePush("maintenance_changed", {
      maintenance = newMaintenance,
    })
  end

  if newPaused ~= ModemRPC.terminalPaused then
    ModemRPC.queuePush(
      newPaused and "terminal_paused" or "terminal_resumed",
      {paused = newPaused}
    )
  end

  local sessionData = ModemRPC.sessionData
  if type(sessionData) == "table" then
    if tonumber(data.buyVersion)
      and tonumber(data.buyVersion) ~= tonumber(sessionData.buyVersion)
    then
      ModemRPC.queuePush("catalog_updated", {
        catalog = "buy",
        version = tonumber(data.buyVersion),
      })
    end

    if tonumber(data.sellVersion)
      and tonumber(data.sellVersion) ~= tonumber(sessionData.sellVersion)
    then
      ModemRPC.queuePush("catalog_updated", {
        catalog = "sell",
        version = tonumber(data.sellVersion),
      })
    end
  end
end

term.clear()
resetAccount()
ModemRPC.discoveredServer=ModemRPC.discover(4)
if ModemRPC.discoveredServer then pcall(ModemRPC.request,{action="hello"},3) end
Maintenance.bootstrap()
BanSystem.bootstrap()

if Maintenance.active then
  uiState = "maintenance"
  Maintenance.draw(true)
else
  uiState = "idle"
  drawIdleScreen()
end

-- Если программа запущена, когда игрок уже стоит на PIM и компонент умеет
-- вернуть имя, сразу запускаем двухсекундную авторизацию. В режиме
-- технических работ вход намеренно не создаётся.
do
  if not Maintenance.active then
    local initialPlayer = getPlayerOnPim()
    if initialPlayer and isPlayerStandingOnPim() == true then
      createSession(initialPlayer)
    end
  end
end

while true do
  local ev = safeEventPull(0.25)
  local name = ev[1]

  if name == "player_on" or name == "pim" or name == "pim_player_enter" then
    if Maintenance.active then
      Maintenance.draw(false)
    elseif BanSystem.blockedPlayer then
      BanSystem.draw(false)
    else
      local playerName = extractPlayerNameFromEvent(ev)
      if playerName and not session.active then
        createSession(playerName)
      end
    end

  elseif name == "player_off" or name == "pim_player_leave" then
    -- Само событие означает, что игрок сошёл с PIM. Не ждём старого ника
    -- или обновления прокси: сразу закрываем сессию и очищаем SELECTOR.
    if BanSystem.blockedPlayer then
      BanSystem.clear(false, false)
    elseif session.active then
      destroySession()
    end

  elseif name == "modem_message" then
    ModemRPC.acceptPushEvent(ev)

  elseif name == "touch" then
    Performance.markInput()
    if uiState == "shop" and session.active then
      if not isPimOwner(ev[6] or "Неизвестный") then
        writeDebugLog("⚠️ Коснулся не владелец: " .. tostring(ev[6] or "Неизвестный") .. ", игнорируем")
      else
        handleClick(ev[3], ev[4])
      end
    end

  elseif name == "scroll" then
    Performance.markInput()
    if uiState == "shop" and session.active and not popupState then
      if not isPimOwner(ev[6] or "Неизвестный") then
        writeDebugLog("⚠️ Прокрутил не владелец: " .. tostring(ev[6] or "Неизвестный") .. ", игнорируем")
      else
        local x, direction = ev[3], ev[5]
        if x >= LIST_X and x < SCROLL_X then
          Performance.queueScroll(-direction)
        end
      end
    end

  elseif name == "key_down" then
    Performance.markInput()
    if not session.active then
      -- Пока PIM-сессии нет, клавиатура полностью заблокирована.
    elseif not isPimOwner(ev[5] or "Неизвестный") then
      writeDebugLog("⚠️ Нажал клавишу не владелец: " .. tostring(ev[5] or "Неизвестный") .. ", игнорируем")
    else
      local char, code = ev[3], ev[4]

      if popupState then
        if code == keyboard.keys.escape then
          closePopup()
        elseif code == keyboard.keys.enter then
          if popupState.type == "sale_confirm" and SellFlow.confirm then
            SellFlow.confirm()
          else
            closePopup()
          end
        end
      elseif uiState == "shop" then
        if searchFocused then
          if code == keyboard.keys.escape then
            Performance.applySearchNow()
            searchFocused = false
            redrawSearchField()
          elseif code == keyboard.keys.enter or code == keyboard.keys.tab then
            Performance.applySearchNow()
            searchFocused = false
            redrawSearchField()
          elseif code == keyboard.keys.back then
            -- На пустом поле Backspace ничего не делает: каталог больше
            -- не перерисовывается и не моргает без причины.
            if searchQuery ~= "" then
              searchQuery = unicode.sub(searchQuery, 1, -2)
              redrawSearchField()
              Performance.scheduleSearch()
            end
          elseif char and char >= 32 then
            if unicode.len(searchQuery) < SEARCH_W - 4 then
              searchQuery = searchQuery .. unicode.char(char)
              redrawSearchField()
              Performance.scheduleSearch()
            end
          end

        elseif qtyFocused then
          if code == keyboard.keys.escape then
            qtyFocused = false
            drawQuantitySection()
          elseif code == keyboard.keys.enter or code == keyboard.keys.tab then
            qtyFocused = false
            drawQuantitySection()
          elseif code == keyboard.keys.back then
            quantity = unicode.sub(quantity, 1, -2)
            drawQuantitySection()
          elseif char and char >= 48 and char <= 57 then
            if unicode.len(quantity) < 8 then
              appendQuantityDigit(char)
              drawQuantitySection()
            end
          end

        else
          if code == keyboard.keys.up then
            selectItem(selectedIndex - 1)
          elseif code == keyboard.keys.down then
            selectItem(selectedIndex + 1)
          end
          -- Escape вне поля или POPUP намеренно ничего не делает: экран заблокирован.
        end
      end
    end
  end

  ModemRPC.processPushes()
  ModemRPC.heartbeat(computer.uptime())

  -- Через две секунды запускается загрузка каталога и аккаунта.
  -- Сам магазин откроется только после завершения загрузки, поэтому
  -- товары будут видны сразу при первом кадре интерфейса.
  local now = computer.uptime()

  -- Несколько быстрых событий колеса объединяются в один GPU-сдвиг.
  if Performance.applyPendingScroll(now) then
    now = computer.uptime()
  end

  -- Фильтрация выполняется один раз после короткой паузы ввода.
  if Performance.searchDirty
    and now >= Performance.nextSearchAt
    and uiState == "shop"
    and session.active
  then
    Performance.applySearchNow()
    now = computer.uptime()
  end

  -- HTTP-проверки больше не останавливают скролл или набор текста.
  Performance.idleFor =
    now - (Performance.lastInputAt or 0)

  if Performance.idleFor >= Performance.networkIdleDelay
    and not transactionLock
    and not searchFocused
    and not qtyFocused
  then
    Maintenance.poll(now)
    now = computer.uptime()
    BanSystem.poll(now)
    now = computer.uptime()
  end

  if Maintenance.active then
    Maintenance.draw(false)
  elseif BanSystem.blockedPlayer then
    BanSystem.draw(false)

    -- Некоторые сборки не присылают player_off. Проверяем PIM и снимаем
    -- экран блокировки сразу после ухода заблокированного игрока.
    if now - lastPimCheck >= PIM_CHECK_INTERVAL then
      lastPimCheck = now
      if isPlayerStandingOnPim() == false then
        BanSystem.clear(false, false)
      end
    end
  else
    if (uiState == "idle" or uiState == "auth") and type(animateWelcomeFrame) == "function" then
      animateWelcomeFrame(now)
    end

    if uiState == "auth" and authDeadline and now >= authDeadline then
      finishAuthorization()
      now = computer.uptime()
    end

    -- Резервная проверка присутствия нужна для сборок, где player_off
    -- иногда не приходит, но getInventorySize меняется с 40 на 0.
    if now - lastPimCheck >= PIM_CHECK_INTERVAL then
      lastPimCheck = now

      if session.active then
        if isPlayerStandingOnPim() == false then
          destroySession()
        end
      else
        -- Методы имени могут возвращать старый ник после ухода. Новую сессию
        -- создаём только когда датчик присутствия действительно показывает PIM.
        if isPlayerStandingOnPim() == true then
          local detectedPlayer = getPlayerOnPim()
          if detectedPlayer then
            createSession(detectedPlayer)
          end
        end
      end
    end
  end
end

clearSelector()
term.clear()
gpu.setForeground(0xFFFFFF)
gpu.setBackground(0x000000)
