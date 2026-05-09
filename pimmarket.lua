local component = require("component")
local event = require("event")
local gpu = component.gpu
local unicode = require("unicode")
local serialization = require("serialization")

local modem = component.modem

-- PIM
local pimList = {}
for addr in component.list("pim") do table.insert(pimList, addr) end
local pim = component.proxy(pimList[1])

modem.open(0xffef)
modem.open(0xfffe)

local serverAddress = "535305a9-37c9-4645-b7c4-46204187ee7b"
local currentPlayer = nil
local playerBalance = 0.00
local currentScreen = "welcome"   -- welcome / auth / menu / shop / utility / account
local terminalRegistered = false
local authStartTime = 0
local AUTH_DELAY = 3

-- ========== НАСТРОЙКА ЭКРАНА ==========
gpu.setResolution(80, 25)
gpu.setBackground(0x000000)

-- ========== КРУПНЫЙ ОБЪЁМНЫЙ ШРИФТ 5x5 ==========
local font = {}
local function addLetter(char, rows) font[char] = rows end

addLetter("A", { " ███ ", "█   █", "█████", "█   █", "█   █" })
addLetter("B", { "████ ", "█   █", "████ ", "█   █", "████ " })
addLetter("C", { " ████", "█    ", "█    ", "█    ", " ████" })
addLetter("D", { "████ ", "█   █", "█   █", "█   █", "████ " })
addLetter("E", { "█████", "█    ", "████ ", "█    ", "█████" })
addLetter("F", { "█████", "█    ", "████ ", "█    ", "█    " })
addLetter("G", { " ████", "█    ", "█ ███", "█   █", " ████" })
addLetter("H", { "█   █", "█   █", "█████", "█   █", "█   █" })
addLetter("I", { "█████", "  █  ", "  █  ", "  █  ", "█████" })
addLetter("J", { "   ██", "    █", "    █", "█   █", " ███ " })
addLetter("K", { "█   █", "█  █ ", "███  ", "█  █ ", "█   █" })
addLetter("L", { "█    ", "█    ", "█    ", "█    ", "█████" })
addLetter("M", { "█   █", "██ ██", "█ █ █", "█   █", "█   █" })
addLetter("N", { "█   █", "██  █", "█ █ █", "█  ██", "█   █" })
addLetter("O", { " ███ ", "█   █", "█   █", "█   █", " ███ " })
addLetter("P", { "████ ", "█   █", "████ ", "█    ", "█    " })
addLetter("Q", { " ███ ", "█   █", "█   █", "█  ██", " ████" })
addLetter("R", { "████ ", "█   █", "████ ", "█  █ ", "█   █" })
addLetter("S", { " ████", "█    ", " ███ ", "    █", "████ " })
addLetter("T", { "█████", "  █  ", "  █  ", "  █  ", "  █  " })
addLetter("U", { "█   █", "█   █", "█   █", "█   █", " ███ " })
addLetter("V", { "█   █", "█   █", "█   █", " ███ ", "  █  " })
addLetter("W", { "█   █", "█   █", "█ █ █", "██ ██", "█   █" })
addLetter("X", { "█   █", " █ █ ", "  █  ", " █ █ ", "█   █" })
addLetter("Y", { "█   █", " █ █ ", "  █  ", "  █  ", "  █  " })
addLetter("Z", { "█████", "   █ ", "  █  ", " █   ", "█████" })
addLetter(" ", { "     ", "     ", "     ", "     ", "     " })

local function drawBigText(y, text, color, shadowColor)
  local width = 0
  for ch in text:gmatch(".") do
    if font[ch] then width = width + 5 + 1 end
  end
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

local function clear()
  gpu.setBackground(0x000000)
  gpu.fill(1, 1, 80, 25, " ")
end

local function drawCenteredText(y, text, color)
  gpu.setForeground(color or 0xFFFFFF)
  local x = math.floor((80 - unicode.len(text)) / 2) + 1
  gpu.set(x, y, text)
end

