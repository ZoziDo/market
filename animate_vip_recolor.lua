-- VIP-SHOP smooth color-flow animation for OpenComputers / OpenOS
-- IMPORTANT:
-- This does NOT swap whole .pic frames.
-- It loads ONE .pic once, draws it once, and then only recolors the same cells in place.
-- So visually the image stays on screen and only the colors flow.
--
-- Put in /home:
--   vip_pickaxe.pic
--   animate_vip_recolor.lua
--
-- Run:
--   animate_vip_recolor.lua
-- or:
--   lua /home/animate_vip_recolor.lua /home/vip_pickaxe.pic

local component = require("component")
local gpu = component.gpu
local os = require("os")

local args = {...}
local path = args[1] or "/home/vip_pickaxe.pic"

local palette = {
  0x000000,0x000040,0x000080,0x0000BF,0x0000FF,0x002400,0x002440,0x002480,0x0024BF,0x0024FF,
  0x004900,0x004940,0x004980,0x0049BF,0x0049FF,0x006D00,0x006D40,0x006D80,0x006DBF,0x006DFF,
  0x009200,0x009240,0x009280,0x0092BF,0x0092FF,0x00B600,0x00B640,0x00B680,0x00B6BF,0x00B6FF,
  0x00DB00,0x00DB40,0x00DB80,0x00DBBF,0x00DBFF,0x00FF00,0x00FF40,0x00FF80,0x00FFBF,0x00FFFF,
  0x0F0F0F,0x1E1E1E,0x2D2D2D,0x330000,0x330040,0x330080,0x3300BF,0x3300FF,0x332400,0x332440,
  0x332480,0x3324BF,0x3324FF,0x334900,0x334940,0x334980,0x3349BF,0x3349FF,0x336D00,0x336D40,
  0x336D80,0x336DBF,0x336DFF,0x339200,0x339240,0x339280,0x3392BF,0x3392FF,0x33B600,0x33B640,
  0x33B680,0x33B6BF,0x33B6FF,0x33DB00,0x33DB40,0x33DB80,0x33DBBF,0x33DBFF,0x33FF00,0x33FF40,
  0x33FF80,0x33FFBF,0x33FFFF,0x3C3C3C,0x4B4B4B,0x5A5A5A,0x660000,0x660040,0x660080,0x6600BF,
  0x6600FF,0x662400,0x662440,0x662480,0x6624BF,0x6624FF,0x664900,0x664940,0x664980,0x6649BF,
  0x6649FF,0x666D00,0x666D40,0x666D80,0x666DBF,0x666DFF,0x669200,0x669240,0x669280,0x6692BF,
  0x6692FF,0x66B600,0x66B640,0x66B680,0x66B6BF,0x66B6FF,0x66DB00,0x66DB40,0x66DB80,0x66DBBF,
  0x66DBFF,0x66FF00,0x66FF40,0x66FF80,0x66FFBF,0x66FFFF,0x696969,0x787878,0x878787,0x969696,
  0x990000,0x990040,0x990080,0x9900BF,0x9900FF,0x992400,0x992440,0x992480,0x9924BF,0x9924FF,
  0x994900,0x994940,0x994980,0x9949BF,0x9949FF,0x996D00,0x996D40,0x996D80,0x996DBF,0x996DFF,
  0x999200,0x999240,0x999280,0x9992BF,0x9992FF,0x99B600,0x99B640,0x99B680,0x99B6BF,0x99B6FF,
  0x99DB00,0x99DB40,0x99DB80,0x99DBBF,0x99DBFF,0x99FF00,0x99FF40,0x99FF80,0x99FFBF,0x99FFFF,
  0xA5A5A5,0xB4B4B4,0xC3C3C3,0xCC0000,0xCC0040,0xCC0080,0xCC00BF,0xCC00FF,0xCC2400,0xCC2440,
  0xCC2480,0xCC24BF,0xCC24FF,0xCC4900,0xCC4940,0xCC4980,0xCC49BF,0xCC49FF,0xCC6D00,0xCC6D40,
  0xCC6D80,0xCC6DBF,0xCC6DFF,0xCC9200,0xCC9240,0xCC9280,0xCC92BF,0xCC92FF,0xCCB600,0xCCB640,
  0xCCB680,0xCCB6BF,0xCCB6FF,0xCCDB00,0xCCDB40,0xCCDB80,0xCCDBBF,0xCCDBFF,0xCCFF00,0xCCFF40,
  0xCCFF80,0xCCFFBF,0xCCFFFF,0xD2D2D2,0xE1E1E1,0xF0F0F0,0xFF0000,0xFF0040,0xFF0080,0xFF00BF,
  0xFF00FF,0xFF2400,0xFF2440,0xFF2480,0xFF24BF,0xFF24FF,0xFF4900,0xFF4940,0xFF4980,0xFF49BF,
  0xFF49FF,0xFF6D00,0xFF6D40,0xFF6D80,0xFF6DBF,0xFF6DFF,0xFF9200,0xFF9240,0xFF9280,0xFF92BF,
  0xFF92FF,0xFFB600,0xFFB640,0xFFB680,0xFFB6BF,0xFFB6FF,0xFFDB00,0xFFDB40,0xFFDB80,0xFFDBBF,
  0xFFDBFF,0xFFFF00,0xFFFF40,0xFFFF80,0xFFFFBF,0xFFFFFF
}

