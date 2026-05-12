local component = require("component")
local event = require("event")
local gpu = component.gpu
local unicode = require("unicode")
local serialization = require("serialization")
local keyboard = require("keyboard")

-- Загружаем внешний файл с предметами
local shopData = dofile("/home/shop_items.lua")
local sellItems = shopData.sellItems
local vanillaItems = shopData.vanillaItems

local modem = component.modem
local pimList = {}
for addr in component.list("pim") do table.insert(pimList, addr) end
local pim = component.proxy(pimList[1])

modem.open(0xffef)
modem.open(0xfffe)

local serverAddress = "535305a9-37c9-4645-b7c4-46204187ee7b"
local currentPlayer, currentToken, playerBalance = nil, nil, 0.0
local playerTransactions = 0
local playerRegDate = ""
local currentScreen = "welcome"
local authStartTime = 0
local AUTH_TIMEOUT = 3
local accountRequestTime = 0
local ACCOUNT_TIMEOUT = 3
local alreadyAuthorized = false
local helpPage = 1
local HELP_PAGES = 3

-- Переменные магазина (общие для покупки и пополнения)
local shopItems = {}
local shopSearch = ""
local searchActive = false
local searchInput = ""
local showOnlyAvailable = false
local currentShopMode = "buy"   -- "buy" или "sell"

-- Фильтр для раздела пополнения ("all" / "vanilla")
local buyFilterMode = "all"

-- Скролл и выделение
local listScroll = 1
local visibleRows = 12
local selectedIndex = 0
local hoveredIndex = 0
local filteredItems = {}
local selectedItem = nil

-- Горизонтальный скролл для длинных названий
local horizontalScroll = 1
local maxItemWidth = 0

-- Переменные экрана покупки
local purchaseQuantity = 1
local purchaseItem = nil

-- ========== ПЕРЕМЕННЫЕ ДЛЯ ПРОДАЖИ ==========
local sellConfirmItem = nil
local foundAmount = 0

-- ========== ЭКРАН ==========
gpu.setResolution(80, 25)
gpu.setBackground(0x000000)

-- ========== КРУПНЫЙ ШРИФТ NEXAR SHOP ==========
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
  shop = {x=31,xs=20,y=8,ys=3,text="Магазин",tx=6,ty=1,bg=0x444444,fg=0x3375cc},
  util = {x=31,xs=20,y=12,ys=3,text="Полезности",tx=5,ty=1,bg=0x444444,fg=0x3375cc},
  account = {x=31,xs=20,y=16,ys=3,text="Аккаунт",tx=6,ty=1,bg=0x444444,fg=0x3375cc}
}
local function drawButton(btn)
  gpu.setBackground(btn.bg) gpu.fill(btn.x,btn.y,btn.xs,btn.ys," ")
  gpu.setForeground(btn.fg) gpu.set(btn.x+btn.tx, btn.y+btn.ty, btn.text)
  gpu.setBackground(0x000000)
end

local function drawBottomPanel()
  gpu.setForeground(0xcc3342) gpu.set(4,23,"[Помощь]")
  gpu.setForeground(0x00FF00) gpu.set(33,23,"[Конвертация + / $]")
  gpu.setForeground(0xcc3342) gpu.set(69,23,"[Отзывы]")
end

-- Гибкая кнопка
local function drawFlexButton(btn)
  gpu.setBackground(btn.bg)
  gpu.fill(btn.x, btn.y, btn.xs, btn.ys, " ")
  gpu.setForeground(btn.fg)
  local textX = btn.x + math.floor((btn.xs - unicode.len(btn.text)) / 2)
  local textY = btn.y + math.floor((btn.ys - 1) / 2)
  gpu.set(textX, textY, btn.text)
  gpu.setBackground(0x000000)
end

-- Кнопка "Назад" главная
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