-- Кнопки главного меню
local menuButtons = {
  shop = {x = 31, xs = 20, y = 8, ys = 3, text = "Магазин", tx = 6, ty = 1, bg = 0x444444, fg = 0x3375cc},
  util = {x = 31, xs = 20, y = 12, ys = 3, text = "Полезности", tx = 5, ty = 1, bg = 0x444444, fg = 0x3375cc},
  account = {x = 31, xs = 20, y = 16, ys = 3, text = "Исключить", tx = 5, ty = 1, bg = 0x444444, fg = 0x3375cc}
}

local function drawButton(btn)
  gpu.setBackground(btn.bg)
  gpu.fill(btn.x, btn.y, btn.xs, btn.ys, " ")
  gpu.setForeground(btn.fg)
  gpu.set(btn.x + btn.tx, btn.y + btn.ty, btn.text)
  gpu.setBackground(0x000000)
end

local function drawBottomPanel()
  gpu.setForeground(0xcc3342)
  gpu.set(4, 23, "[Помощь]")
  gpu.setForeground(0x00FF00)
  gpu.set(33, 23, "[Конвертация + / $]")
  gpu.setForeground(0xcc3342)
  gpu.set(69, 23, "[Отзывы]")
end

-- Строка состояния (отладка) внизу слева
local function drawDebug(text)
  gpu.setForeground(0x888888)
  gpu.set(1, 25, "                                                                                ")
  gpu.set(1, 25, text)
end

local function drawWelcomeScreen()
  gpu.setBackground(0x202020)
  gpu.fill(1, 1, 80, 25, " ")
  drawDebug("Экран приветствия")

  local prefix = "Приветствуем в "
  local shop = "NEXAR SHOP"
  local full = prefix .. shop
  local startX = math.floor((80 - unicode.len(full)) / 2) + 1
  gpu.setForeground(0xFFFFFF)
  gpu.set(startX, 2, prefix)
  gpu.setForeground(0x00FF00)
  gpu.set(startX + unicode.len(prefix), 2, shop)

  drawBigText(4, "NEXAR SHOP", 0x00FF00, 0x006600)

  gpu.setForeground(0x00FF00)
  drawCenteredText(11, "↓   Встаньте на PIM   ↓", 0x00FF00)
  drawCenteredText(12, "━━━━━━━━━━━━━━━━━━━━", 0x00FF00)

  gpu.setForeground(0x414243)
  drawCenteredText(15, "По любым вопросам пишите в Telegram: f0rb4ik", 0x414243)

  gpu.setBackground(0x000000)
end

local function drawAuthScreen(remaining)
  gpu.setBackground(0x202020)
  gpu.fill(1, 1, 80, 25, " ")
  drawDebug(string.format("Авторизация... %.1f сек", remaining))

  local prefix = "Приветствуем в "
  local shop = "NEXAR SHOP"
  local full = prefix .. shop
  local startX = math.floor((80 - unicode.len(full)) / 2) + 1
  gpu.setForeground(0xFFFFFF)
  gpu.set(startX, 2, prefix)
  gpu.setForeground(0x00FF00)
  gpu.set(startX + unicode.len(prefix), 2, shop)

  drawBigText(4, "NEXAR SHOP", 0x00FF00, 0x006600)

  gpu.setForeground(0xFFFFFF)
  drawCenteredText(12, "Авторизация....", 0xFFFFFF)

  gpu.setForeground(0x414243)
  drawCenteredText(15, "По любым вопросам пишите в Telegram: f0rb4ik", 0x414243)

  gpu.setBackground(0x000000)
end

local function drawMainMenu()
  clear()
  drawDebug("Главное меню")

  if currentPlayer then
    local pink1 = "Добро пожаловать, "
    local white1 = currentPlayer .. "!"
    local full1 = pink1 .. white1
    local x1 = math.floor((80 - unicode.len(full1)) / 2) + 1
    gpu.setForeground(0xFF00FF)
    gpu.set(x1, 4, pink1)
    gpu.setForeground(0xFFFFFF)
    gpu.set(x1 + unicode.len(pink1), 4, white1)

    local pink2 = "Ваш баланс: "
    local white2 = string.format("%.2f", playerBalance) .. " Эмов"
    local full2 = pink2 .. white2
    local x2 = math.floor((80 - unicode.len(full2)) / 2) + 1
    gpu.setForeground(0xFF00FF)
    gpu.set(x2, 6, pink2)
    gpu.setForeground(0xFFFFFF)
    gpu.set(x2 + unicode.len(pink2), 6, white2)

    for _, btn in pairs(menuButtons) do
      drawButton(btn)
    end
    drawBottomPanel()
  else
    drawWelcomeScreen()
  end
