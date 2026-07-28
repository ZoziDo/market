-- shop_admin.lua
-- Pixel-perfect replication of the OpenComputers shop admin GUI

local component = require("component")
local gpu = component.gpu
local event = require("event")
local unicode = require("unicode")

-- Colour palette (matching the screenshot as closely as possible)
local C = {
    background  = 0x111111,
    border      = 0x00E5FF,
    title       = 0x00FFFF,
    text        = 0xFFFFFF,
    gray        = 0x777777,
    darkGray    = 0x444444,
    green       = 0x00FF66,
    yellow      = 0xFFD800,
    red         = 0xFF3333,
    blue        = 0x0099FF,
    purple      = 0xAA00FF,
    cyan        = 0x00FFFF,
    selected    = 0x003366,
    logTime     = 0x888888,
    logText     = 0xCCCCCC,
}

-- Global screen dimensions (updated on resize)
local WIDTH, HEIGHT

-- Data: catalog items (name, amount, min, price, inn, indent)
local items = {
    {name="HiCropsPlating_Plating_1.name",   amount="0",    min=0, price=0, inn=0, indent=0},
    {name="Дракониевая пыль",                amount="365",  min=0, price=0, inn=0, indent=0},
    {name="Бумага",                          amount="2",    min=0, price=0, inn=0, indent=0},
    {name="Медовые соты",                    amount="121",  min=0, price=0, inn=0, indent=0},
    {name="Сборщик фруктов",                 amount="2",    min=0, price=0, inn=0, indent=0},
    {name="Ведро ледяное и ароматное",       amount="0",    min=0, price=0, inn=0, indent=0},
    {name="Светло-серая мини-зеркальная шерсть", amount="0", min=0, price=0, inn=0, indent=0},
    {name="Сырая баранина",                  amount="278",  min=0, price=0, inn=0, indent=0},
    {name="Голова страничная Края",          amount="4.7k", min=0, price=0, inn=0, indent=0},
    {name="МЗ жидкостная шина импорта",      amount="1",    min=0, price=0, inn=0, indent=0},
    {name="Реакторная камера",               amount="0",    min=0, price=0, inn=0, indent=0},
    {name="Авто-вариант",                    amount="1",    min=0, price=0, inn=0, indent=0},
    {name="Дракониевая блок",                amount="0",    min=0, price=0, inn=0, indent=0},
    {name="Яблоко",                          amount="5.5k", min=0, price=0, inn=0, indent=0},
    {name="item.item_portable_cell_advanced.name", amount="1", min=0, price=0, inn=0, indent=0},
    {name="Ведро ремонтирующего",            amount="158",  min=0, price=0, inn=0, indent=0},
    {name="Чан",                             amount="0",    min=0, price=0, inn=0, indent=0},
    {name="Охлаждающее ядро",                amount="0",    min=0, price=0, inn=0, indent=0},
    {name="S8Tёмное покрытие",               amount="0",    min=0, price=0, inn=0, indent=1},
    {name="S8Tёмный порошок",                amount="0",    min=0, price=0, inn=0, indent=0},
    {name="МЗ беспроводная",                 amount="0",    min=0, price=0, inn=0, indent=1},
    {name="Кристалл истинного кварца",       amount="20.3k",min=0, price=0, inn=0, indent=0},
    {name="Измельчённый мини-зеркаль",       amount="1.4k", min=0, price=0, inn=0, indent=1},
    {name="Анализатор",                      amount="0",    min=0, price=0, inn=0, indent=0},
    {name="Одуванчик",                       amount="1.7k", min=0, price=0, inn=0, indent=0},
    {name="Стеклянная панель",               amount="269",  min=0, price=0, inn=0, indent=0},
    {name="Комбайн",                         amount="1",    min=0, price=0, inn=0, indent=0},
    {name="Усиленная жидкостная труба",      amount="512",  min=0, price=0, inn=0, indent=0},
    {name="Расширение: Пространственно-временной унификатор флакса", amount="0", min=0, price=0, inn=0, indent=1},
    {name="Руда урана",                      amount="5.9k", min=0, price=0, inn=0, indent=0},
    {name="Электрическая мотыга",            amount="1",    min=0, price=0, inn=0, indent=0},
    {name="Пергамент",                       amount="0",    min=0, price=0, inn=0, indent=0},
    {name="Камень Воскрешения",              amount="0",    min=0, price=0, inn=0, indent=0},
    {name="Производитель пыль",              amount="1",    min=0, price=0, inn=0, indent=1},
    {name="Контур печатной платы",           amount="0",    min=0, price=0, inn=0, indent=1},
}

