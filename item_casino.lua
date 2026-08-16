local component = require("component")
local event = require("event")
local computer = require("computer")
local term = require("term")
local unicode = require("unicode")
local serialization = require("serialization")
unpackArgs = table.unpack or unpack

local BUILD = "VIP-CASINO-PHYSICAL-v3.6.6-RAW-ME-STOCK-MONITOR"

local CONFIG_PATH = "/home/casino_config.lua"

local DISPLAY_VERSION = "v_3.6.6"
local FOOTER_OWNER = "ZoziDo"

local function loadMainConfig()
  local loader, err =
    loadfile(CONFIG_PATH)

  if not loader then
    error(
      "Не удалось загрузить "
      .. CONFIG_PATH
      .. ": "
      .. tostring(err)
    )
  end

  local ok, cfg =
    pcall(loader)

  if not ok then
    error(
      "Ошибка casino_config.lua: "
      .. tostring(cfg)
    )
  end

  if type(cfg) ~= "table" then
    error(
      "casino_config.lua должен возвращать таблицу"
    )
  end

  return cfg
end

local CONFIG = loadMainConfig()

local HW = CONFIG.hardware or {}
local BET = CONFIG.bet or {}
local FILES = CONFIG.files or {}
local RNG_CONFIG = CONFIG.rng or {}
local JACKPOT = CONFIG.jackpot or {}
TERMINAL = CONFIG.terminal or {}
STOCK = CONFIG.stock or {}
local ADMIN = CONFIG.admin or {}
local REEL = CONFIG.reel or {}
local IDLE = CONFIG.idle or {}
local TIMING = CONFIG.timing or {}
local UI = CONFIG.ui or {}

local PRIZE_PIM =
  tostring(HW.pim or "")

local PRIZE_ME =
  tostring(HW.me or "")

local PRIZE_ME_DIRECTION =
  tostring(HW.meDirection or "UP")

local BET_ITEM_ID =
  tostring(BET.itemId or "")

local BET_ITEM_DAMAGE =
  tonumber(BET.damage) or 0

local BET_AMOUNT =
  tonumber(BET.amount) or 4

BET_PIM_PUSH_DIRECTION =
  tostring(BET.pimPushDirection or "down")

local DISPLAY_SLOT =
  tonumber(HW.displaySlot) or 1

local CENTER_POS =
  tonumber(HW.centerPos) or 4

local SELECTORS =
  HW.selectors or {}

local PENDING_FILE =
  tostring(
    FILES.pending
    or "/home/vip_casino_physical_pending.lua"
  )

local PRIZE_CONFIG_PATH =
  tostring(
    FILES.prizes
    or "/home/casino_prizes.lua"
  )

local RNG_STATE_FILE =
  tostring(
    FILES.rngState
    or "/home/vip_casino_rng_state.dat"
  )

local RANDOM_SCALE =
  tonumber(RNG_CONFIG.scale)
  or 1000000

CasinoHouse = {
  statsFile = tostring(
    FILES.stats
    or "/home/vip_casino_house_stats.lua"
  ),

  staffItemId = tostring(
    JACKPOT.staffItemId
    or "DraconicEvolution:draconicDistructionStaff"
  ),

  staffEvery = math.max(
    1,
    math.floor(
      tonumber(
        JACKPOT.staffEverySpins
      ) or 1000
    )
  ),

  staffIndex = nil,

  powerSealItemId = tostring(
    JACKPOT.powerSealItemId
    or "dwcity:Power_seal"
  ),

  powerSealEvery = math.max(
    1,
    math.floor(
      tonumber(
        JACKPOT.powerSealEverySpins
      ) or 500
    )
  ),

  powerSealIndex = nil,

  statusPopupOpen = false,
  statusPopupDirty = false,
  editStaffEvery = nil,
  statusMessage = "",

  stats = {
    version = 2,
    totalSpins = 0,
    totalMoney = 0,
    uniquePlayers = 0,
    players = {},
    cycleSpins = 0,
    staffWins = 0,
    staffEvery = nil,

    powerSealCycleSpins = 0,
    powerSealWins = 0,
    powerSealEvery = nil,

    specialCycleSpins = 0,
    staffClaimedThisCycle = false,
    powerSealClaimedThisCycle = false
  }
}

function casinoHouseSaveStats()
  local f, err =
    io.open(
      CasinoHouse.statsFile,
      "w"
    )

  if not f then
    return false, err
  end

  f:write(
    "return "
    .. serialization.serialize(
      CasinoHouse.stats
    )
    .. "\n"
  )

  f:close()

  return true
end

function casinoHouseLoadStats()
  local f =
    io.open(
      CasinoHouse.statsFile,
      "r"
    )

  if not f then
    return
  end

  local content =
    f:read("*a")

  f:close()

  if not content
    or content == ""
  then
    return
  end

  local expression =
    content:gsub(
      "^%s*return%s+",
      ""
    )

  local ok, saved =
    pcall(
      serialization.unserialize,
      expression
    )

  if not ok
    or type(saved) ~= "table"
  then
    return
  end

  local savedStaffEvery =
    math.max(
      1,
      math.floor(
        tonumber(
          saved.staffEvery
        )
        or CasinoHouse.staffEvery
      )
    )

  CasinoHouse.staffEvery =
    savedStaffEvery

  local savedPowerSealEvery =
    math.max(
      1,
      math.floor(
        tonumber(
          saved.powerSealEvery
        )
        or CasinoHouse.powerSealEvery
      )
    )

  CasinoHouse.powerSealEvery =
    savedPowerSealEvery

  local players =
    type(saved.players) == "table"
    and saved.players
    or {}

  local unique = 0

  for _, present in pairs(players) do
    if present == true then
      unique = unique + 1
    end
  end

  CasinoHouse.stats = {
    version = 2,

    totalSpins =
      math.max(
        0,
        math.floor(
          tonumber(
            saved.totalSpins
          ) or 0
        )
      ),

    totalMoney =
      math.max(
        0,
        math.floor(
          tonumber(
            saved.totalMoney
          ) or 0
        )
      ),

    uniquePlayers =
      math.max(
        unique,
        math.floor(
          tonumber(
            saved.uniquePlayers
          ) or 0
        )
      ),

    players = players,

    cycleSpins =
      math.max(
        0,
        math.min(
          CasinoHouse.staffEvery,
          math.floor(
            tonumber(
              saved.cycleSpins
            ) or 0
          )
        )
      ),

    staffWins =
      math.max(
        0,
        math.floor(
          tonumber(
            saved.staffWins
          ) or 0
        )
      ),

    staffEvery =
      CasinoHouse.staffEvery,

    powerSealCycleSpins =
      math.max(
        0,
        math.min(
          CasinoHouse.powerSealEvery,
          math.floor(
            tonumber(
              saved.powerSealCycleSpins
            ) or 0
          )
        )
      ),

    powerSealWins =
      math.max(
        0,
        math.floor(
          tonumber(
            saved.powerSealWins
          ) or 0
        )
      ),

    powerSealEvery =
      CasinoHouse.powerSealEvery,

    specialCycleSpins =
      math.max(
        0,
        math.floor(
          tonumber(
            saved.specialCycleSpins
          )
          or math.max(
            tonumber(
              saved.cycleSpins
            ) or 0,
            tonumber(
              saved.powerSealCycleSpins
            ) or 0
          )
        )
      ),

    staffClaimedThisCycle =
      saved.staffClaimedThisCycle
      == true,

    powerSealClaimedThisCycle =
      saved.powerSealClaimedThisCycle
      == true
  }

  if saved.specialCycleSpins == nil then
    local migrated =
      CasinoHouse.stats.specialCycleSpins

    if migrated
      >= CasinoHouse.powerSealEvery
      and (
        tonumber(
          saved.powerSealCycleSpins
        ) or 0
      ) < CasinoHouse.powerSealEvery
    then
      CasinoHouse.stats.powerSealClaimedThisCycle =
        true
    end
  end

  CasinoHouse.stats.cycleSpins =
    CasinoHouse.stats.specialCycleSpins

  CasinoHouse.stats.powerSealCycleSpins =
    CasinoHouse.stats.specialCycleSpins
end

function casinoHouseCycleMax()
  return math.max(
    CasinoHouse.staffEvery,
    CasinoHouse.powerSealEvery
  )
end

function casinoHouseSelectDueSpecial()
  local stats =
    CasinoHouse.stats

  local cycle =
    tonumber(
      stats.specialCycleSpins
    ) or 0

  local staffDue =
    not stats.staffClaimedThisCycle
    and cycle
      >= CasinoHouse.staffEvery

  local sealDue =
    not stats.powerSealClaimedThisCycle
    and cycle
      >= CasinoHouse.powerSealEvery

  if not staffDue
    and not sealDue
  then
    return nil
  end

  if staffDue and sealDue then
    if CasinoHouse.staffEvery
      < CasinoHouse.powerSealEvery
    then
      return "staff"
    end

    if CasinoHouse.powerSealEvery
      < CasinoHouse.staffEvery
    then
      return "power_seal"
    end

    return "staff"
  end

  if staffDue then
    return "staff"
  end

  return "power_seal"
end

function casinoHouseRecordPaidSpin(
  player,
  paidMoney
)
  local stats =
    CasinoHouse.stats

  stats.totalSpins =
    stats.totalSpins + 1

  stats.totalMoney =
    stats.totalMoney
    + math.max(
        0,
        math.floor(
          tonumber(paidMoney) or 0
        )
      )

  local playerKey =
    string.lower(
      tostring(player or "")
    )

  if playerKey ~= ""
    and stats.players[playerKey]
      ~= true
  then
    stats.players[playerKey] = true
    stats.uniquePlayers =
      stats.uniquePlayers + 1
  end

  stats.specialCycleSpins =
    math.max(
      0,
      math.floor(
        tonumber(
          stats.specialCycleSpins
        ) or 0
      )
    ) + 1

  stats.cycleSpins =
    stats.specialCycleSpins

  stats.powerSealCycleSpins =
    stats.specialCycleSpins

  local due =
    casinoHouseSelectDueSpecial()

  casinoHouseSaveStats()

  return {
    totalSpin =
      stats.totalSpins,

    cycleSpin =
      stats.specialCycleSpins,

    powerSealCycleSpin =
      stats.specialCycleSpins,

    specialDue =
      due,

    forceStaff =
      due == "staff",

    forcePowerSeal =
      due == "power_seal"
  }
end

function casinoHouseCanResetCycle()
  return CasinoHouse.stats.staffClaimedThisCycle
    == true
    and CasinoHouse.stats.powerSealClaimedThisCycle
      == true
end

function casinoHouseResetSpecialCycle()
  CasinoHouse.stats.specialCycleSpins = 0
  CasinoHouse.stats.cycleSpins = 0
  CasinoHouse.stats.powerSealCycleSpins = 0

  CasinoHouse.stats.staffClaimedThisCycle =
    false

  CasinoHouse.stats.powerSealClaimedThisCycle =
    false

  return casinoHouseSaveStats()
end

function casinoHouseFinalizeStaff()
  CasinoHouse.stats.staffWins =
    CasinoHouse.stats.staffWins + 1

  CasinoHouse.stats.staffClaimedThisCycle =
    true

  if casinoHouseCanResetCycle() then
    return casinoHouseResetSpecialCycle()
  end

  return casinoHouseSaveStats()
end

function casinoHouseFinalizePowerSeal()
  CasinoHouse.stats.powerSealWins =
    CasinoHouse.stats.powerSealWins + 1

  CasinoHouse.stats.powerSealClaimedThisCycle =
    true

  if casinoHouseCanResetCycle() then
    return casinoHouseResetSpecialCycle()
  end

  return casinoHouseSaveStats()
end

function casinoHouseStaffProgressText()
  local stats =
    CasinoHouse.stats

  if stats.staffClaimedThisCycle then
    return "ВЫДАНО"
  end

  return tostring(
    math.min(
      tonumber(
        stats.specialCycleSpins
      ) or 0,
      CasinoHouse.staffEvery
    )
  )
    .. "/"
    .. tostring(
      CasinoHouse.staffEvery
    )
end

function casinoHousePowerSealProgressText()
  local stats =
    CasinoHouse.stats

  if stats.powerSealClaimedThisCycle then
    return "ВЫДАНО"
  end

  return tostring(
    math.min(
      tonumber(
        stats.specialCycleSpins
      ) or 0,
      CasinoHouse.powerSealEvery
    )
  )
    .. "/"
    .. tostring(
      CasinoHouse.powerSealEvery
    )
end

casinoHouseLoadStats()

CasinoHouse.stats.staffEvery =
  CasinoHouse.staffEvery

CasinoHouse.stats.powerSealEvery =
  CasinoHouse.powerSealEvery

CasinoHouse.stats.specialCycleSpins =
  math.max(
    0,
    math.floor(
      tonumber(
        CasinoHouse.stats.specialCycleSpins
      ) or 0
    )
  )

CasinoHouse.stats.cycleSpins =
  CasinoHouse.stats.specialCycleSpins

CasinoHouse.stats.powerSealCycleSpins =
  CasinoHouse.stats.specialCycleSpins

local CASINO_MODEM_ADDRESS =
  tostring(JACKPOT.casinoModem or "")

local JACKPOT_BOARD_MODEM_ADDRESS =
  tostring(JACKPOT.boardModem or "")

local JACKPOT_BOARD_PORT =
  tonumber(JACKPOT.port)
  or 28741

local JACKPOT_BOARD_PROTOCOL =
  tostring(
    JACKPOT.protocol
    or "VIP_CASINO_JACKPOT_V1"
  )

local JACKPOT_BOARD_SECRET =
  tostring(JACKPOT.secret or "")

TERMINAL_ENABLED =
  TERMINAL.enabled ~= false

TERMINAL_MODEM_ADDRESS =
  tostring(TERMINAL.modem or "")

TERMINAL_PORT =
  tonumber(TERMINAL.port) or 28742

TERMINAL_PROTOCOL =
  tostring(
    TERMINAL.protocol
    or "VIP_CASINO_TERMINAL_V1"
  )

TERMINAL_SECRET =
  tostring(
    TERMINAL.secret
    or "VIP_CASINO_LOCAL_TERMINAL"
  )

TERMINAL_STATUS_INTERVAL =
  tonumber(
    TERMINAL.statusInterval
  ) or 0.75

local CLEAR_WINNER_ENABLED =
  ADMIN.clearWinnerEnabled ~= false

local CLEAR_WINNER_LABEL =
  tostring(
    ADMIN.clearWinnerLabel
    or "[ СТЕРЕТЬ ПОБЕДИТЕЛЯ ]"
  )

local CLEAR_WINNER_HOLD =
  tonumber(
    ADMIN.clearWinnerMessageHold
  ) or 0.8

local REEL_FAST_STEPS =
  tonumber(REEL.fastSteps) or 8

local REEL_FAST_DELAY =
  tonumber(REEL.fastDelay) or 0.015

local REEL_MEDIUM_DELAYS =
  REEL.mediumDelays
  or {
    0.022,
    0.030,
    0.038,
    0.048
  }

local REEL_SLOW_DELAYS =
  REEL.slowDelays
  or {
    0.025,
    0.035,
    0.045
  }

local REEL_CENTER_DELAY =
  tonumber(REEL.centerDelay)
  or 0.035

local REEL_FINAL_DELAYS =
  REEL.finalDelays
  or {
    0.050,
    0.070,
    0.095
  }

RuntimeTuning = RuntimeTuning or {
  spinDuration =
    tonumber(REEL.spinDuration)
    or 2.50,

  spinDelay =
    tonumber(REEL.spinDelay)
    or tonumber(REEL.fastDelay)
    or 0.035,

  idleStepInterval =
    tonumber(IDLE.stepInterval)
    or 0.68,

  idleLongPause =
    tonumber(IDLE.longPause)
    or 1.20,

  idlePauseEvery =
    tonumber(IDLE.pauseEvery)
    or 7
}

function applyRuntimeTuning(values)
  if type(values) ~= "table" then
    return false, "settings_not_table"
  end

  if values.spinDuration ~= nil then
    RuntimeTuning.spinDuration =
      math.max(
        0.50,
        math.min(
          30.0,
          tonumber(values.spinDuration)
          or RuntimeTuning.spinDuration
        )
      )
  end

  if values.spinDelay ~= nil then
    RuntimeTuning.spinDelay =
      math.max(
        0.005,
        math.min(
          1.0,
          tonumber(values.spinDelay)
          or RuntimeTuning.spinDelay
        )
      )
  end

  if values.idleStepInterval ~= nil then
    RuntimeTuning.idleStepInterval =
      math.max(
        0.05,
        math.min(
          10.0,
          tonumber(values.idleStepInterval)
          or RuntimeTuning.idleStepInterval
        )
      )
  end

  if values.idleLongPause ~= nil then
    RuntimeTuning.idleLongPause =
      math.max(
        0.05,
        math.min(
          30.0,
          tonumber(values.idleLongPause)
          or RuntimeTuning.idleLongPause
        )
      )
  end

  if values.idlePauseEvery ~= nil then
    RuntimeTuning.idlePauseEvery =
      math.max(
        1,
        math.floor(
          tonumber(values.idlePauseEvery)
          or RuntimeTuning.idlePauseEvery
        )
      )
  end

  return true
end

local JACKPOT_RETRY_INTERVAL =
  tonumber(
    JACKPOT.retryInterval
    or TIMING.jackpotRetry
  ) or 5

local EVENT_POLL =
  tonumber(TIMING.eventPoll)
  or 0.03

local IDLE_BET_POLL =
  tonumber(TIMING.idleBetPoll)
  or 0.60

local AFTER_BET_ACCEPTED =
  tonumber(TIMING.afterBetAccepted)
  or 0.02

