local component = require("component")
local gpu = component.gpu
local term = require("term")
local event = require("event")
local keyboard = require("keyboard")
local unicode = require("unicode")
local json = require("json")
local internet = require("internet")

local WIDTH, HEIGHT = gpu.getResolution()
local maxW, maxH = gpu.maxResolution()
if WIDTH < maxW or HEIGHT < maxH then
  gpu.setResolution(maxW, maxH)
  WIDTH, HEIGHT = gpu.getResolution()
end

-- ============================================
-- ЦВЕТА
-- ============================================
local C = {
  bg = 0x0C0C0C, white = 0xFFFFFF, gray = 0xAAAAAA, darkGray = 0x555555,
  green = 0x55FF55, yellow = 0xFFFF55, red = 0xFF5555, cyan = 0x55FFFF,
  selectedBg = 0x002440, selectedName = 0x00e6b1, star = 0x077d42,
  vipTitle = 0x0c9a76, underLine = 0x428A72, mainLine = 0x7FFFD4,
  sectionLine = 0x27BDEC, headerBg = 0x1A2D33, notFound = 0xF50016,
  buttonBuy = 0x0a502d, buttonClear = 0x8b1a1a, buttonSales = 0x1a5a6b,
  inputBg = 0x1a1a1a, inputFg = 0xFFFFFF, accent = 0x0c9a76, frame = 0x27BDEC,
}

-- ============================================
-- КЭШ И ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ
-- ============================================
local cachedCatalog = nil
local cachedSellItems = nil
local cacheTimestamp = 0
local CACHE_LIFETIME = 30
local catalogData = {}
local sellItemsData = {}
local shopItems = {}

local blacklist = {
  ["customnpcs:npcMoney"] = true,
}

local function setBG(c) gpu.setBackground(c) end
local function setFG(c) gpu.setForeground(c) end
local function fill(x, y, w, h, c) setBG(c) gpu.fill(x, y, w, h, " ") end
local function text(x, y, str, fg, bg)
  if bg then setBG(bg) end
  if fg then setFG(fg) end
  gpu.set(x, y, str)
end
local function sectionHeader(x, y, w, title, lineColor, titleColor)
  lineColor = lineColor or C.sectionLine
  titleColor = titleColor or C.white
  setBG(C.bg) setFG(lineColor)
  gpu.set(x, y, string.rep("-", w))
  setFG(titleColor)
  gpu.set(x + 1, y, title)
end
local function truncate(str, maxLen)
  if #str <= maxLen then return str end
  return str:sub(1, maxLen - 3) .. "..."
end

-- ============================================
-- HTTP ФУНКЦИИ
-- ============================================
function httpGet(url, timeout)
  if not component.isAvailable("internet") then
    return nil, "No internet component available"
  end
  
  timeout = timeout or 5
  local result, err = internet.request(url, nil, nil, timeout)
  
  if not result then
    return nil, err or "Connection failed"
  end
  
  local data = ""
  while true do
    local chunk = result.read()
    if not chunk then break end
    data = data .. chunk
  end
  result.close()
  
  local ok, parsed = pcall(json.decode, data)
  if ok then
    return parsed, nil
  else
    return {raw = data}, nil
  end
end

-- ============================================
-- ЗАГРУЗКА КАТАЛОГА
-- ============================================
function loadCatalogFromServer()
  local url = "http://201.24.112.170:8080/data/catalog.json"
  local result, err = httpGet(url, 5)
  if result then
    return result
  else
    return {}
  end
end

function loadSellItemsFromServer()
  local url = "http://201.24.112.170:8080/data/sell_items.json"
  local result, err = httpGet(url, 5)
  if err then
    return {}
  end
  if result and result.sellItems then
    return result.sellItems
  else
    return {}
  end
end

function sortableName(name)
  if not name then return "" end
  local lower = string.lower(name)
  local result = lower:gsub("(%d+)", function(d)
    return string.format("%08d", tonumber(d))
  end)
  return result
end

function getActualItemQuantity(internalName, damage)
  if not component.isAvailable("me_interface") then return 0 end
  local me = component.me_interface
  local items = me.getItemsInNetwork()
  local total = 0
  for _, meItem in ipairs(items) do
    if meItem.name == internalName and (meItem.damage or 0) == (damage or 0) then
      total = total + (meItem.size or 0)
    end
  end
  return total
end