-- Log entries (static for demonstration)
local logs = {
    "[12:41] Каталог загружен",
    "[12:42] Обновление цен",
    "[12:43] Готов к работе",
}

-- Selection state
local selectedIndex = 1          -- 1‑based
local scrollOffset = 1           -- first visible item index

-- ----------------------------------------------------------------------------
-- Helper functions
-- ----------------------------------------------------------------------------
local function setColor(fg, bg)
    if fg then gpu.setForeground(fg) end
    if bg then gpu.setBackground(bg) end
end

local function fill(x, y, w, h, char, fg, bg)
    setColor(fg, bg)
    for row = y, y + h - 1 do
        gpu.set(x, row, string.rep(char, w))
    end
end

local function drawBorder(x, y, w, h, fg, bg, title, titleFg)
    if not fg then fg = C.border end
    if not bg then bg = C.background end
    setColor(fg, bg)

    gpu.set(x, y, "+")
    gpu.set(x + w - 1, y, "+")
    gpu.set(x + 1, y, string.rep("-", w - 2))

    gpu.set(x, y + h - 1, "+")
    gpu.set(x + w - 1, y + h - 1, "+")
    gpu.set(x + 1, y + h - 1, string.rep("-", w - 2))

    for row = y + 1, y + h - 2 do
        gpu.set(x, row, "|")
        gpu.set(x + w - 1, row, "|")
    end

    if title then
        local titleLen = unicode.len(title)
        local startX = x + math.floor((w - titleLen) / 2)
        if startX < x + 2 then startX = x + 2 end
        setColor(titleFg or C.title, bg)
        gpu.set(startX, y, title)
        setColor(bg, bg)
        for i = x + 1, x + w - 2 do
            if i < startX or i >= startX + titleLen then
                gpu.set(i, y, " ")
            end
        end
        setColor(fg, bg)
    end
end

local function formatNumber(num)
    if type(num) == "string" then return num end
    if num >= 1000000 then return string.format("%.1fM", num / 1000000) end
    if num >= 1000 then return string.format("%.1fk", num / 1000) end
    return tostring(num)
end

-- ----------------------------------------------------------------------------
-- Drawing functions (all coordinates computed from WIDTH/HEIGHT)
-- ----------------------------------------------------------------------------
local function drawHeader()
    setColor(C.text, C.background)
    gpu.set(1, 1, "SHOP-ADMIN v3.0")
    local centerText = "McSkill HiTech"
    local cx = math.floor((WIDTH - unicode.len(centerText)) / 2) + 1
    gpu.set(cx, 1, centerText)
    local rightText = "UP:01:19"
    gpu.set(WIDTH - unicode.len(rightText) + 1, 1, rightText)

    setColor(C.border, C.background)
    gpu.set(1, 2, string.rep("=", WIDTH))
end

