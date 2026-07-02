local shell = require("shell")
local event = require("event")

print("")
print("═══════════════════════════════════════════")
print("🚀 ЗАПУСК PIM MARKET СИСТЕМЫ")
print("═══════════════════════════════════════════")
print("")

print("📡 Запуск pimserver.lua...")
shell.execute("lua /home/pimserver.lua &")

os.sleep(3)

print("🤖 Запуск telegram_bot.lua...")
shell.execute("lua /home/telegram_bot.lua &")

print("🌐 Запуск web_admin.lua...")
shell.execute("lua /home/web_admin.lua &")

print("")
print("✅ Все сервисы запущены!")
print("")
print("📱 Для управления через Telegram:")
print("   Напишите /start боту")
print("")
print("🌐 Для доступа через веб:")
print("   http://localhost:8080")
print("")
print("💡 Для остановки всех скриптов:")
print("   Используйте Ctrl+C или перезагрузите компьютер")
print("")
print("═══════════════════════════════════════════")
print("")

-- Оставляем скрипт запущенным
while true do
    event.pull(0.5)
end