-- Кнопки панели (текст и цвет динамические)
local searchButton = {text = "Поиск...", x=3, y=21, xs=20, ys=1, bg=0x333333, fg=0x00aaff}
local filterButton  = {text = "В наличии", x=33, y=21, xs=14, ys=1, bg=0x333333, fg=0x00aaff}
local nextButton    = {text = "Далее", x=70, y=21, xs=7, ys=1, bg=0x333333, fg=0x888888}

-- Кнопки меню "Магазин"
local shopMenuButtons = {
  buy = {x=31,xs=20,y=7,ys=3,text="Покупка",tx=6,ty=1,bg=0x444444,fg=0x3375cc},
  sell = {x=31,xs=20,y=11,ys=3,text="Пополнение",tx=5,ty=1,bg=0x444444,fg=0x3375cc},
  bundle = {x=31,xs=20,y=15,ys=3,text="Наборы/Квесты",tx=4,ty=1,bg=0x444444,fg=0x3375cc}
}

-- ==================== ЗАГРУЗКА ПРЕДМЕТОВ ====================
local function loadBuyItems()
  if not component.isAvailable("me_interface") then return end
  local me = component.me_interface
  local rawItems = me.getItemsInNetwork()
  shopItems = {}
  for _, item in ipairs(rawItems) do
    if item and item.size and item.size > 0 then
      table.insert(shopItems, {
        name = item.label or item.name or "???",
        qty = item.size,
        price = 0.0
      })
    end
  end
  table.sort(shopItems, function(a,b) return a.name < b.name end)
end

local function loadSellItems()
  shopItems = {}
  for _, item in ipairs(sellItems) do
    table.insert(shopItems, {
      name = item.name,
      qty = item.qty,
      price = item.price
    })
  end
end

-- ==================== РАБОТА С ИНВЕНТАРЁМ И ME ====================
local function scanPlayerInventory(itemName)
  if not pim then return 0 end
  local count = 0

  for slot = 1, 44 do
    local stack = pim.getStackInSlot(slot)
    if stack then
      -- Несколько способов проверки имени
      if stack.label == itemName or 
         stack.name == itemName or 
         (stack.displayName and stack.displayName == itemName) then
        count = count + (stack.size or 0)
      end
    end
  end
  return count
end

local function extractToME(itemName, amount)
  if not pim or amount <= 0 then return 0 end
  local extracted = 0

  for slot = 1, 44 do
    if extracted >= amount then break end
    local stack = pim.getStackInSlot(slot)
    if stack then
      if stack.label == itemName or stack.name == itemName or 
         (stack.displayName and stack.displayName == itemName) then
        
        local toTake = math.min(stack.size or 0, amount - extracted)
        if toTake > 0 then
          local success = pim.extractItem(slot, toTake)
          if success then
            if component.isAvailable("me_interface") then
              local me = component.me_interface
              local itemToExport = {name = stack.name, damage = stack.damage or 0}
              me.exportItem(itemToExport, 0, toTake)
            end
            extracted = extracted + toTake
          end
        end
      end
    end
  end
  return extracted
end

-- ========== ПОЛУЧЕНИЕ ОТФИЛЬТРОВАННОГО СПИСКА ==========
local function getFilteredItems()
  local filtered = {}
  for _, item in ipairs(shopItems) do
    local matchesSearch = (shopSearch == "" or string.find(string.lower(item.name), string.lower(shopSearch), 1, true))

    local matchesAvailability = true
    if currentShopMode == "buy" then
      matchesAvailability = (not showOnlyAvailable) or (item.qty > 0)
    end

    local matchesVanilla = true
    if currentShopMode == "sell" and buyFilterMode == "vanilla" then
      matchesVanilla = false
      for _, vname in ipairs(vanillaItems) do
        if item.name == vname then
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
    local len = unicode.len(item.name)
    if len > maxItemWidth then maxItemWidth = len end
  end
  return filtered
end

