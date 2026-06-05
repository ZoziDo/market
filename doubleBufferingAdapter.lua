local component = require("component")
local realGPU = component.gpu

local width, height = 80, 25
local backColor = {}
local foreColor = {}
local chars = {}

local currentBG = 0x000000
local currentFG = 0xFFFFFF

local function idx(x, y) return (y-1)*width + x end

local function clearBuffers()
    for i = 1, width*height do
        backColor[i] = 0x000000
        foreColor[i] = 0xFFFFFF
        chars[i] = " "
    end
end

function adapter.setResolution(w, h)
    width, height = w, h
    realGPU.setResolution(w, h)
    clearBuffers()
end

function adapter.getResolution() return width, height end

function adapter.setBackground(c) currentBG = c end
function adapter.getBackground() return currentBG end
function adapter.setForeground(c) currentFG = c end
function adapter.getForeground() return currentFG end

function adapter.set(x, y, str)
    if not str or str == "" then return end
    for i = 1, #str do
        local xi = x + i - 1
        if xi >= 1 and xi <= width and y >= 1 and y <= height then
            local id = idx(xi, y)
            backColor[id] = currentBG
            foreColor[id] = currentFG
            chars[id] = str:sub(i, i)
        end
    end
end

function adapter.fill(x, y, w, h, ch)
    for j = y, y+h-1 do
        for i = x, x+w-1 do
            if i >= 1 and i <= width and j >= 1 and j <= height then
                local id = idx(i, j)
                backColor[id] = currentBG
                foreColor[id] = currentFG
                chars[id] = ch
            end
        end
    end
end

function adapter.get(x, y)
    if x >= 1 and y >= 1 and x <= width and y <= height then
        local id = idx(x, y)
        return backColor[id], foreColor[id], chars[id]
    end
    return 0, 0, " "
end

function adapter.copy(x, y, w, h, dx, dy)
    local temp = {}
    for j = y, y+h-1 do
        for i = x, x+w-1 do
            local id = idx(i, j)
            table.insert(temp, {backColor[id], foreColor[id], chars[id]})
        end
    end
    local t = 1
    for j = y+dy, y+dy+h-1 do
        for i = x+dx, x+dx+w-1 do
            if i >= 1 and i <= width and j >= 1 and j <= height then
                local id = idx(i, j)
                local data = temp[t]
                backColor[id] = data[1]
                foreColor[id] = data[2]
                chars[id] = data[3]
            end
            t = t + 1
        end
    end
end

function adapter.present()
    local lastBG = nil
    local lastFG = nil
    for y = 1, height do
        local lineStart = true
        local lineStr = ""
        for x = 1, width do
            local id = idx(x, y)
            local bg = backColor[id]
            local fg = foreColor[id]
            local ch = chars[id]
            if bg ~= lastBG then
                if lineStr ~= "" then
                    realGPU.setBackground(lastBG)
                    realGPU.setForeground(lastFG)
                    realGPU.set(lineStart, y, lineStr)
                end
                lineStr = ""
                lineStart = x
                lastBG = bg
                lastFG = fg
                realGPU.setBackground(bg)
            end
            if fg ~= lastFG then
                if lineStr ~= "" then
                    realGPU.setBackground(lastBG)
                    realGPU.setForeground(lastFG)
                    realGPU.set(lineStart, y, lineStr)
                end
                lineStr = ""
                lineStart = x
                lastFG = fg
                realGPU.setForeground(fg)
            end
            lineStr = lineStr .. ch
        end
        if lineStr ~= "" then
            realGPU.setBackground(lastBG)
            realGPU.setForeground(lastFG)
            realGPU.set(lineStart, y, lineStr)
        end
    end
end

function adapter.getDepth() return 8 end
function adapter.maxDepth() return 8 end
function adapter.maxResolution() return 160, 50 end

adapter.setResolution(80, 25)

return adapter
