-- ============================================================================
-- Reactor Control v1.1 (build 3) – ДЕМОНСТРАЦИОННЫЙ ИНТЕРФЕЙС
-- Исправленная версия: добавлены недостающие символы.
-- Для OpenComputers (McSkill HiTech 1.7.10)
-- ============================================================================

local computer = require("computer")
local image = require("image")
local buffer = require("doubleBuffering")
local event = require("event")
local term = require("term")
local unicode = require("unicode")
local bit = require("bit32")

buffer.setResolution(160, 50)
buffer.clear(0x000000)

local version = "1.1"
local build = "3"

local colors = {
    bg      = 0x202020,
    bg2     = 0x101010,
    bg3     = 0x3c3c3c,
    bg4     = 0x969696,
    bg5     = 0xff0000,
    textclr = 0xcccccc,
    textbtn = 0xffffff,
    whitebtn = nil,
    whitebtn2 = 0x38afff,
    msginfo  = 0x61ff52,
    msgwarn  = 0xfff700,
    msgerror = 0xff0000,
}

-- ---------------------- Символы Брайля (дополнено) ---------------------------
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

local braill0 = {{1,1,1,0,1,0,1,0},{1,0,1,0,1,0,1,0},{1,1,0,0,0,0,0,0},{1,0,0,0,0,0,0,0}}
local braill1 = {{0,1,1,1,0,1,0,1},{0,0,0,0,0,0,0,0},{1,1,0,0,0,0,0,0},{1,0,0,0,0,0,0,0}}
local braill2 = {{1,1,0,0,1,1,1,0},{1,0,1,0,1,0,0,0},{1,1,0,0,0,0,0,0},{1,0,0,0,0,0,0,0}}
local braill3 = {{1,1,0,0,1,1,0,0},{1,0,1,0,1,0,1,0},{1,1,0,0,0,0,0,0},{1,0,0,0,0,0,0,0}}
local braill4 = {{1,0,1,0,1,1,0,0},{1,0,1,0,1,0,1,0},{0,0,0,0,0,0,0,0},{1,0,0,0,0,0,0,0}}
local braill5 = {{1,1,1,0,1,1,0,0},{1,0,0,0,1,0,1,0},{1,1,0,0,0,0,0,0},{1,0,0,0,0,0,0,0}}
local braill6 = {{1,1,1,0,1,1,1,0},{1,0,0,0,1,0,1,0},{1,1,0,0,0,0,0,0},{1,0,0,0,0,0,0,0}}
local braill7 = {{1,1,0,0,0,0,0,0},{1,0,1,0,1,0,1,0},{0,0,0,0,0,0,0,0},{1,0,0,0,0,0,0,0}}
local braill8 = {{1,1,1,0,1,1,1,0},{1,0,1,0,1,0,1,0},{1,1,0,0,0,0,0,0},{1,0,0,0,0,0,0,0}}
local braill9 = {{1,1,1,0,1,1,0,0},{1,0,1,0,1,0,1,0},{1,1,0,0,0,0,0,0},{1,0,0,0,0,0,0,0}}
local braill_minus = {{0,0,0,0,1,1,0,0},{0,0,0,0,1,0,0,0},{0,0,0,0,0,0,0,0},{0,0,0,0,0,0,0,0}}
local braill_dot   = {{0,0,0,0,0,0,0,0},{0,0,0,0,0,0,0,0},{1,0,0,0,0,0,0,0},{0,0,0,0,0,0,0,0}}

-- Дополнительные символы, которых не хватало
local brail_greenbtn = {{0,0,0,1,1,1,0,1},{0,0,0,0,1,0,0,0},{0,0,0,0,0,0,0,0},{0,0,0,0,0,0,0,0}}
local brail_redbtn   = {{0,0,0,0,0,1,0,0},{0,0,0,0,1,1,0,0},{0,0,0,0,0,0,0,0},{0,0,0,0,0,0,0,0}}