local function drawCatalog()
    local leftX = 1
    local leftW = math.floor(WIDTH * 0.65)
    local topY = 3
    local bottomY = HEIGHT - 3          -- leave space for buttons and blank row
    local height = bottomY - topY + 1

    drawBorder(leftX, topY, leftW, height, C.border, C.background, "КАТАЛОГ ТОВАРОВ", C.title)

    local innerX = leftX + 1
    local innerY = topY + 1
    local innerW = leftW - 2
    local innerH = height - 2

    -- "Поиск:" line
    setColor(C.text, C.background)
    gpu.set(innerX, innerY, "Поиск:")

    -- Column headers
    local headerY = innerY + 1
    setColor(C.cyan, C.background)
    local nameW = math.floor(innerW * 0.40)
    local amountW = 8
    local minW = 5
    local priceW = 10
    local innW = 6
    local totalFixed = amountW + minW + priceW + innW + 4
    if nameW + totalFixed > innerW then
        nameW = innerW - totalFixed
        if nameW < 10 then nameW = 10 end
    end
    local pos = innerX
    gpu.set(pos, headerY, "ТОВАР")
    pos = pos + nameW + 1
    gpu.set(pos, headerY, "В МЕ")
    pos = pos + amountW + 1
    gpu.set(pos, headerY, "МИН")
    pos = pos + minW + 1
    gpu.set(pos, headerY, "ЦЕНА ЕМ")
    pos = pos + priceW + 1
    gpu.set(pos, headerY, "ИНН")

    -- Separator
    setColor(C.gray, C.background)
    local sepY = headerY + 1
    gpu.set(innerX, sepY, string.rep("-", innerW))

    -- Items
    local itemStartY = sepY + 1
    local maxItems = innerH - 4   -- rows for items
    if maxItems < 1 then return end

    local totalItems = #items
    local visibleItems = maxItems
    local maxScroll = math.max(1, totalItems - visibleItems + 1)
    if scrollOffset > maxScroll then scrollOffset = maxScroll end
    if scrollOffset < 1 then scrollOffset = 1 end

    -- Scrollbar
    local scrollBarX = leftX + leftW - 2
    local scrollBarTop = itemStartY
    local scrollBarHeight = maxItems
    if totalItems > visibleItems then
        local thumbSize = math.max(2, math.floor(visibleItems / totalItems * scrollBarHeight))
        local thumbPos = math.floor((scrollOffset - 1) / (totalItems - visibleItems + 1) * (scrollBarHeight - thumbSize)) + scrollBarTop
        setColor(C.border, C.background)
        for row = scrollBarTop, scrollBarTop + scrollBarHeight - 1 do
            gpu.set(scrollBarX, row, " ")
        end
        setColor(C.cyan, C.selected)
        for row = thumbPos, thumbPos + thumbSize - 1 do
            gpu.set(scrollBarX, row, "█")
        end
    else
        setColor(C.background, C.background)
        for row = scrollBarTop, scrollBarTop + scrollBarHeight - 1 do
            gpu.set(scrollBarX, row, " ")
        end
    end

    -- Draw items
    for i = 1, visibleItems do
        local itemIndex = scrollOffset + i - 1
        if itemIndex > totalItems then break end
        local item = items[itemIndex]
        local row = itemStartY + i - 1
        if row > innerY + innerH - 1 then break end

        setColor(C.background, C.background)
        gpu.set(innerX, row, string.rep(" ", innerW))

        local bgColor = C.background
        local fgColor = C.text
        if itemIndex == selectedIndex then
            bgColor = C.selected
            fgColor = C.title
        end

        local indent = item.indent or 0
        local nameStr = item.name
        if indent > 0 then
            nameStr = "  " .. nameStr
        end

        local maxNameLen = nameW - 2
        if unicode.len(nameStr) > maxNameLen then
            nameStr = unicode.sub(nameStr, 1, maxNameLen - 1) .. "…"
        end

        local amountStr = item.amount
        if type(item.amount) == "number" then
            amountStr = formatNumber(item.amount)
        end
        local minStr = tostring(item.min)
        local priceStr = tostring(item.price) .. " EM"
        local innStr = tostring(item.inn)

        setColor(fgColor, bgColor)
        pos = innerX
        gpu.set(pos, row, nameStr)
        pos = pos + nameW + 1
        gpu.set(pos, row, string.format("%" .. amountW .. "s", amountStr))
        pos = pos + amountW + 1
        gpu.set(pos, row, string.format("%" .. minW .. "s", minStr))
        pos = pos + minW + 1
        gpu.set(pos, row, string.format("%" .. priceW .. "s", priceStr))
        pos = pos + priceW + 1
        gpu.set(pos, row, string.format("%" .. innW .. "s", innStr))
    end

    -- Clear remaining lines
    for row = itemStartY + visibleItems, innerY + innerH - 1 do
        setColor(C.background, C.background)
        gpu.set(innerX, row, string.rep(" ", innerW))
    end
end

local function drawInfoPanel()
    local leftX = math.floor(WIDTH * 0.65) + 2
    local topY = 3
    local bottomY = 3 + math.floor((HEIGHT - 3 - 2) * 0.40)  -- 40% of main area
    local rightX = WIDTH
    local w = rightX - leftX + 1
    local h = bottomY - topY + 1

    drawBorder(leftX, topY, w, h, C.border, C.background, "INFO | ADMIN | PC-2", C.title)

    local innerX = leftX + 1
    local innerY = topY + 1
    local innerW = w - 2
    local innerH = h - 2

    setColor(C.background, C.background)
    for row = innerY, innerY + innerH - 1 do
        gpu.set(innerX, row, string.rep(" ", innerW))
    end

    local item = items[selectedIndex] or items[1]
    local lines = {
        "",
        " " .. item.name,
        " Цена: " .. tostring(item.price) .. " EM",
        " В ME: " .. tostring(item.amount),
        " Мин: " .. tostring(item.min),
        " Крафт: нет",
    }

    setColor(C.text, C.background)
    for i, line in ipairs(lines) do
        local row = innerY + i - 1
        if row <= innerY + innerH - 1 then
            gpu.set(innerX, row, line)
        end
    end
end

