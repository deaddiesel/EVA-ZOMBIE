@echo off
cls
:: Включаем поддержку русского языка в консоли Windows
chcp 65001 > nul

echo [Ядро] Запуск Зомби Сервера в режиме глубокой трассировки (deep trace)...

:loop
:: Запуск игрового сервера с твоими параметрами
hlds.exe -console -game cstrike +ip 0.0.0.0 +port 27015 +maxplayers 32 +map de_dust2 -num_edicts 4096 -heapsize 262144 -noipx -nojoy -nosteam

echo [Ядро] Сервер упал или перезагрузился! Перезапуск через 5 секунд...
ping -n 5 127.0.0.1 > nul
goto loop