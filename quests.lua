-- =============================================
-- Reactor Control v1.1 build 3 — Полная версия
-- Работает без картинок
-- =============================================

local computer = require("computer")
local buffer = require("doubleBuffering")
local event = require("event")
local component = require("component")
local fs = require("filesystem")
local unicode = require("unicode")
local shell = require("shell")

buffer.setResolution(160, 50)
buffer.clear(0x000000)

local version = "1.1"
local build = "3"
local exit = false

local porog = 50000
local reactors = 0
local reactor_work = {}
local reactor_aborted = {}
local temperature = {}
local reactor_type = {}
local reactor_rf = {}
local reactor_getcoolant = {}
local reactor_maxcoolant = {}
local fluidInMe = 125000
local status_metric = "Auto"
local metric = 0

local consoleLines = {}
local second, minute, hour = 0, 0, 0
local MeSecond = 0

local widgetCoords = {
    {10,6},{36,6},{65,6},{91,6},
    {10,18},{36,18},{65,18},{91,18},
    {10,30},{36,30},{65,30},{91,30}
}

-- ====================== ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ======================

local function brailleChar(dots)
    return unicode.char(
        10240 +
        (dots[8] or 0) * 128 +
        (dots[7] or 0) * 64 +
        (dots[6] or 0) * 32 +
        (dots[4] or 0) * 16 +
        (dots[2] or 0) * 8 +
        (dots[5] or 0) * 4 +
        (dots[3] or 0) * 2 +
        (dots[1] or 0)
    )
end

local brail_status = {{1,1,1,0,1,0,1,0},{1,0,1,0,1,0,1,0},{1,1,0,0,0,0,0,0},{1,0,0,0,0,0,0,0}}

local function centerText(text, width)
    local len = unicode.len(text)
    local pad = math.floor((width - len)/2)
    return string.rep(" ", pad) .. text
end

local function formatRFwidgets(value)
    if value >= 1000000 then
        return "Ген: " .. math.floor(value/1000000) .. " mRF/t"
    elseif value >= 1000 then
        return "Ген: " .. math.floor(value/1000) .. " kRF/t"
    else
        return "Ген: " .. value .. " RF/t"
    end
end

local function animatedButton(push, x, y, text, length)
    length = length or unicode.len(text) + 2
    local color = push == 1 and 0x00cc44 or 0xff3333
    buffer.drawRectangle(x, y, length, 3, color, 0, " ")
    buffer.drawText(x + 1, y + 1, 0xffffff, centerText(text, length-2))
end

local function drawVerticalProgressBar(x, y, height, value, maxValue)
    if maxValue == 0 then maxValue = 1 end
    local filled = math.floor(height * (value / maxValue))
    for i = 0, height-1 do
        local col = i < (height - filled) and 0x222222 or 0x4488ff
        buffer.drawText(x, y + i, col, "█")
    end
end

-- ====================== ОСНОВНОЙ ИНТЕРФЕЙС ======================

local function drawStatic()
    -- Фон
    buffer.drawRectangle(1, 1, 160, 50, 0x1c1c1c, 0, " ")
    buffer.drawRectangle(2, 2, 158, 48, 0x2a2a2a, 0, " ")

    -- Заголовок
    buffer.drawText(68, 2, 0xffd700, "РЕАКТОРЫ")

    -- Нижняя панель кнопок
    animatedButton(1, 3,  44, "⚙", 4)           -- Настройки
    animatedButton(1, 3,  47, "ⓘ", 4)           -- Инфо

    animatedButton(1, 12, 44, "Отключить реакторы!", 24)
    animatedButton(1, 40, 44, "Запуск реакторов!", 23)
    animatedButton(1, 67, 44, "Пр.Обновить МЭ", 18)

    animatedButton(1, 12, 47, "Рестарт программы.", 24)
    animatedButton(1, 40, 47, "Выход из программы.", 23)
    animatedButton(1, 67, 47, "Метрика: " .. status_metric, 18)

    buffer.drawText(123, 50, 0x666666, "Reactor Control v"..version.."."..build)
end

