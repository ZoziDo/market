-- ============================================
-- КОНФИГУРАЦИЯ11
-- ============================================
local component = require("component")
local event = require("event")
local gpu = component.gpu
local unicode = require("unicode")
local serialization = require("serialization")
local keyboard = require("keyboard")
local computer = require("computer")
local fs = require("filesystem")
local shell = require("shell")

-- ============================================
-- ЦВЕТА
-- ============================================
local colors = {
    bg_main = 0x0A0A0F,
    bg_secondary = 0x14141F,
    bg_button = 0x1F1F2E,
    accent_main = 0x8B5CF6,
    accent_secondary = 0x00E5C9,
    text_main = 0xD0D0E0,
    text_bright = 0xF0F0FF,
    success = 0x00FFAA,
    error = 0xFF4D7A,
    inactive = 0x555566,
    star_glow = 0xC8C8FF,
    black_fon = 0x000000,
    tomato = 0xFF6347,
    white = 0xFFFFFF
}

-- ============================================
-- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
-- ============================================
local function clear()
    gpu.setBackground(colors.bg_main)
    gpu.fill(1, 1, 80, 25, " ")
end

local function drawCenteredText(y, text, color)
    gpu.setForeground(color or colors.text_main)
    local x = math.floor((80 - unicode.len(text)) / 2) + 1 + 1
    gpu.set(x, y, text)
end

local function drawButton(btn)
    gpu.setBackground(btn.bg)
    gpu.fill(btn.x, btn.y, btn.xs, btn.ys, " ")
    gpu.setForeground(btn.fg)
    local textX = btn.x + math.floor((btn.xs - unicode.len(btn.text)) / 2)
    local textY = btn.y + math.floor((btn.ys - 1) / 2)
    gpu.set(textX, textY, btn.text)
    gpu.setBackground(colors.bg_main)
end

local function drawFlexButton(btn)
    gpu.setBackground(btn.bg)
    gpu.fill(btn.x, btn.y, btn.xs, btn.ys, " ")
    gpu.setForeground(btn.fg)
    local textX = btn.x + math.floor((btn.xs - unicode.len(btn.text)) / 2)
    local textY = btn.y + math.floor((btn.ys - 1) / 2)
    gpu.set(textX, textY, btn.text)
    gpu.setBackground(colors.bg_main)
end

local function drawPopupBorder(x, y, w, h, color)
    gpu.setForeground(color or colors.accent_secondary)
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

local function drawScreenBorder()
    local left = 1
    local right = 80
    local top = 1
    local bottom = 24
    gpu.setForeground(colors.accent_secondary)
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

local function sortableName(name)
    if not name then return "" end
    local lower = string.lower(name)
    local result = lower:gsub("(%d+)", function(d)
        return string.format("%08d", tonumber(d))
    end)
    return result
end

local function safeDoFile(path)
    if not fs.exists(path) then
        return {}
    end
    local ok, result = pcall(dofile, path)
    if not ok then
        print("Ошибка загрузки файла " .. path .. ": " .. tostring(result))
        return {}
    end
    return result
end

local function isButtonClicked(btn, x, y)
    return y >= btn.y and y < btn.y + btn.ys and x >= btn.x and x < btn.x + btn.xs
end

local function normalizeName(name)
    if not name then return "" end
    local lastColon = name:match(".*:([^:]+)$")
    return lastColon or name
end

local function namesMatch(name1, name2)
    if not name1 or not name2 then return false end
    if name1 == name2 then return true end
    local short1 = normalizeName(name1)
    local short2 = normalizeName(name2)
    return short1 == short2
end

-- ============================================
-- ЗАГРУЗКА ДАННЫХ МАГАЗИНА
-- ============================================
local shopData = safeDoFile("/home/shop_items.lua")
local sellItems = shopData.sellItems or {}
local vanillaItems = shopData.vanillaItems or {}

local buyItemsData = safeDoFile("/home/buy_items.lua")
local buyItemMap = {}
for _, item in ipairs(buyItemsData) do
    local dmg = item.damage or 0
    local key = item.internalName .. ":" .. dmg
    buyItemMap[key] = item
end

local drawAgreementScreen = safeDoFile("/home/agreement.lua")

-- ============================================
-- СИСТЕМА ДАННЫХ ИГРОКА (локальная)
-- ============================================
local playerData = {
    name = nil,
    balanceCoin = 0,
    balanceEma = 0,
    transactions = 0,
    regDate = "",
    agreed = false
}

-- ============================================
-- PIM МЕНЕДЖЕР
-- ============================================
local PimManager = {}
PimManager.__index = PimManager

function PimManager.new()
    local self = setmetatable({}, PimManager)
    self.pim = nil
    self.hasPlayer = false
    self.debounceTime = 0.7
    self.monitorRunning = false
    
    for addr in component.list("pim") do
        self.pim = component.proxy(addr)
        break
    end
    
    return self
end

function PimManager:hasPlayerOnPlate()
    if not self.pim then return false end
    local ok, size = pcall(self.pim.getInventorySize, self.pim)
    if not ok then return false end
    return size > 0
end

function PimManager:startMonitoring()
    if self.monitorRunning then return end
    self.monitorRunning = true
    
    -- Первая проверка
    self.hasPlayer = self:hasPlayerOnPlate()
    
    event.timer(0.1, function()
        self:monitorLoop()
    end, math.huge)
end

function PimManager:monitorLoop()
    if not self.monitorRunning then return end
    
    local currentState = self:hasPlayerOnPlate()
    
    if currentState ~= self.hasPlayer then
        if currentState then
            -- Игрок появился
            self.hasPlayer = true
            event.signal("pim_occupied")
        else
            -- Игрок исчез - антидребезг
            os.sleep(self.debounceTime)
            -- Двойная проверка
            if not self:hasPlayerOnPlate() then
                self.hasPlayer = false
                event.signal("pim_free")
            end
        end
    end
    
    -- Продолжаем мониторинг
    event.timer(0.1, function()
        self:monitorLoop()
    end)
end

local pimManager = PimManager.new()

-- ============================================
-- СЕССИЯ ИГРОКА
-- ============================================
local session = {
    active = false,
    playerName = nil,
    isAuthorized = false
}

local function createSession(playerName)
    session.active = true
    session.playerName = playerName or "Игрок"
    session.isAuthorized = true -- Авторизация всегда успешна
    return true
end

local function destroySession()
    session.active = false
    session.playerName = nil
    session.isAuthorized = false
    
    -- Очищаем все временные данные
    selectedItem = nil
    hoveredIndex = 0
    selectedIndex = 0
    purchaseItem = nil
    purchaseQuantity = 1
    sellConfirmItem = nil
    foundAmount = 0
    showSellPopup = false
    showPartialPopup = false
    showInsufficientPopup = false
    showInventoryFullPopup = false
    shopSearch = ""
    searchActive = false
    searchInput = ""
    listScroll = 1
    filteredItems = {}
    feedbacks = {}
    feedbacksPage = 1
    feedbackInput = ""
    feedbackEditMode = false
    playerHasFeedback = false
    reportInput = ""
    tempMessage = ""
    
    return true
end

-- ============================================
-- РАБОТА С ИНВЕНТАРЕМ
-- ============================================
local function getPimAddr()
    for addr in component.list("pim") do
        return addr
    end
    return nil
end

local PUSH_DIRECTION = "down"
local PULL_DIRECTION = "up"

local function getActualItemQuantity(internalName, damage)
    if not component.isAvailable("me_interface") then return 0 end
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

local function scanPlayerInventory(targetName, targetDamage)
    local pimAddr = getPimAddr()
    if not pimAddr then return 0 end
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
    return total
end

local function extractToME(targetName, amount, targetDamage)
    local pimAddr = getPimAddr()
    if not pimAddr or amount <= 0 then return 0 end
    targetDamage = targetDamage or 0
    local extracted = 0
    for slot = 1, 36 do
        if extracted >= amount then break end
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
    return extracted
end

-- ============================================
-- ЛОГИКА МАГАЗИНА
-- ============================================
local blacklist = {
    ["customnpcs:npcMoney"] = true,
}

local shopItems = {}
local shopSearch = ""
local searchActive = false
local searchInput = ""
local currentShopMode = "buy"
local listScroll = 1
local visibleRows = 15
local selectedIndex = 0
local hoveredIndex = 0
local filteredItems = {}
local selectedItem = nil
local horizontalScroll = 1
local maxItemWidth = 0
local purchaseQuantity = 1
local purchaseItem = nil
local sellConfirmItem = nil
local foundAmount = 0
local showSellPopup = false

local showPartialPopup = false
local partialExtracted = 0
local partialRequested = 0
local partialRefundCoin = 0
local partialRefundEma = 0
local partialItem = nil

local showInsufficientPopup = false
local insufficientBalanceCoin = 0
local insufficientBalanceEma = 0

local showInventoryFullPopup = false

local feedbacks = {}
local feedbacksPage = 1
local feedbacksTotalPages = 1
local feedbackInput = ""
local feedbackEditMode = false
local playerHasFeedback = false

local reportInput = ""
local lastReportTime = nil

local tempMessage = ""
local tempMessageTimer = nil

local currentScreen = "idle"

local selector = nil
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

