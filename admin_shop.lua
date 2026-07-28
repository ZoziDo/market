-- ============================================================
-- VIP-SHOP
-- Визуальная копия + интерактив
-- OpenComputers / OpenOS / GPU API / Lua 5.2
-- ============================================================

local component = require("component")
local gpu       = component.gpu
local term      = require("term")
local event     = require("event")
local keyboard  = require("keyboard")

-- ====================== РАЗРЕШЕНИЕ ======================
local WIDTH, HEIGHT = gpu.getResolution()
local maxW, maxH = gpu.maxResolution()
if WIDTH < maxW or HEIGHT < maxH then
  gpu.setResolution(maxW, maxH)
  WIDTH, HEIGHT = gpu.getResolution()
end

-- ====================== ЦВЕТА ======================
local C = {
  bg            = 0x0C0C0C,
  border        = 0x00AAAA,
  borderDark    = 0x008888,
  white         = 0xFFFFFF,
  gray          = 0xAAAAAA,
  darkGray      = 0x555555,
  green         = 0x55FF55,
  yellow        = 0xFFFF55,
  red           = 0xFF5555,
  cyan          = 0x55FFFF,

  selectedBg    = 0x002440,   -- подсветка выбранного товара
  star          = 0x0a502d,   -- цвет *
  vipTitle      = 0x0c9a76,   -- VIP-SHOP
  catalogLine   = 0x0b4b3b,   -- линии каталога
  infoLine      = 0x0b424b,   -- линии инфо
  underLine     = 0x1f2925,   -- линия под VIP-SHOP

  buttonBuy     = 0x0a502d,
  buttonSell    = 0x5a1a1a,
  buttonClear   = 0x333333,
  inputBg       = 0x1a1a1a,
  inputFg       = 0xFFFFFF,
}

-- ====================== ВСПОМОГАТЕЛЬНЫЕ ======================
local function setBG(c) gpu.setBackground(c) end
local function setFG(c) gpu.setForeground(c) end

local function fill(x, y, w, h, c)
  setBG(c)
  gpu.fill(x, y, w, h, " ")
end

local function text(x, y, str, fg, bg)
  if bg then setBG(bg) end
  if fg then setFG(fg) end
  gpu.set(x, y, str)
end

-- ====================== РАЗМЕРЫ ======================
local TOP_H   = 2
local BOT_H   = 3
local MAIN_Y  = 3
local MAIN_H  = HEIGHT - TOP_H - BOT_H

local LEFT_W  = math.floor(WIDTH * 0.62)
local RIGHT_W = WIDTH - LEFT_W

local LIST_X  = 2
local LIST_Y  = MAIN_Y + 4
local LIST_H  = MAIN_H - 5
local LIST_W  = LEFT_W - 3
local SCROLL_X = LEFT_W - 1

local COL_NAME_X  = 3
local COL_ME_X    = LEFT_W - 28
local COL_COINA_X = LEFT_W - 18
local COL_EMA_X   = LEFT_W - 10

local RIGHT_INNER_X = LEFT_W + 2
local RIGHT_INNER_W = RIGHT_W - 3

local INFO_Y  = MAIN_Y + 3
local INFO_H  = 11

local INPUT_Y = INFO_Y + INFO_H + 1
local TOTAL_Y = INPUT_Y + 2
local BTN_Y   = TOTAL_Y + 2

local BOT_Y   = HEIGHT - 2