local brail_console   = {{0,0,0,0,1,1,1,1},{0,0,1,1,0,0,0,0}}
local brail_fluid     = {{0,1,0,1,1,1,1,1},{1,0,1,0,1,1,1,1},{1,1,0,1,0,0,0,0},{1,1,1,0,0,0,0,0}}
local brail_thunderbolt = {{0,0,0,0,0,1,0,0},{0,1,1,0,1,1,0,1},{0,0,0,1,0,0,0,0},{1,0,0,0,0,0,0,0}}
local brail_cherta    = {{1,0,1,0,1,0,1,0},{1,0,1,1,1,0,1,0},{0,0,0,0,1,0,1,0},{1,0,1,0,1,0,1,0},{0,0,1,1,0,1,0,1},{0,1,0,1,0,1,0,1},{0,0,1,1,1,0,1,0}}
local brail_time      = {{1,1,1,0,0,1,1,0},{1,1,0,1,1,0,0,1},{1,0,1,1,0,0,0,0},{0,1,1,1,0,0,0,0}}
local brail_status    = {{0,0,0,1,1,1,1,1},{0,0,1,0,1,1,1,1},{1,1,1,1,1,0,0,0},{1,1,1,1,0,1,0,0}}
local button1         = {{0,0,0,0,1,1,1,1},{0,0,0,0,1,0,1,1},{1,1,1,1,1,1,1,1},{0,0,0,0,0,1,1,1},{1,1,0,1,0,0,0,0},{1,1,1,0,0,0,0,0},{1,1,1,1,0,0,0,0},{1,1,1,1,1,1,1,0},{1,1,1,1,1,1,0,1}}
local button1_push    = {{0,0,0,0,0,0,1,1},{0,0,0,0,0,0,1,0},{1,1,1,1,1,1,1,1},{0,0,0,0,0,0,0,1},{0,1,0,0,0,0,0,0},{1,0,0,0,0,0,0,0},{1,1,0,0,0,0,0,0}} -- добавлено
local brail_verticalbar = {{0,0,0,0,0,0,1,1},{0,0,0,0,1,1,1,1},{0,0,1,1,1,1,1,1},{1,1,1,1,1,1,1,1}}

local braillMap = {
    [0] = braill0, [1] = braill1, [2] = braill2, [3] = braill3,
    [4] = braill4, [5] = braill5, [6] = braill6, [7] = braill7,
    [8] = braill8, [9] = braill9, ["-"] = braill_minus, ["."] = braill_dot,
}

local function drawDigit(x, y, braill, color)
    buffer.drawText(x,     y,     color, brailleChar(braill[1]))
    buffer.drawText(x,     y + 1, color, brailleChar(braill[3]))
    buffer.drawText(x + 1, y,     color, brailleChar(braill[2]))
    buffer.drawText(x + 1, y + 1, color, brailleChar(braill[4]))
end

local function drawNumberWithText(centerX, centerY, number, digitWidth, color, suffix, suffixColor)
    suffixColor = suffixColor or color
    local strNum = tostring(number)
    local digits = {}
    local widths = {}
    for i = 1, #strNum do
        local ch = strNum:sub(i, i)
        local n = tonumber(ch)
        if n then
            table.insert(digits, braillMap[n])
            table.insert(widths, digitWidth)
        elseif braillMap[ch] then
            table.insert(digits, braillMap[ch])
            table.insert(widths, (ch == "." and 1 or digitWidth))
        end
    end
    local suffixWidth = suffix and #suffix or 0
    local totalWidth = 0
    for _, w in ipairs(widths) do totalWidth = totalWidth + w end
    totalWidth = totalWidth + (suffixWidth > 0 and (suffixWidth + 1) or 0)
    local startX = math.floor(centerX - totalWidth / 2)
    buffer.drawText(startX, centerY, colors.bg, string.rep(" ", totalWidth))
    local x = startX
    for i, digit in ipairs(digits) do
        drawDigit(x, centerY, digit, color)
        x = x + widths[i]
    end
    if suffix and suffixWidth > 0 then
        buffer.drawText(x, centerY, suffixColor, suffix)
    end
end

