local component = require("component")
local event = require("event")
local serialization = require("serialization")
local filesystem = require("filesystem")

local modem = component.modem
modem.open(0xffef)
modem.open(0xfffe)

-- ========== ANSI ЦВЕТА (безопасные последовательности) ==========
local ansi = {
    reset   = "\27[0m",
    bold    = "\27[1m",
    red     = "\27[31m",
    green   = "\27[32m",
    yellow  = "\27[33m",
    blue    = "\27[34m",
    magenta = "\27[35m",
    cyan    = "\27[36m",
    white   = "\27[37m",
    bg_black   = "\27[40m",
    bg_blue    = "\27[44m",
    clear   = "\27[2J\27[H",
    hide_cursor = "\27[?25l",
    show_cursor = "\27[?25h"
}

local function setColor(fg, bg)
    io.write(fg or "")
    if bg then io.write(bg) end
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
    if raw and #raw > 0 then
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
local marketConnected = false
local logBuffer = {}
local LOG_LINES = 14

local function addLog(text, fg)
    table.insert(logBuffer, {text = text, color = fg or ansi.white})
    if #logBuffer > LOG_LINES then table.remove(logBuffer, 1) end
end

-- ========== ОТРИСОВКА ИНТЕРФЕЙСА ==========
function drawInterface()
    io.write(ansi.hide_cursor .. ansi.clear)
    
    -- Верхняя панель
    setColor(ansi.bg_blue, ansi.white)
    local title = " PIM MARKET SERVER – СТАТУС: " .. (marketConnected and "АКТИВЕН" or "ОЖИДАНИЕ MARKET")
    io.write("\27[2;1H" .. string.rep(" ", 78))
    io.write("\27[2;1H" .. title .. string.rep(" ", 78 - #title))
    resetColor()
    
    -- Часы и статистика
    setColor(ansi.cyan)
    io.write("\27[3;1HВремя: " .. os.date("%H:%M:%S"))
    local activeCount = 0
    for _, v in pairs(sessions) do
        if type(v) == "table" and v.token then activeCount = activeCount + 1 end
    end
    io.write("\27[3;40HАктивных сессий: " .. activeCount)
    resetColor()
    
    -- Разделитель
    setColor(ansi.white)
    io.write("\27[4;1H" .. string.rep("─", 78))
    resetColor()
    
    -- Заголовки столбцов
    local colX = {5, 30, 55}
    local titles = {"👥 ИГРОКИ", "📦 ME СИСТЕМА", "🔒 БЕЗОПАСНОСТЬ"}
    setColor(ansi.bold, ansi.yellow)
    for i=1,3 do
        io.write(string.format("\27[5;%dH%-*s", colX[i], 24, titles[i]))
    end
    resetColor()
    
    -- 1) Игроки
    setColor(ansi.green)
    local playerList = {}
    for name, s in pairs(sessions) do
        if type(s) == "table" and s.token then
            table.insert(playerList, name)
        end
    end
    for i=1, math.min(12, #playerList) do
        io.write(string.format("\27[%d;%dH%s", 5+i, colX[1], playerList[i]))
    end
    resetColor()
    
    -- 2) ME система (заглушка, можно расширить)
    setColor(ansi.cyan)
    io.write(string.format("\27[6;%dHДанные ME не доступны", colX[2]))
    io.write(string.format("\27[7;%dH(требуется компонент)", colX[2]))
    resetColor()
    
    -- 3) Безопасность
    setColor(ansi.magenta)
    io.write(string.format("\27[6;%dHЛимит сессии: %d сек", colX[3], SESSION_TIMEOUT))
    local playersCount = 0
    for _ in pairs(players) do playersCount = playersCount + 1 end
    io.write(string.format("\27[7;%dHИгроков в БД: %d", colX[3], playersCount))
    resetColor()
    
    -- Область логов
    setColor(ansi.white)
    io.write(string.format("\27[19;1H" .. string.rep("─", 78)))
    resetColor()
    for i=1, #logBuffer do
        local entry = logBuffer[i]
        setColor(entry.color)
        local line = entry.text
        if #line > 77 then line = line:sub(1, 77) end
        io.write(string.format("\27[%d;1H%-78s", 19+i, line))
        resetColor()
    end
    io.flush()