-- ====================== ДАННЫЕ ======================
local items = {
  {name = "Дракониевая пыль",                    me = "365",   coina = "0", ema = "0",   star = true,  price = 12},
  {name = "Бумага",                              me = "2",     coina = "0", ema = "0",   star = true,  price = 1},
  {name = "Медовые соты",                        me = "121",   coina = "0", ema = "0",   star = true,  price = 8},
  {name = "Сборщик фруктов",                     me = "2",     coina = "0", ema = "0",   star = true,  price = 45},
  {name = "Ведро ледяного криотеума",            me = "0",     coina = "0", ema = "0",   star = false, price = 30},
  {name = "Светло-серая минеральная шерсть",     me = "0",     coina = "0", ema = "0",   star = false, price = 5},
  {name = "Сырая баранина",                      me = "278",   coina = "0", ema = "0",   star = true,  price = 3},
  {name = "Голова странника Края",               me = "4.7k",  coina = "0", ema = "0",   star = true,  price = 120},
  {name = "МЭ жидкостная шина импорта",          me = "1",     coina = "0", ema = "0",   star = true,  price = 85},
  {name = "Реакторная камера",                   me = "0",     coina = "0", ema = "11.7",star = false, price = 200},
  {name = "Авто-варщик",                         me = "1",     coina = "0", ema = "0",   star = true,  price = 60},
  {name = "Дракониевый блок",                    me = "0",     coina = "0", ema = "0",   star = false, price = 90},
  {name = "Яблоко",                              me = "5.5k",  coina = "0", ema = "0",   star = true,  price = 2},
  {name = "item.item_portable_cell_advanced.name",me = "1",    coina = "0", ema = "0",   star = true,  price = 150},
  {name = "Ведро",                               me = "158",   coina = "0", ema = "0.3", star = true,  price = 4},
  {name = "Чан",                                 me = "8",     coina = "0", ema = "0",   star = true,  price = 25},
  {name = "Охлаждающее ядро",                    me = "0",     coina = "0", ema = "0",   star = false, price = 70},
  {name = "$8Тёмное покрытие",                   me = "0",     coina = "0", ema = "7.6", star = false, price = 40},
  {name = "$8Тёмный порошок",                    me = "0",     coina = "0", ema = "0.2", star = false, price = 15},
  {name = "МЭ беспроводная точка доступа",       me = "0",     coina = "0", ema = "0",   star = false, price = 110},
  {name = "Кристалл истинного кварца",           me = "20.3k", coina = "0", ema = "0",   star = true,  price = 6},
  {name = "Измельчённый никель",                 me = "1.4k",  coina = "0", ema = "0",   star = true,  price = 9},
  {name = "Алмазный нагрудник",                  me = "0",     coina = "0", ema = "0",   star = false, price = 300},
  {name = "Анализатор",                          me = "8",     coina = "0", ema = "0",   star = true,  price = 55},
  {name = "Одуванчик",                           me = "1.7k",  coina = "0", ema = "0",   star = true,  price = 1},
  {name = "Пробирки ядро",                       me = "0",     coina = "0", ema = "0",   star = false, price = 35},
  {name = "Стеклянная панель",                   me = "269",   coina = "0", ema = "0",   star = true,  price = 2},
  {name = "Комбайн",                             me = "1",     coina = "0", ema = "0",   star = true,  price = 80},
  {name = "Усиленная жидкостная труба",          me = "512",   coina = "0", ema = "0",   star = true,  price = 18},
  {name = "Расширение: Пространственно-временной унификатор флакса", me = "0", coina = "0", ema = "0", star = false, price = 250},
  {name = "Руда урана",                          me = "5.9k",  coina = "0", ema = "0",   star = true,  price = 14},
  {name = "Электрическая мотыга",                me = "1",     coina = "0", ema = "0",   star = true,  price = 45},
  {name = "Пергамент",                           me = "0",     coina = "0", ema = "0",   star = false, price = 3},
  {name = "Камень Воскрешения",                  me = "0",     coina = "0", ema = "0",   star = false, price = 500},
  {name = "Производитель лавы",                  me = "1",     coina = "0", ema = "0",   star = true,  price = 95},
  {name = "Контур печатной платы",               me = "0",     coina = "0", ema = "7.6", star = false, price = 22},
}

local selectedIndex = 22
local scrollOffset  = 0
local quantity      = ""
local totalPrice    = 0

-- ====================== ОТРИСОВКА ======================
local function drawBackground()
  fill(1, 1, WIDTH, HEIGHT, C.bg)
end