local function animatedButton(push, x, y, text, tx, ty, length, time, clearWidth, color, textcolor)
    local btn = (push == 1) and button1 or button1_push
    local bgColor = color or 0x059bff
    local tColor = textcolor or colors.textbtn
    local ftx = tx or x
    local fty = ty or y + 1
    if push == 1 then
        buffer.drawRectangle(x, y + 1, length, 1, bgColor, 0, " ")
        buffer.drawText(ftx, fty, tColor, (text or "* Клик *"):sub(1, length))
    end
    buffer.drawText(x - 1, y,     bgColor, brailleChar(btn[4]))
    buffer.drawText(x - 1, y + 1, bgColor, brailleChar(btn[3]))
    buffer.drawText(x - 1, y + 2, bgColor, brailleChar(btn[5]))
    buffer.drawText(x + length, y,     bgColor, brailleChar(btn[2]))
    buffer.drawText(x + length, y + 1, bgColor, brailleChar(btn[3]))
    buffer.drawText(x + length, y + 2, bgColor, brailleChar(btn[6]))
    for i = 0, length - 1 do
        buffer.drawText(x + i, y,     bgColor, brailleChar(btn[1]))
        buffer.drawText(x + i, y + 2, bgColor, brailleChar(btn[7]))
    end
    if push == 0 and clearWidth and clearWidth > length then
        buffer.drawRectangle(x, y + 1, length, 1, bgColor, 0, " ")
        buffer.drawText(ftx, fty, tColor, (text or "* Клик *"):sub(1, length))
    end
    if push == 0 then os.sleep(time or 0.3) end
end

local function shortenNameCentered(name, maxLength)
    if unicode.len(name) > maxLength then
        name = unicode.sub(name, 1, maxLength - 3) .. "..."
    end
    local pad = math.floor((maxLength - unicode.len(name)) / 2)
    if pad < 0 then pad = 0 end
    return string.rep(" ", pad) .. name
end

local function centerText(text, totalWidth)
    local pad = math.floor((totalWidth - unicode.len(text)) / 2)
    if pad < 0 then pad = 0 end
    return string.rep(" ", pad) .. text
end

local scrollPos = 1
local maxWidth = 33
local function drawMarquee(x, y, text, color)
    local textLength = unicode.len(text)
    if textLength > maxWidth then
        local visible = unicode.sub(text, scrollPos, scrollPos + maxWidth - 1)
        if unicode.len(visible) < maxWidth then
            visible = visible .. unicode.sub(text, 1, maxWidth - unicode.len(visible))
        end
        buffer.drawText(x, y, color, visible)
        scrollPos = scrollPos + 1
        if scrollPos > textLength then scrollPos = 1 end
    else
        buffer.drawText(x, y, color, text)
    end
    buffer.drawChanges()
end

