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
local waitingForToken = false
local waitStartTime = 0

-- ========== ЭКРАН ==========
gpu.setResolution(80, 25)
gpu.setBackground(0x000000)

-- ========== КРУПНЫЙ ШРИФТ ==========
local font = {}
local function addLetter(char, rows) font[char] = rows end
addLetter("A",{" ███ ","█   █","█████","█   █","█   █"})
addLetter("B",{"████ ","█   █","████ ","█   █","████ "})
addLetter("C",{" ████","█    ","█    ","█    "," ████"})
addLetter("D",{"████ ","█   █","█   █","█   █","████ "})
addLetter("E",{"█████","█    ","████ ","█    ","█████"})
addLetter("F",{"█████","█    ","████ ","█    ","█    "})
addLetter("G",{" ████","█    ","█ ███","█   █"," ████"})
addLetter("H",{"█   █","█   █","█████","█   █","█   █"})
addLetter("I",{"█████","  █  ","  █  ","  █  ","█████"})
addLetter("J",{"   ██","    █","    █","█   █"," ███ "})
addLetter("K",{"█   █","█  █ ","███  ","█  █ ","█   █"})
addLetter("L",{"█    ","█    ","█    ","█    ","█████"})
addLetter("M",{"█   █","██ ██","█ █ █","█   █","█   █"})
addLetter("N",{"█   █","██  █","█ █ █","█  ██","█   █"})
addLetter("O",{" ███ ","█   █","█   █","█   █"," ███ "})
addLetter("P",{"████ ","█   █","████ ","█    ","█    "})
addLetter("Q",{" ███ ","█   █","█   █","█  ██"," ████"})
addLetter("R",{"████ ","█   █","████ ","█  █ ","█   █"})
addLetter("S",{" ████","█    "," ███ ","    █","████ "})
addLetter("T",{"█████","  █  ","  █  ","  █  ","  █  "})
addLetter("U",{"█   █","█   █","█   █","█   █"," ███ "})
addLetter("V",{"█   █","█   █","█   █"," ███ ","  █  "})
addLetter("W",{"█   █","█   █","█ █ █","██ ██","█   █"})
addLetter("X",{"█   █"," █ █ ","  █  "," █ █ ","█   █"})
addLetter("Y",{"█   █"," █ █ ","  █  ","  █  ","  █  "})
addLetter("Z",{"█████","   █ ","  █  "," █   ","█████"})
addLetter(" ",{"     ","     ","     ","     ","     "})

local function drawBigText(y, text, color, shadowColor)
  local width = 0
  for ch in text:gmatch(".") do if font[ch] then width = width + 5 + 1 end end
  width = width - 1
  local startX = math.floor((80 - width) / 2) + 1
  for row = 1, 5 do
    local curX = startX
    for ch in text:gmatch(".") do
      if font[ch] then
        gpu.setForeground(shadowColor)
        gpu.set(curX + 1, y + row, font[ch][row])
        curX = curX + 5 + 1
      end
    end
  end
  for row = 1, 5 do
    local curX = startX
    for ch in text:gmatch(".") do
      if font[ch] then
        gpu.setForeground(color)
        gpu.set(curX, y + row - 1, font[ch][row])
        curX = curX + 5 + 1
      end
    end
  end
end

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
  local prefix = "Приветствуем в " local shop = "NEXAR SHOP"
  local full = prefix..shop
  local startX = math.floor((80 - unicode.len(full))/2)+1
  gpu.setForeground(0xFFFFFF) gpu.set(startX,2,prefix)
  gpu.setForeground(0x00FF00) gpu.set(startX+unicode.len(prefix),2,shop)
  drawBigText(4,"NEXAR SHOP",0x00FF00,0x006600)
  gpu.setForeground(0x00FF00)
  drawCenteredText(11,"↓   Встаньте на PIM   ↓",0x00FF00)
  drawCenteredText(12,"━━━━━━━━━━━━━━━━━━━━",0x00FF00)
  gpu.setForeground(0x414243)
  drawCenteredText(15,"По любым вопросам пишите в Telegram: f0rb4ik",0x414243)
  gpu.setBackground(0x000000)
end

