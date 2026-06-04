-- Reactor Control v1.1 build 3 — Максимально близко к оригиналу
local computer = require("computer")
local buffer = require("doubleBuffering")
local event = require("event")
local unicode = require("unicode")
local shell = require("shell")

buffer.setResolution(160, 50)
buffer.clear(0x000000)

local version = "1.1"
local build = "3"

local porog = 50000
local reactors = 4
local reactor_work = {true, false, true, false}
local temperature = {700, 750, 800, 850}
local reactor_rf = {15000, 18000, 21000, 24000}
local reactor_type = {"Fluid", "Fluid", "Fluid", "Fluid"}
local fluidInMe = 125000

local widgetCoords = {
    {8, 6}, {37, 6}, {66, 6}, {95, 6},
    {8, 20}, {37, 20}, {66, 20}, {95, 20}
}

-- ====================== ВСПОМОГАТЕЛЬНЫЕ ======================
local function brailleChar(dots)
    return unicode.char(10240 + (dots[8] or 0)*128 + (dots[7] or 0)*64 + (dots[6] or 0)*32 + (dots[4] or 0)*16 + (dots[2] or 0)*8 + (dots[5] or 0)*4 + (dots[3] or 0)*2 + (dots[1] or 0))
end

local brail_status = {
    {1,1,1,0,1,0,1,0},
    {1,0,1,0,1,0,1,0},
    {1,1,0,0,0,0,0,0},
    {1,0,0,0,0,0,0,0}
}

-- ====================== ОСНОВНОЙ ИНТЕРФЕЙС ======================
local function drawStatic()
    -- Основной фон
    buffer.drawRectangle(1, 1, 160, 50, 0x1c1c1c, 0, " ")
    buffer.drawRectangle(3, 3, 120, 40, 0x2a2a2a, 0, " ")   -- область реакторов

    -- Заголовок
    buffer.drawText(68, 2, 0xffd700, "РЕАКТОРЫ")

    -- Нижние кнопки
    buffer.drawRectangle(4, 44, 6, 6, 0x8a2be2, 0, " ")     -- Фиолетовые кнопки
    buffer.drawText(5, 45, 0xffffff, "⚙")
    buffer.drawText(5, 48, 0xffffff, "ⓘ")

    buffer.drawRectangle(13, 44, 26, 3, 0xff3333, 0, " ")   -- Красная
    buffer.drawText(15, 45, 0xffffff, "Отключить реакторы!")

    buffer.drawRectangle(42, 44, 26, 3, 0x00cc44, 0, " ")   -- Зелёная
    buffer.drawText(44, 45, 0xffffff, "Запуск реакторов!")

    buffer.drawRectangle(71, 44, 20, 3, 0x3399ff, 0, " ")   -- Синяя
    buffer.drawText(73, 45, 0xffffff, "Пр.Обновить МЭ")

    buffer.drawRectangle(13, 48, 26, 3, 0x3399ff, 0, " ")
    buffer.drawText(15, 49, 0xffffff, "Рестарт программы.")

    buffer.drawRectangle(42, 48, 26, 3, 0x3399ff, 0, " ")
    buffer.drawText(44, 49, 0xffffff, "Выход из программы.")

    buffer.drawRectangle(71, 48, 20, 3, 0x3399ff, 0, " ")
    buffer.drawText(73, 49, 0xffffff, "Метрика: Auto")

    buffer.drawText(125, 50, 0x555555, "Reactor Control v"..version.."."..build)
end

local function drawWidgets()
    for i = 1, reactors do
        local x = widgetCoords[i][1]
        local y = widgetCoords[i][2]
        local working = reactor_work[i]

        -- Фон виджета
        buffer.drawRectangle(x, y, 27, 13, 0x111111, 0, " ")
        buffer.drawRectangle(x+1, y+1, 25, 11, 0x1f1f1f, 0, " ")

        -- Рамка
        buffer.drawText(x, y, 0x444444, brailleChar(brail_status[1]))
        buffer.drawText(x+26, y, 0x444444, brailleChar(brail_status[2]))
        buffer.drawText(x+26, y+12, 0x444444, brailleChar(brail_status[3]))
        buffer.drawText(x, y+12, 0x444444, brailleChar(brail_status[4]))

        -- Информация
        buffer.drawText(x+2, y+1, 0xdddddd, "РЕАКТОР #"..i)
        buffer.drawText(x+2, y+2, 0x88ffaa, "Нагрев: "..temperature[i].."°C")
        buffer.drawText(x+2, y+3, 0xffcc77, "Ген: "..(reactor_rf[i]/1000).." kRF/t")
        buffer.drawText(x+2, y+4, 0x77bbff, "Тип: "..reactor_type[i])
        buffer.drawText(x+2, y+5, working and 0x00ff88 or 0xff6666, "Статус: "..(working and "РАБОТАЕТ" or "СТОП"))

        -- Кнопка
        local btnColor = working and 0xff3333 or 0x00cc44
        buffer.drawRectangle(x+7, y+8, 13, 3, btnColor, 0, " ")
        buffer.drawText(x+9, y+9, 0xffffff, working and "ОТКЛ" or "ВКЛ")

        -- Прогресс-бар жидкости
        if reactor_type[i] == "Fluid" then
            buffer.drawRectangle(x+24, y+1, 2, 11, 0x222222, 0, " ")
            for j = 0, 8 do
                buffer.drawText(x+24, y+10-j, 0x4488ff, "█")
            end
        end
    end
end

local function drawRightPanel()
    buffer.drawRectangle(123, 3, 35, 47, 0x0f0f0f, 0, " ")

    buffer.drawText(124, 4, 0xaaaaaa, "Информационное окно отладки:")

    buffer.drawText(124, 6, 0x44ffaa, "Спасибо за поддержку:")
    buffer.drawText(124, 7, 0xff5555, "roperTopper - 10$")

    buffer.drawText(124, 10, 0x88ff88, "Жидкости в МЭ сети:")
    buffer.drawText(124, 11, 0x4488ff, fluidInMe .. " Mb")

    buffer.drawText(124, 13, 0xffffff, "Порог: " .. porog .. " Mb")

    buffer.drawText(124, 16, 0xffdd77, "Генерация: 48.5 kRF/t")

    buffer.drawText(124, 19, 0xff6666, "Статус комплекса:")
    buffer.drawText(124, 20, 0xff3333, "Stop")

    buffer.drawText(124, 22, 0xaaaaaa, "Время работы: 00:12:45")
end

local function drawAll()
    drawStatic()
    drawWidgets()
    drawRightPanel()
    buffer.drawChanges()
end

-- ====================== ЗАПУСК ======================
drawAll()

while true do
    local e = {event.pull(0.3)}
    if e[1] == "touch" then
        drawAll()
    end
end
