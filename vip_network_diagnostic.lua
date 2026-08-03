local component = require("component")
local computer = require("computer")
local internet = require("internet")
local shellOk, shell = pcall(require, "shell")

local args = {...}
local playerName = tostring(args[1] or "ZoziDo")
local reportPath = "/home/vip_network_report.txt"

local report = {}

local function line(text)
  text = tostring(text or "")
  report[#report + 1] = text
  print(text)
end

local function saveReport()
  local file, err = io.open(reportPath, "w")
  if not file then
    print("Не удалось сохранить отчёт: " .. tostring(err))
    return false
  end

  file:write(table.concat(report, "\n"))
  file:write("\n")
  file:close()
  return true
end

local function parseHttpResponse(response)
  response = tostring(response or "")

  local statusCode = tonumber(
    response:match("^HTTP/%d%.%d%s+(%d+)")
    or response:match("^HTTP/%d%s+(%d+)")
    or "0"
  ) or 0

  local headers, body = response:match("^(.-)\r\n\r\n(.*)$")
  headers = headers or ""
  body = body or ""

  local location = headers:match("\r\n[Ll]ocation:%s*([^\r\n]+)")
    or headers:match("^[Ll]ocation:%s*([^\r\n]+)")

  local contentType = headers:match(
    "\r\n[Cc]ontent%-[Tt]ype:%s*([^\r\n]+)"
  ) or headers:match(
    "^[Cc]ontent%-[Tt]ype:%s*([^\r\n]+)"
  )

  return {
    status = statusCode,
    headers = headers,
    body = body,
    location = location,
    contentType = contentType,
  }
end

local function rawRequest(host, port, request, timeout)
  timeout = tonumber(timeout) or 8

  local startTime = computer.uptime()
  local okSocket, socketOrError = pcall(
    internet.socket,
    host,
    port
  )

  if not okSocket or not socketOrError then
    return nil,
      "internet.socket: "
      .. tostring(socketOrError or "nil")
  end

  local socket = socketOrError

  local okWrite, writeError = pcall(
    socket.write,
    socket,
    request
  )

  if not okWrite then
    pcall(socket.close, socket)
    return nil, "socket.write: " .. tostring(writeError)
  end

  local response = ""

  while true do
    if computer.uptime() - startTime > timeout then
      pcall(socket.close, socket)
      return nil,
        "таймаут " .. tostring(timeout)
        .. " сек.; получено байт: "
        .. tostring(#response)
    end

    local okRead, chunk = pcall(socket.read, socket)

    if not okRead then
      pcall(socket.close, socket)
      return nil, "socket.read: " .. tostring(chunk)
    end

    if chunk == nil then
      break
    end

    response = response .. chunk

    if #response > 2 * 1024 * 1024 then
      pcall(socket.close, socket)
      return nil, "ответ больше 2 МБ"
    end
  end

  pcall(socket.close, socket)

  return parseHttpResponse(response), nil
end

local function get(host, port, path, timeout)
  local request =
    "GET " .. path .. " HTTP/1.1\r\n"
    .. "Host: " .. host .. "\r\n"
    .. "Connection: close\r\n"
    .. "User-Agent: OpenComputers-VIP-Diagnostic/1.0\r\n"
    .. "Accept: */*\r\n\r\n"

  return rawRequest(host, port, request, timeout)
end

local function postJson(host, port, path, jsonBody, timeout)
  local request =
    "POST " .. path .. " HTTP/1.1\r\n"
    .. "Host: " .. host .. "\r\n"
    .. "Connection: close\r\n"
    .. "User-Agent: OpenComputers-VIP-Diagnostic/1.0\r\n"
    .. "Content-Type: application/json\r\n"
    .. "Content-Length: " .. tostring(#jsonBody) .. "\r\n\r\n"
    .. jsonBody

  return rawRequest(host, port, request, timeout)
end

local function printResult(name, result, err)
  line("")
  line("============================================================")
  line(name)
  line("============================================================")

  if not result then
    line("РЕЗУЛЬТАТ: ОШИБКА")
    line("Причина: " .. tostring(err))
    return false
  end

  line("РЕЗУЛЬТАТ: СОЕДИНЕНИЕ ЕСТЬ")
  line("HTTP-код: " .. tostring(result.status))
  line("Тип ответа: " .. tostring(result.contentType or "-"))
  line("Размер тела: " .. tostring(#result.body) .. " байт")

  if result.location then
    line("Перенаправление Location: " .. tostring(result.location))
  end

  local preview = result.body
    :gsub("\r", " ")
    :gsub("\n", " ")
    :sub(1, 300)

  line("Начало ответа:")
  line(preview ~= "" and preview or "<пусто>")

  if result.status >= 200 and result.status < 300 then
    line("ОЦЕНКА: OK")
    return true
  elseif result.status == 301
      or result.status == 302
      or result.status == 307
      or result.status == 308 then
    line("ОЦЕНКА: REDIRECT. OpenComputers-код магазина его не обрабатывает.")
  elseif result.status == 0 then
    line("ОЦЕНКА: сервер не вернул корректный HTTP-заголовок.")
  else
    line("ОЦЕНКА: сервер ответил ошибкой HTTP.")
  end

  return false
end

line("VIP-SHOP NETWORK DIAGNOSTIC")
line("Игрок для теста: " .. playerName)
line("Время uptime: " .. tostring(computer.uptime()))
line("Отчёт: " .. reportPath)
line("")

if not component.isAvailable("internet") then
  line("КРИТИЧЕСКАЯ ОШИБКА: компонент internet не найден.")
  saveReport()
  return
end

line("Интернет-карта: найдена")

-- 1. Файл программы на TimeWeb.
local hostShop, hostShopErr = get(
  "co925228.tw1.ru",
  80,
  "/shop.lua",
  10
)
printResult(
  "ТЕСТ 1: TimeWeb HTTP /shop.lua",
  hostShop,
  hostShopErr
)

-- 2. Простой JSON на TimeWeb.
local hostConfig, hostConfigErr = get(
  "co925228.tw1.ru",
  80,
  "/data/config.json",
  8
)
printResult(
  "ТЕСТ 2: TimeWeb HTTP /data/config.json",
  hostConfig,
  hostConfigErr
)

-- 3. Каталог VPS.
local vpsCatalog, vpsCatalogErr = get(
  "201.24.112.170",
  8080,
  "/data/catalog.json",
  8
)
printResult(
  "ТЕСТ 3: VPS 201.24.112.170:8080 /data/catalog.json",
  vpsCatalog,
  vpsCatalogErr
)

-- 4. Основная команда авторизации магазина.
local safePlayerName = playerName
  :gsub("\\", "\\\\")
  :gsub('"', '\\"')

local sessionBody =
  '{"action":"session_status","name":"'
  .. safePlayerName
  .. '"}'

local vpsStatus, vpsStatusErr = postJson(
  "201.24.112.170",
  8080,
  "/api",
  sessionBody,
  8
)
printResult(
  "ТЕСТ 4: VPS POST /api session_status",
  vpsStatus,
  vpsStatusErr
)

-- 5. Просто TCP до GitHub: подтверждает, что доступ к стандартному 443 есть.
local githubStart = computer.uptime()
local githubOk, githubSocket = pcall(
  internet.socket,
  "raw.githubusercontent.com",
  443
)

line("")
line("============================================================")
line("ТЕСТ 5: TCP raw.githubusercontent.com:443")
line("============================================================")

if githubOk and githubSocket then
  line("РЕЗУЛЬТАТ: TCP-соединение создано")
  line(
    "Время: "
    .. tostring(
      math.floor(
        (computer.uptime() - githubStart) * 1000
      )
    )
    .. " мс"
  )
  pcall(githubSocket.close, githubSocket)
else
  line("РЕЗУЛЬТАТ: ОШИБКА")
  line("Причина: " .. tostring(githubSocket))
end

line("")
line("============================================================")
line("КАК ЧИТАТЬ РЕЗУЛЬТАТ")
line("============================================================")
line("TimeWeb 301/302: используй HTTPS для wget; прямой HTTP перенаправляется.")
line("TimeWeb socket error: DNS/домен заблокирован или недоступен с Realm.")
line("VPS socket error: порт 8080 закрыт, server.php не запущен или Realm блокирует 8080.")
line("VPS GET работает, POST не работает: ошибка server.php/API.")
line("POST status=ok: VPS и авторизация работают; тогда искать ошибку PIM/сессии.")
line("GitHub:443 работает, а VPS:8080 нет: наиболее вероятно блокируется нестандартный порт 8080.")

line("")
if saveReport() then
  line("ГОТОВО. Отчёт сохранён: " .. reportPath)
else
  line("Отчёт вывести на экран удалось, сохранить — нет.")
end
