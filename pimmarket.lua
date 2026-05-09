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

-- ========== ЭКРАН ==========
gpu.setResolution(80, 25)
gpu.setBackground(0x000000)

-- ========== КРУПНЫЙ ШРИФТ NEXAR SHOP ==========
local function drawBigTitle()
  gpu.setForeground(0xff7300)
  local lines = {
    "  ███╗   ██╗ ███████╗ ██╗  ██╗  █████╗  ██████╗ ",
    "  ████╗  ██║ ██╔════╝ ██║ ██╔╝ ██╔══██╗ ██╔══██╗",
    "  ██╔██╗ ██║ █████╗   █████╔╝  ███████║ ██████╔╝",
    "  ██║╚██╗██║ ██╔══╝   ██╔═██╗  ██╔══██║ ██╔══██╗",
    "  ██║ ╚████║ ███████╗ ██║  ██╗ ██║  ██║ ██║  ██║",
    "                                                ",
    "       ███████╗ ██╗  ██╗  ██████╗  ██████╗      ",
    "       ██╔════╝ ██║  ██║ ██╔═══██╗ ██╔══██╗     ",
    "       ███████╗ ███████║ ██║   ██║ ██████╔╝     ",
    "       ╚════██║ ██╔══██║ ██║   ██║ ██╔═══╝      ",
    "       ███████║ ██║  ██║ ╚██████╔╝ ██║          ",
  }
  for i, line in ipairs(lines) do
    if #line < 50 then lines[i] = line .. string.rep(" ", 50 - #line) end
  end
  local startX = 15
  for i, line in ipairs(lines) do gpu.set(startX, 2 + i, line) end
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

-- Гибкая кнопка (для "Назад" в аккаунте и помощи)
local function drawFlexButton(btn)
  gpu.setBackground(btn.bg)
  gpu.fill(btn.x, btn.y, btn.xs, btn.ys, " ")
  gpu.setForeground(btn.fg)
  local textX = btn.x + math.floor((btn.xs - unicode.len(btn.text)) / 2)
  local textY = btn.y + math.floor((btn.ys - 1) / 2)
  gpu.set(textX, textY, btn.text)
  gpu.setBackground(0x000000)
end

-- Кнопка "Назад" для всех разделов (аккаунт, помощь)
local backButton = {
  text = "Назад",
  x = nil, y = 22,
  xs = unicode.len("Назад") + 6,   -- ширина: текст + 2 пробела
  ys = 1,                           -- высота 1 строка
  bg = 0x333333,
  fg = 0xff7300
}
backButton.x = math.floor((80 - backButton.xs) / 2) + 1

local function isButtonClicked(btn, x, y)
  return y >= btn.y and y < btn.y + btn.ys and
         x >= btn.x and x < btn.x + btn.xs
end

