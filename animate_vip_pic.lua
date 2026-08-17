-- FIXED VIP-SHOP fullscreen animation
-- One static .pic, drawn once. Only colors are updated afterward.
-- No full-screen clearing inside the animation loop.

local component = require("component")
local gpu = component.gpu
local os = require("os")

local path = (...) or "/home/vip_shop_fixed.pic"

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

local function rb(f)
  local s=f:read(1)
  if not s then error("Unexpected EOF") end
  return string.byte(s)
end

local function ru16(f) return rb(f)*256+rb(f) end

local function rchar(f)
  local a=f:read(1)
  if not a then error("Unexpected EOF") end
  local b=string.byte(a)
  local n
  if b<0x80 then n=1 elseif b<0xE0 then n=2 elseif b<0xF0 then n=3 else n=4 end
  if n==1 then return a end
  local r=f:read(n-1)
  if not r or #r~=n-1 then error("Unexpected EOF in UTF-8") end
  return a..r
end

local function makeGrid(w,h)
  local g={}
  for y=1,h do
    g[y]={}
    for x=1,w do g[y][x]={bg=0,fg=0xFFFFFF,ch=" "} end
  end
  return g
end

local function loadPic(p)
  local f,reason=io.open(p,"rb")
  if not f then error("Cannot open "..p..": "..tostring(reason)) end
  if f:read(4)~="OCIF" then f:close(); error("Not OCIF") end
  if rb(f)~=6 then f:close(); error("Need OCIF6") end

  local w,h=rb(f),rb(f)
  local g=makeGrid(w,h)
  local ac=rb(f)

  for ai=1,ac do
    local alpha=rb(f)/255
    local sc=ru16(f)
    for si=1,sc do
      local ch=rchar(f)
      local bc=rb(f)
      for bi=1,bc do
        local bg=palette[rb(f)+1]
        local fc=rb(f)
        for fi=1,fc do
          local fg=palette[rb(f)+1]
          local yc=rb(f)
          for yi=1,yc do
            local py=rb(f)
            local xc=rb(f)
            for xi=1,xc do
              local px=rb(f)
              if alpha<1 then g[py][px]={bg=bg,fg=fg,ch=ch} end
            end
          end
        end
      end
    end
  end

  f:close()
  return {w=w,h=h,g=g}
end

local function split(c)
  return math.floor(c/0x10000)%256, math.floor(c/0x100)%256, c%256
end

local function join(r,g,b)
  return math.floor(r)*0x10000+math.floor(g)*0x100+math.floor(b)
end

local function rgb2hsv(r,g,b)
  r,g,b=r/255,g/255,b/255
  local mx=math.max(r,g,b)
  local mn=math.min(r,g,b)
  local d=mx-mn
  local h=0
  local s=mx==0 and 0 or d/mx
  if d~=0 then
    if mx==r then h=((g-b)/d)%6
    elseif mx==g then h=((b-r)/d)+2
    else h=((r-g)/d)+4 end
    h=h/6
  end
  return h,s,mx
end

local function hsv2rgb(h,s,v)
  local i=math.floor(h*6)
  local f=h*6-i
  local p=v*(1-s)
  local q=v*(1-f*s)
  local t=v*(1-(1-f)*s)
  i=i%6
  local r,g,b
  if i==0 then r,g,b=v,t,p
  elseif i==1 then r,g,b=q,v,p
  elseif i==2 then r,g,b=p,v,t
  elseif i==3 then r,g,b=p,q,v
  elseif i==4 then r,g,b=t,p,v
  else r,g,b=v,p,q end
  return r*255,g*255,b*255
end

local pic=loadPic(path)

local mw,mh=gpu.maxResolution()
gpu.setResolution(mw,mh)
local sw,sh=gpu.getResolution()

local ox=math.max(1,math.floor((sw-pic.w)/2)+1)
local oy=math.max(1,math.floor((sh-pic.h)/2)+1)

gpu.setBackground(0x000000)
gpu.setForeground(0xFFFFFF)
gpu.fill(1,1,sw,sh," ")

local animated={}

-- Draw the picture exactly once.
for y=1,pic.h do
  for x=1,pic.w do
    local c=pic.g[y][x]
    gpu.setBackground(c.bg)
    gpu.setForeground(c.fg)
    gpu.set(ox+x-1,oy+y-1,c.ch)

    local function prep(color)
      local r,g,b=split(color)
      local h,s,v=rgb2hsv(r,g,b)
      -- Keep black/dark background fixed. Animate bright/colorful artwork only.
      if v<0.10 then return false,0,0,0 end
      if s<0.18 and v<0.45 then return false,0,0,0 end
      return true,h,s,v
    end

    local ab,bh,bs,bv=prep(c.bg)
    local af,fh,fs,fv=prep(c.fg)

    if ab or af then
      animated[#animated+1]={
        x=ox+x-1,y=oy+y-1,px=x,py=y,ch=c.ch,
        bg=c.bg,fg=c.fg,
        ab=ab,bh=bh,bs=bs,bv=bv,
        af=af,fh=fh,fs=fs,fv=fv,
        lbg=c.bg,lfg=c.fg
      }
    end
  end
end

local function wave(h,s,v,t,x,y)
  -- Smooth left-to-right wave, deliberately subtle so the image keeps its detail.
  local w=math.sin(t*1.45-x*0.105+y*0.018)
  local hue=(h + 0.030*w + 0.010*t) % 1
  local value=math.min(1,v*(1+0.035*w))
  local sat=math.min(1,s*1.035+0.01)
  local r,g,b=hsv2rgb(hue,sat,value)
  return join(r,g,b)
end

while true do
  local t=os.clock()
  local lastBG,lastFG=nil,nil

  for i=1,#animated do
    local c=animated[i]
    local bg=c.bg
    local fg=c.fg

    if c.ab then bg=wave(c.bh,c.bs,c.bv,t,c.px,c.py) end
    if c.af then fg=wave(c.fh,c.fs,c.fv,t,c.px+2,c.py) end

    if bg~=c.lbg or fg~=c.lfg then
      if bg~=lastBG then gpu.setBackground(bg); lastBG=bg end
      if fg~=lastFG then gpu.setForeground(fg); lastFG=fg end
      gpu.set(c.x,c.y,c.ch)
      c.lbg,c.lfg=bg,fg
    end
  end

  os.sleep(0.07)
end
