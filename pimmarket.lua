-- ============================================================
-- ★★★ ЗАГОЛОВОК ★★★
-- ============================================================
local component = require("component")
local event = require("event")
local gpu = component.gpu
local unicode = require("unicode")
local serialization = require("serialization")
local computer = require("computer")
local fs = require("filesystem")
local internet = require("internet")
local math = require("math")
local os = require("os")
local shell = require("shell")

-- ============================================================
-- ★★★ ВРЕМЯ ★★★
-- ============================================================
TIMEZONE_OFFSET = 3 * 3600
tmpfs = component.proxy(computer.tmpAddress())

function getRealTimestamp()
    local handle = tmpfs.open("/time", "w")
    tmpfs.write(handle, "time")
    tmpfs.close(handle)
    return tmpfs.lastModified("/time") / 1000 + TIMEZONE_OFFSET
end

function getRealTimeString()
    return os.date("%d.%m.%Y %H:%M:%S", getRealTimestamp())
end

function getRealTimeHM()
    return os.date("%H:%M:%S", getRealTimestamp())
end

-- ============================================================
-- ★★★ ВСЕ ЦВЕТА В ОДНОМ МЕСТЕ ★★★
-- ============================================================
COLORS = {
    BG_MAIN        = 0x0A0A0F,
    BG_SECONDARY   = 0x14141F,
    BG_BUTTON      = 0x1F1F2E,
    BG_INPUT       = 0x282828,
    BG_POPUP       = 0x0A0A1A,
    BG_ERROR       = 0x441111,
    BG_SUCCESS     = 0x113322,
    BG_WARNING     = 0x332211,
    ACCENT_MAIN    = 0x8B5CF6,
    ACCENT_SECONDARY = 0x00E5C9,
    ACCENT_GOLD    = 0xFFD700,
    TEXT_MAIN      = 0xD0D0E0,
    TEXT_BRIGHT    = 0xF0F0FF,
    TEXT_MUTED     = 0x6B7D93,
    SUCCESS        = 0x00FFAA,
    SUCCESS_GREEN  = 0x3BFF18,
    ERROR          = 0xFF4D7A,
    ERROR_RED      = 0xEF5350,
    WARNING        = 0xFFA726,
    INACTIVE       = 0x555566,
    BLACK          = 0x000000,
    WHITE          = 0xFFFFFF,
    TOMATO         = 0xFF6347,
    CYAN           = 0x00FFCC,
}
colors = COLORS

-- ============================================================
-- ★★★ ВСЕ ЛОГИ В ОДНОМ МЕСТЕ ★★★
-- ============================================================
LOG_TYPES = {
    SYSTEM = {
        STARTUP  = { icon = "🚀", color = COLORS.SUCCESS, send_to_web = false },
        SHUTDOWN = { icon = "🔴", color = COLORS.ERROR, send_to_web = false },
        CACHE    = { icon = "💾", color = COLORS.ACCENT_MAIN, send_to_web = false },
        SYNC     = { icon = "🔄", color = COLORS.ACCENT_SECONDARY, send_to_web = false },
    },
    PLAYER = {
        ENTER    = { icon = "👤", color = COLORS.SUCCESS_GREEN, send_to_web = true },
        LEAVE    = { icon = "🚪", color = COLORS.ERROR_RED, send_to_web = true },
        NEW      = { icon = "✅", color = COLORS.SUCCESS, send_to_web = true },
        BAN      = { icon = "⛔", color = COLORS.ERROR, send_to_web = true },
    },
    TRANSACTION = {
        BUY      = { icon = "🛒", color = COLORS.ACCENT_MAIN, send_to_web = true },
        SELL     = { icon = "💰", color = COLORS.SUCCESS_GREEN, send_to_web = true },
        BALANCE  = { icon = "💳", color = COLORS.ACCENT_GOLD, send_to_web = true },
    },
    BINDING = {
        LINK     = { icon = "🔗", color = COLORS.SUCCESS, send_to_web = true },
        UNLINK   = { icon = "🔓", color = COLORS.WARNING, send_to_web = true },
        ERROR    = { icon = "❌", color = COLORS.ERROR, send_to_web = true },
    },
    SHOP = {
        PAUSE    = { icon = "⏸️", color = COLORS.WARNING, send_to_web = true },
        RESUME   = { icon = "🟢", color = COLORS.SUCCESS, send_to_web = true },
    },
    ERROR_LOG = {
        CRITICAL = { icon = "💥", color = COLORS.ERROR, send_to_web = true },
        WARNING  = { icon = "⚠️", color = COLORS.WARNING, send_to_web = true },
        INFO     = { icon = "ℹ️", color = COLORS.TEXT_MUTED, send_to_web = true },
    },
    FEEDBACK = {
        NEW      = { icon = "📝", color = COLORS.ACCENT_GOLD, send_to_web = true },
        DELETE   = { icon = "🗑️", color = COLORS.ERROR, send_to_web = true },
    },
    REPORT = {
        NEW      = { icon = "📩", color = COLORS.ERROR_RED, send_to_web = true },
    },
    UI = {
        DRAW     = { icon = "🖥️", color = COLORS.TEXT_MUTED, send_to_web = false },
        CLICK    = { icon = "👆", color = COLORS.TEXT_MUTED, send_to_web = false },
    },
}

-- ============================================================
-- ★★★ НОВАЯ СИСТЕМА ЛОГИРОВАНИЯ ★★★
-- ============================================================
logQueue = {}
LOG_FLUSH_INTERVAL = 15

function addLogEntry(text, level)
    if not text then text = "?" end
    level = level or "INFO"
    table.insert(logQueue, { text = text, time = getRealTimeHM(), level = level })
    if #logQueue >= 50 then flushLogQueue() end
end

function addConsoleLog(text, color)
    if color then gpu.setForeground(color) end
    print(text)
    if color then gpu.setForeground(COLORS.TEXT_MAIN) end
end

function addLogWithIcon(text, log_type, category)
    local cat = LOG_TYPES[category] and LOG_TYPES[category][log_type]
    if cat then addLogEntry(cat.icon .. " " .. text, "INFO") else addLogEntry(text, "INFO") end
end

function addPlayerLog(text, log_type)
    local cat = LOG_TYPES.PLAYER[log_type]
    if cat then addLogEntry(cat.icon .. " " .. text, "INFO") else addLogEntry(text, "INFO") end
end

function addTransactionLog(text, log_type)
    local cat = LOG_TYPES.TRANSACTION[log_type]
    if cat then addLogEntry(cat.icon .. " " .. text, "INFO") else addLogEntry(text, "INFO") end
end

function addBindingLog(text, log_type)
    local cat = LOG_TYPES.BINDING[log_type]
    if cat then addLogEntry(cat.icon .. " " .. text, "INFO") else addLogEntry(text, "INFO") end
end

function addErrorLog(text, log_type)
    local cat = LOG_TYPES.ERROR_LOG[log_type]
    if cat then addLogEntry(cat.icon .. " " .. text, "ERROR") else addLogEntry("❌ " .. text, "ERROR") end
end

