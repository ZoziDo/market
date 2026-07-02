-- ============================================
-- TELEGRAM БОТ ДЛЯ PIM MARKET
-- Отдельный файл, работает параллельно с pimserver.lua
-- ============================================

local component = require("component")
local event = require("event")
local modem = component.modem
local serialization = require("serialization")
local internet = require("internet")
local filesystem = require("filesystem")
local computer = require("computer")

-- ============================================
-- НАСТРОЙКИ (ЗАМЕНИ НА СВОИ!)
-- ============================================
local TELEGRAM_TOKEN = "8780133006:AAF2Zg7Dv_mr-E1-bgVuGDVsKYvyuwizuaE"
local TELEGRAM_CHAT_ID = "492178371"

-- АДРЕС ТВОЕГО PIMSERVER (УЗНАЙ КОМАНДОЙ: lua -e 'local m=require("component").modem; print(m.address)')
local PIM_SERVER = "9aae30d7-90cc-4da0-9789-7c8636e4fddc"

-- ============================================
-- ИНИЦИАЛИЗАЦИЯ
-- ============================================
modem.open(0xffef)
local lastUpdateId = 0
local botRunning = true

print("")
print("═══════════════════════════════════════════")
print("🤖 TELEGRAM БОТ ДЛЯ PIM MARKET")
print("═══════════════════════════════════════════")
print("")
print("📡 Адрес модема: " .. modem.address)
print("🎯 PIM Server: " .. PIM_SERVER)
print("📱 Chat ID: " .. TELEGRAM_CHAT_ID)
print("")
print("✅ Бот запущен! Жду команды...")
print("")

-- ============================================
-- ФУНКЦИИ ОТПРАВКИ В TELEGRAM
-- ============================================

local function sendTelegram(text, keyboard)
    if not text then return false end
    
    -- Экранируем текст для URL
    local encodedText = text:gsub(" ", "%%20")
    encodedText = encodedText:gsub("\n", "%%0A")
    encodedText = encodedText:gsub("#", "%%23")
    encodedText = encodedText:gsub("&", "%%26")
    
    local url = "https://api.telegram.org/bot" .. TELEGRAM_TOKEN .. "/sendMessage"
    local postData = "chat_id=" .. TELEGRAM_CHAT_ID .. "&text=" .. encodedText
    
    if keyboard then
        postData = postData .. "&reply_markup=" .. keyboard
    end
    
    local success, response = pcall(function()
        return internet.request(url, postData, {
            ["Content-Type"] = "application/x-www-form-urlencoded"
        })
    end)
    
    if success then
        return true
    else
        print("❌ Ошибка отправки: " .. tostring(response))
        return false
    end
end

-- ============================================
-- КЛАВИАТУРЫ
-- ============================================

-- Главное меню
local function getMainKeyboard()
    return '{"keyboard": [["👥 Игроки", "📊 Статистика"], ["💰 Баланс", "👑 Админы"], ["📦 Добавить предмет", "🔄 Обновить"], ["⏸️ Пауза", "🚫 Закрыть"]], "resize_keyboard": true}'
end

-- Клавиатура с игроками
local function getPlayersKeyboard(playersList)
    local keyboard = '{"keyboard": ['
    local row = {}
    local count = 0
    
    for i, name in ipairs(playersList) do
        table.insert(row, '"' .. name .. '"')
        count = count + 1
        if #row == 2 then
            keyboard = keyboard .. '[' .. table.concat(row, ",") .. '],'
            row = {}
        end
        if count >= 10 then break end
    end
    
    if #row > 0 then
        keyboard = keyboard .. '[' .. table.concat(row, ",") .. '],'
    end
    
    keyboard = keyboard .. '["🔙 Назад"]], "resize_keyboard": true}'
    return keyboard
end

-- ============================================
-- ОТПРАВКА КОМАНД В PIMSERVER
-- ============================================

local function sendToPimServer(command, data, callback)
    local msg = {
        op = "web_command",
        command = command,
        admin_name = "ZoziDo"
    }
    
    if data then
        for k, v in pairs(data) do
            msg[k] = v
        end
    end
    
    modem.send(PIM_SERVER, 0xffef, serialization.serialize(msg))
    
    -- Ждем ответ
    local start = os.clock()
    while os.clock() - start < 5 do
        local ev = {event.pull(0.2)}
        if ev[1] == "modem_message" then
            local from = ev[3]
            local raw = ev[6]
            local success, parsed = pcall(serialization.unserialize, raw)
            if success and parsed and parsed.op == "web_response" then
                if callback then
                    callback(parsed)
                end
                return parsed
            end
        end
    end
    return nil
end

-- ============================================
-- ОБРАБОТЧИК КОМАНД
-- ============================================

