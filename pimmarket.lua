local component = require("component")
local event = require("event")
local gpu = component.gpu
local unicode = require("unicode")
local serialization = require("serialization")

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

-- Переменные магазина
local shopItems = {}
local shopPage = 1
local shopPageSize = 12
local shopSearch = ""
local shopTotalPages = 1
local searchActive = false
local searchInput = ""
local showOnlyAvailable = false
local shopScroll = 0
local SCROLL_STEP = 3   -- строк за одно движение колёсика

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

-- Кнопки панели покупки (строка 21)
local searchButton = {text = "Поиск...", x=3, y=21, xs=20, ys=1, bg=0x333333, fg=0x00aaff}
local stockButton   = {text = "● В наличии", x=33, y=21, xs=14, ys=1, bg=0x333333, fg=0x00aaff}
local prevButton    = {text = "Назад", x=55, y=21, xs=7, ys=1, bg=0x333333, fg=0xffaa00}
local nextButton    = {text = "Далее", x=70, y=21, xs=7, ys=1, bg=0x333333, fg=0xffaa00}

-- Кнопки меню "Магазин"
local shopMenuButtons = {
  buy = {x=31,xs=20,y=7,ys=3,text="Покупка",tx=6,ty=1,bg=0x444444,fg=0x3375cc},
  sell = {x=31,xs=20,y=11,ys=3,text="Пополнение",tx=5,ty=1,bg=0x444444,fg=0x3375cc},
  bundle = {x=31,xs=20,y=15,ys=3,text="Наборы/Квесты",tx=4,ty=1,bg=0x444444,fg=0x3375cc}
}

-- ========== ЗАГРУЗКА ПРЕДМЕТОВ ИЗ ME ==========
local function loadShopItems()
  shopItems = {}
  if component.isAvailable("me_interface") then
    local me = component.me_interface
    local rawItems = me.getItemsInNetwork()
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
end

-- ========== СТАТИЧЕСКАЯ ЧАСТЬ ПОКУПКИ ==========
local function drawBuyStatic()
  clear()
  -- Баланс
  local balanceText = "Баланс: " .. string.format("%.2f Ресов $ | ", playerBalance)
  gpu.setForeground(0x00ff88)
  gpu.set(3, 1, balanceText)
  gpu.setForeground(0xff7300)
  gpu.set(3 + unicode.len(balanceText), 1, string.format("%.2f Эмов *", playerBalance))

  -- "Магазин продаёт"
  gpu.setForeground(0xff7300)
  gpu.set(3, 3, "Магазин продаёт")

  -- Заголовки таблицы (строка 4)
  gpu.setBackground(0x222222)
  gpu.fill(2, 4, 76, 1, " ")
  gpu.setForeground(0xffaa00)
  gpu.set(3, 4, "Название")
  gpu.set(42, 4, "Кол-во")
  gpu.set(65, 4, "Цена")
  gpu.setBackground(0x000000)

  -- Разделитель (строка 5)
  gpu.setForeground(0x444444)
  gpu.set(3, 5, string.rep("─", 74))

  -- Нижние статические элементы
  gpu.set(3, 18, string.rep("─", 74))
  drawCenteredText(19, "Категория", 0x888888)
  gpu.set(3, 23, string.rep("─", 74))
  drawFlexButton(backButton)
end