local function rgbSplit(color)
  return math.floor(color / 0x10000) % 0x100, math.floor(color / 0x100) % 0x100, color % 0x100
end

local function rgbJoin(r, g, b)
  return math.floor(r) * 0x10000 + math.floor(g) * 0x100 + math.floor(b)
end

local function rgbToHsv(r, g, b)
  r = r / 255
  g = g / 255
  b = b / 255

  local maxv = math.max(r, g, b)
  local minv = math.min(r, g, b)
  local d = maxv - minv

  local h = 0
  local s = maxv == 0 and 0 or d / maxv
  local v = maxv

  if d ~= 0 then
    if maxv == r then
      h = ((g - b) / d) % 6
    elseif maxv == g then
      h = ((b - r) / d) + 2
    else
      h = ((r - g) / d) + 4
    end
    h = h / 6
  end

  return h, s, v
end

local function hsvToRgb(h, s, v)
  local i = math.floor(h * 6)
  local f = h * 6 - i
  local p = v * (1 - s)
  local q = v * (1 - f * s)
  local t = v * (1 - (1 - f) * s)
  i = i % 6

  local r, g, b
  if i == 0 then r, g, b = v, t, p
  elseif i == 1 then r, g, b = q, v, p
  elseif i == 2 then r, g, b = p, v, t
  elseif i == 3 then r, g, b = p, q, v
  elseif i == 4 then r, g, b = t, p, v
  else r, g, b = v, p, q end

  return math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)
end

local function readByte(file)
  local s = file:read(1)
  if not s then error("Unexpected end of file") end
  return string.byte(s)
end

local function readU16BE(file)
  return readByte(file) * 256 + readByte(file)
end

local function readUTF8Char(file)
  local first = file:read(1)
  if not first then error("Unexpected EOF while reading UTF-8 char") end
  local b = string.byte(first)
  local count
  if b < 0x80 then count = 1
  elseif b < 0xE0 then count = 2
  elseif b < 0xF0 then count = 3
  elseif b < 0xF8 then count = 4
  else error("Unsupported UTF-8 byte: " .. tostring(b)) end

  if count == 1 then return first end

  local rest = file:read(count - 1)
  if not rest or #rest ~= count - 1 then error("Unexpected EOF in UTF-8 char") end
  return first .. rest
end

local function makeGrid(width, height)
  local grid = {}
  for y = 1, height do
    grid[y] = {}
    for x = 1, width do
      grid[y][x] = {bg = 0x000000, fg = 0xFFFFFF, ch = " "}
    end
  end
  return grid
end

local function loadOCIF6(path)
  local file, reason = io.open(path, "rb")
  if not file then error("Cannot open " .. path .. ": " .. tostring(reason)) end

  local sig = file:read(4)
  if sig ~= "OCIF" then
    file:close()
    error("Bad OCIF signature in " .. path)
  end

  local method = readByte(file)
  if method ~= 6 then
    file:close()
    error("This script supports only OCIF method 6. Got " .. tostring(method))
  end

  local width = readByte(file)
  local height = readByte(file)
  local grid = makeGrid(width, height)

  local alphaCount = readByte(file)
  for ai = 1, alphaCount do
    local alpha = readByte(file) / 255
    local symbolCount = readU16BE(file)

    for si = 1, symbolCount do
      local symbol = readUTF8Char(file)
      local bgCount = readByte(file)

      for bi = 1, bgCount do
        local bgIndex = readByte(file)
        local fgCount = readByte(file)

        for fi = 1, fgCount do
          local fgIndex = readByte(file)
          local yCount = readByte(file)

          local bg = palette[bgIndex + 1]
          local fg = palette[fgIndex + 1]

          for yi = 1, yCount do
            local py = readByte(file)
            local xCount = readByte(file)

            for xi = 1, xCount do
              local px = readByte(file)
              if alpha < 1 then
                grid[py][px] = {bg = bg, fg = fg, ch = symbol}
              end
            end
          end
        end
      end
    end
  end

  file:close()
  return {width = width, height = height, grid = grid}