local AFTER_WIN =
  tonumber(TIMING.afterWin)
  or 0.15

local DELIVERY_CHECK_DELAY =
  tonumber(TIMING.deliveryCheck)
  or 0.15


PENDING_RETRY_INTERVAL =
  tonumber(TIMING.pendingRetry)
  or 2.0

local DELIVERY_CONFIRM_TIMEOUT =
  tonumber(TIMING.deliveryConfirmTimeout)
  or 3.00

local ERROR_PAUSE =
  tonumber(TIMING.errorPause)
  or 0.45

local STARTUP_PAUSE =
  tonumber(TIMING.startupPause)
  or 0.45

local HARDWARE_ERROR_POLL =
  tonumber(TIMING.hardwareErrorPoll)
  or 0.15

local function loadPrizeConfig()
  local loader, err =
    loadfile(PRIZE_CONFIG_PATH)

  if not loader then
    error(
      "Не удалось загрузить "
      .. PRIZE_CONFIG_PATH
      .. ": "
      .. tostring(err)
    )
  end

  local ok, cfg =
    pcall(loader)

  if not ok then
    error(
      "Ошибка casino_prizes.lua: "
      .. tostring(cfg)
    )
  end

  if type(cfg) ~= "table"
    or type(cfg.prizes) ~= "table"
  then
    error(
      "casino_prizes.lua: отсутствует таблица prizes"
    )
  end

  return cfg
end

local PRIZE_CONFIG =
  loadPrizeConfig()

local PRIZES = {}
local PRIZE_BY_KEY = {}
local PRIZE_INDEX_BY_KEY = {}