-- ========== СТАТИЧЕСКАЯ ЧАСТЬ ПОКУПКИ ==========
local function drawBuyStatic()
  clear()
  local balanceText = "Баланс: " .. string.format("%.2f Ресов $ | ", playerBalance)
  gpu.setForeground(0x00ff88)
  gpu.set(3, 1, balanceText)
  gpu.setForeground(0xff7300)
  gpu.set(3 + unicode.len(balanceText), 1, string.format("%.2f Эмов *", playerBalance))

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

-- ========== ОТРИСОВКА ОДНОЙ СТРОКИ СПИСКА ==========
local function drawSingleRow(y, item, isHovered, isSelected, itemIndex)
  if not item then return end
  if isSelected then
    gpu.setBackground(0x225577)
  elseif isHovered then
    gpu.setBackground(0x446688)
  elseif itemIndex % 2 == 1 then
    gpu.setBackground(0x111111)
  else
    gpu.setBackground(0x1a1a1a)
  end
  gpu.fill(2, y, 76, 1, " ")
  gpu.setForeground(0x00ffcc)
  local name = item.name
  if unicode.len(name) > 37 then
    name = unicode.sub(name, horizontalScroll, horizontalScroll + 36)
  end
  gpu.set(3, y, name)
  gpu.setForeground(0xffffff)
  gpu.set(42, y, tostring(item.qty))
  gpu.set(65, y, string.format("%.2f", item.price))
  gpu.setBackground(0x000000)
end

-- ========== СКРОЛЛБАР ==========
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

-- ========== ОБНОВЛЕНИЕ СПИСКА ==========
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

-- ========== ПЛАВНЫЙ СКРОЛЛ ==========
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

-- ========== ОБНОВЛЕНИЕ КНОПОК ПОКУПКИ ==========
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
      filterButton.fg = 0x00ff00   -- зелёный
    else
      filterButton.text = "Vanilla"
      filterButton.fg = 0xffaa00   -- оранжевый
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

  if selectedItem then
    nextButton.fg = 0xffaa00
  else
    nextButton.fg = 0x888888
  end

  drawFlexButton(searchButton)

  -- Ручное центрирование для filterButton
  local filterBg = filterButton.bg
  local filterX = filterButton.x
  local filterY = filterButton.y
  local filterXs = 14
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

  local balanceText = "Баланс: " .. string.format("%.2f Ресов $ | ", playerBalance)
  gpu.setForeground(0x00ff88)
  gpu.set(3, 1, balanceText)
  gpu.setForeground(0xff7300)
  gpu.set(3 + unicode.len(balanceText), 1, string.format("%.2f Эмов *", playerBalance))

  gpu.setForeground(0x00ff88)
  gpu.set(3, 3, "Имя предмета: ")
  gpu.setForeground(0xffffff)
  gpu.set(18, 3, purchaseItem.name)

  gpu.setForeground(0x00ff88)
  gpu.set(55, 3, "Доступно: ")
  gpu.setForeground(0xffffff)
  gpu.set(66, 3, tostring(purchaseItem.qty))

  local total = (purchaseItem.price or 0.0) * purchaseQuantity
  gpu.setForeground(0x00ff88)
  gpu.set(3, 5, "На сумму: ")
  gpu.setForeground(0xff0000)
  gpu.set(14, 5, string.format("%.2f", total))

  gpu.setForeground(0x00ff88)
  gpu.set(55, 5, "Цена: ")
  gpu.setForeground(0x00ff88)
  gpu.set(62, 5, string.format("%.2f", purchaseItem.price or 0.0))

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
  local buyBtn  = {x = 50, y = 23, xs = 10, ys = 1, text = "Купить", bg = 0x333333, fg = 0x00ff88}

  drawFlexButton(backBtn)
  drawFlexButton(buyBtn)
end

local function handleQuantityButtonClick(btnText)
  if btnText == "C" then
    purchaseQuantity = 1
  elseif btnText == "<" then
    purchaseQuantity = math.floor(purchaseQuantity / 10)
    if purchaseQuantity < 1 then purchaseQuantity = 1 end
  elseif tonumber(btnText) then
    purchaseQuantity = purchaseQuantity * 10 + tonumber(btnText)
    if purchaseQuantity > purchaseItem.qty then purchaseQuantity = purchaseItem.qty end
  end
  drawPurchaseScreen()
