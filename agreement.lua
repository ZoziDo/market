-- ============================================================
-- ★★★ agreement.lua ★★★
-- ============================================================
local component = require("component")
local gpu = component.gpu
local unicode = require("unicode")

-- ============================================================
-- ★★★ ЦВЕТА ★★★
-- ============================================================
local COLORS = {
    BG_MAIN        = 0x0A0A0F,
    BG_BUTTON      = 0x1F1F2E,
    BG_SUCCESS     = 0x004400,
    ACCENT_MAIN    = 0x8B5CF6,
    ACCENT_SECONDARY = 0x00E5C9,
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
    BORDER         = 0x00E5C9,
    FRAME          = 0x3BFF18,
    TITLE          = 0x00CCFF,
}

-- ============================================================
-- ★★★ ПОЛУЧЕНИЕ РАЗМЕРА ЭКРАНА ★★★
-- ============================================================
local function getScreenSize()
    return gpu.getResolution()
end

-- ============================================================
-- ★★★ ОТРИСОВКА СОГЛАШЕНИЯ ★★★
-- ============================================================
local function drawAgreementScreen()
    local w, h = getScreenSize()
    
    -- Очистка
    gpu.setBackground(COLORS.BG_MAIN)
    gpu.fill(1, 1, w, h, " ")
    
    -- Рамка (адаптивная)
    local left, right, top, bottom = 3, w - 2, 2, h - 3
    gpu.setForeground(COLORS.BORDER)
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
    
    -- Функция центрирования
    local function center(y, txt, color)
        gpu.setForeground(color or COLORS.TEXT_MAIN)
        local x = math.floor((w - unicode.len(txt)) / 2) + 1
        gpu.set(x, y, txt)
    end
    
    -- Заголовок
    center(top + 3, "ПОЛЬЗОВАТЕЛЬСКОЕ СОГЛАШЕНИЕ", COLORS.TITLE)
    
    -- Текст
    local textY = top + 5
    center(textY, "Используя данный ПК-магазин, ты автоматически соглашаешься", COLORS.TEXT_MUTED)
    center(textY + 1, "со следующими условиями:", COLORS.TEXT_MUTED)
    
    center(textY + 3, "1. Все операции выполняются на ваш страх и риск.", COLORS.TEXT_MAIN)
    center(textY + 4, "2. Администрация не несёт ответственности за потерю предметов.", COLORS.TEXT_MAIN)
    center(textY + 5, "3. Запрещено использование багов и эксплойтов.", COLORS.TEXT_MAIN)
    
    -- Красная строка
    local redText = "   Нарушение = перманентная блокировка аккаунта."
    local redX = math.floor((w - unicode.len(redText)) / 2) + 1
    gpu.setForeground(COLORS.ERROR)
    gpu.set(redX, textY + 6, redText)
    
    center(textY + 8, "4. Цены могут изменяться без уведомления.", COLORS.TEXT_MAIN)
    center(textY + 9, "5. Все сделки окончательны. Возврат невозможен.", COLORS.TEXT_MAIN)
    
    center(textY + 11, "Нажимая кнопку ниже, ты подтверждаешь согласие со всеми", COLORS.TEXT_MUTED)
    center(textY + 12, "условиями данного соглашения.", COLORS.TEXT_MUTED)
    
    -- Кнопка (адаптивная)
    local btnText = "[ ПОНЯТНО ]"
    local btnW = unicode.len(btnText) + 4
    local btnX = math.floor((w - btnW) / 2) + 2
    local btnY = bottom - 2
    
    gpu.setBackground(COLORS.BG_SUCCESS)
    gpu.setForeground(COLORS.SUCCESS_GREEN)
    gpu.fill(btnX, btnY, btnW, 1, " ")
    gpu.set(btnX + 2, btnY, btnText)
    gpu.setBackground(COLORS.BG_MAIN)
end

return drawAgreementScreen
