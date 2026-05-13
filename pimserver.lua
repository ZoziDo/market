local component = require("component")
local event = require("event")
local serialization = require("serialization")
local filesystem = require("filesystem")
local gpu = component.gpu
local math = require("math")
local os = require("os")

local modem = component.modem
modem.open(0xffef)
modem.open(0xfffe)

-- ========== ANSI ЦВЕТА ==========
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

-- ========== ПАРОЛЬ ДЛЯ ПОДКЛЮЧЕНИЯ ==========
local ACCESS_PASSWORD = "secret"

-- ========== БАЗА ДАННЫХ ИГРОКОВ ==========
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

-- ========== ГЛОБАЛЬНАЯ СТАТИСТИКА ==========
local STATS_PATH = "/home/global_stats.db"
local globalStats = {
    totalReports = 0,
    totalBuys = 0,
    totalSells = 0
}
if filesystem.exists(STATS_PATH) then
    local file = io.open(STATS_PATH, "r")
    local raw = file:read("*a")
    file:close()
    if raw and #raw > 0 then
        local success, data = pcall(serialization.unserialize, raw)
        if success and data then
            globalStats.totalReports = data.totalReports or 0
            globalStats.totalBuys = data.totalBuys or 0
            globalStats.totalSells = data.totalSells or 0
        end
    end
end

local function saveGlobalStats()
    local file = io.open(STATS_PATH, "w")
    file:write(serialization.serialize(globalStats))
    file:close()
end

-- ========== ПЕРЕМЕННЫЕ СЕРВЕРА ==========
local owner = nil
local sessions = {}
local SESSION_TIMEOUT = 31536000  -- 1 год
local marketConnected = false
local logBuffer = {}
local shopPaused = false
local adminMode = false
local adminPlayerList = {}
local adminScroll = 0
local selectedAdminIndex = 1
local adminViewHeight = 20

-- Кеш для ME статистики
local cachedMeTotal = "Загрузка..."
local cachedMeUnique = "Загрузка..."
local meStatsTimer = nil

-- График активности
local ACTIVITY_SIZE = 60
local activityBuffer = {}
for i=1, ACTIVITY_SIZE do activityBuffer[i] = 0 end
local activityIndex = 0

-- Размеры экрана
local screenW, screenH = 80, 25
local colX = {5, 30, 55, 80}
local colWidth = 25
local logStartY = 20
local maxLogLines = 14

-- Имя админа и текущий игрок на PIM
local ADMIN_NAME = "ZoziDo"
local currentPIMPlayer = nil   -- кто сейчас стоит на PIM

-- ========== ФУНКЦИИ ОБНОВЛЕНИЯ ЭКРАНА ==========
local function updateScreenSize()
    local w, h = gpu.getResolution()
    if w > 200 then w = 200 end
    if w < 80 then w = 80 end
    if h < 15 then h = 15 end
    screenW, screenH = w, h
    local usable = screenW - 8
    colWidth = math.max(12, math.floor(usable / 4))
    colX = {4, 4 + colWidth, 4 + colWidth * 2, 4 + colWidth * 3}
    logStartY = math.min(18, screenH - 5)
    maxLogLines = screenH - logStartY - 3
    if maxLogLines < 3 then maxLogLines = 3 end
    adminViewHeight = screenH - 8
    if adminViewHeight < 3 then adminViewHeight = 3
end

local function gotoxy(x, y)
    io.write("\27[", y, ";", x, "H")
end

local function fill(x, y, w, h, char)
    for i = 0, h-1 do
        gotoxy(x, y+i)
        io.write(string.rep(char, w))
    end
end

-- ========== ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ==========
local function timeToMidnight()
    local now = os.date("*t")
    local secondsLeft = (24 - now.hour - 1) * 3600 + (60 - now.min - 1) * 60 + (60 - now.sec)
    if secondsLeft < 0 then secondsLeft = 0 end
    local h = math.floor(secondsLeft / 3600)
    local m = math.floor((secondsLeft % 3600) / 60)
    local s = secondsLeft % 60
    return string.format("%02d:%02d:%02d", h, m, s)
end

local function addActivity()
    activityIndex = activityIndex % ACTIVITY_SIZE + 1
    activityBuffer[activityIndex] = 0
end

local function recordTransaction()
    if activityBuffer[activityIndex] then
        activityBuffer[activityIndex] = activityBuffer[activityIndex] + 1
    end
end