local function updateSelectorDisplay(item)
    if not selector then return end
    if not item then
        pcall(selector.setSlot, 0, nil)
        pcall(selector.setSlot, 1, nil)
        return
    end
    local raw = item.internalName or item.name or item.displayName
    if not raw then return end
    local id = raw
    if not id:find(":") then
        id = "minecraft:" .. id
    end
    local dmg = item.damage or 0
    local stack = { id = id, dmg = dmg }
    pcall(selector.setSlot, 0, stack)
    pcall(selector.setSlot, 1, stack)
end

-- ============================================
-- ЗАГРУЗКА ПРЕДМЕТОВ
-- ============================================
local function loadBuyItems()
    if not component.isAvailable("me_interface") then return end
    local me = component.me_interface
    local rawItems = me.getItemsInNetwork()
    local tempShopItems = {}
    
    for _, meItem in ipairs(rawItems) do
        local name = meItem.name
        if blacklist[name] then goto continue end
        local qty = meItem.size or 0
        if qty == 0 then goto continue end

        local damage = meItem.damage or 0
        local mapKey = name .. ":" .. damage
        local mapping = buyItemMap[mapKey]
        if not mapping then goto continue end

        local displayName = mapping.displayName
        local priceCoin = mapping.price_coin or mapping.price or 0
        local priceEma = mapping.price_ema or 0
        if priceCoin <= 0 and priceEma <= 0 then goto continue end

        local key = name .. ":" .. damage
        if tempShopItems[key] then
            tempShopItems[key].qty = tempShopItems[key].qty + qty
        else
            tempShopItems[key] = {
                internalName = name,
                displayName = displayName,
                qty = qty,
                priceCoin = priceCoin,
                priceEma = priceEma,
                damage = damage,
                canBuy = true
            }
        end
        ::continue::
    end

    shopItems = {}
    for key, itemData in pairs(tempShopItems) do
        table.insert(shopItems, itemData)
    end

    table.sort(shopItems, function(a, b)
        return sortableName(a.displayName) < sortableName(b.displayName)
    end)
end

local function loadSellItems()
    shopItems = {}
    for _, item in ipairs(sellItems) do
        local internal = item.internalName or item.name
        if internal then
            table.insert(shopItems, {
                displayName = item.displayName or item.name or internal,
                internalName = internal,
                qty = item.qty or 0,
                price = item.price or 0,
                damage = item.damage or 0
            })
        end
    end
end

-- ============================================
-- UI ФУНКЦИИ
-- ============================================
local function drawTempMessage()
    if tempMessage ~= "" then
        gpu.setBackground(colors.bg_main)
        gpu.fill(1, 25, 80, 1, " ")
        gpu.setForeground(colors.success)
        local x = math.floor((80 - unicode.len(tempMessage)) / 2) + 1
        gpu.set(x, 25, tempMessage)
    else
        gpu.setBackground(colors.bg_main)
        gpu.fill(1, 25, 80, 1, " ")
    end
end

local function showTempMessage(msg, duration)
    tempMessage = msg
    if tempMessageTimer then
        event.cancel(tempMessageTimer)
    end
    tempMessageTimer = event.timer(duration or 2, function()
        tempMessage = ""
        tempMessageTimer = nil
        refreshCurrentScreen()
    end)
    drawTempMessage()
end