local function drawStatic()
    buffer.drawRectangle(1, 1, 160, 50, colors.bg, 0, " ")
    buffer.drawText(3, 2, colors.textclr, "---Reactor Control v" .. version .. "---")
    buffer.drawText(3, 3, colors.textclr, "Автор приложения: P1KaCh0337")
    buffer.drawText(3, 4, colors.textclr, "Версия приложения: " .. version .. ", Build " .. build)
    buffer.drawText(3, 5, colors.textclr, "Авто-обновление: Включено")
    buffer.drawText(3, 6, colors.textclr, "Реакторов найдено: 0")
    buffer.drawText(3, 7, colors.textclr, "МЭ-сеть: Не подключена")
    buffer.drawText(3, 8, colors.textclr, "Flux-сеть: Не подключена")
    buffer.drawText(3, 9, colors.textclr, "ChatBox: Не подключен")
    buffer.drawText(3, 11, colors.textclr, "Инициализация реакторов...")
    buffer.drawText(3, 12, colors.textclr, "Реакторы не найдены!")
    buffer.drawText(3, 13, colors.textclr, "Проверьте подключение реакторов!")

    buffer.drawRectangle(5, 15, 114, 37, colors.bg4, 0, " ")
    buffer.drawRectangle(37, 29, 50, 3, colors.bg2, 0, " ")
    buffer.drawRectangle(36, 30, 52, 1, colors.bg2, 0, " ")
    local cornerPos = {{36,29,1},{87,29,2},{87,31,3},{36,31,4}}
    for _, c in ipairs(cornerPos) do
        buffer.drawText(c[1], c[2], colors.bg2, brailleChar(brail_status[c[3]]))
    end
    buffer.drawText(43, 30, 0xcccccc, "У вас не подключено ни одного реактора!")
    buffer.drawText(40, 30, 0xffd900, "⚠")

    buffer.drawRectangle(123, 2, 35, 48, colors.bg, 0, " ")
    for i = 0, 34 do
        buffer.drawText(123 + i, 1, colors.bg, brailleChar(brail_console[1]))
        buffer.drawText(123 + i, 3, colors.bg2, brailleChar(brail_console[2]))
    end
    buffer.drawText(124, 2, colors.textclr, "Информационное окно отладки:")

    buffer.drawText(124, 5, colors.textclr, "Спасибо за поддержку:")

    animatedButton(1, 5, 44, "🔧", nil, nil, 4, nil, nil, 0xa91df9, 0xffffff)
    animatedButton(1, 5, 47, "ⓘ", nil, nil, 4, nil, nil, 0xa91df9, 0x05e2ff)
    animatedButton(1, 13, 44, "Отключить реакторы!", nil, nil, 24, nil, nil, 0xfd3232)
    animatedButton(1, 41, 44, "Запуск реакторов!", nil, nil, 23, nil, nil, 0x35e525)
    animatedButton(1, 68, 44, "Пр.Обновить МЭ", nil, nil, 18, nil, nil, nil)
    animatedButton(1, 13, 47, "Рестарт программы.", nil, nil, 24, nil, nil, colors.whitebtn)
    animatedButton(1, 41, 47, "Выход из программы.", nil, nil, 23, nil, nil, colors.whitebtn)
    animatedButton(1, 68, 47, "Метрика: Auto", nil, nil, 18, nil, nil, colors.whitebtn)

    buffer.drawText(123, 50, 0x666666, "Reactor Control v" .. version .. "." .. build .. " by P1KaChU337")
end