end

local function goToPurchase(item)
  if not item then return end
  purchaseItem = item
  purchaseQuantity = 1
  drawPurchaseScreen()
end

-- ========== ЭКРАН СКАНИРОВАНИЯ (ПОПОЛНЕНИЕ) ==========
local function drawSellScanScreen()
  currentScreen = "sell_scan"
  clear()

  -- Баланс
  local balanceText = "Баланс: " .. string.format("%.2f Ресов $ | ", playerBalance)
  gpu.setForeground(0x00ff88)
  gpu.set(3, 1, balanceText)
  gpu.setForeground(0xff7300)
  gpu.set(3 + unicode.len(balanceText), 1, string.format("%.2f Эмов *", playerBalance))

  -- Имя предмета
  gpu.setForeground(0x00ff88)
  gpu.set(3, 3, "Имя предмета: ")
  gpu.setForeground(0xffffff)
  gpu.set(18, 3, sellConfirmItem.name)

  gpu.setForeground(0x00ff88)
  gpu.set(55, 3, "Цена: ")
  gpu.setForeground(0xffffff)
  gpu.set(62, 3, string.format("%.0f", sellConfirmItem.price))

  gpu.setForeground(0x00ff88)
  gpu.set(3, 4, "Можно продать: ")
  gpu.setForeground(0xffffff)
  gpu.set(18, 4, tostring(sellConfirmItem.qty))

  -- Центрированная строка
  gpu.setForeground(0xffaa00)
  local scanText = "Сканировать на наличие предмета:"
  local scanX = math.floor((80 - unicode.len(scanText)) / 2)
  gpu.set(scanX, 6, scanText)

  -- Кнопки
  local slotBtn = {x=28, y=8, xs=20, ys=1, text="1 слот", bg=0x333333, fg=0xaaaaaa}
  local allBtn  = {x=28, y=10, xs=20, ys=1, text="Весь инвентарь", bg=0x333333, fg=0x00ff88}

  drawFlexButton(slotBtn)
  drawFlexButton(allBtn)
  drawFlexButton(backButton)
end
-- ========== ФИНАЛЬНОЕ ОКНО ПОДТВЕРЖДЕНИЯ ==========
local function drawSellFinalConfirm()
  currentScreen = "sell_confirm"
  clear()

  local balanceText = "Баланс: " .. string.format("%.2f Ресов $ | ", playerBalance)
  gpu.setForeground(0x00ff88)
  gpu.set(3, 1, balanceText)
  gpu.setForeground(0xff7300)
  gpu.set(3 + unicode.len(balanceText), 1, string.format("%.2f Эмов *", playerBalance))

  gpu.setForeground(0x00ff88)
  gpu.set(3, 4, "В инвентаре найдено:")
  gpu.setForeground(0xffffff)
  gpu.set(25, 4, foundAmount .. " шт. " .. sellConfirmItem.name)

  gpu.setForeground(0xffaa00)
  gpu.set(3, 6, "Будет изъято: " .. foundAmount .. " шт.")

  local value = foundAmount * sellConfirmItem.price
  gpu.setForeground(0x00ff88)
  gpu.set(3, 7, "Пополнение баланса: +" .. string.format("%.2f", value) .. " Эмов")

  local confirmBtn = {x=18, y=12, xs=20, ys=2, text="ПОДТВЕРДИТЬ", bg=0x003300, fg=0x00ff88}
  local cancelBtn  = {x=45, y=12, xs=15, ys=2, text="ОТМЕНА", bg=0x330000, fg=0xff5555}

  drawFlexButton(confirmBtn)
  drawFlexButton(cancelBtn)
  drawFlexButton(backButton)
end

local function goToSellConfirm(item)
  if not item then return end
  sellConfirmItem = item
  foundAmount = 0
  drawSellScanScreen()
