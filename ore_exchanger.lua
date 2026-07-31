-- v3.0.3 - VIP-SHOP EXCHANGER: 16 руд, постоянный счётчик, защита Ctrl+Alt+C
-- Интерфейс автоматически использует максимальное разрешение видеокарты.
-- BUILD: VIP_SHOP_EXCHANGER_16_ORES_PERSISTENT_TOTAL_SAFE_INTERRUPT

local unicode = require("unicode")
local computer = require("computer")
local com = require("component")
local event = require("event")

-- Блокируем Ctrl+Alt+C на уровне библиотеки event.
-- В некоторых версиях OpenComputers shouldInterrupt уже существует,
-- поэтому переопределяем его и в этом случае.
if not event.shouldInterrupt then
    function event.shouldInterrupt()
        return false
    end
else
    event.shouldInterrupt = function()
        return false
    end
end

local fs = require("filesystem")
local shell = require("shell")
local inspect = {}

if not fs.exists("/lib/inspect.lua") then
    shell.execute("wget -q https://raw.githubusercontent.com/kikito/inspect.lua/master/inspect.lua /lib/inspect.lua")
end
inspect = require("inspect")

local me = com.isAvailable("me_interface") and com.me_interface or error("Интерфейс не подключен")
local pim = com.isAvailable("pim") and com.pim or error("PIM не подключен")
local gpu = com.gpu

-- ============================================================
-- МАКСИМАЛЬНОЕ РАЗРЕШЕНИЕ ЭКРАНА
-- ============================================================
local WIDTH, HEIGHT = gpu.getResolution()
local maxW, maxH = gpu.maxResolution()
if WIDTH < maxW or HEIGHT < maxH then
    gpu.setResolution(maxW, maxH)
    WIDTH, HEIGHT = gpu.getResolution()
end

local w, h = WIDTH, HEIGHT
local defBG, defFG = gpu.getBackground(), gpu.getForeground()

-- ============================================================
-- НАСТРОЙКИ ОБМЕННИКА
-- ============================================================
local EXPORT_DIR = "UP"
local PUSH_DIR = "DOWN"
local currDir = shell.getWorkingDirectory()
local STATS_FILE = currDir .. "/exchanger_stats.txt"
-- Постоянный файл общего счётчика. Значение не сбрасывается после перезапуска.
local TOTAL_FILE = currDir .. "/total_ore.txt"

-- ============================================================
-- ЦВЕТА GUI
-- ============================================================
local C = {
    bg          = 0x0C0C0C,
    logo        = 0x00E5C9,
    border      = 0x55FFFF,
    title       = 0x55FFFF,
    white       = 0xFFFFFF,
    gray        = 0x8A9499,
    darkGray    = 0x30383D,
    green       = 0x55FF55,
    yellow      = 0xFF4F00,
    red         = 0xFF5555,
    cyan        = 0x55FFFF,
    magenta     = 0xFF55FF,
    barEmpty    = 0x30383D,
    ratio       = 0xFFD75F,
    stock       = 0xFFFFFF
}
-- ============================================================
-- СПИСОК РУД
-- ============================================================
local ore_list = {
    { take = { label = "Алмазная руда", name = "minecraft:diamond_ore", amount = 1 }, give = { label = "Алмаз", name = "minecraft:diamond", amount = 2 } },
    { take = { label = "Железная руда", name = "minecraft:iron_ore", amount = 3 }, give = { label = "Железный слиток", name = "minecraft:iron_ingot", amount = 7 } },
    { take = { label = "Золотая руда", name = "minecraft:gold_ore", amount = 3 }, give = { label = "Золотой слиток", name = "minecraft:gold_ingot", amount = 7 } },
    { take = { label = "Лазуритовая руда", name = "minecraft:lapis_ore", amount = 1 }, give = { label = "Лазурит", name = "minecraft:dye", damage = 4.0, amount = 7 } },
    { take = { label = "Красная руда", name = "minecraft:redstone_ore", amount = 1 }, give = { label = "Блок красного камня", name = "minecraft:redstone_block", amount = 1 } },
    { take = { label = "Угольная руда", name = "minecraft:coal_ore", amount = 1 }, give = { label = "Уголь", name = "minecraft:coal", amount = 3 } },
    { take = { label = "Руда истинного кварца", name = "appliedenergistics2:tile.OreQuartz", amount = 1 }, give = { label = "Кристалл ист. кварца", name = "appliedenergistics2:item.ItemMultiMaterial", amount = 3 } },
    { take = { label = "Заряж. руда ист. квар", name = "appliedenergistics2:tile.OreQuartzCharged", amount = 1 }, give = { label = "Заряж. крист. кварца", name = "appliedenergistics2:item.ItemMultiMaterial", damage = 1.0, amount = 3 } },
    { take = { label = "Кварцевая руда", name = "minecraft:quartz_ore", amount = 1 }, give = { label = "Кварц", name = "minecraft:quartz", amount = 4 } },
    { take = { label = "Медная руда", name = "IC2:blockOreCopper", amount = 3 }, give = { label = "Медный слиток", name = "IC2:itemIngot", amount = 7 } },
    { take = { label = "Оловянная руда", name = "IC2:blockOreTin", amount = 3 }, give = { label = "Оловянный слиток", name = "IC2:itemIngot", damage = 1.0, amount = 7 } },
    { take = { label = "Свинцовая руда", name = "IC2:blockOreLead", amount = 1 }, give = { label = "Свинцовый слиток", name = "IC2:itemIngot", damage = 5.0, amount = 2 } },
    { take = { label = "Серебряная руда", name = "ThermalFoundation:Ore", damage = 2.0, amount = 1 }, give = { label = "Серебряный слиток", name = "IC2:itemIngot", damage = 6.0, amount = 2 } },
    { take = { label = "Платиновая руда", name = "ThermalFoundation:Ore", damage = 5.0, amount = 1 }, give = { label = "Измельчённая платина", name = "ThermalFoundation:material", damage = 37.0, amount = 2 } },
    { take = { label = "Никелевая руда", name = "ThermalFoundation:Ore", damage = 4.0, amount = 1 }, give = { label = "Никелевый слиток", name = "ThermalFoundation:material", damage = 68.0, amount = 2 } },
    { take = { label = "Дракониевая руда", name = "DraconicEvolution:draconiumOre", amount = 1 }, give = { label = "Дракониевая пыль", name = "DraconicEvolution:draconiumDust", amount = 2 } }
}