local function drawDynamic()
    local fl_y1 = 30
    buffer.drawRectangle(123, fl_y1-1, 35, 4, colors.bg, 0, " ")
    for i = 0, 34 do
        buffer.drawText(123 + i, fl_y1-2, colors.bg, brailleChar(brail_console[1]))
        buffer.drawText(123 + i, fl_y1,   colors.bg2, brailleChar(brail_console[2]))
    end
    buffer.drawText(124, fl_y1-1, colors.textclr, "Жидкости в МЭ сети:")
    drawDigit(125, fl_y1+1, brail_fluid, 0x0088ff)
    drawNumberWithText(143, fl_y1+1, 50000, 2, colors.textclr, "Mb", colors.textclr)

    fl_y1 = 35
    buffer.drawRectangle(123, fl_y1-1, 35, 4, colors.bg, 0, " ")
    for i = 0, 34 do
        buffer.drawText(123 + i, fl_y1-2, colors.bg, brailleChar(brail_console[1]))
        buffer.drawText(123 + i, fl_y1,   colors.bg2, brailleChar(brail_console[2]))
    end
    buffer.drawText(124, fl_y1-1, colors.textclr, "Настройка порога жидкости:")
    drawDigit(124, fl_y1+1, brail_greenbtn, 0xa6ff00)
    drawDigit(126, fl_y1+1, brail_redbtn,   0xff2121)
    drawNumberWithText(144, fl_y1+1, 50000, 2, colors.textclr, "Mb", colors.textclr)

    fl_y1 = 40
    buffer.drawRectangle(123, fl_y1, 35, 4, colors.bg, 0, " ")
    for i = 0, 34 do
        buffer.drawText(123 + i, fl_y1-1, colors.bg, brailleChar(brail_console[1]))
        buffer.drawText(123 + i, fl_y1+1, colors.bg2, brailleChar(brail_console[2]))
    end
    buffer.drawText(124, fl_y1, colors.textclr, "Генерация всех реакторов:")
    drawDigit(125, fl_y1+2, brail_thunderbolt, 0xffc400)
    drawNumberWithText(144, fl_y1+2, 0, 2, colors.textclr, "Rf/t", colors.textclr)

    buffer.drawRectangle(89, 44, 31, 6, colors.bg, 0, " ")
    buffer.drawText(90, 44, colors.textclr, "Статус комплекса:")
    for i = 0, 30 do
        buffer.drawText(89 + i, 43, colors.bg, brailleChar(brail_console[1]))
        buffer.drawText(89 + i, 45, colors.bg2, brailleChar(brail_console[2]))
    end
    buffer.drawText(110, 45, colors.bg2, brailleChar(brail_cherta[5]))
    buffer.drawText(110, 46, colors.bg2, brailleChar(brail_cherta[6]))
    buffer.drawText(110, 47, colors.bg2, brailleChar(brail_cherta[6]))
    buffer.drawText(110, 48, colors.bg2, brailleChar(brail_cherta[6]))
    buffer.drawText(110, 49, colors.bg2, brailleChar(brail_cherta[6]))
    buffer.drawText(90, 46, colors.textclr, "Кол-во реакторов: 0")
    buffer.drawText(90, 47, colors.textclr, "Общее потребление")
    buffer.drawText(90, 48, colors.textclr, "жидкости: 0 Mb/s")

    buffer.drawRectangle(112, 47, 6, 1, 0xfd3232, 0, " ")
    buffer.drawRectangle(113, 46, 4, 3, 0xfd3232, 0, " ")
    buffer.drawText(112, 46, 0xfd3232, brailleChar(brail_status[1]))
    buffer.drawText(117, 46, 0xfd3232, brailleChar(brail_status[2]))
    buffer.drawText(117, 48, 0xfd3232, brailleChar(brail_status[3]))
    buffer.drawText(112, 48, 0xfd3232, brailleChar(brail_status[4]))
    buffer.drawText(113, 47, 0x9d0000, "Stop")

    fl_y1 = 45
    buffer.drawRectangle(123, fl_y1, 35, 4, colors.bg, 0, " ")
    for i = 0, 34 do
        buffer.drawText(123 + i, fl_y1-1, colors.bg, brailleChar(brail_console[1]))
        buffer.drawText(123 + i, fl_y1+1, colors.bg2, brailleChar(brail_console[2]))
    end
    buffer.drawText(124, fl_y1, colors.textclr, "МЭ: Обн. ч/з..")
    buffer.drawText(141, fl_y1, colors.textclr, "Время работы:")
    drawDigit(125, fl_y1+2, brail_time, 0xaa4b2e)
    drawNumberWithText(134, fl_y1+2, 60, 2, colors.textclr, "Sec", colors.textclr)
    drawNumberWithText(146, fl_y1+2, 0, 2, colors.textclr, "Hrs", colors.textclr)
    drawNumberWithText(154, fl_y1+2, 0, 2, colors.textclr, "Min", colors.textclr)
end