end

-- Заглушка покупки
local function performPurchase()
  drawCenteredText(20, "Покупка выполняется...", 0x00ff88)
  os.sleep(1)
  if currentShopMode == "buy" then
    currentScreen = "shop_buy"
  else
    currentScreen = "shop_sell"
  end
  selectedItem = nil
  selectedIndex = 0
  hoveredIndex = 0
  drawBuyStatic()
  drawBuyItemsList()
  drawBuyButtons()
end

-- ========== ИНИЦИАЛИЗАЦИЯ ПОКУПКИ И ПОПОЛНЕНИЯ ==========
local function goToBuy()
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
  showOnlyAvailable = false
  buyFilterMode = "all"
  loadBuyItems()
  drawBuyStatic()
  drawBuyItemsList()
  drawBuyButtons()
end

local function goToSell()
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
  buyFilterMode = "all"   -- начинаем с "Все"
  loadSellItems()
  drawBuyStatic()
  drawBuyItemsList()
  drawBuyButtons()
end

-- ========== ОСТАЛЬНЫЕ ЭКРАНЫ ==========
local function drawShopMenu()
  clear()
  drawCenteredText(4, "МАГАЗИН", 0xff7300)
  for _,btn in pairs(shopMenuButtons) do drawButton(btn) end
  drawFlexButton(backButton)
end

local function drawHelpScreen()
  clear()
  if helpPage == 1 then
    drawCenteredText(2, "Информация об магазине", 0xff7300)
    drawCenteredText(4, "Добро пожаловать в магазин/обменник warg'а Legend", 0xffffff)
    drawCenteredText(5, "Обязательно к прочтению", 0xff0000)
    gpu.setForeground(0xff7300)
    gpu.set(4, 7, "1. Что такое $ – Это торговая валюта")
    gpu.setForeground(0xffffff)
    gpu.set(4, 8, "за ресурсы которыми можно пополнить данный магазин")
    gpu.setForeground(0xff7300)
    gpu.set(4, 9, "Что такое ♦ – Это эмеральды")
    gpu.setForeground(0xffffff)
    gpu.set(4, 10, 'которыми можно пополнить магазин в виде физических "денег"')
    gpu.setForeground(0xff7300)
    gpu.set(4, 12, '2. Как пополнять свой баланс для покупок - в разделе')
    gpu.setForeground(0x00aaff)
    gpu.set(4, 13, '"Пополнить"')
    gpu.setForeground(0xffffff)
    gpu.set(4, 14, "Вы можете пополнить свой баланс")
    gpu.setForeground(0x00ff88)
    gpu.set(4, 15, "$ – Ресурсами скупаемыми магазином")
    gpu.setForeground(0xffffff)
    gpu.set(4, 16, "и так-же ♦ – Физическими деньгами")
  elseif helpPage == 2 then
    drawCenteredText(2, "Информация об магазине", 0xff7300)
    gpu.setForeground(0xff7300)
    gpu.set(4, 5, "3. Магазин имеет 3 вида оплаты")
    gpu.setForeground(0x00ff88)
    gpu.set(4, 6, "$ - Только ресурсы")
    gpu.setForeground(0x00aaff)
    gpu.set(4, 7, "♦ - Только эмеральны")
    gpu.setForeground(0xffaa00)
    gpu.set(4, 8, "$ и ♦ - Смежная оплата за обе валюты")
    gpu.setForeground(0xff7300)
    gpu.set(4, 10, "4. Как совершить покупку - в разделе")
    gpu.setForeground(0xffffff)
    gpu.set(4, 11, '"Покупка" Выбираете интересующий товар,')
    gpu.set(4, 12, "указываете кол-во и нажимаете на 'купить'")
    gpu.set(4, 13, "товар будет выдан автоматически. Таким же")
    gpu.set(4, 14, "образом совершается покупка Наборов и")
    gpu.set(4, 15, 'Квестов в разделе "Наборы/Квесты"')
  elseif helpPage == 3 then
    drawCenteredText(2, "Информация об магазине", 0xff7300)
    gpu.setForeground(0xff0000)
    gpu.set(4, 5, "5. Правила:")
    gpu.setForeground(0xffffff)
    gpu.set(4, 6, "Запрещено использовать уязвимости,")
    gpu.set(4, 7, "баги и любые возможные способы")
    gpu.set(4, 8, "обогащения не задуманные создателями")
    gpu.set(4, 9, "данного магазина кроме купле/продажи,")
    gpu.set(4, 10, "о любых сбоях в работе, багах или")
    gpu.set(4, 11, "возможных улучшениях рекомендуется")
    gpu.set(4, 12, "сообщить или предложить Владельцам в")
    gpu.setForeground(0x00aaff)
    gpu.set(4, 13, "Telegram: f0rb4ik")
    drawCenteredText(15, "Приятных покупок", 0x00ff88)
  end
  local pageStr = "⟵ " .. helpPage .. " ⟶"
  drawCenteredText(20, pageStr, 0x00CCFF)
  drawFlexButton(backButton)