function exportFromME(itemName, damage, amount)
  if not component.isAvailable("me_interface") then return 0 end
  local me = component.me_interface
  local id = itemName
  if not id:find(":") then
    id = "minecraft:" .. id
  end
  local fingerprint = { id = id, dmg = damage or 0 }
  local success, result = pcall(function()
    return me.exportItem(fingerprint, "down", amount)
  end)
  if success then
    if type(result) == "number" then
      return result
    elseif type(result) == "boolean" and result == true then
      return amount
    elseif type(result) == "table" then
      if result.count then return result.count end
      if result.amount then return result.amount end
      if result.size then return result.size end
    end
  end
  return 0
end

-- ИСПРАВЛЕННАЯ ФУНКЦИЯ
function loadBuyItemsFast()
  if not component.isAvailable("me_interface") then 
    return 
  end
  
  if not cachedCatalog then
    cachedCatalog = loadCatalogFromServer()
  end
  
  catalogData = cachedCatalog or {}
  if not catalogData or next(catalogData) == nil then
    return
  end
  
  local me = component.me_interface
  local rawItems = me.getItemsInNetwork()
  local tempShopItems = {}
  
  for _, meItem in ipairs(rawItems) do
    local name = meItem.name
    if blacklist[name] then
      -- пропускаем
    else
      local qty = meItem.size or 0
      if qty == 0 then
        -- пропускаем
      else
        local damage = meItem.damage or 0
        local mapKey = name .. ":" .. damage
        
        local mapping = catalogData[mapKey]
        if not mapping then
          -- пропускаем
        else
          local displayName = mapping.displayName
          local priceCoin = mapping.priceCoin or 0
          local priceEma = mapping.priceEma or 0
          if priceCoin <= 0 and priceEma <= 0 then
            -- пропускаем
          else
            local key = name .. ":" .. damage
            if tempShopItems[key] then
              tempShopItems[key].qty = tempShopItems[key].qty + qty
            else
              tempShopItems[key] = {
                internalName = name,
                displayName = displayName,
                qty = qty,
                priceCoin = priceCoin,
                priceEma = priceEma,
                damage = damage,
                canBuy = true
              }
            end
          end -- if priceCoin <= 0
        end -- if not mapping
      end -- if qty == 0
    end -- if blacklist
  end -- for

  shopItems = {}
  for key, itemData in pairs(tempShopItems) do
    table.insert(shopItems, itemData)
  end

  table.sort(shopItems, function(a, b)
    return sortableName(a.displayName) < sortableName(b.displayName)
  end)
end

function loadSellItemsFast()
  if not cachedSellItems then
    cachedSellItems = loadSellItemsFromServer()
  end
  
  sellItemsData = cachedSellItems or {}
  shopItems = {}
  
  for _, item in ipairs(sellItemsData) do
    local internal = item.internalName or item.name
    if internal then
      local priceCoin = item.priceCoin or 0
      local priceEma = item.priceEma or 0
      
      if priceCoin > 0 or priceEma > 0 then
        table.insert(shopItems, {
          displayName = item.displayName or item.name or internal,
          internalName = internal,
          qty = item.qty or 0,
          priceCoin = priceCoin,
          priceEma = priceEma,
          damage = item.damage or 0,
          canSell = true
        })
      end
    end
  end
  
  table.sort(shopItems, function(a, b)
    return sortableName(a.displayName) < sortableName(b.displayName)
  end)
end

-- ============================================
-- РАЗМЕРЫ ЭКРАНА
-- ============================================
local TOP_H = 3
local BOT_H = 3
local MAIN_Y = 4
local MAIN_H = HEIGHT - TOP_H - BOT_H
local LEFT_W = math.floor(WIDTH * 0.60)
local SCROLL_X = LEFT_W - 2
local SEPARATOR1 = LEFT_W
local SEPARATOR2 = LEFT_W + 1
local LIST_X = 2
local LIST_Y = MAIN_Y + 3
local LIST_H = MAIN_H - 4
local LIST_W = SCROLL_X - 3
local COL_NAME_X = 3
local COL_ME_X = SCROLL_X - 26
local COL_COINA_X = SCROLL_X - 16
local COL_EMA_X = SCROLL_X - 7
local RIGHT_INNER_X = LEFT_W + 3
local RIGHT_INNER_W = WIDTH - RIGHT_INNER_X - 1
local INFO_Y = MAIN_Y + 1
local QTY_Y = INFO_Y + 8
local TOTAL_Y = QTY_Y + 5
local BTN_Y = TOTAL_Y + 2
local ACC_Y = BTN_Y + 3
local BOT_Y = HEIGHT - 2