local function drawLogPanel()
    local leftX = math.floor(WIDTH * 0.65) + 2
    local topY = 3 + math.floor((HEIGHT - 3 - 2) * 0.40) + 1
    local rightX = WIDTH
    local bottomY = HEIGHT - 3
    local w = rightX - leftX + 1
    local h = bottomY - topY + 1

    drawBorder(leftX, topY, w, h, C.border, C.background, "LOG", C.title)

    local innerX = leftX + 1
    local innerY = topY + 1
    local innerW = w - 2
    local innerH = h - 2

    setColor(C.background, C.background)
    for row = innerY, innerY + innerH - 1 do
        gpu.set(innerX, row, string.rep(" ", innerW))
    end

    local maxLogLines = innerH
    local startIdx = math.max(1, #logs - maxLogLines + 1)
    setColor(C.logText, C.background)
    for i = startIdx, #logs do
        local row = innerY + (i - startIdx)
        if row <= innerY + innerH - 1 then
            local line = logs[i]
            if unicode.len(line) > innerW then
                line = unicode.sub(line, 1, innerW - 1) .. "…"
            end
            gpu.set(innerX, row, line)
        end
    end
end

local function drawButtons()
    -- Clear blank row above buttons
    setColor(C.background, C.background)
    gpu.set(1, HEIGHT - 2, string.rep(" ", WIDTH))

    local buttons = {
        {label=" ОБНОВИТЬ ", fg=C.text, bg=C.blue},
        {label=" ИЗМЕНИТЬ ", fg=C.text, bg=C.green},
        {label=" УДАЛИТЬ ",  fg=C.text, bg=C.red},
        {label=" ОБМЕННИК ", fg=C.text, bg=C.purple},
    }

    local totalWidth = 0
    for _, b in ipairs(buttons) do
        totalWidth = totalWidth + unicode.len(b.label) + 1
    end
    totalWidth = totalWidth - 1

    local startX = math.floor((WIDTH - totalWidth) / 2) + 1
    local currentX = startX
    local row = HEIGHT - 1

    for _, b in ipairs(buttons) do
        local label = b.label
        local len = unicode.len(label)
        setColor(b.fg, b.bg)
        gpu.set(currentX, row, label)
        if _ < #buttons then
            setColor(C.background, C.background)
            gpu.set(currentX + len, row, " ")
        end
        currentX = currentX + len + 1
    end
end

local function draw()
    gpu.setBackground(C.background)
    gpu.setForeground(C.text)
    gpu.fill(1, 1, WIDTH, HEIGHT, " ")
    drawHeader()
    drawCatalog()
    drawInfoPanel()
    drawLogPanel()
    drawButtons()
end

-- ----------------------------------------------------------------------------
-- Main loop
-- ----------------------------------------------------------------------------
local function main()
    -- Set initial resolution
    local maxW, maxH = gpu.maxResolution()
    gpu.setResolution(maxW, maxH)
    WIDTH, HEIGHT = maxW, maxH

    draw()

    while true do
        local ev, _, _, _, key = event.pull()
        if ev == "key_down" then
            local handled = true
            if key == 200 then -- Up
                if selectedIndex > 1 then
                    selectedIndex = selectedIndex - 1
                    if selectedIndex < scrollOffset then
                        scrollOffset = selectedIndex
                    end
                end
            elseif key == 208 then -- Down
                if selectedIndex < #items then
                    selectedIndex = selectedIndex + 1
                    local visible = HEIGHT - 3 - 4   -- approximate visible items
                    if selectedIndex > scrollOffset + visible - 1 then
                        scrollOffset = selectedIndex - visible + 1
                    end
                end
            elseif key == 201 then -- Page Up
                local visible = HEIGHT - 3 - 4
                selectedIndex = math.max(1, selectedIndex - visible)
                scrollOffset = math.max(1, scrollOffset - visible)
            elseif key == 209 then -- Page Down
                local visible = HEIGHT - 3 - 4
                selectedIndex = math.min(#items, selectedIndex + visible)
                scrollOffset = math.min(#items - visible + 1, scrollOffset + visible)
            elseif key == 199 then -- Home
                selectedIndex = 1
                scrollOffset = 1
            elseif key == 207 then -- End
                selectedIndex = #items
                local visible = HEIGHT - 3 - 4
                scrollOffset = math.max(1, #items - visible + 1)
            elseif key == 28 then -- Enter (just redraw)
                -- optional action
            elseif key == 1 then -- Escape
                break
            else
                handled = false
            end
            if handled then
                draw()
            end
        elseif ev == "resize" then
            -- Update dimensions
            local newW, newH = gpu.getResolution()
            WIDTH, HEIGHT = newW, newH
            draw()
        end
    end
end

-- Start the application
main()

-- End of file
