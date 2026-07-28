-- ============================================================
-- SHOP-ADMIN v3.0
-- Полная визуальная копия GUI со скриншота
-- OpenComputers / OpenOS / GPU API / Lua 5.2
-- ============================================================

local component = require("component")
local gpu = component.gpu
local term = require("term")

-- ====================== РАЗРЕШЕНИЕ ======================
local WIDTH, HEIGHT = gpu.getResolution()
local maxW, maxH = gpu.maxResolution()
if WIDTH < maxW or HEIGHT < maxH then
  gpu.setResolution(maxW, maxH)
  WIDTH, HEIGHT = gpu.getResolution()
end

-- ====================== ЦВЕТА ======================
local C = {
  bg          = 0x0C0C0C,
  panel       = 0x101010,
  border      = 0x00AAAA,
  borderDark  = 0x008888,
  white       = 0xFFFFFF,
  gray        = 0xAAAAAA,
  darkGray    = 0x555555,
  green       = 0x55FF55,
  yellow      = 0xFFFF55,
  red         = 0xFF5555,
  cyan        = 0x55FFFF,
  blue        = 0x0055AA,
  blueDark    = 0x003366,
  title       = 0xFFFFFF,
  header      = 0x00AAAA,
  buttonBg    = 0x222222,
  buttonText  = 0xFFFFFF,
  logBg       = 0x0A0A0A,
  logText     = 0xAAAAAA,
  selectedBg  = 0x0055AA,
  selectedFg  = 0xFFFFFF,
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
local TOP_H   = 1
local BOT_H   = 3
local MAIN_Y  = 2
local MAIN_H  = HEIGHT - TOP_H - BOT_H

local LEFT_W  = math.floor(WIDTH * 0.62)
local LEFT_X  = 1
local RIGHT_X = LEFT_W + 1
local RIGHT_W = WIDTH - LEFT_W

local LIST_X  = 2
local LIST_Y  = MAIN_Y + 4
local LIST_H  = MAIN_H - 5
local LIST_W  = LEFT_W - 3
local SCROLL_X = LEFT_W - 1

local COL_NAME_X  = 3
local COL_ME_X    = LEFT_W - 28
local COL_MIN_X   = LEFT_W - 18
local COL_PRICE_X = LEFT_W - 10

local RIGHT_INNER_X = LEFT_W + 2
local RIGHT_INNER_W = RIGHT_W - 3

local INFO_Y  = MAIN_Y + 3
local INFO_H  = 12
local LOG_Y   = INFO_Y + INFO_H + 1
local LOG_H   = MAIN_H - INFO_H - 4

local BOT_Y   = HEIGHT - 2

-- ====================== ДАННЫЕ ======================
local items = {
  {name = "Дракониевая пыль",                    me = "365",   min = "0", price = "0 EM",   color = C.green,  star = true},
  {name = "Бумага",                              me = "2",     min = "0", price = "0 EM",   color = C.green,  star = true},
  {name = "Медовые соты",                        me = "121",   min = "0", price = "0 EM",   color = C.green,  star = true},
  {name = "Сборщик фруктов",                     me = "2",     min = "0", price = "0 EM",   color = C.green,  star = true},
  {name = "Ведро ледяного криотеума",            me = "0",     min = "0", price = "0 EM",   color = C.red,    star = false},
  {name = "Светло-серая минеральная шерсть",     me = "0",     min = "0", price = "0 EM",   color = C.red,    star = false},
  {name = "Сырая баранина",                      me = "278",   min = "0", price = "0 EM",   color = C.green,  star = true},
  {name = "Голова странника Края",               me = "4.7k",  min = "0", price = "0 EM",   color = C.green,  star = true},
  {name = "МЭ жидкостная шина импорта",          me = "1",     min = "0", price = "0 EM",   color = C.green,  star = true},
  {name = "Реакторная камера",                   me = "0",     min = "0", price = "11.7 EM",color = C.red,    star = false},
  {name = "Авто-варщик",                         me = "1",     min = "0", price = "0 EM",   color = C.green,  star = true},
  {name = "Дракониевый блок",                    me = "0",     min = "0", price = "0 EM",   color = C.red,    star = false},
  {name = "Яблоко",                              me = "5.5k",  min = "0", price = "0 EM",   color = C.green,  star = true},
  {name = "item.item_portable_cell_advanced.name",me = "1",    min = "0", price = "0 EM",   color = C.green,  star = true},
  {name = "Ведро",                               me = "158",   min = "0", price = "0.3 EM", color = C.green,  star = true},
  {name = "Чан",                                 me = "8",     min = "0", price = "0 EM",   color = C.green,  star = true},
  {name = "Охлаждающее ядро",                    me = "0",     min = "0", price = "0 EM",   color = C.red,    star = false},
  {name = "$8Тёмное покрытие",                   me = "0",     min = "0", price = "7.6 EM", color = C.red,    star = false},
  {name = "$8Тёмный порошок",                    me = "0",     min = "0", price = "0.2 EM", color = C.red,    star = false},
  {name = "МЭ беспроводная точка доступа",       me = "0",     min = "0", price = "0 EM",   color = C.red,    star = false},
  {name = "Кристалл истинного кварца",           me = "20.3k", min = "0", price = "0 EM",   color = C.green,  star = true},
  {name = "Измельчённый никель",                 me = "1.4k",  min = "0", price = "0 EM",   color = C.green,  star = true},
  {name = "Алмазный нагрудник",                  me = "0",     min = "0", price = "0 EM",   color = C.red,    star = false},
  {name = "Анализатор",                          me = "8",     min = "0", price = "0 EM",   color = C.green,  star = true},
  {name = "Одуванчик",                           me = "1.7k",  min = "0", price = "0 EM",   color = C.green,  star = true},
  {name = "Пробирки ядро",                       me = "0",     min = "0", price = "0 EM",   color = C.red,    star = false},
  {name = "Стеклянная панель",                   me = "269",   min = "0", price = "0 EM",   color = C.green,  star = true},
  {name = "Комбайн",                             me = "1",     min = "0", price = "0 EM",   color = C.green,  star = true},
  {name = "Усиленная жидкостная труба",          me = "512",   min = "0", price = "0 EM",   color = C.green,  star = true},
  {name = "Расширение: Пространственно-временной унификатор флакса", me = "0", min = "0", price = "0 EM", color = C.red, star = false},
  {name = "Руда урана",                          me = "5.9k",  min = "0", price = "0 EM",   color = C.green,  star = true},
  {name = "Электрическая мотыга",                me = "1",     min = "0", price = "0 EM",   color = C.green,  star = true},
  {name = "Пергамент",                           me = "0",     min = "0", price = "0 EM",   color = C.red,    star = false},
  {name = "Камень Воскрешения",                  me = "0",     min = "0", price = "0 EM",   color = C.red,    star = false},
  {name = "Производитель лавы",                  me = "1",     min = "0", price = "0 EM",   color = C.green,  star = true},
  {name = "Контур печатной платы",               me = "0",     min = "0", price = "7.6 EM", color = C.red,    star = false},
}

local selectedIndex = 22
local scrollOffset  = 0

local selectedItem = {
  name  = "Измельчённый никель",
  id    = "ThermalFoundation:material:36",
  price = "0 EM",
  me    = "1.4k",
  min   = "0",
  craft = "64",
}

local logLines = {
  {text = "[697:46] Обменник – скоро",                    color = C.yellow},
  {text = "[697:16] OK: получено 1215 товаров",           color = C.green},
  {text = "[697:03] Загрузка БД с КУ...",                 color = C.gray},
  {text = "[697:03] Цены OK: 0 обн., 0 без пары",         color = C.green},
  {text = "[697:03] Запрос загрузки цен на ПК-1...",      color = C.gray},
  {text = "[697:03] Товаров: 1215",                       color = C.cyan},
  {text = "[697:03] OK: получено 1215 товаров",           color = C.green},
  {text = "[696:54] Загрузка БД с КУ...",                 color = C.gray},
  {text = "[696:54] Обновление с ПК-1...",                color = C.gray},
  {text = "[696:54] Товаров: 1215",                       color = C.cyan},
  {text = "[696:54] OK: получено 1215 товаров",           color = C.green},
  {text = "[696:44] Загрузка БД с КУ...",                 color = C.gray},
  {text = "[696:44] Обновление с ПК-1...",                color = C.gray},
  {text = "[696:44] OK: получено 1215 товаров",           color = C.green},
  {text = "[696:31] Загрузка БД с КУ...",                 color = C.gray},
  {text = "[696:31] Цены OK: 0 обн., 0 без пары",         color = C.green},
  {text = "[696:31] Запрос загрузки цен на ПК-1...",      color = C.gray},
  {text = "[01:19] OK: получено 1215 товаров",            color = C.green},
  {text = "[01:07] Загрузка БД с КУ...",                  color = C.gray},
  {text = "[01:07] Загрузка БД с ПК-1...",                color = C.gray},
}

local buttons = {
  {label = " ОБНОВИТЬ ",   bg = 0x0055AA, fg = C.white},
  {label = " ИЗМЕНИТЬ ",   bg = 0x333333, fg = C.white},
  {label = " УДАЛИТЬ ",    bg = 0xAA0000, fg = C.white},
  {label = " ОБМЕННИК ",   bg = 0x005555, fg = C.white},
  {label = " БЭКАП КУ ",   bg = 0x333333, fg = C.white},
  {label = " ЦЕНЫ->БД ",   bg = 0x333333, fg = C.white},
  {label = " FORTUNE 1 ",  bg = 0xAA8800, fg = C.white},
  {label = "[-]",          bg = 0x444444, fg = C.yellow},
  {label = "[+]",          bg = 0x444444, fg = C.yellow},
  {label = " ВЫХОД ",      bg = 0xAA0000, fg = C.white},
}

-- ====================== ФУНКЦИИ ОТРИСОВКИ ======================
local function drawBackground()
  fill(1, 1, WIDTH, HEIGHT, C.bg)
end

local function drawTopBar()
  fill(1, 1, WIDTH, 1, 0x0A0A0A)
  text(2, 1, "Управление каталогом товаров", C.white, 0x0A0A0A)
  local title = "SHOP-ADMIN v3.0"
  text(math.floor((WIDTH - #title) / 2) + 1, 1, title, C.cyan, 0x0A0A0A)
  text(WIDTH - 22, 1, "McSkill HiTech", C.gray, 0x0A0A0A)
  text(WIDTH - 8, 1, "UP:01:19", C.yellow, 0x0A0A0A)
end

local function drawMainFrames()
  setBG(C.bg)
  setFG(C.border)

  gpu.set(1, MAIN_Y, "╔" .. string.rep("═", WIDTH - 2) .. "╗")
  for y = MAIN_Y + 1, MAIN_Y + MAIN_H - 2 do
    gpu.set(1, y, "║")
    gpu.set(WIDTH, y, "║")
  end
  gpu.set(1, MAIN_Y + MAIN_H - 1, "╚" .. string.rep("═", WIDTH - 2) .. "╝")

  for y = MAIN_Y + 1, MAIN_Y + MAIN_H - 2 do
    gpu.set(LEFT_W, y, "║")
  end

  local headerY = MAIN_Y + 2
  setFG(C.border)
  for x = 2, LEFT_W - 1 do
    gpu.set(x, headerY, "─")
  end
  for x = LEFT_W + 1, WIDTH - 1 do
    gpu.set(x, headerY, "─")
  end

  gpu.set(LEFT_W, MAIN_Y, "╦")
  gpu.set(LEFT_W, MAIN_Y + MAIN_H - 1, "╩")
  gpu.set(LEFT_W, headerY, "╬")
end

local function drawLeftHeader()
  text(3, MAIN_Y + 1, "КАТАЛОГ ТОВАРОВ", C.header, C.bg)
  local colY = MAIN_Y + 3
  fill(2, colY, LEFT_W - 2, 1, C.bg)
  text(COL_NAME_X,  colY, "ТОВАР",   C.white, C.bg)
  text(COL_ME_X,    colY, "В ME",    C.white, C.bg)
  text(COL_MIN_X,   colY, "МИН",     C.white, C.bg)
  text(COL_PRICE_X, colY, "ЦЕНА EM", C.white, C.bg)
end

local function drawScrollbar()
  setBG(C.bg)
  setFG(C.borderDark)
  gpu.set(SCROLL_X, LIST_Y - 1, "┬")
  for y = LIST_Y, LIST_Y + LIST_H - 1 do
    gpu.set(SCROLL_X, y, "│")
  end
  gpu.set(SCROLL_X, LIST_Y + LIST_H, "┴")

  local thumbH = math.max(3, math.floor(LIST_H * 0.25))
  local thumbY = LIST_Y + math.floor((LIST_H - thumbH) / 2)
  setFG(C.cyan)
  for i = 0, thumbH - 1 do
    gpu.set(SCROLL_X, thumbY + i, "█")
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

  local fgName  = isSelected and C.selectedFg or C.white
  local fgMe    = isSelected and C.selectedFg or item.color
  local fgMin   = isSelected and C.selectedFg or C.gray
  local fgPrice = isSelected and C.selectedFg or (item.price ~= "0 EM" and C.yellow or C.gray)

  local marker = item.star and "* " or "- "
  if isSelected then marker = "> " end

  local maxNameLen = COL_ME_X - COL_NAME_X - 2
  local displayName = marker .. item.name
  if #displayName > maxNameLen then
    displayName = displayName:sub(1, maxNameLen - 1) .. "…"
  end

  text(COL_NAME_X, y, displayName, fgName, isSelected and C.selectedBg or C.bg)
  text(COL_ME_X,   y, item.me,    fgMe,   isSelected and C.selectedBg or C.bg)
  text(COL_MIN_X,  y, item.min,   fgMin,  isSelected and C.selectedBg or C.bg)
  text(COL_PRICE_X,y, item.price, fgPrice,isSelected and C.selectedBg or C.bg)
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
  local y = INFO_Y

  text(RIGHT_INNER_X, y, "Товар:", C.gray, C.bg)
  text(RIGHT_INNER_X + 7, y, selectedItem.name, C.white, C.bg)
  y = y + 1

  text(RIGHT_INNER_X, y, selectedItem.id, C.cyan, C.bg)
  y = y + 2

  text(RIGHT_INNER_X, y, "Цена: ", C.gray, C.bg)
  text(RIGHT_INNER_X + 6, y, selectedItem.price, C.yellow, C.bg)
  y = y + 1

  text(RIGHT_INNER_X, y, "В ME: ", C.gray, C.bg)
  text(RIGHT_INNER_X + 6, y, selectedItem.me, C.green, C.bg)
  y = y + 1

  text(RIGHT_INNER_X, y, "Мин: ", C.gray, C.bg)
  text(RIGHT_INNER_X + 5, y, selectedItem.min, C.white, C.bg)
  y = y + 1

  text(RIGHT_INNER_X, y, "Крафт: ", C.gray, C.bg)
  text(RIGHT_INNER_X + 7, y, selectedItem.craft, C.cyan, C.bg)
  y = y + 2

  setFG(C.borderDark)
  setBG(C.bg)
  gpu.set(RIGHT_INNER_X, y, string.rep("─", RIGHT_INNER_W))
  y = y + 1

  text(RIGHT_INNER_X, y, "F1  – взять из ME", C.gray, C.bg)
  y = y + 1
  text(RIGHT_INNER_X, y, "TAB – след. поле", C.gray, C.bg)
  y = y + 1
  text(RIGHT_INNER_X, y, "ENT – сохранить", C.gray, C.bg)
end

local function drawRightSeparator()
  setFG(C.border)
  setBG(C.bg)
  for x = LEFT_W + 1, WIDTH - 1 do
    gpu.set(x, LOG_Y - 1, "─")
  end
  gpu.set(LEFT_W, LOG_Y - 1, "╠")
  gpu.set(WIDTH, LOG_Y - 1, "╣")
end

local function drawLog()
  fill(RIGHT_INNER_X, LOG_Y - 1, RIGHT_INNER_W, 1, C.bg)
  text(RIGHT_INNER_X, LOG_Y - 1, "Лог:", C.header, C.bg)

  fill(RIGHT_INNER_X, LOG_Y, RIGHT_INNER_W, LOG_H, C.logBg)

  local maxLines = LOG_H
  local start = math.max(1, #logLines - maxLines + 1)

  for i = start, #logLines do
    local line = logLines[i]
    local row = LOG_Y + (i - start)
    if row <= LOG_Y + LOG_H - 1 then
      local txt = line.text
      if #txt > RIGHT_INNER_W then
        txt = txt:sub(1, RIGHT_INNER_W - 1) .. "…"
      end
      text(RIGHT_INNER_X, row, txt, line.color, C.logBg)
    end
  end
end

local function drawRightPanel()
  text(LEFT_W + 3, MAIN_Y + 1, "ИНФО", C.header, C.bg)
  text(LEFT_W + 10, MAIN_Y + 1, "ADMIN", C.cyan, C.bg)
  text(WIDTH - 6, MAIN_Y + 1, "PC-2", C.gray, C.bg)

  drawInfoBlock()
  drawRightSeparator()
  drawLog()
end

local function drawBottomBar()
  fill(1, BOT_Y, WIDTH, 2, 0x0A0A0A)

  setFG(C.border)
  setBG(C.bg)
  gpu.set(1, BOT_Y - 1, "╠" .. string.rep("═", WIDTH - 2) .. "╣")

  local x = 2
  for i, btn in ipairs(buttons) do
    local w = #btn.label
    setBG(btn.bg)
    setFG(btn.fg)
    gpu.fill(x, BOT_Y, w, 1, " ")
    gpu.set(x, BOT_Y, btn.label)
    x = x + w + 1

    if i == 6 then
      x = x + 2
    elseif i == 9 then
      x = WIDTH - #buttons[10].label - 1
    end
  end

  local exitBtn = buttons[10]
  local exitX = WIDTH - #exitBtn.label
  setBG(exitBtn.bg)
  setFG(exitBtn.fg)
  gpu.fill(exitX, BOT_Y, #exitBtn.label, 1, " ")
  gpu.set(exitX, BOT_Y, exitBtn.label)
end

local function drawBottomBorder()
  setFG(C.border)
  setBG(C.bg)
  gpu.set(1, HEIGHT, "╚" .. string.rep("═", WIDTH - 2) .. "╝")
end

-- ====================== ГЛАВНЫЙ ЗАПУСК ======================
term.clear()
drawBackground()
drawTopBar()
drawMainFrames()
drawLeftHeader()
drawProductList()
drawRightPanel()
drawBottomBar()
drawBottomBorder()

-- Убираем курсор
gpu.setForeground(C.bg)
gpu.setBackground(C.bg)
term.setCursor(1, HEIGHT)
