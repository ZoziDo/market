local component = require("component")
local event = require("event")
local gpu = component.gpu
local unicode = require("unicode")
local serialization = require("serialization")
local keyboard = require("keyboard")

-- Загружаем внешние файлы
local shopData = dofile("/home/shop_items.lua")
local sellItems = shopData.sellItems
local vanillaItems = shopData.vanillaItems or {}

local buyItemsData = dofile("/home/buy_items.lua")
local buyItemMap = {}
for _, item in ipairs(buyItemsData) do
  buyItemMap[item.internalName] = item
end

local drawAgreementScreen = dofile("/home/agreement.lua")   -- экран соглашения

local modem = component.modem
local pimList = {}
for addr in component.list("pim") do table.insert(pimList, addr) end
local pimAddr = pimList[1]
local PUSH_DIRECTION = "down"
local PULL_DIRECTION = "up"

-- ==================== ITEM SELECTOR ====================
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

local function debugPlayerInventory()
    if not pimAddr then return end
    print("=== СОДЕРЖИМОЕ ИНВЕНТАРЯ (PIM) ===")
    for slot = 1, 36 do
        local stack = component.invoke(pimAddr, "getStackInSlot", slot)
        if stack then
            local qty = stack.size or stack.qty or 0
            if qty > 0 then
                local rawName = stack.label or stack.name or "???"
                local cleanName = rawName:gsub("§.", "")
                print(string.format("Слот %2d | %3d шт. | %s", slot, qty, cleanName))
            end
        end
    end
end

modem.open(0xffef)
modem.open(0xfffe)

local serverAddress = "535305a9-37c9-4645-b7c4-46204187ee7b"
local currentPlayer, currentToken = nil, nil
local resBalance = 0.0
local emBalance = 0.0
local playerTransactions = 0
local playerRegDate = ""
local playerAgreed = false          -- <-- ДОБАВЛЕНО: СТАТУС СОГЛАСИЯ
local currentScreen = "welcome"
local authStartTime = 0
local AUTH_TIMEOUT = 3
local accountRequestTime = 0
local ACCOUNT_TIMEOUT = 3
local alreadyAuthorized = false

-- Переменные магазина
local shopItems = {}
local shopSearch = ""
local searchActive = false
local searchInput = ""
local showOnlyAvailable = false
local currentShopMode = "buy"
local buyFilterMode = "all"

local blacklist = {
    ["customnpcs:npcMoney"] = true,
}

local listScroll = 1
local visibleRows = 12
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

-- Переменные репорта
local reportInput = ""
local lastReportTime = nil
local showShopDenied = false   -- флаг для смены сообщения

-- ========== ЭКРАН ==========
gpu.setResolution(80, 25)
gpu.setBackground(0x000000)

