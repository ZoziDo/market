-- ============================================================================
-- Reactor Control v1.1 – точная копия интерфейса (без брайль-символов)
-- Использует только стандартную псевдографику + term
-- Для OpenComputers (любая версия)
-- ============================================================================

local term = require("term")
local event = require("event")
local computer = require("computer")
local unicode = require("unicode")

-- Устанавливаем размер терминала 160x50 (если поддерживается)
term.clear()
term.setViewport(160, 50)
term.setCursor(1, 1)

-- Вспомогательная функция для рисования рамки
local function drawBox(x1, y1, x2, y2, color, fill)
    color = color or 0xffffff
    term.setForeground(color)
    -- верхняя и нижняя границы
    term.setCursor(x1, y1)
    term.write("┌" .. string.rep("─", x2 - x1 - 1) .. "┐")
    for y = y1+1, y2-1 do
        term.setCursor(x1, y)
        term.write("│" .. string.rep(fill and " " or " ", x2 - x1 - 1) .. "│")
    end
    term.setCursor(x1, y2)
    term.write("└" .. string.rep("─", x2 - x1 - 1) .. "┘")
end

local function drawText(x, y, text, color)
    term.setForeground(color or 0xcccccc)
    term.setCursor(x, y)
    term.write(text)
end

-- Очистка экрана и фон
term.clear()
term.setBackground(0x000000)
drawBox(1, 1, 160, 50, 0x202020, true)

-- =========================== ЛЕВАЯ ВЕРХНЯЯ ПАНЕЛЬ ===========================
drawText(3, 2, "---Reactor Control v1.1---", 0xcccccc)
drawText(3, 3, "Автор приложения: P1KaCh0337", 0xcccccc)
drawText(3, 4, "Версия приложения: 1.1, Build 3", 0xcccccc)
drawText(3, 5, "Авто-обновление: Включено", 0xcccccc)
drawText(3, 6, "Реакторов найдено: 0", 0xcccccc)
drawText(3, 7, "МЭ-сеть: Не подключена", 0xcccccc)
drawText(3, 8, "Flux-сеть: Не подключена", 0xcccccc)
drawText(3, 9, "ChatBox: Не подключен", 0xcccccc)
drawText(3, 11, "Инициализация реакторов...", 0xcccccc)
drawText(3, 12, "Реакторы не найдены!", 0xff6666)
drawText(3, 13, "Проверьте подключение реакторов!", 0xffaa66)

-- =========================== БЛОК "РЕАКТОРЫ" ===========================
drawBox(5, 15, 118, 51, 0x969696, true)   -- внешняя рамка
-- Внутреннее сообщение "У вас не подключено ни одного реактора!"
drawBox(36, 29, 87, 32, 0x101010, true)
drawText(43, 30, "У вас не подключено ни одного реактора!", 0xcccccc)
drawText(40, 30, "⚠", 0xffd900)

-- =========================== ПРАВАЯ ПАНЕЛЬ ===========================
-- Рамка "Информационное окно отладки"
drawBox(123, 1, 158, 49, 0x202020, true)
drawText(124, 2, "Информационное окно отладки:", 0xcccccc)
drawText(124, 5, "Спасибо за поддержку:", 0xcccccc)
-- Бегущая строка (обновится позже)
drawText(124, 6, "а реакторы для тестов, Fiellyns - спасибо за поддержку!                                     ", 0xF15F2C)

-- =========================== БЛОК "Жидкости в МЭ сети" ===========================
drawBox(123, 29, 157, 33, 0x101010, true)
drawText(124, 30, "Жидкости в МЭ сети:", 0xcccccc)
drawText(143, 32, "50000 Mb", 0xcccccc)   -- цифра по центру

-- =========================== БЛОК "Настройка порога жидкости" ===========================
drawBox(123, 34, 157, 38, 0x101010, true)
drawText(124, 35, "Настройка порога жидкости:", 0xcccccc)
drawText(144, 37, "50000 Mb", 0xcccccc)
drawText(124, 37, "+", 0xa6ff00)
drawText(126, 37, "-", 0xff2121)

-- =========================== БЛОК "Генерация всех реакторов" ===========================
drawBox(123, 39, 157, 43, 0x101010, true)
drawText(124, 40, "Генерация всех реакторов:", 0xcccccc)
drawText(144, 42, "0 Rf/t", 0xcccccc)