function flushLogQueue()
    if #logQueue == 0 then return end
    local logs_to_send = {}
    for _, e in ipairs(logQueue) do
        local should_send = true
        for category, types in pairs(LOG_TYPES) do
            for name, config in pairs(types) do
                if config.icon and config.icon .. " " == string.sub(e.text, 1, #config.icon + 1) then
                    if not config.send_to_web then should_send = false end
                    break
                end
            end
            if not should_send then break end
        end
        if should_send then table.insert(logs_to_send, { time = e.time, text = e.text, level = e.level }) end
    end
    if #logs_to_send == 0 then logQueue = {}; return end
    pcall(function() sendToWeb("/api/logs_batch", toJson({ logs = logs_to_send })) end)
    logQueue = {}
end

createTimer(LOG_FLUSH_INTERVAL, flushLogQueue, true)

function addLog(text) addLogEntry(text, "INFO") end
function writeDebugLog(msg) addConsoleLog(msg, COLORS.TEXT_MUTED) end
function writeErrorLog(msg) addErrorLog(msg, "WARNING") end
function writeDebugFile(msg) addConsoleLog(msg, COLORS.TEXT_MUTED) end

-- ============================================================
-- ★★★ ВСЕ ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ ★★★
-- ============================================================
WEB_URL = "https://zozido.pythonanywhere.com"
TRANSACTION_LOCK = false
isShuttingDown = false
guiDirty = true
renderTimer = nil

-- КЕШ ДАННЫХ С ХОСТИНГА
cache_players = {}
cache_buy_items = {}
cache_sell_items = {}
cache_feedbacks = {}
cache_reports = {}
cache_admins = {}
cache_bans = {}
cache_shop_paused = false
cache_online = 0

-- Буфер транзакций (если нет интернета)
transaction_buffer = {}
BUFFER_FILE = "/home/transaction_buffer.lua"

-- Время последнего обновления кеша
last_cache_update = 0
CACHE_UPDATE_INTERVAL = 30
isSyncing = false

-- ---- ИГРОКИ ----
currentPlayer = nil
currentToken = nil
pimOwner = nil
alreadyAuthorized = false
coinBalance = 0.0
emaBalance = 0.0
playerTransactions = 0
playerRegDate = ""
playerAgreed = false
playerHasFeedback = false

-- ---- ЭКРАНЫ ----
currentScreen = "welcome"
qrPopupActive = false
lastRenderedScreen = ""

-- ---- АУТЕНТИФИКАЦИЯ ----
authCodeInput = ""
boundPlayer = nil
authStartTime = 0
AUTH_TIMEOUT = 3

-- ---- МАГАЗИН ----
shopItems = {}
shopSearch = ""
searchActive = false
searchInput = ""
currentShopMode = "buy"
shopPaused = false
listScroll = 1
visibleRows = 15
selectedIndex = 0
hoveredIndex = 0
filteredItems = {}
selectedItem = nil
horizontalScroll = 1
maxItemWidth = 0
purchaseQuantity = 1
purchaseItem = nil
sellConfirmItem = nil
foundAmount = 0
showSellPopup = false

-- ---- ПОПАПЫ ----
showPartialPopup = false
partialExtracted = 0
partialRequested = 0
partialRefundCoin = 0
partialRefundEma = 0
partialItem = nil
showInsufficientPopup = false
insufficientBalanceCoin = 0
insufficientBalanceEma = 0
showInventoryFullPopup = false

-- ---- РЕПОРТЫ И ОТЗЫВЫ ----
reportInput = ""
lastReportTime = nil
showShopDenied = false
feedbacksPage = 1
feedbacksTotalPages = 1
feedbackInput = ""
feedbackRating = 5
feedbackEditMode = false

-- ---- ТАЙМЕРЫ ----
timers = {}
tempMessage = ""
tempMessageTimer = nil
mouseDebounceTimer = nil
pendingMouseX = 0
pendingMouseY = 0

-- ---- ОПТИМИЗАЦИЯ ----
lastSentQuantities = {}
lastSentTime = 0
lastCheckTime = 0
MIN_SEND_INTERVAL = 1800

-- ---- ПРИВЯЗКА ----
bindingCache = {
    isBound = false,
    lastCheck = 0,
    checkInterval = 10,
    pendingUpdate = false
}

-- ---- ЧЁРНЫЙ СПИСОК ----
blacklist = {
    ["customnpcs:npcMoney"] = true,
}

-- ---- НАПРАВЛЕНИЯ ----
PUSH_DIRECTION = "down"
PULL_DIRECTION = "up"

-- ============================================================
-- ★★★ АВТОМАТИЧЕСКАЯ НАСТРОЙКА АВТОЗАПУСКА ★★★
-- ============================================================

function setupAutoStart()
    local startupFile = "/home/startup.lua"
    if not fs.exists(startupFile) then
        addConsoleLog("📝 Создаём автозапуск: " .. startupFile, COLORS.ACCENT_MAIN)
        local file = io.open(startupFile, "w")
        if file then
            file:write([[
-- Автозапуск PIM MARKET
local shell = require("shell")
local computer = require("computer")

os.sleep(3)
shell.execute("lua /home/pimmarket.lua &")
print("✅ PIM MARKET запущен")
]])
            file:close()
            addConsoleLog("✅ Автозапуск создан", COLORS.SUCCESS)
            return true
        end
    end
    
    local shrcFile = "/home/.shrc"
    if not fs.exists(shrcFile) then
        local file = io.open(shrcFile, "w")
        if file then
            file:write("-- Автозапуск PIM MARKET\n")
            file:write("lua /home/pimmarket.lua &\n")
            file:close()
            addConsoleLog("✅ .shrc создан", COLORS.SUCCESS)
        end
    end
    
    return true
end

if not fs.exists("/home/.autostart_done") then
    local success = setupAutoStart()
    if success then
        local file = io.open("/home/.autostart_done", "w")
        if file then
            file:write("autostart_configured_" .. os.date("%Y-%m-%d %H:%M:%S"))
            file:close()
        end
        addConsoleLog("🎯 Автозагрузка настроена!", COLORS.SUCCESS)
    end
end

pcall(function()
    event.ignore("interrupted", function() end)
    event.ignore("terminate", function() end)
end)

if not event.shouldInterrupt then
    function event.shouldInterrupt()
        return false
    end
end

-- ============================================================
-- ★★★ GRACEFUL SHUTDOWN ★★★
-- ============================================================

function saveAllData()
    writeDebugLog("💾 Сохранение всех данных...")
    flushLogQueue()
    if #transaction_buffer > 0 then
        saveTransactionBuffer()
        writeDebugLog("   ✅ Буфер транзакций сохранён")
    end
    writeDebugLog("💾 Все данные сохранены!")
end

function asyncSaveData()
    if isShuttingDown then
        return
    end
    
    isShuttingDown = true
    
    event.timer(0.1, function()
        pcall(saveAllData)
        isShuttingDown = false
        return false
    end)
end

function forceSaveData()
    isShuttingDown = true
    saveAllData()
    isShuttingDown = false
end

event.listen("computer_shutdown", function()
    addErrorLog("⏻ Компьютер выключается! Сохраняем данные...", "WARNING")
    forceSaveData()
    addConsoleLog("✅ Данные сохранены перед выключением", COLORS.SUCCESS)
end)

event.listen("terminate", function()
    addErrorLog("⏻ Процесс завершается! Сохраняем данные...", "WARNING")
    forceSaveData()
    addConsoleLog("✅ Данные сохранены перед завершением", COLORS.SUCCESS)
end)

-- ============================================================
-- ★★★ ВЕБ-ИНТЕГРАЦИЯ ★★★
-- ============================================================

function toJson(val)
    if type(val) == "string" then
        return '"' .. val:gsub('"', '\\"') .. '"'
    elseif type(val) == "number" or type(val) == "boolean" then
        return tostring(val)
    elseif type(val) == "table" then
        local isArray = true
        local count = 0
        for k, _ in pairs(val) do
            if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
                isArray = false
                break
            end
            count = count + 1
        end
        if isArray and count == #val then
            local parts = {}
            for i = 1, #val do
                table.insert(parts, toJson(val[i]))
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local parts = {}
            for k, v in pairs(val) do
                table.insert(parts, '"' .. k .. '":' .. toJson(v))
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    else
        return "null"
    end
end

function sendToWeb(endpoint, jsonData)
    pcall(function()
        internet.request(WEB_URL .. endpoint, jsonData, {
            ["Content-Type"] = "application/json",
            ["Connection"] = "close",
            ["Timeout"] = 3
        })
    end)
end

function parseJSON(json_str)
    if not json_str or json_str == "" then 
        return nil 
    end

    local str = json_str
    local pos = 1
    local len = #str

    local function skipSpace()
        while pos <= len do
            local c = str:sub(pos, pos)
            if c ~= " " and c ~= "\n" and c ~= "\r" and c ~= "\t" then break end
            pos = pos + 1
        end
    end

    local function parseString()
        if str:sub(pos, pos) ~= '"' then 
            return nil 
        end
        
        pos = pos + 1
        local start = pos
        local result = ""
        
        while pos <= len do
            local ch = str:sub(pos, pos)
            if ch == '"' then
                result = result .. str:sub(start, pos-1)
                pos = pos + 1
                return result
            elseif ch == '\\' then
                result = result .. str:sub(start, pos-1)
                pos = pos + 1
                if pos > len then return nil end
                
                local esc = str:sub(pos, pos)
                local map = {
                    ['"'] = '"',
                    ['\\'] = '\\',
                    ['/'] = '/',
                    b = '\b',
                    f = '\f',
                    n = '\n',
                    r = '\r',
                    t = '\t'
                }
                
                if map[esc] then
                    result = result .. map[esc]
                elseif esc == 'u' then
                    local hex = str:sub(pos+1, pos+4)
                    if #hex == 4 then
                        local code = tonumber(hex, 16)
                        if code then
                            result = result .. unicode.char(code)
                            pos = pos + 4
                        end
                    end
                else
                    result = result .. '\\' .. esc
                end
                pos = pos + 1
                start = pos
            else
                pos = pos + 1
            end
        end
        return nil
    end

    function parseNumber()
        local start = pos
        while pos <= len do
            local ch = str:sub(pos, pos)
            if not ch:match("[%d%.%-%+eE]") then break end
            pos = pos + 1
        end
        return tonumber(str:sub(start, pos-1))
    end

    local function parseArray()
        if str:sub(pos, pos) ~= '[' then 
            return nil
        end
        
        pos = pos + 1
        local arr = {}
        skipSpace()
        if str:sub(pos, pos) == ']' then
            pos = pos + 1
            return arr
        end
        
        while true do
            local val = parseValue()
            if val == nil then break end
            table.insert(arr, val)
            skipSpace()
            local ch = str:sub(pos, pos)
            if ch == ',' then 
                pos = pos + 1
            elseif ch == ']' then 
                pos = pos + 1
                break
            else 
                break 
            end
        end
        return arr
    end

    local function parseObject()
        if str:sub(pos, pos) ~= '{' then 
            return nil
        end
        
        pos = pos + 1
        local obj = {}
        skipSpace()
        if str:sub(pos, pos) == '}' then
            pos = pos + 1
            return obj
        end
        
        while true do
            skipSpace()
            local key = parseString()
            if not key then break end
            skipSpace()
            if str:sub(pos, pos) ~= ':' then break end
            pos = pos + 1
            skipSpace()
            local val = parseValue()
            if val == nil then break end
            obj[key] = val
            skipSpace()
            local ch = str:sub(pos, pos)
            if ch == ',' then 
                pos = pos + 1
            elseif ch == '}' then 
                pos = pos + 1
                break
            else 
                break 
            end
        end
        return obj
    end

    function parseValue()
        skipSpace()
        if pos > len then 
            return nil
        end
        local ch = str:sub(pos, pos)

        if ch == '"' then
            return parseString()
        elseif ch == '{' then
            return parseObject()
        elseif ch == '[' then
            return parseArray()
        elseif ch == 't' and str:sub(pos, pos+3) == 'true' then
            pos = pos + 4
            return true
        elseif ch == 'f' and str:sub(pos, pos+4) == 'false' then
            pos = pos + 5
            return false
        elseif ch == 'n' and str:sub(pos, pos+3) == 'null' then
            pos = pos + 4
            return nil
        elseif ch:match("[%d%-]") then
            return parseNumber()
        end
        return nil
    end

    skipSpace()
    return parseValue()
end

function sendErrorToWeb(error_msg, level)
    level = level or "ERROR"
    local timestamp = getRealTimeHM()
    sendToWeb("/api/error_log", toJson({
        error = error_msg,
        level = level,
        time = timestamp
    }))
end

function safeCall(func, ...)
    local args = {...}
    local ok, err = pcall(func, table.unpack(args))
    if not ok then
        local debugInfo = debug.getinfo(func, "l")
        local line = debugInfo and debugInfo.currentline or "?"
        local errorMsg = "ОШИБКА в строке " .. line .. ": " .. tostring(err)
        print(errorMsg)
        writeErrorLog(errorMsg)
        if type(err) == "string" and err:find("nil") then
            writeErrorLog("  → Возможно, переменная равна nil")
        end
        return false, err
    end
    return true, ok
end

event.ignore("interrupted", function() end)
event.ignore("terminate", function() end)

-- ============================================================
-- ★★★ БАЗОВЫЕ ФУНКЦИИ UI ★★★
-- ============================================================

function clear()
    gpu.setBackground(COLORS.BG_MAIN)
    gpu.fill(1, 1, 80, 25, " ")
end

function drawCenteredText(y, text, color)
    if not text then
        text = ""
    end
    gpu.setForeground(color or COLORS.TEXT_MAIN)
    local x = math.floor((80 - unicode.len(text)) / 2) + 1
    gpu.set(x, y, text)
end

function drawButton(btn)
    if not btn then return end
    gpu.setBackground(btn.bg)
    gpu.fill(btn.x, btn.y, btn.xs, btn.ys, " ")
    gpu.setForeground(btn.fg)
    local text = btn.text or ""
    local textX = btn.x + math.floor((btn.xs - unicode.len(text)) / 2)
    local textY = btn.y + math.floor((btn.ys - 1) / 2)
    gpu.set(textX, textY, text)
    gpu.setBackground(COLORS.BG_MAIN)
end

function drawFlexButton(btn)
    if not btn then return end
    gpu.setBackground(btn.bg)
    gpu.fill(btn.x, btn.y, btn.xs, btn.ys, " ")
    gpu.setForeground(btn.fg)
    local text = btn.text or ""
    local textX = btn.x + math.floor((btn.xs - unicode.len(text)) / 2)
    local textY = btn.y + math.floor((btn.ys - 1) / 2)
    gpu.set(textX, textY, text)
    gpu.setBackground(COLORS.BG_MAIN)
end

function drawPopupBorder(x, y, w, h, color)
    gpu.setForeground(color or COLORS.ACCENT_SECONDARY)
    gpu.fill(x, y, w, 1, "─")
    gpu.fill(x, y + h - 1, w, 1, "─")
    for i = 1, h - 2 do
        gpu.set(x, y + i, "│")
        gpu.set(x + w - 1, y + i, "│")
    end
    gpu.set(x, y, "┌")
    gpu.set(x + w - 1, y, "┐")
    gpu.set(x, y + h - 1, "└")
    gpu.set(x + w - 1, y + h - 1, "┘")
end

function drawScreenBorder()
    local left = 1
    local right = 80
    local top = 1
    local bottom = 24
    gpu.setForeground(COLORS.ACCENT_SECONDARY)
    gpu.fill(left, top, right - left + 1, 1, "─")
    gpu.fill(left, bottom, right - left + 1, 1, "─")
    for y = top + 1, bottom - 1 do
        gpu.set(left, y, "│")
        gpu.set(right, y, "│")
    end
    gpu.set(left, top, "┌")
    gpu.set(right, top, "┐")
    gpu.set(left, bottom, "└")
    gpu.set(right, bottom, "┘")
end

function drawTempMessage()
    if tempMessage ~= "" and tempMessage then
        gpu.setBackground(COLORS.BG_MAIN)
        gpu.fill(1, 25, 80, 1, " ")
        gpu.setForeground(COLORS.SUCCESS)
        local x = math.floor((80 - unicode.len(tempMessage)) / 2) + 1
        gpu.set(x, 25, tempMessage)
    else
        gpu.setBackground(COLORS.BG_MAIN)
        gpu.fill(1, 25, 80, 1, " ")
    end
end

function drawTextMessage(msg, color)
    if msg and msg ~= "" then
        gpu.setBackground(COLORS.BG_MAIN)
        gpu.fill(1, 25, 80, 1, " ")
        gpu.setForeground(color or COLORS.SUCCESS)
        local x = math.floor((80 - unicode.len(msg)) / 2) + 1
        gpu.set(x, 25, msg)
    else
        gpu.setBackground(COLORS.BG_MAIN)
        gpu.fill(1, 25, 80, 1, " ")
    end
end

function drawAccountLoading()
    clear()
    drawScreenBorder()
    drawCenteredText(12, "Загрузка данных аккаунта...", COLORS.TEXT_MAIN)
    local backButton = {
        text = "[ НАЗАД ]",
        x = 37, y = 24,
        xs = unicode.len("[ НАЗАД ]") + 2,
        ys = 1,
        bg = COLORS.BG_BUTTON,
        fg = COLORS.ACCENT_SECONDARY
    }
    drawFlexButton(backButton)
    drawTempMessage()
end

function isButtonClicked(btn, x, y)
    if not btn then return false end
    return y >= btn.y and y < btn.y + btn.ys and x >= btn.x and x < btn.x + btn.xs
end

-- ============================================================
-- ★★★ УПРАВЛЕНИЕ ПЕРЕРИСОВКОЙ ★★★
-- ============================================================

function markDirty()
    guiDirty = true
    if not renderTimer then
        renderTimer = event.timer(0.1, function()
            renderTimer = nil
            if guiDirty then
                renderCurrentScreen()
                guiDirty = false
            end
            return false
        end)
    end
end

function forceRender()
    guiDirty = true
    if renderTimer then
        event.cancel(renderTimer)
        renderTimer = nil
    end
    renderCurrentScreen()
    guiDirty = false
end

function renderCurrentScreen()
    if showInsufficientPopup then
        drawInsufficientPopup()
        drawTempMessage()
        return
    end
    if showSellPopup then
        drawSellPopup()
        drawTempMessage()
        return
    end
    if showPartialPopup then
        drawPartialPopup()
        drawTempMessage()
        return
    end
    if showInventoryFullPopup then
        drawInventoryFullPopup()
        drawTempMessage()
        return
    end
    if currentScreen == "welcome" then
        drawWelcomeScreen()
    elseif currentScreen == "menu" then
        drawMainMenu()
    elseif currentScreen == "shop" then
        drawShopMenu()
    elseif currentScreen == "shop_buy" or currentScreen == "shop_sell" then
        drawBuyStatic()
        drawBuyItemsList()
        drawBuyButtons()
    elseif currentScreen == "sell_scan" then
        drawSellScanScreen()
    elseif currentScreen == "purchase" then
        drawPurchaseScreen()
    elseif currentScreen == "account" then
        drawAccount({balance=coinBalance, emaBalance=emaBalance, transactions=playerTransactions, regDate=playerRegDate, agreed=playerAgreed})
    elseif currentScreen == "report" then
        drawReportScreen()
    elseif currentScreen == "feedbacks" then
        drawFeedbacksList()
    elseif currentScreen == "feedback_input" then
        drawFeedbackInputScreen()
    elseif currentScreen == "agreement" then
        if type(drawAgreementScreen) == "function" then
            drawAgreementScreen()
        end
    elseif currentScreen == "auth_popup" then
        if not qrPopupActive then
            showAuthPopup()
        end
    elseif currentScreen == "qr_popup" then
        -- Ничего не делаем
    end
    drawTempMessage()
end

-- ============================================================
-- ★★★ МЕНЕДЖЕР ТАЙМЕРОВ ★★★
-- ============================================================

timers = {}

function createTimer(interval, callback, shouldRepeat)
    local times = shouldRepeat and math.huge or 1
    local timerId = event.timer(interval, callback, times)
    table.insert(timers, timerId)
    return timerId
end

function clearAllTimers()
    for _, id in ipairs(timers) do
        pcall(event.cancel, id)
    end
    timers = {}
end

function lockTransactions()
    TRANSACTION_LOCK = true
    writeDebugLog("🔒 Транзакции заблокированы")
end

function unlockTransactions()
    TRANSACTION_LOCK = false
    writeDebugLog("🔓 Транзакции разблокированы")
    event.timer(0.5, function()
        if not TRANSACTION_LOCK then
            writeDebugLog("📡 Быстрая проверка команд после транзакции")
            checkWebCommands()
        end
        return false
    end)
end

-- ============================================================
-- ★★★ БЕЗОПАСНЫЙ ВЫХОД ★★★
-- ============================================================

function safeExit()
    writeDebugLog("🚪 Безопасный выход")
    
    qrPopupActive = false
    
    isShuttingDown = true
    
    if currentPlayer ~= nil then
        addPlayerLog("Выход: " .. currentPlayer, "LEAVE")
        writeDebugLog("👤 Выход игрока: " .. tostring(currentPlayer))
    else
        writeDebugLog("🚪 Выход без игрока")
    end
    
    currentPlayer = nil
    currentToken = nil
    alreadyAuthorized = false
    pimOwner = nil
    currentScreen = "welcome"
    authCodeInput = ""
    boundPlayer = nil
    
    if TRANSACTION_LOCK then
        TRANSACTION_LOCK = false
        writeDebugLog("🔓 Блокировка сброшена при выходе")
    end
    
    selectedItem = nil
    hoveredIndex = 0
    selectedIndex = 0
    filteredItems = {}
    shopSearch = ""
    searchActive = false
    searchInput = ""
    purchaseItem = nil
    purchaseQuantity = 1
    sellConfirmItem = nil
    foundAmount = 0
    showSellPopup = false
    showPartialPopup = false
    showInsufficientPopup = false
    showInventoryFullPopup = false
    listScroll = 1
    horizontalScroll = 1
    tempMessage = ""
    
    if tempMessageTimer then
        event.cancel(tempMessageTimer)
        tempMessageTimer = nil
    end
    
    pcall(updateSelectorDisplay, nil)
    pcall(selector.setSlot, 0, nil)
    pcall(selector.setSlot, 1, nil)
    
    clearAllTimers()
    writeDebugLog("⏹️ Все таймеры остановлены")
    
    drawWelcomeScreen()
    writeDebugLog("🖥️ Экран приветствия отображён")
    
    asyncSaveData()
    writeDebugLog("💾 Запущено фоновое сохранение данных")
    
    isShuttingDown = false
    
    writeDebugLog("✅ Безопасный выход завершён")
    addErrorLog("🔴 Терминал #1 (PIM MARKET) остановлен", "INFO")
end

-- ============================================================
-- ★★★ НОВАЯ СИСТЕМА КЕШИРОВАНИЯ ★★★
-- ============================================================

function loadAllDataFromHost()
    writeDebugLog("📡 Загрузка всех данных с хостинга...")
    if isSyncing then
        writeDebugLog("⏳ Уже выполняется синхронизация")
        return false
    end
    isSyncing = true
    
    local function fetchData(endpoint, callback)
        local success, response = pcall(function()
            return internet.request(WEB_URL .. endpoint, nil, {
                ["Connection"] = "close",
                ["Timeout"] = 5
            })
        end)
        if success and response then
            local body = ""
            for chunk in response do
                body = body .. chunk
            end
            local data = parseJSON(body)
            if data then
                callback(data)
                return true
            end
        end
        return false
    end
    
    -- Загружаем игроков
    fetchData("/api/players", function(data)
        if data.players then
            cache_players = {}
            for _, p in ipairs(data.players) do
                cache_players[p.name] = p
            end
            writeDebugLog("✅ Загружено " .. #data.players .. " игроков")
        end
    end)
    
    -- Загружаем товары покупки
    fetchData("/api/buy_items", function(data)
        if data.items then
            cache_buy_items = data.items
            writeDebugLog("✅ Загружено " .. #data.items .. " товаров покупки")
        end
    end)
    
    -- Загружаем товары продажи
    fetchData("/api/sell_items", function(data)
        if data.items then
            cache_sell_items = data.items
            writeDebugLog("✅ Загружено " .. #data.items .. " товаров продажи")
        end
    end)
    
    -- Загружаем админов
    fetchData("/api/admins", function(data)
        if data.admins then
            cache_admins = data.admins
            writeDebugLog("✅ Загружено " .. #cache_admins .. " админов")
        end
    end)
    
    -- Загружаем баны
    fetchData("/api/bans", function(data)
        if data.bans then
            cache_bans = {}
            for _, ban in ipairs(data.bans) do
                cache_bans[ban.name] = ban
            end
            writeDebugLog("✅ Загружено " .. #data.bans .. " банов")
        end
    end)
    
    -- Загружаем отзывы
    fetchData("/api/feedbacks", function(data)
        if data.feedbacks then
            cache_feedbacks = data.feedbacks
            writeDebugLog("✅ Загружено " .. #cache_feedbacks .. " отзывов")
        end
    end)
    
    -- Загружаем репорты
    fetchData("/api/reports", function(data)
        if data.reports then
            cache_reports = data.reports
            writeDebugLog("✅ Загружено " .. #cache_reports .. " репортов")
        end
    end)
    
    -- Загружаем статус магазина
    fetchData("/api/shop_status", function(data)
        if data.paused ~= nil then
            shopPaused = data.paused
            cache_shop_paused = data.paused
            writeDebugLog("✅ Статус магазина: " .. (shopPaused and "ЗАКРЫТ" or "ОТКРЫТ"))
        end
    end)
    
    last_cache_update = os.time()
    isSyncing = false
    writeDebugLog("✅ Все данные загружены с хостинга!")
    return true
end

function updateCache()
    local now = os.time()
    if now - last_cache_update < CACHE_UPDATE_INTERVAL then
        return
    end
    if isSyncing then
        return
    end
    
    -- Быстрое обновление только товаров
    local success, response = pcall(function()
        return internet.request(WEB_URL .. "/api/buy_items", nil, {
            ["Connection"] = "close",
            ["Timeout"] = 3
        })
    end)
    
    if success and response then
        local body = ""
        for chunk in response do
            body = body .. chunk
        end
        local data = parseJSON(body)
        if data and data.items then
            cache_buy_items = data.items
            writeDebugLog("🔄 Обновлены товары покупки: " .. #cache_buy_items)
        end
    end
    
    local success2, response2 = pcall(function()
        return internet.request(WEB_URL .. "/api/sell_items", nil, {
            ["Connection"] = "close",
            ["Timeout"] = 3
        })
    end)
    
    if success2 and response2 then
        local body = ""
        for chunk in response2 do
            body = body .. chunk
        end
        local data = parseJSON(body)
        if data and data.items then
            cache_sell_items = data.items
            writeDebugLog("🔄 Обновлены товары продажи: " .. #cache_sell_items)
        end
    end
    
    -- Обновляем статус магазина
    local success3, response3 = pcall(function()
        return internet.request(WEB_URL .. "/api/shop_status", nil, {
            ["Connection"] = "close",
            ["Timeout"] = 3
        })
    end)
    
    if success3 and response3 then
        local body = ""
        for chunk in response3 do
            body = body .. chunk
        end
        local data = parseJSON(body)
        if data and data.paused ~= nil then
            shopPaused = data.paused
            cache_shop_paused = data.paused
        end
    end
    
    last_cache_update = now
end

function getPlayerFromCache(name)
    return cache_players[name]
end

function updatePlayerInCache(name, data)
    if cache_players[name] then
        for k, v in pairs(data) do
            cache_players[name][k] = v
        end
        return true
    end
    return false
end

-- ============================================================
-- ★★★ БУФЕР ТРАНЗАКЦИЙ ★★★
-- ============================================================

function saveTransactionBuffer()
    local file = io.open(BUFFER_FILE, "w")
    if file then
        file:write(serialization.serialize(transaction_buffer))
        file:close()
        return true
    end
    return false
end

function loadTransactionBuffer()
    if fs.exists(BUFFER_FILE) then
        local ok, data = pcall(dofile, BUFFER_FILE)
        if ok and type(data) == "table" then
            transaction_buffer = data
            writeDebugLog("📂 Загружен буфер транзакций: " .. #transaction_buffer .. " записей")
            return true
        end
    end
    transaction_buffer = {}
    return false
end

function flushTransactionBuffer()
    if #transaction_buffer == 0 then
        return
    end
    
    writeDebugLog("📤 Отправка буфера транзакций (" .. #transaction_buffer .. " записей)")
    
    local success, response = pcall(function()
        return internet.request(WEB_URL .. "/api/transactions_batch", toJson({
            transactions = transaction_buffer
        }), {
            ["Content-Type"] = "application/json",
            ["Connection"] = "close",
            ["Timeout"] = 10
        })
    end)
    
    if success and response then
        local body = ""
        for chunk in response do
            body = body .. chunk
        end
        local data = parseJSON(body)
        if data and data.status == "ok" then
            transaction_buffer = {}
            saveTransactionBuffer()
            writeDebugLog("✅ Буфер транзакций отправлен")
            return true
        end
    end
    
    writeErrorLog("⚠️ Не удалось отправить буфер транзакций")
    return false
end

function sendTransactionToHost(type, playerName, item, qty, value_coin, value_ema)
    writeDebugLog("📤 Отправка транзакции на хостинг: " .. type)
    
    local transaction = {
        type = type,
        player = playerName,
        item = item,
        qty = qty,
        coin = value_coin or 0,
        ema = value_ema or 0,
        time = getRealTimeString()
    }
    
    local success, response = pcall(function()
        return internet.request(WEB_URL .. "/api/transaction", toJson(transaction), {
            ["Content-Type"] = "application/json",
            ["Connection"] = "close",
            ["Timeout"] = 5
        })
    end)
    
    if success and response then
        local body = ""
        for chunk in response do
            body = body .. chunk
        end
        local data = parseJSON(body)
        if data and data.status == "ok" then
            writeDebugLog("✅ Транзакция отправлена на хостинг")
            return true
        else
            writeErrorLog("❌ Ошибка отправки транзакции: " .. tostring(body))
        end
    else
        writeErrorLog("❌ Ошибка соединения при отправке транзакции")
    end
    
    -- Если не удалось - сохраняем в буфер
    table.insert(transaction_buffer, transaction)
    saveTransactionBuffer()
    writeDebugLog("💾 Транзакция сохранена в буфер")
    return false
end

-- ============================================================
-- ★★★ НОВАЯ СИСТЕМА ТРАНЗАКЦИЙ ★★★
-- ============================================================

function addTransaction(type, playerName, item, qty, value_coin, value_ema)
    writeDebugFile(">>> addTransaction()")
    writeDebugFile("   type=" .. tostring(type))
    writeDebugFile("   playerName=" .. tostring(playerName))
    writeDebugFile("   item=" .. tostring(item))
    writeDebugFile("   qty=" .. tostring(qty))
    writeDebugFile("   value_coin=" .. tostring(value_coin))
    writeDebugFile("   value_ema=" .. tostring(value_ema))
    
    -- Отправляем на хостинг
    local sent = sendTransactionToHost(type, playerName, item, qty, value_coin, value_ema)
    
    -- Обновляем локальный кеш
    local player = cache_players[playerName]
    if player then
        if type == "buy" then
            player.balance = (player.balance or 0) - (value_coin or 0)
            player.emaBalance = (player.emaBalance or 0) - (value_ema or 0)
        else
            player.balance = (player.balance or 0) + (value_coin or 0)
            player.emaBalance = (player.emaBalance or 0) + (value_ema or 0)
        end
        if player.balance < 0 then player.balance = 0 end
        if player.emaBalance < 0 then player.emaBalance = 0 end
        player.transactions = (player.transactions or 0) + 1
        writeDebugLog("   ✅ Кеш обновлён: Coin=" .. player.balance .. ", EMA=" .. player.emaBalance)
    else
        writeErrorLog("   ❌ Игрок не найден в кеше: " .. tostring(playerName))
    end
    
    -- Лог
    local currency = ""
    if value_coin > 0 and value_ema > 0 then
        currency = string.format("%.2f₵ + %.2f۞", value_coin, value_ema)
    elseif value_coin > 0 then
        currency = string.format("%.2f₵", value_coin)
    elseif value_ema > 0 then
        currency = string.format("%.2f۞", value_ema)
    end
    local action = type == "buy" and "Купил" or "Продал"
    addTransactionLog(string.format("%s %s: %s x%d за %s", action, playerName, item, qty, currency), type == "buy" and "BUY" or "SELL")
    
    -- Обновляем UI
    if currentPlayer == playerName then
        coinBalance = cache_players[playerName] and cache_players[playerName].balance or 0
        emaBalance = cache_players[playerName] and cache_players[playerName].emaBalance or 0
        markDirty()
        writeDebugLog("   ✅ UI обновлён: Coin=" .. coinBalance .. ", EMA=" .. emaBalance)
    end
    
    return sent
end

-- ============================================================
-- ★★★ СИСТЕМНАЯ ИНФОРМАЦИЯ ★★★
-- ============================================================

function formatUptime(seconds)
    if not seconds or seconds < 0 then 
        return "—" 
    end 
    
    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    
    if days > 0 then
        return string.format("%dд %dч %dм", days, hours, minutes)
    elseif hours > 0 then
        return string.format("%dч %dм", hours, minutes)
    else
        return string.format("%dм", math.max(1, minutes))
    end
end

function getSystemInfo()
    local info = {}
    
    local uptime = computer.uptime()
    info.uptime_seconds = uptime
    info.uptime_human = formatUptime(uptime)
    
    local realTime = getRealTimestamp()
    local bootTime = realTime - uptime
    info.boot_time = os.date("%d.%m.%Y %H:%M:%S", bootTime)
    
    info.cpu_load = 0
    info.cpu_percent = "N/A"
    if computer.getCPUUsage then
        local ok, cpu = pcall(computer.getCPUUsage)
        if ok and cpu and type(cpu) == "number" then
            info.cpu_load = cpu
            info.cpu_percent = string.format("%.1f%%", cpu * 100)
        end
    end
    
    info.memory_total = 0
    info.memory_used = 0
    info.memory_free = 0
    info.memory_used_mb = "N/A"
    info.memory_total_mb = "N/A"
    info.memory_human = "N/A"
    
    if computer.totalMemory then
        local ok, total = pcall(computer.totalMemory)
        if ok and total and type(total) == "number" then
            info.memory_total = total
            info.memory_total_mb = string.format("%.1f MB", total / 1024 / 1024)
        end
    end
    
    if computer.freeMemory then
        local ok, free = pcall(computer.freeMemory)
        if ok and free and type(free) == "number" then
            info.memory_free = free
            if info.memory_total > 0 then
                info.memory_used = info.memory_total - free
                info.memory_used_mb = string.format("%.1f MB", info.memory_used / 1024 / 1024)
                info.memory_human = info.memory_used_mb .. " / " .. info.memory_total_mb
            end
        end
    end
    
    info.disk_used_percent = "N/A"
    local fs = require("filesystem")
    local paths = {"/", "/home", "/tmp", "/lib"}
    for _, path in ipairs(paths) do
        local ok1, free = pcall(fs.space, path)
        local ok2, total = pcall(fs.total, path)
        if ok1 and ok2 and total and type(total) == "number" and total > 0 then
            if free and type(free) == "number" then
                info.disk_used_percent = string.format("%.1f%%", (total - free) / total * 100)
                break
            end
        end
    end
    
    info.ip = "N/A"
    if computer.getLocalIP then
        local ok, ip = pcall(computer.getLocalIP)
        if ok and ip then
            info.ip = ip
        end
    end
    
    info.current_player = "—"
    local pimAddr = getPimAddr()
    if pimAddr then
        local pim = component.proxy(pimAddr)
        local player = nil
        
        if pim.getPlayer then
            local ok, result = pcall(pim.getPlayer, pim)
            if ok and result then
                player = result
            end
        end
        
        if not player and pim.getPlayerName then
            local ok, result = pcall(pim.getPlayerName, pim)
            if ok and result then
                player = result
            end
        end
        
        if not player and pim.getUsername then
            local ok, result = pcall(pim.getUsername, pim)
            if ok and result then
                player = result
            end
        end
        
        if not player then
            local ok, result = pcall(function()
                return pim.player
            end)
            if ok and result then
                player = result
            end
        end
        
        if player and player ~= "" then
            info.current_player = player
        end
    end
    
    info.real_time = getRealTimeString()
    info.online = cache_online or 0
    info.paused = shopPaused
    
    return info
end

function sendStats()
    writeDebugLog("📊 sendStats() начат")
    
    local now = os.time()
    if now - lastSentTime < MIN_SEND_INTERVAL then
        writeDebugLog("⏳ Прошло " .. (now - lastSentTime) .. "с, минимальный интервал " .. MIN_SEND_INTERVAL .. "с, пропускаем")
        return
    end
    
    lastSentTime = now
    
    local sysInfo = getSystemInfo()
    
    local playerList = {}
    local totalBalance = 0
    
    for name, data in pairs(cache_players) do
        local bal = (data.balance or 0) + (data.emaBalance or 0)
        totalBalance = totalBalance + bal
        
        table.insert(playerList, {
            name = name,
            balance = data.balance or 0,
            emaBalance = data.emaBalance or 0,
            transactions = data.transactions or 0,
            banned = data.banned or false,
            site_user = data.site_user
        })
    end
    
    local payload = {
        players = playerList,
        admins = cache_admins,
        total = #playerList,
        total_balance = totalBalance,
        online = cache_online or 0,
        paused = shopPaused,
        buy_items = cache_buy_items,
        sell_items = cache_sell_items,
        system_info = sysInfo
    }
    
    local jsonData = toJson(payload)
    writeDebugLog("📤 Отправлены данные: " .. #playerList .. " игроков")
    
    sendToWeb("/api/update", jsonData)
end

-- ============================================================
-- ★★★ ФУНКЦИИ ДЛЯ РАБОТЫ С PIM ★★★
-- ============================================================

function getPimAddr()
    local success, result = pcall(function()
        for addr in component.list("pim") do
            return addr
        end
    end)
    if success and result then
        return result
    end
    return nil
end

function getPlayerOnPim()
    local pimAddr = getPimAddr()
    if not pimAddr then 
        return nil
    end
    
    local pim = component.proxy(pimAddr)
    local player = nil
    
    if pim.getPlayer then
        local ok, result = pcall(pim.getPlayer, pim)
        if ok and result and result ~= "" then
            player = result
        end
    end
    
    if not player and pim.getPlayerName then
        local ok, result = pcall(pim.getPlayerName, pim)
        if ok and result and result ~= "" then
            player = result
        end
    end
    
    if not player and pim.getUsername then
        local ok, result = pcall(pim.getUsername, pim)
        if ok and result and result ~= "" then
            player = result
        end
    end
    
    if not player then
        local ok, result = pcall(function()
            return pim.player
        end)
        if ok and result and result ~= "" then
            player = result
        end
    end
    
    return player
end

function isPimOwner(playerName)
    if not playerName or not pimOwner then 
        return false
    end
    return playerName == pimOwner
end

selector = nil
for addr in component.list("openperipheral_selector") do
    selector = component.proxy(addr)
    break
end
if not selector then
    for addr in component.list("item_selector") do
        selector = component.proxy(addr)
        break
    end
end

function updateSelectorDisplay(item)
    if not selector then 
        return
    end
    
    if not item then
        pcall(selector.setSlot, 0, nil)
        pcall(selector.setSlot, 1, nil)
        return
    end
    
    local raw = item.internalName or item.name or item.displayName
    if not raw then 
        return
    end
    
    local id = raw
    if not id:find(":") then
        id = "minecraft:" .. id
    end
    local dmg = item.damage or 0
    local stack = { id = id, dmg = dmg }
    pcall(selector.setSlot, 0, stack)
    pcall(selector.setSlot, 1, stack)
end

function syncCurrentPlayer()
    if not currentPlayer then 
        return
    end
    
    writeDebugLog("🔄 Синхронизация игрока: " .. currentPlayer)
    
    local player = cache_players[currentPlayer]
    if player then
        coinBalance = player.balance or 0
        emaBalance = player.emaBalance or 0
        playerTransactions = player.transactions or 0
        playerRegDate = player.regDate or ""
        playerAgreed = player.agreed or false
        playerHasFeedback = player.hasFeedback or false
        
        writeDebugLog("✅ Синхронизирован: Coin=" .. coinBalance .. ", EMA=" .. emaBalance)
        return true
    end
    
    writeDebugLog("⚠️ Игрок не найден при синхронизации: " .. currentPlayer)
    return false
end

function forceUpdateBindingStatus()
    if not currentPlayer then
        return
    end
    bindingCache.lastCheck = 0
    bindingCache.isBound = false
    bindingCache.pendingUpdate = false
    getBindingStatus()
end

function sortableName(name)
    if not name then return "" end
    local lower = string.lower(name)
    local result = lower:gsub("(%d+)", function(d)
        return string.format("%08d", tonumber(d))
    end)
    return result
end

function toLowerCase(str)
    if not str then return "" end
    str = string.lower(str)
    str = str:gsub("А", "а"):gsub("Б", "б"):gsub("В", "в"):gsub("Г", "г"):gsub("Д", "д")
    str = str:gsub("Е", "е"):gsub("Ё", "ё"):gsub("Ж", "ж"):gsub("З", "з"):gsub("И", "и")
    str = str:gsub("Й", "й"):gsub("К", "к"):gsub("Л", "л"):gsub("М", "м"):gsub("Н", "н")
    str = str:gsub("О", "о"):gsub("П", "п"):gsub("Р", "р"):gsub("С", "с"):gsub("Т", "т")
    str = str:gsub("У", "у"):gsub("Ф", "ф"):gsub("Х", "х"):gsub("Ц", "ц"):gsub("Ч", "ч")
    str = str:gsub("Ш", "ш"):gsub("Щ", "щ"):gsub("Ъ", "ъ"):gsub("Ы", "ы"):gsub("Ь", "ь")
    str = str:gsub("Э", "э"):gsub("Ю", "ю"):gsub("Я", "я")
    return str
end

function canSendReport()
    if not lastReportTime then 
        return true
    end
    
    local now = getRealTimestamp()
    local reportDate = os.date("*t", lastReportTime)
    local nowDate = os.date("*t", now)
    if reportDate.day ~= nowDate.day or reportDate.month ~= nowDate.month or reportDate.year ~= nowDate.year then
        return true
    end
    return false
end

function getActualItemQuantity(internalName, damage)
    if not component.isAvailable("me_interface") then 
        return 0
    end
    
    local me = component.me_interface
    local items = me.getItemsInNetwork()
    local total = 0
    for _, meItem in ipairs(items) do
        if meItem.name == internalName and (meItem.damage or 0) == (damage or 0) then
            total = total + (meItem.size or 0)
        end
    end
    return total
end

function showTempMessage(msg, duration)
    writeDebugLog("showTempMessage: " .. tostring(msg))
    tempMessage = msg or ""
    if tempMessageTimer then
        event.cancel(tempMessageTimer)
    end
    tempMessageTimer = event.timer(duration or 2, function()
        tempMessage = ""
        tempMessageTimer = nil
        markDirty()
    end)
    drawTempMessage()
end

function namesMatch(name1, name2)
    if not name1 or not name2 then 
        return false 
    end
    
    if name1 == name2 then 
        return true 
    end
    
    local function normalizeName(n)
        if not n then return "" end
        local lastColon = n:match(".*:([^:]+)$")
        return lastColon or n
    end
    
    return normalizeName(name1) == normalizeName(name2)
end

function scanPlayerInventory(targetName, targetDamage)
    writeDebugLog("scanPlayerInventory: " .. tostring(targetName))
    local pimAddr = getPimAddr()
    if not pimAddr then 
        writeErrorLog("❌ PIM адрес не найден!")
        return 0 
    end
    targetDamage = targetDamage or 0
    local total = 0
    for slot = 1, 36 do
        local stack = component.invoke(pimAddr, "getStackInSlot", slot)
        if stack then
            local qty = stack.size or stack.qty or 0
            if qty > 0 then
                local rawName = stack.name or stack.label or ""
                local cleanName = rawName:gsub("§.", "")
                local damage = stack.damage or 0
                if namesMatch(cleanName, targetName) and damage == targetDamage then
                    total = total + qty
                end
            end
        end
    end
    writeDebugLog("scanPlayerInventory: найдено " .. total)
    return total
end

function extractToME(targetName, amount, targetDamage)
    writeDebugLog("extractToME: " .. tostring(targetName) .. " x" .. tostring(amount))
    local pimAddr = getPimAddr() 
    if not pimAddr or amount <= 0 then 
        return 0
    end
    
    targetDamage = targetDamage or 0
    local extracted = 0
    for slot = 1, 36 do
        if extracted >= amount then
            break
        end
        
        local stack = component.invoke(pimAddr, "getStackInSlot", slot)
        if stack then
            local qty = stack.size or stack.qty or 0
            if qty > 0 then
                local rawName = stack.name or stack.label or ""
                local cleanName = rawName:gsub("§.", "")
                local damage = stack.damage or 0
                if namesMatch(cleanName, targetName) and damage == targetDamage then
                    local toTake = math.min(qty, amount - extracted)
                    if toTake > 0 then
                        local moved = component.invoke(pimAddr, "pushItem", PUSH_DIRECTION, slot, toTake)
                        if type(moved) == "number" and moved > 0 then
                            extracted = extracted + moved
                        end
                    end
                end
            end
        end
    end
    writeDebugLog("extractToME: извлечено " .. extracted)
    return extracted
end

-- ============================================================
-- ★★★ ФУНКЦИИ ДЛЯ ТОВАРОВ ★★★
-- ============================================================

function loadBuyItems(forceRefresh)
    writeDebugLog("loadBuyItems()" .. (forceRefresh and " (принудительное обновление)" or ""))
    if forceRefresh then
        updateCache()
    end
    
    shopItems = {}
    for _, item in ipairs(cache_buy_items) do
        local actualQty = getActualItemQuantity(item.internalName, item.damage or 0)
        table.insert(shopItems, {
            internalName = item.internalName,
            displayName = item.displayName or item.internalName,
            qty = actualQty,
            priceCoin = item.price_coin or 0,
            priceEma = item.price_ema or 0,
            damage = item.damage or 0,
            canBuy = true
        })
    end
    writeDebugLog("loadBuyItems: загружено " .. #shopItems .. " товаров")
end

function loadSellItems()
    writeDebugLog("loadSellItems()")
    shopItems = {}
    for _, item in ipairs(cache_sell_items) do
        table.insert(shopItems, {
            displayName = item.displayName or item.internalName,
            internalName = item.internalName,
            qty = item.qty or 0,
            price = item.price or 0,
            damage = item.damage or 0
        })
    end
    writeDebugLog("loadSellItems: загружено " .. #shopItems .. " товаров")
end

-- ============================================================
-- ★★★ UI МАГАЗИНА ★★★
-- ============================================================

function drawBalanceLine(x, y)
    writeDebugLog("drawBalanceLine: x=" .. tostring(x) .. ", y=" .. tostring(y))
    
    local coin = coinBalance or 0.0
    local ema = emaBalance or 0.0
    
    if coinBalance == nil then
        writeErrorLog("⚠️ coinBalance = nil в drawBalanceLine, установлен 0")
        coinBalance = 0.0
    end
    if emaBalance == nil then
        writeErrorLog("⚠️ emaBalance = nil в drawBalanceLine, установлен 0")
        emaBalance = 0.0
    end
    
    gpu.setForeground(COLORS.WHITE)
    gpu.set(x, y, "Баланс: ")
    local coinStr = string.format("%.2f", coin) .. " Coina ₵"
    gpu.setForeground(COLORS.ACCENT_MAIN)
    gpu.set(x + unicode.len("Баланс: "), y, coinStr)
    gpu.setForeground(COLORS.WHITE)
    gpu.set(x + unicode.len("Баланс: ") + unicode.len(coinStr), y, " | ")
    local emaStr = "ЭМЫ: " .. string.format("%.2f", ema) .. " ۞"
    gpu.setForeground(COLORS.TOMATO)
    gpu.set(x + unicode.len("Баланс: ") + unicode.len(coinStr) + unicode.len(" | "), y, emaStr)
end

function redrawSearchField()
    local searchX = 42
    local searchText = ""
    if searchActive then
        searchText = (searchInput or "") .. "_"
    else
        searchText = (shopSearch == "" and "Поиск..." or (shopSearch or ""))
    end
    gpu.setBackground(COLORS.BG_BUTTON)
    gpu.fill(searchX, 3, 23, 1, " ")
    gpu.setForeground(COLORS.ACCENT_MAIN)
    gpu.set(searchX + 1, 3, unicode.sub(searchText, 1, 21))

    local clearText = "[ СТЕРЕТЬ ]"
    local clearWidth = unicode.len(clearText) + 2
    local clearX = searchX + 23 + 1
    gpu.setBackground(COLORS.ERROR)
    gpu.fill(clearX, 3, clearWidth, 1, " ")
    gpu.setForeground(COLORS.ACCENT_SECONDARY)
    local textX = clearX + math.floor((clearWidth - unicode.len(clearText)) / 2)
    gpu.set(textX, 3, clearText)
    gpu.setBackground(COLORS.BG_MAIN)
end

function drawBuyStatic()
    writeDebugLog("drawBuyStatic()")
    clear()
    drawScreenBorder()
    drawBalanceLine(3, 1)

    if currentShopMode == "buy" then
        gpu.setForeground(COLORS.ACCENT_SECONDARY)
        gpu.set(3, 3, "Магазин продаёт")
    else
        gpu.setForeground(COLORS.ACCENT_SECONDARY)
        gpu.set(3, 3, "Магазин покупает")
    end

    redrawSearchField()

    gpu.setBackground(COLORS.BG_BUTTON)
    gpu.fill(2, 5, 76, 1, " ")
    gpu.setForeground(COLORS.TEXT_BRIGHT)
    gpu.set(3, 5, "Название")
    gpu.set(42, 5, "Кол-во")
    if currentShopMode == "buy" then
        gpu.set(55, 5, "Coina")
        gpu.set(67, 5, "ЭМЫ")
    else
        gpu.set(65, 5, "Цена")
    end
    gpu.setBackground(COLORS.BG_MAIN)

    drawTempMessage()
end

function drawSingleRow(y, item, isHovered, isSelected, itemIndex)
    if not item then
        return
    end
    
    if not item.displayName then
        item.displayName = "Неизвестно"
    end
    if not item.internalName then
        item.internalName = "unknown"
    end
    if item.qty == nil then
        item.qty = 0
    end
    if item.price == nil then
        item.price = 0
    end
    if item.priceCoin == nil then
        item.priceCoin = 0
    end
    if item.priceEma == nil then
        item.priceEma = 0
    end
    
    local bg, fg
    if currentShopMode == "buy" and item.qty == 0 then
        bg = COLORS.BG_SECONDARY
        fg = COLORS.INACTIVE
    elseif isSelected then
        bg = 0x225577
    elseif isHovered then
        bg = 0x446688
    elseif itemIndex and itemIndex % 2 == 1 then
        bg = COLORS.BG_SECONDARY
    else
        bg = 0x1a1a1a
    end
    
    if currentShopMode == "buy" then
        if item.qty > 0 then
            fg = COLORS.ACCENT_MAIN
        else
            fg = COLORS.INACTIVE
        end
    else
        fg = COLORS.ACCENT_MAIN
    end
    
    gpu.setBackground(bg)
    gpu.fill(2, y, 76, 1, " ")
    gpu.setForeground(fg)
    
    local name = item.displayName or "Неизвестно"
    if unicode.len(name) > 37 then
        name = unicode.sub(name, (horizontalScroll or 1), (horizontalScroll or 1) + 36)
    end
    gpu.set(3, y, name)
    
    if currentShopMode == "buy" then
        if item.qty > 0 then
            gpu.setForeground(COLORS.TEXT_BRIGHT)
        else
            gpu.setForeground(COLORS.INACTIVE)
        end
    else
        gpu.setForeground(COLORS.TEXT_BRIGHT)
    end
    gpu.set(42, y, tostring(item.qty or 0))

    if currentShopMode == "sell" then
        if item.internalName == "customnpcs:npcMoney" then
            gpu.setForeground(COLORS.TOMATO)
            local priceStr = string.format("%.2f", item.price or 0) .. " ۞"
            gpu.set(65, y, priceStr)
        else
            gpu.setForeground(COLORS.TEXT_BRIGHT)
            local priceStr = string.format("%.2f", item.price or 0) .. " ₵"
            gpu.set(65, y, priceStr)
        end
    else
        if item.priceCoin and item.priceCoin > 0 then
            gpu.setForeground(COLORS.ACCENT_MAIN)
            local coinStr = string.format("%.2f", item.priceCoin)
            gpu.set(55, y, coinStr)
        else
            gpu.setForeground(COLORS.INACTIVE)
            gpu.set(55, y, "0")
        end
        if item.priceEma and item.priceEma > 0 then
            gpu.setForeground(COLORS.TOMATO)
            local emaStr = string.format("%.2f", item.priceEma)
            gpu.set(67, y, emaStr)
        else
            gpu.setForeground(COLORS.INACTIVE)
            gpu.set(67, y, "0")
        end
    end
    gpu.setBackground(COLORS.BG_MAIN)
end

function drawScrollBar()
    local total = #filteredItems
    local barX = 78
    local barY = 7
    local barHeight = 15
    gpu.setBackground(COLORS.BG_MAIN)
    gpu.fill(barX, barY, 2, barHeight, " ")
    if total <= visibleRows then 
        return
    end
    
    gpu.setBackground(COLORS.BG_SECONDARY)
    gpu.fill(barX, barY, 2, barHeight, " ")
    local thumbHeight = math.max(2, math.floor(barHeight * visibleRows / total))
    local maxPos = barHeight - thumbHeight
    local thumbPos = math.floor((listScroll - 1) * maxPos / (total - visibleRows)) + 1
    thumbPos = math.min(thumbPos, maxPos + 1)
    gpu.setBackground(COLORS.ACCENT_MAIN)
    gpu.fill(barX, barY + thumbPos - 1, 2, thumbHeight, " ")
    gpu.setBackground(COLORS.BG_MAIN)
end

function getFilteredItems()
    writeDebugLog("getFilteredItems()")
    local filtered = {}
    local searchLower = toLowerCase(shopSearch or "")
    local searchWords = {}

    if searchLower ~= "" then
        for word in searchLower:gmatch("%S+") do
            table.insert(searchWords, word)
        end
    end

    for _, item in ipairs(shopItems) do
        if not item then
            goto continue
        end

        local nameLower = toLowerCase(item.displayName or item.internalName or "")
        local matchesSearch = false

        if #searchWords == 0 then
            matchesSearch = true
        else
            for _, word in ipairs(searchWords) do
                if string.find(nameLower, word, 1, true) then
                    matchesSearch = true
                    break
                end
            end
        end

        if matchesSearch then
            table.insert(filtered, item)
        end

        ::continue::
    end

    table.sort(filtered, function(a, b)
        return sortableName(a.displayName) < sortableName(b.displayName)
    end)

    maxItemWidth = 0
    for _, item in ipairs(filtered) do
        local len = unicode.len(item.displayName or item.internalName or "")
        if len > maxItemWidth then
            maxItemWidth = len
        end
    end

    writeDebugLog("getFilteredItems: найдено " .. #filtered .. " товаров")
    return filtered
end

function drawBuyItemsList()
    filteredItems = getFilteredItems()
    local maxScroll = math.max(1, #filteredItems - visibleRows + 1)
    listScroll = math.max(1, math.min(listScroll or 1, maxScroll))

    if #filteredItems == 0 then
        gpu.setBackground(COLORS.BG_MAIN)
        gpu.fill(2, 7, 78, visibleRows, " ")
        local msg = "ПО ТВОЕМУ ЗАПРОСУ, НИЧЕГО НЕ НАЙДЕНО!"
        local msgX = math.floor((80 - unicode.len(msg)) / 2) + 1
        local msgY = 14
        gpu.setForeground(COLORS.ERROR)
        gpu.set(msgX, msgY, msg)
    else
        for i = 1, visibleRows do
            local itemIndex = listScroll + i - 1
            local item = filteredItems[itemIndex]
            local y = 6 + i
            local isSelected = (itemIndex == selectedIndex)
            local isHovered = (itemIndex == hoveredIndex)
            
            if item then
                drawSingleRow(y, item, isHovered, isSelected, itemIndex)
            else
                gpu.setBackground(COLORS.BG_MAIN)
                gpu.fill(2, y, 76, 1, " ")
            end
        end
    end

    drawScrollBar()
    if selectedItem then
        updateSelectorDisplay(selectedItem)
    end
end

function smoothScroll(steps)
    writeDebugLog("smoothScroll: " .. tostring(steps))
    local filtered = filteredItems
    local total = #filtered
    local maxScroll = math.max(1, total - visibleRows + 1)
    local newScroll = (listScroll or 1) + steps
    newScroll = math.max(1, math.min(newScroll, maxScroll))
    
    if newScroll == listScroll then
        return
    end
    
    if math.abs(steps) == 1 and total > visibleRows then
        if steps > 0 then
            gpu.copy(2, 8, 76, visibleRows - 1, 0, -1)
            gpu.setBackground(COLORS.BG_MAIN)
            gpu.fill(2, 21, 76, 1, " ")
            local newIdx = newScroll + visibleRows - 1
            if newIdx <= total then
                drawSingleRow(21, filtered[newIdx], (newIdx == hoveredIndex), (newIdx == selectedIndex), newIdx)
            end
        else
            gpu.copy(2, 7, 76, visibleRows - 1, 0, 1)
            gpu.setBackground(COLORS.BG_MAIN)
            gpu.fill(2, 7, 76, 1, " ")
            local newIdx = newScroll
            if newIdx >= 1 then
                drawSingleRow(7, filtered[newIdx], (newIdx == hoveredIndex), (newIdx == selectedIndex), newIdx)
            end
        end
    else
        drawBuyItemsList()
        return
    end
    
    listScroll = newScroll
    drawScrollBar()
end

function drawBuyButtons()
    writeDebugFile("========== drawBuyButtons() ==========")
    local backButton = {
        text = "[ НАЗАД ]",
        x = 37, y = 24,
        xs = unicode.len("[ НАЗАД ]") + 2,
        ys = 1,
        bg = COLORS.BG_BUTTON,
        fg = COLORS.ACCENT_SECONDARY
    }
    local nextButton = {}
    if currentShopMode == "buy" then
        nextButton.text = "[ КУПИТЬ ]"
        nextButton.xs = unicode.len(nextButton.text) + 2
    else
        nextButton.text = "[ ПРОДАТЬ ]"
        nextButton.xs = unicode.len(nextButton.text) + 2
    end
    nextButton.x = 59
    nextButton.y = 24
    nextButton.ys = 1
    nextButton.bg = COLORS.BG_BUTTON
    
    if selectedItem and (currentShopMode ~= "buy" or selectedItem.qty > 0) then
        nextButton.fg = COLORS.ACCENT_SECONDARY
    else
        nextButton.fg = COLORS.INACTIVE
    end

    drawFlexButton(backButton)
    drawFlexButton(nextButton)
    drawTempMessage()
    writeDebugFile("========================================")
end

-- ============================================================
-- ★★★ ЭКРАНЫ (UI) ★★★
-- ============================================================

menuButtons = {
    shop    = {x=32, xs=20, y=9,  ys=3, text="🛒 Магазин",     tx=6, ty=1, bg=COLORS.BG_BUTTON, fg=COLORS.ACCENT_MAIN},
    account = {x=32, xs=20, y=17, ys=3, text="👤 Аккаунт",      tx=6, ty=1, bg=COLORS.BG_BUTTON, fg=COLORS.ACCENT_MAIN}
}

shopMenuButtons = {
    buy    = {x=32, xs=20, y=9,  ys=3, text="🛍 Покупка",     tx=6, ty=1, bg=COLORS.BG_BUTTON, fg=COLORS.ACCENT_MAIN},
    sell   = {x=32, xs=20, y=17, ys=3, text="💰 Пополнение",  tx=5, ty=1, bg=COLORS.BG_BUTTON, fg=COLORS.ACCENT_MAIN},
}

function drawWelcomeScreen()
    writeDebugLog("drawWelcomeScreen()")
    
    gpu.setBackground(COLORS.BG_MAIN)
    gpu.fill(1, 1, 80, 25, " ")
    
    local border_color = 0x00E5C9
    local text_color = 0x00FFCC
    local sub_color = 0xFFFF00
    local hint_color = 0xAAAAAA
    
    gpu.setForeground(border_color)
    gpu.set(1, 1, "┌" .. string.rep("─", 78) .. "┐")
    gpu.set(1, 25, "└" .. string.rep("─", 78) .. "┘")
    for y = 2, 24 do
        gpu.set(1, y, "│")
        gpu.set(80, y, "│")
    end
    
    local diamond = {
        "             ▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▓            ",
        "           ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▒▒▒▒▓          ",
        "        ▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▓▓▓        ",
        "      ▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▒▒▒▒▒▒▒▒▒▓      ",
        "     ▒▒▒▒▒▒▒▒▒▒▒▓▓▓▓▒▒▒▒▒▒▒▒▒▒▓▓▓▓▒▒▒▒▓▓▓▒▒     ",
        "     ▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▓▓▓▓▒▒▒▒▒▒▓▓      ",
        "       ▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▓▓▓▓       ",
        "        ▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▓▓▓▒▓▓▓▓         ",
        "          ▓▒▒▒▒▒▒▒▒▓▓▓▒▒▒▒▒▓▓▓▓▓▓▓▓▓▓▓          ",
        "            ▓▒▒▒▒▒▓▓▓▓▓▒▒▓▓▓▓▓▓▓▓▓▓▓            ",
        "             ▓▒▒▒▒▒▓▓▓▓▒▒▓▓▓▓▓▒▓▓▓▓             ",
        "               ▓▒▒▒▒▓▓▓▒▒▓▓▓▓▓▓▓▓               ",
        "                 ▓▒▒▒▓▓▒▒▓▓▓▓▓▓▓                ",
        "                  ▓▒▒▒▓▓▒▓▓▓▓▓                  ",
        "                    ▓▒▒▒▒▓▒▓▓                   ",
        "                      ▓▒▒▒▓▓                    ",
        "                        ▒▓                      ",
    }
    
    local gradient = {
        0x003D33,
        0x005A4C,
        0x007A66,
        0x009980,
        0x00B899,
        0x00D4B3,
        0x00E5C9,
        0x33FFD6,
    }
    
    local diamX = 17
    local diamY = 3
    
    for i, line in ipairs(diamond) do
        local color = gradient[math.min(math.floor((i-1) / 2) + 1, #gradient)]
        gpu.setForeground(color)
        gpu.set(diamX, diamY + i - 1, line)
    end
    
    local cx = 41
    
    if shopPaused then
        gpu.setForeground(COLORS.ERROR)
        drawCenteredText(21, " РЕЖИМ ОБСЛУЖИВАНИЯ", COLORS.ERROR)
        drawCenteredText(22, " Магазин временно закрыт", COLORS.ERROR)
        drawCenteredText(23, " Пожалуйста, зайдите позже", COLORS.TEXT_MAIN)
    else
        if currentPlayer and currentPlayer ~= "" then
            gpu.setForeground(text_color)
            gpu.set(cx - 2, 21, "VIP SHOP")
            
            gpu.setForeground(sub_color)
            gpu.set(cx - 6, 22, "◆ McSkill HiTech ◆")
            
            gpu.setForeground(hint_color)
            gpu.set(cx - 10, 23, "Встаньте на ПИМ для входа")
        else
            gpu.setForeground(text_color)
            gpu.set(cx - 2, 21, "VIP SHOP")
            
            gpu.setForeground(sub_color)
            gpu.set(cx - 6, 22, "◆ McSkill HiTech ◆")
            
            gpu.setForeground(hint_color)
            gpu.set(cx - 10, 23, "Встаньте на ПИМ для входа")
        end
    end
end

function drawMainMenu()
    clear()
    drawScreenBorder()
    
    if currentPlayer then
        local hello1 = "Добро пожаловать, "
        local hello2 = currentPlayer .. "!"
        local full1 = hello1 .. hello2
        local x1 = math.floor((80 - unicode.len(full1))/2) + 2
        gpu.setForeground(COLORS.SUCCESS)
        gpu.set(x1, 4, hello1)
        gpu.setForeground(COLORS.TEXT_BRIGHT)
        gpu.set(x1 + unicode.len(hello1), 4, hello2)

        local coin = coinBalance or 0.0
        local ema = emaBalance or 0.0
        
        gpu.setForeground(COLORS.WHITE)
        local balanceText = "Баланс: " .. string.format("%.2f", coin) .. " Coina ₵"
        local balanceX = math.floor((80 - unicode.len(balanceText .. " | ЭМЫ: " .. string.format("%.2f", ema) .. " ۞")) / 2) + 1
        gpu.set(balanceX, 5, "Баланс: ")
        gpu.setForeground(COLORS.ACCENT_MAIN)
        gpu.set(balanceX + unicode.len("Баланс: "), 5, string.format("%.2f", coin) .. " Coina ₵")
        gpu.setForeground(COLORS.WHITE)
        gpu.set(balanceX + unicode.len("Баланс: ") + unicode.len(string.format("%.2f", coin) .. " Coina ₵"), 5, " | ")
        gpu.setForeground(COLORS.TOMATO)
        gpu.set(balanceX + unicode.len("Баланс: ") + unicode.len(string.format("%.2f", coin) .. " Coina ₵") + unicode.len(" | "), 5, "ЭМЫ: " .. string.format("%.2f", ema) .. " ۞")
        
        local isBound = getBindingStatus()
        
        local boundText = ""
        local textColor = COLORS.ERROR
        
        if isBound then
            boundText = " АККАУНТ ПРИВЯЗАН "
            textColor = COLORS.SUCCESS_GREEN
        else
            boundText = " АККАУНТ НЕ ПРИВЯЗАН "
            textColor = COLORS.ERROR
        end
        
        local line = string.rep("═", 15)
        local fullStr = line .. boundText .. line
        local x = math.floor((80 - unicode.len(fullStr)) / 2) + 1
        
        local frameColor = COLORS.ACCENT_MAIN
        
        gpu.setForeground(frameColor)
        gpu.set(x, 2, line)
        
        gpu.setForeground(textColor)
        gpu.set(x + unicode.len(line), 2, boundText)
        
        gpu.setForeground(frameColor)
        gpu.set(x + unicode.len(line) + unicode.len(boundText), 2, line)

        if not playerAgreed then
            gpu.setForeground(COLORS.ACCENT_SECONDARY)
            if showShopDenied then
                drawCenteredText(7, "Доступ запрещён. Примите соглашение [Соглашение]", COLORS.ERROR)
            else
                drawCenteredText(7, "Вы не приняли пользовательское соглашение! Нажмите [Соглашение]", COLORS.ACCENT_SECONDARY)
            end
        end

        for _, btn in pairs(menuButtons) do
            drawButton(btn)
        end
        
        gpu.setForeground(COLORS.ERROR)
        gpu.set(4, 24, "[ ПОДДЕРЖКА ]")
        gpu.set(35, 24, "[ СОГЛАШЕНИЕ ]")
        gpu.set(68, 24, "[ ОТЗЫВЫ ]")
    else
        drawWelcomeScreen()
    end
    drawTempMessage()
end

function drawShopMenu()
    writeDebugLog("drawShopMenu()")
    clear()
    drawScreenBorder()
    drawCenteredText(6, " МАГАЗИН", COLORS.ACCENT_SECONDARY)
    if not playerAgreed then
        drawCenteredText(9, "Доступ запрещён.", COLORS.ERROR)
        drawCenteredText(10, "Примите соглашение, нажав [Соглашение] в главном меню.", COLORS.ACCENT_MAIN)
        local backButton = {
            text = "[ НАЗАД ]",
            x = 37, y = 24,
            xs = unicode.len("[ НАЗАД ]") + 2,
            ys = 1,
            bg = COLORS.BG_BUTTON,
            fg = COLORS.ACCENT_SECONDARY
        }
        drawFlexButton(backButton)
        drawTempMessage()
        return
    end
    for _, btn in pairs(shopMenuButtons) do
        drawButton(btn)
    end
    local backButton = {
        text = "[ НАЗАД ]",
        x = 37, y = 24,
        xs = unicode.len("[ НАЗАД ]") + 2,
        ys = 1,
        bg = COLORS.BG_BUTTON,
        fg = COLORS.ACCENT_SECONDARY
    }
    drawFlexButton(backButton)
    drawTempMessage()
end

function drawAccount(data)
    writeDebugLog("drawAccount()")
    clear()
    drawScreenBorder()
    drawCenteredText(10, (currentPlayer or "Игрок") .. ":", COLORS.TEXT_BRIGHT)
    
    local coin = (data and data.balance) or coinBalance or 0.0
    local ema = (data and data.emaBalance) or emaBalance or 0.0
    local agreed = (data and data.agreed) or playerAgreed or false
    
    gpu.setForeground(COLORS.WHITE)
    local balanceText = "Баланс: " .. string.format("%.2f", coin) .. " Coina ₵"
    local balanceX = math.floor((80 - unicode.len(balanceText .. " | ЭМЫ: " .. string.format("%.2f", ema) .. " ۞")) / 2) + 1
    gpu.set(balanceX, 12, "Баланс: ")
    gpu.setForeground(COLORS.ACCENT_MAIN)
    gpu.set(balanceX + unicode.len("Баланс: "), 12, string.format("%.2f", coin) .. " Coina ₵")
    gpu.setForeground(COLORS.WHITE)
    gpu.set(balanceX + unicode.len("Баланс: ") + unicode.len(string.format("%.2f", coin) .. " Coina ₵"), 12, " | ")
    gpu.setForeground(COLORS.TOMATO)
    gpu.set(balanceX + unicode.len("Баланс: ") + unicode.len(string.format("%.2f", coin) .. " Coina ₵") + unicode.len(" | "), 12, "ЭМЫ: " .. string.format("%.2f", ema) .. " ۞")

    local transLabel = "Совершенно транзакций: "
    local transCount = tostring((data and data.transactions) or playerTransactions or 0)
    local fullTrans = transLabel .. transCount
    local transX = math.floor((80 - unicode.len(fullTrans)) / 2) + 1
    gpu.setForeground(COLORS.SUCCESS)
    gpu.set(transX, 13, transLabel)
    gpu.setForeground(COLORS.TEXT_BRIGHT)
    gpu.set(transX + unicode.len(transLabel), 13, transCount)

    local regLabel = "Регистрация: "
    local regDate = (data and data.regDate) or playerRegDate or "Неизвестно"
    local fullReg = regLabel .. regDate
    local regX = math.floor((80 - unicode.len(fullReg)) / 2) + 1
    gpu.setForeground(COLORS.SUCCESS)
    gpu.set(regX, 14, regLabel)
    gpu.setForeground(COLORS.TEXT_BRIGHT)
    gpu.set(regX + unicode.len(regLabel), 14, regDate)

    local agreeLabel = "Соглашение: "
    local agreeStatus = agreed and "ознакомлен" or "не ознакомлен"
    local agreeColor = agreed and COLORS.TEXT_BRIGHT or COLORS.ERROR
    local fullAgree = agreeLabel .. agreeStatus
    local agreeX = math.floor((80 - unicode.len(fullAgree)) / 2) + 1
    gpu.setForeground(COLORS.SUCCESS)
    gpu.set(agreeX, 15, agreeLabel)
    gpu.setForeground(agreeColor)
    gpu.set(agreeX + unicode.len(agreeLabel), 15, agreeStatus)

    local authBtn = {
        text = "[ АУТЕНТИФИКАЦИЯ ]",
        x = 20,
        y = 24,
        xs = unicode.len("[ АУТЕНТИФИКАЦИЯ ]") + 2,
        ys = 1,
        bg = COLORS.BG_BUTTON,
        fg = COLORS.ACCENT_SECONDARY
    }

    local backButton = {
        text = "[ НАЗАД ]",
        x = 50,
        y = 24,
        xs = unicode.len("[ НАЗАД ]") + 2,
        ys = 1,
        bg = COLORS.BG_BUTTON,
        fg = COLORS.ACCENT_SECONDARY
    }

    drawFlexButton(authBtn)
    drawFlexButton(backButton)
    drawTempMessage()
end

function drawReportScreen()
    writeDebugLog("drawReportScreen()")
    currentScreen = "report"
    clear()
    drawScreenBorder()
    drawCenteredText(4, "РЕПОРТ", COLORS.ACCENT_SECONDARY)
    gpu.setForeground(COLORS.TEXT_MAIN)
    local help1 = "Опишите проблему: баг, предложение, жалоба."
    local helpX = math.floor((80 - unicode.len(help1)) / 2) + 1
    gpu.set(helpX, 7, help1)

    if not canSendReport() then
        drawCenteredText(9, "Вы уже отправляли репорт сегодня.", COLORS.ERROR)
        drawCenteredText(10, "Лимит: 1 сообщение в сутки (сброс в 00:00 МСК).", COLORS.ERROR)
        local backButton = {
            text = "[ НАЗАД ]",
            x = 37, y = 24,
            xs = unicode.len("[ НАЗАД ]") + 2,
            ys = 1,
            bg = COLORS.BG_BUTTON,
            fg = COLORS.ACCENT_SECONDARY
        }
        drawFlexButton(backButton)
        drawTempMessage()
        return
    end

    gpu.setBackground(COLORS.BG_INPUT)
    gpu.fill(11, 9, 59, 3, " ")
    gpu.setForeground(COLORS.TEXT_BRIGHT)
    if reportInput and reportInput ~= "" then
        gpu.set(12, 10, unicode.sub(reportInput, -58))
    else
        gpu.setForeground(COLORS.INACTIVE)
        gpu.set(12, 10, "Введите текст сообщения...")
    end
    gpu.setBackground(COLORS.BG_MAIN)

    local sendBtn = {x=33, y=14, xs=17, ys=1, text="[ ОТПРАВИТЬ ]", bg=COLORS.BG_BUTTON, fg=COLORS.SUCCESS}
    local backButton = {
        text = "[ НАЗАД ]",
        x = 37, y = 24,
        xs = unicode.len("[ НАЗАД ]") + 2,
        ys = 1,
        bg = COLORS.BG_BUTTON,
        fg = COLORS.ACCENT_SECONDARY
    }
    drawFlexButton(sendBtn)
    drawFlexButton(backButton)
    gpu.setForeground(COLORS.TEXT_MAIN)
    drawCenteredText(16, "Ограничение: 1 репорт в сутки (сброс в 00:00 МСК)", COLORS.ERROR)
    drawTempMessage()
end

function drawFeedbacksList()
    writeDebugLog("drawFeedbacksList()")
    
    if currentPlayer then
        local player = cache_players[currentPlayer]
        if player then
            playerHasFeedback = player.hasFeedback or false
        end
    end
    
    local feedbacks = cache_feedbacks or {}
    
    clear()
    drawScreenBorder()

    local function drawStars(x, y, rating)
        local starColor = 0xFFD700
        local emptyColor = COLORS.INACTIVE
        for i = 1, 5 do
            if i <= rating then
                gpu.setForeground(starColor)
                gpu.set(x + (i - 1) * 2, y, "★")
            else
                gpu.setForeground(emptyColor)
                gpu.set(x + (i - 1) * 2, y, "☆")
            end
        end
    end

    local line = string.rep("═", 15)
    local title = " ОТЗЫВЫ "
    local line2 = string.rep("═", 15)
    local fullStr = line .. title .. line2
    local x = math.floor((80 - unicode.len(fullStr)) / 2) + 1
    gpu.setForeground(COLORS.ACCENT_MAIN)
    gpu.set(x, 2, line)
    gpu.setForeground(COLORS.TEXT_BRIGHT)
    gpu.set(x + unicode.len(line), 2, title)
    gpu.setForeground(COLORS.ACCENT_MAIN)
    gpu.set(x + unicode.len(line) + unicode.len(title), 2, line2)

    if #feedbacks == 0 then
        drawCenteredText(10, "Пока нет ни одного отзыва.", COLORS.TEXT_MAIN)
        drawCenteredText(11, "Будьте первым, кто оставит отзыв!", COLORS.ACCENT_MAIN)
        if not playerHasFeedback then
            drawCenteredText(12, "Нажмите [ДОБАВИТЬ] чтобы оставить отзыв", COLORS.TEXT_MAIN)
        end
    else
        local startIdx = (feedbacksPage - 1) * 3 + 1
        local endIdx = math.min(startIdx + 2, #feedbacks)
        local y = 5

        for i = startIdx, endIdx do
            local fb = feedbacks[i]
            if fb then
                local rating = fb.rating or 5
                
                gpu.setForeground(COLORS.ACCENT_SECONDARY)
                gpu.fill(5, y, 70, 4, " ")
                gpu.setBackground(COLORS.BG_SECONDARY)
                gpu.fill(6, y+1, 68, 2, " ")

                gpu.setForeground(COLORS.ACCENT_MAIN)
                gpu.set(7, y+1, fb.name or "Аноним")
                
                gpu.setForeground(COLORS.INACTIVE)
                local timeStr = fb.time or ""
                local timeX = 7 + unicode.len(fb.name or "Аноним") + 2
                if timeX + unicode.len(timeStr) < 75 then
                    gpu.set(timeX, y+1, timeStr)
                end

                drawStars(7, y+2, rating)

                gpu.setForeground(COLORS.TEXT_BRIGHT)
                local shortText = unicode.sub(fb.text or "", 1, 60)
                local textX = 7 + 12
                if textX + unicode.len(shortText) < 75 then
                    gpu.set(textX, y+2, shortText)
                else
                    gpu.set(textX, y+2, unicode.sub(shortText, 1, 75 - textX - 3) .. "...")
                end

                y = y + 5
            end
        end

        local feedbacksTotalPages = math.max(1, math.ceil(#feedbacks / 3))
        local pageInfo = "Страница " .. feedbacksPage .. " из " .. feedbacksTotalPages
        local pageX = math.floor((80 - unicode.len(pageInfo)) / 2) + 1
        gpu.setForeground(COLORS.TEXT_MAIN)
        gpu.set(pageX, 22, pageInfo)
    end

    local backBtn = {x = 5, y = 24, xs = 11, ys = 1, text = "[ НАЗАД ]", bg = COLORS.BG_BUTTON, fg = COLORS.ACCENT_SECONDARY}
    local addBtn = {x = 36, y = 24, xs = 14, ys = 1, text = "[ ДОБАВИТЬ ]", bg = COLORS.BG_BUTTON, fg = COLORS.SUCCESS}
    local prevBtn = {x = 59, y = 24, xs = 7, ys = 1, text = "[ < ]", bg = COLORS.BG_BUTTON, fg = COLORS.ACCENT_MAIN}
    local nextBtn = {x = 69, y = 24, xs = 7, ys = 1, text = "[ > ]", bg = COLORS.BG_BUTTON, fg = COLORS.ACCENT_MAIN}

    if not playerHasFeedback then
        drawFlexButton(addBtn)
    end
    drawFlexButton(backBtn)
    if #feedbacks > 3 then
        drawFlexButton(prevBtn)
        drawFlexButton(nextBtn)
    end

    drawTempMessage()
end

function drawFeedbackInputScreen()
    writeDebugLog("drawFeedbackInputScreen()")
    if playerHasFeedback then
        showTempMessage("Вы уже оставляли отзыв!", 2)
        goBackToMenu()
        return
    end
    currentScreen = "feedback_input"
    clear()
    drawScreenBorder()
    drawCenteredText(4, "ОСТАВИТЬ ОТЗЫВ", COLORS.ACCENT_SECONDARY)

    gpu.setForeground(COLORS.TEXT_MAIN)
    drawCenteredText(7, "Ваше имя: " .. (currentPlayer or "Игрок"), COLORS.ACCENT_MAIN)
    drawCenteredText(9, "Оцените магазин:", COLORS.TEXT_MAIN)

    local starsY = 11
    local starsX = 30
    gpu.setForeground(COLORS.ACCENT_SECONDARY)
    gpu.set(starsX, starsY, "Рейтинг: ")
    for i = 1, 5 do
        local starX = starsX + unicode.len("Рейтинг: ") + (i - 1) * 3
        if i <= feedbackRating then
            gpu.setForeground(0xFFD700)
            gpu.set(starX, starsY, "★")
        else
            gpu.setForeground(COLORS.INACTIVE)
            gpu.set(starX, starsY, "☆")
        end
    end

    gpu.setForeground(COLORS.INACTIVE)
    drawCenteredText(13, "Нажмите 1-5 для выбора рейтинга", COLORS.INACTIVE)

    gpu.setForeground(COLORS.TEXT_MAIN)
    drawCenteredText(15, "Оставьте свой отзыв о магазине:", COLORS.TEXT_MAIN)

    gpu.setBackground(COLORS.BG_INPUT)
    gpu.fill(11, 17, 59, 3, " ")
    gpu.setForeground(COLORS.TEXT_BRIGHT)
    if feedbackEditMode then
        if feedbackInput and feedbackInput ~= "" then
            gpu.set(12, 18, unicode.sub(feedbackInput, -58) .. "_")
        else
            gpu.setForeground(COLORS.INACTIVE)
            gpu.set(12, 18, "Введите ваш отзыв..._")
        end
    else
        if feedbackInput and feedbackInput ~= "" then
            gpu.set(12, 18, unicode.sub(feedbackInput, -58))
        else
            gpu.setForeground(COLORS.INACTIVE)
            gpu.set(12, 18, "Введите ваш отзыв...")
        end
    end
    gpu.setBackground(COLORS.BG_MAIN)

    local cancelBtn = {x = 20, y = 24, xs = 12, ys = 1, text = "[ ОТМЕНА ]", bg = COLORS.BG_BUTTON, fg = COLORS.ERROR}
    local sendBtn = {x = 46, y = 24, xs = 15, ys = 1, text = "[ ОТПРАВИТЬ ]", bg = COLORS.BG_BUTTON, fg = COLORS.SUCCESS}

    drawFlexButton(cancelBtn)
    drawFlexButton(sendBtn)
    drawTempMessage()
end

function drawSellPopup()
    writeDebugLog("drawSellPopup()")
    if not sellConfirmItem then
        writeErrorLog("❌ drawSellPopup: sellConfirmItem = nil!")
        return
    end
    
    local popupWidth = 40
    local popupHeight = 10
    local popupX = math.floor((80 - popupWidth) / 2)
    local popupY = 10

    gpu.setBackground(COLORS.BLACK)
    gpu.fill(popupX, popupY+2, popupWidth, popupHeight-4, " ")
    gpu.fill(popupX+1, popupY+1, popupWidth-2, popupHeight-2, " ")

    drawPopupBorder(popupX, popupY, popupWidth, popupHeight, COLORS.ACCENT_SECONDARY)

    local name = sellConfirmItem.displayName or "Неизвестно"
    local totalFound = foundAmount or 0
    local value = totalFound * (sellConfirmItem.price or 0)

    gpu.setForeground(COLORS.TEXT_BRIGHT)
    gpu.set(popupX+14, popupY, "Подтверждение")

    gpu.setForeground(COLORS.SUCCESS)
    gpu.set(popupX+3, popupY+3, "Магазин заберёт: ")
    gpu.setForeground(COLORS.TEXT_BRIGHT)
    gpu.set(popupX+3 + unicode.len("Магазин заберёт: "), popupY+3, tostring(totalFound))

    gpu.setForeground(COLORS.SUCCESS)
    gpu.set(popupX+3, popupY+4, name .. " x")
    gpu.setForeground(COLORS.TEXT_BRIGHT)
    gpu.set(popupX+3 + unicode.len(name .. " x"), popupY+4, tostring(totalFound))

    gpu.setForeground(COLORS.SUCCESS)
    gpu.set(popupX+3, popupY+5, "Вы получите: ")
    if sellConfirmItem.internalName == "customnpcs:npcMoney" then
        gpu.setForeground(COLORS.TOMATO)
        gpu.set(popupX+3 + unicode.len("Вы получите: "), popupY+5, string.format("%.2f", value) .. " ۞")
    else
        gpu.setForeground(COLORS.ACCENT_MAIN)
        gpu.set(popupX+3 + unicode.len("Вы получите: "), popupY+5, string.format("%.2f", value) .. " ₵")
    end

    local yesBtn = {x=popupX+5, y=popupY+7, xs=13, ys=1, text="[ Принять ]", bg=COLORS.BG_BUTTON, fg=COLORS.SUCCESS}
    local noBtn  = {x=popupX+popupWidth-16, y=popupY+7, xs=12, ys=1, text="[ Отмена ]", bg=COLORS.BG_BUTTON, fg=COLORS.ERROR}
    drawFlexButton(yesBtn)
    drawFlexButton(noBtn)
    drawTempMessage()
end

function drawSellScanScreen()
    writeDebugLog("drawSellScanScreen()")
    if not sellConfirmItem then
        writeErrorLog("❌ drawSellScanScreen: sellConfirmItem = nil!")
        return
    end
    
    currentScreen = "sell_scan"
    clear()
    drawScreenBorder()
    drawBalanceLine(3, 1)

    gpu.setForeground(COLORS.SUCCESS)
    gpu.set(3, 3, "Имя предмета: ")
    gpu.setForeground(COLORS.TEXT_BRIGHT)
    gpu.set(18, 3, sellConfirmItem.displayName or "Неизвестно")

    gpu.setForeground(COLORS.SUCCESS)
    gpu.set(55, 3, "Цена: ")
    if sellConfirmItem.internalName == "customnpcs:npcMoney" then
        gpu.setForeground(COLORS.TOMATO)
        gpu.set(62, 3, string.format("%.2f", sellConfirmItem.price or 0) .. " ۞")
    else
        gpu.setForeground(COLORS.ACCENT_MAIN)
        gpu.set(62, 3, string.format("%.2f", sellConfirmItem.price or 0) .. " ₵")
    end

    gpu.setForeground(COLORS.SUCCESS)
    gpu.set(3, 5, "Можно продать: ")
    gpu.setForeground(COLORS.TEXT_BRIGHT)
    gpu.set(18, 5, tostring(sellConfirmItem.qty or 0))

    gpu.setForeground(COLORS.ACCENT_SECONDARY)
    local scanText = "Сканировать на наличие предмета:"
    local scanX = math.floor((80 - unicode.len(scanText)) / 2)
    gpu.set(scanX, 11, scanText)

    local allBtn  = {x=30, y=13, xs=20, ys=1, text="Весь инвентарь", bg=COLORS.BG_BUTTON, fg=COLORS.SUCCESS}
    drawFlexButton(allBtn)
    
    local backButton = {
        text = "[ НАЗАД ]",
        x = 37, y = 24,
        xs = unicode.len("[ НАЗАД ]") + 2,
        ys = 1,
        bg = COLORS.BG_BUTTON,
        fg = COLORS.ACCENT_SECONDARY
    }
    drawFlexButton(backButton)

    if showSellPopup and sellConfirmItem then
        drawSellPopup()
    end
    drawTempMessage()
end

function drawPurchaseScreen()
    writeDebugFile(">>> drawPurchaseScreen()")
    currentScreen = "purchase"
    clear()
    drawScreenBorder()
    drawBalanceLine(3, 1)

    if not purchaseItem then
        writeDebugFile("❌ drawPurchaseScreen: purchaseItem = nil!")
        writeErrorLog("❌ drawPurchaseScreen: purchaseItem = nil!")
        drawCenteredText(10, "Ошибка: предмет не выбран", COLORS.ERROR)
        local backBtn = {x = 37, y = 24, xs = unicode.len("[ НАЗАД ]") + 2, ys = 1, text = "[ НАЗАД ]", bg = COLORS.BG_BUTTON, fg = COLORS.ACCENT_SECONDARY}
        drawFlexButton(backBtn)
        drawTempMessage()
        return
    end

    writeDebugFile("✅ purchaseItem: " .. tostring(purchaseItem.displayName))

    gpu.setForeground(COLORS.SUCCESS)
    gpu.set(3, 3, "Имя предмета: ")
    gpu.setForeground(COLORS.TEXT_BRIGHT)
    gpu.set(18, 3, purchaseItem.displayName or "Неизвестно")

    gpu.setForeground(COLORS.SUCCESS)
    gpu.set(55, 3, "Доступно: ")
    gpu.setForeground(COLORS.TEXT_BRIGHT)
    gpu.set(66, 3, tostring(purchaseItem.qty or 0))

    local qty = purchaseQuantity or 1
    local totalCoin = (purchaseItem.priceCoin or 0) * qty
    local totalEma = (purchaseItem.priceEma or 0) * qty

    gpu.setForeground(COLORS.SUCCESS)
    gpu.set(3, 5, "На сумму: ")
    local sumY = 5
    if totalCoin > 0 then
        gpu.setForeground(COLORS.ERROR)
        gpu.set(14, sumY, string.format("%.2f", totalCoin) .. " ₵")
        sumY = sumY + 1
    end
    if totalEma > 0 then
        gpu.setForeground(COLORS.TOMATO)
        gpu.set(14, sumY, string.format("%.2f", totalEma) .. " ۞")
    end

    gpu.setForeground(COLORS.SUCCESS)
    gpu.set(55, 5, "Цена: ")
    local priceY = 5
    if purchaseItem.priceCoin and purchaseItem.priceCoin > 0 then
        gpu.setForeground(COLORS.ACCENT_MAIN)
        gpu.set(62, priceY, string.format("%.2f", purchaseItem.priceCoin) .. " ₵")
        priceY = priceY + 1
    end
    if purchaseItem.priceEma and purchaseItem.priceEma > 0 then
        gpu.setForeground(COLORS.TOMATO)
        gpu.set(62, priceY, string.format("%.2f", purchaseItem.priceEma) .. " ۞")
    end

    gpu.setForeground(COLORS.SUCCESS)
    gpu.set(3, 7, "Кол-во: ")
    gpu.setForeground(COLORS.TEXT_BRIGHT)
    gpu.set(12, 7, tostring(qty))

    local keys = {
        {"1","2","3"},
        {"4","5","6"},
        {"7","8","9"},
        {"<","0","C"}
    }
    local startX = 34
    local startY = 11
    local btnW = 3
    local btnH = 1
    local spacing = 2
    for row = 1, 4 do
        for col = 1, 3 do
            local x = startX + (col-1)*(btnW + spacing)
            local y = startY + (row-1)*(btnH + 1)
            local text = keys[row][col]
            gpu.setBackground(COLORS.BG_BUTTON)
            gpu.fill(x, y, btnW, btnH, " ")
            gpu.setForeground(COLORS.ACCENT_MAIN)
            local tx = x + math.floor((btnW - unicode.len(text)) / 2)
            local ty = y
            gpu.set(tx, ty, text)
        end
    end
    local backBtn = {x = 19, y = 24, xs = unicode.len("[ НАЗАД ]") + 2, ys = 1, text = "[ НАЗАД ]", bg = COLORS.BG_BUTTON, fg = COLORS.ACCENT_SECONDARY}
    local buyBtn  = {x = 51, y = 24, xs = unicode.len("[ КУПИТЬ ]") + 2, ys = 1, text = "[ КУПИТЬ ]", bg = COLORS.BG_BUTTON, fg = COLORS.SUCCESS}
    drawFlexButton(backBtn)
    drawFlexButton(buyBtn)
    drawTempMessage()
end

function drawInsufficientPopup()
    writeDebugLog("drawInsufficientPopup()")
    local popupWidth = 52
    local popupHeight = 11
    local popupX = math.floor((80 - popupWidth) / 2)
    local popupY = 7

    gpu.setBackground(COLORS.BLACK)
    gpu.fill(popupX, popupY, popupWidth, popupHeight, " ")
    gpu.fill(popupX+1, popupY+1, popupWidth-2, popupHeight-2, " ")
    drawPopupBorder(popupX, popupY, popupWidth, popupHeight, COLORS.ERROR)

    gpu.setForeground(COLORS.ERROR)
    local title = "НЕДОСТАТОЧНО СРЕДСТВ"
    local titleX = popupX + math.floor((popupWidth - unicode.len(title)) / 2)
    gpu.set(titleX, popupY, title)

    gpu.setForeground(COLORS.TEXT_MAIN)
    local line1a = "Пополни баланс, не можешь купить"
    local line1aX = popupX + math.floor((popupWidth - unicode.len(line1a)) / 2)
    gpu.set(line1aX, popupY+2, line1a)

    local line1b = "хотя бы 1 штуку предмета."
    local line1bX = popupX + math.floor((popupWidth - unicode.len(line1b)) / 2)
    gpu.set(line1bX, popupY+3, line1b)

    gpu.setForeground(COLORS.SUCCESS)
    gpu.set(popupX+3, popupY+5, "Твой баланс Coin: ")
    gpu.setForeground(COLORS.ACCENT_MAIN)
    gpu.set(popupX+3 + unicode.len("Твой баланс Coin: "), popupY+5, string.format("%.2f", insufficientBalanceCoin or 0) .. " ₵")
    if insufficientBalanceEma and insufficientBalanceEma > 0 then
        gpu.setForeground(COLORS.SUCCESS)
        gpu.set(popupX+3, popupY+6, "Твой баланс ЭМЫ: ")
        gpu.setForeground(COLORS.TOMATO)
        gpu.set(popupX+3 + unicode.len("Твой баланс ЭМЫ: "), popupY+6, string.format("%.2f", insufficientBalanceEma) .. " ۞")
    end

    local okBtnText = "[ ПОНЯТНО ]"
    local okBtnWidth = unicode.len(okBtnText) + 2
    local okBtn = {
        x = popupX + math.floor((popupWidth - okBtnWidth) / 2),
        y = popupY+8,
        xs = okBtnWidth,
        ys = 1,
        text = okBtnText,
        bg = COLORS.BG_BUTTON,
        fg = COLORS.SUCCESS
    }
    drawFlexButton(okBtn)
    drawTempMessage()
end

function drawPartialPopup()
    writeDebugLog("drawPartialPopup()")
    local popupWidth = 52
    local popupHeight = 9
    local popupX = math.floor((80 - popupWidth) / 2)
    local popupY = 9

    gpu.setBackground(COLORS.BLACK)
    gpu.fill(popupX, popupY, popupWidth, popupHeight, " ")
    gpu.fill(popupX+1, popupY+1, popupWidth-2, popupHeight-2, " ")
    drawPopupBorder(popupX, popupY, popupWidth, popupHeight, COLORS.ERROR)

    gpu.setForeground(COLORS.ERROR)
    local title = "НЕ ПОЛНАЯ ВЫДАЧА"
    local titleX = popupX + math.floor((popupWidth - unicode.len(title)) / 2)
    gpu.set(titleX, popupY, title)

    gpu.setForeground(COLORS.TEXT_MAIN)
    local line1 = "Не хватило места в инвентаре!"
    local line1X = popupX + math.floor((popupWidth - unicode.len(line1)) / 2)
    gpu.set(line1X, popupY+2, line1)

    local line2 = "Выдано " .. (partialExtracted or 0) .. " из " .. (partialRequested or 0)
    local line2X = popupX + math.floor((popupWidth - unicode.len(line2)) / 2)
    gpu.set(line2X, popupY+3, line2)

    local spentLabelCoin = "Списано Coin: "
    local spentValueCoin = string.format("%.2f", partialRefundCoin or 0) .. " ₵"
    local fullSpentTextCoin = spentLabelCoin .. spentValueCoin
    local spentStartXCoin = popupX + math.floor((popupWidth - unicode.len(fullSpentTextCoin)) / 2)
    gpu.setForeground(COLORS.SUCCESS)
    gpu.set(spentStartXCoin, popupY+4, spentLabelCoin)
    gpu.setForeground(COLORS.ACCENT_MAIN)
    gpu.set(spentStartXCoin + unicode.len(spentLabelCoin), popupY+4, spentValueCoin)

    if partialRefundEma and partialRefundEma > 0 then
        local spentLabelEma = "Списано ЭМЫ: "
        local spentValueEma = string.format("%.2f", partialRefundEma) .. " ۞"
        local fullSpentTextEma = spentLabelEma .. spentValueEma
        local spentStartXEma = popupX + math.floor((popupWidth - unicode.len(fullSpentTextEma)) / 2)
        gpu.setForeground(COLORS.SUCCESS)
        gpu.set(spentStartXEma, popupY+5, spentLabelEma)
        gpu.setForeground(COLORS.TOMATO)
        gpu.set(spentStartXEma + unicode.len(spentLabelEma), popupY+5, spentValueEma)
    end

    local okBtnText = "[ ПРИНЯТЬ ]"
    local okBtnWidth = unicode.len(okBtnText) + 2
    local okBtn = {
        x = popupX + math.floor((popupWidth - okBtnWidth) / 2),
        y = popupY+6,
        xs = okBtnWidth,
        ys = 1,
        text = okBtnText,
        bg = COLORS.BG_BUTTON,
        fg = COLORS.SUCCESS
    }
    drawFlexButton(okBtn)
    drawTempMessage()
end

function drawInventoryFullPopup()
    writeDebugLog("drawInventoryFullPopup()")
    local popupWidth = 52
    local popupHeight = 9
    local popupX = math.floor((80 - popupWidth) / 2)
    local popupY = 9

    gpu.setBackground(COLORS.BLACK)
    gpu.fill(popupX, popupY, popupWidth, popupHeight, " ")
    gpu.fill(popupX+1, popupY+1, popupWidth-2, popupHeight-2, " ")
    drawPopupBorder(popupX, popupY, popupWidth, popupHeight, COLORS.ERROR)

    gpu.setForeground(COLORS.ERROR)
    local title = "ПРЕДУПРЕЖДЕНИЕ"
    local titleX = popupX + math.floor((popupWidth - unicode.len(title)) / 2)
    gpu.set(titleX, popupY, title)

    gpu.setForeground(COLORS.TEXT_MAIN)
    local line1 = "Ваш инвентарь полон!"
    local line1X = popupX + math.floor((popupWidth - unicode.len(line1)) / 2)
    gpu.set(line1X, popupY+2, line1)

    local line2 = "Освободите его и повторите попытку."
    local line2X = popupX + math.floor((popupWidth - unicode.len(line2)) / 2)
    gpu.set(line2X, popupY+3, line2)

    local okBtnText = "[ ПОНЯТНО ]"
    local okBtnWidth = unicode.len(okBtnText) + 2
    local okBtn = {
        x = popupX + math.floor((popupWidth - okBtnWidth) / 2),
        y = popupY+6,
        xs = okBtnWidth,
        ys = 1,
        text = okBtnText,
        bg = COLORS.BG_BUTTON,
        fg = COLORS.SUCCESS
    }
    drawFlexButton(okBtn)
    drawTempMessage()
end

-- ============================================================
-- ★★★ НАВИГАЦИЯ ★★★
-- ============================================================

function goBackToMenu()
    writeDebugLog("goBackToMenu()")
    showShopDenied = false
    currentScreen = "menu"
    markDirty()
    updateSelectorDisplay(nil)
    pcall(selector.setSlot, 0, nil)
    pcall(selector.setSlot, 1, nil)
end

function goToShop()
    writeDebugLog("goToShop()")
    currentScreen = "shop"
    markDirty()
end

function goToBuy()
    writeDebugLog("goToBuy()")
    if not playerAgreed then
        drawCenteredText(12, "Вы не приняли пользовательское соглашение!", COLORS.ERROR)
        drawCenteredText(13, "Нажмите [Помощь] и ознакомьтесь с условиями.", COLORS.TEXT_MAIN)
        os.sleep(3)
        markDirty()
        return
    end
    currentScreen = "shop_buy"
    currentShopMode = "buy"
    listScroll = 1
    horizontalScroll = 1
    selectedIndex = 0
    hoveredIndex = 0
    selectedItem = nil
    shopSearch = ""
    searchActive = false
    searchInput = ""
    loadBuyItems()
    markDirty()
end

function goToSell()
    writeDebugLog("goToSell()")
    if not playerAgreed then
        drawCenteredText(12, "Вы не приняли пользовательское соглашение!", COLORS.ERROR)
        drawCenteredText(13, "Нажмите [Помощь] и ознакомьтесь с условиями.", COLORS.TEXT_MAIN)
        os.sleep(3)
        markDirty()
        return
    end

    currentScreen = "shop_sell"
    currentShopMode = "sell"
    listScroll = 1
    horizontalScroll = 1
    selectedIndex = 0
    hoveredIndex = 0
    selectedItem = nil
    shopSearch = ""
    searchActive = false
    searchInput = ""
    loadSellItems()
    markDirty()
end

function goToSellConfirm(item)
    writeDebugFile(">>> goToSellConfirm()")
    if not item then
        writeDebugFile("❌ goToSellConfirm: item = nil!")
        writeErrorLog("❌ goToSellConfirm: item = nil!")
        return
    end
    sellConfirmItem = item
    foundAmount = 0
    showSellPopup = false
    currentScreen = "sell_scan"
    writeDebugFile("✅ sellConfirmItem установлен: " .. tostring(sellConfirmItem.displayName))
    writeDebugFile("✅ currentScreen = " .. currentScreen)
    markDirty()
end

function goToPurchase(item)
    writeDebugFile(">>> goToPurchase()")
    if not item then
        writeDebugFile("❌ goToPurchase: item = nil!")
        writeErrorLog("❌ goToPurchase: item = nil!")
        return
    end
    purchaseItem = item
    purchaseQuantity = 1
    currentScreen = "purchase"
    writeDebugFile("✅ purchaseItem установлен: " .. tostring(purchaseItem.displayName))
    writeDebugFile("✅ currentScreen = " .. currentScreen)
    markDirty()
end

function goToReport()
    writeDebugLog("goToReport()")
    currentScreen = "report"
    reportInput = ""
    markDirty()
end

function goToHelp()
    writeDebugLog("goToHelp()")
    currentScreen = "agreement"
    if type(drawAgreementScreen) == "function" then
        markDirty()
    else
        drawCenteredText(10, "СОГЛАШЕНИЕ НЕ ЗАГРУЖЕНО", COLORS.ERROR)
        drawCenteredText(12, "Файл agreement.lua отсутствует", COLORS.TEXT_MAIN)
        drawCenteredText(14, "Нажмите [НАЗАД] для возврата", COLORS.TEXT_MAIN)
        
        local backButton = {
            text = "[ НАЗАД ]",
            x = 37, y = 24,
            xs = unicode.len("[ НАЗАД ]") + 2,
            ys = 1,
            bg = COLORS.BG_BUTTON,
            fg = COLORS.ACCENT_SECONDARY
        }
        drawFlexButton(backButton)
        drawTempMessage()
        
        while currentScreen == "agreement" do
            local ev = {event.pull(0.5)}
            if ev[1] == "touch" then
                local x = tonumber(ev[3]) or 0
                local y = tonumber(ev[4]) or 0
                if isButtonClicked(backButton, x, y) then
                    goBackToMenu()
                    break
                end
            end
        end
    end
end

function goToAccount()
    writeDebugLog("goToAccount()")
    if not currentToken then
        drawCenteredText(12, "Ошибка: нет авторизации", COLORS.ERROR)
        return
    end
    currentScreen = "account_loading"
    markDirty()
    local player = cache_players[currentPlayer]
    if player then
        currentScreen = "account"
        markDirty()
    end
end

function handleQuantityButtonClick(btnText)
    writeDebugLog("handleQuantityButtonClick: " .. tostring(btnText))
    if btnText == "C" then
        purchaseQuantity = 0
    elseif btnText == "<" then
        purchaseQuantity = math.floor((purchaseQuantity or 1) / 10)
    elseif tonumber(btnText) then
        local digit = tonumber(btnText)
        if purchaseQuantity == 0 then
            purchaseQuantity = digit
        else
            purchaseQuantity = (purchaseQuantity or 1) * 10 + digit
        end
        if purchaseItem and purchaseQuantity > (purchaseItem.qty or 0) then
            purchaseQuantity = purchaseItem.qty
        end
    end
    markDirty()
end

-- ============================================================
-- ★★★ АУТЕНТИФИКАЦИЯ (ПРИВЯЗКА АККАУНТА) ★★★
-- ============================================================

function getBindingStatus()
    if not currentPlayer then
        boundPlayer = nil
        bindingCache.isBound = false
        return false
    end
    
    local player = cache_players[currentPlayer]
    if player and player.site_user and player.site_user ~= "" then
        boundPlayer = player.site_user
        bindingCache.isBound = true
        bindingCache.lastCheck = os.time()
        return true
    end
    
    local now = os.time()
    if now - (bindingCache.lastCheck or 0) < bindingCache.checkInterval then
        return bindingCache.isBound
    end
    
    bindingCache.lastCheck = now
    
    if not bindingCache.pendingUpdate then
        bindingCache.pendingUpdate = true
        event.timer(0.1, function()
            local success, response = pcall(function()
                return internet.request(WEB_URL .. "/api/player_binding?game_player=" .. currentPlayer, nil, {
                    ["Connection"] = "close",
                    ["Timeout"] = 3
                })
            end)
            if success and response then
                local body = ""
                for chunk in response do
                    body = body .. chunk
                end
                local data = parseJSON(body)
                if data and data.success and data.site_user then
                    if currentPlayer and cache_players[currentPlayer] then
                        cache_players[currentPlayer].site_user = data.site_user
                    end
                    boundPlayer = data.site_user
                    bindingCache.isBound = true
                elseif data and data.success == false then
                    if currentPlayer and cache_players[currentPlayer] then
                        cache_players[currentPlayer].site_user = nil
                    end
                    boundPlayer = nil
                    bindingCache.isBound = false
                end
                bindingCache.lastCheck = os.time()
                bindingCache.pendingUpdate = false
                if currentScreen == "menu" then markDirty() end
            else
                bindingCache.lastCheck = os.time()
                bindingCache.pendingUpdate = false
            end
            return false
        end)
    end
    
    return bindingCache.isBound
end

function forceSyncBinding()
    if not currentPlayer then return end
    bindingCache.lastCheck = 0
    bindingCache.isBound = false
    bindingCache.pendingUpdate = false
    getBindingStatus()
end

function verifyAuthCodeOnServer(code, game_player)
    writeDebugLog("verifyAuthCodeOnServer: code=" .. tostring(code) .. ", player=" .. tostring(game_player))
    
    local success, response = pcall(function()
        return internet.request(WEB_URL .. "/api/verify_auth_code", toJson({
            code = code,
            game_player = game_player
        }), {
            ["Content-Type"] = "application/json",
            ["Connection"] = "close",
            ["Timeout"] = 5
        })
    end)
    
    if not success or not response then
        writeErrorLog("❌ Ошибка соединения с сервером")
        return "SERVER_ERROR"
    end
    
    local body = ""
    for chunk in response do
        body = body .. chunk
    end
    local data = parseJSON(body)
    if not data then
        writeErrorLog("❌ Ошибка парсинга JSON: " .. body)
        return "SERVER_ERROR"
    end
    
    if data.success and data.status == "SUCCESS" then
        if cache_players[game_player] then
            cache_players[game_player].site_user = data.site_user
            boundPlayer = data.site_user
            bindingCache.isBound = true
            bindingCache.lastCheck = os.time()
            addBindingLog("Аккаунт привязан: " .. boundPlayer .. " -> " .. game_player, "LINK")
            return "SUCCESS"
        end
    end
    
    return data.status or "SERVER_ERROR"
end

function unbindAccount()
    if not currentPlayer then
        showTempMessage("Ошибка: игрок не авторизован", 2)
        return
    end
    
    local json_data = toJson({
        game_player = currentPlayer
    })
    
    local success, response = pcall(function()
        return internet.request(WEB_URL .. "/api/unbind_player", json_data, {
            ["Content-Type"] = "application/json; charset=utf-8",
            ["Connection"] = "close",
            ["Timeout"] = 5
        })
    end)
    
    if success and response then
        local body = ""
        for chunk in response do
            body = body .. chunk
        end
        local data = parseJSON(body)
        if data and data.success then
            if currentPlayer and cache_players[currentPlayer] then
                cache_players[currentPlayer].site_user = nil
                boundPlayer = nil
                bindingCache.isBound = false
                bindingCache.lastCheck = 0
                addBindingLog("Аккаунт отвязан: " .. currentPlayer, "UNLINK")
                gpu.setForeground(COLORS.SUCCESS)
                gpu.set(28, 17, "✅ Аккаунт ОТВЯЗАН!")
                gpu.setForeground(COLORS.TEXT_MAIN)
                gpu.set(23, 18, "   Доступ к магазину ограничен")
                os.sleep(2)
                goBackToMenu()
            else
                gpu.setForeground(COLORS.ERROR)
                gpu.set(20, 17, "❌ Игрок не найден")
                os.sleep(2)
                markDirty()
            end
        else
            local status = data and data.status or "SERVER_ERROR"
            gpu.setForeground(COLORS.ERROR)
            gpu.set(20, 17, "❌ Ошибка: " .. status)
            os.sleep(2)
            markDirty()
        end
    else
        gpu.setForeground(COLORS.ERROR)
        gpu.set(20, 17, "❌ Ошибка соединения")
        os.sleep(2)
        markDirty()
    end
end

function showUnbindConfirmPopup()
    writeDebugLog("showUnbindConfirmPopup()")
    
    local popupWidth = 46
    local popupHeight = 10
    local popupX = math.floor((80 - popupWidth) / 2) + 1
    local popupY = math.floor((25 - popupHeight) / 2)
    
    gpu.setBackground(COLORS.BLACK)
    gpu.fill(popupX - 2, popupY - 2, popupWidth + 4, popupHeight + 4, " ")
    gpu.setBackground(COLORS.BG_POPUP)
    gpu.fill(popupX, popupY, popupWidth, popupHeight, " ")
    
    gpu.setForeground(COLORS.ERROR)
    gpu.fill(popupX, popupY, popupWidth, 1, "═")
    gpu.fill(popupX, popupY + popupHeight - 1, popupWidth, 1, "═")
    for i = 1, popupHeight - 2 do
        gpu.set(popupX, popupY + i, "║")
        gpu.set(popupX + popupWidth - 1, popupY + i, "║")
    end
    gpu.set(popupX, popupY, "╔")
    gpu.set(popupX + popupWidth - 1, popupY, "╗")
    gpu.set(popupX, popupY + popupHeight - 1, "╚")
    gpu.set(popupX + popupWidth - 1, popupY + popupHeight - 1, "╝")
    
    local titleText = "ПОДТВЕРЖДЕНИЕ"
    local titleLen = unicode.len(titleText)
    gpu.setForeground(COLORS.ERROR)
    gpu.set(popupX + math.floor((popupWidth - titleLen) / 2), popupY + 1, titleText)
    
    gpu.setForeground(COLORS.TEXT_MAIN)
    gpu.set(popupX + 3, popupY + 3, "Вы действительно хотите")
    gpu.set(popupX + 3, popupY + 4, "ОТВЯЗАТЬ аккаунт?")
    
    gpu.setForeground(COLORS.INACTIVE)
    gpu.set(popupX + 3, popupY + 6, "После отвязки доступ к магазину")
    gpu.set(popupX + 3, popupY + 7, "будет ограничен до новой привязки.")
    
    local yesBtn = {
        text = "[ ДА, ОТВЯЗАТЬ ]",
        x = popupX + 5,
        y = popupY + popupHeight - 2,
        xs = unicode.len("[ ДА, ОТВЯЗАТЬ ]") + 2,
        ys = 1,
        bg = 0x441111,
        fg = COLORS.ERROR
    }
    local noBtn = {
        text = "[ ОТМЕНА ]",
        x = popupX + popupWidth - unicode.len("[ ОТМЕНА ]") - 4,
        y = popupY + popupHeight - 2,
        xs = unicode.len("[ ОТМЕНА ]") + 2,
        ys = 1,
        bg = COLORS.BG_BUTTON,
        fg = COLORS.ACCENT_SECONDARY
    }
    drawFlexButton(yesBtn)
    drawFlexButton(noBtn)
    
    while true do
        local ev = {event.pull(0.5)}
        
        if ev[1] == "player_off" or ev[1] == "pim_player_leave" then
            writeDebugLog("👤 Игрок ушёл с PIM во время подтверждения отвязки")
            currentScreen = "welcome"
            markDirty()
            break
        end
        
        if ev[1] == "touch" then
            local x, y = ev[3], ev[4]
            local touchPlayer = ev[6] or "Неизвестный"
            
            if not isPimOwner(touchPlayer) then
                writeDebugLog("⚠️ Коснулся не владелец: " .. touchPlayer .. ", игнорируем")
                goto continue_unbind
            end
            
            if isButtonClicked(noBtn, x, y) then
                showAuthPopup()
                break
            end
            
            if isButtonClicked(yesBtn, x, y) then
                unbindAccount()
                break
            end
        end
        
        ::continue_unbind::
    end
end

function showAuthPopup()
    writeDebugLog("showAuthPopup() - НОВАЯ ВЕРСИЯ")
    
    if qrPopupActive then
        writeDebugLog("⚠️ QR-код активен, не рисуем аутентификацию")
        qrPopupActive = false
        return
    end
    
    currentScreen = "auth_popup"
    authCodeInput = authCodeInput or ""
    
    local popupWidth = 50
    local popupHeight = 16
    local popupX = math.floor((80 - popupWidth) / 2) + 1
    local popupY = math.floor((25 - popupHeight) / 2)
    
    gpu.setBackground(COLORS.BLACK)
    gpu.fill(1, 1, 80, 25, " ")
    gpu.setBackground(COLORS.BG_POPUP)
    gpu.fill(popupX, popupY, popupWidth, popupHeight, " ")
    
    gpu.setForeground(0x00FFCC)
    gpu.fill(popupX, popupY, popupWidth, 1, "─")
    gpu.fill(popupX, popupY + popupHeight - 1, popupWidth, 1, "─")
    for i = 1, popupHeight - 2 do
        gpu.set(popupX, popupY + i, "│")
        gpu.set(popupX + popupWidth - 1, popupY + i, "│")
    end
    gpu.set(popupX, popupY, "┌")
    gpu.set(popupX + popupWidth - 1, popupY, "┐")
    gpu.set(popupX, popupY + popupHeight - 1, "└")
    gpu.set(popupX + popupWidth - 1, popupY + popupHeight - 1, "┘")
    
    gpu.setForeground(0x00FFCC)
    gpu.set(popupX + math.floor((popupWidth - 22) / 2) + 1, popupY + 1, "🔐 АУТЕНТИФИКАЦИЯ")
    
    gpu.setForeground(COLORS.WHITE)
    gpu.set(popupX + 3, popupY + 3, "👤 Игрок: ")
    gpu.setForeground(COLORS.ACCENT_MAIN)
    gpu.set(popupX + 15, popupY + 3, currentPlayer or "Неизвестно")
    
    local isBound = getBindingStatus()
    
    if isBound then
        gpu.setForeground(COLORS.SUCCESS)
        gpu.set(popupX + 3, popupY + 5, "✅ Аккаунт ПРИВЯЗАН к: " .. boundPlayer)
        
        gpu.setForeground(COLORS.TEXT_MAIN)
        gpu.set(popupX + 3, popupY + 7, "   Для отвязки нажмите кнопку ниже")
        
        local unbindBtn = {
            text = "[ ОТВЯЗАТЬ ]",
            x = popupX + 5,
            y = popupY + popupHeight - 3,
            xs = unicode.len("[ ОТВЯЗАТЬ ]") + 2,
            ys = 1,
            bg = 0x441111,
            fg = COLORS.ERROR
        }
        drawFlexButton(unbindBtn)
        
        local closeBtn = {
            text = "[ ЗАКРЫТЬ ]",
            x = popupX + popupWidth - 13,
            y = popupY + popupHeight - 3,
            xs = 10,
            ys = 1,
            bg = COLORS.BG_BUTTON,
            fg = COLORS.ACCENT_SECONDARY
        }
        drawFlexButton(closeBtn)
        
        while currentScreen == "auth_popup" do
            local ev = {event.pull(0.5)}
            
            if ev[1] == "player_off" or ev[1] == "pim_player_leave" then
                writeDebugLog("👤 Игрок ушёл с PIM во время аутентификации")
                authCodeInput = ""
                currentScreen = "welcome"
                markDirty()
                break
            end
            
            if ev[1] == "touch" then
                local x, y = ev[3], ev[4]
                local touchPlayer = ev[6] or "Неизвестный"
                
                if not isPimOwner(touchPlayer) then
                    writeDebugLog("⚠️ Коснулся не владелец: " .. touchPlayer .. ", игнорируем")
                    goto continue_auth_bound
                end
                
                if isButtonClicked(closeBtn, x, y) then
                    authCodeInput = ""
                    goBackToMenu()
                    break
                end
                
                if isButtonClicked(unbindBtn, x, y) then
                    authCodeInput = ""
                    showUnbindConfirmPopup()
                    break
                end
            end
            
            ::continue_auth_bound::
        end
        
    else
        gpu.setForeground(COLORS.TEXT_MAIN)
        gpu.set(popupX + 3, popupY + 5, "📋 Введите код из браузера:")
        gpu.setForeground(COLORS.INACTIVE)
        gpu.set(popupX + 3, popupY + 6, "   (код отображается на сайте)")
        
        gpu.setBackground(COLORS.BLACK)
        gpu.fill(popupX + 5, popupY + 8, popupWidth - 10, 3, " ")
        gpu.setBackground(0x1A1A2E)
        gpu.fill(popupX + 6, popupY + 9, popupWidth - 12, 1, " ")
        
        gpu.setForeground(0x00FFAA)
        local displayCode = authCodeInput or ""
        if #displayCode < 6 then
            displayCode = displayCode .. "▌"
        end
        local codeX = popupX + 6 + math.floor((popupWidth - 12 - unicode.len(displayCode)) / 2)
        gpu.set(codeX, popupY + 9, displayCode)
        gpu.setBackground(COLORS.BG_POPUP)
        
        local btnY = popupY + popupHeight - 3
        
        local closeText = "[ ЗАКРЫТЬ ]"
        local qrText = "[ QR CODE ]"
        local confirmText = "[ ПОДТВЕРДИТЬ ]"
        
        local closeLen = unicode.len(closeText) + 2
        local qrLen = unicode.len(qrText) + 2
        local confirmLen = unicode.len(confirmText) + 2
        
        local totalBtnWidth = closeLen + qrLen + confirmLen
        local spacing = 2
        local totalSpacing = spacing * 2
        local totalWidth = totalBtnWidth + totalSpacing
        local startX = popupX + math.floor((popupWidth - totalWidth) / 2)
        
        local confirmBtn = {
            text = confirmText,
            x = startX,
            y = btnY,
            xs = confirmLen,
            ys = 1,
            bg = COLORS.BG_BUTTON,
            fg = COLORS.SUCCESS
        }
        
        local qrBtn = {
            text = qrText,
            x = startX + confirmLen + spacing,
            y = btnY,
            xs = qrLen,
            ys = 1,
            bg = COLORS.BG_BUTTON,
            fg = COLORS.ACCENT_MAIN
        }
        
        local closeBtn = {
            text = closeText,
            x = startX + confirmLen + spacing + qrLen + spacing,
            y = btnY,
            xs = closeLen,
            ys = 1,
            bg = COLORS.BG_BUTTON,
            fg = COLORS.ERROR
        }
        
        drawFlexButton(confirmBtn)
        drawFlexButton(qrBtn)
        drawFlexButton(closeBtn)
        
        local cursorVisible = true
        local cursorTimer = nil
        
        cursorTimer = event.timer(0.5, function()
            cursorVisible = not cursorVisible
            gpu.setBackground(0x1A1A2E)
            gpu.fill(popupX + 6, popupY + 9, popupWidth - 12, 1, " ")
            gpu.setForeground(0x00FFAA)
            local display = authCodeInput or ""
            if cursorVisible and #display < 6 then
                display = display .. "▌"
            end
            local codeX2 = popupX + 6 + math.floor((popupWidth - 12 - unicode.len(display)) / 2)
            gpu.set(codeX2, popupY + 9, display)
            gpu.setBackground(COLORS.BG_POPUP)
            return true
        end, math.huge)
        
        local isEditing = true
        while currentScreen == "auth_popup" and isEditing do
            local ev = {event.pull(0.5)}
            
            if ev[1] == "player_off" or ev[1] == "pim_player_leave" then
                writeDebugLog("👤 Игрок ушёл с PIM во время аутентификации")
                authCodeInput = ""
                if cursorTimer then
                    event.cancel(cursorTimer)
                    cursorTimer = nil
                end
                currentScreen = "welcome"
                markDirty()
                break
            end
            
            if ev[1] == "touch" then
                local x, y = ev[3], ev[4]
                local touchPlayer = ev[6] or "Неизвестный"
                
                if not isPimOwner(touchPlayer) then
                    writeDebugLog("⚠️ Коснулся не владелец: " .. touchPlayer .. ", игнорируем")
                    goto continue_auth
                end
                
                if isButtonClicked(closeBtn, x, y) then
                    isEditing = false
                    authCodeInput = ""
                    if cursorTimer then
                        event.cancel(cursorTimer)
                        cursorTimer = nil
                    end
                    goBackToMenu()
                    break
                end
                
                if isButtonClicked(qrBtn, x, y) then
                    gpu.setBackground(COLORS.BLACK)
                    gpu.fill(1, 1, 80, 25, " ")
                    showQRCodePopup()
                    break
                end
                
                if isButtonClicked(confirmBtn, x, y) then
                    if authCodeInput and #authCodeInput == 6 then
                        isEditing = false
                        local status = verifyAuthCodeOnServer(authCodeInput, currentPlayer)
                        if status == "SUCCESS" then
                            gpu.setForeground(COLORS.SUCCESS)
                            gpu.set(popupX + 3, popupY + 10, "✅ Аккаунт успешно привязан!")
                            os.sleep(1.5)
                            authCodeInput = ""
                            if cursorTimer then
                                event.cancel(cursorTimer)
                                cursorTimer = nil
                            end
                            forceSyncBinding()
                            clear()
                            currentScreen = "menu"
                            forceRender()
                            break
                        else
                            local msgData = AUTH_MESSAGES[status]
                            if msgData then
                                gpu.setForeground(msgData.color or COLORS.ERROR)
                                gpu.set(popupX + 3, popupY + 10, msgData.text)
                            else
                                gpu.setForeground(COLORS.ERROR)
                                gpu.set(popupX + 3, popupY + 10, "❌ Ошибка: " .. status)
                            end
                            os.sleep(2)
                            gpu.setBackground(COLORS.BG_POPUP)
                            gpu.fill(popupX + 3, popupY + 10, popupWidth - 6, 1, " ")
                            authCodeInput = ""
                            gpu.setBackground(0x1A1A2E)
                            gpu.fill(popupX + 6, popupY + 9, popupWidth - 12, 1, " ")
                            gpu.setForeground(0x00FFAA)
                            local display = "▌"
                            local codeX3 = popupX + 6 + math.floor((popupWidth - 12 - unicode.len(display)) / 2)
                            gpu.set(codeX3, popupY + 9, display)
                            gpu.setBackground(COLORS.BG_POPUP)
                            markDirty()
                            isEditing = true
                        end
                    else
                        gpu.setForeground(COLORS.ERROR)
                        gpu.set(popupX + 3, popupY + 10, " Введите 6-значный код!")
                        os.sleep(1.5)
                        gpu.setBackground(COLORS.BG_POPUP)
                        gpu.fill(popupX + 3, popupY + 10, popupWidth - 6, 1, " ")
                        markDirty()
                    end
                    break
                end
                
            elseif ev[1] == "key_down" then
                local ch = ev[3]
                local keyPlayer = ev[5] or "Неизвестный"
                
                if not isPimOwner(keyPlayer) then
                    writeDebugLog("⚠️ Нажал клавишу не владелец: " .. keyPlayer .. ", игнорируем")
                    goto continue_auth
                end
                
                if ch == 13 then
                    if authCodeInput and #authCodeInput == 6 then
                        isEditing = false
                        local status = verifyAuthCodeOnServer(authCodeInput, currentPlayer)
                        if status == "SUCCESS" then
                            gpu.setForeground(COLORS.SUCCESS)
                            gpu.set(popupX + 3, popupY + 10, "✅ Аккаунт успешно привязан!")
                            os.sleep(1.5)
                            authCodeInput = ""
                            if cursorTimer then
                                event.cancel(cursorTimer)
                                cursorTimer = nil
                            end
                            forceSyncBinding()
                            clear()
                            currentScreen = "menu"
                            forceRender()
                            break
                        else
                            local msgData = AUTH_MESSAGES[status]
                            if msgData then
                                gpu.setForeground(msgData.color or COLORS.ERROR)
                                gpu.set(popupX + 3, popupY + 10, msgData.text)
                            else
                                gpu.setForeground(COLORS.ERROR)
                                gpu.set(popupX + 3, popupY + 10, "❌ Ошибка: " .. status)
                            end
                            os.sleep(2)
                            gpu.setBackground(COLORS.BG_POPUP)
                            gpu.fill(popupX + 3, popupY + 10, popupWidth - 6, 1, " ")
                            authCodeInput = ""
                            gpu.setBackground(0x1A1A2E)
                            gpu.fill(popupX + 6, popupY + 9, popupWidth - 12, 1, " ")
                            gpu.setForeground(0x00FFAA)
                            local display = "▌"
                            local codeX4 = popupX + 6 + math.floor((popupWidth - 12 - unicode.len(display)) / 2)
                            gpu.set(codeX4, popupY + 9, display)
                            gpu.setBackground(COLORS.BG_POPUP)
                            markDirty()
                            isEditing = true
                        end
                    else
                        gpu.setForeground(COLORS.ERROR)
                        gpu.set(popupX + 3, popupY + 10, " Введите 6-значный код!")
                        os.sleep(1.5)
                        gpu.setBackground(COLORS.BG_POPUP)
                        gpu.fill(popupX + 3, popupY + 10, popupWidth - 6, 1, " ")
                        markDirty()
                    end
                    break
                    
                elseif ch == 8 then
                    authCodeInput = unicode.sub(authCodeInput or "", 1, -2)
                    gpu.setBackground(0x1A1A2E)
                    gpu.fill(popupX + 6, popupY + 9, popupWidth - 12, 1, " ")
                    gpu.setForeground(0x00FFAA)
                    local display = authCodeInput or ""
                    if #display < 6 then
                        display = display .. "▌"
                    end
                    local codeX5 = popupX + 6 + math.floor((popupWidth - 12 - unicode.len(display)) / 2)
                    gpu.set(codeX5, popupY + 9, display)
                    gpu.setBackground(COLORS.BG_POPUP)
                    
                elseif ch >= 48 and ch <= 57 then
                    if unicode.len(authCodeInput or "") < 6 then
                        authCodeInput = (authCodeInput or "") .. unicode.char(ch)
                        gpu.setBackground(0x1A1A2E)
                        gpu.fill(popupX + 6, popupY + 9, popupWidth - 12, 1, " ")
                        gpu.setForeground(0x00FFAA)
                        local display = authCodeInput or ""
                        if #display < 6 then
                            display = display .. "▌"
                        end
                        local codeX6 = popupX + 6 + math.floor((popupWidth - 12 - unicode.len(display)) / 2)
                        gpu.set(codeX6, popupY + 9, display)
                        gpu.setBackground(COLORS.BG_POPUP)
                    end
                end
            end
            
            ::continue_auth::
        end
        
        if cursorTimer then
            event.cancel(cursorTimer)
            cursorTimer = nil
        end
    end
end

AUTH_MESSAGES = {
    ["SUCCESS"] = { text = "✅ Аккаунт успешно привязан!", color = COLORS.SUCCESS },
    ["INVALID_CODE"] = { text = "❌ Неверный код", color = COLORS.ERROR },
    ["CODE_EXPIRED"] = { text = "⏰ Срок действия кода истек", color = COLORS.ERROR },
    ["CODE_USED"] = { text = "❌ Код уже был использован", color = COLORS.ERROR },
    ["ALREADY_LINKED"] = { text = "🔒 Данный игрок уже привязан", color = COLORS.ERROR },
    ["ALREADY_LINKED_SITE"] = { text = "🔒 Этот аккаунт уже привязан к другому игроку", color = COLORS.ERROR },
    ["ALREADY_LINKED_PLAYER"] = { text = "🔒 Игрок уже привязан к другому аккаунту", color = COLORS.ERROR },
    ["NICKNAME_MISMATCH"] = { text = "❌ Ник не совпадает с ожидаемым", color = COLORS.ERROR },
    ["TOO_MANY_ATTEMPTS"] = { text = "⛔ Превышено количество попыток", color = COLORS.ERROR },
    ["SERVER_ERROR"] = { text = "⚠️ Ошибка сервера", color = COLORS.ERROR },
}

function showQRCodePopup()
    writeDebugLog("showQRCodePopup()")
    
    qrPopupActive = true
    currentScreen = "qr_popup"
    
    local oldWidth, oldHeight = gpu.getResolution()
    
    gpu.setResolution(80, 25)
    gpu.setBackground(COLORS.BLACK)
    gpu.fill(1, 1, 80, 25, " ")
    
    gpu.setResolution(160, 50)
    gpu.setBackground(COLORS.BLACK)
    gpu.fill(1, 1, 160, 50, " ")
    
    gpu.setForeground(0x00FFCC)
    gpu.fill(1, 1, 160, 1, "=")
    gpu.fill(1, 50, 160, 1, "=")
    for i = 2, 49 do
        gpu.set(1, i, "|")
        gpu.set(160, i, "|")
    end
    gpu.set(1, 1, "+")
    gpu.set(160, 1, "+")
    gpu.set(1, 50, "+")
    gpu.set(160, 50, "+")
    
    local titleText = "QR-КОД ДЛЯ ВХОДА"
    local titleX = 80 - math.floor(#titleText / 2) + 2
    gpu.setForeground(0x00FFCC)
    gpu.set(titleX, 2, titleText)
    
    local playerText = "Игрок: " .. (currentPlayer or "?")
    local playerX = 80 - math.floor(#playerText / 2)   
    gpu.setForeground(COLORS.WHITE)
    gpu.set(playerX, 4, playerText)
    
    local hintText = "Отсканируйте QR-код для входа на сайт"
    local hintX = 80 - math.floor(#hintText / 2) + 11
    gpu.setForeground(COLORS.INACTIVE)
    gpu.set(hintX, 5, hintText)
    
    local qrY = 7
    local qrX = 44
    
    local asciiQR = [[
█████████████████████████████████████████████████████████████████████
█████████████████████████████████████████████████████████████████████
██████░░░░░░░░░░███████░██░░██████░██████░░░░██░░░███░░░░░░░░░░██████
████░░█████████░░████████░████░░██░░░██░░░░██░░░████░░█████████░░████
████░░██░░░░░██░░██████░░░████████░████░░░░████░████░░██░░░░░██░░████
████░░██░░░░░██░░████░░███░░██░░░░███████░░██░░░████░░██░░░░░██░░████
████░░██░░░░░██░░████░░░████████████░░░██░░██░░░████░░██░░░░░██░░████
████░░█████████░░███████░░░░░░░░░░░██░░░░██░░███░░██░░█████████░░████
█████░░░░░░░░░░░███░░██░██░░██░░██░██░░██░░██░██░░███░░░░░░░░░░░█████
███████████████████████░██░░░░░░░░░░░██░░░░███░░█████████████████████
████████░░░░███░░████░░░░░░░██░░███░░████░░░░███░░░░░░██░████████████
████████░░░░░░░██████░░░░░██░░░░░░█░░░░██████░░░██░░░░███████░░░░████
██████░░░░██░██░░░░█████░░░░████░░░██░░░░░░░░░░░░░██░░███████░░░░████
████████████░████████░░░█████████████████████░██████░░░░░░░██████████
████░░██████░░░░░░░██░░██████████████████████░░░░░░░██░░█████████████
████████░░██░██████░░██████░░░██████████████████░░████░░░██░░████████
██████░░░░░░░██░░██░░██░█████░░░░░░░░░░░██████████░░░░█████░░████████
████░░████░░█████████░░░██████░░░░░░░░░██████░████░░████░░░████░░████
██████████░░█░░░░░░████████████░░░░░░░████████░░░░██░░░░░░░██████████
█████████████░░██░░░░░░███████░░█████████████░░░████░░░░░██░░░░██████
████░░██░░██░░░░░░░██░░░████████████████████████████████░██░░████████
████░░░░█████████░░██░░░██████░░█████░░██████░████░░░░░░░████░░██████
████░░░░████░░░░░██░░░░██████████████████████░████░░█████░░░░████████
████░░██░░███░░██████░░░██████████████████████████░░███████░░██░░████
████████████░░░░░██████░████░░░░░░░░░░░████░░░██████░░░░█░░░░░░░░████
██████░░███████████░░░░░██░░░░████░████░░████░░░░░░░██░░█████░░░░████
████░░██████░░░░░░░░░███░░██░░█████░░██░░░░░░░░░░░░░░░░░░████░░░░████
███████████████████░░█████░░██░░░░░░░░░░░░░██░██░░██████░██░░░░██████
█████░░░░░░░░░░░███░░░░░██░░░░██░░░░░░░██████░░░░░██░░██░░░░░████████
████░░█████████░░████░░░░░░░░░████░████████░░░██░░██████░██░░░░░░████
████░░██░░░░░██░░█████████░░██████░██░░░░░░████░░░░░░░░░░░░░░░░██████
████░░██░░░░░██░░██░░███░░██░░░░░░█░░████░░░░███░░████░░█████████████
████░░██░░░░░██░░██░░███████████░░░██░░██░░██░░░░░░░░░░░░░░░░░░░░████
████░░█████████░░██████░░░██░░███████░░████░░█░░░░░░░░░░░░░░░░░░░████
██████░░░░░░░░░░████████░░████████░██░░███████░░░░░░░░░░░░░░░░░░░████
█████████████████████████████████████████████████████████████████████
█████████████████████████████████████████████████████████████████████
]]
    
    local lines = {}
    for line in asciiQR:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    
    for i, line in ipairs(lines) do
        gpu.set(qrX, qrY + i - 1, line)
    end
    
    local linkText = "Ссылка: https://zozido.pythonanywhere.com/"
    local linkX = 80 - math.floor(#linkText / 2) + 1
    gpu.setForeground(COLORS.INACTIVE)
    gpu.set(linkX, qrY + 39, linkText)
    
    local bottomHint = "[ Нажмите ЗАКРЫТЬ или ESC для возврата ]"
    local bottomHintX = 80 - math.floor(#bottomHint / 2) + 12
    gpu.setForeground(COLORS.TEXT_MAIN)
    gpu.set(bottomHintX, 48, bottomHint)
    
    local closeText = "[ ЗАКРЫТЬ ]"
    local closeLen = unicode.len(closeText) + 2
    local closeX = 80 - math.floor(closeLen / 2)
    
    local closeBtn = {
        text = closeText,
        x = closeX,
        y = 49,
        xs = closeLen,
        ys = 1,
        bg = COLORS.BG_BUTTON,
        fg = COLORS.ACCENT_SECONDARY
    }
    drawFlexButton(closeBtn)
    
    while currentScreen == "qr_popup" do
        local ev = {event.pull(0.5)}
        
        if currentScreen ~= "qr_popup" then
            writeDebugLog("⚠️ currentScreen изменился на " .. currentScreen .. ", выходим из QR")
            qrPopupActive = false
            break
        end
        
        if ev[1] == "touch" then
            local x, y = ev[3], ev[4]
            local touchPlayer = ev[6] or "Неизвестный"
            
            if not isPimOwner(touchPlayer) then
                writeDebugLog("⚠️ Коснулся не владелец: " .. touchPlayer .. ", игнорируем")
                goto continue_qr
            end
            
            if isButtonClicked(closeBtn, x, y) then
                writeDebugLog("✅ QR-код закрыт по кнопке")
                qrPopupActive = false
                currentScreen = "auth_popup"
                markDirty()
                break
            end
            
        elseif ev[1] == "key_down" then
            local code = ev[3]
            local keyPlayer = ev[5] or "Неизвестный"
            
            if not isPimOwner(keyPlayer) then
                writeDebugLog("⚠️ Нажал клавишу не владелец: " .. keyPlayer .. ", игнорируем")
                goto continue_qr
            end
            
            if code == 27 then
                writeDebugLog("✅ QR-код закрыт по ESC")
                qrPopupActive = false
                currentScreen = "auth_popup"
                markDirty()
                break
            end
        end
        
        ::continue_qr::
    end
    
    if qrPopupActive then
        qrPopupActive = false
    end
    
    gpu.setResolution(oldWidth, oldHeight)
    gpu.setBackground(COLORS.BLACK)
    gpu.fill(1, 1, oldWidth, oldHeight, " ")
    
    if currentScreen ~= "auth_popup" then
        currentScreen = "auth_popup"
        markDirty()
        showAuthPopup()
    end
end

function decodeBase64(data)
    if not data or data == "" then
        return ""
    end
    
    local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    local result = {}
    local padding = 0
    
    data = data:gsub('[^A-Za-z0-9+/=]', '')
    
    if data:sub(-1) == '=' then
        padding = padding + 1
    end
    if data:sub(-2, -1) == '==' then
        padding = padding + 1
    end
    
    for i = 1, #data, 4 do
        local chunk = data:sub(i, i + 3)
        local n = 0
        
        for j = 1, #chunk do
            local c = chunk:sub(j, j)
            if c ~= '=' then
                local index = b64chars:find(c)
                if index then
                    n = n * 64 + (index - 1)
                end
            end
        end
        
        local bytes = {}
        for j = 3, 1, -1 do
            if i + j - 1 <= #data - padding then
                table.insert(bytes, 1, string.char(n % 256))
                n = math.floor(n / 256)
            end
        end
        table.insert(result, table.concat(bytes))
    end
    
    return table.concat(result)
end

-- ============================================================
-- ★★★ ВЫПОЛНЕНИЕ ПОКУПКИ И ПРОДАЖИ ★★★
-- ============================================================

function performSell()
    if not playerAgreed then
        drawCenteredText(17, "Сначала примите пользовательское соглашение", COLORS.ERROR)
        os.sleep(2)
        markDirty()
        return
    end

    if TRANSACTION_LOCK then
        writeDebugLog("⚠️ Продажа уже выполняется")
        showTempMessage("Подождите, транзакция выполняется...", 2)
        return
    end
    lockTransactions()

    if sellConfirmItem and sellConfirmItem._processing then
        writeDebugLog("⚠️ Продажа уже выполняется, пропускаем")
        unlockTransactions()
        return
    end
    
    if sellConfirmItem and sellConfirmItem._processed then
        writeDebugLog("⚠️ Продажа уже обработана, пропускаем")
        unlockTransactions()
        return
    end

    showSellPopup = false
    markDirty()
    drawCenteredText(17, "Выполняется пополнение...", COLORS.ACCENT_MAIN)
    os.sleep(0.2)

    sellConfirmItem._processing = true

    local realExtracted = extractToME(sellConfirmItem.internalName, foundAmount, sellConfirmItem.damage or 0)
    if realExtracted == 0 then
        sellConfirmItem._processing = false
        drawCenteredText(17, "Не удалось изъять предметы! Проверьте инвентарь.", COLORS.ERROR)
        os.sleep(2)
        unlockTransactions()
        currentScreen = "shop_sell"
        markDirty()
        return
    end

    local value = realExtracted * sellConfirmItem.price
    if sellConfirmItem.internalName == "customnpcs:npcMoney" then
        emaBalance = emaBalance + value
    else
        coinBalance = coinBalance + value
    end
    playerTransactions = playerTransactions + 1

    if currentPlayer and cache_players[currentPlayer] then
        local player = cache_players[currentPlayer]
        player.balance = coinBalance
        player.emaBalance = emaBalance
        player.transactions = playerTransactions
        writeDebugLog("💾 Баланс сохранён после продажи для " .. currentPlayer .. ": Coin=" .. coinBalance .. ", EMA=" .. emaBalance)
    else
        writeErrorLog("⚠️ Игрок не найден при продаже: " .. tostring(currentPlayer))
    end

    addTransaction("sell", currentPlayer, sellConfirmItem.displayName, realExtracted, value, 0)

    sellConfirmItem._processed = true
    sellConfirmItem._processing = false

    gpu.setBackground(COLORS.BG_MAIN)
    gpu.fill(2, 17, 78, 1, " ")
    local currencySymbol = (sellConfirmItem.internalName == "customnpcs:npcMoney") and "۞" or "₵"
    drawCenteredText(17, "Успешно! +" .. string.format("%.2f", value) .. " " .. currencySymbol, COLORS.SUCCESS)
    os.sleep(0.8)

    unlockTransactions()
    currentScreen = "shop_sell"
    showSellPopup = false
    markDirty()
end

function performBuy()
    if not playerAgreed then
        drawCenteredText(20, "Сначала примите пользовательское соглашение", COLORS.ERROR)
        os.sleep(2)
        markDirty()
        return
    end

    if TRANSACTION_LOCK then
        writeDebugLog("⚠️ Покупка уже выполняется")
        showTempMessage("Подождите, транзакция выполняется...", 2)
        return
    end
    lockTransactions()

    if not purchaseItem then
        writeErrorLog("❌ performBuy: purchaseItem = nil!")
        unlockTransactions()
        return
    end

    local me = component.me_interface
    local item = purchaseItem

    local actualQty = getActualItemQuantity(item.internalName, item.damage)
    if actualQty <= 0 then
        drawCenteredText(20, "Товар закончился! Обновление списка...", COLORS.ERROR)
        os.sleep(0.8)
        loadBuyItems(true)
        unlockTransactions()
        currentScreen = "shop_buy"
        markDirty()
        return
    end

    local qty = purchaseQuantity
    if qty > actualQty then
        qty = actualQty
        purchaseQuantity = qty
        markDirty()
    end

    if qty <= 0 then
        drawCenteredText(20, "Выберите количество!", COLORS.ERROR)
        os.sleep(0.8)
        unlockTransactions()
        currentScreen = "shop_buy"
        markDirty()
        return
    end

    local totalCoin = (item.priceCoin or 0) * qty
    local totalEma = (item.priceEma or 0) * qty
    if coinBalance < totalCoin or emaBalance < totalEma then
        showInsufficientPopup = true
        insufficientBalanceCoin = coinBalance
        insufficientBalanceEma = emaBalance
        unlockTransactions()
        showInsufficientPopupAndWait() 
        return
    end

    drawCenteredText(20, "Выполняется покупка...", COLORS.ACCENT_MAIN)
    os.sleep(0.4)

    local id = item.internalName
    if not id:find(":") then
        id = "minecraft:" .. id
    end
    local fingerprint = { id = id, dmg = item.damage or 0 }

    local maxStackSize = 64
    local ok, detail = pcall(me.getItemDetail, me, item.internalName, item.damage)
    if ok and detail and detail.maxSize then
        maxStackSize = detail.maxSize
    end

    local remaining = qty
    local extracted = 0
    local lastError = nil

    while remaining > 0 do
        local toTake = math.min(remaining, maxStackSize)
        local success, result = pcall(function()
            return me.exportItem(fingerprint, PULL_DIRECTION, toTake)
        end)

        local got = 0
        if success then
            if type(result) == "number" then
                got = result
            elseif type(result) == "boolean" and result == true then
                got = toTake
            elseif type(result) == "table" then
                if result.count then
                    got = result.count
                elseif result.amount then
                    got = result.amount
                elseif result.size then
                    got = result.size
                else
                    got = toTake
                end
            else
                lastError = "неизвестный ответ: " .. tostring(result)
            end
        else
            lastError = tostring(result)
        end

        if got > 0 then
            extracted = extracted + got
            remaining = remaining - got
        else
            if lastError == nil then
                lastError = "не удалось выдать (вернулось 0 или false)"
            end
            break
        end
    end

    if extracted == 0 then
        showInventoryFullPopupAndWait()
        unlockTransactions()
        return
    end

    if extracted < qty then
        local actuallySpentCoin = extracted * (item.priceCoin or 0)
        local actuallySpentEma = extracted * (item.priceEma or 0)
        coinBalance = coinBalance - actuallySpentCoin
        emaBalance = emaBalance - actuallySpentEma
        playerTransactions = playerTransactions + 1

        if currentPlayer and cache_players[currentPlayer] then
            local player = cache_players[currentPlayer]
            player.balance = coinBalance
            player.emaBalance = emaBalance
            player.transactions = playerTransactions
            writeDebugLog("💾 Баланс сохранён (част.) для " .. currentPlayer .. ": Coin=" .. coinBalance .. ", EMA=" .. emaBalance)
        end

        addTransaction("buy", currentPlayer, item.displayName, extracted, actuallySpentCoin, actuallySpentEma)

        partialExtracted = extracted
        partialRequested = qty
        partialRefundCoin = actuallySpentCoin
        partialRefundEma = actuallySpentEma
        partialItem = item
        showPartialPopup = true
        unlockTransactions()
        showPartialPopupAndWait()
        return
    end

    coinBalance = coinBalance - totalCoin
    emaBalance = emaBalance - totalEma
    playerTransactions = playerTransactions + 1

    if currentPlayer and cache_players[currentPlayer] then
        local player = cache_players[currentPlayer]
        player.balance = coinBalance
        player.emaBalance = emaBalance
        player.transactions = playerTransactions
        writeDebugLog("💾 Баланс сохранён (полн.) для " .. currentPlayer .. ": Coin=" .. coinBalance .. ", EMA=" .. emaBalance)
    else
        writeErrorLog("⚠️ Игрок не найден при покупке: " .. tostring(currentPlayer))
    end

    addTransaction("buy", currentPlayer, item.displayName, extracted, totalCoin, totalEma)

    gpu.setBackground(COLORS.BG_MAIN)
    gpu.fill(2, 20, 78, 1, " ")
    local priceStr = ""
    if totalCoin > 0 then
        priceStr = priceStr .. string.format("%.2f", totalCoin) .. "₵"
    end
    if totalEma > 0 then
        if priceStr ~= "" then
            priceStr = priceStr .. " + "
        end
        priceStr = priceStr .. string.format("%.2f", totalEma) .. "۞"
    end
    drawCenteredText(20, "Куплено " .. extracted .. " шт. за " .. priceStr, COLORS.SUCCESS)

    loadBuyItems(true)
    for _, newItem in ipairs(shopItems) do
        if newItem.internalName == item.internalName and newItem.damage == item.damage then
            purchaseItem = newItem
            break
        end
    end
    os.sleep(0.8)
    unlockTransactions()
    currentScreen = "shop_buy"
    markDirty()
    
    writeDebugFile("========================================")
    writeDebugFile("✅ performBuy() ЗАВЕРШЕНА")
    writeDebugFile("   extracted=" .. tostring(extracted))
    writeDebugFile("   totalCoin=" .. tostring(totalCoin))
    writeDebugFile("   totalEma=" .. tostring(totalEma))
    writeDebugFile("   currentPlayer=" .. tostring(currentPlayer))
    writeDebugFile("========================================")
end

-- ============================================================
-- ★★★ ПОПАПЫ (Ожидание) ★★★
-- ============================================================

function showSellPopupAndWait()
    showSellPopup = true
    drawSellPopup()
    
    while showSellPopup do
        local ev = {event.pull(0.5)}
        
        if ev[1] == "player_off" or ev[1] == "pim_player_leave" then
            showSellPopup = false
            safeExit()
            return
        end
        
        if ev[1] == "touch" then
            local x, y = ev[3], ev[4]
            
            local popupWidth = 40
            local popupHeight = 10
            local popupX = math.floor((80 - popupWidth) / 2)
            local popupY = 10
            
            local yesBtn = {x=popupX+5, y=popupY+7, xs=13, ys=1}
            local noBtn  = {x=popupX+popupWidth-16, y=popupY+7, xs=12, ys=1}
            
            if isButtonClicked(yesBtn, x, y) then
                showSellPopup = false
                performSell()
                break
            elseif isButtonClicked(noBtn, x, y) then
                showSellPopup = false
                forceRender()
                break
            elseif not (x >= popupX and x < popupX + popupWidth and y >= popupY and y < popupY + popupHeight) then
                showSellPopup = false
                forceRender()
                break
            end
        end
    end
end

function showPartialPopupAndWait()
    showPartialPopup = true
    drawPartialPopup()
    
    while showPartialPopup do
        local ev = {event.pull(0.5)}
        
        if ev[1] == "player_off" or ev[1] == "pim_player_leave" then
            showPartialPopup = false
            safeExit()
            return
        end
        
        if ev[1] == "touch" then
            local x, y = ev[3], ev[4]
            
            local popupWidth = 52
            local popupHeight = 9
            local popupX = math.floor((80 - popupWidth) / 2)
            local popupY = 9
            
            local okBtnText = "[ ПРИНЯТЬ ]"
            local okBtnWidth = unicode.len(okBtnText) + 2
            local okBtn = {
                x = popupX + math.floor((popupWidth - okBtnWidth) / 2),
                y = popupY + 6,
                xs = okBtnWidth,
                ys = 1
            }
            
            if isButtonClicked(okBtn, x, y) then
                showPartialPopup = false
                forceRender()
                break
            end
            
            if not (x >= popupX and x < popupX + popupWidth and y >= popupY and y < popupY + popupHeight) then
                showPartialPopup = false
                forceRender()
                break
            end
        end
    end
end

function showInventoryFullPopupAndWait()
    showInventoryFullPopup = true
    drawInventoryFullPopup()
    
    while showInventoryFullPopup do
        local ev = {event.pull(0.5)}
        
        if ev[1] == "player_off" or ev[1] == "pim_player_leave" then
            showInventoryFullPopup = false
            safeExit()
            return
        end
        
        if ev[1] == "touch" then
            local x, y = ev[3], ev[4]
            
            local popupWidth = 52
            local popupHeight = 9
            local popupX = math.floor((80 - popupWidth) / 2)
            local popupY = 9
            
            local okBtnText = "[ ПОНЯТНО ]"
            local okBtnWidth = unicode.len(okBtnText) + 2
            local okBtn = {
                x = popupX + math.floor((popupWidth - okBtnWidth) / 2),
                y = popupY + 6,
                xs = okBtnWidth,
                ys = 1
            }
            
            if isButtonClicked(okBtn, x, y) then
                showInventoryFullPopup = false
                forceRender()
                break
            end
            
            if not (x >= popupX and x < popupX + popupWidth and y >= popupY and y < popupY + popupHeight) then
                showInventoryFullPopup = false
                forceRender()
                break
            end
        end
    end
end

function showInsufficientPopupAndWait()
    showInsufficientPopup = true
    drawInsufficientPopup()
    
    while showInsufficientPopup do
        local ev = {event.pull(0.5)}
        
        if ev[1] == "player_off" or ev[1] == "pim_player_leave" then
            showInsufficientPopup = false
            safeExit()
            return
        end
        
        if ev[1] == "touch" then
            local x, y = ev[3], ev[4]
            
            local popupWidth = 52
            local popupHeight = 11
            local popupX = math.floor((80 - popupWidth) / 2)
            local popupY = 7
            
            local okBtnText = "[ ПОНЯТНО ]"
            local okBtnWidth = unicode.len(okBtnText) + 2
            local okBtn = {
                x = popupX + math.floor((popupWidth - okBtnWidth) / 2),
                y = popupY + 8,
                xs = okBtnWidth,
                ys = 1
            }
            
            if isButtonClicked(okBtn, x, y) then
                showInsufficientPopup = false
                forceRender()
                break
            end
            
            if not (x >= popupX and x < popupX + popupWidth and y >= popupY and y < popupY + popupHeight) then
                showInsufficientPopup = false
                forceRender()
                break
            end
        end
    end
end

-- ============================================================
-- ★★★ РАССЫЛКА ОБНОВЛЕНИЙ ★★★
-- ============================================================

modem = component.modem
modem.open(0xffef)
modem.open(0xfffe)

markets = {}

event.listen("modem_message", function(_, _, from, port, _, _, data)
    if port == 0xffef then
        local ok, msg = pcall(serialization.unserialize, data)
        if ok and msg and msg.op == "register" then
            markets[from] = true
            writeDebugLog("📡 Терминал зарегистрирован: " .. from)
        end
    end
end)

function broadcastUpdate()
    writeDebugLog("📢 Рассылка обновления терминалам")
    local msg = serialization.serialize({
        op = "update_market",
        type = "reload_items"
    })
    for addr in pairs(markets) do
        pcall(modem.send, addr, 0xffef, msg)
    end
end

function broadcastKill()
    writeDebugLog("💀 Рассылка команды завершения терминалам")
    local msg = serialization.serialize({op="kill_market"})
    for addr in pairs(markets) do
        pcall(modem.send, addr, 0xffef, msg)
    end
end

-- ============================================================
-- ★★★ СОГЛАШЕНИЕ ★★★
-- ============================================================

drawAgreementScreen = nil
if fs.exists("/home/agreement.lua") then
    local ok, func = pcall(dofile, "/home/agreement.lua")
    if ok and type(func) == "function" then
        drawAgreementScreen = func
        writeDebugLog("✅ agreement.lua загружен")
    else
        writeErrorLog("❌ Ошибка загрузки agreement.lua")
    end
end
if not drawAgreementScreen then
    drawAgreementScreen = function()
        writeDebugLog("drawAgreementScreen (заглушка)")
        clear()
        drawScreenBorder()
        drawCenteredText(6, "ПОЛЬЗОВАТЕЛЬСКОЕ СОГЛАШЕНИЕ", COLORS.ACCENT_SECONDARY)
        drawCenteredText(8, "Файл agreement.lua не найден!", COLORS.ERROR)
        drawCenteredText(9, "Создайте его в папке /home/", COLORS.TEXT_MAIN)
        drawCenteredText(11, "Нажмите [НАЗАД] для возврата", COLORS.TEXT_MAIN)
        
        local backButton = {
            text = "[ НАЗАД ]",
            x = 37, y = 24,
            xs = unicode.len("[ НАЗАД ]") + 2,
            ys = 1,
            bg = COLORS.BG_BUTTON,
            fg = COLORS.ACCENT_SECONDARY
        }
        drawFlexButton(backButton)
        drawTempMessage()
        
        while currentScreen == "agreement" do
            local ev = {event.pull(0.5)}
            if ev[1] == "touch" then
                local x = tonumber(ev[3]) or 0
                local y = tonumber(ev[4]) or 0
                if isButtonClicked(backButton, x, y) then
                    goBackToMenu()
                    break
                end
            end
        end
    end
end

-- ============================================================
-- ★★★ КОМАНДЫ С САЙТА ★★★
-- ============================================================

function checkWebCommands()
    writeDebugFile(">>> checkWebCommands() ВЫЗВАНА в " .. getRealTimeHM())
    
    if currentPlayer then
        syncCurrentPlayer()
    end
    
    writeDebugLog("🔍 checkWebCommands() запущена в " .. getRealTimeHM())

    local success, err = pcall(function()
        local url = WEB_URL .. "/api/commands"
        writeDebugFile("📡 Запрос к: " .. url)

        local response = internet.request(url, nil, {
            ["Connection"] = "close",
            ["Timeout"] = 2
        })
        
        if not response then
            writeDebugFile("⚠️ Нет ответа от сервера")
            return
        end

        local status = response.getStatus and response:getStatus() or response.code or response.status
        if status then
            if status == 200 or status == 204 then
                writeDebugFile("✅ Статус ответа: " .. tostring(status))
            else
                writeDebugFile("⚠️ Сервер вернул HTTP " .. tostring(status))
                return
            end
        else
            writeDebugFile("⚠️ Не удалось получить статус ответа")
        end

        if status == 204 then
            writeDebugFile("⚠️ Сервер вернул 204 No Content, пропускаем")
            return
        end

        local body = ""
        for chunk in response do
            body = body .. chunk
        end

        writeDebugFile("📥 Получено " .. #body .. " байт")

        if #body < 10 then
            writeDebugFile("⚠️ Ответ слишком короткий")
            return
        end

        local data = parseJSON(body)
        if data then
            writeDebugFile("✅ Распарсено")
        else
            writeDebugFile("❌ Ошибка парсинга JSON")
            writeErrorLog("❌ Ошибка парсинга JSON: " .. string.sub(body, 1, 300))
            return
        end

        if not data.commands or #data.commands == 0 then
            writeDebugFile("⚠️ Нет команд в ответе")
            return
        end

        writeDebugFile("📨 Найдено команд: " .. #data.commands)

        for _, cmd in ipairs(data.commands) do
            local d = cmd.data or cmd
            local requestId = cmd.requestId or os.time()
        
            local function sendResult(success, msg, extra)
                writeDebugFile("📤 [" .. (cmd.command or "unknown") .. "] " .. (success and "✅" or "❌") .. " " .. (msg or ""))
                local payload = {
                    requestId = requestId,
                    success = success,
                    message = msg or "",
                    command = cmd.command
                }
                if extra then
                    for k, v in pairs(extra) do
                        payload[k] = v
                    end
                end
                sendToWeb("/api/command_result", toJson(payload))
            end
        
            writeDebugFile("🔧 Выполняем команду: " .. (cmd.command or "unknown"))
            writeDebugFile("📨 Данные команды: " .. serialization.serialize(d))
        
            -- === UPDATE_PLAYER / SET_BALANCE ===
            if cmd.command == "update_player" or cmd.command == "set_balance" then
                writeDebugFile("📥 Получена команда update_player")
                local playerName = d.name or d.player
                writeDebugFile("   playerName=" .. tostring(playerName))
                writeDebugFile("   balance=" .. tostring(d.balance))
                writeDebugFile("   emaBalance=" .. tostring(d.emaBalance))
                
                if not playerName then
                    sendResult(false, "Нет имени игрока")
                    goto continue
                end
                
                local player = cache_players[playerName]
                if player then
                    if d.balance then
                        player.balance = tonumber(d.balance) or 0
                        writeDebugFile("   ✅ Баланс установлен: " .. player.balance)
                    end
                    if d.emaBalance then
                        player.emaBalance = tonumber(d.emaBalance) or 0
                        writeDebugFile("   ✅ EMA баланс установлен: " .. player.emaBalance)
                    end
                    addTransactionLog("Баланс обновлён: " .. playerName, "BALANCE")
                    markDirty()
                    
                    if currentPlayer == playerName then
                        coinBalance = player.balance
                        emaBalance = player.emaBalance
                        writeDebugFile("   ✅ ТЕКУЩИЙ ИГРОК ОБНОВЛЁН: Coin=" .. coinBalance .. ", EMA=" .. emaBalance)
                    end
                    
                    sendResult(true, "Баланс обновлён")
                else
                    writeDebugFile("   ❌ Игрок не найден")
                    sendResult(false, "Игрок не найден")
                end
                goto continue
            end
            
            -- === UPDATE CACHE ===
            if cmd.command == "update_cache" then
                writeDebugLog("📦 Получена команда обновления кеша")
                updateCache()
                if currentScreen == "shop_buy" or currentScreen == "shop_sell" then
                    loadBuyItems(true)
                    markDirty()
                end
                sendResult(true, "Кеш обновлён")
                goto continue
            end

            -- === TOGGLE PAUSE ===
            if cmd.command == "toggle_pause" then
                if d.paused ~= nil then
                    shopPaused = d.paused
                    cache_shop_paused = d.paused
                    writeDebugFile("📥 Установлен режим обслуживания: " .. tostring(shopPaused))
                else
                    shopPaused = not shopPaused
                    cache_shop_paused = shopPaused
                    writeDebugFile("📥 Переключён режим обслуживания: " .. tostring(shopPaused))
                end
                
                addLog(shopPaused and "⏸️ Магазин переведён в режим обслуживания" or "🟢 Магазин открыт")
                sendToWeb("/api/shop_status", toJson({ paused = shopPaused }))
                
                local msg = serialization.serialize({op = "shop_paused", paused = shopPaused})
                for addr in pairs(markets or {}) do
                    pcall(modem.send, addr, 0xffef, msg)
                end
                
                markDirty()
                sendResult(true, shopPaused and "Магазин на паузе" or "Магазин активен")
                goto continue
            end
            
            -- === UPDATE MARKET ===
            if cmd.command == "update_market" then
                broadcastUpdate()
                sendResult(true, "Обновление разослано")
                goto continue
            end
            
            -- === KILL MARKET ===
            if cmd.command == "kill_market" then
                broadcastKill()
                sendResult(true, "Терминалы будут завершены")
                goto continue
            end
            
            -- === TERMINAL CONTROL ===
            if cmd.command == "terminal_control" then
                local action = d.action
                writeDebugFile("🚨 ПОЛУЧЕНА КОМАНДА: " .. action)
                
                if action == "shutdown" then
                    writeDebugFile("⏻ ВЫКЛЮЧЕНИЕ ТЕРМИНАЛА")
                    sendResult(true, "Терминал выключается...")
                    os.sleep(0.5)
                    
                    local shutdown_attempts = {
                        function() computer.shutdown() end,
                        function() os.execute("shutdown -h now") end,
                        function() os.execute("shutdown") end,
                        function() os.exit(0) end
                    }
                    
                    for i, func in ipairs(shutdown_attempts) do
                        local ok, err = pcall(func)
                        if ok then
                            writeDebugFile("✅ Выключение успешно (способ " .. i .. ")")
                            break
                        else
                            writeDebugFile("⚠️ Способ " .. i .. " не сработал: " .. tostring(err))
                        end
                    end
                    
                elseif action == "reboot" then
                    writeDebugFile("🔄 ПЕРЕЗАГРУЗКА ТЕРМИНАЛА")
                    sendResult(true, "Терминал перезагружается...")
                    os.sleep(0.5)
                    
                    local reboot_attempts = {
                        function() computer.reboot() end,
                        function() os.execute("reboot") end,
                        function() os.execute("shutdown -r now") end,
                        function() os.exit(1) end
                    }
                    
                    for i, func in ipairs(reboot_attempts) do
                        local ok, err = pcall(func)
                        if ok then
                            writeDebugFile("✅ Перезагрузка успешна (способ " .. i .. ")")
                            break
                        else
                            writeDebugFile("⚠️ Способ " .. i .. " не сработал: " .. tostring(err))
                        end
                    end
                    
                elseif action == "toggle_autostart" then
                    writeDebugFile("🔄 ПЕРЕКЛЮЧЕНИЕ АВТОЗАПУСКА")
                    
                    local shrcPath = "/home/.shrc"
                    local autostartEnabled = false
                    
                    if fs.exists(shrcPath) then
                        local file = io.open(shrcPath, "r")
                        if file then
                            local content = file:read("*a")
                            file:close()
                            if content and (content:find("startup.lua") or content:find("pimmarket")) then
                                autostartEnabled = true
                            end
                        end
                    end
                    
                    local newStatus = false
                    
                    if autostartEnabled then
                        if fs.exists(shrcPath) then
                            if fs.exists(shrcPath .. ".bak") then
                                fs.remove(shrcPath .. ".bak")
                            end
                            fs.rename(shrcPath, shrcPath .. ".bak")
                            writeDebugLog("❌ Автозапуск ОТКЛЮЧЁН")
                            addLog("❌ Автозапуск терминала отключён")
                            newStatus = false
                        end
                    else
                        if fs.exists(shrcPath .. ".bak") then
                            if fs.exists(shrcPath) then
                                fs.remove(shrcPath)
                            end
                            fs.rename(shrcPath .. ".bak", shrcPath)
                            writeDebugLog("✅ Автозапуск ВКЛЮЧЁН")
                            addLog("✅ Автозапуск терминала включён")
                            newStatus = true
                        else
                            local file = io.open(shrcPath, "w")
                            if file then
                                file:write("lua /home/pimmarket.lua\n")
                                file:close()
                                writeDebugLog("✅ Автозапуск ВКЛЮЧЁН (создан новый .shrc)")
                                addLog("✅ Автозапуск терминала включён")
                                newStatus = true
                            else
                                writeDebugLog("❌ Не удалось создать .shrc")
                                sendResult(false, "Не удалось создать .shrc")
                                goto continue
                            end
                        end
                    end
                    
                    sendResult(true, newStatus and "Автозапуск включён" or "Автозапуск отключён", {autostart_enabled = newStatus})
                    goto continue
                    
                elseif action == "restart_script" then
                    writeDebugFile("🔄 ПЕРЕЗАПУСК СКРИПТА")
                    sendResult(true, "Перезапуск скрипта...")
                    os.sleep(0.5)
                    
                    forceSaveData()
                    
                    local scriptPath = "/home/pimmarket.lua"
                    if fs.exists(scriptPath) then
                        local pid = shell.execute("lua " .. scriptPath .. " &")
                        writeDebugLog("✅ Новый процесс запущен: " .. tostring(pid))
                        os.exit(0)
                    else
                        writeDebugLog("❌ Скрипт не найден: " .. scriptPath)
                        sendResult(false, "Скрипт не найден")
                    end
                end
                goto continue
            end
            
            -- === UNBIND PLAYER ===
            if cmd.command == "unbind_player" then
                local playerName = d.player
                writeDebugFile("📥 Получена команда отвязки для: " .. playerName)
                
                if currentPlayer == playerName then
                    boundPlayer = nil
                    bindingCache.isBound = false
                    bindingCache.lastCheck = 0
                    if cache_players[currentPlayer] then
                        cache_players[currentPlayer].site_user = nil
                    end
                    addBindingLog("Аккаунт отвязан по команде сервера: " .. playerName, "UNLINK")
                    markDirty()
                    sendResult(true, "Аккаунт отвязан")
                else
                    sendResult(false, "Игрок не найден")
                end
                goto continue
            end

            -- === SYNC BINDING ===
            if cmd.command == "sync_binding" then
                local playerName = d.player
                local siteUser = d.site_user
                writeDebugFile("📥 Получена команда синхронизации привязки для: " .. playerName)
                
                if playerName and cache_players[playerName] then
                    local player = cache_players[playerName]
                    if siteUser and siteUser ~= "" then
                        player.site_user = siteUser
                        addBindingLog("Привязка синхронизирована: " .. playerName .. " -> " .. siteUser, "LINK")
                    else
                        player.site_user = nil
                        addBindingLog("Привязка удалена: " .. playerName, "UNLINK")
                    end
                    markDirty()
                    sendResult(true, "Привязка синхронизирована")
                else
                    sendResult(false, "Игрок не найден")
                end
                goto continue
            end
            
            -- === DELETE FEEDBACK ===
            if cmd.command == "delete_feedback" then
                local index = d.index
                writeDebugFile("🗑️ Удаление отзыва: индекс " .. tostring(index))
                
                if type(index) == "number" and index >= 1 and index <= #cache_feedbacks then
                    table.remove(cache_feedbacks, index)
                    writeDebugFile("✅ Отзыв удалён из кеша")
                    sendResult(true, "Отзыв удалён")
                else
                    writeDebugFile("⚠️ Индекс не найден: " .. tostring(index) .. ", всего отзывов: " .. #cache_feedbacks)
                    sendResult(false, "Индекс не найден")
                end
                goto continue
            end
            
            -- === FEEDBACK VIEWED ===
            if cmd.command == "feedback_viewed" then
                local index = d.index
                writeDebugFile("📌 Отметка отзыва как просмотренного: индекс " .. tostring(index))
                
                if type(index) == "number" and index >= 1 and index <= #cache_feedbacks then
                    cache_feedbacks[index].viewed = true
                    writeDebugFile("✅ Отзыв отмечен как просмотренный")
                    sendResult(true, "Отзыв отмечен")
                else
                    writeDebugFile("⚠️ Индекс не найден: " .. tostring(index))
                    sendResult(false, "Индекс не найден")
                end
                goto continue
            end

            -- === NEW FEEDBACK ===
            if cmd.command == "new_feedback" then
                local feedback = d.feedback
                writeDebugFile("📝 Новый отзыв от " .. (feedback and feedback.name or "?"))
                
                if feedback then
                    if not feedback.rating then feedback.rating = 5 end
                    table.insert(cache_feedbacks, 1, feedback)
                    writeDebugFile("✅ Отзыв добавлен в кеш")
                    sendResult(true, "Отзыв обработан")
                else
                    sendResult(false, "Нет данных")
                end
                goto continue
            end

            -- === SYNC FEEDBACK ===
            if cmd.command == "sync_feedback" then
                local playerName = d.player
                local hasFeedback = d.hasFeedback
                writeDebugFile("📥 Получена команда sync_feedback для: " .. playerName)
                
                if playerName and cache_players[playerName] then
                    cache_players[playerName].hasFeedback = hasFeedback
                    if currentPlayer == playerName then
                        playerHasFeedback = hasFeedback
                        markDirty()
                    end
                    addLog("🔄 Синхронизирован флаг отзыва для " .. playerName .. ": " .. tostring(hasFeedback))
                    sendResult(true, "Флаг отзыва синхронизирован")
                else
                    sendResult(false, "Игрок не найден")
                end
                goto continue
            end

            -- === AGREE ===
            if cmd.command == "agree" then
                writeDebugFile("📝 Получена команда agree для: " .. (d.name or "?"))
                local playerName = d.name
                if not playerName then
                    sendResult(false, "Нет имени игрока")
                    goto continue
                end
                
                if cache_players[playerName] then
                    cache_players[playerName].agreed = true
                    if currentPlayer == playerName then
                        playerAgreed = true
                        markDirty()
                    end
                    addLog("📝 " .. playerName .. " принял пользовательское соглашение")
                    sendResult(true, "Соглашение принято")
                else
                    sendResult(false, "Игрок не найден")
                end
                goto continue
            end

            sendResult(false, "Неизвестная команда: " .. tostring(cmd.command))
            
            ::continue::
        end  
     end)

    if not success then
        writeDebugFile("❌ Критическая ошибка в checkWebCommands: " .. tostring(err))
        writeErrorLog("❌ Критическая ошибка в checkWebCommands: " .. tostring(err))
    end
end

-- ============================================================
-- ★★★ ТАЙМЕРЫ ★★★
-- ============================================================

-- Загрузка всех данных при старте
loadAllDataFromHost()
loadTransactionBuffer()

-- Обновление кеша товаров (каждые 30 секунд)
createTimer(30, function()
    updateCache()
    return true
end, true)

-- Отправка буфера транзакций (каждые 10 секунд)
createTimer(10, function()
    if #transaction_buffer > 0 then
        flushTransactionBuffer()
    end
    return true
end, true)

-- Полная синхронизация (каждые 5 минут)
createTimer(300, function()
    if not isSyncing then
        loadAllDataFromHost()
    end
    return true
end, true)

-- Проверка команд с сайта (каждые 10 секунд) — ОСТАЁТСЯ!
event.timer(10, function()
    if not TRANSACTION_LOCK then
        checkWebCommands()
    end
    return true
end, math.huge)

-- Отправка статистики (каждые 30 минут)
createTimer(1800, function()
    if not TRANSACTION_LOCK then
        pcall(sendStats)
    end
    return true
end, true)

-- Системная информация (каждые 5 минут)
createTimer(300, function()
    if not TRANSACTION_LOCK then
        local sysInfo = getSystemInfo()
        sendToWeb("/api/system_info", toJson(sysInfo))
        writeDebugLog("📊 Отправлены системные данные отдельным пакетом")
    end
    return true
end, true)

-- ============================================================
-- ★★★ ОСНОВНОЙ ЦИКЛ ★★★
-- ============================================================

function main()
    addConsoleLog("🚀 main() запущен", COLORS.SUCCESS)
    drawWelcomeScreen()
    
    addErrorLog("🟢 Терминал #1 (PIM MARKET) запущен", "INFO")

    while true do
        local ev = {event.pull(0.5)}
        local e = ev[1]

        if e == "key_down" then
            local playerName = ev[5] or "Неизвестный"
            local keyCode = ev[3] or 0
            
            if keyCode == 18 or keyCode == 17 or keyCode == 16 or keyCode == 91 or keyCode == 93 then
                goto continue
            end
            
            if not isPimOwner(playerName) then
                goto continue
            end
            
            if currentScreen == "report" and canSendReport() then
                local ch = ev[3]
                if ch == 13 then
                    markDirty()
                elseif ch == 8 then
                    reportInput = unicode.sub(reportInput or "", 1, -2)
                    markDirty()
                elseif ch >= 32 then
                    reportInput = (reportInput or "") .. unicode.char(ch)
                    markDirty()
                end
            elseif (currentScreen == "shop_buy" or currentScreen == "shop_sell") and searchActive then
                local ch = ev[3]
                if ch == 13 then
                    shopSearch = searchInput or ""
                    searchActive = false
                    listScroll = 1
                    selectedIndex = 0
                    selectedItem = nil
                    hoveredIndex = 0
                    markDirty()
                elseif ch == 8 then
                    searchInput = unicode.sub(searchInput or "", 1, -2)
                    shopSearch = searchInput or ""
                    filteredItems = getFilteredItems()
                    drawBuyItemsList()
                    redrawSearchField()
                    
                    if shopSearch == "" then
                        if selectedItem ~= nil then
                            selectedItem = nil
                            selectedIndex = 0
                            drawBuyButtons()
                        end
                    end
                elseif ch >= 32 then
                    searchInput = (searchInput or "") .. unicode.char(ch)
                    shopSearch = searchInput or ""
                    filteredItems = getFilteredItems()
                    drawBuyItemsList()
                    redrawSearchField()
                    
                    if selectedItem ~= nil then
                        local stillVisible = false
                        for _, item in ipairs(filteredItems) do
                            if item == selectedItem then
                                stillVisible = true
                                break
                            end
                        end
                        if not stillVisible then
                            selectedItem = nil
                            selectedIndex = 0
                            drawBuyButtons()
                        end
                    end
                end
                goto continue
            elseif currentScreen == "feedback_input" and feedbackEditMode then
                local ch = ev[3]
                if ch == 13 then
                    if feedbackInput and feedbackInput ~= "" then
                        local feedbackData = {
                            name = currentPlayer or "Аноним",
                            text = feedbackInput,
                            time = getRealTimeString(),
                            rating = feedbackRating or 5
                        }
                        
                        sendToWeb("/api/new_feedback", toJson(feedbackData))
                        table.insert(cache_feedbacks, 1, feedbackData)
                        
                        playerHasFeedback = true
                        if currentPlayer and cache_players[currentPlayer] then
                            cache_players[currentPlayer].hasFeedback = true
                        end
                        
                        showTempMessage("✅ Отзыв отправлен! Спасибо!", 10)
                    end
                    feedbackEditMode = false
                    feedbackInput = ""
                    feedbackRating = 5
                    currentScreen = "feedbacks"
                    markDirty()
                elseif ch == 8 then
                    feedbackInput = unicode.sub(feedbackInput or "", 1, -2)
                    markDirty()
                elseif ch >= 49 and ch <= 53 then
                    feedbackRating = ch - 48
                    markDirty()
                elseif ch >= 32 then
                    if unicode.len(feedbackInput or "") < 200 then
                        feedbackInput = (feedbackInput or "") .. unicode.char(ch)
                        markDirty()
                    end
                end
                goto continue
            end
            goto continue
        end

        if currentScreen == "auth" then
            if os.clock() - authStartTime >= AUTH_TIMEOUT then
                currentScreen = "menu"
                markDirty()
            end
        end

        if e == "touch" then
            local x = tonumber(ev[3]) or 0
            local y = tonumber(ev[4]) or 0
            local playerName = ev[6] or "Неизвестный"
            
            if currentScreen == "auth_popup" then
                local currentOnPim = getPlayerOnPim()
                if not currentOnPim or currentOnPim == "" then
                    goto continue
                end
                if currentPlayer and currentOnPim ~= currentPlayer then
                    writeDebugLog("⚠️ На PIM другой игрок, игнорируем touch в auth_popup")
                    goto continue
                end
                if playerName ~= currentPlayer then
                    writeDebugLog("⚠️ Коснулся не владелец: " .. playerName .. ", игнорируем")
                    goto continue
                end
            end
            
            if not isPimOwner(playerName) then
                goto continue
            end

            if currentPlayer and playerName ~= currentPlayer then
                writeDebugLog("⚠️ Игрок сменился! Было: " .. currentPlayer .. ", стало: " .. playerName)
                if currentPlayer then
                    safeExit()
                end
                goto continue
            end

            if currentScreen == "menu" then
                for name, btn in pairs(menuButtons) do
                    if x >= btn.x and x < btn.x + btn.xs and y >= btn.y and y < btn.y + btn.ys then
                        if name == "shop" then
                            if playerAgreed then
                                goToShop()
                            else
                                showShopDenied = true
                                markDirty()
                            end
                        elseif name == "account" then
                            showShopDenied = false
                            goToAccount()
                        end
                        goto continue
                    end
                end
                
                if x >= 4 and x < 4 + unicode.len("[ ПОДДЕРЖКА ]") and y == 24 then
                    goToReport()
                    goto continue
                end
                
                if x >= 35 and x < 35 + unicode.len("[ СОГЛАШЕНИЕ ]") and y == 24 then
                    if type(drawAgreementScreen) == "function" then
                        currentScreen = "agreement"
                        markDirty()
                    else
                        showTempMessage("Файл соглашения не найден!", 2)
                    end
                    goto continue
                end
                
                if x >= 68 and x < 68 + unicode.len("[ ОТЗЫВЫ ]") and y == 24 then
                    currentScreen = "feedbacks"
                    feedbacksPage = 1
                    markDirty()
                    goto continue
                end
                
            end

            if currentScreen == "shop" then
                for name, btn in pairs(shopMenuButtons) do
                    if x >= btn.x and x < btn.x + btn.xs and y >= btn.y and y < btn.y + btn.ys then
                        if name == "buy" then
                            goToBuy()
                        elseif name == "sell" then
                            goToSell()
                        end
                        goto continue
                    end
                end
                local backButton = {
                    text = "[ НАЗАД ]",
                    x = 37, y = 24,
                    xs = unicode.len("[ НАЗАД ]") + 2,
                    ys = 1,
                    bg = COLORS.BG_BUTTON,
                    fg = COLORS.ACCENT_SECONDARY
                }
                if isButtonClicked(backButton, x, y) then
                    goBackToMenu()
                    goto continue
                end
            end

            if currentScreen == "shop_buy" or currentScreen == "shop_sell" then
                if y >= 7 and y <= 21 and x >= 2 and x <= 77 then
                    local relativeRow = y - 6
                    local clickedIndex = (listScroll or 1) + relativeRow - 1
                    local item = filteredItems[clickedIndex]
                    
                    if item and (currentShopMode ~= "buy" or item.qty > 0) then
                        local oldSelectedIndex = selectedIndex
                        selectedIndex = clickedIndex
                        selectedItem = item
                        hoveredIndex = 0
                        
                        if oldSelectedIndex > 0 and oldSelectedIndex ~= clickedIndex then
                            local oldRow = oldSelectedIndex - listScroll + 1
                            if oldRow >= 1 and oldRow <= visibleRows then
                                local oldItem = filteredItems[oldSelectedIndex]
                                if oldItem then
                                    drawSingleRow(6 + oldRow, oldItem, false, false, oldSelectedIndex)
                                end
                            end
                        end
                        
                        local newRow = clickedIndex - listScroll + 1
                        if newRow >= 1 and newRow <= visibleRows then
                            drawSingleRow(6 + newRow, item, false, true, clickedIndex)
                        end
                        
                        drawBuyButtons()
                        updateSelectorDisplay(selectedItem)
                    end
                    goto continue
                end

                if x >= 78 and y >= 7 and y <= 21 then
                    local total = #filteredItems
                    if total > visibleRows then
                        local clickPos = y - 6
                        listScroll = math.floor((clickPos - 1) * (total - visibleRows) / visibleRows) + 1
                        drawBuyItemsList()
                    end
                    goto continue
                end

                if y == 3 and x >= 42 and x <= 64 then
                    searchActive = true
                    searchInput = shopSearch or ""
                    redrawSearchField()
                    goto continue
                end

                if y == 3 and x >= 66 and x <= 78 then
                    shopSearch = ""
                    searchInput = ""
                    searchActive = false
                    listScroll = 1
                    selectedIndex = 0
                    selectedItem = nil
                    hoveredIndex = 0
                    filteredItems = getFilteredItems()
                    drawBuyItemsList()
                    redrawSearchField()
                    drawBuyButtons()
                    goto continue
                end

                local backButton = {
                    text = "[ НАЗАД ]",
                    x = 37, y = 24,
                    xs = unicode.len("[ НАЗАД ]") + 2,
                    ys = 1,
                    bg = COLORS.BG_BUTTON,
                    fg = COLORS.ACCENT_SECONDARY
                }

                if isButtonClicked(backButton, x, y) then
                    currentScreen = "shop"
                    selectedIndex = 0
                    selectedItem = nil
                    hoveredIndex = 0
                    updateSelectorDisplay(nil)
                    markDirty()
                    goto continue
                end

                local nextButton = {}
                if currentShopMode == "buy" then
                    nextButton.text = "[ КУПИТЬ ]"
                    nextButton.xs = unicode.len(nextButton.text) + 2
                else
                    nextButton.text = "[ ПРОДАТЬ ]"
                    nextButton.xs = unicode.len(nextButton.text) + 2
                end
                nextButton.x = 59
                nextButton.y = 24
                nextButton.ys = 1
                nextButton.bg = COLORS.BG_BUTTON
                
                local isActive = selectedItem and (currentShopMode ~= "buy" or selectedItem.qty > 0)
                if isActive then
                    nextButton.fg = COLORS.ACCENT_SECONDARY
                else
                    nextButton.fg = COLORS.INACTIVE
                end

                if isButtonClicked(nextButton, x, y) then
                    if selectedItem and (currentShopMode ~= "buy" or selectedItem.qty > 0) then
                        if currentShopMode == "buy" then
                            local needCoin = selectedItem.priceCoin or 0
                            local needEma = selectedItem.priceEma or 0
                            
                            if (needCoin > 0 and coinBalance < needCoin) or (needEma > 0 and emaBalance < needEma) then
                                insufficientBalanceCoin = coinBalance
                                insufficientBalanceEma = emaBalance
                                showInsufficientPopupAndWait()
                                goto continue
                            end
                            goToPurchase(selectedItem)
                        else
                            goToSellConfirm(selectedItem)
                        end
                    end
                    goto continue
                end

                if searchActive then
                    shopSearch = searchInput or ""
                    searchActive = false
                    listScroll = 1
                    selectedIndex = 0
                    selectedItem = nil
                    hoveredIndex = 0
                    markDirty()
                    goto continue
                end
            end

            if showSellPopup and currentScreen == "sell_scan" then
                goto continue
            end

            if currentScreen == "purchase" then
                if (y >= 24 and y <= 24) and (x >= 19 and x <= 28) then
                    if currentShopMode == "buy" then
                        currentScreen = "shop_buy"
                        markDirty()
                    else
                        currentScreen = "shop_sell"
                        markDirty()
                    end
                    goto continue
                elseif (y >= 24 and y <= 24) and (x >= 51 and x <= 61) then
                    performBuy()
                    goto continue
                end

                local startX = 34
                local startY = 11
                local btnW = 3
                local btnH = 1
                local spacing = 2
                local keys = {
                    {"1","2","3"},
                    {"4","5","6"},
                    {"7","8","9"},
                    {"<","0","C"}
                }
                for row = 1, 4 do
                    for col = 1, 3 do
                        local bx = startX + (col-1)*(btnW + spacing)
                        local by = startY + (row-1)*(btnH + 1)
                        if x >= bx and x < bx+btnW and y >= by and y < by+btnH then
                            handleQuantityButtonClick(keys[row][col])
                            goto continue
                        end
                    end
                end
            end

            if currentScreen == "sell_scan" then
                local backButton = {
                    text = "[ НАЗАД ]",
                    x = 37, y = 24,
                    xs = unicode.len("[ НАЗАД ]") + 2,
                    ys = 1,
                    bg = COLORS.BG_BUTTON,
                    fg = COLORS.ACCENT_SECONDARY
                }
                if isButtonClicked(backButton, x, y) then
                    currentScreen = "shop_sell"
                    showSellPopup = false
                    markDirty()
                    goto continue
                elseif y == 13 and x >= 30 and x <= 50 then
                    drawCenteredText(17, "Сканирование...", COLORS.ACCENT_SECONDARY)
                    os.sleep(0.6)
                    if not sellConfirmItem then
                        writeErrorLog("❌ sellConfirmItem = nil при сканировании!")
                        goto continue
                    end
                    foundAmount = scanPlayerInventory(sellConfirmItem.internalName, sellConfirmItem.damage or 0)
                    if foundAmount > 0 then
                        showSellPopupAndWait()
                    else
                        drawCenteredText(17, "Предмет не найден!", COLORS.ERROR)
                        os.sleep(0.8)
                        markDirty()
                    end
                    goto continue
                end
            end

            if currentScreen == "report" then
                local backButton = {
                    text = "[ НАЗАД ]",
                    x = 37, y = 24,
                    xs = unicode.len("[ НАЗАД ]") + 2,
                    ys = 1,
                    bg = COLORS.BG_BUTTON,
                    fg = COLORS.ACCENT_SECONDARY
                }
                if isButtonClicked(backButton, x, y) then
                    goBackToMenu()
                    goto continue
                end
                if canSendReport() then
                    local sendBtn = {x=33, y=14, xs=17, ys=1}
                    if isButtonClicked(sendBtn, x, y) and reportInput and reportInput ~= "" then
                        sendToWeb("/api/new_report", toJson({
                            time = getRealTimeString(),
                            name = currentPlayer or "?",
                            text = reportInput
                        }))
                        addLog("📩 Репорт от " .. (currentPlayer or "?"))
                        lastReportTime = getRealTimestamp()
                        drawCenteredText(18, "Сообщение успешно отправлено! Ожидайте ответа.", COLORS.SUCCESS)
                        os.sleep(0.8)
                        goBackToMenu()
                        goto continue
                    end
                end
            end

            if currentScreen == "feedbacks" then
                local backBtn = {x=5, y=24, xs=11, ys=1}
                if isButtonClicked(backBtn, x, y) then
                    currentScreen = "menu"
                    markDirty()
                    goto continue
                end
                
                local showAddButton = not playerHasFeedback
                
                if showAddButton then
                    local addBtn = {x=36, y=24, xs=14, ys=1}
                    if isButtonClicked(addBtn, x, y) then
                        if currentPlayer then
                            local player = cache_players[currentPlayer]
                            if player then
                                playerHasFeedback = player.hasFeedback or false
                                if not playerHasFeedback then
                                    for _, fb in ipairs(cache_feedbacks) do
                                        if fb.name == currentPlayer then
                                            playerHasFeedback = true
                                            player.hasFeedback = true
                                            break
                                        end
                                    end
                                end
                            end
                        end
                        
                        if playerHasFeedback then
                            showTempMessage("Вы уже оставляли отзыв!", 2)
                        else
                            feedbackInput = ""
                            feedbackEditMode = true
                            currentScreen = "feedback_input"
                            markDirty()
                        end
                        goto continue
                    end
                end
                
                if isButtonClicked({x=59, y=24, xs=7, ys=1}, x, y) and feedbacksPage > 1 then
                    feedbacksPage = feedbacksPage - 1
                    markDirty()
                    goto continue
                end
                if isButtonClicked({x=69, y=24, xs=7, ys=1}, x, y) and feedbacksPage < feedbacksTotalPages then
                    feedbacksPage = feedbacksPage + 1
                    markDirty()
                    goto continue
                end
            end

            if currentScreen == "feedback_input" then
                if isButtonClicked({x=20, y=24, xs=12, ys=1}, x, y) then
                    feedbackEditMode = false
                    feedbackInput = ""
                    feedbackRating = 5
                    currentScreen = "feedbacks"
                    markDirty()
                    goto continue
                end
                
                if isButtonClicked({x=46, y=24, xs=15, ys=1}, x, y) and feedbackInput and feedbackInput ~= "" then
                    local feedbackData = {
                        name = currentPlayer or "Аноним",
                        text = feedbackInput,
                        time = getRealTimeString(),
                        rating = feedbackRating or 5
                    }
                    
                    sendToWeb("/api/new_feedback", toJson(feedbackData))
                    table.insert(cache_feedbacks, 1, feedbackData)
                    
                    playerHasFeedback = true
                    if currentPlayer and cache_players[currentPlayer] then
                        cache_players[currentPlayer].hasFeedback = true
                    end
                    
                    showTempMessage("✅ Отзыв отправлен! Спасибо!", 10)
                    feedbackEditMode = false
                    feedbackInput = ""
                    feedbackRating = 5
                    currentScreen = "feedbacks"
                    markDirty()
                    goto continue
                end
            end

            if currentScreen == "agreement" then
                local backButton = {
                    text = "[ НАЗАД ]",
                    x = 37, y = 24,
                    xs = unicode.len("[ НАЗАД ]") + 2,
                    ys = 1,
                    bg = COLORS.BG_BUTTON,
                    fg = COLORS.ACCENT_SECONDARY
                }
                if isButtonClicked(backButton, x, y) then
                    goBackToMenu()
                    goto continue
                end
                local btnText = "[ ПОНЯТНО ]"
                local btnW = unicode.len(btnText) + 4
                local btnX = math.floor((80 - btnW)/2) + 2
                if y == 22 and x >= btnX and x <= btnX + btnW then
                    playerAgreed = true
                    if cache_players[currentPlayer] then
                        cache_players[currentPlayer].agreed = true
                    end
                    showTempMessage("✅ Спасибо! Теперь вам доступен магазин.", 2)
                    goBackToMenu()
                    goto continue
                end
            end

            if currentScreen == "account" or currentScreen == "account_loading" then
                local backButton = {
                    text = "[ НАЗАД ]",
                    x = 50, y = 24,
                    xs = unicode.len("[ НАЗАД ]") + 2,
                    ys = 1,
                    bg = COLORS.BG_BUTTON,
                    fg = COLORS.ACCENT_SECONDARY
                }
                if isButtonClicked(backButton, x, y) then
                    goBackToMenu()
                    goto continue
                end

                local authBtn = {
                    text = "[ АУТЕНТИФИКАЦИЯ ]",
                    x = 20, y = 24,
                    xs = unicode.len("[ АУТЕНТИФИКАЦИЯ ]") + 2,
                    ys = 1,
                    bg = COLORS.BG_BUTTON,
                    fg = COLORS.ACCENT_SECONDARY
                }
                if isButtonClicked(authBtn, x, y) then
                    showAuthPopup()
                    goto continue
                end
            end
        end
 
        if e == "scroll" and (currentScreen == "shop_buy" or currentScreen == "shop_sell") then
            local playerName = ev[6] or "Неизвестный"
            if not isPimOwner(playerName) then
                goto continue
            end

            if currentPlayer and playerName ~= currentPlayer then
                writeDebugLog("⚠️ Игрок сменился (scroll)! Было: " .. currentPlayer .. ", стало: " .. playerName)
                if currentPlayer then
                    safeExit()
                end
                goto continue
            end
            local direction = ev[5] or 0
            local x = ev[3] or 0
            local y = ev[4] or 0
            if x >= 2 and x <= 78 and y >= 7 and y <= 21 then
                if direction == -1 then
                    smoothScroll(1)
                elseif direction == 1 then
                    smoothScroll(-1)
                end
            end
            goto continue
        end

        if e == "mouse_move" and (currentScreen == "shop_buy" or currentScreen == "shop_sell") then
            if not pimOwner then
                goto continue
            end

            local pimPlayer = getPlayerOnPim()
            if not pimPlayer or pimPlayer == "" then
                goto continue
            end

            if currentPlayer and pimPlayer ~= currentPlayer then
                writeDebugLog("⚠️ Игрок сменился (mouse)! Было: " .. currentPlayer .. ", стало: " .. pimPlayer)
                if currentPlayer then
                    safeExit()
                end
                goto continue
            end
            
            local x, y = ev[3], ev[4]
            
            pendingMouseX = x
            pendingMouseY = y
            
            if mouseDebounceTimer then
                event.cancel(mouseDebounceTimer)
                mouseDebounceTimer = nil
            end
            
            mouseDebounceTimer = event.timer(0.05, function()
                mouseDebounceTimer = nil
                processMouseMove(pendingMouseX, pendingMouseY)
                return false
            end)
            
            goto continue
        end

        if e == "key_down" then
            local playerName = ev[5] or "Неизвестный"
            local keyCode = ev[3] or 0
            
            if keyCode == 18 or keyCode == 17 or keyCode == 16 or keyCode == 91 or keyCode == 93 then
                goto continue
            end
            
            if not isPimOwner(playerName) then
                goto continue
            end

            if currentPlayer and playerName ~= currentPlayer then
                writeDebugLog("⚠️ Игрок сменился (key)! Было: " .. currentPlayer .. ", стало: " .. playerName)
                if currentPlayer then
                    safeExit()
                end
                goto continue
            end
            
            if currentScreen == "report" and canSendReport() then
                local ch = ev[3]
                if ch == 13 then
                    markDirty()
                elseif ch == 8 then
                    reportInput = unicode.sub(reportInput or "", 1, -2)
                    markDirty()
                elseif ch >= 32 then
                    reportInput = (reportInput or "") .. unicode.char(ch)
                    markDirty()
                end
            elseif (currentScreen == "shop_buy" or currentScreen == "shop_sell") and searchActive then
                local ch = ev[3]
                if ch == 13 then
                    shopSearch = searchInput or ""
                    searchActive = false
                    listScroll = 1
                    selectedIndex = 0
                    selectedItem = nil
                    hoveredIndex = 0
                    markDirty()
                elseif ch == 8 then
                    searchInput = unicode.sub(searchInput or "", 1, -2)
                    shopSearch = searchInput or ""
                    filteredItems = getFilteredItems()
                    drawBuyItemsList()
                    redrawSearchField()
                    
                    if shopSearch == "" then
                        if selectedItem ~= nil then
                            selectedItem = nil
                            selectedIndex = 0
                            drawBuyButtons()
                        end
                    end
                elseif ch >= 32 then
                    searchInput = (searchInput or "") .. unicode.char(ch)
                    shopSearch = searchInput or ""
                    filteredItems = getFilteredItems()
                    drawBuyItemsList()
                    redrawSearchField()
                    
                    if selectedItem ~= nil then
                        local stillVisible = false
                        for _, item in ipairs(filteredItems) do
                            if item == selectedItem then
                                stillVisible = true
                                break
                            end
                        end
                        if not stillVisible then
                            selectedItem = nil
                            selectedIndex = 0
                            drawBuyButtons()
                        end
                    end
                end
                goto continue
            elseif currentScreen == "feedback_input" and feedbackEditMode then
                local ch = ev[3]
                if ch == 13 then
                    if feedbackInput and feedbackInput ~= "" then
                        local feedbackData = {
                            name = currentPlayer or "Аноним",
                            text = feedbackInput,
                            time = getRealTimeString(),
                            rating = feedbackRating or 5
                        }
                        
                        sendToWeb("/api/new_feedback", toJson(feedbackData))
                        table.insert(cache_feedbacks, 1, feedbackData)
                        
                        playerHasFeedback = true
                        if currentPlayer and cache_players[currentPlayer] then
                            cache_players[currentPlayer].hasFeedback = true
                        end
                        
                        showTempMessage("✅ Отзыв отправлен! Спасибо!", 10)
                    end
                    feedbackEditMode = false
                    feedbackInput = ""
                    feedbackRating = 5
                    currentScreen = "feedbacks"
                    markDirty()
                elseif ch == 8 then
                    feedbackInput = unicode.sub(feedbackInput or "", 1, -2)
                    markDirty()
                elseif ch >= 49 and ch <= 53 then
                    feedbackRating = ch - 48
                    markDirty()
                elseif ch >= 32 then
                    if unicode.len(feedbackInput or "") < 200 then
                        feedbackInput = (feedbackInput or "") .. unicode.char(ch)
                        markDirty()
                    end
                end
                goto continue
            end
            goto continue
        end

        if e == "player_on" or e == "pim" or e == "pim_player_enter" then
            local playerName = ev[2] or "Игрок"
            
            if not playerName or playerName == "" or playerName == "Игрок" then
                goto continue
            end
            
            if currentPlayer and currentPlayer ~= "" and currentPlayer ~= playerName then
                writeDebugLog("⚠️ Пришёл новый игрок, сбрасываем старого: " .. currentPlayer .. " -> " .. playerName)
                
                isShuttingDown = true
                currentPlayer = nil
                currentToken = nil
                alreadyAuthorized = false
                pimOwner = nil
                currentScreen = "welcome"
                authCodeInput = ""
                boundPlayer = nil
                
                if TRANSACTION_LOCK then
                    TRANSACTION_LOCK = false
                end
                
                selectedItem = nil
                hoveredIndex = 0
                selectedIndex = 0
                filteredItems = {}
                shopSearch = ""
                searchActive = false
                searchInput = ""
                purchaseItem = nil
                purchaseQuantity = 1
                sellConfirmItem = nil
                foundAmount = 0
                showSellPopup = false
                showPartialPopup = false
                showInsufficientPopup = false
                showInventoryFullPopup = false
                listScroll = 1
                horizontalScroll = 1
                tempMessage = ""
                
                if tempMessageTimer then
                    event.cancel(tempMessageTimer)
                    tempMessageTimer = nil
                end
                
                pcall(updateSelectorDisplay, nil)
                pcall(selector.setSlot, 0, nil)
                pcall(selector.setSlot, 1, nil)
                
                clearAllTimers()
                drawWelcomeScreen()
                isShuttingDown = false
                
                pimOwner = playerName
            end
            
            if shopPaused then
                drawWelcomeScreen()
                while shopPaused do
                    local ev2 = {event.pull(1)}
                    if ev2[1] == "player_off" or ev2[1] == "pim_player_leave" then
                        drawWelcomeScreen()
                        break
                    end
                end
                goto continue
            end
                                    
            if not pimOwner then
                pimOwner = playerName
            end
            currentPlayer = playerName:match("^%s*(.-)%s*$") or playerName
            
            if not currentPlayer or currentPlayer == "" then
                currentPlayer = playerName
            end
            
            local banInfo = nil
            local success, response = pcall(function()
                return internet.request(WEB_URL .. "/api/check_ban?name=" .. currentPlayer)
            end)
            if success and response then
                local body = ""
                for chunk in response do
                    body = body .. chunk
                end
                local data = parseJSON(body)
                if data and data.banned then
                    banInfo = data
                end
            end
                
            if banInfo then
                local reason = "Не указана"
                if banInfo.reason_b64 then
                    reason = decodeBase64(banInfo.reason_b64)
                elseif banInfo.reason then
                    reason = banInfo.reason
                end
                reason = cleanString(reason)
                
                local admin = cleanString(banInfo.admin or "Система")
                
                local function formatDate(isoDate)
                    if not isoDate or isoDate == "" then return "" end
                    local year, month, day = isoDate:match("(%d+)-(%d+)-(%d+)")
                    if year and month and day then
                        return day .. "." .. month .. "." .. year
                    end
                    return isoDate
                end
                
                local formattedDate = banInfo.date and formatDate(banInfo.date) or ""
                local formattedExpire = banInfo.expires and formatDate(banInfo.expires) or ""
                local isPermanent = not banInfo.expires or banInfo.expires == ""
                
                gpu.setBackground(COLORS.BG_MAIN)
                gpu.fill(1, 1, 80, 25, " ")
                
                gpu.setForeground(COLORS.ERROR)
                drawCenteredText(6, "╔══════════════════════════════════════════════════════════════╗", COLORS.ERROR)
                drawCenteredText(7, "║                       ВЫ ЗАБЛОКИРОВАНЫ                       ║", COLORS.ERROR)
                drawCenteredText(8, "╚══════════════════════════════════════════════════════════════╝", COLORS.ERROR)
                
                drawCenteredText(10, "Причина: " .. reason, COLORS.TEXT_MAIN)
                drawCenteredText(11, "Администратор: " .. admin, COLORS.TEXT_MAIN)
                
                if formattedDate ~= "" then
                    drawCenteredText(12, "Дата: " .. formattedDate, COLORS.TEXT_MAIN)
                end
                
                if isPermanent then
                    drawCenteredText(13, "Бессрочный бан", COLORS.TEXT_MAIN)
                else
                    drawCenteredText(13, "Срок истекает: " .. formattedExpire, COLORS.TEXT_MAIN)
                end
                
                drawCenteredText(15, " Доступ запрещён", COLORS.ERROR)
                
                gpu.setForeground(COLORS.ACCENT_SECONDARY)
                drawCenteredText(22, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", COLORS.ACCENT_SECONDARY)
                
                drawTempMessage()
                
                while true do
                    local ev2 = {event.pull(1)}
                    if ev2[1] == "player_off" or ev2[1] == "pim_player_leave" then
                        drawWelcomeScreen()
                        break
                    end
                end
                currentPlayer = nil
                pimOwner = nil
                alreadyAuthorized = false
                currentScreen = "welcome"
                markDirty()
                goto continue
            end
            
            if alreadyAuthorized then
                local player = cache_players[currentPlayer]
                if player then
                    playerHasFeedback = player.hasFeedback or false
                end
                
                if currentScreen == "auth" or currentScreen == "account_loading" then
                    currentScreen = "menu"
                    markDirty()
                end
                forceSyncBinding()
                markDirty()
            else
                coinBalance = 0.0
                emaBalance = 0.0
                playerAgreed = false
                currentScreen = "auth"
                authStartTime = os.clock()
                
                local player = cache_players[currentPlayer]
                if not player then
                    player = {
                        name = currentPlayer,
                        balance = 0,
                        emaBalance = 0,
                        transactions = 0,
                        banned = false,
                        agreed = false,
                        hasFeedback = false,
                        regDate = getRealTimeString(),
                        site_user = nil
                    }
                    cache_players[currentPlayer] = player
                    addPlayerLog("Новый игрок: " .. currentPlayer, "NEW")
                end
                
                if player.banned then
                    drawCenteredText(20, "Вы забанены!", COLORS.ERROR)
                    os.sleep(2)
                    currentPlayer = nil
                    currentScreen = "welcome"
                    markDirty()
                else
                    currentToken = tostring(math.floor(math.random() * 900000000 + 100000000))
                    coinBalance = player.balance or 0
                    emaBalance = player.emaBalance or 0
                    playerTransactions = player.transactions or 0
                    playerAgreed = player.agreed or false
                    playerRegDate = player.regDate or getRealTimeString()
                    alreadyAuthorized = true
                    
                    if selector then
                    end
                    
                    currentScreen = "menu"
                    markDirty()
                    forceSyncBinding()
                    addPlayerLog("Вход: " .. currentPlayer, "ENTER")
                end
            end
            goto continue
        end

        if e == "player_off" or e == "pim_player_leave" then
            local playerName = ev[2] or "Игрок"
            writeDebugLog("player_off: " .. playerName)
            
            if currentPlayer and playerName == currentPlayer then
                local currentOnPim = getPlayerOnPim()
                writeDebugLog("🔍 На PIM сейчас: " .. tostring(currentOnPim))
                
                if currentOnPim and currentOnPim == currentPlayer then
                    writeDebugLog("⚠️ PIM говорит, что игрок всё ещё стоит, игнорируем player_off")
                    goto continue
                end
            end
            
            if playerName == pimOwner then
                pimOwner = nil
                
                if TRANSACTION_LOCK then
                    writeDebugLog("⚠️ Игрок ушёл ВО ВРЕМЯ транзакции! Ожидаем завершения...")
                    local waitCount = 0
                    while TRANSACTION_LOCK and waitCount < 30 do
                        os.sleep(0.1)
                        waitCount = waitCount + 1
                    end
                    if TRANSACTION_LOCK then
                        writeDebugLog("⚠️ Транзакция зависла, принудительный сброс")
                        TRANSACTION_LOCK = false
                    end
                end
            end
            
            if currentPlayer and playerName == currentPlayer then
                safeExit()
            else
                if playerName == pimOwner then
                    safeExit()
                end
            end
            
            goto continue
        end
       ::continue::
    end
end

-- ★★★ ЗАПУСК С ЗАЩИТОЙ ★★★
local running = true
while running do
    local ok, err = pcall(main)
    if not ok then
        local msg = "💥 ГЛОБАЛЬНАЯ ОШИБКА: " .. tostring(err)
        print(msg)
        writeErrorLog(msg)
        local stack = debug.traceback()
        writeErrorLog("Стек вызовов:\n" .. stack)
        print(stack)
        
        if err and type(err) == "string" and err:find("shutdown") then
            running = false
            break
        end
        
        os.sleep(5)
    end
end

forceSaveData()
addErrorLog("🔴 Терминал #1 завершил работу", "INFO")