event.timer(60, addActivity, math.huge)

-- ========== ДАННЫЕ ИЗ ME ==========
local function updateMeStats()
    if not component.isAvailable("me_interface") then
        cachedMeTotal = "Комп. не найден"
        cachedMeUnique = "Проверь подключение"
        return
    end
    local me = component.me_interface
    local success, items = pcall(me.getItemsInNetwork, me)
    if not success or not items then
        cachedMeTotal = "Ошибка доступа"
        cachedMeUnique = "Нет данных"
        return
    end
    local totalItems = 0
    local uniqueItems = 0
    for _, it in ipairs(items) do
        totalItems = totalItems + (it.size or 0)
        uniqueItems = uniqueItems + 1
    end
    cachedMeTotal = tostring(totalItems)
    cachedMeUnique = tostring(uniqueItems)
end

meStatsTimer = event.timer(10, updateMeStats, math.huge)
updateMeStats()

-- ========== АДМИН-ПАНЕЛЬ ==========
local function updateAdminPlayerList()
    adminPlayerList = {}
    for name, data in pairs(players) do
        table.insert(adminPlayerList, {name=name, data=data})
    end
    table.sort(adminPlayerList, function(a,b) return a.name < b.name end)
end

local function drawAdminPanel()
    io.write(ansi.hide_cursor .. ansi.clear)
    updateScreenSize()

    setColor(ansi.white)
    fill(1, 1, screenW, 1, "─")
    fill(1, screenH, screenW, 1, "─")
    for y=2, screenH-1 do
        gotoxy(1, y) io.write("│")
        gotoxy(screenW, y) io.write("│")
    end
    gotoxy(1,1) io.write("┌"..string.rep("─", screenW-2).."┐")
    gotoxy(1,screenH) io.write("└"..string.rep("─", screenW-2).."┘")
    resetColor()

    setColor(ansi.bg_blue, ansi.white)
    fill(2, 1, screenW-2, 1, " ")
    gotoxy(2,1) io.write(" АДМИН-ПАНЕЛЬ (нажмите A для выхода) ")
    resetColor()

    local startIdx = adminScroll + 1
    local endIdx = math.min(#adminPlayerList, adminScroll + adminViewHeight)
    setColor(ansi.yellow)
    gotoxy(2, 3) io.write("Игроки (↑↓ выбор, клик мышкой, D - бан, R - сброс статистики, P - пауза, E - редактировать баланс)")
    resetColor()

    for i=startIdx, endIdx do
        local ply = adminPlayerList[i]
        local bannedStr = ply.data.banned and " [ЗАБАНЕН]" or ""
        local line = string.format("%-20s | Ресы: %8.2f | Эмы: %8.2f | Транз: %d%s",
            ply.name, ply.data.resBalance or 0, ply.data.balance or 0, ply.data.transactions or 0, bannedStr)
        if #line > screenW - 4 then line = line:sub(1, screenW-4) end
        local y = 4 + (i - startIdx)
        setColor((i == selectedAdminIndex) and ansi.bg_blue or ansi.white, (i == selectedAdminIndex) and ansi.white or nil)
        gotoxy(2, y)
        io.write(line)
        resetColor()
    end

    setColor(ansi.cyan)
    gotoxy(2, screenH-2)
    io.write("BAN: D | UNBAN: U | RESET STATS: R | PAUSE: P | EDIT BALANCE: E | SCROLL: ↑↓ | MOUSE CLICK")
    resetColor()
    io.flush()
end

-- ========== ОТРИСОВКА ОСНОВНОГО ИНТЕРФЕЙСА ==========
function drawInterface()
    io.write(ansi.hide_cursor .. ansi.clear)
    updateScreenSize()
    
    setColor(ansi.bg_blue, ansi.white)
    fill(1, 2, screenW, 1, " ")
    gotoxy(1, 2)
    local title = " PIM MARKET SERVER – СТАТУС: " .. (marketConnected and "АКТИВЕН" or "ОЖИДАНИЕ MARKET")
    if shopPaused then title = title .. " [ПАУЗА]" end
    io.write(title .. string.rep(" ", screenW - #title))
    resetColor()
    
    setColor(ansi.cyan)
    gotoxy(1, 3)
    io.write("Время: " .. os.date("%H:%M:%S") .. "  До сброса репортов: " .. timeToMidnight())
    local activeCount = 0
    for _, v in pairs(sessions) do
        if type(v) == "table" and v.token then activeCount = activeCount + 1 end
    end
    gotoxy(screenW - 25, 3)
    io.write("Активных сессий: " .. activeCount)
    resetColor()
    
    setColor(ansi.white)
    fill(1, 4, screenW, 1, "─")
    resetColor()
    
    local titles = {"👥 ИГРОКИ", "📦 ME СИСТЕМА", "🔒 БЕЗОПАСНОСТЬ", "📊 СТАТИСТИКА"}
    setColor(ansi.bold, ansi.yellow)
    for i=1,4 do
        gotoxy(colX[i], 5)
        io.write(titles[i] .. string.rep(" ", colWidth - #titles[i]))
    end
    resetColor()
    
    setColor(ansi.green)
    local playerList = {}
    for name, s in pairs(sessions) do
        if type(s) == "table" and s.token then table.insert(playerList, name) end
    end
    local rowsAvailable = logStartY - 7
    for i=1, math.min(rowsAvailable, #playerList) do
        gotoxy(colX[1], 5+i)
        local name = playerList[i]
        if #name > colWidth then name = name:sub(1, colWidth) end
        io.write(name .. string.rep(" ", colWidth - #name))
    end
    resetColor()
    
    setColor(ansi.cyan)
    gotoxy(colX[2], 6)
    io.write("Всего предметов: " .. cachedMeTotal)
    gotoxy(colX[2], 7)
    io.write("Уникальных типов: " .. cachedMeUnique)
    resetColor()
    
    setColor(ansi.magenta)
    gotoxy(colX[3], 6)
    io.write("Лимит сессии: " .. SESSION_TIMEOUT .. " сек")
    local playersCount = 0
    for _ in pairs(players) do playersCount = playersCount + 1 end
    gotoxy(colX[3], 7)
    io.write("Игроков в БД: " .. playersCount)
    gotoxy(colX[3], 9)
    io.write("Активность (последние 60 мин):")
    local graphWidth = colWidth - 2
    local maxVal = 1
    for i=1, ACTIVITY_SIZE do
        if activityBuffer[i] > maxVal then maxVal = activityBuffer[i] end
    end
    for i=1, math.min(ACTIVITY_SIZE, graphWidth) do
        local val = activityBuffer[(activityIndex - i + ACTIVITY_SIZE) % ACTIVITY_SIZE + 1] or 0
        local height = math.ceil((val / (maxVal+0.01)) * 3)
        gotoxy(colX[3]+i-1, 13 - height)
        setColor(ansi.green)
        io.write("█")
        resetColor()
    end
    resetColor()
    
    setColor(ansi.yellow)
    gotoxy(colX[4], 6)
    io.write("Репортов: " .. globalStats.totalReports)
    gotoxy(colX[4], 7)
    io.write("Покупок: " .. globalStats.totalBuys)
    gotoxy(colX[4], 8)
    io.write("Продаж: " .. globalStats.totalSells)
    resetColor()
    
    setColor(ansi.white)
    gotoxy(1, screenH-1)
    io.write("P - Пауза магазина | A - Админ-панель (только для " .. ADMIN_NAME .. " на PIM)")
    resetColor()
    
    setColor(ansi.white)
    fill(1, logStartY-1, screenW, 1, "─")
    resetColor()
    for i=1, maxLogLines do
        local entry = logBuffer[#logBuffer - maxLogLines + i]
        if entry then
            setColor(entry.color)
            gotoxy(1, logStartY + i - 1)
            local line = entry.text
            if #line > screenW - 1 then line = line:sub(1, screenW-1) end
            io.write(line .. string.rep(" ", screenW - #line))
            resetColor()
        end
    end
    io.flush()
end

-- ========== ЛОГИРОВАНИЕ ==========
function addLog(text, fg)
    table.insert(logBuffer, {text = text, color = fg or ansi.white})
    while #logBuffer > 200 do table.remove(logBuffer, 1) end
    if not adminMode then drawInterface() end
end

local function log(level, msg)
    local color = ansi.white
    if level == "INFO" then color = ansi.green
    elseif level == "WARN" then color = ansi.yellow
    elseif level == "ERROR" then color = ansi.red end
    addLog("[" .. os.date("%H:%M:%S") .. "] [" .. level .. "] " .. msg, color)
end

-- ========== ОБРАБОТКА СОБЫТИЙ PIM (запоминаем игрока) ==========
local function onPlayerEnter(playerName, playerUUID)
    currentPIMPlayer = playerName
    log("INFO", "Игрок " .. playerName .. " встал на PIM")
end

local function onPlayerLeave()
    currentPIMPlayer = nil
    -- если админ-панель была открыта и админ ушёл – закрываем её
    if adminMode then
        adminMode = false
        drawInterface()
    end
    log("INFO", "Игрок ушёл с PIM")
end

-- ========== ОБРАБОТКА КЛАВИШ И МЫШИ ==========
local function handleKey(keyCode, char, playerFromEvent)
    local currentPlayer = currentPIMPlayer

    if keyCode == 97 or keyCode == 65 then   -- A / a
        if currentPlayer ~= ADMIN_NAME then
            log("WARN", "Попытка открыть админ-панель не админом: " .. tostring(currentPlayer))
            return
        end
        if adminMode then
            adminMode = false
            drawInterface()
        else
            adminMode = true
            updateAdminPlayerList()
            selectedAdminIndex = 1
            adminScroll = 0
            drawAdminPanel()
        end
        return
    end

    if keyCode == 112 or keyCode == 80 then   -- P / p
        if currentPlayer ~= ADMIN_NAME then
            log("WARN", "Попытка изменить паузу не админом")
            return
        end
        shopPaused = not shopPaused
        log("INFO", "Магазин " .. (shopPaused and "приостановлен" or "возобновлён"))
        if adminMode then drawAdminPanel() else drawInterface() end
        return
    end

    if adminMode then
        if keyCode == 200 then -- стрелка вверх
            if selectedAdminIndex > 1 then
                selectedAdminIndex = selectedAdminIndex - 1
                if selectedAdminIndex < adminScroll + 1 then
                    adminScroll = math.max(0, selectedAdminIndex - 1)
                end
                drawAdminPanel()
            end
        elseif keyCode == 208 then -- стрелка вниз
            if selectedAdminIndex < #adminPlayerList then
                selectedAdminIndex = selectedAdminIndex + 1
                if selectedAdminIndex > adminScroll + adminViewHeight then
                    adminScroll = selectedAdminIndex - adminViewHeight
                end
                drawAdminPanel()
            end
        elseif keyCode == 100 or keyCode == 68 then -- D / d
            local ply = adminPlayerList[selectedAdminIndex]
            if ply then
                ply.data.banned = not ply.data.banned
                log("INFO", "Игрок " .. ply.name .. (ply.data.banned and " забанен" or " разбанен"))
                saveDB()
                drawAdminPanel()
            end
        elseif keyCode == 114 or keyCode == 82 then -- R / r
            local ply = adminPlayerList[selectedAdminIndex]
            if ply then
                ply.data.transactions = 0
                ply.data.balance = 0
                ply.data.resBalance = 0
                saveDB()
                log("INFO", "Статистика игрока " .. ply.name .. " сброшена")
                drawAdminPanel()
            end
        elseif keyCode == 101 or keyCode == 69 then -- E / e
            local ply = adminPlayerList[selectedAdminIndex]
            if ply then
                log("INFO", "Редактирование баланса игрока " .. ply.name .. " (функция в разработке)")
                drawAdminPanel()
            end
        end
    end
end

local function handleTouch(x, y, playerFromEvent)
    if not adminMode then return end
    if currentPIMPlayer ~= ADMIN_NAME then return end
    if y >= 4 and y <= 4 + adminViewHeight - 1 then
        local lineIndex = y - 4
        local realIndex = adminScroll + lineIndex + 1
        if realIndex >= 1 and realIndex <= #adminPlayerList then
            selectedAdminIndex = realIndex
            drawAdminPanel()
        end
    end
end

-- ========== БАЗОВЫЕ ФУНКЦИИ ДЛЯ ИГРОКОВ ==========
local function getOrCreatePlayer(name)
    if not players[name] then
        players[name] = {
            balance = 0.0, resBalance = 0.0, transactions = 0,
            regDate = os.date("%d.%m.%Y %H:%M:%S"), agreed = false, banned = false
        }
        saveDB()
        log("INFO", "Создан игрок " .. name)
    end
    return players[name]
end

local function validateSession(name, token)
    local s = sessions[name]
    return s and s.token == token and os.time() - (s.lastAction or 0) < SESSION_TIMEOUT
end

-- ========== ОСНОВНОЙ ЦИКЛ ==========
local refreshTimer = event.timer(3, function()
    if not adminMode then drawInterface() end
end, math.huge)

log("INFO", "Сервер запущен. Ожидание терминалов...")
drawInterface()

while true do
    local ev = {event.pull(0.5)}
    local etype = ev[1]

    if etype == "key_down" then
        local keyCode = ev[4]
        local char = ev[3]
        handleKey(keyCode, char, ev[5])
    elseif etype == "touch" then
        local x, y = ev[3], ev[4]
        local player = ev[5]
        handleTouch(x, y, player)
    elseif etype == "player_on" or etype == "pim_player_enter" then
        local playerName = ev[2] or ev[3]
        if type(playerName) ~= "string" then playerName = tostring(playerName) end
        onPlayerEnter(playerName, ev[3])
    elseif etype == "player_off" or etype == "pim_player_leave" then
        onPlayerLeave()
    elseif etype == "modem_message" then
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
            if msg.password ~= ACCESS_PASSWORD then
                modem.send(from, 0xffef, serialization.serialize({op="error", message="Неверный пароль"}))
                log("WARN", "Попытка подключения с неверным паролем от " .. from)
                goto continue
            end
            marketConnected = true
            if not owner then
                owner = from
                log("INFO", "✅ АДМИН ЗАРЕГИСТРИРОВАН: " .. from)
            end
            modem.send(from, 0xffef, serialization.serialize({op="welcome", owner=(from==owner), shopPaused=shopPaused}))
            if not adminMode then drawInterface() end

        elseif msg.op == "enter" then
            if shopPaused then
                modem.send(from, 0xffef, serialization.serialize({op="error", message="Магазин на паузе"}))
                goto continue
            end
            local playerName = msg.name
            if not playerName or playerName == "" then
                log("WARN", "Вход без имени от " .. from)
                goto continue
            end
            local player = getOrCreatePlayer(playerName)
            if player.banned then
                modem.send(from, 0xffef, serialization.serialize({op="error", message="Вы забанены"}))
                goto continue
            end

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
                agreed = player.agreed or false,
                shopPaused = shopPaused
            }))
            if not adminMode then drawInterface() end

        elseif msg.op == "getAccount" then
            if not validateSession(msg.name, msg.token) then
                log("WARN", "Неверный токен для getAccount от " .. (msg.name or "?"))
                modem.send(from, 0xffef, serialization.serialize({op="accountData", error = true, message = "Токен устарел"}))
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
                    agreed = player.agreed,
                    shopPaused = shopPaused
                }
            }))
            log("INFO", "Аккаунт отправлен для " .. msg.name)

        elseif msg.op == "sell" then
            if shopPaused then
                modem.send(from, 0xffef, serialization.serialize({op="error", message="Магазин на паузе"}))
                goto continue
            end
            if not validateSession(msg.name, msg.token) then
                log("WARN", "Неверный токен для sell")
                goto continue
            end
            local player = players[msg.name]
            if not player or player.banned then goto continue end
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

            globalStats.totalSells = (globalStats.totalSells or 0) + 1
            saveGlobalStats()
            saveDB()
            recordTransaction()
            log("INFO", string.format("💰 %s пополнил %s: предмет '%s' x%d на сумму %.2f", msg.name, currency, msg.item, qty, value))

        elseif msg.op == "buy" then
            if shopPaused then
                modem.send(from, 0xffef, serialization.serialize({op="error", message="Магазин на паузе"}))
                goto continue
            end
            if not validateSession(msg.name, msg.token) then
                log("WARN", "Неверный токен для buy")
                goto continue
            end
            local player = players[msg.name]
            if not player or player.banned then goto continue end
            local value = tonumber(msg.value) or 0
            local currency = msg.currency or "res"
            if currency == "em" then
                player.balance = (player.balance or 0) - value
            else
                player.resBalance = (player.resBalance or 0) - value
            end
            player.transactions = (player.transactions or 0) + 1
            sessions[msg.name].lastAction = os.time()

            globalStats.totalBuys = (globalStats.totalBuys or 0) + 1
            saveGlobalStats()
            saveDB()
            recordTransaction()
            log("INFO", string.format("🛒 %s купил %s x%d за %.2f %s", msg.name, msg.item, msg.qty, value, currency))

        elseif msg.op == "report" then
            if not validateSession(msg.name, msg.token) then
                log("WARN", "Неверный токен для report")
                goto continue
            end
            globalStats.totalReports = (globalStats.totalReports or 0) + 1
            saveGlobalStats()
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