end

local function drawPlaceholder(title)
  clear()
  drawDebug(title)
  drawCenteredText(8, title .. " (в разработке)", 0x00FF00)
  gpu.setBackground(0x333333)
  gpu.fill(2, 22, 12, 3, " ")
  gpu.setForeground(0xFFFFFF)
  gpu.set(4, 23, "Назад")
  gpu.setBackground(0x000000)
end

local function goToShop() currentScreen = "shop"; drawPlaceholder("Магазин") end
local function goToUtility() currentScreen = "utility"; drawPlaceholder("Полезности") end
local function goToAccount() currentScreen = "account"; drawPlaceholder("Исключить") end
local function goBackToMenu() currentScreen = "menu"; drawMainMenu() end

-- Завершение авторизации
local function finishAuth()
  print("Авторизация завершена, переход в меню")
  modem.send(serverAddress, 0xffef, serialization.serialize({op = "enter"}))
  currentScreen = "menu"
  drawMainMenu()
end

-- ======== Инициализация ========
drawWelcomeScreen()
modem.send(serverAddress, 0xffef, serialization.serialize({op = "register"}))
print("Терминал отправляет регистрацию...")

-- ======== Главный цикл ========
while true do
  local ev = {event.pull(0.1)}   -- короткий интервал для частой проверки таймера
  local e = ev[1]

  -- Проверка таймера авторизации (только в состоянии auth)
  if currentScreen == "auth" then
    local remaining = AUTH_DELAY - (os.clock() - authStartTime)
    if remaining <= 0 then
      finishAuth()
    else
      -- обновляем строку состояния раз в ~0.5 сек, чтобы не мерцало
      -- (можно и чаще, но не критично)
      drawDebug(string.format("Авторизация... %.1f сек", remaining))
    end
  end

  if e == "touch" then
    local x, y = ev[3], ev[4]
    if currentScreen == "menu" then
      for name, btn in pairs(menuButtons) do
        if x >= btn.x and x < btn.x + btn.xs and y >= btn.y and y < btn.y + btn.ys then
          if name == "shop" then goToShop()
          elseif name == "util" then goToUtility()
          elseif name == "account" then goToAccount() end
          break
        end
      end
    elseif currentScreen == "shop" or currentScreen == "utility" or currentScreen == "account" then
      if x >= 2 and x <= 13 and y >= 22 and y <= 24 then goBackToMenu() end
    end
  elseif e == "player_on" or e == "pim" then
    -- оба события для совместимости
    local playerName = ev[2] or "Игрок"
    currentPlayer = playerName:match("^%s*(.-)%s*$") or playerName
    playerBalance = 0.00
    print("Игрок встал на PIM: " .. currentPlayer)
    if currentScreen ~= "auth" then
      currentScreen = "auth"
      authStartTime = os.clock()
      drawAuthScreen(AUTH_DELAY)
    end
  elseif e == "player_off" then
    print("Игрок сошёл с PIM")
    currentPlayer = nil
    currentScreen = "welcome"
    drawWelcomeScreen()
  elseif e == "modem_message" then
    local _, _, from, port, data = ev[2], ev[3], ev[4], ev[5], ev[6]
    if from == serverAddress then
      local success, msg = pcall(serialization.unserialize, data)
      if success and msg and msg.op == "welcome" then
        terminalRegistered = true
        print("✅ Терминал зарегистрирован на сервере")
        if msg.balance then playerBalance = tonumber(msg.balance) or playerBalance end
        if currentScreen == "menu" then drawMainMenu() end
      end
    end
  end
end