local function drawBigTitle()
    gpu.setForeground(colors.accent_secondary)
    local darkonLines = {
        "  ██╗   ██╗██╗██████╗ ",
        "  ██║   ██║██║██╔══██╗",
        "  ██║   ██║██║██████╔╝",
        "  ╚██╗ ██╔╝██║██╔═══╝",
        "   ╚████╔╝ ██║██║",
        "    ╚═══╝  ╚═╝╚═╝",
    }
    local darkonOffset = 18
    local darkonX = math.floor((80 - #darkonLines[1]) / 2) + darkonOffset
    for i, line in ipairs(darkonLines) do
        gpu.set(darkonX, 4 + i, line)
    end

    local shopLines = {
        "  ███████╗██╗  ██╗ ██████╗ ██████╗ ",
        "  ██╔════╝██║  ██║██╔═══██╗██╔══██╗",
        "  ███████╗███████║██║   ██║██████╔╝",
        "  ╚════██║██╔══██║██║   ██║██╔═══╝ ",
        "  ███████║██║  ██║╚██████╔╝██║     ",
        "  ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝     "
    }
    local shopOffset = 29
    local shopX = math.floor((80 - #shopLines[1]) / 2) + shopOffset
    for i, line in ipairs(shopLines) do
        gpu.set(shopX, 10 + i, line)
    end
end

local function drawIdleScreen()
    clear()
    drawScreenBorder()
    drawBigTitle()
    gpu.setForeground(colors.success)
    drawCenteredText(18, "↓   Встаньте на PIM   ↓", colors.accent_main)
    drawCenteredText(19, "━━━━━━━━━━━━━━━━━━━", colors.accent_main)
    gpu.setForeground(colors.text_main)
    drawCenteredText(22, "--===============|VIP SHOP|===============--", colors.text_main)
    drawTempMessage()
end

local function drawBalanceLine(x, y)
    gpu.setForeground(colors.white)
    gpu.set(x, y, "Баланс: ")
    local coinStr = string.format("%.2f", playerData.balanceCoin) .. " Coina ₵"
    gpu.setForeground(colors.accent_main)
    gpu.set(x + unicode.len("Баланс: "), y, coinStr)
    gpu.setForeground(colors.white)
    gpu.set(x + unicode.len("Баланс: ") + unicode.len(coinStr), y, " | ")
    local emaStr = "ЭМЫ: " .. string.format("%.2f", playerData.balanceEma) .. " ۞"
    gpu.setForeground(colors.tomato)
    gpu.set(x + unicode.len("Баланс: ") + unicode.len(coinStr) + unicode.len(" | "), y, emaStr)
end

local function drawMainMenu()
    clear()
    drawScreenBorder()
    
    if not session.active or not session.isAuthorized then
        drawIdleScreen()
        return
    end
    
    local hello1 = "Добро пожаловать, "
    local hello2 = session.playerName .. "!"
    local full1 = hello1 .. hello2
    local x1 = math.floor((80 - unicode.len(full1))/2) + 2
    gpu.setForeground(colors.success)
    gpu.set(x1, 4, hello1)
    gpu.setForeground(colors.text_bright)
    gpu.set(x1 + unicode.len(hello1), 4, hello2)

    local balanceText = "Баланс: " .. string.format("%.2f", playerData.balanceCoin) .. " Coina ₵"
    gpu.setForeground(colors.white)
    local balanceX = math.floor((80 - unicode.len(balanceText .. " | ЭМЫ: " .. string.format("%.2f", playerData.balanceEma) .. " ۞")) / 2) + 1
    gpu.set(balanceX, 5, "Баланс: ")
    gpu.setForeground(colors.accent_main)
    gpu.set(balanceX + unicode.len("Баланс: "), 5, string.format("%.2f", playerData.balanceCoin) .. " Coina ₵")
    gpu.setForeground(colors.white)
    gpu.set(balanceX + unicode.len("Баланс: ") + unicode.len(string.format("%.2f", playerData.balanceCoin) .. " Coina ₵"), 5, " | ")
    gpu.setForeground(colors.tomato)
    gpu.set(balanceX + unicode.len("Баланс: ") + unicode.len(string.format("%.2f", playerData.balanceCoin) .. " Coina ₵") + unicode.len(" | "), 5, "ЭМЫ: " .. string.format("%.2f", playerData.balanceEma) .. " ۞")

    if not playerData.agreed then
        gpu.setForeground(colors.accent_secondary)
        drawCenteredText(7, "⚠️ Вы не приняли пользовательское соглашение! Нажмите [Соглашение]", colors.accent_secondary)
    end

    local menuButtons = {
        shop = {x=32, xs=20, y=10, ys=3, text="🛒 Магазин", tx=6, ty=1, bg=colors.bg_button, fg=colors.accent_main},
        account = {x=32, xs=20, y=16, ys=3, text="👤 Аккаунт", tx=6, ty=1, bg=colors.bg_button, fg=colors.accent_main}
    }
    
    for _, btn in pairs(menuButtons) do
        drawButton(btn)
    end
    
    -- Нижняя панель
    gpu.setForeground(colors.error)
    gpu.set(4, 24, "[ ПОДДЕРЖКА ]")
    gpu.set(35, 24, "[ СОГЛАШЕНИЕ ]")
    gpu.set(68, 24, "[ ОТЗЫВЫ ]")
    
    drawTempMessage()
end

local function drawShopMenu()
    clear()
    drawScreenBorder()
    drawCenteredText(6, "МАГАЗИН", colors.accent_secondary)
    
    if not playerData.agreed then
        drawCenteredText(9, "Доступ запрещён.", colors.error)
        drawCenteredText(10, "Примите соглашение, нажав [Соглашение] в главном меню.", colors.accent_main)
        
        local backBtn = {x=37, y=24, xs=12, ys=1, text="[ НАЗАД ]", bg=colors.bg_button, fg=colors.accent_secondary}
        drawFlexButton(backBtn)
        drawTempMessage()
        return
    end
    
    local shopMenuButtons = {
        buy = {x=32, xs=20, y=9, ys=3, text="🛍 Покупка", tx=6, ty=1, bg=colors.bg_button, fg=colors.accent_main},
        sell = {x=32, xs=20, y=17, ys=3, text="💰 Пополнение", tx=5, ty=1, bg=colors.bg_button, fg=colors.accent_main}
    }
    
    for _, btn in pairs(shopMenuButtons) do
        drawButton(btn)
    end
    
    local backBtn = {x=37, y=24, xs=12, ys=1, text="[ НАЗАД ]", bg=colors.bg_button, fg=colors.accent_secondary}
    drawFlexButton(backBtn)
    drawTempMessage()
end

local function getFilteredItems()
    local filtered = {}
    local searchLower = string.lower(shopSearch)
    local searchWords = {}
    if searchLower ~= "" then
        for word in searchLower:gmatch("%S+") do
            table.insert(searchWords, word)
        end
    end

    for _, item in ipairs(shopItems) do
        local nameLower = string.lower(item.displayName or item.internalName)
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
    end

    table.sort(filtered, function(a, b)
        return sortableName(a.displayName) < sortableName(b.displayName)
    end)

    maxItemWidth = 0
    for _, item in ipairs(filtered) do
        local len = unicode.len(item.displayName or item.internalName or "")
        if len > maxItemWidth then maxItemWidth = len end
    end
    return filtered
end

local function drawBuyStatic()
    clear()
    drawScreenBorder()
    drawBalanceLine(3, 1)

    if currentShopMode == "buy" then
        gpu.setForeground(colors.accent_secondary)
        gpu.set(3, 3, "Магазин продаёт")
    else
        gpu.setForeground(colors.accent_secondary)
        gpu.set(3, 3, "Магазин покупает")
    end

    -- Поле поиска
    local searchX = 42
    local searchText = ""
    if searchActive then
        searchText = searchInput .. "_"
    else
        searchText = (shopSearch == "" and "Поиск..." or shopSearch)
    end
    gpu.setBackground(colors.bg_button)
    gpu.fill(searchX, 3, 23, 1, " ")
    gpu.setForeground(colors.accent_main)
    gpu.set(searchX + 1, 3, unicode.sub(searchText, 1, 21))

    local clearText = "[ СТЕРЕТЬ ]"
    local clearWidth = unicode.len(clearText) + 2
    local clearX = searchX + 23 + 1
    gpu.setBackground(colors.error)
    gpu.fill(clearX, 3, clearWidth, 1, " ")
    gpu.setForeground(colors.accent_secondary)
    local textX = clearX + math.floor((clearWidth - unicode.len(clearText)) / 2)
    gpu.set(textX, 3, clearText)
    gpu.setBackground(colors.accent_secondary)

    gpu.setBackground(colors.bg_button)
    gpu.fill(2, 5, 76, 1, " ")
    gpu.setForeground(colors.text_bright)
    gpu.set(3, 5, "Название")
    gpu.set(42, 5, "Кол-во")
    if currentShopMode == "buy" then
        gpu.set(55, 5, "Coina")
        gpu.set(67, 5, "ЭМЫ")
    else
        gpu.set(65, 5, "Цена")
    end
    gpu.setBackground(colors.bg_main)

    drawTempMessage()
end

local function drawSingleRow(y, item, isHovered, isSelected, itemIndex)
    if not item then return end
    local bg, fg
    if currentShopMode == "buy" and item.qty == 0 then
        bg = colors.bg_secondary
        fg = colors.inactive
    elseif isSelected then
        bg = 0x225577
    elseif isHovered then
        bg = 0x446688
    elseif itemIndex % 2 == 1 then
        bg = colors.bg_secondary
    else
        bg = 0x1a1a1a
    end
    if currentShopMode == "buy" then
        if item.qty > 0 then
            fg = colors.accent_main
        else
            fg = colors.inactive
        end
    else
        fg = colors.accent_main
    end
    gpu.setBackground(bg)
    gpu.fill(2, y, 76, 1, " ")
    gpu.setForeground(fg)
    local name = item.displayName or item.internalName
    if unicode.len(name) > 37 then
        name = unicode.sub(name, horizontalScroll, horizontalScroll + 36)
    end
    gpu.set(3, y, name)
    if currentShopMode == "buy" then
        if item.qty > 0 then
            gpu.setForeground(colors.text_bright)
        else
            gpu.setForeground(colors.inactive)
        end
    else
        gpu.setForeground(colors.text_bright)
    end
    gpu.set(42, y, tostring(item.qty))

    if currentShopMode == "sell" then
        if item.internalName == "customnpcs:npcMoney" then
            gpu.setForeground(colors.tomato)
            local priceStr = string.format("%.2f", item.price) .. " ۞"
            gpu.set(65, y, priceStr)
        else
            gpu.setForeground(colors.text_bright)
            local priceStr = string.format("%.2f", item.price) .. " ₵"
            gpu.set(65, y, priceStr)
        end
    else
        if item.priceCoin and item.priceCoin > 0 then
            gpu.setForeground(colors.accent_main)
            local coinStr = string.format("%.2f", item.priceCoin)
            gpu.set(55, y, coinStr)
        else
            gpu.setForeground(colors.inactive)
            gpu.set(55, y, "0")
        end
        if item.priceEma and item.priceEma > 0 then
            gpu.setForeground(colors.tomato)
            local emaStr = string.format("%.2f", item.priceEma)
            gpu.set(67, y, emaStr)
        else
            gpu.setForeground(colors.inactive)
            gpu.set(67, y, "0")
        end
    end
    gpu.setBackground(colors.bg_main)
end

local function drawScrollBar()
    local total = #filteredItems
    local barX = 78
    local barY = 7
    local barHeight = 15
    gpu.setBackground(colors.bg_main)
    gpu.fill(barX, barY, 2, barHeight, " ")
    if total <= visibleRows then return end
    gpu.setBackground(colors.bg_secondary)
    gpu.fill(barX, barY, 2, barHeight, " ")
    local thumbHeight = math.max(2, math.floor(barHeight * visibleRows / total))
    local maxPos = barHeight - thumbHeight
    local thumbPos = math.floor((listScroll - 1) * maxPos / (total - visibleRows)) + 1
    thumbPos = math.min(thumbPos, maxPos + 1)
    gpu.setBackground(colors.accent_main)
    gpu.fill(barX, barY + thumbPos - 1, 2, thumbHeight, " ")
    gpu.setBackground(colors.bg_main)
end

local function drawBuyItemsList()
    filteredItems = getFilteredItems()
    local maxScroll = math.max(1, #filteredItems - visibleRows + 1)
    listScroll = math.max(1, math.min(listScroll, maxScroll))

    gpu.setBackground(colors.bg_main)
    gpu.fill(2, 7, 78, visibleRows, " ")

    if #filteredItems == 0 then
        local msg = "ПО ТВОЕМУ ЗАПРОСУ, НИЧЕГО НЕ НАЙДЕНО!"
        local msgX = math.floor((80 - unicode.len(msg)) / 2) + 1
        local msgY = 14
        gpu.setForeground(colors.error)
        gpu.set(msgX, msgY, msg)
    else
        for i = 1, visibleRows do
            local itemIndex = listScroll + i - 1
            local item = filteredItems[itemIndex]
            if not item then break end
            local y = 6 + i            local isSelected = (itemIndex == selectedIndex)
            local isHovered = (itemIndex == hoveredIndex)
            drawSingleRow(y, item, isHovered, isSelected, itemIndex)
        end
    end

    drawScrollBar()
    if selectedItem then
        updateSelectorDisplay(selectedItem)
    end
end

local function drawBuyButtons()
    local backBtn = {x=37, y=24, xs=12, ys=1, text="[ НАЗАД ]", bg=colors.bg_button, fg=colors.accent_secondary}
    local nextBtn
    
    if currentShopMode == "buy" then
        nextBtn = {x=59, y=24, xs=13, ys=1, text="[ КУПИТЬ ]", bg=colors.bg_button, fg=colors.inactive}
    else
        nextBtn = {x=59, y=24, xs=14, ys=1, text="[ ПРОДАТЬ ]", bg=colors.bg_button, fg=colors.inactive}
    end

    if selectedItem and (currentShopMode ~= "buy" or selectedItem.qty > 0) then
        nextBtn.fg = colors.accent_secondary
    end

    drawFlexButton(backBtn)
    drawFlexButton(nextBtn)
    drawTempMessage()
end

local function drawAccountScreen()
    clear()
    drawScreenBorder()
    
    drawCenteredText(10, session.playerName .. ":", colors.text_bright)
    
    local balanceText = "Баланс: " .. string.format("%.2f", playerData.balanceCoin) .. " Coina ₵"
    gpu.setForeground(colors.white)
    local balanceX = math.floor((80 - unicode.len(balanceText .. " | ЭМЫ: " .. string.format("%.2f", playerData.balanceEma) .. " ۞")) / 2) + 1
    gpu.set(balanceX, 12, "Баланс: ")
    gpu.setForeground(colors.accent_main)
    gpu.set(balanceX + unicode.len("Баланс: "), 12, string.format("%.2f", playerData.balanceCoin) .. " Coina ₵")
    gpu.setForeground(colors.white)
    gpu.set(balanceX + unicode.len("Баланс: ") + unicode.len(string.format("%.2f", playerData.balanceCoin) .. " Coina ₵"), 12, " | ")
    gpu.setForeground(colors.tomato)
    gpu.set(balanceX + unicode.len("Баланс: ") + unicode.len(string.format("%.2f", playerData.balanceCoin) .. " Coina ₵") + unicode.len(" | "), 12, "ЭМЫ: " .. string.format("%.2f", playerData.balanceEma) .. " ۞")

    local transLabel = "Совершенно транзакций: "
    local transCount = tostring(playerData.transactions)
    local fullTrans = transLabel .. transCount
    local transX = math.floor((80 - unicode.len(fullTrans)) / 2) + 1
    gpu.setForeground(colors.success)
    gpu.set(transX, 13, transLabel)
    gpu.setForeground(colors.text_bright)
    gpu.set(transX + unicode.len(transLabel), 13, transCount)

    local regLabel = "Регистрация: "
    local regDate = playerData.regDate or "Неизвестно"
    local fullReg = regLabel .. regDate
    local regX = math.floor((80 - unicode.len(fullReg)) / 2) + 1
    gpu.setForeground(colors.success)
    gpu.set(regX, 14, regLabel)
    gpu.setForeground(colors.text_bright)
    gpu.set(regX + unicode.len(regLabel), 14, regDate)

    local agreeLabel = "Соглашение: "
    local agreeStatus = playerData.agreed and "ознакомлен" or "не ознакомлен"
    local agreeColor = playerData.agreed and colors.text_bright or colors.error
    local fullAgree = agreeLabel .. agreeStatus
    local agreeX = math.floor((80 - unicode.len(fullAgree)) / 2) + 1
    gpu.setForeground(colors.success)
    gpu.set(agreeX, 15, agreeLabel)
    gpu.setForeground(agreeColor)
    gpu.set(agreeX + unicode.len(agreeLabel), 15, agreeStatus)

    local backBtn = {x=37, y=24, xs=12, ys=1, text="[ НАЗАД ]", bg=colors.bg_button, fg=colors.accent_secondary}
    drawFlexButton(backBtn)
    drawTempMessage()
end

local function drawFeedbacksList()
    clear()
    drawScreenBorder()

    local line = string.rep("═", 15)
    local title = " ОТЗЫВЫ "
    local line2 = string.rep("═", 15)
    local fullStr = line .. title .. line2
    local x = math.floor((80 - unicode.len(fullStr)) / 2) + 1 + 1
    gpu.setForeground(colors.accent_main)
    gpu.set(x, 2, line)
    gpu.setForeground(colors.text_bright)
    gpu.set(x + unicode.len(line), 2, title)
    gpu.setForeground(colors.accent_main)
    gpu.set(x + unicode.len(line) + unicode.len(title), 2, line2)

    if #feedbacks == 0 then
        drawCenteredText(10, "Пока нет ни одного отзыва.", colors.text_main)
        drawCenteredText(11, "Будьте первым, кто оставит отзыв!", colors.accent_main)
        if not playerHasFeedback then
            drawCenteredText(12, "Нажмите [ДОБАВИТЬ] чтобы оставить отзыв", colors.text_main)
        end
    else
        local startIdx = (feedbacksPage - 1) * 3 + 1
        local endIdx = math.min(startIdx + 2, #feedbacks)
        local y = 5

        for i = startIdx, endIdx do
            local fb = feedbacks[i]
            if fb then
                gpu.setForeground(colors.accent_secondary)
                gpu.fill(5, y, 70, 3, " ")
                gpu.setBackground(colors.bg_secondary)
                gpu.fill(6, y+1, 68, 1, " ")

                gpu.setForeground(colors.accent_main)
                gpu.set(7, y+1, fb.name)
                gpu.setForeground(colors.inactive)
                local timeStr = fb.time or ""
                gpu.set(7 + unicode.len(fb.name) + 2, y+1, timeStr)

                gpu.setForeground(colors.text_bright)
                local shortText = unicode.sub(fb.text, 1, 62)
                gpu.set(7, y+2, shortText)

                y = y + 4
            end
        end

        feedbacksTotalPages = math.max(1, math.ceil(#feedbacks / 3))
        local pageInfo = "Страница " .. feedbacksPage .. " из " .. feedbacksTotalPages
        local x = math.floor((80 - unicode.len(pageInfo)) / 2) + 1 + 1
        x = x + 1
        gpu.setForeground(colors.text_main)
        gpu.set(x, 22, pageInfo)
    end

    local backBtn = {x=5, y=24, xs=11, ys=1, text="[ НАЗАД ]", bg=colors.bg_button, fg=colors.accent_secondary}
    local addBtn = {x=36, y=24, xs=14, ys=1, text="[ ДОБАВИТЬ ]", bg=colors.bg_button, fg=colors.success}
    local prevBtn = {x=59, y=24, xs=7, ys=1, text="[ < ]", bg=colors.bg_button, fg=colors.accent_main}
    local nextBtn = {x=69, y=24, xs=7, ys=1, text="[ > ]", bg=colors.bg_button, fg=colors.accent_main}

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

local function drawFeedbackInputScreen()
    if playerHasFeedback then
        showTempMessage("Вы уже оставляли отзыв!", 2)
        currentScreen = "menu"
        drawMainMenu()
        return
    end
    currentScreen = "feedback_input"
    clear()
    drawScreenBorder()
    drawCenteredText(4, "ОСТАВИТЬ ОТЗЫВ", colors.accent_secondary)

    gpu.setForeground(colors.text_main)
    drawCenteredText(7, "Ваше имя: " .. session.playerName, colors.accent_main)
    drawCenteredText(9, "Оставьте свой отзыв о магазине:", colors.text_main)
    drawCenteredText(10, "Ваше мнение поможет нам стать лучше!", colors.inactive)

    gpu.setBackground(colors.black_fon)
    gpu.fill(10, 12, 60, 3, " ")
    gpu.setForeground(colors.text_bright)
    if feedbackEditMode then
        if feedbackInput ~= "" then
            gpu.set(11, 13, unicode.sub(feedbackInput, -58) .. "_")
        else
            gpu.setForeground(colors.inactive)
            gpu.set(11, 13, "Введите ваш отзыв..._")
        end
    else
        if feedbackInput ~= "" then
            gpu.set(11, 13, unicode.sub(feedbackInput, -58))
        else
            gpu.setForeground(colors.inactive)
            gpu.set(11, 13, "Введите ваш отзыв...")
        end
    end

    local cancelBtn = {x=20, y=24, xs=12, ys=1, text="[ ОТМЕНА ]", bg=colors.bg_button, fg=colors.error}
    local sendBtn = {x=46, y=24, xs=15, ys=1, text="[ ОТПРАВИТЬ ]", bg=colors.bg_button, fg=colors.success}

    drawFlexButton(cancelBtn)
    drawFlexButton(sendBtn)
    drawTempMessage()
end

local function drawReportScreen()
    currentScreen = "report"
    clear()
    drawScreenBorder()
    drawCenteredText(4, "РЕПОРТ", colors.accent_secondary)
    gpu.setForeground(colors.text_main)
    local help1 = "Опишите проблему: баг, предложение, жалоба."
    local helpX = math.floor((80 - unicode.len(help1)) / 2) + 1
    gpu.set(helpX, 7, help1)

    gpu.setBackground(colors.black_fon)
    gpu.fill(10, 9, 60, 3, " ")
    gpu.setForeground(colors.text_bright)
    if reportInput ~= "" then
        gpu.set(11, 10, unicode.sub(reportInput, -58))
    else
        gpu.setForeground(colors.inactive)
        gpu.set(11, 10, "Введите текст сообщения...")
    end
    gpu.setBackground(colors.bg_main)

    local sendBtn = {x=33, y=14, xs=17, ys=1, text="[ ОТПРАВИТЬ ]", bg=colors.bg_button, fg=colors.success}
    drawFlexButton(sendBtn)
    
    local backBtn = {x=37, y=24, xs=12, ys=1, text="[ НАЗАД ]", bg=colors.bg_button, fg=colors.accent_secondary}
    drawFlexButton(backBtn)
    drawTempMessage()
end

local function drawPurchaseScreen()
    currentScreen = "purchase"
    clear()
    drawScreenBorder()
    drawBalanceLine(3, 1)

    gpu.setForeground(colors.success)
    gpu.set(3, 3, "Имя предмета: ")
    gpu.setForeground(colors.text_bright)
    gpu.set(18, 3, purchaseItem.displayName)

    gpu.setForeground(colors.success)
    gpu.set(55, 3, "Доступно: ")
    gpu.setForeground(colors.text_bright)
    gpu.set(66, 3, tostring(purchaseItem.qty))

    local totalCoin = (purchaseItem.priceCoin or 0) * purchaseQuantity
    local totalEma = (purchaseItem.priceEma or 0) * purchaseQuantity

    gpu.setForeground(colors.success)
    gpu.set(3, 5, "На сумму: ")
    local sumY = 5
    if totalCoin > 0 then
        gpu.setForeground(colors.error)
        gpu.set(14, sumY, string.format("%.2f", totalCoin) .. " ₵")
        sumY = sumY + 1
    end
    if totalEma > 0 then
        gpu.setForeground(colors.tomato)
        gpu.set(14, sumY, string.format("%.2f", totalEma) .. " ۞")
    end

    gpu.setForeground(colors.success)
    gpu.set(55, 5, "Цена: ")
    local priceY = 5
    if purchaseItem.priceCoin and purchaseItem.priceCoin > 0 then
        gpu.setForeground(colors.accent_main)
        gpu.set(62, priceY, string.format("%.2f", purchaseItem.priceCoin) .. " ₵")
        priceY = priceY + 1
    end
    if purchaseItem.priceEma and purchaseItem.priceEma > 0 then
        gpu.setForeground(colors.tomato)
        gpu.set(62, priceY, string.format("%.2f", purchaseItem.priceEma) .. " ۞")
    end

    gpu.setForeground(colors.success)
    gpu.set(3, 7, "Кол-во: ")
    gpu.setForeground(colors.text_bright)
    gpu.set(12, 7, tostring(purchaseQuantity))

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
            gpu.setBackground(colors.bg_button)
            gpu.fill(x, y, btnW, btnH, " ")
            gpu.setForeground(colors.accent_main)
            local tx = x + math.floor((btnW - unicode.len(text)) / 2)
            local ty = y
            gpu.set(tx, ty, text)
        end
    end
    
    local backBtn = {x=19, y=24, xs=12, ys=1, text="[ НАЗАД ]", bg=colors.bg_button, fg=colors.accent_secondary}
    local buyBtn = {x=51, y=24, xs=13, ys=1, text="[ КУПИТЬ ]", bg=colors.bg_button, fg=colors.success}
    drawFlexButton(backBtn)
    drawFlexButton(buyBtn)
    drawTempMessage()
end

local function drawSellScanScreen()
    currentScreen = "sell_scan"
    clear()
    drawScreenBorder()
    drawBalanceLine(3, 1)

    gpu.setForeground(colors.success)
    gpu.set(3, 3, "Имя предмета: ")
    gpu.setForeground(colors.text_bright)
    gpu.set(18, 3, sellConfirmItem.displayName)

    gpu.setForeground(colors.success)
    gpu.set(55, 3, "Цена: ")
    if sellConfirmItem.internalName == "customnpcs:npcMoney" then
        gpu.setForeground(colors.tomato)
        gpu.set(62, 3, string.format("%.2f", sellConfirmItem.price) .. " ۞")
    else
        gpu.setForeground(colors.accent_main)
        gpu.set(62, 3, string.format("%.2f", sellConfirmItem.price) .. " ₵")
    end

    gpu.setForeground(colors.success)
    gpu.set(3, 5, "Можно продать: ")
    gpu.setForeground(colors.text_bright)
    gpu.set(18, 5, tostring(sellConfirmItem.qty))

    gpu.setForeground(colors.accent_secondary)
    local scanText = "Сканировать на наличие предмета:"
    local scanX = math.floor((80 - unicode.len(scanText)) / 2)
    gpu.set(scanX, 11, scanText)

    local allBtn = {x=30, y=13, xs=20, ys=1, text="Весь инвентарь", bg=colors.bg_button, fg=colors.success}
    drawFlexButton(allBtn)
    
    local backBtn = {x=37, y=24, xs=12, ys=1, text="[ НАЗАД ]", bg=colors.bg_button, fg=colors.accent_secondary}
    drawFlexButton(backBtn)

    if showSellPopup and sellConfirmItem then
        drawSellPopup()
    end
    drawTempMessage()
end

local function drawSellPopup()
    local popupWidth = 40
    local popupHeight = 10
    local popupX = math.floor((80 - popupWidth) / 2)
    local popupY = 10

    gpu.setBackground(colors.black_fon)
    gpu.fill(popupX, popupY+2, popupWidth, popupHeight-4, " ")
    gpu.fill(popupX+1, popupY+1, popupWidth-2, popupHeight-2, " ")

    drawPopupBorder(popupX, popupY, popupWidth, popupHeight, colors.accent_secondary)

    local name = sellConfirmItem.displayName
    local totalFound = foundAmount
    local value = totalFound * sellConfirmItem.price

    gpu.setForeground(colors.text_bright)
    gpu.set(popupX+14, popupY, "Подтверждение")

    gpu.setForeground(colors.success)
    gpu.set(popupX+3, popupY+3, "Магазин заберёт: ")
    gpu.setForeground(colors.text_bright)
    gpu.set(popupX+3 + unicode.len("Магазин заберёт: "), popupY+3, tostring(totalFound))

    gpu.setForeground(colors.success)
    gpu.set(popupX+3, popupY+4, name .. " x")
    gpu.setForeground(colors.text_bright)
    gpu.set(popupX+3 + unicode.len(name .. " x"), popupY+4, tostring(totalFound))

    gpu.setForeground(colors.success)
    gpu.set(popupX+3, popupY+5, "Вы получите: ")
    if sellConfirmItem.internalName == "customnpcs:npcMoney" then
        gpu.setForeground(colors.tomato)
        gpu.set(popupX+3 + unicode.len("Вы получите: "), popupY+5, string.format("%.2f", value) .. " ۞")
    else
        gpu.setForeground(colors.accent_main)
        gpu.set(popupX+3 + unicode.len("Вы получите: "), popupY+5, string.format("%.2f", value) .. " ₵")
    end

    local yesBtn = {x=popupX+5, y=popupY+7, xs=13, ys=1, text="[ Принять ]", bg=colors.bg_button, fg=colors.success}
    local noBtn = {x=popupX+popupWidth-16, y=popupY+7, xs=12, ys=1, text="[ Отмена ]", bg=colors.bg_button, fg=colors.error}
    drawFlexButton(yesBtn)
    drawFlexButton(noBtn)
    drawTempMessage()
end

local function drawInsufficientPopup()
    local popupWidth = 52
    local popupHeight = 11
    local popupX = math.floor((80 - popupWidth) / 2)
    local popupY = 7

    gpu.setBackground(colors.black_fon)
    gpu.fill(popupX, popupY, popupWidth, popupHeight, " ")
    gpu.fill(popupX+1, popupY+1, popupWidth-2, popupHeight-2, " ")
    drawPopupBorder(popupX, popupY, popupWidth, popupHeight, colors.error)

    gpu.setForeground(colors.error)
    local title = "НЕДОСТАТОЧНО СРЕДСТВ"
    local titleX = popupX + math.floor((popupWidth - unicode.len(title)) / 2)
    gpu.set(titleX, popupY, title)

    gpu.setForeground(colors.text_main)
    local line1a = "Пополни баланс, не можешь купить"
    local line1aX = popupX + math.floor((popupWidth - unicode.len(line1a)) / 2)
    gpu.set(line1aX, popupY+2, line1a)

    local line1b = "хотя бы 1 штуку предмета."
    local line1bX = popupX + math.floor((popupWidth - unicode.len(line1b)) / 2)
    gpu.set(line1bX, popupY+3, line1b)

    gpu.setForeground(colors.success)
    gpu.set(popupX+3, popupY+5, "Твой баланс Coin: ")
    gpu.setForeground(colors.accent_main)
    gpu.set(popupX+3 + unicode.len("Твой баланс Coin: "), popupY+5, string.format("%.2f", insufficientBalanceCoin) .. " ₵")
    if insufficientBalanceEma > 0 then
        gpu.setForeground(colors.success)
        gpu.set(popupX+3, popupY+6, "Твой баланс ЭМЫ: ")
        gpu.setForeground(colors.tomato)
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
        bg = colors.bg_button,
        fg = colors.success
    }
    drawFlexButton(okBtn)
    drawTempMessage()
end

local function drawPartialPopup()
    local popupWidth = 52
    local popupHeight = 9
    local popupX = math.floor((80 - popupWidth) / 2)
    local popupY = 9

    gpu.setBackground(colors.black_fon)
    gpu.fill(popupX, popupY, popupWidth, popupHeight, " ")
    gpu.fill(popupX+1, popupY+1, popupWidth-2, popupHeight-2, " ")
    drawPopupBorder(popupX, popupY, popupWidth, popupHeight, colors.error)

    gpu.setForeground(colors.error)
    local title = "НЕ ПОЛНАЯ ВЫДАЧА"
    local titleX = popupX + math.floor((popupWidth - unicode.len(title)) / 2)
    gpu.set(titleX, popupY, title)

    gpu.setForeground(colors.text_main)
    local line1 = "Не хватило места в инвентаре!"
    local line1X = popupX + math.floor((popupWidth - unicode.len(line1)) / 2)
    gpu.set(line1X, popupY+2, line1)

    local line2 = "Выдано " .. partialExtracted .. " из " .. partialRequested
    local line2X = popupX + math.floor((popupWidth - unicode.len(line2)) / 2)
    gpu.set(line2X, popupY+3, line2)

    local spentLabelCoin = "Списано Coin: "
    local spentValueCoin = string.format("%.2f", partialRefundCoin) .. " ₵"
    local fullSpentTextCoin = spentLabelCoin .. spentValueCoin
    local spentStartXCoin = popupX + math.floor((popupWidth - unicode.len(fullSpentTextCoin)) / 2)
    gpu.setForeground(colors.success)
    gpu.set(spentStartXCoin, popupY+4, spentLabelCoin)
    gpu.setForeground(colors.accent_main)
    gpu.set(spentStartXCoin + unicode.len(spentLabelCoin), popupY+4, spentValueCoin)

    if partialRefundEma > 0 then
        local spentLabelEma = "Списано ЭМЫ: "
        local spentValueEma = string.format("%.2f", partialRefundEma) .. " ۞"
        local fullSpentTextEma = spentLabelEma .. spentValueEma
        local spentStartXEma = popupX + math.floor((popupWidth - unicode.len(fullSpentTextEma)) / 2)
        gpu.setForeground(colors.success)
        gpu.set(spentStartXEma, popupY+5, spentLabelEma)
        gpu.setForeground(colors.tomato)
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
        bg = colors.bg_button,
        fg = colors.success
    }
    drawFlexButton(okBtn)
    drawTempMessage()
end

local function drawInventoryFullPopup()
    local popupWidth = 52
    local popupHeight = 9
    local popupX = math.floor((80 - popupWidth) / 2)
    local popupY = 9

    gpu.setBackground(colors.black_fon)
    gpu.fill(popupX, popupY, popupWidth, popupHeight, " ")
    gpu.fill(popupX+1, popupY+1, popupWidth-2, popupHeight-2, " ")
    drawPopupBorder(popupX, popupY, popupWidth, popupHeight, colors.error)

    gpu.setForeground(colors.error)
    local title = "ПРЕДУПРЕЖДЕНИЕ"
    local titleX = popupX + math.floor((popupWidth - unicode.len(title)) / 2)
    gpu.set(titleX, popupY, title)

    gpu.setForeground(colors.text_main)
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
        bg = colors.bg_button,
        fg = colors.success
    }
    drawFlexButton(okBtn)
    drawTempMessage()
end

-- ============================================
-- ЛОГИКА ПОКУПКИ/ПРОДАЖИ
-- ============================================
local function performBuy()
    if not playerData.agreed then
        drawCenteredText(20, "Сначала примите пользовательское соглашение", colors.error)
        os.sleep(2)
        currentScreen = "menu"
        drawMainMenu()
        return
    end

    local me = component.me_interface
    local item = purchaseItem

    local actualQty = getActualItemQuantity(item.internalName, item.damage)
    if actualQty <= 0 then
        drawCenteredText(20, "Товар закончился! Обновление списка...", colors.error)
        os.sleep(0.8)
        loadBuyItems()
        drawBuyStatic()
        drawBuyItemsList()
        drawBuyButtons()
        currentScreen = "shop_buy"
        return
    end

    local qty = purchaseQuantity
    if qty > actualQty then
        qty = actualQty
        purchaseQuantity = qty
        drawPurchaseScreen()
    end

    if qty <= 0 then
        drawCenteredText(20, "Выберите количество!", colors.error)
        os.sleep(0.8)
        currentScreen = "shop_buy"
        drawBuyStatic()
        drawBuyItemsList()
        drawBuyButtons()
        return
    end

    local totalCoin = (item.priceCoin or 0) * qty
    local totalEma = (item.priceEma or 0) * qty
    if playerData.balanceCoin < totalCoin or playerData.balanceEma < totalEma then
        showInsufficientPopup = true
        insufficientBalanceCoin = playerData.balanceCoin
        insufficientBalanceEma = playerData.balanceEma
        drawPurchaseScreen()
        drawInsufficientPopup()
        return
    end

    drawCenteredText(20, "Выполняется покупка...", colors.accent_main)
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
        showInventoryFullPopup = true
        drawPurchaseScreen()
        drawInventoryFullPopup()
        return
    end

    if extracted < qty then
        local actuallySpentCoin = extracted * (item.priceCoin or 0)
        local actuallySpentEma = extracted * (item.priceEma or 0)
        playerData.balanceCoin = playerData.balanceCoin - actuallySpentCoin
        playerData.balanceEma = playerData.balanceEma - actuallySpentEma
        playerData.transactions = playerData.transactions + 1

        partialExtracted = extracted
        partialRequested = qty
        partialRefundCoin = actuallySpentCoin
        partialRefundEma = actuallySpentEma
        partialItem = item
        showPartialPopup = true
        drawPurchaseScreen()
        drawPartialPopup()
        return
    end

    playerData.balanceCoin = playerData.balanceCoin - totalCoin
    playerData.balanceEma = playerData.balanceEma - totalEma
    playerData.transactions = playerData.transactions + 1

    gpu.setBackground(colors.bg_main)
    gpu.fill(2, 20, 78, 1, " ")
    local priceStr = ""
    if totalCoin > 0 then priceStr = priceStr .. string.format("%.2f", totalCoin) .. "₵" end
    if totalEma > 0 then
        if priceStr ~= "" then priceStr = priceStr .. " + " end
        priceStr = priceStr .. string.format("%.2f", totalEma) .. "۞"
    end
    drawCenteredText(20, "Куплено " .. extracted .. " шт. за " .. priceStr, colors.success)

    loadBuyItems()
    for _, newItem in ipairs(shopItems) do
        if newItem.internalName == item.internalName and newItem.damage == item.damage then
            purchaseItem = newItem
            break
        end
    end
    os.sleep(0.8)
    currentScreen = "shop_buy"
    drawBuyStatic()
    drawBuyItemsList()
    drawBuyButtons()
end

local function performSell()
    if not playerData.agreed then
        drawCenteredText(17, "Сначала примите пользовательское соглашение", colors.error)
        os.sleep(2)
        currentScreen = "menu"
        drawMainMenu()
        return
    end

    showSellPopup = false
    drawSellScanScreen()
    drawCenteredText(17, "Выполняется пополнение...", colors.accent_main)
    os.sleep(0.2)

    local realExtracted = extractToME(sellConfirmItem.internalName, foundAmount, sellConfirmItem.damage or 0)
    if realExtracted == 0 then
        drawCenteredText(17, "Не удалось изъять предметы! Проверьте инвентарь.", colors.error)
        os.sleep(2)
        currentScreen = "shop_sell"
        drawBuyStatic()
        drawBuyItemsList()
        drawBuyButtons()
        return
    end

    local value = realExtracted * sellConfirmItem.price
    if sellConfirmItem.internalName == "customnpcs:npcMoney" then
        playerData.balanceEma = playerData.balanceEma + value
    else
        playerData.balanceCoin = playerData.balanceCoin + value
    end
    playerData.transactions = playerData.transactions + 1

    gpu.setBackground(colors.bg_main)
    gpu.fill(2, 17, 78, 1, " ")
    local currencySymbol = (sellConfirmItem.internalName == "customnpcs:npcMoney") and "۞" or "₵"
    drawCenteredText(17, "Успешно! +" .. string.format("%.2f", value) .. " " .. currencySymbol, colors.success)
    os.sleep(0.8)

    currentScreen = "shop_sell"
    showSellPopup = false
    drawBuyStatic()
    drawBuyItemsList()
    drawBuyButtons()
end

-- ============================================
-- НАВИГАЦИЯ
-- ============================================
local function goToBuy()
    if not playerData.agreed then
        drawCenteredText(12, "Вы не приняли пользовательское соглашение!", colors.error)
        drawCenteredText(13, "Нажмите [Соглашение] и ознакомьтесь с условиями.", colors.text_main)
        os.sleep(3)
        drawMainMenu()
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
    drawBuyStatic()
    drawBuyItemsList()
    drawBuyButtons()
end

local function goToSell()
    if not playerData.agreed then
        drawCenteredText(12, "Вы не приняли пользовательское соглашение!", colors.error)
        drawCenteredText(13, "Нажмите [Соглашение] и ознакомьтесь с условиями.", colors.text_main)
        os.sleep(3)
        drawMainMenu()
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
    drawBuyStatic()
    drawBuyItemsList()
    drawBuyButtons()
end

local function goToShop()
    currentScreen = "shop"
    drawShopMenu()
end

local function goToAccount()
    currentScreen = "account"
    drawAccountScreen()
end

local function goToReport()
    currentScreen = "report"
    reportInput = ""
    drawReportScreen()
end

local function goToHelp()
    currentScreen = "agreement"
    if drawAgreementScreen and type(drawAgreementScreen) == "function" then
        drawAgreementScreen()
    else
        drawCenteredText(12, "Соглашение не загружено", colors.error)
        os.sleep(2)
        currentScreen = "menu"
        drawMainMenu()
    end
end

local function refreshAndAgree()
    if playerData.agreed then
        currentScreen = "menu"
        drawMainMenu()
        return
    end
    playerData.agreed = true
    drawCenteredText(20, "Спасибо! Теперь вам доступен магазин.", colors.success)
    os.sleep(0.8)
    currentScreen = "menu"
    drawMainMenu()
end

local function goBackToMenu()
    currentScreen = "menu"
    drawMainMenu()
    updateSelectorDisplay(nil)
    pcall(selector.setSlot, 0, nil)
    pcall(selector.setSlot, 1, nil)
end

local function handleQuantityButtonClick(btnText)
    if btnText == "C" then
        purchaseQuantity = 0
    elseif btnText == "<" then
        purchaseQuantity = math.floor(purchaseQuantity / 10)
    elseif tonumber(btnText) then
        local digit = tonumber(btnText)
        if purchaseQuantity == 0 then
            purchaseQuantity = digit
        else
            purchaseQuantity = purchaseQuantity * 10 + digit
        end
        if purchaseItem and purchaseQuantity > purchaseItem.qty then
            purchaseQuantity = purchaseItem.qty
        end
    end
    drawPurchaseScreen()
end

local function goToPurchase(item)
    if not item then return end
    purchaseItem = item
    purchaseQuantity = 1
    drawPurchaseScreen()
end

local function goToSellConfirm(item)
    if not item then return end
    sellConfirmItem = item
    foundAmount = 0
    showSellPopup = false
    drawSellScanScreen()
end

-- ============================================
-- ОБНОВЛЕНИЕ ЭКРАНА
-- ============================================
local function refreshCurrentScreen()
    if currentScreen == "idle" then
        drawIdleScreen()
    elseif currentScreen == "menu" then
        drawMainMenu()
    elseif currentScreen == "shop" then
        drawShopMenu()
    elseif currentScreen == "shop_buy" then
        drawBuyStatic()
        drawBuyItemsList()
        drawBuyButtons()
    elseif currentScreen == "shop_sell" then
        drawBuyStatic()
        drawBuyItemsList()
        drawBuyButtons()
    elseif currentScreen == "purchase" then
        drawPurchaseScreen()
    elseif currentScreen == "sell_scan" then
        drawSellScanScreen()
    elseif currentScreen == "account" then
        drawAccountScreen()
    elseif currentScreen == "feedbacks" then
        drawFeedbacksList()
    elseif currentScreen == "feedback_input" then
        drawFeedbackInputScreen()
    elseif currentScreen == "report" then
        drawReportScreen()
    elseif currentScreen == "agreement" then
        if drawAgreementScreen and type(drawAgreementScreen) == "function" then
            drawAgreementScreen()
        else
            drawMainMenu()
        end
    else
        drawMainMenu()
    end
end

-- ============================================
-- ИНИЦИАЛИЗАЦИЯ
-- ============================================
gpu.setResolution(80, 25)
gpu.setBackground(colors.bg_main)

-- Проверяем наличие игрока при старте
if pimManager:hasPlayerOnPlate() then
    createSession("Игрок")
    currentScreen = "menu"
    drawMainMenu()
else
    currentScreen = "idle"
    drawIdleScreen()
end

-- Запускаем мониторинг PIM
pimManager:startMonitoring()

-- ============================================
-- ОБРАБОТЧИКИ СОБЫТИЙ
-- ============================================
-- Появление игрока
event.listen("pim_occupied", function()
    if not session.active then
        createSession("Игрок")
        currentScreen = "menu"
        drawMainMenu()
        showTempMessage("Добро пожаловать!", 2)
    end
end)

-- Уход игрока
event.listen("pim_free", function()
    if session.active then
        destroySession()
        currentScreen = "idle"
        drawIdleScreen()
        showTempMessage("До свидания!", 2)
    end
end)

-- ============================================
-- ГЛАВНЫЙ ЦИКЛ
-- ============================================
while true do
    local ev = {event.pull(0.5)}
    local e = ev[1]
    
    -- Игнорируем клавишу Ctrl+C
    if e == "key_down" then
        local _, _, _, code, char = table.unpack(ev)
        if char == 3 then
            goto continue
        end
    end
    
    if e == "touch" then
        local x, y = ev[3], ev[4]
        
        -- ============================================
        -- ОБРАБОТКА ВСПЛЫВАЮЩИХ ОКОН
        -- ============================================
        if showSellPopup and currentScreen == "sell_scan" then
            local popupWidth = 40
            local popupHeight = 10
            local popupX = math.floor((80 - popupWidth) / 2)
            local popupY = 10
            local yesBtn = {x=popupX+5, y=popupY+7, xs=13, ys=1}
            local noBtn = {x=popupX+popupWidth-16, y=popupY+7, xs=12, ys=1}
            if isButtonClicked(yesBtn, x, y) then
                performSell()
            elseif isButtonClicked(noBtn, x, y) then
                showSellPopup = false
                drawSellScanScreen()
            elseif not (x >= popupX and x < popupX + popupWidth and y >= popupY and y < popupY + popupHeight) then
                showSellPopup = false
                drawSellScanScreen()
            end
            goto continue
        end
        
        if showInsufficientPopup then
            local popupWidth = 52
            local popupHeight = 11
            local popupX = math.floor((80 - popupWidth) / 2)
            local popupY = 7
            local okBtnText = "[ ПОНЯТНО ]"
            local okBtnWidth = unicode.len(okBtnText) + 2
            local okBtn = {
                x = popupX + math.floor((popupWidth - okBtnWidth) / 2),
                y = popupY+8,
                xs = okBtnWidth,
                ys = 1
            }
            if isButtonClicked(okBtn, x, y) then
                showInsufficientPopup = false
                currentScreen = "shop_buy"
                drawBuyStatic()
                drawBuyItemsList()
                drawBuyButtons()
            end
            goto continue
        end
        
        if showPartialPopup then
            local popupWidth = 52
            local popupHeight = 9
            local popupX = math.floor((80 - popupWidth) / 2)
            local popupY = 9
            local okBtnText = "[ ПРИНЯТЬ ]"
            local okBtnWidth = unicode.len(okBtnText) + 2
            local okBtn = {
                x = popupX + math.floor((popupWidth - okBtnWidth) / 2),
                y = popupY+6,
                xs = okBtnWidth,
                ys = 1
            }
            if isButtonClicked(okBtn, x, y) then
                showPartialPopup = false
                currentScreen = "shop_buy"
                drawBuyStatic()
                drawBuyItemsList()
                drawBuyButtons()
            end
            goto continue
        end
        
        if showInventoryFullPopup then
            local popupWidth = 52
            local popupHeight = 9
            local popupX = math.floor((80 - popupWidth) / 2)
            local popupY = 9
            local okBtnText = "[ ПОНЯТНО ]"
            local okBtnWidth = unicode.len(okBtnText) + 2
            local okBtn = {
                x = popupX + math.floor((popupWidth - okBtnWidth) / 2),
                y = popupY+6,
                xs = okBtnWidth,
                ys = 1
            }
            if isButtonClicked(okBtn, x, y) then
                showInventoryFullPopup = false
                currentScreen = "shop_buy"
                drawBuyStatic()
                drawBuyItemsList()
                drawBuyButtons()
            end
            goto continue
        end
        
        -- ============================================
        -- ОБРАБОТКА ЭКРАНА ПОКУПКИ/ПРОДАЖИ
        -- ============================================
        if currentScreen == "shop_buy" or currentScreen == "shop_sell" then
            if not session.active then
                currentScreen = "idle"
                drawIdleScreen()
                goto continue
            end
            
            -- Клик по списку предметов
            if y >= 7 and y <= 21 and x >= 2 and x <= 77 then
                local relativeRow = y - 6
                local clickedIndex = listScroll + relativeRow - 1
                local item = filteredItems[clickedIndex]
                if item and (currentShopMode ~= "buy" or item.qty > 0) then
                    selectedIndex = clickedIndex
                    selectedItem = item
                    hoveredIndex = 0
                    updateSelectorDisplay(selectedItem)
                    drawBuyItemsList()
                    drawBuyButtons()
                end
                goto continue
            end
            
            -- Клик по скроллбару
            if x >= 78 and y >= 7 and y <= 21 then
                local total = #filteredItems
                if total > visibleRows then
                    local clickPos = y - 6
                    listScroll = math.floor((clickPos - 1) * (total - visibleRows) / visibleRows) + 1
                    drawBuyItemsList()
                end
                goto continue
            end
            
            -- Клик по полю поиска
            if y == 3 and x >= 42 and x <= 64 then
                searchActive = true
                searchInput = shopSearch
                redrawSearchField()
                drawBuyItemsList()
                goto continue
            end
            
            -- Клик по кнопке "СТЕРЕТЬ"
            if y == 3 and x >= 66 and x <= 78 then
                shopSearch = ""
                searchInput = ""
                searchActive = false
                redrawSearchField()
                listScroll = 1
                selectedIndex = 0
                selectedItem = nil
                hoveredIndex = 0
                drawBuyItemsList()
                drawBuyButtons()
                goto continue
            end
            
            -- Кнопка НАЗАД
            if isButtonClicked({x=37, y=24, xs=12, ys=1}, x, y) then
                currentScreen = "shop"
                selectedIndex = 0
                selectedItem = nil
                hoveredIndex = 0
                updateSelectorDisplay(nil)
                drawShopMenu()
                goto continue
            end
            
            -- Кнопка КУПИТЬ/ПРОДАТЬ
            if x >= 59 and x <= 74 and y == 24 then
                if selectedItem and (currentShopMode ~= "buy" or selectedItem.qty > 0) then
                    if currentShopMode == "buy" then
                        local needCoin = selectedItem.priceCoin or 0
                        local needEma = selectedItem.priceEma or 0
                        if (needCoin > 0 and playerData.balanceCoin < needCoin) or (needEma > 0 and playerData.balanceEma < needEma) then
                            showInsufficientPopup = true
                            insufficientBalanceCoin = playerData.balanceCoin
                            insufficientBalanceEma = playerData.balanceEma
                            drawBuyStatic()
                            drawBuyItemsList()
                            drawBuyButtons()
                            drawInsufficientPopup()
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
                shopSearch = searchInput
                searchActive = false
                listScroll = 1
                selectedIndex = 0
                selectedItem = nil
                hoveredIndex = 0
                drawBuyItemsList()
                drawBuyButtons()
                goto continue
            end
        end
        
        -- ============================================
        -- ОБРАБОТКА ЭКРАНА ПОКУПКИ (ввод количества)
        -- ============================================
        if currentScreen == "purchase" then
            if (y >= 24 and y <= 24) and (x >= 19 and x <= 30) then
                if currentShopMode == "buy" then
                    currentScreen = "shop_buy"
                    drawBuyStatic()
                    drawBuyItemsList()
                    drawBuyButtons()
                else
                    currentScreen = "shop_sell"
                    drawBuyStatic()
                    drawBuyItemsList()
                    drawBuyButtons()
                end
                goto continue
            end
            
            if (y >= 24 and y <= 24) and (x >= 51 and x <= 63) then
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
                        break
                    end
                end
            end
            goto continue
        end
        
        -- ============================================
        -- ОБРАБОТКА ЭКРАНА ПРОДАЖИ (скан)
        -- ============================================
        if currentScreen == "sell_scan" then
            if isButtonClicked({x=37, y=24, xs=12, ys=1}, x, y) then
                currentScreen = "shop_sell"
                showSellPopup = false
                drawBuyStatic()
                drawBuyItemsList()
                drawBuyButtons()
                goto continue
            end
            
            if y == 13 and x >= 30 and x <= 50 then
                drawCenteredText(17, "Сканирование...", colors.accent_secondary)
                os.sleep(0.6)
                foundAmount = scanPlayerInventory(sellConfirmItem.internalName, sellConfirmItem.damage or 0)
                if foundAmount > 0 then
                    showSellPopup = true
                    drawSellScanScreen()
                else
                    drawCenteredText(17, "Предмет не найден!", colors.error)
                    os.sleep(0.8)
                    drawSellScanScreen()
                end
                goto continue
            end
        end
        
        -- ============================================
        -- ОБРАБОТКА ГЛАВНОГО МЕНЮ
        -- ============================================
        if currentScreen == "menu" then
            if not session.active then
                currentScreen = "idle"
                drawIdleScreen()
                goto continue
            end
            
            -- Кнопка "Магазин"
            if x >= 32 and x <= 52 and y >= 10 and y <= 13 then
                if playerData.agreed then
                    goToShop()
                else
                    showTempMessage("⚠️ Примите соглашение!", 2)
                end
                goto continue
            end
            
            -- Кнопка "Аккаунт"
            if x >= 32 and x <= 52 and y >= 16 and y <= 19 then
                goToAccount()
                goto continue
            end
            
            -- Нижняя панель
            if y == 24 then
                if x >= 4 and x <= 25 then
                    goToReport()
                elseif x >= 35 and x <= 47 then
                    goToHelp()
                elseif x >= 68 and x <= 78 then
                    currentScreen = "feedbacks"
                    drawFeedbacksList()
                end
                goto continue
            end
        end
        
        -- ============================================
        -- ОБРАБОТКА ОСТАЛЬНЫХ ЭКРАНОВ
        -- ============================================
        if currentScreen == "shop" then
            if x >= 32 and x <= 52 then
                if y >= 9 and y <= 12 then
                    goToBuy()
                elseif y >= 17 and y <= 20 then
                    goToSell()
                end
                goto continue
            end
            
            if isButtonClicked({x=37, y=24, xs=12, ys=1}, x, y) then
                goBackToMenu()
                goto continue
            end
        end
        
        if currentScreen == "account" then
            if isButtonClicked({x=37, y=24, xs=12, ys=1}, x, y) then
                goBackToMenu()
                goto continue
            end
        end
        
        if currentScreen == "feedbacks" then
            if isButtonClicked({x=5, y=24, xs=11, ys=1}, x, y) then
                goBackToMenu()
                goto continue
            end
            
            if isButtonClicked({x=36, y=24, xs=14, ys=1}, x, y) then
                if playerHasFeedback then
                    showTempMessage("Вы уже оставляли отзыв!", 2)
                else
                    feedbackInput = ""
                    feedbackEditMode = true
                    drawFeedbackInputScreen()
                end
                goto continue
            end
            
            if isButtonClicked({x=59, y=24, xs=7, ys=1}, x, y) and feedbacksPage > 1 then
                feedbacksPage = feedbacksPage - 1
                drawFeedbacksList()
                goto continue
            end
            
            if isButtonClicked({x=69, y=24, xs=7, ys=1}, x, y) and feedbacksPage < feedbacksTotalPages then
                feedbacksPage = feedbacksPage + 1
                drawFeedbacksList()
                goto continue
            end
        end
        
        if currentScreen == "feedback_input" then
            if isButtonClicked({x=20, y=24, xs=12, ys=1}, x, y) then
                feedbackEditMode = false
                feedbackInput = ""
                currentScreen = "feedbacks"
                drawFeedbacksList()
                goto continue
            end
            
            if isButtonClicked({x=46, y=24, xs=15, ys=1}, x, y) and feedbackInput ~= "" then
                table.insert(feedbacks, {
                    name = session.playerName,
                    text = feedbackInput,
                    time = os.date("%d.%m.%Y %H:%M:%S")
                })
                playerHasFeedback = true
                showTempMessage("✅ Отзыв сохранен! Спасибо!", 3)
                feedbackEditMode = false
                feedbackInput = ""
                currentScreen = "feedbacks"
                drawFeedbacksList()
                goto continue
            end
        end
        
        if currentScreen == "report" then
            if isButtonClicked({x=37, y=24, xs=12, ys=1}, x, y) then
                goBackToMenu()
                goto continue
            end
            
            if isButtonClicked({x=33, y=14, xs=17, ys=1}, x, y) and reportInput ~= "" then
                showTempMessage("✅ Репорт сохранен!", 3)
                reportInput = ""
                goBackToMenu()
                goto continue
            end
        end
        
        if currentScreen == "agreement" then
            local btnText = "[ ПОНЯТНО ]"
            local btnW = unicode.len(btnText) + 4
            local btnX = math.floor((80 - btnW)/2) + 2
            if y == 22 and x >= btnX and x <= btnX + btnW then
                refreshAndAgree()
                goto continue
            end
            
            if isButtonClicked({x=37, y=24, xs=12, ys=1}, x, y) then
                goBackToMenu()
                goto continue
            end
        end
    end
    
    -- ============================================
    -- ОБРАБОТКА КЛАВИАТУРЫ
    -- ============================================
    if e == "key_down" then
        local ch = ev[3]
        
        -- Поиск в магазине
        if (currentScreen == "shop_buy" or currentScreen == "shop_sell") and searchActive then
            if ch == 13 then
                shopSearch = searchInput
                searchActive = false
                listScroll = 1
                selectedIndex = 0
                selectedItem = nil
                hoveredIndex = 0
                drawBuyItemsList()
                drawBuyButtons()
            elseif ch == 8 then
                searchInput = unicode.sub(searchInput, 1, -2)
                shopSearch = searchInput
                redrawSearchField()
                drawBuyItemsList()
            elseif ch >= 32 then
                searchInput = searchInput .. unicode.char(ch)
                shopSearch = searchInput
                redrawSearchField()
                drawBuyItemsList()
            end
            goto continue
        end
        
        -- Ввод отзыва
        if currentScreen == "feedback_input" and feedbackEditMode then
            if ch == 13 then
                if feedbackInput ~= "" then
                    table.insert(feedbacks, {
                        name = session.playerName,
                        text = feedbackInput,
                        time = os.date("%d.%m.%Y %H:%M:%S")
                    })
                    playerHasFeedback = true
                    showTempMessage("✅ Отзыв сохранен! Спасибо!", 3)
                end
                feedbackEditMode = false
                feedbackInput = ""
                currentScreen = "feedbacks"
                drawFeedbacksList()
            elseif ch == 8 then
                feedbackInput = unicode.sub(feedbackInput, 1, -2)
                drawFeedbackInputScreen()
            elseif ch >= 32 then
                if unicode.len(feedbackInput) < 200 then
                    feedbackInput = feedbackInput .. unicode.char(ch)
                    drawFeedbackInputScreen()
                end
            end
            goto continue
        end
        
        -- Ввод репорта
        if currentScreen == "report" then
            if ch == 13 then
                drawReportScreen()
            elseif ch == 8 then
                reportInput = unicode.sub(reportInput, 1, -2)
                drawReportScreen()
            elseif ch >= 32 then
                reportInput = reportInput .. unicode.char(ch)
                drawReportScreen()
            end
            goto continue
        end
        
        -- Прокрутка колесиком мыши
        if e == "scroll" and (currentScreen == "shop_buy" or currentScreen == "shop_sell") then
            local direction = ev[5]
            local x = ev[3]
            local y = ev[4]
            if x >= 2 and x <= 78 and y >= 7 and y <= 21 then
                if direction == -1 then
                    smoothScroll(1)
                elseif direction == 1 then
                    smoothScroll(-1)
                end
            end
            goto continue
        end
        
        -- Наведение мыши
        if e == "mouse_move" and (currentScreen == "shop_buy" or currentScreen == "shop_sell") then
            local x, y = ev[3], ev[4]
            if y >= 7 and y <= 21 and x >= 2 and x <= 77 then
                local rel = y - 6
                local newHover = listScroll + rel - 1
                if newHover <= #filteredItems and newHover ~= hoveredIndex then
                    hoveredIndex = newHover
                    drawBuyItemsList()
                end
            else
                if hoveredIndex ~= 0 then
                    hoveredIndex = 0
                    drawBuyItemsList()
                end
            end
            goto continue
        end
    end
    
    ::continue::
end
