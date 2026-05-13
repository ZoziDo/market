local component = require("component")
local event = require("event")
local serialization = require("serialization")
local filesystem = require("filesystem")

local modem = component.modem
modem.open(0xffef)
modem.open(0xfffe)

-- ========== ANSI ЦВЕТА И ОФОРМЛЕНИЕ ==========
local ansi = {
    reset   = "\27[0m",
    bold    = "\27[1m",
    black   = "\27[30m",
    red     = "\27[31m",
    green   = "\27[32m",
    yellow  = "\27[33m",
    blue    = "\27[34m",
    magenta = "\27[35m",
    cyan    = "\27[36m",
    white   = "\27[37m",
    bg_black   = "\27[40m",
    bg_red     = "\27[41m",
    bg_green   = "\27[42m",
    bg_yellow  = "\27[43m",
    bg_blue    = "\27[44m",
    bg_magenta = "\27[45m",
    bg_cyan    = "\27[46m",
    bg_white   = "\27[47m",
    clear   = "\27[2J\27[H",
    hide_cursor = "\27[?25l",
    show_cursor = "\27[?25h"
}

local function setColor(fg, bg)
    local s = ""
    if fg then s = s .. fg end
    if bg then s = s .. bg end
    io.write(s)
end

local function resetColor()
    io.write(ansi.reset)
end

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

-- ========== РЕАЛЬНОЕ ВРЕМЯ ==========
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
local marketConnected = false      -- подключён ли клиент market_01
local logBuffer = {}               -- храним последние сообщения логов
local LOG_LINES = 14               -- сколько строк лога показывать

function addLog(text, fg, bg)
    table.insert(logBuffer, {text=text, fg=fg or ansi.white, bg=bg})
    if #logBuffer > LOG_LINES then table.remove(logBuffer, 1) end
end

