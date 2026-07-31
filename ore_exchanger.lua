-- v3.0 - Полностью обновлённый GUI динамического обменника
-- Интерфейс автоматически использует максимальное разрешение видеокарты.

local unicode = require("unicode")
local computer = require("computer")
local com = require("component")
local event = require("event")
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
local STATS_FILE = "exchanger_stats.txt"
local TOTAL_FILE = "total_ore.txt"

-- ============================================================
-- ЦВЕТА GUI
-- ============================================================
local C = {
    bg          = 0x0C0C0C,
    panel       = 0x101820,
    header      = 0x11262B,
    border      = 0x27BDEC,
    title       = 0x55FFFF,
    white       = 0xFFFFFF,
    gray        = 0x8A9499,
    darkGray    = 0x30383D,
    green       = 0x55FF55,
    yellow      = 0xFFFF55,
    red         = 0xFF5555,
    cyan        = 0x55FFFF,
    barFill     = 0x00D084,
    barEmpty    = 0x354047,
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
    { take = { label = "Серебряная руда", name = "ThermalFoundation:Ore", damage = 2.0, amount = 1 }, give = { label = "Серебрянный слиток", name = "IC2:itemIngot", damage = 6.0, amount = 2 } },
    { take = { label = "Платиновая руда", name = "ThermalFoundation:Ore", damage = 5.0, amount = 1 }, give = { label = "Измельчённая платина", name = "ThermalFoundation:material", damage = 37.0, amount = 2 } },
    { take = { label = "Никелевая руда", name = "ThermalFoundation:Ore", damage = 4.0, amount = 1 }, give = { label = "Никелевый слиток", name = "ThermalFoundation:material", damage = 68.0, amount = 2 } },
    { take = { label = "Дракониевая руда", name = "DraconicEvolution:draconiumOre", amount = 1 }, give = { label = "Дракониевая пыль", name = "DraconicEvolution:draconiumDust", amount = 2 } }
}

-- Целевой запас для полосы заполнения.
-- Для новой руды можно указать поле limit прямо в exchanger_ores.txt.
local STOCK_LIMITS = {
    ["minecraft:diamond"] = 10000,
    ["minecraft:iron_ingot"] = 500,
    ["minecraft:gold_ingot"] = 500,
    ["minecraft:dye:4"] = 5000,
    ["minecraft:redstone_block"] = 2000,
    ["minecraft:coal"] = 5000,
    ["appliedenergistics2:item.ItemMultiMaterial:0"] = 5000,
    ["appliedenergistics2:item.ItemMultiMaterial:1"] = 2500,
    ["minecraft:quartz"] = 5000,
    ["IC2:itemIngot:0"] = 500,
    ["IC2:itemIngot:1"] = 500,
    ["IC2:itemIngot:6"] = 500,
    ["ThermalFoundation:material:37"] = 500,
    ["ThermalFoundation:material:68"] = 500,
    ["DraconicEvolution:draconiumDust"] = 5000
}

