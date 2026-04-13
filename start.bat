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

:: ── 2. Servidor relay (solo necesario si usas LuaSocket en Lua) ──
echo  [2/2] Iniciando servidor relay (puerto 12345)...
start "myTraductor Relay" cmd /k "cd /d %~dp0server && python translator_server.py"

:: ── 3. AutoHotkey (traduccion via teclado, sin LuaSocket) ────────
echo  [3/3] Iniciando AutoHotkey como Administrador...
where autohotkey >nul 2>&1
if %errorlevel% == 0 (
    :: Lanzar elevado para poder interceptar input de WoW (que corre como Admin)
    powershell -Command "Start-Process autohotkey -ArgumentList '\"%~dp0myTraductor.ahk\"' -Verb RunAs"
    echo         AutoHotkey iniciado (elevado). Usa F12 en WoW para traducir.
) else (
    echo         AutoHotkey no encontrado. Descargalo de https://www.autohotkey.com
    echo         o ejecuta myTraductor.ahk manualmente con clic derecho -> Ejecutar como administrador.
)

echo.
echo  Listos. Abre WoW y usa F12 para traducir.
echo.
pause