local function drawWidgets()
    buffer.drawRectangle(5, 5, 114, 37, 0x2a2a2a, 0, " ")

    if reactors == 0 then
        buffer.drawRectangle(35, 22, 52, 3, 0x111111, 0, " ")
        buffer.drawText(38, 23, 0xffaa00, "⚠")
        buffer.drawText(42, 23, 0xffffff, "У вас не подключено ни одного реактора!")
        return
    end

    for i = 1, math.min(reactors, 12) do
        local x, y = widgetCoords[i][1], widgetCoords[i][2]
        
        buffer.drawRectangle(x, y, 24, 13, 0x1f1f1f, 0, " ")
        buffer.drawRectangle(x+1, y+1, 22, 11, 0x2a2a2a, 0, " ")

        buffer.drawText(x, y, 0x555555, brailleChar(brail_status[1]))
        buffer.drawText(x+23, y, 0x555555, brailleChar(brail_status[2]))
        buffer.drawText(x+23, y+12, 0x555555, brailleChar(brail_status[3]))
        buffer.drawText(x, y+12, 0x555555, brailleChar(brail_status[4]))

        local working = reactor_work[i] or false

        buffer.drawText(x+2, y+1, 0xdddddd, "РЕАКТОР #"..i)
        buffer.drawText(x+2, y+2, 0x88ffaa, "Нагрев: "..(temperature[i] or 650).."°C")
        buffer.drawText(x+2, y+3, 0xffcc77, formatRFwidgets(reactor_rf[i] or 12500))
        buffer.drawText(x+2, y+4, 0x77bbff, "Тип: "..(reactor_type[i] or "Fluid"))
        buffer.drawText(x+2, y+5, working and 0x00ff88 or 0xff6666, "Статус: "..(working and "РАБОТАЕТ" or "СТОП"))

        if reactor_type[i] == "Fluid" then
            drawVerticalProgressBar(x+21, y+1, 11, reactor_getcoolant[i] or 8500, 10000)
        end

        animatedButton(working and 0 or 1, x+6, y+8, working and "ОТКЛ" or "ВКЛ", 11)
    end
end

local function drawRightPanel()
    buffer.drawRectangle(123, 3, 35, 47, 0x1a1a1a, 0, " ")
    buffer.drawText(124, 4, 0xaaaaaa, "Информационное окно отладки:")

    buffer.drawText(124, 6, 0x44ffaa, "Спасибо за поддержку:")
    buffer.drawText(124, 7, 0xff5555, "roperTopper - 10$")

    buffer.drawText(124, 10, 0x88ff88, "Жидкости в МЭ сети:")
    buffer.drawText(124, 11, 0x4488ff, "125000 Mb")

    buffer.drawText(124, 13, 0xffffff, "Порог: " .. porog .. " Mb")

    buffer.drawText(124, 16, 0xffdd77, "Генерация: 48.5 kRF/t")

    buffer.drawText(124, 20, 0xaaaaaa, "Статус комплекса:")
    buffer.drawText(124, 21, 0xff4444, "Stop")

    buffer.drawText(124, 23, 0xaaaaaa, "Время работы: 00:12:45")
end

local function drawAll()
    drawStatic()
    drawWidgets()
    drawRightPanel()
    buffer.drawChanges()
end

-- ====================== ОБРАБОТКА КЛИКОВ ======================

local function handleTouch(x, y)
    if y >= 44 and y <= 49 then
        if x >= 12 and x <= 36 then
            buffer.drawText(15, 45, 0xffffff, "Отключаем...")
            buffer.drawChanges()
            os.sleep(0.5)
            drawAll()
        elseif x >= 40 and x <= 63 then
            buffer.drawText(43, 45, 0xffffff, "Запускаем...")
            buffer.drawChanges()
            os.sleep(0.5)
            drawAll()
        elseif x >= 3 and x <= 7 and y >= 44 and y <= 46 then
            buffer.drawText(5, 45, 0xffffff, "Настройки")
            buffer.drawChanges()
            os.sleep(0.3)
            drawAll()
        end
    end
end

-- ====================== ГЛАВНЫЙ ЦИКЛ ======================

local function main()
    -- Симуляция реакторов
    reactors = 4
    for i = 1, reactors do
        reactor_work[i] = i % 2 == 1
        reactor_type[i] = "Fluid"
        temperature[i] = 650 + i*50
        reactor_rf[i] = 12000 + i*3000
        reactor_getcoolant[i] = 8000 - i*1000
        reactor_maxcoolant[i] = 10000
    end

    drawAll()

    while not exit do
        local e = {event.pull(0.5)}
        if e[1] == "touch" then
            handleTouch(e[3], e[4])
        end
        second = second + 1
        if second % 10 == 0 then
            drawAll()
        end
    end
end

main()