-- Целевой запас для каждой шкалы заполнения.
-- Поле limit в exchanger_ores.txt может переопределить значение для отдельной позиции.
local DEFAULT_STOCK_LIMIT = 5000000

local SHORT_NAMES = {
    ["minecraft:diamond_ore"] = "Алмаз",
    ["minecraft:iron_ore"] = "Железо",
    ["minecraft:gold_ore"] = "Золото",
    ["minecraft:lapis_ore"] = "Лазур",
    ["minecraft:redstone_ore"] = "Редст",
    ["minecraft:coal_ore"] = "Уголь",
    ["appliedenergistics2:tile.OreQuartz"] = "Ист.кв.",
    ["appliedenergistics2:tile.OreQuartzCharged"] = "Зар.кв.",
    ["minecraft:quartz_ore"] = "Кварц",
    ["IC2:blockOreCopper"] = "Медь",
    ["IC2:blockOreTin"] = "Олово",
    ["IC2:blockOreLead"] = "Свинец",
    ["ThermalFoundation:Ore:2"] = "Серебро",
    ["ThermalFoundation:Ore:5"] = "Платина",
    ["ThermalFoundation:Ore:4"] = "Никель",
    ["DraconicEvolution:draconiumOre"] = "Дракон"
}


-- Индивидуальные цвета полос для стандартных руд.
local BAR_COLORS = {
    ["minecraft:diamond_ore"] = 0x55FFFF,
    ["minecraft:iron_ore"] = 0xD8D8D8,
    ["minecraft:gold_ore"] = 0xFFFF55,
    ["minecraft:lapis_ore"] = 0x3366FF,
    ["minecraft:redstone_ore"] = 0xFF3333,
    ["minecraft:coal_ore"] = 0x666666,
    ["appliedenergistics2:tile.OreQuartz"] = 0xE8F8FF,
    ["appliedenergistics2:tile.OreQuartzCharged"] = 0x00AFFF,
    ["minecraft:quartz_ore"] = 0xFFF4D6,
    ["IC2:blockOreCopper"] = 0xFF9A3C,
    ["IC2:blockOreTin"] = 0xAADDFF,
    ["IC2:blockOreLead"] = 0x708090,
    ["ThermalFoundation:Ore:2"] = 0xC0C0C0,
    ["ThermalFoundation:Ore:5"] = 0x66E0D0,
    ["ThermalFoundation:Ore:4"] = 0xD4C060,
    ["DraconicEvolution:draconiumOre"] = 0xAA55FF
}

-- Запасная палитра для руд, добавленных через админское сканирование.
local BAR_PALETTE = {
    0x55FFFF, 0xFFFF55, 0x55FF55, 0xFF5555, 0xAA55FF,
    0xFF9A3C, 0x3366FF, 0xAADDFF, 0xFF55FF, 0xD8D8D8
}

-- ============================================================
-- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
-- ============================================================
local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function itemKey(name, damage)
    damage = tonumber(damage) or 0
    if damage ~= 0 then
        return tostring(name) .. ":" .. tostring(math.floor(damage))
    end
    return tostring(name)
end

local function fitText(text, width)
    text = tostring(text or "")
    width = math.max(0, width or 0)

    if unicode.len(text) <= width then
        return text
    end

    if width <= 1 then
        return unicode.sub(text, 1, width)
    end

    return unicode.sub(text, 1, width - 1) .. "…"
end

local function padRight(text, width)
    text = fitText(text, width)
    return text .. string.rep(" ", math.max(0, width - unicode.len(text)))
end

local function centeredX(startX, width, text)
    return startX + math.max(0, math.floor((width - unicode.len(text)) / 2))
end

local function setText(x, y, text, color, background)
    if background then gpu.setBackground(background) end
    if color then gpu.setForeground(color) end
    gpu.set(x, y, text)
end

local function formatNumber(num)
    num = tonumber(num) or 0
    local symbols = { "", "K", "M", "B", "T" }
    local symbolIndex = 1
    local value = math.abs(num)

    while value >= 1000 and symbolIndex < #symbols do
        value = value / 1000
        symbolIndex = symbolIndex + 1
    end

    local result
    if symbolIndex == 1 then
        result = tostring(math.floor(value + 0.5))
    else
        result = string.format("%.1f", value)
        if result:sub(-2) == ".0" then
            result = result:sub(1, -3)
        end
    end

    if num < 0 then result = "-" .. result end
    return result .. symbols[symbolIndex]