end

local function drawWelcomeScreen()
  gpu.setBackground(0x202020) gpu.fill(1,1,80,25," ")
  drawBigTitle()
  gpu.setForeground(0x00FF00)
  drawCenteredText(17, "↓   Встаньте на PIM   ↓", 0x00FF00)
  drawCenteredText(18, "━━━━━━━━━━━━━━━━━━━━", 0x00FF00)
  gpu.setForeground(0x414243)
  drawCenteredText(21, "По любым вопросам пишите в Telegram: f0rb4ik", 0x414243)
  gpu.setBackground(0x000000)
end

local function drawAuthScreen()
  gpu.setBackground(0x202020) gpu.fill(1,1,80,25," ")
  drawBigTitle()
  gpu.setForeground(0xFFFFFF)
  drawCenteredText(17, "Авторизация....", 0xFFFFFF)
  gpu.setForeground(0x414243)
  drawCenteredText(21, "По любым вопросам пишите в Telegram: f0rb4ik", 0x414243)
  gpu.setBackground(0x000000)
end

local function drawMainMenu()
  clear()
  if currentPlayer then
    local pink1 = "Добро пожаловать, " local white1 = currentPlayer.."!"
    local full1 = pink1..white1
    local x1 = math.floor((80 - unicode.len(full1))/2)+1
    gpu.setForeground(0xFF00FF) gpu.set(x1,4,pink1)
    gpu.setForeground(0xFFFFFF) gpu.set(x1+unicode.len(pink1),4,white1)
    local pink2 = "Ваш баланс: " local white2 = string.format("%.2f",playerBalance).." Эмов"
    local full2 = pink2..white2
    local x2 = math.floor((80 - unicode.len(full2))/2)+1
    gpu.setForeground(0xFF00FF) gpu.set(x2,6,pink2)
    gpu.setForeground(0xFFFFFF) gpu.set(x2+unicode.len(pink2),6,white2)
    for _,btn in pairs(menuButtons) do drawButton(btn) end
    drawBottomPanel()
  else drawWelcomeScreen() end
end