-- =========================== БЛОК "Статус комплекса" ===========================
drawBox(89, 44, 119, 49, 0x101010, true)
drawText(90, 45, "Статус комплекса:", 0xcccccc)
drawText(90, 47, "Кол-во реакторов: 0", 0xcccccc)
drawText(90, 48, "Общее потребление", 0xcccccc)
drawText(90, 49, "жидкости: 0 Mb/s", 0xcccccc)
-- Индикатор Stop (красный)
drawText(112, 47, "[STOP]", 0xfd3232)

-- =========================== НИЖНИЕ КНОПКИ ===========================
-- Кнопка 🔧
drawBox(5, 44, 9, 46, 0xa91df9, true)
drawText(6, 45, "🔧", 0xffffff)
-- Кнопка ⓘ
drawBox(5, 47, 9, 49, 0xa91df9, true)
drawText(6, 48, "ⓘ", 0x05e2ff)

-- Кнопка "Отключить реакторы!"
drawBox(13, 44, 36, 46, 0xfd3232, true)
drawText(15, 45, "Отключить реакторы!", 0xffffff)

-- Кнопка "Запуск реакторов!"
drawBox(41, 44, 63, 46, 0x35e525, true)
drawText(43, 45, "Запуск реакторов!", 0xffffff)

-- Кнопка "Пр.Обновить МЭ"
drawBox(68, 44, 85, 46, 0x38afff, true)
drawText(70, 45, "Пр.Обновить МЭ", 0xffffff)

-- Кнопка "Рестарт программы."
drawBox(13, 47, 36, 49, 0x888888, true)
drawText(15, 48, "Рестарт программы.", 0xffffff)

-- Кнопка "Выход из программы."
drawBox(41, 47, 63, 49, 0x888888, true)
drawText(43, 48, "Выход из программы.", 0xffffff)

-- Кнопка "Метрика: Auto"
drawBox(68, 47, 85, 49, 0x888888, true)
drawText(70, 48, "Метрика: Auto", 0xffffff)

-- Нижний колонтитул
drawText(123, 50, "Reactor Control v1.1.3 by P1KaChU337", 0x666666)

-- =========================== БЛОК ВРЕМЕНИ ===========================
drawBox(123, 45, 157, 49, 0x101010, true)
drawText(124, 46, "МЭ: Обн. ч/з..", 0xcccccc)
drawText(141, 46, "Время работы:", 0xcccccc)
drawText(125, 48, "⏱", 0xaa4b2e)
drawText(134, 48, "60 Sec", 0xcccccc)
drawText(146, 48, "0 Hrs", 0xcccccc)
drawText(154, 48, "0 Min", 0xcccccc)

-- Бегущая строка (имитация обновления)
local scrollPos = 1
local supporterText = "а реакторы для тестов, Fiellyns - спасибо за поддержку!                                     "
local function updateMarquee()
    local visible = supporterText:sub(scrollPos, scrollPos + 33)
    if #visible < 33 then visible = visible .. supporterText:sub(1, 33 - #visible) end
    drawText(124, 6, visible, 0xF15F2C)
    scrollPos = scrollPos + 1
    if scrollPos > #supporterText then scrollPos = 1 end
end

-- Таймер для обновления времени и бегущей строки
local lastTick = computer.uptime()
local seconds = 0
local minutes = 0
local hours = 0

-- Цикл обработки событий и обновления динамических данных
while true do
    local now = computer.uptime()
    if now - lastTick >= 1 then
        lastTick = now
        seconds = seconds + 1
        if seconds >= 60 then
            seconds = 0
            minutes = minutes + 1
            if minutes >= 60 then
                minutes = 0
                hours = hours + 1
            end
            -- обновляем время на экране
            drawText(134, 48, string.format("%02d Sec", seconds), 0xcccccc)
            drawText(146, 48, string.format("%d Hrs", hours), 0xcccccc)
            drawText(154, 48, string.format("%d Min", minutes), 0xcccccc)
        end
        -- обновляем бегущую строку
        updateMarquee()
        -- здесь можно обновлять другие динамические цифры, например таймер МЭ
        drawText(124, 32, "50000 Mb", 0xcccccc) -- пример статично, но можно менять
    end

    local ev = {event.pull(0.05)}
    if ev[1] == "touch" then
        local _, _, x, y = table.unpack(ev)
        -- обработка кнопок (пример: выход)
        if x >= 41 and x <= 63 and y >= 47 and y <= 49 then
            term.clear()
            term.setCursor(1, 1)
            term.setViewport(80, 25)
            return
        end
        -- здесь можно добавить обработку остальных кнопок (анимация нажатия)
        -- для простоты оставим только выход
    end
end