-- ============================================
-- ДАННЫЕ И ПЕРЕМЕННЫЕ
-- ============================================
local items = {}
local selectedIndex = 1
local scrollOffset = 0
local quantity = ""
local searchQuery = ""
local searchFocused = false
local qtyFocused = false

local account = {
  nick = "Player_777",
  coina = "12500",
  ema = "842.5",
  regDate = "12.03.2025",
  trans = "148",
}

-- Загружаем товары из МЭ системы
local function loadItems()
  loadBuyItemsFast()
  items = {}
  for i, v in ipairs(shopItems) do
    items[i] = v
  end
  if #items == 0 then
    -- Если МЭ система не доступна или пуста, используем тестовые данные
    items = {
      {name="Дракониевая пыль", me="365", coina="12", ema="0.8", star=true},
      {name="Бумага", me="2", coina="1", ema="0.1", star=true},
      {name="Медовые соты", me="121", coina="8", ema="0.5", star=true},
      {name="Сборщик фруктов", me="2", coina="45", ema="3.2", star=true},
      {name="Ведро ледяного криотеума", me="0", coina="30", ema="2.1", star=false},
      {name="Светло-серая минеральная шерсть", me="0", coina="5", ema="0.3", star=false},
      {name="Сырая баранина", me="278", coina="3", ema="0.2", star=true},
      {name="Голова странника Края", me="4.7k", coina="120", ema="8.5", star=true},
      {name="МЭ жидкостная шина импорта", me="1", coina="85", ema="6.0", star=true},
      {name="Реакторная камера", me="0", coina="200", ema="14.0", star=false},
      {name="Авто-варщик", me="1", coina="60", ema="4.2", star=true},
      {name="Дракониевый блок", me="0", coina="90", ema="6.5", star=false},
      {name="Яблоко", me="5.5k", coina="2", ema="0.15", star=true},
      {name="item.item_portable_cell_advanced.name", me="1", coina="150", ema="10.5", star=true},
      {name="Ведро", me="158", coina="4", ema="0.3", star=true},
      {name="Чан", me="8", coina="25", ema="1.8", star=true},
      {name="Охлаждающее ядро", me="0", coina="70", ema="5.0", star=false},
      {name="$8Тёмное покрытие", me="0", coina="40", ema="2.8", star=false},
      {name="$8Тёмный порошок", me="0", coina="15", ema="1.0", star=false},
      {name="МЭ беспроводная точка доступа", me="0", coina="110", ema="7.8", star=false},
      {name="Кристалл истинного кварца", me="20.3k", coina="6", ema="0.4", star=true},
      {name="Измельчённый никель", me="1.4k", coina="9", ema="0.6", star=true},
      {name="Алмазный нагрудник", me="0", coina="300", ema="21.0", star=false},
      {name="Анализатор", me="8", coina="55", ema="3.9", star=true},
      {name="Одуванчик", me="1.7k", coina="1", ema="0.05", star=true},
      {name="Пробирки ядро", me="0", coina="35", ema="2.5", star=false},
      {name="Стеклянная панель", me="269", coina="2", ema="0.15", star=true},
      {name="Комбайн", me="1", coina="80", ema="5.6", star=true},
      {name="Усиленная жидкостная труба", me="512", coina="18", ema="1.3", star=true},
      {name="Расширение: Пространственно-временной унификатор флакса", me="0", coina="250", ema="17.5", star=false},
      {name="Руда урана", me="5.9k", coina="14", ema="1.0", star=true},
      {name="Электрическая мотыга", me="1", coina="45", ema="3.2", star=true},
      {name="Пергамент", me="0", coina="3", ema="0.2", star=false},
      {name="Камень Воскрешения", me="0", coina="500", ema="35.0", star=false},
      {name="Производитель лавы", me="1", coina="95", ema="6.7", star=true},
      {name="Контур печатной платы", me="0", coina="22", ema="1.5", star=false},
    }
  end
end

