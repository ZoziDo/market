local component = require("component")
local sides = require("sides")

if not component.isAvailable("transposer") then
    error("Transposer не найден")
end

local transposer = component.transposer

-- По результатам твоего теста:
local BUFFER_SIDE = sides.front -- 3: сундук от ME IO Port
local STORAGE_SIDE = sides.back -- 2: склад руды и слитков

local IRON_ORE = "minecraft:iron_ore"
local IRON_INGOT = "minecraft:iron_ingot"

local IRON_ORE_DAMAGE = 0
local IRON_INGOT_DAMAGE = 0

-- Курс обмена:
local TAKE_AMOUNT = 3
local GIVE_AMOUNT = 7

local function getItemName(stack)
    if not stack then
        return nil
    end

    return stack.name or stack.id
end

local function getItemDamage(stack)
    if not stack then
        return 0
    end

    return tonumber(stack.damage or stack.dmg) or 0
end

local function getItemAmount(stack)
    if not stack then
        return 0
    end

    return math.floor(tonumber(stack.size or stack.qty) or 0)
end

local function isRequiredItem(stack, itemName, damage)
    if not stack then
        return false
    end

    return getItemName(stack) == itemName
        and getItemDamage(stack) == (tonumber(damage) or 0)
end

local function getInventorySize(side)
    local ok, size = pcall(
        transposer.getInventorySize,
        side
    )

    if not ok or not tonumber(size) then
        return nil
    end

    return math.floor(tonumber(size))
end

local function getTotalAmount(side, itemName, damage)
    local inventorySize = getInventorySize(side)

    if not inventorySize then
        return 0
    end

    local total = 0

    for slot = 1, inventorySize do
        local ok, stack = pcall(
            transposer.getStackInSlot,
            side,
            slot
        )

        if ok and isRequiredItem(stack, itemName, damage) then
            total = total + getItemAmount(stack)
        end
    end

    return total
end

-- Перемещает нужное количество предмета, даже если оно
-- находится сразу в нескольких слотах.
local function moveItem(fromSide, toSide, itemName, damage, amount)
    amount = math.max(0, math.floor(tonumber(amount) or 0))

    if amount == 0 then
        return 0
    end

    local inventorySize = getInventorySize(fromSide)

    if not inventorySize then
        return 0
    end

    local totalMoved = 0

    for slot = 1, inventorySize do
        if totalMoved >= amount then
            break
        end

        local okStack, stack = pcall(
            transposer.getStackInSlot,
            fromSide,
            slot
        )

        if okStack and isRequiredItem(stack, itemName, damage) then
            local remaining = amount - totalMoved
            local stackAmount = getItemAmount(stack)
            local requestAmount = math.min(remaining, stackAmount)

            local okMove, moved = pcall(
                transposer.transferItem,
                fromSide,
                toSide,
                requestAmount,
                slot
            )

            if okMove then
                totalMoved = totalMoved + math.floor(
                    tonumber(moved) or 0
                )
            end
        end
    end

    return totalMoved
end

print("========================================")
print(" АВТОМАТИЧЕСКИЙ ОБМЕН ЖЕЛЕЗНОЙ РУДЫ")
print("========================================")
print("")

local bufferName = transposer.getInventoryName(BUFFER_SIDE)
local storageName = transposer.getInventoryName(STORAGE_SIDE)

if not bufferName then
    error("Буферный сундук FRONT не найден")
end

if not storageName then
    error("Складской сундук BACK не найден")
end

print("Буфер: " .. tostring(bufferName))
print("Склад: " .. tostring(storageName))
print("")

local availableOre = getTotalAmount(
    BUFFER_SIDE,
    IRON_ORE,
    IRON_ORE_DAMAGE
)

local availableIngots = getTotalAmount(
    STORAGE_SIDE,
    IRON_INGOT,
    IRON_INGOT_DAMAGE
)

print("В буфере железной руды: " .. tostring(availableOre))
print("На складе железных слитков: " .. tostring(availableIngots))
print("")

local exchangeGroups = math.floor(availableOre / TAKE_AMOUNT)
local oreToTake = exchangeGroups * TAKE_AMOUNT
local ingotsToGive = exchangeGroups * GIVE_AMOUNT
local oreRemainder = availableOre - oreToTake

if exchangeGroups <= 0 then
    print("Недостаточно железной руды.")
    print("Для обмена требуется минимум: " .. TAKE_AMOUNT)
    return
end

print("Расчёт обмена:")
print("Полных обменов: " .. tostring(exchangeGroups))
print("Будет принято руды: " .. tostring(oreToTake))
print("Будет выдано слитков: " .. tostring(ingotsToGive))
print("Останется руды: " .. tostring(oreRemainder))
print("")

if availableIngots < ingotsToGive then
    print("ОБМЕН ОТМЕНЁН!")
    print("На складе недостаточно железных слитков.")
    print("Требуется: " .. tostring(ingotsToGive))
    print("Имеется: " .. tostring(availableIngots))
    return
end

print("Забираю железную руду...")

local movedOre = moveItem(
    BUFFER_SIDE,
    STORAGE_SIDE,
    IRON_ORE,
    IRON_ORE_DAMAGE,
    oreToTake
)

if movedOre ~= oreToTake then
    print("Не удалось забрать всю руду.")
    print("Забрано: " .. tostring(movedOre))
    print("Возвращаю перемещённую руду обратно...")

    local returnedOre = moveItem(
        STORAGE_SIDE,
        BUFFER_SIDE,
        IRON_ORE,
        IRON_ORE_DAMAGE,
        movedOre
    )

    print("Возвращено руды: " .. tostring(returnedOre))
    error("Обмен отменён из-за ошибки перемещения руды")
end

print("Руда успешно принята.")
print("Выдаю железные слитки...")

local movedIngots = moveItem(
    STORAGE_SIDE,
    BUFFER_SIDE,
    IRON_INGOT,
    IRON_INGOT_DAMAGE,
    ingotsToGive
)

if movedIngots ~= ingotsToGive then
    print("Не удалось выдать все слитки.")
    print("Выдано: " .. tostring(movedIngots))
    print("Требовалось: " .. tostring(ingotsToGive))
    print("Запускаю возврат операции...")

    if movedIngots > 0 then
        local returnedIngots = moveItem(
            BUFFER_SIDE,
            STORAGE_SIDE,
            IRON_INGOT,
            IRON_INGOT_DAMAGE,
            movedIngots
        )

        print("Возвращено слитков на склад: "
            .. tostring(returnedIngots))
    end

    local returnedOre = moveItem(
        STORAGE_SIDE,
        BUFFER_SIDE,
        IRON_ORE,
        IRON_ORE_DAMAGE,
        movedOre
    )

    print("Возвращено руды игроку: "
        .. tostring(returnedOre))

    error("Обмен отменён из-за ошибки выдачи слитков")
end

print("")
print("========================================")
print(" ОБМЕН УСПЕШНО ЗАВЕРШЁН")
print("========================================")
print("Принято железной руды: " .. tostring(movedOre))
print("Выдано железных слитков: " .. tostring(movedIngots))
print("Остаток руды в буфере: " .. tostring(oreRemainder))