local function handleCommand(text)
    if not text or text == "" then return end
    
    print("📥 Команда: " .. text)
    
    -- ========== ГЛАВНОЕ МЕНЮ ==========
    if text == "/start" or text == "🔙 Назад" then
        sendTelegram("🛒 **PIM Market Admin**\n\nВыберите действие:", getMainKeyboard())
        return
    end
    
    -- ========== ИГРОКИ ==========
    if text == "👥 Игроки" then
        local response = sendToPimServer("get_players")
        if response and response.players then
            local msg = "👥 **Список игроков:**\n"
            msg = msg .. "═══════════════════\n"
            local playersList = {}
            for i, p in ipairs(response.players) do
                msg = msg .. i .. ". " .. p.name
                if p.banned then msg = msg .. " 🚫" end
                msg = msg .. "\n"
                table.insert(playersList, p.name)
                if i >= 10 then
                    msg = msg .. "\n... и ещё " .. (#response.players - 10) .. " игроков"
                    break
                end
            end
            if #response.players == 0 then
                msg = msg .. "Нет игроков"
            end
            sendTelegram(msg, getPlayersKeyboard(playersList))
        else
            sendTelegram("❌ Не удалось получить список игроков", getMainKeyboard())
        end
        return
    end
    
    -- ========== СТАТИСТИКА ==========
    if text == "📊 Статистика" then
        local response = sendToPimServer("get_stats")
        if response then
            local msg = "📊 **Статистика магазина**\n"
            msg = msg .. "═══════════════════\n"
            msg = msg .. "👥 Игроков: " .. (response.totalPlayers or 0) .. "\n"
            msg = msg .. "💰 Транзакций: " .. (response.totalTransactions or 0) .. "\n"
            msg = msg .. "🚫 Забанов: " .. (response.bannedCount or 0) .. "\n"
            msg = msg .. "👑 Админов: " .. (response.adminsCount or 0) .. "\n"
            msg = msg .. "⏸️ Пауза: " .. (response.shopPaused and "🔴 Включена" or "🟢 Выключена") .. "\n"
            sendTelegram(msg, getMainKeyboard())
        else
            sendTelegram("❌ Не удалось получить статистику", getMainKeyboard())
        end
        return
    end
    
    -- ========== АДМИНЫ ==========
    if text == "👑 Админы" then
        local response = sendToPimServer("get_admins")
        if response and response.admins then
            local msg = "👑 **Администраторы:**\n"
            msg = msg .. "═══════════════════\n"
            for i, name in ipairs(response.admins) do
                msg = msg .. i .. ". " .. name .. "\n"
            end
            if #response.admins == 0 then
                msg = msg .. "Нет администраторов"
            end
            sendTelegram(msg, getMainKeyboard())
        else
            sendTelegram("❌ Не удалось получить список админов", getMainKeyboard())
        end
        return
    end
    
    -- ========== ПАУЗА ==========
    if text == "⏸️ Пауза" then
        local response = sendToPimServer("toggle_pause")
        if response and response.success then
            local status = response.paused and "🔴 ПРИОСТАНОВЛЕН" or "🟢 ВОЗОБНОВЛЕН"
            sendTelegram("⏸️ Магазин **" .. status .. "**", getMainKeyboard())
        else
            sendTelegram("❌ Не удалось изменить статус", getMainKeyboard())
        end
        return
    end
    
    -- ========== ОБНОВИТЬ ==========
    if text == "🔄 Обновить" then
        sendTelegram("🔄 **Отправка обновления** всем терминалам...", getMainKeyboard())
        -- Отправляем обновление через pimserver
        local response = sendToPimServer("update_market")
        sendTelegram("✅ **Обновление отправлено!**", getMainKeyboard())
        return
    end
    
    -- ========== ЗАКРЫТЬ ==========
    if text == "🚫 Закрыть" then
        sendTelegram("🚫 **Закрытие магазина...**", getMainKeyboard())
        local response = sendToPimServer("kill_market")
        sendTelegram("🚫 **Магазин закрыт!** Все терминалы отключены.", getMainKeyboard())
        return
    end
    
    -- ========== ДОБАВИТЬ ПРЕДМЕТ ==========
    if text == "📦 Добавить предмет" then
        local msg = "📦 **Добавление предмета**\n\n"
        msg = msg .. "Отправьте команду:\n"
        msg = msg .. "`/additem internalName displayName цена_coin цена_ema`\n\n"
        msg = msg .. "📌 **Пример:**\n"
        msg = msg .. "`/additem minecraft:diamond Алмаз 10 5`\n\n"
        msg = msg .. "Где:\n"
        msg = msg .. "• internalName - ID предмета\n"
        msg = msg .. "• displayName - отображаемое имя\n"
        msg = msg .. "• цена_coin - цена в Coina\n"
        msg = msg .. "• цена_ema - цена в ЭМЫ"
        sendTelegram(msg, getMainKeyboard())
        return
    end
    
    -- ========== ДОБАВЛЕНИЕ ПРЕДМЕТА (КОМАНДА) ==========
    if text:match("^/additem") then
        local parts = {}
        for part in text:gmatch("%S+") do
            table.insert(parts, part)
        end
        
        if #parts >= 4 then
            local internal = parts[2]
            local display = parts[3]
            local coin = tonumber(parts[4]) or 0
            local ema = tonumber(parts[5]) or 0
            
            if coin < 0 then coin = 0 end
            if ema < 0 then ema = 0 end
            
            if coin == 0 and ema == 0 then
                sendTelegram("❌ **Ошибка!**\nЦена не может быть нулевой (хотя бы одна валюта > 0)", getMainKeyboard())
                return
            end
            
            local response = sendToPimServer("add_item", {
                internal = internal,
                display = display,
                price_coin = coin,
                price_ema = ema,
                damage = 0
            })
            
            if response and response.success then
                local msg = "✅ **Предмет добавлен!**\n"
                msg = msg .. "═══════════════════\n"
                msg = msg .. "📦 " .. display .. "\n"
                msg = msg .. "🆔 " .. internal .. "\n"
                if coin > 0 then msg = msg .. "💰 " .. coin .. " ₵\n" end
                if ema > 0 then msg = msg .. "💚 " .. ema .. " ۞\n" end
                sendTelegram(msg, getMainKeyboard())
            else
                sendTelegram("❌ **Ошибка добавления!**\nПроверьте правильность данных.", getMainKeyboard())
            end
        else
            local msg = "❌ **Ошибка!**\n\n"
            msg = msg .. "Формат:\n"
            msg = msg .. "`/additem internalName displayName цена_coin цена_ema`\n\n"
            msg = msg .. "Пример:\n"
            msg = msg .. "`/additem minecraft:diamond Алмаз 10 5`"
            sendTelegram(msg, getMainKeyboard())
        end
        return
    end
    
    -- ========== БАЛАНС ИГРОКА ==========
    if text == "💰 Баланс" then
        sendTelegram("💰 **Баланс игрока**\n\nВведите имя игрока:", '{"keyboard": [["🔙 Назад"]], "resize_keyboard": true}')
        return
    end
    
    -- ========== ПРОВЕРКА: ВВЕДЕНО ИМЯ ИГРОКА ==========
    -- Если текст не команда и не кнопка - пробуем найти игрока
    if not text:match("^/") and text ~= "🔙 Назад" and text ~= "👥 Игроки" and text ~= "📊 Статистика" and text ~= "👑 Админы" and text ~= "⏸️ Пауза" and text ~= "🔄 Обновить" and text ~= "🚫 Закрыть" and text ~= "📦 Добавить предмет" and text ~= "💰 Баланс" then
        -- Проверяем, есть ли такой игрок
        local response = sendToPimServer("get_players")
        if response and response.players then
            for _, p in ipairs(response.players) do
                if p.name:lower() == text:lower() then
                    local msg = "👤 **" .. p.name .. "**\n"
                    msg = msg .. "═══════════════════\n"
                    msg = msg .. "💰 Coina: " .. string.format("%.2f", p.balance or 0) .. " ₵\n"
                    msg = msg .. "💚 ЭМЫ: " .. string.format("%.2f", p.emaBalance or 0) .. " ۞\n"
                    msg = msg .. "📊 Транзакций: " .. (p.transactions or 0) .. "\n"
                    msg = msg .. "📅 Регистрация: " .. (p.regDate or "неизвестно") .. "\n"
                    if p.banned then msg = msg .. "🚫 **Забанен**" else msg = msg .. "✅ **Активен**" end
                    sendTelegram(msg, getMainKeyboard())
                    return
                end
            end
        end
        sendTelegram("❌ Игрок **" .. text .. "** не найден!\nПроверьте имя и попробуйте снова.", getMainKeyboard())
        return
    end
end

-- ============================================
-- ПРОВЕРКА НОВЫХ СООБЩЕНИЙ
-- ============================================

local function checkUpdates()
    local url = "https://api.telegram.org/bot" .. TELEGRAM_TOKEN .. "/getUpdates?offset=" .. (lastUpdateId + 1) .. "&timeout=10"
    
    local success, response = pcall(function()
        return internet.request(url)
    end)
    
    if not success then return end
    
    if type(response) == "table" then
        local responseData = ""
        while true do
            local chunk = response()
            if not chunk then break end
            responseData = responseData .. chunk
        end
        
        local ok, parsed = pcall(function()
            return serialization.unserialize(responseData)
        end)
        
        if ok and parsed and parsed.result then
            for _, update in ipairs(parsed.result) do
                if update.update_id and update.update_id > lastUpdateId then
                    lastUpdateId = update.update_id
                end
                if update.message and update.message.text then
                    handleCommand(update.message.text)
                end
            end
        end
    end
end

-- ============================================
-- ОСНОВНОЙ ЦИКЛ
-- ============================================

-- Отправляем приветственное сообщение
sendTelegram("🤖 **PIM Market Бот запущен!**\n\nНажмите /start для начала работы.", getMainKeyboard())

while botRunning do
    local success, err = pcall(function()
        checkUpdates()
    end)
    
    if not success then
        print("⚠️ Ошибка: " .. tostring(err))
    end
    
    os.sleep(1)
end

print("🛑 Бот остановлен")