-- ========== ОБНОВЛЕНИЕ ТОЛЬКО СПИСКА (БЕЗ КНОПОК) ==========
local function drawBuyItemsListOnly()
  gpu.setBackground(0x000000)
  for y = 6, 17 do gpu.fill(2, y, 76, 1, " ") end
  gpu.fill(2, 22, 76, 1, " ")

  local filtered = {}
  for _, item in ipairs(shopItems) do
    local matchesSearch = (shopSearch == "" or string.find(string.lower(item.name), string.lower(shopSearch), 1, true))
    local matchesAvailability = (not showOnlyAvailable) or (item.qty > 0)
    if matchesSearch and matchesAvailability then
      table.insert(filtered, item)
    end
  end

  filteredItems = filtered   -- глобальная ссылка для обработчиков

  local maxScroll = math.max(0, #filtered - shopPageSize)
  if shopScroll > maxScroll then shopScroll = maxScroll end
  if shopScroll < 0 then shopScroll = 0 end

  shopTotalPages = math.max(1, math.ceil(#filtered / shopPageSize))
  if shopPage > shopTotalPages then shopPage = shopTotalPages end
  -- синхронизация страницы со скроллом
  shopPage = math.floor(shopScroll / shopPageSize) + 1

  for i = 1, shopPageSize do
    local idx = shopScroll + i
    if idx <= #filtered then
      local item = filtered[idx]
      local y = 5 + i
      if i % 2 == 1 then gpu.setBackground(0x111111)
      else gpu.setBackground(0x1a1a1a) end
      gpu.fill(2, y, 76, 1, " ")
      gpu.setForeground(0x00ff88)
      gpu.set(3, y, item.name:sub(1, 37))
      gpu.setForeground(0xffffff)
      gpu.set(42, y, tostring(item.qty))
      gpu.set(65, y, string.format("%.2f", item.price))
    end
  end
  gpu.setBackground(0x000000)

  -- Индикатор страницы между кнопками
  local pageStr = (math.floor(shopScroll/shopPageSize)+1) .. "/" .. shopTotalPages
  local middleX = math.floor((62 + 70) / 2)
  local pageX = middleX - math.floor(unicode.len(pageStr) / 2)
  gpu.setForeground(0xffffff)
  gpu.fill(middleX - 4, 22, 8, 1, " ")
  gpu.set(pageX, 21, pageStr)
end

-- ========== ОБНОВЛЕНИЕ ТОЛЬКО КНОПОК ==========
local function drawBuyButtons()
  if searchActive then searchButton.text = searchInput .. "_"
  else searchButton.text = "Поиск..." end
  if showOnlyAvailable then stockButton.text = "● В наличии"; stockButton.fg = 0x00ff00
  else stockButton.text = "● В наличии"; stockButton.fg = 0xff0000 end
  drawFlexButton(searchButton)
  drawFlexButton(stockButton)
  drawFlexButton(prevButton)
  drawFlexButton(nextButton)
end

-- ========== ИНИЦИАЛИЗАЦИЯ ПОКУПКИ ==========
local function goToBuy()
  currentScreen = "shop_buy"
  shopPage = 1
  shopSearch = ""
  searchActive = false
  searchInput = ""
  showOnlyAvailable = false
  shopScroll = 0
  loadShopItems()
  drawBuyStatic()
  drawBuyItemsListOnly()
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
    local x,y = ev[3],ev[4]
    if currentScreen == "menu" then
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
          elseif name == "sell" then
            currentScreen = "shop_sell"
            clear()
            drawCenteredText(10, "Пополнение (в разработке)", 0xffffff)
            drawFlexButton(backButton)
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
    elseif currentScreen == "shop_buy" then
      if isButtonClicked(backButton, x, y) then
        currentScreen = "shop"
        drawShopMenu()
      elseif isButtonClicked(searchButton, x, y) then
        searchActive = true
        searchInput = shopSearch
        drawBuyButtons()
      elseif isButtonClicked(stockButton, x, y) then
        showOnlyAvailable = not showOnlyAvailable
        shopScroll = 0
        drawBuyItemsListOnly()
        drawBuyButtons()
      elseif isButtonClicked(prevButton, x, y) then
        if shopScroll > 0 then
          shopScroll = math.max(0, shopScroll - shopPageSize)
          drawBuyItemsListOnly()
        end
      elseif isButtonClicked(nextButton, x, y) then
        if filteredItems and shopScroll + shopPageSize < #filteredItems then
          shopScroll = shopScroll + shopPageSize
          drawBuyItemsListOnly()
        end
      elseif searchActive then
        shopSearch = searchInput
        searchActive = false
        shopScroll = 0
        drawBuyItemsListOnly()
        drawBuyButtons()
      end
    elseif currentScreen == "shop_sell" or currentScreen == "shop_bundle" then
      if isButtonClicked(backButton, x, y) then
        currentScreen = "shop"
        drawShopMenu()
      end
    elseif currentScreen == "utility" then
      if x>=2 and x<=13 and y>=22 and y<=24 then goBackToMenu() end
    end
  elseif e == "scroll" and currentScreen == "shop_buy" then
    local direction = ev[3]
    if direction > 0 then
      shopScroll = math.max(0, shopScroll - SCROLL_STEP)
    else
      if filteredItems then
        shopScroll = math.min(math.max(0, #filteredItems - shopPageSize), shopScroll + SCROLL_STEP)
      end
    end
    drawBuyItemsListOnly()
  elseif e == "key_down" and currentScreen == "shop_buy" and searchActive then
    local ch = ev[3]
    if ch == 13 then
      shopSearch = searchInput
      searchActive = false
      shopScroll = 0
      drawBuyItemsListOnly()
      drawBuyButtons()
    elseif ch == 8 then
      searchInput = string.sub(searchInput, 1, -2)
      shopSearch = searchInput
      shopScroll = 0
      drawBuyItemsListOnly()
    elseif ch > 30 then
      searchInput = searchInput .. unicode.char(ch)
      shopSearch = searchInput
      shopScroll = 0
      drawBuyItemsListOnly()
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
