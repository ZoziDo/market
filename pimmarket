local component = require("component")
local event = require("event")
local gpu = component.gpu

local modem = component.modem
local pimList = {}
for addr in component.list("pim") do table.insert(pimList, addr) end
local pim = component.proxy(pimList[1])

modem.open(0xffef)
modem.open(0xfffe)

local serverAddress = "535305a9-37c9-4645-b7c4-46204187ee7b"

gpu.setResolution(80, 25)
gpu.setBackground(0x000000)

-- Текущий игрок и его баланс (обновляются при входе/сообщениях)
local currentPlayer = nil
local playerBalance = 0.00   -- заглушка, потом будем получать с сервера

local function clear()
  gpu.setBackground(0x000000)
  gpu.fill(1, 1, 80, 25, " ")
end

-- Универсальная функция для вывода текста по центру
local function drawCenteredText(y, text, color)
  gpu.setForeground(color or 0xFFFFFF)
  local x = math.floor((80 - #text) / 2) + 1
  gpu.set(x, y, text)
end

-- Отрисовка строки с разными цветами (для приветствия и баланса)
local function drawColoredLine(y, parts)
  -- parts = { {text="Добро пожаловать, ", color=0xFF00FF}, {text="Player", color=0xFFFFFF} }
  local fullText = ""
  for _, part in ipairs(parts) do
    fullText = fullText .. part.text
  end
  local x = math.floor((80 - #fullText) / 2) + 1
  for _, part in ipairs(parts) do
    gpu.setForeground(part.color)
    gpu.set(x, y, part.text)
    x = x + #part.text
  end
end

-- Кнопки главного меню
local menuButtons = {
  shop = {
    x = 31, xs = 20, y = 8,  ys = 3,
    text = "Магазин",
    tx = 6, ty = 1,
    bg = 0x444444, fg = 0xFFFF00
  },
  util = {
    x = 31, xs = 20, y = 12, ys = 3,
    text = "Полезности",
    tx = 5, ty = 1,
    bg = 0x444444, fg = 0xFFFF00
  },
  account = {
    x = 31, xs = 20, y = 16, ys = 3,
    text = "Исключить",   -- изменено на "Исключить" по скрину
    tx = 5, ty = 1,       -- tx = (20 - 8)/2 = 6, но "Исключить" 8 букв, центр 4, сдвинем на 5
    bg = 0x444444, fg = 0xFFFF00
  }
}

local function drawButton(btn)
  gpu.setBackground(btn.bg)
  gpu.fill(btn.x, btn.y, btn.xs, btn.ys, " ")
  gpu.setForeground(btn.fg)
  gpu.set(btn.x + btn.tx, btn.y + btn.ty, btn.text)
  gpu.setBackground(0x000000)
end

-- Нижняя панель с разным цветом
local function drawBottomPanel()
  -- [Помощь] красным
  gpu.setForeground(0xFF0000)
  gpu.set(4, 23, "[Помощь]")

  -- [Конвертация + / $] зелёным, но символ + синим
  local convX = 33
  gpu.setForeground(0x00FF00)   -- зелёный
  gpu.set(convX, 23, "[Конвертация ")
  gpu.setForeground(0x0000FF)   -- синий для "+"
  gpu.set(convX + #"[Конвертация ", 23, "+")
  gpu.setForeground(0x00FF00)   -- снова зелёный
  gpu.set(convX + #"[Конвертация +", 23, " / $]")

  -- [Отзывы] красным, справа
  gpu.setForeground(0xFF0000)
  gpu.set(69, 23, "[Отзывы]")
end

local function drawMainMenu()
  clear()

  -- Приветствие и баланс (если игрок есть)
  if currentPlayer then
    drawColoredLine(4, {
      {text = "Добро пожаловать, ", color = 0xFF00FF},   -- розовый
      {text = currentPlayer, color = 0xFFFFFF}            -- белый
    })
    drawColoredLine(6, {
      {text = "Ваш баланс: ", color = 0xFF00FF},
      {text = string.format("%.2f", playerBalance) .. " Эмов", color = 0xFFFFFF}
    })
  else
    -- Если игрока нет, показываем просьбу встать на PIM (необязательно)
    drawCenteredText(5, "Встаньте на PIM", 0xFFFF00)
  end

  -- Кнопки
  for _, btn in pairs(menuButtons) do
    drawButton(btn)
  end

  -- Нижняя панель
  drawBottomPanel()
end

drawMainMenu()

-- Основной цикл обработки событий
while true do
  local ev = {event.pull(1)}
  local e = ev[1]

  if e == "touch" then
    local x, y = ev[3], ev[4]
    -- Проверка попадания в кнопки меню
    for name, btn in pairs(menuButtons) do
      if x >= btn.x and x < btn.x + btn.xs and y >= btn.y and y < btn.y + btn.ys then
        drawCenteredText(13, "→ " .. btn.text .. " ←", 0x00FF00)
        os.sleep(1)
        drawMainMenu()
        break
      end
    end
  end

  if e == "player_on" or e == "pim" then
    -- Игрок встал на PIM
    currentPlayer = ev[2]   -- имя игрока из события
    -- Баланс пока 0, но можно запросить у сервера (позже)
    playerBalance = 0.00
    drawMainMenu()
  end

  if e == "player_off" then
    -- Игрок ушёл
    currentPlayer = nil
    drawMainMenu()   -- покажет "Встаньте на PIM"
  end
end
