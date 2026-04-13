@echo off
title myTraductor — Servidores de traduccion

echo.
echo  =============================================
echo   myTraductor — Iniciando servidores
echo  =============================================
echo.

:: ── 1. LibreTranslate ────────────────────────────────────────────
echo  [1/2] Iniciando LibreTranslate (puerto 5000)...
start "LibreTranslate" cmd /k "libretranslate --host 127.0.0.1 --port 5000 --load-only en,es"

:: Esperar a que LibreTranslate levante antes de arrancar el relay
echo  Esperando que LibreTranslate este listo...
timeout /t 8 /nobreak >nul

:: ── 2. Servidor relay ─────────────────────────────────────────────
echo  [2/2] Iniciando servidor relay (puerto 12345)...
start "myTraductor Relay" cmd /k "cd /d %~dp0server && python translator_server.py"

echo.
echo  Ambos servidores iniciados.
echo  Puedes cerrar esta ventana y abrir WoW.
echo.
pause