local function drawTopBar()
  fill(1, 1, WIDTH, 2, 0x0A0A0A)

  -- VIP-SHOP
  local title = "VIP-SHOP"
  text(math.floor((WIDTH - #title) / 2) + 1, 1, title, C.vipTitle, 0x0A0A0A)

  -- линия под VIP-SHOP
  setFG(C.underLine)
  setBG(0x0A0A0A)
  gpu.set(1, 2, string.rep("═", WIDTH))

  -- текст под линией
  text(2, 2, "Управление каталогом товаров", C.white, 0x0A0A0A)
end

local function drawMainFrames()
  setBG(C.bg)
  setFG(C.catalogLine)

  gpu.set(1, MAIN_Y, "╔" .. string.rep("═", WIDTH - 2) .. "╗")
  for y = MAIN_Y + 1, MAIN_Y + MAIN_H - 2 do
    gpu.set(1, y, "║")
    gpu.set(WIDTH, y, "║")
  end
  gpu.set(1, MAIN_Y + MAIN_H - 1, "╚" .. string.rep("═", WIDTH - 2) .. "╝")

  -- вертикальный разделитель
  setFG(C.catalogLine)
  for y = MAIN_Y + 1, MAIN_Y + MAIN_H - 2 do
    gpu.set(LEFT_W, y, "║")
  end

  -- горизонтальные линии под заголовками
  local headerY = MAIN_Y + 2
  setFG(C.catalogLine)
  for x = 2, LEFT_W - 1 do
    gpu.set(x, headerY, "─")
  end

  setFG(C.infoLine)
  for x = LEFT_W + 1, WIDTH - 1 do
    gpu.set(x, headerY, "─")
  end

  gpu.set(LEFT_W, MAIN_Y, "╦")
  gpu.set(LEFT_W, MAIN_Y + MAIN_H - 1, "╩")
  gpu.set(LEFT_W, headerY, "╬")
end

local function drawLeftHeader()
  text(3, MAIN_Y + 1, "КАТАЛОГ ТОВАРОВ", C.catalogLine, C.bg)

  local colY = MAIN_Y + 3
  fill(2, colY, LEFT_W - 2, 1, C.bg)
  text(COL_NAME_X,  colY, "ТОВАР",  C.white, C.bg)
  text(COL_ME_X,    colY, "В ME",   C.white, C.bg)
  text(COL_COINA_X, colY, "COINA",  C.white, C.bg)
  text(COL_EMA_X,   colY, "EMA",    C.white, C.bg)
end

local function drawScrollbar()
  setBG(C.bg)
  setFG(C.borderDark)
  gpu.set(SCROLL_X, LIST_Y - 1, "┬")
  for y = LIST_Y, LIST_Y + LIST_H - 1 do
    gpu.set(SCROLL_X, y, "│")
  end
  gpu.set(SCROLL_X, LIST_Y + LIST_H, "┴")

  local thumbH = math.max(3, math.floor(LIST_H * (#items / math.max(#items, LIST_H))))
  local maxScroll = math.max(0, #items - LIST_H)
  local thumbY = LIST_Y
  if maxScroll > 0 then
    thumbY = LIST_Y + math.floor((scrollOffset / maxScroll) * (LIST_H - thumbH))
  end
  setFG(C.cyan)
  for i = 0, thumbH - 1 do
    if thumbY + i <= LIST_Y + LIST_H - 1 then
      gpu.set(SCROLL_X, thumbY + i, "█")
    end
  end
end

local function drawItemRow(index, y)
  local item = items[index]
  if not item then return end

  local isSelected = (index == selectedIndex)

  if isSelected then
    fill(LIST_X, y, LIST_W, 1, C.selectedBg)
  else
    fill(LIST_X, y, LIST_W, 1, C.bg)
  end

  local fgName  = isSelected and C.white or C.white
  local fgMe    = isSelected and C.white or (item.star and C.green or C.red)
  local fgCoina = isSelected and C.white or C.gray
  local fgEma   = isSelected and C.white or (item.ema ~= "0" and C.yellow or C.gray)

  local marker = item.star and "* " or "- "
  if isSelected then marker = "> " end

  local maxNameLen = COL_ME_X - COL_NAME_X - 2
  local displayName = marker .. item.name
  if #displayName > maxNameLen then
    displayName = displayName:sub(1, maxNameLen - 1) .. "…"
  end

  local starColor = item.star and C.star or C.darkGray
  if isSelected then starColor = C.white end

  text(COL_NAME_X, y, displayName, fgName, isSelected and C.selectedBg or C.bg)
  text(COL_ME_X,   y, item.me,    fgMe,   isSelected and C.selectedBg or C.bg)
  text(COL_COINA_X,y, item.coina, fgCoina,isSelected and C.selectedBg or C.bg)
  text(COL_EMA_X,  y, item.ema,   fgEma,  isSelected and C.selectedBg or C.bg)
end

local function drawProductList()
  fill(LIST_X, LIST_Y, LIST_W, LIST_H, C.bg)
  local visibleCount = LIST_H
  local startIdx = scrollOffset + 1
  local endIdx   = math.min(#items, startIdx + visibleCount - 1)

  for i = startIdx, endIdx do
    local rowY = LIST_Y + (i - startIdx)
    drawItemRow(i, rowY)
  end
  drawScrollbar()
end

local function drawInfoBlock()
  fill(RIGHT_INNER_X, INFO_Y, RIGHT_INNER_W, INFO_H, C.bg)

  local item = items[selectedIndex]
  if not item then return end

  local y = INFO_Y

  text(RIGHT_INNER_X, y, "Товар:", C.gray, C.bg)
  text(RIGHT_INNER_X + 7, y, item.name, C.white, C.bg)
  y = y + 1

  text(RIGHT_INNER_X, y, "ID: item." .. selectedIndex, C.cyan, C.bg)
  y = y + 2

  text(RIGHT_INNER_X, y, "Цена: ", C.gray, C.bg)
  text(RIGHT_INNER_X + 6, y, tostring(item.price) .. " EMA", C.yellow, C.bg)
  y = y + 1

  text(RIGHT_INNER_X, y, "В ME: ", C.gray, C.bg)
  text(RIGHT_INNER_X + 6, y, item.me, C.green, C.bg)
  y = y + 1

  text(RIGHT_INNER_X, y, "COINA: ", C.gray, C.bg)
  text(RIGHT_INNER_X + 7, y, item.coina, C.white, C.bg)
  y = y + 1

  text(RIGHT_INNER_X, y, "EMA: ", C.gray, C.bg)
  text(RIGHT_INNER_X + 5, y, item.ema, C.yellow, C.bg)
end

local function drawQuantityInput()
  fill(RIGHT_INNER_X, INPUT_Y, RIGHT_INNER_W, 3, C.bg)

  text(RIGHT_INNER_X, INPUT_Y, "Количество:", C.gray, C.bg)

  -- поле ввода
  local inputW = 12
  fill(RIGHT_INNER_X, INPUT_Y + 1, inputW, 1, C.inputBg)
  text(RIGHT_INNER_X, INPUT_Y + 1, quantity .. (quantity == "" and "_" or ""), C.inputFg, C.inputBg)

  -- итоговая цена
  local item = items[selectedIndex]
  if item and quantity ~= "" then
    local qty = tonumber(quantity) or 0
    totalPrice = qty * item.price
    text(RIGHT_INNER_X, TOTAL_Y, "Итого: " .. totalPrice .. " EMA", C.yellow, C.bg)
  else
    text(RIGHT_INNER_X, TOTAL_Y, "Итого: 0 EMA", C.gray, C.bg)
  end
end

local function drawActionButtons()
  local btnW = 12
  local gap  = 2

  -- Купить
  setBG(C.buttonBuy)
  setFG(C.white)
  gpu.fill(RIGHT_INNER_X, BTN_Y, btnW, 1, " ")
  gpu.set(RIGHT_INNER_X + 2, BTN_Y, " Купить ")

  -- Очистить
  setBG(C.buttonClear)
  setFG(C.white)
  gpu.fill(RIGHT_INNER_X + btnW + gap, BTN_Y, btnW, 1, " ")
  gpu.set(RIGHT_INNER_X + btnW + gap + 1, BTN_Y, " Очистить ")
end

local function drawRightPanel()
  text(LEFT_W + 3, MAIN_Y + 1, "ИНФО", C.infoLine, C.bg)

  drawInfoBlock()
  drawQuantityInput()
  drawActionButtons()
end

local function drawBottomBar()
  fill(1, BOT_Y, WIDTH, 2, 0x0A0A0A)

  setFG(C.catalogLine)
  setBG(C.bg)
  gpu.set(1, BOT_Y - 1, "╠" .. string.rep("═", WIDTH - 2) .. "╣")

  local btnW = 14
  local buyX = math.floor(WIDTH / 2) - btnW - 2
  local sellX = math.floor(WIDTH / 2) + 2

  -- Покупка
  setBG(C.buttonBuy)
  setFG(C.white)
  gpu.fill(buyX, BOT_Y, btnW, 1, " ")
  gpu.set(buyX + 3, BOT_Y, "Покупка")

  -- Продажа
  setBG(C.buttonSell)
  setFG(C.white)
  gpu.fill(sellX, BOT_Y, btnW, 1, " ")
  gpu.set(sellX + 3, BOT_Y, "Продажа")
end

local function drawBottomBorder()
  setFG(C.catalogLine)
  setBG(C.bg)
  gpu.set(1, HEIGHT, "╚" .. string.rep("═", WIDTH - 2) .. "╝")
end

local function redrawAll()
  drawBackground()
  drawTopBar()
  drawMainFrames()
  drawLeftHeader()
  drawProductList()
  drawRightPanel()
  drawBottomBar()
  drawBottomBorder()
end

-- ====================== ЛОГИКА ======================
local function selectItem(index)
  if index < 1 then index = 1 end
  if index > #items then index = #items end
  selectedIndex = index

  -- автоскролл
  if selectedIndex - 1 < scrollOffset then
    scrollOffset = selectedIndex - 1
  elseif selectedIndex > scrollOffset + LIST_H then
    scrollOffset = selectedIndex - LIST_H
  end

  quantity = ""
  totalPrice = 0
  drawProductList()
  drawRightPanel()
end

local function scroll(delta)
  local maxScroll = math.max(0, #items - LIST_H)
  scrollOffset = math.max(0, math.min(maxScroll, scrollOffset + delta))
  drawProductList()
end

local function handleClick(x, y)
  -- клик по списку товаров
  if x >= LIST_X and x <= LIST_X + LIST_W and y >= LIST_Y and y <= LIST_Y + LIST_H - 1 then
    local row = y - LIST_Y
    local index = scrollOffset + row + 1
    if index >= 1 and index <= #items then
      selectItem(index)
    end
    return
  end

  -- клик по кнопке Очистить
  local btnW = 12
  local gap  = 2
  local clearX = RIGHT_INNER_X + btnW + gap
  if y == BTN_Y and x >= clearX and x < clearX + btnW then
    quantity = ""
    totalPrice = 0
    drawQuantityInput()
    return
  end

  -- клик по кнопке Купить (пока просто визуально)
  if y == BTN_Y and x >= RIGHT_INNER_X and x < RIGHT_INNER_X + btnW then
    -- здесь можно добавить реальную покупку
    return
  end
end

-- ====================== ГЛАВНЫЙ ЦИКЛ ======================
term.clear()
redrawAll()

while true do
  local ev = {event.pull()}
  local name = ev[1]

  if name == "touch" then
    local x, y = ev[3], ev[4]
    handleClick(x, y)

  elseif name == "scroll" then
    local x, y, direction = ev[3], ev[4], ev[5]
    if x >= LIST_X and x <= LIST_X + LIST_W + 1 then
      scroll(-direction)  -- direction: 1 вверх, -1 вниз
    end

  elseif name == "key_down" then
    local _, _, char, code = table.unpack(ev)

    if code == keyboard.keys.up then
      selectItem(selectedIndex - 1)
    elseif code == keyboard.keys.down then
      selectItem(selectedIndex + 1)
    elseif code == keyboard.keys.enter then
      -- подтверждение количества (можно расширить)
    elseif code == keyboard.keys.back then
      quantity = quantity:sub(1, -2)
      drawQuantityInput()
    elseif char and char >= 48 and char <= 57 then -- цифры 0-9
      if #quantity < 6 then
        quantity = quantity .. string.char(char)
        drawQuantityInput()
      end
    elseif code == keyboard.keys.q or code == keyboard.keys.escape then
      break
    end
  end
end

-- выход
term.clear()
gpu.setForeground(0xFFFFFF)
gpu.setBackground(0x000000)