local SHORT_NAMES = {
    ["minecraft:diamond_ore"] = "Алмаз",
    ["minecraft:iron_ore"] = "Железо",
    ["minecraft:gold_ore"] = "Золото",
    ["minecraft:lapis_ore"] = "Лазурит",
    ["minecraft:redstone_ore"] = "Редстоун",
    ["minecraft:coal_ore"] = "Уголь",
    ["appliedenergistics2:tile.OreQuartz"] = "Ист. кварц",
    ["appliedenergistics2:tile.OreQuartzCharged"] = "Заряж. кварц",
    ["minecraft:quartz_ore"] = "Кварц",
    ["IC2:blockOreCopper"] = "Медь",
    ["IC2:blockOreTin"] = "Олово",
    ["ThermalFoundation:Ore:2"] = "Серебро",
    ["ThermalFoundation:Ore:5"] = "Платина",
    ["ThermalFoundation:Ore:4"] = "Никель",
    ["DraconicEvolution:draconiumOre"] = "Драконий"
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
    local customLimit = tonumber(ore.limit or ore.stockLimit or ore.maxStock)
    if customLimit and customLimit > 0 then
        return customLimit
    end

    local key = itemKey(ore.give.name, ore.give.damage)
    return STOCK_LIMITS[key] or STOCK_LIMITS[ore.give.name] or 1000
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
        end
    else
        total_ores_global = 0
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

local currDir = shell.getWorkingDirectory()
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

local function saveOres(ores)
    local file = io.open(oresPath, "w")
    if not file then
        return false
    end

    file:write(inspect(ores))
    file:close()
    return true
end

-- ============================================================
-- ДИНАМИЧЕСКАЯ РАЗМЕТКА GUI
-- ============================================================
local UI = {}

local function calculateLayout()
    UI.top = 1
    UI.headerY = 2
    UI.headerSeparatorY = 3
    UI.firstRowY = 4
    UI.statusSeparatorY = h - 2
    UI.statusY = h - 1
    UI.bottomY = h

    local innerWidth = w - 2
    UI.nameW = clamp(math.floor(innerWidth * 0.18), 12, 28)
    UI.stockW = clamp(math.floor(innerWidth * 0.14), 12, 19)
    UI.ratioW = clamp(math.floor(innerWidth * 0.12), 11, 16)
    UI.barW = innerWidth - UI.nameW - UI.stockW - UI.ratioW - 3

    if UI.barW < 12 then
        local missing = 12 - UI.barW
        UI.nameW = math.max(8, UI.nameW - missing)
        UI.barW = innerWidth - UI.nameW - UI.stockW - UI.ratioW - 3
    end

    UI.sep1 = 2 + UI.nameW
    UI.sep2 = UI.sep1 + UI.barW + 1
    UI.sep3 = UI.sep2 + UI.stockW + 1

    UI.nameX = 2
    UI.barX = UI.sep1 + 1
    UI.stockX = UI.sep2 + 1
    UI.ratioX = UI.sep3 + 1

    UI.visibleRows = math.max(0, UI.statusSeparatorY - UI.firstRowY)
end

calculateLayout()

local currentStatus = {
    text = "Система активна. Ожидаю игрока на PIM.",
    color = C.white,
    marker = C.green
}

local function drawHeader()
    gpu.setBackground(C.header)
    gpu.fill(2, UI.headerY, w - 2, 1, " ")

    local title = "↻ ДИНАМИЧЕСКИЙ ОБМЕННИК"
    local total = "[Общий счёт: " .. formatNumber(total_ores_global) .. " руды]"
    local totalX = w - unicode.len(total) - 2
    local availableTitleWidth = math.max(1, totalX - 4)

    title = fitText(title, availableTitleWidth)
    setText(3, UI.headerY, title, C.title, C.header)
    setText(totalX, UI.headerY, total, C.white, C.header)
end

local function drawTopBorder()
    gpu.setBackground(C.bg)
    gpu.setForeground(C.border)
    gpu.set(1, UI.top, "┌" .. string.rep("─", w - 2) .. "┐")
end

local function drawHeaderSeparator()
    gpu.setBackground(C.bg)
    gpu.setForeground(C.border)

    local line = "├"
        .. string.rep("─", UI.nameW)
        .. "┬"
        .. string.rep("─", UI.barW)
        .. "┬"
        .. string.rep("─", UI.stockW)
        .. "┬"
        .. string.rep("─", UI.ratioW)
        .. "┤"

    gpu.set(1, UI.headerSeparatorY, line)
end

local function drawStatusSeparator()
    gpu.setBackground(C.bg)
    gpu.setForeground(C.border)

    local line = "├"
        .. string.rep("─", UI.nameW)
        .. "┴"
        .. string.rep("─", UI.barW)
        .. "┴"
        .. string.rep("─", UI.stockW)
        .. "┴"
        .. string.rep("─", UI.ratioW)
        .. "┤"

    gpu.set(1, UI.statusSeparatorY, line)
end

local function drawBottomBorder()
    gpu.setBackground(C.bg)
    gpu.setForeground(C.border)
    gpu.set(1, UI.bottomY, "└" .. string.rep("─", w - 2) .. "┘")
end

local function drawBodyGrid()
    gpu.setBackground(C.panel)

    for y = UI.firstRowY, UI.statusSeparatorY - 1 do
        gpu.fill(2, y, w - 2, 1, " ")
        gpu.setForeground(C.border)
        gpu.setBackground(C.bg)
        gpu.set(1, y, "│")
        gpu.set(UI.sep1, y, "│")
        gpu.set(UI.sep2, y, "│")
        gpu.set(UI.sep3, y, "│")
        gpu.set(w, y, "│")
    end
end

local function drawStatus()
    gpu.setBackground(C.panel)
    gpu.fill(2, UI.statusY, w - 2, 1, " ")

    gpu.setBackground(C.bg)
    gpu.setForeground(C.border)
    gpu.set(1, UI.statusY, "│")
    gpu.set(w, UI.statusY, "│")

    setText(3, UI.statusY, "[", C.gray, C.panel)
    setText(4, UI.statusY, "●", currentStatus.marker, C.panel)
    setText(5, UI.statusY, "]", C.gray, C.panel)

    local statusWidth = math.max(0, w - 9)
    setText(7, UI.statusY, fitText(currentStatus.text, statusWidth), currentStatus.color, C.panel)
end

local function setStatus(text, color, marker)
    currentStatus.text = tostring(text or "")
    currentStatus.color = color or C.white
    currentStatus.marker = marker or C.green
    drawStatus()
end

local function drawOreRow(ore, rowIndex)
    local y = UI.firstRowY + rowIndex - 1
    if y >= UI.statusSeparatorY then return end

    local stock = math.max(0, tonumber(ore.size) or 0)
    local limit = math.max(1, getStockLimit(ore))
    local ratio = clamp(stock / limit, 0, 1)
    local innerBarW = math.max(1, UI.barW - 2)
    local filled = math.floor(innerBarW * ratio + 0.5)
    local empty = innerBarW - filled

    gpu.setBackground(C.panel)
    gpu.fill(UI.nameX, y, UI.nameW, 1, " ")
    gpu.fill(UI.barX, y, UI.barW, 1, " ")
    gpu.fill(UI.stockX, y, UI.stockW, 1, " ")
    gpu.fill(UI.ratioX, y, UI.ratioW, 1, " ")

    local name = padRight(" " .. getOreName(ore), UI.nameW)
    setText(UI.nameX, y, name, C.white, C.panel)

    local barStartX = UI.barX + 1
    if filled > 0 then
        setText(barStartX, y, string.rep("█", filled), C.barFill, C.panel)
    end
    if empty > 0 then
        setText(barStartX + filled, y, string.rep("░", empty), C.barEmpty, C.panel)
    end

    local stockText = formatNumber(stock) .. "/" .. formatNumber(limit)
    stockText = fitText(stockText, UI.stockW)
    setText(centeredX(UI.stockX, UI.stockW, stockText), y, stockText, C.stock, C.panel)

    local ratioText = tostring(ore.take.amount or 0) .. " → " .. tostring(ore.give.amount or 0)
    ratioText = fitText(ratioText, UI.ratioW)
    setText(centeredX(UI.ratioX, UI.ratioW, ratioText), y, ratioText, C.ratio, C.panel)

    gpu.setBackground(C.bg)
    gpu.setForeground(C.border)
    gpu.set(1, y, "│")
    gpu.set(UI.sep1, y, "│")
    gpu.set(UI.sep2, y, "│")
    gpu.set(UI.sep3, y, "│")
    gpu.set(w, y, "│")
end

local function drawRows()
    drawBodyGrid()

    local rowsToDraw = math.min(#ore_list, UI.visibleRows)
    for i = 1, rowsToDraw do
        drawOreRow(ore_list[i], i)
    end

    if #ore_list > UI.visibleRows and UI.visibleRows > 0 then
        local hidden = #ore_list - UI.visibleRows + 1
        local y = UI.statusSeparatorY - 1
        gpu.setBackground(C.panel)
        gpu.fill(2, y, w - 2, 1, " ")
        local text = "… ещё позиций: " .. tostring(hidden)
        setText(3, y, fitText(text, w - 6), C.gray, C.panel)

        gpu.setBackground(C.bg)
        gpu.setForeground(C.border)
        gpu.set(1, y, "│")
        gpu.set(UI.sep1, y, "│")
        gpu.set(UI.sep2, y, "│")
        gpu.set(UI.sep3, y, "│")
        gpu.set(w, y, "│")
    end
end

local function drawInterface()
    gpu.setBackground(C.bg)
    gpu.setForeground(C.white)
    gpu.fill(1, 1, w, h, " ")

    drawTopBorder()
    drawHeader()
    drawHeaderSeparator()
    drawRows()
    drawStatusSeparator()
    drawStatus()
    drawBottomBorder()
end

-- Совместимая замена старой функции обновления общего счёта.
local function drawTotalLine()
    drawHeader()
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
        drawHeader()
        drawRows()
        drawStatusSeparator()
        drawStatus()
        drawBottomBorder()
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
            drawInfo("ingots")
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

    drawInfo("ingots")
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

    if eventName == "interrupted" then
        gpu.setBackground(defBG)
        gpu.setForeground(defFG)
        gpu.fill(1, 1, w, h, " ")
        os.exit()
        return true
    end

    if eventName == "player_on" then
        if not updInfo("ingots") then return end

        stats.ores = 0
        stats.ingots = 0

        setStatus(
            string.format("Игрок %s на PIM. Начинаю проверку руды.", tostring(args[1] or "")),
            C.green,
            C.green
        )
        checkInventory()
        return
    end

    if eventName == "player_off" then
        if not updInfo("ingots") then return end
        setStatus("Система активна. Ожидаю игрока на PIM.", C.white, C.green)
        return
    end

    -- Скрытая админ-зона осталась в правой части строки состояния.
    if eventName == "touch"
        and args[2] >= w - 38
        and args[3] >= h - 1
        and isAdmin(args[5]) then
        scanExchangeConfiguration()
    end
end

-- ============================================================
-- ЗАПУСК
-- ============================================================
local function main()
    drawInterface()

    if updInfo("full") then
        setStatus("Система активна. Ожидаю игрока на PIM.", C.white, C.green)
    end

    while true do
        handleEvent(event.pull(1))
    end
end

while true do
    local success, err = pcall(main)

    if not success then
        local errorText = tostring(err or "Неизвестная ошибка")
        local errorFile = io.open(currDir .. "/exchanger_errors.txt", "ab")
        if errorFile then
            errorFile:write(errorText .. "\n")
            errorFile:close()
        end

        computer.beep(2000, 3)
    else
        break
    end
end
