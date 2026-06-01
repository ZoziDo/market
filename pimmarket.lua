local component = require("component")
local event = require("event")
local gpu = component.gpu
local unicode = require("unicode")
local serialization = require("serialization")
local keyboard = require("keyboard")
local computer = require("computer")
local fs = require("filesystem")
local TIMEZONE_OFFSET = 3 * 3600

event.ignore("interrupted", function() end)
event.ignore("terminate", function() end)

local tmpfs = component.proxy(computer.tmpAddress())
local function getRealTimestamp()
    local handle = tmpfs.open("/time", "w")
    tmpfs.write(handle, "time")
    tmpfs.close(handle)
    return tmpfs.lastModified("/time") / 1000 + TIMEZONE_OFFSET
end

local function getRealTimeString()
    return os.date("%d.%m.%Y %H:%M:%S", getRealTimestamp())
end

local function getRealTimeHM()
    return os.date("%H:%M:%S", getRealTimestamp())
end

local serverAddress = "535305a9-37c9-4645-b7c4-46204187ee7b"
local ACCESS_PASSWORD = "secret"

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

local coinBalance = 0.0
local emaBalance = 0.0

local function clear()
    gpu.setBackground(colors.bg_main)
    gpu.fill(1, 1, 80, 25, " ")
end

local function drawCenteredText(y, text, color)
    gpu.setForeground(color or colors.text_main)
    local x = math.floor((80 - unicode.len(text)) / 2) + 1 + 1
    gpu.set(x, y, text)
end

local function drawBalanceLine(x, y)
    if coinBalance == nil or emaBalance == nil then
        gpu.setForeground(colors.white)
        gpu.set(x, y, "Баланс: загрузка...")
        return
    end
    gpu.setForeground(colors.white)
    gpu.set(x, y, "Баланс: ")
    local coinStr = string.format("%.2f", coinBalance) .. " Coina ₵"
    gpu.setForeground(colors.accent_main)
    gpu.set(x + unicode.len("Баланс: "), y, coinStr)
    gpu.setForeground(colors.white)
    gpu.set(x + unicode.len("Баланс: ") + unicode.len(coinStr), y, " | ")
    local emaStr = "ЭМЫ: " .. string.format("%.2f", emaBalance) .. " ۞"
    gpu.setForeground(colors.tomato)
    gpu.set(x + unicode.len("Баланс: ") + unicode.len(coinStr) + unicode.len(" | "), y, emaStr)
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

local function safeDoFile(path)
    if not fs.exists(path) then
        print("Файл не найден, создаём: " .. path)
        return {}
    end
    local ok, result = pcall(dofile, path)
    if not ok then
        print("Ошибка загрузки файла " .. path .. ": " .. tostring(result))
        return {}
    end
    return result
end

local function sortableName(name)
    if not name then return "" end
    local lower = string.lower(name)
    local result = lower:gsub("(%d+)", function(d)
        return string.format("%08d", tonumber(d))
    end)
    return result
end

local feedbacks = {}
local feedbacksPage = 1
local feedbacksTotalPages = 1
local feedbackInput = ""
local feedbackEditMode = false
local playerHasFeedback = false

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

local shopData = safeDoFile("/home/shop_items.lua")
local sellItems = shopData.sellItems
local vanillaItems = shopData.vanillaItems or {}

local buyItemsData = safeDoFile("/home/buy_items.lua")
local buyItemMap = {}
for _, item in ipairs(buyItemsData) do
    local dmg = item.damage or 0
    local key = item.internalName .. ":" .. dmg
    buyItemMap[key] = item
end

local drawAgreementScreen = safeDoFile("/home/agreement.lua")

local modem = component.modem

local function getPimAddr()
    for addr in component.list("pim") do
        return addr
    end
    return nil
end

local PUSH_DIRECTION = "down"
local PULL_DIRECTION = "up"

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

modem.open(0xffef)
modem.open(0xfffe)

local currentPlayer, currentToken = nil, nil
local playerTransactions = 0
local playerRegDate = ""
local playerAgreed = false
local currentScreen = "welcome"
local authStartTime = 0
local AUTH_TIMEOUT = 3
local accountRequestTime = 0
local ACCOUNT_TIMEOUT = 3
local alreadyAuthorized = false

local shopItems = {}
local shopSearch = ""
local searchActive = false
local searchInput = ""
local currentShopMode = "buy"

local blacklist = {
    ["customnpcs:npcMoney"] = true,
}

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

local reportInput = ""
local lastReportTime = nil
local showShopDenied = false

local tempMessage = ""
local tempMessageTimer = nil

-- ========== НОВАЯ СИСТЕМА КВЕСТОВ ==========
local questsList = {}
local selectedQuest = nil
local questListScroll = 1
local questVisibleRows = 15
local questSelectedIndex = 0
local questHoveredIndex = 0
local questSearch = ""
local questSearchActive = false
local questSearchInput = ""

local pendingFilePath = "/home/pending_quests.lua"
local currentQuestForDetails = nil   -- квест, выбранный для детального просмотра

-- ========== ФУНКЦИИ КВЕСТОВ ==========
local function loadQuests()
    if not fs.exists("/home/quests.lua") then
        questsList = {}
        return
    end
    local ok, data = pcall(dofile, "/home/quests.lua")
    if not ok or type(data) ~= "table" then
        questsList = {}
        return
    end
    questsList = data
    for _, quest in ipairs(questsList) do
        quest.available = nil
    end
end

local function checkQuestAvailable(quest)
    if not component.isAvailable("me_interface") then return false end
    local me = component.me_interface
    for _, req in ipairs(quest.requiredItems) do
        local needed = req.requiredCount
        local found = 0
        local items = me.getItemsInNetwork()
        for _, meItem in ipairs(items) do
            if meItem.name == req.internalName and (meItem.damage or 0) == (req.damage or 0) then
                found = found + (meItem.size or 0)
                if found >= needed then break end
            end
        end
        if found < needed then
            return false
        end
    end
    return true
end

local function getMissingItemsText(quest)
    if not component.isAvailable("me_interface") then return "ME система недоступна" end
    local me = component.me_interface
    local missing = {}
    for _, req in ipairs(quest.requiredItems) do
        local needed = req.requiredCount
        local found = 0
        local items = me.getItemsInNetwork()
        for _, meItem in ipairs(items) do
            if meItem.name == req.internalName and (meItem.damage or 0) == (req.damage or 0) then
                found = found + (meItem.size or 0)
                if found >= needed then break end
            end
        end
        if found < needed then
            table.insert(missing, req.displayName .. " (" .. (needed - found) .. "/" .. needed .. ")")
        end
    end
    return table.concat(missing, ", ")
end

local function savePendingForPlayer(player, questName, pendingItems)
    local pendingData = {}
    if fs.exists(pendingFilePath) then
        local ok, data = pcall(dofile, pendingFilePath)
        if ok and type(data) == "table" then pendingData = data end
    end
    pendingData[player] = {
        questName = questName,
        items = pendingItems
    }
    local file = io.open(pendingFilePath, "w")
    if file then
        file:write("return " .. serialization.serialize(pendingData))
        file:close()
    end
end

local function loadPendingForPlayer(player)
    if not fs.exists(pendingFilePath) then return nil end
    local ok, data = pcall(dofile, pendingFilePath)
    if not ok or type(data) ~= "table" then return nil end
    return data[player]
end

local function deletePendingForPlayer(player)
    if not fs.exists(pendingFilePath) then return end
    local pendingData = {}
    local ok, data = pcall(dofile, pendingFilePath)
    if ok and type(data) == "table" then pendingData = data end
    pendingData[player] = nil
    local file = io.open(pendingFilePath, "w")
    if file then
        file:write("return " .. serialization.serialize(pendingData))
        file:close()
    end
end