-- Страницы помощи с цветовой разметкой
local helpPages = {
  -- Страница 1
  {
    {text = " Информация об магазине", color = 0xff7300, centered = true},
    {text = " Добро пожаловать в магазин/обменник", color = 0xffffff, centered = true},
    {text = " warg'а Legend", color = 0xffffff, centered = true},
    {text = " Обязательно к прочтению", color = 0xff0000, centered = true},
    {text = ""},

    {text = "1. Что такое $ – Это торговая валюта", color = 0xff7300},
    {text = "   за ресурсы которыми можно пополнить", color = 0xffffff},
    {text = "   данный магазин", color = 0xffffff},
    {text = "   Что такое ♦ – Это эмеральды", color = 0xff7300},
    {text = "   которыми можно пополнить магазин", color = 0xffffff},
    {text = '   в виде физических "денег"', color = 0xffffff},
    {text = ""},

    {text = "2. Как пополнять свой баланс для", color = 0xff7300},
    {text = "   покупок - в разделе ", color = 0xffffff},           -- белый
    {text = '"Пополнить"', color = 0x00aaff},                      -- голубой
    {text = "   Вы можете пополнить свой баланс", color = 0xffffff},
    {text = "   $ – Ресурсами скупаемыми", color = 0x00ff88},
    {text = "   магазином и так-же ♦ –", color = 0x00ff88},
    {text = "   Физическими деньгами", color = 0x00ff88},
  },

  -- Страница 2
  {
    {text = " Информация об магазине", color = 0xff7300, centered = true},
    {text = ""},

    {text = "3. Магазин имеет 3 вида оплаты", color = 0xff7300},
    {text = "   $ - Только ресурсы", color = 0x00ff88},
    {text = "   ♦ - Только эмеральды", color = 0x00aaff},
    {text = "   $ и ♦ - Смежная оплата за обе валюты", color = 0xffaa00},
    {text = ""},

    {text = "4. Как совершить покупку - в разделе", color = 0xff7300},
    {text = '   "Покупка" выбираете интересующий', color = 0xffffff},
    {text = "   товар, указываете кол-во и", color = 0xffffff},
    {text = '   нажимаете на "купить"', color = 0xffffff},
    {text = "   товар будет выдан автоматически.", color = 0xffffff},
    {text = "   Таким же образом совершается покупка", color = 0xffffff},
    {text = '   Наборов и Квестов в разделе "Наборы/Квесты"', color = 0xffffff},
  },

  -- Страница 3
  {
    {text = " Информация об магазине", color = 0xff7300, centered = true},
    {text = ""},

    {text = "5. Правила:", color = 0xff0000},
    {text = "   Запрещено использовать уязвимости, баги и любые", color = 0xffffff},
    {text = "   возможные способы обогащения не задуманные", color = 0xffffff},
    {text = "   создателями данного магазина", color = 0xffffff},
    {text = "   кроме купле/продажи, о любых сбоях", color = 0xffffff},
    {text = "   в работе, багах или возможных", color = 0xffffff},
    {text = "   улучшениях рекомендуется сообщить", color = 0xffffff},
    {text = "   или предложить Владельцам в", color = 0xffffff},
    {text = "   Discord fkpupsik/alex25764", color = 0x00aaff},
    {text = ""},

    {text = "Приятных покупок", color = 0x00ff88, centered = true},
  }
}

local function drawHelpScreen()
  clear()
  local page = helpPages[helpPage]
  for i, item in ipairs(page) do
    local text = item.text or ""
    local color = item.color or 0xFFFFFF
    if item.centered then
      drawCenteredText(1 + i, text, color)
    else
      gpu.setForeground(color)
      gpu.set(3, 1 + i, text)   -- левый отступ 3 символа
    end
  end
  -- Номер страницы
  local pageStr = "← " .. helpPage .. " →"
  drawCenteredText(20, pageStr, 0xFFFFFF)
  -- Кнопка "Назад"
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

-- Экран аккаунта (цвета исправлены)
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

-- Попытка автоматического обновления токена
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

local function goToShop() currentScreen="shop" clear() drawCenteredText(8,"Магазин (в разработке)",0x00FF00) end
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
      -- Нижняя панель
      if y == 23 then
        if x >= 4 and x <= 13 then goToHelp() end
        -- Конвертация, отзывы пока заглушки
      end
    elseif currentScreen == "help" then
      -- Перелистывание страниц
      if y == 20 then
        local pageStr = "← " .. helpPage .. " →"
        local pageX = math.floor((80 - unicode.len(pageStr)) / 2) + 1
        if x >= pageX and x < pageX + 4 then
          if helpPage > 1 then helpPage = helpPage - 1 drawHelpScreen() end
        elseif x >= pageX + unicode.len(pageStr) - 4 and x < pageX + unicode.len(pageStr) then
          if helpPage < HELP_PAGES then helpPage = helpPage + 1 drawHelpScreen() end
        end
      end
      -- Кнопка "Назад"
      if isButtonClicked(backButton, x, y) then
        goBackToMenu()
      end
    elseif currentScreen == "account" or currentScreen == "account_loading" then
      if isButtonClicked(backButton, x, y) then
        goBackToMenu()
      end
    elseif currentScreen=="shop" or currentScreen=="utility" then
      if x>=2 and x<=13 and y>=22 and y<=24 then goBackToMenu() end
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