end

local function getOreName(ore)
    if ore.shortName and ore.shortName ~= "" then
        return ore.shortName
    end

    local key = itemKey(ore.take.name, ore.take.damage)
    return SHORT_NAMES[key] or SHORT_NAMES[ore.take.name] or ore.take.label or ore.take.name
end

local function getStockLimit(ore)
    return DEFAULT_STOCK_LIMIT
end

local function getBarColor(ore, index)
    local key = itemKey(ore.take.name, ore.take.damage)
    return BAR_COLORS[key]
        or BAR_COLORS[ore.take.name]
        or BAR_PALETTE[((index - 1) % #BAR_PALETTE) + 1]
end

-- ============================================================
-- ЗАГРУЗКА И СОХРАНЕНИЕ ДАННЫХ
-- ============================================================
local total_ores_global = 0

local function loadTotalOres()
    if fs.exists(TOTAL_FILE) then
        local f = io.open(TOTAL_FILE, "r")
        if f then
            local content = f:read("*all")
            f:close()
            total_ores_global = tonumber(content) or 0
            return
        end
    end

    -- Файл отсутствует или не читается: создаём его сразу со значением 0.
    total_ores_global = 0
    local f = io.open(TOTAL_FILE, "w")
    if f then
        f:write("0")
        f:close()
    end
end

local function saveTotalOres()
    local f = io.open(TOTAL_FILE, "w")
    if f then
        f:write(tostring(total_ores_global))
        f:close()
    end
end

loadTotalOres()

local oresPath = currDir .. "/exchanger_ores.txt"

if fs.exists(oresPath) then
    local file = io.open(oresPath, "r")
    if file then
        local content = file:read("*all")
        file:close()

        local loader, loadError = load("return " .. content)
        if not loader then
            error("Ошибка чтения таблицы " .. oresPath .. ": " .. tostring(loadError))
        end

        local success, oreTable = pcall(loader)
        if not success or type(oreTable) ~= "table" then
            error("Ошибка в таблице " .. oresPath .. ": " .. tostring(oreTable))
        end

        ore_list = oreTable
    end
end

-- Даже если exchanger_ores.txt был создан старой версией с 15 позициями,
-- обязательная свинцовая руда автоматически добавляется один раз.
local function ensureLeadOre()
    for _, ore in ipairs(ore_list) do
        if ore.take and ore.take.name == "IC2:blockOreLead"
            and (tonumber(ore.take.damage) or 0) == 0 then
            return false
        end
    end

    table.insert(ore_list, {
        take = {
            label = "Свинцовая руда",
            name = "IC2:blockOreLead",
            amount = 1
        },
        give = {
            label = "Свинцовый слиток",
            name = "IC2:itemIngot",
            damage = 5.0,
            amount = 2
        }
    })
    return true
end

local leadWasAdded = ensureLeadOre()

local function saveOres(ores)
    local file = io.open(oresPath, "w")
    if not file then
        return false
    end

    file:write(inspect(ores))
    file:close()
    return true
end

if leadWasAdded and fs.exists(oresPath) then
    -- Обновляем старую конфигурацию, чтобы свинец сохранился и после перезапуска.
    saveOres(ore_list)
end

-- ============================================================
-- БЛОКИРОВКА ЭКРАНА И БЕЗОПАСНЫЙ ЦИКЛ
-- ============================================================
local pimSession = {
    active = false,
    owner = nil
}

local function lowerText(value)
    value = tostring(value or "")
    if unicode and type(unicode.lower) == "function" then
        local ok, result = pcall(unicode.lower, value)
        if ok and result then return result end
    end
    return string.lower(value)
end

local function setPimOwner(playerName)
    if type(playerName) == "string" and playerName ~= "" and playerName ~= "null" then
        pimSession.active = true
        pimSession.owner = playerName
    else
        pimSession.active = false
        pimSession.owner = nil
    end
end

local function clearPimOwner()
    pimSession.active = false
    pimSession.owner = nil
end

-- Экран принимает действия только от игрока, который открыл текущую PIM-сессию.
local function isPimOwner(playerName)
    if not pimSession.active or not pimSession.owner then return false end
    if type(playerName) ~= "string" or playerName == "" then return false end
    return lowerText(playerName) == lowerText(pimSession.owner)
end

local function writeDebugLog(message)
    pcall(function()
        local file = io.open(currDir .. "/exchanger_debug.txt", "ab")
        if file then
            file:write(string.format("[%s] %s\n", os.date("%Y-%m-%d %H:%M:%S"), tostring(message)))
            file:close()
        end
    end)
end

-- Ctrl+Alt+C в OpenComputers вызывает interrupted или ошибку event.pull.
-- Оба варианта перехватываются и не завершают программу.
local function safeEventPull(timeout)
    local result = { pcall(event.pull, timeout) }
    if not result[1] then
        writeDebugLog("Попытка прервать скрипт заблокирована: " .. tostring(result[2]))
        return {}
    end

    table.remove(result, 1)
    return result
end

local function safeCall(label, callback, ...)
    local arguments = { ... }
    local function runner()
        return callback(table.unpack(arguments))
    end

    local ok, result = xpcall(runner, function(err)
        local trace = tostring(err)
        if debug and type(debug.traceback) == "function" then
            trace = debug.traceback(trace, 2)
        end
        return trace
    end)

    if not ok then
        writeDebugLog("Критическая ошибка [" .. tostring(label) .. "]: " .. tostring(result))
        return false, result
    end

    return true, result
end

-- ============================================================
-- GUI ORE EXCHANGER
-- ============================================================
-- Шестистрочный логотип VIP-SHOP. Каждая строка
-- автоматически выравнивается по центру экрана.
local LOGO_LINES = {
    "██╗   ██╗██╗██████╗       ███████╗██╗  ██╗ ██████╗ ██████╗ ",
    "██║   ██║██║██╔══██╗      ██╔════╝██║  ██║██╔═══██╗██╔══██╗",
    "██║   ██║██║██████╔╝█████╗███████╗███████║██║   ██║██████╔╝",
    "╚██╗ ██╔╝██║██╔═══╝ ╚════╝╚════██║██╔══██║██║   ██║██╔═══╝ ",
    " ╚████╔╝ ██║██║           ███████║██║  ██║╚██████╔╝██║     ",
    "  ╚═══╝  ╚═╝╚═╝           ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝     "
}
local FOOTER_OWNER = "ZoziDo"
local FOOTER_VERSION = "v_3.0.1"

local UI = {}

local function calculateLayout()
    -- Опускаем логотип ровно на одну строку вниз.
    UI.logoY = 2

    UI.logoW = 0
    for _, line in ipairs(LOGO_LINES) do
        UI.logoW = math.max(UI.logoW, unicode.len(line))
    end

    -- Информационная строка идёт сразу под логотипом.
    UI.subtitleY = UI.logoY + #LOGO_LINES
    UI.titleY = UI.subtitleY
    UI.tableTopY = UI.subtitleY + 2

    -- Пять колонок: исходная руда, шкала, запас, курс, результат.
    UI.takeW = 28
    UI.stockW = 12
    UI.ratioW = 9
    UI.giveW = 28

    -- На 160×50 шкала имеет ширину 50 символов, а вся таблица
    -- остаётся по центру. На меньшем экране шкала сжимается.
    local desiredProgressW = 50
    local fixedWidth = UI.takeW + UI.stockW + UI.ratioW + UI.giveW + 6
    UI.progressW = math.min(desiredProgressW, math.max(18, w - fixedWidth - 2))

    UI.tableW = fixedWidth + UI.progressW
    UI.tableX = math.max(1, math.floor((w - UI.tableW) / 2) + 1)
    UI.tableRight = UI.tableX + UI.tableW - 1

    UI.sep1 = UI.tableX + UI.takeW + 1
    UI.sep2 = UI.sep1 + UI.progressW + 1
    UI.sep3 = UI.sep2 + UI.stockW + 1
    UI.sep4 = UI.sep3 + UI.ratioW + 1

    UI.takeX = UI.tableX + 1
    UI.progressX = UI.sep1 + 1
    UI.stockX = UI.sep2 + 1
    UI.ratioX = UI.sep3 + 1
    UI.giveX = UI.sep4 + 1

    UI.headerY = UI.tableTopY + 1
    UI.headerSeparatorY = UI.tableTopY + 2
    UI.firstRowY = UI.tableTopY + 3

    -- Каждая позиция занимает две строки: строка предмета и пустой отступ.
    -- После переноса заголовка вверх на 160×50 помещаются все 16 руд.
    UI.rowHeight = 2
    UI.footerY = h
    local reservedBottom = 4 -- нижняя рамка таблицы, две строки статуса и футер
    local availableHeight = h - UI.firstRowY - reservedBottom
    local maxVisible = math.floor(availableHeight / UI.rowHeight)
    UI.visibleRows = math.max(1, math.min(#ore_list, maxVisible))
    UI.tableBottomY = UI.firstRowY + UI.visibleRows * UI.rowHeight

    UI.statusY = UI.tableBottomY + 2
    UI.hintY = UI.statusY + 1
    -- Счётчик рисуется прямо на нижней рамке таблицы справа.
    UI.totalY = UI.tableBottomY
end

calculateLayout()

local currentStatus = {
    text = "Система активна. Ожидаю игрока на PIM.",
    color = C.white,
    marker = C.green
}

local function makeBorder(left, middle1, middle2, middle3, middle4, right)
    return left
        .. string.rep("─", UI.takeW)
        .. middle1
        .. string.rep("─", UI.progressW)
        .. middle2
        .. string.rep("─", UI.stockW)
        .. middle3
        .. string.rep("─", UI.ratioW)
        .. middle4
        .. string.rep("─", UI.giveW)
        .. right
end

local function makeRow(takeName, progress, stock, ratio, giveName)
    return "│"
        .. padRight(takeName, UI.takeW)
        .. "│"
        .. padRight(progress, UI.progressW)
        .. "│"
        .. padRight(stock, UI.stockW)
        .. "│"
        .. padRight(ratio, UI.ratioW)
        .. "│"
        .. padRight(giveName, UI.giveW)
        .. "│"
end

local function drawLogo()
    gpu.setBackground(C.bg)
    gpu.setForeground(C.logo)

    for index, line in ipairs(LOGO_LINES) do
        local y = UI.logoY + index - 1
        gpu.fill(1, y, w, 1, " ")

        if line ~= "" then
            local visible = fitText(line, w)
            local x = math.max(1, math.floor((w - unicode.len(visible)) / 2) + 1)
            gpu.set(x, y, visible)
        end
    end
end

local function drawSubtitle()
    calculateLayout()
    gpu.setBackground(C.bg)
    gpu.fill(1, UI.subtitleY, w, 1, " ")

    local subtitle = "МГНОВЕННЫЙ ОБМЕН РУДЫ НА СЛИТКИ | ОБЩИЙ ЛИМИТ: 5M | ВЕРСИЯ 3.0.1"
    local visible = fitText(subtitle, w)
    local x = math.max(1, math.floor((w - unicode.len(visible)) / 2) + 1)
    setText(x, UI.subtitleY, visible, C.yellow, C.bg)
end

local function drawTableFrame()
    gpu.setBackground(C.bg)
    gpu.setForeground(C.border)

    gpu.set(UI.tableX, UI.tableTopY, makeBorder("┌", "┬", "┬", "┬", "┬", "┐"))
    gpu.set(
        UI.tableX,
        UI.headerY,
        makeRow(" ИСХОДНЫЙ ПРЕДМЕТ", " ПРОГРЕСС", " В МЭ", " КУРС", " РЕЗУЛЬТАТ")
    )
    gpu.set(UI.tableX, UI.headerSeparatorY, makeBorder("├", "┼", "┼", "┼", "┼", "┤"))
end

local function drawColoredRatio(ore, y)
    local leftAmount = tostring(ore.take.amount or 0)
    local rightAmount = tostring(ore.give.amount or 0)
    local ratioWidth = unicode.len(leftAmount) + 3 + unicode.len(rightAmount)
    local x = UI.ratioX + math.max(0, math.floor((UI.ratioW - ratioWidth) / 2))

    setText(x, y, leftAmount, C.magenta, C.bg)
    x = x + unicode.len(leftAmount)
    setText(x, y, " > ", C.yellow, C.bg)
    x = x + 3
    setText(x, y, rightAmount, C.magenta, C.bg)
end

-- Обновляет только шкалу и число остатка. Названия и вся таблица не стираются,
-- поэтому во время выдачи предметов экран больше не моргает.
local function drawOreStock(ore, index)
    local y = UI.firstRowY + (index - 1) * UI.rowHeight
    if y >= UI.tableBottomY then return end

    local stock = math.max(0, tonumber(ore.size) or 0)
    local limit = math.max(1, getStockLimit(ore))
    local fraction = clamp(stock / limit, 0, 1)
    local barWidth = math.max(1, UI.progressW - 4)
    local filled = math.floor(barWidth * fraction + 0.5)
    if stock > 0 and filled == 0 then filled = 1 end
    filled = clamp(filled, 0, barWidth)
    local empty = barWidth - filled

    gpu.setBackground(C.bg)
    gpu.fill(UI.progressX, y, UI.progressW, 1, " ")
    gpu.fill(UI.stockX, y, UI.stockW, 1, " ")

    local bracketX = UI.progressX + 1
    setText(bracketX, y, "[", C.gray, C.bg)
    if filled > 0 then
        setText(bracketX + 1, y, string.rep("█", filled), getBarColor(ore, index), C.bg)
    end
    if empty > 0 then
        setText(bracketX + 1 + filled, y, string.rep("░", empty), C.barEmpty, C.bg)
    end
    setText(bracketX + 1 + barWidth, y, "]", C.gray, C.bg)

    local stockText = formatNumber(stock) .. "/" .. formatNumber(limit)
    setText(UI.stockX, y, padRight(" " .. stockText, UI.stockW), C.stock, C.bg)
end

local function drawOreRow(ore, index)
    local y = UI.firstRowY + (index - 1) * UI.rowHeight
    if y >= UI.tableBottomY then return end

    gpu.setBackground(C.bg)
    gpu.fill(UI.tableX, y, UI.tableW, 1, " ")

    gpu.setForeground(C.border)
    gpu.set(UI.tableX, y, "│")
    gpu.set(UI.sep1, y, "│")
    gpu.set(UI.sep2, y, "│")
    gpu.set(UI.sep3, y, "│")
    gpu.set(UI.sep4, y, "│")
    gpu.set(UI.tableRight, y, "│")

    setText(UI.takeX, y, padRight(" " .. tostring(ore.take.label or ore.take.name), UI.takeW), C.green, C.bg)
    setText(UI.giveX, y, padRight(" " .. tostring(ore.give.label or ore.give.name), UI.giveW), C.green, C.bg)

    drawOreStock(ore, index)

    gpu.fill(UI.ratioX, y, UI.ratioW, 1, " ")
    drawColoredRatio(ore, y)
end

local function refreshStockColumns()
    calculateLayout()
    for index = 1, UI.visibleRows do
        if ore_list[index] then
            drawOreStock(ore_list[index], index)
        end
    end
end

local function drawRows()
    calculateLayout()
    drawTableFrame()

    for index = 1, UI.visibleRows do
        drawOreRow(ore_list[index], index)

        -- Пустая строка после каждого предмета, но вертикальные
        -- границы таблицы продолжаются без разрывов.
        local blankY = UI.firstRowY + (index - 1) * UI.rowHeight + 1
        if blankY < UI.tableBottomY then
            gpu.setBackground(C.bg)
            gpu.fill(UI.tableX, blankY, UI.tableW, 1, " ")
            gpu.setForeground(C.border)
            gpu.set(UI.tableX, blankY, "│")
            gpu.set(UI.sep1, blankY, "│")
            gpu.set(UI.sep2, blankY, "│")
            gpu.set(UI.sep3, blankY, "│")
            gpu.set(UI.sep4, blankY, "│")
            gpu.set(UI.tableRight, blankY, "│")
        end
    end

    gpu.setBackground(C.bg)
    gpu.setForeground(C.border)
    gpu.set(UI.tableX, UI.tableBottomY, makeBorder("└", "┴", "┴", "┴", "┴", "┘"))
end

local function drawStatus()
    calculateLayout()
    gpu.setBackground(C.bg)

    if UI.statusY < UI.footerY then
        gpu.fill(1, UI.statusY, w, 1, " ")

        local maxTextWidth = math.max(0, UI.tableW - 6)
        local visibleStatus = fitText(currentStatus.text, maxTextWidth)
        local fullWidth = 4 + unicode.len(visibleStatus)
        local x = UI.tableX + math.max(0, math.floor((UI.tableW - fullWidth) / 2))

        setText(x, UI.statusY, "[", C.gray, C.bg)
        setText(x + 1, UI.statusY, "●", currentStatus.marker, C.bg)
        setText(x + 2, UI.statusY, "] ", C.gray, C.bg)
        setText(x + 4, UI.statusY, visibleStatus, currentStatus.color, C.bg)
    end

    if UI.hintY < UI.footerY then
        gpu.fill(1, UI.hintY, w, 1, " ")
        local hint = fitText("[Для обмена встаньте на PIM и не сходите]", UI.tableW - 4)
        local hintX = centeredX(UI.tableX, UI.tableW, hint)
        setText(hintX, UI.hintY, hint, C.gray, C.bg)
    end
end

local function drawFooter()
    calculateLayout()
    gpu.setBackground(C.bg)
    gpu.fill(1, UI.footerY, w, 1, " ")

    -- Полноширинная нижняя строка, как на скриншоте.
    gpu.setForeground(C.border)
    if w >= 2 then
        gpu.set(1, UI.footerY, "+" .. string.rep("=", w - 2) .. "+")
    else
        gpu.set(1, UI.footerY, "+")
    end

    local footerText = "[ " .. FOOTER_OWNER .. " ] [ " .. FOOTER_VERSION .. " ]"
    local footerX = math.max(1, math.floor((w - unicode.len(footerText)) / 2) + 1)
    setText(footerX, UI.footerY, footerText, C.gray, C.bg)
end

local function drawTotalLine()
    calculateLayout()
    if UI.totalY < 1 or UI.totalY > h then return end

    local total = "[Всего обменено: " .. formatNumber(total_ores_global) .. " руды]"
    local maxWidth = math.max(1, UI.giveW + UI.ratioW + UI.stockW)
    local visible = fitText(total, maxWidth)
    -- Поднимаем счётчик на нижнюю рамку таблицы и прижимаем вправо.
    local x = math.max(UI.tableX + 1, UI.tableRight - unicode.len(visible) - 1)

    -- Под текстом очищается только нужный участок рамки, остальная рамка не мигает.
    gpu.setBackground(C.bg)
    gpu.fill(x, UI.totalY, unicode.len(visible), 1, " ")
    setText(x, UI.totalY, visible, C.cyan, C.bg)
end

local function setStatus(text, color, marker)
    currentStatus.text = tostring(text or "")
    currentStatus.color = color or C.white
    currentStatus.marker = marker or C.green
    drawStatus()
end

local function drawInterface()
    calculateLayout()
    gpu.setBackground(C.bg)
    gpu.setForeground(C.white)
    gpu.fill(1, 1, w, h, " ")

    drawLogo()
    drawSubtitle()
    drawRows()
    drawStatus()
    drawTotalLine()
    drawFooter()
end

-- ============================================================
-- ОБНОВЛЕНИЕ ОСТАТКОВ В МЭ
-- ============================================================
local function updIngotsSize()
    if #ore_list < 1 then return false end

    local meResponded = false

    for _, ore in ipairs(ore_list) do
        local giveDamage = ore.give.damage or 0
        local success, item = pcall(function()
            local detail = me.getItemDetail({ id = ore.give.name, dmg = giveDamage })
            if detail and detail.basic then
                return detail.basic()
            end
            return nil
        end)

        if success then
            meResponded = true
        end

        if success and item then
            ore.size = tonumber(item.qty) or 0
            ore.maxSize = tonumber(item.max_size) or 64
        else
            ore.size = 0
            ore.maxSize = 64
        end
    end

    return meResponded
end

local function drawInfo(drawType)
    if drawType == "full" then
        drawInterface()
    else
        refreshStockColumns()
        drawStatus()
        drawTotalLine()
    end
end

local function updInfo(drawType)
    drawType = drawType or "full"
    local connected = updIngotsSize()
    drawInfo(drawType)

    if not connected then
        setStatus("Нет соединения с МЭ или руды не настроены.", C.red, C.red)
    end

    return connected
end

-- ============================================================
-- СТАТИСТИКА ОБМЕНА
-- ============================================================
local stats = { ores = 0, ingots = 0 }

local function saveStats()
    local f = io.open(STATS_FILE, "a")
    if f then
        f:write(string.format(
            "[%s] Переработано руды: %d, выдано слитков: %d\n",
            os.date("%Y-%m-%d %H:%M:%S"),
            stats.ores,
            stats.ingots
        ))
        f:close()
    end
end

-- ============================================================
-- ЛОГИКА ОБМЕНА
-- ============================================================
local function giveIngot(toGive, ore, index)
    local totalGive = 0
    local giveDamage = ore.give.damage or 0

    while totalGive < toGive do
        local giveSize = math.min(toGive - totalGive, ore.maxSize or 64)
        local success, res = pcall(
            me.exportItem,
            { id = ore.give.name, dmg = giveDamage },
            EXPORT_DIR,
            giveSize
        )

        if success and res and res.size and res.size > 0 then
            totalGive = totalGive + res.size
            ore_list[index].size = math.max(0, (ore_list[index].size or 0) - res.size)
            stats.ingots = stats.ingots + res.size
            drawOreStock(ore_list[index], index)
        else
            setStatus(
                string.format(
                    "Ошибка выдачи: осталось выдать %d × %s. Проверьте инвентарь и направление.",
                    toGive - totalGive,
                    ore.give.label
                ),
                C.red,
                C.red
            )
            os.sleep(1)
        end
    end
end

local function exchangeOre(slot, ore, index)
    local success, curSlot = pcall(pim.getStackInSlot, slot)
    if not success or not curSlot then
        setStatus("Вы сошли с PIM. Обмен прерван.", C.red, C.red)
        os.sleep(1)
        return false
    end

    local userOreSize = tonumber(curSlot.qty) or 0
    local takeAmount = tonumber(ore.take.amount) or 1
    local giveAmount = tonumber(ore.give.amount) or 1
    local takeSize = userOreSize - (userOreSize % takeAmount)

    if takeSize == 0 then
        return true
    end

    local giveSize = (takeSize / takeAmount) * giveAmount

    if (tonumber(ore.size) or 0) < giveSize then
        setStatus(
            string.format(
                "Недостаточно: %s — в МЭ %d, требуется %d.",
                ore.give.label,
                tonumber(ore.size) or 0,
                giveSize
            ),
            C.red,
            C.red
        )
        os.sleep(2)
        return false
    end

    local pushSuccess, takedOre = pcall(pim.pushItem, PUSH_DIR, slot, takeSize)
    if not pushSuccess or not takedOre or takedOre == 0 then
        setStatus(
            "Не удалось забрать руду. Проверьте ME-интерфейс и направление PUSH_DIR.",
            C.red,
            C.red
        )
        os.sleep(2)
        return false
    end

    local actualGive = math.floor(takedOre / takeAmount) * giveAmount
    stats.ores = stats.ores + takedOre
    total_ores_global = total_ores_global + takedOre
    saveTotalOres()
    drawTotalLine()

    setStatus(
        string.format(
            "Обмен: %d × %s → %d × %s",
            takedOre,
            getOreName(ore),
            actualGive,
            ore.give.label
        ),
        C.yellow,
        C.yellow
    )

    giveIngot(actualGive, ore, index)
    return true
end

local function playerIsOnPim()
    local success, inventoryName = pcall(pim.getInventoryName)
    return success and inventoryName and inventoryName ~= "pim"
end

local function checkInventory()
    for i = 2, 1, -1 do
        setStatus(string.format("Обмен начнётся через %d сек...", i), C.yellow, C.yellow)
        os.sleep(1)
    end

    local sizeSuccess, size = pcall(pim.getInventorySize)
    local dataSuccess, data = pcall(pim.getAllStacks, 0)

    if not sizeSuccess or not dataSuccess or not size or not data then
        setStatus("Не удалось прочитать инвентарь PIM.", C.red, C.red)
        return false
    end

    local forceBreak = false

    for slot = 1, size do
        if forceBreak then break end

        if data[slot] then
            for index, ore in pairs(ore_list) do
                local needDamage = ore.take.damage or 0
                if data[slot].id == ore.take.name and data[slot].dmg == needDamage then
                    if not exchangeOre(slot, ore, index) then
                        forceBreak = true
                        break
                    end
                end
            end
        end
    end

    updIngotsSize()
    refreshStockColumns()
    setStatus(
        string.format(
            "Обмен завершён. Принято: %d руды, выдано: %d предметов.",
            stats.ores,
            stats.ingots
        ),
        C.green,
        C.green
    )
    saveStats()

    if playerIsOnPim() then
        return checkInventory()
    end

    event.push("player_off")
    return true
end

-- ============================================================
-- АДМИНИСТРАТОРСКОЕ СКАНИРОВАНИЕ
-- ============================================================
local function isAdmin(user)
    local users = table.pack(computer.users())
    for _, adminUser in pairs(users) do
        if adminUser == user then
            return true
        end
    end
    return false
end

local function scanExchangeConfiguration()
    computer.beep(1500, 0.1)

    for i = 5, 1, -1 do
        setStatus(
            string.format("Сканирование конфигурации через %d сек...", i),
            C.yellow,
            C.yellow
        )
        os.sleep(1)
    end

    setStatus("Сканирую пары предметов в инвентаре...", C.cyan, C.cyan)
    computer.beep(1500, 0.8)

    if playerIsOnPim() then
        ore_list = {}
        local success, data = pcall(pim.getAllStacks, 0)

        if not success or not data then
            setStatus("Не удалось получить содержимое инвентаря.", C.red, C.red)
            return
        end

        local i = 10
        while i ~= 9 do
            if i == 18 or i == 27 then
                i = i + 1
            elseif i == 36 then
                i = 1
            end

            if data[i] and data[i + 1] then
                table.insert(ore_list, {
                    take = {
                        label = data[i].display_name,
                        name = data[i].id,
                        damage = data[i].dmg,
                        amount = math.floor(data[i].qty)
                    },
                    give = {
                        label = data[i + 1].display_name,
                        name = data[i + 1].id,
                        damage = data[i + 1].dmg,
                        amount = math.floor(data[i + 1].qty)
                    }
                })
            end

            i = i + 2
        end

        saveOres(ore_list)
        computer.beep(500, 0.2)
        updInfo("full")
        setStatus("Новая конфигурация обмена сохранена.", C.green, C.green)
    else
        setStatus("Не найден инвентарь для сканирования.", C.red, C.red)
        computer.beep(2000, 0.2)
        computer.beep(2000, 0.2)
    end

    os.sleep(1)

    for i = 5, 1, -1 do
        setStatus(string.format("Возобновление работы через %d сек...", i), C.gray, C.yellow)
        os.sleep(1)
    end

    setStatus("Система активна. Ожидаю игрока на PIM.", C.white, C.green)
end

-- ============================================================
-- СОБЫТИЯ
-- ============================================================
local function handleEvent(eventName, ...)
    local args = { ... }

    -- Ctrl+Alt+C / interrupted намеренно игнорируется.
    if eventName == "interrupted" then
        writeDebugLog("Попытка завершить обменник через Ctrl+Alt+C заблокирована")
        return
    end

    if eventName == "player_on" then
        local playerName = tostring(args[1] or "")
        setPimOwner(playerName)

        if not updInfo("ingots") then return end

        stats.ores = 0
        stats.ingots = 0

        setStatus(
            string.format("Игрок %s на PIM. Начинаю проверку руды.", playerName ~= "" and playerName or "Неизвестный"),
            C.green,
            C.green
        )
        checkInventory()
        return
    end

    if eventName == "player_off" then
        clearPimOwner()
        if not updInfo("ingots") then return end
        setStatus("Система активна. Ожидаю игрока на PIM.", C.white, C.green)
        return
    end

    if eventName == "touch" then
        local touchPlayer = args[5] or "Неизвестный"

        -- === Блокировка экрана ===
        if not isPimOwner(touchPlayer) then
            writeDebugLog("Коснулся не владелец: " .. tostring(touchPlayer) .. ", игнорируем")
            return
        end

        -- Скрытая админ-зона доступна только владельцу текущей PIM-сессии,
        -- который одновременно является администратором компьютера.
        if args[2] >= UI.tableRight - 38
            and args[3] >= UI.statusY
            and args[3] <= UI.hintY
            and isAdmin(touchPlayer) then
            scanExchangeConfiguration()
        end
        return
    end

    -- В интерфейсе нет управления прокруткой и клавиатурой, поэтому эти
    -- события полностью блокируются. Попытки посторонних сохраняются в лог.
    if eventName == "scroll" then
        local scrollPlayer = args[5] or "Неизвестный"
        if not isPimOwner(scrollPlayer) then
            writeDebugLog("Прокрутил не владелец: " .. tostring(scrollPlayer) .. ", игнорируем")
        end
        return
    end

    if eventName == "key_down" then
        local keyPlayer = args[4] or "Неизвестный"
        if not isPimOwner(keyPlayer) then
            writeDebugLog("Нажал клавишу не владелец: " .. tostring(keyPlayer) .. ", игнорируем")
        end
        return
    end
end

-- ============================================================
-- ЗАПУСК С АВТОМАТИЧЕСКИМ ВОССТАНОВЛЕНИЕМ
-- ============================================================
local function isInterruptError(err)
    local message = lowerText(err)
    return message:find("interrupted", 1, true) ~= nil
        or message:find("interrupt", 1, true) ~= nil
        or message:find("прерван", 1, true) ~= nil
end

local function resumeExchangeAfterProtectedError(err)
    if not playerIsOnPim() then
        return false
    end

    writeDebugLog("Игрок остаётся на PIM, обмен автоматически продолжен после ошибки: " .. tostring(err))
    local ok, resumeError = safeCall("resumeExchange", checkInventory)
    if not ok then
        writeDebugLog("Не удалось автоматически продолжить обмен: " .. tostring(resumeError))
    end
    return ok
end

local function main()
    drawInterface()

    if updInfo("full") then
        setStatus("Система активна. Ожидаю игрока на PIM.", C.white, C.green)
    end

    while true do
        local ev = safeEventPull(1)
        if ev[1] then
            local ok, err = safeCall("handleEvent", handleEvent, table.unpack(ev))
            if not ok then
                -- Ctrl+Alt+C больше не оставляет обменник ждать нового player_on.
                -- Если игрок всё ещё на PIM, проверка инвентаря запускается снова сразу.
                if not resumeExchangeAfterProtectedError(err) then
                    if isInterruptError(err) then
                        setStatus("Система активна. Ожидаю игрока на PIM.", C.white, C.green)
                    else
                        setStatus("Ошибка обработана. Обменник продолжает работу.", C.red, C.red)
                    end
                end
            end
        end
    end
end

-- Даже критическая ошибка внутри main не закрывает скрипт: ошибка пишется
-- в лог, экран восстанавливается, после чего основной цикл запускается снова.
while true do
    local ok, err = safeCall("main", main)
    if not ok then
        pcall(function()
            computer.beep(2000, 0.25)
            os.sleep(0.5)
        end)
    else
        -- main в нормальной работе не завершается. Если это всё же произошло,
        -- запускаем его снова вместо выхода в оболочку.
        writeDebugLog("Основной цикл завершился без ошибки и был перезапущен")
        os.sleep(0.2)
    end
end