local function processPendingOnLogin(player)
    local pending = loadPendingForPlayer(player)
    if not pending or not pending.items or #pending.items == 0 then
        deletePendingForPlayer(player)
        return
    end
    local me = component.me_interface
    if not me then return end
    local allCompleted = true
    local newPending = {}
    for _, req in ipairs(pending.items) do
        if req.neededCount > 0 then
            local id = req.internalName
            if not id:find(":") then id = "minecraft:" .. id end
            local fingerprint = { id = id, dmg = req.damage or 0 }
            local maxStack = 64
            local ok, detail = pcall(me.getItemDetail, me, req.internalName, req.damage)
            if ok and detail and detail.maxSize then maxStack = detail.maxSize end
            local remaining = req.neededCount
            local extracted = 0
            while remaining > 0 do
                local toTake = math.min(remaining, maxStack)
                local success, result = pcall(me.exportItem, me, fingerprint, PULL_DIRECTION, toTake)
                local got = 0
                if success then
                    if type(result) == "number" then got = result
                    elseif type(result) == "boolean" and result == true then got = toTake
                    elseif type(result) == "table" then got = result.count or result.amount or result.size or toTake
                    else got = 0 end
                end
                if got > 0 then
                    extracted = extracted + got
                    remaining = remaining - got
                else
                    break
                end
            end
            if extracted < req.neededCount then
                allCompleted = false
                table.insert(newPending, {
                    internalName = req.internalName,
                    damage = req.damage,
                    displayName = req.displayName,
                    neededCount = req.neededCount - extracted
                })
            end
        end
    end
    if allCompleted then
        deletePendingForPlayer(player)
        showTempMessage("✅ Все предметы квеста '" .. pending.questName .. "' получены!", 5)
    else
        savePendingForPlayer(player, pending.questName, newPending)
        showTempMessage("⚠️ Часть предметов квеста выдана, остальное позже", 5)
    end
end

local function performBuyQuest(quest)
    if not playerAgreed then
        drawCenteredText(20, "Сначала примите пользовательское соглашение", colors.error)
        os.sleep(2)
        goBackToMenu()
        return
    end

    if emaBalance < quest.priceEma then
        showTempMessage("Недостаточно ЭМЫ! Нужно: " .. string.format("%.2f", quest.priceEma), 3)
        drawQuestDetailsScreen(quest)
        return
    end

    if not checkQuestAvailable(quest) then
        local missing = getMissingItemsText(quest)
        showTempMessage("Не хватает в МЭ: " .. missing, 4)
        drawQuestDetailsScreen(quest)
        return
    end

    -- списываем ЭМЫ
    emaBalance = emaBalance - quest.priceEma
    playerTransactions = playerTransactions + 1
    if currentToken then
        modem.send(serverAddress, 0xffef, serialization.serialize({
            op = "buy_quest",
            name = currentPlayer,
            token = currentToken,
            questName = quest.name,
            priceEma = quest.priceEma
        }))
    end

    local me = component.me_interface
    local pendingItems = {}
    local anyMissing = false

    for _, req in ipairs(quest.requiredItems) do
        local id = req.internalName
        if not id:find(":") then id = "minecraft:" .. id end
        local fingerprint = { id = id, dmg = req.damage or 0 }
        local needed = req.requiredCount
        local maxStack = 64
        local ok, detail = pcall(me.getItemDetail, me, req.internalName, req.damage)
        if ok and detail and detail.maxSize then maxStack = detail.maxSize end

        local remaining = needed
        local extracted = 0
        while remaining > 0 do
            local toTake = math.min(remaining, maxStack)
            local success, result = pcall(me.exportItem, me, fingerprint, PULL_DIRECTION, toTake)
            local got = 0
            if success then
                if type(result) == "number" then got = result
                elseif type(result) == "boolean" and result == true then got = toTake
                elseif type(result) == "table" then got = result.count or result.amount or result.size or toTake
                else got = 0 end
            end
            if got > 0 then
                extracted = extracted + got
                remaining = remaining - got
            else
                break
            end
        end
        if extracted < needed then
            anyMissing = true
            table.insert(pendingItems, {
                internalName = req.internalName,
                damage = req.damage,
                displayName = req.displayName,
                neededCount = needed - extracted
            })
        end
    end

    if anyMissing then
        savePendingForPlayer(currentPlayer, quest.name, pendingItems)
        showTempMessage("⚠️ Часть предметов не влезла в инвентарь. Остальное выдадим позже.", 5)
    else
        showTempMessage("✅ Квест '" .. quest.name .. "' выполнен! Все предметы выданы.", 5)
    end

    drawQuestListScreen()
end

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

-- ========== ОТРИСОВКА ЭКРАНА КВЕСТОВ (СПИСОК) ==========
local function drawQuestStatic()
    clear()
    drawScreenBorder()
    drawBalanceLine(3, 1)

    gpu.setForeground(colors.accent_secondary)
    gpu.set(3, 3, "НАБОРЫ / КВЕСТЫ")

    local searchX = 42
    local searchText = ""
    if questSearchActive then
        searchText = questSearchInput .. "_"
    else
        searchText = (questSearch == "" and "Поиск..." or questSearch)
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
    gpu.set(3, 5, "Название квеста")
    gpu.set(55, 5, "Цена (ЭМЫ)")
    gpu.setBackground(colors.bg_main)

    drawTempMessage()
end

local function drawQuestSingleRow(y, quest, isHovered, isSelected, idx)
    local bg, fg
    local available = checkQuestAvailable(quest)
    if isSelected then
        bg = 0x225577
    elseif isHovered then
        bg = 0x446688
    elseif idx % 2 == 1 then
        bg = colors.bg_secondary
    else
        bg = 0x1a1a1a
    end
    fg = available and colors.accent_main or colors.inactive
    gpu.setBackground(bg)
    gpu.fill(2, y, 76, 1, " ")
    gpu.setForeground(fg)
    local name = quest.name
    if unicode.len(name) > 37 then name = unicode.sub(name, 1, 37) end
    gpu.set(3, y, name)
    gpu.setForeground(colors.tomato)
    gpu.set(55, y, string.format("%.2f", quest.priceEma) .. " ۞")
    gpu.setBackground(colors.bg_main)
end