-- ========== КРУПНЫЙ ШРИФТ ==========
local function drawBigTitle()
  gpu.setForeground(0xff7300)
  local darkonLines = {
    "  ██████╗ ██████╗  █████╗ ██████╗ ██╗  ██╗ ██████╗ ███╗   ██╗",
    "  ██╔══██╗██╔══██╗██╔══██╗██╔══██╗██║ ██╔╝██╔═══██╗████╗  ██║",
    "  ██║  ██║██████╔╝███████║██║  ██║█████╔╝ ██║   ██║██╔██╗ ██║",
    "  ██║  ██║██╔══██╗██╔══██║██║  ██║██╔═██╗ ██║   ██║██║╚██╗██║",
    "  ██████╔╝██║  ██║██║  ██║██████╔╝██║  ██╗╚██████╔╝██║ ╚████║",
  }
  local darkonOffset = 47
  local darkonX = math.floor((80 - #darkonLines[1]) / 2) + darkonOffset
  for i, line in ipairs(darkonLines) do gpu.set(darkonX, 4 + i, line) end

  local shopLines = {
    "  ███████╗ ██╗  ██╗  ██████╗  ██████╗ ",
    "  ██╔════╝ ██║  ██║ ██╔═══██╗ ██╔══██╗",
    "  ███████╗ ███████║ ██║   ██║ ██████╔╝",
    "  ╚════██║ ██╔══██║ ██║   ██║ ██╔═══╝ ",
    "  ███████║ ██║  ██║ ╚██████╔╝ ██║     "
  }
  local shopOffset = 28
  local shopX = math.floor((80 - #shopLines[1]) / 2) + shopOffset
  for i, line in ipairs(shopLines) do gpu.set(shopX, 10 + i, line) end
end

-- ========== ФУНКЦИИ ЭКРАНА ==========
local function clear() gpu.setBackground(0x000000) gpu.fill(1,1,80,25," ") end
local function drawCenteredText(y, text, color)
  gpu.setForeground(color or 0xFFFFFF)
  local x = math.floor((80 - unicode.len(text)) / 2) + 1
  gpu.set(x, y, text)
end

-- Кнопки главного меню
local menuButtons = {
  shop = {x=31,xs=20,y=9,ys=3,text="Магазин",tx=6,ty=1,bg=0x444444,fg=0x00FF88},
  util = {x=31,xs=20,y=13,ys=3,text="Полезности",tx=5,ty=1,bg=0x444444,fg=0x00FF88},
  account = {x=31,xs=20,y=17,ys=3,text="Аккаунт",tx=6,ty=1,bg=0x444444,fg=0x00FF88}
}
local function drawButton(btn)
  gpu.setBackground(btn.bg) gpu.fill(btn.x,btn.y,btn.xs,btn.ys," ")
  gpu.setForeground(btn.fg) gpu.set(btn.x+btn.tx, btn.y+btn.ty, btn.text)
  gpu.setBackground(0x000000)
end

local function drawBottomPanel()
  gpu.setForeground(0xcc3342) 
  gpu.set(4, 23, "[Сообщить о проблеме]")
  gpu.set(35, 23, "[Соглашение]")           -- правее, например 33
  gpu.set(70, 23, "[Отзывы]")
end

local function drawFlexButton(btn)
  gpu.setBackground(btn.bg)
  gpu.fill(btn.x, btn.y, btn.xs, btn.ys, " ")
  gpu.setForeground(btn.fg)
  local textX = btn.x + math.floor((btn.xs - unicode.len(btn.text)) / 2)
  local textY = btn.y + math.floor((btn.ys - 1) / 2)
  gpu.set(textX, textY, btn.text)
  gpu.setBackground(0x000000)
end

local backButton = {
  text = "Назад",
  x = nil, y = 24,
  xs = unicode.len("Назад") + 6,
  ys = 1,
  bg = 0x333333,
  fg = 0xff7300
}
backButton.x = math.floor((80 - backButton.xs) / 2) + 1

local function isButtonClicked(btn, x, y)
  return y >= btn.y and y < btn.y + btn.ys and
         x >= btn.x and x < btn.x + btn.xs
end

local searchButton = {text = "Поиск...", x=3, y=21, xs=20, ys=1, bg=0x333333, fg=0x00aaff}
local filterButton  = {text = "● В наличии", x=33, y=21, xs=14, ys=1, bg=0x333333, fg=0x00ff00}
local nextButton    = {text = "Далее", x=70, y=21, xs=7, ys=1, bg=0x333333, fg=0x888888}

local shopMenuButtons = {
  buy = {x=31,xs=20,y=9,ys=3,text="Покупка",tx=6,ty=1,bg=0x444444,fg=0x00FF88},
  sell = {x=31,xs=20,y=13,ys=3,text="Пополнение",tx=5,ty=1,bg=0x444444,fg=0x00FF88},
  bundle = {x=31,xs=20,y=17,ys=3,text="Наборы/Квесты",tx=4,ty=1,bg=0x444444,fg=0x00FF88}
}

-- ==================== ПРОВЕРКА СБРОСА РЕПОРТА ====================
local function canSendReport()
  if not lastReportTime then return true end
  local now = os.time()
  local reportDate = os.date("*t", lastReportTime)
  local nowDate = os.date("*t", now)
  if reportDate.day ~= nowDate.day or reportDate.month ~= nowDate.month or reportDate.year ~= nowDate.year then
    return true
  end
  return false
end

-- ========== ВСПОМОГАТЕЛЬНАЯ ФУНКЦИЯ ==========
local function getActualItemQuantity(internalName)
    if not component.isAvailable("me_interface") then return 0 end
    local me = component.me_interface
    local items = me.getItemsInNetwork()
    local total = 0
    for _, meItem in ipairs(items) do
        if meItem.name == internalName then
            total = total + (meItem.size or 0)
        end
    end
    return total
end

-- ==================== ЗАГРУЗКА ПРЕДМЕТОВ ====================
local function loadBuyItems()
  if not component.isAvailable("me_interface") then return end
  local me = component.me_interface
  local rawItems = me.getItemsInNetwork()
  local tempShopItems = {}
  local knownItems = {}
  for _, item in ipairs(shopItems) do
    knownItems[item.internalName] = true
  end
  local newFound = {}

  for _, meItem in ipairs(rawItems) do
    local name = meItem.name

    if blacklist[name] then
      goto continue
    end

    local qty = meItem.size or 0
    if qty == 0 then goto continue end

    local mapping = buyItemMap[name]
    if not mapping then
      goto continue
    end

    local displayName = mapping.displayName or (meItem.label or name)
    local price = mapping.price or 0
    local currency = mapping.currency or "res"

    if price <= 0 then
      goto continue
    end

    if tempShopItems[name] then
      tempShopItems[name].qty = tempShopItems[name].qty + qty
    else
      tempShopItems[name] = {
        internalName = name,
        displayName = displayName,
        qty = qty,
        price = price,
        currency = currency,
        canBuy = true
      }
    end
    ::continue::
  end

  local newShopItems = {}
  for _, itemData in pairs(tempShopItems) do
    table.insert(newShopItems, itemData)
    if not knownItems[itemData.internalName] and itemData.qty > 0 then
      table.insert(newFound, {name = itemData.displayName, qty = itemData.qty})
    end
  end

  if #newFound > 0 and currentToken then
    modem.send(serverAddress, 0xffef, serialization.serialize({
      op = "new_items",
      name = currentPlayer,
      token = currentToken,
      items = newFound
    }))
  end

  shopItems = newShopItems
  table.sort(shopItems, function(a, b) return a.displayName < b.displayName end)
end

local function loadSellItems()
  shopItems = {}
  for _, item in ipairs(sellItems) do
    table.insert(shopItems, {
      displayName = item.displayName or item.name,
      internalName = item.internalName or item.name,
      qty = item.qty,
      price = item.price
    })
  end
end

-- ==================== СКАНИРОВАНИЕ И ИЗЪЯТИЕ ====================
local function scanPlayerInventory(targetName)
    if not pimAddr then return 0 end
    local total = 0
    for slot = 1, 36 do
        local stack = component.invoke(pimAddr, "getStackInSlot", slot)
        if stack then
            local qty = stack.size or stack.qty or 0
            if qty > 0 then
                local rawName = stack.label or stack.name or ""
                local cleanName = rawName:gsub("§.", "")
                if cleanName == targetName or string.find(cleanName, targetName, 1, true) then
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

local function extractToME(targetName, amount)
    if not pimAddr or amount <= 0 then return 0 end
    local extracted = 0
    for slot = 1, 36 do
        if extracted >= amount then break end
        local stack = component.invoke(pimAddr, "getStackInSlot", slot)
        if stack then
            local qty = stack.size or stack.qty or 0
            if qty > 0 then
                local rawName = stack.label or stack.name or ""
                local cleanName = rawName:gsub("§.", "")
                -- Сравниваем имена: пробуем точное совпадение, затем очистка от minecraft:
                local match = (cleanName == targetName) or (cleanName == "minecraft:" .. targetName) or (cleanName:find(targetName, 1, true) and cleanName:match(targetName))
                if match then
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

-- ========== ФИЛЬТРАЦИЯ ==========
local function getFilteredItems()
  local filtered = {}
  for _, item in ipairs(shopItems) do
    local matchesSearch = (shopSearch == "" or string.find(string.lower(item.displayName or item.internalName), string.lower(shopSearch), 1, true))
    local matchesAvailability = true
    if currentShopMode == "buy" then
      matchesAvailability = (not showOnlyAvailable) or (item.qty > 0)
    end
    local matchesVanilla = true
    if currentShopMode == "sell" and buyFilterMode == "vanilla" then
      matchesVanilla = false
      for _, vname in ipairs(vanillaItems) do
        if (item.internalName or item.name) == vname then
          matchesVanilla = true
          break
        end
      end
    end
    if matchesSearch and matchesAvailability and matchesVanilla then
      table.insert(filtered, item)
    end
  end
  maxItemWidth = 0
  for _, item in ipairs(filtered) do
    local len = unicode.len(item.displayName or item.internalName or "")
    if len > maxItemWidth then maxItemWidth = len end
  end
  return filtered
end

-- ========== ОТРИСОВКА СПИСКА ==========
local function drawBuyStatic()
  clear()
  local resText = "Баланс: " .. string.format("%.2f Ресов $ | ", resBalance)
  local emText = string.format("%.2f Эмов *", emBalance)
  gpu.setForeground(0x00ff88)
  gpu.set(3, 1, resText)
  gpu.setForeground(0xff7300)
  gpu.set(3 + unicode.len(resText), 1, emText)

  if currentShopMode == "buy" then
    gpu.setForeground(0xff7300)
    gpu.set(3, 3, "Магазин продаёт")
  else
    gpu.setForeground(0xff7300)
    gpu.set(3, 3, "Магазин покупает")
  end

  gpu.setBackground(0x222222)
  gpu.fill(2, 4, 76, 1, " ")
  gpu.setForeground(0xffaa00)
  gpu.set(3, 4, "Название")
  gpu.set(42, 4, "Кол-во")
  gpu.set(65, 4, "Цена")
  gpu.setBackground(0x000000)

  gpu.setForeground(0x444444)
  gpu.set(3, 5, string.rep("─", 74))
  gpu.set(3, 18, string.rep("─", 74))
  drawCenteredText(19, "Категория", 0x888888)
  gpu.set(3, 23, string.rep("─", 74))
  drawFlexButton(backButton)
end

local function drawSingleRow(y, item, isHovered, isSelected, itemIndex)
  if not item then return end
  local bg, fg
  if currentShopMode == "buy" and item.qty == 0 then
    bg = 0x111111
    fg = 0x555555
  elseif isSelected then
    bg = 0x225577
  elseif isHovered then
    bg = 0x446688
  elseif itemIndex % 2 == 1 then
    bg = 0x111111
  else
    bg = 0x1a1a1a
  end
  if currentShopMode == "buy" then
    if item.qty > 0 then fg = 0x00ffcc else fg = 0x555555 end
  else
    fg = 0x00ffcc
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
    if item.qty > 0 then gpu.setForeground(0xffffff) else gpu.setForeground(0x555555) end
  else
    gpu.setForeground(0xffffff)
  end
  gpu.set(42, y, tostring(item.qty))
  if currentShopMode == "buy" then
    local currencySym = (item.currency == "em") and " Э" or " $"
    gpu.set(65, y, string.format("%.2f", item.price) .. currencySym)
  else
    gpu.set(65, y, string.format("%.2f", item.price))
  end
  gpu.setBackground(0x000000)
end

local function drawScrollBar()
  local total = #filteredItems
  local barX = 78
  local barY = 6
  local barHeight = 12
  gpu.setBackground(0x000000)
  gpu.fill(barX, barY, 2, barHeight, " ")
  if total <= visibleRows then return end
  gpu.setBackground(0x111111)
  gpu.fill(barX, barY, 2, barHeight, " ")
  local thumbHeight = math.max(2, math.floor(barHeight * visibleRows / total))
  local maxPos = barHeight - thumbHeight
  local thumbPos = math.floor((listScroll - 1) * maxPos / (total - visibleRows)) + 1
  thumbPos = math.min(thumbPos, maxPos + 1)
  gpu.setBackground(0x00aaff)
  gpu.fill(barX, barY + thumbPos - 1, 2, thumbHeight, " ")
  gpu.setBackground(0x000000)
end

local function drawBuyItemsList()
  local filtered = getFilteredItems()
  filteredItems = filtered
  local maxScroll = math.max(1, #filtered - visibleRows + 1)
  listScroll = math.max(1, math.min(listScroll, maxScroll))
  gpu.setBackground(0x000000)
  gpu.fill(2, 6, 78, visibleRows, " ")
  for i = 1, visibleRows do
    local itemIndex = listScroll + i - 1
    local item = filtered[itemIndex]
    if not item then break end
    local y = 5 + i
    local isSelected = (itemIndex == selectedIndex)
    local isHovered = (itemIndex == hoveredIndex)
    drawSingleRow(y, item, isHovered, isSelected, itemIndex)
  end
  drawScrollBar()
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
      gpu.copy(2, 7, 76, visibleRows - 1, 0, -1)
      gpu.setBackground(0x000000)
      gpu.fill(2, 17, 76, 1, " ")
      local newIdx = newScroll + visibleRows - 1
      if newIdx <= total then
        drawSingleRow(17, filtered[newIdx], (newIdx == hoveredIndex), (newIdx == selectedIndex), newIdx)
      end
    else
      gpu.copy(2, 6, 76, visibleRows - 1, 0, 1)
      gpu.setBackground(0x000000)
      gpu.fill(2, 6, 76, 1, " ")
      local newIdx = newScroll
      if newIdx >= 1 then
        drawSingleRow(6, filtered[newIdx], (newIdx == hoveredIndex), (newIdx == selectedIndex), newIdx)
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
  if searchActive then
    local displayText = unicode.sub(searchInput, -16)
    searchButton.text = displayText .. "_"
  else
    searchButton.text = "Поиск..."
  end
  if currentShopMode == "sell" then
    if buyFilterMode == "all" then
      filterButton.text = "Все"
      filterButton.fg = 0x00ff00
    else
      filterButton.text = "Vanilla"
      filterButton.fg = 0xffaa00
    end
  else
    if showOnlyAvailable then
      filterButton.text = "● В наличии"
      filterButton.fg = 0x00ff00
    else
      filterButton.text = "● В наличии"
      filterButton.fg = 0xff0000
    end
  end
  if selectedItem and (currentShopMode ~= "buy" or selectedItem.qty > 0) then
    nextButton.fg = 0xffaa00
  else
    nextButton.fg = 0x888888
  end
  drawFlexButton(searchButton)
  local filterBg = filterButton.bg
  local filterX = filterButton.x
  local filterY = filterButton.y
  local filterXs = 15
  local filterYs = filterButton.ys
  local filterText = filterButton.text
  local filterFg = filterButton.fg
  gpu.setBackground(filterBg)
  gpu.fill(filterX, filterY, filterXs, filterYs, " ")
  gpu.setForeground(filterFg)
  local filterTextX = filterX + math.floor((filterXs - unicode.len(filterText)) / 2)
  local filterTextY = filterY + math.floor((filterYs - 1) / 2)
  gpu.set(filterTextX, filterTextY, filterText)
  gpu.setBackground(0x000000)
  drawFlexButton(nextButton)
end

-- ========== ЭКРАН ПОКУПКИ ==========
local function drawPurchaseScreen()
  currentScreen = "purchase"
  clear()
  local resText = "Баланс: " .. string.format("%.2f Ресов $ | ", resBalance)
  local emText = string.format("%.2f Эмов *", emBalance)
  gpu.setForeground(0x00ff88)
  gpu.set(3, 1, resText)
  gpu.setForeground(0xff7300)
  gpu.set(3 + unicode.len(resText), 1, emText)

  gpu.setForeground(0x00ff88)
  gpu.set(3, 3, "Имя предмета: ")
  gpu.setForeground(0xffffff)
  gpu.set(18, 3, purchaseItem.displayName)

  gpu.setForeground(0x00ff88)
  gpu.set(55, 3, "Доступно: ")
  gpu.setForeground(0xffffff)
  gpu.set(66, 3, tostring(purchaseItem.qty))

  local total = (purchaseItem.price or 0.0) * purchaseQuantity
  local currencySym = (purchaseItem.currency == "em") and "Э" or "$"
  gpu.setForeground(0x00ff88)
  gpu.set(3, 5, "На сумму: ")
  gpu.setForeground(0xff0000)
  gpu.set(14, 5, string.format("%.2f", total) .. " " .. currencySym)

  gpu.setForeground(0x00ff88)
  gpu.set(55, 5, "Цена: ")
  gpu.setForeground(0x00ff88)
  gpu.set(62, 5, string.format("%.2f", purchaseItem.price) .. " " .. currencySym)

  gpu.setForeground(0x00ff88)
  gpu.set(3, 7, "Кол-во: ")
  gpu.setForeground(0xffffff)
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
      gpu.setBackground(0x222222)
      gpu.fill(x, y, btnW, btnH, " ")
      gpu.setForeground(0xffaa00)
      local tx = x + math.floor((btnW - unicode.len(text)) / 2)
      local ty = y
      gpu.set(tx, ty, text)
    end
  end
  local backBtn = {x = 18, y = 23, xs = 10, ys = 1, text = "Назад", bg = 0x333333, fg = 0xff7300}
  local buyBtn  = {x = 51, y = 23, xs = 10, ys = 1, text = "Купить", bg = 0x333333, fg = 0x00ff88}
  drawFlexButton(backBtn)
  drawFlexButton(buyBtn)
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
  purchaseQuantity = 0
  drawPurchaseScreen()
end

-- ========== ПРОДАЖА ==========
local function drawSellPopup()
  local popupWidth = 40
  local popupHeight = 10
  local popupX = math.floor((80 - popupWidth) / 2)
  local popupY = 10

  gpu.setBackground(0x000000)
  gpu.setForeground(0xffffff)
  gpu.fill(popupX, popupY, popupWidth, popupHeight, " ")
  gpu.setBackground(0x333333)
  gpu.fill(popupX+1, popupY+1, popupWidth-2, popupHeight-2, " ")

  local name = sellConfirmItem.displayName
  local totalFound = foundAmount
  local value = totalFound * sellConfirmItem.price
  local currency = (sellConfirmItem.internalName == "npcMoney") and "Эмов" or "$"

  gpu.setForeground(0xffffff)
  gpu.set(popupX+14, popupY+1, "Подтверждение")
  gpu.setForeground(0xffaa00)
  gpu.set(popupX+3, popupY+3, "Магазин заберёт: " .. totalFound)
  gpu.set(popupX+3, popupY+4, name .. " x" .. totalFound)
  gpu.setForeground(0x00ff88)
  gpu.set(popupX+3, popupY+5, "Вы получите: " .. string.format("%.2f", value) .. " " .. currency)

  local yesBtn = {x=popupX+5, y=popupY+7, xs=13, ys=1, text="[ Принять ]", bg=0x004400, fg=0x00ff88}
  local noBtn  = {x=popupX+popupWidth-15, y=popupY+7, xs=12, ys=1, text="[ Отмена ]", bg=0x440000, fg=0xff5555}
  drawFlexButton(yesBtn)
  drawFlexButton(noBtn)
end

local function drawSellScanScreen()
  currentScreen = "sell_scan"
  clear()
  local resText = "Баланс: " .. string.format("%.2f Ресов $ | ", resBalance)
  local emText = string.format("%.2f Эмов *", emBalance)
  gpu.setForeground(0x00ff88)
  gpu.set(3, 1, resText)
  gpu.setForeground(0xff7300)
  gpu.set(3 + unicode.len(resText), 1, emText)

  gpu.setForeground(0x00ff88)
  gpu.set(3, 3, "Имя предмета: ")
  gpu.setForeground(0xffffff)
  gpu.set(18, 3, sellConfirmItem.displayName)

  gpu.setForeground(0x00ff88)
  gpu.set(55, 3, "Цена: ")
  gpu.setForeground(0xffffff)
  gpu.set(62, 3, string.format("%.2f", sellConfirmItem.price))

  gpu.setForeground(0x00ff88)
  gpu.set(3, 5, "Можно продать: ")
  gpu.setForeground(0xffffff)
  gpu.set(18, 5, tostring(sellConfirmItem.qty))

  gpu.setForeground(0xffaa00)
  local scanText = "Сканировать на наличие предмета:"
  local scanX = math.floor((80 - unicode.len(scanText)) / 2)
  gpu.set(scanX, 11, scanText)

  local slotBtn = {x=30, y=13, xs=20, ys=1, text="1 слот", bg=0x333333, fg=0xaaaaaa}
  local allBtn  = {x=30, y=15, xs=20, ys=1, text="Весь инвентарь", bg=0x333333, fg=0x00ff88}
  drawFlexButton(slotBtn)
  drawFlexButton(allBtn)
  drawFlexButton(backButton)

  if showSellPopup and sellConfirmItem then
    drawSellPopup()
  end
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
    drawCenteredText(17, "Сначала примите пользовательское соглашение", 0xff0000)
    os.sleep(2)
    currentScreen = "menu"
    drawMainMenu()
    return
  end

  showSellPopup = false
  drawSellScanScreen()
  drawCenteredText(17, "Выполняется пополнение...", 0x00ff88)
  os.sleep(0.6)

  local realExtracted = extractToME(sellConfirmItem.internalName, foundAmount)
  if realExtracted == 0 then
    drawCenteredText(17, "Не удалось изъять предметы! Проверьте инвентарь.", 0xff0000)
    os.sleep(2.5)
    currentScreen = "shop_sell"
    drawBuyStatic()
    drawBuyItemsList()
    drawBuyButtons()
    return
  end

  local value = realExtracted * sellConfirmItem.price
  local currency = (sellConfirmItem.internalName == "npcMoney") and "em" or "res"

  if currency == "em" then
    emBalance = emBalance + value
  else
    resBalance = resBalance + value
  end
  playerTransactions = playerTransactions + 1

  if currentToken then
    modem.send(serverAddress, 0xffef, serialization.serialize({
      op = "sell",
      name = currentPlayer,
      token = currentToken,
      item = sellConfirmItem.displayName,
      qty = realExtracted,
      value = value,
      currency = currency
    }))
  end

  local currencyName = (sellConfirmItem.internalName == "npcMoney") and "Эмов" or "Ресов"
  gpu.setBackground(0x000000)
  gpu.fill(1, 17, 80, 1, " ")
  drawCenteredText(17, "Успешно! +" .. string.format("%.2f", value) .. " " .. currencyName, 0x00ff88)
  os.sleep(2.5)

  currentScreen = "shop_sell"
  showSellPopup = false
  drawBuyStatic()
  drawBuyItemsList()
  drawBuyButtons()
end

-- ========== ПОКУПКА ==========
local function performBuy()
  -- Проверка согласия
  if not playerAgreed then
    drawCenteredText(20, "Сначала примите пользовательское соглашение (Помощь)", 0xff0000)
    os.sleep(2)
    currentScreen = "menu"
    drawMainMenu()
    return
  end

  local me = component.me_interface
  local item = purchaseItem
  
  local actualQty = getActualItemQuantity(item.internalName)
  if actualQty <= 0 then
    drawCenteredText(20, "Товар закончился! Обновление списка...", 0xff0000)
    os.sleep(1.5)
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
  
  local totalCost = item.price * qty
  local currency = item.currency

  if qty <= 0 then
    drawCenteredText(20, "Выберите количество!", 0xff0000)
    os.sleep(1.5)
    currentScreen = "shop_buy"
    drawBuyStatic()
    drawBuyItemsList()
    drawBuyButtons()
    return
  end

  if currency == "em" and emBalance < totalCost then
    drawCenteredText(20, "Недостаточно Эмов!", 0xff0000)
    os.sleep(1.5)
    currentScreen = "shop_buy"
    drawBuyStatic()
    drawBuyItemsList()
    drawBuyButtons()
    return
  elseif currency == "res" and resBalance < totalCost then
    drawCenteredText(20, "Недостаточно Ресов!", 0xff0000)
    os.sleep(1.5)
    currentScreen = "shop_buy"
    drawBuyStatic()
    drawBuyItemsList()
    drawBuyButtons()
    return
  end

  drawCenteredText(20, "Выполняется покупка...", 0x00ff88)
  os.sleep(0.4)

  local fingerprint = { id = item.internalName, raw_name = item.displayName }
  local ok, err = pcall(function() me.exportItem(fingerprint, PULL_DIRECTION, qty) end)
  local extracted = ok and qty or 0

  if extracted > 0 then
    if currency == "em" then
      emBalance = emBalance - totalCost
    else
      resBalance = resBalance - totalCost
    end
    playerTransactions = playerTransactions + 1

    if currentToken then
      modem.send(serverAddress, 0xffef, serialization.serialize({
        op = "buy",
        name = currentPlayer,
        token = currentToken,
        item = item.displayName,
        qty = extracted,
        value = totalCost,
        currency = currency
      }))
    end

    local currencyName = (currency == "em") and "Эмов" or "Ресов"
    drawCenteredText(20, "Куплено " .. extracted .. " шт. за " .. string.format("%.2f", totalCost) .. " " .. currencyName, 0x00ff88)
    
    loadBuyItems()
    for _, newItem in ipairs(shopItems) do
      if newItem.internalName == item.internalName then
        purchaseItem = newItem
        break
      end
    end
  else
    drawCenteredText(20, "Не удалось выдать предметы! Ошибка: " .. tostring(err), 0xff0000)
  end
  os.sleep(2.5)
  currentScreen = "shop_buy"
  drawBuyStatic()
  drawBuyItemsList()
  drawBuyButtons()
end

-- ========== ЭКРАН РЕПОРТА ==========
local function drawReportScreen()
  currentScreen = "report"
  clear()
  drawCenteredText(4, "РЕПОРТ", 0xff7300)
  gpu.setForeground(0xcccccc)
  local help1 = "Опишите проблему: баг, предложение, жалоба."
  local helpX = math.floor((80 - unicode.len(help1)) / 2) + 1
  gpu.set(helpX, 7, help1)

  if not canSendReport() then
    drawCenteredText(9, "Вы уже отправляли репорт сегодня.", 0xff0000)
    drawCenteredText(10, "Лимит: 1 сообщение в сутки (сброс в 00:00 МСК).", 0xff0000)
    drawFlexButton(backButton)
    return
  end

  gpu.setBackground(0x222222)
  gpu.fill(10, 9, 60, 3, " ")
  gpu.setForeground(0xffffff)
  if reportInput ~= "" then
    gpu.set(11, 10, unicode.sub(reportInput, -58))
  else
    gpu.setForeground(0x888888)
    gpu.set(11, 10, "Введите текст сообщения...")
  end
  gpu.setBackground(0x000000)

  local sendBtn = {x=33, y=14, xs=17, ys=1, text="[ ОТПРАВИТЬ ]", bg=0x004400, fg=0x00ff88}
  drawFlexButton(sendBtn)
  drawFlexButton(backButton)
  gpu.setForeground(0x888888)
  drawCenteredText(16, "Ограничение: 1 репорт в сутки (сброс в 00:00 МСК)", 0x888888)
end

-- ========== НАВИГАЦИЯ ==========
local function goToBuy()
  if not playerAgreed then
    drawCenteredText(12, "Вы не приняли пользовательское соглашение!", 0xff5555)
    drawCenteredText(13, "Нажмите [Помощь] и ознакомьтесь с условиями.", 0xcccccc)
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
  showOnlyAvailable = true
  buyFilterMode = "all"
  filterButton.fg = 0x00ff00
  loadBuyItems()
  drawBuyStatic()
  drawBuyItemsList()
  drawBuyButtons()
end

local function goToSell()
  if not playerAgreed then
    drawCenteredText(12, "Вы не приняли пользовательское соглашение!", 0xff5555)
    drawCenteredText(13, "Нажмите [Помощь] и ознакомьтесь с условиями.", 0xcccccc)
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
  showOnlyAvailable = false
  buyFilterMode = "all"
  loadSellItems()
  drawBuyStatic()
  drawBuyItemsList()
  drawBuyButtons()
end

local function drawShopMenu()
  clear()
  drawCenteredText(4, "МАГАЗИН", 0xff7300)
  if not playerAgreed then
    drawCenteredText(9, "Доступ запрещён.", 0xff5555)
    drawCenteredText(10, "Примите соглашение, нажав [Соглашение] в главном меню.", 0xffaa00)
    drawFlexButton(backButton)
    return
  end
  for _,btn in pairs(shopMenuButtons) do drawButton(btn) end
  drawFlexButton(backButton)
end

local function drawWelcomeScreen()
  gpu.setBackground(0x000000) gpu.fill(1,1,80,25," ")
  drawBigTitle()
  gpu.setForeground(0x00FF00)
  drawCenteredText(18, "↓   Встаньте на PIM   ↓", 0x00FF00)
  drawCenteredText(19,  "━━━━━━━━━━━━━━━━━━━", 0x00FF00)
  gpu.setForeground(0x414243)
  drawCenteredText(22, "По любым вопросам пишите в Telegram: f0rb4ik", 0x414243)
  gpu.setBackground(0x000000)
end

local function drawAuthScreen()
  gpu.setBackground(0x000000) gpu.fill(1,1,80,25," ")
  drawBigTitle()
  gpu.setForeground(0xFFFFFF)
  drawCenteredText(18, "Авторизация....", 0xFFFFFF)
  gpu.setForeground(0x414243)
  drawCenteredText(22, "По любым вопросам пишите в Telegram: f0rb4ik", 0x414243)
  gpu.setBackground(0x000000)
end

local function drawMainMenu()
  clear()
  if currentPlayer then
    local hello1 = "Добро пожаловать, "
    local hello2 = currentPlayer.."!"
    local full1 = hello1..hello2
    local x1 = math.floor((80 - unicode.len(full1))/2)+1
    gpu.setForeground(0x00FF88)
    gpu.set(x1, 4, hello1)
    gpu.setForeground(0xFFFFFF)
    gpu.set(x1 + unicode.len(hello1), 4, hello2)

    local resText = "Ваш баланс: " .. string.format("%.2f Ресов $ | ", resBalance)
    local emText = string.format("%.2f Эмы *", emBalance)
    local full2 = resText .. emText
    local x2 = math.floor((80 - unicode.len(full2))/2)+1
    gpu.setForeground(0x00FF88)
    gpu.set(x2, 6, resText)
    gpu.setForeground(0xFF7300)
    gpu.set(x2 + unicode.len(resText), 6, emText)

    -- Предупреждение, если не принято соглашение (с учётом флага showShopDenied)
    if not playerAgreed then
      gpu.setForeground(0xFFAA00)
      if showShopDenied then
        drawCenteredText(7, "Доступ запрещён. Примите соглашение [Соглашение]", 0xFF5555)
      else
        drawCenteredText(7, "Вы не приняли пользовательское соглашение! Нажмите [Соглашение]", 0xFFAA00)
      end
    end

    for _,btn in pairs(menuButtons) do
      drawButton(btn)
    end
    drawBottomPanel()
  else
    drawWelcomeScreen()
  end
end

local function drawAccount(data)
  clear()
  drawCenteredText(10, currentPlayer .. ":", 0xFFD700)
  local res = data.resBalance or resBalance
  local em = data.emBalance or emBalance
  local resPart1 = string.format("Баланс Ресов: %.2f $ | ", res)
  local emPart = string.format("Эмов: %.2f *", em)
  local full = resPart1 .. emPart
  local x = math.floor((80 - unicode.len(full)) / 2) + 1
  gpu.setForeground(0x00FF00)
  gpu.set(x, 12, resPart1)
  gpu.setForeground(0xff7300)
  gpu.set(x + unicode.len(resPart1), 12, emPart)

  local transLabel = "Совершенно транзакций: "
  local transCount = tostring(data.transactions or 0)
  local fullTrans = transLabel .. transCount
  local transX = math.floor((80 - unicode.len(fullTrans)) / 2) + 1
  gpu.setForeground(0x00FF00)
  gpu.set(transX, 13, transLabel)
  gpu.setForeground(0xFFFFFF)
  gpu.set(transX + unicode.len(transLabel), 13, transCount)

  local regLabel = "Регистрация: "
  local regDate = data.regDate or "Неизвестно"
  local fullReg = regLabel .. regDate
  local regX = math.floor((80 - unicode.len(fullReg)) / 2) + 1
  gpu.setForeground(0x00FF00)
  gpu.set(regX, 14, regLabel)
  gpu.setForeground(0xFFFFFF)
  gpu.set(regX + unicode.len(regLabel), 14, regDate)

  -- Строка согласия
  local agreeLabel = "Соглашение: "
  local agreeStatus = (data.agreed or playerAgreed) and "ознакомлен" or "не ознакомлен"
  local agreeColor = (data.agreed or playerAgreed) and 0x00FF00 or 0xFF5555
  local fullAgree = agreeLabel .. agreeStatus
  local agreeX = math.floor((80 - unicode.len(fullAgree)) / 2) + 1
  gpu.setForeground(0x00FF00)
  gpu.set(agreeX, 15, agreeLabel)
  gpu.setForeground(agreeColor)
  gpu.set(agreeX + unicode.len(agreeLabel), 15, agreeStatus)

  drawFlexButton(backButton)
end

local function drawAccountLoading()
  clear()
  drawCenteredText(12, "Загрузка...", 0x888888)
  drawFlexButton(backButton)
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
          emBalance = msg.balance or 0.0
          resBalance = msg.resBalance or 0.0
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
    drawCenteredText(12, "Ошибка: нет авторизации", 0xFF0000)
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
  currentScreen="utility"
  clear()
  drawCenteredText(8,"Полезности (в разработке)",0x00FF00)
end

local function goBackToMenu()
  showShopDenied = false
  currentScreen = "menu"
  drawMainMenu()
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
    drawCenteredText(20, "Отправка подтверждения...", 0x00FF88)
  else
    goBackToMenu()
  end
end

-- ======== ИНИЦИАЛИЗАЦИЯ ========
drawWelcomeScreen()
modem.send(serverAddress,0xffef,serialization.serialize({op="register"}))
print("Терминал отправляет регистрацию...")

-- ======== ГЛАВНЫЙ ЦИКЛ ========
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
      elseif not (x >= popupX and x < popupX+popupWidth and y >= popupY and y < popupY+popupHeight) then
        showSellPopup = false
        drawSellScanScreen()
      end
      goto continue
    end

    if currentScreen == "shop_buy" or currentScreen == "shop_sell" then
      if y >= 6 and y <= 17 and x >= 2 and x <= 77 then
        local relativeRow = y - 5
        local clickedIndex = listScroll + relativeRow - 1
        local item = filteredItems[clickedIndex]
        if item and (currentShopMode ~= "buy" or item.qty > 0) then
          selectedIndex = clickedIndex
          selectedItem = item
          hoveredIndex = 0
          drawBuyItemsList()
          drawBuyButtons()
        end
      end

      if x >= 78 and y >= 6 and y <= 17 then
        local total = #filteredItems
        if total > visibleRows then
          local clickPos = y - 5
          listScroll = math.floor((clickPos - 1) * (#filteredItems - visibleRows) / visibleRows) + 1
          drawBuyItemsList()
        end
      end

      if isButtonClicked(backButton, x, y) then
        currentScreen = "shop"
        selectedIndex = 0
        selectedItem = nil
        hoveredIndex = 0
        drawShopMenu()
      elseif isButtonClicked(searchButton, x, y) then
        searchActive = true
        searchInput = shopSearch
        drawBuyButtons()
      elseif isButtonClicked(filterButton, x, y) then
        if currentShopMode == "sell" then
          if buyFilterMode == "all" then
            buyFilterMode = "vanilla"
          else
            buyFilterMode = "all"
          end
          listScroll = 1
          selectedIndex = 0
          selectedItem = nil
          hoveredIndex = 0
          drawBuyItemsList()
          drawBuyButtons()
        else
          showOnlyAvailable = not showOnlyAvailable
          listScroll = 1
          selectedIndex = 0
          selectedItem = nil
          hoveredIndex = 0
          drawBuyItemsList()
          drawBuyButtons()
        end
      elseif isButtonClicked(nextButton, x, y) then
        if selectedItem and (currentShopMode ~= "buy" or selectedItem.qty > 0) then
          if currentShopMode == "buy" then
            goToPurchase(selectedItem)
          else
            goToSellConfirm(selectedItem)
          end
        end
      elseif searchActive then
        shopSearch = searchInput
        searchActive = false
        listScroll = 1
        selectedIndex = 0
        selectedItem = nil
        hoveredIndex = 0
        drawBuyItemsList()
        drawBuyButtons()
      end

    elseif currentScreen == "purchase" then
      if (y >= 23 and y <= 23) and (x >= 18 and x <= 28) then
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
      end
      if (y >= 23 and y <= 23) and (x >= 50 and x <= 60) then
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
        drawCenteredText(17, "Сканирование...", 0xffaa00)
        os.sleep(0.4)
        foundAmount = scanPlayerInventory(sellConfirmItem.internalName)
        if foundAmount > 0 then
          showSellPopup = true
          drawSellScanScreen()
        else
          drawCenteredText(17, "Предмет не найден!", 0xff0000)
          os.sleep(1.2)
          drawSellScanScreen()
        end
      elseif y == 15 and x >= 30 and x <= 50 then
        drawCenteredText(17, "Сканирование инвентаря...", 0xffaa00)
        os.sleep(0.6)
        foundAmount = scanPlayerInventory(sellConfirmItem.internalName)
        if foundAmount > 0 then
          showSellPopup = true
          drawSellScanScreen()
        else
          drawCenteredText(17, "Предмет не найден!", 0xff0000)
          os.sleep(1.5)
          drawSellScanScreen()
        end
      end

    elseif currentScreen == "menu" then
      for name,btn in pairs(menuButtons) do
        if x>=btn.x and x<btn.x+btn.xs and y>=btn.y and y<btn.y+btn.ys then
          if name=="shop" then
            if playerAgreed then
              goToShop()
            else
              showShopDenied = true
              drawMainMenu()   -- просто обновляем меню с новым текстом
            end
          elseif name=="util" then
            showShopDenied = false
            goToUtility()
          elseif name=="account" then
            showShopDenied = false
            goToAccount()
          end
          break
        end
      end
      if y == 23 then
        if x >= 4 and x <= 25 then          -- [Сообщить о проблеме]
          showShopDenied = false
          goToReport()
        elseif x >= 39 and x <= 45 then     -- [Соглашение] (30 - начало, ~40 - конец)
          showShopDenied = false
          goToHelp()
        elseif x >= 70 and x <= 78 then     -- [Отзывы]
          showShopDenied = false
          drawCenteredText(18, "Отзывы в разработке", 0x888888)
          os.sleep(1)
          drawMainMenu()
        end
      end

    elseif currentScreen == "agreement" then
      local btnText = "[ ПОНЯТНО ]"
      local btnW = unicode.len(btnText) + 4
      local btnX = math.floor((80 - btnW)/2)
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
        if x>=btn.x and x<btn.x+btn.xs and y>=btn.y and y<btn.y+btn.ys then
          if name == "buy" then goToBuy()
          elseif name == "sell" then goToSell()
          elseif name == "bundle" then
            currentScreen = "shop_bundle"
            clear()
            drawCenteredText(10, "Наборы/Квесты (в разработке)", 0xffffff)
            drawFlexButton(backButton)
          end
          break
        end
      end
      if isButtonClicked(backButton, x, y) then goBackToMenu() end

    elseif currentScreen == "shop_bundle" then
      if isButtonClicked(backButton, x, y) then
        currentScreen = "shop"
        drawShopMenu()
      end

    elseif currentScreen == "utility" then
      if isButtonClicked(backButton, x, y) then goBackToMenu() end

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
              time = os.date("%d.%m.%Y %H:%M:%S")
            }))
          end
          lastReportTime = os.time()
          drawCenteredText(18, "Сообщение успешно отправлено! Ожидайте ответа.", 0x00ff88)
          os.sleep(2)
          goBackToMenu()
        end
      end
    end

  elseif e == "scroll" and (currentScreen == "shop_buy" or currentScreen == "shop_sell") then
    local direction = ev[5]
    local x = ev[3]
    local y = ev[4]
    if x >= 2 and x <= 78 and y >= 6 and y <= 17 then
      if direction == -1 then
        smoothScroll(1)
      elseif direction == 1 then
        smoothScroll(-1)
      end
    end

  elseif e == "mouse_move" and (currentScreen == "shop_buy" or currentScreen == "shop_sell") then
    local x, y = ev[3], ev[4]
    if y >= 6 and y <= 17 and x >= 2 and x <= 77 then
      local rel = y - 5
      local newHover = listScroll + rel - 1
      if newHover ~= hoveredIndex and newHover <= #filteredItems then
        hoveredIndex = newHover
        drawBuyItemsList()
      end
    else
      if hoveredIndex ~= 0 then
        hoveredIndex = 0
        drawBuyItemsList()
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
      drawBuyItemsList()
      drawBuyButtons()
    elseif ch == 8 then
      searchInput = unicode.sub(searchInput, 1, -2)
      shopSearch = searchInput
      listScroll = 1
      selectedIndex = 0
      selectedItem = nil
      hoveredIndex = 0
      drawBuyItemsList()
      drawBuyButtons()
    elseif ch >= 32 then
      searchInput = searchInput .. unicode.char(ch)
      shopSearch = searchInput
      listScroll = 1
      selectedIndex = 0
      selectedItem = nil
      hoveredIndex = 0
      drawBuyItemsList()
      drawBuyButtons()
    end

  elseif e == "player_on" or e == "pim" or e == "pim_player_enter" then
    local playerName = ev[2] or "Игрок"
    currentPlayer = playerName:match("^%s*(.-)%s*$") or playerName
    if alreadyAuthorized then
      if currentScreen == "auth" or currentScreen == "account_loading" then
        currentScreen = "menu"
        drawMainMenu()
      end
    elseif currentToken then
      alreadyAuthorized = true
      if currentScreen == "auth" or currentScreen == "account_loading" then
        currentScreen = "menu"
        drawMainMenu()
      end
    else
      emBalance = 0.0
      resBalance = 0.0
      playerAgreed = false
      currentScreen = "auth"
      authStartTime = os.clock()
      drawAuthScreen()
      modem.send(serverAddress,0xffef,serialization.serialize({op="enter", name=currentPlayer}))
    end

  elseif e == "player_off" or e == "pim_player_leave" then
    currentPlayer = nil
    currentToken = nil
    alreadyAuthorized = false
    currentScreen = "welcome"
    drawWelcomeScreen()

  elseif e == "modem_message" then
    local sender = ev[3]
    local data = ev[6]
    if sender == serverAddress then
      local success, msg = pcall(serialization.unserialize, data)
      if success and msg then
        if msg.op == "welcome" and msg.token then
          currentToken = msg.token
          emBalance = msg.balance or 0.0
          resBalance = msg.resBalance or 0.0
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
            drawCenteredText(20, "Спасибо! Теперь вам доступен магазин.", 0x00FF88)
            os.sleep(1.5)
            drawMainMenu()
            currentScreen = "menu"
          elseif msg.error and msg.message == "Токен устарел" then
            drawCenteredText(20, "Сессия устарела. Обновление...", 0xffaa00)
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
                    emBalance = m.balance or 0.0
                    resBalance = m.resBalance or 0.0
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
              drawCenteredText(20, "Повторная отправка...", 0x00FF88)
            else
              drawCenteredText(20, "Не удалось обновить сессию", 0xFF0000)
              os.sleep(2)
              drawMainMenu()
              currentScreen = "menu"
            end
          else
            drawCenteredText(20, "Ошибка: " .. (msg.message or "неизвестная"), 0xFF0000)
            os.sleep(2)
            drawMainMenu()
            currentScreen = "menu"
          end
        end
      end
    end
  end
  ::continue::
end
