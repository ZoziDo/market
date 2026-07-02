-- Веб-админка для PIM Market Server
local component = require("component")
local event = require("event")
local filesystem = require("filesystem")
local serialization = require("serialization")
local computer = require("computer")

local modem = component.modem
local PORT = 8080

-- АДРЕС ТВОЕГО PIMSERVER (ЗАМЕНИ НА СВОЙ!)
-- Узнай командой: lua -e 'local m=require("component").modem; print(m.address)'
local SERVER_ADDRESS = "2a904dc5-cbac-47de-be90-6f407fa91ecc"

print("")
print("═══════════════════════════════════════════")
print("🌐 ВЕБ-АДМИНКА PIM MARKET")
print("═══════════════════════════════════════════")
print("")
print("🔍 Сервер ищет pimserver по адресу: " .. SERVER_ADDRESS)
print("📡 Мой адрес модема: " .. modem.address)
print("")

-- Чтение HTML файла
local function readHTML()
    local path = "/home/web/static/index.html"
    if filesystem.exists(path) then
        local file = io.open(path, "r")
        if file then
            local content = file:read("*a")
            file:close()
            print("📄 index.html загружен, размер: " .. #content .. " байт")
            return content
        end
    end
    print("❌ index.html не найден по пути: " .. path)
    return nil
end

-- Отправка команды на сервер
local function sendCommand(command, data, callback)
    local msg = {
        op = "web_command",
        command = command,
        admin_name = "ZoziDo"
    }
    
    -- Добавляем данные
    for k, v in pairs(data or {}) do
        msg[k] = v
    end
    
    print("📤 Отправка команды: " .. command .. " на " .. SERVER_ADDRESS)
    
    -- Отправляем на сервер
    modem.send(SERVER_ADDRESS, 0xffef, serialization.serialize(msg))
    
    -- Ждем ответ
    local timeout = os.clock() + 3
    while os.clock() < timeout do
        local ev = {event.pull(0.1)}
        if ev[1] == "modem_message" then
            local from = ev[3]
            local data = ev[6]
            local success, parsed = pcall(serialization.unserialize, data)
            if success and parsed and parsed.op == "web_response" then
                print("📥 Получен ответ от сервера")
                if callback then
                    callback(parsed)
                end
                return parsed
            end
        end
    end
    print("⏰ Таймаут: ответ не получен")
    return nil
end

-- HTTP парсер
local function parseRequest(data)
    local lines = {}
    for line in data:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    if #lines == 0 then return nil end
    
    local method, path, version = lines[1]:match("^(%S+) (%S+) HTTP/(%S+)")
    if not method then return nil end
    
    local headers = {}
    local body = ""
    local inBody = false
    
    for i = 2, #lines do
        if lines[i] == "" then
            inBody = true
        elseif not inBody then
            local key, value = lines[i]:match("^([^:]+):%s*(.*)$")
            if key then headers[key:lower()] = value end
        else
            body = body .. lines[i] .. "\n"
        end
    end
    
    local query = {}
    local pathWithoutQuery = path
    local qPos = path:find("?")
    if qPos then
        pathWithoutQuery = path:sub(1, qPos-1)
        local qStr = path:sub(qPos+1)
        for param in qStr:gmatch("[^&]+") do
            local key, value = param:match("^([^=]+)=(.*)$")
            if key then
                query[key] = value
            end
        end
    end
    
    return {
        method = method,
        path = pathWithoutQuery,
        version = version,
        headers = headers,
        body = body,
        query = query
    }
end

-- Отправка ответа
local function sendResponse(socket, status, headers, body)
    local response = "HTTP/1.1 " .. status .. "\r\n"
    headers["Content-Length"] = tostring(#body)
    headers["Connection"] = "close"
    headers["Access-Control-Allow-Origin"] = "*"
    for key, value in pairs(headers) do
        response = response .. key .. ": " .. value .. "\r\n"
    end
    response = response .. "\r\n" .. body
    socket.write(response)
    socket.close()
end

-- Обработка API запросов
local function handleAPI(socket, request)
    local path = request.path
    local body = request.body ~= "" and serialization.unserialize(request.body) or {}
    
    print("📨 API запрос: " .. path)
    
    -- GET /api/players
    if path == "/api/players" and request.method == "GET" then
        local response = sendCommand("get_players")
        if response then
            sendResponse(socket, "200 OK", {
                ["Content-Type"] = "application/json"
            }, serialization.serialize({
                players = response.players or {},
                admins = response.admins or {},
                total = response.total or 0
            }))
        else
            sendResponse(socket, "200 OK", {
                ["Content-Type"] = "application/json"
            }, serialization.serialize({players = {}, admins = {}, total = 0}))
        end
        
    -- POST /api/balance
    elseif path == "/api/balance" and request.method == "POST" then
        if body.name then
            local response = sendCommand("set_balance", {
                name = body.name,
                coin = body.coin,
                ema = body.ema
            })
            sendResponse(socket, "200 OK", {
                ["Content-Type"] = "application/json"
            }, serialization.serialize({success = response and response.success or false}))
        end
        
    -- POST /api/ban
    elseif path == "/api/ban" and request.method == "POST" then
        if body.name then
            local response = sendCommand("toggle_ban", {
                name = body.name
            })
            sendResponse(socket, "200 OK", {
                ["Content-Type"] = "application/json"
            }, serialization.serialize({
                success = response and response.success or false,
                banned = response and response.banned or false
            }))
        end
        
    -- POST /api/reset
    elseif path == "/api/reset" and request.method == "POST" then
        if body.name then
            local response = sendCommand("reset_player", {
                name = body.name
            })
            sendResponse(socket, "200 OK", {
                ["Content-Type"] = "application/json"
            }, serialization.serialize({success = response and response.success or false}))
        end
        
    -- POST /api/additem
    elseif path == "/api/additem" and request.method == "POST" then
        if body.internal and body.display then
            local response = sendCommand("add_item", {
                internal = body.internal,
                display = body.display,
                price_coin = body.price_coin or 0,
                price_ema = body.price_ema or 0,
                damage = body.damage or 0
            })
            sendResponse(socket, "200 OK", {
                ["Content-Type"] = "application/json"
            }, serialization.serialize({success = response and response.success or false}))
        end
        
    -- GET /api/admins
    elseif path == "/api/admins" and request.method == "GET" then
        local response = sendCommand("get_admins")
        sendResponse(socket, "200 OK", {
            ["Content-Type"] = "application/json"
        }, serialization.serialize({admins = response and response.admins or {}}))
        
    -- POST /api/addadmin
    elseif path == "/api/addadmin" and request.method == "POST" then
        if body.name then
            local response = sendCommand("add_admin", {
                name = body.name
            })
            sendResponse(socket, "200 OK", {
                ["Content-Type"] = "application/json"
            }, serialization.serialize({success = response and response.success or false}))
        end
        
    -- POST /api/removeadmin
    elseif path == "/api/removeadmin" and request.method == "POST" then
        if body.name then
            local response = sendCommand("remove_admin", {
                name = body.name
            })
            sendResponse(socket, "200 OK", {
                ["Content-Type"] = "application/json"
            }, serialization.serialize({success = response and response.success or false}))
        end
        
    -- GET /api/pause
    elseif path == "/api/pause" and request.method == "GET" then
        local response = sendCommand("toggle_pause")
        sendResponse(socket, "200 OK", {
            ["Content-Type"] = "application/json"
        }, serialization.serialize({
            success = response and response.success or false,
            paused = response and response.paused or false
        }))
        
    -- GET /api/stats
    elseif path == "/api/stats" and request.method == "GET" then
        local response = sendCommand("get_stats")
        if response then
            sendResponse(socket, "200 OK", {
                ["Content-Type"] = "application/json"
            }, serialization.serialize({
                totalPlayers = response.totalPlayers or 0,
                totalTransactions = response.totalTransactions or 0,
                bannedCount = response.bannedCount or 0,
                adminsCount = response.adminsCount or 0,
                shopPaused = response.shopPaused or false
            }))
        end
        
    -- GET /api/logs
    elseif path == "/api/logs" and request.method == "GET" then
        local response = sendCommand("get_logs")
        sendResponse(socket, "200 OK", {
            ["Content-Type"] = "application/json"
        }, serialization.serialize({logs = response and response.logs or {}}))
        
    else
        sendResponse(socket, "404 Not Found", {
            ["Content-Type"] = "text/plain"
        }, "404 Not Found")
    end
end

-- Запуск веб-сервера
modem.open(PORT)
print("✅ Веб-сервер запущен на порту " .. PORT)
print("📱 Для доступа с телефона:")

-- Получаем IP
local ip = "localhost"
if component.isAvailable("internet") then
    local success, host = pcall(function()
        return component.internet.getHostname()
    end)
    if success and host then
        ip = host
    end
end

print("   http://" .. ip .. ":" .. PORT)
print("   ИЛИ через ngrok")
print("")
print("🔐 Администратор: ZoziDo")
print("")
print("🔄 Сервер ожидает подключений...")
print("")

-- Основной цикл с защитой от ошибок
while true do
    local success, err = pcall(function()
        local ev = {event.pull(0.5)}
        if ev[1] == "modem_message" then
            local from = ev[3]
            local data = ev[6]
            
            if type(data) == "string" and data:match("^%a+ /") then
                local req = parseRequest(data)
                if req then
                    if req.path:match("^/api/") then
                        handleAPI(from, req)
                    else
                        local html = readHTML()
                        if html then
                            sendResponse(from, "200 OK", {
                                ["Content-Type"] = "text/html; charset=utf-8"
                            }, html)
                        else
                            sendResponse(from, "200 OK", {
                                ["Content-Type"] = "text/html; charset=utf-8"
                            }, "<html><body><h1>PIM Market</h1><p>Сервер работает!<br>Но index.html не найден.</p><p>Путь: /home/web/static/index.html</p></body></html>")
                        end
                    end
                end
            end
        end
    end)
    
    if not success then
        print("⚠️ Ошибка в цикле: " .. tostring(err))
        os.sleep(1)
    end
end