-- ========== ОТРИСОВКА ИНТЕРФЕЙСА ==========
function drawInterface()
    -- Скрываем курсор и очищаем экран
    io.write(ansi.hide_cursor .. ansi.clear)
    
    -- Верхняя панель
    setColor(ansi.bg_blue, ansi.white)
    local title = " PIM MARKET SERVER – СТАТУС: " .. (marketConnected and "АКТИВЕН" or "ОЖИДАНИЕ MARKEТ")
    local status = marketConnected and ansi.green or ansi.red
    io.write("\27[2;1H") -- строка 2, колонка 1
    io.write(string.rep(" ", 78))
    io.write("\27[2;1H" .. title .. string.rep(" ", 78 - #title))
    resetColor()
    
    -- Часы и статистика сессий
    setColor(ansi.cyan)
    io.write("\27[3;1HВремя: " .. os.date("%H:%M:%S"))
    io.write("\27[3;40HАктивных сессий: " .. #sessions)
    resetColor()
    
    -- Разделитель
    setColor(ansi.bg_black, ansi.white)
    io.write("\27[4;1H" .. string.rep("─", 78))
    resetColor()
    
    -- 3 столбца
    local colWidth = 25
    local colX = {5, 30, 55}
    local titles = {"👥 ИГРОКИ", "📦 ME СИСТЕМА", "🔒 БЕЗОПАСНОСТЬ"}
    setColor(ansi.bold, ansi.yellow)
    for i=1,3 do
        io.write(string.format("\27[5;%dH%-*s", colX[i], colWidth, titles[i]))
    end
    resetColor()
    
    -- Содержимое столбцов
    -- 1) Игроки (список из сессий)
    setColor(ansi.green)
    local y = 6
    local playerList = {}
    for name, s in pairs(sessions) do
        if type(s) == "table" and s.token then
            table.insert(playerList, name)
        end
    end
    for i=1, math.min(12, #playerList) do
        io.write(string.format("\27[%d;%dH%s", y+i-1, colX[1], playerList[i]))
    end
    resetColor()
    
    -- 2) ME система (пока заглушка, можно добавить реальное количество предметов из интерфейса)
    setColor(ansi.cyan)
    io.write(string.format("\27[6;%dHДанные MЭ не доступны", colX[2]))
    io.write(string.format("\27[7;%dH(необходим доп. компонент)", colX[2]))
    resetColor()
    
    -- 3) Безопасность (последние события, блокировки)
    setColor(ansi.magenta)
    io.write(string.format("\27[6;%dHЛимит сессии: %d сек", colX[3], SESSION_TIMEOUT))
    io.write(string.format("\27[7;%dHВсего игроков в БД: %d", colX[3], table.getn(players)))
    resetColor()
    
    -- Область логов (последние LOG_LINES строк)
    setColor(ansi.bg_black, ansi.white)
    io.write(string.format("\27[%d;1H" .. string.rep("─", 78), 19)) -- линия над логами
    resetColor()
    local logStartY = 20
    for i, logEntry in ipairs(logBuffer) do
        local fg = logEntry.fg or ansi.white
        local bg = logEntry.bg or ansi.bg_black
        setColor(fg, bg)
        local line = logEntry.text
        if #line > 77 then line = line:sub(1, 77) end
        io.write(string.format("\27[%d;1H%-78s", logStartY + i - 1, line))
        resetColor()
    end
    resetColor()
    io.flush()
end

local lastDraw = 0
local function updateInterface(force)
    if force or os.clock() - lastDraw >= 1 then
        drawInterface()
        lastDraw = os.clock()
    end
end

-- ========== ОСНОВНАЯ ЛОГИКА СЕРВЕРА ==========
local function log(level, msg)
    local color = ansi.white
    if level == "INFO" then color = ansi.green
    elseif level == "WARN" then color = ansi.yellow
    elseif level == "ERROR" then color = ansi.red end
    addLog("[" .. os.date("%H:%M:%S") .. "] [" .. level .. "] " .. msg, color)
    updateInterface(true)
end

local function getOrCreatePlayer(name)
  if not players[name] then
    local realDate = getRealTime()
    players[name] = {
      balance = 0.0,
      resBalance = 0.0,
      transactions = 0,
      regDate = realDate,
      agreed = false
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

-- Основной цикл обработки событий (без бесконечного опроса, используется event.pull с таймером для отрисовки)
log("INFO", "Сервер запущен. Ожидание терминалов...")
updateInterface(true)

while true do
    local ev = {event.pull(0.5)}
    local etype = ev[1]

    if etype == "timer" then
        updateInterface(false)
    elseif etype == "modem_message" then
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
            marketConnected = true
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
                balance=player.balance or 0.0,
                resBalance=player.resBalance or 0.0,
                transactions=player.transactions,
                regDate=player.regDate,
                agreed = player.agreed or false
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
                    balance = player.balance or 0.0,
                    resBalance = player.resBalance or 0.0,
                    transactions = player.transactions,
                    regDate = player.regDate,
                    agreed = player.agreed or false
                }
            }))
            log("INFO", "Аккаунт отправлен для " .. msg.name)

        elseif msg.op == "selector_status" then
            log("INFO", string.format("Selector status от %s: %s", msg.name or "?", msg.available and "подключён" or "не найден"))

        elseif msg.op == "scan_report" then
            if not validateSession(msg.name, msg.token) then
                log("WARN", "Неверный токен для scan_report от " .. (msg.name or "?"))
                goto continue
            end
            log("INFO", string.format("🔍 %s сканирует '%s': найдено %d шт.", msg.name, msg.target, msg.found or 0))

        elseif msg.op == "sell" then
            if not validateSession(msg.name, msg.token) then
                log("WARN", "Неверный токен для sell от " .. (msg.name or "?"))
                goto continue
            end
            local player = players[msg.name]
            if not player then goto continue end
            local qty = tonumber(msg.qty) or 0
            local value = tonumber(msg.value) or 0
            local currency = msg.currency or "em"

            if currency == "em" then
                player.balance = (player.balance or 0) + value
            else
                player.resBalance = (player.resBalance or 0) + value
            end
            player.transactions = (player.transactions or 0) + 1
            sessions[msg.name].lastAction = os.time()
            saveDB()
            log("INFO", string.format("💰 %s пополнил %s: предмет '%s' x%d на сумму %.2f. Баланс Эмов: %.2f, Ресов: %.2f",
                msg.name, currency, msg.item, qty, value, player.balance or 0, player.resBalance or 0))

        elseif msg.op == "buy" then
            if not validateSession(msg.name, msg.token) then
                log("WARN", "Неверный токен для buy от " .. (msg.name or "?"))
                goto continue
            end
            local player = players[msg.name]
            if not player then goto continue end
            local value = tonumber(msg.value) or 0
            local currency = msg.currency or "res"
            if currency == "em" then
                player.balance = (player.balance or 0) - value
            else
                player.resBalance = (player.resBalance or 0) - value
            end
            player.transactions = (player.transactions or 0) + 1
            sessions[msg.name].lastAction = os.time()
            saveDB()
            log("INFO", string.format("🛒 %s купил %s x%d за %.2f %s. Баланс Эмов: %.2f, Ресов: %.2f",
                msg.name, msg.item, msg.qty, value, currency, player.balance or 0, player.resBalance or 0))

        elseif msg.op == "new_items" then
            if not validateSession(msg.name, msg.token) then
                log("WARN", "Неверный токен для new_items от " .. (msg.name or "?"))
                goto continue
            end
            for _, item in ipairs(msg.items or {}) do
                log("INFO", "🆕 Новый предмет: " .. item.name .. " (x" .. item.qty .. ")")
            end

        elseif msg.op == "report" then
            if not validateSession(msg.name, msg.token) then
                log("WARN", "Неверный токен для report от " .. (msg.name or "?"))
                goto continue
            end
            log("INFO", "📩 Репорт от " .. msg.name .. " (" .. msg.time .. ")")
            log("INFO", "   Текст: " .. (msg.text or ""))
            local file = io.open("/home/reports.log", "a")
            if file then
                file:write("[" .. msg.time .. "] " .. msg.name .. ": " .. msg.text .. "\n")
                file:close()
                log("INFO", "✅ Сохранено в reports.log")
            else
                log("ERROR", "❌ Не удалось открыть reports.log для записи")
            end

        elseif msg.op == "agree" then
            if not validateSession(msg.name, msg.token) then
                log("WARN", "Неверный токен для agree от " .. (msg.name or "?"))
                modem.send(from, 0xffef, serialization.serialize({ op="agree", error = true, message = "Токен устарел" }))
                goto continue
            end
            local player = players[msg.name]
            if player then
                player.agreed = true
                saveDB()
                sessions[msg.name].lastAction = os.time()
                log("INFO", "📝 " .. msg.name .. " принял пользовательское соглашение")
                modem.send(from, 0xffef, serialization.serialize({
                    op = "agree",
                    success = true,
                    agreed = true
                }))
            else
                modem.send(from, 0xffef, serialization.serialize({ op = "agree", error = true, message = "Игрок не найден" }))
            end
        end
    end
    ::continue::
end