local function drawAccount(data)
  clear()
  drawCenteredText(6, currentPlayer .. ":", 0xFFD700)
  local balance = data.balance or 0
  local balancePart1 = string.format("Баланс: %.2f Ресов $ | ", balance)
  local balancePart2 = string.format("%.2f Эмов *", balance)
  local balanceFull = balancePart1 .. balancePart2
  local balanceX = math.floor((80 - unicode.len(balanceFull)) / 2) + 1
  gpu.setForeground(0x00FF00)
  gpu.set(balanceX, 8, balancePart1)
  gpu.setForeground(0xff7300)
  gpu.set(balanceX + unicode.len(balancePart1), 8, balancePart2)
  local transText = "Совершенно транзакций: " .. tostring(data.transactions or 0)
  local transX = math.floor((80 - unicode.len(transText)) / 2) + 1
  gpu.setForeground(0x00FF00)
  gpu.set(transX, 10, "Совершенно транзакций: ")
  gpu.setForeground(0xFFFFFF)
  gpu.set(transX + unicode.len("Совершенно транзакций: "), 10, tostring(data.transactions or 0))
  local regText = "Регистрация: " .. (data.regDate or "Неизвестно")
  local regX = math.floor((80 - unicode.len(regText)) / 2) + 1
  gpu.setForeground(0x00FF00)
  gpu.set(regX, 12, "Регистрация: ")
  gpu.setForeground(0xFFFFFF)
  gpu.set(regX + unicode.len("Регистрация: "), 12, data.regDate or "Неизвестно")
  drawFlexButton(backButton)
end

local function drawAccountLoading()
  clear()
  drawCenteredText(12, "Загрузка...", 0x888888)
  drawFlexButton(backButton)
end

-- Попытка обновления токена
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
          playerBalance = msg.balance or 0.0
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

-- Переходы
local function goToShop()
  currentScreen = "shop"
  drawShopMenu()
end
local function goToUtility() currentScreen="utility" clear() drawCenteredText(8,"Полезности (в разработке)",0x00FF00) end
local function goToHelp()
  currentScreen = "help"
  helpPage = 1
  drawHelpScreen()