local function drawQuestList()
    local filtered = questsList
    if questSearch ~= "" then
        local lower = string.lower(questSearch)
        filtered = {}
        for _, q in ipairs(questsList) do
            if string.find(string.lower(q.name), lower, 1, true) then
                table.insert(filtered, q)
            end
        end
    end

    local maxScroll = math.max(1, #filtered - questVisibleRows + 1)
    questListScroll = math.max(1, math.min(questListScroll, maxScroll))

    gpu.setBackground(colors.bg_main)
    gpu.fill(2, 7, 78, questVisibleRows, " ")

    for i = 1, questVisibleRows do
        local idx = questListScroll + i - 1
        local q = filtered[idx]
        if q then
            local y = 6 + i
            local isSelected = (idx == questSelectedIndex)
            local isHovered = (idx == questHoveredIndex)
            drawQuestSingleRow(y, q, isHovered, isSelected, idx)
        end
    end

    -- скроллбар
    local barX = 78
    local barY = 7
    local barHeight = 15
    gpu.setBackground(colors.bg_main)
    gpu.fill(barX, barY, 2, barHeight, " ")
    if #filtered > questVisibleRows then
        gpu.setBackground(colors.bg_secondary)
        gpu.fill(barX, barY, 2, barHeight, " ")
        local thumbHeight = math.max(2, math.floor(barHeight * questVisibleRows / #filtered))
        local maxPos = barHeight - thumbHeight
        local thumbPos = math.floor((questListScroll - 1) * maxPos / (#filtered - questVisibleRows)) + 1
        thumbPos = math.min(thumbPos, maxPos + 1)
        gpu.setBackground(colors.accent_main)
        gpu.fill(barX, barY + thumbPos - 1, 2, thumbHeight, " ")
        gpu.setBackground(colors.bg_main)
    end
end

local function drawQuestButtons()
    local backBtn = {x = 5, y = 24, xs = 11, ys = 1, text = "[ НАЗАД ]", bg = colors.bg_button, fg = colors.accent_secondary}
    local detailsBtn = {x = 65, y = 24, xs = 13, ys = 1, text = "[ ПОДРОБНЕЕ ]", bg = colors.bg_button, fg = colors.success}
    drawFlexButton(backBtn)
    drawFlexButton(detailsBtn)
    drawTempMessage()
end

local function drawQuestListScreen()
    currentScreen = "shop_bundle"
    drawQuestStatic()
    drawQuestList()
    drawQuestButtons()
end

-- ========== ЭКРАН ДЕТАЛЕЙ КВЕСТА (СПИСОК ПРЕДМЕТОВ) ==========
local function drawQuestDetailsScreen(quest)
    currentQuestForDetails = quest
    currentScreen = "quest_details"
    clear()
    drawScreenBorder()
    drawBalanceLine(3, 1)

    gpu.setForeground(colors.accent_secondary)
    gpu.set(3, 3, "КВЕСТ: " .. quest.name)

    gpu.setForeground(colors.success)
    gpu.set(3, 4, "Цена: ")
    gpu.setForeground(colors.tomato)
    gpu.set(3 + unicode.len("Цена: "), 4, string.format("%.2f", quest.priceEma) .. " ۞")

    gpu.setForeground(colors.text_bright)
    gpu.set(3, 5, "Список выдаваемых предметов:")

    local y = 7
    for i, req in ipairs(quest.requiredItems) do
        if y > 21 then
            gpu.setForeground(colors.error)
            gpu.set(3, 22, "... и ещё " .. (#quest.requiredItems - i + 1) .. " предметов")
            break
        end
        gpu.setForeground(colors.text_main)
        gpu.set(5, y, req.displayName)
        gpu.setForeground(colors.accent_main)
        gpu.set(55, y, "x" .. req.requiredCount)
        y = y + 1
    end

    local backBtn = {x = 20, y = 24, xs = 12, ys = 1, text = "[ НАЗАД ]", bg = colors.bg_button, fg = colors.accent_secondary}
    local buyBtn = {x = 50, y = 24, xs = 15, ys = 1, text = "[ ПРИОБРЕСТИ ]", bg = colors.bg_button, fg = colors.success}
    drawFlexButton(backBtn)
    drawFlexButton(buyBtn)
    drawTempMessage()
end

-- ========== ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ (НЕ ИЗМЕНЕНЫ) ==========
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

gpu.setResolution(80, 25)
gpu.setBackground(colors.bg_main)

local function drawBigTitle()
    gpu.setForeground(colors.accent_secondary)
    local darkonLines = {
        "  ██████╗ ██████╗  █████╗ ██████╗ ██╗  ██╗ ██████╗ ███╗   ██╗",
        "  ██╔══██╗██╔══██╗██╔══██╗██╔══██╗██║ ██╔╝██╔═══██╗████╗  ██║",
        "  ██║  ██║██████╔╝███████║██║  ██║█████╔╝ ██║   ██║██╔██╗ ██║",
        "  ██║  ██║██╔══██╗██╔══██║██║  ██║██╔═██╗ ██║   ██║██║╚██╗██║",
        "  ██████╔╝██║  ██║██║  ██║██████╔╝██║  ██╗╚██████╔╝██║ ╚████║",
    }
    local darkonOffset = 47
    local darkonX = math.floor((80 - #darkonLines[1]) / 2) + darkonOffset
    for i, line in ipairs(darkonLines) do
        gpu.set(darkonX, 4 + i, line)
    end

    local shopLines = {
        "  ███████╗ ██╗  ██╗  ██████╗  ██████╗ ",
        "  ██╔════╝ ██║  ██║ ██╔═══██╗ ██╔══██╗",
        "  ███████╗ ███████║ ██║   ██║ ██████╔╝",
        "  ╚════██║ ██╔══██║ ██║   ██║ ██╔═══╝ ",
        "  ███████║ ██║  ██║ ╚██████╔╝ ██║     "
    }
    local shopOffset = 28
    local shopX = math.floor((80 - #shopLines[1]) / 2) + shopOffset
    for i, line in ipairs(shopLines) do
        gpu.set(shopX, 10 + i, line)
    end
end

local function showTempMessage(msg, duration)
    tempMessage = msg
    if tempMessageTimer then
        event.cancel(tempMessageTimer)
    end
    tempMessageTimer = event.timer(duration, function()
        tempMessage = ""
        tempMessageTimer = nil
        if currentScreen == "shop_buy" or currentScreen == "shop_sell" then
            drawBuyStatic()
            drawBuyItemsList()
            drawBuyButtons()
        elseif currentScreen == "menu" then
            drawMainMenu()
        elseif currentScreen == "shop" then
            drawShopMenu()
        elseif currentScreen == "account" then
            drawAccount({balance=coinBalance, emaBalance=emaBalance, transactions=playerTransactions, regDate=playerRegDate, agreed=playerAgreed})
        elseif currentScreen == "feedbacks" then
            drawFeedbacksList()
        elseif currentScreen == "quest_details" and currentQuestForDetails then
            drawQuestDetailsScreen(currentQuestForDetails)
        elseif currentScreen == "shop_bundle" then
            drawQuestListScreen()
        else
            drawTempMessage()
        end
    end)
    drawTempMessage()
end

local function loadFeedbacksFromServer()
    if not currentToken then return end
    modem.send(serverAddress, 0xffef, serialization.serialize({
        op = "get_feedbacks",
        name = currentPlayer,
        token = currentToken
    }))
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

    local backBtn = {x = 5, y = 24, xs = 11, ys = 1, text = "[ НАЗАД ]", bg = colors.bg_button, fg = colors.accent_secondary}
    local addBtn = {x = 36, y = 24, xs = 14, ys = 1, text = "[ ДОБАВИТЬ ]", bg = colors.bg_button, fg = colors.success}
    local prevBtn = {x = 59, y = 24, xs = 7, ys = 1, text = "[ < ]", bg = colors.bg_button, fg = colors.accent_main}
    local nextBtn = {x = 69, y = 24, xs = 7, ys = 1, text = "[ > ]", bg = colors.bg_button, fg = colors.accent_main}

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
        goBackToMenu()
        return
    end
    currentScreen = "feedback_input"
    clear()
    drawScreenBorder()
    drawCenteredText(4, "ОСТАВИТЬ ОТЗЫВ", colors.accent_secondary)

    gpu.setForeground(colors.text_main)
    drawCenteredText(7, "Ваше имя: " .. currentPlayer, colors.accent_main)
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

    local cancelBtn = {x = 20, y = 24, xs = 12, ys = 1, text = "[ ОТМЕНА ]", bg = colors.bg_button, fg = colors.error}
    local sendBtn = {x = 46, y = 24, xs = 15, ys = 1, text = "[ ОТПРАВИТЬ ]", bg = colors.bg_button, fg = colors.success}

    drawFlexButton(cancelBtn)
    drawFlexButton(sendBtn)
    drawTempMessage()
end

local menuButtons = {
    shop    = {x=32, xs=20, y=9,  ys=3, text="🛒 Магазин",     tx=6, ty=1, bg=colors.bg_button, fg=colors.accent_main},
    util    = {x=32, xs=20, y=13, ys=3, text="🛠 Полезности",   tx=5, ty=1, bg=colors.bg_button, fg=colors.accent_main},
    account = {x=32, xs=20, y=17, ys=3, text="👤 Аккаунт",      tx=6, ty=1, bg=colors.bg_button, fg=colors.accent_main}
}

local function drawBottomPanel()
    gpu.setForeground(colors.error)
    gpu.set(4, 24, "[ ПОДДЕРЖКА ]")
    gpu.set(35, 24, "[ СОГЛАШЕНИЕ ]")
    gpu.set(68, 24, "[ ОТЗЫВЫ ]")
end

local backButton = {
    text = "[ НАЗАД ]",
    x = 37, y = 24,
    xs = unicode.len("[ НАЗАД ]") + 2,
    ys = 1,
    bg = colors.bg_button,
    fg = colors.accent_secondary
}

local function isButtonClicked(btn, x, y)
    return y >= btn.y and y < btn.y + btn.ys and x >= btn.x and x < btn.x + btn.xs
end

local nextButton    = {text = "[ КУПИТЬ ]",  x=59, y=24, xs=11, ys=1, bg=colors.bg_button, fg=colors.inactive}

local shopMenuButtons = {
    buy    = {x=32, xs=20, y=9,  ys=3, text="🛍 Покупка",     tx=6, ty=1, bg=colors.bg_button, fg=colors.accent_main},
    sell   = {x=32, xs=20, y=13, ys=3, text="💰 Пополнение",  tx=5, ty=1, bg=colors.bg_button, fg=colors.accent_main},
    bundle = {x=32, xs=20, y=17, ys=3, text="🎁 Наборы/Квесты", tx=4, ty=1, bg=colors.bg_button, fg=colors.accent_main}
}

local function canSendReport()
    if not lastReportTime then return true end
    local now = getRealTimestamp()
    local reportDate = os.date("*t", lastReportTime)
    local nowDate = os.date("*t", now)
    if reportDate.day ~= nowDate.day or reportDate.month ~= nowDate.month or reportDate.year ~= nowDate.year then
        return true
    end
    return false
end

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

local function loadBuyItems()
    if not component.isAvailable("me_interface") then return end
    local me = component.me_interface
    local rawItems = me.getItemsInNetwork()
    local tempShopItems = {}
    local knownKeys = {}
    for _, item in ipairs(shopItems) do
        local key = item.internalName .. ":" .. (item.damage or 0)
        knownKeys[key] = true
    end
    local newFound = {}

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

    local newShopItems = {}
    for key, itemData in pairs(tempShopItems) do
        table.insert(newShopItems, itemData)
        if not knownKeys[key] and itemData.qty > 0 then
            table.insert(newFound, {name = itemData.displayName, qty = itemData.qty})
        end
    end

    if #newFound > 0 and currentToken then
        local chunkSize = 10
        for i = 1, #newFound, chunkSize do
            local chunk = {}
            for j = i, math.min(i + chunkSize - 1, #newFound) do
                table.insert(chunk, newFound[j])
            end
            local data = serialization.serialize({
                op = "new_items",
                name = currentPlayer,
                token = currentToken,
                items = chunk
            })
            if #data < 8000 then
                modem.send(serverAddress, 0xffef, data)
            else
                print("Предупреждение: пакет с " .. #chunk .. " предметами слишком велик")
            end
            os.sleep(0.05)
        end
    end

    shopItems = newShopItems
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
    if currentToken then
        modem.send(serverAddress, 0xffef, serialization.serialize({
            op = "scan_report",
            name = currentPlayer,
            token = currentToken,
            target = targetName,
            found = total
        }))
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
            local y = 6 + i
            local isSelected = (itemIndex == selectedIndex)
            local isHovered = (itemIndex == hoveredIndex)
            drawSingleRow(y, item, isHovered, isSelected, itemIndex)
        end
    end

    drawScrollBar()
    if selectedItem then
        updateSelectorDisplay(selectedItem)
    end
end

local function smoothScroll(steps)
    local filtered = filteredItems
    local total = #filtered
    local maxScroll = math.max(1, total - visibleRows + 1)
    local newScroll = listScroll + steps
    newScroll = math.max(1, math.min(newScroll, maxScroll))
    if newScroll == listScroll then return end
    if math.abs(steps) == 1 and total > visibleRows then
        if steps > 0 then
            gpu.copy(2, 8, 76, visibleRows - 1, 0, -1)
            gpu.setBackground(colors.bg_main)
            gpu.fill(2, 21, 76, 1, " ")
            local newIdx = newScroll + visibleRows - 1
            if newIdx <= total then
                drawSingleRow(21, filtered[newIdx], (newIdx == hoveredIndex), (newIdx == selectedIndex), newIdx)
            end
        else
            gpu.copy(2, 7, 76, visibleRows - 1, 0, 1)
            gpu.setBackground(colors.bg_main)
            gpu.fill(2, 7, 76, 1, " ")
            local newIdx = newScroll
            if newIdx >= 1 then
                drawSingleRow(7, filtered[newIdx], (newIdx == hoveredIndex), (newIdx == selectedIndex), newIdx)
            end
        end
    else
        drawBuyItemsList()
        return
    end
    listScroll = newScroll
    drawScrollBar()
end

local function drawBuyButtons()
    if currentShopMode == "buy" then
        nextButton.text = "[ КУПИТЬ ]"
        nextButton.xs = unicode.len(nextButton.text) + 2
    else
        nextButton.text = "[ ПРОДАТЬ ]"
        nextButton.xs = unicode.len(nextButton.text) + 2
    end

    if selectedItem and (currentShopMode ~= "buy" or selectedItem.qty > 0) then
        nextButton.fg = colors.accent_secondary
    else
        nextButton.fg = colors.inactive
    end

    drawFlexButton(backButton)
    drawFlexButton(nextButton)
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
    local backBtn = {x = 19, y = 24, xs = unicode.len("[ НАЗАД ]") + 2, ys = 1, text = "[ НАЗАД ]", bg = colors.bg_button, fg = colors.accent_secondary}
    local buyBtn  = {x = 51, y = 24, xs = unicode.len("[ КУПИТЬ ]") + 2, ys = 1, text = "[ КУПИТЬ ]", bg = colors.bg_button, fg = colors.success}
    drawFlexButton(backBtn)
    drawFlexButton(buyBtn)
    drawTempMessage()
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
    local noBtn  = {x=popupX+popupWidth-16, y=popupY+7, xs=12, ys=1, text="[ Отмена ]", bg=colors.bg_button, fg=colors.error}
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

    local allBtn  = {x=30, y=13, xs=20, ys=1, text="Весь инвентарь", bg=colors.bg_button, fg=colors.success}
    drawFlexButton(allBtn)
    drawFlexButton(backButton)

    if showSellPopup and sellConfirmItem then
        drawSellPopup()
    end
    drawTempMessage()
end

local function goToSellConfirm(item)
    if not item then return end
    sellConfirmItem = item
    foundAmount = 0
    showSellPopup = false
    drawSellScanScreen()
end

local function performSell()
    if not playerAgreed then
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
        emaBalance = emaBalance + value
    else
        coinBalance = coinBalance + value
    end
    playerTransactions = playerTransactions + 1

    if currentToken then
        modem.send(serverAddress, 0xffef, serialization.serialize({
            op = "sell",
            name = currentPlayer,
            token = currentToken,
            item = sellConfirmItem.displayName,
            internalName = sellConfirmItem.internalName,
            qty = realExtracted,
            value = value
        }))
    end

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

local function performBuy()
    if not playerAgreed then
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
    if coinBalance < totalCoin or emaBalance < totalEma then
        showInsufficientPopup = true
        insufficientBalanceCoin = coinBalance
        insufficientBalanceEma = emaBalance
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
        coinBalance = coinBalance - actuallySpentCoin
        emaBalance = emaBalance - actuallySpentEma
        playerTransactions = playerTransactions + 1

        if currentToken then
            modem.send(serverAddress, 0xffef, serialization.serialize({
                op = "buy",
                name = currentPlayer,
                token = currentToken,
                item = item.displayName,
                internalName = item.internalName,
                qty = extracted,
                value_coin = actuallySpentCoin,
                value_ema = actuallySpentEma
            }))
        end

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

    coinBalance = coinBalance - totalCoin
    emaBalance = emaBalance - totalEma
    playerTransactions = playerTransactions + 1

    if currentToken then
        modem.send(serverAddress, 0xffef, serialization.serialize({
            op = "buy",
            name = currentPlayer,
            token = currentToken,
            item = item.displayName,
            internalName = item.internalName,
            qty = extracted,
            value_coin = totalCoin,
            value_ema = totalEma
        }))
    end

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

local function drawReportScreen()
    currentScreen = "report"
    clear()
    drawScreenBorder()
    drawCenteredText(4, "РЕПОРТ", colors.accent_secondary)
    gpu.setForeground(colors.text_main)
    local help1 = "Опишите проблему: баг, предложение, жалоба."
    local helpX = math.floor((80 - unicode.len(help1)) / 2) + 1
    gpu.set(helpX, 7, help1)

    if not canSendReport() then
        drawCenteredText(9, "Вы уже отправляли репорт сегодня.", colors.error)
        drawCenteredText(10, "Лимит: 1 сообщение в сутки (сброс в 00:00 МСК).", colors.error)
        drawFlexButton(backButton)
        drawTempMessage()
        return
    end

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
    drawFlexButton(backButton)
    gpu.setForeground(colors.text_main)
    drawCenteredText(16, "Ограничение: 1 репорт в сутки (сброс в 00:00 МСК)", colors.text_main)
    drawTempMessage()
end

local function goToBuy()
    if not playerAgreed then
        drawCenteredText(12, "Вы не приняли пользовательское соглашение!", colors.error)
        drawCenteredText(13, "Нажмите [Помощь] и ознакомьтесь с условиями.", colors.text_main)
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
    if not playerAgreed then
        drawCenteredText(12, "Вы не приняли пользовательское соглашение!", colors.error)
        drawCenteredText(13, "Нажмите [Помощь] и ознакомьтесь с условиями.", colors.text_main)
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

local function drawShopMenu()
    clear()
    drawScreenBorder()
    drawCenteredText(6, "МАГАЗИН", colors.accent_secondary)
    if not playerAgreed then
        drawCenteredText(9, "Доступ запрещён.", colors.error)
        drawCenteredText(10, "Примите соглашение, нажав [Соглашение] в главном меню.", colors.accent_main)
        drawFlexButton(backButton)
        drawTempMessage()
        return
    end
    for _, btn in pairs(shopMenuButtons) do
        drawButton(btn)
    end
    drawFlexButton(backButton)
    drawTempMessage()
end

local function drawWelcomeScreen()
    gpu.setBackground(colors.bg_main)
    gpu.fill(1, 1, 80, 25, " ")
    drawBigTitle()
    gpu.setForeground(colors.success)
    drawCenteredText(18, "↓   Встаньте на PIM   ↓", colors.accent_main)
    drawCenteredText(19, "━━━━━━━━━━━━━━━━━━━", colors.accent_main)
    gpu.setForeground(colors.text_main)
    drawCenteredText(22, "По любым вопросам пишите в Telegram: f0rb4ik", colors.text_main)
    gpu.setBackground(colors.bg_main)
    drawTempMessage()
end

local function drawAuthScreen()
    gpu.setBackground(colors.bg_main)
    gpu.fill(1, 1, 80, 25, " ")
    drawBigTitle()
    gpu.setForeground(colors.text_bright)
    drawCenteredText(18, "Авторизация....", colors.text_bright)
    gpu.setForeground(colors.text_main)
    drawCenteredText(22, "По любым вопросам пишите в Telegram: f0rb4ik", colors.text_main)
    gpu.setBackground(colors.bg_main)
    drawTempMessage()
end

local function drawMainMenu()
    clear()
    drawScreenBorder()
    if currentPlayer then
        local hello1 = "Добро пожаловать, "
        local hello2 = currentPlayer .. "!"
        local full1 = hello1 .. hello2
        local x1 = math.floor((80 - unicode.len(full1))/2) + 2
        gpu.setForeground(colors.success)
        gpu.set(x1, 4, hello1)
        gpu.setForeground(colors.text_bright)
        gpu.set(x1 + unicode.len(hello1), 4, hello2)

        local balanceText = "Баланс: " .. string.format("%.2f", coinBalance) .. " Coina ₵"
        gpu.setForeground(colors.white)
        local balanceX = math.floor((80 - unicode.len(balanceText .. " | ЭМЫ: " .. string.format("%.2f", emaBalance) .. " ۞")) / 2) + 1
        gpu.set(balanceX, 5, "Баланс: ")
        gpu.setForeground(colors.accent_main)
        gpu.set(balanceX + unicode.len("Баланс: "), 5, string.format("%.2f", coinBalance) .. " Coina ₵")
        gpu.setForeground(colors.white)
        gpu.set(balanceX + unicode.len("Баланс: ") + unicode.len(string.format("%.2f", coinBalance) .. " Coina ₵"), 5, " | ")
        gpu.setForeground(colors.tomato)
        gpu.set(balanceX + unicode.len("Баланс: ") + unicode.len(string.format("%.2f", coinBalance) .. " Coina ₵") + unicode.len(" | "), 5, "ЭМЫ: " .. string.format("%.2f", emaBalance) .. " ۞")

        if not playerAgreed then
            gpu.setForeground(colors.accent_secondary)
            if showShopDenied then
                drawCenteredText(7, "Доступ запрещён. Примите соглашение [Соглашение]", colors.error)
            else
                drawCenteredText(7, "Вы не приняли пользовательское соглашение! Нажмите [Соглашение]", colors.accent_secondary)
            end
        end

        for _, btn in pairs(menuButtons) do
            drawButton(btn)
        end
        drawBottomPanel()
    else
        drawWelcomeScreen()
    end
    drawTempMessage()
end

local function drawAccount(data)
    clear()
    drawScreenBorder()
    drawCenteredText(10, currentPlayer .. ":", colors.text_bright)
    local coin = data.balance or coinBalance
    local ema = data.emaBalance or emaBalance
    local balanceText = "Баланс: " .. string.format("%.2f", coin) .. " Coina ₵"
    gpu.setForeground(colors.white)
    local balanceX = math.floor((80 - unicode.len(balanceText .. " | ЭМЫ: " .. string.format("%.2f", ema) .. " ۞")) / 2) + 1
    gpu.set(balanceX, 12, "Баланс: ")
    gpu.setForeground(colors.accent_main)
    gpu.set(balanceX + unicode.len("Баланс: "), 12, string.format("%.2f", coin) .. " Coina ₵")
    gpu.setForeground(colors.white)
    gpu.set(balanceX + unicode.len("Баланс: ") + unicode.len(string.format("%.2f", coin) .. " Coina ₵"), 12, " | ")
    gpu.setForeground(colors.tomato)
    gpu.set(balanceX + unicode.len("Баланс: ") + unicode.len(string.format("%.2f", coin) .. " Coina ₵") + unicode.len(" | "), 12, "ЭМЫ: " .. string.format("%.2f", ema) .. " ۞")

    local transLabel = "Совершенно транзакций: "
    local transCount = tostring(data.transactions or 0)
    local fullTrans = transLabel .. transCount
    local transX = math.floor((80 - unicode.len(fullTrans)) / 2) + 1
    gpu.setForeground(colors.success)
    gpu.set(transX, 13, transLabel)
    gpu.setForeground(colors.text_bright)
    gpu.set(transX + unicode.len(transLabel), 13, transCount)

    local regLabel = "Регистрация: "
    local regDate = data.regDate or "Неизвестно"
    local fullReg = regLabel .. regDate
    local regX = math.floor((80 - unicode.len(fullReg)) / 2) + 1
    gpu.setForeground(colors.success)
    gpu.set(regX, 14, regLabel)
    gpu.setForeground(colors.text_bright)
    gpu.set(regX + unicode.len(regLabel), 14, regDate)

    local agreeLabel = "Соглашение: "
    local agreeStatus = (data.agreed or playerAgreed) and "ознакомлен" or "не ознакомлен"
    local agreeColor = (data.agreed or playerAgreed) and colors.text_bright or colors.error
    local fullAgree = agreeLabel .. agreeStatus
    local agreeX = math.floor((80 - unicode.len(fullAgree)) / 2) + 1
    gpu.setForeground(colors.success)
    gpu.set(agreeX, 15, agreeLabel)
    gpu.setForeground(agreeColor)
    gpu.set(agreeX + unicode.len(agreeLabel), 15, agreeStatus)

    drawFlexButton(backButton)
    drawTempMessage()
end

local function drawAccountLoading()
    clear()
    drawScreenBorder()
    drawCenteredText(12, "Загрузка...", colors.text_main)
    drawFlexButton(backButton)
    drawTempMessage()
end

local function retryAccountAfterTokenRefresh()
    if not currentPlayer then return end
    modem.send(serverAddress, 0xffef, serialization.serialize({op="enter", name=currentPlayer}))
    local start = os.clock()
    while os.clock() - start < 3 do
        local ev = {event.pull(0.3)}
        if ev[1] == "modem_message" then
            local sender = ev[3]
            local data = ev[6]
            if sender == serverAddress then
                local success, msg = pcall(serialization.unserialize, data)
                if success and msg and msg.op == "welcome" and msg.token then
                    currentToken = msg.token
                    coinBalance = msg.balance or 0.0
                    emaBalance = msg.emaBalance or 0.0
                    playerAgreed = msg.agreed or false
                    alreadyAuthorized = true
                    currentScreen = "account_loading"
                    accountRequestTime = os.clock()
                    drawAccountLoading()
                    modem.send(serverAddress, 0xffef, serialization.serialize({
                        op = "getAccount", name = currentPlayer, token = currentToken
                    }))
                    return
                end
            end
        elseif ev[1] == "player_off" or ev[1] == "pim_player_leave" then
            currentPlayer = nil
            currentToken = nil
            alreadyAuthorized = false
            currentScreen = "welcome"
            drawWelcomeScreen()
            return
        end
    end
    currentScreen = "menu"
    drawMainMenu()
end

local function goToAccount()
    if not currentToken then
        drawCenteredText(12, "Ошибка: нет авторизации", colors.error)
        return
    end
    currentScreen = "account_loading"
    accountRequestTime = os.clock()
    drawAccountLoading()
    modem.send(serverAddress, 0xffef, serialization.serialize({
        op = "getAccount", name = currentPlayer, token = currentToken
    }))
end

local function goToReport()
    currentScreen = "report"
    reportInput = ""
    drawReportScreen()
end

local function goToShop()
    currentScreen = "shop"
    drawShopMenu()
end

local function goToUtility()
    currentScreen = "utility"
    clear()
    drawCenteredText(8, "Полезности (в разработке)", colors.success)
    drawTempMessage()
end

local function goBackToMenu()
    showShopDenied = false
    currentScreen = "menu"
    drawMainMenu()
    updateSelectorDisplay(nil)
    pcall(selector.setSlot, 0, nil)
    pcall(selector.setSlot, 1, nil)
end

local function clearSelectorState()
    selectedItem = nil
    hoveredIndex = 0
    selectedIndex = 0
    updateSelectorDisplay(nil)
    pcall(selector.setSlot, 0, nil)
    pcall(selector.setSlot, 1, nil)
end

local function goToHelp()
    currentScreen = "agreement"
    drawAgreementScreen()
end

local function refreshAndAgree()
    if playerAgreed then
        goBackToMenu()
        return
    end
    if currentToken then
        modem.send(serverAddress, 0xffef, serialization.serialize({
            op = "agree",
            name = currentPlayer,
            token = currentToken
        }))
        drawCenteredText(20, "Отправка подтверждения...", colors.success)
    else
        goBackToMenu()
    end
end

local function main()
    loadQuests()  -- загружаем квесты при старте
    drawWelcomeScreen()
    modem.send(serverAddress, 0xffef, serialization.serialize({op="register", password=ACCESS_PASSWORD}))

    while true do
        local ev = {event.pull(0.5)}
        local e = ev[1]

        if currentScreen == "auth" then
            if os.clock() - authStartTime >= AUTH_TIMEOUT then
                currentScreen = "menu"
                drawMainMenu()
            end
        end

        if currentScreen == "account_loading" then
            if os.clock() - accountRequestTime >= ACCOUNT_TIMEOUT then
                retryAccountAfterTokenRefresh()
            end
        end

        if e == "touch" then
            local x, y = ev[3], ev[4]

            if showSellPopup and currentScreen == "sell_scan" then
                local popupWidth = 40
                local popupHeight = 10
                local popupX = math.floor((80 - popupWidth) / 2)
                local popupY = 10
                local yesBtn = {x=popupX+5, y=popupY+7, xs=13, ys=1}
                local noBtn  = {x=popupX+popupWidth-15, y=popupY+7, xs=12, ys=1}
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
            elseif showInsufficientPopup then
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
            elseif showPartialPopup then
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
            elseif showInventoryFullPopup then
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
            elseif currentScreen == "shop_buy" or currentScreen == "shop_sell" then
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

                if x >= 78 and y >= 7 and y <= 21 then
                    local total = #filteredItems
                    if total > visibleRows then
                        local clickPos = y - 6
                        listScroll = math.floor((clickPos - 1) * (total - visibleRows) / visibleRows) + 1
                        drawBuyItemsList()
                    end
                    goto continue
                end

                if y == 3 and x >= 42 and x <= 64 then
                    searchActive = true
                    searchInput = shopSearch
                    drawBuyStatic()
                    drawBuyItemsList()
                    drawBuyButtons()
                    goto continue
                end
                if y == 3 and x >= 66 and x <= 78 then
                    shopSearch = ""
                    searchInput = ""
                    searchActive = false
                    drawBuyStatic()
                    drawBuyItemsList()
                    drawBuyButtons()
                    goto continue
                end

                if isButtonClicked(backButton, x, y) then
                    currentScreen = "shop"
                    selectedIndex = 0
                    selectedItem = nil
                    hoveredIndex = 0
                    updateSelectorDisplay(nil)
                    drawShopMenu()
                    goto continue
                end

                if isButtonClicked(nextButton, x, y) then
                    if selectedItem and (currentShopMode ~= "buy" or selectedItem.qty > 0) then
                        if currentShopMode == "buy" then
                            local needCoin = selectedItem.priceCoin or 0
                            local needEma = selectedItem.priceEma or 0
                            if (needCoin > 0 and coinBalance < needCoin) or (needEma > 0 and emaBalance < needEma) then
                                showInsufficientPopup = true
                                insufficientBalanceCoin = coinBalance
                                insufficientBalanceEma = emaBalance
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
            elseif currentScreen == "purchase" then
                if (y >= 24 and y <= 24) and (x >= 19 and x <= 28) then
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
                elseif (y >= 24 and y <= 24) and (x >= 51 and x <= 61) then
                    performBuy()
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
            elseif currentScreen == "sell_scan" then
                if isButtonClicked(backButton, x, y) then
                    currentScreen = "shop_sell"
                    showSellPopup = false
                    drawBuyStatic()
                    drawBuyItemsList()
                    drawBuyButtons()
                elseif y == 13 and x >= 30 and x <= 50 then
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
                end
            elseif currentScreen == "menu" then
                for name, btn in pairs(menuButtons) do
                    if x >= btn.x and x < btn.x + btn.xs and y >= btn.y and y < btn.y + btn.ys then
                        if name == "shop" then
                            if playerAgreed then
                                goToShop()
                            else
                                showShopDenied = true
                                drawMainMenu()
                            end
                        elseif name == "util" then
                            showShopDenied = false
                            goToUtility()
                        elseif name == "account" then
                            showShopDenied = false
                            goToAccount()
                        end
                        break
                    end
                end
                if y == 24 then
                    if x >= 4 and x <= 25 then
                        showShopDenied = false
                        goToReport()
                    elseif x >= 35 and x <= 47 then
                        showShopDenied = false
                        goToHelp()
                    elseif x >= 68 and x <= 78 then
                        currentScreen = "feedbacks"
                        loadFeedbacksFromServer()
                        drawFeedbacksList()
                    end
                end
            elseif currentScreen == "agreement" then
                local btnText = "[ ПОНЯТНО ]"
                local btnW = unicode.len(btnText) + 4
                local btnX = math.floor((80 - btnW)/2) + 2
                if y == 22 and x >= btnX and x <= btnX + btnW then
                    refreshAndAgree()
                end
                if isButtonClicked(backButton, x, y) then
                    goBackToMenu()
                end
            elseif currentScreen == "account" or currentScreen == "account_loading" then
                if isButtonClicked(backButton, x, y) then
                    goBackToMenu()
                end
            elseif currentScreen == "shop" then
                for name, btn in pairs(shopMenuButtons) do
                    if x >= btn.x and x < btn.x + btn.xs and y >= btn.y and y < btn.y + btn.ys then
                        if name == "buy" then
                            goToBuy()
                        elseif name == "sell" then
                            goToSell()
                        elseif name == "bundle" then
                            -- открываем список квестов
                            drawQuestListScreen()
                        end
                        break
                    end
                end
                if isButtonClicked(backButton, x, y) then
                    goBackToMenu()
                end
            elseif currentScreen == "shop_bundle" then
                -- список квестов
                if y >= 7 and y <= 21 and x >= 2 and x <= 77 then
                    local relativeRow = y - 6
                    local clickedIndex = questListScroll + relativeRow - 1
                    local filtered = questsList
                    if questSearch ~= "" then
                        filtered = {}
                        for _, q in ipairs(questsList) do
                            if string.find(string.lower(q.name), string.lower(questSearch), 1, true) then
                                table.insert(filtered, q)
                            end
                        end
                    end
                    local quest = filtered[clickedIndex]
                    if quest then
                        questSelectedIndex = clickedIndex
                        selectedQuest = quest
                        questHoveredIndex = 0
                        drawQuestDetailsScreen(quest)   -- показываем детали
                    end
                    goto continue
                end
                if x >= 78 and y >= 7 and y <= 21 then
                    local total = #questsList
                    if total > questVisibleRows then
                        local clickPos = y - 6
                        questListScroll = math.floor((clickPos - 1) * (total - questVisibleRows) / questVisibleRows) + 1
                        drawQuestListScreen()
                    end
                    goto continue
                end
                if y == 3 and x >= 42 and x <= 64 then
                    questSearchActive = true
                    questSearchInput = questSearch
                    drawQuestListScreen()
                    goto continue
                end
                if y == 3 and x >= 66 and x <= 78 then
                    questSearch = ""
                    questSearchInput = ""
                    questSearchActive = false
                    drawQuestListScreen()
                    goto continue
                end
                if questSearchActive then
                    questSearch = questSearchInput
                    questSearchActive = false
                    questListScroll = 1
                    questSelectedIndex = 0
                    selectedQuest = nil
                    questHoveredIndex = 0
                    drawQuestListScreen()
                    goto continue
                end
                if isButtonClicked({x=5, y=24, xs=11, ys=1}, x, y) then
                    currentScreen = "shop"
                    drawShopMenu()
                    goto continue
                end
                if isButtonClicked({x=65, y=24, xs=13, ys=1}, x, y) then
                    if selectedQuest then
                        drawQuestDetailsScreen(selectedQuest)
                    end
                    goto continue
                end
            elseif currentScreen == "quest_details" then
                -- экран деталей квеста
                if isButtonClicked({x=20, y=24, xs=12, ys=1}, x, y) then
                    drawQuestListScreen()
                    goto continue
                end
                if isButtonClicked({x=50, y=24, xs=15, ys=1}, x, y) then
                    if currentQuestForDetails then
                        performBuyQuest(currentQuestForDetails)
                    end
                    goto continue
                end
            elseif currentScreen == "utility" then
                if isButtonClicked(backButton, x, y) then
                    goBackToMenu()
                end
            elseif currentScreen == "report" then
                if isButtonClicked(backButton, x, y) then
                    goBackToMenu()
                elseif canSendReport() then
                    local sendBtn = {x=20, y=14, xs=40, ys=1}
                    if isButtonClicked(sendBtn, x, y) and reportInput ~= "" then
                        if currentToken then
                            modem.send(serverAddress, 0xffef, serialization.serialize({
                                op = "report",
                                name = currentPlayer,
                                token = currentToken,
                                text = reportInput,
                                time = getRealTimeString()
                            }))
                        end
                        lastReportTime = getRealTimestamp()
                        drawCenteredText(18, "Сообщение успешно отправлено! Ожидайте ответа.", colors.success)
                        os.sleep(0.8)
                        goBackToMenu()
                    end
                end
            elseif currentScreen == "feedbacks" then
                if isButtonClicked({x=5, y=24, xs=11, ys=1}, x, y) then
                    currentScreen = "menu"
                    drawMainMenu()
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
            elseif currentScreen == "feedback_input" then
                if isButtonClicked({x=20, y=24, xs=12, ys=1}, x, y) then
                    feedbackEditMode = false
                    feedbackInput = ""
                    currentScreen = "feedbacks"
                    drawFeedbacksList()
                    goto continue
                end
                if isButtonClicked({x=46, y=24, xs=15, ys=1}, x, y) and feedbackInput ~= "" then
                    if currentToken then
                        modem.send(serverAddress, 0xffef, serialization.serialize({
                            op = "add_feedback",
                            name = currentPlayer,
                            token = currentToken,
                            text = feedbackInput,
                            time = getRealTimeString()
                        }))
                        showTempMessage("✅ Отзыв отправлен! Спасибо!", 10)
                    end
                    feedbackEditMode = false
                    feedbackInput = ""
                    currentScreen = "feedbacks"
                    drawFeedbacksList()
                    goto continue
                end
            end
        elseif e == "scroll" and (currentScreen == "shop_buy" or currentScreen == "shop_sell") then
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
        elseif e == "scroll" and currentScreen == "shop_bundle" then
            local direction = ev[5]
            local x, y = ev[3], ev[4]
            if x >= 2 and x <= 78 and y >= 7 and y <= 21 then
                if direction == -1 then
                    local maxScroll = math.max(1, #questsList - questVisibleRows + 1)
                    questListScroll = math.min(questListScroll + 1, maxScroll)
                    drawQuestListScreen()
                elseif direction == 1 then
                    questListScroll = math.max(1, questListScroll - 1)
                    drawQuestListScreen()
                end
            end
        elseif e == "mouse_move" and (currentScreen == "shop_buy" or currentScreen == "shop_sell") then
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
        elseif e == "mouse_move" and currentScreen == "shop_bundle" then
            local x, y = ev[3], ev[4]
            if y >= 7 and y <= 21 and x >= 2 and x <= 77 then
                local rel = y - 6
                local newHover = questListScroll + rel - 1
                if newHover <= #questsList and newHover ~= questHoveredIndex then
                    questHoveredIndex = newHover
                    drawQuestListScreen()
                end
            else
                if questHoveredIndex ~= 0 then
                    questHoveredIndex = 0
                    drawQuestListScreen()
                end
            end
        elseif e == "key_down" and currentScreen == "report" and canSendReport() then
            local ch = ev[3]
            if ch == 13 then
                drawReportScreen()
            elseif ch == 8 then
                reportInput = unicode.sub(reportInput, 1, -2)
                drawReportScreen()
            elseif ch >= 32 then
                reportInput = reportInput .. unicode.char(ch)
                drawReportScreen()
            end
        elseif e == "key_down" and (currentScreen == "shop_buy" or currentScreen == "shop_sell") and searchActive then
            local ch = ev[3]
            if ch == 13 then
                shopSearch = searchInput
                searchActive = false
                listScroll = 1
                selectedIndex = 0
                selectedItem = nil
                hoveredIndex = 0
                drawBuyStatic()
                drawBuyItemsList()
                drawBuyButtons()
            elseif ch == 8 then
                searchInput = unicode.sub(searchInput, 1, -2)
                shopSearch = searchInput
                drawBuyStatic()
                drawBuyItemsList()
                drawBuyButtons()
            elseif ch >= 32 then
                searchInput = searchInput .. unicode.char(ch)
                shopSearch = searchInput
                drawBuyStatic()
                drawBuyItemsList()
                drawBuyButtons()
            end
            goto continue
        elseif e == "key_down" and currentScreen == "shop_bundle" and questSearchActive then
            local ch = ev[3]
            if ch == 13 then
                questSearch = questSearchInput
                questSearchActive = false
                questListScroll = 1
                questSelectedIndex = 0
                selectedQuest = nil
                questHoveredIndex = 0
                drawQuestListScreen()
            elseif ch == 8 then
                questSearchInput = unicode.sub(questSearchInput, 1, -2)
                questSearch = questSearchInput
                drawQuestListScreen()
            elseif ch >= 32 then
                questSearchInput = questSearchInput .. unicode.char(ch)
                questSearch = questSearchInput
                drawQuestListScreen()
            end
            goto continue
        elseif e == "key_down" and currentScreen == "feedback_input" and feedbackEditMode then
            local ch = ev[3]
            if ch == 13 then
                if feedbackInput ~= "" and currentToken then
                    modem.send(serverAddress, 0xffef, serialization.serialize({
                        op = "add_feedback",
                        name = currentPlayer,
                        token = currentToken,
                        text = feedbackInput,
                        time = getRealTimeString()
                    }))
                    showTempMessage("✅ Отзыв отправлен! Спасибо!", 10)
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
        elseif e == "player_on" or e == "pim" or e == "pim_player_enter" then
            local playerName = ev[2] or "Игрок"
            currentPlayer = playerName:match("^%s*(.-)%s*$") or playerName
            if alreadyAuthorized then
                if currentScreen == "auth" or currentScreen == "account_loading" then
                    currentScreen = "menu"
                    drawMainMenu()
                end
                processPendingOnLogin(currentPlayer)
            elseif currentToken then
                alreadyAuthorized = true
                if currentScreen == "auth" or currentScreen == "account_loading" then
                    currentScreen = "menu"
                    drawMainMenu()
                end
                processPendingOnLogin(currentPlayer)
            else
                coinBalance = 0.0
                emaBalance = 0.0
                playerAgreed = false
                currentScreen = "auth"
                authStartTime = os.clock()
                drawAuthScreen()
                modem.send(serverAddress, 0xffef, serialization.serialize({op="enter", name=currentPlayer}))
            end
        elseif e == "player_off" or e == "pim_player_leave" then
            currentPlayer = nil
            currentToken = nil
            alreadyAuthorized = false
            currentScreen = "welcome"
            selectedItem = nil
            hoveredIndex = 0
            selectedIndex = 0
            pcall(updateSelectorDisplay, nil)
            pcall(selector.setSlot, 0, nil)
            pcall(selector.setSlot, 1, nil)
            drawWelcomeScreen()
        elseif e == "modem_message" then
            local sender = ev[3]
            local data = ev[6]
            if sender == serverAddress then
                local success, msg = pcall(serialization.unserialize, data)
                if success and msg then
                    if msg.op == "welcome" and msg.token then
                        currentToken = msg.token
                        coinBalance = msg.balance or 0.0
                        emaBalance = msg.emaBalance or 0.0
                        playerTransactions = msg.transactions or 0
                        playerRegDate = msg.regDate or ""
                        playerAgreed = msg.agreed or false
                        alreadyAuthorized = true
                        if selector then
                            modem.send(serverAddress, 0xffef, serialization.serialize({
                                op = "selector_status",
                                name = currentPlayer,
                                token = currentToken,
                                available = true
                            }))
                        end
                        if currentScreen == "auth" or currentScreen == "account_loading" then
                            currentScreen = "menu"
                            drawMainMenu()
                        end
                        processPendingOnLogin(currentPlayer)
                    elseif msg.op == "accountData" then
                        if msg.error then
                            retryAccountAfterTokenRefresh()
                        else
                            if currentScreen == "account_loading" then
                                currentScreen = "account"
                                playerAgreed = msg.data.agreed or false
                                drawAccount(msg.data)
                            end
                        end
                    elseif msg.op == "agree" then
                        if msg.success then
                            playerAgreed = true
                            showShopDenied = false
                            drawCenteredText(20, "Спасибо! Теперь вам доступен магазин.", colors.success)
                            os.sleep(0.8)
                            drawMainMenu()
                            currentScreen = "menu"
                        elseif msg.error and msg.message == "Токен устарел" then
                            drawCenteredText(20, "Сессия устарела. Обновление...", colors.accent_secondary)
                            os.sleep(1)
                            modem.send(serverAddress, 0xffef, serialization.serialize({op="enter", name=currentPlayer}))
                            local start = os.clock()
                            local refreshed = false
                            while os.clock() - start < 3 do
                                local evt = {event.pull(0.3)}
                                if evt[1] == "modem_message" then
                                    local s, d = evt[3], evt[6]
                                    if s == serverAddress then
                                        local ok, m = pcall(serialization.unserialize, d)
                                        if ok and m and m.op == "welcome" and m.token then
                                            currentToken = m.token
                                            coinBalance = m.balance or 0.0
                                            emaBalance = m.emaBalance or 0.0
                                            playerAgreed = m.agreed or false
                                            refreshed = true
                                            break
                                        end
                                    end
                                elseif evt[1] == "player_off" or evt[1] == "pim_player_leave" then
                                    break
                                end
                            end
                            if refreshed then
                                modem.send(serverAddress, 0xffef, serialization.serialize({
                                    op = "agree",
                                    name = currentPlayer,
                                    token = currentToken
                                }))
                                drawCenteredText(20, "Повторная отправка...", colors.success)
                            else
                                drawCenteredText(20, "Не удалось обновить сессию", colors.error)
                                os.sleep(2)
                                drawMainMenu()
                                currentScreen = "menu"
                            end
                        else
                            drawCenteredText(20, "Ошибка: " .. (msg.message or "неизвестная"), colors.error)
                            os.sleep(2)
                            drawMainMenu()
                            currentScreen = "menu"
                        end
                    elseif msg.op == "add_buy_item" then
                        local ok, err = pcall(function()
                            local buyItems = dofile("/home/buy_items.lua")
                            if type(buyItems) ~= "table" then buyItems = {} end
                            local newItem = {
                                internalName = msg.internalName,
                                displayName = msg.displayName,
                                price_coin = msg.price_coin or 0,
                                price_ema = msg.price_ema or 0,
                            }
                            if msg.damage and msg.damage ~= 0 then
                                newItem.damage = msg.damage
                            end
                            table.insert(buyItems, newItem)
                            local file = io.open("/home/buy_items.lua", "w")
                            file:write("return " .. serialization.serialize(buyItems))
                            file:close()
                            buyItemsData = dofile("/home/buy_items.lua")
                            buyItemMap = {}
                            for _, item in ipairs(buyItemsData) do
                                local dmg = item.damage or 0
                                local key = item.internalName .. ":" .. dmg
                                buyItemMap[key] = item
                            end
                            if currentScreen == "shop_buy" then
                                loadBuyItems()
                                drawBuyStatic()
                                drawBuyItemsList()
                                drawBuyButtons()
                            end
                        end)
                        if ok then
                            modem.send(sender, 0xffef, serialization.serialize({op = "add_buy_item_response", success = true}))
                            showTempMessage("✅ Предмет добавлен: " .. msg.displayName, 10)
                        else
                            modem.send(sender, 0xffef, serialization.serialize({op = "add_buy_item_response", success = false, error = tostring(err)}))
                            showTempMessage("❌ Ошибка добавления: " .. tostring(err), 10)
                        end
                        goto continue
                    elseif msg.op == "add_buy_item_response" then
                        if msg.success then
                            print("Предмет успешно добавлен на сервере")
                        else
                            print("Ошибка добавления предмета: " .. (msg.error or "неизвестная"))
                        end
                    elseif msg.op == "reload_buy_items" then
                        buyItemsData = dofile("/home/buy_items.lua")
                        buyItemMap = {}
                        for _, item in ipairs(buyItemsData) do
                            local dmg = item.damage or 0
                            local key = item.internalName .. ":" .. dmg
                            buyItemMap[key] = item
                        end
                        if currentScreen == "shop_buy" then
                            loadBuyItems()
                            drawBuyStatic()
                            drawBuyItemsList()
                            drawBuyButtons()
                        end
                        goto continue
                    elseif msg.op == "feedbacks_list" then
                        feedbacks = msg.feedbacks or {}
                        playerHasFeedback = msg.hasFeedback or false
                        feedbacksPage = 1
                        if currentScreen == "feedbacks" then
                            drawFeedbacksList()
                        end
                        goto continue
                    elseif msg.op == "add_feedback_response" then
                        if msg.success then
                            showTempMessage("✅ Отзыв добавлен!", 10)
                            loadFeedbacksFromServer()
                        else
                            showTempMessage("❌ Ошибка: " .. (msg.error or "неизвестная"), 10)
                        end
                        goto continue
                    end
                end
            end
        end
        ::continue::
    end
end

local function drawCrashPopup(errText)
    local popupWidth = 50
    local popupHeight = 8
    local popupX = math.floor((80 - popupWidth) / 2)
    local popupY = 9

    gpu.setBackground(colors.bg_main)
    gpu.fill(1, 1, 80, 25, " ")
    gpu.setBackground(colors.bg_main)

    drawPopupBorder(popupX, popupY, popupWidth, popupHeight, colors.error)

    gpu.setForeground(colors.error)
    local title = "ОШИБКА"
    local titleX = popupX + math.floor((popupWidth - unicode.len(title)) / 2)
    gpu.set(titleX, popupY, title)

    gpu.setForeground(colors.text_main)
    local shortErr = errText:sub(1, popupWidth - 4)
    local errX = popupX + 2
    gpu.set(errX, popupY + 2, shortErr)

    for i = 3, 1, -1 do
        gpu.setForeground(colors.success)
        local msg = "Перезагрузка через " .. i .. " сек..."
        local msgX = popupX + math.floor((popupWidth - unicode.len(msg)) / 2)
        gpu.set(msgX, popupY + 5, msg)
        os.sleep(1)
    end
end

main()
