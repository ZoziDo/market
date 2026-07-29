local component = require("component")
local gpu = component.gpu
local term = require("term")
local event = require("event")
local keyboard = require("keyboard")
local unicode = require("unicode")
local fs = require("filesystem")
local json = require("json")
local os = require("os")

local WIDTH, HEIGHT = gpu.getResolution()
local maxW, maxH = gpu.maxResolution()
if WIDTH < maxW or HEIGHT < maxH then
  gpu.setResolution(maxW, maxH)
  WIDTH, HEIGHT = gpu.getResolution()
end

local C = {
  bg = 0x0C0C0C,
  white = 0xFFFFFF,
  gray = 0xAAAAAA,
  darkGray = 0x555555,
  green = 0x55FF55,
  yellow = 0xFFFF55,
  red = 0xFF5555,
  cyan = 0x55FFFF,
  selectedBg = 0x002440,
  selectedName = 0x00e6b1,
  star = 0x077d42,
  vipTitle = 0x0c9a76,
  underLine = 0x428A72,
  mainLine = 0x7FFFD4,
  sectionLine = 0x27BDEC,
  headerBg = 0x1A2D33,
  notFound = 0xF50016,
  buttonBuy = 0x0a502d,
  buttonClear = 0x8b1a1a,
  buttonSales = 0x1a5a6b,
  inputBg = 0x1a1a1a,
  inputFg = 0xFFFFFF,
  accent = 0x0c9a76,
  frame = 0x27BDEC,
  bgHover = 0x1a2a3a,
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
  setBG(C.bg)
  setFG(lineColor)
  gpu.set(x, y, string.rep("-", w))
  setFG(titleColor)
  gpu.set(x + 1, y, title)
end

local function truncate(str, maxLen)
  if #str <= maxLen then return str end
  return str:sub(1, maxLen - 3) .. "..."
end

local function sortableName(name)
  if not name then return "" end
  local lower = string.lower(name)
  return lower:gsub("(%d+)", function(d) return string.format("%08d", tonumber(d)) end)
end

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

local allItems = {}
local items = {}
local shopMode = "buy"

local selectedIndex = 1
local scrollOffset = 0
local quantity = ""
local searchQuery = ""
local searchFocused = false
local qtyFocused = false
local hoveredIndex = 0
local mouseDebounceTimer = nil
local pendingMouseX = 0
local pendingMouseY = 0

local selector = nil
for addr in component.list("openperipheral_selector") do
  selector = component.proxy(addr)
  break
end
if not selector then
  for addr in component.list("item_selector") do
    selector = component.proxy(addr)
    break
  end
end

local account = {
  nick = "Player_777",
  coina = "12500",
  ema = "842.5",
  regDate = "12.03.2025",
  trans = "148",
}

local ME = { interface = nil, available = false }

function ME.init()
  for addr in component.list("me_interface") do
    ME.interface = component.proxy(addr)
    ME.available = true
    break
  end
  if not ME.available then
    for addr in component.list("me_bridge") do
      ME.interface = component.proxy(addr)
      ME.available = true
      break
    end
  end
  return ME.available
end

function ME.getItemQuantity(internalName, damage)
  if not ME.available or not ME.interface then return 0 end
  damage = damage or 0
  local total = 0
  local ok, meItems = pcall(ME.interface.getItemsInNetwork, ME.interface)
  if ok and meItems then
    for _, meItem in ipairs(meItems) do
      local name = meItem.name or ""
      local itemDamage = meItem.damage or 0
      if name == internalName and itemDamage == damage then
        total = total + (meItem.size or meItem.qty or 0)
      end
    end
  end
  return total
end

function ME.exportItem(internalName, damage, quantity, direction)
  if not ME.available or not ME.interface then return 0 end
  direction = direction or "down"
  damage = damage or 0
  local fingerprint = { id = internalName, dmg = damage }
  local ok, result = pcall(ME.interface.exportItem, ME.interface, fingerprint, direction, quantity)
  if ok then
    if type(result) == "number" then return result end
    if type(result) == "boolean" and result == true then return quantity end
    return 0
  end
  return 0
end

function ME.importItem(internalName, damage, quantity, direction)
  if not ME.available or not ME.interface then return 0 end
  direction = direction or "up"
  damage = damage or 0
  local fingerprint = { id = internalName, dmg = damage }
  local ok, result = pcall(ME.interface.importItem, ME.interface, fingerprint, direction, quantity)
  if ok then
    if type(result) == "number" then return result end
    if type(result) == "boolean" and result == true then return quantity end
    return 0
  end
  return 0
end

local function loadCatalogFromFile()
  local catalogPath = "/data/catalog.json"
  if fs.exists(catalogPath) then
    local file = io.open(catalogPath, "r")
    if file then
      local content = file:read("*a")
      file:close()
      local ok, data = pcall(json.decode, content)
      if ok and data then return data end
    end
  end
  return nil
end

local function loadSellItemsFromFile()
  local sellPath = "/data/sell_items.json"
  if fs.exists(sellPath) then
    local file = io.open(sellPath, "r")
    if file then
      local content = file:read("*a")
      file:close()
      local ok, data = pcall(json.decode, content)
      if ok and data then return data end
    end
  end
  return nil
end

function loadItems()
  local newItems = {}
  ME.init()
  
  if shopMode == "buy" then
    local catalog = loadCatalogFromFile()
    if catalog then
      for key, itemData in pairs(catalog) do
        local name = itemData.displayName or key
        local meQty = ME.getItemQuantity(key, itemData.damage or 0)
        local meDisplay = tostring(meQty)
        if meQty >= 1000 then meDisplay = string.format("%.1fk", meQty / 1000) end
        table.insert(newItems, {
          name = name,
          me = meDisplay,
          meRaw = meQty,
          coina = tostring(itemData.priceCoin or "0"),
          ema = tostring(itemData.priceEma or "0"),
          star = itemData.star or false,
          internalName = key,
          damage = itemData.damage or 0,
          priceCoin = itemData.priceCoin or 0,
          priceEma = itemData.priceEma or 0,
          qty = meQty
        })
      end
    end
  else
    local sellItems = loadSellItemsFromFile()
    if sellItems then
      for _, itemData in ipairs(sellItems) do
        local name = itemData.displayName or itemData.internalName or "Unknown"
        local meQty = ME.getItemQuantity(itemData.internalName, itemData.damage or 0)
        local meDisplay = tostring(meQty)
        if meQty >= 1000 then meDisplay = string.format("%.1fk", meQty / 1000) end
        table.insert(newItems, {
          name = name,
          me = meDisplay,
          meRaw = meQty,
          coina = tostring(itemData.priceCoin or "0"),
          ema = tostring(itemData.priceEma or "0"),
          star = false,
          internalName = itemData.internalName,
          damage = itemData.damage or 0,
          priceCoin = itemData.priceCoin or 0,
          priceEma = itemData.priceEma or 0,
          qty = meQty
        })
      end
    end
  end
  
  table.sort(newItems, function(a, b) return sortableName(a.name) < sortableName(b.name) end)
  allItems = newItems
  items = {}
  for i, v in ipairs(allItems) do items[i] = v end
end

function updateMEQuantities()
  if not ME.available then return end
  for _, item in ipairs(allItems) do
    local qty = ME.getItemQuantity(item.internalName, item.damage or 0)
    item.meRaw = qty
    item.qty = qty
    if qty >= 1000 then item.me = string.format("%.1fk", qty / 1000)
    else item.me = tostring(qty) end
  end
  drawProductList()
  drawScrollbar()
  drawRightPanel()
end

local function filterItems()
  items = {}
  if searchQuery == "" then
    for i, v in ipairs(allItems) do items[i] = v end
  else
    local q = searchQuery:lower()
    for _, v in ipairs(allItems) do
      if v.name:lower():find(q, 1, true) then items[#items + 1] = v end
    end
  end
  selectedIndex = 1
  scrollOffset = 0
  hoveredIndex = 0
end

function updateSelectorDisplay(item)
  if not selector then return end
  if not item then
    pcall(selector.setSlot, 0, nil)
    pcall(selector.setSlot, 1, nil)
    return
  end
  local raw = item.internalName or item.name
  if not raw then return end
  local id = raw
  if not id:find(":") then id = "minecraft:" .. id end
  local dmg = item.damage or 0
  local stack = { id = id, dmg = dmg }
  pcall(selector.setSlot, 0, stack)
  pcall(selector.setSlot, 1, stack)
end

function performBuy()
  local item = items[selectedIndex]
  if not item then showTempMessage("❌ Товар не выбран", 2) return end
  local qty = tonumber(quantity) or 0
  if qty <= 0 then showTempMessage("❌ Введите количество", 2) return end
  if qty > item.qty then showTempMessage("❌ Недостаточно товара в МЭ", 2) return end
  
  local totalCoin = qty * (item.priceCoin or 0)
  local totalEma = qty * (item.priceEma or 0)
  if totalCoin > tonumber(account.coina) or totalEma > tonumber(account.ema) then
    showTempMessage("❌ Недостаточно средств", 2)
    return
  end
  
  local exported = ME.exportItem(item.internalName, item.damage or 0, qty, "down")
  if exported > 0 then
    account.coina = tostring(tonumber(account.coina) - totalCoin)
    account.ema = tostring(tonumber(account.ema) - totalEma)
    account.trans = tostring(tonumber(account.trans) + 1)
    showTempMessage(string.format("✅ Куплено %d шт.", exported), 2)
    updateMEQuantities()
    drawRightPanel()
  else
    showTempMessage("❌ Ошибка выдачи товара", 2)
  end
end

function performSell()
  local item = items[selectedIndex]
  if not item then showTempMessage("❌ Товар не выбран", 2) return end
  local qty = tonumber(quantity) or 0
  if qty <= 0 then showTempMessage("❌ Введите количество", 2) return end
  if not selector then showTempMessage("❌ Селектор не найден", 2) return end
  
  local imported = ME.importItem(item.internalName, item.damage or 0, qty, "up")
  if imported > 0 then
    local totalCoin = imported * (item.priceCoin or 0)
    local totalEma = imported * (item.priceEma or 0)
    account.coina = tostring(tonumber(account.coina) + totalCoin)
    account.ema = tostring(tonumber(account.ema) + totalEma)
    account.trans = tostring(tonumber(account.trans) + 1)
    showTempMessage(string.format("✅ Продано %d шт.", imported), 2)
    updateMEQuantities()
    drawRightPanel()
  else
    showTempMessage("❌ Ошибка приема товара", 2)
  end
end

local function drawBackground()
  fill(1, 1, WIDTH, HEIGHT, C.bg)
end

local function drawTopBar()
  fill(1, 1, WIDTH, 3, 0x0A0A0A)
  local title = "VIP-SHOP"
  text(math.floor((WIDTH - #title) / 2) + 1, 1, title, C.vipTitle, 0x0A0A0A)
  local meStatus = ME.available and "МЭ: ONLINE" or "МЭ: OFFLINE"
  local meColor = ME.available and C.green or C.red
  text(WIDTH - #meStatus - 2, 1, meStatus, meColor, 0x0A0A0A)
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
    local display = searchQuery
    if searchFocused then display = display .. "_" end
    text(searchX + 1, searchY, display, C.inputFg, C.inputBg)
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
  local modeText = shopMode == "buy" and "ПОКУПКИ" or "ПРОДАЖИ"
  sectionHeader(2, MAIN_Y + 1, LEFT_W - 3, modeText, C.mainLine, C.white)
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
  for y = LIST_Y, LIST_Y + LIST_H - 1 do gpu.set(SCROLL_X, y, " ") end
  local maxScroll = math.max(0, #items - LIST_H)
  if #items <= LIST_H then return end
  local thumbH = math.max(3, math.floor(LIST_H * 0.25))
  local thumbY = LIST_Y
  if maxScroll > 0 then thumbY = LIST_Y + math.floor((scrollOffset / maxScroll) * (LIST_H - thumbH)) end
  setBG(C.accent)
  for i = 0, thumbH - 1 do
    local yy = thumbY + i
    if yy >= LIST_Y and yy <= LIST_Y + LIST_H - 1 then gpu.set(SCROLL_X, yy, " ") end
  end
  setBG(C.bg)
end

local function drawItemRow(index, y)
  local item = items[index]
  if not item then return end
  local isSelected = (index == selectedIndex)
  local isHovered = (index == hoveredIndex)
  local bgColor = C.bg
  if isSelected then bgColor = C.selectedBg
  elseif isHovered then bgColor = C.bgHover end
  fill(LIST_X, y, LIST_W, 1, bgColor)
  
  local nameColor = isSelected and C.selectedName or (isHovered and C.white or C.white)
  local markerColor = item.star and C.star or C.darkGray
  local marker = item.star and "* " or "- "
  if isSelected then text(COL_NAME_X, y, "> ", C.selectedName, bgColor)
  else text(COL_NAME_X, y, marker, markerColor, bgColor) end
  
  local maxNameLen = COL_ME_X - COL_NAME_X - 2
  local displayName = truncate(item.name, maxNameLen - 2)
  text(COL_NAME_X + 2, y, displayName, nameColor, bgColor)
  
  local meColor = C.green
  if item.meRaw == 0 then meColor = C.red
  elseif item.meRaw < 10 then meColor = C.yellow end
  if isSelected then meColor = C.selectedName end
  text(COL_ME_X, y, item.me, meColor, bgColor)
  
  local coinaColor = C.yellow
  if isSelected then coinaColor = C.selectedName end
  text(COL_COINA_X, y, item.coina, coinaColor, bgColor)
  
  local emaColor = C.cyan
  if isSelected then emaColor = C.selectedName end
  text(COL_EMA_X, y, item.ema, emaColor, bgColor)
end

local function drawProductList()
  fill(LIST_X, LIST_Y, LIST_W, LIST_H, C.bg)
  if #items == 0 then
    local msg = "ПО ТВОЕМУ ЗАПРОСУ, НИЧЕГО НЕ НАЙДЕНО!"
    local mx = LIST_X + math.floor((LIST_W - #msg) / 2)
    local my = LIST_Y + math.floor(LIST_H / 2)
    text(mx, my, msg, C.notFound, C.bg)
    return
  end
  local startIdx = scrollOffset + 1
  local endIdx = math.min(#items, startIdx + LIST_H - 1)
  for i = startIdx, endIdx do drawItemRow(i, LIST_Y + (i - startIdx)) end
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
  text(RIGHT_INNER_X, y, string.format("В ME : %d шт.", item.meRaw), C.green, C.bg)
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
    local display = quantity
    if qtyFocused then display = display .. "_" end
    text(RIGHT_INNER_X + 2, fieldY, display, C.inputFg, C.inputBg)
  end
  
  local item = items[selectedIndex]
  local qty = tonumber(quantity) or 0
  local totalCoina = 0
  local totalEma = 0
  if item then
    totalCoina = qty * (tonumber(item.coina) or 0)
    totalEma = qty * (tonumber(item.ema) or 0)
  end
  text(RIGHT_INNER_X, TOTAL_Y, string.format("Итог: COINA: %.2f | EMA: %.2f", totalCoina, totalEma), C.yellow, C.bg)
  
  local btnW = 12
  local gap = 2
  local btnText = shopMode == "buy" and "[ Купить ]" or "[ Продать ]"
  local btnColor = shopMode == "buy" and C.buttonBuy or C.buttonSales
  setBG(btnColor)
  setFG(C.white)
  gpu.fill(RIGHT_INNER_X, BTN_Y, btnW, 1, " ")
  gpu.set(RIGHT_INNER_X + 1, BTN_Y, btnText)
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
  local buyX = 2
  local buyColor = shopMode == "buy" and C.buttonBuy or C.bg
  setBG(buyColor)
  setFG(C.white)
  gpu.fill(buyX, BOT_Y, btnW, 1, " ")
  gpu.set(buyX + 2, BOT_Y, "[ Покупки ]")
  local salesX = buyX + btnW + gap
  local salesColor = shopMode == "sell" and C.buttonSales or C.bg
  setBG(salesColor)
  setFG(C.white)
  gpu.fill(salesX, BOT_Y, btnW, 1, " ")
  gpu.set(salesX + 2, BOT_Y, "[ Продажи ]")
end

local function drawBottomBorder()
  setFG(C.mainLine)
  setBG(C.bg)
  gpu.set(1, HEIGHT, "+" .. string.rep("=", WIDTH - 2) .. "+")
end

function smoothScroll(steps)
  local total = #items
  if total <= LIST_H then return end
  local maxScroll = total - LIST_H
  local newScroll = scrollOffset + steps
  newScroll = math.max(0, math.min(newScroll, maxScroll))
  if newScroll == scrollOffset then return end
  local step = steps > 0 and 1 or -1
  local target = newScroll
  while scrollOffset ~= target do
    scrollOffset = scrollOffset + step
    drawProductList()
    drawScrollbar()
    os.sleep(0.03)
  end
end

local function selectItem(index)
  if #items == 0 then return end
  if index < 1 then index = 1 end
  if index > #items then index = #items end
  selectedIndex = index
  if selectedIndex - 1 < scrollOffset then scrollOffset = selectedIndex - 1
  elseif selectedIndex > scrollOffset + LIST_H then scrollOffset = selectedIndex - LIST_H end
  quantity = ""
  hoveredIndex = 0
  local item = items[selectedIndex]
  updateSelectorDisplay(item)
  drawProductList()
  drawScrollbar()
  drawRightPanel()
end

function setShopMode(mode)
  if mode == shopMode then return end
  shopMode = mode
  selectedIndex = 1
  scrollOffset = 0
  hoveredIndex = 0
  quantity = ""
  searchQuery = ""
  searchFocused = false
  qtyFocused = false
  loadItems()
  filterItems()
  redrawAll()
end

local function processMouseMove(x, y)
  if y >= LIST_Y and y <= LIST_Y + LIST_H - 1 and x >= LIST_X and x <= LIST_X + LIST_W then
    local row = y - LIST_Y
    local index = scrollOffset + row + 1
    if index >= 1 and index <= #items and index ~= hoveredIndex then
      hoveredIndex = index
      drawProductList()
    end
  else
    if hoveredIndex ~= 0 then
      hoveredIndex = 0
      drawProductList()
    end
  end
end

local function handleClick(x, y)
  searchFocused = false
  qtyFocused = false
  
  if x >= LIST_X and x <= LIST_X + LIST_W and y >= LIST_Y and y <= LIST_Y + LIST_H - 1 then
    local row = y - LIST_Y
    local index = scrollOffset + row + 1
    if index >= 1 and index <= #items then selectItem(index) end
    return
  end
  
  if x == SCROLL_X and y >= LIST_Y and y <= LIST_Y + LIST_H - 1 then
    if #items > LIST_H then
      local relY = y - LIST_Y
      local maxScroll = #items - LIST_H
      scrollOffset = math.floor((relY / LIST_H) * maxScroll)
      scrollOffset = math.max(0, math.min(scrollOffset, maxScroll))
      drawProductList()
      drawScrollbar()
    end
    return
  end
  
  local searchW = 40
  local clearX = 2 + searchW + 2
  if y == 3 then
    if x >= clearX and x < clearX + 11 then
      searchQuery = ""
      filterItems()
      redrawAll()
      return
    end
    if x >= 2 and x <= 2 + searchW then
      searchFocused = true
      redrawAll()
      return
    end
  end
  
  local fieldY = QTY_Y + 2
  if y == fieldY and x >= RIGHT_INNER_X and x <= RIGHT_INNER_X + RIGHT_INNER_W then
    qtyFocused = true
    drawQuantitySection()
    return
  end
  
  local btnW = 12
  local gap = 2
  local clearQtyX = RIGHT_INNER_X + btnW + gap
  
  if y == BTN_Y then
    if x >= RIGHT_INNER_X and x < RIGHT_INNER_X + btnW then
      if shopMode == "buy" then performBuy()
      else performSell() end
      return
    end
    if x >= clearQtyX and x < clearQtyX + btnW then
      quantity = ""
      drawQuantitySection()
      return
    end
  end
  
  if y == BOT_Y then
    local buyX = 2
    local salesX = buyX + 14 + 2
    if x >= buyX and x < buyX + 14 then setShopMode("buy") return end
    if x >= salesX and x < salesX + 14 then setShopMode("sell") return end
  end
end

local function handleKey(char, code)
  if searchFocused then
    if code == keyboard.keys.enter or code == keyboard.keys.tab then
      searchFocused = false
      redrawAll()
      return
    elseif code == keyboard.keys.back then
      searchQuery = searchQuery:sub(1, -2)
      filterItems()
      redrawAll()
      return
    elseif char and char >= 32 and char < 127 then
      if #searchQuery < 30 then
        searchQuery = searchQuery .. unicode.char(char)
        filterItems()
        redrawAll()
      end
      return
    end
  end
  
  if qtyFocused then
    if code == keyboard.keys.enter or code == keyboard.keys.tab then
      qtyFocused = false
      drawQuantitySection()
      return
    elseif code == keyboard.keys.back then
      quantity = quantity:sub(1, -2)
      drawQuantitySection()
      return
    elseif char and char >= 48 and char <= 57 then
      if #quantity < 8 then
        quantity = quantity .. string.char(char)
        drawQuantitySection()
      end
      return
    end
  end
  
  if code == keyboard.keys.up then
    selectItem(selectedIndex - 1)
    return
  elseif code == keyboard.keys.down then
    selectItem(selectedIndex + 1)
    return
  elseif code == keyboard.keys.pageup then
    smoothScroll(-LIST_H)
    return
  elseif code == keyboard.keys.pagedown then
    smoothScroll(LIST_H)
    return
  end
  
  if char and char >= 48 and char <= 57 then
    if #quantity < 8 then
      quantity = quantity .. string.char(char)
      drawQuantitySection()
    end
    return
  end
  
  if code == keyboard.keys.back then
    quantity = quantity:sub(1, -2)
    drawQuantitySection()
    return
  end
  
  if code == keyboard.keys.q or code == keyboard.keys.escape then return true end
end

local tempMessage = ""
local tempMessageTimer = nil

function showTempMessage(msg, duration)
  tempMessage = msg
  if tempMessageTimer then event.cancel(tempMessageTimer) end
  tempMessageTimer = event.timer(duration or 2, function()
    tempMessage = ""
    tempMessageTimer = nil
    drawBottomBar()
    return false
  end)
  drawBottomBar()
end

function redrawAll()
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

loadItems()
filterItems()
redrawAll()

local updateTimer = event.timer(5, function()
  if ME.available then updateMEQuantities() end
  return true
end)

while true do
  local ev = {event.pull(0.05)}
  local name = ev[1]
  
  if name == "touch" then
    handleClick(ev[3], ev[4])
  elseif name == "scroll" then
    local x, direction = ev[3], ev[5]
    if x >= LIST_X and x <= LIST_X + LIST_W + 2 then
      smoothScroll(-direction * 3)
    end
  elseif name == "mouse_move" then
    pendingMouseX = ev[3]
    pendingMouseY = ev[4]
    if mouseDebounceTimer then
      event.cancel(mouseDebounceTimer)
      mouseDebounceTimer = nil
    end
    mouseDebounceTimer = event.timer(0.05, function()
      mouseDebounceTimer = nil
      processMouseMove(pendingMouseX, pendingMouseY)
      return false
    end)
  elseif name == "key_down" then
    local _, _, char, code = table.unpack(ev)
    if handleKey(char, code) then break end
  end
end

if updateTimer then event.cancel(updateTimer) end
term.clear()
gpu.setForeground(0xFFFFFF)
gpu.setBackground(0x000000)