end

local picture = loadOCIF6(path)

local maxW, maxH = gpu.maxResolution()
gpu.setResolution(maxW, maxH)
local sw, sh = gpu.getResolution()

local ox = math.max(1, math.floor((sw - picture.width) / 2) + 1)
local oy = math.max(1, math.floor((sh - picture.height) / 2) + 1)

gpu.setBackground(0x000000)
gpu.setForeground(0xFFFFFF)
gpu.fill(1, 1, sw, sh, " ")

local cells = {}

local function shouldAnimate(color, ch)
  local r, g, b = rgbSplit(color)
  local h, s, v = rgbToHsv(r, g, b)

  -- leave nearly-black background untouched
  if v < 0.08 then
    return false
  end

  -- animate colorful parts and bright emissive parts
  if s > 0.18 or v > 0.35 then
    return true
  end

  return ch ~= " "
end

for y = 1, picture.height do
  for x = 1, picture.width do
    local cell = picture.grid[y][x]

    gpu.setBackground(cell.bg)
    gpu.setForeground(cell.fg)
    gpu.set(ox + x - 1, oy + y - 1, cell.ch)

    local bgAnimate = shouldAnimate(cell.bg, cell.ch)
    local fgAnimate = shouldAnimate(cell.fg, cell.ch)

    local bgH, bgS, bgV = 0, 0, 0
    local fgH, fgS, fgV = 0, 0, 0

    if bgAnimate then
      local r, g, b = rgbSplit(cell.bg)
      bgH, bgS, bgV = rgbToHsv(r, g, b)
    end

    if fgAnimate then
      local r, g, b = rgbSplit(cell.fg)
      fgH, fgS, fgV = rgbToHsv(r, g, b)
    end

    cells[#cells + 1] = {
      sx = ox + x - 1,
      sy = oy + y - 1,
      ch = cell.ch,

      baseBG = cell.bg,
      baseFG = cell.fg,

      bgAnimate = bgAnimate,
      fgAnimate = fgAnimate,

      bgH = bgH, bgS = bgS, bgV = bgV,
      fgH = fgH, fgS = fgS, fgV = fgV,

      px = x,
      py = y,

      lastBG = cell.bg,
      lastFG = cell.fg
    }
  end
end

gpu.setBackground(0x000000)
gpu.setForeground(0xAAAAAA)
gpu.set(1, math.min(sh, oy + picture.height + 1), "Smooth recolor mode | Image stays in place | Ctrl+C to stop")

local function animatedColor(h, s, v, t, px, py, boost)
  local flow = t * 0.10 + px * 0.018 + py * 0.008
  local newH = (h + flow) % 1.0
  local newS = math.min(1.0, s * 1.08 + 0.02)
  local newV = math.min(1.0, v * boost)
  local r, g, b = hsvToRgb(newH, newS, newV)
  return rgbJoin(r, g, b)
end

while true do
  local t = os.clock()
  local lastBG = nil
  local lastFG = nil

  for i = 1, #cells do
    local c = cells[i]

    local bg = c.baseBG
    local fg = c.baseFG

    if c.bgAnimate then
      bg = animatedColor(c.bgH, c.bgS, c.bgV, t, c.px, c.py, 1.03)
    end

    if c.fgAnimate then
      fg = animatedColor(c.fgH, c.fgS, c.fgV, t, c.px + 3, c.py + 2, 1.07)
    end

    if bg ~= c.lastBG or fg ~= c.lastFG then
      if lastBG ~= bg then
        gpu.setBackground(bg)
        lastBG = bg
      end
      if lastFG ~= fg then
        gpu.setForeground(fg)
        lastFG = fg
      end
      gpu.set(c.sx, c.sy, c.ch)
      c.lastBG = bg
      c.lastFG = fg
    end
  end

  os.sleep(0.05)
end
