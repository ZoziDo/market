local term = require("term")
local event = require("event")
local computer = require("computer")

term.clear()
term.setCursor(1,1)

-- Функция рисования рамки
local function box(x1,y1,x2,y2)
    -- верх
    term.setCursor(x1, y1)
    term.write("+" .. string.rep("-", x2-x1-1) .. "+")
    -- боковые
    for y = y1+1, y2-1 do
        term.setCursor(x1, y)
        term.write("|")
        term.setCursor(x2, y)
        term.write("|")
    end
    -- низ
    term.setCursor(x1, y2)
    term.write("+" .. string.rep("-", x2-x1-1) .. "+")
end

local function txt(x,y,str)
    term.setCursor(x,y)
    term.write(str)
end

-- ========== ЛЕВАЯ ПАНЕЛЬ ==========
txt(3,2, "---Reactor Control v1.1---")
txt(3,3, "Автор приложения: P1KaCh0337")
txt(3,4, "Версия приложения: 1.1, Build 3")
txt(3,5, "Авто-обновление: Включено")
txt(3,6, "Реакторов найдено: 0")
txt(3,7, "МЭ-сеть: Не подключена")
txt(3,8, "Flux-сеть: Не подключена")
txt(3,9, "ChatBox: Не подключен")
txt(3,11,"Инициализация реакторов...")
txt(3,12,"Реакторы не найдены!")
txt(3,13,"Проверьте подключение реакторов!")

-- ========== БЛОК "РЕАКТОРЫ" ==========
box(5,15, 118,51)
box(36,29, 87,32)
txt(43,30, "У вас не подключено ни одного реактора!")
txt(40,30, "!")

-- ========== ПРАВАЯ ПАНЕЛЬ ==========
box(123,1, 158,49)
txt(124,2, "Информационное окно отладки:")
txt(124,5, "Спасибо за поддержку:")
txt(124,6, "а реакторы для тестов, Fiellyns - спасибо за поддержку!                                     ")

-- ========== ЖИДКОСТИ ==========
box(123,29, 157,33)
txt(124,30, "Жидкости в МЭ сети:")
txt(143,32, "50000 Mb")

-- ========== ПОРОГ ==========
box(123,34, 157,38)
txt(124,35, "Настройка порога жидкости:")
txt(144,37, "50000 Mb")
txt(124,37, "+")
txt(126,37, "-")

-- ========== ГЕНЕРАЦИЯ ==========
box(123,39, 157,43)
txt(124,40, "Генерация всех реакторов:")
txt(144,42, "0 Rf/t")

-- ========== СТАТУС ==========
box(89,44, 119,49)
txt(90,45, "Статус комплекса:")
txt(90,47, "Кол-во реакторов: 0")
txt(90,48, "Общее потребление")
txt(90,49, "жидкости: 0 Mb/s")
txt(112,47, "[STOP]")

-- ========== КНОПКИ ==========
box(5,44,9,46)
txt(6,45, "[ ]")
box(5,47,9,49)
txt(6,48, "( )")

box(13,44,36,46)
txt(15,45, "Отключить реакторы!")
box(41,44,63,46)
txt(43,45, "Запуск реакторов!")
box(68,44,85,46)
txt(70,45, "Пр.Обновить МЭ")

box(13,47,36,49)
txt(15,48, "Рестарт программы.")
box(41,47,63,49)
txt(43,48, "Выход из программы.")
box(68,47,85,49)
txt(70,48, "Метрика: Auto")

-- ========== ФУТЕР ==========
txt(123,50, "Reactor Control v1.1.3 by P1KaChU337")

-- ========== ВРЕМЯ ==========
box(123,45,157,49)
txt(124,46, "МЭ: Обн. ч/з..")
txt(141,46, "Время работы:")
txt(125,48, "*")
txt(134,48, "60 Sec")
txt(146,48, "0 Hrs")
txt(154,48, "0 Min")

-- Бегущая строка
local scroll = 1
local msg = "а реакторы для тестов, Fiellyns - спасибо за поддержку!                                     "
local last = computer.uptime()
local sec = 0
local min = 0
local hr = 0

while true do
    local now = computer.uptime()
    if now - last >= 1 then
        last = now
        sec = sec + 1
        if sec >= 60 then
            sec = 0
            min = min + 1
            if min >= 60 then
                min = 0
                hr = hr + 1
            end
            txt(134,48, string.format("%02d Sec", sec))
            txt(146,48, string.format("%d Hrs", hr))
            txt(154,48, string.format("%d Min", min))
        end
        -- бегущая строка
        local vis = msg:sub(scroll, scroll+33)
        if #vis < 33 then vis = vis .. msg:sub(1,33-#vis) end
        txt(124,6, vis)
        scroll = scroll + 1
        if scroll > #msg then scroll = 1 end
    end

    local ev = {event.pull(0.05)}
    if ev[1] == "touch" then
        local _,_,x,y = table.unpack(ev)
        if x>=41 and x<=63 and y>=47 and y<=49 then
            term.clear()
            term.setCursor(1,1)
            return
        end
    end
end