local function drawAuthScreen()
  gpu.setBackground(0x202020) gpu.fill(1,1,80,25," ")
  local prefix = "Приветствуем в " local shop = "NEXAR SHOP"
  local full = prefix..shop
  local startX = math.floor((80 - unicode.len(full))/2)+1
  gpu.setForeground(0xFFFFFF) gpu.set(startX,2,prefix)
  gpu.setForeground(0x00FF00) gpu.set(startX+unicode.len(prefix),2,shop)
  drawBigText(4,"NEXAR SHOP",0x00FF00,0x006600)
  gpu.setForeground(0xFFFFFF)
  drawCenteredText(12,"Авторизация....",0xFFFFFF)
  gpu.setForeground(0x414243)
  drawCenteredText(15,"По любым вопросам пишите в Telegram: f0rb4ik",0x414243)
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

-- ========== ЭКРАН АККАУНТА ==========
local function drawAccount(data)
  clear()
  drawCenteredText(2, "Аккаунт: " .. currentPlayer, 0xFFD700)

  gpu.setForeground(0xFF00FF)
  gpu.set(5,5,"Баланс:")
  gpu.set(5,6,"Совершено транзакций:")
  gpu.set(5,7,"Регистрация:")

  gpu.setForeground(0xFFFFFF)
  gpu.set(30,5,string.format("%.2f Ресурсы $ | %.2f Эмов", data.balance, data.balance))
  gpu.set(30,6, tostring(data.transactions or 0))
  gpu.set(30,7, data.regDate or "Неизвестно")

  -- Кнопка "Назад"
  gpu.setBackground(0x333333)
  gpu.fill(2,22,12,3," ")
  gpu.setForeground(0xFFFFFF)
  gpu.set(4,23,"Назад")
  gpu.setBackground(0x000000)
end

local function goToAccount()
  if not currentToken then
    drawCenteredText(12, "Ошибка: нет авторизации", 0xFF0000)
    return
  end
  currentScreen = "account"
  modem.send(serverAddress, 0xffef, serialization.serialize({
    top = "getAccount",
    name = currentPlayer,
    token = currentToken
  }))
  drawCenteredText(12, "Загрузка...", 0x888888)
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

  -- Проверка таймаута ожидания токена
  if waitingForToken and (os.clock() - waitStartTime) >= 2 then
    waitingForToken = false
    print("⚠ Таймаут получения токена")
    if not currentToken then
      drawCenteredText(12, "⚠ Нет ответа сервера", 0xFF0000)
    end
    currentScreen = "menu"
    drawMainMenu()
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
    elseif currentScreen == "account" then
      if x>=2 and x<=13 and y>=22 and y<=24 then goBackToMenu() end
    elseif currentScreen=="shop" or currentScreen=="utility" then
      if x>=2 and x<=13 and y>=22 and y<=24 then goBackToMenu() end
    end
  elseif e=="player_on" or e=="pim" or e=="pim_player_enter" then
    local playerName = ev[2] or "Игрок"
    currentPlayer = playerName:match("^%s*(.-)%s*$") or playerName
    playerBalance = 0.0
    currentToken = nil
    print("Игрок встал на PIM: "..currentPlayer)

    -- Авторизация
    currentScreen = "auth"
    drawAuthScreen()
    os.sleep(1)

    -- Отправляем enter с именем
    local enterMsg = {op="enter", name=currentPlayer}
    print("Отправляю enter: " .. serialization.serialize(enterMsg))
    modem.send(serverAddress, 0xffef, serialization.serialize(enterMsg))
    print("Отправлен enter для "..currentPlayer)

    waitingForToken = true
    waitStartTime = os.clock()

  elseif e=="player_off" or e=="pim_player_leave" then
    print("Игрок сошёл с PIM")
    currentPlayer = nil
    currentToken = nil
    waitingForToken = false
    currentScreen = "welcome"
    drawWelcomeScreen()
  elseif e=="modem_message" then
    local _,_,from,_,_,data = ev[2],ev[3],ev[4],ev[5],ev[6]
    if from == serverAddress then
      local success, msg = pcall(serialization.unserialize, data)
      if success and msg then
        if msg.op == "welcome" then
          print("Получен welcome от сервера: token="..tostring(msg.token).." balance="..tostring(msg.balance))
          if msg.token then
            currentToken = msg.token
            playerBalance = msg.balance or 0.0
            playerTransactions = msg.transactions or 0
            playerRegDate = msg.regDate or ""
          end
          if waitingForToken then
            waitingForToken = false
            currentScreen = "menu"
            drawMainMenu()
          end
        elseif msg.op == "accountData" then
          if currentScreen == "account" then
            drawAccount(msg.data)
          end
        end
      end
    end
  end
end