end
local function goBackToMenu() currentScreen="menu" drawMainMenu() end

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

    if currentScreen == "shop_buy" or currentScreen == "shop_sell" then
      -- Клик по списку
      if y >= 6 and y <= 17 and x >= 2 and x <= 77 then
        local relativeRow = y - 5
        local clickedIndex = listScroll + relativeRow - 1
        if filteredItems[clickedIndex] then
          selectedIndex = clickedIndex
          selectedItem = filteredItems[clickedIndex]
          hoveredIndex = 0
          drawBuyItemsList()
          drawBuyButtons()
        end
      end

      -- Клик по скроллбару
      if x >= 78 and y >= 6 and y <= 17 then
        local total = #filteredItems
        if total > visibleRows then
          local clickPos = y - 5
          listScroll = math.floor((clickPos - 1) * (#filteredItems - visibleRows) / visibleRows) + 1
          drawBuyItemsList()
        end
      end

      -- Кнопки
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
          -- Переключаем фильтр "Все" / "Vanilla" для пополнения
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
          -- Режим покупки: фильтр "В наличии"
          showOnlyAvailable = not showOnlyAvailable
          listScroll = 1
          selectedIndex = 0
          selectedItem = nil
          hoveredIndex = 0
          drawBuyItemsList()
          drawBuyButtons()
        end
      elseif isButtonClicked(nextButton, x, y) then
        if selectedItem then
          if currentShopMode == "buy" then
            goToPurchase(selectedItem)
          else
            goToSellConfirm(selectedItem)   -- ← переход в сканирование для продажи
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
      -- Кнопка Назад
      if (y >= 23 and y <= 23) and (x >= 18 and x <= 28) then
        if currentShopMode == "buy" then
          currentScreen = "shop_buy"
        else
          currentScreen = "shop_sell"
        end
        drawBuyStatic()
        drawBuyItemsList()
        drawBuyButtons()
      end

      -- Кнопка Купить
      if (y >= 23 and y <= 23) and (x >= 50 and x <= 60) then
        performPurchase()
      end

      -- Обработка цифровой клавиатуры
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
        drawBuyStatic()
        drawBuyItemsList()
        drawBuyButtons()
      elseif y == 8 and x >= 28 and x <= 48 then -- 1 слот
        drawCenteredText(15, "Сканирование...", 0xffaa00)
        os.sleep(0.4)
        foundAmount = scanPlayerInventory(sellConfirmItem.name)
        if foundAmount > 0 then drawSellFinalConfirm() else
          drawCenteredText(15, "Предмет не найден!", 0xff0000); os.sleep(1.2); drawSellScanScreen()
        end
      elseif y == 10 and x >= 28 and x <= 48 then -- Весь инвентарь
        drawCenteredText(15, "Сканирование инвентаря...", 0xffaa00)
        os.sleep(0.6)
        foundAmount = scanPlayerInventory(sellConfirmItem.name)
        if foundAmount > 0 then drawSellFinalConfirm() else
          drawCenteredText(15, "Предмет не найден!", 0xff0000); os.sleep(1.5); drawSellScanScreen()
        end
      end

    elseif currentScreen == "sell_confirm" then
      if isButtonClicked(backButton, x, y) or (y >= 12 and y <= 13 and x >= 45 and x <= 60) then
        currentScreen = "sell_scan"
        drawSellScanScreen()
      elseif y >= 12 and y <= 13 and x >= 18 and x <= 38 then -- ПОДТВЕРДИТЬ
        drawCenteredText(15, "Выполняется пополнение...", 0x00ff88)
        os.sleep(0.8)

        local realExtracted = extractToME(sellConfirmItem.name, foundAmount)
        local value = realExtracted * sellConfirmItem.price

        playerBalance = playerBalance + value
        playerTransactions = playerTransactions + 1

        drawCenteredText(15, "Успешно! +" .. string.format("%.2f", value) .. " Эмов", 0x00ff88)
        os.sleep(1.8)

        currentScreen = "shop_sell"
        drawBuyStatic()
        drawBuyItemsList()
        drawBuyButtons()
      end

    elseif currentScreen == "menu" then
      for name,btn in pairs(menuButtons) do
        if x>=btn.x and x<btn.x+btn.xs and y>=btn.y and y<btn.y+btn.ys then
          if name=="shop" then goToShop()
          elseif name=="util" then goToUtility()
          elseif name=="account" then goToAccount() end
          break
        end
      end
      if y == 23 then
        if x >= 4 and x <= 13 then goToHelp() end
      end
    elseif currentScreen == "help" then
      local pageStr = "⟵ " .. helpPage .. " ⟶"
      local pageX = math.floor((80 - unicode.len(pageStr)) / 2) + 1
      if y == 20 then
        if x >= pageX and x < pageX + 4 and helpPage > 1 then
          helpPage = helpPage - 1
          drawHelpScreen()
        elseif x >= pageX + unicode.len(pageStr) - 4 and x < pageX + unicode.len(pageStr) and helpPage < HELP_PAGES then
          helpPage = helpPage + 1
          drawHelpScreen()
        end
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
      if x>=2 and x<=13 and y>=22 and y<=24 then goBackToMenu() end
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
    elseif ch > 0 then
      searchInput = searchInput .. unicode.char(ch)
      shopSearch = searchInput
      listScroll = 1
      selectedIndex = 0
      selectedItem = nil
      hoveredIndex = 0
      drawBuyItemsList()
      drawBuyButtons()
    end
  elseif e=="player_on" or e=="pim" or e=="pim_player_enter" then
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
      playerBalance = 0.0
      currentScreen = "auth"
      authStartTime = os.clock()
      drawAuthScreen()
      modem.send(serverAddress,0xffef,serialization.serialize({op="enter", name=currentPlayer}))
    end

  elseif e=="player_off" or e=="pim_player_leave" then
    currentPlayer = nil
    currentToken = nil
    alreadyAuthorized = false
    currentScreen = "welcome"
    drawWelcomeScreen()
  elseif e=="modem_message" then
    local sender = ev[3]
    local data = ev[6]
    if sender == serverAddress then
      local success, msg = pcall(serialization.unserialize, data)
      if success and msg then
        if msg.op == "welcome" and msg.token then
          currentToken = msg.token
          playerBalance = msg.balance or 0.0
          playerTransactions = msg.transactions or 0
          playerRegDate = msg.regDate or ""
          alreadyAuthorized = true
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
              drawAccount(msg.data)
            end
          end
        end
      end
    end
  end
end
