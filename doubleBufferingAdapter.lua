local doubleBuffer = require("doubleBuffering")

-- Состояние адаптера
local currentBackground = 0x000000
local currentForeground = 0xFFFFFF
local needPresent = false
local width, height = doubleBuffer.getResolution()

-- Инициализация: устанавливаем разрешение как в оригинале
doubleBuffer.setResolution(80, 25)
width, height = 80, 25

-- Публичный API, полностью совместимый с component.gpu
local adapter = {}

function adapter.getResolution()
    return doubleBuffer.getResolution()
end

function adapter.setResolution(w, h)
    doubleBuffer.setResolution(w, h)
    width, height = w, h
end

function adapter.getBackground()
    return currentBackground
end

function adapter.setBackground(color)
    currentBackground = color
end

function adapter.getForeground()
    return currentForeground
end

function adapter.setForeground(color)
    currentForeground = color
end

function adapter.set(x, y, text)
    if not text or text == "" then return end
    local len = #text
    for i = 1, len do
        local ch = text:sub(i, i)
        if ch ~= "" then
            doubleBuffer.set(x + i - 1, y, currentBackground, currentForeground, ch)
        end
    end
    needPresent = true
end

function adapter.fill(x, y, w, h, char)
    if not char then char = " " end
    for j = y, y + h - 1 do
        for i = x, x + w - 1 do
            doubleBuffer.set(i, j, currentBackground, currentForeground, char)
        end
    end
    needPresent = true
end

function adapter.get(x, y)
    return doubleBuffer.get(x, y)  -- возвращает background, foreground, symbol
end

function adapter.copy(x, y, w, h, dx, dy)
    local picture = doubleBuffer.copy(x, y, w, h)
    doubleBuffer.paste(x + dx, y + dy, picture)
    needPresent = true
end

function adapter.getDepth()
    return 8  -- совместимость, можно вернуть реальное значение из GPU
end

function adapter.maxDepth()
    return 8
end

function adapter.maxResolution()
    return 160, 50
end

-- Метод, который нужно вызывать после завершения отрисовки кадра
function adapter.present()
    if needPresent then
        doubleBuffer.present()
        needPresent = false
    end
end

-- Принудительный сброс буфера (например, при смене экрана)
function adapter.flush()
    doubleBuffer.flush()
    needPresent = false
end

-- Для прямого доступа к оригинальному буферу (не обязательно)
function adapter.getDoubleBuffer()
    return doubleBuffer
end

return adapter
