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

-- ========== ЭКРАН ==========
gpu.setResolution(80, 25)
gpu.setBackground(0x000000)

-- ========== КРУПНЫЙ ШРИФТ NEXAR SHOP ==========
local function drawBigTitle()
  gpu.setForeground(0x00FF00)  -- ярко-зелёный
  
  -- NEXAR
  gpu.set(15, 3, "  ███╗   ██╗ ███████╗ ██╗  ██╗  █████╗  ██████╗ ")
  gpu.set(15, 4, "  ████╗  ██║ ██╔════╝ ██║ ██╔╝ ██╔══██╗ ██╔══██╗")
  gpu.set(15, 5, "  ██╔██╗ ██║ █████╗   █████╔╝  ███████║ ██████╔╝")
  gpu.set(15, 6, "  ██║╚██╗██║ ██╔══╝   ██╔═██╗  ██╔══██║ ██╔══██╗")
  gpu.set(15, 7, "  ██║ ╚████║ ███████╗ ██║  ██╗ ██║  ██║ ██║  ██║")
  
  -- SHOP
  gpu.set(32, 9,  "  ███████╗ ██╗  ██╗  ██████╗  ██████╗ ")
  gpu.set(32, 10, "  ██╔════╝ ██║  ██║ ██╔═══██╗ ██╔══██╗")
  gpu.set(32, 11, "  ███████╗ ███████║ ██║   ██║ ██████╔╝")
  gpu.set(32, 12, "  ╚════██║ ██╔══██║ ██║   ██║ ██╔═══╝ ")
  gpu.set(32, 13, "  ███████║ ██║  ██║ ╚██████╔╝ ██║     ")
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

local function drawWelcomeScreen()
  gpu.setBackground(0x202020) gpu.fill(1,1,80,25," ")
  
  drawBigTitle()
  
  gpu.setForeground(0x00FF00)
  drawCenteredText(16, "↓   Встаньте на PIM   ↓", 0x00FF00)
  drawCenteredText(17, "━━━━━━━━━━━━━━━━━━━━", 0x00FF00)
  gpu.setForeground(0x414243)
  drawCenteredText(20, "По любым вопросам пишите в Telegram: f0rb4ik", 0x414243)
  gpu.setBackground(0x000000)
end

local function drawAuthScreen()
  gpu.setBackground(0x202020) gpu.fill(1,1,80,25," ")
  drawBigTitle()
  gpu.setForeground(0xFFFFFF)
  drawCenteredText(16, "Авторизация....", 0xFFFFFF)
  gpu.setForeground(0x414243)
  drawCenteredText(20, "По любым вопросам пишите в Telegram: f0rb4ik", 0x414243)
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

-- Экран аккаунта (переработан под твой скриншот)
local function drawAccount(data)
  clear()
  
  -- Имя игрока по центру
  drawCenteredText(2, currentPlayer .. ":", 0xFFFFFF)
  
  -- Данные по центру
  local balanceText = string.format("Баланс: %.2f Ресоб $ | %.2f Змоб *", data.balance, data.balance)
  local transText = "Совершенно транзакций: " .. (data.transactions or 0)
  local regText = "Регистрация: " .. (data.regDate or "Неизвестно")
  
  drawCenteredText(5, balanceText, 0x00FF00)
  drawCenteredText(7, transText, 0x00FF00)
  drawCenteredText(9, regText, 0x00FF00)
  
  -- Кнопка "Назад" внизу по центру (маленькая)
  local backText = "Назад"
  local backWidth = #backText + 2  -- небольшой отступ
  local backX = math.floor((80 - backWidth) / 2) + 1
  gpu.setBackground(0x333333)
  gpu.fill(backX, 22, backWidth, 3, " ")
  gpu.setForeground(0xFFFFFF)
  gpu.set(backX + 1, 23, backText)
  gpu.setBackground(0x000000)
end

-- Экран загрузки аккаунта
local function drawAccountLoading()
  clear()
  drawCenteredText(12, "Загрузка...", 0x888888)
  local backText = "Назад"
  local backWidth = #backText + 2
  local backX = math.floor((80 - backWidth) / 2) + 1
  gpu.setBackground(0x333333)
  gpu.fill(backX, 22, backWidth, 3, " ")
  gpu.setForeground(0xFFFFFF)
  gpu.set(backX + 1, 23, backText)
  gpu.setBackground(0x000000)
end

local function goToAccount()
  if not currentToken then
    drawCenteredText(12, "Ошибка: нет авторизации", 0xFF0000)
    return
  end
  print("Запрос аккаунта...")
  currentScreen = "account_loading"
  accountRequestTime = os.clock()
  drawAccountLoading()
  modem.send(serverAddress, 0xffef, serialization.serialize({
    op = "getAccount", name = currentPlayer, token = currentToken
  }))
end

local function goToShop() currentScreen="shop" clear() drawCenteredText(8,"Магазин (в разработке)",0x00FF00) end
local function goToUtility() currentScreen="utility" clear() drawCenteredText(8,"Полезности (в разработке)",0x00FF00) end
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
      print("⚠ Таймаут авторизации")
      currentScreen = "menu"
      drawMainMenu()
    end
  end

  if currentScreen == "account_loading" then
    if os.clock() - accountRequestTime >= ACCOUNT_TIMEOUT then
      print("⚠ Таймаут загрузки аккаунта")
      currentScreen = "menu"
      drawMainMenu()
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
    elseif currentScreen == "account" or currentScreen == "account_loading" then
      -- Проверка кнопки "Назад" по центру
      local backText = "Назад"
      local backWidth = #backText + 2
      local backX = math.floor((80 - backWidth) / 2) + 1
      if x >= backX and x < backX + backWidth and y >= 22 and y <= 24 then
        goBackToMenu()
      end
    elseif currentScreen=="shop" or currentScreen=="utility" then
      if x>=2 and x<=13 and y>=22 and y<=24 then goBackToMenu() end
    end
  elseif e=="player_on" or e=="pim" or e=="pim_player_enter" then
    local playerName = ev[2] or "Игрок"
    currentPlayer = playerName:match("^%s*(.-)%s*$") or playerName
    playerBalance = 0.0
    currentToken = nil
    print("Игрок встал на PIM: "..currentPlayer)

    currentScreen = "auth"
    authStartTime = os.clock()
    drawAuthScreen()

    modem.send(serverAddress,0xffef,serialization.serialize({op="enter", name=currentPlayer}))
    print("Отправлен enter для "..currentPlayer)

  elseif e=="player_off" or e=="pim_player_leave" then
    print("Игрок сошёл с PIM")
    currentPlayer = nil
    currentToken = nil
    currentScreen = "welcome"
    drawWelcomeScreen()
  elseif e=="modem_message" then
    local sender = ev[3]
    local data = ev[6]
    print("Получено сообщение от " .. sender)
    if sender == serverAddress then
      local success, msg = pcall(serialization.unserialize, data)
      if success and msg then
        print("Сообщение расшифровано: op=" .. tostring(msg.op) .. " token=" .. tostring(msg.token))
        if msg.op == "welcome" and msg.token then
          currentToken = msg.token
          playerBalance = msg.balance or 0.0
          playerTransactions = msg.transactions or 0
          playerRegDate = msg.regDate or ""
          print("✅ Авторизация успешна, токен: "..currentToken)
          if currentScreen == "auth" then
            currentScreen = "menu"
            drawMainMenu()
          end
        elseif msg.op == "accountData" then
          print("Получен ответ аккаунта")
          if currentScreen == "account_loading" then
            currentScreen = "account"
            drawAccount(msg.data)
          end
        end
      end
    end
  end
end