for _, raw in ipairs(
  PRIZE_CONFIG.prizes
) do
  if type(raw) == "table"
    and raw.enabled ~= false
  then
    local item =
      type(raw.item) == "table"
      and raw.item
      or {}

    local id =
      tostring(
        item.id
        or raw.itemId
        or ""
      )

    local dmg =
      tonumber(
        item.dmg
        or item.damage
        or raw.damage
        or 0
      ) or 0

    local key =
      tostring(raw.key or "")

    local name =
      tostring(
        raw.name
        or key
      )

    local chance =
      tonumber(raw.chance) or 0

    local qtyMin =
      math.max(
        1,
        math.floor(
          tonumber(raw.qtyMin) or 1
        )
      )

    local qtyMax =
      math.max(
        1,
        math.floor(
          tonumber(raw.qtyMax)
          or qtyMin
        )
      )

    if qtyMax < qtyMin then
      qtyMin, qtyMax =
        qtyMax, qtyMin
    end

    if key ~= ""
      and id ~= ""
      and chance > 0
    then
      local prize = {
        key = key,
        label = name,
        name = name,

        category =
          tostring(
            raw.category
            or "common"
          ),

        chance = chance,

        qtyMin = qtyMin,
        qtyMax = qtyMax,

        item = {
          id = id,
          dmg = dmg,
          qty = 1
        }
      }

      local itemLabel =
        item.itemLabel
        or item.item_label
        or raw.itemLabel
        or raw.item_label

      if itemLabel
        and tostring(itemLabel) ~= ""
      then
        prize.item.itemLabel =
          tostring(itemLabel)
      end

      local nbtHash =
        item.nbt_hash
        or raw.nbt_hash

      if nbtHash
        and tostring(nbtHash) ~= ""
      then
        prize.item.nbt_hash =
          tostring(nbtHash)
      end

      PRIZES[#PRIZES + 1] =
        prize
    end
  end
end

if #PRIZES < 1 then
  error(
    "В "
    .. PRIZE_CONFIG_PATH
    .. " нет активных призов"
  )
end

local chanceTotal = 0
local unitTotal = 0
local fractions = {}

for index, prize in ipairs(PRIZES) do
  chanceTotal =
    chanceTotal + prize.chance

  local exact =
    (
      prize.chance
      / 100
    )
    * RANDOM_SCALE

  local base =
    math.floor(exact)

  prize.chanceUnits = base

  unitTotal =
    unitTotal + base

  fractions[#fractions + 1] = {
    index = index,
    fraction = exact - base
  }
end

if math.abs(
  chanceTotal - 100
) > 0.001
then
  error(
    string.format(
      "Сумма шансов каталога %.9f%%, ожидалось 100%%",
      chanceTotal
    )
  )
end

table.sort(
  fractions,
  function(a, b)
    if a.fraction == b.fraction then
      return a.index < b.index
    end

    return a.fraction > b.fraction
  end
)

local missing =
  RANDOM_SCALE - unitTotal

local fi = 1

while missing > 0 do
  local entry =
    fractions[fi]

  PRIZES[
    entry.index
  ].chanceUnits =
    PRIZES[
      entry.index
    ].chanceUnits + 1

  missing = missing - 1
  fi = fi + 1

  if fi > #fractions then
    fi = 1
  end
end

if missing < 0 then
  error(
    "Ошибка нормализации диапазонов RNG"
  )
end

local cursor = 0

for index, prize in ipairs(PRIZES) do
  prize.rangeFrom =
    cursor + 1

  prize.rangeTo =
    cursor
    + prize.chanceUnits

  cursor =
    prize.rangeTo

  PRIZE_BY_KEY[
    prize.key
  ] = prize

  PRIZE_INDEX_BY_KEY[
    prize.key
  ] = index
end

if cursor ~= RANDOM_SCALE then
  error(
    "Диапазоны RNG не покрывают 1.."
    .. tostring(RANDOM_SCALE)
  )
end

for index, prize in ipairs(PRIZES) do
  if string.lower(
    tostring(
      prize.item
      and prize.item.id
      or ""
    )
  ) == string.lower(
    CasinoHouse.staffItemId
  )
  then
    CasinoHouse.staffIndex = index
    break
  end
end

if not CasinoHouse.staffIndex then
  error(
    "JACKPOT-посох не найден в "
    .. PRIZE_CONFIG_PATH
    .. ": "
    .. CasinoHouse.staffItemId
  )
end

for index, prize in ipairs(PRIZES) do
  if string.lower(
    tostring(
      prize.item
      and prize.item.id
      or ""
    )
  ) == string.lower(
    CasinoHouse.powerSealItemId
  )
  then
    CasinoHouse.powerSealIndex = index
    break
  end
end

if not CasinoHouse.powerSealIndex then
  error(
    "Печать силы не найдена в "
    .. PRIZE_CONFIG_PATH
    .. ": "
    .. CasinoHouse.powerSealItemId
  )
end

local hardwareRngAddress = nil

for address in component.list() do
  local ok, methods =
    pcall(
      component.methods,
      address
    )

  if ok
    and type(methods) == "table"
    and methods.random
  then
    hardwareRngAddress =
      tostring(address)

    break
  end
end

local RNG_MOD = 2147483647
local RNG_MULT = 48271
local rngState = 1

local function hashText(
  seed,
  value
)
  local h =
    tonumber(seed) or 1

  local text =
    tostring(value or "")

  for i = 1, #text do
    h =
      (
        h * 131
        + text:byte(i)
        + i
      )
      % RNG_MOD
  end

  if h <= 0 then
    h = 1
  end

  return h
end

local function readSavedRngState()
  local f =
    io.open(
      RNG_STATE_FILE,
      "r"
    )

  if not f then
    return nil
  end

  local value =
    tonumber(
      f:read("*a")
    )

  f:close()

  if value
    and value > 0
    and value < RNG_MOD
  then
    return math.floor(value)
  end

  return nil
end

local function saveRngState()
  local f =
    io.open(
      RNG_STATE_FILE,
      "w"
    )

  if not f then
    return false
  end

  f:write(
    tostring(
      math.floor(rngState)
    )
  )

  f:close()

  return true
end

local function buildInitialSeed()
  local seed =
    readSavedRngState()
    or 104729

  seed =
    hashText(
      seed,
      tostring(
        computer.uptime()
      )
    )

  local okAddress, address =
    pcall(computer.address)

  if okAddress then
    seed =
      hashText(
        seed,
        address
      )
  end

  local okTime, now =
    pcall(os.time)

  if okTime then
    seed =
      hashText(
        seed,
        now
      )
  end

  local okFree, free =
    pcall(computer.freeMemory)

  if okFree then
    seed =
      hashText(
        seed,
        free
      )
  end

  for address, ctype in component.list() do
    seed =
      hashText(
        seed,
        tostring(address)
        .. ":"
        .. tostring(ctype)
      )
  end

  return seed
end

rngState =
  buildInitialSeed()

local function mixEntropy(extra)
  rngState =
    hashText(
      rngState,
      tostring(
        computer.uptime()
      )
      .. "|"
      .. tostring(extra or "")
    )

  local okFree, free =
    pcall(computer.freeMemory)

  if okFree then
    rngState =
      hashText(
        rngState,
        free
      )
  end
end

local function fallbackNext()
  rngState =
    (
      rngState
      * RNG_MULT
    )
    % RNG_MOD

  if rngState <= 0 then
    rngState = 1
  end

  return rngState
end

local function hardwareUInt32()
  if not hardwareRngAddress then
    return nil
  end

  local ok, bytes =
    pcall(
      component.invoke,
      hardwareRngAddress,
      "random",
      4
    )

  if not ok
    or type(bytes) ~= "string"
    or #bytes < 4
  then
    hardwareRngAddress = nil
    return nil
  end

  local a, b, c, d =
    bytes:byte(1, 4)

  return (
    (
      (
        a * 256
        + b
      ) * 256
      + c
    ) * 256
    + d
  )
end

local function localRandomInt(
  minimum,
  maximum,
  entropyTag
)
  minimum =
    math.floor(
      tonumber(minimum) or 0
    )

  maximum =
    math.floor(
      tonumber(maximum) or 0
    )

  if maximum < minimum then
    minimum, maximum =
      maximum, minimum
  end

  if minimum == maximum then
    return minimum
  end

  local span =
    maximum - minimum + 1

  if hardwareRngAddress then
    local UINT32 =
      4294967296

    local limit =
      math.floor(
        UINT32 / span
      ) * span

    for _ = 1, 16 do
      local value =
        hardwareUInt32()

      if value
        and value < limit
      then
        return minimum
          + (
            value % span
          )
      end
    end
  end

  mixEntropy(entropyTag)

  local usable =
    RNG_MOD - 1

  local limit =
    math.floor(
      usable / span
    ) * span

  for _ = 1, 32 do
    local value =
      fallbackNext() - 1

    if value < limit then
      local result =
        minimum
        + (
          value % span
        )

      saveRngState()

      return result
    end
  end

  local value =
    fallbackNext() - 1

  saveRngState()

  return minimum
    + (
      value % span
    )
end

local function chooseLocalPrize(
  player,
  forceStaff,
  forcePowerSeal
)
  local entropy =
    tostring(player or "")
    .. "|"
    .. tostring(
      computer.uptime()
    )

  local specialIndex = nil
  local specialTag = nil

  if forceStaff == true then
    specialIndex =
      CasinoHouse.staffIndex

    specialTag = "STAFF"
  elseif forcePowerSeal == true then
    specialIndex =
      CasinoHouse.powerSealIndex

    specialTag = "POWER_SEAL"
  end

  if specialIndex then
    local selected =
      PRIZES[specialIndex]

    if not selected then
      return nil,
        nil,
        nil,
        nil,
        "Особый приз не найден"
    end

    local qty =
      localRandomInt(
        selected.qtyMin,
        selected.qtyMax,
        specialTag
        .. "_QTY|"
        .. entropy
      )

    return selected,
      specialIndex,
      qty,
      specialTag
  end

  local ordinaryUnits = 0

  for index, prize in ipairs(PRIZES) do
    if index
      ~= CasinoHouse.staffIndex
      and index
        ~= CasinoHouse.powerSealIndex
    then
      ordinaryUnits =
        ordinaryUnits
        + math.max(
            0,
            math.floor(
              tonumber(
                prize.chanceUnits
              ) or 0
            )
          )
    end
  end

  if ordinaryUnits <= 0 then
    return nil,
      nil,
      nil,
      nil,
      "Нет обычных призов для RNG"
  end

  local roll =
    localRandomInt(
      1,
      ordinaryUnits,
      "PRIZE|"
      .. entropy
    )

  local selected = nil
  local selectedIndex = nil
  local cursorNormal = 0

  for index, prize in ipairs(PRIZES) do
    if index
      ~= CasinoHouse.staffIndex
      and index
        ~= CasinoHouse.powerSealIndex
    then
      cursorNormal =
        cursorNormal
        + math.max(
            0,
            math.floor(
              tonumber(
                prize.chanceUnits
              ) or 0
            )
          )

      if roll <= cursorNormal then
        selected = prize
        selectedIndex = index
        break
      end
    end
  end

  if not selected then
    return nil,
      nil,
      nil,
      nil,
      "RNG roll не попал в обычный диапазон"
  end

  local qty =
    localRandomInt(
      selected.qtyMin,
      selected.qtyMax,
      "QTY|"
      .. selected.key
      .. "|"
      .. tostring(roll)
      .. "|"
      .. entropy
    )

  return selected,
    selectedIndex,
    qty,
    roll
end

local function getRngMode()
  if hardwareRngAddress then
    return "HARDWARE RANDOM"
  end

  return "LOCAL PRNG"
end

local gpu = component.gpu

local maxW, maxH = gpu.maxResolution()
gpu.setResolution(maxW, maxH)

local W, H = gpu.getResolution()

term.setCursorBlink(false)

local DEFAULT_COLORS = {
  bg = 0x000000,

  white = 0xFFFFFF,
  gray = 0xAAAAAA,
  darkGray = 0x555555,

  cyan = 0x00D7FF,
  green = 0x55FF55,
  yellow = 0xFFFF55,
  red = 0xFF5555,

  gold = 0xFFC400,
  goldDark = 0xB88600,

  panel = 0x0B1116,
  panel2 = 0x101A21,
  line = 0x236B7B,
  blue = 0x55AAFF
}

local C = {}

for key, value in pairs(
  DEFAULT_COLORS
) do
  C[key] = value
end

if type(UI.colors) == "table" then
  for key, value in pairs(
    UI.colors
  ) do
    C[key] =
      tonumber(value)
      or value
  end
end

local function fill(x, y, w, h, bg)
  local old = gpu.getBackground()

  gpu.setBackground(bg)
  gpu.fill(x, y, w, h, " ")

  gpu.setBackground(old)
end

local function text(x, y, value, fg, bg)
  local oldFg = gpu.getForeground()
  local oldBg = gpu.getBackground()

  if fg then
    gpu.setForeground(fg)
  end

  if bg then
    gpu.setBackground(bg)
  end

  gpu.set(x, y, tostring(value))

  gpu.setForeground(oldFg)
  gpu.setBackground(oldBg)
end

local function center(y, value, fg)
  local s = tostring(value or "")
  local x =
    math.floor((W - unicode.len(s)) / 2) + 1

  text(
    math.max(1, x),
    y,
    s,
    fg or C.white,
    C.bg
  )
end

local function drawFrame()
  text(
    1,
    1,
    "+"
      .. string.rep("=", W - 2)
      .. "+",
    C.gold,
    C.bg
  )

  for y = 2, H - 1 do
    text(
      1,
      y,
      "|",
      C.goldDark,
      C.bg
    )

    text(
      W,
      y,
      "|",
      C.goldDark,
      C.bg
    )
  end

  text(
    1,
    H,
    "+"
      .. string.rep("=", W - 2)
      .. "+",
    C.gold,
    C.bg
  )
end

local function hLine(
  y,
  color,
  ch
)
  text(
    2,
    y,
    string.rep(
      ch or "-",
      math.max(1, W - 2)
    ),
    color or C.line,
    C.bg
  )
end

local function drawPanel(
  x,
  y,
  w,
  h,
  title,
  titleColor
)
  if w < 4 or h < 3 then
    return
  end

  fill(
    x,
    y,
    w,
    h,
    C.panel
  )

  text(
    x,
    y,
    "+"
      .. string.rep(
        "-",
        math.max(0, w - 2)
      )
      .. "+",
    C.line,
    C.panel
  )

  for yy = y + 1, y + h - 2 do
    text(
      x,
      yy,
      "|",
      C.line,
      C.panel
    )

    text(
      x + w - 1,
      yy,
      "|",
      C.line,
      C.panel
    )
  end

  text(
    x,
    y + h - 1,
    "+"
      .. string.rep(
        "-",
        math.max(0, w - 2)
      )
      .. "+",
    C.line,
    C.panel
  )

  if title
    and tostring(title) ~= ""
  then
    local label =
      "[ "
      .. tostring(title)
      .. " ]"

    text(
      x + 2,
      y,
      label,
      titleColor or C.cyan,
      C.panel
    )
  end
end

local INFO_PANEL_Y =
  tonumber(UI.infoPanelY) or 20
local INFO_PANEL_H =
  math.max(
    10,
    H - INFO_PANEL_Y - 8
  )

local SYSTEM_PANEL_Y =
  INFO_PANEL_Y
  + INFO_PANEL_H
  + 1

local SYSTEM_PANEL_H =
  math.max(
    5,
    H - SYSTEM_PANEL_Y - 2
  )

local function getClearWinnerButtonX()
  return math.max(
    20,
    W
      - unicode.len(
          CLEAR_WINNER_LABEL
        )
      - 5
  )
end

local function getClearWinnerButtonY()
  return SYSTEM_PANEL_Y
end

local function drawClearWinnerButton()
  if not CLEAR_WINNER_ENABLED then
    return
  end

  text(
    getClearWinnerButtonX(),
    getClearWinnerButtonY(),
    CLEAR_WINNER_LABEL,
    C.red,
    C.panel
  )
end

local function drawBottomFooter(player)
  local nickPart =
    "[ "
    .. FOOTER_OWNER
    .. " ]"

  local versionPart =
    "[ "
    .. DISPLAY_VERSION
    .. " ]"

  local footer =
    nickPart
    .. "  "
    .. versionPart

  local footerLen =
    unicode.len(footer)

  local x =
    math.max(
      3,
      W - footerLen - 2
    )

  text(
    x,
    H,
    footer,
    C.gold,
    C.bg
  )

  text(
    x + 2,
    H,
    FOOTER_OWNER,
    C.yellow,
    C.bg
  )

  text(
    x
      + unicode.len(nickPart)
      + 4,
    H,
    DISPLAY_VERSION,
    C.gold,
    C.bg
  )
end

local function drawSessionStatus(
  player,
  betCount,
  totalPending
)
  local sessionText =
    player
    and (
      "PIM: ЗАНЯТ  •  ИГРОК: "
      .. tostring(player)
    )
    or "PIM: СВОБОДЕН  •  СЕССИЯ: НЕТ"

  local betText =
    "СТАВКА: "
    .. tostring(
      tonumber(betCount) or 0
    )
    .. "/"
    .. tostring(BET_AMOUNT)

  local pendingText =
    "ОЖИДАЮЩИХ ПРИЗОВ: "
    .. tostring(
      tonumber(totalPending) or 0
    )

  fill(
    3,
    8,
    W - 4,
    2,
    C.bg
  )

  center(
    8,
    "СОСТОЯНИЕ КАЗИНО",
    C.gold
  )

  center(
    9,
    sessionText
      .. "  •  "
      .. betText
      .. "  •  "
      .. pendingText,
    player
      and C.green
      or C.gray
  )
end

local function drawBase()
  fill(
    1,
    1,
    W,
    H,
    C.bg
  )

  drawFrame()

  center(
    2,
    "VIP-CASINO  •  PHYSICAL ITEM JACKPOT",
    C.cyan
  )

  center(
    3,
    "ЛОКАЛЬНЫЙ RNG  •  ПРИЗЫ ИЗ ME  •  АВТОМАТИЧЕСКАЯ ВЫДАЧА",
    C.gray
  )

  hLine(
    4,
    C.goldDark,
    "="
  )

  text(
    4,
    5,
    "ИГРОК: ---",
    C.white,
    C.bg
  )

  center(
    5,
    "СТАВКА: "
      .. tostring(BET_AMOUNT)
      .. " ДЕНЕГ",
    C.gold
  )

  local rightInfo =
    "КАТАЛОГ: "
    .. tostring(#PRIZES)
    .. " ПРИЗОВ"

  text(
    math.max(
      3,
      W
        - unicode.len(rightInfo)
        - 3
    ),
    5,
    rightInfo,
    C.white,
    C.bg
  )

  hLine(
    6,
    C.line,
    "-"
  )

  drawSessionStatus(
    nil,
    0,
    0
  )

  center(
    12,
    "ФИЗИЧЕСКИЙ БАРАБАН",
    C.cyan
  )

  center(
    14,
    "[ 1 ]  [ 2 ]  [ 3 ]  [ ★ 4 ★ ]  [ 5 ]  [ 6 ]  [ 7 ]",
    C.gray
  )

  center(
    15,
    "▲",
    C.gold
  )

  center(
    16,
    "ЦЕНТР = ВЫИГРЫШ",
    C.gold
  )

  center(
    18,
    "ОБЫЧНЫЙ  •  НЕОБЫЧНЫЙ  •  РЕДКИЙ  •  ЭПИЧЕСКИЙ  •  ЛЕГЕНДАРНЫЙ  •  JACKPOT",
    C.darkGray
  )

  drawPanel(
    3,
    INFO_PANEL_Y,
    W - 4,
    INFO_PANEL_H,
    "ТЕКУЩЕЕ СОСТОЯНИЕ",
    C.cyan
  )

  if SYSTEM_PANEL_Y
    + SYSTEM_PANEL_H
    <= H
  then
    drawPanel(
      3,
      SYSTEM_PANEL_Y,
      W - 4,
      SYSTEM_PANEL_H,
      "СИСТЕМА",
      C.gold
    )

    drawClearWinnerButton()
  end

  if H >= 4 then
    center(
      H - 1,
      "СИСТЕМА: ONLINE  •  ВЫДАЧА: ME -> PIM  •  RNG: LOCAL  •  JACKPOT BOARD",
      C.darkGray
    )
  end

  drawBottomFooter(nil)
end

local function clearInfo()
  fill(
    5,
    INFO_PANEL_Y + 2,
    W - 8,
    math.max(
      1,
      INFO_PANEL_H - 4
    ),
    C.panel
  )
end

local function drawStatus(
  line1,
  color1,
  line2,
  color2,
  line3,
  color3,
  line4,
  color4
)
  if type(PendingViewer) == "table"
    and PendingViewer.open == true
  then
    return
  end

  if type(CasinoHouse) == "table"
    and CasinoHouse.statusPopupOpen == true
  then
    return
  end

  clearInfo()

  local startY =
    INFO_PANEL_Y + 3

  if line1 then
    center(
      startY,
      line1,
      color1 or C.white
    )
  end

  if line2 then
    center(
      startY + 2,
      line2,
      color2 or C.gray
    )
  end

  if line3 then
    center(
      startY + 4,
      line3,
      color3 or C.gray
    )
  end

  if line4 then
    center(
      startY + 6,
      line4,
      color4 or C.gray
    )
  end
end

local function safeInvoke(address, method, ...)
  local ok, a, b, c, d = pcall(
    component.invoke,
    address,
    method,
    ...
  )

  if not ok then
    return false, tostring(a)
  end

  return true, a, b, c, d
end

local function safeEventPull(timeout)
  local result = {
    pcall(
      computer.pullSignal,
      timeout
    )
  }

  if not result[1] then
    return {}
  end

  table.remove(result, 1)

  return result
end

local quitRequested = false
casinoWirelessDispatch = nil

local function checkQuitEvent(ev)
  return false
end

local function sleepSafe(seconds)
  local deadline =
    computer.uptime() + seconds

  while computer.uptime() < deadline do
    local remaining =
      deadline - computer.uptime()

    local ev = safeEventPull(
      math.min(0.05, remaining)
    )

    local systemHandled = false
    local viewerHandled = false

    if type(CasinoHouse) == "table"
      and CasinoHouse.statusPopupOpen == true
      and type(handleHiddenStatusTouch)
        == "function"
    then
      systemHandled =
        handleHiddenStatusTouch(ev)
        == true
    end

    if not systemHandled
      and type(PendingViewer) == "table"
      and PendingViewer.open == true
      and type(
        PendingViewer.handleViewerTouch
      ) == "function"
    then
      viewerHandled =
        PendingViewer.handleViewerTouch(
          ev
        ) == true
    end

    if not systemHandled
      and not viewerHandled
      and type(casinoWirelessDispatch)
        == "function"
    then
      casinoWirelessDispatch(ev)
    end

    checkQuitEvent(ev)

    if type(CasinoHouse) == "table"
      and CasinoHouse.statusPopupOpen == true
      and CasinoHouse.statusPopupDirty == true
      and type(drawHiddenStatusPopup)
        == "function"
    then
      drawHiddenStatusPopup()
    end

    if type(PendingViewer) == "table"
      and PendingViewer.open == true
      and type(
        PendingViewer.draw
      ) == "function"
    then
      PendingViewer.draw()
    end

    if quitRequested then
      return false
    end
  end

  return true
end

local function validatePim()
  return component.type(PRIZE_PIM) == "pim"
end

local function getPimInventorySize()
  local ok, value = safeInvoke(
    PRIZE_PIM,
    "getInventorySize"
  )

  if not ok then
    return 0
  end

  return tonumber(value) or 0
end

local function getPlayerOnPim()
  local size = getPimInventorySize()

  if size <= 0 then
    return nil
  end

  local ok, value = safeInvoke(
    PRIZE_PIM,
    "getInventoryName"
  )

  if not ok then
    return nil
  end

  local name = tostring(value or "")

  if name == ""
    or name == "pim"
    or name == "nil"
  then
    return nil
  end

  return name
end

local function stackId(stack)
  if type(stack) ~= "table" then
    return nil
  end

  return tostring(
    stack.id
    or stack.name
    or ""
  )
end

local function stackDamage(stack)
  if type(stack) ~= "table" then
    return 0
  end

  return tonumber(
    stack.dmg
    or stack.damage
    or stack.meta
    or 0
  ) or 0
end

local function stackQty(stack)
  if type(stack) ~= "table" then
    return 0
  end

  return tonumber(
    stack.qty
    or stack.size
    or stack.count
    or 0
  ) or 0
end

local function countItemOnPim(item)
  local size = getPimInventorySize()

  if size <= 0 then
    return nil
  end

  local total = 0

  for slot = 0, math.floor(size) do
    local ok, stack = safeInvoke(
      PRIZE_PIM,
      "getStackInSlot",
      slot
    )

    if ok
      and type(stack) == "table"
      and stackId(stack) == tostring(item.id)
      and stackDamage(stack)
          == (tonumber(item.dmg) or 0)
    then
      total =
        total + stackQty(stack)
    end
  end

  return total
end

local jackpotModem = nil
local jackpotModemError = nil
wirelessDiag = {
  strengthOk = false,
  strengthValue = nil,
  terminalPortOpen = false,
  lastTerminalRxAt = 0,
  lastTerminalRxType = "",
  lastTerminalSender = "",
  lastStatusTxOk = false,
  lastStatusTxResult = ""
}


local function initJackpotModem()
  if component.type(CASINO_MODEM_ADDRESS)
    ~= "modem"
  then
    jackpotModem = nil
    jackpotModemError =
      "Модем казино не найден: "
      .. CASINO_MODEM_ADDRESS
    return false
  end

  local ok, proxy =
    pcall(
      component.proxy,
      CASINO_MODEM_ADDRESS
    )

  if not ok
    or not proxy
  then
    jackpotModem = nil
    jackpotModemError =
      "Не удалось открыть modem proxy"
    return false
  end

  jackpotModem = proxy
  jackpotModemError = nil

  local okStrength, strengthResult =
    pcall(
      component.invoke,
      CASINO_MODEM_ADDRESS,
      "setStrength",
      400
    )

  wirelessDiag.strengthOk =
    okStrength
      and strengthResult ~= false

  local okGetStrength, strengthValue =
    pcall(
      component.invoke,
      CASINO_MODEM_ADDRESS,
      "getStrength"
    )

  if okGetStrength then
    wirelessDiag.strengthValue =
      strengthValue
  end

  if TERMINAL_ENABLED then
    local okOpen, openResult =
      pcall(
        component.invoke,
        CASINO_MODEM_ADDRESS,
        "open",
        TERMINAL_PORT
      )

    wirelessDiag.terminalPortOpen =
      okOpen
        and openResult ~= false

    local okIsOpen, isOpen =
      pcall(
        component.invoke,
        CASINO_MODEM_ADDRESS,
        "isOpen",
        TERMINAL_PORT
      )

    if okIsOpen then
      wirelessDiag.terminalPortOpen =
        isOpen == true
    end
  end

  return true
end

local function isJackpotPrize(prize)
  return type(prize) == "table"
    and tostring(
      prize.category or ""
    ) == "jackpot"
end

local function sendJackpotToBoard(prize)
  if not isJackpotPrize(prize) then
    return false, "not_jackpot"
  end

  if not jackpotModem then
    initJackpotModem()
  end

  if not jackpotModem then
    return false,
      jackpotModemError
      or "modem_unavailable"
  end

  if not prize.jackpotMessageId
    or tostring(prize.jackpotMessageId) == ""
  then
    prize.jackpotMessageId =
      tostring(
        math.floor(
          computer.uptime() * 1000
        )
      )
      .. "-"
      .. tostring(
        math.random(
          100000,
          999999
        )
      )
  end

  local messageId =
    tostring(
      prize.jackpotMessageId
    )

  local ok, result =
    pcall(
      jackpotModem.send,
      JACKPOT_BOARD_MODEM_ADDRESS,
      JACKPOT_BOARD_PORT,
      JACKPOT_BOARD_PROTOCOL,
      JACKPOT_BOARD_SECRET,
      "JACKPOT",
      messageId,
      tostring(
        prize.player or "UNKNOWN"
      ),
      tostring(
        prize.label
        or prize.name
        or prize.key
        or "JACKPOT"
      ),
      tostring(
        tonumber(prize.originalQty)
        or tonumber(prize.qty)
        or 1
      )
    )

  if not ok then
    return false,
      tostring(result)
  end

  if result == false then
    return false,
      "modem.send returned false"
  end

  return true, messageId
end

local function sendClearWinnerToBoard()
  if not jackpotModem then
    initJackpotModem()
  end

  if not jackpotModem then
    return false,
      jackpotModemError
      or "modem_unavailable"
  end

  local messageId =
    "CLEAR-"
    .. tostring(
      math.floor(
        computer.uptime() * 1000
      )
    )
    .. "-"
    .. tostring(
      math.random(
        100000,
        999999
      )
    )

  local ok, result =
    pcall(
      jackpotModem.send,
      JACKPOT_BOARD_MODEM_ADDRESS,
      JACKPOT_BOARD_PORT,
      JACKPOT_BOARD_PROTOCOL,
      JACKPOT_BOARD_SECRET,
      "CLEAR_WINNER",
      messageId
    )

  if not ok then
    return false,
      tostring(result)
  end

  if result == false then
    return false,
      "modem.send returned false"
  end

  return true, messageId
end

initJackpotModem()

local pendingPrizes = {}
local pendingSeq = 0

local function verifyPendingFile(path)
  local loader, err =
    loadfile(path)

  if not loader then
    return false, err
  end

  local ok, value =
    pcall(loader)

  if not ok
    or type(value) ~= "table"
    or tonumber(value.version) ~= 2
    or type(value.prizes) ~= "table"
  then
    return false,
      value
      or "invalid_pending_payload"
  end

  return true
end

local function savePending()
  local payload = {
    version = 2,
    seq = pendingSeq,
    prizes = pendingPrizes
  }

  local serialized =
    "return "
    .. serialization.serialize(payload)
    .. "\n"

  local tmpPath =
    PENDING_FILE .. ".tmp"

  local backupPath =
    PENDING_FILE .. ".bak"

  local f, err =
    io.open(tmpPath, "w")

  if not f then
    return false, err
  end

  local okWrite, writeErr =
    pcall(
      function()
        f:write(serialized)
        f:flush()
      end
    )

  f:close()

  if not okWrite then
    pcall(os.remove, tmpPath)
    return false, writeErr
  end

  local okTmp, tmpErr =
    verifyPendingFile(tmpPath)

  if not okTmp then
    pcall(os.remove, tmpPath)
    return false, tmpErr
  end

  pcall(os.remove, backupPath)

  local current =
    io.open(PENDING_FILE, "r")

  if current then
    current:close()

    local okBackup, backupErr =
      os.rename(
        PENDING_FILE,
        backupPath
      )

    if not okBackup then
      pcall(os.remove, tmpPath)
      return false, backupErr
    end
  end

  local okRename, renameErr =
    os.rename(
      tmpPath,
      PENDING_FILE
    )

  if not okRename then
    pcall(
      os.rename,
      backupPath,
      PENDING_FILE
    )

    pcall(os.remove, tmpPath)

    return false, renameErr
  end

  local okFinal, finalErr =
    verifyPendingFile(
      PENDING_FILE
    )

  if not okFinal then
    pcall(os.remove, PENDING_FILE)

    pcall(
      os.rename,
      backupPath,
      PENDING_FILE
    )

    return false, finalErr
  end

  return true
end

local function loadPending()
  local f = io.open(PENDING_FILE, "r")

  if not f then
    return {}, 0
  end

  local content = f:read("*a")
  f:close()

  if not content or content == "" then
    return {}, 0
  end

  local expression =
    content:gsub("^%s*return%s+", "")

  local ok, result = pcall(
    serialization.unserialize,
    expression
  )

  if not ok or type(result) ~= "table" then
    return {}, 0
  end

  if tonumber(result.version) == 2
    and type(result.prizes) == "table"
  then
    return result.prizes,
      tonumber(result.seq) or 0
  end

  if result.player
    and result.item
    and result.qty
  then
    result.id =
      result.id
      or ("legacy-"
        .. tostring(
          math.floor(computer.uptime() * 1000)
        ))

    return {result}, 1
  end

  return {}, 0
end

local function makePendingId(player)
  pendingSeq = pendingSeq + 1

  return tostring(
    math.floor(computer.uptime() * 1000)
  )
    .. "-"
    .. tostring(pendingSeq)
    .. "-"
    .. tostring(player)
end

local function addPending(prize)
  local oldSeq =
    pendingSeq

  prize.id =
    prize.id
    or makePendingId(prize.player)

  pendingPrizes[#pendingPrizes + 1] =
    prize

  local lastErr = nil

  for attempt = 1, 3 do
    local ok, err =
      savePending()

    if ok then
      return prize
    end

    lastErr = err

    if attempt < 3 then
      os.sleep(0.05)
    end
  end

  table.remove(
    pendingPrizes,
    #pendingPrizes
  )

  pendingSeq = oldSeq

  return nil,
    lastErr
    or "pending_save_failed"
end

local function removePendingById(id)
  for i = #pendingPrizes, 1, -1 do
    if tostring(pendingPrizes[i].id)
      == tostring(id)
    then
      table.remove(pendingPrizes, i)
      savePending()
      return true
    end
  end

  return false
end

local function countPendingTotal()
  return #pendingPrizes
end

local function samePlayerName(a, b)
  a = string.lower(tostring(a or ""))
  b = string.lower(tostring(b or ""))
  return a ~= "" and b ~= "" and a == b
end

local function countPendingForPlayer(player)
  if not player then
    return 0
  end

  local count = 0

  for _, prize in ipairs(pendingPrizes) do
    if samePlayerName(
      prize.player,
      player
    ) then
      count = count + 1
    end
  end

  return count
end

local function findPendingForPlayer(
  player,
  wantedStatus
)
  if not player then
    return nil
  end

  for _, prize in ipairs(pendingPrizes) do
    if samePlayerName(
      prize.player,
      player
    )
      and (
        not wantedStatus
        or prize.status == wantedStatus
      )
    then
      return prize
    end
  end

  return nil
end

local function findWaitingPendingForPlayer(player)
  return findPendingForPlayer(
    player,
    "waiting_claim"
  )
end

local function findUncertainPendingForPlayer(player)
  return findPendingForPlayer(
    player,
    "delivery_uncertain"
  )
end

local function normalizeLoadedPending()
  local changed = false

  for _, prize in ipairs(pendingPrizes) do
    if not prize.id then
      prize.id =
        makePendingId(prize.player)

      changed = true
    end

    if prize.status == "spinning" then
      prize.status = "waiting_claim"
      changed = true
    end

    if prize.status == "delivering" then
      prize.status = "delivery_uncertain"
      changed = true
    end
  end

  if changed then
    savePending()
  end
end

function normalizeBetItemName(value)
  value =
    tostring(value or "")
  value =
    value:gsub("§.", "")
  value =
    value:gsub(
      "%$[0-9a-fA-Fk-oK-OrR]",
      ""
    )
  value =
    value:gsub("^%s+", "")
  value =
    value:gsub("%s+$", "")
  return string.lower(value)
end

function normalizeBetItemId(
  value,
  damage
)
  value =
    normalizeBetItemName(value)

  local base, suffix =
    value:match(
      "^(.*):(-?%d+)$"
    )

  if base
    and tonumber(suffix)
      == (tonumber(damage) or 0)
  then
    value = base
  end

  return value
end

function shortBetItemName(value)
  value =
    normalizeBetItemName(value)

  return value:match(
    "^[^:]+:(.+)$"
  ) or value
end

function itemMatchesBet(stack)
  if type(stack) ~= "table" then
    return false
  end

  local stackDamage =
    tonumber(
      stack.damage
      or stack.dmg
      or stack.meta
      or stack.item_damage
      or stack.itemDamage
    ) or 0

  local stackName =
    normalizeBetItemId(
      stack.name
      or stack.id
      or stack.item_name
      or stack.itemName
      or stack.internal_name
      or stack.internalName,
      stackDamage
    )

  local wantedName =
    normalizeBetItemId(
      BET_ITEM_ID,
      BET_ITEM_DAMAGE
    )

  local nameMatches =
    stackName ~= ""
    and wantedName ~= ""
    and (
      stackName == wantedName
      or shortBetItemName(stackName)
        == shortBetItemName(wantedName)
    )

  local damageMatches =
    BET_ITEM_DAMAGE == -1
    or BET_ITEM_DAMAGE == 32767
    or stackDamage == BET_ITEM_DAMAGE

  return nameMatches
    and damageMatches
end

function getBetInventoryStack(slot)
  local ok, stack =
    pcall(
      component.invoke,
      PRIZE_PIM,
      "getStackInSlot",
      slot
    )

  if ok then
    if type(stack) == "table" then
      return stack, true
    end

    if stack == nil
      or stack == false
    then
      return nil, true
    end
  end

  local okProxy, pim =
    pcall(
      component.proxy,
      PRIZE_PIM
    )

  if okProxy
    and pim
    and type(pim.getStackInSlot)
      == "function"
  then
    ok, stack =
      pcall(
        pim.getStackInSlot,
        slot
      )

    if ok then
      if type(stack) == "table" then
        return stack, true
      end

      if stack == nil
        or stack == false
      then
        return nil, true
      end
    end

    ok, stack =
      pcall(
        pim.getStackInSlot,
        pim,
        slot
      )

    if ok then
      if type(stack) == "table" then
        return stack, true
      end

      if stack == nil
        or stack == false
      then
        return nil, true
      end
    end
  end

  return nil, false
end

function parseMovedCount(result, requested)
  if type(result) == "number" then
    return math.max(
      0,
      math.floor(result)
    )
  end

  if result == true then
    return requested
  end

  if type(result) == "table" then
    return math.max(
      0,
      math.floor(
        tonumber(
          result.count
          or result.amount
          or result.size
        ) or 0
      )
    )
  end

  return 0
end

function getBetInventorySnapshot()
  local size =
    math.floor(
      tonumber(
        getPimInventorySize()
      ) or 0
    )

  if size <= 0 then
    return 0, {}
  end

  size = math.min(size, 64)

  local total = 0
  local slots = {}

  for slot = 0, size - 1 do
    local stack, readable =
      getBetInventoryStack(
        slot
      )

    if readable
      and itemMatchesBet(stack)
    then
      local qty =
        math.max(
          0,
          math.floor(
            tonumber(
              stack.size
              or stack.qty
              or stack.count
              or stack.amount
            ) or 0
          )
        )

      if qty > 0 then
        total = total + qty

        slots[#slots + 1] = {
          slot = slot,
          qty = qty
        }
      end
    end
  end

  return total, slots
end

function scanPlayerBetMoney()
  local total =
    select(
      1,
      getBetInventorySnapshot()
    )

  return math.max(
    0,
    math.floor(
      tonumber(total) or 0
    )
  )
end

function takeBetFromPlayer()
  local player =
    getPlayerOnPim()

  if not player then
    return false,
      0,
      "NO_PLAYER"
  end

  local total, slots =
    getBetInventorySnapshot()

  if total < BET_AMOUNT then
    return false,
      0,
      "NOT_ENOUGH_MONEY"
  end

  local need = BET_AMOUNT
  local movedTotal = 0

  for _, entry in ipairs(slots) do
    if need <= 0 then
      break
    end

    local moveNow =
      math.min(
        need,
        entry.qty
      )

    if moveNow > 0 then
      local okMove, result =
        pcall(
          component.invoke,
          PRIZE_PIM,
          "pushItem",
          BET_PIM_PUSH_DIRECTION,
          entry.slot,
          moveNow
        )

      if okMove then
        local moved =
          parseMovedCount(
            result,
            moveNow
          )

        if moved > 0 then
          movedTotal =
            movedTotal + moved

          need =
            need - moved
        end
      end
    end
  end

  if movedTotal == BET_AMOUNT then
    return true,
      movedTotal,
      "OK"
  end

  return false,
    movedTotal,
    movedTotal > 0
      and "PAYMENT_PARTIAL"
      or "PAYMENT_FAILED"
end

local function validateSelectors()
  for pos = 1, 7 do
    if component.type(SELECTORS[pos])
      ~= "openperipheral_selector"
    then
      return false,
        "Selector #"
        .. tostring(pos)
        .. " не найден"
    end
  end

  return true
end

local function clearSelectors()
  for pos = 1, 7 do
    safeInvoke(
      SELECTORS[pos],
      "setSlot",
      DISPLAY_SLOT,
      nil
    )
  end
end

local function selectorItemForPrize(prize)
  local result = {
    id = prize.item.id,
    dmg = prize.item.dmg or 0,
    qty = 1
  }

  if prize.item.itemLabel then
    result.itemLabel =
      prize.item.itemLabel
  end

  if prize.item.nbt_hash then
    result.nbt_hash =
      prize.item.nbt_hash
  end

  return result
end

local function showPrizeAt(pos, prizeIndex)
  local prize =
    PRIZES[prizeIndex]

  if not prize then
    return false,
      "Prize index "
      .. tostring(prizeIndex)
      .. " не найден"
  end

  return safeInvoke(
    SELECTORS[pos],
    "setSlot",
    DISPLAY_SLOT,
    selectorItemForPrize(prize)
  )
end

local function renderStrip(strip)
  for pos = 1, 7 do
    local ok, err =
      showPrizeAt(
        pos,
        strip[pos]
      )

    if not ok then
      return false,
        "Selector #"
        .. tostring(pos)
        .. ": "
        .. tostring(err)
    end
  end

  return true
end

local nextPoolIndex = 1

local function nextPrizeIndex()
  local value = nextPoolIndex

  nextPoolIndex =
    nextPoolIndex + 1

  if nextPoolIndex > #PRIZES then
    nextPoolIndex = 1
  end

  return value
end

local function nextFillerIndex(
  forbidden
)
  if #PRIZES <= 1 then
    return 1
  end

  for _ = 1, #PRIZES + 1 do
    local value =
      nextPrizeIndex()

    if value ~= forbidden then
      return value
    end
  end

  return (
    forbidden % #PRIZES
  ) + 1
end

local function makeStrip()
  local strip = {}

  for pos = 1, 7 do
    strip[pos] =
      ((pos - 1) % #PRIZES) + 1
  end

  return strip
end

local function shiftStrip(strip)
  for pos = 1, 6 do
    strip[pos] =
      strip[pos + 1]
  end

  strip[7] =
    nextPrizeIndex()
end

local IDLE_STEP_INTERVAL =
  tonumber(IDLE.stepInterval)
  or 0.68

local IDLE_LONG_PAUSE =
  tonumber(IDLE.longPause)
  or 1.20

local IDLE_PAUSE_EVERY =
  tonumber(IDLE.pauseEvery)
  or 7

local idleStrip = makeStrip()
local idleShowcaseActive = false
local idleLastStep = 0
local idleStepCount = 0

local function resetIdleShowcase()
  idleStrip = makeStrip()
  idleShowcaseActive = false
  idleLastStep = 0
  idleStepCount = 0
end

local function stopIdleShowcase()
  idleShowcaseActive = false
end

local function tickIdleShowcase(now)
  now = tonumber(now) or computer.uptime()

  if not idleShowcaseActive then
    idleShowcaseActive = true
    idleLastStep = now
    idleStepCount = 0

    renderStrip(idleStrip)
    return
  end

  local interval =
    RuntimeTuning.idleStepInterval

  if idleStepCount > 0
    and idleStepCount
      % RuntimeTuning.idlePauseEvery == 0
  then
    interval =
      RuntimeTuning.idleLongPause
  end

  if now - idleLastStep
    < interval
  then
    return
  end

  idleLastStep = now
  idleStepCount =
    idleStepCount + 1

  shiftStrip(idleStrip)
  renderStrip(idleStrip)
end


PendingViewer = PendingViewer or {
  open = false,
  page = 1,
  selected = 1,
  refreshRequested = false
}

function PendingViewer.buttonLabel()
  return "[ НЕВЫДАННЫЕ ПРИЗЫ: "
    .. tostring(
      countPendingTotal()
    )
    .. " ]"
end

function PendingViewer.buttonX()
  local label =
    PendingViewer.buttonLabel()

  return math.max(
    3,
    W - unicode.len(label) - 3
  )
end

function PendingViewer.short(
  value,
  maxLen
)
  local s =
    tostring(value or "")

  local limit =
    math.max(
      1,
      math.floor(
        tonumber(maxLen) or 1
      )
    )

  if unicode.len(s) <= limit then
    return s
  end

  if limit <= 3 then
    return unicode.sub(
      s,
      1,
      limit
    )
  end

  return unicode.sub(
    s,
    1,
    limit - 3
  ) .. "..."
end

function PendingViewer.statusText(prize)
  if type(prize) ~= "table" then
    return "НЕИЗВЕСТНО"
  end

  local status =
    tostring(
      prize.status or ""
    )

  if status == "waiting_claim" then
    if prize.lastError
      and tostring(
        prize.lastError
      ) ~= ""
    then
      return "ОЖИДАЕТ ПОВТОРА"
    end

    return "ОЖИДАЕТ ИГРОКА"
  end

  if status == "delivery_uncertain" then
    return "ТРЕБУЕТ ПРОВЕРКИ"
  end

  if status == "delivering" then
    return "ВЫДАЧА"
  end

  if status == "spinning" then
    return "БАРАБАН"
  end

  if status == "" then
    return "ОЖИДАЕТ ИГРОКА"
  end

  return status
end

function PendingViewer.statusColor(prize)
  local status =
    tostring(
      type(prize) == "table"
      and prize.status
      or ""
    )

  if status == "delivery_uncertain" then
    return C.red
  end

  if type(prize) == "table"
    and prize.lastError
    and tostring(
      prize.lastError
    ) ~= ""
  then
    return C.yellow
  end

  if status == "delivering" then
    return C.cyan
  end

  return C.gold
end

function PendingViewer.reasonText(prize)
  if type(prize) ~= "table" then
    return "-"
  end

  local raw =
    tostring(
      prize.lastError
      or prize.spinError
      or ""
    )

  if raw == "" then
    local status =
      tostring(
        prize.status or ""
      )

    if status == "waiting_claim" then
      return "ОЖИДАЕТ ВОЗВРАЩЕНИЯ ИГРОКА"
    end

    if status == "spinning" then
      return "ОЖИДАЕТ ЗАВЕРШЕНИЯ БАРАБАНА"
    end

    if status == "delivering" then
      return "ИДЁТ ВЫДАЧА ПРИЗА"
    end

    if status == "delivery_uncertain" then
      return "ТРЕБУЕТ ПРОВЕРКИ ВЫДАЧИ"
    end

    return "ПРИЧИНА НЕ ЗАПИСАНА"
  end

  if raw:find(
    "raw_export_failed",
    1,
    true
  ) then
    return "ME НЕ ВЫДАЛ ПРЕДМЕТ"
  end

  local map = {
    nothing_exported =
      "ME НЕ ВЫДАЛ ПРЕДМЕТ",

    ME_EMPTY_OR_INVENTORY_FULL =
      "НЕТ ПРЕДМЕТА В ME ИЛИ НЕТ МЕСТА В PIM",

    inventory_read_failed =
      "ОШИБКА ЧТЕНИЯ PIM",

    player_left_during_delivery =
      "ИГРОК УШЁЛ ВО ВРЕМЯ ВЫДАЧИ",

    after_read_failed =
      "ОШИБКА ПРОВЕРКИ PIM",

    delivery_uncertain =
      "ВЫДАЧА ТРЕБУЕТ ПРОВЕРКИ"
  }

  return map[raw]
    or raw
end

function PendingViewer.geometry()
  local x = 5
  local y = 7
  local w =
    math.max(
      70,
      W - 8
    )

  local h =
    math.max(
      24,
      H - 12
    )

  if x + w - 1 > W - 2 then
    w = W - x - 1
  end

  if y + h - 1 > H - 2 then
    h = H - y - 1
  end

  return x, y, w, h
end

function PendingViewer.rowsPerPage()
  local _, _, _, h =
    PendingViewer.geometry()

  return math.max(
    4,
    math.min(
      12,
      h - 17
    )
  )
end

function PendingViewer.pageCount()
  return math.max(
    1,
    math.ceil(
      countPendingTotal()
      / PendingViewer.rowsPerPage()
    )
  )
end

function PendingViewer.normalize()
  local total =
    countPendingTotal()

  if total <= 0 then
    PendingViewer.selected = 0
    PendingViewer.page = 1
    return
  end

  PendingViewer.selected =
    math.max(
      1,
      math.min(
        total,
        math.floor(
          tonumber(
            PendingViewer.selected
          ) or 1
        )
      )
    )

  PendingViewer.page =
    math.floor(
      (
        PendingViewer.selected - 1
      )
      / PendingViewer.rowsPerPage()
    ) + 1
end

function PendingViewer.draw()
  PendingViewer.normalize()

  local x, y, w, h =
    PendingViewer.geometry()

  fill(
    x,
    y,
    w,
    h,
    C.panel
  )

  drawPanel(
    x,
    y,
    w,
    h,
    "НЕВЫДАННЫЕ ПРИЗЫ",
    C.gold
  )

  text(
    x + 3,
    y + 2,
    "ВСЕГО: "
      .. tostring(
        countPendingTotal()
      ),
    countPendingTotal() > 0
      and C.gold
      or C.gray,
    C.panel
  )

  local pageInfo =
    "СТРАНИЦА "
    .. tostring(
      PendingViewer.page
    )
    .. "/"
    .. tostring(
      PendingViewer.pageCount()
    )

  text(
    x + w
      - unicode.len(pageInfo)
      - 3,
    y + 2,
    pageInfo,
    C.gray,
    C.panel
  )

  local headerY =
    y + 4

  local colN =
    x + 3

  local colPlayer =
    x + 7

  local colPrize =
    x + 28

  local colQty =
    x + w - 34

  local colStatus =
    x + w - 24

  text(
    colN,
    headerY,
    "#",
    C.cyan,
    C.panel
  )

  text(
    colPlayer,
    headerY,
    "ИГРОК",
    C.cyan,
    C.panel
  )

  text(
    colPrize,
    headerY,
    "ПРИЗ",
    C.cyan,
    C.panel
  )

  text(
    colQty,
    headerY,
    "КОЛ-ВО",
    C.cyan,
    C.panel
  )

  text(
    colStatus,
    headerY,
    "СТАТУС",
    C.cyan,
    C.panel
  )

  text(
    x + 3,
    headerY + 1,
    string.rep(
      "-",
      math.max(
        1,
        w - 6
      )
    ),
    C.line,
    C.panel
  )

  local rows =
    PendingViewer.rowsPerPage()

  local startIndex =
    (
      PendingViewer.page - 1
    ) * rows + 1

  local firstRowY =
    headerY + 2

  for row = 1, rows do
    local index =
      startIndex + row - 1

    local prize =
      pendingPrizes[index]

    local yy =
      firstRowY + row - 1

    if prize then
      local selected =
        index
        == PendingViewer.selected

      local bg =
        selected
        and C.panel2
        or C.panel

      fill(
        x + 2,
        yy,
        w - 4,
        1,
        bg
      )

      text(
        colN,
        yy,
        tostring(index),
        selected
          and C.yellow
          or C.gray,
        bg
      )

      text(
        colPlayer,
        yy,
        PendingViewer.short(
          prize.player or "---",
          18
        ),
        C.white,
        bg
      )

      text(
        colPrize,
        yy,
        PendingViewer.short(
          prize.label
          or prize.name
          or (
            type(prize.item)
              == "table"
            and prize.item.id
            or "?"
          ),
          math.max(
            12,
            colQty - colPrize - 2
          )
        ),
        C.green,
        bg
      )

      text(
        colQty,
        yy,
        "x"
          .. tostring(
            tonumber(prize.qty)
            or 0
          ),
        C.white,
        bg
      )

      text(
        colStatus,
        yy,
        PendingViewer.short(
          PendingViewer.statusText(
            prize
          ),
          20
        ),
        PendingViewer.statusColor(
          prize
        ),
        bg
      )
    end
  end

  local detailsY =
    y + h - 8

  text(
    x + 3,
    detailsY - 1,
    string.rep(
      "-",
      math.max(
        1,
        w - 6
      )
    ),
    C.line,
    C.panel
  )

  local selected =
    pendingPrizes[
      PendingViewer.selected
    ]

  if selected then
    local item =
      type(selected.item)
        == "table"
      and selected.item
      or {}

    text(
      x + 3,
      detailsY,
      "ИГРОК: "
        .. PendingViewer.short(
          selected.player or "---",
          24
        )
        .. "  •  ПРИЗ: "
        .. PendingViewer.short(
          selected.label
          or selected.name
          or item.id
          or "?",
          math.max(
            20,
            w - 50
          )
        ),
      C.white,
      C.panel
    )

    text(
      x + 3,
      detailsY + 1,
      "КОЛ-ВО: x"
        .. tostring(
          tonumber(selected.qty)
          or 0
        )
        .. "  •  СТАТУС: "
        .. PendingViewer.statusText(
          selected
        ),
      PendingViewer.statusColor(
        selected
      ),
      C.panel
    )

    text(
      x + 3,
      detailsY + 2,
      "ITEM: "
        .. PendingViewer.short(
          item.id or "?",
          math.max(
            20,
            w - 33
          )
        )
        .. "  •  DAMAGE: "
        .. tostring(
          tonumber(
            item.dmg
            or item.damage
          ) or 0
        ),
      C.cyan,
      C.panel
    )

    local labelNbt =
      item.itemLabel
      or item.item_label
      or item.nbt_hash
      or "-"

    text(
      x + 3,
      detailsY + 3,
      "LABEL/NBT: "
        .. PendingViewer.short(
          labelNbt,
          math.max(
            20,
            w - 18
          )
        ),
      C.gray,
      C.panel
    )

    text(
      x + 3,
      detailsY + 4,
      "ПРИЧИНА: "
        .. PendingViewer.short(
          PendingViewer.reasonText(
            selected
          ),
          math.max(
            20,
            w - 17
          )
        ),
      C.yellow,
      C.panel
    )
  else
    center(
      detailsY + 2,
      "НЕВЫДАННЫХ ПРИЗОВ НЕТ",
      C.darkGray
    )
  end

  local back =
    "[ НАЗАД ]"

  text(
    x + 3,
    y + h - 2,
    back,
    C.white,
    C.red
  )

  text(
    x + w - 15,
    y + h - 2,
    "[ < ]",
    PendingViewer.page > 1
      and C.white
      or C.darkGray,
    C.panel2
  )

  text(
    x + w - 8,
    y + h - 2,
    "[ > ]",
    PendingViewer.page
      < PendingViewer.pageCount()
      and C.white
      or C.darkGray,
    C.panel2
  )

  drawBottomFooter(nil)
end

function PendingViewer.openViewer()
  if type(SystemAdmin) == "table"
    and SystemAdmin.open == true
    and type(SystemAdmin.closeScreen)
      == "function"
  then
    SystemAdmin.closeScreen()
  end

  CasinoHouse.statusPopupOpen = false
  CasinoHouse.statusPopupDirty = false
  CasinoHouse.editStaffEvery = nil
  CasinoHouse.statusMessage = ""
  if gameBusy then
    return false
  end

  PendingViewer.open = true
  PendingViewer.page = 1

  PendingViewer.selected =
    countPendingTotal() > 0
      and 1
      or 0

  stopIdleShowcase()

  fill(
    1,
    1,
    W,
    H,
    C.bg
  )

  drawFrame()
  PendingViewer.draw()

  return true
end

function PendingViewer.closeViewer()
  PendingViewer.open = false
  PendingViewer.refreshRequested = true
  lastUiKey = nil

  drawBase()

  return true
end

function PendingViewer.handleButtonTouch(ev)
  if PendingViewer.open
    or gameBusy
    or type(ev) ~= "table"
    or ev[1] ~= "touch"
  then
    return false
  end

  local tx =
    tonumber(ev[3])

  local ty =
    tonumber(ev[4])

  if not tx or not ty then
    return false
  end

  local label =
    PendingViewer.buttonLabel()

  local bx =
    PendingViewer.buttonX()

  if ty == 5
    and tx >= bx
    and tx < bx
      + unicode.len(label)
  then
    return PendingViewer.openViewer()
  end

  return false
end

function PendingViewer.handleViewerTouch(ev)
  if not PendingViewer.open
    or type(ev) ~= "table"
    or ev[1] ~= "touch"
  then
    return false
  end

  local tx =
    tonumber(ev[3])

  local ty =
    tonumber(ev[4])

  if not tx or not ty then
    return true
  end

  local x, y, w, h =
    PendingViewer.geometry()

  local bottomY =
    y + h - 2

  if ty == bottomY
    and tx >= x + 3
    and tx < x + 12
  then
    PendingViewer.closeViewer()
    return true
  end

  if ty == bottomY
    and tx >= x + w - 15
    and tx < x + w - 10
  then
    if PendingViewer.page > 1 then
      PendingViewer.page =
        PendingViewer.page - 1

      PendingViewer.selected =
        (
          PendingViewer.page - 1
        )
        * PendingViewer.rowsPerPage()
        + 1

      PendingViewer.draw()
    end

    return true
  end

  if ty == bottomY
    and tx >= x + w - 8
    and tx < x + w - 3
  then
    if PendingViewer.page
      < PendingViewer.pageCount()
    then
      PendingViewer.page =
        PendingViewer.page + 1

      PendingViewer.selected =
        (
          PendingViewer.page - 1
        )
        * PendingViewer.rowsPerPage()
        + 1

      PendingViewer.draw()
    end

    return true
  end

  local firstRowY =
    y + 6

  local rows =
    PendingViewer.rowsPerPage()

  if ty >= firstRowY
    and ty < firstRowY + rows
  then
    local row =
      ty - firstRowY + 1

    local index =
      (
        PendingViewer.page - 1
      ) * rows + row

    if pendingPrizes[index] then
      PendingViewer.selected =
        index

      PendingViewer.draw()
    end

    return true
  end

  return true
end

local function animateStep(
  strip,
  delay
)
  shiftStrip(strip)

  local ok, err =
    renderStrip(strip)

  if not ok then
    return false, err
  end

  if not sleepSafe(delay) then
    return false, "quit"
  end

  return true
end

local function forceWinnerIntoCenter(
  strip,
  winnerIndex
)
  for pos = 1, 7 do
    strip[pos] =
      nextFillerIndex(
        winnerIndex
      )
  end

  strip[CENTER_POS] =
    winnerIndex

  local ok, err =
    renderStrip(strip)

  if not ok then
    return false, err
  end

  return true
end

local function spinReel(
  winnerIndex,
  winnerPrize
)
  stopIdleShowcase()

  local strip = makeStrip()

  drawStatus(
    "БАРАБАН КРУТИТСЯ...",
    C.cyan,
    "Результат уже выбран локальным RNG",
    C.gray,
    "RNG: " .. getRngMode(),
    C.darkGray
  )

  local ok, err =
    renderStrip(strip)

  if not ok then
    return false, err
  end

  local spinDuration =
    math.max(
      0.50,
      tonumber(
        RuntimeTuning.spinDuration
      ) or 2.50
    )

  local spinDelay =
    math.max(
      0.005,
      tonumber(
        RuntimeTuning.spinDelay
      ) or 0.035
    )

  local deadline =
    computer.uptime()
    + spinDuration

  while computer.uptime()
    < deadline
  do
    shiftStrip(strip)

    ok, err =
      renderStrip(strip)

    if not ok then
      return false, err
    end

    if not sleepSafe(
      spinDelay
    ) then
      return false, "quit"
    end
  end

  return forceWinnerIntoCenter(
    strip,
    winnerIndex
  )
end

local function showPendingPrizeOnSelectors(
  pending
)
  if not pending then
    return
  end

  local winnerIndex =
    PRIZE_INDEX_BY_KEY[
      tostring(
        pending.key or ""
      )
    ]

  if not winnerIndex then
    return
  end

  local strip = {}

  for pos = 1, 7 do
    strip[pos] =
      nextFillerIndex(
        winnerIndex
      )
  end

  strip[CENTER_POS] =
    winnerIndex

  renderStrip(strip)
end

delivering = false

local function exportResultSize(result)
  if type(result) == "table" then
    return tonumber(
      result.size
      or result.qty
      or result.count
      or 0
    ) or 0
  end

  return tonumber(result) or 0
end

CasinoMEExport =
  CasinoMEExport or {}

function CasinoMEExport.normalizeId(value)
  local id =
    tostring(value or "")

  id =
    id:gsub("\\:", ":")

  if id ~= ""
    and not id:find(
      ":",
      1,
      true
    )
  then
    id =
      "minecraft:"
      .. id
  end

  return id
end

function CasinoMEExport.normalizeLabel(value)
  if type(value) ~= "string"
    and type(value) ~= "number"
  then
    return ""
  end

  value =
    tostring(value or "")

  value =
    value:gsub("§.", "")

  value =
    value:gsub(
      "^%s+",
      ""
    ):gsub(
      "%s+$",
      ""
    )

  return string.lower(value)
end

function CasinoMEExport.parseCount(
  result,
  requested
)
  requested =
    math.max(
      0,
      math.floor(
        tonumber(requested) or 0
      )
    )

  if type(result) == "number" then
    return math.max(
      0,
      math.min(
        requested,
        math.floor(result)
      )
    )
  end

  if type(result) == "table" then
    return math.max(
      0,
      math.min(
        requested,
        math.floor(
          tonumber(
            result.size
            or result.count
            or result.amount
            or result.qty
            or 0
          ) or 0
        )
      )
    )
  end

  return 0
end

function CasinoMEExport.callList(
  methodName,
  details
)
  local ok, result

  if details ~= nil then
    ok, result =
      pcall(
        component.invoke,
        PRIZE_ME,
        methodName,
        details
      )
  else
    ok, result =
      pcall(
        component.invoke,
        PRIZE_ME,
        methodName
      )
  end

  if ok
    and type(result) == "table"
  then
    return result
  end

  return nil
end

function CasinoMEExport.findVariants(item)
  item =
    type(item) == "table"
    and item
    or {}

  local targetId =
    CasinoMEExport.normalizeId(
      item.id
      or item.internalName
    )

  local targetDamage =
    tonumber(
      item.dmg
      or item.damage
      or 0
    ) or 0

  local wantedHash =
    item.nbt_hash
    or item.nbtHash

  local wantedLabel =
    CasinoMEExport.normalizeLabel(
      item.itemLabel
      or item.item_label
      or ""
    )

  local variants = {}
  local seen = {}

  pcall(
    collectgarbage,
    "collect"
  )

  local networkItems =
    CasinoMEExport.callList(
      "getAvailableItems",
      "NONE"
    )

  if type(networkItems)
    ~= "table"
  then
    networkItems =
      CasinoMEExport.callList(
        "getAvailableItems"
      )
  end

  if type(networkItems)
    ~= "table"
  then
    return variants,
      "getAvailableItems_failed"
  end

  for _, entry in pairs(
    networkItems
  ) do
    if type(entry) == "table" then
      local fingerprint =
        type(entry.fingerprint)
          == "table"
        and entry.fingerprint
        or entry

      if type(fingerprint)
        == "table"
      then
        local id =
          CasinoMEExport.normalizeId(
            fingerprint.id
            or fingerprint.name
            or fingerprint.item_name
            or fingerprint.itemName
            or fingerprint.internal_name
            or fingerprint.internalName
            or entry.id
            or entry.name
            or entry.item_name
            or entry.itemName
            or entry.internal_name
            or entry.internalName
          )

        local damage =
          tonumber(
            fingerprint.dmg
            or fingerprint.damage
            or fingerprint.meta
            or fingerprint.item_damage
            or fingerprint.itemDamage
            or entry.dmg
            or entry.damage
            or entry.meta
            or entry.item_damage
            or entry.itemDamage
            or 0
          ) or 0

        local hash =
          fingerprint.nbt_hash
          or fingerprint.nbtHash
          or fingerprint.tag_hash
          or fingerprint.tagHash
          or entry.nbt_hash
          or entry.nbtHash
          or entry.tag_hash
          or entry.tagHash

        local label =
          CasinoMEExport.normalizeLabel(
            fingerprint.label
            or fingerprint.displayName
            or fingerprint.display_name
            or fingerprint.item_label
            or fingerprint.itemLabel
            or entry.label
            or entry.displayName
            or entry.display_name
            or entry.item_label
            or entry.itemLabel
            or ""
          )

        local count =
          tonumber(
            entry.size
            or entry.qty
            or entry.count
            or entry.amount
            or entry.available
            or fingerprint.size
            or fingerprint.qty
            or fingerprint.count
            or 0
          ) or 0

        local hashMatches =
          wantedHash == nil
          or wantedHash == ""
          or tostring(
            hash or ""
          ) == tostring(
            wantedHash
          )

        local labelMatches =
          wantedLabel == ""
          or label
            == wantedLabel

        if id == targetId
          and damage
            == targetDamage
          and count > 0
          and hashMatches
          and labelMatches
        then
          local uniqueKey =
            id
            .. ":"
            .. tostring(damage)
            .. ":"
            .. tostring(hash or "")
            .. ":"
            .. label

          if not seen[uniqueKey] then
            seen[uniqueKey] = true

            variants[
              #variants + 1
            ] = {
              fingerprint =
                fingerprint,

              count =
                math.max(
                  0,
                  math.floor(count)
                ),

              nbt_hash =
                hash,

              itemLabel =
                label
            }
          end
        end
      end
    end
  end

  networkItems = nil

  pcall(
    collectgarbage,
    "collect"
  )

  table.sort(
    variants,
    function(a, b)
      return (
        tonumber(a.count) or 0
      ) > (
        tonumber(b.count) or 0
      )
    end
  )

  return variants, nil
end

function CasinoMEExport.invokeExport(
  fingerprint,
  amount
)
  local ok, result =
    pcall(
      component.invoke,
      PRIZE_ME,
      "exportItem",
      fingerprint,
      PRIZE_ME_DIRECTION,
      amount
    )

  if not ok then
    return 0,
      tostring(result)
  end

  return
    CasinoMEExport.parseCount(
      result,
      amount
    ),
    nil
end

function CasinoMEExport.export(
  item,
  qty
)
  qty =
    math.max(
      0,
      math.floor(
        tonumber(qty) or 0
      )
    )

  if qty <= 0 then
    return 0,
      "invalid_qty"
  end

  local variants, findError =
    CasinoMEExport.findVariants(
      item
    )

  if #variants <= 0 then
    return 0,
      findError
      or "raw_fingerprint_not_found"
  end

  local remaining = qty
  local extracted = 0

  for _, variant in ipairs(
    variants
  ) do
    local available =
      math.max(
        0,
        math.floor(
          tonumber(
            variant.count
          ) or 0
        )
      )

    while remaining > 0
      and available > 0
    do
      local toTake =
        math.min(
          remaining,
          available,
          64
        )

      local moved, exportError =
        CasinoMEExport.invokeExport(
          variant.fingerprint,
          toTake
        )

      moved =
        math.max(
          0,
          math.min(
            toTake,
            available,
            math.floor(
              tonumber(moved) or 0
            )
          )
        )

      if moved <= 0 then
        if extracted <= 0 then
          return 0,
            exportError
            or "raw_export_failed"
        end

        break
      end

      extracted =
        extracted + moved

      remaining =
        remaining - moved

      available =
        available - moved
    end

    if remaining <= 0 then
      break
    end
  end

  if extracted <= 0 then
    return 0,
      "nothing_exported"
  end

  return extracted, nil
end

CasinoStock =
  CasinoStock or {
    closed = false,
    initialized = false,
    missing = {},
    missingCount = 0,
    reason = "",
    lastError = nil,
    nextCheckAt = 0,
    lastCheckAt = 0
  }

STOCK_ENABLED =
  STOCK.enabled ~= false

STOCK_REQUIRED_MODE =
  tostring(
    STOCK.requiredQtyMode
    or "max"
  )

STOCK_CHECK_INTERVAL =
  math.max(
    1.0,
    tonumber(
      STOCK.checkInterval
    ) or 3.0
  )

function casinoStockRequiredQty(
  prize
)
  if STOCK_REQUIRED_MODE == "min" then
    return math.max(
      1,
      math.floor(
        tonumber(
          prize.qtyMin
        ) or 1
      )
    )
  end

  return math.max(
    1,
    math.floor(
      tonumber(
        prize.qtyMax
      )
      or tonumber(
        prize.qtyMin
      )
      or 1
    )
  )
end

function casinoStockEntryInfo(entry)
  if type(entry) ~= "table" then
    return nil
  end

  local fingerprint =
    type(entry.fingerprint)
      == "table"
    and entry.fingerprint
    or entry

  if type(fingerprint)
    ~= "table"
  then
    return nil
  end

  local id =
    CasinoMEExport.normalizeId(
      fingerprint.id
      or fingerprint.name
      or fingerprint.item_name
      or fingerprint.itemName
      or fingerprint.internal_name
      or fingerprint.internalName
      or entry.id
      or entry.name
      or entry.item_name
      or entry.itemName
      or entry.internal_name
      or entry.internalName
    )

  local damage =
    tonumber(
      fingerprint.dmg
      or fingerprint.damage
      or fingerprint.meta
      or fingerprint.item_damage
      or fingerprint.itemDamage
      or entry.dmg
      or entry.damage
      or entry.meta
      or entry.item_damage
      or entry.itemDamage
      or 0
    ) or 0

  local hash =
    fingerprint.nbt_hash
    or fingerprint.nbtHash
    or fingerprint.tag_hash
    or fingerprint.tagHash
    or entry.nbt_hash
    or entry.nbtHash
    or entry.tag_hash
    or entry.tagHash

  local label =
    CasinoMEExport.normalizeLabel(
      fingerprint.label
      or fingerprint.displayName
      or fingerprint.display_name
      or fingerprint.item_label
      or fingerprint.itemLabel
      or entry.label
      or entry.displayName
      or entry.display_name
      or entry.item_label
      or entry.itemLabel
      or ""
    )

  local count =
    tonumber(
      entry.size
      or entry.qty
      or entry.count
      or entry.amount
      or entry.available
      or fingerprint.size
      or fingerprint.qty
      or fingerprint.count
      or fingerprint.amount
      or fingerprint.available
      or 0
    ) or 0

  return {
    id = id,
    damage = damage,
    hash = hash,
    label = label,
    count = math.max(
      0,
      math.floor(count)
    )
  }
end

function casinoStockCountPrize(
  networkItems,
  prize
)
  if type(networkItems) ~= "table"
    or type(prize) ~= "table"
    or type(prize.item) ~= "table"
  then
    return 0
  end

  local item = prize.item

  local targetId =
    CasinoMEExport.normalizeId(
      item.id
      or item.internalName
      or ""
    )

  local targetDamage =
    tonumber(
      item.dmg
      or item.damage
      or 0
    ) or 0

  local wantedHash =
    item.nbt_hash
    or item.nbtHash

  local wantedLabel =
    CasinoMEExport.normalizeLabel(
      item.itemLabel
      or item.item_label
      or ""
    )

  local total = 0

  for _, entry in pairs(
    networkItems
  ) do
    local info =
      casinoStockEntryInfo(entry)

    if info then
      local hashMatches =
        wantedHash == nil
        or wantedHash == ""
        or tostring(
          info.hash or ""
        ) == tostring(
          wantedHash
        )

      local labelMatches =
        wantedLabel == ""
        or info.label
          == wantedLabel

      if info.id == targetId
        and info.damage
          == targetDamage
        and hashMatches
        and labelMatches
      then
        total = total + info.count
      end
    end
  end

  return math.max(
    0,
    math.floor(total)
  )
end

function casinoStockApplyState(
  closed,
  missing,
  reason
)
  local wasClosed =
    CasinoStock.closed

  CasinoStock.closed =
    closed == true

  CasinoStock.missing =
    type(missing) == "table"
    and missing
    or {}

  CasinoStock.missingCount =
    #CasinoStock.missing

  CasinoStock.reason =
    tostring(reason or "")

  CasinoStock.initialized = true

  if CasinoStock.closed then
    stopIdleShowcase()
    clearSelectors()
    lastUiKey = nil
  elseif wasClosed then
    resetIdleShowcase()
    lastUiKey = nil
  end
end

function casinoStockCheckNow()
  if not STOCK_ENABLED then
    casinoStockApplyState(
      false,
      {},
      "disabled"
    )
    return true
  end

  sendTerminalHeartbeat()

  pcall(
    collectgarbage,
    "collect"
  )

  local networkItems =
    CasinoMEExport.callList(
      "getAvailableItems",
      "NONE"
    )

  if type(networkItems)
    ~= "table"
  then
    networkItems =
      CasinoMEExport.callList(
        "getAvailableItems"
      )
  end

  sendTerminalHeartbeat()

  if type(networkItems)
    ~= "table"
  then
    CasinoStock.lastError =
      "getAvailableItems_failed"

    casinoStockApplyState(
      true,
      {},
      "ME_READ_FAILED"
    )

    return false
  end

  local missing = {}

  for index, prize in ipairs(
    PRIZES
  ) do
    local required =
      casinoStockRequiredQty(
        prize
      )

    local available =
      casinoStockCountPrize(
        networkItems,
        prize
      )

    if available < required then
      missing[
        #missing + 1
      ] = {
        index = index,
        key = prize.key,
        name = prize.name,
        available = available,
        required = required
      }
    end
  end

  networkItems = nil

  pcall(
    collectgarbage,
    "collect"
  )

  if #missing > 0 then
    casinoStockApplyState(
      true,
      missing,
      "MISSING_PRIZES"
    )

    return false
  end

  CasinoStock.lastError = nil

  casinoStockApplyState(
    false,
    {},
    ""
  )

  return true
end

function casinoStockTick(now)
  if not STOCK_ENABLED then
    if not CasinoStock.initialized
      or CasinoStock.closed
    then
      casinoStockApplyState(
        false,
        {},
        "disabled"
      )
    end
    return
  end

  if gameBusy
    or PendingViewer.open
    or CasinoHouse.statusPopupOpen
  then
    return
  end

  now =
    tonumber(now)
    or computer.uptime()

  if now
    < CasinoStock.nextCheckAt
  then
    return
  end

  CasinoStock.nextCheckAt =
    now + STOCK_CHECK_INTERVAL

  CasinoStock.lastCheckAt = now

  local ok, err =
    pcall(
      casinoStockCheckNow
    )

  if not ok then
    CasinoStock.lastError =
      tostring(err)

    casinoStockApplyState(
      true,
      {},
      "STOCK_CHECK_ERROR"
    )
  end
end

function casinoStockClosed()
  return STOCK_ENABLED
    and CasinoStock.initialized
    and CasinoStock.closed
end


PendingDelivery =
  PendingDelivery or {
    active = false,
    prizeId = nil,
    player = nil,
    before = nil,
    exported = 0,
    expected = 0,
    startedAt = 0
  }

function pendingDeliveryReset()
  PendingDelivery.active = false
  PendingDelivery.prizeId = nil
  PendingDelivery.player = nil
  PendingDelivery.before = nil
  PendingDelivery.exported = 0
  PendingDelivery.expected = 0
  PendingDelivery.startedAt = 0
end

function findPendingById(id)
  id = tostring(id or "")

  if id == "" then
    return nil
  end

  for _, prize in ipairs(
    pendingPrizes
  ) do
    if tostring(prize.id or "")
      == id
    then
      return prize
    end
  end

  return nil
end

function recoverUncertainPendingStep(player)
  if not player then
    return false, "no_player"
  end

  local prize =
    findUncertainPendingForPlayer(
      player
    )

  if not prize then
    return false,
      "no_uncertain_for_player"
  end

  local currentPlayer =
    getPlayerOnPim()

  if not currentPlayer
    or not samePlayerName(
      currentPlayer,
      prize.player
    )
  then
    return false, "wrong_player"
  end

  local qty =
    math.max(
      1,
      math.floor(
        tonumber(prize.qty) or 1
      )
    )

  local exported =
    math.max(
      0,
      math.floor(
        tonumber(prize.exported) or 0
      )
    )

  local before =
    tonumber(prize.before)

  local currentCount =
    countItemOnPim(
      prize.item
    )

  local confirmedByInventory = 0

  if before ~= nil
    and currentCount ~= nil
  then
    confirmedByInventory =
      math.max(
        0,
        math.floor(
          currentCount - before
        )
      )
  end

  local delivered =
    math.min(
      qty,
      math.max(
        exported,
        confirmedByInventory
      )
    )

  if delivered >= qty then
    removePendingById(
      prize.id
    )

    lastUiKey = nil

    return true,
      "already_exported"
  end

  if delivered > 0 then
    prize.qty =
      qty - delivered

    prize.deliveredTotal =
      (
        tonumber(
          prize.deliveredTotal
        ) or 0
      )
      + delivered
  end

  prize.status =
    "waiting_claim"

  prize.exported = nil
  prize.before = nil
  prize.after = nil
  prize.lastError = nil

  savePending()
  lastUiKey = nil

  return false,
    "resume_waiting_claim"
end

function pendingDeliveryBegin(player)
  if PendingDelivery.active
    or gameBusy
    or not player
  then
    return false, "not_ready"
  end

  local prize =
    findWaitingPendingForPlayer(
      player
    )

  if not prize then
    return false,
      "no_pending_for_player"
  end

  local now =
    computer.uptime()

  local lastAttempt =
    tonumber(
      prize.lastDeliveryAttempt
    ) or 0

  if lastAttempt > 0
    and now - lastAttempt
      < PENDING_RETRY_INTERVAL
  then
    return false,
      "retry_cooldown"
  end

  local currentPlayer =
    getPlayerOnPim()

  if not currentPlayer
    or not samePlayerName(
      currentPlayer,
      prize.player
    )
  then
    return false, "wrong_player"
  end

  local before =
    countItemOnPim(
      prize.item
    )

  if before == nil then
    prize.lastDeliveryAttempt = now
    prize.lastError =
      "inventory_read_failed"

    savePending()

    return false,
      "inventory_read_failed"
  end

  prize.lastDeliveryAttempt = now
  prize.status = "delivering"
  prize.before = before
  prize.exported = nil
  prize.after = nil
  prize.lastError = nil

  savePending()

  local exported,
        exportError =
    CasinoMEExport.export(
      prize.item,
      prize.qty
    )

  exported =
    math.max(
      0,
      math.floor(
        tonumber(exported) or 0
      )
    )

  if exported <= 0 then
    prize.status =
      "waiting_claim"

    prize.before = nil
    prize.exported = nil

    prize.lastError =
      tostring(
        exportError
        or "raw_export_failed"
      )

    savePending()
    lastUiKey = nil

    return false,
      "export_error:"
      .. tostring(
        exportError
        or "raw_export_failed"
      )
  end

  prize.exported = exported

  PendingDelivery.active = true
  PendingDelivery.prizeId =
    tostring(prize.id)
  PendingDelivery.player =
    tostring(prize.player)
  PendingDelivery.before = before
  PendingDelivery.exported =
    exported
  PendingDelivery.expected =
    math.min(
      exported,
      math.max(
        1,
        math.floor(
          tonumber(prize.qty) or 1
        )
      )
    )
  PendingDelivery.startedAt =
    computer.uptime()

  savePending()

  return true, "confirming"
end

function pendingDeliveryConfirmStep()
  if not PendingDelivery.active then
    return false, "idle"
  end

  local prize =
    findPendingById(
      PendingDelivery.prizeId
    )

  if not prize then
    pendingDeliveryReset()
    return true, "already_removed"
  end

  local currentPlayer =
    getPlayerOnPim()

  if not currentPlayer
    or not samePlayerName(
      currentPlayer,
      PendingDelivery.player
    )
  then
    prize.status =
      "delivery_uncertain"

    prize.exported =
      PendingDelivery.exported

    prize.before =
      PendingDelivery.before

    prize.lastError =
      "player_left_during_delivery"

    savePending()
    pendingDeliveryReset()
    lastUiKey = nil

    return false,
      "player_left_during_delivery"
  end

  local after =
    countItemOnPim(
      prize.item
    )

  if after ~= nil then
    local diff =
      math.max(
        0,
        math.floor(
          after
          - (
              tonumber(
                PendingDelivery.before
              ) or 0
            )
        )
      )

    prize.after = after

    if diff
      >= PendingDelivery.expected
    then
      local qty =
        math.max(
          1,
          math.floor(
            tonumber(prize.qty) or 1
          )
        )

      local deliveredNow =
        math.min(
          qty,
          PendingDelivery.expected
        )

      if deliveredNow >= qty then
        removePendingById(
          prize.id
        )
      else
        prize.qty =
          qty - deliveredNow

        prize.deliveredTotal =
          (
            tonumber(
              prize.deliveredTotal
            ) or 0
          )
          + deliveredNow

        prize.status =
          "waiting_claim"

        prize.exported = nil
        prize.before = nil
        prize.after = nil
        prize.lastError = nil

        savePending()
      end

      pendingDeliveryReset()
      lastUiKey = nil

      return true, "delivered"
    end
  end

  if computer.uptime()
    - PendingDelivery.startedAt
    >= DELIVERY_CONFIRM_TIMEOUT
  then
    prize.status =
      "delivery_uncertain"

    prize.exported =
      PendingDelivery.exported

    prize.before =
      PendingDelivery.before

    prize.lastError =
      "confirm_timeout"

    savePending()
    pendingDeliveryReset()
    lastUiKey = nil

    return false,
      "delivery_uncertain"
  end

  return false, "confirming"
end

function tickPendingDelivery(player)
  if casinoStockClosed()
    or gameBusy
    or PendingViewer.open
    or CasinoHouse.statusPopupOpen
  then
    return false, "paused"
  end

  if PendingDelivery.active then
    return pendingDeliveryConfirmStep()
  end

  if not player then
    return false, "no_player"
  end

  local uncertain =
    findUncertainPendingForPlayer(
      player
    )

  if uncertain then
    recoverUncertainPendingStep(
      player
    )
  end

  if gameBusy then
    return false, "game_started"
  end

  return pendingDeliveryBegin(
    player
  )
end

local function validateHardware()
  if #PRIZES < 1 then
    return false,
      "Каталог призов пуст"
  end

  if cursor ~= RANDOM_SCALE then
    return false,
      "Ошибка диапазонов RNG"
  end

  if not validatePim() then
    return false,
      "Prize PIM не найден"
  end

  if component.type(PRIZE_ME)
    ~= "me_interface"
  then
    return false,
      "Prize ME Interface не найден"
  end

  local selectorOk, selectorErr =
    validateSelectors()

  if not selectorOk then
    return false, selectorErr
  end

  if TERMINAL_ENABLED then
    if TERMINAL_MODEM_ADDRESS == "" then
      return false,
        "Не указан modem кассового терминала в casino_config.lua"
    end

    if not jackpotModem then
      return false,
        "Wireless modem казино не найден"
    end
  end

  return true
end

local gameBusy = false

local lastUiKey = nil

local function uiKey(...)
  local values = {...}
  local parts = {}

  for i = 1, #values do
    parts[#parts + 1] =
      tostring(values[i])
  end

  return table.concat(
    parts,
    "|"
  )
end

local function drawRuntimeHeader(
  player,
  betCount,
  totalPending
)
  local playerText =
    player
    and tostring(player)
    or "---"

  local left =
    "ИГРОК: "
    .. playerText

  local middle =
    "MONEY: "
    .. tostring(
      tonumber(betCount) or 0
    )
    .. "/"
    .. tostring(BET_AMOUNT)

  local right =
    "[ НЕВЫДАННЫЕ ПРИЗЫ: "
    .. tostring(
      tonumber(totalPending) or 0
    )
    .. " ]"

  fill(
    3,
    5,
    W - 4,
    1,
    C.bg
  )

  text(
    4,
    5,
    left,
    player and C.green or C.gray,
    C.bg
  )

  center(
    5,
    middle,
    (
      tonumber(betCount) or 0
    ) >= BET_AMOUNT
      and C.green
      or C.gold
  )

  text(
    math.max(
      3,
      W
        - unicode.len(right)
        - 3
    ),
    5,
    right,
    (
      tonumber(totalPending) or 0
    ) > 0
      and C.gold
      or C.gray,
    C.bg
  )

  drawSessionStatus(
    player,
    betCount,
    totalPending
  )

  drawBottomFooter(player)
end

function getHiddenStatusButton()
  local label = "[ СИСТЕМА ]"
  local w = unicode.len(label)

  return {
    label = label,
    x = math.max(
      6,
      W - w - 6
    ),
    y = SYSTEM_PANEL_Y
      + SYSTEM_PANEL_H
      - 2,
    w = w
  }
end

function hiddenStatusPopupGeometry()
  local boxW =
    math.min(
      58,
      W - 10
    )

  local boxH =
    math.min(
      21,
      H - 8
    )

  local boxX =
    math.floor(
      (W - boxW) / 2
    ) + 1

  local boxY =
    math.floor(
      (H - boxH) / 2
    ) + 1

  return boxX,
    boxY,
    boxW,
    boxH
end

function makeStatusButton(
  label,
  x,
  y
)
  return {
    label = label,
    x = x,
    y = y,
    w = unicode.len(label)
  }
end

function getHiddenStatusButtons()
  local boxX,
    boxY,
    boxW,
    boxH =
      hiddenStatusPopupGeometry()

  local minus100 =
    makeStatusButton(
      "[ -100 ]",
      boxX + 5,
      boxY + 11
    )

  local minus10 =
    makeStatusButton(
      "[ -10 ]",
      minus100.x
        + minus100.w
        + 2,
      boxY + 11
    )

  local plus10 =
    makeStatusButton(
      "[ +10 ]",
      minus10.x
        + minus10.w
        + 2,
      boxY + 11
    )

  local plus100 =
    makeStatusButton(
      "[ +100 ]",
      plus10.x
        + plus10.w
        + 2,
      boxY + 11
    )

  local saveLabel =
    "[ СОХРАНИТЬ ]"

  local save =
    makeStatusButton(
      saveLabel,
      boxX
        + math.floor(
            (
              boxW
              - unicode.len(saveLabel)
            ) / 2
          ),
      boxY + 14
    )

  local closeLabel =
    "[ ЗАКРЫТЬ ]"

  local close =
    makeStatusButton(
      closeLabel,
      boxX
        + math.floor(
            (
              boxW
              - unicode.len(closeLabel)
            ) / 2
          ),
      boxY + boxH - 2
    )

  return {
    minus100 = minus100,
    minus10 = minus10,
    plus10 = plus10,
    plus100 = plus100,
    save = save,
    close = close
  }
end

function casinoHouseSetDraftLimit(
  delta
)
  local current =
    math.max(
      1,
      math.floor(
        tonumber(
          CasinoHouse.editStaffEvery
        )
        or CasinoHouse.staffEvery
      )
    )

  CasinoHouse.editStaffEvery =
    math.max(
      1,
      math.min(
        1000000,
        current
          + math.floor(
              tonumber(delta)
              or 0
            )
      )
    )

  CasinoHouse.statusMessage = ""
  CasinoHouse.statusPopupDirty = true
end

function casinoHouseSaveDraftLimit()
  local newLimit =
    math.max(
      1,
      math.min(
        1000000,
        math.floor(
          tonumber(
            CasinoHouse.editStaffEvery
          )
          or CasinoHouse.staffEvery
        )
      )
    )

  CasinoHouse.staffEvery =
    newLimit

  CasinoHouse.stats.staffEvery =
    newLimit

  local ok, err =
    casinoHouseSaveStats()

  if ok then
    CasinoHouse.statusMessage =
      "ЛИМИТ СОХРАНЁН"
  else
    CasinoHouse.statusMessage =
      "ОШИБКА СОХРАНЕНИЯ: "
      .. tostring(err or "?")
  end

  CasinoHouse.statusPopupDirty = true
end

function drawHiddenStatusPopup()
  return
end

function hiddenStatusHit(
  ev,
  button
)
  if type(ev) ~= "table"
    or ev[1] ~= "touch"
    or type(button) ~= "table"
  then
    return false
  end

  local x = tonumber(ev[3])
  local y = tonumber(ev[4])

  if not x or not y then
    return false
  end

  return y == button.y
    and x >= button.x
    and x < button.x + button.w
end

function handleHiddenStatusTouch(ev)
  if type(SystemAdmin) == "table"
    and SystemAdmin.open == true
  then
    if type(SystemAdmin.handleEvent)
      == "function"
    then
      return SystemAdmin.handleEvent(ev)
    end

    return SystemAdmin.handleTouch(ev)
  end

  local button =
    getHiddenStatusButton()

  if hiddenStatusHit(ev, button) then
    if type(SystemAdmin) == "table"
      and type(SystemAdmin.openScreen)
        == "function"
    then
      return SystemAdmin.openScreen()
    end

    return true
  end

  return false
end

function drawCasinoStockClosed()
  if gameBusy then
    return
  end

  clearInfo()

  center(
    INFO_Y + 1,
    "КАЗИНО ВРЕМЕННО ЗАКРЫТО",
    C.red
  )

  center(
    INFO_Y + 3,
    "НЕДОСТАТОЧНО ПРИЗОВ В МЭ",
    C.yellow
  )

  local firstMissing =
    CasinoStock.missing
    and CasinoStock.missing[1]
    or nil

  if CasinoStock.reason == "ME_READ_FAILED"
    or CasinoStock.reason == "STOCK_CHECK_ERROR"
    or CasinoStock.reason == "STOCK_TICK_ERROR"
  then
    center(
      INFO_Y + 5,
      "ОШИБКА ПРОВЕРКИ МЭ",
      C.red
    )
  else
    center(
      INFO_Y + 5,
      "ОТСУТСТВУЕТ ПОЗИЦИЙ: "
        .. tostring(
          CasinoStock.missingCount
        ),
      C.white
    )
  end

  if firstMissing then
    center(
      INFO_Y + 7,
      "ПРИЗ: "
        .. tostring(
          firstMissing.name
          or firstMissing.key
          or "НЕИЗВЕСТНЫЙ ПРИЗ"
        ),
      C.yellow
    )

    local prize =
      PRIZES[
        tonumber(
          firstMissing.index
        ) or 0
      ]

    if prize
      and type(prize.item) == "table"
      and tostring(
        prize.item.id
        or ""
      ) ~= ""
    then
      center(
        INFO_Y + 8,
        "ID: "
          .. tostring(
            prize.item.id
          ),
        C.gray
      )
    end

    center(
      INFO_Y + 10,
      "В МЭ: "
        .. tostring(
          firstMissing.available
          or 0
        )
        .. "   НУЖНО: "
        .. tostring(
          firstMissing.required
          or 1
        ),
      C.white
    )
  end

  center(
    INFO_Y + 12,
    "ПОПОЛНИТЕ МЭ — КАЗИНО ОТКРОЕТСЯ АВТОМАТИЧЕСКИ",
    C.gray
  )
end

local function drawSystemInfo()
  if SYSTEM_PANEL_Y
    + SYSTEM_PANEL_H
    > H
  then
    return
  end

  fill(
    5,
    SYSTEM_PANEL_Y + 2,
    W - 8,
    math.max(
      1,
      SYSTEM_PANEL_H - 4
    ),
    C.panel
  )

  local meOnline =
    component.type(PRIZE_ME)
      == "me_interface"

  local pimOnline =
    component.type(PRIZE_PIM)
      == "pim"

  local selectorsOnline = 0

  for pos = 1, 7 do
    if component.type(
      SELECTORS[pos]
    ) == "openperipheral_selector"
    then
      selectorsOnline =
        selectorsOnline + 1
    end
  end

  local boardOnline =
    component.type(
      CASINO_MODEM_ADDRESS
    ) == "modem"

  local y =
    SYSTEM_PANEL_Y + 2

  local left1 =
    "ME: "
    .. (
      meOnline
      and "ONLINE"
      or "OFFLINE"
    )

  local left2 =
    "PIM: "
    .. (
      pimOnline
      and "ONLINE"
      or "OFFLINE"
    )

  local middle1 =
    "SELECTOR: "
    .. tostring(selectorsOnline)
    .. "/7"

  local middle2 =
    "КАССА: "
    .. tostring(
      CasinoHouse.stats.totalMoney
      or 0
    )
    .. " MONEY"
    .. "  •  ИГР: "
    .. tostring(
      CasinoHouse.stats.totalSpins
      or 0
    )
    .. "  •  ИГРОКОВ: "
    .. tostring(
      CasinoHouse.stats.uniquePlayers
      or 0
    )

  local right1 =
    "ТАБЛО: "
    .. (
      boardOnline
      and "ONLINE"
      or "OFFLINE"
    )

  local right2 =
    "ВЫДАЧА: ME -> PIM"

  text(
    6,
    y,
    left1,
    meOnline and C.green or C.red,
    C.panel
  )

  text(
    6,
    y + 1,
    left2,
    pimOnline and C.green or C.red,
    C.panel
  )

  center(
    y,
    middle1,
    selectorsOnline == 7
      and C.green
      or C.yellow
  )

  center(
    y + 1,
    middle2,
    C.gold
  )

  text(
    math.max(
      6,
      W
        - unicode.len(right1)
        - 6
    ),
    y,
    right1,
    boardOnline and C.green or C.yellow,
    C.panel
  )

  text(
    math.max(
      6,
      W
        - unicode.len(right2)
        - 6
    ),
    y + 1,
    right2,
    C.white,
    C.panel
  )

  if SYSTEM_PANEL_H >= 7 then
    text(
      6,
      y + 3,
      "ПРИЗЫ: "
        .. tostring(#PRIZES)
        .. "  •  СТАВКА: "
        .. tostring(BET_AMOUNT)
        .. "  •  RNG: ACTIVE",
      C.darkGray,
      C.panel
    )
  end

  drawClearWinnerButton()
  local hiddenStatus =
    getHiddenStatusButton()

  text(
    hiddenStatus.x,
    hiddenStatus.y,
    hiddenStatus.label,
    C.darkGray,
    C.panel
  )

end

local function updateWaitingUi(
  preparedPlayer,
  preparedBetCount
)
  if gameBusy then
    return
  end

  local player =
    preparedPlayer

  if player == nil then
    player =
      getPlayerOnPim()
  end

  local betCount =
    tonumber(
      preparedBetCount
    )

  if betCount == nil then
    betCount =
      player
      and scanPlayerBetMoney()
      or 0
  end

  local totalPending =
    countPendingTotal()

  drawRuntimeHeader(
    player,
    betCount,
    totalPending
  )

  drawSystemInfo()

  if not player then
    local key =
      uiKey(
        "no_player",
        betCount,
        totalPending
      )

    if key == lastUiKey then
      return
    end

    lastUiKey = key

    drawStatus(
      "PIM: СВОБОДЕН",
      C.gray,
      "СЕССИЯ: НЕТ АКТИВНОГО ИГРОКА",
      C.white,
      "СТАВКА: "
        .. tostring(betCount)
        .. " / "
        .. tostring(BET_AMOUNT)
        .. " ДЕНЕГ",
      betCount >= BET_AMOUNT
        and C.yellow
        or C.gray,
      "ВИТРИНА: ACTIVE  •  ОЖИДАЮЩИХ ПРИЗОВ: "
        .. tostring(totalPending),
      totalPending > 0
        and C.gold
        or C.darkGray
    )

    return
  end

  local ownWaiting =
    findWaitingPendingForPlayer(player)

  if ownWaiting then
    local key =
      uiKey(
        "own_pending",
        player,
        ownWaiting.id,
        countPendingForPlayer(player)
      )

    if key == lastUiKey then
      return
    end

    lastUiKey = key

    drawStatus(
      "PIM: ЗАНЯТ  •  ПРИЗ ОЖИДАЕТ ВЫДАЧИ",
      C.gold,
      "ИГРОК: "
        .. tostring(player),
      C.cyan,
      tostring(ownWaiting.label)
        .. " x"
        .. tostring(ownWaiting.qty),
      C.green,
      "ВЫДАЧА: АВТОМАТИЧЕСКАЯ  •  ИГРУ НЕ БЛОКИРУЕТ",
      C.yellow
    )

    return
  end

  local uncertain =
    findUncertainPendingForPlayer(player)

  if uncertain then
    local key =
      uiKey(
        "uncertain",
        player,
        uncertain.id,
        betCount
      )

    if key == lastUiKey then
      return
    end

    lastUiKey = key

    drawStatus(
      "КОНТРОЛЬ ВЫДАЧИ: ТРЕБУЕТ ПРОВЕРКИ",
      C.red,
      "ИГРОК: "
        .. tostring(player),
      C.white,
      tostring(uncertain.label)
        .. " x"
        .. tostring(uncertain.qty),
      C.yellow,
      "ИГРЫ: РАЗРЕШЕНЫ  •  СТАВКА: "
        .. tostring(betCount)
        .. " / "
        .. tostring(BET_AMOUNT),
      C.green
    )

    return
  end

  local key =
    uiKey(
      "waiting_bet",
      player,
      betCount,
      totalPending
    )

  if key == lastUiKey then
    return
  end

  lastUiKey = key

  drawStatus(
    "PIM: ЗАНЯТ",
    C.green,
    "ИГРОК: "
      .. tostring(player),
    C.cyan,
    "MONEY В ИНВЕНТАРЕ: "
      .. tostring(betCount)
      .. "  •  СТАВКА: "
      .. tostring(BET_AMOUNT),
    betCount >= BET_AMOUNT
      and C.green
      or C.yellow,
    "КАССА: ОЖИДАНИЕ ЗАПРОСА С ТЕРМИНАЛА"
      .. "  •  ОЖИДАЮЩИХ ПРИЗОВ: "
      .. tostring(totalPending),
    C.gray
  )
end

function casinoTerminalStatePack()
  local busy =
    gameBusy and "1" or "0"

  local closed =
    casinoStockClosed()
    and "1"
    or "0"

  local missing =
    tostring(
      math.max(
        0,
        math.floor(
          tonumber(
            CasinoStock.missingCount
          ) or 0
        )
      )
    )

  local reason =
    tostring(
      CasinoStock.reason
      or ""
    )

  local first =
    CasinoStock.missing
    and CasinoStock.missing[1]
    or nil

  local missingName = ""
  local missingId = ""
  local available = "0"
  local required = "0"

  if first then
    missingName =
      tostring(
        first.name
        or first.key
        or ""
      )

    local prize =
      PRIZES[
        tonumber(
          first.index
        ) or 0
      ]

    if prize
      and type(prize.item) == "table"
    then
      missingId =
        tostring(
          prize.item.id
          or ""
        )
    end

    available =
      tostring(
        math.max(
          0,
          math.floor(
            tonumber(
              first.available
            ) or 0
          )
        )
      )

    required =
      tostring(
        math.max(
          0,
          math.floor(
            tonumber(
              first.required
            ) or 0
          )
        )
      )
  end

  local function clean(value)
    value =
      tostring(value or "")

    value =
      value:gsub(
        "[\r\n|]",
        " "
      )

    return value
  end

  return clean(busy)
    .. "|"
    .. clean(closed)
    .. "|"
    .. clean(missing)
    .. "|"
    .. clean(reason)
    .. "|"
    .. clean(missingName)
    .. "|"
    .. clean(missingId)
    .. "|"
    .. clean(available)
    .. "|"
    .. clean(required)
end

local directTerminalSend

local function startGameFor(
  player,
  terminalRequestId,
  spinInfo
)
  if gameBusy then
    return false,
      "busy"
  end

  stopIdleShowcase()
  gameBusy = true
  lastUiKey = nil

  drawStatus(
    "СТАВКА ПРИНЯТА",
    C.green,
    "ИГРОК: "
      .. tostring(player),
    C.white,
    tostring(BET_AMOUNT)
      .. " Money списано через PIM",
    C.cyan,
    "Определяю результат...",
    C.gray
  )

  local winner,
    winnerIndex,
    winnerQty,
    winnerRoll,
    rngErr =
      chooseLocalPrize(
        player,

        type(spinInfo) == "table"
          and spinInfo.forceStaff
          == true,

        type(spinInfo) == "table"
          and spinInfo.forcePowerSeal
          == true
      )

  if not winner then

    drawStatus(
      "КРИТИЧЕСКАЯ ОШИБКА RNG",
      C.red,
      tostring(rngErr),
      C.yellow,
      "Ставка уже принята. Остановите казино.",
      C.white
    )

    gameBusy = false
    return
  end

  local pendingItem = {
    id = winner.item.id,
    dmg = winner.item.dmg or 0
  }

  if winner.item.itemLabel then
    pendingItem.itemLabel =
      winner.item.itemLabel
  end

  if winner.item.nbt_hash then
    pendingItem.nbt_hash =
      winner.item.nbt_hash
  end

  local gamePrize,
    pendingErr =
    addPending({
      player =
        tostring(player),

      key =
        winner.key,

      label =
        winner.label,

      category =
        winner.category,

      chance =
        winner.chance,

      roll =
        winnerRoll,

      randomScale =
        RANDOM_SCALE,

      rngMode =
        getRngMode(),

      item =
        pendingItem,

      qty =
        winnerQty,

      originalQty =
        winnerQty,

      status =
        "spinning",

      createdUptime =
        computer.uptime(),

      paidSpin =
        type(spinInfo) == "table"
        and spinInfo.totalSpin
        or nil,

      jackpotCycleSpin =
        type(spinInfo) == "table"
        and spinInfo.cycleSpin
        or nil,

      powerSealCycleSpin =
        type(spinInfo) == "table"
        and spinInfo.powerSealCycleSpin
        or nil,

      specialCycleSpin =
        type(spinInfo) == "table"
        and spinInfo.cycleSpin
        or nil,

      specialDue =
        type(spinInfo) == "table"
        and spinInfo.specialDue
        or nil
    })

  if not gamePrize then
    drawStatus(
      "КРИТИЧЕСКАЯ ОШИБКА PENDING",
      C.red,
      "Приз НЕ записан на диск",
      C.yellow,
      tostring(
        pendingErr
        or "unknown"
      ),
      C.white,
      "Счётчик особого приза НЕ сброшен",
      C.green
    )

    gameBusy = false

    return false,
      "pending_save_failed"
  end

  if type(spinInfo) == "table"
    and spinInfo.forceStaff == true
    and winnerIndex
      == CasinoHouse.staffIndex
  then
    casinoHouseFinalizeStaff()
  end

  if type(spinInfo) == "table"
    and spinInfo.forcePowerSeal == true
    and winnerIndex
      == CasinoHouse.powerSealIndex
  then
    casinoHouseFinalizePowerSeal()
  end

  if isJackpotPrize(gamePrize) then
    local boardOk, boardInfo =
      sendJackpotToBoard(
        gamePrize
      )

    gamePrize.jackpotBoardLastAttempt =
      computer.uptime()

    if boardOk then
      gamePrize.jackpotBoardSent =
        true

      gamePrize.jackpotBoardMessageId =
        tostring(
          boardInfo or ""
        )

      gamePrize.jackpotBoardLastError =
        nil
    else
      gamePrize.jackpotBoardSent =
        false

      gamePrize.jackpotBoardLastError =
        tostring(
          boardInfo or "unknown"
        )
    end

    savePending()
  end

  drawStatus(
    "СТАВКА ПРИНЯТА",
    C.green,
    tostring(BET_AMOUNT)
      .. " Money списано с игрока",
    C.white,
    "Запускаю барабан...",
    C.cyan,
    "RNG: "
      .. getRngMode(),
    C.darkGray
  )

  sleepSafe(AFTER_BET_ACCEPTED)

  local spinOk, spinErr =
    spinReel(
      winnerIndex,
      winner
    )

  if quitRequested then
    gamePrize.status =
      "waiting_claim"

    savePending()

    gameBusy = false

    return
  end

  if not spinOk then
    gamePrize.status =
      "waiting_claim"

    gamePrize.spinError =
      tostring(spinErr)

    savePending()

    showPendingPrizeOnSelectors(
      gamePrize
    )

    drawStatus(
      "ОШИБКА АНИМАЦИИ",
      C.red,
      "Оплаченный приз сохранён",
      C.yellow,
      tostring(winner.label)
        .. " x"
        .. tostring(winnerQty),
      C.green,
      "Другие игроки могут продолжать играть",
      C.white
    )

    gameBusy = false

    return
  end

  gamePrize.status =
    "waiting_claim"

  savePending()

  showPendingPrizeOnSelectors(
    gamePrize
  )

  drawStatus(
    "★ ВЫ ВЫИГРАЛИ ★",
    C.gold,
    tostring(winner.label)
      .. " x"
      .. tostring(winnerQty),
    C.green,
    "Редкость: "
      .. tostring(
        winner.category
      ),
    C.white,
    "Проверяю PIM...",
    C.yellow
  )

  if terminalRequestId then
    directTerminalSend(
      "ROUND_RESULT",
      terminalRequestId,
      tostring(player),
      tostring(winner.label),
      tostring(winnerQty),
      tostring(winner.category)
    )
  end

  sleepSafe(AFTER_WIN)

  gameBusy = false

  return true
end

terminalReplyCache = {}
terminalReplyOrder = {}
TERMINAL_REPLY_CACHE_MAX = 24

local function cacheTerminalReply(messageId, payload)
  messageId = tostring(messageId or "")
  if messageId == "" or type(payload) ~= "table" then
    return
  end

  if not terminalReplyCache[messageId] then
    terminalReplyOrder[#terminalReplyOrder + 1] = messageId
  end

  terminalReplyCache[messageId] = payload

  while #terminalReplyOrder > TERMINAL_REPLY_CACHE_MAX do
    local oldId = table.remove(terminalReplyOrder, 1)
    terminalReplyCache[oldId] = nil
  end
end

directTerminalSend = function(eventType, messageId, ...)
  local ok, result =
    pcall(
      component.invoke,
      CASINO_MODEM_ADDRESS,
      "send",
      TERMINAL_MODEM_ADDRESS,
      TERMINAL_PORT,
      TERMINAL_PROTOCOL,
      TERMINAL_SECRET,
      tostring(eventType or ""),
      tostring(messageId or ""),
      ...
    )

  return ok and result ~= false
end

local function replyAndCache(eventType, messageId, ...)
  local payload = {
    tostring(eventType or ""),
    tostring(messageId or ""),
    ...
  }

  cacheTerminalReply(messageId, payload)

  return directTerminalSend(
    unpackArgs(payload)
  )
end

local function resendCachedReply(messageId)
  local payload =
    terminalReplyCache[
      tostring(messageId or "")
    ]

  if type(payload) ~= "table" then
    return false
  end

  directTerminalSend(
    unpackArgs(payload)
  )

  return true
end

local function handleCasinoWirelessDirect(ev)
  if not TERMINAL_ENABLED
    or type(ev) ~= "table"
    or ev[1] ~= "modem_message"
  then
    return false
  end

  local receiver =
    tostring(ev[2] or "")
  local sender =
    tostring(ev[3] or "")
  local port =
    tonumber(ev[4])
  local protocol =
    tostring(ev[6] or "")
  local secret =
    tostring(ev[7] or "")
  local kind =
    tostring(ev[8] or "")
  local messageId =
    tostring(ev[9] or "")

  local trusted =
    receiver == CASINO_MODEM_ADDRESS
    and sender == TERMINAL_MODEM_ADDRESS
    and port == TERMINAL_PORT
    and protocol == TERMINAL_PROTOCOL
    and secret == TERMINAL_SECRET
    and messageId ~= ""

  if not trusted then
    return false
  end

  wirelessDiag.lastTerminalRxAt =
    computer.uptime()
  wirelessDiag.lastTerminalRxType =
    kind
  wirelessDiag.lastTerminalSender =
    sender

  if kind == "STATUS_REQUEST" then
    local player =
      getPlayerOnPim()

    local money =
      player
      and scanPlayerBetMoney()
      or 0

    local statusOk =
      directTerminalSend(
        "STATUS_RESPONSE",
        messageId,
        tostring(player or ""),
        tostring(money),
        tostring(BET_AMOUNT),
        casinoTerminalStatePack()
      )

    wirelessDiag.lastStatusTxOk =
      statusOk == true

    wirelessDiag.lastStatusTxResult =
      statusOk
      and "true"
      or "false"

    return true
  end

  if kind ~= "BET_REQUEST" then
    return true
  end

  local touchPlayer =
    tostring(ev[10] or "")

  if resendCachedReply(messageId) then
    return true
  end

  if casinoStockClosed() then
    replyAndCache(
      "BET_RESPONSE",
      messageId,
      "CASINO_CLOSED_STOCK",
      tostring(
        getPlayerOnPim()
        or ""
      ),
      tostring(
        scanPlayerBetMoney()
      ),
      tostring(
        BET_AMOUNT
      )
    )

    return true
  end

  if gameBusy then
    replyAndCache(
      "BET_RESPONSE",
      messageId,
      "CASINO_BUSY",
      "",
      "0",
      tostring(BET_AMOUNT)
    )
    return true
  end

  local player =
    getPlayerOnPim()

  if not player then
    replyAndCache(
      "BET_RESPONSE",
      messageId,
      "NO_PLAYER",
      "",
      "0",
      tostring(BET_AMOUNT)
    )
    return true
  end

  local normalizedTouch =
    string.lower(
      tostring(touchPlayer or "")
    )

  local normalizedPim =
    string.lower(
      tostring(player or "")
    )

  if normalizedTouch == ""
    or normalizedTouch ~= normalizedPim
  then
    replyAndCache(
      "BET_RESPONSE",
      messageId,
      "NOT_PIM_OWNER",
      tostring(player),
      tostring(scanPlayerBetMoney()),
      tostring(BET_AMOUNT)
    )
    return true
  end

  local moneyBefore =
    scanPlayerBetMoney()

  if moneyBefore < BET_AMOUNT then
    replyAndCache(
      "BET_RESPONSE",
      messageId,
      "NOT_ENOUGH_MONEY",
      tostring(player),
      tostring(moneyBefore),
      tostring(BET_AMOUNT)
    )
    return true
  end

  local playerBeforePay =
    getPlayerOnPim()

  if playerBeforePay
    ~= tostring(player)
  then
    replyAndCache(
      "BET_RESPONSE",
      messageId,
      "PLAYER_CHANGED",
      "",
      tostring(moneyBefore),
      tostring(BET_AMOUNT)
    )
    return true
  end

  if string.lower(tostring(playerBeforePay or ""))
    ~= string.lower(tostring(touchPlayer or ""))
  then
    replyAndCache(
      "BET_RESPONSE",
      messageId,
      "NOT_PIM_OWNER",
      tostring(playerBeforePay or ""),
      tostring(moneyBefore),
      tostring(BET_AMOUNT)
    )
    return true
  end

  local paid,
    moved,
    payCode =
      takeBetFromPlayer()

  if not paid then
    replyAndCache(
      "BET_RESPONSE",
      messageId,
      tostring(
        payCode
        or "PAYMENT_FAILED"
      ),
      tostring(player),
      tostring(moved or 0),
      tostring(BET_AMOUNT)
    )
    return true
  end

  local spinInfo =
    casinoHouseRecordPaidSpin(
      player,
      moved
    )

  replyAndCache(
    "BET_RESPONSE",
    messageId,
    "BET_ACCEPTED",
    tostring(player),
    tostring(
      math.max(
        0,
        moneyBefore - BET_AMOUNT
      )
    ),
    tostring(BET_AMOUNT)
  )

  startGameFor(
    player,
    messageId,
    spinInfo
  )

  return true
end

casinoWirelessDispatch =
  handleCasinoWirelessDirect

local terminalHeartbeatAt = 0

local function sendTerminalHeartbeat()
  if not TERMINAL_ENABLED then
    return
  end

  local now =
    computer.uptime()

  if now < terminalHeartbeatAt then
    return
  end

  terminalHeartbeatAt =
    now + 0.50

  local player =
    getPlayerOnPim()

  local money =
    player
    and scanPlayerBetMoney()
    or 0

  local statusOk =
    directTerminalSend(
      "STATUS_PUSH",
      tostring(
        math.floor(
          now * 1000
        )
      ),
      tostring(player or ""),
      tostring(money),
      tostring(BET_AMOUNT),
      casinoTerminalStatePack()
    )

  wirelessDiag.lastStatusTxOk =
    statusOk == true

  wirelessDiag.lastStatusTxResult =
    statusOk
    and "true"
    or "false"
end

local function handleClearWinnerTouch(ev)
  if not CLEAR_WINNER_ENABLED
    or type(ev) ~= "table"
    or ev[1] ~= "touch"
  then
    return false
  end

  local x =
    tonumber(ev[3])

  local y =
    tonumber(ev[4])

  if not x or not y then
    return false
  end

  local buttonX =
    getClearWinnerButtonX()

  local buttonW =
    unicode.len(
      CLEAR_WINNER_LABEL
    )

  if y ~= getClearWinnerButtonY()
    or x < buttonX
    or x >= buttonX + buttonW
  then
    return false
  end

  local ok, info =
    sendClearWinnerToBoard()

  if ok then
    drawStatus(
      "ПОБЕДИТЕЛЬ СТЁРТ",
      C.green,
      "Верхнее JACKPOT-табло очищено",
      C.white
    )
  else
    drawStatus(
      "ОШИБКА ОЧИСТКИ ТАБЛО",
      C.red,
      tostring(info or "unknown"),
      C.yellow
    )
  end

  if CLEAR_WINNER_HOLD > 0 then
    sleepSafe(
      CLEAR_WINNER_HOLD
    )
  end

  lastUiKey = nil

  return true
end


SystemAdmin = nil

function initSystemAdmin()
  local loader, err =
    loadfile(
      "/home/casino_system.lua"
    )

  if not loader then
    return false, err
  end

  local okModule, module =
    pcall(loader)

  if not okModule
    or type(module) ~= "table"
    or type(module.new) ~= "function"
  then
    return false,
      module
      or "Некорректный casino_system.lua"
  end

  local okAdmin, admin =
    pcall(
      module.new,
      {
        W = W,
        H = H,
        C = C,

        text = text,
        fill = fill,
        center = center,
        drawPanel = drawPanel,
        drawBase = drawBase,

        configPath =
          "/home/casino_config.lua",

        prizePath =
          PRIZE_CONFIG_PATH,

        statsPath =
          CasinoHouse.statsFile,

        staffItemId =
          CasinoHouse.staffItemId,

        powerSealItemId =
          CasinoHouse.powerSealItemId,

        getStats = function()
          return CasinoHouse.stats
        end,

        getCycle = function()
          return tonumber(
            CasinoHouse.stats.specialCycleSpins
          ) or 0
        end,

        getStaffClaimed = function()
          return CasinoHouse.stats.staffClaimedThisCycle
            == true
        end,

        getPowerSealClaimed = function()
          return CasinoHouse.stats.powerSealClaimedThisCycle
            == true
        end,

        getStaffLimit = function()
          return CasinoHouse.staffEvery
        end,

        getPowerSealCycle = function()
          return tonumber(
            CasinoHouse.stats.specialCycleSpins
          ) or 0
        end,

        getPowerSealLimit = function()
          return CasinoHouse.powerSealEvery
        end,

        setPowerSealLimit = function(value)
          local limit =
            math.max(
              1,
              math.min(
                1000000,
                math.floor(
                  tonumber(value)
                  or CasinoHouse.powerSealEvery
                )
              )
            )

          CasinoHouse.powerSealEvery = limit
          CasinoHouse.stats.powerSealEvery =
            limit

          casinoHouseSaveStats()
          return limit
        end,

        setStaffLimit = function(value)
          local limit =
            math.max(
              1,
              math.min(
                1000000,
                math.floor(
                  tonumber(value)
                  or CasinoHouse.staffEvery
                )
              )
            )

          CasinoHouse.staffEvery = limit
          CasinoHouse.stats.staffEvery =
            limit

          casinoHouseSaveStats()
          return limit
        end,

        getRuntimeTuning = function()
          return {
            spinDuration =
              RuntimeTuning.spinDuration,

            spinDelay =
              RuntimeTuning.spinDelay,

            idleStepInterval =
              RuntimeTuning.idleStepInterval,

            idleLongPause =
              RuntimeTuning.idleLongPause,

            idlePauseEvery =
              RuntimeTuning.idlePauseEvery
          }
        end,

        applyRuntimeTuning =
          applyRuntimeTuning,

        setModal = function(open)
          CasinoHouse.statusPopupOpen =
            open == true

          CasinoHouse.statusPopupDirty =
            false

          lastUiKey = nil
        end
      }
    )

  if not okAdmin
    or type(admin) ~= "table"
  then
    return false, admin
  end

  SystemAdmin = admin
  return true
end

initSystemAdmin()

drawBase()

drawStatus(
  "КАТАЛОГ ЗАГРУЖЕН",
  C.green,
  "Призов: "
    .. tostring(#PRIZES)
    .. " • Шанс: 100%",
  C.white,
  "RNG: "
    .. getRngMode(),
  C.cyan,
  jackpotModem
    and "Локально • JACKPOT-табло ONLINE"
    or "Локально • JACKPOT-табло OFFLINE",
  jackpotModem
    and C.green
    or C.yellow
)

sleepSafe(STARTUP_PAUSE)

local hardwareOk, hardwareErr =
  validateHardware()

if not hardwareOk then
  drawStatus(
    "ОШИБКА ОБОРУДОВАНИЯ",
    C.red,
    tostring(hardwareErr),
    C.yellow
  )

  while not quitRequested do
    sendTerminalHeartbeat()

    local ev =
      safeEventPull(HARDWARE_ERROR_POLL)

    if type(casinoWirelessDispatch)
      == "function"
    then
      casinoWirelessDispatch(ev)
    end

    checkQuitEvent(ev)
  end

  clearSelectors()

  return
end

pendingPrizes, pendingSeq =
  loadPending()

normalizeLoadedPending()
resetIdleShowcase()

CasinoStock.initialized = false
CasinoStock.closed = false
CasinoStock.nextCheckAt =
  computer.uptime() + 0.50

local lastKnownBetCount = 0
while not quitRequested do

  sendTerminalHeartbeat()

  local currentPlayer =
    getPlayerOnPim()

  local now =
    computer.uptime()

  local betCount =
    currentPlayer
    and scanPlayerBetMoney()
    or 0

  lastKnownBetCount =
    betCount
  if casinoStockClosed() then
    stopIdleShowcase()
    clearSelectors()

  elseif PendingViewer.open then
    stopIdleShowcase()

  elseif not gameBusy
    and not currentPlayer
  then
    tickIdleShowcase(now)

  else
    stopIdleShowcase()
  end

  if casinoStockClosed()
    and not PendingViewer.open
    and not CasinoHouse.statusPopupOpen
  then
    drawCasinoStockClosed()

  elseif not gameBusy
    and not PendingViewer.open
    and not CasinoHouse.statusPopupOpen
  then
    local ownPending =
      currentPlayer
      and findPendingForPlayer(
        currentPlayer
      )
      or nil

    updateWaitingUi(
      currentPlayer,
      betCount
    )


  end

  if CasinoHouse.statusPopupOpen
    and CasinoHouse.statusPopupDirty
  then
    drawHiddenStatusPopup()
  end

  local ev =
    safeEventPull(EVENT_POLL)

  if handleHiddenStatusTouch(ev) then

  elseif PendingViewer.handleViewerTouch(ev) then

  elseif PendingViewer.handleButtonTouch(ev) then

  elseif handleCasinoWirelessDirect(ev) then

  elseif handleClearWinnerTouch(ev) then

  else
    checkQuitEvent(ev)
  end

  if not quitRequested then
    tickPendingDelivery(
      getPlayerOnPim()
    )
  end

  sendTerminalHeartbeat()

  casinoStockTick(
    computer.uptime()
  )

  sendTerminalHeartbeat()

  if PendingViewer.refreshRequested
    and not PendingViewer.open
    and not gameBusy
    and not CasinoHouse.statusPopupOpen
  then
    PendingViewer.refreshRequested = false
    lastUiKey = nil

    local refreshPlayer =
      getPlayerOnPim()

    local refreshBetCount =
      refreshPlayer
      and scanPlayerBetMoney()
      or 0

    updateWaitingUi(
      refreshPlayer,
      refreshBetCount
    )
  end
end

fill(1, 1, W, H, C.bg)
drawFrame()
drawBottomFooter(nil)

center(
  math.floor(H / 2) - 3,
  "VIP-CASINO ОСТАНОВЛЕН",
  C.gray
)

local pendingCount =
  countPendingTotal()

if pendingCount > 0 then
  center(
    math.floor(H / 2),
    "ОЖИДАЮЩИХ ПРИЗОВ: "
      .. tostring(pendingCount),
    C.gold
  )

  center(
    math.floor(H / 2) + 2,
    "Они сохранены и будут выданы владельцам при возвращении",
    C.white
  )
else
  clearSelectors()

  center(
    math.floor(H / 2),
    "Ожидающих призов нет",
    C.darkGray
  )
end

center(
  H - 2,
  "SYSTEM HALTED",
  C.darkGray
)