local function handleTouch(x, y)
    if y >= 47 and y <= 49 and x >= 41 and x <= 64 then
        buffer.clear(0x000000)
        buffer.drawChanges()
        term.clear()
        os.exit()
    end
    if y >= 44 and y <= 46 then
        if x >= 13 and x <= 37 then
            buffer.drawRectangle(12, 44, 26, 3, colors.bg3, 0, " ")
            animatedButton(1, 13, 44, "Отключить реакторы!", nil, nil, 24, nil, nil, 0xfb3737)
            animatedButton(2, 13, 44, "Отключить реакторы!", nil, nil, 24, nil, nil, 0xfb3737)
            buffer.drawChanges()
            os.sleep(0.2)
            animatedButton(1, 13, 44, "Отключить реакторы!", nil, nil, 24, nil, nil, 0xfd3232)
        elseif x >= 41 and x <= 64 then
            buffer.drawRectangle(40, 44, 25, 3, colors.bg3, 0, " ")
            animatedButton(1, 41, 44, "Запуск реакторов!", nil, nil, 23, nil, nil, 0x61ff52)
            animatedButton(2, 41, 44, "Запуск реакторов!", nil, nil, 23, nil, nil, 0x61ff52)
            buffer.drawChanges()
            os.sleep(0.2)
            animatedButton(1, 41, 44, "Запуск реакторов!", nil, nil, 23, nil, nil, 0x35e525)
        elseif x >= 68 and x <= 86 then
            buffer.drawRectangle(67, 44, 20, 3, colors.bg3, 0, " ")
            animatedButton(1, 68, 44, "Пр.Обновить МЭ", nil, nil, 18, nil, nil, 0x38afff)
            animatedButton(2, 68, 44, "Пр.Обновить МЭ", nil, nil, 18, nil, nil, 0x38afff)
            buffer.drawChanges()
            os.sleep(0.2)
            animatedButton(1, 68, 44, "Пр.Обновить МЭ", nil, nil, 18, nil, nil, nil)
        end
    elseif y >= 47 and y <= 49 then
        if x >= 13 and x <= 37 then
            buffer.drawRectangle(12, 47, 26, 3, colors.bg3, 0, " ")
            animatedButton(1, 13, 47, "Рестарт программы.", nil, nil, 24, nil, nil, colors.whitebtn2)
            animatedButton(2, 13, 47, "Рестарт программы.", nil, nil, 24, nil, nil, colors.whitebtn2)
            buffer.drawChanges()
            os.sleep(0.2)
            animatedButton(1, 13, 47, "Рестарт программы.", nil, nil, 24, nil, nil, colors.whitebtn)
        elseif x >= 68 and x <= 86 then
            buffer.drawRectangle(67, 47, 20, 3, colors.bg3, 0, " ")
            animatedButton(1, 68, 47, "Метрика: Auto", nil, nil, 18, nil, nil, colors.whitebtn2)
            animatedButton(2, 68, 47, "Метрика: Auto", nil, nil, 18, nil, nil, colors.whitebtn2)
            buffer.drawChanges()
            os.sleep(0.2)
            animatedButton(1, 68, 47, "Метрика: Auto", nil, nil, 18, nil, nil, colors.whitebtn)
        end
    end
    if y >= 44 and y <= 46 and x >= 5 and x <= 9 then
        buffer.drawRectangle(4, 44, 6, 3, colors.bg3, 0, " ")
        animatedButton(1, 5, 44, "🔧", nil, nil, 4, nil, nil, 0x8100cc, 0xffffff)
        animatedButton(2, 5, 44, "🔧", nil, nil, 4, nil, nil, 0x8100cc, 0xffffff)
        buffer.drawChanges()
        os.sleep(0.2)
        animatedButton(1, 5, 44, "🔧", nil, nil, 4, nil, nil, 0xa91df9, 0xffffff)
    end
    if y >= 47 and y <= 49 and x >= 5 and x <= 9 then
        buffer.drawRectangle(4, 47, 6, 3, colors.bg3, 0, " ")
        animatedButton(1, 5, 47, "ⓘ", nil, nil, 4, nil, nil, 0x8100cc, 0x05e2ff)
        animatedButton(2, 5, 47, "ⓘ", nil, nil, 4, nil, nil, 0x8100cc, 0x05e2ff)
        buffer.drawChanges()
        os.sleep(0.2)
        animatedButton(1, 5, 47, "ⓘ", nil, nil, 4, nil, nil, 0xa91df9, 0x05e2ff)
    end
    buffer.drawChanges()
end

local lastTime = computer.uptime()
local second = 0
local minute = 0
local hour = 0
local supportersText = "а реакторы для тестов, Fiellyns - спасибо за поддержку!"

drawStatic()
drawDynamic()
buffer.drawChanges()

while true do
    local now = computer.uptime()
    if now - lastTime >= 1 then
        lastTime = now
        second = second + 1
        if second >= 60 then
            minute = minute + 1
            if minute >= 60 then
                hour = hour + 1
                minute = 0
            end
            second = 0
        end
        drawDynamic()
        drawMarquee(124, 6, supportersText .. "                            ", 0xF15F2C)
        buffer.drawChanges()
    end
    local ev = {event.pull(0.05)}
    if ev[1] == "touch" then
        handleTouch(ev[3], ev[4])
    end
end