end

local function updateInterface()
    drawInterface()
end

-- ========== ОСНОВНАЯ ЛОГИКА ==========
local function log(level, msg)
    local color = ansi.white
    if level == "INFO" then color = ansi.green
    elseif level == "WARN" then color = ansi.yellow
    elseif level == "ERROR" then color = ansi.red end
    addLog("[" .. os.date("%H:%M:%S") .. "] [" .. level .. "] " .. msg, color)
    updateInterface()
end

local function getOrCreatePlayer(name)
    if not players[name] then
        local realDate = getRealTime()
        players[name] = {
            balance = 0.0, resBalance = 0.0, transactions = 0,
            regDate = realDate, agreed = false
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

-- Запускаем таймер для обновления экрана каждую секунду
event.timer(1, function() updateInterface() end, math.huge)

log("INFO", "Сервер запущен. Ожидание терминалов...")
updateInterface()

while true do
    local ev = {event.pull(0.5)}
    local etype = ev[1]

    if etype == "modem_message" then
        local from = ev[3]
        local raw = ev[6]
        local success, msg = pcall(serialization.unserialize, raw)
        if not success or not msg or type(msg) ~= "table" then
            goto continue
        end

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
            updateInterface()

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
            updateInterface()

        elseif msg.op == "getAccount" then
            if not validateSession(msg.name, msg.token) then
                log("WARN", "Неверный токен для getAccount от " .. (msg.name or "?"))
                modem.send(from, 0xffef, serialization.serialize({
                    op="accountData", error = true, message = "Токен устарел"
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
                    resBalance = player.resBalance,
                    transactions = player.transactions,
                    regDate = player.regDate,
                    agreed = player.agreed
                }
            }))
            log("INFO", "Аккаунт отправлен для " .. msg.name)

        elseif msg.op == "selector_status" then
            log("INFO", string.format("Selector status от %s: %s", msg.name or "?", msg.available and "подключён" or "не найден"))

        elseif msg.op == "scan_report" then
            if not validateSession(msg.name, msg.token) then
                log("WARN", "Неверный токен для scan_report")
                goto continue
            end
            log("INFO", string.format("🔍 %s сканирует '%s': найдено %d шт.", msg.name, msg.target, msg.found or 0))

        elseif msg.op == "sell" then
            if not validateSession(msg.name, msg.token) then
                log("WARN", "Неверный токен для sell")
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
            log("INFO", string.format("💰 %s пополнил %s: предмет '%s' x%d на сумму %.2f", msg.name, currency, msg.item, qty, value))

        elseif msg.op == "buy" then
            if not validateSession(msg.name, msg.token) then
                log("WARN", "Неверный токен для buy")
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
            log("INFO", string.format("🛒 %s купил %s x%d за %.2f %s", msg.name, msg.item, msg.qty, value, currency))

        elseif msg.op == "new_items" then
            if not validateSession(msg.name, msg.token) then
                log("WARN", "Неверный токен для new_items")
                goto continue
            end
            for _, item in ipairs(msg.items or {}) do
                log("INFO", "🆕 Новый предмет: " .. item.name .. " (x" .. item.qty .. ")")
            end

        elseif msg.op == "report" then
            if not validateSession(msg.name, msg.token) then
                log("WARN", "Неверный токен для report")
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
                log("ERROR", "❌ Не удалось открыть reports.log")
            end

        elseif msg.op == "agree" then
            if not validateSession(msg.name, msg.token) then
                log("WARN", "Неверный токен для agree")
                modem.send(from, 0xffef, serialization.serialize({ op="agree", error = true, message = "Токен устарел" }))
                goto continue
            end
            local player = players[msg.name]
            if player then
                player.agreed = true
                saveDB()
                sessions[msg.name].lastAction = os.time()
                log("INFO", "📝 " .. msg.name .. " принял пользовательское соглашение")
                modem.send(from, 0xffef, serialization.serialize({ op = "agree", success = true, agreed = true }))
            else
                modem.send(from, 0xffef, serialization.serialize({ op = "agree", error = true, message = "Игрок не найден" }))
            end
        end
    end
    ::continue::
end