local function filterItems()
  items = {}
  if searchQuery == "" then
    loadItems()
  else
    local q = searchQuery:lower()
    for _, v in ipairs(shopItems) do
      if v.name:lower():find(q, 1, true) then
        items[#items + 1] = v
      end
    end
  end
  selectedIndex = 1
  scrollOffset = 0
end

-- ============================================
-- ФУНКЦИЯ ПОКУПКИ С ЭКСПОРТОМ ИЗ МЭ
-- ============================================
local function performPurchase()
  local item = items[selectedIndex]
  if not item then return end
  
  local qty = tonumber(quantity) or 1
  if qty <= 0 then
    qty = 1
    quantity = "1"
    drawQuantitySection()
    return
  end
  
  local actualQty = getActualItemQuantity(item.internalName, item.damage or 0)
  if actualQty == 0 then
    text(RIGHT_INNER_X, TOTAL_Y + 2, "❌ Товар закончился!", C.red, C.bg)
    return
  end
  
  if qty > actualQty then
    qty = actualQty
    quantity = tostring(qty)
    drawQuantitySection()
  end
  
  local totalCoina = qty * (tonumber(item.coina) or 0)
  local totalEma = qty * (tonumber(item.ema) or 0)
  
  -- Проверка баланса (здесь нужно добавить вашу логику проверки)
  -- ...
  
  -- Экспорт из МЭ системы
  local exported = exportFromME(item.internalName, item.damage or 0, qty)
  
  if exported == 0 then
    text(RIGHT_INNER_X, TOTAL_Y + 2, "❌ Не удалось выдать предметы!", C.red, C.bg)
    return
  end
  
  if exported < qty then
    text(RIGHT_INNER_X, TOTAL_Y + 2, string.format("⚠️ Выдано %d из %d шт.", exported, qty), C.yellow, C.bg)
  else
    text(RIGHT_INNER_X, TOTAL_Y + 2, string.format("✅ Куплено %d шт.", exported), C.green, C.bg)
  end
  
  -- Обновляем количество в МЭ
  item.me = tostring(getActualItemQuantity(item.internalName, item.damage or 0))
  
  -- Обновляем отображение
  drawProductList()
  drawInfoBlock()
  drawQuantitySection()
end

-- ============================================
-- ФУНКЦИИ ОТРИСОВКИ
-- ============================================
local function drawBackground()
  fill(1, 1, WIDTH, HEIGHT, C.bg)
end

local function drawTopBar()
  fill(1, 1, WIDTH, 3, 0x0A0A0A)
  local title = "VIP-SHOP"
  text(math.floor((WIDTH - #title) / 2) + 1, 1, title, C.vipTitle, 0x0A0A0A)
  setFG(C.underLine)
  setBG(0x0A0A0A)
  gpu.set(1, 2, string.rep("=", WIDTH))
  local searchW = 40
  local searchX = 2
  local searchY = 3
  setFG(C.frame)
  setBG(C.bg)
  gpu.set(searchX - 1, searchY, "[" .. string.rep(" ", searchW) .. "]")
  fill(searchX, searchY, searchW, 1, C.inputBg)
  if searchQuery == "" and not searchFocused then
    text(searchX + 1, searchY, "Поиск...", C.darkGray, C.inputBg)
  else
    text(searchX + 1, searchY, searchQuery, C.inputFg, C.inputBg)
  end
  local clearX = searchX + searchW + 2
  setBG(C.buttonClear)
  setFG(C.white)
  gpu.fill(clearX, searchY, 11, 1, " ")
  gpu.set(clearX + 1, searchY, "[ Стереть ]")
end

local function drawMainFrames()
  setBG(C.bg)
  setFG(C.mainLine)
  gpu.set(1, MAIN_Y, "+" .. string.rep("=", WIDTH - 2) .. "+")
  for y = MAIN_Y + 1, MAIN_Y + MAIN_H - 2 do
    gpu.set(1, y, "|")
    gpu.set(WIDTH, y, "|")
  end
  gpu.set(1, MAIN_Y + MAIN_H - 1, "+" .. string.rep("=", WIDTH - 2) .. "+")
end

local function drawLeftHeader()
  sectionHeader(2, MAIN_Y + 1, LEFT_W - 3, "КАТАЛОГ ТОВАРОВ", C.mainLine, C.white)
  local colY = MAIN_Y + 2
  fill(2, colY, LEFT_W - 3, 1, C.headerBg)
  text(COL_NAME_X, colY, "ТОВАР", C.white, C.headerBg)
  text(COL_ME_X, colY, "В ME", C.white, C.headerBg)
  text(COL_COINA_X, colY, "COINA", C.white, C.headerBg)
  text(COL_EMA_X, colY, "EMA", C.white, C.headerBg)
end

local function drawSeparator()
  setBG(C.bg)
  setFG(C.mainLine)
  for y = MAIN_Y + 1, MAIN_Y + MAIN_H - 2 do
    gpu.set(SEPARATOR1, y, "|")
    gpu.set(SEPARATOR2, y, "|")
  end
  gpu.set(SEPARATOR1, MAIN_Y, "+")
  gpu.set(SEPARATOR2, MAIN_Y, "+")
  gpu.set(SEPARATOR1, MAIN_Y + MAIN_H - 1, "+")
  gpu.set(SEPARATOR2, MAIN_Y + MAIN_H - 1, "+")
end

local function drawScrollbar()
  setBG(C.bg)
  setFG(C.darkGray)
  for y = LIST_Y, LIST_Y + LIST_H - 1 do
    gpu.set(SCROLL_X, y, " ")
  end
  local maxScroll = math.max(0, #items - LIST_H)
  local thumbH = math.max(3, math.floor(LIST_H * 0.25))
  local thumbY = LIST_Y
  if maxScroll > 0 then
    thumbY = LIST_Y + math.floor((scrollOffset / maxScroll) * (LIST_H - thumbH))
  end
  setBG(C.accent)
  for i = 0, thumbH - 1 do
    local yy = thumbY + i
    if yy >= LIST_Y and yy <= LIST_Y + LIST_H - 1 then
      gpu.set(SCROLL_X, yy, " ")
    end
  end
  setBG(C.bg)
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
  local nameColor = isSelected and C.selectedName or C.white
  local meColor = item.star and C.green or C.red
  local coinaColor = C.yellow
  local emaColor = C.cyan
  if isSelected then
    text(COL_NAME_X, y, "> ", C.selectedName, C.selectedBg)
  else
    if item.star then
      text(COL_NAME_X, y, "* ", C.star, C.bg)
    else
      text(COL_NAME_X, y, "- ", C.darkGray, C.bg)
    end
  end
  local maxNameLen = COL_ME_X - COL_NAME_X - 2
  local displayName = truncate(item.name, maxNameLen - 2)
  text(COL_NAME_X + 2, y, displayName, nameColor, isSelected and C.selectedBg or C.bg)
  text(COL_ME_X, y, item.me, meColor, isSelected and C.selectedBg or C.bg)
  text(COL_COINA_X, y, item.coina, coinaColor, isSelected and C.selectedBg or C.bg)
  text(COL_EMA_X, y, item.ema, emaColor, isSelected and C.selectedBg or C.bg)
end

local function drawProductList()
  fill(LIST_X, LIST_Y, LIST_W, LIST_H, C.bg)
  if #items == 0 then
    local msg = "ПО ТВОЕМУ ЗАПРОСУ, НИЧЕГО НЕ НАЙДЕНО!"
    local visualLen = 35
    local mx = LIST_X + math.floor((LIST_W - visualLen) / 2)
    local my = LIST_Y + math.floor(LIST_H / 2)
    text(mx, my, msg, C.notFound, C.bg)
    return
  end
  local startIdx = scrollOffset + 1
  local endIdx = math.min(#items, startIdx + LIST_H - 1)
  for i = startIdx, endIdx do
    drawItemRow(i, LIST_Y + (i - startIdx))
  end
end

local function drawInfoBlock()
  fill(RIGHT_INNER_X, INFO_Y, RIGHT_INNER_W, 7, C.bg)
  sectionHeader(RIGHT_INNER_X, INFO_Y, RIGHT_INNER_W, "ИНФОРМАЦИЯ", C.sectionLine, C.white)
  local item = items[selectedIndex]
  if not item then return end
  local maxLen = RIGHT_INNER_W - 8
  local y = INFO_Y + 2
  text(RIGHT_INNER_X, y, "Товар: " .. truncate(item.name, maxLen), C.white, C.bg)
  y = y + 1
  text(RIGHT_INNER_X, y, "В ME : " .. item.me, C.green, C.bg)
  y = y + 1
  text(RIGHT_INNER_X, y, "COINA: " .. item.coina, C.yellow, C.bg)
  y = y + 1
  text(RIGHT_INNER_X, y, "EMA  : " .. item.ema, C.cyan, C.bg)
end

local function drawQuantitySection()
  fill(RIGHT_INNER_X, QTY_Y, RIGHT_INNER_W, 9, C.bg)
  sectionHeader(RIGHT_INNER_X, QTY_Y, RIGHT_INNER_W, "КОЛИЧЕСТВО", C.sectionLine, C.white)
  local fieldY = QTY_Y + 2
  setFG(C.frame)
  setBG(C.bg)
  gpu.set(RIGHT_INNER_X, fieldY, "[" .. string.rep(" ", RIGHT_INNER_W - 2) .. "]")
  fill(RIGHT_INNER_X + 1, fieldY, RIGHT_INNER_W - 2, 1, C.inputBg)
  if quantity == "" then
    text(RIGHT_INNER_X + 2, fieldY, "Введите количество...", C.darkGray, C.inputBg)
  else
    text(RIGHT_INNER_X + 2, fieldY, quantity, C.inputFg, C.inputBg)
  end
  local item = items[selectedIndex]
  local qty = tonumber(quantity) or 0
  local totalCoina = 0
  local totalEma = 0
  if item then
    totalCoina = qty * (tonumber(item.coina) or 0)
    totalEma = qty * (tonumber(item.ema) or 0)
  end
  text(RIGHT_INNER_X, TOTAL_Y, string.format("Итог: COINA: %s | EMA: %s", totalCoina, totalEma), C.yellow, C.bg)
  
  local btnW = 12
  local gap = 2
  setBG(C.buttonBuy)
  setFG(C.white)
  gpu.fill(RIGHT_INNER_X, BTN_Y, btnW, 1, " ")
  gpu.set(RIGHT_INNER_X + 1, BTN_Y, "[ Купить ]")
  setBG(C.buttonClear)
  setFG(C.white)
  gpu.fill(RIGHT_INNER_X + btnW + gap, BTN_Y, btnW, 1, " ")
  gpu.set(RIGHT_INNER_X + btnW + gap + 1, BTN_Y, "[ Стереть ]")
end

local function drawAccountInfo()
  fill(RIGHT_INNER_X, ACC_Y, RIGHT_INNER_W, 8, C.bg)
  sectionHeader(RIGHT_INNER_X, ACC_Y, RIGHT_INNER_W, "АККАУНТ", C.sectionLine, C.white)
  local y = ACC_Y + 2
  text(RIGHT_INNER_X, y, "Имя: " .. account.nick, C.white, C.bg)
  y = y + 1
  text(RIGHT_INNER_X, y, "Баланс: " .. account.coina .. " COINA | " .. account.ema .. " EMA", C.yellow, C.bg)
  y = y + 1
  text(RIGHT_INNER_X, y, "Регистрация: " .. account.regDate, C.gray, C.bg)
  y = y + 1
  text(RIGHT_INNER_X, y, "Транзакции: " .. account.trans, C.cyan, C.bg)
end

local function drawRightPanel()
  drawInfoBlock()
  drawQuantitySection()
  drawAccountInfo()
end

local function drawBottomBar()
  fill(1, BOT_Y, WIDTH, 2, 0x0A0A0A)
  setFG(C.mainLine)
  setBG(C.bg)
  gpu.set(1, BOT_Y - 1, "+" .. string.rep("=", WIDTH - 2) .. "+")
  local btnW = 14
  local gap = 2
  local leftMargin = 2
  local buyX = leftMargin
  local salesX = buyX + btnW + gap
  setBG(C.buttonBuy)
  setFG(C.white)
  gpu.fill(buyX, BOT_Y, btnW, 1, " ")
  gpu.set(buyX + 2, BOT_Y, "[ Покупки ]")
  setBG(C.buttonSales)
  setFG(C.white)
  gpu.fill(salesX, BOT_Y, btnW, 1, " ")
  gpu.set(salesX + 2, BOT_Y, "[ Продажи ]")
end

local function drawBottomBorder()
  setFG(C.mainLine)
  setBG(C.bg)
  gpu.set(1, HEIGHT, "+" .. string.rep("=", WIDTH - 2) .. "+")
end

local function redrawAll()
  drawBackground()
  drawTopBar()
  drawMainFrames()
  drawLeftHeader()
  drawProductList()
  drawScrollbar()
  drawRightPanel()
  drawBottomBar()
  drawBottomBorder()
  drawSeparator()
end

local function selectItem(index)
  if #items == 0 then return end
  if index < 1 then index = 1 end
  if index > #items then index = #items end
  selectedIndex = index
  if selectedIndex - 1 < scrollOffset then
    scrollOffset = selectedIndex - 1
  elseif selectedIndex > scrollOffset + LIST_H then
    scrollOffset = selectedIndex - LIST_H
  end
  quantity = ""
  drawProductList()
  drawScrollbar()
  drawRightPanel()
end

local function scroll(delta)
  local maxScroll = math.max(0, #items - LIST_H)
  scrollOffset = math.max(0, math.min(maxScroll, scrollOffset + delta))
  drawProductList()
  drawScrollbar()
end

local function handleClick(x, y)
  searchFocused = false
  qtyFocused = false
  
  if x >= LIST_X and x <= LIST_X + LIST_W and y >= LIST_Y and y <= LIST_Y + LIST_H - 1 then
    local row = y - LIST_Y
    local index = scrollOffset + row + 1
    if index >= 1 and index <= #items then
      selectItem(index)
    end
    return
  end
  
  local searchW = 40
  local clearX = 2 + searchW + 2
  if y == 3 and x >= clearX and x < clearX + 11 then
    searchQuery = ""
    filterItems()
    redrawAll()
    return
  end
  
  if y == 3 and x >= 2 and x <= 2 + searchW then
    searchFocused = true
    return
  end
  
  local fieldY = QTY_Y + 2
  if y == fieldY and x >= RIGHT_INNER_X and x <= RIGHT_INNER_X + RIGHT_INNER_W then
    qtyFocused = true
    return
  end
  
  local btnW = 12
  local gap = 2
  local buyX = RIGHT_INNER_X
  if y == BTN_Y and x >= buyX and x < buyX + btnW then
    performPurchase()
    return
  end
  
  local clearQtyX = RIGHT_INNER_X + btnW + gap
  if y == BTN_Y and x >= clearQtyX and x < clearQtyX + btnW then
    quantity = ""
    drawQuantitySection()
  end
end

-- ============================================
-- ИНИЦИАЛИЗАЦИЯ
-- ============================================
term.clear()
filterItems()
redrawAll()

-- ============================================
-- ГЛАВНЫЙ ЦИКЛ
-- ============================================
while true do
  local ev = {event.pull()}
  local name = ev[1]
  
  if name == "touch" then
    handleClick(ev[3], ev[4])
    
  elseif name == "scroll" then
    local x, direction = ev[3], ev[5]
    if x >= LIST_X and x <= LIST_X + LIST_W + 2 then
      scroll(-direction)
    end
    
  elseif name == "key_down" then
    local _, _, char, code = table.unpack(ev)
    
    if searchFocused then
      if code == keyboard.keys.enter or code == keyboard.keys.tab then
        searchFocused = false
      elseif code == keyboard.keys.back then
        searchQuery = searchQuery:sub(1, -2)
        filterItems()
        redrawAll()
      elseif char and char >= 32 then
        if #searchQuery < 30 then
          searchQuery = searchQuery .. unicode.char(char)
          filterItems()
          redrawAll()
        end
      end
      
    elseif qtyFocused then
      if code == keyboard.keys.enter or code == keyboard.keys.tab then
        qtyFocused = false
      elseif code == keyboard.keys.back then
        quantity = quantity:sub(1, -2)
        drawQuantitySection()
      elseif char and char >= 48 and char <= 57 then
        if #quantity < 8 then
          quantity = quantity .. string.char(char)
          drawQuantitySection()
        end
      end
      
    else
      if code == keyboard.keys.up then
        selectItem(selectedIndex - 1)
      elseif code == keyboard.keys.down then
        selectItem(selectedIndex + 1)
      elseif code == keyboard.keys.back then
        quantity = quantity:sub(1, -2)
        drawQuantitySection()
      elseif char and char >= 48 and char <= 57 then
        if #quantity < 8 then
          quantity = quantity .. string.char(char)
          drawQuantitySection()
        end
      elseif code == keyboard.keys.q or code == keyboard.keys.escape then
        break
      end
    end
  end
end

term.clear()
gpu.setForeground(0xFFFFFF)
gpu.setBackground(0x000000)
